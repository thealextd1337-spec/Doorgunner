class_name Infected
## What the new infected types do beyond walking and biting (enemy.gd calls `tick` once a frame, `armor_mult` in `hit`
## and `on_death` in `_die`). Which one an enemy has is its KINDS entry: "ability" (scream, spit), "front_armor", "death".
## Per-enemy state lives in `e.state` (built-in types only, the enemy save hook stores it).
##   Screamer: within SCREAM_SIGHT of the heli (of the base in an assault) it stops, winds up SCREAM_WINDUP s (pulsing
##     red, a ring closing in) and screams: a loud noise (zombies within ~630 px come), then SCREAM_COOLDOWN s of quiet.
##     Shoot it during the wind-up and nothing happens.
##   Spitter: keeps SPIT_MIN..SPIT_MAX px from the nearest built sandbag or wire within SPIT_SIGHT (else the base in an
##     assault, else a landed heli) and spits every SPIT_INTERVAL s: the hit eats it, the puddle keeps eating for 4 s.
##   Bloater: bursts when it dies: a gas cloud for GAS_SECONDS s, and if that reaches into the base people get hurt.

const SCREAM_SIGHT := 420.0
const SCREAM_WINDUP := 3.0
const SCREAM_NOISE := 1.7 # Game.noise_level: zombies come from 120 + 300 * level px
const SCREAM_COOLDOWN := 14.0
const SPIT_SIGHT := 220.0
const SPIT_MIN := 80.0
const SPIT_MAX := 120.0
const SPIT_INTERVAL := 3.0
const SPIT_FLIGHT := 0.6
const SPIT_SANDBAG := 15.0 # at once, on top of the puddle
const ACID_RADIUS := 22.0
const ACID_SECONDS := 4.0
const GAS_RADIUS := 56.0
const GAS_SECONDS := 3.0
const GAS_INJURED := 2 # people hurt when the cloud reaches the base

static var _radio_ms := -100000


## One frame of the enemy's special behaviour. True = it moved the enemy or kept it still: skip the normal goals.
static func tick(e: Node2D, delta: float) -> bool:
	match e.cfg.get("ability", ""):
		"scream":
			return _scream(e, delta)
		"spit":
			return _spit(e, delta)
	return false


## Damage factor against a shot flying along `dir`: shots into the front of a plated enemy are mostly stopped.
static func armor_mult(e: Node2D, dir: Vector2) -> float:
	var armor: float = e.cfg.get("front_armor", 0.0)
	if armor > 0.0 and dir != Vector2.ZERO and dir.dot(Vector2.UP.rotated(e.rotation)) < -0.3:
		return 1.0 - armor
	return 1.0


static func on_death(e: Node2D) -> void:
	if e.cfg.get("death", "") != "gas":
		return
	var pos: Vector2 = e.global_position
	var puddle := Node2D.new()
	puddle.set_script(preload("res://scripts/puddle.gd"))
	puddle.setup("gas", pos, GAS_RADIUS, GAS_SECONDS)
	Game.world.add_child(puddle)
	HitFx.burst(pos, Vector2.ZERO, Color(0.55, 0.68, 0.25), 14, 70.0)
	Sfx.play("explosion", pos, -8.0)
	if Game.base_founded and pos.distance_to(Game.world.base.global_position) < Game.base_radius + GAS_RADIUS:
		Game.injure(GAS_INJURED)
		Game.radio("Base: a bloater burst at the fence, gas in the camp!")


static func _scream(e: Node2D, delta: float) -> bool:
	var s: Dictionary = e.state
	s["cd"] = s.get("cd", 0.0) - delta
	var wind: float = s.get("wind", 0.0)
	if wind <= 0.0:
		var from: Vector2 = Game.world.base.global_position if e.target_base else Game.heli.global_position
		if s["cd"] > 0.0 or e.global_position.distance_to(from) > SCREAM_SIGHT:
			return false
		wind = SCREAM_WINDUP
	wind -= delta
	var ring: Node2D = e.get_node_or_null("Ring")
	if wind > 0.0:
		if ring == null: # also after a load in mid-wind-up
			ring = Node2D.new()
			ring.name = "Ring"
			ring.draw.connect(func(): ring.draw_arc(Vector2.ZERO, 8.0 + 40.0 * float(ring.get_meta("p")), 0.0, TAU, 24, Color(1.0, 0.3, 0.25, 0.3 + 0.5 * float(ring.get_meta("p"))), 1.0))
			e.add_child(ring)
		var p := 1.0 - wind / SCREAM_WINDUP
		ring.set_meta("p", p)
		ring.queue_redraw()
		e.sprite.scale = Vector2.ONE * Art.SCALE * (1.0 + 0.18 * sin(wind * 18.0))
		e.sprite.modulate = Color(1.0, 0.65, 0.6, e.sprite.modulate.a)
		s["wind"] = wind
		return true
	if ring != null:
		ring.queue_free()
	e.sprite.scale = Vector2.ONE * Art.SCALE
	e.sprite.modulate = Color(1, 1, 1, e.sprite.modulate.a)
	s["wind"] = 0.0
	s["cd"] = SCREAM_COOLDOWN
	Game.make_noise(e.global_position, SCREAM_NOISE)
	Sfx.play("boss_roar", e.global_position, -6.0)
	if Game.heli.global_position.distance_to(e.global_position) < 700.0 and Time.get_ticks_msec() - _radio_ms > 20000:
		_radio_ms = Time.get_ticks_msec()
		Game.radio("Screamer! Everything within earshot is coming.")
	return true


## Nearest thing to spit at: [position, impact callable], or [].
static func _spit_target(e: Node2D) -> Array:
	var best := []
	var best_d := SPIT_SIGHT * SPIT_SIGHT
	var base: Node2D = Game.world.base
	var dmg: float = e.dmg # not `e` in the lambdas: the spitter may be dead when the glob lands
	for cell in Game.sandbags if e.target_base else {}: # only assault spitters: a passing horde must not eat the fence while nobody is home
		if Game.sandbags[cell]["built"]:
			var p: Vector2 = base.cell_pos(cell)
			var d := e.global_position.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = [p, func(): if Game.sandbags.has(cell): base.damage_sandbag(cell, SPIT_SANDBAG)]
	if best.is_empty() and e.target_base and e.global_position.distance_to(base.global_position) < SPIT_SIGHT + 60.0:
		best = [base.global_position, func(): base.take_damage(dmg)]
	var heli: Node2D = Game.heli
	if best.is_empty() and heli.landed and e.global_position.distance_to(heli.global_position) < SPIT_SIGHT:
		best = [heli.global_position, func(): if heli.landed: heli.take_damage(dmg)]
	return best


static func _spit(e: Node2D, delta: float) -> bool:
	var s: Dictionary = e.state
	s["look"] = s.get("look", 0.0) - delta
	if s["look"] <= 0.0:
		s["look"] = 0.5
		e.spit_target = _spit_target(e) # looked up again every half second
	var t: Array = e.spit_target
	if t.is_empty():
		return false
	var to: Vector2 = t[0] - e.global_position
	var d := to.length()
	e._face(to)
	if d < SPIT_MIN:
		e._step(-to, delta, 1.0)
	elif d > SPIT_MAX:
		e._walk(t[0], delta)
	elif e.attack_cd <= 0.0:
		e.attack_cd = SPIT_INTERVAL
		var puddle := Node2D.new()
		puddle.set_script(preload("res://scripts/puddle.gd"))
		puddle.setup("acid", t[0], ACID_RADIUS, ACID_SECONDS, SPIT_FLIGHT, e.global_position)
		puddle.impact = t[1]
		Game.world.add_child(puddle)
		Sfx.play("hit", e.global_position, -12.0)
	return true
