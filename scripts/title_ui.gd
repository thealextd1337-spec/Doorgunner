extends CanvasLayer
## Title screen over the live world. ENTER / SPACE / START button emits start_pressed once and hides.

signal start_pressed

const SAND := Color(0.91, 0.86, 0.71)
const ACCENT := Color(0.96, 0.77, 0.18) # warning yellow
const PANEL := Color(0.06, 0.08, 0.04, 0.86)
const OLIVE := Color(0.33, 0.37, 0.2)

var mono := SystemFont.new()
var stats: Label
var hint: Label
var rotor: Sprite2D
var t := 0.0
var tutorial := false # TUTORIAL button: main.gd starts the tutorial with the run


func _ready() -> void:
	layer = 40
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.01, 0.68)
	add_child(dim)
	# big decorative heli on the right, over the real base
	var heli := Node2D.new()
	heli.position = Vector2(990, 330)
	heli.scale = Vector2(6, 6)
	heli.rotation = 0.35
	add_child(heli)
	var body := Art.sprite("heli")
	heli.add_child(body)
	rotor = Art.sprite("rotor")
	rotor.scale *= 1.5
	heli.add_child(rotor)
	var call := _label("CALLSIGN  DG-1  //  ON THE PAD", 14, OLIVE.lightened(0.4), mono)
	call.position = Vector2(875, 540)
	add_child(call)

	var panel := PanelContainer.new()
	panel.position = Vector2(80, 96)
	panel.custom_minimum_size = Vector2(640, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 8
	sb.border_color = ACCENT
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(_label("// FOB RADIO  -  CH 07  -  SECURE", 13, ACCENT, mono))
	var title := _label("DOORGUNNER", 88, SAND)
	title.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.01))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", ACCENT.darkened(0.45))
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 6)
	v.add_child(title)
	v.add_child(_label("Fly in. Pull them out. Hold the line.", 20, ACCENT))
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 2)
	rule.color = OLIVE
	v.add_child(rule)
	v.add_child(_label("> Land by towns and pick up the survivors.\n> Fly them to base. Spend scrap to build it up.\n> Every third night the horde attacks. Hold the base.", 16, SAND, mono))
	v.add_child(_label("WASD   fly             MOUSE  aim     LMB  fire\nSPACE  land / take off  R      restart", 14, SAND.darkened(0.3), mono))
	stats = _label("", 13, OLIVE.lightened(0.45), mono)
	v.add_child(stats)
	var btn := Button.new()
	btn.text = "CLEARED FOR TAKEOFF"
	btn.custom_minimum_size = Vector2(0, 56)
	btn.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = ACCENT if state != "hover" else ACCENT.lightened(0.2)
		if state == "focus":
			s.draw_center = false
		btn.add_theme_stylebox_override(state, s)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(c, Color(0.06, 0.07, 0.03))
	btn.pressed.connect(_start)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(btn)
	var tut := Button.new()
	tut.text = "TUTORIAL"
	tut.custom_minimum_size = Vector2(140, 56)
	tut.add_theme_font_size_override("font_size", 18)
	tut.pressed.connect(func():
		tutorial = true
		_start())
	row.add_child(tut)
	hint = _label("press ENTER", 14, SAND, mono)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


func open() -> void:
	var m: Dictionary = Game.meta
	stats.text = "NO SERVICE RECORD. FIRST SORTIE." if m["runs"] == 0 else "SERVICE RECORD  sorties %d  rescued %d  kills %d  best day %d" % [m["runs"], m["total_rescued"], m["total_kills"], m["best_day"]]
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	rotor.rotation += 9.0 * delta
	hint.modulate.a = 1.0 if fmod(t, 1.2) < 0.8 else 0.15


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		_start()


func _start() -> void:
	if not visible:
		return
	visible = false
	# delayed a few frames so this SPACE press is not also read as "take off" by the heli
	get_tree().create_timer(0.05).timeout.connect(start_pressed.emit)
