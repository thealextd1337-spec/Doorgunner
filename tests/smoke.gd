extends Node
## Headless smoke test. main.gd adds this node when env SMOKE=1:
##   SMOKE=1 godot --headless --path . --quit-after 2000
## Simulates flight and asserts the core loop holds together.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var process_frame := get_tree().process_frame
	await process_frame
	await process_frame
	assert(Game.running, "run should start")
	assert(Game.heli.landed, "heli starts landed on the pad")
	assert(main.chunks.loaded.size() >= 25, "chunks around base generated")
	# take off and fly north-east for a while
	Input.action_press("land")
	await process_frame
	Input.action_release("land")
	for i in 20000:
		await process_frame
		if not Game.heli.landed:
			break
	assert(not Game.heli.landed, "took off after spool")
	Input.action_press("move_right")
	Input.action_press("move_up")
	var fuel0 := Game.fuel
	for i in 6000:
		await process_frame
		if Game.heli.position.x > main.BASE_POS.x + 600.0:
			break
	Input.action_release("move_right")
	Input.action_release("move_up")
	assert(Game.heli.position.x > main.BASE_POS.x + 100, "heli moved: %s" % Game.heli.position)
	assert(Game.fuel < fuel0, "fuel burned")
	assert(main.chunks.loaded.size() > 25, "new chunks generated while flying")
	# fire a few rounds
	var ammo0 := Game.ammo
	Input.action_press("fire")
	for i in 20:
		await process_frame
	Input.action_release("fire")
	assert(Game.ammo < ammo0, "ammo consumed")
	# spawn an enemy and hit it with a bullet
	var e: Node2D = main.spawn_enemy("shambler", Game.heli.position + Vector2(40, 0))
	var b := preload("res://scripts/bullet.gd").new()
	b.setup(Game.heli.position, Vector2.RIGHT, 1000.0, 0)
	main.add_child(b)
	for i in 600:
		await process_frame
		if not is_instance_valid(b):
			break
	assert(not is_instance_valid(e) or e.is_queued_for_deletion(), "enemy killed by bullet")
	assert(Game.kills == 1, "kill counted")
	# day clock
	Game.time = 1.0
	await process_frame
	assert(Game.day == 2, "day rolled over")
	print("SMOKE OK  pois=%d enemies=%d xp=%d" % [main.pois.size(), get_tree().get_nodes_in_group("enemies").size(), Game.xp])
	get_tree().quit(0)
