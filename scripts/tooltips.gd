class_name Tooltips
extends RefCounted
## Every hover text of the menus, in one table for review (docs/ROADMAP2.md Q6b). UIs ask Tooltips.tip(id); a refusal ("needs 40 scrap")
## still wins over these where a button is disabled. Ids: tab_* base menu tabs, buy_* upgrades, build_* tools, job_* jobs,
## loadout_* hangar, wear_* / fleet_* / convoy_* / pick_* rows, title_* title screen, codex_* / key_* this screen.
## Items and modifiers keep their text next to their numbers (progression.gd ITEMS "desc" and "per_level", modifiers.gd TABLE "desc");
## item() and modifier() build the tooltip from those. Buildings hospital..relay: the lines are in buildings2.gd TIPS.

const Mods := preload("res://scripts/modifiers.gd")
const TIPS := {
	# --- base menu: tabs and header
	"tab_BUILD": "Upgrades for the base and the buildings you place on the map.",
	"tab_WORKERS": "Give your people jobs. Idle hands eat food and do nothing.",
	"tab_HANGAR": "Loadout, guns, fitted items and the state of the heli.",
	"tab_CONVOY": "Trucks from the motor pool run supplies and rescues for you.",
	"toggle": "Fold the menu away to use the door gun from the pad. Same key opens it again.",
	"status_fold": "Fold the status panel to its header (it folds by itself when the menu needs the room).",
	# --- base menu: upgrades
	"buy_turrets": "Another auto turret on the fence ring. Shoots whatever gets close.",
	"buy_fuel": "A bigger fuel depot, and a bigger tank in the heli.",
	"buy_armory": "More ammo for the heli and the depot, and a free rifle every day.",
	"buy_workshop": "Breaks salvage down into scrap. Levels 2, 3 and 4 add a gun, system and module slot.",
	"buy_repair": "Patch the base hull with scrap. Cheaper than losing the base.",
	# --- base menu: things to place
	"build_sandbag": "Sandbag post. Militia man it in assaults and zombies stop at it.",
	"build_wire": "Barbed wire. Slows zombies and cuts them while they crawl through.",
	"build_barracks": "Beds for four more people. No bed, no full work rate.",
	"build_clinic": "Two beds for the wounded. A Medic heals them faster.",
	"build_generator": "Makes power for the base. Burns fuel every day.",
	"build_well": "Fresh water every day. Needs a river or lake close by.",
	"build_watchtower": "A post on the fence with long reach. Put a militia on it.",
	"build_motor_pool": "Garage for convoy trucks. Opens the CONVOY tab.",
	"build_demolish": "Mark houses, hedges and fences for the build crew. They tear them down and you get scrap.",
	"build_radio": "Military contact. Needs an Engineer and electronics.",
	"build_airstrip": "A strip for evacuation flights. R turns it before you place it.",
	"build_hospital": "Add-on to a built clinic: four more beds, patients heal faster.",
	"build_greenhouse": "Grows food without farmland. Drinks water, so keep the well running.",
	"build_forge": "Mechanics turn scrap into metal and metal into parts here.",
	"build_bunker": "Saves the survivors once when the base is breached. Spent after that.",
	"build_relay": "One radio relay. Reveals more of the map and warns of raids early.",
	"perimeter": "Push the fence out. Build workers put up the next ring, stage by stage.",
	# --- base menu: workers
	"job_fuel": "Fuel crew: refines +20 fuel a day for the depot.",
	"job_ammo": "Ammo crew: presses +60 ammo a day.",
	"job_repair": "Repair crew: patches +40 base hull a day.",
	"job_militia": "Militia: needs a rifle each. Takes some damage off the base and mans posts in assaults.",
	"job_farm": "Farmers: +6 food a day each.",
	"job_build": "Build crew: works through your blueprints. Sandbag takes 20 seconds a worker.",
	"job_medic": "Medics: patch 20 hull whenever you land, and clear the clinic faster.",
	"job_water": "Water crew: +15 water a day. Needs a river or lake within 40 m.",
	"job_workshop": "Workshop crew: breaks down 12 pieces of salvage a day. Needs the Workshop upgrade.",
	"job_forge": "Forge crew: six units a day, scrap to metal and metal to parts. Needs a Forge.",
	"job_minus": "One fewer on this job. They go back to idle.",
	"job_plus": "One more on this job, taken from the idle people.",
	"unassign": "Send everybody back to idle. Pinned people stay put.",
	"pick_filter": "Which people the list below shows.",
	"pick_sort": "How the list below is ordered.",
	"pick_pin": "Pin to a job (Auto: assigned by skill).",
	"pinned": "Pinned: stays on this job (injured: off duty until healed).",
	"person": "Show this person: skill, trait and mood.",
	# --- base menu: hangar
	"loadout_seats": "Seats in the cabin. More seats, more people per trip, more weight.",
	"loadout_fuel_tank": "Bigger tank for longer sorties. Costs weight points.",
	"loadout_ammo_feed": "More belts on board. Costs weight points.",
	"loadout_armor": "Armour plates. Less damage taken, more weight.",
	"loadout_minus": "Take one level off. Free while you sit on the pad.",
	"loadout_plus": "Add one level. Weight points are limited, and over the limit the heli slows down.",
	"wear_repair": "Order a repair. It uses parts from the workshop and the repair crew's time.",
	"wear_done": "Like new. Nothing to repair.",
	"stow": "Move this gun to the bay. The heli always keeps one.",
	"mount": "Put this gun on a free hardpoint.",
	"scrap": "Scrap the item for half its card value. The slot frees up.",
	"fleet_repair": "Start the repair project. Costs metal, parts, electronics and key parts, plus work days.",
	"fleet_switch": "Fly this heli. The one you fly now stays parked at the base.",
	# --- base menu: convoy
	"convoy_truck": "Build a truck in the motor pool.",
	"convoy_dest": "Where the convoy drives to.",
	"convoy_driver": "Who drives the convoy.",
	"convoy_escort": "Armed escorts for the trip.",
	"convoy_send": "Send the convoy. Bandits like convoys.",
	# --- title screen
	"title_continue": "Pick up the saved run where you left it.",
	"title_restore": "Your saved run was backed up online. Needs the online login of this profile.",
	"title_start": "Start a new run in a fresh world.",
	"title_hangar": "The parts and guns on record: what you unlocked and what is still locked.",
	"title_tutorial": "A short guided run through flying, shooting and rescuing.",
	"title_profiles": "Switch, add or delete pilots. Each has their own unlocks.",
	"title_board": "The best runs, ranked by score.",
	"title_backup": "Export, import and cloud backup of your save.",
	"title_daily": "Today's daily: the same world, modifiers and heli for every pilot. The first start of the day is ranked, later ones are practice. Needs the server.",
	"title_continue_daily": "Pick up the saved daily run. Your normal run is kept apart.",
	"title_heli": "Cycles the helis you have repaired in earlier runs. Repair a wreck of another type to fly it from the start.",
	# --- ESC menu, key screen, help screen
	"menu_keys": "Change any key or mouse button. Conflicts show in red.",
	"menu_help": "Controls and the codex.",
	"menu_skip": "Skip the tutorial and play on.",
	"key_binding": "Click, then press the new key or mouse button. Right-click removes it.",
	"key_add": "Add one more key or mouse button to this action.",
	"keys_reset": "Every action back to its default key.",
	"keys_back": "Back to the ESC menu.",
	"codex_close": "Close the help screen.",
	"trade_buy": "Pay scrap for one unit. Every purchase raises that price a little; it falls back over the days.",
	"trade_sell": "Sell a batch of surplus. The rate is poor and drops with every sale. The base keeps a few days of supplies.",
	"trade_close": "Leave the trade window. The village keeps today's offer.",
	"codex_controls": "Every key as it is set right now.",
	"codex_enemies": "What you met out there.",
	"codex_buildings": "What you built and what it does.",
	"codex_items": "Guns, systems and modules.",
	"codex_systems": "How the base, the radio and the world work.",
}


## Text for `id`; "" (and a warning) for an id missing from the table, so a typo shows up in the tests instead of as an empty tooltip.
static func tip(id: String) -> String:
	if not TIPS.has(id):
		push_warning("no tooltip: " + id)
		return ""
	return TIPS[id]


## Tooltip of a BUILD_INFO tool: the table entry, or the line a building file brings along.
static func building(kind: String) -> String:
	return Buildings3.TIPS.get(kind, Buildings2.TIPS.get(kind, TIPS.get("build_" + kind, "")))


## "Slow heavy shells that punch through.\nLv 1: ...\nLv 5: ..."
static func item(id: String) -> String:
	var it: Dictionary = Progression.ITEMS[id]
	return "%s\nLv 1: %s\nLv 5: %s" % [it["desc"], it["per_level"][0], it["per_level"][4]]


static func modifier(id: String) -> String:
	var m: Dictionary = Mods.TABLE[id]
	return "%s. Score x%.2f." % [m["desc"], m["factor"]]
