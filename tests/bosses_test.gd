extends Node
## Headless test of the Q12 bosses (scripts/bosses.gd): each appears, telegraphs, changes phase, dies, rewards, survives a save.
## main.gd adds this node when env SMOKE=bosses:   SMOKE=bosses godot --headless --path . --quit-after 30000
## Bosses are stepped by hand (process disabled, node._process(dt)) so a whole fight takes no real time.

const KINDS := preload("res://scripts/enemy.gd").KINDS
const T := preload("res://scripts/chunk_manager.gd").T

var main: Node2D
var sys: Node
var heli: Node2D
var frame: Signal


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	sys = main.bosses
	heli = Game.heli
	frame = get_tree().process_frame
	await frame
	await frame
	main.spawner.set_process(false)
	main.bandits.set_process(false)
	sys.set_process(false)
	heli.set_process(false)
	heli.landed = false
	Game.level = Game.LEVEL_CAP # kills would offer upgrade cards and pause the game
	Game.time = 0.5
	Game.hp = Game.max_hp
	print("bosses test seed ", Game.seed)
	_table()
	await _matriarch()
	await _juggernaut()
	await _hive()
	await _warlord()
	await _roaming()
	await _old_saves()
	print("BOSSES OK")
	get_tree().quit(0)


func _enemy(kind: String, pos: Vector2) -> Node2D:
	var e: Node2D = main.spawn_enemy(kind, pos)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	return e


func _step(n: Node2D, seconds: float, dt := 0.1) -> void:
	for i in int(seconds / dt):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n._process(dt)


func _free_all() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	for p in main.get_children():
		if p is Bosses.Shell:
			p.free()


## An open, walkable spot `dist` px from `center` with `lane` px of open ground to its east.
func _spot(center: Vector2, dist: float, lane := 0.0) -> Vector2:
	for k in [1.0, 0.85, 1.15, 0.7, 1.3, 1.6, 2.0]:
		for i in 48:
			var p := center + Vector2(dist * k, 0).rotated(i * TAU / 48.0)
			if main.is_walkable(p) and range(0, int(lane) + 1, 8).all(func(d): return main.is_walkable(p + Vector2(d, 0))):
				return p
	assert(false, "no open spot near %s" % center)
	return center


func _count(kind: String) -> int:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return "kind" in e and e.kind == kind and not e.is_queued_for_deletion()).size()


func _radio_has(text: String) -> bool:
	return Game.radio_log.any(func(l): return text in str(l)) if "radio_log" in Game else true


func _table() -> void:
	for id in ["matriarch", "juggernaut", "hive"]:
		assert(KINDS.has(id) and KINDS[id]["boss_id"] == id and KINDS[id].has("down"), "%s is a boss kind" % id)
		assert(ResourceLoader.exists("res://assets/sprites/b/%s.png" % id), "%s has a sprite" % id)
	assert(Bandit.KINDS["warlord"]["boss_id"] == "warlord" and ResourceLoader.exists("res://assets/sprites/b/warlord.png"), "warlord is a bandit kind with a sprite")
	assert(KINDS["boss"].get("boss_id", "") == "" and KINDS["boss"]["boss"], "the blood-moon boss is untouched")
	for id in Bosses.REWARDS:
		assert(Codex.entries.has(Bosses.codex_id(id)) and Codex.entries[Bosses.codex_id(id)]["category"] == "Enemies" and CodexContent.ROWS.any(func(r): return r[1] == Bosses.codex_id(id)), "%s has a codex row" % id)
		assert(Bosses.NAMES.has(id) and SpawnTable.BOSS_ROWS.has(id), "%s has a name and spawn rules" % id)
	for k in SpawnTable.ROWS: # the boss rows are not in the ordinary weights
		assert(not KINDS[k].has("boss_id"), "%s is no ordinary spawn" % k)
	assert(Save._hooks.has("bosses"), "bosses register a save hook")
	print("BOSSES table OK")


# ---------------------------------------------------------------- Matriarch

func _matriarch() -> void:
	_free_all()
	var pos := _spot(heli.position, 260.0)
	var e := _enemy("matriarch", pos)
	_step(e, 0.1)
	assert(e.state["phase"] == 1 and e.state.has("nemesis_id") and e.state["nemesis_id"] == "", "phase 1, empty nemesis id: %s" % [e.state])
	assert(e.get_node_or_null("BossFx") != null, "hp bar node")
	# telegraph: she rears up (ring, roar) before the brood
	var brood0 := _count("runner") + _count("crawler")
	var roar0: int = Sfx.last_ms.get("boss_roar", -1)
	_step(e, 4.0)
	assert(e.state["wind"] > 0.0 and e.get_node("BossFx").p > 0.0, "rearing up with a ring: %s" % [e.state])
	assert(Sfx.last_ms.get("boss_roar", -1) != roar0, "audible roar before the brood")
	assert(_count("runner") + _count("crawler") == brood0, "no brood during the wind-up")
	_step(e, 1.7)
	var brood1 := _count("runner") + _count("crawler")
	assert(brood1 - brood0 == Bosses.BROOD_SIZE[0], "brood of %d: %d" % [Bosses.BROOD_SIZE[0], brood1 - brood0])
	# half HP: phase 2, she flees and heals
	e.hp = e.max_hp * 0.49
	var at: Vector2 = e.position
	_step(e, 0.2)
	assert(e.state["phase"] == 2 and e.state["mode"] == "flee", "phase 2: flees: %s" % [e.state])
	assert(_count("runner") + _count("crawler") - brood1 >= Bosses.BROOD_SIZE[1] - 1, "a bigger brood as she runs")
	var d0: float = e.position.distance_to(heli.position)
	var hp0: float = e.hp
	_step(e, 3.0)
	assert(e.position.distance_to(heli.position) > d0 + 20.0 and e.hp > hp0, "runs away and heals: %.0f -> %.0f px, hp %.0f -> %.0f" % [d0, e.position.distance_to(heli.position), hp0, e.hp])
	_step(e, Bosses.FLEE_TIME)
	assert(e.state["mode"] == "stalk" and e.hp > e.max_hp * 0.55, "she is back: %s hp %.0f/%.0f" % [e.state["mode"], e.hp, e.max_hp])
	assert(e.state["cd"] <= Bosses.BROOD_CD[1], "phase 2 brood interval")
	# mid-fight save and load
	e.state["wind"] = 0.8
	e.get_node("BossFx").p = 0.5
	var hp: float = e.hp
	var saved: Array = bytes_to_var(var_to_bytes(main._save_enemies()))
	_free_all()
	main._load_enemies(saved.filter(func(a): return a[0] == "matriarch"))
	await frame
	var back: Node2D
	for n in get_tree().get_nodes_in_group("enemies"):
		if n.kind == "matriarch":
			back = n
			back.process_mode = Node.PROCESS_MODE_DISABLED
	assert(back != null and absf(back.hp - hp) < 0.1 and back.state["phase"] == 2 and absf(back.state["wind"] - 0.8) < 0.3, "matriarch back mid wind-up: %s" % [back.state if back else "none"])
	var b0 := _count("runner") + _count("crawler")
	_step(back, 1.0)
	assert(_count("runner") + _count("crawler") - b0 == Bosses.BROOD_SIZE[1], "the loaded Matriarch finishes her wind-up and spawns the brood")
	# death: rewards
	var kills: int = Game.meta["boss_kills"]
	var parts: float = Game.salvage["parts"]
	var scrap: int = Game.scrap
	var morale0: int = main.morale.pending.size()
	back.hit(100000.0, Vector2.RIGHT)
	assert(Game.meta["boss_kills"] == kills + 2, "two boss kills: %d -> %d" % [kills, Game.meta["boss_kills"]])
	assert(Game.salvage["parts"] == parts + 6.0 and Game.scrap >= scrap + 60, "parts and scrap")
	assert(main.morale.pending.size() == morale0 + 1, "morale")
	assert(KINDS["matriarch"]["down"] != "", "own radio line")
	print("BOSSES matriarch OK")


# ---------------------------------------------------------------- Juggernaut

func _juggernaut() -> void:
	_free_all()
	Game.hp = Game.max_hp
	var founded: bool = Game.base_founded
	Game.base_founded = false # a founded base within sight would be its target
	var pos := _spot(heli.position, 300.0, 400.0)
	heli.global_position = pos + Vector2(230, 0)
	var e := _enemy("juggernaut", pos)
	e.rotation = PI / 2 # faces east, to the heli
	_step(e, 0.1)
	# armour: front and sides stopped, back (the fuel pack) takes it all
	var facing := Vector2.UP.rotated(e.rotation)
	e.hp = e.max_hp
	e.hit(100.0, -facing)
	var front: float = e.max_hp - e.hp
	e.hp = e.max_hp
	e.hit(100.0, facing)
	var rear: float = e.max_hp - e.hp
	e.hp = e.max_hp
	e.hit(100.0)
	var splash: float = e.max_hp - e.hp
	assert(absf(front - 20.0) < 0.5 and absf(rear - 100.0) < 0.5 and absf(splash - 60.0) < 0.5, "armour: front %.1f, rear %.1f, splash %.1f" % [front, rear, splash])
	e.hp = e.max_hp
	# a house in the lane and a landed heli at its end
	var lane_cell := Vector2i(((pos + Vector2(110, 0)) / 16.0).floor())
	main.chunks.edit(lane_cell, T.BUILDING)
	e.state["cd"] = 0.0
	e.state["mode"] = "walk"
	_step(e, 0.3)
	assert(e.state["mode"] == "wind", "winds up when the heli is in range: %s" % [e.state])
	assert(e.get_node("BossFx").lane.length() > 200.0 and e.get_node("BossFx").p >= 0.0, "the lane is shown")
	var wind_roar: int = Sfx.last_ms.get("rpg_warn", -1)
	assert(wind_roar != -1, "a warning sound with the wind-up")
	var p0: Vector2 = e.position
	_step(e, 1.0)
	assert(e.position.distance_to(p0) < 2.0 and e.state["mode"] == "wind", "stands still while it lowers its head")
	heli.landed = true
	var hp0: float = Game.hp
	_step(e, 0.8) # wind over: charge
	assert(e.state["mode"] == "charge" or e.state["mode"] == "daze", "charging: %s" % e.state["mode"])
	_step(e, 2.0)
	assert(main.chunks.get_cell_atlas_coords(lane_cell).x == T.RUIN, "the house in its way is ruined: tile %d, juggernaut at %s from %s, mode %s" % [main.chunks.get_cell_atlas_coords(lane_cell).x, e.position, pos, e.state["mode"]])
	assert(e.state["mode"] == "daze", "dazed after the ram: %s" % e.state["mode"])
	assert(Game.hp < hp0, "the landed heli took the hit: %.0f -> %.0f" % [hp0, Game.hp])
	var stood: Vector2 = e.position
	_step(e, 1.0)
	assert(e.position.distance_to(stood) < 2.0, "dazed: it stands")
	_step(e, Bosses.JUG_DAZE)
	assert(e.state["mode"] == "walk", "walks again")
	# half HP: plates come off, two charges in a row
	e.hp = e.max_hp * 0.49
	_step(e, 0.1)
	assert(e.state["phase"] == 2 and e.state["chain"] == Bosses.JUG_CHAIN - 1, "phase 2: %s" % [e.state])
	e.rotation = PI / 2
	e.hp = e.max_hp * 0.49
	e.hit(100.0, -Vector2.UP.rotated(e.rotation))
	assert(absf((e.max_hp * 0.49 - e.hp) - 40.0) < 0.5, "less armour in phase 2: %.1f" % (e.max_hp * 0.49 - e.hp))
	heli.landed = false
	e.position = pos # the open lane again
	heli.global_position = pos + Vector2(230, 0)
	e.state["mode"] = "walk"
	e.state["cd"] = 0.0
	var charges := 0
	var last := ""
	for i in 80:
		_step(e, 0.1)
		if e.state["mode"] == "charge" and last != "charge":
			charges += 1
		last = e.state["mode"]
	assert(charges >= 2, "two charges in a row in phase 2: %d" % charges)
	# mid-charge save and load
	e.state["mode"] = "charge"
	e.state["t"] = 0.5
	e.state["dir"] = Vector2.RIGHT
	var hp: float = e.hp
	var saved: Array = bytes_to_var(var_to_bytes(main._save_enemies()))
	_free_all()
	main._load_enemies(saved)
	await frame
	var back: Node2D
	for n in get_tree().get_nodes_in_group("enemies"):
		back = n
		back.process_mode = Node.PROCESS_MODE_DISABLED
	assert(back != null and back.kind == "juggernaut" and back.state["mode"] == "charge" and back.state["phase"] == 2 and absf(back.hp - hp) < 0.1, "juggernaut back mid-charge")
	var x0: float = back.position.x
	_step(back, 0.4)
	assert(back.position.x > x0 + 20.0 or back.state["mode"] == "daze", "the loaded Juggernaut carries on charging")
	var kills: int = Game.meta["boss_kills"]
	var metal: float = Game.salvage["metal"]
	var rifles: float = Game.base_rifles
	back.hit(100000.0, Vector2.DOWN.rotated(0.0) * -1.0) # a shot from the rear side
	assert(Game.meta["boss_kills"] == kills + 2 and Game.salvage["metal"] == metal + 40.0 and Game.base_rifles >= rifles + 2.0, "juggernaut rewards")
	Game.base_founded = founded
	# the base is its target only while the heli is near the base too (review: no siege while the player is away)
	_free_all()
	var b: Vector2 = main.base.global_position
	var jp := _spot(b, 600.0)
	for heli_d in [1600.0, 0.0]:
		var j := _enemy("juggernaut", jp)
		j.state.merge({"phase": 1, "mode": "walk", "t": 0.0, "w0": Bosses.JUG_WIND, "cd": 99.0, "dir": Vector2.ZERO, "chain": 0, "hit": false, "nemesis_id": ""})
		heli.global_position = b + (jp - b).normalized() * heli_d
		_step(j, 3.0)
		var closer: bool = j.position.distance_to(b) < jp.distance_to(b) - 5.0
		assert(closer == (heli_d == 0.0), "heli %.0f px from the base: the Juggernaut %s the base (%.0f -> %.0f)" % [heli_d, "goes for" if heli_d == 0.0 else "leaves", jp.distance_to(b), j.position.distance_to(b)])
		j.free()
	heli.global_position = b
	print("BOSSES juggernaut OK")


# ---------------------------------------------------------------- Hive

func _hive() -> void:
	_free_all()
	heli.landed = false
	var site := {"kind": "stadium", "pos": _spot(heli.position, 350.0, 120.0), "uid": "test#hive"}
	assert(not sys._has_hive(site.uid), "no hive yet")
	var e: Node2D = sys.spawn_hive(site)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	_step(e, 0.1)
	assert(e.state["site"] == site.uid and e.state["home"] == site.pos and e.state["phase"] == 1 and e.state["nemesis_id"] == "", "hive state: %s" % [e.state])
	assert(sys._has_hive(site.uid), "found by site")
	e.position += Vector2(30, 0)
	e.hit(10.0, Vector2.LEFT)
	_step(e, 0.1)
	assert(e.position.distance_to(site.pos) < 1.0, "the hive is rooted")
	var zombies0 := get_tree().get_nodes_in_group("enemies").size()
	_step(e, Bosses.HIVE_FIRST)
	assert(e.state["wind"] > 0.0 and e.get_node("BossFx").p > 0.0, "throbbing before the wave: %s" % [e.state])
	assert(get_tree().get_nodes_in_group("enemies").size() == zombies0, "no wave during the warning")
	_step(e, Bosses.HIVE_WIND + 0.2)
	var wave1 := get_tree().get_nodes_in_group("enemies").size() - zombies0
	assert(wave1 >= Bosses.HIVE_WAVE[0] / 2 and e.state["waves"] == 1, "a wave came: %d, %s" % [wave1, e.state])
	for z in get_tree().get_nodes_in_group("enemies"):
		if z != e:
			z.free()
	# far away it sleeps
	var far: Vector2 = heli.global_position
	heli.global_position = e.position + Vector2(Bosses.HIVE_ACTIVE + 400.0, 0)
	e.state["cd"] = 0.0
	_step(e, 1.0)
	assert(e.state["wind"] == 0.0, "no wave while the heli is far: %s" % [e.state])
	heli.global_position = far
	# phase 2: faster waves with special kinds
	e.hp = e.max_hp * 0.49
	e.state["wind"] = 0.0
	_step(e, 0.2)
	assert(e.state["phase"] == 2 and e.state["cd"] <= 4.0, "phase 2: %s" % [e.state])
	_step(e, 4.0 + Bosses.HIVE_WIND + 0.3)
	assert(_count("spitter") + _count("bloater") + _count("brute_armored") >= 2, "phase 2 wave brings specials")
	# save and load mid-fight, hp kept
	var hp: float = e.hp
	var saved: Array = bytes_to_var(var_to_bytes(main._save_enemies().filter(func(a): return a[0] == "hive")))
	_free_all()
	main._load_enemies(saved)
	await frame
	var back: Node2D
	for n in get_tree().get_nodes_in_group("enemies"):
		back = n
		back.process_mode = Node.PROCESS_MODE_DISABLED
	assert(back != null and back.kind == "hive" and back.state["phase"] == 2 and absf(back.hp - hp) < 0.1 and back.state["site"] == site.uid, "hive back mid-fight")
	# it despawns when the heli leaves; the site record brings it back with the same hp
	sys.scan()
	assert(sys.records["hive:" + site.uid]["hp"] == back.hp, "hp recorded")
	back.free()
	var again: Node2D = sys.spawn_hive(site)
	again.process_mode = Node.PROCESS_MODE_DISABLED
	assert(absf(again.hp - hp) < 0.1 and again.state["phase"] == 2, "respawned hurt: %.0f vs %.0f" % [again.hp, hp])
	# death: electronics, and it stays dead
	var kills: int = Game.meta["boss_kills"]
	var elec: float = Game.salvage["electronics"]
	again.hit(100000.0, Vector2.RIGHT)
	assert(Game.meta["boss_kills"] == kills + 3 and Game.salvage["electronics"] == elec + 15.0, "hive reward: key part")
	assert(sys.records["hive:" + site.uid].get("dead", false) and not sys.wants_hive(site), "a destroyed hive stays destroyed")
	assert(not sys._has_hive(site.uid), "gone")
	# rolls: about HIVE pct of sites
	var n := 0
	var far_pos: Vector2 = main.base.global_position + Vector2(Bosses.HIVE_BASE_MIN + 500.0, 0)
	for i in 400:
		n += int(sys.wants_hive({"uid": "roll#%d" % i, "pos": far_pos}))
	assert(n > 400 * 0.45 and n < 400 * 0.75, "hive share of sites: %d / 400" % n)
	for i in 400: # review: never next to the base
		assert(not sys.wants_hive({"uid": "roll#%d" % i, "pos": main.base.global_position + Vector2(Bosses.HIVE_BASE_MIN - 100.0, 0)}), "no Hive within HIVE_BASE_MIN of the base")
	print("BOSSES hive OK")


# ---------------------------------------------------------------- Warlord

func _warlord() -> void:
	_free_all()
	var bandits: Node = main.bandits
	Game.day = 12
	# assignment: only far, big camps, at most WARLORD_MAX
	var held := 0
	var assigned := 0
	for i in 30:
		var c: Dictionary = bandits.add_camp("wl#far%d" % i, "prison" if i % 2 == 0 else "motel", Vector2(3000 + i * 10, 400))
		sys._assign_warlord(c)
		assert(c.has("warlord"), "decided once")
		if c["warlord"]:
			assigned += 1
			assert(c["kind"] == "prison" and c["garrison"]["warlord"] == 1, "warlords hold the big camps")
	assert(assigned >= 1 and assigned <= Bosses.WARLORD_MAX, "at most %d: %d" % [Bosses.WARLORD_MAX, assigned])
	# review: dead warlords free their place (the camp flag stays, the garrison count drops)
	for c in bandits.camps.values():
		if c.get("warlord", false):
			c["garrison"]["warlord"] = 0
	var again := 0
	for i in 30:
		var c2: Dictionary = bandits.add_camp("wl#more%d" % i, "prison", Vector2(3000 + i * 10, 800))
		sys._assign_warlord(c2)
		again += int(c2["warlord"])
	assert(again >= 1 and again <= Bosses.WARLORD_MAX, "new warlords once the old ones are dead: %d" % again)
	var near: Dictionary = bandits.add_camp("wl#near", "prison", Vector2(300, 0))
	sys._assign_warlord(near)
	assert(not near["warlord"] and not near["garrison"].has("warlord"), "none near the start")
	for uid in bandits.camps.keys():
		if uid.begins_with("wl#"):
			bandits.camps.erase(uid)
	Game.day = 12
	# the fight
	var pos := _spot(heli.position, 400.0)
	var c: Dictionary = bandits.add_camp("wl#fight", "prison", pos)
	c["garrison"] = {"warlord": 1}
	c["warlord"] = true
	c["prisoners"] = 0
	bandits._wake(c)
	var w: Node2D
	for u in get_tree().get_nodes_in_group("bandits"):
		u.process_mode = Node.PROCESS_MODE_DISABLED
		if u.kind == "warlord":
			w = u
	assert(w != null, "the warlord is at his camp")
	_step(w, 0.1)
	assert(w.state["phase"] == 1 and w.state["nemesis_id"] == "", "state: %s" % [w.state])
	var escorts := get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "escort")
	assert(escorts.size() == Bosses.BODY_N, "bodyguards: %d" % escorts.size())
	for u in escorts:
		u.process_mode = Node.PROCESS_MODE_DISABLED
	# the mortar only fires on a landed heli, with a telegraph
	heli.landed = false
	heli.global_position = w.position + Vector2(450, 0) # in mortar range, out of the gun range
	w.state["mortar"] = 0.0
	_step(w, 0.5)
	assert(main.get_children().filter(func(n): return n is Bosses.Shell and not n.is_queued_for_deletion()).is_empty(), "no mortar on a flying heli")
	heli.landed = true
	Game.hp = Game.max_hp
	_step(w, 0.2)
	var shells := main.get_children().filter(func(n): return n is Bosses.Shell and not n.is_queued_for_deletion())
	assert(shells.size() == 1 and shells[0].position.distance_to(heli.global_position) < 1.0, "one shell on the heli's spot: %d" % shells.size())
	assert(w.get_node("BossFx").p > 0.0, "telegraph on the warlord")
	_step(shells[0], 1.0)
	assert(Game.hp == Game.max_hp, "not yet: the fuse is %.1f" % shells[0].fuse)
	_step(shells[0], Bosses.MORTAR_FUSE)
	assert(Game.hp <= Game.max_hp - Bosses.MORTAR_DMG / Game.stats["armor"] + 0.5, "the shell hit the landed heli: %.1f" % Game.hp)
	# lifting off in time: a miss
	w.state["mortar"] = 0.0
	_step(w, 0.2)
	shells = main.get_children().filter(func(n): return n is Bosses.Shell and not n.is_queued_for_deletion())
	Game.hp = Game.max_hp
	heli.landed = false
	_step(shells[0], Bosses.MORTAR_FUSE + 0.2)
	assert(Game.hp == Game.max_hp, "a heli that took off was missed")
	# half HP: three shells at a time, more bodyguards
	w.hp = w.max_hp * 0.49
	heli.landed = true
	w.state["mortar"] = 0.0
	_step(w, 0.2)
	assert(w.state["phase"] == 2, "phase 2")
	assert(get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "escort").size() == Bosses.BODY_N + Bosses.BODY_P2.size(), "reinforced bodyguards")
	shells = main.get_children().filter(func(n): return n is Bosses.Shell and not n.is_queued_for_deletion())
	assert(shells.size() == 3, "a volley of three: %d" % shells.size())
	for s in shells:
		s.free()
	# save/load mid-fight: the record keeps hp and phase over a sleep and a reload
	sys.scan()
	var rec: Dictionary = bytes_to_var(var_to_bytes(sys.save_state()))
	var hp: float = w.hp
	for u in get_tree().get_nodes_in_group("bandits"):
		u.process_mode = Node.PROCESS_MODE_INHERIT
	bandits._sleep(c)
	await frame
	assert(get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "escort" and not u.is_queued_for_deletion()).is_empty(), "the bodyguards go with him when the camp sleeps")
	sys.records.clear()
	sys.load_state(rec)
	bandits._wake(c)
	for u in get_tree().get_nodes_in_group("bandits"):
		u.process_mode = Node.PROCESS_MODE_DISABLED
		if u.kind == "warlord":
			w = u
	_step(w, 0.1)
	assert(absf(w.hp - hp) < 0.1 and w.state["phase"] == 2, "warlord back mid-fight: hp %.0f vs %.0f, phase %s" % [w.hp, hp, w.state["phase"]])
	# death: reward, bodyguards scatter, camp cleared
	var kills: int = Game.meta["boss_kills"]
	var elec: float = Game.salvage["electronics"]
	var rifles: float = Game.base_rifles
	var cleared := []
	bandits.camp_cleared.connect(func(uid: String): cleared.append(uid))
	w.hit(100000.0)
	assert(Game.meta["boss_kills"] == kills + 3 and Game.salvage["electronics"] == elec + 8.0 and Game.base_rifles >= rifles + 4.0, "warlord rewards")
	assert(c["cleared"] and cleared == ["wl#fight"], "his death clears the camp")
	assert(sys.records["warlord:wl#fight"].get("dead", false), "recorded dead")
	await frame
	var runners := get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "escort" and not u.is_queued_for_deletion())
	assert(runners.all(func(u): return u.role == "home"), "the bodyguards scatter")
	for u in get_tree().get_nodes_in_group("bandits"):
		u.free()
	bandits.camps.erase("wl#fight")
	print("BOSSES warlord OK")


# ---------------------------------------------------------------- spawn rules, codex, old saves

func _roaming() -> void:
	_free_all()
	heli.landed = false
	Game.day = 3
	sys.pending.clear()
	sys.last_roam = -100
	for i in 60:
		sys._on_day(3)
	assert(sys.pending.is_empty(), "no roaming boss before day 6")
	Game.day = 20
	for i in 200:
		sys.last_roam = -100
		sys._on_day(20)
		if not sys.pending.is_empty():
			break
	assert(not sys.pending.is_empty(), "a roamer is rolled for on a late day")
	var kind: String = sys.pending[0]
	sys._on_day(21)
	assert(sys.pending.size() == 1, "not twice within %d days" % Bosses.ROAM_GAP)
	sys.scan()
	assert(sys.pending.is_empty(), "the scan places it")
	var e: Node2D
	for n in get_tree().get_nodes_in_group("enemies"):
		if n.kind == kind:
			e = n
			e.process_mode = Node.PROCESS_MODE_DISABLED
	assert(e != null, "%s appeared" % kind)
	var d: float = e.position.distance_to(heli.position)
	assert(d >= 600.0 and d <= 1000.0 and e.position.distance_to(main.base.position) >= Bosses.ROAM_BASE_MIN - 1.0, "placed 650-950 px from the heli and away from the base: %.0f, base %.0f, founded %s" % [d, e.position.distance_to(main.base.position), Game.base_founded])
	# none while one is alive
	sys.pending.append(kind)
	sys.last_roam = -100
	sys._on_day(30)
	# codex: seen once close
	e.position = heli.position + Vector2(200, 0)
	var meta_codex: String = Game.meta["codex"]
	Game.meta["codex"] = ",".join(Array(Codex.ids_unlocked()).filter(func(i): return i != Bosses.codex_id(kind)))
	sys.scan()
	assert(Codex.is_unlocked(Bosses.codex_id(kind)), "%s unlocked in the codex when seen" % kind)
	Game.meta["codex"] = meta_codex
	# the old blood-moon boss still spawns its runners
	var old := _enemy("boss", _spot(heli.position, 500.0))
	old.spawn_cd = 0.0
	var r0 := _count("runner")
	_step(old, 0.2)
	assert(_count("runner") == r0 + 2, "the blood-moon boss still calls two runners")
	print("BOSSES roaming OK")


func _old_saves() -> void:
	sys.load_state({}) # a run saved before Q12
	assert(sys.records.is_empty() and sys.pending.is_empty(), "old save loads empty")
	main.bandits.load_state({"camps": {"old#1": {"uid": "old#1", "kind": "prison", "pos": Vector2(3000, 0), "garrison": {"rifle": 2}, "prisoners": 1, "cleared": false, "known": false, "looted": false}},
			"town_raid": {}, "base_raid_day": -1, "last_base_raid": -100, "units": []})
	Game.day = 12
	sys.scan()
	assert(main.bandits.camps["old#1"].has("warlord"), "an old camp gets decided on the next scan")
	main.bandits.camps.erase("old#1")
	_free_all()
	main._load_enemies([["shambler", heli.position + Vector2(100, 0), 10.0, 10.0, 5.0, 3.0, false]])
	await frame
	_free_all()
	print("BOSSES old saves OK")
