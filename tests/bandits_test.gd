extends Node
## Headless test of the bandit faction (scripts/bandits.gd, bandit.gd, technical.gd). main.gd adds this node when
## env SMOKE=bandits:   SMOKE=bandits godot --headless --path . --quit-after 30000
## Units are stepped by hand (process disabled, unit._process(dt)) so a minute of fighting takes no real time.

const ROADS := preload("res://scripts/chunk_manager.gd").ROADS
const T := preload("res://scripts/chunk_manager.gd").T

var main: Node2D
var sys: Node
var heli: Node2D
var frame: Signal
var sources := [] # heli.damaged sources


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	sys = main.bandits
	heli = Game.heli
	frame = get_tree().process_frame
	await frame
	await frame
	main.spawner.set_process(false)
	sys.set_process(false)
	heli.set_process(false) # no fuel burn, no input: a still target
	heli.landed = false
	Game.level = Game.LEVEL_CAP # kills would offer upgrade cards and pause the game
	Game.time = 0.5
	Game.run_ended.connect(func(r: String): print("RUN ENDED: ", r))
	heli.damaged.connect(func(_a: float, s: String): sources.append(s))
	print("bandits test seed ", Game.seed) # the world is random per run: a failure names its seed
	assert(Save._hooks.has("bandits"), "bandits registers a save hook")
	_table()
	_sites()
	_camp()
	await _capped_camp()
	_technical()
	_shoots_heli()
	_rocket_and_flare()
	_zombies()
	_raids()
	_save_load()
	await _live()
	print("BANDITS OK")
	get_tree().quit(0)


func _unit(kind: String, pos: Vector2, role := "guard", camp := "") -> Node2D:
	var u: Node2D = sys.spawn_unit(kind, pos, role, pos, camp)
	u.process_mode = Node.PROCESS_MODE_DISABLED
	return u


func _step(nodes: Array, seconds: float, dt := 0.1) -> void:
	for i in int(seconds / dt):
		for n in nodes:
			if is_instance_valid(n) and not n.is_queued_for_deletion():
				n._process(dt)


func _hold_all() -> void:
	for u in get_tree().get_nodes_in_group("bandits"):
		u.process_mode = Node.PROCESS_MODE_DISABLED


## Bandits, rockets and zombies (stray zombies near the start would draw the bandits' fire).
func _clear_units() -> void:
	for u in get_tree().get_nodes_in_group("bandits") + get_tree().get_nodes_in_group("rockets") + get_tree().get_nodes_in_group("enemies").filter(func(e): return "target_base" in e):
		u.remove_from_group("enemies")
		u.remove_from_group("bandits") # gone for the group lookups of this frame already
		u.queue_free()


## An open, walkable spot about `dist` px from `center` (searching farther out on wet or rocky seeds).
func _spot(center: Vector2, dist: float) -> Vector2:
	for r in range(0, 40):
		var d := dist + r * 16.0
		for i in 32:
			var p := center + Vector2(d, 0).rotated(i * TAU / 32.0)
			if main.is_walkable(p) and main.is_walkable(center.lerp(p, 0.5)):
				return p
	assert(false, "no open spot near %s" % center)
	return center


## Open ground all the way (no house, hedge or woods): the zombie keeps sight of the bandit.
func _clear_line(a: Vector2, b: Vector2) -> bool:
	for i in 17:
		var at := a.lerp(b, i / 16.0)
		if not main.is_walkable(at) or main.chunks.tile_at(at) in [T.FOREST, T.TREE_EDGE, T.HEDGE]:
			return false
	return true


func _table() -> void:
	var d4 := SpawnTable.bandits(SpawnTable.CAMP_ROWS, 4)
	var d10 := SpawnTable.bandits(SpawnTable.CAMP_ROWS, 10)
	assert(d4["rifle"] == 3 and d4["mg"] == 1 and d4["rpg"] == 0 and d4["technical"] == 0, "day 4 camp: guards and an MG nest, %s" % d4)
	assert(d10["rpg"] == 1 and d10["technical"] == 1 and d10["rifle"] == 4, "day 10 camp: RPG and technical join, %s" % d10)
	assert(SpawnTable.bandits(SpawnTable.RAID_ROWS, 11).values().all(func(n): return n == 0), "no base raid party before day 12")
	for kind in Bandit.KINDS:
		assert(ResourceLoader.exists("res://assets/sprites/b/%s.png" % Bandit.KINDS[kind]["sprite"]), "%s has a sprite" % kind)
	for s in ["rocket", "bandit_flag"]:
		assert(ResourceLoader.exists("res://assets/sprites/b/%s.png" % s), "%s sprite" % s)


## Camps sit at the four landmark kinds only, none before CAMP_DAY, and once held a site stays held as days pass.
func _sites() -> void:
	var sites: Array = main.chunks.sites_near(Vector2.ZERO, 12000.0).filter(func(s): return s.kind in sys.CAMP_KINDS)
	assert(not sites.is_empty(), "camp landmarks exist within 12 km")
	var held := {}
	for day in [3, 4, 12, 30]:
		Game.day = day
		var n := 0
		for s in sites:
			var h: bool = sys.holds(s)
			assert(not held.get(s.uid, false) or h, "a held site stays held (%s, day %d)" % [s.uid, day])
			held[s.uid] = h
			n += int(h)
		assert(day >= sys.CAMP_DAY or n == 0, "no camps before day %d" % sys.CAMP_DAY)
		if day == 30:
			assert(n * 2 > sites.size(), "most camp landmarks are held on day 30: %d of %d" % [n, sites.size()])
	var listed: Array = sys.camps_near(Vector2.ZERO, 12000.0)
	assert(listed.size() == held.values().filter(func(h): return h).size(), "camps_near lists the held sites")
	assert(listed.all(func(c): return c.kind in sys.CAMP_KINDS), "camps only at prisons, checkpoints, motels, quarries")
	sys.camps.clear()
	Game.day = 10


func _camp() -> void:
	var pos := _spot(heli.position, 300.0)
	var c: Dictionary = sys.add_camp("test:camp", "prison", pos)
	sys._tick() # wakes: the heli is within WAKE_DIST
	_hold_all()
	var units: Array = get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "test:camp")
	var kinds := {}
	for u in units:
		kinds[u.kind] = kinds.get(u.kind, 0) + 1
	for k in ["rifle", "mg", "rpg"]:
		assert(kinds.get(k, 0) == c["garrison"][k], "camp spawns its %s (%s vs %s)" % [k, kinds, c["garrison"]])
	assert(c["known"], "radio names the camp")
	var rifles: int = c["garrison"]["rifle"]
	assert(sys.send_patrol(c), "a patrol leaves for the nearest town")
	_hold_all()
	var patrol: Array = get_tree().get_nodes_in_group("bandits").filter(func(u): return u.role == "patrol")
	assert(patrol.size() >= 1 and c["garrison"]["rifle"] == rifles - patrol.size(), "patrol taken from the garrison")
	var before := Game.base_rifles
	Game.world.morale.pending.clear()
	for u in get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "test:camp" and u.role == "guard"):
		u.hit(99999.0)
	assert(c["cleared"], "killing the garrison clears the camp")
	assert(Game.world.morale.pending.any(func(r): return r[1] == sys.CLEAR_MORALE), "clearing lifts morale")
	var prisoners: Array = main.pois.filter(func(p): return is_instance_valid(p) and p.kind == "survivors" and p.position.distance_to(pos) < 60.0)
	assert(prisoners.size() == 1 and prisoners[0].survivors.size() == c["prisoners"], "the prisoners wait to be picked up")
	_clear_units()
	sys._tick()
	assert(get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "test:camp" and not u.is_queued_for_deletion()).is_empty(), "a cleared camp stays empty")
	heli.position = pos
	heli.landed_changed.emit(true)
	assert(c["looted"] and Game.base_rifles >= before + sys.LOOT["rifles"], "landing takes the stash")
	heli.position = main.BASE_POS
	heli.landed = false


func _technical() -> void:
	_clear_units()
	var road = _road_cell(heli.position)
	assert(road != null, "a road near the start")
	var t := _unit("technical", Vector2(road) * 16.0 + Vector2(8, 8))
	var start: Vector2 = t.position
	var far := 0.0
	for i in 200:
		_step([t], 0.05, 0.05)
		var cell := Vector2i((t.position / 16.0).floor())
		assert(main.chunks.get_cell_atlas_coords(cell).x in ROADS, "technical stays on the road (%s at step %d)" % [cell, i])
		far = maxf(far, t.position.distance_to(start))
	assert(far > 60.0, "technical drives (%.0f px)" % far)
	t.queue_free()
	Game.hp = Game.max_hp


## A road cell near `near` (or a town) on a stretch of at least 24 connected road cells.
func _road_cell(near: Vector2) -> Variant:
	for at in [near] + main.chunks.town_centers:
		for k in 8:
			var road = sys.Technical.road_near(at + Vector2(160, 0).rotated(k * TAU / 8.0) * float(k > 0), 40)
			if road != null and _stretch(road) >= 24:
				return road
	return null


func _stretch(from: Vector2i) -> int:
	var seen := {from: true}
	var todo := [from]
	while not todo.is_empty() and seen.size() < 24:
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if not seen.has(c + d) and main.chunks.get_cell_atlas_coords(c + d).x in ROADS:
				seen[c + d] = true
				todo.append(c + d)
	return seen.size()


func _shoots_heli() -> void:
	_clear_units()
	sources.clear()
	Game.hp = Game.max_hp
	heli.vel = Vector2.ZERO
	var u := _unit("rifle", _spot(heli.position, 150.0))
	assert(u.chance(50.0) > u.chance(250.0), "farther is safer")
	var still: float = u.chance(150.0)
	heli.vel = Vector2(heli.MAX_SPEED, 0)
	assert(u.chance(150.0) < still * 0.6, "speed is safer")
	heli.vel = Vector2.ZERO
	Game.time = 0.95
	assert(u.chance(150.0) < still, "night is safer")
	Game.time = 0.5
	_step([u], 30.0)
	assert(Game.hp < Game.max_hp and "bandit" in sources, "a bandit hits the flying heli (hp %.0f)" % Game.hp)
	if u.cover != Bandit.NONE:
		assert(u.position.distance_to(u.cover) < 8.0 and u._cover_here(), "under fire it took cover")
	u.queue_free()
	Game.hp = Game.max_hp


func _rocket_and_flare() -> void:
	_clear_units()
	sources.clear()
	var u := _unit("rpg", _spot(heli.position, 250.0))
	u.fire_cd = 0.0
	var aimed := false
	for i in 40:
		_step([u], 0.05, 0.05)
		aimed = aimed or u.aim_t > 0.0
	var rockets := get_tree().get_nodes_in_group("rockets")
	assert(aimed and rockets.size() == 1, "the RPG aims, then fires one rocket")
	var r: Node2D = rockets[0]
	r.process_mode = Node.PROCESS_MODE_DISABLED
	_step([r], 3.0, 0.02)
	assert("rocket" in sources and Game.hp <= Game.max_hp - 20.0, "an unopposed rocket hits (hp %.0f)" % Game.hp)
	Game.hp = Game.max_hp
	sources.clear()
	r = u.fire_rocket(heli)
	r.process_mode = Node.PROCESS_MODE_DISABLED
	var fl: Node = load("res://scripts/systems/flares.gd").new()
	fl.process_mode = Node.PROCESS_MODE_DISABLED
	heli.add_child(fl)
	var f: Node2D = fl.drop() # Lv0 flares count for rockets too
	f.position = heli.position + (r.position - heli.position).normalized() * 90.0
	_step([r], 3.0, 0.02)
	assert(Game.hp == Game.max_hp and not "rocket" in sources and r.is_queued_for_deletion(), "a flare pulls the rocket off")
	f.queue_free()
	fl.queue_free()
	u.queue_free()


func _zombies() -> void:
	_clear_units()
	var p := Vector2.ZERO
	var q := Vector2.INF
	for k in 16: # a bandit and a zombie in sight of each other, away from the heli
		p = _spot(heli.position + Vector2(-500, 0).rotated(k * TAU / 16.0), 0.0)
		q = _spot(p, 60.0)
		if q.distance_to(p) < 100.0 and _clear_line(p, q):
			break
	var b := _unit("rifle", p)
	var z: Node2D = main.spawn_enemy("brute", q)
	z.process_mode = Node.PROCESS_MODE_DISABLED
	Game.noise_level = 0.0
	_step([b, z], 15.0)
	assert(not is_instance_valid(z) or z.is_queued_for_deletion() or z.hp < z.max_hp, "the bandit shoots the zombie")
	assert(not is_instance_valid(b) or b.is_queued_for_deletion() or b.hp < b.max_hp, "the zombie goes for the bandit")
	assert(Game.noise_pos.distance_to(p) < 120.0 and Game.noise_level > 0.0, "the gunfight is noise")
	for n in [b, z]:
		if is_instance_valid(n):
			n.queue_free()


## At BANDIT_CAP a camp holds guards back; they come out as slots free up, so killing every guard still clears it.
func _capped_camp() -> void:
	_clear_units()
	var fillers := []
	for i in sys.BANDIT_CAP - 2:
		fillers.append(_unit("rifle", heli.position + Vector2(3000, 0), "patrol"))
	var c: Dictionary = sys.add_camp("test:cap", "prison", _spot(heli.position, 300.0))
	var total: int = c["garrison"].values().reduce(func(a, b): return a + b, 0)
	assert(total > 2, "the test camp needs more than two guards: %s" % c["garrison"])
	sys._tick() # wakes with room for two
	var guards := func() -> Array: return get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "test:cap" and u.role == "guard" and not u.is_queued_for_deletion())
	assert(guards.call().size() == 2, "only two guards fit under the cap (%d)" % guards.call().size())
	for u in fillers:
		u.remove_from_group("bandits")
		u.remove_from_group("enemies")
		u.queue_free()
	var rounds := 0
	while not c["cleared"] and rounds < 20: # kill what is out, let the camp send the rest
		rounds += 1
		sys._tick()
		_hold_all()
		for u in guards.call():
			u.hit(99999.0)
		await frame # the dead leave the group, the camp has room again
	assert(c["cleared"], "killing every guard as they come out clears a capped camp (%s left)" % c["garrison"])
	_clear_units()


func _raids() -> void:
	_clear_units()
	var base: Vector2 = main.base.global_position
	sys.add_camp("test:raid", "motel", base + Vector2(1500, 0))
	Game.first_assault_day = 3
	sys.last_base_raid = -100
	for d in range(4, 30):
		assert(sys._zombie_night(d) == Assault.night_taken(d), "bandits ask assault.gd which nights are taken (day %d)" % d)
	assert(not sys.plan_base_raid(12, true), "no base raid on a zombie assault night (day 12)")
	assert(sys.plan_base_raid(13, true) and sys.base_raid_day == 13, "base raid planned for day 13")
	assert(not sys.plan_base_raid(11, true), "and not before day %d" % sys.BASE_RAID_DAY)
	heli.position = base + Vector2(-1800, 0) # out of the raiders' range: they go for the base
	Game.day = 13
	Game.time = sys.BASE_RAID_AT + 0.01
	sys._tick()
	_hold_all()
	var raiders: Array = get_tree().get_nodes_in_group("bandits").filter(func(u): return u.role == "base")
	var party := SpawnTable.bandits(SpawnTable.RAID_ROWS, 13)
	assert(raiders.size() == party["rifle"] + party["rpg"] and sys.last_base_raid == 13 and sys.base_raid_day == -1, "the raid party comes (%d)" % raiders.size())
	sys.last_base_raid = 13
	assert(not sys.plan_base_raid(14, true), "base raids keep %d days apart" % sys.BASE_RAID_GAP)
	var hp0 := 5000.0
	Game.base_hp = hp0
	for u in raiders: # at their firing spots (the walk there depends on the seed's terrain)
		u.position = u.goal
	_step(raiders, 1.0)
	assert(raiders.any(func(u): return u.target == main.base), "raiders at the fence shoot the base")
	main.base._check_alert()
	assert(main.base.threat and main.base.defenders.get_child_count() == Game.workers["militia"], "bandits at the fence put the militia on their posts")
	_step(raiders, sys.RAID_SECONDS * 1.3) # thinks come every 0.4-0.6 s, raid_t counts 0.5 each
	assert(Game.base_hp < hp0, "raiders shoot the base from beyond the fence (%.0f)" % Game.base_hp)
	assert(raiders.all(func(u): return not is_instance_valid(u) or u.role == "home"), "%d s after setting out the raiders leave" % sys.RAID_SECONDS)
	var rc: Dictionary = sys.camps[raiders[0].camp_uid]
	var want := SpawnTable.bandits(SpawnTable.CAMP_ROWS, Game.day)
	rc["garrison"] = want.duplicate()
	for u in raiders.filter(func(u): return is_instance_valid(u)):
		sys.unit_gone(u)
	assert(rc["garrison"] == want, "returning raiders never push a garrison past CAMP_ROWS: %s vs %s" % [rc["garrison"], want])
	Game.base_hp = Game.max_base_hp
	_clear_units()
	# a settlement raid: off-screen people go missing, with the heli close the raiders really come
	var c: Dictionary = sys.camps["test:raid"]
	var town: Node2D = main.spawn_poi("survivors", _spot(c["pos"] + Vector2(-400, 0), 0.0), RandomNumberGenerator.new(), 5)
	sys.town_raid = {}
	for uid in sys.camps.keys():
		if uid != "test:raid":
			sys.camps.erase(uid)
	assert(sys.plan_town_raid(13, true) and sys.town_raid["poi"] == town.uid, "a town raid is announced")
	var prisoners: int = c["prisoners"]
	Game.time = sys.TOWN_RAID_AT + 0.01
	sys._tick()
	assert(town.survivors.size() < 5 and c["prisoners"] == prisoners + 5 - town.survivors.size(), "off-screen the bandits take people")
	assert(sys.plan_town_raid(13, true), "planned again")
	heli.position = town.position + Vector2(200, 0)
	sys._tick()
	_hold_all()
	var party2: Array = get_tree().get_nodes_in_group("bandits").filter(func(u): return u.role == "raid" and u.poi_uid == town.uid)
	assert(party2.size() >= sys.RAID_PARTY.x, "with the heli close the raiders come")
	var left: int = town.survivors.size()
	heli.position = town.position + Vector2(2000, 0) # out of range: they walk in instead of shooting
	_step(party2, 50.0)
	assert(town.survivors.size() < left, "raiders abduct from the settlement (%d -> %d)" % [left, town.survivors.size()])
	_clear_units()
	# outposts and allied villages (outposts.gd) near a camp are raided at dusk, never on an assault day
	var op: Node2D = main.outposts
	var o := {"id": "o9", "site": "radio_mast", "pos": c["pos"] + Vector2(-500, 0), "fuel": 0.0, "ammo": 0, "hp": op.OUTPOST_HP, "day": 1}
	op.list.append(o)
	var hits := []
	op.raided.connect(func(id, _res, source): hits.append([id, source]))
	sys.outpost_raid = {}
	assert(not sys.plan_outpost_raid(12, true), "no outpost raid on a zombie assault day")
	assert(sys.plan_outpost_raid(13, true) and sys.outpost_raid["id"] == "o9", "an outpost raid is announced")
	Game.time = sys.TOWN_RAID_AT + 0.01
	sys._tick()
	var strength: int = SpawnTable.bandits(SpawnTable.RAID_ROWS, 13)["rifle"]
	assert(hits == [["o9", "bandits"]] and is_equal_approx(o["hp"], op.OUTPOST_HP - strength * op.HP_PER_POINT) and sys.outpost_raid.is_empty(), "the unmanned outpost takes the raid: %s hull %s" % [hits, o["hp"]])
	op.list.erase(o)
	heli.position = main.BASE_POS


func _save_load() -> void:
	_unit("rifle", _spot(heli.position, 200.0), "raid", "test:raid").poi_uid = "none"
	_hold_all()
	var d: Dictionary = bytes_to_var(var_to_bytes(sys.save_state()))
	var roaming: int = d["units"].size()
	assert(roaming > 0, "roaming raiders are saved")
	var camps: Dictionary = sys.camps.duplicate(true)
	_clear_units()
	sys.camps = {}
	sys.load_state(d)
	var back: Array = get_tree().get_nodes_in_group("bandits").filter(func(u): return not u.is_queued_for_deletion())
	assert(back.size() == roaming, "raiders come back (%d of %d)" % [back.size(), roaming])
	assert(sys.camps.size() == camps.size() and sys.camps["test:raid"]["prisoners"] == camps["test:raid"]["prisoners"], "camps come back")
	_clear_units()


## The real thing for a few hundred frames: camps near a day-20 heli wake and fight without script errors.
func _live() -> void:
	Game.day = 20
	sys.camps.clear()
	sys.set_process(true)
	heli.position = main.BASE_POS
	var pos := _spot(heli.position, 400.0)
	sys.add_camp("test:live", "checkpoint", pos)
	for z in 4:
		main.spawn_enemy("shambler", _spot(pos, 120.0))
	var t0 := Time.get_ticks_msec()
	for i in 300:
		await frame
	Game.hp = Game.max_hp
	assert(get_tree().get_nodes_in_group("bandits").size() > 0, "the live camp woke up")
	print("bandits live: %d frames in %d ms" % [300, Time.get_ticks_msec() - t0])
	# stress: the bandit cap and a big horde fighting next to the heli
	for i in sys.BANDIT_CAP if OS.get_environment("STRESS_BASELINE") == "" else 0:
		sys.spawn_unit(["rifle", "rifle", "rpg", "mg"][i % 4], _spot(pos, 30.0 + 4.0 * i), "guard", pos, "")
	for i in 80:
		main.spawn_enemy("shambler", _spot(pos, 150.0 + 2.0 * i))
	for i in 10:
		await frame
	var worst := 0
	t0 = Time.get_ticks_usec()
	for i in 120:
		var f0 := Time.get_ticks_usec()
		await frame
		worst = maxi(worst, Time.get_ticks_usec() - f0)
	Game.hp = Game.max_hp
	print("bandits stress: %d bandits, %d enemies, %.1f ms/frame avg, %.1f ms worst" % [get_tree().get_nodes_in_group("bandits").size(),
		get_tree().get_nodes_in_group("enemies").size(), (Time.get_ticks_usec() - t0) / 120000.0, worst / 1000.0])
