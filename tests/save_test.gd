extends Node
## Headless save test (scripts/save.gd). main.gd adds this node when env SMOKE=save (no pre-founded base):
##   SMOKE=save godot --headless --path . --quit-after 30000
## 1. Load 10 chunks, found the base away from the start site, load more chunks, build a sandbag, finish a POI,
##    demolish a house, break into one, save, reload the scene, load: same resources, same tiles at 500 cells,
##    POI still done, sandbag standing, prop still gone. 2. An assault defers the autosave until it is over.
## 3. Another SAVE_FORMAT is discarded. 4. Death deletes run.sav.
## The node moves itself under the root so it survives the reload; the copy main.gd adds after it frees itself.

const T := preload("res://scripts/chunk_manager.gd").T
const NAME := "SaveTest"


func _ready() -> void:
	if get_tree().root.has_node(NAME):
		queue_free()
		return
	call_deferred("_run")


func _run() -> void:
	reparent(get_tree().root)
	name = NAME
	var frame := get_tree().process_frame
	await frame
	await frame
	var main: Node2D = Game.world
	var chunks: TileMapLayer = main.chunks
	Save.delete_run()
	assert(not Save.has_run(), "no run at the start")
	for i in 10:
		chunks._ensure(Vector2i(3 + i % 4, i / 4 - 1))
	# the base 3 chunks east of the start, on the nearest 5x5 of open ground
	var site := Vector2.INF
	var c0 := Vector2(3.5, 0.5) * 512.0
	for r in 40:
		for i in maxi(1, r * 8):
			var p: Vector2 = c0 + Vector2(r * 32.0, 0).rotated(i * TAU / maxi(1, r * 8))
			if site == Vector2.INF and _open(main, p):
				site = p
	assert(site != Vector2.INF, "open ground for the base")
	main.heli.position = site
	main.heli.landed = true
	main.found_base(site)
	main.base.ui.close()
	assert(Game.base_founded and main.BASE_POS.distance_to(site) < 20.0, "base founded off the start site")
	for c in [Vector2i(7, 0), Vector2i(7, 1), Vector2i(2, 2), Vector2i(4, 3), Vector2i(-1, 0)]: # more chunks after founding
		chunks._ensure(c)
	await frame
	# sandbag (built) and a building blueprint (base floor edits)
	var bc := Vector2i((main.base.position / 16.0).floor())
	var bag := Vector2i(-99999, 0)
	var spot := Vector2i(-99999, 0)
	Game.scrap = 500
	for x in range(-9, 10):
		for y in range(-9, 10):
			var c := bc + Vector2i(x, y)
			if bag.x == -99999 and main.base.free_cell(c):
				bag = c
			elif spot.x == -99999 and c.distance_to(bag) > 3 and main.base.can_place("well", c):
				spot = c
	assert(bag.x != -99999 and main.base.place_sandbag(bag), "sandbag placed")
	Game.sandbags[bag]["built"] = true
	main.base.bags[bag].modulate.a = 1.0
	if spot.x != -99999:
		assert(main.base.place_building("well", spot), "well blueprint")
	# a generated POI that is not a settlement, done by landing next to it
	var poi: Node2D = null
	for p in main.pois:
		if poi == null and p.kind in ["crate", "water_tower", "scrapyard", "pharmacy", "wreck", "radio_tower"] and not p.uid.begins_with("dyn"):
			poi = p
	assert(poi != null, "a generated POI")
	var heli_pos: Vector2 = main.heli.position
	main.heli.position = poi.position
	poi._on_landed(true)
	main.heli.position = heli_pos
	assert(poi.done, "POI done")
	# a house broken into (enemy.gd), a demolition with its prop (a cell next to the base painted as a house)
	var house := Vector2i(-99999, 0)
	for cell in chunks.get_used_cells():
		if house.x == -99999 and chunks.get_cell_atlas_coords(cell).x == T.BUILDING and cell.distance_to(bc) > 20:
			house = cell
	assert(house.x != -99999, "a house somewhere")
	chunks.break_in(house)
	var prop: Node2D = main.spawn_prop("tree", main.base.cell_pos(bc + Vector2i(4, 6)))
	var prop_pos := prop.position
	var demo := {"kind": "house", "cells": [bc + Vector2i(4, 6), bc + Vector2i(5, 6)], "cell": bc + Vector2i(4, 6), "prop": prop, "progress": 0.0}
	main.base.demolitions.append(demo)
	main.base._finish_demolition(demo)
	await frame
	assert(main.base.mark_demolition(bc + Vector2i(4, 6)) == false, "grass is nothing to demolish")
	# a pending order on a fake hedge, half done
	chunks.edit(bc + Vector2i(-6, 5), T.HEDGE)
	assert(main.base.mark_demolition(bc + Vector2i(-6, 5)), "hedge marked: tile %d, %s" % [chunks.get_cell_atlas_coords(bc + Vector2i(-6, 5)).x, main.base.demolitions])
	main.base.demolitions[0]["progress"] = 3.0
	# some zombies, a non-default heli and resources
	for i in 5:
		main.spawn_enemy("shambler", site + Vector2(300 + i * 10, 0))
	main.heli.landed = false
	main.heli.vel = Vector2(12, -3)
	main.heli.position = site + Vector2(40, 10)
	Game.workers["build"] = 0 # no work done in the frames around the reload
	Game.time = 0.5
	Game.day = 2
	Game.add_weapon("autocannon")
	Game.base_food = 33.5
	get_tree().paused = true # nothing moves between the save and the checks
	var before := Game.save_state().duplicate(true)
	var cells := _samples(chunks, bc)
	var tiles := cells.map(func(c): return Vector2i(chunks.get_cell_atlas_coords(c).x, chunks.get_cell_alternative_tile(c)))
	var n_pois: int = main.pois.size()
	var n_enemies := _enemies().size()
	var events: Array = chunks.events.duplicate(true)
	var poi_uid: String = poi.uid
	# --- save, reload, load
	assert(Save.autosave(), "saved")
	assert(Save.has_run() and FileAccess.file_exists(Save.path()), "run.sav written")
	assert(Save.head()["day"] == 2, "head has the day")
	Save.pending = true
	get_tree().reload_current_scene()
	await frame
	await frame
	await frame
	main = Game.world
	chunks = main.chunks
	assert(is_instance_valid(main) and Game.running, "loaded and running")
	var after := Game.save_state()
	for k in before:
		assert(var_to_str(before[k]) == var_to_str(after[k]), "Game.%s restored: %s vs %s" % [k, before[k], after[k]])
	assert(Game.heli_weapons.get_typed_builtin() == TYPE_STRING and "autocannon" in Game.weapon_bay and Game.max_ammo > 0, "typed arrays and recompute")
	assert(main.heli.position.distance_to(site + Vector2(40, 10)) < 2.0 and not main.heli.landed, "heli position %s" % main.heli.position)
	assert(main.BASE_POS.distance_to(site) < 20.0 and main.base.visible, "base back at its site")
	assert(chunks.events.slice(0, events.size()) == events, "same world event log")
	var bad := 0
	for i in cells.size():
		var now := Vector2i(chunks.get_cell_atlas_coords(cells[i]).x, chunks.get_cell_alternative_tile(cells[i]))
		if now != tiles[i]:
			bad += 1
			if bad < 5:
				print("tile differs at %s: %s was %s" % [cells[i], now, tiles[i]])
	assert(bad == 0, "%d of %d sample tiles differ" % [bad, cells.size()])
	assert(chunks.get_cell_atlas_coords(house).x == T.RUIN, "house stays broken")
	assert(chunks.get_cell_atlas_coords(bc + Vector2i(5, 6)).x == T.GRASS, "demolished house stays grass")
	assert(chunks.prop_at(prop_pos) == null, "demolished prop stays gone")
	assert(main.base.demolitions.size() == 1 and main.base.demolitions[0]["progress"] == 3.0, "pending demolition")
	var p2: Node2D = null
	for p in main.pois:
		if p.uid == poi_uid:
			p2 = p
	assert(main.pois.size() == n_pois, "same POI count %d vs %d" % [main.pois.size(), n_pois])
	assert(p2 != null and p2.done, "POI still done")
	assert(Game.sandbags.has(bag) and Game.sandbags[bag]["built"] and main.base.bags.has(bag), "sandbag standing")
	assert(_enemies().size() == n_enemies, "zombies back %d vs %d" % [_enemies().size(), n_enemies])
	get_tree().paused = false
	await frame
	assert(main.base.pawns.get_child_count() == mini(Game.rescued, main.base.PAWN_MAX), "pawns rebuilt")
	print("SAVE load OK  %d tiles, %d events, %d POIs, %d zombies" % [cells.size(), events.size(), n_pois, n_enemies])
	# --- an assault defers the save until it is over
	Game.scrap = 4242
	Game.attack_active = true
	assert(not Save.autosave() and Save.deferred, "no save during an assault")
	assert(Save.read()["systems"]["game"]["scrap"] != 4242, "old run kept")
	for i in 30: # spawner ends the assault (no attackers), then Save writes
		await frame
		if not Save.deferred:
			break
	assert(not Game.attack_active and not Save.deferred, "assault over, deferred save written")
	assert(Save.read()["systems"]["game"]["scrap"] == 4242, "deferred save has the new state")
	# --- another SAVE_FORMAT is discarded
	var data := Save.read()
	data["format"] = Save.SAVE_FORMAT - 1
	FileAccess.open(Save.path(), FileAccess.WRITE).store_buffer(var_to_bytes(data))
	DirAccess.remove_absolute(Save.path() + ".bak")
	assert(not Save.load_run(), "older format refused")
	assert(not Save.has_run() and Save.notice != "", "older run discarded with a notice")
	Save.notice = ""
	# --- death deletes the run
	assert(Save.autosave() and Save.has_run(), "saved again")
	Game.end_run("test")
	assert(not Save.has_run(), "death deleted run.sav")
	print("SAVE OK")
	get_tree().quit(0)


func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return "target_base" in e)


## 500 cells: 200 near the base, 150 on roads, 150 anywhere loaded.
func _samples(chunks: TileMapLayer, bc: Vector2i) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out := []
	for i in 200:
		out.append(bc + Vector2i(rng.randi_range(-14, 14), rng.randi_range(-14, 14)))
	var used: Array = chunks.get_used_cells()
	var roads := used.filter(func(c): return chunks.get_cell_atlas_coords(c).x in chunks.ROADS)
	assert(roads.size() > 0, "some roads")
	for i in 150:
		out.append(roads[rng.randi() % roads.size()])
	for i in 150:
		out.append(used[rng.randi() % used.size()])
	return out


func _open(main: Node2D, p: Vector2) -> bool:
	for x in range(-3, 4):
		for y in range(-3, 4):
			if not main.is_landable(p + Vector2(x, y) * 16.0):
				return false
	return true
