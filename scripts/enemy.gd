extends Node2D
## Zombies. All melee, all on the ground: flying is safe, landing is not.
## They roam, raid settlements, follow noise, and swarm a landed heli.
## target_base = true during base assaults. They path around houses, hedges, water, rock and sandbags (main.gd
## nav_move); walled in, they chew through sandbags and break into houses. They wade slowly through forest and are
## hard to see there.

const KINDS := {
	"shambler": {"hp": 45.0, "speed": 16.0, "dmg": 8.0, "xp": 4, "radius": 8.0},
	"runner": {"hp": 25.0, "speed": 58.0, "dmg": 6.0, "xp": 6, "radius": 7.0},
	"brute": {"hp": 220.0, "speed": 13.0, "dmg": 28.0, "xp": 25, "radius": 11.0},
	"boss": {"hp": 2200.0, "speed": 12.0, "dmg": 45.0, "xp": 300, "radius": 22.0, "boss": true},
}
const MELEE_INTERVAL := 1.0
const RAID_INTERVAL := 5.0 # seconds per survivor killed at a settlement
const AGGRO_DIST := 380.0 # landed heli closer than this gets swarmed
const GOAL_DIST := 900.0 # how far zombies look for a settlement
const DESPAWN_DIST := 2400.0
const PREY_DIST := 90.0 # visible survivors closer than this get attacked
const CHEW_TIME := 6.0 # seconds of pushing against a house before breaking in
const STUCK_TIME := 2.0 # seconds without path progress before chewing at what blocks the way
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
	var cell := Vector2i((position / 16.0).floor())
	if Game.sandbags.get(cell, {}).get("kind", "") == "wire" and Game.sandbags[cell]["built"]: # barbed wire: crawl through it bleeding, wearing it down
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
	if _system_hooks(delta):
		return
	# 1. base assault
	if target_base:
		_approach(delta, Game.world.base, radius + 50.0, Game.world.base.take_damage)
		return
	# 2. waiting or boarding survivors close by
	var prey := _find_prey()
	if prey:
		_approach(delta, prey, radius + 4.0, func(_d): prey.get_parent().lose_survivor_node(prey))
		return
	# 3. landed heli: everything nearby converges
	if heli.landed and to_heli.length() < AGGRO_DIST:
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


func hit(amount: float) -> void:
	hp -= amount
	sprite.modulate = Color(1, 0.5, 0.5, sprite.modulate.a)
	get_tree().create_timer(0.08).timeout.connect(func(): if is_instance_valid(self): sprite.modulate = Color(1, 1, 1, 0.4 if concealed else 1.0))
	Sfx.play("hit", global_position, -14.0)
	if hp <= 0.0:
		_die()


func _die() -> void:
	Game.kills += 1
	Game.add_xp(cfg["xp"])
	if randf() < 0.02:
		Game.base_rifles += 1.0 # a rifle off the body, goes to the base armory
	if randf() < 0.2 or cfg.get("boss", false):
		if cfg.get("boss", false): Game.scrap += int((2 + int(cfg["xp"] / 4)) * Game.stats["scrap_gain"])
		else: Game.salvage["metal"] += 1.0
		if Progression.level("scavenger") >= 5:
			Game.ammo = mini(Game.max_ammo, Game.ammo + 10)
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
