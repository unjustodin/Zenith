extends PanelContainer
## Factorio's blueprint window ("Blueprint item"), for a blueprint in the inventory, the cursor, the
## library or a book's page, laid out as tools/ui_reference's `blueprint` picture: a frame the
## height of the screen with, on the left, the subheader (name with its pencil; select new contents,
## copy, upgrade, parametrise, export, delete), the Icon row (the blueprint's picture and its four
## icon slots), Description, Snap to grid (grid size, grid position, absolute or relative) and
## Components (click one to take every one of it out); on the right, the Preview (right click an
## entity to remove it, left click to restore it, as in Factorio); and "Save blueprint" at the
## bottom right. Nothing changes until Save, as in Factorio.
## Books have their own window (book_window.gd), joined to the inventory.
## The records are the decoded exchange strings (bp_string.gd).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const BpString := preload("res://scripts/ui/factorio/bp_string.gd")
const PlannerSlot := preload("res://scripts/ui/factorio/planner_slot.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const Parts := preload("res://scripts/ui/factorio/planner_parts.gd")
const SpriteProjection := preload("res://scripts/world/sprite_projection.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
## Belts have no sheet in sprite_projection.json: their own animation sheet's first frames (rows
## east, west, north, south; a 128 px frame is 2 tiles).
const BELT_SHEETS := {"transport-belt": "base", "fast-transport-belt": "base", "express-transport-belt": "base",
	"turbo-transport-belt": "space-age"}

signal close_requested
signal saved(record: Dictionary, source: Dictionary)
signal deleted(source: Dictionary)
## Shows the exchange string of this record (the coordinator puts it in the import/export box).
signal export_requested(record: Dictionary)
signal add_to_library(record: Dictionary)
## The copy button: a copy of the blueprint into the cursor.
signal copy_requested(record: Dictionary)
## Select new contents: the blueprint goes into the cursor to select an area for it.
signal reselect_requested(record: Dictionary, source: Dictionary)
## Upgrade items and entities: the coordinator finds an upgrade planner and calls apply_upgrade.
signal upgrade_requested
## The left column's width and the frame's at 100% (the picture: 1540 x the screen's height).
const LEFT_WIDTH := 430
const FRAME_WIDTH := 1540

var picker  # item_picker.gd: the icons' chooser
var protos  # proto_db.gd: footprints and colours for the preview (optional)
## The record being edited and where it came from ({"kind": "slot", "slot"}, {"kind": "library",
## "path"}, {"kind": "game"/"player", "ix"} or {"kind": "page", "page"} for a book's page).
var record := {}
var source := {}
## Entities removed in the preview (right click), by entity_number.
var removed := {}

var _title: Label
var _sub := {}
var _icon_big: PlannerSlot
var _icons: Array = []
var _description: TextEdit
var _left := VBoxContainer.new()
var _body := VBoxContainer.new()
var _preview: Preview
var _delete: Button


func _ready() -> void:
	theme_type_variation = "FFrame"
	theme = EntityPanels.theme()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	visible = false
	z_index = 5
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Blueprint item", true)
	_title = bar.get_child(0)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: close_requested.emit())
	box.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(12))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	# The left column: inside_shallow_frame with the subheader and the settings.
	var left_frame := Kit.panel("FShallowFrame")
	left_frame.custom_minimum_size.x = Kit.px(LEFT_WIDTH)
	row.add_child(left_frame)
	_left.add_theme_constant_override("separation", 0)
	left_frame.add_child(_left)
	_sub = Parts.subheader("Blueprint", func(t: String) -> void:
		_set_label(t)
		_show())
	_left.add_child(_sub["panel"])
	var tools: Dictionary = Parts.header_tools(_sub["tools"], "blueprint")
	(tools["reselect"] as Button).pressed.connect(func() -> void: reselect_requested.emit(result(), source))
	(tools["copy"] as Button).pressed.connect(func() -> void: copy_requested.emit(result()))
	(tools["upgrade"] as Button).pressed.connect(func() -> void: upgrade_requested.emit())
	# Factorio's parametrisation has no script API in 2.1 (no blueprint parameter methods on
	# LuaItemStack), so the button is there but can't be used.
	(tools["parametrise"] as Button).disabled = true
	(tools["parametrise"] as Button).tooltip_text = "Parametrise/reconfigure the blueprint.\nNot available here: Factorio 2.1 gives scripts no access to blueprint parameters."
	(tools["export"] as Button).pressed.connect(func() -> void: export_requested.emit(result()))
	_delete = tools["delete"]
	_delete.pressed.connect(func() -> void:
		deleted.emit(source)
		close_requested.emit())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	_left.add_child(scroll)
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", Kit.px(4))
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(settings)

	# Icon: the blueprint's picture, then its four icon slots.
	var icon_box := _section(settings, "Icon")
	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", Kit.px(8))
	_icon_big = PlannerSlot.new()
	_icon_big.theme_type_variation = "FSlotButton"
	_icon_big.big = true
	_icon_big.custom_minimum_size = Kit.pxv(64, 64)
	_icon_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_child(_icon_big)
	var icon_slots := Kit.panel("FDeepFrame")
	icon_slots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_grid := Kit.slot_grid(4)
	icon_slots.add_child(icon_grid)
	for i in 4:
		var s := Slot.new()
		s.theme_type_variation = "FSlotButton"
		s.name = "Icon%d" % (i + 1)
		s.set_tip("Icon %d" % (i + 1), [["Click: choose · Right click: clear", "", Kit.DISABLED_TEXT]])
		var n := i
		s.clicked.connect(func(button_index: int, _shift: bool) -> void: _icon_clicked(n, button_index))
		_icons.append(s)
		icon_grid.add_child(s)
	icon_row.add_child(icon_slots)
	icon_box.add_child(icon_row)

	var desc_box := _section(settings, "Description")
	_description = TextEdit.new()
	_description.name = "Description"
	_description.custom_minimum_size = Kit.pxv(LEFT_WIDTH - 32, 116)
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.text_changed.connect(func() -> void: BpString.set_description(record, _description.text))
	desc_box.add_child(_description)
	_body.add_theme_constant_override("separation", Kit.px(4))
	settings.add_child(_body)

	# The preview, right.
	var right := Kit.panel("FDeepFrame")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var right_box := VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 0)
	right.add_child(right_box)
	var head := Kit.panel("FSubheader")
	var head_row := HBoxContainer.new()
	head_row.custom_minimum_size.y = Kit.px(36)
	var head_pad := MarginContainer.new()
	head_pad.add_theme_constant_override("margin_left", Kit.px(12))
	head_pad.add_theme_constant_override("margin_right", Kit.px(12))
	head_pad.add_child(head_row)
	head.add_child(head_pad)
	var preview_title := Kit.label("Preview", "FHeading")
	preview_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head_row.add_child(preview_title)
	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.scroll_active = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.text = "[color=#80cef0]Right-click[/color] to remove, [color=#80cef0]Left-click[/color] to restore."
	head_row.add_child(hint)
	right_box.add_child(head)
	_preview = Preview.new()
	_preview.name = "Preview"
	_preview.window = self
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.add_child(_preview)

	# The bottom bar: Save blueprint.
	var bottom := HBoxContainer.new()
	var filler := Kit.panel("FDraggable")
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filler.custom_minimum_size.y = Kit.px(36)
	bottom.add_child(filler)
	var save := Button.new()
	save.name = "Save"
	save.theme_type_variation = "FConfirmButton"
	save.text = "Save blueprint"
	save.focus_mode = Control.FOCUS_NONE
	save.custom_minimum_size = Kit.pxv(150, 36)
	save.pressed.connect(_on_save)
	bottom.add_child(save)
	box.add_child(bottom)
	get_viewport().size_changed.connect(_fit)


## The frame fills the screen's height, as Factorio's.
func _fit() -> void:
	var vs := get_viewport_rect().size
	custom_minimum_size = Vector2(minf(Kit.px(FRAME_WIDTH), vs.x - Kit.px(16)), vs.y)
	size = custom_minimum_size
	position = ((vs - size) * 0.5).floor()


## A section of the left column: its bold heading with Factorio's (i), the content under it.
func _section(parent: Control, heading: String, info := true) -> VBoxContainer:
	var frame := Kit.panel("FShallowFrame")
	var pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, Kit.px(12 if s != "top" else 8))
	frame.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(6))
	pad.add_child(col)
	var l := Kit.label(heading + (" ⓘ" if info else ""), "FHeading")
	col.add_child(l)
	parent.add_child(frame)
	return col


func is_open() -> bool:
	return visible


## Opens a blueprint record (a copy: nothing changes until Save).
func edit(r: Dictionary, from: Dictionary) -> void:
	record = r.duplicate(true)
	source = from
	removed = {}
	visible = true
	_fit()
	_show()


func close() -> void:
	visible = false
	_description.release_focus()


## The record as it would be saved: the preview's removals applied.
func result() -> Dictionary:
	var out := record.duplicate(true)
	if BpString.kind(out) != "blueprint":
		return out
	var b := BpString.body(out)
	if not removed.is_empty() and b.get("entities") is Array:
		b["entities"] = (b["entities"] as Array).filter(func(e) -> bool:
			return not (e is Dictionary and removed.has(int(e.get("entity_number", 0)))))
		if b.get("wires") is Array:
			b["wires"] = (b["wires"] as Array).filter(func(w) -> bool:
				return w is Array and w.size() >= 4 and not removed.has(int(w[0])) and not removed.has(int(w[2])))
	return out


func _show() -> void:
	_title.text = "Blueprint item"
	var label := BpString.label(record)
	Parts.show_name(_sub, label if label != "" else "Blueprint", label)
	if str(_description.text) != BpString.description(record):
		_description.text = BpString.description(record)
	_icon_big.set_record(record)
	var icons := BpString.icons(record)
	for i in 4:
		var s: Slot = _icons[i]
		s.set_stack(str(icons[i][1]) if i < icons.size() else "", -1)
	_delete.disabled = not (str(source.get("kind", "")) in ["library", "slot"])
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_show_snapping()
	_show_components()
	_preview.queue_redraw()


func _show_components() -> void:
	var col := _section(_body, "Components")
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var grid := Kit.slot_grid()
	grid.name = "Components"
	frame.add_child(grid)
	var cells := 0
	for c in BpString.components(result()):
		var s := Slot.new()
		s.theme_type_variation = "FSlotButton"
		s.set_stack(str(c[0]), int(c[1]))
		s.set_tip(Kit.entity_name(str(c[0])) if c[2] == "entity" else Kit.pretty(str(c[0])),
			[["%d in the blueprint" % int(c[1])], ["Click: remove them all", "", Kit.DISABLED_TEXT]])
		var name := str(c[0])
		var what := str(c[2])
		s.clicked.connect(func(button_index: int, _shift: bool) -> void:
			if button_index == MOUSE_BUTTON_LEFT:
				BpString.remove_component(record, name, what)
				_show())
		grid.add_child(s)
		cells += 1
	while cells == 0 or cells % Kit.COLUMNS != 0:
		grid.add_child(Kit.empty_cell())
		cells += 1
	col.add_child(frame)


func _show_snapping() -> void:
	var b := BpString.body(record)
	var snap = b.get("snap-to-grid")
	var rel = b.get("position-relative-to-grid")
	var frame := Kit.panel("FShallowFrame")
	var pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, Kit.px(12 if s != "top" else 8))
	frame.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(6))
	pad.add_child(col)
	_body.add_child(frame)
	var snap_on := MenuKit.checkbox("Snap to grid", snap is Dictionary)
	snap_on.name = "SnapToGrid"
	snap_on.add_theme_font_override("font", Kit.font("bold"))
	col.add_child(snap_on)
	var sx := _number("SnapX", int(snap.get("x", 1)) if snap is Dictionary else 1)
	var sy := _number("SnapY", int(snap.get("y", 1)) if snap is Dictionary else 1)
	col.add_child(_field_row("Grid size ⓘ", "Width:", sx, "Height:", sy))
	# Factorio's "Grid position" moves the blueprint inside its grid cell; the string has no key for
	# it (it moves the entities), so it is shown but not editable here.
	var gx := _number("GridX", 0)
	var gy := _number("GridY", 0)
	gx.editable = false
	gy.editable = false
	col.add_child(_field_row("Grid position ⓘ", "X:", gx, "Y:", gy))
	var group := ButtonGroup.new()
	var abs_on := CheckBox.new()
	abs_on.text = "Absolute ⓘ"
	abs_on.name = "AbsoluteSnapping"
	abs_on.button_group = group
	abs_on.focus_mode = Control.FOCUS_NONE
	abs_on.button_pressed = bool(b.get("absolute-snapping", false))
	var rel_on := CheckBox.new()
	rel_on.text = "Relative ⓘ"
	rel_on.name = "RelativeSnapping"
	rel_on.button_group = group
	rel_on.focus_mode = Control.FOCUS_NONE
	rel_on.button_pressed = not abs_on.button_pressed
	var ox := _number("OffsetX", int(rel.get("x", 0)) if rel is Dictionary else 0)
	var oy := _number("OffsetY", int(rel.get("y", 0)) if rel is Dictionary else 0)
	col.add_child(_field_row("", "X:", ox, "Y:", oy, abs_on))
	col.add_child(rel_on)
	var apply := func() -> void:
		if snap_on.button_pressed:
			b["snap-to-grid"] = {"x": maxi(1, int(sx.text)), "y": maxi(1, int(sy.text))}
		else:
			b.erase("snap-to-grid")
		if snap_on.button_pressed and abs_on.button_pressed:
			b["absolute-snapping"] = true
			if int(ox.text) != 0 or int(oy.text) != 0:
				b["position-relative-to-grid"] = {"x": int(ox.text), "y": int(oy.text)}
			else:
				b.erase("position-relative-to-grid")
		else:
			b.erase("absolute-snapping")
			b.erase("position-relative-to-grid")
		for c in [abs_on, rel_on]:
			c.disabled = not snap_on.button_pressed
		for f in [sx, sy]:
			f.editable = snap_on.button_pressed
		for f in [ox, oy]:
			f.editable = snap_on.button_pressed and abs_on.button_pressed
	snap_on.toggled.connect(func(_on: bool) -> void: apply.call())
	abs_on.toggled.connect(func(_on: bool) -> void: apply.call())
	for f in [sx, sy, ox, oy]:
		f.text_changed.connect(func(_t: String) -> void: apply.call())
	for c in [abs_on, rel_on]:
		c.disabled = not snap_on.button_pressed
	for f in [sx, sy]:
		f.editable = snap_on.button_pressed
	for f in [ox, oy]:
		f.editable = snap_on.button_pressed and abs_on.button_pressed


## A row of the snapping settings: its name (or a radio button) on the left, two short number
## fields with their labels on the right.
func _field_row(text: String, a: String, fa: LineEdit, b: String, fb: LineEdit, lead: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(6))
	var first: Control = lead if lead != null else Kit.label(text)
	first.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(first)
	row.add_child(Kit.label(a))
	row.add_child(fa)
	var gap := Control.new()
	gap.custom_minimum_size.x = Kit.px(12)
	row.add_child(gap)
	row.add_child(Kit.label(b))
	row.add_child(fb)
	return row


func _number(node_name: String, value: int) -> LineEdit:
	var e := LineEdit.new()
	e.name = node_name
	e.text = str(value)
	e.custom_minimum_size = Kit.pxv(40, 32)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return e


func _set_label(t: String) -> void:
	var b := BpString.body(record)
	if t == "":
		b.erase("label")
	else:
		b["label"] = t


func _icon_clicked(i: int, button_index: int) -> void:
	var icons := BpString.icons(record)
	while icons.size() < 4:
		icons.append(["item", ""])
	if button_index == MOUSE_BUTTON_RIGHT:
		icons[i] = ["item", ""]
		BpString.set_icons(record, icons)
		_show()
	elif button_index == MOUSE_BUTTON_LEFT and picker != null:
		picker.choose(["item", "fluid", "virtual"], func(type_name: String, name: String) -> void:
			icons[i] = [type_name, name]
			BpString.set_icons(record, icons)
			_show(), "Choose an icon")


## Right click in the preview: that entity is left out; left click: it comes back.
func preview_clicked(entity_number: int, button_index: int) -> void:
	if entity_number <= 0:
		return
	if button_index == MOUSE_BUTTON_RIGHT:
		removed[entity_number] = true
	elif button_index == MOUSE_BUTTON_LEFT:
		removed.erase(entity_number)
	_show()


## An upgrade planner's mappings applied (the coordinator found one); Save keeps them.
func apply_upgrade(planner: Dictionary) -> int:
	var n := BpString.upgrade(record, planner)
	_show()
	return n


func _on_save() -> void:
	saved.emit(result(), source)
	close_requested.emit()


## The blueprint seen from above, fitted into the panel, as Factorio draws it: each entity's own
## sprite frame from the player's install (sprite_projection.gd's sheets: the frame for its
## direction, its anchor on the entity's position), tiles as squares in their map colour. An
## entity without a sheet (or without Factorio) is its footprint in its map colour with its icon.
class Preview extends Control:
	var window  # the blueprint window

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func _layout() -> Array:
		var b := BpString.body(window.record)
		var items: Array = []  # [rect in tiles, name, entity_number, colour]
		for t in BpString._list(b.get("tiles")):
			var p: Dictionary = t.get("position", {})
			items.append([Rect2(float(p.get("x", 0)), float(p.get("y", 0)), 1, 1), "", 0, _tile_color(str(t.get("name", ""))), 0])
		for e in BpString._list(b.get("entities")):
			var p: Dictionary = e.get("position", {})
			var size := Vector2.ONE
			var color := Color(0.45, 0.45, 0.45)
			if window.protos != null:
				var proto = window.protos.entities_by_name.get(str(e.get("name", "")))
				if proto != null:
					size = Vector2(proto.tile_size)
					color = proto.color
			var d := int(e.get("direction", 0))
			if d == 4 or d == 12:
				size = Vector2(size.y, size.x)
			var at := Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
			items.append([Rect2(at - size * 0.5, size), str(e.get("name", "")), int(e.get("entity_number", 0)), color, d])
		return items

	func _tile_color(name: String) -> Color:
		if window.protos != null:
			var i: int = window.protos.tile_names.find(name)
			if i >= 0 and i < window.protos.tile_colors.size():
				return window.protos.tile_colors[i]
		return Color(0.35, 0.35, 0.35)

	## [scale, offset]: tiles to pixels.
	func _fit(items: Array) -> Array:
		if items.is_empty():
			return [1.0, Vector2.ZERO]
		var r: Rect2 = items[0][0]
		for it in items:
			r = r.merge(it[0])
		var margin := float(Kit.px(48))
		var k := minf((size.x - margin * 2) / maxf(r.size.x, 1.0), (size.y - margin * 2) / maxf(r.size.y, 1.0))
		k = minf(k, float(Kit.px(64)))
		return [k, size * 0.5 - r.get_center() * k]

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(37, 37, 37))
		if window == null or window.record.is_empty():
			return
		var items := _layout()
		var f := _fit(items)
		var k: float = f[0]
		var off: Vector2 = f[1]
		# Back to front, as Factorio sorts them: tiles, then entities by their southern edge.
		items.sort_custom(func(a: Array, b: Array) -> bool:
			if (str(a[1]) == "") != (str(b[1]) == ""):
				return str(a[1]) == ""
			return (a[0] as Rect2).end.y < (b[0] as Rect2).end.y)
		for it in items:
			var r := Rect2((it[0] as Rect2).position * k + off, (it[0] as Rect2).size * k)
			var gone: bool = window.removed.has(int(it[2])) and int(it[2]) > 0
			if str(it[1]) == "":
				draw_rect(r, (it[3] as Color).darkened(0.2))
				continue
			var tint := Color(1, 0.4, 0.4, 0.35) if gone else Color.WHITE
			if _draw_sprite(str(it[1]), int(it[4]), r.get_center(), k, tint):
				continue
			draw_rect(r.grow(-1), Color(it[3], 0.35 if not gone else 0.12))
			var s := minf(r.size.x, r.size.y) * 0.8
			draw_texture_rect(Kit.item_icon(str(it[1])), Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)), false,
				Color(1, 0.4, 0.4, 0.35) if gone else Color.WHITE)

	static var _belts := {}  # name -> ImageTexture (four frames, east west north south) or null

	## The entity's sprite frame with its anchor at `at`; false when there is no sheet for it.
	func _draw_sprite(name: String, d: int, at: Vector2, k: float, tint: Color) -> bool:
		if BELT_SHEETS.has(name):
			var belt := _belt(name)
			if belt == null:
				return false
			var row: int = {4: 0, 12: 1, 0: 2, 8: 3}.get(posmod(d, 16), 2)
			draw_texture_rect_region(belt, Rect2(at - Vector2(k, k), Vector2(k, k) * 2.0), Rect2(0, row * 128, 128, 128), tint)
			return true
		var p = SpriteProjection.for_flat(name)
		if p == null or p.texture == null or p.mode == 3 or p.cells < 1:
			return false
		var cell := 0
		if p.mode == 1:
			cell = (posmod(d, 16) / 4) % p.cells
		var slot := Vector2(float(p.atlas_size.x) / int(p.cells), float(p.atlas_size.y))
		var src := Rect2(Vector2(slot.x * cell, 0), slot)
		var ratio: float = k / float(p.px_per_tile)
		var anchor: Vector2 = p.anchors[cell]
		draw_texture_rect_region(p.texture, Rect2(at - (anchor - src.position) * ratio, slot * ratio), src, tint)
		return true

	static func _belt(name: String) -> Texture2D:
		if _belts.has(name):
			return _belts[name]
		_belts[name] = null
		var dir := ItemIcons.factorio_data_dir()
		var path := dir.path_join("%s/graphics/entity/%s/%s.png" % [BELT_SHEETS[name], name, name]) if dir != "" else ""
		if path != "" and FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null and img.get_width() >= 128 and img.get_height() >= 512:
				_belts[name] = ImageTexture.create_from_image(img.get_region(Rect2i(0, 0, 128, 512)))
		return _belts[name]

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb == null or not mb.pressed or not (mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
			return
		var items := _layout()
		var f := _fit(items)
		var at: Vector2 = (mb.position - (f[1] as Vector2)) / float(f[0])
		for i in range(items.size() - 1, -1, -1):
			if int(items[i][2]) > 0 and (items[i][0] as Rect2).has_point(at):
				window.preview_clicked(int(items[i][2]), mb.button_index)
				accept_event()
				return
