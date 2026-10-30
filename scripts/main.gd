extends Node2D
## World root. Builds everything in code; other scripts reach it through Game.world.

var chunks: TileMapLayer
var heli: Node2D
var base: Node2D
var spawner: Node
var hud: CanvasLayer
var choice_ui: CanvasLayer
var night: CanvasModulate
var radio_target: Node2D # POI currently highlighted on the HUD compass
var ui_open := false # overlays set this so clicks do not fire the gun
var tutorial: Node # tutorial.gd while one runs
var morale: Node # morale.gd
var assault: Node # assault.gd
var bandits: Node # bandits.gd
var wear: Node # wear.gd
var missions: Node # missions.gd (radio missions, J)
var outposts: Node2D # outposts.gd: outposts and allied villages
var wrecks: Node2D # wrecks.gd: heli wrecks, sling hook, repairs, fleet (P15)
var modifiers: Node # modifiers.gd: run modifiers (P15)
var pois := []
var _nav_cache := {} # Rect2i region -> [AStarGrid2D, ticks_msec built]

var BASE_POS := Vector2(16 * 16 + 8, 16 * 16 + 8) # the heli's start (centre of chunk (0,0)) until found_base moves it
const T := preload("res://scripts/chunk_manager.gd").T
const SOLID := [T.WATER, T.BUILDING, T.ROCK, T.WAREHOUSE, T.HEDGE] # walkers (zombies, survivors) cannot enter


func _ready() -> void:
	Game.world = self
	var loaded := Save.pending and Save.load_run() # CONTINUE; each hook below loads as it registers
	if not loaded:
		Game.new_run()
	Save.register("game", Game.save_state, Game.load_state) # before chunks: the replay needs Game.seed
	chunks = preload("res://scripts/chunk_manager.gd").new()
	add_child(chunks)
	base = preload("res://scripts/base.gd").new()
	base.position = BASE_POS
	base.z_index = 1
	base.visible = false # hidden and inactive until found_base
	base.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(base)
	heli = preload("res://scripts/heli.gd").new()
	heli.position = BASE_POS
	heli.z_index = 10
	heli.landed = true
	add_child(heli)
	var cam := Camera2D.new()
	cam.zoom = Vector2(2, 2)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	heli.add_child(cam)
	cam.add_child(preload("res://scripts/shaker.gd").new())
	Save.register("heli", heli.save_state, heli.load_state)
	Save.register("world", chunks.save_state, chunks.load_state)
	Save.register("pois", _save_pois, _load_pois)
	Save.register("base", base.save_state, base.load_state)
	Save.register("enemies", _save_enemies, _load_enemies)
	morale = preload("res://scripts/morale.gd").new() # registers its own save hook
	add_child(morale)
	assault = preload("res://scripts/assault.gd").new() # registers its own save hook
	add_child(assault)
	bandits = preload("res://scripts/bandits.gd").new() # registers its own save hook
	add_child(bandits)
	wear = preload("res://scripts/wear.gd").new() # registers its own save hook
	add_child(wear)
	outposts = preload("res://scripts/outposts.gd").new() # registers its own save hook
	add_child(outposts)
	modifiers = preload("res://scripts/modifiers.gd").new() # registers its own save hook
	add_child(modifiers)
	wrecks = preload("res://scripts/wrecks.gd").new() # registers its own save hook
	add_child(wrecks)
	night = CanvasModulate.new()
	add_child(night)
	spawner = preload("res://scripts/spawner.gd").new()
	add_child(spawner)
	add_child(preload("res://scripts/radio.gd").new())
	missions = preload("res://scripts/missions.gd").new() # registers its own save hook
	add_child(missions)
	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	add_child(preload("res://scripts/missions_ui.gd").new())
	choice_ui = preload("res://scripts/choice_ui.gd").new()
	add_child(choice_ui)
	add_child(preload("res://scripts/game_over_ui.gd").new())
	add_child(preload("res://scripts/settings_ui.gd").new())
	Game.level_up.connect(func(lvl: int): offer_upgrades("Level %d reached" % lvl))
	Game.day_changed.connect(_settlements_decline)
	var smoke := OS.get_environment("SMOKE")
	var test: String = {"1": "smoke", "poi": "poi_test", "ui": "ui_test", "shot": "shot", "prog": "progression_test", "tut": "tutorial_test"}.get(smoke, "")
	if test == "" and smoke != "" and ResourceLoader.exists("res://tests/%s_test.gd" % smoke): # SMOKE=<name> runs tests/<name>_test.gd
		test = smoke + "_test"
	if test != "" and not test in ["found_test", "shot", "save_test"] and not loaded: # the older tests expect a founded, empty base at the start site
		Game.passengers = 0
		found_base(BASE_POS)
		base.ui.close()
	if test != "":
		add_child(load("res://tests/%s.gd" % test).new())
	elif not loaded:
		_show_title()
	if loaded:
		return
	Game.radio("Command: pick a site with open ground near towns and water, land and found the FOB (B).")
	Game.radio("Controls: WASD fly, mouse aim/fire, SPACE land or take off.")


func _show_title() -> void:
	var title: CanvasLayer = preload("res://scripts/title_ui.gd").new()
	add_child(title)
	Game.running = false
	ui_open = true
	hud.visible = false
	title.start_pressed.connect(func():
		Game.running = true
		ui_open = false
		hud.visible = true
		modifiers.start(title.mods)
		wrecks.set_start_type(title.start_heli)
		Online.begin_run(modifiers.active)
		if title.tutorial or Game.meta["tutorial_done"] == 0:
			start_tutorial()
		Sfx.play("ui"))
	title.open()


## B on open ground (heli.gd): the FOB goes up at `pos` (snapped to the 16 px grid). Pad and field workshop, the founding
## crew moves in (2 of them on Build so the barracks gets built), the assault clock starts (first on day + 2).
func found_base(pos: Vector2) -> void:
	place_base(Vector2i((pos / 16.0).floor()))
	Game.base_founded = true
	Game.base_level["workshop"] = 1
	Game.first_assault_day = Game.day + 2
	Game.workers["build"] = mini(2, Game.passengers - Game.passengers_injured) # the hurt need the clinic, not a job
	for i in mini(Game.deliver(), base.PAWN_MAX):
		base.add_pawn(heli.global_position + Vector2(randf_range(-12, 12), randf_range(8, 16)), true)
	Game.radio("Base: field workshop set up.")
	Game.radio("FOB founded. Crew is setting up. Build a barracks (40 scrap) and sandbags; the first assault comes on day %d." % Game.first_assault_day)
	base._on_landed(true) # the heli sits on the new pad: services and the base menu


## The world side of founding (also replayed by a loaded run, chunk_manager.load_state): pad at `cell`, base shown.
func place_base(cell: Vector2i) -> void:
	BASE_POS = Vector2(cell) * 16.0 + Vector2(8, 8)
	base.position = BASE_POS
	chunks.paint_base_at(cell)
	base.visible = true
	base.process_mode = Node.PROCESS_MODE_INHERIT


func start_tutorial() -> void:
	tutorial = preload("res://scripts/tutorial.gd").new()
	add_child(tutorial)


func _process(_delta: float) -> void:
	var d := Game.darkness()
	night.color = Color(1, 1, 1).lerp(Assault.sky(), d)


## Off-screen settlements slowly fall to the horde: rescue early or lose them.
func _settlements_decline(_day: int) -> void:
	var lost := 0
	for p in pois:
		if is_instance_valid(p) and p.kind == "survivors" and not p.done and randf() < 0.3:
			p.lose_survivor(true)
			if p.done:
				lost += 1
	if lost > 0:
		Game.radio("Command: contact lost with %d settlement(s) overnight." % lost)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not Game.running:
		get_tree().reload_current_scene()


## Open ground that is not under a finished base building.
func is_landable(pos: Vector2) -> bool:
	return chunks.is_landable(pos) and not base.building_at(Vector2i((pos / 16.0).floor())).get("built", false)


## Ground a zombie or survivor can walk on: no solid terrain, built sandbag (wire is walkable) or finished base building.
func is_walkable(pos: Vector2) -> bool:
	var cell := Vector2i((pos / 16.0).floor())
	var bag: Dictionary = Game.sandbags.get(cell, {})
	return not chunks.tile_at(pos) in SOLID and not (bag.get("built", false) and bag["kind"] == "sandbag") \
		and not base.building_at(cell).get("built", false)


## Blocking cells changed (house broken into, sandbag built or chewed, building finished): drop cached nav grids.
func nav_dirty() -> void:
	_nav_cache.clear()


## A* waypoints (cell centres, start cell excluded) from `from` towards `to` on the 16 px grid, searched in the
## bounding box of both padded by 8 cells and capped at max_cells per side. A solid `to` (a house) aims at the
## nearest walkable cell around it; a walled-off or out-of-box target gets the path to the closest reachable cell.
## Empty when `from` is solid or nothing gets closer.
func nav_path(from: Vector2, to: Vector2, max_cells := 48) -> PackedVector2Array:
	var fc := Vector2i((from / 16.0).floor())
	var tc := Vector2i((to / 16.0).floor())
	var lo := Vector2i.ZERO
	var size := Vector2i.ZERO
	for a in 2:
		var l := mini(fc[a], tc[a]) - 8
		var h := maxi(fc[a], tc[a]) + 8
		if h - l + 1 > max_cells: # keep `from` inside, reach towards `to`
			l = fc[a] - 8 if tc[a] > fc[a] else fc[a] + 9 - max_cells
			h = l + max_cells - 1
		lo[a] = floori(l / 8.0) * 8 # snapped to 8 cells so nearby walkers share cached grids
		size[a] = mini(ceili((h - lo[a] + 1) / 8.0) * 8, max_cells)
	var region := Rect2i(lo, size)
	var grid := _nav_grid(region)
	if grid.is_point_solid(fc):
		return PackedVector2Array()
	tc = tc.clamp(region.position, region.end - Vector2i.ONE)
	if grid.is_point_solid(tc):
		var best := tc
		var best_d := INF
		for r in range(1, 8):
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					var c := tc + Vector2i(x, y)
					var d := Vector2(c - fc).length_squared()
					if (absi(x) == r or absi(y) == r) and d < best_d and region.has_point(c) and not grid.is_point_solid(c):
						best_d = d
						best = c
			if best != tc:
				break
		tc = best
	var path := grid.get_point_path(fc, tc, true)
	if not path.is_empty():
		path.remove_at(0)
	return path


## Cached AStarGrid2D for `region` (64 kept, rebuilt after 1 s or nav_dirty()).
func _nav_grid(region: Rect2i) -> AStarGrid2D:
	var now := Time.get_ticks_msec()
	if _nav_cache.has(region) and now - _nav_cache[region][1] < 1000:
		return _nav_cache[region][0]
	var grid := AStarGrid2D.new()
	grid.region = region
	grid.cell_size = Vector2(16, 16)
	grid.offset = Vector2(8, 8)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	# the cells is_walkable rejects, stamped per source (building_at per cell would be too slow)
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			if chunks.get_cell_atlas_coords(Vector2i(x, y)).x in SOLID:
				grid.set_point_solid(Vector2i(x, y))
	for c in Game.sandbags:
		if Game.sandbags[c]["built"] and Game.sandbags[c]["kind"] == "sandbag" and region.has_point(c):
			grid.set_point_solid(c)
	for b in Game.buildings:
		var n: int = Game.BUILDINGS[b["kind"]][3]
		if b["built"] and n > 0:
			grid.fill_solid_region(Rect2i(b["cell"], Vector2i(n, n)).intersection(region))
	_nav_cache.erase(region)
	_nav_cache[region] = [grid, now]
	if _nav_cache.size() > 64:
		_nav_cache.erase(_nav_cache.keys()[0]) # oldest
	return grid


## True if a walker cannot go straight from `a` to `b` (sampled every 8 px over the first 512 px).
func _line_blocked(a: Vector2, b: Vector2) -> bool:
	var n := ceili(a.distance_to(b) / 8.0)
	for i in range(1, mini(n, 64) + 1):
		if not is_walkable(a.lerp(b, float(i) / n)):
			return true
	return false


## Walk `node` towards `target` at `speed`: straight while the line is free, else along nav_path, replanned when the
## goal moves 24 px, the path runs out or every ~1.5 s (random phase), sliding if a step is blocked. `state` is the
## walker's own {} (path, i, t, goal; stuck = seconds without 4 px of progress, measured from p). True within 6 px.
func nav_move(node: Node2D, target: Vector2, speed: float, delta: float, state: Dictionary) -> bool:
	var pos := node.global_position
	if pos.distance_to(target) < 6.0:
		state["stuck"] = 0.0
		return true
	if not state.has("path"):
		state.merge({"path": PackedVector2Array(), "i": 0, "t": 0.0, "goal": target, "stuck": 0.0, "p": pos})
	var path: PackedVector2Array = state["path"]
	state["t"] -= delta
	if state["t"] <= 0.0 or (state["t"] < 0.75 and state["goal"].distance_to(target) > 24.0): # >= 0.25 s apart
		state["t"] = randf_range(1.0, 2.0) # random phase keeps a horde's replans spread over frames
		state["goal"] = target
		state["i"] = 0
		state["path"] = nav_path(pos, target) if _line_blocked(pos, target) else PackedVector2Array()
		path = state["path"]
	var wp: Vector2 = path[state["i"]] if state["i"] < path.size() else target
	node.global_position += slide(pos, pos.move_toward(wp, speed * delta) - pos)
	if state["i"] < path.size() and node.global_position.distance_to(wp) < 4.0:
		state["i"] += 1
		if state["i"] >= path.size():
			state["t"] = 0.0 # path walked: replan from here (straight if the line is free now)
	if node.global_position.distance_to(state["p"]) > 4.0:
		state["p"] = node.global_position
		state["stuck"] = 0.0
	else:
		state["stuck"] += delta
	return node.global_position.distance_to(target) < 6.0


## The part of `step` a walker at `from` may take: the full step, else slide along x or y, else none.
## Walkers already stuck inside a solid cell move freely so they can get out.
func slide(from: Vector2, step: Vector2) -> Vector2:
	if not is_walkable(from):
		return step
	for s in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
		if is_walkable(from + s):
			return s
	return Vector2.ZERO


func spawn_poi(kind: String, pos: Vector2, rng: RandomNumberGenerator, count := 0) -> Node2D:
	var p: Node2D = preload("res://scripts/poi.gd").new()
	p.setup(kind, pos, rng, count)
	p.uid = chunks.poi_uid()
	p.z_index = 1
	add_child(p)
	pois.append(p)
	return p


func spawn_enemy(kind: String, pos: Vector2, target_base := false) -> Node2D:
	var e: Node2D = preload("res://scripts/enemy.gd").new()
	e.setup(kind, pos, Game.danger_at(pos), target_base)
	add_child(e)
	return e


## Save hook "pois": changed state per uid; dynamic POIs ("dyn#n": tutorial, supply drops) whole, rebuilt on load.
func _save_pois() -> Dictionary:
	var out := {}
	for p in pois:
		if is_instance_valid(p) and not p.is_queued_for_deletion():
			out[p.uid] = p.save_state()
	return {"pois": out, "radio_target": radio_target.uid if is_instance_valid(radio_target) else ""}


func _load_pois(d: Dictionary) -> void:
	var by_uid := {}
	for p in pois:
		by_uid[p.uid] = p
	for uid in d["pois"]:
		var s: Dictionary = d["pois"][uid]
		var p: Node2D = by_uid.get(uid)
		if p == null and uid.begins_with("dyn#"):
			p = spawn_poi(s["kind"], s["pos"], RandomNumberGenerator.new(), s["count"])
			p.uid = uid
			by_uid[uid] = p
		if p:
			p.load_state(s)
	radio_target = by_uid.get(d["radio_target"])


const ENEMIES_SAVED := 150 # base attackers, then the nearest to the base or heli; the rest are dropped


## Save hook "enemies": kind, position, hp and stats, target_base.
func _save_enemies() -> Array:
	var list := get_tree().get_nodes_in_group("enemies").filter(func(e): return "target_base" in e and not e.is_queued_for_deletion())
	var near := func(e: Node2D) -> float: return minf(e.position.distance_squared_to(heli.position), e.position.distance_squared_to(base.position))
	list.sort_custom(func(a, b): return a.target_base and not b.target_base or a.target_base == b.target_base and near.call(a) < near.call(b)) # attackers first
	return list.slice(0, ENEMIES_SAVED).map(func(e): return [e.kind, e.position, e.hp, e.max_hp, e.speed, e.dmg, e.target_base, e.state.duplicate()])


func _load_enemies(d: Array) -> void:
	for a in d:
		var e := spawn_enemy(a[0], a[1], a[6])
		e.hp = a[2]
		e.max_hp = a[3]
		e.speed = a[4]
		e.dmg = a[5]
		if a.size() > 7: # runs saved before the new infected have no ability state
			e.state = a[7] # a screamer mid-wind-up screams on


## Decorative sprite (church, barn, tree, fence...) placed by the chunk generator. Not interactive.
func spawn_prop(name: String, pos: Vector2, rot := 0.0) -> Node2D:
	var p := Node2D.new()
	p.position = pos
	p.rotation = rot
	p.z_index = 1
	p.add_child(Art.sprite(name))
	add_child(p)
	return p


func spawn_fx(pos: Vector2, scale_factor := 1.0) -> void:
	var fx: Node2D = preload("res://scripts/fx.gd").new()
	fx.position = pos
	fx.scale = Vector2.ONE * scale_factor
	add_child(fx)


## Pause and let the player pick one of `n` item cards (default 3, Veteran Lv5 4).
func offer_upgrades(title: String, n := 0) -> void:
	choice_ui.open(title, n if n > 0 else (4 if Progression.level("veteran") >= 5 else 3))
