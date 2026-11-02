extends PanelContainer
## Factorio's tool bar in the bottom left corner: the character button (tool_bar_open_button, 52
## wide: opens the inventory) over the armour slot with the character's health as a vertical bar
## beside it, then the three gun slots over their ammo (tool_equip_ammo_slot), the gun in use and
## its ammo drawn green. Clicking a gun with nothing held uses it (Tab cycles); other clicks go to
## factorio_ui.gd like the inventory's slots (`slot_clicked`: put the held gun, ammo or armour in,
## take it out). From the mod's `guns` (or the `slots` of the guns and ammo inventories when it
## sends them).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const TipButton := preload("res://scripts/ui/factorio/tip_button.gd")
const Controls := preload("res://scripts/player/controls.gd")

## A slot was clicked: role "guns", "ammo" or "armor", 1-based index.
signal slot_clicked(role: String, index: int, button_index: int, shift: bool, ctrl: bool)
## The character button was clicked.
signal open_requested

const GUN_SLOTS := 3
const OPEN_WIDTH := 52  # tool_bar_open_button
const HEALTH_GREEN := Color(0.0, 0.8, 0.0)

var model: UiModel
## Whether a click on a gun slot should go to slot_clicked (something is held) rather than use it.
var holding := func() -> bool: return false
var _guns: Array[Slot] = []
var _ammo: Array[Slot] = []
var _armor: Slot
var _health := ProgressBar.new()


func _ready() -> void:
	theme_type_variation = "FSlotWindow"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var inner := Kit.panel("FQuickbarInner")  # tool_equip_inner_panel
	add_child(inner)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	inner.add_child(row)

	var first := VBoxContainer.new()
	first.add_theme_constant_override("separation", 0)
	row.add_child(first)
	var open := TipButton.new()
	open.theme_type_variation = "FPageButton"
	open.custom_minimum_size = Kit.pxv(OPEN_WIDTH, Kit.SLOT)
	open.focus_mode = Control.FOCUS_NONE
	open.tooltip_text = "Open character screen (%s)" % (Controls.keys_text("open_screen") if Controls.keys_text("open_screen") != "" else "E")
	var portrait := GuiAssets.core_sprite("icons/entity/character.png")
	if portrait != null:
		open.icon = portrait
		open.expand_icon = true
		open.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		open.add_theme_constant_override("icon_max_width", Kit.px(32))
	open.pressed.connect(func() -> void: open_requested.emit())
	first.add_child(open)
	var armour_row := HBoxContainer.new()
	armour_row.add_theme_constant_override("separation", 0)
	armour_row.custom_minimum_size = Kit.pxv(OPEN_WIDTH, Kit.SLOT)
	first.add_child(armour_row)
	var bar_box := MarginContainer.new()
	bar_box.custom_minimum_size.x = Kit.px(OPEN_WIDTH - Kit.SLOT)
	for side in ["left", "right"]:
		bar_box.add_theme_constant_override("margin_" + side, Kit.px(2))
	for side in ["top", "bottom"]:
		bar_box.add_theme_constant_override("margin_" + side, Kit.px(3))
	armour_row.add_child(bar_box)
	_health.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	_health.show_percentage = false
	_health.max_value = 1.0
	_health.step = 0.0
	_health.value = 1.0
	_health.add_theme_stylebox_override("fill", Kit.bar_style(HEALTH_GREEN))
	_health.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_health.mouse_filter = Control.MOUSE_FILTER_PASS
	bar_box.add_child(_health)
	_armor = Slot.new()
	_armor.theme_type_variation = "FSlot"
	_armor.empty_icon = GuiAssets.core_sprite("icons/mip/empty-armor-slot.png")
	var on_armour := func(button_index: int, shift: bool) -> void:
		slot_clicked.emit("armor", 1, button_index, shift, Input.is_key_pressed(KEY_CTRL))
	_armor.clicked.connect(on_armour)
	armour_row.add_child(_armor)

	var grid := Kit.slot_grid(GUN_SLOTS)
	row.add_child(grid)
	for i in GUN_SLOTS:
		var s := Slot.new()
		s.theme_type_variation = "FToolSlot"
		s.toggle_mode = true
		s.empty_icon = GuiAssets.core_sprite("icons/mip/empty-gun-slot.png")
		var pick := func(button_index: int, shift: bool) -> void:
			if button_index == MOUSE_BUTTON_LEFT and s.item != "" and not holding.call():
				model.select_gun(i + 1)
			else:
				slot_clicked.emit("guns", i + 1, button_index, shift, Input.is_key_pressed(KEY_CTRL))
			refresh.call_deferred()  # the mod's `guns` decides what is selected
		s.clicked.connect(pick)
		grid.add_child(s)
		_guns.append(s)
	for i in GUN_SLOTS:
		var s := Slot.new()
		s.theme_type_variation = "FToolSlot"
		s.toggle_mode = true
		s.empty_icon = GuiAssets.core_sprite("icons/mip/empty-ammo-slot.png")
		var put := func(button_index: int, shift: bool) -> void:
			slot_clicked.emit("ammo", i + 1, button_index, shift, Input.is_key_pressed(KEY_CTRL))
			refresh.call_deferred()
		s.clicked.connect(put)
		grid.add_child(s)
		_ammo.append(s)
	model.guns_changed.connect(refresh)
	model.inventory_changed.connect(refresh)
	refresh()


## The character's health, shown as the bar beside the armour slot.
func set_health(hp: float, max_hp: float) -> void:
	_health.value = clampf(hp / maxf(1.0, max_hp), 0.0, 1.0)
	_health.tooltip_text = "Health: %d / %d" % [roundi(hp), roundi(max_hp)]


func refresh() -> void:
	var guns := model.slots_of("guns")
	var ammo := model.slots_of("ammo")
	var armour := model.slots_of("armor")
	var a0: Dictionary = armour[0] if armour.size() > 0 else {}
	_armor.set_stack(str(a0.get("item", "")), -1)
	_armor.set_tip(Kit.pretty(str(a0["item"])) if not a0.is_empty() else "Armour slot",
		[] if not a0.is_empty() else [["Empty", "", Kit.DISABLED_TEXT]])
	for i in GUN_SLOTS:
		var g: Dictionary = guns[i] if i < guns.size() else {}
		var a: Dictionary = ammo[i] if i < ammo.size() else {}
		var selected := i + 1 == model.selected_gun and not g.is_empty()
		var gs := _guns[i]
		gs.set_stack(str(g.get("item", "")), int(g.get("count", 1)) if not g.is_empty() else -1)
		gs.set_pressed_no_signal(selected)
		if g.is_empty():
			gs.set_tip("Weapon slot %d" % (i + 1), [["Empty", "", Kit.DISABLED_TEXT]])
		else:
			var lines: Array = []
			lines.append(["In use" if selected else "Click or Tab: use it", "", Kit.GREEN_TEXT if selected else Kit.DISABLED_TEXT])
			lines.append([("Ammo: %s × %d" % [Kit.pretty(str(a["item"])), int(a["count"])]) if not a.is_empty() else "No ammo",
				str(a.get("item", "")), Kit.WHITE if not a.is_empty() else Kit.RED_TEXT])
			gs.set_tip(Kit.pretty(str(g["item"])), lines)
		var as_ := _ammo[i]
		as_.set_stack(str(a.get("item", "")), int(a.get("count", -1)) if not a.is_empty() else -1)
		as_.set_pressed_no_signal(selected)
		# The magazine in use: rounds left of its size (the mod's `guns`), as Factorio's bar and
		# the tooltip's first line ("Ammo: 4/10").
		var g_rec: Array = model.guns[i] if i < model.guns.size() and model.guns[i] is Array else []
		var rounds := int(g_rec[3]) if g_rec.size() >= 5 else -1
		var mag := int(g_rec[4]) if g_rec.size() >= 5 else 0
		var bar := float(rounds) / mag if not a.is_empty() and mag > 0 and rounds >= 0 else -1.0
		if not is_equal_approx(bar, as_.ammo_bar):
			as_.ammo_bar = bar
			as_.queue_redraw()
		var ammo_lines: Array = [["Empty", "", Kit.DISABLED_TEXT]]
		if not a.is_empty():
			ammo_lines = [["Ammo: %d/%d" % [rounds, mag]]] if mag > 0 and rounds >= 0 else [["%d magazines" % int(a["count"])]]
		as_.set_tip(Kit.pretty(str(a["item"])) if not a.is_empty() else "Ammo slot %d" % (i + 1), ammo_lines)
