class_name KeyMap
extends RefCounted
## Key remapping (Q6b). Every game key is an Input action from Game._setup_input(); this file lists them for the menus, remembers
## their defaults, and applies / stores the player's own bindings (settings.json key "keys": action -> ["p87", "m1", ...]).
## A binding is a physical key ("p"), a layout key ("k": by keycode) or a mouse button ("m"). A new key keeps the semantics of the
## action's default (WASD & co stay physical so AZERTY works, letter hotkeys stay by keycode).
## Like controls.gd this is input-layer code: the raw-key scan in tests/controls_test.gd skips it.

const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]
const REQUIRED := ["menu", "help"] # always keep one binding: without them there is no way back to the key screen
# [group, [[action, label], ...]]; the menus show them in this order
const GROUPS := [
	["Flying", [["move_up", "Fly up"], ["move_down", "Fly down"], ["move_left", "Fly left"], ["move_right", "Fly right"],
		["yaw_left", "Yaw left"], ["yaw_right", "Yaw right"], ["land", "Land / take off"], ["weapon_swap", "Switch gun"],
		["fire", "Fire door gun"], ["system", "Loudspeaker"], ["hook", "Hook a wreck"]]],
	["Base & map", [["found", "Found the base"], ["outpost", "Outpost: found / help"], ["protect", "Protect a village"],
		["base_menu", "Base menu"], ["missions", "Missions"], ["rotate", "Rotate blueprint"], ["place", "Place blueprint"],
		["unplace", "Remove blueprint"]]],
	["Build bar", [["slot_1", "Tool 1"], ["slot_2", "Tool 2"], ["slot_3", "Tool 3"], ["slot_4", "Tool 4"], ["slot_5", "Tool 5"],
		["slot_6", "Tool 6"], ["slot_7", "Tool 7"], ["slot_8", "Tool 8"], ["slot_9", "Tool 9"]]],
	["Cards", [["reroll", "Level-up: reroll"], ["skip", "Level-up: skip"], ["banish", "Level-up: banish"]]],
	["Menus", [["menu", "ESC menu"], ["help", "Help & codex"], ["perf", "Performance overlay"], ["mute", "Mute"],
		["leaderboard", "Leaderboard"], ["hangar", "Hangar (title)"], ["start", "Start (title)"], ["restart", "Restart"]]],
]

static var defaults := {} # action -> Array[InputEvent], taken after Game._setup_input()
static var physical := {} # action -> true if its default keys are physical keys


static func actions() -> Array:
	var out := []
	for g in GROUPS:
		out.append_array(g[1].map(func(a): return a[0]))
	return out


static func label_of(action: String) -> String:
	for g in GROUPS:
		for a in g[1]:
			if a[0] == action:
				return a[1]
	return action


static func capture_defaults() -> void:
	for a in actions():
		defaults[a] = InputMap.action_get_events(a).map(func(e: InputEvent) -> InputEvent: return e.duplicate())
		physical[a] = defaults[a].any(func(e): return e is InputEventKey and e.physical_keycode != 0)


## The stored bindings of settings.json over the defaults (once at boot, and after a settings reload).
static func apply_saved() -> void:
	var saved = Settings.get_extra("keys", {})
	for a in actions():
		var evs: Array = defaults[a]
		if saved is Dictionary and saved.get(a) is Array:
			evs = saved[a].map(decode).filter(func(e): return e != null)
		_apply(a, evs)


static func events_of(action: String) -> Array:
	return InputMap.action_get_events(action)


static func is_default(action: String) -> bool:
	var cur := events_of(action).map(encode)
	return cur == defaults[action].map(encode)


## Replaces the bindings of `action` and saves settings.json at once (closing the window from the key screen keeps them).
## False (nothing changes) when it would leave a REQUIRED action unbound.
static func set_bindings(action: String, events: Array) -> bool:
	if events.is_empty() and action in REQUIRED:
		return false
	_apply(action, events)
	var saved = Settings.get_extra("keys", {})
	saved = saved.duplicate() if saved is Dictionary else {}
	if is_default(action):
		saved.erase(action)
	else:
		saved[action] = events.map(encode)
	Settings.set_extra("keys", saved)
	Settings.save()
	Input.action_release(action)
	return true


static func reset() -> void:
	Settings.set_extra("keys", {})
	Settings.save()
	apply_saved()


static func _apply(action: String, events: Array) -> void:
	InputMap.action_erase_events(action)
	for e in events:
		InputMap.action_add_event(action, e)


## The event to bind when the player pressed `raw` for `action`: null for modifier-only keys and everything but keys / mouse buttons.
static func binding_for(action: String, raw: InputEvent) -> InputEvent:
	if raw is InputEventMouseButton:
		var mb := InputEventMouseButton.new()
		mb.button_index = raw.button_index
		return mb
	if raw is InputEventKey and not raw.keycode in MODIFIERS:
		var k := InputEventKey.new()
		if physical[action]:
			k.physical_keycode = raw.physical_keycode
		else:
			k.keycode = raw.keycode
		return k if k.physical_keycode != 0 or k.keycode != 0 else null
	return null


static func encode(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		return "m%d" % e.button_index
	return "p%d" % e.physical_keycode if e.physical_keycode != 0 else "k%d" % e.keycode


static func decode(s: Variant) -> InputEvent:
	if not s is String or s.length() < 2 or not s.substr(1).is_valid_int():
		return null
	var n: int = s.substr(1).to_int()
	match s[0]:
		"m":
			var mb := InputEventMouseButton.new()
			mb.button_index = n
			return mb
		"p":
			var kp := InputEventKey.new()
			kp.physical_keycode = n
			return kp
		"k":
			var kk := InputEventKey.new()
			kk.keycode = n
			return kk
	return null


## Layout key code of a key event (a physical key mapped through the current layout; headless has no layout, then the key itself).
static func logical(e: InputEventKey) -> int:
	if e.physical_keycode == 0:
		return e.keycode
	var k: int = 0 if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(e.physical_keycode)
	return k if k != 0 else e.physical_keycode


static func same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventMouseButton:
		return b is InputEventMouseButton and a.button_index == b.button_index
	return a is InputEventKey and b is InputEventKey and logical(a) == logical(b)


static func event_text(e: InputEvent) -> String:
	if e is InputEventMouseButton:
		return {MOUSE_BUTTON_LEFT: "Mouse left", MOUSE_BUTTON_RIGHT: "Mouse right", MOUSE_BUTTON_MIDDLE: "Mouse middle"}.get(e.button_index, "Mouse %d" % e.button_index)
	return e.as_text_physical_keycode() if e.physical_keycode != 0 else e.as_text_keycode()


## "W / Up", "Mouse left"; "-" when unbound.
static func text(action: String) -> String:
	var evs := events_of(action)
	return " / ".join(evs.map(event_text)) if not evs.is_empty() else "-"


## "[K]": the current keys of `action` for the live key hints (HUD hint line, outposts, base menu toggle).
static func tag(action: String) -> String:
	return "[%s]" % text(action)


## Labels of the other actions that share a key with `action` although the defaults do not share it (R is restart, rotate and reroll
## on purpose: they work in different places).
static func conflicts(action: String) -> Array:
	var out := []
	for other in actions():
		if other == action:
			continue
		for e in events_of(action):
			if events_of(other).any(func(f): return same(e, f) and not (_is_default_event(action, e) and _is_default_event(other, f))):
				out.append(label_of(other))
				break
	return out


static func _is_default_event(action: String, e: InputEvent) -> bool:
	return defaults[action].any(func(d): return same(d, e))
