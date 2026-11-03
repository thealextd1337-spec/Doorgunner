extends Node
## Headless test of the four late-game buildings (scripts/buildings3.gd, docs/ROADMAP3.md S1). main.gd adds this node when env SMOKE=late:
##   SMOKE=late godot --headless --path . --quit-after 30000
## Table, sprites, tooltips, codex and build bar; the unlock gate (day 20 or perimeter level 2); Fortress Wall (sandbag hp, new pieces, tint);
## Flak Emplacement (rocket, gunship, wave, ammo, range, limit); Command Post (rewards, a fourth mission, radio ahead); Supply Vault (caps,
## breach); upkeep (paid, idle when short, back when paid); a save and reload and an old save without the system.
## The node moves itself under the root and survives the scene reload.

const T := preload("res://scripts/chunk_manager.gd").T
const NAME := "LateTest"

var main: Node2D
var frame: Signal
var radio_log: Array[String] = []
var meta0: Dictionary


func _ready() -> void:
	if get_tree().root.has_node(NAME):
		queue_free()
		return
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	name = NAME
	frame = get_tree().process_frame
	await frame
	await frame
	meta0 = Game.meta.duplicate(true)
	Game.radio_message.connect(func(m: String): radio_log.append(m))
	_setup()
	_table()
	_gate()
	_fortress()
	_vault()
	_upkeep()
	_flak()
	_command()
	await _save_and_reload()
	await _old_save()
	_breach()
	Game.meta = meta0 # the smoke profile's best day would unlock slots in other tests
	Game._save_meta()
	Save.delete_run()
	print("LATE OK")
	get_tree().quit(0)


func _setup() -> void:
	main = Game.world
	for n in [main.spawner, main.missions, main.assault, main.bandits, main.evac]:
		n.set_process(false) # stepped by hand
	Game.level = Game.LEVEL_CAP # no upgrade cards
	_grass()
	Game.scrap = 20000
	Game.running = true


func _logged(part: String) -> bool:
	return radio_log.any(func(m): return part in m)


## Places and finishes `kind` on free ground, returns its entry.
func _build(kind: String) -> Dictionary:
	var n: int = Game.BUILDINGS[kind][3]
	var cell := _free_spot(n)
	assert(main.base.place_building(kind, cell), "%s placed at %s: %s" % [kind, cell, Buildings3.refusal(kind)])
	var b: Dictionary = main.base.building_at(cell)
	main.base._finish_site(b)
	assert(Game.built(kind) > 0 and main.base.site_nodes.has(cell) and main.base.site_nodes[cell].modulate.a == 1.0, "%s built" % kind)
	return b


func _table() -> void:
	var want := {"fortress": [400, 2], "flak": [500, 2], "command": [600, 2], "vault": [300, 2]}
	for k in want:
		var row: Array = Game.BUILDINGS[k]
		assert(row[1] == want[k][0] and row[3] == want[k][1], "%s costs %s" % [k, row])
		assert(Art.tex(k) != null and Buildings3.TIPS.has(k) and main.base.ui.BUILD_INFO.has(k), "%s has a sprite, a tooltip and a build entry" % k)
		assert(Tooltips.building(k) == Buildings3.TIPS[k] and main.base.ui.place_btns.has(k) and main.base.ui.bar_btns.has(k), "%s in the tooltips and both build lists" % k)
		assert(CodexContent.ROWS.any(func(e): return e[1] == "bld_" + k), "%s has a codex line" % k)
	assert(Buildings3.KINDS.size() == 4 and Game.BUILDINGS.size() == 18, "4 late kinds")
	var keys: Array = main.base.ui.BUILD_INFO.keys()
	assert(keys.slice(0, 9) == ["sandbag", "wire", "barracks", "clinic", "generator", "well", "watchtower", "motor_pool", "demolish"], "keys 1-9 are unchanged")
	assert(keys.size() == 20 and main.base.ui.bar_btns.size() == 20, "20 tools")
	assert(Buildings3.UPKEEP.size() >= 1 and Buildings3.UPKEEP.values().all(func(v): return v > 0), "something costs upkeep")


func _gate() -> void:
	var ui = main.base.ui
	Game.day = 3
	assert(Game.built("perimeter") == 0 and not Buildings3.unlocked(), "day 3, no ring: locked")
	for k in Buildings3.KINDS:
		assert("day 20" in Buildings2.refusal(k) and not main.base.can_place(k, _free_spot(2)) and not main.base.place_building(k, _free_spot(2)), "%s locked: %s" % [k, Buildings2.refusal(k)])
	ui.refresh()
	assert(not ui.bar_btns["flak"].visible and not ui.place_btns["vault"].visible and ui.bar_btns["relay"].visible, "locked tools are hidden, the rest is not")
	Game.day = Buildings3.UNLOCK_DAY - 1
	assert(not Buildings3.unlocked(), "day 19: locked")
	Game.day = Buildings3.UNLOCK_DAY
	assert(Buildings3.unlocked() and Buildings2.refusal("fortress") == "", "day 20: open")
	ui.refresh()
	assert(ui.bar_btns["flak"].visible and ui.place_btns["vault"].visible, "and shown")
	Game.day = 3
	Game.buildings.append({"kind": "perimeter", "cell": Vector2i.ZERO, "built": true, "progress": 0.0})
	assert(not Buildings3.unlocked(), "one ring is not enough")
	Game.buildings.append({"kind": "perimeter", "cell": Vector2i.ZERO, "built": false, "progress": 0.0})
	assert(not Buildings3.unlocked(), "a ring under construction does not count")
	Game.buildings.back()["built"] = true
	assert(Buildings3.unlocked() and Buildings2.refusal("vault") == "", "perimeter level 2: open on day 3")
	Game.buildings = Game.buildings.filter(func(b): return b["kind"] != "perimeter")
	Game.day = 25 # the rest of the test is past the gate
	assert(Buildings2.refusal("hospital") == "needs a built Field Clinic" and Buildings2.refusal("sandbag") == "", "other rules are not touched")


func _fortress() -> void:
	var cells: Array[Vector2i] = []
	for i in 3:
		var c := _free_spot(1)
		assert(main.base.place_sandbag(c, "sandbag"), "sandbag")
		Game.sandbags[c]["built"] = true
		cells.append(c)
	assert(Game.sandbags[cells[0]]["hp"] == Game.SANDBAG_HP and Buildings3.wall_factor() == 1.0, "plain sandbags first")
	var wire := _free_spot(1)
	main.base.place_sandbag(wire, "wire")
	var scrap0: int = Game.scrap
	_build("fortress")
	assert(Game.scrap == scrap0 - 400, "400 scrap")
	assert(Buildings3.wall_factor() == 2.0 and Buildings3.refusal("fortress") == "one is enough", "one wall, double hp")
	for c in cells:
		assert(Game.sandbags[c]["hp"] == Game.SANDBAG_HP * 2.0 and main.base.bags[c].self_modulate == Buildings3.WALL_TINT, "standing sandbags became walls")
	assert(Game.sandbags[wire]["hp"] == Game.WIRE_HP, "wire stays wire")
	var n := _free_spot(1)
	main.base.place_sandbag(n, "sandbag")
	assert(Game.sandbags[n]["hp"] == Game.SANDBAG_HP * 2.0 and main.base.bags[n].self_modulate == Buildings3.WALL_TINT, "new sandbags are walls")
	main.base.damage_sandbag(cells[0], Game.SANDBAG_HP)
	assert(Game.sandbags.has(cells[0]), "a wall takes a full sandbag's damage")
	main.base.damage_sandbag(cells[0], Game.SANDBAG_HP)
	assert(not Game.sandbags.has(cells[0]), "and falls at the double")
	for c in [cells[1], cells[2], wire, n]:
		main.base.remove_sandbag(c)


func _vault() -> void:
	var fuel0: float = Game.base_fuel_cap
	var ammo0: float = Game.base_ammo_cap
	assert(Buildings3.breach_factor() == 1.0, "no vault: a normal breach")
	_build("vault")
	assert(Game.base_fuel_cap == fuel0 * 1.5 and Game.base_ammo_cap == ammo0 * 1.5, "stores +50 %%: %s %s" % [Game.base_fuel_cap, Game.base_ammo_cap])
	assert(Buildings3.breach_factor() == 0.5 and Buildings3.refusal("vault") == "one is enough", "one vault, half a breach")
	Game.base_fuel = Game.base_fuel_cap - 10.0
	Game.base_fuel = minf(Game.base_fuel_cap, Game.base_fuel + 50.0)
	assert(Game.base_fuel == Game.base_fuel_cap and Game.base_fuel > fuel0, "more fits")
	assert(Buildings3.UPKEEP.get("vault", 0) == 0 and Buildings3.UPKEEP.get("fortress", 0) == 0, "vault and wall have no upkeep")


func _upkeep() -> void:
	var b3: Node = main.buildings3
	b3.unpaid = {}
	Game.scrap = 1000
	b3.pay_upkeep(1)
	assert(Game.scrap == 1000, "nothing with an upkeep stands yet")
	Game.scrap = 5000
	_build("flak")
	_build("command")
	assert(Buildings3.active("flak") and Buildings3.active("command"), "both work")
	Game.scrap = 1000
	b3.pay_upkeep(1)
	assert(Game.scrap == 1000 - Buildings3.UPKEEP["flak"] - Buildings3.UPKEEP["command"], "paid at dawn: %d" % Game.scrap)
	assert(Buildings3.active("flak") and Buildings3.active("command"), "paid, working")
	radio_log.clear()
	Game.scrap = 5
	b3.pay_upkeep(2)
	assert(Game.scrap == 5 and not Buildings3.active("flak") and not Buildings3.active("command") and _logged("upkeep"), "no scrap: idle and radioed")
	assert(Buildings3.reward_factor() == 1.0 and Buildings3.extra_missions() == 0, "an idle command post does nothing")
	assert(Game.built("flak") == 1, "but it still stands")
	Game.scrap = 500
	b3.pay_upkeep(3)
	assert(Buildings3.active("flak") and Buildings3.active("command") and Game.scrap == 500 - Buildings3.UPKEEP["flak"] - Buildings3.UPKEEP["command"], "paid again, back at work")
	var two_flaks := Buildings3.UPKEEP["flak"] * 2
	Game.scrap = 5000
	_build("flak")
	Game.scrap = 1000
	b3.pay_upkeep(4)
	assert(Game.scrap == 1000 - two_flaks - Buildings3.UPKEEP["command"], "upkeep per building")
	assert(Buildings3.refusal("flak") == "%d are enough" % Buildings3.FLAK_MAX, "two flaks at most")
	Game.scrap = 10000
	var before: int = radio_log.size()
	Game.base_founded = false
	b3.pay_upkeep(5)
	Game.base_founded = true
	assert(Game.scrap == 10000 and radio_log.size() == before, "no base, no upkeep")


func _flak() -> void:
	var b3: Node = main.buildings3
	b3.unpaid = {}
	var flaks := Game.buildings.filter(func(b): return b["kind"] == "flak")
	var pos: Vector2 = main.base.site_nodes[flaks[0]["cell"]].global_position
	var far: Vector2 = pos + Vector2(Buildings3.FLAK_RANGE + 80.0, 0)
	# a rocket in range goes down, one out of range does not
	var rk := Node2D.new()
	rk.add_to_group("rockets")
	main.add_child(rk)
	rk.global_position = pos + Vector2(Buildings3.FLAK_RANGE - 40.0, 0)
	var rk_far := Node2D.new()
	rk_far.add_to_group("rockets")
	main.add_child(rk_far)
	rk_far.global_position = far
	assert(b3.fire(pos) and rk.is_queued_for_deletion() and not rk_far.is_queued_for_deletion(), "the near rocket is shot down, the far one is not")
	rk_far.global_position = pos + Vector2(Buildings3.FLAK_RANGE, 0) * 0.5
	assert(b3.fire(pos) and rk_far.is_queued_for_deletion(), "it goes down once it is in range")
	assert(not b3.fire(pos), "nothing left to shoot")
	# a gunship
	var g := Nemesis.Gunship.new()
	g.position = pos + Vector2(200, 0)
	main.add_child(g)
	g.set_process(false)
	var hp0: float = g.hp
	assert(b3.fire(pos) and is_equal_approx(g.hp, hp0 - Buildings3.FLAK_AIR_DMG), "the gunship is hit: %s" % g.hp)
	var rk2 := Node2D.new()
	rk2.add_to_group("rockets")
	main.add_child(rk2)
	rk2.global_position = pos + Vector2(100, 0)
	var hp1: float = g.hp
	assert(b3.fire(pos) and rk2.is_queued_for_deletion() and g.hp == hp1, "a rocket comes first")
	g.position = pos + Vector2(Buildings3.FLAK_RANGE + 100, 0)
	assert(not b3.fire(pos), "a gunship out of range is left alone")
	g.queue_free()
	await_free([rk, rk_far, rk2])
	# a wave: fewer than FLAK_WAVE_MIN are left to the turrets, a crowd gets a burst
	var foes: Array = []
	var at: Vector2 = pos + Vector2(150, 0)
	for i in Buildings3.FLAK_WAVE_MIN - 1:
		foes.append(_foe(at + Vector2(i * 4, 0)))
	assert(not b3.fire(pos), "five zombies: no burst")
	foes.append(_foe(at + Vector2(30, 0)))
	var loner := _foe(at + Vector2(0, 120))
	var hp_loner: float = loner.hp
	var hp_foe: float = foes[0].hp
	assert(b3.fire(pos) and foes[0].hp == hp_foe - Buildings3.FLAK_SPLASH_DMG, "six zombies: the burst hits the crowd")
	assert(loner.hp == hp_loner, "and only what is within the splash")
	for e in foes + [loner]:
		e.queue_free()
	# over time: ammo is spent, a dry store holds fire, an idle flak is silent
	var rk3 := Node2D.new()
	rk3.add_to_group("rockets")
	main.add_child(rk3)
	rk3.global_position = pos + Vector2(120, 0)
	Game.base_ammo = 100.0
	b3.cd = 0.0
	b3.shots = 0
	b3._process(0.01)
	assert(b3.shots == 1 and Game.base_ammo == 100.0 - Buildings3.FLAK_AMMO and rk3.is_queued_for_deletion(), "a shot costs %s ammo" % Buildings3.FLAK_AMMO)
	var rk4 := Node2D.new()
	rk4.add_to_group("rockets")
	main.add_child(rk4)
	rk4.global_position = pos + Vector2(120, 0)
	Game.base_ammo = Buildings3.FLAK_AMMO - 1.0
	b3.cd = 0.0
	b3._process(0.01)
	assert(b3.shots == 1 and not rk4.is_queued_for_deletion(), "no ammo, no shot")
	Game.base_ammo = 100.0
	b3.unpaid["flak"] = true
	b3.cd = 0.0
	b3._process(0.01)
	assert(b3.shots == 1 and not rk4.is_queued_for_deletion(), "an idle flak does not fire")
	b3.unpaid.erase("flak")
	b3.cd = 0.0
	b3._process(0.01)
	assert(b3.shots >= 1 and rk4.is_queued_for_deletion(), "paid: it fires")
	rk4.queue_free()
	rk3.queue_free()
	Game.base_ammo = 800.0


func await_free(list: Array) -> void:
	for n in list:
		if is_instance_valid(n):
			n.queue_free()


func _foe(at: Vector2) -> Node2D:
	var e: Node2D = main.spawn_enemy("shambler", at, true)
	e.set_process(false)
	e.set_physics_process(false)
	e.global_position = at
	return e


func _command() -> void:
	var b3: Node = main.buildings3
	var m = main.missions
	m.open.clear()
	# rewards: camp pays 60-100 scrap, 150 XP
	var lo := 1000
	var hi := 0
	for i in 60:
		var r: Dictionary = m.paid(m._reward("camp"))
		lo = mini(lo, r["scrap"])
		hi = maxi(hi, r["scrap"])
		assert(r["xp"] == roundi(150 * 1.25), "xp +25 %%: %d" % r["xp"])
	assert(lo >= 75 and hi <= 125 and hi > 100, "scrap +25 %%: %d..%d" % [lo, hi])
	assert(Buildings3.reward_factor() == 1.25 and Buildings3.extra_missions() == 1 and Buildings3.refusal("command") == "one is enough", "one command post")
	# a fourth mission
	var bandits: Node = main.bandits
	bandits.camps.clear()
	Game.heli.position = main.base.global_position
	var site: Dictionary = main.chunks.sites_near(main.base.global_position, m.MAX_DIST).filter(func(x): return not x.uid in m.used)[0]
	bandits.add_camp(site.uid, "prison", site.pos)
	for i in m.MAX_OPEN:
		m._add("blackbox", {"pos": Vector2(1000 + i, 0), "text": "x", "state": {}})
	b3.unpaid["command"] = true
	assert(m.offer("camp").is_empty(), "idle command post: three at most")
	b3.unpaid.erase("command")
	var fourth: Dictionary = m.offer("camp")
	assert(not fourth.is_empty() and m.open.size() == m.MAX_OPEN + 1, "command post: a fourth mission")
	assert(m.offer("rooftop").is_empty(), "but not a fifth")
	assert(m.paid(fourth["reward"])["scrap"] >= 75, "and it pays more: %s" % [fourth["reward"]])
	# the bonus counts at payout: an offer taken while the post was idle still pays +25 %, and the other way round
	var base_scrap: int = fourth["reward"]["scrap"]
	assert(base_scrap <= 100 and "%d scrap" % roundi(base_scrap * 1.25) in m.reward_text(fourth["reward"]), "text shows the bonus")
	b3.unpaid["command"] = true
	assert(("%d scrap" % base_scrap) in m.reward_text(fourth["reward"]), "idle post: text without the bonus")
	var gain: float = Game.stats["xp_gain"]
	Game.stats["xp_gain"] = 0.0 # at the level cap XP turns into scrap: keep it out of the count
	var s0 := Game.scrap
	fourth["reward"].erase("person")
	m._finish(fourth, true)
	assert(Game.scrap == s0 + base_scrap, "idle post at payout: no bonus")
	b3.unpaid.erase("command")
	var fifth: Dictionary = m._add("rooftop", {"pos": Vector2(900, 0), "text": "x", "state": {}})
	fifth["reward"].erase("person")
	s0 = Game.scrap
	m._finish(fifth, true)
	assert(Game.scrap == s0 + roundi(fifth["reward"]["scrap"] * 1.25), "active post at payout: bonus")
	Game.stats["xp_gain"] = gain
	m.open.clear()
	bandits.camps.erase(site.uid)
	# radio ahead
	var nem = main.nemesis
	nem.rivals.clear()
	var day := 30
	Game.day = day
	nem.rivals["warlord"] = {"kind": "warlord", "name": "Test Kane", "trait": "brutal", "gen": 1, "stage": 3, "since": 1, "met": true, "escapes": 0, "away": -1, "raids": 2,
		"next_raid": 99, "attack_day": day, "hp": 1.0, "camp": "", "engaged": false, "spawn": false}
	b3.warned = {}
	radio_log.clear()
	Game.time = 0.5
	nem._attack_due()
	assert(not _logged("Command Post: radar"), "early in the day: quiet")
	Game.time = ATTACK_AT_MINUS
	nem._attack_due()
	assert(_logged("Command Post: radar shows Test Kane"), "shortly before the attack: radioed: %s" % [radio_log])
	radio_log.clear()
	nem._attack_due()
	assert(not _logged("Command Post"), "only once")
	b3.warned = {}
	b3.unpaid["command"] = true
	nem._attack_due()
	assert(not _logged("Command Post"), "an idle command post stays silent")
	b3.unpaid.erase("command")
	nem.rivals["warlord"]["attack_day"] = day + 2
	nem._attack_due()
	assert(not _logged("Command Post"), "not on another day")
	# the Alpha: warned only when her push will really join tonight's assault (same rule as _on_assault)
	nem.rivals.clear()
	nem.rivals["alpha"] = {"kind": "alpha", "name": "Test Mother", "trait": "brutal", "gen": 1, "stage": 3, "since": 1, "met": true, "escapes": 0, "away": -1, "raids": 2,
		"next_raid": day + 1, "attack_day": -1, "hp": 1.0, "camp": "", "engaged": false, "spawn": false}
	var pending: bool = Game.attack_pending
	Game.attack_pending = true # an assault tonight
	b3.warned = {}
	nem._attack_due()
	assert(not _logged("Command Post"), "her next push is not due yet: no warning")
	nem.rivals["alpha"]["next_raid"] = day
	Game.base_founded = false
	nem._attack_due()
	Game.base_founded = true
	assert(not _logged("Command Post"), "no base, no push: no warning")
	nem._attack_due()
	assert(_logged("Command Post: the horde is massing, and Test Mother"), "her push joins: warned: %s" % [radio_log])
	Game.attack_pending = pending
	nem.rivals.clear()
	Game.time = 0.25
	b3.warned = {}


const ATTACK_AT_MINUS := 0.85 - 0.05


func _save_and_reload() -> void:
	var b3: Node = main.buildings3
	b3.unpaid = {"flak": true}
	b3.warned = {"warlord": 30}
	var want := Game.buildings.filter(func(b): return b["built"]).map(func(b): return [b["kind"], b["cell"]])
	var fuel_cap: float = Game.base_fuel_cap
	assert(Game.built("fortress") == 1 and Game.built("flak") == 2 and Game.built("command") == 1 and Game.built("vault") == 1, "all four built")
	var walls := Game.sandbags.size()
	await _reload()
	b3 = main.buildings3
	var got := Game.buildings.filter(func(b): return b["built"]).map(func(b): return [b["kind"], b["cell"]])
	assert(var_to_str(got) == var_to_str(want), "buildings came back: %s" % [got])
	for b in Game.buildings:
		assert(main.base.site_nodes.has(b["cell"]) and main.base.site_nodes[b["cell"]].modulate.a == 1.0, "node for %s" % b["kind"])
	assert(b3.unpaid == {"flak": true} and b3.warned == {"warlord": 30}, "upkeep state came back: %s %s" % [b3.unpaid, b3.warned])
	assert(not Buildings3.active("flak") and Buildings3.active("command"), "idle stays idle")
	assert(Game.base_fuel_cap == fuel_cap, "the caps were saved, not applied twice: %s" % Game.base_fuel_cap)
	assert(Buildings3.wall_factor() == 2.0 and Buildings3.breach_factor() == 0.5 and Buildings3.reward_factor() == 1.25 and Game.sandbags.size() == walls, "effects follow the loaded buildings")
	var n := _free_spot(1)
	main.base.place_sandbag(n, "sandbag")
	assert(main.base.bags[n].self_modulate == Buildings3.WALL_TINT and Game.sandbags[n]["hp"] == Game.SANDBAG_HP * 2.0, "walls after load")
	main.base.remove_sandbag(n)
	main.base.ui.refresh()
	assert(main.base.ui.bar_btns["flak"].visible, "tools shown")


func _old_save() -> void:
	await _reload(func(systems: Dictionary):
		systems.erase("buildings3")) # a run saved before the late buildings had no such system
	assert(main.buildings3.unpaid.is_empty() and main.buildings3.warned.is_empty(), "no system key: defaults")
	assert(Game.built("fortress") == 1 and Buildings3.active("flak"), "old buildings stay, paid by default")
	main.base.ui.refresh()
	main.buildings3.pay_upkeep(9)


## The breach with a vault: one hurt instead of two, morale cost halved.
func _breach() -> void:
	main.assault.set_process(false)
	Game.rescued = 10
	Game.injured = 0
	Game.attack_active = true
	var b := _build("bunker")
	assert(Buildings3.breach_factor() == 0.5, "vault still there")
	var pending0: int = main.morale.pending.size()
	Game.base_hp = 5.0
	main.base.take_damage(40.0)
	assert(Game.running and Game.injured == 1, "a vault halves the injured of the breach: %d" % Game.injured)
	assert(main.morale.pending.size() == pending0 + 1 and main.morale.pending.back()[1] == main.morale.BREACH * 0.5, "and its morale: %s" % [main.morale.pending.back()])
	assert(b["kind"] == "bunker" and Game.built("bunker") == 0, "bunker spent")
	Game.running = true # for the shutdown below


## Saves, reloads the scene and loads (the test node survives), then sets the systems up again.
func _reload(edit := Callable()) -> void:
	Game.running = true
	assert(Save.autosave(), "saved")
	if edit.is_valid():
		var data := Save.read()
		edit.call(data["systems"])
		Save._write(var_to_bytes(data))
	Save.pending = true
	get_tree().paused = false
	get_tree().reload_current_scene()
	await frame
	await frame
	await frame
	main = Game.world
	for n in [main.spawner, main.missions, main.assault, main.bandits, main.evac]:
		n.set_process(false)
	Game.level = Game.LEVEL_CAP


func _free_spot(n: int) -> Vector2i:
	var c0 := Vector2i((main.base.global_position / 16.0).floor())
	for r in range(3, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cell := c0 + Vector2i(dx, dy)
				var ok := true
				for x in n:
					for y in n:
						ok = ok and main.base.free_cell(cell + Vector2i(x, y))
				if ok:
					return cell
	return Vector2i.ZERO


## Clean grass around the pad (the real terrain may hold houses and water at the start site).
func _grass() -> void:
	var c0 := Vector2i((main.base.global_position / 16.0).floor())
	for dx in range(-16, 17):
		for dy in range(-16, 17):
			var c := c0 + Vector2i(dx, dy)
			if main.base.building_at(c).is_empty():
				main.chunks.edit(c, T.GRASS)
