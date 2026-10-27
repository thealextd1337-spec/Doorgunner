extends RefCounted
## Level-up upgrade pool. roll(n) returns n distinct {name, desc, apply: Callable}.


static func roll(n: int) -> Array:
	var pool := [
		{"name": "Heavy Rounds", "desc": "+20% damage", "apply": _mul.bind("damage", 1.2)},
		{"name": "Rapid Fire", "desc": "+15% fire rate", "apply": _mul.bind("fire_rate", 1.15)},
		{"name": "Extended Tanks", "desc": "+25 fuel capacity, +25 fuel", "apply": _add.bind({"base_max_fuel": 25.0, "fuel": 25.0})},
		{"name": "Lean Burn", "desc": "+15% fuel efficiency", "apply": _mul.bind("fuel_eff", 1.15)},
		{"name": "Ammo Racks", "desc": "+60 ammo capacity, +60 ammo", "apply": _add.bind({"base_max_ammo": 60, "ammo": 60})},
		{"name": "Armor Plating", "desc": "+15% armor", "apply": _mul.bind("base_armor", 1.15)},
		{"name": "Tuned Engine", "desc": "+10% speed", "apply": _mul.bind("speed", 1.1)},
		{"name": "Extra Seat", "desc": "+1 passenger seat", "apply": _add.bind({"base_seats": 1})},
		{"name": "AP Rounds", "desc": "Bullets pierce +1 enemy", "apply": _add.bind({"pierce": 1})},
		{"name": "Twin Guns", "desc": "+1 bullet per shot", "apply": _add.bind({"shots": 1})},
		{"name": "High-Velocity", "desc": "+20% bullet speed", "apply": _mul.bind("bullet_speed", 1.2)},
		{"name": "Field Medic", "desc": "+25 max hull, fully repaired", "apply": _medic},
		{"name": "Veteran", "desc": "+20% XP gain", "apply": _mul.bind("xp_gain", 1.2)},
		{"name": "Salvage Crew", "desc": "+40 scrap now", "apply": _add.bind({"scrap": 40})},
	]
	if Game.stats["shots"] >= 3:
		pool = pool.filter(func(u: Dictionary) -> bool: return u["name"] != "Twin Guns")
	pool.shuffle()
	return pool.slice(0, n)


## Keys are Game.stats entries or plain Game properties (base_armor, ...).
static func _mul(key: String, f: float) -> void:
	if Game.stats.has(key):
		Game.stats[key] *= f
	else:
		Game.set(key, Game.get(key) * f)
	Game.recompute()


## Keys are Game.stats entries or plain Game properties (base_max_fuel, scrap, ...).
## base_* keys come first in the dictionaries above so recompute raises the cap before fuel/ammo top-ups.
static func _add(fields: Dictionary) -> void:
	for k in fields:
		if Game.stats.has(k):
			Game.stats[k] += fields[k]
		else:
			Game.set(k, Game.get(k) + fields[k])
		if k.begins_with("base_"):
			Game.recompute()


static func _medic() -> void:
	Game.max_hp += 25.0
	Game.hp = Game.max_hp
