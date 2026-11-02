extends "res://scripts/ui/factorio/global_window.gd"
## Factorio's Permissions window: the tool row (delete, import, export; add, duplicate, rename),
## the permission groups on the left (the selected one orange), "Players in group" in the middle,
## "Show players in other groups" with their list on the right and the arrows between to move
## players. From the mod's `perms` (game.permissions.groups). Read-only: changing permissions is
## an admin's job in the game itself, so the editing buttons are greyed out.

const LIST := Vector2(250, 400)

var selected := ""
var show_others := false

var _groups := VBoxContainer.new()
var _members := VBoxContainer.new()
var _others := VBoxContainer.new()
var _others_frame: Control


func _ready() -> void:
	_init_frame("Permissions", false)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(8))
	body.add_child(row)

	var left := VBoxContainer.new()
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", Kit.px(2))
	for spec in [["Delete", "icons/mip/trash.png"], ["Import", "icons/mip/import.png"], ["Export", "icons/mip/export.png"]]:
		tools.add_child(_tool(spec[0], spec[1]))
	left.add_child(tools)
	left.add_child(_list_frame(_groups))
	row.add_child(left)

	var mid := VBoxContainer.new()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Kit.px(2))
	for spec in [["Add", "add-icon-white.png"], ["Duplicate", "icons/mip/copy.png"], ["Rename", "rename-icon.png"]]:
		head.add_child(_tool(spec[0], spec[1]))
	head.add_child(Kit.label("Players in group", "FHeading"))
	mid.add_child(head)
	mid.add_child(_list_frame(_members))
	row.add_child(mid)

	var arrows := VBoxContainer.new()
	arrows.alignment = BoxContainer.ALIGNMENT_CENTER
	for spec in [["Move left", "icons/mip/backward-arrow.png"], ["Move right", "icons/mip/forward-arrow.png"]]:
		arrows.add_child(_tool(spec[0], spec[1]))
	row.add_child(arrows)

	var right := VBoxContainer.new()
	var others := MenuKit.checkbox("Show players in other groups", false)
	others.name = "ShowOthers"
	others.toggled.connect(func(on: bool) -> void:
		show_others = on
		rebuild())
	right.add_child(others)
	_others_frame = _list_frame(_others)
	right.add_child(_others_frame)
	row.add_child(right)
	model.perms_changed.connect(rebuild)


func opened() -> void:
	model.request_perms()


func _tool(tip: String, sprite: String) -> Button:
	var b := Button.new()
	b.name = tip.replace(" ", "")
	b.theme_type_variation = "FSlotButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Kit.pxv(28, 28)
	b.icon = GuiAssets.core_sprite(sprite)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", Kit.px(16))
	b.disabled = true
	b.tooltip_text = "%s: change permissions in the game itself (admins only)" % tip
	return b


func _list_frame(list: VBoxContainer) -> Control:
	var deep: Array = Kit.deep_scroll(Kit.pxv(LIST.x, LIST.y))
	list.add_theme_constant_override("separation", 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(deep[1] as ScrollContainer).add_child(list)
	return deep[0]


func _row(text: String, selected_row: bool, action := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.name = "Row_" + text
	b.theme_type_variation = "FListItemSelected" if selected_row else "FListItem"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = Kit.px(28)
	if action.is_valid():
		b.pressed.connect(action)
	return b


func rebuild() -> void:
	clear(_groups)
	clear(_members)
	clear(_others)
	var groups: Array = model.perm_groups
	if selected == "" or not groups.any(func(g: Array) -> bool: return str(g[0]) == selected):
		selected = str(groups[0][0]) if not groups.is_empty() else ""
	for g in groups:
		var name := str(g[0])
		_groups.add_child(_row(name, name == selected, func() -> void:
			selected = name
			rebuild()))
		if name == selected:
			for p in g[1]:
				_members.add_child(_row(str(p), false))
		elif show_others:
			for p in g[1]:
				_others.add_child(_row("%s (%s)" % [str(p), name], false))
	if groups.is_empty():
		var l := Kit.label("No permission groups")
		l.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_groups.add_child(l)
