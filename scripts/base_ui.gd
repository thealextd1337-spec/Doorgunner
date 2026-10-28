extends CanvasLayer
## Base menu, shown while the heli sits on the pad. Tabs: BUILD (upgrades), HANGAR (loadout, weapons), WORKERS (jobs).
## buy(id) applies effects to Game directly.

# id -> [name, max level, scrap cost per level (x level+1), rescued required per level]
const UPGRADES := {
	"turrets": ["Turret", 4, 40, 0],
	"fuel": ["Fuel Depot", 3, 40, 0],
	"armory": ["Armory", 3, 40, 0],
	"workshop": ["Workshop", 3, 60, 0],
}
const UPGRADE_INFO := {"workshop": "+ enables salvage processing"}
const BUILD_INFO := {"barracks": "+4 beds", "clinic": "2 beds for the injured", "generator": "power, 10 fuel/day",
	"well": "+8 water/day", "watchtower": "militia post, +50 % reach"}
# loadout key -> [label, min, max]
const LOADOUT := {
	"seats": ["Seats (1 pt each)", 2, 8],
	"fuel_tank": ["Fuel tank +25 fuel/lv (2 pt)", 0, 3],
	"ammo_feed": ["Ammo feed +60 ammo/lv (2 pt)", 0, 3],
	"armor": ["Armour +15 %/lv (2 pt)", 0, 3],
}
const JOBS := {"fuel": "Fuel +20/day", "ammo": "Ammo +40/day", "repair": "Repair +40 hp/day", "militia": "Militia -3 % dmg, mans posts in assaults", "farm": "Farm +6 food/day",
	"build": "Build: sandbags (20 s) and buildings", "medic": "Medic: 20 hull per landing, faster clinic", "water": "Water +15/day (river or lake within 40 m)",
	"workshop": "Workshop: breaks down salvage, 12/day each (needs Workshop)"}
const Weapons := preload("res://scripts/weapons.gd")

var header: Label
var rows := {} # id -> [Label, Button]
var repair_btn: Button
var place_btn: Button
var place_btns := {} # "sandbag" or building kind -> toggle Button
var site_rows := {} # building kind or "perimeter" -> Label
var perimeter_btn: Button
var tabs := {} # name -> VBoxContainer
var loadout_rows := {} # key -> Label
var loadout_info: Label
var weapon_box: VBoxContainer
var job_rows := {} # job -> Label, its - and + buttons are the next siblings
var worker_info: Label
var worker_msg: Label # why the last + was refused, cleared after 3 s


func _ready() -> void:
	layer = 10
	visible = false
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.05, 0.9)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-400, 10)
	panel.size = Vector2(390, 100)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN # wide rows push it left, not off screen
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "FORWARD OPERATING BASE"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	header = Label.new()
	header.add_theme_font_size_override("font_size", 13)
	box.add_child(header)
	var tab_row := HBoxContainer.new()
	box.add_child(tab_row)
	for t in ["BUILD", "HANGAR", "WORKERS"]:
		var b := Button.new()
		b.text = t
		b.pressed.connect(show_tab.bind(t))
		tab_row.add_child(b)
		tabs[t] = VBoxContainer.new()
		box.add_child(tabs[t])
	for id in UPGRADES:
		rows[id] = _row(tabs["BUILD"], id)
	rows["repair"] = _row(tabs["BUILD"], "repair")
	repair_btn = rows["repair"][1]
	place_btn = _place_toggle(tabs["BUILD"], "sandbag")
	for kind in BUILD_INFO:
		var h := HBoxContainer.new()
		tabs["BUILD"].add_child(h)
		site_rows[kind] = _lbl(h)
		_place_toggle(h, kind).custom_minimum_size.x = 80
	var ph := HBoxContainer.new()
	tabs["BUILD"].add_child(ph)
	site_rows["perimeter"] = _lbl(ph)
	perimeter_btn = Button.new()
	perimeter_btn.custom_minimum_size.x = 80
	perimeter_btn.pressed.connect(func(): get_parent().expand_perimeter())
	ph.add_child(perimeter_btn)
	loadout_info = Label.new()
	loadout_info.add_theme_font_size_override("font_size", 13)
	tabs["HANGAR"].add_child(loadout_info)
	for k in LOADOUT:
		loadout_rows[k] = _pm_row(tabs["HANGAR"], _adjust_loadout, k)
	weapon_box = VBoxContainer.new()
	tabs["HANGAR"].add_child(weapon_box)
	worker_info = _wrap_lbl(tabs["WORKERS"])
	worker_msg = _wrap_lbl(tabs["WORKERS"])
	worker_msg.modulate = Color(1, 0.5, 0.4)
	for j in JOBS:
		job_rows[j] = _pm_row(tabs["WORKERS"], _adjust_worker, j)
	var unassign := Button.new()
	unassign.text = "Unassign all"
	unassign.pressed.connect(unassign_all)
	tabs["WORKERS"].add_child(unassign)
	var hint := Label.new()
	hint.text = "[SPACE] take off closes this menu"
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)
	show_tab("BUILD")


func _row(box: VBoxContainer, id: String) -> Array:
	var h := HBoxContainer.new()
	box.add_child(h)
	var l := _lbl(h)
	var b := Button.new()
	b.custom_minimum_size.x = 80
	b.pressed.connect(buy.bind(id))
	h.add_child(b)
	return [l, b]


## Toggle button for the base's placement mode with `kind` ("sandbag" or a building).
func _place_toggle(parent: Control, kind: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", 13)
	b.toggled.connect(func(on: bool):
		get_parent().place_kind = kind
		get_parent().placing = on)
	parent.add_child(b)
	place_btns[kind] = b
	return b


## Label with - and + buttons; cb(key, -1 / +1) on press.
func _pm_row(box: VBoxContainer, cb: Callable, key: String) -> Label:
	var h := HBoxContainer.new()
	box.add_child(h)
	var l := _lbl(h)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "-" if d < 0 else "+"
		b.custom_minimum_size.x = 30
		b.pressed.connect(cb.bind(key, d))
		h.add_child(b)
	return l


func _lbl(h: HBoxContainer) -> Label:
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 13)
	h.add_child(l)
	return l


func _wrap_lbl(box: VBoxContainer) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 360
	l.add_theme_font_size_override("font_size", 13)
	box.add_child(l)
	return l


func show_tab(tab: String) -> void:
	for t in tabs:
		tabs[t].visible = t == tab


func open() -> void:
	visible = true
	Game.world.ui_open = true
	refresh()


func close() -> void:
	visible = false
	Game.world.ui_open = false
	get_parent().placing = false


func cost(id: String) -> int:
	if id == "repair":
		return maxi(1, ceili((Game.max_base_hp - Game.base_hp) / 10.0))
	return UPGRADES[id][2] * (Game.base_level.get(id, 0) + 1)


func can_buy(id: String) -> bool:
	if Game.scrap < cost(id):
		return false
	if id == "repair":
		return Game.base_hp < Game.max_base_hp
	var lvl: int = Game.base_level.get(id, 0)
	return lvl < UPGRADES[id][1] and Game.rescued >= UPGRADES[id][3] * (lvl + 1)


func refresh() -> void:
	var base: Node2D = get_parent()
	var eaters: int = Game.rescued + Game.campers()
	header.text = "Scrap: %d   Rescued: %d   Beds: %d   Camping: %d   Injured: %d   Idle: %d\nStock  fuel %d/%d   ammo %d/%d   rifles %d   medicine %d\nfood %d   water %d   (-%d/day each)   power %s\nsalvage metal %d  parts %d  electronics %d" % [
		Game.scrap, Game.rescued, Game.housing(), Game.campers(), Game.injured, Game.idle_workers(), Game.base_fuel, Game.base_fuel_cap,
		Game.base_ammo, Game.base_ammo_cap, Game.base_rifles, Game.base_medicine, Game.base_food, Game.base_water, eaters, "on" if Game.power else "off",
		Game.salvage["metal"], Game.salvage["parts"], Game.salvage["electronics"]]
	if base.placing:
		header.text += "\nClick: place %s   RMB: remove blueprint   Build workers build" % ("sandbag" if base.place_kind == "sandbag" else Game.BUILDINGS[base.place_kind][0])
	for k in place_btns:
		place_btns[k].set_pressed_no_signal(base.placing and base.place_kind == k)
		if k != "sandbag":
			place_btns[k].text = "Place" if not place_btns[k].button_pressed else "Placing"
	var built: int = Game.sandbags.values().filter(func(b): return b["built"]).size()
	place_btn.text = "%s sandbags  5 scrap each  RMB removes  %d/%d built" % ["Placing" if place_btn.button_pressed else "Place", built, Game.sandbags.size()]
	for kind in BUILD_INFO:
		var b: Array = Game.BUILDINGS[kind]
		var planned: int = Game.buildings.filter(func(s): return s["kind"] == kind and not s["built"]).size()
		site_rows[kind].text = "%s  %d scrap %ds  %s  (%d%s)" % [b[0], b[1], b[2], BUILD_INFO[kind], Game.built(kind), " +%d planned" % planned if planned > 0 else ""]
		place_btns[kind].disabled = Game.scrap < b[1] and not place_btns[kind].button_pressed
	var plvl: int = base.perimeter_level()
	site_rows["perimeter"].text = "Perimeter %d m  Lv %d/%d  (+6 m, 60 s)" % [Game.base_radius / 10.0, plvl, Game.PERIMETER_MAX]
	perimeter_btn.text = "MAX" if plvl >= Game.PERIMETER_MAX else "Expand %d" % base.building_cost("perimeter")
	perimeter_btn.disabled = plvl >= Game.PERIMETER_MAX or Game.scrap < base.building_cost("perimeter") or not base.next_site("perimeter").is_empty()
	for id in UPGRADES:
		var u: Array = UPGRADES[id]
		var lvl: int = Game.base_level.get(id, 0)
		var maxed: bool = lvl >= u[1]
		var need: int = u[3] * (lvl + 1)
		rows[id][0].text = "%s  Lv %d/%d" % [u[0], lvl, u[1]] + ("" if maxed or need == 0 else "  (needs %d rescued)" % need) + ("  " + UPGRADE_INFO[id] if UPGRADE_INFO.has(id) else "")
		rows[id][1].text = "MAX" if maxed else "Buy %d" % cost(id)
		rows[id][1].disabled = not can_buy(id)
	rows["repair"][0].text = "Repair Base  %d/%d" % [Game.base_hp, Game.max_base_hp]
	repair_btn.text = "Fix %d" % cost("repair")
	repair_btn.disabled = not can_buy("repair")
	loadout_info.text = "Weight %d/%d pts (over 8: -4 %% speed each)   Speed x%.2f\nSeats %d  Fuel %d  Ammo %d  Armour x%.2f" % [
		Game.loadout_points(), Game.loadout_budget, Game.weight_factor, Game.seats, Game.max_fuel, Game.max_ammo, Game.stats["armor"]]
	for k in LOADOUT:
		loadout_rows[k].text = "%s: %d" % [LOADOUT[k][0], Game.loadout[k]]
	_refresh_weapons()
	worker_info.text = "Population %d   beds %d   camping %d (work at 50 %%)   injured %d   assigned %d   idle %d" % [
		Game.rescued, Game.housing(), Game.campers(), Game.injured, Game.assigned(), Game.idle_workers()]
	for j in JOBS:
		job_rows[j].text = "%s: %d" % [JOBS[j], Game.workers[j]]
		var h: Node = job_rows[j].get_parent()
		h.get_child(1).disabled = Game.workers[j] <= 0
		var why := worker_refusal(j, Game.workers[j] + 1)
		h.get_child(2).modulate = Color(1, 1, 1, 0.35) if why != "" else Color.WHITE # greyed but clickable: a click shows why
		h.get_child(2).tooltip_text = why
	job_rows["militia"].text = "Militia %d (rifles %d)  -3 %% dmg each, mans posts in assaults" % [Game.workers["militia"], Game.base_rifles]
	job_rows["militia"].modulate = Color(1, 0.4, 0.4) if Game.workers["militia"] > int(Game.base_rifles) else Color.WHITE


func _refresh_weapons() -> void:
	for c in weapon_box.get_children():
		weapon_box.remove_child(c) # a Stow/Mount button may be mid-signal, so no free()
		c.queue_free()
	var cap := Label.new()
	cap.text = "Weapons  (hardpoints %d/%d, Q switches in flight)" % [Game.heli_weapons.size(), Game.slots["hardpoint"]]
	cap.add_theme_font_size_override("font_size", 13)
	weapon_box.add_child(cap)
	for id in Game.heli_weapons:
		_weapon_row("HELI  %s Lv %d%s" % [Weapons.TABLE[id]["name"], Progression.level(id), "  (equipped)" if id == Game.weapon else ""], "Stow", Game.heli_weapons.size() < 2, stow.bind(id))
	for id in Game.weapon_bay:
		_weapon_row("BAY   %s Lv %d" % [Weapons.TABLE[id]["name"], Progression.level(id)], "Mount", Game.heli_weapons.size() >= Game.slots["hardpoint"], mount.bind(id))
	_refresh_items()


## Fitted systems and modules with a scrap button; Workshop levels buy the extra slots.
func _refresh_items() -> void:
	var cap := Label.new()
	cap.text = "Fitted  (systems %d/%d, modules %d/%d; Workshop 1/2/3 adds a hardpoint/system/module slot)" % [
		Progression.used("system"), Game.slots["system"], Progression.used("module"), Game.slots["module"]]
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD
	cap.custom_minimum_size.x = 360
	cap.add_theme_font_size_override("font_size", 13)
	weapon_box.add_child(cap)
	for id in Game.heli_items:
		if Progression.ITEMS[id]["slot"] != "hardpoint":
			var lv: int = Game.heli_items[id]
			_weapon_row("%s  %s Lv %d" % [Progression.ITEMS[id]["slot"].substr(0, 3).to_upper(), Progression.ITEMS[id]["name"], lv],
				"Scrap +%d" % (lv * Progression.CARD_SCRAP / 2), false, func(): Game.scrap_item(id); refresh())


func _weapon_row(text: String, btn: String, disabled: bool, cb: Callable) -> void:
	var h := HBoxContainer.new()
	weapon_box.add_child(h)
	_lbl(h).text = text
	var b := Button.new()
	b.text = btn
	b.custom_minimum_size.x = 80
	b.disabled = disabled
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


## Why `job` cannot have `n` workers, "" if it can.
func worker_refusal(job: String, n: int) -> String:
	var cur: int = Game.workers[job]
	if n < 0:
		return "nobody on that job"
	if n - cur > Game.idle_workers():
		return "no idle people"
	if n > cur and job == "water" and not get_parent().water_near():
		return "no water within 40 m"
	if n > cur and job == "workshop" and Game.base_level.get("workshop", 0) < 1:
		return "needs the Workshop upgrade (BUILD tab)"
	return ""


func set_worker(job: String, n: int) -> bool:
	var why := worker_refusal(job, n)
	if why != "":
		worker_msg.text = why
		get_tree().create_timer(3.0).timeout.connect(func(): if worker_msg.text == why: worker_msg.text = "")
		return false
	Game.workers[job] = n
	refresh()
	return true


func unassign_all() -> void:
	for k in Game.workers:
		Game.workers[k] = 0
	refresh()


func _adjust_worker(job: String, d: int) -> void:
	set_worker(job, Game.workers[job] + d)
