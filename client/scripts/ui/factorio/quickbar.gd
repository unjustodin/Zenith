extends VBoxContainer
## Factorio's quickbar at the bottom: a slot window (quick_bar_slot_window_frame) with the two
## quickbar rows Factorio shows by default, each 10 slot buttons, and left of them the page
## buttons (quick_bar_page_button) with each row's page number. The lower row is the page in use:
## number keys 1-0 (factorio_ui.gd) select its slots' items for building; clicking a slot does the
## same, or pins the held item when the slot is empty or holds something else; right click clears
## it. The upper row shows another page (the next one until X swaps the rows or the page chooser
## sets it; the mod keeps 10, while the client's own quickbar has one so it stays empty then). Inventory slots can be dragged onto both. Each slot shows its pinned item and
## how many the inventory has (faded when none). The HUD's mining progress and the character's
## health bar sit just above it (add_bar), where Factorio draws them.
##
## Clicking a page button opens Factorio's page chooser over the quickbar: all ten pages, 0 at the
## top down to 1, each a page button and its ten slots. Clicking a page's button there shows that
## page in the row whose button opened it; its slots work like the quickbar's own.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")

## A slot of the lower row (the page in use) was clicked: index 0-9.
signal slot_clicked(index: int, button_index: int)
## A slot of the upper row was clicked: index 0-9.
signal upper_clicked(index: int, button_index: int)
## A slot of a page in the page chooser was clicked: page 1-10, index 0-9.
signal page_slot_clicked(page: int, index: int, button_index: int)

## quick_bar_slot_window_frame's minimal_width.
const MIN_WIDTH := 468

var model: UiModel
## The item held for building, to highlight its slot.
var held_item := ""

## The slot window itself (factorio_ui.gd puts the weapon slots and shortcut bar beside it).
var frame := Kit.panel("FSlotWindow")  # quick_bar_slot_window_frame

var _slots: Array[Slot] = []  # the lower row
var _upper: Array[Slot] = []
var _pages: Array[Button] = []  # [upper, lower]
## The page chooser (top_level, over the quickbar) and the row it was opened for (0 upper, 1 lower).
var chooser := PanelContainer.new()
var _chooser_row := 1
var _chooser_slots := {}  # page -> Array[Slot]
var _chooser_pages := {}  # page -> Button


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", Kit.px(4))

	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.custom_minimum_size.x = Kit.px(MIN_WIDTH)
	add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(8))  # slot_window_frame's horizontal_spacing
	frame.add_child(row)
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 0)
	row.add_child(pages)
	for i in 2:
		var b := Button.new()
		b.theme_type_variation = "FPageButton"
		b.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.toggle_mode = true  # drawn pressed while its page chooser is open
		var row_index := i
		b.pressed.connect(func() -> void: open_chooser(row_index, not (chooser.visible and _chooser_row == row_index)))
		pages.add_child(b)
		_pages.append(b)
	var inner := Kit.panel("FQuickbarInner")
	row.add_child(inner)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	inner.add_child(rows)
	for r in 2:
		var cells := HBoxContainer.new()
		cells.add_theme_constant_override("separation", 0)
		rows.add_child(cells)
		for index in UiModel.QUICKBAR_SLOTS:
			var s := Slot.new()
			s.theme_type_variation = "FSlotButton"
			s.toggle_mode = true
			var lower := r == 1
			var on_click := func(button_index: int, _shift: bool) -> void:
				if lower:
					slot_clicked.emit(index, button_index)
				else:
					upper_clicked.emit(index, button_index)
			s.clicked.connect(on_click)
			if lower:
				s.on_drop = func(item: String) -> void: model.pin(index, item)
			else:
				s.on_drop = func(item: String) -> void: model.pin_on_page(model.quickbar_upper_page(), index, item)
			s.toggled.connect(func(_on: bool) -> void: refresh.call_deferred())  # only held_item decides
			cells.add_child(s)
			(_slots if lower else _upper).append(s)
	_build_chooser()
	model.quickbar_changed.connect(refresh)
	model.inventory_changed.connect(refresh)
	refresh()


func _build_chooser() -> void:
	chooser.theme_type_variation = "FSlotWindow"
	chooser.top_level = true
	chooser.visible = false
	add_child(chooser)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(4))
	chooser.add_child(col)
	var head := HBoxContainer.new()
	head.custom_minimum_size.y = Kit.px(28)
	col.add_child(head)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(space)
	var close := Kit.close_button()
	close.pressed.connect(func() -> void: open_chooser(_chooser_row, false))
	head.add_child(close)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(8))
	col.add_child(row)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 0)
	row.add_child(buttons)
	var inner := Kit.panel("FQuickbarInner")
	row.add_child(inner)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	inner.add_child(rows)
	for k in 10:
		var page := 10 - k  # 10 (shown as 0) at the top down to 1
		var b := Button.new()
		b.theme_type_variation = "FPageButton"
		b.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.text = str(page % 10)
		b.tooltip_text = "Quickbar page %d" % page
		b.pressed.connect(func() -> void: pick_page(page))
		buttons.add_child(b)
		_chooser_pages[page] = b
		var cells := HBoxContainer.new()
		cells.add_theme_constant_override("separation", 0)
		rows.add_child(cells)
		var slots: Array[Slot] = []
		for index in UiModel.QUICKBAR_SLOTS:
			var s := Slot.new()
			s.theme_type_variation = "FSlotButton"
			var on_click := func(button_index: int, _shift: bool) -> void: page_slot_clicked.emit(page, index, button_index)
			s.clicked.connect(on_click)
			s.on_drop = func(item: String) -> void: model.pin_on_page(page, index, item)
			cells.add_child(s)
			slots.append(s)
		_chooser_slots[page] = slots


## Opens (or closes) the page chooser for a row: 0 the upper, 1 the lower (the page in use).
func open_chooser(row_index: int, on: bool) -> void:
	_chooser_row = row_index
	chooser.visible = on
	for i in _pages.size():
		_pages[i].set_pressed_no_signal(on and i == row_index)
	if on:
		_refresh_chooser()
		chooser.reset_size()
		_place_chooser()


func chooser_open() -> bool:
	return chooser.visible


## Shows the page in the row the chooser was opened for, and closes it.
func pick_page(page: int) -> void:
	if _chooser_row == 0:
		model.quickbar_upper = page
		refresh()
	else:
		model.select_quickbar_page(page)
	open_chooser(_chooser_row, false)


func _process(_delta: float) -> void:
	if chooser.visible:
		_place_chooser()


## Over the quickbar, its left edge on the quickbar's.
func _place_chooser() -> void:
	var bar := frame.get_global_rect()
	chooser.global_position = Vector2(bar.position.x, maxf(0.0, bar.position.y - Kit.px(4) - chooser.size.y))


func _refresh_chooser() -> void:
	var shown := model.quickbar_upper_page() if _chooser_row == 0 else model.quickbar_page
	for page: int in _chooser_slots:
		var names := model.quickbar_page_items(page) if model.server_quickbar else []
		if not model.server_quickbar and page == model.quickbar_page:
			names = model.quickbar
		var slots: Array = _chooser_slots[page]
		for i in slots.size():
			var item := str(names[i]) if i < names.size() else ""
			var s: Slot = slots[i]
			if item == "":
				s.set_stack("", -1)
			else:
				var n := model.count_of(item)
				s.set_stack(item, n, n == 0)
			s.set_tip(Kit.pretty(item) if item != "" else "Quickbar page %d, slot %d" % [page, i + 1], [])
		var b: Button = _chooser_pages[page]
		b.set_pressed_no_signal(page == shown)


## A bar over the quickbar, as wide as it; the last one added sits lowest.
func add_bar(bar: Control) -> void:
	bar.size_flags_horizontal = Control.SIZE_FILL
	add_child(bar)
	move_child(bar, frame.get_index())


## Shows both rows, or only the page in use (windows too low for two, where Factorio's own GUI
## would run into the minimap).
func set_two_rows(on: bool) -> void:
	if _upper.is_empty() or _upper[0].get_parent().visible == on:
		return
	_upper[0].get_parent().visible = on
	_pages[0].get_parent().visible = on  # the page buttons too: room is short there
	frame.custom_minimum_size.x = Kit.px(MIN_WIDTH) if on else 0
	reset_size()


func set_held(item: String) -> void:
	if item != held_item:
		held_item = item
		refresh()


func refresh() -> void:
	if chooser.visible:
		_refresh_chooser()
	var upper_page := model.quickbar_upper_page()
	_pages[0].text = str(upper_page % 10)
	_pages[0].tooltip_text = "Quickbar page %d" % upper_page
	_pages[1].text = str(model.quickbar_page % 10)
	_pages[1].tooltip_text = "Quickbar page %d (click: choose another page; Shift+1-0 or X)" % model.quickbar_page
	for i in _slots.size():
		_show(_slots[i], str(model.quickbar[i]), str((i + 1) % 10))
	var names := model.quickbar_page_items(upper_page)
	for i in _upper.size():
		_show(_upper[i], str(names[i]), "")


func _show(s: Slot, item: String, key: String) -> void:
	# Factorio: an empty slot has no tooltip; a pinned one has the item's, with the way to clear it
	# first ("Middle-click to clear shortcut.") and none of the other clicks.
	if item == "":
		s.set_stack("", -1)
		s.set_tip("", [])
	else:
		var n := model.count_of(item)
		s.set_stack(item, n, n == 0)
		s.set_extra({"icons": model.icons_of(item)})
		s.set_tip(Kit.pretty(item), [["Middle-click| to clear shortcut.", "", null, "keys"]])
	s.set_pressed_no_signal(item != "" and item == held_item)
