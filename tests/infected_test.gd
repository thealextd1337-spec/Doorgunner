extends Node
## Headless test of the new infected (scripts/spawn_table.gd, infected.gd, hit_fx.gd). main.gd adds this node when
## env SMOKE=infected:   SMOKE=infected godot --headless --path . --quit-after 30000
## The enemies are stepped by hand (process disabled, enemy._process(delta)) so the 3 s wind-up takes no real time.

const KINDS := preload("res://scripts/enemy.gd").KINDS
const R := preload("res://scripts/chunk_manager.gd").R

var main: Node2D
var frame: Signal


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	frame = get_tree().process_frame
	await frame
	await frame
	main.spawner.set_process(false)
	Game.level = Game.LEVEL_CAP # kills would offer upgrade cards and pause the game
	_table()
	await _screamer()
	await _spitter()
	await _crawler()
	await _bloater()
	await _armor_and_feedback()
	await _save_load()
	print("INFECTED OK")
	get_tree().quit(0)


## A hand-stepped enemy.
func _spawn(kind: String, pos: Vector2) -> Node2D:
	var e: Node2D = main.spawn_enemy(kind, pos)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	return e


func _step(e: Node2D, seconds: float, dt := 0.1) -> void:
	for i in int(seconds / dt):
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			e._process(dt)


## An open, walkable spot `dist` px from `center`, at least `min_heli` px from the heli.
func _spot(center: Vector2, dist: float, min_heli := 0.0) -> Vector2:
	for k in [1.0, 0.85, 1.15, 0.7, 1.3]: # random worlds: water or rock at exactly `dist` all round happens
		for i in 32:
			var p := center + Vector2(dist * k, 0).rotated(i * TAU / 32.0)
			if main.is_walkable(p) and main.is_walkable(center.lerp(p, 0.5)) and p.distance_to(Game.heli.position) >= min_heli:
				return p
	assert(false, "no open spot near %s" % center)
	return center


## A walkable spot near `at` with 32 px of walkable ground to its east (a knockback to the right has room).
func _clear_right(at: Vector2) -> Vector2:
	for i in 64:
		var p := at + Vector2(16 * (i % 8), 16 * (i / 8))
		if range(0, 33, 4).all(func(k): return main.is_walkable(p + Vector2(k, 0))):
			return p
	assert(false, "no open ground east of %s" % at)
	return at


func _table() -> void:
	for kind in SpawnTable.ROWS:
		assert(KINDS.has(kind), "%s is an enemy kind" % kind)
		assert(ResourceLoader.exists("res://assets/sprites/b/%s.png" % kind), "%s has a sprite" % kind)
	var seen := {}
	for i in 600:
		seen[SpawnTable.pick(2.0, {"day": 1})] = true
	assert(seen.keys().all(func(k): return k in ["shambler", "runner", "brute"]), "day 1: only the old three, got %s" % [seen.keys()])
	var count := func(ctx: Dictionary, kind: String) -> int:
		var n := 0
		for i in 6000:
			n += int(SpawnTable.pick(3.0, ctx) == kind)
		return n
	var forest: int = count.call({"day": 12, "region": R.FOREST}, "crawler")
	var farm: int = count.call({"day": 12, "region": R.FARM}, "crawler")
	assert(forest > 2 * farm, "crawlers favour forest: %d vs %d" % [forest, farm])
	var town: int = count.call({"day": 12, "town": true}, "bloater")
	var open: int = count.call({"day": 12, "town": false}, "bloater")
	assert(town > 1.8 * open, "bloaters favour towns: %d vs %d" % [town, open])
	assert(count.call({"day": 12}, "brute_armored") > 0 and count.call({"day": 9}, "brute_armored") == 0, "armored brutes from day 10")
	for kind in ["screamer", "spitter", "crawler", "bloater"]:
		assert(count.call({"day": 12}, kind) > 0, "%s spawns" % kind)
	var packs := 0
	var early := 0
	for i in 400:
		var h := SpawnTable.horde(3.0, {"day": 12})
		packs += int(h.all(func(k): return k == "runner") and h.size() >= SpawnTable.PACK_SIZE.x and h.size() <= SpawnTable.PACK_SIZE.y)
		var h2 := SpawnTable.horde(3.0, {"day": 5})
		early += int(h2.size() < 6 or h2.size() > 12)
	assert(packs > 40 and early == 0, "runner packs from day 10: %d, odd early hordes: %d" % [packs, early])
	print("INFECTED table OK")


func _screamer() -> void:
	var heli: Node2D = Game.heli
	var pos := _spot(heli.position, 200.0)
	var e := _spawn("screamer", pos)
	var mate := _spawn("shambler", _spot(pos, 550.0, 420.0))
	Game.noise_level = 0.0
	_step(e, 0.5)
	assert(e.state["wind"] > 2.0 and e.get_node_or_null("Ring") != null, "wind-up started, with a ring: %s" % [e.state])
	var held: Vector2 = e.position
	_step(e, 2.0)
	assert(e.position == held and Game.noise_level < 0.5, "stands still and quiet during the wind-up")
	_step(e, 1.0)
	assert(Game.noise_level >= Infected.SCREAM_NOISE - 0.1 and Game.noise_pos.distance_to(e.position) < 30.0, "the scream is loud: %.2f at %s, screamer at %s" % [Game.noise_level, Game.noise_pos, e.position])
	assert(e.state["cd"] > 10.0 and e.state["wind"] == 0.0 and (e.get_node_or_null("Ring") == null or e.get_node("Ring").is_queued_for_deletion()), "cooldown after the scream")
	var d0: float = mate.position.distance_to(e.position)
	_step(mate, 5.0, 0.5)
	assert(mate.position.distance_to(e.position) < d0 - 5.0, "zombies come to the scream: %.0f -> %.0f" % [d0, mate.position.distance_to(e.position)])
	Game.noise_level = 0.0
	_step(e, 3.0)
	assert(e.state["wind"] == 0.0, "no second scream during the cooldown")
	e.queue_free()
	mate.queue_free()
	# shot during the wind-up: no scream
	var e2 := _spawn("screamer", pos)
	_step(e2, 0.5)
	assert(e2.state["wind"] > 0.0, "second screamer winding up")
	e2.hit(1000.0, Vector2.RIGHT)
	_step(e2, 4.0)
	assert(Game.noise_level < 0.5, "a dead screamer is quiet")
	# out of sight range: does not start
	var e3 := _spawn("screamer", _spot(heli.position, 900.0))
	_step(e3, 1.0)
	assert(e3.state.get("wind", 0.0) == 0.0, "far screamer waits")
	e3.queue_free()
	await frame
	print("INFECTED screamer OK")


func _spitter() -> void:
	var base: Node2D = main.base
	var bc := Vector2i((base.position / 16.0).floor())
	var bag := Vector2i(-99999, 0)
	Game.scrap = 500
	for x in range(-9, 10):
		for y in range(-9, 10):
			if bag.x == -99999 and base.free_cell(bc + Vector2i(x, y)) and main.is_walkable(base.cell_pos(bc + Vector2i(x, y))):
				bag = bc + Vector2i(x, y)
	assert(bag.x != -99999 and base.place_sandbag(bag), "sandbag placed")
	Game.sandbags[bag]["built"] = true
	var at: Vector2 = base.cell_pos(bag)
	var e := _spawn("spitter", _spot(at, 60.0))
	e.target_base = true # only assault spitters go for the fence
	var hp0: float = Game.sandbags[bag]["hp"]
	_step(e, 0.5)
	var d0: float = e.position.distance_to(at)
	_step(e, 4.0)
	assert(e.position.distance_to(at) > d0 + 5.0, "too close: it backs off")
	for i in 100: # a few seconds to range, the glob flies 0.6 s, then the puddle eats
		for p in get_tree().get_nodes_in_group("puddles"):
			p._process(0.1)
		_step(e, 0.1)
		if Game.sandbags[bag]["hp"] < hp0 - Infected.SPIT_SANDBAG * 0.9:
			break
	assert(get_tree().get_nodes_in_group("puddles").size() > 0, "spat at the sandbag")
	assert(Game.sandbags[bag]["hp"] < hp0 - Infected.SPIT_SANDBAG * 0.9, "acid damaged the sandbag: %s" % Game.sandbags[bag]["hp"])
	var dist: float = e.position.distance_to(at)
	assert(dist > Infected.SPIT_MIN - 10.0 and dist < Infected.SPIT_MAX + 10.0, "keeps its distance: %.0f" % dist)
	e.queue_free()
	for p in get_tree().get_nodes_in_group("puddles"):
		p.queue_free()
	base.remove_sandbag(bag)
	await frame
	print("INFECTED spitter OK")


func _crawler() -> void:
	var base: Node2D = main.base
	var bc := Vector2i((base.position / 16.0).floor())
	var cell := Vector2i(-99999, 0)
	for x in range(-9, 10):
		for y in range(-9, 10):
			if cell.x == -99999 and base.free_cell(bc + Vector2i(x, y)) and main.is_walkable(base.cell_pos(bc + Vector2i(x, y))):
				cell = bc + Vector2i(x, y)
	assert(base.place_sandbag(cell, "wire"), "wire placed")
	Game.sandbags[cell]["built"] = true
	var at: Vector2 = base.cell_pos(cell)
	assert(KINDS["crawler"]["radius"] <= KINDS["shambler"]["radius"] * 0.65, "a crawler is a smaller target")
	var c := _spawn("crawler", at)
	var s := _spawn("shambler", at)
	var wire0: float = Game.sandbags[cell]["hp"]
	var c_hp: float = c.hp
	var s_hp: float = s.hp
	s.position = Vector2(-99999, 0) # far away for now: the crawler alone in the wire
	_step(c, 1.0, 0.25)
	assert(c.hp == c_hp and c.slowed == 0.0 and Game.sandbags[cell]["hp"] == wire0, "the crawler passes the wire untouched")
	s.position = at
	_step(s, 1.0, 0.25)
	assert(s.hp < s_hp and Game.sandbags[cell]["hp"] < wire0, "the shambler bleeds in it: %.1f of %.1f" % [s.hp, s_hp])
	c.queue_free()
	s.queue_free()
	base.remove_sandbag(cell)
	await frame
	print("INFECTED crawler OK")


func _bloater() -> void:
	Game.rescued = 6
	Game.injured = 0
	var kills0: int = Game.kills
	var far := _spawn("bloater", main.base.position + Vector2(1200, 0))
	far.hit(100000.0, Vector2.RIGHT)
	assert(Game.injured == 0, "a bloater bursting far away hurts nobody")
	var e := _spawn("bloater", main.base.position + Vector2(50, 0))
	e.hit(100000.0, Vector2.RIGHT)
	assert(Game.injured == Infected.GAS_INJURED, "gas in the base hurts people: %d" % Game.injured)
	assert(Game.kills == kills0 + 2, "kills counted")
	var clouds := get_tree().get_nodes_in_group("puddles").filter(func(p): return p.kind == "gas")
	assert(clouds.size() == 2, "gas clouds")
	var hp0: float = Game.hp
	for p in clouds:
		p._process(1.1) # a tick: the heli sits on the pad inside the cloud
		p.free()
	assert(Game.hp < hp0, "gas hurts a landed heli")
	Game.rescued = 0
	Game.injured = 0
	await frame
	print("INFECTED bloater OK")


func _armor_and_feedback() -> void:
	var pos := _spot(Game.heli.position, 300.0)
	var b := _spawn("brute_armored", pos)
	b.rotation = 0.0 # facing up
	var hp: float = b.hp
	b.hit(100.0, Vector2.DOWN) # a shot flying down hits the front
	assert(absf((hp - b.hp) - 30.0) < 0.01, "front: 70 percent stopped, lost %.1f" % (hp - b.hp))
	hp = b.hp
	b.hit(100.0, Vector2.RIGHT)
	assert(absf((hp - b.hp) - 100.0) < 0.01, "flank: full damage")
	hp = b.hp
	b.hit(100.0, Vector2.UP)
	assert(absf((hp - b.hp) - 100.0) < 0.01, "rear: full damage")
	hp = b.hp
	b.hit(100.0)
	assert(absf((hp - b.hp) - 100.0) < 0.01, "splash ignores the plates")
	# headshot, knockback, flash on a plain brute
	var e := _spawn("brute", _clear_right(pos + Vector2(40, 0))) # open ground to the east: the kick must not hit a wall
	hp = e.hp
	e.hit(10.0, Vector2.RIGHT, true)
	assert(absf((hp - e.hp) - 10.0 * e.HEAD_MULT) < 0.01, "headshot doubles")
	assert(e.kick.x > 0.0 and e.sprite.modulate.r > 1.5, "kick and white flash")
	var x0: float = e.position.x
	e._process(0.1)
	assert(e.position.x > x0, "knocked back")
	# a bullet roll: Optics raises the headshot chance
	assert(preload("res://scripts/bullet.gd").HEAD_CHANCE + 5 * preload("res://scripts/bullet.gd").HEAD_PER_OPTICS > preload("res://scripts/bullet.gd").HEAD_CHANCE, "optics headshots")
	# corpse that stays, the second pellet of a dead enemy does not count twice
	var sh := _spawn("shambler", pos + Vector2(0, 60))
	var kills0: int = Game.kills
	var n0 := HitFx.corpses.size()
	sh.hit(1000.0, Vector2.RIGHT)
	sh.hit(1000.0, Vector2.RIGHT)
	assert(Game.kills == kills0 + 1, "one kill, not two")
	assert(HitFx.corpses.size() == n0 + 1 and is_instance_valid(HitFx.corpses.back()), "a corpse is left")
	for i in 130:
		HitFx.death(sh)
	assert(HitFx.corpses.size() <= HitFx.MAX_CORPSES, "corpse cap: %d" % HitFx.corpses.size())
	for i in 100:
		HitFx.burst(pos, Vector2.RIGHT, Color.RED, 5, 50.0)
	assert(get_tree().get_nodes_in_group("hit_particles").size() <= HitFx.MAX_PARTICLES, "particle cap")
	# screen shake and its option
	var shaker: Node = get_tree().get_first_node_in_group("shaker")
	assert(shaker != null, "the camera has a shaker")
	shaker.amp = 0.0
	Game.meta["shake"] = 0
	HitFx.shake(3.0)
	assert(shaker.amp == 0.0, "shake off")
	Game.meta["shake"] = 1
	HitFx.shake(3.0)
	assert(shaker.amp == 3.0, "shake on")
	shaker.amp = 0.0
	assert(Weapons_damage("autocannon") >= HitFx.SHAKE_MIN_DAMAGE and Weapons_damage("mg") < HitFx.SHAKE_MIN_DAMAGE, "heavy guns shake, the MG does not")
	b.queue_free()
	e.queue_free()
	await frame
	print("INFECTED feedback OK")


func Weapons_damage(id: String) -> float:
	return Game.Weapons.TABLE[id]["damage"]


func _save_load() -> void:
	var heli: Node2D = Game.heli
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	var pos := _spot(heli.position, 200.0)
	var scr := _spawn("screamer", pos)
	_step(scr, 1.5) # mid wind-up
	var wind: float = scr.state["wind"]
	assert(wind > 1.0 and wind < 2.0, "screamer mid wind-up %.2f" % wind)
	var bl := _spawn("bloater", _spot(heli.position, 300.0))
	bl.hp -= 100.0
	var kinds := ["spitter", "crawler", "brute_armored"]
	for k in kinds:
		_spawn(k, _spot(heli.position, 340.0))
	var saved: Array = main._save_enemies()
	assert(saved.size() == 5, "five saved: %d" % saved.size())
	saved = bytes_to_var(var_to_bytes(saved)) # what Save does to it
	var hp: float = bl.hp
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	main._load_enemies(saved)
	await frame
	var back := {}
	for e in get_tree().get_nodes_in_group("enemies"):
		back[e.kind] = e
		e.process_mode = Node.PROCESS_MODE_DISABLED
	assert(back.size() == 5 and back.has("screamer") and back.has("bloater") and back.has("brute_armored") and back.has("crawler") and back.has("spitter"), "all kinds back: %s" % [back.keys()])
	assert(absf(back["bloater"].hp - hp) < 0.01, "hp back")
	assert(absf(back["screamer"].state["wind"] - wind) < 0.3, # a frame ran between load and check
			 "wind-up back: %s" % [back["screamer"].state])
	Game.noise_level = 0.0
	_step(back["screamer"], 2.0)
	assert(Game.noise_level >= Infected.SCREAM_NOISE - 0.1, "the loaded screamer finishes its scream")
	back["bloater"].hit(100000.0, Vector2.RIGHT)
	for p in get_tree().get_nodes_in_group("puddles"):
		p.free()
	# a run saved before the infected: seven fields per enemy
	main._load_enemies([["shambler", pos, 10.0, 10.0, 5.0, 3.0, false]])
	await frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	print("INFECTED save/load OK")
