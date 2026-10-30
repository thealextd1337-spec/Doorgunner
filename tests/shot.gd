extends Node
## Visual check: SMOKE=shot godot --path . -> flies a bit, saves screenshots (no base at the start, then founds it at the start site; flight, combat, bandits, level-up cards, base BUILD / WORKERS / HANGAR,
## base pawns after delivering 6, settings, title hangar), quits.
## Time-based so it works at any refresh rate.

var t := 0.0
var step := 0
var t_out := 0.0


func _ready() -> void:
	process_priority = -10 # press keys before the heli reads them
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	t += delta
	match step:
		0:
			if t > 0.5:
				_save("shot_nobase.png") # run start: no base yet
				Game.world.found_base(Game.world.BASE_POS)
				Input.action_press("land")
				step = 1
		1:
			Input.action_release("land")
			Input.action_press("move_right")
			step = 2
		2:
			if t > 5.0: # 1.5 s spool + ~3 s flight
				Input.action_release("move_right")
				_save("shot_flight.png")
				var ms: Node = Game.world.missions # the J list with three missions
				ms._add("rooftop", {"pos": Game.heli.position + Vector2(300, -200), "text": "a family is stuck on a roof in a city", "state": {}})
				ms._add("screamer", {"pos": Game.heli.position + Vector2(-600, 500), "text": "a screamer is calling hordes at a village", "state": {}})
				ms._add("blackbox", {"pos": Game.heli.position + Vector2(1500, 900), "text": "recover the black box from the airliner crash site", "state": {}})
				Game.world.get_children().filter(func(c): return c.get("panel") != null and c.layer == 6)[0]._unhandled_input(_j_key())
				step = 21
		21:
			if t > 5.4:
				_save("shot_missions.png")
				Game.world.get_children().filter(func(c): return c.get("panel") != null and c.layer == 6)[0]._unhandled_input(_j_key())
				# the HUD with everything at once: mission arrows, the assault arrow at the fence, worn parts and an engine alarm
				Game.heli.position = Game.world.base.position + Vector2(-60, -40)
				Game.world.assault.plan = {"day": Game.day + 1, "theme": "", "dir": 2, "blood": false, "known": true, "tower": true}
				for c in ["rotor", "engine", "gearbox", "gun"]:
					Game.world.wear.cond[c] = 18.0
				Game.world.wear.state = "warn"
				Game.world.wear.t = 10.0
				step = 22
		22:
			if t > 5.8:
				_save("shot_hud.png")
				Game.world.assault.plan = {}
				for c in ["rotor", "engine", "gearbox", "gun"]:
					Game.world.wear.cond[c] = 100.0
				Game.world.wear.state = ""
				Game.world.missions.open.clear()
				step = 3
		3:
			Game.time = 0.9
			for i in 8:
				Game.world.spawn_enemy(["shambler", "runner", "brute", "screamer", "spitter", "crawler", "bloater", "brute_armored"][i], Game.heli.position + Vector2(120, 0).rotated(i * TAU / 8))
			Game.heli.aim_override = Vector2(0, 1) # nose east: aim out of the right door
			Input.action_press("fire")
			step = 4
		4:
			if t > 5.6:
				_save("shot_night_combat.png")
				Input.action_release("fire")
				Game.heli.aim_override = Vector2.ZERO
				Game.time = 0.5 # bandits by day: riflemen, an MG nest, a technical and an RPG on aim (red line), a rocket in flight
				for e in get_tree().get_nodes_in_group("enemies"):
					if "target_base" in e: # the zombies would draw the bandits' fire
						e.queue_free()
				var at: Vector2 = Game.heli.position + Vector2(0, 120)
				for i in 4:
					Game.world.bandits.spawn_unit("rifle", at + Vector2(-90 + 60 * i, 20 * (i % 2)), "guard", at, "")
				Game.world.bandits.spawn_unit("mg", at + Vector2(110, -40), "guard", at, "")
				Game.world.bandits.spawn_unit("technical", at + Vector2(-140, -60), "guard", at, "")
				var rpg: Node2D = Game.world.bandits.spawn_unit("rpg", at + Vector2(40, 60), "guard", at, "")
				rpg.fire_cd = 0.0
				rpg.fire_rocket(Game.heli).position = at + Vector2(-40, -70)
				step = 41
		41:
			if t > 6.4:
				_save("shot_bandits.png")
				for b in get_tree().get_nodes_in_group("bandits") + get_tree().get_nodes_in_group("rockets"):
					b.queue_free()
				Game.hp = Game.max_hp
				Game.time = 0.9
				Game.add_xp(100)
				step = 5
		5:
			if t > 5.8:
				_save("shot_levelup.png")
				while get_tree().paused:
					Game.world.choice_ui.pick(0)
				Game.heli.position = Game.world.BASE_POS
				Game.heli.vel = Vector2.ZERO
				Game.time = 0.35 # daylight for the base shots
				Game.passengers = 6
				Game.scrap = 150
				Input.action_press("land")
				step = 6
		6:
			Input.action_release("land")
			step = 7
		7:
			if t > 8.0: # 1.5 s landing spool, then the base menu is open
				var ui: CanvasLayer = Game.world.base.ui
				ui.set_worker("militia", 3)
				ui.set_worker("build", 1)
				ui.set_worker("farm", 1)
				var bc := Vector2i((Game.world.BASE_POS / 16.0).floor())
				for i in 6: # a sandbag line with a corner, a wire run in front, half of it built
					for c in [bc + Vector2i(4, i - 3), bc + Vector2i(i - 1, 3)]:
						if Game.world.base.place_sandbag(c) and i % 2 == 0:
							Game.sandbags[c]["built"] = true
							Game.world.base.bags[c].modulate.a = 1.0
					Game.world.base.place_sandbag(bc + Vector2i(6, i - 3), "wire")
				Game.world.base.place_kind = "barracks"
				Game.world.base.placing = true
				get_viewport().warp_mouse(get_viewport().get_visible_rect().size / 2 + Vector2(-60, 120)) # the build preview
				step = 71
		71:
			if t > 8.1:
				_save("shot_base.png")
				Game.world.base.placing = false
				while get_tree().paused:
					Game.world.choice_ui.pick(0) # a late level-up card would cover the menu
				Game.world.base.ui.show_tab("WORKERS")
				Game.people[0]["trait"] = "lazy"
				Game.world.base.ui.pin_person(Game.people[0]["id"], "repair") # a pinned person for the WORKERS shot
				Game.people[2]["injured"] = true
				Game.people[2]["pin"] = "farm"
				Game.world.base.ui.refresh()
				step = 70
		70:
			if t > 8.15:
				_save("shot_workers.png")
				Game.take_item("searchlight")
				Game.take_item("engine")
				Game.world.base.ui.show_tab("HANGAR")
				Game.world.base.ui.refresh()
				step = 8
		8:
			if t > 8.3:
				_save("shot_hangar.png")
				var cv: Node2D = Game.world.convoys # P16: a Motor Pool, a truck, a driver, destinations
				Game.buildings.append({"kind": "motor_pool", "cell": Vector2i(-99, -99), "built": true, "progress": 0.0})
				cv.trucks = 1
				Game.people[1]["skill"] = "driver"
				for s in Game.world.chunks.sites_near(Game.world.BASE_POS, 3000.0):
					Game.world.chunks._ensure(Vector2i((s.pos / 512.0).floor()))
				Game.world.base.ui.show_tab("CONVOY")
				cv.refresh_tab()
				step = 85
		85:
			if t > 8.45:
				_save("shot_convoy_tab.png")
				Game.world.base.ui.visible = false # the pawns walk into the barracks, change and go to work
				Engine.time_scale = 4.0
				step = 80
		80:
			if t > 20.0:
				_save("shot_pawns.png")
				Engine.time_scale = 1.0
				step = 81
		81: # an outpost with a garrison, then an allied village (P14)
			Game.world.base.ui.visible = false
			var op: Node2D = Game.world.outposts
			var at: Vector2 = Game.world.BASE_POS + Vector2(900, 0)
			Game.heli.position = at
			var o := {"id": "o1", "site": "gas_station", "pos": at, "fuel": 40.0, "ammo": 80, "hp": 100.0, "day": Game.day}
			op.list.append(o)
			for i in 3:
				var p := Game.People.make(Game.seed, 900 + i, Game.day, false)
				p["post"] = "o1"
				Game.people.append(p)
			op._rebuild(o)
			op.alert["o1"] = 99.0
			t_out = t
			step = 82
		82:
			if t > t_out + 1.2:
				_save("shot_outpost.png")
				var pos: Vector2 = Game.heli.position + Vector2(-900, 600)
				var poi: Node2D = Game.world.spawn_poi("survivors", pos, RandomNumberGenerator.new(), 4)
				Game.heli.position = pos + Vector2(24, 0)
				Game.heli.landed = true
				Game.world.outposts.protect()
				t_out = t
				step = 83
		83:
			if t > t_out + 1.2:
				_save("shot_village.png")
				var cv: Node2D = Game.world.convoys # a truck on the road (P16)
				for d in cv.destinations():
					if cv.send(d["uid"], Game.people[1]["id"], 0) == "":
						break
				if not cv.list.is_empty():
					var c: Dictionary = cv.list[0]
					c["d"] = cv.length(c) * 0.4
					c["amb"] = {"out": -1.0, "back": -1.0}
					Game.heli.position = cv.pos_of(c) + Vector2(40, -30)
				t_out = t
				step = 84
		84:
			if t > t_out + 1.5:
				_save("shot_convoy.png")
				Game.world.outposts.list.clear()
				Game.world.outposts.alert.clear()
				Game.heli.position = Game.world.BASE_POS
				Game.world.base.ui.visible = true
				for c in Game.world.get_children():
					if c is CanvasLayer and c.layer == 25:
						c.open()
				step = 9
		9:
			if t > 20.3:
				_save("shot_settings.png")
				Profiles.active()["enlisted"] = true # in memory only: no ENLIST pop-up over the hangar shot
				var title: CanvasLayer = preload("res://scripts/title_ui.gd").new()
				Game.world.add_child(title)
				title.open()
				title._toggle_hangar()
				step = 10
		10:
			if t > 20.6:
				_save("shot_title_hangar.png")
				title_ui()._toggle_hangar()
				step = 11
		11:
			if t > 20.9:
				_save("shot_title.png")
				title_ui().profile_ui.open_list()
				step = 12
		12:
			if t > 21.2:
				_save("shot_profiles.png")
				title_ui().profile_ui.enlist("", false)
				title_ui().profile_ui.name_edit.text = "Hitler"
				title_ui().profile_ui.name_edit.text_changed.emit("Hitler")
				step = 13
		13:
			if t > 21.5:
				_save("shot_enlist.png")
				title_ui().profile_ui.close()
				var rows: Array = []
				for i in 50:
					rows.append({"rank": i + 1, "player_id": "id%d" % i, "name": "Gunner%d" % i, "avatar": i % 12, "value": 9000 - i * 130})
				title_ui().board_ui.show_rows("points", rows, {"rank": 77, "player_id": "me", "name": "Me", "avatar": 1, "value": 120})
				step = 14
		14:
			if t > 21.8:
				_save("shot_leaderboard.png")
				get_tree().quit()


func _j_key() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_J
	ev.physical_keycode = KEY_J
	ev.pressed = true
	return ev


func title_ui() -> CanvasLayer:
	return Game.world.get_children().filter(func(c): return c is CanvasLayer and c.layer == 40)[0]


func _save(name: String) -> void:
	get_viewport().get_texture().get_image().save_png("res://" + name)
