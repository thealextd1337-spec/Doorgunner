class_name UiTheme
## Shared UI look and the UI scale (Q6a). Every CanvasLayer UI hangs its controls under `UiTheme.attach(layer)`: a Root
## control that covers the logical canvas at the "ui_scale" setting (90-150 %), so anchors inside it work at any scale.
## Screens laid out for the full canvas (title) or centred dialogs scale only as far as they fit (max_scale / fit).

const SAND := Color(0.91, 0.86, 0.71)
const DIM := Color(0.64, 0.6, 0.5)
const ACCENT := Color(0.96, 0.77, 0.18)
const PANEL := Color(0.06, 0.08, 0.04, 0.97)
const OLIVE := Color(0.33, 0.37, 0.2)
const BAD := Color(1.0, 0.45, 0.38)
const GOOD := Color(0.55, 0.85, 0.45)
const DARK_TEXT := Color(0.06, 0.07, 0.03)
const RADIO := Color(0.8, 1, 0.8) # HUD radio log
const ALERT := Color(1, 0.3, 0.3)
const TOUCH_MIN := 44 # px, smallest finger target (buttons, touch controls)

# font sizes (logical px, the root scale multiplies them)
const FONT_XS := 11
const FONT_S := 12
const FONT := 13
const FONT_M := 14
const FONT_L := 16
const FONT_XL := 24
const FONT_ALERT := 26

# spacing
const MARGIN := 10 # screen edge to the first control
const GAP := 6 # between neighbours in a zone
const PAD := 14 # panel content margin
const BOTTOM_ROW := 30 # bottom strip kept for the HUD key hints; menus end above it
const OBSTACLES := "hud_obstacles" # group: layers whose obstacles() / log_band() the HUD lays its zones around
const TOP_ROW := 24 # top strip of the "[J] MISSIONS" tag; the HUD alert line starts below it

# UI scale setting, percent
const SCALE_KEY := "ui_scale"
const SCALE_MIN := 90
const SCALE_MAX := 150
const SCALE_STEP := 10
const SCALE_DEFAULT := 100
const CANVAS := Vector2(1280, 720) # logical canvas (project.godot: stretch canvas_items, aspect keep)

static var _theme: Theme
static var _mono: SystemFont


## The UI scale factor from the setting (0.9..1.5).
static func ui_scale() -> float:
	return Settings.get_value(SCALE_KEY) / 100.0 if Settings.defs.has(SCALE_KEY) else 1.0


## Adds a scaled Root to `layer` and returns it; build the UI under it. `fit`: the root never scales past what keeps
## that control's minimum size on screen; `max_scale` caps it (1.0 for layouts drawn for the whole canvas).
static func attach(layer: CanvasLayer, fit: Control = null, max_scale := INF) -> Root:
	var r := Root.new()
	r.fit = fit
	r.max_scale = max_scale
	layer.add_child(r)
	return r


static func mono() -> SystemFont:
	if _mono == null:
		_mono = SystemFont.new()
		_mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
	return _mono


## Shared look of the base menu: olive buttons, yellow when pressed / toggled on, sand text.
static func theme() -> Theme:
	if _theme:
		return _theme
	var th := Theme.new()
	th.default_font_size = FONT
	th.set_color("font_color", "Label", SAND)
	th.set_stylebox("normal", "Button", box(OLIVE.darkened(0.35), 4))
	th.set_stylebox("hover", "Button", box(OLIVE.darkened(0.1), 4))
	th.set_stylebox("pressed", "Button", box(ACCENT, 4))
	th.set_stylebox("hover_pressed", "Button", box(ACCENT.lightened(0.15), 4))
	th.set_stylebox("disabled", "Button", box(Color(0.1, 0.11, 0.07), 4))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		th.set_stylebox(st, "OptionButton", th.get_stylebox(st, "Button"))
	th.set_stylebox("panel", "PopupMenu", box(PANEL, 4, ACCENT))
	th.set_stylebox("hover", "PopupMenu", box(ACCENT, 2))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		th.set_color(c, "OptionButton", SAND)
	th.set_color("font_color", "PopupMenu", SAND)
	th.set_color("font_hover_color", "PopupMenu", DARK_TEXT)
	for c in ["font_color", "font_hover_color", "font_focus_color"]:
		th.set_color(c, "Button", SAND)
	th.set_color("font_pressed_color", "Button", DARK_TEXT)
	th.set_color("font_hover_pressed_color", "Button", DARK_TEXT)
	th.set_color("font_disabled_color", "Button", SAND.darkened(0.55))
	th.set_stylebox("panel", "TooltipPanel", box(Color(0.04, 0.05, 0.03, 0.95), 6, ACCENT))
	th.set_color("font_color", "TooltipLabel", SAND)
	_theme = th
	return th


static func box(bg: Color, margin: float, border := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_content_margin_all(margin)
	sb.content_margin_left = margin + 4
	sb.content_margin_right = margin + 4
	if border.a > 0.0:
		sb.border_width_left = 2
		sb.border_color = border
	return sb


## Outlined HUD text (readable over any terrain).
static func outline(l: Control, size := 3) -> void:
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", size)


## Covers the logical canvas at the current scale: size = canvas / scale, scale applied as the control's own transform.
class Root extends Control:
	var fit: Control:
		set(v):
			if fit and fit.minimum_size_changed.is_connected(apply):
				fit.minimum_size_changed.disconnect(apply)
			fit = v
			if fit:
				fit.minimum_size_changed.connect(apply)
			apply()
	var max_scale := INF
	var factor := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		Settings.changed.connect(_on_setting)
		apply()

	func _on_setting(key: String, _v: Variant) -> void:
		if key == UiTheme.SCALE_KEY:
			apply()

	func apply() -> void:
		var s := minf(UiTheme.ui_scale(), max_scale)
		if fit:
			var need := fit.get_combined_minimum_size() + Vector2.ONE * UiTheme.MARGIN * 2.0
			s = minf(s, minf(UiTheme.CANVAS.x / need.x, UiTheme.CANVAS.y / need.y))
		factor = s
		scale = Vector2(s, s)
		size = UiTheme.CANVAS / s
