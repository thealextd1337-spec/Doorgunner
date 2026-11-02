extends Node
## Onboarding (docs/ROADMAP2.md Q11): radio-guided CHAPTERS, one-time context HINTS and the codex unlocks. Tutorial chapter 1 stays in
## tutorial.gd; this node lives next to it and is never `Game.world.tutorial` (save.gd refuses to autosave while a tutorial runs).
## Polls the game state twice a second (SCAN_EVERY), so no other file needs a hook: a chapter starts when its trigger holds the first
## time, each step waits on a condition (_w_<when>, at least STEP_MIN s on screen), the last one closes the chapter. Chapters and hints
## already seen are listed in meta.json "onboarding" (per profile). The "Tutorial hints" setting turns chapters and hints off;
## the codex keeps filling. Texts: {action} becomes the current key (KeyMap.tag), "touch" is the Controls.touch variant.
## Codex unlocks: z_<kind> / b_<kind> for every enemy seen within SEE_DIST (a row of codex_content.gd with that id is enough, later
## enemy kinds unlock themselves), bld_<kind> when placed, item_<id> / heli_<type> when owned, sys_<name> by the rules in _sys().

const KEY := "onboarding" # Settings toggle key
const SCAN_EVERY := 0.5
const STEP_MIN := 1.5 # s a step stays up before its condition may close it
const WAIT := 7.0 # s an info step ("wait") stays up
const HINT_SECONDS := 9.0
const SEE_DIST := 450.0 # an enemy this close to the heli is "met" (codex, hints)
const MISSION_NEAR := 350.0
const KILLS_ASSAULT := 5
const KILLS_BANDITS := 3

# Chapters, in priority order. "trigger": _t_<name>; "urgent": may cut off the running chapter (which restarts later).
# Step: "t" text, "touch" optional text for touch mode, "when": _w_<name> (wait = info step).
const CHAPTERS := {
	"assault": {"title": "First assault", "trigger": "assault", "urgent": true, "steps": [
		{"t": "Horde warning. They come at dusk, from one side. Land by the pad: the base is your command post.", "when": "assault_on"},
		{"t": "Hold the line. {fire} fires the door gun, aim with the mouse. Sandbags and militia do the rest.",
			"touch": "Hold the right stick out to fire the door gun. Sandbags and militia do the rest.", "when": "kills_assault"},
		{"t": "Watch the base hull in the status panel. Keep the gun fed: ammo comes from the base stock.", "when": "assault_over"},
		{"t": "Dawn. A held assault lifts morale; the fallen drag it down. Rebuild sandbags in the BUILD tab.", "when": "wait"},
	]},
	"base": {"title": "Base & workers", "trigger": "base", "steps": [
		{"t": "Land on the pad and the base menu opens. Its tabs run everything: workers, building, upgrades, hangar.", "when": "base_menu"},
		{"t": "WORKERS tab: put someone on Farm. Everyone eats every day, and hunger kills morale first.", "when": "farm"},
		{"t": "Put one worker on Fuel and one on Ammo. That is the stock you refill from on the pad.", "when": "fuel_ammo"},
		{"t": "BUILD tab: a Well keeps the base drinking. Place the blueprint, a build worker does the rest.", "when": "well"},
		{"t": "Idle hands eat but do not work. Keep the jobs filled, and give the injured a clinic bed.", "when": "wait"},
	]},
	"missions": {"title": "Radio missions", "trigger": "missions", "steps": [
		{"t": "Command put a job on the board. Open the list with {missions}.", "touch": "Command put a job on the board. Tap JOBS for the list.", "when": "mission_list"},
		{"t": "Every job has a clock. The compass arrow points at the target: fly there.", "when": "mission_near"},
		{"t": "Do what the card says: rescue, silence, escort, clear. Land close when it asks for it.", "when": "mission_done"},
		{"t": "Jobs pay scrap and XP, now and then a rare specialist: Engineers and Drivers.", "when": "wait"},
	]},
	"outposts": {"title": "Outposts & villages", "trigger": "outposts", "steps": [
		{"t": "A gas station, checkpoint or radio mast can be held as an outpost. Load militia at the base pad first: {outpost}.",
			"touch": "A gas station, checkpoint or radio mast can be held as an outpost. Load militia at the base pad: tap OUTPOST.", "when": "crew"},
		{"t": "Fly to the site, land on it and press {outpost}. It costs scrap and the crew stays.",
			"touch": "Fly to the site, land on it and tap OUTPOST. It costs scrap and the crew stays.", "when": "outpost_set"},
		{"t": "Land at your outpost to refuel and rearm in the field. Raiders will come for it, so check the map.", "when": "outpost_service"},
		{"t": "Villages: land beside a survivor settlement and press {protect} to ally it. Allies trade food and water.",
			"touch": "Villages: land beside a survivor settlement and tap PROTECT to ally it. Allies trade food and water.", "when": "village"},
	]},
	"bandits": {"title": "Bandits", "trigger": "bandits", "steps": [
		{"t": "Bandits. Riflemen, MG nests, RPG gunners, technicals. They shoot back, so stay fast and use cover.", "when": "wait"},
		{"t": "Shoot a few. A moving heli is hit half as often as a parked one.", "when": "bandit_kills"},
		{"t": "Clear a camp: kill the garrison, then land to free prisoners and loot the crates.", "when": "camp_cleared"},
		{"t": "They also raid villages, outposts and your base. Their rifles end up in your armory.", "when": "wait"},
	]},
	"convoys": {"title": "Convoys", "trigger": "convoys", "steps": [
		{"t": "The Motor Pool is up. CONVOY tab: build a truck from salvage (metal and parts).", "when": "truck"},
		{"t": "Choose a destination and a driver, add escorts if you can spare them, then SEND.", "when": "sent"},
		{"t": "Trucks drive the road network on their own. Ambushes happen: keep an eye on the minimap.", "when": "trip"},
		{"t": "A truck brings home fuel, ammo and salvage. A lost truck loses cargo and crew.", "when": "wait"},
	]},
	"wrecks": {"title": "Wrecks", "trigger": "wrecks", "steps": [
		{"t": "A downed heli below. Slow to a hover over it and press {hook}.", "touch": "A downed heli below. Slow to a hover over it and tap HOOK.", "when": "hooked"},
		{"t": "Hold her steady until the hook bites, then carry it home. The load is heavy and the fuel burns fast.", "when": "slung"},
		{"t": "Over the pad, {hook} again to let go. Then HANGAR tab: a repair needs parts, electronics and a Mechanic.",
			"touch": "Over the pad, tap HOOK again to let go. Then HANGAR tab: a repair needs parts, electronics and a Mechanic.", "when": "wreck_home"},
		{"t": "Military wrecks may carry key parts. A repaired heli can be flown from the HANGAR.", "when": "wait"},
	]},
	"evac": {"title": "Evacuation", "trigger": "evac", "steps": [
		{"t": "Military frequency. Build a Radio Station (BUILD tab) and staff it with an Engineer.", "when": "radio_contact"},
		{"t": "Next the Airstrip: a long strip of clear ground inside your fence.", "when": "airstrip"},
		{"t": "When the strip is ready the transport is called. Three days later comes one last siege.", "when": "evac_phase"},
		{"t": "Hold the base until everyone is aboard. Leaving ends the run in victory. Staying is allowed.", "when": "wait"},
	]},
}

# One-time hints (per profile), checked in order. "when": _h_<name>.
const HINTS := {
	"injured": {"when": "injured", "t": "Injured aboard. At the base they need a clinic bed and medicine, or they get worse."},
	"jam": {"when": "jam", "t": "Gun jam. Wait it out. Wear is the cause: repair the gun in the HANGAR tab and the jams stop."},
	"wear_alarm": {"when": "wear_alarm", "t": "Wear alarm. A part is failing. Land at once, or you drop into autorotation."},
	"rpg": {"when": "rpg", "t": "RPG gunner. The red line means a rocket in a second and a half. Turn hard across it, or pop flares."},
	"spitter": {"when": "spitter", "t": "Spitter. Acid pools burn the heli. Keep moving and shoot from range."},
	"screamer": {"when": "screamer", "t": "Screamer. His scream calls a horde. Shoot him first."},
	"bloater": {"when": "bloater", "t": "Bloater. He bursts into gas when he dies. Pop him from range."},
	"armored": {"when": "armored", "t": "Armored brute. Plated in front, so hit him from behind or use a gun that punches through."},
	"boss": {"when": "boss", "t": "Boss. The night does not end until he is dead. Save your heaviest gun and your ammo."},
	"night": {"when": "night", "t": "Night. You see less, and so do they. A Searchlight or Thermal Sight pays off now."},
	"low_fuel": {"when": "low_fuel", "t": "Low fuel. Turn back to the pad, or to a gas station you hold as an outpost."},
	"low_ammo": {"when": "low_ammo", "t": "Low ammo. The base stock refills the heli on the pad. Ammo workers keep it full."},
	"low_hull": {"when": "low_hull", "t": "Hull low. Land at base: medics and repair crews patch it. A Medic item helps in the air."},
	"hungry": {"when": "hungry", "t": "The base is out of food or water. Put workers on Farm and Water, and build a Well."},
	"cards": {"when": "cards", "t": "Level-up cards: {reroll} rerolls, {skip} skips for scrap, {banish} banishes a card for good.",
		"touch": "Level-up cards: tap one to take it. REROLL, SKIP and BANISH sit under the cards."},
	"base_hurt": {"when": "base_hurt", "t": "The base hull is low. Shoot from the pad and rebuild sandbags in the BUILD tab."},
}

var chapter := "" # running chapter id
var step := 0
var step_age := 0.0
var base := {} # baselines taken when the chapter started
var near := {} # codex ids of the enemies within SEE_DIST at the last scan
var panel: PanelContainer
var head_label: Label
var text_label: Label
var skip_btn: Button
var hint_t := 0.0 # seconds the shown hint stays
var _scan_t := 0.0
var _missions_ui: Node


func _init() -> void:
	if not Settings.defs.has(KEY): # a reloaded main scene keeps the registration
		Settings.register_toggle(KEY, "Tutorial hints & chapters", true)
	CodexContent.register_all()


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12 # over the HUD, under the menus
	add_child(layer)
	var root := UiTheme.attach(layer)
	root.theme = UiTheme.theme()
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -150.0 # clear of the radio log; the tutorial card sits in the same band
	panel.custom_minimum_size = Vector2(440, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.04, 0.92)
	sb.border_width_top = 6
	sb.border_color = UiTheme.ACCENT
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	head_label = _label(UiTheme.FONT_S, UiTheme.ACCENT)
	v.add_child(head_label)
	text_label = _label(UiTheme.FONT_L, UiTheme.SAND)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(text_label)
	skip_btn = Button.new()
	skip_btn.text = "Skip chapter"
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	skip_btn.pressed.connect(skip_chapter)
	v.add_child(skip_btn)
	panel.visible = false
	Settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key == KEY and not enabled():
			_end_chapter(false)
			panel.visible = false)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func enabled() -> bool:
	return Settings.is_on(KEY)


func _process(delta: float) -> void:
	if not Game.running or Game.world == null:
		return
	step_age += delta
	if hint_t > 0.0:
		hint_t -= delta
		if hint_t <= 0.0 and chapter == "":
			panel.visible = false
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = SCAN_EVERY
		scan()


## One pass: codex unlocks, then the running chapter or a new one, then hints. Public so the test can drive it.
func scan() -> void:
	_scan_codex()
	if not enabled() or is_instance_valid(Game.world.tutorial) or Game.heli == null:
		return
	if chapter != "":
		_urgent()
	if chapter == "":
		_start_next()
	elif step_age >= STEP_MIN and _done(CHAPTERS[chapter]["steps"][step]["when"]):
		_next_step()
	_hints()


# --- chapters -------------------------------------------------------------------------------------------------------

func seen(id: String) -> bool:
	return id in Game.meta[KEY].split(",", false)


func _mark(id: String) -> void:
	if not seen(id):
		Game.meta[KEY] = ",".join(PackedStringArray(Game.meta[KEY].split(",", false)) + PackedStringArray([id]))
		Game._save_meta()


func _start_next() -> void:
	if not Game.base_founded or Game.world.choice_ui.visible:
		return
	for id: String in CHAPTERS:
		if not seen("ch_" + id) and call("_t_" + CHAPTERS[id]["trigger"]):
			start_chapter(id)
			return


## An urgent chapter (the assault) cuts off a running one; that one is not marked and starts again later.
func _urgent() -> void:
	for id: String in CHAPTERS:
		if CHAPTERS[id].get("urgent", false) and id != chapter and not seen("ch_" + id) and Game.base_founded and call("_t_" + CHAPTERS[id]["trigger"]):
			if not CHAPTERS[chapter].get("urgent", false):
				start_chapter(id)
			return


func start_chapter(id: String) -> void:
	chapter = id
	step = -1
	base = {"kills": Game.kills, "completed": Game.world.missions.completed}
	Game.radio("Command: %s - short briefing. Skip it from the panel or turn hints off in the ESC menu." % CHAPTERS[id]["title"])
	_next_step()


func _next_step() -> void:
	step += 1
	var steps: Array = CHAPTERS[chapter]["steps"]
	if step >= steps.size():
		_end_chapter(true)
		return
	step_age = 0.0
	var txt := _fmt(steps[step])
	head_label.text = "%s  ·  STEP %d / %d" % [CHAPTERS[chapter]["title"].to_upper(), step + 1, steps.size()]
	text_label.text = txt
	skip_btn.visible = true
	skip_btn.custom_minimum_size.y = UiTheme.TOUCH_MIN if Controls.touch else 0.0
	panel.visible = true
	panel.modulate = Color(2, 2, 1.4)
	create_tween().tween_property(panel, "modulate", Color.WHITE, 0.6)
	Game.radio("Command: " + txt)


func skip_chapter() -> void:
	if chapter != "":
		Game.radio("Command: %s skipped." % CHAPTERS[chapter]["title"])
		_end_chapter(true)


func _end_chapter(mark: bool) -> void:
	if chapter != "" and mark:
		_mark("ch_" + chapter)
	chapter = ""
	panel.visible = false


## The text of a step or hint for the input mode in use, with {action} replaced by the current key.
func _fmt(item: Dictionary) -> String:
	var s: String = item["touch"] if Controls.touch and item.has("touch") else item["t"]
	if "{" in s:
		var keys := {}
		for a: String in KeyMap.actions():
			keys[a] = KeyMap.tag(a)
		s = s.format(keys)
	return s


func _done(when: String) -> bool:
	return when == "wait" and step_age >= WAIT or when != "wait" and call("_w_" + when)


# --- hints ----------------------------------------------------------------------------------------------------------

func _hints() -> void:
	for id: String in HINTS:
		if not seen("hint_" + id) and call("_h_" + HINTS[id]["when"]):
			_mark("hint_" + id)
			var txt := _fmt(HINTS[id])
			Game.radio("Command: " + txt)
			if chapter == "": # a chapter step owns the panel, the radio line is enough then
				head_label.text = "HINT"
				text_label.text = txt
				skip_btn.visible = false
				panel.visible = true
				hint_t = HINT_SECONDS
			return # one per scan


func _h_injured() -> bool: return Game.passengers_injured > 0
func _h_jam() -> bool: return Game.world.wear.jam_t > 0.0
func _h_wear_alarm() -> bool: return Game.world.wear.state in ["warn", "auto"]
func _h_rpg() -> bool: return near.has("b_rpg")
func _h_spitter() -> bool: return near.has("z_spitter")
func _h_screamer() -> bool: return near.has("z_screamer")
func _h_bloater() -> bool: return near.has("z_bloater")
func _h_armored() -> bool: return near.has("z_brute_armored")
func _h_boss() -> bool: return near.has("z_boss")
func _h_night() -> bool: return Game.base_founded and Game.is_night()
func _h_low_fuel() -> bool: return Game.fuel < Game.max_fuel * 0.25 and not Game.heli.landed
func _h_low_ammo() -> bool: return Game.ammo < Game.max_ammo * 0.15 and not Game.heli.landed
func _h_low_hull() -> bool: return Game.hp < Game.max_hp * 0.3
func _h_hungry() -> bool: return Game.short_days > 0
func _h_cards() -> bool: return Game.level >= 2
func _h_base_hurt() -> bool: return Game.attack_active and Game.base_hp < Game.max_base_hp * 0.4


# --- chapter triggers and step conditions ---------------------------------------------------------------------------

func _t_assault() -> bool: return Game.attack_pending or Game.attack_active
func _t_base() -> bool: return not Game.attack_pending and not Game.attack_active
func _t_missions() -> bool: return not Game.world.missions.open.is_empty()
func _t_outposts() -> bool:
	var w := Game.world
	return not w.outposts.site_here().is_empty() or not w.outposts.village_near(Game.heli.position, 300.0).is_empty()
func _t_bandits() -> bool: return Game.world.bandits.camps.values().any(func(c): return c["known"]) or near.keys().any(func(id: String) -> bool: return id.begins_with("b_"))
func _t_convoys() -> bool: return Game.world.convoys.pools() > 0
func _t_wrecks() -> bool: return Game.world.wrecks.wrecks.values().any(func(w): return w.get("spotted", false))
func _t_evac() -> bool: return Game.world.evac.announced

func _w_assault_on() -> bool: return Game.attack_active
func _w_kills_assault() -> bool: return Game.kills >= base["kills"] + KILLS_ASSAULT
func _w_assault_over() -> bool: return not Game.attack_active and not Game.attack_pending
func _w_base_menu() -> bool: return Game.world.base.ui.visible and not Game.world.base.ui.collapsed
func _w_farm() -> bool: return Game.workers["farm"] >= 1
func _w_fuel_ammo() -> bool: return Game.workers["fuel"] >= 1 and Game.workers["ammo"] >= 1
func _w_well() -> bool: return Game.buildings.any(func(b): return b["kind"] == "well")
func _w_mission_list() -> bool:
	if not is_instance_valid(_missions_ui):
		var found := Game.world.get_children().filter(func(c): return c.get_script() == preload("res://scripts/missions_ui.gd"))
		_missions_ui = found[0] if not found.is_empty() else null
	return _missions_ui != null and _missions_ui.panel.visible
func _w_mission_near() -> bool: return Game.world.missions.open.any(func(m): return Game.heli.global_position.distance_to(m["pos"]) < MISSION_NEAR)
func _w_mission_done() -> bool: return Game.world.missions.completed > base["completed"] or Game.world.missions.open.is_empty()
func _w_crew() -> bool: return not Game.world.outposts.crew().is_empty() or not Game.world.outposts.list.is_empty()
func _w_outpost_set() -> bool: return not Game.world.outposts.list.is_empty()
func _w_outpost_service() -> bool: return Game.heli.landed and not Game.world.outposts.outpost_at(Game.heli.position).is_empty()
func _w_village() -> bool: return not Game.world.outposts.allies.is_empty()
func _w_bandit_kills() -> bool: return Game.kills >= base["kills"] + KILLS_BANDITS
func _w_camp_cleared() -> bool: return Game.world.bandits.camps.values().any(func(c): return c["cleared"])
func _w_truck() -> bool: return Game.world.convoys.trucks > 0 or not Game.world.convoys.list.is_empty()
func _w_sent() -> bool: return not Game.world.convoys.list.is_empty() or not Game.world.convoys.trips.is_empty()
func _w_trip() -> bool: return not Game.world.convoys.trips.is_empty()
func _w_hooked() -> bool: return Game.world.wrecks.hook != ""
func _w_slung() -> bool: return Game.world.wrecks.slung()
func _w_wreck_home() -> bool: return Game.world.wrecks.wrecks.values().any(func(w): return w["state"] in ["base", "repair", "parked"])
func _w_radio_contact() -> bool: return Game.world.evac.contact
func _w_airstrip() -> bool: return Game.buildings.any(func(b): return b["kind"] == "airstrip")
func _w_evac_phase() -> bool: return Game.world.evac.phase != ""


# --- codex ----------------------------------------------------------------------------------------------------------

func _unlock(id: String) -> void:
	if Codex.entries.has(id) and Codex.unlock(id):
		Game.radio("Codex: %s added (%s)." % [Codex.entries[id]["title"], KeyMap.tag("help")])


func _scan_codex() -> void:
	var w := Game.world
	near = {}
	if Game.heli != null:
		var hp: Vector2 = Game.heli.global_position
		for n: Node2D in get_tree().get_nodes_in_group("enemies"):
			if not is_instance_valid(n) or n.global_position.distance_to(hp) > SEE_DIST:
				continue
			var id := ""
			if n is Bandit:
				id = "b_" + n.kind
			elif n.get("kind") == "nest":
				id = "z_nest"
			elif "cfg" in n:
				id = "z_" + n.kind
			if id != "":
				near[id] = true
	for id: String in near:
		_unlock(id)
	if not Game.base_founded:
		return
	_unlock("bld_pad")
	for b: Dictionary in Game.buildings:
		_unlock("bld_" + b["kind"])
	for s: Dictionary in Game.sandbags.values():
		_unlock("bld_" + s["kind"])
	for id: String in Game.heli_items:
		_unlock("item_" + id)
	for id: String in Game.heli_weapons + Game.weapon_bay:
		_unlock("item_" + id)
	_unlock("heli_" + w.wrecks.type_id())
	for ww: Dictionary in w.wrecks.wrecks.values():
		if ww["state"] != "site" or ww.get("spotted", false):
			_unlock("heli_" + ww["type"])
	for sys: String in ["save", "noise", "night", "cards", "food_water", "injury", "morale", "assault", "wear", "missions", "bandits",
			"outposts", "villages", "convoys", "wrecks", "evac", "modifiers"]:
		if _sys(sys):
			_unlock("sys_" + sys)


## When a system becomes known: the moment the player first meets it.
func _sys(sys: String) -> bool:
	var w := Game.world
	match sys:
		"save": return Game.base_founded
		"noise": return Game.noise_level > 0.3
		"night": return Game.is_night()
		"cards": return Game.level >= 2
		"food_water": return Game.day >= 2
		"injury": return Game.injured > 0 or Game.passengers_injured > 0
		"morale": return Game.day >= 2
		"assault": return Game.attack_pending or Game.attack_active
		"wear": return w.wear.state != "" or w.wear.jam_t > 0.0 or w.wear.cond.values().any(func(c): return c < 90.0)
		"missions": return not w.missions.open.is_empty() or w.missions.completed > 0
		"bandits": return w.bandits.camps.values().any(func(c): return c["known"]) or near.keys().any(func(id: String) -> bool: return id.begins_with("b_"))
		"outposts": return not w.outposts.list.is_empty() or not w.outposts.site_here().is_empty()
		"villages": return not w.outposts.allies.is_empty() or not w.outposts.village_near(Game.heli.position, 300.0).is_empty()
		"convoys": return w.convoys.pools() > 0 or w.convoys.trucks > 0
		"wrecks": return w.wrecks.wrecks.values().any(func(x): return x.get("spotted", false) or x["state"] in ["base", "repair", "parked", "slung"])
		"evac": return w.evac.announced
		"modifiers": return not w.modifiers.active.is_empty()
	return false
