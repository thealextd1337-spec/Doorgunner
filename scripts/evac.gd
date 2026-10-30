class_name Evac
extends Node
## Evacuation, the optional victory (docs/ROADMAP.md P17); main.gd keeps it as `evac`, victory_ui.gd shows the choice.
## Flow: from day FIRST_DAY the radio picks up a military frequency -> build a Radio Station (BUILD tab; an Engineer at the
## base, RADIO_ELECTRONICS electronics) -> contact -> build the Airstrip (a straight 4x24 cell strip inside the fence, so
## perimeter level 1 / radius >= MIN_RADIUS; roads, fields and yards allowed, trees are felled when the blueprint goes down;
## base only, an airstrip at an outpost was left out) -> finished: COUNTDOWN_DAYS days later the FINAL SIEGE starts at dusk
## (Assault.final: the biggest wave of the run in 4 pushes and 2 bosses, plus a bandit raid, Bandits.siege_raid) -> the
## transport lands at LAND_AT after midnight and needs BOARD_SECONDS to load, which only runs while no hostile is on the
## strip (hold it) -> the victory screen (victory_ui.gd): END RUN (the run ends with victory = true) or STAY BEHIND (the run
## goes on endlessly, the victory stays counted in meta["victories"] and on the leaderboard, no second evacuation).
## The two buildings are Game.buildings entries ("radio" 2x2, "airstrip" without a footprint + "rot"), so Build workers, saving
## and the base menu come for free; base.gd calls refusal / pay / strip_node / on_strip. Saves itself (hook "evac").
## For other packages: `Evac.siege_night(day)` (also part of Assault.night_taken), `Evac.holds_assault()`, `Evac.won()`.

signal boarded # everyone is aboard: the victory screen opens

const T := preload("res://scripts/chunk_manager.gd").T
const WON := "EVACUATION COMPLETE" # Game.run_ended reason of END RUN
const FIRST_DAY := 15
const RADIO_ELECTRONICS := 6.0 # salvage, paid when the blueprint goes down (refunded if it is removed)
const STRIP_CELLS := Vector2i(24, 4) # long x short; rot 0 = long along x, 1 = long along y
const MIN_RADIUS := 220.0 # px: smaller fences cannot hold the strip beside the pad
const COUNTDOWN_DAYS := 3
const LAND_AT := 0.04 # time of day (after midnight, the second half of the night) the transport lands
const TAXI_SECONDS := 8.0 # landing roll before the loading starts
const BOARD_SECONDS := 60.0
const HOLD_MARGIN := 48.0 # px around the strip in which a hostile stops the loading
const LANDING_PUSH := 0.4 # extra attackers when the transport touches down, share of the day's wave size
const WARN_EVERY := 15.0
const LEAVE_SECONDS := 6.0
const NAMES_SHOWN := 36 # names on the victory screen
const BLOCKED := [T.WATER, T.ROCK, T.BUILDING, T.RUIN, T.WAREHOUSE, T.HEDGE, T.PAD, T.BRIDGE] # on the strip: demolish first / impossible
const FELLED := [T.FOREST, T.TREE_EDGE] # become grass under the strip, tree props on it are cut
const EXTRA := {"radio": ["electronics", RADIO_ELECTRONICS]}

var announced := false # the military frequency was radioed (day FIRST_DAY)
var contact := false # the Radio Station is built and an Engineer runs it
var phase := "" # "" / "countdown" / "siege" / "landed" / "choice" (victory screen) / "done" (one evacuation per run)
var siege_day := 0 # the night (from dusk of this day) of the final siege
var taxi := 0.0 # s since the transport touched down
var board := 0.0 # s loaded
var victory := false
var flown: Array = [] # names of the people on the transport
var plane: Transport
var warn_cd := 0.0


func _ready() -> void:
	Game.day_changed.connect(_on_day)
	Game.base_attack_started.connect(_on_attack)
	Save.register("evac", save_state, load_state)


func _process(delta: float) -> void:
	if Game.running and Game.base_founded and Game.heli != null and not is_instance_valid(Game.world.tutorial):
		step(delta)


static func _inst() -> Evac:
	var w: Node2D = Game.world
	return w.get("evac") if is_instance_valid(w) else null


## Is `day` the night of the final siege? Assault.night_taken says yes, so no bandit raid of its own is planned.
static func siege_night(day: int) -> bool:
	var e := _inst()
	return e != null and e.phase in ["countdown", "siege"] and e.siege_day == day


## The assault must not end yet: the transport is still to land / load.
static func holds_assault() -> bool:
	var e := _inst()
	return e != null and e.phase in ["siege", "landed"]


## The victory of this run is counted (END RUN and STAY BEHIND both).
static func won() -> bool:
	var e := _inst()
	return e != null and e.victory


## One frame of evacuation time (tests call it by hand).
func step(delta: float) -> void:
	if not contact and Game.built("radio") > 0 and engineer() != null:
		contact = true
		Game.radio("Military: we read you, base. We can fly everyone out. Build an airstrip (%dx%d cells inside your fence, perimeter level 1+)." % [STRIP_CELLS.x, STRIP_CELLS.y])
		Game.radio("Military: when it is finished the transport comes in %d days. Expect everything they have to come for it." % COUNTDOWN_DAYS)
	match phase:
		"":
			if contact and Game.built("airstrip") > 0:
				phase = "countdown"
				siege_day = Game.day + COUNTDOWN_DAYS
				Game.radio("Military: strip confirmed. The transport lands after midnight of the night of day %d." % siege_day)
		"siege":
			if Game.day > siege_day + 1 or (Game.day == siege_day + 1 and Game.time >= LAND_AT):
				_land()
		"landed":
			_board(delta)
		"choice":
			_ensure_plane()


func _on_day(day: int) -> void:
	if Game.base_founded and day >= FIRST_DAY and not announced:
		announced = true
		Game.radio("Command: we are picking up a military frequency. An evacuation may be possible: build a Radio Station (%d scrap, %d electronics, an Engineer to run it)." % [
			Game.BUILDINGS["radio"][1], RADIO_ELECTRONICS])
	if phase != "countdown":
		return
	if day == siege_day:
		Game.attack_pending = true
		Game.radio("Military: the transport is on its way. The final siege comes tonight, hold the base until it has landed and loaded.")
	elif day < siege_day:
		Game.radio("Military: the transport comes in %d day(s). Stock ammo, patch the line." % (siege_day - day))


func _on_attack(day: int) -> void:
	if phase == "countdown" and day == siege_day:
		phase = "siege"
		var b: Node = Game.world.get("bandits")
		if b != null:
			b.siege_raid()


func _land() -> void:
	phase = "landed"
	taxi = 0.0
	board = 0.0
	Sfx.play("alarm")
	Game.radio("Pilot: transport on final. Keep the strip clear until everyone is aboard!")
	Game.world.assault.add_push(int(Assault.wave_size(siege_day) * LANDING_PUSH)) # the bandits' siege raid came at siege start (_on_attack)
	_ensure_plane()


func _board(delta: float) -> void:
	taxi += delta
	_ensure_plane()
	if taxi < TAXI_SECONDS:
		return
	var n := hostiles_on_strip()
	if n > 0:
		warn_cd -= delta
		if warn_cd <= 0.0:
			warn_cd = WARN_EVERY
			Game.radio("Pilot: %d hostile(s) on the strip, I can't load under fire!" % n)
		return
	board += delta
	if board >= board_seconds():
		_boarded()


## Loading time: BOARD_SECONDS, faster with a Chinook as the active heli (heli_types.gd "evac").
func board_seconds() -> float:
	return BOARD_SECONDS / Game.world.wrecks.htype()["evac"]


## Zombies and bandits on or within HOLD_MARGIN px of the strip.
func hostiles_on_strip() -> int:
	var b := strip()
	if b.is_empty():
		return 0
	var r := strip_rect(b).grow(HOLD_MARGIN)
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.is_queued_for_deletion() and r.has_point(e.global_position)).size()


func _boarded() -> void:
	if victory: # counted once per run
		return
	phase = "choice"
	flown = Game.people.filter(func(p): return not p["aboard"] and p.get("post", "") == "").map(func(p): return p["name"])
	victory = true
	Game.meta["victories"] += 1
	Game._save_meta()
	Online.mark_victory() # the server hears of it now, the run may go on
	Game.radio("Pilot: everyone is aboard. Your call, gunner.")
	boarded.emit()
	Save.autosave() # a save from before boarding must not replay it (a second victory)


## Victory screen: STAY BEHIND (true) keeps the run going, END RUN (false) finishes it as a win.
func choose(stay: bool) -> void:
	get_tree().paused = false
	Game.world.ui_open = false
	phase = "done"
	if stay:
		if plane != null:
			plane.leaving = 0.0
		Game.radio("Base: the transport lifts off without us. We are staying, the survivors stay with the base.")
	else:
		Game.end_run(WON, true)


# --- building rules (base.gd)

## Who runs the radio: a healthy Engineer at the base, null if none.
func engineer() -> Variant:
	for p in Game.people:
		if p["skill"] == "engineer" and not p["aboard"] and not p["injured"] and p.get("post", "") == "":
			return p
	return null


func tool_visible(kind: String) -> bool:
	if kind not in ["radio", "airstrip"]:
		return true
	return phase == "" and (announced if kind == "radio" else contact)


## Why `kind` cannot be placed right now regardless of the spot, "" if it can.
func tool_note(kind: String) -> String:
	if not kind in ["radio", "airstrip"]:
		return ""
	if phase != "" or Game.buildings.any(func(b): return b["kind"] == kind):
		return "one is enough" if phase == "" else "the evacuation is already under way or over"
	if kind == "radio":
		if not announced:
			return "no military frequency before day %d" % FIRST_DAY
		if Game.salvage["electronics"] < RADIO_ELECTRONICS:
			return "needs %d electronics, you have %d" % [RADIO_ELECTRONICS, Game.salvage["electronics"]]
		if engineer() == null:
			return "needs an Engineer at the base to run it"
		return ""
	if not contact:
		return "no contact yet: build the Radio Station"
	if Game.base_radius < MIN_RADIUS:
		return "needs perimeter level 1 (radius %d m)" % (MIN_RADIUS / 10.0)
	return ""


## Why `kind` cannot go at `cell` (top-left; `rot` for the airstrip), "" if it can. The ghost shows it.
func refusal(kind: String, cell: Vector2i, rot := 0) -> String:
	var why := tool_note(kind)
	return strip_problem(cell, rot) if why == "" and kind == "airstrip" else why


## Electronics for the radio: paid at placement (sign 1), refunded when the blueprint is removed (-1).
func pay(kind: String, sign: int) -> void:
	if EXTRA.has(kind):
		Game.salvage[EXTRA[kind][0]] -= sign * EXTRA[kind][1]


static func strip_size(rot: int) -> Vector2i:
	return Vector2i(STRIP_CELLS.y, STRIP_CELLS.x) if rot == 1 else STRIP_CELLS


## The airstrip's Game.buildings entry (blueprint or built), {} if none.
func strip() -> Dictionary:
	for b in Game.buildings:
		if b["kind"] == "airstrip":
			return b
	return {}


## World rectangle of the airstrip entry `b`.
static func strip_rect(b: Dictionary) -> Rect2:
	return Rect2(Vector2(b["cell"]) * 16.0, Vector2(strip_size(b["rot"])) * 16.0)


## Is `cell` under the airstrip (blueprint or built)? Nothing else may be placed there.
func on_strip(cell: Vector2i) -> bool:
	var b := strip()
	return not b.is_empty() and Rect2i(b["cell"], strip_size(b["rot"])).has_point(cell)


## What stops a strip with top-left `cell`: the first problem, "" if it fits. Cells need to lie inside the fence, off the pad
## and hangar, free of buildings and sandbags, and on ground that is not water, rock, a house or a hedge.
func strip_problem(cell: Vector2i, rot: int) -> String:
	var base: Node2D = Game.world.base
	var size := strip_size(rot)
	for x in size.x:
		for y in size.y:
			var c := cell + Vector2i(x, y)
			var pos: Vector2 = base.cell_pos(c)
			var d := pos.distance_to(base.global_position)
			if d > Game.base_radius:
				return "the strip must lie inside the fence"
			if d < base.PAD_CLEAR or base.HANGAR.has_point(pos - base.global_position):
				return "the strip must not cross the pad or the hangar"
			if Game.sandbags.has(c) or not base.building_at(c).is_empty():
				return "a building or sandbag is in the way"
			if Game.world.chunks.get_cell_atlas_coords(c).x in BLOCKED:
				return "water, rock or a house is in the way (demolish houses first)"
	return ""


## First top-left cell where a strip with `rot` fits (tests and hints), Vector2i(-99999, 0) if none.
func find_spot(rot: int) -> Vector2i:
	var size := strip_size(rot)
	var c0 := Vector2i((Game.world.base.global_position / 16.0).floor())
	var r := int(Game.base_radius / 16.0) + 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cell := c0 + Vector2i(dx, dy) - size / 2
			if strip_problem(cell, rot) == "":
				return cell
	return Vector2i(-99999, 0)


## The blueprint went down at `cell`: trees on the strip are felled (forest tiles become grass, tree props are cut).
func clear_strip(b: Dictionary) -> void:
	var chunks: TileMapLayer = Game.world.chunks
	var rect := strip_rect(b)
	for x in int(rect.size.x / 16.0):
		for y in int(rect.size.y / 16.0):
			var c: Vector2i = b["cell"] + Vector2i(x, y)
			if chunks.get_cell_atlas_coords(c).x in FELLED:
				chunks.edit(c, T.GRASS)
	for n in Game.world.get_children():
		if n.get_class() == "Node2D" and n.get_script() == null and n.get_child_count() > 0 and n.get_child(0) is Sprite2D \
				and not n.is_queued_for_deletion() and rect.has_point(n.position):
			chunks.cut_prop(n)
	Game.world.nav_dirty()


## base._site_node: the airstrip's node (placed at the strip centre, turned for rot 1) and the radio mast.
static func strip_node(node: Node2D, b: Dictionary, base_pos: Vector2) -> void:
	node.position = strip_rect(b).get_center() - base_pos
	node.rotation = PI / 2.0 if b["rot"] == 1 else 0.0
	node.add_child(StripArt.new())


static func add_mast(node: Node2D) -> void:
	for r in [Rect2(-1, -15, 2, 26), Rect2(-6, -11, 12, 2), Rect2(-4, -6, 8, 2)]:
		var c := ColorRect.new()
		c.position = r.position
		c.size = r.size
		c.color = Color(0.88, 0.88, 0.92)
		node.add_child(c)


# --- HUD

## Lines for the HUD info column ("" before contact).
func status() -> String:
	match phase:
		"":
			if not contact:
				return ""
			return "\nEVAC: building the airstrip" if not strip().is_empty() else "\nEVAC: contact made - build the Airstrip (BUILD tab)"
		"countdown":
			return "\nEVAC: FINAL SIEGE TONIGHT" if Game.day == siege_day else "\nEVAC: transport in %d day(s)" % (siege_day - Game.day)
		"siege":
			return "\nEVAC: hold the base, the transport lands after midnight"
		"landed":
			if taxi < TAXI_SECONDS:
				return "\nEVAC: transport landing"
			var n := hostiles_on_strip()
			return "\nEVAC: CLEAR THE STRIP (%d hostile)" % n if n > 0 else "\nEVAC: loading %d/%d s" % [board, board_seconds()]
	return ""


# --- the transport

func _ensure_plane() -> void:
	var b := strip()
	if b.is_empty():
		return
	if plane == null or not is_instance_valid(plane):
		plane = Transport.new()
		plane.z_index = 3
		Game.world.add_child(plane)
		plane.setup(strip_rect(b).get_center(), Vector2.RIGHT if b["rot"] == 0 else Vector2.DOWN)
	plane.place(taxi, board / board_seconds() if taxi >= TAXI_SECONDS else 0.0)


## The strip as drawn: dark surface, edge lines, centre dashes and threshold bars. Long axis along x, the node turns.
class StripArt extends Node2D:
	func _draw() -> void:
		var l := 24 * 16.0
		var w := 4 * 16.0
		draw_rect(Rect2(-l / 2, -w / 2, l, w), Color(0.19, 0.2, 0.22))
		for y in [-w / 2, w / 2 - 2]:
			draw_rect(Rect2(-l / 2, y, l, 2), Color(0.85, 0.85, 0.8))
		for i in range(-10, 11):
			draw_rect(Rect2(i * 16.0 - 5, -1, 10, 2), Color(0.95, 0.88, 0.45))
		for side in [-1.0, 1.0]:
			for k in 4:
				draw_rect(Rect2(side * (l / 2 - 14) - 5, -w / 2 + 7 + k * 12, 10, 6), Color(0.92, 0.92, 0.9))


## Transport plane (drawn, no sprite): lands from the strip's start along `dir`, loads (bar), leaves when the player stays.
class Transport extends Node2D:
	const LAND_FROM := 760.0 # px before the strip centre it comes in from
	var dir := Vector2.RIGHT
	var rest := Vector2.ZERO
	var loaded := 0.0 # 0..1
	var leaving := -1.0 # s since take-off, -1 = not yet

	func setup(centre: Vector2, d: Vector2) -> void:
		rest = centre
		dir = d

	## `sec` since touch-down was announced (the roll takes TAXI_SECONDS), `share` the boarding share.
	func place(sec: float, share: float) -> void:
		loaded = share
		var k := clampf(sec / Evac.TAXI_SECONDS, 0.0, 1.0)
		position = (rest - dir * LAND_FROM).lerp(rest, 1.0 - (1.0 - k) * (1.0 - k))
		scale = Vector2.ONE * (1.0 + 0.35 * (1.0 - clampf(k / 0.6, 0.0, 1.0)))
		queue_redraw()

	func _process(delta: float) -> void:
		if leaving < 0.0:
			return
		leaving += delta
		position += dir * (90.0 + 320.0 * leaving) * delta
		scale = Vector2.ONE * (1.0 + 0.2 * leaving)
		modulate.a = 1.0 - leaving / Evac.LEAVE_SECONDS
		if leaving >= Evac.LEAVE_SECONDS:
			queue_free()

	func _draw() -> void:
		var olive := Color(0.4, 0.44, 0.3)
		var dark := Color(0.24, 0.27, 0.2)
		draw_set_transform(Vector2.ZERO, dir.angle())
		draw_colored_polygon(PackedVector2Array([Vector2(-66, -13), Vector2(44, -13), Vector2(70, -5), Vector2(70, 5), Vector2(44, 13), Vector2(-66, 13)]), olive) # fuselage
		draw_colored_polygon(PackedVector2Array([Vector2(-8, -12), Vector2(22, -12), Vector2(12, -74), Vector2(-4, -74)]), dark) # wings
		draw_colored_polygon(PackedVector2Array([Vector2(-8, 12), Vector2(22, 12), Vector2(12, 74), Vector2(-4, 74)]), dark)
		draw_colored_polygon(PackedVector2Array([Vector2(-66, -12), Vector2(-48, -12), Vector2(-54, -32), Vector2(-66, -32)]), dark) # tail plane
		draw_colored_polygon(PackedVector2Array([Vector2(-66, 12), Vector2(-48, 12), Vector2(-54, 32), Vector2(-66, 32)]), dark)
		draw_rect(Rect2(-70, -8, 6, 16), Color(0.55, 0.55, 0.5)) # open ramp
		for y in [-52.0, -30.0, 30.0, 52.0]:
			draw_circle(Vector2(26, y), 5.0, dark)
			draw_arc(Vector2(26, y), 11.0, 0.0, TAU, 14, Color(0.9, 0.9, 0.9, 0.35), 1.5) # propeller disc
		draw_rect(Rect2(36, -6, 14, 12), Color(0.45, 0.65, 0.8)) # cockpit
		draw_set_transform(Vector2.ZERO, 0.0)
		if loaded > 0.0 and leaving < 0.0:
			draw_rect(Rect2(-40, -100, 80, 8), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(-39, -99, 78 * loaded, 6), Color(0.45, 0.85, 0.4))


# --- save

func save_state() -> Dictionary:
	return {"announced": announced, "contact": contact, "phase": phase, "siege_day": siege_day, "taxi": taxi, "board": board,
		"victory": victory, "flown": flown}


func load_state(d: Dictionary) -> void:
	announced = d["announced"]
	contact = d["contact"]
	phase = d["phase"]
	siege_day = d["siege_day"]
	taxi = d["taxi"]
	board = d["board"]
	victory = d["victory"]
	flown = d["flown"]
