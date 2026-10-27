extends Node2D
## Forward operating base: pad, walls, turrets, base HP, landing services and the upgrade menu.

const RADIUS := 60.0
const PAD_REACH := 48.0

var walls: Node2D
var turrets: Node2D
var ui: CanvasLayer


func _ready() -> void:
	var pad := Art.sprite("helipad")
	add_child(pad)
	var hangar := Art.sprite("hangar")
	hangar.position = Vector2(-70, -40)
	add_child(hangar)
	walls = Node2D.new()
	add_child(walls)
	turrets = Node2D.new()
	add_child(turrets)
	ui = preload("res://scripts/base_ui.gd").new()
	add_child(ui)
	rebuild()
	call_deferred("_connect_heli") # heli is created after the base


func _connect_heli() -> void:
	Game.heli.landed_changed.connect(_on_landed)


## Rebuild wall ring and turret ring from Game.base_level.
func rebuild() -> void:
	for n in walls.get_children() + turrets.get_children():
		n.free()
	var wall_count: int = 13 * Game.base_level.get("walls", 0)
	for i in wall_count:
		var w := Art.sprite("wall")
		var a := i * TAU / wall_count
		w.position = Vector2(100, 0).rotated(a)
		w.rotation = a + PI / 2
		walls.add_child(w)
	var turret_count: int = Game.base_level.get("turrets", 0) + Game.workers["militia"] / 2
	for i in turret_count:
		var t := preload("res://scripts/turret.gd").new()
		t.position = Vector2(70, 0).rotated(i * TAU / turret_count)
		turrets.add_child(t)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if Game.base_hp >= Game.max_base_hp and not Game.attack_active:
		return
	draw_rect(Rect2(-40, -46, 80, 6), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-39, -45, 78 * clampf(Game.base_hp / Game.max_base_hp, 0.0, 1.0), 4), Color(0.9, 0.3, 0.3))


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


func _on_landed(landed: bool) -> void:
	if not landed:
		ui.close()
		return
	if Game.heli.position.distance_to(position) > PAD_REACH:
		return
	var f: float = minf(Game.max_fuel - Game.fuel, Game.base_fuel)
	Game.fuel += f
	Game.base_fuel -= f
	var a: int = mini(Game.max_ammo - Game.ammo, int(Game.base_ammo))
	Game.ammo += a
	Game.base_ammo -= a
	Game.hp = Game.max_hp
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
