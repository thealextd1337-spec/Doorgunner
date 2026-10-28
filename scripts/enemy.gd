extends Node2D
## Zombies. All melee, all on the ground: flying is safe, landing is not.
## They roam, raid settlements, follow noise, and swarm a landed heli.
## target_base = true during base assaults.

const KINDS := {
	"shambler": {"hp": 45.0, "speed": 22.0, "dmg": 8.0, "xp": 4, "radius": 8.0},
	"runner": {"hp": 25.0, "speed": 80.0, "dmg": 6.0, "xp": 6, "radius": 7.0},
	"brute": {"hp": 220.0, "speed": 18.0, "dmg": 28.0, "xp": 25, "radius": 11.0},
	"boss": {"hp": 2200.0, "speed": 16.0, "dmg": 45.0, "xp": 300, "radius": 22.0, "boss": true},
}
const MELEE_INTERVAL := 1.0
const RAID_INTERVAL := 5.0 # seconds per survivor killed at a settlement
const AGGRO_DIST := 600.0 # landed heli closer than this gets swarmed
const GOAL_DIST := 1500.0 # how far zombies look for a settlement
const DESPAWN_DIST := 2400.0

var kind := "shambler"
var cfg := {}
var hp := 30.0
var max_hp := 30.0
var radius := 8.0
var speed := 20.0
var dmg := 8.0
var target_base := false
var attack_cd := 0.0
var spawn_cd := 10.0
var goal: Node2D # settlement POI being raided
var goal_cd := 0.0
var wander := Vector2.ZERO
var wander_cd := 0.0
var sprite: Sprite2D


func setup(kind_name: String, pos: Vector2, danger: float, base_target := false) -> void:
	kind = kind_name
	cfg = KINDS[kind]
	position = pos
	target_base = base_target
	max_hp = cfg["hp"] * (0.7 + danger * 0.3)
	hp = max_hp
	radius = cfg["radius"]
	speed = cfg["speed"] * randf_range(0.85, 1.15) * (0.9 + danger * 0.1)
	dmg = cfg["dmg"] * (0.8 + danger * 0.2)


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2
	sprite = Art.sprite(kind)
	add_child(sprite)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	attack_cd -= delta
	var heli: Node2D = Game.heli
	var to_heli: Vector2 = heli.global_position - global_position
	if not target_base and to_heli.length() > DESPAWN_DIST:
		queue_free()
		return
	if cfg.get("boss", false):
		spawn_cd -= delta
		if spawn_cd <= 0.0:
			spawn_cd = 10.0
			for i in 2:
				Game.world.spawn_enemy("runner", global_position + Vector2(30, 0).rotated(randf() * TAU), target_base)
	# 1. base assault
	if target_base:
		_approach(delta, Game.world.base, radius + 50.0, Game.world.base.take_damage)
		return
	# 2. landed heli: everything nearby converges
	if heli.landed and to_heli.length() < AGGRO_DIST:
		_approach(delta, heli, radius + heli.RADIUS + 4.0, heli.take_damage)
		return
	# 3. investigate noise (gunfire, rotor): harmless in the air, deadly once you land
	if Game.noise_level > 0.15:
		var to_noise: Vector2 = Game.noise_pos - global_position
		var nd := to_noise.length()
		if nd > 24.0 and nd < 200.0 + 500.0 * Game.noise_level:
			_face(to_noise)
			position += to_noise.normalized() * speed * 0.8 * delta
			return
	# 4. raid the nearest settlement
	goal_cd -= delta
	if (goal == null or not is_instance_valid(goal) or goal.done) and goal_cd <= 0.0:
		goal_cd = 5.0
		goal = _find_settlement()
	if goal and is_instance_valid(goal) and not goal.done:
		_approach(delta, goal, 40.0, func(_d): goal.lose_survivor(), RAID_INTERVAL)
		return
	# 5. wander
	wander_cd -= delta
	if wander_cd <= 0.0:
		wander_cd = randf_range(2.0, 6.0)
		wander = Vector2.RIGHT.rotated(randf() * TAU) * (0.0 if randf() < 0.4 else 1.0)
	_face(wander)
	position += wander * speed * 0.5 * delta


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 0.01:
		rotation = lerp_angle(rotation, dir.angle() + PI / 2, 0.15)


## Walk to `target`; within `reach`, call `strike(dmg)` every `interval` seconds.
func _approach(delta: float, target: Node2D, reach: float, strike: Callable, interval := MELEE_INTERVAL) -> void:
	var to_target: Vector2 = target.global_position - global_position
	_face(to_target)
	if to_target.length() > reach:
		var next: Vector2 = position + to_target.normalized() * speed * delta
		var cell := Vector2i((next / 16.0).floor())
		if Game.sandbags.get(cell, {}).get("built", false): # a built sandbag blocks: chew through it first
			if attack_cd <= 0.0:
				attack_cd = interval
				Game.world.base.damage_sandbag(cell, dmg)
			return
		position = next
	elif attack_cd <= 0.0:
		attack_cd = interval
		strike.call(dmg)


func _find_settlement() -> Node2D:
	var best: Node2D
	var best_d := GOAL_DIST * GOAL_DIST
	for p in Game.world.pois:
		if not is_instance_valid(p) or p.kind != "survivors" or p.done:
			continue
		var d: float = global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func hit(amount: float) -> void:
	hp -= amount
	sprite.modulate = Color(1, 0.5, 0.5)
	get_tree().create_timer(0.08).timeout.connect(func(): if is_instance_valid(self): sprite.modulate = Color.WHITE)
	Sfx.play("hit", global_position, -14.0)
	if hp <= 0.0:
		_die()


func _die() -> void:
	Game.kills += 1
	Game.add_xp(cfg["xp"])
	if randf() < 0.02:
		Game.base_rifles += 1.0 # a rifle off the body, goes to the base armory
	if randf() < 0.2 or cfg.get("boss", false):
		Game.scrap += 2 + int(cfg["xp"] / 4)
	Game.world.spawn_fx(global_position, 2.0 if cfg.get("boss", false) else 0.7)
	Sfx.play("explosion" if cfg.get("boss", false) else "enemy_die", global_position)
	if cfg.get("boss", false):
		Game.radio("Abomination down! Outstanding, gunner.")
		Sfx.play("boss_roar", global_position)
	queue_free()
