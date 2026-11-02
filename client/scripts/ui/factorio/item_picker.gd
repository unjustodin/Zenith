extends PanelContainer
## Factorio's "choose an item / signal" dialog (choose-elem-button's popup): a search field and a
## grid of every item (and, for signals, fluids and virtual signals) as slot buttons. Click one to
## pick it; right click or Esc closes. factorio_ui.gd owns one; machine screens open it with
## `choose(kinds, callback)`, and the callback gets (type, name): "item", "fluid", "virtual" or
## "entity" (enemies, for a turret's priority targets).
##
## The item list is the mod's item dictionary (iprotos), so it holds every item the game knows,
## sorted by name (the bridge has no item groups for items that can't be hand-crafted).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

## Factorio's virtual signals (base game).
const VIRTUAL := [
	"signal-everything", "signal-anything", "signal-each", "signal-0", "signal-1", "signal-2", "signal-3", "signal-4",
	"signal-5", "signal-6", "signal-7", "signal-8", "signal-9", "signal-A", "signal-B", "signal-C", "signal-D",
	"signal-E", "signal-F", "signal-G", "signal-H", "signal-I", "signal-J", "signal-K", "signal-L", "signal-M",
	"signal-N", "signal-O", "signal-P", "signal-Q", "signal-R", "signal-S", "signal-T", "signal-U", "signal-V",
	"signal-W", "signal-X", "signal-Y", "signal-Z", "signal-red", "signal-green", "signal-blue", "signal-yellow",
	"signal-pink", "signal-cyan", "signal-white", "signal-grey", "signal-black", "signal-check", "signal-info", "signal-dot",
]
## Internal items that never go in a filter.
const HIDDEN := ["item-unknown", "blueprint", "blueprint-book", "deconstruction-planner", "upgrade-planner",
	"copy-paste-tool", "cut-paste-tool", "selection-tool", "spidertron-remote", "artillery-targeting-remote",
	"discharge-defense-remote"]
const ROWS := 8

## Item names (and fluid names) to choose from; factorio_ui.gd fills these from the prototypes.
var items: Callable  # -> Array of item names
var fluids: Callable  # -> Array of fluid names
var entities: Callable  # -> Array of entity names a turret can target

var _search: LineEdit
## The value area under the grid, Factorio's two shapes: "Or set a constant" (a decider's or
## arithmetic combinator's second operand: a header, a slider, the number and "Set constant") and a
## constant combinator signal's value ("Set request": the number, a slider and the green tick).
var _constant_row: VBoxContainer
var _constant_head: Control
var _constant_box: LineEdit
var _constant_slider: HSlider
var _constant_ok: Button
var _value_tick: Button
var _on_constant := Callable()
var _grid := Kit.slot_grid()
var _title: Label
var _kinds: Array = ["item"]
var _callback := Callable()


func _ready() -> void:
	theme = MenuKit.theme()
	theme_type_variation = "FFrame"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	z_index = 20
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Select an item", true)
	_title = bar.get_child(0)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(close)
	box.add_child(bar)
	_search = MenuKit.textbox("", "Search")
	_search.custom_minimum_size.x = Kit.px(Kit.SLOT * Kit.COLUMNS)
	_search.text_changed.connect(func(_t: String) -> void: _fill())
	box.add_child(_search)
	var deep: Array = Kit.deep_scroll(Kit.pxv(Kit.SLOT * Kit.COLUMNS, Kit.SLOT * ROWS))
	box.add_child(deep[0])
	deep[1].add_child(_grid)
	_build_value_area(box)


## Opens the dialog for these kinds ("item", "fluid", "virtual"); `callback(type, name)` gets the
## choice.
func choose(kinds: Array, callback: Callable, title := "") -> void:
	_constant_row.visible = false
	_on_constant = Callable()
	_kinds = kinds
	_callback = callback
	_title.text = title if title != "" else ("Select a signal" if kinds.size() > 1 else
		{"fluid": "Select a fluid", "entity": "Select an entity"}.get(str(kinds[0]) if not kinds.is_empty() else "", "Select an item"))
	_search.text = ""
	_fill()
	visible = true
	reset_size()
	_search.grab_focus.call_deferred()


func _build_value_area(box: VBoxContainer) -> void:
	_constant_row = VBoxContainer.new()
	_constant_row.name = "ConstantRow"
	_constant_row.add_theme_constant_override("separation", Kit.px(4))
	_constant_row.visible = false
	var head := Kit.panel("FSubheader")
	head.custom_minimum_size.y = Kit.px(32)
	var hl := Kit.label("Or set a constant", "FHeading")
	hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", Kit.px(8))
	hm.add_child(hl)
	head.add_child(hm)
	_constant_head = head
	_constant_row.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(8))
	_constant_box = MenuKit.textbox("0")
	_constant_box.name = "ConstantBox"
	_constant_box.custom_minimum_size.x = Kit.px(80)
	_constant_box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_constant_box.text_submitted.connect(func(_t: String) -> void: _set_constant())
	_constant_slider = MenuKit.slider(0, 100, 1, 0)
	_constant_slider.name = "ConstantSlider"
	_constant_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_constant_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_constant_slider.value_changed.connect(func(v: float) -> void:
		if _constant_box.text.strip_edges() != str(int(v)):
			_constant_box.text = str(int(v)))
	row.add_child(_constant_slider)
	row.add_child(_constant_box)
	_constant_ok = MenuKit.button("Set constant", "FGreenButton")
	_constant_ok.name = "ConstantOk"
	_constant_ok.pressed.connect(_set_constant)
	row.add_child(_constant_ok)
	_value_tick = Button.new()
	_value_tick.name = "ValueOk"
	_value_tick.theme_type_variation = "FGreenButton"
	_value_tick.custom_minimum_size = Kit.pxv(28, 28)
	_value_tick.focus_mode = Control.FOCUS_NONE
	_value_tick.tooltip_text = "Confirm"
	var tick := GuiAssets.core_sprite("icons/mip/confirm.png")
	if tick != null:
		_value_tick.icon = tick
		_value_tick.expand_icon = true
		_value_tick.add_theme_constant_override("icon_max_width", Kit.px(20))
	else:
		_value_tick.text = "✔"
	_value_tick.pressed.connect(_set_constant)
	row.add_child(_value_tick)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(8))
	pad.add_child(row)
	_constant_row.add_child(pad)
	box.add_child(_constant_row)


## The chooser of a "signal or constant" operand: the signals, and under them "Or set a constant"
## holding `constant`; on_constant(value) gets a constant set.
func choose_or_constant(kinds: Array, callback: Callable, constant: int, on_constant: Callable) -> void:
	choose(kinds, callback, "Select a signal")
	_show_value(constant, on_constant, true)


## A constant combinator's signal: the chooser to swap the signal, and its value under the grid
## (a number box, a slider and the green tick), as Factorio's "Set request" popup.
func choose_with_value(kinds: Array, callback: Callable, value: int, on_value: Callable) -> void:
	choose(kinds, callback, "Set request")
	_show_value(value, on_value, false)


func _show_value(value: int, on_value: Callable, constant: bool) -> void:
	_on_constant = on_value
	_constant_row.visible = true
	_constant_head.visible = constant
	_constant_ok.visible = constant
	_value_tick.visible = not constant
	# Factorio's order: the slider, then the number for a constant; the number first for a value.
	var row := _constant_box.get_parent()
	row.move_child(_constant_box, 1 if constant else 0)
	_constant_slider.max_value = maxf(100.0, float(absi(value)) * 2.0)
	_constant_slider.set_value_no_signal(clampf(value, _constant_slider.min_value, _constant_slider.max_value))
	_constant_box.text = str(value)
	reset_size()
	_constant_box.grab_focus.call_deferred()
	_constant_box.select_all.call_deferred()


func _set_constant() -> void:
	var t := _constant_box.text.strip_edges()
	if not t.is_valid_int() or not _on_constant.is_valid():
		return
	var f := _on_constant
	close()
	f.call(int(t))


func close() -> void:
	_on_constant = Callable()
	visible = false
	_search.release_focus()
	_callback = Callable()


func is_open() -> bool:
	return visible


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and key.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _fill() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var q := _search.text.strip_edges().to_lower()
	var cells := 0
	for kind in _kinds:
		var names: Array = []
		if kind == "item" and items.is_valid():
			names = items.call()
		elif kind == "fluid" and fluids.is_valid():
			names = fluids.call()
		elif kind == "virtual":
			names = VIRTUAL
		elif kind == "entity" and entities.is_valid():
			names = entities.call()
		names = names.duplicate()
		names.sort()
		for n in names:
			var name := str(n)
			if HIDDEN.has(name) or (q != "" and not (name.contains(q) or Kit.pretty(name).to_lower().contains(q))):
				continue
			var s := Slot.new()
			s.theme_type_variation = "FSlotButton"
			s.set_stack(name, -1)
			s.set_tip(Kit.pretty(name))
			var type_name: String = kind
			var on_click := func(button_index: int, _shift: bool) -> void:
				if button_index == MOUSE_BUTTON_LEFT and _callback.is_valid():
					var f := _callback
					close()
					f.call(type_name, name)
				elif button_index == MOUSE_BUTTON_RIGHT:
					close()
			s.clicked.connect(on_click)
			_grid.add_child(s)
			cells += 1
		# Each kind starts a row, like Factorio's groups.
		while cells % Kit.COLUMNS != 0:
			_grid.add_child(Kit.empty_cell())
			cells += 1
	while cells < Kit.COLUMNS * ROWS:
		_grid.add_child(Kit.empty_cell())
		cells += 1
