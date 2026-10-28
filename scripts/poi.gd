extends Node2D
## Points of interest. Landing within LAND_DIST triggers the reward; nests are enemies instead.

const LABELS := {"survivors": "settlement", "hideout": "hideout", "crate": "supply cache", "nest": "zombie den", "radio_tower": "relay tower", "wreck": "crash site", "upgrade": "weapons cache", "water_tower": "water tower", "pharmacy": "pharmacy", "scrapyard": "scrap yard"}
const DIRS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const LAND_DIST := 48.0
const Weapons := preload("res://scripts/weapons.gd")

var kind := ""
var count := 0 # > 0: fixed number of survivors (tutorial)
var force_weapon := false # tests: weapons cache always yields a weapon
var drop_level := 0 # crate from the Supply Drop system (item level): reduced contents
var discovered := false
var done := false
var label := ""
var rng: RandomNumberGenerator
var sprite: Sprite2D
var ring_shown := false
# survivors
var survivors := []
var loading := false
var walking_home := false # next to the base: the survivors walk in on their own (base._call_settlers)
var load_cd := 0.0
var boarded := 0
# nest (group "enemies")
var radius := 16.0
var hp := 300.0
var boss_called := false
var spawn_cd := 8.0
var spawned := []
var raid_warned := 0.0
var last_raid_ms := -100000


## "180 m north-east" as seen from `from` (10 px = 1 m).
static func where(from: Vector2, to: Vector2) -> String:
	var v := to - from
	return "%d m %s" % [v.length() / 10.0, DIRS[wrapi(roundi(v.angle() / (TAU / 8)), 0, 8)]]


func setup(k: String, pos: Vector2, r: RandomNumberGenerator, n := 0) -> void:
	kind = k
	count = n
	position = pos
	rng = r
	label = LABELS[kind]
	hp = 300.0 * Game.danger_at(pos)


func _ready() -> void:
	Game.heli.landed_changed.connect(_on_landed)
	if kind == "survivors" or kind == "hideout":
		# hideout: 1-3 people hiding in a lone house; they stay out of sight (and off the zombies' list) until you land
		for i in count if count > 0 else rng.randi_range(1, 3) if kind == "hideout" else rng.randi_range(2, 6):
			var s: Node2D = preload("res://scripts/survivor.gd").new()
			s.position = Vector2(rng.randf_range(-20, 20), rng.randf_range(-14, 14))
			s.arrived.connect(_board.bind(s))
			s.visible = kind != "hideout"
			add_child(s)
			survivors.append(s)
		return
	sprite = Art.sprite({"upgrade": "crate", "nest": "den", "pharmacy": "crate", "scrapyard": "wreck"}.get(kind, kind))
	add_child(sprite)
	match kind:
		"upgrade": sprite.modulate = Color(0.6, 0.8, 1.0)
		"scrapyard": sprite.modulate = Color(0.55, 0.55, 0.55)
		"pharmacy":
			sprite.modulate = Color(0.5, 1.0, 0.55)
			sprite.show_behind_parent = true # the cross in _draw goes on top
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
		load_cd -= delta * Game.stats["board"]
		if load_cd <= 0.0:
			load_cd = 2.5
			_dispatch()


func _draw() -> void:
	if kind == "pharmacy" and not done:
		draw_rect(Rect2(-5, -1.5, 10, 3), Color.WHITE)
		draw_rect(Rect2(-1.5, -5, 3, 10), Color.WHITE)
	if not ring_shown:
		return
	for i in 24:
		draw_arc(Vector2.ZERO, LAND_DIST, i * TAU / 24, i * TAU / 24 + TAU / 48, 3, Color(1, 1, 1, 0.35), 1.0)


func _on_landed(landed: bool) -> void:
	if not landed:
		_stop_loading()
		return
	if done or walking_home or position.distance_to(Game.heli.position) > LAND_DIST:
		return
	if kind != "survivors" and kind != "hideout":
		Sfx.play("pickup")
	match kind:
		"survivors":
			loading = true
			load_cd = 2.5
			boarded = 0
			Game.world.spawner.call_wave(position, 2)
		"hideout":
			loading = true
			load_cd = 2.5
			boarded = 0
			for s in survivors:
				s.visible = true
			Game.radio("Gunner: people coming out of the house!")
			if Game.world.chunks.region(Vector2i((position / 16.0).floor())) == preload("res://scripts/chunk_manager.gd").R.LAKE:
				Game.base_water += 20.0
				Game.radio("Gunner: lake hut, they filled jerrycans. Base water +20.")
		"water_tower":
			Game.base_water += 40.0
			Game.radio("Water tower: tanks filled, base water +40.")
			_finish(false)
		"scrapyard":
			_salvage(20.0, 6.0, 2.0)
			Game.radio("Scrap yard: stripped clean, salvage +20 metal, +6 parts, +2 electronics.")
			_finish(false)
		"pharmacy":
			Game.base_medicine += 4.0
			Game.radio("Pharmacy: shelves cleared, base medicine +4.")
			_finish(true)
		"crate":
			var k := 1.0 if drop_level == 0 else 0.3 + 0.1 * drop_level
			var a := int(rng.randi_range(30, 60) * k)
			var f := int(rng.randi_range(20, 40) * k)
			var s := rng.randi_range(5, 15) if drop_level == 0 or drop_level >= 5 else 0
			Game.ammo = mini(Game.max_ammo, Game.ammo + a)
			Game.fuel = minf(Game.max_fuel, Game.fuel + f)
			Game.scrap += s
			if drop_level > 0:
				Game.radio("Supply drop: +%d ammo, +%d fuel, +%d scrap." % [a, f, s])
			else:
				Game.base_food += 15.0 # rations go straight to the base larder
				Game.base_fuel = minf(Game.base_fuel_cap, Game.base_fuel + 50.0)
				Game.base_ammo = minf(Game.base_ammo_cap, Game.base_ammo + 100.0)
				Game.base_water += 10.0
				Game.base_medicine += 1.0
				_salvage(6.0, 0.0, 0.0)
				Game.radio("Supply cache: +%d ammo, +%d fuel, +%d scrap. Base stock +50 fuel, +100 ammo, +15 food, +10 water, +1 medicine, +6 metal." % [a, f, s])
			_finish(true)
		"upgrade":
			Game.scrap += 10
			Game.base_rifles += 2.0
			Game.radio("Weapons cache: 2 rifles for the militia.")
			_finish(true)
			var pool: Array = Weapons.unowned()
			if pool.is_empty() or (not force_weapon and rng.randf() < 0.4):
				Game.world.offer_upgrades("Weapons cache", 1)
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
			Game.base_medicine += 2.0
			Game.base_rifles += 1.0
			_salvage(10.0, 4.0, 1.0)
			Game.radio("Crash site: %s, +%d scrap, 2 medkits, a rifle, salvage +10 metal, +4 parts, +1 electronics." % [line, s])
			_finish(false)


func _salvage(metal: float, parts: float, electronics: float) -> void:
	Game.salvage["metal"] += metal
	Game.salvage["parts"] += parts
	Game.salvage["electronics"] += electronics


func _finish(hide: bool) -> void:
	done = true
	ring_shown = false
	queue_redraw()
	if hide:
		sprite.visible = false


## The base was built close by: everyone walks to the pad and moves in, no heli needed.
func walk_to_base() -> void:
	walking_home = true
	loading = false
	for s in survivors:
		s.visible = true
		s.target = Game.world.base
	Game.radio("Radio: the %s next to the base is joining you, %d walking over." % [label, survivors.size()])


## One survivor reached the base pad: rescued, a new pawn walks off to change.
func _join_base(s: Node2D) -> void:
	Game.rescued += 1
	if s.injured:
		Game.injured += 1
	Game.add_xp(6)
	var base: Node2D = Game.world.base
	if base.pawns.get_child_count() < base.PAWN_MAX:
		base.add_pawn(s.global_position, true)
	survivors.erase(s)
	s.queue_free()
	if survivors.is_empty():
		Game.radio("Base: the %s has moved in." % label)
		_finish(false)


func _stop_loading() -> void:
	if walking_home:
		return
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
			if s.injured:
				load_cd *= 2.0 # helping the wounded aboard takes twice as long
			return


func _board(s: Node2D) -> void:
	if walking_home:
		_join_base(s)
		return
	if Game.passengers >= Game.seats:
		_full()
		return
	Game.passengers += 1
	if s.injured:
		Game.passengers_injured += 1
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


## Winch system: hoist one survivor straight aboard without landing. False if none left or the cabin is full.
func winch_one() -> bool:
	if done or walking_home or survivors.is_empty() or Game.passengers >= Game.seats:
		return false
	_board(survivors[0])
	return true


## Zombies raiding the settlement hit one survivor at a time: half the time a healthy one is only wounded.
func lose_survivor(silent := false) -> void:
	if kind != "survivors" or done or survivors.is_empty():
		return
	# a whole horde strikes at once; cap losses to one survivor per 8 s per settlement
	var now_ms := Time.get_ticks_msec()
	if not silent and now_ms - last_raid_ms < 8000:
		return
	last_raid_ms = now_ms
	var healthy: Array = survivors.filter(func(x): return not x.injured)
	if not healthy.is_empty() and randf() < 0.5:
		healthy.back().injured = true
		return
	_kill(survivors.back(), silent)


## A zombie strikes one survivor directly (no per-settlement cap): a healthy one is wounded, a wounded one dies.
func lose_survivor_node(s: Node2D) -> void:
	if done or not s in survivors:
		return
	if not s.injured:
		s.injured = true
	else:
		_kill(s, false)


func _kill(s: Node2D, silent: bool) -> void:
	survivors.erase(s)
	s.queue_free()
	if not silent:
		Game.world.spawn_fx(s.global_position, 0.5)
		Sfx.play("survivor_lost", global_position, -6.0)
	var now := Time.get_ticks_msec() / 1000.0
	if not silent and now - raid_warned > 20.0:
		raid_warned = now
		Game.radio("Radio: %s under attack, %d left, %s!" % [label, survivors.size(), where(Game.heli.position, position)])
	if survivors.is_empty():
		Game.radio("Radio: we lost the %s. No survivors." % label)
		_finish(false)


func _nest(delta: float, d2: float) -> void:
	if not boss_called and d2 < 420.0 * 420.0:
		boss_called = true
		Game.world.spawn_enemy("boss", position + Vector2(40, 0))
		Game.radio("Gunner: abomination crawling out of the den!")
		Sfx.play("boss_roar", position)
	if d2 > 700.0 * 700.0:
		return
	spawn_cd -= delta
	if spawn_cd > 0.0:
		return
	spawn_cd = 8.0
	spawned = spawned.filter(func(e): return is_instance_valid(e))
	if spawned.size() < 12:
		spawned.append(Game.world.spawn_enemy("shambler", position + Vector2(24, 0).rotated(randf() * TAU)))


func hit(amount: float) -> void:
	hp -= amount
	sprite.modulate = Color(1, 0.5, 0.5)
	get_tree().create_timer(0.08).timeout.connect(func(): if is_instance_valid(self): sprite.modulate = Color.WHITE)
	if hp <= 0.0 and not done:
		Game.add_xp(80)
		Game.scrap += 30
		Game.world.spawn_fx(position, 2.0)
		Game.radio("Gunner: den cleared, burn it!")
		Sfx.play("explosion", position)
		remove_from_group("enemies")
		_finish(true)
