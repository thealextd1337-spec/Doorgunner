extends RefCounted
## Door gun variants. heli.gd reads TABLE[Game.weapon]; Game.stats multipliers apply on top.
## range = world px a bullet travels before it fizzles (10 px = 1 m). Optional: splash (radius px, default 0).

const TABLE := {
	"mg": {"name": "Door MG", "desc": "Reliable all-rounder.", "damage": 14.0, "interval": 0.18, "shots": 1, "spread_deg": 4.0, "range": 420.0, "bullet_speed": 520.0, "pierce": 0, "ammo_per_shot": 1, "max_ammo_bonus": 0},
	"minigun": {"name": "Minigun", "desc": "Hose of lead, eats ammo.", "damage": 6.0, "interval": 0.06, "shots": 1, "spread_deg": 10.0, "range": 320.0, "bullet_speed": 560.0, "pierce": 0, "ammo_per_shot": 1, "max_ammo_bonus": 120},
	"autocannon": {"name": "Autocannon", "desc": "Slow heavy shells that punch through.", "damage": 45.0, "interval": 0.55, "shots": 1, "spread_deg": 2.0, "range": 620.0, "bullet_speed": 420.0, "pierce": 1, "ammo_per_shot": 2, "max_ammo_bonus": 0},
	"shotgun": {"name": "Flak Gun", "desc": "Six-pellet blast, 20 m reach.", "damage": 7.0, "interval": 0.7, "shots": 6, "spread_deg": 22.0, "range": 200.0, "bullet_speed": 600.0, "pierce": 0, "ammo_per_shot": 2, "max_ammo_bonus": 0},
	"rockets": {"name": "Rocket Pod", "desc": "Splash damage on impact.", "damage": 90.0, "interval": 1.4, "shots": 1, "spread_deg": 3.0, "range": 520.0, "bullet_speed": 380.0, "pierce": 0, "ammo_per_shot": 5, "max_ammo_bonus": 0, "splash": 60.0},
	"railgun": {"name": "Railgun", "desc": "Pierces everything in a line.", "damage": 120.0, "interval": 1.2, "shots": 1, "spread_deg": 0.5, "range": 900.0, "bullet_speed": 1400.0, "pierce": 99, "ammo_per_shot": 4, "max_ammo_bonus": 0},
}


## Weapon ids the player owns neither aboard nor in the bay.
static func unowned() -> Array:
	return TABLE.keys().filter(func(id: String) -> bool: return id not in Game.heli_weapons and id not in Game.weapon_bay)
