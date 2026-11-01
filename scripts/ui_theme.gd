class_name UiTheme
## Shared UI look (Q0 minimal). New UI uses these instead of its own constants; Q6a moves the existing UIs over and adds
## font sizes, spacing and the UI-scale setting.

const SAND := Color(0.91, 0.86, 0.71)
const DIM := Color(0.64, 0.6, 0.5)
const ACCENT := Color(0.96, 0.77, 0.18)
const PANEL := Color(0.06, 0.08, 0.04, 0.97)
const OLIVE := Color(0.33, 0.37, 0.2)
const BAD := Color(1.0, 0.45, 0.38)
const GOOD := Color(0.55, 0.85, 0.45)
const DARK_TEXT := Color(0.06, 0.07, 0.03)
const TOUCH_MIN := 44 # px, smallest finger target (buttons, touch controls)


## UI scale factor; fixed until Q6a registers its slider.
static func ui_scale() -> float:
	return 1.0
