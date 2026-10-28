extends Node2D
## Searchlight system: cone ahead of the heli. At night zombies inside are slowed and POIs revealed; Lv5 freezes them 2 s.

const HALF_ANGLE := 0.4 # rad


func _ready() -> void:
	z_index = -1 # under the heli sprites


func _process(_delta: float) -> void:
	visible = Game.darkness() > 0.2
	queue_redraw()
	if not visible or not Game.running:
		return
	var lv := Progression.level("searchlight")
	for e in get_tree().get_nodes_in_group("enemies"):
		if "slowed" in e and _lit(e.global_position):
			e.slowed = 0.25 + 0.05 * lv
			if lv >= 5:
				e.stun(2.0)
	for p in Game.world.pois:
		if is_instance_valid(p) and not p.discovered and _lit(p.global_position):
			p.discovered = true


func _reach() -> float:
	return 140.0 + 30.0 * Progression.level("searchlight")


func _forward() -> Vector2:
	return Vector2.UP.rotated(get_parent().body.rotation)


func _lit(pos: Vector2) -> bool:
	var v := pos - global_position
	return v.length() < _reach() and absf(_forward().angle_to(v)) < HALF_ANGLE


func _draw() -> void:
	var f := _forward() * _reach()
	draw_colored_polygon(PackedVector2Array([Vector2.ZERO, f.rotated(-HALF_ANGLE), f.rotated(HALF_ANGLE)]), Color(1, 1, 0.8, 0.18))
