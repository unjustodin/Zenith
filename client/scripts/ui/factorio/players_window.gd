extends Control
## Factorio's players window ([gui-players]: Players, Name, Location): every player of the game
## from `pl`, online ones first, each name in the player's colour with their tag, whether they are
## online (or away), where they are, and which one the client plays. Opened from the Esc menu or
## the "Players" control (unbound by default, as Factorio opens it from its menu).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")

## Factorio counts a player as away after 5 minutes without input.
const AFK_TICKS := 5 * 60 * 60

var model: UiModel

var _title: Label
var _table := GridContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := Kit.panel("FFrame")
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	frame.add_child(box)
	var bar := Kit.title_bar("Player management", true)  # Factorio 2.1's title
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: visible = false)
	box.add_child(bar)
	_title = Kit.label("", "FHeading")
	box.add_child(_title)
	var deep: Array = Kit.deep_scroll(Kit.pxv(420, 240))
	box.add_child(deep[0])
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(8))
	deep[1].add_child(pad)
	_table.columns = 3
	_table.add_theme_constant_override("h_separation", Kit.px(24))
	_table.add_theme_constant_override("v_separation", Kit.px(4))
	pad.add_child(_table)
	if model != null:
		model.players_changed.connect(_refresh)
	_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _refresh() -> void:
	if model == null or not is_inside_tree():
		return
	for c in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	var online := 0
	for p in model.players:
		if p["connected"]:
			online += 1
	_title.text = "%d online" % online if not model.players.is_empty() else ""
	_title.visible = _title.text != ""
	for h in ["Name", "Status", "Location"]:
		_table.add_child(Kit.label(h, "FHeading"))
	if model.players.is_empty():
		var none := Kit.label("No players: the bridge plays its own character")
		none.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_table.add_child(none)
		_table.add_child(Control.new())
		_table.add_child(Control.new())
		return
	var list: Array = model.players.duplicate()
	list.sort_custom(func(a, b) -> bool: return a["connected"] and not b["connected"] or (a["connected"] == b["connected"] and str(a["name"]) < str(b["name"])))
	for p in list:
		var name := str(p["name"])
		if str(p["tag"]) != "":
			name += " " + str(p["tag"])
		if int(p["index"]) == model.me_player:
			name += "  (you)"
		var l := Kit.label(name)
		l.add_theme_color_override("font_color", (p["color"] as Color).lightened(0.25))
		l.add_theme_font_override("font", Kit.font("semibold"))
		_table.add_child(l)
		var status := "Online"
		if not p["connected"]:
			status = "Offline"
		elif int(p["afk"]) >= AFK_TICKS:
			status = "Away (%d min)" % (int(p["afk"]) / 3600)
		if p["admin"]:
			status += ", admin"
		var s := Kit.label(status)
		s.add_theme_color_override("font_color", Kit.GREEN_TEXT if p["connected"] else Kit.DISABLED_TEXT)
		_table.add_child(s)
		_table.add_child(Kit.label(LocaleNames.space_location(str(p["surface"])) if str(p["surface"]) != "" else ""))
