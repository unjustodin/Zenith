extends RefCounted
## Factorio's own GUI graphics and fonts, read at runtime from the player's install like the item
## icons (nothing from the game is copied into this repo):
##
##   <data>/core/graphics/gui-new.png       the GUI sprite atlas, laid out by core/prototypes/style.lua
##   <data>/core/fonts/TitilliumWeb-*.ttf   the "default", "default-semibold" and "default-bold" fonts
##   <data>/core/graphics/icons/close.png   the close button's cross
##   <data>/<mod>/graphics/item-group/*.png the crafting tabs' group icons
##   <data>/core/graphics/status.png        the green/red/yellow status dots of machine screens
##   <data>/core/graphics/icons/mip/*.png   the hand in a slot, empty gun/ammo/armour slot icons
##   <data>/<mod>/graphics/technology/*.png technology icons, found through prototypes/technology.lua
##
## Without an install everything here returns null and kit.gd falls back to plain Godot styling.

const ItemIcons := preload("res://scripts/world/item_icons.gd")

const FONT_FILES := {
	"regular": "TitilliumWeb-Regular.ttf",
	"semibold": "TitilliumWeb-SemiBold.ttf",
	"bold": "TitilliumWeb-Bold.ttf",
}
const GROUP_MODS := ["base", "space-age", "quality", "elevated-rails"]
## Item groups whose icon file has another name.
const GROUP_ICON_FILES := {"combat": "military"}

static var _loaded := false
static var _atlas: Image = null
static var _fonts := {}  # weight -> FontFile
static var _sprites := {}  # relative path -> Texture2D or null
static var _tech_icon_paths := {}  # technology -> "<mod>/graphics/technology/x.png", from technology.lua
static var _tech_paths_loaded := false
static var _others := {}  # name -> other_icon's texture or null
## status.png's dots, left to right (utility-sprites.lua: status_working, _not_working, _yellow,
## _blue, _inactive).
const STATUS_DOTS := ["green", "red", "yellow", "blue", "grey"]


## The GUI atlas (2x resolution: Factorio draws it at half size at 100% UI scale), or null.
static func atlas() -> Image:
	_load()
	return _atlas


static func available() -> bool:
	return atlas() != null


## "regular", "semibold" or "bold"; null without an install.
static func font(weight: String) -> Font:
	_load()
	return _fonts.get(weight)


## A sprite from core/graphics, e.g. "icons/close.png". Icons with mipmaps beside them are cropped
## to the square on the left.
static func core_sprite(path: String) -> Texture2D:
	var dir := ItemIcons.find_data_dir()
	if dir == "":
		return null
	return _sprite(dir.path_join("core/graphics").path_join(path))


## A sprite from any of the game's data folders, e.g. "base/graphics/icons/shortcut-toolbar/mip/copy-x56.png".
static func data_sprite(path: String) -> Texture2D:
	var dir := ItemIcons.find_data_dir()
	if dir == "":
		return null
	return _sprite(dir.path_join(path))


## A shortcut bar icon (shortcuts.lua), e.g. "copy", "new-blueprint", "alt-mode", or null.
static func shortcut_icon(name: String) -> Texture2D:
	return data_sprite("base/graphics/icons/shortcut-toolbar/mip/%s-x56.png" % name)


## Icons that aren't items: fluids ("water", and recipes named after their fluid like
## "basic-oil-processing") and virtual signals ("signal-A" is signal/signal_A.png), or null.
static func other_icon(name: String) -> Texture2D:
	if _others.has(name):
		return _others[name]
	_others[name] = null
	var dir := ItemIcons.find_data_dir()
	if dir == "":
		return null
	# The prototypes' own icons first (tools/icon_index.py), then files named after them.
	for kind in ["fluid", "virtual-signal", "recipe"]:
		var known := ItemIcons.texture_for_kind(kind, name)
		if known != null:
			_others[name] = known
			return known
	var files :=["graphics/icons/fluid/%s.png" % name, "graphics/icons/signal/%s.png" % name]
	if name.begins_with("signal-"):
		files.push_front("graphics/icons/signal/signal_%s.png" % name.substr(7))
	for mod in GROUP_MODS:
		for f in files:
			var path := dir.path_join(mod).path_join(f)
			if FileAccess.file_exists(path):
				_others[name] = _sprite(path)
				return _others[name]
	return null


## The icon of an item group (crafting tab), e.g. "logistics", or null.
static func group_icon(group: String) -> Texture2D:
	var dir := ItemIcons.find_data_dir()
	if dir == "":
		return null
	var file: String = GROUP_ICON_FILES.get(group, group)
	for mod in GROUP_MODS:
		var path := dir.path_join(mod).path_join("graphics/item-group/%s.png" % file)
		if FileAccess.file_exists(path):
			return _sprite(path)
	return null


## One of status.png's 32x32 dots: "green", "red", "yellow", "blue" or "grey"; null without an
## install.
static func status_dot(color: String) -> Texture2D:
	var dir := ItemIcons.find_data_dir()
	var i := STATUS_DOTS.find(color)
	if dir == "" or i < 0:
		return null
	var key := "status:" + color
	if _sprites.has(key):
		return _sprites[key]
	var texture: Texture2D = null
	var path := dir.path_join("core/graphics/status.png")
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and image.get_width() >= (i + 1) * 32:
			image.convert(Image.FORMAT_RGBA8)
			image = image.get_region(Rect2i(i * 32, 0, 32, 32))
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	_sprites[key] = texture
	return texture


## A region of a picture in core/graphics, e.g. one row of side-menu-buttons.png, or null.
static func core_region(path: String, region: Rect2i) -> Texture2D:
	var dir := ItemIcons.find_data_dir()
	var key := "%s:%s" % [path, region]
	if dir == "":
		return null
	if _sprites.has(key):
		return _sprites[key]
	var texture: Texture2D = null
	var file := dir.path_join("core/graphics").path_join(path)
	if FileAccess.file_exists(file):
		var image := Image.load_from_file(file)
		if image != null and Rect2i(Vector2i.ZERO, image.get_size()).encloses(region):
			image.convert(Image.FORMAT_RGBA8)
			image = image.get_region(region)
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	_sprites[key] = texture
	return texture


## One of the side menu's 64 px icons (utility-sprites.lua side_menu_*_icon, by row).
static func side_menu_icon(row: int) -> Texture2D:
	return core_region("side-menu-buttons.png", Rect2i(0, row * 64, 64, 64))


## A technology's icon (a 256 px picture), or null. icons.json has every one of the game's; for
## others technology.lua names most of them, and levelled technologies ("logistics-2") without
## their own entry use their base's.
static func tech_icon(tech: String) -> Texture2D:
	var dir := ItemIcons.find_data_dir()
	if dir == "":
		return null
	# The prototypes' own icons (icons.json), with the bonus badges; the guesses below are for
	# technologies the index doesn't know (a mod's).
	var indexed := ItemIcons.texture_for_kind("technology", tech)
	if indexed != null:
		return indexed
	_load_tech_paths(dir)
	var names := [tech]
	var base := tech
	var dash := tech.rfind("-")
	if dash > 0 and tech.substr(dash + 1).is_valid_int():
		base = tech.substr(0, dash)
		names.append(base)
	for n in names:
		if _tech_icon_paths.has(n):
			return _sprite(dir.path_join(_tech_icon_paths[n]))
	for n in [tech, base, base + "-1"]:
		for mod in GROUP_MODS:
			var path := dir.path_join(mod).path_join("graphics/technology/%s.png" % n)
			if FileAccess.file_exists(path):
				return _sprite(path)
	return null


## name -> icon from each mod's prototypes/technology.lua: the first `icon = "__mod__/..."` after a
## `name = "..."` (good enough for Wube's files, which list one technology per table).
static func _load_tech_paths(dir: String) -> void:
	if _tech_paths_loaded:
		return
	_tech_paths_loaded = true
	var re := RegEx.create_from_string("name\\s*=\\s*\"([^\"]+)\"|icon\\s*=\\s*\"__([a-z-]+)__/([^\"]+)\"")
	for mod in GROUP_MODS:
		var path := dir.path_join(mod).path_join("prototypes/technology.lua")
		if not FileAccess.file_exists(path):
			continue
		var name := ""
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			if m.get_string(1) != "":
				name = m.get_string(1)
			elif name != "" and not _tech_icon_paths.has(name):
				_tech_icon_paths[name] = m.get_string(2).path_join(m.get_string(3))
				name = ""


static func _sprite(path: String) -> Texture2D:
	if _sprites.has(path):
		return _sprites[path]
	var texture: Texture2D = null
	if FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
			var h := image.get_height()
			if image.get_width() > h:
				image = image.get_region(Rect2i(0, 0, h, h))
			# The see-through pixels' colour is black in Factorio's files: averaged into the smaller
			# mipmaps it gave every icon a dark, smeared rim when drawn small. (Icons only: the
			# big sheets aren't drawn shrunk.)
			if h <= 256:
				image.fix_alpha_edges()
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	_sprites[path] = texture
	return texture


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := ItemIcons.find_data_dir()
	if dir == "":
		return
	var atlas_path := dir.path_join("core/graphics/gui-new.png")
	if FileAccess.file_exists(atlas_path):
		var image := Image.load_from_file(atlas_path)
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
			_atlas = image
	for weight in FONT_FILES:
		var path := dir.path_join("core/fonts").path_join(FONT_FILES[weight])
		if FileAccess.file_exists(path):
			var f := FontFile.new()
			if f.load_dynamic_font(path) == OK:
				f.hinting = TextServer.HINTING_LIGHT
				_fonts[weight] = f
	print("factorio gui: %s" % ("atlas and fonts from " + dir if _atlas != null else "gui-new.png not found, plain styling"))
