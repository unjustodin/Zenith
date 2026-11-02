extends RefCounted
## A small Factorio-style UI kit: style boxes cut from Factorio's GUI atlas (gui_assets.gd) the
## way core/prototypes/style.lua lays them out, Factorio's fonts and colours, a Godot Theme with
## them, and helpers for the common pieces (window frames with a title bar, deep frames, slots,
## tooltips). Without a Factorio install the same names give flat boxes in Factorio's colours.
##
## Sizes are Factorio's "GUI pixels" (a slot is 40) times the UI scale, picked like Factorio's
## automatic scale from the window height (100% up to 1080 lines, then in steps of 25%), or
## --ui-scale=1.25. The atlas is drawn at half size at 100%, as Factorio does (default_sprite_scale).
##
## The numbers below (atlas positions, corner sizes, paddings, colours) are copied from style.lua.
## A layer is one of:
##   {"at": [x, y], "corner": c}               9-slice of a (2c+1) square (Factorio's position + corner_size)
##   {"at": [x, y], "size": s, "border": b}    an s x s image with a b-wide border (border + size)
##   {"parts": {"lt": [x, y, w, h], ...}}      explicit pieces: lt t rt l c r lb b rb; missing ones aren't drawn
## with optional "center": [x, y, w, h] (replaces the middle), "outer": true (the border is drawn
## outside the box, draw_type = "outer"), "shift": [l, t, r, b] (*_outer_border_shift),
## "tint": Color, "tile": true (the middle repeats sideways) or "tile_v" (repeats downwards).

const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const LayeredStyle := preload("res://scripts/ui/factorio/layered_style.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")

const SLOT := 40  # slot_size
## The pieces are baked at the size they are drawn, so nearest filtering keeps them sharp and stops
## stretched 1-pixel edges blending into their neighbours. Item icons (slot.gd) use linear.
const FILTER := CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
const ICON_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const COLUMNS := 10  # slot_table_column_count

## gui_color and friends from style.lua.
const CAPTION := Color(1.0, 230 / 255.0, 192 / 255.0)
const ORANGE := Color(0.98, 0.66, 0.22)
const WHITE := Color(1, 1, 1)
const BLACK := Color(0, 0, 0)
const RED_TEXT := Color(1.0, 136 / 255.0, 136 / 255.0)
const DISABLED_TEXT := Color(179 / 255.0, 179 / 255.0, 179 / 255.0)
const GLOW_COLOR := Color(225 / 255.0, 177 / 255.0, 106 / 255.0)
const BUTTON_BOLD_TEXT := Color8(28, 28, 28)  # button_default_bold_font_color
const GREEN_TEXT := Color(0.53, 0.85, 0.55)  # "working" and other good news in tooltips
const YELLOW_TEXT := Color(1.0, 0.83, 0.25)
const KEY_TEXT := Color(0.5, 0.8, 1.0)  # a control's keys in tooltips and hints ("Press T")
const SHADOW_COLOR := Color(0, 0, 0, 0.35)
const DIRT_COLOR := Color(15 / 255.0, 7 / 255.0, 3 / 255.0, 100 / 255.0)
const DIRT_FILLER_COLOR := Color(15 / 255.0, 7 / 255.0, 3 / 255.0, 56 / 255.0)
const GREEN_GLOW := Color(135 / 255.0, 216 / 255.0, 139 / 255.0, 0.5)
const RED_GLOW := Color(254 / 255.0, 90 / 255.0, 90 / 255.0, 0.5)
## Progress bar colours: the bar image is white and tinted.
const BAR_GREEN := Color(0, 1, 0)
const BAR_ORANGE := Color(0.98, 0.66, 0.22)

## Flat stand-ins when there is no atlas: [background, border, border width, corner radius],
## the colours sampled from the atlas.
const FLAT := {
	"frame": [Color8(45, 44, 45), Color8(25, 22, 21), 2, 2],
	"frame_left": [Color8(45, 44, 45), Color8(25, 22, 21), 2, 2],
	"frame_right": [Color8(45, 44, 45), Color8(25, 22, 21), 2, 2],
	"frame_middle": [Color8(45, 44, 45), Color8(25, 22, 21), 2, 0],
	"slot_window": [Color8(45, 44, 45), Color8(25, 22, 21), 2, 2],
	"deep": [Color8(31, 30, 31), Color8(15, 14, 15), 2, 0],
	"shallow": [Color8(62, 61, 62), Color8(25, 24, 25), 2, 0],
	"tab_pane": [Color8(62, 61, 62), Color8(25, 24, 25), 1, 0],
	"subheader": [Color8(31, 30, 31), Color8(15, 14, 15), 1, 0],
	"tooltip": [Color(25 / 255.0, 24 / 255.0, 25 / 255.0, 0.88), Color8(0, 0, 0), 1, 2],
	"tooltip_title": [Color(1.0, 231 / 255.0, 193 / 255.0, 0.88), Color8(0, 0, 0), 0, 2],
	"quickbar_inner": [Color8(31, 30, 31), Color8(15, 14, 15), 1, 0],
	"draggable": [Color8(55, 53, 52), Color8(30, 28, 27), 1, 0],
	"button": [Color8(143, 143, 143), Color8(40, 40, 40), 1, 3],
	"button_hover": [Color8(255, 175, 0), Color8(40, 40, 40), 1, 3],
	"button_pressed": [Color8(230, 140, 0), Color8(40, 40, 40), 1, 3],
	"button_disabled": [Color8(100, 100, 100), Color8(40, 40, 40), 1, 3],
	"green_button": [Color8(94, 182, 99), Color8(30, 60, 30), 1, 3],
	"green_button_hover": [Color8(135, 216, 139), Color8(30, 60, 30), 1, 3],
	"green_button_pressed": [Color8(70, 150, 75), Color8(30, 60, 30), 1, 3],
	"green_button_disabled": [Color8(80, 100, 80), Color8(30, 60, 30), 1, 3],
	"red_button": [Color8(254, 90, 90), Color8(70, 20, 20), 1, 3],
	"red_button_hover": [Color8(255, 140, 140), Color8(70, 20, 20), 1, 3],
	"red_button_pressed": [Color8(200, 60, 60), Color8(70, 20, 20), 1, 3],
	"red_button_disabled": [Color8(120, 70, 70), Color8(70, 20, 20), 1, 3],
	"frame_action": [Color8(45, 44, 45), Color8(20, 20, 20), 1, 2],
	"frame_action_hover": [Color8(255, 175, 0), Color8(20, 20, 20), 1, 2],
	"frame_action_pressed": [Color8(230, 140, 0), Color8(20, 20, 20), 1, 2],
	"slot": [Color8(45, 44, 45), Color8(25, 24, 25), 1, 0],
	"slot_hover": [Color8(255, 175, 0), Color8(25, 24, 25), 1, 0],
	"slot_pressed": [Color8(230, 140, 0), Color8(25, 24, 25), 1, 0],
	"slot_selected": [Color8(20, 120, 170), Color8(25, 24, 25), 1, 0],
	"slot_button": [Color8(45, 45, 45), Color8(20, 20, 20), 1, 3],
	"slot_button_hover": [Color8(255, 175, 0), Color8(20, 20, 20), 1, 3],
	"slot_button_pressed": [Color8(230, 140, 0), Color8(20, 20, 20), 1, 3],
	"red_slot_button": [Color8(150, 50, 50), Color8(40, 15, 15), 1, 3],
	"red_slot_button_hover": [Color8(200, 90, 90), Color8(40, 15, 15), 1, 3],
	"red_slot_button_pressed": [Color8(170, 70, 70), Color8(40, 15, 15), 1, 3],
	"tab": [Color8(143, 143, 143), Color8(40, 40, 40), 1, 3],
	"tab_hover": [Color8(255, 175, 0), Color8(40, 40, 40), 1, 3],
	"tab_pressed": [Color8(230, 140, 0), Color8(40, 40, 40), 1, 3],
	"tab_selected": [Color8(62, 61, 62), Color8(25, 24, 25), 1, 3],
	"progress_bg": [Color8(60, 58, 60), Color8(20, 20, 20), 1, 2],
	"progress_bar": [Color8(255, 255, 255), Color8(0, 0, 0), 0, 2],
	"scroll_bg": [Color8(48, 44, 44), Color8(20, 20, 20), 1, 2],
	"thumb": [Color8(163, 163, 163), Color8(40, 40, 40), 1, 2],
	"thumb_hover": [Color8(255, 175, 0), Color8(40, 40, 40), 1, 2],
	"thumb_pressed": [Color8(230, 140, 0), Color8(40, 40, 40), 1, 2],
	"deep_slot_bg": [Color8(25, 24, 25), Color8(15, 14, 15), 1, 2],
	"queue_slot": [Color8(62, 61, 62), Color8(20, 20, 20), 1, 3],
	"queue_slot_hover": [Color8(255, 175, 0), Color8(20, 20, 20), 1, 3],
	"queue_slot_pressed": [Color8(230, 140, 0), Color8(20, 20, 20), 1, 3],
	"tech_available": [Color8(150, 128, 60), Color8(40, 35, 20), 2, 3],
	"tech_available_hover": [Color8(200, 170, 80), Color8(40, 35, 20), 2, 3],
	"tech_available_selected": [Color8(255, 210, 100), Color8(40, 35, 20), 2, 3],
	"tech_researched": [Color8(70, 140, 70), Color8(20, 45, 20), 2, 3],
	"tech_researched_hover": [Color8(100, 180, 100), Color8(20, 45, 20), 2, 3],
	"tech_researched_selected": [Color8(140, 220, 140), Color8(20, 45, 20), 2, 3],
	"tech_unavailable": [Color8(140, 60, 60), Color8(45, 20, 20), 2, 3],
	"tech_unavailable_hover": [Color8(180, 90, 90), Color8(45, 20, 20), 2, 3],
	"tech_unavailable_selected": [Color8(220, 120, 120), Color8(45, 20, 20), 2, 3],
	"tech_band_available": [Color8(77, 71, 48), Color8(40, 35, 20), 0, 2],
	"tech_band_researched": [Color8(40, 80, 40), Color8(20, 45, 20), 0, 2],
	"tech_band_unavailable": [Color8(80, 40, 40), Color8(45, 20, 20), 0, 2],
	"confirm": [Color8(94, 182, 99), Color8(30, 60, 30), 1, 3],
	"confirm_hover": [Color8(135, 216, 139), Color8(30, 60, 30), 1, 3],
	"confirm_pressed": [Color8(70, 150, 75), Color8(30, 60, 30), 1, 3],
	"confirm_disabled": [Color8(80, 100, 80), Color8(30, 60, 30), 1, 3],
	"back": [Color8(143, 143, 143), Color8(40, 40, 40), 1, 3],
	"back_hover": [Color8(255, 175, 0), Color8(40, 40, 40), 1, 3],
	"back_pressed": [Color8(230, 140, 0), Color8(40, 40, 40), 1, 3],
	"back_disabled": [Color8(100, 100, 100), Color8(40, 40, 40), 1, 3],
	"red_back": [Color8(254, 90, 90), Color8(70, 20, 20), 1, 3],
	"red_back_hover": [Color8(255, 140, 140), Color8(70, 20, 20), 1, 3],
	"red_back_pressed": [Color8(200, 60, 60), Color8(70, 20, 20), 1, 3],
	"red_back_disabled": [Color8(120, 70, 70), Color8(70, 20, 20), 1, 3],
	# slot_sized_button (quick_bar_page_button, shortcut_bar_button) and its blue, red, green kinds
	"page_button": [Color8(143, 143, 143), Color8(40, 40, 40), 1, 3],
	"page_button_hover": [Color8(255, 175, 0), Color8(40, 40, 40), 1, 3],
	"page_button_pressed": [Color8(240, 200, 120), Color8(40, 40, 40), 1, 3],
	"page_button_disabled": [Color8(70, 70, 70), Color8(40, 40, 40), 1, 3],
	"blue_page_button": [Color8(30, 110, 170), Color8(20, 40, 60), 1, 3],
	"blue_page_button_hover": [Color8(70, 150, 210), Color8(20, 40, 60), 1, 3],
	"blue_page_button_pressed": [Color8(20, 90, 140), Color8(20, 40, 60), 1, 3],
	"red_page_button": [Color8(170, 30, 30), Color8(60, 20, 20), 1, 3],
	"red_page_button_hover": [Color8(210, 70, 70), Color8(60, 20, 20), 1, 3],
	"red_page_button_pressed": [Color8(140, 20, 20), Color8(60, 20, 20), 1, 3],
	"green_page_button": [Color8(30, 120, 30), Color8(20, 60, 20), 1, 3],
	"green_page_button_hover": [Color8(70, 160, 70), Color8(20, 60, 20), 1, 3],
	"green_page_button_pressed": [Color8(20, 100, 20), Color8(20, 60, 20), 1, 3],
	"green_slot": [Color8(40, 160, 40), Color8(25, 24, 25), 1, 0],
	"green_slot_hover": [Color8(80, 200, 80), Color8(25, 24, 25), 1, 0],
	"green_slot_pressed": [Color8(30, 130, 30), Color8(25, 24, 25), 1, 0],
	"yellow_slot": [Color8(160, 130, 40), Color8(25, 24, 25), 1, 0],
	"yellow_slot_hover": [Color8(255, 175, 0), Color8(25, 24, 25), 1, 0],
	"yellow_slot_pressed": [Color8(230, 140, 0), Color8(25, 24, 25), 1, 0],
	"red_slot": [Color8(120, 40, 40), Color8(25, 24, 25), 1, 0],
	"red_slot_hover": [Color8(255, 175, 0), Color8(25, 24, 25), 1, 0],
	"red_slot_pressed": [Color8(230, 140, 0), Color8(25, 24, 25), 1, 0],
	# the top-right side menu: research_progress_inner_frame_*, side_menu_button
	"research_inactive": [Color8(36, 35, 36), Color8(15, 14, 15), 1, 2],
	"research_active": [Color8(62, 61, 62), Color8(25, 24, 25), 1, 2],
	"side_button": [Color8(45, 44, 45), Color8(25, 22, 21), 1, 2],
	"side_button_hover": [Color8(255, 175, 0), Color8(40, 40, 40), 1, 2],
	"side_button_pressed": [Color8(230, 140, 0), Color8(40, 40, 40), 1, 2],
}

## Content padding (Factorio's left/top/right/bottom_padding) per style, in GUI pixels.
const PADDING := {
	"frame": [8, 4, 8, 8],
	"frame_left": [8, 4, 4, 8],
	"frame_right": [8, 4, 8, 8],
	"frame_middle": [8, 4, 4, 8],
	"slot_window": [4, 4, 4, 4],
	"tab_pane": [12, 8, 12, 8],
	"subheader": [8, 3, 4, 5],
	"tooltip": [8, 4, 8, 6],
	"tooltip_title": [8, 1, 8, 1],
	"button": [8, 0, 8, 0],
	"green_button": [8, 0, 8, 0],
	"red_button": [8, 0, 8, 0],
	"tab": [3, 4, 4, 4],
	# dialog_button with an arrow: the text keeps clear of the arrow's point.
	"confirm": [12, 0, 28, 2],
	"back": [28, 0, 12, 2],
	"red_back": [28, 0, 12, 2],
}

## A frame's padding is measured inside its border (corner_size 8 of the double-size atlas: 4 GUI
## pixels), as measured on Factorio's own windows (tools/ui_reference): left, top, right, bottom.
const BORDER := {
	"frame": [4, 4, 4, 4],
	"frame_left": [4, 4, 0, 4],
	"frame_right": [0, 4, 4, 4],
	"frame_middle": [0, 4, 0, 4],
	"slot_window": [4, 4, 4, 4],
}

static var scale := 1.0
static var _scale_set := false
static var _styles := {}  # name -> StyleBox
static var _theme: Theme = null
static var _fallback_fonts := {}
static var _swatches := {}  # item -> ImageTexture, for items without an icon


static func configure(window_height: float) -> void:
	if _scale_set:
		return
	_scale_set = true
	scale = scale_for(window_height)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-scale="):
			scale = clampf(float(arg.get_slice("=", 1)), 0.5, 4.0)


## Factorio's automatic UI scale for a window this many lines high: 100% up to 1080 lines, then in
## steps of 25% (1440: 125%, 1659: 150%, 2160: 200%).
static func scale_for(window_height: float) -> float:
	return maxf(1.0, floorf(window_height / 1080.0 / 0.25 + 0.5) * 0.25)


## GUI pixels to screen pixels.
static func px(v: float) -> int:
	return roundi(v * scale)


static func pxv(x: float, y: float) -> Vector2:
	return Vector2(px(x), px(y))


static func uses_atlas() -> bool:
	return GuiAssets.available()


## "regular", "semibold" or "bold": Titillium from the install, or Godot's font made bolder.
static func font(weight: String) -> Font:
	var f := GuiAssets.font(weight)
	if f != null:
		return f
	if not _fallback_fonts.has(weight):
		var v := FontVariation.new()
		v.base_font = ThemeDB.fallback_font
		v.variation_embolden = {"regular": 0.0, "semibold": 0.4, "bold": 0.8}.get(weight, 0.0)
		_fallback_fonts[weight] = v
	return _fallback_fonts[weight]


# --- layers, from style.lua ------------------------------------------------------------------

static func _glow(tint: Color) -> Dictionary:  # default_glow
	return {"at": [200, 128], "corner": 8, "outer": true, "tint": tint}


static func _glow_no_left(tint: Color) -> Dictionary:  # glow_without_left
	return {"parts": {"t": [208, 128, 1, 8], "rt": [209, 128, 8, 8], "c": [208, 136, 1, 1],
		"r": [209, 136, 8, 1], "b": [208, 137, 1, 8], "rb": [209, 137, 8, 8]}, "outer": true, "tint": tint}


static func _glow_no_right(tint: Color) -> Dictionary:  # glow_without_right
	return {"parts": {"lt": [200, 128, 8, 8], "t": [208, 128, 1, 8], "l": [200, 136, 8, 1],
		"c": [208, 136, 1, 1], "lb": [200, 137, 8, 8], "b": [208, 137, 1, 8]}, "outer": true, "tint": tint}


static func _inner_shadow() -> Dictionary:  # default_inner_shadow
	return {"at": [183, 128], "corner": 8, "tint": Color(0, 0, 0, 1)}


static func _slot_glow(tint: Color) -> Dictionary:  # offset_by_2_rounded_corners_glow
	return {"at": [240, 736], "corner": 16, "outer": true, "shift": [4, 4, -4, -4], "tint": tint}


static func _square_glow(tint: Color) -> Dictionary:  # offset_by_2_default_glow
	return {"at": [280, 736], "corner": 16, "outer": true, "shift": [4, 4, -4, -4], "tint": tint}


static func _frame_button_shadow() -> Dictionary:
	return {"at": [440, 24], "corner": 8, "outer": true}


static func _base(x: int, y: int) -> Dictionary:
	return {"at": [x, y], "corner": 8}


static func _slot_image(x: int, y: int) -> Dictionary:
	return {"at": [x, y], "size": 80, "border": 4}


## Factorio's filter_group_tab: a button without its bottom edge, so it joins the pane below.
static func _tab_base(x: int) -> Dictionary:
	return {"parts": {"lt": [x, 17, 8, 8], "t": [x + 8, 17, 1, 8], "rt": [x + 9, 17, 8, 8],
		"l": [x, 25, 8, 1], "c": [x + 8, 25, 1, 1], "r": [x + 9, 25, 8, 1]}}


## Atlas rows of the technology slot images (style.lua: available_, researched_, unavailable_technology_slot).
const TECH_ROWS := {"tech_available": 136, "tech_researched": 187, "tech_unavailable": 170}


## arrow_idle_index, arrow_disabled_index, arrow_hovered_index, arrow_clicked_index.
static func _arrow_index(name: String) -> int:
	if name.ends_with("_disabled"):
		return 1
	if name.ends_with("_hover"):
		return 2
	if name.ends_with("_pressed"):
		return 3
	return 0


## style.lua's arrow_forward / arrow_back: a 48x64 arrow tileset cell gives the pointed end and
## the middle, the button composition tileset the flat end. Pieces are [x, y, w, h] in the atlas
## and where they go in a 33x64 picture, 9-sliced so only the middle stretches.
static func _arrow_button(arrows: Vector2i, comp: Vector2i, index: int, forward: bool) -> Dictionary:
	var a := arrows.x + index * 96
	var c := comp.x + index * 17
	var y := arrows.y
	if forward:
		return {"canvas": [33, 64], "margins": [8, 8, 24, 8], "pieces": [
			[c, comp.y, 8, 8, 0, 0, 8, 8], [c, comp.y + 8, 8, 1, 0, 8, 8, 48], [c, comp.y + 9, 8, 8, 0, 56, 8, 8],
			[a + 24, y, 1, 64, 8, 0, 1, 64], [a + 24, y, 24, 64, 9, 0, 24, 64]]}
	return {"canvas": [33, 64], "margins": [24, 8, 8, 8], "pieces": [
		[a, y, 24, 64, 0, 0, 24, 64], [a + 24, y, 1, 64, 24, 0, 1, 64],
		[c + 9, comp.y, 8, 8, 25, 0, 8, 8], [c + 9, comp.y + 8, 8, 1, 25, 8, 8, 48], [c + 9, comp.y + 9, 8, 8, 25, 56, 8, 8]]}


## The atlas row of a slot_sized_button colour.
static func _sized_row(name: String) -> int:
	if name.begins_with("blue_"):
		return 760
	if name.begins_with("red_"):
		return 776
	if name.begins_with("green_"):
		return 792
	return 744


static func _layers(name: String) -> Array:
	var dirt := _glow(DIRT_COLOR)
	match name:
		"frame", "slot_window":
			return [_glow(SHADOW_COLOR), _base(0, 0)]
		"frame_left":  # character_gui_left_side
			return [_glow_no_right(SHADOW_COLOR), {"parts": {"lt": [0, 0, 8, 8], "l": [0, 8, 8, 1], "lb": [0, 9, 8, 8],
				"t": [8, 0, 1, 8], "b": [8, 9, 1, 8], "c": [8, 8, 1, 1]}}]
		"frame_right":  # frame_without_left_side
			return [_glow_no_left(SHADOW_COLOR), {"parts": {"rt": [9, 0, 8, 8], "r": [9, 8, 8, 1], "rb": [9, 9, 8, 8],
				"t": [8, 0, 1, 8], "b": [8, 9, 1, 8], "c": [8, 8, 1, 1]}}]
		"frame_middle":  # a frame between frame_left and frame_right: only its top and bottom edges
			return [{"parts": {"t": [8, 0, 1, 8], "b": [8, 9, 1, 8], "c": [8, 8, 1, 1]}}]
		"deep":  # inside_deep_frame
			return [{"at": [17, 0], "corner": 8, "center": [42, 8, 1, 1], "outer": true}, _inner_shadow()]
		"shallow":  # inside_shallow_frame
			return [{"at": [17, 0], "corner": 8, "center": [76, 8, 1, 1], "outer": true}, _inner_shadow()]
		"tab_pane":  # tabbed_pane_graphical_set (filter_frame)
			return [{"parts": {"t": [76, 0, 1, 8], "c": [76, 8, 1, 1], "b": [76, 9, 1, 8]}}]
		"subheader":  # subheader_frame
			return [{"parts": {"c": [256, 25, 1, 1], "b": [256, 26, 1, 8]}}]
		"tooltip":  # tooltip_frame
			return [_glow(SHADOW_COLOR), _base(403, 0)]
		"tooltip_title":  # tooltip_title_frame_light
			return [_base(352, 0)]
		"quickbar_inner":  # quick_bar_inner_panel
			return [_frame_button_shadow(), {"parts": {"c": [42, 8, 1, 1]}}]
		"draggable":  # draggable_space
			return [_glow(DIRT_FILLER_COLOR), {"parts": {"t": [192, 8, 8, 7], "c": [200, 8, 8, 8], "b": [208, 8, 8, 8]}, "tile": true}]
		"button":
			return [dirt, _base(0, 17)]
		"button_hover":
			return [dirt, _base(34, 17), _glow(GLOW_COLOR)]
		"button_pressed":
			return [dirt, _base(51, 17)]
		"button_disabled":
			return [dirt, _base(17, 17)]
		"button_selected":
			return [dirt, _base(225, 17)]
		"green_button":
			return [dirt, _base(68, 17)]
		"green_button_hover":
			return [dirt, _base(102, 17), _glow(GREEN_GLOW)]
		"green_button_pressed":
			return [dirt, _base(119, 17)]
		"green_button_disabled":
			return [dirt, _base(85, 17)]
		"red_button":
			return [dirt, _base(136, 17)]
		"red_button_hover":
			return [dirt, _base(170, 17), _glow(RED_GLOW)]
		"red_button_pressed":
			return [dirt, _base(187, 17)]
		"red_button_disabled":
			return [dirt, _base(153, 17)]
		"frame_action":  # frame_button
			return [_frame_button_shadow(), _base(0, 0)]
		"frame_action_hover":
			return [_frame_button_shadow(), _base(34, 17), _glow(GLOW_COLOR)]
		"frame_action_pressed":
			return [_frame_button_shadow(), _base(51, 17)]
		# slot_sized_button: quick_bar_page_button, shortcut_bar_button (rows 744; blue 760, red 776,
		# green 792), its shadow offset_by_2_default_glow(default_dirt_color, 0.5).
		"page_button", "blue_page_button", "red_page_button", "green_page_button":
			return [_square_glow(Color(DIRT_COLOR, 0.5)), _base(312, _sized_row(name))]
		"page_button_hover", "blue_page_button_hover", "red_page_button_hover", "green_page_button_hover":
			return [_square_glow(Color(DIRT_COLOR, 0.5)), _base(346, _sized_row(name)), _square_glow(Color(GLOW_COLOR, 0.5))]
		"page_button_pressed", "blue_page_button_pressed", "red_page_button_pressed", "green_page_button_pressed":
			return [_square_glow(Color(DIRT_COLOR, 0.5)), _base(363, _sized_row(name))]
		"page_button_disabled":
			return [_square_glow(Color(DIRT_COLOR, 0.5)), _base(329, 744)]
		"research_inactive":  # research_progress_inner_frame_inactive
			return [_base(34, 0)]
		"research_active":  # research_progress_inner_frame_active
			return [_base(68, 0)]
		"side_button":  # side_menu_button
			return [_base(0, 0)]
		"side_button_hover":
			return [_base(34, 17), _glow(GLOW_COLOR)]
		"side_button_pressed":
			return [_base(51, 17)]
		"green_slot":  # the gun in use and its ammo (tool_equip slots)
			return [_slot_image(504, 136)]
		"green_slot_hover":
			return [_slot_image(504, 216)]
		"green_slot_pressed":
			return [_slot_image(504, 296)]
		"slot":  # inventory_slot
			return [_slot_image(0, 424)]
		"slot_hover":
			return [_slot_image(80, 424)]
		"slot_pressed":
			return [_slot_image(160, 424)]
		"slot_selected":
			return [_slot_image(160, 504)]
		# yellow_slot (a machine's product with items in it) and red_slot (an ingredient that is short).
		"yellow_slot":
			return [_slot_image(0, 816)]
		"yellow_slot_hover":
			return [_slot_image(80, 816)]
		"yellow_slot_pressed":
			return [_slot_image(160, 816)]
		"red_slot":
			return [_slot_image(240, 816)]
		"red_slot_hover":
			return [_slot_image(320, 816)]
		"red_slot_pressed":
			return [_slot_image(400, 816)]
		"slot_button":
			return [_slot_glow(DIRT_COLOR), _slot_image(0, 736)]
		"slot_button_hover":
			return [_slot_glow(DIRT_COLOR), _slot_image(80, 736), _slot_glow(GLOW_COLOR)]
		"slot_button_pressed":
			return [_slot_glow(DIRT_COLOR), _slot_image(160, 736)]
		"red_slot_button":
			return [_slot_glow(DIRT_COLOR), _slot_image(240, 656)]
		"red_slot_button_hover":
			return [_slot_glow(DIRT_COLOR), _slot_image(320, 656), _slot_glow(Color(1.0, 166 / 255.0, 123 / 255.0, 0.5))]
		"red_slot_button_pressed":
			return [_slot_glow(DIRT_COLOR), _slot_image(400, 656)]
		"tab":
			return [_glow(SHADOW_COLOR), _tab_base(0)]
		"tab_hover":
			return [_tab_base(34), _glow(GLOW_COLOR)]
		"tab_pressed":
			return [_glow(GLOW_COLOR), _base(51, 17)]
		"tab_selected":
			return [_glow(SHADOW_COLOR), {"parts": {"lt": [68, 0, 8, 8], "t": [76, 0, 1, 8], "rt": [77, 0, 8, 8],
				"l": [68, 8, 8, 1], "c": [76, 8, 1, 1], "r": [77, 8, 8, 1]}}]
		"progress_bg":
			return [dirt, _base(296, 48)]
		"progress_bar":
			return [_base(313, 48)]
		"scroll_bg":  # vertical_scrollbar
			return [_base(0, 72)]
		"thumb":
			return [_glow(SHADOW_COLOR), {"parts": {"t": [0, 48, 20, 7], "c": [0, 55, 20, 8], "b": [0, 63, 20, 7]}, "tile_v": true}]
		"thumb_hover":
			return [{"parts": {"t": [20, 48, 20, 7], "c": [20, 55, 20, 8], "b": [20, 63, 20, 7]}, "tile_v": true}, _glow(GLOW_COLOR)]
		"thumb_pressed":
			return [_glow(SHADOW_COLOR), {"parts": {"t": [40, 48, 20, 7], "c": [40, 55, 20, 8], "b": [40, 63, 20, 7]}, "tile_v": true}]
		"deep_slot_bg":  # deep_slot_background_tiling, one cell
			return [_base(282, 17)]
		"queue_slot":  # crafting_queue_slot
			return [_base(48, 584)]
		"queue_slot_hover":
			return [_base(64, 584)]
		"queue_slot_pressed":
			return [_base(80, 584)]
		# technology_slot styles: available (yellow), researched (green), unavailable (red); hovered
		# is the next image right, highlighted (selected) the one after.
		"tech_available", "tech_researched", "tech_unavailable":
			return [_glow(SHADOW_COLOR), _base(296, TECH_ROWS[name])]
		"tech_available_hover", "tech_researched_hover", "tech_unavailable_hover":
			return [_glow(SHADOW_COLOR), _base(312, TECH_ROWS[name.trim_suffix("_hover")])]
		"tech_available_selected", "tech_researched_selected", "tech_unavailable_selected":
			return [_glow(SHADOW_COLOR), _base(330, TECH_ROWS[name.trim_suffix("_selected")])]
		"tech_band_available", "tech_band_researched", "tech_band_unavailable":  # *_ingredients_background
			return [_base(347, TECH_ROWS["tech_" + name.trim_prefix("tech_band_")])]
		# confirm_button (green, arrow right), back_button (grey, arrow left), red_back_button.
		"confirm", "confirm_disabled", "confirm_hover", "confirm_pressed":
			return [_arrow_button(Vector2i(0, 296), Vector2i(68, 17), _arrow_index(name), true)]
		"back", "back_disabled", "back_hover", "back_pressed":
			return [_arrow_button(Vector2i(0, 232), Vector2i(0, 17), _arrow_index(name), false)]
		"red_back", "red_back_disabled", "red_back_hover", "red_back_pressed":
			return [_arrow_button(Vector2i(0, 360), Vector2i(136, 17), _arrow_index(name), false)]
	push_warning("kit: no style %s" % name)
	return []


# --- style boxes -----------------------------------------------------------------------------

## The named style as a StyleBox (cached). Its content margins are Factorio's padding.
static func style(name: String) -> StyleBox:
	if _styles.has(name):
		return _styles[name]
	var box: StyleBox
	if uses_atlas():
		var layered := LayeredStyle.new()
		for spec in _layers(name):
			var layer := _bake(spec)
			if layer != null:
				layered.layers.append(layer)
		box = layered
	else:
		box = _flat(name)
	var base_name := name
	for suffix in ["_hover", "_pressed", "_disabled", "_selected"]:
		base_name = base_name.trim_suffix(suffix)
	var pad: Array = PADDING.get(base_name, [0, 0, 0, 0])
	var edge: Array = BORDER.get(base_name, [0, 0, 0, 0])
	box.content_margin_left = px(pad[0] + edge[0])
	box.content_margin_top = px(pad[1] + edge[1])
	box.content_margin_right = px(pad[2] + edge[2])
	box.content_margin_bottom = px(pad[3] + edge[3])
	_styles[name] = box
	return box


## The named style with other content margins (GUI pixels: left, top, right, bottom). A copy that
## shares the layers: duplicate() doesn't copy LayeredStyle's layers.
static func style_with_margins(name: String, l: float, t: float, r: float, b: float) -> StyleBox:
	var key := "%s@%s,%s,%s,%s" % [name, l, t, r, b]
	if _styles.has(key):
		return _styles[key]
	var source := style(name)
	var box: StyleBox
	if source.get_script() == LayeredStyle:
		box = LayeredStyle.new()
		box.layers = source.layers
	else:
		box = source.duplicate()
	box.content_margin_left = px(l)
	box.content_margin_top = px(t)
	box.content_margin_right = px(r)
	box.content_margin_bottom = px(b)
	_styles[key] = box
	return box


## The progress bar's fill, tinted.
static func bar_style(color: Color) -> StyleBox:
	var key := "progress_bar:" + color.to_html()
	if _styles.has(key):
		return _styles[key]
	var box: StyleBox
	if uses_atlas():
		var spec := _base(313, 48)
		spec["tint"] = color
		var layered := LayeredStyle.new()
		layered.layers.append(_bake(spec))
		box = layered
	else:
		var flat: StyleBoxFlat = _flat("progress_bar")
		flat.bg_color = color
		box = flat
	_styles[key] = box
	return box


static func _flat(name: String) -> StyleBoxFlat:
	var f: Array = FLAT.get(name, [Color8(45, 44, 45), Color8(20, 20, 20), 1, 0])
	var box := StyleBoxFlat.new()
	box.bg_color = f[0]
	box.border_color = f[1]
	box.set_border_width_all(int(f[2]))
	box.set_corner_radius_all(px(f[3]))
	if name == "frame" or name == "tooltip" or name.begins_with("frame_"):
		box.shadow_color = SHADOW_COLOR
		box.shadow_size = px(4)
	return box


## One layer: the pieces cut from the atlas, scaled to the UI scale and put back together as a
## small 9-slice texture.
static func _bake(spec: Dictionary) -> StyleBox:
	var atlas := GuiAssets.atlas()
	var f := 0.5 * scale
	var box := StyleBoxTexture.new()
	var image: Image
	var margins := [0, 0, 0, 0]  # left, top, right, bottom
	if spec.has("pieces"):
		var canvas: Array = spec["canvas"]
		image = Image.create(_scaled(canvas[0], f), _scaled(canvas[1], f), false, Image.FORMAT_RGBA8)
		for p in spec["pieces"]:
			var x0 := roundi(p[4] * f)
			var y0 := roundi(p[5] * f)
			var w := maxi(1, roundi((p[4] + p[6]) * f) - x0)
			var h := maxi(1, roundi((p[5] + p[7]) * f) - y0)
			var piece := atlas.get_region(Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
			piece.resize(w, h, Image.INTERPOLATE_LANCZOS)
			image.blit_rect(piece, Rect2i(0, 0, w, h), Vector2i(x0, y0))
		var m: Array = spec["margins"]
		margins = [_scaled(m[0], f), _scaled(m[1], f), _scaled(m[2], f), _scaled(m[3], f)]
	elif spec.has("border"):
		var at: Array = spec["at"]
		var s := int(spec["size"])
		image = atlas.get_region(Rect2i(int(at[0]), int(at[1]), s, s))
		var side := maxi(1, roundi(s * f))
		image.resize(side, side, Image.INTERPOLATE_LANCZOS)
		var b := maxi(1, roundi(int(spec["border"]) * f))
		margins = [b, b, b, b]
	else:
		var parts := _parts(spec)
		var widths := [_extent(parts, ["lt", "l", "lb"], 2), _extent(parts, ["t", "c", "b"], 2), _extent(parts, ["rt", "r", "rb"], 2)]
		var heights := [_extent(parts, ["lt", "t", "rt"], 3), _extent(parts, ["l", "c", "r"], 3), _extent(parts, ["lb", "b", "rb"], 3)]
		var sw := [_scaled(widths[0], f), _scaled_middle(widths[1], f), _scaled(widths[2], f)]
		var sh := [_scaled(heights[0], f), _scaled_middle(heights[1], f), _scaled(heights[2], f)]
		image = Image.create(maxi(1, sw[0] + sw[1] + sw[2]), maxi(1, sh[0] + sh[1] + sh[2]), false, Image.FORMAT_RGBA8)
		var names := [["lt", "t", "rt"], ["l", "c", "r"], ["lb", "b", "rb"]]
		var y := 0
		for row in 3:
			var x := 0
			for col in 3:
				var key: String = names[row][col]
				if parts.has(key) and sw[col] > 0 and sh[row] > 0:
					var r: Array = parts[key]
					var piece := atlas.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
					if piece.get_width() != sw[col] or piece.get_height() != sh[row]:
						piece.resize(sw[col], sh[row], Image.INTERPOLATE_LANCZOS)
					image.blit_rect(piece, Rect2i(0, 0, sw[col], sh[row]), Vector2i(x, y))
				x += sw[col]
			y += sh[row]
		margins = [sw[0], sh[0], sw[2], sh[2]]
		box.draw_center = parts.has("c") or parts.has("t") or parts.has("b")
	box.texture = ImageTexture.create_from_image(image)
	box.texture_margin_left = margins[0]
	box.texture_margin_top = margins[1]
	box.texture_margin_right = margins[2]
	box.texture_margin_bottom = margins[3]
	if spec.get("outer", false):
		var shift: Array = spec.get("shift", [0, 0, 0, 0])
		box.expand_margin_left = margins[0] - shift[0] * f
		box.expand_margin_top = margins[1] - shift[1] * f
		box.expand_margin_right = margins[2] + shift[2] * f
		box.expand_margin_bottom = margins[3] + shift[3] * f
	if spec.get("tile", false):
		box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	if spec.get("tile_v", false):
		box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	if spec.has("tint"):
		box.modulate_color = spec["tint"]
	return box


static func _parts(spec: Dictionary) -> Dictionary:
	if spec.has("parts"):
		return spec["parts"]
	var at: Array = spec["at"]
	var x := int(at[0])
	var y := int(at[1])
	var c := int(spec["corner"])
	var parts := {
		"lt": [x, y, c, c], "t": [x + c, y, 1, c], "rt": [x + c + 1, y, c, c],
		"l": [x, y + c, c, 1], "c": [x + c, y + c, 1, 1], "r": [x + c + 1, y + c, c, 1],
		"lb": [x, y + c + 1, c, c], "b": [x + c, y + c + 1, 1, c], "rb": [x + c + 1, y + c + 1, c, c],
	}
	if spec.has("center"):
		parts["c"] = spec["center"]
	return parts


## The width (index 2) or height (3) of a row or column of pieces.
static func _extent(parts: Dictionary, keys: Array, index: int) -> int:
	for key in keys:
		if parts.has(key):
			return int(parts[key][index])
	return 0


static func _scaled(v: int, f: float) -> int:
	return 0 if v == 0 else maxi(1, roundi(v * f))


## A 1-pixel middle stays 1 pixel (it is stretched anyway); wider ones (tiles) are scaled.
static func _scaled_middle(v: int, f: float) -> int:
	return v if v <= 1 else maxi(1, roundi(v * f))


# --- theme -----------------------------------------------------------------------------------

## The theme for everything on screen: Factorio's look for Godot's own controls, plus type
## variations for Factorio's styles (set a control's theme_type_variation):
##   panels: FFrame, FFrameLeft, FFrameMiddle, FFrameRight, FSlotWindow, FDeepFrame, FShallowFrame, FTabPane,
##           FSubheader, FTooltip, FTooltipTitle, FQuickbarInner, FDraggable
##   buttons: FGreenButton, FRedButton, FFrameAction, FSlot, FSlotButton, FRedSlotButton, FTab,
##            FPageButton (slot_sized_button) and its FBlue/FRed/FGreenPageButton, FToolSlot (weapons)
##   labels: FCaption (frame title), FHeading (bold), FTooltipTitleLabel, FGameLabel (outlined)
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = px(14)

	t.set_color("font_color", "Label", WHITE)
	_variation(t, "FCaption", "Label")
	t.set_font("font", "FCaption", font("bold"))
	t.set_font_size("font_size", "FCaption", px(18))
	t.set_color("font_color", "FCaption", CAPTION)
	_variation(t, "FHeading", "Label")
	t.set_font("font", "FHeading", font("bold"))
	t.set_color("font_color", "FHeading", CAPTION)
	_variation(t, "FTooltipTitleLabel", "Label")
	t.set_font("font", "FTooltipTitleLabel", font("bold"))
	t.set_color("font_color", "FTooltipTitleLabel", BLACK)
	_variation(t, "FGameLabel", "Label")  # default-game: 18 with a border
	t.set_font_size("font_size", "FGameLabel", px(18))
	t.set_color("font_outline_color", "FGameLabel", BLACK)
	t.set_constant("outline_size", "FGameLabel", px(4))
	_variation(t, "FSmallLabel", "Label")  # HUD text over the world
	t.set_font("font", "FSmallLabel", font("semibold"))
	t.set_color("font_outline_color", "FSmallLabel", Color(0, 0, 0, 0.85))
	t.set_constant("outline_size", "FSmallLabel", px(4))

	_buttons(t, "Button", "button")
	t.set_font("font", "Button", font("semibold"))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "Button", BLACK)
	t.set_color("font_disabled_color", "Button", DISABLED_TEXT)
	t.set_constant("h_separation", "Button", px(4))
	for v in ["FGreenButton:green_button", "FRedButton:red_button", "FFrameAction:frame_action",
			"FSlot:slot", "FSlotButton:slot_button", "FRedSlotButton:red_slot_button", "FTab:tab",
			"FPageButton:page_button", "FBluePageButton:blue_page_button", "FRedPageButton:red_page_button",
			"FGreenPageButton:green_page_button", "FGreenSlot:green_slot", "FYellowSlot:yellow_slot", "FRedSlot:red_slot", "FSideButton:side_button"]:
		var type_name: String = v.get_slice(":", 0)
		_variation(t, type_name, "Button")
		_buttons(t, type_name, v.get_slice(":", 1))
	# quick_bar_page_button: default-bold in button_hovered_font_color; toggled is the clicked look
	# (a shortcut that is on, like Alt-mode).
	for v in ["FPageButton:page_button", "FBluePageButton:blue_page_button", "FRedPageButton:red_page_button",
			"FGreenPageButton:green_page_button"]:
		var type_name: String = v.get_slice(":", 0)
		t.set_font("font", type_name, font("bold"))
		t.set_stylebox("hover_pressed", type_name, style(v.get_slice(":", 1) + "_pressed"))
	# Dialog buttons: confirm (green, arrow right) and back (grey or red, arrow left), bold 18.
	for v in ["FConfirmButton:confirm", "FBackButton:back", "FRedBackButton:red_back"]:
		var type_name: String = v.get_slice(":", 0)
		_variation(t, type_name, "Button")
		_buttons(t, type_name, v.get_slice(":", 1))
		t.set_font("font", type_name, font("bold"))
		t.set_font_size("font_size", type_name, px(18))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(c, type_name, BUTTON_BOLD_TEXT)
	_variation(t, "FQueueSlot", "Button")
	t.set_stylebox("normal", "FQueueSlot", style("queue_slot"))
	t.set_stylebox("hover", "FQueueSlot", style("queue_slot_hover"))
	t.set_stylebox("pressed", "FQueueSlot", style("queue_slot_pressed"))
	t.set_stylebox("hover_pressed", "FQueueSlot", style("queue_slot_pressed"))
	t.set_stylebox("focus", "FQueueSlot", StyleBoxEmpty.new())
	# Technology slots: toggled is Factorio's highlighted (selected) look.
	for state in ["available", "researched", "unavailable"]:
		var type_name: String = "FTech" + str(state).capitalize()
		_variation(t, type_name, "Button")
		t.set_stylebox("normal", type_name, style("tech_" + state))
		t.set_stylebox("disabled", type_name, style("tech_" + state))
		t.set_stylebox("hover", type_name, style("tech_%s_hover" % state))
		t.set_stylebox("pressed", type_name, style("tech_%s_selected" % state))
		t.set_stylebox("hover_pressed", type_name, style("tech_%s_selected" % state))
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		_variation(t, "FTechBand" + state.capitalize(), "PanelContainer")
		t.set_stylebox("panel", "FTechBand" + state.capitalize(), style("tech_band_" + state))
	# The weapon slots (tool_equip_ammo_slot): toggled is the gun in use, drawn green as the game does.
	_variation(t, "FToolSlot", "Button")
	_buttons(t, "FToolSlot", "slot")
	t.set_stylebox("pressed", "FToolSlot", style("green_slot"))
	t.set_stylebox("hover_pressed", "FToolSlot", style("green_slot_hover"))
	# Toggled slots and tabs show Factorio's "selected" look.
	t.set_stylebox("pressed", "FSlot", style("slot_selected"))
	t.set_stylebox("hover_pressed", "FSlot", style("slot_hover"))
	t.set_stylebox("pressed", "FTab", style("tab_selected"))
	t.set_stylebox("hover_pressed", "FTab", style("tab_selected"))
	t.set_stylebox("pressed", "FSlotButton", style("slot_button_pressed"))
	t.set_stylebox("hover_pressed", "FSlotButton", style("slot_button_hover"))

	t.set_stylebox("panel", "PanelContainer", style("frame"))
	t.set_stylebox("panel", "Panel", style("frame"))
	for v in ["FFrame:frame", "FFrameLeft:frame_left", "FFrameRight:frame_right", "FFrameMiddle:frame_middle", "FSlotWindow:slot_window",
			"FDeepFrame:deep", "FShallowFrame:shallow", "FTabPane:tab_pane", "FSubheader:subheader",
			"FTooltip:tooltip", "FTooltipTitle:tooltip_title", "FQuickbarInner:quickbar_inner", "FDraggable:draggable",
			"FResearchInactive:research_inactive", "FResearchActive:research_active"]:
		var type_name: String = v.get_slice(":", 0)
		_variation(t, type_name, "PanelContainer")
		t.set_stylebox("panel", type_name, style(v.get_slice(":", 1)))

	_variation(t, "FDeepSlotBg", "Panel")
	t.set_stylebox("panel", "FDeepSlotBg", style("deep_slot_bg"))

	# Every tooltip popup gets Factorio's tooltip frame: plain ones (tooltip_text) and tooltip()'s.
	t.set_stylebox("panel", "TooltipPanel", style("tooltip"))
	t.set_color("font_color", "TooltipLabel", WHITE)
	t.set_font("font", "TooltipLabel", font("regular"))
	t.set_font_size("font_size", "TooltipLabel", px(14))

	t.set_stylebox("background", "ProgressBar", style("progress_bg"))
	t.set_stylebox("fill", "ProgressBar", bar_style(BAR_GREEN))
	t.set_color("font_color", "ProgressBar", WHITE)

	var scroll := style("scroll_bg").duplicate() as StyleBox
	scroll.content_margin_left = px(6)
	scroll.content_margin_right = px(6)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("scroll_focus", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", style("thumb"))
	t.set_stylebox("grabber_highlight", "VScrollBar", style("thumb_hover"))
	t.set_stylebox("grabber_pressed", "VScrollBar", style("thumb_pressed"))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


static func _variation(t: Theme, type_name: String, base: String) -> void:
	t.set_type_variation(type_name, base)


static func _buttons(t: Theme, type_name: String, style_name: String) -> void:
	t.set_stylebox("normal", type_name, style(style_name))
	t.set_stylebox("hover", type_name, style(style_name + "_hover"))
	t.set_stylebox("pressed", type_name, style(style_name + "_pressed"))
	t.set_stylebox("hover_pressed", type_name, style(style_name + "_pressed"))
	t.set_stylebox("disabled", type_name, style(style_name + "_disabled") if _has_style(style_name + "_disabled") else style(style_name))
	t.set_stylebox("focus", type_name, StyleBoxEmpty.new())


static func _has_style(name: String) -> bool:
	return FLAT.has(name)


# --- widgets ---------------------------------------------------------------------------------

## A label in one of the theme's label variations.
static func label(text: String, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel(variation: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


## A frame's title bar: caption, the ribbed drag handle, and optionally the close button.
## Returns the HBoxContainer; the close button (if any) is its last child.
static func title_bar(title: String, closable: bool) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", px(8))
	bar.custom_minimum_size.y = px(28)
	var caption := label(title, "FCaption")
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(caption)
	var space := panel("FDraggable")  # draggable_space_header
	space.custom_minimum_size.y = px(24)
	# The header is the filler's 24 high plus frame_header_flow's bottom_padding of 4: the filler
	# sits at its top.
	space.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(space)
	if closable:
		bar.add_child(close_button())
	return bar


## frame_action_button with Factorio's cross (black when hovered, like the game's inverted icon).
static func close_button() -> Button:
	var b := Button.new()
	b.theme_type_variation = "FFrameAction"
	b.custom_minimum_size = pxv(24, 24)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Close"
	var cross := GuiAssets.core_sprite("icons/close.png")
	if cross != null:
		b.icon = cross
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", px(16))
		b.add_theme_color_override("icon_normal_color", WHITE)
		b.add_theme_color_override("icon_hover_color", BLACK)
		b.add_theme_color_override("icon_pressed_color", BLACK)
	else:
		b.text = "×"
		b.add_theme_color_override("font_color", WHITE)
	return b


## A deep frame (inside_deep_frame) around a scrolling area; returns [frame, scroll].
static func deep_scroll(min_size: Vector2) -> Array:
	var frame := panel("FDeepFrame")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE  # arrow keys walk; they mustn't scroll the window
	scroll.custom_minimum_size = min_size
	frame.add_child(scroll)
	return [frame, scroll]


## An empty cell of a slot grid: the recess of deep_slot_background_tiling (a 32x32 tile in the
## middle of the 40x40 cell).
static func empty_cell() -> Control:
	var m := MarginContainer.new()
	m.custom_minimum_size = pxv(SLOT, SLOT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, px(4))
	var p := Panel.new()
	p.theme_type_variation = "FDeepSlotBg"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(p)
	return m


## A grid of slots with no gaps, 10 wide.
static func slot_grid(columns := COLUMNS) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	return grid


static func progress_bar(color: Color = BAR_GREEN) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(px(40), px(8))  # bar_width = 8
	bar.add_theme_stylebox_override("fill", bar_style(color))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


## A Factorio tooltip: the light title bar, then lines of text, each optionally led by an item
## icon and coloured (lines are [text], [text, item] or [text, item or "", Color]; [text, "", null,
## "keys"] is a control hint, "Middle-click| to clear shortcut." with the keys before | in bold blue).
## The popup around it draws the tooltip frame (theme: TooltipPanel).
static func tooltip(title: String, lines: Array) -> Control:
	var box := VBoxContainer.new()
	box.texture_filter = FILTER
	box.custom_minimum_size.x = px(120)
	box.add_theme_constant_override("separation", px(2))
	var frame := box
	var head := panel("FTooltipTitle")
	head.add_child(label(title, "FTooltipTitleLabel"))
	box.add_child(head)
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", px(4))
		if line is Array and line.size() > 1 and str(line[1]) != "":
			var icon := TextureRect.new()
			icon.texture = item_icon(str(line[1]))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = pxv(24, 24)
			icon.texture_filter = ICON_FILTER
			row.add_child(icon)
		var text := str(line[0]) if line is Array else str(line)
		var color: Variant = line[2] if line is Array and line.size() > 2 and line[2] is Color else null
		if line is Array and line.size() > 3 and str(line[3]) == "keys":
			# A control hint: "Middle-click| to clear shortcut." with the part before | in bold blue.
			var parts := text.split("|", true, 1)
			var k := label(parts[0])
			k.add_theme_font_override("font", font("bold"))
			k.add_theme_color_override("font_color", KEY_TEXT)
			row.add_theme_constant_override("separation", 0)
			row.add_child(k)
			if parts.size() > 1:
				row.add_child(label(parts[1]))
			box.add_child(row)
			continue
		for l in key_value_labels(text, color):
			row.add_child(l)
		box.add_child(row)
	return frame


## A tooltip line as Factorio writes it: "Stack size: 100" with the name in bold, a heading
## ("Ingredients:") in the caption colour, anything else plain. `color` tints the line.
static func key_value_labels(text: String, color: Variant = null) -> Array[Label]:
	var out: Array[Label] = []
	var cut := text.find(": ")
	if text.ends_with(":"):
		out.append(label(text, "FHeading"))
	elif cut > 0 and cut <= 32:
		var k := label(text.substr(0, cut + 1))
		k.add_theme_font_override("font", font("bold"))
		out.append(k)
		out.append(label(" " + text.substr(cut + 2)))
	else:
		out.append(label(text))
	for l in out:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if color is Color:
			l.add_theme_color_override("font_color", color)
	return out


## Factorio's plain tooltip (no title bar), as on its HUD buttons: each line of the text, a
## trailing "(keys)" with the keys in bold blue ("Toggle "Alt-mode" (Left Alt)").
static func simple_tooltip(text: String) -> Control:
	var box := VBoxContainer.new()
	box.texture_filter = FILTER
	box.add_theme_constant_override("separation", px(2))
	for line in text.split("\n"):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var keys := ""
		var open := line.rfind(" (")
		if line.ends_with(")") and open > 0:
			keys = line.substr(open + 2, line.length() - open - 3)
			line = line.substr(0, open)
		row.add_child(label(line))
		if keys != "":
			row.add_child(label(" ("))
			var k := label(keys)
			k.add_theme_font_override("font", font("bold"))
			k.add_theme_color_override("font_color", KEY_TEXT)
			row.add_child(k)
			row.add_child(label(")"))
		box.add_child(row)
	return box


## The item's icon from the Factorio install, or a swatch of its colour.
static func item_icon(item: String) -> Texture2D:
	var texture := ItemIcons.texture_for(item)
	if texture == null and item != "":
		texture = GuiAssets.other_icon(item)  # fluids and virtual signals
	if texture == null and item != "":
		texture = ItemIcons.texture_for_kind("entity", item)  # a straight rail, a rock: no item of that name
	if texture != null:
		return texture
	if not _swatches.has(item):
		var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		image.fill(ItemIcons.color_for(item))
		_swatches[item] = ImageTexture.create_from_image(image)
	return _swatches[item]


## Display names from the player's Factorio locale files (locale_names.gd), "iron-gear-wheel" ->
## "Iron gear wheel" without an install.
static func pretty(name: String) -> String:
	return LocaleNames.item(name)


static func recipe_name(name: String) -> String:
	return LocaleNames.recipe(name)


static func entity_name(name: String) -> String:
	return LocaleNames.entity(name)


static func tech_name(name: String) -> String:
	return LocaleNames.technology(name)


static func group_name(name: String) -> String:
	return LocaleNames._first(name, ["item-group-name"])


## Factorio's short counts: 999, 1.2k, 12k, 1.2M.
static func count_text(n: int) -> String:
	if n < 1000:
		return str(n)
	if n < 10000:
		return ("%.1fk" % (n / 1000.0)).replace(".0k", "k")
	if n < 1000000:
		return "%dk" % (n / 1000)
	return ("%.1fM" % (n / 1000000.0)).replace(".0M", "M")
