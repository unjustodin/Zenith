extends Button
## One of Factorio's item slots (40x40 at 100%): the slot image (theme_type_variation FSlot,
## FSlotButton or FRedSlotButton), the item's 32x32 icon and its count in the bottom-right corner
## in Factorio's count font (bold 13 with a black border). A "ghost" slot (a quickbar pin with none
## left) draws its icon faded and no count; a "hand" slot is where the stack in the cursor came
## from (Factorio's hand icon over the faded item). `progress` draws the crafting queue's orange pie,
## `empty_icon` the faint placeholder of an empty gun, ammo or armour slot. Space Age: a stack
## better than normal quality shows the quality's icon in the bottom-left corner, and a spoiling
## stack its freshness as a bar along the top (green fresh, red about to spoil); set_extra() takes
## both from a slot dictionary. Hovering shows a Factorio tooltip; slots can be dragged onto
## others that accept an item.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

## crafting_queue_slot's pie_progress_color.
const PIE_COLOR := Color(0.98, 0.66, 0.22, 0.5)

## Mouse button pressed on the slot (MOUSE_BUTTON_LEFT/RIGHT/MIDDLE), with Shift held or not.
signal clicked(button_index: int, shift: bool)

var item := ""
## -1 hides the count.
var count := -1
var ghost := false
## Ctrl was held for the latest click.
var ctrl := false
## The stack in the cursor came from this slot: Factorio's hand icon on the emptied slot. When only
## part of the stack was picked up (right click) the slot shows what is left, `hand_left`, instead.
var hand := false
var hand_left := -1
## Which inventory slot this is (factorio_ui.gd finds the slot under the mouse while a held stack
## is dragged across slots): the role ("main", "chest", ...) and 1-based index; "" for other slots.
var slot_role := ""
var slot_index := 0
## A held stack is being spread across slots (factorio_ui.gd): no drag-and-drop meanwhile.
static var spreading := false
## 0..1 draws a progress pie over the slot; below 0 none.
var progress := -1.0
## Drawn faintly while the slot is empty (e.g. GuiAssets.core_sprite("icons/mip/empty-gun-slot.png")).
var empty_icon: Texture2D = null
var tip_title := ""
## Tooltip lines: [text] or [text, item for an icon].
var tip_lines: Array = []
## Dragging this slot carries this item ("" disables dragging).
var drag_item := ""
## Called with the item dropped on this slot; dropping is off while it is invalid.
var on_drop := Callable()
## Past a chest's limit bar: Factorio tints the slot red.
var blocked := false
## Factorio's item stats under every item slot's tooltip (stack size, fuel value, the entity it
## builds...): Callable(item) -> lines, set by factorio_ui.gd from Factoriopedia's data.
static var info := Callable()
## A filter set on an empty slot: its item drawn faintly (inventory and inserter filters).
var filter_item := ""
## The stack's quality ("" or "normal": none drawn) and freshness (0..1, below 0: doesn't spoil).
var quality := ""
var freshness := -1.0
## Rounds left in a magazine as a fraction (0..1), drawn as Factorio's thin green bar along the
## bottom left (item_ammo_magazine_left_bar_color); below 0, or a full magazine: none.
var ammo_bar := -1.0
## A blueprint's, book's or planner's icons ([[signal type, name], ...]): Factorio draws them over
## the item, one big or up to four in a square.
var record_icons: Array = []

## Factorio's quality colours (quality.lua), for names in tooltips.
const QUALITY_COLORS := {"uncommon": Color8(43, 230, 43), "rare": Color8(25, 128, 255), "epic": Color8(180, 0, 255),
	"legendary": Color8(255, 166, 0)}
static var _quality_icons := {}


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	texture_filter = Kit.ICON_FILTER  # the slot images are drawn 1:1, so only the icon is filtered
	theme_type_variation = "FSlot"
	custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
	button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE


func set_stack(new_item: String, new_count: int, is_ghost := false) -> void:
	if new_item == item and new_count == count and is_ghost == ghost:
		return
	item = new_item
	count = new_count
	ghost = is_ghost
	queue_redraw()


## Quality, freshness and a blueprint's icons from a slot dictionary ({"item", "count",
## "quality"?, "freshness"?, "icons"?}).
func set_extra(stack: Dictionary) -> void:
	var q := str(stack.get("quality", ""))
	var f := float(stack.get("freshness", -1.0))
	var i: Array = stack.get("icons", []) if stack.get("icons") is Array else []
	if q != quality or not is_equal_approx(f, freshness) or i != record_icons:
		quality = q
		freshness = f
		record_icons = i
		queue_redraw()


## The quality's icon from the player's install (Space Age's quality mod), or null for normal.
static func quality_icon(q: String) -> Texture2D:
	if q == "" or q == "normal":
		return null
	if not _quality_icons.has(q):
		_quality_icons[q] = GuiAssets.data_sprite("quality/graphics/icons/quality-%s.png" % q)
	return _quality_icons[q]


## Tooltip lines for a stack's quality and freshness, as Factorio's item tooltip shows them.
static func extra_lines(stack: Dictionary) -> Array:
	var lines: Array = []
	var q := str(stack.get("quality", ""))
	if q != "" and q != "normal":
		lines.append(["Quality: %s" % q.capitalize(), "", QUALITY_COLORS.get(q, Kit.DISABLED_TEXT)])
	if stack.has("freshness"):
		lines.append(["Freshness: %d%%" % roundi(float(stack["freshness"]) * 100.0), "", freshness_color(float(stack["freshness"]))])
	return lines


## Green while fresh, through yellow, to red about to spoil.
static func freshness_color(f: float) -> Color:
	return Color(0.9, 0.2, 0.15).lerp(Color(1.0, 0.85, 0.2), clampf(f * 2.0, 0.0, 1.0)) if f < 0.5 		else Color(1.0, 0.85, 0.2).lerp(Color(0.35, 0.85, 0.3), clampf(f * 2.0 - 1.0, 0.0, 1.0))


## What stays in a slot whose stack is in the cursor (hand_slot: [role, index, n picked up, 0: all]):
## -1 when the whole stack was taken.
static func hand_left_of(hand_slot: Array, stack: Dictionary) -> int:
	var n := int(hand_slot[2]) if hand_slot.size() >= 3 else 0
	var have := int(stack.get("count", 0))
	return have - n if n > 0 and n < have else -1


## `left` >= 0: only part was picked up and that many stay in the slot (drawn as a normal stack).
func set_hand(on: bool, left := -1) -> void:
	if on != hand or left != hand_left:
		hand = on
		hand_left = left
		queue_redraw()


func set_progress(value: float) -> void:
	if not is_equal_approx(value, progress):
		progress = value
		queue_redraw()


func set_tip(title: String, lines: Array = []) -> void:
	tip_title = title
	tip_lines = lines
	tooltip_text = title  # non-empty, so Godot asks _make_custom_tooltip


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		ctrl = mb.ctrl_pressed
		clicked.emit(mb.button_index, mb.shift_pressed)


func set_blocked(on: bool) -> void:
	if on != blocked:
		blocked = on
		queue_redraw()


func _draw() -> void:
	var icon_size := float(Kit.px(32))
	var rect := Rect2((size - Vector2(icon_size, icon_size)) * 0.5, Vector2(icon_size, icon_size))
	if blocked:
		draw_rect(Rect2(Vector2.ZERO, size).grow(-Kit.px(2)), Color(0.75, 0.1, 0.1, 0.55))
	if item == "":
		if filter_item != "":
			draw_texture_rect(Kit.item_icon(filter_item), rect, false, Color(1, 1, 1, 0.4))
		elif empty_icon != null:
			draw_texture_rect(empty_icon, rect, false, Color(1, 1, 1, 0.6))
		return
	var whole_hand := hand and hand_left < 0
	if whole_hand:
		# The whole stack is in the cursor: Factorio shows only its hand on the empty slot.
		var hand_icon := GuiAssets.core_sprite("icons/mip/slot-item-in-hand.png")
		if hand_icon != null:
			draw_texture_rect(hand_icon, rect, false)
		else:
			draw_texture_rect(Kit.item_icon(item), rect, false, Color(1, 1, 1, 0.35))
		return
	var faded := ghost
	draw_texture_rect(Kit.item_icon(item), rect, false, Color(1, 1, 1, 0.45) if faded else Color.WHITE)
	draw_record_icons(self, record_icons, rect, Color(1, 1, 1, 0.45) if faded else Color.WHITE)
	if progress >= 0.0:
		_draw_pie(clampf(progress, 0.0, 1.0))
	var q_icon := quality_icon(quality)
	if q_icon != null:
		var qs := float(Kit.px(14))
		draw_texture_rect(q_icon, Rect2(Vector2(Kit.px(2), size.y - qs - Kit.px(2)), Vector2(qs, qs)), false)
	if freshness >= 0.0 and not faded:
		var bar := Rect2(Vector2(Kit.px(4), Kit.px(3)), Vector2(size.x - Kit.px(8), maxf(2.0, Kit.px(3))))
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(freshness, 0.0, 1.0), bar.size.y)), freshness_color(freshness))
	if ammo_bar >= 0.0 and ammo_bar < 1.0 and not faded:
		var full := size.x - Kit.px(6)
		draw_rect(Rect2(Vector2(Kit.px(3), size.y - Kit.px(5)), Vector2(maxf(1.0, full * ammo_bar), maxf(2.0, Kit.px(2)))), Color(0, 1, 0))
	if count >= 0 and not faded:
		var f := Kit.font("bold")
		var fs := Kit.px(13)
		var text := Kit.count_text(hand_left if hand and hand_left >= 0 else count)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(size.x - w - Kit.px(3), size.y - Kit.px(3))
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Kit.px(3), Color(0, 0, 0, 0.9))
		draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


## Up to four icons over an item's picture `rect`: one alone at most of its size, more in a 2 x 2
## square, as Factorio draws a blueprint's or book's icons.
static func draw_record_icons(on: CanvasItem, icons: Array, rect: Rect2, modulate := Color.WHITE) -> void:
	var n := mini(icons.size(), 4)
	if n == 0:
		return
	var cell := rect.size.x * (0.875 if n == 1 else 0.4375)
	var origin := rect.position + (rect.size - Vector2(cell, cell) * (1.0 if n == 1 else 2.0)) * 0.5
	for i in n:
		var icon = icons[i]
		var name := str(icon[1]) if icon is Array and icon.size() >= 2 else ""
		if name != "":
			var at := origin + Vector2(i % 2, i / 2) * cell if n > 1 else origin
			on.draw_texture_rect(Kit.item_icon(name), Rect2(at, Vector2(cell, cell)), false, modulate)


## The part done, clockwise from the top, as Factorio's crafting queue shows it.
func _draw_pie(done: float) -> void:
	if done <= 0.0:
		return
	var c := size * 0.5
	var r := size.length() * 0.5
	var points := PackedVector2Array([c])
	var steps := 32
	for i in steps + 1:
		var a := TAU * done * i / float(steps) - PI * 0.5
		points.append(c + Vector2(cos(a), sin(a)) * r)
	var clip := Rect2(Vector2.ZERO, size).grow(-Kit.px(2))
	for i in points.size():
		points[i] = points[i].clamp(clip.position, clip.end)
	draw_colored_polygon(points, PIE_COLOR)


func _make_custom_tooltip(_for_text: String) -> Object:
	if tip_title == "":
		return null
	var lines := tip_lines
	if info.is_valid() and item != "":
		var more: Array = info.call(item)
		if not more.is_empty():
			lines = tip_lines.duplicate()
			lines.append_array(more)
	return Kit.tooltip(tip_title, lines)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_item == "" or spreading:
		return null
	var preview := TextureRect.new()
	preview.texture = Kit.item_icon(drag_item)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Kit.pxv(32, 32)
	preview.position = -preview.size * 0.5
	var holder := Control.new()
	holder.add_child(preview)
	set_drag_preview(holder)
	return {"f3d_item": drag_item}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return on_drop.is_valid() and data is Dictionary and data.has("f3d_item")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	on_drop.call(str(data["f3d_item"]))
