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

var _groups := {}  # kind -> [CanvasGroup, Control]
## Robots, signals, stops and recipe icons, over the coverage areas (a node draws under its children).
var marks := Control.new()
## _visible_entries' lists this frame, by [margin, centre, scale, size, frame].
var _entries := {}
var _entries_frame := -1
## follow(): how far what is drawn may be moved before it is drawn again, how often new data is
## drawn at most, and the state of the last drawing.
const SHIFT_PX := 24.0
const DATA_REDRAW_MSEC := 250
var _stale := false
var _drawn_msec := 0
var _drawn_size := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for spec in [["construction", 0.16], ["logistic", 0.28], ["electric", 0.3], ["turret", 0.22]]:
		var group := CanvasGroup.new()
		group.self_modulate = Color(1, 1, 1, spec[1])
		add_child(group)
		var canvas := Control.new()
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var kind: String = spec[0]
		canvas.draw.connect(func() -> void: _draw_areas(canvas, kind))
		group.add_child(canvas)
		_groups[kind] = [group, canvas]
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	marks.draw.connect(_draw_marks)
	add_child(marks)


## The minimap's way of redrawing: while the view only moves a little, what is drawn moves with it
## instead of being drawn again (thousands of areas on a big base: 2 ms a frame while walking). It is
## drawn again once it has moved SHIFT_PX, the zoom or size changed, or the data `changed` (at most
## every DATA_REDRAW_MSEC). Everything is drawn SHIFT_PX past the edges, so moving shows no seam.
func follow(at: Vector2, scale: float, changed: bool) -> void:
	_stale = _stale or changed
	var offset := (centre - at) * scale
	var now := Time.get_ticks_msec()
	if is_equal_approx(scale, scale_px) and size == _drawn_size and offset.length() <= SHIFT_PX and not (_stale and now - _drawn_msec >= DATA_REDRAW_MSEC):
		_shift(offset)
		return
	_stale = false
	_drawn_msec = now
	redraw(at, scale)


func _shift(offset: Vector2) -> void:
	for kind in _groups:
		(_groups[kind][1] as Control).position = offset
	marks.position = offset


## Redraws for a view now drawn around `at` (tiles) at `scale` screen pixels per tile.
func redraw(at: Vector2, scale: float) -> void:
	centre = at
	scale_px = scale
	_drawn_size = size
	_shift(Vector2.ZERO)
	for kind in _groups:
		var g: Array = _groups[kind]
		(g[0] as CanvasGroup).visible = _shown(kind)
		(g[1] as Control).size = size
		(g[1] as Control).queue_redraw()
	marks.size = size
	marks.queue_redraw()


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
	return Vector2(SHIFT_PX, SHIFT_PX) / maxf(scale_px, 0.001)


func to_screen(t: Vector2) -> Vector2:
	return size / 2.0 + (t - centre) * scale_px


## The overlay entries within the view (and `margin` tiles around it). The minimap redraws every
## frame while the character walks, and its layers ask for these six times: looking through every
## charted chunk's list each time took 3-4 ms a frame on a big base. The chunks in view are looked
## up instead, and each margin's list is kept for the frame.
func _visible_entries(margin: float) -> Array:
	if model == null:
		return []
	var key := [margin, centre, scale_px, size, Engine.get_process_frames()]
	if _entries.has(key):
		return _entries[key]
	if _entries_frame != Engine.get_process_frames():
		_entries.clear()
		_entries_frame = Engine.get_process_frames()
	var out: Array = []
	var half := size / 2.0 / scale_px + Vector2(margin, margin) + _slack()
	var view := Rect2(centre - half, half * 2.0)
	var overlays: Dictionary = model.map_overlays
	var lo := Vector2i((view.position / 32.0).floor()) - Vector2i.ONE
	var hi := Vector2i((view.end / 32.0).floor()) + Vector2i.ONE
	if (hi.x - lo.x + 1) * (hi.y - lo.y + 1) <= overlays.size():
		for cy in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				var list = overlays.get(Vector2i(cx, cy))
				if list != null:
					for r in list:
						if view.has_point(Vector2(r[1], r[2])):
							out.append(r)
	else:  # zoomed far out over few charted chunks
		var chunks := Rect2(view.position / 32.0 - Vector2.ONE, view.size / 32.0 + Vector2(2, 2))
		for chunk in overlays:
			if chunks.has_point(Vector2(chunk)):
				for r in overlays[chunk]:
					if view.has_point(Vector2(r[1], r[2])):
						out.append(r)
	_entries[key] = out
	return out


func _draw_areas(canvas: Control, kind: String) -> void:
	if kind == "logistic" or kind == "construction":
		var colour := LOGISTIC if kind == "logistic" else CONSTRUCTION
		for square: Rect2 in roboport_squares(kind):
			canvas.draw_rect(square, colour)
		return
	var want := "e" if kind == "electric" else "t"
	var color := ELECTRIC if kind == "electric" else TURRET
	for r in _visible_entries(60.0):
		if r[0] != want:
			continue
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
	for row in _visible_entries(60.0 if kind == "logistic" else 120.0):
		if row[0] != "l" or model.has_roboport_at(si, Vector2i(roundi(row[1] * 256.0), roundi(row[2] * 256.0))):
			continue
		var r := float(row[k + 1])
		out.append(Rect2(to_screen(Vector2(row[1], row[2]) - Vector2(r, r)), Vector2(r, r) * 2.0 * scale_px))
	return out


## Dims the charted chunks in view that no radar, roboport (or the character) sees now.
func _draw_unseen() -> void:
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
				marks.draw_rect(Rect2(to_screen(Vector2(chunk) * 32.0), Vector2(32, 32) * scale_px), UNSEEN)


## The stripes' period in tiles at this zoom: whole tiles, doubling as the map zooms out, so they
## keep about the same width on screen without crawling while zooming.
static func stripe_period(scale: float) -> float:
	var period := 4.0
	while period * scale < STRIPE_PX * 2.0:
		period *= 2.0
	return period


## Demolisher territories' ground: each chunk washed red with diagonal bands (x + y in a
## stripe's half of the period) that run on unbroken from chunk to chunk; the borders go over them.
func _draw_territories() -> void:
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
		marks.draw_rect(Rect2(to_screen(area.position), area.size * scale_px), TERRITORY_WASH)
		if not striped:
			continue
		var low := area.position.x + area.position.y
		var k := floorf(low / period) * period
		while k < low + 64.0:
			var band := stripe_band(area, k, k + period / 2.0)
			if band.size() >= 3:
				for i in band.size():
					band[i] = to_screen(band[i])
				marks.draw_colored_polygon(band, TERRITORY_STRIPE)
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
		marks.draw_set_transform(to_screen(at), cars[i + 2] / 1000.0 * TAU, Vector2.ONE)
		marks.draw_rect(Rect2(-width / 2.0, -length / 2.0, width, length), colour)
		marks.draw_rect(Rect2(-width / 2.0, -length / 2.0, width, length), Color(0, 0, 0, 0.6), false, 1.0)
	marks.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_marks() -> void:
	_draw_unseen()
	if model != null and bool(settings.get_value("map/show_pollution")) and not model.map_pollution.is_empty():
		var half := size / 2.0 / scale_px + Vector2(32, 32) + _slack()
		var view := Rect2(centre - half, half * 2.0)
		for chunk: Vector2i in model.map_pollution:
			var area := Rect2(Vector2(chunk) * 32.0, Vector2(32, 32))
			if view.intersects(area):
				var a := pollution_alpha(float(model.map_pollution[chunk]))
				marks.draw_rect(Rect2(to_screen(area.position), area.size * scale_px), Color(POLLUTION, a))
	if model != null and not model.territory_edges.is_empty() and model.territories_shown():
		_draw_territories()
		var half := size / 2.0 / scale_px + Vector2(32, 32) + _slack()
		var view := Rect2(centre - half, half * 2.0)
		var edges: PackedVector2Array = model.territory_edges
		for i in range(0, edges.size() - 1, 2):
			if view.has_point(edges[i]) or view.has_point(edges[i + 1]):
				marks.draw_line(to_screen(edges[i]), to_screen(edges[i + 1]), TERRITORY, maxf(1.5, 0.15 * scale_px))
	if bool(settings.get_value("map/show_electric")) and scale_px >= 0.5:
		# A wire's start can be far outside the view while it crosses it: a wide margin.
		for r in _visible_entries(64.0):
			if str(r[0]) == "w" and r.size() >= 5:
				marks.draw_line(to_screen(Vector2(r[1], r[2])), to_screen(Vector2(r[3], r[4])), WIRE, maxf(1.0, 0.12 * scale_px), true)
	_draw_trains()
	var robots := bool(settings.get_value("map/show_robots"))
	var signals := bool(settings.get_value("map/show_signals"))
	var stops := bool(settings.get_value("map/show_stops"))
	var recipes := bool(settings.get_value("map/show_recipes"))
	if not (robots or signals or stops or recipes):
		return
	var font := Kit.font("semibold")
	var font_size := Kit.px(14)
	for r in _visible_entries(8.0):
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
