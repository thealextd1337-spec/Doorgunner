extends CanvasLayer
## Game-over panel: run summary and lifetime meta. [R] restart lives in main.gd; nothing here grabs input.

var body: Label


func _ready() -> void:
	layer = 30
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.75)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	var title := Label.new()
	title.text = "MISSION FAILED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = Color(1, 0.3, 0.3)
	v.add_child(title)
	body = Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body)
	Game.run_ended.connect(_show)


func _show(reason: String) -> void:
	var m: Dictionary = Game.meta
	body.text = "%s\n\nThis run: day %d, %d survivors rescued, %d kills, level %d, %d scrap\nLifetime: %d survivors rescued over %d run(s), best day %d\n\nEvery 25 survivors rescued adds a permanent seat; every 10 add fuel and ammo capacity.\n\n[R] new run" % [
		reason, Game.day, Game.rescued, Game.kills, Game.level, Game.scrap,
		m["total_rescued"], m["runs"], m["best_day"]]
	visible = true
	Game.world.ui_open = true
