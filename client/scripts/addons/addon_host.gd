extends Node
## Zenith's add-ons (docs/ADDONS.md): finds them (addon_loader.gd), starts the ones switched on,
## each with its API object (addon_api.gd), and stands between them and the game: which add-on has
## the camera, keeping its camera keys from Zenith meanwhile, the interface hidden for a clean
## shot, the mouse, frames saved, the time of day held, lighter updates. main.gd makes one at
## start-up, after Zenith's own controls are defined (add-ons' keys must be in Settings → Controls
## before any game), and tells it when a game starts and ends.
##
## An add-on's entry script extends Node; it is added under this node, and its
## addon_start(api) is called (then addon_stop() when it is switched off). Its _process and input
## callbacks run as any node's; it gets input before Zenith's game controls and menus do.

const AddonLoader := preload("res://scripts/addons/addon_loader.gd")
const AddonApi := preload("res://scripts/addons/addon_api.gd")
const AddonEvents := preload("res://scripts/addons/addon_events.gd")
const AddonWorld := preload("res://scripts/addons/addon_world.gd")
const AddonRequests := preload("res://scripts/addons/addon_requests.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")

## The list changed, or an add-on started or stopped (the Mods window redraws).
signal addons_changed

## main.gd (or a stand-in in tests): its game nodes (rig, avatar, input, hud, movers, world, ride,
## rockets, ups_governor, front_end) are read from it.
var main: Node = null
## Every add-on found: addon_loader.read()'s manifest, plus "node" and "object" (its API) while it runs and
## "error" when it failed to start.
var addons: Array = []
var events := AddonEvents.new()
var world := AddonWorld.new(self)
## Add-ons' windows: over the HUD, under Zenith's menus.
var layer := CanvasLayer.new()
var ui_root := Control.new()
## Look for add-ons when added (off in tests, which call load_all with their own folders).
var autoload := true

var _game_on := false
var _holder = null  # the AddonApi that has the camera
var _holder_input := true
var _input_locked := false
var _mouse_managed := false
var _hidden_by := {}  # add-on id -> true while it wants the interface hidden
var _hidden_nodes: Array = []  # [CanvasLayer, visible before]
var _daytime_by := ""  # the add-on holding the time of day
var _daytime_before := -1.0
var _frame_tasks: Array[int] = []


func _ready() -> void:
	name = "Addons"
	events.name = "Events"
	add_child(events)
	layer.name = "AddonWindows"
	layer.layer = 15
	add_child(layer)
	ui_root.name = "Root"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = MenuKit.theme()
	layer.add_child(ui_root)
	if autoload:
		load_all()


## Finds the add-ons and starts those switched on.
func load_all(where: Array = []) -> void:
	addons = AddonLoader.scan(where)
	for m: Dictionary in addons:
		if not m["ok"]:
			print("addons: %s not loaded: %s" % [m["id"], m["problem"]])
		elif AddonLoader.enabled(m):
			start(m)
	addons_changed.emit()


func find(id: String) -> Dictionary:
	for m: Dictionary in addons:
		if m["id"] == id:
			return m
	return {}


## Starts an add-on (switched on in the Mods window). False, with m["error"], when it can't.
func start(m: Dictionary) -> bool:
	if m.has("node"):
		return true
	if not m["ok"]:
		m["error"] = str(m["problem"])
		return false
	m.erase("error")
	var unpacked := AddonLoader.unpack(m)  # a zipped add-on, into user://addons-cache/<id>
	if unpacked != "":
		m["error"] = unpacked
		print("addons: %s: %s" % [m["id"], m["error"]])
		return false
	var path := str(m["dir"]).path_join(str(m["entry"]))
	var script = load(path)
	if not script is Script or not (script as Script).can_instantiate():
		m["error"] = "its entry script %s has an error (see the log)" % m["entry"]
		print("addons: %s: %s" % [m["id"], m["error"]])
		return false
	var base := str((script as Script).get_instance_base_type())
	if base != "Node" and not ClassDB.is_parent_class(base, "Node"):
		m["error"] = "its entry script must extend Node"
		print("addons: %s: %s" % [m["id"], m["error"]])
		return false
	var node: Node = (script as Script).new()
	var api := AddonApi.new()
	api._setup(self, m)
	m["object"] = api
	m["node"] = node
	node.name = "Addon_" + str(m["id"]).replace("-", "_")
	add_child(node)
	if node.has_method("addon_start"):
		node.addon_start(api)
	print("addons: %s %s started (%s)" % [m["name"], m["version"], m["dir"]])
	if _game_on:
		api.game_started.emit()
	addons_changed.emit()
	return true


## Stops a running add-on: its addon_stop(), then everything it set up through its API goes.
func stop(m: Dictionary) -> void:
	if not m.has("node"):
		return
	var node: Node = m["node"]
	var api = m["object"]
	if is_instance_valid(node) and node.has_method("addon_stop"):
		node.addon_stop()
	api._teardown()
	_hidden_by.erase(api.id)
	_apply_hidden()
	if is_instance_valid(node):
		node.queue_free()
	m.erase("node")
	m.erase("object")
	addons_changed.emit()


## The Mods window's switch: remembered, and the add-on started or stopped at once.
func set_enabled(id: String, on: bool) -> void:
	var m := find(id)
	if m.is_empty():
		return
	AddonLoader.set_enabled(id, on)
	if on:
		start(m)
	else:
		stop(m)


func running() -> Array:
	return addons.filter(func(m: Dictionary) -> bool: return m.has("object"))


# --- the game ----------------------------------------------------------------------------------

## main.gd built the game's nodes. Add-ons hear of it a moment later, once the menu has said
## which save or address it is (api.storage keys its data by that).
func game_started() -> void:
	_game_on = true
	events.attach(main)
	_tell_started.call_deferred()


func _tell_started() -> void:
	if not _game_on:
		return
	for m in running():
		m["object"].game_started.emit()


## Called before the game's nodes are freed: add-ons hear of it while they can still save.
func game_ended() -> void:
	if not _game_on:
		return
	if _holder != null:
		var api = _holder
		release_camera(api)
		api.camera._lost()
	for m in running():
		m["object"].game_ended.emit()
	_restore_mouse()
	_hidden_by.clear()  # a new game starts with its interface
	_apply_hidden()
	for m in running():
		m["object"].view._hiding = false
	_daytime_by = ""
	events.detach()
	_game_on = false


func in_game() -> bool:
	return _game_on


## One of main.gd's game nodes by its name ("rig", "avatar", "movers"...), or null.
func game_node(field: String):
	if main == null or not _game_on:
		return null
	var n = main.get(field)
	return n if n is Object and is_instance_valid(n) else null


func rig():
	return game_node("rig")


func ui_model():
	var hud = game_node("hud")
	return hud.ui.model if hud != null and hud.get("ui") != null else null


# --- the camera ----------------------------------------------------------------------------------

func camera_holder():
	return _holder


func take_camera(api, with_input: bool) -> bool:
	var r = rig()
	if r == null or (_holder != null and _holder != api):
		return false
	var ride = game_node("ride")
	if ride != null and (ride.riding() or ride.in_hub()):
		return false  # Zenith's own film of the ride, and the hub's view, need the camera
	if r.get("vr_view") != null:
		return false  # in VR the headset is the camera
	if _holder == null:
		r.take_over()
	_holder = api
	_holder_input = with_input
	if not with_input:
		_unlock_input()
	_lock_input()
	return true


func release_camera(api) -> void:
	if _holder != api or api == null:
		return
	_holder = null
	_unlock_input()
	var r = rig()
	if r != null:
		r.hand_back()
	_mouse_managed = false
	_apply_mouse()


## Zenith needs the camera back (a ride started): the add-on is told with `lost`.
func _take_back() -> void:
	var api = _holder
	release_camera(api)
	api.camera._lost()


func _lock_input() -> void:
	if _holder == null or not _holder_input:
		return
	var input = game_node("input")
	if input != null and input.is_processing():
		input.set_process(false)
		input.set_process_unhandled_input(false)
		Bridge.send({"t": "walk", "d": -1})
	_input_locked = true


func _unlock_input() -> void:
	if not _input_locked:
		return
	_input_locked = false
	var input = game_node("input")
	var ride = game_node("ride")
	var fe = game_node("front_end")
	# Under a menu main.gd turns the controls back on when it closes; during a ride, ride.gd does.
	if input != null and not (ride != null and ride.riding()) and not (fe != null and fe.covers_game()):
		input.set_process(true)
		input.set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	_finish_frames()
	if not _game_on:
		return
	if _holder != null:
		var r = rig()
		var ride = game_node("ride")
		if r == null or (ride != null and ride.riding()):
			_take_back()
		else:
			# main.gd and ride.gd turn the player's controls back on when their own reasons end.
			_lock_input()
			r.taken_focus = _holder.camera._focus_point()
	_apply_mouse()


## While an add-on has the camera and the player's controls, the events of its camera keys are
## kept from Zenith (E flies up instead of opening the inventory). Esc closes add-ons' windows
## first. The add-ons themselves get every event before this.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE and not menu_open():
		for m in running():
			var open: Array = m["object"].ui._open_windows()
			if not open.is_empty():
				m["object"].ui.show(open[-1], false)
				get_viewport().set_input_as_handled()
				return
	if _holder == null or not _holder_input or keys_blocked():
		return
	for action in _holder.keys._camera_actions():
		if event.is_action(action):
			get_viewport().set_input_as_handled()
			return


## Add-ons' keys are off while the player types or Zenith's menus are over the game.
func keys_blocked() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit or menu_open()


func menu_open() -> bool:
	var fe = main.get("front_end") if main != null else null
	return fe != null and is_instance_valid(fe) and fe.has_method("covers_game") and fe.covers_game()


func windows_open() -> bool:
	var hud = game_node("hud")
	if hud != null and hud.get("ui") != null and (hud.ui.is_open() or hud.ui.map_open()):
		return true
	for m in running():
		if not m["object"].ui._open_windows().is_empty():
			return true
	return false


## The mouse: captured for an add-on's mouse look, hidden with the interface, and visible
## whenever a menu or a window wants it. Left alone (first person keeps its own) otherwise.
func _apply_mouse() -> void:
	var want := ""
	if _holder != null and _holder.camera.mouse_captured():
		want = "captured"
	elif interface_hidden():
		want = "hidden"
	if want == "":
		_restore_mouse()
		return
	_mouse_managed = true
	var mode := Input.MOUSE_MODE_VISIBLE
	if not (menu_open() or windows_open()):
		mode = Input.MOUSE_MODE_CAPTURED if want == "captured" else Input.MOUSE_MODE_HIDDEN
	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func _restore_mouse() -> void:
	if not _mouse_managed:
		return
	_mouse_managed = false
	var r = rig()
	var fp: bool = r != null and r.first_person and not r.taken() and not menu_open()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if fp else Input.MOUSE_MODE_VISIBLE


# --- the interface, frames, the time of day ------------------------------------------------------

func request_hidden(api, on: bool) -> void:
	if on:
		_hidden_by[api.id] = true
	else:
		_hidden_by.erase(api.id)
	_apply_hidden()


func interface_hidden() -> bool:
	return not _hidden_by.is_empty()


## Hides every CanvasLayer of the game (the HUD and its windows, hover lines, the crosshair) but
## the ride's fade, and the hover outline; brings them back as they were.
func _apply_hidden() -> void:
	var hiding := interface_hidden() and _game_on
	var game = main.get("_game") if main != null and _game_on else null
	if hiding and _hidden_nodes.is_empty() and game is Node:
		var ride = game_node("ride")
		for n: Node in (game as Node).find_children("*", "CanvasLayer", true, false):
			var layer_node := n as CanvasLayer
			if ride != null and ride.is_ancestor_of(layer_node):
				continue
			_hidden_nodes.append([layer_node, layer_node.visible])
			layer_node.visible = false
		var input = game_node("input")
		if input != null and input.get("_clean_shot") != null:
			input.set("_clean_shot", true)  # no hover outline or selection
	elif not hiding and not _hidden_nodes.is_empty():
		for pair in _hidden_nodes:
			if is_instance_valid(pair[0]):
				(pair[0] as CanvasLayer).visible = bool(pair[1])
		_hidden_nodes.clear()
		var input = game_node("input")
		if input != null and input.get("_clean_shot") != null:
			input.set("_clean_shot", OS.get_cmdline_user_args().has("--clean-shot"))
	for m in running():
		m["object"].ui._interface_hidden(hiding)
	_apply_mouse()


func windows_changed() -> void:
	_apply_mouse()


func save_frame(path: String, viewport: Viewport) -> bool:
	var vp := viewport if viewport != null else get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		return false
	var image := tex.get_image()
	if image == null or image.is_empty():
		return false
	var target := path
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	_frame_tasks.append(WorkerThreadPool.add_task(func() -> void: image.save_png(target), false, "add-on frame"))
	return true


func frames_pending() -> int:
	return _frame_tasks.size()


func _finish_frames() -> void:
	for i in range(_frame_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_frame_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_frame_tasks[i])
			_frame_tasks.remove_at(i)


func _exit_tree() -> void:
	for t in _frame_tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_frame_tasks.clear()


func world_3d() -> World3D:
	return get_viewport().find_world_3d() if _game_on else null


func hold_daytime(api, daytime: float) -> void:
	var sky = main.get("_planet_sky") if main != null and _game_on else null
	if sky == null:
		return
	if daytime >= 0.0:
		if _daytime_by == "":
			_daytime_before = float(sky.forced_daytime)
		_daytime_by = api.id
		sky.forced_daytime = fposmod(daytime, 1.0)
	elif _daytime_by == api.id:
		_daytime_by = ""
		sky.forced_daytime = _daytime_before


func requests_changed() -> void:
	var g = game_node("ups_governor")
	if g != null:
		g.changed.emit()  # main.gd applies the settings again, through the governor and the requests


## The save the game was loaded from (its name), or the bridge's address; "" outside a game.
func save_key() -> String:
	if not _game_on or main == null:
		return ""
	var fe = main.get("front_end")
	if fe == null:
		return "game"
	var launcher = fe.get("launcher")
	if str(fe.get("session")) == "launched" and launcher != null and str(launcher.save_path) != "":
		return str(launcher.save_path).get_file().get_basename()
	var address := str(fe.get("session_address"))
	return "address " + address.replace(":", "-") if address != "" else "game"
