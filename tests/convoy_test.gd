extends Node
## Headless convoy test (docs/ROADMAP.md P16). main.gd adds this node when env SMOKE=convoy (base founded):
##   SMOKE=convoy godot --headless --path . --quit-after 30000
## Motor pool and truck costs, dispatch refusals, a road-only path (cost measured), the trip out, looting, the way home
## and the unloading, the crew off the base but still scored, an ambush that stops the truck (abstract and with real
## bandits near the heli), a save round trip mid-trip, a destroyed truck.

const Chunks := preload("res://scripts/chunk_manager.gd")


func _ready() -> void:
	call_deferred("_run")


func _drive(cv: Node2D, c: Dictionary, until: Callable, max_steps := 20000) -> int:
	for i in max_steps:
		if until.call():
			return i
		cv._step(c, 0.25, true)
	return -1


func _run() -> void:
	var main: Node2D = Game.world
	var cv: Node2D = main.convoys
	var heli: Node2D = Game.heli
	var ch: TileMapLayer = main.chunks
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = true # the test drives the convoy itself
	Game.day = 6 # bandits are about (CAMP_DAY)
	# --- crew: a driver, two militia, two more
	Game.people.clear()
	Game.rescued = 6
	Game.people[0]["skill"] = "driver"
	Game.people[0]["skill_lv"] = 2
	for p in Game.people.slice(1):
		p["skill"] = "farmer"
	Game.workers["militia"] = 3 # the driver (best level) takes one of the seats
	Game.assign_jobs()
	var driver: Dictionary = Game.people[0]
	assert(Game.people.filter(func(p): return p["job"] == "militia").size() == 3, "three militia, the driver among them")
	# --- motor pool and truck
	assert("Motor Pool" in cv.build_truck(), "no truck without a Motor Pool")
	assert(Game.BUILDINGS.has("motor_pool") and Game.BUILDINGS["motor_pool"][1] == 80, "Motor Pool costs 80 scrap")
	Game.buildings.append({"kind": "motor_pool", "cell": Vector2i(-99, -99), "built": true, "progress": 0.0})
	Game.salvage = {"metal": 5.0, "parts": 0.0, "electronics": 0.0}
	assert("metal" in cv.build_truck() and cv.trucks == 0, "a truck needs salvage")
	Game.salvage = {"metal": 100.0, "parts": 100.0, "electronics": 0.0}
	assert(cv.build_truck() == "" and cv.trucks == 1 and Game.salvage["metal"] == 80.0 and Game.salvage["parts"] == 85.0, "truck built from salvage")
	# --- destinations: seen sites (their chunk loaded); the nearest with a road
	assert(cv.send("nowhere", driver["id"], 0) == "Pick a destination.", "unknown destination refused")
	var sites: Array = ch.sites_near(main.BASE_POS, 4000.0).filter(func(s): return s.pos.distance_to(main.BASE_POS) > cv.MIN_DIST)
	assert(not sites.is_empty(), "sites around the base")
	var dest := {}
	var path := PackedVector2Array()
	var worst := 0.0
	for s in sites.slice(0, 4):
		ch._ensure(Vector2i((s.pos / (Chunks.CHUNK * Chunks.TILE)).floor())) # the heli has seen it
		var t0 := Time.get_ticks_usec()
		var p: PackedVector2Array = cv.road_path(main.base.position, s.pos)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		if p.size() >= 2 and dest.is_empty():
			dest = s
			path = p
	assert(not dest.is_empty(), "a road from the base to one of %d sites" % sites.size())
	var t1 := Time.get_ticks_usec()
	assert(cv.road_path(main.base.position, dest.pos) == path, "the same path again")
	var cached := (Time.get_ticks_usec() - t1) / 1000.0
	print("convoy road path: %d cells to %s, worst build %.1f ms, cached %.3f ms" % [path.size(), dest.kind, worst, cached])
	assert(cached < 1.0, "cached path is free")
	var far: Array = ch.sites_near(main.BASE_POS, cv.RANGE).filter(func(s): return s.pos.distance_to(main.BASE_POS) > 6000.0)
	for s in far.slice(0, 4): # far trips into unloaded land: the generator's roads on the way are computed once
		var t2 := Time.get_ticks_usec()
		var fp: PackedVector2Array = cv.road_path(main.base.position, s.pos)
		print("convoy far path to a %s %d m away: %d cells, %.1f ms" % [s.kind, s.pos.distance_to(main.BASE_POS) / 10.0, fp.size(), (Time.get_ticks_usec() - t2) / 1000.0])
	assert(dest.uid in cv.destinations().map(func(d): return d["uid"]), "the seen site is a destination")
	# road only: every cell on the path is a road tile, each step to a neighbouring cell
	for i in path.size():
		var cell := Vector2i((path[i] / 16.0).floor())
		assert(ch._ft(cell) in Chunks.ROADS or ch.edits.has(cell), "path cell %s is road, not %d" % [cell, ch._ft(cell)])
		if i > 0:
			var prev := Vector2i((path[i - 1] / 16.0).floor())
			var ports: Array = ch._layout(ch._macro(cell)).ports
			assert(path[i].distance_to(path[i - 1]) < 23.0 or (cell in ports and prev in ports), "path steps cell by cell (or across a town between its road ends)")
	assert(path[0].distance_to(main.base.position) <= cv.START_REACH and path[path.size() - 1].distance_to(dest.pos) <= cv.DEST_REACH, "starts near the base, ends near the site")
	# --- refusals
	assert("driver" in cv.send(dest.uid, Game.people[1]["id"], 0), "a farmer cannot drive")
	assert("militia" in cv.send(dest.uid, driver["id"], 3), "only two militia")
	Game.base_rifles = 1.0
	var why: String = cv.send(dest.uid, driver["id"], 2)
	assert("rifles" in why, "a rifle per escort: %s" % why)
	Game.base_rifles = 4.0
	# --- the trip: out, loot, home
	var saved0 := Game.saved_count()
	var rescued0 := Game.rescued
	heli.position = main.base.position + Vector2(-5000, -5000) # far away: the convoy runs abstractly
	assert(cv.send(dest.uid, driver["id"], 2) == "", "convoy sent")
	var c: Dictionary = cv.list[0]
	assert(cv.trucks == 0 and Game.base_rifles == 2.0, "truck and two rifles out")
	assert(cv.crew(c).size() == 3 and Game.rescued == rescued0 - 3 and Game.saved_count() == saved0, "crew left the base but still counts for the score")
	assert(cv.escorts(c).all(func(p): return p["job"] == "" and p != driver), "escorts are off their jobs")
	c["amb"] = {"out": -1.0, "back": -1.0}
	var steps := _drive(cv, c, func(): return c["leg"] == "loot")
	assert(steps > 0 and is_equal_approx(c["d"], cv.length(c)), "arrived at the site after %d steps" % steps)
	assert(c["hp"] < cv.HULL and c["hp"] > 0.0, "the road wore the hull a bit: %.1f" % c["hp"])
	assert(cv._nodes.is_empty(), "no truck node far from the heli")
	_drive(cv, c, func(): return c["leg"] == "back")
	assert(not c["cargo"].is_empty(), "looted: %s" % c["cargo"])
	var cargo: Dictionary = c["cargo"].duplicate()
	var food0 := Game.base_food
	var metal0: float = Game.salvage["metal"]
	assert(_drive(cv, c, func(): return cv.list.is_empty()) > 0, "came home")
	assert(cv.trucks == 1 and Game.base_rifles == 4.0 and Game.rescued == rescued0, "truck, rifles and crew back")
	assert(Game.base_food >= food0 + cargo.get("food", 0.0) - 0.01 and Game.salvage["metal"] >= metal0 + cargo.get("metal", 0.0) - 0.01, "cargo unloaded")
	assert(cv.trips.get(dest.uid, 0) == 1, "trip counted for depletion")
	# --- ambush: stops the truck until the bandits are dead
	Game.assign_jobs()
	assert(cv.send(dest.uid, driver["id"], 0) == "", "second convoy, no escort")
	c = cv.list[0]
	var spot := minf(300.0, cv.length(c) * 0.5)
	c["amb"] = {"out": spot, "back": -1.0}
	_drive(cv, c, func(): return c["foes"] > 0, 4000)
	assert(c["foes"] >= cv.AMBUSH_SIZE.x and is_equal_approx(c["d"], spot), "ambushed at the spot")
	var at: float = c["d"]
	var hp0: float = c["hp"]
	for i in 40:
		cv._step(c, 0.25, true)
	assert(c["d"] == at and c["foes"] > 0 and c["hp"] < hp0, "the ambush stops the truck and hurts it (no escort to fight)")
	# save round trip mid-trip
	var snap: Dictionary = bytes_to_var(var_to_bytes(cv.save_state()))
	cv.load_state(snap)
	c = cv.list[0]
	assert(c["d"] == at and c["foes"] > 0 and c["path"].size() == cv.road_path(main.base.position, dest.pos).size() and cv.crew(c).size() == 1, "convoy round-trips mid-ambush")
	# the heli arrives: the ambushers become real bandits
	heli.position = cv.pos_of(c) + Vector2(80, 0)
	cv._step(c, 0.25, true)
	assert(cv._nodes.has(c["id"]) and cv._foes.get(c["id"], []).size() == c["foes"], "truck and %d ambushers in view" % c["foes"])
	for u in cv._foes[c["id"]]:
		u.hit(99999.0)
	cv._step(c, 0.25, true)
	assert(c["foes"] == 0, "ambush beaten off")
	cv._step(c, 0.25, true)
	assert(c["d"] > at, "and the truck drives on")
	# --- destroyed: cargo, truck and crew lost or hurt
	var n0 := Game.people.size()
	c["hp"] = 0.01
	c["cargo"] = {"food": 99.0}
	heli.position = main.base.position + Vector2(-5000, -5000)
	cv._step(c, 0.25, true)
	assert(cv.list.is_empty() and cv.trucks == 0, "truck lost")
	assert(Game.people.size() < n0 or driver["injured"], "the driver died or walks home injured")
	assert(Game.people.all(func(p): return p.get("post", "") == ""), "nobody left on the road")
	# --- the CONVOY tab
	main.base.ui.open()
	main.base.ui.show_tab("CONVOY")
	cv.refresh_tab()
	assert(cv._ui["dest"].item_count > 0 and "trucks at home 0" in cv._ui["pool"].text, "CONVOY tab lists destinations")
	main.base.ui.close()
	# --- Warlords: camps and ambushes from day 1; the camp share's day term never goes negative
	var mods: Node = main.modifiers
	var bd: Node = main.bandits
	assert(bd.first_camp_day() == bd.CAMP_DAY, "camps from CAMP_DAY")
	mods.active = ["warlords"]
	assert(bd.first_camp_day() == 1, "Warlords: camps from day 1")
	var day0 := Game.day
	Game.day = 1
	var rolls := []
	for i in 200:
		rolls.append(cv._roll_ambush(c, [500.0]))
	assert(rolls.any(func(r): return r >= 0.0), "Warlords: ambushes on day 1")
	mods.active = []
	assert(cv._roll_ambush(c, [500.0]) < 0.0, "no ambush on day 1 without Warlords")
	Game.day = day0
	# --- Scarcity: convoy loot -30 %
	var lc := {"id": "cx", "dest": {"uid": "scarcity-test", "kind": "town", "name": "x", "pos": Vector2.ZERO}, "cargo": {}, "leg": "loot"}
	mods.active = ["scarcity"]
	cv._load(lc)
	mods.active = []
	var food: float = lc["cargo"]["food"]
	assert(food >= roundf(cv.LOOT["town"]["food"] * 0.7 * 0.8) and food <= roundf(cv.LOOT["town"]["food"] * 0.7 * 1.2), "Scarcity: %d food" % food)
	# --- no convoy leaves during the evacuation
	cv.trucks = 1
	main.evac.phase = "countdown"
	assert("evacuation" in cv.send(dest.uid, driver["id"], 0), "SEND refused during the countdown")
	main.evac.phase = ""
	cv.trucks = 0
	# old saves: no "convoys" system, defaults stay
	cv.load_state({"list": [], "trucks": 0, "seq": 0, "trips": {}})
	assert(cv.list.is_empty(), "empty state loads")
	print("convoy_test OK")
	get_tree().quit()
