extends Node2D
## Zombies. All melee, all on the ground: flying is safe, landing is not.
## They roam, raid settlements, follow noise, and swarm a landed heli.
## target_base = true during base assaults. They path around houses, hedges, water, rock and sandbags (main.gd
## nav_move); walled in, they chew through sandbags and break into houses. They wade slowly through forest and are
## hard to see there. A chase (survivor or landed heli) ends after CHASE_MAX s without reaching the target or
## LOSE_SIGHT s with houses, hedges or woods in between; that target is then ignored for GIVE_UP s.

const KILL_SCRAP := 1 # every kill strips some scrap off the gear (playtest 0.7.0: scrap ran short)
const KINDS := {
	"shambler": {"hp": 45.0, "speed": 12.0, "dmg": 8.0, "xp": 4, "radius": 8.0},
	"runner": {"hp": 25.0, "speed": 42.0, "dmg": 6.0, "xp": 6, "radius": 7.0},
	"brute": {"hp": 220.0, "speed": 10.0, "dmg": 28.0, "xp": 25, "radius": 11.0},
	"boss": {"hp": 2200.0, "speed": 9.0, "dmg": 45.0, "xp": 300, "radius": 22.0, "boss": true},
	# the new infected (P9); ability / front_armor / death: scripts/infected.gd, wire_proof: crawls under barbed wire
	"screamer": {"hp": 30.0, "speed": 14.0, "dmg": 4.0, "xp": 12, "radius": 7.0, "ability": "scream"},
	"spitter": {"hp": 40.0, "speed": 12.0, "dmg": 6.0, "xp": 10, "radius": 7.0, "ability": "spit", "blood": Color(0.6, 0.7, 0.2)},
	"crawler": {"hp": 35.0, "speed": 26.0, "dmg": 7.0, "xp": 8, "radius": 5.0, "wire_proof": true}, # radius 5 = 40 % less to hit
	"bloater": {"hp": 320.0, "speed": 7.0, "dmg": 12.0, "xp": 30, "radius": 12.0, "death": "gas", "blood": Color(0.6, 0.7, 0.2)},
	"brute_armored": {"hp": 300.0, "speed": 10.0, "dmg": 32.0, "xp": 45, "radius": 11.0, "front_armor": 0.7},
}
const HEAD_MULT := 2.0 # headshots (bullet.gd)
const KNOCK := 110.0 # px/s kick of a hit on a radius-8 enemy, lighter on big ones
const KNOCK_DECAY := 900.0
const MELEE_INTERVAL := 1.0
const RAID_INTERVAL := 5.0 # seconds per survivor killed at a settlement
const AGGRO_DIST := 380.0 # landed heli closer than this gets swarmed
const GOAL_DIST := 900.0 # how far zombies look for a settlement
const DESPAWN_DIST := 2400.0
const PREY_DIST := 90.0 # visible survivors closer than this get attacked
const CHEW_TIME := 6.0 # seconds of pushing against a house before breaking in
const STUCK_TIME := 2.0 # seconds without path progress before chewing at what blocks the way
const CHASE_MAX := 40.0
const LOSE_SIGHT := 4.0
const GIVE_UP := 20.0
const SIGHT_WALLS := [T.BUILDING, T.WAREHOUSE, T.HEDGE]
const T := preload("res://scripts/chunk_manager.gd").T

static var break_in_ms := -100000 # last "broke into a house" radio line, shared by all zombies

var kind := "shambler"
var cfg := {}
var hp := 30.0
var max_hp := 30.0
var radius := 8.0
var speed := 20.0
var dmg := 8.0
var target_base := false
var attack_cd := 0.0
var spawn_cd := 10.0
var goal: Node2D # settlement POI being raided
var goal_cd := 0.0
var wander := Vector2.ZERO
var wander_cd := 0.0
var sprite: Sprite2D
# heli systems (scripts/systems): searchlight slow/stun, loudspeaker panic, flare decoys
var slowed := 0.0 # fraction of speed lost, set each frame by the searchlight
var stun_left := 0.0
var panic_left := 0.0
var panic_from := Vector2.ZERO
var chew_t := 0.0
var nav := {} # main.gd nav_move state
var concealed := false # standing in forest: faded sprite, off the minimap
var chased: Node2D # current chase target
var chase_t := 0.0 # seconds chasing `chased` without being in reach
var unseen_t := 0.0 # seconds `chased` has been out of sight
var sight_cd := 0.0 # line of sight is sampled 4x a second
var seen := true
var ignored := {} # instance id -> msec until which that target is left alone
var state := {} # ability state (infected.gd), saved with the enemy
var spit_target := [] # spitter: [position, impact callable], runtime only
var kick := Vector2.ZERO # knockback velocity, fades out


func setup(kind_name: String, pos: Vector2, danger: float, base_target := false) -> void:
	kind = kind_name
	cfg = KINDS[kind]
	position = pos
	target_base = base_target
	max_hp = cfg["hp"] * (0.7 + danger * 0.3)
	hp = max_hp
	radius = cfg["radius"]
	speed = cfg["speed"] * randf_range(0.85, 1.15) * (0.9 + danger * 0.1)
	dmg = cfg["dmg"] * (0.8 + danger * 0.2)


func _ready() -> void:
	add_to_group("enemies")
	z_index = 2
	sprite = Art.sprite(kind)
	add_child(sprite)


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	if kick != Vector2.ZERO:
		position += Game.world.slide(position, kick * delta)
		kick = kick.move_toward(Vector2.ZERO, KNOCK_DECAY * delta)
	var cell := Vector2i((position / 16.0).floor())
	if not cfg.get("wire_proof", false) and Game.sandbags.get(cell, {}).get("kind", "") == "wire" and Game.sandbags[cell]["built"]: # barbed wire: crawl through it bleeding, wearing it down
		slowed = maxf(slowed, Game.WIRE_SLOW)
		Game.world.base.damage_sandbag(cell, delta)
		hp -= Game.WIRE_DPS * delta
		if hp <= 0.0:
			_die()
			return
	delta *= 1.0 - slowed
	slowed = 0.0
	attack_cd -= delta
	var heli: Node2D = Game.heli
	var to_heli: Vector2 = heli.global_position - global_position
	if not target_base and to_heli.length() > DESPAWN_DIST:
		queue_free()
		return
	if cfg.get("boss", false):
		spawn_cd -= delta
		if spawn_cd <= 0.0:
			spawn_cd = 10.0
			for i in 2:
				Game.world.spawn_enemy("runner", global_position + Vector2(30, 0).rotated(randf() * TAU), target_base)
	if _system_hooks(delta) or Infected.tick(self, delta) or Assault.ram(self, delta):
		return
	# 1. base assault
	if target_base:
		_approach(delta, Game.world.base, radius + 50.0, Game.world.base.take_damage)
		return
	# 2. waiting or boarding survivors close by
	var prey := _find_prey()
	if prey and _pursue(prey, radius + 4.0, delta):
		_approach(delta, prey, radius + 4.0, func(_d): prey.get_parent().lose_survivor_node(prey))
		return
	# 3. landed heli: everything nearby converges
	if heli.landed and to_heli.length() < AGGRO_DIST and _pursue(heli, radius + heli.RADIUS + 4.0, delta):
		_approach(delta, heli, radius + heli.RADIUS + 4.0, heli.take_damage)
		return
	# 4. investigate noise (gunfire, rotor): harmless in the air, deadly once you land
	if Game.noise_level > 0.15:
		var to_noise: Vector2 = Game.noise_pos - global_position
		var nd := to_noise.length()
		if nd > 24.0 and nd < 120.0 + 300.0 * Game.noise_level:
			_walk(Game.noise_pos, delta, 0.8)
			return
	# 5. raid the nearest settlement
	goal_cd -= delta
	if (goal == null or not is_instance_valid(goal) or goal.done) and goal_cd <= 0.0:
		goal_cd = 5.0
		goal = _find_settlement()
	if goal and is_instance_valid(goal) and not goal.done:
		_approach(delta, goal, 40.0, func(_d): goal.lose_survivor(), RAID_INTERVAL)
		return
	# 6. wander
	wander_cd -= delta
	if wander_cd <= 0.0:
		wander_cd = randf_range(2.0, 6.0)
		wander = Vector2.RIGHT.rotated(randf() * TAU) * (0.0 if randf() < 0.4 else 1.0)
	_face(wander)
	_step(wander, delta, 0.5)


## Keep after `target`? False once the chase ran CHASE_MAX s without reaching it or lost sight for LOSE_SIGHT s;
## the target is then ignored for GIVE_UP s and the zombie falls through to its other goals.
func _pursue(target: Node2D, reach: float, delta: float) -> bool:
	var id := target.get_instance_id()
	if ignored.get(id, 0) > Time.get_ticks_msec():
		return false
	if target != chased:
		chased = target
		chase_t = 0.0
		unseen_t = 0.0
		sight_cd = 0.0
	sight_cd -= delta
	if sight_cd <= 0.0:
		sight_cd = 0.25
		seen = _sees(target.global_position)
	unseen_t = 0.0 if seen else unseen_t + delta
	chase_t = 0.0 if global_position.distance_to(target.global_position) <= reach + 8.0 else chase_t + delta
	if chase_t > CHASE_MAX or unseen_t > LOSE_SIGHT:
		ignored[id] = Time.get_ticks_msec() + int(GIVE_UP * 1000.0)
		chased = null
		wander_cd = 0.0
		return false
	return true


## No house, warehouse or hedge and at most 40 px of woods on the line to `at`.
func _sees(at: Vector2) -> bool:
	var n := ceili(global_position.distance_to(at) / 8.0)
	var woods := 0
	for i in range(1, n):
		var t: int = Game.world.chunks.tile_at(global_position.lerp(at, float(i) / n))
		woods += int(t == T.FOREST)
		if t in SIGHT_WALLS or woods > 5:
			return false
	return true


func _face(dir: Vector2) -> void:
	if dir.length_squared() > 0.01:
		rotation = lerp_angle(rotation, dir.angle() + PI / 2, 0.15)


## Walk to `target`; within `reach`, call `strike(dmg)` every `interval` seconds.
func _approach(delta: float, target: Node2D, reach: float, strike: Callable, interval := MELEE_INTERVAL) -> void:
	var to_target: Vector2 = target.global_position - global_position
	if to_target.length() > reach:
		_walk(target.global_position, delta)
	else:
		_face(to_target)
		if attack_cd <= 0.0:
			attack_cd = interval
			strike.call(dmg)


## Path to `to` (main.gd nav_move); after STUCK_TIME without progress (walled in), chew through what is in the way.
func _walk(to: Vector2, delta: float, factor := 1.0) -> void:
	var before := position
	Game.world.nav_move(self, to, _pace(factor), delta, nav)
	_face(position - before)
	if nav["stuck"] < STUCK_TIME:
		return
	var d := (to - position).normalized() * 10.0
	for s in [d, Vector2(signf(d.x) * 10.0, 0), Vector2(0, signf(d.y) * 10.0)]:
		if not Game.world.is_walkable(position + s):
			_chew(Vector2i(((position + s) / 16.0).floor()), delta)
			return


## Move along `dir` at speed * factor, sliding along solid cells (main.gd slide), chewing what stops it.
func _step(dir: Vector2, delta: float, factor := 1.0) -> void:
	var v := dir.normalized() * _pace(factor) * delta
	var move: Vector2 = Game.world.slide(position, v)
	if move != v:
		_chew(Vector2i(((position + v) / 16.0).floor()), delta)
	position += move


## speed * factor, halved in forest (where the zombie is also faded and off the minimap).
func _pace(factor: float) -> float:
	var t: int = Game.world.chunks.tile_at(position)
	concealed = t == T.FOREST or t == T.TREE_EDGE
	sprite.modulate.a = 0.4 if concealed else 1.0
	return speed * factor * (0.5 if concealed else 1.0)


## Pushing into `cell`: hit a built sandbag every MELEE_INTERVAL, break into a house after CHEW_TIME.
func _chew(cell: Vector2i, delta: float) -> void:
	if Game.sandbags.get(cell, {}).get("built", false):
		if attack_cd <= 0.0:
			attack_cd = MELEE_INTERVAL
			Game.world.base.damage_sandbag(cell, dmg)
	elif Game.world.chunks.get_cell_atlas_coords(cell).x == T.BUILDING:
		chew_t += delta
		if chew_t > CHEW_TIME:
			chew_t = 0.0
			Game.world.chunks.break_in(cell)
			if Game.heli.global_position.distance_to(global_position) < 600.0 and Time.get_ticks_msec() - break_in_ms > 20000:
				break_in_ms = Time.get_ticks_msec()
				Game.radio("Zombies broke into a house")


## Nearest visible survivor of an unfinished settlement within PREY_DIST (hideout people stay hidden until landing).
func _find_prey() -> Node2D:
	var best: Node2D
	var best_d := PREY_DIST * PREY_DIST
	for s in get_tree().get_nodes_in_group("survivors"):
		var d: float = global_position.distance_squared_to(s.global_position)
		if d < best_d and s.visible and not s.get_parent().done:
			best_d = d
			best = s
	return best


func _find_settlement() -> Node2D:
	var best: Node2D
	var best_d := GOAL_DIST * GOAL_DIST
	for p in Game.world.pois:
		if not is_instance_valid(p) or p.kind != "survivors" or p.done:
			continue
		var d: float = global_position.distance_squared_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func unflash() -> void:
	sprite.modulate = Color(1, 1, 1, 0.4 if concealed else 1.0)


## `dir`: the way the shot flies (zero for splash), `head`: a headshot. Shots into the front of an armored one count 30 %.
func hit(amount: float, dir := Vector2.ZERO, head := false) -> void:
	if is_queued_for_deletion():
		return # a second pellet in the frame it died
	var armor := Infected.armor_mult(self, dir)
	hp -= amount * armor * (HEAD_MULT if head else 1.0)
	kick = (kick + dir * KNOCK * clampf(amount / 14.0, 0.5, 2.0) * 8.0 / radius).limit_length(KNOCK * 2.0)
	HitFx.hit(self, dir, head, armor < 1.0)
	if hp <= 0.0:
		_die()


func _die() -> void:
	Game.kills += 1
	Game.scrap += KILL_SCRAP
	Game.add_xp(cfg["xp"] * Assault.xp_mult(self))
	if randf() < 0.02:
		Game.base_rifles += 1.0 # a rifle off the body, goes to the base armory
	if randf() < 0.2 or cfg.get("boss", false):
		if cfg.get("boss", false): Game.scrap += int((2 + int(cfg["xp"] / 4)) * Game.stats["scrap_gain"])
		else: Game.salvage["metal"] += 1.0
		if Progression.level("scavenger") >= 5:
			Game.ammo = mini(Game.max_ammo, Game.ammo + 10)
	HitFx.death(self)
	Infected.on_death(self)
	Game.world.spawn_fx(global_position, 2.0 if cfg.get("boss", false) else 0.7)
	Sfx.play("explosion" if cfg.get("boss", false) else "enemy_die", global_position)
	if cfg.get("boss", false):
		Game.radio("Abomination down! Outstanding, gunner.")
		Game.meta["boss_kills"] += 1
		Sfx.play("boss_roar", global_position)
	queue_free()


## Searchlight Lv5: freeze for `seconds`, then immune for 4 s.
func stun(seconds: float) -> void:
	if stun_left <= -4.0:
		stun_left = seconds


## Loudspeaker Lv5: run away from `from` for `seconds`.
func panic(from: Vector2, seconds: float) -> void:
	panic_from = from
	panic_left = seconds


## Stun, panic and flare decoys (Lv5 flares join group "decoys") override the normal goals. True = handled.
func _system_hooks(delta: float) -> bool:
	stun_left -= delta
	panic_left -= delta
	if stun_left > 0.0:
		return true
	if panic_left > 0.0:
		var away := global_position - panic_from
		_face(away)
		_step(away, delta)
		return true
	var best: Node2D
	var best_d := 400.0 * 400.0
	for d in get_tree().get_nodes_in_group("decoys"):
		if global_position.distance_squared_to(d.global_position) < best_d:
			best_d = global_position.distance_squared_to(d.global_position)
			best = d
	if best == null:
		return false
	_approach(delta, best, radius + 6.0, best.hit)
	return true
