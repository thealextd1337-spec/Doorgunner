# Doorgunner

Top-down helicopter rescue roguelike. You are the door gunner of a military helicopter
over a zombie-infested countryside: rescue survivors, haul them to the forward base,
build the base up, and hold it when the horde assaults every third night.

## Play
- Open the project in Godot 4.7 (`godot --path .`) and press F5, or run `godot --path . --export`-free: just `godot --path .`.
- **WASD / arrows** fly, **mouse** aims, **LMB** fires the door gun, **SPACE** lands / takes off, **R** restarts after a run ends, **ESC** opens the sound settings (volumes are saved).
- Land next to a point of interest to interact: settlements (survivors board one by one, hold the LZ),
  supply crates (fuel, ammo, scrap), weapons caches (pick an upgrade), relay towers (reveal nearby POIs),
  crash sites (scrap and a permanent boost). Zombie dens spawn an abomination boss when approached.
- Landing on the base pad refuels, rearms, repairs, delivers passengers and opens the base menu (turrets, walls, depot, armory, workshop, clinic, barracks).
- Pace is deliberate: landing and take-off spool for 1.5 s, gunfire and the rotor make NOISE that draws zombies (flying is safe, landing is not: everything within 600 px swarms a landed heli), settlements fall overnight if you leave them, the base eats food (farm workers, crates) and hull repairs cost scrap.
- Fuel and ammo run out. Level-ups let you pick one of three upgrades. Dying ends the run; survivors rescued
  across runs unlock permanent seats, fuel and ammo capacity (saved in `user://meta.json`).

## Dev
- `python tools/gen_sprites.py` regenerates the three art variants in `assets/sprites/{a,b,c}/` (pick one on the title screen with 1/2/3; `ART=b` env overrides it for a session). Previews: `docs/art_a.png`, `docs/art_b.png`, `docs/art_c.png`.
- `python tools/gen_sfx.py` regenerates all sound effects in `assets/sfx/`. **M** mutes in game.
- Headless checks (bash): `SMOKE=1 godot --headless --path . --quit-after 3000` prints `SMOKE OK`. Other values: `poi`, `base`, `ui`.
- `SMOKE=shot godot --path .` saves three screenshots into the project folder.
