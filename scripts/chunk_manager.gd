extends TileMapLayer
## Endless procedural terrain in 32x32-tile chunks. Towns and POIs are seeded per chunk.
## Terrain is a pure function of Game.seed (height, moisture and river noise); towns, farmland and roads are
## painted on top. Paint that lands in a chunk not loaded yet waits in `_pending` until that chunk loads.

const CHUNK := 32
const TILE := 16
const LOAD_RADIUS := 2
const ROAD_REACH := 3000.0 # world px; towns link to known towns / the base within this distance
enum T { GRASS, FOREST, WATER, SAND, ROAD, BUILDING, RUIN, BASE_FLOOR, GRASS2, GRASS3, FIELD, DIRT_ROAD, ROCK, TREE_EDGE, HOUSE_YARD, ASPHALT }
const GRASSY := [T.GRASS, T.GRASS2, T.GRASS3, T.TREE_EDGE]
const TOWNISH := [T.ROAD, T.BUILDING, T.RUIN, T.BASE_FLOOR, T.HOUSE_YARD, T.ASPHALT]
const ACROSS := 1 # alternative tile id: transposed (road dashes, wheel tracks, crop rows, yard path run the other way)
const RIPE := 2 # extra FIELD alternatives (+ACROSS): golden crop

var noise := FastNoiseLite.new() # height
var moisture := FastNoiseLite.new()
var river := FastNoiseLite.new()
var loaded := {}
var town_centers := [] # world positions, used by the spawner
var _pending := {} # chunk -> {cell: Vector2i(tile, alt)}
var _ports := [] # [Vector2i end_a, Vector2i end_b] per town plus the base: where roads attach


func _ready() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(64, 64) # 4x art; the layer scale below keeps cells TILE world px apart
	var src := TileSetAtlasSource.new()
	src.texture = Art.tex("tiles")
	src.texture_region_size = Vector2i(64, 64)
	ts.add_source(src, 0)
	for i in T.size():
		src.create_tile(Vector2i(i, 0))
		src.create_alternative_tile(Vector2i(i, 0), ACROSS)
		src.get_tile_data(Vector2i(i, 0), ACROSS).transpose = true
	for alt in [RIPE, RIPE + ACROSS]:
		src.create_alternative_tile(Vector2i(T.FIELD, 0), alt)
		src.get_tile_data(Vector2i(T.FIELD, 0), alt).transpose = alt == RIPE + ACROSS
		src.get_tile_data(Vector2i(T.FIELD, 0), alt).modulate = Color(1.18, 1.06, 0.78)
	tile_set = ts
	scale = Vector2(Art.SCALE, Art.SCALE)
	noise.seed = Game.seed
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	moisture.seed = Game.seed + 1
	moisture.frequency = 0.02
	moisture.fractal_octaves = 2
	river.seed = Game.seed + 2
	river.frequency = 0.004
	river.fractal_octaves = 2


func _process(_delta: float) -> void:
	if Game.heli == null:
		return
	var c := Vector2i((Game.heli.position / (CHUNK * TILE)).floor())
	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			_ensure(c + Vector2i(dx, dy))


func tile_at(world_pos: Vector2) -> int:
	var cell := Vector2i((world_pos / TILE).floor())
	var atlas := get_cell_atlas_coords(cell)
	return atlas.x if atlas.x >= 0 else T.GRASS


func is_landable(world_pos: Vector2) -> bool:
	var t := tile_at(world_pos)
	return t != T.WATER and t != T.FOREST and t != T.BUILDING and t != T.ROCK


func _ensure(c: Vector2i) -> void:
	if loaded.has(c):
		return
	loaded[c] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed, c.x, c.y])
	var origin := c * CHUNK
	# terrain with a one-cell margin, so forest borders can see their neighbours in other chunks
	var n := CHUNK + 2
	var grid := PackedByteArray()
	grid.resize(n * n)
	for y in n:
		for x in n:
			grid[y * n + x] = _terrain(origin + Vector2i(x - 1, y - 1))
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var t := grid[y * n + x]
			if t == T.FOREST and (grid[y * n + x - 1] != T.FOREST or grid[y * n + x + 1] != T.FOREST \
					or grid[(y - 1) * n + x] != T.FOREST or grid[(y + 1) * n + x] != T.FOREST):
				t = T.TREE_EDGE
			set_cell(origin + Vector2i(x - 1, y - 1), 0, Vector2i(t, 0))
	var pend: Dictionary = _pending.get(c, {})
	for cell in pend:
		set_cell(cell, 0, Vector2i(pend[cell].x, 0), pend[cell].y)
	_pending.erase(c)
	if c == Vector2i.ZERO:
		_paint_base(origin)
		return
	var dist := Vector2(c).length()
	if rng.randf() < 0.4:
		_paint_town(origin, rng, dist)
	else:
		_place_wild_poi(origin, rng, dist)


func _terrain(cell: Vector2i) -> int:
	var h := noise.get_noise_2d(cell.x, cell.y)
	if h < -0.38:
		return T.WATER
	if h < -0.32:
		return T.SAND
	var r := absf(river.get_noise_2d(cell.x, cell.y))
	if r < 0.016:
		return T.WATER
	if r < 0.028:
		return T.ROCK if h > 0.25 else T.SAND
	if h > 0.46:
		return T.ROCK
	var m := moisture.get_noise_2d(cell.x, cell.y) + h * 0.5
	if m > 0.2:
		return T.FOREST
	# grass variants follow moisture in clumps, dithered at their borders by a cell hash
	var k := m + float(hash(cell) % 1000) * 0.0003
	if k > 0.12:
		return T.GRASS2
	if k < -0.2:
		return T.GRASS3
	return T.GRASS


## Current tile of any cell: loaded, waiting in _pending, or the bare terrain it will get.
func _tile(cell: Vector2i) -> int:
	var c := Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
	if loaded.has(c):
		return get_cell_atlas_coords(cell).x
	if _pending.has(c) and _pending[c].has(cell):
		return _pending[c][cell].x
	return _terrain(cell)


func _put(cell: Vector2i, t: int, alt := 0) -> void:
	var c := Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
	if loaded.has(c):
		set_cell(cell, 0, Vector2i(t, 0), alt)
	else:
		if not _pending.has(c):
			_pending[c] = {}
		_pending[c][cell] = Vector2i(t, alt)


func _paint_base(origin: Vector2i) -> void:
	var center := origin + Vector2i(CHUNK / 2, CHUNK / 2)
	for x in range(-10, 11):
		for y in range(-10, 11):
			var cell := center + Vector2i(x, y)
			if abs(x) <= 6 and abs(y) <= 6:
				set_cell(cell, 0, Vector2i(T.BASE_FLOOR, 0))
			elif not get_cell_atlas_coords(cell).x in [T.GRASS, T.GRASS2, T.GRASS3]:
				set_cell(cell, 0, Vector2i(T.GRASS, 0))
	_ports.append([center + Vector2i(7, 0), center + Vector2i(0, 7)])


## Town on a main street (axis u) with side streets every 8 cells, house rows in yards either side,
## a car park by the centre and a ring of fields. Cells are addressed as (u, v) and mapped by `_uv`.
func _paint_town(origin: Vector2i, rng: RandomNumberGenerator, dist: float) -> void:
	var size := rng.randi_range(3, 6)
	var center := origin + Vector2i(rng.randi_range(8, CHUNK - 8), rng.randi_range(8, CHUNK - 8))
	for _i in 4: # prefer dry ground for the centre
		if not _tile(center) in [T.WATER, T.SAND]:
			break
		center = origin + Vector2i(rng.randi_range(8, CHUNK - 8), rng.randi_range(8, CHUNK - 8))
	var ruin_chance := clampf(dist * 0.12, 0.1, 0.8)
	var along := rng.randf() < 0.5 # main street runs along x
	var L := size + 3 # half length of the built-up area
	var W := 3 if size < 5 else 7 # half width: one house row each side, or two with a back street
	var street_alt := 0 if not along else ACROSS
	var cross_alt := ACROSS if not along else 0
	var park_side := 1 if rng.randf() < 0.5 else -1
	# farmland first, so the town core paints over any overlap: rectangles around the town, rows turned per field
	for i in rng.randi_range(7, 11):
		var w := rng.randi_range(4, 8)
		var h := rng.randi_range(3, 6)
		var gap := rng.randi_range(2, 6)
		var ru := rng.randi_range(-L - 6, L + 6)
		var rv := rng.randi_range(-W - 6, W + 6)
		match rng.randi() % 4: # push the field off one side of the town
			0: ru = -L - gap - w
			1: ru = L + gap
			2: rv = -W - gap - h
			3: rv = W + gap
		var at := _uv(center, along, ru, rv)
		if not along:
			var tmp := w
			w = h
			h = tmp
		var rows := (ACROSS if rng.randf() < 0.5 else 0) + (RIPE if rng.randf() < 0.4 else 0)
		var open := []
		for x in w:
			for y in h:
				if _tile(at + Vector2i(x, y)) in GRASSY:
					open.append(at + Vector2i(x, y))
		if open.size() >= w * h * 0.8: # whole rectangles only, no field scraps between rivers and woods
			for cell in open:
				_put(cell, T.FIELD, rows)
	var lots := {} # house-row cells (u, v) that get a house
	for u in range(-L, L + 1):
		for v in [-6, -2, 2, 6]:
			if rng.randf() < 0.7:
				lots[Vector2i(u, v)] = true
	for u in range(-L - 2, L + 3):
		for v in range(-W, W + 1):
			var cell := _uv(center, along, u, v)
			var side := absi(v)
			var cross_street := posmod(u, 8) == 4 and absi(u) <= L
			var t := -1
			var alt := 0
			if v == 0 or (side == 4 and absi(u) <= L):
				t = T.ASPHALT if cross_street else T.ROAD
				alt = street_alt
			elif absi(u) > L:
				continue
			elif cross_street:
				t = T.ROAD
				alt = cross_alt
			elif absi(u) <= 2 and side <= 2 and signi(v) == park_side:
				t = T.ASPHALT # car park by the centre
			elif lots.has(Vector2i(u, v)) or (absi(u) <= 2 and side == 3 and signi(v) == park_side):
				t = T.RUIN if rng.randf() < ruin_chance else T.BUILDING
			elif (side == 1 or side == 5) and lots.has(Vector2i(u, v + signi(v))):
				t = T.HOUSE_YARD # front yard, its path leads from the street to the door
				alt = cross_alt
			else:
				t = T.GRASS2 # gardens and empty lots
			if t == T.ROAD or _tile(cell) != T.WATER: # streets bridge water, houses do not
				_put(cell, t, alt)
	var ends := [_uv(center, along, -L - 2, 0), _uv(center, along, L + 2, 0)]
	_link(ends, along, rng)
	_ports.append(ends)
	var world_center := Vector2(center) * TILE + Vector2(8, 8)
	town_centers.append(world_center)
	Game.world.spawn_poi("survivors", world_center, rng)
	if rng.randf() < 0.5:
		var off := Vector2(rng.randf_range(-size, size), rng.randf_range(-size, size)) * TILE * 2
		Game.world.spawn_poi("crate", world_center + off, rng)
	if rng.randf() < 0.3 and world_center.distance_to(Game.world.BASE_POS) > 1100.0:
		Game.world.spawn_poi("nest", world_center + Vector2((size + 4) * TILE, 0).rotated(rng.randf() * TAU), rng)


func _uv(center: Vector2i, along: bool, u: int, v: int) -> Vector2i:
	return center + (Vector2i(u, v) if along else Vector2i(v, u))


## Dirt roads from a new town to its nearest one or two known towns / the base, as Z-shaped lanes.
func _link(ends: Array, along: bool, rng: RandomNumberGenerator) -> void:
	var near := []
	for p in _ports:
		var best := [INF, Vector2i.ZERO, Vector2i.ZERO]
		for a: Vector2i in ends:
			for b: Vector2i in p:
				var d := Vector2(a - b).length()
				if d < best[0]:
					best = [d, a, b]
		if best[0] * TILE < ROAD_REACH:
			near.append(best)
	near.sort_custom(func(x, y): return x[0] < y[0])
	for i in mini(near.size(), 2 if rng.randf() < 0.3 else 1):
		_lane(near[i][1], near[i][2], along, rng)


func _lane(a: Vector2i, b: Vector2i, along: bool, rng: RandomNumberGenerator) -> void:
	# legs: along the town's axis to a bend, across, then on to the other end
	var axis := 0 if along else 1
	var bend := a[axis] + roundi((b[axis] - a[axis]) * rng.randf_range(0.3, 0.7))
	var p := a
	var corners := [Vector2i(bend, a.y) if along else Vector2i(a.x, bend), Vector2i(bend, b.y) if along else Vector2i(b.x, bend), b]
	var path := []
	var wet := 0
	for target: Vector2i in corners:
		while p != target:
			var step := (target - p).sign()
			p += step
			var t := _tile(p)
			if t == T.DIRT_ROAD and path.size() > 3:
				break # joined an existing road
			wet += int(t == T.WATER)
			if not t in TOWNISH and t != T.DIRT_ROAD:
				path.append([p, ACROSS if step.x != 0 else 0])
		if p != target:
			break
	if wet > 5:
		return # no long causeways across lakes
	for c in path:
		_put(c[0], T.DIRT_ROAD, c[1])


func _place_wild_poi(origin: Vector2i, rng: RandomNumberGenerator, dist: float) -> void:
	var r := rng.randf()
	var kind := ""
	if r < 0.18:
		kind = "crate"
	elif r < 0.30:
		kind = "radio_tower"
	elif r < 0.42:
		kind = "wreck"
	elif r < 0.55:
		kind = "upgrade"
	elif r < 0.55 + clampf(dist * 0.06, 0.05, 0.3):
		kind = "nest"
	if kind == "":
		return
	if kind == "nest" and Vector2(origin * TILE).distance_to(Game.world.BASE_POS) < 1100.0:
		kind = "crate" # no hive queen next door on day 1
	for _i in 10:
		var cell := origin + Vector2i(rng.randi_range(4, CHUNK - 4), rng.randi_range(4, CHUNK - 4))
		var t := get_cell_atlas_coords(cell).x
		if t in GRASSY or t == T.SAND or t == T.FIELD:
			Game.world.spawn_poi(kind, Vector2(cell) * TILE + Vector2(8, 8), rng)
			return
