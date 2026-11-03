extends Node
## Error reporting test (scripts/error_report.gd) against the local stub tools/fake_supabase.py, which this test starts:
##   SMOKE=errors godot --headless --path . --quit-after 30000
## Off under SMOKE by default, reported (push_error, a failed assert = script error, the browser handler), deduplicated per
## session and by the server, local paths scrubbed, opt-out, offline queue that survives a restart and flushes later, the
## player id of a registered profile, rate limit pause, first-start notice.
## The log of this test deliberately contains errors: every one of them carries "ERRORS-TEST" in its first line, so
##   grep "SCRIPT ERROR" | grep -v ERRORS-TEST
## must stay empty (the full-suite loop of docs/ROADMAP2.md).

var PORT := 20000 + OS.get_process_id() % 20000 # one stub per test process: parallel runs must not share a server
var BASE := "http://127.0.0.1:%d" % PORT

var _bad: PackedStringArray = []
var _pid := -1
var _real_path := ""


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


func _run() -> void:
	var script := ProjectSettings.globalize_path("res://tools/fake_supabase.py")
	_pid = OS.create_process("python", ["-I", script, str(PORT)])
	if _pid <= 0:
		_pid = OS.create_process("python3", ["-I", script, str(PORT)])
	if _pid <= 0 or not await _stub_up():
		push_error("ERRORS FAIL: could not start tools/fake_supabase.py (python on the PATH?)")
		_finish()
		return
	await _cases()
	_finish()


func _finish() -> void:
	if _pid > 0:
		OS.kill(_pid)
	ErrorReport.enabled = OS.get_environment("SMOKE") == ""
	ErrorReport.path = _real_path if _real_path != "" else ErrorReport.path
	Settings.set_value(ErrorReport.KEY, true) # in memory only, Settings.save() is never called here
	Online.enabled = OS.get_environment("SMOKE") == ""
	Online._forget()
	if not _bad.is_empty():
		push_error("ERRORS FAIL\n" + "\n".join(_bad))
		get_tree().quit(1)
		return
	print("ERRORS OK")
	get_tree().quit(0)


func _stub_up() -> bool:
	for i in 30:
		if (await _req(HTTPClient.METHOD_GET, "/_test"))["status"] == 200:
			return true
		await get_tree().create_timer(0.3).timeout
	return false


func _req(method: int, path: String, body := {}) -> Dictionary:
	var r := HTTPRequest.new()
	add_child(r)
	r.request(BASE + path, ["apikey: test", "Content-Type: application/json"], method, JSON.stringify(body))
	var res: Array = await r.request_completed
	r.queue_free()
	return {"status": res[1], "data": JSON.parse_string(res[3].get_string_from_utf8())}


func _errors() -> Array:
	return (await _req(HTTPClient.METHOD_GET, "/_test"))["data"]["errors"]


## The stub row whose message contains `part`, {} if none.
func _row(part: String) -> Dictionary:
	for e in await _errors():
		if part in e["message"]:
			return e
	return {}


func _wait(cond: Callable, secs := 6.0) -> bool:
	var t := 0.0
	while not await cond.call() and t < secs:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	return await cond.call()


func _arrived(part: String) -> bool:
	return not (await _row(part)).is_empty()


func _settle() -> void: # long enough for _process + one request round trip
	await get_tree().create_timer(1.0).timeout


func _cases() -> void:
	# under SMOKE the reporter is off: this error is not sent
	check(not ErrorReport.enabled, "reporter is off while SMOKE tests run")
	push_error("ERRORS-TEST ignored while disabled")
	await _settle()
	check((await _errors()).is_empty(), "nothing sent while disabled")

	# switch it on against the stub; own queue file, the player's one is never touched
	_real_path = ErrorReport.path
	ErrorReport.path = Game.profile_dir() + "error_reports_test.json"
	DirAccess.make_dir_recursive_absolute(Game.profile_dir())
	DirAccess.remove_absolute(ErrorReport.path)
	ErrorReport.enabled = true
	Online.enabled = true
	Online.url = BASE
	Online._forget()
	check(Settings.defs.has(ErrorReport.KEY) and Settings.is_on(ErrorReport.KEY), "toggle registered, default on")
	check(Settings.defs[ErrorReport.KEY]["label"] == "Send crash reports", "toggle label")

	# push_error is captured; version, platform, no player id
	push_error("ERRORS-TEST one")
	check(await _wait(_arrived.bind("ERRORS-TEST one")), "push_error reported")
	var row := await _row("ERRORS-TEST one")
	check(row.get("version") == ProjectSettings.get_setting("application/config/version"), "version sent: %s" % [row])
	check(row.get("platform") == OS.get_name() and row.get("player_id") == null and row.get("count") == 1, "platform, anonymous, count 1: %s" % [row])
	check(row.get("stack", "") != "", "stack not empty")
	check(ErrorReport.queue_size() == 0, "queue empty after sending")

	# once per session; a new session (same message) is one server row with count 2
	push_error("ERRORS-TEST one")
	await _settle()
	check((await _row("ERRORS-TEST one")).get("count") == 1, "same message twice in a session: sent once")
	ErrorReport._seen.clear()
	push_error("ERRORS-TEST one")
	check(await _wait(func(): return (await _row("ERRORS-TEST one")).get("count") == 2), "next session: server dedupes with count 2")
	var same := 0
	for e in await _errors():
		same += 1 if "ERRORS-TEST one" in e["message"] else 0
	check(same == 1, "one row for the message, got %d" % same)

	# a real script error (failed assert) goes through the same Logger
	_deliberate_script_error()
	check(await _wait(_arrived.bind("ERRORS-TEST assert")), "script error (assert) reported")

	# the browser handler (window.onerror) and path scrubbing
	ErrorReport._on_js_error(["Uncaught ERRORS-TEST js", "https://example.com/game/index.js?v=3", 12, 5, null])
	check(await _wait(_arrived.bind("ERRORS-TEST js")), "window.onerror text reported")
	var js := await _row("ERRORS-TEST js")
	check("[index.js:12:5]" in js.get("message", ""), "js source reduced to the file name: %s" % [js])
	push_error("ERRORS-TEST cannot open C:\\Users\\SecretName\\Desktop\\x.png and /home/secretname/y and " + OS.get_user_data_dir() + "/save.json")
	check(await _wait(_arrived.bind("ERRORS-TEST cannot open")), "path error reported")
	var p := await _row("ERRORS-TEST cannot open")
	check(not "SecretName" in p["message"] and not "secretname" in p["message"] and not OS.get_user_data_dir() in p["message"] and "<home>" in p["message"],
		"local paths scrubbed: %s" % [p.get("message")])

	# opt-out: nothing is queued or sent, an existing queue is dropped
	Settings.set_value(ErrorReport.KEY, false)
	push_error("ERRORS-TEST after optout")
	await _settle()
	check((await _row("ERRORS-TEST after optout")).is_empty() and ErrorReport.queue_size() == 0, "opt-out: not sent, not queued")
	Settings.set_value(ErrorReport.KEY, true)

	# offline: queued in memory and file, sent once the server is back (also after a restart = reload of the file)
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": true})
	push_error("ERRORS-TEST offline")
	await _settle()
	check(ErrorReport.queue_size() == 1, "offline: report waits in the queue")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(ErrorReport.path))
	check(saved is Dictionary and saved["queue"].size() == 1 and saved["queue"][0]["message"].begins_with("ERRORS-TEST offline"), "queue file written")
	ErrorReport._queue.clear()
	ErrorReport._load() # what the next start does
	check(ErrorReport.queue_size() == 1, "queue survives a restart")
	await _req(HTTPClient.METHOD_POST, "/_test", {"down": false})
	ErrorReport.flush()
	check(await _wait(_arrived.bind("ERRORS-TEST offline")), "queue flushed when the server is back")
	check(await _wait(func(): return ErrorReport.queue_size() == 0), "queue empty after the flush")

	# a registered profile reports with its anonymous player id
	Online.register("ErrTester", 2)
	var r: Array = await Online.done
	check(r[0], "register ok, got %s" % [r])
	push_error("ERRORS-TEST registered")
	check(await _wait(_arrived.bind("ERRORS-TEST registered")), "registered profile reported")
	check((await _row("ERRORS-TEST registered")).get("player_id") == Online.player_id() and Online.player_id() != "", "player id attached")

	# rate limit: the refused report is dropped and sending pauses
	await _req(HTTPClient.METHOD_POST, "/_test", {"err_limit": 1})
	push_error("ERRORS-TEST limited")
	await _settle()
	check(ErrorReport.queue_size() == 0 and ErrorReport._pause_until > Time.get_ticks_msec(), "rate_limit: dropped and paused")
	check((await _row("ERRORS-TEST limited")).is_empty(), "rate-limited report not stored")
	ErrorReport._pause_until = 0

	# first-start notice: shown once, remembered
	ErrorReport._noticed = false
	ErrorReport.show_notice()
	check(ErrorReport._noticed and ErrorReport.get_child_count() == 1, "notice shown")
	ErrorReport.show_notice()
	check(ErrorReport.get_child_count() == 1, "notice only once")
	check(JSON.parse_string(FileAccess.get_file_as_string(ErrorReport.path))["noticed"] == true, "notice remembered in the file")
	ErrorReport.get_child(0).queue_free()


func _deliberate_script_error() -> void:
	assert(false, "ERRORS-TEST assert")
