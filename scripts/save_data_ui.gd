class_name SaveDataUi
extends Overlay
## BACKUP over the title (docs/ROADMAP2.md Q3): export the active profile (meta + saved run) to a file and import one as a new
## profile. Logic in cloud_save.gd. Web: download / upload through JavaScriptBridge, desktop: the native file dialog.

signal changed ## a profile was imported

var status: Label
var auth_box: CheckBox
var dialog: FileDialog
var _pending_export := PackedByteArray() # bytes waiting for the save dialog
var _js_cbs := [] # JavaScriptBridge callbacks must stay referenced or the browser drops them


func _ready() -> void:
	_build(620)
	dialog = FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.filters = PackedStringArray(["*.%s ; Doorgunner export" % CloudSave.EXT])
	dialog.file_selected.connect(_on_file)
	add_child(dialog)


func open() -> void:
	closable = true
	clear()
	box.add_child(label("// BACKUP", 13, ACCENT))
	box.add_child(label("BACKUP", 24))
	box.add_child(label("Online profiles upload their saved run to the cloud when you land at the base (at most every 5 minutes).\nThe online identity lives in this browser/device: clearing the browser data makes the cloud copy unreachable.\nAn export file keeps the profile and its run.", 12, SAND.darkened(0.2)))
	auth_box = CheckBox.new()
	auth_box.text = "Include my online login (leaderboard identity)"
	auth_box.add_theme_font_override("font", mono)
	box.add_child(auth_box)
	box.add_child(label("WARNING: with the login the file works like a password. Anyone who has it can play as you online.", 12, RED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var exp := button("EXPORT PROFILE", 0, true)
	exp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp.pressed.connect(_export)
	row.add_child(exp)
	var imp := button("IMPORT FILE", 0)
	imp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	imp.pressed.connect(_import)
	row.add_child(imp)
	box.add_child(label("An imported run is never ranked on the leaderboard. The import makes a new profile.", 12, SAND.darkened(0.2)))
	status = label("", 13, ACCENT)
	box.add_child(status)
	var close_btn := button("CLOSE", 140)
	close_btn.pressed.connect(close)
	box.add_child(close_btn)
	visible = true


func _export() -> void:
	var bytes := CloudSave.export_bytes(auth_box.button_pressed)
	var fname := "doorgunner_%s.%s" % [String(Profiles.active().get("name", "profile")).replace(" ", "_"), CloudSave.EXT]
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, fname, "application/octet-stream")
		status.text = "Exported %s (%d KB)." % [fname, bytes.size() / 1024]
		return
	_pending_export = bytes
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.current_file = fname
	dialog.popup_centered_ratio(0.6)


func _import() -> void:
	if not OS.has_feature("web"):
		_pending_export = PackedByteArray()
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.popup_centered_ratio(0.6)
		return
	var cb := JavaScriptBridge.create_callback(func(args: Array): _imported(Marshalls.base64_to_raw(str(args[0]))))
	_js_cbs.append(cb)
	JavaScriptBridge.get_interface("window").set("__dg_pick", cb)
	JavaScriptBridge.eval("(function(){var i=document.createElement('input');i.type='file';i.accept='.%s';i.onchange=function(){var f=i.files[0];if(!f)return;var r=new FileReader();r.onload=function(){window.__dg_pick(String(r.result).split(',')[1]||'');};r.readAsDataURL(f);};i.click();})()" % CloudSave.EXT)


func _on_file(path: String) -> void:
	if dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			status.text = "Could not write that file."
			return
		f.store_buffer(_pending_export)
		status.text = "Exported to %s." % path.get_file()
		return
	_imported(FileAccess.get_file_as_bytes(path))


func _imported(bytes: PackedByteArray) -> void:
	var err := CloudSave.import_bytes(bytes)
	status.text = "Imported - the run is not ranked." if err == "" else err
	status.add_theme_color_override("font_color", ACCENT if err == "" else RED)
	if err == "":
		changed.emit()
