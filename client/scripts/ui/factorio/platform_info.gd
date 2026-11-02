extends PanelContainer
## Factorio 2.1's panel of a space platform, shown wherever the view is on one: under the minimap
## on board and in the remote view of a platform (platform_panel.gd), and in the right column of the
## map view and the space map (remote_frame.gd). Copied from Factorio 2.1.23's own screens
## (tools/ui_reference/capture.py `--only platform_panel`, H3 and H7):
##   stopped (with or without a schedule, paused, waiting at its stop, or done and waiting for cargo
##   before it leaves): a dark strip with the planet's icon in a slot and "Stopped at Nauvis";
##   travelling: the strip holds the planet it left, a green bar of the way done with the distance
##   come ("4 524 km") at its right end, and the planet it goes to;
## under it "Speed: 109.70 km/s" and "Mass: 60 tons". On board, over it, Factorio's "Drop to a
## planet" button with the character's icon and the red cross that cancels a planned drop.
## Left out: Factorio's "Thrust" and "Damage taken" lines while travelling (2.1's scripts can't read
## either). Ours alone (H7: the owner wants to see where a waiting platform goes): stopped with
## another stop in its schedule, a "Next stop" line with that planet's icon.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const SpacePanels := preload("res://scripts/ui/factorio/space_panels.gd")
const SpaceMap := preload("res://scripts/ui/factorio/space_map.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

## "Drop to a planet" pressed (on board).
signal drop_requested
## The red cross: cancel the planned drop.
signal drop_cancelled
## A planet picked from the list "Drop to a planet" opens.
signal drop_chosen(planet: String)

## The platform shown (a `plat` record), {} for none.
var platform := {}
## The character is on it: the drop row shows.
var on_board := false
## The planet a drop is planned to ("" none): the button says "Dropping to ..." and the cross is lit.
var dropping_to := ""

var _head_row := HBoxContainer.new()
var _lines := VBoxContainer.new()
var _drop_row := HBoxContainer.new()
var _choices := VBoxContainer.new()
var _drop: Button
var _cancel: Button
var _sig := ""


func _init() -> void:
	name = "PlatformInfo"
	theme_type_variation = "FFrame"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	_drop_row.name = "DropRow"
	_drop_row.add_theme_constant_override("separation", Kit.px(4))
	_drop_row.visible = false
	_drop = Button.new()
	_drop.name = "Drop"
	_drop.focus_mode = Control.FOCUS_NONE
	_drop.custom_minimum_size.y = Kit.px(28)
	_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drop.icon = GuiAssets.core_sprite("icons/entity/character.png")
	_drop.expand_icon = true
	_drop.add_theme_constant_override("icon_max_width", Kit.px(20))
	_drop.pressed.connect(func() -> void: drop_requested.emit())
	_drop_row.add_child(_drop)
	_cancel = Button.new()
	_cancel.name = "CancelDrop"
	_cancel.theme_type_variation = "FRedSlotButton"
	_cancel.focus_mode = Control.FOCUS_NONE
	_cancel.custom_minimum_size = Kit.pxv(28, 28)
	_cancel.tooltip_text = "Cancel planet drop"
	_cancel.icon = GuiAssets.core_sprite("icons/close.png")
	_cancel.expand_icon = true
	_cancel.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cancel.add_theme_constant_override("icon_max_width", Kit.px(16))
	_cancel.pressed.connect(func() -> void: drop_cancelled.emit())
	_drop_row.add_child(_cancel)
	box.add_child(_drop_row)
	_choices.name = "DropChoices"
	_choices.add_theme_constant_override("separation", Kit.px(2))
	_choices.visible = false
	box.add_child(_choices)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	box.add_child(inner)
	var head := Kit.panel("FSubheader")
	head.name = "Head"
	_head_row.add_theme_constant_override("separation", Kit.px(4))
	head.add_child(_head_row)
	inner.add_child(head)
	var shallow := Kit.panel("FShallowFrame")
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(8))
	_lines.add_theme_constant_override("separation", Kit.px(2))
	pad.add_child(_lines)
	shallow.add_child(pad)
	inner.add_child(shallow)


## Shows `p` (a `plat` record; {} leaves the panel as it was), `board` when the character is on it.
func show_platform(p: Dictionary, board := false) -> void:
	platform = p
	on_board = board
	var sig := "%s|%s|%s" % [JSON.stringify(p), board, dropping_to]
	if sig == _sig or p.is_empty():
		return
	_sig = sig
	for c in _head_row.get_children():
		_head_row.remove_child(c)
		c.queue_free()
	var leg := trip(p)
	if leg.is_empty():
		var loc := str(p.get("loc", ""))
		_head_row.add_child(slot_icon(loc))
		var title := Kit.label("Stopped at %s" % SpacePanels.place(loc), "FHeading")
		title.name = "Title"
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_head_row.add_child(title)
	else:
		_head_row.add_child(journey(leg))
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for line in lines(p):
		_lines.add_child(_line(str(line[0]), str(line[1])))
	var nx := next_stop(p)
	if nx != "":
		var r := _line("Next stop", " " + SpacePanels.place(nx), nx)
		r.name = "NextStop"
		_lines.add_child(r)
	_drop_row.visible = board
	if not board:
		_choices.visible = false
	if dropping_to != "":
		_drop.text = "Dropping to %s" % SpacePanels.place(dropping_to)
		_drop.tooltip_text = "You will drop to %s when %s is in orbit over the planet." % [SpacePanels.place(dropping_to), _name(p)]
	else:
		_drop.text = "Drop to a planet"
		_drop.tooltip_text = "Choose a planet to drop to when %s is in orbit over it." % _name(p)
	_cancel.disabled = dropping_to == ""


## The list "Drop to a planet" opens (Factorio's "Select planet to drop to"): a button per planet,
## or hides it when `names` is empty.
func choose_drop(names: Array) -> void:
	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	_choices.visible = not names.is_empty()
	if names.is_empty():
		return
	_choices.add_child(Kit.label("Select planet to drop to", "FHeading"))
	for planet in names:
		var b := Button.new()
		b.name = "DropTo_" + str(planet)
		b.text = SpacePanels.place(str(planet))
		b.icon = SpacePanels.planet_icon(str(planet))
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", Kit.px(20))
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = Kit.px(28)
		var name_of := str(planet)
		b.pressed.connect(func() -> void: drop_chosen.emit(name_of))
		_choices.add_child(b)


func choosing_drop() -> bool:
	return _choices.visible


## The trip under way, or {}: {from, to, d (thousandths of the way from `from`), len?}.
static func trip(p: Dictionary) -> Dictionary:
	if not p.has("to"):
		return {}
	var t := {"from": str(p.get("from", "")), "to": str(p["to"]), "d": clampi(int(p.get("d", 0)), 0, 1000)}
	if p.has("len"):
		t["len"] = int(p["len"])
	return t


## Where a stopped platform goes next by its schedule (`nx`), "" when travelling or without one.
static func next_stop(p: Dictionary) -> String:
	return str(p.get("nx", "")) if not p.has("to") and str(p.get("loc", "")) != "" else ""


## The lines under the strip in Factorio's words, [key, value]: speed and mass.
static func lines(p: Dictionary) -> Array:
	var out := [["Speed", "%.2f km/s" % float(p.get("sp", 0.0))]]
	if p.has("w"):
		out.append(["Mass", tons(int(p["w"]))])
	return out


## The travelling strip (G1, H7): the planet it left, the bar of the way done with the distance come
## at its right end, the planet it goes to.
static func journey(leg: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Journey"
	row.add_theme_constant_override("separation", Kit.px(4))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var from := slot_icon(str(leg.get("from", "")))
	from.name = "JourneyFrom"
	row.add_child(from)
	var bar := Kit.progress_bar(Kit.BAR_GREEN)
	bar.name = "JourneyBar"
	bar.max_value = 1000
	bar.value = clampi(int(leg.get("d", 0)), 0, 1000)
	bar.custom_minimum_size.y = Kit.px(24)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color8(60, 58, 60)
	bg.border_color = Color8(32, 27, 25)
	bg.set_border_width_all(1)
	bar.add_theme_stylebox_override("background", bg)
	if leg.has("len"):
		var done := Kit.label("%s km" % SpaceMap.km(roundi(int(leg["len"]) * int(leg.get("d", 0)) / 1000.0)))
		done.name = "JourneyDistance"
		done.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		done.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		done.offset_right = -Kit.px(8)
		bar.add_child(done)
	row.add_child(bar)
	var to := slot_icon(str(leg.get("to", "")))
	to.name = "JourneyTo"
	row.add_child(to)
	return row


## A line as Factorio's panel writes it: the key bold in the heading colour, the value plain, and an
## icon before the value when `planet` is given.
static func _line(key: String, value: String, planet := "") -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 0)
	var k := Kit.label(key + ":")
	k.add_theme_font_override("font", Kit.font("bold"))
	k.add_theme_color_override("font_color", Kit.CAPTION)
	r.add_child(k)
	if planet != "":
		r.add_child(Kit.label(" "))
		var icon := TextureRect.new()
		icon.texture = SpacePanels.planet_icon(planet)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Kit.pxv(20, 20)
		icon.texture_filter = Kit.ICON_FILTER
		r.add_child(icon)
	r.add_child(Kit.label(" " + value.strip_edges()))
	for c in r.get_children():
		if c is Label:
			(c as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return r


## A planet's icon in a grey slot, as the panel's strip has them (28 GUI pixels, the icon 24).
static func slot_icon(planet: String) -> Button:
	var b := Button.new()
	b.name = "Icon"
	b.theme_type_variation = "FSlotButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Kit.pxv(28, 28)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_constant_override("icon_max_width", Kit.px(24))
	b.texture_filter = Kit.ICON_FILTER
	if planet != "":
		b.icon = SpacePanels.planet_icon(planet)
		b.tooltip_text = SpacePanels.place(planet)
	return b


## A mass as Factorio writes it: "60 tons", "86.6 tons", "1 ton".
static func tons(kg: int) -> String:
	var t := "%.1f" % (kg / 1000.0)
	if t.ends_with(".0"):
		t = t.left(-2)
	return "%s %s" % [t, "ton" if t == "1" else "tons"]


static func _name(p: Dictionary) -> String:
	return SpacePanels.plain(str(p.get("n", "the platform")))
