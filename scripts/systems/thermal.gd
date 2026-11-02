extends Node2D
## Thermal Sight (Q8 system): at night enemies near the heli glow orange through the dark. Lv5 reaches 45 m and also
## shows zombies hiding in forest. Purely visual: no enemy.gd branch.

const REACH_BASE := 160.0 # px, + REACH_PER_LEVEL per level
const REACH_PER_LEVEL := 40.0
const REACH_LV5 := 450.0
const MIN_DARK := 0.2 # below this it is day and the sight is off


func _ready() -> void:
	z_index = 6


func reach() -> float:
	var lv := Progression.level("thermal")
	return REACH_LV5 if lv >= 5 else REACH_BASE + REACH_PER_LEVEL * lv


## Enemies the sight currently shows (tests, and _draw).
func seen() -> Array:
	var out := []
	if Game.darkness() < MIN_DARK:
		return out
	var r := reach()
	for e in get_tree().get_nodes_in_group("enemies"):
		if global_position.distance_squared_to(e.global_position) <= r * r and (not e.get("concealed") or Progression.level("thermal") >= 5):
			out.append(e)
	return out


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not Game.running:
		return
	var night: Color = Game.world.night.color
	var heat := Color(1.0, 0.45, 0.15, 0.55 * Game.darkness()) / Color(night.r, night.g, night.b, 1.0) # undo the night tint so the glow stays bright
	for e in seen():
		draw_circle(to_local(e.global_position), e.radius + 3.0, heat)
