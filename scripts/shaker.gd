extends Node
## Child of the heli camera: HitFx.shake() kicks it, the camera offset jitters and settles. Option "shake" in the ESC menu.

const DECAY := 14.0 # px per second

var amp := 0.0
var cam: Camera2D


func _ready() -> void:
	cam = get_parent()
	add_to_group("shaker")


func kick(amount: float) -> void:
	if Game.meta.get("shake", 1) == 1:
		amp = maxf(amp, amount)


func _process(delta: float) -> void:
	amp = maxf(0.0, amp - DECAY * delta)
	cam.offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
