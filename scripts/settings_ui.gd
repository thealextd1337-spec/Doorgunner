extends CanvasLayer
## ESC: one row per option registered in Settings (sliders: label + slider, toggles: check button). Pauses the game while open.

var panel: PanelContainer
var rows := {} # key -> HSlider or CheckButton
var skip_btn: Button
var prev_ui_open := false


func _ready() -> void:
	layer = 25
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	panel = PanelContainer.new()
	panel.position = Vector2(440, 200)
	panel.size = Vector2(400, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SOUND"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	for key in Settings.defs:
		var def: Dictionary = Settings.defs[key]
		if def["kind"] == "toggle":
			var b := CheckButton.new()
			b.text = def["label"]
			b.toggled.connect(func(on: bool): set_volume(key, 1 if on else 0))
			box.add_child(b)
			rows[key] = b
			continue
		var l := Label.new()
		l.text = def["label"]
		box.add_child(l)
		var s := HSlider.new()
		s.min_value = def["min"]
		s.max_value = def["max"]
		s.step = def["step"]
		s.custom_minimum_size.x = 360
		s.value_changed.connect(func(v: float): set_volume(key, v))
		box.add_child(s)
		rows[key] = s
	_sync()
	skip_btn = Button.new()
	skip_btn.text = "Skip tutorial"
	skip_btn.pressed.connect(func():
		Game.world.tutorial.finish(false)
		close())
	box.add_child(skip_btn)
	var hint := Label.new()
	hint.text = "[ESC] resume"
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)
	var ver := Label.new()
	ver.text = Game.version_text()
	ver.modulate = Color(0.5, 0.5, 0.5)
	ver.add_theme_font_size_override("font_size", 11)
	box.add_child(ver)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		close() if visible else open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_sync()
	skip_btn.visible = is_instance_valid(Game.world.tutorial)
	prev_ui_open = Game.world.ui_open
	Game.world.ui_open = true
	get_tree().paused = true
	visible = true


func close() -> void:
	visible = false
	get_tree().paused = false
	Game.world.ui_open = prev_ui_open
	Game._save_meta()
	Sfx.play("ui")


func _sync() -> void:
	for key in rows:
		if rows[key] is CheckButton:
			rows[key].set_pressed_no_signal(Settings.is_on(key))
		else:
			rows[key].set_value_no_signal(Settings.get_value(key))


## Row callback (any registered key; name kept from the sound-only menu).
func set_volume(key: String, value: Variant) -> void:
	Settings.set_value(key, value)
	Sfx.apply_volumes()
