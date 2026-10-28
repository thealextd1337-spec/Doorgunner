extends Node
## Headless pathfinding test (main.gd nav_path / nav_move). main.gd adds this node when env SMOKE=nav:
##   SMOKE=nav godot --headless --path . --quit-after 30000

const T := preload("res://scripts/chunk_manager.gd").T


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var process_frame := get_tree().process_frame
	await process_frame
	await process_frame
	var chunks: TileMapLayer = main.chunks
	for x in range(26, 57):
		for y in range(4, 47):
			chunks.set_cell(Vector2i(x, y), 0, Vector2i(T.GRASS, 0))
	# a U of houses open to the east, the zombie inside it, its target due west behind the U
	for i in range(12, 21):
		chunks.set_cell(Vector2i(40, i), 0, Vector2i(T.BUILDING, 0))
	for x in range(40, 49):
		chunks.set_cell(Vector2i(x, 12), 0, Vector2i(T.BUILDING, 0))
		chunks.set_cell(Vector2i(x, 20), 0, Vector2i(T.BUILDING, 0))
	main.nav_dirty()
	var target := Vector2(32 * 16 + 8, 16 * 16 + 8)
	assert(main._line_blocked(Vector2(44 * 16 + 8, 16 * 16 + 8), target), "the U blocks the straight line")
	# cost: 50 walkers inside the U replanning at once on a cold cache
	var dummies: Array[Node2D] = []
	for i in 50:
		var n := Node2D.new()
		n.position = Vector2(randf_range(41.2, 47.8), randf_range(13.2, 19.8)) * 16.0
		add_child(n)
		dummies.append(n)
	var t0 := Time.get_ticks_usec()
	for n in dummies:
		main.nav_move(n, target, 16.0, 0.016, {})
	print("NAV 50 blocked nav_move calls: %.3f ms each (cold cache)" % ((Time.get_ticks_usec() - t0) / 50000.0))
	main.nav_dirty()
	t0 = Time.get_ticks_usec()
	for n in dummies:
		n.position = target + Vector2(400, 0).rotated(randf() * TAU)
		main.nav_path(n.position, target)
	print("NAV worst case: %.3f ms per nav_path, 50 walkers 400 px out, cold cache" % ((Time.get_ticks_usec() - t0) / 50000.0))
	for n in dummies:
		n.free()
	# a shambler (driven through its own _walk) gets out of the U and round to the target without entering a house
	var z: Node2D = main.spawn_enemy("shambler", Vector2(44 * 16 + 8, 16 * 16 + 8))
	z.set_process(false)
	z.hp = 1e6
	z.speed = 80.0
	var start := Time.get_ticks_msec()
	while z.position.distance_to(target) > 12.0 and Time.get_ticks_msec() - start < 20000:
		z._walk(target, get_process_delta_time())
		assert(chunks.tile_at(z.position) != T.BUILDING, "zombie walked into a house at %s" % z.position)
		await process_frame
	assert(z.position.distance_to(target) <= 12.0, "zombie reached the target: %s" % z.position)
	z.free()
	# a survivor walks around a hedge to the heli
	for i in range(34, 43):
		chunks.set_cell(Vector2i(40, i), 0, Vector2i(T.HEDGE, 0))
	main.nav_dirty()
	var heli := Node2D.new()
	heli.position = Vector2(43 * 16 + 8, 38 * 16 + 8)
	main.add_child(heli)
	var s: Node2D = preload("res://scripts/survivor.gd").new()
	s.position = Vector2(37 * 16 + 8, 38 * 16 + 8)
	main.add_child(s)
	var arrived := [false]
	s.arrived.connect(func(): arrived[0] = true)
	s.target = heli
	start = Time.get_ticks_msec()
	while not arrived[0] and Time.get_ticks_msec() - start < 15000:
		assert(chunks.tile_at(s.position) != T.HEDGE, "survivor walked into the hedge at %s" % s.position)
		await process_frame
	assert(arrived[0], "survivor reached the heli: %s" % s.position)
	print("NAV OK")
	get_tree().quit(0)
