extends Node
## Zombie spawning: hordes around towns, plus the base assault waves.

const HORDE_INTERVAL := 3.0

var horde_cd := 3.0
var wave_left := 0
var wave_cd := 0.0


func _ready() -> void:
	Game.base_attack_started.connect(_on_attack)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	horde_cd -= delta
	if horde_cd <= 0.0:
		horde_cd = HORDE_INTERVAL
		_horde()
	if wave_left > 0:
		wave_cd -= delta
		if wave_cd <= 0.0:
			wave_cd = 0.5
			wave_left -= 1
			var pos: Vector2 = Game.world.base.global_position + Vector2(720, 0).rotated(randf() * TAU)
			Game.world.spawn_enemy(_pick(Game.danger_at(Vector2.ZERO)), pos, true)
	elif Game.attack_active and _attackers_alive() == 0:
		Game.attack_active = false
		Game.radio("Base secured. Good work, gunner.")


## A horde of 6-12 zombies spawned around a town near the heli (towns are where the dead are).
func _horde() -> void:
	var heli: Node2D = Game.heli
	var danger := Game.danger_at(heli.position)
	if get_tree().get_nodes_in_group("enemies").size() >= int(30 + danger * 10):
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
	if base_d < Game.base_radius + 300.0 or not Game.world.chunks.is_landable(pos):
		return
	if Game.power and Game.is_night() and base_d < 1500.0 and randf() < 0.3:
		return # the base lights keep them away
	for i in randi_range(6, 12):
		Game.world.spawn_enemy(_pick(danger), pos + Vector2(randf_range(-40, 40), randf_range(-40, 40)))


func _pick(danger: float) -> String:
	var w := {"shambler": 70.0, "runner": 10.0 + danger * 5.0, "brute": 3.0 + danger * 3.0}
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "shambler"


## Extra zombies converging on a hot landing zone (used by POIs).
func call_wave(pos: Vector2, count: int) -> void:
	var danger := Game.danger_at(pos)
	for i in count:
		var p := pos + Vector2(380.0 + randf() * 120.0, 0).rotated(randf() * TAU)
		Game.world.spawn_enemy(_pick(danger), p)


func _on_attack(day: int) -> void:
	wave_left = Game.tutorial_wave if Game.tutorial_wave > 0 else 20 + day * 6
	wave_cd = 0.0
	Sfx.play("alarm")
	var tutorial := Game.tutorial_wave > 0
	Game.tutorial_wave = 0
	if not tutorial and day % (Game.ATTACK_EVERY_DAYS * 2) == 0:
		Game.world.spawn_enemy("boss", Game.world.base.global_position + Vector2(800, 0).rotated(randf() * TAU), true)


func _attackers_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if "target_base" in e and e.target_base:
			n += 1
	return n
