extends CanvasLayer
## In-flight HUD: resource bars, clock, radio log, compass arrows to base and radio target.

var bars := {}
var info: Label
var slots_label: Label # fitted items per slot type, under the bars
var log_label: Label
var hint: Label
var alert: Label
var compass: Control
var minimap: Control
var log_lines: Array[String] = []

const MAP_SIZE := 200.0
const MAP_SCALE := 16.0 # world px per minimap px
const MAP_SEEN := 480.0 # POIs this close to the heli become known
const ARC_IN := 36.0 # door gun wedges around the heli, screen px (camera zoom 2)
const ARC_OUT := 56.0
# minimap terrain colours by chunk_manager tile index (see its T enum)
const MAP_COLORS := {
	0: Color(0.36, 0.48, 0.25), 8: Color(0.33, 0.46, 0.24), 9: Color(0.42, 0.5, 0.28), 13: Color(0.28, 0.4, 0.2), # grass
	1: Color(0.14, 0.28, 0.14), 16: Color(0.2, 0.34, 0.16), # forest, hedge
	2: Color(0.25, 0.4, 0.7), 17: Color(0.3, 0.45, 0.4), # water, marsh
	3: Color(0.75, 0.68, 0.48), 10: Color(0.68, 0.64, 0.3), 14: Color(0.5, 0.58, 0.32), # sand, field, yard
	4: Color(0.22, 0.22, 0.24), 15: Color(0.2, 0.2, 0.22), 21: Color(0.26, 0.26, 0.28), 11: Color(0.5, 0.38, 0.24), # roads, parking, dirt
	5: Color(0.6, 0.6, 0.62), 18: Color(0.55, 0.55, 0.6), 6: Color(0.42, 0.4, 0.38), # building, warehouse, ruin
	7: Color(0.7, 0.7, 0.68), 22: Color(0.66, 0.64, 0.6), 23: Color(0.62, 0.62, 0.6), # base floor, plaza, pad
	12: Color(0.5, 0.5, 0.48), 19: Color(0.36, 0.34, 0.32), 20: Color(0.2, 0.18, 0.17), # rock, ash, crater
	27: Color(0.45, 0.36, 0.26), # bridge
}
const POI_COLORS := {
	"survivors": Color(0.4, 1, 0.5), "hideout": Color(0.6, 0.9, 0.6), "crate": Color(1, 0.85, 0.3), "upgrade": Color(0.5, 0.8, 1),
	"radio_tower": Color(1, 1, 1), "wreck": Color(1, 0.5, 0.2), "nest": Color(1, 0.3, 0.9), "fuel_station": Color(1, 0.6, 0.2),
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
	slots_label = _label(root, Vector2(10, y), 860)
	slots_label.add_theme_font_size_override("font_size", 13)
	# logical canvas is fixed at 1280x720 (stretch mode canvas_items)
	info = _label(root, Vector2(620, 10), 650, HORIZONTAL_ALIGNMENT_RIGHT)
	log_label = _label(root, Vector2(10, 575), 620) # five lines end above the hint row (y 690)
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
	minimap.clip_contents = true
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
	var next_attack := Game.days_to_assault()
	var table: Dictionary = preload("res://scripts/weapons.gd").TABLE
	var carried := " / ".join(Game.heli_weapons.map(func(id): return table[id]["name"].to_upper() if id == Game.weapon else table[id]["name"]))
	info.text = "DAY %d  %02d:%02d %s\nSCRAP %d\nPASSENGERS %d/%d\nWEAPON %s  (%d m)\n" % [ # rescued / kills: title screen service record only
		Game.day, h, m, "NIGHT" if Game.is_night() else "",
		Game.scrap, Game.passengers, Game.seats, carried, Game.heli.weapon_range() / 10.0]
	info.text += "NO BASE: land on open ground and press B" if not Game.base_founded else "BASE HP %d/%d   STOCK %d fuel  %d ammo  %d food  SALVAGE %d/%d/%d\nWATER %d  MED %d  RIFLES %d  INJURED %d\nPOWER %s (gen fuel %d/day)\nNOISE %d%%\nNext assault: %s" % [
		Game.base_hp, Game.max_base_hp, Game.base_fuel, Game.base_ammo, Game.base_food, Game.salvage["metal"], Game.salvage["parts"], Game.salvage["electronics"],
		Game.base_water, Game.base_medicine, Game.base_rifles, Game.injured, "on" if Game.power else "off", Game.built("generator") * Game.GEN_FUEL, Game.noise_level * 100.0,
		"TONIGHT" if Game.attack_pending or Game.attack_active else "in %d day(s)" % (next_attack if next_attack > 0 else Game.ATTACK_EVERY_DAYS)]
	info.text += Game.world.outposts.status() + Game.world.convoys.status() + Game.world.evac.status()
	if Game.passengers >= Game.seats and Game.passengers > 0: # full cabin: who is aboard
		info.text += "\nABOARD " + ", ".join(Game.people.filter(func(p): return p["aboard"]).map(preload("res://scripts/people.gd").short))
	info.visible = not Game.world.ui_open # base menu shows the same numbers
	slots_label.text = Progression.slot_line() + "     " + Game.world.wear.status_line()
	slots_label.visible = not Game.world.ui_open # would show through between the base menu panels
	if Game.heli:
		hint.text = "spooling..." if Game.heli.pending != 0 else "[SPACE] take off" + ("   [B] found the base here" if Game.heli.can_found() else "") + Game.world.outposts.hint() if Game.heli.landed else "[SPACE] land   [LMB] fire   [Q][E] turn   [X] weapon   [ESC] sound" + ("   [F] loudspeaker" if Game.heli_items.has("loudspeaker") else "") + ("   [G] hook the wreck" if Game.world.wrecks.wreck_below(Game.heli.position) != "" else "")
	alert.text = Assault.alert_text() if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else ""
	if Game.fuel < Game.max_fuel * 0.2 and alert.text == "":
		alert.text = "LOW FUEL"
	if Game.heli and Game.heli.no_angle > 0.0 and alert.text == "":
		alert.text = "no firing angle: swing the heli"
	var sling: String = Game.world.wrecks.alert()
	if sling != "":
		alert.text = sling
	var wear_alert: String = Game.world.wear.alert()
	if wear_alert != "":
		alert.text = wear_alert # engine trouble outranks everything else
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
	compass.draw_arc(center, Game.heli.weapon_range() * 2.0, 0.0, TAU, 64, Color(1, 1, 1, 0.12), 1.0) # camera zoom 2
	_door_arcs(Game.heli.get_global_transform_with_canvas().origin) # on the heli itself, the smoothed camera lags behind it
	if Game.base_founded:
		_arrow(center, Game.world.base.global_position, Color(0.9, 0.9, 0.3), "BASE")
	if is_instance_valid(Game.world.radio_target):
		_arrow(center, Game.world.radio_target.global_position, Color(0.4, 1, 0.5), "RADIO")
	Assault.draw_arrow(compass)
	for m: Dictionary in Game.world.missions.open:
		_arrow(center, m["pos"], Color(1.0, 0.75, 0.3), Game.world.missions.TYPES[m["type"]]["tag"])


## Left and right door gun arcs turning with the heli body, lit on the side the mouse aims at; aim line red outside both.
func _door_arcs(at: Vector2) -> void:
	var heli: Node2D = Game.heli
	var aim: Vector2 = heli.aim_dir()
	var ok: bool = heli.in_arc(aim)
	var half := deg_to_rad(heli.ARC_DEG)
	for side in [0.0, PI]:
		var a: float = heli.body.rotation + side # body rotation 0 = nose up, so the doors face rotation and rotation + PI
		var lit: bool = ok and Vector2.from_angle(a).dot(aim) > 0.0
		var pts := PackedVector2Array()
		for i in 15:
			pts.append(at + Vector2.from_angle(a - half + i * half / 7.0) * ARC_OUT)
		for i in 15:
			pts.append(at + Vector2.from_angle(a + half - i * half / 7.0) * ARC_IN)
		compass.draw_colored_polygon(pts, Color(1, 0.85, 0.3, 0.28 if lit else 0.12))
		compass.draw_arc(at, ARC_OUT, a - half, a + half, 24, Color(0, 0, 0, 0.35), 4.0) # dark rim for daylight contrast
		compass.draw_arc(at, ARC_OUT, a - half, a + half, 24, Color(1, 0.85, 0.3, 0.95 if lit else 0.5), 2.0 if lit else 1.5)
	compass.draw_line(at + aim * ARC_IN, at + aim * (ARC_OUT + 14.0), Color(1, 1, 1, 0.8) if ok else Color(1, 0.2, 0.15, 0.9), 2.0)


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
	# terrain samples sit on a fixed world grid (not relative to the heli), so the map scrolls instead of flickering
	var step := 5.0 # minimap px per terrain sample
	var world_step := step * MAP_SCALE
	var chunks: Node = Game.world.chunks
	var first := ((heli_pos - Vector2(half, half) * MAP_SCALE) / world_step).floor() * world_step
	var n := int(MAP_SIZE / step) + 2
	for i in n:
		for j in n:
			var wp := first + Vector2(i, j) * world_step
			var mp := (wp - heli_pos) / MAP_SCALE + Vector2(half, half)
			var c: Color = MAP_COLORS.get(chunks.tile_at(wp + Vector2(world_step, world_step) / 2.0), Color(0.3, 0.3, 0.3))
			minimap.draw_rect(Rect2(mp, Vector2(step, step)), c)
	var to_map := func(wp: Vector2) -> Vector2:
		return ((wp - heli_pos) / MAP_SCALE + Vector2(half, half)).clamp(Vector2(2, 2), Vector2(MAP_SIZE - 2, MAP_SIZE - 2))
	if Game.base_founded:
		minimap.draw_rect(Rect2(to_map.call(Game.world.base.global_position) - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 0.3))
	Game.world.outposts.draw_map(minimap, to_map)
	Game.world.convoys.draw_map(minimap, to_map)
	for p in Game.world.pois:
		if not is_instance_valid(p) or p.done:
			continue
		if not p.discovered and heli_pos.distance_squared_to(p.global_position) < MAP_SEEN * MAP_SEEN and not Game.world.modifiers.on("blackout"):
			p.discovered = true
		if p.discovered:
			minimap.draw_rect(Rect2(to_map.call(p.global_position) - Vector2(2, 2), Vector2(4, 4)), POI_COLORS.get(p.kind, Color.WHITE))
	for m: Dictionary in Game.world.missions.open:
		minimap.draw_rect(Rect2(to_map.call(m["pos"]) - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.75, 0.3), false, 1.5)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("concealed"):
			continue # in the forest
		var mp: Vector2 = (e.global_position - heli_pos) / MAP_SCALE + Vector2(half, half)
		if mp.x >= 0 and mp.y >= 0 and mp.x < MAP_SIZE and mp.y < MAP_SIZE:
			minimap.draw_rect(Rect2(mp - Vector2(1, 1), Vector2(2, 2)), Color(1, 0.25, 0.25))
	minimap.draw_rect(Rect2(Vector2(half - 2, half - 2), Vector2(4, 4)), Color.WHITE)
	minimap.draw_rect(Rect2(Vector2.ZERO, Vector2(MAP_SIZE, MAP_SIZE)), Color(0.8, 0.8, 0.7, 0.8), false, 1.0)
