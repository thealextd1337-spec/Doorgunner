extends Node2D
## Survivor waiting at a POI. Walks to `target` at 45 px/s (wounded 25 px/s) and emits `arrived` on reaching it.

signal arrived

const SPEED := 45.0
const INJURED_SPEED := 25.0

var target: Node2D
var injured := false:
	set(v):
		injured = v
		modulate = Color(1, 0.5, 0.5) if v else Color.WHITE


func _ready() -> void:
	var s := Art.sprite("survivor")
	add_child(s)


func _process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.move_toward(target.global_position, (INJURED_SPEED if injured else SPEED) * delta)
	if global_position.distance_to(target.global_position) < 6.0:
		arrived.emit()
