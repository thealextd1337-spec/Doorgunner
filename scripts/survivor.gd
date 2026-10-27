extends Node2D
## Survivor waiting at a POI. Walks to `target` at 45 px/s and emits `arrived` on reaching it.

signal arrived

const SPEED := 45.0

var target: Node2D


func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = load("res://assets/sprites/survivor.png")
	add_child(s)


func _process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.move_toward(target.global_position, SPEED * delta)
	if global_position.distance_to(target.global_position) < 6.0:
		arrived.emit()
