extends Node
## Headless test of the Q15 rivals (scripts/nemesis.gd): memory and adaptation, a named Warlord in his camp who flees and comes back
## stronger, escalation (ransom card, raids, the big attack on a free night), the gunship (distance, guns and rockets, flares),
## save/load, death for good, the Alpha, the daily rule, old saves.
## main.gd adds this node when env SMOKE=nemesis:   SMOKE=nemesis godot --headless --path . --quit-after 30000
## Systems are stepped by hand (process disabled, node._process(dt) / sys.tick()) so days and fights take no real time.

const Flare := preload("res://scripts/systems/flares.gd").Flare
const Weapons := preload("res://scripts/weapons.gd")

var main: Node2D
var sys: Node
var heli: Node2D
var ui: Node
var frame: Signal
var radio := []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	main = Game.world
	sys = main.nemesis
	heli = Game.heli
	ui = main.choice_ui
	frame = get_tree().process_frame
	await frame
	await frame
	for n in [main.spawner, main.bandits, main.bosses, sys, heli, main.events, main.assault]:
		n.set_process(false)
	heli.landed = false
	heli.vel = Vector2.ZERO
	Game.level = Game.LEVEL_CAP # kills would offer upgrade cards and pause the game
	Game.time = 0.3
	Game.hp = Game.max_hp
	Game.radio_message.connect(func(m: String): radio.append(m))
	print("nemesis test seed ", Game.seed)
	sys.next_day["alpha"] = 1000 # the Alpha has her own part below
	_free_all()
	_memory()
	await _warlord()
	await _gunship()
	await _alpha()
	_daily()
	_old_saves()
	print("NEMESIS OK")
	get_tree().quit(0)


func _free_all() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()
	for r in get_tree().get_nodes_in_group("rockets"):
		r.free()


func _step(n: Node, seconds: float, dt := 0.05) -> void:
	for i in int(seconds / dt):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n._process(dt)


func _said(part: String) -> bool:
	return radio.any(func(m: String) -> bool: return part in m)


func _spot(center: Vector2, dist: float) -> Vector2:
	for k in [1.0, 0.8, 1.25, 1.6]:
		for i in 48:
			var p := center + Vector2(dist * k, 0).rotated(i * TAU / 48.0)
			if main.is_walkable(p):
				return p
	assert(false, "no open spot near %s" % center)
	return center


func _warlord_node(uid: String) -> Node2D:
	for u in get_tree().get_nodes_in_group("bandits"):
		u.process_mode = Node.PROCESS_MODE_DISABLED
		if u.kind == "warlord" and u.camp_uid == uid and not u.is_queued_for_deletion():
			return u
	return null


# ---------------------------------------------------------------- memory -> adaptation

func _memory() -> void:
	assert(not sys.fast_flyer() and not sys.wire_heavy() and sys.favourite() == "mg", "a fresh run remembers nothing")
	var mg_band: Vector2 = sys.keep_band()
	heli.fire_cd = -10.0
	heli.vel = Vector2(heli.MAX_SPEED, 0)
	for i in int(Nemesis.FAST_MIN_AIR / Nemesis.TICK) + 4:
		sys._remember()
	assert(sys.fast_flyer(), "flying flat out: a fast flyer (%s)" % [sys.memory])
	heli.vel = Vector2.ZERO
	Game.weapon = "railgun"
	heli.fire_cd = 0.0
	for i in 10:
		sys._remember()
	heli.fire_cd = -10.0
	Game.weapon = "mg"
	assert(sys.favourite() == "railgun", "favourite gun: %s" % sys.favourite())
	var band: Vector2 = sys.keep_band()
	assert(band.y > mg_band.y and band.y == Nemesis.GS_KEEP.y, "the gunship keeps further off a railgun: %s vs %s" % [band, mg_band])
	assert(sys.rocket_cd() < Nemesis.GS_ROCKET_CD, "more rockets against a fast flyer")
	var cells := []
	for i in Nemesis.WIRE_HEAVY + 1:
		var cell := Vector2i(900 + i, 900)
		Game.sandbags[cell] = {"kind": "wire", "hp": 10.0, "built": true, "rot": 0}
		cells.append(cell)
	sys._on_day(Game.day)
	for cell in cells:
		Game.sandbags.erase(cell)
	assert(sys.wire_heavy(), "lots of wire remembered: %d" % sys.memory["wire"])
	print("NEMESIS memory OK")


# ---------------------------------------------------------------- the Warlord in his camp

func _warlord() -> void:
	var bandits: Node = main.bandits
	var codex: String = Game.meta["codex"]
	Game.day = 9
	var c: Dictionary = bandits.add_camp("nm#camp", "motel", _spot(heli.position, 600.0))
	c["garrison"] = {"rifle": 1}
	c["known"] = true
	sys.tick()
	assert(not sys.rivals.has("warlord"), "no rival before day %d" % Nemesis.FIRST_DAY["warlord"])
	Game.day = 10
	radio.clear()
	sys.tick()
	assert(sys.rivals.has("warlord"), "a known camp gets the rival warlord")
	var r: Dictionary = sys.rivals["warlord"]
	assert(r["name"] == Nemesis.NAMES["warlord"][hash([Game.seed, "warlord", 0]) % Nemesis.NAMES["warlord"].size()], "name from the seed: %s" % r["name"])
	assert(Nemesis.TRAITS[r["trait"]]["kind"] == "warlord" and r["stage"] == 1, "trait %s, stage %d" % [r["trait"], r["stage"]])
	assert(c["warlord"] and c["garrison"]["warlord"] == 1 and main.bosses.records["warlord:nm#camp"]["nemesis_id"] == "warlord", "he holds the camp")
	assert(_said(r["name"]) and _said("Intercepted"), "intro on bandit radio: %s" % [radio])
	# his body: the Q12 warlord, made stronger once, with rocket men against a fast flyer
	bandits._wake(c)
	var w := _warlord_node("nm#camp")
	assert(w != null, "the warlord is at his camp")
	w._process(0.05) # bosses.gd sets him up (hp from the record, bodyguards)
	var base_hp: float = w.max_hp
	heli.global_position = w.global_position + Vector2(300, 0)
	radio.clear()
	sys.tick()
	sys.tick()
	assert(w.state["nemesis_id"] == "warlord" and w.state["nem"], "named boss: %s" % [w.state])
	assert(is_equal_approx(w.max_hp, base_hp * sys.trait_val(r, "hp", 1.0)), "trait hp once: %.0f vs %.0f" % [w.max_hp, base_hp])
	var rpgs := get_tree().get_nodes_in_group("bandits").filter(func(u): return u.camp_uid == "escort" and u.kind == "rpg").size()
	assert(rpgs == Nemesis.RPG_EXTRA, "rocket men against a fast flyer: %d" % rpgs)
	assert(r["met"] and Codex.is_unlocked("b_rival") and _said("Gunner"), "contact: codex and radio")
	# the heli breaks off the fight: remembered, and he comes back sooner
	heli.global_position = w.global_position + Vector2(Nemesis.DISENGAGE + 100.0, 0)
	sys.tick()
	assert(sys.memory["flees"] == 1 and sys.return_days() == Nemesis.RETURN_DAYS - 1, "flight remembered: %s" % [sys.memory])
	# hurt: he escapes, the camp stays
	heli.global_position = w.global_position + Vector2(300, 0)
	w.hp = w.max_hp * 0.2
	radio.clear()
	sys.tick()
	assert(w.is_queued_for_deletion() and r["escapes"] == 1 and r["away"] == Game.day + sys.return_days(), "escaped: %s" % [r])
	assert(c["garrison"]["warlord"] == 0 and not c["cleared"] and _said("I will be back"), "his camp stays without him")
	await frame
	# he returns stronger; the contact days are over: stage 2 and the ransom card (Q13)
	Game.day = r["away"]
	sys._on_day(Game.day)
	assert(r["away"] == -1 and c["garrison"]["warlord"] == 1 and _said("Miss me"), "back in his camp")
	assert(r["stage"] == 2 and ui.visible and ui.ev["id"] == "nem_ransom", "stage 2 brings the ransom card")
	var scrap0: int = Game.scrap
	Game.scrap = 0
	assert(not ui.ev["view"]["opts"][0]["ok"], "paying needs %d scrap" % Nemesis.RANSOM_SCRAP)
	ui.pick(1)
	assert(r["next_raid"] == Game.day + 1 and _said("Then I come early"), "refused: he raids tomorrow")
	Game.scrap = scrap0
	bandits._sleep(c)
	await frame
	bandits._wake(c)
	w = _warlord_node("nm#camp")
	w._process(0.05)
	base_hp = w.max_hp # danger grows with the days
	sys.tick()
	assert(is_equal_approx(w.max_hp, base_hp * sys.trait_val(r, "hp", 1.0) * (1.0 + Nemesis.STRONGER)), "stronger after an escape: %.0f" % w.max_hp)
	bandits._sleep(c)
	await frame
	# raids: an outpost (no convoy out), then the big attack, planned on a night no assault has taken
	var hits := []
	main.outposts.raided.connect(func(id: String, _res: Dictionary, source: String): hits.append([id, source]))
	main.outposts.list.append({"id": "o90", "site": "nm", "pos": heli.position + Vector2(1500, 0), "fuel": 0.0, "ammo": 0, "hp": 100.0, "day": Game.day})
	Game.day += 1
	sys._on_day(Game.day)
	assert(hits.size() == 1 and hits[0] == ["o90", "bandits"] and r["raids"] == 1 and r["stage"] == 2, "raid on the outpost: %s %s" % [hits, r])
	main.outposts.list = main.outposts.list.filter(func(o): return o["id"] != "o90")
	Game.first_assault_day = Game.day + Nemesis.RAID_GAP # the day of the second raid is an assault night
	Game.day += Nemesis.RAID_GAP
	assert(Assault.night_taken(Game.day), "test setup: tonight is taken")
	sys._on_day(Game.day)
	assert(r["raids"] == 2 and r["stage"] == 3, "stage 3 after %d raids: %s" % [Nemesis.RAIDS_TO_ATTACK, r])
	assert(c["garrison"]["warlord"] == 0 and _said("helicopter of my own"), "he left his camp for the air")
	assert(r["attack_day"] == Game.day + 1 and not Assault.night_taken(r["attack_day"]), "the attack waits for a free night: %d" % r["attack_day"])
	Game.meta["codex"] = codex
	Game.first_assault_day = 1000 # no real assault starts while the clock runs on
	print("NEMESIS warlord OK")


# ---------------------------------------------------------------- the gunship

func _gunship() -> void:
	var r: Dictionary = sys.rivals["warlord"]
	Game.day = r["attack_day"]
	Game.time = Nemesis.ATTACK_AT - 0.05
	sys.tick()
	assert(sys.gunship == null, "not before %.2f" % Nemesis.ATTACK_AT)
	Game.time = Nemesis.ATTACK_AT + 0.01
	var bandits0: int = get_tree().get_nodes_in_group("bandits").size()
	sys.tick()
	var g: Node2D = sys.gunship
	assert(is_instance_valid(g) and sys.body_of(r) == g, "the big attack: his gunship")
	var raiders := get_tree().get_nodes_in_group("bandits").filter(func(u): return u.role == "base")
	assert(raiders.size() > 0 and raiders.filter(func(u): return u.kind == "rpg").size() >= Nemesis.RPG_EXTRA, "and a bandit raid with rocket men: %d" % raiders.size())
	assert(r["attack_day"] == -1 and r["next_raid"] == Game.day + Nemesis.ATTACK_GAP, "next attack in %d days" % Nemesis.ATTACK_GAP)
	for u in get_tree().get_nodes_in_group("bandits"):
		u.free()
	assert(get_tree().get_nodes_in_group("bandits").size() == 0 and bandits0 >= 0)
	g.process_mode = Node.PROCESS_MODE_DISABLED
	# it closes in and holds its band
	Game.hp = Game.max_hp
	g.position = heli.global_position + Vector2(800, 0)
	g.rocket_cd = 100.0
	_step(g, 15.0)
	var band: Vector2 = sys.keep_band()
	var d: float = g.position.distance_to(heli.global_position)
	assert(d > band.x - 100.0 and d < band.y + 100.0, "holds the band %s: %.0f" % [band, d])
	assert(g.position.distance_to(heli.global_position + Vector2(800, 0)) > 200.0, "it moved")
	# heli physics: never faster than GS_SPEED
	assert(g.vel.length() <= Nemesis.GS_SPEED + 0.01, "speed %.1f" % g.vel.length())
	# guns and rockets
	g.gun_cd = 0.0
	_step(g, 20.0)
	assert(Game.hp < Game.max_hp, "its guns hit the heli")
	var rockets0 := get_tree().get_nodes_in_group("rockets").size()
	g.rocket_cd = 0.0
	_step(g, Nemesis.GS_AIM + 0.2)
	assert(get_tree().get_nodes_in_group("rockets").size() == rockets0 + 1, "a rocket after the aim line")
	_free_all_rockets()
	# a flare near the heli: rockets held; a flare near the gunship: it veers away
	var f: Node2D = Flare.new()
	f.add_to_group("rocket_decoys")
	f.position = heli.global_position + Vector2(0, 40)
	f.process_mode = Node.PROCESS_MODE_DISABLED
	main.add_child(f)
	g.rocket_cd = 0.0
	_step(g, 1.0)
	assert(g.held >= 1 and get_tree().get_nodes_in_group("rockets").is_empty(), "rockets held while flares burn")
	f.position = g.position + g.vel.normalized() * 50.0 if g.vel != Vector2.ZERO else g.position + Vector2(50, 0)
	var gap0: float = g.position.distance_to(f.position)
	_step(g, 1.5)
	assert(g.dodges == 1 and g.position.distance_to(f.position) > gap0, "veers away from the flare: %.0f -> %.0f" % [gap0, g.position.distance_to(f.position)])
	f.free()
	# save / load mid-fight
	var data: Dictionary = bytes_to_var(var_to_bytes(sys.save_state()))
	var hp: float = g.hp
	var pos: Vector2 = g.position
	g.free()
	var name0: String = r["name"]
	sys.rivals = {}
	sys.memory["flees"] = 0
	sys.load_state(data)
	g = sys.gunship
	r = sys.rivals["warlord"]
	assert(is_instance_valid(g) and g.hp == hp and g.position == pos and r["name"] == name0 and sys.memory["flees"] == 1, "gunship and memory loaded")
	g.process_mode = Node.PROCESS_MODE_DISABLED
	# hurt: it flies off, he is away
	g.hp = g.max_hp * 0.2
	sys.tick()
	assert(g.fleeing and r["escapes"] == 2 and r["away"] > Game.day, "the gunship flees: %s" % [r])
	_step(g, 40.0)
	assert(g.is_queued_for_deletion(), "gone at %.0f px" % Nemesis.GS_LEAVE)
	await frame
	# back with no escapes left: shot down for good
	Game.day = r["away"]
	sys._on_day(Game.day)
	assert(r["away"] == -1 and r["stage"] == 3, "back")
	g = sys.big_attack(r)
	for u in get_tree().get_nodes_in_group("bandits"):
		u.free()
	g.process_mode = Node.PROCESS_MODE_DISABLED
	assert(is_equal_approx(g.max_hp, Nemesis.GS_HP * (1.0 + 2 * Nemesis.STRONGER) * sys.trait_val(r, "hp", 1.0)), "stronger gunship: %.0f" % g.max_hp)
	g.hp = g.max_hp * 0.1
	sys.tick()
	assert(not g.fleeing, "no escape left")
	var scrap: int = Game.scrap
	var ended := []
	sys.ended.connect(func(k: String, n: String): ended.append([k, n]))
	g.hit(1.0e6)
	assert(not sys.rivals.has("warlord") and ended == [["warlord", name0]], "dead for good")
	assert(Game.scrap >= scrap + Nemesis.REWARD["scrap"] and Codex.is_unlocked("b_rival"), "big reward")
	assert(sys.next_day["warlord"] == Game.day + Nemesis.NEW_RIVAL_DAYS, "no new rival for a while")
	await frame
	# a new warlord only later, with the next name roll
	var c: Dictionary = main.bandits.camps["nm#camp"]
	c["garrison"]["rifle"] = 1
	sys.tick()
	assert(not sys.rivals.has("warlord"), "not yet")
	Game.day = sys.next_day["warlord"]
	sys.tick()
	assert(sys.rivals.has("warlord") and sys.rivals["warlord"]["gen"] == 1, "the next rival later in the run")
	sys.rivals.erase("warlord")
	main.bandits.camps.erase("nm#camp")
	print("NEMESIS gunship OK")


func _free_all_rockets() -> void:
	for x in get_tree().get_nodes_in_group("rockets"):
		x.free()


# ---------------------------------------------------------------- the Alpha

func _alpha() -> void:
	_free_all()
	main.bandits.camps.clear()
	heli.landed = false
	Game.day = 20
	sys.next_day["alpha"] = 0
	radio.clear()
	sys.tick()
	assert(sys.rivals.has("alpha"), "the alpha is named")
	var r: Dictionary = sys.rivals["alpha"]
	var e: Node2D = sys.body_of(r)
	assert(e != null and e.kind == "matriarch" and e.state["nemesis_id"] == "alpha", "she hunts the heli: a named matriarch")
	assert(_said(r["name"]), "intro")
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e._process(0.05)
	var base_hp: float = e.max_hp
	sys.tick()
	assert(e.state["nem"] and is_equal_approx(e.max_hp, base_hp * sys.trait_val(r, "hp", 1.0)), "made stronger once")
	e.hp = e.max_hp * 0.2
	sys.tick()
	assert(e.is_queued_for_deletion() and r["escapes"] == 1, "she escapes")
	await frame
	Game.day = r["away"]
	sys._on_day(Game.day)
	assert(r["spawn"] and r["stage"] == 2, "back, hunting; raids now")
	sys.tick()
	e = sys.body_of(r)
	assert(e != null, "she is back")
	e.process_mode = Node.PROCESS_MODE_DISABLED
	e._process(0.05)
	base_hp = e.max_hp # her danger roll differs at the new spot
	sys.tick()
	assert(is_equal_approx(e.max_hp, base_hp * sys.trait_val(r, "hp", 1.0) * (1.0 + Nemesis.STRONGER)), "stronger: %.0f" % e.max_hp)
	e.free()
	assert(sys.raid(r) == "hunt" and r["spawn"], "no convoy or outpost: she comes for the heli")
	# wire: her push is crawlers and spitters
	sys.memory["wire"] = 0
	assert(sys.horde(r).has("runner"), "normal push")
	sys.memory["wire"] = Nemesis.WIRE_HEAVY
	assert(sys.horde(r).all(func(k): return k in Nemesis.WIRE_MIX), "against wire: %s" % [sys.horde(r)])
	# stage 3: she leads the next assault
	r["spawn"] = false
	sys._stage3(r)
	main.assault.clear_wave()
	sys._on_assault(Game.day)
	e = sys.body_of(r)
	assert(e != null and e.target_base and main.assault.queue.size() == sys.horde(r).size(), "she and her push join the assault")
	e.process_mode = Node.PROCESS_MODE_DISABLED
	main.assault.clear_wave()
	var ended := []
	sys.ended.connect(func(k: String, n: String): ended.append(k))
	e.hit(1.0e7)
	assert(not sys.rivals.has("alpha") and "alpha" in ended and Codex.is_unlocked("z_alpha"), "her death ends the rival")
	await frame
	_free_all()
	print("NEMESIS alpha OK")


func _daily() -> void:
	var mode: String = Game.mode
	Game.mode = "daily"
	var r: Dictionary = sys._name("warlord")
	sys._stage2(r)
	assert(not ui.visible, "no ransom card in a daily")
	Game.mode = mode
	sys.rivals.clear()
	print("NEMESIS daily OK")


func _old_saves() -> void:
	sys.load_state({}) # a run saved before Q15
	assert(sys.rivals.is_empty() and not is_instance_valid(sys.gunship), "old save loads without rivals")
	print("NEMESIS old saves OK")
