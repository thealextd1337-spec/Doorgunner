extends Node
## Loudspeaker system: [F] blares a noise burst that pulls zombies in (radius grows per level); Lv5 makes them flee 5 s instead.

const COOLDOWN := 8.0

var cd := 0.0


func _process(delta: float) -> void:
	cd -= delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		blare()


func blare() -> bool:
	if cd > 0.0 or not Game.running:
		return false
	cd = COOLDOWN
	var lv := Progression.level("loudspeaker")
	var noise := 0.6 + 0.2 * lv # zombies follow noise within 200 + 500 * level px
	var pos: Vector2 = get_parent().global_position
	Sfx.play("alarm", null, -10.0)
	if lv < 5:
		Game.make_noise(pos, noise)
		return true
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.has_method("panic") and pos.distance_to(e.global_position) < 200.0 + 500.0 * noise:
			e.panic(pos, 5.0)
	Game.radio("Gunner: they're running! Loudspeaker works.")
	return true
