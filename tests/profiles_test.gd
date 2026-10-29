extends Node
## Profiles + leaderboard UI test: SMOKE=profiles godot --headless --path . --quit-after 30000
## Runs against the real Online autoload and the stub tools/fake_supabase.py (started by this test, like online_test.gd):
## profiles (create / switch / rename / delete), name feedback, registering when the connection comes back, offline renames
## pushed later, name_taken, delete_me online and offline, the leaderboard (boards, breakdown, offline view, reload on
## reconnect). Profiles live in the SMOKE namespace (Game.profiles_path), never in the player's profiles.
## Failures are collected so one run lists all of them.

const PORT := 18766
const BASE := "http://127.0.0.1:18766"

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
		push_error("PROFILES FAIL: could not start tools/fake_supabase.py (python on the PATH?)")
		_finish()
		return
	await _cases()
	_finish()


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)
	Online.enabled = false
	if not _bad.is_empty():
		push_error("PROFILES FAIL\n" + "\n".join(_bad))
		get_tree().quit(1)
		return
	print("PROFILES OK")
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


## Server player named `n` (or {}).
func _player(n: String) -> Dictionary:
	for p in (await _req(HTTPClient.METHOD_GET, "/_test"))["data"]["players"].values():
		if p["name"] == n:
			return p
	return {}


## Polls the stub until player `n` is there (or gone).
func _server_has(n: String, present := true) -> bool:
	for i in 100:
		if (not (await _player(n)).is_empty()) == present:
			return true
		await get_tree().create_timer(0.05).timeout
	return false


func _wait(cond: Callable, secs := 8.0) -> bool:
	var t := 0.0
	while not cond.call() and t < secs:
		await get_tree().create_timer(0.05).timeout
		t += 0.05
	return cond.call()


func _offline() -> void:
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": true})
	Online._probe()
	await _wait(func(): return not Online.is_online())


func _online() -> void:
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": false})
	Online._probe()
	await _wait(func(): return Online.is_online())


func _cases() -> void:
	Online.enabled = true
	Online.url = BASE
	check(Game.profiles_path().contains("_smoke") and Game.profile_dir().contains("/_smoke/"), "test profiles live in the SMOKE namespace: %s" % Game.profiles_path())
	await _offline()

	# --- local: create, switch, rename, delete (no registration involved)
	var a := Profiles.create("Alpha", 3)
	var b := Profiles.create("Bravo", 7)
	check(Game.profiles["last"] == b, "new profile is active")
	check(Profiles.find(a)["avatar"] == 3 and Profiles.find(a)["enlisted"], "profile stored")
	Game.switch_profile(a)
	check(Game.profiles["last"] == a, "switched")
	Profiles.edit(a, "Alpha2", 5)
	check(Profiles.find(a)["name"] == "Alpha2" and Profiles.find(a)["avatar"] == 5, "rename + portrait")
	DirAccess.make_dir_recursive_absolute(Game.profile_dir_of(b))
	FileAccess.open(Game.profile_dir_of(b) + "meta.json", FileAccess.WRITE).store_string("{}")
	check(await Profiles.delete(b) == "", "local profile: deleted without a server call")
	check(Profiles.find(b).is_empty() and not DirAccess.dir_exists_absolute(Game.profile_dir_of(b)), "deleted with folder")
	check(Game.profiles["last"] == a, "active stays")
	await Profiles.delete(a)
	check(not Game.profiles["list"].any(func(p): return p["id"] in [a, b]), "both gone")

	# --- form: name feedback, submit while offline
	var ui := ProfileUi.new()
	add_child(ui)
	await get_tree().process_frame
	var n0: int = Game.profiles["list"].size()
	ui.enlist()
	check(ui.visible and ui.ok_btn.disabled, "empty name: ENLIST disabled")
	ui.name_edit.text = "ab"
	ui.name_edit.text_changed.emit("ab")
	check(ui.check.text == "Name must be 3-16 characters.", "length feedback: " + ui.check.text)
	ui.name_edit.text = "Hitler"
	ui.name_edit.text_changed.emit("Hitler")
	check(ui.check.text == "That name is not allowed." and ui.ok_btn.disabled, "banned feedback")
	ui.name_edit.text = "Ace_77"
	ui.name_edit.text_changed.emit("Ace_77")
	check(ui.check.text == "Name OK" and not ui.ok_btn.disabled, "ok feedback")
	ui.picked = 4
	ui._submit()
	check(await _wait(func(): return not ui.busy), "offline submit finishes (no stuck 'Contacting HQ')")
	check(Game.profiles["list"].size() == n0 + 1, "profile created offline")
	var p := Profiles.active()
	var ace: String = p["id"]
	check(p["name"] == "Ace_77" and p["avatar"] == 4 and not Online.is_registered() and Profiles.needs_push(p), "offline: local, not registered, push pending")
	check(not ui.visible, "form closed")

	# --- title: the pending profile is registered when the connection comes back; offline notice follows online_changed
	var title: CanvasLayer = preload("res://scripts/title_ui.gd").new()
	add_child(title)
	await get_tree().process_frame
	title.open()
	check(await _wait(func(): return not Profiles._busy), "title push offline ends")
	check(not Online.is_registered(), "still local while offline")
	await _online()
	check(await _wait(func(): return Online.is_registered()), "registered when online_changed(true) fires")
	check(await _server_has("Ace_77") and Profiles.find(ace)["synced"]["name"] == "Ace_77", "server has Ace_77, profile knows it is synced")
	check(not Profiles.needs_push(Profiles.find(ace)) and Profiles.registered(ace), "registered() reads auth.json")
	await _offline()
	check(title.online_notice.visible and title.online_notice.text == Online.NOTICE, "title shows the offline notice")
	Profiles.edit(ace, "Ace_88", 9) # renamed offline
	check(Profiles.needs_push(Profiles.find(ace)), "offline rename is pending")
	await _online()
	check(await _server_has("Ace_88"), "pending rename pushed on reconnect")
	check((await _player("Ace_88"))["avatar"] == 9 and (await _player("Ace_77")).is_empty(), "portrait pushed too")
	check(await _wait(func(): return not Profiles._busy) and not title.online_notice.visible, "notice gone when online")

	# --- online form: name_taken undoes, register ok, rename + portrait sync, rename rejected
	var rival := await _req(HTTPClient.METHOD_POST, "/auth/v1/signup")
	var rival_tok: String = rival["data"]["access_token"]
	var rival_id: String = rival["data"]["user"]["id"]
	await _req(HTTPClient.METHOD_POST, "/rest/v1/rpc/register_player", {"p_name": "Rival", "p_avatar": 1}, ["Authorization: Bearer " + rival_tok])
	var prev: String = Game.profiles["last"]
	var n1: int = Game.profiles["list"].size()
	ui.enlist()
	ui.name_edit.text = "Rival"
	ui.picked = 2
	ui._submit()
	check(await _wait(func(): return not ui.busy), "name_taken answered")
	check(Game.profiles["list"].size() == n1 and Game.profiles["last"] == prev, "name_taken: nothing created, previous profile active")
	check(ui.visible and ui.check.text == Online.error_text("name_taken"), "name_taken message: " + ui.check.text)
	ui.name_edit.text = "Fresh One"
	ui._submit()
	check(await _wait(func(): return not ui.busy), "register answered")
	var qid: String = Game.profiles["last"] # switch_profile reloads profiles.json: look the dict up each time
	check(Profiles.find(qid)["name"] == "Fresh One" and Online.is_registered() and await _server_has("Fresh One"), "registered online")
	ui.enlist(qid)
	ui.name_edit.text = "Fresh Two"
	ui.picked = 6
	ui._submit()
	check(await _wait(func(): return not ui.busy), "rename answered")
	var sp := await _player("Fresh Two")
	check(not sp.is_empty() and sp["avatar"] == 6, "rename + portrait synced: %s" % [sp])
	ui.enlist(qid)
	ui.name_edit.text = "Rival"
	ui.picked = 1
	ui._submit()
	check(await _wait(func(): return not ui.busy), "rejected rename answered")
	var q := Profiles.find(qid)
	check(q["name"] == "Fresh Two" and q["avatar"] == 6 and ui.check.text == Online.error_text("name_taken"), "rejected rename undone: %s / %s" % [q["name"], ui.check.text])
	ui.close()

	# --- delete: online registered profile leaves the server, offline one only locally
	ui.ask_delete(qid)
	check(ui.confirm.dialog_text.contains("removed from the leaderboard"), "delete text online: " + ui.confirm.dialog_text)
	ui._delete()
	check(await _wait(func(): return Profiles.find(qid).is_empty()), "deleted through the list")
	check(await _server_has("Fresh Two", false), "delete_me removed it from the server")
	ui.close()
	await _offline()
	Game.switch_profile(ace)
	ui.ask_delete(ace)
	check(ui.confirm.dialog_text.contains("stays online"), "delete text offline: " + ui.confirm.dialog_text)
	check(await Profiles.delete(ace) == "offline", "offline delete reports the error")
	check(Profiles.find(ace).is_empty() and await _server_has("Ace_88"), "offline delete: gone locally, online entry stays")
	ui.close()

	# --- leaderboard through the real Online
	var boss := Profiles.create("Boss", 2)
	await _online()
	check(await Profiles.push(Profiles.find(boss)) == "" and Online.is_registered(), "Boss registered")
	await Online.begin_run()
	Online.end_run(4, 7, 30, true)
	check(await _wait(func(): return Online._outbox.is_empty() and not Online._flushing), "Boss run sent")
	var lb := LeaderboardUi.new()
	add_child(lb)
	await get_tree().process_frame
	lb.open()
	lb.show_player({"player_id": rival_id, "name": "Rival"})
	check(await _wait(func(): return lb.detail.text == "No runs on the boards yet."), "player without runs: " + lb.detail.text)
	var run_body := {"p_run_id": "11111111-1111-4111-8111-111111111111", "p_day": 5, "p_rescued": 2, "p_kills": 10, "p_ended": true, "p_victory": false, "p_modifiers": [], "p_version": "0"}
	await _req(HTTPClient.METHOD_POST, "/rest/v1/rpc/upsert_run", run_body, ["Authorization: Bearer " + rival_tok])
	lb.show_kind("points")
	check(await _wait(func(): return lb.list.get_child_count() == 2 and lb.status.text == ""), "points board loads: %s / %d rows" % [lb.status.text, lb.list.get_child_count()])
	check(lb.own_slot.get_child_count() == 1 and lb.own_id == Online.player_id(), "own row pinned")
	lb.show_player({"player_id": rival_id, "name": "Rival"})
	check(await _wait(func(): return lb.detail.text.contains("Days survived")), "breakdown loads: " + lb.detail.text)
	check(not lb.detail.text.contains("Runs") and not lb.detail.text.contains("Victories") and lb.detail.text.contains("day 5"), "other player: no runs / wins, best run day 5: " + lb.detail.text)
	lb.show_player({"player_id": Online.player_id(), "name": "Boss"})
	check(await _wait(func(): return lb.detail.text.contains("Victories")), "own breakdown loads: " + lb.detail.text)
	check(lb.detail.text.contains("Runs") and lb.detail.text.contains("day 4, victory"), "own breakdown has runs and best run: " + lb.detail.text)
	lb.show_kind("days") # quick switching: the answer of the last request is shown
	lb.show_kind("rescued")
	check(await _wait(func(): return lb.list.get_child_count() == 2 and lb.status.text == ""), "quick tab switch does not hang: " + lb.status.text)
	await _offline()
	lb.show_kind("kills")
	check(await _wait(func(): return lb.status.text == "Leaderboard offline."), "offline view: " + lb.status.text)
	check(lb.list.get_child_count() >= 3 and lb.own_slot.get_child_count() == 0, "offline view shows the local record")
	await _online()
	check(await _wait(func(): return lb.list.get_child_count() == 2 and lb.status.text == ""), "board reloads when the connection returns: " + lb.status.text)

	# --- rendering: 50 rows, own row below the top 50, highlight, best run text
	var rows: Array = []
	for i in 50:
		rows.append({"rank": i + 1, "player_id": "id%d" % i, "name": "Player%d" % i, "avatar": i % 12, "value": 5000 - i * 10})
	lb.show_rows("points", rows, {"rank": 77, "player_id": "me", "name": "Me", "avatar": 1, "value": 120})
	check(lb.list.get_child_count() == 50 and lb.own_slot.get_child_count() == 1 and lb.own_id == "me", "50 rows + pinned own row")
	lb.show_rows("days", rows, {"rank": 3, "player_id": "id2", "name": "Player2", "avatar": 2, "value": 4980})
	var hl: Button = lb.list.get_child(2)
	check((hl.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left == 4, "own row highlighted in the list")
	lb.show_rows("best_run", [{"rank": 1, "player_id": "x", "name": "Top", "avatar": 0, "value": 9000, "day": 30, "victory": true}], {})
	check((lb.list.get_child(0).get_child(0).get_child(3) as Label).text.contains("day 30 WIN"), "best run shows day + win")
	lb.close()

	# --- title wiring: L key, overlays block starting
	title.open()
	title.profile_ui.close()
	title.board_ui.close()
	var key := InputEventKey.new()
	key.keycode = KEY_L
	key.pressed = true
	title._input(key)
	check(title.board_ui.visible, "L opens the leaderboard")
	title._start()
	check(title.visible, "overlay blocks starting")
	title.board_ui._input(key)
	check(not title.board_ui.visible, "L closes it again")
	await Profiles.delete(boss)
