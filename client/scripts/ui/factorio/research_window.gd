extends Control
## Factorio 2.1's technology screen (T), over the whole screen with the world blurred behind it:
##
## - Left (540 wide): "Research queue", seven technology slots (the first with the progress);
##   "<Name> (<state>)" over the selected technology's details: its big card, Cost (each pack per
##   unit, the time per unit, × units), Effects (the recipes it unlocks, bonuses) and its
##   description, with Start research / Add to queue (or Cancel) at the bottom right; then "List of
##   technologies", every technology seven to a row (available, then not yet available, then
##   researched), with a search.
## - Right: "Technology tree" with back / forward (the technologies selected before) and close, a
##   "Show only essential technologies" box, and the tree around the selected technology: every
##   technology it needs above it, what it opens up under it, joined by lines; the selected one drawn
##   large in the middle.
##
## From the mod's `techs` and `rs` (ui_model.gd). Clicking a technology anywhere selects it; the
## buttons send `research` and `research_cancel`. Trigger technologies show their task ("Craft 50
## Iron plate"), infinite ones their level and cost formula, a stopped one its kept progress.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const TechSlot := preload("res://scripts/ui/factorio/tech_slot.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const Info := preload("res://scripts/ui/factorio/info_text.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

signal close_requested

## Factorio's layout at 1920x1080, 100% (GUI pixels).
const LEFT_WIDTH := 540
const QUEUE_SLOTS := 7
const LIST_COLUMNS := 7
const CARD := Vector2(72, 100)
const BIG_CARD := Vector2(136, 200)
## Between technology slots in the tree, as measured on Factorio's (5 between neighbours, 25
## between rows, where the lines run).
const GAP := Vector2(5, 25)
## Lines in one gap between rows are this far apart.
const LANE := 4
const STATE_NAMES := ["Not available", "Available", "Researched"]


## The tree's lines, drawn under the slots: Factorio's thin grey (137, 137, 137) orthogonal lines,
## each in its own lane, no arrows.
class TreeView extends Control:
	const LINE := Color8(137, 137, 137)
	var lines: Array = []  # [PackedVector2Array, Color]

	func _draw() -> void:
		for l in lines:
			draw_polyline(l[0], l[1], 1.0)


var model: UiModel
## The technology shown on the left and in the middle of the tree.
var selected := ""
## "Show only essential technologies".
var essential_only := false

var _left := Kit.panel("FFrame")
var _right := Kit.panel("FFrame")
var _queue_box := HBoxContainer.new()
var _title: Label
var _details := HBoxContainer.new()
var _list := GridContainer.new()
var _list_scroll: ScrollContainer
var _tree := TreeView.new()
var _tree_scroll := ScrollContainer.new()
var _essential: CheckBox
## tech -> TechSlot in the list of technologies, and in the tree.
var _slots := {}
var _tree_slots := {}
var _list_sig := ""
var _tree_key := ""
var _search := LineEdit.new()
var _history: Array = []
var _history_at := -1
var _back: Button
var _forward: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = MenuKit.theme()
	visible = false
	# The world behind, blurred as Factorio's technology screen does (the HUD with it).
	var blur := ColorRect.new()
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen: hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 c = textureLod(screen, SCREEN_UV, 3.5).rgb;
	COLOR = vec4(c * 0.8, 1.0);
}"""
	mat.shader = sh
	blur.material = mat
	add_child(blur)

	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	_left.custom_minimum_size.x = Kit.px(LEFT_WIDTH)
	row.add_child(_left)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Only the title bar and the frame's edge are drawn: the tree lies over the blurred world.
	var see_through := StyleBoxFlat.new()
	see_through.bg_color = Color(0, 0, 0, 0)
	see_through.border_color = Color8(49, 48, 49)
	see_through.set_border_width_all(Kit.px(4))
	see_through.set_content_margin_all(Kit.px(4))
	_right.add_theme_stylebox_override("panel", see_through)
	row.add_child(_right)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", Kit.px(8))
	_left.add_child(left)
	left.add_child(Kit.label("Research queue", "FCaption"))
	var queue_frame := Kit.panel("FDeepFrame")
	_queue_box.add_theme_constant_override("separation", 0)
	_queue_box.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_frame.add_child(_queue_box)
	left.add_child(queue_frame)
	_title = Kit.label("", "FCaption")
	left.add_child(_title)
	var details_frame := Kit.panel("FDeepFrame")
	details_frame.custom_minimum_size.y = Kit.px(BIG_CARD.y + 52)
	_details.add_theme_constant_override("separation", Kit.px(8))
	details_frame.add_child(_details)
	left.add_child(details_frame)
	var list_head := HBoxContainer.new()
	var list_title := Kit.label("List of technologies", "FCaption")
	list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_head.add_child(list_title)
	_search.placeholder_text = "Search"
	_search.custom_minimum_size = Kit.pxv(180, 24)
	_search.visible = false
	_search.text_changed.connect(func(_t: String) -> void: _refresh_tree())
	list_head.add_child(_search)
	var glass := Kit.close_button()
	glass.name = "Search"
	glass.tooltip_text = "Search (Ctrl+F)"
	var icon := GuiAssets.core_sprite("icons/search.png")
	if icon != null:
		glass.icon = icon
	glass.pressed.connect(toggle_search)
	list_head.add_child(glass)
	left.add_child(list_head)
	var deep: Array = Kit.deep_scroll(Kit.pxv(LIST_COLUMNS * CARD.x, 100))
	(deep[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(deep[0])
	_list_scroll = deep[1]
	_list.columns = LIST_COLUMNS
	_list.add_theme_constant_override("h_separation", 0)
	_list.add_theme_constant_override("v_separation", 0)
	_list_scroll.add_child(_list)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", Kit.px(4))
	_right.add_child(right)
	var bar_frame := PanelContainer.new()
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color8(49, 48, 49)
	bar_bg.content_margin_left = Kit.px(8)
	bar_bg.content_margin_right = Kit.px(4)
	bar_bg.content_margin_bottom = Kit.px(4)
	bar_frame.add_theme_stylebox_override("panel", bar_bg)
	var bar := Kit.title_bar("Technology tree", true)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: close_requested.emit())
	_back = _frame_button("Back", "icons/mip/backward-arrow.png", go_back)
	_forward = _frame_button("Forward", "icons/mip/forward-arrow.png", go_forward)
	for b in [_back, _forward]:
		bar.add_child(b)
		bar.move_child(b, bar.get_child_count() - 2)
	bar_frame.add_child(bar)
	right.add_child(bar_frame)
	var tree_frame := Kit.panel("FDeepFrame")
	tree_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var clear := StyleBoxFlat.new()  # the blurred world shows through
	clear.bg_color = Color(0, 0, 0, 0.15)
	tree_frame.add_theme_stylebox_override("panel", clear)
	right.add_child(tree_frame)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_frame.add_child(stack)
	_tree_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tree_scroll.offset_top = Kit.px(36)
	_tree_scroll.focus_mode = Control.FOCUS_NONE
	stack.add_child(_tree_scroll)
	_tree.mouse_filter = Control.MOUSE_FILTER_PASS
	_tree_scroll.add_child(_tree)
	# Factorio's subheader strip across the top of the tree, the checkbox at its right.
	var strip := Kit.panel("FSubheader")
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.custom_minimum_size.y = Kit.px(36)
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	stack.add_child(strip)
	_essential = MenuKit.checkbox("Show only essential technologies", false)
	_essential.name = "Essential"
	_essential.size_flags_horizontal = Control.SIZE_SHRINK_END
	_essential.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_essential.toggled.connect(func(on: bool) -> void:
		essential_only = on
		_list_sig = ""
		_tree_key = ""
		refresh())
	strip.add_child(_essential)

	model.research_changed.connect(refresh)
	refresh()


func _frame_button(name: String, sprite: String, action: Callable) -> Button:
	var b := Kit.close_button()
	b.name = name
	b.tooltip_text = name
	var icon := GuiAssets.core_sprite(sprite)
	if icon != null:
		b.icon = icon
	b.pressed.connect(action)
	return b


func open(on: bool) -> void:
	visible = on
	if on:
		if selected == "" or not model.techs.has(selected):
			selected = _default_selection()
		refresh()
		_center_on.call_deferred(selected)


func is_open() -> bool:
	return visible


func toggle_search() -> void:
	_search.visible = not _search.visible
	if _search.visible:
		_search.grab_focus()
	else:
		_search.text = ""
		_refresh_tree()


## Deferred: the clicked slot may be one the refresh replaces. Remembered for back / forward.
func select(tech: String) -> void:
	if tech != selected:
		_history.resize(_history_at + 1)
		if selected != "" and (_history.is_empty() or _history[-1] != selected):
			_history.append(selected)
		_history.append(tech)
		_history_at = _history.size() - 1
	selected = tech
	refresh.call_deferred()
	_center_on.call_deferred(tech)


func go_back() -> void:
	if _history_at > 0:
		_history_at -= 1
		selected = str(_history[_history_at])
		refresh()
		_center_on.call_deferred(selected)


func go_forward() -> void:
	if _history_at >= 0 and _history_at < _history.size() - 1:
		_history_at += 1
		selected = str(_history[_history_at])
		refresh()
		_center_on.call_deferred(selected)


## Brings a technology into view in the tree (in the middle) and in the list.
func _center_on(tech: String) -> void:
	var s = _tree_slots.get(tech)
	if s != null and is_instance_valid(s):
		var c: Vector2 = (s as Control).position + (s as Control).size * 0.5
		_tree_scroll.scroll_horizontal = int(c.x - _tree_scroll.size.x * 0.5)
		_tree_scroll.scroll_vertical = int(c.y - _tree_scroll.size.y * 0.5)
	var l = _slots.get(tech)
	if l != null and is_instance_valid(l):
		_list_scroll.ensure_control_visible(l)


## Kept for the earlier name.
func _scroll_to(tech: String) -> void:
	_center_on(tech)


func refresh() -> void:
	# Closed, it waits for open(), which refreshes: research progress (`rs`) comes about once a second
	# and rebuilding the tree each time cost ~9 ms on the main thread.
	if not is_inside_tree() or not visible:
		return
	if selected == "" or not model.techs.has(selected):
		selected = _default_selection()
	_back.disabled = _history_at <= 0
	_forward.disabled = _history_at < 0 or _history_at >= _history.size() - 1
	_refresh_tree()
	_refresh_queue()
	_refresh_details()


## The research in progress, else the first available technology, else any.
func _default_selection() -> String:
	if model.research != "":
		return model.research
	for t in _sorted_techs():
		if int(model.techs[t]["state"]) == 1:
			return t
	var all := _sorted_techs()
	return all[0] if not all.is_empty() else ""


func _sorted_techs() -> Array:
	var names: Array = model.techs.keys()
	var before := func(a, b) -> bool:
		var oa := str(model.techs[a]["order"])
		var ob := str(model.techs[b]["order"])
		return oa < ob if oa != ob else str(a) < str(b)
	names.sort_custom(before)
	return names


func _shown(t: String) -> bool:
	return not essential_only or bool(model.techs[t].get("essential", true)) or t == selected


## Queue position (1 = being researched), or 0.
func _place(tech: String) -> int:
	if tech == model.research and tech != "":
		return 1
	var i := model.research_queue.find(tech)
	if i < 0:
		return 0
	return i + (2 if model.research != "" else 1)


func _refresh_tree() -> void:
	var sig := JSON.stringify(model.techs) + str(essential_only)
	if sig != _list_sig:
		_list_sig = sig
		_build_list()
	var key := sig + selected
	if key != _tree_key:
		_tree_key = key
		_build_tree()
	var query := _search.text.strip_edges().to_lower()
	for slots in [_slots, _tree_slots]:
		for t in slots:
			var s: TechSlot = slots[t]
			s.set_pressed_no_signal(t == selected)
			s.set_progress(model.research_progress if t == model.research else -1.0, _place(t))
			s.modulate.a = 1.0 if query == "" or _matches(t, query) else 0.25
	for t in _slots:
		(_slots[t] as Control).visible = query == "" or _matches(t, query)


## Factorio's list: available first, then not available yet, then researched, each by order.
func _build_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_slots.clear()
	for state in [1, 0, 2]:
		for t in _sorted_techs():
			if int(model.techs[t]["state"]) == state and _shown(t):
				var s := _tech_slot(t)
				_list.add_child(s)
				_slots[t] = s


## The tree around the selected technology: every prerequisite (all the way down) above it, the
## technologies that need it below it. Rows are by the longest way down to the selected one; each
## row is ordered by where what it leads to sits, so lines cross little.
func _build_tree() -> void:
	for child in _tree.get_children():
		_tree.remove_child(child)
		child.queue_free()
	_tree_slots.clear()
	if model.techs.is_empty() or selected == "":
		var l := Kit.label("The mod hasn't sent any technologies yet.")
		l.position = Kit.pxv(16, 48)
		_tree.add_child(l)
		_tree.custom_minimum_size = Kit.pxv(300, 60)
		_tree.lines = []
		_tree.queue_redraw()
		return
	# How far above the selected one each prerequisite sits (the longest chain).
	var up := {selected: 0}
	var todo: Array = [selected]
	while not todo.is_empty():
		var t: String = todo.pop_front()
		for p in model.techs[t]["prerequisites"]:
			var pn := str(p)
			if not model.techs.has(pn) or not _shown(pn):
				continue
			var d := int(up[t]) + 1
			if int(up.get(pn, -1)) < d:
				up[pn] = d
				todo.append(pn)
	var rows := {}
	for t in up:
		var r := -int(up[t])
		if not rows.has(r):
			rows[r] = []
		rows[r].append(t)
	var below: Array = []
	for t in required_by(selected):
		if _shown(t) and not up.has(t):
			below.append(t)
	if not below.is_empty():
		rows[1] = below
	var cell := Kit.pxv(CARD.x, CARD.y)
	var big := Kit.pxv(BIG_CARD.x, BIG_CARD.y)
	var gap := Kit.pxv(GAP.x, GAP.y)
	var keys: Array = rows.keys()
	keys.sort()
	# Order each row above by the mean place of what it leads to, from the selected one upwards.
	var x_of := {selected: 0.0}
	for r in range(-1, int(keys[0]) - 1, -1):
		if not rows.has(r):
			continue
		var list: Array = rows[r]
		var mean := {}
		for t in list:
			var xs: Array = []
			for other in x_of:
				if (model.techs[other]["prerequisites"] as Array).has(t):
					xs.append(float(x_of[other]))
			mean[t] = 0.0 if xs.is_empty() else xs.reduce(func(a, b): return a + b, 0.0) / xs.size()
		list.sort_custom(func(a, b) -> bool: return float(mean[a]) < float(mean[b]) if float(mean[a]) != float(mean[b]) else str(model.techs[a]["order"]) < str(model.techs[b]["order"]))
		for i in list.size():
			x_of[list[i]] = i - (list.size() - 1) * 0.5
	var widest := 1
	for r in keys:
		widest = maxi(widest, (rows[r] as Array).size())
	var margin := Kit.pxv(48, 40)
	var view := _tree_scroll.size if _tree_scroll.size.x > 0.0 else Kit.pxv(1300, 900)
	var width := maxf(margin.x * 2.0 + widest * (cell.x + gap.x) + big.x, view.x)
	var pos := {}
	var row_of := {}
	var row_span := {}  # row -> [top, bottom]
	var y := margin.y
	for r in keys:
		var list: Array = rows[r]
		var h := big.y if int(r) == 0 else cell.y
		var row_w := 0.0
		for t in list:
			row_w += (big.x if t == selected else cell.x) + gap.x
		row_w -= gap.x
		var x := (width - row_w) * 0.5
		for t in list:
			var sz := big if t == selected else cell
			var at := Vector2(x, y + (h - sz.y) * 0.5)
			pos[t] = Rect2(at, sz)
			row_of[t] = int(r)
			var s := _tech_slot(t)
			if t == selected:
				s.custom_minimum_size = sz
				s.big = true
			s.position = at
			s.size = sz
			_tree.add_child(s)
			_tree_slots[t] = s
			x += sz.x + gap.x
		row_span[int(r)] = [y, y + h]
		y += h + gap.y
	_tree.lines = _route(pos, row_of, row_span, keys)
	_tree.custom_minimum_size = Vector2(width, maxf(y + margin.y - gap.y, view.y))
	_tree.queue_redraw()


## Factorio's lines: out of the bottom of a prerequisite (several spread along it), along a lane of
## the gap under its row, down a free channel between the slots of the rows in between, along a lane
## of the gap over the technology that needs it and into its top (several spread along it).
func _route(pos: Dictionary, row_of: Dictionary, row_span: Dictionary, keys: Array) -> Array:
	var edges: Array = []  # [from, to]
	for t in pos:
		for p in model.techs[t]["prerequisites"]:
			if pos.has(str(p)) and int(row_of[str(p)]) < int(row_of[t]):
				edges.append([str(p), t])
	var outs := {}
	var ins := {}
	for e in edges:
		if not outs.has(e[0]):
			outs[e[0]] = []
		outs[e[0]].append(e)
		if not ins.has(e[1]):
			ins[e[1]] = []
		ins[e[1]].append(e)
	var cx := func(t) -> float: return (pos[t] as Rect2).get_center().x
	var spread := func(rect: Rect2, i: int, n: int) -> float:
		if n <= 1:
			return roundf(rect.get_center().x)
		var room := minf(rect.size.x - Kit.px(16), Kit.px(12) * (n - 1))
		return roundf(rect.get_center().x - room * 0.5 + room * i / (n - 1))
	var exit_x := {}
	var entry_x := {}
	for t in outs:
		var list: Array = outs[t]
		list.sort_custom(func(a, b) -> bool: return float(cx.call(a[1])) < float(cx.call(b[1])))
		for i in list.size():
			exit_x[list[i]] = spread.call(pos[t], i, list.size())
	for t in ins:
		var list: Array = ins[t]
		list.sort_custom(func(a, b) -> bool: return float(cx.call(a[0])) < float(cx.call(b[0])))
		for i in list.size():
			entry_x[list[i]] = spread.call(pos[t], i, list.size())
	var lane_count := {}  # gap above row r -> lanes used
	var lane := func(r: int) -> float:
		var top: float = float(row_span[r - 1][1]) if row_span.has(r - 1) else float(row_span[r][0]) - Kit.px(GAP.y)
		var bottom: float = float(row_span[r][0])
		var room := maxi(1, int((bottom - top - Kit.px(LANE) * 2) / Kit.px(LANE)) + 1)
		var k := int(lane_count.get(r, 0))
		lane_count[r] = k + 1
		return roundf(top + Kit.px(LANE) + Kit.px(LANE) * (k % room)) + 0.5
	var used_channels: Array = []
	var out: Array = []
	for e in edges:
		var a: Rect2 = pos[e[0]]
		var b: Rect2 = pos[e[1]]
		var ra := int(row_of[e[0]])
		var rb := int(row_of[e[1]])
		var x0: float = float(exit_x[e]) + 0.5
		var x1: float = float(entry_x[e]) + 0.5
		var pts := PackedVector2Array([Vector2(x0, a.end.y)])
		if rb == ra + 1:
			var ly: float = lane.call(rb)
			pts.append_array([Vector2(x0, ly), Vector2(x1, ly), Vector2(x1, b.position.y)])
		else:
			var y1: float = lane.call(ra + 1)
			var y2: float = lane.call(rb)
			var channel := _channel(x1, pos, row_of, ra, rb, used_channels)
			used_channels.append([channel, ra, rb])
			pts.append_array([Vector2(x0, y1), Vector2(channel, y1), Vector2(channel, y2), Vector2(x1, y2), Vector2(x1, b.position.y)])
		out.append([pts, TreeView.LINE])
	return out


## An x near `want` that passes no slot of the rows strictly between ra and rb, nor another long
## line over the same rows.
func _channel(want: float, pos: Dictionary, row_of: Dictionary, ra: int, rb: int, used: Array) -> float:
	var step := float(maxi(2, Kit.px(LANE)))
	for k in 400:
		var x := want + (ceilf(k / 2.0) * step * (1.0 if k % 2 == 1 else -1.0))
		var free := true
		for t in pos:
			var r := int(row_of[t])
			if r > ra and r < rb and (pos[t] as Rect2).grow(Kit.px(1)).has_point(Vector2(x, (pos[t] as Rect2).get_center().y)):
				free = false
				break
		if free:
			for u in used:
				if absf(float(u[0]) - x) < step * 0.5 and not (int(u[2]) <= ra or int(u[1]) >= rb):
					free = false
					break
		if free:
			return roundf(x) + 0.5
	return want


## The search finds a technology by its name or by what it unlocks.
func _matches(t: String, query: String) -> bool:
	if title_of(t).to_lower().contains(query) or t.contains(query):
		return true
	for e in model.techs[t].get("effects", []):
		if e is Array and e.size() >= 2 and str(e[0]) == "unlock-recipe" and Kit.recipe_name(str(e[1])).to_lower().contains(query):
			return true
	return false


## A technology's name; infinite and levelled ones by the level they are at ("Mining productivity 7").
func title_of(t: String) -> String:
	var info: Dictionary = model.techs.get(t, {})
	var max_level := int(info.get("max_level", 1))
	if max_level != 1 and int(info.get("level", 1)) > 1:
		var base := t
		var dash := t.rfind("-")
		if dash > 0 and t.substr(dash + 1).is_valid_int():
			base = t.substr(0, dash)
		return "%s %d" % [Kit.tech_name(base), int(info["level"])]
	return Kit.tech_name(t)


## The technologies that need this one.
func required_by(t: String) -> Array:
	var out: Array = []
	for other in _sorted_techs():
		if (model.techs[other]["prerequisites"] as Array).has(t):
			out.append(other)
	return out


func _tech_slot(t: String) -> TechSlot:
	var s := TechSlot.new()
	var info: Dictionary = model.techs[t]
	var packs: Array = []
	for ing in info["ingredients"]:
		if ing is Array and ing.size() >= 1:
			packs.append(str(ing[0]))
	s.setup(t, int(info["state"]), packs, false)
	s.title = title_of(t)
	var max_level := int(info.get("max_level", 1))
	s.level_text = "∞" if max_level == -1 else ""
	# Upgrades (a "-N" series of bonuses, not of recipes, or several levels) carry Factorio's level
	# badge; "Automation 2" doesn't.
	var dash := t.rfind("-")
	var series := dash > 0 and t.substr(dash + 1).is_valid_int()
	for e in info.get("effects", []):
		if e is Array and e.size() >= 1 and str(e[0]) == "unlock-recipe":
			series = false
	if series or max_level != 1:
		s.level = maxi(1, int(info.get("level", t.substr(dash + 1).to_int() if series else 1)))
	if max_level == -1:
		s.level_range = "%d - ∞" % s.level
	s.tip_lines = _cost_lines(info)
	s.tip_lines.append(["Click: select", "", Kit.DISABLED_TEXT])
	s.pressed.connect(select.bind(t))
	return s


func _cost_lines(info: Dictionary) -> Array:
	var lines: Array = []
	if str(info.get("trigger", "")) != "":
		var detail: Array = info.get("trigger_detail", [])
		lines.append([Info.trigger_text(detail, str(info["trigger"])), str(detail[1]) if detail.size() > 1 and str(detail[0]).ends_with("item") else ""])
	else:
		lines.append(["Cost:"])
		for ing in info["ingredients"]:
			if ing is Array and ing.size() >= 2:
				lines.append(["%s × %s" % [Kit.count_text(int(ing[1]) * int(info["count"])), Kit.pretty(str(ing[0]))], str(ing[0])])
		lines.append(["Time: %s" % _time_text(float(info["seconds"]) * int(info["count"]))])
	if float(info.get("saved", 0.0)) > 0.0:
		lines.append(["%d%% done" % roundi(float(info["saved"]) * 100.0), "", Kit.YELLOW_TEXT])
	var effects: Array = info.get("effects", [])
	if not effects.is_empty():
		lines.append(["Effects:"])
		for e in effects.slice(0, 8):
			if e is Array and e.size() >= 2:
				lines.append(Info.effect_line(e))
	return lines


static func _time_text(seconds: float) -> String:
	var s := roundi(seconds)
	if s < 60:
		return "%ds" % s
	if s < 3600:
		return "%dm %ds" % [s / 60, s % 60] if s % 60 != 0 else "%dm" % (s / 60)
	return "%dh %dm" % [s / 3600, (s % 3600) / 60]


## Factorio's queue: seven technology slots, the first being researched; empty places dark.
func _refresh_queue() -> void:
	for child in _queue_box.get_children():
		_queue_box.remove_child(child)
		child.queue_free()
	var queued: Array = []
	if model.research != "":
		queued.append(model.research)
	for q in model.research_queue:
		if not queued.has(str(q)) and model.techs.has(str(q)):
			queued.append(str(q))
	for i in QUEUE_SLOTS:
		if i < queued.size():
			var t: String = queued[i]
			var s := _tech_slot(t)
			s.name = "Queue_" + t
			s.set_pressed_no_signal(t == selected)
			s.set_progress(model.research_progress if t == model.research else -1.0, _place(t))
			_queue_box.add_child(s)
		else:
			var empty := Panel.new()
			empty.custom_minimum_size = Kit.pxv(CARD.x, CARD.y)
			var st := StyleBoxFlat.new()
			st.bg_color = Color8(31, 31, 31)
			st.border_color = Color8(20, 20, 20)
			st.set_border_width_all(Kit.px(2))
			empty.add_theme_stylebox_override("panel", st)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_queue_box.add_child(empty)


func _refresh_details() -> void:
	for child in _details.get_children():
		_details.remove_child(child)
		child.queue_free()
	if selected == "" or not model.techs.has(selected):
		_title.text = "Technology"
		_details.add_child(Kit.label("Select a technology."))
		return
	var info: Dictionary = model.techs[selected]
	var state := int(info["state"])
	var place := _place(selected)
	var status: String = STATE_NAMES[state]
	if place == 1:
		status = "Researching %d%%" % roundi(model.research_progress * 100.0)
	elif place > 1:
		status = "Queued"
	_title.text = "%s (%s)" % [title_of(selected), status]
	var big := _tech_slot(selected)
	big.custom_minimum_size = Kit.pxv(BIG_CARD.x, BIG_CARD.y)
	big.disabled = true
	big.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	big.set_progress(model.research_progress if selected == model.research else -1.0, place)
	_details.add_child(big)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", Kit.px(4))
	_details.add_child(col)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.focus_mode = Control.FOCUS_NONE
	col.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", Kit.px(6))
	scroll.add_child(v)

	var max_level := int(info.get("max_level", 1))
	if str(info.get("trigger", "")) != "":
		var detail: Array = info.get("trigger_detail", [])
		v.add_child(Kit.label("Unlocked by doing it", "FHeading"))
		var task := HBoxContainer.new()
		task.add_theme_constant_override("separation", Kit.px(6))
		if detail.size() > 1 and str(detail[1]) != "":
			task.add_child(_pack_slot(str(detail[1]), int(detail[2]) if detail.size() > 2 else 1))
		var tl := Kit.label(Info.trigger_text(detail, str(info["trigger"])))
		tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		task.add_child(tl)
		v.add_child(task)
	else:
		v.add_child(Kit.label("Cost", "FHeading"))
		# Factorio: each pack per unit in a row of slots, the time per unit, then × units.
		var cost_frame := Kit.panel("FDeepFrame")
		var cost := HBoxContainer.new()
		cost.add_theme_constant_override("separation", 0)
		for ing in info["ingredients"]:
			if ing is Array and ing.size() >= 2:
				cost.add_child(_pack_slot(str(ing[0]), int(ing[1])))
		var clock := TextureRect.new()
		clock.texture = GuiAssets.core_sprite("clock-icon.png")
		clock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		clock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		clock.custom_minimum_size = Kit.pxv(16, 16)
		clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cost.add_child(clock)
		var secs := Kit.label(str(snappedf(float(info["seconds"]), 0.1)).trim_suffix(".0"))
		secs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost.add_child(secs)
		var units := Kit.label("  × %d" % int(info["count"]))
		units.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		units.tooltip_text = "%d units × %ss = %s" % [int(info["count"]), str(snappedf(float(info["seconds"]), 0.1)), _time_text(float(info["seconds"]) * int(info["count"]))]
		units.mouse_filter = Control.MOUSE_FILTER_PASS
		cost.add_child(units)
		cost_frame.add_child(cost)
		v.add_child(cost_frame)
		if str(info.get("formula", "")) != "":
			var f := Kit.label("Units: %s (L: the level)" % str(info["formula"]))
			f.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
			v.add_child(f)
	if max_level == -1:
		var inf := Kit.label("Infinite technology: each level costs more")
		inf.add_theme_color_override("font_color", Kit.YELLOW_TEXT)
		v.add_child(inf)
	elif max_level > 1:
		v.add_child(Kit.label("Level %d of %d" % [int(info.get("level", 1)), max_level]))
	if float(info.get("saved", 0.0)) > 0.0 and selected != model.research:
		v.add_child(Kit.label("%d%% researched before it was stopped" % roundi(float(info["saved"]) * 100.0)))
	var unlocks := HFlowContainer.new()
	unlocks.add_theme_constant_override("h_separation", Kit.px(2))
	var bonuses: Array = []
	for e in info.get("effects", []):
		if e is Array and e.size() >= 2:
			if str(e[0]) == "unlock-recipe":
				var s := Slot.new()
				s.set_stack(str(e[1]), -1)
				s.set_tip(Kit.recipe_name(str(e[1])), [["Unlocked by this technology", "", Kit.DISABLED_TEXT]])
				unlocks.add_child(s)
			else:
				bonuses.append(Info.effect_line(e))
	if unlocks.get_child_count() > 0 or not bonuses.is_empty():
		v.add_child(Kit.label("Effects", "FHeading"))
		if unlocks.get_child_count() > 0:
			v.add_child(unlocks)
		for b in bonuses:
			v.add_child(Kit.label(str(b[0])))
	var about := Info.description("technology", selected)
	if about != "":
		var d := Kit.label(about)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = Kit.px(LEFT_WIDTH - BIG_CARD.x - 60)
		v.add_child(d)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", Kit.px(8))
	buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(buttons)
	if place > 0:
		var cancel := _dialog_button("Cancel research" if place == 1 else "Remove from queue", "FRedButton")
		cancel.pressed.connect(func() -> void: model.cancel_research(selected))
		buttons.add_child(cancel)
	if state != 2 and place == 0:
		var start := _dialog_button("Start research" if model.research == "" else "Add to queue", "")
		start.disabled = state == 0
		if state == 0:
			start.tooltip_text = "Research the required technologies first"
		start.pressed.connect(func() -> void: model.start_research(selected))
		buttons.add_child(start)


func _pack_slot(pack: String, n: int) -> Control:
	var s := Slot.new()
	s.set_stack(pack, n)
	s.set_tip(Kit.pretty(pack), [["%d per unit" % n]])
	return s


func _dialog_button(text: String, variation: String) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Kit.pxv(112, 28)
	return b


## Ctrl+F: the list's search.
func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if visible and k != null and k.pressed and k.ctrl_pressed and k.keycode == KEY_F:
		toggle_search()
		get_viewport().set_input_as_handled()
