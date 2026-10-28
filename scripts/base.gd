extends Node2D
## Forward operating base: pad, turrets, sandbags (blueprints built by Build workers), militia defenders,
## base HP, landing services and the upgrade menu.

const RADIUS := 60.0
const PAD_REACH := 48.0
const CELL := 16.0
const SANDBAG_REACH := 260.0 # placement radius around the pad centre
const PAD_CLEAR := 40.0 # no sandbags on the helipad

var turrets: Node2D
var sandbags: Node2D # one Sprite2D per cell, keyed in bags
var defenders: Node2D # militia posted during an assault
var ui: CanvasLayer
var bags := {} # Vector2i cell -> Sprite2D
var build_progress := 0.0 # blueprints finished per 20 s per build worker, carried between frames
var placing := false: # BUILD tab toggle: LMB places a blueprint, RMB removes
	set(v):
		placing = v
		if ui:
			ui.refresh()


func _ready() -> void:
	var pad := Art.sprite("helipad")
	add_child(pad)
	var hangar := Art.sprite("hangar")
	hangar.position = Vector2(-70, -40)
	add_child(hangar)
	sandbags = Node2D.new()
	add_child(sandbags)
	turrets = Node2D.new()
	add_child(turrets)
	defenders = Node2D.new()
	add_child(defenders)
	ui = preload("res://scripts/base_ui.gd").new()
	add_child(ui)
	rebuild()
	Game.base_attack_started.connect(_on_attack)
	call_deferred("_connect_heli") # heli is created after the base


func _connect_heli() -> void:
	Game.heli.landed_changed.connect(_on_landed)


## Rebuild the turret ring from Game.base_level.
func rebuild() -> void:
	for n in turrets.get_children():
		n.free()
	var turret_count: int = Game.base_level.get("turrets", 0)
	for i in turret_count:
		var t := preload("res://scripts/turret.gd").new()
		t.position = Vector2(70, 0).rotated(i * TAU / turret_count)
		turrets.add_child(t)


func _process(delta: float) -> void:
	queue_redraw()
	if not Game.attack_active and defenders.get_child_count() > 0:
		for d in defenders.get_children():
			d.queue_free()
	if Game.workers["build"] > 0:
		build_progress += Game.workers["build"] * delta / Game.BUILD_SECONDS
		while build_progress >= 1.0:
			var cell: Variant = _nearest_blueprint()
			if cell == null:
				build_progress = 0.0
				break
			build_progress -= 1.0
			Game.sandbags[cell]["built"] = true
			bags[cell].modulate.a = 1.0


func _draw() -> void:
	if placing:
		draw_arc(Vector2.ZERO, SANDBAG_REACH, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 1.0)
	if Game.base_hp >= Game.max_base_hp and not Game.attack_active:
		return
	draw_rect(Rect2(-40, -46, 80, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-39, -45, 78 * clampf(Game.base_hp / Game.max_base_hp, 0.0, 1.0), 4), Color(0.9, 0.3, 0.3))


func _input(event: InputEvent) -> void:
	if placing and event.is_action_pressed("menu"):
		placing = false


func _unhandled_input(event: InputEvent) -> void:
	if not placing or not (event is InputEventMouseButton and event.pressed):
		return
	var cell := Vector2i((get_global_mouse_position() / CELL).floor())
	if event.button_index == MOUSE_BUTTON_LEFT:
		place_sandbag(cell)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		remove_sandbag(cell)


func cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell) * CELL + Vector2(CELL / 2, CELL / 2)


## Blueprint for 5 scrap: near the pad but not on it, on landable ground, up to 80.
func place_sandbag(cell: Vector2i) -> bool:
	var pos := cell_pos(cell)
	var d := pos.distance_to(global_position)
	if Game.sandbags.has(cell) or Game.sandbags.size() >= Game.SANDBAG_MAX or Game.scrap < Game.SANDBAG_COST:
		return false
	if d > SANDBAG_REACH or d < PAD_CLEAR or not Game.world.is_landable(pos):
		return false
	Game.scrap -= Game.SANDBAG_COST
	Game.sandbags[cell] = {"hp": Game.SANDBAG_HP, "built": false}
	var s := Art.sprite("wall")
	s.position = pos - global_position
	s.modulate.a = 0.4
	sandbags.add_child(s)
	bags[cell] = s
	ui.refresh()
	return true


## RMB: blueprints are refunded, built sandbags are just torn down.
func remove_sandbag(cell: Vector2i) -> void:
	if not Game.sandbags.has(cell):
		return
	if not Game.sandbags[cell]["built"]:
		Game.scrap += Game.SANDBAG_COST
	_free_sandbag(cell)
	ui.refresh()


## Zombies chew on a built sandbag in their way (enemy.gd); at 0 hp it is gone.
func damage_sandbag(cell: Vector2i, amount: float) -> void:
	Game.sandbags[cell]["hp"] -= amount
	Sfx.play("base_hit", cell_pos(cell), -14.0)
	if Game.sandbags[cell]["hp"] <= 0.0:
		Game.world.spawn_fx(cell_pos(cell), 0.5)
		_free_sandbag(cell)


func _free_sandbag(cell: Vector2i) -> void:
	Game.sandbags.erase(cell)
	bags[cell].queue_free()
	bags.erase(cell)


func _nearest_blueprint() -> Variant:
	var best: Variant = null
	var best_d := INF
	for cell in Game.sandbags:
		if Game.sandbags[cell]["built"]:
			continue
		var d: float = cell_pos(cell).distance_squared_to(global_position + Vector2(-70, -40)) # hangar first
		if d < best_d:
			best_d = d
			best = cell
	return best


## Militia take up rifles on the outermost built sandbags (a 60 px ring without any).
func _on_attack(_day: int) -> void:
	var posts: Array = Game.sandbags.keys().filter(func(c): return Game.sandbags[c]["built"]).map(cell_pos)
	posts.sort_custom(func(a, b): return a.distance_squared_to(global_position) > b.distance_squared_to(global_position))
	var n: int = Game.workers["militia"]
	for i in n:
		var t := preload("res://scripts/turret.gd").new()
		t.rifle = true
		t.position = posts[i] - global_position if i < posts.size() else Vector2(RADIUS, 0).rotated(i * TAU / n)
		defenders.add_child(t)


func take_damage(amount: float) -> void:
	if not Game.running:
		return
	Game.base_hp -= amount * (1.0 - 0.12 * Game.base_level.get("barracks", 0)) * (1.0 - minf(0.3, 0.03 * Game.workers["militia"]))
	Sfx.play("base_hit", global_position, -6.0)
	modulate = Color(1, 0.5, 0.5)
	get_tree().create_timer(0.1).timeout.connect(func(): modulate = Color.WHITE)
	if Game.base_hp <= 0.0:
		Game.base_hp = 0.0
		Game.end_run("The base has fallen.")


## Top the heli up from base stock. Also runs after every purchase or loadout change while parked,
## so a bigger tank or ammo feed fills right away instead of showing 100/125 until the next landing.
func resupply() -> void:
	var f: float = minf(Game.max_fuel - Game.fuel, Game.base_fuel)
	Game.fuel += f
	Game.base_fuel -= f
	var a: int = mini(Game.max_ammo - Game.ammo, int(Game.base_ammo))
	Game.ammo += a
	Game.base_ammo -= a


func _on_landed(landed: bool) -> void:
	if not landed:
		ui.close()
		return
	if Game.heli.position.distance_to(position) > PAD_REACH:
		return
	resupply()
	var free_hp: float = Game.MEDIC_REPAIR * Game.workers["medic"] # medics patch for free, the rest is 1 scrap per 5 hull
	var repair := int(ceil(maxf(0.0, Game.max_hp - Game.hp - free_hp) / 5.0))
	if Game.scrap >= repair:
		Game.scrap -= repair
		Game.hp = Game.max_hp
		if repair > 0:
			Game.radio("Base: hull patched for %d scrap." % repair)
	else:
		Game.hp = minf(Game.max_hp, Game.hp + free_hp)
		Game.radio("Base: not enough scrap for hull repairs, %d needed." % repair)
	if Game.fuel < Game.max_fuel or Game.ammo < Game.max_ammo:
		Game.radio("Base: stock is short, partial top-up only. Put people on fuel and ammo duty.")
	Sfx.play("pickup")
	var n: int = Game.passengers
	if n > 0:
		Game.passengers = 0
		Game.rescued += n
		Game.scrap += 3 * n
		Game.radio("%d survivors delivered. Total: %d" % [n, Game.rescued])
		Game.add_xp(6 * n)
	ui.open()
