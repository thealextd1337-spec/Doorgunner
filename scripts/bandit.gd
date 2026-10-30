class_name Bandit
extends Node2D
## Bandit units (docs/ROADMAP.md P11), spawned, tracked and saved by bandits.gd. In group "enemies" (player bullets,
## turrets and the base alert treat them like zombies) and "bandits" (zombies go for them: foe_for, enemy.gd).
## Unlike zombies they shoot the heli, flying or landed: hitscan rounds whose chance falls with distance, the heli's
## speed and darkness (chance()). Zombies within ZOMBIE_SIGHT come first: bandits shoot them, and gunfire is noise.
## Kinds (KINDS):
##   rifle: infantry. Under the heli's fire it runs for cover (a free cell next to a house, hedge or woods within
##     COVER_CELLS); in cover COVER_MISS of the rounds that reach it miss.
##   mg: a static machine-gun nest at a camp, firing bursts.
##   rpg: aims RPG_AIM s at the heli (red line, radio warning), then fires a homing Rocket. Flares (group
##     "rocket_decoys", flares.gd) within DECOY_RANGE of the rocket pull it off; a hard turn may outrun its turn rate.
##   technical: technical.gd, a pickup with an MG that drives the roads.
## role: "guard" (stays by its camp), "patrol" (walks to `goal`, then bandits.gd decides), "raid" (takes survivors
## from the settlement POI `poi_uid`), "home" (walks back to the camp and rejoins it), "base" (attacks the FOB from `goal`).

const KINDS := {
	"rifle": {"hp": 60.0, "speed": 24.0, "range": 260.0, "interval": 1.6, "burst": 1, "dmg": 3.0, "zdmg": 14.0, "chance": 0.5, "xp": 15, "radius": 6.0, "sprite": "bandit"},
	"mg": {"hp": 150.0, "speed": 0.0, "range": 320.0, "interval": 3.0, "burst": 5, "dmg": 2.0, "zdmg": 10.0, "chance": 0.35, "xp": 30, "radius": 9.0, "sprite": "mg_nest"},
	"rpg": {"hp": 70.0, "speed": 22.0, "range": 380.0, "interval": 10.0, "burst": 1, "dmg": 25.0, "zdmg": 10.0, "chance": 1.0, "xp": 25, "radius": 6.0, "sprite": "bandit_rpg"},
	"technical": {"hp": 280.0, "speed": 55.0, "range": 340.0, "interval": 2.6, "burst": 6, "dmg": 2.0, "zdmg": 10.0, "chance": 0.35, "xp": 60, "radius": 12.0, "sprite": "technical"},
}
const CHANCE_FALLOFF := 0.6 # at full range a round hits 40 % as often as point-blank
const CHANCE_SPEED := 0.5 # a heli at top speed is hit half as often
const CHANCE_DARK := 0.4 # and at darkest night 40 % less
const LANDED_MULT := 1.5 # a parked heli is an easy target
const BURST_GAP := 0.12
const ZOMBIE_SIGHT := 170.0
const ZOMBIE_CHANCE := 0.6
const ZOMBIE_INTERVAL := 1.2
const FOE_SIGHT := 140.0 # zombies notice bandits this close (gunfire noise draws them from farther)
const FOE_LOOK := 0.5
const NOISE := 0.7 # Game.noise_level of a round: zombies within 120 + 300 * 0.7 = 330 px come
const COVER_CELLS := 6
const COVER_MISS := 0.5
const COVER := [T.BUILDING, T.WAREHOUSE, T.HEDGE, T.FOREST, T.TREE_EDGE, T.ROCK]
const UNDER_FIRE := 6.0 # seconds a hit from the heli keeps a rifleman looking for cover
const THINK := 0.5
const GUARD_ROAM := 70.0
const DESPAWN_DIST := 2400.0 # patrols and raiders this far from the heli are dropped
const STUCK_RETRY := 4.0 # s without progress before a raider looks for another firing spot
const RPG_AIM := 1.5
const ROCKET_SPEED := 210.0
const ROCKET_TURN := 1.8 # rad/s: a heli crossing at speed can out-turn it
const ROCKET_LIFE := 3.5
const ROCKET_HIT := 12.0
const DECOY_RANGE := 260.0
const BASE_CHANCE := 0.5
const BASE_DMG := 3.0
const ABDUCT_INTERVAL := 6.0
const KILL_SCRAP := 2
const HEAD_MULT := 2.0 # headshots, as for zombies
const RIFLE_DROP := 0.2 # chance a dead bandit's gun goes to the base armory
const TRACER_TIME := 0.06
const T := preload("res://scripts/chunk_manager.gd").T
const NONE := Vector2(INF, INF)

static var _warn_ms := -100000 # last RPG radio warning, shared

var kind := "rifle"
var cfg := {}
var hp := 60.0
var max_hp := 60.0
var radius := 6.0
var speed := 24.0
var role := "guard"
var camp_uid := ""
var home := Vector2.ZERO
var goal := Vector2.ZERO
var poi_uid := ""
var target: Node2D
var think_cd := 0.0
var fire_cd := 0.0
var burst_left := 0
var gap_cd := 0.0
var aim_t := 0.0 # rpg: seconds aimed at the current target
var cover := NONE
var in_cover := false
var under_fire := 0.0
var abduct_cd := ABDUCT_INTERVAL
var nav := {} # main.gd nav_move state
var sprite: Sprite2D
var tracer := Vector2.ZERO # local end of the last round's tracer
var tracer_t := 0.0
var concealed := false # HitFx reads it


func setup(kind_name: String, pos: Vector2, unit_role: String, home_pos: Vector2, danger: float) -> void:
	kind = kind_name
	cfg = KINDS[kind]
	position = pos
	role = unit_role
	home = home_pos
	goal = pos
	max_hp = cfg["hp"] * (0.7 + danger * 0.3)
	hp = max_hp
	radius = cfg["radius"]
	speed = cfg["speed"] * randf_range(0.9, 1.1)
	think_cd = randf() * THINK
	fire_cd = randf() * cfg["interval"]


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("bandits")
	z_index = 2
	sprite = Art.sprite(cfg["sprite"])
	add_child(sprite)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	tracer_t -= delta
	under_fire -= delta
	think_cd -= delta
	if think_cd <= 0.0:
		think_cd = THINK * randf_range(0.8, 1.2)
		_think()
		if is_queued_for_deletion():
			return
	_move(delta)
	_shoot(delta)
	if tracer_t > -0.1 or aim_t > 0.0:
		queue_redraw()


## Twice a second: what to shoot at and where to stand.
func _think() -> void:
	var heli: Node2D = Game.heli
	var base: Node2D = Game.world.base
	var hd := global_position.distance_to(heli.global_position)
	if role in ["patrol", "raid", "home"] and hd > DESPAWN_DIST:
		Game.world.bandits.unit_gone(self)
		queue_free()
		return
	target = _nearest_zombie()
	if target == null and hd <= cfg["range"]:
		target = heli
	elif target == null and role == "base" and global_position.distance_to(base.global_position) <= Game.base_radius + Game.world.bandits.RAID_STANDOFF + 40.0:
		target = base
	in_cover = _cover_here()
	if kind == "rifle" and (target == heli or under_fire > 0.0):
		if cover == NONE or cover.distance_to(global_position) > COVER_CELLS * 24.0:
			cover = _find_cover()
		goal = cover if cover != NONE else global_position
		return
	cover = NONE
	if target != null and target != base:
		goal = global_position # stand and shoot
		return
	match role:
		"guard":
			if global_position.distance_to(goal) < 8.0 or goal.distance_to(home) > GUARD_ROAM * 1.5:
				goal = _walkable_near(home, GUARD_ROAM)
		"patrol":
			if global_position.distance_to(goal) < 24.0:
				Game.world.bandits.patrol_arrived(self)
		"raid":
			var p: Node2D = Game.world.bandits.poi(poi_uid)
			if p == null or p.done:
				role = "home"
			else:
				goal = p.global_position
				if global_position.distance_to(goal) < 48.0:
					abduct_cd -= THINK
					if abduct_cd <= 0.0:
						abduct_cd = ABDUCT_INTERVAL
						Game.world.bandits.abduct(self, p)
		"base":
			if nav.get("stuck", 0.0) > STUCK_RETRY: # no way to this spot (water, walls): try another side of the fence
				nav["stuck"] = 0.0
				var base_pos: Vector2 = Game.world.base.global_position
				goal = _walkable_near(base_pos + (global_position - base_pos).normalized().rotated(randf_range(-1.2, 1.2)) * (Game.base_radius + Game.world.bandits.RAID_STANDOFF), 24.0)
		"home":
			goal = home
			if global_position.distance_to(home) < 40.0:
				Game.world.bandits.unit_home(self)


func _move(delta: float) -> void:
	if speed <= 0.0 or global_position.distance_to(goal) < 6.0:
		if target != null:
			_face(target.global_position - global_position)
		return
	var before := position
	Game.world.nav_move(self, goal, speed, delta, nav)
	_face(target.global_position - global_position if target != null else position - before)


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 0.01:
		sprite.rotation = lerp_angle(sprite.rotation, dir.angle() + PI / 2, 0.2)


func _shoot(delta: float) -> void:
	fire_cd -= delta
	gap_cd -= delta
	if target == null or not is_instance_valid(target) or target.is_queued_for_deletion():
		target = null
		aim_t = 0.0
		return
	var zombie: bool = target != Game.heli and target != Game.world.base
	if kind == "rpg" and not zombie:
		if fire_cd > 0.0:
			return
		if aim_t == 0.0 and target == Game.heli and Time.get_ticks_msec() - _warn_ms > 8000:
			_warn_ms = Time.get_ticks_msec()
			Game.radio("Pilot: RPG! Break hard or pop flares!")
		aim_t += delta
		if aim_t >= RPG_AIM:
			aim_t = 0.0
			fire_cd = cfg["interval"]
			fire_rocket(target)
		return
	aim_t = 0.0
	if burst_left <= 0 and fire_cd <= 0.0:
		burst_left = 1 if zombie else cfg["burst"]
		fire_cd = ZOMBIE_INTERVAL if zombie else cfg["interval"]
	if burst_left > 0 and gap_cd <= 0.0:
		burst_left -= 1
		gap_cd = BURST_GAP
		_round(target)


## One hitscan round at `t`: the heli, the base or a zombie.
func _round(t: Node2D) -> void:
	var to: Vector2 = t.global_position - global_position
	var heli: bool = t == Game.heli
	var base: bool = t == Game.world.base
	var hit_it := randf() < (chance(to.length()) if heli else (BASE_CHANCE if base else ZOMBIE_CHANCE))
	tracer = to + (Vector2.ZERO if hit_it else Vector2(randf_range(-28, 28), randf_range(-28, 28)))
	tracer_t = TRACER_TIME
	Sfx.play("gun", global_position, -16.0)
	Game.make_noise(global_position, NOISE)
	if not hit_it:
		return
	if heli:
		t.take_damage(cfg["dmg"], "bandit")
	elif base:
		t.take_damage(BASE_DMG)
	else:
		t.hit(cfg["zdmg"], to.normalized())


## Chance of one round hitting the heli `d` px away.
func chance(d: float) -> float:
	var heli: Node2D = Game.heli
	var p: float = cfg["chance"] * (1.0 - CHANCE_FALLOFF * clampf(d / cfg["range"], 0.0, 1.0))
	p *= 1.0 - CHANCE_SPEED * clampf(heli.vel.length() / heli.MAX_SPEED, 0.0, 1.0)
	p *= 1.0 - CHANCE_DARK * Game.darkness()
	return p * (LANDED_MULT if heli.landed else 1.0)


func fire_rocket(t: Node2D) -> Node2D:
	var r := Rocket.new()
	r.position = global_position
	r.dir = (t.global_position - global_position).normalized()
	r.target = t
	r.dmg = cfg["dmg"]
	Game.world.add_child(r)
	Sfx.play("explosion", global_position, -14.0)
	return r


func _nearest_zombie() -> Node2D:
	var best: Node2D
	var best_d := ZOMBIE_SIGHT * ZOMBIE_SIGHT
	for e in get_tree().get_nodes_in_group("enemies"):
		if not "target_base" in e: # bandits, dens
			continue
		var d := global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _covers(cell: Vector2i) -> bool:
	for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		if Game.world.chunks.get_cell_atlas_coords(cell + d).x in COVER:
			return true
	return false


func _cover_here() -> bool:
	return _covers(Vector2i((global_position / 16.0).floor()))


## The nearest walkable cell centre next to cover within COVER_CELLS, else NONE.
func _find_cover() -> Vector2:
	var c0 := Vector2i((global_position / 16.0).floor())
	for r in COVER_CELLS + 1:
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				if maxi(absi(x), absi(y)) != r:
					continue
				var c := c0 + Vector2i(x, y)
				var p := Vector2(c) * 16.0 + Vector2(8, 8)
				if Game.world.is_walkable(p) and _covers(c):
					return p
	return NONE


func _walkable_near(at: Vector2, r: float) -> Vector2:
	for i in 6:
		var p := at + Vector2(randf_range(0.2, 1.0) * r, 0).rotated(randf() * TAU)
		if Game.world.is_walkable(p):
			return p
	return global_position


func unflash() -> void:
	sprite.modulate = Color.WHITE


## Player rounds (dir set), splash and zombie strikes. In cover half the rounds miss.
func hit(amount: float, dir := Vector2.ZERO, head := false) -> void:
	if is_queued_for_deletion():
		return
	if dir != Vector2.ZERO:
		under_fire = UNDER_FIRE
		think_cd = minf(think_cd, 0.1)
		if in_cover and randf() < COVER_MISS:
			HitFx.burst(global_position, -dir, HitFx.SPARK, 3, 60.0)
			return
	hp -= amount * (HEAD_MULT if head else 1.0)
	HitFx.hit(self, dir, head, false)
	if hp <= 0.0:
		_die()



func _die() -> void:
	Game.kills += 1
	Game.scrap += KILL_SCRAP
	Game.add_xp(cfg["xp"])
	if randf() < RIFLE_DROP:
		Game.base_rifles += 1.0
	HitFx.burst(global_position, Vector2.ZERO, HitFx.BLOOD, 10, 60.0)
	Game.world.spawn_fx(global_position, 1.6 if kind == "technical" else 0.7)
	Sfx.play("explosion" if kind == "technical" else "enemy_die", global_position)
	Game.world.bandits.unit_died(self)
	queue_free()


func _draw() -> void:
	if tracer_t > 0.0:
		draw_line(Vector2.ZERO, tracer, Color(1.0, 0.85, 0.45, 0.85), 1.0)
	if aim_t > 0.0 and target != null and is_instance_valid(target):
		var a := 0.35 + 0.6 * aim_t / RPG_AIM
		draw_line(Vector2.ZERO, target.global_position - global_position, Color(1.0, 0.15, 0.1, a), 1.0 + aim_t)


## For enemy.gd: the bandit zombie `e` goes for, the nearest within FOE_SIGHT, looked up every FOE_LOOK s.
static func foe_for(e: Node2D, delta: float) -> Node2D:
	var t: float = e.get_meta("foe_t", 0.0) - delta
	if t <= 0.0:
		t = FOE_LOOK
		var best: Node2D = null
		var best_d := FOE_SIGHT * FOE_SIGHT
		for b in e.get_tree().get_nodes_in_group("bandits"):
			var d: float = e.global_position.distance_squared_to(b.global_position)
			if d < best_d:
				best_d = d
				best = b
		e.set_meta("foe", [best]) # wrapped: set_meta(key, null) would erase the key
	e.set_meta("foe_t", t)
	var foe = e.get_meta("foe", [null])[0]
	return foe if is_instance_valid(foe) and not foe.is_queued_for_deletion() else null


## RPG round: flies at ROCKET_SPEED turning at most ROCKET_TURN rad/s towards its target, which a flare within
## DECOY_RANGE replaces. Explodes within ROCKET_HIT of the target or after ROCKET_LIFE s.
class Rocket extends Node2D:
	var target: Node2D
	var dir := Vector2.RIGHT
	var life := ROCKET_LIFE
	var dmg := 25.0
	var sprite: Sprite2D

	func _ready() -> void:
		add_to_group("rockets")
		z_index = 9
		sprite = Art.sprite("rocket")
		add_child(sprite)

	func _process(delta: float) -> void:
		if not Game.running:
			return
		life -= delta
		var best_d := DECOY_RANGE * DECOY_RANGE
		for d in get_tree().get_nodes_in_group("rocket_decoys"):
			if global_position.distance_squared_to(d.global_position) < best_d:
				best_d = global_position.distance_squared_to(d.global_position)
				target = d
		if life <= 0.0 or target == null or not is_instance_valid(target):
			_boom(null)
			return
		var to := target.global_position - global_position
		if to.length() < ROCKET_HIT:
			_boom(target)
			return
		dir = dir.rotated(clampf(dir.angle_to(to), -ROCKET_TURN * delta, ROCKET_TURN * delta))
		position += dir * ROCKET_SPEED * delta
		sprite.rotation = dir.angle() + PI / 2
		queue_redraw()

	func _boom(t: Node2D) -> void:
		if t != null and t == Game.heli:
			t.take_damage(dmg, "rocket")
		elif t != null and t == Game.world.base:
			t.take_damage(dmg)
		Game.world.spawn_fx(global_position, 1.0)
		Sfx.play("explosion", global_position, -4.0)
		queue_free()

	func _draw() -> void:
		draw_line(Vector2.ZERO, -dir * 14.0, Color(0.8, 0.8, 0.78, 0.5), 2.0)
