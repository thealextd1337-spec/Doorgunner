extends CanvasLayer
## ESC: one row per option registered in Settings (sliders: label + slider, toggles: check button). Pauses the game while open.
## Centred under a UiTheme root that scales as far as the panel fits (the "UI scale" row rescales it live).

var panel: PanelContainer
var rows := {} # key -> HSlider or CheckButton
var skip_btn: Button
var keys_ui: CanvasLayer # key bindings screen (keys_ui.gd)
var prev_ui_open := false


func _ready() -> void:
	layer = 25
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	var root := UiTheme.attach(self)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 400
	center.add_child(panel)
	root.fit = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.GAP)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SOUND"
	title.add_theme_font_size_override("font_size", UiTheme.FONT_XL)
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
	keys_ui = preload("res://scripts/keys_ui.gd").new()
	add_child(keys_ui)
	skip_btn = Button.new()
	skip_btn.text = "Skip tutorial"
	skip_btn.tooltip_text = Tooltips.tip("menu_skip")
	skip_btn.pressed.connect(func():
		Game.world.tutorial.finish(false)
		close())
	box.add_child(skip_btn)
	var foot := HBoxContainer.new() # resume hint, key bindings and help share one row: the panel has no room for another
	box.add_child(foot)
	var hint := Label.new()
	hint.text = "[ESC] resume"
	hint.modulate = Color(0.7, 0.7, 0.7)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	for def in [["Key bindings...", "menu_keys", func(): keys_ui.open()], ["Help & codex", "menu_help", func(): Game.world.codex_ui.open()]]:
		var b := Button.new()
		b.text = def[0]
		b.tooltip_text = Tooltips.tip(def[1])
		b.pressed.connect(def[2])
		foot.add_child(b)
	var ver := Label.new()
	ver.text = Game.version_text()
	ver.modulate = Color(0.5, 0.5, 0.5)
	ver.add_theme_font_size_override("font_size", UiTheme.FONT_XS)
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
