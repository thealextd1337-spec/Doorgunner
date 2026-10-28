# Doorgunner

Top-down helicopter rescue roguelike. You are the door gunner of a military helicopter
over a zombie-infested countryside: rescue survivors, haul them to the forward base,
build the base up, and hold it when the horde assaults every third night.

## Play
- Open the project in Godot 4.7 (`godot --path .`) and press F5, or run `godot --path . --export`-free: just `godot --path .`.
- **WASD / arrows** fly, **mouse** aims, **LMB** fires the door gun (out of the side doors only: swing the heli to bring it to bear; zombies hide in forests and chew into houses), **SPACE** lands / takes off, **Q / E** swing the heli (the door guns only fire sideways), **Q** switches guns, **F** fires the loudspeaker (when fitted), **R** restarts after a run ends, **ESC** opens the sound settings (volumes are saved).
- Land next to a point of interest to interact: settlements (survivors board one by one, hold the LZ),
  supply crates (fuel, ammo, scrap), weapons caches (a weapon or one item card), relay towers (reveal nearby POIs),
  crash sites (scrap and a permanent boost). Zombie dens spawn an abomination boss when approached.
- Landing on the base pad refuels, rearms, repairs, delivers passengers and opens the base menu (turrets, depot, armory, workshop, buildings, perimeter).
- The base has needs: everyone eats 1 food and drinks 1 water a day; with no beds left (2 in the hangar, 4 per Barracks) people camp outside, eat double, work at half rate and get hurt in assaults. Buildings (Barracks, Field Clinic, Generator, Well, Watchtower) and perimeter stages are placed as blueprints in the BUILD tab inside the fence and built by Build workers. The injured need a clinic bed and 1 medicine (pharmacies, crates, crash sites) or may die; water comes from wells, the Water job (river or lake nearby), water towers in towns, crates and lake huts. A fuelled Generator lights the base at night, keeps turrets at full rate, speeds healing and thins out the night hordes. Militia only shoot with rifles (weapons caches, crash sites, the Armory, zombie drops). The first run starts a short tutorial (also on the title screen; ESC menu skips it).
- Salvage: crates, crash sites, scrap yards (industrial towns, some suburbs) and kills yield metal, parts and electronics; with the Workshop upgrade, Workshop workers break 12 units a day each down into scrap (electronics 3, parts 2, metal 1).
- Sandbags: toggle "Place sandbags" in the BUILD tab and click around the pad (5 scrap, RMB removes). Blueprints are built by survivors on Build duty, zombies have to chew through them, Militia man them during assaults, Medics patch the hull for free.
- Pace is deliberate: landing and take-off spool for 1.5 s, gunfire and the rotor make NOISE that draws zombies (flying is safe, landing is not: everything within 380 px swarms a landed heli), settlements fall overnight if you leave them, the base eats food (farm workers, crates) and hull repairs cost scrap.
- Fuel and ammo run out. Dying ends the run; survivors rescued across runs unlock permanent seats, fuel and ammo capacity (saved in `user://meta.json`).
- Progression (`docs/PROGRESSION.md`, `scripts/progression.gd`): the heli has hardpoint / system / module slots (start 1/2/2, Workshop or meta unlocks raise them to 2/3/3).
  Each level-up offers three item cards (new item or next level, max 5): **1-4** or click picks, **R** rerolls, **S** skips for 15 scrap, **B** banishes (unlocked at 200 rescued).
  Heli level caps at 30, further XP turns into scrap. The base HANGAR tab scraps items; the title screen HANGAR (**H**) lists every item and its unlock condition.

## Dev
- `python tools/gen_sprites.py` regenerates the art ("Field Map" style) in `assets/sprites/b/`. Previews: `docs/region_*.png`.
- `python tools/gen_sfx.py` regenerates all sound effects in `assets/sfx/`. Sound starts muted for now: **M** or the ESC menu turns it on.
- Headless checks (bash): `SMOKE=1 godot --headless --path . --quit-after 30000` prints `SMOKE OK`. Other values: `poi`, `base`, `ui`, `prog` (heli systems), `tut` (tutorial).
- `SMOKE=shot godot --path .` saves screenshots (flight, combat, level-up cards, base, hangar, settings, title hangar) into the project folder.
