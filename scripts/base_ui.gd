extends CanvasLayer
## Base menu, shown while the heli sits on the pad, in the title screen's look (olive/black panels, sand text, yellow accent).
## Left: status column (population, stocks with per-day deltas, power, next assault), refreshed twice a second.
## Right: tabs BUILD (upgrades, buildings to place), WORKERS (jobs table), HANGAR (loadout, weapons, fitted items).
## While placing (base.placing) both give way to a compact build bar along the bottom edge (hotkeys 1-8, base.gd).
## buy(id) applies effects to Game directly.

const SAND := Color(0.91, 0.86, 0.71)
const DIM := Color(0.64, 0.6, 0.5)
const ACCENT := Color(0.96, 0.77, 0.18)
const PANEL := Color(0.06, 0.08, 0.04, 0.97)
const OLIVE := Color(0.33, 0.37, 0.2)
const BAD := Color(1.0, 0.45, 0.38)
const GOOD := Color(0.55, 0.85, 0.45)
const DARK_TEXT := Color(0.06, 0.07, 0.03)

# id -> [name, max level, scrap cost per level (x level+1), rescued required per level]
const UPGRADES := {
	"turrets": ["Turret", 4, 40, 0],
	"fuel": ["Fuel Depot", 3, 40, 0],
	"armory": ["Armory", 3, 40, 0],
	"workshop": ["Workshop", 4, 60, 0],
}
const UPGRADE_INFO := {"turrets": "+1 auto turret on the ring", "fuel": "+25 heli fuel, +200 depot", "armory": "+60 heli ammo, +400 store, +1 rifle/day",
	"workshop": "salvage processing; Lv 2/3/4 add heli slots", "repair": "patch the base hull"}
# placing tools in build bar order (hotkeys 1..8)
const BUILD_INFO := {"sandbag": "militia posts", "wire": "slows and cuts zombies", "barracks": "+4 beds", "clinic": "2 patient beds",
	"generator": "power, 10 fuel/day", "well": "+8 water/day", "watchtower": "post, +50 % reach", "demolish": "houses, hedges, fences for scrap"}
# loadout key -> [label, min, max]
const LOADOUT := {
	"seats": ["Seats (1 pt each)", 2, 8],
	"fuel_tank": ["Fuel tank +25 fuel/lv (2 pt)", 0, 3],
	"ammo_feed": ["Ammo feed +60 ammo/lv (2 pt)", 0, 3],
	"armor": ["Armour +15 %/lv (2 pt)", 0, 3],
}
const JOBS := {"fuel": ["Fuel", "+20 fuel/day"], "ammo": ["Ammo", "+40 ammo/day"], "repair": ["Repair", "+40 base hull/day"],
	"militia": ["Militia", "-3 % base damage, mans posts in assaults"], "farm": ["Farm", "+6 food/day"], "build": ["Build", "builds blueprints (sandbag 20 s)"],
	"medic": ["Medic", "20 free hull per landing, faster clinic"], "water": ["Water", "+15 water/day (river or lake in 40 m)"],
	"workshop": ["Workshop", "breaks down 12 salvage/day"]}
const PERSON_COLS := [14, 122, 82, 68, 78, 44, 100] # WORKERS list: pin mark, name, skill, trait, job, rate, pin selector
# status column stock rows: id -> [label, bar colour]
const STOCKS := {"fuel": ["fuel", Color(0.9, 0.75, 0.2)], "ammo": ["ammo", Color(0.7, 0.7, 0.7)], "food": ["food", Color(0.5, 0.75, 0.3)],
	"water": ["water", Color(0.35, 0.6, 0.9)], "medicine": ["medicine", Color(0.9, 0.35, 0.35)], "rifles": ["rifles", Color(0.6, 0.65, 0.35)],
	"scrap": ["scrap", Color(0.75, 0.5, 0.3)], "metal": ["metal", Color(0.55, 0.57, 0.6)], "parts": ["parts", Color(0.6, 0.55, 0.45)],
	"electronics": ["electr.", Color(0.4, 0.75, 0.7)]}
const Weapons := preload("res://scripts/weapons.gd")
const People := preload("res://scripts/people.gd")
const Wear := preload("res://scripts/wear.gd")

var mono := SystemFont.new()
var pop_label: Label
var morale_label: Label
var stock_rows := {} # id -> [fill ColorRect, value Label, delta Label]
var power_label: Label
var assault_label: Label
var status_t := 0.0
var tabs := {} # name -> content Control
var tab_btns := {} # name -> Button
var rows := {} # upgrade id or "repair" -> [name Label, pips HBox, Button]
var place_btns := {} # BUILD_INFO kind -> toggle Button
var perimeter_btn: Button
var status_panel: Control
var main_panel: Control
var build_bar: Control # bottom bar shown instead of the panels while placing
var collapsed := false # TAB or the toggle button: menu folded away, the door gun can fire from the pad
var toggle_btn: Button
var bar_btns := {} # BUILD_INFO kind -> toggle Button
var loadout_info: Label
var loadout_rows := {} # key -> value Label
var weapon_box: VBoxContainer
var wear_rows := {} # part -> [fill ColorRect, value Label, effect Label, repair Button]
var wear_msg: Label # why the last repair order was refused
var worker_info: Label
var job_rows := {} # job -> [count Label, - Button, + Button, note Label]
var worker_msg: Label # why the last + was refused, cleared after 3 s
var people_box: VBoxContainer # WORKERS tab: one row of people per job, idle, injured
var person_info: Label
var people_sort := "job" # People.view
var people_filter := "all"
var people_count: Label
var person_sel := -1 # id of the person shown in person_info


func _ready() -> void:
	layer = 10
	visible = false
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE # clicks between the panels place blueprints (base.gd)
	root.theme = _theme()
	add_child(root)
	# left status column
	var status := _panel(root, Vector2(10, 10), 280)
	status.add_child(_label("// FOB STATUS", 12, ACCENT, true))
	status.add_child(_label("FORWARD OPERATING BASE", 17))
	status.add_child(_label("POPULATION", 12, ACCENT, true))
	pop_label = _label("", 13, SAND, true)
	status.add_child(pop_label)
	morale_label = _label("", 13, SAND, true)
	morale_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_child(morale_label)
	status.add_child(_label("STOCK", 12, ACCENT, true))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	status.add_child(grid)
	for id in STOCKS:
		grid.add_child(_label(STOCKS[id][0], 12, DIM, true))
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(64, 6)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.color = Color(0, 0, 0, 0.6)
		grid.add_child(bar)
		var fill := ColorRect.new()
		fill.size = Vector2(0, 6)
		fill.color = STOCKS[id][1]
		bar.add_child(fill)
		var v := _label("", 12, SAND, true)
		v.custom_minimum_size.x = 72
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
		var d := _label("", 12, DIM, true)
		grid.add_child(d)
		stock_rows[id] = [fill, v, d]
	power_label = _label("", 13, SAND, true)
	status.add_child(power_label)
	assault_label = _label("", 13, SAND, true)
	status.add_child(assault_label)
	# right main panel: tab bar, content, instruction bar
	var main := _panel(root, Vector2(650, 10), 620)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	main.add_child(tab_row)
	for t in ["BUILD", "WORKERS", "HANGAR"]:
		var b := Button.new()
		b.text = t
		b.custom_minimum_size = Vector2(120, 34)
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(show_tab.bind(t))
		tab_row.add_child(b)
		tab_btns[t] = b
	var take_off := _label("[SPACE] take off", 12, DIM, true)
	take_off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_off.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tab_row.add_child(take_off)
	main.add_child(_rule())
	_build_tab(main)
	_workers_tab(main)
	_hangar_tab(main)
	status_panel = status.get_parent()
	main_panel = main.get_parent()
	toggle_btn = Button.new()
	toggle_btn.add_theme_font_override("font", mono)
	toggle_btn.add_theme_font_size_override("font_size", 13)
	toggle_btn.position = Vector2(300, 10) # in the gap between the status column (10-290) and the main panel (650+)
	toggle_btn.size = Vector2(140, 26)
	toggle_btn.pressed.connect(toggle)
	root.add_child(toggle_btn)
	# bottom build bar: one button per tool, centred, growing up from the bottom edge
	var bar := _panel(root, Vector2.ZERO, 0)
	build_bar = bar.get_parent()
	build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_bar.offset_left = 0
	build_bar.offset_right = 0
	build_bar.offset_top = -10
	build_bar.offset_bottom = -10
	build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_bar.mouse_filter = Control.MOUSE_FILTER_STOP # clicks on the bar never place blueprints underneath
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	for i in BUILD_INFO.size():
		var kind: String = BUILD_INFO.keys()[i]
		var t := _tool(kind)
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE # SPACE takes off, it must not click the bar
		b.custom_minimum_size = Vector2(96, 40)
		b.add_theme_font_override("font", mono)
		b.text = "%d %s\n%s" % [i + 1, t[0].to_upper(), "+scrap" if kind == "demolish" else "%d scrap" % t[1]]
		b.tooltip_text = BUILD_INFO[kind]
		b.toggled.connect(func(_on: bool):
			get_parent().place_kind = kind
			refresh())
		row.add_child(b)
		bar_btns[kind] = b
	bar.add_child(_label("LMB place  ·  RMB remove  ·  R rotate  ·  ESC done", 12, DIM, true))
	show_tab("BUILD")


func _process(delta: float) -> void:
	status_t -= delta
	if visible and status_t <= 0.0:
		status_t = 0.5
		_refresh_status()


## Shared look: olive buttons, yellow when pressed / toggled on, sand text.
func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 13
	th.set_color("font_color", "Label", SAND)
	th.set_stylebox("normal", "Button", _box(OLIVE.darkened(0.35), 4))
	th.set_stylebox("hover", "Button", _box(OLIVE.darkened(0.1), 4))
	th.set_stylebox("pressed", "Button", _box(ACCENT, 4))
	th.set_stylebox("hover_pressed", "Button", _box(ACCENT.lightened(0.15), 4))
	th.set_stylebox("disabled", "Button", _box(Color(0.1, 0.11, 0.07), 4))
	var focus := StyleBoxEmpty.new()
	th.set_stylebox("focus", "Button", focus)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		th.set_stylebox(st, "OptionButton", th.get_stylebox(st, "Button"))
	th.set_stylebox("panel", "PopupMenu", _box(PANEL, 4, ACCENT))
	th.set_stylebox("hover", "PopupMenu", _box(ACCENT, 2))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		th.set_color(c, "OptionButton", SAND)
	th.set_color("font_color", "PopupMenu", SAND)
	th.set_color("font_hover_color", "PopupMenu", DARK_TEXT)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		th.set_color(c, "Button", SAND)
	th.set_color("font_pressed_color", "Button", DARK_TEXT)
	th.set_color("font_hover_pressed_color", "Button", DARK_TEXT)
	th.set_color("font_disabled_color", "Button", SAND.darkened(0.55))
	th.set_stylebox("panel", "TooltipPanel", _box(Color(0.04, 0.05, 0.03, 0.95), 6, ACCENT))
	th.set_color("font_color", "TooltipLabel", SAND)
	return th


func _box(bg: Color, margin: float, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_content_margin_all(margin)
	sb.content_margin_left = margin + 4
	sb.content_margin_right = margin + 4
	if border.a > 0.0:
		sb.border_width_left = 2
		sb.border_color = border
	return sb


## Panel with the title screen's yellow top bar; returns its VBox.
func _panel(root: Control, pos: Vector2, width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.custom_minimum_size.x = width
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_width_top = 6
	sb.border_color = ACCENT
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	return v


func _label(text: String, size := 13, color := SAND, is_mono := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if is_mono:
		l.add_theme_font_override("font", mono)
	return l


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 2)
	r.color = OLIVE
	return r


func _build_tab(main: VBoxContainer) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	main.add_child(cols)
	tabs["BUILD"] = cols
	var up := VBoxContainer.new()
	up.custom_minimum_size.x = 250
	cols.add_child(up)
	up.add_child(_label("UPGRADES", 12, ACCENT, true))
	for id in UPGRADES.keys() + ["repair"]:
		var h := HBoxContainer.new()
		up.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 1)
		h.add_child(v)
		var top := HBoxContainer.new()
		v.add_child(top)
		var name := _label("", 14)
		top.add_child(name)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 3)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(pips)
		for i in (UPGRADES[id][1] if id != "repair" else 0):
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(8, 8)
			pips.add_child(pip)
		v.add_child(_label(UPGRADE_INFO[id], 11, DIM))
		var b := Button.new()
		b.custom_minimum_size = Vector2(84, 0)
		b.add_theme_font_override("font", mono)
		b.pressed.connect(buy.bind(id))
		h.add_child(b)
		rows[id] = [name, pips, b]
	var site := VBoxContainer.new()
	site.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(site)
	site.add_child(_label("BUILD ON THE MAP", 12, ACCENT, true))
	for kind in BUILD_INFO:
		var b := Button.new()
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggled.connect(func(on: bool):
			get_parent().place_kind = kind
			get_parent().placing = on)
		site.add_child(b)
		place_btns[kind] = b
	perimeter_btn = Button.new()
	perimeter_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	perimeter_btn.pressed.connect(func(): get_parent().expand_perimeter())
	site.add_child(perimeter_btn)


func _workers_tab(main: VBoxContainer) -> void:
	var v := VBoxContainer.new()
	main.add_child(v)
	tabs["WORKERS"] = v
	worker_info = _label("", 13, SAND, true)
	v.add_child(worker_info)
	# two jobs per table row: label - n + note, twice (hover a job name for its effect)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	v.add_child(grid)
	for j in JOBS:
		var name := _label(JOBS[j][0], 14)
		name.custom_minimum_size.x = 58
		name.tooltip_text = JOBS[j][1]
		name.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(name)
		var r := []
		var n := _label("", 14, SAND, true)
		n.custom_minimum_size.x = 22
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for d in [-1, 1]:
			var b := Button.new()
			b.text = "-" if d < 0 else "+"
			b.custom_minimum_size = Vector2(26, 24)
			b.pressed.connect(_adjust_worker.bind(j, d))
			grid.add_child(b)
			r.append(b)
			if d < 0:
				grid.add_child(n)
		var note := _label("", 12, DIM, true)
		note.custom_minimum_size.x = 108
		grid.add_child(note)
		job_rows[j] = [n, r[0], r[1], note]
	var bar := HBoxContainer.new()
	v.add_child(bar)
	var unassign := Button.new()
	unassign.text = "Unassign all"
	unassign.pressed.connect(unassign_all)
	bar.add_child(unassign)
	worker_msg = _label("", 13, BAD)
	bar.add_child(worker_msg)
	v.add_child(_rule())
	# people list: show / sort, then one row per person
	var ctl := HBoxContainer.new()
	ctl.add_theme_constant_override("separation", 6)
	v.add_child(ctl)
	ctl.add_child(_label("SHOW", 12, ACCENT, true))
	var filters := [["All", "all"], ["Idle", "idle"], ["Injured", "injured"], ["Pinned", "pinned"]]
	filters += JOBS.keys().map(func(j): return ["Job: " + JOBS[j][0], "job:" + j])
	filters += People.SKILL_JOBS.keys().map(func(k): return ["Skill: " + k.capitalize(), "skill:" + k])
	ctl.add_child(_picker(filters, func(val: String): people_filter = val; _refresh_people()))
	ctl.add_child(_label("SORT", 12, ACCENT, true))
	ctl.add_child(_picker([["Job", "job"], ["Name", "name"], ["Skill", "skill"], ["Level", "level"]], func(val: String): people_sort = val; _refresh_people()))
	people_count = _label("", 12, DIM, true)
	ctl.add_child(people_count)
	person_info = _label("", 12, SAND, true)
	v.add_child(person_info)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	v.add_child(head)
	for i in PERSON_COLS.size():
		var h := _label(["", "NAME", "SKILL", "TRAIT", "WORKS AS", "RATE", "PIN TO"][i], 11, ACCENT, true)
		h.custom_minimum_size.x = PERSON_COLS[i]
		head.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	people_box = VBoxContainer.new()
	people_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	people_box.add_theme_constant_override("separation", 2)
	scroll.add_child(people_box)


## OptionButton over [text, value] pairs; `on_pick` gets the value.
func _picker(items: Array, on_pick: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE # SPACE takes off
	o.add_theme_font_size_override("font_size", 12)
	for i in items.size():
		o.add_item(items[i][0])
		o.set_item_metadata(i, items[i][1])
	o.item_selected.connect(func(i: int): on_pick.call(o.get_item_metadata(i)))
	return o


func _hangar_tab(main: VBoxContainer) -> void:
	var v := VBoxContainer.new()
	main.add_child(v)
	tabs["HANGAR"] = v
	v.add_child(_label("LOADOUT", 12, ACCENT, true))
	loadout_info = _label("", 13, SAND, true)
	v.add_child(loadout_info)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)
	for k in LOADOUT:
		var name := _label(LOADOUT[k][0], 13)
		name.custom_minimum_size.x = 260
		grid.add_child(name)
		for d in [-1, 1]:
			var b := Button.new()
			b.text = "-" if d < 0 else "+"
			b.custom_minimum_size = Vector2(28, 26)
			b.pressed.connect(_adjust_loadout.bind(k, d))
			grid.add_child(b)
			if d < 0:
				loadout_rows[k] = _label("", 14, SAND, true)
				loadout_rows[k].custom_minimum_size.x = 26
				loadout_rows[k].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				grid.add_child(loadout_rows[k])
	v.add_child(_label("HELI CONDITION  (wear in flight and from hits; repairs run while the heli sits on the pad)", 12, ACCENT, true))
	var wgrid := GridContainer.new()
	wgrid.columns = 5
	wgrid.add_theme_constant_override("h_separation", 8)
	v.add_child(wgrid)
	for c in Wear.COMPONENTS:
		var name := _label(Wear.NAMES[c], 13)
		name.custom_minimum_size.x = 84
		wgrid.add_child(name)
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(120, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.color = Color(0, 0, 0, 0.6)
		wgrid.add_child(bar)
		var fill := ColorRect.new()
		fill.size = Vector2(0, 8)
		bar.add_child(fill)
		var val := _label("", 13, SAND, true)
		val.custom_minimum_size.x = 44
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		wgrid.add_child(val)
		var note := _label("", 12, DIM, true)
		note.custom_minimum_size.x = 100
		wgrid.add_child(note)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE # SPACE takes off, it must not click the button
		b.custom_minimum_size = Vector2(150, 26)
		b.add_theme_font_override("font", mono)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_order_repair.bind(c))
		wgrid.add_child(b)
		wear_rows[c] = [fill, val, note, b]
	wear_msg = _label("", 12, BAD, true)
	v.add_child(wear_msg)
	weapon_box = VBoxContainer.new()
	v.add_child(weapon_box)


func _order_repair(part: String) -> void:
	wear_msg.text = Game.world.wear.order_repair(part)
	_refresh_wear()


## The four condition bars and their repair buttons (also on the status tick, the repairs progress).
func _refresh_wear() -> void:
	var wear: Node = Game.world.wear
	for c in Wear.COMPONENTS:
		var r: Array = wear_rows[c]
		var v: float = wear.cond[c]
		r[0].size.x = 120.0 * v / 100.0
		r[0].color = GOOD if v >= Wear.LOW_BELOW else (ACCENT if v >= Wear.FAIL_BELOW else BAD)
		r[1].text = "%d %%" % ceili(v)
		r[2].text = "may fail!" if c == "engine" and v < Wear.FAIL_BELOW else (Wear.EFFECTS[c] if v < Wear.LOW_BELOW else "")
		r[2].add_theme_color_override("font_color", BAD if r[2].text == "may fail!" else DIM)
		var on: bool = wear.orders.has(c)
		r[3].text = "working... (cancel)" if on else ("Repair %d parts" % wear.repair_cost(c) if v < 100.0 else "like new")
		r[3].disabled = v >= 100.0 and not on
		r[3].tooltip_text = "~%d s with the repair crew; parts: %d" % [wear.repair_seconds(c), Game.salvage["parts"]] if v < 100.0 else ""


func show_tab(tab: String) -> void:
	for t in tabs:
		tabs[t].visible = t == tab
		var sb := _box(OLIVE.darkened(0.2) if t == tab else Color(0.1, 0.12, 0.07), 4)
		sb.border_width_bottom = 4 if t == tab else 0
		sb.border_color = ACCENT
		for s in ["normal", "hover", "pressed", "hover_pressed"]:
			tab_btns[t].add_theme_stylebox_override(s, sb)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			tab_btns[t].add_theme_color_override(c, ACCENT if t == tab else DIM)


func open() -> void:
	visible = true
	collapsed = false
	Game.world.ui_open = true
	refresh()


## Fold the menu away (heli stays on the pad) or bring it back.
func toggle() -> void:
	collapsed = not collapsed
	Game.world.ui_open = not collapsed
	if collapsed:
		get_parent().placing = false # refreshes
	else:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		toggle()
		get_viewport().set_input_as_handled()


func close() -> void:
	visible = false
	Game.world.ui_open = false
	get_parent().placing = false


## [name, scrap, build seconds] of a BUILD_INFO tool.
func _tool(kind: String) -> Array:
	match kind:
		"sandbag": return ["Sandbags", Game.SANDBAG_COST, Game.BUILD_SECONDS]
		"wire": return ["Barbed wire", Game.WIRE_COST, Game.BUILD_SECONDS]
		"demolish": return ["Demolish", 0, 0]
	return Game.BUILDINGS[kind].slice(0, 3)


func cost(id: String) -> int:
	if id == "repair":
		return maxi(1, ceili((Game.max_base_hp - Game.base_hp) / 10.0))
	return UPGRADES[id][2] * (Game.base_level.get(id, 0) + 1)


func can_buy(id: String) -> bool:
	return _buy_refusal(id) == ""


## Why `id` cannot be bought right now, "" if it can.
func _buy_refusal(id: String) -> String:
	if id == "repair" and Game.base_hp >= Game.max_base_hp:
		return "the base hull is intact"
	if id != "repair":
		var lvl: int = Game.base_level.get(id, 0)
		if lvl >= UPGRADES[id][1]:
			return "maximum level"
		if Game.rescued < UPGRADES[id][3] * (lvl + 1):
			return "needs %d rescued" % (UPGRADES[id][3] * (lvl + 1))
	if Game.scrap < cost(id):
		return "needs %d scrap, you have %d" % [cost(id), Game.scrap]
	return ""


## Population, stocks with per-day change, power, next assault.
func _refresh_status() -> void:
	var base: Node2D = get_parent()
	var w: Dictionary = Game.workers
	var eff := Game.work_eff()
	var rate: Dictionary = Game.WORKER_RATE
	var eaters: int = Game.rescued + Game.campers()
	pop_label.text = "rescued %3d   beds    %3d\ncamping %3d   injured %3d\nidle    %3d   assigned%3d" % [
		Game.rescued, Game.housing(), Game.campers(), Game.injured, Game.idle_workers(), Game.assigned()]
	var morale: Node = Game.world.morale
	morale_label.text = "MORALE  " + morale.summary()
	morale_label.add_theme_color_override("font_color", BAD if morale.value < morale.LOW_BELOW else (GOOD if morale.value > morale.HIGH_ABOVE else SAND))
	var gen: float = Game.built("generator") * Game.GEN_FUEL
	# id -> [value, bar full at, per day (null: unknown), show cap]
	var s := {
		"fuel": [Game.base_fuel, Game.base_fuel_cap, Game.crew("fuel") * rate["fuel"] * eff - gen, true],
		"ammo": [Game.base_ammo, Game.base_ammo_cap, Game.crew("ammo") * rate["ammo"] * eff, true],
		"food": [Game.base_food, maxf(10.0, eaters * 10.0), Game.crew("farm") * rate["farm"] * eff + Game.FIELD_FOOD * base.field_cells().size() - Game.food_eaters() * Game.FOOD_PER_PERSON, false],
		"water": [Game.base_water, maxf(10.0, eaters * 10.0), Game.crew("water") * rate["water"] * eff + Game.built("well") * Game.WELL_WATER - eaters * Game.WATER_PER_PERSON, false],
		"medicine": [Game.base_medicine, 10.0, null, false],
		"rifles": [Game.base_rifles, maxf(10.0, w["militia"]), float(Game.base_level.get("armory", 0)), false],
		"scrap": [Game.scrap, 200.0, null, false],
		"metal": [Game.salvage["metal"], 60.0, null, false],
		"parts": [Game.salvage["parts"], 60.0, null, false],
		"electronics": [Game.salvage["electronics"], 60.0, null, false],
	}
	for id in s:
		var r: Array = stock_rows[id]
		var v: Array = s[id]
		r[0].size.x = 64.0 * clampf(v[0] / v[1], 0.0, 1.0)
		r[1].text = ("%d/%d" % [v[0], v[1]]) if v[3] else "%d" % v[0]
		r[2].text = "" if v[2] == null else "%+.0f/d" % v[2]
		r[2].add_theme_color_override("font_color", DIM if v[2] == null or absf(v[2]) < 0.5 else (GOOD if v[2] > 0 else BAD))
	power_label.text = "POWER    %s" % ("ON  (gen fuel %d/day)" % gen if Game.power else ("OFF (generator has no fuel)" if gen > 0.0 else "OFF (no generator)"))
	power_label.add_theme_color_override("font_color", GOOD if Game.power else DIM)
	assault_label.text = "ASSAULT  %s" % _assault_eta()
	assault_label.add_theme_color_override("font_color", BAD if Game.attack_active or Game.attack_pending else SAND)
	_refresh_wear()


## "UNDER ATTACK", or in-game hours until the next assault (time 0.8 of every third day).
func _assault_eta() -> String:
	if Game.attack_active:
		return "UNDER ATTACK"
	var d: int = Game.day + Game.days_to_assault()
	if d == Game.day and Game.time >= 0.8 and not Game.attack_pending:
		d += Game.ATTACK_EVERY_DAYS
	var hours := ((d - Game.day) + 0.8 - Game.time) * 24.0
	return "%s, in %dh" % ["TONIGHT" if d == Game.day else "day %d" % d, ceili(hours)]


func refresh() -> void:
	var base: Node2D = get_parent()
	_refresh_status()
	# BUILD
	for id in rows:
		var r: Array = rows[id]
		var lvl: int = Game.base_level.get(id, 0)
		var why := _buy_refusal(id)
		if id == "repair":
			r[0].text = "Repair base  %d/%d " % [Game.base_hp, Game.max_base_hp]
			r[2].text = "Fix %d" % cost(id)
		else:
			r[0].text = UPGRADES[id][0] + " "
			for i in r[1].get_child_count():
				r[1].get_child(i).color = ACCENT if i < lvl else Color(0.2, 0.22, 0.14)
			r[2].text = "MAX" if lvl >= UPGRADES[id][1] else "Buy %d" % cost(id)
		r[2].disabled = why != ""
		r[2].tooltip_text = why
	for kind in place_btns:
		var b: Button = place_btns[kind]
		var on: bool = base.placing and base.place_kind == kind
		b.set_pressed_no_signal(on)
		var t := _tool(kind)
		var pieces: Array = Game.sandbags.values().filter(func(s): return s["kind"] == kind)
		var built: int = pieces.filter(func(s): return s["built"]).size() if kind in ["sandbag", "wire"] else Game.built(kind)
		var plan: int = pieces.size() - built if kind in ["sandbag", "wire"] else Game.buildings.filter(func(s): return s["kind"] == kind and not s["built"]).size()
		b.text = "%s%s  -  %s\n%d scrap  %d s   built %d  planned %d" % ["> " if on else "", t[0].to_upper(), BUILD_INFO[kind], t[1], t[2], built, plan]
		if kind == "demolish":
			b.text = "%sDEMOLISH  -  %s\n%d orders" % ["> " if on else "", BUILD_INFO[kind], base.demolitions.size()]
		b.disabled = Game.scrap < t[1] and not on
		b.tooltip_text = "needs %d scrap, you have %d" % [t[1], Game.scrap] if b.disabled else "click, then click inside the fence to place"
		bar_btns[kind].set_pressed_no_signal(base.place_kind == kind)
		bar_btns[kind].disabled = Game.scrap < t[1] and base.place_kind != kind
	var plvl: int = base.perimeter_level()
	var busy: bool = not base.next_site("perimeter").is_empty()
	perimeter_btn.text = "EXPAND PERIMETER  -  %d m to %d m\n%d scrap  60 s   level %d/%d%s" % [
		Game.base_radius / 10.0, (Game.base_radius + Game.PERIMETER_STEP) / 10.0, base.building_cost("perimeter"), plvl, Game.PERIMETER_MAX, "   building..." if busy else ""]
	perimeter_btn.disabled = plvl >= Game.PERIMETER_MAX or busy or Game.scrap < base.building_cost("perimeter")
	perimeter_btn.tooltip_text = "maximum level" if plvl >= Game.PERIMETER_MAX else ("the current stage is still being built" if busy \
		else ("needs %d scrap, you have %d" % [base.building_cost("perimeter"), Game.scrap] if perimeter_btn.disabled else "Build workers put up the next fence ring"))
	status_panel.visible = not base.placing and not collapsed
	main_panel.visible = not base.placing and not collapsed
	build_bar.visible = base.placing and not collapsed
	toggle_btn.text = "BASE MENU [TAB]" if collapsed else "HIDE MENU [TAB]"
	# HANGAR
	loadout_info.text = "weight %d/%d pts (over 8: -4 %% speed each)  speed x%.2f\nseats %d  fuel %d  ammo %d  armour x%.2f" % [
		Game.loadout_points(), Game.loadout_budget, Game.weight_factor, Game.seats, Game.max_fuel, Game.max_ammo, Game.stats["armor"]]
	for k in LOADOUT:
		loadout_rows[k].text = str(Game.loadout[k])
	_refresh_weapons()
	# WORKERS
	worker_info.text = "population %d  beds %d  camping %d (work at 50 %%)\ninjured %d  assigned %d  idle %d" % [
		Game.rescued, Game.housing(), Game.campers(), Game.injured, Game.assigned(), Game.idle_workers()]
	for j in JOBS:
		var r: Array = job_rows[j]
		r[0].text = str(Game.workers[j])
		r[1].disabled = Game.workers[j] <= Game.pinned(j)
		r[1].tooltip_text = "%d pinned here: unpin them first" % Game.pinned(j) if r[1].disabled and Game.pinned(j) > 0 else ""
		var why := worker_refusal(j, Game.workers[j] + 1)
		r[2].modulate = Color(1, 1, 1, 0.35) if why != "" else Color.WHITE # greyed but clickable: a click shows why
		r[2].tooltip_text = why
		var note := ""
		var bad := false
		match j:
			"militia":
				note = "rifles %d" % Game.base_rifles
				bad = Game.workers[j] > int(Game.base_rifles)
			"water":
				bad = not base.water_near()
				note = "no water near" if bad else ""
			"workshop":
				bad = Game.base_level.get("workshop", 0) < 1
				note = "needs Workshop" if bad else "salvage %d" % (Game.salvage["metal"] + Game.salvage["parts"] + Game.salvage["electronics"])
			"build":
				note = "%d blueprints" % (Game.sandbags.values().filter(func(s): return not s["built"]).size() + Game.buildings.filter(func(b): return not b["built"]).size() + base.demolitions.size())
			"medic":
				note = "clinic beds %d" % (2 * Game.built("clinic"))
		r[3].text = note
		r[3].add_theme_color_override("font_color", BAD if bad else DIM)
	_refresh_people()


## One row per person (filtered and sorted): name, skill, trait, job (green: good at it), work rate, and the pin selector. A click on the name shows the person.
func _refresh_people() -> void:
	Game.assign_jobs()
	for c in people_box.get_children():
		people_box.remove_child(c) # a person button may be mid-signal, so no free()
		c.queue_free()
	var here: Array = Game.people.filter(func(p): return not p["aboard"] and p.get("post", "") == "")
	var shown := People.view(here, people_sort, people_filter)
	people_count.text = "%d of %d" % [shown.size(), here.size()]
	for p in shown:
		people_box.add_child(_person_row(p))
	_show_person()


func _person_row(p: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var pin: String = p.get("pin", "")
	var job: String = p["job"]
	var fit := job != "" and People.matches(p, job)
	var cells := [
		["*" if pin != "" else "", ACCENT],
		[p["name"], SAND],
		["%s %s" % [p["skill"].capitalize(), "★".repeat(p["skill_lv"])], GOOD if fit else SAND],
		[p["trait"].capitalize() if p["trait"] != "" else "-", DIM],
		["injured" if p["injured"] else (JOBS[job][0] if job != "" else "idle"), BAD if p["injured"] else (GOOD if fit else (SAND if job != "" else DIM))],
		["x%.2f" % People.rate(p, Game.is_night()) if job != "" else "-", GOOD if fit else DIM]]
	for i in cells.size():
		var l: Control
		if i == 1:
			l = Button.new() # flat name button: click for details
			l.text = cells[i][0]
			l.flat = true
			l.alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.clip_text = true
			l.focus_mode = Control.FOCUS_NONE
			l.pressed.connect(func(): person_sel = p["id"]; _show_person())
		else:
			l = Label.new()
			l.text = cells[i][0]
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.custom_minimum_size.y = 24
		l.add_theme_font_override("font", mono)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", cells[i][1])
		l.custom_minimum_size.x = PERSON_COLS[i]
		row.add_child(l)
	if pin != "":
		row.get_child(0).tooltip_text = "pinned: stays on this job (injured: off duty until healed)"
		row.get_child(0).mouse_filter = Control.MOUSE_FILTER_STOP
	var sel := _picker([["Auto", ""]] + JOBS.keys().map(func(j): return [JOBS[j][0], j]), func(val: String): pin_person(p["id"], val))
	sel.selected = 0 if pin == "" else 1 + JOBS.keys().find(pin)
	sel.custom_minimum_size = Vector2(PERSON_COLS[6], 22)
	sel.tooltip_text = "Pin to a job (Auto: assigned by skill)"
	row.add_child(sel)
	return row


func _show_person() -> void:
	var sel: Array = Game.people.filter(func(p): return p["id"] == person_sel)
	person_info.text = People.describe(sel[0], int(Game.world.morale.value), Game.day) if not sel.is_empty() \
		else "click a name for details; green = the job fits the skill\n"


func _refresh_weapons() -> void:
	for c in weapon_box.get_children():
		weapon_box.remove_child(c) # a Stow/Mount button may be mid-signal, so no free()
		c.queue_free()
	weapon_box.add_child(_rule())
	weapon_box.add_child(_label("WEAPONS  hardpoints %d/%d  (X switches in flight)" % [Game.heli_weapons.size(), Game.slots["hardpoint"]], 12, ACCENT, true))
	for id in Game.heli_weapons:
		_weapon_row("HELI  %s Lv %d%s" % [Weapons.TABLE[id]["name"], Progression.level(id), "  (equipped)" if id == Game.weapon else ""], "Stow", "the heli needs one gun" if Game.heli_weapons.size() < 2 else "", stow.bind(id))
	for id in Game.weapon_bay:
		_weapon_row("BAY   %s Lv %d" % [Weapons.TABLE[id]["name"], Progression.level(id)], "Mount", "no free hardpoint" if Game.heli_weapons.size() >= Game.slots["hardpoint"] else "", mount.bind(id))
	_refresh_items()


## Fitted systems and modules with a scrap button; Workshop levels buy the extra slots.
func _refresh_items() -> void:
	weapon_box.add_child(_label("FITTED  systems %d/%d  modules %d/%d" % [
		Progression.used("system"), Game.slots["system"], Progression.used("module"), Game.slots["module"]], 12, ACCENT, true))
	weapon_box.add_child(_label("Workshop 2/3/4 adds a hardpoint / system / module slot. Scrapping refunds half the cards.", 11, DIM))
	for id in Game.heli_items:
		if Progression.ITEMS[id]["slot"] != "hardpoint":
			var lv: int = Game.heli_items[id]
			_weapon_row("%s  %s Lv %d" % [Progression.ITEMS[id]["slot"].substr(0, 3).to_upper(), Progression.ITEMS[id]["name"], lv],
				"Scrap +%d" % (lv * Progression.CARD_SCRAP / 2), "", func(): Game.scrap_item(id); refresh())


## Row with a button; `refusal` != "" disables it and is shown on hover.
func _weapon_row(text: String, btn: String, refusal: String, cb: Callable) -> void:
	var h := HBoxContainer.new()
	weapon_box.add_child(h)
	var l := _label(text, 13, SAND, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var b := Button.new()
	b.text = btn
	b.custom_minimum_size.x = 96
	b.disabled = refusal != ""
	b.tooltip_text = refusal
	b.pressed.connect(cb)
	h.add_child(b)


func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	Game.scrap -= cost(id)
	if id == "repair":
		Game.base_hp = Game.max_base_hp
	else:
		Game.base_level[id] = Game.base_level.get(id, 0) + 1
	match id:
		"turrets":
			get_parent().rebuild()
		"fuel":
			Game.base_max_fuel += 25.0
			Game.base_fuel_cap += 200.0
		"armory":
			Game.base_max_ammo += 60
			Game.base_ammo_cap += 400.0
		"workshop": # extra hardpoint/system/module slot per level, see Progression.apply_all
			Game.loadout_budget += 1
	Game.recompute()
	get_parent().resupply()
	refresh()
	return true


## Loadout changes are free but only while landed at base (this menu is open).
func set_loadout(key: String, lvl: int) -> bool:
	var cur: int = Game.loadout[key]
	if lvl < LOADOUT[key][1] or lvl > LOADOUT[key][2]:
		return false
	if Game.loadout_points() + (lvl - cur) * Game.LOADOUT_COST[key] > Game.loadout_budget:
		return false
	Game.loadout[key] = lvl
	Game.recompute()
	get_parent().resupply()
	refresh()
	return true


func _adjust_loadout(key: String, d: int) -> void:
	set_loadout(key, Game.loadout[key] + d)


func stow(id: String) -> void:
	if Game.heli_weapons.size() < 2 or id not in Game.heli_weapons:
		return
	Game.heli_weapons.erase(id)
	Game.weapon_bay.append(id)
	if Game.weapon == id:
		Game.weapon = Game.heli_weapons[0]
	Game.recompute()
	get_parent().resupply()
	refresh()


func mount(id: String) -> void:
	if Game.heli_weapons.size() >= Game.slots["hardpoint"] or id not in Game.weapon_bay:
		return
	Game.weapon_bay.erase(id)
	Game.heli_weapons.append(id)
	refresh()


## Why `job` cannot have `n` workers, "" if it can. `freed`: seats the change frees elsewhere (a pin moves a worker over).
func worker_refusal(job: String, n: int, freed := 0) -> String:
	var cur: int = Game.workers[job]
	if n < 0:
		return "nobody on that job"
	if n < Game.pinned(job):
		return "%d pinned here: unpin them first" % Game.pinned(job)
	if n - cur > Game.idle_workers() + freed:
		return "no idle people"
	if n > cur and job == "water" and not get_parent().water_near():
		return "no water within 40 m"
	if n > cur and job == "workshop" and Game.base_level.get("workshop", 0) < 1:
		return "needs the Workshop upgrade (BUILD tab)"
	return ""


func _say(why: String) -> void:
	worker_msg.text = why
	get_tree().create_timer(3.0).timeout.connect(func(): if worker_msg.text == why: worker_msg.text = "")


func set_worker(job: String, n: int) -> bool:
	var why := worker_refusal(job, n)
	if why != "":
		_say(why)
		return false
	Game.workers[job] = n
	refresh()
	return true


## Pins person `id` to `job` ("" = auto again). The job's count rises to cover them (the seat they held on another job moves
## over); refused like a + when that job cannot take one more. An injured pinned person keeps the pin but is off duty.
func pin_person(id: int, job: String) -> bool:
	var found: Array = Game.people.filter(func(q): return q["id"] == id)
	if found.is_empty():
		return false
	var p: Dictionary = found[0]
	var old: String = p.get("pin", "")
	Game.assign_jobs()
	var held: String = p["job"]
	p["pin"] = job
	if job != "" and not p["injured"] and Game.workers[job] < Game.pinned(job):
		var why := worker_refusal(job, Game.workers[job] + 1, 1 if held != "" else 0)
		if why != "":
			p["pin"] = old
			_say(why)
			refresh()
			return false
		Game.workers[job] += 1
		if held != "" and held != job:
			Game.workers[held] -= 1
	refresh()
	return true


func unassign_all() -> void:
	for k in Game.workers:
		Game.workers[k] = 0
	for p in Game.people:
		p["pin"] = ""
	refresh()


func _adjust_worker(job: String, d: int) -> void:
	set_worker(job, Game.workers[job] + d)
