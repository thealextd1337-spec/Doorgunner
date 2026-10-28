extends Node
## Headless test of the heli systems and weapon Lv5 effects. main.gd adds this node when env SMOKE=prog:
##   SMOKE=prog godot --headless --path . --quit-after 30000
## Each system is taken as a card, then a few frames run with the heli hovering.


func _ready() -> void:
	Engine.max_fps = 120 # frame waits below map to real seconds
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var main: Node2D = Game.world
	var heli: Node2D = Game.heli
	await _frames(2)
	main.spawner.horde_cd = 1e9 # no random hordes in the way
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	heli.landed = false
	heli.position = main.BASE_POS + Vector2(400, 0)
	heli.body.rotation = PI / 2 # nose east
	Game.time = 0.0 # midnight
	# searchlight: of two zombies walking to the base, the one in the cone moves slower
	Game.take_item("searchlight")
	for c in 16: # plain grass under both walks (the seed is random: no forest or houses in the way)
		for r in 16:
			main.chunks.set_cell(Vector2i((heli.position / 16.0).floor()) + Vector2i(c - 4, r - 4), 0, Vector2i(0, 0))
	var lit: Node2D = main.spawn_enemy("shambler", heli.position + Vector2(100, 0), true)
	var dark: Node2D = main.spawn_enemy("shambler", heli.position + Vector2(0, 100), true)
	lit.speed = 20.0
	dark.speed = 20.0
	var p_lit := lit.position
	var p_dark := dark.position
	await _frames(120)
	var d_lit := lit.position.distance_to(p_lit)
	var d_dark := dark.position.distance_to(p_dark)
	assert(d_lit < d_dark * 0.85, "searchlight slows the lit zombie: %.1f vs %.1f" % [d_lit, d_dark])
	lit.queue_free()
	dark.queue_free()
	# flares: the flare's noise pulls Game.noise_pos to it
	Game.take_item("flares")
	Game.noise_level = 0.0
	var flare: Node2D = heli.get_node("flares").drop()
	await _frames(2)
	assert(Game.noise_pos.distance_to(flare.position) < 1.0 and Game.noise_pos.distance_to(heli.position) > 30.0, "flare noise moved noise_pos")
	# winch: hovering next to a settlement hoists a survivor without landing
	Game.take_item("winch")
	var poi: Node2D = main.spawn_poi("survivors", heli.position + Vector2(30, 0), RandomNumberGenerator.new())
	heli.vel = Vector2.ZERO
	heli.get_node("winch").cd = 0.0
	var p0: int = Game.passengers
	await _frames(3)
	assert(Game.passengers == p0 + 1 and not heli.landed, "winch boarded a survivor: %d" % Game.passengers)
	poi.queue_free()
	main.pois.erase(poi)
	# medic: hull regenerates in flight
	Game.take_item("medic")
	Game.hp = 50.0
	await _frames(60)
	assert(Game.hp > 50.0, "medic regenerates hull: %.2f" % Game.hp)
	# supply drop: a reduced crate lands under the heli (base pad is landable)
	Game.take_item("supply")
	heli.position = main.BASE_POS
	var n0: int = main.pois.size()
	heli.get_node("supply").cd = 0.0
	await _frames(2)
	assert(main.pois.size() == n0 + 1 and main.pois[-1].kind == "crate" and main.pois[-1].drop_level == 1, "supply crate dropped")
	# railgun chain: a bolt hitting one zombie jumps to a second one off its line
	heli.position = main.BASE_POS + Vector2(-600, 0)
	var e1: Node2D = main.spawn_enemy("shambler", heli.position + Vector2(100, 0))
	var e2: Node2D = main.spawn_enemy("shambler", heli.position + Vector2(100, 90))
	var b: Node2D = preload("res://scripts/bullet.gd").new()
	b.setup(heli.position + Vector2(40, 0), Vector2.RIGHT, 1.0, 99, 300.0, 1.0)
	b.chain = 2
	main.add_child(b)
	await _frames(90)
	assert(e1.hp < e1.max_hp and e2.hp < e2.max_hp, "railgun chain hit a second target")
	e1.queue_free()
	e2.queue_free()
	# co-gunner: holds fire without ammo, then shoots and kills a nearby zombie on its own, 1 round per 3 shots
	Game.take_item("cogunner")
	var cg: Node = heli.get_node("cogunner")
	Game.ammo = 0
	var z: Node2D = main.spawn_enemy("shambler", heli.position + Vector2(120, 0))
	z.hp = 3.0
	await _frames(60)
	assert(cg.shots == 0 and is_instance_valid(z), "co-gunner holds fire with no ammo")
	Game.ammo = 50
	await _frames(240)
	assert(not is_instance_valid(z), "co-gunner killed the zombie")
	z = main.spawn_enemy("brute", heli.position + Vector2(120, 0))
	z.hp = 1e9
	await _frames(240)
	assert(cg.shots >= 3 and Game.ammo == 50 - floori(cg.shots / 3.0), "co-gunner pays 1 round per 3 shots: %d shots, %d ammo" % [cg.shots, Game.ammo])
	z.queue_free()
	print("PROG OK  systems=%d" % heli.get_children().filter(func(c): return Progression.ITEMS.has(str(c.name))).size())
	get_tree().quit(0)
