extends Node
## Onboarding (docs/ROADMAP2.md Q11): SMOKE=onboarding godot --headless --path . --quit-after 30000
## The codex table covers every enemy kind, building, item and heli type; enemies, buildings, items and systems unlock when met
## (and persist in meta.json); chapters trigger, their steps close on their conditions, an urgent chapter (assault) cuts in, the
## panel shows the touch variant; a hint comes once per profile; Save.autosave() writes during a chapter; the setting and the
## skip button end chapters and mute hints while the codex keeps filling. Works on the smoke profile, its meta is put back.

const ENEMY := preload("res://scripts/enemy.gd")
const HeliTypes := preload("res://scripts/heli_types.gd")

var _bad: PackedStringArray = []
var main: Node2D
var ob: Node
var radio_log: Array = []


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	main = Game.world
	var frame := get_tree().process_frame
	await frame
	await frame
	get_tree().paused = true # the test drives scan() itself
	ob = main.get_children().filter(func(c): return c.get_script() == preload("res://scripts/onboarding.gd"))[0]
	var meta0: Dictionary = Game.meta.duplicate()
	var touch0: bool = Controls.touch
	Game.radio_message.connect(func(m: String): radio_log.append(m))
	Game.meta["codex"] = ""
	Game.meta["onboarding"] = ""
	Game.meta["tutorial_done"] = 1
	Controls.touch = false
	Settings.set_value(ob.KEY, 1)
	Game.passengers = 0
	Game.attack_pending = false
	Game.attack_active = false
	main.tutorial = null
	main.ui_open = false

	_table()
	_codex_encounters()
	var counts := _chapters()
	_hints()
	_touch()
	_toggle()
	_persist()

	Game.meta = meta0
	Game._save_meta()
	Controls.touch = touch0
	Settings.set_value(ob.KEY, 1)
	if _bad.is_empty():
		print("ONBOARDING OK  codex=%s chapters=%d hints=%d" % [counts, ob.CHAPTERS.size(), ob.HINTS.size()])
		get_tree().quit(0)
	else:
		for m in _bad:
			push_error("ONBOARDING FAIL: " + m)
		get_tree().quit(1)


## One pass with the step timer run out, for the chapter walk-through.
func _scan() -> void:
	ob.step_age = 999.0
	ob.scan()


func _table() -> void:
	for id in Progression.ITEMS:
		check(Codex.entries.has("item_" + id), "codex entry for item " + id)
	for id in Game.BUILDINGS:
		check(Codex.entries.has("bld_" + id), "codex entry for building " + id)
	for id in HeliTypes.TYPES:
		check(Codex.entries.has("heli_" + id), "codex entry for heli " + id)
	for id in ENEMY.KINDS:
		check(Codex.entries.has("z_" + id), "codex entry for infected " + id)
	for id in Bandit.KINDS:
		check(Codex.entries.has("b_" + id), "codex entry for bandit " + id)
	for id in ["bld_pad", "bld_sandbag", "bld_wire", "z_nest"]:
		check(Codex.entries.has(id), "codex entry " + id)
	for c in Codex.CATEGORIES:
		check(not Codex.in_category(c).is_empty(), "codex category %s is filled" % c)
	for id in Codex.entries:
		var e: Dictionary = Codex.entries[id]
		check(e["text"].length() > 20 and e["text"].length() < 220, "codex text length of " + id)
	check(Codex.entries.size() == CodexContent.ROWS.size(), "ids are unique (the table registers every row)")


func _codex_encounters() -> void:
	var hp: Vector2 = Game.heli.global_position
	check(Codex.ids_unlocked().size() == 0, "a fresh profile knows nothing")
	var far: Node2D = main.spawn_enemy("spitter", hp + Vector2(ob.SEE_DIST + 300.0, 0))
	radio_log.clear()
	ob.scan()
	check(Codex.ids_unlocked().size() >= 3, "the first scan of a run finds several entries: %d" % Codex.ids_unlocked().size())
	check(radio_log.filter(func(m): return m.begins_with("Codex:")).size() == 1 and radio_log.any(func(m): return " more added" in m), "... and radios them in ONE line: %s" % [radio_log])
	check(not Codex.is_unlocked("z_spitter"), "a spitter far away is not met yet")
	far.queue_free()
	var e: Node2D = main.spawn_enemy("spitter", hp + Vector2(120, 0))
	radio_log.clear()
	ob.scan()
	check(Codex.is_unlocked("z_spitter"), "a spitter near the heli unlocks its entry")
	check(radio_log.any(func(m): return m.begins_with("Codex: Spitter")), "the unlock is radioed")
	var n0 := Codex.ids_unlocked().size()
	ob.scan()
	check(Codex.ids_unlocked().size() == n0, "an entry unlocks once")
	e.queue_free()
	var b: Node2D = main.bandits.spawn_unit("rpg", hp + Vector2(150, 0), "guard", hp, "test_camp")
	ob.scan()
	check(Codex.is_unlocked("b_rpg"), "a bandit RPG gunner unlocks its entry")
	b.queue_free()
	Game.buildings.append({"kind": "well", "cell": Vector2i(1, 1), "built": false, "progress": 0.0})
	Game.heli_items["flamer"] = 1
	Game.world.wrecks.wrecks["t_wreck"] = {"type": "hind", "pos": hp + Vector2(5000, 0), "rot": 0.0, "cond": 0.5, "keys": [], "state": "site", "progress": 0.0, "days": 0, "heli": {}}
	ob.scan()
	check(Codex.is_unlocked("bld_well"), "a placed well unlocks its entry")
	check(Codex.is_unlocked("item_flamer"), "an owned item unlocks its entry")
	check(Codex.is_unlocked("heli_huey"), "the heli flown unlocks its entry")
	check(not Codex.is_unlocked("heli_hind"), "an unspotted wreck stays unknown")
	check(Codex.is_unlocked("sys_save") and Codex.is_unlocked("bld_pad"), "founding the base unlocks saving and the pad")
	Game.world.wrecks.wrecks["t_wreck"]["spotted"] = true
	ob.scan()
	check(Codex.is_unlocked("heli_hind") and Codex.is_unlocked("sys_wrecks"), "a spotted wreck unlocks its heli and the wrecks system")
	Game.world.wrecks.wrecks.erase("t_wreck")
	Game.buildings.pop_back()
	Game.heli_items.erase("flamer")
	check(not Codex.is_unlocked("sys_evac"), "systems not met stay locked")
	var wire_cell := Vector2i(-30, -30)
	Game.sandbags[wire_cell] = {"kind": "wire", "hp": 10.0, "built": true, "rot": 0}
	ob.scan()
	check(Codex.is_unlocked("bld_wire"), "a new wire cell unlocks barbed wire")
	Game.sandbags.erase(wire_cell)
	main.codex_ui.open()
	main.codex_ui.show_page("Enemies")
	var shown: Array = main.codex_ui.content.find_children("*", "Label", true, false).map(func(l): return l.text)
	check("Spitter" in shown and "Shambler" not in shown, "F1 shows met entries and hides the rest")
	main.codex_ui.close()
	get_tree().paused = true


## Marks every chapter seen except `ids`, so a test world's gas station or camp does not start a chapter by accident.
func _only(ids: Array) -> void:
	Game.meta["onboarding"] = ",".join(ob.CHAPTERS.keys().filter(func(id): return not id in ids).map(func(id): return "ch_" + id))


func _chapters() -> String:
	var w := main
	_only(["base", "assault"])
	# --- base & workers: starts once the base stands and no assault looms
	_scan()
	check(ob.chapter == "base", "the base chapter starts first on a quiet base")
	check(ob.panel.visible, "the chapter panel is up")
	Events.offer("stray_dog")
	ob._process(0.0)
	check(main.choice_ui.visible and not ob.panel.is_visible_in_tree(), "an event card hides the chapter card (and its Skip button)")
	main.choice_ui.pick_event(main.choice_ui.ev["view"]["default"])
	ob._process(0.0)
	check(not main.choice_ui.visible and ob.panel.is_visible_in_tree(), "the chapter card is back after the answer")
	Game.attack_pending = false
	_scan()
	check(ob.step == 0, "step 1 waits for the base menu")
	w.base.ui.open()
	_scan()
	check(ob.step == 1, "opening the base menu closes step 1")
	Game.workers["farm"] = 1
	_scan()
	Game.workers["fuel"] = 1
	Game.workers["ammo"] = 1
	_scan()
	check(ob.step == 3, "farm, fuel and ammo workers close steps 2 and 3")
	ob.step_age = 0.0
	Game.buildings.append({"kind": "well", "cell": Vector2i(1, 1), "built": false, "progress": 0.0})
	ob.scan()
	check(ob.step == 3, "a step stays up for STEP_MIN seconds")
	check(Save.autosave(), "Save.autosave() writes during a chapter")
	_scan()
	check(ob.step == 4, "a placed well closes step 4")

	# --- the tutorial's little horde is no first assault; a real one cuts in, the base chapter is not marked and restarts later
	Game.attack_pending = true
	Game.tutorial_wave = 8
	ob.scan() # no step_age bump: the base chapter's step stays
	check(ob.chapter == "base", "the tutorial's pending horde does not start the assault chapter")
	Game.tutorial_wave = 0
	_scan()
	check(ob.chapter == "assault" and not ob.seen("ch_base"), "the assault chapter cuts in without marking the base chapter")
	check(Save.autosave(), "Save.autosave() writes during the assault chapter")
	Game.attack_active = true
	_scan()
	check(ob.step == 1, "an active assault closes step 1")
	Game.kills += ob.KILLS_ASSAULT
	_scan()
	Game.attack_pending = false
	Game.attack_active = false
	_scan()
	check(ob.step == 3, "the assault is over: step 4, the last")
	_scan()
	ob.step_age = ob.WAIT
	ob.scan()
	check(ob.seen("ch_assault") and ob.chapter != "assault", "the assault chapter ends and is remembered")
	check(ob.chapter == "base" and ob.step == 0, "the base chapter starts again afterwards")
	ob.skip_chapter()
	check(ob.seen("ch_base") and ob.chapter == "", "skipping marks the chapter seen")
	_scan()
	check(ob.chapter == "", "seen chapters do not start again")

	# --- missions: trigger, list, near, done
	_only(["missions"])
	var m := {"id": 99, "type": "blackbox", "title": "Black box", "pos": w.BASE_POS + Vector2(300, 0), "left": 500.0, "total": 500.0}
	w.missions.open.append(m)
	_scan()
	check(ob.chapter == "missions", "an open mission starts the missions chapter")
	var panel_ui: Node = w.get_children().filter(func(c): return c.get_script() == preload("res://scripts/missions_ui.gd"))[0]
	panel_ui.panel.visible = true
	_scan()
	check(ob.step == 1, "the mission list open closes step 1")
	Game.heli.global_position = m["pos"]
	_scan()
	check(ob.step == 2, "being at the target closes step 2")
	w.missions.completed += 1
	_scan()
	check(ob.step == 3, "a done mission closes step 3")
	ob.step_age = ob.WAIT
	ob.scan()
	check(ob.seen("ch_missions"), "the missions chapter ends")
	panel_ui.panel.visible = false
	w.missions.open.clear()
	Game.heli.global_position = w.BASE_POS

	# --- the other triggers (state only): each chapter starts on its own cue and is dropped again
	var cues := {"outposts": func(): Game.world.outposts.allies["v1"] = {"uid": "v1", "name": "Test", "pos": Game.heli.global_position, "last_visit": Game.day, "stock": {"food": 0.0, "water": 0.0}},
		"convoys": func(): Game.buildings.append({"kind": "motor_pool", "cell": Vector2i(3, 3), "built": true, "progress": 90.0}),
		"wrecks": func(): Game.world.wrecks.wrecks["t2"] = {"type": "huey", "pos": Vector2.ZERO, "state": "site", "spotted": true},
		"evac": func(): Game.world.evac.announced = true}
	for id: String in cues:
		_only([id])
		cues[id].call()
		_scan()
		check(ob.chapter == id, "the %s chapter starts on its cue" % id)
		ob.skip_chapter()
	Game.world.outposts.allies.erase("v1")
	Game.buildings.pop_back()
	Game.world.wrecks.wrecks.erase("t2")
	Game.world.evac.announced = false
	for e in w.get_children().filter(func(c): return c.get_script() == ENEMY):
		e.queue_free()
	_only(["bandits"])
	var b: Node2D = w.bandits.spawn_unit("rifle", Game.heli.global_position + Vector2(100, 0), "guard", Game.heli.global_position, "test_camp2")
	_scan()
	check(ob.chapter == "bandits", "a bandit nearby starts the bandits chapter")
	b.queue_free()
	ob.skip_chapter()
	check(ob.seen("ch_bandits"), "the skipped bandits chapter is remembered")
	_only([])
	return "E%d B%d I%d S%d" % [Codex.in_category("Enemies").size(), Codex.in_category("Buildings").size(), Codex.in_category("Items").size(), Codex.in_category("Systems").size()]


func _hints() -> void:
	radio_log.clear()
	Game.passengers = 2
	Game.passengers_injured = 1
	ob.scan()
	check(ob.seen("hint_injured"), "an injured passenger brings the hint")
	check(radio_log.any(func(m): return "Injured aboard" in m), "the hint is radioed")
	check(ob.panel.visible and ob.head_label.text == "HINT", "the hint shows in the panel")
	Game.hp = Game.max_hp * 0.2 # low hull: a second hint is due, but the first one is still up
	var hints_n := func() -> int: return Array(Game.meta["onboarding"].split(",", false)).filter(func(i): return i.begins_with("hint_")).size()
	var n_hints: int = hints_n.call()
	ob.scan()
	check(hints_n.call() == n_hints and ob.text_label.text.contains("Injured"), "no new hint while one shows (hint_t > 0)")
	ob.hint_t = 0.0
	ob.scan()
	check(hints_n.call() == n_hints + 1, "the next hint once the panel is free")
	Game.hp = Game.max_hp
	ob.hint_t = 0.0
	radio_log.clear()
	Game.passengers_injured = 0
	ob.scan()
	Game.passengers_injured = 1
	ob.scan()
	check(not radio_log.any(func(m): return "Injured aboard" in m), "the hint comes only once")
	Game.passengers = 0
	# a new profile (empty list) gets it again
	_only([]) # forgets the hints, keeps the chapters out of the way
	Game.meta["onboarding"] = ""
	Game.passengers = 2
	Game.passengers_injured = 1
	radio_log.clear()
	ob.hint_t = 0.0
	ob.scan()
	check(radio_log.any(func(m): return "Injured aboard" in m), "another profile gets the hint too")
	Game.passengers = 0
	_only([])
	# rpg hint from a bandit in sight
	var hp: Vector2 = Game.heli.global_position
	var b: Node2D = main.bandits.spawn_unit("rpg", hp + Vector2(150, 0), "guard", hp, "test_camp3")
	radio_log.clear()
	ob.hint_t = 0.0
	ob.scan()
	check(radio_log.any(func(m): return "RPG gunner" in m), "an RPG gunner in sight brings the rpg hint")
	b.queue_free()
	# a hint is bound to the key text: rebinding changes the card hint
	check("[%s]" % KeyMap.text("reroll") in ob._fmt(ob.HINTS["cards"]), "hint texts follow the key bindings")


func _touch() -> void:
	Controls.touch = true
	check("tap" in ob._fmt(ob.HINTS["cards"]).to_lower() and not "[" in ob._fmt(ob.HINTS["cards"]), "touch mode shows the touch variant")
	check(ob._fmt(ob.CHAPTERS["missions"]["steps"][0]).contains("JOBS"), "the missions step names the JOBS button on touch")
	for id: String in ob.CHAPTERS:
		for s: Dictionary in ob.CHAPTERS[id]["steps"]:
			check(not ob._fmt(s).contains("{"), "chapter %s: every {action} resolves" % id)
	Controls.touch = false
	check(ob._fmt(ob.CHAPTERS["missions"]["steps"][0]).contains("["), "keyboard mode shows the key")
	for id: String in ob.CHAPTERS:
		var steps: Array = ob.CHAPTERS[id]["steps"]
		check(steps.size() >= 3 and steps.size() <= 6, "chapter %s has 3-6 steps" % id)
		for s: Dictionary in steps:
			check(s["when"] == "wait" or ob.has_method("_w_" + s["when"]), "chapter %s: condition %s exists" % [id, s["when"]])
		check(ob.has_method("_t_" + ob.CHAPTERS[id]["trigger"]), "chapter %s: trigger exists" % id)
	for id: String in ob.HINTS:
		check(ob.has_method("_h_" + ob.HINTS[id]["when"]), "hint %s: condition exists" % id)


func _toggle() -> void:
	ob.seen("x")
	Game.meta["onboarding"] = ""
	ob._end_chapter(false)
	_scan()
	check(ob.chapter != "", "a chapter is running before the toggle")
	var running: String = ob.chapter
	Settings.set_value(ob.KEY, 0)
	check(ob.chapter == "" and not ob.panel.visible, "hints off ends the chapter and hides the panel")
	check(not ob.seen("ch_" + running), "a chapter ended by the toggle is not marked seen")
	Game.meta["codex"] = ""
	main.spawn_enemy("runner", Game.heli.global_position + Vector2(80, 0))
	Game.passengers = 2
	Game.passengers_injured = 1
	radio_log.clear()
	_scan()
	check(ob.chapter == "" and not ob.panel.visible, "no chapter starts while hints are off")
	check(not radio_log.any(func(m): return "Injured aboard" in m), "no hint while hints are off")
	check(Codex.is_unlocked("z_runner"), "the codex keeps filling while hints are off")
	Game.passengers = 0
	Settings.set_value(ob.KEY, 1)
	_scan()
	check(ob.chapter != "", "hints back on: chapters start again")
	# the skip button
	ob.skip_btn.pressed.emit()
	check(ob.chapter == "" and not ob.panel.visible, "the skip button ends the chapter")


func _persist() -> void:
	ob._mark("ch_test")
	Game._load_meta()
	check(ob.seen("ch_test"), "seen chapters survive a reload of meta.json")
	check(Codex.is_unlocked("z_runner"), "codex unlocks survive a reload of meta.json")
