extends PanelContainer
## Factorio's blueprint book window: the right half of one window with the character's inventory
## on the left (character_window.gd show_side), as tools/ui_reference's `blueprint_book` picture
## shows: the subheader (copy, upgrade, export, delete), the book's picture with its name and
## pencil, then "Use Shift + Mouse wheel to change active blueprint." with the list / small / large
## view toggles, and the pages: in the list view each page's big picture with its name, the
## active one framed green, and an empty slot at the end.
## Mouse, as in Factorio: click a page to take it out of the book into the cursor, right click to
## open it (blueprint_window.gd, or the planner's window), drag to reorder, Del over one to take it
## out; click the empty slot with a blueprint in the cursor to put it in. The active page (framed
## green) stays the same page while others come and go; Shift+wheel with the book held changes it. As in Factorio there is no Save: changes are
## written back where the book came from when the window closes (flush()).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const BpString := preload("res://scripts/ui/factorio/bp_string.gd")
const PlannerSlot := preload("res://scripts/ui/factorio/planner_slot.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const Parts := preload("res://scripts/ui/factorio/planner_parts.gd")

signal close_requested
signal closed
signal saved(record: Dictionary, source: Dictionary)
signal deleted(source: Dictionary)
signal export_requested(record: Dictionary)
signal copy_requested(record: Dictionary)
signal upgrade_requested
## Right click on a page: open its window (index into the pages).
signal page_open_requested(page: Dictionary, index: int)
## Click on a page: it has left the book; the coordinator puts it in the cursor.
signal page_taken(page: Dictionary)
## A click on the empty slot: the coordinator adds the held blueprint.
signal add_held_page

var record := {}
var source := {}
## "list", "grid" (small icons) or "slots" (large icons), as Factorio's toggles.
var view := "list"

var _sub := {}
var _picture: PlannerSlot
var _name: Label
var _pages_box := VBoxContainer.new()
var _toggles: HBoxContainer
var _toggles_holder := HBoxContainer.new()
var _delete: Button
var _hovered_page := -1
var _owner := 1
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

	var top := Kit.panel("FShallowFrame")
	box.add_child(top)
	var top_box := VBoxContainer.new()
	top_box.add_theme_constant_override("separation", 0)
	top.add_child(top_box)
	_sub = Parts.subheader("Blueprint book", func(t: String) -> void:
		var b := BpString.body(record)
		if t == "":
			b.erase("label")
		else:
			b["label"] = t
		_dirty = true
		_show())
	(_sub["pencil"] as Button).visible = false  # the pencil is by the name below, as in Factorio
	top_box.add_child(_sub["panel"])
	var tools: Dictionary = Parts.header_tools(_sub["tools"], "book")
	(tools["copy"] as Button).pressed.connect(func() -> void: copy_requested.emit(record.duplicate(true)))
	(tools["upgrade"] as Button).pressed.connect(func() -> void: upgrade_requested.emit())
	(tools["export"] as Button).pressed.connect(func() -> void: export_requested.emit(record.duplicate(true)))
	_delete = tools["delete"]
	_delete.pressed.connect(func() -> void:
		_dirty = false
		deleted.emit(source)
		close_requested.emit())
	var info := HBoxContainer.new()
	info.add_theme_constant_override("separation", Kit.px(12))
	_picture = PlannerSlot.new()
	_picture.theme_type_variation = "FSlotButton"
	_picture.big = true
	_picture.custom_minimum_size = Kit.pxv(64, 64)
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_picture)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", Kit.px(4))
	lines.add_child(Kit.label("Inventory:"))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", Kit.px(6))
	_name = Kit.label("", "FHeading")
	_name.add_theme_color_override("font_color", Kit.WHITE)
	name_row.add_child(_name)
	var pencil := (_sub["pencil"] as Button).duplicate() as Button
	pencil.visible = true
	pencil.name = "RenameBook"
	pencil.pressed.connect(func() -> void: (_sub["pencil"] as Button).pressed.emit())
	name_row.add_child(pencil)
	lines.add_child(name_row)
	info.add_child(lines)
	top_box.add_child(_padded(info, 8, 12))

	var list_frame := Kit.panel("FShallowFrame")
	list_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(list_frame)
	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 0)
	list_frame.add_child(list_box)
	var head := Kit.panel("FSubheader")
	var head_row := HBoxContainer.new()
	head_row.custom_minimum_size.y = Kit.px(36)
	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.scroll_active = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.text = "Use [color=#80cef0]Shift + Mouse wheel[/color] to change active blueprint."
	head_row.add_child(hint)
	head_row.add_child(_toggles_holder)
	head.add_child(_padded(head_row, 0, 0))
	list_box.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = Kit.px(Kit.SLOT * 9)
	scroll.focus_mode = Control.FOCUS_NONE
	_pages_box.add_theme_constant_override("separation", 0)
	_pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_padded(_pages_box, 8, 8))
	list_box.add_child(scroll)


static func _padded(content: Control, top: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", Kit.px(12))
	m.add_theme_constant_override("margin_right", Kit.px(12))
	m.add_theme_constant_override("margin_top", Kit.px(top))
	m.add_theme_constant_override("margin_bottom", Kit.px(bottom))
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(content)
	return m


func is_open() -> bool:
	return visible


func edit(r: Dictionary, from: Dictionary) -> void:
	if visible:
		flush()
	record = r.duplicate(true)
	source = from
	_dirty = false
	visible = true
	_show()


func title_text() -> String:
	return "Blueprint book"


func close() -> void:
	if not visible:
		return
	flush()
	visible = false
	closed.emit()


func flush() -> void:
	if _dirty:
		_dirty = false
		saved.emit(record.duplicate(true), source)


func _changed() -> void:
	_dirty = true
	_show()


func _show() -> void:
	var label := BpString.label(record)
	Parts.show_name(_sub, "Blueprint book", label)
	_name.text = label if label != "" else "Blueprint book"
	_picture.set_record(record)
	_delete.disabled = not (str(source.get("kind", "")) in ["library", "slot"])
	if _toggles != null:
		_toggles_holder.remove_child(_toggles)
		_toggles.queue_free()
	_toggles = Parts.view_toggles(view, func(v: String) -> void:
		view = v
		_show())
	_toggles_holder.add_child(_toggles)
	_show_pages()


func _show_pages() -> void:
	for c in _pages_box.get_children():
		_pages_box.remove_child(c)
		c.queue_free()
	var pages := BpString.pages(record)
	var active := int(BpString.body(record).get("active_index", 0))
	_owner += 1
	_hovered_page = -1
	var grid: GridContainer = null
	if view != "list":
		grid = Kit.slot_grid(Kit.COLUMNS if view == "grid" else 5)
		grid.name = "Pages"
		_pages_box.add_child(grid)
	else:
		_pages_box.name = "Pages"
	for i in pages.size() + 1:
		var s: PlannerSlot
		if view == "list":
			var row: Array = Parts.list_row()
			s = row[1]
			(row[2] as Label).text = BpString.title(pages[i][1]) if i < pages.size() else ""
			_pages_box.add_child(row[0])
			if i < pages.size():
				_pages_box.add_child(Parts.separator())
		else:
			s = PlannerSlot.new()
			s.theme_type_variation = "FSlotButton"
			if view == "slots":
				s.big = true
				s.custom_minimum_size = Kit.pxv(72, 72)
			grid.add_child(s)
		s.name = "Page%d" % i
		s.index = i
		s.owner_id = _owner
		if i < pages.size():
			s.set_record(pages[i][1])
			s.marked = i == active
			var n := i
			s.clicked.connect(func(button_index: int, _shift: bool) -> void: _page_clicked(n, button_index))
			s.mouse_entered.connect(func() -> void: _hovered_page = n)
			s.mouse_exited.connect(func() -> void:
				if _hovered_page == n:
					_hovered_page = -1)
			s.on_record_drop = func(from: int, owner: int) -> void: _page_dropped(from, owner, n)
		else:
			s.name = "AddPage"
			s.set_tip("Empty", [["Click with a blueprint in the cursor: add it", "", Kit.DISABLED_TEXT]])
			s.clicked.connect(func(button_index: int, _shift: bool) -> void:
				if button_index == MOUSE_BUTTON_LEFT:
					add_held_page.emit())


func _page_list() -> Array:
	return BpString.pages(record).map(func(p: Array) -> Dictionary: return p[1])


func _page_clicked(i: int, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_LEFT:
		var page: Dictionary = _page_list()[i]
		remove_page(i)
		page_taken.emit(page)
	elif button_index == MOUSE_BUTTON_RIGHT:
		page_open_requested.emit(_page_list()[i].duplicate(true), i)


func _page_dropped(from: int, owner: int, to: int) -> void:
	if owner != _owner or from == to:
		return
	var list := _page_list()
	var r = list[from]
	list.remove_at(from)
	list.insert(clampi(to, 0, list.size()), r)
	BpString.set_pages(record, list)
	_changed()


## Adds a record to the book as its last page (the held blueprint, from the coordinator).
func add_page(r: Dictionary) -> void:
	var list := _page_list()
	list.append(r)
	BpString.set_pages(record, list)
	_changed()


## Takes page i out; the active page stays the one it was (the next one if it was this).
func remove_page(i: int) -> void:
	var list := _page_list()
	if i < 0 or i >= list.size():
		return
	var b := BpString.body(record)
	var active := int(b.get("active_index", 0))
	list.remove_at(i)
	if i < active:
		active -= 1
	b["active_index"] = clampi(active, 0, maxi(list.size() - 1, 0))
	BpString.set_pages(record, list)
	_changed()


## An upgrade planner's mappings applied to every page (kept, as every change is).
func apply_upgrade(planner: Dictionary) -> int:
	var n := BpString.upgrade(record, planner)
	_changed()
	return n


## A page edited in its own window comes back.
func set_page(i: int, r: Dictionary) -> void:
	var list := _page_list()
	if i >= 0 and i < list.size():
		list[i] = r
		BpString.set_pages(record, list)
		_changed()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not visible or key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_DELETE and _hovered_page >= 0 and not (_sub["edit"] as LineEdit).has_focus():
		remove_page(_hovered_page)
		get_viewport().set_input_as_handled()
