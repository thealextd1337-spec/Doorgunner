extends Node2D
## A patch on the ground that wears off: spitter acid (eats sandbags and wire, hurts a landed heli in it) and the
## gas cloud of a burst bloater (hurts a landed heli). A spit first flies `delay` s from `origin`, then calls `impact`
## and the puddle starts. Drawn, not saved: it is gone after a few seconds anyway.

const ACID_DPS := 14.0 # on sandbags and wire in the puddle
const HELI_HIT := 3.0 # per second spent in it, taken once a second
const TICK := 1.0

var kind := "acid"
var radius := 20.0
var life := 4.0
var delay := 0.0
var origin := Vector2.ZERO
var impact := Callable() # called once when the spit lands
var _life0 := 4.0
var _delay0 := 0.0
var _tick := 0.0


func setup(k: String, pos: Vector2, r: float, seconds: float, flight := 0.0, from := Vector2.ZERO) -> void:
	kind = k
	position = pos
	radius = r
	life = seconds
	_life0 = seconds
	delay = flight
	_delay0 = flight
	origin = from


func _ready() -> void:
	z_index = 3
	add_to_group("puddles")


func _process(delta: float) -> void:
	if not Game.running:
		return
	queue_redraw()
	if delay > 0.0:
		delay -= delta
		if delay <= 0.0 and impact.is_valid():
			impact.call()
		return
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	if kind == "acid":
		var c0 := Vector2i(((position - Vector2(radius, radius)) / 16.0).floor())
		var c1 := Vector2i(((position + Vector2(radius, radius)) / 16.0).floor())
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var cell := Vector2i(x, y)
				if Game.sandbags.get(cell, {}).get("built", false) and Game.world.base.cell_pos(cell).distance_to(position) <= radius + 8.0:
					Game.world.base.damage_sandbag(cell, ACID_DPS * TICK)
	var heli: Node2D = Game.heli
	if heli.landed and heli.global_position.distance_to(position) <= radius + heli.RADIUS:
		heli.take_damage(HELI_HIT)


func _draw() -> void:
	var col := Color(0.62, 0.74, 0.2) if kind == "acid" else Color(0.5, 0.62, 0.3)
	if delay > 0.0: # the glob in flight
		draw_circle((origin - position).lerp(Vector2.ZERO, 1.0 - delay / _delay0), 2.5, Color(col, 0.9))
		return
	var f := clampf(life / _life0, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius * (0.75 + 0.25 * f), Color(col, 0.18 + 0.3 * f))
	draw_arc(Vector2.ZERO, radius * (0.75 + 0.25 * f), 0.0, TAU, 20, Color(col, 0.6 * f), 1.0)
