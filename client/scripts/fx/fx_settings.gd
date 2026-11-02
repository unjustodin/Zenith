extends RefCounted
## Sound and effect settings: a volume and an on/off switch per audio bus (Factorio's sound
## settings), the output device, the voice cap, and debug logging. Kept in settings.gd's file
## (`user://settings.cfg`, section [sound]; the smoke and particles switch is [graphics] effects),
## then the command line (after `--`), which wins for that run and isn't saved:
##
##   --volume=0.8 --sfx-volume=1 --music-volume=0.3 --ui-volume=1 --mute
##   --max-voices=12 --sfx-log --no-fx (no smoke, flashes or corpses)
##
## Volumes are linear, 0 to 1. Music is off (0) unless asked for.

const Settings := preload("res://scripts/menu/settings.gd")

## Volume key -> [bus, the bus it feeds]. Factorio's categories: walking, environment (machines and
## vehicles), weapons, explosions and enemies are parts of the game effects.
const BUSES := {
	"master": ["Master", ""], "effects": ["Effects", "Master"], "music": ["Music", "Master"],
	"ui": ["UI", "Master"], "walking": ["Walking", "Effects"], "environment": ["Environment", "Effects"],
	"weapons": ["Weapons", "Effects"], "explosions": ["Explosions", "Effects"], "enemies": ["Enemies", "Effects"],
	"ambient": ["Ambient", "Effects"],
}

static var volumes := {
	"master": 0.8, "effects": 1.0, "music": 0.0, "ui": 1.0,
	"walking": 1.0, "environment": 1.0, "weapons": 1.0, "explosions": 1.0, "enemies": 1.0, "ambient": 1.0,
}
## Factorio's box beside each slider: false mutes that bus.
static var enabled := {}
## Machine and vehicle loops playing at once; one-shot sounds have their own pool.
static var max_voices := 12
static var log_sounds := false
static var effects_enabled := true
static var _loaded := false
## Set from the command line for this run: not saved, and the file doesn't change it.
static var _overridden := {}


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	_read()
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--volume="):
			_override("master", value)
		elif arg.begins_with("--sfx-volume="):
			_override("effects", value)
		elif arg.begins_with("--music-volume="):
			_override("music", value)
		elif arg.begins_with("--ui-volume="):
			_override("ui", value)
		elif arg == "--mute":
			_override("master", "0")
		elif arg.begins_with("--max-voices="):
			max_voices = clampi(int(value), 0, 64)
			_overridden["max_voices"] = true
		elif arg == "--sfx-log":
			log_sounds = true
		elif arg == "--no-fx":
			effects_enabled = false
			_overridden["fx"] = true
	Settings.listen(_on_setting)
	setup_buses()
	apply_device()


static func _override(key: String, value: String) -> void:
	volumes[key] = clampf(float(value), 0.0, 1.0)
	enabled[key] = true
	_overridden[key] = true


static func _read() -> void:
	for key in volumes:
		if not _overridden.has(key):
			volumes[key] = clampf(float(Settings.get_value("sound", key)), 0.0, 1.0)
			enabled[key] = bool(Settings.get_value("sound", key + "_on")) if Settings.has_value("sound", key + "_on") else true
	if not _overridden.has("max_voices"):
		max_voices = clampi(int(Settings.get_value("sound", "max_voices")), 0, 64)
	if not _overridden.has("fx"):
		effects_enabled = bool(Settings.get_value("graphics", "effects"))


static func _on_setting(section: String, key: String) -> void:
	if section == "sound" or (section == "graphics" and key == "effects"):
		_read()
		setup_buses()
		if key == "output_device":
			apply_device()


## Kept for older callers: the settings file is written as each value changes.
static func save() -> void:
	Settings.save()


## Changes a volume now (for a settings screen); `persist` writes the file too.
static func set_volume(key: String, value: float, persist := true) -> void:
	if not volumes.has(key):
		return
	_overridden.erase(key)
	Settings.set_value("sound", key, clampf(value, 0.0, 1.0), persist)


static func set_enabled(key: String, on: bool) -> void:
	if not volumes.has(key):
		return
	_overridden.erase(key)
	Settings.set_value("sound", key + "_on", on)


## The buses, each feeding its parent. Created at runtime, so the project needs no bus layout
## resource.
static func setup_buses() -> void:
	for key in BUSES:
		var bus: String = BUSES[key][0]
		var index := AudioServer.get_bus_index(bus)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
		if BUSES[key][1] != "":
			AudioServer.set_bus_send(index, BUSES[key][1])
		elif AudioServer.get_bus_effect_count(index) == 0:
			# Many sounds at once must never clip: a limiter on the output, just below full scale.
			var limiter := AudioEffectHardLimiter.new()
			limiter.ceiling_db = -0.5
			AudioServer.add_bus_effect(index, limiter)
		var v: float = volumes[key]
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(index, v <= 0.0 or not bool(enabled.get(key, true)))


## Factorio's "Preferred output": a device from AudioServer.get_output_device_list(), or "Default".
static func apply_device() -> void:
	var device := str(Settings.get_value("sound", "output_device"))
	if not AudioServer.get_output_device_list().has(device):
		device = "Default"
	if AudioServer.output_device != device:
		AudioServer.output_device = device
