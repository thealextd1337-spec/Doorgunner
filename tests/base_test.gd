extends Node
## Headless base test. main.gd adds this node when env SMOKE=base:
##   SMOKE=base godot --headless --path . --quit-after 8000
## Landing services, base menu purchase and turret fire.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var process_frame := get_tree().process_frame
	await process_frame
	await process_frame
	Game.passengers = 3
	Game.fuel = 10.0
	Game.scrap = 100
	Game.heli.landed_changed.emit(true)
	for i in 3:
		await process_frame
	assert(Game.rescued == 3, "passengers delivered")
	assert(Game.passengers == 0, "cabin emptied")
	assert(Game.fuel == Game.max_fuel, "refuelled")
	assert(Game.ammo == Game.max_ammo, "rearmed")
	assert(main.ui_open, "base menu open")
	var scrap0: int = Game.scrap
	assert(main.base.ui.buy("turrets"), "turret purchase accepted")
	assert(Game.base_level["turrets"] == 1, "turret level stored")
	assert(Game.scrap < scrap0, "scrap spent")
	assert(main.base.turrets.get_child_count() == 1, "turret node placed")
	assert(not main.base.ui.buy("barracks"), "barracks needs 8 rescued")
	var e: Node2D = main.spawn_enemy("walker", main.base.position + Vector2(100, 0), true)
	for i in 600:
		await process_frame
		if not is_instance_valid(e) or e.hp < e.max_hp:
			break
	assert(not is_instance_valid(e) or e.hp < e.max_hp, "turret hit the enemy")
	Game.heli.landed_changed.emit(false)
	await process_frame
	assert(not main.ui_open, "takeoff closes menu")
	print("BASE OK  scrap=%d base_hp=%d" % [Game.scrap, Game.base_hp])
	get_tree().quit(0)
