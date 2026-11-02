extends RefCounted
## Names as the player sees them ("Iron gear wheel"), read from the locale files in the player's
## own Factorio install (<data>/<mod>/locale/<language>/*.cfg). The mod can only send internal
## names: a headless server has no player to translate for. Without an install, internal names
## are tidied up instead ("iron-gear-wheel" -> "Iron gear wheel").
##
## Command-line option (after `--`): --factorio-locale=<language> (default en).

const ItemIcons := preload("res://scripts/world/item_icons.gd")

static var language := "en"
static var _sections := {}  # "item-name" -> {key: text}
static var _loaded := false


static func configure_from_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--factorio-locale="):
			language = arg.get_slice("=", 1)


static func item(name: String) -> String:
	return _first(name, ["item-name", "entity-name", "equipment-name", "fluid-name"])


static func entity(name: String) -> String:
	return _first(name, ["entity-name", "item-name"])


static func recipe(name: String) -> String:
	return _first(name, ["recipe-name", "item-name", "fluid-name", "entity-name"])


## Planets and other places in space ("Vulcanus", "Solar system edge").
static func space_location(name: String) -> String:
	return _first(name, ["space-location-name"])


## Levelled technologies ("logistics-2") are their base name plus the level.
static func technology(name: String) -> String:
	_load()
	var text := _lookup("technology-name", name)
	if text != "":
		return text
	var m := RegEx.create_from_string("^(.*)-(\\d+)$").search(name)
	if m != null:
		var base := _lookup("technology-name", m.get_string(1))
		if base != "":
			return "%s %s" % [base, m.get_string(2)]
	return _tidy(name)


static func _first(name: String, sections: Array) -> String:
	_load()
	for section in sections:
		var text := _lookup(section, name)
		if text != "":
			return text
	return _tidy(name)


## References like __ITEM__iron-plate__ are replaced by that name.
static func _lookup(section: String, key: String) -> String:
	var table: Dictionary = _sections.get(section, {})
	var text := str(table.get(key, ""))
	if text.contains("__"):
		var re := RegEx.create_from_string("__(ITEM|ENTITY|FLUID|RECIPE|TILE)__([^_]+(?:_[^_]+)*)__")
		for m in re.search_all(text):
			var kind := m.get_string(1).to_lower() + "-name"
			var other := str((_sections.get(kind, {}) as Dictionary).get(m.get_string(2), m.get_string(2)))
			text = text.replace(m.get_string(0), other)
	return text


static func _tidy(name: String) -> String:
	var words := name.replace("-", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data := ItemIcons.factorio_data_dir()
	if data == "":
		return
	for mod in ItemIcons.MODS:
		var dir := data.path_join(mod).path_join("locale").path_join(language)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".cfg"):
				_parse(FileAccess.get_file_as_string(dir.path_join(file)))


## [section] headers, key=value lines; anything before the first header is skipped.
static func _parse(text: String) -> void:
	var section := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2)
			if not _sections.has(section):
				_sections[section] = {}
			continue
		var eq := line.find("=")
		if section != "" and eq > 0:
			_sections[section][line.substr(0, eq)] = line.substr(eq + 1)
