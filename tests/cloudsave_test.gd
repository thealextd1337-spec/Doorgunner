extends Node
## Cloud backup + export/import test (scripts/cloud_save.gd, docs/ROADMAP2.md Q3) against tools/fake_supabase.py, which this test starts:
##   SMOKE=cloudsave godot --headless --path . --quit-after 30000
## Upload on landing (rate-limited), delete local + restore, death deletes cloud then local (also while offline: the marker retries),
## export / import (auth only on request, outdated runs, garbage), an imported run is never ranked, lower values never reach the
## server, saves from before Q3 (no `imported`, run.sav) load. Failures are collected so one run lists all of them.

# one stub per test process: parallel runs (other worktrees, agents) must not share a server and its "down" switch
var PORT := 20000 + OS.get_process_id() % 20000
var BASE := "http://127.0.0.1:%d" % PORT

var _bad: PackedStringArray = []
var _pid := -1
var _profiles_at_start := 0


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
		push_error("CLOUDSAVE FAIL: could not start tools/fake_supabase.py (python on the PATH?)")
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
		push_error("CLOUDSAVE FAIL\n" + "\n".join(_bad))
		get_tree().quit(1)
		return
	print("CLOUDSAVE OK")
	get_tree().quit(0)


func _stub_up() -> bool:
	for i in 30:
		if (await _req(HTTPClient.METHOD_GET, "/_test"))["status"] == 200:
			return true
		await get_tree().create_timer(0.3).timeout
	return false


func _req(method: int, path: String, body := {}) -> Dictionary:
	var r := HTTPRequest.new()
	add_child(r)
	r.request(BASE + path, ["apikey: test", "Content-Type: application/json"], method, JSON.stringify(body))
	var res: Array = await r.request_completed
	r.queue_free()
	return {"status": res[1], "data": JSON.parse_string(res[3].get_string_from_utf8())}


func _wait(cond: Callable, secs := 8.0) -> bool:
	var t := 0.0
	while not cond.call() and t < secs:
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return cond.call()


## The cloud copy as the server has it ({} if none), data decoded.
func _cloud(with_data := true) -> Dictionary:
	var r: Dictionary = await Online.cloud_call("get_save", {"p_slot": "run", "p_meta_only": not with_data})
	if r["ok"] and r["data"] is Dictionary:
		return r["data"]
	return {}


func _server_runs() -> Array:
	return (await _req(HTTPClient.METHOD_GET, "/_test"))["data"]["runs"].values()


func _cases() -> void:
	Online.enabled = true
	Online.url = BASE
	Online._forget()
	Save.delete_run()
	CloudSave._set_pending(Game.profile_dir(), [])
	_profiles_at_start = Game.profiles["list"].size()
	var home: String = Game.profiles["last"]

	# --- the slot: run.sav stays the name of the default slot, a save from before Q3 loads
	check(Save.slot == "run" and Save.path() == Game.profile_dir() + "run.sav", "default slot keeps run.sav: %s" % Save.path())
	var old := {"version": "1.0.0-beta", "format": Save.SAVE_FORMAT, "saved_at": 1, "head": {"day": 4, "time": 0.5, "rescued": 3, "kills": 20},
		"systems": {"online": {"id": "old-id", "ranked": true, "started": true, "modifiers": []}}}
	FileAccess.open(Save.path(), FileAccess.WRITE).store_buffer(var_to_bytes(old))
	check(Save.has_run() and Save.head()["day"] == 4, "pre-Q3 save read")
	Online._load_state(old["systems"]["online"])
	check(Online.ranked and not Online.imported and Online._run["id"] == "old-id", "pre-Q3 online state: still ranked")
	check(Online.title_notice() == "", "no imported notice on an old save")
	Online._run = {}
	Online.ranked = false
	Save.delete_run()

	# --- register, start a ranked run
	Online.register("Cloudy", 3)
	var r: Array = await Online.done
	check(r[0] and Online.is_registered(), "register: %s" % [r])
	await Online.begin_run()
	check(Online.ranked and Online._run["started"], "ranked run")
	var run_id: String = Online._run["id"]

	# --- upload on landing; the second landing within 5 minutes sends nothing
	check(await _cloud(false) == {}, "no cloud save before the first landing")
	Game.day = 2
	check(Save.autosave(false), "plain autosave")
	await get_tree().create_timer(0.3).timeout
	check(await _cloud(false) == {}, "a plain autosave does not upload")
	check(Save.autosave(true), "autosave on landing")
	check(await _wait(func(): return not CloudSave._uploading and CloudSave._last_upload.size() > 0), "upload finished")
	var local := FileAccess.get_file_as_bytes(Save.path())
	var cloud: Dictionary = await _cloud()
	check(not cloud.is_empty() and cloud["format"] == Save.SAVE_FORMAT, "cloud save stored: %s" % [cloud.keys()])
	var up := CloudSave.unpack(Marshalls.base64_to_raw(cloud.get("data", "")))
	check(up == local, "the cloud copy is the local file (%d bytes)" % up.size())
	print("CLOUDSAVE sizes: run.sav %d bytes, cloud (zstd) %d bytes" % [local.size(), CloudSave.last_size])
	check(CloudSave.last_size > 0 and CloudSave.last_size < CloudSave.MAX_BYTES, "compressed size within the cap")
	await Online.cloud_call("delete_save", {"p_slot": "run"})
	Save.autosave(true)
	await get_tree().create_timer(0.4).timeout
	check(await _cloud(false) == {}, "second landing within 5 min: no upload")

	# --- restore: put it back, delete local, restore
	CloudSave._last_upload.clear()
	Save.autosave(true)
	check(await _wait(func(): return CloudSave._last_upload.size() > 0), "uploaded again")
	local = FileAccess.get_file_as_bytes(Save.path())
	check(await CloudSave.restore() != "", "restore refuses while a local run exists")
	Save.delete_run()
	var meta: Dictionary = await CloudSave.peek()
	check(not meta.is_empty() and not Save.has_run(), "peek finds the cloud copy when the local one is gone")
	check(await CloudSave.restore() == "" and Save.has_run(), "restore")
	check(FileAccess.get_file_as_bytes(Save.path()) == local and Save.head()["day"] == 2, "restored file is byte-identical, day 2")
	check(Save.read()["systems"]["online"]["id"] == run_id and Save.read()["systems"]["online"]["ranked"], "a restored own run keeps its ranked state")

	# --- the server never lowers values (a rewound copy changes nothing)
	Game.rescued = 4
	Game.kills = 60
	Game.day_changed.emit(3)
	check(await _wait(func(): return Online._outbox.is_empty()), "day 3 sent")
	Online.submit_run(run_id, {"day": 2, "rescued": 1, "kills": 5})
	check(await _wait(func(): return Online._outbox.is_empty()), "rewound update sent")
	var srv: Array = await _server_runs()
	check(srv.size() == 1 and srv[0]["day"] == 3 and srv[0]["kills"] == 60, "server keeps the higher values: %s" % [srv])

	# --- export: meta + run, auth only on request
	local = FileAccess.get_file_as_bytes(Save.path()) # the day change autosaved
	Game.meta["runs"] = 7
	Game.meta["best_day"] = 9
	var plain := CloudSave.unpack(CloudSave.export_bytes(false))
	var ex: Dictionary = bytes_to_var(plain)
	check(ex["magic"] == CloudSave.MAGIC and ex["meta"]["runs"] == 7 and ex["save"] == local and not ex.has("auth"), "export without auth: %s" % [ex.keys()])
	var with_auth: Dictionary = bytes_to_var(CloudSave.unpack(CloudSave.export_bytes(true)))
	check(with_auth.has("auth") and "refresh_token" in with_auth["auth"], "export with auth when ticked")
	print("CLOUDSAVE sizes: export %d bytes" % CloudSave.export_bytes(false).size())

	# --- import: a new profile, the run unranked, the old online state dropped
	var before_runs: int = (await _server_runs()).size()
	check(CloudSave.import_bytes(PackedByteArray([1, 2, 3])) == CloudSave.NOT_EXPORT, "garbage refused")
	var bad_fmt := ex.duplicate()
	bad_fmt["export_format"] = CloudSave.EXPORT_FORMAT + 1
	var n_profiles: int = Game.profiles["list"].size()
	check(CloudSave.import_bytes(CloudSave.pack(var_to_bytes(bad_fmt))) == CloudSave.OLD_EXPORT, "newer export format refused")
	check(Game.profiles["list"].size() == n_profiles, "a refused import creates no profile")
	check(CloudSave.import_bytes(CloudSave.export_bytes(false)) == "", "import ok")
	check(Game.profiles["last"] != home and Game.profiles["list"].size() == n_profiles + 1, "import made a new active profile")
	var imp1: String = Game.profiles["last"]
	check(Game.meta["runs"] == 7 and Game.meta["best_day"] == 9, "meta imported")
	check(Save.has_run() and Save.head()["day"] == 2, "run imported")
	var st: Dictionary = Save.read()["systems"]["online"]
	check(st == {"imported": true}, "online state replaced: %s" % [st])
	check(Online.title_notice() == Online.IMPORTED_NOTICE, "title says imported: %s" % Online.title_notice())
	check(not Online.is_registered(), "no auth without the tick: the imported profile is local only")
	Online._load_state(st) # CONTINUE
	check(Online.imported and not Online.ranked and Online._run.is_empty(), "imported run is not ranked")
	check(Online._save_state() == {"imported": true}, "and stays imported when saved again")
	Game.rescued = 99
	Game.kills = 999
	Game.day_changed.emit(30)
	Online.end_run(30, 99, 999)
	await get_tree().create_timer(0.5).timeout
	var srv2: Array = await _server_runs()
	check(srv2.size() == before_runs and srv2[0]["day"] == 3 and Online._outbox.is_empty(), "nothing of the imported run reaches the server: %s" % [srv2])
	Online.imported = false

	# --- import with auth: same online identity; an outdated run is dropped
	Game.switch_profile(home)
	var uid: String = Online.player_id()
	var old_run: Dictionary = bytes_to_var(local)
	old_run["format"] = Save.SAVE_FORMAT - 1
	var ex_old := with_auth.duplicate()
	ex_old["save"] = var_to_bytes(old_run)
	check(CloudSave.import_bytes(CloudSave.pack(var_to_bytes(ex_old))) == "", "import with an outdated run still makes the profile")
	check(not Save.has_run() and Save.notice == Save.OLD_NOTICE, "outdated run dropped with the notice")
	Save.notice = ""
	check(Online.is_registered() and Online.player_id() == uid, "auth.json imported on request: same identity")
	var imp2: String = Game.profiles["last"]
	Game.switch_profile(home)

	# --- death: the cloud copy goes first, then the local one; offline the delete is retried
	Online.imported = false
	CloudSave._last_upload.clear()
	check(Save.autosave(true), "saved before the death")
	check(await _wait(func(): return CloudSave._last_upload.size() > 0), "cloud copy there")
	Game.end_run("test")
	check(not Save.has_run(), "death deleted the local run")
	check(await _wait(func(): return CloudSave.pending_slots().is_empty() and not CloudSave._draining), "cloud delete confirmed, marker gone")
	check(await _cloud(false) == {}, "death deleted the cloud copy")
	check(await CloudSave.peek() == {}, "nothing to restore after a death")
	Game.running = true
	Save.delete_run()

	# offline death: marker first, local gone, no restore offered, upload blocked; back online it is deleted
	await Online.begin_run()
	CloudSave._last_upload.clear()
	check(Save.autosave(true), "saved")
	check(await _wait(func(): return CloudSave._last_upload.size() > 0), "cloud copy there again")
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": true})
	Game.end_run("test")
	check(not Save.has_run() and CloudSave.pending_slots() == ["run"], "offline death: local gone, delete pending in cloud_del.json: %s" % [CloudSave.pending_slots()])
	await get_tree().create_timer(0.5).timeout
	check(CloudSave.pending_slots() == ["run"], "the failed delete stays pending")
	check(await CloudSave.restore() == "That run is over." and await CloudSave.peek() == {}, "no restore while the delete is pending")
	Game.running = true
	CloudSave._last_upload.clear()
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": false})
	Online._probe()
	check(await _wait(func(): return CloudSave.pending_slots().is_empty() and not CloudSave._draining), "pending delete sent when the server is back")
	check(await _cloud(false) == {}, "cloud copy gone after the retry")
	Save.delete_run()

	# --- clean up the profiles made here
	Online.enabled = false
	Online._forget()
	for id in [imp1, imp2]:
		Online._dir = ""
		await Profiles.delete(id)
	Game.switch_profile(home)
	check(Game.profiles["list"].size() == _profiles_at_start, "test profiles removed")
