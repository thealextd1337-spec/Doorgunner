class_name Overlay
extends CanvasLayer
## Base of the title's modal screens (profiles, leaderboard): dim background, centered panel in the title's style,
## label / button helpers, ESC closes. Subclasses fill `box`.

const SAND := UiTheme.SAND
const ACCENT := UiTheme.ACCENT
const PANEL := UiTheme.PANEL
const OLIVE := UiTheme.OLIVE
const RED := UiTheme.BAD

var mono := UiTheme.mono()
var box: VBoxContainer
var closable := true


func _init() -> void:
	layer = 41 # over the title (40)
	process_mode = PROCESS_MODE_ALWAYS
	visible = false


func _build(min_width: int) -> void:
	var root := UiTheme.attach(self) # scales as far as the panel fits (fit below)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.01, 0.8)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(min_width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 8
	sb.border_color = ACCENT
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	root.fit = panel
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)


func label(text: String, size := UiTheme.FONT_M, color := SAND) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", mono)
	return l


func button(text: String, width := 0, accent := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 40)
	b.add_theme_font_override("font", mono)
	b.add_theme_font_size_override("font_size", UiTheme.FONT_L)
	if accent:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var s := StyleBoxFlat.new()
			s.bg_color = ACCENT if state != "hover" else ACCENT.lightened(0.2)
			if state == "disabled":
				s.bg_color = OLIVE
			if state == "focus":
				s.draw_center = false
			b.add_theme_stylebox_override(state, s)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(c, Color(0.06, 0.07, 0.03))
	return b


func portrait(avatar: int, size := 48) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Profiles.avatar_tex(avatar)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


func clear() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func close() -> void:
	visible = false


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		if closable:
			close()
