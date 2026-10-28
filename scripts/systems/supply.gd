extends Node
## Supply Drop system: every 90 s (-10 s per level) a crate POI with reduced contents lands under the heli; Lv5 adds scrap.

var cd := 90.0


func _process(delta: float) -> void:
	if not Game.running:
		return
	cd -= delta
	if cd > 0.0:
		return
	var pos: Vector2 = get_parent().global_position
	if not Game.world.is_landable(pos):
		cd = 2.0 # over water or forest: try again shortly
		return
	var lv := Progression.level("supply")
	cd = 100.0 - 10.0 * lv
	var p: Node2D = Game.world.spawn_poi("crate", pos, RandomNumberGenerator.new())
	p.drop_level = lv
	p.discovered = true
	Game.radio("Command: supply drop on your position, land next to it.")
