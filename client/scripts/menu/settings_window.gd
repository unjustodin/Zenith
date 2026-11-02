extends PanelContainer
## Factorio-style settings window: the tabs of Factorio's Settings menu (Graphics, Sound,
## Controls, Interface, Other, Mod settings) and ours (Camera, Factorio), rows of "name: control"
## grouped under headings in a light pane, Back at the bottom. Every row is wired to what it
## changes: settings.gd saves and tells its listeners, so most apply at once; the few that need a
## restart or a new server say so. Each control is named "<section>-<key>" for tests (map switches "map-show_tags", bindings "controls-<action>-<slot>").

signal closed
## Confirm in a single page (page_mode): the settings window and the list it came from close.
signal confirmed

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const Paths := preload("res://scripts/menu/paths.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")
const Sfx := preload("res://scripts/fx/sfx.gd")
const UiSettings := preload("res://scripts/ui/ui_settings.gd")
const ColorFilter := preload("res://scripts/menu/color_filter.gd")
const ControlsInfo := preload("res://scripts/menu/controls_info.gd")

const TABS := ["Graphics", "Sound", "Controls", "Interface", "Other", "Mod settings", "Camera", "Factorio"]
## Factorio's sound sliders ([gui-sound-settings]) the client has a bus for, in its order (Master,
## Music, Game effects, GUI effects, Walking, Environment, Ambient), then the client's own three.
## Factorio's Alerts, Wind and Simulations have no bus here (the client's alerts are silent, wind is
## in Ambient, there are no tips simulations).
const SOUND := [
	["Master", "master"], ["Music", "music"], ["Game effects", "effects"], ["GUI effects", "ui"], ["Walking", "walking"],
	["Environment", "environment", "Sounds of machines and vehicles."], ["Ambient", "ambient", "Wind and the planet's background sounds."],
	["Weapons", "weapons"], ["Explosions", "explosions"], ["Enemies", "enemies"],
]
## The bridge mod's runtime-global settings (mod/factorio-3d-bridge/settings.lua):
## [name, label, type, default, min, max].
const MOD_SETTINGS := [
	["f3d-surface", "Surface to stream", "string", "nauvis"],
	["f3d-chunks-per-tick", "Chunk snapshots per tick", "int", 1, 1, 16],
	["f3d-bytes-per-tick", "Bytes sent per tick", "int", 32768, 4096, 1048576],
	["f3d-max-focus-radius", "Max live-update radius", "int", 192, 16, 256],
	["f3d-mover-interval", "Moving entity update interval (ticks)", "int", 2, 1, 30],
	["f3d-detail-radius", "Detail radius (belt items, hands)", "int", 24, 0, 64],
	["f3d-detail-interval", "Detail update interval (ticks)", "int", 6, 1, 60],
	["f3d-starter-kit", "Starter kit for the bridge's character", "bool", true],
	["f3d-player", "Player to play as", "string", ""],
]

var in_game := false
var start_tab := ""
## Factorio's way: one page at a time ("Graphics settings", ...), opened from the Settings list
## (front_end.gd), without the tab row, with Back (to the list) and Confirm (close).
var page_mode := false
## The launched server's RCON (rcon.gd) while in a game started from the menu, for Mod settings.
var rcon = null

var _tab_buttons: Array[Button] = []
var _pane: VBoxContainer
var _tab := 0
var _capturing := ""  # "<action>/<slot>" waiting for a key
var _preset: OptionButton  # Graphics > Preset, following the settings it covers
var _scroll: ScrollContainer


func _ready() -> void:
	theme_type_variation = "FFrame"
	Settings.listen(_on_setting)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Settings", not page_mode)
	box.add_child(bar)
	if not page_mode:
		var close: Button = bar.get_child(bar.get_child_count() - 1)
		close.pressed.connect(_close)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	box.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.name = "Tab" + TABS[i].replace(" ", "")
		b.theme_type_variation = "FTab"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Kit.pxv(92, 32)
		b.add_theme_font_override("font", Kit.font("bold"))
		var index := i
		b.pressed.connect(func() -> void:
			Sfx.play_ui("gui-tab")
			_open_tab(index))
		tabs.add_child(b)
		_tab_buttons.append(b)
	tabs.visible = not page_mode

	var pane := Kit.panel("FShallowFrame")
	pane.custom_minimum_size = Kit.pxv(780, 500)
	box.add_child(pane)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pane.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(12))
	_scroll.add_child(pad)
	_pane = VBoxContainer.new()
	_pane.name = "Pane"
	_pane.add_theme_constant_override("separation", Kit.px(10))
	pad.add_child(_pane)

	var row: Array = MenuKit.dialog_buttons("Back", "Confirm" if page_mode else "")
	box.add_child(row[0])
	(row[1] as Button).pressed.connect(func() -> void:
		Sfx.play_ui("gui-back")
		_close())
	if page_mode:
		(row[2] as Button).name = "Confirm"
		(row[2] as Button).pressed.connect(func() -> void:
			Sfx.play_ui("gui-green-confirm")
			_capturing = ""
			confirmed.emit())
	var wanted := start_tab.replace("_", " ").to_lower()
	var start := 0
	for i in TABS.size():
		if TABS[i].to_lower() == wanted or TABS[i].to_lower().replace(" ", "") == wanted.replace(" ", ""):
			start = i
	_open_tab(start)
	if page_mode:
		(bar.get_child(0) as Label).text = page_title(TABS[start])


## Factorio's page titles: "Graphics settings", "Sound settings", "Mod settings".
static func page_title(tab: String) -> String:
	return tab if tab == "Mod settings" else tab + " settings"


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return  # a modifier on its own: wait for the key it goes with
	var target := _capturing
	_capturing = ""
	if key.physical_keycode != KEY_ESCAPE:
		capture(target, Settings.event_code(key))
	_open_tab(_tab)


## Binds "<action>/<slot>" to a key code with modifiers (what a key press while capturing does).
func capture(target: String, code: int) -> void:
	Settings.bind_slot(target.get_slice("/", 0), int(target.get_slice("/", 1)), code)
	Sfx.play_ui("gui-click")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	_capturing = ""
	closed.emit()


func current_tab() -> String:
	return TABS[_tab]


func open_tab(tab_name: String) -> void:
	var i := TABS.find(tab_name)
	if i >= 0:
		_open_tab(i)


func _open_tab(index: int) -> void:
	_tab = index
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	for c in _pane.get_children():
		_pane.remove_child(c)
		c.queue_free()
	match TABS[index]:
		"Graphics":
			_graphics()
		"Sound":
			_sound()
		"Controls":
			_controls()
		"Interface":
			_interface()
		"Other":
			_other()
		"Mod settings":
			_mod_settings()
		"Camera":
			_camera()
		"Factorio":
			_factorio()


func _exit_tree() -> void:
	Settings.unlisten(_on_setting)


## The preset shows what the settings match as they change (Custom once one is set by hand).
func _on_setting(section: String, _key: String) -> void:
	if section != "graphics" or not is_instance_valid(_preset):
		return
	var now := Settings.preset_now()
	for i in _preset.item_count:
		if str(_preset.get_item_metadata(i)) == now:
			_preset.select(i)


# --- tabs ------------------------------------------------------------------------------------

## What the Recommended button last chose (its text), kept across the tab being rebuilt.
var _recommended := ""


## Recommended (Graphics): the preset for this PC's hardware, and in a game what it measured over
## RECOMMEND_SECONDS (the slowest tenth of frames, the game's ticks a second); see
## Settings.recommended_preset.
const RECOMMEND_SECONDS := 6.0


func _recommend(button: Button) -> void:
	Sfx.play_ui("gui-click")
	var fps := 0.0
	var ups := 0.0
	var frame_ms := 0.0
	var gpu_ms := 0.0
	if Bridge.world_ready:
		button.disabled = true
		button.text = "Measuring..."
		var frames: Array[float] = []
		var started := Time.get_ticks_usec()
		var tick := Bridge.server_tick
		var last := started
		# The GPU's share of the frame too: merged materials help only where the CPU holds it up.
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		var gpu: Array[float] = []
		while Time.get_ticks_usec() - started < RECOMMEND_SECONDS * 1e6:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - last) / 1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			last = now
		RenderingServer.viewport_set_measure_render_time(vp, false)
		ups = (Bridge.server_tick - tick) / ((last - started) / 1e6)
		frames.sort()
		gpu.sort()
		frame_ms = frames[frames.size() / 2] if not frames.is_empty() else 0.0
		gpu_ms = gpu[gpu.size() / 2] if not gpu.is_empty() else 0.0
		fps = 1000.0 / maxf(frames[int(frames.size() * 0.9)] if not frames.is_empty() else 16.7, 0.1)
		if not is_instance_valid(button):
			return
		button.disabled = false
	var preset := Settings.recommended_preset(OS.get_processor_count(), RenderingServer.get_video_adapter_name(), fps, ups, Settings.preset_now())
	Settings.set_value("graphics", "hold_ups", true, false)
	Settings.set_value("graphics", "belt_smooth", true, false)
	# Not part of any preset: Low to Ultra leave it as the player set it.
	Settings.set_value("graphics", "merged_materials",
		Settings.recommended_merged_materials(RenderingServer.get_video_adapter_name(), frame_ms, gpu_ms), false)
	Settings.apply_preset(preset)
	_recommended = "Recommended: %s" % preset.capitalize()
	if fps > 0.0:
		_recommended += " (measured %d fps, %d UPS)" % [roundi(fps), roundi(ups)]
	button.text = _recommended
	_open_tab.call_deferred(_tab)


const PRESET_ITEMS := [["Low", "low"], ["Medium", "medium"], ["High", "high"], ["Ultra", "ultra"], ["Custom", "custom"]]


func _graphics() -> void:
	_heading("General")
	var grid := _grid()
	# The preset sets shadows, ambient occlusion, level of detail and the distances below together.
	_preset = MenuKit.dropdown(PRESET_ITEMS, Settings.preset_now())
	_preset.name = "graphics-preset"
	_preset.item_selected.connect(func(i: int) -> void:
		Sfx.play_ui("gui-click")
		var preset := str(_preset.get_item_metadata(i))
		if preset == "custom":
			_on_setting("graphics", "")  # nothing to set: back to what the settings match
		else:
			Settings.apply_preset(preset)
			_open_tab.call_deferred(_tab))
	_row(grid, "Preset", _preset, "shadows, ambient occlusion, level of detail, view and decorative distances, clouds")
	var recommend := MenuKit.button(_recommended if _recommended != "" else "Recommended")
	recommend.name = "graphics-recommended"
	recommend.pressed.connect(_recommend.bind(recommend))
	_row(grid, "For this PC", recommend,
		"the preset this PC holds at a steady 60 UPS and 60 FPS, with Hold the game at 60 UPS and smooth belt items on; in a game it measures for a few seconds first")
	_dropdown(grid, "Full screen", "graphics", "window_mode", [["Windowed", "windowed"], ["Borderless full screen", "borderless"], ["Exclusive full screen", "fullscreen"]], "", true)
	var sizes: Array = [["Default (1600 × 900)", ""]]
	var screen := DisplayServer.screen_get_size()
	var listed: Array = Settings.RESOLUTIONS.duplicate()
	var native := "%dx%d" % [screen.x, screen.y]
	if not listed.has(native):
		listed.append(native)
	for r in listed:
		var w := int(str(r).get_slice("x", 0))
		var h := int(str(r).get_slice("x", 1))
		if w <= screen.x and h <= screen.y:
			sizes.append(["%d × %d" % [w, h], r])
	_dropdown(grid, "Resolution", "graphics", "resolution", sizes, "windowed mode", true)
	var screens: Array = [["Primary screen (%d)" % (DisplayServer.get_primary_screen() + 1), -1]]
	for i in DisplayServer.get_screen_count():
		var s := DisplayServer.screen_get_size(i)
		screens.append(["Screen %d (%d × %d)" % [i + 1, s.x, s.y], i])
	_dropdown(grid, "Preferred screen", "graphics", "screen", screens, "", true)
	_check(grid, "Minimize on focus loss", "graphics", "minimize_on_focus_loss", "full screen only")
	_check(grid, "Wait for VSync", "graphics", "vsync", "", true)
	_dropdown(grid, "FPS limit", "graphics", "fps_cap", [["Unlimited", 0], ["30", 30], ["60", 60], ["120", 120], ["144", 144], ["240", 240]], "", true)
	_slider(grid, "Game render scaling", "graphics", "render_scale", 0.5, 2.0, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100.0), true)
	_slider(grid, "View distance", "graphics", "view_radius", 2, 20, 1, func(v: float) -> String:
		var n := int(v) * 2 + 1
		return "%d chunks around (%d × %d)" % [int(v), n, n])
	_slider(grid, "Entity distance", "graphics", "entity_radius", 32, 256, 16, func(v: float) -> String:
		return "%d tiles" % int(v), false, false, "vehicles, trains, robots, enemies and working machines; the server caps it")
	_slider(grid, "Belt items in full", "graphics", "belt_near_distance", 8, 96, 8, func(v: float) -> String:
		return "%d tiles" % int(v), false, false, "every item on belts drawn this far round the character; further costs the server more on busy bases")
	_slider(grid, "Belt items far away", "graphics", "belt_far_distance", 0, 640, 32, func(v: float) -> String:
		return "Off" if int(v) == 0 else "%d tiles" % int(v), false, false, "past the nearby items, each belt lane shows an icon of what it carries")
	_check(grid, "Smooth belt items", "graphics", "belt_smooth",
		"on: items on belts update five times a second and follow curves; off: on a busy base the server reads them a little each tick and they update less often (lighter for the server, but items can cut across curves)")
	_check(grid, "Hold the game at 60 UPS", "graphics", "hold_ups",
		"while the game runs slow, the distances above, the minimap's refreshes and the frame rate go lower for a while (the F4 line says what); your settings stay as they are")
	_check(grid, "Show all smoke and particles", "graphics", "effects", "smoke, dust, flashes, explosions, corpses")
	_dropdown(grid, "Items on belts", "graphics", "item_models", [["3D models", true], ["Icons", false]], "also on the ground and in inserter hands; items without a model show their icon")
	_check(grid, "Clouds", "graphics", "clouds", "clouds in the sky, their shadows drifting over the ground, and haze")
	_check(grid, "Decoratives", "graphics", "decoratives", "grass, flowers and small rocks on the ground, from Factorio's pictures")
	_slider(grid, "Decorative density", "graphics", "decorative_density", 0.1, 1.0, 0.05, func(v: float) -> String: return "%d%%" % roundi(v * 100.0))
	_slider(grid, "Decorative distance", "graphics", "decorative_distance", 64, 320, 16, func(v: float) -> String:
		return "%d tiles" % int(v), false, false, "full detail to 80 tiles, then thinner further out")
	_check(grid, "Item icons on belts and the ground", "graphics", "item_icons", "Factorio's icons; off: coloured blocks. From the next connection")
	_dropdown(grid, "Model look", "graphics", "model_look", [["Factorio colours", "colours"],
		["Factorio sprite projected", "sprite"]], "each part in its colour from the game's sprite, or the sprite painted on; after a restart")

	_heading("Advanced")
	grid = _grid()
	_dropdown(grid, "Anti-aliasing", "graphics", "antialiasing", [["Off", "off"], ["FXAA", "fxaa"], ["TAA", "taa"], ["MSAA 2×", "msaa2"], ["MSAA 4×", "msaa4"], ["MSAA 8×", "msaa8"]], "", true)
	_dropdown(grid, "Shadows", "graphics", "shadows", [["Off", "off"], ["Low", "low"], ["Medium", "medium"], ["High", "high"], ["Ultra", "ultra"]],
		"how far shadows reach past what you see, how sharp and how many passes draw them")
	_dropdown(grid, "Level of detail", "graphics", "lod_quality", [["Low", "low"], ["Medium", "medium"], ["High", "high"]],
		"how soon models far away and their shadows are drawn simpler; those near you stay whole")
	_check(grid, "Merge far buildings", "graphics", "merge_far",
		"past about four chunks from the camera, each chunk's buildings are drawn as one simplified mesh, still and without their own shadows: far fewer draws at long view distances")
	_check(grid, "Merged materials (may help when CPU-bound)", "graphics", "merged_materials",
		"each model drawn as one surface with one material: fewer draws and less CPU for the renderer, a little more GPU time. After a restart")
	_check(grid, "Ambient occlusion (SSAO)", "graphics", "ssao")
	_check(grid, "Render on a separate thread", "graphics", "render_thread",
		"experimental (Godot): may help on some PCs, can hang on quitting; off is the stable choice. After a restart")

	_heading("Accessibility")
	grid = _grid()
	var pct := func(v: float) -> String: return "%d%%" % roundi(v * 100.0)
	_slider(grid, "Brightness", "graphics", "brightness", 0.5, 1.5, 0.05, pct, false, true)
	_slider(grid, "Contrast", "graphics", "contrast", 0.5, 1.5, 0.05, pct, false, true)
	_slider(grid, "Saturation", "graphics", "saturation", 0.0, 2.0, 0.05, pct, false, true)
	_dropdown(grid, "Color filter", "graphics", "color_filter", ColorFilter.FILTERS.map(func(f: Array) -> Array: return [f[1], f[0]]))


func _sound() -> void:
	_heading("Output")
	var grid := _grid()
	var devices: Array = []
	for d in AudioServer.get_output_device_list():
		devices.append(["Default device" if d == "Default" else d, d])
	_dropdown(grid, "Preferred output", "sound", "output_device", devices)
	_slider(grid, "Machine sounds at once", "sound", "max_voices", 4, 32, 1, func(v: float) -> String: return "%d" % int(v), false, false, "from the next game")
	_heading("Volume")
	grid = _grid()
	for entry in SOUND:
		var key: String = entry[1]
		var holder := _hbox()
		var on := MenuKit.checkbox("", bool(FxSettings.enabled.get(key, true)))
		on.name = "sound-%s_on" % key
		on.tooltip_text = "Enable/Disable (Mute) all sounds of this category."
		on.toggled.connect(func(v: bool) -> void:
			Sfx.play_ui("gui-checkbox-click")
			FxSettings.set_enabled(key, v))
		holder.add_child(on)
		var s := MenuKit.slider(0.0, 1.0, 0.01, float(FxSettings.volumes.get(key, 1.0)))
		s.name = "sound-" + key
		var value := Kit.label("%d%%" % roundi(s.value * 100.0))
		value.custom_minimum_size.x = Kit.px(48)
		s.value_changed.connect(func(v: float) -> void:
			value.text = "%d%%" % roundi(v * 100.0)
			FxSettings.set_volume(key, v, false))
		s.drag_ended.connect(func(_changed: bool) -> void:
			Settings.save()
			Sfx.play_ui("gui-slider"))
		holder.add_child(s)
		holder.add_child(value)
		if entry.size() > 2:
			s.tooltip_text = entry[2]
		_row(grid, entry[0], holder)
	_note("Music is Factorio's soundtrack, read from your install. The game effects slider also turns down walking, environment, weapons, explosions and enemies.")


func _controls() -> void:
	_note("Click a binding, then press the key (with Shift, Ctrl or Alt if you like). Right click clears it, Esc cancels. Bindings that clash are red.")
	var by_group := {}
	for action in Settings.bindable_actions():
		var group := ControlsInfo.group_of(action)
		if not by_group.has(group):
			by_group[group] = []
		by_group[group].append(action)
	var named := {}
	for action in Settings.bindable_actions():
		named[ControlsInfo.name_of(action)] = true
	for group in ControlsInfo.groups():  # Zenith's groups, then each add-on's (scripts/addons/)
		var fixed: Array = ControlsInfo.FIXED.filter(func(f: Array) -> bool: return f[0] == group and not named.has(f[1]))
		if not by_group.has(group) and fixed.is_empty():
			continue
		_heading(group)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", Kit.px(12))
		grid.add_theme_constant_override("v_separation", Kit.px(4))
		_pane.add_child(grid)
		for action in by_group.get(group, []):
			_binding_row(grid, action)
		for f in fixed:
			var l := Kit.label(f[1])
			l.custom_minimum_size.x = Kit.px(260)
			grid.add_child(l)
			var key := Kit.label(f[2])
			key.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
			key.tooltip_text = "Not rebindable yet"
			grid.add_child(key)
			grid.add_child(Control.new())
			grid.add_child(Control.new())
	var reset_all := MenuKit.button("Reset all to defaults")
	reset_all.name = "ResetControls"
	reset_all.custom_minimum_size.x = Kit.px(200)
	reset_all.pressed.connect(func() -> void:
		Sfx.play_ui("gui-click")
		for action in Settings.bindable_actions():
			Settings.bind(action, [])
		_open_tab(_tab))
	_pane.add_child(reset_all)


func _binding_row(grid: GridContainer, action: String) -> void:
	var l := Kit.label(ControlsInfo.name_of(action))
	l.custom_minimum_size.x = Kit.px(260)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	var keys := Settings.keys_for(action)
	for slot in 2:
		var target := "%s/%d" % [action, slot]
		var b := MenuKit.button(Settings.key_name(action, slot))
		b.name = "controls-" + target.replace("/", "-")
		b.custom_minimum_size.x = Kit.px(150)
		var clash := Settings.conflicts(action, int(keys[slot]))
		if not clash.is_empty():
			b.add_theme_color_override("font_color", Kit.RED_TEXT)
			b.tooltip_text = "Also bound to: " + ", ".join(clash.map(func(a: String) -> String: return ControlsInfo.name_of(a)))
		if _capturing == target:
			b.text = "Press a key…"
		b.pressed.connect(func() -> void:
			Sfx.play_ui("gui-click")
			_capturing = target
			b.text = "Press a key…")
		b.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				capture(target, 0)
				_open_tab(_tab))
		grid.add_child(b)
	if keys != Settings.default_keys(action):
		var reset := MenuKit.button("Default")
		reset.custom_minimum_size.x = Kit.px(72)
		reset.tooltip_text = "Back to " + " / ".join(Settings.default_keys(action).filter(func(c: int) -> bool: return c != 0).map(func(c: int) -> String: return Settings.key_text(c)))
		reset.pressed.connect(func() -> void:
			Sfx.play_ui("gui-click")
			Settings.bind(action, [])
			_open_tab(_tab))
		grid.add_child(reset)
	else:
		grid.add_child(Control.new())


## Laid out under Factorio's headings (Visualization, Alt-mode, Interaction, UI scale, Tooltips,
## Other) with its wording; the client's own switches and the minimap's size follow.
func _interface() -> void:
	_heading("Visualization")
	var grid := _grid()
	_ui_check(grid, "Show minimap", "map/minimap", "M opens the map")
	_check(grid, "Show mouse and keyboard control hints", "interface", "show_help", "F1; the client's help panel, hidden while a window is open")
	_check(grid, "Fade tall entities in the way", "interface", "hide_tall", "buildings and trees taller than 2 tiles between the camera and the character or cursor fade out; the shortcut bar toggles it too")

	_heading("Alt-mode")
	grid = _grid()
	_check(grid, "Alt-mode", "interface", "alt_mode", "Alt toggles it; kept between games")

	_heading("Interaction")
	grid = _grid()
	_check(grid, "Smart belt building", "interface", "smart_belt_building", "dragged belts jump obstacles with undergrounds")
	_check(grid, "Lock belt building to straight line", "interface", "lock_belt_straight", "dragged belts don't turn corners")

	_heading("UI scale")
	grid = _grid()
	_dropdown(grid, "UI scale", "interface", "ui_scale", [["Automatic", "auto"], ["75%", "0.75"], ["100%", "1.0"], ["125%", "1.25"], ["150%", "1.5"], ["175%", "1.75"], ["200%", "2.0"]], "Ctrl+= / Ctrl+- / Ctrl+0")

	_heading("Tooltips")
	grid = _grid()
	_slider(grid, "Tooltip delay", "interface", "tooltip_delay", 0.0, 2.0, 0.05, func(v: float) -> String: return "%d ms" % roundi(v * 1000.0))
	_check(grid, "Entity tooltip on the side", "interface", "entity_info", "the panel for what the mouse is over, on the right")

	_heading("Other")
	grid = _grid()
	_slider(grid, "Chat message delay", "interface", "message_delay", 1.0, 20.0, 0.5, func(v: float) -> String: return "%d s" % roundi(v))

	_heading("3D client")
	grid = _grid()
	_check(grid, "Shortcut bar", "interface", "shortcut_bar", "right of the quickbar")
	_check(grid, "Research progress", "interface", "research_progress", "top right")
	_check(grid, "Alerts", "interface", "alerts", "over the shortcut bar")
	_check(grid, "Debug line (F4)", "interface", "debug_overlay", "tick, chunks, packets, FPS")
	_ui_slider(grid, "Minimap size", "map/minimap_size", 120.0, 480.0, 20.0, func(v: float) -> String: return "%d px" % roundi(v))
	_ui_slider(grid, "Minimap zoom", "map/minimap_zoom", 0.25, 4.0, 0.25, func(v: float) -> String: return "%.2f px per tile" % v)
	_ui_check(grid, "Show tags on the minimap", "map/minimap_tags")

	_heading("Map view")
	grid = _grid()
	for layer in UiSettings.MAP_LAYERS:
		_ui_check(grid, layer[1], layer[0])
	_note("The map view's switches are also on the map itself (M), and apply to the minimap too.")


func _other() -> void:
	_heading("Server")
	var grid := _grid()
	var intervals: Array = [["Never", 0]]
	for m in [1, 2, 5, 10, 15, 20, 30, 60]:
		intervals.append(["%d min" % m, m])
	_dropdown(grid, "Autosave interval", "factorio", "autosave_interval", intervals, "servers started from the menu")
	_slider(grid, "Autosave slots", "factorio", "autosave_slots", 1, 20, 1, func(v: float) -> String: return "%d" % int(v))
	_check(grid, "Verbose logging", "factorio", "verbose_logging", "the server's factorio-current.log")
	_note("These go into the server-settings.json the menu writes in the server's data folder when it starts a server, and apply from the next start.")


func _mod_settings() -> void:
	_heading("Map")
	if rcon == null or not rcon.is_open():
		_note("The bridge mod's map settings can be changed here while you play a game started from this menu. In other games, type them in the server's console, for example /c settings.global[\"f3d-chunks-per-tick\"] = {value = 2}.")
		return
	var grid := _grid()
	var status := Kit.label("Reading the server's settings…")
	status.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	_pane.add_child(status)
	var names: Array = MOD_SETTINGS.map(func(m: Array) -> String: return "\"%s\"" % m[0])
	var reply: String = await rcon.run(get_tree(), "/sc local o = {} for _, n in pairs({%s}) do o[n] = settings.global[n].value end rcon.print(helpers.table_to_json(o))" % ", ".join(names))
	if not is_inside_tree() or TABS[_tab] != "Mod settings":
		return
	var values = JSON.parse_string(reply.strip_edges())
	if not values is Dictionary:
		status.text = "The server didn't answer: " + reply.strip_edges()
		return
	status.text = "Changes are sent to the server at once (settings.global)."
	for m in MOD_SETTINGS:
		var name: String = m[0]
		var current = values.get(name, m[3])
		var control: Control
		match str(m[2]):
			"bool":
				var c := MenuKit.checkbox("", bool(current))
				c.toggled.connect(func(on: bool) -> void:
					Sfx.play_ui("gui-checkbox-click")
					_set_mod_setting(name, "true" if on else "false"))
				control = c
			"int":
				var spin := SpinBox.new()
				spin.min_value = m[4]
				spin.max_value = m[5]
				spin.value = int(current)
				spin.custom_minimum_size = Kit.pxv(160, 28)
				spin.value_changed.connect(func(v: float) -> void: _set_mod_setting(name, str(int(v))))
				control = spin
			_:
				var e := MenuKit.textbox(str(current))
				e.text_submitted.connect(func(t: String) -> void: _set_mod_setting(name, JSON.stringify(t.strip_edges())))
				control = e
		control.name = "mod-" + name
		_row(grid, m[1], control, "default %s" % str(m[3]))


func _set_mod_setting(name: String, lua_value: String) -> void:
	if rcon != null and rcon.is_open():
		await rcon.run(get_tree(), "/sc settings.global[\"%s\"] = {value = %s}" % [name, lua_value])


func _camera() -> void:
	var grid := _grid()
	_dropdown(grid, "View when a game starts", "camera", "default_view", [["Angled view", "angled"], ["Factorio's view", "factorio"], ["First person", "first_person"]], "F6 and F5 switch in the game")
	_dropdown(grid, "Projection", "camera", "orthographic", [["Perspective", false], ["Orthographic", true]], "for the angled view; Factorio's view (F6) is always orthographic; F7 switches")
	_dropdown(grid, "Projection on the map", "camera", "map_orthographic", [["Perspective", false], ["Orthographic", true]], "the remote view, zoomed in from the map; F7 there switches it")
	_slider(grid, "Furthest zoom", "camera", "max_zoom", 60.0, 400.0, 10.0, func(v: float) -> String: return "%d tiles" % int(v), false, false, "the default is 140; far out, more of the world must be drawn")
	_slider(grid, "Mouse sensitivity", "camera", "look_sensitivity", 0.25, 3.0, 0.05, func(v: float) -> String: return "%.2f×" % v)
	_check(grid, "Invert mouse look", "camera", "invert_y", "first person and middle-drag tilt")


func _factorio() -> void:
	var grid := _grid()
	var found := Paths.find_factorio_exe()
	var exe := MenuKit.textbox(str(Settings.get_value("factorio", "executable")), "Automatic: " + (found if found != "" else "not found"))
	exe.custom_minimum_size.x = Kit.px(420)
	_on_text(exe, "factorio", "executable")
	_row(grid, "Factorio (factorio.exe or its folder)", exe)
	var in_use := Paths.factorio_exe()
	var ok := in_use != "" and FileAccess.file_exists(in_use)
	var status := Kit.label(("Using " + in_use) if ok else "Factorio not found: set the path above")
	status.add_theme_color_override("font_color", Kit.DISABLED_TEXT if ok else Kit.RED_TEXT)
	_row(grid, "", status)
	var data := MenuKit.textbox(str(Settings.get_value("factorio", "server_data")), Paths.repo_dir().path_join("server/data"))
	data.custom_minimum_size.x = Kit.px(420)
	_on_text(data, "factorio", "server_data")
	_row(grid, "Server data folder", data)
	var saves := MenuKit.textbox(str(Settings.get_value("factorio", "saves")), Paths.repo_dir().path_join("server/saves"))
	saves.custom_minimum_size.x = Kit.px(420)
	_on_text(saves, "factorio", "saves")
	_row(grid, "Saves folder", saves)
	var port := SpinBox.new()
	port.name = "factorio-port_base"
	port.min_value = 1024
	port.max_value = 65000
	port.value = int(Settings.get_value("factorio", "port_base"))
	port.custom_minimum_size = Kit.pxv(160, 28)
	port.value_changed.connect(func(v: float) -> void: Settings.set_value("factorio", "port_base", int(v)))
	_row(grid, "First port for servers", port, "four free ports from here up")
	_note("The server keeps its config, logs, mods and RCON password in the data folder, apart from your normal game, so both can run at once. Leave a field empty for the default.")


# --- rows ------------------------------------------------------------------------------------

func _heading(text: String) -> void:
	var l := Kit.label(text, "FHeading")
	_pane.add_child(l)


func _hbox() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", Kit.px(8))
	return h


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", Kit.px(24))
	grid.add_theme_constant_override("v_separation", Kit.px(8))
	_pane.add_child(grid)
	return grid


func _row(grid: GridContainer, text: String, control: Control, note := "") -> void:
	var l := Kit.label(text)
	l.custom_minimum_size.x = Kit.px(260)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grid.add_child(l)
	# In a box, so every control keeps its own width instead of filling the column.
	var holder := _hbox()
	holder.add_child(control)
	grid.add_child(holder)
	if note == "":
		return
	var n := Kit.label(note)
	n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(n)


func _note(text: String) -> void:
	var n := MenuKit.paragraph(text, 740)
	n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	_pane.add_child(n)


func _check(grid: GridContainer, text: String, section: String, key: String, note := "", window := false) -> void:
	var c := MenuKit.checkbox("", bool(Settings.get_value(section, key)))
	c.name = section + "-" + key
	c.toggled.connect(func(on: bool) -> void:
		Sfx.play_ui("gui-checkbox-click")
		Settings.set_value(section, key, on)
		if window:
			Settings.apply_window(get_tree().root))
	_row(grid, text, c, note)


## `live`: applied while dragging (saved on release); otherwise set on release.
func _slider(grid: GridContainer, text: String, section: String, key: String, from: float, to: float, step: float, fmt: Callable, window := false, live := false, note := "") -> void:
	var holder := _hbox()
	var s := MenuKit.slider(from, to, step, float(Settings.get_value(section, key)))
	s.name = section + "-" + key
	var value := Kit.label(fmt.call(s.value))
	var as_value := func(v: float) -> Variant: return int(v) if step >= 1.0 else v
	s.value_changed.connect(func(v: float) -> void:
		value.text = fmt.call(v)
		if live:
			Settings.set_value(section, key, as_value.call(v), false))
	s.drag_ended.connect(func(_changed: bool) -> void:
		Sfx.play_ui("gui-slider")
		Settings.set_value(section, key, as_value.call(s.value))
		if window:
			Settings.apply_window(get_tree().root))
	holder.add_child(s)
	holder.add_child(value)
	_row(grid, text, holder, note)


func _dropdown(grid: GridContainer, text: String, section: String, key: String, items: Array, note := "", window := false) -> void:
	var o := MenuKit.dropdown(items, Settings.get_value(section, key))
	o.name = section + "-" + key
	o.item_selected.connect(func(i: int) -> void:
		Sfx.play_ui("gui-click")
		Settings.set_value(section, key, o.get_item_metadata(i))
		if window:
			Settings.apply_window(get_tree().root))
	_row(grid, text, o, note)


func _ui_check(grid: GridContainer, text: String, key: String, note := "") -> void:
	var ui = UiSettings.shared()
	var c := MenuKit.checkbox("", bool(ui.get_value(key)))
	c.name = key.replace("/", "-")
	c.toggled.connect(func(on: bool) -> void:
		Sfx.play_ui("gui-checkbox-click")
		ui.set_value(key, on))
	_row(grid, text, c, note)


func _ui_slider(grid: GridContainer, text: String, key: String, from: float, to: float, step: float, fmt: Callable) -> void:
	var ui = UiSettings.shared()
	var holder := _hbox()
	var s := MenuKit.slider(from, to, step, float(ui.get_value(key)))
	s.name = key.replace("/", "-")
	var value := Kit.label(fmt.call(s.value))
	s.value_changed.connect(func(v: float) -> void:
		value.text = fmt.call(v)
		ui.set_value(key, v, false))
	s.drag_ended.connect(func(_changed: bool) -> void:
		Sfx.play_ui("gui-slider")
		ui.save())
	holder.add_child(s)
	holder.add_child(value)
	_row(grid, text, holder)


func _on_text(e: LineEdit, section: String, key: String) -> void:
	e.name = section + "-" + key
	var commit := func() -> void:
		if str(Settings.get_value(section, key)) != e.text.strip_edges():
			Settings.set_value(section, key, e.text.strip_edges())
	e.text_submitted.connect(func(_t: String) -> void: commit.call())
	e.focus_exited.connect(commit)
