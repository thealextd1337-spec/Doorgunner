extends Node2D
## Player tracer. Hits anything in group "enemies" exposing hit(damage) and radius.

var dir := Vector2.RIGHT
var speed := 520.0
var damage := 10.0
var pierce := 0
var life := 1.3
var splash := 0.0 # radius: on hit also damage every enemy within it
var hit_list := []


func setup(pos: Vector2, d: Vector2, dmg: float, p: int, spd := 520.0, life_s := 1.3, splash_r := 0.0) -> void:
	position = pos
	dir = d
	damage = dmg
	pierce = p
	speed = spd * Game.stats["bullet_speed"]
	life = life_s
	splash = splash_r


func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = load("res://assets/sprites/bullet.png")
	add_child(s)
	rotation = dir.angle()


func _process(delta: float) -> void:
	position += dir * speed * delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e in hit_list:
			continue
		if position.distance_squared_to(e.global_position) <= e.radius * e.radius:
			e.hit(damage)
			hit_list.append(e)
			if splash > 0.0:
				for o in get_tree().get_nodes_in_group("enemies"):
					if o != e and position.distance_squared_to(o.global_position) <= splash * splash:
						o.hit(damage)
				Game.world.spawn_fx(position, 0.8)
				Sfx.play("explosion", position, -6.0)
			if hit_list.size() > pierce:
				queue_free()
				return
