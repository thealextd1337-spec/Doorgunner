class_name ProfileUi
extends Overlay
## ENLIST (name + portrait form, also RENAME) and PROFILES (switch / new / rename / delete) over the title.
## Logic lives in scripts/profiles.gd; this only draws and wires it. `changed` tells the title to refresh.

signal changed

var edit_id := "" # profile being edited, "" = new profile
var picked := 0
var busy := false
var name_edit: LineEdit
var check: Label
var ok_btn: Button
var confirm: ConfirmationDialog
var delete_id := ""
var from_list := false # the form was opened from the profile list and returns there


func _ready() -> void:
	_build(560)
	confirm = ConfirmationDialog.new()
	confirm.ok_button_text = "DELETE"
	confirm.confirmed.connect(_delete)
	add_child(confirm)


## Title entry point: the form on its own (first start / no profile left).
func enlist(id := "", forced := false) -> void:
	from_list = false
	open_form(id, forced)


## Name + portrait form. id "" creates a profile, else edits it. `forced`: no CANCEL (first start, no profile left).
func open_form(id := "", forced := false) -> void:
	edit_id = id
	closable = not forced
	var p := Profiles.find(id)
	picked = p.get("avatar", 0)
	clear()
	box.add_child(label("// ENLIST" if id == "" or not p.get("enlisted", false) else "// EDIT PROFILE", 13, ACCENT))
	box.add_child(label("CALLSIGN", 24))
	name_edit = LineEdit.new()
	name_edit.max_length = NameFilter.MAX_LEN
	name_edit.placeholder_text = "Callsign (3-16 characters)"
	name_edit.text = "" if p.is_empty() or (p["name"] == Profiles.DEFAULT_NAME and not p.get("enlisted", false)) else p["name"]
	name_edit.custom_minimum_size = Vector2(0, 40)
	name_edit.add_theme_font_override("font", mono)
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.text_changed.connect(func(_t: String): _check())
	name_edit.text_submitted.connect(func(_t: String): _submit())
	box.add_child(name_edit)
	check = label("", 13, RED)
	box.add_child(check)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var group := ButtonGroup.new()
	for i in Profiles.AVATARS:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == picked
		b.custom_minimum_size = Vector2(64, 64)
		b.icon = Profiles.avatar_tex(i)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.pressed.connect(func(): picked = i)
		grid.add_child(b)
	box.add_child(label("Your name and portrait are shown on the public leaderboard.", 12, SAND.darkened(0.2)))
	box.add_child(label("Online: your callsign is registered now." if Online.is_online() else "Offline: saved on this device, registered online later.", 12, OLIVE.lightened(0.5)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	ok_btn = button("ENLIST", 0, true)
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.pressed.connect(_submit)
	row.add_child(ok_btn)
	if closable:
		var cancel := button("CANCEL", 140)
		cancel.pressed.connect(_back)
		row.add_child(cancel)
	visible = true
	name_edit.grab_focus()
	_check()


func _check() -> void:
	var reason := NameFilter.check(name_edit.text)
	check.text = reason
	check.add_theme_color_override("font_color", RED)
	if reason == "" and name_edit.text != "":
		check.text = "Name OK"
		check.add_theme_color_override("font_color", ACCENT)
	ok_btn.disabled = reason != "" or busy


func _submit() -> void:
	if busy or NameFilter.check(name_edit.text) != "":
		return
	busy = true
	ok_btn.disabled = true
	check.text = "Contacting HQ..."
	var n := name_edit.text
	var prev: String = Game.profiles["last"]
	var id := edit_id
	var backup := Profiles.find(id).duplicate()
	if id == "":
		id = Profiles.create(n, picked) # becomes the active profile, which Online works on
	else:
		Game.switch_profile(id)
		Profiles.edit(id, n, picked)
	var p := Profiles.find(id)
	var err := await Profiles.push(p)
	if Profiles.is_input_error(err): # rejected by the server: undo the local change
		if edit_id == "":
			await Profiles.delete(id)
		else:
			var synced: Dictionary = p.get("synced", {}) # what the server knows now, may differ from the backup after a partial push
			p.clear()
			p.merge(backup)
			if not synced.is_empty():
				p["synced"] = synced
			Game._save_profiles()
		_restore(prev)
		busy = false
		check.text = Online.error_text(err)
		check.add_theme_color_override("font_color", RED)
		ok_btn.disabled = false
		return
	if edit_id != "":
		_restore(prev) # RENAME of another profile does not switch to it
	busy = false
	changed.emit()
	_back()


func _restore(prev: String) -> void:
	if prev != "" and not Profiles.find(prev).is_empty() and Game.profiles["last"] != prev:
		Game.switch_profile(prev)


func _back() -> void:
	if from_list and closable:
		open_list()
	else:
		close()


func open_list() -> void:
	closable = true
	from_list = true
	clear()
	box.add_child(label("// PROFILES", 13, ACCENT))
	box.add_child(label("PROFILES", 24))
	for p in Game.profiles["list"]:
		var active: bool = p["id"] == Game.profiles["last"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		row.add_child(portrait(p["avatar"]))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(label(p["name"], 18, ACCENT if active else SAND))
		info.add_child(label(("ACTIVE  -  " if active else "") + ("online" if Profiles.registered(p["id"]) else "local only"), 12, OLIVE.lightened(0.5)))
		row.add_child(info)
		var sel := button("ACTIVE" if active else "SELECT", 100)
		sel.disabled = active
		sel.pressed.connect(func():
			Game.switch_profile(p["id"])
			changed.emit()
			open_list())
		row.add_child(sel)
		var ren := button("RENAME", 100)
		ren.pressed.connect(func(): open_form(p["id"]))
		row.add_child(ren)
		var del := button("DELETE", 100)
		del.pressed.connect(func(): ask_delete(p["id"]))
		row.add_child(del)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	box.add_child(foot)
	var new := button("NEW PROFILE", 0, true)
	new.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new.pressed.connect(func(): open_form())
	foot.add_child(new)
	var close_btn := button("CLOSE", 140)
	close_btn.pressed.connect(close)
	foot.add_child(close_btn)
	visible = true


func ask_delete(id: String) -> void:
	delete_id = id
	var p := Profiles.find(id)
	var extra := ""
	if Profiles.registered(id):
		extra = "\nIt is removed from the leaderboard too." if Online.is_online() else "\nYou are offline: its leaderboard entry stays online."
	confirm.dialog_text = "Delete profile \"%s\"?\nIts progress and saved run are lost.%s" % [p.get("name", ""), extra]
	confirm.popup_centered()


func _delete() -> void:
	await Profiles.delete(delete_id)
	changed.emit()
	if Game.profiles["list"].is_empty():
		enlist("", true)
	else:
		open_list()
