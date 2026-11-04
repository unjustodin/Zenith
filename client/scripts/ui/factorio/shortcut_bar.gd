extends PanelContainer
## Factorio's shortcut bar, right of the quickbar (shortcut_bar_window_frame): every shortcut of
## shortcuts.lua in its order (Alt-mode, undo, redo, copy, cut, paste, import string, blueprint,
## blueprint book, deconstruction and upgrade planner, the equipment toggles, copper, green and red
## wire, the remotes), with its own icons (base/graphics/icons/shortcut-toolbar) on
## shortcut_bar_button and its blue, red and green kinds. Like Factorio's the buttons fill columns
## top to bottom (two rows when there is room).
##
## The ⋮ button on the right (shortcut_bar_expand_button) opens Factorio's chooser above the bar:
## a row per shortcut with its small icon, a checkbox that shows or hides it on the bar (kept in
## settings: [interface] hidden_shortcuts) and its name; shortcuts that need research the force
## hasn't done (the remotes) are greyed out there and never on the bar. Its search button filters
## the rows.
##
## `pressed(name)` goes to factorio_ui.gd, which does what the shortcut's key does, and which picks
## the number of columns and a scale so the bar fits beside the quickbar. Toggles (Alt-mode, the
## equipment) show pressed while on. Factorio's last shortcut, "Toggle visibility of tall
## entities", isn't here: its see-through fade was taken out at the owner's word.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Controls := preload("res://scripts/player/controls.gd")
const TipButton := preload("res://scripts/ui/factorio/tip_button.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")

signal pressed(name: String)

## [name, icon, tooltip (Factorio's shortcut name), action whose key is shown, style, technology
## that must be researched before it is available ("" always)], in Factorio's order: shortcuts.lua's
## `order` strings sorted, ties by name (so copper, green, red wire; the three remotes artillery,
## discharge, spidertron). The wires have no style there: plain grey buttons like the others.
const SHORTCUTS := [
	["alt", "alt-mode", "Toggle \"Alt-mode\"", "alt_mode", "", ""],
	["undo", "undo", "Undo", "undo", "", ""], ["redo", "redo", "Redo", "redo", "", ""],
	["copy", "copy", "Copy", "copy", "", ""], ["cut", "cut", "Cut", "cut", "", ""],
	["paste", "paste", "Paste", "paste", "", ""],
	["import", "import-string", "Import string", "", "", ""],
	["blueprint", "new-blueprint", "Blueprint", "give_blueprint", "blue", ""],
	["book", "new-blueprint-book", "Blueprint book", "", "blue", ""],
	["decon", "new-deconstruction-planner", "Deconstruction planner", "give_deconstruction_planner", "red", ""],
	["upgrade", "new-upgrade-planner", "Upgrade planner", "give_upgrade_planner", "green", ""],
	["roboport", "toggle-personal-roboport", "Toggle personal roboport", "toggle_personal_roboport", "", ""],
	["exoskeleton", "toggle-exoskeleton", "Toggle exoskeleton", "toggle_equipment_movement_bonus", "", ""],
	["copper-wire", "new-copper-wire", "Make copper wire", "give_copper_wire", "", ""],
	["green-wire", "new-green-wire", "Make green wire", "give_green_wire", "", ""],
	["red-wire", "new-red-wire", "Make red wire", "give_red_wire", "", ""],
	["artillery", "artillery-targeting-remote", "Create artillery targeting remote", "", "", "artillery"],
	["discharge", "discharge-defense-remote", "Create discharge defense remote", "", "", "discharge-defense-equipment"],
	["spidertron", "new-rts-tool", "Create spidertron remote", "", "", "spidertron"],
]
## Toggles: drawn pressed while on.
const TOGGLES := ["alt", "roboport", "exoskeleton"]
const STYLES := {"": "FPageButton", "blue": "FBluePageButton", "red": "FRedPageButton", "green": "FGreenPageButton"}

var _buttons := {}
var _order: Array[Button] = []
var _grid := GridContainer.new()
var _columns := 6
var _gaps: Array[Control] = []
var _available := {}  # name -> false while its equipment or research is missing
var _hidden := {}  # name -> true: unticked in the chooser
var _expand := Button.new()
## The chooser above the bar.
var chooser := PanelContainer.new()
var _rows := {}  # name -> [row, checkbox]
var _search := LineEdit.new()


func _ready() -> void:
	theme_type_variation = "FSlotWindow"
	# shortcut_bar_window_frame: no padding on the right (the expand button's column is there)
	add_theme_stylebox_override("panel", Kit.style_with_margins("slot_window", 8, 8, 4, 8))  # right_padding = 0: just the border
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	var inner := Kit.panel("FQuickbarInner")  # shortcut_bar_inner_panel
	row.add_child(inner)
	_grid.add_theme_constant_override("h_separation", 0)
	_grid.add_theme_constant_override("v_separation", 0)
	inner.add_child(_grid)
	# shortcut_bar_expand_button: 8x16 frame_button with the ⋮ dots at the top of its column
	_expand.theme_type_variation = "FFrameAction"
	_expand.focus_mode = Control.FOCUS_NONE
	_expand.toggle_mode = true
	_expand.custom_minimum_size = Kit.pxv(8, 16)
	_expand.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_expand.tooltip_text = "Choose which shortcuts show"
	var dots := GuiAssets.core_region("icons/mip/open-panel-options-8x16-white.png", Rect2i(0, 0, 8, 16))
	if dots != null:
		_expand.icon = dots
		_expand.expand_icon = true
		_expand.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_expand.add_theme_color_override("icon_hover_color", Kit.BLACK)
		_expand.add_theme_color_override("icon_pressed_color", Kit.BLACK)
	else:
		_expand.text = "⋮"
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var look := str({"normal": "frame_action", "hover": "frame_action_hover"}.get(state, "frame_action_pressed"))
		_expand.add_theme_stylebox_override(state, Kit.style_with_margins(look, 0, 0, 0, 0))
	_expand.toggled.connect(open_chooser)
	row.add_child(_expand)
	var hidden = Settings.get_value("interface", "hidden_shortcuts") if Settings.has_value("interface", "hidden_shortcuts") else []
	if hidden is Array:
		for n in hidden:
			_hidden[str(n)] = true
	for s in SHORTCUTS:
		var b := TipButton.new()
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = STYLES.get(str(s[4]), "FPageButton")
		b.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
		b.toggle_mode = TOGGLES.has(s[0])
		var icon := GuiAssets.shortcut_icon(str(s[1]))
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.add_theme_constant_override("icon_max_width", Kit.px(28))  # the x56 icons at half size
			b.add_theme_constant_override("h_separation", 0)
		else:
			b.text = str(s[2]).substr(0, 2)
		var keys := Controls.keys_text(str(s[3])) if str(s[3]) != "" else ""
		b.tooltip_text = str(s[2]) + (" (%s)" % keys if keys != "" else "")
		var name := str(s[0])
		b.pressed.connect(func() -> void: pressed.emit(name))
		_grid.add_child(b)
		_buttons[name] = b
		_order.append(b)
		if str(s[5]) != "":
			_available[name] = false
	_build_chooser()
	_refresh_visible()


## Shows a toggle shortcut on or off (Alt-mode).
func set_on(name: String, on: bool) -> void:
	var b: Button = _buttons.get(name)
	if b != null:
		b.set_pressed_no_signal(on)


func is_on(name: String) -> bool:
	var b: Button = _buttons.get(name)
	return b != null and b.button_pressed


## Whether a shortcut can be used: the equipment toggles while the armour has the equipment, the
## remotes once researched (Factorio shows those only when unlocked).
func show_shortcut(name: String, on: bool) -> void:
	if _available.get(name, true) != on:
		_available[name] = on
		_refresh_visible()


## The remotes once their technology is researched (techs: ui_model.gd's, state 2 = researched).
func update_unlocks(techs: Dictionary) -> void:
	for s in SHORTCUTS:
		if str(s[5]) != "":
			show_shortcut(str(s[0]), int(techs.get(str(s[5]), {}).get("state", 0)) == 2)


## Shows or hides a shortcut on the bar, as the chooser's checkbox does (saved in the settings).
func choose(name: String, on: bool) -> void:
	if on:
		_hidden.erase(name)
	else:
		_hidden[name] = true
	Settings.set_value("interface", "hidden_shortcuts", _hidden.keys())
	_refresh_visible()


func set_columns(n: int) -> void:
	_columns = clampi(n, 1, SHORTCUTS.size())
	_arrange()


## The number of shortcuts showing.
func shown_count() -> int:
	return _order.filter(func(b: Button) -> bool: return b.visible).size()


func button(name: String) -> Button:
	return _buttons.get(name)


# --- the chooser -------------------------------------------------------------------------------

## Factorio's chooser: a frame with search and close buttons over a list of rows.
func _build_chooser() -> void:
	chooser.theme_type_variation = "FFrame"
	chooser.theme = EntityPanels.theme()  # Factorio's checkboxes
	chooser.top_level = true
	chooser.visible = false
	chooser.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(chooser)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(8))
	chooser.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Kit.px(8))
	head.custom_minimum_size.y = Kit.px(28)
	col.add_child(head)
	_search.placeholder_text = "Search"
	_search.visible = false
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_filter)
	head.add_child(_search)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(space)
	var find := Kit.close_button()
	find.tooltip_text = "Search"
	var lens := GuiAssets.core_sprite("icons/search.png")
	if lens != null:
		find.icon = lens
	var toggle_search := func() -> void:
		_search.visible = not _search.visible
		space.visible = not _search.visible
		if _search.visible:
			_search.grab_focus()
		else:
			_search.text = ""
			_filter("")
	find.pressed.connect(toggle_search)
	head.add_child(find)
	var close := Kit.close_button()
	close.pressed.connect(func() -> void: open_chooser(false))
	head.add_child(close)
	var list_frame := Kit.panel("FDeepFrame")
	col.add_child(list_frame)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	list_frame.add_child(list)
	for s in SHORTCUTS:
		var name := str(s[0])
		var r := PanelContainer.new()
		r.theme_type_variation = "FSubheader"  # shortcut_selection_row: a dark strip with a line under it
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", Kit.px(8))
		r.add_child(h)
		# the shortcut's small icon (x24) on a small button of its kind
		var icon := Button.new()
		icon.theme_type_variation = STYLES.get(str(s[4]), "FPageButton")
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.focus_mode = Control.FOCUS_NONE
		icon.custom_minimum_size = Kit.pxv(20, 20)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.icon = GuiAssets.data_sprite("base/graphics/icons/shortcut-toolbar/mip/%s-x24.png" % str(s[1]))
		if icon.icon == null:
			icon.icon = GuiAssets.shortcut_icon(str(s[1]))
		icon.expand_icon = true
		icon.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for state in ["normal", "hover", "pressed", "disabled"]:
			var kind := str(STYLES.get(str(s[4]), "FPageButton")).trim_prefix("F").to_snake_case()
			icon.add_theme_stylebox_override(state, Kit.style_with_margins(kind, 2, 2, 2, 2))
		h.add_child(icon)
		var c := CheckBox.new()
		c.text = str(s[2])
		c.focus_mode = Control.FOCUS_NONE
		c.button_pressed = not _hidden.has(name)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.toggled.connect(func(on: bool) -> void: choose(name, on))
		h.add_child(c)
		var grip := Kit.panel("FDraggable")  # Factorio's reorder handle (dragging isn't copied)
		grip.custom_minimum_size = Kit.pxv(16, 20)
		grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(grip)
		list.add_child(r)
		_rows[name] = [r, c]
	chooser.custom_minimum_size.x = Kit.px(490)


func open_chooser(on: bool) -> void:
	_expand.set_pressed_no_signal(on)
	chooser.visible = on
	if on:
		_refresh_chooser()
		chooser.reset_size()
		_place_chooser()


func chooser_open() -> bool:
	return chooser.visible


func _process(_delta: float) -> void:
	if chooser.visible:
		_place_chooser()


## Over the bar, its left edge on the bar's, kept inside the window.
func _place_chooser() -> void:
	var bar := get_global_rect()
	var view := get_viewport_rect().size
	var s := chooser.size
	chooser.global_position = Vector2(clampf(bar.position.x, 0.0, maxf(0.0, view.x - s.x)), maxf(0.0, bar.position.y - s.y))


func _refresh_chooser() -> void:
	for s in SHORTCUTS:
		var name := str(s[0])
		var c: CheckBox = _rows[name][1]
		var usable: bool = str(s[5]) == "" or bool(_available.get(name, false))
		c.disabled = not usable
		c.set_pressed_no_signal(usable and not _hidden.has(name))
		c.modulate = Color.WHITE if usable else Color(1, 1, 1, 0.45)


func _filter(text: String) -> void:
	var t := text.strip_edges().to_lower()
	for s in SHORTCUTS:
		var r: Control = _rows[str(s[0])][0]
		r.visible = t == "" or str(s[2]).to_lower().contains(t)


func _refresh_visible() -> void:
	for s in SHORTCUTS:
		var name := str(s[0])
		var b: Button = _buttons[name]
		b.visible = bool(_available.get(name, true)) and not _hidden.has(name)
	if chooser.visible:
		_refresh_chooser()
	_arrange()


## The grid fills rows, Factorio's bar fills columns: put the visible buttons in the order that
## reads top to bottom, then left to right.
func _arrange() -> void:
	var shown: Array[Button] = []
	for b in _order:
		if b.visible:
			shown.append(b)
	var cols := mini(_columns, maxi(1, shown.size()))
	var rows := ceili(float(shown.size()) / cols)
	cols = ceili(float(shown.size()) / maxi(1, rows))
	_grid.columns = maxi(1, cols)
	for gap in _gaps:
		_grid.remove_child(gap)
		gap.queue_free()
	_gaps.clear()
	var placed := 0
	for r in rows:
		for c in cols:
			var i := c * rows + r
			if i < shown.size():
				_grid.move_child(shown[i], placed)
			else:  # the last column's empty cells: Factorio's dark slot recess
				var gap := Kit.empty_cell()
				_grid.add_child(gap)
				_grid.move_child(gap, placed)
				_gaps.append(gap)
			placed += 1
	for b in _order:
		if not b.visible:
			_grid.move_child(b, _grid.get_child_count() - 1)
