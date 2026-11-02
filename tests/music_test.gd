extends Node
## Music and sound test (Q7): SMOKE=music godot --headless --path . --quit-after 30000
## Every sound file is there and loads, the stems share one length (tempo), pick_state per situation, the state machine
## (changes wait for a bar line, calmer states wait out the cooldown), crossfades between every pair of states never go
## silent and finish within one bar, radio ducking, the beep per sender and the "Radio beeps" switch, UI clicks.

const SFX := ["gun", "hit", "enemy_die", "boss_roar", "explosion", "pickup", "board", "levelup", "radio", "alarm", "land", "takeoff", "ui", "base_hit",
	"weapon_swap", "survivor_lost", "town_alarm", "rotor", "hover", "wind", "night", "radio_base", "radio_pilot", "radio_tower", "radio_bandit",
	"radio_convoy", "rpg_warn", "autorot", "build", "build_done", "ui_click", "event"]

var _bad: PackedStringArray = []


func _ready() -> void:
	call_deferred("_run")


func check(cond: bool, msg: String) -> void:
	if not cond:
		_bad.append(msg)


## Sum of the music stems' current (or, with targets, wanted) volumes.
func _total(dict: Dictionary) -> float:
	var t := 0.0
	for name in dict:
		if name.begins_with("music_"):
			t += dict[name]
	return t


func _faded() -> bool:
	return Sfx.loop_cur.keys().all(func(k): return Sfx.loop_cur[k] == Sfx.loop_target[k])


## Settle every loop at the targets of `state`.
func _settle(state: String) -> void:
	Sfx.set_music_state(state)
	for name in Sfx.loop_cur:
		Sfx.loop_cur[name] = Sfx.loop_target[name]


func _bar_of_ref() -> int:
	var ref: AudioStreamPlayer = Sfx.loops["music_calm"]
	return int((ref.get_playback_position() + AudioServer.get_time_since_last_mix()) / Sfx.BAR_SECONDS)


func _run() -> void:
	await get_tree().process_frame
	Sfx.set_process(false) # the test drives the state machine itself
	Sfx._situation_cd = 1.0e9
	# --- files -------------------------------------------------------------------------------------------------
	var stems: Array = Sfx.LOOP_DB.keys().filter(func(k): return k.begins_with("music_"))
	check(stems.size() == 7, "seven music stems: %s" % [stems])
	check(Sfx.MUSIC_MIX.keys().all(func(st): return Sfx.MUSIC_MIX[st].keys().all(func(k): return k in stems)), "MUSIC_MIX only names stems")
	for n in SFX + stems:
		var path := "res://assets/sfx/%s.wav" % n
		check(ResourceLoader.exists(path), "missing " + path)
		check(ResourceLoader.exists(path) and load(path) is AudioStreamWAV, "not loadable " + path)
	for st in stems:
		var s: AudioStreamWAV = load("res://assets/sfx/%s.wav" % st)
		check(s != null and absf(s.get_length() - 16.0) < 0.01, "%s is 16 s (8 bars at 120 BPM): %.3f" % [st, s.get_length() if s else -1.0])
	# --- which state for which situation -------------------------------------------------------------------------
	var cases := [
		[{}, "title"], [{"running": false, "night": true}, "title"], [{"running": true}, "calm"], [{"running": true, "night": true}, "tension"],
		[{"running": true, "close": 1}, "tension"], [{"running": true, "alarm": true}, "tension"], [{"running": true, "close": 2, "near": 2}, "tension"],
		[{"running": true, "near": 3, "close": 3}, "combat"], [{"running": true, "near": 3, "assault": true}, "assault"],
		[{"running": true, "assault": true, "blood": true}, "bloodmoon"], [{"running": true, "blood": true, "near": 9, "victory": true}, "victory"],
		[{"running": false, "victory": true}, "victory"]]
	for c in cases:
		check(Sfx.pick_state(c[0]) == c[1], "%s -> %s, got %s" % [c[0], c[1], Sfx.pick_state(c[0])])
	# the real game: an assault, then enemies around the heli
	Game.time = 0.5
	Game.attack_active = true
	check(Sfx.pick_state(Sfx.situation()) == "assault", "attack_active -> assault")
	Game.attack_active = false
	var fakes: Array[Node2D] = []
	for i in 3:
		var e := Node2D.new()
		e.add_to_group("enemies")
		add_child(e)
		e.global_position = Game.heli.global_position + Vector2(100 + 40 * i, 0)
		fakes.append(e)
	var sit: Dictionary = Sfx.situation()
	check(sit["near"] >= 3 and Sfx.pick_state(sit) == "combat", "three enemies close -> combat: %s" % [sit])
	fakes[2].global_position = Game.heli.global_position + Vector2(Sfx.TENSION_DIST - 50.0, 0)
	fakes[1].global_position = Game.heli.global_position + Vector2(Sfx.TENSION_DIST + 400.0, 0)
	sit = Sfx.situation()
	check(sit["near"] == 1 and sit["close"] >= 2 and Sfx.pick_state(sit) == "tension", "one near, one in range, one far -> tension: %s" % [sit])
	for e in fakes:
		e.free()
	# --- state machine: changes wait for a bar line ----------------------------------------------------------------
	var ref: AudioStreamPlayer = Sfx.loops["music_calm"]
	_settle("calm")
	Sfx.music_time = 100.0
	Sfx.request_music("combat")
	check(Sfx.music_state == "calm" and Sfx.music_pending == "combat", "an up-change is pending, not applied")
	Sfx.request_music("calm")
	check(Sfx.music_pending == "", "asking for the current state again cancels it")
	# a bar line: put the reference stem just before one, tick (nothing happens), move it across, tick again
	ref.seek(Sfx.BAR_SECONDS * 3 - 0.3)
	Sfx.music_tick(0.0) # notes the bar
	Sfx.request_music("combat")
	Sfx.music_tick(0.0)
	var before := Sfx.music_state
	var bar0 := Sfx.music_bar
	ref.seek(Sfx.BAR_SECONDS * 4 + 0.05)
	Sfx.music_tick(0.0)
	var seeked: bool = _bar_of_ref() == 4 # the dummy audio driver may not report a seeked position
	check(not seeked or (before == "calm" and bar0 == 2 and Sfx.music_state == "combat"), "applied exactly when the reference crosses a bar line (before %s, bar %d, now %s)" % [before, bar0, Sfx.music_state])
	# without a bar line (audio not running) it is applied after MUSIC_STALL
	_settle("calm")
	ref.stop()
	Sfx.music_tick(0.0) # notes that there is no bar
	Sfx.request_music("assault")
	for i in 4:
		Sfx.music_tick(1.0)
	check(Sfx.music_state == "calm", "not applied before MUSIC_STALL")
	for i in 3:
		Sfx.music_tick(1.0)
	check(Sfx.music_state == "assault", "applied after MUSIC_STALL without a bar line")
	ref.play()
	# calmer states wait out the cooldown, title / victory do not
	_settle("combat")
	Sfx.music_time = 200.0
	Sfx.request_music("calm")
	check(Sfx.music_pending == "", "a calmer state is not pending at once")
	Sfx.music_time += Sfx.MUSIC_COOLDOWN - 1.0
	Sfx.request_music("calm")
	check(Sfx.music_pending == "", "...nor after cooldown - 1 s")
	Sfx.music_time += 2.0
	Sfx.request_music("calm")
	check(Sfx.music_pending == "calm", "...but after the cooldown")
	_settle("assault")
	Sfx.request_music("title")
	check(Sfx.music_pending == "title", "title: no cooldown")
	Sfx.request_music("victory")
	check(Sfx.music_pending == "victory", "victory: no cooldown")
	# --- crossfades: every pair of states, no silence, done within one bar ---------------------------------------------
	var worst_dip := 99.0
	var worst_time := 0.0
	var worst_pair := ""
	for a in Sfx.MUSIC_MIX:
		for b in Sfx.MUSIC_MIX:
			if a == b:
				continue
			_settle(a)
			var floor_v := minf(_total(Sfx.loop_cur), _total(Sfx.MUSIC_MIX[b]))
			Sfx.set_music_state(b)
			var t := 0.0
			while not _faded() and t < 5.0:
				if _total(Sfx.loop_cur) / floor_v < worst_dip:
					worst_dip = _total(Sfx.loop_cur) / floor_v
					worst_pair = "%s -> %s at %.2f s" % [a, b, t]
				Sfx.fade_loops(1.0 / 60.0)
				t += 1.0 / 60.0
			check(is_equal_approx(_total(Sfx.loop_cur), _total(Sfx.loop_target)), "%s -> %s ends on the target mix" % [a, b])
			worst_time = maxf(worst_time, t)
	check(worst_dip >= 0.85, "no gap in any crossfade (lowest total vs the quieter end state: %.2f, %s)" % [worst_dip, worst_pair])
	check(worst_time <= Sfx.BAR_SECONDS + 0.1, "every crossfade is done within one bar (%.2f s)" % worst_time)
	# --- ducking under radio messages ---------------------------------------------------------------------------------
	_settle("calm")
	Sfx.duck_t = 0.0
	Sfx.duck = 1.0
	Sfx._beep_ms = 0
	Game.radio("Base: stock is short, partial top-up only. Put people on fuel and ammo duty.")
	check(Sfx.duck_t >= Sfx.DUCK_BASE, "a radio message ducks the music")
	for i in 30:
		Sfx.music_tick(1.0 / 60.0)
		Sfx.fade_loops(1.0 / 60.0)
	check(is_equal_approx(Sfx.duck, Sfx.DUCK_GAIN), "ducked to DUCK_GAIN: %.2f" % Sfx.duck)
	check(Sfx.loops["music_calm"].volume_db < Sfx.LOOP_DB["music_calm"] - 6.0, "the stem volume carries the duck")
	for i in 9:
		Sfx.music_tick(1.0)
	Sfx.fade_loops(0.0)
	check(Sfx.duck == 1.0 and is_equal_approx(Sfx.loops["music_calm"].volume_db, Sfx.LOOP_DB["music_calm"]), "released after the message")
	# --- radio beeps ----------------------------------------------------------------------------------------------------
	for pair in [["Base: low on fuel", "radio_base"], ["Pilot: RPG!", "radio_pilot"], ["Watchtower: movement north.", "radio_tower"],
			["Intercepted bandit radio: \"x\"", "radio_bandit"], ["Radio: bandits closing in", "radio_bandit"], ["ALERT: bandits attacking the base", "radio_bandit"],
			["Convoy 2 rolls out", "radio_convoy"], ["ALERT: Convoy 2 under attack", "radio_convoy"], ["Motor pool: a truck is ready", "radio_convoy"],
			["Command: FINAL SIEGE", "radio"], ["Military: we read you", "radio"], ["Crew: nothing left", "radio"]]:
		check(Sfx.beep_for(pair[0]) == pair[1], "%s -> %s, got %s" % [pair[0], pair[1], Sfx.beep_for(pair[0])])
	check(Settings.defs.has("radio_beeps") and Settings.defs["radio_beeps"]["kind"] == "toggle" and Settings.defs["radio_beeps"]["default"] == 1, "Radio beeps is a registered toggle, on by default")
	var was: int = Settings.get_value("radio_beeps")
	Settings.set_value("radio_beeps", 1)
	Sfx.last_ms.clear()
	Sfx._beep_ms = 0
	Game.radio("Pilot: we are full, head back to base.")
	check(Sfx.last_ms.has("radio_pilot"), "beeps on: the Pilot beep plays")
	Game.radio("Base: right behind it.")
	check(not Sfx.last_ms.has("radio_base"), "a second message inside BEEP_GAP_MS gets no beep")
	Settings.set_value("radio_beeps", 0)
	Sfx.last_ms.clear()
	Sfx._beep_ms = 0
	Sfx.duck_t = 0.0
	Game.radio("Base: hull patched.")
	check(not Sfx.last_ms.has("radio_base") and not Sfx.last_ms.has("radio"), "beeps off: silent")
	check(Sfx.duck_t > 0.0, "...but the music still ducks")
	Settings.set_value("radio_beeps", was)
	# --- UI clicks --------------------------------------------------------------------------------------------------------
	var btn := Button.new()
	add_child(btn)
	Sfx.last_ms.erase("ui_click")
	btn.pressed.emit()
	await get_tree().process_frame
	check(Sfx.last_ms.has("ui_click"), "a button press clicks")
	Sfx.last_ms.erase("ui_click")
	Sfx.last_ms["ui"] = Time.get_ticks_msec()
	btn.pressed.emit()
	await get_tree().process_frame
	check(not Sfx.last_ms.has("ui_click"), "no second click when the owner played ui")
	btn.free()
	# --- restore --------------------------------------------------------------------------------------------------------------
	_settle("calm")
	Sfx._situation_cd = 0.0
	Sfx.set_process(true)
	Game.time = 0.25
	if _bad.is_empty():
		print("MUSIC OK  stems=%d sfx=%d  bar-line seek tested=%s  worst crossfade %.2f s, dip %.2f" % [stems.size(), SFX.size(), seeked, worst_time, worst_dip])
		get_tree().quit(0)
	else:
		for m in _bad:
			push_error("MUSIC FAIL: " + m)
		get_tree().quit(1)
