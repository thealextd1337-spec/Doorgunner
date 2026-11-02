extends CanvasLayer
## Title screen over the live world. ENTER / SPACE / START button emits start_pressed once and hides.
## HANGAR button / H swaps the decorative heli for the list of all heli items and their meta unlocks (scrolls).
## Laid out for the whole canvas: its UiTheme root shrinks to 90 % but never grows past 100 %; the right-hand side
## (heli, hangar, run setup, version) is anchored to the right edge.

signal start_pressed

const SAND := UiTheme.SAND
const ACCENT := UiTheme.ACCENT # warning yellow
const PANEL := Color(UiTheme.PANEL, 0.86) # the live world shows through
const OLIVE := UiTheme.OLIVE
const RIGHT_X := 484.0 # px from the right edge to the hangar / setup panels' left side
const RIGHT_W := 448.0

var mono := UiTheme.mono()
var root: UiTheme.Root
var right: Control # anchored to the top-right corner: decorative heli and callsign
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
var cont_daily_btn: Button # CONTINUE DAILY: the saved run of the slot "daily" (Q14), next to the normal one
var daily_panel: PanelContainer
var daily_btn: Button
var daily_lbl: Label # today's daily: modifiers, heli, countdown, played (Online.fetch_daily)
var daily_info := {} # get_daily's answer, {} offline
var daily_until := 0 # ticks_msec of the daily's reset
var _on_confirm := Callable() # what ABANDON in `confirm` does
var notice: Label
var online_notice: Label # Online.title_notice(): "Offline - this run is not ranked"
var confirm: ConfirmationDialog
var badge: Button # active profile (portrait + name), opens PROFILES
var profile_ui: ProfileUi
var data_ui: SaveDataUi # BACKUP: export / import (Q3)
var restore_btn: Button # RESTORE FROM CLOUD: no local run, but a cloud copy (Q3), of the normal or the daily slot
var restore_slot := "run"
var board_ui: LeaderboardUi
# NEW RUN setup (P15): run modifiers and the start heli, read by main.gd when the run starts
const Modifiers := preload("res://scripts/modifiers.gd")
const Wrecks := preload("res://scripts/wrecks.gd")
const HeliTypes := preload("res://scripts/heli_types.gd")
var mods: Array = []
var start_heli := "huey"
var setup: PanelContainer
var setup_title: Label
var heli_btn: Button
var mod_btns := {} # id -> Button


func _ready() -> void:
	layer = 40
	process_mode = PROCESS_MODE_ALWAYS
	visible = false
	root = UiTheme.attach(self, null, 1.0)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.01, 0.68)
	root.add_child(dim)
	right = Control.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(right)
	# big decorative heli on the right, over the real base
	var heli := Node2D.new()
	deco = heli
	heli.position = Vector2(990 - 1280, 330)
	heli.scale = Vector2(6, 6)
	heli.rotation = 0.35
	right.add_child(heli)
	var body := Art.sprite("heli")
	heli.add_child(body)
	rotor = Art.sprite("rotor")
	rotor.scale *= 1.5
	heli.add_child(rotor)
	var call := _label("CALLSIGN  DG-1  //  ON THE PAD", 14, OLIVE.lightened(0.4), mono)
	call.position = Vector2(875 - 1280, 540)
	deco_call = call
	right.add_child(call)
	var ver := _label(Game.version_text(), 12, OLIVE.lightened(0.3), mono)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_left = -310
	ver.offset_top = -26
	ver.offset_right = -UiTheme.MARGIN
	ver.offset_bottom = -UiTheme.MARGIN + 2
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ver)

	var panel := PanelContainer.new()
	panel.position = Vector2(80, 90)
	panel.custom_minimum_size = Vector2(640, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 8
	sb.border_color = ACCENT
	sb.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
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
	cont_btn.tooltip_text = Tooltips.tip("title_continue")
	cont_btn.pressed.connect(_continue)
	v.add_child(cont_btn)
	restore_btn = _big_button()
	restore_btn.add_theme_font_size_override("font_size", 18)
	restore_btn.tooltip_text = Tooltips.tip("title_restore")
	restore_btn.visible = false
	restore_btn.pressed.connect(_restore)
	v.add_child(restore_btn)
	var btn := _big_button()
	start_btn = btn
	btn.tooltip_text = Tooltips.tip("title_start")
	btn.pressed.connect(_start)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	v.add_child(btn_row)
	btn_row.add_child(btn)
	var hangar_btn := Button.new()
	hangar_btn.text = "HANGAR [H]"
	hangar_btn.tooltip_text = Tooltips.tip("title_hangar")
	hangar_btn.custom_minimum_size = Vector2(150, 56)
	hangar_btn.add_theme_font_override("font", mono)
	hangar_btn.add_theme_font_size_override("font_size", 16)
	hangar_btn.pressed.connect(_toggle_hangar)
	btn_row.add_child(hangar_btn)
	var tut := Button.new()
	tut.text = "TUTORIAL"
	tut.tooltip_text = Tooltips.tip("title_tutorial")
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
	for def in [["PROFILES", _open_profiles, "title_profiles"], ["LEADERBOARD [L]", _open_board, "title_board"], ["BACKUP", _open_data, "title_backup"]]:
		var b := Button.new()
		b.text = def[0]
		b.tooltip_text = Tooltips.tip(def[2])
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
	root.add_child(badge)
	profile_ui = ProfileUi.new()
	profile_ui.changed.connect(open)
	add_child(profile_ui)
	board_ui = LeaderboardUi.new()
	add_child(board_ui)
	data_ui = SaveDataUi.new()
	data_ui.changed.connect(open)
	add_child(data_ui)
	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "Abandon the current run? It counts as lost."
	confirm.ok_button_text = "ABANDON"
	confirm.confirmed.connect(func(): _on_confirm.call())
	confirm.canceled.connect(func(): tutorial = false)
	add_child(confirm)
	_build_hangar()
	_build_setup()
	_build_daily()
	hint = _label("press ENTER", 14, SAND, mono)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _build_hangar() -> void:
	hangar = PanelContainer.new() # top right down to the version line; the list scrolls
	hangar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	hangar.offset_left = -RIGHT_X
	hangar.offset_right = -RIGHT_X + RIGHT_W
	hangar.offset_top = 96
	hangar.offset_bottom = -36
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 8
	sb.border_color = OLIVE.lightened(0.3)
	sb.set_content_margin_all(20)
	hangar.add_theme_stylebox_override("panel", sb)
	hangar.visible = false
	root.add_child(hangar)
	var v := VBoxContainer.new()
	hangar.add_child(v)
	v.add_child(_label("// HANGAR  -  PARTS ON RECORD", 13, ACCENT, mono))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	hangar_grid = GridContainer.new()
	hangar_grid.columns = 3
	hangar_grid.add_theme_constant_override("h_separation", 14)
	scroll.add_child(hangar_grid)


## NEW RUN panel bottom right: start heli (cycles the unlocked types) and the run modifiers (locked ones say how to unlock).
func _build_setup() -> void:
	setup = PanelContainer.new() # bottom right, grows up
	setup.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	setup.offset_left = -RIGHT_X
	setup.offset_right = -RIGHT_X + RIGHT_W
	setup.offset_top = -36
	setup.offset_bottom = -36
	setup.grow_vertical = Control.GROW_DIRECTION_BEGIN
	setup.custom_minimum_size = Vector2(RIGHT_W, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 4
	sb.border_color = ACCENT
	sb.set_content_margin_all(UiTheme.PAD)
	setup.add_theme_stylebox_override("panel", sb)
	root.add_child(setup)
	var v := VBoxContainer.new()
	setup.add_child(v)
	setup_title = _label("", 13, ACCENT, mono)
	v.add_child(setup_title)
	heli_btn = Button.new()
	heli_btn.add_theme_font_override("font", mono)
	heli_btn.add_theme_font_size_override("font_size", 14)
	heli_btn.pressed.connect(func():
		var types := Wrecks.start_types()
		start_heli = types[(types.find(start_heli) + 1) % types.size()]
		_refresh_setup())
	v.add_child(heli_btn)
	var grid := GridContainer.new()
	grid.columns = 3
	v.add_child(grid)
	for id in Modifiers.TABLE:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(136, 40)
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 11)
		b.toggled.connect(func(on: bool):
			if on and not id in mods:
				mods.append(id)
			elif not on:
				mods.erase(id)
			_refresh_setup())
		grid.add_child(b)
		mod_btns[id] = b


## DAILY panel top right (Q14): today's modifiers and heli, countdown, played; PLAY DAILY and CONTINUE DAILY (the saved
## daily run, kept apart from the normal one).
func _build_daily() -> void:
	daily_panel = PanelContainer.new()
	daily_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	daily_panel.offset_left = -RIGHT_X
	daily_panel.offset_right = -RIGHT_X + RIGHT_W
	daily_panel.offset_top = 96
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 4
	sb.border_color = ACCENT
	sb.set_content_margin_all(UiTheme.PAD)
	daily_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(daily_panel)
	var v := VBoxContainer.new()
	daily_panel.add_child(v)
	daily_lbl = _label("", 13, SAND, mono)
	v.add_child(daily_lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	daily_btn = Button.new()
	daily_btn.text = "PLAY DAILY"
	daily_btn.tooltip_text = Tooltips.tip("title_daily")
	daily_btn.pressed.connect(_daily)
	cont_daily_btn = Button.new()
	cont_daily_btn.tooltip_text = Tooltips.tip("title_continue_daily")
	cont_daily_btn.visible = false
	cont_daily_btn.pressed.connect(_continue_daily)
	for b: Button in [daily_btn, cont_daily_btn]:
		b.custom_minimum_size = Vector2(0, UiTheme.TOUCH_MIN)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 14)
		row.add_child(b)


func _refresh_setup() -> void:
	if not start_heli in Wrecks.start_types():
		start_heli = "huey"
	var t: Dictionary = HeliTypes.TYPES[start_heli]
	heli_btn.text = "START HELI  < %s >  %s, %d seats" % [t["name"], t["role"], t["seats"]]
	heli_btn.tooltip_text = Tooltips.tip("title_heli")
	for id in mod_btns:
		var b: Button = mod_btns[id]
		var m: Dictionary = Modifiers.TABLE[id]
		var ok := Modifiers.unlocked(id)
		if not ok:
			mods.erase(id)
		b.disabled = not ok
		b.set_pressed_no_signal(id in mods)
		b.text = "%s x%.2f
%s" % [m["name"], m["factor"], m["desc"]]
		b.tooltip_text = Tooltips.modifier(id) if ok else "LOCKED  " + Modifiers.condition(id)
	setup_title.text = "// NEW RUN  -  MODIFIERS  -  SCORE x%.2f" % Modifiers.factor(mods)


func _toggle_hangar() -> void:
	hangar.visible = not hangar.visible
	setup.visible = not hangar.visible
	daily_panel.visible = not hangar.visible
	deco.visible = not hangar.visible
	deco_call.visible = deco.visible
	for c in hangar_grid.get_children():
		c.free()
	for id in Progression.ITEMS:
		var it: Dictionary = Progression.ITEMS[id]
		var ok := Progression.unlocked(id)
		var col := SAND if ok else SAND.darkened(0.55)
		var nm := _label(it["name"], 13, col, mono)
		nm.tooltip_text = Tooltips.item(id)
		nm.mouse_filter = Control.MOUSE_FILTER_STOP
		hangar_grid.add_child(nm)
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


func _open_data() -> void:
	if not _overlay_open():
		data_ui.open()


func _overlay_open() -> bool:
	return profile_ui.visible or board_ui.visible or data_ui.visible


## No local run but a cloud copy: offer RESTORE. Answers later (network), so it re-checks that the title is still as it was.
func _refresh_cloud() -> void:
	restore_btn.visible = false
	for s in ["run", "daily"]:
		if Save.has_run(s):
			continue
		var meta := await CloudSave.peek(s)
		if meta.is_empty() or Save.has_run(s) or not visible:
			continue
		restore_slot = s
		restore_btn.text = "RESTORE %sFROM CLOUD  -  SAVED %s" % ["DAILY " if s == "daily" else "", str(meta.get("updated_at", "")).substr(0, 16).replace("T", " ")]
		restore_btn.visible = true
		return


func _restore() -> void:
	restore_btn.disabled = true
	var err := await CloudSave.restore(restore_slot)
	restore_btn.disabled = false
	if err != "":
		notice.text = err
		notice.visible = true
		return
	open() # the restored run shows as CONTINUE


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
	stats.text = "NO SERVICE RECORD. FIRST SORTIE." if m["runs"] == 0 else "SERVICE RECORD  sorties %d  rescued %d  kills %d  best day %d%s" % [m["runs"], m["total_rescued"], m["total_kills"], m["best_day"], "  victories %d" % m["victories"] if m["victories"] > 0 else ""]
	var h := Save.head() # an outdated run is discarded here and leaves Save.notice
	cont_btn.visible = not h.is_empty()
	if cont_btn.visible:
		var mins := int(h["time"] * 24 * 60)
		cont_btn.text = "CONTINUE  -  DAY %d  %02d:%02d  -  %d RESCUED" % [h["day"], mins / 60, mins % 60, h["rescued"]]
	var daily := Save.read_slot("daily")
	cont_daily_btn.visible = not daily.is_empty()
	if cont_daily_btn.visible:
		var practice: bool = not daily["systems"].get("online", {}).get("ranked", false)
		cont_daily_btn.text = "CONTINUE  DAY %d%s" % [daily["head"]["day"], "  (practice)" if practice else ""]
	start_btn.text = "NEW RUN" if cont_btn.visible else "CLEARED FOR TAKEOFF"
	notice.text = Save.notice
	notice.visible = notice.text != ""
	Save.notice = ""
	_refresh_online_notice()
	_refresh_setup()
	visible = true
	CloudSave.flush_pending()
	_refresh_cloud()
	_refresh_daily()


## Today's daily from the server (no seed before the start). Answers later, so it re-checks that the title is still open.
func _refresh_daily() -> void:
	daily_info = {}
	daily_lbl.text = "// DAILY  -  calling command..."
	var r: Dictionary = await Online.fetch_daily()
	if not visible:
		return
	if not r["ok"] or not r["data"] is Dictionary:
		daily_lbl.text = "// DAILY  -  needs the server: " + Online.error_text(r["error"])
		return
	daily_info = r["data"]
	daily_until = Time.get_ticks_msec() + int(daily_info.get("resets_in", 0)) * 1000
	_daily_text()


func _daily_text() -> void:
	var d := daily_info
	var names: Array = d["modifiers"].map(func(id): return Modifiers.TABLE.get(id, {"name": id})["name"])
	var left := maxi(0, (daily_until - Time.get_ticks_msec()) / 1000)
	var state := "played today: practice only" if d["played"] else "first start today is ranked" if Online.is_registered() else "register online to play it"
	daily_lbl.text = "// DAILY %s  -  SAME WORLD, SAME MODIFIERS
%s  +  %s  (x%.2f)
resets in %02d:%02d:%02d  -  %s" % [d["date"],
		HeliTypes.get_type(d["heli"])["name"], ", ".join(names) if not names.is_empty() else "no modifiers", Modifiers.factor(d["modifiers"]),
		left / 3600, left / 60 % 60, left % 60, state]


## DAILY: claim today's attempt on the server and reload into it (main.gd reads Online.daily_run). A saved daily is
## abandoned first (asks). Never offline: the seed comes from the server.
func _daily() -> void:
	if not visible or confirm.visible or _overlay_open() or daily_btn.disabled:
		return
	if not Save.read_slot("daily").is_empty():
		_ask("Abandon the saved daily run? It counts as lost.", func():
			_abandon_daily()
			_daily())
		return
	daily_btn.disabled = true
	var err := await Online.start_daily()
	daily_btn.disabled = false
	if err != "":
		notice.text = "DAILY: " + Online.error_text(err)
		notice.visible = true
		return
	visible = false
	get_tree().reload_current_scene()


func _abandon_daily() -> void:
	Save.slot = "daily"
	Save.abandon()
	Save.slot = "run"


func _continue_daily() -> void:
	if not visible or confirm.visible or _overlay_open():
		return
	Save.slot = "daily"
	Save.pending = true
	get_tree().reload_current_scene()


func _ask(text: String, on_ok: Callable) -> void:
	confirm.dialog_text = text
	_on_confirm = on_ok
	confirm.popup_centered()


func _process(delta: float) -> void:
	if not visible:
		return
	if not daily_info.is_empty() and int(t + delta) != int(t): # once a second
		if Time.get_ticks_msec() >= daily_until:
			_refresh_daily() # a new day
		else:
			_daily_text()
	t += delta
	rotor.rotation += 9.0 * delta
	hint.modulate.a = 1.0 if fmod(t, 1.2) < 0.8 else 0.15


func _input(event: InputEvent) -> void:
	if _overlay_open():
		return # typing a name must not trigger H / SPACE / ENTER here
	if visible and event.is_action_pressed("leaderboard"):
		_open_board()
	elif visible and event.is_action_pressed("hangar"):
		_toggle_hangar()
	elif visible and event.is_action_pressed("start"):
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
		_ask("Abandon the current run? It counts as lost.", func():
			Save.abandon()
			_start())
		return
	visible = false
	# delayed a few frames so this SPACE press is not also read as "take off" by the heli
	get_tree().create_timer(0.05).timeout.connect(start_pressed.emit)
