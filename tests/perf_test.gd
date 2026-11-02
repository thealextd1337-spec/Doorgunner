extends Node
## Headless performance scenarios (docs/ROADMAP2.md Q1). main.gd adds this node when env SMOKE=perf (base founded):
##   SMOKE=perf godot --headless --path . --quit-after 30000
## City approach, blood moon with BLOOD_N attackers, bandit camp + horde, convoy SEND on a far route, a long flight
## (memory). Each scenario runs real frames and reads the overlay's numbers (scripts/perf.gd); the desktop limits
## (P95_MAX on the work time, HITCH_MAX on the worst chunk-loading frame) must hold. Headless has no rendering and
## idles to ~7 ms frames (Windows sleeps in 15.6 ms steps), so the asserts use the work and chunk timers, not wall time,
## which other Godot processes on the machine also skew.
## The heli is moved by hand at FLY_SPEED per simulated 60 fps frame, whatever the real frame time.

const SIM_DT := 1.0 / 60.0
const FLY_SPEED := 115.0 # heli.gd MAX_SPEED
const P95_MAX := 33.0 # ms of work per frame, every scenario
const HITCH_MAX := 50.0 # ms of chunk loading in the worst frame while flying into new land
const BLOOD_N := 250
const HORDE_N := 40
const KILLS_PER_FRAME := 2 # the blood moon also kills and respawns, for corpses and particles
const LONG_FRAMES := 7000
const LONG_SPEED := 4.0 # x FLY_SPEED: more land per frame for the long flight

var main: Node2D
var heli: Node2D
var perf: Perf
var rows: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	heli = Game.heli
	await get_tree().process_frame
	await get_tree().process_frame
	perf = main.get_children().filter(func(n): return n is Perf)[0]
	main.spawner.set_process(false)
	main.assault.set_process(false)
	Game.level = Game.LEVEL_CAP # no upgrade cards
	heli.landed = false
	_overlay_check()
	await _city()
	await _blood_moon()
	await _bandits()
	await _convoy()
	await _long()
	print("perf scenarios (desktop, headless):\n" + "\n".join(rows))
	Save.delete_run()
	print("PERF OK")
	get_tree().quit(0)


## F3 toggles the overlay; its counts match the world.
func _overlay_check() -> void:
	assert(InputMap.has_action("perf"), "F3 action")
	var ev := InputEventAction.new()
	ev.action = "perf"
	ev.pressed = true
	perf._unhandled_input(ev)
	assert(perf.visible, "F3 shows the overlay")
	perf._unhandled_input(ev)
	assert(not perf.visible, "F3 hides it again")
	var s := perf.stats()
	assert(s["chunks"] == main.chunks.loaded.size() and s["pois"] == main.pois.size(), "overlay counts chunks and POIs")
	assert(perf.text(s).begins_with("FPS"), "overlay text")
	Perf.fx = 0.5
	assert(Perf.fx_cap(60) == 30 and Perf.fx_cap(1) == 1, "fx caps scale with the frame rate")
	Perf.fx = 1.0
	var near: Node2D = main.spawn_enemy("shambler", heli.position + Vector2(100, 0))
	var far: Node2D = main.spawn_enemy("shambler", heli.position + Vector2(Perf.AI_NEAR + 200.0, 0))
	assert(Perf.stride(near) == 1 and Perf.stride(far) == Perf.AI_FAR_STRIDE, "near enemies think every frame, far ones staggered")
	near.free()
	far.free()


func _keep_alive() -> void:
	Game.hp = Game.max_hp
	Game.fuel = Game.max_fuel
	Game.base_hp = Game.max_base_hp
	heli.vel = Vector2.ZERO


func _clear_enemies() -> void:
	for e in _walkers():
		e.queue_free()
	await get_tree().process_frame


## Zombies and bandits (zombie dens are in the group too but stay).
func _walkers() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return "target_base" in e or e is Bandit)


## Runs `frames` frames, calling `each(i)` before each, and records the overlay's numbers under `name`.
func _measure(name: String, frames: int, each: Callable) -> Dictionary:
	perf.reset()
	for i in frames:
		_keep_alive()
		each.call(i)
		await get_tree().process_frame
	var s := perf.stats()
	rows.append("  %-11s fps %4.0f  p50 %5.2f  p95 %5.2f  max %5.1f ms  work p50 %5.2f p95 %5.2f | chunk %.2f (%.1f)  path %.2f (%.1f)  spawn %.2f (%.1f) | enemies %d bandits %d chunks %d nodes %d mem %.0f MB" % [
		name, s["fps"], s["p50"], s["p95"], s["max"], s["cpu50"], s["cpu95"], s["chunk"], s["chunk_max"], s["path"], s["path_max"], s["spawn"], s["spawn_max"],
		s["enemies"], s["bandits"], s["chunks"], s["nodes"], s["mem_mb"]])
	assert(s["frames"] > 0 and s["fps"] > 0.0, "%s: overlay measured frames" % name)
	assert(s["cpu95"] < P95_MAX, "%s: work p95 %.1f ms over %.0f" % [name, s["cpu95"], P95_MAX])
	return s


## Jump the heli to `pos` and let the 5x5 around it load (a jump loads at once; not part of any measurement).
func _jump(pos: Vector2) -> void:
	heli.position = pos
	for i in 30:
		await get_tree().process_frame


## Fly in a straight line from 2500 px out into the nearest city (else the nearest town).
func _city() -> void:
	var ch: TileMapLayer = main.chunks
	var sites: Array = ch.sites_near(main.BASE_POS, 40000.0, "city")
	if sites.is_empty():
		sites = ch.sites_near(main.BASE_POS, 40000.0).filter(func(s): return s.kind in ch.TOWN_SIZE)
	var target: Vector2 = sites[0].pos
	var dir := Vector2.RIGHT.rotated(randf() * TAU)
	await _jump(target - dir * 2500.0)
	var s := await _measure("city/" + sites[0].kind, int(2500.0 / FLY_SPEED / SIM_DT), func(_i): heli.position += dir * FLY_SPEED * SIM_DT)
	assert(s["chunk_max"] < HITCH_MAX, "city approach: chunk hitch %.1f ms over %.0f" % [s["chunk_max"], HITCH_MAX])


## BLOOD_N attackers on the base, the heli hovering over it; KILLS_PER_FRAME die (corpses, particles) and come back.
func _blood_moon() -> void:
	await _jump(main.BASE_POS + Vector2(0, -60))
	await _clear_enemies()
	var kinds := ["shambler", "shambler", "shambler", "runner", "runner", "brute", "crawler", "spitter", "screamer", "bloater"]
	var spawn := func():
		for k in 20:
			var p: Vector2 = main.BASE_POS + Vector2(randf_range(350.0, 750.0), 0).rotated(randf() * TAU)
			if main.is_walkable(p):
				main.spawn_enemy(kinds[randi() % kinds.size()], p, true)
				return
	for i in BLOOD_N:
		spawn.call()
	await _measure("blood moon", 900, func(_i):
		var list := _walkers()
		for k in KILLS_PER_FRAME:
			var e: Node2D = list[randi() % list.size()]
			if not e.is_queued_for_deletion():
				e.hit(e.hp + 1.0, Vector2.RIGHT)
		while _walkers().size() < BLOOD_N:
			spawn.call())
	await _clear_enemies()


## A bandit camp woken by the heli 300 px off, with HORDE_N zombies wandering in.
func _bandits() -> void:
	Game.day = maxi(Game.day, main.bandits.first_camp_day())
	var pos: Vector2 = main.BASE_POS + Vector2(1600, 0)
	var camps: Array = main.chunks.sites_near(main.BASE_POS, 20000.0).filter(func(s): return s.kind in main.bandits.CAMP_KINDS and s.pos.length() > main.bandits.CAMP_MIN_BASE)
	if not camps.is_empty():
		pos = camps[0].pos
	main.bandits.add_camp("perf_camp", "prison", pos)
	await _jump(pos + Vector2(300, 0))
	for i in HORDE_N:
		main.spawn_enemy("shambler" if i % 4 else "runner", pos + Vector2(randf_range(150, 400), 0).rotated(randf() * TAU))
	await _measure("bandits", 700, func(i): heli.position = pos + Vector2(300, 0).rotated(i * 0.004))
	main.bandits.camps["perf_camp"]["cleared"] = true
	await _clear_enemies()


## A convoy to a far site: the SEND (road path through unloaded land) and the drive, the heli at home.
func _convoy() -> void:
	var cv: Node2D = main.convoys
	var ch: TileMapLayer = main.chunks
	await _jump(main.BASE_POS + Vector2(0, -60))
	Game.buildings.append({"kind": "motor_pool", "cell": Vector2i(-99, -99), "built": true, "progress": 0.0})
	cv.trucks = 1
	Game.rescued = maxi(Game.rescued, 3) # the founding crew is delivered, people at home
	Game.people[0]["skill"] = "driver"
	Game.people[0]["injured"] = false
	var far: Array = ch.sites_near(main.BASE_POS, cv.RANGE).filter(func(s): return s.pos.distance_to(main.BASE_POS) > 6000.0)
	var sent := ""
	var t_send := 0.0
	for s in far.slice(0, 6):
		ch._ensure(Vector2i((s.pos / (ch.CHUNK * ch.TILE)).floor())) # the heli has seen it
		var t0 := Time.get_ticks_usec()
		var why: String = cv.send(s.uid, Game.people[0]["id"], 0)
		t_send = (Time.get_ticks_usec() - t0) / 1000.0
		if why == "":
			sent = "%s %d m" % [s.kind, s.pos.distance_to(main.BASE_POS) / 10.0]
			break
	rows.append("  convoy SEND to %s: %.1f ms" % [sent if sent != "" else "(no far road)", t_send])
	await _measure("convoy", 400, func(_i): pass)
	for c in cv.list.duplicate():
		cv._home(c)


## A long flight in widening squares with the spawner on: chunk loading, hordes, memory over the run.
func _long() -> void:
	main.spawner.set_process(true)
	await _jump(main.BASE_POS)
	var mem0: float = perf.stats()["mem_mb"]
	var ch0: int = main.chunks.loaded.size()
	var leg := 600.0
	var dir := Vector2.RIGHT
	var left := leg
	var step := FLY_SPEED * LONG_SPEED * SIM_DT
	var s := await _measure("long flight", LONG_FRAMES, func(_i):
		heli.position += dir * step
		left -= step
		if left <= 0.0:
			dir = dir.rotated(PI / 2)
			leg += 300.0
			left = leg)
	var chunks: int = main.chunks.loaded.size() - ch0
	rows.append("  long flight: +%d chunks, memory %.0f -> %.0f MB (%.2f MB per chunk)" % [chunks, mem0, s["mem_mb"], (s["mem_mb"] - mem0) / maxi(1, chunks)])
	assert(s["chunk_max"] < HITCH_MAX, "long flight: chunk hitch %.1f ms over %.0f" % [s["chunk_max"], HITCH_MAX])
	main.spawner.set_process(false)
