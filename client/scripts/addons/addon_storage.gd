extends RefCounted
## api.storage: an add-on's own data as JSON files in Zenith's user data, one set per save (camera
## paths over a base belong to that base) and one for every save (options, presets):
##   user://addons-data/<id>/<name>.json                 read_global / write_global
##   user://addons-data/<id>/saves/<save key>/<name>.json  read / write
## The save key is the save's name for a game started from Zenith's menu, else the address of the
## bridge it connected to ("address 127.0.0.1-34200"). Values are plain JSON: numbers, strings,
## booleans, arrays and dictionaries (store a Vector3 as [x, y, z]); JSON numbers come back as floats.

## Where every add-on's data goes (tests point it elsewhere).
static var root := "user://addons-data"

var _host
var _api


func _init(host, api) -> void:
	_host = host
	_api = api


## The current save's key ("" outside a game), safe as a folder name.
func save_key() -> String:
	return clean(_host.save_key())


## This add-on's data folder.
func folder() -> String:
	return root.path_join(_api.id)


## The current save's data called `name`, {} when there is none yet (or outside a game).
func read(name := "data") -> Dictionary:
	if save_key() == "":
		return {}
	return _read_file(folder().path_join("saves").path_join(save_key()).path_join(clean(name) + ".json"))


## Saves the current save's data called `name`. False outside a game or when it can't be written.
func write(data: Dictionary, name := "data") -> bool:
	if save_key() == "":
		return false
	return _write_file(folder().path_join("saves").path_join(save_key()).path_join(clean(name) + ".json"), data)


## Data for every save.
func read_global(name := "settings") -> Dictionary:
	return _read_file(folder().path_join(clean(name) + ".json"))


func write_global(data: Dictionary, name := "settings") -> bool:
	return _write_file(folder().path_join(clean(name) + ".json"), data)


## A name safe for a file: letters, digits, space, - _ . kept, the rest as _.
static func clean(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		out += c if (c.is_valid_identifier() or c.is_valid_int() or c in [" ", "-", "."]) else "_"
	return out.trim_prefix(".").left(80)


static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _write_file(path: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	# Written whole first, then put in place: a crash mid-write can't leave half a file.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
