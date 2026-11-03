extends Node
## Headless trade test (docs/ROADMAP3.md S2). main.gd adds this node when env SMOKE=trade (base founded):
##   SMOKE=trade godot --headless --path . --quit-after 30000
## The daily offer, buying (cost, stock, goods), price rise per purchase and recovery over the days, a recruit joining through
## Game.join, the poor sell rates and the supply reserve, the T key and the TRADE touch button, the window, save/load and old saves.
## TRADE_SHOT=<dir> (not headless): also saves the window at 100 % and 150 % UI scale as <dir>/trade_100.png / trade_150.png.

var _bad := 0


func check(ok: bool, msg: String) -> void:
	if not ok:
		_bad += 1
		print("FAIL: ", msg)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node2D = Game.world
	var op: Node2D = main.outposts
	var tr: Node = main.trade
	var heli: Node2D = Game.heli
	var frame := get_tree().process_frame
	await frame
	await frame
	get_tree().paused = true # the test drives the clock
	check(tr != null and tr.state.is_empty() and Save._hooks.has("trade"), "trade node and its save hook")
	check(InputMap.has_action("trade") and KeyMap.text("trade") == "T" and "trade" in KeyMap.actions(), "T is the trade action, listed for rebinding")
	check(not tr.can_open() and tr.hint() == "", "no village, no trade")
	# --- an allied village to trade with
	var pos: Vector2 = main.BASE_POS + Vector2(-1500, 400)
	var poi: Node2D = main.spawn_poi("survivors", pos, RandomNumberGenerator.new(), 4)
	await frame
	heli.position = pos + Vector2(20, 0)
	heli.landed = true
	await frame
	await frame
	Game.day = 10
	check(op.protect(), "village protected")
	var id: String = poi.uid
	check(tr.can_open() and tr.village_here()["id"] == id, "landed beside the village: trade possible")
	heli.position = pos + Vector2(400, 0)
	check(not tr.can_open(), "too far from the village")
	heli.position = pos + Vector2(20, 0)
	heli.landed = false
	check(not tr.can_open(), "in the air: no trade")
	heli.landed = true
	tr.available = true
	check(tr.hint().contains("[T] trade with"), "HUD hint: " + tr.hint())
	# --- the daily offer: small, the same for the same day, a new one on another day
	var o1: Array = tr.offer(id).duplicate(true)
	check(not o1.is_empty() and o1.size() <= tr.GOODS.size(), "an offer: %s" % [o1])
	check(o1.any(func(e): return e["good"] == "food"), "food is always on offer")
	check(o1.all(func(e): return e["left"] >= 1 and (e["good"] != "person" or e["skill"] in tr.PERSON_PRICE)), "stock and skills sane")
	tr.state.clear()
	check(tr.offer(id) == o1, "same seed, village and day: the same offer")
	var differs := false
	for d in range(11, 21):
		Game.day = d
		differs = differs or tr.offer(id) != o1
	check(differs, "other days bring other offers")
	var persons := 0
	for d in range(100, 200):
		Game.day = d
		persons += int(tr.offer(id).any(func(e): return e["good"] == "person"))
	check(persons > 30 and persons < 90, "a recruit on roughly %d %% of the days: %d / 100" % [100.0 * tr.PERSON_CHANCE, persons])
	Game.day = 10
	tr.state.clear()
	# --- buying: pin the offer so every good can be tried
	var list: Array = tr.offer(id)
	list.clear()
	for g in ["food", "electronics", "medicine", "rifles"]:
		list.append({"good": g, "skill": "", "left": 3})
	list.append({"good": "person", "skill": "engineer", "left": 1})
	list.append({"good": "person", "skill": "mechanic", "left": 1})
	Game.scrap = 1000
	var food0: float = Game.base_food
	check(tr.price(id, 0) == 15 and tr.buy_problem(id, 0) == "", "10 food: 15 scrap")
	check(tr.buy(id, 0) and Game.scrap == 985 and is_equal_approx(Game.base_food, food0 + 10.0) and list[0]["left"] == 2, "bought food")
	check(tr.price(id, 0) == 17, "the price rose a little: %d" % tr.price(id, 0))
	var el0: float = Game.salvage["electronics"]
	check(tr.price(id, 1) == 45, "electronics x5: 45 scrap")
	check(tr.buy(id, 1) and Game.salvage["electronics"] == el0 + 5.0 and Game.scrap == 985 - 45, "bought electronics")
	check(tr.price(id, 1) == 57, "electronics +25 %%: %d" % tr.price(id, 1))
	var p2: int = tr.price(id, 1)
	check(tr.buy(id, 1) and tr.price(id, 1) == 68 and tr.price(id, 1) > p2, "and again: %d" % tr.price(id, 1))
	check(tr.price(id, 1) > 45 and tr.price(id, 0) < tr.price(id, 1), "demand is per good")
	var med0: float = Game.base_medicine
	var rif0: float = Game.base_rifles
	check(tr.buy(id, 2) and is_equal_approx(Game.base_medicine, med0 + 2.0), "bought medicine x2")
	check(tr.buy(id, 3) and is_equal_approx(Game.base_rifles, rif0 + 1.0), "bought a rifle")
	# --- limits: stock, money
	check(tr.buy(id, 3) and tr.buy(id, 3) and list[3]["left"] == 0, "three rifles in all")
	check(tr.buy_problem(id, 3).contains("Sold out") and not tr.buy(id, 3) and list[3]["left"] == 0, "sold out: %s" % tr.buy_problem(id, 3))
	var before: int = Game.scrap
	Game.scrap = 10
	check(tr.buy_problem(id, 0).contains("scrap") and not tr.buy(id, 0) and Game.scrap == 10, "too poor: %s" % tr.buy_problem(id, 0))
	check(tr.buy_problem(id, 99) != "" and not tr.buy(id, -1), "no such line")
	Game.scrap = before
	# --- a recruit joins through Game.join and is a full member of the base
	var n0: int = Game.people.size()
	var rescued0: int = Game.rescued
	var saved0: int = Game.saved_count()
	var scrap0: int = Game.scrap
	check(tr.price(id, 4) == 140, "an engineer is dear: %d" % tr.price(id, 4))
	check(tr.buy(id, 4), "bought the engineer")
	var fresh: Dictionary = Game.people[Game.people.size() - 1]
	check(Game.people.size() == n0 + 1 and Game.rescued == rescued0 + 1 and Game.saved_count() == saved0 + 1, "one more person at the base")
	check(fresh["skill"] == "engineer" and not fresh["aboard"] and fresh["post"] == "" and Game.scrap == scrap0 - 140, "an engineer joined: %s" % [fresh])
	check(list[4]["left"] == 0 and tr.buy_problem(id, 4).contains("Sold out"), "one recruit per line")
	check(tr.price(id, 5) == 112, "recruits get dearer with every one: %d" % tr.price(id, 5))
	# --- recovery over the days (the offer of the new day is rolled; the heat only cools)
	var heat_e: float = tr.heat(id, "electronics")
	check(is_equal_approx(heat_e, 0.5) and is_equal_approx(tr.heat(id, "food"), 0.1), "heat after the purchases: %s" % [tr.sheet(id)["heat"]])
	Game.day += 3
	check(is_equal_approx(tr.heat(id, "electronics"), 0.2) and tr.heat(id, "food") == 0.0, "3 days: food cooled, electronics at 0.2: %s" % [tr.sheet(id)["heat"]])
	var oe: int = tr.offer(id).find_custom(func(e): return e["good"] == "electronics")
	check(oe >= 0 and tr.price(id, oe) == 54, "electronics price recovering: %d" % tr.price(id, oe))
	check(tr.offer(id).all(func(e): return e["left"] >= 1), "new day, new stock")
	Game.day += 5
	check(tr.sheet(id)["heat"].is_empty() and tr.price(id, tr.offer(id).find_custom(func(e): return e["good"] == "electronics")) == 45, "after 8 days: back to the base price")
	# --- selling: poor rates, falling with every sale, the base keeps its supplies
	Game.base_food = Game.food_eaters() * Game.FOOD_PER_PERSON * tr.SELL["food"]["keep_days"] + 35.0
	var s0: int = Game.scrap
	var f0: float = Game.base_food
	check(tr.payout(id, "food") == 4 and tr.payout(id, "food") < tr.price(id, tr.offer(id).find_custom(func(e): return e["good"] == "food")), "10 food sell for 4 and cost 15")
	check(tr.sell(id, "food") and Game.scrap == s0 + 4 and is_equal_approx(Game.base_food, f0 - 10.0), "sold food")
	check(tr.payout(id, "food") == 3, "the next batch pays less: %d" % tr.payout(id, "food"))
	check(tr.sell(id, "food") and tr.sell(id, "food") and tr.sell_problem(id, "food") != "", "the reserve stays: %s" % tr.sell_problem(id, "food"))
	check(not tr.sell(id, "food") and is_equal_approx(Game.base_food, f0 - 30.0), "nothing sold below the reserve (%d food left)" % Game.base_food)
	check(tr.payout(id, "food") >= 1 and tr.payout(id, "food") <= 4, "the payout never reaches zero")
	for i in 10:
		tr._bump(id, "sell_food", tr.SELL_STEP)
	check(tr.payout(id, "food") == maxi(1, floori(4 * tr.SELL_FLOOR)), "sell rate floors out: %d" % tr.payout(id, "food"))
	Game.base_water = 500.0
	var w0: int = Game.scrap
	check(tr.sell(id, "water") and Game.scrap == w0 + 3 and tr.sell_problem(id, "gold") != "", "water sells for 3, they do not buy gold")
	# the water reserve counts campers double, like the daily water tick
	var r0: int = Game.rescued
	Game.rescued = Game.housing() + 4
	check(Game.campers() == 4, "4 campers")
	check(is_equal_approx(tr.spare("water"), Game.base_water - (Game.rescued + 4) * Game.WATER_PER_PERSON * tr.SELL["water"]["keep_days"]), "campers drink double in the reserve: %.1f" % tr.spare("water"))
	Game.rescued = r0
	Game.day += 15
	check(tr.payout(id, "food") == 4, "the market recovers: %d" % tr.payout(id, "food"))
	# --- save and load: offer, stock and heat of each village; old saves have none
	Game.day = 30
	Game.scrap = 1000
	var line: int = tr.offer(id).find_custom(func(e): return e["good"] == "food")
	tr.buy(id, line)
	var offer_then: Array = tr.offer(id).duplicate(true)
	var price_then: int = tr.price(id, line)
	Save.autosave()
	var saved: Dictionary = Save.read()["systems"]["trade"]
	check(saved["v"].has(id) and saved["v"][id]["day"] == 30, "the village sheet is in run.sav")
	var back: Dictionary = bytes_to_var(var_to_bytes(tr.save_state().duplicate(true)))
	tr.state.clear()
	tr.load_state(back)
	check(tr.offer(id) == offer_then and tr.price(id, line) == price_then, "offer, stock and price survive save/load")
	tr.load_state({})
	check(tr.state.is_empty(), "a save from before trade loads: nothing yet")
	check(tr.offer(id) != [] and tr.price(id, 0) > 0, "and the village rolls its first offer")
	tr.state["gone"] = {"day": 1, "offer": [], "heat": {}}
	check(not tr.save_state()["v"].has("gone") and tr.save_state()["v"].has(id), "a fallen village loses its sheet")
	# --- the window
	var ui: CanvasLayer = main.trade_ui
	check(ui != null and not ui.visible, "window built and closed")
	tr.state.clear()
	ui.open()
	check(ui.visible and get_tree().paused and main.ui_open, "window open, game paused")
	check(ui.buy_btns.size() == tr.offer(id).size() and ui.sell_btns.size() == tr.SELL.size(), "a button per line")
	Game.scrap = 1000
	var n_lines: int = ui.buy_btns.size()
	var scrap_ui: int = Game.scrap
	ui.buy_btns[0].pressed.emit()
	check(Game.scrap < scrap_ui and ui.buy_btns.size() == n_lines and ui.note == "Done.", "a click buys and the window refreshes")
	Game.scrap = 0
	ui.refresh()
	check(ui.buy_btns.all(func(b): return b.disabled), "no scrap: every buy button greyed out")
	ui.close()
	check(not ui.visible and get_tree().paused and not main.ui_open, "closed: the test's own pause stays")
	# --- T key and TRADE touch button (unpaused, so the input reaches the window)
	get_tree().paused = false
	Game.scrap = 100
	var touch: CanvasLayer = main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/touch_ui.gd"))[0]
	var pad: Control = touch.context[3]
	check(pad.action == "trade" and pad.text == "TRADE", "a TRADE pad among the context buttons")
	Controls.touch = true
	heli.position = pos + Vector2(500, 0)
	await get_tree().create_timer(0.5).timeout # the scan runs 4x a second
	check(not tr.available and not pad.visible, "no village: no TRADE pad")
	heli.position = pos + Vector2(20, 0)
	await get_tree().create_timer(0.5).timeout
	check(tr.available and pad.visible and pad.size.y >= UiTheme.TOUCH_MIN and pad.size.x >= UiTheme.TOUCH_MIN, "village in reach: TRADE pad, finger sized")
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.pressed = true
	pad._gui_input(ev)
	await frame
	await frame
	check(ui.visible and get_tree().paused, "the TRADE pad opens the window")
	ev.pressed = false
	pad._gui_input(ev)
	ui.close()
	Controls.touch = false
	get_tree().paused = false
	await frame
	check(not ui.visible and not get_tree().paused, "closed again")
	var press := InputEventAction.new()
	press.action = "trade"
	press.pressed = true
	Input.parse_input_event(press)
	await frame
	await frame
	check(ui.visible, "the T key opens the window")
	Input.parse_input_event(press)
	await frame
	await frame
	check(not ui.visible and not get_tree().paused, "T closes it again")
	heli.position = pos + Vector2(500, 0)
	Input.parse_input_event(press)
	await frame
	await frame
	check(not ui.visible, "away from the village T does nothing")
	heli.position = pos + Vector2(20, 0)
	var esc := InputEventAction.new()
	esc.action = "menu"
	esc.pressed = true
	ui.open()
	Input.parse_input_event(esc)
	await frame
	await frame
	check(not ui.visible, "ESC closes the window")
	if OS.get_environment("TRADE_SHOT") != "" and DisplayServer.get_name() != "headless":
		await _shots(ui, OS.get_environment("TRADE_SHOT"))
	print("trade_test ", "OK" if _bad == 0 else "FAILED (%d)" % _bad)
	get_tree().quit(0 if _bad == 0 else 1)


## The window at 100 % and 150 % UI scale, with a full offer, a sold-out line and a poor player.
func _shots(ui: CanvasLayer, dir: String) -> void:
	var tr: Node = Game.world.trade
	var real_path := Settings.path
	var start: int = Settings.get_value(UiTheme.SCALE_KEY)
	Settings.path = Game.profile_dir() + "trade_shot.json"
	for pct in [100, 150]:
		Settings.set_value(UiTheme.SCALE_KEY, pct)
		Game.day = 50
		tr.state.clear()
		var id: String = tr.village_here()["id"]
		var list: Array = tr.offer(id)
		list.clear()
		list.append({"good": "person", "skill": "medic", "left": 1})
		list.append({"good": "electronics", "skill": "", "left": 2})
		list.append({"good": "medicine", "skill": "", "left": 0})
		list.append({"good": "rifles", "skill": "", "left": 1})
		list.append({"good": "food", "skill": "", "left": 4})
		Game.scrap = 120
		Game.base_food = 80.0
		Game.base_water = 20.0
		get_tree().paused = false
		ui.open()
		ui.note = "Done."
		ui.refresh()
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/trade_%d.png" % [dir, pct])
		ui.close()
	Settings.set_value(UiTheme.SCALE_KEY, start)
	Settings.path = real_path
