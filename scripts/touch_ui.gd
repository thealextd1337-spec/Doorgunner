extends CanvasLayer
## Touch controls (Q5), shown while Controls.touch is on: left stick flies, right stick aims and fires the door gun while
## held out, a button strip on the right presses the flight actions (InputEventActions, so the game code stays the same),
## context buttons (found base / outpost / protect) appear when they apply. In build mode a tap on the map moves the
## preview and PLACE / REMOVE / ROTATE / DONE act on it. Multi-touch: every pad follows its own finger (index).
## Layout (Q6a): under a UiTheme root, placed from its size every frame: fly stick bottom left, aim stick bottom right
## with the strip left of it, context buttons in the band between them, MENU under the HUD minimap, build buttons a
## column on the right. The HUD fits its radio log into log_band() and around obstacles().

const STICK_R := 90.0
const BTN := Vector2(96, 52) # button strip pad; both sides >= UiTheme.TOUCH_MIN
const GAP := 8.0
const CONTEXT_W := 150.0
const CURSOR_AHEAD := Vector2(0, -56) # build preview starts this far from the landed heli
const MAX_SCALE := 1.25 # past this UI scale the sticks, the strip and a context band no longer fit side by side

var move_stick: Stick
var aim_stick: Stick
var flight: Control # sticks and strip, hidden while a menu is open
var pads := {} # action -> Pad
var context: Array[Pad] = [] # found / outpost / protect
var takeoff: Pad # LAND shown in the base menu gap while the menu is open
var menu: Pad
var restart: Pad
var place_bar: Control
var portrait: Label
var root: UiTheme.Root
var _was_placing := false
var _strip_left := 0.0 # root px, left edge of the button strip (log_band)


func _ready() -> void:
	layer = 31 # over the base menu (10), ESC menu (25) and game over (30); under the title (40). Pads hide while paused
	process_mode = PROCESS_MODE_ALWAYS # MENU must close the paused ESC menu
	add_to_group(UiTheme.OBSTACLES)
	root = UiTheme.attach(self, null, MAX_SCALE)
	flight = Control.new()
	flight.set_anchors_preset(Control.PRESET_FULL_RECT)
	flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flight)
	move_stick = Stick.new(Vector2.ZERO, STICK_R, "FLY")
	flight.add_child(move_stick)
	aim_stick = Stick.new(Vector2.ZERO, STICK_R, "AIM / FIRE")
	flight.add_child(aim_stick)
	var strip := [["land", "LAND"], ["weapon_swap", "GUN"], ["yaw_left", "< YAW"], ["yaw_right", "YAW >"], ["system", "SPEAKER"], ["hook", "HOOK"], ["missions", "JOBS"]]
	for i in strip.size():
		var p := Pad.new(strip[i][0], strip[i][1], Vector2.ZERO, BTN)
		flight.add_child(p)
		pads[strip[i][0]] = p
	for a in ["found", "outpost", "protect"]:
		var p := Pad.new(a, a.to_upper(), Vector2.ZERO, Vector2(CONTEXT_W, BTN.y))
		flight.add_child(p)
		context.append(p)
	takeoff = Pad.new("land", "TAKE OFF", Vector2.ZERO, Vector2(200, BTN.y)) # bottom left, under the base menu's status column
	root.add_child(takeoff)
	menu = Pad.new("menu", "MENU", Vector2.ZERO, Vector2(80, UiTheme.TOUCH_MIN)) # under the HUD minimap
	root.add_child(menu)
	restart = Pad.new("restart", "RESTART", Vector2.ZERO, Vector2(200, BTN.y))
	root.add_child(restart)
	place_bar = VBoxContainer.new()
	place_bar.add_theme_constant_override("separation", int(GAP))
	root.add_child(place_bar)
	for b in [["PLACE", _place], ["REMOVE", _remove], ["ROTATE", "rotate"], ["DONE", "menu"]]:
		var p := Pad.new(b[1] if b[1] is String else "", b[0], Vector2.ZERO, BTN)
		if b[1] is Callable:
			p.on_press = b[1]
		place_bar.add_child(p)
	portrait = Label.new()
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait.add_theme_font_size_override("font_size", UiTheme.FONT_XL)
	portrait.text = "Turn your device sideways:\nDoorgunner plays in landscape."
	var dim := StyleBoxFlat.new()
	dim.bg_color = Color(0, 0, 0, 0.9)
	portrait.add_theme_stylebox_override("normal", dim)
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(portrait)
	_process(0.0)


func _process(_delta: float) -> void:
	var win := DisplayServer.window_get_size()
	portrait.visible = Controls.touch and win.y > win.x
	visible = Controls.touch
	if not visible or Game.world == null or Game.heli == null:
		return
	var paused := get_tree().paused
	var base: Node2D = Game.world.base
	var heli: Node2D = Game.heli
	var in_menu: bool = Game.world.ui_open or base.placing
	flight.visible = Game.running and not paused and not in_menu
	takeoff.visible = Game.running and not paused and in_menu and base.ui.visible and not base.placing and heli.landed
	place_bar.visible = Game.running and not paused and base.placing
	menu.visible = Game.running and (not Game.world.choice_ui.visible if paused else not in_menu) # also closes the ESC menu
	restart.visible = not Game.running and Game.world.hud.visible # game over (the title hides the HUD)
	if base.placing and not _was_placing:
		Controls.cursor = heli.global_position + CURSOR_AHEAD
	_was_placing = base.placing
	Controls.stick_move = move_stick.value if move_stick.is_visible_in_tree() else Vector2.ZERO
	Controls.stick_aim = aim_stick.value if aim_stick.is_visible_in_tree() else Vector2.ZERO
	pads["land"].text = "TAKE OFF" if heli.landed else "LAND"
	pads["system"].visible = Game.heli_items.has("loudspeaker")
	pads["hook"].visible = Game.world.wrecks.slung() or Game.world.wrecks.wreck_below(heli.position) != ""
	var ctx: Dictionary = Game.world.outposts._ctx # what [O] / [P] would do here, rescanned 4x a second
	var on := [heli.can_found(), ctx.get("o", "") != "", ctx.get("p", false)]
	for i in context.size():
		context[i].visible = on[i]
	_layout()
	for c in [move_stick, aim_stick]:
		if not c.is_visible_in_tree():
			c.release()
	for p in pads.values() + context + [takeoff, menu, restart]:
		if not p.is_visible_in_tree():
			p.release()


## Corners and bands from the root size (root px).
func _layout() -> void:
	var w := root.size.x
	var h := root.size.y
	var m := float(UiTheme.MARGIN)
	var s := move_stick.size
	move_stick.position = Vector2(m, h - m - s.y)
	aim_stick.position = Vector2(w - m - s.x, h - m - s.y)
	_strip_left = aim_stick.position.x - GAP - 2.0 * BTN.x - GAP
	var row := pads.values().filter(func(p): return p.visible) # strip without gaps for the hidden pads
	for i in row.size():
		row[i].position = Vector2(_strip_left, h - m - BTN.y) + Vector2(i % 2, -(i / 2)) * (BTN + Vector2(GAP, GAP))
	# context buttons: centred rows at the bottom of the band between the fly stick and the strip
	var left := move_stick.position.x + s.x + GAP
	var per_row := maxi(1, floori((_strip_left - GAP - left + GAP) / (CONTEXT_W + GAP)))
	var shown := context.filter(func(p): return p.visible)
	for i in shown.size():
		var in_row := mini(per_row, shown.size() - i / per_row * per_row)
		var x0 := (left + _strip_left - GAP) / 2.0 - (in_row * (CONTEXT_W + GAP) - GAP) / 2.0
		shown[i].position = Vector2(x0 + (i % per_row) * (CONTEXT_W + GAP), h - m - BTN.y - (i / per_row) * (BTN.y + GAP))
	takeoff.position = Vector2(m, h - m - BTN.y)
	restart.position = Vector2((w - restart.size.x) / 2.0, h - m - BTN.y - 2.0 * GAP)
	var map: Control = Game.world.hud.minimap
	menu.position = Vector2(w - m - menu.size.x, map.get_global_rect().end.y / root.factor + GAP)
	place_bar.reset_size()
	place_bar.position = Vector2(w - m - BTN.x, (h - place_bar.size.y) / 2.0)


## Where the HUD may put its radio log (screen px): the band between the sticks above the context buttons, or above
## TAKE OFF in the base menu. Empty: no constraint.
func log_band() -> Rect2:
	if not visible:
		return Rect2()
	var r := Rect2()
	if flight.visible:
		var left := move_stick.position.x + move_stick.size.x + GAP
		var bottom := root.size.y - UiTheme.MARGIN
		for p in context:
			if p.visible:
				bottom = minf(bottom, p.position.y)
		r = Rect2(left, 0, _strip_left - GAP - left, bottom - GAP)
	elif takeoff.visible:
		r = Rect2(UiTheme.MARGIN, 0, root.size.x - 2.0 * UiTheme.MARGIN, takeoff.position.y - GAP)
	return Rect2(r.position * root.factor, r.size * root.factor)


## Everything a finger presses here, for the HUD to stay clear of.
func obstacles() -> Array:
	return [move_stick, aim_stick, takeoff, menu, restart, place_bar] + pads.values() + context


func _place() -> void:
	var base: Node2D = Game.world.base
	base.place(base.place_kind, base.place_cell())
	base.ui.refresh()


func _remove() -> void:
	var base: Node2D = Game.world.base
	base.remove_at(base.mouse_cell())
	base.ui.refresh()


## A button pad: holds its action pressed while a finger is on it, or calls on_press once.
class Pad extends Control:
	const MOUSE := 99 # finger id of a real mouse (touch mode on a desktop)
	var action: String
	var text: String:
		set(v):
			text = v
			queue_redraw()
	var on_press: Callable
	var finger := -1

	func _init(a: String, label: String, at: Vector2, sz: Vector2) -> void:
		action = a
		text = label
		position = at
		size = sz
		custom_minimum_size = sz
		mouse_filter = Control.MOUSE_FILTER_STOP # emulated clicks on a pad never reach the map

	## Which finger an event belongs to: the touch index, MOUSE for a real mouse, -1 for the mouse events the engine
	## emulates from touches (the ScreenTouch itself is handled instead).
	static func finger_of(ev: InputEvent) -> int:
		if ev is InputEventScreenTouch or ev is InputEventScreenDrag:
			return ev.index
		if ev.device != InputEvent.DEVICE_ID_EMULATION and (ev is InputEventMouseMotion or (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT)):
			return MOUSE
		return -1

	func _gui_input(ev: InputEvent) -> void:
		var id := finger_of(ev)
		if id < 0 or not (ev is InputEventScreenTouch or ev is InputEventMouseButton):
			return
		accept_event()
		if ev.pressed and finger < 0:
			finger = id
			if on_press.is_valid():
				on_press.call()
			else:
				_send(true)
			queue_redraw()
		elif not ev.pressed and id == finger:
			release()

	func release() -> void:
		if finger < 0:
			return
		finger = -1
		if not on_press.is_valid():
			_send(false)
		queue_redraw()

	func _send(on: bool) -> void:
		var a := InputEventAction.new()
		a.action = action
		a.pressed = on
		Input.parse_input_event(a)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.PANEL, 0.75 if finger >= 0 else 0.45))
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.ACCENT if finger >= 0 else UiTheme.OLIVE, false, 2.0)
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_L).x
		draw_string(font, Vector2((size.x - w) / 2.0, size.y / 2.0 + 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT_L, UiTheme.SAND)


## A virtual stick: value is the finger's offset from the centre, length 0..1.
class Stick extends Control:
	var value := Vector2.ZERO
	var finger := -1
	var radius: float
	var label: String

	func _init(center: Vector2, r: float, text: String) -> void:
		radius = r
		label = text
		size = Vector2(r, r) * 2.6 # the touch area reaches a bit past the ring
		position = center - size / 2.0
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		var id := Pad.finger_of(ev)
		if id < 0:
			return
		accept_event()
		if ev is InputEventScreenTouch or ev is InputEventMouseButton:
			if ev.pressed and finger < 0:
				finger = id
				_follow(ev.position)
			elif not ev.pressed and id == finger:
				release()
		elif id == finger:
			_follow(ev.position)

	func _follow(at: Vector2) -> void:
		value = ((at - size / 2.0) / radius).limit_length(1.0)
		queue_redraw()

	func release() -> void:
		finger = -1
		value = Vector2.ZERO
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, radius, Color(0, 0, 0, 0.25))
		draw_arc(c, radius, 0.0, TAU, 48, Color(UiTheme.SAND, 0.5), 2.0)
		draw_circle(c + value * radius, radius * 0.38, Color(UiTheme.ACCENT, 0.7 if finger >= 0 else 0.35))
		var font := ThemeDB.fallback_font
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT).x
		draw_string(font, Vector2(c.x - w / 2.0, c.y + radius + 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.FONT, Color(UiTheme.SAND, 0.7))
