extends RefCounted
## The one object an add-on gets (its entry script's addon_start(api)); docs/ADDONS.md is the
## reference for add-on authors. Versioned: `version` is the add-on API this Zenith offers
## (AddonLoader.API_VERSION) and `level` the exact one with its additions (AddonLoader.API_LEVEL,
## 1.1); an add-on whose addon.json asks for a newer one isn't loaded.
## Everything here only reads the game or changes what this client shows: nothing an add-on does
## through it changes the game.
##
##   camera    take the camera and hand it back (addon_camera.gd)
##   keys      the add-on's own controls, in Settings → Controls (addon_keys.gd)
##   world     what the client knows of the game, read-only (addon_world.gd)
##   events    a train leaving, a rocket launching, a fight starting... as signals (addon_events.gd)
##   view      hide the interface, save frames, hold the time of day (addon_view.gd)
##   ui        windows in Zenith's style, messages, an overlay layer (addon_ui.gd)
##   updates   ask the bridge for lighter updates (addon_updates.gd)
##   storage   the add-on's data, per save and for all saves (addon_storage.gd)
##   settings  (1.1) settings shown on the add-on's page of the Add-ons menu (addon_settings.gd)

const AddonLoader := preload("res://scripts/addons/addon_loader.gd")
const AddonCamera := preload("res://scripts/addons/addon_camera.gd")
const AddonKeys := preload("res://scripts/addons/addon_keys.gd")
const AddonView := preload("res://scripts/addons/addon_view.gd")
const AddonUi := preload("res://scripts/addons/addon_ui.gd")
const AddonUpdates := preload("res://scripts/addons/addon_updates.gd")
const AddonStorage := preload("res://scripts/addons/addon_storage.gd")
const AddonSettings := preload("res://scripts/addons/addon_settings.gd")

## A game started (the world is being received) or ended (back to the menu).
signal game_started
signal game_ended

## The add-on API this Zenith offers.
var version := AddonLoader.API_VERSION
## The add-on API with its additions within the version (1.1: settings, view.keep_drawing). Check it
## before using a 1.1 call to keep working on a Zenith with 1.0: `if api.get("level") != null and api.level >= 1.1`.
var level := AddonLoader.API_LEVEL
## Zenith's own version, for messages.
var zenith_version := "Zenith %s" % str(ProjectSettings.get_setting("application/config/version", "(development build)"))
## The add-on's id, name, version and folder, from its addon.json.
var id := ""
var name := ""
var addon_version := ""
var dir := ""

var camera: AddonCamera
var keys: AddonKeys
var world  # addon_world.gd, shared by every add-on
var events  # addon_events.gd, shared by every add-on
var view: AddonView
var ui: AddonUi
var updates: AddonUpdates
var storage: AddonStorage
var settings: AddonSettings

var _host  # addon_host.gd


func _setup(host, manifest: Dictionary) -> void:
	_host = host
	id = str(manifest["id"])
	name = str(manifest["name"])
	addon_version = str(manifest["version"])
	dir = str(manifest["dir"])
	camera = AddonCamera.new(host, self)
	keys = AddonKeys.new(host, self)
	world = host.world
	events = host.events
	view = AddonView.new(host, self)
	ui = AddonUi.new(host, self)
	updates = AddonUpdates.new(host, self)
	storage = AddonStorage.new(host, self)
	settings = AddonSettings.new(host, self)


## Everything the add-on set up through the API, taken away again (it was switched off).
func _teardown() -> void:
	camera.release()
	keys._remove_all()
	ui._close_all()
	updates.clear()
	view._release()
	settings._remove_all()


## A game is on (the world may still be arriving).
func in_game() -> bool:
	return _host != null and _host.in_game()


## A line in Zenith's log (the console it was started from), marked with the add-on's id.
func note(text: String) -> void:
	print("[%s] %s" % [id, text])


## One of the add-on's own scripts, by its path in the add-on's folder ("modes/orbit.gd").
func load_script(relative: String) -> Script:
	return load(dir.path_join(relative)) as Script
