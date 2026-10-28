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
	# settlement: land next to it, survivors walk over and board
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
	print("POI OK")
	get_tree().quit(0)


func _land(heli: Node2D, landed: bool) -> void:
	heli.landed = landed
	heli.landed_changed.emit(landed)
