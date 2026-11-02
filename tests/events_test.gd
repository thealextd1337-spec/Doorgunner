extends Node
## Headless test of the radio events (docs/ROADMAP2.md Q13). main.gd adds this node when env SMOKE=events (base founded):
##   SMOKE=events godot --headless --path . --quit-after 30000
## 1. The card table: 30+ cards, 2-3 options, known effect keys, chains point at cards.
## 2. Conditions pick a matching card (day, morale, stocks, buildings, bandit camps, place, cooldown).
## 3. Options take effect (stocks, people, morale, bandit attitude, missions, zombies, hull clamp), a need locks an option.
## 4. A chain follows days later. 5. The radio takes the default option after the timeout.
## 6. Event and level-up cards never show together (one queue, number keys). 7. Save and load of chains and open cards.
## 8. Bandit truce, settings switch, registered cards. The clock, spawner and scheduler are driven by hand.

const FX_KEYS := ["morale", "mood", "join", "join_skill", "aboard", "aboard_hurt", "hurt", "die", "leave", "mission", "zombies", "raid", "xp", "parts"]

var main: Node2D
var ev: Node
var ui: CanvasLayer
var log: Array[String] = []
var frame: Signal


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	ev = main.events
	ui = main.choice_ui
	frame = get_tree().process_frame
	await frame
	await frame
	Game.set_process(false) # the test owns the clock
	main.spawner.set_process(false)
	main.chunks.process_mode = Node.PROCESS_MODE_DISABLED
	ev.set_process(false)
	Game.radio_message.connect(func(msg: String): log.append(msg))
	_table()
	_conditions()
	_effects()
	_chains()
	await _timeout()
	await _queue()
	_save()
	_misc()
	_clear()
	print("EVENTS OK")
	get_tree().quit(0)


func _base() -> Vector2:
	return main.base.global_position


## A known state: day 5, six people at the base, plain stocks, no camps, no buildings, the heli on the pad.
func _reset() -> void:
	_clear()
	ev.last.clear()
	ev.chains.clear()
	ev.shown.clear()
	ev.mood = 0
	Game.day = 5
	Game.rescued = 6
	Game.passengers = 0
	Game.scrap = 100
	Game.base_food = 60.0
	Game.base_water = 60.0
	Game.base_fuel = 300.0
	Game.base_ammo = 500.0
	Game.base_medicine = 2.0
	Game.base_rifles = 2.0
	Game.salvage["parts"] = 0.0
	Game.hp = Game.max_hp
	Game.injured = 0
	Game.seats = 4
	Game.buildings = []
	Game.workers["farm"] = 0
	main.morale.value = 50.0
	main.morale.pending.clear()
	main.bandits.camps.clear()
	for e in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("bandits"):
		e.queue_free()
	Game.heli.global_position = _base()
	Game.heli.landed = true
	log.clear()


## Answers or dismisses whatever card is open until nothing is.
func _clear() -> void:
	for i in 12:
		if not ui.ev.is_empty():
			ui.pick_event(ui.ev["view"]["default"])
		elif ui.visible:
			ui.skip()
	ui.queue.clear()
	get_tree().paused = false


func _ids(list: Array) -> String:
	return ", ".join(list)


func _table() -> void:
	var cards: Dictionary = ev.Cards.CARDS
	assert(cards.size() >= 30, "30 cards to start: %d" % cards.size())
	var chained := {}
	var random := 0
	for id: String in cards:
		var c: Dictionary = cards[id]
		assert(c.has("title") and c.has("from") and c.has("text") and c["opts"].size() in [2, 3], "card shape: " + id)
		assert(c.get("default", c["opts"].size() - 1) < c["opts"].size(), "default option exists: " + id)
		assert(c.get("chain_only", false) or c.has("when"), "a random card has conditions: " + id)
		random += int(not c.get("chain_only", false))
		for o: Dictionary in c["opts"]:
			assert(o.has("t") and o.has("out") or o.has("risk"), "option text: " + id)
			var fxs: Array = [o.get("fx", {}), o.get("risk", [0, {}])[1], o.get("need", {})]
			for fx: Dictionary in fxs:
				for k: String in fx:
					assert(ev.RES.has(k) or k in FX_KEYS, "known key %s in %s" % [k, id])
			if o.has("fx") and o["fx"].has("mission"):
				assert(main.missions.TYPES.has(o["fx"]["mission"]), "mission type in " + id)
			if o.has("chain"):
				chained[o["chain"][0]] = true
				assert(cards.has(o["chain"][0]), "chain target of " + id)
	for id: String in cards:
		assert(not cards[id].get("chain_only", false) or chained.has(id), "chain-only card nobody chains to: " + id)
	assert(random >= 25, "random cards: %d" % random)
	print("EVENTS table OK  %d cards, %d random, %d chain follow-ups" % [cards.size(), random, chained.size()])


func _conditions() -> void:
	_reset()
	var ids: Array = ev.eligible()
	for id in ["stranger", "sickness", "quarrel", "stolen_supplies", "herd_at_wire", "stray_dog"]:
		assert(id in ids, "base card eligible at the base: " + id)
	for id in ["bandit_trade", "shortwave", "low_food", "grumbling", "supply_drop", "wounded_soldier", "stranger_clear", "tribute_raid", "night_off"]:
		assert(not id in ids, "not eligible yet: " + id)
	Game.day = 3
	assert(not "sickness" in ev.eligible() and "stranger" in ev.eligible(), "day gate")
	Game.day = 6
	Game.base_food = 5.0
	assert("low_food" in ev.eligible() and not "low_water" in ev.eligible(), "low stock")
	main.morale.value = 20.0
	assert("grumbling" in ev.eligible() and not "night_off" in ev.eligible(), "morale low")
	main.morale.value = 90.0
	assert("night_off" in ev.eligible() and not "grumbling" in ev.eligible(), "morale high")
	main.bandits.add_camp("ev1", "motel", _base() + Vector2(3000, 0))
	assert("bandit_trade" in ev.eligible() and "deserters" in ev.eligible(), "bandit camp present")
	main.bandits.camps["ev1"]["cleared"] = true
	assert(not "bandit_trade" in ev.eligible(), "cleared camp does not count")
	Game.buildings.append({"kind": "radio", "cell": Vector2i.ZERO, "built": true, "progress": 0.0})
	assert("shortwave" in ev.eligible() and "radio_ghost" in ev.eligible(), "building present")
	Game.buildings[0]["built"] = false
	assert(not "shortwave" in ev.eligible(), "unfinished building does not count")
	Game.hp = Game.max_hp * 0.5
	Game.scrap = 100
	assert("mechanic_offer" in ev.eligible(), "damaged hull and scrap")
	Game.scrap = 10
	assert(not "mechanic_offer" in ev.eligible(), "no scrap")
	ev.mood = -2
	# place: in the air the base cards go, the air cards come
	Game.day = 8
	Game.heli.global_position = _base() + Vector2(2500, 0)
	Game.heli.landed = false
	ids = ev.eligible()
	assert("supply_drop" in ids and "wounded_soldier" in ids and "ammo_cache" in ids and "ambush" in ids, "air cards in flight: " + _ids(ids))
	assert(not "stranger" in ids and not "sickness" in ids, "base cards stay home")
	Game.passengers = Game.seats
	assert(not "wounded_soldier" in ev.eligible(), "no free seat")
	# one candidate left -> pick returns it; a cooldown takes it out; days bring it back
	_reset()
	Game.base_food = 5.0
	for id: String in ev.eligible():
		if id != "low_food":
			ev.last[id] = Game.day
	assert(ev.pick() == "low_food", "pick: the only card that fits")
	assert(ev.add("low_food") and ev.last["low_food"] == Game.day and ui.visible, "offered, stamped, shown")
	_clear()
	assert(ev.pick() == "", "cooldown: nothing fits now")
	Game.day += 6
	assert("low_food" in ev.eligible(), "cooldown over after 6 days")
	print("EVENTS conditions OK")


func _effects() -> void:
	# need locks an option: no medicine, "Treat them" cannot be picked
	_reset()
	Game.base_medicine = 0.0
	assert(Events.offer("sickness") and ui.visible and ui.ev["id"] == "sickness", "Events.offer shows the card")
	assert(not ui.ev["view"]["opts"][0]["ok"], "treat needs medicine")
	ui.pick(0)
	assert(not ui.ev.is_empty(), "a locked option does nothing")
	var inj: int = Game.injured
	ui.pick(1)
	assert(ui.ev.is_empty() and not ui.visible and Game.injured == inj + 1, "isolate: one down")
	assert(main.morale.pending.size() == 1 and main.morale.pending[0][1] == -1.0, "morale reported")
	# paid option: stocks, bandit attitude
	_reset()
	main.bandits.add_camp("ev1", "motel", _base() + Vector2(3000, 0))
	Events.offer("bandit_trade")
	ui.pick(0)
	assert(Game.scrap == 60 and Game.base_ammo == 650.0 and ev.mood == 1, "bought ammo: %d scrap, %d ammo, mood %d" % [Game.scrap, Game.base_ammo, ev.mood])
	Events.offer("bandit_trade")
	ui.pick(1)
	assert(Game.base_rifles == 1.0 and Game.scrap == 120 and ev.mood == 2, "sold a rifle")
	# people through the facade
	_reset()
	Events.offer("nurse")
	ui.pick(0)
	assert(Game.rescued == 7 and Game.people.back()["skill"] == "medic", "a medic joined")
	_reset()
	Events.offer("refugees")
	ui.pick(0)
	assert(Game.rescued == 9 and Game.injured == 1 and Game.base_food == 50.0, "family taken in: %d people" % Game.rescued)
	_reset()
	Events.offer("deserters")
	ui.pick(1)
	assert(Game.base_rifles == 4.0, "rifles left behind")
	# a risk: certain, then never
	_reset()
	var c: Dictionary = ev.card("stranger").duplicate(true) # the table is a const: a registered copy with a sure risk
	c["opts"][0]["risk"][0] = 1.0
	Events.register("zz_risk", c)
	Events.offer("zz_risk")
	ui.pick(0)
	assert(Game.rescued == 7 and Game.injured == 2, "risk came true: joined and two sick")
	assert(log.any(func(s): return "sick" in s), "risk line on the radio")
	c["opts"][0]["risk"][0] = 0.0
	Events.register("zz_risk", c)
	Events.offer("zz_risk")
	ui.pick(0)
	assert(Game.rescued == 8 and Game.injured == 2, "risk did not happen")
	Events.extra.erase("zz_risk")
	# deaths and hull clamp, heli stocks
	_reset()
	ev._apply({"die": 1, "leave": 1, "hull": -1.0e6, "heli_fuel": -1.0e6, "heli_ammo": 30, "fuel": 1.0e6, "parts": 2, "scrap": -1000}, {})
	assert(Game.rescued == 4 and Game.hp == 1.0 and Game.fuel == 0.0 and Game.ammo <= Game.max_ammo and Game.base_fuel == Game.base_fuel_cap, "die/leave, hull stays 1, caps")
	assert(Game.salvage["parts"] == 2.0 and Game.scrap == 0, "parts added, scrap floors at 0")
	# a mission and a crowd
	_reset()
	var n: int = main.missions.open.size()
	Events.offer("child_radio")
	ui.pick(0)
	assert(main.missions.open.size() == n + 1 or log.any(func(s): return "no crew free" in s), "rooftop mission offered")
	_reset()
	var z: int = get_tree().get_nodes_in_group("enemies").size()
	Events.offer("herd_at_wire")
	ui.pick(0)
	assert(get_tree().get_nodes_in_group("enemies").size() > z, "the herd arrived")
	assert(ui.visible and ui.dim.visible and ui.ev.is_empty(), "+50 XP levelled up: the level-up card opened at once")
	assert(Game.base_ammo == 460.0, "ammo spent")
	_reset()
	main.bandits.last_base_raid = -100
	Events.offer("tribute_raid")
	ui.pick(0)
	assert(main.bandits.last_base_raid == Game.day, "a raid hit the base")
	# aboard (air card)
	_reset()
	Game.heli.global_position = _base() + Vector2(2500, 0)
	Game.heli.landed = false
	Events.offer("wounded_soldier")
	ui.pick(0)
	assert(Game.passengers == 1 and Game.passengers_injured == 1, "wounded soldier aboard")
	_reset()
	print("EVENTS effects OK")


func _chains() -> void:
	_reset()
	Events.offer("stranger")
	ui.pick(1) # quarantine
	assert(ev.chains.size() == 1 and ev.chains[0]["id"] == "stranger_clear" and ev.chains[0]["day"] == Game.day + 1, "chain scheduled")
	ev._process(0.1)
	assert(not ui.visible, "not due yet")
	Game.day += 1
	ev.timer = 1.0e6
	ev._process(0.1)
	assert(ui.visible and ui.ev["id"] == "stranger_clear" and ev.chains.is_empty(), "the follow-up arrives a day later")
	var n: int = Game.rescued
	ui.pick(0)
	assert(Game.rescued == n + 1 and Game.people.back()["skill"] == "medic", "welcomed as a medic")
	# chain cards are never rolled
	ev.last.clear()
	assert(not ev.eligible().any(func(id): return ev.card(id).get("chain_only", false)), "chain-only cards stay out of the roll")
	# refusing the ultimatum brings the scouts
	_reset()
	main.bandits.add_camp("ev1", "motel", _base() + Vector2(3000, 0))
	Game.day = 10
	Events.offer("ultimatum")
	ui.pick(2)
	assert(ev.mood == -1 and ev.chains[0]["id"] == "tribute_raid", "refused: hostile, scouts tomorrow")
	_reset()
	print("EVENTS chains OK")


func _timeout() -> void:
	_reset()
	var got := []
	var h := func(id: String, o: int): got.append([id, o])
	ev.chosen.connect(h)
	Events.offer("sickness") # default: isolate
	assert(ui.ev["view"]["default"] == 1 and ui.ev["left"] == Events.TIMEOUT, "60 s on the clock")
	ui.ev["left"] = 0.05
	for i in 120:
		if ui.ev.is_empty():
			break
		await frame
	assert(ui.ev.is_empty() and not ui.visible, "card closed on its own")
	assert(got == [["sickness", 1]], "default option taken: %s" % str(got))
	assert(Game.injured == 1, "and it took effect")
	# a default nobody can pay falls back
	Game.base_medicine = 0.0
	var view: Dictionary = ev.view("generator_fault", {})
	assert(view["default"] == 2, "default free")
	Game.scrap = 0
	_fallback()
	# the clock stops while the tree is paused
	Events.offer("sickness")
	ui.ev["left"] = 1.0
	get_tree().paused = true
	ui._process(5.0)
	get_tree().paused = false
	assert(not ui.ev.is_empty() and ui.ev["left"] == 1.0, "paused: no countdown")
	_clear()
	ev.chosen.disconnect(h)
	print("EVENTS timeout OK")


func _fallback() -> void:
	var c: Dictionary = {"title": "T", "from": "F", "text": "x", "default": 1, "opts": [{"t": "a", "out": "a"}, {"t": "b", "need": {"scrap": 999}, "out": "b"}]}
	Events.register("zz_fallback", c)
	assert(ev.view("zz_fallback", {})["default"] == 0, "unpayable default falls back to a free option")
	Events.extra.erase("zz_fallback")


func _queue() -> void:
	# an event card does not pause, takes no dim; number keys answer it
	_reset()
	Events.offer("quarrel")
	assert(ui.visible and not get_tree().paused and not ui.dim.visible and ui.ev_panel.visible, "event card: no pause, no dim")
	assert(ui.obstacles().size() == 1 and ui.is_in_group(UiTheme.OBSTACLES), "HUD obstacle")
	_key("slot_4") # only three options: ignored
	assert(not ui.ev.is_empty(), "slot 4 does nothing on a 3-option card")
	_key("slot_2")
	assert(ui.ev.is_empty() and Game.scrap == 85, "key 2 chose the bonus")
	# event open, level-up requested: the level-up waits
	Events.offer("quarrel")
	main.offer_upgrades("Level 2 reached")
	assert(ui.queue.size() == 1 and not get_tree().paused and ui.ev_panel.visible and not ui.dim.visible, "level-up queued behind the event")
	ui.pick(0)
	assert(ui.ev.is_empty() and ui.visible and get_tree().paused and ui.dim.visible and not ui.ev_panel.visible, "then the level-up shows, paused")
	assert(ui.queue.is_empty(), "queue drained")
	# level-up open, event offered: queued, the clock does not run, then it opens when the cards close
	Events.offer("sickness")
	assert(ui.queue.size() == 1 and ui.ev.is_empty() and ui.dim.visible and ev.shown.size() == 1, "event queued behind the level-up")
	ui.pick(0) # the level-up card
	assert(not ui.dim.visible and ui.ev_panel.visible and not get_tree().paused and ui.ev["id"] == "sickness", "then the event shows, game runs")
	assert(ui.ev["left"] == Events.TIMEOUT, "its clock starts when it shows")
	# two events and a level-up: strictly one at a time, in order
	Events.offer("quarrel")
	main.offer_upgrades("Level 3 reached")
	assert(ui.queue.size() == 2 and ev.shown.size() == 2, "three cards, one shown")
	var order := []
	for i in 6:
		if not ui.ev.is_empty():
			order.append(ui.ev["id"])
			assert(not ui.dim.visible, "never both")
			ui.pick(ui.ev["view"]["default"])
		elif ui.visible:
			order.append("levelup")
			assert(ui.dim.visible and not ui.ev_panel.visible, "never both")
			ui.skip()
	assert(order == ["sickness", "quarrel", "levelup"] or order == ["sickness", "levelup", "quarrel"], "all three shown once: %s" % str(order))
	assert(not ui.visible and ev.shown.is_empty() and not get_tree().paused, "all closed")
	# the level-up via R/S/B keys is unchanged and an event card ignores them
	Events.offer("quarrel")
	var rr: int = Game.rerolls
	_key("reroll")
	_key("skip")
	assert(not ui.ev.is_empty() and Game.rerolls == rr, "R and S do nothing on an event card")
	_clear()
	# a level-up effect of an answer opens right away
	Game.xp = 0
	Game.level = 1
	Events.offer("shortwave") # not eligible but offered by id: the caller's business
	ui.pick(0)
	assert(ui.ev.is_empty() and ui.visible and ui.dim.visible and get_tree().paused, "answered; its XP levelled up and the level-up opened")
	_clear()
	print("EVENTS queue OK")


func _key(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	ui._input(e)


func _save() -> void:
	_reset()
	main.bandits.add_camp("ev1", "motel", _base() + Vector2(3000, 0))
	ev.mood = 2
	Events.offer("ultimatum") # open card
	Events.offer("quarrel") # queued card
	ui.pick(2) # refuse -> chain tribute_raid; the quarrel shows
	assert(ev.chains.size() == 1 and ev.shown.size() == 1 and ui.ev["id"] == "quarrel", "state to save")
	assert(Save.autosave(), "autosaved")
	var d: Dictionary = Save.read()["systems"]["events"]
	assert(d["chains"].size() == 1 and d["chains"][0]["id"] == "tribute_raid" and d["mood"] == 1 and d["shown"].size() == 1, "run.sav holds chains, mood and the open card")
	assert(d["last"].has("ultimatum") and d["last"].has("quarrel"), "cooldown stamps saved")
	var chains: Array = ev.chains.duplicate(true)
	_clear()
	ev.chains.clear()
	ev.last.clear()
	ev.mood = 0
	ev.load_state(d)
	assert(ev.chains == chains and ev.mood == 1 and ev.last.has("ultimatum") and ev.timer == d["timer"], "load gives the chain back")
	ev._process(0.1)
	assert(ui.visible and ui.ev["id"] == "quarrel" and ev.shown.size() == 1, "the open card comes back after a load")
	_clear()
	# an old save has no events hook: nothing to load, the defaults stand; a partial dictionary loads too
	ev.load_state({})
	assert(ev.chains.is_empty() and ev.mood == 0 and ev.shown.is_empty(), "empty save data loads as defaults")
	Save.delete_run()
	print("EVENTS save OK")


func _misc() -> void:
	_reset()
	# bandit truce: friendly bandits plan no raid on the base; forced plans (tests, siege) still work
	main.bandits.add_camp("ev1", "motel", _base() + Vector2(3000, 0))
	main.bandits.last_base_raid = -100
	main.bandits.base_raid_day = -1
	var day := 20
	while Assault.night_taken(day): # a zombie assault night never gets a bandit raid
		day += 1
	Game.day = day
	ev.mood = Events.TRUCE_MOOD
	assert(Events.truce() and not main.bandits.plan_base_raid(day), "truce: no random raid")
	assert(main.bandits.plan_base_raid(day, true), "forced raid still planned")
	main.bandits.base_raid_day = -1
	ev.mood = 0
	assert(not Events.truce(), "no truce at 0")
	# the mood drifts back every few days
	ev.mood = 3
	ev._on_day(Events.MOOD_DRIFT_DAYS)
	assert(ev.mood == 2, "mood drifts")
	ev._on_day(Events.MOOD_DRIFT_DAYS + 1)
	assert(ev.mood == 2, "only on the drift days")
	ev.mood = 0
	# the scheduler: timer, switch, attack, tutorial
	_reset()
	Game.day = 6
	ev.timer = 0.0
	Settings.set_value(Events.KEY, 0)
	ev._process(0.1)
	assert(not ui.visible, "switched off: no card")
	Settings.set_value(Events.KEY, 1)
	Game.attack_active = true
	ev._process(0.1)
	assert(not ui.visible, "no card in an assault")
	Game.attack_active = false
	ev._process(0.1)
	assert(ui.visible and ev.timer >= Events.GAP.x, "the timer ran out: a card, new timer %.0f s" % ev.timer)
	var shown_id: String = ui.ev["id"]
	ev.timer = 0.0
	ev._process(0.1)
	assert(ev.shown.size() == 1, "no second random card while one is open")
	_clear()
	# no card fits: retry soon
	ev.last = {}
	for id: String in ev.Cards.CARDS:
		ev.last[id] = Game.day
	ev.timer = 0.0
	ev._process(0.1)
	assert(not ui.visible and ev.timer == Events.RETRY, "nothing fits: retry in %d s" % Events.RETRY)
	# registered card, unknown card
	Events.register("zz_test", {"title": "TEST", "from": "Q15", "text": "{who} calls.", "opts": [{"t": "A", "fx": {"scrap": 7}, "out": "ok"}, {"t": "B", "out": "no"}]})
	var s: int = Game.scrap
	var got := []
	var h := func(id: String, o: int): got.append([id, o])
	ev.chosen.connect(h)
	assert(Events.offer("zz_test", {"who": "Kane"}) and ui.ev["view"]["text"] == "Kane calls.", "registered card with ctx")
	ui.pick(0)
	assert(Game.scrap == s + 7 and got == [["zz_test", 0]], "chosen signal for Q15")
	ev.chosen.disconnect(h)
	assert(not Events.offer("no_such_card"), "unknown card refused")
	Events.extra.erase("zz_test")
	_reset()
	print("EVENTS misc OK  last=%s" % shown_id)
