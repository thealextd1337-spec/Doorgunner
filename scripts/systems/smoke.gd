extends Node
## Smoke Launcher (Q8 system): when the heli is shot at (bandit bullets, RPGs) or a rocket closes in, a smoke screen pops
## on the heli. Rockets inside it lose their lock and burst harmlessly; zombies inside slow down; Lv5 stuns them.

const COOLDOWN_BASE := 27.0 # s, minus COOLDOWN_PER_LEVEL per level
const COOLDOWN_PER_LEVEL := 3.0
const DURATION_BASE := 5.0 # s, plus 1 per level
const RADIUS := 48.0
const ROCKET_TRIGGER := 200.0 # a rocket this close pops the screen
const SLOW := 0.5
const STUN_LV5 := 2.0

var cd := 0.0


func _ready() -> void:
	get_parent().damaged.connect(func(_a: float, source: String) -> void:
		if source in ["bandit", "rocket"]:
			pop())


func _process(delta: float) -> void:
	cd -= delta
	if cd > 0.0 or not Game.running:
		return
	for r in get_tree().get_nodes_in_group("rockets"):
		if is_instance_valid(r) and r.global_position.distance_squared_to(get_parent().global_position) < ROCKET_TRIGGER * ROCKET_TRIGGER:
			pop()
			return


## Launch the screen now unless it is still reloading. Returns the cloud (tests) or null.
func pop() -> Node2D:
	if cd > 0.0 or not Game.running:
		return null
	var lv := Progression.level("smoke")
	cd = COOLDOWN_BASE - COOLDOWN_PER_LEVEL * lv
	var c := Cloud.new()
	c.position = get_parent().global_position
	c.life = DURATION_BASE + lv
	c.stun = STUN_LV5 if lv >= 5 else 0.0
	Game.world.add_child(c)
	Sfx.play("smoke", c.position, -10.0)
	return c


class Cloud extends Node2D:
	var life := 6.0
	var stun := 0.0

	func _ready() -> void:
		z_index = 4

	func _process(delta: float) -> void:
		life -= delta
		queue_redraw()
		if life <= 0.0:
			queue_free()
			return
		for r in get_tree().get_nodes_in_group("rockets"):
			if is_instance_valid(r) and position.distance_squared_to(r.global_position) < RADIUS * RADIUS:
				r.life = 0.0 # no lock inside the smoke: bursts where it is
		for e in get_tree().get_nodes_in_group("enemies"):
			if "slowed" in e and position.distance_squared_to(e.global_position) < RADIUS * RADIUS:
				e.slowed = maxf(e.slowed, SLOW)
				if stun > 0.0:
					e.stun(stun)

	func _draw() -> void:
		var a := clampf(life / 2.0, 0.0, 1.0) * 0.55
		for i in 5:
			var o := Vector2(cos(i * 1.9 + life * 0.3), sin(i * 2.3 + life * 0.25)) * RADIUS * 0.45
			draw_circle(o, RADIUS * 0.6, Color(0.78, 0.78, 0.74, a))
