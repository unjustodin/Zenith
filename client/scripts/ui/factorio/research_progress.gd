extends PanelContainer
## The research in progress at the top of the side menu (side_menu.gd), as Factorio 2.1 draws it:
## a 240x40 panel with the technology's icon, its name, a thin bar and the percentage right of it.
## Without research it says "Press T to start a new research." beside the technology icon; when
## a research finishes it says "<name> finished. Press T." over a full bar until the next one
## starts. Click opens the technology screen (T).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Controls := preload("res://scripts/player/controls.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")

signal open_requested

const KEY_COLOR := Kit.KEY_TEXT
const TECHNOLOGY_ICON := 11  # side_menu_technology_icon's row

var model

var _icon := TextureRect.new()
var _name: Label
var _bar: ProgressBar
var _percent: Label
var _bar_row := HBoxContainer.new()
var _hint := HBoxContainer.new()
var _row := HBoxContainer.new()
var _key: Label
var _shown := "-"
var _last := ""  # the research seen last, to notice it finishing
var finished := ""  # the technology that just finished, shown until the next research starts
## The research's progress seen over time, for the tooltip's graph: [msec, technology, units done].
var _samples: Array = []
const SAMPLE_MS := 2000
const GRAPH_MINUTES := 10
const BUCKET_S := 10  # the graph's step
var _hovered := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Kit.pxv(240, 40)
	var row := _row
	row.add_theme_constant_override("separation", Kit.px(8))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Kit.pxv(32, 32)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.texture_filter = Kit.ICON_FILTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_name = Kit.label("", "FHeading")
	_name.add_theme_color_override("font_color", Kit.WHITE)
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_name)
	_bar_row.add_theme_constant_override("separation", Kit.px(8))
	_bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_bar_row)
	_bar = Kit.progress_bar(Kit.BAR_GREEN)
	_bar.max_value = 1000
	_bar.custom_minimum_size = Kit.pxv(40, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar_row.add_child(_bar)
	_percent = Kit.label("0%")
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_percent.custom_minimum_size.x = Kit.px(30)
	_percent.add_theme_font_size_override("font_size", Kit.px(13))
	_bar_row.add_child(_percent)
	# "Press T to start a new research." (the key in blue)
	_hint.add_theme_constant_override("separation", 0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bold := Kit.font("semibold")
	_key = Kit.label("T")
	for part: Label in [Kit.label("Press "), _key, Kit.label(" to start a new research.")]:
		part.add_theme_font_override("font", bold)
		_hint.add_child(part)
	_key.add_theme_color_override("font_color", KEY_COLOR)
	row.add_child(_hint)
	model.research_changed.connect(_refresh)
	_refresh()


## Factorio's "Science production information" tooltip: the title with the small flask, the graph
## of science per minute over the last 10 minutes (minutes along the bottom), "Progress: done /
## total", "Science per minute", "Remaining time estimate", and the cost of one unit (each pack, the
## clock) times the units. The game doesn't send its science history, so the graph and the rate
## come from the progress the client has seen since it started. Idle, the plain "Technologies (T)".
func _make_custom_tooltip(for_text: String) -> Object:
	var tech := str(model.research)
	if tech == "":
		return Kit.simple_tooltip(for_text)
	var t: Dictionary = model.techs.get(tech, {})
	var count := int(t.get("count", 0))
	var box := VBoxContainer.new()
	box.name = "ScienceTooltip"
	box.add_theme_constant_override("separation", Kit.px(6))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Kit.px(6))
	var flask := TextureRect.new()
	flask.texture = GuiAssets.side_menu_icon(TECHNOLOGY_ICON)
	flask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flask.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flask.custom_minimum_size = Kit.pxv(16, 16)
	head.add_child(flask)
	head.add_child(Kit.label("Science production information", "FHeading"))
	box.add_child(head)
	var graph := Graph.new()
	graph.values = per_minute(tech)
	graph.custom_minimum_size = Kit.pxv(540, 200)
	box.add_child(graph)
	var done := floori(float(model.research_progress) * count)
	var rate := rate_now(tech)
	var lines: Array = []
	if count > 0:
		lines.append("Progress: %d / %d" % [done, count])
	lines.append("Science per minute: %s" % _num(rate))
	if count > 0 and rate > 0.0:
		lines.append("Remaining time estimate: %s" % duration((count - done) / rate * 60.0))
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		for l in Kit.key_value_labels(line):
			row.add_child(l)
		box.add_child(row)
	var cost := HBoxContainer.new()
	cost.add_theme_constant_override("separation", Kit.px(8))
	var packs := Kit.panel("FDeepFrame")
	var pack_row := HBoxContainer.new()
	pack_row.add_theme_constant_override("separation", Kit.px(4))
	packs.add_child(pack_row)
	for ing in t.get("ingredients", []):
		if ing is Array and ing.size() >= 2:
			var slot := Slot.new()
			slot.theme_type_variation = "FSlot"
			slot.set_stack(str(ing[0]), int(ing[1]))
			pack_row.add_child(slot)
	if float(t.get("seconds", 0.0)) > 0.0:
		var clock := Kit.label("⏱ %s" % _num(float(t["seconds"])))
		clock.add_theme_font_override("font", Kit.font("bold"))
		clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pack_row.add_child(clock)
	cost.add_child(packs)
	if count > 0:
		var times := Kit.label("× %d" % count)
		times.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost.add_child(times)
	box.add_child(cost)
	return box


## Factorio's durations: "24m6s", "1h2m", "45s".
static func duration(seconds: float) -> String:
	var s := roundi(seconds)
	if s >= 3600:
		return "%dh%dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm%ds" % [s / 60, s % 60]
	return "%ds" % s


static func _num(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.05 else "%.1f" % v


## Notes the research's progress every couple of seconds (the graph's data).
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not _samples.is_empty() and now - int(_samples[-1][0]) < SAMPLE_MS:
		return
	var tech := str(model.research)
	if tech == "":
		return
	note_progress(now, tech, float(model.research_progress) * int((model.techs.get(tech, {}) as Dictionary).get("count", 0)))


func note_progress(now: int, tech: String, units: float) -> void:
	_samples.append([now, tech, units])
	while not _samples.is_empty() and now - int(_samples[0][0]) > (GRAPH_MINUTES * 60 + 30) * 1000:
		_samples.pop_front()


## Science per minute in each 10 s step of the last 10 minutes (oldest first), from the samples.
func per_minute(tech: String) -> Array:
	var now := Time.get_ticks_msec()
	var steps: int = GRAPH_MINUTES * 60 / BUCKET_S
	var out: Array = []
	out.resize(steps)
	out.fill(0.0)
	for i in range(1, _samples.size()):
		var a: Array = _samples[i - 1]
		var b: Array = _samples[i]
		if str(a[1]) != tech or str(b[1]) != tech or float(b[2]) < float(a[2]):
			continue
		var age := (now - int(b[0])) / 1000.0
		var k := steps - 1 - floori(age / BUCKET_S)
		if k >= 0 and k < steps:
			out[k] = float(out[k]) + (float(b[2]) - float(a[2])) * 60.0 / BUCKET_S
	return out


## Science per minute over the last minute seen.
func rate_now(tech: String) -> float:
	var now := Time.get_ticks_msec()
	var first: Array = []
	var last: Array = []
	for smp in _samples:
		if str(smp[1]) == tech and now - int(smp[0]) <= 60000:
			if first.is_empty():
				first = smp
			last = smp
	if first.is_empty() or int(last[0]) - int(first[0]) < 5000:
		return 0.0
	return maxf(0.0, (float(last[2]) - float(first[2])) / ((int(last[0]) - int(first[0])) / 60000.0))


## Factorio's hovered research panel turns orange with black text.
func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		_hovered = what == NOTIFICATION_MOUSE_ENTER
		if is_node_ready():
			_refresh()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		finished = ""
		open_requested.emit()
		accept_event()
		_refresh()


func _refresh() -> void:
	var tech := str(model.research)
	if _last != "" and tech != _last:
		var t: Dictionary = model.techs.get(_last, {})
		if int(t.get("state", 0)) == 2:
			finished = _last
	if tech != "":
		finished = ""
	_last = tech
	var keys := Controls.keys_text("open_technology")
	_key.text = keys if keys != "" else "T"
	tooltip_text = "Technologies (%s)" % _key.text
	var shown := tech if tech != "" else finished
	theme_type_variation = "FResearchActive" if shown != "" else "FResearchInactive"
	_hint.visible = shown == ""
	_name.visible = shown != ""
	_name.get_parent().visible = shown != ""  # its column, so the hint keeps the width
	_bar_row.visible = shown != ""
	_frame_padding(shown != "")
	if _hovered:
		var margins := [4, 4, 12, 4] if shown != "" else [13, 4, 2, 4]
		add_theme_stylebox_override("panel", Kit.style_with_margins("side_button_hover", margins[0], margins[1], margins[2], margins[3]))
	if shown != _shown:
		_icon.texture = GuiAssets.tech_icon(shown) if shown != "" else GuiAssets.side_menu_icon(TECHNOLOGY_ICON)
		_icon.custom_minimum_size = Kit.pxv(32, 32) if shown != "" else Kit.pxv(16, 16)
		_row.add_theme_constant_override("separation", Kit.px(8 if shown != "" else 14))
	_icon.visible = _icon.texture != null
	if tech != "":
		_name.text = Kit.tech_name(tech)
		_name.remove_theme_color_override("font_color")
		_name.add_theme_color_override("font_color", Kit.WHITE)
		_bar.value = roundi(float(model.research_progress) * 1000.0)
		_bar.add_theme_stylebox_override("fill", Kit.bar_style(Kit.BAR_GREEN))
	elif finished != "":
		_name.text = "%s finished. Press %s." % [Kit.tech_name(finished), _key.text]
		_name.add_theme_color_override("font_color", Kit.ORANGE)
		_bar.value = 1000
		_bar.add_theme_stylebox_override("fill", Kit.bar_style(Kit.BAR_ORANGE))
	_percent.text = "%d%%" % floori(_bar.value / 10.0)
	_percent.remove_theme_color_override("font_color")
	if _hovered:
		for l in [_name, _percent, _key] + _hint.get_children():
			(l as Label).add_theme_color_override("font_color", Kit.BLACK)
	else:
		for l in _hint.get_children():
			(l as Label).remove_theme_color_override("font_color")
		_key.add_theme_color_override("font_color", KEY_COLOR)
	_shown = shown


## research_progress_inner_frame: 4 pixels around the icon and 12 right of the text; the hint has
## the small flask 13 in from the left.
func _frame_padding(active: bool) -> void:
	if active:
		add_theme_stylebox_override("panel", Kit.style_with_margins("research_active", 4, 4, 12, 4))
	else:
		add_theme_stylebox_override("panel", Kit.style_with_margins("research_inactive", 13, 4, 2, 4))


## The tooltip's graph: Factorio's dark plot with a grid, the values up the left (8 steps), the
## minutes along the bottom (10 to 0) and the line in orange.
class Graph extends Control:
	var values: Array = []

	func _draw() -> void:
		var font := Kit.font("regular")
		var fs := Kit.px(11)
		var left := float(Kit.px(28))
		var bottom := float(Kit.px(18))
		var plot := Rect2(left, Kit.px(6), size.x - left - Kit.px(10), size.y - bottom - Kit.px(6))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.08))
		var top := 0.0
		for v in values:
			top = maxf(top, float(v))
		top = maxf(1.0, top * 1.1)
		var grid := Color(1, 1, 1, 0.08)
		var text_color := Color(0.7, 0.7, 0.7)
		for i in 9:
			var y: float = plot.end.y - plot.size.y * i / 8.0
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid)
			if font != null:
				var v: float = top * i / 8.0
				var text := "0" if i == 0 else ("%.1f" % v).trim_suffix(".0")
				draw_string(font, Vector2(0, y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_RIGHT, left - Kit.px(6), fs, text_color)
		for m in 11:
			var x: float = plot.position.x + plot.size.x * m / 10.0
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), grid)
			if font != null:
				draw_string(font, Vector2(x - Kit.px(10), size.y - Kit.px(3)), str(10 - m), HORIZONTAL_ALIGNMENT_CENTER, Kit.px(20), fs, text_color)
		if values.size() < 2:
			return
		var pts := PackedVector2Array()
		for i in values.size():
			pts.append(Vector2(plot.position.x + plot.size.x * i / float(values.size() - 1), plot.end.y - plot.size.y * float(values[i]) / top))
		draw_polyline(pts, Kit.ORANGE, maxf(1.0, Kit.px(1)))
