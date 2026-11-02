extends RefCounted
## The menus' additions to the Factorio UI kit (kit.gd): Factorio's menu buttons, text boxes,
## check boxes, sliders, dropdowns and list items, cut from the same GUI atlas with the numbers
## from core/prototypes/style.lua (menu_button, textbox, checkbox, slider, dropdown,
## list_box_item), plus helpers for dialogs laid out like Factorio's (a frame with a title bar,
## the content, then Back on the left and the confirm button on the right).
##
## Theme type variations added: FMenuButton, FMenuButtonGreen (menu_button, menu_button_continue),
## FListItem, FListItemSelected, FVersionLabel; LineEdit, CheckBox, HSlider, OptionButton and
## PopupMenu get Factorio's look.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const LayeredStyle := preload("res://scripts/ui/factorio/layered_style.gd")

const TEXTBOX_SELECTION := Color8(241, 190, 100)
const LIST_FLAT := {
	"normal": [Color8(62, 61, 62), Color8(30, 30, 30)],
	"hover": [Color8(255, 175, 0), Color8(30, 30, 30)],
	"pressed": [Color8(230, 140, 0), Color8(30, 30, 30)],
}

static var _theme: Theme = null


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.merge_with(Kit.theme())
	var bold := Kit.font("bold")

	# menu_button: dialog font (bold 18), dark text, 320 x 50.
	for v in ["FMenuButton:button", "FMenuButtonGreen:green_button"]:
		var type_name: String = v.get_slice(":", 0)
		var style_name: String = v.get_slice(":", 1)
		t.set_type_variation(type_name, "Button")
		t.set_stylebox("normal", type_name, Kit.style(style_name))
		t.set_stylebox("hover", type_name, Kit.style(style_name + "_hover"))
		t.set_stylebox("pressed", type_name, Kit.style(style_name + "_pressed"))
		t.set_stylebox("hover_pressed", type_name, Kit.style(style_name + "_pressed"))
		t.set_stylebox("disabled", type_name, Kit.style(style_name + "_disabled"))
		t.set_stylebox("focus", type_name, StyleBoxEmpty.new())
		t.set_font("font", type_name, bold)
		t.set_font_size("font_size", type_name, Kit.px(18))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(c, type_name, Kit.BUTTON_BOLD_TEXT)
		t.set_color("font_disabled_color", type_name, Kit.DISABLED_TEXT)

	# list_box_item: dark rows, orange when hovered; the selected row stays orange.
	t.set_type_variation("FListItem", "Button")
	t.set_stylebox("normal", "FListItem", _list_style("normal", [208, 17]))
	t.set_stylebox("hover", "FListItem", _list_style("hover", [34, 17]))
	t.set_stylebox("pressed", "FListItem", _list_style("pressed", [51, 17]))
	t.set_stylebox("hover_pressed", "FListItem", _list_style("pressed", [51, 17]))
	t.set_stylebox("focus", "FListItem", StyleBoxEmpty.new())
	t.set_font("font", "FListItem", Kit.font("regular"))
	t.set_color("font_color", "FListItem", Kit.WHITE)
	t.set_color("font_focus_color", "FListItem", Kit.WHITE)
	for c in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "FListItem", Kit.BLACK)
	t.set_type_variation("FListItemSelected", "FListItem")
	t.set_stylebox("normal", "FListItemSelected", _list_style("pressed", [51, 17]))
	t.set_stylebox("hover", "FListItemSelected", _list_style("pressed", [51, 17]))
	t.set_color("font_color", "FListItemSelected", Kit.BLACK)
	t.set_color("font_focus_color", "FListItemSelected", Kit.BLACK)

	# main_menu_version_label: default-game (18, outlined).
	t.set_type_variation("FVersionLabel", "Label")
	t.set_font("font", "FVersionLabel", Kit.font("regular"))
	t.set_font_size("font_size", "FVersionLabel", Kit.px(16))
	t.set_color("font_color", "FVersionLabel", Kit.WHITE)
	t.set_color("font_outline_color", "FVersionLabel", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "FVersionLabel", Kit.px(4))

	# textbox: light field, black text.
	t.set_stylebox("normal", "LineEdit", _box([[248, 0]], Color8(220, 220, 220), 3, 2))
	t.set_stylebox("focus", "LineEdit", _box([[265, 0]], Color8(240, 240, 240), 3, 2))
	t.set_stylebox("read_only", "LineEdit", _box([[282, 0]], Color8(150, 150, 150), 3, 2))
	t.set_font("font", "LineEdit", Kit.font("regular"))
	t.set_font_size("font_size", "LineEdit", Kit.px(14))
	t.set_color("font_color", "LineEdit", Kit.BLACK)
	t.set_color("font_uneditable_color", "LineEdit", Color(0.2, 0.2, 0.2))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.35, 0.35, 0.35))
	t.set_color("caret_color", "LineEdit", Kit.BLACK)
	t.set_color("selection_color", "LineEdit", TEXTBOX_SELECTION)

	# checkbox: 14 px box (28 in the atlas), the checkmark over it.
	t.set_icon("unchecked", "CheckBox", _atlas_icon([[0, 132, 28, 28]], Color8(200, 200, 200)))
	t.set_icon("checked", "CheckBox", _atlas_icon([[0, 132, 28, 28], [112, 132, 28, 28]], Color8(255, 175, 0)))
	t.set_icon("unchecked_disabled", "CheckBox", _atlas_icon([[28, 132, 28, 28]], Color8(120, 120, 120)))
	t.set_icon("checked_disabled", "CheckBox", _atlas_icon([[28, 132, 28, 28], [456, 188, 28, 28]], Color8(120, 120, 120)))
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(s, "CheckBox", StyleBoxEmpty.new())
	t.set_font("font", "CheckBox", Kit.font("regular"))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckBox", Kit.WHITE)
	t.set_constant("h_separation", "CheckBox", Kit.px(8))

	# slider: the empty bar, the full (orange) part, the grey handle.
	t.set_stylebox("slider", "HSlider", _parts_box({"l": [56, 72, 8, 8], "c": [64, 72, 1, 8], "r": [65, 72, 8, 8]}, Color8(40, 40, 40), Kit.px(6)))
	t.set_stylebox("grabber_area", "HSlider", _box([[73, 72]], Color8(255, 175, 0), 0, 0, Kit.px(6)))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box([[73, 72]], Color8(255, 175, 0), 0, 0, Kit.px(6)))
	t.set_icon("grabber", "HSlider", _atlas_icon([[64, 48, 40, 24]], Color8(180, 180, 180)))
	t.set_icon("grabber_highlight", "HSlider", _atlas_icon([[144, 48, 40, 24]], Color8(255, 175, 0)))
	t.set_icon("grabber_disabled", "HSlider", _atlas_icon([[104, 48, 40, 24]], Color8(110, 110, 110)))

	# dropdown: a button with Factorio's arrow; its list is a dark panel of list items.
	t.set_font("font", "OptionButton", Kit.font("regular"))
	var arrow := GuiAssets.core_sprite("icons/mip/dropdown.png")
	if arrow != null:
		t.set_icon("arrow", "OptionButton", _scaled_icon(arrow, Kit.px(16)))
	t.set_constant("arrow_margin", "OptionButton", Kit.px(6))
	t.set_stylebox("panel", "PopupMenu", Kit.style("deep_slot_bg") if Kit.uses_atlas() else Kit.style("deep"))
	t.set_stylebox("hover", "PopupMenu", _list_style("hover", [34, 17]))
	t.set_font("font", "PopupMenu", Kit.font("regular"))
	t.set_font_size("font_size", "PopupMenu", Kit.px(14))
	t.set_color("font_color", "PopupMenu", Kit.WHITE)
	t.set_color("font_hover_color", "PopupMenu", Kit.BLACK)
	t.set_color("font_disabled_color", "PopupMenu", Kit.DISABLED_TEXT)
	t.set_constant("v_separation", "PopupMenu", Kit.px(8))
	t.set_constant("item_start_padding", "PopupMenu", Kit.px(8))
	t.set_constant("item_end_padding", "PopupMenu", Kit.px(8))

	# RichTextLabel for longer texts (instructions, errors).
	t.set_font("normal_font", "RichTextLabel", Kit.font("regular"))
	t.set_font("bold_font", "RichTextLabel", Kit.font("bold"))
	t.set_font_size("normal_font_size", "RichTextLabel", Kit.px(14))
	t.set_font_size("bold_font_size", "RichTextLabel", Kit.px(14))
	t.set_color("default_color", "RichTextLabel", Kit.WHITE)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())
	_theme = t
	return t


static func _list_style(state: String, at: Array) -> StyleBox:
	var f: Array = LIST_FLAT[state]
	var box := _box([at], f[0], 8, 0)
	box.content_margin_top = Kit.px(4)
	box.content_margin_bottom = Kit.px(4)
	return box


## Atlas 9-slices (corner 8) drawn over each other, or a flat box in `flat` without the atlas.
static func _box(ats: Array, flat: Color, pad_x: int, pad_y: int, height := 0) -> StyleBox:
	var box: StyleBox
	if Kit.uses_atlas():
		var layered := LayeredStyle.new()
		for at in ats:
			layered.layers.append(Kit._bake({"at": at, "corner": 8}))
		box = layered
	else:
		var f := StyleBoxFlat.new()
		f.bg_color = flat
		f.border_color = Color8(20, 20, 20)
		f.set_border_width_all(1)
		f.set_corner_radius_all(Kit.px(2))
		box = f
	box.content_margin_left = Kit.px(pad_x)
	box.content_margin_right = Kit.px(pad_x)
	box.content_margin_top = Kit.px(pad_y)
	box.content_margin_bottom = Kit.px(pad_y)
	if height > 0:
		box.content_margin_top = height / 2.0
		box.content_margin_bottom = height / 2.0
	return box


static func _parts_box(parts: Dictionary, flat: Color, height: int) -> StyleBox:
	var box: StyleBox
	if Kit.uses_atlas():
		var layered := LayeredStyle.new()
		layered.layers.append(Kit._bake({"parts": parts}))
		box = layered
	else:
		var f := StyleBoxFlat.new()
		f.bg_color = flat
		f.set_corner_radius_all(Kit.px(2))
		box = f
	box.content_margin_top = height / 2.0
	box.content_margin_bottom = height / 2.0
	return box


## Atlas pieces ([x, y, w, h], at the atlas' double size) stacked into one icon at the UI scale.
static func _atlas_icon(pieces: Array, flat: Color) -> Texture2D:
	var first: Array = pieces[0]
	var w := maxi(1, roundi(int(first[2]) * 0.5 * Kit.scale))
	var h := maxi(1, roundi(int(first[3]) * 0.5 * Kit.scale))
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var atlas := GuiAssets.atlas()
	if atlas == null:
		image.fill(flat)
		return ImageTexture.create_from_image(image)
	for p in pieces:
		var piece := atlas.get_region(Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])))
		piece.resize(w, h, Image.INTERPOLATE_LANCZOS)
		image.blend_rect(piece, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return ImageTexture.create_from_image(image)


static func _scaled_icon(texture: Texture2D, size: int) -> Texture2D:
	var image := texture.get_image()
	if image == null:
		return texture
	image = image.duplicate()
	image.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


# --- widgets ---------------------------------------------------------------------------------

static func menu_button(text: String, green := false) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "FMenuButtonGreen" if green else "FMenuButton"
	b.custom_minimum_size = Kit.pxv(320, 50)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func button(text: String, variation := "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = Kit.pxv(108, 28)
	b.focus_mode = Control.FOCUS_NONE
	return b


## A frame with Factorio's title bar; returns [frame, content VBox, close button or null].
static func window(title: String, closable := false) -> Array:
	var frame := Kit.panel("FFrame")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	frame.add_child(box)
	var bar := Kit.title_bar(title, closable)
	box.add_child(bar)
	var close: Button = bar.get_child(bar.get_child_count() - 1) if closable else null
	return [frame, box, close]


## Factorio's dialog button row: back (grey arrow left) on the left, the confirm button (green
## arrow right) on the right, a drag handle between. Returns [row, back, confirm]; either text ""
## leaves that button out.
static func dialog_buttons(back_text: String, confirm_text: String, red_back := false) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(8))
	var back: Button = null
	var confirm: Button = null
	if back_text != "":
		back = Button.new()
		back.text = back_text
		back.theme_type_variation = "FRedBackButton" if red_back else "FBackButton"
		back.custom_minimum_size = Kit.pxv(120, 32)
		back.focus_mode = Control.FOCUS_NONE
		row.add_child(back)
	var space := Kit.panel("FDraggable")
	space.custom_minimum_size.y = Kit.px(32)
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(space)
	if confirm_text != "":
		confirm = Button.new()
		confirm.text = confirm_text
		confirm.theme_type_variation = "FConfirmButton"
		confirm.custom_minimum_size = Kit.pxv(120, 32)
		confirm.focus_mode = Control.FOCUS_NONE
		row.add_child(confirm)
	return [row, back, confirm]


static func checkbox(text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	return c


static func slider(from: float, to: float, step: float, value: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = from
	s.max_value = to
	s.step = step
	s.value = value
	s.custom_minimum_size = Kit.pxv(200, 20)
	s.focus_mode = Control.FOCUS_NONE
	return s


## A dropdown of [label, value] pairs, the one with `value` selected.
static func dropdown(items: Array, value: Variant) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Kit.pxv(200, 28)
	for i in items.size():
		o.add_item(str(items[i][0]), i)
		o.set_item_metadata(i, items[i][1])
		if str(items[i][1]) == str(value):
			o.select(i)
	return o


static func textbox(text: String, placeholder := "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Kit.pxv(200, 28)
	return e


## A label that wraps, for explanations in dialogs.
static func paragraph(text: String, width := 460) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = Kit.px(width)
	return l


## A centred holder for a window over the whole screen, with a dark backdrop that takes the
## mouse (nothing behind it is clicked).
static func overlay(dim := 0.0) -> Control:
	var root := ColorRect.new()
	root.color = Color(0, 0, 0, dim)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	return root


## The CenterContainer inside an overlay(), where its window goes.
static func overlay_center(o: Control) -> Control:
	return o.get_child(0)
