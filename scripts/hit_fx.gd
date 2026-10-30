class_name HitFx
## Hit feedback: blood and spark bursts, corpses that stay for a while, camera shake for heavy guns.

const MAX_PARTICLES := 60 # bursts alive at once; more are skipped
const MAX_CORPSES := 120 # the oldest go first
const CORPSE_SECONDS := 60.0
const CORPSE_FADE := 5.0
const FLASH := 0.06 # seconds of white flash on a hit
const BLOOD := Color(0.55, 0.2, 0.18)
const SPARK := Color(1.0, 0.92, 0.6)
const SHAKE_MIN_DAMAGE := 40.0 # per shot, so autocannon, rockets and railgun
const SHAKE_PER_DAMAGE := 0.04 # px of shake per point of damage, at most SHAKE_MAX
const SHAKE_MAX := 4.0

static var corpses: Array[Node2D] = []


## One enemy took a hit along `dir`: white flash, a few droplets (sparks off armor), a sound that suits the target.
static func hit(e: Node2D, dir: Vector2, head: bool, armored: bool) -> void:
	var sprite: Sprite2D = e.sprite
	sprite.modulate = Color(2.5, 2.5, 2.5, sprite.modulate.a)
	e.get_tree().create_timer(FLASH).timeout.connect(e.unflash) # a method, so a freed enemy drops the call
	if armored:
		burst(e.global_position, -dir, SPARK, 4, 90.0)
		Sfx.play("base_hit", e.global_position, -10.0, 0.2)
		return
	burst(e.global_position, dir, SPARK if head else e.cfg.get("blood", BLOOD), 8 if head else 3, 80.0 if head else 50.0)
	Sfx.play("hit", e.global_position, -8.0 if head else -14.0)


## A bigger burst and a corpse where `e` died.
static func death(e: Node2D) -> void:
	burst(e.global_position, Vector2.ZERO, e.cfg.get("blood", BLOOD), 10, 60.0)
	if e.concealed:
		return
	var c := Art.sprite(e.kind)
	c.position = e.global_position
	c.rotation = e.rotation + randf_range(-0.5, 0.5)
	c.modulate = Color(0.5, 0.38, 0.38, 0.9)
	c.z_index = 0
	Game.world.add_child(c)
	corpses.assign(corpses.filter(func(o) -> bool: return is_instance_valid(o))) # untyped: a freed corpse is no Node2D any more
	corpses.append(c)
	while corpses.size() > MAX_CORPSES:
		corpses.pop_front().queue_free()
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, CORPSE_FADE).set_delay(CORPSE_SECONDS - CORPSE_FADE)
	tw.tween_callback(c.queue_free)


## `n` one-shot droplets from `pos` thrown along `dir` (all round if zero).
static func burst(pos: Vector2, dir: Vector2, color: Color, n: int, speed: float) -> void:
	if Game.world.get_tree().get_nodes_in_group("hit_particles").size() >= MAX_PARTICLES:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 4
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = 0.45
	p.direction = dir
	p.spread = 180.0 if dir == Vector2.ZERO else 40.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = 80.0
	p.damping_max = 120.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	p.color = color
	p.add_to_group("hit_particles")
	p.finished.connect(p.queue_free)
	Game.world.add_child(p)


## Camera shake of `amount` px (decays by itself). Off when Game.meta["shake"] is 0.
static func shake(amount: float) -> void:
	for s in Game.world.get_tree().get_nodes_in_group("shaker"):
		s.kick(minf(amount, SHAKE_MAX))
