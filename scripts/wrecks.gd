extends Node2D
## Heli wrecks, the sling hook, the HANGAR repair project and the fleet (docs/ROADMAP.md P15). main.gd keeps it as `wrecks`,
## it saves itself (hook "wrecks"; a run saved before P15 starts with the stock Huey and no wrecks found yet).
## Wrecks: airfields, checkpoints and airliner crash sites (chunks.sites_near) hold one by a fixed roll per site (HeliTypes.SITES:
## odds, type, condition 30-90 %), found as the heli comes within SCAN_RADIUS; a record is kept once rolled, so the world stays
## order-independent.
## Sling: hover over a wreck (within HOOK_RADIUS, under HOOK_MAX_SPEED of top speed) and press G; after HOOK_SECONDS of steady
## hovering it is hooked. With a load: top speed x HeliTypes sling (0.5, Chinook 0.85), fuel x SLING_FUEL, no landing, the load
## swings on a spring rope (SPRING, DAMP, TUG pulls the heli back), trees snag it, zombies close by and bandits in range
## damage it (at 0 % it breaks apart). G again lets go: inside the base fence it is set down for repair, elsewhere it stays.
## Repair (HANGAR, scripts/fleet_ui.gd): salvage and key parts up front, then work days by Mechanics on Repair duty (Engineers
## x ENGINEER_MULT). Repaired, the heli is parked at the base; the HANGAR switches the active one. Items, weapons, loadout, wear and
## hull stay with each heli. The first repair of each type unlocks it as a start heli (meta "start_helis").
## Key parts (rotor head, turbine, avionics): missions (missions.gd calls add_key) and one roll per military landmark
## (checkpoint, airfield) when the heli lands within KEY_SITE_RADIUS of it.

const HeliTypes := preload("res://scripts/heli_types.gd")
const People := preload("res://scripts/people.gd")
const T := preload("res://scripts/chunk_manager.gd").T
const SCAN_EVERY := 1.0
const SCAN_RADIUS := 1400.0
const SPOT_RADIUS := 420.0 # the crew calls out a wreck this close
const COND_MIN := 0.3
const COND_MAX := 0.9
const HOOK_RADIUS := 28.0
const HOOK_MAX_SPEED := 0.2 # share of heli.MAX_SPEED
const HOOK_SECONDS := 4.0
const SLING_FUEL := 2.0
const ROPE := 36.0 # px, slack below this
const ROPE_MAX := 72.0
const SPRING := 6.0
const DAMP := 0.9
const TUG := 0.3 # share of the rope force that drags on the heli
const SNAG_LOAD := 0.3 # load speed kept when it hits trees
const SNAG_HELI := 0.8 # heli speed kept
const SNAG_DAMAGE := 0.02
const SNAG_CD := 1.5
const ZOMBIE_REACH := 20.0
const ZOMBIE_DPS := 0.02 # condition per second per zombie at the load
const BANDIT_RANGE := 260.0
const BANDIT_DPS := 0.008 # per bandit in range
const COST_SCALE := 1.5 # project cost x (COST_SCALE - condition) / (COST_SCALE - 0.5): x1.2 at 30 %, x0.6 at 90 %
const DAYS_MIN := 10
const DAYS_MAX := 20
const ENGINEER_MULT := 2.0
const KEY_SITE_RADIUS := 220.0
const KEY_SITE_ODDS := 0.6
const PARK_OFFSET := Vector2(-56, 40) # a heli parked by the pad when the active one takes off from it

var wrecks := {} # uid -> {type, pos, rot, cond 0..1, keys: [key part ids], state, progress, days, heli}
# state: "site" (out there), "slung", "base" (inside the fence, waiting), "repair", "parked" (repaired), "active", "lost"
var active := "start" # uid of the heli flown now; "start" is the run's first one
var keys := {"rotor_head": 0, "turbine": 0, "avionics": 0}
var looted := {} # military site uid -> true: its key part roll is done
var hook := "" # uid being hooked (hook_t > 0) or slung
var hook_t := 0.0
var load_pos := Vector2.ZERO
var load_vel := Vector2.ZERO
var _scan := 0.0
var _seen := {} # site uids rolled this session (empty sites are rolled again identically after a load)
var _snag := 0.0
var _nodes := {} # uid -> Sprite2D


func _ready() -> void:
	z_index = 2
	wrecks["start"] = {"type": "huey", "pos": Vector2.ZERO, "rot": 0.0, "cond": 1.0, "keys": [], "state": "active", "progress": 0.0, "days": 0, "heli": {}}
	Save.register("wrecks", save_state, load_state)
	Game.heli.landed_changed.connect(_on_landed) # main.gd adds the heli first


func type_id(uid := active) -> String:
	return wrecks[uid]["type"] if wrecks.has(uid) else "huey"


func htype() -> Dictionary:
	return HeliTypes.get_type(type_id())


## New run (main.gd, title): the start heli's type, if this profile has unlocked it.
func set_start_type(id: String) -> void:
	if id in start_types():
		wrecks["start"]["type"] = id
		Game.recompute()
		Game.fuel = Game.max_fuel
		Game.ammo = Game.max_ammo
	_look()


## Types this profile may start in: the Huey and every type it has repaired once.
static func start_types() -> Array:
	var out := ["huey"]
	for id in str(Game.meta.get("start_helis", "")).split(",", false):
		if HeliTypes.TYPES.has(id) and not id in out:
			out.append(id)
	return out


func _process(delta: float) -> void:
	if not Game.running or Game.heli == null:
		return
	if Input.is_action_just_pressed("hook") and not Game.world.ui_open:
		toggle_hook()
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_EVERY
		scan(Game.heli.position)
	if hook != "":
		_hooking(delta) if hook_t > 0.0 else _sling(delta)
	_repairs(delta)
	queue_redraw()


## Rolls the wreck sites within SCAN_RADIUS of `pos`.
func scan(pos: Vector2) -> void:
	for kind in HeliTypes.SITES:
		for s in Game.world.chunks.sites_near(pos, SCAN_RADIUS, kind):
			if not _seen.has(s.uid):
				_seen[s.uid] = true
				if not wrecks.has(s.uid):
					_roll(s)
	for uid in wrecks:
		var w: Dictionary = wrecks[uid]
		if w["state"] == "site" and not w.get("spotted", false) and w["pos"].distance_to(pos) < SPOT_RADIUS:
			w["spotted"] = true
			Game.radio("Pilot: downed %s down there, %d %% intact. Hover over it and hook it (G)." % [HeliTypes.TYPES[w["type"]]["name"], 100.0 * w["cond"]])
		_sync(uid)


func _roll(s: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed, s.uid, "wreck"])
	var site: Dictionary = HeliTypes.SITES[s.kind]
	if rng.randf() >= site["odds"]:
		return
	var w: Dictionary = site["types"]
	var roll: float = rng.randf() * w.values().reduce(func(a, b): return a + b)
	var type: String = w.keys()[0]
	for k in w:
		roll -= w[k]
		if roll < 0.0:
			type = k
			break
	var parts: Array = HeliTypes.KEY_PARTS.keys()
	var need := []
	for i in HeliTypes.TYPES[type]["keys"]:
		need.append(parts.pop_at(rng.randi() % parts.size()))
	wrecks[s.uid] = {"type": type, "pos": s.pos + Vector2(rng.randf_range(50.0, 90.0), 0).rotated(rng.randf() * TAU), "rot": rng.randf() * TAU,
		"cond": rng.randf_range(COND_MIN, COND_MAX), "keys": need, "state": "site", "progress": 0.0, "days": 0, "heli": {}}


# --- sling ------------------------------------------------------------------------------------------------

func slung() -> bool:
	return hook != "" and hook_t <= 0.0


## G: lower the hook over a wreck, cancel it, or let go of the load. Returns what the crew says ("" if nothing happened).
func toggle_hook() -> String:
	var h: Node2D = Game.heli
	var msg := ""
	if slung():
		msg = release()
	elif hook != "":
		hook = ""
		msg = "Crew: hook's up."
	elif h.landed or h.pending != 0:
		msg = "Crew: we need to be in the air for the hook."
	else:
		var uid := wreck_below(h.position)
		if uid == "":
			msg = "Crew: no wreck under us."
		elif h.vel.length() > HOOK_MAX_SPEED * h.MAX_SPEED:
			msg = "Crew: too fast, slow to a hover over the wreck."
		else:
			hook = uid
			hook_t = HOOK_SECONDS
			msg = "Crew: hook going down. Hold her steady over the %s." % HeliTypes.TYPES[wrecks[uid]["type"]]["name"]
	Game.radio(msg)
	return msg


## The wreck at `pos` (within HOOK_RADIUS) that can be hooked, "" if none.
func wreck_below(pos: Vector2) -> String:
	for uid in wrecks:
		var w: Dictionary = wrecks[uid]
		if w["state"] in ["site", "base"] and w["pos"].distance_to(pos) <= HOOK_RADIUS:
			return uid
	return ""


func _hooking(delta: float) -> void:
	var h: Node2D = Game.heli
	if h.landed or h.vel.length() > HOOK_MAX_SPEED * h.MAX_SPEED or wrecks[hook]["pos"].distance_to(h.position) > HOOK_RADIUS:
		hook = ""
		Game.radio("Crew: the hook slipped off, hold her steady over it.")
		return
	hook_t -= delta
	if hook_t <= 0.0:
		hook_t = 0.0
		wrecks[hook]["state"] = "slung"
		load_pos = wrecks[hook]["pos"]
		load_vel = Vector2.ZERO
		Game.radio("Crew: she's hooked! Heavy load, take it slow. G lets go (inside the fence for the hangar).")


func _sling(delta: float) -> void:
	var h: Node2D = Game.heli
	var w: Dictionary = wrecks[hook]
	var d := h.position - load_pos
	var f := d.normalized() * maxf(0.0, d.length() - ROPE) * SPRING
	load_vel += (f - load_vel * DAMP) * delta
	load_pos += load_vel * delta
	if not h.landed: # a landed heli is not dragged by its load
		h.vel -= f * TUG * delta
	if h.position.distance_to(load_pos) > ROPE_MAX:
		load_pos = h.position - (h.position - load_pos).normalized() * ROPE_MAX
	w["pos"] = load_pos
	_snag -= delta
	if _snag <= 0.0 and Game.world.chunks.tile_at(load_pos) in [T.FOREST, T.TREE_EDGE]:
		_snag = SNAG_CD
		load_vel *= SNAG_LOAD
		h.vel *= SNAG_HELI
		w["cond"] -= SNAG_DAMAGE
		HitFx.shake(2.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.is_in_group("bandits"):
			if e.global_position.distance_to(load_pos) <= BANDIT_RANGE:
				w["cond"] -= BANDIT_DPS * delta
		elif e.global_position.distance_to(load_pos) <= ZOMBIE_REACH:
			w["cond"] -= ZOMBIE_DPS * delta
	if w["cond"] <= 0.0:
		w["state"] = "lost"
		hook = ""
		Game.radio("Crew: the wreck broke apart on the hook. Nothing left to save.")
	_sync(hook if hook != "" else "")


## G with a load: set it down inside the fence (ready for the HANGAR) or leave it where it is.
func release() -> String:
	var w: Dictionary = wrecks[hook]
	hook = ""
	w["pos"] = load_pos
	var home: bool = Game.base_founded and load_pos.distance_to(Game.world.base.global_position) <= Game.base_radius
	w["state"] = "base" if home else "site"
	return "Hangar: wreck is down inside the wire. Repair project in the HANGAR tab." if home else "Crew: load released. It stays here, we can come back for it."


func speed_factor() -> float:
	return htype()["sling"] if slung() else 1.0


func fuel_factor() -> float:
	return SLING_FUEL if slung() else 1.0


# --- key parts --------------------------------------------------------------------------------------------

## A key part for the repairs: `id`, or a random one. Returns its id.
func add_key(id := "") -> String:
	if not keys.has(id):
		id = keys.keys().pick_random()
	keys[id] += 1
	return id


func _on_landed(landed: bool) -> void:
	if not landed:
		return
	for kind in ["checkpoint", "airfield"]:
		for s in Game.world.chunks.sites_near(Game.heli.position, KEY_SITE_RADIUS, kind):
			if looted.has(s.uid):
				continue
			looted[s.uid] = true
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([Game.seed, s.uid, "key"])
			if rng.randf() < KEY_SITE_ODDS:
				var id := add_key(keys.keys()[rng.randi() % keys.size()])
				Game.radio("Crew: pulled a %s out of the %s. Key part for a heli repair." % [HeliTypes.KEY_PARTS[id], kind])


# --- repair project -----------------------------------------------------------------------------------------

## {metal, parts, electronics, keys: [ids], days} of the repair of wreck `uid`.
func cost(uid: String) -> Dictionary:
	var w: Dictionary = wrecks[uid]
	var t: Dictionary = HeliTypes.TYPES[w["type"]]
	var s: float = (COST_SCALE - w["cond"]) / (COST_SCALE - 0.5) # the table holds the cost at 50 %
	var out := {"keys": w["keys"], "days": clampi(roundi(t["days"] * s), DAYS_MIN, DAYS_MAX)}
	for k in t["cost"]:
		out[k] = roundi(t["cost"][k] * s)
	return out


## Why the repair of `uid` cannot start, "" if it can.
func repair_refusal(uid: String) -> String:
	if wrecks[uid]["state"] != "base":
		return "the wreck must sit inside the fence"
	var c := cost(uid)
	for k in ["metal", "parts", "electronics"]:
		if Game.salvage[k] < c[k]:
			return "needs %d %s, you have %d" % [c[k], k, Game.salvage[k]]
	var need := {}
	for k in c["keys"]:
		need[k] = need.get(k, 0) + 1
	for k in need:
		if keys[k] < need[k]:
			return "needs a %s (key part: missions, military landmarks)" % HeliTypes.KEY_PARTS[k]
	return ""


## HANGAR: pay and start the project. Returns why it was refused, "" if started.
func start_repair(uid: String) -> String:
	var why := repair_refusal(uid)
	if why != "":
		return why
	var c := cost(uid)
	for k in ["metal", "parts", "electronics"]:
		Game.salvage[k] -= c[k]
	for k in c["keys"]:
		keys[k] -= 1
	var w: Dictionary = wrecks[uid]
	w["state"] = "repair"
	w["progress"] = 0.0
	w["days"] = c["days"]
	Game.radio("Hangar: %s on the stands. %d work days for the mechanics." % [HeliTypes.TYPES[w["type"]]["name"], c["days"]])
	return ""


## Work days per day from the people on Repair duty: Mechanics x1, Engineers x ENGINEER_MULT, others nothing.
func mechanic_rate() -> float:
	var n := 0.0
	for p in Game.people:
		if p["job"] == "repair" and not p["aboard"] and not p["injured"] and People.matches(p, "repair"):
			n += People.rate(p, Game.is_night()) * (ENGINEER_MULT if p["skill"] == "engineer" else 1.0)
	return n * (Game.work_eff() if Game.base_founded else 0.0)


func _repairs(delta: float) -> void:
	var rate := mechanic_rate() * delta / Game.DAY_SECONDS
	for uid in wrecks:
		var w: Dictionary = wrecks[uid]
		if w["state"] != "repair":
			continue
		w["progress"] += rate
		if w["progress"] >= w["days"]:
			finish_repair(uid)


func finish_repair(uid: String) -> void:
	var w: Dictionary = wrecks[uid]
	w["state"] = "parked"
	w["heli"] = {"items": {"mg": 1}, "weapons": ["mg"], "weapon": "mg", "loadout": {"seats": 4, "fuel_tank": 1, "ammo_feed": 1, "armor": 0},
		"cond": {"rotor": 100.0, "engine": 100.0, "gearbox": 100.0, "gun": 100.0}, "hull": 1.0}
	var types := start_types()
	if not w["type"] in types:
		types.append(w["type"])
		Game.meta["start_helis"] = ",".join(types.slice(1))
		Game._save_meta()
		Game.radio("Command: %s cleared as a start heli for future runs." % HeliTypes.TYPES[w["type"]]["name"])
	Game.radio("Hangar: the %s is flying again. Pick her at the pad (HANGAR tab)." % HeliTypes.TYPES[w["type"]]["name"])
	_sync(uid)


# --- fleet ----------------------------------------------------------------------------------------------

## Helis that can be switched to: uids of parked ones.
func parked() -> Array:
	return wrecks.keys().filter(func(uid): return wrecks[uid]["state"] == "parked")


## Why the active heli cannot be swapped for `uid`, "" if it can.
func switch_refusal(uid: String) -> String:
	if not wrecks.has(uid) or wrecks[uid]["state"] != "parked":
		return "not a repaired heli"
	if not Game.heli.landed or not Game.world.wear.at_pad() or Game.world.wear.state != "" or hook != "":
		return "land on the base pad first"
	return ""


## HANGAR: park the active heli and take `uid`. Items, weapons, loadout, wear and hull swap with it.
func switch_to(uid: String) -> String:
	var why := switch_refusal(uid)
	if why != "":
		return why
	var wear: Node = Game.world.wear
	var cur: Dictionary = wrecks[active]
	var nxt: Dictionary = wrecks[uid]
	cur["heli"] = {"items": Game.heli_items.duplicate(), "weapons": Game.heli_weapons.duplicate(), "weapon": Game.weapon,
		"loadout": Game.loadout.duplicate(), "cond": wear.cond.duplicate(), "hull": Game.hp / Game.max_hp}
	cur["state"] = "parked"
	cur["pos"] = nxt["pos"] if nxt["pos"].distance_to(Game.heli.position) > 24.0 else Game.heli.position + PARK_OFFSET
	cur["rot"] = Game.heli.body.rotation
	var h: Dictionary = nxt["heli"]
	Game.heli_items = h["items"].duplicate()
	Game.heli_weapons.assign(h["weapons"])
	Game.weapon = h["weapon"]
	Game.loadout = h["loadout"].duplicate()
	wear.cond = h["cond"].duplicate()
	wear.orders.clear()
	nxt["state"] = "active"
	active = uid
	Game.recompute()
	Game.hp = h["hull"] * Game.max_hp
	_look()
	for k in wrecks:
		_sync(k)
	Game.radio("Pilot: switching to the %s." % htype()["name"])
	return ""


## The flown heli looks like its type.
func _look() -> void:
	var h: Node2D = Game.heli
	if h == null or h.body == null:
		return
	h.size = htype()["size"]
	h.body.self_modulate = htype()["tint"]


# --- drawing ------------------------------------------------------------------------------------------------

func _sync(uid: String) -> void:
	if not wrecks.has(uid):
		return
	var w: Dictionary = wrecks[uid]
	var n: Sprite2D = _nodes.get(uid)
	if n == null:
		n = Art.sprite("heli")
		add_child(n)
		_nodes[uid] = n
	n.visible = not w["state"] in ["active", "lost"]
	n.position = w["pos"]
	n.rotation = w["rot"]
	n.scale = Vector2.ONE * Art.SCALE * HeliTypes.TYPES.get(w["type"], HeliTypes.TYPES["huey"])["size"]
	n.z_index = 7 if w["state"] == "slung" else 0
	var t: Color = HeliTypes.get_type(w["type"])["tint"]
	n.modulate = t if w["state"] == "parked" else (t.darkened(0.3) if w["state"] == "repair" else Color(0.42, 0.4, 0.36))


func _draw() -> void:
	if hook == "" or Game.heli == null:
		return
	var h: Vector2 = Game.heli.position
	if hook_t > 0.0: # the hook going down: a closing ring
		draw_arc(wrecks[hook]["pos"], 6.0 + 16.0 * hook_t / HOOK_SECONDS, 0.0, TAU, 20, Color(0.96, 0.77, 0.18), 1.0)
		draw_line(h, h.lerp(wrecks[hook]["pos"], 1.0 - hook_t / HOOK_SECONDS), Color(0.15, 0.15, 0.12), 1.0)
	else:
		draw_line(h, load_pos, Color(0.15, 0.15, 0.12), 1.0)


## HUD line while the hook is busy, "" otherwise.
func alert() -> String:
	if hook == "":
		return ""
	if hook_t > 0.0:
		return "HOOKING %d s  hold steady" % ceili(hook_t)
	return "SLUNG LOAD %d %%  [G] release" % ceili(100.0 * wrecks[hook]["cond"])


func save_state() -> Dictionary:
	return {"wrecks": wrecks.duplicate(true), "active": active, "keys": keys.duplicate(), "looted": looted.duplicate(),
		"hook": hook, "hook_t": hook_t, "load_pos": load_pos, "load_vel": load_vel}


func load_state(d: Dictionary) -> void:
	wrecks = d["wrecks"]
	active = d["active"]
	keys.merge(d["keys"], true)
	looted = d["looted"]
	hook = d["hook"]
	hook_t = d["hook_t"]
	load_pos = d["load_pos"]
	load_vel = d["load_vel"]
	Game.recompute() # Game loaded before the heli type was known
	_look()
	for uid in wrecks:
		_sync(uid)
