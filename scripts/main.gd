extends Node2D
## World root. Builds everything in code; other scripts reach it through Game.world.

var chunks: TileMapLayer
var heli: Node2D
var base: Node2D
var spawner: Node
var hud: CanvasLayer
var choice_ui: CanvasLayer
var night: CanvasModulate
var radio_target: Node2D # POI currently highlighted on the HUD compass
var ui_open := false # overlays set this so clicks do not fire the gun
var pois := []

const BASE_POS := Vector2(16 * 16 + 8, 16 * 16 + 8) # centre of chunk (0,0)


func _ready() -> void:
	Game.world = self
	Game.new_run()
	chunks = preload("res://scripts/chunk_manager.gd").new()
	add_child(chunks)
	base = preload("res://scripts/base.gd").new()
	base.position = BASE_POS
	base.z_index = 1
	add_child(base)
	heli = preload("res://scripts/heli.gd").new()
	heli.position = BASE_POS
	heli.z_index = 10
	heli.landed = true
	add_child(heli)
	var cam := Camera2D.new()
	cam.zoom = Vector2(2, 2)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	heli.add_child(cam)
	night = CanvasModulate.new()
	add_child(night)
	spawner = preload("res://scripts/spawner.gd").new()
	add_child(spawner)
	add_child(preload("res://scripts/radio.gd").new())
	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	choice_ui = preload("res://scripts/choice_ui.gd").new()
	add_child(choice_ui)
	add_child(preload("res://scripts/game_over_ui.gd").new())
	add_child(preload("res://scripts/settings_ui.gd").new())
	Game.level_up.connect(func(lvl: int): offer_upgrades("Level %d reached" % lvl))
	Game.day_changed.connect(_settlements_decline)
	var test: String = {"1": "smoke", "poi": "poi_test", "base": "base_test", "ui": "ui_test", "shot": "shot", "prog": "progression_test"}.get(OS.get_environment("SMOKE"), "")
	if test != "":
		add_child(load("res://tests/%s.gd" % test).new())
	else:
		_show_title()
	Game.radio("Command: you are cleared for takeoff. Rescue survivors, bring them home.")
	Game.radio("Controls: WASD fly, mouse aim/fire, SPACE land or take off.")


func _show_title() -> void:
	var title: CanvasLayer = preload("res://scripts/title_ui.gd").new()
	add_child(title)
	Game.running = false
	ui_open = true
	hud.visible = false
	title.start_pressed.connect(func():
		Game.running = true
		ui_open = false
		hud.visible = true
		Sfx.play("ui"))
	title.open()


func _process(_delta: float) -> void:
	var d := Game.darkness()
	night.color = Color(1, 1, 1).lerp(Color(0.2, 0.22, 0.45), d)


## Off-screen settlements slowly fall to the horde: rescue early or lose them.
func _settlements_decline(_day: int) -> void:
	var lost := 0
	for p in pois:
		if is_instance_valid(p) and p.kind == "survivors" and not p.done and randf() < 0.3:
			p.lose_survivor(true)
			if p.done:
				lost += 1
	if lost > 0:
		Game.radio("Command: contact lost with %d settlement(s) overnight." % lost)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and not Game.running:
		get_tree().reload_current_scene()


func is_landable(pos: Vector2) -> bool:
	return chunks.is_landable(pos)


func spawn_poi(kind: String, pos: Vector2, rng: RandomNumberGenerator) -> Node2D:
	var p: Node2D = preload("res://scripts/poi.gd").new()
	p.setup(kind, pos, rng)
	p.z_index = 1
	add_child(p)
	pois.append(p)
	return p


func spawn_enemy(kind: String, pos: Vector2, target_base := false) -> Node2D:
	var e: Node2D = preload("res://scripts/enemy.gd").new()
	e.setup(kind, pos, Game.danger_at(pos), target_base)
	add_child(e)
	return e


## Decorative sprite (church, barn, tree, fence...) placed by the chunk generator. Not interactive.
func spawn_prop(name: String, pos: Vector2, rot := 0.0) -> Node2D:
	var p := Node2D.new()
	p.position = pos
	p.rotation = rot
	p.z_index = 1
	p.add_child(Art.sprite(name))
	add_child(p)
	return p


func spawn_fx(pos: Vector2, scale_factor := 1.0) -> void:
	var fx: Node2D = preload("res://scripts/fx.gd").new()
	fx.position = pos
	fx.scale = Vector2.ONE * scale_factor
	add_child(fx)


## Pause and let the player pick one of `n` item cards (default 3, Veteran Lv5 4).
func offer_upgrades(title: String, n := 0) -> void:
	choice_ui.open(title, n if n > 0 else (4 if Progression.level("veteran") >= 5 else 3))
