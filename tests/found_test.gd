extends Node
## Headless founding test. main.gd adds this node when env SMOKE=found (no pre-founded base for this one):
##   SMOKE=found godot --headless --path . --quit-after 30000
## The run starts without a base; founding over water is refused; fly 400 px east, land on open ground, B founds the FOB.

const T := preload("res://scripts/chunk_manager.gd").T


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var heli: Node2D = Game.heli
	var process_frame := get_tree().process_frame
	await process_frame
	await process_frame
	var start: Vector2 = heli.position
	assert(not Game.base_founded and not main.base.visible and Game.passengers == Game.FOUNDING_CREW, "no base, crew aboard")
	assert(Game.scrap == 60 and Game.base_level.is_empty() and Game.rescued == 0, "start supplies")
	assert(heli.landed and heli.can_found(), "landed on the cleared start patch")
	assert(main.BASE_POS == start, "BASE_POS is the start site before founding")
	assert("NO BASE" in main.hud.info.text and "[B]" in main.hud.hint.text, "HUD says how to found")
	# over water: refused (landing there is impossible, so the heli is set down by hand)
	var water := Vector2.INF
	for x in range(-60, 61):
		for y in range(-60, 61):
			var p: Vector2 = start + Vector2(x, y) * 16.0
			if water == Vector2.INF and main.chunks.tile_at(p) == T.WATER:
				water = p
	if water == Vector2.INF: # dry seed: make a pond
		water = start + Vector2(0, 400)
		main.chunks.set_cell(Vector2i((water / 16.0).floor()), 0, Vector2i(T.WATER, 0))
	heli.position = water
	await _press("found")
	assert(not Game.base_founded, "no base on water")
	heli.position = start
	# take off, fly 400 px east
	await _press("land")
	for i in 3000:
		await process_frame
		if not heli.landed and heli.pending == 0:
			break
	assert(not heli.landed, "took off")
	Input.action_press("move_right")
	for i in 6000:
		await process_frame
		if heli.position.x > start.x + 400.0:
			break
	Input.action_release("move_right")
	assert(heli.position.x > start.x + 400.0, "flew east: %s" % heli.position)
	# land on the nearest spot with 7x7 open ground (the terrain is random)
	var site := Vector2.INF
	for r in 30:
		for i in maxi(1, r * 8):
			var p: Vector2 = heli.position + Vector2(r * 32.0, 0).rotated(i * TAU / maxi(1, r * 8))
			if site == Vector2.INF and _open(main, p):
				site = p
	assert(site != Vector2.INF, "open ground near the heli")
	heli.position = site
	heli.vel = Vector2.ZERO
	await _press("land")
	for i in 3000:
		await process_frame
		if heli.landed and heli.pending == 0:
			break
	assert(heli.landed and not Game.base_founded, "landed, not founded yet")
	await _press("found")
	assert(Game.base_founded, "B founded the base")
	assert(main.BASE_POS.distance_to(heli.position) < 20.0 and main.base.position == main.BASE_POS and main.base.visible, "base at the heli")
	for o in [Vector2.ZERO, Vector2(-6, -6), Vector2(6, 6), Vector2(6, -6), Vector2(-6, 6)]:
		assert(main.chunks.tile_at(main.BASE_POS + o * 16.0) == T.BASE_FLOOR, "pad concrete at %s" % o)
	assert(Game.rescued == 4 and Game.passengers == 0 and Game.workers["build"] == 2, "crew moved in, 2 on Build")
	assert(Game.base_level.get("workshop", 0) == 1, "field workshop")
	assert(Game.first_assault_day == Game.day + 2 and Game.days_to_assault() == 2, "first assault on day + 2")
	assert(main.ui_open and main.base.ui.visible, "base menu open")
	await process_frame
	assert(main.base.pawns.get_child_count() == 4, "4 pawns")
	await _press("found")
	assert(main.BASE_POS.distance_to(heli.position) < 20.0 and Game.rescued == 4, "a second B does nothing")
	print("FOUND OK  base=%s" % main.BASE_POS)
	get_tree().quit(0)


func _open(main: Node2D, p: Vector2) -> bool:
	for x in range(-3, 4):
		for y in range(-3, 4):
			if not main.is_landable(p + Vector2(x, y) * 16.0):
				return false
	return true


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
