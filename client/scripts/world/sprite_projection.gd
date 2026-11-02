extends RefCounted
## Factorio's own sprite for a model, projected onto it from Factorio's camera, so the model
## wears the game's grime, rust and paint. The sprite sheets are read at runtime from the
## player's Factorio install (like item icons; nothing of Wube's is copied into this repo).
## res://data/sprite_projection.json says which frame of which sheet belongs to which model and
## how it lines up (written by tools/models/sprite_projection.py, format in
## assets/models/README.md). Without Factorio, or for a model with no entry, models keep the
## procedural weathered material alone.
##
## Factorio draws an entity's sprite with an orthographic camera looking north and down at
## PITCH, 32 / scale pixels per tile, the frame's centre at the entity's position plus its
## shift, and the position marking a point `anchor` tiles above the ground (0.3 for buildings,
## see tools/models/compare.py). The shader (factorio_material.gdshaderinc) repeats that
## projection per vertex. A model's cells (one per direction it can face, or one per variation)
## go side by side in one atlas texture, each with its anchor's pixel position.

const ItemIcons := preload("res://scripts/world/item_icons.gd")

const DATA := "res://data/sprite_projection.json"
## Depth maps of the models from Factorio's camera (tools/models/projector_depth.py).
const DEPTH_DATA := "res://data/projector_depth.json"
const DEPTH_DIR := "res://data/projector_depth/"
const PITCH := 48.0
const MAX_CELLS := 8
## Vehicles ("rotation" mode): up to this many frames round the turn, in a grid atlas.
const MAX_FRAMES := 64
const VEHICLE_DELAY := 10.0  # seconds after startup that vehicles' projections start building
## Pixels round each cell, so blurred (mipmapped) lookups don't pick up the next cell.
const PAD := 32
const MODES := {"direction": 1, "variation": 2, "rotation": 3}

static var disabled := false
static var _entries := {}
static var _depth_entries := {}
static var _loaded := false
static var _cache := {}  # model name -> SpriteSheet, or null
static var _sheets := {}  # file -> Image, while building
## Vehicles' projections ("rotation" entries) read tens of megabytes of sheets, too slow for the
## startup build: a thread builds them (its own sheet cache, the textures made back here).
static var _vehicle_thread: Thread
static var _vehicle_built := {}  # model name -> SpriteSheet (texture still to make) or null
static var _thread_sheets := {}
static var _vehicle_names := {}  # name -> true while the thread or its textures are pending
static var _waiting := {}  # name -> Array of Callables to call once it is ready
## Frames cut from big sheets ahead of building on the thread ("file|x|y|w|h" -> Image), so each
## sheet is decoded once and dropped before the next (the rail sheets are 4096x8192).
static var _crops := {}


class SpriteSheet:
	var texture: ImageTexture
	var mode := 0  # 0: one cell, 1: a cell per direction (N, E, S, W), 2: a cell per variation,
	# 3: a frame per step round the turn (vehicles), in a grid of `grid` columns `slot` apart
	var cells := 1
	var grid := 1
	var slot := Vector2.ZERO
	var image: Image  # a vehicle's atlas until its texture is made on the main thread
	var anchors := PackedVector2Array()  # each cell's anchor in atlas pixels
	var atlas_size := Vector2.ONE
	var px_per_tile := 64.0
	var anchor_z := 0.3
	var top_down := false  # projected straight down (entry "projection": "top", rails)
	var across := 1.0  # north-south squash across a rail's centre line (entry "across")
	var stretch := 1.0  # north-south ground scale (pipes: their tiles are square on screen)
	## Per-pixel occlusion (DEPTH_DATA): closeness to Factorio's camera, a cell per direction.
	var depth: ImageTexture
	var depth_size := Vector2.ONE
	var depth_cells := PackedVector2Array()
	var depth_ppt := 32.0
	var mean_luminance := 0.25


static func configure_from_command_line() -> void:
	ItemIcons.configure_from_command_line()  # --factorio-data, before the install is looked for
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-sprites":
			disabled = true


## Builds every projection now (under a second), at startup: built lazily while the first
## chunks stream in, the stall made the client drop packets. Vehicles' are built on a thread.
static func build_all() -> void:
	_load()
	var started := Time.get_ticks_msec()
	var built := 0
	var vehicles: Array[String] = []
	for name in _entries:
		var entry: Dictionary = _entries[name]
		# Vehicles and entries marked "deferred" (rails: huge sheets) build on the thread.
		if str(entry.get("mode", "")) == "rotation" or bool(entry.get("deferred", false)):
			if has_entry(str(name)):
				vehicles.append(str(name))
				_vehicle_names[str(name)] = true
			continue
		if for_model(str(name)) != null:
			built += 1
	_sheets.clear()
	if not vehicles.is_empty() and _vehicle_thread == null:
		_vehicle_thread = Thread.new()
		# After the first chunks have streamed in: decoding the sheets alongside that burst
		# still cost the client a packet.
		var tree := Engine.get_main_loop() as SceneTree
		tree.create_timer(VEHICLE_DELAY).timeout.connect(func() -> void:
			_vehicle_thread.start(_build_vehicles.bind(vehicles), Thread.PRIORITY_LOW)
			tree.process_frame.connect(_poll_vehicles))
	if built > 0:
		print("sprite projection: %d models in %d ms" % [built, Time.get_ticks_msec() - started])


static func has_entry(name: String) -> bool:
	_load()
	if disabled or not _entries.has(name):
		return false
	var data := ItemIcons.factorio_data_dir()
	return data != "" and DirAccess.dir_exists_absolute(data.path_join("base/graphics/entity"))


## The projection for a model, built on first use; null without an entry or a Factorio install.
static func for_model(name: String) -> SpriteSheet:
	if _cache.has(name):
		return _cache[name]
	if _vehicle_names.has(name):
		_collect_vehicles()
		if _cache.has(name):
			return _cache[name]
	var p: SpriteSheet = null
	if has_entry(name):
		p = _build(name, _entries[name])
		if p != null and p.texture == null and p.image != null:
			p.texture = ImageTexture.create_from_image(p.image)
			p.image = null
		if p == null:
			push_warning("sprite projection: couldn't build %s from Factorio's files" % name)
	_cache[name] = p
	return p


## An entity's sheet for drawing it flat in the UI (the blueprint window's preview), whether or
## not models wear the projection (Settings' look): null without an entry or a Factorio install,
## and for vehicles (their frames round the turn are built on a thread).
static var _flat_cache := {}


static func for_flat(name: String) -> SpriteSheet:
	if _cache.get(name) != null:
		return _cache[name]
	if _flat_cache.has(name):
		return _flat_cache[name]
	_load()
	var p: SpriteSheet = null
	var entry: Dictionary = _entries.get(name, {})
	if not entry.is_empty() and MODES.get(str(entry.get("mode", "")), 0) != 3 and ItemIcons.factorio_data_dir() != "":
		p = _build(name, entry)
	_flat_cache[name] = p
	return p


## True while a vehicle's projection is still being built: ask for it with when_ready instead,
## rather than stalling the game until the thread is done.
static func pending(name: String) -> bool:
	return _vehicle_names.has(name)


static func when_ready(name: String, callback: Callable) -> void:
	if not _waiting.has(name):
		_waiting[name] = []
	_waiting[name].append(callback)


## Sets a Factorio material's sprite uniforms (factorio_material.gdshaderinc).
static func apply(material: ShaderMaterial, p: SpriteSheet) -> void:
	material.set_shader_parameter("sprite_cells", p.cells)
	material.set_shader_parameter("sprite_mode", p.mode)
	material.set_shader_parameter("sprite_frames", p.cells)
	material.set_shader_parameter("sprite_grid", p.grid)
	material.set_shader_parameter("sprite_slot", p.slot)
	material.set_shader_parameter("sprite_tex", p.texture)
	var anchors := p.anchors.duplicate()
	anchors.resize(MAX_CELLS)
	material.set_shader_parameter("sprite_anchor", anchors)
	material.set_shader_parameter("sprite_atlas_size", p.atlas_size)
	material.set_shader_parameter("sprite_ppt", p.px_per_tile)
	material.set_shader_parameter("sprite_anchor_z", p.anchor_z)
	material.set_shader_parameter("sprite_top_down", p.top_down)
	material.set_shader_parameter("sprite_across", p.across)
	material.set_shader_parameter("sprite_stretch", p.stretch)
	material.set_shader_parameter("sprite_mean_luminance", p.mean_luminance)
	material.set_shader_parameter("depth_on", p.depth != null)
	if p.depth != null:
		material.set_shader_parameter("depth_tex", p.depth)
		material.set_shader_parameter("depth_size", p.depth_size)
		var cells := p.depth_cells.duplicate()
		cells.resize(4)
		material.set_shader_parameter("depth_cell", cells)
		material.set_shader_parameter("depth_ppt", p.depth_ppt)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if parsed is Dictionary:
		_entries = parsed
	if FileAccess.file_exists(DEPTH_DATA):
		var depth = JSON.parse_string(FileAccess.get_file_as_string(DEPTH_DATA))
		if depth is Dictionary:
			_depth_entries = depth


## The model's depth map from Factorio's camera, if projector_depth.py made one.
static func _load_depth(p: SpriteSheet, name: String) -> void:
	var info = _depth_entries.get(name)
	var path := DEPTH_DIR + name + ".bin"
	if not info is Dictionary or not FileAccess.file_exists(path):
		return
	var size: Array = info.get("size", [0, 0])
	var w := int(size[0])
	var h := int(size[1])
	var data := FileAccess.get_file_as_bytes(path).decompress(w * h * 2, FileAccess.COMPRESSION_DEFLATE)
	if w <= 0 or h <= 0 or data.size() != w * h * 2:
		return
	p.depth = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RH, data))
	p.depth_size = Vector2(w, h)
	p.depth_ppt = float(info.get("ppt", 32))
	for c in info.get("cells", []):
		p.depth_cells.append(Vector2(float(c[0]), float(c[1])))


static func _build(name: String, entry: Dictionary) -> SpriteSheet:
	var p := SpriteSheet.new()
	p.mode = MODES.get(str(entry.get("mode", "")), 0)
	p.anchor_z = float(entry.get("anchor", 0.3))
	p.top_down = str(entry.get("projection", "")) == "top"
	p.across = float(entry.get("across", 1.0))
	p.stretch = float(entry.get("stretch", 1.0))
	var cells: Array = entry.get("cells", [])
	if cells.is_empty() or cells.size() > (MAX_FRAMES if p.mode == 3 else MAX_CELLS):
		return null
	if p.mode == 3:
		return _build_rotation(p, cells, float(entry.get("atlas_scale", 1.0)))
	# Each cell: its layers stacked on one canvas, and where the anchor is on it.
	var canvases: Array[Image] = []
	var anchors: Array[Vector2] = []
	var slot := Vector2i.ZERO
	var scale := float(entry.get("atlas_scale", 1.0))
	for cell in cells:
		var layers: Array = cell
		var composed := _compose(layers)
		if composed.is_empty():
			return null
		if scale != 1.0:
			var c: Image = composed[0]
			c.resize(maxi(1, int(c.get_width() * scale)), maxi(1, int(c.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
			composed[1] *= scale
			composed[2] *= scale
		canvases.append(composed[0])
		anchors.append(composed[1])
		p.px_per_tile = composed[2]
		slot.x = maxi(slot.x, composed[0].get_width() + 2 * PAD)
		slot.y = maxi(slot.y, composed[0].get_height() + 2 * PAD)
	var atlas := Image.create(slot.x * canvases.size(), slot.y, false, Image.FORMAT_RGBA8)
	for i in canvases.size():
		var canvas := canvases[i]
		var at := Vector2i(slot.x * i + PAD, PAD)
		atlas.blend_rect(canvas, Rect2i(Vector2i.ZERO, canvas.get_size()), at)
		p.anchors.append(Vector2(at) + anchors[i])
	p.cells = canvases.size()
	p.atlas_size = Vector2(atlas.get_size())
	p.mean_luminance = _mean_luminance(atlas)
	# Transparent pixels take their neighbours' colour, so filtering and the blurred mip levels
	# the shader uses to flatten the baked-in lighting don't darken towards the outline.
	atlas.fix_alpha_edges()
	atlas.generate_mipmaps()
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		p.image = atlas  # its texture is made on the main thread (_finish_vehicle)
	else:
		p.texture = ImageTexture.create_from_image(atlas)
	_load_depth(p, name)
	return p


## A vehicle's frames round the turn in a square-ish grid, each placed so its anchor sits at the
## same spot in its slot (the shader finds frame f's anchor from frame 0's). `scale` shrinks the
## atlas (trains' frames are large).
static func _build_rotation(p: SpriteSheet, cells: Array, scale: float) -> SpriteSheet:
	var canvases: Array[Image] = []
	var anchors: Array[Vector2] = []
	var lo := Vector2.ZERO  # largest anchor offset
	var hi := Vector2.ZERO  # largest extent past the anchor
	for cell in cells:
		var composed := _compose(cell)
		if composed.is_empty():
			return null
		var canvas: Image = composed[0]
		var anchor: Vector2 = composed[1]
		if scale != 1.0:
			canvas.resize(maxi(1, int(canvas.get_width() * scale)), maxi(1, int(canvas.get_height() * scale)), Image.INTERPOLATE_BILINEAR)
			anchor *= scale
		p.px_per_tile = composed[2] * scale
		canvases.append(canvas)
		anchors.append(anchor)
		lo = lo.max(anchor)
		hi = hi.max(Vector2(canvas.get_size()) - anchor)
	var slot := Vector2i((lo + hi).ceil()) + Vector2i(2 * PAD, 2 * PAD)
	p.cells = canvases.size()
	p.grid = int(ceil(sqrt(float(p.cells))))
	var rows := int(ceil(float(p.cells) / p.grid))
	var atlas := Image.create(slot.x * p.grid, slot.y * rows, false, Image.FORMAT_RGBA8)
	for i in canvases.size():
		var origin := Vector2i((i % p.grid) * slot.x, (i / p.grid) * slot.y) + Vector2i(PAD, PAD)
		var at := origin + Vector2i((lo - anchors[i]).round())
		atlas.blend_rect(canvases[i], Rect2i(Vector2i.ZERO, canvases[i].get_size()), at)
	p.anchors.append(Vector2(PAD, PAD) + lo)
	p.slot = Vector2(slot)
	p.atlas_size = Vector2(atlas.get_size())
	p.mean_luminance = _mean_luminance(atlas)
	atlas.fix_alpha_edges()
	atlas.generate_mipmaps()
	p.image = atlas
	return p


## [canvas Image, anchor position on it (pixels), pixels per tile], or [] if a sheet is missing.
static func _compose(layers: Array) -> Array:
	var frames: Array[Image] = []
	var offsets: Array[Vector2] = []
	var ppt := 64.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for item in layers:
		var layer: Dictionary = item
		var frame := _frame(layer)
		if frame == null:
			return []
		ppt = 32.0 / float(layer.get("scale", 0.5))
		var shift: Array = layer.get("shift", [0, 0])
		# The frame's centre is the anchor plus the shift (util.by_pixel units: 1/32 tile).
		var centre := Vector2(float(shift[0]), float(shift[1])) * ppt / 32.0
		var size := Vector2(frame.get_size())
		frames.append(frame)
		offsets.append(centre - size / 2.0)
		lo = lo.min(centre - size / 2.0)
		hi = hi.max(centre + size / 2.0)
	var canvas := Image.create(int(ceil(hi.x - lo.x)), int(ceil(hi.y - lo.y)), false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var at := Vector2i((offsets[i] - lo).round())
		canvas.blend_rect(frames[i], Rect2i(Vector2i.ZERO, frames[i].get_size()), at)
	return [canvas, -lo, ppt]


## The frame's rectangle on its sheet: `xy` (pixels) when given, else `index` in a grid of
## `line` frames a row. `sheet_width` is needed only when `line` is 0 (as many as fit).
static func _frame_rect(layer: Dictionary, sheet_width: int) -> Rect2i:
	var size: Array = layer.get("frame", [0, 0])
	var w := int(size[0])
	var h := int(size[1])
	if layer.has("xy"):
		var xy: Array = layer["xy"]
		return Rect2i(int(xy[0]), int(xy[1]), w, h)
	var line := int(layer.get("line", 0))
	if line <= 0:
		line = maxi(1, sheet_width / maxi(w, 1))
	var index := int(layer.get("index", 0))
	return Rect2i((index % line) * w, (index / line) * h, w, h)


static func _crop_key(file: String, rect: Rect2i) -> String:
	return "%s|%d|%d|%d|%d" % [file, rect.position.x, rect.position.y, rect.size.x, rect.size.y]


## Cuts every frame the named entries need out of their sheets, one sheet in memory at a time.
static func _prefetch(names: Array[String]) -> void:
	var wanted := {}  # file -> {crop key: Rect2i}
	for name in names:
		for cell in _entries[name].get("cells", []):
			for item in cell:
				var layer: Dictionary = item
				if not layer.has("xy") and int(layer.get("line", 0)) <= 0:
					continue  # needs the sheet's width: cut when built
				var file := str(layer.get("file", ""))
				var rect := _frame_rect(layer, 0)
				if not wanted.has(file):
					wanted[file] = {}
				wanted[file][_crop_key(file, rect)] = rect
	for file in wanted:
		var path := ItemIcons.factorio_data_dir().path_join(file)
		if not FileAccess.file_exists(path):
			continue
		var sheet := Image.load_from_file(path)
		if sheet == null:
			continue
		sheet.convert(Image.FORMAT_RGBA8)
		var bounds := Rect2i(Vector2i.ZERO, sheet.get_size())
		for key in wanted[file]:
			var rect: Rect2i = wanted[file][key]
			if bounds.encloses(rect) and rect.size.x > 0 and rect.size.y > 0:
				_crops[key] = sheet.get_region(rect)


static func _frame(layer: Dictionary) -> Image:
	var file := str(layer.get("file", ""))
	var frame: Image = null
	if layer.has("xy") or int(layer.get("line", 0)) > 0:
		var key := _crop_key(file, _frame_rect(layer, 0))
		if _crops.has(key):
			frame = (_crops[key] as Image).duplicate() as Image
	if frame == null:
		var sheet := _sheet(file)
		if sheet == null:
			return null
		var rect := _frame_rect(layer, sheet.get_width())
		if rect.size.x <= 0 or rect.size.y <= 0 or not Rect2i(Vector2i.ZERO, sheet.get_size()).encloses(rect):
			return null
		frame = sheet.get_region(rect)
	if layer.has("tint"):
		_tint(frame, layer["tint"])
	return frame


## Deferred entries share their sheets (every rail piece is cut from the same five), so their
## frames are cut in one pass; each vehicle has sheets of its own.
static func _build_vehicles(names: Array[String]) -> void:
	var shared: Array[String] = []
	for name in names:
		if str(_entries[name].get("mode", "")) != "rotation":
			shared.append(name)
	_prefetch(shared)
	for name in shared:
		_vehicle_built[name] = _build(name, _entries[name])
	_crops.clear()
	for name in names:
		if not shared.has(name):
			var one: Array[String] = [name]
			_prefetch(one)
			_vehicle_built[name] = _build(name, _entries[name])
			_thread_sheets.clear()
			_crops.clear()


## Once the thread is done, makes one vehicle's texture a frame (each is a big upload).
static func _poll_vehicles() -> void:
	if _vehicle_thread != null and (_vehicle_thread.is_alive() or not _vehicle_thread.is_started()):
		return
	if _vehicle_thread != null:
		_vehicle_thread.wait_to_finish()
		_vehicle_thread = null
	if _vehicle_built.is_empty():
		(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_poll_vehicles)
		return
	_finish_vehicle(str(_vehicle_built.keys()[0]))


## Waits for the vehicle thread (normally long done by the time a vehicle shows up) and gives
## its projections their textures.
static func _collect_vehicles() -> void:
	if _vehicle_thread != null and _vehicle_thread.is_started():
		_vehicle_thread.wait_to_finish()
		_vehicle_thread = null
	for name in _vehicle_built.keys():
		_finish_vehicle(str(name))


static func _finish_vehicle(name: String) -> void:
	var p: SpriteSheet = _vehicle_built[name]
	_vehicle_built.erase(name)
	if p != null:
		p.texture = ImageTexture.create_from_image(p.image)
		p.image = null
	else:
		push_warning("sprite projection: couldn't build %s from Factorio's files" % name)
	_cache[name] = p
	_vehicle_names.erase(name)
	for callback in _waiting.get(name, []):
		callback.call()
	_waiting.erase(name)


static func _sheet(file: String) -> Image:
	var on_thread := OS.get_thread_caller_id() != OS.get_main_thread_id()
	var cache := _thread_sheets if on_thread else _sheets
	if cache.has(file):
		return cache[file]
	var path := ItemIcons.factorio_data_dir().path_join(file)
	var image: Image = null
	if FileAccess.file_exists(path):
		image = Image.load_from_file(path)
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
	cache[file] = image
	return image


## Multiplies the colour (as the game tints a tree's leaves).
static func _tint(image: Image, tint: Array) -> void:
	var data := image.get_data()
	var t := [float(tint[0]), float(tint[1]), float(tint[2])]
	for i in range(0, data.size(), 4):
		data[i] = int(data[i] * t[0])
		data[i + 1] = int(data[i + 1] * t[1])
		data[i + 2] = int(data[i + 2] * t[2])
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)


## Mean linear luminance of the opaque pixels (the level the shader flattens lighting towards).
static func _mean_luminance(atlas: Image) -> float:
	var small := atlas.duplicate() as Image
	small.resize(maxi(1, atlas.get_width() / 8), maxi(1, atlas.get_height() / 8), Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	var weight := 0.0
	for y in small.get_height():
		for x in small.get_width():
			var c := small.get_pixel(x, y)
			if c.a > 0.5:
				var l := c.srgb_to_linear()
				total += (0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b) * c.a
				weight += c.a
	return total / weight if weight > 0.0 else 0.25
