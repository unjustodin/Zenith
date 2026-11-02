extends HBoxContainer
## Factorio's notched_slider (style.lua) with the number box beside it, as the inserter's hand
## size, a train stop's limit and priority and the speaker's volume have: notches over a thin bar,
## orange from the left to the pentagon handle, and the value in a text field. Disabled (the
## checkbox before it unticked) everything greys and the box can't be typed in. Dragging or typing
## commits the value with `committed` once the mouse is let go or Enter is pressed.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Switch := preload("res://scripts/ui/factorio/switch.gd")

signal committed(value: int)

var min_value := 0
var max_value := 10
var value := 0
var enabled := true
var bar := Control.new()
var box: LineEdit
var _dragging := false


func _init() -> void:
	add_theme_constant_override("separation", Kit.px(8))
	bar.custom_minimum_size = Kit.pxv(120, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.draw.connect(_draw_bar)
	bar.gui_input.connect(_bar_input)
	add_child(bar)
	box = MenuKit.textbox("")
	box.custom_minimum_size = Kit.pxv(48, 28)
	box.alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.name = "Value"
	box.add_theme_color_override("font_uneditable_color", Kit.DISABLED_TEXT.darkened(0.25))
	box.text_submitted.connect(func(t: String) -> void: _typed(t))
	box.focus_exited.connect(func() -> void: _typed(box.text))
	add_child(box)


func setup(from: int, to: int, current: int, on := true) -> void:
	min_value = from
	max_value = maxi(from + 1, to)
	value = clampi(current, min_value, max_value)
	box.text = str(value)
	set_enabled(on)


func set_enabled(on: bool) -> void:
	enabled = on
	box.editable = on
	bar.mouse_default_cursor_shape = Control.CURSOR_ARROW
	bar.queue_redraw()


## As if the player chose v (tests use it too).
func commit(v: int) -> void:
	if not enabled:
		return
	value = clampi(v, min_value, max_value)
	box.text = str(value)
	bar.queue_redraw()
	committed.emit(value)


func _typed(t: String) -> void:
	if enabled and t.strip_edges().is_valid_int() and int(t.strip_edges()) != value:
		commit(int(t.strip_edges()))
	else:
		box.text = str(value)


func _value_at(x: float) -> int:
	var inset := 6.0 * Kit.scale
	var f := clampf((x - inset) / maxf(1.0, bar.size.x - inset * 2.0), 0.0, 1.0)
	return min_value + roundi(f * (max_value - min_value))


func _bar_input(e: InputEvent) -> void:
	if not enabled:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_dragging = true
			value = _value_at(e.position.x)
			box.text = str(value)
			bar.queue_redraw()
		elif _dragging:
			_dragging = false
			commit(value)
		accept_event()
	elif e is InputEventMouseMotion and _dragging:
		value = _value_at(e.position.x)
		box.text = str(value)
		bar.queue_redraw()


func _draw_bar() -> void:
	var s := Kit.scale
	var w := bar.size.x
	var inset := 6.0 * s
	var y := 13.0 * s
	var h := 4.0 * s
	var f := float(value - min_value) / float(maxi(1, max_value - min_value))
	var knob_x := inset + f * (w - inset * 2.0)
	var tex := Switch._atlas()
	# The notches: one per value for short ranges, else ten.
	var steps := max_value - min_value
	var count := steps + 1 if steps <= 10 else 11
	for i in count:
		var nx := inset + (w - inset * 2.0) * (float(i) / float(maxi(1, count - 1)))
		var r := Rect2(nx - 1.0 * s, 3.0 * s, 2.0 * s, 8.0 * s)
		if tex != null:
			bar.draw_texture_rect_region(tex, r, Rect2(138, 200, 4, 16))
		else:
			bar.draw_rect(r, Color8(20, 20, 20))
	var empty := Rect2(0, y, w, h)
	var full := Rect2(0, y, knob_x, h)
	if tex != null:
		var ey := 80 if not enabled else 72
		bar.draw_texture_rect_region(tex, Rect2(0, y, 4.0 * s, h), Rect2(56, ey, 8, 8))
		bar.draw_texture_rect_region(tex, Rect2(4.0 * s, y, w - 8.0 * s, h), Rect2(64, ey, 1, 8))
		bar.draw_texture_rect_region(tex, Rect2(w - 4.0 * s, y, 4.0 * s, h), Rect2(65, ey, 8, 8))
		if enabled and knob_x > 0.0:
			bar.draw_texture_rect_region(tex, Rect2(0, y, minf(4.0 * s, knob_x), h), Rect2(73, 72, 8, 8))
			if knob_x > 4.0 * s:
				bar.draw_texture_rect_region(tex, Rect2(4.0 * s, y, knob_x - 4.0 * s, h), Rect2(81, 72, 1, 8))
		bar.draw_texture_rect_region(tex, Rect2(knob_x - 6.0 * s, 2.5 * s, 12.0 * s, 17.5 * s), Rect2(24 if not enabled else 0, 189, 24, 35))
	else:
		bar.draw_rect(empty, Color8(30, 30, 30))
		if enabled:
			bar.draw_rect(full, Color8(255, 175, 0))
		bar.draw_rect(Rect2(knob_x - 6.0 * s, 3.0 * s, 12.0 * s, 17.0 * s), Color8(160, 160, 160) if enabled else Color8(90, 90, 90))
