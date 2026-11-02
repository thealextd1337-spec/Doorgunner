class_name Bosses
extends Node
## The new bosses (docs/ROADMAP2.md Q12). main.gd keeps this node as `bosses`; it saves itself (hook "bosses"). The old blood-moon
## "boss" stays as it is. enemy.gd KINDS rows with a "boss_id" are ours; enemy.gd calls `tick` once a frame (before the other goals),
## `armor_mult` in `hit` and `on_death` in `_die`, bandit.gd does the same for the Warlord. Per-boss state lives in `e.state` (saved with the
## enemy); `state["nemesis_id"]` is empty until Q15 gives a boss a name. Every dangerous attack is telegraphed: a ring or lane drawn on the
## boss (BossFx), a roar or warning sound and a radio line. At PHASE_AT of its HP every boss gets a new pattern.
##   Matriarch  roams from day 6. Every few seconds she rears up (BROOD_WIND s, green ring) and spawns a brood of runners and
##              crawlers. At half HP she screeches, drops a bigger brood and flees for FLEE_TIME s healing, then returns faster, with more.
##   Juggernaut roams from day 10. Plated all round (JUG_ARMOR less damage, splash half as effective) except the red fuel pack on its back
##              (shots from behind do full damage). It turns slowly, so fly round it. Charges: stops and lowers its head (JUG_WIND s, the
##              lane shows red), then rams along the lane, ruining houses and sandbags, hurting a landed heli or the base; a crash or a hit
##              leaves it dazed for JUG_DAZE s. At half HP the plates come off (less armour), it is faster and charges twice in a row.
##   Hive       sits in a power plant or stadium (HIVE_KINDS) from day 8, in about 60 % of them. While the heli is within
##              HIVE_ACTIVE it calls a wave every HIVE_CD s (HIVE_WIND s of throbbing first); at half HP the waves come faster and bring
##              spitters, bloaters and armoured brutes. A destroyed Hive stays destroyed.
##   Warlord    a bandit (bandit.gd KINDS) who holds one of the big camps (WARLORD_KINDS, far enough out, from day 10): the camp's
##              garrison gets a "warlord" entry. Bodyguards stand around him; while the heli is LANDED within MORTAR_RANGE his mortar
##              fires: a red circle on the heli's spot, a whistle, impact after MORTAR_FUSE s: lift off in time and it misses. At half HP
##              the shells come three at a time and more bodyguards arrive. His death scatters the bodyguards.
## Where and when (days, odds) is SpawnTable.BOSS_ROWS. Roaming bosses are decided by a day roll (_on_day) and appear near the heli; at most
## one of each, never within ROAM_GAP days of the last.

signal defeated(id: String, nemesis_id: String)

const PHASE_AT := 0.5 # share of max HP at which the second phase begins
const SEE_DIST := 700.0 # px at which the codex page is logged
const SCAN_EVERY := 1.5 # s
# Matriarch
const BROOD_WIND := 1.6
const BROOD_CD := [14.0, 9.0] # per phase
const BROOD_SIZE := [3, 5]
const BROOD_FIRST := 4.0
const BROOD_SIGHT := 700.0
const BROOD_CAP := 14 # enemies within 450 px: no new brood above it
const HUNT_DIST := 600.0 # she walks towards the heli within this
const FLEE_TIME := 12.0
const FLEE_SPEED := 2.4
const FLEE_HEAL := 0.12 # share of max HP regained while away
# Juggernaut
const JUG_ARMOR := [0.8, 0.6] # share of damage stopped, per phase
const JUG_SPLASH_ARMOR := 0.5 # splash gets this much of the armour
const JUG_REAR_DOT := 0.5 # a shot flying along its facing with at least this cosine hits the back
const JUG_TURN := 1.1 # rad/s: slow, so a fast heli gets behind it
const JUG_AIM_TOL := 0.35
const JUG_WIND := 1.6
const JUG_WIND2 := 0.9
const JUG_CHARGE_RANGE := 340.0
const JUG_CHARGE_MIN := 90.0
const JUG_CHARGE_SPEED := 190.0
const JUG_CHARGE_TIME := 1.4
const JUG_CD := [6.0, 3.5]
const JUG_DAZE := 2.6
const JUG_WINDED := 1.2 # a charge that hit nothing
const JUG_BASE_SIGHT := 1000.0 # it goes for the base within this, but only while the heli is within this of the base too
const JUG_HELI_MULT := 0.6 # of its damage on a landed heli
const JUG_SAND := 30.0 # sandbag damage per frame of ramming
const JUG_CHAIN := 2 # charges in a row in phase 2
# Hive
const HIVE_KINDS := ["power_plant", "stadium"]
const HIVE_WAKE := 800.0 # px from the site at which it is placed
const HIVE_ACTIVE := 1000.0
const HIVE_CD := [26.0, 16.0]
const HIVE_WIND := 2.5
const HIVE_WAVE := [8, 10]
const HIVE_SPECIAL := ["spitter", "bloater", "brute_armored"] # phase 2 adds one of each per wave
const HIVE_CAP := 40 # enemies within 700 px: the wave waits
const HIVE_FIRST := 6.0
const HIVE_BASE_MIN := 1500.0 # px from the base (the start before founding): no Hive closer
# Warlord
const WARLORD_KINDS := ["prison", "quarry", "harbour"]
const WARLORD_MIN_DIST := 2000.0 # px from the start
const WARLORD_MAX := 2 # camps with a living warlord at once
const BODY_N := 3
const BODY_P2 := ["rifle", "rifle", "rpg"] # arrive at half HP
const BODY_REFILL := 25.0 # s between replacements
const BODY_REFILLS := 4
const MORTAR_RANGE := 650.0
const MORTAR_FUSE := 2.4
const MORTAR_CD := [10.0, 6.5]
const MORTAR_FIRST := 3.0
const MORTAR_RADIUS := 46.0
const MORTAR_DMG := 24.0
const MORTAR_SPREAD := 70.0
# Rewards: boss kills counted (item unlocks: progression.gd META_KEYS "bosses"), morale, salvage {metal, parts, electronics}, scrap, rifles.
# "Key part" = what the base is short of: parts and electronics (workshop, radio station, evacuation).
const REWARDS := {
	"matriarch": {"kills": 2, "morale": 10.0, "scrap": 60, "salvage": {"parts": 6.0}, "rifles": 0},
	"juggernaut": {"kills": 2, "morale": 6.0, "scrap": 40, "salvage": {"metal": 40.0, "parts": 10.0}, "rifles": 2},
	"hive": {"kills": 3, "morale": 12.0, "scrap": 80, "salvage": {"electronics": 15.0, "parts": 5.0}, "rifles": 0},
	"warlord": {"kills": 3, "morale": 12.0, "scrap": 100, "salvage": {"electronics": 8.0}, "rifles": 4},
}
const NAMES := {"matriarch": "The Matriarch", "juggernaut": "The Juggernaut", "hive": "The Hive", "warlord": "The Warlord"}
const ROAM_GAP := 3 # days between two roaming bosses
const ROAM_DIST := Vector2(650.0, 950.0) # px from the heli
const ROAM_BASE_MIN := 700.0 # px from the FOB
const T := preload("res://scripts/chunk_manager.gd").T
const Poi := preload("res://scripts/poi.gd")

static var _said := {} # radio key -> msec, so a line is not repeated every few seconds
static var _escorts := {} # warlord instance id -> its bodyguards (runtime)

var records := {} # "hive:<site>" / "warlord:<camp>" -> {hp, phase, nemesis_id} while alive, {dead: true} after
var pending := [] # roaming kinds rolled for, waiting for the next scan
var last_roam := -100
var _scan := 0.0


func _ready() -> void:
	Save.register("bosses", save_state, load_state)
	Game.day_changed.connect(_on_day)


func _process(delta: float) -> void:
	if not Game.running or get_tree().paused or Game.heli == null:
		return
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_EVERY
	scan()


func scan() -> void:
	var heli: Vector2 = Game.heli.global_position
	for e in _alive():
		var id: String = e.cfg["boss_id"]
		if e.global_position.distance_to(heli) < SEE_DIST and Codex.unlock(codex_id(id)):
			Game.radio("Codex: %s logged." % NAMES[id])
		var key := _key(e)
		if key != "":
			records[key] = {"hp": e.hp, "phase": e.state.get("phase", 1), "nemesis_id": e.state.get("nemesis_id", "")}
	for s in Game.world.chunks.sites_near(heli, HIVE_WAKE):
		if s.kind in HIVE_KINDS and Game.day >= SpawnTable.BOSS_ROWS["hive"]["min_day"] and wants_hive(s) and not _has_hive(s.uid):
			spawn_hive(s)
	for c in Game.world.bandits.camps.values():
		_assign_warlord(c)
	while not pending.is_empty():
		spawn_roamer(pending.pop_front())


## All living bosses (enemy.gd and bandit.gd nodes with a "boss_id").
func _alive() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get("cfg") != null and e.cfg.has("boss_id") and not e.is_queued_for_deletion())


static func _key(e: Node2D) -> String:
	match e.cfg["boss_id"]:
		"hive":
			return "hive:" + str(e.state.get("site", ""))
		"warlord":
			return "warlord:" + e.camp_uid
	return ""


func _on_day(day: int) -> void:
	if day - last_roam < ROAM_GAP:
		return
	for kind in SpawnTable.ROAMERS:
		var row: Dictionary = SpawnTable.BOSS_ROWS[kind]
		if day >= row["min_day"] and randf() < row["chance"] and not kind in pending and not _alive().any(func(e): return e.cfg["boss_id"] == kind):
			pending.append(kind)
			last_roam = day
			return


## A roaming boss (matriarch, juggernaut) 650-950 px from the heli, away from the base. Null if no open ground was found.
func spawn_roamer(kind: String) -> Node2D:
	var heli: Vector2 = Game.heli.global_position
	for i in 24:
		var p := heli + Vector2(randf_range(ROAM_DIST.x, ROAM_DIST.y), 0).rotated(randf() * TAU)
		if Game.world.is_walkable(p) and not (Game.base_founded and p.distance_to(Game.world.base.global_position) < ROAM_BASE_MIN):
			var e: Node2D = Game.world.spawn_enemy(kind, p)
			Game.radio("Gunner: something huge is moving %s. %s. Keep your distance." % [Poi.where(heli, p), NAMES[kind]])
			return e
	return null


## Does the Hive sit in site `s` ({kind, pos, uid})? A fixed roll per site, none once destroyed.
func wants_hive(s: Dictionary) -> bool:
	var home: Vector2 = Game.world.base.global_position if Game.base_founded else Vector2.ZERO
	return not records.get("hive:" + s.uid, {}).get("dead", false) and s.pos.distance_to(home) >= HIVE_BASE_MIN and hash([Game.seed, s.uid, "hive"]) % 100 < SpawnTable.BOSS_ROWS["hive"]["pct"]


func _has_hive(uid: String) -> bool:
	return _alive().any(func(e): return e.cfg["boss_id"] == "hive" and e.state.get("site", "") == uid)


func spawn_hive(s: Dictionary) -> Node2D:
	var e: Node2D = Game.world.spawn_enemy("hive", s.pos)
	var rec: Dictionary = records.get("hive:" + s.uid, {})
	e.state.merge({"site": s.uid, "home": s.pos, "phase": rec.get("phase", 1), "nemesis_id": rec.get("nemesis_id", "")})
	if rec.has("hp"):
		e.hp = minf(e.max_hp, rec["hp"])
	_say("hive_seen", "Gunner: the %s is crawling... no. There is something alive in there. A Hive. It calls them." % s.kind.replace("_", " "))
	return e


func _assign_warlord(c: Dictionary) -> void:
	if c.has("warlord") or c["cleared"] or Game.day < SpawnTable.BOSS_ROWS["warlord"]["min_day"]:
		return
	var held: int = Game.world.bandits.camps.values().filter(func(o): return o["garrison"].get("warlord", 0) > 0 and not o["cleared"]).size() # living ones
	c["warlord"] = c["kind"] in WARLORD_KINDS and c["pos"].length() >= WARLORD_MIN_DIST and held < WARLORD_MAX and hash([Game.seed, c["uid"], "warlord"]) % 100 < SpawnTable.BOSS_ROWS["warlord"]["pct"]
	if c["warlord"] and not records.get("warlord:" + c["uid"], {}).get("dead", false):
		c["garrison"]["warlord"] = 1
	else:
		c["warlord"] = false


## Codex id of a boss (rows in codex_content.gd): bandit bosses b_, infected z_, like onboarding.gd's enemy ids.
static func codex_id(id: String) -> String:
	return ("b_" if id == "warlord" else "z_") + id


## Radio line at most once a minute per key.
static func _say(key: String, msg: String) -> void:
	if Time.get_ticks_msec() - _said.get(key, -100000) > 60000:
		_said[key] = Time.get_ticks_msec()
		Game.radio(msg)


## One frame of a boss. True = it moved or stood still on purpose: skip the normal goals. enemy.gd and bandit.gd call it.
static func tick(e: Node2D, delta: float) -> bool:
	var id: String = e.cfg.get("boss_id", "")
	if id == "":
		return false
	if "kick" in e:
		e.kick = Vector2.ZERO # bosses are not shoved
	var s: Dictionary = e.state
	match id:
		"matriarch":
			return _matriarch(e, s, delta)
		"juggernaut":
			return _juggernaut(e, s, delta)
		"hive":
			return _hive(e, s, delta)
		"warlord":
			return _warlord(e, s, delta)
	return false


## Damage factor of a shot flying along `dir` (zero: splash). Only the Juggernaut is armoured.
static func armor_mult(e: Node2D, dir: Vector2) -> float:
	if e.cfg.get("boss_id", "") != "juggernaut":
		return 1.0
	var armor: float = JUG_ARMOR[1 if e.state.get("phase", 1) == 2 else 0]
	if dir == Vector2.ZERO:
		return 1.0 - armor * JUG_SPLASH_ARMOR
	if dir.dot(Vector2.UP.rotated(e.rotation)) > JUG_REAR_DOT:
		return 1.0 # the fuel pack
	return 1.0 - armor


## Rewards, called when a boss dies (enemy.gd _die, bandit.gd _die).
static func on_death(e: Node2D) -> void:
	var id: String = e.cfg.get("boss_id", "")
	if id == "":
		return
	var r: Dictionary = REWARDS[id]
	var m: Node = Game.world.bosses
	Game.meta["boss_kills"] += r["kills"] - int(e.cfg.get("boss", false)) # enemy.gd counts its own one
	Game.scrap += r["scrap"]
	for k in r["salvage"]:
		Game.salvage[k] += r["salvage"][k]
	Game.base_rifles += r["rifles"]
	Game.world.morale.add(r["morale"], NAMES[id].to_lower() + " down")
	Game.radio("Gunner: %s is down! %s" % [NAMES[id], _loot_text(r)])
	Codex.unlock(codex_id(id))
	var key := _key(e)
	if key != "":
		m.records[key] = {"dead": true}
	if id == "warlord":
		e.set_meta("dead", true)
	m.defeated.emit(id, e.state.get("nemesis_id", ""))


static func _loot_text(r: Dictionary) -> String:
	var parts := ["%d scrap" % r["scrap"]]
	for k in r["salvage"]:
		parts.append("%d %s" % [r["salvage"][k], k])
	if r["rifles"] > 0:
		parts.append("%d rifles" % r["rifles"])
	return "Loot: %s. Morale up. (+%d boss kills)" % [", ".join(parts), r["kills"]]


## The BossFx child of `e`: hp bar, telegraph ring or lane, the Juggernaut's weak spot. Made on the first frame and after a load.
static func _fx(e: Node2D) -> Node2D:
	var fx: Node2D = e.get_node_or_null("BossFx")
	if fx == null:
		fx = BossFx.new()
		fx.name = "BossFx"
		fx.weak = e.cfg["boss_id"] == "juggernaut"
		e.add_child(fx)
	return fx


static func _pulse(e: Node2D, p: float, col: Color) -> void:
	e.sprite.scale = Vector2.ONE * Art.SCALE * (1.0 + 0.1 * sin(p * 40.0))
	e.sprite.modulate = Color(col, e.sprite.modulate.a)


static func _calm(e: Node2D, fx: Node2D) -> void:
	fx.p = -1.0
	fx.lane = Vector2.ZERO
	e.sprite.scale = Vector2.ONE * Art.SCALE
	e.sprite.modulate = Color(1, 1, 1, e.sprite.modulate.a)


# ---------------------------------------------------------------- Matriarch

static func _matriarch(e: Node2D, s: Dictionary, delta: float) -> bool:
	var fx := _fx(e)
	var heli: Node2D = Game.heli
	var to: Vector2 = heli.global_position - e.global_position
	if not s.has("phase"):
		s.merge({"phase": 1, "mode": "stalk", "cd": BROOD_FIRST, "wind": 0.0, "flee": 0.0, "nemesis_id": ""})
	if s["phase"] == 1 and e.hp <= e.max_hp * PHASE_AT:
		s.merge({"phase": 2, "mode": "flee", "flee": FLEE_TIME, "wind": 0.0, "cd": BROOD_CD[1]}, true)
		_calm(e, fx)
		Sfx.play("boss_roar", e.global_position, -2.0)
		_brood(e, BROOD_SIZE[1])
		Game.radio("Gunner: the Matriarch is hurt and running! She will heal and come back with more.")
	if s["mode"] == "flee":
		s["flee"] -= delta
		e.hp = minf(e.max_hp, e.hp + e.max_hp * FLEE_HEAL * delta / FLEE_TIME)
		e._face(-to)
		e._step(-to, delta, FLEE_SPEED)
		if s["flee"] <= 0.0:
			s["mode"] = "stalk"
			Sfx.play("boss_roar", e.global_position, -4.0)
			Game.radio("Gunner: the Matriarch is back, and she is angry!")
		return true
	var phase: int = s["phase"]
	if s["wind"] > 0.0: # rearing up: the telegraph
		s["wind"] -= delta
		fx.p = 1.0 - s["wind"] / BROOD_WIND
		_pulse(e, fx.p, Color(0.8, 1.0, 0.55))
		if s["wind"] <= 0.0:
			s["wind"] = 0.0
			_calm(e, fx)
			_brood(e, BROOD_SIZE[phase - 1])
			s["cd"] = BROOD_CD[phase - 1]
		return true
	s["cd"] -= delta
	if s["cd"] <= 0.0 and to.length() < BROOD_SIGHT:
		s["wind"] = BROOD_WIND
		Sfx.play("boss_roar", e.global_position, -8.0)
		_say("matriarch_wind", "Gunner: she is rearing up, she is calling a brood!")
		return true
	if to.length() < HUNT_DIST and not e.target_base:
		var strike: Callable = heli.take_damage if heli.landed else func(_d): pass
		e._approach(delta, heli, e.radius + heli.RADIUS + 4.0, strike)
		return true
	return false


static func _brood(e: Node2D, n: int) -> void:
	var near := 0
	for o in e.get_tree().get_nodes_in_group("enemies"):
		near += int(o.global_position.distance_squared_to(e.global_position) < 450.0 * 450.0)
	if near > BROOD_CAP:
		return
	for i in n:
		var p: Vector2 = e.global_position + Vector2(26.0, 0).rotated(randf() * TAU)
		Game.world.spawn_enemy("runner" if i % 2 == 0 else "crawler", p if Game.world.is_walkable(p) else e.global_position, e.target_base)


# ---------------------------------------------------------------- Juggernaut

static func _juggernaut(e: Node2D, s: Dictionary, delta: float) -> bool:
	var fx := _fx(e)
	var heli: Node2D = Game.heli
	var base: Node2D = Game.world.base
	if not s.has("phase"):
		s.merge({"phase": 1, "mode": "walk", "t": 0.0, "w0": JUG_WIND, "cd": JUG_CD[0] * 0.5, "dir": Vector2.ZERO, "chain": 0, "hit": false, "nemesis_id": ""})
	if s["phase"] == 1 and e.hp <= e.max_hp * PHASE_AT:
		s.merge({"phase": 2, "chain": JUG_CHAIN - 1}, true)
		Sfx.play("boss_roar", e.global_position, -2.0)
		Game.radio("Gunner: the Juggernaut's plates are coming off! It is faster now, and it charges twice.")
	var p2: bool = s["phase"] == 2
	var at_base: bool = Game.base_founded and heli.global_position.distance_to(base.global_position) < JUG_BASE_SIGHT # never while the player is away
	var target: Node2D = base if at_base and e.global_position.distance_to(base.global_position) < JUG_BASE_SIGHT else heli
	var to: Vector2 = target.global_position - e.global_position
	match s["mode"]:
		"walk":
			if p2: # plates off: a reddish tint (a hit flash resets it)
				e.sprite.modulate = Color(1.0, 0.8, 0.75, e.sprite.modulate.a)
			e.rotation = rotate_toward(e.rotation, to.angle() + PI / 2, JUG_TURN * delta)
			Game.world.nav_move(e, target.global_position, e.speed * (1.3 if p2 else 1.0), delta, e.nav)
			s["cd"] -= delta
			var d := to.length()
			if s["cd"] <= 0.0 and d <= JUG_CHARGE_RANGE and d >= JUG_CHARGE_MIN and absf(angle_difference(e.rotation, to.angle() + PI / 2)) < JUG_AIM_TOL:
				_jug_wind(e, s, JUG_WIND, to.normalized())
				_say("jug_wind", "Pilot: the Juggernaut is lowering its head! Get out of the red lane!")
		"wind":
			s["t"] -= delta
			e.rotation = rotate_toward(e.rotation, s["dir"].angle() + PI / 2, 4.0 * delta)
			fx.p = 1.0 - s["t"] / s["w0"]
			_pulse(e, fx.p, Color(1.0, 0.7, 0.65))
			if s["t"] <= 0.0:
				s["mode"] = "charge"
				s["t"] = JUG_CHARGE_TIME
				s["hit"] = false
		"charge":
			_jug_charge(e, s, delta)
		"daze":
			s["t"] -= delta
			e.sprite.modulate = Color(0.75, 0.75, 0.8, e.sprite.modulate.a)
			if s["t"] <= 0.0:
				s["mode"] = "walk"
				s["cd"] = JUG_CD[1 if p2 else 0]
				if p2:
					s["chain"] = JUG_CHAIN - 1
				_calm(e, fx)
	return true


static func _jug_wind(e: Node2D, s: Dictionary, seconds: float, dir: Vector2) -> void:
	s.merge({"mode": "wind", "t": seconds, "w0": seconds, "dir": dir}, true)
	var fx := _fx(e)
	fx.lane = dir * JUG_CHARGE_SPEED * JUG_CHARGE_TIME * (1.3 if s["phase"] == 2 else 1.0)
	Sfx.play("boss_roar", e.global_position, -6.0)
	Sfx.play("rpg_warn", e.global_position, -8.0)


static func _jug_charge(e: Node2D, s: Dictionary, delta: float) -> void:
	var dir: Vector2 = s["dir"]
	var p2: bool = s["phase"] == 2
	s["t"] -= delta
	var v := dir * JUG_CHARGE_SPEED * (1.3 if p2 else 1.0) * delta
	e.rotation = dir.angle() + PI / 2
	var perp := dir.orthogonal()
	for d in range(int(e.radius) + 6, int(e.radius + v.length()) + 15, 8): # every cell this step covers: none is skipped
		for k in [-1, 0, 1]: # a swath as wide as the body
			var cell := Vector2i(((e.position + dir * d + perp * k * 10.0) / 16.0).floor())
			if Game.world.chunks.get_cell_atlas_coords(cell).x == T.BUILDING:
				Game.world.chunks.break_in(cell)
				Sfx.play("explosion", Vector2(cell) * 16.0, -10.0)
			elif Game.sandbags.get(cell, {}).get("built", false):
				Game.world.base.damage_sandbag(cell, JUG_SAND)
	var move: Vector2 = Game.world.slide(e.position, v)
	e.position += move
	var crashed := move.length() < v.length() * 0.5
	var heli: Node2D = Game.heli
	var base: Node2D = Game.world.base
	if not s["hit"] and Game.base_founded and e.global_position.distance_to(base.global_position) < e.radius + 50.0:
		s["hit"] = true
		base.take_damage(e.dmg)
	elif not s["hit"] and heli.landed and e.global_position.distance_to(heli.global_position) < e.radius + heli.RADIUS:
		s["hit"] = true
		heli.take_damage(e.dmg * JUG_HELI_MULT)
	if not (crashed or s["hit"] or s["t"] <= 0.0):
		return
	if crashed or s["hit"]:
		Game.world.spawn_fx(e.global_position, 1.2)
		Sfx.play("explosion", e.global_position, -4.0)
	if p2 and s["chain"] > 0 and not crashed and not s["hit"]:
		s["chain"] -= 1
		_jug_wind(e, s, JUG_WIND2, (Game.heli.global_position - e.global_position).normalized())
		return
	s["mode"] = "daze"
	s["t"] = JUG_DAZE if crashed or s["hit"] else JUG_WINDED


# ---------------------------------------------------------------- Hive

static func _hive(e: Node2D, s: Dictionary, delta: float) -> bool:
	var fx := _fx(e)
	if not s.has("home"):
		s.merge({"home": e.position, "site": "", "nemesis_id": ""})
	if not s.has("cd"):
		s.merge({"phase": s.get("phase", 1), "cd": HIVE_FIRST, "wind": 0.0, "waves": 0})
	e.position = s["home"] # rooted
	e.rotation = 0.0
	if s["phase"] == 1 and e.hp <= e.max_hp * PHASE_AT:
		s["phase"] = 2
		s["cd"] = minf(s["cd"], 4.0)
		Sfx.play("boss_roar", e.global_position, -2.0)
		Game.radio("Gunner: the Hive is bleeding... it is calling its strongest!")
	if e.global_position.distance_to(Game.heli.global_position) > HIVE_ACTIVE:
		return true
	if s["wind"] > 0.0:
		s["wind"] -= delta
		fx.p = 1.0 - s["wind"] / HIVE_WIND
		_pulse(e, fx.p, Color(1.0, 0.8, 0.75))
		if s["wind"] <= 0.0:
			s["wind"] = 0.0
			_calm(e, fx)
			_wave(e, s)
			s["cd"] = HIVE_CD[s["phase"] - 1]
		return true
	s["cd"] -= delta
	if s["cd"] <= 0.0:
		s["wind"] = HIVE_WIND
		Sfx.play("boss_roar", e.global_position, -4.0)
		Sfx.play("alarm", e.global_position, -10.0)
		_say("hive_wind", "Gunner: the Hive is throbbing, a wave is coming!")
	return true


static func _wave(e: Node2D, s: Dictionary) -> void:
	var near := 0
	for o in e.get_tree().get_nodes_in_group("enemies"):
		near += int(o.global_position.distance_squared_to(e.global_position) < 700.0 * 700.0)
	if near > HIVE_CAP:
		s["cd"] = 5.0
		return
	s["waves"] += 1
	var kinds: Array = []
	for i in HIVE_WAVE[s["phase"] - 1] + mini(s["waves"], 4):
		kinds.append(SpawnTable.pick(Game.danger_at(e.position), SpawnTable.context(e.position, true)))
	if s["phase"] == 2:
		kinds.append_array(HIVE_SPECIAL)
	for k in kinds:
		for i in 8: # a ring of open cells around a nest in ruins is not always there
			var p: Vector2 = e.global_position + Vector2(randf_range(e.radius + 6.0, e.radius + 70.0), 0).rotated(randf() * TAU)
			if Game.world.is_walkable(p):
				Game.world.spawn_enemy(k, p)
				break
	Game.make_noise(e.global_position, 1.0)
	Sfx.play("boss_roar", e.global_position, -6.0)


# ---------------------------------------------------------------- Warlord

static func _warlord(e: Node2D, s: Dictionary, delta: float) -> bool:
	var fx := _fx(e)
	var m: Node = Game.world.bosses
	var heli: Node2D = Game.heli
	if not s.has("phase"):
		var rec: Dictionary = m.records.get("warlord:" + e.camp_uid, {})
		s.merge({"phase": rec.get("phase", 1), "mortar": MORTAR_FIRST, "refill": BODY_REFILL, "refills": BODY_REFILLS, "nemesis_id": rec.get("nemesis_id", "")})
		if rec.has("hp"):
			e.hp = minf(e.max_hp, rec["hp"])
		_escorts[e.get_instance_id()] = []
		e.tree_exiting.connect(func(): _warlord_gone(e))
		for i in BODY_N + (BODY_P2.size() if s["phase"] == 2 else 0):
			_escort(e, "rifle")
		_say("warlord_seen", "Gunner: that must be the Warlord, with his bodyguards. Watch for the mortar when you land.")
	if s["phase"] == 1 and e.hp <= e.max_hp * PHASE_AT:
		s["phase"] = 2
		for k in BODY_P2:
			_escort(e, k)
		Sfx.play("boss_roar", e.global_position, -4.0)
		Game.radio("Warlord: \"Nobody leaves my camp alive! Fire at will!\"")
	var phase: int = s["phase"]
	s["refill"] -= delta
	if s["refill"] <= 0.0:
		s["refill"] = BODY_REFILL
		var want := BODY_N + (BODY_P2.size() if phase == 2 else 0)
		_escorts[e.get_instance_id()] = _escorts[e.get_instance_id()].filter(func(u): return is_instance_valid(u) and not u.is_queued_for_deletion())
		if s["refills"] > 0 and _escorts[e.get_instance_id()].size() < want:
			s["refills"] -= 1
			_escort(e, "rifle")
	if fx.p >= 0.0: # the telegraph: a flash on the warlord while a shell is on its way
		fx.p = maxf(-1.0, fx.p - delta / MORTAR_FUSE)
		if fx.p <= 0.0:
			fx.p = -1.0
	s["mortar"] -= delta
	if s["mortar"] <= 0.0 and heli.landed and e.global_position.distance_to(heli.global_position) < MORTAR_RANGE:
		s["mortar"] = MORTAR_CD[phase - 1]
		fx.p = 1.0
		var at: Vector2 = heli.global_position
		for i in 3 if phase == 2 else 1:
			_shell(at if i == 0 else at + Vector2(MORTAR_SPREAD, 0).rotated(randf() * TAU), i * 0.25)
		Sfx.play("rpg_warn", e.global_position, -4.0)
		_say("mortar", "Pilot: MORTAR! Lift off, now!")
	return false


static func _shell(at: Vector2, extra: float) -> void:
	var sh := Shell.new()
	sh.position = at
	sh.fuse = MORTAR_FUSE + extra
	sh.fuse0 = sh.fuse
	Game.world.add_child(sh)


static func _escort(e: Node2D, kind: String) -> void:
	var b: Node = Game.world.bandits
	var u: Node2D = b.spawn_unit(kind, b._spot(e.home, 45.0), "guard", e.home, "escort")
	_escorts[e.get_instance_id()].append(u)


## The warlord left the tree: dead, his men run home; asleep or dropped, they go with him.
static func _warlord_gone(e: Node2D) -> void:
	for u in _escorts.get(e.get_instance_id(), []):
		if is_instance_valid(u) and not u.is_queued_for_deletion():
			if e.get_meta("dead", false):
				u.role = "home"
			else:
				u.queue_free()
	_escorts.erase(e.get_instance_id())


## Drawn on every boss: hp bar, the telegraph ring (p 0..1 while one runs), the Juggernaut's charge lane and weak spot.
## Un-rotated: the enemy node turns with its sprite, so the drawing turns back.
class BossFx extends Node2D:
	var p := -1.0
	var lane := Vector2.ZERO # world-space vector of the charge
	var weak := false

	func _ready() -> void:
		z_index = 5

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var e: Node2D = get_parent()
		draw_set_transform(Vector2.ZERO, -e.rotation)
		var r: float = e.radius
		var f := clampf(e.hp / e.max_hp, 0.0, 1.0)
		draw_rect(Rect2(-18.0, -r - 12.0, 36.0, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-18.0, -r - 12.0, 36.0 * f, 3.0), Color(0.9, 0.25, 0.2) if f > Bosses.PHASE_AT else Color(1.0, 0.7, 0.2))
		if p >= 0.0:
			var col := Color(1.0, 0.3, 0.25, 0.3 + 0.6 * p)
			draw_arc(Vector2.ZERO, r + 6.0 + 30.0 * (1.0 - p), 0.0, TAU, 28, col, 1.5)
			if lane != Vector2.ZERO:
				draw_line(Vector2.ZERO, lane, Color(1.0, 0.2, 0.15, 0.2 + 0.4 * p), 8.0 + 8.0 * p)
		if weak:
			var rear := Vector2.DOWN.rotated(e.rotation) * (r - 3.0)
			draw_circle(rear, 3.0 + sin(Time.get_ticks_msec() / 150.0), Color(1.0, 0.25, 0.15, 0.55))


## A mortar shell on its way: a circle closing in on the spot for `fuse` s, then the blast. Hits the heli only if it is still down there.
class Shell extends Node2D:
	var fuse := 2.4
	var fuse0 := 2.4

	func _ready() -> void:
		z_index = 4

	func _process(delta: float) -> void:
		if not Game.running:
			return
		fuse -= delta
		queue_redraw()
		if fuse > 0.0:
			return
		Game.world.spawn_fx(global_position, 1.6)
		Sfx.play("explosion", global_position, -2.0)
		Game.make_noise(global_position, 1.2)
		var heli: Node2D = Game.heli
		if heli.landed and heli.global_position.distance_to(global_position) < Bosses.MORTAR_RADIUS + heli.RADIUS:
			heli.take_damage(Bosses.MORTAR_DMG, "mortar")
		queue_free()

	func _draw() -> void:
		var f := clampf(fuse / fuse0, 0.0, 1.0)
		draw_circle(Vector2.ZERO, Bosses.MORTAR_RADIUS, Color(1.0, 0.2, 0.15, 0.1 + 0.2 * (1.0 - f)))
		draw_arc(Vector2.ZERO, Bosses.MORTAR_RADIUS * (0.3 + 0.7 * f), 0.0, TAU, 28, Color(1.0, 0.35, 0.25, 0.9), 1.5)


func save_state() -> Dictionary:
	return {"records": records.duplicate(true), "pending": pending.duplicate(), "last_roam": last_roam}


func load_state(d: Dictionary) -> void:
	records = d.get("records", {})
	pending = d.get("pending", [])
	last_roam = d.get("last_roam", -100)
