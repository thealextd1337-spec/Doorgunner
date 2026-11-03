extends Overlay
## The trade window (docs/ROADMAP3.md S2), T / TRADE beside an allied village: today's offer of the village to buy with scrap, and
## the surplus food and water to sell. Pauses the game while open, like the help screen. Prices and stock live in trade.gd.

const WIDTH := 560

var village := ""
var note := ""
var was_paused := false
var prev_ui_open := false
var buy_btns: Array[Button] = [] # per offer line, for tests
var sell_btns := {} # good -> Button


func _ready() -> void:
	_build(WIDTH)
	box.theme = UiTheme.theme()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("trade"):
		if visible:
			close()
			get_viewport().set_input_as_handled()
		elif Game.world.trade.can_open() and not Game.world.ui_open and not get_tree().paused:
			open()
			get_viewport().set_input_as_handled()
	else:
		super._input(event)


func open() -> void:
	village = Game.world.trade.village_here().get("id", "")
	if village == "":
		return
	was_paused = get_tree().paused
	prev_ui_open = Game.world.ui_open
	Game.world.ui_open = true
	get_tree().paused = true
	note = ""
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = was_paused
	Game.world.ui_open = prev_ui_open
	Sfx.play("ui")


func refresh() -> void:
	var tr: Node = Game.world.trade
	clear()
	buy_btns.clear()
	sell_btns.clear()
	box.add_child(label("TRADE  -  %s" % tr._name(village).to_upper(), UiTheme.FONT_XL, ACCENT))
	box.add_child(label("Scrap: %d" % Game.scrap, UiTheme.FONT_L))
	box.add_child(label("BUY  (prices rise with every purchase and fall back over the days)", UiTheme.FONT, ACCENT))
	var list: Array = tr.offer(village)
	for i in list.size():
		var why: String = tr.buy_problem(village, i)
		var b := _row(tr.offer_text(list[i]) + ("" if list[i]["left"] > 0 else "  (sold out)"), "%d scrap" % tr.price(village, i), "Buy", why)
		b.tooltip_text = why if why != "" else Tooltips.tip("trade_buy")
		b.pressed.connect(_do.bind(true, i, ""))
		buy_btns.append(b)
	box.add_child(label("SELL  (poor rates, the base keeps a few days of supplies)", UiTheme.FONT, ACCENT))
	for good in tr.SELL:
		var why: String = tr.sell_problem(village, good)
		var b := _row("%s x%d   (base: %d)" % [tr.SELL[good]["label"], tr.SELL[good]["unit"], int(Game.base_food if good == "food" else Game.base_water)],
			"%d scrap" % tr.payout(village, good), "Sell", why)
		b.tooltip_text = why if why != "" else Tooltips.tip("trade_sell")
		b.pressed.connect(_do.bind(false, 0, good))
		sell_btns[good] = b
	box.add_child(label(note, UiTheme.FONT, UiTheme.DIM))
	var close_btn := button("Close  [%s]" % KeyMap.text("trade"), 0, true)
	close_btn.custom_minimum_size.y = UiTheme.TOUCH_MIN
	close_btn.tooltip_text = Tooltips.tip("trade_close")
	close_btn.pressed.connect(close)
	box.add_child(close_btn)


## A line: text (grows), price, button (greyed out when `why` is not empty).
func _row(text: String, price: String, verb: String, why: String) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var l := label(text, UiTheme.FONT_M, SAND if why == "" else UiTheme.DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(label(price, UiTheme.FONT_M, ACCENT))
	var b := button(verb, 90)
	b.custom_minimum_size.y = UiTheme.TOUCH_MIN
	b.disabled = why != ""
	row.add_child(b)
	return b


func _do(buying: bool, i: int, good: String) -> void:
	var tr: Node = Game.world.trade
	note = tr.buy_problem(village, i) if buying else tr.sell_problem(village, good)
	if note == "":
		if buying:
			tr.buy(village, i)
		else:
			tr.sell(village, good)
		note = "Done."
	refresh()
