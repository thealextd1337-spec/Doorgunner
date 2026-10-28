extends Node
## Command radio: periodic POI hints, low-fuel and full-cabin warnings.

const HINT_INTERVAL := 45.0

var hint_cd := HINT_INTERVAL
var fuel_cd := 0.0
var full_said := false


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	var world: Node2D = Game.world
	if is_instance_valid(world.radio_target) and world.radio_target.done:
		world.radio_target = null
	hint_cd -= delta
	if hint_cd <= 0.0:
		hint_cd = 30.0 if Game.power else HINT_INTERVAL # powered base radio reaches further
		_hint()
	fuel_cd -= delta
	if fuel_cd <= 0.0 and Game.fuel < 0.25 * Game.max_fuel:
		fuel_cd = 60.0
		Game.radio("Base: you are low on fuel, return to the pad.")
	var full: bool = Game.passengers >= Game.seats
	if full and not full_said:
		Game.radio("Pilot: we are full, head back to base.")
	full_said = full


func _hint() -> void:
	var heli_pos: Vector2 = Game.heli.position
	var found: Array = Game.world.pois.filter(func(p):
		var d: float = heli_pos.distance_to(p.position)
		return not p.done and not p.discovered and p.kind != "nest" and d >= 600.0 and d <= 3000.0)
	if found.is_empty():
		return
	var p: Node2D = found.pick_random()
	p.discovered = true
	Game.world.radio_target = p
	var what: String = "distress call from a" if p.kind == "survivors" else "recon reports a"
	Game.radio("Command: %s %s, %s." % [what, p.label, p.where(heli_pos, p.position)])
