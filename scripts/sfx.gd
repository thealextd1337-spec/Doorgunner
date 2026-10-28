extends Node
## Autoload "Sfx": pooled one-shot players, rotor loop, ambient/music crossfades, M mutes the master bus.
## Streams load lazily from res://assets/sfx/<name>.wav. On the web, playback silently waits for the first user gesture.

const POOL := 12
const MAX_DIST := 900.0
const MIN_REPEAT_MS := 40 # identical one-shots closer than this are skipped (gun stacking into a buzz)
const FADE_PER_SEC := 0.5 # linear volume units per second for loop crossfades
const LOOP_DB := {"wind": -18.0, "night": -18.0, "music_calm": -14.0, "music_tense": -14.0, "hover": -16.0}

var muted := false
var streams := {}
var players: Array[AudioStreamPlayer] = []
var rotor_player: AudioStreamPlayer
var next_idx := 0
var last_ms := {}
var loops := {} # name -> AudioStreamPlayer, always playing; volume follows loop_target
var loop_target := {}
var loop_cur := {}


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # UI sounds must play while choice_ui pauses the tree
	for bus in ["SFX", "Music"]:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, "Master")
	apply_volumes()
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


func _process(delta: float) -> void:
	ambient(Game.is_night(), Game.attack_active)
	for name in loops:
		var p: AudioStreamPlayer = loops[name]
		if p.stream == null:
			continue
		loop_cur[name] = move_toward(loop_cur[name], loop_target[name], delta * FADE_PER_SEC)
		p.volume_db = LOOP_DB[name] + linear_to_db(maxf(loop_cur[name], 0.001))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		Game.meta["muted"] = 0 if Game.meta["muted"] == 1 else 1
		apply_volumes()
		Game._save_meta()


## Bus volumes and mute from Game.meta (0..100 per bus); the settings menu and M call this.
func apply_volumes() -> void:
	for pair in [["Master", "vol_master"], ["SFX", "vol_sfx"], ["Music", "vol_music"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(Game.meta[pair[1]] / 100.0, 0.0001)))
	muted = Game.meta["muted"] == 1
	AudioServer.set_bus_mute(0, muted)


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


## Crossfade targets: wind always (quiet when idle), night bed at night, music only while running.
func ambient(night: bool, tense: bool) -> void:
	var running: bool = Game.running
	loop_target["wind"] = 0.4 if not running else (0.25 if night else 1.0)
	loop_target["night"] = 1.0 if running and night else 0.0
	loop_target["music_calm"] = 1.0 if running and not tense else 0.0
	loop_target["music_tense"] = 1.0 if running and tense else 0.0
