extends CanvasLayer
## In-flight HUD: resource bars, clock, radio log, compass arrows to base and radio target.

var bars := {}
var info: Label
var log_label: Label
var hint: Label
var alert: Label
var compass: Control
var minimap: Control
var log_lines: Array[String] = []

const MAP_SIZE := 200.0
const MAP_SCALE := 16.0 # world px per minimap px
const MAP_SEEN := 480.0 # POIs this close to the heli become known
const POI_COLORS := {
	"survivors": Color(0.4, 1, 0.5), "crate": Color(1, 0.85, 0.3), "upgrade": Color(0.5, 0.8, 1),
	"radio_tower": Color(1, 1, 1), "wreck": Color(1, 0.5, 0.2), "nest": Color(1, 0.3, 0.9),
}


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var y := 10
	for id in ["hp", "fuel", "ammo", "xp"]:
		bars[id] = _make_bar(root, Vector2(10, y))
		y += 22
	# logical canvas is fixed at 1280x720 (stretch mode canvas_items)
	info = _label(root, Vector2(870, 10), 400, HORIZONTAL_ALIGNMENT_RIGHT)
	log_label = _label(root, Vector2(10, 600), 620)
	log_label.modulate = Color(0.8, 1, 0.8)
	hint = _label(root, Vector2(390, 690), 500, HORIZONTAL_ALIGNMENT_CENTER)
	alert = _label(root, Vector2(390, 60), 500, HORIZONTAL_ALIGNMENT_CENTER)
	alert.add_theme_font_size_override("font_size", 26)
	alert.modulate = Color(1, 0.3, 0.3)
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_FULL_RECT)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	root.add_child(compass)
	minimap = Control.new()
	minimap.position = Vector2(1280 - MAP_SIZE - 10, 720 - MAP_SIZE - 10)
	minimap.size = Vector2(MAP_SIZE, MAP_SIZE)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)
	Game.radio_message.connect(_on_radio)


func _make_bar(parent: Control, pos: Vector2) -> Dictionary:
	var bg := ColorRect.new()
	bg.position = pos
	bg.size = Vector2(200, 16)
	bg.color = Color(0, 0, 0, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var fill := ColorRect.new()
	fill.position = Vector2(2, 2)
	fill.size = Vector2(196, 12)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	var lbl := Label.new()
	lbl.position = Vector2(6, -2)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 3)
	bg.add_child(lbl)
	return {"fill": fill, "label": lbl}


func _label(parent: Control, pos: Vector2, width: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(width, 100)
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _set_bar(id: String, value: float, maxv: float, text: String, color: Color) -> void:
	var b: Dictionary = bars[id]
	b["fill"].size.x = 196.0 * clampf(value / maxv, 0.0, 1.0)
	b["fill"].color = color
	b["label"].text = text


func _process(_delta: float) -> void:
	_set_bar("hp", Game.hp, Game.max_hp, "HULL %d/%d" % [Game.hp, Game.max_hp], Color(0.3, 0.8, 0.3).lerp(Color(0.9, 0.2, 0.2), 1.0 - Game.hp / Game.max_hp))
	_set_bar("fuel", Game.fuel, Game.max_fuel, "FUEL %d/%d" % [Game.fuel, Game.max_fuel], Color(0.9, 0.75, 0.2))
	_set_bar("ammo", Game.ammo, Game.max_ammo, "AMMO %d/%d" % [Game.ammo, Game.max_ammo], Color(0.7, 0.7, 0.7))
	_set_bar("xp", Game.xp, Game.xp_needed(), "LVL %d  XP %d/%d" % [Game.level, Game.xp, Game.xp_needed()], Color(0.3, 0.5, 0.95))
	var h := int(Game.time * 24.0)
	var m := int(fmod(Game.time * 24.0, 1.0) * 60.0)
	var next_attack := Game.ATTACK_EVERY_DAYS - (Game.day % Game.ATTACK_EVERY_DAYS)
	var table: Dictionary = preload("res://scripts/weapons.gd").TABLE
	var carried := " / ".join(Game.heli_weapons.map(func(id): return table[id]["name"].to_upper() if id == Game.weapon else table[id]["name"]))
	info.text = "DAY %d  %02d:%02d %s\nSCRAP %d\nPASSENGERS %d/%d\nRESCUED %d   KILLS %d\nWEAPON %s\nBASE HP %d/%d   STOCK %d fuel  %d ammo  %d food\nNOISE %d%%\nNext assault: %s" % [
		Game.day, h, m, "NIGHT" if Game.is_night() else "",
		Game.scrap, Game.passengers, Game.seats, Game.rescued, Game.kills, carried,
		Game.base_hp, Game.max_base_hp, Game.base_fuel, Game.base_ammo, Game.base_food, Game.noise_level * 100.0,
		"TONIGHT" if Game.attack_pending or Game.attack_active else "in %d day(s)" % next_attack]
	info.visible = not Game.world.ui_open # base menu shows the same numbers
	if Game.heli:
		hint.text = "spooling..." if Game.heli.pending != 0 else "[SPACE] take off" if Game.heli.landed else "[SPACE] land   [LMB] fire   [Q] weapon"
	alert.text = "BASE UNDER ATTACK" if Game.attack_active and fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else ""
	if Game.fuel < Game.max_fuel * 0.2 and alert.text == "":
		alert.text = "LOW FUEL"
	compass.queue_redraw()
	minimap.queue_redraw()


func _on_radio(msg: String) -> void:
	log_lines.append("> " + msg)
	while log_lines.size() > 5:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


func _draw_compass() -> void:
	if Game.heli == null:
		return
	var center := compass.size / 2.0
	_arrow(center, Game.world.base.global_position, Color(0.9, 0.9, 0.3), "BASE")
	if is_instance_valid(Game.world.radio_target):
		_arrow(center, Game.world.radio_target.global_position, Color(0.4, 1, 0.5), "RADIO")


func _arrow(center: Vector2, world_pos: Vector2, color: Color, text: String) -> void:
	var delta: Vector2 = world_pos - Game.heli.global_position
	var dist := delta.length()
	if dist < 120.0:
		return
	var dir := delta.normalized()
	var tip := center + dir * 120.0
	var pts := PackedVector2Array([tip, tip - dir * 14 + dir.orthogonal() * 7, tip - dir * 14 - dir.orthogonal() * 7])
	compass.draw_polygon(pts, PackedColorArray([color, color, color]))
	compass.draw_string(ThemeDB.fallback_font, tip - dir * 52 + Vector2(-40, 5), "%s %dm" % [text, int(dist / 10.0)], HORIZONTAL_ALIGNMENT_CENTER, 80, 12, color)


## North-up minimap centred on the heli: coarse terrain, base, known POIs, enemies.
func _draw_minimap() -> void:
	if Game.heli == null:
		return
	var heli_pos: Vector2 = Game.heli.global_position
	var half := MAP_SIZE / 2.0
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color(0, 0, 0, 0.6))
	var step := 8.0 # minimap px per terrain sample
	var chunks: Node = Game.world.chunks
	for x in range(0, int(MAP_SIZE), int(step)):
		for y in range(0, int(MAP_SIZE), int(step)):
			var wp := heli_pos + (Vector2(x, y) + Vector2(step, step) / 2.0 - Vector2(half, half)) * MAP_SCALE
			var t: int = chunks.tile_at(wp)
			var c := Color(0, 0, 0, 0)
			if t == chunks.T.WATER:
				c = Color(0.2, 0.35, 0.7, 0.7)
			elif t == chunks.T.FOREST:
				c = Color(0.1, 0.3, 0.1, 0.7)
			elif t == chunks.T.BUILDING or t == chunks.T.RUIN or t == chunks.T.ROAD:
				c = Color(0.5, 0.5, 0.5, 0.8)
			if c.a > 0.0:
				minimap.draw_rect(Rect2(Vector2(x, y), Vector2(step, step)), c)
	var to_map := func(wp: Vector2) -> Vector2:
		return ((wp - heli_pos) / MAP_SCALE + Vector2(half, half)).clamp(Vector2(2, 2), Vector2(MAP_SIZE - 2, MAP_SIZE - 2))
	minimap.draw_rect(Rect2(to_map.call(Game.world.base.global_position) - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 0.3))
	for p in Game.world.pois:
		if not is_instance_valid(p) or p.done:
			continue
		if not p.discovered and heli_pos.distance_squared_to(p.global_position) < MAP_SEEN * MAP_SEEN:
			p.discovered = true
		if p.discovered:
			minimap.draw_rect(Rect2(to_map.call(p.global_position) - Vector2(2, 2), Vector2(4, 4)), POI_COLORS.get(p.kind, Color.WHITE))
	for e in get_tree().get_nodes_in_group("enemies"):
		var mp: Vector2 = (e.global_position - heli_pos) / MAP_SCALE + Vector2(half, half)
		if mp.x >= 0 and mp.y >= 0 and mp.x < MAP_SIZE and mp.y < MAP_SIZE:
			minimap.draw_rect(Rect2(mp - Vector2(1, 1), Vector2(2, 2)), Color(1, 0.25, 0.25))
	minimap.draw_rect(Rect2(Vector2(half - 2, half - 2), Vector2(4, 4)), Color.WHITE)
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color(0.8, 0.8, 0.7, 0.8), false, 1.0)
