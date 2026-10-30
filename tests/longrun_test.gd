extends Node
## Long-run balance simulation (docs/ROADMAP.md P18). main.gd adds this node when env SMOKE=longrun:
##   SMOKE=longrun godot --headless --path . --fixed-fps 60 --quit-after 5000000
## Optional env: LONGRUN_DAYS (default 40), LONGRUN_OUT (default build/longrun.csv).
## A bot plays the real game: it flies the heli (input actions) to towns and landmarks, lands at settlements and loot,
## shoots what comes near (door gun, real bullets), delivers, keeps the workers on the jobs the stocks need, builds
## barracks, sandbags, a watchtower, clinic, well, generator, perimeter stages and turrets, orders heli repairs, picks the
## first level-up card, and hovers over the base shooting during assaults and bandit raids. No outposts, convoys, wrecks,
## missions or evacuation (not cheap to script; they only add income).
## Time runs fast: Engine.time_scale is set every frame so a frame is QUIET_DT game seconds while nothing is near the heli
## or the base, FLY_DT while flying and FIGHT_DT (small enough for bullets) while enemies are close. One CSV row per day.
## The run counts as collapsed if it ends before the last day (exit 1). Runtime: ~10-20 min for 40 days (see CHANGELOG).

const DAYS := 40
const QUIET_DT := 1.0
const FLY_DT := 0.1
const FIGHT_DT := 1.0 / 40.0 # bullets travel 13 px per frame: still inside a zombie's 16 px
const HOT_RANGE := 340.0 # px: an enemy this close to the heli switches to FIGHT_DT (the bot fires inside 0.7 x the MG's 420)
const BASE_HOT := 140.0 # px beyond the fence: militia (200 px from the posts) and turrets (240 px) reach about this far
const SORTIE_MAX := 260.0 # game s out before turning home
const LOAD_MAX := 45.0 # game s on the ground at a settlement
const FUEL_RESERVE := 18.0
const REACH_START := 2500.0 # px from the base
const REACH_PER_DAY := 200.0
const LZ_CLEAR := 180.0 # px: no landing while an enemy is this close to the spot
const LZ_WAIT := 25.0 # game s of clearing an LZ before giving up on it
const LOOT := ["survivors", "hideout", "crate", "upgrade", "wreck", "scrapyard", "pharmacy", "water_tower", "fuel_station", "radio_tower"]
const COLS := ["day", "scrap", "metal", "parts", "electronics", "food", "water", "fuel", "ammo", "people", "injured", "deaths", "morale",
	"kills", "base_hp", "assault", "wave", "bandit_raids", "points", "level", "sorties", "delivered", "heli_hp", "buildings", "sandbags"]

var main: Node2D
var days := DAYS
var rows: Array[String] = []
var state := "base"
var target: Variant = null # {"pos": Vector2, "poi": Node2D or null, "site": uid or ""}
var visited := {} # site uid -> true, poi instance id -> true (skipped or done)
var t_state := 0.0
var t_sortie := 0.0
var manage_t := 0.0
var deaths := 0
var sorties := 0
var delivered := 0
var raids := 0
var last_raid := -100
var assault_day := -1
var assault_result := ""
var wave := 0
var hot := false
var finished := false
var meta_keep := {}
var nan_said := false
var hp_landed := 0.0
var aim_foe: Node2D = null
var aim_last := Vector2.ZERO
var frames := [0, 0, 0] # quiet, fly, fight frames today (runtime log)
var DEBUG := OS.get_environment("LONGRUN_DEBUG") != ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # picks level-up cards while the tree is paused
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	main = Game.world
	days = int(OS.get_environment("LONGRUN_DAYS")) if OS.get_environment("LONGRUN_DAYS") != "" else DAYS
	meta_keep = Game.meta.duplicate()
	for k in ["total_rescued", "runs", "best_day", "total_kills", "boss_kills", "assaults_held", "victories"]:
		Game.meta[k] = 0 # a first-time player: no permanent bonuses (earlier test runs piled them up in the test profile)
	Game.base_seats = 0
	Game.base_max_fuel = 75.0
	Game.base_max_ammo = 140
	Game.max_hp = 100.0
	Game._reset_progression()
	Game.recompute()
	Game.fuel = Game.max_fuel
	Game.ammo = Game.max_ammo
	Game.hp = Game.max_hp
	Game.rescued = Game.FOUNDING_CREW # main.gd founds the test base empty; a real run starts with the crew
	Game.workers["build"] = 2
	for c in Game.heli.get_children():
		if c is Camera2D:
			c.position_smoothing_enabled = false # 6/s smoothing overshoots on a 1 s frame and runs off to NaN
	main.base.ui.close()
	Game.person_lost.connect(func(_p, died): deaths += int(died))
	Game.people_delivered.connect(func(n): delivered += n)
	Game.base_attack_started.connect(func(d):
		assault_day = d
		assault_result = "running"
		wave = Assault.wave_size(d))
	Game.day_changed.connect(_on_day)
	Game.run_ended.connect(func(reason): _finish("ended day %d: %s" % [Game.day, reason]))
	if DEBUG:
		Game.heli.damaged.connect(func(a, src): if a >= 5.0: print("BOT hit %.0f %s state %s at %s" % [a, src, state, Game.heli.global_position.round()]))
		Game.radio_message.connect(func(m): print("RADIO d%d %.2f %s" % [Game.day, Game.time, m]))
	print("LONGRUN seed %d, %d days" % [Game.seed, days])


func _process(delta: float) -> void:
	if finished or main == null:
		return
	var real := maxf(0.0001, delta / Engine.time_scale) # the engine's unscaled frame time (1/60 under --fixed-fps 60)
	if main.choice_ui.visible:
		main.choice_ui.pick(0)
		return
	if get_tree().paused or not Game.running:
		return
	if not Game.heli.global_position.is_finite():
		_finish("heli position not finite")
		return
	if assault_result == "running" and not Game.attack_active:
		assault_result = "held"
	var s0 := state
	_bot(delta)
	if DEBUG and state != s0:
		print("BOT d%d t%.2f %s -> %s pos %s fuel %.0f hp %.0f pax %d tgt %s" % [Game.day, Game.time, s0, state, Game.heli.global_position.round(), Game.fuel, Game.hp, Game.passengers, target])
	var want := FIGHT_DT if hot else (QUIET_DT if state == "base" and Game.heli.landed else FLY_DT)
	Engine.time_scale = clampf(want / real, 0.05, 4000.0)
	frames[0 if want == QUIET_DT else (1 if want == FLY_DT else 2)] += 1


# ---------------------------------------------------------------- bot

func _bot(delta: float) -> void:
	var heli: Node2D = Game.heli
	var base: Node2D = main.base
	t_state += delta
	var foe := _nearest_enemy(heli.global_position, HOT_RANGE)
	var base_foe := _nearest_enemy(base.global_position, Game.base_radius + BASE_HOT)
	hot = foe != null or base_foe != null or Game.attack_active
	var near_lz: bool = state == "out" and target != null and target["land"] and heli.global_position.distance_to(target["pos"]) < 350.0
	_shoot(foe if state in ["defend", "loading", "landing", "landing_home", "takeoff", "base"] or near_lz or foe != null and (foe.global_position.distance_to(heli.global_position) < 140.0 or foe.is_in_group("bandits")) else null) # cruising past a horde: save the ammo
	var defend: bool = Game.attack_active or base_foe != null and base_foe.global_position.distance_to(base.global_position) < Game.base_radius + 160.0 \
		or (Game.attack_pending and Game.time > 0.75)
	if state in ["out", "home", "defend"] and heli.landed and heli.pending == 0: # put down by an engine failure (wear.gd)
		_release()
		if not main.wear.grounded():
			heli._toggle_landing() # field repair done: up again
		return
	match state:
		"base":
			_release()
			manage_t -= delta
			if manage_t <= 0.0:
				manage_t = 30.0
				_manage()
			if not heli.landed:
				return
			if defend:
				_take_off("defend")
			elif t_state > 8.0 and Game.hp > Game.max_hp * 0.6 and not main.wear.grounded() and main.wear.orders.is_empty():
				target = _pick_target(heli.global_position)
				if target != null:
					sorties += 1
					t_sortie = 0.0
					_take_off("out")
		"defend":
			if DEBUG and int(t_state / 60.0) != int((t_state - delta) / 60.0) and t_state > 200.0:
				for e in get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get("target_base")):
					print("BOT stuck? %s %s hp %.0f tile %d state %s nav %s" % [e.kind, e.global_position.round(), e.hp, main.chunks.tile_at(e.global_position), e.state, e.nav.get("stuck", -1)])
			if DEBUG and int(t_state / 3.0) != int((t_state - delta) / 3.0):
				print("BOT defend t%.0f base_hp %.0f kills %d ammo %d foes %d heli %s nearest %s militia %d rifles %d defenders %d" % [t_state, Game.base_hp, Game.kills, Game.ammo,
					main.assault.attackers(), heli.global_position.round(), _nearest_enemy(heli.global_position, 2000.0).global_position.round() if _nearest_enemy(heli.global_position, 2000.0) else null,
					Game.workers["militia"], int(Game.base_rifles), base.defenders.get_child_count()])
			var aim: Vector2 = base.global_position
			var f := _nearest_enemy(base.global_position, Game.base_radius + 420.0)
			if f != null:
				aim = base.global_position + (f.global_position - base.global_position).limit_length(Game.base_radius * 0.9)
			elif Game.attack_active:
				f = _nearest_attacker()
				if f != null: # a straggler out there keeps the assault going: hunt it
					aim = f.global_position + (heli.global_position - f.global_position).limit_length(200.0)
			if Game.ammo < 15 and Game.base_ammo >= 30.0 or Game.fuel < 25.0:
				_go_home() # rearm on the pad, then back up
				return
			_fly_to(aim, 40.0)
			if not defend and f == null and t_state > 4.0:
				_go_home()
		"out", "home":
			t_sortie += delta
			if state == "out" and (defend or _must_return()):
				_go_home()
				return
			var to: Vector2 = target["pos"]
			if state == "out" and target["poi"] != null and not _poi_ok(target["poi"]):
				_next_or_home()
				return
			if target["land"] and state == "out" and to.distance_to(heli.global_position) < 260.0 and _nearest_enemy(to, LZ_CLEAR) != null:
				_fly_to(to + (heli.global_position - to).normalized() * 160.0, 30.0) # hold off and clear the LZ first
				if t_state > LZ_WAIT:
					visited[target["poi"].get_instance_id()] = true
					_next_or_home()
				return
			if _fly_to(to, 6.0 if target["land"] else 60.0):
				if target["land"]:
					_release()
					if heli.vel.length() <= heli.LAND_SPEED and heli.pending == 0:
						if main.is_landable(heli.position):
							heli._toggle_landing()
							state = "landing_home" if state == "home" else "landing"
							t_state = 0.0
						else:
							target["pos"] = _landing_spot(heli.position, 48.0)
				else:
					visited[target["site"]] = true
					_next_or_home()
		"landing", "landing_home":
			if heli.landed:
				if state == "landing_home":
					state = "base"
					t_state = 0.0
					manage_t = 0.0
				else:
					state = "loading"
					t_state = 0.0
			elif heli.pending == 0 and t_state > 3.0: # refused: try again a little off
				state = "home" if state == "landing_home" else "out"
		"loading":
			var p: Node2D = target["poi"]
			var done: bool = p == null or not is_instance_valid(p) or p.done or Game.passengers >= Game.seats
			var close := _nearest_enemy(heli.global_position, 110.0)
			if t_state < delta * 1.5:
				hp_landed = Game.hp
			if done or t_state > LOAD_MAX or Game.hp < Game.max_hp * 0.6 or Game.hp < hp_landed - Game.max_hp * 0.12 or defend or (close != null and t_state > 1.0):
				if p != null and is_instance_valid(p):
					visited[p.get_instance_id()] = true
				_take_off("next")
		"takeoff":
			if not heli.landed and heli.pending == 0:
				state = target.get("then", "out") if target != null else "home"
				t_state = 0.0
				if state == "next":
					_next_or_home()
				elif state == "defend":
					pass


func _take_off(then: String) -> void:
	var heli: Node2D = Game.heli
	if target == null:
		target = {"pos": main.base.global_position, "poi": null, "site": "", "land": true}
	target["then"] = then
	if heli.landed and heli.pending == 0:
		heli._toggle_landing()
	state = "takeoff"
	t_state = 0.0


func _must_return() -> bool:
	var back: float = Game.heli.global_position.distance_to(main.base.global_position)
	return Game.fuel < _fuel_for(back) + FUEL_RESERVE or Game.ammo < 25 or Game.hp < Game.max_hp * 0.6 \
		or t_sortie > SORTIE_MAX or (Game.passengers >= Game.seats)


func _next_or_home() -> void:
	if not _must_return():
		var t: Variant = _pick_target(Game.heli.global_position)
		if t != null:
			target = t
			state = "out"
			t_state = 0.0
			return
	_go_home()


func _go_home() -> void:
	target = {"pos": main.base.global_position, "poi": null, "site": "", "land": true}
	state = "home"
	t_state = 0.0


func _fuel_for(dist: float) -> float:
	var speed: float = Game.heli.MAX_SPEED * 0.85
	return dist / speed * (Game.heli.FUEL_IDLE + 0.85 * Game.heli.FUEL_FLY) / Game.stats["fuel_eff"] * main.wear.fuel_factor() * 1.25


## The nearest worthwhile POI (survivors first while seats are free), else the nearest unvisited site; null if nothing
## is in fuel range.
func _pick_target(from: Vector2) -> Variant:
	var base_pos: Vector2 = main.base.global_position
	var budget: float = Game.fuel - FUEL_RESERVE
	var best: Variant = null
	var best_score := INF
	for p in main.pois:
		if not _poi_ok(p) or visited.has(p.get_instance_id()):
			continue
		if p.kind in ["survivors", "hideout"] and Game.passengers >= Game.seats:
			continue
		var d: float = from.distance_to(p.position)
		if _fuel_for(d + p.position.distance_to(base_pos)) > budget or _camp_near(p.position) or p.position.distance_to(base_pos) > _reach():
			continue
		var score := d * (0.5 if p.kind in ["survivors", "hideout"] else 1.0)
		if score < best_score:
			best_score = score
			best = {"pos": _landing_spot(p.position, 40.0), "poi": p, "site": "", "land": true}
	if best != null and best_score < 1800.0:
		return best
	for s in main.chunks.sites_near(from, 6000.0):
		if visited.has(s["uid"]) or _camp_near(s["pos"]) or s["pos"].distance_to(base_pos) > _reach():
			continue
		var d: float = from.distance_to(s["pos"])
		if _fuel_for(d + s["pos"].distance_to(base_pos)) > budget:
			continue
		if d < best_score:
			return {"pos": s["pos"], "poi": null, "site": s["uid"], "land": false}
		break
	return best


## How far out the bot goes: farther each day, as a player learns the map (danger grows with distance, Game.danger_at).
func _reach() -> float:
	return REACH_START + REACH_PER_DAY * Game.day


func _poi_ok(p: Variant) -> bool:
	return is_instance_valid(p) and p.kind in LOOT and not p.done and not p.walking_home \
		and p.position.distance_to(main.base.global_position) > Game.base_radius + 140.0


func _camp_near(pos: Vector2) -> bool:
	for c in main.bandits.camps.values():
		if not c["cleared"] and c["pos"].distance_to(pos) < 900.0:
			return true
	for p in main.pois: # zombie dens call out an abomination
		if is_instance_valid(p) and p.kind == "nest" and not p.done and p.position.distance_to(pos) < 450.0:
			return true
	return false


## A landable spot within `reach` of `pos`, nearest first (the POI's own cell if it is).
func _landing_spot(pos: Vector2, reach: float) -> Vector2:
	for r in range(0, int(reach) + 1, 8):
		for i in 16:
			var at := pos + Vector2(r, 0).rotated(i * TAU / 16.0)
			if main.is_landable(at) and main.is_landable(at + Vector2(8, 0)) and main.is_landable(at - Vector2(8, 0)):
				return at
	return pos


## Steers with the move actions; true once within `near` px and slow.
func _fly_to(to: Vector2, near: float) -> bool:
	var heli: Node2D = Game.heli
	var off: Vector2 = to - heli.global_position
	var top: float = heli.MAX_SPEED * Game.stats["speed"] * Game.weight_factor
	var want := off.normalized() * minf(top, off.length() * 1.2)
	var steer: Vector2 = (want - heli.vel) / 25.0
	steer = steer.limit_length(1.0)
	_press("move_right", steer.x)
	_press("move_left", -steer.x)
	_press("move_down", steer.y)
	_press("move_up", -steer.y)
	return off.length() < near and heli.vel.length() < 45.0


func _press(action: String, v: float) -> void:
	if v > 0.05:
		Input.action_press(action, minf(1.0, v))
	else:
		Input.action_release(action)


func _release() -> void:
	for a in ["move_right", "move_left", "move_down", "move_up"]:
		Input.action_release(a)


func _nearest_attacker() -> Node2D:
	var best: Node2D = null
	var bd := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = e.global_position.distance_squared_to(Game.heli.global_position)
		if e.get("target_base") and d < bd and not e.is_queued_for_deletion():
			bd = d
			best = e
	return best


func _nearest_enemy(pos: Vector2, r: float) -> Node2D:
	var best: Node2D = null
	var bd := r * r
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = e.global_position.distance_squared_to(pos)
		if d < bd and not e.is_queued_for_deletion():
			bd = d
			best = e
	return best


## Door gun: turns the heli so the nearest enemy in range is out of the side door, and fires.
func _shoot(foe: Node2D) -> void:
	var heli: Node2D = Game.heli
	if foe == null or foe.global_position.distance_to(heli.global_position) > heli.weapon_range() * 0.7: # closer in: fewer misses
		Input.action_release("fire")
		heli.aim_override = Vector2.ZERO
		return
	var lead: Vector2 = foe.global_position - heli.global_position
	if aim_foe == foe:
		var v: Vector2 = (foe.global_position - aim_last) / maxf(get_process_delta_time(), 0.001)
		lead += v.limit_length(80.0) * lead.length() / 520.0 # where it will be when the round gets there (MG 520 px/s)
	aim_foe = foe
	aim_last = foe.global_position
	if not lead.is_finite() or lead == Vector2.ZERO:
		if not nan_said:
			nan_said = true
			print("LONGRUN note: non-finite aim at %s %s (%s)" % [foe.get("kind"), foe.global_position, foe.get_script().resource_path])
		Input.action_release("fire")
		return
	heli.aim_override = lead
	heli.body.rotation = lead.angle() # nose at right angles to the aim: the door gun bears
	heli.manual_yaw = 0.0
	Input.action_press("fire")


# ---------------------------------------------------------------- base management

func _manage() -> void:
	var base: Node2D = main.base
	if base.ui.visible:
		base.ui.close()
	_jobs()
	for part in main.wear.COMPONENTS:
		if main.wear.cond[part] < 55.0 and not main.wear.orders.has(part):
			main.wear.order_repair(part)
	if Game.base_hp < Game.max_base_hp * 0.6:
		base.ui.buy("repair")
	var keep := 15 # scrap kept for hull repairs
	var pop: int = Game.rescued
	var plans := []
	if Game.housing() + 4 * _queued("barracks") < pop + 2 and _queued("barracks") < 2 and Game.scrap >= Game.BUILDINGS["barracks"][1] + keep:
		_place("barracks")
	if Game.day >= 2 and Game.built("watchtower") + _queued("watchtower") == 0:
		plans.append("watchtower")
	if Game.injured > 0 and Game.built("clinic") + _queued("clinic") == 0:
		plans.append("clinic")
	if (Game.base_water < pop * 3.0 or not base.water_near()) and Game.built("well") + _queued("well") < 1 + pop / 10:
		plans.append("well")
	if pop >= 8 and Game.built("generator") + _queued("generator") == 0:
		plans.append("generator")
	for kind in plans:
		if Game.scrap >= Game.BUILDINGS[kind][1] + keep and base.next_site().is_empty():
			_place(kind)
	if base.next_site().is_empty():
		if Game.base_level.get("turrets", 0) < 4 and Game.scrap >= base.ui.cost("turrets") + keep: # turrets need no ammo
			base.ui.buy("turrets")
		elif Game.day >= 5 and Game.buildings.size() > 2 + base.perimeter_level() * 3 and Game.scrap >= base.building_cost("perimeter") + keep + 40:
			base.expand_perimeter()
		elif Game.day >= 4 and Game.base_level.get("armory", 0) < 3 and Game.scrap >= base.ui.cost("armory") + keep + 40:
			base.ui.buy("armory")
	var bags := mini(Game.SANDBAG_MAX, 10 + 3 * Game.day)
	var i := 0
	while Game.sandbags.size() < bags and Game.scrap >= Game.SANDBAG_COST + keep and i < 192: # rings 20, 36 and 52 px inside the fence
		var at: Vector2 = base.global_position + Vector2(Game.base_radius - 20.0 - 16.0 * (i / 64), 0).rotated((i % 64) * TAU / 64.0)
		base.place_sandbag(Vector2i((at / 16.0).floor()))
		i += 1


func _queued(kind: String) -> int:
	return Game.buildings.filter(func(b): return b["kind"] == kind and not b["built"]).size()


func _place(kind: String) -> bool:
	var base: Node2D = main.base
	var c0 := Vector2i((base.global_position / 16.0).floor())
	var r := int(Game.base_radius / 16.0)
	for d in range(3, r):
		for x in range(-d, d + 1):
			for y in [-d, d]:
				for cell in [c0 + Vector2i(x, y), c0 + Vector2i(y, x)]:
					if base.cell_pos(cell).distance_to(base.global_position) < Game.base_radius - 40.0 and base.place_building(kind, cell):
						return true
	return false


## Jobs from what the stocks need: water and food first, builders while there is work, militia, workshop, the rest on fuel/ammo/repair.
func _jobs() -> void:
	var base: Node2D = main.base
	for j in Game.workers:
		Game.workers[j] = 0
	var free: int = Game.rescued - Game.injured
	var eaters: float = Game.food_eaters()
	var w := {}
	var water_need: float = (Game.rescued + Game.campers()) * Game.WATER_PER_PERSON - Game.built("well") * Game.WELL_WATER * Game.wells()
	if base.water_near() and water_need > 0.0:
		w["water"] = ceili(water_need / Game.WORKER_RATE["water"] * (1.5 if Game.base_water < 3.0 * Game.rescued else 1.0))
	var food_need: float = eaters - Game.FIELD_FOOD * base.field_tiles()
	if food_need > 0.0:
		w["farm"] = ceili(food_need / Game.WORKER_RATE["farm"] * (1.3 if Game.base_food < 3.0 * eaters else 1.0))
	if not base.next_work().is_empty() or Game.sandbags.values().any(func(s): return not s["built"]):
		w["build"] = 2 if free < 8 else 3
	if Game.injured > 0 and Game.built("clinic") > 0:
		w["medic"] = 1
	w["militia"] = maxi(1, free / 4)
	if Game.salvage.values().any(func(v): return v >= 1.0):
		w["workshop"] = 1 if free < 10 else 2
	if Game.base_hp < Game.max_base_hp:
		w["repair"] = 1
	w["fuel"] = (1 + Game.rescued / 8) if Game.base_fuel < Game.base_fuel_cap * 0.6 else 0 # the heli burns ~250 a flying day
	w["ammo"] = (1 + Game.rescued / 8) if Game.base_ammo < Game.base_ammo_cap * 0.7 else 0
	for j in ["water", "farm", "build", "militia", "medic", "workshop", "repair", "fuel", "ammo"]:
		var n := mini(w.get(j, 0), free)
		Game.workers[j] = n
		free -= n
	Game.workers["militia"] += free # the rest stand guard


# ---------------------------------------------------------------- log

func _on_day(day: int) -> void:
	var d := day - 1 # the day that just ended
	if main.bandits.last_base_raid != last_raid and main.bandits.last_base_raid >= 0:
		last_raid = main.bandits.last_base_raid
		raids += 1
	var saved: int = Game.saved_count()
	var pts := d * 100 + saved * 25 + Game.kills # server/supabase run_points (no victory, factor 1)
	var res := assault_result if assault_day == d or assault_result == "running" else ""
	var vals := [d, Game.scrap, int(Game.salvage["metal"]), int(Game.salvage["parts"]), int(Game.salvage["electronics"]),
		int(Game.base_food), int(Game.base_water), int(Game.base_fuel), int(Game.base_ammo), Game.rescued, Game.injured, deaths,
		int(main.morale.value), Game.kills, int(Game.base_hp), res, wave if res != "" else 0, raids, pts, Game.level, sorties, delivered,
		int(Game.hp), Game.buildings.filter(func(b): return b["built"]).size(), Game.sandbags.size()]
	rows.append(",".join(vals.map(func(v): return str(v))))
	printerr("LONGRUN ", rows[-1], "  (%.0f s real, frames quiet/fly/fight %s)" % [Time.get_ticks_msec() / 1000.0, frames])
	frames = [0, 0, 0]
	if day > days:
		_finish("")


func _finish(why: String) -> void:
	if finished:
		return
	finished = true
	Engine.time_scale = 1.0
	_release()
	Input.action_release("fire")
	var out := OS.get_environment("LONGRUN_OUT")
	if out == "":
		out = ProjectSettings.globalize_path("res://build/longrun.csv")
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("# seed %d\n%s\n%s\n" % [Game.seed, ",".join(COLS), "\n".join(rows)])
	f.close()
	Save.delete_run()
	Game.meta = meta_keep # the bot's run must not count for the test profile
	Game._save_meta()
	if why != "":
		print("LONGRUN COLLAPSED ", why)
		get_tree().quit(1)
		return
	print("LONGRUN OK %d days, csv %s" % [days, out])
	get_tree().quit(0)
