extends TileMapLayer
## Endless procedural terrain in 32x32-tile chunks. Every layer is a pure function of Game.seed and the cell, so a chunk
## comes out the same whatever order chunks load in (tests/world_test.gd):
## 1. _terrain(): a large cellular region noise picks one of seven regions, each bending the height, moisture and river
##    layers its own way, with patches inside (clearings, forest ponds, orchards, burned ground, copses).
## 2. Sites: a macro grid of MACRO x MACRO chunks holds one jittered site per macro cell (site()): a town (one of seven
##    templates per region, rarely a city), a landmark (gas station, airfield, prison...) or nothing. A site is laid out
##    once into its own buffer (_layout) that sees bare terrain only and stays inside its macro cell.
## 3. Roads: each site links to its two nearest neighbours (_knn) by a coarse A* over terrain and the two site layouts
##    (_edge): dirt lanes, paved between cities, fords over brooks and bridges over rivers.
## 4. Lone houses and wild POIs per chunk (_lone), on top of 1-3 and clipped to their chunk.
## A chunk composes these layers (_final), turns road cells into bends and junctions from their neighbours (_bend) and
## spawns the props and POIs that fall inside it. Runtime changes go through edit() and are saved.

const CHUNK := 32
const TILE := 16
const LOAD_RADIUS := 2
const MACRO := 5 # chunks per macro cell side: one site each, ~2560 px apart
const MACRO_CELLS := MACRO * CHUNK
const SITE_JITTER := 24 # cells a site centre may sit off the middle of its macro cell
const SETTLE := 12 # and then off that for drier ground
const SITE_REACH := 52 # cells: the farthest a site paints from its centre (jitter + reach stay inside the macro cell)
const START := Vector2i(16, 16) # the start site (centre of chunk (0,0)), kept clear of all paint
const START_TOWN := Vector2i(40, 50) # the start macro's town sits this many cells (x and y) south-east of START
const ROAD_NODE := 4 # cells per coarse A* node
const ROAD_MARGIN := 6 # nodes of slack around an edge's A* box
const ROAD_GROW := SITE_REACH + (ROAD_MARGIN + 1) * ROAD_NODE # cells: how far an edge's path may stray from its sites' box
const FORD := 2 # water runs up to this long are forded, longer ones bridged
const FRAME_BUDGET_MS := 4.0 # loading and prefetching beyond the 3x3 chunks under the heli
const BIOME_FREQ := 0.001 # region size (1.5x the old regions: a run's fuel range still crosses several)
const PATCH_FREQ := 0.014 # patches inside regions, ~70 cells apart
const PATCH_R := 0.26 # patch radius as a share of their spacing
enum T { GRASS, FOREST, WATER, SAND, ROAD, BUILDING, RUIN, BASE_FLOOR, GRASS2, GRASS3, FIELD, DIRT_ROAD, ROCK, TREE_EDGE,
	HOUSE_YARD, ASPHALT, HEDGE, MARSH, WAREHOUSE, ASH, CRATER, PARKING, PLAZA, PAD, ROAD_BEND, DIRT_BEND, DIRT_X, BRIDGE }
enum R { FARM, FOREST, LAKE, SUBURB, WASTE, HIGHLAND, RIVER }
const REGIONS := ["farm", "forest", "lake", "suburb", "waste", "highland", "river"]
const SITE_ODDS := [[0.6, 0.3], [0.35, 0.5], [0.5, 0.35], [0.7, 0.25], [0.4, 0.45], [0.3, 0.55], [0.55, 0.35]] # town, landmark share
const TOWN_KINDS := [["village", "village", "farm", "farm", "hamlet"], ["hamlet", "hamlet", "hamlet", "village"],
	["fishing", "fishing", "village"], ["suburb", "suburb", "industrial"], ["ruined"], ["hamlet", "hamlet", "village"],
	["fishing", "village", "farm", "hamlet"]]
const TOWN_SIZE := {"village": Vector2i(3, 7), "hamlet": Vector2i(3, 6), "fishing": Vector2i(3, 6), "farm": Vector2i(4, 8),
	"suburb": Vector2i(8, 14), "industrial": Vector2i(5, 10), "ruined": Vector2i(3, 10), "city": Vector2i(4, 5)} # city: blocks a side
const CITY_CHANCE := [0.08, 0.0, 0.0, 0.3, 0.0, 0.0, 0.05] # share of a region's towns that are cities instead
const LANDMARKS := { # weight per region (farm, forest, lake, suburb, waste, highland, river)
	"gas_station": [3, 1, 2, 3, 2, 1, 2], "checkpoint": [2, 1, 1, 2, 3, 2, 2], "campground": [0, 3, 3, 0, 0, 2, 2],
	"quarry": [1, 1, 0, 0, 1, 4, 0], "airfield": [3, 0, 1, 2, 2, 0, 2], "radio_mast": [2, 2, 1, 1, 2, 3, 1],
	"dam": [0, 0, 2, 0, 0, 2, 4], "airliner": [1, 1, 1, 1, 2, 1, 1], "prison": [1, 0, 0, 2, 2, 1, 1],
	"motel": [2, 0, 1, 3, 1, 0, 1], "lumber_camp": [0, 4, 1, 0, 0, 3, 1], "church_ruin": [2, 1, 1, 1, 3, 1, 1],
	"highway": [2, 1, 1, 3, 2, 0, 2]}
const PATCHES := [["orchard", "burned", "copse"], ["clearing", "pond", "clearing", "burned"], ["copse", "meadow"],
	["copse"], ["meadow", "pond"], ["clearing", "pond", "scree"], ["copse", "meadow", "pond"]] # by region, half the patches stay plain
const LONE_CHANCE := [0.5, 0.3, 0.4, 0.6, 0.35, 0.25, 0.4] # a lone house in a wild chunk, by region
const BLOCK := 11 # city street pitch: 10 cells of lots between streets
# region terrain: water below WATER_H (a shore band above it), forest above FOREST_M moisture, rock above ROCK_H
const WATER_H := [-0.42, -0.4, -0.16, -0.42, -0.4, -0.55, -0.45]
const FOREST_M := [0.36, -0.36, 0.12, 0.42, 0.22, -0.12, 0.3]
const ROCK_H := [0.55, 0.38, 0.46, 0.6, 0.46, 0.3, 0.7]
const RIVER_W := [0.016, 0.016, 0.016, 0.016, 0.016, 0.012, 0.05] # river half width in river-noise units
const BANK := [T.SAND, T.SAND, T.MARSH, T.SAND, T.ASH, T.ROCK, T.MARSH]
const GRASSY := [T.GRASS, T.GRASS2, T.GRASS3, T.TREE_EDGE]
const OPEN := [T.GRASS, T.GRASS2, T.GRASS3, T.TREE_EDGE, T.SAND, T.ASH, T.MARSH, T.FIELD] # where wild POIs may sit
const BUILDABLE := [T.GRASS, T.GRASS2, T.GRASS3, T.TREE_EDGE, T.SAND, T.ASH, T.MARSH, T.FIELD, T.HEDGE, T.FOREST, T.CRATER]
const TOWNISH := [T.ROAD, T.BUILDING, T.RUIN, T.BASE_FLOOR, T.HOUSE_YARD, T.ASPHALT, T.WAREHOUSE, T.PARKING, T.PLAZA, T.PAD, T.ROAD_BEND, T.BRIDGE]
const BLOCKED := [T.WATER, T.FOREST, T.BUILDING, T.ROCK, T.WAREHOUSE, T.HEDGE, T.PAD] # not landable
const ROADS := [T.ROAD, T.DIRT_ROAD, T.ASPHALT, T.ROAD_BEND, T.DIRT_BEND, T.DIRT_X, T.BRIDGE]
const LINES := [T.ROAD, T.DIRT_ROAD, T.ROAD_BEND, T.DIRT_BEND, T.DIRT_X, T.BRIDGE] # roads that lead somewhere (not asphalt lots)
const SAME := {T.ROAD_BEND: T.ROAD, T.DIRT_BEND: T.DIRT_ROAD, T.DIRT_X: T.DIRT_ROAD} # tile_at reports bends as plain road
const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT] # neighbour mask bits 1, 2, 4, 8
const WALLED := [T.BUILDING, T.RUIN, T.BASE_FLOOR, T.HOUSE_YARD, T.WAREHOUSE, T.PAD] # roads keep out (houses, gardens)
const BUILT := [T.BUILDING, T.RUIN, T.WAREHOUSE, T.PAD, T.PARKING, T.PLAZA, T.HOUSE_YARD, T.BASE_FLOOR]
const HARD := [T.BUILDING, T.RUIN, T.WAREHOUSE, T.PAD, T.PARKING, T.PLAZA, T.BASE_FLOOR, T.ROAD, T.DIRT_ROAD, T.ASPHALT,
	T.ROAD_BEND, T.DIRT_BEND, T.DIRT_X, T.BRIDGE] # site paint a passing road does not cover
const ACROSS := 1 # alternative tile id: transposed (road dashes, wheel tracks, crop rows, yard path, hedge run the other way)
const RIPE := 2 # extra FIELD alternatives (+ACROSS): golden crop
const FLIP := 2 # extra PARKING alternatives (+ACROSS): bays open the other way
const ROOF_ALT := 2 # BUILDING alternatives ROOF_ALT + i are tinted with ROOFS[i]
const BEND_W := 2 # bend alternatives (+ BEND_N): the art turns south-east, flip_h turns it west, flip_v north
const BEND_N := 4
const ROOFS := [Color(1, 1, 1), Color(1.0, 0.62, 0.5), Color(0.74, 0.8, 0.96), Color(0.94, 0.8, 0.6), Color(0.62, 0.62, 0.66), Color(0.82, 0.92, 0.74)]
const CARS := [Color(1, 0.42, 0.36), Color(0.5, 0.62, 1), Color(1, 1, 1), Color(0.38, 0.38, 0.4), Color(0.92, 0.86, 0.5)]
const TENTS := [Color(1, 0.55, 0.3), Color(0.45, 0.75, 0.5), Color(0.5, 0.65, 1), Color(1, 0.9, 0.45)]
const OLIVE := Color(0.55, 0.62, 0.42)
const BURNT := Color(0.32, 0.28, 0.26)
const PROP_TREE := 1 # terrain scatter props, packed into _terrain()'s result above bit 16
const PROP_DEAD := 2
const NONE := Vector2i(-99999, -99999)
const NO := Vector2i(-1, 0) # no paint in a layer
enum M { GEN, SITE, EDGE, LONE } # what _painted sees: loaded tiles or all layers / a site buffer / bare terrain / a lone buffer

var noise := FastNoiseLite.new() # height
var moisture := FastNoiseLite.new()
var river := FastNoiseLite.new()
var biome := FastNoiseLite.new() # regions
var patch_d := FastNoiseLite.new() # distance to the nearest patch centre
var patch_v := FastNoiseLite.new() # a value per patch
var loaded := {}
var town_centers := [] # world positions, used by the spawner
var _pending := {} # chunk -> {cell: Vector2i(tile, alt)}: edits to chunks not loaded yet
var _sites := {} # macro cell -> site() dictionary
var _near := {} # macro cell -> its two nearest site neighbours (macro cells)
var _layouts := {} # macro cell -> _layout() result
var _edges := {} # Vector4i(macro a, macro b) -> true once its road is in _road
var _cand := {} # chunk -> edges whose road may cross it
var _roads_ok := {} # chunk -> true once every road that may cross it is in _road
var _road := {} # cell -> Vector2i(tile, alt) of all roads computed so far
var _lones := {} # chunk -> _lone() result
var _mode := M.GEN
var _buf := {} # cell -> Vector2i(tile, alt) of the layout being built
var _out := {} # the layout being built
var _taken := {} # cells under trees and other props in the layout being built, so houses keep off them
var _clip := Rect2i() # lone layouts paint only inside their chunk
# save (scripts/save.gd): the world is replayed from Game.seed and this log instead of being stored
var events := [] # in order: ["chunk", cx, cy] per _ensure, ["found", cell] when the base was founded (BASE_POS moved)
var edits := {} # cell -> Vector2i(tile, alt) changed at runtime (edit), applied after the replay
var cuts := [] # positions of generator props removed at runtime (cut_prop)
var _gen := NONE # chunk being generated: its POIs get uid "cx,cy#n"
var _gen_n := 0
var _dyn_n := 0 # POIs from outside the generator get "dyn#n"
var _last := NONE # the heli's chunk last frame
var _shot_at := OS.get_environment("SHOT_AT") # dev hook for screenshots, see _shot_jump


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
	for alt in [FLIP, FLIP + ACROSS]:
		src.create_alternative_tile(Vector2i(T.PARKING, 0), alt)
		src.get_tile_data(Vector2i(T.PARKING, 0), alt).transpose = alt == FLIP + ACROSS
		src.get_tile_data(Vector2i(T.PARKING, 0), alt).flip_v = alt == FLIP
		src.get_tile_data(Vector2i(T.PARKING, 0), alt).flip_h = alt == FLIP + ACROSS
	for t in [T.ROAD_BEND, T.DIRT_BEND]:
		for alt in [BEND_W, BEND_N, BEND_W + BEND_N]:
			src.create_alternative_tile(Vector2i(t, 0), alt)
			src.get_tile_data(Vector2i(t, 0), alt).flip_h = alt & BEND_W != 0
			src.get_tile_data(Vector2i(t, 0), alt).flip_v = alt & BEND_N != 0
	for i in ROOFS.size():
		src.create_alternative_tile(Vector2i(T.BUILDING, 0), ROOF_ALT + i)
		src.get_tile_data(Vector2i(T.BUILDING, 0), ROOF_ALT + i).modulate = ROOFS[i]
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
	biome.seed = Game.seed + 3
	biome.noise_type = FastNoiseLite.TYPE_CELLULAR
	biome.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	biome.fractal_type = FastNoiseLite.FRACTAL_NONE
	biome.frequency = BIOME_FREQ
	for p: FastNoiseLite in [patch_d, patch_v]:
		p.seed = Game.seed + 4
		p.noise_type = FastNoiseLite.TYPE_CELLULAR
		p.fractal_type = FastNoiseLite.FRACTAL_NONE
		p.frequency = PATCH_FREQ
		p.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
		p.cellular_jitter = 0.8
	patch_d.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	patch_v.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE


## The 3x3 chunks under the heli load at once (all 5x5 on the first frame or after a jump); the rest of the 5x5 and
## the roads and sites one ring further out load within FRAME_BUDGET_MS per frame, so flying never hitches.
func _process(_delta: float) -> void:
	if Game.heli == null:
		return
	if _shot_at != "":
		_shot_jump()
	var c := Vector2i((Game.heli.position / (CHUNK * TILE)).floor())
	var all := _last == NONE or maxi(absi(c.x - _last.x), absi(c.y - _last.y)) > 1 # first frame or a jump
	_last = c
	var t0 := Time.get_ticks_usec()
	for r in LOAD_RADIUS + 2:
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				if r > 1 and not (all and r <= LOAD_RADIUS) and Time.get_ticks_usec() - t0 > FRAME_BUDGET_MS * 1000.0:
					return
				if r <= LOAD_RADIUS:
					_ensure(c + Vector2i(dx, dy))
				else:
					_prep(c + Vector2i(dx, dy))


func tile_at(world_pos: Vector2) -> int:
	var cell := Vector2i((world_pos / TILE).floor())
	var atlas := get_cell_atlas_coords(cell)
	return SAME.get(atlas.x, atlas.x) if atlas.x >= 0 else T.GRASS


func is_landable(world_pos: Vector2) -> bool:
	return not tile_at(world_pos) in BLOCKED


## Region of a cell. Borders wander with the height noise and are dithered over ~6 cells by a cell hash.
func region(cell: Vector2i) -> int:
	return _region(cell, noise.get_noise_2d(cell.x, cell.y), hash(cell))


func _region(cell: Vector2i, h: float, j: int) -> int:
	var x := cell.x + h * 120.0 + float(j % 7 - 3)
	var y := cell.y - h * 120.0 + float((j >> 3) % 7 - 3)
	var r := mini(int((biome.get_noise_2d(x, y) + 1.0) * 0.5 * R.size()), R.size() - 1)
	if r == R.WASTE and Vector2(x - START.x, y - START.y).length() < 3.5 * CHUNK:
		return R.FARM # the burned lands start a few chunks out
	return r


func _chunk_of(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))


func _macro(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(MACRO_CELLS)), floori(cell.y / float(MACRO_CELLS)))


func _ensure(c: Vector2i) -> void:
	if loaded.has(c):
		return
	events.append(["chunk", c.x, c.y])
	_gen = c
	_gen_n = 0
	_generate(c)
	_gen = NONE


## Composes chunk c: terrain, then the site, road and lone layers, bends, saved edits, then its props and POIs.
func _generate(c: Vector2i) -> void:
	loaded[c] = true
	var origin := c * CHUNK
	var lay := _layout(_macro(origin))
	var lone := _lone(c)
	# terrain with a one-cell margin, so forest borders can see their neighbours in other chunks
	var n := CHUNK + 2
	var grid := PackedInt32Array()
	grid.resize(n * n)
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			grid[y * n + x] = _terrain(origin + Vector2i(x - 1, y - 1))
	for k in range(1, n - 1): # margin cells are only needed next to forest
		for e: Vector4i in [Vector4i(k, 0, k, 1), Vector4i(k, n - 1, k, n - 2), Vector4i(0, k, 1, k), Vector4i(n - 1, k, n - 2, k)]:
			if grid[e.w * n + e.z] == T.FOREST:
				grid[e.y * n + e.x] = _terrain(origin + Vector2i(e.x - 1, e.y - 1))
	var pend: Dictionary = _pending.get(c, {})
	var roads := []
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var i := y * n + x
			var cell := origin + Vector2i(x - 1, y - 1)
			var f := _final(cell)
			if f.x >= 0:
				set_cell(cell, 0, Vector2i(f.x, 0), f.y)
				if f.x in ROADS:
					roads.append(cell)
				continue
			var t := grid[i] & 0xff
			if t == T.FOREST and (grid[i - 1] != T.FOREST or grid[i + 1] != T.FOREST or grid[i - n] != T.FOREST or grid[i + n] != T.FOREST):
				t = T.TREE_EDGE
			set_cell(cell, 0, Vector2i(t, 0), (grid[i] >> 8) & 0xff)
			if t in ROADS:
				roads.append(cell)
			if grid[i] >= 65536 and not pend.has(cell):
				var j := hash(cell)
				var at := Vector2(cell * TILE) + Vector2(5 + j % 7, 5 + (j >> 4) % 7)
				_prop("tree" if grid[i] >> 16 == PROP_TREE else "dead_tree", at, 0.0 if grid[i] >> 16 == PROP_TREE else j % 628 * 0.01)
	for cell: Vector2i in roads:
		var b := _bend(cell)
		if b.x >= 0:
			set_cell(cell, 0, Vector2i(b.x, 0), b.y)
	for cell in pend:
		set_cell(cell, 0, Vector2i(pend[cell].x, 0), pend[cell].y)
	_pending.erase(c)
	if c == Vector2i.ZERO: # the start site: a grass patch under the heli, wide enough to found the base right here
		for x in range(-4, 5):
			for y in range(-4, 5):
				var cell := START + Vector2i(x, y)
				if not get_cell_atlas_coords(cell).x in [T.GRASS, T.GRASS2, T.GRASS3]:
					set_cell(cell, 0, Vector2i(T.GRASS, 0))
	for l: Dictionary in [lay, lone]:
		for p: Array in l.props.get(c, []):
			_prop(p[0], p[1], p[2], p[3])
	town_centers.append_array(lay.towns.get(c, []))
	for l: Dictionary in [lay, lone]:
		for p: Array in l.pois.get(c, []):
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([Game.seed, p[1]])
			Game.world.spawn_poi(p[0], p[1], rng, p[2])


## Tile id, plus alternative << 8 and a scatter prop << 16.
func _terrain(cell: Vector2i) -> int:
	var h := noise.get_noise_2d(cell.x, cell.y)
	var j := hash(cell)
	var reg := _region(cell, h, j)
	if reg == R.HIGHLAND:
		h = h * 1.3 + 0.06 # rugged: rock ridges, few lakes
	var wh: float = WATER_H[reg]
	if h < wh:
		return T.WATER
	if h < wh + (0.09 if reg == R.LAKE else 0.06):
		if reg == R.LAKE: # reed beds at the water's edge, then a sand beach
			return T.MARSH if h < wh + 0.04 + float(j % 10) * 0.003 else T.SAND
		return T.ASH if reg == R.WASTE else T.SAND
	var r := absf(river.get_noise_2d(cell.x, cell.y))
	var rw: float = RIVER_W[reg]
	if r < rw:
		return T.WATER
	if r < rw * 1.75:
		return T.ROCK if h > 0.25 else BANK[reg]
	if reg == R.RIVER and r < rw * 3.4: # flood meadows along the wide river
		return T.MARSH if j % 7 == 0 or r < rw * 2.0 else T.GRASS2 | (PROP_TREE << 16 if j % 41 == 0 else 0)
	if h > ROCK_H[reg]:
		return T.ROCK
	var m := moisture.get_noise_2d(cell.x, cell.y) + h * 0.5
	var lx := posmod(cell.x + 7 * floori(cell.y / 64.0), 53) == 0
	if reg == R.FOREST and (lx or posmod(cell.y, 61) == 0): # logging tracks through the woods
		return T.DIRT_X if lx and posmod(cell.y, 61) == 0 else T.DIRT_ROAD | (ACROSS << 8 if not lx else 0)
	if reg == R.LAKE and m > 0.25: # wet hollows hold more lakes, ringed with reeds
		return T.WATER if m > 0.3 else T.MARSH
	var p := _patch(cell, reg, j)
	if p >= 0:
		return p
	if m > FOREST_M[reg]:
		if reg == R.WASTE: # burned woods
			return T.ASH | (PROP_DEAD << 16 if j % 9 == 0 else 0)
		return T.FOREST
	# grass variants follow moisture in clumps, dithered at their borders by a cell hash
	var k := m + float(j % 1000) * 0.0003
	match reg:
		R.WASTE:
			if j % 71 == 0:
				return T.CRATER
			return T.GRASS3 if m + float(j % 10) * 0.006 > 0.3 else T.ASH | (PROP_DEAD << 16 if j % 53 == 0 else 0)
		R.FARM:
			var f := _parcel(cell, j)
			if f >= 0:
				return f
		R.SUBURB:
			return T.GRASS2 if k > -0.1 else T.GRASS
		R.HIGHLAND:
			return T.GRASS3 if k < 0.05 else T.GRASS | (PROP_TREE << 16 if j % 97 == 0 else 0)
	if k > 0.12:
		return T.GRASS2
	if k < -0.2:
		return T.GRASS3
	return T.GRASS | (PROP_TREE << 16 if j % 211 == 0 and reg != R.SUBURB else 0)


## Round patches that break up a region: every patch centre picks one of the region's PATCHES (or none) by its value.
func _patch(cell: Vector2i, reg: int, j: int) -> int:
	var d := patch_d.get_noise_2d(cell.x, cell.y) + 1.0 # 0 at the centre, in patch spacings
	if d > PATCH_R:
		return -1
	var kinds: Array = PATCHES[reg]
	var i := int((patch_v.get_noise_2d(cell.x, cell.y) + 1.0) * kinds.size())
	if i >= kinds.size():
		return -1
	var e := d + float(j % 9) * 0.006 # ragged rims
	match kinds[i]:
		"clearing":
			return T.GRASS2 | (PROP_TREE << 16 if j % 29 == 0 else 0) if e < PATCH_R * 0.85 else T.TREE_EDGE
		"pond":
			return T.WATER if e < PATCH_R * 0.5 else (T.MARSH if e < PATCH_R * 0.65 else -1)
		"orchard": # fruit trees in rows
			return T.GRASS2 | (PROP_TREE << 16 if posmod(cell.x, 3) == 0 and posmod(cell.y, 3) == 0 else 0)
		"burned":
			return T.CRATER if j % 61 == 0 else T.ASH | (PROP_DEAD << 16 if j % 17 == 0 else 0)
		"copse":
			return T.FOREST if e < PATCH_R * 0.8 else -1
		"meadow":
			return T.GRASS3 | (PROP_TREE << 16 if j % 53 == 0 else 0)
		"scree":
			return T.ROCK if j % 3 != 0 else T.GRASS3
	return -1


## Farmland patchwork: staggered 12x9 parcels of crops or meadow, most of them hedged, with the odd gap.
func _parcel(cell: Vector2i, j: int) -> int:
	var band := floori(cell.y / 9.0)
	var xs := cell.x + posmod(hash(band), 12)
	var ph := hash(Vector2i(floori(xs / 12.0), band))
	var ex := posmod(xs, 12) == 0
	var ey := posmod(cell.y, 9) == 0
	if ex or ey:
		if ph % 4 != 0 and j % 13 != 0:
			return T.HEDGE | (ACROSS << 8 if ey and not ex else 0) | (PROP_TREE << 16 if j % 19 == 0 else 0)
		return -1
	if ph % 10 < 6:
		return T.FIELD | ((ph >> 4) % 4) << 8
	return -1


# ---------------------------------------------------------------- layers

## Tile painted over the bare terrain, or -1. What counts depends on _mode: a layout being built sees its own buffer
## (a lone layout also the roads and sites under it), road routing sees bare terrain, everything else sees loaded
## chunks and, past them, the composed layers.
func _painted(cell: Vector2i) -> int:
	match _mode:
		M.SITE:
			return _buf.get(cell, NO).x
		M.EDGE:
			return -1
		M.LONE:
			return _buf[cell].x if _buf.has(cell) else _under(cell).x
	if loaded.has(_chunk_of(cell)):
		return get_cell_atlas_coords(cell).x
	return _final(cell).x


## Current tile of any cell: painted (see _painted) or the bare terrain.
func _tile(cell: Vector2i) -> int:
	var t := _painted(cell)
	return t if t >= 0 else _terrain(cell) & 0xff


## The composed paint of a cell (before bends), or NO for bare terrain.
func _final(cell: Vector2i) -> Vector2i:
	var l: Dictionary = _lone(_chunk_of(cell)).cells
	return l[cell] if l.has(cell) else _under(cell)


## Roads over site paint, except where the site has houses, lots or streets of its own.
func _under(cell: Vector2i) -> Vector2i:
	_need_roads(_chunk_of(cell))
	var s: Vector2i = _layout(_macro(cell)).cells.get(cell, NO)
	var r: Vector2i = _road.get(cell, NO)
	return r if r.x >= 0 and not s.x in HARD else s


## Starts building a layout in `mode`; returns what _done needs to restore (layouts nest: a lone layout pulls in sites).
func _begin(mode: int) -> Array:
	var saved := [_mode, _buf, _out, _taken, _clip]
	_mode = mode
	_buf = {}
	_taken = {}
	_out = {"cells": _buf, "taken": _taken, "props": {}, "pois": {}, "towns": {}, "ports": [], "city": Rect2i()}
	return saved


func _done(saved: Array) -> Dictionary:
	var out := _out
	_mode = saved[0]
	_buf = saved[1]
	_out = saved[2]
	_taken = saved[3]
	_clip = saved[4]
	return out


## The site of macro cell m: {kind, center, reg, m, uid, town}, kind "" if empty. Pure and cheap: nothing is painted.
func site(m: Vector2i) -> Dictionary:
	if _sites.has(m):
		return _sites[m]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed, m.x, m.y, 7])
	var mid := m * MACRO_CELLS + Vector2i(MACRO_CELLS / 2, MACRO_CELLS / 2)
	var center := mid + Vector2i(rng.randi_range(-SITE_JITTER, SITE_JITTER), rng.randi_range(-SITE_JITTER, SITE_JITTER))
	if m == Vector2i.ZERO: # a town within ~1200 px of the start site
		center = START + Vector2i(rng.randi_range(START_TOWN.x, START_TOWN.y), rng.randi_range(START_TOWN.x, START_TOWN.y))
	var reg := region(center)
	var odds: Array = SITE_ODDS[reg]
	var roll := rng.randf()
	var kind := ""
	if m == Vector2i.ZERO or roll < odds[0]:
		var kinds: Array = TOWN_KINDS[reg]
		kind = kinds[rng.randi() % kinds.size()]
		if m == Vector2i.ZERO and kind == "ruined":
			kind = "village"
		elif maxi(absi(m.x), absi(m.y)) >= 2 and rng.randf() < CITY_CHANCE[reg]:
			kind = "city"
	elif roll < odds[0] + odds[1]:
		var sum := 0.0
		for k: String in LANDMARKS:
			sum += LANDMARKS[k][reg]
		var w := rng.randf() * sum
		for k: String in LANDMARKS:
			w -= LANDMARKS[k][reg]
			if w < 0.0 and kind == "":
				kind = k
	var s := {"kind": kind, "center": center, "reg": reg, "m": m, "uid": "site:%d,%d" % [m.x, m.y], "town": false}
	if kind != "":
		var saved := _begin(M.EDGE) # bare terrain only
		_settle(s, rng)
		_done(saved)
	_sites[m] = s
	return s


## Dry ground for a site's centre (by the water for fishing villages if possible, on a river for a dam); a site with
## none stays empty, the start town takes its spot regardless.
func _settle(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var c0: Vector2i = s.center
	if s.kind == "dam": # across a river or lake neck 3-14 cells wide, else a gas station
		s.kind = "gas_station"
		for i in 60:
			var c := c0 + Vector2i(rng.randi_range(-SITE_JITTER, SITE_JITTER), rng.randi_range(-SITE_JITTER, SITE_JITTER))
			var ax := Vector2i.RIGHT if i % 2 == 0 else Vector2i.DOWN
			if _terrain(c) & 0xff != T.WATER:
				continue
			var a := c
			var b := c
			while _terrain(a - ax) & 0xff == T.WATER and (b - a).length() < 16:
				a -= ax
			while _terrain(b + ax) & 0xff == T.WATER and (b - a).length() < 16:
				b += ax
			if (b - a).length() >= 2 and (b - a).length() <= 13:
				s.kind = "dam"
				s.center = (a + b) / 2
				s.dam = [a, b, ax]
				s.town = false
				return
	var best := [-1, c0]
	for i in 10: # the driest of a few spots (by the water for fishing villages)
		var center := c0 if i == 0 else c0 + Vector2i(rng.randi_range(-SETTLE, SETTLE), rng.randi_range(-SETTLE, SETTLE))
		if _terrain(center) & 0xff in [T.WATER, T.SAND, T.MARSH, T.ROCK] or s.m == Vector2i.ZERO and Vector2(center - START).length() > 72.0:
			continue
		var dry := 0
		for k in 25:
			dry += int(not _terrain(center + Vector2i(k % 5 - 2, k / 5 - 2) * 6) & 0xff in [T.WATER, T.MARSH, T.ROCK])
		if s.kind == "fishing" and _water_dir(center, 9) == Vector2i.ZERO:
			dry -= 10
		if dry > best[0]:
			best = [dry, center]
		if dry == 25:
			break
	if best[0] >= 0 or s.m == Vector2i.ZERO:
		s.center = best[1]
	else:
		s.kind = ""
	s.town = s.kind in TOWN_SIZE


## Sites (towns and landmarks) within `radius` world px of `pos`, nearest first: [{kind, pos, uid}]. For other systems
## (bandit camps at prisons, outposts at gas stations, wrecks at airfields...); generation is not needed for this.
func sites_near(pos: Vector2, radius: float, kind := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m0 := _macro(Vector2i((pos / TILE).floor()))
	var r := ceili(radius / TILE / MACRO_CELLS) + 1
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			var s := site(m0 + Vector2i(x, y))
			var at := _mid(s.center, s.center)
			if s.kind != "" and (kind == "" or s.kind == kind) and at.distance_to(pos) <= radius:
				out.append({"kind": s.kind, "pos": at, "uid": s.uid})
	out.sort_custom(func(a, b): return a.pos.distance_squared_to(pos) < b.pos.distance_squared_to(pos))
	return out


## The two nearest sites among the 8 macro cells around m.
func _knn(m: Vector2i) -> Array:
	if _near.has(m):
		return _near[m]
	var c: Vector2i = site(m).center
	var all := []
	for x in range(-1, 2):
		for y in range(-1, 2):
			var q := m + Vector2i(x, y)
			if q != m and site(q).kind != "":
				all.append([Vector2(site(q).center - c).length(), q])
	all.sort_custom(func(a, b): return a[0] < b[0])
	_near[m] = all.slice(0, 2).map(func(a): return a[1])
	return _near[m]


## Roads (site pairs, Vector4i(a, b) with a < b) whose path may cross chunk c: one end within 2 macro cells of it.
func _edges_near(c: Vector2i) -> Array:
	if _cand.has(c):
		return _cand[c]
	var rect := Rect2i(c * CHUNK - Vector2i(2, 2), Vector2i(CHUNK + 4, CHUNK + 4))
	var m0 := _macro(c * CHUNK)
	var out := []
	for x in range(-2, 3):
		for y in range(-2, 3):
			var p := m0 + Vector2i(x, y)
			if site(p).kind == "":
				continue
			for q: Vector2i in _knn(p):
				var e := Vector4i(p.x, p.y, q.x, q.y) if p < q else Vector4i(q.x, q.y, p.x, p.y)
				var box := Rect2i(site(p).center, Vector2i.ONE).expand(site(q).center).grow(ROAD_GROW)
				if not e in out and box.intersects(rect):
					out.append(e)
	_cand[c] = out
	return out


func _need_roads(c: Vector2i) -> void:
	if _roads_ok.has(c):
		return
	for e: Vector4i in _edges_near(c):
		_edge(e)
	_roads_ok[c] = true


## One piece of the work chunk c will need (a site, a road, its lone layout, which needs the roads around it);
## false once it has it all.
func _prep(c: Vector2i) -> bool:
	if _lones.has(c):
		return false
	for k in 9:
		if _prep_roads(c + Vector2i(k % 3 - 1, k / 3 - 1)):
			return true
	_lone(c)
	return true


func _prep_roads(c: Vector2i) -> bool:
	if _roads_ok.has(c):
		return false
	var m := _macro(c * CHUNK)
	if not _layouts.has(m):
		_layout(m)
		return true
	for e: Vector4i in _edges_near(c):
		for p: Vector2i in [Vector2i(e.x, e.y), Vector2i(e.z, e.w)]:
			if not _layouts.has(p):
				_layout(p)
				return true
		if not _edges.has(e):
			_edge(e)
			return true
	_roads_ok[c] = true
	return false


## The paint of macro cell m's site, built once from bare terrain: {cells, taken, props, pois, towns (per chunk), ports, city}.
func _layout(m: Vector2i) -> Dictionary:
	if _layouts.has(m):
		return _layouts[m]
	var s := site(m)
	var saved := _begin(M.SITE)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed, m.x, m.y, 8])
	if s.town:
		_paint_town(s, rng)
	elif s.kind != "":
		_landmark(s, rng)
	var out := _done(saved)
	_layouts[m] = out
	return out


## The road between two sites: a coarse A* between their nearest street ends, merged into _road.
func _edge(e: Vector4i) -> void:
	if _edges.has(e):
		return
	_edges[e] = true
	var la := _layout(Vector2i(e.x, e.y))
	var lb := _layout(Vector2i(e.z, e.w))
	var best := [INF, NONE, NONE]
	for a: Vector2i in la.ports:
		for b: Vector2i in lb.ports:
			if Vector2(a - b).length() < best[0]:
				best = [Vector2(a - b).length(), a, b]
	if best[1] == NONE:
		return
	var sa := site(Vector2i(e.x, e.y))
	var sb := site(Vector2i(e.z, e.w))
	var paved: bool = "city" in [sa.kind, sb.kind] or sa.kind in ["suburb", "industrial", "highway"] and sb.kind in ["suburb", "industrial", "highway"]
	var saved := _begin(M.EDGE)
	for p: Array in _paved_path(_route(best[1], best[2], [la.cells, lb.cells], [_box(sa), _box(sb)]), paved):
		var o: Vector2i = _road.get(p[0], NO)
		var v: Vector2i = p[1]
		if _rank(v.x) > _rank(o.x) or _rank(v.x) == _rank(o.x) and v.y > o.y: # the same whatever order roads come in
			_road[p[0]] = v
	_done(saved)


func _rank(t: int) -> int:
	return {T.BRIDGE: 3, T.ROAD: 2, T.DIRT_ROAD: 1}.get(t, 0)


func _box(s: Dictionary) -> Rect2i:
	return Rect2i(s.center - Vector2i(SITE_REACH, SITE_REACH), Vector2i.ONE * (2 * SITE_REACH + 1))


## Cells from a to b: A* over ROAD_NODE-cell nodes (water, rock and woods costly, streets cheap, nodes holding houses
## or gardens of the `layers` solid), then straight runs between node centres. `layers` are cell dictionaries over
## the terrain, `boxes` the areas they cover.
func _route(a: Vector2i, b: Vector2i, layers: Array, boxes: Array) -> Array:
	var ea := _exit(a, layers)
	var eb := _exit(b, layers)
	var na := _node(ea.back())
	var nb := _node(eb.back())
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(na.min(nb) - Vector2i.ONE * ROAD_MARGIN, (na - nb).abs() + Vector2i.ONE * (2 * ROAD_MARGIN + 1))
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	grid.update()
	for x in range(grid.region.position.x, grid.region.end.x):
		for y in range(grid.region.position.y, grid.region.end.y):
			var nd := Vector2i(x, y)
			var cc := nd * ROAD_NODE + Vector2i(2, 2)
			var t := -1
			for i in layers.size():
				if boxes[i].has_point(cc):
					t = layers[i].get(cc, NO).x if t < 0 else t
					if nd != na and nd != nb and _walled(layers[i], nd):
						grid.set_point_solid(nd)
			if grid.is_point_solid(nd):
				continue
			if t < 0:
				t = _tile(cc)
			match t:
				T.WATER:
					grid.set_point_weight_scale(nd, 5.0)
				T.ROCK:
					grid.set_point_weight_scale(nd, 4.0)
				T.FOREST, T.TREE_EDGE, T.MARSH, T.HEDGE:
					grid.set_point_weight_scale(nd, 2.0)
				T.ROAD, T.DIRT_ROAD, T.DIRT_X, T.ASPHALT, T.PLAZA, T.BRIDGE:
					grid.set_point_weight_scale(nd, 0.5) # share streets rather than run beside them
	var ids := grid.get_id_path(na, nb)
	if ids.is_empty():
		return []
	eb.reverse()
	var path := ea.duplicate()
	for target: Vector2i in ids.map(func(nd): return nd * ROAD_NODE + Vector2i(2, 2)) + eb:
		var p: Vector2i = path.back()
		while p != target:
			p += Vector2i(signi(target.x - p.x), 0) if p.x != target.x else Vector2i(0, signi(target.y - p.y))
			path.append(p)
	return path


func _node(cell: Vector2i) -> Vector2i:
	return Vector2i(floori(cell.x / float(ROAD_NODE)), floori(cell.y / float(ROAD_NODE)))


## Street end a and the cells on along its street out of the site (at most 6) until a node holds no houses or walls,
## so a road never has to squeeze past them to reach the street.
func _exit(a: Vector2i, layers: Array) -> Array:
	var tile := func(c: Vector2i) -> int:
		for l: Dictionary in layers:
			if l.has(c):
				return l[c].x
		return _tile(c)
	var out := Vector2i.ZERO
	for dir: Vector2i in DIRS: # the way the street at a leads out
		if tile.call(a - dir) in ROADS and not tile.call(a + dir) in ROADS:
			out = dir
	var path := [a]
	while out != Vector2i.ZERO and path.size() <= 6 and layers.any(func(l): return _walled(l, _node(path.back()))):
		path.append(path.back() + out)
	return path


func _walled(cells: Dictionary, nd: Vector2i) -> bool:
	for k in ROAD_NODE * ROAD_NODE:
		if cells.get(nd * ROAD_NODE + Vector2i(k % ROAD_NODE, k / ROAD_NODE), NO).x in WALLED:
			return true
	return false


## [cell, Vector2i(tile, alt)] along a path: road, or over water a ford (runs up to FORD) or a bridge.
func _paved_path(path: Array, paved: bool) -> Array:
	var out := []
	var i := 0
	while i < path.size():
		if _tile(path[i]) != T.WATER:
			out.append([path[i], Vector2i(T.ROAD if paved else T.DIRT_ROAD, 0)])
			i += 1
			continue
		var j := i
		while j < path.size() and _tile(path[j]) == T.WATER:
			j += 1
		for k in range(i, j):
			var d: Vector2i = path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]
			var t := T.BRIDGE if paved or j - i > FORD else T.DIRT_ROAD
			out.append([path[k], Vector2i(t, ACROSS if absi(d.x) > absi(d.y) else 0)])
		i = j
	return out


## Lone houses and wild POIs of chunk c, away from sites, from the roads and sites under it; paint stays in the chunk.
func _lone(c: Vector2i) -> Dictionary:
	if _lones.has(c):
		return _lones[c]
	for x in range(-1, 2):
		for y in range(-1, 2):
			_need_roads(c + Vector2i(x, y))
	var origin := c * CHUNK
	var mid := origin + Vector2i(CHUNK / 2, CHUNK / 2)
	var s := site(_macro(mid))
	var saved := _begin(M.LONE)
	_clip = Rect2i(origin, Vector2i(CHUNK, CHUNK))
	if c != Vector2i.ZERO and (s.kind == "" or Vector2(s.center - mid).length() > SITE_REACH + CHUNK * 0.75):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([Game.seed, c.x, c.y])
		var reg := region(mid)
		var homes := _lone_houses(origin, rng, reg, 1) if rng.randf() < LONE_CHANCE[reg] else []
		_place_wild_poi(origin, rng, Vector2(c).length(), reg, homes)
	var out := _done(saved)
	_lones[c] = out
	return out


func _put(cell: Vector2i, t: int, alt := 0) -> void:
	if absi(cell.x - START.x) <= 6 and absi(cell.y - START.y) <= 6:
		return # never paint over the start site
	if _mode == M.LONE and not _clip.has_point(cell):
		return
	if t in [T.ROAD, T.DIRT_ROAD] and _terrain(cell) & 0xff == T.WATER and _wet(cell, Vector2i(1, 0) if alt & ACROSS else Vector2i(0, 1)) > FORD:
		t = T.BRIDGE # streets cross rivers on bridges, brooks at fords
	_buf[cell] = Vector2i(t, alt)


## Cells of bare-terrain water through c along d (c included), counted up to 6.
func _wet(c: Vector2i, d: Vector2i) -> int:
	var run := 1
	for dir in [d, -d]:
		var p: Vector2i = c + dir
		while run <= 5 and _terrain(p) & 0xff == T.WATER:
			run += 1
			p += dir
	return run


## Bend, junction or straight tile a road cell takes from its road neighbours (see the composed layers), or NO to keep
## it: a bend where two meet at a right angle, a junction (asphalt / plain dirt) where three or four meet, straight
## along the road otherwise. Asphalt lots and bridges stay as they are, but a street corner made asphalt bends.
func _bend(c: Vector2i) -> Vector2i:
	var t := _ft(c)
	if not t in ROADS or t == T.BRIDGE:
		return NO
	var m := 0
	var k := 0
	var paved := t in [T.ROAD, T.ROAD_BEND]
	var lot := false
	var nt := []
	for i in 4:
		nt.append(_ft(c + DIRS[i]))
		if nt[i] in LINES:
			m |= 1 << i
			k += 1
			paved = paved or (t == T.ASPHALT and nt[i] in [T.ROAD, T.ROAD_BEND])
		lot = lot or nt[i] == T.ASPHALT
	var wide := false # two roads side by side (a 2x2 block): no bends or junctions, just straight
	for i in 4:
		wide = wide or m & (1 << i) != 0 and m & (1 << (i + 1) % 4) != 0 and _ft(c + DIRS[i] + DIRS[(i + 1) % 4]) in LINES
	if m in [3, 6, 12, 9] and not wide and not (t == T.ASPHALT and lot):
		return Vector2i(T.ROAD_BEND if paved else T.DIRT_BEND, (BEND_W if m & 8 else 0) + (BEND_N if m & 1 else 0))
	if t == T.ASPHALT:
		return NO
	if k >= 3 and not wide:
		return Vector2i(T.ASPHALT if paved else T.DIRT_X, 0)
	if m != 0: # across where it runs east-west only, or east-west and not north-south
		return Vector2i(T.ROAD if paved else T.DIRT_ROAD, ACROSS if m & 5 == 0 or m & 10 == 10 and m & 5 != 5 else 0)
	return NO


## Composed tile id of a cell before bends (bends count as their plain road).
func _ft(cell: Vector2i) -> int:
	var f := _final(cell).x
	return SAME.get(f, f) if f >= 0 else _terrain(cell) & 0xff


## Zombies chewed through a house wall (enemy.gd): the cell becomes rubble.
func break_in(cell: Vector2i) -> void:
	edit(cell, T.RUIN)
	Game.world.nav_dirty()
	Game.world.spawn_fx(Vector2(cell) * TILE + Vector2(TILE, TILE) / 2.0, 0.5)


## Open ground a house or structure may take: not water, road, town, city or a prop, and clear of the start site.
func _free(cell: Vector2i) -> bool:
	if (absi(cell.x - START.x) <= 9 and absi(cell.y - START.y) <= 9) or _taken.has(cell):
		return false
	var p := _painted(cell)
	var t := p if p >= 0 else _terrain(cell)
	if t >= 65536 or not t & 0xff in BUILDABLE: # a terrain tree stands there
		return false
	if _mode == M.LONE:
		var l := _layout(_macro(cell))
		return not l.taken.has(cell) and not l.city.has_point(cell)
	return true


## A prop of the layout being built (or straight away outside layouts), spawned with the chunk it stands in (lone
## layouts: with their own chunk).
func _prop(name: String, pos: Vector2, rot := 0.0, tint := Color.WHITE) -> void:
	if _mode == M.GEN:
		Game.world.spawn_prop(name, pos, rot).modulate = tint
		return
	var c := _chunk_of(_clip.position) if _mode == M.LONE else _chunk_of(Vector2i((pos / TILE).floor()))
	if not _out.props.has(c):
		_out.props[c] = []
	_out.props[c].append([name, pos, rot, tint])


## A POI of the layout being built (count 0: the POI rolls its own).
func _poi(kind: String, pos: Vector2, count := 0) -> void:
	var c := _chunk_of(_clip.position) if _mode == M.LONE else _chunk_of(Vector2i((pos / TILE).floor()))
	if not _out.pois.has(c):
		_out.pois[c] = []
	_out.pois[c].append([kind, pos, count])


## A town centre of the layout being built, for the spawner's hordes.
func _town(pos: Vector2) -> void:
	var c := _chunk_of(Vector2i((pos / TILE).floor()))
	if not _out.towns.has(c):
		_out.towns[c] = []
	_out.towns[c].append(pos)


## World px centre of the cell rectangle spanned by a and b.
func _mid(a: Vector2i, b: Vector2i) -> Vector2:
	return (Vector2(a) + Vector2(b) + Vector2.ONE) * 0.5 * TILE


## Big prop on a non-landable PAD footprint (top-left tl, size sz cells); false if the ground is taken.
func _struct(tl: Vector2i, sz: Vector2i, name: String, rot := 0.0, tint := Color.WHITE) -> bool:
	for x in sz.x:
		for y in sz.y:
			if not _free(tl + Vector2i(x, y)):
				return false
	for x in sz.x:
		for y in sz.y:
			_put(tl + Vector2i(x, y), T.PAD)
			_taken[tl + Vector2i(x, y)] = true
	_prop(name, _mid(tl, tl + sz - Vector2i.ONE), rot, tint)
	return true


## Tries random spots around `near` until the structure fits.
func _struct_near(near: Vector2i, rad: int, sz: Vector2i, name: String, rng: RandomNumberGenerator, rot := 0.0) -> bool:
	for _i in 8:
		if _struct(near + Vector2i(rng.randi_range(-rad, rad), rng.randi_range(-rad, rad)), sz, name, rot):
			return true
	return false


## Every runtime tile change (base floor, demolition, break-ins, tutorial clearing) goes through here so it is saved.
func edit(cell: Vector2i, t: int, alt := 0) -> void:
	edits[cell] = Vector2i(t, alt)
	var c := _chunk_of(cell)
	if loaded.has(c):
		set_cell(cell, 0, Vector2i(t, 0), alt)
	else:
		if not _pending.has(c):
			_pending[c] = {}
		_pending[c][cell] = Vector2i(t, alt)


## A generator prop (spawn_prop node) removed at runtime (demolition), remembered by position.
func cut_prop(p: Node2D) -> void:
	cuts.append(p.position)
	p.queue_free()


## spawn_prop node at `pos`, null if none.
func prop_at(pos: Vector2) -> Node2D:
	for n in Game.world.get_children():
		if n.get_class() == "Node2D" and n.get_script() == null and not n.is_queued_for_deletion() and n.position.distance_to(pos) < 0.5:
			return n
	return null


## Stable id for a new POI: "cx,cy#n" while a chunk generates (the same after a replay), else "dyn#n".
func poi_uid() -> String:
	if _gen != NONE:
		_gen_n += 1
		return "%d,%d#%d" % [_gen.x, _gen.y, _gen_n - 1]
	_dyn_n += 1
	return "dyn#%d" % (_dyn_n - 1)


## Save hook "world" (after Game and the heli, before POIs). Generation does not depend on load order, so replaying
## the chunk log matters only for POI uids and for the base being founded on loaded ground.
func save_state() -> Dictionary:
	return {"events": events, "edits": edits, "cuts": cuts, "dyn_n": _dyn_n}


func load_state(d: Dictionary) -> void:
	for e in d["events"]: # the replay logs itself again
		if e[0] == "chunk":
			_ensure(Vector2i(e[1], e[2]))
		elif e[0] == "found":
			Game.world.place_base(e[1])
	for cell in d["edits"]:
		edit(cell, d["edits"][cell].x, d["edits"][cell].y)
	for pos in d["cuts"]:
		var p := prop_at(pos)
		if p:
			cut_prop(p)
	_dyn_n = d["dyn_n"]
	Game.world.nav_dirty()


## The FOB (main.found_base): concrete under the 5x5 pad and the hangar (base.HANGAR, door row included), props there
## removed; the ground around (fields, yards, roads...) stays.
func paint_base_at(center: Vector2i) -> void:
	events.append(["found", center])
	for o in [Vector2i(-10, -10), Vector2i(10, -10), Vector2i(-10, 10), Vector2i(10, 10)]: # loaded first, or terrain would paint over it
		_ensure(_chunk_of(center + o))
	for r in [Rect2i(center - Vector2i(2, 2), Vector2i(5, 5)), Rect2i(center + Vector2i(-5, -3), Vector2i(3, 3))]:
		var area := Rect2(Vector2(r.position) * TILE, Vector2(r.size) * TILE)
		for n in Game.world.get_children():
			if n.get_class() == "Node2D" and n.get_script() == null and area.has_point(n.position): # spawn_prop trees, barns...
				n.queue_free()
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				set_cell(Vector2i(x, y), 0, Vector2i(T.BASE_FLOOR, 0))
	Game.world.nav_dirty()


# ---------------------------------------------------------------- towns

## Paints town site s into the layout being built; the start macro's town also gets a lane to the start site.
func _paint_town(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind: String = s.kind
	var center: Vector2i = s.center
	var dist := Vector2(center - START).length() / CHUNK
	var size := rng.randi_range(TOWN_SIZE[kind].x, TOWN_SIZE[kind].y)
	var along := rng.randf() < 0.5 # main street runs along x
	var st := {"ruin": clampf(dist * 0.05, 0.03, 0.35), "small": 0.5, "gap": 0.2, "trees": 0.35, "tree": "tree", "fence": 0.25,
		"roofs": [1, 3, 0], "yard": T.HOUSE_YARD, "road": T.ROAD}
	var layout := kind
	match kind:
		"village":
			st.roofs = [1, 1, 3, 0]
			st.fence = 0.35
		"hamlet":
			st.roofs = [3, 4, 0, 1]
			st.road = T.DIRT_ROAD
		"fishing":
			st.roofs = [2, 0, 5, 2]
			st.small = 0.7
			st.road = T.DIRT_ROAD
		"farm":
			st.roofs = [1, 3, 0]
			st.small = 0.3
		"suburb":
			st.roofs = [0, 2, 5, 3, 4]
			st.small = 0.0
			st.gap = 0.08
			st.trees = 0.35
			st.fence = 0.2
		"city":
			st.roofs = [0, 2, 4, 3, 5]
			st.small = 0.25
			st.gap = 0.05
			st.trees = 0.3
			st.fence = 0.15
		"ruined":
			st.ruin = 0.85
			st.yard = T.ASH
			st.trees = 0.3
			st.tree = "dead_tree"
			st.fence = 0.0
			st.roofs = [4, 3, 0]
			layout = ["village", "hamlet", "suburb"][rng.randi() % 3]
	var ends: Array
	match layout:
		"village":
			ends = _village(center, along, size, rng, st)
		"hamlet", "fishing":
			ends = _hamlet(center, along, size, rng, st)
		"farm":
			ends = _farm_town(center, along, size, rng, st)
		"suburb":
			ends = _suburb(center, along, size, rng, st)
		"industrial":
			ends = _industrial(center, along, size, rng)
		"city":
			ends = _city(center, size, rng, st)
	if kind == "fishing":
		_jetties(center, size * 2 + 6, rng, rng.randi_range(2, 4))
	if kind == "ruined":
		_scorch(center, size + 8, rng)
	var ports: Array = [ends[0], ends[1]] + ends.slice(3) # ends[2] is the centre
	_out.ports = ports
	if s.m == Vector2i.ZERO: # a lane from the nearest street end to the start site
		var to := START + Vector2i(7, 0)
		ports.sort_custom(func(a, b): return Vector2(a - to).length() < Vector2(b - to).length())
		for p: Array in _paved_path(_route(ports[0], to, [_buf], [_box(s)]), false):
			if not _tile(p[0]) in TOWNISH and not _tile(p[0]) in ROADS:
				_put(p[0], p[1].x, p[1].y)
	var world_center := _mid(ends[2], ends[2])
	if kind == "city": # more people holed up across the blocks
		for _i in 2:
			var at := _find(ends[2], size * 5, [T.ROAD], rng)
			if at != NONE:
				_town(_mid(at, at))
				_poi("survivors", _mid(at, at))
	_town(world_center)
	_poi("survivors", world_center, rng.randi_range(5, 8) if kind == "city" else 0)
	for p: Array in [["water_tower", 0.5, ROADS], ["pharmacy", 0.35, [T.BUILDING]]]: # on a road / a house roof
		if rng.randf() < p[1]:
			var at := _find(ends[2], size * 2, p[2], rng)
			if at != NONE:
				_poi(p[0], _mid(at, at))
	if rng.randf() < 0.5:
		var off := Vector2(rng.randf_range(-size, size), rng.randf_range(-size, size)) * TILE * 2
		_poi("crate", world_center + off)
	# dens sit well outside town (the boss wakes at 420 px), and rarely unless the town is ruined
	if rng.randf() < (0.5 if kind == "ruined" else 0.12) and world_center.distance_to(_mid(START, START)) > 1100.0:
		for _i in 6: # on dry land
			var at := world_center + Vector2((size + 34) * TILE, 0).rotated(rng.randf() * TAU)
			if _tile(Vector2i((at / TILE).floor())) in OPEN:
				_poi("nest", at)
				break
	if kind in ["industrial", "city"] or (kind == "suburb" and rng.randf() < 0.3):
		var yard := _find(ends[2], size * 2, ROADS, rng)
		if yard != NONE:
			_poi("scrapyard", _mid(yard, yard))


## A random cell of one of `tiles` within `rad` of `center`, NONE after 30 misses.
func _find(center: Vector2i, rad: int, tiles: Array, rng: RandomNumberGenerator) -> Vector2i:
	for _i in 30:
		var c := center + Vector2i(rng.randi_range(-rad, rad), rng.randi_range(-rad, rad))
		if _tile(c) in tiles:
			return c
	return NONE


func _dir(along: bool) -> Vector2i:
	return Vector2i(1, 0) if along else Vector2i(0, 1)


## Straight street of n cells from a along d. Crossing an existing street makes a plain asphalt junction.
## Main streets bridge rivers up to 5 cells wide, side streets (`wet` false) stop short of water.
func _street(a: Vector2i, d: Vector2i, n: int, t: int, wet := true) -> void:
	for k in n:
		var c := a + d * k
		if _tile(c) == T.WATER:
			if not wet:
				return
			if _span(c, d) > 5:
				continue
		var was := _painted(c)
		if was in BUILT:
			continue # another town got here first: go round its houses
		_put(c, T.ASPHALT if t == T.ROAD and was == T.ROAD else t, ACROSS if d.x != 0 else 0)


## Cells in the water run through c along d (c included), counted up to 6.
func _span(c: Vector2i, d: Vector2i) -> int:
	var run := 1
	for dir in [d, -d]:
		var p: Vector2i = c + dir
		while run <= 5 and _tile(p) == T.WATER:
			run += 1
			p += dir
	return run


## A house of w cells along the street by dep cells deep, behind a one-cell front yard at `yard`; `o` points away
## from the street. Back garden with a tree and a fence sometimes. Returns the house centre (world px) or Vector2.INF.
func _lot(yard: Vector2i, d: Vector2i, o: Vector2i, w: int, dep: int, rng: RandomNumberGenerator, st: Dictionary) -> Vector2:
	for i in w:
		for k in dep + 1:
			if not _free(yard + d * i + o * k):
				return Vector2.INF
	var ruin := rng.randf() < float(st.ruin)
	var roof: int = st.roofs[rng.randi() % st.roofs.size()]
	for i in w:
		_put(yard + d * i, st.yard if i == 0 else T.GRASS2, 0 if o.y != 0 else ACROSS) # the path leads to the door
		for k in range(1, dep + 1):
			_put(yard + d * i + o * k, T.RUIN if ruin else T.BUILDING, 0 if ruin else ROOF_ALT + roof)
		var g := yard + d * i + o * (dep + 1)
		if rng.randf() < float(st.trees) and _free(g):
			_prop(st.tree, _mid(g, g) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
			_taken[g] = true
	var a := yard + o
	var b := yard + d * (w - 1) + o * dep
	if not ruin:
		var sz := (b - a).abs() + Vector2i.ONE
		var name := "house" if sz == Vector2i.ONE else ("house_2x2" if sz.x == sz.y else "house_2x1")
		_prop(name, _mid(a, b), PI / 2 if sz.y > sz.x or (sz.x == sz.y and d.y != 0) else 0.0, ROOFS[roof])
		if rng.randf() < float(st.fence):
			for i in w:
				_prop("fence", (Vector2(yard + d * i) + Vector2(0.5, 0.5) + Vector2(o) * (dep + 1.45)) * TILE, 0.0 if o.y != 0 else PI / 2)
	return _mid(a, b)


## Houses along one side of a street: yards at a + d * k, houses beyond them in direction o.
func _side(a: Vector2i, d: Vector2i, n: int, o: Vector2i, rng: RandomNumberGenerator, st: Dictionary) -> void:
	var k := rng.randi_range(0, 1)
	while k < n:
		var w := mini(1 if rng.randf() < float(st.small) else 2, n - k)
		if rng.randf() >= float(st.gap):
			_lot(a + d * k, d, o, w, 1 if rng.randf() < 0.6 else 2, rng, st)
		k += w + (1 if rng.randf() < 0.4 else 0)


func _rows(a: Vector2i, d: Vector2i, n: int, rng: RandomNumberGenerator, st: Dictionary) -> void:
	var o := Vector2i(d.y, d.x)
	_side(a + o, d, n, o, rng, st)
	_side(a - o, d, n, -o, rng, st)


## Village: a cobbled square with the church on one side and a pond at a corner, streets out in three directions.
func _village(center: Vector2i, along: bool, size: int, rng: RandomNumberGenerator, st: Dictionary) -> Array:
	var d := _dir(along)
	var o := Vector2i(d.y, d.x)
	var q := 1 + size / 3
	var L := size + q + 3
	_fields(center, along, L, q + 5, rng.randi_range(4, 7), rng)
	for u in range(-q, q + 1):
		for v in range(-q, q + 1):
			if _free(center + d * u + o * v):
				_put(center + d * u + o * v, T.PLAZA)
	for corner in [Vector2i(-q, -q), Vector2i(q, -q), Vector2i(-q, q), Vector2i(q, q)]: # trees on the square's corners
		if rng.randf() < 0.6 and _painted(center + corner) == T.PLAZA:
			_prop(st.tree, _mid(center + corner, center + corner))
	var tl := center + (Vector2i(-1, -q - 3) if along else Vector2i(-q - 2, -1))
	if rng.randf() > float(st.ruin):
		_struct(tl, Vector2i(2, 3), "church")
	var pc := center + (d + o) * (q + 3)
	var pr := rng.randf_range(1.6, 2.6)
	for x in range(-3, 4):
		for y in range(-3, 4):
			if Vector2(x, y * 1.2).length() <= pr and _free(pc + Vector2i(x, y)):
				_put(pc + Vector2i(x, y), T.WATER)
	for i in 3:
		var tc := pc + Vector2i((Vector2.RIGHT * (pr + 1.5)).rotated(rng.randf() * TAU).round())
		if _free(tc):
			_prop(st.tree, _mid(tc, tc))
			_taken[tc] = true
	_street(center - d * (L + 2), d, 2 * L + 5, T.ROAD)
	_street(center + o * (q + 1), o, size + 3, T.ROAD, false)
	# houses facing the square, then along the streets
	_side(center - o * (q + 1) - d * q, d, 2 * q + 1, -o, rng, st)
	_side(center + o * (q + 1) - d * q, d, 2 * q + 1, o, rng, st)
	_side(center + d * (q + 1) - o * q, o, 2 * q + 1, d, rng, st)
	_side(center - d * (q + 1) - o * q, o, 2 * q + 1, -d, rng, st)
	_rows(center + d * (q + 1), d, L - q, rng, st)
	_rows(center - d * (q + 1), -d, L - q, rng, st)
	_rows(center + o * (q + 1), o, size + 3, rng, st)
	return [center - d * (L + 2), center + d * (L + 2), center]


## Roadside hamlet: houses strung along one winding road.
func _hamlet(center: Vector2i, along: bool, size: int, rng: RandomNumberGenerator, st: Dictionary) -> Array:
	var d := _dir(along)
	var o := Vector2i(d.y, d.x)
	var L := size * 2 + 4
	var amp := rng.randf_range(1.5, 3.0)
	var per := rng.randf_range(30.0, 46.0)
	var ph := rng.randf() * TAU
	var off0 := roundi(amp * sin(ph))
	var pts := []
	var prev := 0
	for u in range(-L, L + 1):
		var off := roundi(amp * sin(u / per * TAU + ph)) - off0
		for s in range(prev, off, signi(off - prev) if off != prev else 1): # sideways steps keep the road joined
			if _tile(center + d * u + o * s) != T.WATER or _span(center + d * u + o * s, o) <= 5:
				_put(center + d * u + o * s, st.road, ACROSS if o.x != 0 else 0)
		pts.append(center + d * u + o * off)
		if _tile(pts.back()) != T.WATER or _span(pts.back(), d) <= 5: # fords over streams, no causeways over lakes
			_put(pts.back(), st.road, ACROSS if d.x != 0 else 0)
		prev = off
	for s: int in [-1, 1]:
		var k := rng.randi_range(1, 3)
		while k < pts.size() - 2:
			var w := 1 if rng.randf() < float(st.small) else 2
			if rng.randf() < (0.85 if absi(k - L) < size * 2 else 0.35):
				_lot(pts[k] + o * s, d, o * s, w, 1 if rng.randf() < 0.6 else 2, rng, st)
			k += w + rng.randi_range(1, 2)
	_fields(center, along, L, 6, rng.randi_range(2, 5), rng)
	return [pts[0] - d, pts.back() + d, pts[L]]


## Farm town: main street with houses, barns, a grain elevator (silo row) and fields all around.
func _farm_town(center: Vector2i, along: bool, size: int, rng: RandomNumberGenerator, st: Dictionary) -> Array:
	var d := _dir(along)
	var o := Vector2i(d.y, d.x)
	var L := size + 4
	_fields(center, along, L, 6, rng.randi_range(9, 13), rng)
	_street(center - d * (L + 2), d, 2 * L + 5, T.ROAD)
	_rows(center - d * L, d, 2 * L + 1, rng, st)
	for s: int in [-1, 1]: # the farm yards behind the house rows
		var at := center + d * rng.randi_range(-L + 2, L - 4) + o * s * 6
		_struct_near(at, 2, Vector2i(2, 2), "barn", rng)
		if rng.randf() < 0.6:
			_struct_near(at + d * 4, 2, Vector2i(1, 2), "silo", rng)
	var el := center + d * rng.randi_range(-3, 1) - o * 5 * (1 if rng.randf() < 0.5 else -1) - Vector2i(1, 1)
	for _i in 6: # grain elevator: a row of three silos
		var ok := true
		for x in 3:
			for y in 2:
				ok = ok and _free(el + Vector2i(x, y))
		if ok:
			for x in 3:
				_struct(el + Vector2i(x, 0), Vector2i(1, 2), "silo")
			break
		el += Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
	if rng.randf() < 0.5:
		_struct_near(center + o * 7, 4, Vector2i(1, 2), "water_tower", rng)
	return [center - d * (L + 2), center + d * (L + 2), center]


## Suburb: a boulevard with cul-de-sacs off both sides, a strip mall with a car park and a gas station.
func _suburb(center: Vector2i, along: bool, size: int, rng: RandomNumberGenerator, st: Dictionary) -> Array:
	var d := _dir(along)
	var o := Vector2i(d.y, d.x)
	var L := size + 5
	var reach := 5 + size / 2
	var ms := 1 if rng.randf() < 0.5 else -1 # strip mall side
	_street(center - d * (L + 2), d, 2 * L + 5, T.ROAD)
	var mo := o * ms
	for u in range(-4, 5):
		for v in range(1, 7):
			var cell := center + d * u + mo * v
			if not _free(cell):
				continue
			match v:
				1, 3:
					_put(cell, T.ASPHALT)
				2, 4:
					var face := mo if v == 2 else -mo # bays open onto the aisle at v = 3
					_put(cell, T.PARKING, _bay_alt(face))
					for b: int in [-4, 4]:
						if rng.randf() < 0.3:
							_prop("car", _mid(cell, cell) + Vector2(d) * b, Vector2(face).angle(), CARS[rng.randi() % CARS.size()])
				_:
					_put(cell, T.WAREHOUSE, 0 if along else ACROSS)
	var gu := (L - 5) * (1 if rng.randf() < 0.5 else -1)
	for u in range(gu - 2, gu + 2):
		for v in range(1, 4):
			if _free(center + d * u - mo * v):
				_put(center + d * u - mo * v, T.ASPHALT)
	var g := center + d * (gu - 1) - mo * 2
	if _painted(g) == T.ASPHALT and _painted(g + d) == T.ASPHALT:
		_put(g, T.PAD)
		_put(g + d, T.PAD)
		_prop("gas_station", _mid(g, g + d), 0.0 if along else PI / 2)
	var streets := []
	for u in range(-L + 4, L - 3, 8):
		for s: int in [-1, 1]:
			if s == ms and absi(u) <= 6 or s == -ms and absi(u - gu) <= 3:
				continue
			var a := center + d * u + o * s
			_street(a, o * s, reach, T.ROAD, false)
			var bulb := a + o * s * (reach + 1)
			for x in range(-1, 2):
				for y in range(-1, 2):
					if _tile(bulb + Vector2i(x, y)) in BUILDABLE:
						_put(bulb + Vector2i(x, y), T.ASPHALT)
			streets.append([a, o * s])
	for sv in streets:
		_rows(sv[0], sv[1], reach, rng, st)
		_side(sv[0] + sv[1] * (reach + 3) - d, d, 3, sv[1], rng, st) # at the end of the cul-de-sac
	_rows(center - d * L, d, 2 * L + 1, rng, st)
	if rng.randf() < 0.6:
		_struct_near(center - mo * (reach + 3), 5, Vector2i(1, 2), "water_tower", rng)
	return [center - d * (L + 2), center + d * (L + 2), center]


## City: a grid of n x n blocks of terraced houses around a plaza with a church, with a park, warehouses and car parks
## among them; the middle streets run on out of town. Returns [west, east, centre, north, south] street ends.
func _city(center: Vector2i, n: int, rng: RandomNumberGenerator, st: Dictionary) -> Array:
	var span := n * BLOCK
	var tl := center - Vector2i(span, span) / 2
	var mid := n / 2 * BLOCK # the middle streets
	var special := {Vector2i(n / 2, n / 2): "plaza"} # the block south-east of the middle crossing
	for kind in ["park", "warehouse", "parking", "warehouse" if rng.randf() < 0.5 else "parking"]:
		for _i in 8:
			var b := Vector2i(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1))
			if not special.has(b):
				special[b] = kind
				break
	for i in n + 1:
		_street(tl + Vector2i(0, i * BLOCK), Vector2i.RIGHT, span + 1, T.ROAD)
		_street(tl + Vector2i(i * BLOCK, 0), Vector2i.DOWN, span + 1, T.ROAD)
	_street(tl + Vector2i(-4, mid), Vector2i.RIGHT, 4, T.ROAD) # out of town, kept off the grid so it stays plain road
	_street(tl + Vector2i(span + 1, mid), Vector2i.RIGHT, 4, T.ROAD)
	_street(tl + Vector2i(mid, -4), Vector2i.DOWN, 4, T.ROAD)
	_street(tl + Vector2i(mid, span + 1), Vector2i.DOWN, 4, T.ROAD)
	for bx in n:
		for by in n:
			var a := tl + Vector2i(bx, by) * BLOCK + Vector2i.ONE # first lot cell
			var kind: String = special.get(Vector2i(bx, by), "houses")
			if kind == "plaza":
				_struct(a + Vector2i(4, 3), Vector2i(2, 3), "church")
			for v in (BLOCK - 1) * (BLOCK - 1):
				var c := a + Vector2i(v % (BLOCK - 1), v / (BLOCK - 1))
				if not _free(c):
					continue
				var rim := c.x == a.x or c.y == a.y or c.x == a.x + BLOCK - 2 or c.y == a.y + BLOCK - 2
				var row := (c.y - a.y) % 3
				match kind:
					"plaza":
						_put(c, T.PLAZA)
					"park":
						_put(c, T.GRASS2)
						if not rim and rng.randf() < 0.18:
							_prop(st.tree, _mid(c, c) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
						_taken[c] = true
					"warehouse":
						_put(c, T.ASPHALT if rim else T.WAREHOUSE)
					"parking": # aisles every third row, bays opening onto them
						var face := Vector2i.UP if row == 1 else Vector2i.DOWN
						if row == 0:
							_put(c, T.ASPHALT)
						else:
							_put(c, T.PARKING, _bay_alt(face))
							if rng.randf() < 0.3:
								_prop("car", _mid(c, c), Vector2(face).angle(), CARS[rng.randi() % CARS.size()])
					_:
						if not _tile(c) in GRASSY: # no crops or woods between the houses
							_put(c, T.GRASS)
			if kind == "houses":
				var e := BLOCK - 2
				_side(a, Vector2i.RIGHT, e + 1, Vector2i.DOWN, rng, st)
				_side(a + Vector2i(0, e), Vector2i.RIGHT, e + 1, Vector2i.UP, rng, st)
				_side(a, Vector2i.DOWN, e + 1, Vector2i.RIGHT, rng, st)
				_side(a + Vector2i(e, 0), Vector2i.DOWN, e + 1, Vector2i.LEFT, rng, st)
	_out.city = Rect2i(tl, Vector2i(span + 1, span + 1))
	return [tl + Vector2i(-4, mid), tl + Vector2i(span + 4, mid), tl + Vector2i(mid, mid), tl + Vector2i(mid, -4), tl + Vector2i(mid, span + 4)]


## Alternative for a PARKING tile whose bays open towards `face`.
func _bay_alt(face: Vector2i) -> int:
	if face.y != 0:
		return 0 if face.y > 0 else FLIP
	return ACROSS if face.x > 0 else FLIP + ACROSS


## Industrial yard: warehouses and fuel tanks on asphalt, a long straight rail-like dirt road beside it.
func _industrial(center: Vector2i, along: bool, size: int, rng: RandomNumberGenerator) -> Array:
	var d := _dir(along)
	var o := Vector2i(d.y, d.x)
	var L := size + 3
	var W := 4 + size / 3
	for u in range(-L, L + 1):
		for v in range(-W, W + 1):
			if _free(center + d * u + o * v):
				_put(center + d * u + o * v, T.ASPHALT)
	_street(center - d * (L + 3), d, 2 * L + 7, T.ROAD)
	for s: int in [-1, 1]:
		var u := -L + 1
		while u < L - 2:
			var w := rng.randi_range(3, 5)
			var h := rng.randi_range(2, W - 2)
			var tanks := rng.randf() < 0.25
			for i in mini(w, L - u):
				for k in h:
					var cell := center + d * (u + i) + o * s * (2 + k)
					if _painted(cell) != T.ASPHALT:
						continue
					if not tanks:
						_put(cell, T.WAREHOUSE, 0 if along else ACROSS)
					elif k == 0 and i % 2 == 0:
						_put(cell, T.PAD)
						_prop("fuel_tank", _mid(cell, cell))
			u += w + rng.randi_range(1, 2)
	for i in rng.randi_range(2, 5):
		var cell := center + d * rng.randi_range(-L, L) + o * (1 if rng.randf() < 0.5 else -1)
		if _painted(cell) == T.ASPHALT:
			_prop("car", _mid(cell, cell), 0.0 if along else PI / 2, CARS[rng.randi() % CARS.size()])
	var rv := (W + 2) * (1 if rng.randf() < 0.5 else -1)
	for u in range(-L - 24, L + 25):
		var cell := center + d * u + o * rv
		var t := _tile(cell)
		if t != T.WATER and not t in TOWNISH:
			_put(cell, T.DIRT_ROAD, ACROSS if along else 0) # a dead-end track
	return [center - d * (L + 3), center + d * (L + 3), center]


## Farmland rectangles around a town, rows turned per field, some with a hedge along one side.
func _fields(center: Vector2i, along: bool, L: int, W: int, n: int, rng: RandomNumberGenerator) -> void:
	for i in n:
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
		var at := center + (Vector2i(ru, rv) if along else Vector2i(rv, ru))
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
			if rng.randf() < 0.5:
				for x in w:
					if _tile(at + Vector2i(x, -1)) in GRASSY:
						_put(at + Vector2i(x, -1), T.HEDGE, ACROSS)


## Jetties from the shore into the water near a fishing village or hut.
func _jetties(center: Vector2i, rad: int, rng: RandomNumberGenerator, n: int) -> void:
	for _i in n * 8:
		if n <= 0:
			return
		var cell := center + Vector2i(rng.randi_range(-rad, rad), rng.randi_range(-rad, rad))
		if _jetty(cell):
			n -= 1


## Jetty off `cell` if it is land with deep water straight ahead in some direction.
func _jetty(cell: Vector2i) -> bool:
	var t := _tile(cell)
	if not (t in BUILDABLE or t == T.HOUSE_YARD):
		return false
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if _tile(cell + dir) == T.WATER and _tile(cell + dir * 2) == T.WATER:
			_prop("jetty", (Vector2(cell) + Vector2(0.5, 0.5) + Vector2(dir) * 1.25) * TILE, Vector2(dir).angle() + PI / 2)
			return true
	return false


## First direction with water 2..r cells away, or ZERO.
func _water_dir(cell: Vector2i, r: int) -> Vector2i:
	for k in range(2, r + 1):
		for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if _tile(cell + dir * k) == T.WATER:
				return dir
	return Vector2i.ZERO


## Ruined town: ash and craters in the gardens, burnt-out cars on the streets.
func _scorch(center: Vector2i, rad: int, rng: RandomNumberGenerator) -> void:
	for _i in rad * 4:
		var c := center + Vector2i(rng.randi_range(-rad, rad), rng.randi_range(-rad, rad))
		var t := _tile(c)
		if t in GRASSY or t in [T.HOUSE_YARD, T.FIELD, T.PLAZA]:
			_put(c, T.CRATER if rng.randf() < 0.12 else T.ASH)
		elif t in ROADS and rng.randf() < 0.3 and not _taken.has(c):
			_prop("car", _mid(c, c), rng.randf() * TAU, BURNT)
			_taken[c] = true


# ---------------------------------------------------------------- lone houses

## Lone houses fitting the region; returns their cells. Many hide a few survivors.
func _lone_houses(origin: Vector2i, rng: RandomNumberGenerator, reg: int, count: int) -> Array:
	var homes := []
	for _i in count:
		for _try in 6:
			var cell := origin + Vector2i(rng.randi_range(4, CHUNK - 8), rng.randi_range(4, CHUNK - 8))
			var centre := _homestead(cell, rng, reg)
			if centre != Vector2.INF:
				homes.append(cell)
				if rng.randf() < 0.6:
					_poi("hideout", centre)
				break
	return homes


func _homestead(cell: Vector2i, rng: RandomNumberGenerator, reg: int) -> Vector2:
	var st := {"ruin": 0.0, "small": 0.0, "gap": 0.0, "trees": 0.5, "tree": "tree", "fence": 0.3, "roofs": [1, 3], "yard": T.HOUSE_YARD}
	match reg:
		R.FOREST:
			return _cabin(cell, rng, st)
		R.LAKE:
			var dir := _water_dir(cell, 5)
			if dir == Vector2i.ZERO:
				return Vector2.INF
			st.roofs = [2, 0, 5]
			st.trees = 0.2
			st.fence = 0.0
			var hut := _lot(cell - dir, Vector2i(dir.y, dir.x), dir, 1, 1, rng, st) # yard faces away from the water
			if hut != Vector2.INF:
				var s := cell + dir
				while _tile(s + dir) != T.WATER and (s - cell).length() < 6:
					s += dir
				_jetty(s)
				_driveway(cell - dir)
			return hut
		R.WASTE:
			st.ruin = 0.8
			st.yard = T.ASH
			st.tree = "dead_tree"
			st.roofs = [4]
			var c := _lot(cell, Vector2i.RIGHT, Vector2i.UP, 2, 1, rng, st)
			if c != Vector2.INF:
				for _i in 3:
					var a := cell + Vector2i(rng.randi_range(-2, 3), rng.randi_range(-2, 2))
					if _tile(a) in GRASSY:
						_put(a, T.ASH)
				if rng.randf() < 0.4:
					_prop("car", _mid(cell, cell) + Vector2(40, 8), rng.randf() * TAU, BURNT)
			return c
	# farmstead: house, barn, silo, a small field and a driveway
	var mx := 1 if rng.randf() < 0.5 else -1
	var c := _lot(cell + Vector2i(0, 1), Vector2i.RIGHT, Vector2i.UP, 2, 1 if rng.randf() < 0.6 else 2, rng, st)
	if c == Vector2.INF:
		return c
	var barn := cell + Vector2i(3 if mx > 0 else -4, -1)
	if _struct(barn, Vector2i(2, 2), "barn"):
		_put(barn + Vector2i(0, 2), T.DIRT_ROAD, ACROSS)
		_put(barn + Vector2i(1, 2), T.DIRT_ROAD, ACROSS)
		if rng.randf() < 0.7:
			_struct(barn + Vector2i(2 if mx > 0 else -1, 0), Vector2i(1, 2), "silo")
	var f := cell + Vector2i(-1 if mx > 0 else -3, 3)
	var rows := (ACROSS if rng.randf() < 0.5 else 0) + (RIPE if rng.randf() < 0.4 else 0)
	for x in 6:
		for y in 4:
			if _tile(f + Vector2i(x, y)) in GRASSY or _tile(f + Vector2i(x, y)) == T.HEDGE:
				_put(f + Vector2i(x, y), T.FIELD, rows)
	_driveway(cell + Vector2i(0, 1))
	return c


## Cabin in a forest clearing with a woodpile by the door.
func _cabin(cell: Vector2i, rng: RandomNumberGenerator, st: Dictionary) -> Vector2:
	if not _tile(cell) in [T.FOREST, T.TREE_EDGE, T.GRASS, T.GRASS2, T.GRASS3]:
		return Vector2.INF
	for x in range(-3, 4):
		for y in range(-3, 4):
			var c := cell + Vector2i(x, y)
			if _tile(c) == T.FOREST and absi(x) + absi(y) <= 4:
				_put(c, T.TREE_EDGE if absi(x) + absi(y) >= 3 else T.GRASS2)
	st.roofs = [3, 4]
	st.fence = 0.0
	st.trees = 0.0
	var w := 1 if rng.randf() < 0.6 else 2
	var c := _lot(cell, Vector2i.RIGHT, Vector2i.UP, w, 1, rng, st)
	if c != Vector2.INF:
		_prop("woodpile", c + Vector2(w * 8 + 9, 4), PI / 2)
		_driveway(cell)
	return c


## Dirt driveway from `from` straight to the nearest road within 40 cells, if there is one.
func _driveway(from: Vector2i) -> void:
	var best := 41
	var bd := Vector2i.ZERO
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		for k in range(1, best):
			var t := _painted(from + dir * k)
			if t in [T.BUILDING, T.WAREHOUSE, T.PAD, T.WATER]:
				break
			if t in ROADS:
				best = k
				bd = dir
				break
	if bd == Vector2i.ZERO:
		return
	for k in range(1, best):
		if _tile(from + bd * k) == T.WATER:
			return
	for k in range(1, best):
		if not _tile(from + bd * k) in TOWNISH:
			_put(from + bd * k, T.DIRT_ROAD, ACROSS if bd.x != 0 else 0)


## Wild POI with region-flavoured odds: crates near farmsteads and roads, nests in ruins, ash and woods.
func _place_wild_poi(origin: Vector2i, rng: RandomNumberGenerator, dist: float, reg: int, homes: Array) -> void:
	var kinds := ["crate", "radio_tower", "wreck", "upgrade", "nest"]
	var w := [0.1, 0.03, 0.05, 0.07, clampf(dist * 0.06, 0.05, 0.3)] # the wild is mostly nature: loot sits at sites
	match reg:
		R.FARM:
			w[0] += 0.1
		R.FOREST:
			w[1] += 0.05
			w[4] *= 1.5
		R.SUBURB:
			w[3] += 0.05
		R.WASTE:
			w[2] += 0.12
			w[4] *= 1.6
	var r := rng.randf()
	var kind := ""
	for i in kinds.size():
		if r < w[i]:
			kind = kinds[i]
			break
		r -= w[i]
	if kind == "":
		return
	if kind == "nest" and Vector2(origin * TILE).distance_to(_mid(START, START)) < 1100.0:
		kind = "crate" # no hive queen next door on day 1
	for i in 16:
		var cell := origin + Vector2i(rng.randi_range(4, CHUNK - 4), rng.randi_range(4, CHUNK - 4))
		if kind == "crate" and homes.size() > 0 and i < 8:
			cell = homes[0] + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
		if _tile(cell) in OPEN and (kind == "nest" or _clearing(cell)) and (i >= 12 or _likes(kind, cell)):
			_poi(kind, _mid(cell, cell))
			return


## A landing zone: no trees, water or rock in the 3x3 around the cell (the heli must set down next to it).
func _clearing(cell: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if _tile(cell + Vector2i(dx, dy)) in [T.FOREST, T.TREE_EDGE, T.WATER, T.ROCK, T.HEDGE, T.MARSH]:
				return false
	return true


func _likes(kind: String, cell: Vector2i) -> bool:
	var near := []
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		near.append(_tile(cell + dir))
		near.append(_tile(cell + dir * 2))
	match kind:
		"crate":
			return near.any(func(t): return t in ROADS or t == T.HOUSE_YARD or t == T.BUILDING)
		"nest":
			return _tile(cell) in [T.ASH, T.TREE_EDGE] or near.any(func(t): return t == T.RUIN or t == T.FOREST)
	return true


## Dev hook for screenshots (SMOKE=shot): SHOT_AT="x,y" moves the heli to that world position on the first tick.
## A region name ("farm", "forest", "lake", "suburb", "waste", "highland", "river") jumps 440 px west of the nearest
## site in that region (so the scripted eastward flight ends over it), "farm:village" also forces its town template or
## landmark, a landmark name alone ("airfield") finds the nearest one; a trailing "-" picks a macro cell without a site.
func _shot_jump() -> void:
	var p := _shot_at.split(",")
	var key := _shot_at.get_slice(":", 0).trim_suffix("-")
	var want := REGIONS.find(key)
	var kind := _shot_at.get_slice(":", 1) if ":" in _shot_at else ("" if want >= 0 else key)
	var empty := _shot_at.ends_with("-")
	_shot_at = ""
	Game.max_hp = 1e9; Game.hp = 1e9 # screenshots only: the heli must survive wherever it lands
	if p.size() == 2:
		Game.heli.position = Vector2(float(p[0]), float(p[1]))
		return
	for r in range(1, 40):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				var m := Vector2i(x, y)
				var s := site(m)
				if maxi(absi(x), absi(y)) != r or _layouts.has(m) or (want >= 0 and s.reg != want) or (s.kind == "") != empty:
					continue
				if kind != "" and s.kind != kind:
					if want < 0 or kind == "dam" or not (kind in TOWN_SIZE or LANDMARKS.has(kind)):
						continue
					s.kind = kind
					s.town = kind in TOWN_SIZE
				Game.heli.position = _mid(s.center, s.center) - Vector2(440, 0)
				return


# ---------------------------------------------------------------- landmarks

## Paints landmark site s: a stamp of tiles and props round its centre, its POIs and the street ends roads link to.
## Other systems find them through sites_near (kind = the LANDMARKS key).
func _landmark(s: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2i = s.center
	var d := _dir(rng.randf() < 0.5)
	var o := Vector2i(d.y, d.x)
	var g: int = [T.GRASS, T.GRASS, T.GRASS2, T.GRASS, T.ASH, T.GRASS3, T.GRASS2][s.reg] # cleared ground
	var dash := ACROSS if d.x != 0 else 0 # roads and wheel tracks running along d
	var far := _mid(c, c).distance_to(_mid(START, START)) > 1600.0
	match s.kind:
		"gas_station":
			_clear(c, 14, 12, g)
			_street(c - d * 18, d, 37, T.ROAD)
			_area(c, d, o, -6, 6, 1, 7, T.ASPHALT)
			_area(c, d, o, 2, 3, 3, 3, T.PAD)
			_prop("gas_station", _mid(c + d * 2 + o * 3, c + d * 3 + o * 3), 0.0 if d.x != 0 else PI / 2)
			_block(c - d * 4 + o * 5, c - d * 3 + o * 6, 2)
			for k in 2:
				_area(c, d, o, 5, 5, 4 + k * 2, 4 + k * 2, T.PAD)
				_prop("fuel_tank", _mid(c + d * 5 + o * (4 + k * 2), c + d * 5 + o * (4 + k * 2)))
			_cars(c + o * 4, d, o, 6, 2, rng.randi_range(1, 3), rng)
			_poi("fuel_station", _mid(c - d + o * 2, c - d + o * 2))
			if rng.randf() < 0.5:
				_poi("crate", _mid(c - d * 5 + o * 2, c - d * 5 + o * 2))
			_out.ports = [c - d * 18, c + d * 18]
		"checkpoint":
			_clear(c, 16, 12, g)
			_street(c - d * 20, d, 41, T.ROAD)
			for v: int in [-3, -2, -1, 1, 2, 3]: # barriers either side of the lane
				_area(c, d, o, 0, 1, v, v, T.PAD)
			_area(c, d, o, -9, 9, 4, 9, T.ASPHALT)
			_area(c, d, o, -8, -4, 7, 9, T.WAREHOUSE, dash)
			_area(c, d, o, 4, 8, 7, 9, T.WAREHOUSE, dash)
			_struct(c + d * 3 - o * 5, Vector2i(1, 2), "water_tower", 0.0, OLIVE) # watch tower
			_cars(c + o * 5, d, o, 8, 1, rng.randi_range(2, 4), rng, OLIVE)
			_poi("fuel_station", _mid(c - d * 2 + o * 5, c - d * 2 + o * 5))
			_poi("upgrade", _mid(c + d * 2 + o * 5, c + d * 2 + o * 5))
			_poi("crate", _mid(c + o * 6, c + o * 6))
			_out.ports = [c - d * 20, c + d * 20]
		"campground":
			_clear(c, 13, 11, T.GRASS2)
			for u in range(-7, 8):
				for v: int in [-5, 5]:
					_put(c + d * u + o * v, T.DIRT_ROAD, dash)
			for v in range(-4, 5):
				for u: int in [-7, 7]:
					_put(c + d * u + o * v, T.DIRT_ROAD, 0 if d.x != 0 else ACROSS)
			for _i in 9: # tents
				var t := c + d * rng.randi_range(-5, 5) + o * rng.randi_range(-3, 3)
				if _free(t) and t != c:
					_taken[t] = true
					_prop("house", _mid(t, t), 0.0, TENTS[rng.randi() % TENTS.size()])
			_prop("woodpile", _mid(c, c))
			_cars(c + o * 5, d, o, 6, 0, 2, rng)
			_poi("hideout", _mid(c + o * 2, c + o * 2), rng.randi_range(2, 4))
			if rng.randf() < 0.6:
				_poi("crate", _mid(c - d * 4 - o * 2, c - d * 4 - o * 2))
			_street(c + d * 8, d, 12, T.DIRT_ROAD)
			_out.ports = [c + d * 19]
		"quarry":
			for x in range(-14, 15):
				for y in range(-11, 12):
					var k := Vector2(x / 13.0, y / 10.0).length()
					var cell := c + Vector2i(x, y)
					if k > 1.15 or _tile(cell) == T.WATER:
						continue
					var rim := k > 0.72 or (k > 0.45 and k < 0.52) # terraces
					_put(cell, T.SAND if k > 1.0 else (T.ROCK if rim else (T.CRATER if hash(cell) % 9 == 0 else T.SAND)))
			_street(c, d, 26, T.DIRT_ROAD) # the ramp down
			_clear(c + d * 18 - o * 8, 5, 4, g)
			_area(c, d, o, 15, 21, -11, -6, T.ASPHALT)
			_area(c, d, o, 17, 20, -11, -9, T.WAREHOUSE, dash)
			_area(c, d, o, 15, 15, -7, -7, T.PAD)
			_prop("fuel_tank", _mid(c + d * 15 - o * 7, c + d * 15 - o * 7))
			_cars(c + d * 18 - o * 6, d, o, 2, 0, 2, rng, CARS[4])
			_poi("scrapyard", _mid(c + d * 18 - o * 7, c + d * 18 - o * 7))
			if rng.randf() < 0.5:
				_poi("crate", _mid(c + d * 4, c + d * 4))
			_out.ports = [c + d * 25]
		"airfield":
			_clear(c, 36, 14, g)
			_area(c, d, o, -30, 30, -1, 1, T.ASPHALT)
			_area(c, d, o, -28, 28, 0, 0, T.ROAD, dash) # centre line
			_area(c, d, o, -6, 6, 2, 9, T.ASPHALT)
			_area(c, d, o, -4, 4, 10, 13, T.WAREHOUSE, dash) # hangar
			for k in 2:
				_area(c, d, o, 8 + k, 8 + k, 6, 6, T.PAD)
				_prop("fuel_tank", _mid(c + d * (8 + k) + o * 6, c + d * (8 + k) + o * 6))
			_cars(c + o * 5, d, o, 5, 2, rng.randi_range(0, 2), rng)
			_poi("wreck", _mid(c - d * 12 + o * 5, c - d * 12 + o * 5)) # a downed helicopter by the apron
			_poi("fuel_station", _mid(c + d * 3 + o * 5, c + d * 3 + o * 5))
			if rng.randf() < 0.6:
				_poi("crate", _mid(c - d * 3 + o * 7, c - d * 3 + o * 7))
			_street(c - d * 7 + o * 3, o, 22, T.DIRT_ROAD)
			_out.ports = [c - d * 7 + o * 24]
		"radio_mast":
			_clear(c, 9, 9, g)
			_area(c, d, o, -3, 3, -3, 3, T.ASPHALT)
			for i in range(-3, 4):
				for e: int in [-4, 4]:
					_prop("fence", (Vector2(c + Vector2i(i, e)) + Vector2(0.5, 0.5)) * TILE)
					if e < 0 or i != 0: # the gate
						_prop("fence", (Vector2(c + Vector2i(e, i)) + Vector2(0.5, 0.5)) * TILE, PI / 2)
			_block(c + d * 2 + o * 2, c + d * 3 + o * 3, 4)
			_poi("radio_tower", _mid(c - d - o, c - d - o))
			_street(c + d * 4, d, 14, T.DIRT_ROAD)
			_out.ports = [c + d * 17]
		"dam":
			var a: Vector2i = s.dam[0]
			var b: Vector2i = s.dam[1]
			var ax: Vector2i = s.dam[2]
			var n := Vector2i(ax.y, ax.x)
			var up := n if _terrain(c + n * 3) & 0xff == T.WATER else -n # the reservoir side
			var ph := b + ax * 4 - up * 5
			_clear(ph, 5, 5, g)
			for x in range(-3, 4):
				for y in range(-2, 3):
					_put(ph + Vector2i(x, y), T.ASPHALT)
			_block(ph - Vector2i(2, 2), ph + Vector2i(1, 0), 4) # power house
			for k in range(-6, int((b - a).length()) + 7): # the crest road last, so nothing paints over it
				var cell := a + ax * k
				_put(cell, T.ROAD, ACROSS if ax.x != 0 else 0)
				_put(cell + up, T.PAD)
				if _terrain(cell - up) & 0xff == T.WATER:
					_put(cell - up, T.PAD)
					_put(cell - up * 2, T.SAND if k % 3 else T.ROCK) # dry spillway bed below
			_poi("scrapyard", _mid(ph + Vector2i(2, 2), ph + Vector2i(2, 2)))
			if rng.randf() < 0.5:
				_poi("crate", _mid(a - ax * 4 - up * 2, a - ax * 4 - up * 2))
			_out.ports = [a - ax * 6, b + ax * 6]
		"airliner":
			for u in range(-26, 27): # the scorched slide
				for v in range(-4, 5):
					var cell := c + d * u + o * v
					var j := hash(cell)
					if _tile(cell) != T.WATER and j % 10 < 8 - absi(v):
						_put(cell, T.CRATER if j % 17 == 0 else T.ASH)
			_area(c, d, o, -10, -4, 0, 1, T.RUIN) # fuselage, broken in two
			_area(c, d, o, -2, 7, 0, 1, T.RUIN)
			_area(c, d, o, 1, 3, -8, 9, T.RUIN) # wings
			_area(c, d, o, -18, -15, 0, 1, T.RUIN) # tail
			_area(c, d, o, -18, -17, -3, 4, T.RUIN)
			for v: int in [-5, 6]:
				_prop("fuel_tank", _mid(c + d * 2 + o * v, c + d * 2 + o * v), 0.0, BURNT) # engines
			_cars(c, d, o, 22, 4, 5, rng, BURNT) # debris
			_poi("wreck", _mid(c + d * 9 + o * 3, c + d * 9 + o * 3))
			_poi("wreck", _mid(c - d * 14 - o * 3, c - d * 14 - o * 3))
			_poi("crate", _mid(c + d * 5 - o * 4, c + d * 5 - o * 4))
			_poi("crate", _mid(c - d * 21 + o * 2, c - d * 21 + o * 2))
			_poi("scrapyard", _mid(c - d * 6 + o * 4, c - d * 6 + o * 4))
			_street(c + d * 12 + o * 4, o, 14, T.DIRT_ROAD)
			_out.ports = [c + d * 12 + o * 17]
		"prison":
			_clear(c, 17, 14, g)
			_area(c, d, o, -12, 12, -9, 9, T.PAD) # walls
			_area(c, d, o, -11, 11, -8, 8, T.ASPHALT)
			_area(c, d, o, -9, -2, -6, -4, T.WAREHOUSE, dash) # cell blocks
			_area(c, d, o, 2, 9, -6, -4, T.WAREHOUSE, dash)
			_area(c, d, o, -4, 4, 4, 6, T.BUILDING, ROOF_ALT + 4)
			for e: Vector2i in [Vector2i(-12, -9), Vector2i(12, -9), Vector2i(-12, 9), Vector2i(12, 9)]:
				_prop("water_tower", _mid(c + d * e.x + o * e.y, c + d * e.x + o * e.y), 0.0, ROOFS[4]) # guard towers
			_street(c + o * 9, o, 13, T.ROAD) # through the gate
			_poi("survivors", _mid(c + o, c + o), rng.randi_range(4, 7))
			_poi("upgrade", _mid(c + d * 7 + o * 2, c + d * 7 + o * 2))
			_town(_mid(c, c))
			_out.ports = [c + o * 21]
		"motel":
			_clear(c, 14, 10, g)
			_street(c - d * 16, d, 33, T.ROAD)
			_area(c, d, o, -9, 9, 1, 1, T.ASPHALT)
			for u in range(-9, 10):
				_put(c + d * u + o * 2, T.PARKING, _bay_alt(-o))
			_area(c, d, o, -9, 9, 3, 4, T.BUILDING, ROOF_ALT + 1) # the rooms
			_area(c, d, o, 7, 9, 5, 8, T.BUILDING, ROOF_ALT + 1)
			_cars(c + o * 2, d, o, 8, 0, rng.randi_range(2, 4), rng)
			if rng.randf() < 0.4:
				_area(c, d, o, -13, -12, -2, -2, T.PAD)
				_prop("gas_station", _mid(c - d * 13 - o * 2, c - d * 12 - o * 2), 0.0 if d.x != 0 else PI / 2)
			_poi("hideout", _mid(c + o * 3, c + o * 3), rng.randi_range(1, 3))
			if rng.randf() < 0.5:
				_poi("pharmacy", _mid(c - d * 5 + o * 3, c - d * 5 + o * 3))
			if rng.randf() < 0.5:
				_poi("crate", _mid(c + d * 5 + o, c + d * 5 + o))
			_out.ports = [c - d * 16, c + d * 16]
		"lumber_camp":
			_clear(c, 15, 11, T.GRASS3)
			for _i in 14: # stumps
				var t := c + Vector2i(rng.randi_range(-14, 14), rng.randi_range(-10, 10))
				if _free(t):
					_taken[t] = true
					_prop("dead_tree", _mid(t, t), rng.randf() * TAU, Color(0.8, 0.65, 0.5))
			_area(c, d, o, -6, 6, -4, 4, T.SAND) # sawdust yard
			_struct(c - d - o * 3, Vector2i(2, 2), "barn") # the saw mill
			_block(c + d * 4 + o * 2, c + d * 5 + o * 2, 3)
			_block(c - d * 5 + o * 2, c - d * 4 + o * 2, 3)
			for _i in 6:
				var t := c + d * rng.randi_range(-5, 5) + o * rng.randi_range(-1, 1)
				if _free(t):
					_taken[t] = true
					_prop("woodpile", _mid(t, t), PI / 2 if rng.randf() < 0.5 else 0.0)
			_cars(c + o * 3, d, o, 4, 0, 1, rng, Color(0.7, 0.5, 0.35))
			_poi("hideout", _mid(c + o * 2, c + o * 2), rng.randi_range(1, 3))
			if rng.randf() < 0.5:
				_poi("crate", _mid(c - d * 3 + o, c - d * 3 + o))
			_street(c + d * 7, d, 16, T.DIRT_ROAD)
			_out.ports = [c + d * 22]
		"church_ruin":
			_clear(c, 10, 9, T.GRASS3)
			_struct(c - Vector2i(1, 1), Vector2i(2, 3), "church", 0.0, BURNT)
			for _i in 14: # fallen walls
				var t := c + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
				if _free(t):
					_put(t, T.RUIN)
			for i in 8: # the graveyard
				var t := c + d * (4 + i % 4) + o * (3 + i / 4 * 2)
				if _free(t):
					_prop("fence", _mid(t, t), PI / 2, Color(0.7, 0.7, 0.72))
			for _i in 4:
				var t := c + Vector2i(rng.randi_range(-8, 8), rng.randi_range(-8, 8))
				if _free(t):
					_taken[t] = true
					_prop("dead_tree", _mid(t, t), rng.randf() * TAU)
			_poi("nest" if far and rng.randf() < 0.5 else "crate", _mid(c - d * 5 - o * 4, c - d * 5 - o * 4))
			_street(c + d * 5, d, 13, T.DIRT_ROAD)
			_out.ports = [c + d * 17]
		"highway":
			var L := 40
			for u in range(-L, L + 1):
				for v in range(-2, 4):
					var cell := c + d * u + o * v
					if v == 0 or v == 1:
						_put(cell, T.BRIDGE if _terrain(cell) & 0xff == T.WATER else T.ROAD, dash)
					elif _tile(cell) != T.WATER and not _tile(cell) in [T.FOREST, T.ROCK]:
						_put(cell, T.GRASS3)
			_cars(c, d, o, L - 4, 1, rng.randi_range(10, 16), rng, BURNT, true)
			_cars(c, d, o, L - 4, 1, rng.randi_range(2, 4), rng, Color.WHITE, true)
			_poi("scrapyard", _mid(c + o * 3, c + o * 3))
			var at := c + d * rng.randi_range(-30, 30) - o * 2
			_poi("crate", _mid(at, at))
			_out.ports = [c - d * L, c + d * L]


## Paints c + d * u + o * v for u in u0..u1 and v in v0..v1 (inclusive) with t, except over water.
func _area(c: Vector2i, d: Vector2i, o: Vector2i, u0: int, u1: int, v0: int, v1: int, t: int, alt := 0) -> void:
	for u in range(u0, u1 + 1):
		for v in range(v0, v1 + 1):
			if _tile(c + d * u + o * v) != T.WATER:
				_put(c + d * u + o * v, t, alt)


## Open ground in an rx x ry oval round c (woods, crops and rock cleared, water and reeds kept): room for a landmark.
func _clear(c: Vector2i, rx: int, ry: int, t: int) -> void:
	for x in range(-rx, rx + 1):
		for y in range(-ry, ry + 1):
			if Vector2(float(x) / rx, float(y) / ry).length() <= 1.0 and not _tile(c + Vector2i(x, y)) in [T.WATER, T.MARSH]:
				_put(c + Vector2i(x, y), t)


## A flat-roofed building over the cell rectangle a..b with roof tint ROOFS[roof] (house prop on 1x1, 2x1, 2x2).
func _block(a: Vector2i, b: Vector2i, roof: int) -> void:
	var tl := a.min(b)
	var sz := (a - b).abs() + Vector2i.ONE
	for x in sz.x:
		for y in sz.y:
			_put(tl + Vector2i(x, y), T.BUILDING, ROOF_ALT + roof)
			_taken[tl + Vector2i(x, y)] = true
	if sz.x <= 2 and sz.y <= 2:
		var name := "house" if sz == Vector2i.ONE else ("house_2x2" if sz.x == sz.y else "house_2x1")
		_prop(name, _mid(tl, tl + sz - Vector2i.ONE), PI / 2 if sz.y > sz.x else 0.0, ROOFS[roof])


## n cars (tint, else random colours) scattered along d within +-ru, +-rv cells of c, on dry ground; `lanes`: facing d.
func _cars(c: Vector2i, d: Vector2i, o: Vector2i, ru: int, rv: int, n: int, rng: RandomNumberGenerator, tint := Color.WHITE, lanes := false) -> void:
	for _i in n:
		var cell := c + d * rng.randi_range(-ru, ru) + o * rng.randi_range(-rv, rv)
		if _tile(cell) == T.WATER or _taken.has(cell):
			continue
		_taken[cell] = true
		var rot := Vector2(d).angle() + (0.0 if lanes else rng.randf_range(-0.6, 0.6)) + (PI if rng.randf() < 0.5 else 0.0)
		_prop("car", _mid(cell, cell), rot, tint if tint != Color.WHITE else CARS[rng.randi() % CARS.size()])
