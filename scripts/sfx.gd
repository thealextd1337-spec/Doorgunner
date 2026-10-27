extends Node
## Autoload "Sfx": pooled one-shot players, rotor loop, M mutes the master bus.
## Streams load lazily from res://assets/sfx/<name>.wav. On the web, playback silently waits for the first user gesture.

const POOL := 12
const MAX_DIST := 900.0

var muted := false
var streams := {}
var players: Array[AudioStreamPlayer] = []
var rotor_player: AudioStreamPlayer
var next_idx := 0


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS # UI sounds must play while choice_ui pauses the tree
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	rotor_player = AudioStreamPlayer.new()
	add_child(rotor_player)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		muted = not muted
		AudioServer.set_bus_mute(0, muted)


func _stream(name: String) -> AudioStreamWAV:
	if not streams.has(name):
		var path := "res://assets/sfx/%s.wav" % name
		streams[name] = load(path) if ResourceLoader.exists(path) else null
		if streams[name] == null:
			push_warning("Sfx: missing %s" % path)
	return streams[name]


## pos (Vector2 or null) only sets a distance falloff from the heli; sounds beyond MAX_DIST are dropped.
func play(name: String, pos = null, volume_db := 0.0, pitch_jitter := 0.1) -> void:
	var s := _stream(name)
	if s == null:
		return
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
	if not on:
		rotor_player.stop()
		return
	if rotor_player.stream == null:
		var s := _stream("rotor")
		if s == null:
			return
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = s.data.size() / 2 # 16-bit mono: 2 bytes per frame
		rotor_player.stream = s
	var landed: bool = Game.heli != null and Game.heli.landed
	rotor_player.pitch_scale = 0.8 if landed else lerpf(0.9, 1.3, clampf(speed01, 0.0, 1.0))
	rotor_player.volume_db = -18.0 if landed else -9.0
	if not rotor_player.playing:
		rotor_player.play()
