extends Node2D
## Alien projectile. Damages the heli (landed or not) or the base if that is its target.

var dir := Vector2.RIGHT
var speed := 240.0
var damage := 6.0
var life := 2.2
var target: Node2D


func setup(pos: Vector2, d: Vector2, dmg: float, t: Node2D) -> void:
	position = pos
	dir = d
	damage = dmg
	target = t


func _ready() -> void:
	z_index = 9
	var s := Sprite2D.new()
	s.texture = load("res://assets/sprites/enemy_bullet.png")
	add_child(s)


func _process(delta: float) -> void:
	position += dir * speed * delta
	life -= delta
	if life <= 0.0 or not is_instance_valid(target):
		queue_free()
		return
	var r: float = target.RADIUS if "RADIUS" in target else 16.0
	if position.distance_to(target.global_position) <= r:
		target.take_damage(damage)
		queue_free()
