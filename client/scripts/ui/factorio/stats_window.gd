extends PanelContainer
## Factorio's statistics windows, laid out as 2.1 draws them at 1920x1080:
##
## - Production (P): "<Planet> production" with the planet's icon, search and close in the title
##   bar; a full-width row of time scales (5s ... 1000h, All, the chosen one orange); the tabs
##   Items, Fluids, Buildings, Pollution and Kills (K opens this one); then two panels side by side,
##   "Production" and "Consumption" (Kills: "Kills" and "Losses"), each with a "Universe statistics"
##   box (every surface instead of the character's), the quality dropdown, a red reset button, a
##   graph and a two-column grid of rows: the item's slot with how many in that time, a bar in its
##   line's colour and the rate ("2.4k/m").
## - Electric network info (a pole's screen): three summary bars (Satisfaction, Production,
##   Accumulator charge), the time scales, then three panels (Consumption, Production, Accumulator
##   charge) with graphs and rows.
##
## Clicking a row draws its line in the graphs or takes it away; reset goes back to the busiest.
## "All" shows the all-time totals (the API has no "all" time scale: its graph is the 1000 h one;
## the mod picks and orders its rows by the totals).
## From the mod's `stats` (LuaFlowStatistics), asked for once a second while open.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const Info := preload("res://scripts/ui/factorio/info_text.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")

signal close_requested

const SCALES := ["5s", "1m", "10m", "1h", "10h", "50h", "250h", "1000h", "All"]
## Seconds each time scale covers, for the graph's axis and the slots' counts.
const SCALE_SECONDS := [5, 60, 600, 3600, 36000, 180000, 900000, 3600000, 3600000]
## The "All" button: the mod answers with the 1000 h rates and graph and the rows by totals.
const ALL := 9
const REFRESH := 1.0
## Factorio's windows at 1920x1080, 100% (GUI pixels).
const WIDTH := 1172
const ELECTRIC_WIDTH := 1738
const HEIGHT := 928
const TOP := 27
const ROW_HEIGHT := 56
const GRAPH_HEIGHT := 214
const GRAPH_LINES := 8
## Factorio's graph colours, in order.
const PALETTE := [Color8(30, 110, 255), Color8(255, 100, 0), Color8(80, 190, 20), Color8(220, 20, 40),
	Color8(230, 170, 0), Color8(225, 20, 225), Color8(20, 190, 200), Color8(150, 75, 20)]
## A row without a line: a dull bar.
const NO_LINE := Color8(110, 104, 60)
## The production window's tabs.
const TABS := [["item", "Items"], ["fluid", "Fluids"], ["build", "Buildings"], ["pollution", "Pollution"], ["kill", "Kills"]]
const PRODUCTION := ["item", "fluid", "build", "pollution", "kill"]


## A graph: lines of the drawn rows over the time scale, a grid, the values up the left and the
## time (in the scale's unit, oldest left) along the bottom, as Factorio's.
class Graph extends Control:
	const K := preload("res://scripts/ui/factorio/kit.gd")
	var lines: Array = []  # [name, [values...]]
	var colors := {}  # name -> Color
	var unit := ""  # "W", "J" or "" (counts)
	var seconds := 5

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(14, 14, 14))
		var font := K.font("regular")
		var fs := K.px(11)
		var left := K.px(52 if unit != "" else 36)
		var plot := Rect2(left, K.px(8), size.x - left - K.px(8), size.y - K.px(26))
		var top := 0.0
		for l in lines:
			for v in l[1]:
				top = maxf(top, float(v))
		var steps := 7
		for i in steps + 1:
			var y := plot.end.y - plot.size.y * i / float(steps)
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.07), 1.0)
			if font != null and (top > 0.0 or i == 0):
				draw_string(font, Vector2(0, y + fs * 0.35), short(top * i / float(steps)), HORIZONTAL_ALIGNMENT_RIGHT, left - K.px(4), fs, Color(0.75, 0.75, 0.75))
		var ticks := 18
		var span := axis_span()
		for i in ticks + 1:
			var x := plot.position.x + plot.size.x * i / float(ticks)
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(1, 1, 1, 0.07), 1.0)
			if font != null and i % 2 == 0:
				var t := float(span[0]) * (1.0 - i / float(ticks))
				draw_string(font, Vector2(x - K.px(20), plot.end.y + fs + K.px(4)), _num(t), HORIZONTAL_ALIGNMENT_CENTER, K.px(40), fs, Color(0.75, 0.75, 0.75))
		if top <= 0.0:
			return
		for l in lines:
			var vals: Array = l[1]
			if vals.size() < 2:
				continue
			var pts := PackedVector2Array()
			for i in vals.size():
				pts.append(Vector2(plot.position.x + plot.size.x * i / float(vals.size() - 1), plot.end.y - plot.size.y * float(vals[i]) / top))
			draw_polyline(pts, colors.get(str(l[0]), Color.WHITE), 1.0, true)

	## [how many of the unit the graph spans, the unit's name]: 5 (s), 60 (s), 10 (m), 60 (m)...
	func axis_span() -> Array:
		if seconds <= 60:
			return [float(seconds), "s"]
		if seconds <= 3600:
			return [seconds / 60.0, "m"]
		return [seconds / 3600.0, "h"]

	static func _num(v: float) -> String:
		if v >= 10.0 or is_equal_approx(v, roundf(v)):
			return str(roundi(v))
		return str(snappedf(v, 0.1))

	func short(v: float) -> String:
		if unit != "":
			return Info.joules(v) if unit == "J" else Info.watts(v / 60.0)  # joules per minute
		if v >= 1e6:
			return "%.1fM" % (v / 1e6)
		if v >= 1e3:
			return "%.1fk" % (v / 1e3)
		return str(roundi(v))


var model

## "item", "fluid", "build", "pollution", "kill" or "electric"; the pole for "electric" ({u, p, x, y}).
var kind := "item"
var target := {}
## 1-8 Factorio's time scales, 9 "All".
var prec := 1
## The surface shown: 0 every surface (Universe statistics), -1 the character's.
var surface := -1
## The rows drawn in the graphs; empty: the busiest of each side.
var graph_names: Array = []
var search := ""

var _title: Label
var _planet_icon := TextureRect.new()
var _search_box := LineEdit.new()
var _tabs := HBoxContainer.new()
var _scales := HBoxContainer.new()
var _body := VBoxContainer.new()
var _summary := HBoxContainer.new()
## One per panel: {"box", "head", "title", "universe", "graph", "grid", "side"}.
var _sides: Array = []
var _tab_pane: PanelContainer
var _panels := HBoxContainer.new()
var _timer := 0.0
var _colors := {}
var _rows: Array = []
var _storage: Array = []
## The summary bars of the electric window: [bar, text].
var _bars := {}
## Compatibility with the old layout's names (tests).
var _in_graph: Graph:
	get:
		return _sides[0]["graph"] if _sides.size() > 0 else null
var _out_graph: Graph:
	get:
		return _sides[1]["graph"] if _sides.size() > 1 else null


func _ready() -> void:
	theme = MenuKit.theme()
	theme_type_variation = "FFrame"
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Production statistics", true)
	_title = bar.get_child(0)
	_planet_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_planet_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_planet_icon.custom_minimum_size = Kit.pxv(24, 24)
	_planet_icon.texture_filter = Kit.ICON_FILTER
	bar.add_child(_planet_icon)
	bar.move_child(_planet_icon, 0)
	_search_box.placeholder_text = "Search"
	_search_box.custom_minimum_size = Kit.pxv(200, 24)
	_search_box.visible = false
	_search_box.text_changed.connect(func(t: String) -> void:
		search = t.strip_edges().to_lower()
		_fill())
	bar.add_child(_search_box)
	bar.move_child(_search_box, bar.get_child_count() - 2)
	var glass := Kit.close_button()
	glass.name = "Search"
	glass.tooltip_text = "Search (Ctrl+F)"
	var icon := GuiAssets.core_sprite("icons/search.png")
	if icon != null:
		glass.icon = icon
	glass.pressed.connect(toggle_search)
	bar.add_child(glass)
	bar.move_child(glass, bar.get_child_count() - 2)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: close_requested.emit())
	box.add_child(bar)

	_summary.add_theme_constant_override("separation", Kit.px(12))
	box.add_child(_summary)
	for s in [["Satisfaction", "How much of the demand the network meets"], ["Production", "What the network's producers give"],
			["Accumulator charge", "Energy stored in the network's accumulators"]]:
		_summary.add_child(_summary_bar(s[0], s[1]))

	_scales.add_theme_constant_override("separation", Kit.px(4))
	box.add_child(_scales)
	for i in SCALES.size():
		var b := Button.new()
		b.name = "Scale" + SCALES[i]
		b.text = SCALES[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = Kit.px(28)
		b.add_theme_stylebox_override("pressed", Kit.style("button_selected"))
		b.add_theme_stylebox_override("hover_pressed", Kit.style("button_selected"))
		var index := i + 1
		b.pressed.connect(func() -> void: _set_prec(index))
		_scales.add_child(b)

	box.add_child(_body)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 0)
	_tabs.add_theme_constant_override("separation", Kit.px(2))
	var tab_row := MarginContainer.new()  # Factorio's tabs start 12 in from the pane's edge
	tab_row.add_theme_constant_override("margin_left", Kit.px(12))
	tab_row.add_child(_tabs)
	_body.add_child(tab_row)
	for t in TABS:
		var b := Button.new()
		b.name = "Tab" + str(t[1])
		b.text = t[1]
		b.theme_type_variation = "FTab"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(82, 34)
		b.set_meta("kind", t[0])
		var k: String = t[0]
		b.pressed.connect(func() -> void: _switch_tab(k))
		_tabs.add_child(b)
	_tab_pane = Kit.panel("FTabPane")
	_tab_pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_tab_pane)
	_panels.add_theme_constant_override("separation", Kit.px(12))
	_tab_pane.add_child(_panels)
	for i in 3:
		_sides.append(_side(i))
	model.stats_received.connect(_on_stats)


## A summary bar of the electric window: its title with Factorio's (i), and a bar with the text
## right-aligned on it.
func _summary_bar(title: String, tip: String) -> Control:
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	frame.add_child(v)
	var head := Kit.panel("FSubheader")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", Kit.px(4))
	hb.add_child(Kit.label(title, "FHeading"))
	var info := TextureRect.new()
	info.texture = GuiAssets.core_sprite("icons/mip/info-blue.png")
	info.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	info.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	info.custom_minimum_size = Kit.pxv(12, 12)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.tooltip_text = tip
	hb.add_child(info)
	head.add_child(hb)
	v.add_child(head)
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_left", Kit.px(4))
	holder.add_theme_constant_override("margin_right", Kit.px(4))
	holder.add_theme_constant_override("margin_top", Kit.px(4))
	holder.add_theme_constant_override("margin_bottom", Kit.px(4))
	var b := Kit.progress_bar(Color8(255, 210, 60) if title == "Accumulator charge" else Kit.BAR_GREEN)
	b.custom_minimum_size.y = Kit.px(20)
	b.max_value = 1.0
	holder.add_child(b)
	var text := Kit.label("0 W / 0 W")
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(text)
	v.add_child(holder)
	_bars[title] = [b, text]
	return frame


## One of the panels: a subheader (title, Universe statistics, the quality dropdown, reset), the
## graph, the rows.
func _side(index: int) -> Dictionary:
	var frame := Kit.panel("FDeepFrame")
	frame.name = "Side%d" % index
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_stretch_ratio = 1.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	frame.add_child(v)
	var head := Kit.panel("FSubheader")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", Kit.px(8))
	head.add_child(hb)
	var title := Kit.label("Production", "FHeading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(title)
	var universe := MenuKit.checkbox("Universe statistics", false)
	universe.name = "Universe"
	universe.tooltip_text = "Statistics of every surface instead of this one"
	universe.toggled.connect(func(on: bool) -> void: _set_surface(0 if on else -1))
	hb.add_child(universe)
	var quality := OptionButton.new()
	quality.focus_mode = Control.FOCUS_NONE
	quality.custom_minimum_size = Kit.pxv(140, 28)
	quality.add_icon_item(GuiAssets.core_sprite("icons/any-quality.png"), "All (separate)")
	quality.add_theme_constant_override("icon_max_width", Kit.px(20))
	quality.tooltip_text = "Quality"
	hb.add_child(quality)
	var reset := Button.new()
	reset.name = "Reset"
	reset.theme_type_variation = "FRedButton"
	reset.focus_mode = Control.FOCUS_NONE
	reset.custom_minimum_size = Kit.pxv(28, 28)
	reset.tooltip_text = "Reset the graph to the busiest"
	reset.icon = GuiAssets.core_sprite("icons/mip/reset.png")
	reset.expand_icon = true
	reset.add_theme_constant_override("icon_max_width", Kit.px(16))
	reset.pressed.connect(reset_lines)
	hb.add_child(reset)
	v.add_child(head)
	var graph := Graph.new()
	graph.custom_minimum_size.y = Kit.px(GRAPH_HEIGHT)
	graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(graph)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	v.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", Kit.px(2))
	grid.add_theme_constant_override("v_separation", Kit.px(2))
	scroll.add_child(grid)
	_panels.add_child(frame)
	return {"box": frame, "title": title, "universe": universe, "quality": quality, "graph": graph, "grid": grid, "side": index}


## Opens it on a kind ("item" / "fluid" / "build" / "pollution" / "kill" production tabs,
## "electric" with the pole), or closes it when it already shows that.
func toggle(new_kind: String, new_target := {}) -> void:
	if visible and new_target == target and (kind == new_kind or (new_kind == "item" and kind in PRODUCTION)):
		visible = false
		return
	var was_electric := kind == "electric"
	kind = new_kind
	target = new_target
	visible = true
	if was_electric != (kind == "electric"):
		graph_names = []
	_rows = []
	_storage = []
	_setup()
	_set_prec(prec)


func is_open() -> bool:
	return visible


func toggle_search() -> void:
	_search_box.visible = not _search_box.visible
	if _search_box.visible:
		_search_box.grab_focus()
	else:
		_search_box.text = ""
		search = ""
		_fill()


## Factorio's names for the two sides of each tab.
func _columns() -> Array:
	match kind:
		"kill":
			return ["Kills", "Losses"]
		"electric":
			return ["Consumption", "Production", "Accumulator charge"]
		"build":
			return ["Built", "Removed"]
	return ["Production", "Consumption"]


func _setup() -> void:
	var electric := kind == "electric"
	if electric:
		_title.text = "Electric network info"
		_planet_icon.visible = false
	else:
		var planet := str(model.planet.get("name", "")) if model.planet is Dictionary else ""
		var place := LocaleNames.space_location(planet) if planet not in ["", "space"] else "Platform"
		_title.text = "%s production" % place
		_planet_icon.texture = _planet_texture(planet)
		_planet_icon.visible = _planet_icon.texture != null
	_summary.visible = electric
	_tabs.visible = not electric
	_tab_pane.theme_type_variation = "FTabPane" if not electric else ""
	if electric:
		_tab_pane.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		_tab_pane.remove_theme_stylebox_override("panel")
	for b in _tabs.get_children():
		(b as Button).set_pressed_no_signal(str(b.get_meta("kind")) == kind)
	var names := _columns()
	for s in _sides:
		var i: int = s["side"]
		s["box"].visible = i < names.size()
		if i < names.size():
			s["title"].text = names[i]
		s["universe"].visible = not electric
		s["universe"].set_pressed_no_signal(surface == 0)
	_layout()


func _planet_texture(planet: String) -> Texture2D:
	if planet in ["", "space"]:
		return GuiAssets.data_sprite("space-age/graphics/icons/space-platform-hub.png")
	var icon := GuiAssets.data_sprite("space-age/graphics/icons/%s.png" % planet)
	if icon == null:
		icon = GuiAssets.data_sprite("base/graphics/icons/%s.png" % planet)
	return icon


## Factorio's size and place: centred, near the top, nearly the whole height.
func _layout() -> void:
	var view := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var w := minf(Kit.px(ELECTRIC_WIDTH if kind == "electric" else WIDTH), view.x - Kit.px(8))
	var h := minf(Kit.px(HEIGHT), view.y - Kit.px(TOP) - Kit.px(125))
	custom_minimum_size = Vector2(w, maxf(h, Kit.px(400)))
	size = custom_minimum_size
	position = Vector2(roundf((view.x - size.x) / 2.0), minf(Kit.px(TOP), maxf(0.0, view.y - size.y)))


func _switch_tab(k: String) -> void:
	kind = k
	graph_names = []
	_rows = []
	_setup()
	_request()


func _set_surface(si: int) -> void:
	surface = si
	for s in _sides:
		s["universe"].set_pressed_no_signal(surface == 0)
	_request()


func _set_prec(p: int) -> void:
	prec = clampi(p, 1, ALL)
	for i in _scales.get_child_count():
		(_scales.get_child(i) as Button).set_pressed_no_signal(i + 1 == prec)
	_request()


func reset_lines() -> void:
	graph_names = []
	_request()


func _request() -> void:
	_timer = REFRESH
	var g: Array = graph_names if not graph_names.is_empty() else _busiest()
	model.request_stats(kind, prec, target, surface if kind != "electric" else -1, g)


## The rows the graphs show by default: the busiest few of each side ([] before the first answer,
## which the mod reads as its five busiest).
func _busiest() -> Array:
	var out: Array = []
	var per := GRAPH_LINES / 2
	for side in 2:
		var sorted := _sorted(side)
		for i in mini(per, sorted.size()):
			if not out.has(sorted[i][0]):
				out.append(sorted[i][0])
	return out


func _process(delta: float) -> void:
	if not visible:
		return
	_layout()
	_timer -= delta
	if _timer <= 0.0:
		_request()


## The rows of one side, busiest first (totals for All), without the ones with nothing.
func _sorted(side: int) -> Array:
	var col := 1 + side if prec != ALL else 3 + side
	var out: Array = []
	for r in _rows:
		if r is Array and r.size() >= 5 and float(r[col]) > 0.0:
			out.append(r)
	out.sort_custom(func(a: Array, b: Array) -> bool:
		if float(a[col]) != float(b[col]):
			return float(a[col]) > float(b[col])
		return str(a[0]) < str(b[0]))
	return out


func _on_stats(got_kind: String, got_prec: int, rows: Array) -> void:
	# An older mod answers "All" (9) with 8.
	if not visible or got_kind != kind or (got_prec != prec and not (prec == ALL and got_prec == 8)):
		return
	_rows = rows
	_storage = model.stats_storage
	_colors.clear()
	var lines: Array = model.stats_graph
	for i in lines.size():
		if lines[i] is Array and lines[i].size() >= 3:
			_colors[str(lines[i][0])] = PALETTE[i % PALETTE.size()]
	for s in _sides:
		var g: Graph = s["graph"]
		var side: int = s["side"]
		g.lines = []
		for l in lines:
			if l is Array and l.size() >= 3 and side < 2:
				g.lines.append([l[0], l[1 + side]])
		g.colors = _colors
		g.unit = "W" if kind == "electric" else ""
		if kind == "electric" and side == 2:
			g.unit = "J"
		g.seconds = SCALE_SECONDS[prec - 1]
		g.queue_redraw()
	if kind == "electric":
		_update_summary()
	_fill()


## Satisfaction, production and accumulator charge: the network's last update when the mod sends
## it (LuaElectricNetwork.flow_last_tick), else worked out from the statistics.
func _update_summary() -> void:
	var f: Array = model.stats_flow
	if f.size() >= 6:
		var tick := func(i: int) -> float: return float(f[i]) * 60.0
		var demand: float = tick.call(1)
		var avail: float = tick.call(3)
		_set_bar("Satisfaction", float(f[0]) / float(f[1]) if float(f[1]) > 0.0 else 0.0,
			"%s / %s" % [Info.watts(tick.call(0)), Info.watts(demand)])
		_set_bar("Production", float(f[2]) / float(f[3]) if float(f[3]) > 0.0 else 0.0,
			"%s / %s" % [Info.watts(tick.call(2)), Info.watts(avail)])
		_set_bar("Accumulator charge", float(f[4]) / float(f[5]) if float(f[5]) > 0.0 else 0.0,
			"%s / %s" % [Info.joules(float(f[4])), Info.joules(float(f[5]))])
		return
	var used := 0.0
	var made := 0.0
	for r in _rows:
		if r is Array and r.size() >= 5:
			used += float(r[1]) / 60.0
			made += float(r[2]) / 60.0
	var met := minf(used, made) if used > 0.0 else 0.0
	_set_bar("Satisfaction", met / used if used > 0.0 else 0.0, "%s / %s" % [Info.watts(met), Info.watts(used)])
	_set_bar("Production", 1.0 if made > 0.0 else 0.0, "%s / %s" % [Info.watts(made), Info.watts(made)])
	# The statistics hold what is stored, not the accumulators' capacity: the bar stays empty.
	var stored := 0.0
	for r in _storage:
		if r is Array and r.size() >= 3:
			stored += float(r[2])
	_set_bar("Accumulator charge", 0.0, Info.joules(stored))


func _set_bar(title: String, value: float, text: String) -> void:
	var pair: Array = _bars[title]
	(pair[0] as ProgressBar).value = clampf(value, 0.0, 1.0)
	(pair[1] as Label).text = text


## Refills each side's grid from the last answer and the search.
func _fill() -> void:
	for s in _sides:
		var grid: GridContainer = s["grid"]
		for c in grid.get_children():
			grid.remove_child(c)
			c.queue_free()
		if not s["box"].visible:
			continue
		var side: int = s["side"]
		var rows: Array = _sorted(side) if side < 2 else _storage_rows()
		var col := (1 + side if prec != ALL else 3 + side) if side < 2 else 2
		var top := 0.0
		for r in rows:
			top = maxf(top, float(r[col]))
		var shown := 0
		for r in rows:
			if search != "" and not _display(str(r[0])).to_lower().contains(search):
				continue
			grid.add_child(_cell(r, side, col, top))
			shown += 1
		# Factorio fills the panel with empty rows.
		var want := maxi(shown + shown % 2, 2 * 8)
		for i in want - shown:
			grid.add_child(_blank())


func _storage_rows() -> Array:
	var out: Array = []
	for r in _storage:
		if r is Array and r.size() >= 3:
			out.append(r)
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
	return out


func _row_style() -> StyleBox:
	var s := StyleBoxFlat.new()
	s.bg_color = Color8(62, 62, 62)
	s.content_margin_left = Kit.px(8)
	s.content_margin_right = Kit.px(12)
	return s


func _blank() -> Control:
	var p := PanelContainer.new()
	var s := _row_style()
	s.bg_color = Color8(42, 42, 42)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size.y = Kit.px(ROW_HEIGHT)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A row: the slot (how many in the time scale, or in all), a bar in the line's colour against the
## busiest row, and the rate. Clicking it draws or removes its line.
func _cell(r: Array, side: int, col: int, top: float) -> Control:
	var name := str(r[0])
	var p := PanelContainer.new()
	p.name = "Row_" + name
	p.add_theme_stylebox_override("panel", _row_style())
	p.custom_minimum_size.y = Kit.px(ROW_HEIGHT)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			toggle_line(name))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", Kit.px(10))
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	var s := Slot.new()
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value := float(r[col])
	var count := -1
	if kind != "electric":
		count = roundi(value) if prec == ALL else roundi(value * SCALE_SECONDS[prec - 1] / 60.0)
	s.set_stack(name, count)
	var names := _columns()
	if side < 2 and r.size() >= 5:
		s.set_tip(_display(name), [["%s: %s in all" % [names[0], Kit.count_text(int(r[3]))]], ["%s: %s in all" % [names[1], Kit.count_text(int(r[4]))]]])
	else:
		s.set_tip(_display(name))
	s.pressed.connect(func() -> void: toggle_line(name))
	hb.add_child(s)
	var b := Kit.progress_bar(_colors.get(name, NO_LINE))
	b.max_value = maxf(top, 0.0001)
	b.value = value
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Kit.pxv(60, 8)
	hb.add_child(b)
	var l := Kit.label(_value_text(value, side))
	l.custom_minimum_size.x = Kit.px(64)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_FILL
	hb.add_child(l)
	return p


## Draws a row's line in the graphs or takes it away; the first click replaces the busiest.
func toggle_line(name: String) -> void:
	if graph_names.is_empty():
		graph_names = _colors.keys()
	if graph_names.has(name):
		graph_names.erase(name)
		if graph_names.is_empty():
			graph_names = ["-"]  # none drawn (an unknown name gets no line)
	else:
		graph_names.erase("-")
		graph_names.append(name)
		while graph_names.size() > GRAPH_LINES:
			graph_names.pop_front()
	_request()


func _display(name: String) -> String:
	if kind in ["electric", "kill", "build", "pollution"]:
		return Kit.entity_name(name)
	if kind == "fluid":
		return Info.display_name("fluid", name)
	return Kit.pretty(name)


## Rates as Factorio writes them: "2.4k/m" (per minute averaged over the time scale), totals for
## All, watts for electricity (joules per minute / 60), joules stored for accumulators.
func _value_text(v: float, side: int) -> String:
	if kind == "electric":
		return Info.joules(v) if side == 2 else Info.watts(v / 60.0)
	if prec == ALL:
		return Kit.count_text(roundi(v))
	if v >= 1000.0:
		return Kit.count_text(roundi(v)) + "/m"
	return ("%.1f" % v).trim_suffix(".0") + "/m"


## Ctrl+F while open: the search.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k != null and k.pressed and k.ctrl_pressed and k.keycode == KEY_F:
		toggle_search()
		get_viewport().set_input_as_handled()
