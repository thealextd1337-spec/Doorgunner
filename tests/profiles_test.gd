extends Node
## Profiles + leaderboard UI test: SMOKE=profiles godot --headless --path . --quit-after 30000
## Creates / switches / renames / deletes profiles (meta stays separate), name feedback in the form, leaderboard rows from fake
## data, a fake Online for the register / name_taken / board / player paths. profiles.json is restored at the end.


class FakeOnline extends Node:
	signal done(ok: bool, error: String)
	signal board(rows: Array, own_row: Dictionary)
	signal player(stats: Dictionary)
	var calls: Array = []
	var next_error := ""
	var rows: Array = []
	var own: Dictionary = {}

	func is_online() -> bool:
		return true

	func register(n: String, a: int) -> void:
		calls.append(["register", n, a])
		_answer.call_deferred()

	func rename(n: String) -> void:
		calls.append(["rename", n])
		_answer.call_deferred()

	func set_avatar(a: int) -> void:
		calls.append(["set_avatar", a])
		_answer.call_deferred()

	func delete_me() -> void:
		calls.append(["delete_me"])
		_answer.call_deferred()

	func fetch_board(kind: String, limit: int) -> void:
		calls.append(["board", kind, limit])
		board.emit.call_deferred(rows, own)

	func fetch_player(id) -> void:
		calls.append(["player", id])
		player.emit.call_deferred({"points": 4321, "days": 12, "rescued": 99, "kills": 800, "runs": 7, "wins": 1, "best_run": 2500})

	func _answer() -> void:
		var e := next_error
		next_error = ""
		done.emit(e == "", e)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var frame := get_tree().process_frame
	await frame
	await frame
	var had_file := FileAccess.file_exists(Game.PROFILES_PATH)
	var saved_profiles := FileAccess.get_file_as_string(Game.PROFILES_PATH) if had_file else ""
	var before: Dictionary = Game.profiles.duplicate(true)

	# --- local: create, switch, rename, delete
	var a := Profiles.create("Alpha", 3)
	var b := Profiles.create("Bravo", 7)
	assert(Game.profiles["last"] == b, "new profile is active")
	assert(Profiles.find(a)["avatar"] == 3 and Profiles.find(a)["enlisted"], "profile stored")
	Game.switch_profile(a)
	assert(Game.profiles["last"] == a, "switched")
	Profiles.edit(a, "Alpha2", 5)
	assert(Profiles.find(a)["name"] == "Alpha2" and Profiles.find(a)["avatar"] == 5, "rename + portrait")
	DirAccess.make_dir_recursive_absolute(Game.profile_dir_of(b))
	FileAccess.open(Game.profile_dir_of(b) + "meta.json", FileAccess.WRITE).store_string("{}")
	await Profiles.delete(b)
	assert(Profiles.find(b).is_empty() and not DirAccess.dir_exists_absolute(Game.profile_dir_of(b)), "deleted with folder")
	assert(Game.profiles["last"] == a, "active stays")
	await Profiles.delete(a)
	assert(not Game.profiles["list"].any(func(p): return p["id"] in [a, b]), "both gone")

	# --- form: name feedback, submit offline
	var ui := ProfileUi.new()
	add_child(ui)
	await frame
	var n0: int = Game.profiles["list"].size()
	ui.enlist()
	assert(ui.visible and ui.ok_btn.disabled, "empty name: ENLIST disabled")
	ui.name_edit.text = "ab"
	ui.name_edit.text_changed.emit("ab")
	assert(ui.check.text == "Name must be 3-16 characters.", "length feedback: " + ui.check.text)
	ui.name_edit.text = "Hitler"
	ui.name_edit.text_changed.emit("Hitler")
	assert(ui.check.text == "That name is not allowed." and ui.ok_btn.disabled, "banned feedback")
	ui.name_edit.text = "Ace_77"
	ui.name_edit.text_changed.emit("Ace_77")
	assert(ui.check.text == "Name OK" and not ui.ok_btn.disabled, "ok feedback")
	ui.picked = 4
	ui._submit()
	for i in 3:
		await frame
	assert(Game.profiles["list"].size() == n0 + 1, "profile created offline")
	var p := Profiles.active()
	assert(p["name"] == "Ace_77" and p["avatar"] == 4 and not p.get("registered", false), "offline: local, not registered")
	assert(not ui.visible, "form closed")

	# --- list screen, delete via confirm
	ui.open_list()
	assert(ui.visible, "list opens")
	ui.ask_delete(p["id"])
	ui._delete()
	for i in 3:
		await frame
	assert(Profiles.find(p["id"]).is_empty(), "deleted through the list")
	ui.close()

	# --- online (fake): name_taken undoes, register ok, rename + portrait sync, delete_me
	var fake := FakeOnline.new()
	Profiles.fake = fake
	add_child(fake)
	var prev: String = Game.profiles["last"]
	var n1: int = Game.profiles["list"].size()
	fake.next_error = "name_taken"
	ui.enlist()
	ui.name_edit.text = "Taken"
	ui.picked = 2
	ui._submit()
	for i in 6:
		await frame
	assert(Game.profiles["list"].size() == n1 and Game.profiles["last"] == prev, "name_taken: nothing created, previous profile active")
	assert(ui.visible and ui.check.text == "That name is taken, pick another one.", "name_taken message: " + ui.check.text)
	ui.name_edit.text = "Fresh One"
	ui._submit()
	for i in 6:
		await frame
	var q := Profiles.active()
	assert(q["name"] == "Fresh One" and q["registered"], "registered online")
	assert(fake.calls.has(["register", "Fresh One", 2]), "register called")
	ui.enlist(q["id"])
	ui.name_edit.text = "Fresh Two"
	ui.picked = 6
	ui._submit()
	for i in 8:
		await frame
	assert(fake.calls.has(["rename", "Fresh Two"]) and fake.calls.has(["set_avatar", 6]), "rename + set_avatar sync: " + str(fake.calls))
	await Profiles.delete(q["id"])
	assert(fake.calls.has(["delete_me"]) and Profiles.find(q["id"]).is_empty(), "delete_me for a registered profile")

	# --- leaderboard: fake rows, own row below the top 50, highlight, detail, offline
	var lb := LeaderboardUi.new()
	add_child(lb)
	await frame
	var rows: Array = []
	for i in 50:
		rows.append({"rank": i + 1, "player_id": "id%d" % i, "name": "Player%d" % i, "avatar": i % 12, "value": 5000 - i * 10})
	lb.show_rows("points", rows, {"rank": 77, "player_id": "me", "name": "Me", "avatar": 1, "value": 120})
	await frame
	assert(lb.list.get_child_count() == 50 and lb.own_slot.get_child_count() == 1, "50 rows + pinned own row")
	assert(lb.own_id == "me", "own id")
	lb.show_rows("days", rows, {"rank": 3, "player_id": "id2", "name": "Player2", "avatar": 2, "value": 4980})
	await frame
	assert(lb.list.get_child_count() == 50 and lb.own_slot.get_child_count() == 1, "own row pinned and highlighted in the list too")
	var hl: Button = lb.list.get_child(2)
	assert((hl.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left == 4, "own row highlighted")
	lb.show_rows("best_run", [{"rank": 1, "player_id": "x", "name": "Top", "avatar": 0, "value": 9000, "day": 30, "victory": true}], {})
	await frame
	assert((lb.list.get_child(0).get_child(0).get_child(3) as Label).text.contains("day 30 WIN"), "best run shows day + win")
	fake.rows = rows
	fake.own = {"rank": 77, "player_id": "me", "name": "Me", "avatar": 1, "value": 120}
	lb.show_kind("kills")
	assert(lb.loading, "loading while waiting")
	for i in 4:
		await frame
	assert(not lb.loading and lb.list.get_child_count() == 50 and lb.own_slot.get_child_count() == 1 and fake.calls.has(["board", "kills", 50]), "board via Online")
	lb.show_player(rows[0])
	for i in 4:
		await frame
	assert(lb.detail.text.contains("Points") and lb.detail.text.contains("4321") and lb.detail.text.contains("Victories"), "breakdown: " + lb.detail.text)
	Profiles.fake = null
	fake.queue_free()
	lb.show_kind("points")
	assert(lb.status.text == "Leaderboard offline." and lb.list.get_child_count() >= 3, "offline view with local record")

	# --- title wiring: L key, overlays block starting
	var title: CanvasLayer = preload("res://scripts/title_ui.gd").new()
	add_child(title)
	await frame
	title.open()
	title.profile_ui.close()
	title.board_ui.close()
	var key := InputEventKey.new()
	key.keycode = KEY_L
	key.pressed = true
	title._input(key)
	assert(title.board_ui.visible, "L opens the leaderboard")
	title._start()
	assert(title.visible, "overlay blocks starting")
	title.board_ui._input(key)
	assert(not title.board_ui.visible, "L closes it again")

	# --- restore the real profile list
	if had_file:
		FileAccess.open(Game.PROFILES_PATH, FileAccess.WRITE).store_string(saved_profiles)
	else:
		DirAccess.remove_absolute(Game.PROFILES_PATH)
	Game.profiles = before
	print("PROFILES OK")
	get_tree().quit(0)
