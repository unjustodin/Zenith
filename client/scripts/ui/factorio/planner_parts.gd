extends RefCounted
## Pieces Factorio's planner windows share (blueprint, book, deconstruction and upgrade planner,
## the library), as the reference pictures in tools/ui_reference show them: the subheader with the
## record's name, its pencil and the tool buttons (copy, export, delete), the whitelist / blacklist
## switch, the list / grid view toggles, and the big rows books and the library list their
## records in.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const PlannerSlot := preload("res://scripts/ui/factorio/planner_slot.gd")

## The view toggles' icons (core/graphics/icons/mip): list, small grid, big grid.
const VIEWS := [["list", "list-view.png", "List view"], ["grid", "grid-view.png", "Small icons"],
	["slots", "slots-view.png", "Large icons"]]


## The subheader_frame heading a planner's half of the window: its name in bold, the pencil that
## turns it into a text box (Enter or leaving it renames: on_rename(text)), and the tool buttons
## added to "tools" on the right. Returns {"panel", "caption", "edit", "pencil", "tools"}.
static func subheader(title: String, on_rename: Callable) -> Dictionary:
	var panel := Kit.panel("FSubheader")
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", Kit.px(12))
	pad.add_theme_constant_override("margin_right", Kit.px(8))
	panel.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(6))
	row.custom_minimum_size.y = Kit.px(36)
	pad.add_child(row)
	var caption := Kit.label(title, "FHeading")
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)
	var edit := LineEdit.new()
	edit.name = "NameEdit"
	edit.visible = false
	edit.custom_minimum_size = Kit.pxv(220, 28)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(edit)
	var pencil := Button.new()
	pencil.name = "Rename"
	pencil.theme_type_variation = "FFrameAction"
	pencil.custom_minimum_size = Kit.pxv(16, 16)
	pencil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pencil.focus_mode = Control.FOCUS_NONE
	pencil.tooltip_text = "Edit name"
	var icon := GuiAssets.core_sprite("rename-icon.png")
	if icon != null:
		pencil.icon = icon
		pencil.expand_icon = true
		pencil.add_theme_constant_override("icon_max_width", Kit.px(14))
	else:
		pencil.text = "✎"
	row.add_child(pencil)
	var done := func() -> void:
		if not edit.visible:
			return
		edit.visible = false
		caption.visible = true
		pencil.visible = true
		on_rename.call(edit.text.strip_edges())
	pencil.pressed.connect(func() -> void:
		edit.text = str(edit.get_meta("label", ""))
		caption.visible = false
		pencil.visible = false
		edit.visible = true
		edit.grab_focus()
		edit.select_all())
	edit.text_submitted.connect(func(_t: String) -> void: done.call())
	edit.focus_exited.connect(done)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(space)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", Kit.px(4))
	row.add_child(tools)
	return {"panel": panel, "caption": caption, "edit": edit, "pencil": pencil, "tools": tools}


## Sets a subheader's shown name and the text its pencil starts editing from.
static func show_name(sub: Dictionary, shown: String, label: String) -> void:
	(sub["caption"] as Label).text = shown
	(sub["edit"] as LineEdit).set_meta("label", label)


## tool_button (28x28, a core icon) in grey, red (delete) or green (select new).
static func tool_button(icon_file: String, tip: String, variation := "Button") -> Button:
	var b := Button.new()
	b.theme_type_variation = variation
	b.custom_minimum_size = Kit.pxv(28, 28)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	var icon := GuiAssets.core_sprite(icon_file if icon_file.contains("/") or icon_file == "export.png" or icon_file == "import.png" else "icons/mip/" + icon_file)
	if icon != null:
		b.icon = icon
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", Kit.px(20))
		if variation != "Button":
			b.add_theme_color_override("icon_normal_color", Kit.WHITE)
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.45))
	return b


## The header's buttons, in Factorio's order. kind "blueprint": select new contents (blue), copy,
## upgrade (green), parametrise (green), export, delete; "book": copy, upgrade, export, delete;
## planners: copy, export, delete. Returns them by name: "reselect", "copy", "upgrade",
## "parametrise", "export", "delete".
static func header_tools(tools: HBoxContainer, kind: String) -> Dictionary:
	var out := {}
	var add := func(key: String, icon: String, tip: String, variation: String) -> void:
		var b := tool_button(icon, tip, variation)
		b.name = key.capitalize().replace(" ", "") + "Button"
		tools.add_child(b)
		out[key] = b
	if kind == "blueprint":
		add.call("reselect", "reassign.png", "Select new contents for the blueprint.", "FBluePageButton")
	add.call("copy", "copy.png", "Create copy of this", "Button")
	if kind == "blueprint" or kind == "book":
		add.call("upgrade", "upgrade-blueprint.png", "Upgrade items and entities in the blueprint." if kind == "blueprint"
			else "Upgrade items and entities in all blueprints in this book.", "FGreenPageButton")
	if kind == "blueprint":
		add.call("parametrise", "icons/parametrise.png", "Parametrise/reconfigure the blueprint.", "FGreenPageButton")
	add.call("export", "export.png", "Export to string", "Button")
	add.call("delete", "trash.png", "Delete", "FRedButton")
	return out


## The standard copy / export / delete trio: returns [copy, export, delete] after adding them.
static func record_tools(tools: HBoxContainer) -> Array:
	var out: Array = []
	var copy := tool_button("copy.png", "Copy")
	copy.name = "CopyButton"
	tools.add_child(copy)
	out.append(copy)
	var export := tool_button("export.png", "Export to string")
	export.name = "ExportButton"
	tools.add_child(export)
	out.append(export)
	var delete := tool_button("trash.png", "Delete", "FRedButton")
	delete.name = "DeleteButton"
	tools.add_child(delete)
	out.append(delete)
	return out


## Factorio's switch: two labels with a sliding knob between them; the chosen side's label is
## orange. on_change(right: bool). Clicking either label or the knob picks a side.
static func switch(left: String, right: String, right_on: bool, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(6))
	var l := _switch_label(left, not right_on)
	var r := _switch_label(right, right_on)
	var knob := SwitchKnob.new()
	knob.right = right_on
	knob.custom_minimum_size = Kit.pxv(30, 16)
	knob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.name = left
	r.name = right
	knob.name = "Switch"
	l.pressed.connect(func() -> void:
		if right_on:
			on_change.call(false))
	r.pressed.connect(func() -> void:
		if not right_on:
			on_change.call(true))
	knob.pressed.connect(func() -> void: on_change.call(not right_on))
	row.add_child(l)
	row.add_child(knob)
	row.add_child(r)
	return row


static func _switch_label(text: String, on: bool) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Kit.font("bold" if on else "regular"))
	var color := Kit.ORANGE if on else Kit.WHITE
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, color)
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	return b


## The knob of switch(): a dark rounded track with a light knob on the chosen side.
class SwitchKnob extends Button:
	var right := false

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())

	func _draw() -> void:
		var h := size.y
		var track := StyleBoxFlat.new()
		track.bg_color = Color8(32, 32, 32)
		track.border_color = Color8(20, 20, 20)
		track.set_border_width_all(1)
		track.set_corner_radius_all(int(h * 0.5))
		draw_style_box(track, Rect2(Vector2.ZERO, size))
		var knob := StyleBoxFlat.new()
		knob.bg_color = Color8(200, 200, 200) if not is_hovered() else Color8(255, 220, 160)
		knob.set_corner_radius_all(int(h * 0.5))
		var w := h * 1.1
		draw_style_box(knob, Rect2(Vector2(size.x - w if right else 0.0, 0), Vector2(w, h)).grow(-1))


## The list / small grid / large grid toggles; on_pick(view) gets "list", "grid" or "slots".
static func view_toggles(current: String, on_pick: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(4))
	for v in VIEWS:
		var b := tool_button(str(v[1]), str(v[2]))
		b.name = "View_" + str(v[0])
		if v[0] == current:
			b.add_theme_stylebox_override("normal", Kit.style("button_selected"))
			b.add_theme_stylebox_override("hover", Kit.style("button_selected"))
		var view: String = v[0]
		b.pressed.connect(func() -> void: on_pick.call(view))
		row.add_child(b)
	return row


## A row of the list view: the record's big picture and its name (bold) beside it, as Factorio's
## book and library list them. Returns [row, slot].
static func list_row(slot_size := 74) -> Array:
	# Factorio's rows (blueprint_library at 100%): 92 apart, the 74 slot 8 in, the name in bold at
	# the slot's top, a light line between rows.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", Kit.px(4))
	pad.add_theme_constant_override("margin_top", Kit.px(8))
	pad.add_theme_constant_override("margin_bottom", Kit.px(9))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(6))
	pad.add_child(row)
	var s := PlannerSlot.new()
	s.theme_type_variation = "FSlotButton"
	s.big = true
	s.custom_minimum_size = Kit.pxv(slot_size, slot_size)
	row.add_child(s)
	var name := Kit.label("", "FHeading")
	name.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	name.add_theme_color_override("font_color", Kit.WHITE)
	row.add_child(name)
	return [pad, s, name]


## A thin light line between list rows.
static func separator() -> Control:
	var line := ColorRect.new()
	line.color = Color8(88, 87, 88)
	line.custom_minimum_size.y = maxf(1.0, Kit.px(1))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Factorio's striped filler under a list or grid that doesn't fill its frame.
static func filler(rows: int, columns := Kit.COLUMNS) -> Control:
	var g := Kit.slot_grid(columns)
	for i in rows * columns:
		var c := Kit.empty_cell()
		c.modulate = Color(1, 1, 1, 0.35)
		g.add_child(c)
	return g


## Factorio's faint striped rows filling a deep frame below its content (`rows` slot rows high).
static func stripes(rows: int) -> Control:
	var s := Stripes.new()
	s.custom_minimum_size.y = Kit.px(Kit.SLOT) * maxi(rows, 0)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


class Stripes extends Control:
	func _draw() -> void:
		var h := float(Kit.px(Kit.SLOT))
		var y := 0.0
		var i := 0
		while y < size.y:
			draw_rect(Rect2(0, y, size.x, minf(h, size.y - y)), Color(1, 1, 1, 0.025 if i % 2 == 0 else 0.0))
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.25))
			y += h
			i += 1
