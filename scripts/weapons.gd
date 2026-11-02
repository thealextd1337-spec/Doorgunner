extends RefCounted
## Door gun variants. heli.gd reads TABLE[Game.weapon]; Game.stats multipliers apply on top.
## range = world px a bullet travels before it fizzles (10 px = 1 m). Optional: splash (radius px, default 0).
## Q8 optional keys, copied onto the bullet by tune(): burn (dps) / burn_s (seconds), falloff (damage lost at max range, 0..1),
## lob (shell flies to the aim point and bursts there), stun (seconds), push (px/s shove), reach (px added to the bullet's hit radius),
## head (extra headshot chance), sprite (Art name of the projectile).

const TABLE := {
	"mg": {"name": "Door MG", "desc": "Reliable all-rounder.", "damage": 14.0, "interval": 0.18, "shots": 1, "spread_deg": 4.0, "range": 420.0, "bullet_speed": 520.0, "pierce": 0, "ammo_per_shot": 1, "max_ammo_bonus": 0},
	"minigun": {"name": "Minigun", "desc": "Hose of lead, eats ammo.", "damage": 6.0, "interval": 0.06, "shots": 1, "spread_deg": 10.0, "range": 320.0, "bullet_speed": 560.0, "pierce": 0, "ammo_per_shot": 1, "max_ammo_bonus": 120},
	"autocannon": {"name": "Autocannon", "desc": "Slow heavy shells that punch through.", "damage": 45.0, "interval": 0.55, "shots": 1, "spread_deg": 2.0, "range": 620.0, "bullet_speed": 420.0, "pierce": 1, "ammo_per_shot": 2, "max_ammo_bonus": 0},
	"shotgun": {"name": "Flak Gun", "desc": "Six-pellet blast, 20 m reach.", "damage": 7.0, "interval": 0.7, "shots": 6, "spread_deg": 22.0, "range": 200.0, "bullet_speed": 600.0, "pierce": 0, "ammo_per_shot": 2, "max_ammo_bonus": 0},
	"rockets": {"name": "Rocket Pod", "desc": "Splash damage on impact.", "damage": 90.0, "interval": 1.4, "shots": 1, "spread_deg": 3.0, "range": 520.0, "bullet_speed": 380.0, "pierce": 0, "ammo_per_shot": 5, "max_ammo_bonus": 0, "splash": 60.0},
	"railgun": {"name": "Railgun", "desc": "Pierces everything in a line.", "damage": 120.0, "interval": 1.2, "shots": 1, "spread_deg": 0.5, "range": 900.0, "bullet_speed": 1400.0, "pierce": 99, "ammo_per_shot": 4, "max_ammo_bonus": 0},
	"scatter": {"name": "Scatter Gun", "desc": "Ten wide pellets, deadly up close, weak at range.", "damage": 6.0, "interval": 0.9, "shots": 10, "spread_deg": 30.0, "range": 140.0, "bullet_speed": 560.0, "pierce": 0, "ammo_per_shot": 3, "max_ammo_bonus": 0, "falloff": 0.65},
	"flamer": {"name": "Flamethrower", "desc": "Short-range fire stream, sets zombies burning.", "damage": 4.0, "interval": 0.08, "shots": 1, "spread_deg": 16.0, "range": 110.0, "bullet_speed": 240.0, "pierce": 99, "ammo_per_shot": 1, "max_ammo_bonus": 0, "burn": 8.0, "burn_s": 3.0, "sprite": "flame"},
	"grenade": {"name": "Grenade Launcher", "desc": "Lobbed shell bursts where you aim.", "damage": 70.0, "interval": 1.1, "shots": 1, "spread_deg": 0.0, "range": 420.0, "bullet_speed": 230.0, "pierce": 0, "ammo_per_shot": 4, "max_ammo_bonus": 0, "splash": 55.0, "lob": true, "sprite": "shell"},
	"marksman": {"name": "Precision Rifle", "desc": "One slow, hard shot through two targets. Aims for the head.", "damage": 80.0, "interval": 0.9, "shots": 1, "spread_deg": 0.3, "range": 1000.0, "bullet_speed": 1500.0, "pierce": 2, "ammo_per_shot": 2, "max_ammo_bonus": 0, "head": 0.2},
	"sonic": {"name": "Sonic Cannon", "desc": "Shockwave that stuns and shoves everything in a cone.", "damage": 4.0, "interval": 0.8, "shots": 1, "spread_deg": 0.0, "range": 160.0, "bullet_speed": 220.0, "pierce": 99, "ammo_per_shot": 3, "max_ammo_bonus": 0, "stun": 0.8, "reach": 16.0, "push": 150.0, "sprite": "wave"},
	"net": {"name": "Net Launcher", "desc": "Net shell roots zombies in its burst for a few seconds.", "damage": 3.0, "interval": 1.6, "shots": 1, "spread_deg": 2.0, "range": 380.0, "bullet_speed": 380.0, "pierce": 0, "ammo_per_shot": 3, "max_ammo_bonus": 0, "splash": 45.0, "stun": 2.0, "lob": true, "sprite": "shell"},
}


## Weapon ids the player owns neither aboard nor in the bay and has unlocked (meta), so caches and wrecks only hand out those.
static func unowned() -> Array:
	return TABLE.keys().filter(func(id: String) -> bool: return id not in Game.heli_weapons and id not in Game.weapon_bay and Progression.unlocked(id))


## Per-level scaling of the Q8 guns (heli.gd multiplies/adds these). Level 5 specials are in tune().
static func level_mods(id: String, lv: int) -> Dictionary:
	var m := {"dmg": 1.0, "pellets": 0, "splash": 1.0}
	match id:
		"scatter": m["pellets"] = lv - 1
		"grenade": m["splash"] = 1.0 + 0.15 * (lv - 1)
		"marksman": m["dmg"] = 1.0 + 0.15 * (lv - 1)
		"sonic": m["dmg"] = (1.0 + 0.25 * (lv - 1)) * (4.0 if lv >= 5 else 1.0)
		"net": m["splash"] = 2.0 if lv >= 5 else 1.0
	return m


## Copies the weapon's special properties onto a freshly set-up bullet. `aim_dist`: how far the lobbed shell flies.
static func tune(b: Node2D, id: String, lv: int, aim_dist: float) -> void:
	var w: Dictionary = TABLE[id]
	b.burn = w.get("burn", 0.0) * (1.0 + 0.15 * (lv - 1) if id == "flamer" else 1.0)
	b.burn_s = w.get("burn_s", 3.0)
	b.falloff = w.get("falloff", 0.0)
	b.stun = w.get("stun", 0.0) + (0.2 * (lv - 1) if id == "sonic" else 0.5 * (lv - 1) if id == "net" else 0.0)
	b.reach = w.get("reach", 0.0)
	b.push = w.get("push", 0.0)
	b.head_bonus = w.get("head", 0.0)
	b.art = w.get("sprite", "bullet")
	b.lob_dist = aim_dist if w.get("lob", false) else 0.0
	if lv >= 5:
		match id:
			"scatter": # dragon's breath
				b.burn = 4.0
			"flamer": # fire jumps to neighbours
				b.burn_spread = true
			"marksman":
				b.head_bonus = 0.5
				b.pierce += 2
