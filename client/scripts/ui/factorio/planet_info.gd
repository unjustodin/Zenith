extends VBoxContainer
## The planet the character is on (Space Age), under the character's inventory: its icon and name
## and its surface properties as Factoriopedia lists them (gravity, pressure, magnetic field,
## solar power, day length), from the mod's `planet` (ui_model.planet). On a platform it says
## "Space". Hidden until the mod has sent a planet.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")
const SpacePanels := preload("res://scripts/ui/factorio/space_panels.gd")

## [property, label, unit, decimals] in Factoriopedia's order.
const PROPERTIES := [["gravity", "Gravity", " m/s²", 1], ["pressure", "Pressure", " hPa", 0],
	["magnetic-field", "Magnetic field", " μT", 0], ["solar-power", "Solar power", "%", 0]]

var model

var _title: Label
var _icon: TextureRect
var _rows: GridContainer


func _ready() -> void:
	add_theme_constant_override("separation", Kit.px(2))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Kit.px(6))
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.custom_minimum_size = Kit.pxv(24, 24)
	_icon.texture_filter = Kit.ICON_FILTER
	head.add_child(_icon)
	_title = Kit.label("", "FHeading")
	head.add_child(_title)
	add_child(head)
	var frame := Kit.panel("FShallowFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var m := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, Kit.px(8 if side == "left" or side == "right" else 4))
	frame.add_child(m)
	_rows = GridContainer.new()
	_rows.columns = 6
	_rows.add_theme_constant_override("h_separation", Kit.px(10))
	m.add_child(_rows)
	add_child(frame)
	visible = false
	model.planet_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var p: Dictionary = model.planet
	visible = not p.is_empty()
	if not visible:
		return
	var name := str(p.get("name", ""))
	_title.text = "Space" if name == "space" else LocaleNames.space_location(name)
	_icon.texture = SpacePanels.planet_icon(name) if name != "space" else GuiAssets.data_sprite("space-age/graphics/icons/space-platform-hub.png")
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var props: Dictionary = p.get("props") if p.get("props") is Dictionary else {}
	for prop in PROPERTIES:
		if props.has(prop[0]):
			_add(str(prop[1]), _number(float(props[prop[0]]), int(prop[3])) + str(prop[2]))
	var day := int(p.get("day", 0))
	if bool(p.get("always_day", false)):
		_add("Day length", "Always day")
	elif day > 0:
		_add("Day length", "%s min" % str(snappedf(day / 3600.0, 0.1)))


func _add(label: String, value: String) -> void:
	var l := Kit.label(label)
	l.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	_rows.add_child(l)
	_rows.add_child(Kit.label(value))


static func _number(v: float, decimals: int) -> String:
	if decimals <= 0:
		return Kit.count_text(roundi(v)) if v >= 10000 else str(roundi(v))
	return str(snappedf(v, pow(10.0, -decimals)))
