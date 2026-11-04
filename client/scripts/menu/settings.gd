extends RefCounted
## Every setting of the client, in one file: `user://settings.cfg` (on Windows
## `%APPDATA%\Godot\app_userdata\Zenith\settings.cfg`), changed in the Settings window
## (settings_window.gd). The sections follow Factorio's settings tabs: [graphics], [sound],
## [interface], [map] (minimap and map view), [controls] (rebound keys only), [camera],
## [factorio] (paths, ports, the server's autosave) and [new_game] (the map generator's last
## choices). ui_settings.gd ([map], [interface]) and fx_settings.gd ([sound]) are views of it.
## The older `ui.cfg` and `audio.cfg` are read into this file once (the keys it doesn't have yet)
## and then left alone.
##
## Command-line options win over the file for that run and aren't saved: --ui-scale (kit.gd),
## --camera=... (camera_rig.gd), --factorio-data (item_icons.gd), --no-sprites, the sound options
## (fx_settings.gd), and --factorio=<factorio.exe> --server-data=<dir> --saves-dir=<dir>
## --port-base=<port> (here). --settings-file=<path> uses another file, so tests and screenshots
## leave the player's own settings alone.
##
## Whoever shows something a setting changes calls `listen(callable)`; `set_value` saves and calls
## every listener with (section, key), so most settings apply at once.

const ItemCards := preload("res://scripts/world/item_cards.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const Kit := preload("res://scripts/ui/factorio/kit.gd")

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"graphics": {
		"window_mode": "windowed",  # windowed, borderless, fullscreen
		"resolution": "",  # "1920x1080"; "" keeps the project's window size
		"screen": -1,  # Factorio's preferred screen; -1: the primary one
		"minimize_on_focus_loss": false,  # in full screen
		"vsync": true,
		"fps_cap": 0,  # 0: unlimited
		"render_scale": 1.0,
		"antialiasing": "fxaa",  # off, fxaa, taa, msaa2, msaa4, msaa8
		"shadows": "high",  # off, low, medium, high, ultra (sun_shadows.gd)
		"shadow_distance": 0,  # tiles the shadows may reach from the camera; 0: the quality's (sun_shadows.gd)
		# high, medium, low: how soon far-away models and their shadows simplify (model_lods.gd); the
		# models near the character stay whole at every level
		"lod_quality": "medium",
		# Far chunks' buildings drawn as one simplified mesh each (far_chunks.gd): far fewer draws
		"merge_far": true,
		# Each model drawn as one surface with one material (material_rows.gd): fewer draws and less
		# render CPU, but its per-pixel table reads cost GPU time (laptop at Ultra: 1-2 ms more
		# standing), so off unless the CPU is the limit. Read when models load: after a restart.
		"merged_materials": false,
		# Screen-space ambient occlusion: off (owner's decision; WIP). Its own step is cheap, but it makes
		# Godot's depth pre-pass work out every pixel's normal and roughness, which runs the models'
		# weathering: 6-7 ms of GPU a frame at a busy base (PERFORMANCE-AUDIT.md, item 2).
		"ssao": false,
		# Godot's renderer on a thread of its own (faster on busy bases); off: the main thread, as
		# before. Read at start-up from ENGINE_OVERRIDES, so it applies after a restart.
		"render_thread": false,  # Godot calls it experimental; no gain measured, rare hangs on quitting
		"view_radius": 10,  # chunks around the camera that are drawn (doubled from 5)
		"entity_radius": 192,  # tiles around the camera where moving things and machine states are shown (doubled from 96)
		# Items on belts are drawn out to belt_distance (0 off): moving, from the character outwards, as
		# far as belt_updates allows (the most items and lanes the server reads an update), and past
		# that each lane as icons of what it carries (owner: one distance and a cap, not two distances).
		"belt_distance": 160,
		"belt_updates": 6000,  # 0: Unlimited, every item within belt_distance moves
		"belt_smooth": true,  # belt items read in one tick, every update (smooth on curves) rather than spread over ticks
		"decorative_distance": 192,
		# While the game runs under 60 UPS, ask the bridge for less (distances, minimap refreshes,
		# frame rate) below these settings, and give it back when it recovers (ups_governor.gd)
		"hold_ups": true,  # tiles out to which ground clutter is drawn, thinner far away
		"item_icons": true,  # Factorio's icons on items on belts and on the ground
		"item_models": true,  # items on belts, on the ground, in hands as 3D models (false: icons)
		# Models: "colours" (each part in its colour from Factorio's sprite), "sprite" (Factorio's
		# sprite projected on as well), "palette" (the models' own colours)
		"model_look": "colours",
		"effects": true,  # Factorio's "Show all smoke" and "Show particles": smoke, dust, flashes, corpses
		"clouds": true,  # clouds in the sky and their shadows on the ground, planets' haze (scripts/world/sky.gd)
		"decoratives": true,  # grass, flowers and small rocks from Factorio (scripts/world/decoratives.gd)
		"decorative_density": 1.0,  # the share of them drawn, 0.1 to 1
		"brightness": 1.0,  # 0.5 to 1.5, as Factorio's sliders
		"contrast": 1.0,
		"saturation": 1.0,
		"color_filter": "none",  # color_filter.gd FILTERS
	},
	"sound": {
		# Linear volumes, 0 to 1 (fx_settings.gd); "<name>_on" false mutes that slider.
		"master": 0.8, "effects": 1.0, "music": 0.0, "ui": 1.0,
		"walking": 1.0, "environment": 1.0, "weapons": 1.0, "explosions": 1.0, "enemies": 1.0,
		"ambient": 1.0,  # wind and each planet's background sounds (fx/ambience.gd)
		"max_voices": 12,  # machine and vehicle loops playing at once
		"output_device": "Default",
	},
	"interface": {
		"ui_scale": "auto",  # auto, 0.75 ... 2.0
		"show_help": false,  # Factorio's "Show mouse and keyboard control hints"; Factorio shows no help panel
		"debug_overlay": false,
		"tooltip_delay": 0.5,  # seconds before a tooltip shows
		"message_delay": 4.0,  # seconds a message stays (Factorio's "Chat message delay")
		"alt_mode": false,  # Alt-mode, remembered between games like Factorio's
		# Factorio's Interface > Alt-mode arrows (issue #9), with its defaults (seen in 2.1.23 with a fresh
		# config: machines' and pumps' arrows show, inserters' don't)
		"alt_inserter_arrows": false,
		"alt_pump_arrows": true,
		"alt_machine_arrows": true,
		"entity_info": true,  # the entity info panel on the right
		"shortcut_bar": true,  # the shortcut bar right of the quickbar
		"research_progress": true,  # the research in progress, top left
		"alerts": true,  # alert icons over the shortcut bar
		"smart_belt_building": true,  # Factorio's: dragged belts jump obstacles with undergrounds
		"lock_belt_straight": false,  # Factorio's "Lock belt building to straight line"
	},
	"camera": {
		"default_view": "angled",  # angled, factorio, first_person
		"follow_hills": false,  # the camera rises and falls with an add-on's hills (api.terrain); off: stays level (owner)
		"look_sensitivity": 1.0,
		"invert_y": false,
		"orthographic": false,  # the angled view's projection; Factorio's view (F6) is always orthographic
		"map_orthographic": true,  # the remote view's, from the map (F7 switches the view in use)
		"max_zoom": 140,  # how far the wheel zooms out, in tiles from the focus
		"map_zoom_out": 240,  # the map's remote view: how far out before the map comes back (tiles)
	},
	"factorio": {
		"executable": "",  # factorio.exe or the install folder; "" finds it
		"server_data": "",  # "" is <repo>/server/data
		"saves": "",  # "" is <repo>/server/saves
		"port_base": 34500,  # launched servers take free ports from here up
		"autosave_interval": 10,  # minutes, 0: never (server-settings.json)
		"autosave_slots": 5,
		"verbose_logging": false,
	},
	# action -> "<primary>,<alternative>" key names (OS.get_keycode_string, with modifiers such as
	# "Shift+R"; an empty slot is unbound). Only rebound actions are written.
	"controls": {},
	# alert kinds (Factorio's names) switched off or muted in the alerts settings window
	"alerts": {
		"disabled": [],
		"muted": [],
	},
}

## Resolutions offered besides the screen's own.
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
## Project settings read before the game starts (project.godot's
## application/config/project_settings_override): the render thread setting is written here.
const ENGINE_OVERRIDES := "user://engine.cfg"
## Godot's thread models: the renderer on the main thread, or on its own.
const THREAD_SAFE := 1
const THREAD_SEPARATE := 2


## Writes ENGINE_OVERRIDES from the settings; Godot reads it at the next start.
static func write_engine_overrides() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("rendering", "driver/threads/thread_model", THREAD_SEPARATE if bool(get_value("graphics", "render_thread")) else THREAD_SAFE)
	cfg.save(ENGINE_OVERRIDES)


## Graphics presets (Settings > Graphics > Preset): the settings each sets together, from cheapest to
## dearest. High is the defaults; every setting stays its own, and the preset shows "Custom" once
## any of these differs from all of them (preset_now()).
const PRESETS := {
	"low": {"shadows": "low", "ssao": false, "lod_quality": "low", "view_radius": 5, "entity_radius": 96,
		"belt_updates": 2000, "belt_distance": 64, "decorative_distance": 96, "decorative_density": 0.5,
		"clouds": false},
	"medium": {"shadows": "medium", "ssao": false, "lod_quality": "medium", "view_radius": 7, "entity_radius": 128,
		"belt_updates": 4000, "belt_distance": 96, "decorative_distance": 128, "decorative_density": 0.75,
		"clouds": true},
	"high": {"shadows": "high", "ssao": false, "lod_quality": "medium", "view_radius": 10, "entity_radius": 192,
		"belt_updates": 6000, "belt_distance": 160, "decorative_distance": 192, "decorative_density": 1.0,
		"clouds": true},
	"ultra": {"shadows": "ultra", "ssao": false, "lod_quality": "high", "view_radius": 14, "entity_radius": 256,
		"belt_updates": 12000, "belt_distance": 320, "decorative_distance": 256, "decorative_density": 1.0,
		"clouds": true},
}


## Sets every graphics setting of a preset (PRESETS), writing the file once.
static func apply_preset(preset: String) -> void:
	var values: Dictionary = PRESETS.get(preset, {})
	var keys := values.keys()
	for i in keys.size():
		set_value("graphics", keys[i], values[keys[i]], i == keys.size() - 1)


## The preset to recommend for this PC (Settings > Graphics > Recommended). From the hardware: an
## integrated GPU gets Low or Medium, a discrete one High, a recent big one with 16 threads or more
## Ultra. Then, from what was measured in a game (`fps`: the slowest tenth of frames as a rate,
## `ups`: the game's ticks a second; 0 when not measured), one preset lower for every way it falls
## short of a steady 60: the aim is 60 UPS and 60 FPS, not the most detail.
static func recommended_preset(cores: int, adapter: String, fps := 0.0, ups := 0.0, now := "") -> String:
	var order := ["low", "medium", "high", "ultra"]
	var name := adapter.to_lower()
	var integrated := name.contains("intel") or name.contains("uhd") or name.contains("iris") 		or (name.contains("radeon") and not name.contains("rx")) or name.contains("vega") or name.contains("llvmpipe")
	var big := name.contains("rtx 40") or name.contains("rtx 50") or name.contains("rx 7") or name.contains("rx 9")
	var pick := 2
	if integrated:
		pick = 1 if cores >= 8 else 0
	elif cores < 8:
		pick = 1
	elif big and cores >= 16:
		pick = 3
	if fps > 0.0:
		# Measured in a game at the preset in use: start from it rather than the guess.
		if order.has(now):
			pick = order.find(now)
		if fps < 50.0:
			pick -= 2 if fps < 35.0 else 1
		elif fps > 90.0 and ups >= 59.0:
			pick += 1
		if ups > 0.0 and ups < 57.0:
			pick -= 1
	return order[clampi(pick, 0, order.size() - 1)]


## Settings > Graphics > Merged materials, for the models made from now on (at start-up, before
## any: a change in a game applies after a restart, as models already made keep their surfaces).
## --merged-materials / --no-merged-materials win.
static func apply_merged_materials() -> void:
	if not has_arg("--no-merged-materials") and not has_arg("--merged-materials"):
		ModelLibrary.merge_materials = bool(get_value("graphics", "merged_materials"))


## Whether Settings > Graphics > Recommended turns merged materials on: a big recent discrete GPU
## (the GPU has room for the table reads), and, when a game was measured, a frame the GPU isn't
## holding up (`gpu_ms` the GPU's share of `frame_ms`; 0: not measured).
static func recommended_merged_materials(adapter: String, frame_ms := 0.0, gpu_ms := 0.0) -> bool:
	var name := adapter.to_lower()
	var big := name.contains("rtx 40") or name.contains("rtx 50") or name.contains("rx 7") or name.contains("rx 9")
	if not big or name.contains("laptop"):
		return false
	return frame_ms <= 0.0 or gpu_ms < frame_ms * 0.7


## The preset the graphics settings match now, or "custom".
static func preset_now() -> String:
	for preset in PRESETS:
		var values: Dictionary = PRESETS[preset]
		var same := true
		for key in values:
			var now: Variant = get_value("graphics", key)
			same = same and (is_equal_approx(float(now), float(values[key])) if values[key] is float else now == values[key])
		if same:
			return preset
	return "custom"


## Directional shadow atlas size per quality (sun_shadows.gd QUALITY sets it in a game; the menu's
## background and whether the sun casts shadows at all read it here).
const SHADOW_SIZES := {"low": 2048, "medium": 4096, "high": 4096, "ultra": 8192}
const MSAA := {"msaa2": Viewport.MSAA_2X, "msaa4": Viewport.MSAA_4X, "msaa8": Viewport.MSAA_8X}

## The file in use: PATH, --settings-file=<path>, or a test's (use_file()).
static var path := ""
## The older files read into this one once: file -> {their section: our section}.
static var legacy := {
	"user://ui.cfg": {"map": "map", "interface": "interface"},
	"user://audio.cfg": {"audio": "sound"},
}

static var _cfg := ConfigFile.new()
static var _loaded := false
static var _listeners: Array[Callable] = []
## The rebindable actions' defaults as player_input.gd defines them: action -> [primary, alternative]
## key codes (0: none), in its order.
static var _default_keys := {}


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	if path == "":
		path = arg_value("--settings-file=")
		if path == "":
			path = PATH
	if path == PATH:
		copy_old_user_folder()
	_cfg = ConfigFile.new()
	var existed := _cfg.load(path) == OK
	if not existed:
		_cfg = ConfigFile.new()
	var renamed := _rename_values()
	var reset := _ssao_off_once()
	if _migrate() or renamed or reset or not existed:
		_cfg.save(path)


## Values that were renamed: an older name of the angled view's setting is read as it. True when one changed.
static func _rename_values() -> bool:
	var changed := false
	if str(_cfg.get_value("camera", "default_view", "")) == "zomboid":
		_cfg.set_value("camera", "default_view", "angled")
		changed = true
	# "Belt items far away" became the one Belt item distance; "Belt items in full" gave way to
	# Belt updates (how far items move follows from it).
	if _cfg.has_section_key("graphics", "belt_far_distance"):
		if not _cfg.has_section_key("graphics", "belt_distance"):
			_cfg.set_value("graphics", "belt_distance", _cfg.get_value("graphics", "belt_far_distance"))
		_cfg.erase_section_key("graphics", "belt_far_distance")
		changed = true
	if _cfg.has_section_key("graphics", "belt_near_distance"):
		_cfg.erase_section_key("graphics", "belt_near_distance")
		changed = true
	return changed


## SSAO was on by default and in the High and Ultra presets until it measured 6-7 ms of GPU a
## frame; it is off now (a WIP option), and turned off once in files saved before. True when changed.
static func _ssao_off_once() -> bool:
	if bool(_cfg.get_value("meta", "ssao_off", false)):
		return false
	_cfg.set_value("meta", "ssao_off", true)
	if _cfg.has_section_key("graphics", "ssao"):
		_cfg.set_value("graphics", "ssao", false)
	return true


## The project was renamed from "Factorio 3D" to "Zenith", which moved Godot's user folder
## (app_userdata/<project name>). Once, while the new folder has no settings yet, the player's
## files from the old one are copied over: settings, quickbar, blueprint library, sound.
static func copy_old_user_folder() -> void:
	var here := OS.get_user_data_dir()
	var old := here.get_base_dir().path_join("Factorio 3D")
	if FileAccess.file_exists(here.path_join("settings.cfg")) or not DirAccess.dir_exists_absolute(old):
		return
	var dir := DirAccess.open(old)
	if dir == null:
		return
	DirAccess.make_dir_recursive_absolute(here)
	for f in dir.get_files():
		if (f.ends_with(".cfg") or f.ends_with(".json")) and not f.contains("test") and not f.begins_with("probe-"):
			DirAccess.copy_absolute(old.path_join(f), here.path_join(f))


## Uses another file from now on (tests), forgetting what was loaded.
static func use_file(file: String) -> void:
	path = file
	_loaded = false
	load_settings()


## Reads the older ui.cfg and audio.cfg into this file, once: the keys it doesn't have yet.
## True when the file needs saving.
static func _migrate() -> bool:
	if bool(_cfg.get_value("meta", "migrated", false)):
		return false
	for old_path in legacy:
		var old := ConfigFile.new()
		if old.load(old_path) != OK:
			continue
		var sections: Dictionary = legacy[old_path]
		for section in old.get_sections():
			var target := str(sections.get(section, ""))
			if target == "":
				continue
			for key in old.get_section_keys(section):
				if not _cfg.has_section_key(target, key):
					_cfg.set_value(target, key, old.get_value(section, key))
		# audio.cfg's [effects] enabled is the graphics tab's smoke and particles.
		if old.has_section_key("effects", "enabled") and not _cfg.has_section_key("graphics", "effects"):
			_cfg.set_value("graphics", "effects", bool(old.get_value("effects", "enabled")))
	_cfg.set_value("meta", "migrated", true)
	return true


static func get_value(section: String, key: String) -> Variant:
	load_settings()
	var fallback = DEFAULTS.get(section, {}).get(key)
	return _cfg.get_value(section, key, fallback)


## Changes a setting, writes the file (unless `persist` is false: a slider being dragged) and
## tells the listeners.
static func set_value(section: String, key: String, value: Variant, persist := true) -> void:
	load_settings()
	_cfg.set_value(section, key, value)
	if persist:
		_cfg.save(path)
	if section == "interface" and key == "tooltip_delay":
		apply_interface()
	if section == "graphics" and key == "item_models":
		ItemCards.use_models = bool(value)
	if section == "graphics" and key == "render_thread" and persist:
		write_engine_overrides()
	if section == "interface" and key == "ui_scale":
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			apply_ui_scale(tree.root)
	_notify(section, key)


static func save() -> void:
	load_settings()
	_cfg.save(path)


static func has_value(section: String, key: String) -> bool:
	load_settings()
	return _cfg.has_section_key(section, key)


## Puts a setting back to its default.
static func reset_value(section: String, key: String) -> void:
	load_settings()
	if _cfg.has_section_key(section, key):
		_cfg.erase_section_key(section, key)
		_cfg.save(path)
	_notify(section, key)


static func _notify(section: String, key: String) -> void:
	for f in _listeners.duplicate():
		if f.is_valid():
			f.call(section, key)
		else:
			_listeners.erase(f)


static func listen(f: Callable) -> void:
	if not _listeners.has(f):
		_listeners.append(f)


static func unlisten(f: Callable) -> void:
	_listeners.erase(f)


static func arg_value(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


static func has_arg(prefix: String) -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return true
	return false


# --- startup ---------------------------------------------------------------------------------

## Settings that must be in place before anything is built: the UI scale, models' sprites,
## icons on items, the tooltip delay. Called first thing by main.gd.
static func apply_startup(window_height: float) -> void:
	load_settings()
	var ui_scale := str(get_value("interface", "ui_scale"))
	if ui_scale != "auto" and not has_arg("--ui-scale="):
		Kit.scale = clampf(float(ui_scale), 0.5, 4.0)
		Kit._scale_set = true
	Kit.configure(window_height)
	ModelLibrary.set_look(str(get_value("graphics", "model_look")))
	apply_merged_materials()
	ItemCards.use_icons = bool(get_value("graphics", "item_icons"))
	ItemCards.use_models = bool(get_value("graphics", "item_models"))
	ItemCards.configure_from_command_line()
	apply_interface()


## The UI scales Factorio offers (Settings → Interface, Ctrl+= / Ctrl+- step through them), as
## the settings file stores them.
const UI_SCALES := ["0.75", "1.0", "1.25", "1.5", "1.75", "2.0"]


## The UI scale the settings ask for now ("auto" follows the window's height, as Factorio does).
static func wanted_ui_scale() -> float:
	if has_arg("--ui-scale="):
		return clampf(float(arg_value("--ui-scale=")), 0.5, 4.0)
	var value := str(get_value("interface", "ui_scale"))
	if value == "auto":
		return Kit.scale_for(DisplayServer.window_get_size().y)
	return clampf(float(value), 0.5, 4.0)


## Changes the UI scale without a restart. The UI is built in GUI pixels times Kit.scale, the
## scale it started with; the root window's content scale makes up the difference, so every
## window, the HUD and the menus grow or shrink at once and lay themselves out again for the
## smaller or larger room (the 3D view keeps its full resolution). The next start builds at the
## new scale directly, so text is as sharp as ever then.
static func apply_ui_scale(root: Window) -> void:
	if root == null or DisplayServer.get_name() == "headless":
		return
	var factor := wanted_ui_scale() / Kit.scale
	if not is_equal_approx(root.content_scale_factor, factor):
		root.content_scale_factor = factor


## One step up or down Factorio's list of UI scales (Ctrl+= / Ctrl+-), from the scale in use.
static func step_ui_scale(steps: int) -> void:
	var now := wanted_ui_scale()
	var i := 0
	for k in UI_SCALES.size():
		if absf(float(UI_SCALES[k]) - now) < absf(float(UI_SCALES[i]) - now):
			i = k
	set_value("interface", "ui_scale", UI_SCALES[clampi(i + steps, 0, UI_SCALES.size() - 1)])


## Settings of the interface that apply at once: the tooltip delay (Godot reads it for each
## tooltip).
static func apply_interface() -> void:
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", clampf(float(get_value("interface", "tooltip_delay")), 0.0, 5.0))


## Window mode, size, screen, vsync, FPS cap, render scale and anti-aliasing. The window's mode
## and size are skipped for screenshots (--screenshot), so they keep the project's window.
## The UPS governor's frame rate cap while it holds one (0: none); main.gd sets it.
static var fps_hold := 0


## The frame rate cap to use: the player's, or the governor's when that is lower (0: unlimited).
static func fps_limit() -> int:
	var cap := int(get_value("graphics", "fps_cap"))
	if fps_hold > 0:
		return fps_hold if cap <= 0 else mini(cap, fps_hold)
	return cap


static func apply_window(root: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	Engine.max_fps = fps_limit()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(get_value("graphics", "vsync")) else DisplayServer.VSYNC_DISABLED)
	root.scaling_3d_scale = clampf(float(get_value("graphics", "render_scale")), 0.25, 2.0)
	var aa := str(get_value("graphics", "antialiasing"))
	root.msaa_3d = MSAA.get(aa, Viewport.MSAA_DISABLED)
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa = aa == "taa"
	# --borderless: a window without a frame, for screenshot runs that shouldn't look like the game opening.
	if has_arg("--borderless"):
		# Dropping the frame keeps the outer rectangle, which would grow the picture by the frame's
		# size: keep the size asked for (--resolution 1920x1080 for UI reference shots).
		var before := DisplayServer.window_get_size()
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(before)
	if has_arg("--screenshot="):
		return
	var screen := int(get_value("graphics", "screen"))
	if screen < 0 or screen >= DisplayServer.get_screen_count():
		screen = DisplayServer.get_primary_screen()
	var on_screen := DisplayServer.window_get_current_screen() == screen
	match str(get_value("graphics", "window_mode")):
		"borderless", "fullscreen":
			if not on_screen:
				if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_current_screen(screen)
			var exclusive := str(get_value("graphics", "window_mode")) == "fullscreen"
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if exclusive else DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size := DisplayServer.window_get_size()
			var res := str(get_value("graphics", "resolution"))
			if res.contains("x"):
				var wanted := Vector2i(int(res.get_slice("x", 0)), int(res.get_slice("x", 1)))
				if wanted.x >= 320 and wanted.y >= 240:
					size = wanted
			if size != DisplayServer.window_get_size() or not on_screen:
				DisplayServer.window_set_size(size)
				var area := DisplayServer.screen_get_usable_rect(screen)
				DisplayServer.window_set_position(area.position + (area.size - size) / 2)


## Brightness, contrast and saturation on a 3D environment (the game's and the menu's).
static func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var b := clampf(float(get_value("graphics", "brightness")), 0.5, 1.5)
	var c := clampf(float(get_value("graphics", "contrast")), 0.5, 1.5)
	var s := clampf(float(get_value("graphics", "saturation")), 0.0, 2.0)
	env.adjustment_enabled = b != 1.0 or c != 1.0 or s != 1.0
	env.adjustment_brightness = b
	env.adjustment_contrast = c
	env.adjustment_saturation = s


## The shadow atlas for a quality; "off" turns the sun's shadows off (main.gd).
static func shadow_size() -> int:
	return int(SHADOW_SIZES.get(str(get_value("graphics", "shadows")), 0))


# --- key bindings ----------------------------------------------------------------------------
# Like Factorio, each control has a primary and an alternative binding, each a key with any
# modifiers (Shift, Ctrl, Alt). A binding with modifiers only fires with them held; one without
# fires whatever is held (so R also answers Shift+R, which rotate reads as reverse rotate).

## Remembers player_input.gd's default keys (its first key is the primary binding, the second the
## alternative), then applies the saved bindings over them. Call after PlayerInput.define_actions()
## and after any other script has added its actions.
static func apply_bindings() -> void:
	for action in InputMap.get_actions():
		var name := str(action)
		if name.begins_with("ui_") or _default_keys.has(name):
			continue
		var keys: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and keys.size() < 2:
				keys.append(event_code(ev as InputEventKey))
		while keys.size() < 2:
			keys.append(0)
		_default_keys[name] = keys
	for action in _default_keys:
		_set_keys(action, keys_for(action))


## A key event's code with its modifiers (KEY_MASK_SHIFT...), as OS.get_keycode_string names it.
static func event_code(ev: InputEventKey) -> int:
	var code := int(ev.physical_keycode if ev.physical_keycode != KEY_NONE else ev.keycode)
	if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return code
	if ev.shift_pressed:
		code |= KEY_MASK_SHIFT
	if ev.ctrl_pressed:
		code |= KEY_MASK_CTRL
	if ev.alt_pressed:
		code |= KEY_MASK_ALT
	if ev.meta_pressed:
		code |= KEY_MASK_META
	return code


## The actions that can be rebound, in the order they were defined.
static func bindable_actions() -> Array:
	return _default_keys.keys()


## [primary, alternative] key codes bound to an action (0: none): saved ones, or the defaults.
static func keys_for(action: String) -> Array:
	load_settings()
	var saved := str(_cfg.get_value("controls", action, "\u0001"))
	if saved == "\u0001":
		return default_keys(action)
	var names := saved.split(",")
	var keys: Array = []
	for i in 2:
		var name := names[i].strip_edges() if i < names.size() else ""
		keys.append(OS.find_keycode_from_string(name) if name != "" else 0)
	return keys


static func default_keys(action: String) -> Array:
	return (_default_keys.get(action, [0, 0]) as Array).duplicate()


## Binds one slot (0 primary, 1 alternative) of an action to a key code with modifiers; 0
## unbinds it.
static func bind_slot(action: String, slot: int, code: int) -> void:
	var keys := keys_for(action)
	keys[clampi(slot, 0, 1)] = code
	bind(action, keys)


## Binds an action to [primary, alternative] (a shorter list leaves the rest unbound); [] puts the
## defaults back.
static func bind(action: String, keys: Array) -> void:
	load_settings()
	var codes: Array = [0, 0]
	for i in mini(2, keys.size()):
		codes[i] = int(keys[i])
	if keys.is_empty() or codes == default_keys(action):
		if _cfg.has_section_key("controls", action):
			_cfg.erase_section_key("controls", action)
			_cfg.save(path)
		_notify("controls", action)
	else:
		var names: Array = []
		for code in codes:
			names.append(OS.get_keycode_string(code) if code != 0 else "")
		set_value("controls", action, ",".join(names))
	_set_keys(action, keys_for(action))


## The key bound to a slot, as Factorio writes it ("Shift + R"), or "" when unbound.
static func key_name(action: String, slot: int) -> String:
	var code: int = keys_for(action)[clampi(slot, 0, 1)]
	return key_text(code)


static func key_text(code: int) -> String:
	return OS.get_keycode_string(code).replace("+", " + ") if code != 0 else ""


## Both bindings, "W / Up", for help texts.
static func key_names(action: String) -> String:
	var names: Array = []
	for code in keys_for(action):
		if code != 0:
			names.append(key_text(code))
	return " / ".join(names) if not names.is_empty() else "(none)"


## The other actions using this key code (with the same modifiers) where both work.
static func conflicts(action: String, code: int) -> Array:
	var out: Array = []
	if code == 0:
		return out
	for other in _default_keys:
		if other != action and keys_for(other).has(code) and _meet(action, other):
			out.append(other)
	return out


## Where an add-on's action works (scripts/addons/addon_keys.gd): "global" (always, like Zenith's
## own controls) or "<add-on id>:camera" (only while that add-on has the camera and Zenith's own
## controls are off, so it may reuse their keys). Zenith's own actions aren't listed.
static var contexts := {}


## Two actions can both fire: then a shared key clashes.
static func _meet(a: String, b: String) -> bool:
	var ca := str(contexts.get(a, ""))
	var cb := str(contexts.get(b, ""))
	return ca == cb or ca == "global" or cb == "global"


## An add-on's action with its default keys ([primary, alternative] codes) and where it works;
## the saved binding (if any) applies over them, and it shows in Settings → Controls.
static func add_action(action: String, keys: Array, context := "global") -> void:
	contexts[action] = context
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var codes: Array = [0, 0]
	for i in mini(2, keys.size()):
		codes[i] = int(keys[i])
	_default_keys[action] = codes
	_set_keys(action, keys_for(action))


## Takes an add-on's action away again (the add-on was switched off); its saved binding stays.
static func remove_action(action: String) -> void:
	_default_keys.erase(action)
	contexts.erase(action)
	if InputMap.has_action(action):
		InputMap.erase_action(action)


static func _set_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	for code in keys:
		if int(code) == 0:
			continue
		var ev := InputEventKey.new()
		ev.physical_keycode = int(code) & KEY_CODE_MASK
		ev.shift_pressed = int(code) & KEY_MASK_SHIFT != 0
		ev.ctrl_pressed = int(code) & KEY_MASK_CTRL != 0
		ev.alt_pressed = int(code) & KEY_MASK_ALT != 0
		ev.meta_pressed = int(code) & KEY_MASK_META != 0
		InputMap.action_add_event(action, ev)


## A readable name for an action ("camera_tilt_up" -> "Camera tilt up").
static func action_label(action: String) -> String:
	return action.replace("_", " ").capitalize()
