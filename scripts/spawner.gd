extends Node
## Enemy spawning: ground packs near settlements, rare flyers, and the base assault waves.

const GROUND_INTERVAL := 3.0
const FLYER_INTERVAL := 14.0

var ground_cd := 3.0
var flyer_cd := 20.0
var wave_left := 0
var wave_cd := 0.0


func _ready() -> void:
	Game.base_attack_started.connect(_on_attack)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	ground_cd -= delta
	if ground_cd <= 0.0:
		ground_cd = GROUND_INTERVAL
		_ground_pack()
	flyer_cd -= delta
	if flyer_cd <= 0.0:
		flyer_cd = FLYER_INTERVAL * (0.6 if Game.is_night() else 1.0)
		_flyer()
	if wave_left > 0:
		wave_cd -= delta
		if wave_cd <= 0.0:
			wave_cd = 1.0
			wave_left -= 1
			var pos: Vector2 = Game.world.base.global_position + Vector2(720, 0).rotated(randf() * TAU)
			Game.world.spawn_enemy(_pick_ground(Game.danger_at(Vector2.ZERO)), pos, true)
	elif Game.attack_active and _attackers_alive() == 0:
		Game.attack_active = false
		Game.radio("Base secured. Good work, gunner.")


func _count(ground: bool) -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if "cfg" in e and e.cfg.get("ground", true) == ground:
			n += 1
	return n


## A pack of 2-4 ground aliens heading for a settlement near the heli.
func _ground_pack() -> void:
	var heli: Node2D = Game.heli
	var danger := Game.danger_at(heli.position)
	if _count(true) >= int(6 + danger * 3):
		return
	var towns: Array = Game.world.chunks.town_centers.filter(func(t):
		var d: float = heli.position.distance_to(t)
		return d > 350.0 and d < 950.0)
	var pos: Vector2
	if towns.is_empty():
		pos = heli.position + Vector2(550.0 + randf() * 150.0, 0).rotated(randf() * TAU)
	else:
		pos = towns[randi() % towns.size()] + Vector2(180.0 + randf() * 80.0, 0).rotated(randf() * TAU)
	if pos.distance_to(Game.world.base.global_position) < 450.0 or not Game.world.chunks.is_landable(pos):
		return
	var kind := _pick_ground(danger)
	for i in randi_range(2, 4):
		Game.world.spawn_enemy(kind, pos + Vector2(randf_range(-20, 20), randf_range(-20, 20)))


func _flyer() -> void:
	var heli: Node2D = Game.heli
	if _count(false) >= (2 if Game.is_night() else 1):
		return
	if heli.position.distance_to(Game.world.base.global_position) < 450.0:
		return
	Game.world.spawn_enemy("flyer", heli.position + Vector2(650.0, 0).rotated(randf() * TAU))


func _pick_ground(danger: float) -> String:
	var w := {"walker": 50.0, "runner": 12.0 + danger * 6.0, "spitter": 6.0 + danger * 6.0}
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "walker"


## Extra ground aliens converging on a hot landing zone (used by POIs).
func call_wave(pos: Vector2, count: int) -> void:
	var danger := Game.danger_at(pos)
	for i in count:
		var p := pos + Vector2(380.0 + randf() * 120.0, 0).rotated(randf() * TAU)
		Game.world.spawn_enemy(_pick_ground(danger), p)


func _on_attack(day: int) -> void:
	wave_left = 8 + day * 3
	wave_cd = 0.0
	Sfx.play("alarm")
	if day % (Game.ATTACK_EVERY_DAYS * 2) == 0:
		Game.world.spawn_enemy("boss", Game.world.base.global_position + Vector2(800, 0).rotated(randf() * TAU), true)


func _attackers_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if "target_base" in e and e.target_base:
			n += 1
	return n
