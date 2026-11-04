extends Control
## What Factorio's map view switches draw over the charted map ([gui-map-view-settings]):
## electric networks (the poles' supply areas), logistic networks (roboports' logistic and
## construction areas), turret coverage, train stop names, worker robots, rail signal states and
## recipe icons, from the charts' `ov` (ui_model.gd map_overlays), and the whole surface's roboports
## from `mrp` (H13: the network shows whole, not only where charts were loaded). Which ones show is
## ui_settings.gd's map/show_* switches; the minimap and the map view each have one of these over
## their map, filling it.
##
## Areas are drawn solid inside a CanvasGroup that is made translucent as a whole, so overlapping
## areas read as one covered region, like Factorio's map, instead of getting darker.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const UiSettings := preload("res://scripts/ui/ui_settings.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")

## Factorio-like map colours.
const ELECTRIC := Color(0.13, 0.55, 0.85)
const LOGISTIC := Color(1.0, 0.6, 0.1)
const CONSTRUCTION := Color(0.3, 0.75, 0.3)
const TURRET := Color(0.95, 0.15, 0.1)
const ROBOT := Color(1.0, 0.9, 0.55)
## Copper wires between poles, with the electric layer (Factorio draws them over the supply areas).
const WIRE := Color(0.95, 0.72, 0.35, 0.9)
## Pollution: each chunk tinted by how much it holds, stronger on a log scale.
const POLLUTION := Color(0.85, 0.12, 0.05)
const POLLUTION_FULL := 10000.0  # this much (and more) is the strongest tint
## Vulcanus' demolisher territories' borders.
const TERRITORY := Color(0.9, 0.12, 0.08, 0.85)
## Their ground, striped across as Factorio's map marks a hazard: a light red wash with
## stronger diagonal bands, a stripe and a gap at least this many screen pixels.
const TERRITORY_WASH := Color(0.9, 0.12, 0.08, 0.1)
const TERRITORY_STRIPE := Color(0.9, 0.12, 0.08, 0.26)
const STRIPE_PX := 18.0
## Past this many territory chunks in view only the wash is drawn (zoomed far out).
const STRIPED_CHUNKS := 3000
## defines.signal_state: open, closed, reserved, reserved by circuit network.
const SIGNAL_COLORS := [Color(0.2, 0.9, 0.2), Color(0.95, 0.15, 0.1), Color(1.0, 0.85, 0.1), Color(0.2, 0.5, 1.0)]

var model
var settings = UiSettings.shared()
## Where the map is drawn from, set by the view each time it draws: tiles in the middle, screen
## pixels per tile.
var centre := Vector2.ZERO
var scale_px := 1.0
## Text (train stop names) only where there is room for it: the map view, not the minimap.
var show_text := true
## Where the character is (tiles), set by the view: the ground round it counts as seen.
var character_at := Vector2.ZERO
## Charted chunks no radar sees are drawn this much darker, as Factorio's map does.
const UNSEEN := Color(0, 0, 0, 0.4)

## The layers, each a canvas of its own drawn again only when its own data changed (the minimap
## drew every layer up to four times a second, 15-20 ms each time on a big base: the stutter
## standing still), in drawing order: the four coverage areas (each in its CanvasGroup), then
## `shade` (unseen chunks dimmed, pollution, territories), `wires`, `trains` and `marks` (robots,
## signals, stops and recipe icons, last: over the coverage areas).
const LAYERS := ["construction", "logistic", "electric", "turret", "shade", "wires", "trains", "marks"]
var _groups := {}  # kind -> [CanvasGroup, Control]
var _canvas := {}  # layer -> its Control
var shade := Control.new()
var wires := Control.new()
var trains := Control.new()
## Robots, signals, stops and recipe icons, over the coverage areas.
var marks := Control.new()
## Every layer is drawn into this SubViewport, which renders only when a layer was drawn again or
## the view moved past shift_px (UPDATE_ONCE): the rest of the time the map's layers are one
## textured rectangle (`cached`, premultiplied alpha), not thousands of draw commands every frame.
var _vp := SubViewport.new()
var _root := Control.new()
var cached := TextureRect.new()
## How often each layer was drawn, and how often the SubViewport was asked to render (tests).
var drawn := {}
var renders := 0
## Each charted chunk's overlay rows split by layer ({"e", "t", "l", "w", "p": rows}), made when
## first needed and dropped when its chart comes again.
var _split := {}
## Each chunk's signature at its last chart (charted, pollution, a hash per layer's rows): a chart
## that comes again unchanged (the views ask for theirs every few seconds) redraws nothing.
var _sig := {}
const _SIG_LAYERS := [["shade"], ["shade"], ["electric"], ["turret"], ["logistic", "construction"], ["wires"], ["marks"]]
var _empty_hash := hash([])
var _coverage_sig := 0
var _near_sig := 0
var _near_at := Vector2.INF
## follow(): how far what is drawn may be moved before it is drawn again (shift_px: also how far
## past the view's edges everything is drawn), how often new data is drawn at most, and the state
## of the last drawing.
const SHIFT_PX := 24.0
const DATA_REDRAW_MSEC := 250
var shift_px := SHIFT_PX
var _dirty := {}  # layer -> true: its data changed since it was drawn
var _forced := false  # a setting or the surface changed: drawn at once, not after DATA_REDRAW_MSEC
var _drawn_msec := 0
var _drawn_size := Vector2.ZERO
var _shift_now := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vp.name = "LayersViewport"
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(2, 2)
	add_child(_vp)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(_root)
	for spec in [["construction", 0.16], ["logistic", 0.28], ["electric", 0.3], ["turret", 0.22]]:
		var group := CanvasGroup.new()
		group.self_modulate = Color(1, 1, 1, spec[1])
		_root.add_child(group)
		var canvas := Control.new()
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kind: String = spec[0]
		canvas.draw.connect(func() -> void: _draw_areas(canvas, kind))
		group.add_child(canvas)
		_groups[kind] = [group, canvas]
		_canvas[kind] = canvas
	for spec in [["shade", shade, _draw_shade], ["wires", wires, _draw_wires], ["trains", trains, _draw_trains], ["marks", marks, _draw_marks]]:
		var canvas: Control = spec[1]
		canvas.name = str(spec[0]).capitalize()
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.draw.connect(spec[2])
		_root.add_child(canvas)
		_canvas[spec[0]] = canvas
	# The SubViewport's texture holds premultiplied colours (drawn over a transparent background).
	var premultiplied := CanvasItemMaterial.new()
	premultiplied.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	cached.name = "Cached"
	cached.material = premultiplied
	cached.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cached.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cached.stretch_mode = TextureRect.STRETCH_SCALE
	cached.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cached.texture = _vp.get_texture()
	add_child(cached)
	settings.changed.connect(_on_setting)
	if model != null:
		model.map_changed.connect(_on_chart)
		model.map_surfaces_changed.connect(_on_surface)
		model.tags_changed.connect(_check_reset)
		model.map_trains_changed.connect(_on_trains)
		model.territories_changed.connect(func() -> void: _dirty["shade"] = true)
		model.roboports_changed.connect(_on_roboports)


func _on_setting(key: String) -> void:
	if key.begins_with("map/"):
		dirty_all(true)


## Every layer is drawn again (forced: at once, not after DATA_REDRAW_MSEC).
func dirty_all(forced := false) -> void:
	for layer in LAYERS:
		_dirty[layer] = true
	_forced = _forced or forced


## A chart came: the layers whose rows in it changed are drawn again, if it is near the view.
func _on_chart(chunk: Vector2i) -> void:
	_split.erase(chunk)
	var rows := _parts(chunk)
	var sig := [model.map_charts.get(chunk) != null, int(model.map_pollution.get(chunk, 0)), hash(rows["e"]), hash(rows["t"]),
		hash(rows["l"]), hash(rows["w"]), hash(rows["p"])]
	var old: Array = _sig.get(chunk, [false, 0, _empty_hash, _empty_hash, _empty_hash, _empty_hash, _empty_hash])
	_sig[chunk] = sig
	# Rows reach at most a construction area (120 tiles here) past their chunk.
	var half := size / 2.0 / maxf(scale_px, 0.001) + Vector2(160, 160) + _slack()
	if not Rect2(centre - half, half * 2.0).intersects(Rect2(Vector2(chunk) * 32.0, Vector2(32, 32))):
		return
	for i in sig.size():
		if sig[i] != old[i]:
			for layer in _SIG_LAYERS[i]:
				_dirty[layer] = true


## Another surface: everything from scratch.
func _on_surface() -> void:
	_split.clear()
	_sig.clear()
	dirty_all(true)


## map_cache.gd's reset() empties the charts without a chart for each: start again then too.
func _check_reset() -> void:
	if model != null and not _sig.is_empty() and model.map_overlays.is_empty() and model.map_charts.is_empty():
		_on_surface()


## Trains come about once a second: only their layer, and the dimming if what radars see changed
## (it comes with them, `cov`).
func _on_trains() -> void:
	_dirty["trains"] = true
	var cov := hash([model.map_coverage, model.map_coverage_known, model.map_si])
	if cov != _coverage_sig:
		_coverage_sig = cov
		_dirty["shade"] = true


func _on_roboports() -> void:
	for layer in ["logistic", "construction", "shade"]:
		_dirty[layer] = true


## The chunks round the character that count as seen changed (it walked): the dimming again.
func _check_near() -> void:
	if character_at == _near_at or model == null:
		return
	_near_at = character_at
	var sig := 0
	if model.map_si == 0 and model.map_coverage_known:
		var r := UiModel.COVERED_RADIUS + 16.0
		var lo := Vector2i(((character_at - Vector2(r, r)) / 32.0).floor()) - Vector2i.ONE
		var hi := Vector2i(((character_at + Vector2(r, r)) / 32.0).floor()) + Vector2i.ONE
		var near := PackedInt32Array()
		for cy in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				if (Vector2(cx, cy) * 32.0 + Vector2(16, 16)).distance_to(character_at) <= r:
					near.append(cx)
					near.append(cy)
		sig = hash(near)
	if sig != _near_sig:
		_near_sig = sig
		_dirty["shade"] = true


## The minimap's (and the map view's) way of redrawing: while the view only moves a little, what is
## drawn moves with it instead of being drawn again (thousands of areas on a big base: 2 ms a frame
## while walking). It is all drawn again once it has moved shift_px, or the zoom or size changed; a
## layer whose data changed (everything: `changed`) is drawn again where it was drawn, at most every
## DATA_REDRAW_MSEC (a setting or a new surface at once). Everything is drawn shift_px past the
## edges, so moving shows no seam.
func follow(at: Vector2, scale: float, changed: bool) -> void:
	if changed:
		dirty_all()
	_check_reset()
	_check_near()
	var offset := (centre - at) * scale
	var now := Time.get_ticks_msec()
	if not is_equal_approx(scale, scale_px) or size != _drawn_size or offset.length() > shift_px:
		_drawn_msec = now
		redraw(at, scale)
		return
	if not _dirty.is_empty() and (_forced or now - _drawn_msec >= DATA_REDRAW_MSEC):
		_drawn_msec = now
		_draw_dirty()
	_shift(offset)


## How far what is drawn has been moved since it was drawn (screen pixels).
func shift_now() -> Vector2:
	return _shift_now


func _shift(offset: Vector2) -> void:
	var s := _screen_scale()
	# Whole screen pixels: the texture is drawn one to one, never between pixels (blurred).
	_shift_now = (offset * s).round() / s
	cached.position = _shift_now - Vector2(shift_px, shift_px)
	cached.size = Vector2(_vp.size) / s


## Redraws for a view now drawn around `at` (tiles) at `scale` screen pixels per tile.
func redraw(at: Vector2, scale: float) -> void:
	centre = at
	scale_px = scale
	_drawn_size = size
	_check_reset()
	_check_near()
	dirty_all()
	_draw_dirty()
	_shift(Vector2.ZERO)


## Draws the layers whose data changed again, into the SubViewport, which renders this frame (a
## SubViewport renders before the window that shows it: nothing lags a frame).
func _draw_dirty() -> void:
	var s := _screen_scale()
	var m := Vector2(shift_px, shift_px)
	var want := Vector2i(((size + m * 2.0) * s).ceil()).max(Vector2i(2, 2))
	if _vp.size != want:
		_vp.size = want
		dirty_all()
	_root.position = m * s
	_root.scale = Vector2(s, s)
	_root.size = size
	_root.texture_filter = _filter()
	for kind in _groups:
		(_groups[kind][0] as CanvasGroup).visible = _shown(kind)
	for layer in _dirty:
		var canvas: Control = _canvas[layer]
		canvas.size = size
		canvas.queue_redraw()
	_dirty.clear()
	_forced = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1


## Screen pixels per GUI pixel here (the window's content scale after a live UI scale change): the
## SubViewport is sized in screen pixels, so its texture is drawn one to one.
func _screen_scale() -> float:
	if not is_inside_tree():
		return 1.0
	return maxf(get_screen_transform().get_scale().x, 0.01)


## The texture filter this node draws with (the views switch it with the zoom): the icons drawn
## inside the SubViewport take it too.
func _filter() -> CanvasItem.TextureFilter:
	var node: Node = self
	while node is CanvasItem:
		var f := (node as CanvasItem).texture_filter
		if f != CanvasItem.TEXTURE_FILTER_PARENT_NODE:
			return f
		node = node.get_parent()
	return CanvasItem.TEXTURE_FILTER_LINEAR


func _counted(layer: String) -> void:
	drawn[layer] = int(drawn.get(layer, 0)) + 1


func _shown(kind: String) -> bool:
	match kind:
		"electric":
			return bool(settings.get_value("map/show_electric"))
		"logistic", "construction":
			return bool(settings.get_value("map/show_logistic"))
		"turret":
			return bool(settings.get_value("map/show_turrets"))
	return false


## How strongly a chunk with this much pollution is tinted.
static func pollution_alpha(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	return clampf(log(1.0 + amount) / log(1.0 + POLLUTION_FULL), 0.05, 1.0) * 0.6


## How far past the view's edges (tiles) everything is drawn, for follow() to move it.
func _slack() -> Vector2:
	return Vector2(shift_px, shift_px) / maxf(scale_px, 0.001)


func to_screen(t: Vector2) -> Vector2:
	return size / 2.0 + (t - centre) * scale_px


## A charted chunk's overlay rows by layer: "e" electric areas, "t" turrets, "l" roboports, "w"
## wires, "p" robots, signals, stops and recipe icons.
func _parts(chunk: Vector2i) -> Dictionary:
	var parts = _split.get(chunk)
	if parts != null:
		return parts
	var out := {"e": [], "t": [], "l": [], "w": [], "p": []}
	var list = model.map_overlays.get(chunk) if model != null else null
	if list != null:
		for r in list:
			var k := str(r[0])
			if k == "e" or k == "t" or k == "l":
				(out[k] as Array).append(r)
			elif k == "w":
				if r.size() >= 5:
					(out["w"] as Array).append(r)
			else:
				(out["p"] as Array).append(r)
	_split[chunk] = out
	return out


## The overlay entries of one layer's kind ("e", "t", "l", "w", "p"; "" all of them) within the view
## and `margin` tiles around it. The chunks in view are looked up, not every charted chunk's list
## (3-4 ms a frame on a big base).
func _entries_of(kind: String, margin: float) -> Array:
	var out: Array = []
	if model == null:
		return out
	var half := size / 2.0 / scale_px + Vector2(margin, margin) + _slack()
	var view := Rect2(centre - half, half * 2.0)
	var overlays: Dictionary = model.map_overlays
	var lo := Vector2i((view.position / 32.0).floor()) - Vector2i.ONE
	var hi := Vector2i((view.end / 32.0).floor()) + Vector2i.ONE
	var chunks: Array = []
	if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) <= overlays.size():
		for cy in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var chunk := Vector2i(cx, cy)
				if overlays.has(chunk):
					chunks.append(chunk)
	else:  # zoomed far out over few charted chunks
		var area := Rect2(view.position / 32.0 - Vector2.ONE, view.size / 32.0 + Vector2(2, 2))
		for chunk in overlays:
			if area.has_point(Vector2(chunk)):
				chunks.append(chunk)
	for chunk in chunks:
		var parts := _parts(chunk)
		for k in (["e", "t", "l", "w", "p"] if kind == "" else [kind]):
			for r in parts[k]:
				if view.has_point(Vector2(r[1], r[2])):
					out.append(r)
	return out


## Every overlay entry within the view and `margin` tiles around it.
func _visible_entries(margin: float) -> Array:
	return _entries_of("", margin)


func _draw_areas(canvas: Control, kind: String) -> void:
	_counted(kind)
	if not _shown(kind):
		return
	if kind == "logistic" or kind == "construction":
		var colour := LOGISTIC if kind == "logistic" else CONSTRUCTION
		for square: Rect2 in roboport_squares(kind):
			canvas.draw_rect(square, colour)
		return
	var want := "e" if kind == "electric" else "t"
	var color := ELECTRIC if kind == "electric" else TURRET
	for r in _entries_of(want, 60.0):
		var p := to_screen(Vector2(r[1], r[2]))
		if kind == "electric":
			var half := float(r[3]) * scale_px
			canvas.draw_rect(Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0), color)
		else:
			canvas.draw_circle(p, float(r[3]) * scale_px, color)


## The roboports' logistic or construction squares (`kind`) reaching into the view, on screen: every
## roboport of the shown surface from its whole list (`mrp`, H13: the network shows whole, not only
## where charts were loaded), and those in the charts' rows that the list doesn't have yet (built
## since it was read).
func roboport_squares(kind: String) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if model == null:
		return out
	var k := 2 if kind == "logistic" else 3
	var half_view := size / 2.0 / scale_px + _slack()
	var view := Rect2(centre - half_view, half_view * 2.0)
	var si: int = model.shown_surface()
	var ports: PackedInt32Array = model.roboports_of(si)
	for i in range(0, ports.size() - 3, 4):
		var r := ports[i + k] / 256.0
		var square := Rect2(Vector2(ports[i], ports[i + 1]) / 256.0 - Vector2(r, r), Vector2(r, r) * 2.0)
		if view.intersects(square):
			out.append(Rect2(to_screen(square.position), square.size * scale_px))
	for row in _entries_of("l", 60.0 if kind == "logistic" else 120.0):
		if model.has_roboport_at(si, Vector2i(roundi(row[1] * 256.0), roundi(row[2] * 256.0))):
			continue
		var r := float(row[k + 1])
		out.append(Rect2(to_screen(Vector2(row[1], row[2]) - Vector2(r, r)), Vector2(r, r) * 2.0 * scale_px))
	return out


## Dims the charted chunks in view that no radar, roboport (or the character) sees now.
func _draw_unseen(c: Control) -> void:
	if model == null or not model.map_coverage_known:
		return
	var half := size / 2.0 / scale_px + _slack()
	var first := Vector2i((centre - half) / 32.0) - Vector2i.ONE
	var last := Vector2i((centre + half) / 32.0) + Vector2i.ONE
	if (last - first).x * (last - first).y > 40000:
		return  # zoomed out over a huge area: not worth the draw calls
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var chunk := Vector2i(cx, cy)
			if model.map_charts.get(chunk) != null and not model.chunk_covered(chunk, character_at):
				c.draw_rect(Rect2(to_screen(Vector2(chunk) * 32.0), Vector2(32, 32) * scale_px), UNSEEN)


## The stripes' period in tiles at this zoom: whole tiles, doubling as the map zooms out, so they
## keep about the same width on screen without crawling while zooming.
static func stripe_period(scale: float) -> float:
	var period := 4.0
	while period * scale < STRIPE_PX * 2.0:
		period *= 2.0
	return period


## Demolisher territories' ground: each chunk washed red with diagonal bands (x + y in a
## stripe's half of the period) that run on unbroken from chunk to chunk; the borders go over them.
func _draw_territories(c: Control) -> void:
	var half := size / 2.0 / scale_px + _slack()
	var view := Rect2(centre - half, half * 2.0)
	var shown: Array = []
	for chunk: Vector2i in model.territory_chunks:
		var area := Rect2(Vector2(chunk) * 32.0, Vector2(32, 32))
		if view.intersects(area):
			shown.append(area)
	var period := stripe_period(scale_px)
	var striped := shown.size() <= STRIPED_CHUNKS
	for area: Rect2 in shown:
		c.draw_rect(Rect2(to_screen(area.position), area.size * scale_px), TERRITORY_WASH)
		if not striped:
			continue
		var low := area.position.x + area.position.y
		var k := floorf(low / period) * period
		while k < low + 64.0:
			var band := stripe_band(area, k, k + period / 2.0)
			if band.size() >= 3:
				for i in band.size():
					band[i] = to_screen(band[i])
				c.draw_colored_polygon(band, TERRITORY_STRIPE)
			k += period


## The part of the square `area` (tiles) where a <= x + y <= b, as a polygon (empty if none).
static func stripe_band(area: Rect2, a: float, b: float) -> PackedVector2Array:
	var poly := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end,
		Vector2(area.position.x, area.end.y)])
	poly = _clip(poly, a, 1.0)
	return _clip(poly, -b, -1.0)


## Keeps the side of `poly` where side * (x + y) >= limit (Sutherland-Hodgman, one edge).
static func _clip(poly: PackedVector2Array, limit: float, side: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		var dp := side * (p.x + p.y) - limit
		var dq := side * (q.x + q.y) - limit
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			out.append(p.lerp(q, dp / (dp - dq)))
	return out


## Every carriage on charted ground as a rectangle in its map colour, turned the way it faces, as
## Factorio's map shows trains. At least a few pixels long, so a train far out still shows.
func _draw_trains() -> void:
	_counted("trains")
	if model == null or model.map_trains.is_empty():
		return
	var cars: PackedInt32Array = model.map_trains
	var half_view := size / 2.0 / scale_px + Vector2(8, 8) + _slack()
	var view := Rect2(centre - half_view, half_view * 2.0)
	for i in range(0, cars.size() - 5, 6):
		var at := Vector2(cars[i], cars[i + 1]) / 256.0
		if not view.has_point(at):
			continue
		var length := maxf(cars[i + 3] / 256.0 * scale_px, 4.0)
		var width := maxf(cars[i + 4] / 256.0 * scale_px, 2.0)
		var c := cars[i + 5]
		var colour := Color8((c >> 16) & 255, (c >> 8) & 255, c & 255)
		# Orientation 0 is north (screen up), turning clockwise.
		trains.draw_set_transform(to_screen(at), cars[i + 2] / 1000.0 * TAU, Vector2.ONE)
		trains.draw_rect(Rect2(-width / 2.0, -length / 2.0, width, length), colour)
		trains.draw_rect(Rect2(-width / 2.0, -length / 2.0, width, length), Color(0, 0, 0, 0.6), false, 1.0)
	trains.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Unseen chunks dimmed, pollution, demolisher territories and their borders.
func _draw_shade() -> void:
	_counted("shade")
	_draw_unseen(shade)
	if model != null and bool(settings.get_value("map/show_pollution")) and not model.map_pollution.is_empty():
		var half := size / 2.0 / scale_px + Vector2(32, 32) + _slack()
		var view := Rect2(centre - half, half * 2.0)
		for chunk: Vector2i in model.map_pollution:
			var area := Rect2(Vector2(chunk) * 32.0, Vector2(32, 32))
			if view.intersects(area):
				var a := pollution_alpha(float(model.map_pollution[chunk]))
				shade.draw_rect(Rect2(to_screen(area.position), area.size * scale_px), Color(POLLUTION, a))
	if model != null and not model.territory_edges.is_empty() and model.territories_shown():
		_draw_territories(shade)
		var half := size / 2.0 / scale_px + Vector2(32, 32) + _slack()
		var view := Rect2(centre - half, half * 2.0)
		var edges: PackedVector2Array = model.territory_edges
		for i in range(0, edges.size() - 1, 2):
			if view.has_point(edges[i]) or view.has_point(edges[i + 1]):
				shade.draw_line(to_screen(edges[i]), to_screen(edges[i + 1]), TERRITORY, maxf(1.5, 0.15 * scale_px))


## Copper wires between poles, with the electric layer.
func _draw_wires() -> void:
	_counted("wires")
	if bool(settings.get_value("map/show_electric")) and scale_px >= 0.5:
		# A wire's start can be far outside the view while it crosses it: a wide margin.
		for r in _entries_of("w", 64.0):
			wires.draw_line(to_screen(Vector2(r[1], r[2])), to_screen(Vector2(r[3], r[4])), WIRE, maxf(1.0, 0.12 * scale_px), true)


## Robots, signals, stops and recipe icons.
func _draw_marks() -> void:
	_counted("marks")
	var robots := bool(settings.get_value("map/show_robots"))
	var signals := bool(settings.get_value("map/show_signals"))
	var stops := bool(settings.get_value("map/show_stops"))
	var recipes := bool(settings.get_value("map/show_recipes"))
	if not (robots or signals or stops or recipes):
		return
	var font := Kit.font("semibold")
	var font_size := Kit.px(14)
	for r in _entries_of("p", 8.0):
		var p := to_screen(Vector2(r[1], r[2]))
		match str(r[0]):
			"b":
				if robots:
					marks.draw_circle(p, maxf(1.5, 0.35 * scale_px), ROBOT)
			"g":
				if signals:
					marks.draw_circle(p, maxf(2.0, 0.45 * scale_px), SIGNAL_COLORS[clampi(int(r[3]), 0, 3)])
			"c":
				if recipes and scale_px >= 1.0:
					var side := clampf(2.2 * scale_px, 10.0, 48.0)
					marks.draw_texture_rect(Kit.item_icon(str(r[3])), Rect2(p - Vector2(side, side) / 2.0, Vector2(side, side)), false)
			"s":
				if stops:
					marks.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.95, 0.3, 0.25))
					if show_text and font != null and str(r[3]) != "":
						var at := p + Vector2(6, font_size * 0.35)
						# Names with icons ([item=...]) draw them, as Factorio's map does.
						RichText.draw(marks, font, at, str(r[3]), font_size, Color.WHITE, maxi(2, font_size / 5))
