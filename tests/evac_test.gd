extends Node
## Headless evacuation test (scripts/evac.gd, docs/ROADMAP.md P17). main.gd adds this node when env SMOKE=evac (base founded):
##   SMOKE=evac godot --headless --path . --quit-after 30000
## An old save without the evac key loads; day 15 announces the frequency; Radio Station (Engineer, electronics, refund) -> contact;
## Airstrip checks (perimeter, fence, pad, rock/water/house, sandbag, forest felled and trees cut, rotation, one only, nothing built on
## it) -> 3 day countdown -> save and reload in the middle of it -> raids keep out of the siege night -> the final siege (biggest wave,
## 4 pushes, bosses, bandit raid, does not end by itself) -> landing, loading only while the strip is clear -> victory screen,
## the victory counted once, the server told while the run is not ended -> STAY BEHIND (run goes on, no second evacuation,
## a later death carries the victory) -> END RUN of another run. The node moves itself under the root and survives the scene reloads.

const T := preload("res://scripts/chunk_manager.gd").T
const NAME := "EvacTest"

var main: Node2D
var e: Evac
var frame: Signal
var radio_log: Array[String] = []
var meta0: Dictionary


func _ready() -> void:
	if get_tree().root.has_node(NAME):
		queue_free()
		return
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	name = NAME
	frame = get_tree().process_frame
	await frame
	await frame
	meta0 = Game.meta.duplicate(true)
	Game.radio_message.connect(func(m: String): radio_log.append(m))
	_setup()
	await _old_save()
	_contact()
	_airstrip()
	await _reload_mid_countdown()
	await _siege()
	_landing_and_boarding()
	_victory_screen()
	await _stay_behind()
	await _end_run()
	Game.meta = meta0 # the smoke profile's best day would unlock slots in other tests
	Game._save_meta()
	Save.delete_run()
	print("EVAC OK")
	get_tree().quit(0)


func _setup() -> void:
	main = Game.world
	e = main.evac
	for n in [main.spawner, main.missions, main.assault, main.bandits, e]:
		n.set_process(false) # stepped by hand
	Game.level = Game.LEVEL_CAP # no upgrade cards


func _logged(part: String) -> bool:
	return radio_log.any(func(m): return part in m)


func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(x): return not x.is_queued_for_deletion())


func _clear_enemies() -> void:
	for x in _enemies():
		x.free()
	main.assault.clear_wave()


## Saves, reloads the scene and loads (the test node survives), then sets the systems up again.
func _reload(edit := Callable()) -> void:
	Game.running = true
	assert(Save.autosave(), "saved")
	if edit.is_valid():
		var data := Save.read()
		edit.call(data["systems"])
		Save._write(var_to_bytes(data))
	Save.pending = true
	get_tree().paused = false
	get_tree().reload_current_scene()
	await frame
	await frame
	await frame
	_setup()


func _old_save() -> void:
	await _reload(func(systems: Dictionary):
		systems.erase("evac") # runs saved before the evacuation have neither the system nor these keys
		systems["assault"].erase("final"))
	assert(not e.announced and not e.contact and e.phase == "" and not e.victory, "no evac key: defaults")
	assert(main.assault.final == false, "assault without the final flag loads")
	assert(Game.meta.has("victories"), "meta has the victories stat")
	assert(Evac.siege_night(Game.day) == false and not Evac.holds_assault() and not Evac.won(), "statics are quiet")


func _contact() -> void:
	Game.rescued = 6
	for p in Game.people:
		p["skill"] = "farmer"
	Game.scrap = 600
	Game.salvage["electronics"] = 0.0
	Game.day = 14
	e._on_day(14)
	assert(not e.announced and not e.tool_visible("radio") and "frequency" in e.tool_note("radio"), "nothing before day 15")
	e._on_day(15)
	Game.day = 15
	assert(e.announced and _logged("military frequency") and e.tool_visible("radio") and not e.tool_visible("airstrip"), "day 15: the frequency is radioed")
	assert("electronics" in e.tool_note("radio"), "needs electronics: %s" % e.tool_note("radio"))
	Game.salvage["electronics"] = 10.0
	assert("Engineer" in e.tool_note("radio"), "needs an Engineer: %s" % e.tool_note("radio"))
	Game.people[0]["skill"] = "engineer"
	Game.people[0]["injured"] = true
	assert(e.engineer() == null, "an injured Engineer cannot run it")
	Game.people[0]["injured"] = false
	assert(e.engineer() != null and e.tool_note("radio") == "", "ready to build")
	var cell := _free_spot(2)
	assert(main.base.can_place("radio", cell), "radio fits")
	var scrap0: int = Game.scrap
	assert(main.base.place_building("radio", cell), "radio blueprint")
	assert(Game.scrap == scrap0 - 90 and is_equal_approx(Game.salvage["electronics"], 4.0), "90 scrap, 6 electronics paid")
	assert(not main.base.can_place("radio", _free_spot(2)) and "one" in e.tool_note("radio"), "only one radio station")
	main.base.remove_blueprint(cell)
	assert(Game.scrap == scrap0 and is_equal_approx(Game.salvage["electronics"], 10.0) and Game.buildings.is_empty(), "removing the blueprint refunds both")
	assert(main.base.place_building("radio", cell), "placed again")
	e.step(0.1)
	assert(not e.contact, "an unbuilt radio makes no contact")
	var b: Dictionary = main.base.building_at(cell)
	main.base._finish_site(b)
	e.step(0.1)
	assert(e.contact and _logged("we read you"), "contact once the radio is built and run")
	assert(e.tool_visible("airstrip"), "airstrip tool appears")
	Game.people[0]["skill"] = "farmer"
	e.step(0.1)
	assert(e.contact, "contact stays")


func _airstrip() -> void:
	assert("perimeter" in e.tool_note("airstrip") and not main.base.can_place("airstrip", Vector2i.ZERO), "fence radius 160: no strip")
	Game.base_radius = 220.0 # perimeter level 1
	assert(e.tool_note("airstrip") == "", "radius 220: allowed")
	print("evac: spot on the real terrain: ", e.find_spot(0), " / ", e.find_spot(1))
	_grass()
	var spot := e.find_spot(0)
	assert(spot.x != -99999 and e.strip_problem(spot, 0) == "" and main.base.can_place("airstrip", spot), "a strip fits on clean ground at %s" % spot)
	assert(e.find_spot(1).x != -99999, "and one turned")
	assert("fence" in e.strip_problem(spot + Vector2i(30, 0), 0), "outside the fence")
	var c0 := Vector2i((main.base.global_position / 16.0).floor())
	assert("pad" in e.strip_problem(c0 - STRIP_HALF, 0), "across the pad")
	for t in [T.ROCK, T.WATER, T.BUILDING]:
		var cell := spot + Vector2i(5, 1)
		main.chunks.edit(cell, t)
		assert(e.strip_problem(spot, 0) != "" and not main.base.can_place("airstrip", spot), "tile %d in the way" % t)
		main.chunks.edit(cell, T.GRASS)
	Game.sandbags[spot + Vector2i(3, 2)] = {"kind": "sandbag", "hp": 100.0, "built": true, "rot": 0}
	assert("sandbag" in e.strip_problem(spot, 0), "a sandbag in the way")
	Game.sandbags.clear()
	for t in [T.ROAD, T.FIELD, T.HOUSE_YARD, T.ASPHALT]: # roads, fields, yards are fine
		main.chunks.edit(spot + Vector2i(7, 2), t)
		assert(e.strip_problem(spot, 0) == "", "tile %d is fine" % t)
	main.chunks.edit(spot + Vector2i(2, 2), T.FOREST)
	assert(e.strip_problem(spot, 0) == "", "forest is felled, not refused")
	var tree: Node2D = main.spawn_prop("tree", main.base.cell_pos(spot + Vector2i(4, 1)))
	var outside: Node2D = main.spawn_prop("tree", main.base.cell_pos(spot + Vector2i(4, 6)))
	var tree_pos := tree.position
	# placing: cost, rot, node, felled trees
	Game.scrap = 500
	main.base.place_rot = 0
	assert(main.base.place_building("airstrip", spot), "airstrip blueprint")
	assert(Game.scrap == 350, "150 scrap paid")
	var b: Dictionary = e.strip()
	assert(b["cell"] == spot and b["rot"] == 0 and not b["built"], "stored with cell and rot")
	assert(main.base.site_nodes.has(spot) and main.base.site_nodes[spot].rotation == 0.0, "strip node")
	assert(main.chunks.get_cell_atlas_coords(spot + Vector2i(2, 2)).x == T.GRASS, "forest tile became grass")
	assert(tree.is_queued_for_deletion() and main.chunks.cuts.has(tree_pos), "the tree on the strip is cut and remembered")
	assert(not outside.is_queued_for_deletion(), "trees beside it stay")
	assert(not main.base.can_place("airstrip", spot) and "one" in e.tool_note("airstrip"), "only one airstrip")
	assert(not main.base.free_cell(spot + Vector2i(1, 1)) and not main.base.can_place("sandbag", spot + Vector2i(1, 1)) and not main.base.can_place("barracks", spot + Vector2i(1, 1)), "nothing goes on the strip")
	assert(e.on_strip(spot) and e.on_strip(spot + Vector2i(23, 3)) and not e.on_strip(spot + Vector2i(24, 0)), "strip cells")
	# RMB on the blueprint refunds, then the turned one
	main.base.remove_blueprint(spot + Vector2i(10, 1))
	assert(e.strip().is_empty() and Game.scrap == 500 and not main.base.site_nodes.has(spot), "removed and refunded")
	main.base.place_rot = 1
	var spot1 := e.find_spot(1)
	assert(main.base.place_building("airstrip", spot1), "turned airstrip")
	assert(e.strip()["rot"] == 1 and absf(main.base.site_nodes[spot1].rotation - PI / 2.0) < 0.01, "node turned")
	assert(Evac.strip_rect(e.strip()).size == Vector2(64, 384), "4x24 cells upright")
	# the countdown starts when it is finished
	e.step(0.1)
	assert(e.phase == "", "a blueprint starts nothing")
	main.base._finish_site(e.strip())
	e.step(0.1)
	assert(e.phase == "countdown" and e.siege_day == 18 and _logged("transport lands"), "countdown of 3 days: siege day %d" % e.siege_day)
	assert(not e.tool_visible("airstrip") and e.status().contains("transport in 3 day"), "status: %s" % e.status())
	assert(e.tool_visible("sandbag") and e.tool_visible("motor_pool") and e.tool_visible("demolish"), "the other build tools stay during the countdown")
	# bandit raids keep out of the siege night, but not of other nights
	main.bandits.camps["evac_test"] = {"uid": "evac_test", "kind": "prison", "pos": main.base.global_position + Vector2(2500, 0), "garrison": {}, "prisoners": 0,
		"cleared": false, "known": true, "looted": false}
	assert(Assault.night_taken(e.siege_day) and Evac.siege_night(e.siege_day), "the siege night is taken")
	assert(not main.bandits.plan_base_raid(e.siege_day, true), "no planned raid on the siege night")
	var free_day := e.siege_day + 1
	while Assault.night_taken(free_day):
		free_day += 1
	assert(main.bandits.plan_base_raid(free_day, true), "a free night still gets one")
	main.bandits.base_raid_day = -1
	main.bandits.last_base_raid = -100
	main.bandits.camps.erase("evac_test")


func _reload_mid_countdown() -> void:
	var siege_day: int = e.siege_day
	var strip: Dictionary = e.strip().duplicate()
	var saved: Dictionary = e.save_state().duplicate(true)
	assert(var_to_str(bytes_to_var(var_to_bytes(saved))) == var_to_str(saved), "built-in types only")
	await _reload()
	assert(e.phase == "countdown" and e.siege_day == siege_day and e.contact and e.announced and not e.victory, "countdown back after a load")
	assert(var_to_str(e.save_state()) == var_to_str(saved), "same state")
	assert(var_to_str(e.strip()) == var_to_str(strip) and main.base.site_nodes.has(strip["cell"]), "airstrip entry and node back")
	assert(absf(main.base.site_nodes[strip["cell"]].rotation - PI / 2.0) < 0.01, "node still turned")
	assert(Game.base_radius == 220.0, "radius saved")
	e.step(0.1)
	assert(e.phase == "countdown", "the countdown goes on")


func _siege() -> void:
	var d: int = e.siege_day
	Game.day = d - 1
	Game.time = 0.5
	main.assault._on_day(Game.day) # plans tomorrow's assault
	e._on_day(Game.day)
	assert(main.assault.plan.get("day") == d and _logged("transport comes in 1 day"), "the siege night is planned: %s" % [main.assault.plan])
	Game.day = d
	Game.attack_pending = false
	e._on_day(d)
	assert(Game.attack_pending and _logged("final siege"), "dusk: the siege is due")
	_clear_enemies()
	Game.time = 0.7999
	for i in 120:
		await frame
		if Game.attack_active:
			break
	assert(Game.attack_active, "the assault started")
	var a: Assault = main.assault
	var total := Assault.wave_size(d)
	if Assault.blood_moon(d):
		total = int(total * Assault.BLOOD_SIZE)
	total = int(total * Assault.FINAL_SIZE)
	assert(a.final and e.phase == "siege", "final siege running")
	assert(a.queued() == total and a.surges.size() == Assault.FINAL_PUSHES - 1, "%d attackers in %d pushes: queued %d, surges %d" % [total, Assault.FINAL_PUSHES, a.queued(), a.surges.size()])
	assert(total > Assault.wave_size(d) * Assault.BLOOD_SIZE, "bigger than any blood moon")
	assert(_enemies().filter(func(x): return x.kind == "boss").size() >= Assault.FINAL_BOSSES, "bosses")
	assert(get_tree().get_nodes_in_group("bandits").size() > 0 and _logged("bandits attacking"), "the bandit raid comes with it")
	assert("FINAL SIEGE" in Assault.alert_text() and Evac.holds_assault(), "HUD text and hold")
	assert(e.status().contains("FINAL SIEGE") == false and e.status().contains("hold the base"), "status: %s" % e.status())
	var saved: Dictionary = a.save_state()
	assert(saved["final"] and var_to_str(bytes_to_var(var_to_bytes(saved))) == var_to_str(saved), "final flag saved")
	# the siege does not end by itself, however empty it gets
	_clear_enemies()
	for i in 5:
		a._process(0.5)
	assert(Game.attack_active and a.final, "no end while the transport is on its way")


func _landing_and_boarding() -> void:
	var d: int = e.siege_day
	Game.day = d + 1
	Game.time = 0.03
	e.step(0.1)
	assert(e.phase == "siege", "not yet")
	Game.time = 0.0405
	var bandits0 := get_tree().get_nodes_in_group("bandits").size()
	e.step(0.1)
	assert(e.phase == "landed" and e.plane != null and _logged("on final"), "the transport lands in the second half of the night")
	var push := int(Assault.wave_size(d) * Evac.LANDING_PUSH)
	assert(main.assault.queued() == push, "landing push of %d: %d" % [push, main.assault.queued()])
	assert(get_tree().get_nodes_in_group("bandits").size() == bandits0, "no second bandit raid at the landing")
	_clear_enemies()
	var centre: Vector2 = Evac.strip_rect(e.strip()).get_center()
	e.step(Evac.TAXI_SECONDS)
	assert(e.status().contains("loading"), "status: %s" % e.status())
	var b0: float = e.board
	var z: Node2D = main.spawn_enemy("shambler", centre + Vector2(0, 40))
	e.step(5.0)
	assert(e.hostiles_on_strip() == 1 and e.board == b0 and e.status().contains("CLEAR THE STRIP") and _logged("hostile"), "a zombie on the strip stops the loading")
	var far: Node2D = main.spawn_enemy("shambler", centre + Vector2(300, 0)) # beside the strip it does not
	z.free()
	assert(e.hostiles_on_strip() == 0, "far zombies do not count")
	far.free()
	e.step(5.0)
	assert(is_equal_approx(e.board, b0 + 5.0), "loading goes on: %f" % e.board)
	assert(Game.running and e.phase == "landed", "not loaded yet")
	var w: Node2D = main.wrecks # a Chinook loads faster (heli_types "evac" 1.5)
	var t0: String = w.wrecks[w.active]["type"]
	w.wrecks[w.active]["type"] = "chinook"
	assert(is_equal_approx(e.board_seconds(), Evac.BOARD_SECONDS / 1.5) and e.status().contains("/40 s"), "Chinook boarding: %s" % e.status())
	w.wrecks[w.active]["type"] = t0
	assert(is_equal_approx(e.board_seconds(), Evac.BOARD_SECONDS), "other helis load in BOARD_SECONDS")
	e.step(Evac.BOARD_SECONDS - e.board - 0.5)
	assert(e.phase == "landed", "half a second short")
	_online_setup()
	e.step(1.0)
	assert(e.phase == "choice", "loaded")
	var on_disk: Dictionary = Save.read()["systems"]["evac"]
	assert(on_disk["phase"] == "choice" and on_disk["victory"], "boarding saves at once: %s" % [on_disk])
	var v: int = Game.meta["victories"]
	e._boarded()
	assert(Game.meta["victories"] == v, "boarding twice counts once")


## A ranked run waiting in the outbox of an unreachable server.
func _online_setup() -> void:
	Online.enabled = true
	Online.ranked = true
	Online.url = "http://127.0.0.1:9"
	Online._outbox.clear()
	Online._run = {"id": "evac-test-run", "ranked": true, "started": true, "ended": false, "modifiers": []}


func _victory_screen() -> void:
	assert(e.victory and Game.meta["victories"] == meta0["victories"] + 1, "the victory is counted: %d" % Game.meta["victories"])
	assert(e.flown.size() == Game.rescued and Game.people.all(func(p): return p["name"] in e.flown), "everyone at the base flew: %d names" % e.flown.size())
	assert(get_tree().paused and main.ui_open, "the game waits for the choice")
	var ui: CanvasLayer = main.get_children().filter(func(c): return c.get("names") != null and c is CanvasLayer)[0]
	assert(ui.visible and "Saved: %d" % Game.saved_count() in ui.body.text and Game.people[0]["name"] in ui.names.text, "victory screen: %s / %s" % [ui.body.text, ui.names.text])
	assert(Online._outbox.size() == 1 and Online._outbox[0]["victory"] and not Online._outbox[0]["ended"] and not Online._run["ended"], "the server hears of the victory, the run is not ended: %s" % [Online._outbox])
	# a save made on this screen shows it again
	assert(e.save_state()["phase"] == "choice" and e.save_state()["victory"], "saved on the victory screen")


func _stay_behind() -> void:
	var victories: int = Game.meta["victories"]
	var ui: CanvasLayer = main.get_children().filter(func(c): return c.get("names") != null and c is CanvasLayer)[0]
	ui._pick(true)
	assert(not get_tree().paused and not main.ui_open and not ui.visible, "back in the game")
	assert(e.phase == "done" and e.victory and Game.running and not Evac.holds_assault(), "the run goes on, the victory stays")
	assert(Game.meta["victories"] == victories and not Online._run["ended"], "counted once, run not ended")
	assert(e.plane.leaving == 0.0, "the transport takes off")
	assert(e.tool_note("airstrip") != "" and not e.tool_visible("airstrip") and not e.tool_visible("radio"), "no second evacuation: %s" % e.tool_note("airstrip"))
	assert(e.tool_visible("sandbag") and e.tool_visible("motor_pool"), "building goes on after STAY BEHIND")
	var siege := e.siege_day
	Game.day += 5
	e.step(0.1)
	e._on_day(Game.day)
	assert(e.phase == "done" and not Evac.siege_night(siege) and not Evac.siege_night(Game.day), "nothing starts again")
	# the assault can end now
	main.assault.clear_wave()
	main.assault._process(0.5)
	assert(not Game.attack_active and not main.assault.final, "the siege is over once the transport is out")
	# the leaving transport frees itself
	var plane := e.plane
	plane._process(Evac.LEAVE_SECONDS + 1.0)
	await frame
	assert(not is_instance_valid(plane), "plane gone")
	# a later death carries the victory to the server
	Game.end_run("died after staying")
	assert(not Game.running and Game.meta["victories"] == victories, "death does not count the victory again")
	assert(Online._outbox.size() == 1 and Online._outbox[0]["ended"] and Online._outbox[0]["victory"], "end_run sends victory = true: %s" % [Online._outbox])
	Online.enabled = false
	Online._outbox.clear()
	Online._run = {}
	Online.ranked = false
	Online.url = OnlineConfig.URL
	DirAccess.remove_absolute(Online._dir + "outbox.json")


func _end_run() -> void:
	Game.running = true
	e.phase = "choice"
	e.victory = true
	var victories: int = Game.meta["victories"]
	var runs: int = Game.meta["runs"]
	var reasons: Array[String] = []
	Game.run_ended.connect(func(r: String): reasons.append(r))
	e.choose(false)
	assert(not Game.running and reasons == [Evac.WON], "END RUN ends the run as a win: %s" % [reasons])
	assert(Game.meta["runs"] == runs + 1 and Game.meta["victories"] == victories and not Save.has_run(), "recorded, not counted twice, the save is gone")
	var over: CanvasLayer = main.get_children().filter(func(c): return c is CanvasLayer and c.get("body") != null and c.get("title_label") != null)[0]
	assert(over.visible and over.title_label.text == "VICTORY" and "victories" in over.body.text, "game over screen says VICTORY: %s" % over.body.text)


# --- helpers

const STRIP_HALF := Vector2i(12, 2)


## Top-left cell of a free n x n spot inside the fence.
func _free_spot(n: int) -> Vector2i:
	var c0 := Vector2i((main.base.global_position / 16.0).floor())
	for r in range(3, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := c0 + Vector2i(dx, dy)
				var ok := true
				for x in n:
					for y in n:
						ok = ok and main.base.free_cell(cell + Vector2i(x, y))
				if ok:
					return cell
	return Vector2i.ZERO


## Clean grass around the pad (the real terrain may hold houses and water at the start site).
func _grass() -> void:
	var c0 := Vector2i((main.base.global_position / 16.0).floor())
	for dx in range(-16, 17):
		for dy in range(-16, 17):
			var c := c0 + Vector2i(dx, dy)
			if main.base.building_at(c).is_empty():
				main.chunks.edit(c, T.GRASS)
