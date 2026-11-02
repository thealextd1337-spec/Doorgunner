extends CanvasLayer
## Level-up cards from Game.offer_cards: pauses the tree. Click or 1-4 picks, R rerolls, S skips (+15 scrap),
## B toggles banish mode (meta unlock). Requests queue while open. Nothing left to offer: scrap + hull patch, no pause.
## Q13 radio event cards (events.gd) use the same queue and number keys: a panel at the bottom, no dim and no pause, 1-3 or a click
## answers, after Events.TIMEOUT s the default option is taken. A level-up card and an event card never show together.

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
var queue := [] # [title, count] level-up requests and {id, ctx} event requests
var prev_ui_open := false
var dim: ColorRect
var ev := {} # the open event card: {id, ctx, view, left}
var ev_panel: PanelContainer
var ev_box: VBoxContainer
var ev_head: Label
var ev_title: Label
var ev_text: Label
var ev_rows: VBoxContainer
var ev_wait: Label


func _ready() -> void:
	layer = 20
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	var root := UiTheme.attach(self)
	add_to_group(UiTheme.OBSTACLES) # the HUD lays its radio log around the event panel
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)
	root.fit = box # four cards at 150 % would not fit: scales only that far
	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", UiTheme.FONT_XL + 4)
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
	_build_event_panel(root)


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
	dim.visible = true
	ev_panel.visible = false
	options = Game.offer_cards(n)
	if options.is_empty():
		Game.scrap += SKIP_SCRAP # what skipping a card pays (was 40: 15 % of the late scrap)
		Game.hp = minf(Game.max_hp, Game.hp + Game.max_hp * 0.1)
		Game.radio("Crew: nothing left to fit. Mechanics salvage %d scrap and patch the hull." % SKIP_SCRAP)
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
	if not ev.is_empty():
		pick_event(i)
		return
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
	_drain()


func _drain() -> void:
	while not queue.is_empty() and not visible:
		var next = queue.pop_front()
		if next is Dictionary:
			open_event(next["id"], next["ctx"])
		else:
			open(next[0], next[1])


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not ev.is_empty():
		for n in ev["view"]["opts"].size():
			if event.is_action_pressed("slot_%d" % (n + 1)):
				pick_event(n)
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("reroll"):
		reroll()
	elif event.is_action_pressed("skip"):
		skip()
	elif event.is_action_pressed("banish"):
		toggle_banish()
	else:
		var i := range(4).filter(func(n): return event.is_action_pressed("slot_%d" % (n + 1)))
		if i.is_empty():
			return
		pick(i[0])
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
	if ResourceLoader.exists("res://assets/sprites/%s/icon_%s.png" % [Art.variant, id]): # Q8 items have a card icon
		var icon := TextureRect.new()
		icon.texture = Art.tex("icon_" + id)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(icon)
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


# --- Q13 radio event cards (events.gd): the panel sits at the bottom, the game keeps running

func _build_event_panel(root: Control) -> void:
	ev_panel = PanelContainer.new()
	ev_panel.visible = false
	ev_panel.custom_minimum_size.x = 480
	ev_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ev_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ev_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ev_panel.offset_bottom = -(UiTheme.BOTTOM_ROW + UiTheme.GAP)
	ev_panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.PAD, UiTheme.ACCENT))
	root.add_child(ev_panel)
	ev_box = VBoxContainer.new()
	ev_box.add_theme_constant_override("separation", UiTheme.GAP)
	ev_panel.add_child(ev_box)
	ev_head = _text(ev_box, "", UiTheme.FONT_S, UiTheme.ACCENT)
	ev_title = _text(ev_box, "", UiTheme.FONT_L, Color.WHITE)
	ev_text = _text(ev_box, "", UiTheme.FONT, UiTheme.RADIO)
	ev_rows = VBoxContainer.new()
	ev_rows.add_theme_constant_override("separation", UiTheme.GAP)
	ev_box.add_child(ev_rows)
	ev_wait = _text(ev_box, "", UiTheme.FONT_XS, UiTheme.DIM)


## Shows radio event card `id` (Events.add), or queues it behind an open card.
func open_event(id: String, ctx: Dictionary) -> void:
	if visible:
		queue.append({"id": id, "ctx": ctx})
		return
	var view: Dictionary = Game.world.events.view(id, ctx)
	ev = {"id": id, "ctx": ctx, "view": view, "left": Events.TIMEOUT}
	ev_head.text = "RADIO  -  %s" % view["from"]
	ev_title.text = view["title"]
	ev_text.text = view["text"]
	for c in ev_rows.get_children():
		ev_rows.remove_child(c)
		c.queue_free()
	for i in view["opts"].size():
		var o: Dictionary = view["opts"][i]
		var b := Button.new()
		b.text = "[%d] %s%s" % [i + 1, o["t"], "   -   " + o["h"] if o["h"] != "" else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = UiTheme.TOUCH_MIN if Controls.touch else 28
		b.disabled = not o["ok"]
		b.pressed.connect(pick_event.bind(i))
		ev_rows.add_child(b)
	_event_wait()
	dim.visible = false
	ev_panel.visible = true
	visible = true
	Sfx.play("event")


func pick_event(i: int) -> void:
	if ev.is_empty() or i < 0 or i >= ev["view"]["opts"].size() or not ev["view"]["opts"][i]["ok"]:
		return
	Sfx.play("ui")
	var done := ev
	ev = {} # before the effects: a level-up they cause opens at once
	visible = false
	ev_panel.visible = false
	Game.world.events.resolve(done["id"], done["ctx"], i)
	_drain()


func _event_wait() -> void:
	var o: Dictionary = ev["view"]["opts"][ev["view"]["default"]]
	ev_wait.text = "No answer in %d s: %s" % [ceili(ev["left"]), o["t"]]


func _process(delta: float) -> void:
	if ev.is_empty() or get_tree().paused:
		return
	ev["left"] -= delta
	if ev["left"] <= 0.0:
		pick_event(ev["view"]["default"])
	else:
		_event_wait()


## HUD obstacle: the event panel, while one is open.
func obstacles() -> Array:
	return [ev_panel] if not ev.is_empty() else []
