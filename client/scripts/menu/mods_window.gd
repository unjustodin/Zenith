extends PanelContainer
## Factorio's Mods window for the server the menu starts: the game's own mods (base and the DLC
## from the install's data folder) and the mods in the server's mods folder (zips and folders),
## each with its version and an on/off box. Changes go into the server's mods/mod-list.json, so
## they apply the next time a server starts. The bridge mod is always on. Space Age needs Quality
## and Elevated rails, as in Factorio; turning one on or off carries the others along.

signal closed

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Paths := preload("res://scripts/menu/paths.gd")
const Sfx := preload("res://scripts/fx/sfx.gd")

const BRIDGE := "factorio-3d-bridge"
const DLC := ["base", "elevated-rails", "quality", "space-age"]
## mod -> the mods it needs (Factorio's DLC dependencies).
const NEEDS := {"space-age": ["quality", "elevated-rails"]}

## While a game runs the list is shown but not changed (Factorio's own window does the same).
var read_only := false
## Zenith's add-ons (scripts/addons/addon_host.gd), listed after the mods with their own switches,
## which apply at once, in a game too; null leaves them out.
var addons = null

var _mods: Array = []  # [{name, title, version, source, enabled}]
var _list: VBoxContainer
var _boxes := {}  # name -> CheckBox


func _ready() -> void:
	theme_type_variation = "FFrame"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Mods", true)
	box.add_child(bar)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: closed.emit())
	var where := MenuKit.paragraph("The server's mods (%s). Changes apply the next time a server starts." % Paths.server_data_dir().path_join("mods"), 560)
	where.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	box.add_child(where)
	var deep: Array = Kit.deep_scroll(Kit.pxv(560, 360))
	box.add_child(deep[0])
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.add_theme_constant_override("separation", Kit.px(2))
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deep[1].add_child(_list)
	var row: Array = MenuKit.dialog_buttons("Back", "")
	box.add_child(row[0])
	(row[1] as Button).pressed.connect(func() -> void:
		Sfx.play_ui("gui-back")
		closed.emit())
	_mods = scan()
	_fill()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()


## Every mod the server could load, with its state in mod-list.json (on when not listed, as
## Factorio does).
static func scan() -> Array:
	var states := _list_states()
	var out: Array = []
	var data := Paths.read_data_dir(Paths.factorio_exe())
	for name in DLC:
		var info := _info_at(data.path_join(name))
		if not info.is_empty():
			out.append(_entry(name, info, "game", states))
	var mods_dir := Paths.server_data_dir().path_join("mods")
	if DirAccess.dir_exists_absolute(mods_dir):
		for dir in DirAccess.get_directories_at(mods_dir):
			var info := _info_at(mods_dir.path_join(dir))
			if not info.is_empty():
				out.append(_entry(str(info.get("name", dir)), info, "folder", states))
		for file in DirAccess.get_files_at(mods_dir):
			if file.to_lower().ends_with(".zip"):
				var info := _info_in_zip(mods_dir.path_join(file))
				if not info.is_empty():
					out.append(_entry(str(info.get("name", file.get_basename())), info, "zip", states))
	return out


static func _entry(name: String, info: Dictionary, source: String, states: Dictionary) -> Dictionary:
	return {"name": name, "title": str(info.get("title", name)), "version": str(info.get("version", "")),
		"source": source, "enabled": name == BRIDGE or bool(states.get(name, true))}


static func _info_at(dir: String) -> Dictionary:
	var file := dir.path_join("info.json")
	if not FileAccess.file_exists(file):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
	return parsed if parsed is Dictionary else {}


static func _info_in_zip(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {}
	var info := {}
	for f in zip.get_files():
		if f.get_file() == "info.json" and f.count("/") <= 1:
			var parsed = JSON.parse_string(zip.read_file(f).get_string_from_utf8())
			if parsed is Dictionary:
				info = parsed
			break
	zip.close()
	return info


static func _list_states() -> Dictionary:
	var out := {}
	var file := Paths.server_data_dir().path_join("mods/mod-list.json")
	if not FileAccess.file_exists(file):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
	if parsed is Dictionary:
		for m in parsed.get("mods", []):
			if m is Dictionary:
				out[str(m.get("name", ""))] = bool(m.get("enabled", true))
	return out


## Writes mod-list.json, keeping entries of mods not found here.
static func write_states(mods: Array) -> void:
	var file := Paths.server_data_dir().path_join("mods/mod-list.json")
	var states := _list_states()
	for m in mods:
		states[m["name"]] = bool(m["enabled"])
	var list: Array = []
	for name in states:
		list.append({"name": name, "enabled": states[name]})
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"mods": list}, "  "))
		f.close()


## Turns a mod on or off, with the DLC that go with it.
func set_enabled(name: String, on: bool) -> void:
	var change := {name: on}
	if on:
		for need in NEEDS.get(name, []):
			change[need] = true
	else:
		for other in NEEDS:
			if (NEEDS[other] as Array).has(name):
				change[other] = false
	for m in _mods:
		if change.has(m["name"]) and m["name"] != BRIDGE and m["name"] != "base":
			m["enabled"] = change[m["name"]]
	write_states(_mods)
	_fill()


func _fill() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_boxes.clear()
	var last := ""
	for m in _mods:
		var group := "Factorio" if m["source"] == "game" else "Mods"
		if group != last:
			last = group
			_list.add_child(Kit.label(group, "FHeading"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(8))
		var c := MenuKit.checkbox("", bool(m["enabled"]))
		c.name = str(m["name"])
		c.disabled = read_only or m["name"] in [BRIDGE, "base"]
		if m["name"] == BRIDGE:
			c.tooltip_text = "The bridge to the 3D client is always on."
		var name: String = m["name"]
		c.toggled.connect(func(on: bool) -> void:
			Sfx.play_ui("gui-checkbox-click")
			set_enabled(name, on))
		row.add_child(c)
		var title := Kit.label(str(m["title"]))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		var version := Kit.label(str(m["version"]))
		version.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		row.add_child(version)
		_list.add_child(row)
		_boxes[name] = c
	if read_only:
		var n := MenuKit.paragraph("Leave the game to change the mods.", 520)
		n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_list.add_child(n)
	if addons != null:
		_fill_addons()


## Zenith's add-ons: each with its switch (at once, in a game too), version, and why it isn't
## running when it can't; Options shows a running add-on's own settings under it.
func _fill_addons() -> void:
	_list.add_child(Kit.label("Zenith add-ons", "FHeading"))
	var found: Array = addons.addons
	if found.is_empty():
		var n := MenuKit.paragraph("None installed. An add-on is a folder put in %s (docs/ADDONS.md)." % ProjectSettings.globalize_path("user://addons"), 520)
		n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_list.add_child(n)
		return
	for m: Dictionary in found:
		var id := str(m["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(8))
		var c := MenuKit.checkbox("", m.has("object"))
		c.name = "addon-" + id
		c.disabled = not bool(m["ok"]) or str(m["source"]) == "command line"
		if str(m["source"]) == "command line":
			c.tooltip_text = "Given with --addons: always on."
		c.toggled.connect(func(on: bool) -> void:
			Sfx.play_ui("gui-checkbox-click")
			addons.set_enabled(id, on)
			_fill())
		row.add_child(c)
		var title := Kit.label(str(m["name"]))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.tooltip_text = "%s\n%s" % [str(m["description"]), str(m["dir"])]
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(title)
		var options: Callable = m["object"].ui._options_builder() if m.has("object") else Callable()
		var holder := VBoxContainer.new()
		if options.is_valid():
			var b := MenuKit.button("Options")
			b.name = "addon-options-" + id
			b.pressed.connect(func() -> void:
				Sfx.play_ui("gui-click")
				if holder.get_child_count() > 0:
					for ch in holder.get_children():
						ch.queue_free()
				else:
					options.call(holder))
			row.add_child(b)
		var version := Kit.label(str(m["version"]))
		version.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		row.add_child(version)
		_list.add_child(row)
		var why := str(m.get("error", m["problem"]))
		if why != "":
			var n := Kit.label("Not loaded: " + why)
			n.name = "addon-problem-" + id
			n.add_theme_color_override("font_color", Kit.RED_TEXT)
			_list.add_child(n)
		_list.add_child(holder)
