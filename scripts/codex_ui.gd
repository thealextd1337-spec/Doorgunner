extends CanvasLayer
## F1 (action "help", or the ESC menu button): the help and codex screen. Pages: "Controls" (every current binding, plus the touch
## controls while touch mode is on) and the Codex categories (scripts/codex.gd; locked entries show as ???, empty ones say so).
## Pauses the game while open, like the ESC menu.

const CONTROLS := "Controls"
const TOUCH_LINES := [["Left stick", "fly"], ["Right stick", "aim; held out it fires the door gun"], ["LAND / TAKE OFF", "land or lift off"],
	["GUN", "switch gun"], ["< YAW  YAW >", "turn the heli"], ["SPEAKER", "loudspeaker"], ["HOOK", "hook a wreck (when one is below)"],
	["JOBS", "missions"], ["FOUND / OUTPOST / PROTECT", "appear when they apply"], ["MENU", "ESC menu"],
	["Build mode", "tap the map to move the preview, then PLACE / REMOVE / ROTATE / DONE"]]

var page := CONTROLS
var content: VBoxContainer # the shown page
var page_btns := {} # page name -> Button
var prev_ui_open := false
var was_paused := false
var hint: Label
var root: Control # UiTheme root
var panel: PanelContainer


func _ready() -> void:
	layer = 45 # over the title (40) and the touch layer (31)
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	root = UiTheme.attach(self)
	root.theme = UiTheme.theme()
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.7)
	root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 140)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 50)
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
	title.text = "HELP & CODEX"
	title.add_theme_font_size_override("font_size", UiTheme.FONT_XL)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.tooltip_text = Tooltips.tip("codex_close")
	close_btn.pressed.connect(close)
	head.add_child(close_btn)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 160
	body.add_child(nav)
	for p in [CONTROLS] + Codex.CATEGORIES:
		var b := Button.new()
		b.text = p
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = Tooltips.tip("codex_" + p.to_lower())
		b.pressed.connect(show_page.bind(p))
		nav.add_child(b)
		page_btns[p] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	hint = Label.new()
	hint.modulate = UiTheme.DIM
	outer.add_child(hint)


## Before the game's own handlers (and the ESC menu's): while open, help and menu close it.
func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("help") or event.is_action_pressed("menu") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
	elif not visible and event.is_action_pressed("help") and not _blocked():
		open()
		get_viewport().set_input_as_handled()


## No help while a level-up card choice waits or the key screen is open (it may be capturing F1 as a new binding).
func _blocked() -> bool:
	var w := Game.world
	return w != null and is_instance_valid(w.choice_ui) and w.choice_ui.visible 		or get_tree().get_nodes_in_group("keys_ui").any(func(k): return k.visible)


func open() -> void:
	was_paused = get_tree().paused
	prev_ui_open = Game.world.ui_open
	Game.world.ui_open = true
	get_tree().paused = true
	visible = true
	hint.text = "[%s] close   -   rebind keys in the ESC menu" % KeyMap.text("help")
	show_page(page)


func close() -> void:
	visible = false
	get_tree().paused = was_paused
	Game.world.ui_open = prev_ui_open
	Sfx.play("ui")


func show_page(p: String) -> void:
	page = p
	for c in content.get_children():
		content.remove_child(c)
		c.queue_free()
	for name in page_btns:
		page_btns[name].disabled = name == p
	if p == CONTROLS:
		_controls_page()
	else:
		_codex_page(p)


func _controls_page() -> void:
	for g in KeyMap.GROUPS:
		_heading(g[0])
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		content.add_child(grid)
		for a in g[1]:
			var l := Label.new()
			l.text = a[1]
			l.custom_minimum_size.x = 220
			grid.add_child(l)
			var k := Label.new()
			k.text = KeyMap.text(a[0])
			k.add_theme_color_override("font_color", UiTheme.ACCENT)
			grid.add_child(k)
	if Controls.touch:
		_heading("Touch controls")
		for t in TOUCH_LINES:
			_line("%s  -  %s" % t, UiTheme.SAND)


func _codex_page(category: String) -> void:
	_heading(category)
	var ids := Codex.in_category(category)
	if ids.is_empty():
		_line("Nothing to read here yet.", UiTheme.DIM)
	for id in ids:
		var e: Dictionary = Codex.entries[id]
		if Codex.is_unlocked(id):
			_line(e["title"], UiTheme.ACCENT)
			_line(e["text"], UiTheme.SAND)
		else:
			_line("???  (not discovered yet)", UiTheme.DIM)


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.add_theme_font_size_override("font_size", UiTheme.FONT_L)
	content.add_child(l)


func _line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	content.add_child(l)
