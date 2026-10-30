extends Node
## Headless test of the assaults (scripts/assault.gd). main.gd adds this node when env SMOKE=assault:
##   SMOKE=assault godot --headless --path . --quit-after 30000
## Schedule (night_taken, blood_moon), themes (right kinds, ram state, screamer chain), pushes with pauses, the
## announced direction, the Watchtower report, the blood moon (clock held until the last attacker dies, 2x XP, morale),
## the HUD text, and a save in the middle of an assault that loads back (the node moves itself under the root and
## survives the scene reload, like save_test).

const NAME := "AssaultTest"

var main: Node2D
var a: Assault
var frame: Signal
var radio_log: Array[String] = []


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
	main = Game.world
	a = main.assault
	main.spawner.set_process(false)
	a.set_process(false) # stepped by hand
	Game.level = Game.LEVEL_CAP # no upgrade cards
	Game.radio_message.connect(func(m: String): radio_log.append(m))
	_schedule()
	_themes()
	_pushes()
	_screamer_chain()
	_announcement()
	await _blood_moon()
	await _save_mid_assault()
	print("ASSAULT OK")
	get_tree().quit(0)


func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	a.clear_wave()
	a.plan = {}
	a.theme = ""
	a.blood = false
	a.dir = -1
	Game.attack_active = false
	Game.attack_pending = false
	radio_log.clear()


func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return "target_base" in e and e.target_base)


func _kinds_queued() -> Array:
	var out: Array = a.queue.duplicate()
	for s in a.surges:
		out.append_array(s)
	return out


## Starts the assault of `day` with `theme` (and a blood moon / direction as given), hands the first push to the caller.
func _start(day: int, theme: String, dir := 2, blood := false) -> void:
	_clear()
	Game.day = day
	a.plan = {"day": day, "theme": theme, "dir": dir, "blood": blood, "known": false, "tower": false}
	Game.attack_active = true
	a._on_attack(day)


## Runs the wave by hand until everything is spawned (no end: the attackers stay alive).
func _spawn_all() -> void:
	for i in 2000:
		if a.queued() == 0:
			return
		a._process(0.5)
	assert(false, "the wave never finished spawning")


func _schedule() -> void:
	Game.day = 1
	Game.first_assault_day = 3
	assert(Assault.night_taken(3) and Assault.night_taken(6) and Assault.night_taken(9), "an assault every third day")
	assert(not Assault.night_taken(4) and not Assault.night_taken(5) and not Assault.night_taken(2), "no assault in between")
	assert(not Assault.blood_moon(3) and not Assault.blood_moon(6), "no blood moon in the first nights")
	assert(Assault.blood_moon(9) and Assault.blood_moon(18) and not Assault.blood_moon(12) and not Assault.blood_moon(10), "a blood moon every 9th night: %s" % [[9, 18, 12].map(Assault.blood_moon)])
	assert(Assault.night_taken(9) and Assault.night_taken(18), "a blood moon night is an assault night (bandits keep out)")
	Game.attack_pending = true # the tutorial's assault is not on the schedule
	assert(Assault.night_taken(Game.day), "an assault due tonight counts")
	Game.attack_pending = false
	Game.base_founded = false
	assert(not Assault.night_taken(3), "no base, no assault")
	Game.base_founded = true
	print("ASSAULT schedule ok")


func _themes() -> void:
	var total := Assault.wave_size(12)
	# runner storm: mostly runners
	_start(12, "runner_storm")
	var kinds := _kinds_queued()
	assert(kinds.size() == total, "wave size %d vs %d" % [kinds.size(), total])
	assert(kinds.count("runner") >= total * 0.6, "runner storm: %d runners" % kinds.count("runner"))
	assert("Runner storm" in " ".join(radio_log).replace("runner storm incoming", "Runner storm"), "named on the radio: %s" % [radio_log])
	# brute ram: brutes, armored ones from day 10, all with the ram state
	_start(12, "ram")
	kinds = _kinds_queued()
	assert(kinds.count("brute") >= 2 and kinds.count("brute_armored") >= 2, "ram: brutes %d armored %d" % [kinds.count("brute"), kinds.count("brute_armored")])
	_spawn_all()
	var brutes := _enemies().filter(func(e): return e.kind.begins_with("brute"))
	assert(brutes.size() >= 4 and brutes.all(func(e): return e.state.get("ram", false)), "ram brutes carry the ram state")
	assert(_enemies().filter(func(e): return not e.kind.begins_with("brute")).all(func(e): return not e.state.get("ram", false)), "only brutes ram")
	# a ram brute walks straight at the base
	var ram: Node2D = brutes[0]
	ram.process_mode = Node.PROCESS_MODE_DISABLED
	var spot := _open_spot(main.base.global_position, 260.0)
	ram.position = spot
	var d0 := ram.position.distance_to(main.base.global_position)
	for i in 20:
		ram._process(0.1)
	assert(ram.position.distance_to(main.base.global_position) < d0 - 10.0, "the ram brute closes in: %.1f -> %.1f" % [d0, ram.position.distance_to(main.base.global_position)])
	# an early ram wave has no armored brutes (day 3)
	_start(3, "ram")
	assert(not "brute_armored" in _kinds_queued(), "no armored brutes on day 3")
	# spitter siege, screamer chain, mixed
	_start(12, "siege")
	kinds = _kinds_queued()
	assert(kinds.count("spitter") >= total * 0.25, "siege: %d spitters" % kinds.count("spitter"))
	_start(12, "scream")
	kinds = _kinds_queued()
	assert(kinds.count("screamer") >= 2, "screamer chain: %d screamers" % kinds.count("screamer"))
	_start(12, "mixed")
	kinds = _kinds_queued()
	var special := {}
	for k in kinds:
		if k != "shambler":
			special[k] = true
	assert(special.size() >= 5, "mixed: %d kinds %s" % [special.size(), special.keys()])
	# nothing before day 4 that does not exist yet
	_start(3, "mixed")
	assert(not ("spitter" in _kinds_queued()) and not ("bloater" in _kinds_queued()) and not ("brute_armored" in _kinds_queued()), "mixed on day 3 only has what exists")
	# themes start with the 2nd assault, never the same twice, only ones that exist
	Game.first_assault_day = 3
	assert(a._roll(3)["theme"] == "", "no theme on the first assault")
	a.last_theme = "runner_storm"
	for i in 30:
		var t: String = a._roll(6)["theme"]
		assert(t != "" and t != "runner_storm" and Assault.THEMES[t]["min_day"] <= 6, "theme %s" % t)
	a.last_theme = ""
	assert(a._roll(6)["dir"] in range(8), "a compass direction")
	# the HUD text carries the name
	_start(12, "scream")
	assert("SCREAMER CHAIN" in Assault.alert_text() and "LEFT" in Assault.alert_text(), "HUD: %s" % Assault.alert_text())
	# the tutorial's wave is a plain small one
	_clear()
	Game.tutorial_wave = 8
	Game.attack_active = true
	a._on_attack(1)
	assert(a.queued() == 8 and a.theme == "" and not a.blood and a.surges.is_empty(), "tutorial wave: %d" % a.queued())
	print("ASSAULT themes ok")


func _open_spot(center: Vector2, dist: float) -> Vector2:
	for i in 16:
		var p := center + Vector2(dist, 0).rotated(i * TAU / 16.0)
		if main.is_walkable(p) and main.is_walkable(center.lerp(p, 0.5)):
			return p
	assert(false, "no open spot")
	return center


## A wave of 100+ comes in 2-3 pushes with a pause; it ends only when the last push is dead.
func _pushes() -> void:
	_start(12, "ram", 2)
	var total := a.queued()
	var first: int = a.queue.size()
	assert(a.surges.size() >= 1 and a.surges.size() <= 2 and first < total, "pushes: first %d of %d, %d more" % [first, total, a.surges.size()])
	# the first push is spawned, then they pull back
	var boss := _enemies().filter(func(e): return e.kind == "boss").size()
	assert(boss == 1, "a boss on a boss assault (day 12): %d" % boss)
	for i in first + 2:
		a._process(0.5)
	assert(a.queue.is_empty() and a.pause > 0.0 and a.surges.size() >= 1, "pause between the pushes")
	var n := _enemies().size()
	for i in 10: # 5 s: nothing new while they live
		a._process(0.5)
	assert(_enemies().size() == n and Game.attack_active, "pause: no new attackers")
	for e in _enemies():
		e.free()
	for i in 20: # the push is dead: the pause is short (QUICK_PAUSE)
		a._process(0.5)
		if not a.queue.is_empty():
			break
	assert(not a.queue.is_empty() or _enemies().size() > n - 1, "the next push follows")
	_spawn_all()
	assert(Game.attack_active, "still on while the last push lives")
	# direction: 70 % from east
	var east := 0
	var all := _enemies().filter(func(e): return e.kind != "boss")
	for e in all:
		if absf(wrapf((e.position - main.base.global_position).angle(), -PI, PI)) < 0.6:
			east += 1
	assert(east >= all.size() * 0.55, "from the announced direction: %d of %d" % [east, all.size()])
	var held: int = Game.meta["assaults_held"]
	for e in _enemies():
		e.free()
	a._process(0.5)
	assert(not Game.attack_active and Game.meta["assaults_held"] == held + 1 and a.plan.is_empty(), "assault over when the last attacker is dead")
	assert("Base secured" in " ".join(radio_log), "radio: base secured")
	print("ASSAULT pushes ok")


func _screamer_chain() -> void:
	_start(12, "scream")
	a.queue = []
	a.surges = []
	var s: Node2D = main.spawn_enemy("screamer", main.base.global_position + Vector2(300, 0), true)
	var n := _enemies().size()
	a._escalate(Assault.ESCALATE_EVERY)
	assert(_enemies().size() == n + 2 + 12 / 4, "a living screamer calls more: %d -> %d" % [n, _enemies().size()])
	s.free()
	for e in _enemies().filter(func(e): return e.kind == "screamer"): # the extras may include screamers
		e.free()
	n = _enemies().size()
	a._escalate(Assault.ESCALATE_EVERY)
	a.esc_cd = 0.0
	a._escalate(Assault.ESCALATE_EVERY)
	assert(_enemies().size() == n, "no screamer, no more")
	print("ASSAULT screamer chain ok")


func _announcement() -> void:
	_clear()
	Game.first_assault_day = 3
	Game.day = 8
	Game.time = 0.7
	a._on_day(8) # rolls tomorrow's: day 9 is the first blood moon
	assert(a.plan["day"] == 9 and a.plan["blood"], "the plan for the blood moon night: %s" % [a.plan])
	a._evening()
	assert(a.plan["known"] and not a.plan["tower"], "announced")
	assert(not "Watchtower" in " ".join(radio_log) and "blood moon" in " ".join(radio_log), "no tower, no direction; the blood moon is announced: %s" % [radio_log])
	# with a Watchtower: direction on the radio, an arrow for the HUD
	radio_log.clear()
	Game.buildings.append({"kind": "watchtower", "built": true, "cell": Vector2i(0, 0)})
	a.plan["known"] = false
	a.plan["dir"] = 1
	a._evening()
	assert(a.plan["tower"] and "Watchtower: movement north-east." in radio_log, "the tower reports: %s" % [radio_log])
	Game.buildings.pop_back()
	# the evening before only, not earlier in the day
	_clear()
	Game.day = 8
	Game.time = 0.3
	a._on_day(8)
	assert(a.plan["day"] == 9, "the plan survives")
	a._evening()
	assert(not a.plan["known"], "still too early on the day before")
	Game.time = 0.65
	a._evening()
	assert(a.plan["known"], "announced in the evening")
	_clear()
	print("ASSAULT announcement ok")


func _blood_moon() -> void:
	main.base.ui.set_worker("build", 0)
	_start(9, "mixed", 4, true)
	var total := int(Assault.wave_size(9) * Assault.BLOOD_SIZE)
	assert(a.queued() == total and a.surges.size() == 2, "blood moon: %d attackers in 3 pushes, %d" % [a.queued(), a.surges.size()])
	assert(_enemies().filter(func(e): return e.kind == "boss").size() == 1, "a boss for sure")
	assert(Assault.blood_active() and Assault.sky() == Assault.BLOOD_SKY and "BLOOD MOON" in Assault.alert_text(), "red sky, named")
	var e0: Node2D = _enemies()[0]
	assert(Assault.xp_mult(e0) == 2, "double XP for attackers")
	var stray: Node2D = main.spawn_enemy("shambler", main.base.global_position + Vector2(900, 0))
	assert(Assault.xp_mult(stray) == 1, "not for strays")
	stray.free()
	# one attacker left, the night is deep: the clock stands still
	a.clear_wave()
	for e in _enemies():
		e.free()
	var last: Node2D = main.spawn_enemy("shambler", main.base.global_position + Vector2(700, 0), true)
	last.process_mode = Node.PROCESS_MODE_DISABLED
	a.set_process(true)
	Game.time = Assault.HOLD_AT - 0.0001
	for i in 12:
		await frame
	assert(is_equal_approx(Game.time, Assault.HOLD_AT) and Game.is_night(), "the night is held: time %.4f" % Game.time)
	assert(Game.attack_active and a.held > 0.0 and "will not set" in " ".join(radio_log), "assault goes on: %s" % [radio_log])
	for i in 20:
		await frame
	assert(is_equal_approx(Game.time, Assault.HOLD_AT), "still held")
	# the cap: after HOLD_MAX s the dawn comes, the assault stays
	a.held = Assault.HOLD_MAX
	assert(not Assault.holds_dawn(), "the hold ends after HOLD_MAX")
	a.held = 1.0
	# last attacker dead: held, the clock runs again, morale +10
	var pending: int = main.morale.pending.size()
	last.free()
	for i in 20:
		await frame
	assert(not Game.attack_active and not a.blood, "blood moon over with the last attacker")
	assert(Game.time > Assault.HOLD_AT + 0.0001, "the clock runs again: %.5f" % Game.time)
	assert(main.morale.pending.size() == pending + 2 and main.morale.pending.has(["blood moon held", Assault.BLOOD_MORALE]), "morale +10: %s" % [main.morale.pending])
	assert(Assault.sky() == Assault.NIGHT_SKY and Assault.alert_text() == "", "normal sky again")
	a.set_process(false)
	print("ASSAULT blood moon ok")


## An assault in progress with a ram brute, saved while it runs, loaded in a fresh scene.
func _save_mid_assault() -> void:
	Game.rescued = 4
	assert(main.base.ui.set_worker("militia", 2), "militia assigned: rescued %d workers %s injured %d" % [Game.rescued, Game.workers, Game.injured])
	_start(12, "ram", 6)
	for i in 30:
		a._process(0.5)
	var queued: int = a.queued()
	var alive := _enemies().size()
	var rams := _enemies().filter(func(e): return e.state.get("ram", false)).size()
	var left_pushes: int = a.surges.size()
	assert(queued > 0 and alive > 0 and rams > 0 and left_pushes >= 1, "a wave in progress: queued %d alive %d rams %d" % [queued, alive, rams])
	var plan: Dictionary = a.plan.duplicate(true)
	Game.time = 0.9
	Game.scrap = 4242
	get_tree().paused = true
	assert(Save.autosave(), "saved in the middle of an assault")
	var saved: Dictionary = Save.read()["systems"]
	assert(saved["game"]["attack_active"] and saved["assault"]["theme"] == "ram" and saved.has("enemies"), "the save holds the assault")
	Save.pending = true
	get_tree().paused = false
	get_tree().reload_current_scene()
	await frame
	await frame
	await frame
	main = Game.world
	a = main.assault
	main.spawner.set_process(false)
	a.set_process(false)
	assert(Game.attack_active and Game.scrap == 4242, "loaded in the assault")
	assert(a.theme == "ram" and a.dir == 6 and a.queued() == queued and a.surges.size() == left_pushes, "wave state back: %s %d queued %d" % [a.theme, a.queued(), queued])
	assert(var_to_str(a.plan) == var_to_str(plan), "plan back")
	assert(_enemies().size() == alive and _enemies().filter(func(e): return e.state.get("ram", false)).size() == rams, "attackers and their ram state back")
	assert(main.base.defenders.get_child_count() == 2, "the militia man their posts again: %d, militia %d" % [main.base.defenders.get_child_count(), Game.workers["militia"]])
	var pause: float = a.pause
	for i in 4:
		a._process(0.5)
	assert(a.queued() < queued or a.pause < pause, "the wave goes on after the load: queued %d -> %d, pause %.1f -> %.1f" % [queued, a.queued(), pause, a.pause])
	print("ASSAULT save mid-assault ok")
