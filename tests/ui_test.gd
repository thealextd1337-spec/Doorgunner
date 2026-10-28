extends Node
## Headless UI test. main.gd adds this node when env SMOKE=ui:
##   SMOKE=ui godot --headless --path . --quit-after 3000
## Level-ups open the choice overlay (paused, queued), picks apply, game over shows.


func _ready() -> void:
	call_deferred("_run")


func _snap() -> Dictionary:
	return {"stats": Game.stats.duplicate(), "fuel": Game.max_fuel, "ammo": Game.max_ammo,
		"hp": Game.max_hp, "seats": Game.seats, "scrap": Game.scrap}


func _run() -> void:
	var main: Node2D = Game.world
	var process_frame := get_tree().process_frame
	await process_frame
	await process_frame
	var before := _snap()
	Game.add_xp(1000)
	await process_frame
	assert(get_tree().paused, "tree paused on level-up")
	assert(main.ui_open, "ui_open while choosing")
	var picks := 0
	while get_tree().paused and picks < 50:
		main.choice_ui.pick(0)
		picks += 1
		await process_frame
	assert(picks > 1, "level-ups queued: %d" % picks)
	assert(not get_tree().paused and not main.ui_open, "all choices resolved")
	assert(_snap() != before, "an upgrade applied")
	Game.end_run("test")
	await process_frame
	var over: CanvasLayer
	for c in main.get_children():
		if c is CanvasLayer and c.layer == 30:
			over = c
	assert(over and over.visible, "game-over layer visible")
	assert(main.ui_open, "ui_open after game over")
	assert(Game.meta["runs"] >= 1, "meta saved")
	# sound settings menu
	var settings: CanvasLayer
	for c in Game.world.get_children():
		if c is CanvasLayer and c.layer == 25:
			settings = c
	settings.open()
	assert(get_tree().paused and settings.visible, "settings pause the game")
	settings.set_volume("vol_sfx", 50)
	assert(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.5)) < 0.01, "SFX bus follows the slider")
	settings.set_volume("muted", 1)
	assert(AudioServer.is_bus_mute(0), "mute toggles the master bus")
	settings.set_volume("muted", 0)
	settings.set_volume("vol_sfx", 100)
	settings.close()
	assert(not get_tree().paused and not settings.visible, "settings closed")
	print("UI OK  picks=%d level=%d" % [picks, Game.level])
	get_tree().quit(0)
