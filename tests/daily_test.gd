extends Node
## Daily seed + weekly season test (docs/ROADMAP2.md Q14) against tools/fake_supabase.py, which this test starts:
##   SMOKE=daily godot --headless --path . --quit-after 30000
## Today's daily without the seed, start_daily: first attempt ranked (the server binds the run id: mode daily, the daily's
## modifiers), the run starts with the server seed / modifiers / heli (locked or not), both save slots side by side (title shows
## both CONTINUE buttons), cloud backup per slot, an ended daily drops only the daily cloud slot, second attempt practice (never
## sent), daily and season boards, no daily offline or unregistered, the ISO week helper, and the "same world" hash.
## Without --headless it also saves shot_daily_title.png and shot_daily_board.png (gitignored) for a look.
## Web check of the world hash: open the web build with ?perf=1, the console prints "WORLDHASH seed 20261102: <n>" once;
## <n> must equal WORLD_HASH below (FastNoiseLite and hash() give the same numbers in wasm as on desktop).

const PORT := 18767
const BASE := "http://127.0.0.1:18767"
const CM := preload("res://scripts/chunk_manager.gd")
const WORLD_HASH := 1761177401 # world_hash(CM.HASH_SEED); changes only when the world generator changes (then bump Save.SAVE_FORMAT too)

var _bad: PackedStringArray = []
var _pid := -1


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	get_tree().paused = true # Game.new_run below resets the run under the live world: keep the world still
	var script := ProjectSettings.globalize_path("res://tools/fake_supabase.py")
	_pid = OS.create_process("python", ["-I", script, str(PORT)])
	if _pid <= 0:
		_pid = OS.create_process("python3", ["-I", script, str(PORT)])
	if _pid <= 0 or not await _stub_up():
		push_error("DAILY FAIL: could not start tools/fake_supabase.py (python on the PATH?)")
		_finish()
		return
	_pure()
	await _cases()
	_finish()


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)
	Online.enabled = OS.get_environment("SMOKE") == ""
	Online._forget()
	Online.daily_run = {}
	for s in ["daily", "run"]:
		Save.slot = s
		Save.delete_run()
	Save.slot = "run"
	CloudSave._set_pending(Game.profile_dir(), [])
	get_tree().paused = false
	if not _bad.is_empty():
		push_error("DAILY FAIL\n" + "\n".join(_bad))
		get_tree().quit(1)
		return
	print("DAILY OK")
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


func _server_runs() -> Array:
	return (await _req(HTTPClient.METHOD_GET, "/_test"))["data"]["runs"].values()


func _utc(y: int, m: int, d: int) -> float:
	return Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": d, "hour": 12})


## No server needed: the ISO week helper (same as the server's to_char IYYY-"W"IW) and the world hash.
func _pure() -> void:
	for c in [[2026, 11, 2, "2026-W45"], [2026, 11, 1, "2026-W44"], [2027, 1, 1, "2026-W53"], [2024, 12, 30, "2025-W01"], [2021, 1, 3, "2020-W53"]]:
		check(Online.season_week(_utc(c[0], c[1], c[2])) == c[3], "season_week %d-%d-%d: %s, expected %s" % [c[0], c[1], c[2], Online.season_week(_utc(c[0], c[1], c[2])), c[3]])
	check(Online.utc_date(_utc(2026, 11, 2)) == "2026-11-02", "utc_date")
	var seed_before := Game.seed
	var t0 := Time.get_ticks_msec()
	var h := CM.world_hash(CM.HASH_SEED)
	print("WORLDHASH seed %d: %d (%d ms)" % [CM.HASH_SEED, h, Time.get_ticks_msec() - t0])
	check(h == WORLD_HASH, "world hash of seed %d is %d, expected %d (world generator changed?)" % [CM.HASH_SEED, h, WORLD_HASH])
	check(CM.world_hash(CM.HASH_SEED) == h, "world hash is stable")
	check(CM.world_hash(CM.HASH_SEED + 1) != h, "another seed, another world")
	check(Game.seed == seed_before, "world_hash restores Game.seed")


func _cases() -> void:
	var main: Node2D = Game.world
	Online.enabled = true
	Online.url = BASE
	Online._forget()
	CloudSave._set_pending(Game.profile_dir(), [])
	for s in ["daily", "run"]:
		Save.slot = s
		Save.delete_run()
	Save.slot = "run"
	var now := Time.get_unix_time_from_system()

	# --- not startable without a player or offline
	check(await Online.start_daily() == "no_player" and Online.daily_run.is_empty(), "unregistered: no daily")
	Online.register("Daily_Pilot", 5)
	var reg: Array = await Online.done
	check(reg[0] and Online.is_registered(), "register: %s" % [reg])
	Online.url = "http://127.0.0.1:9"
	check(await Online.start_daily() == "offline" and Online.daily_run.is_empty(), "offline: no daily")
	Online.url = BASE

	# --- today's daily: no seed before the start
	var info: Dictionary = await Online.fetch_daily()
	var d: Dictionary = info["data"] if info["ok"] and info["data"] is Dictionary else {}
	check(not d.is_empty() and not d.has("seed"), "get_daily without the seed: %s" % [info])
	check(d.get("date") == Online.utc_date(now) and d.get("season_week") == Online.season_week(now), "date and week agree with the client: %s" % [d])
	check(d.get("played") == false and int(d.get("resets_in", -1)) in range(0, 86401), "not played, reset countdown: %s" % [d])

	# --- first attempt: ranked, the run starts with the server's seed, modifiers and heli
	check(await Online.start_daily() == "", "start_daily")
	var day1: Dictionary = Online.daily_run.duplicate()
	check(day1.get("ranked") == true and day1.get("seed") is int and day1.get("modifiers") == d.get("modifiers") and day1.get("heli") == d.get("heli"),
		"first start is ranked and reveals the seed: %s" % [day1])
	var locked: Array = day1["modifiers"].filter(func(id): return not main.modifiers.unlocked(id))
	Game.new_run(day1["seed"], day1["modifiers"], "daily")
	check(Game.seed == day1["seed"] and Game.mode == "daily" and Game.start_mods == day1["modifiers"], "new_run(seed, modifiers, mode)")
	main.start_run(Game.start_mods, day1["heli"], "daily")
	check(main.modifiers.active == day1["modifiers"], "daily modifiers active, locked ones too (%s locked): %s" % [locked, main.modifiers.active])
	check(main.wrecks.type_id() == day1["heli"], "daily heli: %s, expected %s" % [main.wrecks.type_id(), day1["heli"]])
	check(Online.daily_run.is_empty() and Online._run["id"] == day1["run_id"] and Online._run["mode"] == "daily", "begin_run used the claimed id")
	check(await _wait(func(): return Online._run["started"]), "ranked daily sent its first update")
	var runs := await _server_runs()
	check(runs.size() == 1 and runs[0]["mode"] == "daily" and runs[0]["daily_date"] == d["date"] and runs[0]["modifiers"] == day1["modifiers"],
		"server made it the daily run: %s" % [runs])
	info = await Online.fetch_daily()
	check(info["ok"] and info["data"]["played"] == true, "played after the start")

	# --- both save slots side by side, cloud backup per slot
	Save.slot = "daily"
	Game.day = 3
	check(Save.autosave(true), "daily autosave")
	check(await _wait(func(): return not CloudSave._uploading and CloudSave._last_upload.has(Game.profile_dir() + "daily")), "daily slot uploaded")
	# review: the title offers the daily slot's cloud copy too and restores it into that slot
	var dbytes := FileAccess.get_file_as_bytes(Save.path())
	Save.slot = "run"
	for f in ["daily.sav", "daily.sav.bak"]:
		DirAccess.remove_absolute(Game.profile_dir() + f)
	var t0: CanvasLayer = preload("res://scripts/title_ui.gd").new()
	main.add_child(t0)
	t0.open()
	check(await _wait(func(): return t0.restore_btn.visible) and t0.restore_btn.text.contains("DAILY") and t0.restore_slot == "daily", "title offers RESTORE DAILY: " + t0.restore_btn.text)
	await t0._restore()
	check(FileAccess.get_file_as_bytes(Game.profile_dir() + "daily.sav") == dbytes and not Save.has_run() and Save.slot == "run", "restored into daily.sav, the run slot untouched")
	check(t0.cont_daily_btn.visible and not t0.restore_btn.visible, "the restored daily shows as CONTINUE")
	t0.queue_free()
	var normal_online := Online._run
	Online._run = {"id": "normal-run", "ranked": false, "started": false, "ended": false, "modifiers": [], "mode": "normal"}
	Game.mode = "normal"
	Game.day = 7
	check(Save.autosave(false), "normal autosave")
	Online._run = normal_online
	Game.mode = "daily"
	var dsave := Save.read_slot("daily")
	var nsave := Save.read_slot("run")
	check(FileAccess.file_exists(Game.profile_dir() + "daily.sav") and FileAccess.file_exists(Game.profile_dir() + "run.sav"), "daily.sav and run.sav both on disk")
	check(dsave["head"]["day"] == 3 and dsave["systems"]["game"]["mode"] == "daily" and dsave["systems"]["online"]["ranked"], "daily slot: day 3, daily, ranked")
	check(nsave["head"]["day"] == 7 and nsave["systems"]["game"]["mode"] == "normal", "run slot: day 7, normal")
	var cloud: Dictionary = await Online.cloud_call("get_save", {"p_slot": "daily", "p_meta_only": true})
	check(cloud["ok"] and cloud["data"] is Dictionary, "cloud has the daily slot")
	cloud = await Online.cloud_call("get_save", {"p_slot": "run", "p_meta_only": true})
	check(cloud["ok"] and cloud["data"] == null, "the daily upload did not touch the run slot")
	var title: CanvasLayer = preload("res://scripts/title_ui.gd").new()
	main.add_child(title)
	title.open()
	check(title.cont_btn.visible and title.cont_btn.text.contains("DAY 7"), "title CONTINUE: the normal run: " + title.cont_btn.text)
	check(title.cont_daily_btn.visible and title.cont_daily_btn.text.contains("DAY 3") and not title.cont_daily_btn.text.contains("practice"),
		"title CONTINUE DAILY: " + title.cont_daily_btn.text)
	check(await _wait(func(): return title.daily_lbl.text.contains("played today")), "title DAILY panel: " + title.daily_lbl.text)
	check(title.daily_lbl.text.contains(d["date"]) and title.daily_lbl.text.contains("resets in"), "DAILY shows date and countdown: " + title.daily_lbl.text)
	if DisplayServer.get_name() != "headless":
		await _shot("shot_daily_title.png")
	title.queue_free()

	# --- the ranked daily ends: the server drops the daily cloud slot only
	Online.end_run(3, 2, 15)
	check(await _wait(func(): return Online._outbox.is_empty() and not Online._flushing), "ended daily sent")
	runs = await _server_runs()
	check(runs.size() == 1 and runs[0]["ended"], "daily run ended on the server")
	cloud = await Online.cloud_call("get_save", {"p_slot": "daily", "p_meta_only": true})
	check(cloud["ok"] and cloud["data"] == null, "ended daily: its cloud slot is gone")

	# --- second attempt: same world, practice, nothing sent
	check(await Online.start_daily() == "", "second start_daily")
	var day2: Dictionary = Online.daily_run.duplicate()
	check(day2.get("ranked") == false and day2.get("seed") == day1["seed"] and day2.get("modifiers") == day1["modifiers"], "second attempt: same seed, not ranked: %s" % [day2])
	Game.new_run(day2["seed"], day2["modifiers"], "daily")
	main.start_run(Game.start_mods, day2["heli"], "daily")
	check(not Online.ranked and not Online._run["ranked"] and Online._run["id"] == day2["run_id"], "practice run is unranked")
	Online._on_day(2)
	Online.end_run(2, 1, 5)
	await get_tree().create_timer(0.4).timeout
	check((await _server_runs()).size() == 1, "practice run never reached the server")

	# --- boards: daily (today) and season (this week); all-time tabs only under ALL-TIME
	var lb := LeaderboardUi.new()
	add_child(lb)
	await get_tree().process_frame
	lb.open()
	lb.show_kind("daily")
	check(await _wait(func(): return lb.list.get_child_count() == 1 and lb.status.text.begins_with("Daily " + d["date"])), "daily board: %s / %d rows" % [lb.status.text, lb.list.get_child_count()])
	check(not lb.tabs.visible and lb.scope_btns["daily"].button_pressed and lb.own_slot.get_child_count() == 1, "daily tab: no all-time tabs, own row pinned")
	if DisplayServer.get_name() != "headless":
		await _shot("shot_daily_board.png")
	lb.show_kind("season")
	check(await _wait(func(): return lb.list.get_child_count() == 1 and lb.status.text.contains(d["season_week"])), "season board: %s / %d rows" % [lb.status.text, lb.list.get_child_count()])
	lb.show_kind("points")
	check(await _wait(func(): return lb.list.get_child_count() == 1 and lb.status.text == ""), "all-time points: %s" % lb.status.text)
	check(lb.tabs.visible and lb.scope_btns["points"].button_pressed and lb.tab_btns["points"].button_pressed, "ALL-TIME shows its tabs")
	lb.queue_free()

	# --- review: a claim older than an hour that never reached the runs table is practice
	await _req(HTTPClient.METHOD_POST, "/_test", {"today": "2030-01-02"})
	check(await Online.start_daily() == "" and Online.daily_run.get("ranked") == true, "a new day: first start ranked")
	var late: Dictionary = Online.daily_run.duplicate()
	await _req(HTTPClient.METHOD_POST, "/_test", {"age_attempts": 3700})
	Game.new_run(late["seed"], late["modifiers"], "daily")
	main.start_run(Game.start_mods, late["heli"], "daily")
	check(await _wait(func(): return Online._run["started"]), "the late run was sent")
	var late_run: Array = (await _server_runs()).filter(func(r): return r["id"] == late["run_id"])
	check(late_run.size() == 1 and late_run[0]["mode"] == "normal" and late_run[0]["daily_date"] == null, "a late run on an old claim is no daily run: %s" % [late_run])
	await _req(HTTPClient.METHOD_POST, "/_test", {"today": null})


func _shot(name: String) -> void:
	get_tree().paused = false
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://" + name)
	get_tree().paused = true
