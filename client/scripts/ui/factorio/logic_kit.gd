extends RefCounted
## Small pieces Factorio's logistics, circuit, train and vehicle windows share, cut from the GUI
## atlas and laid out with style.lua's numbers: the switch, the notched slider with its number box,
## the thin divider line, the dark subheader strip, labels with the blue (i) info icon, tool buttons
## (pencil, eyedropper, trash), the "Connected to: 7" network line, the small R / G wire checkboxes
## and the 10-wide signal strips of the combinators.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const Switch := preload("res://scripts/ui/factorio/switch.gd")
const NotchedSlider := preload("res://scripts/ui/factorio/notched_slider.gd")

const RED_WIRE := Color(1, 0.45, 0.45)
const GREEN_WIRE := Color(0.45, 1, 0.45)
## Factorio's network id colours in "Connected to:" (red and green wire).
const RED_ID := Color8(255, 88, 88)
const GREEN_ID := Color8(92, 210, 92)
## The orange of a bold active label (switch active_label, "Automatic", "Sort descending").
const ACTIVE := Color8(241, 190, 100)


static func switch(left_text: String, right_text: String, current: String, on_switch := Callable()) -> Switch:
	var s := Switch.new()
	s.left_label.text = left_text
	s.right_label.text = right_text
	s.set_state(current)
	if on_switch.is_valid():
		s.switched.connect(on_switch)
	return s


static func notched(from: int, to: int, current: int, on: bool, on_commit := Callable()) -> NotchedSlider:
	var s := NotchedSlider.new()
	s.setup(from, to, current, on)
	if on_commit.is_valid():
		s.committed.connect(on_commit)
	return s


## Factorio's line style: a thin dark-over-light groove across the panel.
static func line() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = Kit.px(4)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var draw := func() -> void:
		var tex := Switch._atlas()
		var r := Rect2(0, 0, c.size.x, Kit.px(4))
		if tex != null:
			c.draw_texture_rect_region(tex, r, Rect2(8, 40, 1, 8))
		else:
			c.draw_rect(Rect2(0, 1, c.size.x, 1), Color8(20, 20, 20))
			c.draw_rect(Rect2(0, 2, c.size.x, 1), Color8(80, 80, 80))
	c.draw.connect(draw)
	return c


## subheader_frame: the dark strip across a panel's top. Returns [frame, its row].
static func subheader() -> Array:
	var frame := Kit.panel("FSubheader")
	frame.custom_minimum_size.y = Kit.px(36)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", Kit.px(8))
	m.add_theme_constant_override("margin_right", Kit.px(4))
	frame.add_child(m)
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", Kit.px(6))
	r.alignment = BoxContainer.ALIGNMENT_BEGIN
	m.add_child(r)
	return [frame, r]


## The blue (i) after a label; hovering it shows `tip`.
static func info_icon(tip: String) -> Control:
	var t := TextureRect.new()
	t.texture = GuiAssets.core_sprite("icons/mip/info-blue.png")
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Kit.pxv(12, 12)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.texture_filter = Kit.ICON_FILTER
	t.tooltip_text = tip
	t.mouse_filter = Control.MOUSE_FILTER_STOP
	if t.texture == null:
		var l := Kit.label("ⓘ")
		l.add_theme_color_override("font_color", Color8(110, 170, 255))
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		return l
	return t


## A label followed by the (i) icon.
static func info_label(text: String, tip: String, variation := "") -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", Kit.px(4))
	var l := Kit.label(text, variation)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r.add_child(l)
	r.add_child(info_icon(tip))
	return r


## A checkbox whose label has the (i) icon after it ("Spoiled priority (i)").
static func info_checkbox(text: String, tip: String, on: bool, on_toggle: Callable) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", Kit.px(4))
	var c := MenuKit.checkbox(text, on)
	c.toggled.connect(on_toggle)
	r.add_child(c)
	r.add_child(info_icon(tip))
	return r


## tool_button: a 28 x 28 grey button with an icon (pencil, eyedropper, map). `sprite` is a path
## under core/graphics.
static func tool_button(sprite: String, tip: String, on_press := Callable(), variation := "") -> Button:
	var b := Button.new()
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = Kit.pxv(28, 28)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var icon := GuiAssets.core_sprite(sprite)
	if icon != null:
		# Drawn over the button with style.lua's padding of 2: the plain button's own padding of 8
		# would leave a 28-pixel tool button no room for its icon.
		b.add_child(_icon_over(icon, 2))
	else:
		b.text = tip.substr(0, 1)
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func _icon_over(icon: Texture2D, pad: int) -> TextureRect:
	var t := TextureRect.new()
	t.name = "Icon"
	t.texture = icon
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = Kit.ICON_FILTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["offset_left", "offset_top"]:
		t.set(side, Kit.px(pad))
	for side in ["offset_right", "offset_bottom"]:
		t.set(side, -Kit.px(pad))
	return t


## mini_button with the rename pencil, as after a train or section name.
static func rename_button(tip: String, on_press: Callable) -> Button:
	var b := tool_button("rename-icon.png", tip, on_press)
	b.custom_minimum_size = Kit.pxv(16, 16)
	var icon := b.get_node_or_null("Icon") as TextureRect
	if icon != null:
		for side in ["offset_left", "offset_top"]:
			icon.set(side, Kit.px(1))
		for side in ["offset_right", "offset_bottom"]:
			icon.set(side, -Kit.px(1))
	return b


## A frame_action_button for a title bar (circuit network, logistic network); toggled is the
## orange look Factorio gives it while its side window is open.
static func frame_button(sprite: String, tip: String, on: bool) -> Button:
	var b := Button.new()
	b.theme_type_variation = "FFrameAction"
	b.custom_minimum_size = Kit.pxv(24, 24)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.toggle_mode = true
	b.button_pressed = on
	b.add_theme_stylebox_override("pressed", Kit.style("frame_action_pressed"))
	var icon := GuiAssets.core_sprite(sprite)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", Kit.px(18))
		b.add_theme_color_override("icon_pressed_color", Kit.BLACK)
		b.add_theme_color_override("icon_hover_color", Kit.BLACK)
	return b


## Factorio's two small wire checkboxes stacked: R over G. `sel` is a CircuitNetworkSelection
## ({red, green}, both on by default); on_change gets the new one. Without on_change they only
## show which wires are connected (greyed).
static func wire_checks(sel, on_change := Callable(), vertical := true) -> BoxContainer:
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var s: Dictionary = sel if sel is Dictionary else {}
	for wire in [["red", "R"], ["green", "G"]]:
		var key: String = wire[0]
		var on := bool(s.get(key, true))
		var c := MenuKit.checkbox(str(wire[1]), on)
		c.name = "Net" + str(wire[1])
		c.add_theme_font_size_override("font_size", Kit.px(13))
		c.add_theme_constant_override("h_separation", Kit.px(4))
		for col in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			c.add_theme_color_override(col, Kit.DISABLED_TEXT)
		c.tooltip_text = "Read the %s network" % key
		if on_change.is_valid():
			var flip := func(v: bool) -> void:
				var n := {"red": bool(s.get("red", true)), "green": bool(s.get("green", true))}
				n[key] = v
				on_change.call(n)
			c.toggled.connect(flip)
		else:
			c.disabled = true
		box.add_child(c)
	return box


## "Input: Connected to: 7 (i)" / "Not connected": the network ids of one side, each in its wire's
## colour. `nets` is {r, g} (or {ri, gi}); prefix "" leaves the "Input:" part out.
static func connected_line(prefix: String, nets) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", Kit.px(4))
	if prefix != "":
		var p := Kit.label(prefix + ":", "FHeading")
		r.add_child(p)
	var ids: Array = []
	if nets is Dictionary:
		for wire in [["r", RED_ID], ["g", GREEN_ID]]:
			# gui.cc.nets has {r, g}; gui.sig has the lists in r / g and the ids in ri / gi.
			var v = nets.get(str(wire[0]) + "i", nets.get(wire[0], 0))
			var id := int(v) if (v is int or v is float) else 0
			if id > 0:
				ids.append([id, wire[1]])
	if ids.is_empty():
		r.add_child(Kit.label("Not connected"))
		return r
	r.add_child(Kit.label("Connected to:"))
	for pair in ids:
		var l := Kit.label(str(pair[0]))
		l.add_theme_color_override("font_color", pair[1])
		r.add_child(l)
	r.add_child(info_icon("The id of the circuit network this side is connected to"))
	return r


## A combinator's signal strip: a deep frame of 10-wide rows, each signal on its wire's colour
## (green or red slot), the rest empty recesses. list: [[type, name, count, wire?], ...].
static func signal_strip(list: Array, columns := 10, rows := 1, name := "") -> Control:
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if name != "":
		frame.name = name
	var grid := Kit.slot_grid(columns)
	frame.add_child(grid)
	var cells := 0
	for s in list:
		if not (s is Array) or s.size() < 3:
			continue
		var slot := Slot.new()
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.theme_type_variation = "FRedSlotButton" if s.size() >= 4 and str(s[3]) == "r" else "FGreenSlot"
		slot.set_stack(str(s[1]), -1)
		slot.set_tip(Kit.pretty(str(s[1])), [["%d" % int(s[2])]])
		slot.add_child(_count_label(int(s[2])))
		grid.add_child(slot)
		cells += 1
	var target := maxi(rows * columns, ceili(cells / float(columns)) * columns)
	while cells < target:
		grid.add_child(Kit.empty_cell())
		cells += 1
	return frame


## A signal's count in a slot's corner, negative ones too (slot.gd draws only counts from 0).
static func _count_label(n: int) -> Label:
	var l := Kit.label(("-" if n < 0 else "") + Kit.count_text(absi(n)))
	l.add_theme_font_override("font", Kit.font("bold"))
	l.add_theme_font_size_override("font_size", Kit.px(13))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", Kit.px(3))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_right = -Kit.px(3)
	l.offset_bottom = Kit.px(1)
	return l


## A panel's padded column: inside_shallow_frame's 12 / 8 padding.
static func padded(content: Control, h := 12, v := 8) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, Kit.px(h))
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, Kit.px(v))
	m.add_child(content)
	return m


## A grey label for what is shown but can't be changed here.
static func grey(text: String) -> Label:
	var l := Kit.label(text)
	l.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	return l


## A row pushed to the right: an expanding spacer then `child`.
static func push_right(row: Container, child: Control) -> void:
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(space)
	row.add_child(child)


## A long grey button across the panel ("+ Add station", "Add section", "Add description").
static func wide_button(text: String, on_press: Callable, width := 0) -> Button:
	var b := MenuKit.button(text)
	b.custom_minimum_size = Kit.pxv(width, 28)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if text.begins_with("+") else HORIZONTAL_ALIGNMENT_CENTER
	if width == 0:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	return b


# --- pieces of entity windows (take the machine screen) ----------------------------------------

## A row of one inventory's slots (no heading, no frame), with Factorio's faint placeholder icon in
## the empty ones; clicks go to machine_screen.gd like every slot's.
static func slot_row(screen, role: String, empty_icon := "", min_slots := 0) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 0)
	r.name = "Slots_" + role
	var stacks: Array = screen._slot_list(role)
	var exact: bool = screen.knows_slots(role)
	var icon: Texture2D = GuiAssets.core_sprite(empty_icon) if empty_icon != "" else null
	var n := maxi(stacks.size(), min_slots)
	for i in n:
		var stack: Dictionary = stacks[i] if i < stacks.size() else {}
		var s: Slot = screen._stack_slot(role, i + 1 if exact else 0, stack)
		if stack.is_empty() and icon != null:
			s.empty_icon = icon
		r.add_child(s)
	return r


## The fuel slots and the red bar of what is burning, as a burner's window starts.
static func fuel_row(screen, role := "fuel") -> HBoxContainer:
	var r := slot_row(screen, role, "icons/mip/empty-fuel-slot.png", 1)
	r.add_theme_constant_override("separation", Kit.px(0))
	var gap := Control.new()
	gap.custom_minimum_size.x = Kit.px(8)
	r.add_child(gap)
	var bar := Kit.progress_bar(Color8(230, 60, 40))
	bar.max_value = 1000
	bar.value = int(screen._last.get("bu", 0))
	bar.custom_minimum_size = Kit.pxv(160, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = "Fuel burning"
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.name = "BurnerBar"
	r.add_child(bar)
	var bars: Array = screen.get_meta("burner_bars") if screen.has_meta("burner_bars") else []
	bars.append(bar)
	screen.set_meta("burner_bars", bars)
	return r


## The colour button pair Factorio puts at the right of a lamp's status line (and a train stop's
## or locomotive's header): the eyedropper and the swatch, both opening the colour picker.
static func color_buttons(screen, col) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", Kit.px(4))
	var picker := ColorPickerButton.new()
	picker.name = "ColorPicker"
	picker.color = _color(col)
	picker.edit_alpha = false
	picker.focus_mode = Control.FOCUS_NONE
	picker.custom_minimum_size = Kit.pxv(28, 28)
	picker.tooltip_text = "Color"
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0, 0, 0, 0)
	flat.set_border_width_all(Kit.px(1))
	flat.border_color = Color8(20, 20, 20)
	for state in ["normal", "hover", "pressed", "focus"]:
		picker.add_theme_stylebox_override(state, flat)
	picker.popup_closed.connect(func() -> void: screen.model.set_color(screen.unit, [picker.color.r8, picker.color.g8, picker.color.b8]))
	var dropper := tool_button("icons/mip/color-picker.png", "Pick a color", func() -> void: picker.get_popup().popup_centered())
	dropper.name = "EyeDropper"
	r.add_child(dropper)
	r.add_child(picker)
	return r


## The "Not connected" / "Connected to: 5" strip over a window that is part of the circuit network.
static func network_header(last: Dictionary) -> Control:
	var sh := subheader()
	var cc = last.get("cc")
	var nets = cc.get("nets") if cc is Dictionary else null
	(sh[1] as HBoxContainer).add_child(connected_line("", nets))
	return bleed(sh[0])


## A strip across the whole of the panel it sits in (past inside_shallow_frame's padding).
static func bleed(strip: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", -Kit.px(12))
	m.add_theme_constant_override("margin_right", -Kit.px(12))
	m.add_theme_constant_override("margin_top", -Kit.px(8))
	m.add_child(strip)
	m.name = "Subheader"
	return m


static func _color(c) -> Color:
	if c is Array and (c as Array).size() >= 3:
		return Color8(int(c[0]), int(c[1]), int(c[2]))
	return Color.WHITE
