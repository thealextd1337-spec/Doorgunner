extends TileMapLayer
## Endless procedural terrain in 32x32-tile chunks. Towns and POIs are seeded per chunk.

const CHUNK := 32
const TILE := 16
const LOAD_RADIUS := 2
enum T { GRASS, FOREST, WATER, SAND, ROAD, BUILDING, RUIN, BASE_FLOOR }

var noise := FastNoiseLite.new()
var loaded := {}
var town_centers := [] # world positions, used by the spawner


func _ready() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	var src := TileSetAtlasSource.new()
	src.texture = load("res://assets/sprites/tiles.png")
	src.texture_region_size = Vector2i(TILE, TILE)
	for i in 8:
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	tile_set = ts
	noise.seed = Game.seed
	noise.frequency = 0.012
	noise.fractal_octaves = 3


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
	return t != T.WATER and t != T.FOREST and t != T.BUILDING


func _ensure(c: Vector2i) -> void:
	if loaded.has(c):
		return
	loaded[c] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed, c.x, c.y])
	var origin := c * CHUNK
	for x in CHUNK:
		for y in CHUNK:
			var cell := origin + Vector2i(x, y)
			set_cell(cell, 0, Vector2i(_terrain(cell), 0))
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
	if h < -0.28:
		return T.WATER
	if h < -0.2:
		return T.SAND
	if h > 0.3:
		return T.FOREST
	return T.GRASS


func _paint_base(origin: Vector2i) -> void:
	var center := origin + Vector2i(CHUNK / 2, CHUNK / 2)
	for x in range(-10, 11):
		for y in range(-10, 11):
			var cell := center + Vector2i(x, y)
			if abs(x) <= 6 and abs(y) <= 6:
				set_cell(cell, 0, Vector2i(T.BASE_FLOOR, 0))
			elif get_cell_atlas_coords(cell).x != T.GRASS:
				set_cell(cell, 0, Vector2i(T.GRASS, 0))


func _paint_town(origin: Vector2i, rng: RandomNumberGenerator, dist: float) -> void:
	var size := rng.randi_range(3, 6)
	var center := origin + Vector2i(rng.randi_range(8, CHUNK - 8), rng.randi_range(8, CHUNK - 8))
	var ruin_chance := clampf(dist * 0.12, 0.1, 0.8)
	for x in range(-size, size + 1):
		for y in range(-size, size + 1):
			var cell := center + Vector2i(x, y)
			var t: int
			if x % 3 == 0 or y % 3 == 0:
				t = T.ROAD
			elif rng.randf() < ruin_chance:
				t = T.RUIN
			else:
				t = T.BUILDING
			set_cell(cell, 0, Vector2i(t, 0))
	var world_center := Vector2(center) * TILE + Vector2(8, 8)
	town_centers.append(world_center)
	Game.world.spawn_poi("survivors", world_center, rng)
	if rng.randf() < 0.5:
		var off := Vector2(rng.randf_range(-size, size), rng.randf_range(-size, size)) * TILE * 2
		Game.world.spawn_poi("crate", world_center + off, rng)
	if rng.randf() < 0.3 and world_center.distance_to(Game.world.BASE_POS) > 1100.0:
		Game.world.spawn_poi("nest", world_center + Vector2((size + 4) * TILE, 0).rotated(rng.randf() * TAU), rng)


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
		if t == T.GRASS or t == T.SAND:
			Game.world.spawn_poi(kind, Vector2(cell) * TILE + Vector2(8, 8), rng)
			return
