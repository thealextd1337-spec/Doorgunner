# Changelog

The version lives in `project.godot` (`config/version`). Builds show it with commit and date ("v0.5.0 (a3aaf6b 2026-10-28)")
on the title screen and in the ESC menu. `tools/deploy_web.sh` tags the deployed commit `v<version>`: bump the version
for a new release. Versions before 0.5.0 were assigned afterwards from the git history and are not tagged.

## Unreleased
- Evacuation (P17): from day 15 a Radio Station (Engineer, electronics) makes contact with the military; an Airstrip
  (4x24 cells inside the fence) starts a 3-day countdown to the final siege, the biggest assault of the run plus a bandit
  raid. Hold the strip while the transport lands and loads, then END RUN as a victory or STAY BEHIND and play on (the
  victory stays counted in the profile and on the leaderboard).

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
