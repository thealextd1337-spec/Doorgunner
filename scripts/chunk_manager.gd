extends TileMapLayer
## Endless procedural terrain in 32x32-tile chunks. Towns, lone houses and POIs are seeded per chunk.
## Terrain is a pure function of Game.seed: a large cellular region noise picks farmland, forest hills, lakeland,
## suburbs or burned wasteland, and each region bends the height, moisture and river layers its own way.
## Towns (one of seven templates per region), farmsteads, cabins, huts and roads are painted on top, with
## decorative props (church, barns, silos, trees, jetties, cars...) from Game.world.spawn_prop.
## Paint that lands in a chunk not loaded yet waits in `_pending` until that chunk loads.

const CHUNK := 32
const TILE := 16
const LOAD_RADIUS := 2
const ROAD_REACH := 3000.0 # world px; towns link to known towns / the base within this distance
enum T { GRASS, FOREST, WATER, SAND, ROAD, BUILDING, RUIN, BASE_FLOOR, GRASS2, GRASS3, FIELD, DIRT_ROAD, ROCK, TREE_EDGE,
	HOUSE_YARD, ASPHALT, HEDGE, MARSH, WAREHOUSE, ASH, CRATER, PARKING, PLAZA, PAD }
enum R { FARM, FOREST, LAKE, SUBURB, WASTE }
const REGIONS := ["farm", "forest", "lake", "suburb", "waste"]
const TOWN_CHANCE := [0.35, 0.15, 0.3, 0.55, 0.35] # per chunk, by region
const TOWN_KINDS := [["village", "village", "farm", "farm", "hamlet"], ["hamlet", "hamlet", "hamlet", "village"],
	["fishing", "fishing", "village"], ["suburb", "suburb", "industrial"], ["ruined"]]
const TOWN_SIZE := {"village": Vector2i(3, 7), "hamlet": Vector2i(3, 6), "fishing": Vector2i(3, 6), "farm": Vector2i(4, 8),
	"suburb": Vector2i(8, 14), "industrial": Vector2i(5, 10), "ruined": Vector2i(3, 10)}
# region terrain: water below WATER_H (a shore band above it), forest above FOREST_M moisture, rock above ROCK_H
const WATER_H := [-0.42, -0.4, -0.16, -0.42, -0.4]
const FOREST_M := [0.36, -0.36, 0.12, 0.42, 0.22]
const ROCK_H := [0.55, 0.38, 0.46, 0.6, 0.46]
const GRASSY := [T.GRASS, T.GRASS2, T.GRASS3, T.TREE_EDGE]
const OPEN := [T.GRASS, T.GRASS2, T.GRASS3, T.TREE_EDGE, T.SAND, T.ASH, T.MARSH, T.FIELD] # where wild POIs may sit
const BUILDABLE := [T.GRASS, T.GRASS2, T.GRASS3, T.TREE_EDGE, T.SAND, T.ASH, T.MARSH, T.FIELD, T.HEDGE, T.FOREST, T.CRATER]
const TOWNISH := [T.ROAD, T.BUILDING, T.RUIN, T.BASE_FLOOR, T.HOUSE_YARD, T.ASPHALT, T.WAREHOUSE, T.PARKING, T.PLAZA, T.PAD]
const BLOCKED := [T.WATER, T.FOREST, T.BUILDING, T.ROCK, T.WAREHOUSE, T.HEDGE, T.PAD] # not landable
const ROADS := [T.ROAD, T.DIRT_ROAD, T.ASPHALT]
const BUILT := [T.BUILDING, T.RUIN, T.WAREHOUSE, T.PAD, T.PARKING, T.PLAZA, T.HOUSE_YARD, T.BASE_FLOOR]
const ACROSS := 1 # alternative tile id: transposed (road dashes, wheel tracks, crop rows, yard path, hedge run the other way)
const RIPE := 2 # extra FIELD alternatives (+ACROSS): golden crop
const FLIP := 2 # extra PARKING alternatives (+ACROSS): bays open the other way
const ROOF_ALT := 2 # BUILDING alternatives ROOF_ALT + i are tinted with ROOFS[i]
const ROOFS := [Color(1, 1, 1), Color(1.0, 0.62, 0.5), Color(0.74, 0.8, 0.96), Color(0.94, 0.8, 0.6), Color(0.62, 0.62, 0.66), Color(0.82, 0.92, 0.74)]
const CARS := [Color(1, 0.42, 0.36), Color(0.5, 0.62, 1), Color(1, 1, 1), Color(0.38, 0.38, 0.4), Color(0.92, 0.86, 0.5)]
const BURNT := Color(0.32, 0.28, 0.26)
const PROP_TREE := 1 # terrain scatter props, packed into _terrain()'s result above bit 16
const PROP_DEAD := 2
const NONE := Vector2i(-99999, -99999)

var noise := FastNoiseLite.new() # height
var moisture := FastNoiseLite.new()
var river := FastNoiseLite.new()
var biome := FastNoiseLite.new() # regions
var loaded := {}
var town_centers := [] # world positions, used by the spawner
var _pending := {} # chunk -> {cell: Vector2i(tile, alt)}
var _ports := [] # [Vector2i end_a, Vector2i end_b] per town plus the base: where roads attach
var _taken := {} # cells under trees and other ground props, so houses keep off them
var _shot_at := OS.get_environment("SHOT_AT") # dev hook for screenshots, see _shot_jump
var _shot_kind := ""


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
	biome.frequency = 0.0015


func _process(_delta: float) -> void:
	if Game.heli == null:
		return
	if _shot_at != "":
		_shot_jump()
	var c := Vector2i((Game.heli.position / (CHUNK * TILE)).floor())
	for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dy in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			_ensure(c + Vector2i(dx, dy))


func tile_at(world_pos: Vector2) -> int:
	var cell := Vector2i((world_pos / TILE).floor())
	var atlas := get_cell_atlas_coords(cell)
	return atlas.x if atlas.x >= 0 else T.GRASS


func is_landable(world_pos: Vector2) -> bool:
	return not tile_at(world_pos) in BLOCKED


## Region of a cell. Borders wander with the height noise and are dithered over ~6 cells by a cell hash.
func region(cell: Vector2i) -> int:
	return _region(cell, noise.get_noise_2d(cell.x, cell.y), hash(cell))


func _region(cell: Vector2i, h: float, j: int) -> int:
	var x := cell.x + h * 80.0 + float(j % 7 - 3)
	var y := cell.y - h * 80.0 + float((j >> 3) % 7 - 3)
	var r := mini(int((biome.get_noise_2d(x, y) + 1.0) * 2.5), R.WASTE)
	if r == R.WASTE and Vector2(x - 16, y - 16).length() < 3.5 * CHUNK:
		return R.FARM # the burned lands start a few chunks out
	return r


func _has_town(c: Vector2i, reg: int) -> bool:
	return c != Vector2i.ZERO and hash([Game.seed, c.x, c.y, 1]) % 1000 < TOWN_CHANCE[reg] * 1000


func _ensure(c: Vector2i) -> void:
	if loaded.has(c):
		return
	loaded[c] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed, c.x, c.y])
	var origin := c * CHUNK
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
	for y in range(1, n - 1):
		for x in range(1, n - 1):
			var i := y * n + x
			var t := grid[i] & 0xff
			if t == T.FOREST and (grid[i - 1] != T.FOREST or grid[i + 1] != T.FOREST or grid[i - n] != T.FOREST or grid[i + n] != T.FOREST):
				t = T.TREE_EDGE
			var cell := origin + Vector2i(x - 1, y - 1)
			set_cell(cell, 0, Vector2i(t, 0), (grid[i] >> 8) & 0xff)
			if grid[i] >= 65536 and not pend.has(cell):
				var j := hash(cell)
				var at := Vector2(cell * TILE) + Vector2(5 + j % 7, 5 + (j >> 4) % 7)
				_prop("tree" if grid[i] >> 16 == PROP_TREE else "dead_tree", at, 0.0 if grid[i] >> 16 == PROP_TREE else j % 628 * 0.01)
				_taken[cell] = true
	for cell in pend:
		set_cell(cell, 0, Vector2i(pend[cell].x, 0), pend[cell].y)
	_pending.erase(c)
	if c == Vector2i.ZERO:
		_paint_base(origin)
		return
	var dist := Vector2(c).length()
	var reg := region(origin + Vector2i(CHUNK / 2, CHUNK / 2))
	if _has_town(c, reg) and _paint_town(origin, rng, dist, reg):
		if rng.randf() < 0.3:
			_lone_houses(origin, rng, reg, 1)
	else:
		_place_wild_poi(origin, rng, dist, reg, _lone_houses(origin, rng, reg, rng.randi_range(1, 2)))


## Tile id, plus alternative << 8 and a scatter prop << 16.
func _terrain(cell: Vector2i) -> int:
	var h := noise.get_noise_2d(cell.x, cell.y)
	var j := hash(cell)
	var reg := _region(cell, h, j)
	var wh: float = WATER_H[reg]
	if h < wh:
		return T.WATER
	if h < wh + (0.09 if reg == R.LAKE else 0.06):
		if reg == R.LAKE: # reed beds at the water's edge, then a sand beach
			return T.MARSH if h < wh + 0.04 + float(j % 10) * 0.003 else T.SAND
		return T.ASH if reg == R.WASTE else T.SAND
	var r := absf(river.get_noise_2d(cell.x, cell.y))
	if r < 0.016:
		return T.WATER
	if r < 0.028:
		return T.ROCK if h > 0.25 else [T.SAND, T.SAND, T.MARSH, T.SAND, T.ASH][reg]
	if h > ROCK_H[reg]:
		return T.ROCK
	var m := moisture.get_noise_2d(cell.x, cell.y) + h * 0.5
	if reg == R.FOREST and (posmod(cell.x + 7 * floori(cell.y / 64.0), 53) == 0 or posmod(cell.y, 61) == 0):
		return T.DIRT_ROAD | (ACROSS << 8 if posmod(cell.y, 61) == 0 else 0) # logging tracks through the woods
	if reg == R.LAKE and m > 0.25: # wet hollows hold more lakes, ringed with reeds
		return T.WATER if m > 0.3 else T.MARSH
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
	if k > 0.12:
		return T.GRASS2
	if k < -0.2:
		return T.GRASS3
	return T.GRASS | (PROP_TREE << 16 if j % 211 == 0 and reg != R.SUBURB else 0)


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


## Tile already painted (loaded or pending), or -1 if the cell still has its bare terrain.
func _painted(cell: Vector2i) -> int:
	var c := Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
	if loaded.has(c):
		return get_cell_atlas_coords(cell).x
	if _pending.has(c) and _pending[c].has(cell):
		return _pending[c][cell].x
	return -1


## Current tile of any cell: loaded, waiting in _pending, or the bare terrain it will get.
func _tile(cell: Vector2i) -> int:
	var t := _painted(cell)
	return t if t >= 0 else _terrain(cell) & 0xff


func _put(cell: Vector2i, t: int, alt := 0) -> void:
	if absi(cell.x - 16) <= 6 and absi(cell.y - 16) <= 6:
		return # never paint over the base floor
	var c := Vector2i(floori(cell.x / float(CHUNK)), floori(cell.y / float(CHUNK)))
	if loaded.has(c):
		set_cell(cell, 0, Vector2i(t, 0), alt)
	else:
		if not _pending.has(c):
			_pending[c] = {}
		_pending[c][cell] = Vector2i(t, alt)


## Open ground a house or structure may take: not water, road, town or a prop, and clear of the base.
func _free(cell: Vector2i) -> bool:
	return (absi(cell.x - 16) > 9 or absi(cell.y - 16) > 9) and not _taken.has(cell) and _tile(cell) in BUILDABLE


func _prop(name: String, pos: Vector2, rot := 0.0, tint := Color.WHITE) -> void:
	Game.world.spawn_prop(name, pos, rot).modulate = tint


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
	_prop(name, _mid(tl, tl + sz - Vector2i.ONE), rot, tint)
	return true


## Tries random spots around `near` until the structure fits.
func _struct_near(near: Vector2i, rad: int, sz: Vector2i, name: String, rng: RandomNumberGenerator, rot := 0.0) -> bool:
	for _i in 8:
		if _struct(near + Vector2i(rng.randi_range(-rad, rad), rng.randi_range(-rad, rad)), sz, name, rot):
			return true
	return false


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


# ---------------------------------------------------------------- towns

## Paints a town; false (nothing painted) if the chunk has no dry ground for its centre.
func _paint_town(origin: Vector2i, rng: RandomNumberGenerator, dist: float, reg: int) -> bool:
	var kinds: Array = TOWN_KINDS[reg]
	var kind: String = kinds[rng.randi() % kinds.size()] if _shot_kind == "" else _shot_kind
	var size := rng.randi_range(TOWN_SIZE[kind].x, TOWN_SIZE[kind].y)
	var center := origin + Vector2i(rng.randi_range(8, CHUNK - 8), rng.randi_range(8, CHUNK - 8))
	var dry := false
	for i in 12: # dry ground for the centre, by the water for fishing villages if possible
		dry = not _tile(center) in [T.WATER, T.SAND, T.MARSH, T.ROCK]
		if dry and (kind != "fishing" or i >= 8 or _water_dir(center, 9) != Vector2i.ZERO):
			break
		center = origin + Vector2i(rng.randi_range(8, CHUNK - 8), rng.randi_range(8, CHUNK - 8))
	if not dry:
		return false
	for tc: Vector2 in town_centers: # shrink to keep clear of the neighbours
		size = mini(size, int(tc.distance_to(_mid(center, center)) / TILE / 2.5) - 4)
	size = maxi(size, 3)
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
	if kind == "fishing":
		_jetties(center, size * 2 + 6, rng, rng.randi_range(2, 4))
	if kind == "ruined":
		_scorch(center, size + 8, rng)
	_link([ends[0], ends[1]], along, rng)
	_ports.append([ends[0], ends[1]])
	var world_center := _mid(ends[2], ends[2])
	town_centers.append(world_center)
	Game.world.spawn_poi("survivors", world_center, rng)
	for p: Array in [["water_tower", 0.5, ROADS], ["pharmacy", 0.35, [T.BUILDING]]]: # on a road / a house roof
		if rng.randf() < p[1]:
			var at := _find(ends[2], size * 2, p[2], rng)
			if at != NONE:
				Game.world.spawn_poi(p[0], _mid(at, at), rng)
	if rng.randf() < 0.5:
		var off := Vector2(rng.randf_range(-size, size), rng.randf_range(-size, size)) * TILE * 2
		Game.world.spawn_poi("crate", world_center + off, rng)
	# dens sit well outside town (the boss wakes at 420 px), and rarely unless the town is ruined
	if rng.randf() < (0.5 if kind == "ruined" else 0.12) and world_center.distance_to(Game.world.BASE_POS) > 1100.0:
		for _i in 6: # on dry land
			var at := world_center + Vector2((size + 34) * TILE, 0).rotated(rng.randf() * TAU)
			if _tile(Vector2i((at / TILE).floor())) in OPEN:
				Game.world.spawn_poi("nest", at, rng)
				break
	return true


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
			var run := 1
			for dir in [d, -d]:
				var p: Vector2i = c + dir
				while run <= 5 and _tile(p) == T.WATER:
					run += 1
					p += dir
			if run > 5:
				continue
		var was := _painted(c)
		if was in BUILT:
			continue # another town got here first: go round its houses
		_put(c, T.ASPHALT if t == T.ROAD and was == T.ROAD else t, ACROSS if d.x != 0 else 0)


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
			if _tile(center + d * u + o * s) != T.WATER:
				_put(center + d * u + o * s, st.road, ACROSS if o.x != 0 else 0)
		pts.append(center + d * u + o * off)
		if _tile(pts.back()) != T.WATER: # a lane, no causeways
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
			_put(cell, T.DIRT_ROAD, ACROSS if along else 0)
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
					Game.world.spawn_poi("hideout", centre, rng)
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
				_driveway(cell - dir, rng)
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
	_driveway(cell + Vector2i(0, 1), rng)
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
		_driveway(cell, rng)
	return c


## Dirt driveway from `from` straight to the nearest painted road within 40 cells, else a lane to a town within 40.
func _driveway(from: Vector2i, rng: RandomNumberGenerator) -> void:
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
	if bd != Vector2i.ZERO:
		for k in range(1, best):
			if _tile(from + bd * k) == T.WATER:
				return
		for k in range(1, best):
			if not _tile(from + bd * k) in TOWNISH:
				_put(from + bd * k, T.DIRT_ROAD, ACROSS if bd.x != 0 else 0)
		return
	for p in _ports:
		for e: Vector2i in p:
			if Vector2(e - from).length() < 40:
				_lane(from, e, rng.randf() < 0.5, rng)
				return


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


## Wild POI with region-flavoured odds: crates near farmsteads and roads, nests in ruins, ash and woods.
func _place_wild_poi(origin: Vector2i, rng: RandomNumberGenerator, dist: float, reg: int, homes: Array) -> void:
	var kinds := ["crate", "radio_tower", "wreck", "upgrade", "nest"]
	var w := [0.18, 0.12, 0.12, 0.13, clampf(dist * 0.06, 0.05, 0.3)]
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
	if kind == "nest" and Vector2(origin * TILE).distance_to(Game.world.BASE_POS) < 1100.0:
		kind = "crate" # no hive queen next door on day 1
	for i in 16:
		var cell := origin + Vector2i(rng.randi_range(4, CHUNK - 4), rng.randi_range(4, CHUNK - 4))
		if kind == "crate" and homes.size() > 0 and i < 8:
			cell = homes[0] + Vector2i(rng.randi_range(-4, 4), rng.randi_range(-4, 4))
		if _tile(cell) in OPEN and (kind == "nest" or _clearing(cell)) and (i >= 12 or _likes(kind, cell)):
			Game.world.spawn_poi(kind, _mid(cell, cell), rng)
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
## A region name ("farm", "forest", "lake", "suburb", "waste") jumps to the nearest town in that region instead,
## 440 px west of it so the scripted eastward flight ends over it; "farm:village" also forces the town template
## (village, hamlet, fishing, farm, suburb, industrial, ruined); a trailing "-" picks a chunk without a town.
func _shot_jump() -> void:
	var p := _shot_at.split(",")
	var want := REGIONS.find(_shot_at.get_slice(":", 0).trim_suffix("-"))
	var town := not _shot_at.ends_with("-")
	_shot_kind = _shot_at.get_slice(":", 1) if ":" in _shot_at else ""
	_shot_at = ""
	if p.size() == 2:
		Game.heli.position = Vector2(float(p[0]), float(p[1]))
		Game.max_hp = 1e9; Game.hp = 1e9 # screenshots only: the heli must survive wherever it lands
		return
	for r in range(3, 60):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				var c := Vector2i(x, y)
				var reg := region(c * CHUNK + Vector2i(CHUNK / 2, CHUNK / 2))
				if maxi(absi(x), absi(y)) == r and reg == want and _has_town(c, reg) == town and not loaded.has(c):
					var towns := town_centers.size()
					_ensure(c)
					if town and town_centers.size() == towns:
						continue # the town found no dry ground
					_shot_kind = ""
					Game.heli.position = (town_centers.back() if town else Vector2(c * CHUNK * TILE) + Vector2(256, 256)) - Vector2(440, 0)
					Game.max_hp = 1e9; Game.hp = 1e9
					return
