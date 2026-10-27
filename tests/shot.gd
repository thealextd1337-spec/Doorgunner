extends Node
## Visual check: SMOKE=shot godot --path . -> flies a bit, saves screenshots to the project folder, quits.

var frames := 0


func _ready() -> void:
	process_priority = -10 # press keys before the heli reads them
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	frames += 1
	if frames == 30:
		Input.action_press("land")
	if frames == 32:
		Input.action_release("land")
		Input.action_press("move_right")
	if frames == 200:
		Input.action_release("move_right")
		_save("shot_flight.png")
	if frames == 210:
		Game.time = 0.9
		for i in 8:
			Game.world.spawn_enemy(["walker", "runner", "spitter", "flyer"][i % 4], Game.heli.position + Vector2(120, 0).rotated(i * TAU / 8))
		Input.action_press("fire")
	if frames == 240:
		_save("shot_night_combat.png")
		Input.action_release("fire")
		Game.add_xp(100)
	if frames == 250:
		_save("shot_levelup.png")
		while get_tree().paused:
			Game.world.choice_ui.pick(0)
		Game.heli.position = Game.world.BASE_POS
		Game.heli.vel = Vector2.ZERO
		Input.action_press("land")
	if frames == 252:
		Input.action_release("land")
	if frames == 400:
		_save("shot_base.png")
		get_tree().quit()


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://" + name)
