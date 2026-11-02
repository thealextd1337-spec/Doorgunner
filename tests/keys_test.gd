extends Node
## Key remapping, F1 help / codex and tooltips (Q6b): SMOKE=keys godot --headless --path . --quit-after 30000
## Every action is listed in the key menu, defaults share no keys by accident, a rebinding works at once, keeps the default's
## keycode / physical semantics, survives a settings.json reload and shows up on the F1 page; conflicts are reported, "reset"
## restores everything; codex unlocks persist per profile; every button of the base menu (and the title) has a tooltip.
## Works on a settings file in the smoke profile; the player's settings.json is never written.

var _bad: PackedStringArray = []
var main: Node2D
var keys_ui: CanvasLayer
var codex_ui: CanvasLayer


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _key(code: Key, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	return e


func _mouse(button: MouseButton, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	return e


func _rebind(action: String, index: int, raw: InputEvent) -> bool:
	keys_ui.begin(action, index)
	return keys_ui.bind(raw)


func _run() -> void:
	main = Game.world
	var frame := get_tree().process_frame
	await frame
	var real_path := Settings.path
	Settings.path = Game.profile_dir() + "keys_test.json"
	DirAccess.make_dir_recursive_absolute(Game.profile_dir())
	DirAccess.remove_absolute(Settings.path)
	Settings.load_file()
	KeyMap.reset()
	keys_ui = main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/settings_ui.gd"))[0].keys_ui
	codex_ui = main.codex_ui

	# --- the menu lists every action, the defaults conflict with nothing
	var listed := KeyMap.actions()
	for a in InputMap.get_actions():
		if not a.begins_with("ui_") and not a.begins_with("spatial_editor") and not a.begins_with("input_"):
			check(a in listed, "action %s is in the key menu" % a)
	for a in listed:
		check(InputMap.has_action(a) and not KeyMap.events_of(a).is_empty(), "%s has a default binding" % a)
		check(KeyMap.conflicts(a).is_empty(), "defaults: %s shares no key by accident: %s" % [a, KeyMap.conflicts(a)])
	check(InputMap.event_is_action(_key(KEY_F1), "help"), "F1 is the help key")
	check(keys_ui.rows.size() == listed.size(), "one row per action")

	# --- rebinding works at once, B no longer founds the base
	check(_rebind("found", 0, _key(KEY_K)), "rebind found to K")
	check(InputMap.event_is_action(_key(KEY_K), "found") and not InputMap.event_is_action(_key(KEY_B), "found"), "K founds, B does not")
	check(InputMap.event_is_action(_key(KEY_B), "banish"), "banish (a card key) still on B")
	check(KeyMap.text("found") == "K" and keys_ui.rows["found"]["warn"].text == "", "row text, no conflict")
	check(KeyMap.conflicts("found").is_empty(), "K is free")
	# semantics: found is a physical key, mute binds by keycode
	var fe: InputEventKey = KeyMap.events_of("found")[0]
	check(fe.physical_keycode == KEY_K and fe.keycode == 0, "WASD-style actions stay physical keys")
	check(_rebind("mute", 0, _key(KEY_N)), "rebind mute to N")
	var me: InputEventKey = KeyMap.events_of("mute")[0]
	check(me.keycode == KEY_N and me.physical_keycode == 0, "hotkeys stay keycode keys")
	# mouse button, extra binding, things that cannot be bound
	check(_rebind("weapon_swap", -1, _mouse(MOUSE_BUTTON_MIDDLE)) and KeyMap.events_of("weapon_swap").size() == 2, "add a mouse button as a second binding")
	check(InputMap.event_is_action(_mouse(MOUSE_BUTTON_MIDDLE), "weapon_swap") and InputMap.event_is_action(_key(KEY_X), "weapon_swap"), "middle mouse and X switch the gun")
	check(not _rebind("weapon_swap", -1, _key(KEY_SHIFT)), "a modifier alone cannot be bound")
	check(not _rebind("weapon_swap", -1, _key(KEY_Y, false)), "a release cannot be bound")
	keys_ui.remove("weapon_swap", 1)
	check(KeyMap.events_of("weapon_swap").size() == 1, "removing a binding")
	check(_rebind("move_up", 1, _key(KEY_I)) and InputMap.event_is_action(_key(KEY_W), "move_up") and InputMap.event_is_action(_key(KEY_I), "move_up")
		and not InputMap.event_is_action(_key(KEY_UP), "move_up"), "replace only the second of the two move_up keys")

	# --- conflicts: weapon_swap on K collides with found, R/S/B/SPACE/1-9 sharing stays quiet
	check(_rebind("weapon_swap", 0, _key(KEY_K)), "weapon_swap to K")
	check(KeyMap.conflicts("weapon_swap") == ["Found the base"] and KeyMap.conflicts("found") == ["Switch gun"], "K is shared: both report it")
	check(keys_ui.rows["found"]["warn"].text.contains("Switch gun") and keys_ui.rows["weapon_swap"]["warn"].text.contains("Found the base"), "the rows show the conflict")
	check(keys_ui.status.text.contains("Conflicts: 2"), "the header counts them")
	check(KeyMap.conflicts("restart").is_empty() and KeyMap.conflicts("skip").is_empty(), "R and S shared by default are no conflict")

	# --- saved in settings.json, loaded again at boot
	Settings.save()
	var file = JSON.parse_string(FileAccess.get_file_as_string(Settings.path))
	check(file is Dictionary and file.get("keys", {}).get("found") == ["p%d" % KEY_K] and file["keys"].get("mute") == ["k%d" % KEY_N], "settings.json holds the bindings")
	check(not file["keys"].has("restart") and not file["keys"].has("land"), "only changed actions are stored")
	for a in ["found", "mute", "weapon_swap", "move_up"]: # forget the live state, then boot from the file
		KeyMap._apply(a, KeyMap.defaults[a])
	check(InputMap.event_is_action(_key(KEY_B), "found"), "(live state forgotten)")
	Settings.load_file()
	KeyMap.apply_saved()
	check(InputMap.event_is_action(_key(KEY_K), "found") and not InputMap.event_is_action(_key(KEY_B), "found"), "found is on K after a reload")
	check(KeyMap.events_of("mute")[0].keycode == KEY_N and InputMap.event_is_action(_key(KEY_I), "move_up"), "mute and move_up too")
	# garbage in the file never breaks the defaults
	Settings.set_extra("keys", {"found": ["junk", 5, "p"], "land": "x", "nonsense": ["p1"]})
	KeyMap.apply_saved()
	check(KeyMap.events_of("found").is_empty() and InputMap.event_is_action(_key(KEY_SPACE), "land"), "bad entries: nothing bound, a bad list keeps the default")
	Settings.load_file()
	KeyMap.apply_saved()

	# --- F1: the page shows the new binding, the key itself opens and closes it
	main.ui_open = false
	_press(KEY_F1)
	await frame
	check(codex_ui.visible and get_tree().paused, "F1 opens the help and pauses")
	check(_page_has("Found the base", "K"), "the Controls page shows found = K")
	check(_page_has("Help & codex", "F1"), "...and F1 for the help itself")
	check(not _texts(codex_ui.content).any(func(t): return t.begins_with("Touch controls")) and not Controls.touch, "no touch section in mouse mode")
	Controls.touch = true
	codex_ui.show_page("Controls")
	check(_texts(codex_ui.content).any(func(t): return t == "TOUCH CONTROLS"), "touch mode adds the touch controls")
	Controls.touch = false
	_press(KEY_F1)
	await frame
	check(not codex_ui.visible and not get_tree().paused, "F1 closes it again")
	KeyMap.set_bindings("help", [_key(KEY_F5)])
	_press(KEY_F1)
	await frame
	check(not codex_ui.visible, "after rebinding help, F1 does nothing")
	_press(KEY_F5)
	await frame
	check(codex_ui.visible and _page_has("Help & codex", "F5") and codex_ui.hint.text.contains("F5"), "the new help key opens it and is shown")
	codex_ui.show_page("Enemies")
	check(_texts(codex_ui.content).has("Nothing to read here yet."), "empty category says so")
	codex_ui.close()
	check(not get_tree().paused and not main.ui_open, "closing restores pause and ui_open")

	# --- the live key hints follow a rebinding: HUD hint line, outpost / protect hints, base menu toggle
	check(_rebind("land", 0, _key(KEY_U)) and _rebind("outpost", 0, _key(KEY_Y)) and _rebind("base_menu", 0, _key(KEY_KP_5)), "rebind land, outpost, base menu")
	main.outposts._ctx = {"o": "found an outpost", "p": true}
	check(main.outposts.hint().contains("[Y] found an outpost") and main.outposts.hint().contains("[P] protect"), "outpost hints show the keys: " + main.outposts.hint())
	Game.heli.landed = true
	await frame
	check(main.hud.hint.text.begins_with("[U] take off") or main.hud.hint.text == "spooling...", "HUD hint shows the new land key: " + main.hud.hint.text)
	Game.heli.landed = false
	await frame
	check(main.hud.hint.text.begins_with("[U] land") and main.hud.hint.text.contains("[Mouse left] fire"), "...in flight too: " + main.hud.hint.text)
	main.outposts._ctx = {}
	main.base.ui.refresh()
	check(main.base.ui.toggle_btn.text.ends_with("[Kp 5]"), "base menu toggle shows the new key: " + main.base.ui.toggle_btn.text)

	# --- reset to defaults
	keys_ui.reset_all()
	check(InputMap.event_is_action(_key(KEY_B), "found") and not InputMap.event_is_action(_key(KEY_K), "found"), "reset: B founds again")
	check(KeyMap.events_of("mute")[0].keycode == KEY_M and InputMap.event_is_action(_key(KEY_UP), "move_up") and InputMap.event_is_action(_key(KEY_F1), "help"), "reset: all defaults")
	check(Settings.get_extra("keys", {"x": 1}).is_empty() and listed.all(func(a): return KeyMap.is_default(a) and KeyMap.conflicts(a).is_empty()), "reset: nothing stored, no conflict")

	# --- capture through the real input path: ESC cancels, a key binds and never reaches the game
	keys_ui.open()
	keys_ui.begin("found", 0)
	_press(KEY_ESCAPE)
	check(keys_ui.capturing == "" and keys_ui.visible and InputMap.event_is_action(_key(KEY_B), "found"), "ESC cancels the capture only")
	keys_ui.begin("found", 0)
	_press(KEY_V)
	check(keys_ui.capturing == "" and InputMap.event_is_action(_key(KEY_V), "found"), "a pressed key binds")
	keys_ui.begin("found", 0)
	_press(KEY_F1)
	check(keys_ui.capturing == "" and InputMap.event_is_action(_key(KEY_F1), "found") and not codex_ui.visible, "F1 while capturing binds, the codex stays shut")
	_press(KEY_F1)
	check(not codex_ui.visible, "no codex under the open key screen")
	_press(KEY_ESCAPE)
	check(not keys_ui.visible, "ESC closes the key screen")
	keys_ui.reset_all()

	# --- robustness: ESC menu and help keep one key, junk under "keys", every change is on disk at once
	check(not keys_ui.remove("menu", 0) and not KeyMap.events_of("menu").is_empty(), "the last ESC menu key cannot be removed")
	check(not keys_ui.remove("help", 0) and InputMap.event_is_action(_key(KEY_F1), "help"), "the last help key cannot be removed")
	check(keys_ui.status.text.contains("needs at least one key"), "...and the screen says why")
	check(_rebind("help", -1, _key(KEY_F2)) and keys_ui.remove("help", 0) and KeyMap.text("help") == "F2", "with a second key the first can go")
	Settings.set_extra("keys", "junk")
	check(_rebind("found", 0, _key(KEY_K)) and Settings.get_extra("keys", {}).get("found") == ["p%d" % KEY_K], "a non-dictionary \"keys\" is replaced, not a crash")
	file = JSON.parse_string(FileAccess.get_file_as_string(Settings.path))
	check(file is Dictionary and file.get("keys", {}).get("found") == ["p%d" % KEY_K], "a rebind is saved without Settings.save()")
	keys_ui.reset_all()
	file = JSON.parse_string(FileAccess.get_file_as_string(Settings.path))
	check(file is Dictionary and file.get("keys") == {}, "reset is saved at once")

	# --- codex: register, unlock, persists per profile
	if not Codex.entries.has("t_walker"):
		Codex.register("Enemies", "t_walker", "Walker", "Slow, many, patient.")
	if not Codex.entries.has("t_sandbag"):
		Codex.register("Buildings", "t_sandbag", "Sandbag post", "Stops them for a while.")
	var home: String = Game.profiles["last"]
	var a := Profiles.create("Keys_A", 1)
	var b := Profiles.create("Keys_B", 2)
	Game.switch_profile(a)
	check(not Codex.is_unlocked("t_walker") and Codex.ids_unlocked().is_empty(), "a new profile knows nothing")
	check(Codex.unlock("t_walker") and not Codex.unlock("t_walker"), "unlock is true once")
	Game.meta["codex"] = ""
	Game._load_meta() # as after a restart: meta.json is read again
	check(Codex.is_unlocked("t_walker") and not Codex.is_unlocked("t_sandbag"), "the unlock survives a reload of meta.json")
	Game.switch_profile(b)
	check(not Codex.is_unlocked("t_walker"), "another profile has not unlocked it")
	Codex.unlock("t_sandbag")
	Game.switch_profile(a)
	check(Codex.is_unlocked("t_walker") and not Codex.is_unlocked("t_sandbag"), "...and a's unlocks are its own")
	codex_ui.open()
	codex_ui.show_page("Enemies")
	var ts := _texts(codex_ui.content)
	check(ts.has("Walker") and ts.has("Slow, many, patient."), "an unlocked entry shows on its page")
	codex_ui.show_page("Buildings")
	ts = _texts(codex_ui.content)
	check(not ts.has("Sandbag post") and ts.any(func(t): return t.begins_with("???")), "a locked entry shows as ???")
	codex_ui.close()
	Game.switch_profile(home)
	await Profiles.delete(a)
	await Profiles.delete(b)
	Codex.entries.erase("t_walker")
	Codex.entries.erase("t_sandbag")

	# --- tooltips: every button and drop-down of the base menu, in a state that shows all kinds of rows
	var base: Node2D = main.base
	Game.scrap = 500
	Game.rescued = 3
	Game.weapon_bay.append("minigun")
	Game.heli_items["searchlight"] = 1
	Game.recompute()
	var fleet: Node = base.ui.find_children("*", "VBoxContainer", true, false).filter(func(c): return c.get_script() == preload("res://scripts/fleet_ui.gd"))[0]
	var w: Node = main.wrecks
	w.wrecks["t_wreck"] = {"type": "huey", "pos": Vector2.ZERO, "rot": 0.0, "cond": 0.5, "keys": [], "state": "base", "progress": 0.0, "days": 2, "heli": {}}
	w.wrecks["t_parked"] = {"type": "huey", "pos": Vector2.ZERO, "rot": 0.0, "cond": 1.0, "keys": [], "state": "parked", "progress": 0.0, "days": 0, "heli": {}}
	base.ui.open()
	base.ui.refresh()
	fleet._build(w)
	var buttons: Array = base.ui.find_children("*", "BaseButton", true, false) + base.ui.find_children("*", "OptionButton", true, false)
	var missing: Array = buttons.filter(func(c): return c.tooltip_text == "")
	check(buttons.size() > 60, "found the base menu buttons: %d" % buttons.size())
	check(missing.is_empty(), "buttons without a tooltip: " + ", ".join(missing.map(func(c): return "%s '%s'" % [c.get_class(), c.get("text")])))
	var tips := fleet.find_children("*", "Button", true, false)
	check(tips.size() >= 2 and tips.all(func(c): return c.tooltip_text != ""), "fleet buttons: %d, all with tooltips" % tips.size())
	w.wrecks.erase("t_wreck")
	w.wrecks.erase("t_parked")
	base.ui.close()
	# the table: every job, upgrade, building, item and modifier has text; item tooltips carry level 1 and 5
	for j in base.ui.JOBS:
		check(Tooltips.TIPS.has("job_" + j), "tooltip for job " + j)
	for u in base.ui.UPGRADES.keys() + ["repair"]:
		check(Tooltips.TIPS.has("buy_" + u), "tooltip for upgrade " + u)
	for k in base.ui.BUILD_INFO:
		check(Tooltips.building(k) != "", "tooltip for building " + k)
	for k in base.ui.LOADOUT:
		check(Tooltips.TIPS.has("loadout_" + k), "tooltip for loadout " + k)
	for id in Progression.ITEMS:
		check(Tooltips.item(id).contains("Lv 5: "), "tooltip for item " + id)
	for id in Tooltips.Mods.TABLE:
		check(Tooltips.modifier(id).contains("Score x"), "tooltip for modifier " + id)
	check(Tooltips.TIPS.size() >= 80, "tooltip table size %d" % Tooltips.TIPS.size())

	# restore the real settings
	DirAccess.remove_absolute(Settings.path)
	Settings.path = real_path
	Settings.load_file()
	KeyMap.apply_saved()
	Settings.set_value("muted", 1)
	Sfx.apply_volumes()
	if _bad.is_empty():
		print("KEYS OK  actions=%d tooltips=%d buttons=%d" % [listed.size(), Tooltips.TIPS.size(), buttons.size()])
		get_tree().quit(0)
	else:
		for m in _bad:
			push_error("KEYS FAIL: " + m)
		get_tree().quit(1)


## A key press through the real input path (viewport -> _input -> _unhandled_input).
func _press(code: Key) -> void:
	Input.parse_input_event(_key(code))
	Input.flush_buffered_events()
	Input.parse_input_event(_key(code, false))
	Input.flush_buffered_events()


func _texts(n: Node) -> Array:
	return n.find_children("*", "Label", true, false).map(func(l): return l.text)


## A grid row: a Label `left` followed by a Label `right` (the Controls page).
func _page_has(left: String, right: String) -> bool:
	var labels: Array = codex_ui.content.find_children("*", "Label", true, false)
	for i in labels.size() - 1:
		if labels[i].text == left and labels[i + 1].text == right:
			return true
	return false
