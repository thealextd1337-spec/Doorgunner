extends Node
## UI theme and scale test (Q6a): SMOKE=uitheme godot --headless --path . --quit-after 30000
## At 90, 100 and 150 % UI scale the HUD zones, the touch layer, the base menu (every tab, the build bar), the title
## (with the hangar list), the ESC menu, the key bindings and the help / codex pages keep their controls on screen and apart (control rects compared pairwise).
## The scale is set in memory and Settings points at a file in the smoke profile: the player's settings.json is never written.

const SCALES := [90, 100, 150]

var _bad: PackedStringArray = []
var main: Node
var touch: CanvasLayer


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	main = Game.world
	touch = main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/touch_ui.gd"))[0]
	var real_path := Settings.path
	var start: int = Settings.get_value(UiTheme.SCALE_KEY)
	Settings.path = Game.profile_dir() + "uitheme_test.json"
	var def: Dictionary = Settings.defs.get(UiTheme.SCALE_KEY, {})
	check(def.get("kind") == "slider" and def.get("min") == 90 and def.get("max") == 150, "UI scale slider registered (90-150)")
	for i in 6: # a full, wrapping radio log and an alert line
		Game.radio("Command: radio line %d, long enough to wrap on a narrow screen at the larger UI scales of this test" % i)
	Profiles.active()["enlisted"] = true # in memory only: no ENLIST pop-up over the title
	for pct in SCALES:
		Settings.set_value(UiTheme.SCALE_KEY, pct)
		var s: float = pct / 100.0
		await _frames(3)
		check(is_equal_approx(main.hud.root.factor, s) and is_equal_approx(main.hud.root.size.x, 1280.0 / s), "HUD root at %d %%" % pct)
		check(is_equal_approx(touch.root.factor, minf(s, touch.MAX_SCALE)), "touch root capped at %d %%" % pct)
		# HUD in flight
		Game.heli.landed = false
		Game.fuel = Game.max_fuel * 0.1 # LOW FUEL alert
		await _frames(2)
		check(main.hud.alert.visible and main.hud.log_label.visible and main.hud.hint.visible, "HUD alert, log and hints shown at %d %%" % pct)
		_apart("HUD %d %%" % pct, _hud())
		# touch layer over the HUD, with two context buttons
		Controls.touch = true
		main.outposts._ctx = {"o": "outpost", "p": true}
		await _frames(2)
		check(touch.flight.visible and touch.context[1].visible, "touch pads up at %d %%" % pct)
		_apart("touch %d %%" % pct, _hud() + _layer(touch))
		check(main.hud.log_label.visible, "touch: the radio log still gets lines at %d %%" % pct)
		Controls.touch = false
		main.outposts._ctx = {}
		# base menu, every tab, with and without touch (TAKE OFF pad)
		Game.heli.landed = true
		main.base.ui.open()
		for tab in main.base.ui.tabs:
			main.base.ui.show_tab(tab)
			for on in [false, true]:
				Controls.touch = on
				await _frames(2)
				var what := "base %s %d %%%s" % [tab, pct, " touch" if on else ""]
				_apart(what, _hud() + _layer(main.base.ui) + (_layer(touch) if on else []))
				var box: Control = main.base.ui.tabs[tab].get_parent()
				check(main.base.ui.main_panel.get_global_rect().grow(0.5).encloses(box.get_global_rect()), what + ": tab inside the panel")
		Controls.touch = false
		check(main.base.ui.status_body[0].visible == (pct < 150), "status panel folds by itself only when narrow (%d %%)" % pct)
		main.base.placing = true # build bar
		await _frames(2)
		_apart("build bar %d %%" % pct, _hud() + _layer(main.base.ui))
		Controls.touch = true
		await _frames(2)
		_apart("build bar %d %% touch" % pct, _hud() + _layer(main.base.ui) + _layer(touch))
		Controls.touch = false
		main.base.ui.close()
		# ESC menu
		var esc: CanvasLayer = main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/settings_ui.gd"))[0]
		esc.visible = true
		await _frames(2)
		_apart("ESC menu %d %%" % pct, [["panel", esc.panel.get_global_rect()]])
		# key bindings (one row with four keys, the widest it gets in play) and every page of help / codex (Q6b)
		if pct != 100:
			var keys: CanvasLayer = esc.keys_ui
			for k in [KEY_KP_1, KEY_KP_2, KEY_KP_3]:
				var e := InputEventKey.new()
				e.keycode = k
				keys.begin("weapon_swap", -1)
				keys.bind(e)
			keys.open()
			keys.begin("found", 0) # "press a key..." is the widest button text
			await _frames(2)
			_apart("keys %d %%" % pct, [["keys.panel", keys.panel.get_global_rect()]])
			_inside("keys %d %%" % pct, keys.panel, keys.list)
			keys.reset_all()
			keys.close()
			esc.visible = false
			var codex: CanvasLayer = main.codex_ui
			codex.open()
			for page in [codex.CONTROLS] + Codex.CATEGORIES:
				codex.show_page(page)
				await _frames(2)
				_apart("codex %s %d %%" % [page, pct], [["codex.panel", codex.panel.get_global_rect()]])
				_inside("codex %s %d %%" % [page, pct], codex.panel, codex.panel)
			codex.close()
		esc.visible = false
		# title with the hangar list (laid out for the whole canvas: never above 100 %)
		var title: CanvasLayer = preload("res://scripts/title_ui.gd").new()
		main.add_child(title)
		title.open()
		await _frames(2)
		check(is_equal_approx(title.root.factor, minf(s, 1.0)), "title root capped at 100 %% (%d %%)" % pct)
		_apart("title %d %%" % pct, _title(title, [title.setup]))
		title._toggle_hangar()
		await _frames(2)
		_apart("title hangar %d %%" % pct, _title(title, [title.hangar]))
		var scroll: ScrollContainer = title.hangar_grid.get_parent()
		var fits: bool = title.hangar_grid.size.y <= scroll.size.y + 1.0
		check(fits or scroll.get_v_scroll_bar().max_value >= title.hangar_grid.size.y - 1.0, "hangar list fits or scrolls (%d %%)" % pct)
		check(pct < 100 or not fits, "hangar list scrolls at 100 %% (%d %%)" % pct)
		title.free()
	Game.running = true
	main.ui_open = false
	Settings.set_value(UiTheme.SCALE_KEY, start)
	DirAccess.remove_absolute(Settings.path)
	Settings.path = real_path
	for b in _bad:
		push_error("UITHEME FAIL: " + b)
	assert(_bad.is_empty(), "uitheme test failed: %s" % ", ".join(_bad))
	print("UITHEME %s  checks failed=%d" % ["OK" if _bad.is_empty() else "FAILED", _bad.size()])
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## [name, screen rect] of the visible HUD zones.
func _hud() -> Array:
	var h: CanvasLayer = main.hud
	var out := []
	for k in ["status_zone", "minimap", "alert", "log_label", "hint"]:
		var c: Control = h.get(k)
		if c.is_visible_in_tree() and not (c is Label and c.text == ""):
			out.append(["hud." + k, c.get_global_rect()])
	return out


## [name, screen rect] of a layer's visible obstacles (touch pads, base panels).
func _layer(l: CanvasLayer) -> Array:
	var out := []
	for c: Control in l.obstacles():
		if c.is_visible_in_tree():
			out.append(["%s.%s" % [l.get_script().resource_path.get_file().get_basename(), c.name if not c.name.begins_with("@") else c.get_class()], c.get_global_rect()])
	return out


func _title(t: CanvasLayer, right: Array) -> Array:
	var panel: Control = t.start_btn.get_parent().get_parent().get_parent() # button row > VBox > panel
	var out := [["title.panel", panel.get_global_rect()], ["title.badge", t.badge.get_global_rect()]]
	for c: Control in right:
		out.append(["title." + c.get_class(), c.get_global_rect()])
	return out


## Every rect on the 1280x720 canvas, no two overlapping (touching edges is fine).
func _apart(what: String, rects: Array) -> void:
	var screen := Rect2(Vector2.ZERO, UiTheme.CANVAS)
	for r in rects:
		if not screen.encloses(r[1].grow(-0.5)):
			check(false, "%s: %s off screen %s" % [what, r[0], r[1]])
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i][1].grow(-0.5).intersects(rects[j][1].grow(-0.5)):
				check(false, "%s: %s %s overlaps %s %s" % [what, rects[i][0], rects[i][1], rects[j][0], rects[j][1]])


## Every visible control under `under` lies inside `panel` across (the rows scroll up and down, never sideways).
func _inside(what: String, panel: Control, under: Node) -> void:
	var p := panel.get_global_rect().grow(0.5)
	for c: Control in under.find_children("*", "Control", true, false):
		var r := c.get_global_rect()
		if c.is_visible_in_tree() and (r.position.x < p.position.x or r.end.x > p.end.x):
			check(false, "%s: %s '%s' %s sticks out of the panel %s" % [what, c.get_class(), c.get("text"), r, p])
