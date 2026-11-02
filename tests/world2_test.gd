extends Node
## Q10 regions and landmarks (docs/ROADMAP2.md Q10). main.gd adds this node when env SMOKE=world2:
##   SMOKE=world2 godot --headless --path . --quit-after 30000
## Over a few fixed seeds (fresh generators, Game.seed restored at the end):
## 1. Coast (with sea) and winter (with frozen lakes) appear in every seed.
## 2. Each new landmark (hospital, harbour, stadium, power plant, ski lift) is found, its POIs and centre are landable,
##    it has street ends and a road to one of its two neighbours; sites_near knows the kinds; other systems list them.
## 3. Chunks over a harbour's coast and a winter site come out the same in two load orders.
## 4. A frozen lake is landable and walkable, the sea is neither.
## 5. A flight over the stadium stays under 50 ms per frame.
## 6. landmarks.gd: hospital medics, the stadium horde, the power part saving generator fuel, save/load.

const CM := preload("res://scripts/chunk_manager.gd")
const T := CM.T
const R := CM.R
const SEEDS := [11, 22, 33, 44]
const KINDS := ["hospital", "harbour", "stadium", "power_plant", "ski_lift"]
const SEARCH := 16 # macro cells out from the start

var main: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	await get_tree().process_frame
	await get_tree().process_frame
	main.chunks.process_mode = Node.PROCESS_MODE_DISABLED
	main.landmarks.process_mode = Node.PROCESS_MODE_DISABLED
	main.spawner.set_process(false)
	var seed0: int = Game.seed
	# 1. regions across seeds
	var found := {} # kind -> [seed, macro cell]
	var areas := {} # "coast" / "winter" -> [seed, macro cell]
	for sd: int in SEEDS:
		Game.seed = sd
		var ch := _fresh()
		var count := {}
		var sea := 0
		var ice := 0
		for x in range(-6000, 6001, 150):
			for y in range(-6000, 6001, 150):
				var c := Vector2i(x, y)
				var r: int = ch.region(c)
				count[r] = count.get(r, 0) + 1
				var t: int = ch._terrain(c)
				sea += int(r == R.COAST and t == T.WATER | CM.SEA << 8)
				ice += int(r == R.WINTER and t == T.ICE)
		print("seed %d: regions %s, sea samples %d, ice samples %d" % [sd, count, sea, ice])
		assert(count.get(R.COAST, 0) > 0 and count.get(R.WINTER, 0) > 0, "coast and winter in seed %d" % sd)
		assert(sea > 0 and ice > 0, "sea in the coast and frozen lakes in the winter of seed %d" % sd)
		for r in SEARCH:
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					if maxi(absi(x), absi(y)) != r:
						continue
					var s: Dictionary = ch.site(Vector2i(x, y))
					if s.kind in KINDS and not found.has(s.kind):
						found[s.kind] = [sd, s.m]
					if s.kind == "harbour" and s.reg == R.COAST and not areas.has("coast"):
						areas["coast"] = [sd, s.m]
					if s.reg == R.WINTER and s.kind != "" and not areas.has("winter"):
						areas["winter"] = [sd, s.m]
		ch.queue_free()
	print("landmarks found: %s, areas: %s" % [found, areas])
	for k in KINDS:
		assert(found.has(k), "a %s within %d macro cells in one of the seeds" % [k, SEARCH])
	assert(areas.has("coast") and areas.has("winter"), "a coast harbour and a winter site")
	# 2. landmarks: landable, street ends, a road to a neighbour, sites_near
	for k: String in found:
		Game.seed = found[k][0]
		var ch := _fresh()
		var m: Vector2i = found[k][1]
		var s: Dictionary = ch.site(m)
		var lay: Dictionary = ch._layout(m)
		var pois := 0
		for c in lay.pois:
			for p: Array in lay.pois[c]:
				pois += 1
				assert(_landable_near(ch, Vector2i((p[1] / CM.TILE).floor())), "%s: its %s can be landed at" % [k, p[0]])
		assert(pois >= 2, "%s has POIs" % k)
		assert(not ch._ft(s.center) in CM.BLOCKED, "%s: its centre is landable (%s)" % [k, ch._ft(s.center)])
		assert(lay.ports.size() > 0, "%s has street ends" % k)
		var joined: bool = ch._knn(m).any(func(q): return _joined(ch, lay.ports, ch._layout(q).ports))
		print("%s at %s, %s px (seed %d, %s): %d POIs, ports %s, joined by road: %s" % [k, m, ch._mid(s.center, s.center), found[k][0], CM.REGIONS[s.reg], pois, lay.ports, joined])
		assert(joined, "%s joined by road to a neighbour" % k)
		var near: Array = ch.sites_near(ch._mid(s.center, s.center), 100.0, k)
		assert(near.size() == 1 and near[0].uid == s.uid, "sites_near finds the %s by kind" % k)
		ch.queue_free()
	assert("harbour" in main.bandits.CAMP_KINDS and main.outposts.SITE_KINDS.has("harbour"), "harbours hold bandit camps and outposts")
	for k in ["hospital", "harbour", "stadium", "power_plant"]:
		assert(main.convoys.LOOT.has(k), "convoys loot the %s" % k)
	assert(main.missions.ROOF_SITES.has("hospital") and main.missions.SCREAMER_SITES.has("stadium"), "missions at hospitals and stadiums")
	# 3. order independence over the coast and the snow
	for area: String in areas:
		Game.seed = areas[area][0]
		var mc: Vector2i = areas[area][1]
		var a := _fresh()
		var centre: Vector2i = a._chunk_of(a.site(mc).center)
		var chunks := []
		for y in range(-2, 3):
			for x in range(-3, 3):
				chunks.append(centre + Vector2i(x, y))
		var props_a := _props(func(): for c in chunks: a._ensure(c))
		var b := _fresh()
		for c in [centre + Vector2i(20, -9), centre + Vector2i(-11, 7)]: # another cache history first
			b._ensure(c)
		var rev := chunks.duplicate()
		rev.reverse()
		var props_b := _props(func(): for c in rev: b._ensure(c))
		var bad := 0
		var tiles := {}
		var iced := 0 # straight road cells on ice wider than a ford: must have become bridges
		for c: Vector2i in chunks:
			for k in CM.CHUNK * CM.CHUNK:
				var cell := c * CM.CHUNK + Vector2i(k % CM.CHUNK, k / CM.CHUNK)
				tiles[a.get_cell_atlas_coords(cell).x] = true
				var at: int = a.get_cell_atlas_coords(cell).x
				if at in [T.ROAD, T.DIRT_ROAD] and a._terrain(cell) & 0xff == T.ICE and mini(a._wet(cell, Vector2i(1, 0)), a._wet(cell, Vector2i(0, 1))) > CM.FORD:
					iced += 1
				if a.get_cell_atlas_coords(cell) != b.get_cell_atlas_coords(cell) or a.get_cell_alternative_tile(cell) != b.get_cell_alternative_tile(cell):
					bad += 1
		var inside := func(p): return chunks.has(Vector2i((p[1] / (CM.CHUNK * CM.TILE)).floor()))
		props_a = props_a.filter(inside)
		props_b = props_b.filter(inside)
		print("%s at %s px (seed %d, chunk %s): %d cells differ, %d props and POIs, tiles %s" % [area, a._mid(a.site(mc).center, a.site(mc).center), Game.seed, centre, bad, props_a.size(), tiles.keys()])
		assert(bad == 0, "%s: same tiles in both orders" % area)
		assert(iced == 0, "%s: %d road cells lie on wide ice without a bridge" % [area, iced])
		assert(var_to_str(props_a) == var_to_str(props_b), "%s: same props and POIs in both orders" % area)
		for ch: TileMapLayer in [a, b]:
			ch.queue_free()
	# 4. the sea and frozen lakes, loaded
	var ice_ok := false
	var sea_ok := false
	var shore_at := Vector2.INF # a dune by the sea in the first seed, for previews (SHOT_AT)
	for sd: int in SEEDS:
		Game.seed = sd
		var ch := _fresh()
		for x in range(-6000, 6001, 50):
			for y in range(-6000, 6001, 50):
				if ice_ok and sea_ok and shore_at != Vector2.INF:
					break
				var c := Vector2i(x, y)
				var t: int = ch._terrain(c)
				if shore_at == Vector2.INF and t == T.DUNE and ch._water_dir(c, 12, true) != Vector2i.ZERO:
					shore_at = ch._mid(c, c)
					print("coastline at %s px (seed %d)" % [shore_at, sd])
				if not ice_ok and t == T.ICE and ch._ft(c) == T.ICE:
					ch._ensure(ch._chunk_of(c))
					var at: Vector2 = ch._mid(c, c)
					assert(ch.tile_at(at) == T.ICE and ch.is_landable(at) and not T.ICE in main.SOLID, "a frozen lake is landable and walkable")
					var across := [] # a paved road straight over the ice: bridge cells wherever it is frozen
					for k in range(-3, 4):
						across.append(c + Vector2i(0, k))
					for p: Array in ch._paved_path(across, true):
						assert(ch._tile(p[0]) != T.ICE or p[1].x == T.BRIDGE, "a paved road crosses ice on a bridge")
					ice_ok = true
				if not sea_ok and t == T.WATER | CM.SEA << 8 and ch._ft(c) == T.WATER:
					ch._ensure(ch._chunk_of(c))
					var at: Vector2 = ch._mid(c, c)
					assert(ch.get_cell_alternative_tile(c) == CM.SEA and not ch.is_landable(at) and T.WATER in main.SOLID, "the sea is neither landable nor walkable")
					sea_ok = true
		ch.queue_free()
	assert(ice_ok and sea_ok, "found a frozen lake and the sea to land on")
	# 5. a flight over the stadium
	Game.seed = found["stadium"][0]
	var fl := _fresh()
	var st: Dictionary = fl.site(found["stadium"][1])
	var target: Vector2 = fl._mid(st.center, st.center)
	fl.process_mode = Node.PROCESS_MODE_ALWAYS
	var heli: Node2D = Game.heli
	var keep: Vector2 = heli.position
	heli.position = target - Vector2(2600, 0)
	await get_tree().process_frame # the jump
	var worst := 0.0
	while heli.position.x < target.x + 2600.0:
		heli.position.x += 115.0 / 60.0 * 4.0
		var t0 := Time.get_ticks_usec()
		fl._process(1.0 / 60.0)
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	print("flight over the stadium: worst frame %.1f ms, %d chunks" % [worst, fl.loaded.size()])
	assert(worst < 50.0, "no frame over 50 ms flying over the stadium")
	fl.process_mode = Node.PROCESS_MODE_DISABLED
	heli.position = keep
	fl.queue_free()
	Game.seed = seed0
	# 6. landmarks.gd
	var lm: Node = main.landmarks
	var e0 := get_tree().get_nodes_in_group("enemies").size()
	lm._horde({"kind": "stadium", "uid": "test:stadium", "pos": heli.position + Vector2(600, 0)})
	var e1 := get_tree().get_nodes_in_group("enemies").size()
	print("stadium horde: %d zombies" % (e1 - e0))
	assert(e1 - e0 >= lm.HORDES["stadium"] / 2 and "test:stadium" in lm.woken, "the stadium's horde pours out once")
	lm._seq0 = Game.person_seq
	var before: int = Game.passengers
	Game.passengers += 2
	lm._medics()
	var aboard := Game.people.filter(func(p): return p["aboard"] and p["id"] >= lm._seq0)
	assert(aboard.size() == 2 and aboard.all(func(p): return p["skill"] == "medic"), "people boarding at the hospital are medics")
	Game.passengers = before
	lm._seq0 = -1
	Game.buildings.append({"kind": "generator", "cell": Vector2i(-99, -99), "built": true, "progress": 0.0})
	Game.base_founded = true
	Game.power = true
	Game.base_fuel = 100.0
	lm.parts = 1
	lm._process(Game.DAY_SECONDS * 0.1)
	var paid: float = Game.base_fuel - 100.0
	assert(absf(paid - Game.GEN_FUEL * lm.PART_SAVE * 0.1 * Game.built("generator")) < 0.01, "a power part pays back generator fuel (%.2f)" % paid)
	assert(is_equal_approx(lm.gen_fuel(), Game.built("generator") * Game.GEN_FUEL * (1.0 - lm.PART_SAVE)), "the HUD's gen fuel/day counts the part")
	var pp: Dictionary = {}
	for r in SEARCH:
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				if pp.is_empty() and maxi(absi(x), absi(y)) == r and main.chunks.site(Vector2i(x, y)).kind == "power_plant":
					pp = main.chunks.site(Vector2i(x, y))
	if not pp.is_empty(): # this run's seed is random
		lm.parts = 0
		heli.position = main.chunks._mid(pp.center, pp.center)
		lm._on_landed(true)
		assert(lm.parts == 1 and pp.uid in lm.claimed, "landing at the power plant takes its part")
		lm._on_landed(true)
		assert(lm.parts == 1, "only once")
		heli.position = keep
	var saved: Dictionary = lm.save_state()
	lm.load_state({})
	assert(lm.parts == 0 and lm.woken.is_empty(), "load of an empty state")
	lm.load_state(saved)
	assert(lm.parts == 1 and "test:stadium" in lm.woken, "save and load")
	print("WORLD2 OK")
	get_tree().quit(0)


## A new generator next to main's (no processing) with the current Game.seed.
func _fresh() -> TileMapLayer:
	var ch: TileMapLayer = CM.new()
	ch.process_mode = Node.PROCESS_MODE_DISABLED
	main.add_child(ch)
	return ch


## [kind, position] of every prop and POI main gets while `f` runs, sorted.
func _props(f: Callable) -> Array:
	var n := main.get_child_count()
	f.call()
	var out := []
	for i in range(n, main.get_child_count()):
		var p: Node = main.get_child(i)
		if p is Node2D and not p is TileMapLayer:
			out.append([p.get("kind") if p.get("kind") != null else p.get_child(0).texture.resource_path if p.get_child_count() > 0 and p.get_child(0) is Sprite2D else "", p.position.round()])
	out.sort_custom(func(x, y): return var_to_str(x) < var_to_str(y))
	return out


## A landable composed cell within 2 cells (the heli lands within the POI's 48 px).
func _landable_near(ch: TileMapLayer, c: Vector2i) -> bool:
	for k in 25:
		if not ch._ft(c + Vector2i(k % 5 - 2, k / 5 - 2)) in CM.BLOCKED:
			return true
	return false


## Breadth-first search over road, plaza and car park cells (composed layers, nothing loaded) from `ends` to `goals`.
func _joined(ch: TileMapLayer, ends: Array, goals: Array) -> bool:
	var goal := {}
	for g: Vector2i in goals:
		goal[g] = true
	var drive: Array = CM.ROADS + [T.PLAZA, T.PARKING]
	var seen := {}
	var q := ends.duplicate()
	for e: Vector2i in q:
		seen[e] = true
	var i := 0
	while i < q.size() and i < 40000:
		var c: Vector2i = q[i]
		i += 1
		if goal.has(c):
			return true
		for dir: Vector2i in CM.DIRS:
			if not seen.has(c + dir) and (goal.has(c + dir) or ch._ft(c + dir) in drive):
				seen[c + dir] = true
				q.append(c + dir)
	return false
