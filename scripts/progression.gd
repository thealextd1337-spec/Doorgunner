class_name Progression
extends RefCounted
## Heli items (docs/PROGRESSION.md): slot types, five levels each, meta unlocks.
## Game.heli_items holds id -> level; apply_all() derives Game.stats, Game.slots and the heli's system nodes from it.
## Weapons are "hardpoint" items: Game.heli_weapons / weapon_bay stay their storage, heli.gd reads their level.

const ITEMS := {
	"mg": {"name": "Door MG", "slot": "hardpoint", "desc": "Reliable all-rounder.", "per_level": ["Mount the Door MG", "+12 % damage", "+24 % damage", "+36 % damage", "Twin MG: two tracers per shot"], "unlock": null},
	"minigun": {"name": "Minigun", "slot": "hardpoint", "desc": "Hose of lead, spread grows while firing.", "per_level": ["Mount the Minigun", "+10 % fire rate", "+20 % fire rate", "+30 % fire rate", "No overheating: spread stays tight"], "unlock": null},
	"autocannon": {"name": "Autocannon", "slot": "hardpoint", "desc": "Slow heavy shells that punch through.", "per_level": ["Mount the Autocannon", "+15 % damage", "+30 % damage", "+45 % damage", "Explosive shells: small splash"], "unlock": {"kind": "rescued", "value": 50}},
	"shotgun": {"name": "Flak Gun", "slot": "hardpoint", "desc": "Pellet blast, 20 m reach.", "per_level": ["Mount the Flak Gun", "+1 pellet", "+2 pellets", "+3 pellets", "Double cone: twice the pellets"], "unlock": {"kind": "assaults", "value": 6}},
	"rockets": {"name": "Rocket Pod", "slot": "hardpoint", "desc": "Splash damage on impact.", "per_level": ["Mount the Rocket Pod", "+15 % blast radius", "+30 % blast radius", "+45 % blast radius", "Salvo: 3 rockets per trigger"], "unlock": {"kind": "bosses", "value": 10}},
	"railgun": {"name": "Railgun", "slot": "hardpoint", "desc": "Pierces everything in a line.", "per_level": ["Mount the Railgun", "+20 % damage", "+40 % damage", "+60 % damage", "Chain bolt: jumps to 2 more targets"], "unlock": {"kind": "day", "value": 20}},
	"searchlight": {"name": "Searchlight", "slot": "system", "desc": "Light cone ahead. At night zombies in it slow down and POIs show up.", "per_level": ["17 m cone, -30 % zombie speed", "20 m cone, -35 %", "23 m cone, -40 %", "26 m cone, -45 %", "Blinding: zombies in the cone freeze 2 s"], "unlock": null},
	"flares": {"name": "Flares", "slot": "system", "desc": "Drops a burning flare whose noise lures zombies away.", "per_level": ["Flare every 20 s, burns 8 s", "Every 17.5 s, burns 9 s", "Every 15 s, burns 10 s", "Every 12.5 s, burns 11 s", "Two flares, zombies attack them"], "unlock": {"kind": "rescued", "value": 50}},
	"loudspeaker": {"name": "Loudspeaker", "slot": "system", "desc": "[F] blares noise that pulls zombies to you, out of a settlement.", "per_level": ["Pull radius 60 m", "Pull radius 70 m", "Pull radius 80 m", "Pull radius 90 m", "Panic: zombies flee for 5 s"], "unlock": {"kind": "assaults", "value": 6}},
	"winch": {"name": "Winch", "slot": "system", "desc": "Hover slowly over survivors to hoist them aboard without landing.", "per_level": ["One survivor every 6 s", "Every 5.3 s", "Every 4.5 s", "Every 3.8 s", "Two at a time, every 3 s"], "unlock": {"kind": "rescued", "value": 100}},
	"cogunner": {"name": "Co-gunner", "slot": "system", "desc": "Second gunner shoots the nearest zombie in any direction, uses 1 ammo per 3 shots.", "per_level": ["40 % damage, 23 m reach", "45 % damage, 26 m", "50 % damage, 29 m", "55 % damage, 32 m", "Takes over the main gun at 80 %"], "unlock": null},
	"medic": {"name": "Medic", "slot": "system", "desc": "Patches the hull while you fly.", "per_level": ["+1 hull/s in flight", "+1.5 hull/s", "+2 hull/s", "+2.5 hull/s", "+3 hull/s, also when landed"], "unlock": {"kind": "rescued", "value": 100}},
	"supply": {"name": "Supply Drop", "slot": "system", "desc": "Command drops a supply crate on your position now and then.", "per_level": ["Crate every 90 s, 40 % of a cache", "Every 80 s, 50 %", "Every 70 s, 60 %", "Every 60 s, 70 %", "Every 50 s, 80 %, plus scrap"], "unlock": {"kind": "bosses", "value": 10}},
	"engine": {"name": "Engine", "slot": "module", "desc": "Turbine tuning.", "per_level": ["+6 % top speed", "+12 % top speed", "+18 % top speed", "+24 % top speed", "+30 %, landing spool halved"], "unlock": null},
	"plating": {"name": "Armor", "slot": "module", "desc": "Bolt-on armour plates.", "per_level": ["+8 % armour", "+16 % armour", "+24 % armour", "+32 % armour", "+40 %, zombie ram damage halved"], "unlock": null},
	"leanburn": {"name": "Lean Burn", "slot": "module", "desc": "Leaner fuel mixture.", "per_level": ["+8 % fuel efficiency", "+16 % fuel efficiency", "+24 % fuel efficiency", "+32 % fuel efficiency", "+40 %, deliveries refill 10 % fuel"], "unlock": null},
	"ammobelts": {"name": "Ammo Belts", "slot": "module", "desc": "Extra belts in the cabin.", "per_level": ["+40 max ammo", "+80 max ammo", "+120 max ammo", "+160 max ammo", "+200, deliveries return 20 % ammo"], "unlock": null},
	"training": {"name": "Gunnery", "slot": "module", "desc": "Gunner drills.", "per_level": ["+8 % fire rate", "+16 % fire rate", "+24 % fire rate", "+32 % fire rate", "+40 %, first shot after a pause crits x2"], "unlock": null},
	"hardcore": {"name": "Hard Core", "slot": "module", "desc": "Hardened rounds.", "per_level": ["+1 pierce, +10 % bullet speed", "+20 % bullet speed", "+2 pierce, +30 % bullet speed", "+40 % bullet speed", "+3 pierce, bullets ricochet once"], "unlock": {"kind": "day", "value": 20}},
	"cabin": {"name": "Cabin", "slot": "module", "desc": "Cabin refit for passengers.", "per_level": ["+1 seat, +10 % boarding speed", "+20 % boarding speed", "+2 seats, +30 % boarding", "+40 % boarding speed", "+3 seats, civilians board twice as fast"], "unlock": null},
	"veteran": {"name": "Veteran", "slot": "module", "desc": "Experienced crew.", "per_level": ["+10 % XP", "+20 % XP", "+30 % XP", "+40 % XP", "+50 % XP, level-ups offer 4 cards"], "unlock": {"kind": "runs", "value": 20}},
	"scavenger": {"name": "Scavenger", "slot": "module", "desc": "Salvage crew picks the dead clean.", "per_level": ["+15 % scrap from kills", "+30 % scrap", "+45 % scrap", "+60 % scrap", "+75 %, zombie drops give ammo"], "unlock": {"kind": "runs", "value": 20}},
	"optics": {"name": "Optics", "slot": "module", "desc": "Gun sights for long shots.", "per_level": ["+10 % range", "+20 % range", "+30 % range", "+40 % range", "+50 %, hits in the outer third +50 % damage"], "unlock": null},
}
const SLOT_TYPES := ["hardpoint", "system", "module"]
const META_KEYS := {"rescued": "total_rescued", "assaults": "assaults_held", "bosses": "boss_kills", "day": "best_day", "runs": "runs"}
const BASE_STATS := {
	"damage": 1.0, "fire_rate": 1.0, "speed": 1.0, "fuel_eff": 1.0, "armor": 1.0, "pierce": 0, "shots": 1,
	"bullet_speed": 1.0, "xp_gain": 1.0, "range": 1.0, "seats": 0, "max_ammo": 0, "scrap_gain": 1.0, "spool": 1.0, "board": 1.0,
}
const CARD_SCRAP := 20 # value of one card; scrapping an item refunds half


## Level of an item, 0 if never taken (bay weapons keep theirs).
static func level(id: String) -> int:
	return Game.heli_items.get(id, 0)


## Fitted to the heli right now: weapons must be mounted, everything else just taken.
static func owned(id: String) -> bool:
	return id in Game.heli_weapons if ITEMS[id]["slot"] == "hardpoint" else Game.heli_items.has(id)


static func used(slot: String) -> int:
	return ITEMS.keys().filter(func(id: String) -> bool: return ITEMS[id]["slot"] == slot and owned(id)).size()


static func unlocked(id: String) -> bool:
	var u = ITEMS[id]["unlock"]
	return u == null or Game.meta[META_KEYS[u["kind"]]] >= u["value"]


## "25 rescued (12/25)" for the title hangar.
static func condition(id: String) -> String:
	var u = ITEMS[id]["unlock"]
	if u == null:
		return "always"
	var word: String = {"rescued": "rescued", "assaults": "assaults held", "bosses": "boss kills", "day": "reach day", "runs": "runs played"}[u["kind"]]
	return "%s %d (%d/%d)" % [word, u["value"], Game.meta[META_KEYS[u["kind"]]], u["value"]]


static func can_banish() -> bool:
	return Game.meta["total_rescued"] >= 200 and Game.banished.size() < 3


## Recompute from scratch: stats from item levels, slots from workshop + meta, system nodes on the heli.
static func apply_all() -> void:
	Game.stats.merge(BASE_STATS, true)
	for id in Game.heli_items:
		if owned(id):
			apply(id, Game.heli_items[id])
	var ws: int = Game.base_level.get("workshop", 0)
	var m: Dictionary = Game.meta
	var extra := {"hardpoint": ws >= 2 or m["best_day"] >= 5, "system": ws >= 3 or m["best_day"] >= 15, "module": ws >= 4 or m["total_rescued"] >= 300} # workshop 1 is the stock one
	for k in SLOT_TYPES:
		Game.slots[k] = Game.MAX_SLOTS[k] if extra[k] else Game.START_SLOTS[k]
	if is_instance_valid(Game.heli):
		Game.heli.refresh_systems()


## Module effects on Game.stats. Weapons and systems read their level live instead.
static func apply(id: String, lv: int) -> void:
	var s: Dictionary = Game.stats
	match id:
		"engine":
			s["speed"] *= 1.0 + 0.06 * lv
			s["spool"] = 0.5 if lv >= 5 else 1.0
		"plating":
			s["armor"] *= (1.0 + 0.08 * lv) * (2.0 if lv >= 5 else 1.0) # only zombie rams hurt the heli, so halving them = double armour
		"leanburn": s["fuel_eff"] *= 1.0 + 0.08 * lv
		"ammobelts": s["max_ammo"] += 40 * lv
		"training": s["fire_rate"] *= 1.0 + 0.08 * lv
		"hardcore":
			s["pierce"] += (lv + 1) / 2
			s["bullet_speed"] *= 1.0 + 0.1 * lv
		"cabin":
			s["seats"] += (lv + 1) / 2
			s["board"] = 2.0 if lv >= 5 else 1.0 + 0.1 * lv
		"veteran": s["xp_gain"] *= 1.0 + 0.1 * lv
		"scavenger": s["scrap_gain"] *= 1.0 + 0.15 * lv
		"optics": s["range"] *= 1.0 + 0.1 * lv


## Lv5 Lean Burn / Ammo Belts: every passenger delivery at base tops up a share of the tanks for free.
static func on_delivery() -> void:
	if level("leanburn") >= 5:
		Game.fuel = minf(Game.max_fuel, Game.fuel + Game.max_fuel * 0.1)
	if level("ammobelts") >= 5:
		Game.ammo = mini(Game.max_ammo, Game.ammo + Game.max_ammo / 5)


## HUD line: "[Door MG 3] [Searchlight 2][ - ] [Engine 2][ - ][ - ]".
static func slot_line() -> String:
	var parts := []
	for slot in SLOT_TYPES:
		var s := ""
		var ids: Array = Game.heli_weapons if slot == "hardpoint" else ITEMS.keys().filter(func(id: String) -> bool: return ITEMS[id]["slot"] == slot and owned(id))
		for id in ids:
			s += "[%s %d]" % [ITEMS[id]["name"], level(id)]
		for i in Game.slots[slot] - ids.size():
			s += "[ - ]"
		parts.append(s)
	return " ".join(parts)
