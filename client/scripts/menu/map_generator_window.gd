extends PanelContainer
## Factorio's map generator window (New game): preset, seed and name at the top; tabs Resources,
## Terrain, Enemy and Advanced with every option of Factorio's ([gui-map-generator] in
## core.cfg); a preview on the right made by Factorio itself (--generate-map-preview), for the
## planet picked under it; Back and Play at the bottom. What it sets goes to `factorio --create`
## as --map-gen-settings / --map-settings (map_gen.gd), so it really shapes the map. The last
## choices are remembered (Settings [new_game]).
##
## Controls are named by their settings path with "-" for "/" (e.g.
## "gen-autoplace_controls-iron-ore-richness") for tests.

signal play(save_name: String, settings: Dictionary, seed_text: String, exchange: String)
signal closed

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const MapGen := preload("res://scripts/menu/map_gen.gd")
const Saves := preload("res://scripts/menu/saves.gd")
const Paths := preload("res://scripts/menu/paths.gd")
const Sfx := preload("res://scripts/fx/sfx.gd")

const TABS := ["Resources", "Terrain", "Enemy", "Advanced"]

## server_launcher.gd, for the preview.
var launcher
var settings := {}
var seed_text := ""
var exchange := ""

var _name_edit: LineEdit
var _seed_edit: LineEdit
var _preset: OptionButton
var _modified: Label
var _reset: Button
var _tab_buttons: Array[Button] = []
var _pane: VBoxContainer
var _tab := 0
var _preview := TextureRect.new()
var _preview_note: Label
var _planet: OptionButton
var _previewing := false


func _ready() -> void:
	theme_type_variation = "FFrame"
	_load_last()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Map generator", true)
	box.add_child(bar)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(func() -> void: closed.emit())

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", Kit.px(10))
	box.add_child(top)
	top.add_child(Kit.label("Name"))
	var n := 1
	while FileAccess.file_exists(Paths.saves_dir().path_join("world-%d.zip" % n)):
		n += 1
	_name_edit = MenuKit.textbox("world-%d" % n)
	_name_edit.name = "Name"
	top.add_child(_name_edit)
	top.add_child(Kit.label("Preset"))
	var presets: Array = []
	for key in MapGen.PRESETS:
		presets.append([MapGen.PRESETS[key]["name"], key])
	_preset = MenuKit.dropdown(presets, settings.get("preset", "default"))
	_preset.name = "Preset"
	_preset.item_selected.connect(func(i: int) -> void:
		Sfx.play_ui("gui-click")
		settings = MapGen.preset_settings(str(_preset.get_item_metadata(i)))
		_changed(true))
	top.add_child(_preset)
	_modified = Kit.label("[modified]")
	_modified.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	top.add_child(_modified)
	_reset = MenuKit.button("Reset")
	_reset.name = "ResetPreset"
	_reset.pressed.connect(func() -> void:
		Sfx.play_ui("gui-click")
		settings = MapGen.preset_settings(str(settings.get("preset", "default")))
		_changed(true))
	top.add_child(_reset)
	top.add_child(Kit.label("Seed"))
	_seed_edit = MenuKit.textbox(seed_text, "Random")
	_seed_edit.name = "Seed"
	_seed_edit.custom_minimum_size.x = Kit.px(140)
	_seed_edit.text_changed.connect(func(t: String) -> void: seed_text = t)
	top.add_child(_seed_edit)
	var dice := MenuKit.button("Random seed")
	dice.pressed.connect(func() -> void:
		Sfx.play_ui("gui-click")
		_seed_edit.text = str(randi())
		seed_text = _seed_edit.text)
	top.add_child(dice)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", Kit.px(12))
	box.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	columns.add_child(left)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	left.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.name = "Tab" + TABS[i]
		b.theme_type_variation = "FTab"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(110, 32)
		b.add_theme_font_override("font", Kit.font("bold"))
		var index := i
		b.pressed.connect(func() -> void:
			Sfx.play_ui("gui-tab")
			_open_tab(index))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var pane := Kit.panel("FShallowFrame")
	pane.custom_minimum_size = Kit.pxv(720, 470)
	left.add_child(pane)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pane.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(10))
	scroll.add_child(pad)
	_pane = VBoxContainer.new()
	_pane.add_theme_constant_override("separation", Kit.px(8))
	pad.add_child(_pane)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", Kit.px(6))
	columns.add_child(right)
	right.add_child(Kit.label("Preview", "FHeading"))
	var frame := Kit.panel("FDeepFrame")
	frame.custom_minimum_size = Kit.pxv(380, 380)
	right.add_child(frame)
	_preview.name = "Preview"
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_preview.custom_minimum_size = Kit.pxv(372, 372)
	frame.add_child(_preview)
	_preview_note = MenuKit.paragraph("Spoiler alert: don't show the preview if you want to explore the map on your own.", 380)
	_preview_note.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	right.add_child(_preview_note)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", Kit.px(8))
	right.add_child(prow)
	var planets: Array = []
	var mods := MapGen.enabled_mods()
	for p in MapGen.PLANETS:
		if p == "nauvis" or bool(mods.get("space-age", true)):
			planets.append([p.capitalize(), p])
	_planet = MenuKit.dropdown(planets, "nauvis")
	_planet.name = "PreviewPlanet"
	prow.add_child(_planet)
	var show := MenuKit.button("Preview", "FGreenButton")
	show.name = "ShowPreview"
	show.pressed.connect(func() -> void:
		Sfx.play_ui("gui-click")
		make_preview())
	prow.add_child(show)

	var row: Array = MenuKit.dialog_buttons("Back", "Play")
	box.add_child(row[0])
	(row[1] as Button).pressed.connect(func() -> void:
		Sfx.play_ui("gui-back")
		closed.emit())
	(row[2] as Button).name = "Play"
	(row[2] as Button).pressed.connect(func() -> void:
		Sfx.play_ui("gui-green-confirm")
		_play())
	_open_tab(0)
	_changed(false)
	_name_edit.grab_focus.call_deferred()


## Factorio remembers the last settings used; a stored set from another install or mod list is
## rebuilt over the current defaults.
func _load_last() -> void:
	settings = MapGen.from_stored(str(Settings.get_value("new_game", "settings")) if Settings.has_value("new_game", "settings") else "")
	seed_text = str(Settings.get_value("new_game", "seed")) if Settings.has_value("new_game", "seed") else ""


func _play() -> void:
	var save_name := Saves.clean_name(_name_edit.text)
	Settings.set_value("new_game", "settings", JSON.stringify(settings))
	Settings.set_value("new_game", "seed", seed_text)
	play.emit(save_name, settings, seed_text, exchange)


## Asks Factorio for a preview of the current settings and shows it.
func make_preview() -> void:
	if _previewing or launcher == null:
		return
	_previewing = true
	_preview_note.text = "Factorio is generating the preview…"
	var image: Image = await launcher.generate_preview(settings, seed_text, exchange, str(_planet.get_selected_metadata()), 512)
	_previewing = false
	if not is_inside_tree():
		return
	if image == null:
		_preview_note.text = "Error generating preview: " + str(launcher.error).get_slice("\n", 0)
		return
	_preview.texture = ImageTexture.create_from_image(image)
	_preview_note.text = "%s, %s seed." % [str(_planet.get_selected_metadata()).capitalize(), seed_text if seed_text != "" else "a random"]


func _changed(rebuild: bool) -> void:
	var n := MapGen.changed_count(settings)
	_modified.visible = n > 0
	_reset.disabled = n == 0
	_reset.tooltip_text = "Reset %d option%s to preset default%s" % [n, "" if n == 1 else "s", "" if n == 1 else "s"] if n > 0 else "All options have preset values."
	for i in _preset.item_count:
		if str(_preset.get_item_metadata(i)) == str(settings.get("preset", "default")):
			_preset.select(i)
	if rebuild:
		_open_tab(_tab)


func _open_tab(index: int) -> void:
	_tab = index
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	for c in _pane.get_children():
		_pane.remove_child(c)
		c.queue_free()
	match TABS[index]:
		"Resources":
			_resources()
		"Terrain":
			_terrain()
		"Enemy":
			_enemy()
		"Advanced":
			_advanced()


func open_tab(tab_name: String) -> void:
	var i := TABS.find(tab_name)
	if i >= 0:
		_open_tab(i)


# --- tabs ------------------------------------------------------------------------------------

func _resources() -> void:
	var grid := _table(["Resource", "Appears on", "Frequency", "Size", "Richness"])
	for c in MapGen.controls_for(MapGen.enabled_mods()):
		if c[2] != "resource":
			continue
		_control_row(grid, c, ["frequency", "size", "richness"])


func _terrain() -> void:
	var grid := _grid()
	var type := MenuKit.dropdown(MapGen.MAP_TYPES, MapGen.get_value(settings, "gen/property_expression_names/elevation", ""))
	type.name = "gen-property_expression_names-elevation"
	type.item_selected.connect(func(i: int) -> void:
		var v := str(type.get_item_metadata(i))
		var names: Dictionary = settings["gen"]["property_expression_names"]
		if v == "":
			names.erase("elevation")
		else:
			names["elevation"] = v
		_changed(false))
	_row(grid, "Map type", type, "Nauvis")
	_step_slider(grid, "Starting area size", "gen/starting_area", false, "The size of the area without enemy bases around the player.")
	_heading("Terrain generators")
	var table := _table(["", "Appears on", "Scale", "Coverage", ""])
	for c in MapGen.controls_for(MapGen.enabled_mods()):
		if c[2] == "terrain":
			_control_row(table, c, ["frequency", "size"], true)
	_heading("Cliffs")
	table = _table(["", "Appears on", "Frequency", "Continuity", ""])
	for c in MapGen.controls_for(MapGen.enabled_mods()):
		if c[2] == "cliff":
			_control_row(table, c, ["frequency", "size"])
	_heading("Climate (Nauvis)")
	grid = _grid()
	_expression(grid, "Moisture scale", "control:moisture:frequency", true, "Controls the distribution of grass versus desert.")
	_expression(grid, "Moisture bias", "control:moisture:bias", false, "A higher bias generates more grass.")
	_expression(grid, "Terrain type scale", "control:aux:frequency", true, "Controls the distribution of red desert versus sand.")
	_expression(grid, "Terrain type bias", "control:aux:bias", false, "A higher bias generates more red desert.")


func _enemy() -> void:
	var table := _table(["", "Appears on", "Frequency", "Size", ""])
	for c in MapGen.controls_for(MapGen.enabled_mods()):
		if c[2] == "enemy":
			_control_row(table, c, ["frequency", "size"])
	var grid := _grid()
	_check(grid, "Peaceful mode", "gen/peaceful_mode", "Enemies don't attack or expand; they still defend themselves.")
	_check(grid, "No enemies", "gen/no_enemies_mode", "Enemy units don't spawn; inactive spawners still appear.")
	_heading("Enemy expansion")
	grid = _grid()
	_check(grid, "Enabled", "map/enemy_expansion/enabled")
	_spin(grid, "Minimum expansion distance", "map/enemy_expansion/min_expansion_distance", 1, 20, 1, 1.0, "chunks")
	_spin(grid, "Maximum expansion distance", "map/enemy_expansion/max_expansion_distance", 2, 20, 1, 1.0, "chunks")
	_spin(grid, "Evolution group size factor", "map/enemy_expansion/evolution_group_size_factor", 1, 20, 0.5, 1.0, "")
	_spin(grid, "Minimum cooldown", "map/enemy_expansion/min_expansion_cooldown", 1, 60, 1, 1.0 / 3600.0, "min")
	_spin(grid, "Maximum cooldown", "map/enemy_expansion/max_expansion_cooldown", 5, 180, 1, 1.0 / 3600.0, "min")
	_heading("Evolution")
	grid = _grid()
	_check(grid, "Enabled", "map/enemy_evolution/enabled")
	_spin(grid, "Time factor", "map/enemy_evolution/time_factor", 0, 1000, 1, 1e7, "× 10⁻⁷")
	_spin(grid, "Destroy factor", "map/enemy_evolution/destroy_factor", 0, 1000, 1, 1e5, "× 10⁻⁵")
	_spin(grid, "Pollution factor", "map/enemy_evolution/pollution_factor", 0, 1000, 1, 1e7, "× 10⁻⁷")


func _advanced() -> void:
	_heading("Map")
	var grid := _grid()
	_spin(grid, "Width", "gen/width", 0, 2000000, 32, 1.0, "tiles, 0: infinite")
	_spin(grid, "Height", "gen/height", 0, 2000000, 32, 1.0, "tiles, 0: infinite")
	_heading("Pollution")
	grid = _grid()
	_check(grid, "Enabled", "map/pollution/enabled")
	_spin(grid, "Diffusion ratio", "map/pollution/diffusion_ratio", 0, 25, 0.1, 100.0, "%")
	_spin(grid, "Absorption modifier", "map/pollution/ageing", 10, 400, 1, 100.0, "%")
	_spin(grid, "Attack cost modifier", "map/pollution/enemy_attack_pollution_consumption_modifier", 10, 400, 1, 100.0, "%")
	_spin(grid, "Minimum to damage trees", "map/pollution/min_pollution_to_damage_trees", 0, 9999, 1, 1.0, "")
	_spin(grid, "Absorbed per damaged tree", "map/pollution/pollution_restored_per_tree_damage", 0, 9999, 1, 1.0, "")
	_heading("Recipes, technology, spoiling, asteroids")
	grid = _grid()
	_spin(grid, "Technology price multiplier", "map/difficulty_settings/technology_price_multiplier", 0.001, 1000, 0.5, 1.0, "×")
	var spoil := SpinBox.new()
	spoil.name = "map-difficulty_settings-spoil_time_modifier"
	spoil.min_value = 0.01
	spoil.max_value = 100
	spoil.step = 0.01
	spoil.value = 1.0 / maxf(0.01, float(MapGen.get_value(settings, "map/difficulty_settings/spoil_time_modifier", 1.0)))
	spoil.custom_minimum_size = Kit.pxv(140, 28)
	spoil.value_changed.connect(func(v: float) -> void:
		MapGen.set_value(settings, "map/difficulty_settings/spoil_time_modifier", 1.0 / maxf(0.01, v))
		_changed(false))
	_row(grid, "Spoiling rate", spoil, "× (Space Age)")
	_spin(grid, "Asteroid spawning rate", "map/asteroids/spawning_rate", 0, 10, 0.1, 1.0, "× (Space Age)")
	_heading("Map exchange string")
	var ex := TextEdit.new()
	ex.name = "ExchangeString"
	ex.text = exchange
	ex.placeholder_text = ">>>eNp... (from Factorio's map generator)"
	ex.custom_minimum_size = Kit.pxv(680, 80)
	ex.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ex.text_changed.connect(func() -> void: exchange = ex.text.strip_edges())
	_pane.add_child(ex)
	_note("An exchange string from Factorio's map generator is used instead of everything above (the seed above still wins). Factorio can't export one here: that needs its own window.")


# --- rows ------------------------------------------------------------------------------------

func _heading(text: String) -> void:
	_pane.add_child(Kit.label(text, "FHeading"))


func _note(text: String) -> void:
	var n := MenuKit.paragraph(text, 680)
	n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	_pane.add_child(n)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Kit.px(16))
	grid.add_theme_constant_override("v_separation", Kit.px(6))
	_pane.add_child(grid)
	return grid


func _table(headers: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = headers.size()
	grid.add_theme_constant_override("h_separation", Kit.px(10))
	grid.add_theme_constant_override("v_separation", Kit.px(4))
	_pane.add_child(grid)
	for h in headers:
		grid.add_child(Kit.label(h, "FHeading") if h != "" else Control.new())
	return grid


func _row(grid: GridContainer, text: String, control: Control, note := "") -> void:
	var l := Kit.label(text)
	l.custom_minimum_size.x = Kit.px(220)
	grid.add_child(l)
	if note == "":
		grid.add_child(control)
		return
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", Kit.px(8))
	holder.add_child(control)
	var n := Kit.label(note)
	n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	holder.add_child(n)
	grid.add_child(holder)


## One autoplace control: its name, its planet, and a slider per field ("" columns stay empty).
## `inverse`: the slider shows the scale (1 / frequency), as Factorio's terrain sliders do.
func _control_row(grid: GridContainer, c: Array, fields: Array, inverse := false) -> void:
	var label := Kit.label(c[1])
	label.custom_minimum_size.x = Kit.px(150)
	grid.add_child(label)
	var planet := Kit.label(str(c[3]).capitalize())
	planet.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	grid.add_child(planet)
	for i in 3:
		if i >= fields.size():
			grid.add_child(Control.new())
			continue
		var path := "gen/autoplace_controls/%s/%s" % [c[0], fields[i]]
		grid.add_child(_step_control(path, inverse and fields[i] == "frequency", fields[i] == "size"))


func _step_slider(grid: GridContainer, text: String, path: String, inverse: bool, note := "") -> void:
	var holder := _step_control(path, inverse, false)
	holder.tooltip_text = note
	_row(grid, text, holder)


## A slider over Factorio's steps (17% to 600%, "None" at the left where it makes sense).
func _step_control(path: String, inverse: bool, allow_none: bool) -> HBoxContainer:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", Kit.px(4))
	var raw := float(MapGen.get_value(settings, path, 1.0))
	var shown := 1.0 / raw if inverse and raw > 0.0 else raw
	var first := 0 if allow_none else 1
	var s := MenuKit.slider(first, MapGen.STEPS.size() - 1, 1, _nearest_step(shown))
	s.name = path.replace("/", "-")
	s.custom_minimum_size = Kit.pxv(100, 20)
	var value := Kit.label(MapGen.percent(shown))
	value.custom_minimum_size.x = Kit.px(48)
	s.value_changed.connect(func(v: float) -> void:
		var step: float = MapGen.STEPS[int(v)]
		value.text = MapGen.percent(step)
		MapGen.set_value(settings, path, (1.0 / step if inverse and step > 0.0 else step))
		_changed(false))
	holder.add_child(s)
	holder.add_child(value)
	return holder


static func _nearest_step(v: float) -> int:
	var best := 6
	for i in MapGen.STEPS.size():
		if absf(MapGen.STEPS[i] - v) < absf(MapGen.STEPS[best] - v):
			best = i
	return best


## Moisture and terrain type: scale (1 / the expression's frequency) and bias, kept as strings
## as Factorio's property_expression_names are.
func _expression(grid: GridContainer, text: String, key: String, scale: bool, note: String) -> void:
	var path := "gen/property_expression_names/" + key
	var raw := float(str(MapGen.get_value(settings, path, "1" if scale else "0")))
	var spin := SpinBox.new()
	spin.name = path.replace("/", "-").replace(":", "_")
	spin.min_value = 0.17 if scale else -0.5
	spin.max_value = 6.0 if scale else 0.5
	spin.step = 0.01
	spin.value = (1.0 / raw if raw > 0.0 else 1.0) if scale else raw
	spin.custom_minimum_size = Kit.pxv(140, 28)
	spin.tooltip_text = note
	spin.value_changed.connect(func(v: float) -> void:
		MapGen.set_value(settings, path, str(snappedf(1.0 / v, 0.0001) if scale else v))
		_changed(false))
	_row(grid, text, spin, "×" if scale else "")


func _check(grid: GridContainer, text: String, path: String, note := "") -> void:
	var c := MenuKit.checkbox("", bool(MapGen.get_value(settings, path, false)))
	c.name = path.replace("/", "-")
	c.tooltip_text = note
	c.toggled.connect(func(on: bool) -> void:
		Sfx.play_ui("gui-checkbox-click")
		MapGen.set_value(settings, path, on)
		_changed(false))
	_row(grid, text, c, note)


## A number box showing the setting times `scale` (e.g. ticks as minutes, factors as × 10⁻⁷).
func _spin(grid: GridContainer, text: String, path: String, from: float, to: float, step: float, scale: float, unit: String) -> void:
	var spin := SpinBox.new()
	spin.name = path.replace("/", "-")
	spin.min_value = from
	spin.max_value = to
	spin.step = step
	spin.value = float(MapGen.get_value(settings, path, 0.0)) * scale
	spin.custom_minimum_size = Kit.pxv(140, 28)
	var is_int := scale == 1.0 and step >= 1.0
	spin.value_changed.connect(func(v: float) -> void:
		var value: Variant = v / scale
		if path.contains("cooldown"):
			value = roundi(v / scale)  # minutes to ticks
		elif is_int:
			value = int(v)
		MapGen.set_value(settings, path, value)
		_changed(false))
	_row(grid, text, spin, unit)
