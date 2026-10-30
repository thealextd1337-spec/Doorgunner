extends Node
## Headless outposts + allied villages test (docs/ROADMAP.md P14). main.gd adds this node when env SMOKE=outposts (base founded):
##   SMOKE=outposts godot --headless --path . --quit-after 30000
## Crew loading, founding (cost, limit, site), refuelling and saving on the pad, deposits, reinforcement, a held and a lost raid,
## a gas station's daily fuel, the village protect / food pickup / neglect / raid, the P11 / P13 API, save round trip.

const People := preload("res://scripts/people.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var op: Node2D = main.outposts
	var heli: Node2D = Game.heli
	var frame := get_tree().process_frame
	await frame
	await frame
	get_tree().paused = true # the test drives the clock and the keys
	assert(op != null and op.list.is_empty() and op.allies.is_empty(), "outposts node, nothing founded")
	# --- landmarks to hold
	var sites: Array = main.chunks.sites_near(main.BASE_POS, 14000.0).filter(func(s): return s["kind"] in op.SITE_KINDS and s["pos"].distance_to(main.BASE_POS) > op.MIN_FROM_BASE)
	assert(sites.size() >= 3, "gas stations, checkpoints or radio masts around: %d" % sites.size())
	var gas: Array = sites.filter(func(s): return s["kind"] == "gas_station")
	var first: Dictionary = gas[0] if not gas.is_empty() else sites[0]
	var second: Dictionary = sites.filter(func(s): return s["pos"].distance_to(first["pos"]) > op.MIN_APART)[0]
	# --- crew: loaded on the base pad, they are passengers and are not delivered by landing at the base
	Game.passengers = 4
	Game.deliver()
	Game.workers["militia"] = 2
	Game.assign_jobs()
	var militia: Array = Game.people.filter(func(p): return p["job"] == "militia")
	assert(militia.size() == 2 and Game.rescued == 4, "two militia at the base")
	heli.position = main.BASE_POS
	heli.landed = true
	Game.scrap = 100
	assert(op.found_problem() != "" and not op.found(), "no site at the base pad")
	assert(op.load_crew(), "crew loaded")
	assert(Game.passengers == 2 and Game.rescued == 2 and op.crew().size() == 2, "the crew sits in the cabin: %d aboard, %d at the base" % [Game.passengers, Game.rescued])
	assert(op.crew().all(func(p): return p in militia), "militia go first")
	assert(Game.deliver() == 0 and Game.passengers == 2, "landing at the base leaves the crew aboard")
	assert(op.load_crew() == true and op.crew().is_empty() and Game.rescued == 4, "O again puts them back")
	assert(op.load_crew() and op.crew().size() == 2, "loaded again")
	# --- founding: cost, site, limits
	heli.position = main.BASE_POS + Vector2(80, 0)
	assert("no gas station" in op.found_problem(), "open ground without a landmark: %s" % op.found_problem())
	heli.position = first["pos"] + Vector2(30, 0)
	Game.scrap = 10
	assert("40 scrap" in op.found_problem() and not op.found(), "too poor")
	Game.scrap = 100
	assert(op.found_problem() == "", "can found: %s" % op.found_problem())
	assert(op.found() and op.list.size() == 1, "outpost founded")
	assert(Game.scrap == 60, "40 scrap paid")
	var o: Dictionary = op.list[0]
	assert(o["site"] == first["kind"] and op.garrison(o["id"]).size() == 2 and op.crew().is_empty(), "the crew became the garrison")
	assert(Game.passengers == 0 and Game.rescued == 2, "garrison is neither passengers nor population")
	assert(Game.saved_count() == 4, "but they still count as saved for the score: %d" % Game.saved_count())
	assert(Game.injured == 0 and Game.assigned() <= 2, "workers fit the smaller base: %d" % Game.assigned())
	Game.assign_jobs()
	assert(op.garrison(o["id"]).all(func(p): return p["job"] == "" and p["post"] == o["id"]), "garrison off the job list")
	assert(Game.deliver() == 0, "nothing to deliver")
	# limit: one outpost without a watchtower
	heli.position = second["pos"]
	Game.passengers = 2
	for p in Game.people.filter(func(p): return p["aboard"]):
		p["post"] = op.LOADED
	assert("can hold 1" in op.found_problem(), "limit of one: %s" % op.found_problem())
	Game.buildings.append({"kind": "watchtower", "cell": Vector2i(1, 1), "built": true, "progress": 0.0})
	assert(op.max_outposts() == 2 and op.found_problem() == "", "a watchtower allows a second: %s" % op.found_problem())
	assert(op.found() and op.list.size() == 2 and op.garrison("o2").size() == 2, "second outpost")
	Game.buildings.clear()
	op.list.pop_back() # keep one for the rest, give the people back
	for p in op.garrison("o2"):
		p["post"] = ""
	# --- refuel, rearm, save on landing
	heli.position = o["pos"]
	heli.landed = true
	Game.fuel = 10.0
	Game.ammo = 20
	o["fuel"] = 40.0
	o["ammo"] = 60
	op._on_landed(true)
	assert(is_equal_approx(Game.fuel, 50.0) and Game.ammo == 80 and is_equal_approx(o["fuel"], 0.0) and o["ammo"] == 0, "topped up from the stock: fuel %s ammo %d" % [Game.fuel, Game.ammo])
	assert(FileAccess.file_exists(Save.path()), "landing on an outpost saves the run")
	# gas stations deliver fuel, checkpoints ammo
	o["site"] = "gas_station"
	Game.day += 1
	Game.day_changed.emit(Game.day)
	assert(is_equal_approx(o["fuel"], op.SITE_YIELD["gas_station"]["fuel"]), "gas station delivered fuel: %s" % o["fuel"])
	o["site"] = "checkpoint"
	Game.day += 1
	Game.day_changed.emit(Game.day)
	assert(o["ammo"] == op.SITE_YIELD["checkpoint"]["ammo"], "checkpoint delivered ammo")
	# deposit: spare fuel and ammo go into the stock, the reserve stays
	Game.fuel = Game.max_fuel
	Game.ammo = Game.max_ammo
	var f0: float = o["fuel"]
	assert(op.press_o() and o["fuel"] > f0 and Game.fuel >= Game.max_fuel * op.SPARE_SHARE - 0.01, "deposited, reserve kept")
	# --- raids: the garrison holds a small attack, loses to a big one
	o["ammo"] = 100
	var r: Dictionary = op.raid(o["id"], 3.0, "zombies")
	assert(r["held"] and not r["fell"] and o["hp"] == op.OUTPOST_HP, "small raid held: %s" % r)
	assert(o["ammo"] == 100 - op.RAID_AMMO, "the raid used crate ammo")
	for p in op.garrison(o["id"]):
		p["injured"] = false
		p["skill"] = "" # soldiers would add defence and make the raid sizes below random
	assert(op.defence(o) >= 4.0 + op.HELI_HELP, "two healthy men plus the heli: %s" % op.defence(o))
	Game.day += 1
	Game.day_changed.emit(Game.day)
	assert(op.targets().size() == 1 and op.targets()[0]["kind"] == "outpost" and op.targets()[0]["pos"] == o["pos"], "targets lists the outpost")
	heli.position = Vector2(-9999, 9999) # far away: no door gun help
	r = op.raid(o["id"], 7.0)
	assert(not r["held"] and o["hp"] < op.OUTPOST_HP and r["hurt"] >= 1, "a big raid hurts: %s hull %s" % [r, o["hp"]])
	var before: int = Game.people.size()
	var lost := []
	Game.person_lost.connect(func(p, died): if died: lost.append(p))
	r = op.raid(o["id"], 100.0)
	assert(r["fell"] and op.list.is_empty() and op.garrison(o["id"]).is_empty(), "the outpost fell")
	assert(Game.people.size() == before - lost.size() and lost.size() == r["died"], "dead are gone, the rest walked home: %d lost" % lost.size())
	assert(Game.people.all(func(p): return p["post"] == "" or p["aboard"] == false), "nobody stuck on a dead post")
	assert(op.raid("o99", 5.0).is_empty(), "unknown target")
	# night raids roll without error and keep the garrison consistent
	heli.position = first["pos"] + Vector2(30, 0)
	heli.landed = true
	Game.passengers = 0
	for p in Game.people:
		p["post"] = ""
		p["aboard"] = false
	Game.people.filter(func(p): return true).slice(0, 2).map(func(p): p["aboard"] = true; p["post"] = op.LOADED)
	Game.scrap = 100
	assert(op.found(), "founded again")
	o = op.list[0]
	op.night_raids(true)
	assert(op.list.size() <= 1, "night raid resolved")
	# --- villages: spawn a settlement, clear it, protect it
	if op.list.is_empty():
		op.list.append(o)
	var pos: Vector2 = main.BASE_POS + Vector2(-1500, 400)
	var poi: Node2D = main.spawn_poi("survivors", pos, RandomNumberGenerator.new(), 4)
	await frame
	heli.position = pos + Vector2(20, 0)
	heli.landed = true
	var foe: Node2D = main.spawn_enemy("shambler", pos + Vector2(60, 0))
	assert(not op.protect() and op.allies.is_empty(), "hostiles near: no protecting")
	foe.queue_free()
	await frame
	await frame
	Game.day = 10
	assert(op.protect() and op.allies.has(poi.uid) and poi.done and poi.survivors.size() == 4, "village protected, people stay")
	assert(op.villages().size() == 1 and op.villages()[0]["pop"] == 4 and op.village_near(pos, 80.0)["id"] == poi.uid, "villages() API")
	assert(op.targets().any(func(t): return t["kind"] == "village" and t["id"] == poi.uid), "targets lists the village")
	var id: String = poi.uid
	# food and water every VILLAGE_DAYS days, collected by landing, delivered on the base pad
	Game.day += 1
	Game.day_changed.emit(Game.day)
	assert(is_zero_approx(op.allies[id]["stock"]["food"]), "nothing the first day")
	Game.day += 1
	Game.day_changed.emit(Game.day)
	assert(is_equal_approx(op.allies[id]["stock"]["food"], 4 * op.FOOD_PER_PERSON), "village left food: %s" % op.allies[id]["stock"])
	op._on_landed(true)
	assert(is_equal_approx(op.cargo["food"], 12.0) and is_equal_approx(op.cargo["water"], 8.0), "picked up: %s" % op.cargo)
	var food0: float = Game.base_food
	var water0: float = Game.base_water
	heli.position = main.BASE_POS
	op._on_landed(true)
	assert(is_equal_approx(Game.base_food, food0 + 12.0) and is_equal_approx(Game.base_water, water0 + 8.0) and op.cargo["food"] == 0.0, "the base got the food")
	# delivery hook (P13) resets the neglect clock
	var got := []
	op.village_delivered.connect(func(vid, item, amount): got.append([vid, item, amount]))
	Game.day += 5
	assert(op.deliver(id, "medicine", 2.0) and got == [[id, "medicine", 2.0]] and op.allies[id]["last_visit"] == Game.day and not op.deliver("nope", "medicine", 1.0), "deliver hook")
	# a raid that the village cannot hold costs people, a big one ends it; garrisons nearby help
	op.list[0]["pos"] = pos + Vector2(300, 0)
	assert(op.village_defence(op.allies[id]) >= 4 * op.VILLAGE_DEF_PER_PERSON + 0.0, "village defence")
	op.list.clear()
	r = op.raid(id, 5.0)
	assert(not r["held"] and r["died"] >= 1 and poi.survivors.size() < 4, "raid cost villagers: %s" % r)
	# neglect: unvisited villages fall by chance
	var fell := []
	op.fell.connect(func(i, k): fell.append([i, k]))
	main.missions.open.clear()
	Game.base_medicine = 5.0
	for i in 80:
		Game.day += 1
		Game.day_changed.emit(Game.day)
		if op.allies.is_empty():
			break
	assert(op.allies.is_empty() and fell == [[id, "village"]], "an unvisited village falls: %s" % [fell])
	assert(poi.survivors.is_empty(), "its people are gone")
	assert(main.missions.open.any(func(m): return m["type"] == "medicine" and m["state"]["uid"] == id), "a neglected village radioed a medicine run")
	main.missions.open.clear()
	# --- save round trip
	op.list.clear()
	Game.passengers = 0
	Game.scrap = 100
	Game.people.clear()
	Game.passengers = 2
	for p in Game.people:
		p["post"] = op.LOADED
	heli.position = first["pos"]
	heli.landed = true
	assert(op.found(), "an outpost to save")
	op.cargo = {"food": 3.0, "water": 1.0}
	op.list[0]["fuel"] = 33.0
	var snap: Dictionary = op.save_state().duplicate(true)
	var people_snap: Array = Game.people.duplicate(true)
	op.list.clear()
	op.cargo = {"food": 0.0, "water": 0.0}
	op.load_state(snap)
	assert(op.list.size() == 1 and op.list[0]["fuel"] == 33.0 and op.cargo["food"] == 3.0 and op._nodes.size() == 1, "outposts round-trip")
	var bytes := var_to_bytes({"o": snap, "p": people_snap})
	var back: Dictionary = bytes_to_var(bytes)
	assert(back["o"]["list"][0]["pos"] == op.list[0]["pos"] and back["p"][0]["post"] == op.list[0]["id"], "built-in types only: Vector2 and the post survive var_to_bytes")
	assert(op.garrison(op.list[0]["id"]).size() == 2, "the garrison belongs to the outpost after loading")
	# the run's score counts the garrisons: meta (and Online.end_run) get saved_count, not the base population
	var meta0: Dictionary = Game.meta.duplicate(true)
	var total0: int = Game.meta["total_rescued"]
	var saved: int = Game.saved_count()
	assert(saved > Game.rescued, "garrison makes the difference: %d saved, %d at the base" % [saved, Game.rescued])
	Game.end_run("test over") # also deletes the autosave
	assert(Game.meta["total_rescued"] == total0 + saved and not FileAccess.file_exists(Save.path()), "meta got %d" % (Game.meta["total_rescued"] - total0))
	Game.meta = meta0 # the smoke profile's best day would unlock slots in other tests
	Game._save_meta()
	print("outposts_test OK")
	get_tree().quit()
