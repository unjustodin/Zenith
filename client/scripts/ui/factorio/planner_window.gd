extends PanelContainer
## Factorio's deconstruction and upgrade planner windows: the right half of one window with the
## character's inventory on the left (character_window.gd show_side), titled with the planner's
## name, as tools/ui_reference's deconstruction_planner and upgrade_planner pictures show.
##   Deconstruction planner: the subheader (name, pencil, copy / export / delete), "Trees/rocks
##     only", then Entities / Tiles tabs, each a Whitelist / Blacklist switch over 30 filter slots
##     (the Tiles tab also has the tile selection mode: Normal, Always, Never, Only).
##   Upgrade planner: the subheader, then four "From / To" column pairs of mapping rules, filled
##     row by row (Factorio's mapper index 0 is the first pair's first row, 1 the second pair's).
## Slots open the item chooser (left click) and clear (right click). As in Factorio there is no
## Save: every change is kept, and written back where the planner came from when the window
## closes (flush()).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const BpString := preload("res://scripts/ui/factorio/bp_string.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const Parts := preload("res://scripts/ui/factorio/planner_parts.gd")

signal close_requested
## The window closed (the coordinator takes it out of the character window).
signal closed
signal saved(record: Dictionary, source: Dictionary)
signal deleted(source: Dictionary)
signal export_requested(record: Dictionary)
signal add_to_library(record: Dictionary)
## The copy button: a copy of the planner into the cursor.
signal copy_requested(record: Dictionary)

const FILTERS := 30
const MAPPERS := 24
## The upgrade planner's column pairs, and the rows shown at least.
const PAIRS := 4
const MIN_ROWS := 4
## defines.deconstruction_item.tile_selection_mode, in order.
const TILE_MODES := [["Normal", 0], ["Always", 1], ["Never", 2], ["Only", 3]]

var picker  # item_picker.gd
var record := {}
var source := {}
## Entities or Tiles (the deconstruction planner's tab).
var tab := "entities"

var _title: Label  # the subheader's name (the window's title is the character window's)
var _sub := {}
var _body := VBoxContainer.new()
var _delete: Button
var _dirty := false


func _ready() -> void:
	theme_type_variation = "FFrameRight"
	theme = EntityPanels.theme()
	custom_minimum_size.x = Kit.px(Kit.SLOT * Kit.COLUMNS + 24)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("", true)
	(bar.get_child(0) as Label).visible = false
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: close_requested.emit())
	box.add_child(bar)
	var shallow := Kit.panel("FShallowFrame")
	shallow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(shallow)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	shallow.add_child(inner)
	_sub = Parts.subheader("Deconstruction planner", func(t: String) -> void:
		_set_label(t)
		_show())
	_title = _sub["caption"]
	inner.add_child(_sub["panel"])
	var tools: Array = Parts.record_tools(_sub["tools"])
	(tools[0] as Button).pressed.connect(func() -> void: copy_requested.emit(record.duplicate(true)))
	(tools[1] as Button).pressed.connect(func() -> void: export_requested.emit(record.duplicate(true)))
	_delete = tools[2]
	_delete.pressed.connect(func() -> void:
		_dirty = false
		deleted.emit(source)
		close_requested.emit())
	_body.add_theme_constant_override("separation", 0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(_body)


func is_open() -> bool:
	return visible


func edit(r: Dictionary, from: Dictionary) -> void:
	if visible:
		flush()
	record = r.duplicate(true)
	source = from
	tab = "entities"
	_dirty = false
	var b := BpString.body(record)
	if not (b.get("settings") is Dictionary):
		b["settings"] = {}
	visible = true
	_show()


## Factorio's window title: the planner's kind (its name is in the subheader).
func title_text() -> String:
	return "Upgrade planner" if BpString.kind(record) == "upgrade_planner" else "Deconstruction planner"


func close() -> void:
	if not visible:
		return
	flush()
	visible = false
	closed.emit()


## Writes the changes back where the planner came from (Factorio keeps every change at once).
func flush() -> void:
	if _dirty:
		_dirty = false
		saved.emit(record.duplicate(true), source)


func settings() -> Dictionary:
	return BpString.body(record)["settings"]


func _changed() -> void:
	_dirty = true
	_show()


func _set_label(t: String) -> void:
	var b := BpString.body(record)
	if t == "":
		b.erase("label")
	else:
		b["label"] = t
	_dirty = true


func _show() -> void:
	var upgrade := BpString.kind(record) == "upgrade_planner"
	var label := BpString.label(record)
	Parts.show_name(_sub, label if label != "" else title_text(), label)
	_delete.disabled = not (str(source.get("kind", "")) in ["library", "slot"])
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	if upgrade:
		_show_upgrade()
	else:
		_show_deconstruction()


static func _padded(content: Control, top := 12, bottom := 12) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", Kit.px(12))
	m.add_theme_constant_override("margin_right", Kit.px(12))
	m.add_theme_constant_override("margin_top", Kit.px(top))
	m.add_theme_constant_override("margin_bottom", Kit.px(bottom))
	m.add_child(content)
	return m


# --- deconstruction planner -------------------------------------------------------------------

func _show_deconstruction() -> void:
	var st := settings()
	var trees_only := bool(st.get("trees_and_rocks_only", false))
	var trees := MenuKit.checkbox("Trees/rocks only", trees_only)
	trees.name = "TreesAndRocksOnly"
	trees.toggled.connect(func(on: bool) -> void:
		if on:
			st["trees_and_rocks_only"] = true
		else:
			st.erase("trees_and_rocks_only")
		_changed())
	_body.add_child(_padded(trees, 8, 8))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	for t in [["entities", "Entities"], ["tiles", "Tiles"]]:
		var b := Button.new()
		b.theme_type_variation = "FTab"
		b.text = t[1]
		b.name = "Tab_" + str(t[0])
		b.toggle_mode = true
		b.button_pressed = tab == t[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(84, 36)
		b.add_theme_font_override("font", Kit.font("bold"))
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			tab = key
			_show())
		tabs.add_child(b)
	var tab_band := Kit.panel("FDeepFrame")
	tab_band.add_child(_padded(tabs, 4, 0))
	_body.add_child(tab_band)
	var pane := VBoxContainer.new()
	pane.add_theme_constant_override("separation", Kit.px(8))
	if tab == "entities":
		pane.add_child(_mode_switch("entity_filter_mode"))
		pane.add_child(_filter_frame("entity_filters", "EntityFilters", trees_only))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(12))
		row.add_child(_mode_switch("tile_filter_mode"))
		var space := Control.new()
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(space)
		row.add_child(Kit.label("Tiles:"))
		var sel := MenuKit.dropdown(TILE_MODES, int(st.get("tile_selection_mode", 0)))
		sel.name = "TileSelectionMode"
		sel.custom_minimum_size.x = Kit.px(140)
		sel.item_selected.connect(func(i: int) -> void:
			var v := int(sel.get_item_metadata(i))
			if v == 0:
				st.erase("tile_selection_mode")
			else:
				st["tile_selection_mode"] = v
			_changed())
		row.add_child(sel)
		pane.add_child(row)
		pane.add_child(_filter_frame("tile_filters", "TileFilters", int(st.get("tile_selection_mode", 0)) == 2))
	_body.add_child(_padded(pane, 8, 12))


## Factorio's Whitelist / Blacklist switch for one of the filter lists.
func _mode_switch(key: String) -> Control:
	var st := settings()
	var sw := Parts.switch("Whitelist", "Blacklist", int(st.get(key, 0)) == 1, func(black: bool) -> void:
		if black:
			st[key] = 1
		else:
			st.erase(key)
		_changed())
	sw.name = key
	return sw


## The 30 filter slots in a deep frame, with Factorio's faint empty rows under them.
func _filter_frame(key: String, node_name: String, disabled: bool) -> Control:
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	frame.add_child(col)
	col.add_child(_filter_grid(key, node_name, disabled))
	col.add_child(Parts.filler(3))
	return frame


## 30 filter slots for a list of {"name", "index" (0-based)} (2.0's planner strings).
func _filter_grid(key: String, node_name: String, disabled: bool) -> GridContainer:
	var st := settings()
	var by_index := {}
	for f in BpString._list(st.get(key)):
		by_index[int(f.get("index", 0))] = f
	var grid := Kit.slot_grid()
	grid.name = node_name
	for i in FILTERS:
		var s := Slot.new()
		s.theme_type_variation = "FSlotButton"
		s.name = "%s%d" % [node_name, i]
		var f: Dictionary = by_index.get(i, {})
		s.set_stack(str(f.get("name", "")), -1)
		s.disabled = disabled
		if f.has("name"):
			s.set_tip(Kit.entity_name(str(f["name"])) if key == "entity_filters" else Kit.pretty(str(f["name"])))
		var n := i
		s.clicked.connect(func(button_index: int, _shift: bool) -> void: _filter_clicked(key, n, button_index))
		grid.add_child(s)
	return grid


func _filter_clicked(key: String, i: int, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_RIGHT:
		set_filter(key, i, "")
	elif button_index == MOUSE_BUTTON_LEFT and picker != null:
		picker.choose(["item"], func(_type: String, name: String) -> void: set_filter(key, i, name),
			"Choose an entity" if key == "entity_filters" else "Choose a tile")


## Sets (or with "" clears) one filter slot.
func set_filter(key: String, i: int, name: String) -> void:
	var st := settings()
	var list: Array = BpString._list(st.get(key)).filter(func(f: Dictionary) -> bool: return int(f.get("index", 0)) != i)
	if name != "":
		list.append({"name": name, "index": i})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	if list.is_empty():
		st.erase(key)
	else:
		st[key] = list
	_changed()


# --- upgrade planner --------------------------------------------------------------------------

func _show_upgrade() -> void:
	var st := settings()
	var by_index := {}
	var last := -1
	for m in BpString._list(st.get("mappers")):
		by_index[int(m.get("index", 0))] = m
		last = maxi(last, int(m.get("index", 0)))
	var rows := clampi(ceili((last + 2) / float(PAIRS)), MIN_ROWS, MAPPERS / PAIRS)
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	frame.add_child(col)
	var grid := GridContainer.new()
	grid.name = "Mappers"
	grid.columns = PAIRS * 2 + PAIRS - 1  # a gap column between the pairs
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	for p in PAIRS:
		for h in ["From", "To"]:
			var l := Kit.label(h, "FHeading")
			l.add_theme_color_override("font_color", Kit.WHITE)
			l.custom_minimum_size = Kit.pxv(Kit.SLOT, 24)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(l)
		if p < PAIRS - 1:
			grid.add_child(_gap())
	for r in rows:
		for p in PAIRS:
			var i := r * PAIRS + p
			var m: Dictionary = by_index.get(i, {})
			for side in ["from", "to"]:
				var s := Slot.new()
				s.theme_type_variation = "FSlotButton"
				s.name = "Mapper%d_%s" % [i, side]
				var it = m.get(side)
				s.set_stack(str(it.get("name", "")) if it is Dictionary else "", -1)
				if it is Dictionary:
					s.quality = str(it.get("quality", ""))
					var lines: Array = []
					if it.has("quality") and str(it["quality"]) != "normal":
						lines.append(["Quality: %s" % str(it["quality"]).capitalize()])
					s.set_tip(Kit.entity_name(str(it.get("name", ""))), lines)
				var which: String = side
				s.clicked.connect(func(button_index: int, _shift: bool) -> void: _mapper_clicked(i, which, button_index))
				grid.add_child(s)
			if p < PAIRS - 1:
				grid.add_child(_gap())
	col.add_child(grid)
	col.add_child(Parts.stripes(MAPPERS / PAIRS + 2 - rows))
	_body.add_child(_padded(frame, 12, 12))


static func _gap() -> Control:
	var g := Control.new()
	g.custom_minimum_size = Kit.pxv(26, 0)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _mapper_clicked(i: int, side: String, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_RIGHT:
		set_mapper(i, side, "")
	elif button_index == MOUSE_BUTTON_LEFT and picker != null:
		picker.choose(["item"], func(_type: String, name: String) -> void: set_mapper(i, side, name), "Choose an entity")


## Sets one side of mapper i (0-based) to an entity, or clears it with "". The type stays
## "entity" (Factorio's planner also maps modules, as "item"; modules chosen here map as items).
func set_mapper(i: int, side: String, name: String) -> void:
	var st := settings()
	var list: Array = BpString._list(st.get("mappers"))
	var row := {}
	for m in list:
		if int(m.get("index", 0)) == i:
			row = m
	if row.is_empty():
		row = {"index": i}
		list.append(row)
	if name == "":
		row.erase(side)
	else:
		row[side] = {"type": "item" if name.ends_with("-module") or name.contains("-module-") else "entity", "name": name}
	list = list.filter(func(m: Dictionary) -> bool: return m.has("from") or m.has("to"))
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]))
	if list.is_empty():
		st.erase("mappers")
	else:
		st["mappers"] = list
	_changed()
