extends Node
## Headless test of P15 (docs/ROADMAP.md): heli types, wrecks, the sling hook, the HANGAR repair, switching helis, run modifiers.
##   SMOKE=wreck godot --headless --path . --quit-after 30000
## Types set seats / hardpoints / speed / armour; a wreck rolls the same every time; G hooks it after 4 s of steady hovering;
## with the load top speed halves, fuel burns double, no landing, the load swings behind and zombies chew on it; G drops it
## outside (it stays) and inside the fence (repair project); the repair pays salvage and key parts and takes work days of
## mechanics (engineers x2); the repaired heli is switched in at the pad and items and wear stay with each heli; the type
## unlocks as a start heli; modifiers apply and multiply; everything round-trips through run.sav, a save without P15 loads.

const HeliTypes := preload("res://scripts/heli_types.gd")
const Wrecks := preload("res://scripts/wrecks.gd")
const Modifiers := preload("res://scripts/modifiers.gd")
var w: Node2D
var heli: Node2D
var main: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	var frame := get_tree().process_frame
	await frame
	await frame
	get_tree().paused = true # the test drives the clock
	w = main.wrecks
	heli = Game.heli
	Game.passengers = 0
	var meta0: Dictionary = Game.meta.duplicate() # the test unlocks things; the smoke profile gets its meta back at the end
	Game.meta["start_helis"] = ""
	_types()
	_twin()
	var uid := _sling()
	_repair(uid)
	_switch(uid)
	_modifiers()
	_save()
	Game.meta = meta0
	Game._save_meta()
	print("WRECK OK")
	get_tree().quit(0)


func _types() -> void:
	assert(w.type_id() == "huey", "a new run flies the Huey")
	var seats0: int = Game.seats - 4 # meta bonus seats of the test profile
	var hp0: int = Game.slots["hardpoint"] - 1
	var huey_armor: float = Game.stats["armor"]
	var huey_speed := _top_speed()
	for id in HeliTypes.TYPES:
		var t: Dictionary = HeliTypes.TYPES[id]
		w.wrecks["start"]["type"] = id
		Game.recompute()
		assert(Game.seats - seats0 == t["seats"] and Game.slots["hardpoint"] - hp0 == t["hardpoints"], "%s: %d seats, %d hardpoints (got %d, %d)" % [id, t["seats"], t["hardpoints"], Game.seats - seats0, Game.slots["hardpoint"] - hp0])
		assert(is_equal_approx(Game.stats["armor"], huey_armor * t["armor"]), "%s armour x%s" % [id, t["armor"]])
		var v := _top_speed()
		assert(absf(v / huey_speed - t["speed"]) < 0.02, "%s top speed x%s (got %s)" % [id, t["speed"], v / huey_speed])
	w.wrecks["start"]["type"] = "huey"
	Game.recompute()
	assert(HeliTypes.get_type("future_heli")["name"] == "Huey", "an unknown type flies as a Huey")
	print("WRECK types OK")


## Black Hawk: both mounted guns fire at once.
func _twin() -> void:
	var shots_huey := _volley()
	w.wrecks["start"]["type"] = "black_hawk"
	Game.recompute()
	Game.add_weapon("minigun")
	assert(Game.heli_weapons.size() == 2, "the Black Hawk mounts two guns")
	var shots_hawk := _volley()
	assert(shots_hawk > shots_huey, "both door guns fire: %d vs %d bullets" % [shots_hawk, shots_huey])
	Game.heli_weapons.assign(["mg"])
	Game.heli_items = {"mg": 1}
	Game.weapon = "mg"
	w.wrecks["start"]["type"] = "huey"
	Game.recompute()
	print("WRECK twin guns OK")


func _volley() -> int:
	for b in main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/bullet.gd")):
		b.free()
	heli.landed = false
	heli.fire_cd = 0.0
	heli.fire_cd2 = 0.0
	heli.body.rotation = 0.0
	heli.aim_override = Vector2.RIGHT
	Game.ammo = Game.max_ammo
	main.ui_open = false
	Input.action_press("fire")
	heli._process(0.001)
	Input.action_release("fire")
	heli.aim_override = Vector2.ZERO
	return main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/bullet.gd")).size()


func _sling() -> String:
	# a fixed roll per site
	var site := {"kind": "airfield", "pos": Game.world.BASE_POS + Vector2(500, 0), "uid": "test_airfield"}
	w._roll(site)
	assert(w.wrecks.has("test_airfield"), "an airfield always has a wreck")
	var first: Dictionary = w.wrecks["test_airfield"].duplicate(true)
	w.wrecks.erase("test_airfield")
	w._roll(site)
	assert(w.wrecks["test_airfield"] == first, "the roll is fixed by seed and site")
	var r: Dictionary = w.wrecks["test_airfield"]
	assert(r["cond"] >= Wrecks.COND_MIN and r["cond"] <= Wrecks.COND_MAX and r["keys"].size() == HeliTypes.TYPES[r["type"]]["keys"], "condition 30-90 %%, key parts by type: %s" % [r])
	for i in 40: # the Hind only shows up at military landmarks
		w._roll({"kind": "airfield", "pos": Vector2(9000, 0), "uid": "af%d" % i})
		assert(w.wrecks["af%d" % i]["type"] != "hind", "no Hind at an airfield")
		w.wrecks.erase("af%d" % i)
	var uid := "test_airfield"
	r["type"] = "black_hawk" # sling numbers of a regular airframe
	r["keys"] = ["turbine", "avionics"]
	var spot: Vector2 = r["pos"]
	# hooking: hover, G, 4 s steady
	heli.position = spot + Vector2(200, 0)
	heli.vel = Vector2.ZERO
	heli.landed = false
	heli.pending = 0
	w.toggle_hook()
	assert(w.hook == "", "G away from a wreck does nothing")
	heli.position = spot + Vector2(6, 0)
	heli.vel = Vector2(80, 0)
	w.toggle_hook()
	assert(w.hook == "", "too fast to hook")
	heli.vel = Vector2.ZERO
	w.toggle_hook()
	assert(w.hook == uid and not w.slung(), "hook going down")
	_tick(2.0)
	heli.vel = Vector2(80, 0)
	_tick(0.1)
	assert(w.hook == "", "moving off slips the hook")
	heli.vel = Vector2.ZERO
	w.toggle_hook()
	_tick(Wrecks.HOOK_SECONDS - 0.5)
	assert(not w.slung(), "not before 4 s")
	_tick(0.6)
	assert(w.slung() and r["state"] == "slung", "hooked after 4 s of hovering")
	# with the load: speed, fuel, no landing
	var load_cond: float = r["cond"]
	var slow := _top_speed()
	var burn := _burn()
	w.hook = ""
	var fast := _top_speed()
	var burn0 := _burn()
	w.hook = uid
	assert(absf(slow / fast - HeliTypes.TYPES["black_hawk"]["sling"]) < 0.02, "a load halves the top speed: %s" % (slow / fast))
	assert(is_equal_approx(burn / burn0, Wrecks.SLING_FUEL), "a load doubles the fuel burn: %s" % (burn / burn0))
	r["type"] = "chinook"
	w.wrecks["start"]["type"] = "chinook"
	assert(is_equal_approx(w.speed_factor(), 0.85), "a Chinook only loses 15 %")
	w.wrecks["start"]["type"] = "huey"
	r["type"] = "black_hawk"
	heli.position = spot
	heli.vel = Vector2.ZERO
	w.load_pos = spot
	heli._toggle_landing()
	assert(heli.pending == 0, "no landing with a load")
	# pendulum: the load trails behind and stays on the rope
	var lag := 0.0
	for i in 120:
		heli.position += Vector2(50, 0) * 0.05
		_tick(0.05)
		lag = maxf(lag, heli.position.x - w.load_pos.x)
		assert(heli.position.distance_to(w.load_pos) <= Wrecks.ROPE_MAX + 0.1, "the rope holds the load")
	assert(lag > Wrecks.ROPE * 0.8, "the load trails behind: %s px" % lag)
	var swing: Vector2 = w.load_vel
	for i in 20:
		_tick(0.05) # heli stops: the load swings on
	assert(swing.length() > 1.0, "the load has momentum")
	# zombies at the load chew on it
	r["cond"] = load_cond
	var z: Node2D = main.spawn_enemy("shambler", w.load_pos)
	_tick(1.0)
	assert(r["cond"] < load_cond, "a zombie at the load damages it")
	z.free()
	# G outside the fence: it stays where it is, can be hooked again
	w.toggle_hook()
	assert(w.hook == "" and r["state"] == "site", "released outside: stays")
	var left: Vector2 = r["pos"]
	heli.position = left
	heli.vel = Vector2.ZERO
	w.toggle_hook()
	_tick(Wrecks.HOOK_SECONDS + 0.1)
	assert(w.slung(), "picked up again")
	# G inside the fence: set down for the hangar
	var base_pos: Vector2 = main.base.global_position
	heli.position = base_pos + Vector2(60, 40)
	w.load_pos = heli.position + Vector2(0, 30)
	w.load_vel = Vector2.ZERO
	w.toggle_hook()
	assert(r["state"] == "base" and r["pos"].distance_to(base_pos) <= Game.base_radius, "dropped inside the fence")
	heli.landed = true
	print("WRECK sling OK  slow x%.2f fuel x%.1f lag %.0f px" % [slow / fast, burn / burn0, lag])
	return uid


func _repair(uid: String) -> void:
	var r: Dictionary = w.wrecks[uid]
	var c: Dictionary = w.cost(uid)
	assert(c["days"] >= Wrecks.DAYS_MIN and c["days"] <= Wrecks.DAYS_MAX and c["metal"] > 100, "a big project: %s" % [c])
	r["cond"] = 0.5
	c = w.cost(uid)
	assert(c["metal"] == 200 and c["parts"] == 120 and c["electronics"] == 60 and c["days"] == 15, "Black Hawk at 50 %%: 200/120/60, 15 days: %s" % [c])
	Game.salvage = {"metal": 0.0, "parts": 0.0, "electronics": 0.0}
	assert(w.start_repair(uid).contains("metal"), "no salvage, no project")
	Game.salvage = {"metal": 300.0, "parts": 200.0, "electronics": 100.0}
	w.keys = {"rotor_head": 0, "turbine": 1, "avionics": 0}
	assert(w.start_repair(uid).contains("avionics"), "the key parts are needed")
	w.add_key("avionics")
	assert(w.start_repair(uid) == "" and r["state"] == "repair", "project started")
	assert(Game.salvage["metal"] == 100.0 and w.keys["turbine"] == 0 and w.keys["avionics"] == 0, "salvage and key parts paid up front")
	# no mechanics: no progress
	_repair_tick(Game.DAY_SECONDS)
	assert(r["progress"] == 0.0, "nobody on repair: no progress")
	var mech := _person(9001, "mechanic")
	Game.people.append(mech)
	Game.workers["repair"] = 1
	var eff: float = Game.work_eff() * preload("res://scripts/people.gd").rate(mech, false) # a Lv 1 mechanic works x1.5
	_repair_tick(Game.DAY_SECONDS)
	assert(absf(r["progress"] - eff) < 0.01, "a mechanic does their skill rate in work days a day: %s" % r["progress"])
	mech["skill"] = "engineer"
	var p0: float = r["progress"]
	_repair_tick(Game.DAY_SECONDS)
	assert(absf(r["progress"] - p0 - 2.0 * eff) < 0.01, "an engineer does two")
	_repair_tick(Game.DAY_SECONDS * 8.0)
	assert(r["state"] == "parked", "repaired after the work days")
	assert("black_hawk" in Wrecks.start_types(), "the repaired type is a start heli now")
	Game.people.erase(mech)
	Game.workers["repair"] = 0
	print("WRECK repair OK  %s" % [c])


func _switch(uid: String) -> void:
	var wear: Node = main.wear
	heli.position = main.base.global_position
	heli.landed = true
	heli.vel = Vector2.ZERO
	Game.heli_items["engine"] = 2
	Game.recompute()
	wear.cond["engine"] = 40.0
	Game.hp = Game.max_hp * 0.5
	heli.landed = false
	assert(w.switch_to(uid) != "", "only on the pad")
	heli.landed = true
	assert(w.switch_to(uid) == "", "switched at the pad")
	assert(w.type_id() == "black_hawk" and Game.slots["hardpoint"] >= 2 and heli.size == HeliTypes.TYPES["black_hawk"]["size"], "flying the Black Hawk")
	assert(not Game.heli_items.has("engine") and wear.cond["engine"] == 100.0 and is_equal_approx(Game.hp, Game.max_hp), "its own items, wear and hull")
	assert(w.wrecks["start"]["state"] == "parked", "the Huey is parked")
	Game.heli_items["plating"] = 1
	assert(w.switch_to("start") == "", "back to the Huey")
	assert(w.type_id() == "huey" and Game.heli_items.get("engine", 0) == 2 and not Game.heli_items.has("plating") and wear.cond["engine"] == 40.0 and is_equal_approx(Game.hp, Game.max_hp * 0.5), "the Huey kept its items, wear and hull")
	assert(w.switch_to(uid) == "" and Game.heli_items.has("plating"), "the Black Hawk kept its armour")
	print("WRECK switch OK")


func _modifiers() -> void:
	var m: Node = main.modifiers
	var hp0: float = Game.max_hp
	Game.meta["total_kills"] = 0
	m.start(["dense_horde"])
	assert(m.active.is_empty(), "a locked modifier cannot be picked")
	for id in Modifiers.UNLOCK:
		Game.meta[Modifiers.UNLOCK[id][0]] = Modifiers.UNLOCK[id][1]
	m.start(["glass_cockpit", "scarcity", "dry_season", "future_mod"])
	assert(m.active == ["glass_cockpit", "scarcity", "dry_season"], "unknown ids are dropped")
	assert(is_equal_approx(Game.max_hp, hp0 * Modifiers.HULL) and Game.hp == Game.max_hp, "Glass Cockpit: -40 % hull")
	assert(is_equal_approx(m.loot(10.0), 7.0) and is_equal_approx(Game.wells(), 0.5), "Scarcity -30 % loot, Dry Season wells -50 %")
	assert(is_equal_approx(Modifiers.factor(["glass_cockpit", "scarcity"]), 1.625) and Modifiers.factor(Modifiers.TABLE.keys()) == Modifiers.MAX_FACTOR, "factors multiply, capped at x3")
	assert(Modifiers.factor(["future_mod"]) == 1.0, "unknown ids count 1.0")
	var camp := {"kind": "prison", "pos": Vector2(9000, 0), "uid": ""}
	var held := 0
	for i in 20:
		camp.uid = "p%d" % i
		held += int(main.bandits.holds(camp))
	assert(held == 0, "day 1: no camps")
	m.active.append("warlords")
	for i in 20:
		camp.uid = "p%d" % i
		held += int(main.bandits.holds(camp))
	assert(held > 0, "Warlords: camps from day 1")
	m.active = ["dense_horde"]
	var n0 := get_tree().get_nodes_in_group("enemies").size()
	for i in 30:
		main.spawner._horde()
	assert(get_tree().get_nodes_in_group("enemies").size() >= n0, "Dense Horde spawns")
	m.active = ["blackout", "future_mod"]
	assert(m.on("blackout") and Modifiers.factor(m.active) == 1.2, "an unknown id from a newer save does nothing")
	print("WRECK modifiers OK")


func _save() -> void:
	w.add_key("rotor_head")
	main.modifiers.active = ["scarcity", "future_mod"]
	assert(Save.autosave(), "autosaved")
	var data: Dictionary = Save.read()
	var d: Dictionary = data["systems"]["wrecks"]
	var before: Dictionary = w.save_state()
	w.wrecks = {}
	w.active = "start"
	w.keys = {"rotor_head": 0, "turbine": 0, "avionics": 0}
	w.load_state(d)
	assert(w.save_state() == before and w.type_id() == "black_hawk", "wrecks, fleet and key parts round-trip")
	main.modifiers.active = []
	Save.load_run()
	assert(main.modifiers.active == ["scarcity", "future_mod"], "modifiers round-trip")
	# a save from before P15: no wrecks / modifiers keys, no start_helis in meta
	data["systems"].erase("wrecks")
	data["systems"].erase("modifiers")
	Save._write(var_to_bytes(data))
	main.modifiers.active = []
	assert(Save.load_run() and Game.running and main.modifiers.active.is_empty(), "an old save loads, without modifiers")
	Save.delete_run()
	var meta: Dictionary = Game.meta.duplicate()
	Game.meta.erase("start_helis")
	assert(Wrecks.start_types() == ["huey"], "old meta: only the Huey")
	Game.meta = meta
	print("WRECK save OK")


func _person(id: int, skill: String) -> Dictionary:
	return {"id": id, "name": "Person %d" % id, "skill": skill, "skill_lv": 1, "trait": "", "injured": false, "job": "repair", "aboard": false,
		"origin_day": 1, "job_days": 0, "pin": "repair", "post": ""}


func _tick(seconds: float) -> void:
	var n := ceili(seconds / 0.05)
	for i in n:
		w._process(seconds / n)


func _repair_tick(seconds: float) -> void:
	var n := 20
	for i in n:
		w._repairs(seconds / n)


func _top_speed() -> float:
	var pos: Vector2 = heli.position
	heli.landed = false
	heli.vel = Vector2.ZERO
	Input.action_press("move_right")
	for i in 200:
		heli._move(0.05)
	Input.action_release("move_right")
	var v: float = heli.vel.length()
	heli.position = pos
	heli.vel = Vector2.ZERO
	return v


func _burn() -> float:
	heli.landed = false
	heli.vel = Vector2.ZERO
	Game.fuel = Game.max_fuel
	heli._fuel(10.0)
	return Game.max_fuel - Game.fuel
