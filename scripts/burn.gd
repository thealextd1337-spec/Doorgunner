class_name Burn
extends Node2D
## Burning status (Q8 flamethrower, Scatter Gun Lv5): a child of the enemy named "Burn" that calls the enemy's own hit()
## every TICK, so enemy.gd needs no new branch. Not saved: it lasts a few seconds. Lv5 flamer: `spread` ignites neighbours.

const TICK := 0.5
const SPREAD_RANGE := 28.0

var dps := 0.0
var left := 0.0
var spread := false
var _acc := 0.0


## Set `e` alight, or extend the fire it already has.
static func ignite(e: Node2D, dps_: float, secs: float, spread_ := false) -> void:
	if not is_instance_valid(e) or e.is_queued_for_deletion() or dps_ <= 0.0:
		return
	var b: Burn = e.get_node_or_null("Burn")
	if b == null:
		b = Burn.new()
		b.name = "Burn"
		e.add_child(b)
	b.dps = maxf(b.dps, dps_)
	b.left = maxf(b.left, secs)
	b.spread = b.spread or spread_


func _ready() -> void:
	z_index = 3


func _process(delta: float) -> void:
	if not Game.running:
		return
	left -= delta
	_acc += delta
	queue_redraw()
	if left <= 0.0:
		queue_free()
		return
	if _acc < TICK:
		return
	_acc -= TICK
	var e: Node2D = get_parent()
	if spread:
		for o in get_tree().get_nodes_in_group("enemies"):
			if o != e and not o.has_node("Burn") and o.global_position.distance_squared_to(e.global_position) <= SPREAD_RANGE * SPREAD_RANGE:
				ignite(o, dps, left, true)
	e.hit(dps * TICK)


func _draw() -> void:
	var r := 4.0 + randf() * 2.5
	draw_circle(Vector2(0, -2), r, Color(1, 0.45, 0.1, 0.55))
	draw_circle(Vector2(0, -2), r * 0.5, Color(1, 0.85, 0.4, 0.8))
