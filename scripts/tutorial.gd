extends Node
## First-run tutorial (docs/BASE.md section 7). main.gd adds it after the title when meta "tutorial_done" is 0
## or on the TUTORIAL button. Each step is a radio line and waits on a condition; the compass marks the settlement.
## Ends with a small forced assault tonight. The ESC menu's "Skip tutorial" calls finish(false).
## The current step also sits in its own panel (base menu look) above the radio log, on top of the base menu.

const STEPS := [
	"Land on open ground and press B to found the base.",
	"Take off (SPACE).",
	"Fly to the marked settlement.",
	"Land next to it (SPACE) and hold the LZ: people board one by one. Noise draws zombies, keep the gun busy.",
	"Return to base and land on the pad.",
	"Open BUILD, place a Barracks blueprint, then assign 1 Build worker in WORKERS.",
	"Place 6 sandbags on the east side.",
	"Assign 1 Militia. Tonight's assault will test your line.",
]
const SCRAP_GRANT := 80 # barracks 40 + 6 sandbags 30, with some spare

var step := -1
var settlement: Node2D # spawned 700 px east of the base once it is founded
var rescued0 := 0 # the founding crew does not count as rescued
var panel: PanelContainer
var step_label: Label
var text_label: Label


func _ready() -> void:
	_panel()
	_next()


## Bottom-centre card between the radio log and the minimap, clear of the base menu panels.
func _panel() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11 # over the base menu: steps 5-7 are done in it
	add_child(layer)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(460, 470)
	panel.custom_minimum_size = Vector2(440, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.04, 0.92)
	sb.border_width_top = 6
	sb.border_color = Color(0.96, 0.77, 0.18)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	layer.add_child(panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	step_label = _label(13, Color(0.96, 0.77, 0.18))
	v.add_child(step_label)
	text_label = _label(16, Color(0.91, 0.86, 0.71))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(text_label)
	v.add_child(_label(11, Color(0.64, 0.6, 0.5), "ESC menu: skip tutorial"))


func _label(size: int, color: Color, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _spawn_settlement() -> void:
	rescued0 = Game.rescued
	var world: Node2D = Game.world
	var pos: Vector2 = world.BASE_POS + Vector2(700, 0)
	var found := false
	for ring in 6: # spiral outwards in 48 px steps until the spot and its 3x3 are landable
		for i in maxi(1, ring * 8):
			var off := Vector2(ring * 48.0, 0).rotated(i * TAU / maxi(1, ring * 8))
			if _clear(pos + off):
				pos += off
				found = true
				break
		if found:
			break
	if not found: # water or forest everywhere: lay a grass clearing, it is the tutorial
		var chunks: TileMapLayer = world.chunks
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				chunks.set_cell(Vector2i((pos / 16.0).floor()) + Vector2i(dx, dy), 0, Vector2i(chunks.T.GRASS, 0))
	settlement = world.spawn_poi("survivors", pos, RandomNumberGenerator.new(), 3)
	settlement.discovered = true
	world.radio_target = settlement


func _clear(at: Vector2) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if not Game.world.is_landable(at + Vector2(dx, dy) * 16.0):
				return false
	return true


func _process(_delta: float) -> void:
	if not Game.running:
		return
	if step >= 1 and step < 4 and not settlement.done:
		Game.world.radio_target = settlement # radio hints would point elsewhere
	var done := false
	match step:
		0: done = Game.base_founded
		1: done = not Game.heli.landed
		2: done = Game.heli.position.distance_to(settlement.position) < 160.0
		3: done = Game.passengers >= 1
		4: done = Game.rescued >= rescued0 + 3 or (settlement.done and Game.passengers == 0 and Game.rescued > rescued0) # a raid may cost people
		5: done = Game.buildings.any(func(b): return b["kind"] == "barracks") and Game.workers["build"] >= 1
		6: done = Game.sandbags.size() >= 6
		7: done = Game.workers["militia"] >= 1
	if done:
		_next()


func _next() -> void:
	step += 1
	if step >= STEPS.size():
		finish(true)
		return
	if step == 1:
		_spawn_settlement()
	Game.radio("TUTORIAL: " + STEPS[step])
	step_label.text = "TUTORIAL  ·  STEP %d / %d" % [step + 1, STEPS.size()]
	text_label.text = STEPS[step]
	panel.modulate = Color(2, 2, 1.4) # flash on each new step
	create_tween().tween_property(panel, "modulate", Color.WHITE, 0.6)
	if step == 4:
		Game.world.radio_target = null # the BASE arrow shows the way home
	if step == 5 and Game.scrap < SCRAP_GRANT:
		Game.scrap = SCRAP_GRANT
		Game.radio("Command: %d scrap released for construction." % SCRAP_GRANT)


## Marks the tutorial done; attack = true forces a small assault (8 zombies) tonight.
func finish(attack: bool) -> void:
	Game.meta["tutorial_done"] = 1
	Game._save_meta()
	if attack:
		Game.attack_pending = true
		Game.time = 0.79
		Game.tutorial_wave = 8
		Game.radio("TUTORIAL: done. A small horde is coming tonight. Hold the base.")
	if settlement and Game.world.radio_target == settlement:
		Game.world.radio_target = null
	Game.world.tutorial = null
	queue_free()
