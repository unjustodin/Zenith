extends RefCounted
## What Factorio's map generator window sets, as the two JSON files `factorio --create` takes:
## map-gen-settings (autoplace controls, cliffs, terrain expressions, starting area, peaceful mode,
## size) and map-settings (pollution, evolution, expansion, difficulty, asteroids). Starts from the
## install's map-gen-settings.example.json / map-settings.example.json, with every autoplace
## control of the enabled mods filled in, then a preset from base/prototypes/map-gen-presets.lua.
##
## The settings are one Dictionary {"gen": {...}, "map": {...}, "preset": name}; get_value() and
## set_value() address them by path ("gen/autoplace_controls/iron-ore/richness"). Space Age's
## controls are left out when its mod is off in the server's mod-list.json (Factorio refuses
## controls it doesn't know).

const Paths := preload("res://scripts/menu/paths.gd")

## Autoplace controls in Factorio's order: [name, label, category, planet, richness?]. From
## base and space-age prototypes/autoplace-controls.lua and the planets' map_gen_settings.
const CONTROLS := [
	["iron-ore", "Iron ore", "resource", "nauvis", true],
	["copper-ore", "Copper ore", "resource", "nauvis", true],
	["stone", "Stone", "resource", "nauvis", true],
	["coal", "Coal", "resource", "nauvis", true],
	["uranium-ore", "Uranium ore", "resource", "nauvis", true],
	["crude-oil", "Crude oil", "resource", "nauvis", true],
	["vulcanus_coal", "Coal", "resource", "vulcanus", true],
	["tungsten_ore", "Tungsten ore", "resource", "vulcanus", true],
	["calcite", "Calcite", "resource", "vulcanus", true],
	["sulfuric_acid_geyser", "Sulfuric acid geyser", "resource", "vulcanus", true],
	["gleba_stone", "Stone", "resource", "gleba", true],
	["scrap", "Scrap", "resource", "fulgora", true],
	["lithium_brine", "Lithium brine", "resource", "aquilo", true],
	["fluorine_vent", "Fluorine vent", "resource", "aquilo", true],
	["aquilo_crude_oil", "Crude oil", "resource", "aquilo", true],
	["water", "Water", "terrain", "nauvis", false],
	["trees", "Trees", "terrain", "nauvis", false],
	["rocks", "Rocks", "terrain", "nauvis", false],
	["vulcanus_volcanism", "Volcanism", "terrain", "vulcanus", false],
	["gleba_water", "Water", "terrain", "gleba", false],
	["gleba_plants", "Plants", "terrain", "gleba", false],
	["fulgora_islands", "Islands", "terrain", "fulgora", false],
	["nauvis_cliff", "Cliffs", "cliff", "nauvis", false],
	["gleba_cliff", "Cliffs", "cliff", "gleba", false],
	["fulgora_cliff", "Cliffs", "cliff", "fulgora", false],
	["enemy-base", "Enemy bases", "enemy", "nauvis", false],
	["gleba_enemy_base", "Enemy bases", "enemy", "gleba", false],
]
const PLANETS := ["nauvis", "vulcanus", "gleba", "fulgora", "aquilo"]
## The slider steps of Factorio's map generator: 17% to 600% ("None" turns a control off).
const STEPS := [0.0, 1.0 / 6.0, 0.25, 1.0 / 3.0, 0.5, 0.70710678, 1.0, 1.41421356, 2.0, 3.0, 4.0, 6.0]
## Map type on Nauvis: the elevation expression (map-gen-presets.lua's lakes and island).
const MAP_TYPES := [["Normal", ""], ["Lakes", "elevation_lakes"], ["Island", "elevation_island"]]

## base/prototypes/map-gen-presets.lua, with its named sizes as numbers (very-low 0.5, low 0.707,
## high 1.414, very-high / very-big / very-good 2, small 0.707).
const PRESETS := {
	"default": {"name": "Default", "gen": {}, "map": {}},
	"rich-resources": {"name": "Rich resources", "gen": {"autoplace_controls": {
		"iron-ore": {"richness": 2}, "copper-ore": {"richness": 2}, "stone": {"richness": 2},
		"coal": {"richness": 2}, "uranium-ore": {"richness": 2}, "crude-oil": {"richness": 2}}}, "map": {}},
	"marathon": {"name": "Marathon", "gen": {}, "map": {"difficulty_settings": {"technology_price_multiplier": 4}}},
	"death-world": {"name": "Death world", "gen": {
		"autoplace_controls": {"enemy-base": {"frequency": 2, "size": 2}}, "starting_area": 0.70710678},
		"map": {"enemy_evolution": {"time_factor": 0.00002, "pollution_factor": 0.0000012},
			"pollution": {"ageing": 0.5, "enemy_attack_pollution_consumption_modifier": 0.5},
			"enemy_expansion": {"build_base_unit_dispatch_cooldown": 600}}},
	"death-world-marathon": {"name": "Death world marathon", "gen": {
		"autoplace_controls": {"enemy-base": {"frequency": 2, "size": 2}}, "starting_area": 0.70710678},
		"map": {"enemy_evolution": {"time_factor": 0.000015, "pollution_factor": 0.000001},
			"pollution": {"ageing": 0.5, "enemy_attack_pollution_consumption_modifier": 0.8},
			"enemy_expansion": {"build_base_unit_dispatch_cooldown": 600},
			"difficulty_settings": {"technology_price_multiplier": 4}}},
	"rail-world": {"name": "Rail world", "gen": {"autoplace_controls": {
		"coal": {"frequency": 0.33333333, "size": 3}, "copper-ore": {"frequency": 0.33333333, "size": 3},
		"crude-oil": {"frequency": 0.33333333, "size": 3}, "uranium-ore": {"frequency": 0.33333333, "size": 3},
		"iron-ore": {"frequency": 0.33333333, "size": 3}, "stone": {"frequency": 0.33333333, "size": 3},
		"enemy-base": {"size": 1}, "water": {"frequency": 0.5, "size": 1.5}}},
		"map": {"enemy_evolution": {"time_factor": 0.000002}, "enemy_expansion": {"enabled": false}}},
	"ribbon-world": {"name": "Ribbon world", "gen": {
		"property_expression_names": {"elevation": "elevation_lakes", "trees_forest_path_cutout": 1},
		"autoplace_controls": {
			"coal": {"frequency": 3, "size": 0.5, "richness": 2}, "copper-ore": {"frequency": 3, "size": 0.5, "richness": 2},
			"crude-oil": {"frequency": 3, "size": 0.5, "richness": 2}, "uranium-ore": {"frequency": 3, "size": 0.5, "richness": 2},
			"iron-ore": {"frequency": 3, "size": 0.5, "richness": 2}, "stone": {"frequency": 3, "size": 0.5, "richness": 2},
			"water": {"frequency": 4, "size": 0.25}, "nauvis_cliff": {"frequency": 0.25, "size": 0.75}},
		"starting_area": 3, "height": 128}, "map": {}},
	"lakes": {"name": "Lakes", "gen": {
		"property_expression_names": {"elevation": "elevation_lakes", "moisture": "moisture_basic", "aux": "aux_basic",
			"cliffiness": "cliffiness_basic", "cliff_elevation": "cliff_elevation_from_elevation", "trees_forest_path_cutout": 1},
		"cliff_settings": {"cliff_smoothing": 1}, "autoplace_controls": {"trees": {"frequency": 1, "size": 0.5}}}, "map": {}},
	"island": {"name": "Island", "gen": {
		"property_expression_names": {"elevation": "elevation_island", "moisture": "moisture_basic", "aux": "aux_basic",
			"cliffiness": "cliffiness_basic", "cliff_elevation": "cliff_elevation_from_elevation", "trees_forest_path_cutout": 1},
		"cliff_settings": {"cliff_smoothing": 1}, "autoplace_controls": {"trees": {"frequency": 1, "size": 0.5}}}, "map": {}},
}


## The settings of a preset over the install's defaults. `exe` finds the example files.
static func preset_settings(preset: String, exe := "") -> Dictionary:
	var base := defaults(exe)
	var p: Dictionary = PRESETS.get(preset, PRESETS["default"])
	return {"gen": merged(base["gen"], p["gen"]), "map": merged(base["map"], p["map"]), "preset": preset if PRESETS.has(preset) else "default"}


## Settings stored by the map generator (JSON, Settings [new_game] settings) over the current
## defaults; controls of mods that are off now are dropped. The default preset when there are none.
static func from_stored(json: String, exe := "") -> Dictionary:
	var last = JSON.parse_string(json) if json != "" else null
	var base := preset_settings(str(last.get("preset", "default")) if last is Dictionary else "default", exe)
	if not last is Dictionary:
		return base
	var known: Dictionary = base["gen"]["autoplace_controls"]
	var stored: Dictionary = last.get("gen", {}).get("autoplace_controls", {})
	for key in stored.keys():
		if not known.has(key):
			stored.erase(key)
	return {"gen": merged(base["gen"], last.get("gen", {})), "map": merged(base["map"], last.get("map", {})), "preset": base["preset"]}


## The example files with every control of the enabled mods at 100%.
static func defaults(exe := "") -> Dictionary:
	if exe == "":
		exe = Paths.factorio_exe()
	var gen := _example(exe, "map-gen-settings.example.json")
	var map := _example(exe, "map-settings.example.json")
	gen.erase("seed")  # --map-gen-seed, or random
	var controls := {}
	for c in controls_for(enabled_mods()):
		controls[c[0]] = {"frequency": 1, "size": 1, "richness": 1} if c[4] else {"frequency": 1, "size": 1}
	gen["autoplace_controls"] = controls
	if not gen.has("property_expression_names"):
		gen["property_expression_names"] = {}
	for key in ["control:moisture:frequency", "control:moisture:bias", "control:aux:frequency", "control:aux:bias"]:
		if not gen["property_expression_names"].has(key):
			gen["property_expression_names"][key] = "0" if key.ends_with("bias") else "1"
	gen["no_enemies_mode"] = false
	if not map.has("asteroids"):
		map["asteroids"] = {"spawning_rate": 1}
	return {"gen": gen, "map": map}


## The controls of the base game, and Space Age's planets when it is on.
static func controls_for(mods: Dictionary) -> Array:
	var space_age := bool(mods.get("space-age", true))
	return CONTROLS.filter(func(c: Array) -> bool: return c[3] == "nauvis" or space_age)


## The server's mods/mod-list.json as name -> enabled. Factorio turns on the DLC it finds, so a
## missing list means base and the DLC are on.
static func enabled_mods() -> Dictionary:
	var out := {"base": true, "space-age": true, "quality": true, "elevated-rails": true}
	var file := Paths.server_data_dir().path_join("mods/mod-list.json")
	if not FileAccess.file_exists(file):
		return out
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
	if parsed is Dictionary:
		for m in parsed.get("mods", []):
			if m is Dictionary:
				out[str(m.get("name", ""))] = bool(m.get("enabled", true))
	return out


static func get_value(settings: Dictionary, path: String, fallback: Variant = null) -> Variant:
	var at: Variant = settings
	for part in path.split("/"):
		if not at is Dictionary or not (at as Dictionary).has(part):
			return fallback
		at = at[part]
	return at


static func set_value(settings: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split("/")
	var at: Dictionary = settings
	for i in parts.size() - 1:
		if not at.get(parts[i]) is Dictionary:
			at[parts[i]] = {}
		at = at[parts[i]]
	at[parts[-1]] = value


## How far the settings are from their preset's: the number of values changed (Factorio's
## "[modified]" and "Reset N options to preset defaults").
static func changed_count(settings: Dictionary, exe := "") -> int:
	var preset := preset_settings(str(settings.get("preset", "default")), exe)
	return _diff(settings.get("gen", {}), preset["gen"]) + _diff(settings.get("map", {}), preset["map"])


static func _diff(a: Variant, b: Variant) -> int:
	if a is Dictionary and b is Dictionary:
		var n := 0
		for key in a:
			n += _diff(a[key], b.get(key))
		for key in b:
			if not (a as Dictionary).has(key):
				n += 1
		return n
	if (a is float or a is int) and (b is float or b is int):
		return 0 if absf(float(a) - float(b)) < 1e-9 else 1
	return 0 if a == b else 1


static func _example(exe: String, file: String) -> Dictionary:
	var path := Paths.read_data_dir(exe).path_join(file) if exe != "" else ""
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" and FileAccess.file_exists(path) else null
	return strip_comments(parsed) if parsed is Dictionary else {}


## The example files explain themselves in "_comment" keys; leave those out.
static func strip_comments(d: Dictionary) -> Dictionary:
	var out := {}
	for key in d:
		if str(key).begins_with("_"):
			continue
		out[key] = strip_comments(d[key]) if d[key] is Dictionary else d[key]
	return out


static func merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in over:
		if over[key] is Dictionary and out.get(key) is Dictionary:
			out[key] = merged(out[key], over[key])
		else:
			out[key] = over[key]
	return out


## "100%" for a factor; "None" for 0.
static func percent(v: float) -> String:
	return "None" if v <= 0.0 else "%d%%" % roundi(v * 100.0)
