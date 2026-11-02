extends RefCounted
## Factorio's own tile graphics on the ground, read at runtime from the player's install like the
## item icons and model sprites (nothing of Wube's is copied into this repo):
##
##   <data>/base/prototypes/tile/tiles.lua (and space-age's)   which picture, variant sizes,
##                                                             weights and layer each tile has
##   <data>/<mod>/graphics/terrain/*.png                       the pictures
##
## Each tile type that appears in a loaded chunk gets one layer of a Texture2DArray, repacked from
## Factorio's sheet into the same slot layout (64 px per tile, 32 x 16 slots):
##   rows 0-7   4x4 variants, 8 per row      (or material backgrounds: concrete, landfill...)
##   rows 8-9   2x2 variants, 16 per row
##   row 10     1x1 variants
## chunk_view.gd picks a variant for every tile the way Factorio does (bigger blocks where the
## whole aligned block is that tile and a roll passes, weighted variants) and puts its slot in the
## tile's UVs. Without an install, or for a tile whose graphics can't be read, layer() is -1 and
## the shaders keep the map colour with procedural detail.

const ItemIcons := preload("res://scripts/world/item_icons.gd")
const Visuals := preload("res://scripts/world/visuals.gd")

const PX := 64  # Factorio's high-resolution tiles: 64 px each (scale 0.5 of 128 px/tile)
const COLS := 32
const ROWS := 16
const MAX_LAYERS := 96  # the shaders' per-layer table
## A surface change drops every layer once this many are in use, so a session that visits every
## planet doesn't run out (each planet needs 15-55 kinds of ground) and leave the last one bare.
const TRIM_LAYERS := 40
## Factorio's ground pictures are on average about this much brighter than the tiles' map colours
## (Nauvis water 0.9x, grass 1.4x).
const MAP_TO_GROUND := 1.2
## Sky reflected by Factorio's "wetland-water" shaders' tiles, against water's 1.
const MURKY_REFLECT := 0.25
## Rows of the slot layout, by variant size.
const ROW_4 := 0
const ROW_2 := 8
const ROW_1 := 10
## Where each variant size starts in a tile_variations_template sheet (tiles.lua).
const TEMPLATE_Y := {1: 0, 2: 128, 4: 320}
## Draw order between layer groups (Factorio's: water, water-overlay, then ground): artificial
## floors go over natural ground whatever their layer, and Gleba's lowlands (water-overlay) under
## its midlands.
const GROUP_RANK := {"water": 0, "water-overlay": 1, "zero": 2, "ground-natural": 2, "ground-artificial": 3}
## Collision masks of tiles drawn as water (lowered, with the water shader and a shore): water,
## shallow water (Gleba's wetlands, Nauvis' mud) and Aquilo's ammoniacal ocean.
const WATER_MASKS := ["tile_collision_masks.water(", "tile_collision_masks.shallow_water(", "tile_collision_masks.ammoniacal_ocean("]
## The same without an install (the mock's tiles), besides any name with "water" in it.
const WATER_NAMES := ["ammoniacal-ocean", "ammoniacal-ocean-2", "gleba-deep-lake"]


## How one tile type is drawn.
class TileGfx:
	var name := ""
	var name_hash := 0
	var layer := -1  # Texture2DArray layer, -1: no graphics, use the map colour
	## Factorio's draw order: higher tiles' edges spread over lower neighbours.
	var priority := 0
	## Natural ground spreads soft edges over lower neighbours; artificial floors stay crisp.
	var spills := false
	var water := false
	## Variant sizes, largest first: [size, probability, weights (cumulative), count].
	var sizes: Array = []
	## material_background tiles (concrete): variant size in tiles and how many there are.
	var material := Vector2i.ZERO
	var material_count := 0
	## Multiplies the picture: a copy of water with its own effect colour (the ammoniacal ocean).
	var tint := Color.WHITE
	## How much sky the water shader shows in it (1: water; murky swamps less).
	var reflect := 1.0

	## The slot (in tiles) of the variant tile (x, y) of the world shows, decided per aligned block
	## so the result is the same in every chunk rebuild and session. (lx, ly) is the tile in its
	## chunk and `uniform[size]` which of the chunk's aligned blocks are all one tile.
	func slot(x: int, y: int, lx: int, ly: int, uniform: Dictionary) -> Vector2i:
		if material_count > 0:
			var bx := floori(float(x) / material.x)
			var by := floori(float(y) / material.y)
			var v := posmod(hash(Vector3i(bx, by, 7001)), material_count)
			var per_row := COLS / material.x
			return Vector2i((v % per_row) * material.x + x - bx * material.x, (v / per_row) * material.y + y - by * material.y)
		for entry in sizes:
			var s: int = entry[0]
			var ox := floori(float(x) / s) * s
			var oy := floori(float(y) / s) * s
			if s > 1:
				var flags: PackedByteArray = uniform[s]
				if flags[(ly / s) * (32 / s) + lx / s] == 0 or _roll(ox, oy, s, 1) >= float(entry[1]):
					continue
			var v := _pick(entry[2], _roll(ox, oy, s, 2))
			var sub := Vector2i(x - ox, y - oy)
			match s:
				4:
					return Vector2i((v % 8) * 4, ROW_4 + (v / 8) * 4) + sub
				2:
					return Vector2i(v * 2, ROW_2) + sub
				_:
					return Vector2i(v, ROW_1)
		return Vector2i(0, ROW_1)

	func _roll(ox: int, oy: int, s: int, salt: int) -> float:
		return float(hash(Vector4i(ox, oy, s * 16 + salt, name_hash)) & 0xffffff) / 16777216.0

	static func _pick(cumulative: PackedFloat32Array, r: float) -> int:
		var total := cumulative[cumulative.size() - 1]
		for i in cumulative.size():
			if r * total < cumulative[i]:
				return i
		return cumulative.size() - 1

	## (first row, variant width, height, count) for the shaders, which sample this tile's
	## texture by world position where it spreads into a neighbour.
	func shader_info() -> Color:
		if material_count > 0:
			return Color(0, material.x, material.y, material_count)
		# The plain 1x1 variants: the big ones carry features (flowers, dry patches) that would
		# be cut off by the transition mask.
		for entry in sizes:
			if entry[0] == 1:
				return Color(ROW_1, 1, 1, entry[3])
		for entry in sizes:
			if entry[0] == 4:
				return Color(ROW_4, 4, 4, entry[3])
		return Color(ROW_1, 1, 1, 1)


static var _defs := {}  # tile name -> Lua block of its prototype, read once
static var _defs_read := false
static var _water := {}  # tile name -> true: its collision mask is water's (WATER_MASKS)
static var _layer_of := {}  # tile name -> its `layer`, worked out with the file's constants
static var _tint_of := {}  # tile name -> Color, for copies of a water tile with another map colour
static var _effects := {}  # tile-effect name -> its Lua block, for water shaders with a picture
static var _gfx := {}  # tile name -> TileGfx
static var _images: Array[Image] = []
static var _array: Texture2DArray
static var _infos := PackedColorArray()
static var _reflects := PackedFloat32Array()
static var _dirty := false
static var _compress := -1  # -1 unknown, 0 no, 1 yes
## --plain-terrain keeps the procedural ground even with an install (for comparisons).
static var disabled := "--plain-terrain" in OS.get_cmdline_user_args()


## Pictures being read on worker threads: tile name -> [task id, TileGfx]. A TileGfx is only
## handed out once it is final, so terrain jobs on other threads never see one change.
static var _pending := {}
static var _loaded := {}  # tile name -> Image (or null), written by the workers
static var _loaded_mutex := Mutex.new()
## Goes up whenever lookup() can answer more tiles than before.
static var generation := 0
static var _changed := false


## The graphics for a tile, or null while its picture is being read (on a worker thread: reading
## and compressing one takes 50-350 ms, which on the main thread was a hitch for every new kind
## of ground). Draw it in its map colour meanwhile and ask again after `generation` changes.
static func lookup(tile_name: String) -> TileGfx:
	var g: TileGfx = _gfx.get(tile_name)
	if g != null or _pending.has(tile_name):
		return g
	g = TileGfx.new()
	g.name = tile_name
	g.name_hash = tile_name.hash()
	g.water = is_water_tile(tile_name)
	var block := ""
	if not disabled and ItemIcons.factorio_data_dir() != "":
		_read_defs()
		block = _defs.get(tile_name, "")
	if block != "":
		var group := _str(block, "layer_group", "water" if g.water else "ground-natural")
		g.priority = int(GROUP_RANK.get(group, 2)) * 1000 + int(_layer_of.get(tile_name, 0))
		g.spills = group in ["ground-natural", "zero", "water-overlay"]
		g.tint = _tint_of.get(tile_name, Color.WHITE)
	if block == "" or _images.size() + _pending.size() >= MAX_LAYERS:
		if block != "":
			push_warning("Terrain textures: no room for %s (%d kinds of ground in use)" % [tile_name, MAX_LAYERS])
		_gfx[tile_name] = g
		_changed = true
		return g
	_pending[tile_name] = [WorkerThreadPool.add_task(_load.bind(g, block)), g]
	return null


## Whether a tile is drawn as water: by its collision mask in Factorio's definitions, else by name.
static func is_water_tile(tile_name: String) -> bool:
	if "water" in tile_name or tile_name in WATER_NAMES:
		return true
	if disabled or ItemIcons.factorio_data_dir() == "":
		return false
	_read_defs()
	return _water.has(tile_name)


## After a surface change, once the chunks drawn with them are gone: forgets every layer if many
## are in use, so the new surface's ground has room. Pictures still being read land in the new
## table. True if it dropped them.
static func trim() -> bool:
	if _images.size() < TRIM_LAYERS:
		return false
	_gfx.clear()
	_images.clear()
	_infos = PackedColorArray()
	_reflects = PackedFloat32Array()
	_changed = true
	generation += 1
	return true


## How many layers are in use (for tests).
static func layer_count() -> int:
	return _images.size()


## The graphics for a tile if lookup() has them ready, without starting anything.
static func peek(tile_name: String) -> TileGfx:
	return _gfx.get(tile_name)


static func _load(g: TileGfx, block: String) -> void:
	var t0 := Time.get_ticks_msec()
	var image := _build_layer(g, block)
	_loaded_mutex.lock()
	_loaded[g.name] = image
	_loaded_mutex.unlock()
	if image != null:
		print("Terrain: %s from Factorio's graphics (layer %d, %d ms)" % [g.name, g.priority, Time.get_ticks_msec() - t0])


## Hands out the pictures read since the last call and puts them on the GPU. Main thread, once a
## frame. True when lookup() can answer more tiles than before.
static func poll() -> bool:
	for tile_name in _pending.keys():
		var task: int = _pending[tile_name][0]
		if not WorkerThreadPool.is_task_completed(task):
			continue
		_publish(tile_name, task)
	commit()
	var changed := _changed
	_changed = false
	if changed:
		generation += 1
	return changed


## Waits for the pictures still being read (before quitting).
static func finish_all() -> void:
	for tile_name in _pending.keys():
		_publish(tile_name, _pending[tile_name][0])
	commit()


static func _publish(tile_name: String, task: int) -> void:
	WorkerThreadPool.wait_for_task_completion(task)
	var g: TileGfx = _pending[tile_name][1]
	_pending.erase(tile_name)
	_loaded_mutex.lock()
	var image: Image = _loaded.get(tile_name)
	_loaded.erase(tile_name)
	_loaded_mutex.unlock()
	if image == null:
		g.sizes = []
		g.material_count = 0
	else:
		g.layer = _images.size()
		_images.append(image)
		_infos.append(g.shader_info())
		_reflects.append(g.reflect)
		_dirty = true
	_gfx[tile_name] = g
	_changed = true


## Puts newly loaded layers on the GPU (one upload however many tiles arrived this frame).
static func commit() -> void:
	if not _dirty or _images.is_empty():
		return
	_dirty = false
	_array = Texture2DArray.new()
	var err := _array.create_from_images(_images)
	if err != OK:
		push_warning("Terrain textures: %s" % error_string(err))
		return
	# Vectors, not Colors: a Color array would be converted from sRGB on the way in.
	var infos := PackedVector4Array()
	infos.resize(MAX_LAYERS)
	for i in _infos.size():
		var c := _infos[i]
		infos[i] = Vector4(c.r, c.g, c.b, c.a)
	for m: ShaderMaterial in [Visuals.terrain_material(), Visuals.water_material()]:
		m.set_shader_parameter("tiles", _array)
		m.set_shader_parameter("tile_info", infos)
		m.set_shader_parameter("textured", true)
	var reflects := _reflects.duplicate()
	reflects.resize(MAX_LAYERS)
	Visuals.water_material().set_shader_parameter("tile_reflect", reflects)


## Whether any of Factorio's tile pictures are in use (the shore is built differently then).
static func active() -> bool:
	return _array != null


## Fraction of a layer per slot, for UVs.
static func slot_uv() -> Vector2:
	return Vector2(1.0 / COLS, 1.0 / ROWS)


# --- reading Factorio's definitions -------------------------------------------------------------

static func _read_defs() -> void:
	if _defs_read:
		return
	_defs_read = true
	var data := ItemIcons.factorio_data_dir()
	var files: Array[String] = [data.path_join("base/prototypes/tile/tiles.lua")]
	var sa := data.path_join("space-age/prototypes/tile")
	if DirAccess.dir_exists_absolute(sa):
		for f in DirAccess.get_files_at(sa):
			if f.ends_with(".lua"):
				files.append(sa.path_join(f))
	var re := RegEx.create_from_string("(?m)^\\s*name\\s*=\\s*\"([^\"]+)\"")
	# `gleba_tile_offset = 32` at the top of a file, used as `layer = gleba_tile_offset + 8`.
	var const_re := RegEx.create_from_string("(?m)^\\s*(?:local\\s+)?([A-Za-z_]\\w*)\\s*=\\s*(-?\\d+)\\s*$")
	var layer_re := RegEx.create_from_string("\\blayer\\s*=\\s*([\\w\\s+\\-]+?)\\s*(?:,|\\n)")
	# `local x = table.deepcopy(data.raw.tile["water"])`, then `x.name = "ammoniacal-ocean"`.
	var copy_re := RegEx.create_from_string("local\\s+(\\w+)\\s*=\\s*table\\.deepcopy\\(\\s*data\\.raw\\.tile\\[\"([^\"]+)\"\\]\\s*\\)")
	# A tile-effect names its shader right after its name; its block may run on into script that
	# mentions variants.
	var effect_re := RegEx.create_from_string("^\\s*name\\s*=\\s*\"[^\"]+\"\\s*,\\s*shader\\s*=")
	var copies: Array = []
	var frozen: Array[String] = []
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		var consts := {}
		for m in const_re.search_all(text):
			consts[m.get_string(1)] = int(m.get_string(2))
		var found := re.search_all(text)
		for i in found.size():
			var end := found[i + 1].get_start() if i + 1 < found.size() else text.length()
			var block := text.substr(found[i].get_start(), end - found[i].get_start())
			var tile_name := found[i].get_string(1)
			if effect_re.search(block) != null:
				if not _effects.has(tile_name) and "image_textures" in block:
					_effects[tile_name] = block
			elif not _defs.has(tile_name) and "variants" in block:
				_defs[tile_name] = block
				var lm := layer_re.search(block)
				if lm != null:
					_layer_of[tile_name] = _sum(lm.get_string(1), consts)
				for mask in WATER_MASKS:
					if mask in block:
						_water[tile_name] = true
		for m in copy_re.search_all(text):
			var v := m.get_string(1)
			var nm := RegEx.create_from_string("\\b%s\\.name\\s*=\\s*\"([^\"]+)\"" % v).search(text)
			if nm != null:
				var ec := RegEx.create_from_string("\\b%s\\.map_color\\s*=\\s*\\{([^}]*)\\}" % v).search(text)
				copies.append([nm.get_string(1), m.get_string(2), ec.get_string(1) if ec != null else ""])
		# Aquilo's floors are made by `frozen_concrete("concrete", ...)`: the floor one layer up,
		# with its frozen picture (8 material variants).
		for m in RegEx.create_from_string("(?m)^frozen_concrete\\(\\s*\"([^\"]+)\"").search_all(text):
			var floor_name := m.get_string(1)
			frozen.append(floor_name)
	for floor_name: String in frozen:
		var base: String = _defs.get(floor_name, "")
		var frozen_name := "frozen-" + floor_name
		if base == "" or _defs.has(frozen_name):
			continue
		_defs[frozen_name] = 'name = "%s", layer_group = "%s", variants = material_background("__space-age__/graphics/terrain/aquilo/%s.png", 8)' % [
			frozen_name, _str(base, "layer_group", "ground-artificial"), frozen_name]
		_layer_of[frozen_name] = int(_layer_of.get(floor_name, 0)) + 1
	# A copy draws with its original's pictures. Factorio's water shader colours it by its own
	# effect colour; the map colour says how that looks, so the picture is shifted by the ratio of
	# the two map colours (the ammoniacal ocean is a dark indigo copy of water).
	for c in copies:
		var src: String = c[1]
		if _defs.has(c[0]) or not _defs.has(src):
			continue
		_defs[c[0]] = _defs[src]
		_layer_of[c[0]] = _layer_of.get(src, 0)
		if _water.has(src):
			_water[c[0]] = true
		var own := _rgb(c[2])
		var theirs := RegEx.create_from_string("\\bmap_color\\s*=\\s*\\{([^}]*)\\}").search(_defs[src])
		var base := _rgb(theirs.get_string(1)) if theirs != null else Color.BLACK
		if own != Color.BLACK and base.r > 0.0 and base.g > 0.0 and base.b > 0.0:
			_tint_of[c[0]] = Color(minf(own.r / base.r, 4.0), minf(own.g / base.g, 4.0), minf(own.b / base.b, 4.0))


## `32 + 8`, `gleba_tile_offset+8`: names from the file's constants.
static func _sum(expr: String, consts: Dictionary) -> int:
	var total := 0
	var sign := 1
	for part in expr.replace("+", " + ").replace("-", " - ").split(" ", false):
		if part == "+":
			sign = 1
		elif part == "-":
			sign = -1
		else:
			total += sign * (int(part) if part.is_valid_int() else int(consts.get(part, 0)))
			sign = 1
	return total


## The inside of `key = { ... }` in a block, "" if it has none.
static func _str_table(block: String, key: String) -> String:
	var m := RegEx.create_from_string("\\b%s\\s*=\\s*\\{([^}]*)\\}" % key).search(block)
	return m.get_string(1) if m != null else ""


## "{21, 147, 167}" or "{r = 46, g = 45, b = 51}" as a Color (0-255 or 0-1, as Factorio reads
## them), black if it isn't one.
static func _rgb(body: String) -> Color:
	var n: Array[float] = []
	for part in body.split(","):
		var v := part.get_slice("=", part.get_slice_count("=") - 1).strip_edges()
		if v.is_valid_float():
			n.append(float(v))
	if n.size() < 3:
		return Color.BLACK
	var k := 255.0 if n[0] > 1.0 or n[1] > 1.0 or n[2] > 1.0 else 1.0
	return Color(n[0] / k, n[1] / k, n[2] / k)


static func _num(block: String, key: String, default: float) -> float:
	var m := RegEx.create_from_string("\\b%s\\s*=\\s*(-?[\\d.]+)" % key).search(block)
	return float(m.get_string(1)) if m != null else default


static func _str(block: String, key: String, default: String) -> String:
	var m := RegEx.create_from_string("\\b%s\\s*=\\s*\"([^\"]+)\"" % key).search(block)
	return m.get_string(1) if m != null else default


static func _path(lua_path: String) -> String:
	var m := RegEx.create_from_string("^__(.+?)__/(.*)$").search(lua_path)
	if m == null:
		return ""
	return ItemIcons.factorio_data_dir().path_join(m.get_string(1)).path_join(m.get_string(2))


static func _sheet(lua_path: String, tint := Color.WHITE) -> Image:
	var path := _path(lua_path)
	if path == "" or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	if tint != Color.WHITE:
		# Only copies of water have a tint, and water's sheets are small (512 x 64 to 512 x 256).
		var data := image.get_data()
		var k := [tint.r, tint.g, tint.b]
		for i in data.size():
			if i % 4 != 3:
				data[i] = mini(255, int(data[i] * k[i % 4]))
		image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
	return image


## Whether a sheet is laid out as a tile_variations_template (1x1, 2x2 and 4x4 rows).
static func _is_template_sheet(sheet: Image) -> bool:
	return sheet.get_height() == TEMPLATE_Y[4] + 4 * PX and sheet.get_width() >= 16 * PX


## One layer in the slot layout from the tile's definition, or null if it can't be read.
static func _build_layer(g: TileGfx, block: String) -> Image:
	var layer := Image.create_empty(COLS * PX, ROWS * PX, false, Image.FORMAT_RGBA8)
	var any := false
	var mat := RegEx.create_from_string("material_background\\s*(?:\\(\\s*\"([^\"]+)\"\\s*,\\s*(\\d+)|=\\s*\\{[^}]*?picture\\s*=\\s*\"([^\"]+)\"[^}]*?count\\s*=\\s*(\\d+))").search(block)
	var template := RegEx.create_from_string("\\w*template\\w*\\(\\s*\"([^\"]+)\"").search(block)
	var main := RegEx.create_from_string("main\\s*=\\s*\\{").search(block)
	var effect := _effect_picture(block)
	if effect != null:
		# Gleba's wetlands and Aquilo's brash ice: Factorio draws them with its water shader from
		# one seamless picture (2048 x 1024: 32 x 16 tiles, the whole layer).
		var w := mini(effect.get_width() / PX, COLS)
		var h := mini(effect.get_height() / PX, ROWS)
		if w > 0 and h > 0:
			# Several tiles share a picture and the shader sets each one's shade (light and dark
			# dead skin, the deep lake): their map colours say how light, so the picture is
			# scaled to that (Factorio's ground draws about MAP_TO_GROUND times its map colour).
			var target := _luma(_rgb(_str_table(block, "map_color"))) * MAP_TO_GROUND
			var own := _mean_luma(effect)
			if target > 0.0 and own > 0.0:
				effect.adjust_bcs(clampf(target / own, 0.3, 1.5), 1.0, 1.0)
			layer.blit_rect(effect, Rect2i(0, 0, w * PX, h * PX), Vector2i.ZERO)
			g.material = Vector2i(w, h)
			g.material_count = 1
			g.reflect = MURKY_REFLECT
			# No _fill_empty_slots: the picture fills the layer, and its alpha (a mask for
			# Factorio's shader, often under a half) would pass for empty slots.
			return _finish_layer(layer)
	if mat != null:
		var sheet := _sheet(mat.get_string(1) if mat.get_string(1) != "" else mat.get_string(3))
		var count := int(mat.get_string(2) if mat.get_string(2) != "" else mat.get_string(4))
		if sheet == null or count <= 0:
			return null
		var w := sheet.get_width() / count / PX
		var h := sheet.get_height() / PX
		if w <= 0 or h <= 0 or w > COLS or h > ROWS:
			return null
		var per_row := COLS / w
		count = mini(count, per_row * (ROWS / h))
		for v in count:
			layer.blit_rect(sheet, Rect2i(v * w * PX, 0, w * PX, h * PX), Vector2i((v % per_row) * w, (v / per_row) * h) * PX)
		g.material = Vector2i(w, h)
		g.material_count = count
		any = true
	var template_sheet: Image = null
	if mat == null and template != null:
		template_sheet = _sheet(template.get_string(1), g.tint)
		if template_sheet == null:
			return null
	elif mat == null and main != null:
		# Gleba's wetlands name one 1x1 picture of a whole template sheet (Factorio draws them
		# through the water shader's own texture): read all of its variants, or every tile of
		# the swamp shows the same square.
		var only := RegEx.create_from_string("\\{\\s*picture\\s*=\\s*\"([^\"]+)\"([^{}]*)\\}").search_all(block.substr(main.get_start()))
		if only.size() == 1 and int(_num(only[0].get_string(2), "count", 1)) == 1:
			var sheet := _sheet(only[0].get_string(1), g.tint)
			if sheet != null and _is_template_sheet(sheet):
				template_sheet = sheet
	if template_sheet != null:
		var sheet := template_sheet
		var max_size := int(_num(block, "max_size", 4))
		for s in [4, 2, 1]:
			if s > max_size:
				continue
			var opts := _size_options(block, s)
			var weights: PackedFloat32Array = opts[1]
			var count := weights.size() if not weights.is_empty() else 16
			var y: int = TEMPLATE_Y[s]
			count = mini(count, mini(16, sheet.get_width() / (s * PX)))
			if y + s * PX > sheet.get_height() or count <= 0:
				continue
			for v in count:
				layer.blit_rect(sheet, Rect2i(v * s * PX, y, s * PX, s * PX), _slot_px(s, v))
			g.sizes.append([s, opts[0], _cumulative(weights, count), count])
			any = true
	elif mat == null and main != null:
		var entries := RegEx.create_from_string("\\{\\s*picture\\s*=\\s*\"([^\"]+)\"([^{}]*)\\}").search_all(block.substr(main.get_start()))
		var by_size := {}
		for e in entries:
			var s := int(_num(e.get_string(2), "size", 1))
			if s in [1, 2, 4] and not by_size.has(s):
				by_size[s] = e
		for s in [4, 2, 1]:
			if not by_size.has(s):
				continue
			var e: RegExMatch = by_size[s]
			var sheet := _sheet(e.get_string(1), g.tint)
			if sheet == null:
				continue
			var props := e.get_string(2)
			var count := mini(16, int(_num(props, "count", 1)))
			var x0 := int(_num(props, "x", 0))
			var y0 := int(_num(props, "y", 0))
			var line := int(_num(props, "line_length", count))
			var placed := 0
			for v in count:
				var src := Vector2i(x0 + (v % maxi(line, 1)) * s * PX, y0 + (v / maxi(line, 1)) * s * PX)
				if src.x + s * PX > sheet.get_width() or src.y + s * PX > sheet.get_height():
					break
				layer.blit_rect(sheet, Rect2i(src, Vector2i(s, s) * PX), _slot_px(s, v))
				placed += 1
			if placed > 0:
				g.sizes.append([s, _num(props, "probability", 1.0), _cumulative(PackedFloat32Array(), placed), placed])
				any = true
	if not any:
		return null
	_fill_empty_slots(layer)
	return _finish_layer(layer)


## The picture of the tile's effect, when that is a "wetland-water" water shader with one.
static func _effect_picture(block: String) -> Image:
	var effect_name := _str(block, "effect", "")
	var effect: String = _effects.get(effect_name, "")
	if effect == "" or not "wetland-water" in effect:
		return null
	var m := RegEx.create_from_string("image_textures\\s*=\\s*\\{\\s*\\{\\s*filename\\s*=\\s*\"([^\"]+)\"").search(effect)
	return _sheet(m.get_string(1)) if m != null else null


static func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b


## Average brightness of a picture, from a 64 x 64 grid of its pixels.
static func _mean_luma(image: Image) -> float:
	var total := 0.0
	for j in 64:
		for i in 64:
			total += _luma(image.get_pixel(i * image.get_width() / 64, j * image.get_height() / 64))
	return total / 4096.0


static func _finish_layer(layer: Image) -> Image:
	layer.convert(Image.FORMAT_RGB8)
	layer.generate_mipmaps()
	if _compress != 0:
		var err := layer.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_SRGB)
		_compress = 1 if err == OK else 0
	return layer


## Unused slots get copies of used ones, so filtering and mipmaps at the edges of the variants
## pull in more of the same ground rather than black.
static func _fill_empty_slots(layer: Image) -> void:
	var filled := PackedByteArray()
	filled.resize(COLS * ROWS)
	var first := -1
	for i in COLS * ROWS:
		if layer.get_pixel((i % COLS) * PX + PX / 2, (i / COLS) * PX + PX / 2).a > 0.5:
			filled[i] = 1
			if first < 0:
				first = i
	for row in ROWS:
		for col in COLS:
			var i := row * COLS + col
			if filled[i] == 1:
				continue
			var src := -1
			for k in range(1, COLS):
				if filled[row * COLS + posmod(col - k, COLS)] == 1:
					src = row * COLS + posmod(col - k, COLS)
					break
			if src < 0:
				src = i - COLS if row > 0 else first
			layer.blit_rect(layer, Rect2i((src % COLS) * PX, (src / COLS) * PX, PX, PX), Vector2i(col, row) * PX)
			filled[i] = 1


static func _slot_px(s: int, v: int) -> Vector2i:
	match s:
		4:
			return Vector2i((v % 8) * 4, ROW_4 + (v / 8) * 4) * PX
		2:
			return Vector2i(v * 2, ROW_2) * PX
	return Vector2i(v, ROW_1) * PX


## [probability, weights] of one size in a tile_variations_template's options: `[2] = {
## probability = 0.91, weights = {...} }`. Size 1 always fits; bigger sizes default to never.
static func _size_options(block: String, s: int) -> Array:
	var m := RegEx.create_from_string("\\[%d\\]\\s*=\\s*\\{([^{}]*(?:\\{[^{}]*\\})?[^{}]*)\\}" % s).search(block)
	if m == null:
		return [1.0 if s == 1 else 0.0, PackedFloat32Array()]
	var body := m.get_string(1)
	var weights := PackedFloat32Array()
	var w := RegEx.create_from_string("weights\\s*=\\s*\\{([^}]*)\\}").search(body)
	if w != null:
		for part in w.get_string(1).split(","):
			if part.strip_edges() != "":
				weights.append(float(part.strip_edges()))
	return [_num(body, "probability", 1.0), weights]


static func _cumulative(weights: PackedFloat32Array, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var total := 0.0
	for i in count:
		total += weights[i] if i < weights.size() else 1.0
		out.append(total)
	return out
