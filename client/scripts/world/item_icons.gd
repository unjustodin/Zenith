extends RefCounted
## Item, fluid, signal and recipe icons, read at runtime from the player's own Factorio install
## (Wube's graphics are never copied into this repo). Which file is whose icon comes from the
## prototypes' `icon` / `icons` (res://data/icons.json, written by tools/icon_index.py): files
## aren't named after their items (the stone wall's is wall.png) and some icons are tinted layers
## (barrels), composed here as Factorio does. Names the index doesn't know (a mod's) fall back to
##
##   <data>/<base|space-age|quality|elevated-rails>/graphics/icons/<item>.png
##
## <data> is Factorio's `data` folder: --factorio-data=<dir>, or found in the usual Steam and
## standalone install places. Items without an icon get a colour instead.

const MODS := ["base", "space-age", "quality", "elevated-rails"]
const INDEX := "res://data/icons.json"
## Composed icons are drawn this many pixels across (technologies: Factorio's 256 px tech icons).
const COMPOSED := 64
const COMPOSED_TECH := 256

## Common items, so they are recognisable even without icons.
const COLORS := {
	"iron-plate": Color(0.62, 0.66, 0.72), "copper-plate": Color(0.86, 0.47, 0.27),
	"steel-plate": Color(0.78, 0.8, 0.83), "iron-ore": Color(0.42, 0.5, 0.6),
	"copper-ore": Color(0.76, 0.4, 0.24), "coal": Color(0.12, 0.12, 0.12),
	"stone": Color(0.66, 0.58, 0.45), "stone-brick": Color(0.72, 0.62, 0.5),
	"wood": Color(0.55, 0.38, 0.2), "iron-gear-wheel": Color(0.48, 0.5, 0.54),
	"copper-cable": Color(0.92, 0.58, 0.3), "electronic-circuit": Color(0.25, 0.66, 0.3),
	"advanced-circuit": Color(0.78, 0.26, 0.24), "processing-unit": Color(0.26, 0.36, 0.82),
	"plastic-bar": Color(0.92, 0.92, 0.92), "sulfur": Color(0.92, 0.86, 0.22),
	"uranium-ore": Color(0.42, 0.82, 0.2), "automation-science-pack": Color(0.86, 0.2, 0.2),
	"logistic-science-pack": Color(0.3, 0.8, 0.3),
}

static var data_dir := ""
static var _searched := false
static var _textures := {}  # name -> Texture2D, or null when there is no icon
static var _kinds := {}  # "kind:name" -> Texture2D or null, for fluids, signals and recipes
static var _index := {}  # kind -> name -> layers (icons.json)


static func configure_from_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--factorio-data="):
			data_dir = arg.get_slice("=", 1)


static func color_for(item: String) -> Color:
	if COLORS.has(item):
		return COLORS[item]
	return Color.from_hsv(posmod(hash(item), 1000) / 1000.0, 0.45, 0.85)


static func texture_for(item: String) -> Texture2D:
	if _textures.has(item):
		return _textures[item]
	factorio_data_dir()
	var texture := load_uncached(item)
	_textures[item] = texture
	return texture


## Whether texture_for(item) would answer at once.
static func is_cached(item: String) -> bool:
	return _textures.has(item)


## An icon loaded from its files, past the cache: safe on a worker thread once
## prepare_for_threads() has run on the main thread (a tinted icon is composed pixel by pixel,
## which takes up to tens of milliseconds). store() then puts it in the cache.
static func load_uncached(item: String) -> Texture2D:
	var texture: Texture2D = null
	var layers = index().get("item", {}).get(item)
	if data_dir != "" and layers is Array:
		texture = _compose(layers)
	if texture == null and data_dir != "":
		for mod in MODS:
			var path := data_dir.path_join(mod).path_join("graphics/icons/%s.png" % item)
			if FileAccess.file_exists(path):
				texture = _load_icon(path)
				break
	return texture


## Finds the install and reads the index, so load_uncached() on a worker only reads them.
static func prepare_for_threads() -> void:
	factorio_data_dir()
	index()


## Puts an icon load_uncached() made in the cache, unless one got there first.
static func store(item: String, texture: Texture2D) -> Texture2D:
	if not _textures.has(item):
		_textures[item] = texture
	return _textures[item]


## Factorio's data folder, found on first use; "" when there is no Factorio install. Also used
## for the sprites projected onto models (sprite_projection.gd).
static func factorio_data_dir() -> String:
	if not _searched:
		_searched = true
		if data_dir == "":
			data_dir = _find_data_dir()
		print("Factorio data: %s" % (data_dir if data_dir != "" else "not found, using colours and plain materials (--factorio-data=<dir>)"))
	return data_dir


## A fluid's, virtual signal's, recipe's or technology's icon from the prototypes ("fluid",
## "virtual-signal", "recipe", "technology"), or null when the index has none (a recipe named after
## its product uses the item's).
static func texture_for_kind(kind: String, name: String) -> Texture2D:
	var key := kind + ":" + name
	if _kinds.has(key):
		return _kinds[key]
	var texture: Texture2D = null
	var layers = index().get(kind, {}).get(name)
	if factorio_data_dir() != "" and layers is Array:
		texture = _compose(layers, COMPOSED_TECH if kind == "technology" else COMPOSED)
	_kinds[key] = texture
	return texture


## The prototypes' icons (tools/icon_index.py): {kind: {name: [[file, icon_size, tint, scale,
## shift], ...]}}; {"": {}} if the file is missing.
static func index() -> Dictionary:
	if _index.is_empty():
		_index = {"": {}}
		if FileAccess.file_exists(INDEX):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
			if parsed is Dictionary:
				_index = parsed
	return _index


## An icon from its layers, as Factorio draws IconData: each layer `icon_size * scale` across
## (scale defaults to (size / 2) / icon_size, so a lone 64 px item icon is 32 units and a 256 px
## technology icon 128), centred, moved by `shift` in the same units, multiplied by `tint` with
## premultiplied alpha (a tint's alpha below one lets the layers under it show through, as on
## barrels). The first layer sets the icon's size, `size` pixels across.
static func _compose(layers: Array, size := COMPOSED) -> Texture2D:
	if layers.is_empty():
		return null
	var first: Array = layers[0]
	if layers.size() == 1 and first[2] == null and first[3] == null and first[4] == null:
		return _load_icon(data_dir.path_join(str(first[0])), int(first[1]))
	var ppu := size / (float(first[1]) * _scale_of(first, size))
	if layers.all(func(l: Array) -> bool: return l[2] == null):
		return _compose_plain(layers, size, ppu)
	var acc := PackedFloat32Array()
	acc.resize(size * size * 4)
	for layer: Array in layers:
		var image := _layer_image(data_dir.path_join(str(layer[0])), int(layer[1]))
		if image == null:
			return null
		var px := maxi(1, roundi(float(layer[1]) * _scale_of(layer, size) * ppu))
		if image.get_width() != px:
			image.resize(px, px, Image.INTERPOLATE_LANCZOS if px < image.get_width() else Image.INTERPOLATE_BILINEAR)
		var tint := Color(1, 1, 1, 1)
		if layer[2] is Array:
			var t: Array = layer[2]
			tint = Color(float(t[0]), float(t[1]), float(t[2]), float(t[3]))
		var shift := Vector2.ZERO
		if layer[4] is Array:
			shift = Vector2(float(layer[4][0]), float(layer[4][1]))
		var x0 := roundi(size * 0.5 + shift.x * ppu - px * 0.5)
		var y0 := roundi(size * 0.5 + shift.y * ppu - px * 0.5)
		for y in px:
			var cy := y0 + y
			if cy < 0 or cy >= size:
				continue
			for x in px:
				var cx := x0 + x
				if cx < 0 or cx >= size:
					continue
				var c := image.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				var i := (cy * size + cx) * 4
				var keep := 1.0 - c.a * tint.a
				acc[i] = c.r * c.a * tint.r + acc[i] * keep
				acc[i + 1] = c.g * c.a * tint.g + acc[i + 1] * keep
				acc[i + 2] = c.b * c.a * tint.b + acc[i + 2] * keep
				acc[i + 3] = c.a * tint.a + acc[i + 3] * keep
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var i := (y * size + x) * 4
			var a := clampf(acc[i + 3], 0.0, 1.0)
			if a > 0.0:
				out.set_pixel(x, y, Color(minf(acc[i] / a, 1.0), minf(acc[i + 1] / a, 1.0), minf(acc[i + 2] / a, 1.0), a))
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


## Layers without tints (technologies' bonus badges): blended whole, much faster than per pixel.
static func _compose_plain(layers: Array, size: int, ppu: float) -> Texture2D:
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for layer: Array in layers:
		var image := _layer_image(data_dir.path_join(str(layer[0])), int(layer[1]))
		if image == null:
			return null
		var px := maxi(1, roundi(float(layer[1]) * _scale_of(layer, size) * ppu))
		if image.get_width() != px:
			image.resize(px, px, Image.INTERPOLATE_LANCZOS if px < image.get_width() else Image.INTERPOLATE_BILINEAR)
		var shift := Vector2.ZERO
		if layer[4] is Array:
			shift = Vector2(float(layer[4][0]), float(layer[4][1]))
		var at := Vector2i(roundi(size * 0.5 + shift.x * ppu - px * 0.5), roundi(size * 0.5 + shift.y * ppu - px * 0.5))
		out.blend_rect(image, Rect2i(0, 0, px, px), at)
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)


static func _scale_of(layer: Array, size := COMPOSED) -> float:
	return float(layer[3]) if layer[3] != null else size * 0.5 / float(layer[1])


## The full-size picture of an icon file (its left `size` square), or null.
static func _layer_image(path: String, size: int) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	image.convert(Image.FORMAT_RGBA8)
	var side := mini(size, image.get_height())
	if image.get_width() != side or image.get_height() != side:
		image = image.get_region(Rect2i(0, 0, side, side))
	return image


## Icons hold their own smaller mipmaps to the right of the full-size one (a 64x64 icon is a
## 120x64 image); only the square on the left (`size` across when known) is kept.
static func _load_icon(path: String, size := 0) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	var side := image.get_height() if size <= 0 else mini(size, image.get_height())
	if image.get_width() != side or image.get_height() != side:
		image = image.get_region(Rect2i(0, 0, side, side))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _find_data_dir() -> String:
	var home := OS.get_environment("HOME")
	var libraries: Array[String] = []
	if OS.get_name() == "Windows":
		var steam := "C:/Program Files (x86)/Steam"
		libraries.append(steam)
		libraries.append_array(_steam_libraries(steam.path_join("steamapps/libraryfolders.vdf")))
	else:
		for steam: String in [home.path_join(".steam/steam"), home.path_join(".local/share/Steam"), home.path_join("Library/Application Support/Steam")]:
			libraries.append(steam)
			libraries.append_array(_steam_libraries(steam.path_join("steamapps/libraryfolders.vdf")))
	var candidates: Array[String] = []
	for lib in libraries:
		candidates.append(lib.path_join("steamapps/common/Factorio/data"))
		candidates.append(lib.path_join("steamapps/common/Factorio/factorio.app/Contents/data"))
	candidates.append("C:/Program Files/Factorio/data")
	candidates.append(home.path_join("factorio/data"))
	for dir in candidates:
		if DirAccess.dir_exists_absolute(dir.path_join("base/graphics/icons")):
			return dir
	return ""


## Steam libraries on other drives, from Steam's libraryfolders.vdf ("path"  "D:\\SteamLibrary").
static func _steam_libraries(vdf: String) -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(vdf):
		return out
	var re := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
	for m in re.search_all(FileAccess.get_file_as_string(vdf)):
		out.append(m.get_string(1).replace("\\\\", "/"))
	return out


## Same as factorio_data_dir() (the name the UI kit uses).
static func find_data_dir() -> String:
	return factorio_data_dir()
