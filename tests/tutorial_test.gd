extends Node
## Headless tutorial test. main.gd adds this node when env SMOKE=tut:
##   SMOKE=tut godot --headless --path . --quit-after 30000
## Step 0 (found the base) passes on the pre-founded test base, 1-4 played through (take off, fly, land, board, fly home, land),
## 5-7 by direct calls, then the forced assault.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var heli: Node2D = Game.heli
	var process_frame := get_tree().process_frame
	var prev_done: int = Game.meta["tutorial_done"]
	await process_frame
	await process_frame
	main.start_tutorial()
	var tut: Node = main.tutorial
	assert(tut.step == 0 and tut.settlement == null, "step 0: found the base, no settlement yet")
	await process_frame # the base is already founded (main.gd test hook): step 0 passes, the settlement appears
	assert(tut.step == 1, "step 0 done: base founded")
	var s: Node2D = tut.settlement
	assert(s.survivors.size() == 3 and main.radio_target == s, "settlement of 3 marked")
	assert(s.position.distance_to(main.BASE_POS) < 900.0 and main.is_landable(s.position), "close, on landable ground")
	# 1. take off
	await _press_land(heli)
	assert(not heli.landed and tut.step == 2, "step 1 done: airborne")
	# 2. fly over (placed next to it; flight itself is covered by the smoke test)
	heli.position = s.position + Vector2(100, 0)
	await process_frame
	assert(tut.step == 3, "step 2 done: within 160 px")
	# 3. land on the settlement, people board; zombies are cleared so the test is deterministic
	heli.position = s.position
	heli.vel = Vector2.ZERO
	await _press_land(heli)
	assert(heli.landed, "landed at the settlement")
	for i in 3000:
		await process_frame
		for e in get_tree().get_nodes_in_group("enemies"):
			e.free()
		if Game.passengers >= 3:
			break
	assert(Game.passengers == 3 and tut.step == 4, "all 3 aboard, step 3 done")
	# 4. home
	await _press_land(heli)
	heli.position = main.BASE_POS
	heli.vel = Vector2.ZERO
	await _press_land(heli)
	while get_tree().paused: # delivery XP may level up: pick upgrades
		main.choice_ui.pick(0)
	await process_frame
	await process_frame
	assert(Game.rescued == 3 and tut.step == 5, "step 4 done: delivered")
	assert(Game.scrap >= 80, "construction scrap granted")
	# 5-7 by direct calls
	var cell := Vector2i(((main.BASE_POS + Vector2(-20, 60)) / 16.0).floor())
	assert(main.base.place_building("barracks", cell), "barracks blueprint")
	assert(main.base.ui.set_worker("build", 1), "build worker")
	await process_frame
	assert(tut.step == 6, "step 5 done")
	var n := 0
	for y in range(-4, 4):
		if main.base.place_sandbag(Vector2i(((main.BASE_POS + Vector2(80, y * 16)) / 16.0).floor())):
			n += 1
	assert(n >= 6, "6 sandbags east: %d" % n)
	await process_frame
	assert(tut.step == 7, "step 6 done")
	assert(main.base.ui.set_worker("militia", 1), "militia")
	await process_frame
	await process_frame
	assert(Game.meta["tutorial_done"] == 1 and main.tutorial == null, "tutorial done")
	assert(Game.attack_pending or Game.attack_active, "assault forced tonight")
	for i in 5000:
		await process_frame
		if Game.attack_active:
			break
	assert(Game.attack_active and main.spawner.wave_left <= 8, "small assault: %d" % main.spawner.wave_left)
	Game.meta["tutorial_done"] = prev_done # keep the player's own save as it was
	Game._save_meta()
	print("TUTORIAL OK  rescued=%d scrap=%d" % [Game.rescued, Game.scrap])
	get_tree().quit(0)


## SPACE, then wait out the 1.5 s spool.
func _press_land(heli: Node2D) -> void:
	var was: bool = heli.landed
	Input.action_press("land")
	await get_tree().process_frame
	Input.action_release("land")
	for i in 3000:
		await get_tree().process_frame
		if heli.landed != was and heli.pending == 0:
			return
