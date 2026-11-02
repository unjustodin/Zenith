extends Control
## Factorio's logistic networks window (L): every logistic network of the force down the left, by
## surface, with its robots; the selected network on the right: its logistic and construction
## robots (available / all), its members (roboport cells, storage, providers, requesters) and the
## items in it, as Factorio's item grid. As in Factorio 2.1 it lives in the remote view: opening it
## (and choosing a network) looks at the network (show_at; factorio_ui.gd keeps the remote view open
## while this is, and its frame's close closes both). From the mod's `lnets` (the list) and `lnet`
## (one network's items), asked for while open.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

signal close_requested
## Look at a position (tiles) on a surface (its index).
signal show_at(at: Vector2, si: int)

const REFRESH := 2.0
const LIST_WIDTH := 290
## The member and item grids' width (slots), as Factorio's.
const COLUMNS := 6

var model: UiModel
var selected := 0

var _list := VBoxContainer.new()
var _details := VBoxContainer.new()
var _items := GridContainer.new()
var _right_frame: PanelContainer
var _timer := 0.0
var _sig := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = MenuKit.theme()
	visible = false
	# Factorio 2.1 draws two frames at the top left of the screen (in its remote view): the list,
	# and the selected network beside it.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(4))
	row.position = Kit.pxv(12, 40)  # under the remote view's title bar, as Factorio's
	add_child(row)
	var left_frame := Kit.panel("FFrame")
	left_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	left_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(left_frame)
	var lbox := VBoxContainer.new()
	lbox.add_theme_constant_override("separation", Kit.px(6))
	left_frame.add_child(lbox)
	# No close of its own: the remote view's title bar closes it.
	var bar := Kit.title_bar("Logistic networks", false)
	(bar.get_child(1) as Control).visible = false
	lbox.add_child(bar)
	var left := Kit.panel("FDeepFrame")
	lbox.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Kit.pxv(LIST_WIDTH, 560)
	left.add_child(scroll)
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_right_frame = Kit.panel("FFrame")
	_right_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	_right_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_right_frame)
	_details.add_theme_constant_override("separation", Kit.px(6))
	_right_frame.add_child(_details)
	_items.columns = COLUMNS
	_items.add_theme_constant_override("h_separation", 0)
	_items.add_theme_constant_override("v_separation", 0)
	model.lnets_changed.connect(_refresh)
	var got := func(id: int) -> void:
		if id == selected:
			_refresh_details()
	model.lnet_received.connect(got)


func is_open() -> bool:
	return visible


func open(on: bool) -> void:
	visible = on
	if on:
		_timer = 0.0
		_sig = ""
		_refresh()
		_look()


func toggle() -> void:
	open(not visible)


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		model.request_lnets()
		if selected != 0:
			model.request_lnet(selected)


func _refresh() -> void:
	if not is_inside_tree():
		return
	var ids: Array = model.lnets.map(func(n) -> int: return int(n["id"]))
	if (selected == 0 or not ids.has(selected)) and not ids.is_empty():
		selected = int(ids[0])
		model.request_lnet(selected)
		_look()
	var sig := JSON.stringify(model.lnets) + str(selected)
	if sig != _sig:
		_sig = sig
		for c in _list.get_children():
			_list.remove_child(c)
			c.queue_free()
		if model.lnets.is_empty():
			var none := Kit.label("No logistic networks present.")
			none.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
			_list.add_child(none)
		var surface := ""
		for n in model.lnets:
			if str(n["surface"]) != surface:
				surface = str(n["surface"])
				var head := Kit.panel("FSubheader")
				head.add_child(Kit.label(Kit.pretty(surface), "FHeading"))
				_list.add_child(head)
			_list.add_child(_row(n))
	_refresh_details()


## One network in the list: the roboport's icon, its name (or number) and its robots on the right.
func _row(n: Dictionary) -> Button:
	var b := Button.new()
	var id := int(n["id"])
	b.name = "Net%d" % id
	b.theme_type_variation = "FListItemSelected" if id == selected else "FListItem"
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.icon = Kit.item_icon("roboport")
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", Kit.px(20))
	var log_robots: Array = n["logistic"]
	var con: Array = n["construction"]
	var name := _name_of(n)
	b.text = name
	b.tooltip_text = "%s\nLogistic robots: %d available of %d\nConstruction robots: %d available of %d\n%d roboport cells" % [
		name, int(log_robots[0]), int(log_robots[1]), int(con[0]), int(con[1]), int(n["cells"])]
	b.custom_minimum_size = Kit.pxv(LIST_WIDTH - 12, 28)
	var count := Kit.label(str(int(log_robots[1]) + int(con[1])))
	count.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	count.offset_left = -Kit.px(60)
	count.offset_right = -Kit.px(8)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if id == selected:
		count.add_theme_color_override("font_color", Kit.BLACK)
	b.add_child(count)
	var pick := func() -> void:
		selected = id
		_sig = ""
		model.request_lnet(id)
		_refresh()
		_look()
	b.pressed.connect(pick)
	return b


## Looks at the selected network (one of its roboports) in the remote view.
func _look() -> void:
	var n := _network(selected)
	if not n.is_empty() and int(n["cells"]) > 0:
		show_at.emit(n["position"], int(n["si"]))


func _name_of(n: Dictionary) -> String:
	return RichText.plain(str(n["name"])) if str(n["name"]) != "" else "Network #%d" % int(n["id"])


func _network(id: int) -> Dictionary:
	for n in model.lnets:
		if int(n["id"]) == id:
			return n
	return {}


func _refresh_details() -> void:
	if _items.get_parent() != null:
		_items.get_parent().remove_child(_items)
	for c in _details.get_children():
		_details.remove_child(c)
		c.queue_free()
	var n := _network(selected)
	_right_frame.visible = not n.is_empty()
	if n.is_empty():
		return
	var bar := Kit.title_bar(_name_of(n), false)
	var look := Kit.close_button()
	look.name = "LookAtIt"
	look.tooltip_text = "Look at it"
	var go := GuiAssets.core_sprite("icons/mip/center.png")
	if go != null:
		look.icon = go
	var at: Vector2 = n["position"]
	var si := int(n["si"])
	look.pressed.connect(func() -> void: show_at.emit(at, si))
	look.disabled = int(n["cells"]) == 0
	bar.add_child(look)
	_details.add_child(bar)
	_details.add_child(_subheader("Members"))
	var members := Kit.slot_grid(COLUMNS)
	var log_robots: Array = n["logistic"]
	var con: Array = n["construction"]
	for m in [["roboport", int(n["cells"]), "Roboport cells"],
			["logistic-robot", int(log_robots[1]), "Logistic robots: %d / %d available" % [int(log_robots[0]), int(log_robots[1])]],
			["construction-robot", int(con[1]), "Construction robots: %d / %d available" % [int(con[0]), int(con[1])]],
			["storage-chest", int(n["storages"]), "Storage chests"], ["passive-provider-chest", int(n["providers"]), "Providers"],
			["requester-chest", int(n["requesters"]), "Requesters"]]:
		if int(m[1]) <= 0:
			continue
		var s := Slot.new()
		s.name = "Member_" + str(m[0])
		s.set_stack(str(m[0]), int(m[1]))
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		s.set_tip(str(m[2]))
		members.add_child(s)
	for i in (COLUMNS - members.get_child_count() % COLUMNS) % COLUMNS:
		members.add_child(Kit.empty_cell())
	var mframe := Kit.panel("FDeepFrame")
	mframe.add_child(members)
	_details.add_child(mframe)
	_details.add_child(_subheader("Items"))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(Kit.px(Kit.SLOT * COLUMNS + 12), Kit.px(Kit.SLOT * 10))
	var deep := Kit.panel("FDeepFrame")
	deep.add_child(scroll)
	_details.add_child(deep)
	scroll.add_child(_items)
	for c in _items.get_children():
		_items.remove_child(c)
		c.queue_free()
	var contents: Dictionary = model.lnet.get(selected, {})
	for it in contents.get("items", []):
		if not (it is Array and it.size() >= 2):
			continue
		var s := Slot.new()
		s.set_stack(str(it[0]), int(it[1]))
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		var q := str(it[2]) if it.size() > 2 else ""
		s.set_tip(Kit.pretty(str(it[0])) + (" (%s)" % q if q != "" else ""), [["%s in the network" % Kit.count_text(int(it[1]))]])
		_items.add_child(s)
	var cells := maxi(COLUMNS * 10, _items.get_child_count() + (COLUMNS - _items.get_child_count() % COLUMNS) % COLUMNS)
	for i in cells - _items.get_child_count():
		_items.add_child(Kit.empty_cell())


func _subheader(text: String) -> Control:
	var p := Kit.panel("FSubheader")
	p.add_child(Kit.label(text, "FHeading"))
	return p
