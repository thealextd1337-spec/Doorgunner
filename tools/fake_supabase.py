#!/usr/bin/env python3
"""Tiny in-memory stand-in for the Doorgunner Supabase backend (server/README.md), for tests/online_test.gd.

    python tools/fake_supabase.py [port]      (default 18765)

Auth (signup, refresh), the RPCs register_player / rename_player / set_avatar / delete_me / upsert_run and the
leaderboard views, with the same error codes. Test controls: POST /_test {"expire": true} invalidates all access tokens,
{"down": true} answers every request with 503, {"max_day": n} makes upsert_run answer `implausible` above day n;
GET /_test returns {"players": ..., "runs": ...}. Not a security reference: it checks only what the client needs.
"""
import json
import re
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

S = {"access": {}, "refresh": {}, "players": {}, "runs": {}, "n": 0, "down": False, "max_day": 100000}
VIEWS = {"leaderboard_points": "points", "leaderboard_days": "day", "leaderboard_rescued": "rescued", "leaderboard_kills": "kills"}


def tokens(uid):
    S["n"] += 1
    a, r = "at-%d" % S["n"], "rt-%d" % S["n"]
    S["access"][a] = uid
    S["refresh"][r] = uid
    return {"access_token": a, "refresh_token": r, "expires_in": 3600, "expires_at": int(time.time()) + 3600,
            "token_type": "bearer", "user": {"id": uid, "is_anonymous": True}}


def points(r):
    return r["day"] * 100 + r["rescued"] * 25 + r["kills"] + (2000 if r["victory"] else 0)


class Err(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status


def rpc(name, uid, b):
    if uid is None:
        raise Err("permission denied", 401)
    p = S["players"].get(uid)
    if name == "register_player":
        if p:
            raise Err("already_registered")
        n = str(b.get("p_name", ""))
        if not re.fullmatch(r"[A-Za-z0-9_-]( ?[A-Za-z0-9_-]){2,15}", n) or len(n) > 16:
            raise Err("name_invalid")
        if "badword" in n.lower():
            raise Err("name_banned")
        if any(q["name"].lower() == n.lower() for q in S["players"].values()):
            raise Err("name_taken")
        if not 0 <= b.get("p_avatar", -1) <= 11:
            raise Err("avatar_invalid")
        S["players"][uid] = {"id": uid, "name": n, "avatar": b["p_avatar"]}
        return S["players"][uid]
    if p is None:
        raise Err("no_player")
    if name == "rename_player":
        n = str(b.get("p_name", ""))
        if not re.fullmatch(r"[A-Za-z0-9_-]( ?[A-Za-z0-9_-]){2,15}", n):
            raise Err("name_invalid")
        if any(q["name"].lower() == n.lower() and q["id"] != uid for q in S["players"].values()):
            raise Err("name_taken")
        p["name"] = n
        return p
    if name == "set_avatar":
        if not 0 <= b.get("p_avatar", -1) <= 11:
            raise Err("avatar_invalid")
        p["avatar"] = b["p_avatar"]
        return p
    if name == "delete_me":
        S["players"].pop(uid)
        for k in [k for k, r in S["runs"].items() if r["player_id"] == uid]:
            S["runs"].pop(k)
        S["access"] = {k: v for k, v in S["access"].items() if v != uid}
        S["refresh"] = {k: v for k, v in S["refresh"].items() if v != uid}
        return None
    if name == "upsert_run":
        rid = b.get("p_run_id")
        if not rid or b.get("p_day", 0) < 1:
            raise Err("run_invalid")
        r = S["runs"].get(rid)
        if r and r["player_id"] != uid:
            raise Err("not_your_run")
        if r and r["ended"]:
            raise Err("run_ended")
        if b["p_day"] > S["max_day"]:
            raise Err("implausible")
        if not r:
            r = S["runs"][rid] = {"id": rid, "player_id": uid, "day": 1, "rescued": 0, "kills": 0, "victory": False,
                                  "modifiers": sorted(set(b.get("p_modifiers") or []))}
        r["day"], r["rescued"], r["kills"] = max(r["day"], b["p_day"]), max(r["rescued"], b["p_rescued"]), max(r["kills"], b["p_kills"])
        r["victory"] = r["victory"] or b["p_victory"]
        r["ended"] = b["p_ended"]
        r["version"] = b.get("p_version")
        r["points"] = points(r)
        return r["points"]
    raise Err("unknown rpc", 404)


def view(name, q):
    by = {}
    for r in S["runs"].values():
        p = S["players"].get(r["player_id"])
        if p:
            by.setdefault(p["id"], []).append(r)
    rows = []
    for pid, rs in by.items():
        p = S["players"][pid]
        row = {"player_id": pid, "name": p["name"], "avatar": p["avatar"]}
        if name == "best_run":
            b = max(rs, key=lambda r: r["points"])
            row.update(value=b["points"], day=b["day"], victory=b["victory"], modifiers=b["modifiers"])
        else:
            row["value"] = sum(r[VIEWS[name]] if VIEWS[name] != "points" else r["points"] for r in rs)
        rows.append(row)
    rows.sort(key=lambda r: -r["value"])
    for r in rows:
        r["rank"] = 1 + sum(1 for o in rows if o["value"] > r["value"])
    if "player_id" in q:
        rows = [r for r in rows if r["player_id"] == q["player_id"][0].removeprefix("eq.")]
    return rows[: int(q.get("limit", ["1000"])[0])]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self, method):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        n = int(self.headers.get("Content-Length") or 0)
        b = json.loads(self.rfile.read(n) or b"{}") if n else {}
        try:
            if u.path == "/_test":
                if method == "POST":
                    if b.get("expire"):
                        S["access"].clear()
                    S["down"] = b.get("down", S["down"])
                    S["max_day"] = b.get("max_day", S["max_day"])
                return self.reply(200, {"players": S["players"], "runs": S["runs"]})
            if S["down"]:
                return self.reply(503, {"message": "down"})
            if not self.headers.get("apikey"):
                return self.reply(401, {"message": "No API key found in request"})
            if u.path == "/auth/v1/signup":
                return self.reply(200, tokens(str(uuid.uuid4())))
            if u.path == "/auth/v1/token":
                uid = S["refresh"].pop(b.get("refresh_token"), None)
                if uid is None:
                    return self.reply(400, {"error": "invalid_grant", "error_description": "Invalid Refresh Token"})
                return self.reply(200, tokens(uid))
            bearer = self.headers.get("Authorization", "").removeprefix("Bearer ")
            uid = S["access"].get(bearer)
            if u.path.startswith("/rest/v1/rpc/"):
                if uid is None and bearer not in ("", self.headers.get("apikey")):
                    return self.reply(401, {"code": "PGRST301", "message": "JWT expired"})
                return self.reply(200, rpc(u.path.rsplit("/", 1)[1], uid, b))
            name = u.path.rsplit("/", 1)[1]
            if name in VIEWS or name == "best_run":
                return self.reply(200, view(name, q))
            if name == "modifiers":
                return self.reply(200, [])
            if name == "runs":
                if uid is None:
                    return self.reply(401, {"code": "PGRST301", "message": "JWT expired"})
                return self.reply(200, [r for r in S["runs"].values() if r["player_id"] == uid])
            self.reply(404, {"message": "not found"})
        except Err as e:
            self.reply(e.status, {"code": "P0001", "message": e.code})

    def do_GET(self):
        self.handle_any("GET")

    def do_POST(self):
        self.handle_any("POST")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 18765), H).serve_forever()
