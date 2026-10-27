extends Node2D
## Points of interest. Landing within LAND_DIST triggers the reward; nests are enemies instead.

const LABELS := {"survivors": "settlement", "crate": "supply cache", "nest": "hive nest", "radio_tower": "relay tower", "wreck": "crash site", "upgrade": "weapons cache"}
const DIRS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const LAND_DIST := 48.0
const Weapons := preload("res://scripts/weapons.gd")

var kind := ""
var force_weapon := false # tests: weapons cache always yields a weapon
var discovered := false
var done := false
var label := ""
var rng: RandomNumberGenerator
var sprite: Sprite2D
var ring_shown := false
# survivors
var survivors := []
var loading := false
var load_cd := 0.0
var boarded := 0
# nest (group "enemies")
var radius := 16.0
var hp := 300.0
var queen_called := false
var spawn_cd := 8.0
var spawned := []
var raid_warned := 0.0


## "180 m north-east" as seen from `from` (10 px = 1 m).
static func where(from: Vector2, to: Vector2) -> String:
	var v := to - from
	return "%d m %s" % [v.length() / 10.0, DIRS[wrapi(roundi(v.angle() / (TAU / 8)), 0, 8)]]


func setup(k: String, pos: Vector2, r: RandomNumberGenerator) -> void:
	kind = k
	position = pos
	rng = r
	label = LABELS[kind]
	hp = 300.0 * Game.danger_at(pos)


func _ready() -> void:
	Game.heli.landed_changed.connect(_on_landed)
	if kind == "survivors":
		for i in rng.randi_range(2, 6):
			var s: Node2D = preload("res://scripts/survivor.gd").new()
			s.position = Vector2(rng.randf_range(-20, 20), rng.randf_range(-14, 14))
			s.arrived.connect(_board.bind(s))
			add_child(s)
			survivors.append(s)
		return
	sprite = Art.sprite("crate" if kind == "upgrade" else kind)
	add_child(sprite)
	match kind:
		"upgrade": sprite.modulate = Color(0.6, 0.8, 1.0)
		"radio_tower": sprite.offset = Vector2(0, -16) / Art.SCALE # offset is in texture px
		"nest": add_to_group("enemies")


func _process(delta: float) -> void:
	if done or not Game.running or Game.heli == null:
		return
	var d2 := position.distance_squared_to(Game.heli.position)
	if d2 > 800.0 * 800.0:
		return
	var show := d2 < 160.0 * 160.0 and kind != "nest"
	if show != ring_shown:
		ring_shown = show
		queue_redraw()
	if kind == "nest":
		_nest(delta, d2)
	elif loading:
		load_cd -= delta
		if load_cd <= 0.0:
			load_cd = 2.5
			_dispatch()


func _draw() -> void:
	if not ring_shown:
		return
	for i in 24:
		draw_arc(Vector2.ZERO, LAND_DIST, i * TAU / 24, i * TAU / 24 + TAU / 48, 3, Color(1, 1, 1, 0.35), 1.0)


func _on_landed(landed: bool) -> void:
	if not landed:
		_stop_loading()
		return
	if done or position.distance_to(Game.heli.position) > LAND_DIST:
		return
	if kind != "survivors":
		Sfx.play("pickup")
	match kind:
		"survivors":
			loading = true
			load_cd = 2.5
			boarded = 0
			Game.world.spawner.call_wave(position, 2)
		"crate":
			var a := rng.randi_range(30, 60)
			var f := rng.randi_range(20, 40)
			var s := rng.randi_range(5, 15)
			Game.ammo = mini(Game.max_ammo, Game.ammo + a)
			Game.fuel = minf(Game.max_fuel, Game.fuel + f)
			Game.base_food += 15.0 # rations go straight to the base larder
			Game.scrap += s
			Game.base_fuel = minf(Game.base_fuel_cap, Game.base_fuel + 50.0)
			Game.base_ammo = minf(Game.base_ammo_cap, Game.base_ammo + 100.0)
			Game.radio("Supply cache: +%d ammo, +%d fuel, +%d scrap. Base stock +50 fuel, +100 ammo." % [a, f, s])
			_finish(true)
		"upgrade":
			Game.scrap += 10
			_finish(true)
			var pool: Array = Weapons.unowned()
			if pool.is_empty() or (not force_weapon and rng.randf() < 0.4):
				Game.world.offer_upgrades("Weapons cache")
			else:
				Game.add_weapon(pool[rng.randi() % pool.size()])
		"radio_tower":
			var found: Array = Game.world.pois.filter(func(p): return p != self and not p.done and not p.discovered and position.distance_to(p.position) < 2500.0)
			found.sort_custom(func(a, b): return position.distance_squared_to(a.position) < position.distance_squared_to(b.position))
			for p in found.slice(0, 3):
				p.discovered = true
				Game.radio("Relay: %s located, %s." % [p.label, where(position, p.position)])
			if not found.is_empty():
				Game.world.radio_target = found[0]
			Game.scrap += 10
			_finish(false)
		"wreck":
			var s := rng.randi_range(20, 40)
			Game.scrap += s
			var line := ""
			var pool: Array = Weapons.unowned()
			var roll: int = 3 if not pool.is_empty() and rng.randf() < 0.3 else rng.randi_range(0, 2)
			match roll:
				0:
					Game.base_max_ammo += 40
					Game.recompute()
					Game.ammo += 40
					line = "salvaged an ammo feed"
				1:
					Game.base_max_fuel += 20.0
					Game.recompute()
					Game.fuel += 20.0
					line = "patched in a spare fuel tank"
				2:
					Game.max_hp += 15.0
					line = "stripped armour plates off the hull"
				3:
					var id: String = pool[rng.randi() % pool.size()]
					Game.add_weapon(id)
					line = "recovered a %s" % Weapons.TABLE[id]["name"]
			Game.radio("Crash site: %s, +%d scrap." % [line, s])
			_finish(false)


func _finish(hide: bool) -> void:
	done = true
	ring_shown = false
	queue_redraw()
	if hide:
		sprite.visible = false


func _stop_loading() -> void:
	loading = false
	for s in survivors:
		s.target = null


func _full() -> void:
	Game.radio("Pilot: heli full, we leave the rest behind.")
	_stop_loading()


func _dispatch() -> void:
	if Game.passengers >= Game.seats:
		_full()
		return
	for s in survivors:
		if s.target == null:
			s.target = Game.heli
			return


func _board(s: Node2D) -> void:
	if Game.passengers >= Game.seats:
		_full()
		return
	Game.passengers += 1
	Game.add_xp(4)
	Sfx.play("board")
	survivors.erase(s)
	s.queue_free()
	boarded += 1
	if boarded == 3:
		Game.radio("Pilot: LZ is hot, more incoming!")
		Game.world.spawner.call_wave(position, 2)
	if survivors.is_empty():
		Game.radio("Pilot: all survivors aboard.")
		_finish(false)


## Ground aliens raiding the settlement kill one survivor at a time.
func lose_survivor(silent := false) -> void:
	if kind != "survivors" or done or survivors.is_empty():
		return
	var s: Node2D = survivors.pop_back()
	if s.target != null:
		s.target = null
	s.queue_free()
	if not silent:
		Game.world.spawn_fx(global_position + s.position, 0.5)
		Sfx.play("survivor_lost", global_position, -6.0)
	var now := Time.get_ticks_msec() / 1000.0
	if not silent and now - raid_warned > 20.0:
		raid_warned = now
		Game.radio("Radio: %s under attack, %d left, %s!" % [label, survivors.size(), where(Game.heli.position, position)])
	if survivors.is_empty():
		Game.radio("Radio: we lost the %s. No survivors." % label)
		_finish(false)


func _nest(delta: float, d2: float) -> void:
	if not queen_called and d2 < 420.0 * 420.0:
		queen_called = true
		Game.world.spawn_enemy("boss", position + Vector2(40, 0))
		Game.radio("Gunner: hive queen sighted!")
		Sfx.play("boss_roar", position)
	if d2 > 700.0 * 700.0:
		return
	spawn_cd -= delta
	if spawn_cd > 0.0:
		return
	spawn_cd = 8.0
	spawned = spawned.filter(func(e): return is_instance_valid(e))
	if spawned.size() < 6:
		spawned.append(Game.world.spawn_enemy("walker", position + Vector2(24, 0).rotated(randf() * TAU)))


func hit(amount: float) -> void:
	hp -= amount
	sprite.modulate = Color(1, 0.5, 0.5)
	get_tree().create_timer(0.08).timeout.connect(func(): if is_instance_valid(self): sprite.modulate = Color.WHITE)
	if hp <= 0.0 and not done:
		Game.add_xp(80)
		Game.scrap += 30
		Game.world.spawn_fx(position, 2.0)
		Game.radio("Gunner: hive nest destroyed!")
		Sfx.play("explosion", position)
		remove_from_group("enemies")
		_finish(true)
