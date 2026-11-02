extends Control
## Factorio 2.1's Factoriopedia, laid out as the game draws it at 1920x1080 (896 x 940, centred):
##
## - The title bar: "Factoriopedia", then search, the Space Age toggle, pin, back / forward, close.
## - Left (424 wide): the item groups as two rows of six big tabs (the chosen one orange), under
##   them a deep frame of slots ten wide: the group's things in rows by subgroup, empty slots filling
##   each row and the frame.
## - Right: a dark strip with the page's icon and "Iron plate (Recipe/Item)" (every kind the page
##   covers), and under it the page: the entity's picture, a dark box of stats ("Stack size: 100",
##   "Rocket capacity: 1.0k (10 stacks)", the entity's speed, health, pollution, resistances), the
##   energy box ("Consumes electricity"), then Factorio's sections: Ingredients and Products (a slot
##   and "1 × Iron ore" per row, the crafting time under them), Made in and Used in (slot grids ten
##   wide), Alternative recipes and Recycling recipes (a slot and the name per row), Unlocked by
##   (technology cards). Everything listed links to its own page; back and forward go through the
##   history.
##
## The index (`pidx`) and the pages (`pedia`) come from the mod (pedia.lua) on request, names and
## icons from the player's install. Opened with its key (factorio_ui.gd), or Alt+click on anything
## in the world or a window (open_page).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const Info := preload("res://scripts/ui/factorio/info_text.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const TechSlot := preload("res://scripts/ui/factorio/tech_slot.gd")

signal close_requested
## The page's "Open in the technology screen" (and a click on an Unlocked by card).
signal open_technology(name: String)

const COLUMNS := 10
## Groups whose icon is one of core's category pictures (base/prototypes/item-groups.lua).
const CORE_GROUP_ICONS := {"enemies": "enemies", "environment": "environment", "tiles": "tiles-editor", "other": "unsorted"}
## Factorio's window at 1920x1080, 100%.
const WIDTH := 896
const HEIGHT := 940
const TOP := 70
const LEFT_WIDTH := 424
const TAB := 70
const PAGE_WIDTH := 422
## Slot rows the left frame shows (empty ones fill it).
const GRID_ROWS := 18
## A rocket lifts this much (grams; utility-constants' rocket_lift_weight).
const ROCKET_LIFT := 1000000.0
const STAT_BG := Color8(36, 35, 36)
const SECTION_LINE := Color8(36, 35, 36)
## The chosen group's tab and the shown thing's slot (measured on Factorio's).
const SELECTED_TAB := Color8(241, 191, 100)
const SELECTED_SLOT := Color8(255, 160, 0)


## A slot-sized button showing a thing's icon (and a count), linking to its page.
class LinkSlot extends Button:
	const K := preload("res://scripts/ui/factorio/kit.gd")
	const R := preload("res://scripts/ui/factorio/rich_text.gd")
	const I := preload("res://scripts/ui/factorio/info_text.gd")
	var kind := ""
	var thing := ""
	var amount := ""
	var tip_lines: Array = []

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		theme_type_variation = "FSlotButton"
		custom_minimum_size = K.pxv(K.SLOT, K.SLOT)
		texture_filter = K.ICON_FILTER

	func setup(new_kind: String, new_name: String, new_amount := "") -> void:
		kind = new_kind
		thing = new_name
		amount = new_amount
		tooltip_text = I.display_name(kind, thing)
		queue_redraw()

	func _draw() -> void:
		var t := R.icon(kind, thing)
		var side := float(K.px(32))
		var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
		if t != null:
			draw_texture_rect(t, rect, false)
		if amount != "":
			var f := K.font("bold")
			var fs := K.px(13)
			var w := f.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(size.x - w - K.px(3), size.y - K.px(4))
			draw_string_outline(f, at, amount, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, K.px(3), Color(0, 0, 0, 0.9))
			draw_string(f, at, amount, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, K.WHITE)

	func _make_custom_tooltip(_for_text: String) -> Object:
		return K.tooltip(I.display_name(kind, thing), tip_lines)


var model: UiModel
## What the page shows: kind ("item", "fluid", "entity", "recipe", "technology", "tile", "planet",
## "space-location", "quality") and name.
var kind := ""
var thing := ""

var _frame := Kit.panel("FFrame")
var _search: LineEdit
var _tabs := GridContainer.new()
var _grid := VBoxContainer.new()
var _page := VBoxContainer.new()
var _page_title: Label
var _page_icon := TextureRect.new()
var _page_scroll := ScrollContainer.new()
var _back: Button
var _forward: Button
var _group := ""
var _history: Array = []  # [[kind, name], ...]
var _at := -1
var _dirty := false
var _waiting := {}  # "kind/name" of pages the shown page needs


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_child(_frame)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	_frame.add_child(box)
	var bar := Kit.title_bar("Factoriopedia", true)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: close_requested.emit())
	_search = LineEdit.new()
	_search.placeholder_text = "Search"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Kit.pxv(200, 24)
	_search.visible = false
	_search.text_changed.connect(func(_t: String) -> void: _fill_grid())
	var glass := _title_button("Search", "icons/search.png", "Search (Ctrl+F)")
	glass.pressed.connect(toggle_search)
	var space_age := _title_button("SpaceAge", "icons/space-age.png", "Show Space Age content")
	space_age.toggle_mode = true
	space_age.button_pressed = true
	space_age.disabled = true  # the index already lists what the game has
	var pin := _title_button("Pin", "icons/mip/pin.png", "Pin")
	pin.disabled = true
	_back = _title_button("Back", "icons/mip/backward-arrow.png", "Back")
	_forward = _title_button("Forward", "icons/mip/forward-arrow.png", "Forward")
	_back.pressed.connect(func() -> void: _go(_at - 1))
	_forward.pressed.connect(func() -> void: _go(_at + 1))
	for c in [_search, glass, space_age, pin, _back, _forward]:
		bar.add_child(c)
		bar.move_child(c, bar.get_child_count() - 2)
	box.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(12))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(row)

	# Left: the tabs, then the slots.
	var left := Kit.panel("FDeepFrame")
	left.custom_minimum_size.x = Kit.px(LEFT_WIDTH)
	row.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 0)
	left.add_child(left_box)
	_tabs.columns = 6
	_tabs.add_theme_constant_override("h_separation", 0)
	_tabs.add_theme_constant_override("v_separation", 0)
	left_box.add_child(_tabs)
	var pane := Kit.panel("FTabPane")
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(pane)
	var deep: Array = Kit.deep_scroll(Kit.pxv(Kit.SLOT * COLUMNS + 12, Kit.SLOT * 4))
	(deep[0] as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	(deep[0] as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pane.add_child(deep[0])
	_grid.add_theme_constant_override("separation", 0)
	(deep[1] as ScrollContainer).add_child(_grid)

	# Right: the page's title strip and the page.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var strip := Kit.panel("FSubheader")
	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", Kit.px(6))
	_page_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page_icon.custom_minimum_size = Kit.pxv(24, 24)
	_page_icon.texture_filter = Kit.ICON_FILTER
	strip_row.add_child(_page_icon)
	_page_title = Kit.label("", "FHeading")
	_page_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_title.clip_text = true
	_page_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip_row.add_child(_page_title)
	strip.add_child(strip_row)
	right.add_child(strip)
	var shallow := Kit.panel("FShallowFrame")
	shallow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(shallow)
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.focus_mode = Control.FOCUS_NONE
	_page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shallow.add_child(_page_scroll)
	_page.add_theme_constant_override("separation", 0)
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_scroll.add_child(_page)

	model.pedia_index_changed.connect(_on_index)
	model.pedia_page_received.connect(_on_page)
	_update_nav()


func _title_button(name: String, sprite: String, tip: String) -> Button:
	var b := Kit.close_button()
	b.name = name
	b.tooltip_text = tip
	var icon := GuiAssets.core_sprite(sprite)
	b.icon = icon
	if icon == null:
		b.text = {"Back": "<", "Forward": ">", "Search": "?", "Pin": "", "SpaceAge": ""}.get(name, "")
	return b


func toggle_search() -> void:
	_search.visible = not _search.visible
	if _search.visible:
		_search.grab_focus()
	else:
		_search.text = ""
		_fill_grid()


## Factorio's size and place: centred, 70 from the top, smaller screens shrink it.
func _layout() -> void:
	var view := size
	var w := minf(Kit.px(WIDTH), view.x - Kit.px(8))
	var h := minf(Kit.px(HEIGHT), view.y - Kit.px(TOP) - Kit.px(70))
	_frame.size = Vector2(w, h)
	_frame.position = Vector2(roundf((view.x - w) * 0.5), minf(Kit.px(TOP), maxf(0.0, view.y - h)))


func is_open() -> bool:
	return visible


func open(on: bool) -> void:
	visible = on
	if on:
		model.request_pedia_index()
		if _tabs.get_child_count() == 0:
			_on_index()
		if kind == "" and not model.pedia_index.is_empty():
			var first: Dictionary = model.pedia_index[0]
			show_page(str(first["kind"]), str(first["name"]))


## Opens it on a thing's page (Alt+click). An entity an item builds, and a recipe named after its
## product, open that item's page, as in Factorio.
func open_page(new_kind: String, name: String) -> void:
	open(true)
	show_page(new_kind, name)


## The page Factoriopedia lists a thing under: [kind, name].
func page_of(k: String, name: String) -> Array:
	if model.pedia_index.is_empty():
		return [k, name]
	var listed := _listed()
	if listed.has(k + "/" + name):
		return [k, name]
	for other in ["item", "fluid", "entity"]:
		if listed.has(other + "/" + name):
			return [other, name]
	return [k, name]


var _listed_cache := {}
var _listed_size := -1


func _listed() -> Dictionary:
	if _listed_size != model.pedia_index.size():
		_listed_size = model.pedia_index.size()
		_listed_cache.clear()
		for e in model.pedia_index:
			_listed_cache[str(e["kind"]) + "/" + str(e["name"])] = e
	return _listed_cache


func show_page(new_kind: String, name: String, remember := true) -> void:
	var p := page_of(new_kind, name)
	kind = str(p[0])
	thing = str(p[1])
	if remember:
		_history.resize(_at + 1)
		_history.append([kind, thing])
		_at = _history.size() - 1
		_update_nav()
	var entry: Dictionary = _listed().get(kind + "/" + thing, {})
	if not entry.is_empty() and str(entry["group"]) != _group:
		_group = str(entry["group"])
		_fill_tabs()
		_fill_grid()
	else:
		for row in grid_rows():
			for b in row_things(row):
				_mark(b)
	_build_page()
	_page_scroll.scroll_vertical = 0


func _go(i: int) -> void:
	if i < 0 or i >= _history.size():
		return
	_at = i
	_update_nav()
	show_page(str(_history[i][0]), str(_history[i][1]), false)


func _update_nav() -> void:
	if _back != null:
		_back.disabled = _at <= 0
		_forward.disabled = _at >= _history.size() - 1


func _process(_delta: float) -> void:
	if visible:
		_layout()
	if _dirty and visible:
		_dirty = false
		_build_page()


func _on_index() -> void:
	_listed_size = -1
	var groups: Array = []
	for g in model.pedia_groups:
		if g is Array and g.size() >= 1:
			groups.append(str(g[0]))
	if (_group == "" or not groups.has(_group)) and not groups.is_empty():
		_group = groups[0]
	# A page opened before the index came: its group's tab, and the page as the index lists it.
	if kind != "":
		var p := page_of(kind, thing)
		var entry: Dictionary = _listed().get(str(p[0]) + "/" + str(p[1]), {})
		if not entry.is_empty():
			_group = str(entry["group"])
		if str(p[0]) != kind:
			kind = str(p[0])
			_dirty = true
	_fill_tabs()
	_fill_grid()
	if visible and kind == "" and not model.pedia_index.is_empty():
		show_page(str(model.pedia_index[0]["kind"]), str(model.pedia_index[0]["name"]))


func _on_page(k: String, name: String) -> void:
	var key := k + "/" + name
	if (k == kind and name == thing) or _waiting.has(key):
		_dirty = true


# --- the left side ------------------------------------------------------------------------------

## The groups Factoriopedia has tabs for (technologies have pages but no tab, as in Factorio).
func _tab_groups() -> Array:
	var out: Array = []
	for g in model.pedia_groups:
		if g is Array and g.size() >= 1 and str(g[0]) != "technologies":
			out.append(str(g[0]))
	return out


func _fill_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	var groups := _tab_groups()
	for group in groups:
		var b := Button.new()
		b.theme_type_variation = "FTab"
		b.toggle_mode = true
		b.button_pressed = group == _group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(TAB, TAB)
		b.tooltip_text = Kit.group_name(group)
		for st in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, _flat(SELECTED_TAB))
		var icon := GuiAssets.group_icon(group)
		if icon == null and CORE_GROUP_ICONS.has(group):
			icon = GuiAssets.core_sprite("icons/category/%s.png" % CORE_GROUP_ICONS[group])
		if icon != null:
			b.icon = icon
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.add_theme_constant_override("icon_max_width", Kit.px(64))
		else:
			b.text = b.tooltip_text
			b.clip_text = true
		var pick := func() -> void:
			_group = group
			_search.text = ""
			for t in _tabs.get_children():
				if t is Button:
					(t as Button).set_pressed_no_signal(t == b)
			_fill_grid()
		b.pressed.connect(pick)
		_tabs.add_child(b)
	# Factorio fills the last tab row with an empty recess.
	var rest := (6 - groups.size() % 6) % 6
	for i in rest:
		var blank := Kit.panel("FDeepFrame")
		blank.custom_minimum_size = Kit.pxv(TAB, TAB)
		_tabs.add_child(blank)


## The selected group's things in rows by subgroup (each row ten wide, filled with empty slots),
## or everything matching the search; empty rows fill the frame.
func _fill_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var query := _search.text.strip_edges().to_lower() if _search != null else ""
	var row: GridContainer = null
	var sub := ""
	var n := 0
	var rows := 0
	for e in model.pedia_index:
		if query != "":
			var shown := Info.display_name(str(e["kind"]), str(e["name"])).to_lower()
			if not (shown.contains(query) or str(e["name"]).contains(query)):
				continue
		elif str(e["group"]) != _group:
			continue
		if row == null or (query == "" and str(e["sub"]) != sub):
			if row != null:
				rows += _pad_row(row)
			sub = str(e["sub"])
			row = Kit.slot_grid(COLUMNS)
			_grid.add_child(row)
		var b := LinkSlot.new()
		b.setup(str(e["kind"]), str(e["name"]))
		b.pressed.connect(show_page.bind(str(e["kind"]), str(e["name"])))
		_mark(b)
		row.add_child(b)
		n += 1
		if n >= 600:
			break
	if row != null:
		rows += _pad_row(row)
	if model.pedia_index.is_empty():
		var l := Kit.label("Waiting for the game's prototypes…")
		l.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_grid.add_child(l)
		return
	if rows < GRID_ROWS:
		var filler := Kit.slot_grid(COLUMNS)
		filler.name = "Filler"
		for i in (GRID_ROWS - rows) * COLUMNS:
			filler.add_child(Kit.empty_cell())
		_grid.add_child(filler)


## Fills a row's last line with empty slots; returns how many lines it has.
static func _pad_row(row: GridContainer) -> int:
	for i in (COLUMNS - row.get_child_count() % COLUMNS) % COLUMNS:
		row.add_child(Kit.empty_cell())
	return ceili(row.get_child_count() / float(COLUMNS))


## Factorio's orange slot for the thing the page shows.
func _mark(b: LinkSlot) -> void:
	if b.kind == kind and b.thing == thing:
		b.add_theme_stylebox_override("normal", _flat(SELECTED_SLOT))
	else:
		b.remove_theme_stylebox_override("normal")


static func _flat(c: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.border_color = Color8(25, 24, 25)
	st.set_border_width_all(1)
	return st


## The rows of things (not the empty filler) in the grid.
func grid_rows() -> Array:
	return _grid.get_children().filter(func(c) -> bool: return c is GridContainer and c.name != "Filler")


## The things (LinkSlots) in a grid row.
static func row_things(row: Control) -> Array:
	return row.get_children().filter(func(c) -> bool: return c is LinkSlot)


# --- the page -------------------------------------------------------------------------------------

func _clear_page() -> void:
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()


## Every kind of page this one covers, Factorio's "(Recipe/Item/Entity)".
func _kinds_text(d: Dictionary) -> String:
	var kinds: Array = []
	match kind:
		"item":
			if _list(d.get("made")).has(thing):
				kinds.append("Recipe")
			kinds.append("Item")
			if d.get("entity") is Dictionary:
				kinds.append("Entity")
			elif d.has("tile"):
				kinds.append("Tile")
		"fluid":
			if _list(d.get("made")).has(thing):
				kinds.append("Recipe")
			kinds.append("Fluid")
		"space-location":
			kinds.append("Space location")
		_:
			kinds.append(kind.capitalize())
	return "/".join(kinds)


## Rebuilds the page from what is known; pages it needs (a recipe's ingredients) are asked for
## and fill in when they arrive.
func _build_page() -> void:
	_clear_page()
	_waiting.clear()
	if kind == "":
		_page_title.text = ""
		_page_icon.texture = null
		return
	var page := model.pedia_page(kind, thing)
	var d: Dictionary = page.get("d", {})
	_page_icon.texture = RichText.icon(kind, thing)
	# Factorio names a planet's page by the planet alone.
	var kinds := _kinds_text(d) if not kind in ["planet", "space-location"] else ""
	_page_title.text = Info.display_name(kind, thing) + (" (%s)" % kinds if kinds != "" else "")
	if page.is_empty():
		_section("").add_child(_muted("Loading…"))
		return
	if not page.get("found", false):
		_section("").add_child(_muted("The game has no such thing."))
		return
	match kind:
		"item":
			_item_page(d)
		"fluid":
			_fluid_page(d)
		"entity":
			_entity_page(d)
		"recipe":
			_recipe_parts(thing, d)
			_tech_cards("Unlocked by", d.get("unlocked", []))
		"technology":
			_technology_page(d)
		"tile":
			_tile_page(d)
		"planet", "space-location":
			_location_page(d)
		"quality":
			_quality_page(d)
	var desc := Info.description(kind, thing) if not kind in ["planet", "space-location"] else ""
	if desc != "":
		var dl := Kit.label(desc)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD
		dl.custom_minimum_size.x = Kit.px(PAGE_WIDTH - 24)
		_section("").add_child(dl)


func _item_page(d: Dictionary) -> void:
	var lines: Array = []
	if d.get("entity") is Dictionary:
		var e: Dictionary = d["entity"]
		_picture()
		lines = _entity_stats(e)
		lines.append_array(_item_stats(d))
		lines.append_array(_resistances(e))
		_stat_box(lines)
		_energy_box(e)
	else:
		lines = Info.item_lines(d.duplicate())
		lines.append_array(_rocket_lines(d))
		_stat_box(lines)
	var made: Array = _list(d.get("made"))
	var own := thing if made.has(thing) else ""
	if own != "":
		_recipe_parts(own, model.pedia_data("recipe", own))
	_slot_grid("Used in", "recipe", d.get("used", []))
	if d.get("entity") is Dictionary:
		var e: Dictionary = d["entity"]
		_slot_grid("Can craft", "recipe", e.get("recipes", []))
		_slot_grid("Can mine", "entity", e.get("can_mine", []))
		_slot_grid("Accepted science packs", "item", e.get("packs", []))
	_slot_grid("Mined from", "entity", d.get("mined", []))
	_name_rows("Alternative recipes", "recipe", made.filter(func(r) -> bool: return str(r) != own))
	_name_rows("Recycling recipes", "recipe", d.get("recycle", []))
	if d.has("tile"):
		_name_rows("Places", "tile", [d["tile"]])
	if d.has("burnt"):
		_name_rows("Burnt result", "item", [d["burnt"]])
	if d.has("rocket"):
		_amount_rows("Rocket launch products", d["rocket"])
	if own != "":
		_tech_cards("Unlocked by", model.pedia_data("recipe", own).get("unlocked", []))


func _fluid_page(d: Dictionary) -> void:
	# Factorio's fluid page (factoriopedia_fluid.png): no stats box (the fuel value only when it
	# burns), Used in, then every recipe making it as Alternative recipes.
	if d.has("fuel"):
		_stat_box([["Fuel value: %s" % Info.joules(float(d["fuel"]))]])
	var made: Array = _list(d.get("made"))
	var own := thing if made.has(thing) else ""
	if own != "":
		_recipe_parts(own, model.pedia_data("recipe", own))
	_slot_grid("Used in", "recipe", d.get("used", []))
	_name_rows("Alternative recipes", "recipe", made.filter(func(r) -> bool: return str(r) != own))
	_slot_grid("Found in", "tile", d.get("tiles", []))
	_slot_grid("Extracted by", "entity", d.get("pumped", []))
	_slot_grid("Mined from", "entity", d.get("mined", []))


func _entity_page(d: Dictionary) -> void:
	_picture()
	var lines := _entity_stats(d)
	lines.append_array(_resistances(d))
	_stat_box(lines)
	_energy_box(d)
	if not d.get("mine", []).is_empty():
		var sec := _amount_rows("Mining results", d["mine"])
		if d.has("mtime") and sec != null:
			_time_line(sec, float(d["mtime"]), "Mining time")
	_slot_grid("Can craft", "recipe", d.get("recipes", []))
	_slot_grid("Can mine", "entity", d.get("can_mine", []))
	_slot_grid("Items to place it", "item", d.get("items", []))
	if d.has("next"):
		_name_rows("Upgrades to", "entity", [d["next"]])


func _technology_page(d: Dictionary) -> void:
	var lines: Array = []
	var level := int(d.get("level", 1))
	var max_level := int(d.get("max_level", 1))
	if max_level >= 4294967295 or max_level == -1:
		lines.append(["Level: %d (infinite)" % level])
	elif max_level > 1:
		lines.append(["Level: %d of %d" % [level, max_level]])
	if d.get("trigger") is Array and not (d["trigger"] as Array).is_empty():
		lines.append(["Research trigger: %s" % Info.trigger_text(d["trigger"], "")])
	else:
		var count := str(d["formula"]) if str(d.get("formula", "")) != "" else Kit.count_text(int(d.get("count", 1)))
		lines.append(["Unit count: %s" % count])
		lines.append(["Time per unit: %s" % Info.seconds(float(d.get("time", 0)))])
	if float(d.get("saved", 0)) > 0.0:
		lines.append(["Progress: %d%%" % roundi(float(d["saved"]) * 100.0)])
	_stat_box(lines)
	var cost: Array = []
	for c in d.get("cost", []):
		cost.append(["item", str(c[0]), float(c[1])])
	_amount_rows("Cost per unit", cost)
	var unlocks: Array = []
	var other: Array = []
	for e in d.get("effects", []):
		if e is Array and e.size() >= 2:
			if str(e[0]) == "unlock-recipe":
				unlocks.append(str(e[1]))
			else:
				other.append(Info.effect_line(e))
	_slot_grid("Unlocks recipes", "recipe", unlocks)
	if not other.is_empty():
		var sec := _section("Effects")
		for line in other:
			sec.add_child(_line(line))
	_tech_cards("Required technologies", d.get("pre", []))
	_tech_cards("Required by", d.get("succ", []))
	var b := Button.new()
	b.text = "Open in the technology screen"
	b.focus_mode = Control.FOCUS_NONE
	var t := thing
	b.pressed.connect(func() -> void: open_technology.emit(t))
	_section("").add_child(b)


func _tile_page(d: Dictionary) -> void:
	var lines: Array = []
	if d.has("walk"):
		lines.append(["Walking speed: %s%%" % Info.num(float(d["walk"]) * 100.0)])
	if d.has("friction"):
		lines.append(["Vehicle friction: %s%%" % Info.num(float(d["friction"]) * 100.0)])
	if d.get("absorb") is Dictionary:
		for p in d["absorb"]:
			lines.append(["%s absorption: %s/m" % [Kit.pretty(str(p)), Info.num(float(d["absorb"][p]))]])
	if d.has("foundation"):
		lines.append(["Foundation: space platforms"])
	_stat_box(lines)
	if d.has("fluid"):
		_name_rows("Offshore pumps give", "fluid", [d["fluid"]])
	_slot_grid("Placed by", "item", d.get("items", []))
	if not d.get("mine", []).is_empty():
		_amount_rows("Mining results", d["mine"])


func _location_page(d: Dictionary) -> void:
	# Factorio's planet page: the description heads the stats box, no picture.
	var lines: Array = []
	var desc := Info.description(kind, thing)
	if desc != "":
		lines.append([desc])
	var props: Dictionary = d.get("props", {}) if d.get("props") is Dictionary else {}
	for p in ["gravity", "pressure", "magnetic-field", "solar-power", "day-night-cycle"]:
		if props.has(p):
			var spec: Array = Info.PROPERTIES[p]
			lines.append(["%s: %s %s" % [spec[0], Info.num(float(props[p]) * float(spec[2])), spec[1]]])
	for p in props:
		if not Info.PROPERTIES.has(p):
			lines.append(["%s: %s" % [Kit.pretty(str(p)), Info.num(float(props[p]))]])
	if d.has("solar") and float(d["solar"]) > 0.0:
		lines.append(["Solar power in space: %s%%" % Info.num(float(d["solar"]))])
	_stat_box(lines)
	var links: Array = []
	var lengths: Array = []
	for l in d.get("links", []):
		if l is Array and l.size() >= 2:
			links.append(str(l[0]))
			lengths.append("%s km" % Kit.count_text(int(l[1])))
	_slot_grid("Connections", "planet", links)
	if not links.is_empty():
		var grid := _last_section().get_child(1)
		for i in mini(links.size(), grid.get_child_count()):
			var b := grid.get_child(i) as LinkSlot
			b.tip_lines = [[lengths[i]]]


func _quality_page(d: Dictionary) -> void:
	var lines: Array = [["Level: %d" % int(d.get("level", 0))]]
	if d.has("next"):
		lines.append(["Next quality: %s (%s%%)" % [Info.display_name("quality", str(d["next"])), Info.num(float(d.get("prob", 0)) * 100.0)]])
	var mult: Dictionary = d.get("mult", {}) if d.get("mult") is Dictionary else {}
	for k in mult:
		if float(mult[k]) != 1.0:
			lines.append(["%s: ×%s" % [str(k).replace("_multiplier", "").replace("_", " ").capitalize(), Info.num(float(mult[k]))]])
	_stat_box(lines)


# --- page parts -----------------------------------------------------------------------------------

## The entity's lines in Factoriopedia's order: its speeds, "Base health", pollution and the rest,
## without the energy (the energy box) and resistances (listed last).
func _entity_stats(e: Dictionary) -> Array:
	var out: Array = []
	var health_at := 0
	for line in Info.entity_lines(e):
		var text := str(line[0]) if line is Array else str(line)
		if text.begins_with("Energy consumption") or text.begins_with("Drain:") or text.begins_with("Health:") or text.begins_with("  "):
			continue
		if text.contains("speed:") or text.begins_with("Speed:"):
			health_at = out.size() + 1
		out.append(line)
	if e.has("hp"):
		out.insert(health_at, ["Base health: %s" % Info.num(float(e["hp"]))])
	return out


func _item_stats(d: Dictionary) -> Array:
	var out: Array = []
	if d.has("stack"):
		out.append(["Stack size: %d" % int(d["stack"])])
	out.append_array(_rocket_lines(d))
	return out


## "Rocket capacity: 1.0k (10 stacks)": how many a rocket lifts by the item's weight.
static func _rocket_lines(d: Dictionary) -> Array:
	var weight := float(d.get("weight", 0))
	if weight <= 0.0:
		return []
	var cap := floori(ROCKET_LIFT / weight)
	var text := "Rocket capacity: %s" % _short(cap)
	var stack := int(d.get("stack", 0))
	if stack > 0 and cap > stack:
		text += " (%s stacks)" % Info.num(cap / float(stack))
	return [[text]]


static func _short(n: int) -> String:
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)


func _resistances(e: Dictionary) -> Array:
	var out: Array = []
	for r in e.get("res", []):
		if r is Array and r.size() >= 3:
			var flat := float(r[1])
			var pct := float(r[2])
			var value := ("%s/%s%%" % [Info.num(flat), Info.num(pct)]) if flat != 0.0 else "%s%%" % Info.num(pct)
			out.append(["  •  %s: %s" % [Kit.pretty(str(r[0])), value]])
	if not out.is_empty():
		out.push_front(["Resistances"])
	return out


func _margin(l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", Kit.px(l))
	m.add_theme_constant_override("margin_top", Kit.px(t))
	m.add_theme_constant_override("margin_right", Kit.px(r))
	m.add_theme_constant_override("margin_bottom", Kit.px(b))
	return m


## A section of the page: its heading (none for ""), a dark line between it and the last one.
func _section(title: String) -> VBoxContainer:
	if _page.get_child_count() > 0:
		var line := ColorRect.new()
		line.color = SECTION_LINE
		line.custom_minimum_size.y = Kit.px(2)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(line)
	var m := _margin(12, 10, 12, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	m.add_child(box)
	if title != "":
		var h := Kit.label(title, "FHeading")
		box.add_child(h)
	_page.add_child(m)
	return box


## The last section's box.
func _last_section() -> VBoxContainer:
	for i in range(_page.get_child_count() - 1, -1, -1):
		var c := _page.get_child(i)
		if c is MarginContainer and c.get_child(0) is VBoxContainer:
			return c.get_child(0) as VBoxContainer
	return _section("")


## The entity's (or planet's) picture on Factorio's chequered background (its icon: the client has
## no entity pictures to draw).
func _picture() -> void:
	var m := _margin(12, 12, 12, 0)
	var pic := Control.new()
	pic.name = "Picture"
	pic.custom_minimum_size = Kit.pxv(PAGE_WIDTH - 24, 152)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := RichText.icon(kind, thing)
	var paint := func() -> void:
		var cell := float(Kit.px(38))
		var y := 0.0
		var row := 0
		while y < pic.size.y:
			var x := 0.0
			var col := 0
			while x < pic.size.x:
				var c := Color8(54, 54, 54) if (row + col) % 2 == 0 else Color8(46, 46, 46)
				pic.draw_rect(Rect2(x, y, minf(cell, pic.size.x - x), minf(cell, pic.size.y - y)), c)
				x += cell
				col += 1
			y += cell
			row += 1
		if tex != null:
			var side := minf(pic.size.y - Kit.px(24), float(Kit.px(112)))
			pic.draw_texture_rect(tex, Rect2((pic.size - Vector2(side, side)) * 0.5, Vector2(side, side)), false)
	pic.draw.connect(paint)
	m.add_child(pic)
	_page.add_child(m)


## A dark box of lines (stats; the energy box with its heading).
func _dark_box(lines: Array, heading: Control = null) -> void:
	if lines.is_empty():
		return
	var m := _margin(12, 12, 12, 4)
	var p := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = STAT_BG
	bg.set_content_margin_all(Kit.px(8))
	p.add_theme_stylebox_override("panel", bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	if heading != null:
		box.add_child(heading)
		var rule := ColorRect.new()
		rule.color = Color8(62, 62, 62)
		rule.custom_minimum_size.y = 1
		box.add_child(rule)
	for line in lines:
		var row := _line(line)
		box.add_child(row)
	p.add_child(box)
	m.add_child(p)
	_page.add_child(m)


func _stat_box(lines: Array) -> void:
	_dark_box(lines)


## Factoriopedia's energy box: "Consumes electricity" (or burnable fuel, heat, fluid) with the
## maximum and minimum consumption.
func _energy_box(e: Dictionary) -> void:
	if not e.has("energy"):
		return
	var etype := str(e.get("etype", "electric"))
	var titles := {"electric": "Consumes electricity", "burner": "Consumes burnable fuel", "heat": "Consumes heat",
		"fluid": "Consumes fluid", "void": "Consumes nothing"}
	var lines: Array = [["Max. consumption: %s" % Info.watts(float(e["energy"]))]]
	if e.has("drain") and float(e["drain"]) > 0.0:
		lines.append(["Min. consumption: %s" % Info.watts(float(e["drain"]))])
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Kit.px(4))
	var icon := TextureRect.new()
	var sprite := "icons/tooltips/tooltip-category-electricity.png" if etype == "electric" else "icons/tooltips/tooltip-category-consumes.png"
	# The tooltip category icons hold their mipmaps side by side: the first is the full one.
	var sheet := GuiAssets.core_sprite(sprite)
	if sheet != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0, 0, sheet.get_height() * (0.8 if etype == "electric" else 1.0), sheet.get_height())
		icon.texture = atlas
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Kit.pxv(16, 16)
	head.add_child(icon)
	head.add_child(Kit.label(str(titles.get(etype, "Consumes energy")), "FHeading"))
	_dark_box(lines, head)


## One stat line: the label part in bold ("Stack size:"), the rest plain.
func _line(line) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var text := str(line[0]) if line is Array else str(line)
	var color: Variant = line[2] if line is Array and line.size() > 2 and line[2] is Color else null
	if text == "Resistances":
		var r := Kit.label(text)
		r.add_theme_font_override("font", Kit.font("bold"))
		row.add_child(r)
		return row
	for l in Kit.key_value_labels(text, color):
		if text.length() > 60:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.custom_minimum_size.x = Kit.px(PAGE_WIDTH - 60)
		row.add_child(l)
	return row


## Ingredients, the crafting time and Products of a recipe, then Made in (asked for when unknown).
func _recipe_parts(recipe: String, d: Dictionary) -> void:
	if d.is_empty():
		_waiting["recipe/" + recipe] = true
		model.pedia_page("recipe", recipe)
		_section("Ingredients").add_child(_muted("Loading…"))
		return
	var ing := _amount_rows("Ingredients", d.get("ing", []))
	if ing == null:
		ing = _section("Ingredients")
	_time_line(ing, float(d.get("time", 0.5)), "Crafting time")
	_amount_rows("Products", d.get("prod", []))
	_slot_grid("Made in", "entity", d.get("made_in", []))


## The rule and "⏱ 0.5 s Crafting time" under a list.
func _time_line(sec: VBoxContainer, seconds: float, what: String) -> void:
	var rule := ColorRect.new()
	rule.color = SECTION_LINE
	rule.custom_minimum_size.y = 1
	sec.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(2))
	var pad := Control.new()
	pad.custom_minimum_size.x = Kit.px(36)
	row.add_child(pad)
	var clock := TextureRect.new()
	clock.texture = GuiAssets.core_sprite("clock-icon.png")
	clock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	clock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	clock.custom_minimum_size = Kit.pxv(14, 14)
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(clock)
	var t := Kit.label("%s s" % Info.num(seconds))
	t.add_theme_font_override("font", Kit.font("bold"))
	row.add_child(t)
	row.add_child(Kit.label(" " + what))
	sec.add_child(row)


## A section of [type, name, amount] rows: a slot and "2 × Steel plate". Returns the section.
func _amount_rows(title: String, rows) -> VBoxContainer:
	var list := _list(rows)
	if list.is_empty():
		return null
	var sec := _section(title)
	for p in list:
		if not (p is Array and p.size() >= 3):
			continue
		var type := str(p[0])
		var n := str(p[1])
		var target := page_of(type if type == "fluid" else "item", n)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(8))
		var b := LinkSlot.new()
		b.setup(str(target[0]), n)
		b.pressed.connect(show_page.bind(str(target[0]), n))
		row.add_child(b)
		var amount := Kit.label(Info.num(float(p[2])) + " × ")
		amount.add_theme_font_override("font", Kit.font("bold"))
		amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(amount)
		var l := Kit.label(Info.display_name(str(target[0]), n))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
		sec.add_child(row)
	return sec


## A list from a page: Factorio's table_to_json writes an empty one as {} (seen on the real server).
static func _list(v) -> Array:
	return v if v is Array else []


## A section of slots ten wide, the last row filled with empty slots.
func _slot_grid(title: String, link_kind: String, list) -> void:
	var names := _list(list)
	if names.is_empty():
		return
	var sec := _section(title)
	var grid := Kit.slot_grid(COLUMNS)
	for n in names:
		var target := page_of(link_kind, str(n))
		var b := LinkSlot.new()
		b.setup(str(target[0]), str(n))
		b.pressed.connect(show_page.bind(str(target[0]), str(n)))
		grid.add_child(b)
	for i in (COLUMNS - names.size() % COLUMNS) % COLUMNS:
		grid.add_child(Kit.empty_cell())
	sec.add_child(grid)


## A section of rows: a slot and the thing's name.
func _name_rows(title: String, link_kind: String, list) -> void:
	var names := _list(list)
	if names.is_empty():
		return
	var sec := _section(title)
	for n in names:
		sec.add_child(_name_row(link_kind, str(n), ""))


func _name_row(link_kind: String, n: String, text: String) -> Control:
	var target := page_of(link_kind, n)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(8))
	var b := LinkSlot.new()
	b.setup(str(target[0]), n)
	b.pressed.connect(show_page.bind(str(target[0]), n))
	row.add_child(b)
	var l := Kit.label(text if text != "" else Info.display_name(str(target[0]), n))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return row


## Technologies as Factorio's cards ("Unlocked by", required ones); a click opens their page.
func _tech_cards(title: String, list) -> void:
	var techs := _list(list)
	if techs.is_empty():
		return
	var sec := _section(title)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", Kit.px(4))
	flow.add_theme_constant_override("v_separation", Kit.px(4))
	for t in techs:
		var card := TechSlot.new()
		var info: Dictionary = model.techs.get(str(t), {})
		var packs: Array = []
		for ing in info.get("ingredients", []):
			if ing is Array and ing.size() >= 1:
				packs.append(str(ing[0]))
		card.setup(str(t), int(info.get("state", 1)), packs, false)
		card.toggle_mode = false
		card.name = "Tech_" + str(t)
		card.pressed.connect(show_page.bind("technology", str(t)))
		flow.add_child(card)
	sec.add_child(flow)


func _muted(text: String) -> Label:
	var l := Kit.label(text)
	l.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	return l
