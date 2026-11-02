extends "res://scripts/ui/factorio/global_window.gd"
## Factorio's "Tips and tricks" window (the side menu's graduation cap): nearly the whole screen, a
## list of tips on the left (300 wide, a row per tip, titles bold, followers indented, Factorio's
## faint stripes below) and the selected tip on the right ("No tips and tricks selected" until one
## is picked). Factorio plays a small simulation of each tip over its text; the client can't run
## those, so the right side is the tip's name and text.
##
## The tips come from the player's install: every <mod>/prototypes/tips-and-tricks.lua (name,
## category, order, indent, is_title) and the locale's [tips-and-tricks-item-name] /
## [tips-and-tricks-item-description]. Factorio shows only the tips the player has unlocked, which a
## mod can't read, so every tip is listed.

const LocaleNames := preload("res://scripts/world/locale_names.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const Controls := preload("res://scripts/player/controls.gd")

const LIST_WIDTH := 300
const ROW := 28

static var _tips: Array = []  # [name, category order, order, indent, is_title], sorted
static var _loaded := false

var selected := ""
var _list := VBoxContainer.new()
var _page := VBoxContainer.new()


func _ready() -> void:
	_init_frame("Tips and tricks")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(12))
	body.add_child(row)
	var left: Array = Kit.deep_scroll(Kit.pxv(LIST_WIDTH, 400))
	(left[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(left[0])
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(left[1] as ScrollContainer).add_child(_list)
	var right := Kit.panel("FDeepFrame")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(16))
	right.add_child(pad)
	_page.add_theme_constant_override("separation", Kit.px(12))
	pad.add_child(_page)


## Nearly the whole screen, as Factorio's (88 pixels in from the sides at 1920x1080).
func _process(_delta: float) -> void:
	if not visible:
		return
	var view := get_viewport_rect().size
	var margin := Vector2(minf(Kit.px(88), view.x * 0.05), minf(Kit.px(54), view.y * 0.05))
	var inner := view - margin * 2.0 - Vector2(0, Kit.px(56))  # the quickbar stays visible below
	var list_frame: Control = _list.get_parent().get_parent()
	list_frame.custom_minimum_size.y = maxf(Kit.px(200), inner.y - Kit.px(60))
	custom_minimum_size = inner.max(Vector2(Kit.px(600), Kit.px(300)))
	reset_size()
	position = margin.round()


## The tips in Factorio's order (category order, then the tip's), from the install.
static func tips() -> Array:
	if _loaded:
		return _tips
	_loaded = true
	var data := ItemIcons.factorio_data_dir()
	if data == "":
		return _tips
	var categories := {}
	var items: Array = []
	var block := RegEx.create_from_string("\\{([^{}]*(?:\\{[^{}]*\\}[^{}]*)*)\\}")
	var field := func(text: String, key: String) -> String:
		var m := RegEx.create_from_string("(?m)^\\s*" + key + "\\s*=\\s*\"?([^\",\\n]*)\"?").search(text)
		return m.get_string(1).strip_edges() if m != null else ""
	for mod in ItemIcons.MODS:
		var path := data.path_join(mod).path_join("prototypes/tips-and-tricks.lua")
		if not FileAccess.file_exists(path):
			continue
		for m in block.search_all(FileAccess.get_file_as_string(path)):
			var text := m.get_string(1)
			var type: String = field.call(text, "type")
			if type == "tips-and-tricks-item-category":
				categories[field.call(text, "name")] = field.call(text, "order")
			elif type == "tips-and-tricks-item":
				items.append([field.call(text, "name"), field.call(text, "category"), field.call(text, "order"),
					int(field.call(text, "indent")) if field.call(text, "indent") != "" else 0, field.call(text, "is_title") == "true"])
	for it in items:
		_tips.append([it[0], str(categories.get(it[1], it[1])), it[2], it[3], it[4]])
	_tips.sort_custom(func(a, b) -> bool: return [a[1], a[2], a[0]] < [b[1], b[2], b[0]])
	return _tips


static func tip_name(name: String) -> String:
	return _controls(LocaleNames._lookup("tips-and-tricks-item-name", name))


static func tip_text(name: String) -> String:
	return _controls(LocaleNames._lookup("tips-and-tricks-item-description", name)).replace("\\n", "\n")


## __CONTROL__show-info__ becomes the client's key for it ([Alt]); controls the client doesn't
## have keep Factorio's name for them.
static func _controls(text: String) -> String:
	if not text.contains("__"):
		return text
	for m in RegEx.create_from_string("__CONTROL(?:_[A-Z_]+)?__([a-z0-9\\-]+)__").search_all(text):
		var control := m.get_string(1)
		var keys := Controls.keys_text({"show-info": "alt_mode"}.get(control, control.replace("-", "_")))
		if keys == "":
			keys = LocaleNames._lookup("controls", control)
		text = text.replace(m.get_string(0), "[font=default-bold][color=128,206,240]%s[/color][/font]" % (keys if keys != "" else control))
	return text.replace("__ALT_CONTROL_LEFT_CLICK__", "Alt + Left click")


func select(name: String) -> void:
	selected = name
	rebuild()


func rebuild() -> void:
	LocaleNames._load()
	clear(_list)
	for t in tips():
		var title := tip_name(str(t[0]))
		if search != "" and not (title + " " + tip_text(str(t[0]))).to_lower().contains(search):
			continue
		var b := Button.new()
		b.name = "Tip_" + str(t[0])
		b.theme_type_variation = "FListItemSelected" if str(t[0]) == selected else "FListItem"
		b.toggle_mode = true
		b.button_pressed = str(t[0]) == selected
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = Kit.px(ROW)
		b.text = "    ".repeat(int(t[3])) + RichText.plain(title)
		if bool(t[4]) or int(t[3]) == 0:
			b.add_theme_font_override("font", Kit.font("bold"))
		var name := str(t[0])
		b.pressed.connect(func() -> void: select(name))
		_list.add_child(b)
	clear(_page)
	if selected == "":
		var none := Kit.label("No tips and tricks selected")
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		none.size_flags_vertical = Control.SIZE_EXPAND_FILL
		none.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_page.add_child(none)
		return
	_page.add_child(Kit.label(RichText.plain(tip_name(selected)), "FHeading"))
	for para in tip_text(selected).split("\n"):
		var l := RichText.label(para)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.fit_content = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_page.add_child(l)
