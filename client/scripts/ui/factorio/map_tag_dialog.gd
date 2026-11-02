extends PanelContainer
## Factorio's tag dialog on the map: "Create tag" or "Edit tag", an icon (a row of common ones to
## pick from, click again for none), the name, and Cancel / Delete / Confirm. Enter confirms, Esc
## (or Cancel, or ×) closes it.

signal confirmed(text: String, icon_name: String)
signal deleted

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const LayeredStyle := preload("res://scripts/ui/factorio/layered_style.gd")

## The icons offered (Factorio lets you pick any signal; these are what tags usually mark).
const ICONS := ["iron-ore", "copper-ore", "coal", "stone", "uranium-ore", "iron-plate", "copper-plate",
	"steel-plate", "electronic-circuit", "transport-belt"]

var text_field := LineEdit.new()
var icon_name := ""
var editing := false

var _title := Label.new()
var _delete := Button.new()
var _icon_buttons: Array = []


func _ready() -> void:
	theme_type_variation = "FFrame"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Create tag", true)
	_title = bar.get_child(0) as Label
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(close)
	box.add_child(bar)

	var inner := Kit.panel("FShallowFrame")
	box.add_child(inner)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", Kit.px(8))
	inner.add_child(rows)
	rows.add_child(Kit.label("Icon", "FHeading"))
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 0)
	rows.add_child(icons)
	for item in ICONS:
		var b := Button.new()
		b.theme_type_variation = "FSlotButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
		b.icon = Kit.item_icon(item)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", Kit.px(32))
		b.texture_filter = Kit.ICON_FILTER
		b.tooltip_text = Kit.pretty(item)
		b.set_meta("item", item)
		b.pressed.connect(_pick.bind(item))
		icons.add_child(b)
		_icon_buttons.append(b)
	rows.add_child(Kit.label("Name", "FHeading"))
	text_field.custom_minimum_size = Vector2(Kit.px(Kit.SLOT * ICONS.size()), Kit.px(28))
	text_field.max_length = 200
	text_field.placeholder_text = "Tag name"
	_style_textbox(text_field)
	text_field.text_submitted.connect(func(_t: String) -> void: _confirm())
	text_field.gui_input.connect(_on_field_input)
	rows.add_child(text_field)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", Kit.px(8))
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.theme_type_variation = "FBackButton"
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(close)
	buttons.add_child(cancel)
	var space := Kit.panel("FDraggable")  # Factorio's dialog_buttons_horizontal_flow filler
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	space.custom_minimum_size.y = Kit.px(32)
	buttons.add_child(space)
	_delete.theme_type_variation = "FRedButton"
	_delete.text = "Delete"
	_delete.focus_mode = Control.FOCUS_NONE
	_delete.custom_minimum_size.y = Kit.px(32)
	var delete := func() -> void:
		deleted.emit()
		close()
	_delete.pressed.connect(delete)
	buttons.add_child(_delete)
	var ok := Button.new()
	ok.theme_type_variation = "FConfirmButton"
	ok.text = "Confirm"
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(_confirm)
	buttons.add_child(ok)


## Factorio's textbox: the light field from the atlas, black text.
static func _style_textbox(field: LineEdit) -> void:
	for state in ["normal", "focus", "read_only"]:
		field.add_theme_stylebox_override(state, _textbox_style(state == "focus"))
	field.add_theme_color_override("font_color", Kit.BLACK)
	field.add_theme_color_override("font_placeholder_color", Color(0, 0, 0, 0.4))
	field.add_theme_color_override("caret_color", Kit.BLACK)
	field.add_theme_color_override("selection_color", Color8(241, 190, 100))
	field.add_theme_font_size_override("font_size", Kit.px(14))


static func _textbox_style(active: bool) -> StyleBox:
	var box: StyleBox
	if Kit.uses_atlas():
		# style.lua: textbox default_background {248, 0}, active_background {265, 0}, corner 8.
		var layered := LayeredStyle.new()
		layered.layers.append(Kit._bake({"at": [265 if active else 248, 0], "corner": 8}))
		box = layered
	else:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(1, 1, 1) if active else Color8(227, 227, 227)
		flat.border_color = Color8(40, 40, 40)
		flat.set_border_width_all(1)
		box = flat
	box.content_margin_left = Kit.px(3)
	box.content_margin_right = Kit.px(2)
	return box


## Shows the dialog at a screen point (kept inside the window), filled from `tag` when editing.
func open_at(at: Vector2, tag: Dictionary) -> void:
	editing = not tag.is_empty()
	_title.text = "Edit tag" if editing else "Create tag"
	_delete.visible = editing
	text_field.text = str(tag.get("text", ""))
	_pick_quietly(str(tag.get("icon_name", "")))
	visible = true
	reset_size()
	var screen := get_viewport_rect().size
	position = (at + Kit.pxv(16, 16)).clamp(Vector2.ZERO, (screen - size).max(Vector2.ZERO))
	text_field.grab_focus()
	text_field.caret_column = text_field.text.length()


## The field has the keyboard while typing, so Esc is caught here (it would only end the edit).
func _on_field_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.physical_keycode == KEY_ESCAPE:
		close()
		text_field.accept_event()


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	text_field.release_focus()


func _pick(item: String) -> void:
	_pick_quietly("" if icon_name == item else item)


func _pick_quietly(item: String) -> void:
	icon_name = item
	for b in _icon_buttons:
		(b as Button).set_pressed_no_signal(str((b as Button).get_meta("item")) == item)


func _confirm() -> void:
	if text_field.text.strip_edges() == "" and icon_name == "":
		return  # Factorio doesn't make an empty tag either
	confirmed.emit(text_field.text.strip_edges(), icon_name)
	close()
