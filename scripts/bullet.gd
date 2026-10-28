extends Node2D
## Player tracer. Hits anything in group "enemies" exposing hit(damage) and radius.

var dir := Vector2.RIGHT
var speed := 520.0
var damage := 10.0
var pierce := 0
var life := 1.3
var splash := 0.0 # radius: on hit also damage every enemy within it
var hit_list := []
var life0 := 1.3
var chain := 0 # railgun Lv5: jumps left to further targets
var bounce := 0 # Hard Core Lv5: ricochets left


func setup(pos: Vector2, d: Vector2, dmg: float, p: int, spd := 520.0, life_s := 1.3, splash_r := 0.0) -> void:
	position = pos
	dir = d
	damage = dmg
	pierce = p
	speed = spd * Game.stats["bullet_speed"]
	life = life_s
	life0 = life_s
	splash = splash_r


func _ready() -> void:
	var s := Art.sprite("bullet")
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
			e.hit(damage * (1.5 if life < life0 / 3.0 and Progression.level("optics") >= 5 else 1.0))
			hit_list.append(e)
			if chain > 0:
				_chain(e)
			if splash > 0.0:
				for o in get_tree().get_nodes_in_group("enemies"):
					if o != e and position.distance_squared_to(o.global_position) <= splash * splash:
						o.hit(damage)
				Game.world.spawn_fx(position, 0.8)
				Sfx.play("explosion", position, -6.0)
			if hit_list.size() > pierce:
				var next: Node2D = _nearest(e) if bounce > 0 else null
				if next == null:
					queue_free()
					return
				bounce -= 1
				pierce += 1
				dir = (next.global_position - position).normalized()
				rotation = dir.angle()


## Closest enemy not hit yet within 160 px of `from`.
func _nearest(from: Node2D) -> Node2D:
	var best: Node2D
	var best_d := 160.0 * 160.0
	for o in get_tree().get_nodes_in_group("enemies"):
		var d: float = from.global_position.distance_squared_to(o.global_position)
		if o not in hit_list and d < best_d:
			best_d = d
			best = o
	return best


## Railgun chain: a new bolt from the struck enemy to the next one, carrying the remaining jumps.
func _chain(from: Node2D) -> void:
	var next := _nearest(from)
	if next != null:
		var b: Node2D = get_script().new()
		b.setup(from.global_position, (next.global_position - from.global_position).normalized(), damage, 0,
			speed / Game.stats["bullet_speed"], (from.global_position.distance_to(next.global_position) + 20.0) / speed)
		b.chain = chain - 1
		b.hit_list = hit_list.duplicate()
		Game.world.add_child(b)
	chain = 0
