extends Node
## Headless base test. main.gd adds this node when env SMOKE=base:
##   SMOKE=base godot --headless --path . --quit-after 8000
## Landing services from stock, base menu purchase, turret fire, weapon find + Q cycle, loadout, workers.


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var process_frame := get_tree().process_frame
	await process_frame
	await process_frame
	Game.passengers = 3
	Game.fuel = 10.0
	Game.ammo = 0
	Game.base_fuel = 10.0
	Game.scrap = 100
	Game.heli.landed_changed.emit(true)
	for i in 3:
		await process_frame
	assert(Game.rescued == 3, "passengers delivered")
	assert(Game.passengers == 0, "cabin emptied")
	assert(is_equal_approx(Game.fuel, 20.0) and Game.base_fuel == 0.0, "partial refuel from stock")
	assert(Game.ammo == Game.max_ammo and Game.base_ammo == 800.0 - Game.max_ammo, "rearmed from stock")
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
	# weapons cache next to the pad: forced weapon branch fills the second heli slot and auto-equips
	var cache: Node2D = main.spawn_poi("upgrade", Game.heli.position + Vector2(30, 0), RandomNumberGenerator.new())
	cache.force_weapon = true
	Game.heli.landed_changed.emit(true)
	await process_frame
	assert(cache.done and Game.heli_weapons.size() == 2 and Game.weapon != "mg", "weapon found and mounted: %s" % Game.weapon)
	var found: String = Game.weapon
	Input.action_press("weapon_swap")
	await process_frame
	Input.action_release("weapon_swap")
	await process_frame
	assert(Game.weapon == "mg", "Q cycles back to the MG")
	main.base.ui.stow(found)
	assert(Game.weapon_bay == [found] and Game.heli_weapons == ["mg"], "stowed in the bay")
	main.base.ui.mount(found)
	assert(Game.weapon_bay.is_empty() and Game.heli_weapons.size() == 2, "mounted again")
	# splash bullet hits both enemies around the impact point
	var e1: Node2D = main.spawn_enemy("walker", main.base.position + Vector2(300, 0), true)
	var e2: Node2D = main.spawn_enemy("walker", main.base.position + Vector2(330, 0), true)
	var b: Node2D = preload("res://scripts/bullet.gd").new()
	b.setup(e1.position, Vector2.RIGHT, 1.0, 0, 380.0, 1.3, 60.0)
	main.add_child(b)
	await process_frame
	assert(e1.hp < e1.max_hp and e2.hp < e2.max_hp, "splash damaged both")
	# loadout: +1 seat recomputes seats, budget blocks overspend
	var seats0: int = Game.seats
	assert(main.base.ui.set_loadout("seats", 5) and Game.seats == seats0 + 1, "loadout seat recomputed")
	assert(Game.loadout_points() == 9 and Game.weight_factor < 1.0, "weight penalty above 8 pts")
	assert(not main.base.ui.set_loadout("armor", 1), "over budget rejected")
	# workers: 3 rescued, 2 on fuel duty produce stock over time
	assert(main.base.ui.set_worker("fuel", 2) and Game.idle_workers() == 1, "fuel workers assigned")
	assert(not main.base.ui.set_worker("ammo", 2), "no idle left for two more")
	var t0: float = Game.time
	for i in 2000:
		await process_frame
		if Game.base_fuel > 0.0:
			break
	assert(Game.time > t0 and Game.base_fuel > 0.0, "workers produced fuel")
	Game.heli.landed_changed.emit(false)
	await process_frame
	assert(not main.ui_open, "takeoff closes menu")
	print("BASE OK  scrap=%d base_hp=%d weapon=%s base_fuel=%.2f" % [Game.scrap, Game.base_hp, Game.weapon, Game.base_fuel])
	get_tree().quit(0)
