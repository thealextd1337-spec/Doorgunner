class_name Profiles
extends RefCounted
## Profile management on top of Game.profiles (game_state.gd, P1): rename, delete, the ENLIST rules and the guarded
## link to the Online autoload (P6a). Everything works offline; online calls are skipped when /root/Online is missing.

const AVATARS := 12
const DEFAULT_NAME := "Gunner"


static var fake: Node # tests stand in for Online

## The Online autoload or null (not built yet / disabled).
static func online() -> Node:
	if fake:
		return fake
	return Engine.get_main_loop().root.get_node_or_null("Online")


static func is_online() -> bool:
	var o := online()
	return o != null and o.is_online()


static func find(id: String) -> Dictionary:
	for p in Game.profiles["list"]:
		if p["id"] == id:
			return p
	return {}


static func active() -> Dictionary:
	return find(Game.profiles["last"])


static func avatar_tex(avatar: int) -> Texture2D:
	return Art.tex("avatar_%02d" % clampi(avatar, 0, AVATARS - 1))


## The migrated / auto-created "Gunner" that was never named by the player: the title opens ENLIST for it.
static func needs_enlist() -> bool:
	var p := active()
	return p.is_empty() or (p["name"] == DEFAULT_NAME and not p.get("enlisted", false) and Game.meta["runs"] == 0 and not Save.has_run())


## New profile through the game state, marked as player-chosen. Returns its id.
static func create(pname: String, avatar: int) -> String:
	var id := Game.create_profile(pname, avatar)
	find(id)["enlisted"] = true
	Game._save_profiles()
	return id


## Name and portrait of an existing profile (the first-start Gunner, or RENAME).
static func edit(id: String, pname: String, avatar: int) -> void:
	var p := find(id)
	p["name"] = pname
	p["avatar"] = avatar
	p["enlisted"] = true
	Game._save_profiles()


## Removes the profile with its folder (meta.json, run.sav, auth). A registered one also leaves the server (delete_me, only
## when online). The active one falls back to the first that is left, or Game.profiles["last"] is "" when none is left.
static func delete(id: String) -> void:
	var p := find(id)
	if p.get("registered", false) and is_online():
		Game.switch_profile(id) # Online works on the active profile
		await call_online("delete_me", [])
	var list: Array = Game.profiles["list"]
	list.assign(list.filter(func(q): return q["id"] != id))
	_remove_dir(Game.profile_dir_of(id))
	if Game.profiles["last"] == id:
		Game.profiles["last"] = list[0]["id"] if not list.is_empty() else ""
	Game._save_profiles()
	if not list.is_empty():
		Game.switch_profile(Game.profiles["last"])


static func _remove_dir(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + f)
	for d in DirAccess.get_directories_at(path):
		_remove_dir(path + d + "/")
	DirAccess.remove_absolute(path)


## Calls Online.<method>(args) and waits for its done(ok, error) signal. Returns "" on success, the server's error code,
## "offline" without Online or a connection, "timeout" when no answer comes within TIMEOUT seconds.
const TIMEOUT := 10.0

static func call_online(method: String, args: Array) -> String:
	var o := online()
	if o == null or not o.is_online():
		return "offline"
	var st := {"done": false, "error": ""}
	var cb := func(ok: bool, error: String):
		st["done"] = true
		st["error"] = "" if ok else (error if error != "" else "error")
	o.done.connect(cb, CONNECT_ONE_SHOT)
	o.callv(method, args)
	var tree := Engine.get_main_loop() as SceneTree
	var t0 := Time.get_ticks_msec()
	while not st["done"] and Time.get_ticks_msec() - t0 < TIMEOUT * 1000.0:
		await tree.process_frame
	if not st["done"]:
		if o.done.is_connected(cb):
			o.done.disconnect(cb)
		return "timeout"
	return st["error"]


## Brings the server in line with the active profile `p` (`old` = name/avatar before an edit). "" ok, "offline"/"timeout"
## network trouble (the profile stays local, `registered` false, retried by the title), else the server's error code.
static func push(p: Dictionary, old: Dictionary = {}) -> String:
	var err := ""
	if not p.get("registered", false):
		err = await call_online("register", [p["name"], p["avatar"]])
		if err == "" or err == "already_registered":
			p["registered"] = true
			err = ""
	else:
		if old.has("name") and old["name"] != p["name"]:
			err = await call_online("rename", [p["name"]])
		if err == "" and old.has("avatar") and old["avatar"] != p["avatar"]:
			err = await call_online("set_avatar", [p["avatar"]])
	Game._save_profiles()
	return err


## Server errors that reject the player's input (the local change is undone), unlike network trouble.
static func is_input_error(code: String) -> bool:
	return code in ["name_invalid", "name_banned", "name_taken", "avatar_invalid"]


## Error codes of server/README.md as player text.
static func error_text(code: String) -> String:
	return {"name_invalid": "That name is not valid.", "name_banned": "That name is not allowed.",
		"name_taken": "That name is taken, pick another one.", "avatar_invalid": "That portrait is not valid.",
		"offline": "Offline: saved on this device, it will be registered online later.",
		"timeout": "No answer from the server: saved on this device, it will be registered online later."}.get(code, "Online error: %s" % code)
