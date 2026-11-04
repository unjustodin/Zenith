extends RefCounted
## Finds Zenith's add-ons and reads their addon.json (docs/ADDONS.md). An add-on is a folder with
## an addon.json naming its entry script, or a .zip of one (addon.json at the zip's root or one
## folder down, as Factorio's mod zips), unpacked by Zenith into user://addons-cache/ when it starts
## (again only when the zip changes), so relative preloads work as in a folder. Looked for in these
## places; on a duplicate id one given on the command line wins (a development copy), else the
## newer version (a folder on a tie); the one left out is named in the Add-ons menu:
##   --addons=<folder>[,<folder>...]   an add-on's own folder, or a folder of add-ons (development;
##                                     always on while given)
##   user://addons                     Zenith's user data (on Windows %APPDATA%\Godot\app_userdata\Zenith\addons)
##   <Zenith's folder>/addons          beside Zenith.exe in a download (in a checkout: the repo's root)
##
## Whether each is on is kept in the settings file's [addons] section (id -> bool). Until the player
## sets it, an add-on is on, unless the download says otherwise: tools/release/package.py writes
## <Zenith's folder>/addons/bundled.json, {id: on?} for the add-ons it bundles (owner: the Cinematic
## camera on, Terrain Elevation off).

const Paths := preload("res://scripts/menu/paths.gd")
const Settings := preload("res://scripts/menu/settings.gd")

## The add-on API this Zenith offers (addon_api.gd). An add-on names the one it needs in its
## addon.json as "api"; one that needs a newer API than this is refused with a message.
const API_VERSION := 1
## The exact API level, with what was added within version 1 (1.1: api.settings, the Add-ons
## menu's pages, api.view.keep_drawing; 1.2: api.terrain). An addon.json may ask for 1.1 or 1.2;
## 1 means any 1.x.
const API_LEVEL := 1.2
const MANIFEST := "addon.json"
## Ids are folder-like names: lower case letters, digits, - and _.
const ID_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789-_"

## Extra folders to look in before the others (tests); when set, the usual places are skipped.
static var test_folders: Array = []
## Where zipped add-ons are unpacked (tests point it elsewhere).
static var cache_root := "user://addons-cache"


## [[folder, source], ...] in the order they are searched. Source: "command line", "user", "Zenith".
static func folders() -> Array:
	if not test_folders.is_empty():
		return test_folders.map(func(f: String) -> Array: return [f, "test"])
	var out: Array = []
	var given := Settings.arg_value("--addons=")
	if given != "":
		for f in given.split(",", false):
			out.append([f.strip_edges().replace("\\", "/"), "command line"])
	out.append([ProjectSettings.globalize_path("user://addons"), "user"])
	out.append([Paths.repo_dir().path_join("addons"), "Zenith"])
	return out


## Every add-on found, as manifests (see read() and read_zip()), in search order. Of two with one
## id, the one given on the command line is kept, else the newer version (the one found first on a
## tie); the kept one's "also" says what was left out.
static func scan(where: Array = []) -> Array:
	if where.is_empty():
		where = folders()
	var out: Array = []
	var seen := {}  # key -> index in out
	for pair in where:
		var dir := str(pair[0])
		var source := str(pair[1])
		var candidates: Array = []
		if dir.to_lower().ends_with(".zip") and FileAccess.file_exists(dir):
			candidates.append(dir)
		elif FileAccess.file_exists(dir.path_join(MANIFEST)):
			candidates.append(dir)
		elif DirAccess.dir_exists_absolute(dir):
			var subs := DirAccess.get_directories_at(dir)
			subs.sort()
			for sub in subs:
				if FileAccess.file_exists(dir.path_join(sub).path_join(MANIFEST)):
					candidates.append(dir.path_join(sub))
			var files := DirAccess.get_files_at(dir)
			files.sort()
			for f in files:
				if f.to_lower().ends_with(".zip"):
					candidates.append(dir.path_join(f))
		for c in candidates:
			var m := read_zip(c, source) if str(c).to_lower().ends_with(".zip") else read(c, source)
			var key := str(m["id"]).replace("-", "_")
			if not seen.has(key):
				seen[key] = out.size()
				out.append(m)
				continue
			var kept: Dictionary = out[seen[key]]
			var winner := kept
			var loser := m
			if str(kept["source"]) != "command line" and bool(m["ok"]) and (not bool(kept["ok"]) or compare_versions(str(m["version"]), str(kept["version"])) > 0):
				winner = m
				loser = kept
				out[seen[key]] = m
			var also: Array = winner.get("also", [])
			also.append_array(loser.get("also", []))
			also.append("%s %s (%s, %s)" % [where_text(loser), str(loser["version"]), str(loser.get("zip", loser["dir"])),
				"given on the command line instead" if str(winner["source"]) == "command line" else "older" if compare_versions(str(loser["version"]), str(winner["version"])) < 0 else "the same version"])
			winner["also"] = also
	return out


## "A zip" or "a folder", for the Add-ons menu.
static func where_text(m: Dictionary) -> String:
	return "A zip" if m.has("zip") else "A folder"


## -1, 0 or 1: version a older than, the same as or newer than b ("1.10.0" > "1.9.2"; parts that
## aren't numbers count as 0).
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() and pa[i].is_valid_int() else 0
		var y := int(pb[i]) if i < pb.size() and pb[i].is_valid_int() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


## A zipped add-on's manifest, read from inside the zip: as read(), plus "zip" (the zip's path) and
## "inner" (the folder in the zip holding addon.json, "" at its root); "dir" is where it is
## unpacked (unpack() before starting it).
static func read_zip(zip_path: String, source := "") -> Dictionary:
	var base := zip_path.get_file().get_basename()
	var m := {"id": _id_from_zip_name(base), "name": base, "version": "", "api": 0, "entry": "",
		"description": "", "author": "", "dir": cache_root.path_join(base), "zip": zip_path, "inner": "",
		"source": source, "ok": false, "problem": ""}
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		m["problem"] = "the zip can't be read (broken or not a zip)"
		return m
	var files := zip.get_files()
	var manifest := ""
	for f in files:
		if f == MANIFEST or (f.get_file() == MANIFEST and f.count("/") == 1):
			if manifest == "" or f.length() < manifest.length():
				manifest = f
	if manifest == "":
		zip.close()
		m["problem"] = "the zip has no addon.json at its root or one folder down"
		return m
	m["inner"] = manifest.get_base_dir() + "/" if manifest.contains("/") else ""
	var text := zip.read_file(manifest).get_string_from_utf8()
	_fill(m, text)
	if m["problem"] == "":
		var entry := str(m["inner"]) + str(m["entry"])
		if not files.has(entry):
			m["problem"] = "its entry script %s is missing from the zip" % str(m["entry"])
	m["ok"] = m["problem"] == ""
	zip.close()
	if m["ok"]:
		m["dir"] = cache_root.path_join(str(m["id"]))
	return m


static func _id_from_zip_name(base: String) -> String:
	# Factorio's naming: <name>_<version>.zip
	var cut := base.rfind("_")
	if cut > 0 and base.substr(cut + 1).replace(".", "").is_valid_int():
		return base.left(cut)
	return base


## Unpacks a zipped add-on into its cache folder (only when the zip changed since the last time).
## "" when it's ready, else why not.
static func unpack(m: Dictionary) -> String:
	if not m.has("zip"):
		return ""
	var zip_path := str(m["zip"])
	var dir := str(m["dir"])
	var stamp := "%d %d %s" % [FileAccess.get_modified_time(zip_path), FileAccess.get_file_as_bytes(zip_path).size(), str(m["version"])]
	var stamp_file := dir.path_join(".zenith-unpacked")
	if FileAccess.file_exists(stamp_file) and FileAccess.get_file_as_string(stamp_file) == stamp:
		return ""
	_remove_tree(dir)
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "the zip can't be read"
	var inner := str(m["inner"])
	for f in zip.get_files():
		if not f.begins_with(inner) or f.ends_with("/"):
			continue
		var rel := f.substr(inner.length())
		if rel == "" or rel.contains("..") or rel.begins_with("/"):
			continue
		var target := dir.path_join(rel)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			zip.close()
			return "it can't be unpacked to %s" % ProjectSettings.globalize_path(dir)
		out.store_buffer(zip.read_file(f))
		out.close()
	zip.close()
	var s := FileAccess.open(stamp_file, FileAccess.WRITE)
	if s != null:
		s.store_string(stamp)
		s.close()
	return ""


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## An add-on's manifest: {id, name, version, api, entry, description, author, dir, source,
## ok (bool), problem (why it can't load, "" when it can)}.
static func read(dir: String, source := "") -> Dictionary:
	var m := {"id": dir.get_file(), "name": dir.get_file(), "version": "", "api": 0, "entry": "",
		"description": "", "author": "", "dir": dir, "source": source, "ok": false, "problem": ""}
	var text := FileAccess.get_file_as_string(dir.path_join(MANIFEST))
	_fill(m, text)
	m["ok"] = m["problem"] == ""
	return m


## Reads addon.json's text into a manifest: its fields, and "problem" when it can't load.
static func _fill(m: Dictionary, text: String) -> void:
	var json := JSON.new()  # an instance: a broken file is reported here, not as an engine error
	var parsed = json.data if text != "" and json.parse(text) == OK else null
	if not parsed is Dictionary:
		m["problem"] = "its addon.json isn't valid JSON"
		return
	var j: Dictionary = parsed
	for key in ["id", "name", "version", "entry", "description", "author"]:
		if j.has(key) and j[key] != null:
			m[key] = str(j[key])
	m["api"] = float(j.get("api", 0)) if (j.get("api") is float or j.get("api") is int) else 0.0
	m["problem"] = problem_of(m)


## Why a manifest can't be loaded, or "".
static func problem_of(m: Dictionary) -> String:
	var id := str(m["id"])
	if id == "" or not _valid_id(id):
		return "its id \"%s\" must be lower case letters, digits, - and _" % id
	if str(m["version"]) == "":
		return "its addon.json has no version"
	if float(m["api"]) <= 0.0:
		return "its addon.json doesn't say which add-on API it needs (\"api\": %d)" % API_VERSION
	if float(m["api"]) > API_LEVEL + 0.0001:
		return "it needs a newer Zenith (add-on API %s; this Zenith has %s)" % [_level_text(float(m["api"])), _level_text(API_LEVEL)]
	var entry := str(m["entry"])
	if entry == "" or not entry.ends_with(".gd"):
		return "its addon.json has no entry script (a .gd file)"
	if not m.has("zip") and not FileAccess.file_exists(str(m["dir"]).path_join(entry)):  # a zip's is checked inside it
		return "its entry script %s is missing" % entry
	return ""


static func _level_text(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(snappedf(v, 0.01))


static func _valid_id(id: String) -> bool:
	for c in id:
		if not ID_CHARS.contains(c):
			return false
	return true


## On unless switched off in the Add-ons menu, or off by the download's default (bundled.json) until
## switched on. Add-ons given with --addons are always on.
static func enabled(m: Dictionary) -> bool:
	if str(m.get("source", "")) == "command line":
		return true
	var id := str(m["id"])
	if Settings.has_value("addons", id):
		return bool(Settings.get_value("addons", id))
	return bool(bundled_defaults().get(id, true))


## The download's defaults for its bundled add-ons: {id: on?} from <Zenith's folder>/addons/bundled.json
## (none in a checkout, or when it can't be read).
static func bundled_defaults(path := "") -> Dictionary:
	if path == "":
		path = Paths.repo_dir().path_join("addons/bundled.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func set_enabled(id: String, on: bool) -> void:
	Settings.set_value("addons", id, on)
