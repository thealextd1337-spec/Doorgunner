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
	return {"id": id, "name": "Person %d" % id, "skill": skill, "skill_lv": 1, "trait": "", "injured": false, "job": "", "aboard": false, "origin_day": 1, "job_days": 0}
