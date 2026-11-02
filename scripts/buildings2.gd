class_name Buildings2
extends Node
## Five more base buildings (docs/ROADMAP2.md Q9). They are plain Game.buildings entries (game_state.gd BUILDINGS), placed, built
## by Build workers and saved like the others; this file holds what they do. main.gd keeps the node as `buildings2`, it runs the
## Greenhouse and the Forge and saves itself (hook "buildings2"). Everything else is static, read where the effect applies.
##   hospital    Field Hospital, an add-on to a built Field Clinic (one per clinic): +HOSPITAL_BEDS beds, patients heal HOSPITAL_HEAL x
##               faster (game_state.gd clinic_beds / _treat).
##   greenhouse  food without farmland: +GREENHOUSE_FOOD a day, drinks GREENHOUSE_WATER a day; dry tanks, no harvest.
##   forge       the "forge" job (Mechanics and Engineers are good at it, FORGE_SLOTS per forge): FORGE_RATE units a day per worker.
##               A unit is a part from FORGE_PART_METAL metal, else metal from FORGE_METAL_SCRAP scrap (never below FORGE_KEEP_SCRAP).
##   bunker      the base breach (hull at 0) is survived once: the survivors hide, the wave breaks off, the hull comes back at
##               BUNKER_HULL, BUNKER_INJURED are hurt and the bunker is spent (build another). Not against the final siege.
##               While one stands, assault losses weigh BUNKER_LOSSES as much on morale and a held assault gives BUNKER_HELD more.
##   relay       Radio Relay (one): RELAY_REACH x the minimap's POI reveal, the command radio's hints and the mission radius (hud.gd,
##               radio.gd, missions.gd); bandit raids on the base are intercepted RELAY_LEAD day early (bandits.gd).
## Radio Station and Airstrip stay in evac.gd.

const KINDS := ["hospital", "greenhouse", "forge", "bunker", "relay"]
const HOSPITAL_BEDS := 4
const HOSPITAL_HEAL := 1.5
const GREENHOUSE_FOOD := 5.0 # per day
const GREENHOUSE_WATER := 4.0 # per day
const FORGE_RATE := 6.0 # units per worker per day
const FORGE_SLOTS := 2 # workers per forge
const FORGE_METAL_SCRAP := 3 # scrap per metal
const FORGE_PART_METAL := 2 # metal per part
const FORGE_KEEP_SCRAP := 30 # the forge never spends the last of the scrap
const FORGE_CAP := 60.0 # stops making a thing at this stock
const BUNKER_HULL := 0.3 # share of the hull left after the breach
const BUNKER_INJURED := 2
const BUNKER_LOSSES := 0.5 # factor on the morale loss of an assault
const BUNKER_HELD := 4.0 # morale for a held assault
const RELAY_REACH := 1.5
const RELAY_LEAD := 1 # days
# build bar and BUILD tab tooltips
const TIPS := {
	"hospital": "Field Hospital: add-on to a built Field Clinic (one per clinic). +4 patient beds and patients heal 1.5x faster.",
	"greenhouse": "Greenhouse: grows +5 food a day without farmland but drinks 4 water a day. No water, no harvest.",
	"forge": "Forge: Mechanics and Engineers work it (2 per forge). Turns 3 scrap into metal and 2 metal into a part. Never spends the last 30 scrap.",
	"bunker": "Bunker: when the base is breached the survivors hide in it once and the wave breaks off. The bunker is spent. Calms the base during assaults.",
	"relay": "Radio Relay (one): 1.5x reveal, radio hints and mission radius, and bandit raids on the base are heard a day early.",
}

var forge_progress := 0.0 # forge units owed, carried between frames


func _ready() -> void:
	Save.register("buildings2", save_state, load_state)


func _process(delta: float) -> void:
	if not Game.running or get_tree().paused or not Game.base_founded:
		return
	var d := delta / Game.DAY_SECONDS
	var gh := Game.built("greenhouse")
	if gh > 0 and Game.base_water > 0.0:
		Game.base_food += gh * GREENHOUSE_FOOD * d
		Game.base_water = maxf(0.0, Game.base_water - gh * GREENHOUSE_WATER * d)
	var f := Game.built("forge")
	if f == 0:
		forge_progress = 0.0
		return
	forge_progress += Game.crew("forge") * FORGE_RATE * Game.work_eff() * d
	while forge_progress >= 1.0:
		forge_progress -= 1.0
		if not forge_unit():
			forge_progress = 0.0
			return
	forge_progress = minf(forge_progress, 1.0) # no stockpiling while idle


## One unit of forge work: a part from metal if there is room for parts, else metal from scrap. False: nothing to do.
static func forge_unit() -> bool:
	var s: Dictionary = Game.salvage
	if s["metal"] >= FORGE_PART_METAL and s["parts"] < FORGE_CAP:
		s["metal"] -= FORGE_PART_METAL
		s["parts"] += 1.0
		return true
	if Game.scrap - FORGE_METAL_SCRAP >= FORGE_KEEP_SCRAP and s["metal"] < FORGE_CAP:
		Game.scrap -= FORGE_METAL_SCRAP
		s["metal"] += 1.0
		return true
	return false


## Heal speed factor of the patients (Field Hospital).
static func heal_speed() -> float:
	return HOSPITAL_HEAL if Game.built("hospital") > 0 else 1.0


## Radio Relay: factor on reveal, radio hint and mission radius.
static func reach() -> float:
	return RELAY_REACH if Game.built("relay") > 0 else 1.0


## Days ahead bandit raids on the base are announced (bandits.gd).
static func lead() -> int:
	return RELAY_LEAD if Game.built("relay") > 0 else 0


## Factor on the morale loss of an assault (morale.gd).
static func loss_factor() -> float:
	return BUNKER_LOSSES if Game.built("bunker") > 0 else 1.0


## Food a day the greenhouses grow and water they drink (the BASE menu's per-day numbers).
static func greenhouse_food() -> float:
	return Game.built("greenhouse") * GREENHOUSE_FOOD if Game.base_water > 0.0 else 0.0


static func greenhouse_water() -> float:
	return Game.built("greenhouse") * GREENHOUSE_WATER if Game.base_water > 0.0 else 0.0


## Why `kind` cannot be placed right now, "" if it can (base.gd can_place, the ghost and the tooltips).
static func refusal(kind: String) -> String:
	if not kind in KINDS:
		return ""
	var have: int = Game.buildings.filter(func(b): return b["kind"] == kind).size()
	match kind:
		"hospital":
			if Game.built("clinic") == 0:
				return "needs a built Field Clinic"
			if have >= Game.built("clinic"):
				return "one hospital per clinic: build another clinic"
		"bunker", "relay":
			if have > 0:
				return "one is enough"
	return ""


## The base is breached (hull 0). True: the bunker took the survivors, the run goes on (base.gd take_damage).
static func shelter() -> bool:
	var world := Game.world
	var site := Game.buildings.filter(func(b): return b["kind"] == "bunker" and b["built"])
	if site.is_empty() or world.assault.final:
		return false
	var b: Dictionary = site[0]
	Game.buildings.erase(b)
	var node: Node = world.base.site_nodes.get(b["cell"])
	if node:
		node.queue_free()
	world.base.site_nodes.erase(b["cell"])
	world.nav_dirty() # the bunker footprint is walkable again
	Game.base_hp = Game.max_base_hp * BUNKER_HULL
	Game.injure(BUNKER_INJURED)
	world.assault.abort()
	world.morale.breached()
	Game.radio("Base: the line broke, everyone is in the bunker! The wave pulled back. The bunker is spent, %d hurt." % BUNKER_INJURED)
	return true


func save_state() -> Dictionary:
	return {"forge_progress": forge_progress}


func load_state(d: Dictionary) -> void:
	forge_progress = d.get("forge_progress", 0.0)
