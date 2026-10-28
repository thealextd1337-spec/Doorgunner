extends Node2D
## Player helicopter: WASD flight, mouse door gun, landing, fuel/ammo/hp.

signal landed_changed(landed: bool)

const ACCEL := 220.0
const MAX_SPEED := 160.0
const DRAG := 1.4 # low drag: the heli keeps gliding
const LAND_SPEED := 50.0
const RADIUS := 14.0
const SPOOL := 1.5 # seconds to land or take off
const ARC_DEG := 70.0 # door gun arcs: within this of the body's left or right side
const Weapons := preload("res://scripts/weapons.gd")
const DMG_PER_LEVEL := {"mg": 0.12, "autocannon": 0.15, "railgun": 0.2}

var vel := Vector2.ZERO
var landed := false
var fire_cd := 0.0
var manual_yaw := 0.0 # seconds since Q/E were last held; auto-align to the flight path only after a pause
const YAW_SPEED := deg_to_rad(110.0)
var transition := 0.0 # time left in the current land/takeoff
var pending := 0 # 1 landing, -1 taking off
var heat := 0.0 # minigun spread growth 0..1, gone at Lv5
var aim_override := Vector2.ZERO # tests: aim direction used instead of the mouse when non-zero
var no_angle := 0.0 # seconds the HUD keeps showing "no firing angle"
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
	heat = maxf(0.0, heat - delta)
	no_angle -= delta
	muzzle.visible = fire_cd > _interval() - 0.04
	if Input.is_action_just_pressed("land") and pending == 0:
		_toggle_landing()
	if pending != 0:
		transition -= delta / Game.stats["spool"]
		if transition <= 0.0:
			landed = pending == 1
			pending = 0
			landed_changed.emit(landed)
	if Input.is_action_just_pressed("found") and landed and pending == 0 and not Game.base_founded:
		if can_found():
			Game.world.found_base(position)
		else:
			Game.radio("Pilot: too much forest or water here. We need open ground for the FOB.")
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
	# Q/E swing the heli so the door guns bear; without input the nose drifts back toward the flight path
	var yaw := Input.get_axis("yaw_left", "yaw_right")
	if yaw != 0.0:
		body.rotation += yaw * YAW_SPEED * delta
		manual_yaw = 0.0
	else:
		manual_yaw += delta
		if vel.length() > 20.0 and manual_yaw > 1.5:
			body.rotation = lerp_angle(body.rotation, vel.angle() + PI / 2, 1.5 * delta)


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


## Landed, no base yet and the 7x7 cells around the heli are landable: B founds the FOB here.
func can_found() -> bool:
	if not landed or pending != 0 or Game.base_founded:
		return false
	for x in range(-2, 3): # room for the pad; fields, yards and houses around may stay
		for y in range(-2, 3):
			if not Game.world.is_landable(position + Vector2(x, y) * 16.0):
				return false
	return true


## Unit aim direction: the mouse, or aim_override in tests.
func aim_dir() -> Vector2:
	return aim_override.normalized() if aim_override != Vector2.ZERO else (get_global_mouse_position() - global_position).normalized()


## The door gunner fires out of the side doors: not within 90 - ARC_DEG degrees of the nose or tail.
func in_arc(dir: Vector2) -> bool:
	return absf(dir.dot(Vector2.UP.rotated(body.rotation))) < sin(deg_to_rad(ARC_DEG))


## Effective reach of the equipped gun in world px.
func weapon_range() -> float:
	return Weapons.TABLE[Game.weapon]["range"] * Game.stats["range"]


func _interval() -> float:
	var rate: float = 1.0 + 0.1 * (maxi(1, Progression.level("minigun")) - 1) if Game.weapon == "minigun" else 1.0
	return Weapons.TABLE[Game.weapon]["interval"] / Game.stats["fire_rate"] / rate


## Installed system items (Progression slot "system") live as child nodes named by id.
func refresh_systems() -> void:
	for id in Progression.ITEMS:
		if Progression.ITEMS[id]["slot"] != "system":
			continue
		var n := get_node_or_null(NodePath(id))
		if Game.heli_items.has(id) and n == null:
			n = load("res://scripts/systems/%s.gd" % id).new()
			n.name = id
			add_child(n)
		elif not Game.heli_items.has(id) and n != null:
			remove_child(n)
			n.queue_free()


func _fire() -> void:
	var id: String = Game.weapon
	var w: Dictionary = Weapons.TABLE[id]
	if fire_cd > 0.0 or Game.ammo < w["ammo_per_shot"]:
		return
	var aim := aim_dir()
	if not in_arc(aim):
		no_angle = 0.6
		return
	var lv := maxi(1, Progression.level(id))
	var dmg: float = w["damage"] * Game.stats["damage"] * (1.0 + DMG_PER_LEVEL.get(id, 0.0) * (lv - 1))
	if fire_cd < -1.0 and Progression.level("training") >= 5:
		dmg *= 2.0 # Gunnery Lv5: first shot after a pause crits
	fire_cd = _interval()
	Game.ammo -= w["ammo_per_shot"]
	Sfx.play("gun", null, -4.0)
	Game.make_noise(global_position, 1.0)
	muzzle.position = aim * 18
	var shots: int = w["shots"] + Game.stats["shots"] - 1 + (lv - 1 if id == "shotgun" else 0)
	var splash: float = w.get("splash", 0.0) * (1.0 + 0.15 * (lv - 1) if id == "rockets" else 1.0)
	var tracers := [0.0] # sideways offsets, Twin MG fires two parallel tracers
	if lv >= 5:
		match id:
			"mg": tracers = [-3.0, 3.0]
			"shotgun": shots *= 2
			"autocannon": splash = 40.0
			"rockets": shots = 3
	if id == "minigun" and lv < 5:
		heat = minf(1.0, heat + 0.1)
	var jitter: float = w["spread_deg"] / 2.0 * (1.0 + heat)
	for i in shots:
		var spread := deg_to_rad((i - (shots - 1) / 2.0) * 6.0 + randf_range(-jitter, jitter))
		for o in tracers:
			var b := bullet_script.new()
			b.setup(global_position + aim * 16 + aim.orthogonal() * o, aim.rotated(spread), dmg, w["pierce"] + Game.stats["pierce"],
				w["bullet_speed"], weapon_range() / (w["bullet_speed"] * Game.stats["bullet_speed"]), splash)
			b.chain = 2 if id == "railgun" and lv >= 5 else 0
			b.bounce = 1 if Progression.level("hardcore") >= 5 else 0
			Game.world.add_child(b)


## Damage from any source. Ground enemies should only call this when landed.
func take_damage(amount: float) -> void:
	if not Game.running:
		return
	Game.hp -= amount / Game.stats["armor"]
	if Game.passengers > Game.passengers_injured and randf() < 0.1 and not Progression.owned("medic"):
		Game.passengers_injured += 1 # the heli medic system keeps passengers safe
	Sfx.play("hit")
	body.modulate = Color(1, 0.4, 0.4)
	get_tree().create_timer(0.1).timeout.connect(func(): body.modulate = Color.WHITE)
	if Game.hp <= 0.0:
		Game.hp = 0.0
		Game.end_run("Helicopter destroyed.")
