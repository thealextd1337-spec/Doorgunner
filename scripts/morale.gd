extends Node
## Base morale 0-100 (docs/ROADMAP.md P7), main.gd keeps it as `morale`. Settled once a day from what happened:
## hunger, thirst, campers, deaths, power, beds, assaults, big rescues, plus events other systems report with add().
## Below LOW_BELOW work is slower, below LEAVE_BELOW someone may walk out at night, above HIGH_ABOVE work is faster.
## Saves itself (hook "morale").

const START := 60.0
const HUNGER := -10.0
const THIRST := -10.0
const CAMPERS_PER_QUARTER := -5.0 # per 25 % of the people camping outside
const PER_DEATH := -8.0
const ASSAULT_LOSSES := -5.0 # halved for the share of Brave people
const POWER := 5.0
const BEDS := 5.0
const ASSAULT_HELD := 3.0
const BIG_RESCUE := 4.0 # per delivered group of BIG_GROUP or more
const BIG_GROUP := 4
const LOW_BELOW := 40.0
const LOW_RATE := 0.85
const HIGH_ABOVE := 75.0
const HIGH_RATE := 1.1
const LEAVE_BELOW := 25.0
const LEAVE_CHANCE := 0.1

var value := START
var reasons := [] # yesterday's [text, change], strongest first
var pending := [] # [text, change] collected since the last day change
var deaths := 0 # since the last day change
var _in_attack := false
var _attack_deaths := 0


func _ready() -> void:
	Game.day_changed.connect(_on_day)
	Game.person_lost.connect(_on_lost)
	Game.people_delivered.connect(func(n: int): if n >= BIG_GROUP: add(BIG_RESCUE, "%d rescued at once" % n))
	Save.register("morale", save_state, load_state)


## Work rate factor for Game.work_eff.
func rate() -> float:
	return LOW_RATE if value < LOW_BELOW else (HIGH_RATE if value > HIGH_ABOVE else 1.0)


## An event that counts at the next day change (bandit camp cleared, blood moon held ...).
func add(change: float, why: String) -> void:
	pending.append([why, change])


## "62  hunger -10, power +5, beds +5": value and the three strongest reasons of the last day.
func summary() -> String:
	return "%d  %s" % [value, ", ".join(reasons.slice(0, 3).map(func(r): return "%s %+d" % [r[0], r[1]]))]


func _on_lost(_p: Dictionary, died: bool) -> void:
	if died:
		deaths += 1
		_attack_deaths += int(Game.attack_active)


func _process(_delta: float) -> void:
	if Game.attack_active and not _in_attack:
		_attack_deaths = 0
	elif _in_attack and not Game.attack_active:
		add(ASSAULT_HELD, "assault held")
		if _attack_deaths > 0:
			var brave := Game.people.filter(func(p): return p["trait"] == "brave").size() / maxf(1.0, Game.people.size())
			add(ASSAULT_LOSSES * (1.0 - 0.5 * brave), "losses in the assault")
	_in_attack = Game.attack_active


func _on_day(_day: int) -> void:
	if not Game.base_founded or Game.rescued == 0:
		pending.clear()
		deaths = 0
		return
	var r := pending.duplicate()
	if Game.base_food <= 0.0:
		r.append(["hunger", HUNGER])
	if Game.base_water <= 0.0:
		r.append(["thirst", THIRST])
	var quarters := int(4.0 * Game.campers() / Game.rescued)
	if quarters > 0:
		r.append(["camping outside", CAMPERS_PER_QUARTER * quarters])
	if deaths > 0:
		r.append(["%d dead" % deaths, PER_DEATH * deaths])
	if Game.power:
		r.append(["power", POWER])
	if Game.campers() == 0:
		r.append(["beds for all", BEDS])
	for x in r:
		value += x[1]
	value = clampf(value, 0.0, 100.0)
	r.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
	reasons = r
	pending = []
	deaths = 0
	if value < LEAVE_BELOW and randf() < LEAVE_CHANCE:
		var who := Game.walk_out()
		if who != "":
			Game.radio("Base: morale is broken. %s packed up and left in the night." % who)


func save_state() -> Dictionary:
	return {"value": value, "reasons": reasons, "pending": pending, "deaths": deaths, "in_attack": _in_attack, "attack_deaths": _attack_deaths}


func load_state(d: Dictionary) -> void:
	value = d["value"]
	reasons = d["reasons"]
	pending = d["pending"]
	deaths = d["deaths"]
	_in_attack = d["in_attack"]
	_attack_deaths = d["attack_deaths"]
