extends Node2D
## All enemy kinds in one script; behaviour is driven by the KINDS table.
## Ground kinds roam, march on settlements and only go for the heli when it is landed nearby.
## Flyers are the air threat and hunt the heli. Spitters/boss fire enemy_bullet.gd.
## target_base = true during base assaults.

const KINDS := {
	"walker": {"hp": 40.0, "speed": 32.0, "dmg": 8.0, "xp": 5, "radius": 8.0, "ground": true},
	"runner": {"hp": 22.0, "speed": 70.0, "dmg": 5.0, "xp": 6, "radius": 7.0, "ground": true},
	"spitter": {"hp": 50.0, "speed": 24.0, "dmg": 10.0, "xp": 10, "radius": 8.0, "ground": true, "range": 200.0, "cooldown": 2.8},
	"flyer": {"hp": 35.0, "speed": 95.0, "dmg": 14.0, "xp": 12, "radius": 8.0, "ground": false},
	"boss": {"hp": 1200.0, "speed": 26.0, "dmg": 30.0, "xp": 250, "radius": 22.0, "ground": true, "range": 300.0, "cooldown": 2.0, "boss": true},
}
const MELEE_INTERVAL := 1.0
const RAID_INTERVAL := 5.0 # seconds per survivor killed at a settlement
const AGGRO_DIST := 260.0 # landed heli closer than this gets attacked
const GOAL_DIST := 1500.0 # how far ground aliens look for a settlement
const DESPAWN_DIST := 2200.0

var kind := "walker"
var cfg := {}
var hp := 30.0
var max_hp := 30.0
var radius := 8.0
var speed := 60.0
var dmg := 8.0
var target_base := false
var attack_cd := 0.0
var spawn_cd := 8.0
var retreat := 0.0
var goal: Node2D # settlement POI being raided
var goal_cd := 0.0
var wander := Vector2.ZERO
var wander_cd := 0.0
var sprite: Sprite2D

@onready var bullet_script := preload("res://scripts/enemy_bullet.gd")


func setup(kind_name: String, pos: Vector2, danger: float, base_target := false) -> void:
	kind = kind_name
	cfg = KINDS[kind]
	position = pos
	target_base = base_target
	max_hp = cfg["hp"] * (0.7 + danger * 0.3)
	hp = max_hp
	radius = cfg["radius"]
	speed = cfg["speed"] * (0.9 + danger * 0.1)
	dmg = cfg["dmg"] * (0.8 + danger * 0.2)


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2 if cfg["ground"] else 8
	sprite = Art.sprite(kind)
	add_child(sprite)
	if not cfg["ground"]:
		var sh := Art.sprite(kind)
		sh.modulate = Color(0, 0, 0, 0.3)
		sh.position = Vector2(6, 9)
		add_child(sh)
		move_child(sh, 0)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	attack_cd -= delta
	retreat -= delta
	var heli: Node2D = Game.heli
	var to_heli: Vector2 = heli.global_position - global_position
	if not target_base and to_heli.length() > DESPAWN_DIST:
		queue_free()
		return
	if cfg["ground"]:
		_ground_ai(delta, heli, to_heli)
	else:
		_flyer_ai(delta, heli, to_heli)
	if cfg.has("range"):
		_ranged(heli, to_heli)
	if cfg.get("boss", false):
		spawn_cd -= delta
		if spawn_cd <= 0.0:
			spawn_cd = 9.0
			for i in 2:
				Game.world.spawn_enemy("runner", global_position + Vector2(30, 0).rotated(randf() * TAU), target_base)


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 0.01:
		rotation = lerp_angle(rotation, dir.angle() + PI / 2, 0.15)


func _ground_ai(delta: float, heli: Node2D, to_heli: Vector2) -> void:
	# 1. base assault
	if target_base:
		var base: Node2D = Game.world.base
		var to_base: Vector2 = base.global_position - global_position
		_face(to_base)
		if to_base.length() > radius + 50.0:
			position += to_base.normalized() * speed * delta
		elif attack_cd <= 0.0:
			attack_cd = MELEE_INTERVAL
			base.take_damage(dmg)
		return
	# 2. landed heli nearby
	if heli.landed and to_heli.length() < AGGRO_DIST:
		_face(to_heli)
		if to_heli.length() > radius + heli.RADIUS + 4.0:
			position += to_heli.normalized() * speed * delta
		elif attack_cd <= 0.0:
			attack_cd = MELEE_INTERVAL
			heli.take_damage(dmg)
		return
	# 3. raid the nearest settlement
	goal_cd -= delta
	if (goal == null or not is_instance_valid(goal) or goal.done) and goal_cd <= 0.0:
		goal_cd = 5.0
		goal = _find_settlement()
	if goal and is_instance_valid(goal) and not goal.done:
		var to_goal: Vector2 = goal.global_position - global_position
		_face(to_goal)
		if to_goal.length() > 40.0:
			position += to_goal.normalized() * speed * delta
		elif attack_cd <= 0.0:
			attack_cd = RAID_INTERVAL
			goal.lose_survivor()
		return
	# 4. wander
	wander_cd -= delta
	if wander_cd <= 0.0:
		wander_cd = randf_range(2.0, 5.0)
		wander = Vector2.RIGHT.rotated(randf() * TAU) * (0.0 if randf() < 0.3 else 1.0)
	_face(wander)
	position += wander * speed * 0.5 * delta


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


func _flyer_ai(delta: float, heli: Node2D, to_heli: Vector2) -> void:
	_face(to_heli)
	if retreat > 0.0:
		position -= to_heli.normalized() * speed * 0.8 * delta
		return
	position += to_heli.normalized() * speed * delta
	if to_heli.length() < radius + heli.RADIUS:
		heli.take_damage(dmg)
		retreat = 1.0


func _ranged(heli: Node2D, to_heli: Vector2) -> void:
	var target: Node2D = Game.world.base if target_base else heli
	var to_target: Vector2 = target.global_position - global_position
	if to_target.length() > cfg["range"] or attack_cd > 0.0:
		return
	attack_cd = cfg["cooldown"]
	var shots := 5 if cfg.get("boss", false) else 1
	for i in shots:
		var ang := deg_to_rad((i - (shots - 1) / 2.0) * 12.0)
		var b := bullet_script.new()
		b.setup(global_position, to_target.normalized().rotated(ang), dmg * 0.6, target)
		Game.world.add_child(b)


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
	if randf() < 0.25 or cfg.get("boss", false):
		Game.scrap += 2 + int(cfg["xp"] / 4)
	Game.world.spawn_fx(global_position, 2.0 if cfg.get("boss", false) else 1.0)
	Sfx.play("explosion" if cfg.get("boss", false) else "enemy_die", global_position)
	if cfg.get("boss", false):
		Game.radio("Hive queen down! Outstanding, gunner.")
		Sfx.play("boss_roar", global_position)
	queue_free()
