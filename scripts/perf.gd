class_name Perf
extends CanvasLayer
## Performance overlay (F3, action "perf") and the per-system timers behind it (docs/ROADMAP2.md Q1).
## Frame time p50/p95/max over the last WINDOW_MS, enemy/bandit/POI/chunk counts, and ms per frame spent in chunk
## generation, pathfinding and the spawner (avg / worst frame). Systems report with `Perf.add(key, t0_usec)`.
## In the web build `?perf=1` in the URL (desktop: env PERF=1) prints the same numbers as one line every LOG_EVERY s,
## which ends up in the browser console and in `window.doorgunnerPerf`. "work" is the frame time without the idle wait
## (physics, process, redraws). The static helpers also pace the zombie AI (stride/skip) and the hit effects (fx_cap).

const WINDOW_MS := 10000
const LOG_EVERY := 10.0
const REFRESH := 0.5 # s between overlay updates
const KEYS := ["chunk", "path", "spawn"]
const AI_NEAR := 400.0 # px from the heli: about the visible area at zoom 2 (640x360 world px)
const AI_CROWD := 100 # more enemies than this: the near ones think every 2nd frame too
const AI_FAR_STRIDE := 4 # off-screen enemies think every 4th frame (with the banked time)
const SLOW_MS := 33.0 # p95 frame time above this shrinks the particle and corpse caps
const FX_MIN := 0.25 # the caps never go below this share

static var acc := {"chunk": 0, "path": 0, "spawn": 0} # usec spent this frame
static var fx := 1.0 # 1 while frames are fast, down to FX_MIN as p95 passes SLOW_MS (HitFx caps scale with it)
static var _frame := -1
static var _count := 0

var label: Label
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
	label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_right = -UiTheme.MARGIN
	label.offset_bottom = -UiTheme.MARGIN
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override("font_color", UiTheme.SAND)
	label.add_theme_color_override("font_outline_color", UiTheme.DARK_TEXT)
	label.add_theme_constant_override("outline_size", 4)
	UiTheme.attach(self).add_child(label)
	for k in KEYS:
		_sys[k] = PackedFloat32Array()
	log_on = OS.get_environment("PERF") == "1" or OS.has_feature("web") \
		and str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('perf')")) == "1"
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
	if event.is_action_pressed("perf"):
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
		var line := "PERF " + text(stats()).replace("\n", " | ")
		print(line)
		if OS.has_feature("web"): # also readable from the page: window.doorgunnerPerf (array of lines)
			JavaScriptBridge.eval("(window.doorgunnerPerf = window.doorgunnerPerf || []).push(%s)" % JSON.stringify(line))


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
