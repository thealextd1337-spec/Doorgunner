# Doorgunner

Top-down helicopter rescue roguelike. You are the door gunner of a military helicopter
over an alien-infested countryside: rescue survivors, haul them to the forward base,
build the base up, and hold it when the hive assaults every third night.

## Play
- Open the project in Godot 4.7 (`godot --path .`) and press F5, or run `godot --path . --export`-free: just `godot --path .`.
- **WASD / arrows** fly, **mouse** aims, **LMB** fires the door gun, **SPACE** lands / takes off, **R** restarts after a run ends.
- Land next to a point of interest to interact: settlements (survivors board one by one, hold the LZ),
  supply crates (fuel, ammo, scrap), weapons caches (pick an upgrade), relay towers (reveal nearby POIs),
  crash sites (scrap and a permanent boost). Hive nests spawn a queen boss when approached.
- Landing on the base pad refuels, rearms, repairs, delivers passengers and opens the base menu (turrets, walls, depot, armory, workshop, clinic, barracks).
- Fuel and ammo run out. Level-ups let you pick one of three upgrades. Dying ends the run; survivors rescued
  across runs unlock permanent seats, fuel and ammo capacity (saved in `user://meta.json`).

## Dev
- `python tools/gen_sprites.py` regenerates all pixel art in `assets/sprites/`.
- Headless checks (bash): `SMOKE=1 godot --headless --path . --quit-after 3000` prints `SMOKE OK`. Other values: `poi`, `base`, `ui`.
- `SMOKE=shot godot --path .` saves three screenshots into the project folder.
