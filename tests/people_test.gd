extends Node
## Headless people + morale test (docs/ROADMAP.md P7). main.gd adds this node when env SMOKE=people (base founded):
##   SMOKE=people godot --headless --path . --quit-after 30000
## Delivery brings named people, names follow the run seed, assignment prefers skills, skilled work is faster,
## a death removes the right person, the count getters match, morale falls with hunger and slows work, save hooks
## round-trip people and morale.

const People := preload("res://scripts/people.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var frame := get_tree().process_frame
	await frame
	await frame
	get_tree().paused = true # Game._process stays out of the way, the test drives the clock
	assert(Game.rescued == 0 and Game.people.is_empty(), "test base starts empty")
	# --- names from the run seed
	var a := People.make(1234, 7, 1, false)
	assert(a == People.make(1234, 7, 1, false) and a["name"].contains(" "), "same seed and number, same person: %s" % a)
	var names := {}
	for i in 40:
		names[People.make(1234, i, 1, false)["name"]] = true
	assert(names.size() >= 38, "names vary: %d of 40" % names.size())
	# --- boarding and delivery: the same people move in
	Game.passengers = 4
	Game.passengers_injured = 1
	var aboard: Array = Game.people.map(func(p): return p["name"])
	assert(Game.passengers == 4 and Game.passengers_injured == 1 and Game.rescued == 0, "4 aboard, 1 hurt")
	assert(Game.deliver() == 4, "delivered 4")
	assert(Game.rescued == 4 and Game.injured == 1 and Game.passengers == 0, "getters after delivery")
	assert(Game.people.map(func(p): return p["name"]) == aboard, "the same named people moved in")
	# --- assignment prefers the skill
	Game.people.clear()
	Game.people.append(_person(0, "farmer"))
	Game.people.append(_person(1, "builder"))
	Game.people.append(_person(2, "medic"))
	Game.people.append(_person(3, "farmer"))
	Game.people[3]["skill_lv"] = 3
	Game.workers = {"fuel": 0, "ammo": 0, "repair": 0, "militia": 0, "farm": 1, "build": 1, "medic": 0, "water": 0, "workshop": 0}
	Game.assign_jobs()
	assert(Game.people[3]["job"] == "farm" and Game.people[1]["job"] == "build", "skill first, best level first: %s" % [Game.people.map(func(p): return p["job"])])
	assert(Game.people[0]["job"] == "" and Game.people[2]["job"] == "", "the rest idle")
	assert(is_equal_approx(Game.crew("farm"), 2.0) and is_equal_approx(Game.crew("build"), 1.5), "skilled rates: farm %s build %s" % [Game.crew("farm"), Game.crew("build")])
	Game.workers["fuel"] = 2
	Game.assign_jobs()
	assert(is_equal_approx(Game.crew("fuel"), 2.0), "no fuel skill here: plain rate")
	# skill level rises with days in a matching job
	Game.people[1]["job_days"] = People.LEVEL_DAYS[0] - 1
	var up := People.new_day(Game.people)
	assert(Game.people[1]["skill_lv"] == 2 and Game.people[1] in up, "builder reached Lv 2")
	# traits
	var lazy := _person(9, "farmer")
	lazy["trait"] = "lazy"
	lazy["job"] = "fuel"
	assert(is_equal_approx(People.rate(lazy, false), People.LAZY_RATE), "lazy works slower")
	lazy["trait"] = "insomniac"
	assert(People.rate(lazy, true) > People.rate(lazy, false), "insomniac works on at night")
	# --- injuries: the Tough last; a death removes the injured one
	Game.people[0]["trait"] = "tough"
	Game.injure(3)
	assert(Game.injured == 3 and not Game.people[0]["injured"], "3 hurt, the Tough one spared")
	assert(Game.idle_workers() >= 0 and Game.assigned() <= 1, "jobs freed for the hurt")
	Game.people[0]["trait"] = ""
	for p in Game.people:
		p["injured"] = p["id"] == 2
	Game.treating.clear()
	var lost := []
	Game.person_lost.connect(func(p: Dictionary, died: bool): lost.append([p["id"], died]), CONNECT_ONE_SHOT)
	var who := Game.lose_person(true)
	assert(lost == [[2, true]] and who.begins_with("Person"), "the injured one died: %s %s" % [lost, who])
	assert(Game.rescued == 3 and Game.injured == 0, "getters after the death")
	Game.rescued = 5 # facade: count setters still work
	assert(Game.people.size() == 5 and Game.people[4]["name"] != "", "count setter adds named people")
	Game.injured = 2
	assert(Game.injured == 2, "count setter marks the injured")
	Game.injured = 0
	Game.rescued = 3
	assert(Game.people.size() == 3, "count setter removes people")
	# --- morale: hunger and thirst pull it down, low morale slows work
	var morale: Node = main.morale
	assert(morale.value == morale.START, "morale starts at %d" % morale.START)
	var eff := Game.work_eff()
	Game.base_food = 0.0
	Game.base_water = 0.0
	morale._on_day(Game.day + 1)
	assert(morale.value < morale.START and "hunger" in morale.summary() and "thirst" in morale.summary(), "hunger and thirst: %s" % morale.summary())
	morale.value = 30.0
	assert(is_equal_approx(Game.work_eff(), eff * morale.LOW_RATE), "low morale slows work")
	# held assault with losses, a big rescue (counted at the next day change)
	Game.attack_active = true
	morale._process(0.0)
	Game.lose_person()
	Game.attack_active = false
	morale._process(0.0)
	Game.people_delivered.emit(5)
	var v0: float = morale.value
	Game.base_food = 100.0
	Game.base_water = 100.0
	morale._on_day(Game.day + 2)
	assert("assault held" in str(morale.reasons) and "losses" in str(morale.reasons) and "5 rescued" in str(morale.reasons) and "1 dead" in str(morale.reasons), "reasons %s" % [morale.reasons])
	print("morale %d -> %s" % [v0, morale.summary()])
	# --- pins: a pinned person keeps the job, counts stay true, auto fills the rest, injured pinned are off duty
	var ui: CanvasLayer = main.base.ui
	var keep := Game.people.duplicate()
	var keep_w := Game.workers.duplicate()
	Game.people.clear()
	for i in 5:
		Game.people.append(_person(10 + i, ["farmer", "farmer", "builder", "medic", "soldier"][i]))
	for j in Game.workers:
		Game.workers[j] = 0
	var p10: Dictionary = Game.people[0]
	var p11: Dictionary = Game.people[1]
	var p12: Dictionary = Game.people[2]
	var p13: Dictionary = Game.people[3]
	var p14: Dictionary = Game.people[4]
	assert(ui.set_worker("farm", 2), "two farm seats")
	assert(ui.pin_person(12, "farm") and p12["pin"] == "farm", "builder pinned to farm")
	assert(p12["job"] == "farm" and p10["job"] == "farm" and p11["job"] == "" and Game.workers["farm"] == 2 and Game.assigned() == 2, "pin takes a seat, auto fills the other: %s" % [Game.people.map(func(p): return p["job"])])
	assert(ui.pin_person(14, "build") and Game.workers["build"] == 1 and p14["job"] == "build" and Game.assigned() == 3, "a pin raises the count of a job with no seat")
	assert(not ui.set_worker("build", 0) and Game.workers["build"] == 1, "lowering a count below its pinned people is refused")
	assert(ui.set_worker("fuel", 1) and ui.pin_person(13, "repair") and Game.workers["repair"] == 1 and Game.idle_workers() == 0, "pin an idle person: one seat more")
	assert(ui.pin_person(10, "ammo") and Game.workers["ammo"] == 1 and Game.workers["farm"] == 1 and Game.assigned() == 5, "a held seat moves with the pin: %s" % Game.workers)
	assert(Game.assigned() <= 5 and Game.idle_workers() >= 0, "counts never exceed the healthy: %s" % Game.workers)
	var jobs_a: Array = Game.people.map(func(p): return p["job"])
	Game.assign_jobs()
	assert(jobs_a == Game.people.map(func(p): return p["job"]), "assign is deterministic")
	for j in Game.workers:
		assert(Game.people.filter(func(p): return p["job"] == j).size() == Game.workers[j], "count and reality agree on %s: %s" % [j, Game.workers])
	# an injured pinned person keeps the pin and is off duty until healed
	p12["injured"] = true
	p12["job"] = ""
	Game._fit_workers()
	Game.assign_jobs()
	assert(p12["pin"] == "farm" and p12["job"] == "" and Game.pinned("farm") == 0 and Game.idle_workers() >= 0, "injured pinned: pin kept, off duty")
	assert(Game.pinned("build") == 1 and Game.workers["build"] >= 1 and p14["job"] == "build", "the other pins keep their seats")
	p12["injured"] = false
	Game.assign_jobs()
	assert(p12["job"] == "farm" and Game.workers["farm"] >= 1, "healed: back on the pinned job")
	# sorting and filtering
	var ids := func(l: Array) -> Array: return l.map(func(p): return p["id"])
	assert(ids.call(People.view(Game.people, "name", "all")) == [10, 11, 12, 13, 14], "sort by name")
	assert(ids.call(People.view(Game.people, "level", "all")) == [10, 11, 12, 13, 14], "equal levels fall back to name")
	p14["skill_lv"] = 3
	assert(People.view(Game.people, "level", "all")[0] == p14, "best level first")
	assert(ids.call(People.view(Game.people, "skill", "all")) == [12, 10, 11, 13, 14], "sort by skill: builder, farmer, farmer, medic, soldier")
	assert(ids.call(People.view(Game.people, "name", "skill:farmer")) == [10, 11] and ids.call(People.view(Game.people, "name", "job:build")) == [14], "filter by skill and job")
	assert(ids.call(People.view(Game.people, "name", "pinned")) == [10, 12, 13, 14] and ids.call(People.view(Game.people, "name", "idle")) == [11], "filter pinned and idle")
	p11["injured"] = true
	p11["job"] = ""
	assert(ids.call(People.view(Game.people, "job", "injured")) == [11] and People.view(Game.people, "job", "all")[-1] == p11 and not ids.call(People.view(Game.people, "name", "idle")).has(11), "injured last in job order, not idle")
	p11["injured"] = false
	ui.people_filter = "skill:farmer"
	ui.people_sort = "name"
	ui._refresh_people()
	assert(ui.people_box.get_child_count() == 2, "the UI list follows the filter")
	ui.people_filter = "all"
	ui._refresh_people()
	assert(ui.people_box.get_child_count() == 5, "the UI list shows everyone")
	# the pin is saved; a save from before pins loads without the key
	var gp: Dictionary = bytes_to_var(var_to_bytes(Game.save_state()))
	for p in Game.people:
		p["pin"] = "x"
	Game.load_state(gp)
	assert(Game.people[2]["pin"] == "farm" and Game.people[3]["pin"] == "repair" and Game.people[0]["pin"] == "ammo", "pins survive the save")
	for p in gp["people"]:
		p.erase("pin")
	Game.load_state(gp)
	assert(not Game.people[2].has("pin"), "old save: no pin key")
	Game.assign_jobs()
	ui.refresh()
	assert(Game.people[2].get("pin", "") == "" and Game.assigned() <= Game.rescued, "old save loads and assigns")
	ui.pin_person(12, "farm")
	ui.unassign_all()
	assert(Game.people.all(func(p): return p.get("pin", "") == "") and Game.assigned() == 0, "unassign all clears the pins")
	Game.people.assign(keep)
	Game.workers = keep_w
	# --- save hooks round-trip people and morale
	var g: Dictionary = bytes_to_var(var_to_bytes(Game.save_state()))
	var m: Dictionary = bytes_to_var(var_to_bytes(morale.save_state()))
	var people_before := var_to_str(Game.people)
	var morale_before: float = morale.value
	Game.people.clear()
	morale.value = 1.0
	Game.load_state(g)
	morale.load_state(m)
	assert(var_to_str(Game.people) == people_before and Game.people.get_typed_builtin() == TYPE_DICTIONARY, "people restored")
	assert(morale.value == morale_before and Game.rescued == 2, "morale and counts restored")
	print("PEOPLE OK  %s" % ", ".join(Game.people.map(People.short)))
	get_tree().quit(0)


func _person(id: int, skill: String) -> Dictionary:
	return {"id": id, "name": "Person %d" % id, "skill": skill, "skill_lv": 1, "trait": "", "injured": false, "job": "", "aboard": false, "origin_day": 1, "job_days": 0, "pin": ""}
