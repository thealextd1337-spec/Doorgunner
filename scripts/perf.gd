class_name Perf
extends CanvasLayer
## Performance overlay (F3, action "perf") and the per-system timers behind it (docs/ROADMAP2.md Q1).
## Frame time p50/p95/max over the last WINDOW_MS, enemy/bandit/POI/chunk counts, and ms per frame spent in chunk
## generation, pathfinding and the spawner (avg / worst frame). Systems report with `Perf.add(key, t0_usec)`.
## In the web build `?perf=1` in the URL (desktop: env PERF=1) prints the same numbers as one line every LOG_EVERY s,
## which ends up in the browser console and in `window.doorgunnerPerf`. "work" is the frame time without the idle wait
## (physics, process, redraws). The static helpers also pace the zombie AI (stride/skip) and the hit effects (fx_cap).
## S4 (phones): with the perf flag the overlay is always on (top centre, clear of the touch pads) and has a COPY button that
## puts the last COPY_LINES PERF lines plus build / user agent / screen / pixel ratio on the clipboard; if the browser refuses,
## the same text shows in a selectable box. `?perf=1&scenario=bloodmoon|city` (desktop: env PERF_SCENARIO) makes main.gd start
## a run straight in that situation: unranked, never saved (Save.autosave / delete_run and Game.end_run check `scenario`).

const WINDOW_MS := 10000
const LOG_EVERY := 10.0
const REFRESH := 0.5 # s between overlay updates
const KEYS := ["chunk", "path", "spawn"]
const AI_NEAR := 400.0 # px from the heli: about the visible area at zoom 2 (640x360 world px)
const AI_CROWD := 100 # more enemies than this: the near ones think every 2nd frame too
const AI_FAR_STRIDE := 4 # off-screen enemies think every 4th frame (with the banked time)
const SLOW_MS := 33.0 # p95 frame time above this shrinks the particle and corpse caps
const FX_MIN := 0.25 # the caps never go below this share
const COPY_LINES := 20
const SCENARIOS := ["bloodmoon", "city"]

static var acc := {"chunk": 0, "path": 0, "spawn": 0} # usec spent this frame
static var fx := 1.0 # 1 while frames are fast, down to FX_MIN as p95 passes SLOW_MS (HitFx caps scale with it)
static var _frame := -1
static var _count := 0
static var scenario := "" ## S4: "bloodmoon" / "city" while the URL (or env) asks for it under the perf flag, else ""

var label: Label
var box: VBoxContainer
var copy_text_box: TextEdit # fallback when the clipboard is refused
var copy_status: Label
var lines: Array[String] = [] # the last COPY_LINES PERF lines
var web := OS.has_feature("web") # tests/perfphone_test.gd flips these two to run the JS path headless
var js := func(code: String) -> Variant: return JavaScriptBridge.eval(code)
var _copy_wait := false
var log_on := false
var _times := PackedInt64Array() # ticks_msec per sampled frame
var _ms := PackedFloat32Array() # frame time
var _cpu := PackedFloat32Array() # work: physics, process and the deferred calls (redraws) of a frame, no idle wait
var _start := 0 # usec the current frame started, 0 between frames
var _sys := {} # key -> PackedFloat32Array of ms per sampled frame
var _last := 0
var _refresh := 0.0
var _log_t := LOG_EVERY


## Adds the time since `t0_usec` (Time.get_ticks_usec()) to `key` for this frame.
static func add(key: String, t0_usec: int) -> void:
	acc[key] += Time.get_ticks_usec() - t0_usec


## Frames between two AI updates of enemy `e`: 1 near the heli, 2 there in a crowd, AI_FAR_STRIDE off screen.
static func stride(e: Node2D) -> int:
	var f := Engine.get_process_frames()
	if f != _frame:
		_frame = f
		_count = e.get_tree().get_node_count_in_group("enemies")
	if e.position.distance_squared_to(Game.heli.position) > AI_NEAR * AI_NEAR:
		return AI_FAR_STRIDE
	return 2 if _count > AI_CROWD else 1


## True when enemy `e` skips its AI this frame (staggered by instance id so the skipped ones spread over frames).
static func skip(e: Node2D) -> bool:
	return (Engine.get_process_frames() + e.get_instance_id()) % stride(e) != 0


## `n` scaled down while the game runs slow (particle and corpse caps).
static func fx_cap(n: int) -> int:
	return maxi(1, int(n * fx))


func _ready() -> void:
	layer = 120
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000 # after every other node, so its deferred call closes the frame's work time
	log_on = OS.get_environment("PERF") == "1" or web and str(js.call("new URLSearchParams(location.search).get('perf')")) == "1"
	var want := ""
	if log_on:
		want = OS.get_environment("PERF_SCENARIO") if not web else str(js.call("new URLSearchParams(location.search).get('scenario')"))
	scenario = want if want in SCENARIOS else ""
	box = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", UiTheme.SAND)
	label.add_theme_color_override("font_outline_color", UiTheme.DARK_TEXT)
	label.add_theme_constant_override("outline_size", 4)
	box.add_child(label)
	UiTheme.attach(self).add_child(box)
	if log_on: # top centre, right of the status zone and under the alert line: the touch pads sit at the bottom and right
		visible = true
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.add_theme_font_size_override("font_size", UiTheme.FONT_XS)
		box.position = Vector2(320, 76)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var copy := Button.new()
		copy.text = "COPY"
		copy.custom_minimum_size = Vector2(UiTheme.TOUCH_MIN * 2, UiTheme.TOUCH_MIN)
		copy.pressed.connect(copy_lines)
		row.add_child(copy)
		copy_status = Label.new()
		copy_status.add_theme_color_override("font_outline_color", UiTheme.DARK_TEXT)
		copy_status.add_theme_constant_override("outline_size", 4)
		row.add_child(copy_status)
		copy_text_box = TextEdit.new()
		copy_text_box.editable = false
		copy_text_box.custom_minimum_size = Vector2(560, 150)
		copy_text_box.visible = false
		box.add_child(copy_text_box)
	else: # F3 overlay, bottom right
		box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		box.offset_right = -UiTheme.MARGIN
		box.offset_bottom = -UiTheme.MARGIN
		box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for k in KEYS:
		_sys[k] = PackedFloat32Array()
	if log_on: # Q14: compare with tests/daily_test.gd WORLD_HASH (the daily promises the same world on every platform)
		var cm: GDScript = load("res://scripts/chunk_manager.gd")
		print("WORLDHASH seed %d: %d" % [cm.HASH_SEED, cm.world_hash(cm.HASH_SEED)])
	_last = Time.get_ticks_usec()
	get_tree().physics_frame.connect(_frame_start)
	get_tree().process_frame.connect(_frame_start)


func _frame_start() -> void:
	if _start == 0:
		_start = Time.get_ticks_usec()


func _close_work() -> void:
	_cpu.append((Time.get_ticks_usec() - _start) / 1000.0 if _start != 0 else 0.0)
	_start = 0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("perf") and not log_on: # with the perf flag the overlay stays
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	_times.append(now / 1000)
	_ms.append((now - _last) / 1000.0)
	_last = now
	_close_work.call_deferred() # queued after this frame's redraws (this node processes last)
	for k in KEYS:
		_sys[k].append(acc[k] / 1000.0)
		acc[k] = 0
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH
		_trim(now / 1000 - WINDOW_MS)
		var s := stats()
		fx = clampf(SLOW_MS / maxf(s["p95"], 0.001), FX_MIN, 1.0)
		if visible:
			label.text = text(s)
	_log_t -= delta
	if log_on and _log_t <= 0.0:
		_log_t = LOG_EVERY
		var line := perf_line()
		print(line)
		lines.append(line)
		if lines.size() > COPY_LINES:
			lines.pop_front()
		if web: # also readable from the page: window.doorgunnerPerf (array of lines)
			js.call("(window.doorgunnerPerf = window.doorgunnerPerf || []).push(%s)" % JSON.stringify(line))
	if _copy_wait:
		_poll_copy()


func perf_line() -> String:
	return "PERF " + text(stats()).replace("\n", " | ")


## Header (build, scenario, browser) + the last PERF lines + one with the numbers right now.
func copy_payload() -> String:
	var env := {}
	if web:
		var r = js.call("JSON.stringify({ua: navigator.userAgent, screen: screen.width + 'x' + screen.height, window: innerWidth + 'x' + innerHeight, dpr: window.devicePixelRatio})")
		var parsed = JSON.parse_string(str(r)) if r != null else null
		env = parsed if parsed is Dictionary else {} # a browser answer is untrusted: anything but an object reads as n/a
	var head := "Doorgunner %s | scenario %s | UA %s | screen %s | window %s | pixel ratio %s" % [
		Game.version_text(), scenario if scenario != "" else "none",
		env.get("ua", "n/a"), env.get("screen", "n/a"), env.get("window", "n/a"), env.get("dpr", "n/a")]
	return "\n".join([head] + lines + [perf_line() + " (now)"])


## COPY button: clipboard through the browser; refused or unavailable -> selectable text box (see _poll_copy).
func copy_lines() -> void:
	var t := copy_payload()
	print(t)
	copy_text_box.text = t
	if not web:
		DisplayServer.clipboard_set(t)
		copy_status.text = " copied"
		return
	js.call("window.doorgunnerCopy = ''; (navigator.clipboard ? navigator.clipboard.writeText(%s) : Promise.reject()).then(function() { window.doorgunnerCopy = 'ok'; }, function() { window.doorgunnerCopy = 'fail'; })" % JSON.stringify(t))
	_copy_wait = true
	copy_status.text = " ..."


func _poll_copy() -> void:
	var r := str(js.call("window.doorgunnerCopy"))
	if r == "":
		return
	_copy_wait = false
	copy_status.text = " copied" if r == "ok" else " clipboard refused: select the text below and copy it"
	copy_text_box.visible = r != "ok"


## Starts a fresh window (tests/perf_test.gd between scenarios).
func reset() -> void:
	_trim(Time.get_ticks_msec() + 1)
	_last = Time.get_ticks_usec()


func _trim(before_ms: int) -> void:
	var cut := _times.bsearch(before_ms)
	if cut > 0:
		_times = _times.slice(cut)
		_ms = _ms.slice(cut)
		_cpu = _cpu.slice(cut)
		for k in KEYS:
			_sys[k] = _sys[k].slice(cut)


## Frame time p50/p95/max (ms) and fps over the window, the counts, and avg/max ms per frame for each KEYS entry.
func stats() -> Dictionary:
	var sorted := _ms.duplicate()
	sorted.sort()
	var n := sorted.size()
	var s := {"frames": n, "fps": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0, "cpu50": 0.0, "cpu95": 0.0}
	if n > 0:
		var total := 0.0
		for v in sorted:
			total += v
		s["fps"] = n / maxf(total / 1000.0, 0.001)
		s["p50"] = sorted[n / 2]
		s["p95"] = sorted[mini(n - 1, int(n * 0.95))]
		s["max"] = sorted[n - 1]
	var cpu := _cpu.duplicate()
	cpu.sort()
	if cpu.size() > 0:
		s["cpu50"] = cpu[cpu.size() / 2]
		s["cpu95"] = cpu[mini(cpu.size() - 1, int(cpu.size() * 0.95))]
	for k in KEYS:
		var a: PackedFloat32Array = _sys[k]
		var sum := 0.0
		var top := 0.0
		for v in a:
			sum += v
			top = maxf(top, v)
		s[k] = sum / maxi(1, a.size())
		s[k + "_max"] = top
	var w: Node2D = Game.world
	s["bandits"] = get_tree().get_node_count_in_group("bandits")
	s["enemies"] = get_tree().get_node_count_in_group("enemies") - s["bandits"]
	s["pois"] = w.pois.size() if w else 0
	s["chunks"] = w.chunks.loaded.size() if w else 0
	s["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	s["mem_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	return s


func text(s: Dictionary) -> String:
	var out := "FPS %d   frame p50 %.1f  p95 %.1f  max %.1f ms   work p50 %.1f  p95 %.1f\n" % [s["fps"], s["p50"], s["p95"], s["max"], s["cpu50"], s["cpu95"]]
	out += "enemies %d  bandits %d  POIs %d  chunks %d  nodes %d  mem %.0f MB\n" % [s["enemies"], s["bandits"], s["pois"], s["chunks"], s["nodes"], s["mem_mb"]]
	out += "ms/frame avg (max): " + "  ".join(KEYS.map(func(k): return "%s %.2f (%.1f)" % [k, s[k], s[k + "_max"]]))
	return out
