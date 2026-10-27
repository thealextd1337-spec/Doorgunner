extends Node
## Autoload "Game": run resources, day clock, upgrade stats, meta progression.

signal level_up(level: int)
signal day_changed(day: int)
signal base_attack_started(day: int)
signal run_ended(reason: String)
signal radio_message(msg: String)

const DAY_SECONDS := 300.0
const ATTACK_EVERY_DAYS := 3
const META_PATH := "user://meta.json"

var heli: Node2D
var world: Node2D
var seed := 0
var running := false

# run resources
var fuel := 100.0
var max_fuel := 100.0
var ammo := 200
var max_ammo := 200
var hp := 100.0
var max_hp := 100.0
var seats := 4
var passengers := 0
var scrap := 0
var xp := 0
var level := 1
var day := 1
var time := 0.25 # 0..1 fraction of a day, 0 = midnight
var rescued := 0
var kills := 0
var base_hp := 500.0
var max_base_hp := 500.0
var attack_pending := false
var attack_active := false
var base_level := {} # upgrade id -> level

# multipliers / flat stats changed by upgrades
var stats := {
	"damage": 1.0, "fire_rate": 1.0, "speed": 1.0, "fuel_eff": 1.0,
	"armor": 1.0, "pierce": 0, "shots": 1, "bullet_speed": 1.0, "xp_gain": 1.0,
}

var meta := {"total_rescued": 0, "runs": 0, "best_day": 0, "total_kills": 0}


func _ready() -> void:
	_setup_input()
	_load_meta()


func new_run() -> void:
	seed = randi()
	fuel = 100.0; max_fuel = 100.0
	ammo = 200; max_ammo = 200
	hp = 100.0; max_hp = 100.0
	seats = 4; passengers = 0
	scrap = 0; xp = 0; level = 1
	day = 1; time = 0.25
	rescued = 0; kills = 0
	base_hp = 500.0; max_base_hp = 500.0
	attack_pending = false; attack_active = false
	base_level = {}
	for k in stats.keys():
		stats[k] = 1.0 if typeof(stats[k]) == TYPE_FLOAT else 0
	stats["shots"] = 1
	_apply_meta_bonus()
	running = true


## Permanent bonuses from survivors rescued in earlier runs.
func _apply_meta_bonus() -> void:
	var r: int = meta["total_rescued"]
	seats += r / 25
	max_fuel += (r / 10) * 5.0
	fuel = max_fuel
	max_ammo += (r / 10) * 20
	ammo = max_ammo
	max_hp += (r / 20) * 10.0
	hp = max_hp


func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	time += delta / DAY_SECONDS
	if time >= 1.0:
		time -= 1.0
		day += 1
		day_changed.emit(day)
		if day % ATTACK_EVERY_DAYS == 0:
			attack_pending = true
			radio("Intel: hive activity rising. Expect an assault on the base tonight.")
	if attack_pending and time >= 0.8:
		attack_pending = false
		attack_active = true
		base_attack_started.emit(day)
		radio("ALERT: base under attack! Return and defend!")


func is_night() -> bool:
	return time > 0.8 or time < 0.2


## 0 = full daylight, 1 = darkest night.
func darkness() -> float:
	if time < 0.2:
		return 1.0 - time / 0.2
	if time > 0.8:
		return (time - 0.8) / 0.2
	return 0.0


## Threat scaling by distance from base and day count.
func danger_at(pos: Vector2) -> float:
	return 1.0 + pos.length() / 1500.0 + (day - 1) * 0.15


func add_xp(amount: int) -> void:
	xp += int(amount * stats["xp_gain"])
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		level_up.emit(level)


func xp_needed() -> int:
	return 20 + level * 12


func radio(msg: String) -> void:
	radio_message.emit(msg)


func end_run(reason: String) -> void:
	if not running:
		return
	running = false
	meta["runs"] += 1
	meta["total_rescued"] += rescued
	meta["total_kills"] += kills
	meta["best_day"] = max(meta["best_day"], day)
	_save_meta()
	run_ended.emit(reason)


func _load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var f := FileAccess.open(META_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in meta.keys():
			if data.has(k):
				meta[k] = int(data[k])


func _save_meta() -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))


func _setup_input() -> void:
	var keys := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"land": [KEY_SPACE], "interact": [KEY_E], "restart": [KEY_R],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)
