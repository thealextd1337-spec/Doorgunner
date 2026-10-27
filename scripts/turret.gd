extends Node2D
## Base auto turret: every 0.5 s shoots the nearest enemy in range with a player bullet.

const RANGE := 240.0
const INTERVAL := 0.5
const DAMAGE := 8.0

var cd := 0.0
var sprite: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/turret.png")
	add_child(sprite)


func _process(delta: float) -> void:
	if not Game.running:
		return
	cd -= delta
	if cd > 0.0:
		return
	cd = INTERVAL
	var best: Node2D
	var best_d := RANGE * RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var dir: Vector2 = (best.global_position - global_position).normalized()
	sprite.rotation = dir.angle() + PI / 2
	var b := preload("res://scripts/bullet.gd").new()
	b.setup(global_position + dir * 10, dir, DAMAGE, 0)
	Game.world.add_child(b)
