extends HBoxContainer
## Factorio's switch (style.lua switch_style): the left label, the dark pill with its round knob,
## the right label. The side that is on has its label in default-bold orange (241, 190, 100), the
## other in default white. Clicking the pill flips it; clicking a label picks that side. Used for
## Whitelist/Blacklist, Left/Right, Off/On, Automatic/Manual and Sort descending/ascending.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

## The player picked a side: "left" or "right".
signal switched(state: String)

const ACTIVE := Color8(241, 190, 100)
## left_button_position, middle_button_position, right_button_position (GUI pixels).
const KNOB_X := {"left": 2, "none": 9, "right": 16}

var state := "left"
var left_label := Label.new()
var right_label := Label.new()
var enabled := true
var _pill := Control.new()
var _hover := false

static var _atlas_tex: Texture2D = null
static var _atlas_tried := false


func _init() -> void:
	add_theme_constant_override("separation", Kit.px(6))
	for l in [left_label, right_label]:
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left_label.gui_input.connect(func(e: InputEvent) -> void: _label_input(e, "left"))
	right_label.gui_input.connect(func(e: InputEvent) -> void: _label_input(e, "right"))
	_pill.custom_minimum_size = Kit.pxv(32, 16)
	_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pill.mouse_filter = Control.MOUSE_FILTER_STOP
	_pill.draw.connect(_draw_pill)
	_pill.gui_input.connect(_pill_input)
	_pill.mouse_entered.connect(func() -> void:
		_hover = true
		_pill.queue_redraw())
	_pill.mouse_exited.connect(func() -> void:
		_hover = false
		_pill.queue_redraw())
	add_child(left_label)
	add_child(_pill)
	add_child(right_label)


func _ready() -> void:
	_style_labels()


## Shows `s` without telling anyone.
func set_state(s: String) -> void:
	state = s
	_style_labels()
	_pill.queue_redraw()


func set_enabled(on: bool) -> void:
	enabled = on
	_style_labels()


## As if the player picked that side (tests use it too).
func pick(s: String) -> void:
	if not enabled or s == state:
		return
	set_state(s)
	switched.emit(s)


func _label_input(e: InputEvent, side: String) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pick(side)
		accept_event()


func _pill_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pick("left" if state == "right" else "right")
		accept_event()


func _style_labels() -> void:
	for pair in [[left_label, "left"], [right_label, "right"]]:
		var l: Label = pair[0]
		var on: bool = state == pair[1]
		l.add_theme_font_override("font", Kit.font("bold" if on else "regular"))
		var c: Color = ACTIVE if on else Kit.WHITE
		l.add_theme_color_override("font_color", c if enabled else Kit.DISABLED_TEXT)


static func _atlas() -> Texture2D:
	if not _atlas_tried:
		_atlas_tried = true
		var image := GuiAssets.atlas()
		if image != null:
			_atlas_tex = ImageTexture.create_from_image(image)
	return _atlas_tex


func _draw_pill() -> void:
	var size := _pill.size
	var knob_x: float = KNOB_X.get(state, 9) * Kit.scale
	var knob := Rect2(knob_x, 1.0 * Kit.scale, 14.0 * Kit.scale, 14.0 * Kit.scale)
	var tex := _atlas()
	if tex == null:
		_pill.draw_rect(Rect2(Vector2.ZERO, size), Color8(30, 30, 30))
		_pill.draw_circle(knob.get_center(), knob.size.x / 2.0, Color8(180, 180, 180) if not _hover else Color8(255, 175, 0))
		return
	_pill.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), Rect2(64 if _hover and enabled else 0, 96, 64, 32))
	_pill.draw_texture_rect_region(tex, knob, Rect2(156 if _hover and enabled else 128, 96, 28, 28))
