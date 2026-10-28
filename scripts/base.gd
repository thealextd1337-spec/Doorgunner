extends Node2D
## Forward operating base: pad, turrets, sandbags (blueprints built by Build workers), militia defenders,
## base HP, landing services and the upgrade menu. Buildings (Game.buildings) and perimeter expansions are
## blueprints too; a generator powers a night light over the perimeter.

const RADIUS := 60.0
const PAD_REACH := 48.0
const CELL := 16.0
const PAD_CLEAR := 40.0 # no sandbags on the helipad
const HANGAR := Rect2(-86, -56, 32, 32) # local rect of the hangar sprite, kept clear
const WATER_REACH := 400.0 # water job needs a river or lake this close
const TINTS := {"barracks": Color(0.62, 0.7, 0.36), "clinic": Color(1.5, 1.5, 1.5), "generator": Color(0.36, 0.36, 0.4), "well": Color(0.58, 0.68, 0.82)}
const Chunks := preload("res://scripts/chunk_manager.gd")
const Pawn := preload("res://scripts/base_pawn.gd")
const PAWN_MAX := 60 # drawn people; beyond that the base only counts

var turrets: Node2D
var sandbags: Node2D # one Sprite2D per cell, keyed in bags
var defenders: Node2D # militia posted during an assault (invisible: militia pawns stand on the posts)
var pawns: Node2D # base_pawn.gd, one per rescued up to PAWN_MAX
var pawn_t := 0.0 # seconds to the next sync_pawns
var fields: Array = [] # FIELD tile centres inside the perimeter, cached per radius
var fields_r := -1.0
var water_spot: Variant = null # nearest river or lake cell, cached once found
var sites: Node2D # one node per building, keyed in site_nodes
var fence: Node2D
var light: PointLight2D
var ui: CanvasLayer
var bags := {} # Vector2i cell -> Sprite2D
var site_nodes := {} # Vector2i top-left cell -> Node2D
var build_progress := 0.0 # blueprints finished per 20 s per build worker, carried between frames
var place_kind := "sandbag" # what LMB places: "sandbag" or a Game.BUILDINGS kind
var placing := false: # BUILD tab toggle: LMB places a blueprint, RMB removes
	set(v):
		placing = v
		if ui:
			ui.refresh()


func _ready() -> void:
	var pad := Art.sprite("helipad")
	add_child(pad)
	var hangar := Art.sprite("hangar")
	hangar.position = HANGAR.get_center()
	add_child(hangar)
	sites = Node2D.new()
	add_child(sites)
	fence = Node2D.new()
	add_child(fence)
	light = PointLight2D.new()
	var g := GradientTexture2D.new()
	g.width = 256
	g.height = 256
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color.WHITE)
	g.gradient.set_color(1, Color(1, 1, 1, 0))
	light.texture = g
	light.color = Color(1.0, 0.85, 0.6)
	light.energy = 0.9
	light.blend_mode = Light2D.BLEND_MODE_ADD
	light.enabled = false
	add_child(light)
	_fence()
	sandbags = Node2D.new()
	add_child(sandbags)
	turrets = Node2D.new()
	add_child(turrets)
	defenders = Node2D.new()
	add_child(defenders)
	pawns = Node2D.new()
	add_child(pawns)
	ui = preload("res://scripts/base_ui.gd").new()
	add_child(ui)
	rebuild()
	Game.base_attack_started.connect(_on_attack)
	call_deferred("_connect_heli") # heli is created after the base


func _connect_heli() -> void:
	Game.heli.landed_changed.connect(_on_landed)


## Rebuild the turret ring from Game.base_level.
func rebuild() -> void:
	for n in turrets.get_children():
		n.free()
	var turret_count: int = Game.base_level.get("turrets", 0)
	for i in turret_count:
		var t := preload("res://scripts/turret.gd").new()
		t.position = Vector2(70, 0).rotated(i * TAU / turret_count)
		turrets.add_child(t)


func _process(delta: float) -> void:
	queue_redraw()
	if not Game.attack_active and defenders.get_child_count() > 0:
		for d in defenders.get_children():
			d.queue_free()
	light.enabled = Game.power and Game.is_night()
	pawn_t -= delta
	if pawn_t <= 0.0:
		pawn_t = 0.5
		sync_pawns()
	if Game.workers["build"] <= 0:
		return
	var site: Dictionary = next_site() # buildings and perimeter work first, then sandbags
	var crew: float = Game.workers["build"] * Game.work_eff() # campers build at half rate
	if not site.is_empty():
		site["progress"] += crew * delta
		if site["progress"] >= Game.BUILDINGS[site["kind"]][2]:
			_finish_site(site)
		return
	build_progress += crew * delta / Game.BUILD_SECONDS
	while build_progress >= 1.0:
		var cell: Variant = _nearest_blueprint()
		if cell == null:
			build_progress = 0.0
			break
		build_progress -= 1.0
		Game.sandbags[cell]["built"] = true
		bags[cell].modulate.a = 1.0
		Game.world.nav_dirty()


func _draw() -> void:
	if placing:
		draw_arc(Vector2.ZERO, Game.base_radius, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 1.0)
	if Game.base_hp >= Game.max_base_hp and not Game.attack_active:
		return
	draw_rect(Rect2(-40, -46, 80, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-39, -45, 78 * clampf(Game.base_hp / Game.max_base_hp, 0.0, 1.0), 4), Color(0.9, 0.3, 0.3))


func _input(event: InputEvent) -> void:
	if placing and event.is_action_pressed("menu"):
		placing = false


func _unhandled_input(event: InputEvent) -> void:
	if not placing or not (event is InputEventMouseButton and event.pressed):
		return
	var cell := Vector2i((get_global_mouse_position() / CELL).floor())
	if event.button_index == MOUSE_BUTTON_LEFT and place_kind != "sandbag":
		var n: int = Game.BUILDINGS[place_kind][3] # the footprint is centred on the mouse
		place_building(place_kind, Vector2i(((get_global_mouse_position() - Vector2(n - 1, n - 1) * CELL / 2) / CELL).floor()))
	elif event.button_index == MOUSE_BUTTON_LEFT:
		place_sandbag(cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		remove_sandbag(cell)
		remove_blueprint(cell)


func cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL / 2, CELL / 2)


## A cell a sandbag or building may take: inside the perimeter, off the pad and hangar, landable, unused.
func free_cell(cell: Vector2i) -> bool:
	var pos := cell_pos(cell)
	var d := pos.distance_to(global_position)
	return d <= Game.base_radius and d >= PAD_CLEAR and not HANGAR.has_point(pos - global_position) and Game.world.is_landable(pos) \
		and not Game.sandbags.has(cell) and building_at(cell).is_empty()


## Blueprint for 5 scrap inside the perimeter, up to 80.
func place_sandbag(cell: Vector2i) -> bool:
	if Game.sandbags.size() >= Game.SANDBAG_MAX or Game.scrap < Game.SANDBAG_COST or not free_cell(cell):
		return false
	var pos := cell_pos(cell)
	Game.scrap -= Game.SANDBAG_COST
	Game.sandbags[cell] = {"hp": Game.SANDBAG_HP, "built": false}
	var s := Art.sprite("wall")
	s.position = pos - global_position
	s.modulate.a = 0.4
	sandbags.add_child(s)
	bags[cell] = s
	ui.refresh()
	return true


## RMB: blueprints are refunded, built sandbags are just torn down.
func remove_sandbag(cell: Vector2i) -> void:
	if not Game.sandbags.has(cell):
		return
	if not Game.sandbags[cell]["built"]:
		Game.scrap += Game.SANDBAG_COST
	_free_sandbag(cell)
	ui.refresh()


## Zombies chew on a built sandbag in their way (enemy.gd); at 0 hp it is gone.
func damage_sandbag(cell: Vector2i, amount: float) -> void:
	Game.sandbags[cell]["hp"] -= amount
	Sfx.play("base_hit", cell_pos(cell), -14.0)
	if Game.sandbags[cell]["hp"] <= 0.0:
		Game.world.spawn_fx(cell_pos(cell), 0.5)
		_free_sandbag(cell)


func _free_sandbag(cell: Vector2i) -> void:
	Game.sandbags.erase(cell)
	bags[cell].queue_free()
	bags.erase(cell)
	Game.world.nav_dirty()


func _nearest_blueprint() -> Variant:
	var best: Variant = null
	var best_d := INF
	for cell in Game.sandbags:
		if Game.sandbags[cell]["built"]:
			continue
		var d: float = cell_pos(cell).distance_squared_to(global_position + Vector2(-70, -40)) # hangar first
		if d < best_d:
			best_d = d
			best = cell
	return best


## Building (or perimeter stage) whose footprint covers `cell`, {} if none.
func building_at(cell: Vector2i) -> Dictionary:
	for b in Game.buildings:
		var n: int = Game.BUILDINGS[b["kind"]][3]
		if Rect2i(b["cell"], Vector2i(n, n)).has_point(cell):
			return b
	return {}


func building_cost(kind: String) -> int:
	if kind == "perimeter":
		return Game.BUILDINGS[kind][1] * (perimeter_level() + 1)
	return Game.BUILDINGS[kind][1]


## Perimeter stages built or under construction.
func perimeter_level() -> int:
	return Game.buildings.filter(func(b): return b["kind"] == "perimeter").size()


## Blueprint of a building with its top-left at `cell`; workers on Build duty finish it.
func place_building(kind: String, cell: Vector2i) -> bool:
	var n: int = Game.BUILDINGS[kind][3]
	if Game.scrap < building_cost(kind):
		return false
	for x in n:
		for y in n:
			if not free_cell(cell + Vector2i(x, y)):
				return false
	Game.scrap -= building_cost(kind)
	var b := {"kind": kind, "cell": cell, "built": false, "progress": 0.0}
	Game.buildings.append(b)
	_site_node(b)
	for x in range(-1, n + 1): # base floor tiles only around the buildings
		for y in range(-1, n + 1):
			var c := cell + Vector2i(x, y)
			if Game.world.chunks.is_landable(cell_pos(c)):
				Game.world.chunks.set_cell(c, 0, Vector2i(Chunks.T.BASE_FLOOR, 0))
	if ui:
		ui.refresh()
	return true


## Next perimeter stage (+60 px, 60 scrap x stage, 60 s of building), one at a time, up to 5.
func expand_perimeter() -> bool:
	if perimeter_level() >= Game.PERIMETER_MAX or not next_site("perimeter").is_empty() or Game.scrap < building_cost("perimeter"):
		return false
	Game.scrap -= building_cost("perimeter")
	Game.buildings.append({"kind": "perimeter", "cell": Vector2i.ZERO, "built": false, "progress": 0.0})
	if ui:
		ui.refresh()
	return true


## RMB on a building blueprint: refunded and gone. Finished buildings stay.
func remove_blueprint(cell: Vector2i) -> void:
	var b := building_at(cell)
	if b.is_empty() or b["built"]:
		return
	Game.scrap += building_cost(b["kind"])
	Game.buildings.erase(b)
	site_nodes[b["cell"]].queue_free()
	site_nodes.erase(b["cell"])
	if ui:
		ui.refresh()


func _site_node(b: Dictionary) -> void:
	var n: int = Game.BUILDINGS[b["kind"]][3]
	var node := Node2D.new()
	node.position = cell_pos(b["cell"]) + Vector2(n - 1, n - 1) * CELL / 2 - global_position
	node.modulate.a = 0.4
	if b["kind"] == "watchtower":
		var pad := Art.sprite("helipad")
		pad.scale = Vector2.ONE * CELL / 192.0
		node.add_child(pad)
		node.add_child(Art.sprite("turret"))
	else:
		var s := Art.sprite("hangar")
		s.scale = Vector2.ONE * n * CELL / 128.0
		s.modulate = TINTS[b["kind"]]
		node.add_child(s)
	if b["kind"] == "clinic":
		for r in [Rect2(-6, -2, 12, 4), Rect2(-2, -6, 4, 12)]:
			var c := ColorRect.new()
			c.position = r.position
			c.size = r.size
			c.color = Color(0.85, 0.1, 0.1)
			node.add_child(c)
	sites.add_child(node)
	site_nodes[b["cell"]] = node


func next_site(kind := "") -> Dictionary:
	for b in Game.buildings:
		if not b["built"] and (kind == "" or b["kind"] == kind):
			return b
	return {}


func _finish_site(b: Dictionary) -> void:
	b["built"] = true
	Game.world.nav_dirty()
	if b["kind"] == "perimeter":
		Game.base_radius += Game.PERIMETER_STEP
		_fence()
	else:
		site_nodes[b["cell"]].modulate.a = 1.0
	Game.radio("Base: %s finished." % Game.BUILDINGS[b["kind"]][0])
	if ui:
		ui.refresh()


## Fence posts every 32 px on the perimeter; the light covers it plus 80 px.
func _fence() -> void:
	for c in fence.get_children():
		c.free()
	var n := int(TAU * Game.base_radius / 32.0)
	for i in n:
		var a := i * TAU / n
		var p := Art.sprite("fence")
		p.position = Vector2(Game.base_radius, 0).rotated(a)
		p.rotation = a + PI / 2
		fence.add_child(p)
	light.texture_scale = (Game.base_radius + 80.0) / 128.0


## FIELD tiles inside the perimeter (each feeds 0.5 a day).
func field_tiles() -> int:
	return _scan_fields().size()


## Cached field tile centres for the farm pawns.
func field_cells() -> Array:
	if fields_r != Game.base_radius:
		fields_r = Game.base_radius
		fields = _scan_fields()
	return fields


func _scan_fields() -> Array:
	var out := []
	var r := int(Game.base_radius / CELL)
	var c := Vector2i((global_position / CELL).floor())
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			var pos := cell_pos(c + Vector2i(x, y))
			if pos.distance_to(global_position) <= Game.base_radius and Game.world.chunks.tile_at(pos) == Chunks.T.FIELD:
				out.append(pos)
	return out


## River or lake within WATER_REACH: the water job works.
func water_near() -> bool:
	return water_point() != null


## Centre of the nearest water cell within WATER_REACH, null if none (cached once found).
func water_point() -> Variant:
	if water_spot != null:
		return water_spot
	var r := int(WATER_REACH / CELL)
	var c := Vector2i((global_position / CELL).floor())
	var best_d := INF
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			var d := Vector2(x, y).length()
			if d <= r and d < best_d and Game.world.chunks.tile_at(cell_pos(c + Vector2i(x, y))) == Chunks.T.WATER:
				best_d = d
				water_spot = cell_pos(c + Vector2i(x, y))
	return water_spot


## Door of the first built `kind` ("barracks", "clinic"), else of the hangar: where pawns go in and out.
func door(kind: String) -> Vector2:
	for b in Game.buildings:
		if b["kind"] == kind and b["built"]:
			var n: int = Game.BUILDINGS[kind][3]
			return cell_pos(b["cell"]) + Vector2(n - 1, n - 1) * CELL / 2 + Vector2(0, n * CELL / 2 + 4)
	return global_position + HANGAR.get_center() + Vector2(0, HANGAR.size.y / 2 + 4)


## Pawns follow the population: as many as rescued (up to PAWN_MAX), the injured first, then Game.workers, the rest idle.
## A pawn keeps its job while that job still wants people; freed pawns take the first open job.
func sync_pawns() -> void:
	var list := pawns.get_children().filter(func(p): return not p.is_queued_for_deletion())
	var n := mini(Game.rescued, PAWN_MAX)
	while list.size() > n:
		list.pop_back().queue_free()
	while list.size() < n:
		list.append(add_pawn(door("barracks"), false))
	var want := {"injured": Game.injured}
	want.merge(Game.workers)
	for p in list:
		if want.get(p.job, 0) > 0:
			want[p.job] -= 1
		else:
			p.job = ""
	var slots := {}
	for i in list.size():
		var p: Node2D = list[i]
		if p.job == "":
			p.job = "idle"
			for k in want:
				if want[k] > 0:
					p.job = k
					want[k] -= 1
					break
		p.slot = slots.get(p.job, 0)
		slots[p.job] = p.slot + 1
		p.camper = i >= Game.housing()


## New pawn at `pos`; `arriving` ones walk into the barracks to change first.
func add_pawn(pos: Vector2, arriving: bool) -> Node2D:
	var p := Pawn.new()
	p.base = self
	p.state = "arrive" if arriving else "live"
	pawns.add_child(p)
	p.global_position = pos
	return p


## Militia take up rifles on watchtowers first (+50 % reach), then the outermost built sandbags
## (a 60 px ring without any). Only as many fire as there are rifles.
func _on_attack(_day: int) -> void:
	var towers: Array = Game.buildings.filter(func(b): return b["kind"] == "watchtower" and b["built"]).map(func(b): return cell_pos(b["cell"]))
	var posts: Array = Game.sandbags.keys().filter(func(c): return Game.sandbags[c]["built"]).map(cell_pos)
	posts.sort_custom(func(a, b): return a.distance_squared_to(global_position) > b.distance_squared_to(global_position))
	posts = towers + posts
	var n: int = Game.workers["militia"]
	for i in n:
		var t := preload("res://scripts/turret.gd").new()
		t.rifle = true
		t.tower = i < towers.size()
		t.armed = i < int(Game.base_rifles)
		t.position = posts[i] - global_position if i < posts.size() else Vector2(RADIUS, 0).rotated(i * TAU / n)
		t.visible = i >= PAWN_MAX # the militia pawn walks to this post (base_pawn.gd)
		defenders.add_child(t)


func take_damage(amount: float) -> void:
	if not Game.running:
		return
	Game.base_hp -= amount * (1.0 - 0.12 * mini(3, Game.built("barracks"))) * (1.0 - minf(0.3, 0.03 * Game.workers["militia"]))
	Sfx.play("base_hit", global_position, -6.0)
	modulate = Color(1, 0.5, 0.5)
	get_tree().create_timer(0.1).timeout.connect(func(): modulate = Color.WHITE)
	if Game.base_hp <= 0.0:
		Game.base_hp = 0.0
		Game.end_run("The base has fallen.")


## Top the heli up from base stock. Also runs after every purchase or loadout change while parked,
## so a bigger tank or ammo feed fills right away instead of showing 100/125 until the next landing.
func resupply() -> void:
	var f: float = minf(Game.max_fuel - Game.fuel, Game.base_fuel)
	Game.fuel += f
	Game.base_fuel -= f
	var a: int = mini(Game.max_ammo - Game.ammo, int(Game.base_ammo))
	Game.ammo += a
	Game.base_ammo -= a


func _on_landed(landed: bool) -> void:
	if not landed:
		ui.close()
		return
	if Game.heli.position.distance_to(position) > PAD_REACH:
		return
	resupply()
	var free_hp: float = Game.MEDIC_REPAIR * Game.workers["medic"] * Game.work_eff() # medics patch for free, the rest is 1 scrap per 5 hull
	var repair := int(ceil(maxf(0.0, Game.max_hp - Game.hp - free_hp) / 5.0))
	if Game.scrap >= repair:
		Game.scrap -= repair
		Game.hp = Game.max_hp
		if repair > 0:
			Game.radio("Base: hull patched for %d scrap." % repair)
	else:
		Game.hp = minf(Game.max_hp, Game.hp + free_hp)
		Game.radio("Base: not enough scrap for hull repairs, %d needed." % repair)
	if Game.fuel < Game.max_fuel or Game.ammo < Game.max_ammo:
		Game.radio("Base: stock is short, partial top-up only. Put people on fuel and ammo duty.")
	Sfx.play("pickup")
	var n: int = Game.passengers
	if n > 0:
		Game.passengers = 0
		Game.rescued += n
		Game.injured += Game.passengers_injured
		Game.passengers_injured = 0
		Game.scrap += 3 * n
		Game.radio("%d survivors delivered. Total: %d" % [n, Game.rescued])
		for i in mini(n, PAWN_MAX - pawns.get_child_count()):
			add_pawn(Game.heli.global_position + Vector2(randf_range(-12, 12), randf_range(8, 16)), true)
		if Game.campers() > 0:
			Game.radio("Base: no beds left, %d camping outside. Build barracks." % Game.campers())
		Game.add_xp(6 * n)
		Progression.on_delivery()
	ui.open()
