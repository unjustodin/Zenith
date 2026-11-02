extends Control
## Factorio's equipment grid (an armour's, or a vehicle's): the grid's empty cells drawn with the
## GUI atlas' equipment_slot sprite, each piece of equipment on Factorio's default equipment
## background with its own sprite from the player's install (base/graphics/equipment, found
## through the prototypes' `sprite`), a bar along its bottom for its shield or charge, and, while
## an equipment item is in the cursor over the grid, where it would go (green, or red where it
## doesn't fit). Clicks report the cell; factorio_ui.gd decides what they do. Data: ui_model.grids.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")

## A cell is the equipment_slot sprite: 80 atlas pixels at scale 0.5 (utility-sprites.lua).
const CELL := 40
## utility-constants.lua: equipment_default_background_color (premultiplied 200,200,200 at 0.3),
## equipment_default_background_border_color, equipment_default_grabbed_background_color.
## equipment_slot behind each piece, as sampled from the reference picture (86, 86, 86, opaque).
const BACKGROUND := Color8(86, 86, 86)
const BORDER := Color8(36, 35, 36)
const GRABBED := Color(0.3, 0.3, 0.3, 0.3)
## shield_progressbar's colour (style.lua), and the charge's.
const SHIELD_COLOR := Color(0.8, 0.2, 0.8)
const ENERGY_COLOR := Color(1.0, 0.85, 0.1)
const PROTOTYPE_FILES := ["base/prototypes/equipment.lua", "space-age/prototypes/equipment.lua"]

## A cell was clicked (MOUSE_BUTTON_LEFT / RIGHT / MIDDLE).
signal cell_clicked(kind: String, cell: Vector2i, button_index: int, shift: bool)

var model: UiModel
## "char" or "veh".
var kind := "char"
## The cursor's item when it is equipment, to show where it would go ("" none); and the cell of
## the piece picked up from this grid (Vector2i(-1, -1) none), drawn as Factorio's grabbed one.
var held_item := ""
var held_size := Vector2i.ONE
var grabbed := Vector2i(-1, -1)

static var _slot_texture: Texture2D = null
static var _slot_loaded := false
static var _sprite_paths := {}  # equipment -> "<mod>/graphics/equipment/x.png"
static var _shapes := {}  # equipment -> Vector2i, from the prototypes' `shape`
static var _paths_loaded := false
static var _sprites := {}  # equipment -> Texture2D or null

var _hover := Vector2i(-1, -1)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = Kit.ICON_FILTER


func _ready() -> void:
	if model != null:
		var changed := func(k: String) -> void:
			if k == kind:
				_refresh()
		model.equipment_changed.connect(changed)
	_refresh()


func cell_px() -> float:
	return float(Kit.px(CELL))


func _refresh() -> void:
	var g: Dictionary = model.grid(kind) if model != null else {}
	custom_minimum_size = Vector2(int(g.get("w", 0)), int(g.get("h", 0))) * cell_px()
	tooltip_text = " "  # so Godot asks _make_custom_tooltip
	queue_redraw()


## The cell under a point (local coordinates), or (-1, -1).
func cell_at(point: Vector2) -> Vector2i:
	var g := model.grid(kind)
	var c := Vector2i(floori(point.x / cell_px()), floori(point.y / cell_px()))
	if c.x < 0 or c.y < 0 or c.x >= int(g.get("w", 0)) or c.y >= int(g.get("h", 0)):
		return Vector2i(-1, -1)
	return c


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var c := cell_at(motion.position)
		if c != _hover:
			_hover = c
			queue_redraw()
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var c := cell_at(mb.position)
		if c.x >= 0:
			cell_clicked.emit(kind, c, mb.button_index, mb.shift_pressed)
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover.x >= 0:
		_hover = Vector2i(-1, -1)
		queue_redraw()


func set_held(item: String, item_size: Vector2i, from_cell: Vector2i) -> void:
	if item != held_item or item_size != held_size or from_cell != grabbed:
		held_item = item
		held_size = item_size
		grabbed = from_cell
		queue_redraw()


func _draw() -> void:
	if model == null:
		return
	var g := model.grid(kind)
	var w := int(g.get("w", 0))
	var h := int(g.get("h", 0))
	var c := cell_px()
	var slot := _slot()
	for y in h:
		for x in w:
			var r := Rect2(Vector2(x, y) * c, Vector2(c, c))
			if slot != null:
				draw_texture_rect(slot, r, false)
			else:
				draw_rect(r.grow(-1), Color8(31, 30, 31))
				draw_rect(r.grow(-1), Color8(15, 14, 15), false, 1.0)
	for e in g.get("equipment", []):
		_draw_equipment(e, c)
	# Where the held equipment would go: its footprint from the hovered cell.
	if held_item != "" and _hover.x >= 0:
		var to := _hover
		var fits := to.x + held_size.x <= w and to.y + held_size.y <= h
		if fits:
			for e in g.get("equipment", []):
				var other := Rect2i(int(e["x"]), int(e["y"]), int(e["w"]), int(e["h"]))
				if Vector2i(int(e["x"]), int(e["y"])) != grabbed and other.intersects(Rect2i(to, held_size)):
					fits = false
		var area := Rect2(Vector2(to) * c, Vector2(held_size) * c)
		area = area.intersection(Rect2(Vector2.ZERO, Vector2(w, h) * c))
		draw_rect(area, Color(0.2, 0.8, 0.2, 0.3) if fits else Color(0.9, 0.15, 0.15, 0.35))
		var sprite := sprite_for(held_item)
		if sprite != null:
			draw_texture_rect(sprite, _fit(sprite, Rect2(Vector2(to) * c, Vector2(held_size) * c)), false, Color(1, 1, 1, 0.5))


func _draw_equipment(e: Dictionary, c: float) -> void:
	var r := Rect2(Vector2(int(e["x"]), int(e["y"])) * c, Vector2(int(e["w"]), int(e["h"])) * c).grow(-Kit.px(1))
	var picked := Vector2i(int(e["x"]), int(e["y"])) == grabbed
	draw_rect(r, GRABBED if picked else BACKGROUND)
	draw_rect(r, BORDER, false, maxf(1.0, Kit.px(1)))
	var sprite := sprite_for(str(e["name"]))
	var tint := Color(1, 1, 1, 0.35) if picked or bool(e.get("ghost", false)) else Color.WHITE
	if sprite != null:
		draw_texture_rect(sprite, _fit(sprite, r.grow(-Kit.px(2))), false, tint)
	else:
		var icon := Kit.item_icon(str(e["name"]))
		var s := minf(r.size.x, r.size.y) * 0.8
		draw_texture_rect(icon, Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s)), false, tint)
	# Its shield, else its charge, as a thin bar along the bottom.
	var full := float(e.get("max_shield", 0))
	var now := float(e.get("shield", 0))
	var color := SHIELD_COLOR
	if full <= 0.0:
		full = float(e.get("max_energy", 0))
		now = float(e.get("energy", 0))
		color = ENERGY_COLOR
	# Factorio shows no bar on full equipment.
	if full > 0.0 and now < full and not picked:
		var bar := Rect2(r.position.x + Kit.px(3), r.end.y - Kit.px(6), r.size.x - Kit.px(6), Kit.px(3))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(now / full, 0.0, 1.0), bar.size.y)), color)


## A texture's rect inside `r`, keeping its aspect, centred.
static func _fit(t: Texture2D, r: Rect2) -> Rect2:
	var s := t.get_size()
	var k := minf(r.size.x / s.x, r.size.y / s.y)
	var size := s * k
	return Rect2(r.get_center() - size * 0.5, size)


func _make_custom_tooltip(_for_text: String) -> Object:
	if model == null or _hover.x < 0:
		return null
	var e := model.equipment_at(kind, _hover)
	if e.is_empty():
		return null
	var lines: Array = []
	if float(e["max_shield"]) > 0.0:
		lines.append(["Shield: %d / %d" % [int(e["shield"]), int(e["max_shield"])], "", SHIELD_COLOR.lightened(0.3)])
	if float(e["max_energy"]) > 0.0:
		lines.append(["Energy: %s / %s" % [energy_text(float(e["energy"])), energy_text(float(e["max_energy"]))]])
	if str(e["quality"]) != "normal":
		lines.append(["Quality: %s" % str(e["quality"]).capitalize()])
	lines.append(["Click: pick up · Shift+click: to the inventory", "", Kit.DISABLED_TEXT])
	return Kit.tooltip(Kit.pretty(str(e["name"])), lines)


## Joules as Factorio writes them: 120kJ, 20MJ.
static func energy_text(j: float) -> String:
	for unit in [["GJ", 1e9], ["MJ", 1e6], ["kJ", 1e3]]:
		if j >= float(unit[1]):
			return ("%.1f" % (j / float(unit[1]))).trim_suffix(".0") + str(unit[0])
	return "%dJ" % int(j)


## Watts likewise: 750kW.
static func power_text(w: float) -> String:
	return energy_text(w).trim_suffix("J") + "W"


# --- graphics from the player's install --------------------------------------------------------

## The atlas' equipment_slot (gui-new.png 0, 930, 80x80), or null without an install.
static func _slot() -> Texture2D:
	if _slot_loaded:
		return _slot_texture
	_slot_loaded = true
	var atlas := GuiAssets.atlas()
	if atlas != null and atlas.get_height() >= 1010:
		var image := atlas.get_region(Rect2i(0, 930, 80, 80))
		image.generate_mipmaps()
		_slot_texture = ImageTexture.create_from_image(image)
	return _slot_texture


## An equipment's grid sprite (its prototype's `sprite`, not the item icon), or null.
static func sprite_for(equipment: String) -> Texture2D:
	if _sprites.has(equipment):
		return _sprites[equipment]
	_sprites[equipment] = null
	var dir := ItemIcons.find_data_dir()
	if dir == "":
		return null
	_load_paths(dir)
	var rel: String = _sprite_paths.get(equipment, "")
	var candidates: Array = [rel] if rel != "" else []
	for mod in ["base", "space-age"]:
		candidates.append("%s/graphics/equipment/%s.png" % [mod, equipment])
	for c in candidates:
		var path := dir.path_join(str(c))
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null:
				image.generate_mipmaps()
				_sprites[equipment] = ImageTexture.create_from_image(image)
				break
	return _sprites[equipment]


## An equipment's size in cells: as it sits in a grid, else from its prototype, else 1x1.
static func shape_of(equipment: String, from_model: UiModel = null) -> Vector2i:
	if from_model != null:
		for kind in ["char", "veh"]:
			for e in from_model.grid(kind).get("equipment", []):
				if str(e["name"]) == equipment:
					return Vector2i(int(e["w"]), int(e["h"]))
	var dir := ItemIcons.find_data_dir()
	if dir != "":
		_load_paths(dir)
	return _shapes.get(equipment, Vector2i.ONE)


## Which file is whose sprite, from the equipment prototypes: each `name = "..."` followed by its
## `sprite = { filename = "__mod__/..." }` (fusion and fission reactors don't follow their names).
static func _load_paths(dir: String) -> void:
	if _paths_loaded:
		return
	_paths_loaded = true
	var name_re := RegEx.create_from_string("\\n\\s{4}name\\s*=\\s*\"([^\"]+)\"")
	var sprite_re := RegEx.create_from_string("sprite\\s*=\\s*\\{\\s*filename\\s*=\\s*\"__([a-z0-9-]+)__/([^\"]+)\"")
	var shape_re := RegEx.create_from_string("shape\\s*=\\s*\\{\\s*width\\s*=\\s*(\\d+)\\s*,\\s*height\\s*=\\s*(\\d+)")
	for f in PROTOTYPE_FILES:
		var path := dir.path_join(str(f))
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var names := name_re.search_all(text)
		for m in sprite_re.search_all(text):
			var owner := ""
			for n in names:
				if n.get_start() < m.get_start():
					owner = n.get_string(1)
			if owner != "" and not _sprite_paths.has(owner):
				_sprite_paths[owner] = "%s/%s" % [m.get_string(1), m.get_string(2)]
		for m in shape_re.search_all(text):
			var owner := ""
			for n in names:
				if n.get_start() < m.get_start():
					owner = n.get_string(1)
			if owner != "" and not _shapes.has(owner):
				_shapes[owner] = Vector2i(int(m.get_string(1)), int(m.get_string(2)))
