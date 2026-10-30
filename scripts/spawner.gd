extends Node
## Zombie spawning: hordes around towns. The base assault waves are scripts/assault.gd.

const HORDE_INTERVAL := 3.0

var horde_cd := 3.0


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	horde_cd -= delta
	if horde_cd <= 0.0:
		horde_cd = HORDE_INTERVAL
		_horde()


## A horde (SpawnTable.horde: 6-12 zombies, later sometimes a runner pack) spawned around a town near the heli (towns are where the dead are).
func _horde() -> void:
	var heli: Node2D = Game.heli
	var danger := Game.danger_at(heli.position)
	var dense: bool = Game.world.modifiers.on("dense_horde")
	if get_tree().get_nodes_in_group("enemies").size() >= int((30 + danger * 10) * (1.0 + Game.world.modifiers.HORDE_EXTRA * int(dense))):
		return
	var towns: Array = Game.world.chunks.town_centers.filter(func(t):
		var d: float = heli.position.distance_to(t)
		return d > 300.0 and d < 1000.0)
	var pos: Vector2
	if towns.is_empty():
		if randf() < 0.6:
			return # open country is mostly quiet
		pos = heli.position + Vector2(600.0 + randf() * 200.0, 0).rotated(randf() * TAU)
	else:
		pos = towns[randi() % towns.size()] + Vector2(120.0 + randf() * 120.0, 0).rotated(randf() * TAU)
	var base_d: float = pos.distance_to(Game.world.base.global_position)
	if (Game.base_founded and base_d < Game.base_radius + 300.0) or not Game.world.chunks.is_landable(pos):
		return
	if Game.power and Game.is_night() and base_d < 1500.0 and randf() < 0.3:
		return # the base lights keep them away
	for kind in SpawnTable.horde(danger, SpawnTable.context(pos, not towns.is_empty())):
		for i in 1 + int(dense and randf() < Game.world.modifiers.HORDE_EXTRA):
			Game.world.spawn_enemy(kind, pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)))


## Extra zombies converging on a hot landing zone (used by POIs).
func call_wave(pos: Vector2, count: int) -> void:
	var danger := Game.danger_at(pos)
	for i in count:
		var p := pos + Vector2(380.0 + randf() * 120.0, 0).rotated(randf() * TAU)
		Game.world.spawn_enemy(SpawnTable.pick(danger, SpawnTable.context(p)), p)

