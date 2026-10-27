extends CanvasLayer
## Level-up choice: pauses the tree, shows 3 cards; click or keys 1/2/3 picks. Requests queue while open.

var title_label: Label
var row: HBoxContainer
var options := []
var queue := []


func _ready() -> void:
	layer = 20
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	box.add_child(title_label)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var hint := Label.new()
	hint.text = "Click a card or press 1 / 2 / 3"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)


var prev_ui_open := false


func open(title: String, opts: Array) -> void:
	if visible:
		queue.append([title, opts])
		return
	options = opts
	title_label.text = title
	for c in row.get_children():
		c.free()
	for i in opts.size():
		row.add_child(_card(i, opts[i]))
	visible = true
	get_tree().paused = true
	Sfx.play("levelup")
	prev_ui_open = Game.world.ui_open # base menu may still be open underneath
	Game.world.ui_open = true


func pick(i: int) -> void:
	if not visible or i < 0 or i >= options.size():
		return
	options[i]["apply"].call()
	Sfx.play("ui")
	visible = false
	get_tree().paused = false
	Game.world.ui_open = prev_ui_open
	if not queue.is_empty():
		var next: Array = queue.pop_front()
		open(next[0], next[1])


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_3:
		pick(event.keycode - KEY_1)
		get_viewport().set_input_as_handled()


func _card(i: int, opt: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 130)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var btn := Button.new()
	btn.text = "%d. %s" % [i + 1, opt["name"]]
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(pick.bind(i))
	v.add_child(btn)
	var desc := Label.new()
	desc.text = opt["desc"]
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(desc)
	return panel
