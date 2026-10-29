extends Node
## Online client test (scripts/online.gd) against the local stub tools/fake_supabase.py, which this test starts itself:
##   SMOKE=online godot --headless --path . --quit-after 30000
## Registration and its errors, the first upsert of a ranked run, day updates, token expiry (401 -> refresh -> retry),
## server down (outbox keeps the update, sent later), an offline run start (unranked, nothing sent), saved run state,
## abandon from the save file, boards, player stats, delete_me. Failures are collected so one run lists all of them.

const PORT := 18765
const BASE := "http://127.0.0.1:18765"

var _bad: PackedStringArray = []
var _pid := -1


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	var script := ProjectSettings.globalize_path("res://tools/fake_supabase.py")
	_pid = OS.create_process("python", ["-I", script, str(PORT)])
	if _pid <= 0:
		_pid = OS.create_process("python3", ["-I", script, str(PORT)])
	if _pid <= 0 or not await _stub_up():
		push_error("ONLINE FAIL: could not start tools/fake_supabase.py (python on the PATH?)")
		_finish()
		return
	await _cases()
	_finish()


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)
	Online.enabled = OS.get_environment("SMOKE") == ""
	Online._forget()
	Save.delete_run()
	if not _bad.is_empty():
		push_error("ONLINE FAIL\n" + "\n".join(_bad))
		get_tree().quit(1)
		return
	print("ONLINE OK")
	get_tree().quit(0)


func _stub_up() -> bool:
	for i in 30:
		if (await _req(HTTPClient.METHOD_GET, "/_test"))["status"] == 200:
			return true
		await get_tree().create_timer(0.3).timeout
	return false


## One request to the stub (no auth); {status, data}.
func _req(method: int, path: String, body := {}, headers: Array = []) -> Dictionary:
	var r := HTTPRequest.new()
	add_child(r)
	r.request(BASE + path, ["apikey: test", "Content-Type: application/json"] + headers, method, JSON.stringify(body))
	var res: Array = await r.request_completed
	r.queue_free()
	return {"status": res[1], "data": JSON.parse_string(res[3].get_string_from_utf8())}


func _state() -> Dictionary:
	return (await _req(HTTPClient.METHOD_GET, "/_test"))["data"]


func _runs() -> Array:
	return (await _state())["runs"].values()


func _wait(cond: Callable, secs := 8.0) -> bool:
	var t := 0.0
	while not cond.call() and t < secs:
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _day(d: int, rescued: int, kills: int) -> void:
	Game.rescued = rescued
	Game.kills = kills
	Game.day_changed.emit(d)


func _cases() -> void:
	Online._forget()
	Online.enabled = true
	Online.url = BASE
	var rival := await _req(HTTPClient.METHOD_POST, "/auth/v1/signup")
	await _req(HTTPClient.METHOD_POST, "/rest/v1/rpc/register_player", {"p_name": "Rival", "p_avatar": 1},
		["Authorization: Bearer " + rival["data"]["access_token"]])

	# not registered: the run is unranked, nothing is sent
	await Online.begin_run()
	check(not Online.ranked and not Online.is_registered(), "unregistered profile: unranked run")
	check((await _runs()).is_empty(), "unregistered profile: nothing sent")

	# register and its errors
	Online.register("ab", 3)
	var r: Array = await Online.done
	check(not r[0] and r[1] == "name_invalid", "short name -> name_invalid, got %s" % [r])
	Online.register("Rival", 3)
	r = await Online.done
	check(not r[0] and r[1] == "name_taken", "taken name (case-insensitive stub) -> name_taken, got %s" % [r])
	check(not Online.is_registered(), "failed register leaves the profile unregistered")
	Online.register("Tester", 3)
	r = await Online.done
	check(r[0] and r[1] == "" and Online.is_registered(), "register ok, got %s" % [r])
	check(FileAccess.file_exists(Game.profile_dir() + "auth.json"), "auth.json written")
	Online.register("Tester", 3)
	r = await Online.done
	check(not r[0] and r[1] == "already_registered", "second register -> already_registered, got %s" % [r])
	Online.rename("Rival")
	r = await Online.done
	check(not r[0] and r[1] == "name_taken", "rename onto a taken name, got %s" % [r])
	Online.rename("Tester2")
	r = await Online.done
	check(r[0], "rename ok, got %s" % [r])
	Online.set_avatar(5)
	r = await Online.done
	check(r[0] and (await _state())["players"][Online.player_id()]["avatar"] == 5, "set_avatar")

	# ranked run: first upsert at the start, then the day change
	Game.rescued = 0
	Game.kills = 0
	await Online.begin_run()
	check(Online.ranked and Online._run["started"], "run start accepted -> ranked")
	var id: String = Online._run["id"]
	check((await _runs()).size() == 1 and (await _runs())[0]["day"] == 1, "first upsert at run start")
	_day(2, 3, 40)
	check(await _wait(func(): return Online._outbox.is_empty()), "outbox empties after a day change")
	var run: Dictionary = (await _runs())[0]
	check(run["day"] == 2 and run["rescued"] == 3 and run["kills"] == 40, "day 2 on the server: %s" % [run])

	# expired access token: 401 -> refresh -> retry
	var old_tok: String = Online._auth["access_token"]
	await _req(HTTPClient.METHOD_POST, "/_test", {"expire": true})
	_day(3, 5, 80)
	check(await _wait(func(): return Online._outbox.is_empty()), "outbox empties after token expiry")
	check((await _runs())[0]["day"] == 3 and Online._auth["access_token"] != old_tok, "refreshed token, day 3 on the server")

	# server down: the update waits in outbox.json, later it is sent
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": true})
	_day(4, 6, 90)
	check(await _wait(func(): return not Online._flushing and not Online.is_online()), "down: offline")
	check(Online._outbox.size() == 1 and Online._outbox[0]["day"] == 4, "down: update queued")
	check(Online._read(Game.profile_dir() + "outbox.json", []).size() == 1, "down: outbox.json written")
	check((await _req(HTTPClient.METHOD_POST, "/_test", {"down": false}))["status"] == 200, "stub up again")
	Online._probe()
	check(await _wait(func(): return Online._outbox.is_empty()), "outbox sent when the server is back")
	check((await _runs())[0]["day"] == 4 and Online.is_online(), "day 4 on the server")

	# saved run state, abandon from the save file
	check(Save.autosave(), "autosave for the abandon case")
	var online_state: Dictionary = Save.read()["systems"]["online"]
	check(online_state["id"] == id and online_state["ranked"] and online_state["started"], "run id and ranked are saved")
	Online._run = {}
	Online._load_state(online_state)
	check(Online.ranked and Online._run["id"] == id, "state restored")
	Online._run = {}
	Online.ranked = false
	Online.end_run(5, 9, 120) # what Save.abandon does: the run is only in the save file
	check(await _wait(func(): return Online._outbox.is_empty()), "abandoned run sent")
	run = (await _runs())[0]
	check(run["ended"] and run["day"] == 5 and run["rescued"] == 9 and run["kills"] == 120, "abandoned run ended on the server: %s" % [run])
	Save.delete_run()

	# a live run ends normally
	await Online.begin_run()
	var id2: String = Online._run["id"]
	Online.end_run(2, 1, 10)
	check(not Online.ranked, "ended run is not ranked any more")
	check(await _wait(func(): return Online._outbox.is_empty()), "ended run sent")
	check((await _runs()).size() == 2, "two runs on the server")

	# offline at run start: unranked for good
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": true})
	await Online.begin_run()
	check(not Online.ranked and not Online._run["ranked"], "offline run start -> unranked")
	_day(2, 1, 1)
	Online.end_run(2, 1, 1)
	await get_tree().create_timer(0.3).timeout
	check(Online._outbox.is_empty(), "unranked run queues nothing")
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": false})
	Online._probe()
	await get_tree().create_timer(0.5).timeout
	check((await _runs()).size() == 2, "unranked run never sent")
	Save.delete_run() # the day changes above autosaved
	Online._online = false
	check(Online.title_notice() == Online.NOTICE, "title notice while offline")
	Online._online = true
	check(Online.title_notice() == "", "no title notice while online")

	# boards and player stats
	Online.fetch_board("points", 10)
	var b: Array = await Online.board
	check(b[0].size() == 1 and b[0][0]["name"] == "Tester2" and b[0][0]["rank"] == 1, "points board: %s" % [b])
	check(b[1].get("player_id", "") == Online.player_id() and b[1]["value"] == b[0][0]["value"], "own row")
	Online.fetch_board("best_run", 10)
	b = await Online.board
	check(b[0].size() == 1 and b[0][0].has("day") and b[0][0]["day"] == 5, "best_run board: %s" % [b])
	Online.fetch_player(Online.player_id())
	var p: Dictionary = await Online.player
	check(p["name"] == "Tester2" and p["runs"] == 2 and p["wins"] == 0 and p["days"] == 7 and p["avatar"] == 5, "own stats: %s" % [p])
	Online.fetch_player(rival["data"]["user"]["id"])
	var f: String = await Online.player_failed
	check(f == "no_runs", "player without runs: %s" % [f])
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": true})
	Online.fetch_board("days", 10)
	f = await Online.board_failed
	check(f == "offline", "board offline: %s" % [f])
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": false})

	# delete_me
	Online.delete_me()
	r = await Online.done
	check(r[0] and not Online.is_registered() and not FileAccess.file_exists(Game.profile_dir() + "auth.json"), "delete_me ok, local tokens gone: %s" % [r])
	var end := await _state()
	check(end["runs"].is_empty() and end["players"].size() == 1, "delete_me removed player and runs on the server")
