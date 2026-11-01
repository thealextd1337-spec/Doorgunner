extends Node
## Autoload "ErrorReport" (docs/ROADMAP2.md Q2, server/supabase/008_errors.sql): script errors, push_error and engine
## errors (a Logger via OS.add_logger) and, in the browser, window.onerror are sent to the report_error RPC.
## Anonymous: message, stack, game version, platform name and - only if this profile is registered online - the same
## anonymous player id the leaderboard uses. File paths of the player's machine are scrubbed from the text.
## Every message is sent once per session; unsent reports wait in a small queue file (offline, server down, migration
## 008 not run yet) and go out later. Opt-out: ESC menu "Send crash reports" (clears the queue). Off while headless
## tests run (env SMOKE) and in editor builds; tests/errors_test.gd switches it on against tools/fake_supabase.py.
## Release exports only give GDScript backtraces with ProjectSettings debug/settings/gdscript/always_track_call_stacks
## (Q1 measures its cost); without it the stack is the single "file:line @ function" the engine reports.

const KEY := "crash_reports" ## Settings toggle
const MAX_MESSAGE := 500 ## the server cuts at the same lengths (008)
const MAX_STACK := 4000
const MAX_PER_SESSION := 30 ## distinct messages one session may report
const MAX_QUEUE := 20 ## unsent reports kept in the file (oldest dropped)
const MAX_PENDING := 100 ## captured on any thread, not yet looked at by _process
const RETRY_SECONDS := 60.0
const PAUSE_SECONDS := 3600.0 ## no sending after rate_limit or a server without the migration
const NOTICE_DELAY := 2.0
const NOTICE_SECONDS := 14.0
const NOTICE := "Doorgunner sends anonymous crash reports (error text and game version, no personal data).\nTurn it off in the settings menu (ESC): Send crash reports."

var enabled := false ## false in tests (SMOKE) and editor builds
var path := "user://error_reports.json" ## {"noticed": bool, "queue": [{message, stack}]}
var _sink: Logger
var _mutex := Mutex.new()
var _pending: Array = [] # [{message, stack}] from any thread
var _seen := {} # messages already handled this session
var _queue: Array = []
var _noticed := false
var _flushing := false
var _tick := RETRY_SECONDS
var _pause_until := 0
var _home := RegEx.new()
var _js_callback: Variant # keeps the JavaScript callback alive


class _Sink extends Logger:
	var target: Callable ## ErrorReport._capture; called from whatever thread logs

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var message := "%s  [%s:%d]" % [rationale if rationale != "" else code, file, line]
		var stack := ""
		for bt in script_backtraces:
			stack += bt.format() + "\n"
		target.call(message, stack if stack != "" else "%s:%d @ %s" % [file, line, function])


func _init() -> void:
	_sink = _Sink.new()
	_sink.target = _capture
	OS.add_logger(_sink)


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	enabled = OS.get_environment("SMOKE") == "" and not OS.has_feature("editor")
	Settings.register_toggle(KEY, "Send crash reports", true)
	Settings.changed.connect(func(key: String, _v: Variant):
		if key == KEY and not Settings.is_on(KEY):
			_queue.clear()
			_save())
	_home.compile("(?i)([a-z]:)?[\\\\/](users|home)[\\\\/][^\\\\/\\s:'\")\\]]+")
	_load()
	if OS.has_feature("web"):
		_js_callback = JavaScriptBridge.create_callback(_on_js_error)
		JavaScriptBridge.get_interface("window").onerror = _js_callback
	if not _queue.is_empty():
		_tick = 3.0 # let Online probe the server first
	if enabled:
		get_tree().create_timer(NOTICE_DELAY).timeout.connect(show_notice)


func _exit_tree() -> void:
	OS.remove_logger(_sink)


func _process(delta: float) -> void:
	_mutex.lock()
	var taken := _pending
	_pending = []
	_mutex.unlock()
	for e in taken:
		report(e["message"], e["stack"])
	_tick -= delta
	if _tick <= 0.0:
		_tick = RETRY_SECONDS
		flush()


## Count of reports waiting to be sent.
func queue_size() -> int:
	return _queue.size()


## Queues one report (once per message and session) and tries to send. Main thread only; the Logger goes through _capture.
func report(message: String, stack := "") -> void:
	if not enabled or not Settings.is_on(KEY):
		return
	message = _clean(message, MAX_MESSAGE)
	if _seen.has(message) or _seen.size() >= MAX_PER_SESSION:
		return
	_seen[message] = true
	_queue.append({"message": message, "stack": _clean(stack, MAX_STACK)})
	if _queue.size() > MAX_QUEUE:
		_queue.pop_front()
	_save()
	flush()


## Sends the queue in order. Offline stops (retried every RETRY_SECONDS); any other answer drops the report, and anything
## but a rejected report pauses sending for an hour (rate_limit, migration 008 missing).
func flush() -> void:
	if _flushing or not enabled or _queue.is_empty() or Time.get_ticks_msec() < _pause_until:
		return
	_flushing = true
	while not _queue.is_empty():
		var e: Dictionary = _queue[0]
		var r := await _send(e)
		var error: String = r["error"]
		if error == "offline":
			break
		var i := _queue.find_custom(func(q): return is_same(q, e)) # the opt-out may have cleared it meanwhile
		if i >= 0:
			_queue.remove_at(i)
		if not r["ok"] and error != "error_invalid":
			_pause_until = Time.get_ticks_msec() + int(PAUSE_SECONDS * 1000.0)
			break
	_flushing = false
	_save()


## The first-start notice (once, remembered in the queue file). Public for the test.
func show_notice() -> void:
	if _noticed or not Settings.is_on(KEY):
		return
	_noticed = true
	_save()
	var layer := CanvasLayer.new()
	layer.layer = 90
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 24)
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.PANEL
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = NOTICE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", UiTheme.SAND)
	panel.add_child(label)
	layer.add_child(panel)
	add_child(layer)
	get_tree().create_timer(NOTICE_SECONDS).timeout.connect(layer.queue_free)


## Any thread (the Logger can fire from audio or loading threads).
func _capture(message: String, stack: String) -> void:
	_mutex.lock()
	if _pending.size() < MAX_PENDING:
		_pending.append({"message": message, "stack": stack})
	_mutex.unlock()


## window.onerror(message, source, line, column, error)
func _on_js_error(args: Array) -> void:
	var source := str(args[1]).get_slice("?", 0).get_file() if args.size() > 1 else ""
	var stack := ""
	if args.size() > 4 and args[4] is JavaScriptObject:
		stack = str(args[4].stack)
	report("JS: %s  [%s:%s:%s]" % [str(args[0]) if not args.is_empty() else "", source,
		str(args[2]) if args.size() > 2 else "?", str(args[3]) if args.size() > 3 else "?"], stack)


func _send(e: Dictionary) -> Dictionary:
	var body := {"p_version": ProjectSettings.get_setting("application/config/version", "0.0.0"), "p_platform": OS.get_name(),
		"p_message": e["message"], "p_stack": e["stack"]}
	# Online's HTTP layer (token renewal, offline detection). With the player's token the row carries the anonymous
	# player id; a profile that never registered, or lost its login, reports with the anon key.
	var rpc := "/rest/v1/rpc/report_error"
	var r: Dictionary = await Online._call(HTTPClient.METHOD_POST, rpc, body, Online.is_registered())
	if r["error"] == "auth_lost":
		r = await Online._call(HTTPClient.METHOD_POST, rpc, body, false)
	return r


## No local user names or folders in what leaves the machine, then cut to the server's limit.
func _clean(text: String, limit: int) -> String:
	text = text.replace(OS.get_user_data_dir(), "user:/").replace(OS.get_user_data_dir().replace("/", "\\"), "user:/")
	text = _home.sub(text, "<home>", true)
	return text.strip_edges().left(limit)


func _load() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not d is Dictionary:
		return
	_noticed = bool(d.get("noticed", false))
	_queue.clear()
	if Settings.is_on(KEY):
		for e in d.get("queue", []):
			if e is Dictionary and e.get("message") is String:
				_queue.append({"message": e["message"], "stack": str(e.get("stack", ""))})
		_queue = _queue.slice(-MAX_QUEUE)


func _save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"noticed": _noticed, "queue": _queue}))
