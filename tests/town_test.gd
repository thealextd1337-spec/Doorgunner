extends Node
## Headless world-gen test. main.gd adds this node when env SMOKE=town:
##   SMOKE=town godot --headless --path . --quit-after 30000
## A city gets generated (with bend tiles on its corners), and new towns reach earlier ones by road.

const CM := preload("res://scripts/chunk_manager.gd")
const T := CM.T


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var ch: TileMapLayer = Game.world.chunks
	await get_tree().process_frame
	await get_tree().process_frame
	# the nearest city chunk by the generator's own rule
	var t0 := 0
	var city := []
	var at := Vector2i.ZERO
	for r in range(3, 60):
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				var c := Vector2i(x, y)
				var reg: int = ch.region(c * CM.CHUNK + Vector2i(CM.CHUNK / 2, CM.CHUNK / 2))
				if ch._cities.is_empty() and maxi(absi(x), absi(y)) == r and ch._has_town(c, reg) and ch.city_chunk(c, reg):
					t0 = Time.get_ticks_usec()
					ch._ensure(c)
					print("city chunk %s in %.1f ms" % [c, (Time.get_ticks_usec() - t0) / 1000.0])
					city = ch._ports.back()
					at = c
	# then towns around the start and the city, timed against it
	t0 = Time.get_ticks_usec()
	var n := 0
	for o: Vector2i in [Vector2i.ZERO, at]:
		for x in range(-4, 5):
			for y in range(-4, 5):
				if not ch.loaded.has(o + Vector2i(x, y)):
					ch._ensure(o + Vector2i(x, y))
					n += 1
	print("%d chunks in %.1f ms each" % [n, (Time.get_ticks_usec() - t0) / 1000.0 / n])
	assert(not ch._cities.is_empty(), "a city got generated")
	var grid: Rect2i = ch._cities[0]
	var corners := [grid.position, Vector2i(grid.end.x - 1, grid.position.y), Vector2i(grid.position.x, grid.end.y - 1), grid.end - Vector2i.ONE]
	assert(corners.any(func(c: Vector2i) -> bool: return ch._tile(c) == T.ROAD_BEND), "city corners are bends (unless a lane joins there)")
	var edge := [] # side streets meeting the four edges (a river may cut one or two of them)
	for i in range(1, grid.size.x / CM.BLOCK):
		edge.append_array([grid.position + Vector2i(i * CM.BLOCK, 0), Vector2i(grid.position.x + i * CM.BLOCK, grid.end.y - 1)])
	for i in range(1, grid.size.y / CM.BLOCK):
		edge.append_array([grid.position + Vector2i(0, i * CM.BLOCK), Vector2i(grid.end.x - 1, grid.position.y + i * CM.BLOCK)])
	assert(edge.any(func(c: Vector2i) -> bool: return ch._tile(c) == T.ASPHALT), "T junctions on the city edge")
	assert(city.size() == 4, "city has four street ends")
	var bends := 0
	for x in range(-64, 64):
		for y in range(-64, 64):
			bends += int(ch._tile(Vector2i(x, y)) == T.DIRT_BEND)
	print("dirt bends around the start: %d" % bends)
	assert(bends > 0, "lanes and hamlet roads bend")
	# every town that found a neighbour in reach is joined to an earlier town by road
	var joined := 0
	var linkable := 0
	for i in range(1, ch._ports.size()):
		var earlier: Array = ch._ports.slice(0, i)
		if _nearest(ch._ports[i], earlier) * CM.TILE >= CM.ROAD_REACH:
			continue
		linkable += 1
		joined += int(_joined(ch, ch._ports[i], earlier))
	print("towns joined by road: %d / %d" % [joined, linkable])
	assert(linkable > 3 and joined >= linkable * 0.8, "towns joined by road") # lake seeds leave a few towns past 5-cell fords
	var others: Array = ch._ports.filter(func(p: Array) -> bool: return p != city)
	assert(_joined(ch, city, others), "city joined by road to its neighbours")
	print("TOWN OK")
	get_tree().quit(0)


func _nearest(ends: Array, ports: Array) -> float:
	var best := INF
	for p: Array in ports:
		for a: Vector2i in ends:
			for b: Vector2i in p:
				best = minf(best, Vector2(a - b).length())
	return best


## Breadth-first search over road, plaza and car park cells from `ends` to any end in `ports`.
func _joined(ch: TileMapLayer, ends: Array, ports: Array) -> bool:
	var goal := {}
	for p: Array in ports:
		for b: Vector2i in p:
			goal[b] = true
	var drive: Array = CM.ROADS + [T.PLAZA, T.PARKING]
	var seen := {}
	var q := ends.duplicate()
	for e: Vector2i in q:
		seen[e] = true
	var i := 0
	while i < q.size() and i < 12000:
		var c: Vector2i = q[i]
		i += 1
		if goal.has(c):
			return true
		for dir: Vector2i in CM.DIRS:
			if not seen.has(c + dir) and (goal.has(c + dir) or ch._tile(c + dir) in drive):
				seen[c + dir] = true
				q.append(c + dir)
	return false

