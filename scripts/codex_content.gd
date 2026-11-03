class_name CodexContent
extends RefCounted
## Every F1 codex entry of the base game in ONE table (docs/ROADMAP2.md Q11), so the texts can be reviewed in one place.
## Row: [category, id, title, text]. Ids are unique over all categories; prefixes: z_ infected, b_ bandits, bld_ buildings,
## item_ heli items and guns, heli_ heli types, sys_ systems. onboarding.gd unlocks an entry on the first encounter.
## Later packages may still add rows with Codex.register(); the bosses (Q12) live here too.

const ROWS := [
	# --- Enemies: infected
	["Enemies", "z_shambler", "Shambler", "Slow and tough. Follows noise and light. Alone he is nothing, forty of them are a wall."],
	["Enemies", "z_runner", "Runner", "Fast and brittle. Gets to the heli before the door gun has warmed up. Shoot early."],
	["Enemies", "z_brute", "Brute", "Hits like a truck and soaks lead. Keep away from the line, or he walks through it."],
	["Enemies", "z_brute_armored", "Armored Brute", "Plated in front. Hit him from behind, or bring something that punches through."],
	["Enemies", "z_screamer", "Screamer", "Does not bite. His scream calls every zombie in earshot. Shoot him first."],
	["Enemies", "z_spitter", "Spitter", "Spits acid from range and leaves pools that burn. Keep moving, stay out of the puddles."],
	["Enemies", "z_crawler", "Crawler", "Low and quick. Slips under barbed wire and is hard to hit. Mind your flanks."],
	["Enemies", "z_bloater", "Bloater", "Swollen with gas. Bursts when he dies and the cloud hurts. Pop him at range."],
	["Enemies", "z_boss", "Blood Moon Horror", "Comes with every blood moon. Huge, slow, brutal. The night does not end until he is dead."],
	["Enemies", "z_nest", "Nest", "A hive that keeps spawning infected. Burn it out before you land anywhere near."],
	# --- Enemies: bosses (Q12, scripts/bosses.gd; Bosses.codex_id)
	["Enemies", "z_matriarch", "The Matriarch", "A bloated brood mother. She rears up and screeches before she spawns runners and crawlers, so shoot her while she is busy. Wounded, she flees to heal, then comes back with a bigger brood."],
	["Enemies", "z_juggernaut", "The Juggernaut", "Welded plates all round: only the red fuel pack on its back is soft. It turns slowly, so circle it. When it lowers its head, leave the red lane: it rams houses, sandbags and a landed heli, and a crash leaves it dazed."],
	["Enemies", "z_hive", "The Hive", "A nest in a power plant or stadium. It throbs before every wave and calls them until it is destroyed. Wounded, it brings spitters, bloaters and armoured brutes. Destroying it yields electronics."],
	# --- Enemies: bandits
	["Enemies", "b_rifle", "Bandit Rifleman", "Takes cover and shoots the heli. Hits less when you are fast, more when you are parked."],
	["Enemies", "b_mg", "MG Nest", "Does not move, fires long bursts. Come from the side and keep your speed up."],
	["Enemies", "b_rpg", "RPG Gunner", "Aims for a second and a half, a red line shows it. Turn hard, or drop flares and smoke."],
	["Enemies", "b_technical", "Technical", "A pickup with a mounted gun that hunts on the roads. Fast, sturdy, and it brings friends."],
	["Enemies", "b_rival", "Rival Warlord", "A named bandit leader who remembers you: cleared camps, fast flying, your favourite gun. He raids convoys and outposts, escapes when hurt, returns stronger, and ends in a captured gunship."],
	["Enemies", "b_gunship", "Gunship", "The rival warlord's captured heli. It circles at the edge of your favourite gun's reach and fires bursts and rockets. Flares pull the rockets off, and it shies away from them."],
	["Enemies", "z_alpha", "The Alpha", "A named matriarch that learned. She hunts the heli, raids convoys and outposts, then leads an assault; against much wire she brings crawlers and spitters. Hurt, she escapes and returns stronger."],
	["Enemies", "b_warlord", "The Warlord", "He holds the big bandit camps, with bodyguards. His mortar shells a LANDED heli: a red circle shows where, lift off before it lands. Kill him and the bodyguards scatter."],
	# --- Buildings
	["Buildings", "bld_pad", "Landing Pad", "Your home plate. Land here to unload, refuel, rearm and open the base menu."],
	["Buildings", "bld_sandbag", "Sandbag Post", "Zombies stop at it. Militia man it during assaults. Build workers lay one in 20 seconds."],
	["Buildings", "bld_wire", "Barbed Wire", "Slows zombies and cuts them while they crawl through. Crawlers ignore it."],
	["Buildings", "bld_barracks", "Barracks", "Beds for four more people. No bed, no full work rate."],
	["Buildings", "bld_clinic", "Field Clinic", "Two beds for the wounded. A Medic heals them faster. Untreated wounds kill."],
	["Buildings", "bld_generator", "Generator", "Power for lights and machines. Burns base fuel every day."],
	["Buildings", "bld_well", "Well", "Water for the whole base. Dry wells mean thirsty people."],
	["Buildings", "bld_watchtower", "Watchtower", "A post on the fence with long reach. Raises the number of outposts you can hold."],
	["Buildings", "bld_motor_pool", "Motor Pool", "Garage for convoy trucks. Opens the CONVOY tab."],
	["Buildings", "bld_perimeter", "Perimeter", "Pushes the fence out. Build workers put up the next ring, stage by stage."],
	["Buildings", "bld_radio", "Radio Station", "Military contact. Needs an Engineer and electronics. The first step to evacuation."],
	["Buildings", "bld_airstrip", "Airstrip", "A long strip for the evacuation flight. Needs clear ground inside the fence."],
	["Buildings", "bld_hospital", "Field Hospital", "Add-on to a clinic: four more beds, and patients heal faster."],
	["Buildings", "bld_greenhouse", "Greenhouse", "Grows food without farmland, but drinks water. No water, no harvest."],
	["Buildings", "bld_forge", "Forge", "Mechanics turn scrap into metal and metal into parts. Never spends your last scrap."],
	["Buildings", "bld_bunker", "Bunker", "Saves the survivors once when the base is breached, then it is spent."],
	["Buildings", "bld_relay", "Radio Relay", "Reveals more of the map and warns of bandit raids a day early."],
	["Buildings", "bld_fortress", "Fortress Wall", "Late game. Sandbags become walls with double hit points. One per base."],
	["Buildings", "bld_flak", "Flak Emplacement", "Late game. Shoots down rockets, hurts the gunship and bursts on big waves. Eats ammo and 12 scrap a day."],
	["Buildings", "bld_command", "Command Post", "Late game. Missions pay more, one more can be open, and rival attacks are radioed ahead. 8 scrap a day."],
	["Buildings", "bld_vault", "Supply Vault", "Late game. Fuel and ammo stores hold half as much again, and a base breach costs half as much."],
	# --- Items: door guns and hardpoints
	["Items", "item_mg", "Door MG", "Reliable all-rounder. At level 5 it fires twin tracers."],
	["Items", "item_minigun", "Minigun", "A hose of lead. Spread grows while you hold the trigger, and it eats ammo."],
	["Items", "item_autocannon", "Autocannon", "Slow heavy shells that punch through the first target. Explosive at level 5."],
	["Items", "item_shotgun", "Flak Gun", "Pellet blast with 20 metres of reach. Good for runners at the door."],
	["Items", "item_rockets", "Rocket Pod", "Splash damage on impact. Five ammo a rocket, so pick your targets."],
	["Items", "item_railgun", "Railgun", "One bolt through everything in the line. Brutes hate it."],
	["Items", "item_scatter", "Scatter Gun", "Ten wide pellets. Deadly up close, almost useless at range."],
	["Items", "item_flamer", "Flamethrower", "A short fire stream. Burning zombies keep taking damage and pass it on at level 5."],
	["Items", "item_grenade", "Grenade Launcher", "Lobs a shell that bursts where you aim, over walls and over heads."],
	["Items", "item_marksman", "Precision Rifle", "One slow, hard shot through two targets. Aims for the head."],
	["Items", "item_sonic", "Sonic Cannon", "A shockwave that stuns and shoves a whole cone. Bandits shrug it off."],
	["Items", "item_net", "Net Launcher", "Roots zombies in the burst for two seconds. Bosses shrug it off."],
	# --- Items: systems
	["Items", "item_searchlight", "Searchlight", "A light cone ahead. At night zombies in it slow down and points of interest show up."],
	["Items", "item_flares", "Flares", "A burning flare whose noise pulls zombies away. Also pulls rockets off course."],
	["Items", "item_loudspeaker", "Loudspeaker", "Blares noise that drags zombies to you and away from a settlement."],
	["Items", "item_winch", "Winch", "Hover low over survivors and hoist them aboard without landing."],
	["Items", "item_cogunner", "Co-gunner", "A second gunner shoots the nearest zombie in any direction. Uses little ammo."],
	["Items", "item_medic", "Medic", "Patches the hull while you fly."],
	["Items", "item_supply", "Supply Drop", "Command drops a crate on your position now and then."],
	["Items", "item_thermal", "Thermal Sight", "At night, zombies and bandits near you glow in heat view."],
	["Items", "item_smoke", "Smoke Launcher", "Pops a screen when you are shot at. Rockets lose their lock, zombies slow down."],
	# --- Items: modules
	["Items", "item_engine", "Engine", "Turbine tuning: more top speed."],
	["Items", "item_plating", "Armor", "Bolt-on plates: more armour. Level 5 halves zombie ram damage."],
	["Items", "item_leanburn", "Lean Burn", "A leaner mixture: more fuel efficiency."],
	["Items", "item_ammobelts", "Ammo Belts", "Extra belts in the cabin: more max ammo."],
	["Items", "item_training", "Gunnery", "Gunner drills: a faster fire rate."],
	["Items", "item_hardcore", "Hard Core", "Hardened rounds: bullets pierce and fly faster."],
	["Items", "item_cabin", "Cabin", "Refit for passengers: more seats and faster boarding."],
	["Items", "item_veteran", "Veteran", "Experienced crew: more XP from everything."],
	["Items", "item_scavenger", "Scavenger", "The salvage crew picks the dead clean: more scrap from kills."],
	["Items", "item_optics", "Optics", "Gun sights: more range for every gun."],
	["Items", "item_extratank", "Extra Tank", "An auxiliary fuel cell in the cabin."],
	["Items", "item_heavyplates", "Heavy Plates", "Thick armour that weighs you down: slower, much tougher."],
	# --- Items: heli types
	["Items", "heli_huey", "Huey", "The all-rounder. Four seats, one hardpoint, no surprises."],
	["Items", "heli_little_bird", "Little Bird", "A fast, quiet scout. Two seats, thin armour."],
	["Items", "heli_black_hawk", "Black Hawk", "Gunship transport. Eight seats and two hardpoints."],
	["Items", "heli_chinook", "Chinook", "Heavy lift. Fourteen seats and the best wreck sling, but slow."],
	["Items", "heli_hind", "Hind", "A gunship with three hardpoints and heavy armour. Found only at military sites."],
	# --- Systems
	["Systems", "sys_save", "Saving", "The run saves itself on landing and now and then. Dying ends it for good: no reloads, only what you unlocked stays."],
	["Systems", "sys_noise", "Noise", "Gunfire and the rotor draw zombies. A busy gun on the ground calls the whole neighbourhood."],
	["Systems", "sys_night", "Night", "At night they see you less but you see them less too. Light and heat sights pay for themselves."],
	["Systems", "sys_cards", "Level-up cards", "Each level offers cards: new items or upgrades. Reroll, skip or banish what you do not want."],
	["Systems", "sys_food_water", "Food & water", "Every person eats and drinks daily. Run dry and people fall sick; after three days in a row they walk out. Farms, wells, greenhouses."],
	["Systems", "sys_injury", "Injuries", "Hurt survivors cannot work. A clinic bed and a Medic heal them. Untreated they can die."],
	["Systems", "sys_morale", "Morale", "Deaths, hunger and losses drag it down; power, beds and held assaults lift it. Low morale slows work and may make people walk out."],
	["Systems", "sys_assault", "Assaults", "Every few days a horde hits the base at dusk. Sandbags, wire, militia and your door gun hold the line."],
	["Systems", "sys_wear", "Wear", "Rotor, engine, gearbox and gun wear out as you fly and fire. Worn parts jam, fail or send you into autorotation. Repair them at base."],
	["Systems", "sys_missions", "Radio missions", "Command offers jobs with a clock: rescues, escorts, camps. Open the list with J. They pay scrap, XP and sometimes a specialist."],
	["Systems", "sys_bandits", "Bandits", "They hold camps, ride the roads and raid villages, outposts and your base. Their rifles end up in your armory."],
	["Systems", "sys_outposts", "Outposts", "Hold a gas station, checkpoint or radio mast with a militia crew. Refuel and rearm in the field. Raiders will test it."],
	["Systems", "sys_villages", "Villages", "Protect a survivor settlement and it becomes an ally that trades food and water. Neglect it and it falls."],
	["Systems", "sys_convoys", "Convoys", "Trucks from the motor pool loot far towns by road. A driver, optional escorts, a risk of ambush."],
	["Systems", "sys_wrecks", "Wrecks", "Downed helis can be hooked, flown home and repaired in the hangar with parts, electronics and key parts."],
	["Systems", "sys_evac", "Evacuation", "From day 15 the military answers. A radio station, an airstrip and one last siege get everybody out. It ends the run in victory."],
	["Systems", "sys_modifiers", "Modifiers", "Optional handicaps picked before a run. Each one raises your leaderboard score."],
]


## Registers every row once (a reloaded main scene calls this again).
static func register_all() -> void:
	for r in ROWS:
		if not Codex.entries.has(r[1]):
			Codex.register(r[0], r[1], r[2], r[3])
