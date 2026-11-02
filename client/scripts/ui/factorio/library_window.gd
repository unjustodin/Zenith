extends PanelContainer
## Factorio's blueprint library (B): "My blueprints" (the client's own library, bp_library.gd),
## "Game blueprints" (the save's shared tab, from the mod) and, when the bridge plays a save's own
## player, that player's library as the save keeps it. As tools/ui_reference's `blueprint_library`
## picture shows, it is the right half of one window with the character's inventory on the left
## (character_window.gd show_side): the title bar's search, back and forward buttons, the list /
## small / large view toggles, the tabs, and the records (in the list view each one's big picture
## with its name). Books open in place (back goes up again), the search finds labels in every
## book. New books and planners and Import string are on the shortcut bar, as in Factorio; drop
## one from the cursor on the empty slot to keep it here.
##
## Mouse, as in Factorio: click takes the record into the cursor (the mod gets it as the stack it
## keeps for the cursor), right click opens its window (a book opens in place), drag moves it
## (dropped on a book it goes in as the last page; dropped on the back button it leaves the book),
## Del over one deletes it. Clicking the grid with a blueprint or planner from the inventory in
## the cursor adds a copy of it here.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const BpString := preload("res://scripts/ui/factorio/bp_string.gd")
const BpLibrary := preload("res://scripts/ui/factorio/bp_library.gd")
const PlannerSlot := preload("res://scripts/ui/factorio/planner_slot.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const Parts := preload("res://scripts/ui/factorio/planner_parts.gd")

signal close_requested
## It closed (the coordinator takes it out of the character window).
signal closed
## Take into the cursor: {"kind": "library", "path"} or {"kind": "game"/"player", "ix", "item"}.
signal take_requested(source: Dictionary)
## Open the record's window: the same sources.
signal open_requested(source: Dictionary)
## The grid was clicked with an inventory planner held: add it at this place of My blueprints.
signal add_held_requested(path: Array)

const ROWS := 7
const WIDTH := 536
## Columns of the small and large icon views.
const COLUMNS := 10
const BIG_COLUMNS := 5
const TABS := [["mine", "My blueprints"], ["game", "Game blueprints"], ["player", "Player's blueprints"]]

var model  # planner_model.gd
var library: BpLibrary
## The open tab and, in My blueprints, the place shown (see bp_library.gd).
var tab := "mine"
var path: Array = []
## "list", "grid" (small icons) or "slots" (large icons).
var view := "list"

## Where the records are listed (rows in the list view, a slot grid in the others).
var _grid := VBoxContainer.new()
var _view_holder := HBoxContainer.new()
var _views: HBoxContainer
var _history: Array = []  # earlier places, for back: [tab, path]
var _future: Array = []  # places gone back from, for forward
var _forward: Button
var _tabs := HBoxContainer.new()
var _back: Button
var _where: Label
var _list_bg: PanelContainer
var _search: LineEdit
var _hovered := -1
var _shown: Array = []  # what each slot is: [path] (mine) or index into the game list
var _owner := 1


func _ready() -> void:
	theme_type_variation = "FFrameRight"
	theme = EntityPanels.theme()
	# Factorio's library half is 536 wide (the window 984 with the inventory) and 925 tall.
	custom_minimum_size.x = Kit.px(WIDTH)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	# The title bar's right half: search, back, forward, close (the title is the inventory half's).
	var bar := Kit.title_bar("", true)
	(bar.get_child(0) as Label).visible = false
	var close := bar.get_child(bar.get_child_count() - 1) as Button
	close.pressed.connect(func() -> void: close_requested.emit())
	var search_button := _frame_button("icons/search.png", "Search (Ctrl+F)")
	search_button.name = "SearchButton"
	search_button.pressed.connect(func() -> void:
		_search.visible = not _search.visible
		if _search.visible:
			_search.grab_focus()
		else:
			_search.text = ""
			refresh())
	_back = _frame_button("icons/mip/backward-arrow.png", "Back")
	_back.name = "Back"
	_back.pressed.connect(_go_back)
	var can_drop := func(_at: Vector2, data: Variant) -> bool:
		return tab == "mine" and not path.is_empty() and data is Dictionary and data.has("f3d_record")
	var drop := func(_at: Vector2, data: Variant) -> void: drop_on_back(int(data["f3d_record"]))
	_back.set_drag_forwarding(Callable(), can_drop, drop)
	_forward = _frame_button("icons/mip/forward-arrow.png", "Forward")
	_forward.name = "Forward"
	_forward.pressed.connect(_go_forward)
	for b in [search_button, _back, _forward]:
		bar.add_child(b)
		bar.move_child(b, bar.get_child_count() - 2)
	box.add_child(bar)

	var frame := Kit.panel("FShallowFrame")
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(frame)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	frame.add_child(inner)
	# The band: where we are (inside a book), the search box, the client's new / import buttons, the
	# view toggles.
	var band := Kit.panel("FSubheader")
	var band_row := HBoxContainer.new()
	band_row.add_theme_constant_override("separation", Kit.px(4))
	band_row.custom_minimum_size.y = Kit.px(36)
	var band_pad := MarginContainer.new()
	band_pad.add_theme_constant_override("margin_left", Kit.px(12))
	band_pad.add_theme_constant_override("margin_right", Kit.px(8))
	band_pad.add_child(band_row)
	band.add_child(band_pad)
	_where = Kit.label("", "FHeading")
	_where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_where.clip_text = true
	_where.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	band_row.add_child(_where)
	_search = MenuKit.textbox("", "Search")
	_search.custom_minimum_size.x = Kit.px(150)
	_search.visible = false
	_search.text_changed.connect(func(_t: String) -> void: refresh())
	band_row.add_child(_search)
	var gap := Control.new()
	gap.custom_minimum_size.x = Kit.px(8)
	band_row.add_child(gap)
	band_row.add_child(_view_holder)
	inner.add_child(band)
	_tabs.add_theme_constant_override("separation", 0)
	var tabs_pad := MarginContainer.new()
	tabs_pad.add_theme_constant_override("margin_left", Kit.px(12))
	tabs_pad.add_theme_constant_override("margin_top", Kit.px(8))
	tabs_pad.add_child(_tabs)
	inner.add_child(tabs_pad)
	var deep: Array = Kit.deep_scroll(Kit.pxv(Kit.SLOT * Kit.COLUMNS, 793))
	(deep[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(deep[0])
	# The list lies on Factorio's light grey (scroll_pane_with_dark_background is only the edge).
	_list_bg = deep[0]
	_grid.add_theme_constant_override("separation", 0)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(4))
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_grid)
	deep[1].add_child(pad)
	_grid.gui_input.connect(_on_grid_input)
	library.changed.connect(refresh)
	model.library_listed.connect(func(_src: String) -> void: refresh())


func _frame_button(sprite: String, tip: String) -> Button:
	var b := Kit.close_button()
	b.tooltip_text = tip
	var icon := GuiAssets.core_sprite(sprite)
	if icon != null:
		b.icon = icon
	return b


func title_text() -> String:
	return "Blueprint library"


## The records' slots in the order they are listed.
func record_slots() -> Array:
	var out: Array = []
	_collect(_grid, out)
	return out


func _collect(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is PlannerSlot and str(c.name).begins_with("Record") and not c.is_queued_for_deletion():
			out.append(c)
		else:
			_collect(c, out)


func is_open() -> bool:
	return visible


func open(on: bool) -> void:
	var was := visible
	visible = on
	if on:
		model.request_libraries()
		refresh()
	else:
		_search.release_focus()
		if was:
			closed.emit()


func close() -> void:
	open(false)


func show_tab(name: String) -> void:
	_go_to(name, [])


## Moves to a place (a tab and a book path), remembering the last one for back.
func _go_to(new_tab: String, new_path: Array) -> void:
	if new_tab == tab and new_path == path:
		refresh()
		return
	_history.append([tab, path])
	_future = []
	tab = new_tab
	path = new_path
	refresh()


func _go_back() -> void:
	if _history.is_empty():
		_go_up()
		return
	_future.append([tab, path])
	var at: Array = _history.pop_back()
	tab = at[0]
	path = at[1]
	refresh()


func _go_forward() -> void:
	if _future.is_empty():
		return
	_history.append([tab, path])
	var at: Array = _future.pop_back()
	tab = at[0]
	path = at[1]
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_fill_tabs()
	if _views != null:
		_view_holder.remove_child(_views)
		_views.queue_free()
	_views = Parts.view_toggles(view, func(v: String) -> void:
		view = v
		refresh())
	_view_holder.add_child(_views)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_shown = []
	_owner += 1
	_hovered = -1
	var q := _search.text.strip_edges()
	_back.disabled = _history.is_empty() and (tab != "mine" or path.is_empty())
	_forward.disabled = _future.is_empty()
	_where.text = _place_name()
	if _list_bg != null:
		if view == "list":
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color8(62, 61, 62)
			bg.border_color = Color8(17, 17, 17)
			bg.set_border_width_all(Kit.px(2))
			bg.set_content_margin_all(Kit.px(2))
			_list_bg.add_theme_stylebox_override("panel", bg)
		else:
			_list_bg.remove_theme_stylebox_override("panel")
	var grid: GridContainer = null
	if view != "list":
		grid = Kit.slot_grid(COLUMNS if view == "grid" else BIG_COLUMNS)
		_grid.add_child(grid)
	var entries: Array = []  # [shown key, record or listed row]
	if tab == "mine":
		if q != "":
			entries = library.search(q)
		else:
			var list := library.list_at(path)
			for i in list.size():
				entries.append([path + [i], list[i]])
	else:
		var list: Array = model.game_library if tab == "game" else model.player_library
		for i in list.size():
			var r: Array = list[i]
			if q != "" and not str(r[2]).to_lower().contains(q.to_lower()):
				continue
			entries.append([i, r])
	var cell := 0
	for e in entries + [null]:
		var s: PlannerSlot
		var name_label: Label = null
		if view == "list":
			var row: Array = Parts.list_row()
			s = row[1]
			name_label = row[2]
			_grid.add_child(row[0])
			if e != null:
				_grid.add_child(Parts.separator())
		else:
			s = PlannerSlot.new()
			s.theme_type_variation = "FSlotButton"
			if view == "slots":
				s.big = true
				s.custom_minimum_size = Kit.pxv(72, 72)
			grid.add_child(s)
		if e == null:
			# Factorio's empty slot at the end: drop a held planner here to add it.
			s.name = "Empty"
			s.set_tip("Empty", [["Click with a blueprint or planner in the cursor: add a copy", "", Kit.DISABLED_TEXT]])
			s.clicked.connect(func(button_index: int, _shift: bool) -> void:
				if button_index == MOUSE_BUTTON_LEFT and tab == "mine":
					add_held_requested.emit(path))
			break
		_setup_slot(s, cell)
		if tab == "mine":
			s.set_record(e[1])
		else:
			s.set_listed(str(e[1][1]), str(e[1][2]), e[1][3])
			s.drag_item = ""
		if name_label != null:
			name_label.text = BpString.title(e[1]) if tab == "mine" else (str(e[1][2]) if str(e[1][2]) != "" else Kit.pretty(str(e[1][1])))
		_shown.append(e[0])
		cell += 1


func _fill_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for t in TABS:
		if t[0] == "player" and model.player_name == "":
			continue
		var b := Button.new()
		b.theme_type_variation = "FTab"
		b.text = t[1] if t[0] != "player" else "%s's blueprints" % model.player_name
		b.toggle_mode = true
		b.button_pressed = tab == t[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(110, 28)
		b.add_theme_font_override("font", Kit.font("bold"))
		b.name = "Tab_" + str(t[0])
		var key: String = t[0]
		b.pressed.connect(func() -> void: show_tab(key))
		_tabs.add_child(b)


## Inside a book: the books' names (Factorio's band is empty at the top level).
func _place_name() -> String:
	if tab != "mine" or path.is_empty():
		return ""
	var names: Array = []
	for i in path.size():
		names.append(BpString.title(library.record_at(path.slice(0, i + 1))))
	return " › ".join(names)


func _setup_slot(s: PlannerSlot, cell: int) -> void:
	s.theme_type_variation = "FSlotButton"
	s.index = cell
	s.owner_id = _owner
	s.name = "Record%d" % cell
	s.clicked.connect(func(button_index: int, _shift: bool) -> void: _clicked(cell, button_index))
	s.mouse_entered.connect(func() -> void: _hovered = cell)
	s.mouse_exited.connect(func() -> void:
		if _hovered == cell:
			_hovered = -1)
	if tab == "mine" and _search.text.strip_edges() == "":
		s.on_record_drop = func(from: int, owner: int) -> void: _dropped(from, owner, cell)


## The source dictionary for the cell's record.
func source_of(cell: int) -> Dictionary:
	if cell < 0 or cell >= _shown.size():
		return {}
	if tab == "mine":
		return {"kind": "library", "path": _shown[cell]}
	var list: Array = model.game_library if tab == "game" else model.player_library
	var r: Array = list[int(_shown[cell])]
	return {"kind": tab, "ix": int(r[0]), "item": str(r[1]), "label": str(r[2])}


func _clicked(cell: int, button_index: int) -> void:
	var source := source_of(cell)
	if source.is_empty():
		return
	if button_index == MOUSE_BUTTON_LEFT:
		take_requested.emit(source)
	elif button_index == MOUSE_BUTTON_RIGHT:
		if source["kind"] == "library" and BpString.kind(library.record_at(source["path"])) == "blueprint_book" \
				and _search.text.strip_edges() == "":
			_go_to("mine", source["path"])
		else:
			open_requested.emit(source)


func _dropped(from: int, owner: int, to: int) -> void:
	if owner != _owner or from == to or from >= _shown.size():
		return
	var list := library.list_at(path)
	if to < list.size() and BpString.kind(list[to]) == "blueprint_book" and BpString.kind(list[from]) != "blueprint_book":
		library.into_book(path, from, to)
	else:
		library.move(path, from, mini(to, list.size() - 1))


## Clicks on the grid's empty cells: with an inventory planner in the cursor, add it here.
func _on_grid_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and tab == "mine":
		add_held_requested.emit(path)


func _go_up() -> void:
	if not path.is_empty():
		_go_to(tab, path.slice(0, path.size() - 1))


func _new(kind: String) -> void:
	tab = "mine"
	var r: Dictionary = model.empty(kind)
	library.add(path, r)


## Del over a record of My blueprints removes it.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_DELETE and tab == "mine" and _hovered >= 0 and _search.text.strip_edges() == "":
		library.remove(path, _hovered)
		get_viewport().set_input_as_handled()
	elif key.physical_keycode == KEY_BACKSPACE and tab == "mine" and not path.is_empty() and not _search.has_focus():
		_go_up()
		get_viewport().set_input_as_handled()


## For the back button: a page dropped on it leaves the book.
func drop_on_back(from: int) -> void:
	if tab == "mine" and not path.is_empty():
		library.out_of_book(path, from)
