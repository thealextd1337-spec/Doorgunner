extends Node
## Radio missions (docs/ROADMAP.md P13), main.gd keeps it as `missions`; J opens the list (missions_ui.gd).
## At most MAX_OPEN missions. Every OFFER_EVERY s (from day FIRST_DAY, base founded, no assault) Command radios a new one.
## Accepting is flying there; the timer running out drops it. A mission is {id, type, title, pos, left, total, reward, text, state}
## (built-in types only, saved as is). Targets far away are only picked from `chunks.sites_near`; whatever needs loaded
## tiles (the roof, the nest, the refugees) is created when the heli comes within ACTIVATE_DIST.
## Types (one `_make_<type>(args)` -> {pos, text, state} or {} and one `_tick_<type>(m, delta)` -> "" / "done" / "failed"):
##   rooftop   a family on a roof in a town (a city if there is one): a survivors POI on a house tile, winch or land in the yard.
##   blackbox  land at an airliner crash site; pays salvage and one key part.
##   screamer  a screamer with a few shamblers near a town; it calls a horde every night. Done when it dies.
##   escort    refugees at a town walk to the base while the heli is within FOLLOW_DIST of them (a survivors POI that walks home).
##   camp      STUB (P11): needs a node "bandits" under Game.world with camps() -> Array of {uid: String, pos: Vector2}, the live
##             camps. Done when the offered uid is no longer listed. Until that node exists the type is not offered.
##   medicine  STUB (P14): needs a node "villages" under Game.world with allies() -> Array of {uid: String, pos: Vector2}.
##             Done when the heli lands within TARGET_DIST of the village with MEDICINE_COST base medicine (taken). A village can also
##             offer one itself: Game.world.missions.offer("medicine", {"uid": ..., "pos": ...}).
## Rewards: scrap, XP, morale (morale.add), often a person with a rare skill (Game.People, joins the base at once), salvage and
## one `key_parts` (P15 will spend these on the heli repair; nothing reads the counter yet). Saves itself (hook "missions").

signal changed

const Chunks := preload("res://scripts/chunk_manager.gd")
const Poi := preload("res://scripts/poi.gd")
const T := Chunks.T
const MAX_OPEN := 3
const FIRST_DAY := 2
const OFFER_EVERY := 150.0 # seconds between offers
const MIN_DIST := 900.0 # px from the base: nearer sites are not offered
const MAX_DIST := 2600.0
const ACTIVATE_DIST := 700.0 # px from the heli: the roof, nest or refugees appear (chunks within ~1000 px are loaded)
const TARGET_DIST := 64.0 # landing this close to a black box or village counts
const FOLLOW_DIST := 450.0 # refugees only walk while the heli is this close
const JOIN_DIST := 30.0 # a refugee that vanished this close to the base arrived
const ROOF_REACH := 30 # cells around the town centre searched for a roof
const ROOF_PICK := 8 # the family sits on one of this many roofs nearest the centre
const FAMILY := Vector2i(3, 5)
const REFUGEES := Vector2i(3, 5)
const GUARDS := 4 # shamblers around the screamer
const NIGHT_HORDE := 4 # zombies the screamer calls each night
const MEDICINE_COST := 2.0
const BLACKBOX_SALVAGE := {"parts": 6.0, "electronics": 3.0}
const PERSON_SKILLS := ["engineer", "driver"]
const PROVIDERS := {"camp": ["bandits", "camps"], "medicine": ["villages", "allies"]} # type -> [node name, method]
const TYPES := { # time: seconds range, person: chance of a rare-skill recruit
	"rooftop": {"title": "Rooftop rescue", "tag": "ROOF", "time": Vector2(240, 360), "scrap": Vector2i(40, 70), "xp": 60, "morale": 3.0, "person": 0.5},
	"blackbox": {"title": "Black box", "tag": "BOX", "time": Vector2(480, 600), "scrap": Vector2i(20, 40), "xp": 40, "morale": 0.0, "person": 0.0},
	"screamer": {"title": "Silence the screamer", "tag": "SCREAM", "time": Vector2(540, 720), "scrap": Vector2i(30, 50), "xp": 80, "morale": 2.0, "person": 0.25},
	"escort": {"title": "Escort", "tag": "ESCORT", "time": Vector2(420, 540), "scrap": Vector2i(30, 50), "xp": 50, "morale": 2.0, "person": 0.4},
	"camp": {"title": "Clear the camp", "tag": "CAMP", "time": Vector2(600, 840), "scrap": Vector2i(60, 100), "xp": 150, "morale": 5.0, "person": 0.6},
	"medicine": {"title": "Medicine run", "tag": "MEDS", "time": Vector2(420, 540), "scrap": Vector2i(20, 40), "xp": 40, "morale": 2.0, "person": 0.2},
}

var open := []
var key_parts := 0
var completed := 0
var seq := 0
var used := [] # site uids already offered
var offer_t := OFFER_EVERY
var _watched := {} # mission id -> its screamer node (runtime)
var _seen := {} # mission id -> {survivor instance id: last position} (runtime)


func _ready() -> void:
	Save.register("missions", save_state, load_state)


func _process(delta: float) -> void:
	if Game.running and Game.base_founded and Game.heli != null and not is_instance_valid(Game.world.tutorial):
		step(delta)


## One frame of mission time: tick the open ones, drop the expired, maybe radio a new one.
func step(delta: float) -> void:
	for m: Dictionary in open.duplicate():
		m["left"] -= delta
		var res: String = call("_tick_" + m["type"], m, delta)
		if res != "":
			_finish(m, res == "done")
		elif m["left"] <= 0.0:
			_finish(m, false, true)
	offer_t -= delta
	if offer_t <= 0.0:
		offer_t = OFFER_EVERY
		if Game.day >= FIRST_DAY and not Game.attack_active and not Game.attack_pending:
			offer()


## Types that can be offered now: the local ones always, camp and medicine only with their provider node.
func available_types() -> Array:
	return TYPES.keys().filter(func(t): return not PROVIDERS.has(t) or _provider(t) != null)


## A new mission of `type` ("" = a random available type not open yet). {} if full or no target. `args` is for _make_<type>.
func offer(type := "", args := {}) -> Dictionary:
	if open.size() >= MAX_OPEN:
		return {}
	var types: Array = [type] if type != "" else available_types().filter(func(t): return not open.any(func(m): return m["type"] == t))
	types.shuffle()
	for t: String in types:
		var m: Dictionary = call("_make_" + t, args)
		if not m.is_empty():
			return _add(t, m)
	return {}


func _add(type: String, m: Dictionary) -> Dictionary:
	var t: Dictionary = TYPES[type]
	var secs := randf_range(t["time"].x, t["time"].y)
	m.merge({"id": seq, "type": type, "title": t["title"], "left": secs, "total": secs, "reward": _reward(type)})
	seq += 1
	if m["state"].has("uid"):
		used.append(m["state"]["uid"])
	open.append(m)
	Game.radio("Command: %s - %s, %s, %d min." % [t["title"], m["text"], Poi.where(Game.heli.global_position, m["pos"]), ceili(secs / 60.0)])
	changed.emit()
	return m


func _reward(type: String) -> Dictionary:
	var t: Dictionary = TYPES[type]
	var r := {"scrap": randi_range(t["scrap"].x, t["scrap"].y), "xp": t["xp"], "morale": t["morale"]}
	if randf() < t["person"]:
		r["person"] = PERSON_SKILLS.pick_random()
	if type == "blackbox":
		r["salvage"] = BLACKBOX_SALVAGE
		r["key_part"] = true
	return r


## "55 scrap, 60 XP, +3 morale, an engineer, 6 parts, a key part"
func reward_text(r: Dictionary) -> String:
	var parts := ["%d scrap" % r["scrap"], "%d XP" % r["xp"]]
	if r["morale"] > 0.0:
		parts.append("+%d morale" % r["morale"])
	if r.has("person"):
		parts.append("an " + r["person"] if r["person"][0] in "aeiou" else "a " + r["person"])
	for k in r.get("salvage", {}):
		parts.append("%d %s" % [r["salvage"][k], k])
	if r.get("key_part", false):
		parts.append("a key part")
	return ", ".join(parts)


func _finish(m: Dictionary, ok: bool, expired := false) -> void:
	open.erase(m)
	_watched.erase(m["id"])
	_seen.erase(m["id"])
	if ok:
		completed += 1
		var r: Dictionary = m["reward"]
		Game.scrap += r["scrap"]
		Game.add_xp(r["xp"])
		if r["morale"] > 0.0:
			Game.world.morale.add(r["morale"], "mission done")
		for k in r.get("salvage", {}):
			Game.salvage[k] += r["salvage"][k]
		if r.get("key_part", false):
			key_parts += 1 # P15: spent on the heli repair
		if r.has("person"):
			_recruit(r["person"])
		Game.radio("Command: %s complete. %s." % [m["title"], reward_text(r)])
	else:
		Game.radio("Command: %s %s." % [m["title"], "window closed, we lost it" if expired else "failed"])
	changed.emit()


## A person with a given skill joins the base (named like any other from the run seed).
func _recruit(skill: String) -> void:
	var p: Dictionary = Game.People.make(Game.seed, Game.person_seq, Game.day, false)
	Game.person_seq += 1
	p["skill"] = skill
	Game.people.append(p)
	Game.radio("Base: %s, a trained %s, joins us." % [p["name"], skill])


# --- helpers

func _provider(type: String) -> Node:
	var n: Node = Game.world.get_node_or_null(PROVIDERS[type][0])
	return n if n != null and n.has_method(PROVIDERS[type][1]) else null


func _origin() -> Vector2:
	return Game.world.base.global_position if Game.base_founded else Game.heli.global_position


## A random unused site of `kinds` MIN_DIST..MAX_DIST px from the base, {} if none.
func _site(kinds: Array) -> Dictionary:
	var from := _origin()
	var list: Array = Game.world.chunks.sites_near(from, MAX_DIST).filter(func(s): return s.kind in kinds and s.pos.distance_to(from) >= MIN_DIST and not s.uid in used)
	return list.pick_random() if not list.is_empty() else {}


func _town(site: Dictionary) -> String:
	return String(site["kind"]).replace("_", " ")


func _near(pos: Vector2, dist: float) -> bool:
	return Game.heli.global_position.distance_to(pos) < dist


## True once the chunk under `pos` is generated (its tiles can be asked).
func _loaded(pos: Vector2) -> bool:
	return Game.world.chunks.loaded.has(Vector2i((pos / (Chunks.CHUNK * Chunks.TILE)).floor()))


## Walkable open ground within ~200 px of `center`, Vector2.INF if none.
func _open_spot(center: Vector2) -> Vector2:
	for r in range(0, 200, 16):
		for i in (1 if r == 0 else 12):
			var p := center + Vector2(r, 0).rotated(i * TAU / 12.0)
			if Game.world.is_walkable(p) and Game.world.chunks.is_landable(p):
				return p
	return Vector2.INF


func _poi(m: Dictionary) -> Node2D:
	var uid: String = m["state"].get("poi", "")
	for p in Game.world.pois:
		if is_instance_valid(p) and p.uid == uid:
			return p
	return null


func _spawn_poi(m: Dictionary, pos: Vector2, n: int) -> Node2D:
	var p: Node2D = Game.world.spawn_poi("survivors", pos, RandomNumberGenerator.new(), n)
	p.discovered = true
	m["state"]["poi"] = p.uid
	return p


# --- rooftop rescue

func _make_rooftop(_args: Dictionary) -> Dictionary:
	var s := _site(["city"])
	if s.is_empty():
		s = _site(Chunks.TOWN_SIZE.keys())
	if s.is_empty():
		return {}
	return {"pos": s["pos"], "text": "a family is stuck on a roof in a %s" % _town(s), "state": {"uid": s["uid"]}}


func _tick_rooftop(m: Dictionary, _delta: float) -> String:
	if not m["state"].has("poi"):
		if _near(m["pos"], ACTIVATE_DIST) and _loaded(m["pos"]):
			var roofs: Array = []
			var c0 := Vector2i((m["pos"] / 16.0).floor())
			for x in range(-ROOF_REACH, ROOF_REACH + 1):
				for y in range(-ROOF_REACH, ROOF_REACH + 1):
					if Game.world.chunks.get_cell_atlas_coords(c0 + Vector2i(x, y)).x == T.BUILDING:
						roofs.append(c0 + Vector2i(x, y))
			roofs.sort_custom(func(a, b): return Vector2(a - c0).length_squared() < Vector2(b - c0).length_squared())
			var at: Vector2 = m["pos"]
			if not roofs.is_empty():
				at = Vector2(roofs.slice(0, ROOF_PICK).pick_random()) * 16.0 + Vector2(8, 8)
			else: # a town with no house tiles in reach: the yard will do
				at = _open_spot(at) if _open_spot(at) != Vector2.INF else at
			m["state"]["roof"] = not roofs.is_empty()
			m["pos"] = at
			Game.world.radio_target = _spawn_poi(m, at, randi_range(FAMILY.x, FAMILY.y))
		return ""
	var p := _poi(m)
	if p == null:
		return "failed"
	if p.done:
		return "done" if p.boarded > 0 else "failed"
	return ""


# --- black box

func _make_blackbox(_args: Dictionary) -> Dictionary:
	var s := _site(["airliner"])
	return {} if s.is_empty() else {"pos": s["pos"], "text": "recover the black box from the airliner crash site", "state": {"uid": s["uid"]}}


func _tick_blackbox(m: Dictionary, _delta: float) -> String:
	if Game.heli.landed and _near(m["pos"], TARGET_DIST):
		Game.world.spawner.call_wave(m["pos"], 3) # the noise brings company
		return "done"
	return ""


# --- silence the screamer

func _make_screamer(_args: Dictionary) -> Dictionary:
	var s := _site(Chunks.TOWN_SIZE.keys())
	if s.is_empty():
		return {}
	return {"pos": s["pos"] + Vector2(300, 0).rotated(randf() * TAU), "text": "a screamer is calling hordes at a %s" % _town(s), "state": {"uid": s["uid"]}}


func _tick_screamer(m: Dictionary, _delta: float) -> String:
	var s: Dictionary = m["state"]
	if s.get("dead", false):
		return "done"
	var e = _watched.get(m["id"]) # untyped: the node may be freed
	if not is_instance_valid(e): # not out yet, despawned far from the heli, or lost in a load
		e = null
		for x in get_tree().get_nodes_in_group("enemies"):
			if "state" in x and x.kind == "screamer" and x.state.get("mission", -1) == m["id"]: # POI nests are in the group too
				e = x
		if e == null and _near(m["pos"], ACTIVATE_DIST) and _loaded(m["pos"]):
			e = _spawn_nest(m)
		if e != null:
			_watched[m["id"]] = e
			e.tree_exiting.connect(func(): if e.hp <= 0.0: s["dead"] = true) # killed, not despawned
	if e == null:
		return ""
	m["pos"] = e.global_position
	if Game.is_night() and s.get("night", 0) != Game.day:
		s["night"] = Game.day
		Game.world.spawner.call_wave(e.global_position, NIGHT_HORDE)
		if _near(e.global_position, 1500.0):
			Game.radio("Command: the screamer is calling a horde tonight.")
	return ""


func _spawn_nest(m: Dictionary) -> Node2D:
	var at := _open_spot(m["pos"])
	if at == Vector2.INF:
		return null
	var e: Node2D = Game.world.spawn_enemy("screamer", at)
	e.state["mission"] = m["id"]
	if not m["state"].get("guards", false):
		m["state"]["guards"] = true
		for i in GUARDS:
			Game.world.spawn_enemy("shambler", at + Vector2(40, 0).rotated(i * TAU / GUARDS))
	return e


# --- escort

func _make_escort(_args: Dictionary) -> Dictionary:
	var s := _site(Chunks.TOWN_SIZE.keys())
	return {} if s.is_empty() else {"pos": s["pos"], "text": "refugees at a %s need an escort to the base" % _town(s), "state": {"uid": s["uid"], "arrived": 0}}


func _tick_escort(m: Dictionary, _delta: float) -> String:
	var s: Dictionary = m["state"]
	if not s.has("poi"):
		if _near(m["pos"], ACTIVATE_DIST) and _loaded(m["pos"]):
			var at := _open_spot(m["pos"])
			if at != Vector2.INF:
				var poi := _spawn_poi(m, at, randi_range(REFUGEES.x, REFUGEES.y))
				poi.walking_home = true # they walk to the base (and join it) instead of boarding; target set below
				Game.world.radio_target = poi
		return ""
	var p := _poi(m)
	if p == null:
		return "failed"
	var base_pos: Vector2 = Game.world.base.global_position
	var now := {}
	var centre := Vector2.ZERO
	for x in p.survivors:
		now[x.get_instance_id()] = x.global_position
		centre += x.global_position / p.survivors.size()
	var seen: Dictionary = _seen.get(m["id"], now)
	for id in seen:
		if not now.has(id) and seen[id].distance_to(base_pos) < JOIN_DIST:
			s["arrived"] += 1
	_seen[m["id"]] = now
	if not now.is_empty():
		m["pos"] = centre
		var go := _near(centre, FOLLOW_DIST)
		for x in p.survivors:
			x.target = Game.world.base if go else null
	if p.done or now.is_empty():
		return "done" if s["arrived"] > 0 else "failed"
	return ""


# --- clear the camp (P11 stub)

func _make_camp(_args: Dictionary) -> Dictionary:
	var node := _provider("camp")
	if node == null:
		return {}
	var list: Array = node.camps().filter(func(c): return not c["uid"] in used)
	if list.is_empty():
		return {}
	var c: Dictionary = list.pick_random()
	return {"pos": c["pos"], "text": "clear the bandit camp", "state": {"uid": c["uid"]}}


func _tick_camp(m: Dictionary, _delta: float) -> String:
	var node := _provider("camp")
	if node != null and not node.camps().any(func(c): return c["uid"] == m["state"]["uid"]):
		return "done"
	return ""


# --- medicine run (P14 stub)

func _make_medicine(args: Dictionary) -> Dictionary:
	if Game.base_medicine < MEDICINE_COST:
		return {}
	var v: Dictionary = args
	if not v.has("pos"):
		var node := _provider("medicine")
		var list: Array = node.allies() if node != null else []
		if list.is_empty():
			return {}
		v = list.pick_random()
	return {"pos": v["pos"], "text": "bring %d medicine to the allied village" % MEDICINE_COST, "state": {"uid": v["uid"]}}


func _tick_medicine(m: Dictionary, _delta: float) -> String:
	if not Game.heli.landed or not _near(m["pos"], TARGET_DIST):
		return ""
	if Game.base_medicine >= MEDICINE_COST:
		Game.base_medicine -= MEDICINE_COST
		return "done"
	if Time.get_ticks_msec() - m["state"].get("warned", -100000) > 20000:
		m["state"]["warned"] = Time.get_ticks_msec()
		Game.radio("Village: we need %d medicine, fetch it from the base." % MEDICINE_COST)
	return ""


# --- save

func save_state() -> Dictionary:
	return {"open": open.duplicate(true), "seq": seq, "used": used, "key_parts": key_parts, "completed": completed, "offer_t": offer_t}


func load_state(d: Dictionary) -> void:
	open = d["open"]
	seq = d["seq"]
	used = d["used"]
	key_parts = d["key_parts"]
	completed = d["completed"]
	offer_t = d["offer_t"]
	_watched.clear()
	_seen.clear()
	changed.emit()
