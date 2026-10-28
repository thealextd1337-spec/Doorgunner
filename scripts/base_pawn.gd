extends Node2D
## One person living at the base (base.gd keeps one per rescued, up to PAWN_MAX). A fresh arrival walks from the pad
## into the barracks, changes into uniform (3 s) and from then on walks between the spots of its job, choosing the next
## waypoint after a few seconds' idle. Jobs come from base.sync_pawns and are read at the next waypoint.

const SPEED := 30.0
const OLIVE := Color(0.85, 1.0, 0.5)
const HURT := Color(1.0, 0.45, 0.45)
const DARK := Color(0.12, 0.1, 0.08)
const GREY := Color(0.5, 0.52, 0.55)
const TOOL_JOBS := ["fuel", "ammo", "repair", "workshop", "build"]
const WORK_JOBS := TOOL_JOBS + ["farm", "water", "medic"] # bob and swing while waiting at a work spot
const DUST := Color(0.75, 0.66, 0.5)
const FLASH := Color(1.0, 0.8, 0.35)
const DEPOT := Vector2(56, -56) # fuel depot area, from the base centre

var base: Node2D
var job := "idle"
var slot := 0 # index among pawns with the same job (militia: their defender post in an assault)
var camper := false # no bed: sleeps by the fence
var uniformed := false
var state := "arrive" # arrive -> change (3 s in the barracks) -> live
var mode := "" # what happens on arrival: "" idle a bit, "inside" hide, "lie" lie down
var target := Vector2.ZERO
var wait := 0.0 # seconds left at the current waypoint
var leg := 0.0 # seconds left for the current walk before giving up (blocked path)
var nav := {}
var fence_angle := randf() * TAU
var sprite: Sprite2D
var anim := 0.0 # seconds into the current work or firing animation, 0 when idle
var gear := "": # "rifle", "tool" (plus pistol), "pistol" or ""
	set(v):
		if v != gear:
			gear = v
			queue_redraw()


func _ready() -> void:
	sprite = Art.sprite("survivor")
	sprite.show_behind_parent = true # gear (_draw) goes on top of the body
	add_child(sprite)
	if state == "arrive":
		_go(base.door("barracks"), "inside")
	else:
		uniformed = true
		_pick()


func _process(delta: float) -> void:
	_animate(delta)
	if wait > 0.0:
		wait -= delta
		if wait <= 0.0:
			_pick()
		return
	leg -= delta
	if _walk(delta) or leg <= 0.0:
		_arrived()


## Militia on their post turn to the last shot and kick back with a flash; workers at a work spot bob with each swing.
func _animate(delta: float) -> void:
	var post := _post()
	if post == null and not _working():
		if anim > 0.0:
			anim = 0.0
			sprite.position = Vector2.ZERO
			sprite.rotation = 0.0
			queue_redraw()
		return
	anim += delta
	if post != null:
		sprite.rotation = post.aim.angle() + PI / 2
		sprite.position = -post.aim * (1.0 if post.shot > 0.0 else 0.0)
	else:
		sprite.position.y = -absf(sin(anim * 9.0))
	queue_redraw()


## The defender post (turret.gd) this militia pawn stands on during an assault, else null.
func _post() -> Node2D:
	if job != "militia" or not Game.attack_active or slot >= base.defenders.get_child_count():
		return null
	var p: Node2D = base.defenders.get_child(slot)
	return p if global_position.distance_to(p.global_position) < 8.0 else null


func _working() -> bool:
	return wait > 0.0 and mode == "" and job in WORK_JOBS and not Game.is_night() and state == "live"


## nav_move (main.gd) when the world has it, else a straight walk.
func _walk(delta: float) -> bool:
	if Game.world.has_method("nav_move"):
		return Game.world.nav_move(self, target, SPEED, delta, nav)
	global_position = global_position.move_toward(target, SPEED * delta)
	return global_position.distance_to(target) < 1.0


func _go(to: Vector2, m := "") -> void:
	target = to
	mode = m
	nav = {}
	leg = 4.0 + global_position.distance_to(to) / SPEED * 2.0


func _arrived() -> void:
	if state == "arrive":
		state = "change"
		visible = false
		wait = 3.0
		return
	if mode == "inside":
		visible = false
	elif mode == "lie":
		rotation = PI / 2
	wait = randf_range(2.0, 5.0)


## Next waypoint for the job; also wakes the pawn up (visible, standing, tinted, geared) unless it stays put.
func _pick() -> void:
	if state == "change":
		state = "live"
		uniformed = true
	var hurt := job == "injured"
	sprite.modulate = HURT if hurt else (OLIVE if uniformed else Color.WHITE)
	gear = "" if hurt else ("rifle" if job == "militia" else ("tool" if job in TOOL_JOBS else "pistol"))
	var home: Vector2 = base.global_position
	if hurt:
		_go(base.door("clinic") + Vector2(slot % 4 * 6 - 9, -10), "lie")
	elif job == "militia":
		var posts: Node2D = base.defenders
		_go(posts.get_child(slot).global_position if Game.attack_active and slot < posts.get_child_count() else _patrol())
	elif Game.is_night() and camper:
		_go(home + Vector2(Game.base_radius - 14, 0).rotated(fence_angle), "lie")
	elif Game.is_night():
		_go(base.door("barracks"), "inside")
	elif job in TOOL_JOBS:
		_go(_work_spot())
	elif job == "farm":
		var fields: Array = base.field_cells()
		_go(fields.pick_random() if not fields.is_empty() else _around(home, Game.base_radius * 0.6))
	elif job == "medic":
		_go(_around(base.door("clinic"), 14))
	elif job == "water":
		var w: Variant = base.water_point()
		_go(base.door("hangar") if w == null or global_position.distance_to(w) < 24.0 else w)
	else:
		_go(_around(base.door("barracks"), 24))
	var stay := global_position.distance_to(target) < 2.0 # asleep in the barracks or lying down: no flicker
	visible = not (stay and mode == "inside")
	rotation = PI / 2 if stay and mode == "lie" else 0.0


## Militia walk the sandbag line and watchtowers, a step behind them; a 60 px ring without any.
func _patrol() -> Vector2:
	var home: Vector2 = base.global_position
	var spots: Array = Game.sandbags.keys().map(base.cell_pos)
	for b in Game.buildings:
		if b["kind"] == "watchtower" and b["built"]:
			spots.append(base.cell_pos(b["cell"]))
	if spots.is_empty():
		return home + Vector2(60, 0).rotated(randf() * TAU)
	var p: Vector2 = spots.pick_random()
	return p + (home - p).normalized() * 10.0


## Tool jobs shuttle between the hangar, the fuel depot area and blueprints (Build workers go to the blueprint).
func _work_spot() -> Vector2:
	var spots: Array = [base.door("hangar"), base.global_position + DEPOT]
	var site: Dictionary = base.next_site()
	var cell: Variant = base._nearest_blueprint() if site.is_empty() else site["cell"]
	if not site.is_empty() and site["kind"] == "perimeter":
		spots.append(base.global_position + Vector2(Game.base_radius - 10, 0).rotated(fence_angle))
	elif cell != null:
		spots.append(base.cell_pos(cell) + Vector2(0, 14))
	return spots[-1] if job == "build" and spots.size() > 2 else spots.pick_random()


func _around(p: Vector2, r: float) -> Vector2:
	return p + Vector2(randf_range(-r, r), randf_range(-r, r) * 0.5)


func _draw() -> void:
	var post := _post()
	if post != null: # rifle along the aim, flash at the muzzle
		var a: Vector2 = post.aim
		var r := a.orthogonal() * 1.5 + sprite.position
		draw_line(r + a, r + a * 7.0, DARK, 1.0)
		if post.shot > 0.0:
			draw_circle(r + a * 8.5, 1.8, FLASH)
			draw_circle(r + a * 8.5, 0.8, Color.WHITE)
		return
	if anim > 0.0:
		var s := sin(anim * 9.0)
		if job in TOOL_JOBS + ["farm"] and s > 0.6: # dust where the swing lands
			var a := (s - 0.6) / 0.4 * 0.7
			draw_circle(Vector2(6.5, 4), 1.4, Color(DUST, a))
			draw_circle(Vector2(5, 5), 1.0, Color(DUST, a * 0.8))
		if gear == "tool": # hammer swinging from the hand
			draw_set_transform(Vector2(3, 2) + sprite.position, s * 0.9 - 0.3)
			draw_line(Vector2.ZERO, Vector2(2, -3), GREY, 1.0)
			draw_line(Vector2(1, -4), Vector2(3, -2.5), GREY, 1.0)
			draw_set_transform(Vector2.ZERO)
			draw_rect(Rect2(-4, 1, 2, 2), DARK)
			return
	if gear == "rifle":
		draw_line(Vector2(-1, 2), Vector2(5, -1), DARK, 1.0)
	if gear == "tool": # hammer: handle and head
		draw_line(Vector2(3, 2), Vector2(5, -1), GREY, 1.0)
		draw_line(Vector2(4, -2), Vector2(6, -0.5), GREY, 1.0)
	if gear in ["tool", "pistol"]:
		draw_rect(Rect2(-4, 1, 2, 2), DARK)
