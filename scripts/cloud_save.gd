class_name CloudSave
extends RefCounted
## Save robustness (docs/ROADMAP2.md Q3): cloud backup of the saved run for registered profiles (server/supabase/009_cloud_save.sql)
## and export / import of a whole profile as a file. Static helpers on top of Save (the file) and Online (cloud_call).
## Wire format of both: 4 bytes little-endian raw size + zstd of var_to_bytes data (no objects: bytes_to_var only).
## Ironman: death / NEW RUN call forget() BEFORE the local file is deleted. It writes <profile>/cloud_del.json first, so a delete
## that fails (offline) is retried (flush_pending) and until it went through nothing is uploaded or offered for restore.
## An imported run is never ranked (Online.imported): its online state is replaced by {"imported": true}, nothing of it is sent.

const UPLOAD_EVERY_MSEC := 5 * 60 * 1000 # at most one upload per slot per 5 minutes (the server allows one per 30 s)
const MAX_BYTES := 2097152 # server cap of one cloud save (compressed)
const MAX_RAW := 64 << 20 # bigger sizes in a header are refused before decompressing
const MAX_IMPORT_BYTES := 16 << 20
const EXPORT_FORMAT := 1 # shape of the export file itself; the run inside is checked against Save.SAVE_FORMAT
const MAGIC := "DGEXPORT"
const EXT := "dgsave"
const NOT_EXPORT := "That is not a Doorgunner export file."
const OLD_EXPORT := "That export is from an incompatible version."
const MARKER := "cloud_del.json"

static var last_size := 0 # compressed bytes of the last upload attempt (tests, README)
static var _last_upload := {} # profile dir + slot -> ticks_msec of the last successful upload
static var _uploading := false
static var _draining := false


static func pack(raw: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


## Empty when the bytes are no pack() result.
static func unpack(bytes: PackedByteArray) -> PackedByteArray:
	if bytes.size() < 5:
		return PackedByteArray()
	var n := bytes.decode_u32(0)
	if n == 0 or n > MAX_RAW:
		return PackedByteArray()
	return bytes.slice(4).decompress(n, FileAccess.COMPRESSION_ZSTD)


## The save is a run of this build: a Dictionary with `systems` and the current SAVE_FORMAT.
static func valid_run(d: Variant) -> bool:
	return d is Dictionary and d.get("systems") is Dictionary and d.get("format", 0) == Save.SAVE_FORMAT


# --- cloud backup ----------------------------------------------------------------------------------------

## Slots whose cloud copy still has to be deleted (cloud_del.json of the profile).
static func pending_slots(dir := "") -> Array:
	var p := (dir if dir != "" else Game.profile_dir()) + MARKER
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	return d if d is Array else []


static func _set_pending(dir: String, slots: Array) -> void:
	if slots.is_empty():
		DirAccess.remove_absolute(dir + MARKER)
	else:
		_put(dir + MARKER, JSON.stringify(slots))


## Whole file written and closed (a FileAccess temporary would stay open until the function ends, unreadable before).
static func _put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


## Uploads the just written save of the active slot (Save.autosave(true), on landing at the base). Rate-limited, silent on failure.
static func upload() -> void:
	var dir := Game.profile_dir()
	var slot: String = Save.slot
	if not Online.enabled or _uploading or not Online.is_registered() or slot in pending_slots(dir):
		return
	var key := dir + slot
	if _last_upload.has(key) and Time.get_ticks_msec() - _last_upload[key] < UPLOAD_EVERY_MSEC:
		return
	var raw := FileAccess.get_file_as_bytes(Save.path())
	if raw.is_empty():
		return
	var data := pack(raw)
	last_size = data.size()
	if data.size() > MAX_BYTES:
		return
	_uploading = true
	var r: Dictionary = await Online.cloud_call("put_save", {"p_slot": slot, "p_data": Marshalls.raw_to_base64(data),
		"p_version": ProjectSettings.get_setting("application/config/version", "0.0.0"), "p_format": Save.SAVE_FORMAT})
	_uploading = false
	if r["ok"]:
		_last_upload[key] = Time.get_ticks_msec()


## Death / abandoned run: the cloud copy of `slot` goes first. The marker is written before the caller deletes the local file.
static func forget(slot: String) -> void:
	if not Online.enabled or not Online.is_registered():
		return # nothing was ever uploaded
	var dir := Game.profile_dir()
	var slots := pending_slots(dir)
	if not slot in slots:
		slots.append(slot)
		_set_pending(dir, slots)
	flush_pending()


## Sends the delete requests of the marker; what the server confirmed (or cannot have: not registered, 009 not applied) leaves it.
static func flush_pending() -> void:
	var dir := Game.profile_dir()
	if _draining or not Online.enabled or pending_slots(dir).is_empty():
		return
	_draining = true
	var frame: Signal = Engine.get_main_loop().process_frame
	while _uploading:
		await frame # an upload in flight must not land after the delete
	for slot in pending_slots(dir).duplicate():
		var r: Dictionary = await Online.cloud_call("delete_save", {"p_slot": slot})
		if Game.profile_dir() != dir or not (r["ok"] or r["error"] == "no_player" or r["status"] == 404):
			break
		var left := pending_slots(dir)
		left.erase(slot)
		_set_pending(dir, left)
	_draining = false


## Metadata {updated_at, version, format} of the cloud copy of `slot` ("" = the active one), {} if there is none, it is outdated or
## the server cannot be reached. A copy whose delete is still pending counts as gone.
static func peek(slot := "") -> Dictionary:
	slot = Save.slot if slot == "" else slot
	if not Online.enabled or not Online.is_registered() or slot in pending_slots():
		return {}
	var r: Dictionary = await Online.cloud_call("get_save", {"p_slot": slot, "p_meta_only": true})
	if r["ok"] and r["data"] is Dictionary and int(r["data"].get("format", 0)) == Save.SAVE_FORMAT:
		return r["data"]
	return {}


## Writes the cloud copy of `slot` ("" = the active one) as that slot's local save (only when there is no local one). "" ok,
## else a short reason for the title.
static func restore(slot := "") -> String:
	slot = Save.slot if slot == "" else slot
	if Save.has_run(slot):
		return "There is a local run already."
	if slot in pending_slots():
		return "That run is over."
	var r: Dictionary = await Online.cloud_call("get_save", {"p_slot": slot})
	if not r["ok"]:
		return Online.error_text(r["error"])
	if not r["data"] is Dictionary:
		return "No cloud save."
	var raw := unpack(Marshalls.base64_to_raw(str(r["data"].get("data", ""))))
	var d: Variant = bytes_to_var(raw) if not raw.is_empty() else null
	if not valid_run(d):
		return Save.OLD_NOTICE if d is Dictionary else "The cloud save is damaged."
	var keep: String = Save.slot
	Save.slot = slot # _write writes the active slot
	Save._write(raw)
	Save.slot = keep
	return ""


# --- export / import -------------------------------------------------------------------------------------

## The active profile (meta + saved run) as a file's bytes. `include_auth`: auth.json too (a password in effect, see the UI warning).
static func export_bytes(include_auth: bool) -> PackedByteArray:
	var p := Profiles.active()
	var save := PackedByteArray()
	for f in [Save.path(), Save.path() + ".bak"]:
		if save.is_empty() and FileAccess.file_exists(f):
			save = FileAccess.get_file_as_bytes(f)
	var d := {"magic": MAGIC, "export_format": EXPORT_FORMAT, "save_format": Save.SAVE_FORMAT, "slot": Save.slot,
		"version": ProjectSettings.get_setting("application/config/version", "0.0.0"), "name": p.get("name", Profiles.DEFAULT_NAME),
		"avatar": p.get("avatar", 0), "meta": Game.meta.duplicate(), "save": save}
	if include_auth and FileAccess.file_exists(Game.profile_dir() + "auth.json"):
		d["auth"] = FileAccess.get_file_as_string(Game.profile_dir() + "auth.json")
	return pack(var_to_bytes(d))


## Creates a NEW profile from an export (never touches an existing one) and makes it the active one. "" ok, else the reason.
## Its run is unranked; a run of another SAVE_FORMAT is dropped (Save.notice) but the profile is still imported.
static func import_bytes(bytes: PackedByteArray) -> String:
	if bytes.size() > MAX_IMPORT_BYTES:
		return "That file is too big."
	var raw := unpack(bytes)
	var d: Variant = bytes_to_var(raw) if not raw.is_empty() else null
	if not d is Dictionary or d.get("magic") != MAGIC:
		return NOT_EXPORT
	if d.get("export_format") != EXPORT_FORMAT:
		return OLD_EXPORT
	var pname := str(d.get("name", ""))
	var id := Profiles.create(pname if NameFilter.check(pname) == "" else Profiles.DEFAULT_NAME, clampi(int(d.get("avatar", 0)), 0, Profiles.AVATARS - 1))
	var meta := {}
	var m: Variant = d.get("meta")
	for k in Game.META_DEFAULT: # known keys of the right kind only: _load_meta converts them with int() / str()
		if m is Dictionary and m.has(k) and typeof(m[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			meta[k] = m[k]
	DirAccess.make_dir_recursive_absolute(Game.profile_dir_of(id))
	_put(Game.profile_dir_of(id) + "meta.json", JSON.stringify(meta))
	Game._load_meta()
	var a: Variant = JSON.parse_string(d["auth"]) if d.get("auth") is String else null
	if a is Dictionary and a.get("refresh_token") is String and a.get("user_id") is String:
		_put(Game.profile_dir_of(id) + "auth.json", JSON.stringify(a))
	var save: Variant = d.get("save")
	if save is PackedByteArray and not save.is_empty():
		var s: Variant = bytes_to_var(save)
		if valid_run(s):
			s["systems"]["online"] = {"imported": true}
			Save._write(var_to_bytes(s))
		else:
			Save.notice = Save.OLD_NOTICE
	return ""
