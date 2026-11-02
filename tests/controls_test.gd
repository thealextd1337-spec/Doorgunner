extends Node
## Input layer + touch test (Q5): SMOKE=controls godot --headless --path . --quit-after 30000
## No raw key checks left in scripts/, every former raw key is an action with the same key, keyboard/mouse go through
## Controls unchanged, simulated touches fly, aim and fire (multi-touch), the touch buttons press actions, and build
## placement by tap + PLACE / REMOVE / ROTATE / DONE. Sets Controls.touch directly so settings.json is never written.

const RAW := ["is_key_pressed", "keycode", "get_global_mouse_position", "get_mouse_position"]
# old raw checks -> the action that replaced them (same key)
const KEYS := {"slot_1": KEY_1, "slot_4": KEY_4, "slot_9": KEY_9, "base_menu": KEY_TAB, "reroll": KEY_R, "skip": KEY_S,
	"banish": KEY_B, "leaderboard": KEY_L, "menu": KEY_ESCAPE, "mute": KEY_M, "system": KEY_F, "hangar": KEY_H,
	"start": KEY_ENTER}

var _bad: PackedStringArray = []
var touch_ui: CanvasLayer


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	var main: Node2D = Game.world
	var heli: Node2D = Game.heli
	var base: Node2D = main.base
	var frame := get_tree().process_frame
	touch_ui = main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/touch_ui.gd"))[0]
	await frame
	# --- no raw key / mouse checks outside Game._setup_input and Controls
	var raw := _raw_checks("res://scripts/")
	check(raw.is_empty(), "raw key checks left:\n" + "\n".join(raw))
	for a in KEYS:
		check(InputMap.has_action(a) and InputMap.event_is_action(_key(KEYS[a]), a), "%s on its old key" % a)
	var kp := InputEventKey.new()
	kp.keycode = KEY_KP_ENTER
	check(InputMap.event_is_action(kp, "start") and InputMap.event_is_action(_key(KEY_SPACE), "start"), "keypad enter / space start")
	check(Settings.defs.has("touch") and Settings.defs["touch"]["kind"] == "toggle", "touch switch in the ESC menu")
	# --- keyboard + mouse through Controls, unchanged
	check(not Controls.touch and not touch_ui.visible, "touch off without a touchscreen")
	check(Controls.aim() == main.get_global_mouse_position(), "mouse aims")
	Input.action_press("fire")
	check(Controls.fire(), "LMB fires")
	Input.action_release("fire")
	Input.action_press("move_right")
	Input.action_press("yaw_left")
	check(Controls.move() == Vector2.RIGHT and Controls.yaw() == -1.0, "WASD / Q move and yaw")
	Input.action_release("move_right")
	Input.action_release("yaw_left")
	check(Controls.move() == Vector2.ZERO and not Controls.fire(), "idle")
	# --- mode switch (user decision): boots in mouse mode, a real touch turns touch on, real mouse / keys turn it off,
	# Godot's emulated events (DEVICE_ID_EMULATION) never switch. Releases far off-screen so nothing gets pressed.
	check(not Settings.is_on("touch"), "boots in mouse/keyboard mode")
	_send(InputEventScreenTouch.new(), InputEvent.DEVICE_ID_EMULATION)
	check(not Controls.touch, "emulated touch (from the mouse) keeps mouse mode")
	_send(InputEventScreenTouch.new(), 0)
	check(Controls.touch and Settings.is_on("touch"), "first real touch: touch mode")
	_send(InputEventMouseMotion.new(), InputEvent.DEVICE_ID_EMULATION)
	_send(InputEventMouseButton.new(), InputEvent.DEVICE_ID_EMULATION, true)
	_send(InputEventMouseButton.new(), InputEvent.DEVICE_ID_EMULATION)
	check(Controls.touch, "emulated mouse (from the touch) keeps touch mode")
	_send(InputEventMouseMotion.new(), 0)
	check(not Controls.touch and not Settings.is_on("touch"), "real mouse move: back to mouse mode")
	_send(InputEventScreenDrag.new(), 0)
	check(Controls.touch, "real drag: touch mode")
	var shift := _key(KEY_SHIFT)
	shift.pressed = true
	Input.parse_input_event(shift)
	shift = _key(KEY_SHIFT)
	Input.parse_input_event(shift)
	Input.flush_buffered_events()
	check(not Controls.touch, "key press: back to mouse mode")
	# --- touch: take off with the LAND pad
	Controls.touch = true
	await frame
	check(touch_ui.visible and touch_ui.flight.visible and heli.landed, "touch layer up, heli on the pad")
	var land: Control = touch_ui.pads["land"]
	check(land.size.x >= UiTheme.TOUCH_MIN and land.size.y >= UiTheme.TOUCH_MIN, "pads at least TOUCH_MIN")
	_touch(0, _center(land), true)
	await frame
	_touch(0, _center(land), false)
	for i in 2000:
		await frame
		if not heli.landed and heli.pending == 0:
			break
	check(not heli.landed, "LAND pad took off")
	# fly right on the left stick; an emulated click from that finger must not fire
	var ammo0 := Game.ammo
	var x0: float = heli.position.x
	var ms: Control = touch_ui.move_stick
	_touch(0, _center(ms), true)
	_drag(0, _center(ms) + Vector2(ms.radius, 0))
	await frame
	check(Controls.stick_move.is_equal_approx(Vector2.RIGHT) and Controls.move().is_equal_approx(Vector2.RIGHT), "left stick flies: %s" % Controls.stick_move)
	check(not Controls.fire(), "the move finger does not fire")
	for i in 60:
		await frame
	check(heli.position.x > x0 + 5.0 and heli.vel.x > 10.0, "heli flew right: %s" % heli.vel)
	check(Game.ammo == ammo0, "no shot from flying")
	# second finger on the right stick: aim out of the side door and fire while held out
	var side: Vector2 = Vector2.UP.rotated(heli.body.rotation).orthogonal()
	var as_: Control = touch_ui.aim_stick
	_touch(1, _center(as_), true)
	_drag(1, _center(as_) + side * as_.radius)
	await frame
	check(Controls.fire() and Controls.aim().distance_to(heli.global_position + side * Controls.AIM_REACH) < 1.0, "right stick aims and fires")
	check(Controls.stick_move.is_equal_approx(Vector2.RIGHT), "both sticks at once")
	for i in 30:
		await frame
	check(Game.ammo < ammo0, "door gun fired from the right stick")
	_touch(1, _center(as_), false)
	_touch(0, _center(ms), false)
	await frame
	check(not Controls.fire() and Controls.stick_move == Vector2.ZERO, "sticks released")
	# yaw pad held with a third finger
	var yl: Control = touch_ui.pads["yaw_left"]
	_touch(2, _center(yl), true)
	await frame
	check(Controls.yaw() == -1.0, "< YAW pad held")
	_touch(2, _center(yl), false)
	await frame
	check(Controls.yaw() == 0.0, "< YAW pad released")
	# --- build placement by touch
	heli.position = base.position
	heli.vel = Vector2.ZERO
	heli.landed = true
	Game.scrap = 500
	base.ui.open()
	base.place_kind = "sandbag"
	base.placing = true
	for i in 3:
		await frame
	check(touch_ui.place_bar.visible and not touch_ui.flight.visible, "build buttons instead of the flight pads")
	check(Controls.point().distance_to(heli.global_position + touch_ui.CURSOR_AHEAD) < 1.0, "preview starts at the heli")
	var cell := Vector2i(-99, -99)
	for x in range(-4, 5):
		for y in range(-4, 5):
			var c := Vector2i((base.position / base.CELL).floor()) + Vector2i(x, y)
			if cell.x == -99 and base.can_place("sandbag", c) and x > 0:
				cell = c
	check(cell.x != -99, "a free cell inside the fence")
	var at: Vector2 = get_viewport().get_canvas_transform() * base.cell_pos(cell)
	var bags := Game.sandbags.size()
	_touch(0, at, true)
	_touch(0, at, false)
	await frame
	check(base.place_cell() == cell and Game.sandbags.size() == bags, "a tap moves the preview, places nothing: %s vs %s" % [base.place_cell(), cell])
	var btns: Array = touch_ui.place_bar.get_children()
	await _tap(btns[0])
	check(Game.sandbags.has(cell), "PLACE puts the blueprint at the preview")
	await _tap(btns[1])
	check(not Game.sandbags.has(cell), "REMOVE takes it back")
	var rot0: int = base.place_rot
	await _tap(btns[2])
	check(base.place_rot == 1 - rot0, "ROTATE")
	await _tap(btns[3])
	check(not base.placing, "DONE leaves build mode")
	base.ui.close()
	# --- back to keyboard + mouse
	Controls.touch = false
	await frame
	check(not touch_ui.visible and Controls.aim() == main.get_global_mouse_position(), "touch off: mouse again")
	if _bad.is_empty():
		print("CONTROLS OK  raw checks=0  actions=%d" % InputMap.get_actions().size())
		get_tree().quit(0)
	else:
		for b in _bad:
			push_error("CONTROLS FAIL: " + b)
		get_tree().quit(1)


## Parses `ev` from `device` at a far off-screen spot (a release unless `down`).
func _send(ev: InputEvent, device: int, down := false) -> void:
	ev.device = device
	ev.position = Vector2(-5000, -5000)
	if ev is InputEventMouseButton:
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = down
	elif ev is InputEventMouseMotion:
		ev.relative = Vector2(3, 0)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(k: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	return ev


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _touch(i: int, at: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = i
	ev.position = get_viewport().get_screen_transform() * at # canvas -> window px (headless windows are tiny)
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _drag(i: int, at: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = i
	ev.position = get_viewport().get_screen_transform() * at
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _tap(c: Control) -> void:
	_touch(0, _center(c), true)
	await get_tree().process_frame
	_touch(0, _center(c), false)
	await get_tree().process_frame


## "file:line: code" for every raw key or mouse read outside Game._setup_input and controls.gd. KEY_ names of the
## engine's Key enum only (KEY_PARTS etc. are the game's own constants).
func _raw_checks(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var key := RegEx.create_from_string("\\bKEY_([A-Z0-9]|F\\d+|TAB|ESCAPE|ENTER|KP_\\w+|SPACE|UP|DOWN|LEFT|RIGHT|BACKSPACE|DELETE|SHIFT|CTRL|ALT|META|HOME|END|INSERT|PAGE\\w+)\\b")
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd") or f in ["controls.gd", "keymap.gd"]:
			continue
		var fn := ""
		var lines := FileAccess.get_file_as_string(dir + f).split("\n")
		for n in lines.size():
			var l: String = lines[n]
			if l.begins_with("func "):
				fn = l.get_slice("(", 0).trim_prefix("func ")
			var code := l.get_slice("#", 0)
			if fn != "_setup_input" and (key.search(code) != null or RAW.any(func(r): return code.contains(r))):
				out.append("%s%s:%d: %s" % [dir, f, n + 1, l.strip_edges()])
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_raw_checks(dir + d + "/"))
	return out
