extends CanvasLayer
## Victory screen of the evacuation (evac.gd): the transport is loaded. Pauses the tree until the player picks END RUN (the run
## ends with a win) or STAY BEHIND (the run goes on, the victory stays counted). Opens again after a load saved in this state.

var body: Label
var names: Label


func _ready() -> void:
	layer = 22
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	var title := Label.new()
	title.text = "EVACUATION COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = Color(0.5, 1, 0.55)
	v.add_child(title)
	body = Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)
	names = Label.new()
	names.custom_minimum_size.x = 560
	names.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	names.modulate = Color(0.8, 0.9, 0.8)
	v.add_child(names)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	for opt in [["END RUN  (fly out, the run ends with a victory)", false], ["STAY BEHIND  (the run goes on, the victory stays counted)", true]]:
		var b := Button.new()
		b.text = opt[0]
		b.custom_minimum_size = Vector2(300, 40)
		b.pressed.connect(_pick.bind(opt[1]))
		row.add_child(b)
	Game.world.evac.boarded.connect(open)
	if Game.world.evac.phase == "choice": # a run saved on this screen
		open.call_deferred()


func open() -> void:
	var e: Node = Game.world.evac
	var shown: Array = e.flown.slice(0, e.NAMES_SHOWN)
	body.text = "Everyone is aboard.\n\nSaved: %d survivors   Days: %d   Kills: %d   Level %d\nVictories (lifetime): %d" % [
		Game.saved_count(), Game.day, Game.kills, Game.level, Game.meta["victories"]]
	names.text = "On the transport: %s%s" % [", ".join(shown), " and %d more" % (e.flown.size() - shown.size()) if e.flown.size() > shown.size() else ""]
	visible = true
	get_tree().paused = true
	Game.world.ui_open = true


func _pick(stay: bool) -> void:
	visible = false
	Sfx.play("ui")
	Game.world.evac.choose(stay)
