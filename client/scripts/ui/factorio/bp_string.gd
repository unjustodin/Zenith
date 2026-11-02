extends RefCounted
## Factorio's exchange strings for blueprints, books and planners: a version character ("0"), then
## base64 of zlib-compressed JSON. Strings copied from the game or from websites decode here, and
## what this encodes imports in Factorio (LuaItemStack.import_stack, or the game's Import string).
##
## The JSON's top level names the kind: {"blueprint": {...}}, {"blueprint_book": {...}},
## {"deconstruction_planner": {...}} or {"upgrade_planner": {...}}. Records are kept decoded as
## these dictionaries (the library and the editors work on them) and encoded when they go to the
## game.

## The JSON key of each kind -> the item that holds it.
const ITEMS := {
	"blueprint": "blueprint", "blueprint_book": "blueprint-book",
	"deconstruction_planner": "deconstruction-planner", "upgrade_planner": "upgrade-planner",
}


## The decoded record, or {} when the text isn't an exchange string.
static func decode(text: String) -> Dictionary:
	var s := text.strip_edges()
	if s.length() < 2 or s[0] != "0":
		return {}
	var raw := Marshalls.base64_to_raw(s.substr(1))
	if raw.is_empty():
		return {}
	# Godot's DEFLATE mode is zlib's format (header and checksum), which is what Factorio writes.
	var json := raw.decompress_dynamic(64 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
	if json.is_empty():
		return {}
	var d = JSON.parse_string(json.get_string_from_utf8())
	if not (d is Dictionary) or kind(d) == "":
		return {}
	return d


static func encode(record: Dictionary) -> String:
	var json := JSON.stringify(_plain(record)).to_utf8_buffer()
	return "0" + Marshalls.raw_to_base64(json.compress(FileAccess.COMPRESSION_DEFLATE))


## JSON numbers come back as floats; whole ones go out as integers (Factorio's import wants
## integers for indices, entity numbers and versions).
static func _plain(v: Variant) -> Variant:
	if v is float and v == floorf(v) and absf(v) < 9.0e15:
		return int(v)
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _plain(v[k])
		return out
	if v is Array:
		var out: Array = []
		for x in v:
			out.append(_plain(x))
		return out
	return v


## "blueprint", "blueprint_book", "deconstruction_planner", "upgrade_planner", or "".
static func kind(record: Dictionary) -> String:
	for k in ITEMS:
		if record.has(k) and record[k] is Dictionary:
			return k
	return ""


static func item_of(record: Dictionary) -> String:
	return str(ITEMS.get(kind(record), ""))


## The record's body ({"item", "label", ...}).
static func body(record: Dictionary) -> Dictionary:
	var k := kind(record)
	return record[k] if k != "" else {}


static func label(record: Dictionary) -> String:
	return str(body(record).get("label", ""))


## Factorio's name for an unlabelled one.
static func title(record: Dictionary) -> String:
	var l := label(record)
	return l if l != "" else "Untitled"


## The icons as [[type, name], ...] in their order (blueprints keep them on the body, planners in
## their settings).
static func icons(record: Dictionary) -> Array:
	var b := body(record)
	var list = b.get("icons", b.get("settings", {}).get("icons", []) if b.get("settings") is Dictionary else [])
	var out: Array = []
	if list is Array:
		var sorted: Array = list.duplicate()
		sorted.sort_custom(func(a, c) -> bool: return int(a.get("index", 0)) < int(c.get("index", 0)))
		for i in sorted:
			if i is Dictionary and i.get("signal") is Dictionary:
				out.append([str(i["signal"].get("type", "item")), str(i["signal"].get("name", ""))])
	return out


static func set_icons(record: Dictionary, list: Array) -> void:
	var b := body(record)
	var out: Array = []
	for i in list.size():
		var icon: Array = list[i]
		if str(icon[1]) == "":
			continue
		var sig := {"name": str(icon[1])}
		if str(icon[0]) != "item":
			sig["type"] = str(icon[0])
		out.append({"signal": sig, "index": i + 1})
	var holder: Dictionary = b
	if kind(record) in ["deconstruction_planner", "upgrade_planner"]:
		if not (b.get("settings") is Dictionary):
			b["settings"] = {}
		holder = b["settings"]
	if out.is_empty():
		holder.erase("icons")
	else:
		holder["icons"] = out


static func description(record: Dictionary) -> String:
	var b := body(record)
	if b.has("description"):
		return str(b["description"])
	var st = b.get("settings")
	return str(st.get("description", "")) if st is Dictionary else ""


static func set_description(record: Dictionary, text: String) -> void:
	var b := body(record)
	var holder: Dictionary = b
	if kind(record) in ["deconstruction_planner", "upgrade_planner"]:
		if not (b.get("settings") is Dictionary):
			b["settings"] = {}
		holder = b["settings"]
	if text == "":
		holder.erase("description")
	else:
		holder["description"] = text


## How many of each entity and tile a blueprint holds: [[name, count, "entity"|"tile"], ...], most
## first (Factorio's components list).
static func components(record: Dictionary) -> Array:
	var counts := {}
	var b := body(record)
	for e in _list(b.get("entities")):
		var key := "entity:" + str(e.get("name", ""))
		counts[key] = int(counts.get(key, 0)) + 1
	for t in _list(b.get("tiles")):
		var key := "tile:" + str(t.get("name", ""))
		counts[key] = int(counts.get(key, 0)) + 1
	var out: Array = []
	for key in counts:
		var parts := str(key).split(":", true, 1)
		out.append([parts[1], counts[key], parts[0]])
	out.sort_custom(func(a, c) -> bool: return a[1] > c[1] or (a[1] == c[1] and str(a[0]) < str(c[0])))
	return out


## Takes every entity (or tile) of that name out of the blueprint, as clicking it in Factorio's
## components list does. Wires and other references to the removed entities go with them.
static func remove_component(record: Dictionary, name: String, what: String) -> void:
	var b := body(record)
	if what == "tile":
		b["tiles"] = _list(b.get("tiles")).filter(func(t: Dictionary) -> bool: return str(t.get("name", "")) != name)
		if (b["tiles"] as Array).is_empty():
			b.erase("tiles")
		return
	var gone := {}
	var kept: Array = []
	for e in _list(b.get("entities")):
		if str(e.get("name", "")) == name:
			gone[int(e.get("entity_number", 0))] = true
		else:
			kept.append(e)
	b["entities"] = kept
	if kept.is_empty():
		b.erase("entities")
	# 2.0 keeps wires in a list of [entity, connector, entity, connector].
	if b.get("wires") is Array:
		b["wires"] = (b["wires"] as Array).filter(func(w) -> bool:
			return w is Array and w.size() >= 4 and not gone.has(int(w[0])) and not gone.has(int(w[2])))
	if b.get("schedules") is Array:
		for sched in b["schedules"]:
			if sched is Dictionary and sched.get("locomotives") is Array:
				sched["locomotives"] = (sched["locomotives"] as Array).filter(func(n) -> bool: return not gone.has(int(n)))


static func _list(v) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if x is Dictionary:
				out.append(x)
	return out


## A book's pages in order: [[index (0-based), record], ...].
static func pages(record: Dictionary) -> Array:
	var out: Array = []
	for p in _list(body(record).get("blueprints")):
		var inner := {}
		for k in ITEMS:
			if p.has(k):
				inner[k] = p[k]
		if not inner.is_empty():
			out.append([int(p.get("index", out.size())), inner])
	out.sort_custom(func(a, c) -> bool: return a[0] < c[0])
	return out


## Writes a book's pages back, numbered in order (Factorio's book keeps an index per page).
static func set_pages(record: Dictionary, list: Array) -> void:
	var b := body(record)
	var out: Array = []
	for i in list.size():
		var page: Dictionary = list[i].duplicate()
		page["index"] = i
		out.append(page)
	b["blueprints"] = out
	if out.is_empty():
		b.erase("blueprints")
	b["active_index"] = clampi(int(b.get("active_index", 0)), 0, maxi(out.size() - 1, 0))


## An empty record of a kind, stamped with a game version (Factorio's 64-bit version number from
## another string; 0 lets the game assume its own).
static func empty(k: String, version := 0) -> Dictionary:
	var b := {"item": ITEMS.get(k, "blueprint")}
	if version != 0:
		b["version"] = version
	if k == "deconstruction_planner" or k == "upgrade_planner":
		b["settings"] = {}
	return {k: b}


## Factorio's version number of a record (major << 48 | minor << 32 | patch << 16 | build), or 0.
static func version_of(record: Dictionary) -> int:
	return int(body(record).get("version", 0))


## An upgrade planner's mappings applied to a blueprint (a book: every page), as Factorio's
## "Upgrade items and entities in the blueprint" does: each entity mapped from -> to changes its
## name, and module requests of mapped items too. Returns how many changed.
static func upgrade(record: Dictionary, planner: Dictionary) -> int:
	var map := {}
	var st = body(planner).get("settings")
	for m in _list(st.get("mappers") if st is Dictionary else null):
		if m.get("from") is Dictionary and m.get("to") is Dictionary:
			map[str(m["from"].get("name", ""))] = str(m["to"].get("name", ""))
	return _upgrade(record, map)


static func _upgrade(record: Dictionary, map: Dictionary) -> int:
	var n := 0
	if kind(record) == "blueprint_book":
		var list: Array = []
		for p in pages(record):
			n += _upgrade(p[1], map)
			list.append(p[1])
		set_pages(record, list)
		return n
	for e in _list(body(record).get("entities")):
		var name := str(e.get("name", ""))
		if map.has(name) and str(map[name]) != "":
			e["name"] = map[name]
			n += 1
	return n
