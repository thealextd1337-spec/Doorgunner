extends Bandit
## Bandit technical (docs/ROADMAP.md P11): a pickup with an MG that drives the road network of the world generator
## cell by cell over any road tile (bridges, lanes, asphalt): straight on where it can, a random turn at junctions
## (TURN_CHANCE), back towards its camp once farther than LEASH, turning round at dead ends and at the edge of the
## loaded world. Shoots like the other bandits (bandit.gd KINDS["technical"]: the AA gun reaches the heli at 340 px).

const LEASH := 1400.0
const TURN_CHANCE := 0.35
const ROADS := preload("res://scripts/chunk_manager.gd").ROADS
const DIRS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var heading := Vector2i.RIGHT
var next_cell := Vector2i.ZERO


func _ready() -> void:
	super()
	next_cell = Vector2i((position / 16.0).floor())
	for d in DIRS:
		if _road(next_cell + d):
			heading = d


## The road cell nearest to `pos` within `reach` cells (loaded tiles only), or null.
static func road_near(pos: Vector2, reach: int) -> Variant:
	var c0 := Vector2i((pos / 16.0).floor())
	for r in reach + 1:
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				if maxi(absi(x), absi(y)) == r and _road(c0 + Vector2i(x, y)):
					return c0 + Vector2i(x, y)
	return null


static func _road(c: Vector2i) -> bool:
	return Game.world.chunks.get_cell_atlas_coords(c).x in ROADS


func _move(delta: float) -> void:
	var to := Vector2(next_cell) * 16.0 + Vector2(8, 8)
	var step := to - position
	if step.length() <= speed * delta:
		position = to
		next_cell = _next(next_cell)
	else:
		position += step.normalized() * speed * delta
		sprite.rotation = lerp_angle(sprite.rotation, step.angle() + PI / 2, 0.25)
	if target != null and is_instance_valid(target):
		queue_redraw()


## The cell after `c`: straight on, sometimes a side road, homewards when off the leash; back where it came from at a dead end.
func _next(c: Vector2i) -> Vector2i:
	var ways := DIRS.filter(func(d): return d != -heading and _road(c + d))
	if ways.is_empty():
		if not _road(c - heading):
			return c # stranded (the road got unloaded): wait
		heading = -heading
		return c + heading
	var pick: Vector2i = heading if heading in ways else ways.pick_random()
	if global_position.distance_to(home) > LEASH:
		ways.sort_custom(func(a, b): return Vector2(c + a).distance_squared_to(home / 16.0) < Vector2(c + b).distance_squared_to(home / 16.0))
		pick = ways[0]
	elif ways.size() > 1 and randf() < TURN_CHANCE:
		pick = ways.pick_random()
	heading = pick
	return c + heading
