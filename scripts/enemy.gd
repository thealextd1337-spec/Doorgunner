extends Node2D
## All enemy kinds in one script; behaviour is driven by the KINDS table.
## Ground kinds only hurt the heli while it is landed. Flyers ram it in the air.
## Spitters/boss fire enemy_bullet.gd. target_base = true during base assaults.

const KINDS := {
	"walker": {"hp": 30.0, "speed": 60.0, "dmg": 8.0, "xp": 5, "radius": 8.0, "ground": true},
	"runner": {"hp": 18.0, "speed": 130.0, "dmg": 5.0, "xp": 6, "radius": 7.0, "ground": true},
	"spitter": {"hp": 40.0, "speed": 40.0, "dmg": 10.0, "xp": 10, "radius": 8.0, "ground": true, "range": 260.0, "cooldown": 2.2},
	"flyer": {"hp": 22.0, "speed": 160.0, "dmg": 12.0, "xp": 8, "radius": 8.0, "ground": false},
	"boss": {"hp": 900.0, "speed": 45.0, "dmg": 30.0, "xp": 200, "radius": 22.0, "ground": true, "range": 320.0, "cooldown": 1.4, "boss": true},
}
const MELEE_INTERVAL := 0.8
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
var spawn_cd := 6.0
var retreat := 0.0
var sprite: Sprite2D
var wander := Vector2.ZERO

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
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/%s.png" % kind)
	add_child(sprite)
	if not cfg["ground"]:
		var sh := Sprite2D.new()
		sh.texture = sprite.texture
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
	var target: Node2D = Game.world.base if target_base and Game.world.base else heli
	var to_target: Vector2 = target.global_position - global_position
	var dist := to_target.length()
	if not target_base and dist > DESPAWN_DIST:
		queue_free()
		return
	if dist > 0.1:
		rotation = to_target.angle() + PI / 2
	if cfg["ground"]:
		_ground_ai(delta, target, to_target, dist)
	else:
		_flyer_ai(delta, heli, to_target, dist)
	if cfg.has("range"):
		_ranged(delta, target, to_target, dist)
	if cfg.get("boss", false):
		spawn_cd -= delta
		if spawn_cd <= 0.0:
			spawn_cd = 7.0
			for i in 2:
				Game.world.spawn_enemy("runner", global_position + Vector2(30, 0).rotated(randf() * TAU), target_base)


func _ground_ai(delta: float, target: Node2D, to_target: Vector2, dist: float) -> void:
	var reach := radius + 18.0
	if target_base:
		reach = radius + 50.0
	var can_hit: bool = target_base or Game.heli.landed
	if dist > reach:
		var dir := to_target.normalized()
		if not can_hit and dist < 60.0:
			# circle beneath the hovering heli
			wander = wander.lerp(Vector2.RIGHT.rotated(randf() * TAU), 0.1)
			dir = wander
		position += dir * speed * delta
	elif can_hit and attack_cd <= 0.0:
		attack_cd = MELEE_INTERVAL
		target.take_damage(dmg)


func _flyer_ai(delta: float, heli: Node2D, to_target: Vector2, dist: float) -> void:
	if retreat > 0.0:
		position -= to_target.normalized() * speed * 0.8 * delta
		return
	position += to_target.normalized() * speed * delta
	if dist < radius + heli.RADIUS:
		heli.take_damage(dmg)
		retreat = 0.7


func _ranged(_delta: float, target: Node2D, to_target: Vector2, dist: float) -> void:
	if dist > cfg["range"] or attack_cd > 0.0:
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
	if hp <= 0.0:
		_die()


func _die() -> void:
	Game.kills += 1
	Game.add_xp(cfg["xp"])
	if randf() < 0.25 or cfg.get("boss", false):
		Game.scrap += 2 + int(cfg["xp"] / 4)
	Game.world.spawn_fx(global_position, 2.0 if cfg.get("boss", false) else 1.0)
	if cfg.get("boss", false):
		Game.radio("Hive queen down! Outstanding, gunner.")
	queue_free()
