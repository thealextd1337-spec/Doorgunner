class_name Codex
extends RefCounted
## The F1 codex (docs/ROADMAP2.md Q6b): entries by category, unlocked per profile (meta.json "codex": ids, comma separated).
## Code registers entries once (Codex.register), gameplay unlocks them (Codex.unlock); ids are unique over all categories.
## The pages stay empty until Q11 fills them.

const CATEGORIES := ["Enemies", "Buildings", "Items", "Systems"]

static var entries := {} # id -> {"category", "title", "text"}, in registration order


static func register(category: String, id: String, title: String, text: String) -> void:
	assert(category in CATEGORIES, "codex category: " + category)
	assert(not entries.has(id), "codex id registered twice: " + id)
	entries[id] = {"category": category, "title": title, "text": text}


static func ids_unlocked() -> PackedStringArray:
	return PackedStringArray(Game.meta["codex"].split(",", false))


static func is_unlocked(id: String) -> bool:
	return id in ids_unlocked()


## Unlocks `id` for the active profile and saves it. True the first time (the caller may show a toast), false if known already.
static func unlock(id: String) -> bool:
	var ids := ids_unlocked()
	if id in ids:
		return false
	ids.append(id)
	Game.meta["codex"] = ",".join(ids)
	Game._save_meta()
	return true


## Registered ids of a category, in registration order.
static func in_category(category: String) -> Array:
	return entries.keys().filter(func(id: String) -> bool: return entries[id]["category"] == category)
