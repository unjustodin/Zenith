extends RefCounted
## Factorio's numbers as its tooltips and Factoriopedia write them ("150 kW", "4 MJ", "3/m"), and the
## stat lines of items, entities, recipes and technologies from Factoriopedia's data (the mod's
## `pedia` pages, ui_model.pedia_data). Lines are Kit.tooltip's: [text], [text, icon item] or
## [text, icon item or "", Color].

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")

const STAT := Color(0.85, 0.85, 0.85)
const ROBOT_EFFECTS := {"speed": "Speed", "productivity": "Productivity", "consumption": "Energy consumption",
	"pollution": "Pollution", "quality": "Quality"}
## LuaSpaceLocationPrototype surface properties: name, unit, scale.
const PROPERTIES := {"gravity": ["Gravity", "m/s²", 0.1], "pressure": ["Pressure", "hPa", 1.0],
	"magnetic-field": ["Magnetic field", "μT", 1.0], "solar-power": ["Solar power", "%", 1.0],
	"day-night-cycle": ["Day/night cycle", "min", 1.0 / 3600.0]}


static func si(v: float, unit: String) -> String:
	for step in [[1e12, "T"], [1e9, "G"], [1e6, "M"], [1e3, "k"]]:
		if absf(v) >= float(step[0]):
			return "%s %s%s" % [num(v / float(step[0])), step[1], unit]
	return "%s %s" % [num(v), unit]


## Up to two decimals, without trailing zeros.
static func num(v: float) -> String:
	var s := "%.2f" % v
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


static func watts(w: float) -> String:
	return si(w, "W")


static func joules(j: float) -> String:
	return si(j, "J")


static func seconds(s: float) -> String:
	if s < 60.0:
		return "%ss" % num(s)
	var t := roundi(s)
	if t < 3600:
		return "%dm %ds" % [t / 60, t % 60] if t % 60 != 0 else "%dm" % (t / 60)
	return "%dh %dm" % [t / 3600, (t % 3600) / 60]


## A prototype's description from the locale files ("" without one).
static func description(kind: String, name: String) -> String:
	LocaleNames._load()
	var sections: Array = {"item": ["item-description", "entity-description"], "fluid": ["fluid-description"],
		"entity": ["entity-description", "item-description"], "recipe": ["recipe-description", "item-description"],
		"technology": ["technology-description"], "tile": ["tile-description"], "planet": ["space-location-description"],
		"space-location": ["space-location-description"], "quality": ["quality-description"]}.get(kind, [])
	for section in sections:
		var text := LocaleNames._lookup(section, name)
		if text != "":
			return text.replace("\\n", "\n")
	return ""


## A display name for any kind Factoriopedia lists.
static func display_name(kind: String, name: String) -> String:
	match kind:
		"entity":
			return Kit.entity_name(name)
		"recipe":
			return Kit.recipe_name(name)
		"technology":
			return Kit.tech_name(name)
		"planet", "space-location":
			return LocaleNames.space_location(name)
		"tile":
			return LocaleNames._first(name, ["tile-name"])
		"quality":
			return LocaleNames._first(name, ["quality-name"])
	return Kit.pretty(name)


## An entity's stats (d: a page's data, or an item page's "entity"), Factorio's order.
static func entity_lines(d: Dictionary) -> Array:
	var lines: Array = []
	if d.has("craft"):
		lines.append(["Crafting speed: %s" % num(float(d["craft"]))])
	if d.has("mine_speed"):
		lines.append(["Mining speed: %s/s" % num(float(d["mine_speed"]))])
	if d.has("belt"):
		lines.append(["Speed: %s items/s" % num(float(d["belt"]))])
	if d.has("research"):
		lines.append(["Research speed: %s" % num(float(d["research"]))])
	if d.has("rot"):
		lines.append(["Rotation speed: %s°/s" % num(float(d["rot"]))])
	if d.has("energy"):
		var etype := str(d.get("etype", ""))
		var text := "Energy consumption: %s" % watts(float(d["energy"]))
		if etype in ["burner", "heat", "fluid"]:
			text += " (%s)" % {"burner": "burner", "heat": "heat", "fluid": "fluid"}[etype]
		lines.append([text])
	if d.has("drain"):
		lines.append(["Drain: %s" % watts(float(d["drain"]))])
	if d.has("power"):
		lines.append(["Maximum power output: %s" % watts(float(d["power"]))])
	if d.get("poll") is Dictionary:
		for p in d["poll"]:
			var v := float(d["poll"][p])
			if v != 0.0:
				lines.append(["%s: %s/m" % [("Pollution" if p == "pollution" else Kit.pretty(str(p))), num(v)]])
	if d.has("modules"):
		lines.append(["Module slots: %d" % int(d["modules"])])
	if d.has("fuels"):
		var names: Array = []
		for f in d["fuels"]:
			names.append(Kit.pretty(str(f)) + " fuel")
		lines.append(["Fuel: %s" % ", ".join(names)])
	if d.has("hp"):
		lines.append(["Health: %s" % num(float(d["hp"]))])
	for r in d.get("res", []):
		if r is Array and r.size() >= 3:
			lines.append(["  %s: %s/%s%%" % [Kit.pretty(str(r[0])), num(float(r[1])), num(float(r[2]))], "", STAT])
	if d.has("range"):
		lines.append(["Range: %s" % num(float(d["range"]))])
	if d.has("supply"):
		lines.append(["Supply area: %s×%s" % [num(float(d["supply"])), num(float(d["supply"]))]])
	if d.has("wire"):
		lines.append(["Wire reach: %s" % num(float(d["wire"]))])
	if d.has("under"):
		lines.append(["Max. underground distance: %d" % int(d["under"])])
	if d.has("mradius"):
		lines.append(["Mining area: %s×%s" % [num(float(d["mradius"])), num(float(d["mradius"]))]])
	if d.has("inv"):
		lines.append(["Storage size: %d" % int(d["inv"])])
	if d.has("speed"):
		lines.append(["Speed: %s km/h" % num(float(d["speed"]) * 3.6)])
	if d.has("size") and d["size"] is Array and (d["size"] as Array).size() == 2 and int(d["size"][0]) > 0:
		lines.append(["Size: %d×%d" % [int(d["size"][0]), int(d["size"][1])]])
	return lines


## An item's own stats (stack size, fuel, weight, spoiling, module effects), then its entity's.
static func item_lines(d: Dictionary) -> Array:
	var lines: Array = []
	if d.has("fuel"):
		lines.append(["Fuel value: %s" % joules(float(d["fuel"]))])
	if d.has("module"):
		var fx: Dictionary = d["module"]
		for k in ["speed", "productivity", "consumption", "pollution", "quality"]:
			if fx.has(k) and float(fx[k]) != 0.0:
				var v := float(fx[k]) * (10.0 if k == "quality" else 100.0)
				lines.append(["%s: %s%s%%" % [ROBOT_EFFECTS[k], "+" if v > 0 else "", num(v)], "",
					Kit.GREEN_TEXT if (v > 0) != (k in ["consumption", "pollution"]) else Kit.RED_TEXT])
	if d.has("spoil"):
		lines.append(["Spoil time: %s" % seconds(float(d["spoil"]) / 60.0)])
		if d.has("spoil_to"):
			lines.append(["Spoils into %s" % Kit.pretty(str(d["spoil_to"])), str(d["spoil_to"])])
	if d.has("stack"):
		lines.append(["Stack size: %d" % int(d["stack"])])
	if d.has("weight") and float(d["weight"]) > 0.0:
		lines.append(["Weight: %s kg" % num(float(d["weight"]) / 1000.0)])
	if d.get("entity") is Dictionary:
		lines.append_array(entity_lines(d["entity"]))
	return lines


## A recipe's ingredients, time and products as tooltip lines.
static func recipe_lines(d: Dictionary) -> Array:
	var lines: Array = [["Ingredients:"]]
	for i in d.get("ing", []):
		lines.append(["%s × %s" % [num(float(i[2])), Kit.pretty(str(i[1]))], str(i[1])])
	lines.append(["%s Crafting time" % seconds(float(d.get("time", 0.5)))])
	lines.append(["Products:"])
	for p in d.get("prod", []):
		lines.append(["%s × %s" % [num(float(p[2])), Kit.pretty(str(p[1]))], str(p[1])])
	return lines


## What a technology's trigger asks for ("Craft 50 Iron plate").
static func trigger_text(detail: Array, trigger: String) -> String:
	var t := str(detail[0]) if detail.size() > 0 else trigger
	var target := str(detail[1]) if detail.size() > 1 else ""
	var count := int(detail[2]) if detail.size() > 2 else 1
	var what := Kit.pretty(target) if target != "" else ""
	match t:
		"craft-item":
			return "Craft %s%s" % ["%d × " % count if count > 1 else "", what]
		"craft-fluid":
			return "Produce %s%s" % ["%d × " % count if count > 1 else "", what]
		"mine-entity":
			return "Mine %s" % Kit.entity_name(target)
		"build-entity":
			return "Build %s" % Kit.entity_name(target)
		"capture-spawner":
			return "Capture a spawner"
		"send-item-to-orbit":
			return "Launch %s into orbit" % what
		"create-space-platform":
			return "Create a space platform"
		"scripted":
			return "Unlocked by a script"
	return t.replace("-", " ").capitalize() + (" " + what if what != "" else "")


## A technology effect as Factorio lists it: [text, icon item].
static func effect_line(e: Array) -> Array:
	var t := str(e[0])
	if t == "unlock-recipe":
		return [Kit.recipe_name(str(e[1])), str(e[1])]
	var v := float(e[2]) if e.size() > 2 else 0.0
	var words := t.replace("-", " ")
	var text := words.substr(0, 1).to_upper() + words.substr(1)
	if str(e[1]) != "":
		text += " (%s)" % Kit.pretty(str(e[1]))
	if v != 0.0:
		text += ": %s%s%%" % ["+" if v > 0 else "", num(v * 100.0)]
	return [text, ""]
