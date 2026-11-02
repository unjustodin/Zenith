extends RefCounted
## api.settings (add-on API 1.1): an add-on's own settings, declared by the add-on and shown on its
## page of Zenith's Add-ons menu (addons_window.gd) with its keys. Each has a type, a default, a
## label and options; values are kept per add-on in Zenith's settings file (section
## "addon_<id>"), so they last across games and Zenith updates, and `changed` says when one moves
## (from the menu, or from the add-on itself).
##
## Types and their options:
##   "bool"    a check box
##   "number"  a slider: "min", "max", "step" (1 by default; whole numbers then come back as ints
##             when the default is one), "unit" ("tiles", "s", "°/s": shown after the value)
##   "choice"  a dropdown: "choices", [[label, value], ...] (values strings or numbers)
##   "text"    a text box: "placeholder"
## Every type also takes "section" (a heading the setting goes under on the page) and "note" (its
## tooltip).

## A setting's value changed: from the Add-ons menu, set_value() or reset().
signal changed(id: String, value: Variant)

const Settings := preload("res://scripts/menu/settings.gd")
const TYPES := ["bool", "number", "choice", "text"]

var _host
var _api
var _defs := {}  # id -> the declaration (see list())


func _init(host, api) -> void:
	_host = host
	_api = api


## Declares a setting and returns its value now (the stored one, else the default). Declaring it
## again replaces the declaration and keeps the value.
func add(id: String, type: String, default: Variant, label: String, options := {}) -> Variant:
	if not type in TYPES:
		_api.note("settings.add(%s): unknown type \"%s\" (bool, number, choice or text)" % [id, type])
		return default
	var def := {"id": id, "type": type, "label": label, "section": str(options.get("section", "")),
		"note": str(options.get("note", ""))}
	match type:
		"bool":
			def["default"] = bool(default)
		"number":
			def["min"] = float(options.get("min", 0.0))
			def["max"] = maxf(float(options.get("max", 100.0)), float(def["min"]))
			def["step"] = maxf(float(options.get("step", 1.0)), 0.0)
			def["unit"] = str(options.get("unit", ""))
			def["integer"] = default is int and float(def["step"]) >= 1.0 and float(def["step"]) == floorf(float(def["step"]))
			def["default"] = default
			def["default"] = _clean(def, default)
		"choice":
			var choices: Array = []
			for c in options.get("choices", []):
				if c is Array and c.size() >= 2:
					choices.append([str(c[0]), c[1]])
				else:
					choices.append([str(c), c])
			def["choices"] = choices
			def["default"] = default
		"text":
			def["placeholder"] = str(options.get("placeholder", ""))
			def["default"] = str(default)
	_defs[id] = def
	return value(id)


## A setting's value now (the default when it was never set; null for one never declared).
func value(id: String) -> Variant:
	if not _defs.has(id):
		return null
	var def: Dictionary = _defs[id]
	if not Settings.has_value(section(), id):
		return def["default"]
	return _clean(def, Settings.get_value(section(), id))


## Every declared setting's value: {id: value}.
func values() -> Dictionary:
	var out := {}
	for id in _defs:
		out[id] = value(id)
	return out


## Changes a setting (kept at once; `persist` false while a slider is dragged, then
## Settings.save()). Says `changed` when the value moved. False for a setting never declared.
func set_value(id: String, v: Variant, persist := true) -> bool:
	if not _defs.has(id):
		return false
	var before = value(id)
	var now = _clean(_defs[id], v)
	Settings.set_value(section(), id, now, persist)
	if not _same(before, now):
		changed.emit(id, now)
	return true


## Back to its default.
func reset(id: String) -> void:
	if not _defs.has(id):
		return
	var before = value(id)
	Settings.reset_value(section(), id)
	var now = value(id)
	if not _same(before, now):
		changed.emit(id, now)


func is_default(id: String) -> bool:
	return _defs.has(id) and _same(value(id), _defs[id]["default"])


## The declarations in the order they were added: [{id, type, label, default, section, note, and
## the type's own: min, max, step, unit, integer / choices / placeholder}] (copies).
func list() -> Array:
	var out: Array = []
	for id in _defs:
		out.append((_defs[id] as Dictionary).duplicate(true))
	return out


## The settings file's section this add-on's values are in.
func section() -> String:
	return "addon_" + str(_api.id).replace("-", "_")


static func _clean(def: Dictionary, v: Variant) -> Variant:
	match str(def["type"]):
		"bool":
			return bool(v) if (v is bool or v is int or v is float) else bool(def["default"])
		"number":
			var f := float(v) if (v is int or v is float or (v is String and (v as String).is_valid_float())) else float(def["default"])
			f = clampf(f, float(def["min"]), float(def["max"]))
			if float(def["step"]) > 0.0:
				f = float(def["min"]) + snappedf(f - float(def["min"]), float(def["step"]))
				f = clampf(f, float(def["min"]), float(def["max"]))
			return int(roundf(f)) if bool(def["integer"]) else f
		"choice":
			for c in def["choices"]:
				if _same(c[1], v):
					return c[1]
			return def["default"]
		"text":
			return str(v)
	return v


static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return typeof(a) == typeof(b) and a == b


func _remove_all() -> void:
	_defs.clear()
