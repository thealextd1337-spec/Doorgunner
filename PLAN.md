# Doorgunner – Plan

Godot 4.7 / GDScript, pixel art (16 px tiles, 32 px heli), all English.
Twin-stick: WASD flies the heli, mouse aims/fires the door gun.
Endless procedural chunk world, day/night cycle (1 day = 5 min), base attack every 3rd night.
Permadeath run, meta progression (rescued survivors unlock permanent bonuses).

## Milestones
- M1 vertical slice: heli, bullets, chunked terrain with towns, walker enemies, ammo/fuel, base (land = refuel/rearm/unload), survivors rescue, HUD, day clock.
- M2 content: POI types (supply, upgrade, radio tower, crash site), radio hints, XP + level-up choice, 4 enemy types + boss, base attack wave, base upgrades (turrets, fuel tank, hangar, barracks).
- M3 loop: game over + meta progression save, sound, title screen.

## Layout
- tools/gen_sprites.py  -> assets/sprites/*.png (regenerate: `python tools/gen_sprites.py`)
- scripts/game_state.gd autoload: run resources, day clock, meta save
- scenes/main.tscn      world root: ChunkManager, Heli, Base, spawner, HUD
- scenes/heli/, scenes/enemies/, scenes/poi/, scenes/base/, scenes/ui/

## Run
`godot --path J:/Doorgunner` (editor) or `godot --path J:/Doorgunner --headless --quit` (import check)
