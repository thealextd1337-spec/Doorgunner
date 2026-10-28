extends Node2D
## Survivor waiting at a POI. Walks to `target` at 45 px/s (wounded 25 px/s) and emits `arrived` on reaching it.

signal arrived

const SPEED := 45.0
const INJURED_SPEED := 25.0

var target: Node2D
var nav := {} # main.gd nav_move state: walks around hedges and houses
var injured := false:
	set(v):
		injured = v
		modulate = Color(1, 0.5, 0.5) if v else Color.WHITE


func _ready() -> void:
	add_to_group("survivors") # zombies close by attack them (enemy.gd)
	var s := Art.sprite("survivor")
	add_child(s)


func _process(delta: float) -> void:
	if target == null:
		return
	if Game.world.nav_move(self, target.global_position, INJURED_SPEED if injured else SPEED, delta, nav):
		arrived.emit()
