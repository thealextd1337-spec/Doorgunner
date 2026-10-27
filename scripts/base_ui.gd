extends CanvasLayer
## Base menu, shown while the heli sits on the pad. Tabs: BUILD (upgrades), HANGAR (loadout, weapons), WORKERS (jobs).
## buy(id) applies effects to Game directly.

# id -> [name, max level, scrap cost per level (x level+1), rescued required per level]
const UPGRADES := {
	"turrets": ["Turret", 4, 40, 0],
	"walls": ["Sandbag Walls", 3, 50, 0],
	"fuel": ["Fuel Depot", 3, 40, 0],
	"armory": ["Armory", 3, 40, 0],
	"workshop": ["Workshop", 3, 60, 0],
	"clinic": ["Field Clinic", 3, 50, 5],
	"barracks": ["Barracks", 3, 60, 8],
}
# loadout key -> [label, min, max]
const LOADOUT := {
	"seats": ["Seats (1 pt each)", 2, 8],
	"fuel_tank": ["Fuel tank +25 fuel/lv (2 pt)", 0, 3],
	"ammo_feed": ["Ammo feed +60 ammo/lv (2 pt)", 0, 3],
	"armor": ["Armour +15 %/lv (2 pt)", 0, 3],
}
const JOBS := {"fuel": "Fuel +20/day", "ammo": "Ammo +40/day", "repair": "Repair +40 hp/day", "militia": "Militia -3 % dmg, 2 = turret", "farm": "Farm +6 food/day"}
const Weapons := preload("res://scripts/weapons.gd")

var header: Label
var rows := {} # id -> [Label, Button]
var repair_btn: Button
var tabs := {} # name -> VBoxContainer
var loadout_rows := {} # key -> Label
var loadout_info: Label
var weapon_box: VBoxContainer
var job_rows := {} # job -> Label


func _ready() -> void:
	layer = 10
	visible = false
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.05, 0.9)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-400, 120)
	panel.size = Vector2(390, 100)
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
	loadout_info = Label.new()
	loadout_info.add_theme_font_size_override("font_size", 13)
	tabs["HANGAR"].add_child(loadout_info)
	for k in LOADOUT:
		loadout_rows[k] = _pm_row(tabs["HANGAR"], _adjust_loadout, k)
	weapon_box = VBoxContainer.new()
	tabs["HANGAR"].add_child(weapon_box)
	for j in JOBS:
		job_rows[j] = _pm_row(tabs["WORKERS"], _adjust_worker, j)
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
	header.text = "Scrap: %d   Rescued: %d   Idle: %d\nStock  fuel %d/%d   ammo %d/%d   food %d (eats %d/day)" % [
		Game.scrap, Game.rescued, Game.idle_workers(), Game.base_fuel, Game.base_fuel_cap, Game.base_ammo, Game.base_ammo_cap, Game.base_food, Game.rescued]
	for id in UPGRADES:
		var u: Array = UPGRADES[id]
		var lvl: int = Game.base_level.get(id, 0)
		var maxed: bool = lvl >= u[1]
		var need: int = u[3] * (lvl + 1)
		rows[id][0].text = "%s  Lv %d/%d" % [u[0], lvl, u[1]] + ("" if maxed or need == 0 else "  (needs %d rescued)" % need)
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
	for j in JOBS:
		job_rows[j].text = "%s: %d" % [JOBS[j], Game.workers[j]]


func _refresh_weapons() -> void:
	for c in weapon_box.get_children():
		weapon_box.remove_child(c) # a Stow/Mount button may be mid-signal, so no free()
		c.queue_free()
	var cap := Label.new()
	cap.text = "Weapons  (heli %d/%d slots, Q switches in flight)" % [Game.heli_weapons.size(), Game.HELI_SLOTS]
	cap.add_theme_font_size_override("font_size", 13)
	weapon_box.add_child(cap)
	for id in Game.heli_weapons:
		_weapon_row("HELI  %s%s" % [Weapons.TABLE[id]["name"], "  (equipped)" if id == Game.weapon else ""], "Stow", Game.heli_weapons.size() < 2, stow.bind(id))
	for id in Game.weapon_bay:
		_weapon_row("BAY   %s" % Weapons.TABLE[id]["name"], "Mount", Game.heli_weapons.size() >= Game.HELI_SLOTS, mount.bind(id))


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
		"walls":
			Game.max_base_hp += 250.0
			Game.base_hp += 250.0
			get_parent().rebuild()
		"fuel":
			Game.base_max_fuel += 25.0
			Game.base_fuel_cap += 200.0
		"armory":
			Game.base_max_ammo += 60
			Game.base_ammo_cap += 400.0
		"workshop":
			Game.stats["damage"] += 0.15
			Game.loadout_budget += 1
		"clinic":
			Game.max_hp += 20.0
		"barracks":
			Game.base_seats += 1
	Game.recompute()
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
	refresh()


func mount(id: String) -> void:
	if Game.heli_weapons.size() >= Game.HELI_SLOTS or id not in Game.weapon_bay:
		return
	Game.weapon_bay.erase(id)
	Game.heli_weapons.append(id)
	refresh()


func set_worker(job: String, n: int) -> bool:
	var cur: int = Game.workers[job]
	if n < 0 or n - cur > Game.idle_workers():
		return false
	Game.workers[job] = n
	if job == "militia":
		get_parent().rebuild()
	refresh()
	return true


func _adjust_worker(job: String, d: int) -> void:
	set_worker(job, Game.workers[job] + d)
