extends PanelContainer
## Factorio 2.1's top-right corner: one slot_window_frame (8 + 240 + 8 wide) flush with the
## window's corner holding the research in progress (research_progress.gd), the side menu's
## buttons (side_menu_frame: 6 + 4 side_menu_buttons of 40x40 on deep slot recesses) and, below
## them, the place for the minimap (minimap.gd draws itself; factorio_ui.gd puts it on
## `minimap_slot`). The buttons, in Factorio's order: blueprint library, production statistics,
## bonuses, Factoriopedia, trains, achievements; tips and tricks, logistic networks, alerts
## settings, master mute. `pressed(name)` goes to factorio_ui.gd.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Controls := preload("res://scripts/player/controls.gd")
const TipButton := preload("res://scripts/ui/factorio/tip_button.gd")

signal pressed(name: String)

const WIDTH := 240  # right_menu_width
const COLUMNS := 6
## [name, side-menu-buttons.png row, tooltip, action whose key is shown]
const BUTTONS := [
	["blueprint_library", 0, "Blueprint library", "blueprint_library"],
	["production", 1, "Production statistics", "production_statistics"],
	["bonuses", 2, "Bonuses", ""],
	["factoriopedia", 10, "Factoriopedia", "toggle_factoriopedia"],
	["trains", 4, "Trains", ""],
	["achievements", 5, "Achievements", ""],
	["tips", 3, "Tips and tricks", ""],
	["logistic_networks", 9, "Logistic networks", "logistic_networks"],
	["alerts", 13, "Alerts settings", ""],
	["mute", 15, "Mute all sounds", ""],
]
const MUTED_ICON := 14

var research: Control  # research_progress.gd, set by factorio_ui.gd before _ready
## Where the minimap goes: as wide as the menu, as tall as the minimap.
var minimap_slot := Control.new()
var _buttons := {}
var _column := VBoxContainer.new()


func _ready() -> void:
	theme_type_variation = "FSlotWindow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_theme_constant_override("separation", Kit.px(8))
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	if research != null:
		_column.add_child(research)
	var frame := Kit.panel("FDeepFrame")  # side_menu_frame: no padding, recesses behind the buttons
	frame.add_theme_stylebox_override("panel", Kit.style_with_margins("deep", 0, 0, 0, 0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(frame)
	var grid := Kit.slot_grid(COLUMNS)
	frame.add_child(grid)
	for b in BUTTONS:
		var button := TipButton.new()
		button.theme_type_variation = "FSideButton"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
		button.icon = GuiAssets.side_menu_icon(int(b[1]))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", Kit.px(32))
		# invert_colors_of_picture_when_hovered_or_toggled: the white icon turns black
		for c in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
			button.add_theme_color_override(c, Kit.BLACK)
		var keys := Controls.keys_text(str(b[3])) if str(b[3]) != "" else ""
		button.tooltip_text = str(b[2]) + (" (%s)" % keys if keys != "" else "")
		var name := str(b[0])
		button.pressed.connect(func() -> void: pressed.emit(name))
		grid.add_child(button)
		_buttons[name] = button
	for i in (COLUMNS - BUTTONS.size() % COLUMNS) % COLUMNS:
		grid.add_child(Kit.empty_cell())
	minimap_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap_slot.custom_minimum_size = Kit.pxv(WIDTH, WIDTH)
	_column.add_child(minimap_slot)


## The minimap's place: its side (0 hides the place, when the minimap is off).
func set_minimap_side(side: float) -> void:
	minimap_slot.visible = side > 0.0
	minimap_slot.custom_minimum_size = Vector2(maxf(Kit.px(WIDTH), side), side)


## The master mute button shows the muted speaker while sound is off.
func set_muted(on: bool) -> void:
	var b: Button = _buttons.get("mute")
	if b != null and b.has_meta("muted") != on:
		if on:
			b.set_meta("muted", true)
		else:
			b.remove_meta("muted")
		b.icon = GuiAssets.side_menu_icon(MUTED_ICON if on else 15)
		b.tooltip_text = "Unmute all sounds" if on else "Mute all sounds"


func button(name: String) -> Button:
	return _buttons.get(name)
