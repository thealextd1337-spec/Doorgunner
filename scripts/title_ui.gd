extends CanvasLayer
## Title screen over the live world. ENTER / SPACE / START button emits start_pressed once and hides.
## HANGAR button / H swaps the decorative heli for the list of all heli items and their meta unlocks.

signal start_pressed

const SAND := Color(0.91, 0.86, 0.71)
const ACCENT := Color(0.96, 0.77, 0.18) # warning yellow
const PANEL := Color(0.06, 0.08, 0.04, 0.86)
const OLIVE := Color(0.33, 0.37, 0.2)

var mono := SystemFont.new()
var stats: Label
var hint: Label
var rotor: Sprite2D
var deco: Node2D
var deco_call: Label
var hangar: PanelContainer
var hangar_grid: GridContainer
var t := 0.0
var tutorial := false # TUTORIAL button: main.gd starts the tutorial with the run
var start_btn: Button
var cont_btn: Button # CONTINUE: only with a saved run (scripts/save.gd)
var notice: Label
var online_notice: Label # Online.title_notice(): "Offline - this run is not ranked"
var confirm: ConfirmationDialog
var badge: Button # active profile (portrait + name), opens PROFILES
var profile_ui: ProfileUi
var board_ui: LeaderboardUi


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
	deco = heli
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
	deco_call = call
	add_child(call)
	var ver := _label(Game.version_text(), 12, OLIVE.lightened(0.3), mono)
	ver.position = Vector2(970, 694) # bottom-right corner of the 1280x720 canvas
	ver.size = Vector2(300, 18)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ver)

	var panel := PanelContainer.new()
	panel.position = Vector2(80, 90)
	panel.custom_minimum_size = Vector2(640, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 8
	sb.border_color = ACCENT
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
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
	v.add_child(_label("> Fly out, pick a site, land and found the base (B).\n> Land by towns and pick up the survivors.\n> Fly them to base. Spend scrap to build it up.\n> Every third night the horde attacks. Hold the base.", 16, SAND, mono))
	v.add_child(_label("WASD   fly             MOUSE  aim     LMB  fire\nSPACE  land / take off  R      restart", 14, SAND.darkened(0.3), mono))
	stats = _label("", 13, OLIVE.lightened(0.45), mono)
	v.add_child(stats)
	notice = _label("", 13, Color(1, 0.45, 0.35), mono)
	v.add_child(notice)
	online_notice = _label("", 13, Color(0.96, 0.77, 0.18), mono)
	v.add_child(online_notice)
	Online.online_changed.connect(_on_online_changed)
	cont_btn = _big_button()
	cont_btn.pressed.connect(_continue)
	v.add_child(cont_btn)
	var btn := _big_button()
	start_btn = btn
	btn.pressed.connect(_start)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	v.add_child(btn_row)
	btn_row.add_child(btn)
	var hangar_btn := Button.new()
	hangar_btn.text = "HANGAR [H]"
	hangar_btn.custom_minimum_size = Vector2(150, 56)
	hangar_btn.add_theme_font_override("font", mono)
	hangar_btn.add_theme_font_size_override("font_size", 16)
	hangar_btn.pressed.connect(_toggle_hangar)
	btn_row.add_child(hangar_btn)
	var tut := Button.new()
	tut.text = "TUTORIAL"
	tut.custom_minimum_size = Vector2(140, 56)
	tut.add_theme_font_override("font", mono)
	tut.add_theme_font_size_override("font_size", 16)
	tut.pressed.connect(func():
		tutorial = true
		_start())
	btn_row.add_child(tut)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	v.add_child(row2)
	for def in [["PROFILES", _open_profiles], ["LEADERBOARD [L]", _open_board]]:
		var b := Button.new()
		b.text = def[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(def[1])
		row2.add_child(b)
	badge = Button.new()
	badge.flat = true
	badge.position = Vector2(80, 24)
	badge.custom_minimum_size = Vector2(0, 56)
	badge.add_theme_font_override("font", mono)
	badge.add_theme_font_size_override("font_size", 22)
	badge.add_theme_color_override("font_color", SAND)
	badge.add_theme_constant_override("icon_max_width", 48)
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.pressed.connect(_open_profiles)
	add_child(badge)
	profile_ui = ProfileUi.new()
	profile_ui.changed.connect(open)
	add_child(profile_ui)
	board_ui = LeaderboardUi.new()
	add_child(board_ui)
	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Abandon the current run? It counts as lost."
	confirm.ok_button_text = "ABANDON"
	confirm.confirmed.connect(func():
		Save.abandon()
		_start())
	confirm.canceled.connect(func(): tutorial = false)
	add_child(confirm)
	_build_hangar()
	hint = _label("press ENTER", 14, SAND, mono)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _build_hangar() -> void:
	hangar = PanelContainer.new()
	hangar.position = Vector2(796, 96)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 8
	sb.border_color = OLIVE.lightened(0.3)
	sb.set_content_margin_all(20)
	hangar.add_theme_stylebox_override("panel", sb)
	hangar.visible = false
	add_child(hangar)
	var v := VBoxContainer.new()
	hangar.add_child(v)
	v.add_child(_label("// HANGAR  -  PARTS ON RECORD", 13, ACCENT, mono))
	hangar_grid = GridContainer.new()
	hangar_grid.columns = 3
	hangar_grid.add_theme_constant_override("h_separation", 14)
	v.add_child(hangar_grid)


func _toggle_hangar() -> void:
	hangar.visible = not hangar.visible
	deco.visible = not hangar.visible
	deco_call.visible = deco.visible
	for c in hangar_grid.get_children():
		c.free()
	for id in Progression.ITEMS:
		var it: Dictionary = Progression.ITEMS[id]
		var ok := Progression.unlocked(id)
		var col := SAND if ok else SAND.darkened(0.55)
		hangar_grid.add_child(_label(it["name"], 13, col, mono))
		hangar_grid.add_child(_label(it["slot"].to_upper(), 12, OLIVE.lightened(0.45) if ok else col, mono))
		hangar_grid.add_child(_label("ready" if ok else "LOCKED  " + Progression.condition(id), 12, ACCENT if ok else col, mono))


func _big_button() -> Button:
	var btn := Button.new()
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
	return btn


func _label(text: String, size: int, color: Color, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


func _open_profiles() -> void:
	if not _overlay_open():
		profile_ui.open_list()


func _open_board() -> void:
	if not _overlay_open():
		board_ui.open()


func _overlay_open() -> bool:
	return profile_ui.visible or board_ui.visible


func _refresh_online_notice() -> void:
	online_notice.text = Online.title_notice()
	online_notice.visible = online_notice.text != ""


## Registers a profile created offline, sends a pending rename / portrait. Offline it just fails and waits for online_changed.
func _sync_profile() -> void:
	var p := Profiles.active()
	if Profiles.needs_push(p) and not profile_ui.busy:
		await Profiles.push(p)
		_refresh_online_notice()


func _on_online_changed(on: bool) -> void:
	_refresh_online_notice()
	if on:
		_sync_profile()


func open() -> void:
	var m: Dictionary = Game.meta
	var p := Profiles.active()
	badge.text = " " + p.get("name", "")
	badge.icon = Profiles.avatar_tex(p.get("avatar", 0))
	if profile_ui.visible:
		pass
	elif Profiles.needs_enlist():
		profile_ui.enlist(p.get("id", ""), true) # first start (or no profile left): pick a callsign and portrait
	else:
		_sync_profile()
	stats.text = "NO SERVICE RECORD. FIRST SORTIE." if m["runs"] == 0 else "SERVICE RECORD  sorties %d  rescued %d  kills %d  best day %d" % [m["runs"], m["total_rescued"], m["total_kills"], m["best_day"]]
	var h := Save.head() # an outdated run is discarded here and leaves Save.notice
	cont_btn.visible = not h.is_empty()
	if cont_btn.visible:
		var mins := int(h["time"] * 24 * 60)
		cont_btn.text = "CONTINUE  -  DAY %d  %02d:%02d  -  %d RESCUED" % [h["day"], mins / 60, mins % 60, h["rescued"]]
	start_btn.text = "NEW RUN" if cont_btn.visible else "CLEARED FOR TAKEOFF"
	notice.text = Save.notice
	notice.visible = notice.text != ""
	Save.notice = ""
	_refresh_online_notice()
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	rotor.rotation += 9.0 * delta
	hint.modulate.a = 1.0 if fmod(t, 1.2) < 0.8 else 0.15


func _input(event: InputEvent) -> void:
	if _overlay_open():
		return # typing a name must not trigger H / SPACE / ENTER here
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		_open_board()
	elif visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		_toggle_hangar()
	elif visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		_continue() if cont_btn.visible else _start()


## The saved run: main._ready loads it after the reload.
func _continue() -> void:
	if not visible or confirm.visible or _overlay_open():
		return
	Save.pending = true
	get_tree().reload_current_scene()


func _start() -> void:
	if not visible or confirm.visible or _overlay_open():
		return
	if Save.has_run(): # NEW RUN over a saved one asks first
		confirm.popup_centered()
		return
	visible = false
	# delayed a few frames so this SPACE press is not also read as "take off" by the heli
	get_tree().create_timer(0.05).timeout.connect(start_pressed.emit)
