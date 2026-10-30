extends RefCounted
## Heli types (docs/ROADMAP.md P15): base values per airframe; items and loadout build on top (Progression.apply_all calls apply()).
## seats/hardpoints replace the Huey's (4 / 1), speed/armor/spool/noise multiply. twin: both mounted guns fire at once (heli.gd).
## sling: top speed left with a wreck on the hook (wrecks.gd). sites: wreck odds per landmark kind -> type weights.
## cost: the HANGAR repair project at wreck condition 50 % (wrecks.gd scales it), keys: key parts, days: work days of a mechanic.

const TYPES := {
	"huey": {"name": "Huey", "role": "all-rounder", "seats": 4, "hardpoints": 1, "speed": 1.0, "armor": 1.0, "spool": 1.0, "noise": 1.0,
		"twin": false, "sling": 0.5, "evac": 1.0, "size": 1.0, "tint": Color(1, 1, 1),
		"cost": {"metal": 160, "parts": 100, "electronics": 50}, "keys": 1, "days": 12},
	"little_bird": {"name": "Little Bird", "role": "scout", "seats": 2, "hardpoints": 1, "speed": 1.35, "armor": 0.6, "spool": 0.6, "noise": 0.5,
		"twin": false, "sling": 0.5, "evac": 1.0, "size": 0.8, "tint": Color(0.75, 0.8, 0.95),
		"cost": {"metal": 120, "parts": 80, "electronics": 50}, "keys": 1, "days": 10},
	"black_hawk": {"name": "Black Hawk", "role": "gunship transport", "seats": 8, "hardpoints": 2, "speed": 0.95, "armor": 1.4, "spool": 1.0, "noise": 1.0,
		"twin": true, "sling": 0.5, "evac": 1.0, "size": 1.15, "tint": Color(0.6, 0.65, 0.6),
		"cost": {"metal": 200, "parts": 120, "electronics": 60}, "keys": 2, "days": 15},
	"chinook": {"name": "Chinook", "role": "heavy lift", "seats": 14, "hardpoints": 1, "speed": 0.75, "armor": 1.2, "spool": 1.2, "noise": 1.0,
		"twin": false, "sling": 0.85, "evac": 1.5, "size": 1.35, "tint": Color(0.85, 0.85, 0.7),
		"cost": {"metal": 240, "parts": 140, "electronics": 60}, "keys": 2, "days": 18},
	"hind": {"name": "Hind", "role": "gunship", "seats": 4, "hardpoints": 3, "speed": 0.9, "armor": 1.7, "spool": 1.1, "noise": 1.0,
		"twin": false, "sling": 0.5, "evac": 1.0, "size": 1.25, "tint": Color(0.75, 0.7, 0.55),
		"cost": {"metal": 260, "parts": 160, "electronics": 80}, "keys": 3, "days": 20},
}
const SITES := {
	"airfield": {"odds": 1.0, "types": {"huey": 40, "little_bird": 35, "black_hawk": 15, "chinook": 10}},
	"checkpoint": {"odds": 0.5, "types": {"huey": 25, "black_hawk": 40, "chinook": 20, "hind": 15}}, # the Hind only at military landmarks
	"airliner": {"odds": 0.6, "types": {"huey": 40, "little_bird": 30, "chinook": 20, "black_hawk": 10}},
}
const KEY_PARTS := {"rotor_head": "rotor head", "turbine": "turbine", "avionics": "avionics"}


static func get_type(id: String) -> Dictionary:
	return TYPES.get(id, TYPES["huey"]) # unknown ids (newer saves) fly as a Huey


## Progression.apply_all: the active type's base values into Game.stats / Game.slots.
static func apply(id: String, stats: Dictionary, slots: Dictionary) -> void:
	var t := get_type(id)
	stats["speed"] *= t["speed"]
	stats["armor"] *= t["armor"]
	stats["spool"] *= t["spool"]
	stats["seats"] += t["seats"] - 4 # loadout seats start at the Huey's 4
	slots["hardpoint"] += t["hardpoints"] - 1
