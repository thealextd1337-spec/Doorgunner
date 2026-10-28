extends Node
## Visual check: SMOKE=shot godot --path . -> flies a bit, saves screenshots to the project folder, quits.
## Time-based so it works at any refresh rate.

var t := 0.0
var step := 0


func _ready() -> void:
	process_priority = -10 # press keys before the heli reads them
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	t += delta
	match step:
		0:
			if t > 0.5:
				Input.action_press("land")
				step = 1
		1:
			Input.action_release("land")
			Input.action_press("move_right")
			step = 2
		2:
			if t > 5.0: # 1.5 s spool + ~3 s flight
				Input.action_release("move_right")
				_save("shot_flight.png")
				step = 3
		3:
			Game.time = 0.9
			for i in 8:
				Game.world.spawn_enemy(["shambler", "runner", "brute", "shambler"][i % 4], Game.heli.position + Vector2(120, 0).rotated(i * TAU / 8))
			Input.action_press("fire")
			step = 4
		4:
			if t > 5.6:
				_save("shot_night_combat.png")
				Input.action_release("fire")
				Game.add_xp(100)
				step = 5
		5:
			if t > 5.8:
				_save("shot_levelup.png")
				while get_tree().paused:
					Game.world.choice_ui.pick(0)
				Game.heli.position = Game.world.BASE_POS
				Game.heli.vel = Vector2.ZERO
				Input.action_press("land")
				step = 6
		6:
			Input.action_release("land")
			step = 7
		7:
			if t > 8.0: # 1.5 s landing spool, then the base menu is open
				_save("shot_base.png")
				for c in Game.world.get_children():
					if c is CanvasLayer and c.layer == 25:
						c.open()
				step = 8
		8:
			if t > 8.3:
				_save("shot_settings.png")
				get_tree().quit()


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://" + name)
