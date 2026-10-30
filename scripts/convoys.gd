extends Node2D
## Convoys (docs/ROADMAP.md P16). main.gd keeps this node as `convoys`; it saves itself (hook "convoys").
##
## A Motor Pool (Game.BUILDINGS, BUILD tab) lets the base build trucks from salvage (TRUCK_COST; highway scrap yards and
## car wrecks deliver parts) and send them out from the CONVOY tab of the base menu: a destination (a site the heli has
## seen, an allied village or an outpost, within RANGE), a driver (Driver skill, healthy) and up to ESCORTS_MAX escorts
## (militia or soldiers, one base rifle each). Crew members get person["post"] = convoy id: not at the base (no work, no
## food) but still counted by Game.saved_count(). The truck drives out, loots for LOOT_SECONDS, drives back and unloads
## (LOOT, less after each trip to the same site: DEPLETE); villages hand over their stock, outposts their surplus.
##
## Road pathing (road_path): the sites form a graph (each links to its two nearest, chunk_manager._knn); Dijkstra over that
## graph picks the sites on the way, chunk_manager._edge computes (and caches) the roads between them, and an AStar2D over
## just those road cells and the streets of the sites on the way gives the cell path. Paths are cached (_paths) and saved
## with the convoy, so a trip never re-paths. Cost: one dispatch to a far site computes its few roads once (the same work
## the world generator does while flying there), the A* itself runs over a few thousand cells.
##
## Off-screen: a convoy is only a distance `d` along its saved path. Within SHOW_DIST of the heli it gets a truck node
## (dropped again beyond HIDE_DIST): real zombies within CONTACT slow it and chew the hull, its escorts shoot real hostiles.
## Far away the same happens abstractly: ZOMBIE_WEAR per second (times the danger there, less per escort).
## Ambushes: at dispatch each leg rolls one bandit ambush at a bridge or a narrow (road between water, rock or woods), likelier
## near a bandit camp (bandits.camps_near). The truck stops, the radio calls "Convoy under attack" with a bearing, the
## ambushers (bandits.spawn_unit, role guard) appear when the heli comes close; far away the escorts fight them abstractly.
## The ambush hits the hull with AMBUSH_DPS per ambusher until they are dead. A destroyed truck loses its cargo and rifles;
## each crew member dies (LOST_DEATH) or walks home injured.

const Chunks := preload("res://scripts/chunk_manager.gd")
const Poi := preload("res://scripts/poi.gd")

const TRUCK_COST := {"metal": 20.0, "parts": 15.0} # salvage
const TRUCKS_PER_POOL := 2 # trucks (at home and on the road) one Motor Pool keeps
const ESCORTS_MAX := 3 # plus the driver: 4 people on a truck
const RANGE := 9000.0 # px from the base a destination may be
const START_REACH := 900.0 # px from the base to the first road cell (the truck rolls there off-road, not shown)
const MIN_DIST := 600.0 # px: closer sites are no convoy destination
const DEST_REACH := 480.0 # px from the destination to the last road cell
const SPEED := 42.0 # px/s on the road (the heli flies 115)
const DRIVER_SPEED := 0.15 # per driver level above 1
const HULL := 100.0
const LOOT_SECONDS := 45.0
const LOOT := { # per trip, by site kind; towns use "town", other landmarks "landmark"
	"town": {"food": 40.0, "water": 20.0, "metal": 15.0, "parts": 10.0, "medicine": 2.0},
	"city": {"food": 70.0, "water": 30.0, "metal": 25.0, "parts": 20.0, "electronics": 10.0, "medicine": 4.0},
	"gas_station": {"fuel": 150.0, "parts": 5.0},
	"checkpoint": {"ammo": 300.0, "rifles": 1.0, "metal": 10.0},
	"airfield": {"fuel": 120.0, "electronics": 10.0, "parts": 10.0},
	"highway": {"parts": 30.0, "metal": 30.0, "fuel": 40.0},
	"landmark": {"metal": 20.0, "parts": 10.0, "food": 10.0},
}
const DEPLETE := 0.75 # yield factor per earlier trip to the same site
const MIN_YIELD := 0.25
const OUTPOST_KEEP := {"fuel": 20.0, "ammo": 60} # an outpost keeps this much, the convoy takes the rest
# hazards
const ZOMBIE_WEAR := 0.03 # hull/s per point of danger off-screen
const ESCORT_COVER := 0.2 # less wear per escort
const CONTACT := 22.0 # px: zombies this close to the truck slow it and hit it
const ZOMBIE_DPS := 3.0 # per zombie in contact
const ZOMBIE_SLOW := 0.35 # speed / (1 + this per zombie in contact)
const ESCORT_RANGE := 220.0
const ESCORT_DPS := 14.0 # per healthy escort, at the nearest hostile
const AMBUSH_CHANCE := 0.08 # per leg
const AMBUSH_CAMP_CHANCE := 0.35 # per leg with a bandit camp within AMBUSH_CAMP_REACH of the spot
const AMBUSH_CAMP_REACH := 2800.0
const AMBUSH_GAP := 300.0 # px between candidate spots
const AMBUSH_END_GAP := 400.0 # px: no ambush this close to either end
const AMBUSH_SIZE := Vector2i(2, 4) # plus one per AMBUSH_DAYS days
const AMBUSH_DAYS := 10
const AMBUSH_DPS := 0.4 # hull/s per ambusher
const ESCORT_KILLS := 0.03 # ambushers per second per healthy escort, off-screen
const AMBUSH_HURT := 0.3 # per escort once an ambush is beaten off
const AMBUSH_SPOT := Vector2(60.0, 140.0) # px from the road the ambushers stand
const LOST_DEATH := 0.4
const LOST_MORALE := -3.0
const SHOW_DIST := 1000.0
const HIDE_DIST := 1200.0
const TICK := 0.25
const NARROW := [Chunks.T.WATER, Chunks.T.ROCK, Chunks.T.FOREST, Chunks.T.TREE_EDGE]

var list: Array = [] # {id, dest {uid, kind, name, pos}, path, d, leg "out"|"loot"|"back", t, hp, cargo, amb {out, back}, foes, kill}
var trucks := 0 # at home
var seq := 0
var trips := {} # site uid -> trips looted
var sel := {"dest": "", "driver": -1, "escorts": 0} # CONVOY tab choices
var _paths := {} # [from cell, to cell] -> PackedVector2Array
var _cum := {} # convoy id -> PackedFloat32Array of path lengths
var _nodes := {} # convoy id -> truck node
var _foes := {} # convoy id -> ambusher nodes
var _zombies := {} # convoy id -> zombies in contact (last tick)
var _tick := 0.0
var _ui := {}
var _ui_t := 0.0


func _ready() -> void:
	Save.register("convoys", save_state, load_state)
	_build_tab.call_deferred()


func _process(delta: float) -> void:
	if not Game.running or get_tree().paused:
		return
	_tick -= delta
	var tick := _tick <= 0.0
	if tick:
		_tick = TICK
	for c in list.duplicate():
		_step(c, delta, tick)
	_ui_t -= delta
	if _ui_t <= 0.0 and not _ui.is_empty() and _ui["box"].is_visible_in_tree():
		_ui_t = 0.5
		refresh_tab()


# ---------------------------------------------------------------- road pathing

## Cell centres (world px) along the roads from near `from` to near `to`; empty if no road joins them.
func road_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var key := [Vector2i((from / 16.0).floor()), Vector2i((to / 16.0).floor())]
	if _paths.has(key):
		return _paths[key]
	var out := PackedVector2Array()
	var a := _site_near(from)
	var b := _site_near(to)
	if a != Chunks.NONE and b != Chunks.NONE:
		var route := _site_route(a, b)
		if not route.is_empty():
			out = _cell_path(route, from, to)
	if _paths.size() >= 16:
		_paths.erase(_paths.keys()[0])
	_paths[key] = out
	return out


## Macro cell of the site nearest `pos` among the 3x3 macro cells around it, NONE if none.
func _site_near(pos: Vector2) -> Vector2i:
	var ch: TileMapLayer = Game.world.chunks
	var m0: Vector2i = ch._macro(Vector2i((pos / 16.0).floor()))
	var best := Chunks.NONE
	var best_d := INF
	for k in 9:
		var s: Dictionary = ch.site(m0 + Vector2i(k % 3 - 1, k / 3 - 1))
		var dd := (Vector2(s.center) * 16.0).distance_squared_to(pos)
		if s.kind != "" and dd < best_d:
			best_d = dd
			best = s.m
	return best


## Sites joined to m by a road: its two nearest and those that count m among theirs.
func _links(m: Vector2i) -> Array:
	var ch: TileMapLayer = Game.world.chunks
	var out: Array = ch._knn(m).duplicate()
	for k in 9:
		var q := m + Vector2i(k % 3 - 1, k / 3 - 1)
		if q != m and not q in out and ch.site(q).kind != "" and m in ch._knn(q):
			out.append(q)
	return out


## Dijkstra over the site graph from a to b inside their box grown by 2 macro cells: the macro cells on the way, [] if none.
func _site_route(a: Vector2i, b: Vector2i) -> Array:
	var ch: TileMapLayer = Game.world.chunks
	var box := Rect2i(a, Vector2i.ONE).expand(b).grow(2)
	var dist := {a: 0.0}
	var prev := {}
	var open := [a]
	while not open.is_empty():
		var m: Vector2i = open[0]
		for q: Vector2i in open:
			if dist[q] < dist[m]:
				m = q
		open.erase(m)
		if m == b:
			break
		for q: Vector2i in _links(m):
			var nd: float = dist[m] + Vector2(ch.site(q).center - ch.site(m).center).length()
			if box.has_point(q) and nd < dist.get(q, INF):
				if not dist.has(q):
					open.append(q)
				dist[q] = nd
				prev[q] = m
	if not dist.has(b):
		return []
	var route := [b]
	while route[0] != a:
		route.push_front(prev[route[0]])
	return route


## A* over the road cells of the roads between consecutive route sites (and all roads leaving its two ends) and the
## route sites' streets.
func _cell_path(route: Array, from: Vector2, to: Vector2) -> PackedVector2Array:
	var ch: TileMapLayer = Game.world.chunks
	var pairs := []
	for i in route.size() - 1:
		pairs.append([route[i], route[i + 1]])
	for m: Vector2i in [route[0], route[-1]]:
		for q: Vector2i in _links(m): # all their roads: start and goal may sit on another one (a site's streets do not always join its ports)
			pairs.append([m, q])
	var edges := []
	for pq in pairs:
		var m: Vector2i = pq[0]
		var q: Vector2i = pq[1]
		var e := Vector4i(m.x, m.y, q.x, q.y) if m < q else Vector4i(q.x, q.y, m.x, m.y)
		if not e in edges:
			edges.append(e)
	var cells := {}
	for e: Vector4i in edges:
		ch._edge(e)
		var road = ch._edges.get(e)
		if road is Array:
			for c: Vector2i in road:
				var s: int = ch._layout(ch._macro(c)).cells.get(c, Chunks.NO).x
				if not (s in Chunks.HARD and not s in Chunks.ROADS): # a house of the site stands there (chunk_manager._under)
					cells[c] = true
	for m: Vector2i in route:
		var lay: Dictionary = ch._layout(m).cells
		for c: Vector2i in lay:
			if lay[c].x in Chunks.ROADS:
				cells[c] = true
	var astar := AStar2D.new()
	astar.reserve_space(cells.size())
	var ids := {}
	for c: Vector2i in cells:
		ids[c] = ids.size()
		astar.add_point(ids[c], Vector2(c) * 16.0 + Vector2(8, 8))
	for c: Vector2i in cells:
		for o: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
			if ids.has(c + o):
				astar.connect_points(ids[c], ids[c + o])
	# small towns may leave their road ends unjoined (chunk_manager ports): the truck crosses the town between them
	for m: Vector2i in route:
		var ports: Array = ch._layout(m).ports
		for i in ports.size():
			for j in range(i + 1, ports.size()):
				if ids.has(ports[i]) and ids.has(ports[j]):
					astar.connect_points(ids[ports[i]], ids[ports[j]])
	# lanes and spurs can be cut off from the network: start and goal are the nearest cells of one connected piece
	var part := {}
	var best := [INF, -1, -1] # summed distance, start id, goal id
	for c0: Vector2i in cells:
		if part.has(c0):
			continue
		part[c0] = true
		var todo: Array[Vector2i] = [c0]
		var near := [INF, -1, INF, -1] # start distance, id, goal distance, id
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			var at := Vector2(c) * 16.0 + Vector2(8, 8)
			if at.distance_to(from) < near[0]:
				near[0] = at.distance_to(from)
				near[1] = ids[c]
			if at.distance_to(to) < near[2]:
				near[2] = at.distance_to(to)
				near[3] = ids[c]
			for id in astar.get_point_connections(ids[c]):
				var q := Vector2i((astar.get_point_position(id) / 16.0).floor())
				if not part.has(q):
					part[q] = true
					todo.append(q)
		if near[0] <= START_REACH and near[2] <= DEST_REACH and near[0] + near[2] < best[0]:
			best = [near[0] + near[2], near[1], near[3]]
	if best[1] < 0:
		return PackedVector2Array()
	return astar.get_point_path(best[1], best[2])


# ---------------------------------------------------------------- along the path

func _lengths(c: Dictionary) -> PackedFloat32Array:
	if not _cum.has(c["id"]):
		var p: PackedVector2Array = c["path"]
		var cum := PackedFloat32Array([0.0])
		for i in range(1, p.size()):
			cum.append(cum[i - 1] + p[i - 1].distance_to(p[i]))
		_cum[c["id"]] = cum
	return _cum[c["id"]]


func length(c: Dictionary) -> float:
	var cum := _lengths(c)
	return cum[cum.size() - 1]


## World position of convoy c.
func pos_of(c: Dictionary) -> Vector2:
	return _at(c, c["d"])


func _at(c: Dictionary, d: float) -> Vector2:
	var p: PackedVector2Array = c["path"]
	var cum := _lengths(c)
	var i := cum.bsearch(d)
	if i <= 0:
		return p[0]
	if i >= p.size():
		return p[p.size() - 1]
	return p[i - 1].lerp(p[i], (d - cum[i - 1]) / maxf(0.001, cum[i] - cum[i - 1]))


## Distances along `c`'s path where bandits like to wait: bridges and narrows, AMBUSH_GAP apart, clear of both ends.
func ambush_spots(c: Dictionary) -> Array:
	var ch: TileMapLayer = Game.world.chunks
	var p: PackedVector2Array = c["path"]
	var cum := _lengths(c)
	var out := []
	var last := -INF
	for i in range(1, p.size()):
		if cum[i] < AMBUSH_END_GAP or cum[i] > length(c) - AMBUSH_END_GAP or cum[i] - last < AMBUSH_GAP:
			continue
		var cell := Vector2i((p[i] / 16.0).floor())
		var side := Vector2i((p[i] - p[i - 1]).normalized().orthogonal().round())
		var bridge: bool = ch._road.get(cell, Chunks.NO).x == Chunks.T.BRIDGE
		if bridge or (ch._terrain(cell + side) & 0xff in NARROW and ch._terrain(cell - side) & 0xff in NARROW):
			out.append(cum[i])
			last = cum[i]
	return out


func _roll_ambush(c: Dictionary, spots: Array) -> float:
	if spots.is_empty() or Game.day < Game.world.bandits.first_camp_day():
		return -1.0
	var d: float = spots.pick_random()
	var camp: bool = not Game.world.bandits.camps_near(_at(c, d), AMBUSH_CAMP_REACH).is_empty()
	return d if randf() < (AMBUSH_CAMP_CHANCE if camp else AMBUSH_CHANCE) else -1.0


# ---------------------------------------------------------------- crews and dispatch

func crew(c: Dictionary) -> Array:
	return Game.people.filter(func(p): return p.get("post", "") == c["id"])


func escorts(c: Dictionary) -> Array:
	return crew(c).filter(func(p): return p["id"] != c["driver"] and not p["injured"])


func _home_people() -> Array:
	return Game.people.filter(func(p): return not p["aboard"] and p.get("post", "") == "" and not p["injured"])


func drivers() -> Array:
	return _home_people().filter(func(p): return p["skill"] == "driver")


## Healthy militia first, then soldiers: who rides along with a rifle.
func escort_pool(driver_id: int) -> Array:
	var out := _home_people().filter(func(p): return p["id"] != driver_id and (p["job"] == "militia" or p["skill"] == "soldier"))
	out.sort_custom(func(a, b): return int(a["job"] == "militia") > int(b["job"] == "militia") or (a["job"] == b["job"] and a["id"] < b["id"]))
	return out


func pools() -> int:
	return Game.built("motor_pool")


## Sites the heli has seen (their chunk loaded), allied villages and outposts within RANGE of the base: [{uid, kind, name, pos}].
func destinations() -> Array:
	var out := []
	if not Game.base_founded:
		return out
	var base_pos: Vector2 = Game.world.base.position
	var ch: TileMapLayer = Game.world.chunks
	for s in ch.sites_near(base_pos, RANGE):
		if ch.loaded.has(Vector2i((s.pos / (Chunks.CHUNK * Chunks.TILE)).floor())) and s.pos.distance_to(base_pos) > MIN_DIST:
			out.append({"uid": s.uid, "kind": s.kind, "name": "%s, %s" % [s.kind.replace("_", " ").capitalize(), Poi.where(base_pos, s.pos)], "pos": s.pos})
	for v in Game.world.outposts.villages():
		out.append({"uid": v["id"], "kind": "ally", "name": "%s, %s" % [v["name"], Poi.where(base_pos, v["pos"])], "pos": v["pos"]})
	for o in Game.world.outposts.list:
		out.append({"uid": o["id"], "kind": "outpost", "name": "Outpost %s, %s" % [o["id"].substr(1), Poi.where(base_pos, o["pos"])], "pos": o["pos"]})
	return out


func build_truck() -> String:
	if pools() == 0:
		return "Build a Motor Pool first (BUILD tab)."
	if trucks + list.size() >= pools() * TRUCKS_PER_POOL:
		return "The motor pool is full (%d trucks per Motor Pool)." % TRUCKS_PER_POOL
	for k in TRUCK_COST:
		if Game.salvage[k] < TRUCK_COST[k]:
			return "A truck takes %d metal and %d parts (salvage)." % [TRUCK_COST["metal"], TRUCK_COST["parts"]]
	for k in TRUCK_COST:
		Game.salvage[k] -= TRUCK_COST[k]
	trucks += 1
	Game.radio("Motor pool: a truck is ready (%d at home)." % trucks)
	return ""


## Sends a truck to destination `uid` with driver `driver_id` and `n` escorts. "" when it left, else why not.
func send(uid: String, driver_id: int, n: int) -> String:
	if pools() == 0:
		return "Build a Motor Pool first (BUILD tab)."
	if trucks <= 0:
		return "No truck at home. Build one from salvage."
	if Game.world.evac.phase in ["countdown", "siege", "landed"]:
		return "The evacuation is under way: every truck stays home to hold the base."
	var dest := {}
	for d in destinations():
		if d["uid"] == uid:
			dest = d
	if dest.is_empty():
		return "Pick a destination."
	var driver: Dictionary = {}
	for p in drivers():
		if p["id"] == driver_id:
			driver = p
	if driver.is_empty():
		return "A convoy needs a healthy driver (Driver skill) at the base."
	var pool := escort_pool(driver_id)
	n = clampi(n, 0, ESCORTS_MAX)
	if pool.size() < n:
		return "Only %d militia or soldiers at the base to escort." % pool.size()
	if Game.base_rifles < n:
		return "Only %d rifles in the armory for the escort." % int(Game.base_rifles)
	var path := road_path(Game.world.base.position, dest["pos"])
	if path.size() < 2:
		return "No road leads from the base to %s." % dest["name"]
	seq += 1
	var c := {"id": "c%d" % seq, "dest": dest, "path": path, "d": 0.0, "leg": "out", "t": 0.0, "hp": HULL, "cargo": {},
		"amb": {}, "foes": 0, "kill": 0.0, "driver": driver_id}
	var spots := ambush_spots(c)
	c["amb"] = {"out": _roll_ambush(c, spots), "back": _roll_ambush(c, spots)}
	trucks -= 1
	Game.base_rifles -= n
	for p in [driver] + pool.slice(0, n):
		p["post"] = c["id"]
		p["job"] = ""
	Game._fit_workers()
	list.append(c)
	Game.radio("Convoy %d rolls out to %s: %.1f km of road, %d escort(s)." % [seq, dest["name"], length(c) / 10000.0, n])
	Save.autosave()
	return ""


# ---------------------------------------------------------------- driving

func _step(c: Dictionary, delta: float, tick: bool) -> void:
	var pos := pos_of(c)
	var near := Game.heli.position.distance_to(pos) < (HIDE_DIST if _nodes.has(c["id"]) else SHOW_DIST)
	_show(c, near, pos)
	if tick and near:
		_tick_near(c, pos)
	elif tick:
		_zombies.erase(c["id"])
	if c["foes"] > 0:
		_fight(c, delta, near)
	elif c["leg"] == "loot":
		c["t"] -= delta
		if c["t"] <= 0.0:
			_load(c)
	else:
		_drive(c, delta, pos)
	if c["hp"] <= 0.0:
		_lost(c)
	elif _nodes.has(c["id"]):
		var n: Node2D = _nodes[c["id"]]
		var to := pos_of(c)
		if to.distance_squared_to(n.position) > 0.01:
			n.get_child(0).rotation = lerp_angle(n.get_child(0).rotation, (to - n.position).angle() + PI / 2, 0.25)
		n.position = to
		n.queue_redraw()


func _drive(c: Dictionary, delta: float, pos: Vector2) -> void:
	var dir := 1.0 if c["leg"] == "out" else -1.0
	var lv: int = 1
	for p in crew(c):
		if p["id"] == c["driver"]:
			lv = p["skill_lv"]
	var speed := SPEED * (1.0 + DRIVER_SPEED * (lv - 1))
	if _zombies.has(c["id"]):
		var z: int = _zombies[c["id"]]
		speed /= 1.0 + ZOMBIE_SLOW * z
		c["hp"] -= ZOMBIE_DPS * z * delta
	else:
		c["hp"] -= ZOMBIE_WEAR * Game.danger_at(pos) * maxf(0.0, 1.0 - ESCORT_COVER * escorts(c).size()) * delta
	var nd: float = c["d"] + dir * speed * delta
	var stop: float = c["amb"][c["leg"]]
	if stop >= 0.0 and (nd - stop) * dir >= 0.0:
		nd = stop
		c["amb"][c["leg"]] = -1.0
		_ambush(c)
	c["d"] = clampf(nd, 0.0, length(c))
	if c["leg"] == "out" and c["d"] >= length(c):
		c["leg"] = "loot"
		c["t"] = LOOT_SECONDS
		Game.radio("Convoy %s reached %s, loading up." % [c["id"].substr(1), c["dest"]["name"]])
	elif c["leg"] == "back" and c["d"] <= 0.0:
		_home(c)


## 4x a second while the truck is in view: zombies in contact, escorts firing at the nearest hostile.
func _tick_near(c: Dictionary, pos: Vector2) -> void:
	var z := 0
	var best: Node2D = null
	var best_d := ESCORT_RANGE * ESCORT_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_queued_for_deletion() or not e.has_method("hit"):
			continue
		var d := pos.distance_squared_to(e.global_position)
		if "target_base" in e and d < CONTACT * CONTACT:
			z += 1
		if d < best_d:
			best_d = d
			best = e
	_zombies[c["id"]] = z
	var n := escorts(c).size()
	if best != null and n > 0:
		best.hit(ESCORT_DPS * n * TICK, (best.global_position - pos).normalized())
		if _nodes.has(c["id"]):
			_nodes[c["id"]].set_meta("shot", [best.global_position, Time.get_ticks_msec()])
		Sfx.play("gun", pos, -18.0)


func _ambush(c: Dictionary) -> void:
	c["foes"] = randi_range(AMBUSH_SIZE.x, AMBUSH_SIZE.y) + Game.day / AMBUSH_DAYS
	c["kill"] = 0.0
	var alone := " No escort: the truck can't hold on its own!" if escorts(c).is_empty() and not _nodes.has(c["id"]) else ""
	Game.radio("ALERT: Convoy %s under attack, %s from the base! Requesting air cover.%s" % [c["id"].substr(1), Poi.where(Game.world.base.position, pos_of(c)), alone])
	Sfx.play("alarm")


func _fight(c: Dictionary, delta: float, near: bool) -> void:
	if near:
		var alive: Array = _foes.get(c["id"], []).filter(func(u): return is_instance_valid(u) and not u.is_queued_for_deletion())
		_foes[c["id"]] = alive
		c["foes"] = alive.size()
	else:
		c["kill"] += escorts(c).size() * ESCORT_KILLS * delta
		while c["kill"] >= 1.0 and c["foes"] > 0:
			c["kill"] -= 1.0
			c["foes"] -= 1
	c["hp"] -= AMBUSH_DPS * c["foes"] * delta
	if c["foes"] <= 0 and c["hp"] > 0.0:
		_foes.erase(c["id"])
		var hurt := 0
		for p in escorts(c):
			if randf() < AMBUSH_HURT:
				p["injured"] = true
				hurt += 1
		Game.radio("Convoy %s: ambush beaten off%s. Moving on." % [c["id"].substr(1), ", %d hurt" % hurt if hurt > 0 else ""])


## The truck node (and the ambushers) while the heli is close, dropped beyond HIDE_DIST (ambushers keep their count).
func _show(c: Dictionary, near: bool, pos: Vector2) -> void:
	var id: String = c["id"]
	if near and not _nodes.has(id):
		var n := Truck.new()
		n.convoy = c
		n.position = pos
		n.z_index = 3
		var s := Art.sprite("truck")
		var ahead := _at(c, c["d"] + (4.0 if c["leg"] == "out" else -4.0))
		s.rotation = (ahead - pos).angle() + PI / 2 if ahead != pos else 0.0
		n.add_child(s)
		add_child(n)
		_nodes[id] = n
	elif not near and _nodes.has(id):
		_nodes[id].queue_free()
		_nodes.erase(id)
	if near and c["foes"] > 0 and not _foes.has(id):
		var side := (_at(c, c["d"] + 8.0) - pos).orthogonal().normalized()
		var units := []
		for i in c["foes"]:
			var kind := "rpg" if i == 0 and Game.day >= 8 else "rifle"
			var at := pos
			for _try in 8:
				at = pos + side * randf_range(AMBUSH_SPOT.x, AMBUSH_SPOT.y) * (1.0 if i % 2 == 0 else -1.0) + side.orthogonal() * randf_range(-60, 60)
				if Game.world.is_walkable(at):
					break
			units.append(Game.world.bandits.spawn_unit(kind, at, "guard", at, ""))
		_foes[id] = units
	elif not near and _foes.has(id):
		for u in _foes[id]:
			if is_instance_valid(u):
				u.queue_free()
		_foes.erase(id)


func _drop(c: Dictionary) -> void:
	if _nodes.has(c["id"]):
		_nodes[c["id"]].queue_free()
	for u in _foes.get(c["id"], []):
		if is_instance_valid(u): # the ambushers walk off and vanish (unit_home without a camp)
			u.role = "home"
			u.home = u.global_position + (u.global_position - Game.heli.position).normalized() * 300.0
	for dict: Dictionary in [_nodes, _foes, _cum, _zombies]:
		dict.erase(c["id"])
	list.erase(c)


# ---------------------------------------------------------------- loot, home, loss

func _load(c: Dictionary) -> void:
	var dest: Dictionary = c["dest"]
	var cargo := {}
	var op: Node = Game.world.outposts
	match dest["kind"]:
		"ally": # an allied village (a town site of kind "village" loots as a town)
			if op.allies.has(dest["uid"]):
				var v: Dictionary = op.allies[dest["uid"]]
				cargo = v["stock"].duplicate()
				v["stock"] = {"food": 0.0, "water": 0.0}
				v["last_visit"] = Game.day
		"outpost":
			var o: Dictionary = op.outpost(dest["uid"])
			if not o.is_empty():
				cargo = {"fuel": maxf(0.0, o["fuel"] - OUTPOST_KEEP["fuel"]), "ammo": float(maxi(0, o["ammo"] - OUTPOST_KEEP["ammo"]))}
				o["fuel"] -= cargo["fuel"]
				o["ammo"] -= int(cargo["ammo"])
		_:
			var kind: String = dest["kind"]
			var table: Dictionary = LOOT.get(kind, LOOT["town"] if kind in Chunks.TOWN_SIZE else LOOT["landmark"])
			var f := maxf(MIN_YIELD, pow(DEPLETE, trips.get(dest["uid"], 0)))
			trips[dest["uid"]] = trips.get(dest["uid"], 0) + 1
			for k in table:
				cargo[k] = roundf(Game.world.modifiers.loot(table[k] * f * randf_range(0.8, 1.2))) # villages / outposts give their stock as is
	c["cargo"] = cargo
	c["leg"] = "back"
	Game.radio("Convoy %s loaded (%s), heading home." % [c["id"].substr(1), _cargo_text(cargo)])


func _cargo_text(cargo: Dictionary) -> String:
	var parts := []
	for k in cargo:
		if cargo[k] >= 1.0:
			parts.append("%d %s" % [cargo[k], k])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _home(c: Dictionary) -> void:
	var g: Dictionary = c["cargo"]
	Game.base_food += g.get("food", 0.0)
	Game.base_water += g.get("water", 0.0)
	Game.base_medicine += g.get("medicine", 0.0)
	Game.base_rifles += g.get("rifles", 0.0) + escorts(c).size() + crew(c).filter(func(p): return p["injured"] and p["id"] != c["driver"]).size()
	Game.base_fuel = minf(Game.base_fuel_cap, Game.base_fuel + g.get("fuel", 0.0))
	Game.base_ammo = minf(Game.base_ammo_cap, Game.base_ammo + g.get("ammo", 0.0))
	Game.scrap += int(g.get("scrap", 0.0))
	for k in Game.salvage:
		Game.salvage[k] += g.get(k, 0.0)
	for p in crew(c):
		p["post"] = ""
	trucks += 1
	Game.radio("Convoy %s is back: %s." % [c["id"].substr(1), _cargo_text(g)])
	_drop(c)
	Save.autosave()


func _lost(c: Dictionary) -> void:
	var died := 0
	for p in crew(c):
		if randf() < LOST_DEATH:
			Game.lose_person(false, p)
			died += 1
		else:
			p["injured"] = true
			p["post"] = ""
	Game.radio("ALERT: Convoy %s was destroyed %s from the base! Cargo lost, %d dead, the rest walk home injured." % [c["id"].substr(1), Poi.where(Game.world.base.position, pos_of(c)), died])
	Game.world.morale.add(LOST_MORALE, "convoy lost")
	_drop(c)


# ---------------------------------------------------------------- HUD and map

func _what(c: Dictionary) -> String:
	if c["foes"] > 0:
		return "UNDER ATTACK"
	return {"out": "out %d%%" % (100.0 * c["d"] / maxf(1.0, length(c))), "loot": "loading", "back": "home %d%%" % (100.0 * (1.0 - c["d"] / maxf(1.0, length(c))))}[c["leg"]]


func status() -> String:
	var out := ""
	for c in list:
		out += "\nCONVOY %s %s  hull %d" % [c["id"].substr(1), _what(c), c["hp"]]
	return out


func draw_map(canvas: Control, to_map: Callable) -> void:
	for c in list:
		var at: Vector2 = to_map.call(pos_of(c))
		var col := Color(1.0, 0.2, 0.2) if c["foes"] > 0 and fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0 else Color(0.95, 0.85, 0.3)
		canvas.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Color.BLACK)
		canvas.draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), col)


## Truck node: the sprite (child 0), a hull bar and the escorts' last tracer.
class Truck extends Node2D:
	var convoy: Dictionary

	func _draw() -> void:
		var f: float = clampf(convoy["hp"] / HULL, 0.0, 1.0)
		draw_rect(Rect2(-9, -18, 18, 2), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-9, -18, 18 * f, 2), Color(0.4, 0.9, 0.4) if f > 0.5 else Color(1.0, 0.5, 0.2))
		var shot: Array = get_meta("shot", [])
		if not shot.is_empty() and Time.get_ticks_msec() - shot[1] < 80:
			draw_line(Vector2.ZERO, shot[0] - global_position, Color(1.0, 0.85, 0.45, 0.8), 1.0)


# ---------------------------------------------------------------- CONVOY tab

func _build_tab() -> void:
	var ui: CanvasLayer = Game.world.base.ui
	if ui == null or not ui.tabs.has("CONVOY"):
		return
	var v: VBoxContainer = ui.tabs["CONVOY"]
	_ui["box"] = v
	v.add_child(ui._label("MOTOR POOL", 12, ui.ACCENT, true))
	var row := HBoxContainer.new()
	v.add_child(row)
	_ui["pool"] = ui._label("", 13, ui.SAND, true)
	_ui["pool"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ui["pool"])
	_ui["truck"] = Button.new()
	_ui["truck"].text = "BUILD TRUCK"
	_ui["truck"].pressed.connect(func(): _say(build_truck()))
	row.add_child(_ui["truck"])
	v.add_child(ui._rule())
	v.add_child(ui._label("NEW CONVOY", 12, ui.ACCENT, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	v.add_child(grid)
	for k in ["dest", "driver"]:
		grid.add_child(ui._label({"dest": "Destination", "driver": "Driver"}[k], 13))
		var o := OptionButton.new()
		o.custom_minimum_size.x = 420
		o.item_selected.connect(func(i: int): sel[k] = o.get_item_metadata(i))
		grid.add_child(o)
		_ui[k] = o
	grid.add_child(ui._label("Escorts", 13))
	var er := HBoxContainer.new()
	grid.add_child(er)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "-" if d < 0 else "+"
		b.custom_minimum_size = Vector2(28, 26)
		b.pressed.connect(func():
			sel["escorts"] = clampi(sel["escorts"] + d, 0, ESCORTS_MAX)
			refresh_tab())
		er.add_child(b)
		if d < 0:
			_ui["escorts"] = ui._label("", 14, ui.SAND, true)
			er.add_child(_ui["escorts"])
	_ui["send"] = Button.new()
	_ui["send"].text = "SEND CONVOY"
	_ui["send"].custom_minimum_size = Vector2(160, 32)
	_ui["send"].pressed.connect(func(): _say(send(sel["dest"], sel["driver"], sel["escorts"])))
	v.add_child(_ui["send"])
	_ui["msg"] = ui._label("", 12, ui.BAD, true)
	_ui["msg"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_ui["msg"])
	v.add_child(ui._rule())
	v.add_child(ui._label("ON THE ROAD", 12, ui.ACCENT, true))
	_ui["road"] = ui._label("", 13, ui.SAND, true)
	v.add_child(_ui["road"])


func _say(why: String) -> void:
	_ui["msg"].text = why
	refresh_tab()


func _fill(o: OptionButton, items: Array, key: String) -> void:
	var labels := items.map(func(it): return it[0])
	if o.get_meta("labels", []) != labels:
		o.set_meta("labels", labels)
		o.clear()
		for it in items:
			o.add_item(it[0])
			o.set_item_metadata(o.item_count - 1, it[1])
	var found := false
	for i in o.item_count:
		if o.get_item_metadata(i) == sel[key]:
			o.select(i)
			found = true
	if not found and o.item_count > 0:
		o.select(0)
		sel[key] = o.get_item_metadata(0)


func refresh_tab() -> void:
	if _ui.is_empty():
		return
	_ui["pool"].text = "motor pools %d   trucks at home %d   on the road %d\ntruck: %d metal + %d parts (you have %d / %d)" % [pools(), trucks, list.size(),
		TRUCK_COST["metal"], TRUCK_COST["parts"], Game.salvage["metal"], Game.salvage["parts"]]
	_ui["truck"].disabled = pools() == 0
	_fill(_ui["dest"], destinations().map(func(d): return [d["name"], d["uid"]]), "dest")
	_fill(_ui["driver"], drivers().map(func(p): return [preload("res://scripts/people.gd").short(p), p["id"]]), "driver")
	var pool := escort_pool(sel["driver"]).size()
	_ui["escorts"].text = " %d  (%d militia/soldiers, %d rifles) " % [sel["escorts"], pool, Game.base_rifles]
	_ui["send"].disabled = trucks <= 0
	var lines := []
	for c in list:
		lines.append("Truck %s -> %s\n   %s   hull %d   %d crew" % [c["id"].substr(1), c["dest"]["name"], _what(c), c["hp"], crew(c).size()])
	_ui["road"].text = "\n".join(lines) if not lines.is_empty() else "no convoys out"


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	return {"list": list, "trucks": trucks, "seq": seq, "trips": trips}


func load_state(d: Dictionary) -> void:
	for c in list.duplicate():
		_drop(c)
	list.assign(d["list"])
	trucks = d["trucks"]
	seq = d["seq"]
	trips = d["trips"]
