extends Node
## Autoload "Online": Supabase client (server/README.md, docs/ROADMAP.md P6a): anonymous auth with refresh token, the
## player RPCs, run submission through an outbox and the leaderboards. HTTPRequest only, so it works on desktop and web.
## Tokens live in <profile>/auth.json, queued run updates in <profile>/outbox.json.
## Ranked runs: begin_run (main.gd, new run) sends the first upsert_run; if that fails the run is unranked for good
## (`ranked` false, saved with the run, never sent). A ranked run that loses the connection later keeps its updates in
## the outbox (one entry per run, values only grow) and sends them when the server answers again.
## One account operation at a time: register / rename / set_avatar / delete_me all answer on `done`.

signal done(ok: bool, error: String) ## register / rename / set_avatar / delete_me finished; error is a server code (ERRORS) or "offline"
signal board(rows: Array, own_row: Dictionary) ## rows: [{rank, player_id, name, avatar, value, (best_run: day, victory, modifiers)}]; own_row {} if unranked
signal board_failed(error: String)
signal player(stats: Dictionary) ## {player_id, name, avatar, points, points_rank, days, rescued, kills, best: {value, day, victory, modifiers}, runs, wins} (runs/wins -1 for other players)
signal player_failed(error: String)
signal online_changed(online: bool)

const ERRORS := {
	"offline": "No connection to the server.",
	"name_taken": "That name is already taken.",
	"name_invalid": "Names have 3-16 letters, digits, space, _ or -.",
	"name_banned": "That name is not allowed.",
	"avatar_invalid": "Pick one of the portraits.",
	"already_registered": "This profile is already registered online.",
	"no_player": "This profile is not registered online yet.",
	"auth_lost": "The online identity of this profile is gone (cleared browser data?).",
	"rate_limit": "Too many requests, try again in a minute.",
	"rate_limit_new_runs": "Too many new runs today.",
}
const NOTICE := "Offline - this run is not ranked"
const BOARDS := ["points", "days", "rescued", "kills", "best_run"]
const RETRY_SECONDS := 60.0 # outbox retry / reachability probe; the server allows one update per run per 30 s
const TOKEN_MARGIN := 60 # renew the access token this many seconds before it expires
const TIMEOUT := 15.0
const PERMANENT := ["run_invalid", "not_your_run", "run_ended", "no_player"] # the server will never accept these updates

var enabled := false ## false in headless tests (SMOKE): nothing is sent
var url := OnlineConfig.URL ## env ONLINE_URL overrides it
var ranked := false ## the running run counts for the leaderboard (false: offline at run start, never sent)
var _run := {} # {id, ranked, started, modifiers, ended}: the run this session plays; the first three are saved with it
var _auth := {}
var _outbox: Array = [] # [{run_id, day, rescued, kills, ended, victory, modifiers}]
var _dir := "" # profile folder _auth and _outbox were read from
var _online := false
var _busy := false # a token renewal is running
var _auth_error := "offline" # why the last renewal failed
var _flushing := false
var _tick := RETRY_SECONDS
var _board_seq := 0
var _player_seq := 0


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	var env := OS.get_environment("ONLINE_URL")
	if env != "":
		url = env
	enabled = OS.get_environment("SMOKE") == "" or env != ""
	_sync_profile()
	Save.register("online", _save_state, _load_state)
	Game.day_changed.connect(_on_day)
	if enabled:
		_probe()


func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = RETRY_SECONDS
		if enabled and (not _online or not _outbox.is_empty()):
			_probe()


## Server reachable (the last request got an answer).
func is_online() -> bool:
	return _online


## This profile has a player row on the server (auth.json).
func is_registered() -> bool:
	_sync_profile()
	return _auth.get("registered", false)


## The server-side id of this profile's player (board rows' player_id), "" before the first sign-in.
func player_id() -> String:
	_sync_profile()
	return _auth.get("user_id", "")


func register(pname: String, avatar: int) -> void:
	_account("register_player", {"p_name": pname, "p_avatar": avatar}, func(): _auth["registered"] = true; _save_auth())


func rename(pname: String) -> void:
	_account("rename_player", {"p_name": pname})


func set_avatar(avatar: int) -> void:
	_account("set_avatar", {"p_avatar": avatar})


## Deletes player, runs and auth user on the server and the local tokens/outbox. A profile that was never registered
## only loses its local files.
func delete_me() -> void:
	if not is_registered():
		_forget()
		done.emit.call_deferred(true, "")
		return
	_account("delete_me", {}, _forget)


## stats: {day, rescued, kills, ended, victory, modifiers}. Queued in the outbox; values only grow on the server.
func submit_run(run_id: String, stats: Dictionary) -> void:
	_sync_profile()
	if not enabled:
		return
	var e := {"run_id": run_id, "day": int(stats.get("day", 1)), "rescued": int(stats.get("rescued", 0)), "kills": int(stats.get("kills", 0)),
		"ended": bool(stats.get("ended", false)), "victory": bool(stats.get("victory", false)), "modifiers": Array(stats.get("modifiers", []))}
	var i := _outbox.find_custom(func(o): return o["run_id"] == run_id)
	if i < 0:
		_outbox.append(e)
	else:
		var o: Dictionary = _outbox[i]
		for k in ["day", "rescued", "kills"]:
			o[k] = maxi(o[k], e[k])
		o["ended"] = o["ended"] or e["ended"]
		o["victory"] = o["victory"] or e["victory"]
	_save_outbox()
	_flush()


## kind: "points" | "days" | "rescued" | "kills" | "best_run". Answers on `board` or `board_failed`.
func fetch_board(kind: String, limit := 50) -> void:
	_board_seq += 1
	var seq := _board_seq
	var view := "best_run" if kind == "best_run" else "leaderboard_" + kind
	if not enabled or not kind in BOARDS:
		board_failed.emit.call_deferred("offline")
		return
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/%s?order=rank,name&limit=%d" % [view, limit], null, false)
	if seq != _board_seq:
		return # a newer request took over
	if not r["ok"]:
		board_failed.emit(r["error"])
		return
	var rows := _rows(r["data"])
	var own := {}
	var uid := player_id()
	if uid != "":
		var i := rows.find_custom(func(o): return o["player_id"] == uid)
		if i >= 0:
			own = rows[i]
		else:
			var o: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/%s?player_id=eq.%s" % [view, uid], null, false)
			if seq != _board_seq:
				return
			if o["ok"] and not _rows(o["data"]).is_empty():
				own = _rows(o["data"])[0]
	board.emit(rows, own)


## Answers on `player` or `player_failed`. `id` is a board row's player_id. Runs and wins are only known for yourself.
func fetch_player(id: String) -> void:
	_player_seq += 1
	var seq := _player_seq
	if not enabled:
		player_failed.emit.call_deferred("offline")
		return
	var s := {"player_id": id, "name": "", "avatar": 0, "points": 0, "points_rank": 0, "days": 0, "rescued": 0, "kills": 0,
		"best": {}, "runs": -1, "wins": -1}
	var keys := {"points": "points", "days": "days", "rescued": "rescued", "kills": "kills"}
	for kind in keys:
		var r: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/leaderboard_%s?player_id=eq.%s" % [kind, id], null, false)
		if seq != _player_seq:
			return
		if not r["ok"]:
			player_failed.emit(r["error"])
			return
		for row in _rows(r["data"]):
			s[keys[kind]] = row["value"]
			s["name"] = row["name"]
			s["avatar"] = row["avatar"]
			if kind == "points":
				s["points_rank"] = row["rank"]
	var b: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/best_run?player_id=eq.%s" % id, null, false)
	if seq != _player_seq:
		return
	if b["ok"] and not _rows(b["data"]).is_empty():
		s["best"] = _rows(b["data"])[0]
	if id == player_id() and is_registered():
		var runs: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/runs?select=victory", null)
		if seq != _player_seq:
			return
		if runs["ok"]:
			s["runs"] = runs["data"].size()
			s["wins"] = runs["data"].filter(func(x): return x["victory"]).size()
	if s["name"] == "":
		player_failed.emit("no_runs") # the player has no run on the boards yet
		return
	player.emit(s)


## Run start (main.gd, new run only): first upsert; if it fails the run is unranked.
func begin_run(modifiers := []) -> void:
	_sync_profile()
	_run = {"id": _uuid(), "ranked": false, "started": false, "ended": false, "modifiers": modifiers.duplicate()}
	ranked = false
	if not enabled or not is_registered():
		return
	_run["ranked"] = true
	ranked = true
	await _start_run()


## Run over or abandoned (Game.record_run). An abandoned saved run is read from the save file.
func end_run(run_day: int, run_rescued: int, run_kills: int, victory := false) -> void:
	if not enabled:
		return
	_sync_profile() # after a profile switch the run in memory belongs to the other profile
	var st := _run
	if _run.is_empty() or _run["ended"]:
		st = Save.read().get("systems", {}).get("online", {})
	else:
		_run["ended"] = true
	ranked = false
	if st.get("ranked", false):
		submit_run(st["id"], {"day": run_day, "rescued": run_rescued, "kills": run_kills, "ended": true, "victory": victory, "modifiers": st["modifiers"]})


## Evacuation victory (evac.gd) while the run goes on (STAY BEHIND): the run is NOT ended, the server only learns victory = true
## (upsert_run keeps it on a running run) and keeps it through every later update, death included.
func mark_victory() -> void:
	if enabled and ranked and Game.running and not _run.is_empty() and not _run["ended"]:
		submit_run(_run["id"], {"day": Game.day, "rescued": Game.saved_count(), "kills": Game.kills, "victory": true, "modifiers": _run["modifiers"]})


## Title text: NOTICE for an unranked saved run or while offline, else "".
func title_notice() -> String:
	if not enabled or not is_registered():
		return ""
	if Save.has_run():
		return "" if Save.read().get("systems", {}).get("online", {}).get("ranked", false) else NOTICE
	return "" if _online else NOTICE


func error_text(code: String) -> String:
	return ERRORS.get(code, "Server error (%s)." % code)


# --- run state -------------------------------------------------------------------------------------------

func _save_state() -> Dictionary:
	return {} if _run.is_empty() else {"id": _run["id"], "ranked": _run["ranked"], "started": _run["started"], "modifiers": _run["modifiers"]}


func _load_state(d: Dictionary) -> void:
	_sync_profile() # first, so a later profile check does not drop the run just loaded
	if d.is_empty():
		return
	_run = {"id": d["id"], "ranked": d["ranked"], "started": d["started"], "ended": false, "modifiers": d["modifiers"]}
	ranked = d["ranked"]
	if ranked and not d["started"]: # closed before the server answered the first call
		_start_run.call_deferred()


## First upsert_run of the current run: day 1 whatever the loaded state says (the server limits days by elapsed time).
func _start_run() -> void:
	var id: String = _run["id"]
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/upsert_run", _body({"run_id": id, "day": 1, "rescued": 0, "kills": 0, "ended": false,
		"victory": false, "modifiers": _run["modifiers"]}))
	if _run.get("id") != id:
		return
	if r["ok"]:
		_run["started"] = true
		_flush()
	else:
		_run["ranked"] = false
		ranked = false
		_outbox = _outbox.filter(func(o): return o["run_id"] != id)
		_save_outbox()


func _on_day(day: int) -> void:
	if enabled and ranked and Game.running:
		submit_run(_run["id"], {"day": day, "rescued": Game.saved_count(), "kills": Game.kills, "modifiers": _run["modifiers"]})


# --- outbox ----------------------------------------------------------------------------------------------

func _body(e: Dictionary) -> Dictionary:
	return {"p_run_id": e["run_id"], "p_day": e["day"], "p_rescued": e["rescued"], "p_kills": e["kills"],
		"p_ended": e["ended"], "p_victory": e["victory"], "p_modifiers": e["modifiers"],
		"p_version": ProjectSettings.get_setting("application/config/version", "0.0.0")}


## Sends the queue in order. The current run waits for the answer to its first call; offline stops everything, any other
## error only skips that entry until the next try (PERMANENT ones are dropped).
func _flush() -> void:
	if _flushing or not enabled:
		return
	_sync_profile()
	_flushing = true
	var dir := _dir
	var i := 0
	while i < _outbox.size() and dir == _dir:
		var e: Dictionary = _outbox[i]
		if _run.get("id") == e["run_id"] and not _run["started"]:
			i += 1
			continue
		var snap := e.duplicate(true)
		var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/upsert_run", _body(e))
		if dir != _dir:
			break
		if r["ok"] or r["error"] in PERMANENT:
			var j := _outbox.find_custom(func(o): return o == snap) # newer values were merged in meanwhile: keep and resend
			if j >= 0:
				_outbox.remove_at(j)
			else:
				i += 1
		elif r["error"] == "offline" or r["error"] == "auth_lost":
			break
		else:
			i += 1
	_flushing = false
	_save_outbox()


func _probe() -> void:
	await _http(HTTPClient.METHOD_GET, "/rest/v1/modifiers?limit=1", null, "")
	if _online:
		_flush()


# --- account ---------------------------------------------------------------------------------------------

func _account(rpc_name: String, body: Dictionary, on_ok := Callable()) -> void:
	_sync_profile()
	if not enabled:
		done.emit.call_deferred(false, "offline")
		return
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + rpc_name, body)
	if rpc_name == "register_player" and r["error"] == "already_registered": # row exists (crash before auth.json was saved)
		r = {"ok": true, "error": ""}
	if r["ok"] and on_ok.is_valid():
		on_ok.call()
	done.emit(r["ok"], r["error"])


## Local tokens and queue gone (after delete_me).
func _forget() -> void:
	_sync_profile()
	_auth = {}
	_outbox = []
	_run = {}
	ranked = false
	for f in ["auth.json", "outbox.json"]:
		DirAccess.remove_absolute(_dir + f)


# --- HTTP and tokens -------------------------------------------------------------------------------------

## Authenticated call: renews the access token when it is about to expire or the server answers 401 (once).
## authed = false: public reads with the anon key.
func _call(method: int, path: String, body: Variant, authed := true) -> Dictionary:
	if not authed:
		return await _http(method, path, body, "")
	_sync_profile()
	var tok: String = _auth.get("access_token", "")
	if tok == "" or int(_auth.get("expires_at", 0)) - Time.get_unix_time_from_system() < TOKEN_MARGIN:
		if not await _renew(tok):
			return {"ok": false, "status": 0, "data": null, "error": _auth_error}
		tok = _auth["access_token"]
	var r: Dictionary = await _http(method, path, body, tok)
	if r["status"] == 401:
		if not await _renew(tok):
			return {"ok": false, "status": 0, "data": null, "error": _auth_error}
		r = await _http(method, path, body, _auth["access_token"])
	return r


## New access token: refresh, or anonymous sign-up for a profile without identity. `stale` is the token that failed; if
## another call renewed it meanwhile there is nothing to do. A registered profile whose refresh token is rejected keeps
## its name on the server, so it is NOT silently signed up again (error auth_lost).
func _renew(stale: String) -> bool:
	while _busy:
		await get_tree().process_frame
	if _auth.get("access_token", "") != stale:
		return true
	_busy = true
	var ok := await _renew_locked()
	_busy = false
	return ok


func _renew_locked() -> bool:
	var r := {"ok": false, "error": "none"}
	if _auth.has("refresh_token"):
		r = await _http(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": _auth["refresh_token"]}, "")
	if not r["ok"] and r["error"] != "offline":
		if _auth.get("registered", false):
			_auth_error = "auth_lost"
			return false
		r = await _http(HTTPClient.METHOD_POST, "/auth/v1/signup", {}, "")
	if not r["ok"]:
		_auth_error = r["error"]
		return false
	var d: Dictionary = r["data"]
	_auth = {"access_token": d["access_token"], "refresh_token": d["refresh_token"], "user_id": d["user"]["id"],
		"expires_at": int(d.get("expires_at", Time.get_unix_time_from_system() + int(d.get("expires_in", 3600)))),
		"registered": _auth.get("registered", false)}
	_save_auth()
	return true


## One request. `token` "" = anon key. Returns {ok, status, data, error}; error "offline" for no answer and 5xx.
func _http(method: int, path: String, body: Variant, token: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	var headers := ["apikey: " + OnlineConfig.ANON_KEY, "Authorization: Bearer " + (token if token != "" else OnlineConfig.ANON_KEY),
		"Content-Type: application/json"]
	if req.request(url + path, headers, method, "" if body == null else JSON.stringify(body)) != OK:
		req.queue_free()
		_set_online(false)
		return {"ok": false, "status": 0, "data": null, "error": "offline"}
	var res: Array = await req.request_completed # [result, status, headers, body]
	req.queue_free()
	var status: int = res[1]
	if res[0] != HTTPRequest.RESULT_SUCCESS or status >= 500:
		_set_online(false)
		return {"ok": false, "status": 0, "data": null, "error": "offline"}
	_set_online(true)
	var text: String = res[3].get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if text != "" else null
	var ok := status >= 200 and status < 300
	return {"ok": ok, "status": status, "data": data, "error": "" if ok else _error_code(status, data)}


## PostgREST/RPC errors carry the code in `message`; GoTrue in `error_code` / `msg` / `error_description`.
func _error_code(status: int, data: Variant) -> String:
	if data is Dictionary:
		for k in ["error_code", "message", "msg", "error_description"]:
			if data.get(k) is String and data[k] != "":
				return data[k]
	return "http_%d" % status


func _set_online(v: bool) -> void:
	if v != _online:
		_online = v
		online_changed.emit(v)


func _rows(data: Variant) -> Array:
	var out := []
	for r in (data if data is Array else []):
		for k in ["rank", "value", "avatar", "day"]:
			if r.has(k):
				r[k] = int(r[k])
		out.append(r)
	return out


func _uuid() -> String:
	var b := Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h := b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20)]


# --- files (per profile) ---------------------------------------------------------------------------------

## Reads auth.json and outbox.json again when the active profile changed.
func _sync_profile() -> void:
	var dir := Game.profile_dir()
	if dir == _dir:
		return
	if _dir != "": # another profile: its run is not ours (the save hook loads ours again)
		_run = {}
		ranked = false
	_dir = dir
	_auth = _read(dir + "auth.json", {})
	_outbox = _read(dir + "outbox.json", []).map(func(e): # JSON gives floats
		return {"run_id": e["run_id"], "day": int(e["day"]), "rescued": int(e["rescued"]), "kills": int(e["kills"]), "ended": bool(e["ended"]),
			"victory": bool(e["victory"]), "modifiers": e["modifiers"]})
	if not _outbox.is_empty():
		_tick = 1.0


func _read(path: String, fallback: Variant) -> Variant:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return data if typeof(data) == typeof(fallback) else fallback


func _save_auth() -> void:
	_write(_dir + "auth.json", _auth)


func _save_outbox() -> void:
	_write(_dir + "outbox.json", _outbox)


func _write(path: String, data: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
