class_name Art
## Sprite lookup for the selected art variant. Textures are 4x their logical size, so sprites are scaled by SCALE.

const SCALE := 0.25

static var variant := "b"
static var _cache := {}


static func tex(name: String) -> Texture2D:
	var path := "res://assets/sprites/%s/%s.png" % [variant, name]
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


static func sprite(name: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(name)
	s.scale = Vector2(SCALE, SCALE)
	return s
