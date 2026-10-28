extends Node
## Flares system: drops a burning flare behind the heli whose noise lures zombies; Lv5 drops two and zombies attack them.

var cd := 5.0


func _process(delta: float) -> void:
	if not Game.running:
		return
	cd -= delta
	if cd > 0.0:
		return
	var lv := Progression.level("flares")
	cd = 22.5 - 2.5 * lv
	if lv >= 5:
		drop(-30.0)
		drop(30.0)
	else:
		drop()


## One flare `side` px left/right, 60 px behind the heli. Returns it (tests).
func drop(side := 0.0) -> Node2D:
	var heli: Node2D = get_parent()
	var f := Flare.new()
	f.position = heli.global_position + Vector2(side, 60).rotated(heli.body.rotation)
	f.life = 7.0 + Progression.level("flares")
	if Progression.level("flares") >= 5:
		f.add_to_group("decoys")
	Game.world.add_child(f)
	return f


class Flare extends Node2D:
	var life := 8.0
	var hp := 60.0

	func _ready() -> void:
		z_index = 3

	func _process(delta: float) -> void:
		life -= delta
		Game.make_noise(global_position, 1.1) # louder than gunfire (1.0), so the flare wins
		queue_redraw()
		if life <= 0.0 or hp <= 0.0:
			queue_free()

	## Zombies strike Lv5 flares like anything else.
	func hit(amount: float) -> void:
		hp -= amount

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 7.0 + randf() * 3.0, Color(1, 0.5, 0.2, 0.3))
		draw_circle(Vector2.ZERO, 2.5, Color(1, 0.9, 0.6))
