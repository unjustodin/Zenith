extends PanelContainer
## The frame the game-wide windows share (bonuses_window.gd, alerts_config.gd,
## achievements_window.gd, permissions_window.gd): Factorio's frame centred on the screen, the
## title bar with the search button (a box in the title bar, Ctrl+F too) and close. Subclasses put
## their content in `body` and fill it in `rebuild()`; `search` holds the search's lower-case text.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

var model
var body := VBoxContainer.new()
var search := ""
var title_label: Label
var _search_box := LineEdit.new()


func _init_frame(title: String, searchable := true) -> void:
	theme = MenuKit.theme()
	theme_type_variation = "FFrame"
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar(title, true)
	title_label = bar.get_child(0)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: open(false))
	if searchable:
		_search_box.placeholder_text = "Search"
		_search_box.custom_minimum_size = Kit.pxv(180, 24)
		_search_box.visible = false
		_search_box.text_changed.connect(func(t: String) -> void:
			search = t.strip_edges().to_lower()
			rebuild())
		bar.add_child(_search_box)
		bar.move_child(_search_box, bar.get_child_count() - 2)
		var glass := Kit.close_button()
		glass.name = "Search"
		glass.tooltip_text = "Search (Ctrl+F)"
		var icon := GuiAssets.core_sprite("icons/search.png")
		if icon != null:
			glass.icon = icon
		glass.pressed.connect(toggle_search)
		bar.add_child(glass)
		bar.move_child(glass, bar.get_child_count() - 2)
	box.add_child(bar)
	body.add_theme_constant_override("separation", Kit.px(8))
	box.add_child(body)


func is_open() -> bool:
	return visible


func open(on: bool) -> void:
	visible = on
	if on:
		opened()
		rebuild()


func toggle() -> void:
	open(not visible)


func toggle_search() -> void:
	_search_box.visible = not _search_box.visible
	if _search_box.visible:
		_search_box.grab_focus()
	else:
		_search_box.text = ""
		search = ""
		rebuild()


## Asks the mod for what the window shows (subclasses).
func opened() -> void:
	pass


func rebuild() -> void:
	pass


func _process(_delta: float) -> void:
	if not visible:
		return
	reset_size()
	var view := get_viewport_rect().size
	position = ((view - size) * 0.5).round().max(Vector2.ZERO)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k != null and k.pressed and k.ctrl_pressed and k.keycode == KEY_F and _search_box.get_parent() != null:
		toggle_search()
		get_viewport().set_input_as_handled()


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()
