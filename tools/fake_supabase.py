#!/usr/bin/env python3
"""Tiny in-memory stand-in for the Doorgunner Supabase backend (server/README.md), for tests/online_test.gd.

    python tools/fake_supabase.py [port]      (default 18765)

Auth (signup, refresh), the RPCs register_player / rename_player / set_avatar / delete_me / upsert_run and the
leaderboard views, with the same error codes. Test controls: POST /_test {"expire": true} invalidates all access tokens,
{"down": true} answers every request with 503, {"max_day": n} makes upsert_run answer `implausible` above day n;
GET /_test returns {"players": ..., "runs": ...}. Not a security reference: it checks only what the client needs.
"""
import base64
import json
import re
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

S = {"access": {}, "refresh": {}, "players": {}, "runs": {}, "n": 0, "down": False, "max_day": 100000,
     "errors": {}, "err_rate": {}, "err_limit": 20}
VIEWS = {"leaderboard_points": "points", "leaderboard_days": "day", "leaderboard_rescued": "rescued", "leaderboard_kills": "kills"}


def tokens(uid):
    S["n"] += 1
    a, r = "at-%d" % S["n"], "rt-%d" % S["n"]
    S["access"][a] = uid
    S["refresh"][r] = uid
    return {"access_token": a, "refresh_token": r, "expires_in": 3600, "expires_at": int(time.time()) + 3600,
            "token_type": "bearer", "user": {"id": uid, "is_anonymous": True}}


def points(r):
    return r["day"] * 100 + r["rescued"] * 25 + r["kills"] + (5000 if r["victory"] else 0)  # run_points, server/supabase/007_balance.sql


class Err(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status


def player(uid):
    p = S["players"].get(uid)
    if p is None:
        raise Err("no_player")
    return p


def register_player(uid, b):
    if uid in S["players"]:
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


def rename_player(uid, b):
    p = player(uid)
    n = str(b.get("p_name", ""))
    if not re.fullmatch(r"[A-Za-z0-9_-]( ?[A-Za-z0-9_-]){2,15}", n):
        raise Err("name_invalid")
    if any(q["name"].lower() == n.lower() and q["id"] != uid for q in S["players"].values()):
        raise Err("name_taken")
    p["name"] = n
    return p


def set_avatar(uid, b):
    p = player(uid)
    if not 0 <= b.get("p_avatar", -1) <= 11:
        raise Err("avatar_invalid")
    p["avatar"] = b["p_avatar"]
    return p


def delete_me(uid, b):
    S["players"].pop(player(uid)["id"])
    for k in [k for k, r in S["runs"].items() if r["player_id"] == uid]:
        S["runs"].pop(k)
    S["access"] = {k: v for k, v in S["access"].items() if v != uid}
    S["refresh"] = {k: v for k, v in S["refresh"].items() if v != uid}
    for e in S["errors"].values():
        if e["player_id"] == uid:
            e["player_id"] = None
    return None


def upsert_run(uid, b):
    player(uid)
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
    if r["ended"]:  # 009 trigger runs_ended_drop_cloud_save: an ended run's cloud copy goes too
        SAVES.pop((uid, "run"), None)
    r["version"] = b.get("p_version")
    r["points"] = points(r)
    return r["points"]


def report_error(uid, b):  # callable without a sign-in (uid None), like 008_errors.sql; err_limit = per-player calls, anon 200
    msg = str(b.get("p_message") or "")[:500]
    if not msg.strip():
        raise Err("error_invalid")
    bucket = uid or "anon"
    if S["err_rate"].get(bucket, 0) >= (S["err_limit"] if uid else 200):
        raise Err("rate_limit")
    S["err_rate"][bucket] = S["err_rate"].get(bucket, 0) + 1
    ver = str(b.get("p_version") or "")[:32]
    e = S["errors"].get((ver, msg))
    if e:
        e["count"] += 1
    else:
        S["errors"][(ver, msg)] = {"player_id": uid, "version": ver, "platform": str(b.get("p_platform") or "")[:32],
                                   "message": msg, "stack": str(b.get("p_stack") or "")[:4000], "count": 1}


SAVES = {}  # (player id, slot) -> {updated_at, version, format, data (base64 text)}; unreachable once delete_me removed the player (FK cascade in 009)


def put_save(uid, b):  # server/supabase/009_cloud_save.sql
    player(uid)
    if b.get("p_slot") not in ("run", "daily"):
        raise Err("slot_invalid")
    d = b.get("p_data")
    if not isinstance(d, str) or not d or not isinstance(b.get("p_format"), int) or b["p_format"] < 0:
        raise Err("save_invalid")
    if len(d) > 2097152 * 4 // 3 + 16:
        raise Err("save_too_large")
    try:
        raw = base64.b64decode(d, validate=True)
    except Exception:
        raise Err("save_invalid")
    if len(raw) > 2097152:
        raise Err("save_too_large")
    SAVES[(uid, b["p_slot"])] = {"updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "version": str(b.get("p_version", ""))[:32],
                                 "format": b["p_format"], "data": d}
    return SAVES[(uid, b["p_slot"])]["updated_at"]


def get_save(uid, b):
    s = SAVES.get((uid, b.get("p_slot"))) if uid in S["players"] else None
    if s is None:
        return None
    return {k: v for k, v in s.items() if k != "data" or not b.get("p_meta_only")}


def delete_save(uid, b):
    SAVES.pop((uid, b.get("p_slot")), None)
    return None


# One function per RPC: fn(uid, body) -> JSON result, raise Err(code) like the SQL. Packages append their own
# function above and ONE line here (call player(uid) first if the RPC needs a registered player).
RPCS = {
    "register_player": register_player,
    "rename_player": rename_player,
    "set_avatar": set_avatar,
    "delete_me": delete_me,
    "upsert_run": upsert_run,
    "report_error": report_error,
    "put_save": put_save,
    "get_save": get_save,
    "delete_save": delete_save,
}


def rpc(name, uid, b):
    if uid is None and name != "report_error":
        raise Err("permission denied", 401)
    if name not in RPCS:
        raise Err("unknown rpc", 404)
    return RPCS[name](uid, b)


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
                    S["err_limit"] = b.get("err_limit", S["err_limit"])
                return self.reply(200, {"players": S["players"], "runs": S["runs"], "errors": list(S["errors"].values())})
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
