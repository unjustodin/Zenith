extends Control
## The stack in the cursor, drawn at the mouse like Factorio: the item's icon with its count in the
## count font, over windows and wherever the world shows no build ghost (an item that can't be
## built, or one held over nothing). factorio_ui.gd sets `item`, `count` and `over_world_too`.

const Kit := preload("res://scripts/ui/factorio/kit.gd")

var item := ""
## -1 hides the count.
var count := -1
## Also drawn over the world (player_input.gd: no build ghost is showing).
var over_world_too := false
## Over a window this frame (factorio_ui.gd).
var over_gui := false
## Where to draw instead of the mouse (--ui-hover, for screenshots); x < 0: the mouse.
var debug_at := Vector2(-1, -1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = Kit.ICON_FILTER
	z_index = 100


func _process(_delta: float) -> void:
	queue_redraw()


func shown() -> bool:
	return item != "" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and (over_gui or over_world_too)


func _draw() -> void:
	if not shown():
		return
	var at := get_local_mouse_position() if debug_at.x < 0 else debug_at
	var side := float(Kit.px(32))
	# Down and right of the pointer's tip, so the pointer still shows where a click lands.
	var rect := Rect2(at + Vector2(Kit.px(6), Kit.px(6)), Vector2(side, side))
	draw_texture_rect(Kit.item_icon(item), rect, false)
	if count >= 0:
		var f := Kit.font("bold")
		var fs := Kit.px(13)
		var text := Kit.count_text(count)
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := rect.end - Vector2(w - Kit.px(2), -Kit.px(2))
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Kit.px(3), Color(0, 0, 0, 0.9))
		draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
