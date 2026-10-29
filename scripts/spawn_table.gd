class_name SpawnTable
## The one place for enemy types and how often they spawn. spawner.gd asks it for a kind (`pick`) or a whole horde
## (`horde`); later packages add rows here (assault themes, bandits) instead of touching the spawner.
## weight = base + per_danger * danger, times `town` when the spawn is next to a settlement and times the entry of the
## region (chunk_manager R: farm, forest, lake, suburb, waste); a row is off before `min_day`.

const R := preload("res://scripts/chunk_manager.gd").R
const ROWS := {
	"shambler": {"base": 70.0},
	"runner": {"base": 10.0, "per_danger": 5.0},
	"brute": {"base": 3.0, "per_danger": 3.0},
	"screamer": {"base": 1.5, "per_danger": 0.8, "min_day": 3},
	"spitter": {"base": 2.5, "per_danger": 1.0, "min_day": 4},
	"crawler": {"base": 5.0, "per_danger": 1.0, "min_day": 2, "region": {R.FOREST: 3.0, R.LAKE: 2.5, R.WASTE: 1.5}},
	"bloater": {"base": 1.5, "per_danger": 0.8, "min_day": 5, "town": 2.5, "region": {R.SUBURB: 2.0}},
	"brute_armored": {"base": 0.0, "per_danger": 2.0, "min_day": 10},
}
const PACK_DAY := 10 # from this day a horde may be a runner pack
const PACK_CHANCE := 0.25
const PACK_SIZE := Vector2i(5, 8)


## One weighted kind. ctx: {"region": R, "town": bool, "day": int}; missing keys count as farmland, open country, today.
static func pick(danger: float, ctx := {}) -> String:
	var day: int = ctx.get("day", Game.day)
	var weights := {}
	var total := 0.0
	for kind in ROWS:
		var row: Dictionary = ROWS[kind]
		if day < row.get("min_day", 1):
			continue
		var w: float = row["base"] + row.get("per_danger", 0.0) * danger
		w *= row.get("region", {}).get(ctx.get("region", R.FARM), 1.0) * (row.get("town", 1.0) if ctx.get("town", false) else 1.0)
		weights[kind] = w
		total += w
	var r := randf() * total
	for kind in weights:
		r -= weights[kind]
		if r <= 0.0:
			return kind
	return "shambler"


## Kinds of one horde: 6-12 picks, or from PACK_DAY on sometimes a pack of runners.
static func horde(danger: float, ctx := {}) -> Array[String]:
	var out: Array[String] = []
	if ctx.get("day", Game.day) >= PACK_DAY and randf() < PACK_CHANCE:
		out.resize(randi_range(PACK_SIZE.x, PACK_SIZE.y))
		out.fill("runner")
		return out
	for i in randi_range(6, 12):
		out.append(pick(danger, ctx))
	return out


## ctx for a spawn at `pos` (region of the cell, `town` if it is next to a settlement).
static func context(pos: Vector2, town := false) -> Dictionary:
	return {"region": Game.world.chunks.region(Vector2i((pos / 16.0).floor())), "town": town, "day": Game.day}
