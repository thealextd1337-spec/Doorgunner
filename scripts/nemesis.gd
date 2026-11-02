class_name Nemesis
extends Node
## Named rivals with a memory, and the Warlord's gunship (docs/ROADMAP2.md Q15). main.gd keeps this node as `nemesis`; it saves
## itself (hook "nemesis"; a run saved before Q15 starts with no rivals and an empty memory).
## Up to two rivals per run, built on the Q12 bosses (bosses.gd) whose `state["nemesis_id"]` they set:
##   warlord  a named bandit Warlord (bandit.gd kind "warlord") who holds a camp: a Q12 warlord camp, else the first known camp
##            gets him (from FIRST_DAY). From the big attack on he flies the captured GUNSHIP (class Gunship below) instead.
##   alpha    a named infected Alpha: a Q12 Matriarch (enemy.gd kind "matriarch") that hunts the heli and later leads an assault.
## Names and traits come from the seed (a daily gives everybody the same rivals); TRAITS scale hp, raids, escape or speed.
## Memory (cheap counters, sampled every TICK s and once a day) and what the rivals do with it:
##   air / fast    seconds airborne / at FAST_SHARE of top speed  -> fast_flyer(): RPG_EXTRA rocket men with the Warlord and in his
##                 raid, gunship rockets every GS_ROCKET_CD * GS_FAST_ROCKET s
##   wire          most built barbed-wire pieces seen             -> wire_heavy(): the Alpha's assault push is crawlers (under the
##                 wire) and spitters (shoot over it), WIRE_MIX
##   weapons       seconds of fire per gun                        -> favourite(): the gunship keeps to the edge of its range (keep_band)
##   camps         bandit camps cleared                           -> raid strength + CAMP_GRUDGE each, a taunt
##   flees         fights with a rival the heli broke off (ENGAGE -> DISENGAGE px) -> a rival returns sooner (RETURN_DAYS - flees), taunt
## A rival below its escape share of HP (ESCAPE_AT, the cunning trait more) escapes, at most MAX_ESCAPES times; it is away RETURN_DAYS
## days and returns STRONGER (hp, raids, horde). Escalation (_on_day): stage 1 contact (named, intro on the radio) -> after
## CONTACT_DAYS stage 2: raids every RAID_GAP days on convoys on the road, outposts and villages (outposts.raid) or settlements, the
## Warlord's ransom card (Q13 Events, "nem_ransom", not in a daily: no cards there) -> after RAIDS_TO_ATTACK raids stage 3, the big
## attack every ATTACK_GAP days: the Warlord's gunship plus a bandit base raid at ATTACK_AT on a night Assault.night_taken leaves
## free; the Alpha leads the next scheduled assault (her push joins assault.gd's queue). Killed for good (defeated signal, gunship
## shot down): REWARD, morale, codex; the next rival of that kind not before NEW_RIVAL_DAYS days later.

signal ended(kind: String, rival_name: String) # a rival died for good

const KINDS := ["warlord", "alpha"]
const FIRST_DAY := {"warlord": 10, "alpha": 8}
const NEW_RIVAL_DAYS := 8
const NAMES := {
	"warlord": ["Iron Kane", "Mad Brennan", "Red Mallory", "Baron Vasquez", "Butcher Holt", "Major Sokol"],
	"alpha": ["Mother Grief", "The Widow", "Old Hunger", "Scarback", "The Ash Queen"],
}
# hp: max HP factor, raid: raid strength factor, escape: escape share of HP, speed: walking speed factor, horde: assault push factor
const TRAITS := {
	"brutal": {"kind": "warlord", "raid": 1.5, "text": "brutal: his raids hit half again as hard"},
	"cunning": {"kind": "warlord", "escape": 0.45, "text": "cunning: runs early, so he lives to come back"},
	"proud": {"kind": "warlord", "hp": 1.3, "text": "proud: tougher, never backs down early"},
	"swift": {"kind": "alpha", "speed": 1.35, "text": "swift: a third faster"},
	"fecund": {"kind": "alpha", "horde": 1.5, "text": "fecund: a bigger brood in her assault"},
	"scarred": {"kind": "alpha", "hp": 1.3, "text": "scarred: tougher hide"},
}
const CODEX := {"warlord": "b_rival", "alpha": "z_alpha"}
const SEE_DIST := 700.0
# escape and return
const ESCAPE_AT := 0.3
const MAX_ESCAPES := 2
const RETURN_DAYS := 3
const STRONGER := 0.25 # per escape: hp, raid strength, assault push
# escalation
const CONTACT_DAYS := 2
const RAID_GAP := 2
const RAIDS_TO_ATTACK := 2
const ATTACK_GAP := 4
const ATTACK_AT := 0.85 # time of day of the Warlord's attack (bandits.BASE_RAID_AT)
const CAMP_GRUDGE := 0.15
const CONVOY_HIT := 35.0 # the Alpha's brood on a convoy: truck hull
const ALPHA_HUNT := 0.5 # chance a day she comes for the heli (stages 1-2, not around)
const ALPHA_PUSH := 10 # her push in the assault (x strength x trait)
const ALPHA_MIX := ["runner", "runner", "brute"]
const WIRE_MIX := ["crawler", "crawler", "spitter"]
const RANSOM_SCRAP := 80
const RANSOM_DAYS := 3
# memory
const TICK := 0.5
const FAST_SHARE := 0.8
const FAST_MIN_AIR := 60.0 # s airborne before the speed counts
const FAST_ADAPT := 0.4 # share of airborne time spent fast: a fast flyer
const WIRE_HEAVY := 8
const ENGAGE := 450.0
const DISENGAGE := 1200.0
const RPG_EXTRA := 2
# reward for killing a rival for good (on top of the Q12 boss reward)
const REWARD := {"scrap": 150, "xp": 400, "morale": 15.0, "salvage": {"parts": 10.0, "electronics": 10.0}}
# gunship: heli physics like heli.gd (ACCEL / DRAG / MAX_SPEED), a bit slower than the player
const GS_HP := 650.0
const GS_RADIUS := 14.0
const GS_ACCEL := 140.0
const GS_SPEED := 100.0 # player heli 115
const GS_DRAG := 1.25
const GS_ORBIT := 0.7 # sideways share of its steering: it circles while it holds the distance
const GS_KEEP := Vector2(240.0, 380.0) # outer edge of the band it holds: KEEP_SHARE of the favourite gun's range, clamped (inside its own GS_GUN_RANGE)
const KEEP_SHARE := 0.9
const GS_KEEP_WIDTH := 100.0
const GS_SPAWN := 900.0 # px from the heli
const GS_GUN_RANGE := 400.0
const GS_BURST := 5
const GS_GUN_CD := 2.4
const GS_ROUND_DMG := 2.5
const GS_CHANCE := 0.4 # per round point-blank, less with range and the heli's speed (as bandit.gd)
const GS_ROCKET_RANGE := 480.0
const GS_ROCKET_CD := 9.0
const GS_FAST_ROCKET := 0.6 # cooldown factor against a fast flyer
const GS_ROCKET_DMG := 22.0
const GS_AIM := 1.0 # s of red aim line before a rocket
const GS_FLARE_SEE := 300.0 # a flare this close to the heli: the gunship holds its rockets (they would chase the flare)
const GS_FLARE_WAIT := 1.5
const GS_FLARE_DODGE := 140.0 # a flare this close to the gunship: it breaks away from it
const GS_DODGE_ACCEL := 2.0 # thrust factor while it breaks away
const GS_LEAVE := 1400.0 # a fleeing gunship is gone at this distance
const GS_XP := 300
const Weapons := preload("res://scripts/weapons.gd")
const Poi := preload("res://scripts/poi.gd")
# radio voice: the Warlord on intercepted bandit radio (bandit beep), the Alpha through the crew
const LINES := {
	"warlord": {
		"intro": "Intercepted - {name}: \"So you are the bird over my valley. I am {name}. Stay out of my sky.\"",
		"seen": "Gunner: that is {name} himself. Take him and his band falls apart.",
		"threat": "Intercepted - {name}: \"Your outposts. Your trucks. I know where every one of them is.\"",
		"raid": "Intercepted - {name}: \"Burn it. Leave one alive to tell them who did it.\"",
		"escape": "Intercepted - {name}: \"Not today, bird! I will be back, and I will bring friends.\"",
		"return": "Intercepted - {name}: \"Miss me? I got new toys.\"",
		"aloft": "Intercepted - {name}: \"I found a helicopter of my own. Now we meet in the air.\"",
		"attack_warn": "Intercepted - {name}: \"{when} I come for your base. Look up.\"",
		"attack": "ALERT: {name}'s gunship inbound! It holds its distance and fires rockets: flares pull them off.",
		"coward": "Intercepted - {name}: \"Run, bird, run! I saw your tail.\"",
		"camp": "Intercepted - {name}: \"That was my camp. You will pay for every man.\"",
		"fast": "Intercepted - {name}: \"Fast flyer, eh? Rockets are faster. Boys, bring the tubes.\"",
		"gun": "Intercepted - {name}: \"I know your {gun}. My pilot stays just out of its reach.\"",
		"paid": "Intercepted - {name}: \"Smart. Enjoy the quiet while it lasts.\"",
		"refused": "Intercepted - {name}: \"Then I come early.\"",
		"death": "Gunner: {name} is dead! That band is finished.",
	},
	"alpha": {
		"intro": "Watchtower: survivors talk about a matriarch that learned. Scarred, clever, patient. They call her {name}.",
		"seen": "Gunner: that is {name}! Scars all over, and she is watching us.",
		"threat": "Watchtower: a screech on the wind every night. {name} is circling the outposts.",
		"raid": "Radio: {name}'s brood is tearing at our people!",
		"escape": "Gunner: {name} is bleeding and running! She will be back, and bigger.",
		"return": "Watchtower: that screech again. {name} is back.",
		"hunt": "Gunner: {name} is on our trail. She follows the rotor noise.",
		"attack_warn": "Watchtower: the horde moves like an army now. {name} will lead the next assault.",
		"attack": "ALERT: {name} leads the assault!",
		"coward": "Gunner: we left {name} behind. She will follow the noise.",
		"wire": "Watchtower: they stopped walking into the wire. Crawlers and spitters now. {name} learned.",
		"death": "Gunner: {name} is dead! The hordes are leaderless.",
	},
}

var rivals := {} # kind -> {kind, name, trait, gen, stage 1-3, since, met, escapes, away (return day, -1), raids, next_raid, attack_day, hp (share), camp, engaged, spawn}
var memory := {"air": 0.0, "fast": 0.0, "wire": 0, "camps": 0, "flees": 0, "weapons": {}, "told": []}
var next_day := {"warlord": 0, "alpha": 0} # no new rival of that kind before this day
var gens := {"warlord": 0, "alpha": 0} # rivals named so far, per kind (name and trait roll)
var gunship: Node2D
var _t := 0.0


func _ready() -> void:
	Save.register("nemesis", save_state, load_state)
	Game.day_changed.connect(_on_day)
	Game.base_attack_started.connect(_on_assault) # after assault.gd's handler: main.gd adds this node later
	Game.world.bosses.defeated.connect(_on_defeated)
	Game.world.bandits.camp_cleared.connect(_on_camp_cleared)
	Game.world.events.chosen.connect(_on_chosen)
	Events.register("nem_ransom", {"title": "A PRICE ON YOUR HEAD", "from": "Bandit radio", "chain_only": true, "default": 1,
		"text": "{rival}: \"Your outposts and trucks burn one by one, or you pay me and I look the other way. For a while.\"",
		"opts": [
			{"t": "Pay him", "h": "%d scrap, no raids for %d days" % [RANSOM_SCRAP, RANSOM_DAYS], "need": {"scrap": RANSOM_SCRAP}, "fx": {"scrap": -RANSOM_SCRAP}},
			{"t": "Refuse", "h": "he raids tomorrow", "fx": {"morale": 1}}]})


func _process(delta: float) -> void:
	if not Game.running or get_tree().paused or Game.heli == null or is_instance_valid(Game.world.tutorial):
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = TICK
	tick()


func tick() -> void:
	_remember()
	for kind in KINDS:
		if not rivals.has(kind) and Game.day >= FIRST_DAY[kind] and Game.day >= next_day[kind]:
			_try_name(kind)
	for r: Dictionary in rivals.values():
		var body := body_of(r)
		if body != null:
			_watch(r, body)
		elif r["kind"] == "alpha" and r["spawn"] and r["away"] < 0:
			_hunt(r)
	_attack_due()


# ---------------------------------------------------------------- memory

func _remember() -> void:
	var h: Node2D = Game.heli
	if not h.landed:
		memory["air"] += TICK
		if h.vel.length() >= FAST_SHARE * h.MAX_SPEED:
			memory["fast"] += TICK
	if h.fire_cd > -TICK: # fired within the last tick
		memory["weapons"][Game.weapon] = memory["weapons"].get(Game.weapon, 0.0) + TICK
	for r: Dictionary in rivals.values(): # adaptations announce themselves once
		if r["kind"] == "warlord" and fast_flyer():
			_tell(r, "fast")
		if r["kind"] == "alpha" and wire_heavy() and r["stage"] >= 2:
			_tell(r, "wire")


func fast_flyer() -> bool:
	return memory["air"] >= FAST_MIN_AIR and memory["fast"] / memory["air"] >= FAST_ADAPT


func wire_heavy() -> bool:
	return memory["wire"] >= WIRE_HEAVY


## The gun fired longest this run ("mg" before any).
func favourite() -> String:
	var best := "mg"
	for id: String in memory["weapons"]:
		if memory["weapons"][id] > memory["weapons"].get(best, 0.0) and Weapons.TABLE.has(id):
			best = id
	return best


## Distance band (near, far) the gunship holds: just outside the reach of the favourite gun where it can.
func keep_band() -> Vector2:
	var far := clampf(Weapons.TABLE[favourite()]["range"] * KEEP_SHARE, GS_KEEP.x, GS_KEEP.y)
	return Vector2(far - GS_KEEP_WIDTH, far)


func rocket_cd() -> float:
	return GS_ROCKET_CD * (GS_FAST_ROCKET if fast_flyer() else 1.0)


func strength(r: Dictionary) -> float:
	return 1.0 + STRONGER * r["escapes"]


func trait_val(r: Dictionary, key: String, default: float) -> float:
	return TRAITS[r["trait"]].get(key, default)


func return_days() -> int:
	return maxi(1, RETURN_DAYS - memory["flees"])


## The Alpha's push into an assault.
func horde(r: Dictionary) -> Array:
	var mix: Array = WIRE_MIX if wire_heavy() else ALPHA_MIX
	var out := []
	for i in int(ALPHA_PUSH * strength(r) * trait_val(r, "horde", 1.0)):
		out.append(mix[i % mix.size()])
	return out


# ---------------------------------------------------------------- naming, bodies

func _try_name(kind: String) -> void:
	if kind == "warlord":
		var camp := {}
		for c: Dictionary in Game.world.bandits.camps.values():
			if c["cleared"]:
				continue
			if c.get("warlord", false) and c["garrison"].get("warlord", 0) > 0:
				camp = c
				break
			if c["known"] and camp.is_empty():
				camp = c
		if camp.is_empty():
			return
		_seat(_name(kind), camp)
	elif not Game.heli.landed:
		_name(kind)["spawn"] = true


func _name(kind: String) -> Dictionary:
	var gen: int = gens[kind]
	gens[kind] = gen + 1
	var names: Array = NAMES[kind]
	var traits: Array = TRAITS.keys().filter(func(t: String) -> bool: return TRAITS[t]["kind"] == kind)
	var r := {"kind": kind, "name": names[hash([Game.seed, kind, gen]) % names.size()], "trait": traits[hash([Game.seed, kind, gen, "trait"]) % traits.size()],
		"gen": gen, "stage": 1, "since": Game.day, "met": false, "escapes": 0, "away": -1, "raids": 0, "next_raid": Game.day + CONTACT_DAYS,
		"attack_day": -1, "hp": 1.0, "camp": "", "engaged": false, "spawn": false}
	rivals[kind] = r
	say(r, "intro")
	return r


## The Warlord holds camp `c` (or, without one, his old camp or any other that is not cleared). False if there is none.
func _seat(r: Dictionary, c := {}) -> bool:
	var camps: Dictionary = Game.world.bandits.camps
	if c.is_empty():
		c = camps.get(r["camp"], {})
	if c.is_empty() or c["cleared"]:
		c = {}
		for o: Dictionary in camps.values():
			if not o["cleared"]:
				c = o
				break
	if c.is_empty():
		return false
	r["camp"] = c["uid"]
	c["warlord"] = true
	c["garrison"]["warlord"] = 1
	var key: String = "warlord:" + c["uid"]
	var rec: Dictionary = {} if Game.world.bosses.records.get(key, {}).get("dead", false) else Game.world.bosses.records.get(key, {})
	rec["nemesis_id"] = "warlord" # a Q12 warlord already there keeps his hp and phase
	Game.world.bosses.records[key] = rec
	return true


## The rival's node: the Warlord in his camp (stages 1-2) or his gunship (3), the Alpha's matriarch. Null while not out there.
func body_of(r: Dictionary) -> Node2D:
	if r["kind"] == "warlord" and r["stage"] >= 3:
		return gunship if is_instance_valid(gunship) and not gunship.is_queued_for_deletion() else null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion() or e.get("state") == null:
			continue
		if r["kind"] == "warlord" and e is Bandit and e.kind == "warlord" and e.camp_uid == r["camp"]:
			return e
		if r["kind"] == "alpha" and e.state.get("nemesis_id", "") == "alpha":
			return e
	return null


## Every TICK while the rival is out there: name the boss, make it stronger once, contact, the heli breaking off, the escape.
func _watch(r: Dictionary, body: Node2D) -> void:
	var s: Dictionary = body.state
	if body != gunship:
		if not s.has("phase"):
			return # bosses.gd sets the boss up on its first frame (hp from its record): ours comes after
		if not s.get("nem", false):
			s["nemesis_id"] = r["kind"]
			s["nem"] = true
			body.max_hp *= strength(r) * trait_val(r, "hp", 1.0)
			body.hp = body.max_hp * r["hp"]
			body.speed *= trait_val(r, "speed", 1.0)
			if r["kind"] == "warlord" and fast_flyer():
				for i in RPG_EXTRA:
					Bosses._escort(body, "rpg")
	r["hp"] = clampf(body.hp / body.max_hp, 0.0, 1.0)
	var d: float = body.global_position.distance_to(Game.heli.global_position)
	if d < SEE_DIST and not r["met"]:
		r["met"] = true
		Codex.unlock(CODEX[r["kind"]])
		say(r, "seen")
	if body == gunship and d < SEE_DIST:
		Codex.unlock("b_gunship")
	if d < ENGAGE:
		r["engaged"] = true
	elif r["engaged"] and d > DISENGAGE and not body.get("fleeing"):
		r["engaged"] = false
		memory["flees"] += 1
		say(r, "coward")
	if r["hp"] < trait_val(r, "escape", ESCAPE_AT) and r["escapes"] < MAX_ESCAPES and not body.get("fleeing"):
		_escape(r, body)


func _escape(r: Dictionary, body: Node2D) -> void:
	r["escapes"] += 1
	r["away"] = Game.day + return_days()
	r["hp"] = 1.0
	r["engaged"] = false
	say(r, "escape")
	Sfx.play("boss_roar", body.global_position, -6.0)
	if body == gunship:
		gunship.fleeing = true
		return
	Game.world.spawn_fx(body.global_position, 1.2)
	if r["kind"] == "warlord":
		_unseat(r)
	body.queue_free()


## The Warlord leaves his camp (escape, or he takes to the air): his bodyguards scatter, the camp may be cleared without him.
func _unseat(r: Dictionary) -> void:
	var c: Dictionary = Game.world.bandits.camps.get(r["camp"], {})
	if c.is_empty():
		return
	c["garrison"]["warlord"] = 0
	Game.world.bosses.records.erase("warlord:" + c["uid"])
	for e in get_tree().get_nodes_in_group("bandits"):
		if e.kind == "warlord" and e.camp_uid == c["uid"] and not e.is_queued_for_deletion():
			e.set_meta("dead", true) # bosses.gd: the bodyguards walk home instead of vanishing
			e.queue_free()
	if not c["cleared"] and c["garrison"].values().all(func(n): return n <= 0):
		Game.world.bandits._clear(c)


## The Alpha comes for the heli: a roaming matriarch near it, away from the base.
func _hunt(r: Dictionary) -> void:
	if Game.heli.landed:
		return
	var e: Node2D = Game.world.bosses.spawn_roamer("matriarch")
	if e != null:
		e.state["nemesis_id"] = "alpha"
		r["spawn"] = false
		say(r, "hunt")


# ---------------------------------------------------------------- escalation

func _on_day(day: int) -> void:
	var wire := 0
	for s: Dictionary in Game.sandbags.values():
		wire += int(s["kind"] == "wire" and s["built"])
	memory["wire"] = maxi(memory["wire"], wire)
	for r: Dictionary in rivals.values():
		if r["away"] >= 0:
			if day < r["away"]:
				continue
			_come_back(r)
		match r["stage"]:
			1:
				if day >= r["since"] + CONTACT_DAYS:
					_stage2(r)
			2:
				if day >= r["next_raid"]:
					raid(r)
			3:
				if r["kind"] == "warlord" and r["attack_day"] >= 0 and r["attack_day"] < day:
					r["attack_day"] = free_night(day) # missed (a load, an assault took it)
				elif r["kind"] == "warlord" and r["attack_day"] < 0 and day >= r["next_raid"]:
					_plan_attack(r)
		if r["kind"] == "alpha" and r["stage"] < 3 and body_of(r) == null and randf() < ALPHA_HUNT:
			r["spawn"] = true


func _come_back(r: Dictionary) -> void:
	r["away"] = -1
	say(r, "return")
	if r["kind"] == "alpha":
		r["spawn"] = r["stage"] < 3
	elif r["stage"] < 3 and not _seat(r):
		_stage3(r) # no camp left to hold: he takes to the air


func _stage2(r: Dictionary) -> void:
	r["stage"] = 2
	r["next_raid"] = Game.day + 1
	say(r, "threat")
	if r["kind"] == "warlord" and Game.mode != "daily" and Settings.is_on(Events.KEY): # no cards in a daily (events.gd)
		Events.offer("nem_ransom", {"rival": r["name"]})


## One raid of rival `r`: a convoy on the road, else an outpost or village, else a settlement (the Warlord) or the heli (the Alpha).
## Returns what was hit: "convoy", "outpost", "town", "hunt" or "".
func raid(r: Dictionary) -> String:
	r["raids"] += 1
	r["next_raid"] = Game.day + RAID_GAP
	var what := ""
	var power: float = strength(r) * trait_val(r, "raid", 1.0) * (1.0 + CAMP_GRUDGE * memory["camps"])
	var cv: Node = Game.world.convoys
	var trucks: Array = cv.list.filter(func(c: Dictionary) -> bool: return c["leg"] in ["out", "back"] and c["foes"] <= 0 and c["hp"] > 0.0)
	var targets: Array = Game.world.outposts.targets()
	if not trucks.is_empty():
		var c: Dictionary = trucks.pick_random()
		if r["kind"] == "warlord":
			cv._ambush(c)
			c["foes"] += r["escapes"]
		else:
			c["hp"] -= CONVOY_HIT * power
			Game.radio("ALERT: Convoy %s hit by the horde!" % c["id"].substr(1))
		what = "convoy"
	elif not targets.is_empty():
		var t: Dictionary = targets.pick_random()
		Game.world.outposts.raid(t["id"], SpawnTable.bandits(SpawnTable.RAID_ROWS, Game.day).get("rifle", 3) * power, "bandits" if r["kind"] == "warlord" else "infected")
		what = "outpost"
	elif r["kind"] == "warlord":
		what = "town" if Game.world.bandits.plan_town_raid(Game.day, true) else ""
	else:
		r["spawn"] = true
		what = "hunt"
	if what != "" and what != "hunt":
		say(r, "raid")
	if r["raids"] >= RAIDS_TO_ATTACK:
		_stage3(r)
	return what


func _stage3(r: Dictionary) -> void:
	r["stage"] = 3
	if r["kind"] == "warlord":
		_unseat(r)
		say(r, "aloft")
		_plan_attack(r)
	else:
		r["next_raid"] = Game.day # she joins the next assault
		say(r, "attack_warn")


## First day from `from` whose night no assault (or blood moon, or bandit base raid) has taken.
func free_night(from: int) -> int:
	var d := from
	while Assault.night_taken(d) or Game.world.bandits.base_raid_day == d or d == Game.day and Game.time >= ATTACK_AT:
		d += 1
	return d


func _plan_attack(r: Dictionary) -> void:
	r["attack_day"] = free_night(Game.day)
	say(r, "attack_warn", {"when": "Tonight" if r["attack_day"] == Game.day else "In %d nights" % (r["attack_day"] - Game.day)})


func _attack_due() -> void:
	var r: Dictionary = rivals.get("warlord", {})
	if r.is_empty() or r["stage"] < 3 or r["away"] >= 0 or r["attack_day"] != Game.day or Game.time < ATTACK_AT or body_of(r) != null:
		return
	if Assault.night_taken(Game.day):
		r["attack_day"] = free_night(Game.day + 1)
		return
	big_attack(r)


## The Warlord's big attack: his gunship, and a bandit raid on the base (RPG men too against a fast flyer).
func big_attack(r: Dictionary) -> Node2D:
	r["attack_day"] = -1
	r["next_raid"] = Game.day + ATTACK_GAP
	var g := spawn_gunship(r)
	if Game.base_founded:
		var units: Array = Game.world.bandits.base_raid()
		if fast_flyer() and not units.is_empty():
			for i in RPG_EXTRA:
				var u: Node2D = Game.world.bandits.spawn_unit("rpg", units[0].position, "base", units[0].home, units[0].camp_uid)
				u.goal = units[0].goal
	say(r, "attack")
	if favourite() != "mg":
		_tell(r, "gun")
	return g


func spawn_gunship(r: Dictionary, at := Vector2.INF) -> Node2D:
	var g := Gunship.new()
	g.position = at if at != Vector2.INF else Game.heli.global_position + Vector2(GS_SPAWN, 0).rotated(randf() * TAU)
	g.max_hp = GS_HP * strength(r) * trait_val(r, "hp", 1.0)
	g.hp = g.max_hp * r["hp"]
	Game.world.add_child(g)
	gunship = g
	Sfx.play("alarm", null, -6.0)
	return g


## The Alpha leads the assault that just began (stage 3, once every ATTACK_GAP days): she and her push join the wave.
func _on_assault(day: int) -> void:
	var r: Dictionary = rivals.get("alpha", {})
	if r.is_empty() or r["stage"] < 3 or r["away"] >= 0 or day < r["next_raid"] or not Game.base_founded:
		return
	r["next_raid"] = day + ATTACK_GAP
	var e := body_of(r)
	if e == null:
		e = Game.world.spawn_enemy("matriarch", Game.world.base.global_position + Vector2(Assault.SPAWN_RADIUS + 80.0, 0).rotated(randf() * TAU), true)
		e.state["nemesis_id"] = "alpha"
	e.target_base = true
	Game.world.assault.queue.append_array(horde(r))
	say(r, "attack")


# ---------------------------------------------------------------- the end, signals

func _on_defeated(_id: String, nemesis_id: String) -> void:
	if rivals.has(nemesis_id):
		_end(rivals[nemesis_id])


func gunship_down() -> void:
	if rivals.has("warlord"):
		_end(rivals["warlord"])


func _end(r: Dictionary) -> void:
	rivals.erase(r["kind"])
	next_day[r["kind"]] = Game.day + NEW_RIVAL_DAYS
	Game.scrap += REWARD["scrap"]
	Game.add_xp(REWARD["xp"])
	for k: String in REWARD["salvage"]:
		Game.salvage[k] += REWARD["salvage"][k]
	Game.world.morale.add(REWARD["morale"], "rival killed")
	Codex.unlock(CODEX[r["kind"]])
	say(r, "death")
	Game.radio("Command: %s is gone for good. +%d scrap, %d parts, %d electronics. Morale up." % [r["name"], REWARD["scrap"], REWARD["salvage"]["parts"], REWARD["salvage"]["electronics"]])
	ended.emit(r["kind"], r["name"])


func _on_camp_cleared(_uid: String) -> void:
	memory["camps"] += 1
	if rivals.has("warlord"):
		say(rivals["warlord"], "camp")


func _on_chosen(id: String, option: int) -> void:
	var r: Dictionary = rivals.get("warlord", {})
	if id != "nem_ransom" or r.is_empty():
		return
	if option == 0:
		r["next_raid"] = maxi(r["next_raid"], Game.day + RANSOM_DAYS)
		say(r, "paid")
	else:
		r["next_raid"] = Game.day + 1
		say(r, "refused")


func say(r: Dictionary, key: String, extra := {}) -> void:
	var line: String = LINES[r["kind"]].get(key, "")
	if line == "":
		return
	var ctx := {"name": r["name"], "gun": Weapons.TABLE[favourite()]["name"]}
	ctx.merge(extra)
	Game.radio(line.format(ctx))


## A line about an adaptation, once per rival.
func _tell(r: Dictionary, key: String) -> void:
	var id: String = "%s%d:%s" % [r["kind"], r["gen"], key]
	if not id in memory["told"]:
		memory["told"].append(id)
		say(r, key)


## Any rival met (onboarding hint).
func met() -> bool:
	return rivals.values().any(func(r: Dictionary) -> bool: return r["met"])


func save_state() -> Dictionary:
	var g := []
	if is_instance_valid(gunship) and not gunship.is_queued_for_deletion():
		g = [gunship.position, gunship.vel, gunship.hp, gunship.max_hp, gunship.fleeing]
	return {"rivals": rivals.duplicate(true), "memory": memory.duplicate(true), "next_day": next_day.duplicate(), "gens": gens.duplicate(), "gunship": g}


func load_state(d: Dictionary) -> void:
	rivals = d.get("rivals", {})
	memory.merge(d.get("memory", {}), true)
	next_day.merge(d.get("next_day", {}), true)
	gens.merge(d.get("gens", {}), true)
	if is_instance_valid(gunship):
		gunship.free()
	var g: Array = d.get("gunship", [])
	if not g.is_empty() and rivals.has("warlord"):
		spawn_gunship(rivals["warlord"], g[0])
		gunship.vel = g[1]
		gunship.hp = g[2]
		gunship.max_hp = g[3]
		gunship.fleeing = g[4]


## The Warlord's captured helicopter. Flies like heli.gd (thrust, drag, top speed), holds keep_band() from the heli while it circles,
## fires GS_BURST-round bursts within GS_GUN_RANGE and bandit.gd rockets (decoyed by flares) after GS_AIM s of red aim line.
## Flares near the heli: it holds the rockets; a flare near itself: it veers away. In group "enemies": the door gun, turrets and
## militia hit it. Fleeing it flies straight away and is gone at GS_LEAVE.
class Gunship extends Node2D:
	var hp := GS_HP
	var max_hp := GS_HP
	var radius := GS_RADIUS
	var kind := "gunship"
	var state := {}
	var concealed := false
	var vel := Vector2.ZERO
	var fleeing := false
	var orbit := 1.0
	var gun_cd := 1.5
	var burst := 0
	var gap := 0.0
	var rocket_cd := 4.0
	var aim_t := 0.0
	var dodges := 0 # flares it veered from (tests)
	var held := 0 # rocket shots held back for a flare (tests)
	var tracer := Vector2.ZERO
	var tracer_t := 0.0
	var sprite: Sprite2D
	var rotor: Sprite2D
	var shadow: Sprite2D

	func _ready() -> void:
		add_to_group("enemies")
		z_index = 8
		shadow = Art.sprite("gunship")
		shadow.modulate = Color(0, 0, 0, 0.35)
		shadow.position = Vector2(10, 14)
		add_child(shadow)
		sprite = Art.sprite("gunship")
		add_child(sprite)
		rotor = Art.sprite("rotor")
		add_child(rotor)
		orbit = 1.0 if randf() < 0.5 else -1.0

	func _process(delta: float) -> void:
		if not Game.running or Game.heli == null:
			return
		var nem: Node = Game.world.nemesis
		var to: Vector2 = Game.heli.global_position - global_position
		var d := to.length()
		var want := Vector2.ZERO
		var accel := GS_ACCEL
		if fleeing:
			want = -to
			if d > GS_LEAVE:
				queue_free()
				return
		else:
			var band: Vector2 = nem.keep_band()
			var radial := 1.0 if d > band.y else (-1.0 if d < band.x else 0.0)
			want = to.normalized() * radial + to.orthogonal().normalized() * orbit * GS_ORBIT
			var dodge := Vector2.ZERO
			for f in get_tree().get_nodes_in_group("rocket_decoys"):
				var away: Vector2 = global_position - f.global_position
				if away.length() < GS_FLARE_DODGE:
					dodge += away.normalized()
					if not f.has_meta("dodged"):
						f.set_meta("dodged", true)
						dodges += 1
			if dodge != Vector2.ZERO: # a burning flare beats holding the band
				want = dodge
				accel *= GS_DODGE_ACCEL
		if want != Vector2.ZERO:
			vel += want.normalized() * accel * delta
		vel -= vel * GS_DRAG * delta
		vel = vel.limit_length(GS_SPEED)
		position += vel * delta
		var face := vel.angle() if fleeing and vel != Vector2.ZERO else to.angle()
		sprite.rotation = lerp_angle(sprite.rotation, face + PI / 2, minf(1.0, 4.0 * delta))
		shadow.rotation = sprite.rotation
		rotor.rotation += 25.0 * delta
		if not fleeing:
			_shoot(delta, to, d, nem)
		queue_redraw()

	func _shoot(delta: float, to: Vector2, d: float, nem: Node) -> void:
		tracer_t -= delta
		gun_cd -= delta
		gap -= delta
		if d < GS_GUN_RANGE and burst <= 0 and gun_cd <= 0.0:
			burst = GS_BURST
			gun_cd = GS_GUN_CD
		if burst > 0 and gap <= 0.0:
			burst -= 1
			gap = 0.12
			_round(to, d)
		rocket_cd -= delta
		if rocket_cd > 0.0 or d > GS_ROCKET_RANGE:
			aim_t = 0.0
			return
		if _flare_near_heli():
			held += 1
			aim_t = 0.0
			rocket_cd = GS_FLARE_WAIT
			return
		if aim_t == 0.0:
			Sfx.play("rpg_warn", global_position, -6.0)
		aim_t += delta
		if aim_t >= GS_AIM:
			aim_t = 0.0
			rocket_cd = nem.rocket_cd()
			var r := Bandit.Rocket.new()
			r.position = global_position + to.normalized() * 16.0
			r.dir = to.normalized()
			r.target = Game.heli
			r.dmg = GS_ROCKET_DMG
			Game.world.add_child(r)
			Sfx.play("explosion", global_position, -14.0)

	func _flare_near_heli() -> bool:
		return get_tree().get_nodes_in_group("rocket_decoys").any(func(f): return f.global_position.distance_to(Game.heli.global_position) < GS_FLARE_SEE)

	func _round(to: Vector2, d: float) -> void:
		var heli: Node2D = Game.heli
		var p := GS_CHANCE * (1.0 - 0.6 * clampf(d / GS_GUN_RANGE, 0.0, 1.0)) * (1.0 - 0.5 * clampf(heli.vel.length() / heli.MAX_SPEED, 0.0, 1.0))
		var hit_it := randf() < p
		tracer = to + (Vector2.ZERO if hit_it else Vector2(randf_range(-28, 28), randf_range(-28, 28)))
		tracer_t = 0.06
		Sfx.play("gun", global_position, -12.0)
		if hit_it:
			heli.take_damage(GS_ROUND_DMG, "bandit")

	func hit(amount: float, dir := Vector2.ZERO, _head := false) -> void:
		if is_queued_for_deletion():
			return
		hp -= amount
		sprite.modulate = Color(2.5, 2.5, 2.5)
		get_tree().create_timer(0.08).timeout.connect(unflash)
		HitFx.burst(global_position, dir, HitFx.SPARK, 3, 60.0)
		if hp <= 0.0:
			Game.kills += 1
			Game.add_xp(GS_XP)
			Game.world.spawn_fx(global_position, 2.2)
			Sfx.play("explosion", global_position)
			queue_free()
			Game.world.nemesis.gunship_down()

	func unflash() -> void:
		sprite.modulate = Color.WHITE

	func _draw() -> void:
		var f := clampf(hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(-18.0, -radius - 14.0, 36.0, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-18.0, -radius - 14.0, 36.0 * f, 3.0), Color(0.9, 0.25, 0.2))
		if tracer_t > 0.0:
			draw_line(Vector2.ZERO, tracer, Color(1.0, 0.85, 0.45, 0.85), 1.0)
		if aim_t > 0.0:
			draw_line(Vector2.ZERO, Game.heli.global_position - global_position, Color(1.0, 0.15, 0.1, 0.35 + 0.6 * aim_t / GS_AIM), 1.0 + aim_t)
