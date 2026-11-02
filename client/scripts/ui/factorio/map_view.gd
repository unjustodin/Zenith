extends Control
## Factorio's map view (M): the charted map over the whole window, north up, with the character's
## arrow, the map tags (icon and name) and the layers of Factorio's map view settings (electric and
## logistic networks, turret coverage, train stop names, worker robots, rail signals, recipe icons;
## map_layers.gd), switched in a panel at the top right like Factorio's. The game keeps running
## underneath; the quickbar and other windows stay on top, as in Factorio.
##
##   drag (left or middle) or WASD / arrows: move the map (Shift: faster); the map stops following
##       the character until it is opened again
##   wheel: zoom about the mouse, in steps of √2 between 1/4 and 8 GUI pixels per tile; zooming in
##       past the closest zoom goes into the world there (Factorio 2.0's remote view: zoom_to_world)
##   right click or double click: create a tag there; right click on a tag: edit or delete it
##   M or Esc: close (Esc closes the tag dialog first)
##
## Factorio's surface switcher sits at the top left: a button per planet and space platform the
## mod lists (`surfs`); the map then shows that surface's charts and tags, centred on a planet's
## cargo landing pad (H23; the mod answers `lpad`) or a platform's hub. Closing the map goes back to
## the character's surface, as Factorio does.
##
## Charts for what is visible are asked for through map_cache.gd, which spaces the requests out.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MapCache := preload("res://scripts/ui/factorio/map_cache.gd")
const MapTagDialog := preload("res://scripts/ui/factorio/map_tag_dialog.gd")
const MapLayers := preload("res://scripts/ui/factorio/map_layers.gd")
const UiSettings := preload("res://scripts/ui/ui_settings.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")

## The Surfaces panel's list (GUI pixels), as Factorio's.
const SURFACES_WIDTH := 238

## Screen (GUI) pixels per tile.
const MIN_ZOOM := 0.25
const MAX_ZOOM := 8.0
const DEFAULT_ZOOM := 2.0
const ZOOM_STEP := 1.4142135
## Seconds between asking again for the same area.
const REFRESH := 6.0
## The most chunks asked for at once around the middle of the view (the mod sends 240 a second).
const MAX_CHUNKS := 96
## Screen pixels a second WASD moves the map.
const PAN_SPEED := 700.0

## Zoomed in past MAX_ZOOM at this point (tiles): factorio_ui.gd shows the world there.
signal zoom_to_world(at: Vector2)
## The "Space map" button under the surface switcher (Space Age).
signal space_map_requested
## Add tag / Add ping / a quick tag icon (remote_frame.gd) armed or done.
signal placing_changed
## A surface was picked in the Surfaces panel (its index; 0 the character's).
signal surface_chosen(si: int)

## The next left click on the map: {"kind": "tag" (with "icon") or "ping"}, or {} for none.
var placing := {}:
	set(v):
		placing = v
		placing_changed.emit()

var cache: MapCache
var model
## Returns [position (tiles), heading (radians clockwise from north)] of the character.
var character: Callable
var dialog := MapTagDialog.new()
var layers := MapLayers.new()
## The map view settings: an icon button per layer (named by its option, "map-show_tags").
var panel := PanelContainer.new()
## The surface switcher (top left): a button per surface in model.map_surfaces.
var surfaces_panel := PanelContainer.new()
## platform_panel.gd (the force's platforms, `plat`), for the planet icons on platform rows.
var platforms: Control = null
## The space map is open: its row is the chosen one (set_space_open).
var space_open := false
var _surface_box := VBoxContainer.new()
var settings = UiSettings.shared()

## Tiles in the middle of the window, and GUI pixels per tile (times Kit.scale on screen).
var centre := Vector2.ZERO
var zoom := DEFAULT_ZOOM
## The view follows the character until it is moved.
var following := true

var _hint := Label.new()
var _dragging := false
var _press_at := Vector2(-1, -1)
var _tag_at := Vector2.ZERO  # where the dialog's new tag goes (tiles)
var _tag_editing := -1  # id of the tag being edited
var _unghost := {}  # unghost request id -> the screen point right-clicked
var _me := [Vector2.ZERO, 0.0]
var _redraw := true
## The landing pad asked for on switching to a planet (its ask's id; -1 none, or the view was moved).
var _pad_q := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visible = false
	layers.model = model
	add_child(layers)
	_build_panel()
	_build_surfaces()
	model.map_surfaces_changed.connect(_on_surfaces_changed)
	model.unghost_answered.connect(_on_unghost)
	settings.changed.connect(func(key: String) -> void:
		if key.begins_with("map/"):
			_redraw = true)
	_hint.text = "Drag or WASD: move · Wheel: zoom · Right click: add or edit a tag · M or Esc: close"
	_hint.theme_type_variation = "FSmallLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.anchor_left = 1.0
	_hint.anchor_right = 1.0
	_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint.offset_right = -Kit.px(12)
	_hint.offset_top = Kit.px(8)
	_hint.add_theme_font_size_override("font_size", Kit.px(13))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false  # Factorio's remote view has no such line: F1's help says it
	add_child(_hint)
	add_child(dialog)
	dialog.confirmed.connect(_on_tag_confirmed)
	dialog.deleted.connect(_on_tag_deleted)
	cache.updated.connect(func() -> void: _redraw = true)
	model.tags_changed.connect(func() -> void: _redraw = true)
	model.map_trains_changed.connect(func() -> void: _redraw = true)
	model.territories_changed.connect(func() -> void: _redraw = true)
	model.roboports_changed.connect(func() -> void: _redraw = true)
	model.landing_pad_found.connect(_on_landing_pad)


func is_open() -> bool:
	return visible


func open(on: bool) -> void:
	if on == visible:
		return
	visible = on
	dialog.close()
	_dragging = false
	if on:
		following = true
		_me = _character()
		centre = _me[0]
		_redraw = true
	elif model.map_si != 0:
		model.set_map_surface(0)  # back to the character's surface, as in Factorio


## Screen pixels per tile.
func scale_now() -> float:
	return zoom * Kit.scale


func screen_to_tiles(p: Vector2) -> Vector2:
	return centre + (p - size / 2.0) / scale_now()


func tiles_to_screen(t: Vector2) -> Vector2:
	return size / 2.0 + (t - centre) * scale_now()


## Zooms by `factor`, keeping the point under `at` (screen) where it is.
func zoom_by(factor: float, at: Vector2) -> void:
	var before := screen_to_tiles(at)
	if factor > 1.0 and zoom >= MAX_ZOOM - 0.001:
		# On another surface the mod streams that surface's world for the remote view (`view`).
		zoom_to_world.emit(before)
		return
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if absf(zoom - 1.0) < 0.01:
		zoom = 1.0
	centre += before - screen_to_tiles(at)
	_pad_q = -1
	_redraw = true


func _character() -> Array:
	return character.call() if character.is_valid() else [Vector2.ZERO, 0.0]


func _process(delta: float) -> void:
	if not visible:
		return
	var me := _character()
	if me[0] != _me[0] or me[1] != _me[1]:
		_me = me
		_redraw = true
	if following and model.map_si == 0:
		centre = _me[0]
	var pan := _pan_input()
	if pan != Vector2.ZERO:
		var speed := PAN_SPEED * Kit.scale * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		centre += pan * speed * delta / scale_now()
		following = false
		_pad_q = -1
		_redraw = true
	var scale := scale_now()
	var half := size / 2.0 / scale
	var chunks := MapCache.chunks_of(Rect2(centre - half, half * 2.0))
	# Beyond MAX_CHUNKS across, only the middle is asked for; the rest shows what was seen before.
	var middle := chunks.get_center()
	var cap := Vector2i(mini(chunks.size.x, MAX_CHUNKS), mini(chunks.size.y, MAX_CHUNKS))
	chunks = Rect2i(middle - cap / 2, cap)
	if Bridge.world_ready:
		cache.want(chunks, MapCache.resolution_for(scale), REFRESH)
		model.ask_map_trains()
		model.ask_roboports(model.shown_surface())
	cache.flush()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if scale >= 0.5 else CanvasItem.TEXTURE_FILTER_LINEAR
	if _redraw or not model.live_pings().is_empty():
		_redraw = false
		queue_redraw()
		layers.character_at = _me[0]
		layers.redraw(centre, scale)


## WASD and the arrow keys, unless the tag dialog is being typed in.
func _pan_input() -> Vector2:
	if dialog.is_open():
		return Vector2.ZERO
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	return v.normalized()


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	var scale := scale_now()
	draw_rect(area, Color8(17, 16, 14))  # uncharted: Factorio's near-black, not pure black
	cache.draw(self, area, centre, scale)
	var font := Kit.font("semibold")
	var font_size := Kit.px(14)
	var icon := float(Kit.px(24))
	if bool(settings.get_value("map/show_tags")):
		for tag in model.map_tags:
			var p := tiles_to_screen(tag["position"])
			if area.grow(icon + Kit.px(200)).has_point(p):
				MapCache.draw_tag(self, p, tag, icon, true, font, font_size)
	MapCache.draw_pings(self, model.live_pings(), tiles_to_screen, float(Kit.px(24)))
	if model.map_si == 0:
		MapCache.draw_player(self, tiles_to_screen(_me[0]), float(_me[1]), float(Kit.px(20)))


## Factorio's surface switcher: planets first, then space platforms, the shown one pressed.
func _build_surfaces() -> void:
	surfaces_panel.name = "MapSurfaces"
	surfaces_panel.theme_type_variation = "FFrame"
	surfaces_panel.theme = MenuKit.theme()
	surfaces_panel.offset_left = Kit.px(12)
	surfaces_panel.offset_top = Kit.px(32)
	surfaces_panel.visible = false
	add_child(surfaces_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", Kit.px(8))
	surfaces_panel.add_child(outer)
	outer.add_child(Kit.label("Surfaces", "FCaption"))
	var deep := Kit.panel("FDeepFrame")
	deep.custom_minimum_size.x = Kit.px(SURFACES_WIDTH)
	outer.add_child(deep)
	_surface_box.add_theme_constant_override("separation", 0)
	deep.add_child(_surface_box)


func _on_surfaces_changed() -> void:
	for child in _surface_box.get_children():
		_surface_box.remove_child(child)
		child.queue_free()
	var list: Array = model.map_surfaces
	surfaces_panel.visible = list.size() >= 1
	_redraw = true
	if list.is_empty():
		return
	var planets: Array = list.filter(func(e: Dictionary) -> bool: return str(e["platform"]) == "" and str(e["planet"]) != "")
	var on_platforms: Array = list.filter(func(e: Dictionary) -> bool: return str(e["platform"]) != "")
	var others: Array = list.filter(func(e: Dictionary) -> bool: return str(e["platform"]) == "" and str(e["planet"]) == "")
	# Factorio's order: Space map, Planets, Platforms, the add button, then Other.
	var space := Button.new()
	space.name = "SpaceMap"
	space.text = "Space map"
	space.theme_type_variation = "FListItemSelected" if space_open else "FListItem"
	space.alignment = HORIZONTAL_ALIGNMENT_LEFT
	space.focus_mode = Control.FOCUS_NONE
	space.custom_minimum_size.y = Kit.px(30)
	space.pressed.connect(func() -> void: space_map_requested.emit())
	_surface_box.add_child(space)
	_surface_box.add_child(_subheader("Planets"))
	for entry in planets:
		_surface_box.add_child(_surface_button(entry))
	_surface_box.add_child(_subheader("Platforms"))
	for entry in on_platforms:
		_surface_box.add_child(_surface_button(entry))
	var add := Button.new()
	add.name = "AddPlatform"
	add.text = "+ Add space platform"
	add.focus_mode = Control.FOCUS_NONE
	add.disabled = true
	add.tooltip_text = "Build a space platform starter pack from a rocket silo"
	add.custom_minimum_size.y = Kit.px(30)
	_surface_box.add_child(add)
	if not others.is_empty():
		_surface_box.add_child(_subheader("Other"))
		for entry in others:
			_surface_box.add_child(_surface_button(entry))


func _subheader(text: String) -> Control:
	var p := Kit.panel("FSubheader")
	p.add_child(Kit.label(text, "FHeading"))
	return p


func _surface_button(entry: Dictionary) -> Button:
	var b := Button.new()
	var si := int(entry["si"])
	var planet := str(entry["planet"])
	b.name = "Surface%d" % si
	var rich := _plain_name(str(entry["platform"]))
	var other := planet == "" and str(entry["platform"]) == ""
	b.text = LocaleNames.space_location(planet) if planet != "" else (str(entry["name"]) if other else rich[0])
	b.tooltip_text = b.text + ("  (you are here)" if si == model.character_si else "")
	if not other:
		b.icon = _surface_icon(planet) if planet != "" or rich[1] == "" else Kit.item_icon(rich[1])
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", Kit.px(24))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.theme_type_variation = "FListItemSelected" if si == model.shown_surface() and not space_open else "FListItem"
	# A platform's row shows the planet it is at (or going to) on the right, as Factorio's.
	var pf := int(entry.get("pf", 0))
	if pf != 0 and platforms != null and is_instance_valid(platforms) and platforms.platforms.has(pf):
		var p: Dictionary = platforms.platforms[pf]
		var at := TextureRect.new()
		at.name = "At"
		at.texture = _surface_icon(str(p.get("to", p.get("loc", ""))))
		at.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		at.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		at.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		at.offset_left = -Kit.px(30)
		at.offset_right = -Kit.px(6)
		at.offset_top = Kit.px(3)
		at.offset_bottom = -Kit.px(3)
		at.mouse_filter = Control.MOUSE_FILTER_IGNORE
		at.texture_filter = Kit.ICON_FILTER
		b.add_child(at)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(Kit.px(SURFACES_WIDTH), Kit.px(30))
	b.pressed.connect(func() -> void:
		show_surface(si)
		surface_chosen.emit(model.map_si))
	return b


## A platform name with Factorio's rich text ("[item=space-science-pack] run", "[planet=vulcanus]")
## as plain words, and the first item named in it ("" if none) for the button's icon.
static func _plain_name(name: String) -> Array:
	var re := RegEx.create_from_string("\\[(item|planet|space-location|fluid|virtual-signal|entity|recipe)=([^\\],]+)[^\\]]*\\]")
	var first := ""
	var out := name
	for m in re.search_all(name):
		var kind := m.get_string(1)
		var what := m.get_string(2)
		if first == "" and kind == "item":
			first = what
		var word := LocaleNames.space_location(what) if kind in ["planet", "space-location"] else Kit.pretty(what)
		out = out.replace(m.get_string(0), word)
	out = out.strip_edges()
	return [out if out != "" else name, first]


## A planet's icon, or the platform hub's for a platform, from the player's install (or null).
static func _surface_icon(planet: String) -> Texture2D:
	if planet == "":
		return GuiAssets.data_sprite("space-age/graphics/icons/space-platform-hub.png")
	var icon := GuiAssets.data_sprite("space-age/graphics/icons/%s.png" % planet)
	if icon == null:
		icon = GuiAssets.data_sprite("base/graphics/icons/%s.png" % planet)
	return icon


## Shows another surface's map (its index from model.map_surfaces), centred on its middle, or the
## character's again, centred on the character.
## Rebuilds the Surfaces panel (the platforms moved, or their data arrived).
func refresh_surfaces() -> void:
	_on_surfaces_changed()


func set_space_open(on: bool) -> void:
	if on != space_open:
		space_open = on
		_on_surfaces_changed()


## The platform the map shows (its `plat` record), or {}.
func shown_platform() -> Dictionary:
	if not visible or platforms == null or not is_instance_valid(platforms):
		return {}
	var si: int = model.shown_surface()
	for entry in model.map_surfaces:
		if int(entry["si"]) == si and int(entry.get("pf", 0)) != 0:
			return platforms.platforms.get(int(entry["pf"]), {})
	return {}


func show_surface(si: int) -> void:
	model.set_map_surface(si)
	_on_surfaces_changed()
	dialog.close()
	_pad_q = -1
	if model.map_si == 0:
		following = true
		centre = _me[0]
	else:
		following = false
		centre = Vector2.ZERO  # a platform's hub; a planet's middle until its landing pad is known
		if str(model.map_surface(model.map_si).get("planet", "")) != "":
			_pad_q = model.ask_landing_pad(model.map_si)
	_redraw = true


## The mod's answer: the planet's landing pad, where the view goes unless it was moved meanwhile.
func _on_landing_pad(si: int, q: int, at: Vector2, found: bool) -> void:
	if q != _pad_q:
		return
	_pad_q = -1
	if found and si == model.map_si and visible:
		centre = at
		_redraw = true


## The map on another surface (or the character's, 0), centred on `at` (tiles) and zoomed in: an
## alert's entity there.
func look_at_on(si: int, at: Vector2) -> void:
	show_surface(si)
	_pad_q = -1
	following = false
	centre = at
	zoom = maxf(zoom, DEFAULT_ZOOM * 2.0)
	_redraw = true


## Factorio's map view settings: under the side menu, a grid of its own icon buttons (the
## side-map-menu-buttons.png rows, read from the install) in its order, lit orange when on, each
## named by its option ("map-show_tags") with Factorio's name as its tooltip. Factorio's player
## names and pipelines switches aren't here: the map doesn't draw those yet.
const LAYER_BUTTONS := [["map/show_logistic", 0], ["map/show_electric", 1], ["map/show_turrets", 2],
	["map/show_pollution", 3], ["map/show_stops", 4], ["map/show_tags", 6], ["map/show_robots", 7],
	["map/show_signals", 8], ["map/show_recipes", 9]]
const LAYER_COLUMNS := 6


func _build_panel() -> void:
	panel.name = "MapViewSettings"
	panel.theme_type_variation = "FSlotWindow"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_right = -Kit.px(12)
	panel.offset_top = Kit.px(32)
	add_child(panel)
	var frame := Kit.panel("FDeepFrame")
	frame.add_theme_stylebox_override("panel", Kit.style_with_margins("deep", 0, 0, 0, 0))
	panel.add_child(frame)
	var grid := Kit.slot_grid(LAYER_COLUMNS)
	grid.name = "LayerGrid"
	frame.add_child(grid)
	var labels := {}
	for layer in UiSettings.MAP_LAYERS:
		labels[layer[0]] = layer[1]
	for spec in LAYER_BUTTONS:
		var key: String = spec[0]
		var b := Button.new()
		b.name = key.replace("/", "-")
		b.theme_type_variation = "FSideButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
		b.icon = GuiAssets.core_region("icons/mip/side-map-menu-buttons.png", Rect2i(0, int(spec[1]) * 64, 64, 64))
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", Kit.px(32))
		if b.icon == null:
			b.text = str(labels.get(key, key)).substr(0, 2)
		b.tooltip_text = str(labels.get(key, key))
		b.button_pressed = bool(settings.get_value(key))
		b.toggled.connect(func(on: bool) -> void: settings.set_value(key, on))
		settings.changed.connect(func(k: String) -> void:
			if k == key:
				b.set_pressed_no_signal(bool(settings.get_value(key))))
		grid.add_child(b)
	for i in (LAYER_COLUMNS - LAYER_BUTTONS.size() % LAYER_COLUMNS) % LAYER_COLUMNS:
		grid.add_child(Kit.empty_cell())


## The tag drawn under a screen point, or {}.
func tag_at(p: Vector2) -> Dictionary:
	var best := {}
	var best_d := float(Kit.px(16)) ** 2
	for tag in model.map_tags:
		var at := tiles_to_screen(tag["position"])
		if str(tag.get("icon_name", "")) == "":
			at.y -= Kit.px(12)  # the pin stands above its point
		var d := at.distance_squared_to(p)
		if d <= best_d:
			best_d = d
			best = tag
	return best


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed and dialog.is_open() and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dialog.close()
			accept_event()
			return
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					zoom_by(ZOOM_STEP, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_by(1.0 / ZOOM_STEP, mb.position)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				_dragging = mb.pressed
				if mb.button_index == MOUSE_BUTTON_LEFT:
					if mb.pressed:
						_press_at = mb.position
					elif not placing.is_empty() and _press_at.distance_to(mb.position) < Kit.px(6):
						place_at(mb.position)
				if mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
					_dragging = false
					edit_tag_at(mb.position)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					right_click(mb.position)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging and mm.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE):
		centre -= mm.relative / scale_now()
		following = false
		_pad_q = -1
		_redraw = true
		accept_event()


## Carries out Add tag / Add ping at a screen point: the tag dialog there (with the quick icon
## chosen), or a ping said in the chat as a gps link (Factorio's ping).
func place_at(p: Vector2) -> void:
	var what: Dictionary = placing
	placing = {}
	if what.get("kind", "") == "ping":
		var at := screen_to_tiles(p)
		model.ping(at)
		model.say("[gps=%d,%d]" % [roundi(at.x), roundi(at.y)])
		_redraw = true
	elif what.get("kind", "") == "tag":
		_tag_editing = -1
		_tag_at = screen_to_tiles(p)
		dialog.open_at(p, {})
		dialog._pick_quietly(str(what.get("icon", "")))


## Opens the tag dialog for the tag under a screen point, or to create one there.
## Right-click, as in Factorio: on a tag, edit it; else remove the ghost there, and where there is
## none, add a tag (the mod answers first: ghosts far away aren't in the client's world).
func right_click(p: Vector2) -> void:
	if not tag_at(p).is_empty():
		edit_tag_at(p)
		return
	_unghost[model.unghost(screen_to_tiles(p))] = p


func _on_unghost(q: int, n: int) -> void:
	var p = _unghost.get(q)
	_unghost.erase(q)
	if p is Vector2 and n == 0 and is_open():
		edit_tag_at(p)


func edit_tag_at(p: Vector2) -> void:
	var tag := tag_at(p)
	_tag_editing = int(tag["id"]) if not tag.is_empty() else -1
	_tag_at = tag["position"] if not tag.is_empty() else screen_to_tiles(p)
	dialog.open_at(p, tag)


func _on_tag_confirmed(text: String, icon_name: String) -> void:
	# There is no "change tag" command: an edit replaces the tag.
	if _tag_editing >= 0:
		model.remove_map_tag(_tag_editing)
	model.add_map_tag(_tag_at, text, "item" if icon_name != "" else "", icon_name)
	_tag_editing = -1


func _on_tag_deleted() -> void:
	if _tag_editing >= 0:
		model.remove_map_tag(_tag_editing)
	_tag_editing = -1


## Esc closes the dialog first, then the map. Returns true if it did something.
func escape() -> bool:
	if dialog.is_open():
		dialog.close()
		return true
	if visible:
		open(false)
		return true
	return false
