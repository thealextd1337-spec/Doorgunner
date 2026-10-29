extends CanvasLayer
## ESC: sound settings (master / effects / music+ambience / mute). Pauses the game while open.

const ROWS := {"vol_master": "Master", "vol_sfx": "Effects", "vol_music": "Music & ambience"}

var panel: PanelContainer
var sliders := {}
var mute_btn: CheckButton
var shake_btn: CheckButton
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
	for key in ROWS:
		var l := Label.new()
		l.text = ROWS[key]
		box.add_child(l)
		var s := HSlider.new()
		s.max_value = 100
		s.value = Game.meta[key]
		s.custom_minimum_size.x = 360
		s.value_changed.connect(func(v: float): set_volume(key, int(v)))
		box.add_child(s)
		sliders[key] = s
	mute_btn = CheckButton.new()
	mute_btn.text = "Mute all  (M)"
	mute_btn.button_pressed = Game.meta["muted"] == 1
	mute_btn.toggled.connect(func(on: bool): set_volume("muted", 1 if on else 0))
	box.add_child(mute_btn)
	shake_btn = CheckButton.new()
	shake_btn.text = "Screen shake (heavy guns)"
	shake_btn.button_pressed = Game.meta["shake"] == 1
	shake_btn.toggled.connect(func(on: bool): set_volume("shake", 1 if on else 0))
	box.add_child(shake_btn)
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
	for key in sliders:
		sliders[key].set_value_no_signal(Game.meta[key])
	mute_btn.set_pressed_no_signal(Game.meta["muted"] == 1)
	shake_btn.set_pressed_no_signal(Game.meta["shake"] == 1)
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


func set_volume(key: String, value: int) -> void:
	Game.meta[key] = value
	Sfx.apply_volumes()
