extends Control
## Factorio 2.1's "Remote view" frame, around both the map (M, zoomed out) and the world seen from
## afar (zoomed in, or from an alert or a train): a title bar across the top with search, reset (back
## to the character), back / forward and close, a thin frame round the screen, the "Surfaces" panel
## at the top left (map_view.gd's, moved in here: Space map, Planets, Platforms, + Add space
## platform), and at the right, where the minimap sits, the map view settings. Factorio's "Add tag" /
## "Add ping" panel is left out on purpose: tags are added by right-clicking the map.
##
## Around the space map ("space", space_map.gd) it is the same frame. In the right column, under
## the map view settings as in Factorio, a platform's panel (platform_info.gd): shown while a
## platform is selected on the space map or the map shows a platform. In the world (zoomed in) the
## HUD's own panel shows it under the minimap (platform_panel.gd).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const PlatformInfo := preload("res://scripts/ui/factorio/platform_info.gd")

## The title bar's close: leave the remote view.
signal close_requested
## Reset: back to the character.
signal reset_requested

const BORDER := 4
const TITLE_HEIGHT := 40

var map_view: Control
## The rect the right column goes in (the minimap's), set by factorio_ui.gd.
var right_column := Rect2()
## The side menu's button grid (screen), which the map view settings' buttons line up under.
var buttons_rect := Rect2()
## "map", "world" or "space".
var mode := "map"
## The platform the panel at the right describes (a `plat` record), or {}.
var platform_info := {}
## The character is on that platform: its panel has the "Drop to a planet" row (factorio_ui.gd).
var platform_board := false
var info_panel := PlatformInfo.new()
## The logistic networks window is open: its frames take the Surfaces panel's place, and the title
## bar has only back / forward and close, as Factorio's.
var networks_open := false

var title_bar := PanelContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	title_bar.name = "RemoteTitle"
	title_bar.theme_type_variation = "FFrame"
	title_bar.anchor_right = 1.0
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(title_bar)
	var bar := Kit.title_bar("Remote view", true)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: close_requested.emit())
	for spec in [["Search", "icons/search.png", "Search the map", false], ["Reset", "icons/mip/reset-white.png", "Back to the character", true],
			["Back", "icons/mip/backward-arrow.png", "Back", false], ["Forward", "icons/mip/forward-arrow.png", "Forward", false]]:
		var b := Kit.close_button()
		b.name = spec[0]
		b.tooltip_text = spec[2]
		var icon := GuiAssets.core_sprite(spec[1])
		if icon != null:
			b.icon = icon
		b.disabled = not spec[3]
		if spec[0] == "Reset":
			b.pressed.connect(func() -> void: reset_requested.emit())
		bar.add_child(b)
		bar.move_child(b, bar.get_child_count() - 2)
	title_bar.add_child(bar)

	info_panel.visible = false
	add_child(info_panel)
	if map_view != null:
		# The Surfaces panel and the map view settings live in the frame, so they show in the world
		# view too (the settings only on the map).
		map_view.surfaces_panel.reparent(self, false)
		map_view.panel.reparent(self, false)
		map_view.panel.set_anchors_preset(Control.PRESET_TOP_LEFT)


## Shows it around the map ("map"), the world ("world") or the space map ("space"), or hides it ("").
func show_for(what: String) -> void:
	visible = what != ""
	if what != "":
		mode = what
	if not visible and map_view != null:
		map_view.placing = {}


func _process(_delta: float) -> void:
	if not visible:
		return
	var view := size
	title_bar.size = Vector2(view.x, Kit.px(TITLE_HEIGHT))
	title_bar.position = Vector2.ZERO
	# The right column's top: under the minimap (the map view keeps it too, H22), or where its place
	# begins when it is hidden (a rect of no height).
	var w := maxf(right_column.size.x, Kit.px(240))
	var y := right_column.position.y
	if right_column.size.y > 0.0:
		y = right_column.end.y + Kit.px(4)
	var right := view.x - Kit.px(BORDER) if right_column.size.x <= 0.0 else right_column.end.x
	var top := Vector2(right - w, maxf(y, Kit.px(TITLE_HEIGHT) + Kit.px(8)))
	for b in ["Search", "Reset"]:
		var tb := title_bar.find_child(b, true, false) as Control
		if tb != null:
			tb.visible = not networks_open
	if map_view != null and map_view.surfaces_panel.get_parent() == self:
		map_view.surfaces_panel.visible = not networks_open and not map_view.model.map_surfaces.is_empty()
		map_view.surfaces_panel.position = Vector2(Kit.px(BORDER) + Kit.px(4), Kit.px(TITLE_HEIGHT) + Kit.px(4))
		var settings_panel: Control = map_view.panel
		settings_panel.visible = mode == "map"
		settings_panel.reset_size()
		# Its buttons lined up under the side menu's, as Factorio's are.
		var left := right - settings_panel.size.x
		var grid := settings_panel.find_child("*Grid*", true, false) as Control
		if buttons_rect.size.x > 0.0 and grid != null and grid.is_inside_tree():
			left = buttons_rect.position.x - (grid.global_position.x - settings_panel.global_position.x)
		settings_panel.position = Vector2(left, top.y)
	# The platform's panel in the right column, under the map view settings as Factorio has it.
	info_panel.visible = not platform_info.is_empty() and mode != "world"
	if info_panel.visible:
		info_panel.show_platform(platform_info, platform_board)
		info_panel.custom_minimum_size.x = w
		info_panel.reset_size()
		info_panel.position = top
		if map_view != null and map_view.panel.visible:
			info_panel.position.y = map_view.panel.position.y + map_view.panel.size.y + Kit.px(4)
	queue_redraw()


## Factorio's thin frame round the screen under the title bar.
func _draw() -> void:
	var b := float(Kit.px(BORDER))
	var c := Color8(49, 48, 49)
	var top := float(Kit.px(TITLE_HEIGHT))
	draw_rect(Rect2(0, top, b, size.y - top), c)
	draw_rect(Rect2(size.x - b, top, b, size.y - top), c)
	draw_rect(Rect2(0, size.y - b, size.x, b), c)
