extends Node
## Perf overlay on phones (docs/ROADMAP3.md S4): main.gd adds this node when env SMOKE=perfphone (no base founded):
##   SMOKE=perfphone godot --headless --path . --quit-after 30000
## Under the perf flag the overlay is visible without F3 and F3 cannot hide it, its box stays clear of the touch pads, the
## COPY text has build / user agent / screen / pixel ratio and the last 20 PERF lines (JavaScriptBridge stubbed), a refused
## clipboard shows the text box, and the scenario switch builds the situation as an unranked, unsaved run.

var _bad: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	var main: Node2D = Game.world
	await get_tree().process_frame
	var keep_meta := Game.meta.duplicate()
	var plain := Perf.new() # no flag: the normal F3 overlay
	main.add_child(plain)
	check(not plain.visible and plain.copy_text_box == null and Perf.scenario == "", "without the flag: hidden, no copy button, no scenario")
	plain.free()

	OS.set_environment("PERF", "1")
	var perf := Perf.new()
	main.add_child(perf)
	await get_tree().process_frame
	check(perf.log_on and perf.visible, "perf flag: overlay visible without F3")
	var ev := InputEventAction.new()
	ev.action = "perf"
	ev.pressed = true
	perf._unhandled_input(ev)
	check(perf.visible, "F3 does not hide it under the flag")

	# touch pads and the overlay (with the fallback text box open, its biggest size) never overlap
	Settings.set_value("touch", 1)
	perf.copy_text_box.visible = true
	perf.label.text = perf.text(perf.stats())
	for i in 4:
		await get_tree().process_frame
	var touch: CanvasLayer = main.get_children().filter(func(n): return n.get_script() == load("res://scripts/touch_ui.gd"))[0]
	var mine := perf.box.get_global_rect()
	for c: Control in touch.obstacles():
		if c.is_visible_in_tree():
			check(not mine.intersects(c.get_global_rect()), "overlay %s overlaps touch control %s %s" % [mine, c.name, c.get_global_rect()])
	check(mine.position.y < 200.0 and mine.end.x < 1000.0, "overlay sits top centre: %s" % mine)
	perf.copy_text_box.visible = false
	Settings.set_value("touch", 0)

	# the last COPY_LINES lines
	for i in Perf.COPY_LINES + 5:
		perf._log_t = 0.0
		await get_tree().process_frame
	check(perf.lines.size() == Perf.COPY_LINES and perf.lines.all(func(l: String): return l.begins_with("PERF FPS")), "keeps %d PERF lines: %d" % [Perf.COPY_LINES, perf.lines.size()])

	# COPY through the (stubbed) browser: clipboard ok, then refused
	var sent: Array[String] = []
	var answer := ["ok"]
	perf.web = true
	perf.js = func(code: String) -> Variant:
		if "navigator.userAgent" in code:
			return '{"ua":"Mozilla/5.0 (TestPhone)","screen":"390x844","window":"390x700","dpr":3}'
		if code == "window.doorgunnerCopy":
			return answer[0]
		sent.append(code)
		return null
	perf.copy_lines()
	var payload := perf.copy_payload()
	var rows := payload.split("\n")
	check(rows.size() == 1 + Perf.COPY_LINES + 1, "header + %d lines + now: %d rows" % [Perf.COPY_LINES, rows.size()])
	for want in ["Doorgunner " + Game.version_text(), "Mozilla/5.0 (TestPhone)", "screen 390x844", "pixel ratio 3", "scenario none"]:
		check(want in rows[0], "header has '%s': %s" % [want, rows[0]])
	check(rows[1].begins_with("PERF FPS") and rows[-1].ends_with("(now)"), "lines then the live line")
	check(sent.size() == 1 and "writeText" in sent[0] and JSON.stringify(rows[1]).trim_prefix('"').trim_suffix('"') in sent[0], "clipboard call carries the text")
	var real_js: Callable = perf.js
	for odd in ["[1, 2]", "42", "null"]:
		perf.js = func(_code: String) -> Variant: return odd
		check("UA n/a" in perf.copy_payload().split("
")[0], "an odd browser answer reads as n/a: %s" % odd)
	perf.js = real_js
	await get_tree().process_frame
	check(perf.copy_status.text == " copied" and not perf.copy_text_box.visible, "clipboard ok: '%s'" % perf.copy_status.text)
	answer[0] = "fail"
	perf.copy_lines()
	await get_tree().process_frame
	check(perf.copy_text_box.visible and not perf.copy_text_box.editable and perf.copy_text_box.text.begins_with("Doorgunner "), "refused clipboard: selectable text box")
	check("refused" in perf.copy_status.text, "refused clipboard says so")

	# URL flag parsing (env on desktop, same code path)
	OS.set_environment("PERF_SCENARIO", "bloodmoon")
	var p2 := Perf.new()
	main.add_child(p2)
	check(Perf.scenario == "bloodmoon", "scenario read under the flag")
	p2.free()
	OS.set_environment("PERF_SCENARIO", "nonsense")
	p2 = Perf.new()
	main.add_child(p2)
	check(Perf.scenario == "", "unknown scenario ignored")
	p2.free()
	OS.set_environment("PERF_SCENARIO", "bloodmoon")
	OS.set_environment("PERF", "")
	p2 = Perf.new()
	main.add_child(p2)
	check(Perf.scenario == "", "no scenario without the perf flag")
	p2.free()
	perf.free()

	# scenarios: unranked, unsaved
	Perf.scenario = "city"
	main._perf_scenario("city")
	var city: Array = main.chunks.sites_near(main.BASE_POS, 40000.0, "city")
	if city.is_empty():
		city = main.chunks.sites_near(main.BASE_POS, 40000.0).filter(func(s): return s.kind in main.chunks.TOWN_SIZE)
	check(Game.running and not Game.heli.landed and not city.is_empty() and absf(Game.heli.position.distance_to(city[0].pos) - 1500.0) < 1.0, "city: heli 1500 px from the nearest city")
	Perf.scenario = "bloodmoon"
	main._perf_scenario("bloodmoon")
	check(Game.base_founded and Game.attack_pending and Assault.blood_moon(Game.day), "bloodmoon: base founded, blood moon due on day %d" % Game.day)
	Game.time = 0.8
	for i in 5:
		await get_tree().process_frame
	check(Game.attack_active and main.assault.blood and Assault.blood_active(), "bloodmoon: the assault is running")
	check(not Online.ranked, "the run is unranked")
	check(not Save.autosave(), "no autosave in a scenario")
	var f := FileAccess.open(Save.path(), FileAccess.WRITE) # a saved run of the player's: must survive dying here
	f.store_string("x")
	f = null
	var runs: int = Game.meta["runs"]
	Game.end_run("test")
	check(FileAccess.file_exists(Save.path()) and Game.meta["runs"] == runs, "death in a scenario keeps the saved run and the meta")
	DirAccess.remove_absolute(Save.path())
	Game.meta["perfphone_marker"] = true # an unlock inside the scenario (codex, onboarding) must not be written
	Game._save_meta()
	var mf := Game.profile_dir() + "meta.json"
	check(not FileAccess.file_exists(mf) or not "perfphone_marker" in FileAccess.get_file_as_string(mf), "a scenario never writes the meta")
	Perf.scenario = ""
	Game.meta = keep_meta
	_finish()


func _finish() -> void:
	OS.set_environment("PERF", "")
	OS.set_environment("PERF_SCENARIO", "")
	if not _bad.is_empty():
		push_error("PERFPHONE FAIL\n" + "\n".join(_bad))
		get_tree().quit(1)
		return
	print("PERFPHONE OK")
	get_tree().quit(0)
