extends VBoxContainer
## HANGAR tab rows of P15 (scripts/wrecks.gd): key parts, wrecks inside the fence with their repair project, projects with a
## progress bar, parked helis to switch to. base_ui.gd adds it and sets `ui` (its label helper and colours).
## Rebuilt when the shown state changes (checked twice a second), so buttons stay clickable in between.

const HeliTypes := preload("res://scripts/heli_types.gd")

const WIDTH := 590.0 # px of the HANGAR column

var ui: CanvasLayer # base_ui.gd
var _sig := ""
var _t := 0.0
var _msg := ""


func _process(delta: float) -> void:
	_t -= delta
	if not is_visible_in_tree() or _t > 0.0:
		return
	_t = 0.5
	var w: Node = Game.world.wrecks
	var sig := "%s|%s|%s|%s|%s|%s" % [w.active, w.keys, Game.salvage, w.wrecks.keys().map(func(u): return [w.wrecks[u]["state"], int(w.wrecks[u]["progress"] * 20.0)]), Game.heli.landed, _msg]
	if sig != _sig:
		_sig = sig
		_build(w)


func _build(w: Node) -> void:
	for c in get_children():
		c.free()
	var t: Dictionary = w.htype()
	add_child(ui._label("FLEET  flying the %s (%s, %d seats, %d hardpoints)" % [t["name"], t["role"], Game.seats, Game.slots["hardpoint"]], 12, ui.ACCENT, true))
	_wrap("key parts: " + "  ".join(w.keys.keys().map(func(k): return "%s %d" % [HeliTypes.KEY_PARTS[k], w.keys[k]])), ui.DIM)
	var any := false
	for uid in w.wrecks:
		var r: Dictionary = w.wrecks[uid]
		var name: String = HeliTypes.get_type(r["type"])["name"]
		match r["state"]:
			"base":
				var c: Dictionary = w.cost(uid)
				var why: String = w.repair_refusal(uid)
				_row("%s wreck, %d %% intact: %d metal, %d parts, %d electronics, %s, %d work days" % [name, 100.0 * r["cond"], c["metal"], c["parts"], c["electronics"],
					", ".join(c["keys"].map(func(k): return HeliTypes.KEY_PARTS[k])), c["days"]], "Start repair", why, func(): _msg = w.start_repair(uid))
			"repair":
				var n := int(20.0 * r["progress"] / r["days"])
				var rate: float = w.mechanic_rate()
				_wrap("%s  [%s%s]  %.1f/%d work days  %s" % [name, "#".repeat(n), "-".repeat(20 - n), r["progress"], r["days"],
					"(%.1f/day)" % rate if rate > 0.0 else "(needs Mechanics or Engineers on Repair duty)"], ui.SAND)
			"parked":
				_row("%s, repaired, parked at the base" % name, "Fly this one", w.switch_refusal(uid), func(): _msg = w.switch_to(uid))
			_:
				continue
		any = true
	if not any:
		_wrap("No wrecks at the base. Hook one at an airfield, checkpoint or airliner crash (G) and drop it inside the fence.", ui.DIM)
	if _msg != "":
		_wrap(_msg, ui.BAD)


func _wrap(text: String, color: Color) -> void:
	var l: Label = ui._label(text, 12, color, true)
	l.custom_minimum_size.x = WIDTH
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)


func _row(text: String, action: String, why: String, on_press: Callable) -> void:
	var h := HBoxContainer.new()
	add_child(h)
	var l: Label = ui._label(text, 12, ui.SAND, true)
	l.custom_minimum_size.x = WIDTH - 130
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	var b := Button.new()
	b.text = action
	b.focus_mode = Control.FOCUS_NONE # SPACE takes off, it must not click the button
	b.custom_minimum_size = Vector2(120, 26)
	b.add_theme_font_size_override("font_size", 12)
	b.disabled = why != ""
	b.tooltip_text = why
	b.pressed.connect(on_press)
	h.add_child(b)
