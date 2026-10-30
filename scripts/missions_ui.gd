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
	tag = Label.new()
	tag.position = Vector2(540, 8)
	tag.size = Vector2(200, 20)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tag)
	panel = PanelContainer.new()
	panel.position = Vector2(300, 100)
	panel.custom_minimum_size = Vector2(680, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Overlay.PANEL
	sb.border_width_top = 6
	sb.border_color = Overlay.ACCENT
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	body = Label.new()
	body.add_theme_font_size_override("font_size", 14)
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
