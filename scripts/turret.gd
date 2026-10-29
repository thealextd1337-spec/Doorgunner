extends Node2D
## Base auto turret: every 0.5 s shoots the nearest enemy in range with a player bullet.
## rifle = true: a militia survivor (6 dmg, 200 px, 0.8 s), posted by base.gd during assaults.
## Turrets and watchtower posts fire at half rate without base power.

const RANGE := 240.0
const INTERVAL := 0.5
const DAMAGE := 8.0

var cd := 0.0
var rifle := false
var armed := true # a militia post without a rifle just stands there
var tower := false # watchtower post: +50 % reach
var skill := 1.0 # rifle damage factor of the person on this post (people.gd rate: Soldiers hit harder)
var sprite: Sprite2D
var flash: Sprite2D # muzzle flash, shown for `shot` seconds after each round
var aim := Vector2.UP # last firing direction (base_pawn.gd turns the militia on this post to it)
var shot := 0.0


func _ready() -> void:
	sprite = Art.sprite("survivor" if rifle else "turret")
	if not armed:
		sprite.modulate = Color(0.6, 0.6, 0.6)
	add_child(sprite)
	flash = Art.sprite("muzzle")
	flash.scale *= 0.6 if rifle else 1.0
	flash.visible = false
	add_child(flash)


func _process(delta: float) -> void:
	shot -= delta
	flash.visible = shot > 0.0
	if not Game.running or not armed:
		return
	cd -= delta
	if cd > 0.0:
		return
	cd = (0.8 if rifle else INTERVAL) * (2.0 if (tower or not rifle) and not Game.power else 1.0)
	var best: Node2D
	var best_d := pow(200.0 * (1.5 if tower else 1.0), 2) if rifle else RANGE * RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	var dir: Vector2 = (best.global_position - global_position).normalized()
	sprite.rotation = dir.angle() + PI / 2
	aim = dir
	shot = 0.08
	flash.position = dir * (7.0 if rifle else 12.0)
	Sfx.play("gun", global_position, -14.0 if rifle else -10.0)
	var b := preload("res://scripts/bullet.gd").new()
	b.setup(global_position + dir * 10, dir, 6.0 * skill if rifle else DAMAGE, 0)
	Game.world.add_child(b)
