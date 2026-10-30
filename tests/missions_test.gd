extends Node
## Headless test of the radio missions (docs/ROADMAP.md P13). main.gd adds this node when env SMOKE=missions (base founded):
##   SMOKE=missions godot --headless --path . --quit-after 30000
## Offers (timer, limit, targets in range), expiry, and each type start to finish: rooftop rescue, black box, screamer,
## escort, plus camp and medicine against fake provider nodes; rewards, the J list, the save hook.
## The clock, the spawner and the mission timer are driven by hand. A type with no site in range for the random seed
## is forced onto the nearest site of any distance (printed), so the ticks are always tested.

const CM := preload("res://scripts/chunk_manager.gd")
const M := preload("res://scripts/missions.gd")


class FakeProvider extends Node:
	var list := []

	func camps() -> Array:
		return list

	func allies() -> Array:
		return list


var main: Node2D
var missions: Node
var frame: Signal
var log: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	missions = main.missions
	frame = get_tree().process_frame
	await frame
	await frame
	Game.set_process(false) # the test owns the clock
	main.spawner.set_process(false)
	missions.set_process(false)
	Game.radio_message.connect(func(msg: String): log.append(msg))
	Game.level = Game.LEVEL_CAP # kills must not offer upgrade cards (they pause)
	Game.time = 0.5
	Game.day = 3
	Game.hp = 1.0e6
	Game.seats = 8
	_offers()
	await _rooftop()
	await _blackbox()
	await _screamer()
	await _escort()
	_providers()
	await _ui_and_save()
	print("MISSIONS OK")
	get_tree().quit(0)


func _base() -> Vector2:
	return main.base.global_position


func _reset() -> void:
	missions.open.clear()
	missions.used.clear()
	missions._watched.clear()
	missions._seen.clear()


## Fly there and wait until the chunks around `pos` are generated.
func _goto(pos: Vector2) -> void:
	Game.heli.position = pos
	var c := Vector2i((pos / 512.0).floor())
	for i in 900:
		if range(-1, 2).all(func(x): return range(-1, 2).all(func(y): return main.chunks.loaded.has(c + Vector2i(x, y)))):
			break
		await frame
	await frame


## An offered mission of `type`, or (no site in range for this seed) one forced onto the nearest site of any distance.
func _force(type: String) -> Dictionary:
	var m: Dictionary = missions.offer(type)
	if not m.is_empty():
		var d: float = m["pos"].distance_to(_base())
		assert(d >= M.MIN_DIST - 400.0 and d <= M.MAX_DIST + 400.0, "%s target in range: %d px" % [type, d]) # screamer nests sit 300 px off their town
		return m
	var kinds: Array = ["airliner"] if type == "blackbox" else CM.TOWN_SIZE.keys()
	var sites: Array = main.chunks.sites_near(_base(), 20000.0).filter(func(s): return s.kind in kinds and s.pos.distance_to(_base()) >= M.MIN_DIST)
	if sites.is_empty(): # crash sites are rare: any open ground will do for the tick
		sites = [{"uid": "fake:1", "pos": _base() + Vector2(1500, 600)}]
	print("MISSIONS note: no %s site in range for this seed, forced %s" % [type, sites[0].uid])
	return missions._add(type, {"pos": sites[0].pos + (Vector2(300, 0) if type == "screamer" else Vector2.ZERO), "text": "forced", "state": {"uid": sites[0].uid, "arrived": 0}})


func _offers() -> void:
	assert(Save._hooks.has("missions"), "the save hook is registered")
	assert(InputMap.has_action("missions"), "J is an action")
	var types: Array = missions.available_types()
	types.sort()
	assert(types == ["blackbox", "escort", "rooftop", "screamer"], "no provider, no camp / medicine: %s" % [types])
	for t in M.TYPES:
		assert(missions.has_method("_make_" + t) and missions.has_method("_tick_" + t), "%s has make and tick" % t)
	# the timer offers one (day 3, no assault) when some site is in range
	missions.offer_t = 0.01
	missions.step(0.1)
	var from := _base()
	var any: bool = main.chunks.sites_near(from, M.MAX_DIST).any(func(s): return s.pos.distance_to(from) >= M.MIN_DIST)
	assert(missions.open.size() == 1 or not any, "the timer radioed a mission: %d open" % missions.open.size())
	for m: Dictionary in missions.open:
		assert(m["pos"].distance_to(from) <= M.MAX_DIST + 400.0 and m["left"] > 100.0 and m["reward"]["scrap"] > 0, "target, time and reward: %s" % [m])
		assert(log.any(func(l): return l.contains(m["title"])), "the radio line names the mission")
	# day 1 offers nothing by itself
	_reset()
	Game.day = 1
	missions.offer_t = 0.01
	missions.step(0.1)
	assert(missions.open.is_empty(), "no missions on day 1")
	Game.day = 3
	# at most MAX_OPEN
	for i in M.MAX_OPEN:
		missions._add("blackbox", {"pos": Vector2(1000 + i, 0), "text": "x", "state": {}})
	assert(missions.open.size() == M.MAX_OPEN and missions.offer("rooftop").is_empty(), "limit of %d open" % M.MAX_OPEN)
	# expiry removes it
	var gone: Dictionary = missions.open[0]
	gone["left"] = 0.05
	missions.step(0.1)
	assert(not gone in missions.open and missions.open.size() == M.MAX_OPEN - 1, "expired mission dropped")
	assert(log.any(func(l): return l.contains("window closed")), "expiry on the radio")
	_reset()


func _rooftop() -> void:
	_reset()
	var m := _force("rooftop")
	await _goto(m["pos"])
	missions.step(0.1)
	assert(m["state"].has("poi"), "the family appears when the heli comes close")
	var poi: Node2D = missions._poi(m)
	assert(poi != null and poi.kind == "survivors" and poi.survivors.size() >= M.FAMILY.x and poi.survivors.size() <= M.FAMILY.y, "a family of 3-5")
	assert(not m["state"]["roof"] or (main.chunks.tile_at(poi.position) == CM.T.BUILDING and not main.chunks.is_landable(poi.position)), "on a roof: no landing there: tile %d, %s" % [main.chunks.tile_at(poi.position), m["text"]])
	assert(m["pos"] == poi.position and main.radio_target == poi, "pos and compass follow the roof")
	assert(missions.open.has(m), "still open while they wait")
	# winch them aboard: reward
	m["reward"]["person"] = "engineer"
	var scrap0 := Game.scrap
	var rescued0 := Game.rescued
	var pending0: int = main.morale.pending.size()
	Game.passengers = 0
	var n := 0
	while poi.winch_one():
		n += 1
	missions.step(0.1)
	assert(n >= M.FAMILY.x and poi.done and missions.open.is_empty() and missions.completed == 1, "rescued %d, mission done" % n)
	assert(Game.scrap >= scrap0 + m["reward"]["scrap"], "scrap paid")
	assert(main.morale.pending.size() == pending0 + 1, "morale reported")
	assert(Game.rescued == rescued0 + 1 and Game.people.back()["skill"] == "engineer", "an engineer joined: %s" % [Game.people.back()])
	assert(log.any(func(l): return l.contains("trained engineer")), "the recruit is announced")
	# a lost family fails it
	Game.passengers = 0
	var f := _force("rooftop")
	await _goto(f["pos"])
	missions.step(0.1)
	var poi2: Node2D = missions._poi(f)
	for i in 80:
		poi2.lose_survivor(true)
	missions.step(0.1)
	assert(missions.open.is_empty() and missions.completed == 1, "nobody left: failed, no reward")
	print("MISSIONS rooftop OK")


func _blackbox() -> void:
	_reset()
	var m := _force("blackbox")
	await _goto(m["pos"])
	Game.heli.landed = false
	missions.step(0.1)
	assert(not missions.open.is_empty(), "flying over it is not enough")
	Game.heli.landed = true
	Game.heli.position = m["pos"] + Vector2(TARGET_OFF, 0)
	var parts0: float = Game.salvage["parts"]
	var elec0: float = Game.salvage["electronics"]
	var kp0: int = missions.key_parts
	var n0 := get_tree().get_nodes_in_group("enemies").size()
	missions.step(0.1)
	assert(missions.open.is_empty() and missions.key_parts == kp0 + 1, "landed on the crash site: done, a key part")
	assert(Game.salvage["parts"] == parts0 + M.BLACKBOX_SALVAGE["parts"] and Game.salvage["electronics"] == elec0 + M.BLACKBOX_SALVAGE["electronics"], "salvage paid")
	assert(get_tree().get_nodes_in_group("enemies").size() >= n0 + 3, "the landing noise brought a wave")
	Game.heli.landed = false
	print("MISSIONS blackbox OK")


const TARGET_OFF := 20.0


func _screamers(m: Dictionary) -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(x): return "state" in x and x.kind == "screamer" and x.state.get("mission", -1) == m["id"] and not x.is_queued_for_deletion())


func _screamer() -> void:
	_reset()
	var m := _force("screamer")
	Game.heli.position = _base()
	missions.step(0.1)
	assert(_screamers(m).is_empty(), "nothing out while the heli is far")
	await _goto(m["pos"])
	missions.step(0.1)
	var s := _screamers(m)
	assert(s.size() == 1, "the screamer appears: %d" % s.size())
	var e: Node2D = s[0]
	var guards: int = get_tree().get_nodes_in_group("enemies").filter(func(x): return "state" in x and x.kind == "shambler" and x.position.distance_to(e.position) < 80.0).size()
	assert(guards >= M.GUARDS, "guards around it: %d" % guards)
	assert(m["pos"] == e.global_position, "the target follows the screamer")
	# a night calls a horde, once per night
	Game.time = 0.95
	var n0 := get_tree().get_nodes_in_group("enemies").size()
	missions.step(0.1)
	var n1 := get_tree().get_nodes_in_group("enemies").size()
	assert(n1 >= n0 + M.NIGHT_HORDE, "night horde: %d -> %d" % [n0, n1])
	missions.step(0.1)
	assert(get_tree().get_nodes_in_group("enemies").size() == n1, "only one per night")
	Game.time = 0.5
	# the save hook round trip keeps the link to the live screamer
	missions.load_state(bytes_to_var(var_to_bytes(missions.save_state())))
	missions.step(0.1)
	assert(_screamers(m).size() == 1 and missions._watched.size() == 1, "found again after a load, no second one")
	# despawned (heli far away) is not dead: it is back when the heli returns
	e = _screamers(m)[0]
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e.free()
	await frame
	missions.step(0.1)
	assert(not missions.open.is_empty() and missions.open[0]["state"].get("dead", false) == false, "despawn is not a kill")
	assert(_screamers(m).size() == 1, "a new screamer when the heli is close again")
	# shoot it
	e = _screamers(m)[0]
	e.hit(1.0e6)
	await frame
	await frame
	missions.step(0.1)
	assert(missions.open.is_empty() and missions.completed == 3, "screamer dead: mission done")
	print("MISSIONS screamer OK")


func _escort() -> void:
	_reset()
	var m := _force("escort")
	await _goto(m["pos"])
	missions.step(0.1)
	var poi: Node2D = missions._poi(m)
	assert(poi != null and poi.walking_home and poi.survivors.size() >= M.REFUGEES.x, "refugees out, walking home")
	# they wait while the heli is away, walk while it is close
	Game.heli.position = m["pos"] + Vector2(M.FOLLOW_DIST + 150.0, 0)
	missions.step(0.1)
	assert(poi.survivors.all(func(x): return x.target == null), "they wait when the heli is far")
	Game.heli.position = m["pos"] + Vector2(100, 0)
	missions.step(0.1)
	assert(poi.survivors.all(func(x): return x.target == main.base), "they walk to the base when it is close")
	# arrival: put them at the pad
	var n: int = poi.survivors.size()
	m["reward"].erase("person") # a recruit would add to the head count
	var rescued0 := Game.rescued
	var state: Dictionary = m["state"]
	for x in poi.survivors:
		x.global_position = _base() + Vector2(3, 0)
	Game.heli.position = _base()
	missions.step(0.1)
	await frame
	await frame
	missions.step(0.1)
	assert(state["arrived"] == n and Game.rescued == rescued0 + n, "%d arrived, base +%d" % [state["arrived"], Game.rescued - rescued0])
	assert(missions.open.is_empty() and missions.completed == 4, "escort done")
	# all lost fails it
	var f := _force("escort")
	await _goto(f["pos"])
	missions.step(0.1)
	var poi2: Node2D = missions._poi(f)
	for i in 80:
		poi2.lose_survivor(true)
	missions.step(0.1)
	assert(missions.open.is_empty() and missions.completed == 4, "all dead: failed")
	print("MISSIONS escort OK")


func _providers() -> void:
	_reset()
	Game.heli.position = _base()
	# clear the camp: only with a "bandits" node
	var bandits := FakeProvider.new()
	bandits.name = "bandits"
	main.add_child(bandits)
	assert(missions.available_types().has("camp") and not missions.available_types().has("medicine"), "camp offered once bandits exist")
	assert(missions.offer("camp").is_empty(), "no camps listed: nothing to offer")
	bandits.list = [{"uid": "camp:7", "pos": _base() + Vector2(1800, 0)}]
	var m: Dictionary = missions.offer("camp")
	assert(not m.is_empty() and m["pos"] == _base() + Vector2(1800, 0) and m["state"]["uid"] == "camp:7", "camp mission at the camp")
	missions.step(0.1)
	assert(missions.open.has(m), "open while the camp stands")
	var scrap0 := Game.scrap
	bandits.list = []
	missions.step(0.1)
	assert(missions.open.is_empty() and Game.scrap >= scrap0 + m["reward"]["scrap"], "camp gone: done and paid")
	bandits.list = [{"uid": "camp:7", "pos": _base() + Vector2(1800, 0)}]
	assert(missions.offer("camp").is_empty(), "the same camp is not offered twice")
	bandits.free()
	# medicine: with villages, or offered by a village
	assert(not missions.available_types().has("camp"), "camp gone with the provider")
	var villages := FakeProvider.new()
	villages.name = "villages"
	main.add_child(villages)
	villages.list = [{"uid": "village:1", "pos": _base() + Vector2(0, 1500)}]
	Game.base_medicine = 0.0
	assert(missions.offer("medicine").is_empty(), "no medicine at the base: not offered")
	Game.base_medicine = 5.0
	var v: Dictionary = missions.offer("medicine")
	assert(not v.is_empty() and v["pos"] == _base() + Vector2(0, 1500), "medicine run to the village")
	Game.heli.position = v["pos"]
	Game.heli.landed = false
	missions.step(0.1)
	assert(not missions.open.is_empty(), "flying over is not delivering")
	Game.heli.landed = true
	Game.base_medicine = 1.0
	missions.step(0.1)
	assert(not missions.open.is_empty() and log.any(func(l): return l.contains("we need")), "short on medicine: they ask")
	Game.base_medicine = 5.0
	missions.step(0.1)
	assert(missions.open.is_empty() and is_equal_approx(Game.base_medicine, 5.0 - M.MEDICINE_COST), "delivered, medicine taken")
	var own: Dictionary = missions.offer("medicine", {"uid": "village:2", "pos": _base() + Vector2(900, 900)}) # a village offering by itself
	assert(not own.is_empty() and own["pos"] == _base() + Vector2(900, 900), "a village can offer its own")
	villages.free()
	Game.heli.landed = false
	_reset()
	print("MISSIONS providers OK")


func _ui_and_save() -> void:
	_reset()
	missions._add("blackbox", {"pos": _base() + Vector2(1200, 0), "text": "recover the black box", "state": {"uid": "x"}})
	missions._add("rooftop", {"pos": _base() + Vector2(0, -1500), "text": "a family on a roof", "state": {"uid": "y"}})
	var ui: CanvasLayer = main.get_children().filter(func(c): return c.get_script() == load("res://scripts/missions_ui.gd"))[0]
	var j := InputEventKey.new()
	j.keycode = KEY_J
	j.physical_keycode = KEY_J
	j.pressed = true
	assert(InputMap.event_is_action(j, "missions"), "J is the missions key")
	main.ui_open = true
	ui._unhandled_input(j)
	assert(not ui.panel.visible, "J does nothing under a menu")
	main.ui_open = false
	ui._unhandled_input(j)
	assert(ui.panel.visible, "J opens the list")
	var text: String = ui.body.text
	assert(text.contains("BLACK BOX") and text.contains("ROOFTOP RESCUE") and text.contains("Reward:") and text.contains("north"), "list shows both with a direction and the reward:\n%s" % text)
	assert(ui.tag.visible and ui.tag.text.contains("2"), "the tag counts them")
	for i in 3: # the HUD compass and minimap draw them
		await frame
	ui._unhandled_input(j)
	assert(not ui.panel.visible, "J closes it")
	# save hook: the file has them, a load gives them back
	missions.key_parts = 2
	assert(Save.autosave(), "autosaved")
	var d: Dictionary = Save.read()["systems"]["missions"]
	assert(d["open"].size() == 2 and d["key_parts"] == 2 and d["open"][0]["pos"] == missions.open[0]["pos"], "run.sav holds the missions")
	var before: Array = missions.open.duplicate(true)
	missions.open.clear()
	missions.key_parts = 0
	missions.load_state(d)
	assert(missions.open == before and missions.key_parts == 2, "load gives the same missions back")
	Save.delete_run()
	print("MISSIONS ui + save OK")
