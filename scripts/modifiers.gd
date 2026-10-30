extends Node
## Run modifiers (docs/ROADMAP.md P15): picked on the title for NEW RUN, voluntary, each a score factor for the leaderboard
## (server table public.modifiers, migration server/supabase/006_modifiers.sql; the server multiplies them, capped at MAX_FACTOR).
## Each is a meta unlock of the profile (UNLOCK: a meta.json counter and the value it must reach).
## main.gd keeps it as `modifiers`, it saves itself (hook "modifiers"); a run saved before P15 has none. Ids this version does not
## know (a newer save) are kept for the server but do nothing here.
## Effects live where they bite, each one call of on(id): spawner.gd (dense_horde), bandits.gd (warlords; convoys.gd ambushes
## through bandits.first_camp_day), poi.gd and convoys.gd loot (scarcity; village / outpost stock not), game_state.gd wells
## (dry_season), start(): hull (glass_cockpit), hud.gd / poi.gd / radio.gd / bandits.gd map reveal (blackout; radio mission
## targets in missions.gd stay marked, the mission needs them).

const TABLE := {
	"dense_horde": {"name": "Dense Horde", "desc": "+50 % zombies", "factor": 1.3},
	"warlords": {"name": "Warlords", "desc": "bandits from day 1", "factor": 1.25},
	"scarcity": {"name": "Scarcity", "desc": "-30 % loot", "factor": 1.25},
	"dry_season": {"name": "Dry Season", "desc": "wells -50 %", "factor": 1.15},
	"glass_cockpit": {"name": "Glass Cockpit", "desc": "-40 % hull", "factor": 1.3},
	"blackout": {"name": "Blackout", "desc": "the map reveals nothing", "factor": 1.2},
}
const UNLOCK := {
	"dense_horde": ["total_kills", 500, "kills"],
	"warlords": ["best_day", 8, "reach day"],
	"scarcity": ["runs", 3, "runs played"],
	"dry_season": ["best_day", 12, "reach day"],
	"glass_cockpit": ["assaults_held", 5, "assaults held"],
	"blackout": ["boss_kills", 3, "boss kills"],
}
const MAX_FACTOR := 3.0 # same cap as upsert_run (c_max_factor)
const HORDE_EXTRA := 0.5 # dense_horde: chance of a second zombie per spawned one, and +50 % enemy cap
const LOOT := 0.7 # scarcity
const WELLS := 0.5 # dry_season
const HULL := 0.6 # glass_cockpit

var active: Array = [] # modifier ids of this run


func _ready() -> void:
	Save.register("modifiers", func(): return {"active": active.duplicate()}, func(d: Dictionary): active = d["active"].duplicate())


func on(id: String) -> bool:
	return id in active


## Run start (main.gd, title NEW RUN): take the picked ids and apply the one-time effects.
func start(ids: Array) -> void:
	active = ids.filter(func(id): return TABLE.has(id) and unlocked(id))
	if on("glass_cockpit"):
		Game.max_hp *= HULL
		Game.hp = Game.max_hp


static func unlocked(id: String) -> bool:
	return UNLOCK.has(id) and int(Game.meta.get(UNLOCK[id][0], 0)) >= UNLOCK[id][1]


## "reach day 8 (3/8)"
static func condition(id: String) -> String:
	var u: Array = UNLOCK[id]
	return "%s %d (%d/%d)" % [u[2], u[1], int(Game.meta.get(u[0], 0)), u[1]]


## Combined score factor of `ids` (unknown ids count 1.0, like the server).
static func factor(ids: Array) -> float:
	var f := 1.0
	for id in ids:
		f *= TABLE.get(id, {"factor": 1.0})["factor"]
	return minf(f, MAX_FACTOR)


## Looted amount under Scarcity.
func loot(x: float) -> float:
	return x * (LOOT if on("scarcity") else 1.0)
