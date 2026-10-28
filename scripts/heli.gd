extends Node2D
## Player helicopter: WASD flight, mouse door gun, landing, fuel/ammo/hp.

signal landed_changed(landed: bool)

const ACCEL := 320.0
const MAX_SPEED := 160.0
const DRAG := 2.2
const LAND_SPEED := 50.0
const RADIUS := 14.0
const SPOOL := 1.5 # seconds to land or take off
const Weapons := preload("res://scripts/weapons.gd")

var vel := Vector2.ZERO
var landed := false
var fire_cd := 0.0
var transition := 0.0 # time left in the current land/takeoff
var pending := 0 # 1 landing, -1 taking off
var body: Sprite2D
var rotor: Sprite2D
var shadow: Sprite2D
var muzzle: Sprite2D

@onready var bullet_script := preload("res://scripts/bullet.gd")


func _ready() -> void:
	add_to_group("player")
	Game.heli = self
	shadow = Art.sprite("heli")
	shadow.modulate = Color(0, 0, 0, 0.35)
	add_child(shadow)
	body = Art.sprite("heli")
	add_child(body)
	rotor = Art.sprite("rotor")
	add_child(rotor)
	muzzle = Art.sprite("muzzle")
	muzzle.visible = false
	add_child(muzzle)


func _process(delta: float) -> void:
	Sfx.rotor(Game.running, vel.length() / MAX_SPEED)
	if not Game.running:
		return
	fire_cd -= delta
	muzzle.visible = fire_cd > _interval() - 0.04
	if Input.is_action_just_pressed("land") and pending == 0:
		_toggle_landing()
	if pending != 0:
		transition -= delta
		if transition <= 0.0:
			landed = pending == 1
			pending = 0
			landed_changed.emit(landed)
	if Input.is_action_just_pressed("weapon_swap"):
		Game.cycle_weapon()
	_move(delta)
	_fuel(delta)
	Game.make_noise(global_position, 0.05 if landed else 0.25 + vel.length() / MAX_SPEED * 0.2)
	if Input.is_action_pressed("fire") and not Game.world.ui_open:
		_fire()
	var h := 0.0 if landed else 1.0
	shadow.position = shadow.position.lerp(Vector2(10, 14) * h, 10 * delta)
	shadow.rotation = body.rotation
	rotor.rotation += (25.0 if not landed else 4.0) * delta
	rotor.position = body.position
	body.scale = Vector2.ONE * Art.SCALE * (1.0 + 0.08 * h)


func _move(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if landed or pending == 1:
		vel = vel.lerp(Vector2.ZERO, 4.0 * delta)
		position += vel * delta
		return
	vel += dir * ACCEL * delta
	vel -= vel * DRAG * delta
	var max_speed: float = MAX_SPEED * Game.stats["speed"] * Game.weight_factor
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed
	position += vel * delta
	if vel.length() > 20.0:
		body.rotation = lerp_angle(body.rotation, vel.angle() + PI / 2, 6 * delta)


func _fuel(delta: float) -> void:
	if landed:
		return
	var burn: float = (0.35 + vel.length() / MAX_SPEED * 0.9) / Game.stats["fuel_eff"]
	Game.fuel = max(0.0, Game.fuel - burn * delta)
	if Game.fuel <= 0.0:
		Game.end_run("Out of fuel: the helicopter went down.")


func _toggle_landing() -> void:
	if landed:
		if Game.fuel > 0.0:
			pending = -1
			transition = SPOOL
			Sfx.play("takeoff")
	elif vel.length() <= LAND_SPEED and Game.world.is_landable(position):
		pending = 1
		transition = SPOOL
		Sfx.play("land")
	else:
		Game.radio("Pilot: too fast or no clear ground to land.")


## Effective reach of the equipped gun in world px.
func weapon_range() -> float:
	return Weapons.TABLE[Game.weapon]["range"] * Game.stats["range"]


func _interval() -> float:
	return Weapons.TABLE[Game.weapon]["interval"] / Game.stats["fire_rate"]


func _fire() -> void:
	var w: Dictionary = Weapons.TABLE[Game.weapon]
	if fire_cd > 0.0 or Game.ammo < w["ammo_per_shot"]:
		return
	fire_cd = _interval()
	Game.ammo -= w["ammo_per_shot"]
	Sfx.play("gun", null, -4.0)
	Game.make_noise(global_position, 1.0)
	var aim: Vector2 = (get_global_mouse_position() - global_position).normalized()
	muzzle.position = aim * 18
	var shots: int = w["shots"] + Game.stats["shots"] - 1
	var jitter: float = w["spread_deg"] / 2.0
	for i in shots:
		var spread := deg_to_rad((i - (shots - 1) / 2.0) * 6.0 + randf_range(-jitter, jitter))
		var b := bullet_script.new()
		b.setup(global_position + aim * 16, aim.rotated(spread), w["damage"] * Game.stats["damage"], w["pierce"] + Game.stats["pierce"],
			w["bullet_speed"], weapon_range() / (w["bullet_speed"] * Game.stats["bullet_speed"]), w.get("splash", 0.0))
		Game.world.add_child(b)


## Damage from any source. Ground enemies should only call this when landed.
func take_damage(amount: float) -> void:
	if not Game.running:
		return
	Game.hp -= amount / Game.stats["armor"]
	if Game.passengers > Game.passengers_injured and randf() < 0.1:
		Game.passengers_injured += 1 # shortcut: no heli medic system blocks this yet, check it here once progression adds one
	Sfx.play("hit")
	body.modulate = Color(1, 0.4, 0.4)
	get_tree().create_timer(0.1).timeout.connect(func(): body.modulate = Color.WHITE)
	if Game.hp <= 0.0:
		Game.hp = 0.0
		Game.end_run("Helicopter destroyed.")
