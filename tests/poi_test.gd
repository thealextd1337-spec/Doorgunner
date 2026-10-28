extends Node
## Headless POI test. main.gd adds this node when env SMOKE=poi:
##   SMOKE=poi godot --headless --path . --quit-after 3000


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var heli: Node2D = Game.heli
	var process_frame := get_tree().process_frame
	var rng := RandomNumberGenerator.new()
	await process_frame
	await process_frame
	# settlement: land next to it, survivors walk over and board (base paused: it would call a settlement this close in)
	main.base.set_process(false)
	var poi: Node2D = main.spawn_poi("survivors", heli.position + Vector2(30, 0), rng)
	assert(poi.survivors.size() >= 2, "survivors spawned")
	var p0: int = Game.passengers
	_land(heli, true)
	assert(poi.loading, "loading started")
	for i in 900:
		await process_frame
		if Game.passengers > p0:
			break
	assert(Game.passengers > p0, "survivor boarded")
	assert(Game.xp >= 4, "xp for boarding")
	assert(get_tree().get_nodes_in_group("enemies").size() >= 2, "LZ wave called (call_wave spawns 2)")
	_land(heli, false)
	assert(not poi.loading and not poi.done, "loading stops on takeoff, settlement stays")
	# crate: refills ammo/fuel, gives scrap
	Game.ammo = 0
	Game.fuel = 10.0
	var scrap0: int = Game.scrap
	var crate: Node2D = main.spawn_poi("crate", heli.position + Vector2(-30, 0), rng)
	_land(heli, true)
	assert(Game.ammo > 0 and Game.fuel > 10.0 and Game.scrap > scrap0 and crate.done, "crate looted")
	assert(crate.where(Vector2.ZERO, Vector2(0, -1000)) == "100 m north", "bearing text")
	# a zombie next to a waiting survivor wounds, then kills it (no per-settlement cap)
	var cc := Vector2i(((heli.position + Vector2(-200, 160)) / 16.0).floor())
	for x in range(-4, 5): # open ground: founding no longer clears the area around the pad
		for y in range(-4, 5):
			main.chunks.set_cell(cc + Vector2i(x, y), 0, Vector2i(main.T.GRASS, 0))
	main.nav_dirty()
	var camp: Node2D = main.spawn_poi("survivors", heli.position + Vector2(-200, 160), rng)
	await process_frame
	var victim: Node2D = camp.survivors[0]
	var n0: int = camp.survivors.size()
	main.spawn_enemy("runner", victim.global_position + Vector2(14, 0))
	var t0 := Time.get_ticks_msec()
	while camp.survivors.size() == n0 and Time.get_ticks_msec() - t0 < 5000:
		await process_frame
	assert(camp.survivors.size() == n0 - 1, "zombie killed a waiting survivor")
	poi.queue_free()
	main.pois.erase(poi)
	camp.queue_free()
	main.pois.erase(camp)
	main.base.set_process(true)
	# a settlement inside the fence walks to the pad on its own and moves in (no zombies left to catch them on the way)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	var r0: int = Game.rescued
	var near: Node2D = main.spawn_poi("survivors", main.BASE_POS + Vector2(-60, -40), rng, 2)
	t0 = Time.get_ticks_msec()
	while not near.done and Time.get_ticks_msec() - t0 < 8000:
		await process_frame
		while get_tree().paused: # moving in gives XP: pick level-up cards
			main.choice_ui.pick(0)
	assert(near.walking_home and near.done and Game.rescued == r0 + 2, "nearby settlement moved in: rescued %d" % Game.rescued)
	# a zombie walled in by houses chews its way out: the BUILDING cell towards its target turns to RUIN
	var T: Dictionary = preload("res://scripts/chunk_manager.gd").T
	var wall := Vector2i(34, 16) # due east of the base centre, so the zombie pushes straight into it
	for x in range(-1, 2):
		for y in range(-1, 2):
			main.chunks.set_cell(wall + Vector2i(1 + x, y), 0, Vector2i(T.BUILDING if x != 0 or y != 0 else T.GRASS, 0))
	main.nav_dirty()
	main.spawn_enemy("shambler", Vector2((wall.x + 1) * 16.0 + 4.0, main.BASE_POS.y), true)
	t0 = Time.get_ticks_msec()
	while main.chunks.tile_at(Vector2(wall) * 16.0 + Vector2(8, 8)) == T.BUILDING and Time.get_ticks_msec() - t0 < 14000:
		await process_frame
	assert(main.chunks.tile_at(Vector2(wall) * 16.0 + Vector2(8, 8)) == T.RUIN, "zombie broke into the house")
	print("POI OK")
	get_tree().quit(0)


func _land(heli: Node2D, landed: bool) -> void:
	heli.landed = landed
	heli.landed_changed.emit(landed)
