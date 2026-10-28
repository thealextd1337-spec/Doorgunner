extends Node
## Co-gunner system: shoots the nearest zombie with part of the equipped gun's damage, no ammo used; Lv5 the main gun at 80 %.

const Weapons := preload("res://scripts/weapons.gd")

var cd := 0.0


func _process(delta: float) -> void:
	cd -= delta
	if cd > 0.0 or not Game.running:
		return
	var heli: Node2D = get_parent()
	var lv := Progression.level("cogunner")
	var w: Dictionary = Weapons.TABLE[Game.weapon]
	var reach: float = heli.weapon_range() if lv >= 5 else 200.0 + 30.0 * lv
	var target: Node2D
	var best := reach * reach
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = heli.global_position.distance_squared_to(e.global_position)
		if d < best:
			best = d
			target = e
	if target == null:
		return
	cd = maxf(0.25, w["interval"])
	var dir: Vector2 = (target.global_position - heli.global_position).normalized()
	var b: Node2D = preload("res://scripts/bullet.gd").new()
	b.setup(heli.global_position + dir * 12, dir, w["damage"] * Game.stats["damage"] * (0.8 if lv >= 5 else 0.35 + 0.05 * lv),
		w["pierce"] if lv >= 5 else 0, w["bullet_speed"], reach / (w["bullet_speed"] * Game.stats["bullet_speed"]), w.get("splash", 0.0) if lv >= 5 else 0.0)
	Game.world.add_child(b)
	Sfx.play("gun", null, -12.0)
