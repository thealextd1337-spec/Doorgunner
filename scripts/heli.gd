extends Node2D
## Player helicopter: WASD flight, mouse door gun, landing, fuel/ammo/hp.

signal landed_changed(landed: bool)

const ACCEL := 700.0
const MAX_SPEED := 260.0
const DRAG := 2.2
const LAND_SPEED := 50.0
const FIRE_INTERVAL := 0.12
const RADIUS := 14.0

var vel := Vector2.ZERO
var landed := false
var fire_cd := 0.0
var body: Sprite2D
var rotor: Sprite2D
var shadow: Sprite2D
var muzzle: Sprite2D

@onready var bullet_script := preload("res://scripts/bullet.gd")


func _ready() -> void:
	add_to_group("player")
	Game.heli = self
	var tex := load("res://assets/sprites/heli.png")
	shadow = Sprite2D.new()
	shadow.texture = tex
	shadow.modulate = Color(0, 0, 0, 0.35)
	add_child(shadow)
	body = Sprite2D.new()
	body.texture = tex
	add_child(body)
	rotor = Sprite2D.new()
	rotor.texture = load("res://assets/sprites/rotor.png")
	add_child(rotor)
	muzzle = Sprite2D.new()
	muzzle.texture = load("res://assets/sprites/muzzle.png")
	muzzle.visible = false
	add_child(muzzle)


func _process(delta: float) -> void:
	Sfx.rotor(Game.running, vel.length() / MAX_SPEED)
	if not Game.running:
		return
	fire_cd -= delta
	muzzle.visible = fire_cd > FIRE_INTERVAL / Game.stats["fire_rate"] - 0.04
	if Input.is_action_just_pressed("land"):
		_toggle_landing()
	_move(delta)
	_fuel(delta)
	if Input.is_action_pressed("fire") and not Game.world.ui_open:
		_fire()
	var h := 0.0 if landed else 1.0
	shadow.position = shadow.position.lerp(Vector2(10, 14) * h, 10 * delta)
	shadow.rotation = body.rotation
	rotor.rotation += (25.0 if not landed else 4.0) * delta
	rotor.position = body.position
	body.scale = Vector2.ONE * (1.0 + 0.08 * h)


func _move(delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if landed:
		vel = Vector2.ZERO
		return
	vel += dir * ACCEL * delta
	vel -= vel * DRAG * delta
	var max_speed: float = MAX_SPEED * Game.stats["speed"]
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
			landed = false
			landed_changed.emit(false)
			Sfx.play("takeoff")
	elif vel.length() <= LAND_SPEED and Game.world.is_landable(position):
		landed = true
		vel = Vector2.ZERO
		landed_changed.emit(true)
		Sfx.play("land")
	else:
		Game.radio("Pilot: too fast or no clear ground to land.")


func _fire() -> void:
	if fire_cd > 0.0 or Game.ammo <= 0:
		return
	fire_cd = FIRE_INTERVAL / Game.stats["fire_rate"]
	Game.ammo -= 1
	Sfx.play("gun", null, -4.0)
	var aim: Vector2 = (get_global_mouse_position() - global_position).normalized()
	muzzle.position = aim * 18
	var shots: int = Game.stats["shots"]
	for i in shots:
		var spread := deg_to_rad((i - (shots - 1) / 2.0) * 6.0 + randf_range(-2, 2))
		var b := bullet_script.new()
		b.setup(global_position + aim * 16, aim.rotated(spread), 10.0 * Game.stats["damage"], Game.stats["pierce"])
		Game.world.add_child(b)


## Damage from any source. Ground enemies should only call this when landed.
func take_damage(amount: float) -> void:
	if not Game.running:
		return
	Game.hp -= amount / Game.stats["armor"]
	Sfx.play("hit")
	body.modulate = Color(1, 0.4, 0.4)
	get_tree().create_timer(0.1).timeout.connect(func(): body.modulate = Color.WHITE)
	if Game.hp <= 0.0:
		Game.hp = 0.0
		Game.end_run("Helicopter destroyed.")
