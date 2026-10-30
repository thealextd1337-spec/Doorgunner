extends Node2D
## Outposts and allied villages (docs/ROADMAP.md P14). main.gd keeps this node as `outposts`; it saves itself (hook "outposts").
##
## OUTPOST: land at a gas station, checkpoint or radio mast and press O. Costs FOUND_COST scrap and a crew of CREW people
## from the base, who must be flown there first: O on the base pad loads CREW healthy people (militia first), they sit in
## the cabin as passengers (person["post"] == LOADED, aboard) and Game.deliver() leaves them alone. O at the site founds the
## outpost: the crew becomes its garrison (aboard false, post = outpost id; they no longer count as Game.rescued, work or eat).
## An outpost is a pad with a fuel tank and an ammo crate: landing on it tops the heli up from the stock and saves the run.
## Gas stations deliver fuel, checkpoints ammo, every day. O on the pad of an outpost reinforces the garrison with a loaded
## crew, else deposits fuel and ammo the heli can spare. At most MAX_BASE + built watchtowers outposts.
## Outposts get raided at night by zombies (raid()) and by bandits (P11); the garrison defends, see defence().
##
## VILLAGE: a settlement (survivors POI) that has been cleared and still has people: land beside it and press P. The POI is
## finished (nobody boards), the people stay and become allies: every VILLAGE_DAYS days they leave food and water to pick up
## (landing beside the village), carried to the base pad (cargo). A village that is not visited for NEGLECT_DAYS days falls
## by chance, and falls when a raid beats its defence.
##
## API for P11 (bandits) and P13 (missions); ids are strings, "o<n>" for outposts and the POI uid for villages:
##   targets() -> Array of {id, kind "outpost"|"village", pos, defence, loot {fuel, ammo | food, water}}
##   raid(id, strength, source := "bandits") -> {held, hurt, died, fell}: resolves a raid at once, loot is not taken (bandits do that)
##   villages() -> Array of {id, name, pos, pop, stock {food, water}, last_visit, away_days, neglected}
##   village_near(pos, radius) -> village dictionary or {}
##   deliver(village_id, item, amount) -> bool: a delivery (P13 "Medicine run"): resets the neglect clock, emits village_delivered
## Signals: raided(id, result, source), fell(id, kind), village_delivered(id, item, amount).

signal raided(id: String, result: Dictionary, source: String)
signal fell(id: String, kind: String)
signal village_delivered(id: String, item: String, amount: float)

const FOUND_COST := 40 # scrap
const CREW := 2 # people loaded at the base for one outpost (or one reinforcement)
const GARRISON_MAX := 6
const MAX_BASE := 1 # outposts without a watchtower
const SITE_KINDS := ["gas_station", "checkpoint", "radio_mast"]
const SITE_REACH := 220.0 # px from the landmark centre the heli may land to found
const MIN_APART := 500.0 # px between outposts
const MIN_FROM_BASE := 700.0
const PAD_REACH := 48.0
const LOADED := "load" # person["post"] of a crew flown to an outpost
const FUEL_CAP := 80.0
const FUEL_START := 20.0
const AMMO_CAP := 200
const AMMO_START := 60
const SITE_YIELD := {"gas_station": {"fuel": 12.0}, "checkpoint": {"ammo": 8}, "radio_mast": {}} # per day
const SPARE_SHARE := 0.4 # depositing keeps this share of the tank and the ammo feed
const OUTPOST_HP := 100.0
const REPAIR_DAY := 20.0 # hull per day with a garrison
const HEAL_CHANCE := 0.5 # per injured garrison member per day
# defence of an outpost: per healthy garrison member (soldiers more), the heli's door gun close by, ammo from the crate
const DEF_PER_PERSON := 2.0
const SOLDIER_BONUS := 1.0
const HELI_HELP := 2.0
const HELI_HELP_RANGE := 300.0
const RAID_AMMO := 15 # crate ammo a raid uses; without it the defence halves
const NO_AMMO_DEFENCE := 0.5
const HP_PER_POINT := 15.0 # hull lost per point of strength beyond the defence
const CASUALTY_CHANCE := 0.3
const FALL_DEATH := 0.5 # share of the garrison that dies when the outpost falls (the rest walks home)
const RAID_NIGHT := 0.85 # time of day the night raids are rolled
const RAID_CHANCE := 0.2 # per outpost and night
const RAID_STRENGTH := 2.5 # times Game.danger_at(outpost)
const ALERT_SECONDS := 8.0
# villages
const VILLAGE_REACH := 64.0 # landing this close to a village counts
const VILLAGE_CLEAR := 220.0 # no enemy this close to protect
const VILLAGE_DAYS := 2
const FOOD_PER_PERSON := 3.0 # per VILLAGE_DAYS
const WATER_PER_PERSON := 2.0
const STOCK_CYCLES := 3 # a village stores this many deliveries
const NEGLECT_DAYS := 8
const FALL_CHANCE := 0.25 # per day once neglected
const VILLAGE_DEF_PER_PERSON := 0.5
const OUTPOST_COVER := 900.0 # garrisons this close add their defence to a village's
const PROTECT_XP := 25

const MAP_OK := Color(0.4, 0.9, 0.4)
const MAP_WARN := Color(1.0, 0.65, 0.2)
const MAP_ALERT := Color(1.0, 0.2, 0.2)

var list: Array = [] # outposts: {id, site, pos, fuel, ammo, hp, day}
var allies := {} # village POI uid -> {uid, name, pos, last_visit, next, stock {food, water}, gifts {item: amount}}
var cargo := {"food": 0.0, "water": 0.0} # picked up at villages, delivered on the base pad
var seq := 0
var vseq := 0
var night_day := 0 # last day the night raids were rolled
var alert := {} # outpost id -> seconds the red ring stays
var _nodes := {}
var _ctx := {}
var _scan_t := 0.0


func _ready() -> void:
	z_index = 1
	Game.heli.landed_changed.connect(_on_landed)
	Game.day_changed.connect(_on_day)
	Save.register("outposts", save_state, load_state)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	for id in alert.keys():
		alert[id] -= delta
		if alert[id] <= 0.0:
			alert.erase(id)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_ctx = _scan()
	if Game.time >= RAID_NIGHT and night_day != Game.day and Game.base_founded:
		night_day = Game.day
		night_raids()
	if not get_tree().paused:
		if Input.is_action_just_pressed("outpost") and _parked():
			press_o()
		if Input.is_action_just_pressed("protect") and _parked():
			protect()
	queue_redraw()


# ---------------------------------------------------------------- helpers

func _parked() -> bool:
	return Game.heli.landed and Game.heli.pending == 0


func garrison(id: String) -> Array:
	return Game.people.filter(func(p): return p.get("post", "") == id and not p["aboard"])


## The people flown to an outpost.
func crew() -> Array:
	return Game.people.filter(func(p): return p.get("post", "") == LOADED)


func outpost(id: String) -> Dictionary:
	for o in list:
		if o["id"] == id:
			return o
	return {}


func outpost_at(pos: Vector2) -> Dictionary:
	for o in list:
		if o["pos"].distance_to(pos) <= PAD_REACH:
			return o
	return {}


func max_outposts() -> int:
	return MAX_BASE + Game.built("watchtower")


func _on_base_pad() -> bool:
	var base: Node2D = Game.world.base
	return Game.base_founded and Game.heli.position.distance_to(base.position) <= base.PAD_REACH


## The landmark of SITE_KINDS under the heli, {} if none.
func site_here() -> Dictionary:
	for s in Game.world.chunks.sites_near(Game.heli.position, SITE_REACH):
		if s["kind"] in SITE_KINDS:
			return s
	return {}


## Defence points of an outpost: garrison, heli help, ammo.
func defence(o: Dictionary) -> float:
	var d := 0.0
	for p in garrison(o["id"]):
		if not p["injured"]:
			d += DEF_PER_PERSON + (SOLDIER_BONUS if p["skill"] == "soldier" else 0.0)
	if is_instance_valid(Game.heli) and Game.heli.position.distance_to(o["pos"]) <= HELI_HELP_RANGE and d > 0.0:
		d += HELI_HELP
	return d * (1.0 if o["ammo"] >= RAID_AMMO else NO_AMMO_DEFENCE)


# ---------------------------------------------------------------- crew and founding

## O (or the HUD) on the base pad: load CREW healthy people (militia, then soldiers, then the idle) for an outpost, or put them back.
func load_crew() -> bool:
	if not _parked() or not _on_base_pad():
		return false
	if not crew().is_empty():
		for p in crew():
			p["aboard"] = false
			p["post"] = ""
		Game.radio("Base: outpost crew back at the barracks.")
		return true
	if Game.seats - Game.passengers < CREW:
		Game.radio("Pilot: no room for %d more aboard." % CREW)
		return false
	var pool: Array = Game.people.filter(func(p): return not p["aboard"] and p.get("post", "") == "" and not p["injured"])
	if pool.size() < CREW:
		Game.radio("Base: we need %d healthy people to man an outpost." % CREW)
		return false
	var fit := func(p: Dictionary) -> float: return (2.0 if p["job"] == "militia" else 0.0) + (1.0 if p["skill"] == "soldier" else 0.0) + (0.5 if p["job"] == "" else 0.0)
	pool.sort_custom(func(a, b): return fit.call(a) > fit.call(b) or (fit.call(a) == fit.call(b) and a["id"] < b["id"]))
	for p in pool.slice(0, CREW):
		p["aboard"] = true
		p["post"] = LOADED
		p["job"] = ""
		p["pin"] = ""
	Game._fit_workers()
	Game.radio("Base: %d militia aboard for an outpost. Land at a gas station, checkpoint or radio mast and press O." % CREW)
	return true


## "" when an outpost can be founded under the heli, else why not.
func found_problem() -> String:
	if not _parked():
		return "Pilot: land first."
	if not Game.base_founded:
		return "Command: found the base first."
	if site_here().is_empty():
		return "Pilot: no gas station, checkpoint or radio mast to hold here."
	if list.size() >= max_outposts():
		return "Command: we can hold %d outpost(s). Watchtowers at the base raise the limit." % max_outposts()
	if Game.heli.position.distance_to(Game.world.base.position) < MIN_FROM_BASE:
		return "Command: too close to the base for an outpost."
	for o in list:
		if o["pos"].distance_to(Game.heli.position) < MIN_APART:
			return "Command: too close to another outpost."
	if crew().is_empty():
		return "Pilot: no crew aboard. Load %d militia at the base pad first (O)." % CREW
	if Game.scrap < FOUND_COST:
		return "Command: an outpost costs %d scrap." % FOUND_COST
	return ""


func found() -> bool:
	var why := found_problem()
	if why != "":
		Game.radio(why)
		return false
	var site := site_here()
	Game.scrap -= FOUND_COST
	seq += 1
	var o := {"id": "o%d" % seq, "site": site["kind"], "pos": Game.heli.position, "fuel": FUEL_START, "ammo": AMMO_START, "hp": OUTPOST_HP, "day": Game.day}
	list.append(o)
	_post_crew(o)
	Game.radio("Outpost %d set up at the %s. %s Land here to refuel and rearm." % [seq, site["kind"].replace("_", " "), SITE_NOTE.get(site["kind"], "")])
	Game.add_xp(PROTECT_XP)
	Sfx.play("pickup")
	Save.autosave()
	return true


const SITE_NOTE := {"gas_station": "The pumps will fill its tank.", "checkpoint": "The armoury will fill its crate.", "radio_mast": "Bring it fuel and ammo."}


func _post_crew(o: Dictionary) -> void:
	for p in crew():
		p["aboard"] = false
		p["post"] = o["id"]
	_rebuild(o)


## O on the pad of an outpost: a loaded crew reinforces the garrison, else spare fuel and ammo go into the stock.
func reinforce_or_deposit(o: Dictionary) -> bool:
	if not crew().is_empty():
		if garrison(o["id"]).size() + CREW > GARRISON_MAX:
			Game.radio("Outpost %d: the garrison is full." % o["id"].substr(1).to_int())
			return false
		_post_crew(o)
		Game.radio("Outpost %d: reinforced, %d on the walls." % [o["id"].substr(1).to_int(), garrison(o["id"]).size()])
		return true
	var f := minf(maxf(0.0, Game.fuel - Game.max_fuel * SPARE_SHARE), FUEL_CAP - o["fuel"])
	var a := mini(maxi(0, Game.ammo - int(Game.max_ammo * SPARE_SHARE)), AMMO_CAP - o["ammo"])
	if f < 1.0 and a < 1:
		Game.radio("Pilot: nothing to spare for the outpost stock.")
		return false
	Game.fuel -= f
	Game.ammo -= a
	o["fuel"] += f
	o["ammo"] += a
	Game.radio("Outpost %d: stocked +%d fuel, +%d ammo." % [o["id"].substr(1).to_int(), f, a])
	return true


func press_o() -> bool:
	if _on_base_pad():
		return load_crew()
	var o := outpost_at(Game.heli.position)
	if not o.is_empty():
		return reinforce_or_deposit(o)
	return found()


## Landing on an outpost: fuel and ammo from its stock, then the run is saved.
func _service(o: Dictionary) -> void:
	var f := minf(Game.max_fuel - Game.fuel, o["fuel"])
	var a := mini(Game.max_ammo - Game.ammo, int(o["ammo"]))
	Game.fuel += f
	Game.ammo += a
	o["fuel"] -= f
	o["ammo"] -= a
	var n: int = o["id"].substr(1).to_int()
	Game.radio("Outpost %d: +%d fuel, +%d ammo from the stock (%d fuel, %d ammo left). Position saved." % [n, f, a, o["fuel"], o["ammo"]])
	Sfx.play("pickup")
	Save.autosave()


func _on_landed(landed: bool) -> void:
	if not landed:
		return
	var o := outpost_at(Game.heli.position)
	if not o.is_empty():
		_service(o)
	var v := village_near(Game.heli.position, VILLAGE_REACH)
	if not v.is_empty():
		_pickup(allies[v["id"]])
	if _on_base_pad() and (cargo["food"] > 0.0 or cargo["water"] > 0.0):
		Game.base_food += cargo["food"]
		Game.base_water += cargo["water"]
		Game.radio("Base: villages sent %d food and %d water." % [cargo["food"], cargo["water"]])
		cargo = {"food": 0.0, "water": 0.0}
		Save.autosave()


# ---------------------------------------------------------------- raids

## A raid of `strength` on outpost or village `id`. The defence is weighed against the strength: an outpost loses hull for the
## excess and its healthy garrison gets hurt (the hurt may die); at 0 hull it falls and half of the garrison dies, the rest
## walks home. A village loses people for the excess and falls when none are left. {held, hurt, died, fell}.
func raid(id: String, strength: float, source := "bandits") -> Dictionary:
	var res := {"held": true, "hurt": 0, "died": 0, "fell": false}
	var o := outpost(id)
	if not o.is_empty():
		_raid_outpost(o, strength, res)
	elif allies.has(id):
		_raid_village(allies[id], strength, res)
	else:
		return {}
	raided.emit(id, res, source)
	return res


func _raid_outpost(o: Dictionary, strength: float, res: Dictionary) -> void:
	var def := defence(o)
	if o["ammo"] >= RAID_AMMO:
		o["ammo"] -= RAID_AMMO
	var excess := maxf(0.0, strength - def)
	res["held"] = excess <= 0.0
	o["hp"] -= excess * HP_PER_POINT
	alert[o["id"]] = ALERT_SECONDS
	var crew_here := garrison(o["id"])
	var healthy := crew_here.filter(func(p): return not p["injured"])
	var hurt := int(excess / DEF_PER_PERSON) + int(strength > def * 0.5 and randf() < CASUALTY_CHANCE)
	for p in crew_here: # the hurt of an earlier raid are in the way
		if p["injured"] and excess > 0.0 and randf() < 0.5:
			_kill(p)
			res["died"] += 1
	for p in healthy.slice(0, mini(hurt, healthy.size())):
		p["injured"] = true
		res["hurt"] += 1
	var n: int = o["id"].substr(1).to_int()
	if o["hp"] <= 0.0:
		res["fell"] = true
		for p in garrison(o["id"]):
			if randf() < FALL_DEATH:
				_kill(p)
				res["died"] += 1
			else:
				p["post"] = ""
		list.erase(o)
		_free_node(o["id"])
		Game.radio("ALERT: Outpost %d has fallen! %d lost." % [n, res["died"]])
		fell.emit(o["id"], "outpost")
	elif res["held"]:
		Game.radio("Outpost %d held against the raid%s." % [n, ", %d hurt" % res["hurt"] if res["hurt"] > 0 else ""])
		_rebuild(o)
	else:
		Game.radio("Outpost %d is hurt: hull %d%%, %d hurt." % [n, o["hp"], res["hurt"]])
		_rebuild(o)


func _kill(p: Dictionary) -> void:
	Game.people.erase(p)
	Game.person_lost.emit(p, true)


func _raid_village(v: Dictionary, strength: float, res: Dictionary) -> void:
	var def := village_defence(v)
	var excess := maxf(0.0, strength - def)
	res["held"] = excess <= 0.0
	var poi := _poi(v["uid"])
	var lose := mini(ceili(excess / 2.0), poi.survivors.size()) if poi else 0
	for i in lose:
		var s: Node2D = poi.survivors.pop_back()
		Game.world.spawn_fx(s.global_position, 0.5)
		s.queue_free()
	res["died"] = lose
	if poi == null or poi.survivors.is_empty():
		res["fell"] = true
		_village_falls(v)
	elif lose > 0:
		Game.radio("Radio: %s was raided, %d left." % [v["name"], poi.survivors.size()])


func village_defence(v: Dictionary) -> float:
	var poi := _poi(v["uid"])
	var d: float = (poi.survivors.size() if poi else 0) * VILLAGE_DEF_PER_PERSON
	for o in list:
		if o["pos"].distance_to(v["pos"]) <= OUTPOST_COVER:
			d += defence(o)
	return d


## Night raids: each outpost has RAID_CHANCE per night to be hit by zombies, strength grows with the danger there.
func night_raids(force := false) -> void:
	for o in list.duplicate():
		if force or randf() < RAID_CHANCE:
			raid(o["id"], RAID_STRENGTH * Game.danger_at(o["pos"]), "zombies")


func targets() -> Array:
	var out := []
	for o in list:
		out.append({"id": o["id"], "kind": "outpost", "pos": o["pos"], "defence": defence(o), "loot": {"fuel": o["fuel"], "ammo": o["ammo"]}})
	for v in allies.values():
		out.append({"id": v["uid"], "kind": "village", "pos": v["pos"], "defence": village_defence(v), "loot": v["stock"].duplicate()})
	return out


# ---------------------------------------------------------------- villages

func _poi(uid: String) -> Node2D:
	for p in Game.world.pois:
		if is_instance_valid(p) and p.uid == uid:
			return p
	return null


## P, landed beside a cleared settlement that still has people: it stays and becomes an ally.
func protect() -> bool:
	var best: Node2D = null
	for p in Game.world.pois:
		if is_instance_valid(p) and p.kind == "survivors" and not p.done and not p.walking_home and not p.survivors.is_empty() \
				and p.position.distance_to(Game.heli.position) <= VILLAGE_REACH and (best == null or p.position.distance_to(Game.heli.position) < best.position.distance_to(Game.heli.position)):
			best = p
	if best == null or not _parked():
		return false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.global_position.distance_to(best.position) < VILLAGE_CLEAR:
			Game.radio("Gunner: hostiles still around the settlement. Clear them first.")
			return false
	vseq += 1
	allies[best.uid] = {"uid": best.uid, "name": "Village %d" % vseq, "pos": best.position, "last_visit": Game.day, "next": Game.day + VILLAGE_DAYS,
		"stock": {"food": 0.0, "water": 0.0}, "gifts": {}}
	best._stop_loading()
	best.done = true # nobody boards any more, and the horde leaves it alone (main._settlements_decline)
	best.ring_shown = false
	best.queue_redraw()
	for s in best.survivors:
		s.visible = true
	Game.radio("Village %d now stands with us: %d people stay. They leave food and water for pickup every %d days. Visit them." % [vseq, best.survivors.size(), VILLAGE_DAYS])
	Game.add_xp(PROTECT_XP)
	Game.world.morale.add(3.0, "village protected")
	Save.autosave()
	return true


func _pickup(v: Dictionary) -> void:
	v["last_visit"] = Game.day
	var f: float = v["stock"]["food"]
	var w: float = v["stock"]["water"]
	if f + w > 0.0:
		cargo["food"] += f
		cargo["water"] += w
		v["stock"] = {"food": 0.0, "water": 0.0}
		Game.radio("%s: loaded %d food and %d water. Take it to the base." % [v["name"], f, w])
	else:
		Game.radio("%s: nothing ready yet, next delivery in %d day(s)." % [v["name"], maxi(0, v["next"] - Game.day)])


func villages() -> Array:
	var out := []
	for v in allies.values():
		var poi := _poi(v["uid"])
		var away: int = Game.day - v["last_visit"]
		out.append({"id": v["uid"], "name": v["name"], "pos": v["pos"], "pop": poi.survivors.size() if poi else 0, "stock": v["stock"].duplicate(),
			"last_visit": v["last_visit"], "away_days": away, "neglected": away >= NEGLECT_DAYS - 3})
	return out


func village_near(pos: Vector2, radius: float) -> Dictionary:
	for v in villages():
		if v["pos"].distance_to(pos) <= radius:
			return v
	return {}


## A delivery to a village (P13 "Medicine run"). The caller takes the goods from the base; this resets the neglect clock.
func deliver(id: String, item: String, amount: float) -> bool:
	if not allies.has(id):
		return false
	allies[id]["last_visit"] = Game.day
	allies[id]["gifts"][item] = allies[id]["gifts"].get(item, 0.0) + amount
	village_delivered.emit(id, item, amount)
	return true


func _village_falls(v: Dictionary) -> void:
	var poi := _poi(v["uid"])
	if poi:
		for s in poi.survivors:
			s.queue_free()
		poi.survivors.clear()
	allies.erase(v["uid"])
	Game.radio("Radio: %s has fallen. We lost contact." % v["name"])
	Game.world.morale.add(-4.0, "village lost")
	fell.emit(v["uid"], "village")


func _on_day(day: int) -> void:
	for o in list:
		var y: Dictionary = SITE_YIELD.get(o["site"], {})
		o["fuel"] = minf(FUEL_CAP, o["fuel"] + y.get("fuel", 0.0))
		o["ammo"] = mini(AMMO_CAP, o["ammo"] + int(y.get("ammo", 0)))
		var crew_here := garrison(o["id"])
		if not crew_here.is_empty():
			o["hp"] = minf(OUTPOST_HP, o["hp"] + REPAIR_DAY)
		for p in crew_here:
			if p["injured"] and randf() < HEAL_CHANCE:
				p["injured"] = false
		_rebuild(o)
	for v in allies.values():
		var poi := _poi(v["uid"])
		if poi == null or poi.survivors.is_empty():
			_village_falls(v)
			continue
		if day >= v["next"]:
			v["next"] = day + VILLAGE_DAYS
			var n: int = poi.survivors.size()
			v["stock"]["food"] = minf(v["stock"]["food"] + n * FOOD_PER_PERSON, n * FOOD_PER_PERSON * STOCK_CYCLES)
			v["stock"]["water"] = minf(v["stock"]["water"] + n * WATER_PER_PERSON, n * WATER_PER_PERSON * STOCK_CYCLES)
		var away: int = day - v["last_visit"]
		if away == NEGLECT_DAYS - 2:
			Game.radio("Radio: %s has not seen us for %d days. Visit them." % [v["name"], away])
		elif away >= NEGLECT_DAYS and randf() < FALL_CHANCE:
			_village_falls(v)


# ---------------------------------------------------------------- HUD

## Where O / P would act at the heli's spot, rescanned 4x a second while landed.
func _scan() -> Dictionary:
	var out := {"o": "", "p": false}
	if not _parked():
		return out
	if _on_base_pad():
		out["o"] = "unload the outpost crew" if not crew().is_empty() else "load %d militia for an outpost" % CREW
	elif not outpost_at(Game.heli.position).is_empty():
		out["o"] = "reinforce the outpost" if not crew().is_empty() else "stock the outpost with spare fuel and ammo"
	elif not site_here().is_empty():
		out["o"] = "hold this %s (%d scrap, %d militia)" % [site_here()["kind"].replace("_", " "), FOUND_COST, CREW]
	for p in Game.world.pois:
		if is_instance_valid(p) and p.kind == "survivors" and not p.done and not p.survivors.is_empty() and p.position.distance_to(Game.heli.position) <= VILLAGE_REACH:
			out["p"] = true
	return out


## Extra hint text for the landed HUD line.
func hint() -> String:
	return ("   [O] " + _ctx["o"] if _ctx.get("o", "") != "" else "") + ("   [P] protect this settlement" if _ctx.get("p", false) else "")


func status() -> String:
	if list.is_empty() and allies.is_empty():
		return ""
	return "\nOUTPOSTS %d/%d  VILLAGES %d%s" % [list.size(), max_outposts(), allies.size(), "  CARGO %d food %d water" % [cargo["food"], cargo["water"]] if cargo["food"] + cargo["water"] > 0.0 else ""]


## Minimap markers: outposts as squares (green held, orange hurt or unmanned, red blinking under attack), villages as diamonds
## (green, yellow when neglected).
func draw_map(canvas: Control, to_map: Callable) -> void:
	for o in list:
		var col := MAP_OK
		if alert.has(o["id"]):
			col = MAP_ALERT if fmod(Time.get_ticks_msec() / 250.0, 2.0) < 1.0 else MAP_WARN
		elif o["hp"] < OUTPOST_HP * 0.5 or defence(o) <= 0.0:
			col = MAP_WARN
		var at: Vector2 = to_map.call(o["pos"])
		canvas.draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color.BLACK)
		canvas.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), col)
	for v in villages():
		var at: Vector2 = to_map.call(v["pos"])
		var col := MAP_WARN if v["neglected"] else MAP_OK
		canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -5), at + Vector2(5, 0), at + Vector2(0, 5), at + Vector2(-5, 0)]), Color.BLACK)
		canvas.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -4), at + Vector2(4, 0), at + Vector2(0, 4), at + Vector2(-4, 0)]), col)


# ---------------------------------------------------------------- world look

func _draw() -> void:
	for o in list:
		var col := MAP_OK if defence(o) > 0.0 else MAP_WARN
		if alert.has(o["id"]):
			col = MAP_ALERT
			draw_arc(o["pos"], 44.0, 0.0, TAU, 32, Color(1, 0.2, 0.2, 0.6), 2.0)
		draw_rect(Rect2(o["pos"] - Vector2(36, 30), Vector2(72, 60)), Color(0.3, 0.28, 0.2, 0.9), false, 1.5) # fence
		draw_line(o["pos"] + Vector2(0, -30), o["pos"] + Vector2(0, -52), Color(0.25, 0.25, 0.25), 1.5)
		draw_colored_polygon(PackedVector2Array([o["pos"] + Vector2(0, -52), o["pos"] + Vector2(12, -47), o["pos"] + Vector2(0, -42)]), col)
	for v in allies.values():
		var col := MAP_WARN if Game.day - v["last_visit"] >= NEGLECT_DAYS - 3 else MAP_OK
		draw_line(v["pos"] + Vector2(0, -8), v["pos"] + Vector2(0, -32), Color(0.25, 0.25, 0.25), 1.5)
		draw_colored_polygon(PackedVector2Array([v["pos"] + Vector2(0, -32), v["pos"] + Vector2(12, -27), v["pos"] + Vector2(0, -22)]), col)


func _free_node(id: String) -> void:
	if _nodes.has(id):
		_nodes[id].queue_free()
		_nodes.erase(id)


## The pad, tank, crate, posts and garrison of one outpost as sprites (rebuilt whenever the garrison changes).
func _rebuild(o: Dictionary) -> void:
	_free_node(o["id"])
	var n := Node2D.new()
	n.position = o["pos"]
	var pad := Art.sprite("helipad")
	pad.scale *= 0.7
	pad.modulate = Color(0.85, 0.9, 0.8)
	n.add_child(pad)
	for part in [["fuel_tank", Vector2(-26, -14)], ["crate", Vector2(26, -14)], ["turret", Vector2(-26, 20)], ["turret", Vector2(26, 20)]]:
		var s := Art.sprite(part[0])
		s.position = part[1]
		n.add_child(s)
	var g := garrison(o["id"])
	for i in g.size():
		var s := Art.sprite("survivor")
		s.position = Vector2(0, -22).rotated(i * TAU / maxi(1, g.size()) + 0.4)
		s.modulate = Color(1, 0.5, 0.5) if g[i]["injured"] else Color.WHITE
		n.add_child(s)
	add_child(n)
	_nodes[o["id"]] = n


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	return {"list": list, "allies": allies, "cargo": cargo, "seq": seq, "vseq": vseq, "night_day": night_day}


func load_state(d: Dictionary) -> void:
	for id in _nodes.keys():
		_free_node(id)
	list.assign(d["list"])
	allies = d["allies"]
	cargo = d["cargo"]
	seq = d["seq"]
	vseq = d["vseq"]
	night_day = d["night_day"]
	for o in list:
		_rebuild(o)
