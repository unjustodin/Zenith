extends Control
## Factorio's minimap in the top-right corner: the charted map around the character (north up),
## the character's arrow in the middle and the map tags, in Factorio's minimap_frame (a deep
## frame), with the map view's layers that are switched on (map_layers.gd). A click opens the map
## view; the wheel or the + / - buttons zoom it. Size, zoom, tags and whether it shows at all are
## options (ui_settings.gd, [map]).
##
## It asks for the charts around it every few seconds while shown (map_cache.gd). As in Factorio it
## shows what the view looks at (H22): while the map view is open, the map's middle (on the map's
## surface; the map view does the asking), and in the 3D remote view the remote view's point. The
## space map hides it.

signal open_map

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MapCache := preload("res://scripts/ui/factorio/map_cache.gd")
const UiSettings := preload("res://scripts/ui/ui_settings.gd")
const MapLayers := preload("res://scripts/ui/factorio/map_layers.gd")
const Controls := preload("res://scripts/player/controls.gd")

## Seconds between asking again for the same area (charts are snapshots).
const REFRESH := 4.0
const ZOOM_STEP := 2.0
const MARGIN := 12  # GUI pixels from the window's corner
## So the map opens already drawn, the minimap asks this often (when it has nothing
## else to ask) for what the map view shows on opening, at the map's first zoom (map_view.gd
## DEFAULT_ZOOM). One pass, then back to its own corner.
const PRELOAD_EVERY := 30.0
const PRELOAD_ZOOM := 2.0

var cache: MapCache
var model
## Returns [position (tiles), heading (radians clockwise from north)] of the character.
var character: Callable
var settings = UiSettings.shared()

var _frame := PanelContainer.new()
var _area := Area.new()
var _zoom_in := Button.new()
var _zoom_out := Button.new()
var _drawn_at := Vector2.ZERO
var _drawn_heading := 0.0
var _drawn_player := Vector2.ZERO
var _redraw := true
var _map_open := false
var _layers := MapLayers.new()
var max_side := INF
## Where the view looks (tiles), set by factorio_ui.gd each frame: Vector2.INF follows the character.
var look_at := Vector2.INF
## The map view is open and asks for the charts it shows: the minimap only draws them.
var map_asks := false
var _preloading := false
var _spot := Rect2i()  # a spot from cache.spots being asked for
var _preloaded_at := -1e9


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	_frame.theme_type_variation = "FDeepFrame"
	_frame.add_theme_stylebox_override("panel", _frame_style())
	add_child(_frame)
	_area.clip_contents = true
	_area.mouse_filter = Control.MOUSE_FILTER_STOP
	var keys := Controls.keys_text("toggle_map")
	_area.tooltip_text = "Map (%s)" % (keys if keys != "" else "M")
	_area.mouse_entered.connect(_area.queue_redraw)
	_area.mouse_exited.connect(_area.queue_redraw)
	_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_area.draw.connect(_draw_area)
	_area.gui_input.connect(_on_area_input)
	_frame.add_child(_area)
	_layers.model = model
	_layers.show_text = false
	_area.add_child(_layers)
	for b in [_zoom_in, _zoom_out]:
		b.theme_type_variation = "FFrameAction"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(24, 24)
		b.add_theme_font_size_override("font_size", Kit.px(16))
		b.add_theme_font_override("font", Kit.font("bold"))
		for c in ["font_color", "font_focus_color"]:
			b.add_theme_color_override(c, Kit.WHITE)
		_area.add_child(b)
	_zoom_in.text = "+"
	_zoom_in.tooltip_text = "Zoom in"
	_zoom_in.pressed.connect(func() -> void: zoom(ZOOM_STEP))
	_zoom_out.text = "−"
	_zoom_out.tooltip_text = "Zoom out"
	_zoom_out.pressed.connect(func() -> void: zoom(1.0 / ZOOM_STEP))
	# Factorio's minimap has no zoom buttons (the wheel zooms it); kept for the UI test.
	_zoom_in.visible = false
	_zoom_out.visible = false
	cache.updated.connect(_queue)
	model.tags_changed.connect(_queue)
	model.pinged.connect(_queue)
	model.map_trains_changed.connect(_queue)
	model.territories_changed.connect(_queue)
	model.roboports_changed.connect(_queue)
	settings.changed.connect(_on_setting)
	_layout()


## The deep frame without its inner padding: the map fills it.
func _frame_style() -> StyleBox:
	return Kit.style_with_margins("deep", 0, 0, 0, 0)


func _on_setting(key: String) -> void:
	if key.begins_with("map/"):
		_layout()


## Its side in screen pixels: the frame and the map in it are this square, the size setting's or
## smaller when the window has no room for it.
func side_px() -> float:
	return maxf(float(Kit.px(40)), minf(float(Kit.px(float(settings.get_value("map/minimap_size")))), max_side))


## The most room the HUD has for it (screen pixels); factorio_ui.gd sets it as it lays out.
func set_max_side(side: float) -> void:
	max_side = side
	_layout()


func _layout() -> void:
	var side := side_px()
	visible = bool(settings.get_value("map/minimap")) and not _map_open
	offset_right = -Kit.px(MARGIN)
	offset_left = offset_right - side
	offset_top = Kit.px(MARGIN)
	offset_bottom = offset_top + side
	_frame.position = Vector2.ZERO
	_frame.size = Vector2(side, side)
	_area.custom_minimum_size = Vector2(side, side)
	var b := Kit.px(24)
	var gap := Kit.px(4)
	_zoom_in.position = Vector2(side - b - gap, side - 2 * b - 2 * gap)
	_zoom_out.position = Vector2(side - b - gap, side - b - gap)
	_queue()


## The space map hides the minimap while it is open.
func set_map_open(on: bool) -> void:
	_map_open = on
	_layout()


## Screen pixels per tile.
func scale_now() -> float:
	return float(settings.get_value("map/minimap_zoom")) * Kit.scale


func zoom(factor: float) -> void:
	settings.set_value("map/minimap_zoom", float(settings.get_value("map/minimap_zoom")) * factor)


func _queue() -> void:
	_redraw = true


func _character() -> Array:
	return character.call() if character.is_valid() else [Vector2.ZERO, 0.0]


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var me := _character()
	var at: Vector2 = me[0] if look_at == Vector2.INF else look_at
	var scale := scale_now()
	var half := _area.size / 2.0 / scale
	# A chunk beyond each edge, so walking doesn't show black edges while the next pass comes.
	var tiles := Rect2(at - half - Vector2(MapCache.CHUNK, MapCache.CHUNK), half * 2.0 + Vector2(2, 2) * MapCache.CHUNK)
	if Bridge.world_ready:
		if not map_asks:
			_ask(MapCache.chunks_of(tiles), MapCache.resolution_for(scale), at)
		model.ask_map_trains()
		model.ask_roboports(model.shown_surface())
	cache.flush()
	_area.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if scale >= 0.5 else CanvasItem.TEXTURE_FILTER_LINEAR
	if not model.live_pings().is_empty():
		_redraw = true
	var player: Vector2 = me[0]
	if _redraw or at.distance_squared_to(_drawn_at) * scale * scale > 0.04 or absf(float(me[1]) - _drawn_heading) > 0.02 \
			or player.distance_squared_to(_drawn_player) * scale * scale > 0.04:
		var changed := _redraw
		_redraw = false
		_drawn_at = at
		_drawn_player = player
		_drawn_heading = float(me[1])
		_area.queue_redraw()
		_layers.character_at = player
		_layers.follow(_drawn_at, scale, changed)


## Asks for the minimap's own area, or now and then for the map view's (preload).
func _ask(own: Rect2i, res: int, at: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not _preloading and now - _preloaded_at >= PRELOAD_EVERY and not cache.busy():
		_preloading = true
		_preloaded_at = now
	if not _preloading and not _spot.has_area() and not cache.spots.is_empty() and not cache.busy():
		_spot = cache.spots.pop_front()
	if _spot.has_area() and not _preloading:
		cache.want(_spot, MapCache.RESOLUTIONS[0], PRELOAD_EVERY)
		if not cache.busy():
			_spot = Rect2i()
		return
	if _preloading:
		var scale := PRELOAD_ZOOM * Kit.scale
		var half := get_viewport_rect().size / 2.0 / scale
		cache.want(MapCache.chunks_of(Rect2(at - half, half * 2.0)), MapCache.resolution_for(scale), PRELOAD_EVERY)
		if not cache.busy():
			_preloading = false
		return
	cache.want(own, res, REFRESH)


func _draw_area() -> void:
	var area := Rect2(Vector2.ZERO, _area.size)
	var scale := scale_now()
	_area.draw_rect(area, Color.BLACK)
	cache.draw(_area, area, _drawn_at, scale)
	var middle := area.size / 2.0
	var icon := float(Kit.px(16))
	if bool(settings.get_value("map/minimap_tags")):
		for tag in model.map_tags:
			var p: Vector2 = middle + ((tag["position"] as Vector2) - _drawn_at) * scale
			if area.grow(icon).has_point(p):
				MapCache.draw_tag(_area, p, tag, icon, false, null, 0)
	MapCache.draw_pings(_area, model.live_pings(), func(t: Vector2) -> Vector2: return middle + (t - _drawn_at) * scale, float(Kit.px(14)))
	# The character's arrow where it is (the middle unless the minimap follows a view), on its surface.
	if model.map_si == 0:
		var me := middle + (_drawn_player - _drawn_at) * scale
		if area.grow(Kit.px(8)).has_point(me):
			MapCache.draw_player(_area, me, _drawn_heading, float(Kit.px(14)))
	if _area.get_global_rect().has_point(_area.get_global_mouse_position()):
		# Factorio's hovered minimap: an orange glow round its edge.
		var w := float(Kit.px(2))
		_area.draw_rect(area.grow(-w / 2.0), Kit.ORANGE, false, w)
		_area.draw_rect(area.grow(-w * 1.5), Color(Kit.ORANGE, 0.35), false, w)


func _on_area_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			open_map.emit()
		MOUSE_BUTTON_WHEEL_UP when mb.shift_pressed:  # Factorio: Shift + wheel zooms the minimap
			zoom(sqrt(ZOOM_STEP))
		MOUSE_BUTTON_WHEEL_DOWN when mb.shift_pressed:
			zoom(1.0 / sqrt(ZOOM_STEP))
		_:
			return
	_area.accept_event()


## The map area: Factorio's minimap tooltip, "Map (M)" with the key in bold blue, then
## "Shift + Mouse wheel to zoom in and out." with the keys in bold blue.
class Area extends Control:
	func _make_custom_tooltip(for_text: String) -> Object:
		var box := Kit.simple_tooltip(for_text)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var k := Kit.label("Shift + Mouse wheel")
		k.add_theme_font_override("font", Kit.font("bold"))
		k.add_theme_color_override("font_color", Kit.KEY_TEXT)
		row.add_child(k)
		row.add_child(Kit.label(" to zoom in and out."))
		box.add_child(row)
		return box
