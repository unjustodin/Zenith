extends "res://scripts/ui/factorio/global_window.gd"
## Factorio's Achievements window: the note that a modded game keeps its achievements apart, the
## progress bar with "Earned n of N", and one tall row per achievement with its picture in the
## round bronze frame, its name, what it asks and the ribbon at the right (green when earned).
##
## The list, names, descriptions and pictures come from the player's install (locale
## [achievement-name] / [achievement-description], <mod>/graphics/achievement/<name>.png). The game
## doesn't tell mods which achievements are earned, and a game with the bridge mod is modded, so
## none count as earned here, as Factorio's own note says for modded games.

const LocaleNames := preload("res://scripts/world/locale_names.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")

const ROW_HEIGHT := 120
const WIDTH := 420

var _note: Label
var _bar: ProgressBar
var _bar_text: Label
var _earned: Label
var _rows := VBoxContainer.new()


func _ready() -> void:
	_init_frame("Achievements")
	_note = Kit.label("The game is modded. Achievements are separate from the vanilla version of the game.")
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = Kit.px(WIDTH)
	body.add_child(_note)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", Kit.px(8))
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar = Kit.progress_bar(Kit.BAR_GREEN)
	_bar.custom_minimum_size.y = Kit.px(16)
	_bar.max_value = 1.0
	holder.add_child(_bar)
	_bar_text = Kit.label("0%")
	_bar_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(_bar_text)
	top.add_child(holder)
	_earned = Kit.label("")
	top.add_child(_earned)
	body.add_child(top)
	var deep: Array = Kit.deep_scroll(Kit.pxv(WIDTH, 720))
	body.add_child(deep[0])
	_rows.add_theme_constant_override("separation", Kit.px(2))
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(deep[1] as ScrollContainer).add_child(_rows)


## [name, title, description] of every achievement, in the locale files' order.
static func all() -> Array:
	LocaleNames._load()
	var names: Dictionary = LocaleNames._sections.get("achievement-name", {})
	var out: Array = []
	for n in names:
		out.append([str(n), LocaleNames._lookup("achievement-name", str(n)), LocaleNames._lookup("achievement-description", str(n)).replace("\\n", " ")])
	return out


static func picture(name: String) -> Texture2D:
	for mod in ["base", "space-age", "quality", "elevated-rails"]:
		var t := GuiAssets.data_sprite("%s/graphics/achievement/%s.png" % [mod, name])
		if t != null:
			return t
	# Levelled ones ("circuit-veteran-2") share the first level's picture.
	var dash := name.rfind("-")
	if dash > 0 and name.substr(dash + 1).is_valid_int():
		return picture(name.substr(0, dash) + "-1") if not name.ends_with("-1") else null
	return null


func rebuild() -> void:
	clear(_rows)
	var list := all()
	var earned := 0
	_bar.value = float(earned) / maxf(1.0, list.size())
	_bar_text.text = "%d%%" % roundi(_bar.value * 100.0)
	_earned.text = "Earned %d of %d" % [earned, list.size()]
	if list.is_empty():
		var none := Kit.label("No achievements found: the client reads them from your Factorio install.")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = Kit.px(WIDTH - 20)
		_rows.add_child(none)
		return
	for a in list:
		if search != "" and not (str(a[1]) + " " + str(a[2])).to_lower().contains(search):
			continue
		_rows.add_child(_row(a))


func _row(a: Array) -> Control:
	var p := PanelContainer.new()
	p.name = "Ach_" + str(a[0])
	var s := StyleBoxFlat.new()
	s.bg_color = Color8(62, 62, 62)
	s.set_content_margin_all(Kit.px(6))
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size.y = Kit.px(ROW_HEIGHT)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", Kit.px(8))
	p.add_child(h)
	var pic := TextureRect.new()
	pic.texture = picture(str(a[0]))
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Kit.pxv(96, 96)
	pic.texture_filter = Kit.ICON_FILTER
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Kit.label(str(a[1]), "FHeading")
	v.add_child(t)
	var d := Kit.label(str(a[2]))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = Kit.px(WIDTH - 180)
	v.add_child(d)
	h.add_child(v)
	var ribbon := TextureRect.new()
	ribbon.texture = GuiAssets.core_sprite("icons/mip/bookmark.png")
	ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ribbon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ribbon.custom_minimum_size = Kit.pxv(24, 32)
	ribbon.modulate = Kit.ORANGE
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ribbon.tooltip_text = "Not earned"
	h.add_child(ribbon)
	return p
