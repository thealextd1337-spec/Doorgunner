extends CanvasLayer
## Base upgrade menu, shown while the heli sits on the pad. buy(id) applies effects to Game directly.

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

var header: Label
var rows := {} # id -> [Label, Button]
var repair_btn: Button


func _ready() -> void:
	layer = 10
	visible = false
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.05, 0.9)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-360, 160)
	panel.size = Vector2(350, 100)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "FORWARD OPERATING BASE"
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)
	header = Label.new()
	box.add_child(header)
	for id in UPGRADES:
		rows[id] = _row(box, id)
	rows["repair"] = _row(box, "repair")
	repair_btn = rows["repair"][1]
	var hint := Label.new()
	hint.text = "[SPACE] take off closes this menu"
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)


func _row(box: VBoxContainer, id: String) -> Array:
	var h := HBoxContainer.new()
	box.add_child(h)
	var l := Label.new()
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 13)
	h.add_child(l)
	var b := Button.new()
	b.custom_minimum_size.x = 80
	b.pressed.connect(buy.bind(id))
	h.add_child(b)
	return [l, b]


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
	header.text = "Scrap: %d   Rescued: %d" % [Game.scrap, Game.rescued]
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
			Game.max_fuel += 25.0
		"armory":
			Game.max_ammo += 60
		"workshop":
			Game.stats["damage"] += 0.15
		"clinic":
			Game.max_hp += 20.0
		"barracks":
			Game.seats += 1
	refresh()
	return true
