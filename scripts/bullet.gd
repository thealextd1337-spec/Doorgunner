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
# Q8 weapon properties (weapons.gd tune() sets them): fire, range falloff, lobbed shells, stun, push, wide hit radius, head bonus
var burn := 0.0 # dps of the fire a hit leaves (burn.gd)
var burn_s := 3.0
var burn_spread := false
var falloff := 0.0 # fraction of damage lost by the end of the flight
var lob_dist := 0.0 # > 0: flies over everything and bursts after this many px
var stun := 0.0 # seconds; targets without stun() (bandits) ignore it
var push := 0.0 # px/s shove along the flight direction
var reach := 0.0 # added to the target's radius
var head_bonus := 0.0
var art := "bullet"
var _travel := 0.0
var _sprite: Sprite2D

const HEAD_CHANCE := 0.04 # of a hit being a headshot (double damage), plus HEAD_PER_OPTICS per Optics level
const HEAD_PER_OPTICS := 0.03


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
	_sprite = Art.sprite(art)
	add_child(_sprite)
	rotation = dir.angle()


func _process(delta: float) -> void:
	position += dir * speed * delta
	life -= delta
	_travel += speed * delta
	if lob_dist > 0.0:
		_lob()
		return
	if life <= 0.0:
		queue_free()
		return
	if art != "bullet":
		_sprite.modulate.a = clampf(life / life0 * 1.6, 0.0, 1.0) # flames and waves fade out
	for e in get_tree().get_nodes_in_group("enemies"):
		if e in hit_list:
			continue
		var r: float = e.radius + reach
		if position.distance_squared_to(e.global_position) <= r * r:
			var head := randf() < HEAD_CHANCE + HEAD_PER_OPTICS * Progression.level("optics") + head_bonus
			e.hit(damage * (1.5 if life < life0 / 3.0 and Progression.level("optics") >= 5 else 1.0) * (1.0 - falloff * (1.0 - life / life0)), dir, head)
			_affect(e)
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


## Status effects of a hit on `e`: fire, stun (not on bosses), shove.
func _affect(e: Node2D) -> void:
	if burn > 0.0:
		Burn.ignite(e, burn, burn_s, burn_spread)
	if stun > 0.0 and e.has_method("stun") and not e.get("cfg").get("boss", false):
		e.stun(stun)
	if push > 0.0 and "kick" in e:
		e.kick = (e.kick + dir * push).limit_length(220.0)


## Lobbed shell: arcs over everything (sprite rises and falls) and bursts at the aim point.
func _lob() -> void:
	var f := clampf(_travel / lob_dist, 0.0, 1.0)
	_sprite.position = Vector2.UP.rotated(-rotation) * sin(f * PI) * 22.0
	_sprite.scale = Vector2.ONE * Art.SCALE * (1.0 + 0.6 * sin(f * PI))
	if _travel < lob_dist and life > 0.0:
		return
	for o in get_tree().get_nodes_in_group("enemies"):
		if position.distance_squared_to(o.global_position) <= (splash + o.radius) * (splash + o.radius):
			o.hit(damage, (o.global_position - position).normalized())
			_affect(o)
	Game.world.spawn_fx(position, 0.8)
	Sfx.play("explosion", position, -6.0)
	queue_free()


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
