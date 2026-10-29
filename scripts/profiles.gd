class_name Profiles
extends RefCounted
## Profile management on top of Game.profiles (game_state.gd, P1): rename, delete, the ENLIST rules and the link to the
## Online autoload (P6a). Everything works offline: Online answers done(false, "offline") and the title pushes again when
## online_changed(true) fires. Whether a profile is registered is Online.is_registered() (auth.json), not stored here;
## the profile only keeps `synced` {name, avatar}: what the server knows, so a rename made offline is pushed later.

const AVATARS := 12
const DEFAULT_NAME := "Gunner"

static var _busy := false # one account call at a time: Online.done carries no id


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


## This profile has a player row on the server: Online.is_registered() for the active one, else its auth.json.
static func registered(id: String) -> bool:
	if id == Game.profiles["last"]:
		return Online.is_registered()
	var path := Game.profile_dir_of(id) + "auth.json"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return d is Dictionary and d.get("registered", false)


## Removes the profile with its folder (meta.json, run.sav, auth). A registered one also leaves the server (delete_me);
## if that fails (offline) the local profile is deleted anyway and its online entry stays. Returns that error ("" ok).
## The active profile stays active; when it is deleted the first left takes over, or Game.profiles["last"] is "" when none is.
static func delete(id: String) -> String:
	var prev: String = Game.profiles["last"]
	var err := ""
	if registered(id):
		Game.switch_profile(id) # Online works on the active profile
		err = await call_online("delete_me", [], id)
		Game.profiles["last"] = prev
	var list: Array = Game.profiles["list"]
	list.assign(list.filter(func(q): return q["id"] != id))
	_remove_dir(Game.profile_dir_of(id))
	if Game.profiles["last"] == id:
		Game.profiles["last"] = list[0]["id"] if not list.is_empty() else ""
	Game._save_profiles()
	if not list.is_empty():
		Game.switch_profile(Game.profiles["last"])
	return err


static func _remove_dir(path: String) -> void:
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + f)
	for d in DirAccess.get_directories_at(path):
		_remove_dir(path + d + "/")
	DirAccess.remove_absolute(path)


## Calls Online.<method>(args) and waits for its done(ok, error). Returns "" on success, else the server's error code or
## "offline" (Online has its own request timeout, so this always answers). `id`: the profile the call is for; "switched"
## when another one became active while waiting (Online works on the active profile).
static func call_online(method: String, args: Array, id := "") -> String:
	var frame: Signal = Engine.get_main_loop().process_frame
	while _busy:
		await frame
	if id != "" and Game.profiles["last"] != id:
		return "switched"
	_busy = true
	var res := []
	Online.done.connect(func(ok: bool, error: String): res.assign([ok, error]), CONNECT_ONE_SHOT)
	Online.callv(method, args)
	while res.is_empty():
		await frame
	_busy = false
	return "" if res[0] else (res[1] if res[1] != "" else "error")


## The active profile `p` still has to reach the server: not registered yet, or renamed / new portrait while offline.
static func needs_push(p: Dictionary) -> bool:
	if not p.get("enlisted", false):
		return false
	var s: Dictionary = p.get("synced", {})
	return not Online.is_registered() or (not s.is_empty() and (s["name"] != p["name"] or s["avatar"] != p["avatar"]))


## Brings the server in line with the active profile `p`: registers it, or sends the pending rename / portrait. "" ok,
## "offline" network trouble (the profile stays local, pushed again later), else the server's error code.
static func push(p: Dictionary) -> String:
	var err := ""
	if not Online.is_registered():
		err = await call_online("register", [p["name"], p["avatar"]], p["id"])
		if err == "":
			p["synced"] = {"name": p["name"], "avatar": p["avatar"]}
	else:
		if not p.has("synced"):
			p["synced"] = {"name": p["name"], "avatar": p["avatar"]}
		var s: Dictionary = p["synced"]
		if s["name"] != p["name"]:
			err = await call_online("rename", [p["name"]], p["id"])
			if err == "":
				s["name"] = p["name"]
		if err == "" and s["avatar"] != p["avatar"]:
			err = await call_online("set_avatar", [p["avatar"]], p["id"])
			if err == "":
				s["avatar"] = p["avatar"]
	Game._save_profiles()
	return err


## Server errors that reject the player's input (the local change is undone), unlike network trouble.
static func is_input_error(code: String) -> bool:
	return code in ["name_invalid", "name_banned", "name_taken", "avatar_invalid"]
