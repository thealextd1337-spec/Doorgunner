extends Node
## Headless test of the five Q9 buildings (scripts/buildings2.gd). main.gd adds this node when env SMOKE=buildings2 (base founded):
##   SMOKE=buildings2 godot --headless --path . --quit-after 30000
## Table and sprites, placement rules and tooltips, Field Hospital (beds, heal speed), Greenhouse (food for water), Forge (job, slots,
## scrap -> metal -> parts, keeps 30 scrap), Radio Relay (reach, raid heard a day early), Bunker (morale, one breach survived, not the
## final siege, then the run ends), the build bar, a save and reload with a Forge crew and an old save without any of it.
## The node moves itself under the root and survives the scene reload.

const T := preload("res://scripts/chunk_manager.gd").T
const NAME := "Buildings2Test"

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
	_rules()
	_hospital()
	_greenhouse()
	_forge()
	_relay()
	_bunker_morale()
	await _save_and_reload()
	await _old_save()
	_breach()
	Game.meta = meta0 # the smoke profile's best day would unlock slots in other tests
	Game._save_meta()
	Save.delete_run()
	print("BUILDINGS2 OK")
	get_tree().quit(0)


func _setup() -> void:
	main = Game.world
	for n in [main.spawner, main.missions, main.assault, main.bandits, main.evac]:
		n.set_process(false) # stepped by hand
	Game.level = Game.LEVEL_CAP # no upgrade cards
	_grass()
	Game.scrap = 3000
	Game.running = true


func _logged(part: String) -> bool:
	return radio_log.any(func(m): return part in m)


## Places and finishes `kind` on free ground, returns its entry.
func _build(kind: String) -> Dictionary:
	var n: int = Game.BUILDINGS[kind][3]
	var cell := _free_spot(n)
	assert(main.base.place_building(kind, cell), "%s placed at %s" % [kind, cell])
	var b: Dictionary = main.base.building_at(cell)
	main.base._finish_site(b)
	assert(Game.built(kind) > 0 and main.base.site_nodes.has(cell) and main.base.site_nodes[cell].modulate.a == 1.0, "%s built" % kind)
	return b


func _people(n: int, skill: String) -> void:
	Game.rescued = n
	for p in Game.people:
		p["skill"] = skill
		p["trait"] = ""
		p["injured"] = false
		p["pin"] = ""


func _table() -> void:
	var want := {"hospital": [110, 120.0, 2], "greenhouse": [70, 75.0, 2], "forge": [100, 100.0, 2], "bunker": [130, 120.0, 2], "relay": [100, 90.0, 1]}
	for k in want:
		var row: Array = Game.BUILDINGS[k]
		assert(row[1] == want[k][0] and row[2] == want[k][1] and row[3] == want[k][2], "%s costs %s" % [k, row])
		assert(Art.tex(k) != null and Buildings2.TIPS.has(k) and main.base.ui.BUILD_INFO.has(k), "%s has a sprite, a tooltip and a build entry" % k)
	assert(Buildings2.KINDS.size() == 5 and Game.BUILDINGS.size() == 14, "5 new kinds")
	var keys: Array = main.base.ui.BUILD_INFO.keys()
	assert(keys.slice(0, 9) == ["sandbag", "wire", "barracks", "clinic", "generator", "well", "watchtower", "motor_pool", "demolish"], "keys 1-9 are unchanged: %s" % [keys.slice(0, 9)])
	assert(keys.size() == 16 and main.base.ui.bar_btns.size() == 16 and main.base.ui.place_btns.size() == 16, "16 tools")
	assert(Game.workers.has("forge") and main.base.ui.JOBS.has("forge") and "forge" in Game.People.SKILL_JOBS["mechanic"] and "forge" in Game.People.SKILL_JOBS["engineer"], "the forge job")


func _rules() -> void:
	var ui = main.base.ui
	ui.refresh()
	assert("Clinic" in ui.place_btns["hospital"].tooltip_text, "hospital tooltip says why: %s" % ui.place_btns["hospital"].tooltip_text)
	var cell := _free_spot(2)
	assert(not main.base.can_place("hospital", cell) and not main.base.place_building("hospital", cell), "no hospital without a clinic")
	_build("clinic")
	assert(Buildings2.refusal("hospital") == "" and main.base.can_place("hospital", _free_spot(2)), "a clinic allows one hospital")
	_build("hospital")
	assert("clinic" in Buildings2.refusal("hospital") and not main.base.can_place("hospital", _free_spot(2)), "one hospital per clinic")
	var scrap0: int = Game.scrap
	var r := _free_spot(1)
	assert(main.base.place_building("relay", r) and Game.scrap == scrap0 - 100, "relay costs 100")
	assert(Buildings2.refusal("relay") == "one is enough" and not main.base.can_place("relay", _free_spot(1)), "one relay")
	main.base.remove_blueprint(r)
	assert(Game.scrap == scrap0 and Buildings2.refusal("relay") == "", "removing the blueprint refunds it and frees the slot")
	assert(Buildings2.refusal("sandbag") == "" and Buildings2.refusal("barracks") == "", "other tools are not touched")


func _hospital() -> void:
	Game.base_medicine = 20.0
	Game.treating = []
	_people(14, "farmer")
	Game.injured = 6
	assert(Game.built("clinic") == 1 and Game.built("hospital") == 1 and Game.clinic_beds() == 2 + Buildings2.HOSPITAL_BEDS, "6 beds")
	Game._treat(0.0)
	assert(Game.treating.size() == 6 and Game.base_medicine == 14.0, "six patients in beds: %d" % Game.treating.size())
	var h0: float = Game.treating[5]
	Game._treat(0.1)
	assert(is_equal_approx(h0 - Game.treating[5], 0.1 * Buildings2.HOSPITAL_HEAL), "the hospital heals %sx faster" % Buildings2.HOSPITAL_HEAL)
	Game.injured = 0
	Game.treating = []


func _greenhouse() -> void:
	_build("greenhouse")
	_build("greenhouse")
	var node: Node = main.buildings2
	Game.base_food = 10.0
	Game.base_water = 50.0
	node._process(Game.DAY_SECONDS * 0.1)
	assert(is_equal_approx(Game.base_food, 10.0 + 2 * Buildings2.GREENHOUSE_FOOD * 0.1), "two greenhouses grow food: %s" % Game.base_food)
	assert(is_equal_approx(Game.base_water, 50.0 - 2 * Buildings2.GREENHOUSE_WATER * 0.1), "and drink water: %s" % Game.base_water)
	Game.base_water = 0.0
	Game.base_food = 10.0
	node._process(Game.DAY_SECONDS * 0.1)
	assert(Game.base_food == 10.0 and Game.base_water == 0.0 and Buildings2.greenhouse_food() == 0.0, "no water, no harvest")
	Game.base_water = 50.0
	assert(Buildings2.greenhouse_food() == 10.0 and Buildings2.greenhouse_water() == 8.0, "per-day numbers for the menu")


func _forge() -> void:
	var ui = main.base.ui
	_people(6, "mechanic")
	Game.workers["fuel"] = 0
	assert(not ui.set_worker("forge", 1) and "Forge" in ui.worker_refusal("forge", 1), "no forge job without a forge: %s" % ui.worker_refusal("forge", 1))
	var f := _build("forge")
	ui.refresh()
	assert(ui.worker_refusal("forge", 1) == "" and ui.worker_refusal("forge", 2) == "" and "Forge" in ui.worker_refusal("forge", 3), "2 workers per forge")
	assert(ui.set_worker("forge", 2), "two on the forge")
	Game.assign_jobs()
	assert(Game.people.filter(func(p): return p["job"] == "forge").size() == 2 and Game.crew("forge") == 3.0, "mechanics fill it, 1.5 each")
	# a unit: part from metal first, else metal from scrap, never the last 30 scrap
	Game.salvage = {"metal": 4.0, "parts": 0.0, "electronics": 0.0}
	Game.scrap = 100
	assert(Buildings2.forge_unit() and Buildings2.forge_unit(), "two units")
	assert(Game.salvage["metal"] == 0.0 and Game.salvage["parts"] == 2.0, "4 metal make 2 parts: %s" % [Game.salvage])
	assert(Buildings2.forge_unit() and Game.scrap == 97 and Game.salvage["metal"] == 1.0, "no metal for a part: 3 scrap make metal")
	Game.salvage["metal"] = 0.0
	Game.scrap = 32
	assert(not Buildings2.forge_unit() and Game.scrap == 32, "32 scrap: the last 30 stay")
	Game.scrap = 33
	assert(Buildings2.forge_unit() and Game.scrap == 30 and Game.salvage["metal"] == 1.0, "33 scrap: one more metal")
	assert(not Buildings2.forge_unit() and Game.scrap == 30, "and no more")
	Game.salvage = {"metal": 0.0, "parts": Buildings2.FORGE_CAP, "electronics": 0.0}
	Game.scrap = 1000
	for i in int(Buildings2.FORGE_CAP):
		Buildings2.forge_unit()
	assert(Game.salvage["metal"] == Buildings2.FORGE_CAP and not Buildings2.forge_unit(), "stops at the cap")
	# over time: the crew's work becomes parts
	Game.salvage = {"metal": 0.0, "parts": 0.0, "electronics": 0.0}
	Game.scrap = 1000
	main.buildings2.forge_progress = 0.0
	Game.base_food = 100.0
	main.buildings2._process(Game.DAY_SECONDS * 0.5)
	var units: float = 3.0 * Buildings2.FORGE_RATE * 0.5 * Game.work_eff()
	assert(Game.salvage["parts"] >= 1.0 and Game.salvage["parts"] <= units, "half a day of two workers made parts: %s (%s units)" % [Game.salvage, units])
	assert(Game.scrap < 1000, "from scrap")
	Game.scrap = 3000
	# the pawn walks to the forge
	main.base.sync_pawns()
	var pawn: Node2D = main.base.pawns.get_children().filter(func(p): return p.job == "forge").front()
	pawn._pick()
	assert(pawn.target.distance_to(main.base.door("forge")) < 20.0, "a forge worker goes to the forge door")
	assert("forge" in pawn.TOOL_JOBS and pawn.gear == "tool", "and carries a tool")
	assert(f["built"], "forge built")


func _relay() -> void:
	assert(Buildings2.reach() == 1.0 and Buildings2.lead() == 0, "no relay: normal reach, same-day warning")
	var b: Node = main.bandits
	b.add_camp("q9_camp", "prison", Vector2(9000, 9000))
	var d := 12 # a day and the next without a zombie assault night
	while Assault.night_taken(d) or Assault.night_taken(d + 1):
		d += 1
	Game.day = d
	b.base_raid_day = -1
	b.last_base_raid = -100
	assert(b.plan_base_raid(d + Buildings2.lead(), true) and b.base_raid_day == d and _logged("Tonight we take"), "without a relay: tonight")
	b.base_raid_day = -1
	_build("relay")
	assert(Buildings2.reach() == Buildings2.RELAY_REACH and Buildings2.lead() == 1, "relay: 1.5x reach, a day early")
	assert(Buildings2.reach() * 480.0 == 720.0 and Buildings2.reach() * 3000.0 == 4500.0 and Buildings2.reach() * 2600.0 == 3900.0, "reveal 720, hints 4500, missions 3900")
	radio_log.clear()
	Game.day = d
	b.last_base_raid = -100
	assert(b.plan_base_raid(d + Buildings2.lead(), true) and b.base_raid_day == d + 1 and _logged("Tomorrow night"), "the relay hears day %d's raid on day %d: %s" % [d + 1, d, radio_log])
	Game.day = d + 1
	assert(not b.plan_base_raid(d + 1 + Buildings2.lead(), true) and b.base_raid_day == d + 1, "the next day's look-ahead does not overwrite tonight's raid")
	b.base_raid_day = -1
	b.camps.erase("q9_camp")
	Game.day = 1


func _bunker_morale() -> void:
	var m = main.morale
	m.pending = []
	assert(Buildings2.loss_factor() == 1.0, "no bunker, normal losses")
	_build("bunker")
	assert(Buildings2.loss_factor() == Buildings2.BUNKER_LOSSES, "a bunker halves what losses weigh")
	Game.attack_active = true
	m._process(0.0)
	Game.attack_active = false
	m._process(0.0)
	assert(m.pending.any(func(x): return x[0] == "assault held" and x[1] == m.ASSAULT_HELD + Buildings2.BUNKER_HELD), "a held assault counts +%s: %s" % [m.ASSAULT_HELD + Buildings2.BUNKER_HELD, m.pending])
	m.pending = []
	m._attack_deaths = 0
	Game.attack_active = true
	m._process(0.0)
	m._attack_deaths = 1
	Game.attack_active = false
	m._process(0.0)
	assert(m.pending.any(func(x): return x[0] == "losses in the assault" and absf(x[1]) <= absf(m.ASSAULT_LOSSES) * Buildings2.BUNKER_LOSSES + 0.001), "losses weigh half: %s" % [m.pending])
	m.pending = []
	assert(Buildings2.refusal("bunker") == "one is enough", "one bunker")


func _save_and_reload() -> void:
	_people(8, "mechanic")
	Game.workers["forge"] = 2
	main.buildings2.forge_progress = 0.5
	var want := Game.buildings.filter(func(b): return b["built"]).map(func(b): return [b["kind"], b["cell"]])
	assert(Game.built("hospital") == 1 and Game.built("greenhouse") == 2 and Game.built("forge") == 1 and Game.built("bunker") == 1 and Game.built("relay") == 1, "all five built: %s" % [Game.buildings.map(func(b): return [b["kind"], b["built"]])])
	await _reload()
	var got := Game.buildings.filter(func(b): return b["built"]).map(func(b): return [b["kind"], b["cell"]])
	assert(var_to_str(got) == var_to_str(want), "buildings came back: %s" % [got])
	for b in Game.buildings:
		assert(main.base.site_nodes.has(b["cell"]) and main.base.site_nodes[b["cell"]].modulate.a == 1.0, "node for %s" % b["kind"])
	Game.assign_jobs()
	assert(Game.workers["forge"] == 2 and Game.crew("forge") == 3.0, "the forge crew is back")
	assert(main.buildings2.forge_progress > 0.45, "forge progress saved (a few frames ran since): %s" % main.buildings2.forge_progress)
	assert(Buildings2.reach() == 1.5 and Game.clinic_beds() == 6, "effects follow the loaded buildings")
	main.base.ui.refresh()


func _old_save() -> void:
	await _reload(func(systems: Dictionary):
		systems.erase("buildings2")
		systems["game"]["workers"].erase("forge")) # a run saved before the new buildings had no forge job or system
	assert(Game.workers.has("forge") and Game.workers["forge"] == 0, "the forge job defaults to 0")
	assert(main.buildings2.forge_progress == 0.0, "no system key: defaults")
	main.base.ui.refresh()
	assert(Game.built("bunker") == 1, "old buildings stay")
	main.base.ui.set_worker("forge", 1)
	assert(Game.workers["forge"] == 1, "and the job works")
	Game.workers["forge"] = 0


## The breach, last: the bunker saves the base once (and not the final siege), then the next breach ends the run.
func _breach() -> void:
	main.assault.set_process(false)
	_people(10, "farmer")
	Game.injured = 0
	var e: Node2D = main.spawn_enemy("shambler", main.base.position + Vector2(200, 0), true)
	e.target_base = true
	Game.attack_active = true
	main.assault.queue = ["shambler", "shambler"]
	Game.base_hp = 5.0
	var bunker_cell: Vector2i = Game.buildings.filter(func(b): return b["kind"] == "bunker")[0]["cell"]
	main.assault.final = true
	assert(not Buildings2.shelter() and Game.built("bunker") == 1, "not against the final siege")
	main.assault.final = false
	var morale0: int = main.morale.pending.size()
	main.base.take_damage(40.0)
	assert(Game.running and Game.base_hp == Game.max_base_hp * Buildings2.BUNKER_HULL, "the base survived the breach: hull %s" % Game.base_hp)
	assert(Game.built("bunker") == 0 and not main.base.site_nodes.has(bunker_cell), "the bunker is spent and gone")
	assert(not Game.attack_active and main.assault.queue.is_empty() and not e.target_base, "the wave broke off")
	assert(Game.injured == Buildings2.BUNKER_INJURED and Game.rescued == 10, "everyone lived, %d hurt" % Buildings2.BUNKER_INJURED)
	assert(main.morale.pending.size() == morale0 + 1 and main.morale.pending.back()[0] == "base breached", "morale: breached, not held: %s" % [main.morale.pending])
	assert(_logged("bunker") and Buildings2.refusal("bunker") == "", "radioed, and a new bunker may be built")
	main.base.take_damage(1000.0)
	assert(not Game.running, "the next breach, without a bunker, ends the run")
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
