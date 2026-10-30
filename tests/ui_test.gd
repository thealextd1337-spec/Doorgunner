extends Node
## Headless UI test. main.gd adds this node when env SMOKE=ui:
##   SMOKE=ui godot --headless --path . --quit-after 3000
## Level-ups open the choice overlay (paused, queued), picks apply, card offers follow the slot rules, game over shows.


func _ready() -> void:
	call_deferred("_run")


func _snap() -> Dictionary:
	return {"stats": Game.stats.duplicate(), "fuel": Game.max_fuel, "ammo": Game.max_ammo,
		"hp": Game.max_hp, "seats": Game.seats, "scrap": Game.scrap, "items": Game.heli_items.duplicate()}


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
	_cards()
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
	await _build_bar_clear()
	print("UI OK  picks=%d level=%d" % [picks, Game.level])
	get_tree().quit(0)


## The build bar with all 11 tools (radio and airstrip shown) stays clear of the minimap at 1280x720.
func _build_bar_clear() -> void:
	var base: Node2D = Game.world.base
	base.ui.open()
	base.placing = true
	for b in base.ui.bar_btns.values():
		b.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	var bar: Rect2 = base.ui.build_bar.get_global_rect()
	var map: Rect2 = Game.world.hud.minimap.get_global_rect()
	assert(base.ui.build_bar.visible and base.ui.bar_btns.size() == 11, "build bar shown with 11 tools")
	assert(not bar.intersects(map) and bar.position.x >= 0.0, "build bar %s clear of the minimap %s" % [bar, map])
	base.placing = false
	base.ui.close()


## Offer rules from docs/PROGRESSION.md section 3 on a fresh run.
func _cards() -> void:
	Game.new_run()
	var o: Array = Game.offer_cards(3)
	assert(o.size() == 3 and o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "offer has 3 distinct cards: %s" % [o])
	Game.take_item("searchlight")
	assert(Progression.used("system") == 1 and Game.heli.has_node("searchlight"), "new system fills a slot and mounts its node")
	for id in ["engine", "plating", "leanburn"]: # always unlocked; fills 2 or 3 module slots
		if Progression.used("module") < Game.slots["module"]:
			Game.take_item(id)
	var all: Array = Game.offer_cards(99)
	for id in all:
		assert(Progression.ITEMS[id]["slot"] != "module" or Progression.owned(id), "full module slots offer only level-ups: %s" % id)
	assert("engine" in all, "owned module still levels up")
	var speed0: float = Game.stats["speed"]
	Game.take_item("engine")
	assert(Game.heli_items["engine"] == 2 and Game.stats["speed"] > speed0, "level-up recomputes stats")
	Game.banished.append("cogunner")
	assert(not "cogunner" in Game.offer_cards(99), "banished item never offered again")
	Game.level = Game.LEVEL_CAP
	Game.xp = 0
	var scrap0: int = Game.scrap
	Game.add_xp(100)
	assert(Game.level == Game.LEVEL_CAP and Game.scrap == scrap0 + 10, "XP past the cap turns into scrap (10:1)")
	Game.world.choice_ui.open("test", 3)
	Game.world.choice_ui.skip()
	assert(Game.scrap == scrap0 + 25 and not get_tree().paused, "skip gives 15 scrap and unpauses")
	assert(Game.scrap_item("plating") == Progression.CARD_SCRAP / 2 and not Progression.owned("plating"), "scrapping frees the slot and refunds")
