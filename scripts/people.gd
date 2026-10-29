extends RefCounted
## Named survivors (docs/ROADMAP.md P7). A person is a Dictionary in Game.people (built-in types only, saved as is):
##   {id, name, skill, skill_lv 1-3, trait ("" or one of TRAITS), injured, job ("" = idle), aboard (in the heli),
##    origin_day (joined the run), job_days (days worked in a job matching the skill)}
## Game.rescued / injured / passengers / passengers_injured are counts over this list. Game.workers stays the wanted
## number per job; assign() picks who: matching skill first (best level first), then anyone.

const NAMES_PATH := "res://data/names.txt"
const SKILL_WEIGHT := {"mechanic": 17, "farmer": 20, "medic": 13, "soldier": 17, "builder": 18, "driver": 10, "engineer": 5}
# jobs a skill is good at; ammo and fuel have no own skill in the plan, soldier and driver/engineer take them
const SKILL_JOBS := {"mechanic": ["repair", "workshop"], "farmer": ["farm", "water"], "medic": ["medic"], "soldier": ["militia", "ammo"],
	"builder": ["build"], "driver": ["fuel"], "engineer": ["repair", "workshop", "fuel"]}
const SKILL_TAG := {"mechanic": "MEC", "farmer": "FRM", "medic": "MED", "soldier": "SOL", "builder": "BLD", "driver": "DRV", "engineer": "ENG"}
const SKILL_RATE := [1.0, 1.5, 1.75, 2.0] # work rate by skill level in a matching job, index 0 = not matching
const LEVEL_DAYS := [5, 15] # days in a matching job for level 2 and 3
const TRAITS := ["tough", "glutton", "lazy", "brave", "insomniac"]
const TRAIT_CHANCE := 0.5
const GLUTTON_FOOD := 1.5
const LAZY_RATE := 0.8
const INSOMNIAC_NIGHT := 1.5 # works on through the night: +50 % while it is dark

static var _names := {} # "first"/"last" -> PackedStringArray, read once


static func _load_names() -> void:
	_names = {"first": PackedStringArray(), "last": PackedStringArray()}
	var part := "first"
	for line in FileAccess.get_file_as_string(NAMES_PATH).split("\n"):
		line = line.strip_edges()
		if line.begins_with("#"):
			part = "last" if "last" in line else "first"
		elif line != "":
			_names[part].append(line)


## The person number `seq` of the run with `run_seed`: same seed, same people in the same order.
static func make(run_seed: int, seq: int, day: int, aboard: bool) -> Dictionary:
	if _names.is_empty():
		_load_names()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, seq])
	var skill: String = SKILL_WEIGHT.keys()[rng.rand_weighted(PackedFloat32Array(SKILL_WEIGHT.values()))]
	var first: PackedStringArray = _names["first"]
	var last: PackedStringArray = _names["last"]
	return {"id": seq, "name": "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]], "skill": skill, "skill_lv": 1,
		"trait": TRAITS[rng.randi() % TRAITS.size()] if rng.randf() < TRAIT_CHANCE else "", "injured": false, "job": "", "aboard": aboard,
		"origin_day": day, "job_days": 0}


static func matches(p: Dictionary, job: String) -> bool:
	return job in SKILL_JOBS[p["skill"]]


## Work output of `p` in its job relative to an average worker (Game.crew sums these).
static func rate(p: Dictionary, night: bool) -> float:
	var r: float = SKILL_RATE[p["skill_lv"] if matches(p, p["job"]) else 0]
	match p["trait"]:
		"lazy": r *= LAZY_RATE
		"insomniac": r *= INSOMNIAC_NIGHT if night else 1.0
	return r


static func food(p: Dictionary) -> float:
	return GLUTTON_FOOD if p["trait"] == "glutton" else 1.0


## Fills `workers` (job -> wanted count) from the healthy `list`: matching skills first, best level first, then the rest.
static func assign(list: Array, workers: Dictionary) -> void:
	var left := workers.duplicate()
	var fit := []
	for p in list:
		p["job"] = ""
		if not p["injured"]:
			fit.append(p)
	fit.sort_custom(func(a, b): return a["skill_lv"] > b["skill_lv"] or (a["skill_lv"] == b["skill_lv"] and a["id"] < b["id"]))
	for p in fit:
		for j in SKILL_JOBS[p["skill"]]:
			if left.get(j, 0) > 0:
				p["job"] = j
				left[j] -= 1
				break
	for p in fit:
		if p["job"] == "":
			for j in left:
				if left[j] > 0:
					p["job"] = j
					left[j] -= 1
					break


## A day passed: a day of practice for everyone in a matching job. Returns the people who reached a new level.
static func new_day(list: Array) -> Array:
	var up := []
	for p in list:
		if p["job"] != "" and matches(p, p["job"]):
			p["job_days"] += 1
			var lv := 1 + int(p["job_days"] >= LEVEL_DAYS[0]) + int(p["job_days"] >= LEVEL_DAYS[1])
			if lv > p["skill_lv"]:
				p["skill_lv"] = lv
				up.append(p)
	return up


## "MED2 Marta K." for short lists (HUD, worker rows).
static func short(p: Dictionary) -> String:
	var parts: PackedStringArray = p["name"].split(" ", false, 1)
	return "%s%d %s %s." % [SKILL_TAG[p["skill"]], p["skill_lv"], parts[0], parts[1].substr(0, 1) if parts.size() > 1 else ""]


## Detail line for the WORKERS tab.
static func describe(p: Dictionary, morale: int, day: int) -> String:
	return "%s  -  %s Lv %d (%d days practice)%s\n%s  -  mood %d  -  %d days with you%s" % [p["name"], p["skill"].capitalize(), p["skill_lv"], p["job_days"],
		"  -  " + p["trait"].capitalize() if p["trait"] != "" else "", "injured" if p["injured"] else ("job: " + p["job"] if p["job"] != "" else "idle"),
		morale, day - p["origin_day"], "  (good at %s)" % ", ".join(SKILL_JOBS[p["skill"]])]
