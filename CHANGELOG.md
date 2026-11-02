# Changelog

The version lives in `project.godot` (`config/version`). Builds show it with commit and date ("v0.5.0 (a3aaf6b 2026-10-28)")
on the title screen and in the ESC menu. `tools/deploy_web.sh` tags the deployed commit `v<version>`: bump the version
for a new release. Versions before 0.5.0 were assigned afterwards from the git history and are not tagged.

## 1.0.0-beta.4 - 2026-11-02
- Onboarding: short radio-guided chapters (first assault, base & workers, missions, outposts & villages, bandits,
  convoys, wrecks, evacuation) start the first time you meet each system and wait for you to do each step. Skip one
  from its card, or turn them all off with "Tutorial hints & chapters" in the ESC menu. One-time hints pop up for an
  injured passenger, a jammed gun, an RPG, a spitter, the first night, low fuel and more. A chapter card steps aside
  while a radio event card is open.
- The F1 codex is filled: every enemy, building, item, heli and system has a page that unlocks when you first meet it
  (a run you continue logs everything it already has in one radio line).
- Four new bosses, each telegraphed with a red ring, lane or circle and a sound, with an HP bar and a second phase at
  half HP: the **Matriarch** (spawns broods, flees to heal), the **Juggernaut** (armoured except the fuel pack on its
  back, charges along a red lane; it only goes for the base while you are there), the **Hive** (in some power plants
  and stadiums away from your base, calls waves until destroyed) and the **Warlord** (holds a far bandit camp with
  bodyguards; his mortar shells a landed heli). Boss kills pay scrap, parts, electronics, rifles and morale.
- Radio events: from day 2 the radio brings a choice every few minutes (34 cards: traders, refugees, sickness,
  ultimatums, wounded soldiers ...). Answer with 1-3 or a click; the game does not pause, after 60 s the radio takes
  the default (never an option you cannot afford). Some answers start a chain days later; bandits who like you stop
  raiding the base. ESC menu: "Radio events" switch.
- Daily seed and weekly season: the DAILY panel on the title shows today's start heli and modifiers, the same for
  everyone. The first start of the day is ranked, later ones are practice. The daily has its own save slot next to
  your normal run (both can be restored from the cloud) and has no random radio events. The leaderboard has DAILY
  and SEASON (this week, all runs) tabs.

## 1.0.0-beta.3 - 2026-11-02
- New regions: the coast (sea, beaches, cliffs, dunes, fishing villages with boats) and the winter highland (snow,
  frosted woods, huts, frozen lakes you can land on; roads cross frozen rivers on bridges). New landmarks: hospital
  (medicine, medics, many infected), harbour (fuel, boats, sometimes bandits), stadium (a huge horde, big supply
  stash), power plant (a part that halves the generator's fuel; the HUD and base menu show the lower burn), ski lift ruin.
- **Runs from older versions cannot be continued:** the world generator changed, so the same seed now makes a
  different world and a run saved with an older version is discarded. Profiles, unlocks and the leaderboard stay.
- UI scale (ESC menu, 90-150 %): the HUD, menus and dialogs grow or shrink together and keep out of each other's
  way. The HUD status block folds with [-] STATUS, the base menu's status panel folds at its header (and by itself
  when the screen is too narrow). Clicking a HUD or menu button no longer fires the door gun.
- Key bindings (ESC menu > "Key bindings..."): rebind every action to a key or mouse button, add a second key, remove
  one with a right-click; keys shared by accident show in red, "Reset to defaults" undoes everything. Bindings are
  saved at once. The ESC menu and help keys always keep one key. The HUD key hints, the outpost hints and the base
  menu toggle show your keys; other labels (tutorial, level-up cards, some menu rows) keep the default keys.
- Help & codex (F1, or the ESC menu): all current controls (plus the touch controls in touch mode) and codex pages
  for enemies, buildings, items and systems (still empty: entries arrive with later updates and unlock per profile). Buttons in the menus, jobs and
  buildings now have hover tooltips.

## 1.0.0-beta.2 - 2026-11-02
- Arsenal: six new door guns, each unlocked in the hangar and levelled 1-5 like the others: Scatter Gun (ten wide
  pellets, weak at range), Flamethrower (short stream, zombies keep burning), Grenade Launcher (lobbed shell that
  bursts where you aim, over walls and crowds), Precision Rifle (slow shot through two targets, favours the head),
  Sonic Cannon (stuns and shoves everything in a cone) and Net Launcher (roots zombies in its burst). New systems:
  Thermal Sight (heat view at night) and Smoke Launcher (a smoke screen when you are shot at; rockets lose their
  lock). New modules: Extra Tank and Heavy Plates (armour that weighs the heli down). Weapons caches and wrecks only
  hand out guns you have unlocked. Armour Plating and Heavy Plates together cut damage by at most 71 %.
- Five new base buildings in the BUILD tab (which now scrolls): Field Hospital (more beds, faster healing next to a
  Field Clinic), Greenhouse (food without farmland), Forge (scrap into metal and parts), Bunker (when the base is
  breached the survivors hide there once and the wave breaks off) and Radio Relay (wider map reveal, raid warnings a
  day early).
- Touch controls: the first touch on a touchscreen brings up two sticks (fly / aim and fire) and buttons for landing,
  guns, yaw, loudspeaker, hook, jobs and building; a mouse move or a key press switches back. The game always starts
  in mouse and keyboard mode; "Touch controls" in the ESC menu shows and switches the mode.
- Music now follows the action: calm, tension, combat, assault, blood moon and victory layers crossfade on the beat.
  Radio messages lower the music and each sender has its own beep (ESC: "Radio beeps"). New sounds for RPG warnings,
  autorotation, building, buttons, events and the smoke screen.
- Cloud backup for online profiles: your run is backed up when you land at the base and can be restored from the
  title screen (RESTORE FROM CLOUD) when the local save is gone. BACKUP on the title exports and imports a profile as a file; an
  imported run is never ranked. A run that ends also removes its cloud copy.
- Crash reports: script errors are reported automatically so they can be fixed (ESC: "Send crash reports" turns it off).
- Smoother play in the browser: chunks load in small steps, distant zombies think less often, paths are cached and
  the minimap redraws less. F3 shows a performance overlay.

## 1.0.0-beta - 2026-10-30
Balance pass over long runs (P18): a bot played 40-day runs on several worlds before and after these changes.
- Morale no longer gets stuck at 100 or slides to 0 for good: each day it moves a quarter of the way back towards 60,
  then the day's events count. A base with power and beds for everyone settles in the 80s, a hungry one near 40, and
  it recovers within a few days once the problem is fixed. Power and "beds for all" give +3 a day (was +5).
- Heli wear is half as fast (rotor 0.6, engine 0.8, gearbox 0.5 % per flight minute). The Workshop now keeps 10
  salvage parts for heli repairs instead of breaking every part down into scrap: before, the hangar never had parts
  and engines failed far from home.
- An Ammo worker makes 60 ammo a day (was 40): the base ran dry right before the big assaults.
- Assaults grow faster after day 25 (+4 more attackers per day on top of the usual +6): the late game was too safe.
- Fix: a brute ram that walks into rock, water or a hedge now goes around it instead of pushing at it for ever.
- Fix: attackers that cannot reach the base (behind a river, stuck in rock) no longer keep an assault going for days:
  at dawn the next morning the last of them scatter and the assault counts as held.
- Fix: shooting a zombie den with the door gun no longer throws a script error.
- Fix: corpses fade out again (an error kept them on the ground after the first one faded).
- Fix: the build bar no longer covers the minimap; with all 11 tools it wraps into a second row.
- Leaderboard: an evacuation victory is worth 5000 points (was 2000). The server checks runs against the real
  15-minute day (server/supabase/007_balance.sql).
- Dev: `SMOKE=longrun` (tests/longrun_test.gd) plays 40 days with a bot and writes build/longrun.csv; it takes 15-40
  minutes and is not part of the quick test loop.

## 0.9.0 - 2026-10-30
- Heli wrecks and a fleet (P15): airfields, checkpoints and airliner crash sites can hold a wrecked Little Bird, Black
  Hawk, Chinook or Hind. Hover over one and press **G** to hook it on the sling (slow, heavy, it swings and snags on
  trees), set it down inside the fence and repair it in the HANGAR with salvage, key parts and Mechanics' work days.
  Switch between your helis in the HANGAR; each one you repair can be picked as the start heli of later runs.
- Run modifiers (P15): pick Dense Horde, Warlords, Scarcity, Dry Season, Glass Cockpit or Blackout on NEW RUN for a
  harder run and a higher score. Each one unlocks through your profile's lifetime stats.
- Convoys (P16): build a Motor Pool (key **8** in build mode) and trucks from salvage, then send a driver and escorts
  from the new CONVOY tab along the roads to a town, landmark, allied village or outpost to bring loot home. Bandits
  can ambush a truck at bridges and narrows: fly in and give air cover, because a truck without an escort can't hold
  on its own. A lost truck costs its cargo, and some of the crew may die.
- Evacuation (P17): from day 15 a Radio Station (Engineer, electronics) makes contact with the military; an Airstrip
  (4x24 cells inside the fence) starts a 3-day countdown to the final siege, the biggest assault of the run plus a bandit
  raid. Hold the strip while the transport lands and loads (faster with a Chinook), then END RUN as a victory or STAY
  BEHIND and play on (the victory stays counted in the profile and on the leaderboard). Trucks stay home during the
  evacuation.
- Build mode: keys 1-9 now end at Demolish (9); Radio Station and Airstrip are picked with the mouse.

## 0.8.0 - 2026-10-30
- Assaults with character (P10): the evening before, a Watchtower radios where they will come from and the HUD points
  an arrow at the fence. Assaults come in 2-3 pushes with a breather between them, and from the 2nd one with a theme
  (runner storm, brute ram, screamer chain, spitter siege). Every 9th night is a **blood moon**: red sky, a boss, a
  bigger wave and double XP. The run now also saves in the middle of an assault.
- Bandits (P11): from day 4 they hold prisons, checkpoints, motels and quarries. Riflemen, MG nests, RPG gunners and
  technicals shoot the heli in the air: keep moving, keep your distance, drop flares against rockets. They fight the
  zombies, carry people off from settlements, raid settlements, outposts and villages at dusk and, from day 12, the
  base at night (never on an assault night). Clear a camp for XP, morale, freed prisoners and its stash.
- Heli wear (P12): rotor, engine, gearbox and door gun wear in flight and from hits (bandit rounds and rockets hit
  them hardest). Worn parts slow you, spread the gun, burn fuel or jam. A dying engine can quit: glide down in
  autorotation, land with **SPACE** and repair on site. The HANGAR tab repairs parts with salvage.
- Radio missions (P13, **J**): rooftop rescues, black boxes, screamers, escorts, clearing bandit camps and medicine
  runs to allied villages, for scrap, XP, morale and sometimes a skilled recruit.
- Outposts and villages (P14): fly 2 militia (**O** on the base pad) to a gas station, checkpoint or radio mast and
  hold it: a pad to refuel, rearm and save. **P** next to a cleared settlement makes it an allied village that
  sends food and water; visit it or it may fall.
- Outpost garrisons count as rescued for the leaderboard and lifetime progress.
- Fix: the radio log no longer runs into the key hints at the bottom of the screen.

## 0.7.2 - 2026-10-30
- WORKERS tab: pin a person to a job (PIN TO; pinned people keep it, the +/- counts spread the rest), sort and filter
  the people list, each row shows skill level, trait, job, whether it fits the skill and the work rate.

## 0.7.1 - 2026-10-30
- Militia also man their posts and shoot when infected come near the fence, not only during assaults.
- **TAB** (or the button between the panels) folds the base menu away while landed on the pad; the door gun can fire.
- Every kill gives 1 scrap.
- Fix: after a browser tab or window switch the heli no longer keeps flying on a key that was held.

## 0.7.0 - 2026-10-30
- Profiles and online leaderboard (P6a, P6b): on first start you enlist with a name and portrait; PROFILES on the title
  switches, renames and deletes profiles; LEADERBOARD (**L**) shows points, days, rescued, kills and best run. Runs are
  sent at start, each day and at the end; a run that could not reach the server at its start is not ranked.
- Named survivors (P7): everyone has a name, a skill that speeds up the matching job (and grows with days in it) and
  a trait. Base morale (hunger, thirst, beds, power, deaths, assaults) speeds up or slows work; very low morale makes
  people leave. Deaths are reported by name.
- New world (P8): one site per 2.5 km cell, towns about three times further apart, 13 landmarks (gas station,
  checkpoint, airfield, dam, crashed airliner, prison ...), highland and river valley regions, bridges, paved roads
  between cities, gas stations refuel the heli once.
- New infected (P9): crawler, screamer, spitter, bloater, armored brute, runner packs; knockback, hit flash, blood,
  corpses, headshots, screen shake for heavy guns (ESC menu option).
- Saves from 0.6.0 cannot be continued (new world and people).

## 0.6.0 - 2026-10-29
- Ironman save (P1): one run per profile saves itself (landing on the pad, each new day, every 120 s, on close; not during an
  assault) and is deleted on death. CONTINUE on the title; NEW RUN over a saved run counts it as lost. Profiles on disk
  (`user://profiles/`), the old `meta.json` becomes profile "Gunner".
- Online backend prepared (P2, not used by the game yet): Supabase tables, RPCs and leaderboard views in `server/`.
- Player-name filter (P3) and 12 profile portraits (P4), used by the profile screen in a later version.
- Tempo (P5): heli top speed 115 / accel 150 (was 160 / 220), zombies slower (shambler 12, runner 42, brute 10, boss 9), a day lasts 900 s,
  XP per level 30 * L^1.6, a full starting tank (100) lasts ~5 min at full throttle, meta unlocks need twice as many rescues / assaults /
  bosses / days / runs (also rerolls, banish, starting slots and the permanent per-rescue bonuses), threat rises 0.08 per day
  instead of 0.15. The heli now actually reaches its top speed (drag 1.25), and Engine upgrades raise it.

## 0.5.0 - 2026-10-28
- Base building: grid preview (green / red, with cost), sandbags rotate with R and join into lines with corners,
  barbed wire (walkable, slows and cuts zombies, wears out), demolition orders for houses, hedges and fences
  (Build workers tear them down for scrap and salvage), compact build bar along the bottom while placing (keys 1-8).
- The base only needs room for the helipad: found it on fields or next to towns, build on any open ground inside the fence.
- Settlements and hideouts inside the fence or within 12 m of it walk to the base and move in by themselves.
- Base people visibly work (bob, hammer swing, dust); militia on their posts aim, recoil and flash; turrets show muzzle flashes.
- Cities: a rare town kind with a street grid, plaza, park, warehouses and three survivor groups.
- Every town links to its two nearest neighbours, roads ford short river crossings, road bends and junctions have their own tiles.
- Zombies give up a chase after 40 s without reaching the target or 4 s out of sight.
- The tutorial shows its current step in its own panel; rescued and kill counts only on the title screen.
- Versioning: version on the title screen, in the ESC menu and in the save file; this changelog.

## 0.4.0 - 2026-10-28
- Runs start without a base: land on open ground and press B to found the FOB.
- A* pathfinding for zombies, survivors and base people.
- Animated base people (uniform, jobs, night, assaults) and the base menu redesign (status column, BUILD / WORKERS / HANGAR).
- Heavier heli with door gun arcs, Q / E yaw, ammo-fed co-gunner.

## 0.3.0 - 2026-10-28
- Progression: heli item slots, level-up cards, systems, weapon levels, meta unlocks, non-linear XP curve.
- Base simulation: sandbags built by workers, militia with rifles, housing, perimeter, water, medicine, injuries and clinic,
  power and light, salvage economy, first-run tutorial.

## 0.2.0 - 2026-10-28
- Zombies instead of aliens, dens with an abomination boss.
- Countryside regions, town templates, lone houses and hideouts; realistic flat art.
- Sound settings (ESC), weapon range.

## 0.1.0 - 2026-10-27
- Playable vertical slice: heli, door gun, procedural chunks, towns, survivors, base, day / night, assaults.
- Title screen, minimap, procedural sound, web export and GitHub Pages deploy.
