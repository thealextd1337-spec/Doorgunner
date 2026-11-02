extends Node
## Headless test of the Q8 arsenal (scripts/weapons.gd, progression.gd, burn.gd, systems/thermal.gd, smoke.gd). SMOKE=arsenal:
##   SMOKE=arsenal godot --headless --path . --quit-after 30000
## Tables and unlocks, an old-style save, each new gun through heli._fire() on frozen zombies, each item, a save with every new item.
## The node moves itself under the root so it survives the scene reloads; the copy main.gd adds after it frees itself.

const NAME := "ArsenalTest"
const Weapons := preload("res://scripts/weapons.gd")
const BulletScript := preload("res://scripts/bullet.gd")
const NEW_GUNS := ["scatter", "flamer", "grenade", "marksman", "sonic", "net"]
const NEW_ITEMS := ["thermal", "smoke", "extratank", "heavyplates"]


class FakeRocket extends Node2D:
	var life := 3.0


var main: Node2D
var heli: Node2D
var frame: Signal


func _ready() -> void:
	if get_tree().root.has_node(NAME):
		queue_free()
		return
	Engine.max_fps = 120
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await frame


func _attach() -> void:
	main = Game.world
	heli = Game.heli


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()


## Quiet ground around the heli, no spawner, no other zombies, midday.
func _arena() -> void:
	_clear_enemies()
	for b in get_tree().get_nodes_in_group("rockets"):
		b.queue_free()
	main.spawner.horde_cd = 1e9
	main.spawner.set_process(false)
	Game.time = 0.5
	heli.landed = false
	heli.position = main.BASE_POS + Vector2(400, 0)
	heli.vel = Vector2.ZERO
	heli.body.rotation = 0.0 # nose north: east is a door side
	heli.aim_override = Vector2.RIGHT
	for c in 100:
		for r in 20:
			main.chunks.set_cell(Vector2i((heli.position / 16.0).floor()) + Vector2i(c - 4, r - 10), 0, Vector2i(0, 0))


## A frozen zombie `dx`/`dy` px east/south of the heli that can be stunned right away.
func _z(dx: float, dy := 0.0, kind := "shambler") -> Node2D:
	var e: Node2D = main.spawn_enemy(kind, heli.position + Vector2(dx, dy))
	e.hp = 1e6
	e.max_hp = 1e6
	e.stun_left = -5.0
	e.set_process(false)
	e.set_physics_process(false)
	return e


func _equip(id: String, lv: int) -> void:
	Game.heli_weapons.clear()
	Game.heli_weapons.append(id)
	Game.weapon = id
	Game.heli_items[id] = lv
	Game.recompute()
	Game.ammo = Game.max_ammo
	heli.fire_cd = 0.0


func _bullets() -> Array:
	return main.get_children().filter(func(c: Node) -> bool: return c.get_script() == BulletScript and not c.is_queued_for_deletion())


func _clear_bullets() -> void:
	for b in _bullets():
		b.queue_free()


func _lost(z: Node2D) -> float:
	return z.max_hp - z.hp


func _run() -> void:
	reparent(get_tree().root)
	name = NAME
	frame = get_tree().process_frame
	await _frames(2)
	_attach()
	_tables()
	# --- an old-style save (only the Door MG) loads with the new code
	_arena()
	Save.delete_run()
	var fuel0 := Game.max_fuel
	assert(Save.autosave(), "old-style save written")
	Save.pending = true
	get_tree().reload_current_scene()
	await _frames(3)
	_attach()
	assert(Game.running and Game.heli_items == {"mg": 1}, "old save loaded: %s" % Game.heli_items)
	assert(is_equal_approx(Game.max_fuel, fuel0) and Game.stats["tank"] == 0.0 and Game.stats["weight"] == 0, "no Q8 stat leaks into an old run")
	Save.delete_run()
	# --- guns
	_arena()
	await _scatter()
	await _flamer()
	await _grenade()
	await _marksman()
	await _sonic()
	await _net()
	# --- items
	await _thermal()
	await _smoke()
	_modules()
	# --- everything taken, saved, reloaded
	_clear_enemies()
	_clear_bullets()
	await _frames(2)
	Game.heli_weapons.clear()
	Game.heli_weapons.append("mg")
	Game.weapon = "mg"
	Game.heli_items = {"mg": 1}
	Game.weapon_bay.clear()
	for id in NEW_GUNS:
		Game.heli_items[id] = 3
		Game.weapon_bay.append(id)
	for id in NEW_ITEMS:
		Game.heli_items[id] = 3 if id != "smoke" else 5
	Game.recompute()
	var want := {"items": var_to_str(Game.heli_items), "bay": var_to_str(Game.weapon_bay), "fuel": Game.max_fuel, "weight": Game.weight_factor, "armor": Game.stats["armor"]}
	assert(Save.autosave(), "full save written")
	Save.pending = true
	get_tree().reload_current_scene()
	await _frames(3)
	_attach()
	assert(Game.running and var_to_str(Game.heli_items) == want["items"], "items restored: %s" % Game.heli_items)
	assert(var_to_str(Game.weapon_bay) == want["bay"] and Game.weapon_bay.get_typed_builtin() == TYPE_STRING, "bay restored")
	assert(is_equal_approx(Game.max_fuel, want["fuel"]) and is_equal_approx(Game.weight_factor, want["weight"]) and is_equal_approx(Game.stats["armor"], want["armor"]), "stats derived again")
	assert(heli.has_node("thermal") and heli.has_node("smoke"), "system nodes rebuilt on the heli")
	Save.delete_run()
	print("ARSENAL OK  guns=%d items=%d" % [NEW_GUNS.size(), NEW_ITEMS.size()])
	get_tree().quit(0)


func _tables() -> void:
	for id in NEW_GUNS:
		var w: Dictionary = Weapons.TABLE[id]
		for k in ["name", "desc", "damage", "interval", "shots", "spread_deg", "range", "bullet_speed", "pierce", "ammo_per_shot", "max_ammo_bonus"]:
			assert(w.has(k), "%s has %s" % [id, k])
		assert(Progression.ITEMS[id]["slot"] == "hardpoint", "%s is a hardpoint item" % id)
	for id in NEW_GUNS + NEW_ITEMS:
		var it: Dictionary = Progression.ITEMS[id]
		assert(it["per_level"].size() == 5 and it["desc"] != "" and it["unlock"] != null and Progression.META_KEYS.has(it["unlock"]["kind"]), "%s has tooltip text and a meta unlock" % id)
		assert(ResourceLoader.exists("res://assets/sprites/b/icon_%s.png" % id), "%s has an icon" % id)
		assert(Progression.condition(id).contains("("), "hangar shows the condition of %s" % id)
		if it["slot"] == "system":
			assert(ResourceLoader.exists("res://scripts/systems/%s.gd" % id), "system script for %s" % id)
	for id in Weapons.TABLE:
		assert(Progression.ITEMS.has(id), "%s is a progression item" % id)
	for spr in ["flame", "shell", "wave"]:
		assert(ResourceLoader.exists("res://assets/sprites/b/%s.png" % spr), "projectile sprite " + spr)
	# unlocks: locked just below the threshold, open at it
	var meta0: Dictionary = Game.meta.duplicate()
	for id in NEW_GUNS + NEW_ITEMS:
		var u: Dictionary = Progression.ITEMS[id]["unlock"]
		var key: String = Progression.META_KEYS[u["kind"]]
		Game.meta[key] = u["value"] - 1
		assert(not Progression.unlocked(id), "%s locked below its threshold" % id)
		Game.meta[key] = u["value"]
		assert(Progression.unlocked(id), "%s open at its threshold" % id)
		Game.meta[key] = meta0[key]
	# caches and wrecks (poi.gd) draw from Weapons.unowned(): never a gun still locked by meta
	for k in Progression.META_KEYS.values():
		Game.meta[k] = 0
	var owned0: Array = [Game.heli_weapons.duplicate(), Game.weapon_bay.duplicate()]
	Game.heli_weapons.assign(["mg"])
	Game.weapon_bay.clear()
	var pool: Array = Weapons.unowned()
	assert(not pool.is_empty() and pool.all(func(id): return Progression.unlocked(id)), "unowned() holds only unlocked guns: %s" % [pool])
	assert(not pool.has("flamer"), "a locked Flamethrower never comes from a cache")
	var fu: Dictionary = Progression.ITEMS["flamer"]["unlock"]
	Game.meta[Progression.META_KEYS[fu["kind"]]] = fu["value"]
	assert(Weapons.unowned().has("flamer"), "unlocked and unowned: the Flamethrower can come from a cache")
	Game.heli_weapons.assign(owned0[0])
	Game.weapon_bay.assign(owned0[1])
	Game.meta = meta0


func _scatter() -> void:
	_equip("scatter", 1)
	var z := _z(60)
	heli._fire()
	var bs := _bullets()
	assert(bs.size() == 10, "scatter fires 10 pellets: %d" % bs.size())
	var lo := 9.0
	var hi := -9.0
	for b in bs:
		lo = minf(lo, b.dir.angle())
		hi = maxf(hi, b.dir.angle())
		assert(b.falloff > 0.0, "pellets lose damage with range")
	assert(rad_to_deg(hi - lo) > 40.0, "wide cone: %.0f deg" % rad_to_deg(hi - lo))
	_clear_bullets()
	z.queue_free()
	# falloff: the same pellet hurts less far away (best of 4 so a lucky headshot cannot fool the test)
	var near := 1e9
	var far := 1e9
	for pair in [[40.0, 0], [130.0, 1]]:
		for i in 4:
			var t := _z(pair[0])
			var b: Node2D = BulletScript.new()
			b.setup(heli.global_position, Vector2.RIGHT, 10.0, 0, 560.0, 140.0 / 560.0)
			b.falloff = 0.65
			main.add_child(b)
			await _frames(40)
			if pair[1] == 0:
				near = minf(near, _lost(t))
			else:
				far = minf(far, _lost(t))
			t.queue_free()
	assert(near > 7.0 and far > 2.0 and near > far * 1.6, "falloff: near %.1f vs far %.1f" % [near, far])
	_equip("scatter", 3)
	heli._fire()
	assert(_bullets().size() == 12, "Lv3: +2 pellets: %d" % _bullets().size())
	_clear_bullets()
	_equip("scatter", 5)
	heli._fire()
	var bs5 := _bullets()
	assert(bs5.size() == 14 and bs5[0].burn > 0.0, "Lv5: 14 pellets, dragon's breath: %d" % bs5.size())
	_clear_bullets()


func _flamer() -> void:
	_equip("flamer", 1)
	var near := _z(80)
	var far := _z(170)
	for i in 80:
		Game.ammo = Game.max_ammo
		heli._fire()
		await frame
	assert(near.has_node("Burn") and _lost(near) > 10.0, "flame hits and ignites: lost %.1f" % _lost(near))
	assert(_lost(far) == 0.0 and not far.has_node("Burn"), "11 m reach only")
	await _frames(40) # the last bullets are gone
	var hp: float = near.hp
	await _frames(240)
	assert(hp - near.hp > 6.0, "burning keeps hurting after the stream stops: %.1f" % (hp - near.hp))
	await _frames(300)
	assert(not near.has_node("Burn"), "the fire dies out")
	# Lv5: fire jumps to a neighbour that was never in the stream
	_equip("flamer", 5)
	var side := _z(80, 26)
	for i in 80:
		Game.ammo = Game.max_ammo
		heli._fire()
		await frame
	await _frames(150)
	assert(side.has_node("Burn"), "Lv5 wildfire spreads")
	_clear_bullets()
	_clear_enemies()
	await frame


func _grenade() -> void:
	_equip("grenade", 1)
	var hit := _z(heli.aim_dist())
	var beside := _z(heli.aim_dist(), 40)
	var under := _z(150) # in the flight path: the shell arcs over it
	var out := _z(heli.aim_dist(), 120)
	heli._fire()
	await _frames(260)
	assert(_lost(hit) > 60.0 and _lost(beside) > 60.0, "burst hurts everything in the blast: %.0f / %.0f" % [_lost(hit), _lost(beside)])
	assert(_lost(under) == 0.0 and _lost(out) == 0.0, "the shell flies over zombies and misses far ones")
	_equip("grenade", 4)
	heli._fire()
	assert(is_equal_approx(_bullets()[0].splash, 55.0 * 1.45), "+15 % blast radius per level")
	_clear_bullets()
	_equip("grenade", 5)
	heli._fire()
	assert(_bullets().size() == 3, "Lv5 cluster: 3 shells")
	_clear_bullets()
	_clear_enemies()
	await frame


func _marksman() -> void:
	_equip("marksman", 1)
	var line := [_z(200), _z(230), _z(260), _z(290)]
	heli._fire()
	await _frames(60)
	assert(_lost(line[0]) >= 79.0 and _lost(line[1]) >= 79.0 and _lost(line[2]) >= 79.0, "the rifle goes through three: %.0f %.0f %.0f" % [_lost(line[0]), _lost(line[1]), _lost(line[2])])
	assert(_lost(line[3]) == 0.0, "pierce 2 stops after the third")
	for z in line:
		z.queue_free()
	var far := _z(900)
	_equip("marksman", 1)
	heli._fire()
	await _frames(120)
	assert(_lost(far) >= 79.0, "90 m shot lands: %.0f" % _lost(far))
	far.queue_free()
	_equip("marksman", 5)
	heli._fire()
	var b: Node2D = _bullets()[0]
	assert(b.pierce == 4 and is_equal_approx(b.head_bonus, 0.5) and is_equal_approx(b.damage, 80.0 * 1.6), "Lv5 dead-eye: pierce %d, head %.2f, dmg %.0f" % [b.pierce, b.head_bonus, b.damage])
	_clear_bullets()


func _sonic() -> void:
	_equip("sonic", 1)
	var a := _z(60)
	var b := _z(100, 12)
	var c := _z(100, 70) # outside the wave
	heli._fire()
	await _frames(160)
	assert(a.stun_left > 0.5 and b.stun_left > 0.5, "the wave stuns everything in the cone: %.2f %.2f" % [a.stun_left, b.stun_left])
	assert(c.stun_left <= -5.0 and _lost(c) == 0.0, "but not beside it")
	assert(a.kick.length() > 20.0, "and shoves it")
	_clear_enemies()
	_equip("sonic", 5)
	var d := _z(60)
	heli._fire()
	await _frames(160)
	assert(_lost(d) > 12.0, "Lv5 resonance hits harder: %.1f" % _lost(d))
	_clear_enemies()
	await frame


func _net() -> void:
	_equip("net", 1)
	var d: float = heli.aim_dist()
	var a := _z(d)
	var b := _z(d, 30)
	var mid := _z(120)
	var out := _z(d, 110)
	var boss := _z(d, -30, "boss")
	heli._fire()
	await _frames(240)
	assert(a.stun_left > 1.5 and b.stun_left > 1.5, "the net roots zombies in the burst: %.2f %.2f" % [a.stun_left, b.stun_left])
	assert(mid.stun_left <= -5.0 and out.stun_left <= -5.0, "the shell flies over the rest")
	assert(boss.stun_left <= -5.0, "bosses shrug the net off")
	_equip("net", 3)
	heli._fire()
	assert(is_equal_approx(_bullets()[0].stun, 3.0), "+0.5 s per level: %.1f" % _bullets()[0].stun)
	_clear_bullets()
	_equip("net", 5)
	heli._fire()
	assert(is_equal_approx(_bullets()[0].splash, 90.0), "Lv5 doubles the net")
	_clear_bullets()
	_clear_enemies()
	await frame


func _thermal() -> void:
	_equip("mg", 1)
	Game.take_item("thermal")
	var t: Node2D = heli.get_node("thermal")
	Game.time = 0.0 # midnight
	var near := _z(150)
	var far := _z(260)
	var hidden := _z(120, 100)
	hidden.concealed = true
	await _frames(2)
	var seen: Array = t.seen()
	assert(near in seen and far not in seen and hidden not in seen, "Lv1 shows the zombie at 15 m only, not the one in the forest")
	Game.time = 0.5
	assert(t.seen().is_empty(), "off by day")
	Game.time = 0.0
	for i in 4:
		Game.take_item("thermal")
	assert(far in t.seen() and hidden in t.seen(), "Lv5 sees 26 m and into the forest")
	Game.time = 0.5
	_clear_enemies()
	await frame


func _smoke() -> void:
	Game.take_item("smoke")
	var sm: Node = heli.get_node("smoke")
	var z := _z(10)
	sm.cd = 0.0
	heli.damaged.emit(5.0, "")
	assert(sm.cd <= 0.0, "zombie damage does not pop the screen")
	var rocket := FakeRocket.new()
	rocket.add_to_group("rockets")
	rocket.position = heli.position + Vector2(120, 0)
	main.add_child(rocket)
	await _frames(3)
	assert(sm.cd > 20.0, "a rocket closing in pops the screen: cd %.1f" % sm.cd)
	rocket.position = heli.position + Vector2(20, 0) # it flies on into the smoke
	await _frames(3)
	assert(rocket.life <= 0.0, "the rocket loses its lock inside the smoke")
	assert(z.slowed >= 0.5, "zombies in the smoke slow down: %.2f" % z.slowed)
	assert(sm.pop() == null, "reloading")
	sm.cd = 0.0
	heli.damaged.emit(8.0, "bandit")
	assert(sm.cd > 20.0, "a bandit hit pops it too")
	rocket.queue_free()
	for i in 4:
		Game.take_item("smoke")
	sm.cd = 0.0
	z.stun_left = -5.0
	heli.damaged.emit(8.0, "rocket")
	await _frames(3)
	assert(z.stun_left > 1.0, "Lv5 smoke stuns zombies: %.2f" % z.stun_left)
	_clear_enemies()
	await frame


func _modules() -> void:
	Game.heli_items = {"mg": 1}
	Game.heli_weapons.clear()
	Game.heli_weapons.append("mg")
	Game.weapon = "mg"
	Game.recompute()
	var fuel := Game.max_fuel
	var armor: float = Game.stats["armor"]
	var speed := Game.weight_factor
	Game.take_item("extratank")
	assert(is_equal_approx(Game.max_fuel, fuel + 10.0), "Extra Tank Lv1: +10 fuel: %.1f" % (Game.max_fuel - fuel))
	for i in 4:
		Game.take_item("extratank")
	assert(is_equal_approx(Game.max_fuel, fuel + 60.0) and is_equal_approx(Game.stats["fuel_eff"], 1.1), "Extra Tank Lv5: +60, 10 % less burn")
	Game.take_item("heavyplates")
	assert(is_equal_approx(Game.stats["armor"], armor * 1.2) and is_equal_approx(Game.weight_factor, speed - 0.04), "Heavy Plates Lv1: +20 % armour, -4 % speed")
	for i in 4:
		Game.take_item("heavyplates")
	assert(is_equal_approx(Game.stats["armor"], armor * 2.5) and is_equal_approx(Game.weight_factor, speed - 0.2), "Heavy Plates Lv5: x2.5 armour, -20 % speed")
	Game.heli_items["plating"] = 5 # x2.8 alone; with Heavy Plates Lv5 the item factor is capped instead of x7
	Game.recompute()
	assert(is_equal_approx(Game.stats["armor"], armor * Progression.MAX_ITEM_ARMOR), "Plating + Heavy Plates capped at x%.1f: %.2f" % [Progression.MAX_ITEM_ARMOR, Game.stats["armor"] / armor])
	Game.heli_items.erase("plating")
	Game.recompute()
	Game.scrap_item("extratank")
	Game.scrap_item("heavyplates")
	assert(is_equal_approx(Game.max_fuel, fuel) and is_equal_approx(Game.stats["armor"], armor), "scrapping takes the effect away")
