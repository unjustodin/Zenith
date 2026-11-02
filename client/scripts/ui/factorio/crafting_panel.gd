extends VBoxContainer
## The hand-crafting side of the character window, laid out like Factorio's: the item group tabs
## (when the mod sends groups), then the selected group's recipes as a 10-wide grid of slot
## buttons, a new row for each subgroup. Recipes the inventory can't make now are red. Click:
## craft 1, right click: 5, Shift+click: as many as possible, like Factorio. The tooltip lists
## ingredients (red where short), time and products once the mod sends them. Ctrl+F (or the
## search field in the title bar) filters recipes by name across every group, as Factorio's search.
## The group tabs are filter_group_tab buttons (71 wide at least, 72 high) stretched over the
## width, five to a row as in Factorio's 10-slot-wide panel.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")

## Rows of recipes visible at once, with and without tabs (the panel then matches the inventory).
const ROWS_WITH_TABS := 6
const ROWS := 8
const TABS_PER_ROW := 5

var model: UiModel

var _tabs := GridContainer.new()
var _tab_strip := Kit.panel("FDeepFrame")
var _grid := Kit.slot_grid()
var _scroll: ScrollContainer
var _group := ""
var _shown_sig := ""
## Factorio's recipe search: shown with Ctrl+F; while it has text the grid holds every match.
var search: LineEdit


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	search = MenuKit.textbox("", "Search recipes (Esc: clear)")
	search.theme = MenuKit.theme()
	search.visible = false
	search.text_changed.connect(func(_t: String) -> void: _fill_grid())
	search.gui_input.connect(_on_search_key)
	add_child(search)
	_tabs.add_theme_constant_override("h_separation", 0)
	_tabs.add_theme_constant_override("v_separation", 0)
	_tab_strip.add_child(_tabs)
	add_child(_tab_strip)
	var pane := Kit.panel("FTabPane")
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pane)
	var deep: Array = Kit.deep_scroll(Kit.pxv(Kit.SLOT * Kit.COLUMNS, Kit.SLOT * ROWS_WITH_TABS))
	pane.add_child(deep[0])
	_scroll = deep[1]
	_scroll.add_child(_grid)
	model.recipes_changed.connect(_rebuild)
	model.inventory_changed.connect(_refresh_counts)
	visibility_changed.connect(func() -> void:
		if _counts_stale and is_visible_in_tree():
			_refresh_counts())
	_rebuild()


func _rebuild() -> void:
	if model.groups.size() > 0 and not model.groups.has(_group):
		_group = model.groups[0]
	var with_tabs := model.groups.size() > 1
	_tab_strip.visible = with_tabs
	_scroll.custom_minimum_size.y = Kit.px(Kit.SLOT * (ROWS_WITH_TABS if with_tabs else ROWS))
	for child in _tabs.get_children():
		_tabs.remove_child(child)  # out of the layout now, not at the end of the frame
		child.queue_free()
	_tabs.columns = clampi(model.groups.size(), 1, TABS_PER_ROW)
	if with_tabs:
		for g in model.groups:
			_tabs.add_child(_tab(str(g)))
	_fill_grid()


## Ctrl+F: shows the search field and puts the keys in it.
func focus_search() -> void:
	search.visible = true
	search.grab_focus()
	search.select_all()


func _on_search_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.physical_keycode == KEY_ESCAPE:
		search.text = ""
		search.visible = false
		search.release_focus()
		_fill_grid()
		search.accept_event()


func _tab(group: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = "FTab"
	b.toggle_mode = true
	b.button_pressed = group == _group
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Kit.pxv(71, 72)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = Kit.group_name(group)
	var icon := GuiAssets.group_icon(group)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", Kit.px(64))
	else:
		b.text = Kit.group_name(group)
		b.clip_text = true
	var pick := func() -> void:
		_group = group
		for t in _tabs.get_children():
			(t as Button).set_pressed_no_signal(t == b)
		_fill_grid()
	b.pressed.connect(pick)
	return b


func _fill_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)  # out of the layout now, not at the end of the frame
		child.queue_free()
	var with_tabs := model.groups.size() > 1
	var cells := 0
	var subgroup := ""
	var query := search.text.strip_edges().to_lower() if search != null else ""
	for r in model.recipes:
		if query != "":
			var name := str(r["name"])
			if not (name.contains(query) or Kit.recipe_name(name).to_lower().contains(query)):
				continue
		elif with_tabs and r["group"] != _group:
			continue
		if r["subgroup"] != subgroup and cells % Kit.COLUMNS != 0:
			while cells % Kit.COLUMNS != 0:  # each subgroup starts a row, as in Factorio
				_grid.add_child(Kit.empty_cell())
				cells += 1
		subgroup = r["subgroup"]
		_grid.add_child(_recipe_slot(r))
		cells += 1
	var rows := ROWS_WITH_TABS if with_tabs else ROWS
	while cells < rows * Kit.COLUMNS or cells % Kit.COLUMNS != 0:
		_grid.add_child(Kit.empty_cell())
		cells += 1


func _recipe_slot(r: Dictionary) -> Slot:
	var s := Slot.new()
	var name: String = r["name"]
	s.item = _icon_item(r)
	s.set_meta("recipe", name)
	_style_recipe(s, r)
	var craft := func(button_index: int, shift: bool) -> void:
		if button_index == MOUSE_BUTTON_MIDDLE:
			return
		var n := 5 if button_index == MOUSE_BUTTON_RIGHT else 1
		if shift:  # Factorio: as many as the inventory has ingredients for
			n = maxi(1, int(model.recipe(name).get("craftable", 1)))
		model.craft(name, n)
	s.clicked.connect(craft)
	return s


## Factorio's recipe tooltip: "Ingredients:" (have/need in red where the inventory is short),
## the crafting time, "Products:". The item's own lines follow (Slot.info), as Factorio's second box.
func _tip_lines(r: Dictionary) -> Array:
	return recipe_tip_lines(model, r)


static func recipe_tip_lines(m, r: Dictionary) -> Array:
	var lines: Array = []
	if not r.get("ingredients", []).is_empty():
		lines.append(["Ingredients:"])
		for ing in r["ingredients"]:
			if ing is Array and ing.size() >= 2:
				var have: int = m.count_of(str(ing[0]))
				var short := have < float(ing[1])
				var amount := ("%d/%s" % [have, _amount(float(ing[1]))]) if short else _amount(float(ing[1]))
				lines.append(["%s × %s" % [amount, Kit.pretty(str(ing[0]))], str(ing[0]), Kit.RED_TEXT if short else Kit.WHITE])
	if float(r.get("energy", -1.0)) >= 0.0:
		lines.append(["⏱ %s s Crafting time" % str(snappedf(float(r["energy"]), 0.01))])
	var products: Array = r.get("products", [])
	if not products.is_empty():
		lines.append(["Products:"])
		for p in products:
			if p is Array and p.size() >= 2:
				lines.append(["%s × %s" % [_amount(float(p[1])), Kit.pretty(str(p[0]))], str(p[0])])
	return lines


static func _amount(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.01))


## Red when the inventory can't make it (only known with ingredient data), with the count it can.
func _style_recipe(s: Slot, r: Dictionary) -> void:
	var n: int = r["craftable"]
	s.theme_type_variation = "FRedSlotButton" if n == 0 else "FSlotButton"
	s.count = n if n > 0 else -1
	s.set_tip("%s (Recipe)" % Kit.recipe_name(str(r["name"])), _tip_lines(r))
	s.queue_redraw()


## The icon to show: the recipe's own name is an item for almost every hand recipe; otherwise its
## first product.
func _icon_item(r: Dictionary) -> String:
	var products: Array = r["products"]
	if products.size() == 1 and products[0] is Array:
		return str(products[0][0])
	return r["name"]


## Closed, only noted (as character_window.gd's slots): drawn when the panel shows.
var _counts_stale := false


func _refresh_counts() -> void:
	if not is_visible_in_tree():
		_counts_stale = true
		return
	_counts_stale = false
	for child in _grid.get_children():
		if child is Slot and child.has_meta("recipe"):
			var r := model.recipe(str(child.get_meta("recipe")))
			if not r.is_empty():
				_style_recipe(child, r)
