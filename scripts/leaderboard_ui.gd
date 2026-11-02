class_name LeaderboardUi
extends Overlay
## Title leaderboard (L): DAILY (today's ranked daily runs) / SEASON (points of this ISO week) / ALL-TIME with the tabs
## POINTS / DAYS / RESCUED / KILLS / BEST RUN, top 50, own row always visible, click a row for
## the player's breakdown. Online data comes from the Online autoload (P6a): fetch_board(kind, limit) -> board(rows, own_row) /
## board_failed(error), fetch_player(id) -> player(stats) / player_failed(error); Online drops answers of superseded requests.
## Rows: {rank, player_id, name, avatar, value, day?, victory?}. Offline: the local record.

const TABS := {"points": "POINTS", "days": "DAYS", "rescued": "RESCUED", "kills": "KILLS", "best_run": "BEST RUN"} # all-time
const SCOPES := {"daily": "DAILY", "season": "SEASON", "points": "ALL-TIME"} # kind each top tab opens
const LIMIT := 50

var kind := "points"
var own_id := ""
var failed := false # the board shown is an error / offline view: reload when the connection comes back
var tab_btns := {}
var scope_btns := {}
var tabs: HBoxContainer # the all-time tabs, hidden on DAILY / SEASON
var list: VBoxContainer
var own_slot: VBoxContainer # the own row, pinned below the scroll area
var status: Label
var detail: Label
var player_id := "" # whose breakdown was asked for


func _ready() -> void:
	_build(720)
	box.add_child(label("// LEADERBOARD", 13, ACCENT))
	var scopes := HBoxContainer.new()
	scopes.add_theme_constant_override("separation", 6)
	box.add_child(scopes)
	for k in SCOPES:
		var b := button(SCOPES[k], 0)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): show_kind(k))
		scopes.add_child(b)
		scope_btns[k] = b
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	box.add_child(tabs)
	for k in TABS:
		var b := button(TABS[k], 0)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): show_kind(k))
		tabs.add_child(b)
		tab_btns[k] = b
	status = label("", 13, OLIVE.lightened(0.5))
	box.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)
	own_slot = VBoxContainer.new()
	box.add_child(own_slot)
	detail = label("", 13, SAND)
	box.add_child(detail)
	var close_btn := button("CLOSE [L]", 0, true)
	close_btn.pressed.connect(close)
	box.add_child(close_btn)
	Online.board.connect(_on_board)
	Online.board_failed.connect(_on_board_failed)
	Online.player.connect(_on_player)
	Online.player_failed.connect(_on_player_failed)
	Online.online_changed.connect(_on_online)


func open() -> void:
	visible = true
	show_kind(kind)


func _input(event: InputEvent) -> void:
	super(event)
	if visible and event.is_action_pressed("leaderboard"):
		get_viewport().set_input_as_handled()
		close()


func show_kind(k: String) -> void:
	kind = k
	_mark_tabs()
	detail.text = ""
	player_id = ""
	failed = false
	status.text = "Loading..."
	_fill([], {})
	Online.fetch_board(k, LIMIT) # offline answers board_failed("offline")


func _on_board(rows: Array, own_row: Dictionary) -> void:
	if not visible:
		return
	failed = false
	var now := Time.get_unix_time_from_system()
	var when: String = {"daily": "Daily %s (UTC)" % Online.utc_date(now), "season": "Season %s" % Online.season_week(now)}.get(kind, "")
	status.text = when if not rows.is_empty() else (when + "  -  " if when != "" else "") + "No entries yet."
	_fill(rows, own_row)


func _on_board_failed(error: String) -> void:
	if not visible:
		return
	failed = true
	if error == "offline":
		_show_offline()
	else:
		status.text = Online.error_text(error)
		_fill([], {})


func _on_online(on: bool) -> void:
	if on and visible and failed:
		show_kind(kind)


## Shows rows without Online (tests, and _on_board).
func show_rows(k: String, rows: Array, own_row: Dictionary) -> void:
	kind = k
	_mark_tabs()
	visible = true
	_on_board(rows, own_row)


func _mark_tabs() -> void:
	for t in tab_btns:
		tab_btns[t].button_pressed = t == kind
	for s in scope_btns:
		scope_btns[s].button_pressed = s == kind or s == "points" and kind in TABS
	tabs.visible = kind in TABS


func _fill(rows: Array, own_row: Dictionary) -> void:
	for c in list.get_children() + own_slot.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	own_id = str(own_row.get("player_id", ""))
	for r in rows:
		list.add_child(_row(r, own_id != "" and str(r.get("player_id", "")) == own_id))
	if not own_row.is_empty(): # also outside the top 50, so it is always on screen
		own_slot.add_child(_row(own_row, true))


func _row(r: Dictionary, mine: bool) -> Control:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 40)
	if mine:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(ACCENT, 0.22)
		sb.border_width_left = 4
		sb.border_color = ACCENT
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 10)
	var col := ACCENT if mine else SAND
	var rank := label("#%d" % int(r.get("rank", 0)), 16, col)
	rank.custom_minimum_size.x = 56
	h.add_child(_pass(rank))
	h.add_child(_pass(portrait(int(r.get("avatar", 0)), 32)))
	var nm := label(str(r.get("name", "?")), 16, col)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_pass(nm))
	var val := label(_value(r), 16, col)
	val.custom_minimum_size.x = 150
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(_pass(val))
	b.add_child(h)
	b.pressed.connect(func(): show_player(r))
	return b


func _pass(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _value(r: Dictionary) -> String:
	var v := str(int(r.get("value", 0)))
	if kind in ["best_run", "daily"] and r.has("day"):
		v += "  (day %d%s)" % [int(r["day"]), " WIN" if r.get("victory", false) else ""]
	return v


func show_player(r: Dictionary) -> void:
	if not r.has("player_id"):
		return
	player_id = r["player_id"]
	detail.text = "%s  -  loading..." % r.get("name", "?")
	Online.fetch_player(player_id)


func _on_player(stats: Dictionary) -> void:
	if not visible or stats["player_id"] != player_id:
		return
	player_id = ""
	var best: Dictionary = stats["best"]
	var lines: PackedStringArray = [stats["name"]]
	lines.append("%-18s %d  (#%d)" % ["Points", stats["points"], stats["points_rank"]])
	lines.append("%-18s %d" % ["Days survived", stats["days"]]) # summed over all runs
	lines.append("%-18s %d" % ["Rescued", stats["rescued"]])
	lines.append("%-18s %d" % ["Kills", stats["kills"]])
	if stats["runs"] >= 0: # only known for yourself
		lines.append("%-18s %d" % ["Runs", stats["runs"]])
		lines.append("%-18s %d" % ["Victories", stats["wins"]])
	if not best.is_empty():
		lines.append("%-18s %d  (day %d%s)" % ["Best run", best["value"], best["day"], ", victory" if best.get("victory", false) else ""])
	detail.text = "\n".join(lines)


func _on_player_failed(error: String) -> void:
	if not visible or player_id == "":
		return
	player_id = ""
	match error:
		"no_runs": detail.text = "No runs on the boards yet."
		"offline": detail.text = "Offline: no details."
		_: detail.text = Online.error_text(error)


## No connection: the local record of the active profile (the server computes points, so none here).
func _show_offline() -> void:
	status.text = "Leaderboard offline."
	_fill([], {})
	var m: Dictionary = Game.meta
	var p := Profiles.active()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(portrait(p.get("avatar", 0)))
	row.add_child(label(p.get("name", "?"), 18, ACCENT))
	list.add_child(row)
	list.add_child(label("YOUR LOCAL RECORD", 13, OLIVE.lightened(0.5)))
	list.add_child(label("sorties %d\nrescued %d\nkills %d\nbest day %d" % [m["runs"], m["total_rescued"], m["total_kills"], m["best_day"]], 16, SAND))
