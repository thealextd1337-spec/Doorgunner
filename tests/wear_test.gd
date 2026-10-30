extends Node
## Headless heli wear test (docs/ROADMAP.md P12). main.gd adds this node when env SMOKE=wear (base founded):
##   SMOKE=wear godot --headless --path . --quit-after 30000
## Wear drops in flight and from hits (bandits more), the low-condition effects bite, a failing engine warns and then
## starts the autorotation, SPACE puts her down (open ground cheaper than rough ground), the crew repairs on site
## (faster with a mechanic aboard) and the heli can take off again, the HANGAR repair costs parts and takes time, the hook round-trips.

const Wear := preload("res://scripts/wear.gd")
var wear: Node
var heli: Node2D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var frame := get_tree().process_frame
	await frame
	await frame
	get_tree().paused = true # the test drives the clock
	wear = main.wear
	heli = Game.heli
	Game.passengers = 0
	# --- fresh heli, wear in flight only
	assert(Wear.COMPONENTS.all(func(c): return wear.cond[c] == 100.0) and wear.state == "", "new run: everything at 100 %")
	heli.landed = true
	_tick(10.0)
	assert(wear.cond["engine"] == 100.0, "no wear on the ground")
	heli.landed = false
	_tick(60.0)
	assert(is_equal_approx(wear.cond["engine"], 100.0 - Wear.WEAR_PER_MIN["engine"]) and wear.cond["rotor"] < 100.0 and wear.cond["gearbox"] < 100.0, "a flight minute wears: %s" % [wear.cond])
	assert(wear.cond["gun"] == 100.0, "the gun wears by firing, not by flying")
	# --- hits wear, bandit hits more; the hull takes the damage as before
	var plain := _wear_after_hits("")
	var bandit := _wear_after_hits("bandit")
	assert(plain > 0.0 and bandit > plain * 2.5, "bandit hits wear more: %s vs %s" % [bandit, plain])
	_reset()
	Game.hp = Game.max_hp
	heli.take_damage(10.0, "bandit")
	heli.take_damage(10.0)
	assert(Game.hp < Game.max_hp and Wear.COMPONENTS.any(func(c): return wear.cond[c] < 100.0), "take_damage with and without a source")
	# --- effects start under 50 %
	_reset()
	assert(wear.speed_factor() == 1.0 and wear.spread_factor() == 1.0 and wear.fuel_factor() == 1.0, "healthy: no effects")
	for c in Wear.COMPONENTS:
		wear.cond[c] = Wear.LOW_BELOW
	assert(wear.speed_factor() == 1.0 and wear.spread_factor() == 1.0 and wear.fuel_factor() == 1.0, "50 %: still no effects")
	var fast := _top_speed()
	var burn_ok := _burn()
	wear.cond["engine"] = 0.0
	wear.cond["rotor"] = 0.0
	wear.cond["gearbox"] = 0.0
	assert(is_equal_approx(wear.speed_factor(), 1.0 - Wear.ENGINE_SLOW) and is_equal_approx(wear.spread_factor(), 1.0 + Wear.VIBRATION) and is_equal_approx(wear.fuel_factor(), 1.0 + Wear.GEARBOX_FUEL), "effects at 0 %")
	var slow := _top_speed()
	assert(slow < fast * 0.7, "a dead engine is slower: %s vs %s" % [slow, fast])
	assert(_burn() > burn_ok * 1.4, "a bad gearbox burns more fuel")
	_reset()
	for i in 3000:
		wear.shot(0.15)
	assert(wear.gun_ok() and wear.cond["gun"] < 100.0, "a healthy gun wears but never jams")
	wear.cond["gun"] = 0.0
	var jams := 0
	for i in 400:
		wear.jam_t = 0.0
		wear.shot(0.15)
		jams += int(not wear.gun_ok())
	while wear.gun_ok():
		wear.shot(0.15)
	assert(jams > 5 and wear.alert() == "GUN JAMMED", "a worn gun jams in sustained fire: %d jams" % jams)
	wear._process(Wear.JAM_SECONDS + 0.1)
	assert(wear.gun_ok(), "the jam clears")
	# --- engine failure: no risk above 25 %, then warning, then autorotation
	_reset()
	wear.cond["engine"] = 60.0
	_tick(300.0)
	assert(wear.state == "", "no failure with a healthy engine")
	wear.cond["engine"] = 5.0
	var secs := 0.0
	while wear.state == "" and secs < 600.0:
		_tick(0.1)
		secs += 0.1
	assert(wear.state == "warn" and wear.alert() == "ENGINE FAILING", "a worn engine fails: %s after %d s" % [wear.state, secs])
	_tick(Wear.WARN_SECONDS - 0.5)
	assert(wear.state == "warn", "the warning lasts %d s" % Wear.WARN_SECONDS)
	_tick(0.6)
	assert(wear.state == "auto" and wear.autorotating() and wear.t >= Wear.AUTO_MIN and wear.t <= Wear.AUTO_MAX, "then autorotation: %s %s" % [wear.state, wear.t])
	assert("AUTOROTATION" in wear.alert() and wear.fuel_factor() == 0.0, "HUD alert, no fuel burn")
	# glide: no thrust, the speed falls even with the stick held
	heli.vel = Vector2(Game.heli.MAX_SPEED, 0)
	Input.action_press("move_right")
	var steer_t0: float = wear.thrust()
	for i in 60:
		wear._process(0.1)
		heli._move(0.1)
	Input.action_release("move_right")
	assert(wear.thrust() < steer_t0 and steer_t0 <= Wear.AUTO_STEER and heli.vel.length() < 60.0, "the glide slows down: thrust %s, speed %s" % [wear.thrust(), heli.vel.length()])
	# --- landing: open ground against rough ground, the passengers
	var open_pos := _find_ground(true)
	var rough_pos := _find_ground(false)
	var open_loss := _crash_test(open_pos, Vector2.ZERO)
	assert(open_loss > 0.0 and open_loss <= Wear.LAND_HULL + 0.01, "open ground costs a little hull: %s" % open_loss)
	assert(wear.state == "down" and heli.landed and wear.grounded() and "FIELD REPAIR" in wear.alert(), "down after the landing")
	assert(Game.hp > 0.0, "survived")
	heli._toggle_landing()
	assert(heli.pending == 0, "no take-off while the crew works")
	var fast_land := _crash_test(open_pos, Vector2(heli.MAX_SPEED, 0))
	assert(fast_land > open_loss, "landing fast hurts more: %s vs %s" % [fast_land, open_loss])
	if rough_pos != Vector2.ZERO:
		var rough_loss := _crash_test(rough_pos, Vector2.ZERO)
		assert(rough_loss >= Wear.CRASH_HULL / Game.stats["armor"] - 0.01 and rough_loss > open_loss * 2.0, "rough ground costs a lot: %s vs %s" % [rough_loss, open_loss])
	else:
		print("WEAR: no rough ground near the start, crash landing not checked")
	var hurt := 0
	for i in 12: # the passengers: chance per person, so over many landings somebody gets hurt
		Game.passengers = 4
		Game.passengers_injured = 0
		_crash_test(open_pos if rough_pos == Vector2.ZERO else rough_pos, Vector2.ZERO)
		hurt += Game.passengers_injured
	assert(hurt > 0, "passengers get hurt in hard landings: %d" % hurt)
	Game.passengers = 0
	# --- on-site repair: 45 s, faster with a mechanic aboard, then take-off with a 30 % engine
	_crash_test(open_pos, Vector2.ZERO)
	wear.cond["engine"] = 0.0
	var plain_s := _repair_seconds_on_site()
	assert(absf(plain_s - Wear.FIELD_SECONDS) <= 1.5, "field repair takes %d s: %s" % [Wear.FIELD_SECONDS, plain_s])
	assert(wear.state == "" and wear.cond["engine"] == Wear.ON_SITE_ENGINE, "engine back at %d %%" % Wear.ON_SITE_ENGINE)
	heli._toggle_landing()
	assert(heli.pending == -1, "take-off allowed again")
	heli.pending = 0
	heli.landed = true
	Game.people.append(_person(1, "mechanic", true))
	_crash_test(open_pos, Vector2.ZERO)
	Game.people[0]["injured"] = false # the landing may have hurt the mechanic; an injured one does not count
	var mech_s := _repair_seconds_on_site()
	assert(mech_s < plain_s * 0.8 and absf(mech_s - Wear.FIELD_SECONDS / (1.0 + Wear.MECHANIC_BOOST * Wear.People.SKILL_RATE[1])) <= 1.5, "a mechanic aboard speeds it up: %s vs %s" % [mech_s, plain_s])
	Game.people.clear()
	# --- gliding runs out: the heli comes down on its own
	_glide(open_pos, Vector2.ZERO)
	_tick(Wear.AUTO_MAX + 0.5)
	assert(wear.state == "down" and heli.landed, "the glide ending lands her")
	wear.state = ""
	# --- HANGAR repair: parts, time, the repair crew
	heli.position = main.base.position
	heli.landed = true
	_reset()
	wear.cond["rotor"] = 40.0
	Game.salvage["parts"] = 0.0
	assert(wear.order_repair("rotor") != "" and wear.orders.is_empty(), "no parts, no repair order")
	assert(wear.order_repair("gun") != "", "nothing to repair on a new part")
	Game.salvage["parts"] = 10.0
	var solo_s: float = wear.repair_seconds("rotor")
	Game.people.append(_person(2, "mechanic", false))
	Game.people[0]["skill_lv"] = 3
	Game.workers["repair"] = 1
	Game.assign_jobs()
	assert(wear.repair_seconds("rotor") < solo_s * 0.5, "the repair crew works faster: %s vs %s" % [wear.repair_seconds("rotor"), solo_s])
	Game.workers["repair"] = 0
	Game.assign_jobs()
	Game.people.clear()
	assert(wear.order_repair("rotor") == "" and wear.orders.has("rotor") and wear.repair_cost("rotor") == 6, "order placed, 6 parts")
	_tick(30.0)
	assert(wear.cond["rotor"] > 40.0 and wear.cond["rotor"] < 100.0 and Game.salvage["parts"] < 10.0, "repair takes time: %s" % wear.cond["rotor"])
	_tick(solo_s)
	assert(wear.cond["rotor"] == 100.0 and wear.orders.is_empty() and is_equal_approx(Game.salvage["parts"], 4.0), "done, 6 parts spent: %s" % Game.salvage["parts"])
	wear.cond["gearbox"] = 20.0
	Game.salvage["parts"] = 2.0
	wear.order_repair("gearbox")
	_tick(200.0)
	assert(is_equal_approx(wear.cond["gearbox"], 40.0) and Game.salvage["parts"] < 0.001 and wear.orders.is_empty(), "parts run out, the repair stops: %s" % wear.cond["gearbox"])
	wear.cond["gun"] = 50.0
	Game.salvage["parts"] = 9.0
	wear.order_repair("gun")
	heli.landed = false
	_tick(0.1)
	assert(wear.orders.is_empty() and wear.cond["gun"] <= 50.0, "orders are dropped when she takes off")
	heli.landed = true
	# an engine repair at the pad ends the field repair
	wear.state = "down"
	wear.field = 0.1
	wear.cond["engine"] = 28.0
	Game.salvage["parts"] = 20.0
	wear.order_repair("engine")
	_tick(10.0)
	assert(wear.state == "" and wear.cond["engine"] >= Wear.ON_SITE_ENGINE, "the hangar repair got her flying: %s %s" % [wear.state, wear.cond["engine"]])
	# --- the HANGAR tab
	var ui: CanvasLayer = main.base.ui
	_reset()
	wear.cond["rotor"] = 30.0
	wear.cond["engine"] = 20.0
	ui.refresh()
	var rows: Dictionary = ui.wear_rows
	assert(rows.size() == 4 and rows["engine"][2].text == "may fail!" and rows["rotor"][2].text == "vibration" and rows["gun"][3].disabled, "four condition bars")
	assert(rows["rotor"][3].text == "Repair 7 parts", "cost on the button: %s" % rows["rotor"][3].text)
	Game.salvage["parts"] = 0.0
	ui._order_repair("rotor")
	assert(ui.wear_msg.text != "" and wear.orders.is_empty(), "the UI says why")
	Game.salvage["parts"] = 20.0
	ui._order_repair("rotor")
	assert(wear.orders.has("rotor") and rows["rotor"][3].text.begins_with("working"), "order from the UI")
	ui._order_repair("rotor")
	assert(wear.orders.is_empty(), "a second click cancels")
	# --- save hook
	wear.cond = {"rotor": 12.5, "engine": 7.0, "gearbox": 88.0, "gun": 49.0}
	wear.state = "auto"
	wear.t = 6.5
	wear.auto_total = 10.0
	wear.field = 0.4
	wear.orders = {"gun": true}
	var d: Dictionary = bytes_to_var(var_to_bytes(wear.save_state()))
	_reset()
	wear.orders = {}
	wear.load_state(d)
	assert(wear.cond["engine"] == 7.0 and wear.state == "auto" and wear.t == 6.5 and wear.auto_total == 10.0 and wear.field == 0.4 and wear.orders.has("gun"), "wear round-trips the save")
	print("WEAR OK  hits plain %.1f bandit %.1f, top speed %d -> %d, field repair %d s / %d s with a mechanic" % [plain, bandit, fast, slow, plain_s, mech_s])
	get_tree().quit(0)


func _tick(seconds: float) -> void:
	var n := ceili(seconds / 0.1)
	for i in n:
		wear._process(seconds / n)


func _reset() -> void:
	for c in Wear.COMPONENTS:
		wear.cond[c] = 100.0
	wear.state = ""
	wear.orders.clear()
	wear.jam_t = 0.0
	wear.field = 0.0


func _wear_after_hits(source: String) -> float:
	_reset()
	for i in 20:
		wear.on_hit(10.0, source)
	return Wear.COMPONENTS.reduce(func(a, c): return a + 100.0 - wear.cond[c], 0.0)


func _top_speed() -> float:
	heli.landed = false
	heli.vel = Vector2.ZERO
	Input.action_press("move_right")
	for i in 200:
		heli._move(0.05)
	Input.action_release("move_right")
	var v: float = heli.vel.length()
	heli.position = Game.world.BASE_POS
	heli.vel = Vector2.ZERO
	return v


func _burn() -> float:
	heli.landed = false
	heli.vel = Vector2.ZERO
	Game.fuel = Game.max_fuel
	heli._fuel(10.0)
	return Game.max_fuel - Game.fuel


## A flat spot the heli can (or cannot) land on, at least a pad away from the base; ZERO if none near the start.
func _find_ground(open: bool) -> Vector2:
	var base: Vector2 = Game.world.BASE_POS
	for r in range(6, 40):
		for a in 16:
			var p := base + Vector2.from_angle(a * TAU / 16.0) * r * 16.0
			if Game.world.is_landable(p) == open and p.distance_to(base) > Game.world.base.PAD_REACH * 2.0:
				return p
	return Vector2.ZERO


## Sets up an autorotation over `pos` at `vel`, puts her down; the hull she lost.
func _crash_test(pos: Vector2, vel: Vector2) -> float:
	Game.hp = Game.max_hp
	_glide(pos, vel)
	assert(wear.touchdown(), "touchdown during autorotation")
	return Game.max_hp - Game.hp


func _glide(pos: Vector2, vel: Vector2) -> void:
	heli.position = pos
	heli.vel = vel
	heli.landed = false
	wear.state = "auto"
	wear.t = Wear.AUTO_MAX
	wear.auto_total = Wear.AUTO_MAX


## Seconds until the on-site repair is done (the heli is down).
func _repair_seconds_on_site() -> float:
	var s := 0.0
	while wear.state == "down" and s < 120.0:
		wear._process(0.5)
		s += 0.5
	return s


func _person(id: int, skill: String, aboard: bool) -> Dictionary:
	return {"id": id, "name": "Person %d" % id, "skill": skill, "skill_lv": 1, "trait": "", "injured": false, "job": "", "aboard": aboard, "origin_day": 1, "job_days": 0, "pin": ""}
