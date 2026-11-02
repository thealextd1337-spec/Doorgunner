extends Node
## Autoload `Controls`: the one place game code reads flight, aim and fire from (keyboard + mouse, or the touch layer
## touch_ui.gd). Every key is an Input action from Game._setup_input(); nothing else reads raw keys (controls_test.gd).
## Touch mode ("touch" setting): every boot starts in mouse/keyboard mode (a saved "touch" is ignored, so a touchscreen
## laptop never boots into it); the first real touch switches to touch mode, a real mouse move/click or key press switches
## back (_input). The ESC menu row shows the mode and can force it. In touch mode the sticks fill stick_move / stick_aim, the touch
## buttons send InputEventActions, and a tap on the world sets the build cursor instead of placing at once.

const STICK_DEAD := 0.25 # aim stick deflection below which the door gun holds fire
const AIM_REACH := 160.0 # world px ahead of the heli that aim() returns for the aim stick

var touch := false
var stick_move := Vector2.ZERO # left stick, length 0..1 (touch_ui.gd)
var stick_aim := Vector2.ZERO # right stick, length 0..1
var _aim_dir := Vector2.RIGHT # touch: last aim stick direction, kept when the stick is let go
var cursor := Vector2.ZERO # touch: world position of the last tap on the map (build preview)


func _ready() -> void:
	Settings.register_toggle("touch", "Touch controls", false)
	Settings.values["touch"] = 0
	Settings.changed.connect(func(key: String, v: Variant) -> void:
		if key == "touch":
			touch = v == 1
			stick_move = Vector2.ZERO
			stick_aim = Vector2.ZERO)


## Switch mode on real input only: Godot's touch<->mouse emulation events carry DEVICE_ID_EMULATION and are ignored.
func _input(ev: InputEvent) -> void:
	if ev.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if not touch and (ev is InputEventScreenTouch or ev is InputEventScreenDrag):
		Settings.set_value("touch", 1)
	elif touch and (ev is InputEventMouseMotion or (ev is InputEventMouseButton or ev is InputEventKey) and ev.pressed):
		Settings.set_value("touch", 0)


## Flight input, each axis -1..1: WASD / arrows, else the left stick.
func move() -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return v if v != Vector2.ZERO or not touch else stick_move.limit_length(1.0)


## Q/E (or the touch yaw buttons, which press the same actions): -1 left .. 1 right.
func yaw() -> float:
	return Input.get_axis("yaw_left", "yaw_right")


## World position the door gun aims at: the mouse, or in touch mode a point along the aim stick.
func aim() -> Vector2:
	if not touch:
		return point()
	if stick_aim.length() > STICK_DEAD:
		_aim_dir = stick_aim.normalized()
	return (Game.heli.global_position if Game.heli else Vector2.ZERO) + _aim_dir * AIM_REACH


## Door gun trigger: LMB (the "fire" action), or in touch mode the aim stick held out (emulated touch clicks never fire).
func fire() -> bool:
	return stick_aim.length() > STICK_DEAD if touch else Input.is_action_pressed("fire")


## World position of the pointer: the mouse, or in touch mode the last tap on the map (build placement).
func point() -> Vector2:
	return cursor if touch else Game.world.get_global_mouse_position()


## Touch: a tap at viewport position `screen` becomes the build cursor.
func tap(screen: Vector2) -> void:
	cursor = Game.world.get_viewport().get_canvas_transform().affine_inverse() * screen
