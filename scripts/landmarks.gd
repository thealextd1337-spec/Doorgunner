extends Node
## What the Q10 landmarks (docs/ROADMAP2.md Q10, painted by chunk_manager.gd _landmark2) do beyond their POIs.
## main.gd adds the node; it saves itself (hook "landmarks"). Sites are found by kind with chunks.sites_near.
##   hospital     people who board while the heli stands at a hospital (its survivors: nurses and doctors) are medics.
##   stadium,     the first time the heli comes within WAKE_DIST, HORDES[kind] zombies (SpawnTable.pick) pour out of it.
##   hospital
##   power_plant  landing at its centre the first time salvages a power part from the spare parts store: each part
##                (up to PARTS_MAX) saves PART_SAVE of the base generators' fuel. Q12 puts a boss here.
##   harbour      fuel depot, boats, maybe a bandit camp (bandits.gd CAMP_KINDS): table entries elsewhere only.

const WAKE_DIST := 650.0 # px from the site
const HORDES := {"stadium": 36, "hospital": 14}
const HORDE_RING := Vector2(40.0, 200.0) # px from the site centre they spawn
const SCAN_EVERY := 1.5 # s
const LAND_REACH := 260.0 # px from a hospital's centre: boarding there makes medics
const PART_DIST := 64.0 # px from a power plant's centre to land for its part
const PART_SAVE := 0.5 # share of the generator fuel one part saves
const PARTS_MAX := 1

var woken := [] # site uids whose horde came out
var claimed := [] # power plant uids stripped of their part
var parts := 0
var _scan := 0.0
var _seq0 := -1 # Game.person_seq when the heli landed at a hospital, -1 elsewhere (runtime)


func _ready() -> void:
	Save.register("landmarks", save_state, load_state)
	Game.heli.landed_changed.connect(_on_landed)


func _process(delta: float) -> void:
	if not Game.running or get_tree().paused or Game.heli == null:
		return
	if _seq0 >= 0:
		_medics()
	if parts > 0 and Game.base_founded and Game.power: # pays back part of what game_state.gd burns
		var save := Game.built("generator") * Game.GEN_FUEL * PART_SAVE * minf(parts, PARTS_MAX) * delta / Game.DAY_SECONDS
		Game.base_fuel = minf(Game.base_fuel_cap, Game.base_fuel + save)
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = SCAN_EVERY
	for s in Game.world.chunks.sites_near(Game.heli.position, WAKE_DIST):
		if HORDES.has(s.kind) and not s.uid in woken:
			_horde(s)


## The landmark's dead pour out once.
## Base generator fuel per day after what the power part pays back (HUD and base menu figures).
func gen_fuel() -> float:
	return Game.built("generator") * Game.GEN_FUEL * (1.0 - PART_SAVE * minf(parts, PARTS_MAX))


func _horde(s: Dictionary) -> void:
	woken.append(s.uid)
	var n := 0
	for i in HORDES[s.kind] * 3:
		if n >= HORDES[s.kind]:
			break
		var p: Vector2 = s.pos + Vector2(randf_range(HORDE_RING.x, HORDE_RING.y), 0).rotated(randf() * TAU)
		if Game.world.is_walkable(p):
			Game.world.spawn_enemy(SpawnTable.pick(Game.danger_at(p), SpawnTable.context(p, true)), p)
			n += 1
	Game.radio("Gunner: the %s is crawling with them! Here they come!" % s.kind)


func _on_landed(landed: bool) -> void:
	_seq0 = -1
	if not landed:
		return
	var pos: Vector2 = Game.heli.position
	if not Game.world.chunks.sites_near(pos, LAND_REACH, "hospital").is_empty():
		_seq0 = Game.person_seq
	for s in Game.world.chunks.sites_near(pos, PART_DIST, "power_plant"):
		if not s.uid in claimed and parts < PARTS_MAX:
			claimed.append(s.uid)
			parts += 1
			Game.radio("Crew: pulled a turbine regulator out of the plant's stores. Base generators burn %d %% less fuel." % roundi(PART_SAVE * 100.0))


## Everyone who joined the heli since it landed at the hospital is a medic.
func _medics() -> void:
	for p in Game.people:
		if p["aboard"] and p["id"] >= _seq0 and p["skill"] != "medic":
			p["skill"] = "medic"
			Game.radio("Pilot: %s worked at the hospital. A medic for the base." % p["name"])


func save_state() -> Dictionary:
	return {"woken": woken, "claimed": claimed, "parts": parts}


func load_state(d: Dictionary) -> void:
	woken = d.get("woken", [])
	claimed = d.get("claimed", [])
	parts = d.get("parts", 0)
