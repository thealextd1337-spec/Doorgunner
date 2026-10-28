extends CanvasLayer
## Level-up cards from Game.offer_cards: pauses the tree. Click or 1-4 picks, R rerolls, S skips (+15 scrap),
## B toggles banish mode (meta unlock). Requests queue while open. Nothing left to offer: scrap + hull patch, no pause.

const SLOT_COLORS := {"hardpoint": Color(1, 0.62, 0.3), "system": Color(0.45, 0.8, 1), "module": Color(0.55, 0.95, 0.5)}
const SKIP_SCRAP := 15

var title_label: Label
var row: HBoxContainer
var reroll_btn: Button
var skip_btn: Button
var banish_btn: Button
var options := [] # item ids on the cards
var count := 3
var title := ""
var banish_mode := false
var queue := []
var prev_ui_open := false


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
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	box.add_child(actions)
	reroll_btn = _button(actions, reroll)
	skip_btn = _button(actions, skip)
	skip_btn.text = "[S] Skip  +%d scrap" % SKIP_SCRAP
	banish_btn = _button(actions, toggle_banish)
	var hint := Label.new()
	hint.text = "Click a card or press its number"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)


func _button(parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 34)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func open(t: String, n: int) -> void:
	if visible:
		queue.append([t, n])
		return
	options = Game.offer_cards(n)
	if options.is_empty():
		Game.scrap += 40
		Game.hp = minf(Game.max_hp, Game.hp + Game.max_hp * 0.1)
		Game.radio("Crew: nothing left to fit. Mechanics salvage 40 scrap and patch the hull.")
		return
	title = t
	count = n
	banish_mode = false
	_build()
	visible = true
	get_tree().paused = true
	Sfx.play("levelup")
	prev_ui_open = Game.world.ui_open # base menu may still be open underneath
	Game.world.ui_open = true


func _build() -> void:
	for c in row.get_children():
		row.remove_child(c) # a card may be mid-input-signal, so no free()
		c.queue_free()
	for i in options.size():
		row.add_child(_card(i, options[i]))
	title_label.text = "BANISH: pick a card to remove it for this run" if banish_mode else title
	reroll_btn.text = "[R] Reroll  (%d left)" % Game.rerolls
	reroll_btn.disabled = Game.rerolls <= 0
	banish_btn.text = "[B] Cancel banish" if banish_mode else "[B] Banish  (%d left)" % (3 - Game.banished.size())
	banish_btn.visible = banish_mode or Progression.can_banish()


func pick(i: int) -> void:
	if not visible or i < 0 or i >= options.size():
		return
	Sfx.play("ui")
	if banish_mode:
		Game.banished.append(options[i])
		banish_mode = false
		options = Game.offer_cards(count)
		if options.is_empty():
			_close()
		else:
			_build()
		return
	Game.take_item(options[i])
	_close()


func reroll() -> void:
	if not visible or Game.rerolls <= 0:
		return
	Game.rerolls -= 1
	options = Game.offer_cards(count)
	_build()


func skip() -> void:
	if not visible:
		return
	Game.scrap += SKIP_SCRAP
	Game.skips += 1
	_close()


func toggle_banish() -> void:
	if visible and (banish_mode or Progression.can_banish()):
		banish_mode = not banish_mode
		_build()


func _close() -> void:
	visible = false
	get_tree().paused = false
	Game.world.ui_open = prev_ui_open
	while not queue.is_empty() and not visible:
		var next: Array = queue.pop_front()
		open(next[0], next[1])


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4: pick(event.keycode - KEY_1)
		KEY_R: reroll()
		KEY_S: skip()
		KEY_B: toggle_banish()
		_: return
	get_viewport().set_input_as_handled()


func _card(i: int, id: String) -> Control:
	var it: Dictionary = Progression.ITEMS[id]
	var lv := Progression.level(id) if Progression.owned(id) else 0
	var col: Color = SLOT_COLORS[it["slot"]]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 250)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.06, 0.96)
	sb.border_width_top = 4
	sb.border_color = col
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			pick(i))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_text(v, "%s   %s" % [it["slot"].to_upper(), "NEW" if lv == 0 else "LV %d > %d" % [lv, lv + 1]], 12, col)
	_text(v, it["name"], 22, Color.WHITE)
	var dots := RichTextLabel.new()
	dots.bbcode_enabled = true
	dots.fit_content = true
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.add_theme_font_size_override("normal_font_size", 28)
	dots.text = "[color=#ffffff]%s[/color][color=#%s]●[/color][color=#4a4a44]%s[/color]" % ["●".repeat(lv), col.to_html(false), "●".repeat(4 - lv)]
	v.add_child(dots)
	_text(v, it["per_level"][lv], 16, Color(0.95, 0.9, 0.7))
	_text(v, it["desc"], 12, Color(0.65, 0.65, 0.6))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_text(v, "[%d]" % (i + 1), 14, Color(0.7, 0.7, 0.7)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return panel


func _text(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l
