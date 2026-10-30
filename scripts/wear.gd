extends Node
## Heli wear, engine failure, autorotation and emergency landing (docs/ROADMAP.md P12). main.gd keeps it as `wear`, saves itself (hook "wear").
## Four parts, condition 0-100: rotor, engine, gearbox, door gun. Flight and hits wear them (heli.take_damage(amount, source): a "bandit"
## hit wears more). Below LOW_BELOW: engine = slower, rotor = vibration (wider spread), gearbox = more fuel, gun = jams.
## Engine below FAIL_BELOW may quit in flight: WARN_SECONDS of alarm, then autorotation (no thrust, a glide that slows down over
## AUTO_MIN..AUTO_MAX seconds, weak steering, SPACE puts her down; the glide ending does it too). Open ground costs some hull, forest,
## water or a house costs a lot; passengers may get hurt. Then state "down": the crew repairs on site (FIELD_SECONDS, faster with a
## mechanic or engineer aboard) and the heli may take off again with the engine at ON_SITE_ENGINE.
## At the base HANGAR tab: order a repair per part; while the heli sits on the pad the base crew works on it, paid in salvage parts.

const People := preload("res://scripts/people.gd")
const COMPONENTS := ["rotor", "engine", "gearbox", "gun"]
const NAMES := {"rotor": "Rotor", "engine": "Engine", "gearbox": "Gearbox", "gun": "Door gun"}
const EFFECTS := {"rotor": "vibration", "engine": "slower", "gearbox": "more fuel", "gun": "jams"} # under LOW_BELOW; see the header
const WEAR_PER_MIN := {"rotor": 1.2, "engine": 1.5, "gearbox": 1.0} # % per flight minute; the door gun wears by firing
const GUN_WEAR_PER_MIN := 4.0 # % per minute of firing
const HIT_WEAR := 0.15 # % per hull point of a hit, on one random part
const HIT_MULT := {"bandit": 3.0, "rocket": 3.0, "crash": 2.0} # source of a hit -> wear multiplier
const LOW_BELOW := 50.0 # effects start under this condition
const ENGINE_SLOW := 0.4 # top speed lost at engine 0
const VIBRATION := 1.5 # extra spread at rotor 0
const GEARBOX_FUEL := 0.5 # extra fuel burn at gearbox 0
const JAM_PER_S := 0.5 # jam chance per second of firing at gun 0
const JAM_SECONDS := 0.8
const FAIL_BELOW := 25.0 # engine failure possible under this
const FAIL_MAX := 0.08 # failure chance per flight second at engine 0 (climbs with the square of the missing condition)
const WARN_SECONDS := 3.0
const AUTO_MIN := 8.0
const AUTO_MAX := 12.0
const AUTO_DRAG := 0.4 # a glide: far less drag than the powered heli
const AUTO_STEER := 0.15 # thrust left for steering, fading to nothing over the glide
const LAND_HULL := 12.0 # open ground; plus LAND_SPEED_HULL at full speed
const LAND_SPEED_HULL := 20.0
const CRASH_HULL := 40.0 # forest, water, houses
const CRASH_SPEED_HULL := 30.0
const LAND_INJURE := 0.2 # chance per healthy passenger
const CRASH_INJURE := 0.6
const FIELD_SECONDS := 45.0
const MECHANIC_BOOST := 0.5 # field repair speed per skill rate of each mechanic or engineer aboard
const ON_SITE_ENGINE := 30.0
const REPAIR_PCT_PER_S := 2.0 # base repair per effective repair worker
const SOLO_CREW := 0.25 # the pilot's own hands when nobody is on repair duty
const PCT_PER_PART := 10.0 # one salvage part restores this many %

var cond := {"rotor": 100.0, "engine": 100.0, "gearbox": 100.0, "gun": 100.0}
var state := "" # "", "warn" (alarm), "auto" (autorotation), "down" (landed, repairing on site)
var t := 0.0 # seconds left in warn / auto
var auto_total := AUTO_MAX
var field := 0.0 # on-site repair progress 0..1
var jam_t := 0.0
var orders := {} # part -> true: base repair ordered, runs while the heli sits on the pad


func _ready() -> void:
	Save.register("wear", save_state, load_state)
	Game.heli.damaged.connect(on_hit) # main.gd adds the heli before wear


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	jam_t = maxf(0.0, jam_t - delta)
	if Game.heli.landed:
		_ground(delta)
	else:
		_flight(delta)


func _flight(delta: float) -> void:
	orders.clear() # the base crew only works on a heli on the pad
	match state:
		"auto":
			t -= delta
			if t <= 0.0:
				touchdown()
		"warn":
			t -= delta
			_wear(delta)
			if t <= 0.0:
				state = "auto"
				t = randf_range(AUTO_MIN, AUTO_MAX)
				auto_total = t
				Game.radio("Pilot: engine's dead! Autorotation. Steer for open ground and put her down (SPACE).")
		_:
			_wear(delta)
			var e: float = cond["engine"]
			if e < FAIL_BELOW and randf() < FAIL_MAX * pow(1.0 - e / FAIL_BELOW, 2.0) * delta:
				state = "warn"
				t = WARN_SECONDS
				Sfx.play("alarm")
				Game.radio("Pilot: engine is failing! Find open ground, we're losing her in %d seconds." % WARN_SECONDS)


func _wear(delta: float) -> void:
	for c in WEAR_PER_MIN:
		cond[c] = maxf(0.0, cond[c] - WEAR_PER_MIN[c] * delta / 60.0)


func _ground(delta: float) -> void:
	if state == "warn":
		state = "" # got down in time
	if state == "down":
		field += delta / (FIELD_SECONDS / field_speed())
		if field >= 1.0:
			state = ""
			cond["engine"] = maxf(cond["engine"], ON_SITE_ENGINE)
			Game.radio("Crew: engine's turning again at %d %%. Get her home for a proper repair." % cond["engine"])
	if orders.is_empty() or not at_pad():
		return
	var rate: float = REPAIR_PCT_PER_S * maxf(Game.crew("repair") * Game.work_eff(), SOLO_CREW) * delta
	for c in orders.keys():
		var gain: float = minf(rate, 100.0 - cond[c])
		var parts: float = Game.salvage["parts"]
		if gain > parts * PCT_PER_PART:
			gain = parts * PCT_PER_PART
			orders.erase(c)
			Game.radio("Hangar: out of parts, the %s stays at %d %%." % [NAMES[c].to_lower(), cond[c] + gain])
		cond[c] += gain
		Game.salvage["parts"] = parts - gain / PCT_PER_PART
		if cond[c] >= 100.0:
			orders.erase(c)
			Game.radio("Hangar: %s is as good as new." % NAMES[c].to_lower())
		if c == "engine" and state == "down" and cond[c] >= ON_SITE_ENGINE:
			field = 1.0 # the hangar crew beats the field repair


func at_pad() -> bool:
	var base: Node2D = Game.world.base
	return Game.base_founded and Game.heli.position.distance_to(base.position) <= base.PAD_REACH


## HANGAR: order (or cancel) the repair of `part`. Returns why it was refused, "" if done.
func order_repair(part: String) -> String:
	if orders.has(part):
		orders.erase(part)
		return ""
	if cond[part] >= 100.0:
		return "%s is in perfect shape" % NAMES[part]
	if Game.salvage["parts"] < 1.0:
		return "needs salvage parts, you have %d" % Game.salvage["parts"]
	orders[part] = true
	return ""


## Parts a full repair of `part` takes.
func repair_cost(part: String) -> int:
	return ceili((100.0 - cond[part]) / PCT_PER_PART)


## Seconds a repair of `part` takes at the current crew.
func repair_seconds(part: String) -> float:
	return (100.0 - cond[part]) / (REPAIR_PCT_PER_S * maxf(Game.crew("repair") * Game.work_eff(), SOLO_CREW))


func _low(part: String) -> float:
	return clampf(1.0 - cond[part] / LOW_BELOW, 0.0, 1.0)


func speed_factor() -> float:
	return 1.0 - ENGINE_SLOW * _low("engine")


func spread_factor() -> float:
	return 1.0 + VIBRATION * _low("rotor")


## Fuel burn factor; no engine, no burn.
func fuel_factor() -> float:
	return 0.0 if state == "auto" else 1.0 + GEARBOX_FUEL * _low("gearbox")


## Share of the thrust the pilot has: all of it, or the fading steering in autorotation.
func thrust() -> float:
	return AUTO_STEER * t / auto_total if state == "auto" else 1.0


func drag(normal: float) -> float:
	return AUTO_DRAG if state == "auto" else normal


func autorotating() -> bool:
	return state == "auto"


## The heli may not take off: the crew is still on the engine.
func grounded() -> bool:
	return state == "down"


func field_speed() -> float:
	var s := 1.0
	for p in Game.people:
		if p["aboard"] and not p["injured"] and People.matches(p, "repair"):
			s += MECHANIC_BOOST * People.SKILL_RATE[p["skill_lv"]]
	return s


func gun_ok() -> bool:
	return jam_t <= 0.0


## The door gun fired a shot that took `interval` seconds: wear, maybe a jam.
func shot(interval: float) -> void:
	cond["gun"] = maxf(0.0, cond["gun"] - GUN_WEAR_PER_MIN * interval / 60.0)
	if randf() < JAM_PER_S * _low("gun") * interval:
		jam_t = JAM_SECONDS


## A hit on the heli (heli.damaged); `source` "bandit", "rocket" and "crash" wear more.
func on_hit(amount: float, source := "") -> void:
	var c: String = COMPONENTS.pick_random()
	cond[c] = maxf(0.0, cond[c] - amount * HIT_WEAR * HIT_MULT.get(source, 1.0))


## Autorotation ends (SPACE or the glide ran out): the heli is down where it is. Returns false if autorotation was not on.
func touchdown() -> bool:
	if state != "auto":
		return false
	var h: Node2D = Game.heli
	var open: bool = Game.world.is_landable(h.position)
	var speed := clampf(h.vel.length() / h.MAX_SPEED, 0.0, 1.0)
	var hull := (LAND_HULL + LAND_SPEED_HULL * speed) if open else (CRASH_HULL + CRASH_SPEED_HULL * speed)
	var injure := LAND_INJURE if open else CRASH_INJURE
	state = "down"
	field = 0.0
	t = 0.0
	h.vel = Vector2.ZERO
	h.landed = true
	h.pending = 0
	h.transition = 0.0
	Sfx.play("land")
	h.take_damage(hull, "crash" if not open else "landing")
	if not Game.running:
		return true
	if not open: # the wreck ends up on open ground, never a zombie-proof perch on water or a roof
		h.position = landable_near(h.position)
	if not Progression.owned("medic"): # the heli medic keeps passengers safe
		var hurt := 0
		for i in Game.passengers - Game.passengers_injured:
			hurt += int(randf() < injure)
		Game.passengers_injured += hurt
	Game.radio("Pilot: %s Crew is on the engine, %d seconds." % ["Down on open ground." if open else "Came down in the trees, water or houses, she's torn up!", FIELD_SECONDS / field_speed()])
	h.landed_changed.emit(true)
	return true


## The nearest landable spot to `pos` (rings of 16 px out to 400 px), `pos` itself if there is none.
func landable_near(pos: Vector2) -> Vector2:
	for r in range(16, 400, 16):
		for i in 16:
			var p := pos + Vector2(r, 0).rotated(i * TAU / 16.0)
			if Game.world.is_landable(p):
				return p
	return pos


## One line for the HUD alert, "" when all is well.
func alert() -> String:
	match state:
		"warn":
			return "ENGINE FAILING"
		"auto":
			return "AUTOROTATION %d s  [SPACE] land" % ceili(t)
		"down":
			var n := int(10.0 * field)
			return "FIELD REPAIR [%s%s] %d %%" % ["#".repeat(n), "-".repeat(10 - n), int(100.0 * field)]
	return "GUN JAMMED" if jam_t > 0.0 else ""


## "HELI  rotor 98  engine 95  gearbox 99  gun 100" for the HUD.
func status_line() -> String:
	return "HELI  " + "  ".join(COMPONENTS.map(func(c): return "%s %d" % [c, ceili(cond[c])]))


func save_state() -> Dictionary:
	return {"cond": cond.duplicate(), "state": state, "t": t, "auto_total": auto_total, "field": field, "orders": orders.keys()}


func load_state(d: Dictionary) -> void:
	cond = d["cond"]
	state = d["state"]
	t = d["t"]
	auto_total = d["auto_total"]
	field = d["field"]
	orders = {}
	for c in d["orders"]:
		orders[c] = true
