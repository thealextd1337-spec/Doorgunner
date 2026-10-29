# Changelog

The version lives in `project.godot` (`config/version`). Builds show it with commit and date ("v0.5.0 (a3aaf6b 2026-10-28)")
on the title screen and in the ESC menu. `tools/deploy_web.sh` tags the deployed commit `v<version>`: bump the version
for a new release. Versions before 0.5.0 were assigned afterwards from the git history and are not tagged.

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
