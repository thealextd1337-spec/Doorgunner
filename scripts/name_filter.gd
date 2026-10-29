class_name NameFilter
extends RefCounted
## Client-side check of a player name. Mirrors the server's name_ok() (server/supabase), which stays authoritative:
## lowercase, unaccent, leetspeak map, drop non-letters, substring match against data/banned_words.txt after
## cutting out the data/allowed_words.txt exceptions. Also the name rules (3-16 chars, [A-Za-z0-9 _-], no double spaces)
## and the number codes 88 / 1488 as their own rule.

const MIN_LEN := 3
const MAX_LEN := 16
const BANNED_PATH := "res://data/banned_words.txt"
const ALLOWED_PATH := "res://data/allowed_words.txt"
const ACCENTS := {"ä": "a", "ö": "o", "ü": "u", "ß": "ss", "à": "a", "á": "a", "â": "a", "ã": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ù": "u", "ú": "u", "û": "u", "ý": "y", "ÿ": "y"}
const LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}

static var _banned: PackedStringArray
static var _allowed: PackedStringArray # longest first
static var _loaded := false


## "" if the name is acceptable, else the reason (English, shown to the player).
static func check(name: String) -> String:
	if name.length() < MIN_LEN or name.length() > MAX_LEN:
		return "Name must be %d-%d characters." % [MIN_LEN, MAX_LEN]
	for c in name:
		if not (c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-"):
			return "Only letters, digits, space, _ and - are allowed."
	if "  " in name:
		return "No double spaces."
	if name != name.strip_edges():
		return "No spaces at the start or end."
	if name.replace(" ", "").replace("_", "").replace("-", "") == "":
		return "Use at least one letter or digit."
	var digits := ""
	for c in name:
		if c >= "0" and c <= "9":
			digits += c
	if "1488" in digits or _has_word(name, "88"):
		return "That number code is not allowed."
	_load()
	var s := normalize(name)
	for a in _allowed:
		s = s.replace(a, "|") # separator, so cutting a word out cannot join its neighbours into a banned one
	for b in _banned:
		if b in s:
			return "That name is not allowed."
	return ""


## Same steps as the server: lowercase, unaccent, leetspeak, keep a-z only.
static func normalize(text: String) -> String:
	var out := ""
	for c in text.to_lower():
		for d in String(ACCENTS.get(c, c)): # ß expands to two letters
			var e: String = LEET.get(d, d)
			if e >= "a" and e <= "z":
				out += e
	return out


## Whole word between spaces, '_' or '-', like the server's regexp_split_to_table(n, '[ _-]+').
static func _has_word(text: String, word: String) -> bool:
	for sep in ["_", "-"]:
		text = text.replace(sep, " ")
	return word in text.split(" ", false)


## Word list files: one word per line, '#' comments, '[lang]' section headers (ignored here, used by the SQL generator).
static func read_words(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("name filter: cannot read %s" % path)
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#") or line.begins_with("["):
			continue
		var w := normalize(line)
		if w.length() >= MIN_LEN and not w in out:
			out.append(w)
	return out


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_banned = read_words(BANNED_PATH)
	var allowed := Array(read_words(ALLOWED_PATH))
	allowed.sort_custom(func(a: String, b: String): return a.length() > b.length())
	_allowed = PackedStringArray(allowed)
