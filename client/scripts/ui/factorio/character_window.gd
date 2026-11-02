extends Control
## Factorio's character window, centred on screen: the main inventory as a 10-wide slot grid on
## the left ("Character") with the armour, gun and ammo slots under it, and on the right either
## hand-crafting ("Crafting", E) or the open machine's screen. Slots report clicks (inventory role
## and 1-based slot) and hovers to factorio_ui.gd, which decides what they do, and inventory
## stacks can be dragged onto the quickbar. Over the inventory sit Factorio's colour picker and
## colour buttons; under its slot rows Factorio's faint empty rows fill the frame. The Logistics
## part is Factorio's: "Personal logistics" and "Trash unrequested" with the network's status dot,
## the requests as the "Main" section (a 10-wide grid; Factorio's other sections aren't sent by the
## bridge) with "Add section" under it, then the trash slots, from the logistics data
## (ui_model.char_requests, network), or a note without it. The Character tab is Factorio's
## character info: bonuses, distances and speeds (`cinfo`).
##
## Right click on armour with an equipment grid opens it as Factorio does: one window titled with
## the armour's name, the inventory on the left and "Equipment grid" on the right (the whole grid,
## equipment_grid.gd, and what it adds up to: grid size, battery and shield capacity, roboports).
## An open vehicle with a grid (tank, spidertron, car with equipment) shows its grid in a panel
## right of its screen.
##
## Other windows for an opened item join the inventory the same way (show_side): the blueprint
## book, deconstruction and upgrade planners and the blueprint library (planner_ui.gd).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const CraftingPanel := preload("res://scripts/ui/factorio/crafting_panel.gd")
const MachineScreen := preload("res://scripts/ui/factorio/machine_screen.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const EquipmentGrid := preload("res://scripts/ui/factorio/equipment_grid.gd")
const LogicWindows := preload("res://scripts/ui/factorio/logic_windows.gd")
const PlanetInfo := preload("res://scripts/ui/factorio/planet_info.gd")
const ProductionPanels := preload("res://scripts/ui/factorio/production_panels.gd")

## A slot of one of the character's inventories was clicked ("main", "guns", "ammo", "armor").
signal slot_clicked(role: String, index: int, button_index: int, shift: bool, ctrl: bool)
signal close_requested
## The colour picker or colour button was clicked.
signal color_requested
## A cell of an equipment grid was clicked ("char" or "veh").
signal grid_clicked(kind: String, cell: Vector2i, button_index: int, shift: bool)

## Inventory rows visible at once before it scrolls (Factorio shows every row of a big inventory;
## the empty striped rows fill the rest of the part).
const ROWS := 8
const MAX_ROWS := 12
## Factorio's default player colour, shown on the colour button (the bridge doesn't send it).
const PLAYER_COLOR := Color(0.869, 0.5, 0.13)
const EQUIPMENT := {"armor": 1, "guns": 3, "ammo": 3}
const EMPTY_ICONS := {"armor": "empty-armor-slot", "guns": "empty-gun-slot", "ammo": "empty-ammo-slot"}

var model: UiModel
var screen: MachineScreen
## The item under the mouse in the character's slots, or "".
var hovered_item := ""
## Where the stack in the cursor came from: [role, index], or [] (factorio_ui.gd sets it).
var hand_slot: Array = []

var crafting_open := false
## Factorio shows the armour's grid only when the armour is opened (right click on it), not with
## every inventory.
var armor_open := false

var _grid := Kit.slot_grid()
var _equipment := {}  # role -> [Slot]
var _crafting_frame := Kit.panel("FFrameRight")
var _logistics_frame := Kit.panel("FFrameMiddle")
var _char_frame := Kit.panel("FFrameLeft")
var _char_caption: Label
## "Character" over the inventory inside an entity's window (where the title is the entity's).
var _inv_heading := Kit.label("Character")
var _sort_button: Button
var _inv_scroll: ScrollContainer
var _stripes: Control
var _crafting_caption: Label
var _crafting: CraftingPanel
var _logistics := VBoxContainer.new()
var _tab_buttons := {}
var _trash_box := VBoxContainer.new()
var _trash_grid := Kit.slot_grid()
var _logistics_sig := "-"
var _color_swatch: ColorPickerButton
var _info := VBoxContainer.new()
## The armour's grid (left of the inventory) and the open vehicle's (right of its screen).
var armor_grid: EquipmentGrid
var vehicle_grid: EquipmentGrid
var _armor_frame := Kit.panel("FFrame")
var _armor_title: Label
var _armor_summary := VBoxContainer.new()
var _armor_switches := HBoxContainer.new()
var _vehicle_frame := Kit.panel("FFrame")
var _vehicle_summary := VBoxContainer.new()
var _row: HBoxContainer
## The panel joined right of the inventory in place of crafting (an opened item's window), and
## the window's title over the inventory half; null when none.
var side: Control = null
var side_title := ""


## The window is centred in the screen above the bottom HUD, as Factorio centres its windows
## (seen at 1920x1080: an entity window's middle is the middle of the room over the quickbar).
var _center := CenterContainer.new()


## How much of the screen's bottom the HUD takes (factorio_ui.gd's layout sets it every frame); the
## window keeps out of it while there is room.
func set_bottom_room(px: float) -> void:
	if _row == null:
		return
	var room := clampf(px, 0.0, maxf(0.0, size.y - _row.get_combined_minimum_size().y))
	if not is_equal_approx(_center.offset_bottom, -room):
		_center.offset_bottom = -room


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := _center
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	center.add_child(row)
	_row = row
	# Factorio 2.1's character screen is one frame of three parts, each with its own title:
	# Character (the inventory), Logistics (requests and trash) and Crafting. With an entity open it
	# is the inventory and the entity's screen. The armour and weapons are on the HUD's tool bar.
	row.add_child(_char_frame)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", Kit.px(4))
	_char_frame.add_child(left_box)
	var char_bar := Kit.title_bar("Character", false)
	_char_caption = char_bar.get_child(0)
	left_box.add_child(char_bar)
	# inside_shallow_frame round the inventory, with its tool row (sort) over the slots
	var shallow := Kit.panel("FShallowFrame")
	shallow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(shallow)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(12))
	pad.add_theme_constant_override("margin_top", Kit.px(8))
	pad.add_theme_constant_override("margin_bottom", Kit.px(12))
	shallow.add_child(pad)
	var inv_box := VBoxContainer.new()
	inv_box.add_theme_constant_override("separation", Kit.px(8))
	pad.add_child(inv_box)
	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_END
	inv_box.add_child(tools)
	_inv_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_heading.visible = false
	tools.add_child(_inv_heading)
	# Factorio 2.1's inventory has no sort button (it sorts by itself); the client keeps one for the
	# mod's sort, hidden. Its two buttons: the colour picker and the player's colour.
	var sort := Button.new()
	sort.visible = false
	sort.pressed.connect(func() -> void: model.sort_inventory("main"))
	tools.add_child(sort)
	_sort_button = sort
	tools.add_theme_constant_override("separation", Kit.px(4))
	var picker_button := Button.new()
	picker_button.name = "ColorPipette"
	picker_button.theme_type_variation = "FPageButton"
	picker_button.custom_minimum_size = Kit.pxv(28, 28)
	picker_button.focus_mode = Control.FOCUS_NONE
	picker_button.tooltip_text = "Color"
	picker_button.icon = GuiAssets.core_region("icons/mip/color-picker.png", Rect2i(0, 0, 32, 32))
	picker_button.expand_icon = true
	picker_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	picker_button.add_theme_constant_override("icon_max_width", Kit.px(16))
	tools.add_child(picker_button)
	# The swatch shows the character's colour (`ccol`); both buttons open the colour picker, whose
	# choice goes to the bridge (set_char_color) when it closes.
	var swatch := ColorPickerButton.new()
	swatch.name = "ColorSwatch"
	swatch.edit_alpha = false
	swatch.color = model.char_color if model != null else PLAYER_COLOR
	swatch.theme_type_variation = "FSlot"
	swatch.custom_minimum_size = Kit.pxv(28, 28)
	swatch.focus_mode = Control.FOCUS_NONE
	swatch.tooltip_text = "Color"
	swatch.popup_closed.connect(func() -> void:
		if swatch.color != model.char_color:
			model.set_character_color(swatch.color)
		color_requested.emit())
	picker_button.pressed.connect(func() -> void: swatch.get_popup().popup_centered())
	_color_swatch = swatch
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = swatch.color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		fill.set_offset(side, Kit.px(2))
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		fill.set_offset(side, -Kit.px(2))
	swatch.add_child(fill)
	swatch.color_changed.connect(func(c: Color) -> void: fill.color = c)
	tools.add_child(swatch)
	var deep: Array = Kit.deep_scroll(Kit.pxv(Kit.SLOT * Kit.COLUMNS, Kit.SLOT * ROWS))
	inv_box.add_child(deep[0])
	_inv_scroll = deep[1]
	deep[1].add_child(_grid)
	_stripes = Stripes.new()
	_stripes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_box.add_child(_stripes)
	var equipment := _equipment_row()
	equipment.visible = false  # Factorio 2.1 has them on the tool bar (weapon_hud.gd) only
	inv_box.add_child(equipment)

	row.add_child(_logistics_frame)
	var mid_box := VBoxContainer.new()
	mid_box.add_theme_constant_override("separation", Kit.px(4))
	_logistics_frame.add_child(mid_box)
	mid_box.add_child(Kit.title_bar("Logistics", false))
	var mid_shallow := Kit.panel("FShallowFrame")
	mid_shallow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_box.add_child(mid_shallow)
	var mid_pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		mid_pad.add_theme_constant_override("margin_" + side, Kit.px(12))
	mid_shallow.add_child(mid_pad)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", Kit.px(8))
	mid_pad.add_child(mid)
	_logistics.theme = EntityPanels.theme()
	_logistics.add_theme_constant_override("separation", Kit.px(8))
	_logistics.custom_minimum_size = Kit.pxv(Kit.SLOT * Kit.COLUMNS, Kit.SLOT * 4)
	mid.add_child(_logistics)
	_trash_box.add_theme_constant_override("separation", Kit.px(2))
	_trash_box.add_child(Kit.label("Trash slots", "FHeading"))
	var trash_frame := Kit.panel("FDeepFrame")
	trash_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	trash_frame.add_child(_trash_grid)
	_trash_box.add_child(trash_frame)
	_trash_box.visible = false
	mid.add_child(_trash_box)
	# Space Age: the planet the character is on and its surface properties.
	var planet := PlanetInfo.new()
	planet.model = model
	mid.add_child(planet)

	row.add_child(_crafting_frame)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", Kit.px(4))
	_crafting_frame.add_child(right_box)
	var bar := Kit.title_bar("Crafting", true)
	_crafting_caption = bar.get_child(0)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: close_requested.emit())
	# Factorio's title buttons: search, then close. The character's details (not part of
	# Factorio's screen) are behind the button before them.
	var info_button := Kit.close_button()
	info_button.tooltip_text = "Character details"
	var portrait := GuiAssets.core_sprite("icons/entity/character.png")
	if portrait != null:
		info_button.icon = portrait
	info_button.toggle_mode = true
	info_button.toggled.connect(func(on: bool) -> void: show_tab("Character" if on else "Crafting"))
	bar.add_child(info_button)
	bar.move_child(info_button, bar.get_child_count() - 2)
	_tab_buttons["Character"] = info_button
	var search := Kit.close_button()
	search.tooltip_text = "Search (Ctrl+F)"
	var glass := GuiAssets.core_sprite("icons/search.png")
	if glass != null:
		search.icon = glass
	search.pressed.connect(focus_search)
	bar.add_child(search)
	bar.move_child(search, bar.get_child_count() - 2)
	right_box.add_child(bar)
	_crafting = CraftingPanel.new()
	_crafting.model = model
	_crafting.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_child(_crafting)
	# Factorio's recipe search field opens in the title bar, left of the search button.
	var field := _crafting.search
	field.get_parent().remove_child(field)
	field.custom_minimum_size.x = Kit.px(100)
	field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(field)
	bar.move_child(field, search.get_index())
	_info.add_theme_constant_override("separation", Kit.px(2))
	_info.custom_minimum_size = Kit.pxv(Kit.SLOT * Kit.COLUMNS, Kit.SLOT * 6)
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_info.visible = false
	right_box.add_child(_info)

	screen.size_flags_vertical = Control.SIZE_FILL
	row.add_child(screen)
	screen.opened_changed.connect(func(_open: bool) -> void: _update_visibility())
	row.add_child(_vehicle_panel())
	_armor_panel()
	model.equipment_changed.connect(func(_kind: String) -> void: _refresh_equipment())
	model.character_info_changed.connect(_refresh_info)

	model.inventory_changed.connect(_refresh)
	model.guns_changed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if _stale and is_visible_in_tree():
			_refresh())
	if model.has_signal("logistics_changed"):
		model.connect("logistics_changed", _refresh_logistics)
	_refresh()
	_refresh_equipment()
	_update_visibility()


## Factorio's armour window's right half: "Equipment grid" over the whole grid (no scrolling, as
## the game shows 10x10) and its summary. It joins the inventory through show_side.
func _armor_panel() -> void:
	_armor_frame.theme_type_variation = "FFrameRight"
	_armor_frame.name = "ArmorPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	_armor_frame.add_child(box)
	var bar := Kit.title_bar("", true)
	_armor_title = bar.get_child(0) as Label
	_armor_title.visible = false
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: open_armor(false))
	box.add_child(bar)
	var shallow := Kit.panel("FShallowFrame")
	shallow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(shallow)
	var pad := MarginContainer.new()
	for side_name in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side_name, Kit.px(12))
	pad.add_theme_constant_override("margin_top", Kit.px(8))
	pad.add_theme_constant_override("margin_bottom", Kit.px(12))
	shallow.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", Kit.px(8))
	pad.add_child(inner)
	inner.add_child(Kit.label("Equipment grid"))
	armor_grid = EquipmentGrid.new()
	armor_grid.model = model
	armor_grid.kind = "char"
	armor_grid.cell_clicked.connect(func(k: String, c: Vector2i, b: int, sh: bool) -> void: grid_clicked.emit(k, c, b, sh))
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	frame.add_child(armor_grid)
	inner.add_child(frame)
	_armor_summary.add_theme_constant_override("separation", 0)
	inner.add_child(_armor_summary)
	_armor_switches.visible = false  # Factorio has them on the shortcut bar (Alt+F, Alt+E) only
	inner.add_child(_armor_switches)
	_armor_frame.visible = false
	_armor_frame.size_flags_vertical = Control.SIZE_FILL


func _vehicle_panel() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	_vehicle_frame.add_child(box)
	box.add_child(Kit.title_bar("Equipment grid", false))
	vehicle_grid = EquipmentGrid.new()
	vehicle_grid.model = model
	vehicle_grid.kind = "veh"
	vehicle_grid.cell_clicked.connect(func(k: String, c: Vector2i, b: int, sh: bool) -> void: grid_clicked.emit(k, c, b, sh))
	box.add_child(_grid_scroll(vehicle_grid))
	_vehicle_summary.add_theme_constant_override("separation", 0)
	box.add_child(_vehicle_summary)
	_vehicle_frame.visible = false
	_vehicle_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", Kit.px(8))
	margin.add_child(_vehicle_frame)
	return margin


## A grid in Factorio's deep frame, scrolling when taller than the inventory.
func _grid_scroll(grid: EquipmentGrid) -> Control:
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.add_child(grid)
	frame.add_child(scroll)
	var fit := func() -> void:
		var s := grid.custom_minimum_size
		var tall := float(Kit.px(Kit.SLOT * ROWS))
		var bar := Kit.px(12) if s.y > tall else 0
		scroll.custom_minimum_size = Vector2(s.x + bar, minf(s.y, tall))
	grid.minimum_size_changed.connect(fit)
	return frame


## The armour panel's and the vehicle panel's contents from ui_model.grids.
func _refresh_equipment() -> void:
	var g := model.grid("char")
	var has := int(g.get("w", 0)) > 0
	var want := armor_open and has
	if want and side != _armor_frame:
		show_side(_armor_frame, "Armor")
	elif not want and side == _armor_frame:
		side = null
		_armor_frame.visible = false
		_update_visibility()
	if has:
		var armor := model.stack_at("armor", 1)
		set_side_title(_armor_frame, Kit.pretty(str(armor["item"])) if not armor.is_empty() else "Armor")
		_fill_armor_summary(g)
		_fill_switches(g)
	_refresh_vehicle()


func _refresh_vehicle() -> void:
	var v := model.grid("veh")
	# As Factorio's: shown once the grid button beside the vehicle's ammo slots is pressed.
	_vehicle_frame.visible = int(v.get("w", 0)) > 0 and screen.is_open() and int(v.get("unit", 0)) == screen.unit 		and LogicWindows.vehicle_grid_open
	if _vehicle_frame.visible:
		_fill_summary(_vehicle_summary, v)


## Vanilla's personal roboports (equipment.lua): robot limit, charging spots, construction radius.
const ROBOPORTS := {"personal-roboport-equipment": [10, 2, 15], "personal-roboport-mk2-equipment": [25, 4, 20]}


## The armour window's summary, worded as Factorio's: bold labels with their values beside them.
func _fill_armor_summary(g: Dictionary) -> void:
	var names: Array = g.get("equipment", []).map(func(e: Dictionary) -> String: return str(e["name"]))
	var sig := "%d/%d/%d/%d/%s" % [int(g.get("w", 0)), int(g.get("h", 0)), int(g.get("max_shield", 0)), int(g.get("max_battery", 0)), str(names)]
	if str(_armor_summary.get_meta("sig", "")) == sig:
		return
	_armor_summary.set_meta("sig", sig)
	for c in _armor_summary.get_children():
		_armor_summary.remove_child(c)
		c.queue_free()
	var line := func(label: String, value: String, bullet: bool) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(6))
		row.add_child(Kit.label(("• " if bullet else "") + label + (":" if value != "" else ""), "FHeading"))
		if value != "":
			row.add_child(Kit.label(value))
		_armor_summary.add_child(row)
	line.call("Equipment grid size", "%d×%d" % [int(g["w"]), int(g["h"])], false)
	if float(g.get("max_battery", 0)) > 0:
		# Factorio writes "100 MJ" here, with a space.
		var e := EquipmentGrid.energy_text(float(g["max_battery"]))
		line.call("Battery capacity", RegEx.create_from_string("([0-9.])([A-Za-z])").sub(e, "$1 $2"), false)
	if int(g.get("max_shield", 0)) > 0:
		line.call("Shield capacity", str(int(g["max_shield"])), false)
	var robots := 0
	var spots := 0
	var radius := 0
	for e in g.get("equipment", []):
		var r: Array = ROBOPORTS.get(str(e["name"]), [])
		if not r.is_empty() and not bool(e.get("ghost", false)):
			robots += int(r[0])
			spots += int(r[1])
			radius = maxi(radius, int(r[2]))
	if robots > 0:
		line.call("Roboport", "", false)
		line.call("Max. robots", str(robots), true)
		line.call("Charging spots", str(spots), true)
		line.call("Construction area", "%d×%d" % [radius * 2, radius * 2], true)


func _fill_summary(box: VBoxContainer, g: Dictionary) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var lines: Array = []
	if int(g.get("max_shield", 0)) > 0:
		lines.append(["Shield", "%d / %d" % [int(g["shield"]), int(g["max_shield"])]])
	if float(g.get("max_battery", 0)) > 0:
		lines.append(["Energy", "%s / %s" % [EquipmentGrid.energy_text(float(g["battery"])), EquipmentGrid.energy_text(float(g["max_battery"]))]])
	if float(g.get("power", 0)) > 0:
		lines.append(["Power", EquipmentGrid.power_text(float(g["power"]))])
	if float(g.get("movement", 0)) > 0 or not bool(g.get("movement_on", true)):
		lines.append(["Movement bonus", "+%d%%" % roundi(float(g["movement"]) * 100) if bool(g.get("movement_on", true)) else "off"])
	if int(g.get("inventory", 0)) > 0:
		lines.append(["Inventory bonus", "+%d" % int(g["inventory"])])
	for l in lines:
		var row := HBoxContainer.new()
		var name := Kit.label(str(l[0]) + ":", "FHeading")
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		row.add_child(Kit.label(str(l[1])))
		box.add_child(row)


## Factorio's Alt+F and Alt+E switches (on its shortcut bar) as checkboxes under the armour.
func _fill_switches(g: Dictionary) -> void:
	var sig := "%d/%s/%s/%s" % [int(g.get("roboport_on", -1)), str(g.get("movement_on", true)), str(_has_part(g, "roboport")),
		str(_has_part(g, "exoskeleton"))]
	if str(_armor_switches.get_meta("sig", "")) == sig:
		return
	_armor_switches.set_meta("sig", sig)
	for c in _armor_switches.get_children():
		_armor_switches.remove_child(c)
		c.queue_free()
	if _has_part(g, "roboport"):
		var roboport_on := int(g.get("roboport_on", 1)) != 0
		var set_roboport := func(v: bool) -> void: model.toggle_equipment("roboport", v)
		_armor_switches.add_child(EntityPanels.checkbox("Personal roboport", roboport_on, set_roboport))
	if _has_part(g, "exoskeleton"):
		var set_movement := func(v: bool) -> void: model.toggle_equipment("movement", v)
		_armor_switches.add_child(EntityPanels.checkbox("Exoskeleton", bool(g.get("movement_on", true)), set_movement))


static func _has_part(g: Dictionary, part: String) -> bool:
	for e in g.get("equipment", []):
		if str(e["name"]).contains(part):
			return true
	return false


## The Character tab: Factorio's character info, from `cinfo`.
func _refresh_info() -> void:
	if not _info.visible:
		return
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	var i := model.character_info
	if i.is_empty():
		var none := Kit.label("Waiting for the character's details from the bridge")
		none.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_info.add_child(none)
		return
	var g := model.grid("char")
	var hp := "%d" % int(i.get("hp", 0))
	if int(i.get("hpb", 0)) > 0:
		hp += "  (+%d)" % int(i["hpb"])
	var walking := _percent(i, "run")
	if int(i.get("eqmv", 0)) > 0:
		walking += "  (+%d%% equipment)" % roundi(int(i["eqmv"]) / 10.0)
	var slots := "%d" % int(i.get("slots", 0))
	var extra: Array = []
	if int(i.get("invb", 0)) > 0:
		extra.append("+%d bonus" % int(i["invb"]))
	if int(i.get("eqinv", 0)) > 0:
		extra.append("+%d armor" % int(i["eqinv"]))
	if not extra.is_empty():
		slots += "  (%s)" % ", ".join(extra)
	var rows: Array = [["Health", hp]]
	if int(g.get("max_shield", 0)) > 0:
		rows.append(["Shield", "%d / %d" % [int(g["shield"]), int(g["max_shield"])]])
	rows.append_array([
		["Crafting speed", _percent(i, "craft")],
		["Mining speed", _percent(i, "mine")],
		["Walking speed", walking],
		["Running speed now", "%.1f km/h" % (int(i.get("speed", 0)) / 1000.0 * 60.0 * 3.6)],
		["Inventory slots", slots],
		["Logistic trash slots", "%d" % int(i.get("trash", 0))],
		["Reach distance", _tiles(i, "reach")],
		["Build distance", _tiles(i, "build")],
		["Resource reach distance", _tiles(i, "rreach")],
		["Item pickup distance", _tiles(i, "pick")],
		["Loot pickup distance", _tiles(i, "loot")],
		["Item drop distance", _tiles(i, "drop")],
		["Follower robot count", "+%d" % int(i.get("robots", 0))],
	])
	_info.add_child(Kit.label("Bonuses", "FHeading"))
	for r in rows:
		var row := HBoxContainer.new()
		var name := Kit.label(str(r[0]))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var value := Kit.label(str(r[1]))
		value.add_theme_font_override("font", Kit.font("semibold"))
		row.add_child(value)
		_info.add_child(row)


## A multiplier in thousandths as Factorio's bonus: "150%  (+50%)".
static func _percent(i: Dictionary, key: String) -> String:
	var v := int(i.get(key, 1000))
	var text := "%d%%" % roundi(v / 10.0)
	if v > 1000:
		text += "  (+%d%%)" % roundi((v - 1000) / 10.0)
	return text


## Tenths of a tile: "2.7", "10".
static func _tiles(i: Dictionary, key: String) -> String:
	return ("%.1f" % (int(i.get(key, 0)) / 10.0)).trim_suffix(".0")


## Armour, weapons and ammo under the inventory, each in its own deep frame with Factorio's
## empty-slot pictures.
func _equipment_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(12))
	for role in ["armor", "guns", "ammo"]:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", Kit.px(2))
		box.add_child(Kit.label({"armor": "Armor", "guns": "Weapons", "ammo": "Ammo"}[role], "FHeading"))
		var frame := Kit.panel("FDeepFrame")
		frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var grid := Kit.slot_grid(int(EQUIPMENT[role]))
		frame.add_child(grid)
		var list: Array = []
		for i in int(EQUIPMENT[role]):
			var s := _new_slot(role, i + 1)
			s.empty_icon = GuiAssets.core_sprite("icons/mip/%s.png" % EMPTY_ICONS[role])
			grid.add_child(s)
			list.append(s)
		_equipment[role] = list
		box.add_child(frame)
		row.add_child(box)
	return row


## "Crafting" or "Logistics" on the right.
func show_tab(tab: String) -> void:
	for t in _tab_buttons:
		(_tab_buttons[t] as Button).set_pressed_no_signal(t == tab)
	# Logistics has its own frame; "Character" swaps the crafting frame for the character's details.
	_crafting.visible = tab != "Character"
	_info.visible = tab == "Character"
	if _crafting_caption != null:
		_crafting_caption.text = "Character" if tab == "Character" else "Crafting"
	_refresh_info()
	if _logistics.visible:
		_logistics_sig = "-"
		_refresh_logistics()


## Ctrl+F: the crafting tab's search.
func focus_search() -> void:
	if screen.focus_search():  # the recipe chooser's own search
		return
	show_tab("Crafting")
	_crafting.focus_search()


## The character's logistic requests (`clog`) and its network (`ln`), when the mod sends them.
func _refresh_logistics() -> void:
	if _color_swatch != null and _color_swatch.color != model.char_color and not _color_swatch.get_popup().visible:
		_color_swatch.color = model.char_color
		(_color_swatch.get_node("Fill") as ColorRect).color = model.char_color
	if not _logistics.is_visible_in_tree():
		return
	var requests = model.get("char_requests")
	var sig := JSON.stringify([requests, model.get("char_requests_on"), model.get("char_trash_unrequested"), model.get("network"),
		model.get("char_sections"), model.get("logistic_groups")])
	if sig == _logistics_sig:
		return
	_logistics_sig = sig
	for c in _logistics.get_children():
		_logistics.remove_child(c)
		c.queue_free()
	if requests == null:
		var note := Kit.label("Personal logistics need the bridge's logistics data (the claude/cloud-logistics branch).")
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = Kit.px(Kit.SLOT * Kit.COLUMNS)
		note.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_logistics.add_child(note)
		return
	var on := bool(model.get("char_requests_on"))
	var trash := bool(model.get("char_trash_unrequested"))
	var list: Array = []
	for r in requests:
		if r is Dictionary:
			list.append([str(r.get("item", "")), int(r.get("min", 0)), int(r.get("max", -1))])
	var send := func(l: Array, new_on: bool, new_trash: bool) -> void:
		var dicts: Array = []
		for x in l:
			dicts.append({"item": x[0], "min": x[1], "max": x[2]})
		model.call("set_character_requests", dicts, new_on, new_trash)
	var set_on := func(v: bool) -> void: send.call(list, v, trash)
	var set_trash := func(v: bool) -> void: send.call(list, on, v)
	var set_list := func(l: Array) -> void: send.call(l, on, trash)
	var net = model.get("network")
	var in_network: bool = net is Dictionary and not (net as Dictionary).is_empty()
	# Factorio: both switches on one row, the status dot at its right end (green: requests can be
	# served here; red: off or no network).
	var top := EntityPanels.row(12)
	top.add_child(EntityPanels.checkbox("Personal logistics", on, set_on))
	top.add_child(EntityPanels.checkbox("Trash unrequested", trash, set_trash))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(space)
	var dot := TextureRect.new()
	dot.texture = GuiAssets.status_dot("green" if on and in_network else "red")
	dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dot.custom_minimum_size = Kit.pxv(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.tooltip_text = "In logistic network %d" % int(net.get("id", 0)) if in_network else "Not in a logistic network"
	dot.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(dot)
	_logistics.add_child(top)
	if model.get("char_sections") is Array:
		# Factorio's logistic sections, each with its group, on/off box, rename and delete, its
		# requests 10 wide, then "Add section" (production_panels.gd, as the hub's and chests').
		var holder := CharacterSections.new()
		holder.picker = screen.picker
		holder.held_item = screen.held_item if screen.get("held_item") is Callable else Callable()
		holder._last = {"lgs": model.get("logistic_groups"), "ql": []}
		_logistics.add_child(holder)
		var slots := func(sec: Dictionary, filters: Array, send: Callable) -> Control:
			var plain: Array = []
			var quality := {}
			for f in filters:
				if f is Array and f.size() >= 6:
					plain.append([str(f[0]), int(f[2]), int(f[3])])
					quality[str(f[0])] = str(f[1])
			var back := func(l: Array) -> void:
				var out: Array = []
				for r in l:
					out.append([str(r[0]), quality.get(str(r[0]), "normal"), int(r[1]), int(r[2]), "", -1])
				send.call(out)
			return EntityPanels.request_grid(holder, plain, back, Kit.COLUMNS)
		var secs := ProductionPanels.sections(holder, (model.get("char_sections") as Array).duplicate(true), slots)
		secs.name = "Sections"
		holder.add_child(secs)
		return
	# Without `clog.sec` (an older mod): the requests as one "Main" section.
	var section := Kit.panel("FDeepFrame")
	var section_box := EntityPanels.column(0)
	section.add_child(section_box)
	var head := Kit.panel("FSubheader")
	var head_row := EntityPanels.row(8)
	head.add_child(head_row)
	head_row.add_child(EntityPanels.checkbox("", on, set_on))
	head_row.add_child(Kit.label("Main", "FHeading"))
	var head_space := Kit.panel("FDraggable")
	head_space.custom_minimum_size.y = Kit.px(20)
	head_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_space.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(head_space)
	section_box.add_child(head)
	var screen_like := {"held_item": Callable(), "picker": screen.picker}
	section_box.add_child(EntityPanels.request_grid(screen_like, list, set_list, Kit.COLUMNS))
	_logistics.add_child(section)


## The character's sections need what production_panels.gd asks of a machine screen: `unit` (0:
## the character, as set_section reads it), `_last` (the force's logistic groups), the held item and
## the item chooser.
class CharacterSections extends VBoxContainer:
	var unit := 0
	var _last := {}
	var held_item := Callable()
	var picker = null


## Shows or hides the armour's grid beside the inventory.
func open_armor(open: bool) -> void:
	armor_open = open
	_refresh_equipment()


func open_crafting(open: bool) -> void:
	crafting_open = open
	if not open and side != null:
		_drop_side()
	_update_visibility()


func is_open() -> bool:
	return visible


func _update_visibility() -> void:
	var machine := screen.is_open()
	if machine and side != null:
		_drop_side()
	var joined := machine or side != null
	_crafting_frame.visible = crafting_open and not joined
	# With an entity (or an opened item) the two frames join into Factorio's one window, titled
	# with its name.
	_char_frame.theme_type_variation = "FFrameLeft"  # crafting or the machine always joins on the right
	_char_caption.text = screen.title_text() if machine else (side_title if side != null else "Character")
	_inv_heading.visible = joined
	var alone := machine and not screen.shows_inventory()
	_char_frame.visible = not alone
	screen.set_alone(alone)
	var was := _logistics_frame.visible
	_logistics_frame.visible = crafting_open and not joined
	if _logistics_frame.visible and not was:
		_logistics_sig = "-"
		_refresh_logistics.call_deferred()
	visible = crafting_open or joined
	if not visible:
		hovered_item = ""
	_refresh_vehicle()


## Joins a panel right of the inventory as one window titled `title` (an opened item: the armour,
## a book, a planner, the library), in place of crafting. Whatever was joined there closes.
func show_side(panel: Control, title: String) -> void:
	if side != null and side != panel:
		_drop_side()
	if screen.is_open():
		screen.close()
	if panel != _armor_frame:
		armor_open = false
	side = panel
	side_title = title
	if panel.get_parent() != _row:
		if panel.get_parent() != null:
			panel.get_parent().remove_child(panel)
		_row.add_child(panel)
	_row.move_child(panel, _char_frame.get_index() + 1)
	panel.visible = true
	_update_visibility()


func set_side_title(panel: Control, title: String) -> void:
	if side == panel and side_title != title:
		side_title = title
		_update_visibility()


## Takes a panel out of the window (it closed).
func hide_side(panel: Control) -> void:
	if side == panel:
		side = null
		panel.visible = false
		if panel == _armor_frame:
			armor_open = false
		_update_visibility()


## Another window takes the right half: the joined panel closes itself.
func _drop_side() -> void:
	var s := side
	side = null
	if s == _armor_frame:
		armor_open = false
	if s.has_method("close"):
		s.call("close")
	s.visible = false


func set_hand_slot(slot: Array) -> void:
	if slot != hand_slot:
		hand_slot = slot.duplicate()
		_refresh()


## Updates the slots in place (the grid keeps its nodes, so a held tooltip or drag survives).
## Closed, the window only notes that its slots are out of date and draws them when it opens: every
## inventory change (ammo used, a robot's delivery) redrew all of them, ~12 ms a time while running
## on the owner's save.
var _stale := false


func _refresh() -> void:
	if not is_visible_in_tree():
		_stale = true
		return
	_stale = false
	var slots := model.main_slots
	while _grid.get_child_count() < slots.size():
		_grid.add_child(_new_slot("main", _grid.get_child_count() + 1))
	while _grid.get_child_count() > slots.size():
		var last := _grid.get_child(_grid.get_child_count() - 1)
		_grid.remove_child(last)
		last.queue_free()
	for i in slots.size():
		_show(_grid.get_child(i), "main", i + 1, slots[i])
	# the deep frame holds the slot rows (scrolling past MAX_ROWS); striped rows fill the rest
	var rows := clampi(ceili(slots.size() / float(Kit.COLUMNS)), 1, MAX_ROWS)
	_inv_scroll.custom_minimum_size.y = Kit.px(Kit.SLOT * rows)
	var trash := model.slots_of("trash")
	_trash_box.visible = not trash.is_empty()
	while _trash_grid.get_child_count() < trash.size():
		var s := _new_slot("trash", _trash_grid.get_child_count() + 1)
		s.empty_icon = GuiAssets.core_sprite("icons/mip/empty-trash-slot.png")
		_trash_grid.add_child(s)
	while _trash_grid.get_child_count() > trash.size():
		var last := _trash_grid.get_child(_trash_grid.get_child_count() - 1)
		_trash_grid.remove_child(last)
		last.queue_free()
	for i in trash.size():
		_show(_trash_grid.get_child(i), "trash", i + 1, trash[i])
	for role in _equipment:
		var list: Array = _equipment[role]
		var stacks := model.slots_of(role)
		for i in list.size():
			_show(list[i], role, i + 1, stacks[i] if i < stacks.size() else {})
			(list[i] as Slot).set_pressed_no_signal(role == "guns" and i + 1 == model.selected_gun and not stacks.is_empty())


func _show(s: Slot, role: String, index: int, stack: Dictionary) -> void:
	var in_hand: bool = hand_slot.size() >= 2 and hand_slot[0] == role and int(hand_slot[1]) == index and not stack.is_empty()
	s.set_hand(in_hand, Slot.hand_left_of(hand_slot, stack))
	var filter: String = model.main_filters.get(index, "") if role == "main" else ""
	if filter != s.filter_item:
		s.filter_item = filter
		s.queue_redraw()
	s.set_extra(stack)
	if stack.is_empty():
		s.set_stack("", -1)
		s.drag_item = ""
		s.set_tip("")
		s.tooltip_text = ""
		return
	var item: String = stack["item"]
	var n := int(stack["count"])
	s.set_stack(item, n if role != "guns" and role != "armor" else -1)
	s.drag_item = item if role == "main" else ""
	var lines: Array = []
	if role == "main":
		lines.append(["%d in this slot, %d in the inventory" % [n, model.count_of(item)]])
		lines.append(["Click: pick up · Right click: pick up half", "", Kit.DISABLED_TEXT])
		lines.append(["1-0 or drag to the quickbar: pin it", "", Kit.DISABLED_TEXT])
	elif role == "guns":
		lines.append(["Selected weapon" if index == model.selected_gun else "Click a weapon in the bottom bar or press Tab to use it", "", Kit.DISABLED_TEXT])
	else:
		lines.append(["%d" % n])
	s.set_tip(Kit.pretty(item), Slot.extra_lines(stack) + lines)


func _new_slot(role: String, index: int) -> Slot:
	var s := Slot.new()
	s.slot_role = role
	s.slot_index = index
	if role == "guns":
		s.toggle_mode = true
		s.theme_type_variation = "FSlot"
	var on_click := func(button_index: int, shift: bool) -> void:
		slot_clicked.emit(role, index, button_index, shift, s.ctrl)
		if s.toggle_mode:
			_refresh.call_deferred()  # only the model decides which gun is selected
	s.clicked.connect(on_click)
	var on_enter := func() -> void:
		hovered_item = s.item
	var on_exit := func() -> void:
		if hovered_item == s.item:
			hovered_item = ""
	s.mouse_entered.connect(on_enter)
	s.mouse_exited.connect(on_exit)
	return s


## Factorio's empty inventory rows under the slots: faint recessed bars, one per slot row.
class Stripes extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var row := float(Kit.px(Kit.SLOT))
		var inset := float(Kit.px(3))
		var y := 0.0
		while y + row <= size.y + 0.5:
			draw_rect(Rect2(inset, y + Kit.px(10), size.x - 2.0 * inset, Kit.px(3)), Color(0, 0, 0, 0.1))
			draw_rect(Rect2(inset, y + Kit.px(29), size.x - 2.0 * inset, Kit.px(1)), Color(1, 1, 1, 0.025))
			y += row
