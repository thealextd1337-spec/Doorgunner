extends Node
## Winch system: hovering slower than 40 px/s within 64 px of a settlement or hideout hoists survivors aboard; Lv5 two at a time.

const REACH := 64.0
const HOVER_SPEED := 40.0

var cd := 6.0


func _process(delta: float) -> void:
	var heli: Node2D = get_parent()
	var lv := Progression.level("winch")
	var poi := _near(heli.global_position)
	if not Game.running or poi == null or heli.landed or heli.pending != 0 or heli.vel.length() > HOVER_SPEED:
		cd = 6.75 - 0.75 * lv
		return
	cd -= delta
	if cd > 0.0:
		return
	cd = 6.75 - 0.75 * lv
	for i in 2 if lv >= 5 else 1:
		poi.winch_one()


func _near(pos: Vector2) -> Node2D:
	for p in Game.world.pois:
		if is_instance_valid(p) and not p.done and (p.kind == "survivors" or p.kind == "hideout") and p.global_position.distance_to(pos) < REACH:
			return p
	return null
