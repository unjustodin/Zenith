extends PanelContainer
## Factorio 2.1's "Train overview" (from a train's or train stop's window, "All trains", and the map
## view): nearly the whole screen, a surface dropdown at the top left, then the tabs Trains,
## Stations and Groups with their counts. Each tab has a striped list on the left that filters the
## grid of cards on the right (All, then each station or group); "No Trains found." in a red banner
## when the grid is empty. A train's card shows a live view of the train from above
## (train_view.gd), its state, carriages and what it carries most; clicking it looks at the train
## in remote view. The search button filters by station, group and state. From the mod's `trl`
## (every train of the force, on every surface), asked for again every few seconds while open.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")
const TrainView := preload("res://scripts/ui/factorio/train_view.gd")

signal close_requested
## Look at a train: its position (tiles) on the character's surface.
signal show_at(at: Vector2)

const REFRESH := 3.0
## Factorio's window at 1920x1080, 100% (GUI pixels).
const WIDTH := 1588
const HEIGHT := 917
const TOP := 27
const LIST_WIDTH := 410
const CARD := Vector2(290, 290)
## The square view on a card.
const VIEW := 258
const COLUMNS := 4
const TABS := ["Trains", "Stations", "Groups"]

var model
## "Trains", "Stations" or "Groups".
var tab := "Trains"
## The list's choice: "" all, else a station's or group's name.
var filter := ""
## The surface shown (index), -1 the character's.
var surface := -1
var search := ""

var _surfaces := OptionButton.new()
var _tab_buttons := {}
var _list := VBoxContainer.new()
var _grid := GridContainer.new()
var _banner: PanelContainer
var _search_box := LineEdit.new()
var _timer := 0.0


func _ready() -> void:
	theme = MenuKit.theme()
	theme_type_variation = "FFrame"
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Train overview", true)
	_search_box.placeholder_text = "Search"
	_search_box.custom_minimum_size = Kit.pxv(200, 24)
	_search_box.visible = false
	_search_box.text_changed.connect(func(t: String) -> void:
		search = t.strip_edges().to_lower()
		_rebuild())
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

	var top := HBoxContainer.new()
	_surfaces.focus_mode = Control.FOCUS_NONE
	_surfaces.custom_minimum_size = Kit.pxv(130, 28)
	_surfaces.item_selected.connect(func(i: int) -> void:
		surface = _surfaces.get_item_id(i)
		filter = ""
		_rebuild())
	top.add_child(_surfaces)
	box.add_child(top)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", Kit.px(2))
	var tab_row := MarginContainer.new()
	tab_row.add_theme_constant_override("margin_left", Kit.px(12))
	tab_row.add_child(tabs)
	body.add_child(tab_row)
	for t in TABS:
		var b := Button.new()
		b.name = "Tab" + t
		b.theme_type_variation = "FTab"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(82, 34)
		var name: String = t
		b.pressed.connect(func() -> void: show_tab(name))
		tabs.add_child(b)
		_tab_buttons[t] = b
	var pane := Kit.panel("FTabPane")
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(pane)
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", Kit.px(8))
	pane.add_child(split)

	var left: Array = Kit.deep_scroll(Kit.pxv(LIST_WIDTH, 100))
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(left[0])
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(left[1] as ScrollContainer).add_child(_list)

	var right_frame := Kit.panel("FDeepFrame")
	right_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right_frame)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right_frame.add_child(right)
	_banner = PanelContainer.new()
	var red := StyleBoxFlat.new()
	red.bg_color = Color8(100, 24, 24)
	red.content_margin_top = Kit.px(4)
	red.content_margin_bottom = Kit.px(4)
	_banner.add_theme_stylebox_override("panel", red)
	var warn := HBoxContainer.new()
	warn.alignment = BoxContainer.ALIGNMENT_CENTER
	warn.add_theme_constant_override("separation", Kit.px(6))
	var w_icon := TextureRect.new()
	w_icon.texture = GuiAssets.core_sprite("icons/mip/warning-white.png")
	w_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	w_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	w_icon.custom_minimum_size = Kit.pxv(16, 16)
	warn.add_child(w_icon)
	var w_text := Kit.label("No Trains found.", "FHeading")
	w_text.name = "BannerText"
	w_text.add_theme_color_override("font_color", Kit.WHITE)
	warn.add_child(w_text)
	_banner.add_child(warn)
	right.add_child(_banner)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	right.add_child(scroll)
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", Kit.px(2))
	_grid.add_theme_constant_override("v_separation", Kit.px(2))
	scroll.add_child(_grid)
	model.trains_overview_changed.connect(_rebuild)
	model.trains_overview_requested.connect(func() -> void: open(true))
	show_tab("Trains")


func is_open() -> bool:
	return visible


func open(on: bool) -> void:
	visible = on
	if on:
		_timer = REFRESH
		_fill_surfaces()
		_layout()
		_rebuild()


func toggle_search() -> void:
	_search_box.visible = not _search_box.visible
	if _search_box.visible:
		_search_box.grab_focus()
	else:
		_search_box.text = ""
		search = ""
		_rebuild()


func show_tab(t: String) -> void:
	tab = t
	filter = ""
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).set_pressed_no_signal(k == t)
	_rebuild()


func _process(delta: float) -> void:
	if not visible:
		return
	_layout()
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		model.request_trains_overview()


func _layout() -> void:
	var view := get_viewport_rect().size
	custom_minimum_size = Vector2(minf(Kit.px(WIDTH), view.x - Kit.px(8)), maxf(Kit.px(300), minf(Kit.px(HEIGHT), view.y - Kit.px(TOP) - Kit.px(125))))
	size = custom_minimum_size
	position = Vector2(roundf((view.x - size.x) / 2.0), minf(Kit.px(TOP), maxf(0.0, view.y - size.y)))


func _fill_surfaces() -> void:
	_surfaces.clear()
	var shown: int = surface if surface > 0 else model.character_si
	var i := 0
	for s in model.map_surfaces:
		if str(s["planet"]) == "":
			continue  # platforms have no trains
		var planet := str(s["planet"])
		var icon := GuiAssets.data_sprite("space-age/graphics/icons/%s.png" % planet)
		if icon == null:
			icon = GuiAssets.data_sprite("base/graphics/icons/%s.png" % planet)
		_surfaces.add_icon_item(icon, LocaleNames.space_location(planet), int(s["si"]))
		if int(s["si"]) == shown:
			_surfaces.select(i)
		i += 1
	if _surfaces.item_count == 0:
		_surfaces.add_item(LocaleNames.space_location(str(model.planet.get("name", "nauvis"))), model.character_si)
	_surfaces.add_theme_constant_override("icon_max_width", Kit.px(20))


func _shown_si() -> int:
	return surface if surface > 0 else model.character_si


## The trains on the shown surface that match the search.
func _trains() -> Array:
	var si := _shown_si()
	var out: Array = []
	for t in model.trains_overview:
		if si != 0 and int(t["si"]) != si and int(t["si"]) != 0:
			continue
		if search != "" and not (str(t["stop"]).to_lower().contains(search) or str(t["group"]).to_lower().contains(search)
				or state_text(t).to_lower().contains(search)):
			continue
		out.append(t)
	return out


## [name, trains] of each station (where trains are or are heading) or group.
func _entries(trains: Array) -> Array:
	var key := "group" if tab == "Groups" else "stop"
	var counts := {}
	for t in trains:
		var n := str(t[key])
		if n != "":
			counts[n] = int(counts.get(n, 0)) + 1
	if tab == "Stations":
		for n in _stop_names():
			if not counts.has(n):
				counts[n] = 0
	var names := counts.keys()
	names.sort()
	return names.map(func(n: String) -> Array: return [n, counts[n]])


func _stop_names() -> Array:
	var ui = get_parent()
	if ui != null and ui.has_method("stop_names"):
		return ui.stop_names()
	return []


func _rebuild() -> void:
	if not visible:
		return
	var trains := _trains()
	var groups := {}
	for t in trains:
		if str(t["group"]) != "":
			groups[str(t["group"])] = true
	var counts := {"Trains": trains.size(), "Stations": _entries_for("Stations", trains).size(), "Groups": groups.size()}
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).text = "%s  %d" % [k, counts[k]]
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var entries := _entries(trains)
	_list.add_child(_list_row("All", trains.size(), filter == "", 0))
	for i in entries.size():
		_list.add_child(_list_row(str(entries[i][0]), int(entries[i][1]), filter == str(entries[i][0]), i + 1))
	for i in maxi(0, 30 - entries.size() - 1):
		_list.add_child(_list_row("", -1, false, entries.size() + 1 + i))
	var shown: Array = []
	if tab == "Stations" and filter == "":
		for e in entries:
			_grid.add_child(_station_card(str(e[0]), int(e[1])))
	else:
		var key := "group" if tab == "Groups" else "stop"
		for t in trains:
			if filter == "" or str(t[key]) == filter:
				shown.append(t)
		for t in shown:
			_grid.add_child(_card(t))
	var empty := _grid.get_child_count() == 0
	_banner.visible = empty
	(_banner.find_child("BannerText", true, false) as Label).text = "No Stations found." if tab == "Stations" and filter == "" else "No Trains found."
	# Factorio draws the empty grid's cells.
	var cells := maxi(COLUMNS * 3, _grid.get_child_count() + (COLUMNS - _grid.get_child_count() % COLUMNS) % COLUMNS)
	for i in cells - _grid.get_child_count():
		_grid.add_child(_blank_card())


func _entries_for(t: String, trains: Array) -> Array:
	var keep := tab
	tab = t
	var out := _entries(trains)
	tab = keep
	return out


## A row of the striped list: the name and how many trains; clicking it filters the grid.
func _list_row(text: String, n: int, selected: bool, index: int) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = Kit.px(28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if n < 0:
		var s := StyleBoxFlat.new()
		s.bg_color = Color8(47, 47, 47) if index % 2 == 0 else Color8(40, 40, 40)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_stylebox_override("hover", s)
		b.add_theme_stylebox_override("pressed", s)
		b.add_theme_stylebox_override("disabled", s)
		b.disabled = true
		return b
	b.name = "List_" + (text if text != "All" else "All")
	b.theme_type_variation = "FListItemSelected" if selected else "FListItem"
	if text != "All":
		RichText.decorate_button(b, text)
		b.text = "%s (%d)" % [b.text, n]
	else:
		b.text = "All trains (%d)" % n
	var name := "" if text == "All" else text
	b.pressed.connect(func() -> void:
		filter = name
		_rebuild())
	return b


## The world's movers (the locomotives the client draws), for the cards' live views.
func _movers() -> Node:
	var root := get_tree().root if is_inside_tree() else null
	return root.find_child("Movers", true, false) if root != null else null


func _card_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_content_margin_all(Kit.px(8))
	return s


func _blank_card() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Kit.pxv(CARD.x, CARD.y)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _card_style(Color8(36, 36, 36)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A train's card: a live view of the train from above (train_view.gd), its state under it,
## carriages and cargo; click: look at it.
func _card(t: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.name = "Train%d" % int(t["id"])
	p.custom_minimum_size = Kit.pxv(CARD.x, CARD.y)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", _card_style(Color8(36, 36, 36)))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var at: Vector2 = t["position"]
	var here: bool = int(t["si"]) == model.character_si or model.character_si == 0
	p.tooltip_text = "Click: look at it" if here else "On another surface"
	p.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and here:
			show_at.emit(at))
	# Factorio's card (trains_nauvis.png): a square view of the train in a deep frame, under it its
	# state in a dark box, nothing else. The cargo and carriages are in the tooltip.
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Kit.px(8))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var frame := Kit.panel("FDeepFrame")
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var preview := TrainView.new()
	preview.name = "View"
	preview.custom_minimum_size = Kit.pxv(VIEW, VIEW)
	preview.cache = get_parent().get("map_cache") if get_parent() != null else null
	preview.movers = _movers()
	preview.show_train(int(t["unit"]), at)
	frame.add_child(preview)
	v.add_child(frame)
	var box := PanelContainer.new()
	var dark := StyleBoxFlat.new()
	dark.bg_color = Color8(31, 30, 31)
	dark.border_color = Color8(14, 14, 14)
	dark.set_border_width_all(1)
	dark.content_margin_top = Kit.px(4)
	dark.content_margin_bottom = Kit.px(4)
	box.add_theme_stylebox_override("panel", dark)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size.x = Kit.px(VIEW)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var state := RichText.text_label(state_text(t))
	state.name = "State"
	state.set("clip_text", true)
	state.set("horizontal_alignment", HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(state)
	v.add_child(box)
	var cargo: Array = []
	for entry in t["cargo"]:
		if entry is Array and entry.size() >= 2:
			cargo.append("%s × %s" % [Kit.count_text(int(entry[1])), Kit.pretty(str(entry[0]))])
	cargo.push_front("%d carriages" % int(t["carriages"]))
	cargo.push_front(p.tooltip_text)
	p.tooltip_text = "\n".join(cargo)
	return p


## A station's card: its name and the trains heading there or waiting; click: its trains.
func _station_card(name: String, n: int) -> Control:
	var b := Button.new()
	b.name = "Station_" + name
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Kit.pxv(CARD.x, CARD.y)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _card_style(Color8(36, 36, 36)))
	b.add_theme_stylebox_override("hover", _card_style(Color8(52, 52, 52)))
	b.add_theme_stylebox_override("pressed", _card_style(Color8(52, 52, 52)))
	b.add_theme_color_override("font_color", Kit.WHITE)
	b.add_theme_color_override("font_hover_color", Kit.WHITE)
	# A name with icons shows its first icon in the stop's place and the rest as text.
	var named := RichText.icon_and_text(name)
	b.icon = named[0] if named[0] != null else Kit.item_icon("train-stop")
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("icon_max_width", Kit.px(64))
	b.text = "%s\n%d trains" % [named[1], n]
	b.pressed.connect(func() -> void:
		filter = name
		_rebuild())
	return b


## Factorio's state names in its own words.
static func state_text(t: Dictionary) -> String:
	var state := str(t["state"])
	var stop := str(t["stop"])
	match state:
		"wait_station":
			return "Waiting at %s" % stop if stop != "" else "Waiting at a station"
		"on_the_path", "arrive_station":
			return "Heading to %s" % stop if stop != "" else "On the way"
		"wait_signal", "arrive_signal":
			return "Waiting at a signal"
		"no_schedule":
			return "No schedule"
		"no_path":
			return "No path"
		"manual_control", "manual_control_stop":
			return "Manual"
	return state.replace("_", " ").capitalize()
