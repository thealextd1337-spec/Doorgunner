extends Node
## Autoload "Game": run resources, day clock, upgrade stats, meta progression.

signal level_up(level: int)
signal day_changed(day: int)
signal base_attack_started(day: int)
signal run_ended(reason: String)
signal radio_message(msg: String)

const DAY_SECONDS := 600.0
const ATTACK_EVERY_DAYS := 3
const META_PATH := "user://meta.json"
const ART_VARIANTS := ["b"] # Field Map only
const Weapons := preload("res://scripts/weapons.gd")
const HELI_SLOTS := 2
const LOADOUT_COST := {"seats": 1, "fuel_tank": 2, "ammo_feed": 2, "armor": 2} # weight points per level
const WORKER_RATE := {"fuel": 20.0, "ammo": 40.0, "repair": 40.0, "farm": 6.0, "water": 15.0} # per worker per day
const BUILD_SECONDS := 20.0 # one sandbag per build worker
const MEDIC_REPAIR := 20.0 # free hull per medic per landing
const SANDBAG_HP := 120.0
const SANDBAG_COST := 5
const SANDBAG_MAX := 80
const FOOD_PER_PERSON := 1.0 # per day

var heli: Node2D
var world: Node2D
var seed := 0
var running := false

# run resources
var fuel := 100.0
var max_fuel := 100.0
var ammo := 200
var max_ammo := 200
var hp := 100.0
var max_hp := 100.0
var seats := 4
var passengers := 0
var scrap := 0
var xp := 0
var level := 1
var day := 1
var time := 0.25 # 0..1 fraction of a day, 0 = midnight
var rescued := 0
var kills := 0
var base_hp := 500.0
var max_base_hp := 500.0
var attack_pending := false
var attack_active := false
var base_level := {} # upgrade id -> level

# weapons: weapon = equipped id, heli_weapons = carried (HELI_SLOTS), weapon_bay = stored at base
var weapon := "mg"
var heli_weapons: Array[String] = ["mg"]
var weapon_bay: Array[String] = []
# heli loadout: upgrades/wrecks/meta modify base_*; recompute() applies loadout on top
var base_seats := 0
var base_max_fuel := 75.0
var base_max_ammo := 140
var base_armor := 1.0
var loadout := {"seats": 4, "fuel_tank": 1, "ammo_feed": 1, "armor": 0}
var loadout_budget := 10
var weight_factor := 1.0 # max speed factor, -4 % per loadout point above 8
# base stock and workers (population = rescued)
var base_fuel := 400.0
var base_ammo := 800.0
var base_fuel_cap := 600.0
var base_ammo_cap := 1200.0
var workers := {"fuel": 0, "ammo": 0, "repair": 0, "militia": 0, "farm": 0, "build": 0, "medic": 0, "water": 0}
var sandbags := {} # Vector2i cell -> {"hp": float, "built": bool}; nodes live in base.gd
var base_food := 60.0
# base block 2 (docs/BASE.md): buildings, perimeter, water/medicine/rifles, injuries, power
# kind -> [name, scrap, build seconds, footprint cells]; "perimeter" costs scrap x next level and has no footprint
const BUILDINGS := {"barracks": ["Barracks", 40, 90.0, 2], "clinic": ["Field Clinic", 50, 90.0, 2], "generator": ["Generator", 60, 60.0, 1],
	"well": ["Well", 30, 60.0, 1], "watchtower": ["Watchtower", 35, 45.0, 1], "perimeter": ["Perimeter", 60, 60.0, 0]}
const BASE_RADIUS := 160.0
const PERIMETER_STEP := 60.0
const PERIMETER_MAX := 5
const WATER_PER_PERSON := 1.0 # per day, campers twice
const WELL_WATER := 8.0 # per well per day
const FIELD_FOOD := 0.5 # per FIELD tile in the perimeter per day
const GEN_FUEL := 10.0 # base fuel per generator per day
const HEAL_DAYS := 1.5 # per clinic bed, halved by a medic (one per 2 beds) and again by power
const UNTREATED_DEATH := 0.15 # per untreated injured per day
var buildings: Array = [] # {"kind", "cell": Vector2i top-left, "built": bool, "progress": seconds}; nodes live in base.gd
var base_radius := BASE_RADIUS
var base_water := 60.0
var base_medicine := 2.0
var base_rifles := 2.0 # float: the armory adds a fraction every frame
var injured := 0 # part of rescued: no work, not idle
var passengers_injured := 0 # part of passengers, join `injured` on delivery
var treating: Array[float] = [] # heal days left per occupied clinic bed
var power := false
var short_days := 0 # days in a row without food or water
var tutorial_wave := 0 # > 0: size of the next assault (tutorial), then back to normal
# noise: gunfire and the rotor draw zombies (Project Zomboid style)
var noise_pos := Vector2.ZERO
var noise_level := 0.0

# multipliers / flat stats changed by upgrades
var stats := {
	"damage": 1.0, "fire_rate": 1.0, "speed": 1.0, "fuel_eff": 1.0,
	"armor": 1.0, "pierce": 0, "shots": 1, "bullet_speed": 1.0, "xp_gain": 1.0, "range": 1.0,
}

var meta := {"total_rescued": 0, "runs": 0, "best_day": 0, "total_kills": 0, "art": "b",
	"vol_master": 100, "vol_sfx": 100, "vol_music": 70, "muted": 1, "tutorial_done": 0} # sound off by default for now; M or ESC menu turns it on
var radio_beep_ms := 0


func _ready() -> void:
	_setup_input()
	_load_meta()
	var art_env := OS.get_environment("ART") # dev override for screenshots, not saved
	Art.variant = art_env if art_env in ART_VARIANTS else meta["art"]


func new_run() -> void:
	seed = randi()
	hp = 100.0; max_hp = 100.0
	passengers = 0
	scrap = 0; xp = 0; level = 1
	day = 1; time = 0.25
	rescued = 0; kills = 0
	base_hp = 500.0; max_base_hp = 500.0
	attack_pending = false; attack_active = false
	base_level = {}
	for k in stats.keys():
		stats[k] = 1.0 if typeof(stats[k]) == TYPE_FLOAT else 0
	stats["shots"] = 1
	weapon = "mg"; heli_weapons = ["mg"]; weapon_bay = []
	base_seats = 0; base_max_fuel = 75.0; base_max_ammo = 140; base_armor = 1.0
	loadout = {"seats": 4, "fuel_tank": 1, "ammo_feed": 1, "armor": 0}; loadout_budget = 10
	base_fuel = 400.0; base_ammo = 800.0; base_fuel_cap = 600.0; base_ammo_cap = 1200.0
	workers = {"fuel": 0, "ammo": 0, "repair": 0, "militia": 0, "farm": 0, "build": 0, "medic": 0, "water": 0}
	sandbags = {}
	base_food = 60.0; noise_level = 0.0
	buildings = []; base_radius = BASE_RADIUS
	base_water = 60.0; base_medicine = 2.0; base_rifles = 2.0
	injured = 0; passengers_injured = 0; treating = []; power = false; short_days = 0; tutorial_wave = 0
	_apply_meta_bonus()
	recompute()
	fuel = max_fuel; ammo = max_ammo; hp = max_hp
	running = true


## Permanent bonuses from survivors rescued in earlier runs.
func _apply_meta_bonus() -> void:
	var r: int = meta["total_rescued"]
	base_seats += r / 25
	base_max_fuel += (r / 10) * 5.0
	base_max_ammo += (r / 10) * 20
	max_hp += (r / 20) * 10.0


## Derive seats/max_fuel/max_ammo/armor/weight from base values + loadout + equipped weapon.
func recompute() -> void:
	seats = base_seats + loadout["seats"]
	max_fuel = base_max_fuel + 25.0 * loadout["fuel_tank"]
	max_ammo = base_max_ammo + 60 * loadout["ammo_feed"] + Weapons.TABLE[weapon]["max_ammo_bonus"]
	stats["armor"] = base_armor * (1.0 + 0.15 * loadout["armor"])
	weight_factor = 1.0 - 0.04 * maxi(0, loadout_points() - 8)
	fuel = minf(fuel, max_fuel)
	ammo = mini(ammo, max_ammo)


func loadout_points() -> int:
	var p := 0
	for k in LOADOUT_COST:
		p += LOADOUT_COST[k] * loadout[k]
	return p


## Housed, healthy people without a job (campers and the injured do not work).
func idle_workers() -> int:
	var n: int = mini(rescued - injured, housing())
	for k in workers:
		n -= workers[k]
	return n


## 4 beds per built barracks + 2 in the hangar.
func housing() -> int:
	return 4 * built("barracks") + 2


func campers() -> int:
	return maxi(0, rescued - housing())


func built(kind: String) -> int:
	return buildings.filter(func(b): return b["kind"] == kind and b["built"]).size()


## Healthy people get hurt; their jobs are freed.
func injure(n: int) -> void:
	injured += clampi(n, 0, rescued - injured)
	_fit_workers()


## Someone leaves or dies (an injured one if `was_injured`).
func lose_person(was_injured := false) -> void:
	if rescued <= 0:
		return
	rescued -= 1
	injured = clampi(injured - (1 if was_injured else 0), 0, rescued)
	if treating.size() > injured:
		treating.resize(injured)
	_fit_workers()


func _fit_workers() -> void:
	var over := -idle_workers()
	for k in workers:
		var cut := mini(over, workers[k])
		if cut > 0:
			workers[k] -= cut
			over -= cut


## Q key: next carried weapon.
func cycle_weapon() -> void:
	if heli_weapons.size() < 2:
		return
	weapon = heli_weapons[(heli_weapons.find(weapon) + 1) % heli_weapons.size()]
	recompute()
	radio("Gunner: switching to %s." % Weapons.TABLE[weapon]["name"])


## Found weapon: heli slot if free (auto-equip when still on the stock MG), else the base bay.
func add_weapon(id: String) -> void:
	var n: String = Weapons.TABLE[id]["name"]
	if heli_weapons.size() >= HELI_SLOTS:
		weapon_bay.append(id)
		radio("Gunner: found a %s, stowed in the bay, swap at base." % n)
		return
	heli_weapons.append(id)
	if weapon == "mg":
		weapon = id
		recompute()
		radio("Gunner: %s mounted on the door. Q switches guns." % n)
	else:
		radio("Gunner: %s stowed aboard. Q switches guns." % n)


func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	var d := delta / DAY_SECONDS
	base_fuel = minf(base_fuel_cap, base_fuel + workers["fuel"] * WORKER_RATE["fuel"] * d)
	base_ammo = minf(base_ammo_cap, base_ammo + workers["ammo"] * WORKER_RATE["ammo"] * d)
	base_hp = minf(max_base_hp, base_hp + workers["repair"] * WORKER_RATE["repair"] * d)
	var eaters: int = rescued + campers() # campers eat and drink double
	base_food = maxf(0.0, base_food + (workers["farm"] * WORKER_RATE["farm"] - eaters * FOOD_PER_PERSON) * d)
	base_water = maxf(0.0, base_water + (workers["water"] * WORKER_RATE["water"] + built("well") * WELL_WATER - eaters * WATER_PER_PERSON) * d)
	base_rifles += base_level.get("armory", 0) * d
	var burn: float = built("generator") * GEN_FUEL * d
	power = burn > 0.0 and base_fuel > 0.0
	base_fuel = maxf(0.0, base_fuel - burn)
	_treat(d)
	noise_level = maxf(0.0, noise_level - delta * 0.35)
	time += d
	if time >= 1.0:
		time -= 1.0
		day += 1
		day_changed.emit(day)
		if world and world.base:
			base_food += FIELD_FOOD * world.base.field_tiles()
		for i in maxi(0, injured - treating.size()): # yesterday's untreated, before anyone new gets hurt
			if randf() < UNTREATED_DEATH:
				lose_person(true)
				radio("Base: an injured survivor died without care.")
		if (base_food <= 0.0 or base_water <= 0.0) and rescued > 0:
			short_days += 1
			injure(1)
			radio("Base: out of %s. One of the survivors fell sick." % ("food" if base_food <= 0.0 else "water"))
			if short_days >= 3:
				lose_person()
				radio("Base: three days without supplies. Someone walked out in the night.")
		else:
			short_days = 0
			if base_food < eaters * FOOD_PER_PERSON * 2.0:
				radio("Base: food is running low, %d rations left." % int(base_food))
			if base_water < eaters * WATER_PER_PERSON * 2.0:
				radio("Base: water is running low, %d days' worth left." % int(base_water / maxf(1.0, eaters)))
		if injured > 0:
			radio("%d injured, %d medicine left" % [injured, int(base_medicine)])
		if day % ATTACK_EVERY_DAYS == 0:
			attack_pending = true
			radio("Intel: a horde is massing. Expect an assault on the base tonight.")
	if attack_pending and time >= 0.8:
		attack_pending = false
		attack_active = true
		if campers() > 0:
			injure(1)
			radio("Base: a camper outside the wire got mauled. Build barracks.")
		base_attack_started.emit(day)
		radio("ALERT: base under attack! Return and defend!")


## Field clinic: 2 beds per clinic, a patient takes a bed for 1 medicine, then heals in HEAL_DAYS
## (x2 speed with a medic for that bed pair, x2 again with power). `d` is the fraction of a day.
func _treat(d: float) -> void:
	while treating.size() < mini(2 * built("clinic"), injured) and base_medicine >= 1.0:
		base_medicine -= 1.0
		treating.append(HEAL_DAYS)
	for i in range(treating.size() - 1, -1, -1):
		treating[i] -= d * (2.0 if i < 2 * workers["medic"] else 1.0) * (2.0 if power else 1.0)
		if treating[i] <= 0.0:
			treating.remove_at(i)
			injured -= 1
			radio("Clinic: patient recovered.")


## Louder noise wins; zombies within 200 + 500 * level px investigate.
func make_noise(pos: Vector2, amount: float) -> void:
	if amount >= noise_level:
		noise_pos = pos
		noise_level = amount


func is_night() -> bool:
	return time > 0.8 or time < 0.2


## 0 = full daylight, 1 = darkest night.
func darkness() -> float:
	if time < 0.2:
		return 1.0 - time / 0.2
	if time > 0.8:
		return (time - 0.8) / 0.2
	return 0.0


## Threat scaling by distance from base and day count.
func danger_at(pos: Vector2) -> float:
	return 1.0 + pos.length() / 1500.0 + (day - 1) * 0.15


func add_xp(amount: int) -> void:
	xp += int(amount * stats["xp_gain"])
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		level_up.emit(level)


func xp_needed() -> int:
	return int(25.0 * pow(level, 1.4)) # grows faster than linear: 25, 66, 117, 174, 238 ... 627 at level 10


func radio(msg: String) -> void:
	if Time.get_ticks_msec() >= radio_beep_ms: radio_beep_ms = Time.get_ticks_msec() + 500; Sfx.play("radio", null, -8.0)
	radio_message.emit(msg)


func end_run(reason: String) -> void:
	if not running:
		return
	running = false
	meta["runs"] += 1
	meta["total_rescued"] += rescued
	meta["total_kills"] += kills
	meta["best_day"] = max(meta["best_day"], day)
	_save_meta()
	run_ended.emit(reason)


func _load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in meta.keys():
			if data.has(k):
				meta[k] = str(data[k]) if meta[k] is String else int(data[k])
	if not meta["art"] in ART_VARIANTS:
		meta["art"] = "b"
	meta["muted"] = 1 # always start silent for now, whatever was saved; M / ESC menu turns sound on for the session


func _save_meta() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))


func _setup_input() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"land": [KEY_SPACE], "interact": [KEY_E], "restart": [KEY_R], "weapon_swap": [KEY_Q], "menu": [KEY_ESCAPE],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)
