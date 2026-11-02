extends Node
## Autoload `Settings`: global options (user://settings.json, not per profile). Every package adds its option with ONE
## register_* call (from its autoload or a node created before main.gd builds settings_ui); the ESC menu builds a row
## per key in registration order and settings.json stores every registered key.
## Values keep the old settings.json format: toggles are int 0/1, sliders snapped to their step (int for whole steps).

signal changed(key: String, value: Variant)

var path := "user://settings.json"
var defs := {} # key -> {"kind": "toggle"/"slider", "label", "default", "min", "max", "step"}
var values := {}
var _file := {} # settings.json as read; keys nobody registered (yet) are written back unchanged


func _init() -> void:
	load_file()
	register_slider("vol_master", "Master", 0, 100, 1, 100)
	register_slider("vol_sfx", "Effects", 0, 100, 1, 100)
	register_slider("vol_music", "Music & ambience", 0, 100, 1, 70)
	register_toggle("muted", "Mute all  (M)", true) # sound off by default for now; M or ESC menu turns it on
	register_toggle("shake", "Screen shake (heavy guns)", true)


func register_toggle(key: String, label: String, default: bool) -> void:
	_register(key, {"kind": "toggle", "label": label, "default": int(default)})


func register_slider(key: String, label: String, min_value: float, max_value: float, step: float, default: float) -> void:
	_register(key, {"kind": "slider", "label": label, "default": default, "min": min_value, "max": max_value, "step": step})


func _register(key: String, def: Dictionary) -> void:
	assert(not defs.has(key), "setting registered twice: " + key)
	defs[key] = def
	values[key] = _coerce(key, _file.get(key, def["default"]))


func get_value(key: String) -> Variant:
	return values[key]


func is_on(key: String) -> bool:
	return values[key] == 1


func set_value(key: String, value: Variant) -> void:
	values[key] = _coerce(key, value)
	changed.emit(key, values[key])


## Bools and JSON floats back to the registered type, sliders clamped to their range and snapped like the HSlider.
func _coerce(key: String, v: Variant) -> Variant:
	var def: Dictionary = defs[key]
	if def["kind"] == "toggle":
		return 1 if (v is bool and v) or (not v is bool and int(v) != 0) else 0
	var x := clampf(def["min"] + snappedf(float(v) - def["min"], def["step"]), def["min"], def["max"])
	return int(x) if is_equal_approx(def["step"], roundf(def["step"])) else x


func load_file() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	_file = data if data is Dictionary else {}
	for key in defs:
		values[key] = _coerce(key, _file.get(key, defs[key]["default"]))


## Free-form data that is neither toggle nor slider (the key bindings, keymap.gd): kept under `key` in settings.json.
func get_extra(key: String, default: Variant) -> Variant:
	return _file.get(key, default)


func set_extra(key: String, value: Variant) -> void:
	_file[key] = value


func save() -> void:
	_file.merge(values, true)
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(_file))
