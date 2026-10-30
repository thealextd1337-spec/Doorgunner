extends Node
## Autoload "Save": Ironman autosave of the running run into <profile>/run.sav (docs/ROADMAP.md P1).
## Each system registers a save hook: Save.register(key, save_fn, load_fn). save_fn() returns built-in types only
## (var_to_bytes keeps Vector2/Vector2i, no objects, no nodes), load_fn(data) restores them.
## Loading: CONTINUE sets `pending` and reloads the scene; main._ready calls load_run() before Game.new_run(), then
## every hook registered during that frame gets its data straight away, so the load order is the registration order
## (main.gd: Game -> heli -> world -> POIs -> base -> enemies -> everything else).
## Saved on landing at the base pad, at the day change, every AUTOSAVE_SECONDS and on closing, also in the middle of an
## assault (assault.gd saves the wave); never during the tutorial. Death deletes the run (Game.end_run).

const SAVE_FORMAT := 2 # 2: P7 people, P8 world generator; bump when saved data changes shape: older runs are discarded, no migration during development
const AUTOSAVE_SECONDS := 120.0
const OLD_NOTICE := "Your saved run is from an older version and cannot be continued."

var pending := false # CONTINUE pressed: main._ready loads the run instead of starting a new one
var notice := "" # shown once on the title (discarded run)
var _hooks := {} # key -> [save_fn, load_fn], in registration order
var _loading := {} # systems of the run being loaded, handed to hooks as they register this frame
var _t := AUTOSAVE_SECONDS
var _js_cbs := [] # JavaScriptBridge callbacks must stay referenced or the browser drops them


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	Game.day_changed.connect(func(_d: int): autosave.call_deferred()) # after Game._process has finished the day change
	if OS.has_feature("web"): # Godot flushes user:// to IndexedDB asynchronously: also save when the tab is hidden
		var cb = JavaScriptBridge.create_callback(_on_page_hidden)
		_js_cbs.append(cb)
		JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", cb)
		JavaScriptBridge.get_interface("window").addEventListener("pagehide", cb)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_keys()


## Keys held while the window or browser tab loses focus never get their release event: let go of all of them,
## or the heli keeps flying after an alt-tab / tab switch.
static func release_keys() -> void:
	for a in InputMap.get_actions():
		Input.action_release(a)


func _on_page_hidden(args: Array) -> void:
	if args[0].type == "pagehide" or JavaScriptBridge.eval("document.visibilityState") == "hidden":
		release_keys()
		autosave()


func _process(delta: float) -> void:
	if not Game.running or get_tree().paused:
		return
	_t -= delta
	if _t <= 0.0:
		autosave()


func register(key: String, save_fn: Callable, load_fn: Callable) -> void:
	_hooks[key] = [save_fn, load_fn]
	if _loading.has(key):
		load_fn.call(_loading[key])


func path() -> String:
	return Game.profile_dir() + "run.sav"


func has_run() -> bool:
	return FileAccess.file_exists(path()) or FileAccess.file_exists(path() + ".bak")


## Writes run.sav. False when nothing was written: no run or the tutorial running.
func autosave() -> bool:
	if not Game.running or Game.world == null or not is_instance_valid(Game.world) or is_instance_valid(Game.world.tutorial):
		return false
	_t = AUTOSAVE_SECONDS
	var systems := {}
	for key in _hooks:
		if _hooks[key][0].is_valid():
			systems[key] = _hooks[key][0].call()
	var data := {"version": ProjectSettings.get_setting("application/config/version", "0.0.0"), "format": SAVE_FORMAT,
		"saved_at": Time.get_unix_time_from_system(), "head": {"day": Game.day, "time": Game.time, "rescued": Game.saved_count(), "kills": Game.kills},
		"systems": systems}
	_write(var_to_bytes(data))
	Game._save_meta() # meta changes mid-run too (assaults held, boss kills)
	return true


## run.sav.tmp first, then the old run.sav becomes run.sav.bak and the tmp file takes its place.
func _write(bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(Game.profile_dir())
	var p := path()
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p + ".bak")
		DirAccess.rename_absolute(p, p + ".bak")
	if DirAccess.rename_absolute(p + ".tmp", p) != OK: # no rename on this file system: write in place
		f = FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		DirAccess.remove_absolute(p + ".tmp")


## The saved run ({version, format, saved_at, head, systems}), run.sav.bak if run.sav is unreadable; {} if none.
## A run of another SAVE_FORMAT is deleted and `notice` set for the title.
func read() -> Dictionary:
	for p in [path(), path() + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var data = bytes_to_var(FileAccess.get_file_as_bytes(p))
		if not data is Dictionary or not data.has("systems"):
			continue
		if data.get("format", 0) != SAVE_FORMAT:
			delete_run()
			notice = OLD_NOTICE
			return {}
		return data
	return {}


## Saved run's {day, time, rescued, kills} for the title, {} if none.
func head() -> Dictionary:
	return read().get("head", {})


## Starts loading the saved run (main._ready, before Game.new_run). False: none or outdated.
func load_run() -> bool:
	pending = false
	var data := read()
	if data.is_empty():
		return false
	_loading = data["systems"]
	for key in _hooks: # hooks registered before (autoloads) load now, the scene's hooks as they register
		if _loading.has(key) and _hooks[key][1].is_valid():
			_hooks[key][1].call(_loading[key])
	get_tree().process_frame.connect(func(): _loading = {}, CONNECT_ONE_SHOT)
	_t = AUTOSAVE_SECONDS
	return true


func delete_run() -> void:
	for p in [path(), path() + ".bak", path() + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## NEW RUN over a saved one: it counts as lost (meta progress as on death), then it is gone.
func abandon() -> void:
	var h := head()
	if not h.is_empty():
		Game.record_run(h["day"], h["rescued"], h["kills"])
	delete_run()
