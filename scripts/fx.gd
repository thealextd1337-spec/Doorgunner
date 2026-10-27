extends Node2D
## One-shot explosion from the 6-frame explosion strip.

var t := 0.0
var sprite: Sprite2D


func _ready() -> void:
	z_index = 11
	sprite = Sprite2D.new()
	sprite.texture = load("res://assets/sprites/explosion.png")
	sprite.hframes = 6
	add_child(sprite)


func _process(delta: float) -> void:
	t += delta
	sprite.frame = min(5, int(t / 0.07))
	if t > 0.45:
		queue_free()
