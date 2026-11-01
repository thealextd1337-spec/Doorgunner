extends Node
## Settings registry test (Q0): SMOKE=settings godot --headless --path . --quit-after 30000
## Built-in keys, an old-format settings.json, registering late, type coercion, persisting (unknown keys kept), the
## change signal and the ESC menu building one row per key. Works on a file in the smoke profile; the player's
## settings.json is never written and the registry is restored at the end.

var _bad: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	var keys := ["vol_master", "vol_sfx", "vol_music", "muted", "shake"]
	check(Settings.defs.keys().slice(0, 5) == keys, "built-in keys registered in menu order")
	check(Settings.defs["vol_music"]["default"] == 70 and Settings.defs["muted"]["default"] == 1, "built-in defaults")
	var real_path := Settings.path
	Settings.path = Game.profile_dir() + "settings_test.json"
	DirAccess.make_dir_recursive_absolute(Game.profile_dir())
	# a settings.json as 1.0.0-beta wrote it, plus a key of a package that is not registered (yet)
	FileAccess.open(Settings.path, FileAccess.WRITE).store_string(
		'{"vol_master":80,"vol_sfx":55,"vol_music":30,"muted":0,"shake":0,"q0_late":0,"q0_unknown":"x"}')
	Settings.load_file()
	check(Settings.get_value("vol_master") == 80 and Settings.get_value("vol_sfx") is int, "old file: ints stay ints")
	check(Settings.get_value("vol_music") == 30 and not Settings.is_on("muted") and not Settings.is_on("shake"), "old file read")
	Settings.register_toggle("q0_late", "Late toggle", true)
	check(Settings.get_value("q0_late") == 0, "a key registered after loading gets its saved value")
	Settings.register_slider("q0_scale", "UI scale", 0.9, 1.5, 0.1, 1.0)
	check(Settings.get_value("q0_scale") == 1.0, "unsaved key starts at its default")
	var seen := []
	var on_change := func(k: String, v: Variant): seen.append([k, v])
	Settings.changed.connect(on_change)
	Settings.set_value("vol_sfx", 150.0)
	Settings.set_value("shake", true)
	Settings.set_value("q0_scale", 1.23)
	Settings.changed.disconnect(on_change)
	check(Settings.get_value("vol_sfx") == 100 and Settings.get_value("vol_sfx") is int, "slider clamped, int kept")
	check(Settings.get_value("shake") == 1 and Settings.is_on("shake"), "bool stored as 1")
	check(is_equal_approx(Settings.get_value("q0_scale"), 1.2), "float slider snapped to its step")
	check(seen == [["vol_sfx", 100], ["shake", 1], ["q0_scale", Settings.get_value("q0_scale")]], "change signal: %s" % [seen])
	Settings.save()
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Settings.path))
	check(saved is Dictionary and saved.get("q0_unknown") == "x", "unregistered keys survive a save")
	check(saved is Dictionary and int(saved.get("vol_sfx", 0)) == 100 and int(saved.get("q0_late", 1)) == 0 and saved.has("q0_scale"), "every registered key saved")
	Settings.set_value("vol_master", 10)
	Settings.load_file()
	check(Settings.get_value("vol_master") == 80 and Settings.get_value("vol_sfx") == 100, "reload from file")
	# the ESC menu: one row per registered key, right control type, current value shown
	var ui: CanvasLayer = preload("res://scripts/settings_ui.gd").new()
	add_child(ui)
	check(ui.rows.size() == Settings.defs.size(), "one row per key (%d/%d)" % [ui.rows.size(), Settings.defs.size()])
	check(ui.rows["shake"] is CheckButton and ui.rows["shake"].button_pressed, "toggle row")
	check(ui.rows["vol_sfx"] is HSlider and ui.rows["vol_sfx"].value == 100, "slider row")
	check(ui.rows["q0_scale"].step == 0.1 and is_equal_approx(ui.rows["q0_scale"].value, 1.2), "slider range from the registry")
	ui.rows["q0_late"].button_pressed = true
	check(Settings.get_value("q0_late") == 1, "toggling the row sets the value")
	ui.free()
	# restore the registry and the real values
	for k in ["q0_late", "q0_scale"]:
		Settings.defs.erase(k)
		Settings.values.erase(k)
	DirAccess.remove_absolute(Settings.path)
	Settings.path = real_path
	Settings.load_file()
	Settings.set_value("muted", 1)
	Sfx.apply_volumes()
	if _bad.is_empty():
		print("SETTINGS OK  keys=%d" % Settings.defs.size())
		get_tree().quit(0)
	else:
		for b in _bad:
			push_error("SETTINGS FAIL: " + b)
		get_tree().quit(1)
