extends RefCounted
## The saves the world selection lists: the server's (server/saves/*.zip) and Factorio's own
## (%APPDATA%\Factorio\saves, loaded as a copy so the original is never touched). Factorio's
## saves carry a preview.jpg inside the zip; the headless server's don't.

const Paths := preload("res://scripts/menu/paths.gd")


## Each save as {"path", "name", "modified" (unix time), "size", "source": "server" or "factorio"},
## newest first.
static func list() -> Array:
	var out: Array = []
	_scan(Paths.saves_dir(), "server", out)
	var own := Paths.factorio_saves_dir()
	if own != "":
		_scan(own, "factorio", out)
	var newer := func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["modified"]) > int(b["modified"])
	out.sort_custom(newer)
	return out


static func _scan(dir: String, source: String, out: Array) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		if not file.to_lower().ends_with(".zip"):
			continue
		var path := dir.path_join(file)
		out.append({
			"path": path, "name": file.get_basename(), "source": source,
			"modified": FileAccess.get_modified_time(path),
			"size": _size(path),
		})


static func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


## "Today 14:05", "Yesterday 09:12" or "2026-10-21 18:40", in local time.
static func when(unix: int) -> String:
	var offset := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := unix + offset
	var now := int(Time.get_unix_time_from_system()) + offset
	var day := local / 86400
	var today := now / 86400
	var clock := Time.get_time_string_from_unix_time(local).substr(0, 5)
	if day == today:
		return "Today " + clock
	if day == today - 1:
		return "Yesterday " + clock
	return Time.get_date_string_from_unix_time(local) + " " + clock


## The save's preview picture (Factorio's preview.jpg), or null.
static func preview(path: String) -> Texture2D:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return null
	var texture: Texture2D = null
	for file in zip.get_files():
		if file.get_file() == "preview.jpg" and file.count("/") <= 1:
			var image := Image.new()
			if image.load_jpg_from_buffer(zip.read_file(file)) == OK:
				texture = ImageTexture.create_from_image(image)
			break
	zip.close()
	return texture


## A name usable as a file name: Factorio's own save names allow letters, digits, spaces, - _ .
static func clean_name(name: String) -> String:
	var out := ""
	for ch in name.strip_edges():
		if ch.is_valid_identifier() or ch.is_valid_int() or ch in " -_.()":
			out += ch
		elif ch.unicode_at(0) > 127:
			out += ch
	return out.strip_edges().trim_suffix(".zip")


## A path in the server's saves for this name that isn't taken ("name", "name (2)", ...).
static func free_path(name: String) -> String:
	var dir := Paths.saves_dir()
	var path := dir.path_join(name + ".zip")
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s (%d).zip" % [name, n])
		n += 1
	return path


## Copies one of Factorio's saves into the server's saves; the copy's path, or "" on failure.
static func copy_to_server(path: String) -> String:
	DirAccess.make_dir_recursive_absolute(Paths.saves_dir())
	var target := free_path(path.get_file().get_basename())
	return target if DirAccess.copy_absolute(path, target) == OK else ""


## Moves a server save to the recycle bin (so a mistaken delete can be undone there).
static func delete(path: String) -> bool:
	return OS.move_to_trash(path) == OK
