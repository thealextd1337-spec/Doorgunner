extends Node
## Autoload "Sfx": pooled one-shots, rotor loop, ambient + music state machine (Q7), radio beeps with ducking, M mutes the master bus.
## Streams load lazily from res://assets/sfx/<name>.wav. On the web, playback silently waits for the first user gesture.

const POOL := 12
const MAX_DIST := 900.0
const MIN_REPEAT_MS := 40 # identical one-shots closer than this are skipped (gun stacking into a buzz)
const FADE_PER_SEC := 0.5 # linear volume units per second for loop crossfades
const LOOP_DB := {"wind": -18.0, "night": -18.0, "music_calm": -14.0, "music_tense": -14.0, "hover": -16.0,
	"music_combat": -16.0, "music_assault": -17.0, "music_bloodmoon": -20.0, "music_victory": -11.0, "music_title": -12.0}
# Q7 music: every stem is a 16 s loop, 120 BPM 4/4 (tools/gen_music.py), so all of them run in sync and may play together.
# A state is a set of stem volumes; a change waits for the next bar line, then fades over 1 / FADE_PER_SEC = one bar.
const MUSIC_MIX := {
	"title": {"music_title": 1.0},
	"calm": {"music_calm": 1.0},
	"tension": {"music_calm": 0.35, "music_tense": 1.0},
	"combat": {"music_tense": 1.0, "music_combat": 1.0},
	"assault": {"music_tense": 1.0, "music_combat": 1.0, "music_assault": 1.0},
	"bloodmoon": {"music_tense": 0.6, "music_combat": 1.0, "music_assault": 0.8, "music_bloodmoon": 1.0},
	"victory": {"music_victory": 1.0, "music_calm": 0.4},
}
const INTENSITY := {"calm": 0, "tension": 1, "combat": 2, "assault": 3, "bloodmoon": 4} # going down this ladder waits MUSIC_COOLDOWN
const BAR_SECONDS := 2.0
const MUSIC_COOLDOWN := 8.0 # s a calmer state must be wanted before the music follows (no flapping at the edge of a fight)
const MUSIC_STALL := 5.0 # s after which a pending change is applied without a bar line (audio not running yet, e.g. web before the first click)
const SITUATION_EVERY := 0.25 # s between looks at the game
const TENSION_DIST := 600.0 # px: any enemy this close to the heli
const COMBAT_DIST := 320.0
const COMBAT_COUNT := 3 # enemies within COMBAT_DIST
const DUCK_GAIN := 0.4 # music volume while a radio message is up
const DUCK_BASE := 1.5 # s of ducking per message plus DUCK_PER_CHAR for each character
const DUCK_PER_CHAR := 0.04
const DUCK_IN := 6.0 # full duck takes 1/DUCK_IN s to go down, 1/DUCK_OUT s to come back
const DUCK_OUT := 1.0
const BEEP_GAP_MS := 500 # radio beeps closer than this are skipped
# message prefix -> beep file; any other sender (Command, Military, Crew, ...) gets the classic "radio"
const BEEPS := {"Base": "radio_base", "Pilot": "radio_pilot", "Watchtower": "radio_tower", "Intercepted": "radio_bandit", "Radio:": "radio_bandit",
	"ALERT: bandits": "radio_bandit", "Convoy": "radio_convoy", "ALERT: Convoy": "radio_convoy", "Motor pool": "radio_convoy"}

var muted := false
var streams := {}
var players: Array[AudioStreamPlayer] = []
var rotor_player: AudioStreamPlayer
var next_idx := 0
var last_ms := {}
var loops := {} # name -> AudioStreamPlayer, always playing; volume follows loop_target
var loop_target := {}
var loop_cur := {}
var music_state := "" # applied state (MUSIC_MIX key)
var music_pending := "" # waits for the next bar line
var music_want := ""
var music_bar := -1 # bar of the reference stem last frame
var music_time := 0.0 # own clock for cooldown / stall (s)
var duck_t := 0.0 # s of ducking left
var duck := 1.0 # current music gain from ducking
var _want_since := 0.0
var _pending_since := 0.0
var _situation_cd := 0.0
var _beep_ms := 0


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # UI sounds must play while choice_ui pauses the tree
	Settings.register_toggle("radio_beeps", "Radio beeps", true)
	for bus in ["SFX", "Music"]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, "Master")
	apply_volumes()
	get_tree().node_added.connect(func(n: Node): if n is BaseButton: n.pressed.connect(_click_later))
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	rotor_player = AudioStreamPlayer.new()
	rotor_player.bus = "SFX"
	add_child(rotor_player)
	for name in LOOP_DB:
		var p := AudioStreamPlayer.new()
		p.stream = _loop_stream(name)
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		loops[name] = p
		loop_target[name] = 0.0
		loop_cur[name] = 0.0
		if p.stream != null:
			p.play()
	set_music_state("title")


func _process(delta: float) -> void:
	ambient(Game.is_night())
	music_tick(delta)
	fade_loops(delta)


## Loop volumes follow their targets (FADE_PER_SEC); music stems also carry the radio ducking.
func fade_loops(delta: float) -> void:
	for name in loops:
		var p: AudioStreamPlayer = loops[name]
		if p.stream == null:
			continue
		loop_cur[name] = move_toward(loop_cur[name], loop_target[name], delta * FADE_PER_SEC)
		p.volume_db = LOOP_DB[name] + linear_to_db(maxf(loop_cur[name], 0.001)) + (linear_to_db(duck) if name.begins_with("music_") else 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		Settings.set_value("muted", 0 if Settings.is_on("muted") else 1)
		apply_volumes()
		Game._save_meta()


## Bus volumes and mute from Settings (0..100 per bus); the settings menu and M call this.
func apply_volumes() -> void:
	for pair in [["Master", "vol_master"], ["SFX", "vol_sfx"], ["Music", "vol_music"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(Settings.get_value(pair[1]) / 100.0, 0.0001)))
	muted = Settings.is_on("muted")
	AudioServer.set_bus_mute(0, muted or OS.get_environment("SMOKE") != "") # test runs stay silent


func _stream(name: String) -> AudioStreamWAV:
	if not streams.has(name):
		var path := "res://assets/sfx/%s.wav" % name
		streams[name] = load(path) if ResourceLoader.exists(path) else null
		if streams[name] == null:
			push_warning("Sfx: missing %s" % path)
	return streams[name]


func _loop_stream(name: String) -> AudioStreamWAV:
	var s := _stream(name)
	if s != null:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate) # frames; data.size()/2 is wrong for compressed imports
	return s


## pos (Vector2 or null) only sets a distance falloff from the heli; sounds beyond MAX_DIST are dropped.
func play(name: String, pos = null, volume_db := 0.0, pitch_jitter := 0.1) -> void:
	var s := _stream(name)
	if s == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(last_ms.get(name, -MIN_REPEAT_MS)) < MIN_REPEAT_MS:
		return
	last_ms[name] = now
	if pos != null and Game.heli != null:
		var d: float = Game.heli.global_position.distance_to(pos)
		if d >= MAX_DIST:
			return
		volume_db += linear_to_db(1.0 - d / MAX_DIST)
	var p := players[next_idx]
	next_idx = (next_idx + 1) % POOL
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func rotor(on: bool, speed01: float) -> void:
	var landed: bool = on and Game.heli != null and Game.heli.landed
	loop_target["hover"] = 1.0 if landed else 0.0
	if not on:
		rotor_player.stop()
		return
	if rotor_player.stream == null:
		rotor_player.stream = _loop_stream("rotor")
		if rotor_player.stream == null:
			return
	rotor_player.pitch_scale = 0.8 if landed else lerpf(0.9, 1.3, clampf(speed01, 0.0, 1.0))
	rotor_player.volume_db = -18.0 if landed else -9.0
	if not rotor_player.playing:
		rotor_player.play()


## Crossfade targets: wind always (quiet when idle), night bed at night. The music is music_tick's job.
func ambient(night: bool) -> void:
	var running: bool = Game.running
	loop_target["wind"] = 0.4 if not running else (0.25 if night else 1.0)
	loop_target["night"] = 1.0 if running and night else 0.0


# ---- music state machine (Q7) ---------------------------------------------------------------------------------------
## The state for a situation {running, victory, blood, assault, night, alarm, near, close}; the order is the priority.
static func pick_state(s: Dictionary) -> String:
	if s.get("victory", false):
		return "victory"
	if not s.get("running", false):
		return "title"
	if s.get("blood", false):
		return "bloodmoon"
	if s.get("assault", false):
		return "assault"
	if s.get("near", 0) >= COMBAT_COUNT:
		return "combat"
	if s.get("close", 0) > 0 or s.get("night", false) or s.get("alarm", false):
		return "tension"
	return "calm"


## The game as pick_state sees it: attack, blood moon, evacuation, wear alarm, enemies around the heli.
func situation() -> Dictionary:
	var w: Node = Game.world if is_instance_valid(Game.world) else null
	var ev = w.get("evac") if w != null else null
	var wear = w.get("wear") if w != null else null
	var s := {"running": Game.running, "night": Game.is_night(), "blood": Assault.blood_active(), "near": 0, "close": 0,
		"assault": Game.attack_active or Evac.holds_assault(), "victory": ev != null and ev.phase == "choice",
		"alarm": (ev != null and ev.phase == "countdown") or (wear != null and wear.state in ["warn", "auto"])}
	if Game.running and Game.heli != null:
		var at: Vector2 = Game.heli.global_position
		for e in get_tree().get_nodes_in_group("enemies"):
			var d2: float = at.distance_squared_to(e.global_position)
			s["close"] += int(d2 <= TENSION_DIST * TENSION_DIST)
			s["near"] += int(d2 <= COMBAT_DIST * COMBAT_DIST)
	return s


## Ask for a state; it is applied on the next bar line (a calmer one only after it was wanted for MUSIC_COOLDOWN).
func request_music(state: String) -> void:
	if state != music_want:
		music_want = state
		_want_since = music_time
	var calmer: bool = INTENSITY.has(state) and INTENSITY.has(music_state) and INTENSITY[state] < INTENSITY[music_state]
	var go: bool = state != music_state and (not calmer or music_time - _want_since >= MUSIC_COOLDOWN)
	if go and music_pending != state:
		_pending_since = music_time
	music_pending = state if go else ""


## Apply a state now: stem targets follow MUSIC_MIX, stems not in it fade out.
func set_music_state(state: String) -> void:
	music_state = state
	music_want = state
	music_pending = ""
	for stem in LOOP_DB:
		if stem.begins_with("music_"):
			loop_target[stem] = MUSIC_MIX[state].get(stem, 0.0)


func music_tick(delta: float) -> void:
	music_time += delta
	_situation_cd -= delta
	if _situation_cd <= 0.0:
		_situation_cd = SITUATION_EVERY
		request_music(pick_state(situation()))
	var ref: AudioStreamPlayer = loops["music_calm"]
	var bar := int((ref.get_playback_position() + AudioServer.get_time_since_last_mix()) / BAR_SECONDS) if ref.playing else -1
	if music_pending != "" and (bar != music_bar or music_time - _pending_since > MUSIC_STALL):
		set_music_state(music_pending)
	music_bar = bar
	var ducked := duck_t > 0.0
	duck_t = maxf(duck_t - delta, 0.0)
	duck = move_toward(duck, DUCK_GAIN if ducked else 1.0, delta * (DUCK_IN if ducked else DUCK_OUT) * (1.0 - DUCK_GAIN))


# ---- radio beeps, UI clicks -------------------------------------------------------------------------------------------
## Beep file for a radio message by its sender prefix ("Base: ..." -> radio_base).
static func beep_for(msg: String) -> String:
	for prefix in BEEPS:
		if msg.begins_with(prefix):
			return BEEPS[prefix]
	return "radio"


## Game.radio calls this for every message: music ducks while it is up, the beep follows the "Radio beeps" setting.
func radio_beep(msg: String) -> void:
	duck_t = maxf(duck_t, DUCK_BASE + DUCK_PER_CHAR * msg.length())
	if Settings.is_on("radio_beeps") and Time.get_ticks_msec() >= _beep_ms:
		_beep_ms = Time.get_ticks_msec() + BEEP_GAP_MS
		play(beep_for(msg), null, -8.0)


func _click_later() -> void:
	_click.call_deferred()


## Every button clicks, unless its owner already played "ui" for the same press.
func _click() -> void:
	if Time.get_ticks_msec() - int(last_ms.get("ui", -1000)) > 100:
		play("ui_click", null, -6.0)
