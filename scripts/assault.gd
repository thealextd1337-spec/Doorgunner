class_name Assault
extends Node
## Base assaults with character (docs/ROADMAP.md P10); main.gd keeps it as `assault`. Takes over the wave control from
## spawner.gd: Game.base_attack_started starts a wave, it ends when everything is spawned and no attacker is left.
## - Direction: the evening before, a Watchtower radios the main direction ("movement north-east") and the HUD shows an
##   arrow at the fence (draw_arrow). 70 % of the attackers come from that direction, with or without a tower.
## - Themes from the 2nd assault on (THEMES): runner storm, brute ram (brutes walk straight at the base and smash what
##   is in the way, `ram`), spitter siege, screamer chain (more zombies every ESCALATE_EVERY s while a screamer lives),
##   mixed. Name on the radio and in the HUD.
## - Blood moon every BLOOD_EVERY-th night from founding: red sky, a boss for sure, the night does not end until the last
##   attacker is dead (holds_dawn, at most HOLD_MAX s), 2x XP for attackers, morale +BLOOD_MORALE once it is held.
## - Surges: a big wave comes in 2-3 pushes with a pause in between (reload, patch the line).
## For other packages: `Assault.night_taken(day)` says whether an assault (or blood moon) falls on that day; bandit raids
## (P11) must not use such a day. `Assault.blood_moon(day)` is the same for blood moons only.
## The evacuation's final siege (evac.gd, `final`): the night Evac.siege_night(day) the wave is FINAL_SIZE times bigger, in
## FINAL_PUSHES pushes with FINAL_BOSSES bosses, and it does not end while Evac.holds_assault() (transport not loaded yet);
## `add_push(n)` adds attackers on top (the landing).
## Saves itself (hook "assault"); Game saves attack_pending / attack_active, so a run can be saved in the middle of an assault.

const SPAWN_RADIUS := 720.0 # px from the base
const SPAWN_INTERVAL := 0.5 # s between two attackers of a push
const FROM_DIRECTION := 0.7 # share of the attackers that come from the announced direction
const DIRECTION_SPREAD := 0.4 # rad either side of it
const BASE_SIZE := 20 # attackers = BASE_SIZE + SIZE_PER_DAY * day (+ LATE_PER_DAY a day after LATE_FROM)
const SIZE_PER_DAY := 6
const LATE_FROM := 25 # from this day the waves grow faster: days 31-40 of the long run were the safest (few losses, scrap past 4000)
const LATE_PER_DAY := 4 # extra attackers per day after LATE_FROM (balance 1.0.0-beta; a flat 8 per day broke weak runs by day 12, 6 the weakest by day 39)
const FIRST_THEME := 2 # themes from this assault on
const EVENING := 0.6 # time of day the evening before the assault is announced
const FIRST_DELAY := 2 # main.found_base: the first assault comes on founding day + this
const BLOOD_EVERY := 9 # every 9th night from founding
const BLOOD_SIZE := 1.25
const BLOOD_MORALE := 10.0
const BLOOD_XP := 2
const FINAL_SIZE := 2.0 # the final siege: wave size factor, the biggest of the run
const FINAL_PUSHES := 4
const FINAL_BOSSES := 2
const HOLD_AT := 0.05 # time of day the blood moon stops the clock at (dark, before dawn at 0.2)
const HOLD_MAX := 480.0 # s the night can be held; the assault still lasts until the last attacker is dead
const PHASED_FROM := 30 # waves this big come in 2-3 pushes (a blood moon always in 3)
const DAWN := 0.25 # time of day the stragglers of last night's assault give up (those stuck behind rivers or rock kept it going for days)
const PAUSE := 20.0 # s between two pushes (shorter once the push is dead)
const QUICK_PAUSE := 6.0
const ESCALATE_EVERY := 6.0
const ESCALATE_MAX := 60 # extra zombies a screamer chain may add
const RAM_SPEED := 1.6 # brute ram: walking speed factor
const Chunks := preload("res://scripts/chunk_manager.gd")
const RAM_LOOK := 48.0 # px: a ram that ran into something it cannot smash walks the normal path until this much is clear
const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
const NIGHT_SKY := Color(0.2, 0.22, 0.45)
const BLOOD_SKY := Color(0.62, 0.1, 0.1)
# mix: share of the wave per kind (at least 2, only once the kind exists at that day), the rest is SpawnTable.pick
const THEMES := {
	"runner_storm": {"name": "Runner storm", "min_day": 2, "mix": {"runner": 0.65}},
	"ram": {"name": "Brute ram", "min_day": 3, "mix": {"brute": 0.1, "brute_armored": 0.05}, "ram": true},
	"scream": {"name": "Screamer chain", "min_day": 3, "mix": {"screamer": 0.08}, "chain": true},
	"siege": {"name": "Spitter siege", "min_day": 4, "mix": {"spitter": 0.3, "bloater": 0.05}},
	"mixed": {"name": "Mixed assault", "min_day": 1, "mix": {"runner": 0.15, "brute": 0.08, "screamer": 0.05, "spitter": 0.08,
		"crawler": 0.08, "bloater": 0.04, "brute_armored": 0.04}},
}

var plan := {} # the next assault: {day, theme, dir (0 = north, clockwise), blood, known, tower}
var theme := "" # of the running assault
var blood := false
var final := false # the running assault is the evacuation's final siege
var dir := -1 # compass index the running assault mostly comes from, -1 = anywhere
var queue: Array = [] # kinds of the current push, spawned one by one
var surges: Array = [] # the pushes still to come
var pause := 0.0 # s until the next push (> 0 while one is due)
var spawn_cd := 0.0
var esc_cd := 0.0
var extra := 0 # zombies a screamer chain added so far
var held := 0.0 # s the blood moon held the night
var last_theme := ""
var start_day := 0 # day the running assault began; its stragglers scatter at DAWN the morning after


func _ready() -> void:
	Game.base_attack_started.connect(_on_attack)
	Game.day_changed.connect(_on_day)
	Save.register("assault", save_state, load_state)


## True if an assault is scheduled for `day` (or is running / due tonight, e.g. the tutorial's).
static func night_taken(day: int) -> bool:
	if day == Game.day and (Game.attack_pending or Game.attack_active):
		return true
	return Evac.siege_night(day) or Game.base_founded and day >= Game.first_assault_day and (day - Game.first_assault_day) % Game.ATTACK_EVERY_DAYS == 0


## Night number n of the base is day - founding day + 1; the founding day is first_assault_day - FIRST_DELAY.
static func blood_moon(day: int) -> bool:
	return Game.base_founded and day >= Game.first_assault_day and (day - Game.first_assault_day) % Game.ATTACK_EVERY_DAYS == 0 \
		and (day - Game.first_assault_day + FIRST_DELAY + 1) % BLOOD_EVERY == 0


static func wave_size(day: int) -> int:
	return BASE_SIZE + SIZE_PER_DAY * day + LATE_PER_DAY * maxi(0, day - LATE_FROM)


static func _inst() -> Assault:
	var w: Node2D = Game.world
	return w.get("assault") if is_instance_valid(w) else null


## A blood moon assault is running.
static func blood_active() -> bool:
	var a := _inst()
	return a != null and a.blood and Game.attack_active


## Game._process: the clock stands still at HOLD_AT while the blood moon is not over.
static func holds_dawn() -> bool:
	var a := _inst()
	return a != null and blood_active() and a.held < HOLD_MAX and Game.time >= HOLD_AT and Game.time < HOLD_AT + 0.02


## main._process: colour the night turns the sky.
static func sky() -> Color:
	return BLOOD_SKY if blood_active() or (Game.attack_pending and blood_moon(Game.day)) else NIGHT_SKY


## enemy._die: XP factor for an attacker.
static func xp_mult(e: Node2D) -> int:
	return BLOOD_XP if e.target_base and blood_active() else 1


## enemy._process: a ram brute walks straight at the base (chewing through sandbags and houses on the way) instead of
## around them. True while it does.
static func ram(e: Node2D, delta: float) -> bool:
	if not e.state.get("ram", false) or not e.target_base:
		return false
	var to: Vector2 = Game.world.base.global_position - e.global_position
	if to.length() <= e.radius + 50.0:
		return false
	if e.state.get("detour", false):
		if _wall_ahead(e.position, to.normalized()):
			return false # walking around rock, water or a hedge on the normal path until the way ahead is clear
		e.state.erase("detour")
	var before: Vector2 = e.position
	e._face(to)
	e._step(to, delta, RAM_SPEED)
	if e.position == before and _wall_ahead(e.position, to.normalized()):
		e.state["detour"] = true # nothing to smash: a ram stuck there kept the assault going for ever (P18 long run)
	return true


## Terrain within RAM_LOOK px along `dir` that no ram can smash (rock, water, hedge, warehouse; not sandbags or houses).
static func _wall_ahead(pos: Vector2, dir: Vector2) -> bool:
	for d in range(8, int(RAM_LOOK) + 1, 8):
		var p := pos + dir * d
		var cell := Vector2i((p / 16.0).floor())
		if not Game.world.is_walkable(p) and not Game.sandbags.get(cell, {}).get("built", false) and Game.world.chunks.get_cell_atlas_coords(cell).x != Chunks.T.BUILDING and Game.world.base.building_at(cell).is_empty():
			return true
	return false


## hud: the alert text while an assault runs ("" otherwise): name of the theme, blood moon, attackers left.
static func alert_text() -> String:
	if not Game.attack_active:
		return ""
	var text := "BASE UNDER ATTACK"
	var a := _inst()
	if a == null:
		return text
	var tags := []
	if a.final:
		tags.append("FINAL SIEGE")
	if a.blood:
		tags.append("BLOOD MOON")
	if a.theme != "":
		tags.append(THEMES[a.theme]["name"].to_upper())
	if a.final or a.blood or a.theme != "":
		tags.append("%d LEFT" % (a.attackers() + a.queued()))
		text += "\n" + " - ".join(tags)
	return text


## hud compass layer: an arrow at the fence pointing in from the announced direction (only if a Watchtower announced it).
static func draw_arrow(c: Control) -> void:
	var a := _inst()
	if a == null or not a.plan.get("tower", false) or not Game.base_founded:
		return
	var t: Transform2D = Game.world.base.get_global_transform_with_canvas()
	var v := Vector2.from_angle(_angle(a.plan["dir"]))
	var near: float = Game.base_radius * t.get_scale().x + 6.0
	var tip: Vector2 = t.origin + v * near
	var tail := tip + v * 34.0
	if not Rect2(Vector2(-60, -60), c.size + Vector2(120, 120)).has_point(tip):
		return
	var col := Color(1.0, 0.25, 0.2, 0.75 + 0.25 * sin(Time.get_ticks_msec() / 250.0)) if a.plan["blood"] else Color(1.0, 0.55, 0.2, 0.75 + 0.25 * sin(Time.get_ticks_msec() / 250.0))
	c.draw_line(tail, tip - v * 6.0, col, 5.0)
	c.draw_colored_polygon(PackedVector2Array([tip, tip + v * 16.0 + v.orthogonal() * 11.0, tip + v * 16.0 - v.orthogonal() * 11.0]), col)
	c.draw_string(ThemeDB.fallback_font, tail + v * 6.0 - Vector2(60, -4), "BLOOD MOON" if a.plan["blood"] else "ASSAULT", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, col)


static func _angle(idx: int) -> float:
	return -PI / 2.0 + idx * PI / 4.0


func attackers() -> int:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return "target_base" in e and e.target_base and not e.is_queued_for_deletion()).size()


## Attackers still to spawn.
func queued() -> int:
	var n := queue.size()
	for s in surges:
		n += s.size()
	return n


## `n` more attackers right now (evac.gd: the landing), on top of whatever is queued.
func add_push(n: int) -> void:
	queue.append_array(_compose(Game.day, n))


## Forgets the rest of the wave (tests).
func clear_wave() -> void:
	queue = []
	surges = []
	pause = 0.0


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	_evening()
	if not Game.attack_active:
		return
	if holds_dawn():
		if held == 0.0:
			Game.radio("Command: the blood moon will not set until the last of them is dead.")
		held += delta
	if not queue.is_empty():
		spawn_cd -= delta
		if spawn_cd <= 0.0:
			spawn_cd = SPAWN_INTERVAL
			_spawn(queue.pop_back())
		if queue.is_empty() and not surges.is_empty():
			pause = PAUSE
			Game.radio("Command: they are pulling back to regroup. Reload and patch the line.")
	elif not surges.is_empty():
		pause = minf(pause, QUICK_PAUSE) if attackers() == 0 else pause
		pause -= delta
		if pause <= 0.0:
			queue = surges.pop_front()
			Game.radio("Command: next push, %s!" % ("the last one" if surges.is_empty() else "more of them"))
	elif attackers() == 0 and not Evac.holds_assault():
		_end()
	elif Game.day > start_day and Game.time >= DAWN and not final:
		_scatter()
	if THEMES.get(theme, {}).get("chain", false):
		_escalate(delta)


## Screamer chain: while a screamer lives, more zombies keep coming.
func _escalate(delta: float) -> void:
	esc_cd -= delta
	if esc_cd > 0.0:
		return
	esc_cd = ESCALATE_EVERY
	var screamers := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get("kind") == "screamer" and e.target_base and not e.is_queued_for_deletion())
	if screamers.is_empty() or extra >= ESCALATE_MAX:
		return
	var n := 2 + Game.day / 4
	extra += n
	for i in n:
		_spawn(SpawnTable.pick(Game.danger_at(Vector2.ZERO), {"day": Game.day}))
	Game.radio("Command: the screamers keep calling them in!")


func _on_day(day: int) -> void:
	if plan.get("day", day) < day and not Game.attack_active:
		plan = {} # an assault that never came (tutorial, skipped)
	if night_taken(day + 1) and plan.get("day", 0) != day + 1:
		plan = _roll(day + 1)


## The next assault: theme (from the 2nd on, never the same twice running), compass direction, blood moon.
func _roll(day: int) -> Dictionary:
	var th := ""
	if (day - Game.first_assault_day) / Game.ATTACK_EVERY_DAYS + 1 >= FIRST_THEME:
		var options := THEMES.keys().filter(func(k): return THEMES[k]["min_day"] <= day and k != last_theme)
		if not options.is_empty():
			th = options.pick_random()
	return {"day": day, "theme": th, "dir": randi() % 8, "blood": blood_moon(day), "known": false, "tower": false}


## The evening before (or later): the Watchtower reports the direction, the blood moon is announced.
func _evening() -> void:
	if plan.is_empty() or plan["known"] or not (Game.day > plan["day"] - 1 or (Game.day == plan["day"] - 1 and Game.time >= EVENING)):
		return
	plan["known"] = true
	plan["tower"] = Game.built("watchtower") > 0
	var when := "tomorrow night" if Game.day < plan["day"] else "tonight"
	if plan["blood"]:
		Game.radio("Command: the moon is rising red. Expect a blood moon assault %s." % when)
	if plan["tower"]:
		Game.radio("Watchtower: movement %s." % COMPASS[plan["dir"]])


func _on_attack(day: int) -> void:
	Sfx.play("alarm")
	var tutorial := Game.tutorial_wave > 0
	var total: int = Game.tutorial_wave if tutorial else wave_size(day)
	Game.tutorial_wave = 0
	if tutorial:
		plan = {}
	elif plan.get("day", -1) != day:
		plan = _roll(day)
	theme = plan.get("theme", "")
	blood = plan.get("blood", false)
	final = not tutorial and Evac.siege_night(day)
	dir = plan.get("dir", -1)
	last_theme = theme
	if blood:
		total = int(total * BLOOD_SIZE)
	if final:
		total = int(total * FINAL_SIZE)
	held = 0.0
	extra = 0
	esc_cd = ESCALATE_EVERY
	start_day = day
	var kinds := _compose(day, total)
	var pushes := 1
	if total >= PHASED_FROM and not tutorial:
		pushes = 3 if blood else randi_range(2, 3)
	if final:
		pushes = FINAL_PUSHES
	var per := ceili(float(kinds.size()) / pushes)
	surges = []
	for i in pushes:
		surges.append(kinds.slice(i * per, (i + 1) * per))
	queue = surges.pop_front()
	pause = 0.0
	spawn_cd = 0.0
	if final:
		Game.radio("Command: FINAL SIEGE! Everything they have is coming for the airstrip. Hold the line until the transport is out.")
		for i in FINAL_BOSSES:
			_spawn("boss", 800.0)
	elif blood:
		Game.radio("Command: BLOOD MOON! The whole horde is coming. It ends when the last of them is dead.")
	elif theme != "":
		Game.radio("Command: %s incoming!" % THEMES[theme]["name"].to_lower())
	if blood or (not tutorial and (day - Game.first_assault_day) % (Game.ATTACK_EVERY_DAYS * 2) == Game.ATTACK_EVERY_DAYS): # blood moon, else every second assault
		_spawn("boss", 800.0)


## `total` kinds: the theme's share first, the rest by the spawn table; shuffled.
func _compose(day: int, total: int) -> Array:
	var out := []
	var mix: Dictionary = THEMES.get(theme, {}).get("mix", {})
	for kind in mix:
		if SpawnTable.ROWS.get(kind, {}).get("min_day", 1) > day:
			continue # not out there yet (screamers, armored brutes)
		for i in mini(total, maxi(2, int(total * mix[kind]))):
			out.append(kind)
	var danger := Game.danger_at(Vector2.ZERO)
	var ctx := SpawnTable.context(Game.world.base.global_position)
	ctx["day"] = day
	while out.size() < total:
		out.append(SpawnTable.pick(danger, ctx))
	out.shuffle()
	return out


func _spawn(kind: String, radius := SPAWN_RADIUS) -> void:
	var angle := randf() * TAU
	if dir >= 0 and randf() < FROM_DIRECTION:
		angle = _angle(dir) + randf_range(-DIRECTION_SPREAD, DIRECTION_SPREAD)
	var e: Node2D = Game.world.spawn_enemy(kind, Game.world.base.global_position + Vector2(radius, 0).rotated(angle), true)
	if THEMES.get(theme, {}).get("ram", false) and kind.begins_with("brute"):
		e.state["ram"] = true


## Morning after: the attackers still out there stop going for the base and wander off; the assault counts as held.
func _scatter() -> void:
	var left := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("target_base") and not e.is_queued_for_deletion():
			e.target_base = false
			left += 1
	Game.radio("Command: daylight. The last %d of them are scattering." % left)
	_end()


func _end() -> void:
	Game.attack_active = false
	Game.meta["assaults_held"] += 1
	if blood:
		Game.radio("The blood moon sets. Base secured. You held the line, gunner.")
		Game.world.morale.add(BLOOD_MORALE, "blood moon held")
	else:
		Game.radio("Base secured. Good work, gunner.")
	blood = false
	final = false
	theme = ""
	dir = -1
	held = 0.0
	plan = {}


func save_state() -> Dictionary:
	return {"plan": plan, "theme": theme, "blood": blood, "final": final, "dir": dir, "queue": queue, "surges": surges, "pause": pause, "spawn_cd": spawn_cd,
		"esc_cd": esc_cd, "extra": extra, "held": held, "last_theme": last_theme, "start_day": start_day}


func load_state(d: Dictionary) -> void:
	plan = d["plan"]
	theme = d["theme"]
	blood = d["blood"]
	final = d.get("final", false) # runs saved before the evacuation have none
	dir = d["dir"]
	queue = d["queue"]
	surges = d["surges"]
	pause = d["pause"]
	spawn_cd = d["spawn_cd"]
	esc_cd = d["esc_cd"]
	extra = d["extra"]
	held = d["held"]
	last_theme = d["last_theme"]
	start_day = d.get("start_day", Game.day) # runs saved before 1.0.0-beta: counted from the day they are loaded
