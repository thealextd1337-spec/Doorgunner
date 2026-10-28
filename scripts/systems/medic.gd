extends Node
## Medic system: hull regenerates in flight (0.5 + 0.5 per level HP/s); Lv5 also while landed.


func _process(delta: float) -> void:
	var lv := Progression.level("medic")
	if Game.running and (not get_parent().landed or lv >= 5):
		Game.hp = minf(Game.max_hp, Game.hp + (0.5 + 0.5 * lv) * delta)
