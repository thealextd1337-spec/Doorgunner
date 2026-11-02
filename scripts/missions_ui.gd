extends CanvasLayer
## J: the radio mission list (docs/ROADMAP.md P13): each open mission with its target direction and distance, time left and
## reward. Does not pause. A small "[J] MISSIONS n" tag shows at the top while any are open.

const REFRESH := 0.25

var tag: Label
var panel: PanelContainer
var body: Label
var _t := 0.0


func _ready() -> void:
	layer = 6
	var root := UiTheme.attach(self)
	tag = Label.new() # top centre, in the HUD's TOP_ROW above its alert line
	tag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tag.offset_left = -100
	tag.offset_right = 100
	tag.offset_top = UiTheme.MARGIN - 2
	tag.offset_bottom = UiTheme.TOP_ROW
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", UiTheme.FONT)
	tag.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	UiTheme.outline(tag)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tag)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -320 # clear of the HUD status zone (300 px + margins) on both sides
	panel.offset_right = 320
	panel.offset_top = 100
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(640, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Overlay.PANEL
	sb.border_width_top = 6
	sb.border_color = Overlay.ACCENT
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	root.fit = panel
	body = Label.new()
	body.add_theme_font_size_override("font_size", UiTheme.FONT_M)
	body.add_theme_color_override("font_color", Overlay.SAND)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(body)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("missions") and Game.running and (panel.visible or not Game.world.ui_open):
		panel.visible = not panel.visible
		refresh()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	refresh()


func refresh() -> void:
	var list: Array = Game.world.missions.open
	tag.visible = not list.is_empty() and Game.running and not Game.world.ui_open
	tag.text = "[J] MISSIONS %d" % list.size()
	if not panel.visible:
		return
	var from: Vector2 = Game.heli.global_position
	var lines := ["RADIO MISSIONS   [J] close", ""]
	for m: Dictionary in list:
		var left := int(m["left"])
		lines.append("%s   %d:%02d left   %s" % [m["title"].to_upper(), left / 60, left % 60, preload("res://scripts/poi.gd").where(from, m["pos"])])
		lines.append("  %s" % m["text"])
		lines.append("  Reward: %s" % Game.world.missions.reward_text(m["reward"]))
		lines.append("")
	if list.is_empty():
		lines.append("Nothing on the radio. Command calls when something comes up.")
	body.text = "\n".join(lines)
