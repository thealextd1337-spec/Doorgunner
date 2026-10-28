extends Node
## Headless base test. main.gd adds this node when env SMOKE=base:
##   SMOKE=base godot --headless --path . --quit-after 8000
## Landing services from stock, base menu purchase, turret fire, weapon find + Q cycle, loadout, workers, sandbags, militia,
## then block 2: rifles, perimeter, barracks/campers, water, sickness, clinic, generator.


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
	var e: Node2D = main.spawn_enemy("shambler", main.base.position + Vector2(100, 0), true)
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
	var e1: Node2D = main.spawn_enemy("shambler", main.base.position + Vector2(300, 0), true)
	var e2: Node2D = main.spawn_enemy("shambler", main.base.position + Vector2(330, 0), true)
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
	assert(main.base.ui.set_worker("fuel", 2) and Game.idle_workers() == 0, "fuel workers assigned (2 hangar beds, 1 camper)")
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
	# a bigger tank bought while parked is filled at once from stock
	Game.base_fuel = 500.0
	Game.scrap = 200
	var max0: float = Game.max_fuel
	assert(main.base.ui.buy("fuel"), "fuel depot bought")
	assert(Game.max_fuel == max0 + 25.0, "max fuel grew")
	assert(Game.fuel == Game.max_fuel, "tank topped up right after the purchase: %s/%s" % [Game.fuel, Game.max_fuel])
	# sandbags: a blueprint costs 5 scrap, a build worker finishes it, zombies chew on it instead of the base
	var cell := Vector2i(((main.base.position + Vector2(100, 0)) / 16.0).floor())
	scrap0 = Game.scrap
	assert(main.base.place_sandbag(cell) and Game.scrap == scrap0 - 5, "blueprint placed for 5 scrap")
	assert(Game.sandbags.has(cell) and not Game.sandbags[cell]["built"], "blueprint stored")
	assert(not main.base.place_sandbag(cell), "no double placement")
	assert(not main.base.place_sandbag(Vector2i((main.base.position / 16.0).floor())), "helipad rejected")
	assert(main.base.ui.set_worker("fuel", 0) and main.base.ui.set_worker("build", 1), "build worker assigned")
	main.base.build_progress = 1.0
	await process_frame
	assert(Game.sandbags[cell]["built"] and main.base.bags[cell].modulate.a == 1.0, "build worker finished the sandbag")
	var z: Node2D = main.spawn_enemy("shambler", main.base.position + Vector2(114, 0), true)
	z.hp = 1e6 # the turret must not kill it before it reaches the sandbag
	var bhp: float = Game.base_hp
	for i in 3000:
		await process_frame
		if not Game.sandbags.has(cell) or Game.sandbags[cell]["hp"] < Game.SANDBAG_HP:
			break
	assert(Game.sandbags.has(cell) and Game.sandbags[cell]["hp"] < Game.SANDBAG_HP, "zombie struck the sandbag")
	assert(Game.base_hp == bhp, "base untouched behind the sandbag")
	z.free()
	main.base.remove_sandbag(cell)
	assert(not Game.sandbags.has(cell) and Game.scrap == scrap0 - 5, "built sandbag torn down without refund")
	# militia man the defence during an assault, stand down afterwards
	assert(main.base.ui.set_worker("build", 0) and main.base.ui.set_worker("militia", 2), "militia assigned")
	Game.attack_active = true
	Game.base_attack_started.emit(3)
	assert(main.base.defenders.get_child_count() == 2 and main.base.defenders.get_child(0).rifle, "2 defenders posted")
	Game.attack_active = false
	await process_frame
	await process_frame
	assert(main.base.defenders.get_child_count() == 0, "defenders stood down")
	# block 2: a militia post without a rifle never fires
	assert(main.base.ui.set_worker("militia", 1), "one militia")
	Game.base_rifles = 0.0
	Game.attack_active = true
	Game.base_attack_started.emit(3)
	main.spawner.wave_left = 0
	var post: Node2D = main.base.defenders.get_child(0)
	assert(not post.armed, "no rifle, unarmed")
	var z2: Node2D = main.spawn_enemy("shambler", post.global_position + Vector2(40, 0), true)
	z2.hp = 1e6
	for i in 20:
		await process_frame
	assert(post.cd <= 0.0, "unarmed militia never fired")
	z2.free()
	Game.attack_active = false
	await process_frame
	# perimeter stage: 60 scrap, 60 s of building, +60 px
	assert(main.base.ui.set_worker("militia", 0) and main.base.ui.set_worker("build", 1), "builder assigned")
	Game.scrap = 300
	assert(main.base.expand_perimeter() and Game.scrap == 240, "perimeter stage for 60 scrap")
	assert(not main.base.expand_perimeter(), "one stage at a time")
	Game.buildings[0]["progress"] = 59.99
	await process_frame
	await process_frame
	assert(Game.base_radius == 220.0, "perimeter grew: %s" % Game.base_radius)
	# barracks: blueprint, built by the worker, 4 more beds, no landing on it
	assert(Game.campers() == 1, "3 rescued, 2 hangar beds")
	var bcell := Vector2i(((main.base.position + Vector2(-20, 60)) / 16.0).floor())
	assert(main.base.place_building("barracks", bcell) and Game.scrap == 200, "barracks blueprint for 40")
	assert(not main.base.place_sandbag(bcell + Vector2i(1, 1)), "no sandbag on a blueprint")
	Game.buildings[1]["progress"] = 89.99
	await process_frame
	await process_frame
	assert(Game.housing() == 6 and Game.campers() == 0, "barracks built")
	assert(not main.is_landable(main.base.cell_pos(bcell)), "no landing on a building")
	# water: 3 drink 1 a day each; a dry dawn makes one sick
	var w0: float = Game.base_water
	for i in 5:
		await process_frame
	assert(Game.base_water < w0, "water drunk")
	Game.base_water = 0.0
	Game.time = 0.99999
	await process_frame
	assert(Game.injured == 1, "sick without water")
	Game.buildings.append({"kind": "well", "cell": Vector2i(-99, -99), "built": true, "progress": 0.0})
	w0 = Game.base_water
	for i in 5:
		await process_frame
	assert(Game.base_water > w0, "a well (8/day) outpaces 3 drinkers")
	# clinic: a bed for 1 medicine, then the patient recovers
	Game.buildings.append({"kind": "clinic", "cell": Vector2i(-99, -90), "built": true, "progress": 0.0})
	Game.base_medicine = 1.0
	await process_frame
	assert(Game.treating.size() == 1 and Game.base_medicine == 0.0, "patient in bed for 1 medicine")
	Game.treating[0] = 0.00001
	await process_frame
	assert(Game.injured == 0 and Game.treating.is_empty(), "clinic healed the patient")
	# generator: burns base fuel, power while it lasts
	Game.buildings.append({"kind": "generator", "cell": Vector2i(-99, -80), "built": true, "progress": 0.0})
	Game.base_fuel = 100.0
	for i in 3:
		await process_frame
	assert(Game.power and Game.base_fuel < 100.0, "generator burns fuel, power on")
	Game.base_fuel = 0.0
	await process_frame
	assert(not Game.power, "no fuel, no power")
	# campers outside the wire get hurt when the assault starts
	Game.rescued = 8
	Game.tutorial_wave = 1
	Game.attack_pending = true
	Game.time = 0.8
	await process_frame
	assert(Game.attack_active and Game.injured == 1, "a camper was hurt by the wave")
	print("BASE OK  scrap=%d base_hp=%d weapon=%s base_fuel=%.2f" % [Game.scrap, Game.base_hp, Game.weapon, Game.base_fuel])
	get_tree().quit(0)
