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
	# door gun arcs: straight ahead is out of reach, out of the side door fires
	var nose := Vector2.UP.rotated(Game.heli.body.rotation)
	Game.heli.aim_override = nose
	var ammo0 := Game.ammo
	Input.action_press("fire")
	for i in 20:
		await process_frame
	assert(Game.ammo == ammo0 and Game.heli.no_angle > 0.0, "no shot straight ahead")
	Game.heli.aim_override = nose.orthogonal()
	for i in 20:
		await process_frame
	Input.action_release("fire")
	Game.heli.aim_override = Vector2.ZERO
	# Q swings the nose
	var rot0: float = Game.heli.body.rotation
	Input.action_press("yaw_left")
	for i in 400:
		await process_frame
	Input.action_release("yaw_left")
	assert(absf(angle_difference(rot0, Game.heli.body.rotation)) > 0.05, "Q turned the heli")
	assert(Game.ammo < ammo0, "ammo consumed firing sideways")
	for c in main.get_children():
		if c.get_script() == preload("res://scripts/bullet.gd"):
			assert(c.life <= 420.0 / 520.0 + 0.001, "bullet lifetime follows the weapon range: %s" % c.life)
			break
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
	assert(Game.version_text().begins_with("v%s (" % ProjectSettings.get_setting("application/config/version")), "version text: " + Game.version_text())
	print("SMOKE OK  pois=%d enemies=%d xp=%d" % [main.pois.size(), get_tree().get_nodes_in_group("enemies").size(), Game.xp])
	get_tree().quit(0)
