class_name Events
extends Node
## Q13 radio events with choices (docs/ROADMAP2.md Q13). Cards are data (event_cards.gd); this runs them:
## every GAP seconds of flight a card whose conditions hold is offered (from FIRST_DAY, base founded, not in an assault,
## never the tutorial), chosen with the cooldown and weight of the card. An option can start a chain: a follow-up card some
## days later. The card shows in choice_ui.gd (one queue with the level-up cards, never two at once); the game does not pause
## and the radio waits TIMEOUT s, then takes the default option.
## Other packages: `Events.offer(id, ctx)` (ctx: strings/numbers for {keys} in the card text), `Events.register(id, card)` for
## more cards, and the signal `Game.world.events.chosen(id, option)`. Saves itself (hook "events").
## Bandit attitude `mood` (-3..3): friendly (TRUCE_MOOD) means no random bandit raid on the base (bandits.gd), hostile
## opens ambush cards; it drifts back to 0.

signal chosen(id: String, option: int)

const KEY := "radio_events" # ESC menu switch
const FIRST_DAY := 2
const GAP := Vector2(300.0, 500.0) # s between two random cards
const RETRY := 30.0 # s until the next try when no card fits
const TIMEOUT := 60.0 # s the radio waits for an answer
const COOLDOWN := 6 # days before a card comes again (card "cd" overrides)
const MOOD_MAX := 3
const TRUCE_MOOD := 2
const MOOD_DRIFT_DAYS := 4 # every Nth day the mood moves 1 towards 0
const BASE_REACH := 420.0 # px from the base pad that count as "at the base"
const SPAWN_RING := Vector2(420.0, 600.0) # px around the base / heli the zombies of a card appear
const MIN_HULL := 1.0 # a card never kills the heli
const Cards := preload("res://scripts/event_cards.gd")
# need / fx key -> [Game property, cap property or ""]; "parts" is Game.salvage["parts"], "xp" goes through add_xp
const RES := {"scrap": ["scrap", ""], "food": ["base_food", ""], "water": ["base_water", ""], "fuel": ["base_fuel", "base_fuel_cap"],
	"ammo": ["base_ammo", "base_ammo_cap"], "medicine": ["base_medicine", ""], "rifles": ["base_rifles", ""], "hull": ["hp", "max_hp"],
	"heli_fuel": ["fuel", "max_fuel"], "heli_ammo": ["ammo", "max_ammo"]}

static var extra := {} # cards other packages registered (id -> card)

var last := {} # card id -> day it was offered
var chains := [] # {id, day, ctx} follow-ups due on `day`
var shown := [] # {id, ctx}: open or queued cards (saved: they come back after a load)
var mood := 0
var timer := GAP.x
var _redo := []


static func register(id: String, card: Dictionary) -> void:
	extra[id] = card


## Offers card `id` now (conditions and cooldown are the caller's business). False for an unknown card or outside a run.
static func offer(id: String, ctx := {}) -> bool:
	var ev: Node = Game.world.get("events") if is_instance_valid(Game.world) else null
	return ev != null and ev.add(id, ctx)


## No random bandit raid on the base while the bandits like us.
static func truce() -> bool:
	var ev: Node = Game.world.get("events") if is_instance_valid(Game.world) else null
	return ev != null and ev.mood >= TRUCE_MOOD


func _ready() -> void:
	if not Settings.defs.has(KEY):
		Settings.register_toggle(KEY, "Radio events", true)
	Save.register("events", save_state, load_state)
	Game.day_changed.connect(_on_day)


func _on_day(d: int) -> void:
	if d % MOOD_DRIFT_DAYS == 0:
		mood -= signi(mood)


func _process(delta: float) -> void:
	if not Game.running or not Game.base_founded or Game.heli == null or is_instance_valid(Game.world.tutorial):
		return
	if not _redo.is_empty():
		for r: Dictionary in _redo:
			add(r["id"], r["ctx"], false)
		_redo.clear()
	if not shown.is_empty() or Game.attack_active:
		return
	for c: Dictionary in chains:
		if Game.day >= c["day"]:
			chains.erase(c)
			add(c["id"], c["ctx"])
			return
	timer -= delta
	if timer > 0.0 or Game.day < FIRST_DAY or Game.attack_pending or not Settings.is_on(KEY):
		return
	var id := pick()
	timer = randf_range(GAP.x, GAP.y) if id != "" else RETRY
	if id != "":
		add(id, {})


func card(id: String) -> Dictionary:
	return Cards.CARDS.get(id, extra.get(id, {}))


## Puts card `id` in the choice_ui queue. `stamp`: remember the day (cooldown).
func add(id: String, ctx := {}, stamp := true) -> bool:
	if card(id).is_empty() or Game.world.choice_ui == null:
		push_warning("Events: unknown card " + id)
		return false
	ctx = ctx.duplicate()
	if not ctx.has("name"):
		var who: Array = Game.people.filter(func(p): return p.get("post", "") == "")
		ctx["name"] = who.pick_random()["name"] if not who.is_empty() else "someone"
	if stamp:
		last[id] = Game.day
	shown.append({"id": id, "ctx": ctx})
	Game.world.choice_ui.open_event(id, ctx)
	return true


## A random card whose conditions hold and whose cooldown is over ("" if none), by weight.
func pick() -> String:
	var ids := eligible()
	if ids.is_empty():
		return ""
	var total := 0.0
	for id: String in ids:
		total += card(id).get("w", 1.0)
	var r := randf() * total
	for id: String in ids:
		r -= card(id).get("w", 1.0)
		if r <= 0.0:
			return id
	return ids[-1]


func eligible() -> Array:
	var out := []
	if Game.mode == "daily": # the daily is the same run for everyone: no random cards (chapters and hints stay)
		return out
	for id: String in Cards.CARDS.keys() + extra.keys():
		var c := card(id)
		if not c.get("chain_only", false) and Game.day - last.get(id, -1000) >= c.get("cd", COOLDOWN) and holds(c.get("when", {})):
			out.append(id)
	return out


## The conditions of a card (see event_cards.gd).
func holds(w: Dictionary) -> bool:
	var m: Node = Game.world.morale
	var base_d: float = Game.heli.global_position.distance_to(Game.world.base.global_position)
	var camps: bool = Game.world.bandits.camps.values().any(func(c): return not c["cleared"])
	var ok: bool = Game.day >= w.get("day", 0) and Game.day <= w.get("day_max", 1 << 30) and Game.rescued >= w.get("people", 0) and Game.rescued <= w.get("people_max", 1 << 30) \
		and m.value >= w.get("morale_min", 0) and m.value <= w.get("morale_max", 100) and mood >= w.get("mood_min", -MOOD_MAX) and mood <= w.get("mood_max", MOOD_MAX) \
		and (not w.has("camps") or camps == w["camps"]) and (not w.has("night") or Game.is_night() == w["night"]) \
		and (not w.get("seat", false) or Game.passengers < Game.seats) and Game.hp <= w.get("hull_below", 2.0) * Game.max_hp
	match w.get("place", ""):
		"base": ok = ok and base_d < BASE_REACH
		"air": ok = ok and base_d >= BASE_REACH and not Game.heli.landed
	for k: String in w.get("res", {}):
		ok = ok and stock(k) >= w["res"][k]
	for k: String in w.get("low", {}):
		ok = ok and stock(k) < w["low"][k]
	for k: String in w.get("built", []):
		ok = ok and Game.built(k) > 0
	for k: String in w.get("workers", {}):
		ok = ok and Game.workers.get(k, 0) >= w["workers"][k]
	return ok


## What choice_ui shows: {title, from, text, default, opts [{t, h, ok}]}. `ok` false: the need is not met.
func view(id: String, ctx: Dictionary) -> Dictionary:
	var c := card(id)
	var opts := []
	for o: Dictionary in c["opts"]:
		opts.append({"t": o["t"], "h": o.get("h", ""), "ok": affordable(o)})
	var def: int = c.get("default", opts.size() - 1)
	while not opts[def]["ok"] and def > 0: # a default nobody can pay falls back to the next free one
		def -= 1
	if not opts[def]["ok"]: # still locked (e.g. default 0): the first free option, or the card would wait forever
		def = maxi(0, opts.map(func(o): return o["ok"]).find(true))
	return {"title": c["title"], "from": c["from"], "text": c["text"].format(ctx), "default": def, "opts": opts}


func affordable(o: Dictionary) -> bool:
	return o.get("need", {}).keys().all(func(k): return stock(k) >= o["need"][k])


## Option `i` of the open card: its consequences, the follow-up, the signal.
func resolve(id: String, ctx: Dictionary, i: int) -> void:
	var o: Dictionary = card(id)["opts"][i]
	for s: Dictionary in shown:
		if s["id"] == id and s["ctx"] == ctx:
			shown.erase(s)
			break
	if Game.passengers + int(o.get("fx", {}).get("aboard", 0)) > Game.seats: # the seat filled up while the card was open
		Game.radio("Pilot: no free seat any more. We had to leave them.")
		chosen.emit(id, i)
		return
	_apply(o.get("fx", {}), ctx)
	var risk: Array = o.get("risk", [])
	if not risk.is_empty() and randf() < risk[0]:
		_apply(risk[1], ctx)
		Game.radio(risk[2].format(ctx))
	elif o.has("out"):
		Game.radio(o["out"].format(ctx))
	if o.has("chain"):
		chains.append({"id": o["chain"][0], "day": Game.day + int(o["chain"][1]), "ctx": {"name": ctx.get("name", "someone")}})
	chosen.emit(id, i)


func stock(k: String) -> float:
	return Game.salvage["parts"] if k == "parts" else float(Game.get(RES[k][0]))


func change(k: String, amount: float) -> void:
	if k == "parts":
		Game.salvage["parts"] = maxf(0.0, Game.salvage["parts"] + amount)
		return
	var prop: String = RES[k][0]
	var cur = Game.get(prop)
	var v := maxf(MIN_HULL if k == "hull" else 0.0, float(cur) + amount)
	if RES[k][1] != "":
		v = minf(v, float(Game.get(RES[k][1])))
	Game.set(prop, int(v) if typeof(cur) == TYPE_INT else v)


func _apply(fx: Dictionary, ctx: Dictionary) -> void:
	for k: String in fx:
		var v = fx[k]
		match k:
			"xp": Game.add_xp(int(v))
			"morale": Game.world.morale.add(v, "radio event")
			"mood": mood = clampi(mood + int(v), -MOOD_MAX, MOOD_MAX)
			"join":
				for n in int(v):
					Game.join(fx.get("join_skill", ""))
			"aboard": Game.passengers += int(v)
			"aboard_hurt": Game.passengers_injured += int(v)
			"hurt": Game.injure(int(v))
			"die":
				for i in int(v):
					Game.lose_person()
			"leave":
				for i in int(v):
					Game.walk_out()
			"mission":
				if Game.world.missions.offer(v).is_empty():
					Game.radio("Command: no crew free for it. The lead goes cold.")
			"zombies": _zombies(int(v))
			"raid": Game.world.bandits.base_raid()
			"join_skill": pass
			_: change(k, float(v))


## n infected arrive around the base (heli at the base: they come for it) or around the heli.
func _zombies(n: int) -> void:
	var at_base: bool = Game.heli.global_position.distance_to(Game.world.base.global_position) < BASE_REACH
	var center: Vector2 = Game.world.base.global_position if at_base else Game.heli.global_position
	var made := 0
	for i in n * 4:
		if made >= n:
			break
		var p := center + Vector2(randf_range(SPAWN_RING.x, SPAWN_RING.y), 0).rotated(randf() * TAU)
		if Game.world.is_walkable(p):
			Game.world.spawn_enemy(SpawnTable.pick(Game.danger_at(p), SpawnTable.context(p)), p, at_base)
			made += 1


func save_state() -> Dictionary:
	return {"last": last, "chains": chains, "mood": mood, "timer": timer, "shown": shown}


func load_state(d: Dictionary) -> void:
	last = d.get("last", {})
	chains = d.get("chains", [])
	mood = d.get("mood", 0)
	timer = d.get("timer", GAP.x)
	_redo = d.get("shown", [])
