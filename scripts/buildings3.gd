class_name Buildings3
extends Node
## Four late-game buildings, the scrap sink (docs/ROADMAP3.md S1). Same pattern as buildings2.gd: plain Game.buildings entries (game_state.gd
## BUILDINGS), placed, built by Build workers and saved like the others; this file holds what they do. main.gd keeps the node as
## `buildings3` (it runs the Flak, pays the upkeep and saves itself, hook "buildings3"). Everything else is static, read where it applies.
## Placeable from day UNLOCK_DAY or with UNLOCK_PERIMETER built perimeter stages (refusal(), the build bar hides them before).
##   fortress  Fortress Wall (one): sandbags become walls, WALL_HP x hit points (the pieces standing and every new one).
##   flak      Flak Emplacement (FLAK_MAX): every FLAK_CD s, for FLAK_AMMO base ammo, it shoots down one rocket (RPG, gunship) in FLAK_RANGE,
##             else hits a gunship for FLAK_AIR_DMG, else bursts on the thickest part of a wave of FLAK_WAVE_MIN or more (FLAK_SPLASH_DMG
##             within FLAK_SPLASH). Upkeep FLAK_UPKEEP scrap a day.
##   command   Command Post (one): missions pay REWARD_FACTOR x scrap and XP, MISSION_SLOTS more may be open (missions.gd), and rival attacks
##             (the Warlord's gunship, the Alpha's assault) are radioed COMMAND_WARN of a day before (nemesis.gd). Upkeep COMMAND_UPKEEP a day.
##   vault     Supply Vault (one): the fuel and ammo stores hold VAULT_CAPS x more (once, when it is finished), a base breach
##             (buildings2.gd shelter) costs VAULT_BREACH as many injured and morale.
## Upkeep (UPKEEP, scrap a day per building, paid at dawn): short of scrap the building idles until the next dawn that finds it paid.

const KINDS := ["fortress", "flak", "command", "vault"]
const UNLOCK_DAY := 20
const UNLOCK_PERIMETER := 2
const WALL_HP := 2.0
const FLAK_MAX := 2
const FLAK_RANGE := 340.0
const FLAK_CD := 0.8
const FLAK_AMMO := 3.0 # base ammo per shot
const FLAK_AIR_DMG := 50.0 # a gunship has about 650 hp
const FLAK_WAVE_MIN := 6
const FLAK_SPLASH := 48.0
const FLAK_SPLASH_DMG := 16.0
const REWARD_FACTOR := 1.25
const MISSION_SLOTS := 1
const COMMAND_WARN := 0.12 # of a day before the attack
const VAULT_CAPS := 1.5
const VAULT_BREACH := 0.5
const UPKEEP := {"flak": 12, "command": 8}
const TIPS := {
	"fortress": "Fortress Wall (one): sandbags become walls with double hit points, the ones standing and every new one. Unlocks on day 20 or at perimeter level 2.",
	"flak": "Flak Emplacement (two at most): shoots down RPG and gunship rockets, hurts the gunship and bursts on big waves. 3 ammo a shot, 12 scrap upkeep a day.",
	"command": "Command Post (one): missions pay +25 %, one more mission open at a time, rival attacks are radioed ahead. 8 scrap upkeep a day.",
	"vault": "Supply Vault (one): fuel and ammo stores hold 50 % more, and a base breach costs half as much. No upkeep.",
}

var unpaid := {} # kind -> true: not paid at the last dawn, idle
var warned := {} # rival kind -> day it was radioed ahead
var cd := 0.0
var shots := 0 # tests


func _ready() -> void:
	Save.register("buildings3", save_state, load_state)
	Game.day_changed.connect(pay_upkeep)


func _process(delta: float) -> void:
	if not Game.running or get_tree().paused or not Game.base_founded or not active("flak"):
		return
	cd -= delta
	if cd > 0.0:
		return
	cd = FLAK_CD
	for b in Game.buildings.filter(func(b): return b["kind"] == "flak" and b["built"]):
		var node: Node2D = Game.world.base.site_nodes.get(b["cell"])
		if node and Game.base_ammo >= FLAK_AMMO and fire(node.global_position):
			Game.base_ammo -= FLAK_AMMO
			shots += 1


## One flak shot from `from`: false if nothing is in reach.
func fire(from: Vector2) -> bool:
	var r2 := FLAK_RANGE * FLAK_RANGE
	for rk in get_tree().get_nodes_in_group("rockets"):
		if not rk.is_queued_for_deletion() and rk.global_position.distance_squared_to(from) < r2:
			_burst(from, rk.global_position, 0.6)
			rk.queue_free()
			return true
	var foes: Array = get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.is_queued_for_deletion() and e.global_position.distance_squared_to(from) < r2)
	for e in foes:
		if e.get("kind") == "gunship":
			_burst(from, e.global_position, 0.5)
			e.hit(FLAK_AIR_DMG, (e.global_position - from).normalized())
			return true
	var ground: Array = foes.filter(func(e): return e.get("kind") != "gunship")
	if ground.size() < FLAK_WAVE_MIN:
		return false
	var best: Node2D
	var best_n := 0
	for e in ground:
		var n := ground.filter(func(o): return o.global_position.distance_squared_to(e.global_position) < FLAK_SPLASH * FLAK_SPLASH).size()
		if n > best_n:
			best_n = n
			best = e
	var at := best.global_position
	_burst(from, at, 0.8)
	for e in ground.filter(func(o): return o.global_position.distance_squared_to(at) < FLAK_SPLASH * FLAK_SPLASH):
		e.hit(FLAK_SPLASH_DMG, (e.global_position - at).normalized())
	return true


func _burst(from: Vector2, at: Vector2, size: float) -> void:
	Game.world.spawn_fx(at, size)
	Sfx.play("explosion", at, -8.0)
	var t := Line2D.new() # tracer, gone in a moment
	t.points = [from, at]
	t.width = 1.5
	t.default_color = Color(1.0, 0.85, 0.4, 0.8)
	t.z_index = 9
	Game.world.add_child(t)
	get_tree().create_timer(0.1).timeout.connect(t.queue_free)


## Dawn: each building with an upkeep is paid for or goes idle.
func pay_upkeep(_day := 0) -> void:
	if not Game.base_founded:
		return
	for kind in UPKEEP:
		var due: int = Game.built(kind) * UPKEEP[kind]
		if due == 0:
			unpaid.erase(kind)
		elif Game.scrap >= due:
			Game.scrap -= due
			unpaid.erase(kind)
		elif not unpaid.has(kind):
			unpaid[kind] = true
			Game.radio("Base: no scrap for the %s upkeep (%d a day), it stands idle until it is paid." % [Game.BUILDINGS[kind][0], due])
		else:
			unpaid[kind] = true


## Built and paid for.
static func active(kind: String) -> bool:
	return Game.built(kind) > 0 and not Game.world.buildings3.unpaid.has(kind)


## Placeable from day UNLOCK_DAY or with UNLOCK_PERIMETER perimeter stages built (the build bar shows the tools then).
static func unlocked() -> bool:
	return Game.day >= UNLOCK_DAY or Game.built("perimeter") >= UNLOCK_PERIMETER


## Why `kind` cannot be placed right now, "" if it can (Buildings2.refusal passes the late kinds here).
static func refusal(kind: String) -> String:
	if not kind in KINDS:
		return ""
	if not unlocked():
		return "unlocks on day %d or at perimeter level %d" % [UNLOCK_DAY, UNLOCK_PERIMETER]
	var have: int = Game.buildings.filter(func(b): return b["kind"] == kind).size()
	if have >= (FLAK_MAX if kind == "flak" else 1):
		return "one is enough" if kind != "flak" else "%d are enough" % FLAK_MAX
	return ""


## A late building was just finished (base.gd _finish_site).
static func on_built(kind: String) -> void:
	if kind == "vault":
		Game.base_fuel_cap *= VAULT_CAPS
		Game.base_ammo_cap *= VAULT_CAPS
	elif kind == "fortress":
		var base: Node = Game.world.base
		for cell in Game.sandbags:
			if Game.sandbags[cell]["kind"] == "sandbag":
				Game.sandbags[cell]["hp"] *= WALL_HP
				base.bags[cell].self_modulate = WALL_TINT


const WALL_TINT := Color(0.72, 0.74, 0.82)


## Factor on sandbag hit points (and the tint of a wall piece).
static func wall_factor() -> float:
	return WALL_HP if Game.built("fortress") > 0 else 1.0


## Mission rewards (missions.gd _reward) and the missions that may be open at once.
static func reward_factor() -> float:
	return REWARD_FACTOR if active("command") else 1.0


static func extra_missions() -> int:
	return MISSION_SLOTS if active("command") else 0


## Factor on what a base breach costs (buildings2.gd shelter).
static func breach_factor() -> float:
	return VAULT_BREACH if Game.built("vault") > 0 else 1.0


## Radio ahead of a rival attack on `day` at time of day `at` (nemesis.gd): once, when the Command Post is up. True if it spoke.
func radio_ahead(rival: String, day: int, at: float, text: String) -> bool:
	if not active("command") or Game.day != day or Game.time < at - COMMAND_WARN or warned.get(rival, -1) == day:
		return false
	warned[rival] = day
	Game.radio(text)
	return true


func save_state() -> Dictionary:
	return {"unpaid": unpaid.keys(), "warned": warned}


func load_state(d: Dictionary) -> void:
	unpaid = {}
	for k in d.get("unpaid", []):
		unpaid[k] = true
	warned = d.get("warned", {})
