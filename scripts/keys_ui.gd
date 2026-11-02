extends CanvasLayer
## Key bindings screen, opened from the ESC menu (settings_ui.gd). One row per action (keymap.gd): a button per binding (click, then press
## a key or mouse button to replace it; right-click removes it), "+" adds another, and shared keys that are not shared by default
## are flagged in red. "Reset to defaults" drops all own bindings. Changes apply at once and are saved with the other settings.

var rows := {} # action -> {"box": HBoxContainer of the binding buttons, "warn": Label}
var list: VBoxContainer
var status: Label
var capturing := "" # action waiting for a key press
var capture_index := -1 # binding being replaced, -1: add a new one
var root: Control # UiTheme root
var panel: PanelContainer


func _ready() -> void:
	layer = 46 # over the ESC menu (25), under nothing that matters while it is open
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	add_to_group("keys_ui") # codex_ui.gd keeps F1 away while this is open
	root = UiTheme.attach(self)
	root.theme = UiTheme.theme()
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.8)
	root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 160)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	root.add_child(margin)
	root.fit = margin # the scale stops where the widest row still fits (rows scroll vertically)
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new() # opaque, like the base menu panels
	sb.bg_color = UiTheme.PANEL
	sb.border_width_top = 6
	sb.border_color = UiTheme.ACCENT
	sb.set_content_margin_all(UiTheme.PAD)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	var outer := VBoxContainer.new()
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := Label.new()
	title.text = "KEY BINDINGS"
	title.add_theme_font_size_override("font_size", UiTheme.FONT_XL)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.tooltip_text = Tooltips.tip("keys_reset")
	reset.pressed.connect(reset_all)
	head.add_child(reset)
	var back := Button.new()
	back.text = "Back"
	back.tooltip_text = Tooltips.tip("keys_back")
	back.pressed.connect(close)
	head.add_child(back)
	status = Label.new()
	status.modulate = UiTheme.DIM
	outer.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for g in KeyMap.GROUPS:
		var h := Label.new()
		h.text = g[0].to_upper()
		h.add_theme_color_override("font_color", UiTheme.ACCENT)
		list.add_child(h)
		for a in g[1]:
			_row(a[0], a[1])


func _row(action: String, label: String) -> void:
	var h := HBoxContainer.new()
	list.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 220
	h.add_child(l)
	var box := HBoxContainer.new()
	h.add_child(box)
	var warn := Label.new()
	warn.add_theme_color_override("font_color", UiTheme.BAD)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(warn)
	rows[action] = {"box": box, "warn": warn}


func open() -> void:
	capturing = ""
	_refresh()
	visible = true


func close() -> void:
	capturing = ""
	visible = false


## Start listening for the next key or mouse button for `action`: replaces binding `index`, or adds one (-1).
func begin(action: String, index := -1) -> void:
	capturing = action
	capture_index = index
	_refresh()


func reset_all() -> void:
	capturing = ""
	KeyMap.reset()
	_refresh()


## Binds `raw` to the action being captured (false for events that cannot be bound: modifiers, releases, touches).
func bind(raw: InputEvent) -> bool:
	var e := KeyMap.binding_for(capturing, raw)
	if e == null or not raw.is_pressed() or raw is InputEventKey and raw.echo:
		return false
	var evs := KeyMap.events_of(capturing)
	if capture_index >= 0 and capture_index < evs.size():
		evs[capture_index] = e
	else:
		evs.append(e)
	KeyMap.set_bindings(capturing, evs)
	capturing = ""
	_refresh()
	return true


## False when `index` is the last binding of a KeyMap.REQUIRED action (ESC menu, help): those keep one.
func remove(action: String, index: int) -> bool:
	var evs := KeyMap.events_of(action)
	evs.remove_at(index)
	var ok := KeyMap.set_bindings(action, evs)
	_refresh()
	if not ok:
		status.text = "\"%s\" needs at least one key." % KeyMap.label_of(action)
	return ok


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if capturing != "":
		if event.is_action_pressed("ui_cancel"):
			capturing = ""
			_refresh()
		elif event is InputEventKey or event is InputEventMouseButton:
			bind(event)
		else:
			return # mouse motion etc. stays with the menu
		get_viewport().set_input_as_handled() # the pressed key never reaches the game or the ESC menu
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		close()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	var total := 0
	for action in rows:
		var box: HBoxContainer = rows[action]["box"]
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
		var evs := KeyMap.events_of(action)
		for i in evs.size():
			var b := Button.new()
			b.text = "press a key..." if capturing == action and capture_index == i else KeyMap.event_text(evs[i])
			b.custom_minimum_size.x = 110
			b.tooltip_text = Tooltips.tip("key_binding")
			b.pressed.connect(begin.bind(action, i))
			b.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					remove.call_deferred(action, i))
			box.add_child(b)
		var add := Button.new()
		add.text = "press a key..." if capturing == action and capture_index == -1 else "+"
		add.tooltip_text = Tooltips.tip("key_add")
		add.pressed.connect(begin.bind(action, -1))
		box.add_child(add)
		var clash := KeyMap.conflicts(action)
		rows[action]["warn"].text = "also: " + ", ".join(clash) if not clash.is_empty() else ""
		total += clash.size()
	status.text = "Press a key to rebind. ESC cancels, right-click removes a binding.   Conflicts: %d" % total if capturing == "" else \
		"Press the new key or mouse button for \"%s\"  (ESC cancels)" % KeyMap.label_of(capturing)
