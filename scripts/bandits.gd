extends Node
## Bandit faction (docs/ROADMAP.md P11), main.gd keeps it as `bandits`. Units: bandit.gd (rifle, mg nest, rpg),
## technical.gd. Saves itself (hook "bandits").
## Camps: landmarks of CAMP_KINDS (chunks.sites_near) are held by bandits from CAMP_DAY on, more often the farther out
## and the later (_holds: a fixed roll per site against CAMP_ODDS + CAMP_PER_KM + CAMP_PER_DAY), so camps only ever
## appear, and a cleared camp stays empty. A camp's garrison ({kind: n}, SpawnTable.CAMP_ROWS) is spawned while the
## heli is within WAKE_DIST and dropped (counts kept) beyond SLEEP_DIST; sleeping camps reinforce by one per kind a day.
## Killing the whole garrison clears the camp: morale, XP, the prisoners wait as a settlement to be picked up, and
## landing there takes the loot (LOOT).
## Patrols: an awake camp sends a few riflemen to the nearest town every PATROL_INTERVAL s; at a settlement they
## abduct survivors (prisoners of the camp), then walk home.
## Raids, announced by intercepted bandit radio: a settlement near a camp at dusk (TOWN_RAID_*; with the heli close
## the raiders really come, otherwise people just go missing), and from BASE_RAID_DAY the FOB at night, never on a
## zombie assault's night (_zombie_night). Base raiders leave RAID_SECONDS after they set out, so a raid always ends.
## Outposts and allied villages (outposts.gd targets()) within PATROL_REACH of a camp are raided at dusk too (outpost_raid):
## resolved at once by outposts.raid with the strength of SpawnTable.RAID_ROWS riflemen.

signal camp_cleared(uid: String) # for missions (P13 "Clear the camp")
signal intercepted(what: String, pos: Vector2) # "town" / "base" raid announced: hint for missions

const CAMP_KINDS := ["prison", "checkpoint", "motel", "quarry"]
const CAMP_DAY := 4
const CAMP_ODDS := {"prison": 0.9, "checkpoint": 0.4, "motel": 0.35, "quarry": 0.3} # share held on CAMP_DAY near the start
const CAMP_PER_KM := 0.06 # more per 1000 px from the start
const CAMP_PER_DAY := 0.03
const CAMP_MAX := 0.95
const CAMP_MIN_BASE := 1000.0 # px: no camp this close to the FOB or the start
const SCAN_RADIUS := 3000.0
const SCAN_INTERVAL := 2.0
const TICK := 0.5
const WAKE_DIST := 950.0
const SLEEP_DIST := 1500.0
const KNOWN_DIST := 1100.0 # radio names the camp when the heli comes this close
const TECH_ROAD_REACH := 20 # cells from the camp a technical looks for a road
const PRISONERS := Vector2i(1, 3)
const LOOT := {"rifles": 2, "fuel": 30.0, "ammo": 80, "scrap": 25}
const LOOT_DIST := 160.0
const CLEAR_XP := 120
const CLEAR_MORALE := 8.0
const PATROL_INTERVAL := Vector2(50.0, 90.0)
const PATROL_REACH := 2800.0
const RAID_SEARCH := 300.0 # px around a patrol's goal for a settlement to raid
const TOWN_RAID_CHANCE := 0.35 # per day and camp, at most one raid a day
const TOWN_RAID_AT := 0.72 # dusk
const LIVE_RAID_DIST := 1300.0 # heli this close to the settlement at raid time: the raiders come for real
const RAID_PARTY := Vector2i(2, 4)
const RAID_SPAWN_DIST := 450.0
const BASE_RAID_DAY := 12
const BASE_RAID_GAP := 4 # days at least between two base raids
const BASE_RAID_CHANCE := 0.5 # per eligible day
const BASE_RAID_AT := 0.85 # night
const BASE_SPAWN_DIST := 700.0
const RAID_STANDOFF := 70.0 # px beyond the fence the raiders shoot from
const RAID_SECONDS := 75.0 # s after it set out (~25 s walk, ~50 s at the fence) a base raider takes what it can and leaves
const BANDIT_CAP := 40 # alive at once
const Technical := preload("res://scripts/technical.gd")
const LANDMARKS := preload("res://scripts/chunk_manager.gd").LANDMARKS
const Poi := preload("res://scripts/poi.gd")

var camps := {} # uid -> {uid, kind, pos, garrison {kind: n}, prisoners, cleared, known, looted}
var town_raid := {} # planned for today: {poi, camp, day}
var outpost_raid := {} # planned for today: {id, camp, day} (outposts.gd target)
var base_raid_day := -1
var last_base_raid := -100
var _awake := {} # camp uid -> [unit nodes and the flag], runtime only
var _patrol_cd := {} # camp uid -> seconds
var _t := 0.0
var _scan_t := 0.0


func _ready() -> void:
	Game.day_changed.connect(_on_day)
	Game.heli.landed_changed.connect(_on_landed)
	Save.register("bandits", save_state, load_state)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = TICK
		_tick()


func _tick() -> void:
	var heli: Vector2 = Game.heli.global_position
	_scan_t -= TICK
	if _scan_t <= 0.0:
		_scan_t = SCAN_INTERVAL
		camps_near(heli, SCAN_RADIUS)
	for uid in camps:
		var c: Dictionary = camps[uid]
		if c["cleared"]:
			continue
		var d: float = heli.distance_to(c["pos"])
		if not c["known"] and d < KNOWN_DIST:
			c["known"] = true
			Game.radio("Gunner: bandit camp at the %s, %s. They shoot back: keep moving, mind the RPG." % [c["kind"].replace("_", " "), Poi.where(heli, c["pos"])])
		if not _awake.has(uid) and d < WAKE_DIST:
			_wake(c)
		elif _awake.has(uid) and d > SLEEP_DIST:
			_sleep(c)
		elif _awake.has(uid):
			_fill(c)
			_patrol_cd[uid] = _patrol_cd.get(uid, randf_range(PATROL_INTERVAL.x, PATROL_INTERVAL.y)) - TICK
			if _patrol_cd[uid] <= 0.0:
				_patrol_cd[uid] = randf_range(PATROL_INTERVAL.x, PATROL_INTERVAL.y)
				send_patrol(c)
	if not town_raid.is_empty() and (town_raid["day"] != Game.day or Game.time >= TOWN_RAID_AT):
		if town_raid["day"] == Game.day:
			_town_raid()
		town_raid = {}
	if not outpost_raid.is_empty() and (outpost_raid["day"] != Game.day or Game.time >= TOWN_RAID_AT):
		if outpost_raid["day"] == Game.day and not camps.get(outpost_raid["camp"], {"cleared": true})["cleared"] and Game.world.get("outposts"):
			Game.world.outposts.raid(outpost_raid["id"], SpawnTable.bandits(SpawnTable.RAID_ROWS, Game.day)["rifle"], "bandits")
		outpost_raid = {}
	if base_raid_day == Game.day and Game.time >= BASE_RAID_AT:
		base_raid_day = -1
		if not _zombie_night(Game.day):
			base_raid()


## Bandit camps (not cleared) within `radius` of `pos`, nearest first: [{uid, kind, pos}]. Registers camps on the way,
## so it also works far from the heli (missions, P13).
func camps_near(pos: Vector2, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in Game.world.chunks.sites_near(pos, radius):
		if not camps.has(s.uid) and s.kind in CAMP_KINDS and holds(s):
			add_camp(s.uid, s.kind, s.pos)
		if camps.has(s.uid) and not camps[s.uid]["cleared"]:
			out.append({"uid": s.uid, "kind": s.kind, "pos": s.pos})
	return out


## Do bandits hold landmark site `s` ({kind, pos, uid}) today? A fixed roll per site against a share that grows with
## distance and days.
func holds(s: Dictionary) -> bool:
	if Game.day < first_camp_day() or not s.kind in CAMP_KINDS or s.pos.length() < CAMP_MIN_BASE:
		return false
	if Game.base_founded and s.pos.distance_to(Game.world.base.global_position) < CAMP_MIN_BASE:
		return false
	var share: float = CAMP_ODDS[s.kind] + CAMP_PER_KM * s.pos.length() / 1000.0 + CAMP_PER_DAY * maxi(0, Game.day - first_camp_day())
	return float(hash([Game.seed, s.uid, "camp"]) % 10000) / 10000.0 < minf(CAMP_MAX, share)


## First day bandits hold camps (and ambush convoys): CAMP_DAY, day 1 under the Warlords modifier.
func first_camp_day() -> int:
	return 1 if Game.world.modifiers.on("warlords") else CAMP_DAY


func add_camp(uid: String, kind: String, pos: Vector2) -> Dictionary:
	camps[uid] = {"uid": uid, "kind": kind, "pos": pos, "garrison": SpawnTable.bandits(SpawnTable.CAMP_ROWS, Game.day),
		"prisoners": randi_range(PRISONERS.x, PRISONERS.y), "cleared": false, "known": false, "looted": false}
	return camps[uid]


func spawn_unit(kind: String, pos: Vector2, role: String, home: Vector2, camp_uid: String) -> Node2D:
	var u: Node2D = Technical.new() if kind == "technical" else Bandit.new()
	u.setup(kind, pos, role, home, Game.danger_at(pos))
	u.camp_uid = camp_uid
	Game.world.add_child(u)
	return u


func _room() -> int:
	return BANDIT_CAP - get_tree().get_nodes_in_group("bandits").size()


func _wake(c: Dictionary) -> void:
	var flag := Art.sprite("bandit_flag")
	flag.position = c["pos"]
	flag.z_index = 1
	Game.world.add_child(flag)
	_awake[c["uid"]] = [flag]
	_fill(c)


## Spawns the guards of awake camp `c` that are in its garrison but not out yet (BANDIT_CAP held some back), so killing
## every guard always empties the garrison.
func _fill(c: Dictionary) -> void:
	var g: Dictionary = c["garrison"]
	var nodes: Array = _awake[c["uid"]]
	for kind in g:
		var out := nodes.filter(func(n): return is_instance_valid(n) and n is Bandit and n.kind == kind and n.role == "guard").size()
		for i in g[kind] - out:
			if _room() <= 0:
				return
			var pos := _spot(c["pos"], 12.0 if kind == "mg" else randf_range(30.0, 80.0))
			if kind == "technical":
				var road = Technical.road_near(c["pos"], TECH_ROAD_REACH)
				if road == null:
					g[kind] = 0 # no road to drive: this camp has none
					break
				pos = Vector2(road) * 16.0 + Vector2(8, 8)
			nodes.append(spawn_unit(kind, pos, "guard", c["pos"], c["uid"]))


func _sleep(c: Dictionary) -> void:
	for n in _awake.get(c["uid"], []):
		if is_instance_valid(n):
			n.queue_free()
	_awake.erase(c["uid"])


## An open, walkable spot about `r` px from `center`, else the centre.
func _spot(center: Vector2, r: float) -> Vector2:
	for i in 12:
		var p := center + Vector2(r, 0).rotated(randf() * TAU)
		if Game.world.is_walkable(p):
			return p
	return center


## A few riflemen of the awake camp `c` walk to the nearest town. False if none could go.
func send_patrol(c: Dictionary) -> bool:
	var g: Dictionary = c["garrison"]
	var towns: Array = Game.world.chunks.sites_near(c["pos"], PATROL_REACH).filter(func(s): return not LANDMARKS.has(s.kind) and s.pos.distance_to(c["pos"]) > 200.0)
	var n := mini(randi_range(SpawnTable.PATROL_SIZE.x, SpawnTable.PATROL_SIZE.y), g.get("rifle", 0) - 1) # one stays home
	if towns.is_empty() or n <= 0 or _room() < n:
		return false
	var to: Vector2 = towns[0].pos + Vector2(randf_range(-40, 40), randf_range(-40, 40))
	for i in n:
		_take_guard(c, "rifle")
		var u := spawn_unit("rifle", _spot(c["pos"], 40.0), "patrol", c["pos"], c["uid"])
		u.goal = to
	return true


## A guard of kind `kind` leaves camp `c` (patrol): one fewer in the garrison and, if awake, one guard node fewer.
func _take_guard(c: Dictionary, kind: String) -> void:
	c["garrison"][kind] -= 1
	for n in _awake.get(c["uid"], []):
		if is_instance_valid(n) and n is Bandit and n.kind == kind and n.role == "guard":
			_awake[c["uid"]].erase(n)
			n.queue_free()
			return


## A patrol reached its town: raid a settlement there, else go home.
func patrol_arrived(u: Node2D) -> void:
	var p := _settlement_near(u.global_position, RAID_SEARCH)
	u.role = "raid" if p else "home"
	u.poi_uid = p.uid if p else ""


func _settlement_near(pos: Vector2, r: float) -> Node2D:
	var best: Node2D
	var best_d := r * r
	for p in Game.world.pois:
		if is_instance_valid(p) and p.kind == "survivors" and not p.done and p.global_position.distance_squared_to(pos) < best_d:
			best_d = p.global_position.distance_squared_to(pos)
			best = p
	return best


func poi(uid: String) -> Node2D:
	for p in Game.world.pois:
		if is_instance_valid(p) and p.uid == uid:
			return p
	return null


## Raider `u` at settlement `p`: one survivor goes to the camp as a prisoner.
func abduct(u: Node2D, p: Node2D) -> void:
	if not p.abduct():
		return
	var c: Dictionary = camps.get(u.camp_uid, {})
	if not c.is_empty() and not c["cleared"]:
		c["prisoners"] += 1
	if p.done:
		u.role = "home"


## A roaming unit is back at its camp: it rejoins the garrison (and stands guard if the camp is awake).
func unit_home(u: Node2D) -> void:
	var c: Dictionary = camps.get(u.camp_uid, {})
	if c.is_empty() or c["cleared"]:
		u.queue_free()
		return
	_rejoin(c, u.kind)
	if _awake.has(c["uid"]):
		u.role = "guard"
		_awake[c["uid"]].append(u)
	else:
		u.queue_free()


## A roaming unit dropped far from the heli: it walks home off-screen.
func unit_gone(u: Node2D) -> void:
	var c: Dictionary = camps.get(u.camp_uid, {})
	if not c.is_empty() and not c["cleared"]:
		_rejoin(c, u.kind)


## One unit back in camp `c`'s garrison, but never past today's CAMP_ROWS: raiders were never taken from it.
func _rejoin(c: Dictionary, kind: String) -> void:
	var n: int = c["garrison"].get(kind, 0)
	c["garrison"][kind] = mini(n + 1, maxi(n, SpawnTable.bandits(SpawnTable.CAMP_ROWS, Game.day).get(kind, 0)))


func unit_died(u: Node2D) -> void:
	if u.role != "guard" or not camps.has(u.camp_uid):
		return
	var c: Dictionary = camps[u.camp_uid]
	c["garrison"][u.kind] = maxi(0, c["garrison"].get(u.kind, 0) - 1)
	_awake.get(c["uid"], []).erase(u)
	if not c["cleared"] and c["garrison"].values().all(func(n): return n <= 0):
		_clear(c)


func _clear(c: Dictionary) -> void:
	c["cleared"] = true
	_sleep(c)
	Game.add_xp(CLEAR_XP)
	Game.world.morale.add(CLEAR_MORALE, "bandit camp cleared")
	var msg := "Gunner: the %s is clear! Land there for their stash." % c["kind"].replace("_", " ")
	if c["prisoners"] > 0:
		var p: Node2D = Game.world.spawn_poi("survivors", _spot(c["pos"], 24.0), RandomNumberGenerator.new(), c["prisoners"])
		p.discovered = not Game.world.modifiers.on("blackout") # Blackout: the map reveals nothing
		msg += " %d prisoners are waiting for a ride." % c["prisoners"]
	Game.radio(msg)
	camp_cleared.emit(c["uid"])


## Landing next to a cleared camp: rifles to the armory, fuel and ammo into the heli, scrap.
func _on_landed(landed: bool) -> void:
	if not landed:
		return
	for uid in camps:
		var c: Dictionary = camps[uid]
		if c["cleared"] and not c["looted"] and Game.heli.global_position.distance_to(c["pos"]) < LOOT_DIST:
			c["looted"] = true
			Game.base_rifles += LOOT["rifles"]
			Game.fuel = minf(Game.max_fuel, Game.fuel + LOOT["fuel"])
			Game.ammo = mini(Game.max_ammo, Game.ammo + LOOT["ammo"])
			Game.scrap += LOOT["scrap"]
			Game.radio("Crew: bandit stash loaded: %d rifles for the armory, fuel, %d rounds, %d scrap." % [LOOT["rifles"], LOOT["ammo"], LOOT["scrap"]])


func _on_day(day: int) -> void:
	for uid in camps:
		var c: Dictionary = camps[uid]
		if c["cleared"] or _awake.has(uid):
			continue
		var want := SpawnTable.bandits(SpawnTable.CAMP_ROWS, day)
		for k in want:
			c["garrison"][k] = maxi(c["garrison"].get(k, 0), mini(want[k], c["garrison"].get(k, 0) + 1))
	plan_town_raid(day)
	plan_outpost_raid(day)
	plan_base_raid(day)


## Maybe plan today's dusk raid on a settlement near a camp, announced over intercepted radio. True if planned.
func plan_town_raid(day: int, force := false) -> bool:
	if not town_raid.is_empty():
		return false
	for uid in camps:
		var c: Dictionary = camps[uid]
		if c["cleared"] or not (force or randf() < TOWN_RAID_CHANCE):
			continue
		var p := _settlement_near(c["pos"], PATROL_REACH)
		if p == null:
			continue
		town_raid = {"poi": p.uid, "camp": uid, "day": day}
		Game.radio("Intercepted bandit radio: \"Hit the settlement at dusk, take the strong ones.\" (%s)" % Poi.where(Game.heli.global_position, p.global_position))
		intercepted.emit("town", p.global_position)
		return true
	return false


## Maybe plan today's dusk raid on an outpost or allied village (outposts.gd targets()) near a camp, never on a zombie
## assault's day. True if planned.
func plan_outpost_raid(day: int, force := false) -> bool:
	var op: Node = Game.world.get("outposts")
	if op == null or not outpost_raid.is_empty() or _zombie_night(day):
		return false
	for uid in camps:
		var c: Dictionary = camps[uid]
		if c["cleared"] or not (force or randf() < TOWN_RAID_CHANCE):
			continue
		for t in op.targets():
			if t["pos"].distance_to(c["pos"]) <= PATROL_REACH:
				outpost_raid = {"id": t["id"], "camp": uid, "day": day}
				Game.radio("Intercepted bandit radio: \"The %s at dusk. Take everything.\" (%s)" % [t["kind"], Poi.where(Game.heli.global_position, t["pos"])])
				intercepted.emit(t["kind"], t["pos"])
				return true
	return false


func _town_raid() -> void:
	var p := poi(town_raid["poi"])
	var c: Dictionary = camps.get(town_raid["camp"], {})
	if p == null or p.done or c.is_empty() or c["cleared"]:
		return
	if Game.heli.global_position.distance_to(p.global_position) < LIVE_RAID_DIST:
		var from: Vector2 = p.global_position + (c["pos"] - p.global_position).normalized() * RAID_SPAWN_DIST
		for i in randi_range(RAID_PARTY.x, RAID_PARTY.y):
			var u := spawn_unit("rifle", _spot(from, 30.0), "raid", c["pos"], c["uid"])
			u.poi_uid = p.uid
		Game.radio("Radio: bandits closing in on the %s, %s!" % [p.label, Poi.where(Game.heli.global_position, p.global_position)])
		return
	var taken := 0
	for i in randi_range(1, 2):
		taken += int(p.abduct())
	c["prisoners"] += taken
	if taken > 0:
		Game.radio("Radio: bandits raided the %s and took %d people." % [p.label, taken])


## The night of a zombie assault? Bandit base raids never share it.
func _zombie_night(day: int) -> bool:
	return Assault.night_taken(day)


## Maybe plan tonight's raid on the FOB (from BASE_RAID_DAY, BASE_RAID_GAP days apart, never on an assault night).
func plan_base_raid(day: int, force := false) -> bool:
	if not Game.base_founded or day < BASE_RAID_DAY or day - last_base_raid < BASE_RAID_GAP or _zombie_night(day):
		return false
	if camps.values().all(func(c): return c["cleared"]) or not (force or randf() < BASE_RAID_CHANCE):
		return false
	base_raid_day = day
	Game.radio("Intercepted bandit radio: \"Tonight we take the soldiers' base. Bring the rockets.\"")
	intercepted.emit("base", Game.world.base.global_position)
	return true


## Explicit override for the evacuation's final siege (evac.gd): a raid on top of the zombie assault, which plan_base_raid never
## allows. Works without any camp. Returns the raiders.
func siege_raid() -> Array:
	return base_raid()


## The raid party (SpawnTable.RAID_ROWS) comes from the nearest camp's side and shoots from beyond the fence.
func base_raid() -> Array:
	var base: Vector2 = Game.world.base.global_position
	var from := Vector2.RIGHT.rotated(randf() * TAU)
	var near := INF
	var camp_uid := ""
	for uid in camps:
		if not camps[uid]["cleared"] and camps[uid]["pos"].distance_to(base) < near:
			near = camps[uid]["pos"].distance_to(base)
			from = (camps[uid]["pos"] - base).normalized()
			camp_uid = uid
	last_base_raid = Game.day
	var units := []
	var party := SpawnTable.bandits(SpawnTable.RAID_ROWS, Game.day)
	for kind in party:
		for i in party[kind]:
			var at := _spot(base + from.rotated(randf_range(-0.3, 0.3)) * BASE_SPAWN_DIST, 30.0)
			var u := spawn_unit(kind, at, "base", camps[camp_uid]["pos"] if camp_uid != "" else at, camp_uid) # home: where they go after RAID_SECONDS
			u.goal = _spot(base + from.rotated(randf_range(-0.5, 0.5)) * (Game.base_radius + RAID_STANDOFF), 16.0)
			units.append(u)
	Sfx.play("alarm")
	Game.radio("ALERT: bandits attacking the base from the %s!" % Poi.DIRS[wrapi(roundi(from.angle() / (TAU / 8)), 0, 8)])
	return units


## Save hook "bandits": camps, plans and the units away from their camp (guards come back with the camp's garrison).
func save_state() -> Dictionary:
	var units := get_tree().get_nodes_in_group("bandits").filter(func(u): return u.role != "guard" and not u.is_queued_for_deletion())
	return {"camps": camps.duplicate(true), "town_raid": town_raid.duplicate(), "outpost_raid": outpost_raid.duplicate(), "base_raid_day": base_raid_day, "last_base_raid": last_base_raid,
		"units": units.map(func(u): return [u.kind, u.position, u.hp, u.max_hp, u.role, u.camp_uid, u.home, u.goal, u.poi_uid])}


func load_state(d: Dictionary) -> void:
	camps = d["camps"]
	town_raid = d["town_raid"]
	outpost_raid = d.get("outpost_raid", {})
	base_raid_day = d["base_raid_day"]
	last_base_raid = d["last_base_raid"]
	for a in d["units"]:
		var u := spawn_unit(a[0], a[1], a[4], a[6], a[5])
		u.hp = a[2]
		u.max_hp = a[3]
		u.goal = a[7]
		u.poi_uid = a[8]
