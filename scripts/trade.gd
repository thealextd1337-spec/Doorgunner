extends Node
## Trade with allied villages (docs/ROADMAP3.md S2). main.gd keeps this node as `trade`; it saves itself (hook "trade"). trade_ui.gd is the window.
##
## Land beside an allied village (outposts.gd, P14) and press T (action "trade", touch: TRADE): buy with scrap, sell surplus food and
## water at poor rates. Every village has a small offer per day, rolled from (run seed, village, day) so the same day always shows the
## same stock; what is bought stays gone until the next day. Buying heats the price of that good (+step per unit, on top of the
## base price), selling cools the payout; the heat falls HEAT_RECOVER per day, so a village you leave alone returns to base prices.
##   buy(village, index) -> bool, sell(village, good) -> bool; *_problem() give the reason a button is greyed out ("" = fine).
## A recruit comes through Game.join(skill) like every other new person. Old saves have no "trade" entry: no prices, no heat.

const HEAT_RECOVER := 0.1 # price heat that goes away per day
const HEAT_MAX := 1.5 # price at most x2.5
const PERSON_CHANCE := 0.6 # a recruit is on offer on this share of the days
# buy: good -> label, base scrap price of one unit, what a unit holds, units on offer per day (lo, hi), heat added per unit bought
const GOODS := {
	"person": {"label": "Recruit", "unit": 1, "lo": 1, "hi": 1, "step": 0.4},
	"electronics": {"label": "Electronics", "base": 45, "unit": 5, "lo": 1, "hi": 3, "step": 0.25},
	"medicine": {"label": "Medicine", "base": 35, "unit": 2, "lo": 0, "hi": 2, "step": 0.25},
	"rifles": {"label": "Rifles", "base": 50, "unit": 1, "lo": 0, "hi": 2, "step": 0.25},
	"food": {"label": "Food", "base": 15, "unit": 10, "lo": 2, "hi": 5, "step": 0.1},
}
const PERSON_PRICE := {"mechanic": 80, "farmer": 70, "medic": 90, "soldier": 80, "builder": 70, "driver": 90, "engineer": 140}
# sell: good -> scrap paid for one batch of `unit`, days of use the base keeps back (nothing below that is sold)
const SELL := {
	"food": {"label": "Food", "unit": 10, "pay": 4, "keep_days": 3},
	"water": {"label": "Water", "unit": 10, "pay": 3, "keep_days": 3},
}
const SELL_STEP := 0.2 # payout lost per batch sold (heat), recovers like the buy heat
const SELL_FLOOR := 0.4 # the payout never drops below this share

var state := {} # village id -> {"day": day of the offer, "offer": [{good, skill, left}], "heat": {good or "sell_"+good: float}}
var available := false # a village is in reach and the heli is parked (touch button, HUD hint), rescanned 4x a second
var _scan_t := 0.0


func _ready() -> void:
	Save.register("trade", save_state, load_state)


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		available = can_open()


## The village the heli is parked beside, {} if none.
func village_here() -> Dictionary:
	var op: Node2D = Game.world.outposts
	if not Game.running or Game.heli == null or not op._parked():
		return {}
	return op.village_near(Game.heli.position, op.VILLAGE_REACH)


func can_open() -> bool:
	return not village_here().is_empty()


func hint() -> String:
	var v := village_here() if available else {}
	return "   %s trade with %s" % [KeyMap.tag("trade"), v["name"]] if not v.is_empty() else ""


# ---------------------------------------------------------------- offer and prices

## The sheet of village `id` for today: rolls the offer of a new day and lets the old heat cool down.
func sheet(id: String) -> Dictionary:
	var s: Dictionary = state.get(id, {"day": -1, "offer": [], "heat": {}})
	state[id] = s
	if s["day"] == Game.day:
		return s
	var gone: int = maxi(0, Game.day - s["day"]) if s["day"] >= 0 else 0
	for g in s["heat"].keys():
		s["heat"][g] = snappedf(maxf(0.0, s["heat"][g] - HEAT_RECOVER * gone), 0.01) # hundredths: no float drift in the prices
		if s["heat"][g] <= 0.0:
			s["heat"].erase(g)
	s["day"] = Game.day
	s["offer"] = _roll(id)
	return s


func _roll(id: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed, id, Game.day])
	var out := []
	for good in GOODS:
		var g: Dictionary = GOODS[good]
		if good == "person":
			if rng.randf() < PERSON_CHANCE:
				var skills: Dictionary = preload("res://scripts/people.gd").SKILL_WEIGHT
				out.append({"good": good, "skill": skills.keys()[rng.rand_weighted(PackedFloat32Array(skills.values()))], "left": 1})
			continue
		var n := rng.randi_range(g["lo"], g["hi"])
		if n > 0:
			out.append({"good": good, "skill": "", "left": n})
	return out


func offer(id: String) -> Array:
	return sheet(id)["offer"]


func heat(id: String, key: String) -> float:
	return sheet(id)["heat"].get(key, 0.0)


func _bump(id: String, key: String, by: float) -> void:
	var h: Dictionary = sheet(id)["heat"]
	h[key] = snappedf(minf(HEAT_MAX, h.get(key, 0.0) + by), 0.01)


## Scrap price of one unit of offer line `i`.
func price(id: String, i: int) -> int:
	var e: Dictionary = offer(id)[i]
	var base: int = PERSON_PRICE[e["skill"]] if e["good"] == "person" else GOODS[e["good"]]["base"]
	return ceili(snappedf(base * (1.0 + heat(id, e["good"])), 0.01))


## Scrap paid for one batch of `good` now.
func payout(id: String, good: String) -> int:
	return maxi(1, floori(snappedf(SELL[good]["pay"] * maxf(SELL_FLOOR, 1.0 - heat(id, "sell_" + good)), 0.01)))


func offer_text(e: Dictionary) -> String:
	if e["good"] == "person":
		return "Recruit: %s" % e["skill"]
	return "%s x%d" % [GOODS[e["good"]]["label"], GOODS[e["good"]]["unit"]]


# ---------------------------------------------------------------- buying and selling

func buy_problem(id: String, i: int) -> String:
	var list: Array = offer(id)
	if i < 0 or i >= list.size():
		return "Nothing like that on offer."
	if list[i]["left"] <= 0:
		return "Sold out today."
	if Game.scrap < price(id, i):
		return "Needs %d scrap." % price(id, i)
	return ""


func buy(id: String, i: int) -> bool:
	var why := buy_problem(id, i)
	if why != "":
		return false
	var e: Dictionary = offer(id)[i]
	var cost := price(id, i)
	Game.scrap -= cost
	e["left"] -= 1
	_bump(id, e["good"], GOODS[e["good"]]["step"])
	var unit: int = GOODS[e["good"]]["unit"]
	match e["good"]:
		"person":
			var p: Dictionary = Game.join(e["skill"])
			Game.radio("%s: %s, a %s, joins the base (%d scrap)." % [_name(id), p["name"], e["skill"], cost])
		"electronics":
			Game.salvage["electronics"] += unit
		"medicine":
			Game.base_medicine += unit
		"rifles":
			Game.base_rifles += unit
		"food":
			Game.base_food += unit
	if e["good"] != "person":
		Game.radio("%s: %s for %d scrap." % [_name(id), offer_text(e), cost])
	Sfx.play("pickup")
	return true


## The part of `good` that may be sold: what the base holds beyond `keep_days` days of use.
func spare(good: String) -> float:
	var have: float = Game.base_food if good == "food" else Game.base_water
	var use: float = Game.food_eaters() * Game.FOOD_PER_PERSON if good == "food" else Game.water_drinkers() * Game.WATER_PER_PERSON # same formulas as the daily tick
	return have - use * SELL[good]["keep_days"]


func sell_problem(id: String, good: String) -> String:
	if not SELL.has(good):
		return "They do not buy that."
	if spare(good) < SELL[good]["unit"]:
		return "Nothing to spare: the base keeps %d days of %s." % [SELL[good]["keep_days"], good]
	return ""


func sell(id: String, good: String) -> bool:
	if sell_problem(id, good) != "":
		return false
	var pay := payout(id, good)
	var unit: int = SELL[good]["unit"]
	if good == "food":
		Game.base_food -= unit
	else:
		Game.base_water -= unit
	Game.scrap += pay
	_bump(id, "sell_" + good, SELL_STEP)
	Game.radio("%s: %d %s sold for %d scrap." % [_name(id), unit, good, pay])
	Sfx.play("pickup")
	return true


func _name(id: String) -> String:
	var v: Dictionary = Game.world.outposts.allies.get(id, {})
	return v.get("name", "Village")


# ---------------------------------------------------------------- saving

func save_state() -> Dictionary:
	for id in state.keys(): # villages that fell take their sheet with them
		if not Game.world.outposts.allies.has(id):
			state.erase(id)
	return {"v": state}


func load_state(d: Dictionary) -> void:
	state = d.get("v", {})
