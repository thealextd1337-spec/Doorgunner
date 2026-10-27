extends Node
## Ambient enemy spawning around the heli and the base assault waves.

const AMBIENT_INTERVAL := 1.6
const SPAWN_DIST := 520.0

var ambient_cd := 2.0
var wave_left := 0
var wave_cd := 0.0


func _ready() -> void:
	Game.base_attack_started.connect(_on_attack)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	ambient_cd -= delta
	if ambient_cd <= 0.0:
		ambient_cd = AMBIENT_INTERVAL
		_ambient()
	if wave_left > 0:
		wave_cd -= delta
		if wave_cd <= 0.0:
			wave_cd = 0.6
			wave_left -= 1
			var pos: Vector2 = Game.world.base.global_position + Vector2(720, 0).rotated(randf() * TAU)
			Game.world.spawn_enemy(_pick_kind(Game.danger_at(Vector2.ZERO), true), pos, true)
	elif Game.attack_active and _attackers_alive() == 0:
		Game.attack_active = false
		Game.radio("Base secured. Good work, gunner.")


func _ambient() -> void:
	var heli: Node2D = Game.heli
	var danger := Game.danger_at(heli.position)
	var cap := int(5 + danger * 3)
	if get_tree().get_nodes_in_group("enemies").size() >= cap:
		return
	# base perimeter is quiet unless an assault is on
	if heli.position.distance_to(Game.world.base.global_position) < 450.0:
		return
	var kind := _pick_kind(danger, false)
	var pos := heli.position + Vector2(SPAWN_DIST + randf() * 150.0, 0).rotated(randf() * TAU)
	if kind != "flyer" and not Game.world.chunks.is_landable(pos):
		return
	Game.world.spawn_enemy(kind, pos)


func _pick_kind(danger: float, assault: bool) -> String:
	var w := {
		"walker": 40.0,
		"runner": 15.0 + danger * 6.0,
		"spitter": 8.0 + danger * 6.0,
		"flyer": (8.0 if assault else 12.0) + (25.0 if Game.is_night() else 0.0),
	}
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "walker"


## Extra enemies converging on a hot landing zone (used by POIs).
func call_wave(pos: Vector2, count: int) -> void:
	var danger := Game.danger_at(pos)
	for i in count:
		var kind := _pick_kind(danger, false)
		var p := pos + Vector2(380.0 + randf() * 120.0, 0).rotated(randf() * TAU)
		Game.world.spawn_enemy(kind, p)


func _on_attack(day: int) -> void:
	wave_left = 10 + day * 3
	wave_cd = 0.0
	if day % (Game.ATTACK_EVERY_DAYS * 2) == 0:
		Game.world.spawn_enemy("boss", Game.world.base.global_position + Vector2(800, 0).rotated(randf() * TAU), true)


func _attackers_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if "target_base" in e and e.target_base:
			n += 1
	return n
