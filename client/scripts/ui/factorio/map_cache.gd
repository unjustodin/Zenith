extends RefCounted
## The map's pictures and the requests behind them, shared by the minimap and the map view.
##
## Charts (ui_model.gd's `map_charts`, one small Image per chunk) are copied into pages of 16 x 16
## chunks as they arrive, at 2 tiles per pixel (the finest the mod sends); a page's texture is
## updated at most once a frame (flush), so drawing is a few textured rectangles whatever the zoom.
##
## The mod charts one rectangle at a time (a new `map` request replaces the old) and sends 4 chunks
## a tick, at most 32 x 32 chunks per request. So the view says what it wants (want()) and this
## sends it in blocks of up to 32 x 32 chunks, nearest the middle first, the next once the last has
## arrived (or nothing more came for a while: charts are sent unreliably, and a busy game sends them
## slower), and asks again for the same area only every `refresh` seconds. Charts that didn't arrive
## are asked for once more straight away. Ground known to be uncharted is skipped (only its edge
## next to charted ground is asked again, where the map grows), except in a full pass every
## FULL_PASS seconds, which finds what radars charted far away.

signal updated

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

## Factorio's default player colour (the character's map marker).
const PLAYER_COLOR := Color(0.869, 0.5, 0.130)
const CHUNK := 32
## Page pixels per chunk: 2 tiles per pixel.
const CHUNK_PX := 16
## Chunks per page side.
const PAGE := 16
const PAGE_TILES := PAGE * CHUNK
## The mod's limit per request (map.lua: MAX_CHUNKS = 1024).
const MAX_BLOCK := 32
const RESOLUTIONS := [2, 4, 8, 16, 32]
## A block is taken as finished when no chart of it came for this long.
const QUIET := 1.5
## Requests are at least this far apart, so dragging the map doesn't send one every frame.
const MIN_GAP := 0.3
## Seconds between passes that ask for uncharted ground too.
const FULL_PASS := 60.0
## Chunks of uncharted ground asked for around charted ground (the force charts 3 around the character).
const FRONTIER := 3

var model
var _pages := {}  # Vector2i page -> [Image, ImageTexture or null]
var _dirty := {}  # page -> true
var _charted := {}  # chunk -> when (seconds) its last picture arrived
var _uncharted := {}  # chunk -> true when it came back uncharted (and never charted)

var _goal := Rect2i()  # chunks wanted (position = first chunk, size in chunks)
var _goal_res := 0
var _goal_refresh := 5.0
var _goal_started := -1e9  # when the current pass over _goal began
var _blocks: Array = []  # [Rect2i, ...] still to send this pass
var _pending := {}  # chunk -> true, in the block in flight
var _retried := false  # the block in flight is already a retry
var _last_full := -1e9
var _last_arrival := -1e9
var _last_send := -1e9
## Requests sent, for tests and the F4 line.
var requests_sent := 0
## Stretches every view's refresh (the UPS governor raises it when the game runs slow: each chart
## costs the mod time in the game's tick).
var refresh_scale := 1.0
## Small areas others want charted (train cards for trains far away), asked for by the minimap one
## at a time when nothing else is (minimap.gd _ask).
var spots: Array[Rect2i] = []
## The surface the pictures are of (model.shown_surface()), and the others seen while the map was
## switched to them: si -> [pages, charted, uncharted].
var _si := 0
var _stash := {}


func _init(ui_model) -> void:
	model = ui_model
	model.map_changed.connect(_on_chart)
	model.map_surfaces_changed.connect(_on_surface)


## The map shows another surface (the map view's switcher): keep this one's pictures for when it
## comes back, and start from that one's.
func _on_surface() -> void:
	var si: int = model.shown_surface()
	if si == _si:
		return
	if _si == 0:  # the first surface named (welcome): the pictures so far are its own
		_si = si
		return
	_stash[_si] = [_pages, _charted, _uncharted]
	var back: Array = _stash.get(si, [{}, {}, {}])
	_stash.erase(si)
	_pages = back[0]
	_charted = back[1]
	_uncharted = back[2]
	_si = si
	_dirty.clear()
	_blocks.clear()
	_pending.clear()
	_goal = Rect2i()
	_goal_res = 0
	_last_full = -1e9
	updated.emit()


## Forgets every chart and tag (the character moved to another surface, which has its own map);
## the views ask for the new surface's charts on their next want().
func reset() -> void:
	_stash.clear()
	_si = model.shown_surface()
	_pages = {}
	_dirty.clear()
	_charted = {}
	_uncharted = {}
	_blocks.clear()
	_pending.clear()
	_goal = Rect2i()
	_goal_res = 0
	_last_full = -1e9
	model.map_charts.clear()
	model.map_overlays.clear()
	model.map_tags.clear()
	model.tags_changed.emit()
	updated.emit()


## The chunks covering a rectangle of tiles.
static func chunks_of(tiles: Rect2) -> Rect2i:
	var a := Vector2i(floori(tiles.position.x / CHUNK), floori(tiles.position.y / CHUNK))
	var b := Vector2i(floori(tiles.end.x / CHUNK), floori(tiles.end.y / CHUNK))
	return Rect2i(a, b - a + Vector2i.ONE)


## The coarsest chart that still gives about a pixel per screen pixel at `scale` screen pixels per tile.
static func resolution_for(scale: float) -> int:
	for res in RESOLUTIONS:
		if res * scale >= 1.0:
			return res
	return RESOLUTIONS[-1]


## The area a view shows, at the chart resolution it needs; call every frame. Charts are
## snapshots, so the same area is asked for again every `refresh` seconds.
func want(chunks: Rect2i, res: int, refresh: float) -> void:
	var now := _now()
	if chunks != _goal or res != _goal_res:
		# The same view moved (the minimap following the character): only the chunks it hasn't had
		# a picture of within its refresh, not its whole area again (on a busy save that was most of
		# the bridge's cost while walking: 4 ms a tick).
		var moved := res == _goal_res and refresh == _goal_refresh and chunks.intersects(_goal)
		_goal = chunks
		_goal_res = res
		_goal_refresh = refresh
		_start_pass(now, moved)
	elif _blocks.is_empty() and _idle(now) and now - _goal_started >= _goal_refresh * refresh_scale:
		_start_pass(now)
	if not _idle(now) or now - _last_send < MIN_GAP:
		return
	if not _pending.is_empty() and not _retried:
		_send(_bounds(_pending.keys()), now, true)
	elif not _blocks.is_empty():
		_send(_blocks.pop_front(), now)


## Queues a small area to chart when the cache is otherwise idle, unless it is all known already.
func ask_spot(chunks: Rect2i) -> void:
	if spots.has(chunks) or spots.size() >= 64:
		return
	for y in range(chunks.position.y, chunks.end.y):
		for x in range(chunks.position.x, chunks.end.x):
			var c := Vector2i(x, y)
			if not _charted.has(c) and not _uncharted.has(c):
				spots.append(chunks)
				return


## Still sending or waiting for the current area's blocks.
func busy() -> bool:
	return not _blocks.is_empty() or not _idle(_now())


## Nothing is coming any more for the last request.
func _idle(now: float) -> bool:
	return _pending.is_empty() or now - maxf(_last_arrival, _last_send) >= QUIET


func _start_pass(now: float, moved := false) -> void:
	if not moved:
		_goal_started = now
	_blocks.clear()
	var full := not moved and now - _last_full >= FULL_PASS
	if full:
		_last_full = now
	var centre := Vector2(_goal.position) + Vector2(_goal.size) / 2.0
	var y := _goal.position.y
	while y < _goal.end.y:
		var x := _goal.position.x
		while x < _goal.end.x:
			var block := Rect2i(x, y, mini(MAX_BLOCK, _goal.end.x - x), mini(MAX_BLOCK, _goal.end.y - y))
			if moved:
				_blocks.append_array(_stale(block, now - _goal_refresh * refresh_scale))
				block = Rect2i()
			elif not full:
				block = _trim(block)
			if block.has_area():
				_blocks.append(block)
			x += MAX_BLOCK
		y += MAX_BLOCK
	var nearest := func(a: Rect2i, b: Rect2i) -> bool:
		return (Vector2(a.get_center()) - centre).length_squared() < (Vector2(b.get_center()) - centre).length_squared()
	_blocks.sort_custom(nearest)
	# A new area replaces the request in flight at once (the mod does the same).
	_pending.clear()


## The part of a block worth asking for: chunks not known to be uncharted, and the uncharted ones
## within FRONTIER of charted ground. Empty when it is all known uncharted ground.
func _trim(block: Rect2i) -> Rect2i:
	var wanted: Array = []
	for y in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			var c := Vector2i(x, y)
			if not _uncharted.has(c):
				wanted.append(c)
	if wanted.is_empty():
		return Rect2i()
	return _bounds(wanted).grow(FRONTIER).intersection(block)


## The parts of a block not charted since `since` (known uncharted ground left to the periodic
## passes): what a moved view lacks, a strip or two. Rows of the same span join into one rectangle,
## so a diagonal move asks for an L as two pieces, not the whole block.
func _stale(block: Rect2i, since: float) -> Array:
	var out: Array = []
	var run := Rect2i()
	for y in range(block.position.y, block.end.y):
		var lo := block.end.x
		var hi := block.position.x - 1
		for x in range(block.position.x, block.end.x):
			var c := Vector2i(x, y)
			if float(_charted.get(c, -1e9)) < since and not _uncharted.has(c):
				lo = mini(lo, x)
				hi = maxi(hi, x)
		if hi < lo:
			if run.has_area():
				out.append(run)
			run = Rect2i()
		elif run.has_area() and run.position.x == lo and run.end.x == hi + 1:
			run.size.y += 1
		else:
			if run.has_area():
				out.append(run)
			run = Rect2i(lo, y, hi - lo + 1, 1)
	if run.has_area():
		out.append(run)
	return out


## The smallest rectangle holding these chunks.
static func _bounds(chunks: Array) -> Rect2i:
	var lo: Vector2i = chunks[0]
	var hi: Vector2i = chunks[0]
	for c in chunks:
		lo = lo.min(c)
		hi = hi.max(c)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _send(block: Rect2i, now: float, retry := false) -> void:
	_retried = retry
	_pending.clear()
	for y in range(block.position.y, block.end.y):
		for x in range(block.position.x, block.end.x):
			_pending[Vector2i(x, y)] = true
	_last_send = now
	requests_sent += 1
	model.request_map(block.position, block.end - Vector2i.ONE, _goal_res)


func _on_chart(chunk: Vector2i) -> void:
	if _pending.erase(chunk):
		_last_arrival = _now()
	var image: Image = model.map_charts.get(chunk)
	if image == null:
		if not _charted.has(chunk):
			_uncharted[chunk] = true
		return  # not charted (yet): stays black, or keeps what it had
	_uncharted.erase(chunk)
	var page_at := Vector2i(floori(chunk.x / float(PAGE)), floori(chunk.y / float(PAGE)))
	var page: Array = _page(page_at)
	var src := image
	if src.get_width() != CHUNK_PX or src.get_format() != Image.FORMAT_RGBA8:
		src = image.duplicate()
		src.convert(Image.FORMAT_RGBA8)
		src.resize(CHUNK_PX, CHUNK_PX, Image.INTERPOLATE_NEAREST)
	(page[0] as Image).blit_rect(src, Rect2i(0, 0, CHUNK_PX, CHUNK_PX), (chunk - page_at * PAGE) * CHUNK_PX)
	_dirty[page_at] = true
	_charted[chunk] = _now()


func _page(at: Vector2i) -> Array:
	if not _pages.has(at):
		var image := Image.create(PAGE * CHUNK_PX, PAGE * CHUNK_PX, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		_pages[at] = [image, null]
	return _pages[at]


func is_charted(chunk: Vector2i) -> bool:
	return _charted.has(chunk)


## Uploads the pages that changed since the last call; emits `updated` if any did.
func flush() -> void:
	if _dirty.is_empty():
		return
	# Each upload gets its own copy of the page: with the renderer on its own thread the upload
	# happens later, there, while new charts are drawn into the page here (the render thread then
	# read a page half-written, or empty: "p_image->is_empty()" in texture_2d_update).
	for at in _dirty:
		var page: Array = _pages[at]
		if page[1] == null:
			page[1] = ImageTexture.create_from_image((page[0] as Image).duplicate())
		else:
			(page[1] as ImageTexture).update((page[0] as Image).duplicate())
	_dirty.clear()
	updated.emit()


## Draws the charted map into `area` of a canvas item, `centre` (tiles) in the middle, at `scale`
## screen pixels per tile. Uncharted ground is left as it is (draw black under it).
func draw(canvas: CanvasItem, area: Rect2, centre: Vector2, scale: float) -> void:
	var middle := area.position + area.size / 2.0
	var half := area.size / 2.0 / scale
	var first := Vector2i(floori((centre.x - half.x) / PAGE_TILES), floori((centre.y - half.y) / PAGE_TILES))
	var last := Vector2i(floori((centre.x + half.x) / PAGE_TILES), floori((centre.y + half.y) / PAGE_TILES))
	for py in range(first.y, last.y + 1):
		for px in range(first.x, last.x + 1):
			var page: Array = _pages.get(Vector2i(px, py), [])
			if page.is_empty() or page[1] == null:
				continue
			# Rounded corners so neighbouring pages meet without a seam.
			var a := (middle + (Vector2(px, py) * PAGE_TILES - centre) * scale).round()
			var b := (middle + (Vector2(px + 1, py + 1) * PAGE_TILES - centre) * scale).round()
			canvas.draw_texture_rect(page[1], Rect2(a, b - a), false)


## The character on the map: an arrow in Factorio's default player colour, pointing `heading`
## (radians clockwise from north), `size` screen pixels long.
static func draw_player(canvas: CanvasItem, at: Vector2, heading: float, size: float) -> void:
	var fwd := Vector2(sin(heading), -cos(heading))
	var side := Vector2(-fwd.y, fwd.x)
	var tip := at + fwd * size * 0.55
	var back := at - fwd * size * 0.45
	var notch := at - fwd * size * 0.18
	var points := PackedVector2Array([tip, back + side * size * 0.4, notch, back - side * size * 0.4])
	var outline := PackedVector2Array(points)
	outline.append(tip)
	canvas.draw_colored_polygon(points, PLAYER_COLOR)
	canvas.draw_polyline(outline, Color(0, 0, 0, 0.9), maxf(1.0, size / 10.0), true)


## A map tag: its icon (or Factorio's green pin when it has none) and, if `show_text`, its text to
## the right in white with a dark outline, as on Factorio's map.
static func draw_tag(canvas: CanvasItem, at: Vector2, tag: Dictionary, size: float, show_text: bool, font: Font, font_size: int) -> void:
	var icon_name := str(tag.get("icon_name", ""))
	var icon: Texture2D = null
	if icon_name != "":
		icon = Kit.item_icon(icon_name)
		canvas.draw_texture_rect(icon, Rect2(at - Vector2(size, size) / 2.0, Vector2(size, size)), false)
	else:
		var pin := tag_pin()
		if pin != null:
			var w := size * pin.get_width() / pin.get_height()
			canvas.draw_texture_rect(pin, Rect2(at - Vector2(w / 2.0, size), Vector2(w, size)), false)
		else:
			canvas.draw_circle(at, size * 0.3, Color(0.75, 1.0, 0.0))
	var text := str(tag.get("text", ""))
	if show_text and text != "" and font != null:
		var pos := at + Vector2(size * 0.6, font_size * 0.35 - (size * 0.5 if icon == null else 0.0))
		RichText.draw(canvas, font, pos, text, font_size, Color.WHITE, maxi(2, font_size / 5))


## Map pings ([[position (tiles), 0..1 of their time], ...]): Factorio's expanding rings, at
## to_screen(position).
static func draw_pings(canvas: CanvasItem, pings: Array, to_screen: Callable, size: float) -> void:
	for p in pings:
		var at: Vector2 = to_screen.call(p[0])
		var t := float(p[1])
		for ring in 2:
			var f := fposmod(t * 3.0 + ring * 0.5, 1.0)
			canvas.draw_arc(at, size * (0.3 + f), 0.0, TAU, 32, Color(1.0, 0.85, 0.2, (1.0 - f) * (1.0 - t)), maxf(1.0, size * 0.08))
		canvas.draw_circle(at, size * 0.18, Color(1.0, 0.85, 0.2, 1.0 - t))


## core/graphics/custom-tag-in-map-view.png from the install (null without one).
static func tag_pin() -> Texture2D:
	return GuiAssets.core_sprite("custom-tag-in-map-view.png")


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
