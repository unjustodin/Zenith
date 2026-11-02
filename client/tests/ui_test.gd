extends Node
## The Factorio-style UI without a server, played like a player with synthetic clicks and keys:
## picking up, splitting, swapping and putting back stacks, machine screens (moves, Shift
## transfers, status, fluids), number keys, quickbar pins and drops, the crafting queue, weapon
## slots, the health bar, the technology screen (T), Esc and F4, keys that mustn't reach buttons,
## the UI scale, the map (M, minimap, tags, chart requests, the map view's layers and switches), the
## settings store (one file, migration from ui.cfg / audio.cfg), the Settings window's tabs, key
## binding with modifiers, the map generator, the mods list, the model's hooks for the mod's data,
## and the Factorio parity controls (rebindable keys with modifiers, quickbar pages, statistics,
## chat, Alt-mode, the clipboard, inserter / splitter / chest bar / combinator / train stop screens,
## the item chooser, splitting transfers, crafting search), blueprints and planners (exchange
## strings, the library, the blueprint / book / planner windows, undo entries, the selection
## highlight, quality and book cycling), circuit settings, decider / selector / constant combinators
## in full, lamp colour, speaker, pump, turret targets, display panel messages, the wire tools,
## tiles, capsules, the rail planner and drag building, and the HUD's layout at common window sizes. The commands the UI sends are caught on a
## UDP socket of the test's own. Exits with 1 if a check fails.
##
##   godot --headless --path client res://tests/ui_test.tscn
##   godot --path client res://tests/ui_test.tscn -- <out.png>   also saves the HUD as a picture

const Hud := preload("res://scripts/ui/hud.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MachineScreen := preload("res://scripts/ui/factorio/machine_screen.gd")
const UiSettings := preload("res://scripts/ui/ui_settings.gd")
const Controls := preload("res://scripts/player/controls.gd")
const ControlsInfo := preload("res://scripts/menu/controls_info.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const SettingsWindow := preload("res://scripts/menu/settings_window.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")
const ColorFilter := preload("res://scripts/menu/color_filter.gd")
const PlayerInput := preload("res://scripts/player/player_input.gd")
const BeltLanesScript := preload("res://scripts/world/belt_lanes.gd")
const QualityMarksScript := preload("res://scripts/world/quality_marks.gd")
const AlertIconsScript := preload("res://scripts/ui/factorio/alert_icons.gd")
const EntityInfoScript := preload("res://scripts/ui/factorio/entity_info.gd")
const FluidsPowerScript := preload("res://scripts/world/fluids_power.gd")
const RoboportLinksScript := preload("res://scripts/world/roboport_links.gd")
const BeltItemsScript := preload("res://scripts/world/belt_items.gd")
const MapGen := preload("res://scripts/menu/map_gen.gd")
const MapGeneratorWindow := preload("res://scripts/menu/map_generator_window.gd")
const ModsWindow := preload("res://scripts/menu/mods_window.gd")
const ServerLauncher := preload("res://scripts/menu/server_launcher.gd")
const WorldMirror := preload("res://scripts/world/world.gd")
const ChunkView := preload("res://scripts/world/chunk_view.gd")
const AnimScript := preload("res://scripts/world/anim.gd")
const MoverLayer := preload("res://scripts/world/movers.gd")
const RemoteFog := preload("res://scripts/world/remote_fog.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const TurretLayer := preload("res://scripts/world/turrets.gd")
const CollectorLayer := preload("res://scripts/world/collectors.gd")
const CursorOverlay := preload("res://scripts/player/cursor_overlay.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const PlayerTags := preload("res://scripts/world/player_tags.gd")
const BpString := preload("res://scripts/ui/factorio/bp_string.gd")
const BpLibrary := preload("res://scripts/ui/factorio/bp_library.gd")
const ConsoleCommands := preload("res://scripts/ui/factorio/console_commands.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const SideMenu := preload("res://scripts/ui/factorio/side_menu.gd")
const CraftingPanel := preload("res://scripts/ui/factorio/crafting_panel.gd")
## A blueprint Factorio 2.1.23 exported (LuaItemStack.export_stack): three belts, an inserter, an
## iron chest and two stone path tiles, labelled "Belt to chest" with two icons and a description.
const FACTORIO_STRING := "0eNqVkt1ugzAMhV8l8nU6DQpT4XLPsLtpmgJYIxI4KHGnVYh3nwnrVtF2aq/yd/Qdx8cjVN0eB2+JoRyhwVB7O7B1BCW8tB5RVdhxUGgCK1E5ZUhZ70jVLQbW8UgBPaOXfaOMCuwI1WC4BQ22dhSgfB0h2A8y3exCpkfBszcUBud5M1vAJGJq8AvKZNIX5LPpJpqeSNPpTQMSW7a42MTD4Z32fYVeWPqKnYbBBbv8dARBPT7kGg5xFX5jPdbLazaXs8KmN2OTe7Dbm7HpPdjsF3uM6hy4vQZM0gvEXF+I5YyZnTDnoNh2Pymtex9lkvuRGmdoE2dodl/39D+5+FjGXm7/RltDZ6SPcvcs3VQyxceKP9GHCM6f0iLP0qzYFXmx3U3TN938Bso="
const WireTool := preload("res://scripts/player/wire_tool.gd")
const WireLayerScript := preload("res://scripts/world/wires.gd")
const CircuitPanel := preload("res://scripts/ui/factorio/circuit_panel.gd")
const TileBrush := preload("res://scripts/player/tile_brush.gd")
const RailPlanner := preload("res://scripts/player/rail_planner.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const TerrainTextures := preload("res://scripts/world/terrain_textures.gd")
const AltOverlay := preload("res://scripts/ui/factorio/alt_overlay.gd")
const DecorativeLayer := preload("res://scripts/world/decoratives.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const SunShadows := preload("res://scripts/world/sun_shadows.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const CharacterAnimScript := preload("res://scripts/player/character_anim.gd")
const CharacterPoseScript := preload("res://scripts/player/character_pose.gd")
const Avatar := preload("res://scripts/player/avatar.gd")
const Creatures := preload("res://scripts/world/creatures.gd")
const CameraRig := preload("res://scripts/player/camera_rig.gd")
const MapCache := preload("res://scripts/ui/factorio/map_cache.gd")
const UpsGovernor := preload("res://scripts/world/ups_governor.gd")
const TerritoryLayer := preload("res://scripts/world/territories.gd")
const DemolisherLayer := preload("res://scripts/world/demolishers.gd")
const VehicleAnim := preload("res://scripts/world/vehicle_anim.gd")
const MapLayersScript := preload("res://scripts/ui/factorio/map_layers.gd")
const PlatformPanel := preload("res://scripts/ui/factorio/platform_panel.gd")
const Ride := preload("res://scripts/world/ride.gd")
const SpriteFx := preload("res://scripts/fx/sprite_fx.gd")
const WeaponFx := preload("res://scripts/fx/weapon_fx.gd")
const SoundBank := preload("res://scripts/fx/sound_bank.gd")

const TEST_SETTINGS := "user://ui-test-settings.cfg"

var fails := 0
## Catches what Bridge.send sends (see _catch_commands).
var _sink := PacketPeerUDP.new()


## Riding up from a silo, the hub, and down by cargo pod (ride.gd), fed `me` as the mod sends it.
func _check_ride(cam_rig, viewer, ui) -> void:
	var rider := Avatar.new()
	add_child(rider)
	rider.snap_to(Vector2(4, 1))
	viewer.avatar = rider
	cam_rig.target = rider
	var lock := Node.new()  # stands in for player_input: the ride turns its processing off
	add_child(lock)
	lock.set_process(true)
	var ride := Ride.new()
	ride.avatar = rider
	ride.rig = cam_rig
	ride.ui = ui
	ride.input = lock
	add_child(ride)
	var me := func(extra: Dictionary) -> Dictionary:
		var m := {"t": "me", "u": 7, "x": 0, "y": 0, "d": 0, "w": 0, "hp": 250, "q": 0}
		m.merge(extra, true)
		return ride.handle_me(m)
	var silo := Vector2(11.5, -0.5)
	var held: Dictionary = me.call({"x": 2944, "y": -1352, "pod": 50, "ps": "awaiting_launch", "up": 1, "gx": 2944, "gy": -128})
	check(ride.state == Ride.BOARDING and held["x"] == 4 * 256 and held["w"] == 1 and not lock.is_processing()
		and cam_rig.target != rider and cam_rig.in_cinematic(),
		"ride: the character walks into the rocket from where it stood, input locked, the camera on the silo")
	for i in 90:
		ride._process(1.0 / 60.0)
	check(ride.state == Ride.UP and not rider.visible, "ride: inside the rocket the character is hidden")
	me.call({"x": 2944, "y": -128 - 100 * 256, "pod": 50, "ps": "ascending", "up": 1, "gx": 2944, "gy": -128})
	for i in 60:
		ride._process(1.0 / 60.0)
	var climbed: float = ride._height
	me.call({"x": 2944, "y": -128 - 200 * 256, "pod": 50, "ps": "surface_transition", "up": 1, "gx": 2944, "gy": -128})
	for i in 60:
		ride._process(1.0 / 60.0)
	check(climbed > 80.0 and ride.fade() > 0.9, "ride: the rocket climbs on the game's height (%.0f tiles) and the view fades out high up" % climbed)
	me.call({"x": -40 * 256, "y": -40 * 256, "pod": 50, "ps": "descending", "up": 0, "gx": 0, "gy": 0})
	check(ride.state == Ride.ARRIVING and is_equal_approx(ride._height, 40.0), "ride: in space the pod comes down onto the hub")
	me.call({"x": 0, "y": 0, "hub": 44})
	for i in 10:
		ride._process(1.0 / 60.0)
	check(ride.state == Ride.IN_HUB and ui.remote and ui.in_hub() and lock.is_processing() and not rider.visible
		and not cam_rig.in_cinematic(), "in the hub: the remote view round it, input back, no avatar")
	ui.end_remote_view()
	check(ui.remote and ui.in_hub(), "in the hub: leaving the remote view comes back to the hub, not the character")
	check(ui._at_hub() and not ui.escape(), "in the hub: Esc on the hub itself goes on to the game menu")
	me.call({"x": -512, "y": 0, "pod": 51, "ps": "awaiting_launch", "up": 1, "gx": 0, "gy": 0})
	check(ride.state == Ride.LEAVING and not ui.in_hub() and not lock.is_processing(), "land: out of the hub into a pod, input locked")
	me.call({"x": 108 * 256, "y": -230 * 256, "pod": 51, "ps": "descending", "up": 0, "gx": 0, "gy": 0})
	me.call({"x": 0, "y": 0, "pod": 51, "ps": "descending", "up": 0, "gx": 0, "gy": 0})
	me.call({"x": -102, "y": -102})
	for i in 10:
		ride._process(1.0 / 60.0)
	check(ride.state == Ride.IDLE and rider.visible and cam_rig.target == rider and lock.is_processing() and not ui.remote
		and rider.ground_position().distance_to(Vector2(-0.4, -0.4)) < 0.05, "land: the character steps out where the pod came down")
	ride.queue_free()
	lock.queue_free()
	rider.queue_free()


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		fails += 1


func key(code: Key, shift := false, ctrl := false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.shift_pressed = shift
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	get_viewport().push_input(ev)


## Points the Bridge at a socket of the test's own, so sent commands can be checked and nothing
## goes to a real game.
func _catch_commands() -> void:
	_sink.bind(0, "127.0.0.1")
	var out := PacketPeerUDP.new()
	out.bind(0, "127.0.0.1")
	out.set_dest_address("127.0.0.1", _sink.get_local_port())
	Bridge._udp = out
	Bridge.bind_error = OK


## The commands sent since the last call (keep-alives left out).
func sent() -> Array:
	var out: Array = []
	while _sink.get_available_packet_count() > 0:
		var msg = JSON.parse_string(_sink.get_packet().get_string_from_utf8())
		if msg is Dictionary and msg.get("t", "") != "hello":
			out.append(msg)
	return out


## The first sent command of type `t`, or {}.
func sent_one(t: String) -> Dictionary:
	for msg in sent():
		if msg.get("t", "") == t:
			return msg
	return {}


func click_main(ui, index: int, button := MOUSE_BUTTON_LEFT, shift := false, ctrl := false) -> void:
	ui.window.slot_clicked.emit("main", index, button, shift, ctrl)


func _ready() -> void:
	_catch_commands()
	UiModel.save_path = "user://quickbar-test.cfg"  # leave the player's own pins alone
	# and every other setting: a file of the test's own, without the player's old ui.cfg / audio.cfg
	Settings.legacy = {}
	DirAccess.remove_absolute(TEST_SETTINGS)
	Settings.use_file(TEST_SETTINGS)
	FxSettings.load_settings()
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar cursor_item := \"\"\nvar cursor_slot := 0\nvar remembered: Array = []\nfunc hold(i: String, slot := 0) -> void:\n\tcursor_item = i\n\tcursor_slot = slot\nfunc remember_mod(h: int, what: String) -> void:\n\tremembered.append([h, what])\nvar cursor_tool := \"\"\nvar reselect_slot := 0\nfunc hold_tool(t: String) -> void:\n\tcursor_tool = t\n"
	gs.reload()
	var player: Node = gs.new()
	add_child(player)
	var hud: Hud = Hud.new()
	add_child(hud)
	await get_tree().process_frame
	var ui = hud.ui
	ui.player = player
	hud.set_inventory([["iron-plate", 60], ["transport-belt", 50]])
	hud.set_recipes(["iron-gear-wheel", "transport-belt"])
	check(hud.count_of("iron-plate") == 60, "count_of")
	check(ui.model.main_slots.size() == 80, "80 slots")
	for i in 10:
		ui.model.unpin(i)
	ui.toggle_inventory()
	check(ui.is_open(), "E opens the window")
	ui.window.slot_clicked.emit("main", 2, MOUSE_BUTTON_LEFT, false, false)
	check(player.cursor_item == "transport-belt", "inventory click picks up the stack")
	player.cursor_item = "transport-belt"
	key(KEY_3)
	await get_tree().process_frame
	check(ui.model.quickbar[2] == "transport-belt", "number key pins the held item")
	ui.window.hovered_item = "iron-plate"
	key(KEY_0)
	await get_tree().process_frame
	check(ui.model.quickbar[9] == "iron-plate", "number key pins the hovered item")
	ui.window.hovered_item = ""
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not ui.is_open(), "Esc closes the window")
	player.cursor_item = ""
	key(KEY_3)
	await get_tree().process_frame
	check(player.cursor_item == "transport-belt", "number key holds the pinned item")
	key(KEY_3)
	await get_tree().process_frame
	check(player.cursor_item == "", "again puts it away")
	ui._on_quickbar_clicked(4, MOUSE_BUTTON_LEFT)
	check(ui.model.quickbar[4] == "", "click on an empty slot with nothing held does nothing")
	player.cursor_item = "iron-plate"
	ui._on_quickbar_clicked(4, MOUSE_BUTTON_LEFT)
	check(ui.model.quickbar[4] == "iron-plate" and ui.model.quickbar[9] == "", "click pins the held item (moving it)")
	ui._on_quickbar_clicked(4, MOUSE_BUTTON_RIGHT)
	check(ui.model.quickbar[4] == "", "right click clears")
	ui.quickbar._slots[1].on_drop.call("iron-plate")
	check(ui.model.quickbar[1] == "iron-plate", "drop pins")
	await get_tree().process_frame
	check(ui.quickbar._slots[1].count == 60, "quickbar shows the count")
	hud.set_inventory([["transport-belt", 50]])
	await get_tree().process_frame
	check(ui.quickbar._slots[1].ghost, "quickbar slot fades when none are left")
	key(KEY_F4)
	await get_tree().process_frame
	check(ui.debug_overlay, "F4 toggles the debug overlay")
	ui.model.set_recipe_details([{"name": "iron-gear-wheel", "group": "intermediate-products", "ingredients": [["iron-plate", 2]]},
		{"name": "transport-belt", "group": "logistics", "ingredients": [["transport-belt", 1]]}], ["logistics", "intermediate-products"])
	check(ui.model.groups == ["logistics", "intermediate-products"], "groups from details")
	check(ui.model.recipe("iron-gear-wheel")["craftable"] == 0, "craftable from ingredients")
	check(ui.model.recipe("transport-belt")["craftable"] == 50, "craftable count")
	hud.set_recipes(["iron-gear-wheel", "transport-belt"])
	check(ui.model.recipe("iron-gear-wheel")["group"] == "intermediate-products", "names-only update keeps details")
	ui.model.set_inventory_slots([["iron-plate", 100], [], ["iron-plate", 20]], 90)
	check(ui.model.main_slots.size() == 90 and ui.model.count_of("iron-plate") == 120 and ui.model.has_slots, "slot data")
	hud.set_inventory([["coal", 5]])
	check(ui.model.count_of("coal") == 0, "inv ignored once slots arrive")
	# The mod's UI data messages (docs/PROTOCOL.md, "Factorio's windows") reach the model's setters.
	var m = ui.model
	m.handle({"t": "slots", "l": {"main": [["wood", 3], 0], "guns": [["pistol", 1], 0, 0]}})
	check(m.main_slots.size() == 2 and m.count_of("wood") == 3 and m.other_slots["guns"][0]["item"] == "pistol", "slots message")
	m.handle({"t": "rdet", "part": 1, "parts": 1, "l": [["iron-gear-wheel", 0.5, ["crafting"], "intermediate-products", "c",
		"intermediate-product", "a", "a", [["item", "iron-plate", 2]], [["item", "iron-gear-wheel", 1]]]]})
	m.handle({"t": "craftable", "l": [["iron-gear-wheel", 7]]})
	var gear: Dictionary = m.recipe("iron-gear-wheel")
	check(gear.get("craftable") == 7 and gear.get("energy") == 0.5 and gear.get("ingredients") == [["iron-plate", 2.0]], "rdet and craftable messages")
	m.handle({"t": "cq", "pr": 500, "l": [[1, "iron-gear-wheel", 3, 0]]})
	check(m.craft_queue_size == 3 and m.craft_queue[0]["progress"] == 0.5 and m.craft_queue[0]["index"] == 1, "cq message")
	m.handle({"t": "techs", "part": 1, "parts": 1, "l": [["automation", "a", [], [["automation-science-pack", 1]], 10, 10, 1, ""]]})
	m.handle({"t": "rs", "cur": "automation", "pr": 250, "q": []})
	check(m.techs.has("automation") and m.research == "automation" and m.research_progress == 0.25, "techs and rs messages")
	m.handle({"t": "chart", "cx": 1, "cy": -2, "n": 2, "pal": [[10, 20, 30], [204, 217, 204]], "px": [0, 0, 1, 0]})
	m.handle({"t": "chart", "cx": 5, "cy": 0, "n": 0})
	var chart: Image = m.map_charts.get(Vector2i(1, -2))
	check(chart != null and chart.get_width() == 2 and chart.get_pixel(0, 1).to_rgba32() == Color8(204, 217, 204).to_rgba32()
		and m.map_charts.has(Vector2i(5, 0)) and m.map_charts[Vector2i(5, 0)] == null, "chart messages")
	m.handle({"t": "tags", "l": [[3, 1280, -512, "base", "item", "iron-plate"]]})
	check(m.map_tags.size() == 1 and m.map_tags[0]["position"] == Vector2(5, -2) and m.map_tags[0]["icon_name"] == "iron-plate", "tags message")
	await _map(ui)
	m.handle({"t": "tr", "l": [[4, "wait_station", 0, -150, 900, "Iron", [700, 701]]]})
	check(m.trains.has(4) and m.trains[4]["speed"] == -0.15 and m.trains[4]["dest"] == "Iron" and m.train_of_unit.get(701) == 4, "tr message")
	m.handle({"t": "clog", "on": 0, "trash": 1, "l": [["iron-plate", 100, -1], ["wood", 5, 20, "rare"]]})
	check(m.char_requests.size() == 2 and m.char_requests[1]["quality"] == "rare" and m.char_requests[0]["max"] == -1
		and not m.char_requests_on and m.char_trash_unrequested, "clog message")
	check(m._request_list(m.char_requests) == [["iron-plate", 100, -1], ["wood", 5, 20, "rare"]], "requests go back on the wire as they came")
	m.handle({"t": "ln", "id": 3, "log": [1, 2], "con": [0, 4]})
	check(m.network.get("id") == 3 and m.network["construction"] == [0, 4], "ln message")
	m.handle({"t": "ln", "id": 0})
	m.handle({"t": "rc", "l": [800, 5, 4]})
	check(m.network.is_empty() and m.robot_cargo.get(800, {}).get("count") == 4, "ln outside a network, rc message")
	m.handle({"t": "planet", "name": "vulcanus", "props": {"gravity": 40}, "day": 5400, "always": 0, "mb": 200, "sol": 4000,
		"dusk": 250, "evening": 450, "morning": 550, "dawn": 750, "heat": [[12, 12.5]]})
	check(m.planet.get("name") == "vulcanus" and m.planet["solar"] == 4.0 and m.heating_radius.get(12) == 12.5, "planet message")
	m.handle({"t": "seg", "l": [[90, 7, [8, 512, 256, 250, 8, 1024, 256, 250]]]})
	check(m.demolishers.has(90) and m.demolishers[90]["segments"].size() == 2 and m.demolishers[90]["segments"][1]["position"] == Vector2(4, 1), "seg message")
	m.handle({"t": "pg", "l": [5, 256, 512, 500]})
	m.handle({"t": "legs", "l": [[6, [0, 0, 256, 256]]]})
	m.handle({"t": "fz", "l": [7]})
	m.handle({"t": "bf", "part": 1, "parts": 1, "l": [42, 750]})
	m.handle({"t": "cp", "l": [[9, "descending", "surface", "vulcanus"]]})
	check(m.plant_growth.get(Vector2(1, 2)) == 0.5 and m.legs[6].size() == 2 and m.frozen.has(7) and m.belt_freshness[42] == 0.75
		and m.cargo_pods[9]["surface"] == "vulcanus", "pg, legs, fz, bf and cp messages")
	check(m._slot_dicts([["yumako", 5, "normal", 640]])[0].get("freshness") == 0.64, "freshness in slots")
	var qb: Array = []
	qb.resize(100)
	qb.fill("")
	qb[12] = "iron-chest"
	m.handle({"t": "qb", "p": 2, "sel": 0, "held": "", "l": qb})
	check(m.server_quickbar and m.quickbar[2] == "iron-chest", "qb message shows its page")
	await _play(hud, player)
	await _parity(hud, player)
	await _hud(hud, player)
	await _info(hud, player)
	await _gear(hud, player)
	await _planners(hud, player)
	await _space(hud, player)
	await _world_marks(hud)
	await _wires(hud)
	await _build_tools(hud)
	await _menus()
	await _layout(hud)
	await _icons(hud)
	_turrets()
	_collectors()
	_asteroid_chunks()
	await _weapons()
	await _console(hud)
	await _performance()
	await _streaming()
	await _far_chunks()
	_ups_governor()
	_terrain()
	_gpu_anim()
	_belt_paths()
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().size() > 0 and OS.get_cmdline_user_args()[-1].ends_with(".png"):
		await _picture(hud, player)
	print("FAILS: %d" % fails)
	get_tree().quit(1 if fails else 0)


## Machines' moving parts and glow move in the model shader from their state (anim.gd setup_part
## and _write, factorio_material.gdshaderinc anim_vertex and anim_glow), written only when it
## changes. The shader's pose, worked out here the shader's way, follows what anim.gd did every
## frame before (spinning, cycling, rocking, pistons, the power switch, hatches, lit lamps, glow
## fading), nothing is written while nothing changes, `st` changes reach it, and a new epoch of the
## shader's clock moves the state over without a jump.
func _gpu_anim() -> void:
	var anim := AnimScript.new()
	add_child(anim)
	var dt := 1.0 / 1000.0  # the old per-frame sums at a fine step, so they meet the exact sums
	# [model, part kind, working from, working until]
	var cases := [["burner-mining-drill", "spin_drill", 0.5, 2.5], ["steam-engine", "spin_flywheel", 0.3, 1.6],
		["assembling-machine-1", "gear_am1_w", 0.2, 2.0], ["oil-refinery", "yoke_refinery", 0.4, 2.2],
		["recycler", "slide_recycler_panel", 0.5, 1.5], ["pumpjack", "rock_beam", 0.25, 2.0],
		["offshore-pump", "bob_b", 0.5, 2.5], ["power-switch", "switch", 0.5, 0.8],
		["rocket-silo", "door_silo_e", 0.2, 3.0], ["rail-signal", "lit_green", 0.5, 2.0]]
	var unit := 9000
	for case in cases:
		var part: ModelLibrary.AnimPart = null
		for p: ModelLibrary.AnimPart in ModelLibrary.parts_for(str(case[0])):
			if p.kind == case[1]:
				part = p
		# Models replaced by another project's (assets/models/fue5/) may not have our moving parts.
		if part == null and ModelLibrary._source(str(case[0])).contains("/assets/models/fue5/"):
			continue
		if part == null:
			check(false, "%s has a %s part" % [case[0], case[1]])
			continue
		unit += 1
		var working := {unit: 0}
		var base := Transform3D(Basis(Vector3.UP, 0.3), Vector3(10.5, 0.0, 20.5))
		var group := _anim_group(part, unit, base)
		AnimScript.place(group, anim, working)
		var corners: Array[Vector3] = []
		var box := part.mesh.get_aabb()
		for k in 8:
			corners.append(box.get_endpoint(k))
		var worst := 0.0
		var old_at := 0.0  # the old accumulators: radians, loops, piston phase, how far open
		var speed := 0.0
		var started := false
		var t := 0.0
		var sample := 0.25
		var c: Dictionary = ModelLibrary.CYCLES.get(part.kind, {})
		while t < 4.0:
			var on := t + dt > float(case[2]) and t + dt <= float(case[3])
			if on != (int(working[unit]) == 1):
				working[unit] = 1 if on else 0
				if part.kind == "door_silo_e":
					anim._linear(anim._state(unit), part, true, on)  # what _hatch does with a rocket near
				anim._write(group, 0, working)  # what state_changed does
			anim._process(dt)
			t += dt
			# The old way, one frame of dt.
			var amount := 0.0
			var goal := 1.0 if on else 0.0
			if on or started:
				started = true
				speed += (goal - speed) * (1.0 - exp(-dt / (AnimScript.SPIN_UP if on else AnimScript.SPIN_DOWN)))
				if not on and speed < 0.01:
					speed = 0.0
			match AnimScript.kind_of(group):
				AnimScript.KIND_TIMED:
					if not started:
						amount = 0.0
					elif not c.is_empty():
						old_at = fposmod(old_at + speed * dt / float(c.get("period", 1.0)), 1.0)
						var loop := old_at + float(c.get("phase", 0.0))
						amount = 0.5 - 0.5 * cos(loop * TAU)
						match c.get("wave", "out"):
							"swing":
								amount = sin(loop * TAU)
							"spin":
								amount = fposmod(loop, 1.0)
						amount *= float(c.get("angle", 1.0))
					elif part.kind.begins_with("rock_"):
						old_at = fposmod(old_at - speed * AnimScript.SPIN_SPEEDS["spin_crank"] * TAU * dt, TAU)
						amount = AnimScript.ROCK_AMPLITUDE * sin(old_at)
					elif AnimScript.BOB_PHASE.has(part.kind):
						old_at = fposmod(old_at + speed * float(AnimScript.BOB_SPEEDS.get(part.model, 1.0)) * TAU * dt, TAU)
						amount = (0.5 - 0.5 * cos(old_at + float(AnimScript.BOB_PHASE[part.kind]))) * minf(speed * 3.0, 1.0)
					else:
						old_at = fposmod(old_at - speed * AnimScript._turns(part.model, part.kind) * TAU * dt, TAU)
						amount = old_at
				AnimScript.KIND_SWITCH:
					old_at = move_toward(old_at, goal, AnimScript.SWITCH_SPEED * dt)
					amount = old_at
				AnimScript.KIND_HATCH:
					old_at = move_toward(old_at, goal, dt / float(ModelLibrary.HATCHES[part.kind].get("time", 1.0)))
					amount = old_at
				AnimScript.KIND_LIT:
					amount = 1.0 if on else 0.0
			if t >= sample:
				sample += 0.25
				var old_xf := base * part.turned(amount)
				for v in corners:
					worst = maxf(worst, (old_xf * v).distance_to(base * _shader_part_pos(part, group.customs[0], anim.clock(), v)))
		check(worst < 0.03, "%s's %s moves in the shader as anim.gd turned it every frame (worst %.4f tiles apart over 4 s)" % [case[0], case[1], worst])
	# A furnace's fire fades in and out with its working state, as it did frame by frame.
	var furnace := ModelLibrary.mesh_for("stone-furnace")
	var glow_group := _anim_group(null, 9500, Transform3D(Basis(), Vector3(4.0, 0.0, 4.0)), furnace)
	var glow_work := {9500: 0}
	AnimScript.place(glow_group, anim, glow_work)
	var level := 0.0
	var glow_worst := 0.0
	var glow_peak := 0.0
	var gt := 0.0
	while gt < 3.0:
		var lit := gt + dt > 0.5 and gt + dt <= 1.5
		if lit != (int(glow_work[9500]) == 1):
			glow_work[9500] = 1 if lit else 0
			anim._write(glow_group, 0, glow_work)
		anim._process(dt)
		gt += dt
		var goal := 1.0 if lit else 0.0
		level += (goal - level) * (1.0 - exp(-dt / (AnimScript.GLOW_UP if goal > level else AnimScript.GLOW_DOWN)))
		var shader_level := _shader_glow(glow_group.customs[0], anim.clock())
		glow_worst = maxf(glow_worst, absf(level - shader_level))
		glow_peak = maxf(glow_peak, shader_level)
	check(AnimScript.kind_of(glow_group) == AnimScript.KIND_GLOW and glow_worst < 0.02 and glow_peak > 0.95,
		"a furnace's fire glows in the shader as anim.gd eased it every frame (worst %.4f apart, up to %.2f)" % [glow_worst, glow_peak])
	# A roboport's door opens when its group next looks and finds a robot near, then the shader
	# slides it: nothing is written between looks.
	var door: ModelLibrary.AnimPart = null
	for p: ModelLibrary.AnimPart in ModelLibrary.parts_for("roboport"):
		if p.kind == "door_n":
			door = p
	var robots := FakeRobots.new()
	anim.movers = robots
	if door == null:  # FUE5's roboport has no doors
		print("skip a roboport's door: its model has none")
	else:
		_check_roboport_door(anim, door)
	robots.queue_free()
	anim.queue_free()
	await _gpu_anim_world()


func _check_roboport_door(anim: AnimScript, door: ModelLibrary.AnimPart) -> void:
	var door_group := _anim_group(door, 9700, Transform3D(Basis(), Vector3(30.0, 0.0, 30.0)))
	AnimScript.place(door_group, anim, {})
	var shut := door_group.customs[0]
	for k in 12:  # 0.2 s: past the group's first look
		anim._roboport(door_group, 1.0 / 60.0)
	var opened := door_group.customs[0]
	var door_writes := anim.writes
	for k in 30:
		anim._process(1.0 / 60.0)
		anim._roboport(door_group, 1.0 / 60.0)
	var top := door.mesh.get_aabb().get_endpoint(7)
	var slid := _shader_part_pos(door, door_group.customs[0], anim.clock(), top) - top
	check(floori(-shut.b - 1.0) % 2 == 0 and floori(-opened.b - 1.0) % 2 == 1 and anim.writes == door_writes
		and slid.distance_to(door.slide * AnimScript.DOOR_TRAVEL) < 0.01,
		"a roboport's door opens for a robot near at its group's look and slides open in the shader (%s, %d writes after)" % [slid, anim.writes - door_writes])


func _gpu_anim_world() -> void:
	# In a world: `st` reaches the parts, nothing is written frame to frame, and a new epoch moves
	# every state onto the newer clock without a jump.
	var world := WorldMirror.new()
	add_child(world)
	var cv := ChunkView.new()
	cv.coord = Vector2i(0, 0)
	world.chunks[cv.coord] = cv
	world.add_child(cv)
	var rec := WorldMirror.Rec.new()
	rec.key = 9600
	rec.unit = 9600
	rec.pos = Vector2(5.5, 5.5)
	world.entities[9600] = rec
	var drill: ModelLibrary.AnimPart = null
	for p: ModelLibrary.AnimPart in ModelLibrary.parts_for("burner-mining-drill"):
		if p.kind == "spin_drill":
			drill = p
	var dgroup := _anim_group(drill, 9600, Transform3D(Basis(), Vector3(5.5, 0.0, 5.5)))
	AnimScript.place(dgroup, world.animator, world.working)
	cv.anim_groups.append(dgroup)
	world._on_states([9600, 1])
	var on_custom := dgroup.customs[0]
	var writes: int = world.animator.writes
	for k in 30:
		world.animator._process(1.0 / 60.0)
	check(floori(-on_custom.b - 1.0) % 2 == 1 and world.animator.writes == writes and dgroup.customs[0] == on_custom,
		"`st` turns a drill's part on in its custom data, and half a second of frames writes nothing (%d writes)" % (world.animator.writes - writes))
	var probe := drill.mesh.get_aabb().get_endpoint(7)
	world.animator._time = AnimScript.EPOCH - 0.004
	world.animator._process(0.0)
	var even_custom := dgroup.customs[0]
	world.animator._process(0.008)  # into the next epoch: migrated this frame
	# Where the drill is drawn now from its state on the odd clock, and from its state on the even
	# one (still running for an epoch): the same place.
	var after := _shader_part_pos(drill, dgroup.customs[0], world.animator.clock(), probe)
	var unmoved := _shader_part_pos(drill, even_custom, world.animator.clock(), probe)
	var parity := floori((-dgroup.customs[0].b - 1.0) / 2.0) % 2
	check(parity == 1 and dgroup.epoch == 1 and after.distance_to(unmoved) < 0.005 and after.distance_to(probe) > 0.0,
		"a new epoch of the shader's clock moves the drill onto the odd clock without a jump (%.5f tiles)" % after.distance_to(unmoved))
	world.queue_free()


## movers.gd's answer to roboports: a robot is always near.
class FakeRobots extends Node:
	func robot_near(_from: Vector3, _radius: float) -> bool:
		return true


## A Group of one instance of `part` (or a glowing model's `mesh`), as chunk_view.gd makes them.
func _anim_group(part: ModelLibrary.AnimPart, unit: int, base: Transform3D, mesh: Mesh = null) -> AnimScript.Group:
	var group := AnimScript.Group.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = part.mesh if part != null else mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, base)
	group.mm = mm
	group.part = part
	group.keys.append(unit)
	group.units.append(unit)
	group.bases.append(Transform3D(Basis(), base.origin) if part != null and part.upright else base)
	group.stateful.append(1)
	group.customs.append(Color(base.origin.x, base.origin.z, 0.0, 1.0))
	return group


## Where the model shader draws vertex v of a timed part (factorio_material.gdshaderinc
## anim_vertex, the same sums), in model space.
static func _shader_part_pos(part: ModelLibrary.AnimPart, c: Color, clock: Vector2, v: Vector3) -> Vector3:
	var m := part.mesh.surface_get_material(0) as ShaderMaterial
	var mode := int(m.get_shader_parameter("anim_mode"))
	if mode == 0 or c.b >= -0.5:
		return v
	var code := -c.b - 1.0
	var flags := floori(code)
	var s0 := code - flags
	var on := flags % 2 == 1
	var dt := maxf((clock.y if floori(flags / 2.0) % 2 == 1 else clock.x) - c.r, 0.0)
	if mode == 5:
		return v if on else v * 0.001
	var amount := float(m.get_shader_parameter("anim_amount"))
	var x := 0.0
	if mode == 6:
		x = move_toward(c.g, float(m.get_shader_parameter("anim_open")) if on else 0.0, float(m.get_shader_parameter("anim_speed")) * dt) * amount
	else:
		var goal := 1.0 if on else 0.0
		var tau := 0.35 if on else 0.9
		var e := exp(-dt / tau)
		var speed := goal + (s0 - goal) * e
		var loops := c.g + float(m.get_shader_parameter("anim_rate")) * (goal * dt + (s0 - goal) * tau * (1.0 - e))
		if mode == 1:
			x = fposmod(loops, 1.0) * TAU
		elif mode == 2:
			var wave := int(m.get_shader_parameter("anim_wave"))
			x = (sin(loops * TAU) if wave == 1 else (fposmod(loops, 1.0) if wave == 2 else 0.5 - 0.5 * cos(loops * TAU))) * amount
		elif mode == 3:
			x = amount * sin(loops * TAU)
		else:
			x = (0.5 - 0.5 * cos(loops * TAU)) * minf(speed * 3.0, 1.0)
	var slide: Vector3 = m.get_shader_parameter("anim_slide")
	if slide != Vector3.ZERO:
		return v + slide * x
	var a: Vector3 = m.get_shader_parameter("anim_axis")
	var pivot := Transform3D(m.get_shader_parameter("anim_pivot") as Projection)
	var p := Transform3D(m.get_shader_parameter("anim_unpivot") as Projection) * v
	p = p * cos(x) + a.cross(p) * sin(x) + a * a.dot(p) * (1.0 - cos(x))
	return pivot * p


## How much the model shader has a timed glowing instance glow (anim_glow, a static model's).
static func _shader_glow(c: Color, clock: Vector2) -> float:
	var flags := floori(-c.b - 1.0)
	var dt := maxf((clock.y if floori(flags / 2.0) % 2 == 1 else clock.x) - c.r, 0.0)
	var goal := 1.0 if floori(flags / 4.0) % 2 == 1 else 0.0
	return goal + (c.a - goal) * exp(-dt / (AnimScript.GLOW_UP if goal > 0.5 else AnimScript.GLOW_DOWN))

## Owner: items on belts floated off them on a dense base, gliding in straight lines between updates
## across curves, over splitters and undergrounds. Two items recorded on a real 2.1.23 belt
## (tests/belt_paths_2.1.23.json: a right and a left curve, a splitter, an underground; one on each
## lane, every tick) are fed as the mod sends them, every 6 and every 24 ticks. Drawn, they stay on
## their own track (a splitter's jump across halves aside), out of sight under the ground, and their
## paths reach the GPU as the shader reads them; in straight lines they cut the curve.
func _belt_paths() -> void:
	var fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/belt_paths_2.1.23.json"))
	var protos := ProtoDB.new()
	protos.add_entities([[1, "transport-belt", "transport-belt", -0.5, -0.5, 0.5, 0.5, 200, 170, 50, 1, 1],
		[2, "underground-belt", "underground-belt", -0.5, -0.5, 0.5, 0.5, 200, 170, 50, 1, 1],
		[3, "splitter", "splitter", -0.9, -0.5, 0.9, 0.5, 200, 170, 50, 2, 1]])
	protos.add_items([[1, ""]])
	var ids := {"transport-belt": 1, "underground-belt": 2, "splitter": 3}
	var recs: Array = []
	for b in fx["belts"]:
		var r := WorldMirror.Rec.new()
		r.unit = recs.size() + 1
		r.key = r.unit
		r.proto_id = ids[str(b[0])]
		r.pos = Vector2(float(b[2]), float(b[3]))
		r.dir = int(b[4])
		if str(b[1]) == "transport-belt":
			r.extra = {"s": str(b[5])}
		elif str(b[1]) == "underground-belt":
			r.extra = {"u": str(b[5])}
		r.chunk = WorldMirror.chunk_of(r.pos)
		recs.append(r)
	var tracks := {}  # uid -> {tick: Vector3(x, y, flags)}
	var last := 0
	for tr in fx["tracks"]:
		var by := {}
		var l: Array = tr[1]
		for i in range(0, l.size() - 3, 4):
			by[int(l[i])] = Vector3(l[i + 1] / 256.0, l[i + 2] / 256.0, int(l[i + 3]))
			last = maxi(last, int(l[i]))
		tracks[int(tr[0])] = by
	# Off its own track, over the ticks round `tick`: the nearest segment between two places in sight.
	var off := func(track: Dictionary, p: Vector2, tick: int) -> float:
		var best := INF
		for t in range(maxi(tick - 80, 0), tick + 4):
			var a = track.get(t)
			var b = track.get(t + 1)
			if a == null or b == null or (int(a.z) & 1) != 0 or (int(b.z) & 1) != 0:
				continue
			var pa := Vector2(a.x, a.y)
			var ab := Vector2(b.x, b.y) - pa
			var u := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			best = minf(best, p.distance_to(pa + ab * u))
		return best
	for run in [[6, true], [24, true], [48, false]]:
		var period: int = run[0]
		var items = BeltItemsScript.new()
		items.protos = protos
		add_child(items)
		items._sync = true
		if run[1]:
			items.index_chunk(Vector2i(0, 0), recs)
		var worst := 0.0  # off its track, away from the splitter
		var on_curve := 0.0  # off its track on the right curve
		var on_splitter := 0.0
		var over_gap := 0  # shown between the underground's ends
		var hidden := 0
		var gpu_ok := true
		var gpu_paths := 0
		for tick in range(0, last + 1):
			if tick % period == 0:
				var l: Array = []
				for uid in tracks:
					var at = tracks[uid].get(tick)
					if at != null and (int(at.z) & 2) == 0:  # the mod sends what is inside a belt
						l.append_array([uid, 1, roundi(at.x * 256), roundi(at.y * 256)])
				items.handle({"t": "bi", "k": 1000 + tick, "p": period, "fx": 8 * 256, "fy": 24 * 256, "fr": 16, "l": l})
			items._process(1.0 / 60.0)
			for uid in tracks:
				var known: bool = items._positions.has(uid)
				var p = items.position_of(uid)
				if not known:
					continue
				if p == null:
					hidden += 1
					continue
				var at := Vector2(p.x, p.z)
				var d: float = off.call(tracks[uid], at, tick)
				if at.x > 5.0 and at.x < 6.0 and at.y > 22.0 and at.y < 24.0:
					on_splitter = maxf(on_splitter, d)
				else:
					worst = maxf(worst, d)
				if at.x > 3.0 and at.x < 4.0 and at.y > 20.0 and at.y < 21.0:
					on_curve = maxf(on_curve, d)
				if at.x > 7.6 and at.x < 10.4 and at.y > 23.0 and at.y < 24.0:
					over_gap += 1
				# What the shader reads: the slot's code points at the item's path in the texture.
				var path: PackedFloat32Array = items._positions[uid][2]
				var it = items._state.items.get(uid)
				if path.size() >= 8 and it != null and it.slot >= 0 and items._paths_image != null:
					var code := int(items._state.kinds[1].buf[it.slot * BeltItemsScript.STRIDE + 15]) - 1
					var img: Image = items._paths_image
					var first := code / 64
					var n := code % 64 + 2
					var k := n - 1
					var tex := img.get_pixel((first + k) % img.get_width(), (first + k) / img.get_width())
					gpu_paths += 1
					if n != path.size() / 4 or absf(tex.r - path[k * 4]) > 0.001 or absf(tex.b - path[k * 4 + 2]) > 0.001:
						gpu_ok = false
		if run[1]:
			check(worst < 0.1 and on_splitter < 0.3 and over_gap == 0 and hidden > 0,
				"belt items every %d ticks follow their lanes: at most %.3f tiles off their track (%.3f on the curve, %.3f switching a splitter's halves), out of sight under the ground (%d frames), never over its gap (%d)"
				% [period, worst, on_curve, on_splitter, hidden, over_gap])
			check(gpu_ok and gpu_paths > 0, "the paths of items that turn reach the shader: each slot's code points at its points in the texture (%d checked)" % gpu_paths)
		else:
			check(on_curve > 0.15 and hidden == 0,
				"in straight lines (no belts known), every %d ticks the same items cut the curve by %.3f tiles and never go out of sight" % [period, on_curve])
		items.queue_free()


## Gleba's and Aquilo's ground. Water is told by its collision mask (the wetlands, the
## deep lake, brash ice, the ammoniacal ocean), `layer = gleba_tile_offset + 8` is worked out so
## the planets' tiles blend in Factorio's order, the water shaders' own pictures fill the swamps
## and brash ice, and a surface change makes room in the layer table.
func _terrain() -> void:
	var db := ProtoDB.new()
	db.add_tiles([[0, "ammoniacal-ocean", 15, 13, 25], [1, "gleba-deep-lake", 18, 37, 51], [2, "snow-flat", 190, 194, 197], [3, "water", 51, 83, 95]])
	check(db.is_water(0) and db.is_water(1) and not db.is_water(2) and db.is_water(3), "Aquilo's ocean and Gleba's deep lake are water, snow isn't")
	check(TerrainTextures._sum("gleba_lowland_tile_offset+4", {"gleba_lowland_tile_offset": 32}) == 36
		and TerrainTextures._sum("aquilo_tile_offset_frozen + 2", {"aquilo_tile_offset_frozen": 50}) == 52
		and TerrainTextures._sum("7", {}) == 7, "a tile's layer from its file's constants")
	check(TerrainTextures._rgb("r = 46, g = 45, b = 51").is_equal_approx(Color8(46, 45, 51))
		and TerrainTextures._rgb("15, 13, 25 ").is_equal_approx(Color8(15, 13, 25)), "map colours both ways Factorio writes them")
	if ItemIcons.find_data_dir() != "" and not TerrainTextures.disabled:
		var names := ["lowland-olive-blubber", "midland-cracked-lichen", "wetland-yumako", "wetland-light-dead-skin", "wetland-dead-skin",
			"gleba-deep-lake", "brash-ice", "ammoniacal-ocean", "snow-flat", "ice-smooth", "frozen-concrete"]
		for n in names:
			TerrainTextures.lookup(n)
		TerrainTextures.finish_all()
		var g := {}
		for n in names:
			g[n] = TerrainTextures.peek(n)
		var all := true
		for n in names:
			all = all and g[n] != null and g[n].layer >= 0
		check(all, "every Gleba and Aquilo tile tried has a picture: %s" % [names.filter(func(n): return g[n] == null or g[n].layer < 0)])
		if all:
			check(g["lowland-olive-blubber"].priority < g["midland-cracked-lichen"].priority and g["lowland-olive-blubber"].spills
				and g["snow-flat"].priority != g["ice-smooth"].priority,
				"lowlands lie under midlands and blend; snow and smooth ice no longer share one priority (hard square edges)")
			check(TerrainTextures.is_water_tile("wetland-yumako") and g["wetland-yumako"].water and g["brash-ice"].water and g["ammoniacal-ocean"].water,
				"wetlands, brash ice and the ammoniacal ocean are drawn as water")
			check(g["wetland-yumako"].material == Vector2i(32, 16) and g["brash-ice"].material == Vector2i(32, 16)
				and g["wetland-yumako"].reflect < 1.0, "swamps and brash ice wear their water shader's whole picture, murky")
			var light: Image = TerrainTextures._images[g["wetland-light-dead-skin"].layer].duplicate()
			var dark: Image = TerrainTextures._images[g["wetland-dead-skin"].layer].duplicate()
			var brash: Image = TerrainTextures._images[g["brash-ice"].layer].duplicate()
			for im: Image in [light, dark, brash]:
				if im.is_compressed():
					im.decompress()
			check(TerrainTextures._mean_luma(light) > TerrainTextures._mean_luma(dark), "light dead skin is lighter than dead skin, as their map colours")
			var repeats := 0
			for i in 31:
				if brash.get_region(Rect2i(i * 64, 0, 64, 64)).get_data() == brash.get_region(Rect2i(i * 64 + 64, 0, 64, 64)).get_data():
					repeats += 1
			check(repeats == 0, "brash ice isn't one square repeated (its low alpha passed for empty slots): %d" % repeats)
			var ocean: TerrainTextures.TileGfx = g["ammoniacal-ocean"]
			check(ocean.tint.b < 0.5 and ocean.tint.r < 0.5, "the ammoniacal ocean is water's picture darkened to its map colour: %s" % ocean.tint)
	# A session that visits every planet runs out of layers unless a surface change makes room.
	var gen := TerrainTextures.generation
	while TerrainTextures.layer_count() < TerrainTextures.TRIM_LAYERS:
		TerrainTextures._images.append(Image.create_empty(4, 4, false, Image.FORMAT_RGB8))
		TerrainTextures._infos.append(Color(0, 1, 1, 1))
		TerrainTextures._reflects.append(1.0)
	check(TerrainTextures.trim() and TerrainTextures.layer_count() == 0 and TerrainTextures.generation > gen
		and TerrainTextures.peek("snow-flat") == null, "a surface change with many layers in use drops them all")
	check(not TerrainTextures.trim(), "and with few in use keeps them")


## Walking on a big base (stutters as chunks stream in): a chunk built again fills its MultiMeshes
## in place, new ones are added within a frame's budget, shadows change only what changes, chunks
## let go of are freed a few a frame, the minimap's layers move with the view instead of being drawn
## again, and the map's pictures are read as bytes.
func _streaming() -> void:
	var protos := ProtoDB.new()
	protos.add_entities([[1, "zz-test-box", "container", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[2, "zz-test-plant", "plant", -0.5, -0.5, 0.5, 0.5, 30, 160, 30, 1, 1]])
	var cv := ChunkView.new()
	add_child(cv)
	var add := func(unit: int, proto: int, x: float) -> void:
		var r := WorldMirror.Rec.new()
		r.key = unit
		r.unit = unit
		r.proto_id = proto
		r.pos = Vector2(x, 3.5)
		cv.entities[unit] = r
	add.call(1, 1, 1.5)
	add.call(2, 2, 3.5)
	var budget := ChunkView.Budget.new(1)
	cv.build_entities(protos, {}, null, budget)
	check(cv._instances.size() == 1 and cv.pending.size() == 1 and budget.left <= 0,
		"a new chunk adds MultiMeshes only within the frame's budget, the rest waits (%d drawn, %d waiting)" % [cv._instances.size(), cv.pending.size()])
	check(cv.add_pending({}, null, ChunkView.Budget.new(10)) and cv._instances.size() == 2 and cv.pending.is_empty(),
		"and adds the rest on a later frame")
	var before := cv._instances.duplicate()
	add.call(3, 1, 5.5)
	cv.build_entities(protos, {}, null, ChunkView.Budget.new(0))
	var box: MultiMeshInstance3D = cv._nodes.get("box")
	check(cv._instances.size() == 2 and before.has(cv._instances[0]) and before.has(cv._instances[1]) and box != null
		and box.multimesh.instance_count == 2 and cv.pending.is_empty(),
		"built again (an entity added), the chunk fills the MultiMeshes it has in place, with no budget left")
	cv.entities.erase(2)
	cv.build_entities(protos, {})
	check(cv._instances.size() == 1 and cv._nodes.has("box") and not cv._nodes.has("cone"),
		"a MultiMesh nothing uses any more goes")
	cv.set_shadow_tier(ChunkView.SHADOWS_NONE)
	check(box.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "a chunk with no shadows to cast turns its own off")
	cv.set_shadow_tier(ChunkView.SHADOWS_NEAR)
	check(box.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and cv._unready == 0,
		"and on again near the camera; nothing waits for a stand-in, so more stand-ins being ready skips it")
	cv.queue_free()
	# Chunks let go of are freed within a time budget (a whole row goes at once when walking, all of
	# them on a respawn), and a reset hides them at once.
	var w := WorldMirror.new()
	add_child(w)
	var gone: Array = []
	for i in 5:
		var c := Vector2i(i, 0)
		var ucv := ChunkView.new()
		ucv.coord = c
		w.chunks[c] = ucv
		w.add_child(ucv)
		gone.append(ucv)
	for i in 3:
		w._unload(Vector2i(i, 0))
	var left_now := gone.filter(func(n) -> bool: return is_instance_valid(n)).size()
	w.reset(true)
	var hidden: bool = not gone[3].visible and not gone[4].visible
	for f in 10:
		w._free_unloaded()
	check(w.chunks.is_empty() and left_now == gone.size() and hidden and gone.all(func(n) -> bool: return not is_instance_valid(n)),
		"chunks let go of (unloaded, or all on a reset, hidden at once) are freed over the next frames (%d kept at first)" % left_now)
	w.queue_free()
	# An item seen for the first time: its model is read on a thread, its kind hidden until then.
	var fresh_item := ""
	for file in DirAccess.get_files_at("res://assets/models/items/"):
		if file.ends_with(".glb") and not preload("res://scripts/world/item_models.gd")._cache.has(file.get_basename()):
			fresh_item = file.get_basename()
			break
	var cards = preload("res://scripts/world/item_cards.gd").new()
	cards.protos = ProtoDB.new()
	cards.protos.add_items([[77, fresh_item]])
	add_child(cards)
	cards.draw({77: [Vector3(1, 0, 1)]})
	var waited_hidden: bool = not cards._kinds[77].visible
	var until := Time.get_ticks_msec() + 10000
	while not cards._kinds[77].visible and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	check(fresh_item != "" and waited_hidden and cards._kinds[77].visible
		and cards._kinds[77].multimesh.mesh == preload("res://scripts/world/item_models.gd").mesh_for(fresh_item)
		and cards._kinds[77].multimesh.visible_instance_count == 1,
		"an item's model is read on a thread the first time it is seen (%s), drawn once it is" % fresh_item)
	cards.queue_free()
	# The map's pictures from their palette, as bytes: the same as a pixel at a time.
	var pal := [[255, 0, 0], [0, 128, 255], "bad"]
	var px := [0, 1, 2, 7, 1, 0, 0, 1, 1]
	var img: Image = UiModel.chart_image(3, pal, px)
	check(img.get_pixel(0, 0) == Color8(255, 0, 0) and img.get_pixel(1, 0) == Color8(0, 128, 255) and img.get_pixel(2, 0) == Color8(0, 0, 0)
		and img.get_pixel(0, 1) == Color8(0, 0, 0) and img.get_pixel(2, 2) == Color8(0, 128, 255),
		"a chart's picture: palette colours where known, black where the index has none")
	# The minimap's layers move with the view; drawn again past SHIFT_PX, a new zoom or new data.
	var layers := MapLayersScript.new()
	layers.size = Vector2(200, 200)
	add_child(layers)
	layers.follow(Vector2(100, 100), 2.0, true)
	var marks_at := layers.marks.position
	layers.follow(Vector2(105, 100), 2.0, false)
	var shifted := layers.marks.position
	layers.follow(Vector2(130, 100), 2.0, false)
	check(marks_at == Vector2.ZERO and shifted == Vector2(-10, 0) and layers.centre == Vector2(130, 100) and layers.marks.position == Vector2.ZERO,
		"the minimap's layers move 10 px for 5 tiles at 2 px a tile, and are drawn again 30 tiles on (%s, %s)" % [shifted, layers.centre])
	layers.follow(Vector2(131, 100), 2.0, true)
	check(layers.centre == Vector2(130, 100) and layers.marks.position == Vector2(-2, 0),
		"new data waits a moment rather than being drawn every frame")
	layers.queue_free()


## Far chunks merged (far_chunks.gd): a chunk going far keeps its MultiMeshes until its merged mesh
## is made, then hides them without a build; trees keep theirs; coming near again before anything
## changed shows them again at once; what it holds changing lets them go and merges again; picking
## still finds its entities; coming near after that, its MultiMeshes are made again and the merged
## mesh goes once they are all in. Bakes and merges run on worker threads, so this waits for them.
func _far_chunks() -> void:
	var w := WorldMirror.new()
	add_child(w)
	w.protos.add_entities([[1, "steel-chest", "container", -0.35, -0.35, 0.35, 0.35, 200, 180, 0, 1, 1],
		[2, "zz-test-box", "container", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[3, "tree-01", "tree", -0.4, -0.4, 0.4, 0.4, 30, 160, 30, 1, 1]])
	# Made now rather than on a worker, so the first build draws them.
	ModelLibrary.mesh_for_entity("steel-chest", "container", {}, 0)
	var tree_mesh := ModelLibrary.mesh_for_entity("tree-01", "tree", {}, 0)
	var c := Vector2i(12, 0)  # 384 tiles from the focus at the origin: far from any camera there
	var cv := ChunkView.new()
	cv.coord = c
	cv.loaded = true
	w.chunks[c] = cv
	w.add_child(cv)
	var add := func(unit: int, proto: int, x: float) -> void:
		var r := WorldMirror.Rec.new()
		r.key = unit
		r.unit = unit
		r.proto_id = proto
		r.pos = Vector2(c.x * 32 + x, 3.5)
		r.chunk = c
		cv.entities[unit] = r
		w.entities[unit] = r
	add.call(1, 1, 1.5)
	add.call(2, 2, 3.5)
	add.call(3, 3, 5.5)
	var fc = w.far_chunks
	var shown := func() -> int: return cv._instances.filter(func(m: MultiMeshInstance3D) -> bool: return m.visible).size()
	var wait_merged := func() -> void:
		var until := Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < until and not (cv.far.node != null and cv.far.node.visible and cv.far.phase == 0):
			await get_tree().process_frame
	fc.enabled = false
	cv.build_entities(w.protos, {})
	check(cv._instances.size() == 3 and not cv.far.far and cv.far.full, "a chunk is built in full while merging is off: %d MultiMeshes" % cv._instances.size())
	# Merging on: far, its merged mesh is made on workers and its MultiMeshes are hidden, not rebuilt.
	fc.enabled = true
	var kept_meanwhile := true
	var until := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until and not (cv.far.node != null and cv.far.node.visible):
		kept_meanwhile = kept_meanwhile and shown.call() == 3
		await get_tree().process_frame
	var node: MeshInstance3D = cv.far.node
	var mesh: ArrayMesh = node.mesh if node != null else null
	check(cv.far.far and node != null and node.visible and kept_meanwhile and mesh != null and mesh.get_surface_count() == 1
		and (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0 and mesh.surface_get_material(0) == fc.material(),
		"far, its buildings become one surface with the colours in its vertices and the shared material, the MultiMeshes drawn until it was made")
	var tree_mmi: MultiMeshInstance3D = cv._nodes.get(tree_mesh)
	check(shown.call() == 1 and tree_mmi != null and tree_mmi.visible and cv.far.hidden.size() == 2 and not w._dirty.has(c),
		"the chest's and the placeholder's MultiMeshes are hidden, with no build; the tree keeps its own: %d shown" % shown.call())
	cv.set_shadow_tier(ChunkView.SHADOWS_NONE)
	var no_shadow := node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cv.set_shadow_tier(ChunkView.SHADOWS_FAR)
	check(no_shadow and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"the merged mesh casts the chunk's shadows where they can reach the view, and none beyond")
	check(w.pick(Vector2(c.x * 32 + 1.5, 3.5)) == cv.entities[1], "picking still finds a merged building")
	# The focus walks up before anything changed: the MultiMeshes are shown again, at once.
	w.set_focus(Vector2(c.x * 32 + 16, 16))
	until = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and cv.far.far:
		await get_tree().process_frame
	check(not cv.far.far and shown.call() == 3 and cv.far.node == null and cv.far.hidden.is_empty() and not w._dirty.has(c),
		"near again with nothing changed: its MultiMeshes are shown again and the merged mesh goes, with no build")
	# Away again, then something built there: the build lets the hidden MultiMeshes go and merges again.
	w.set_focus(Vector2.ZERO)
	await wait_merged.call()
	node = cv.far.node
	var one: int = cv.far.triangles
	add.call(4, 1, 7.5)
	cv.build_entities(w.protos, {})
	check(node != null and node.visible and cv._instances.size() == 1 and cv.far.hidden.is_empty() and not cv.far.full,
		"a building added far away lets the hidden MultiMeshes go; the old merged mesh stays meanwhile")
	until = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until and cv.far.triangles == one:
		await get_tree().process_frame
	check(cv.far.triangles > one and cv.far.node == node, "and the merged mesh is made again with it (%d -> %d triangles)" % [one, cv.far.triangles])
	# Near after that: its MultiMeshes are made within the budget, the merged mesh drawn until the last is in.
	w.set_focus(Vector2(c.x * 32 + 16, 16))
	until = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < until and not w._dirty.has(c):
		await get_tree().process_frame
	w._dirty.erase(c)
	cv.build_entities(w.protos, {}, null, ChunkView.Budget.new(1))
	check(not cv.far.far and not cv.pending.is_empty() and is_instance_valid(node) and node.visible,
		"near again after a change, the chunk is built in full; the merged mesh stays while MultiMeshes are still to come")
	cv.add_pending({}, null, ChunkView.Budget.new(100))
	check(shown.call() == 3 and cv.far.node == null and cv.far.full,
		"and goes once they are all in (%d shown, merged mesh %s, full %s)" % [shown.call(), cv.far.node, cv.far.full])
	w.queue_free()


## Feeds the governor `secs` of frames at `ups` (a Callable of its level, or a number), 0.1 s each.
func _govern(g, tick: Array, secs: float, ups) -> void:
	for i in int(secs * 10.0):
		var u: float = ups.call(g.level) if ups is Callable else float(ups)
		tick[0] += u * 0.1
		g.feed(int(tick[0]), 0.1)


func _ups_governor() -> void:
	check(bool(Settings.get_value("graphics", "hold_ups")), "Hold the game at 60 UPS is on by default")
	var g = UpsGovernor.new()
	add_child(g)
	g.set_process(false)
	var tick := [1000.0]
	_govern(g, tick, 40.0, 60.0)
	check(g.level == 0 and g.status() == "" and absf(g.ups - 60.0) < 0.5, "at 60 UPS nothing is held back (measured %.1f)" % g.ups)
	# Slow, and each step buys a little: it steps down one at a time, PAUSE_DOWN apart, to the floors.
	var helped := func(level: int) -> float: return 50.0 + level * 0.3
	_govern(g, tick, 4.0, helped)
	var first: int = g.level
	check(first == 1 and g.limit("rate", 0.0) == 1.0 and g.limit("map", 1.0) == 1.0 and g.limit("entity", 192.0) == 192.0
		and g.status().contains("updates slowed"),
		"under 57 UPS the first step is taken (the bridge's costliest updates less often), the rest wait: level %d, %s" % [g.level, g.status()])
	_govern(g, tick, 3.0, helped)
	check(g.level == first, "the next step waits PAUSE_DOWN after the last")
	_govern(g, tick, 150.0, helped)
	check(g.level == UpsGovernor.STEPS.size() and g.limit("entity", 192.0) == 64.0 and g.limit("near", 24.0) == 8.0
		and g.limit("far", 160.0) == 32.0 and g.limit("view", 10.0) == 5.0 and g.limit("fps", 0.0) == 45.0 and g.limit("map", 1.0) == 4.0
		and g.limit("rate", 0.0) == 3.0,
		"still slow: every step taken, each knob at its floor and no lower: level %d, %s" % [g.level, g.status()])
	check(g.limit("near", 8.0) == 8.0 and g.limit("fps", 30.0) == 30.0, "a player's setting under the floor stays theirs")
	# The load goes away: one step back up per HOLD_UP at 60, back to the player's settings.
	var top: int = g.level
	_govern(g, tick, 45.0, 60.0)
	check(g.level == top - 1, "after HOLD_UP at 60 UPS one step comes back: level %d of %d" % [g.level, top])
	# Right after a step back up, a few seconds' dip (the bridge sending the newly wanted chunks)
	# takes no step down; a lasting one does.
	var back: int = g.level
	_govern(g, tick, 6.0, 52.0)
	_govern(g, tick, 12.0, 60.0)
	check(g.level == back, "a short dip after a step back up is the burst of new chunks, not load: level %d" % g.level)
	_govern(g, tick, 35.0, 60.0)
	# A 3 s reading at 60 wanders under 59.5 now and then (ticks arrive unevenly); the way back up
	# reads 10 s, so it still comes.
	var frames := [0]
	var uneven := func(_level: int) -> float:
		frames[0] += 1
		return 58.6 if (frames[0] / 25) % 2 == 0 else 61.4
	_govern(g, tick, 35.0 * top, uneven)
	check(g.level == 0 and g.status() == "" and g.limit("entity", 192.0) == 192.0 and g.limit("fps", 0.0) == 0.0,
		"settings return to the player's when the load goes away: level %d" % g.level)
	# A save or a pause (the ticks stop) isn't slowness.
	_govern(g, tick, 20.0, 0.0)
	check(g.level == 0, "stalled ticks take no step")
	# Slow for its own reasons: the steps buy nothing, so it goes back up and holds nothing back.
	var reached := 0
	for i in 12:
		_govern(g, tick, 10.0, 45.0)
		reached = maxi(reached, g.level)
	_govern(g, tick, 90.0, 45.0)
	check(reached == UpsGovernor.STEPS.size() and g.level == 0,
		"steps that buy no UPS are given back and not tried again for a while: level %d, then %d" % [reached, g.level])
	g.queue_free()
	# A setting the player already has low is skipped; switched off, nothing is held back.
	Settings.set_value("graphics", "entity_radius", 64)
	g = UpsGovernor.new()
	add_child(g)
	g.set_process(false)
	_govern(g, tick, 60.0, 60.0)
	_govern(g, tick, 40.0, helped)
	check(g.level > 3 and g.limit("entity", 64.0) == 64.0 and (g.status().find("entity") < 0), "steps for a knob already under them are skipped: %s" % g.status())
	Settings.set_value("graphics", "hold_ups", false)
	check(g.level == 0 and not g.enabled, "switching it off gives everything back at once")
	_govern(g, tick, 60.0, 40.0)
	check(g.level == 0, "switched off, a slow game takes no step")
	Settings.reset_value("graphics", "hold_ups")
	Settings.reset_value("graphics", "entity_radius")
	g.queue_free()
	# The bridge's work budget is kept to the room the game has before anything is asked, so the next
	# big request (a map zoom, a jump) is paced to it rather than reacted to once the UPS has dropped.
	g = UpsGovernor.new()
	add_child(g)
	g.set_process(false)
	var sent: Array = []
	g.budget_changed.connect(func(units: int) -> void: sent.append(units))
	_govern(g, tick, 20.0, 60.0)
	check(sent == [UpsGovernor.BUDGET_DEFAULT] and g.budget == UpsGovernor.BUDGET_DEFAULT,
		"at 60 UPS with nothing waiting the bridge keeps its default budget, sent once: %s" % [sent])
	_govern(g, tick, 5.0, 55.0)
	var cut: int = g.budget
	check(cut < UpsGovernor.BUDGET_DEFAULT and cut >= UpsGovernor.BUDGET_FLOOR and sent[-1] == cut,
		"under 58.5 UPS the budget shrinks within seconds, before any step: %d (sent %s)" % [cut, sent])
	_govern(g, tick, 30.0, 40.0)
	check(g.budget == UpsGovernor.BUDGET_FLOOR, "and no lower than its floor: %d" % g.budget)
	g.queued = 500
	_govern(g, tick, 60.0, 60.0)
	check(g.budget == UpsGovernor.BUDGET_MAX, "at 60 UPS with work waiting it grows back, to its ceiling: %d" % g.budget)
	g.queued = 0
	_govern(g, tick, 20.0, 60.0)
	check(g.budget == UpsGovernor.BUDGET_DEFAULT, "and with nothing waiting back to the default: %d" % g.budget)
	var count := sent.size()
	_govern(g, tick, 10.0, 60.0)
	check(sent.size() == count, "a steady budget isn't sent again")
	_govern(g, tick, 5.0, 50.0)
	Settings.set_value("graphics", "hold_ups", false)
	_govern(g, tick, 2.0, 50.0)
	check(g.budget == UpsGovernor.BUDGET_DEFAULT and sent[-1] == UpsGovernor.BUDGET_DEFAULT, "switched off, the default budget: %s" % [sent])
	Settings.reset_value("graphics", "hold_ups")
	g.queue_free()
	# Recommended (Graphics): from the hardware, then from what a game measured.
	var rec := func(cores: int, gpu: String, fps := 0.0, ups := 0.0, now := "") -> String:
		return Settings.recommended_preset(cores, gpu, fps, ups, now)
	check(rec.call(16, "NVIDIA GeForce RTX 5080") == "ultra" and rec.call(8, "NVIDIA GeForce RTX 3060 Laptop GPU") == "high"
		and rec.call(8, "Intel(R) UHD Graphics") == "medium" and rec.call(4, "Intel(R) Iris(R) Xe Graphics") == "low"
		and rec.call(16, "AMD Radeon(TM) Graphics") == "medium",
		"Recommended picks by the hardware: a big recent GPU with 16 threads Ultra, a discrete one High, integrated Medium or Low")
	check(rec.call(16, "NVIDIA GeForce RTX 5080", 40.0, 60.0, "ultra") == "high" and rec.call(16, "NVIDIA GeForce RTX 5080", 30.0, 52.0, "ultra") == "low"
		and rec.call(8, "NVIDIA GeForce RTX 3060", 120.0, 60.0, "high") == "ultra" and rec.call(8, "NVIDIA GeForce RTX 3060", 70.0, 60.0, "high") == "high",
		"measured in a game it steps down for slow frames or a slow game, up when there is plenty of room")
	check(bool(Settings.get_value("graphics", "belt_smooth")), "Smooth belt items is on by default")
	# The minimap following the character asks only for the chunks it hasn't had lately.
	var cache := MapCache.new(UiModel.new())
	for y in range(0, 10):
		for x in range(0, 10):
			cache._charted[Vector2i(x, y)] = cache._now()
	var strips: Array = cache._stale(Rect2i(1, 1, 10, 10), cache._now() - 4.0)
	check(strips == [Rect2i(10, 1, 1, 9), Rect2i(1, 10, 10, 1)], "a moved minimap asks for the new strips, not its whole area: %s" % [strips])


## The sun's shadow map fitted to the ground in view (sun_shadows.gd), with the camera the angled
## view has by default (30 tiles off, 50 degrees down) and a sun in it.
func _sun_shadows(cam: Camera3D, sun: DirectionalLight3D) -> void:
	var depths := SunShadows.ground_depths(cam)
	check(depths.x > 20.0 and depths.x < 28.0 and depths.y > 36.0 and depths.y < 46.0,
		"from the angled view the ground in view runs from about 24 to 41 tiles from the camera: %s" % depths)
	var fitted := SunShadows.distance_for(depths.y, 150.0, -1.0)
	check(fitted >= depths.y / float(SunShadows.QUALITY["high"]["fade"]) and fitted <= depths.y / float(SunShadows.QUALITY["high"]["fade"]) * SunShadows.STEP + 0.5,
		"the shadows reach just past the top of the screen, so their fade starts there: %.1f" % fitted)
	check(SunShadows.distance_for(INF, 150.0, -1.0) == 150.0 and SunShadows.distance_for(INF, 150.0, fitted) == 150.0,
		"with the horizon in view (first person, a low tilt) they reach the quality's cap at once")
	check(SunShadows.distance_for(INF, 80.0, 150.0) == 80.0, "a lower quality's cap applies at once")
	check(SunShadows.distance_for(depths.y * 0.95, 150.0, fitted) == fitted and SunShadows.distance_for(depths.y * 0.6, 150.0, fitted) < fitted,
		"zooming in a little keeps the step (no flipping to and fro), zooming in more takes a shorter one")
	var two := SunShadows.split_fractions(depths, fitted, 2)
	var four := SunShadows.split_fractions(depths, fitted, 4)
	check(two.x * fitted > depths.x and two.x * fitted < depths.y and four.x < four.y and four.y < four.z and four.x * fitted > depths.x and four.z < 1.0,
		"the splits share out the ground in view: %s %s" % [two, four])
	check(SunShadows.split_fractions(Vector2(0.5, INF), 150.0, 4) == Vector3(0.1, 0.2, 0.5), "with the horizon in view, Godot's own splits")
	# One map while the nearest ground in view is at least a quarter as far as the shadows reach;
	# Godot's cascades for the horizon, with a margin so tilting across the line doesn't flip it.
	check(not SunShadows.reaches_far(depths, fitted, false) and SunShadows.reaches_far(Vector2(1.0, INF), 150.0, false)
		and SunShadows.reaches_far(Vector2(20.0, 150.0), 150.0, false) and SunShadows.reaches_far(Vector2(40.0, 150.0), 150.0, true)
		and not SunShadows.reaches_far(Vector2(40.0, 150.0), 150.0, false), "one shadow map for the angled view, cascades looking far")
	# Fitted, the chunks that cast are those round the view, not 90 tiles ahead under the ground.
	var ahead := Rect2(-70, -70, 16, 16)
	check(WorldMirror._rect_meets_hull(ahead, WorldMirror.shadow_region(cam, sun)), "at a fixed 150 tiles, chunks far ahead cast shadows")
	var fitter := SunShadows.new()
	fitter.sun = sun
	add_child(fitter)
	for q in ["low", "medium", "high", "ultra"]:
		fitter.apply_quality(q)
		var spec: Dictionary = SunShadows.QUALITY[q]
		check(sun.directional_shadow_mode == SunShadows.MODES[int(spec["splits"])] and sun.directional_shadow_max_distance <= float(spec["cap"])
			and Settings.SHADOW_SIZES[q] == int(spec["atlas"]),
			"%s shadows: %d split(s) on a %d atlas, at most %d tiles" % [q, int(spec["splits"]), int(spec["atlas"]), int(spec["cap"])])
	fitter.apply_quality("high")
	check(is_equal_approx(sun.directional_shadow_max_distance, fitted) and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL
		and not WorldMirror._rect_meets_hull(ahead, WorldMirror.shadow_region(cam, sun)) and WorldMirror._rect_meets_hull(Rect2(-16, -16, 32, 32), WorldMirror.shadow_region(cam, sun)),
		"fitted to the view (one map, %.1f tiles), they don't, and the ground round the focus still does" % sun.directional_shadow_max_distance)
	# Looking at the horizon: the cap, in cascades.
	cam.look_at_from_position(Vector3(0.0, 1.6, 0.0), Vector3(30.0, 1.0, 0.0))
	fitter._fit(false)
	check(sun.directional_shadow_max_distance == 150.0 and sun.directional_shadow_mode == SunShadows.MODES[int(SunShadows.QUALITY["high"]["horizon_splits"])],
		"looking at the horizon (first person) the shadows reach the cap in cascades")
	cam.look_at_from_position(Vector3(13.6, 23.0, 13.6), Vector3.ZERO)
	fitter.queue_free()
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


## What keeps a big base smooth. Shadows only from chunks that can shade what the
## camera sees, through simplified stand-ins; models get LODs of their own; the Level of detail
## setting; batched datagrams from the mod; messages handled within a frame's budget; chunk
## rebuilds within a time budget.
func _performance() -> void:
	# The region whose casters can shade the view, and the rectangle test against it.
	var hull := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 0)])
	check(WorldMirror._rect_meets_hull(Rect2(10, 10, 32, 32), hull) and not WorldMirror._rect_meets_hull(Rect2(10, 60, 20, 20), hull)
		and not WorldMirror._rect_meets_hull(Rect2(-100, -100, 32, 32), hull),
		"a chunk inside the shadow region casts, one beyond its slanted edge or far away doesn't")
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(13.6, 23.0, 13.6), Vector3.ZERO)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.directional_shadow_max_distance = 150.0
	sun.shadow_enabled = true
	add_child(sun)
	var region := WorldMirror.shadow_region(cam, sun)
	check(WorldMirror._rect_meets_hull(Rect2(-16, -16, 32, 32), region) and not WorldMirror._rect_meets_hull(Rect2(320, 320, 32, 32), region),
		"the shadow region holds the ground round the focus, not chunks 300 tiles behind the camera")
	_sun_shadows(cam, sun)
	# A world's chunks: near ones cast at full detail, far ones simplified, ones behind none.
	var world := WorldMirror.new()
	world.sun = sun
	add_child(world)
	for c in [Vector2i(0, 0), Vector2i(-3, -3), Vector2i(9, 9)]:
		var cv := ChunkView.new()
		cv.coord = c
		world.chunks[c] = cv
		world.add_child(cv)
	world._update_shadow_casters()
	check(world.chunks[Vector2i(0, 0)].shadow_tier == ChunkView.SHADOWS_NEAR and world.chunks[Vector2i(-3, -3)].shadow_tier == ChunkView.SHADOWS_FAR
		and world.chunks[Vector2i(9, 9)].shadow_tier == ChunkView.SHADOWS_NONE and world.shadow_casters == 2,
		"shadow tiers: near the focus full, further out simplified, behind the camera none: %s" % [world.chunks.values().map(func(cv): return cv.shadow_tier)])
	world.queue_free()
	sun.queue_free()
	cam.queue_free()
	# Picking what's under the mouse uses an index of selection boxes: the same answers as testing
	# every entity, and it follows entities coming and going.
	var pw := WorldMirror.new()
	pw.pick_build_usec = 1 << 40  # the whole index at once (in play it is built over frames)
	add_child(pw)
	pw.protos.add_entities([[1, "transport-belt", "transport-belt", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[2, "assembling-machine-1", "assembling-machine", -1.5, -1.5, 1.5, 1.5, 120, 120, 120, 3, 3],
		[3, "iron-ore", "resource", -0.5, -0.5, 0.5, 0.5, 100, 100, 160, 1, 1]])
	for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var pcv := ChunkView.new()
		pcv.coord = c
		pw.chunks[c] = pcv
		pw.add_child(pcv)
	var unit := 1
	for x in range(-6, 40, 3):
		for y in range(-2, 40, 3):
			pw._add([unit, 2 if (x + y) % 2 == 0 else 1, x * 256 + 128, y * 256 + 128, 0])
			unit += 1
			pw._add([unit, 3, x * 256 + 128, y * 256 + 128, 0])
			unit += 1
	var brute := func(point: Vector2) -> Object:
		var best: Object = null
		var area := INF
		for r in pw.entities.values():
			var proto: ProtoDB.EntityProto = pw.protos.entity(r.proto_id)
			var rect := WorldMirror.selection_rect(proto, r.pos, r.dir)
			var a := rect.get_area() + (1000.0 if proto.type == "resource" else 0.0)
			if rect.has_point(point) and a < area:
				area = a
				best = r
		return best
	var same := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 400:
		var point := Vector2(rng.randf_range(-8.0, 42.0), rng.randf_range(-4.0, 42.0))
		same = same and pw.pick(point) == brute.call(point)
	check(same, "picking from the index finds what testing every entity finds (400 points)")
	var picked = pw.pick(Vector2(3.6, 1.6))
	var picked_key = picked.key if picked != null else null
	pw._remove(picked_key)
	var after = pw.pick(Vector2(3.6, 1.6))
	check(picked != null and after != picked and after == brute.call(Vector2(3.6, 1.6)),
		"an entity removed is no longer picked (%s, then %s)" % [picked_key, after.key if after != null else null])
	# In play a chunk's index is built a slice a frame (PICK_BUILD_USEC), so walking with the mouse
	# over new busy chunks doesn't take the whole build in one frame.
	pw.pick_build_usec = 0
	var slow_cv: ChunkView = pw.chunks[Vector2i(0, 0)]
	slow_cv.pick_grid = []
	pw._pick_frame = -1
	pw._pick_grid(slow_cv)
	var partial := slow_cv.pick_grid.size() == 4 and int(slow_cv.pick_grid[3]) < slow_cv.entities.size()
	pw.pick_build_usec = 1 << 40
	pw._pick_grid(slow_cv)
	check(partial and slow_cv.pick_grid.size() == 2, "a chunk's pick index is built over frames, then kept whole")
	pw.queue_free()
	# Chunks stream in a few at a time, nearest first: walking at a long view distance asked for a
	# whole row at once (owner's desktop, 18 fps running).
	var sw := WorldMirror.new()
	add_child(sw)
	sw.view_radius = 10
	sw._update_subscription(0.2)
	var first: Array = sw._subscribed.duplicate()
	var nearest := first.all(func(c: Vector2i) -> bool: return c.length_squared() <= 5)
	for c in first:
		var cv: ChunkView = sw.chunks[c]
		cv.loaded = true
		cv.tile_ids = PackedInt32Array()
	sw._update_subscription(0.2)
	check(first.size() == WorldMirror.STREAM_MOVING and nearest and sw._subscribed.size() == 2 * WorldMirror.STREAM_MOVING,
		"chunks are asked for a few at a time, nearest first, more once those are drawn: %d then %d" % [first.size(), sw._subscribed.size()])
	sw.queue_free()
	# Copies of models' materials made without asking the RenderingServer (copy_material) match duplicate().
	var source_mat := ModelLibrary.mesh_for("assembling-machine-1").surface_get_material(0) as ShaderMaterial
	var copied := ModelLods.copy_material(source_mat)
	var duplicated := source_mat.duplicate() as ShaderMaterial
	var params_match := copied.shader == duplicated.shader and copied.resource_name == duplicated.resource_name
	for u: Dictionary in source_mat.shader.get_shader_uniform_list():
		var a: Variant = copied.get_shader_parameter(u["name"])
		var b: Variant = duplicated.get_shader_parameter(u["name"])
		params_match = params_match and (a == b or (a == null and b == RenderingServer.shader_get_parameter_default(source_mat.shader.get_rid(), u["name"])))
	check(params_match, "a material copied for a model has the shader, name and parameters duplicate() gives")
	check(ModelLibrary._source("assembling-machine-1").begins_with(ModelLibrary.GLTF_SOURCE),
		"models are read from their .glb (also in an exported game, addons/zenith_export ships them)")
	# A modeller's folder (--models=) only fills gaps, unless --models-first lets it replace a model.
	var outside := OS.get_user_data_dir().path_join("test-models")
	DirAccess.make_dir_recursive_absolute(outside)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/models/wooden-chest.glb"), outside.path_join("iron-chest.glb"))
	var saved_dir := ModelLibrary.external_dir
	ModelLibrary.external_dir = outside
	ModelLibrary._sources.erase("iron-chest")
	check(not ModelLibrary._source("iron-chest").contains(outside), "a --models folder doesn't replace a model the project has")
	ModelLibrary.external_first = true
	ModelLibrary._sources.erase("iron-chest")
	check(ModelLibrary._source("iron-chest") == ModelLibrary.GLTF_SOURCE + outside.path_join("iron-chest.glb"),
		"with --models-first the folder's model replaces the project's own")
	ModelLibrary.external_first = false
	ModelLibrary.external_dir = saved_dir
	ModelLibrary._sources.erase("iron-chest")
	DirAccess.remove_absolute(outside.path_join("iron-chest.glb"))
	# A model's stand-in and its own LODs, made on a worker thread.
	var mesh := ModelLibrary.mesh_for("assembling-machine-1")
	var surfaces := mesh.get_surface_count()
	var proxy := ModelLods.proxy_for(mesh)
	# Every model the test drew before queued its own job: wait for this one (up to a minute).
	var until := Time.get_ticks_msec() + 60000
	while proxy != null and not ModelLods.is_ready(proxy) and Time.get_ticks_msec() < until:
		ModelLods.poll()
		await get_tree().process_frame
	check(proxy != null and ModelLods.is_ready(proxy) and proxy.get_surface_count() == 1 and ModelLods.lod_models >= 1,
		"a model gets a one-surface shadow stand-in and LODs of its own (%s, %d jobs waiting)" % [proxy, ModelLods._queue.size()])
	check(mesh.get_surface_count() == surfaces and mesh.surface_get_material(0) is ShaderMaterial,
		"the assembler keeps its surfaces and materials when given its LODs")
	# Settings > Graphics > Merged materials (off by default): one material per model, assembler 2's
	# materials rows of one surface's material; off, a surface per material as before.
	var merged_default: bool = Settings.DEFAULTS["graphics"]["merged_materials"]
	var am_load := ModelLibrary.Load.new()
	am_load.path = "res://assets/models/assembling-machine-2.glb"
	am_load.combine = true
	am_load.run()
	var am2 := ModelLibrary._commit_load(am_load, [])
	var am_rows := ModelLibrary.MaterialRows.rows(am2.surface_get_material(0)).size()
	var am_plain := ModelLibrary.Load.new()
	am_plain.path = am_load.path
	am_plain.combine = false
	am_plain.run()
	var saved_merge := ModelLibrary.merge_materials
	Settings.set_value("graphics", "merged_materials", true, false)
	Settings.apply_merged_materials()
	var merge_on := ModelLibrary.merge_materials
	Settings.set_value("graphics", "merged_materials", merged_default, false)
	Settings.apply_merged_materials()
	var merge_off := ModelLibrary.merge_materials
	ModelLibrary.merge_materials = saved_merge
	check(not merged_default and merge_on and not merge_off and am2.get_surface_count() == 1 and am_rows > 1
		and (ModelLods.arrays_of(am2, 0)[Mesh.ARRAY_CUSTOM2] as PackedFloat32Array).size() > 0 and am_plain.groups.size() == am_rows,
		"Merged materials (off by default) makes assembler 2 one surface, its %d materials rows of one; off, %d surfaces" % [am_rows, am_plain.groups.size()])
	check(Settings.recommended_merged_materials("NVIDIA GeForce RTX 5080") and not Settings.recommended_merged_materials("NVIDIA GeForce RTX 5060 Laptop GPU")
		and not Settings.recommended_merged_materials("Intel(R) UHD Graphics") and not Settings.recommended_merged_materials("NVIDIA GeForce RTX 4090", 16.0, 15.0),
		"Recommended turns merged materials on for a big desktop GPU whose frames the CPU holds up, off otherwise")
	check(ModelLods.proxy_for(Visuals.box_mesh()) == null, "a small mesh casts its own shadow")
	var tree_job = ModelLods._job_for(ModelLibrary.mesh_for("tree-01") as ArrayMesh)
	check(tree_job != null and not tree_job.view_lods, "a tree keeps its leaf cards whole in view (no LODs), with a shadow stand-in")
	# Forests: with SSAO on, Godot's depth prepass writes normals and roughness, so a leaf card's
	# roughness must not come from the weathering noise (each crown is a dozen cut-out layers deep:
	# a zoomed-out forest's GPU frame 17.5 -> 12.3 ms), and trees keep no per-frame LODs.
	var leaf_shader := load("res://shaders/factorio_material_leaf.gdshader") as Shader
	var include_text := FileAccess.get_file_as_string("res://shaders/factorio_material.gdshaderinc")
	check(leaf_shader != null and include_text.contains("// Leaves keep their base roughness")
		and include_text.contains("ROUGHNESS = mix(m_rough, 0.85, pc);"),
		"leaf cards' roughness skips the weathering, so the SSAO prepass stays cheap in forests")
	# A model's first appearance is made on a worker thread. Its chunk leaves it out meanwhile
	# (nothing blocks the frame), and draws it when built again once the model is ready.
	var fresh := "cryogenic-plant"
	if ModelLibrary._cache.has(fresh):
		check(false, "the test needs %s not made yet" % fresh)
	var lprotos := ProtoDB.new()
	lprotos.add_entities([[7, fresh, "assembling-machine", -2.5, -2.5, 2.5, 2.5, 1, 1, 1, 1, 1]])
	var lcv := ChunkView.new()
	add_child(lcv)
	var lrec := WorldMirror.Rec.new()
	lrec.key = 4242
	lrec.unit = 4242
	lrec.proto_id = 7
	lrec.pos = Vector2(3, 3)
	lcv.entities[lrec.key] = lrec
	var t0 := Time.get_ticks_usec()
	lcv.build_entities(lprotos, {})
	var first_usec := Time.get_ticks_usec() - t0
	check(lcv.waiting_models and lcv._instances.is_empty() and not lcv.placeholder_keys.has(lrec.key) and not ModelLibrary._cache.has(fresh),
		"a chunk whose model isn't made yet draws nothing for it and waits (%d us, %d instances)" % [first_usec, lcv._instances.size()])
	var gen := ModelLibrary.generation
	until = Time.get_ticks_msec() + 60000
	while not ModelLibrary.ready(fresh) and Time.get_ticks_msec() < until:
		ModelLibrary.poll()
		await get_tree().process_frame
	check(ModelLibrary.generation > gen and ModelLibrary.mesh_for(fresh) != null and ModelLibrary.mesh_for(fresh).has_meta(ModelLods.ARRAYS_META),
		"the model is made on a worker thread, keeping its arrays on the CPU (no GPU read-back later)")
	lcv.build_entities(lprotos, {})
	var drawn := lcv._instances.any(func(mmi: MultiMeshInstance3D) -> bool: return mmi.multimesh.mesh == ModelLibrary.mesh_for(fresh))
	check(not lcv.waiting_models and drawn, "built again, the chunk draws the model")
	lcv.queue_free()
	# Settings > Graphics > Level of detail.
	check(str(Settings.DEFAULTS["graphics"]["lod_quality"]) == "medium", "Level of detail defaults to medium")
	ModelLods.apply_quality("low", get_viewport())
	check(is_equal_approx(get_viewport().mesh_lod_threshold, 4.0) and is_equal_approx(ModelLods.lod_bias, 0.08), "low: 4 px of error, far shadows sooner")
	ModelLods.apply_quality("high", get_viewport())
	check(is_equal_approx(get_viewport().mesh_lod_threshold, 1.0) and is_equal_approx(ModelLods.lod_bias, 0.25), "high: Godot's pixel")
	ModelLods.apply_quality("medium", get_viewport())
	check(is_equal_approx(get_viewport().mesh_lod_threshold, 4.0), "medium (High's preset): 4 px, 2 ms less GPU on the owner's base than 2 with no visible change")
	var window := SettingsWindow.new()
	add_child(window)
	var found := window.find_children("*", "", true, false).any(func(n: Node) -> bool: return n is Label and (n as Label).text == "Level of detail")
	check(found, "the settings window offers Level of detail")
	window.queue_free()
	# Batched datagrams (hello b) and the frame budget for handling messages.
	var b = load("res://scripts/net/bridge.gd").new()
	var got: Array = []
	b.message_received.connect(func(msg: Dictionary) -> void: got.append(str(msg.get("t"))))
	b.receive('{"t":"welcome","r":1,"v":1,"k":1}'.to_utf8_buffer())
	b.receive('{"t":"sky","k":2}\n{"t":"me","k":2}\n{"t":"mv","k":2,"l":[]}'.to_utf8_buffer())
	check(got == ["sky", "me", "mv"], "several messages in one datagram, joined by newlines, are each handled: %s" % [got])
	got.clear()
	var lines: Array = []
	for i in 3000:
		lines.append('{"t":"sky","k":%d}' % (3 + i))
	b._queue("\n".join(lines).to_utf8_buffer())
	var slow := func(_msg: Dictionary) -> void: OS.delay_usec(20)
	b.message_received.connect(slow)
	b._drain()
	check(got.size() > 0 and got.size() < 3000 and b.waiting_count() == 3000 - got.size(),
		"a frame handles messages for its time budget and leaves the rest for the next: %d now, %d waiting" % [got.size(), b.waiting_count()])
	while b.waiting_count() > 0:
		b._drain()
	check(got.size() == 3000, "... and they are all handled in order over the next frames")
	b.free()
	# Chunk rebuilds stop at their time budget (at least one a frame).
	check(WorldMirror.REBUILD_USEC > 0 and WorldMirror.REBUILD_USEC <= 8000, "chunk rebuilds have a frame time budget")


## The console (chat_window.gd, console_commands.gd): each command goes where it can run, Lua
## commands' game.player is the bridge's player, Tab completes, Up and Down go back through what
## was typed, /clear, /color, /ignore.
func _console(hud: Hud) -> void:
	var ui = hud.ui
	var m = ui.model
	var chat = ui.chat
	var con = chat.console
	var old_rcon: Callable = con.rcon
	var old_has: Callable = con.has_rcon
	sent()
	check(ConsoleCommands.canonical("c") == "command" and ConsoleCommands.canonical("SC") == "silent-command"
		and ConsoleCommands.canonical("nope") == "", "console: aliases name their command")
	check(ConsoleCommands.complete("/evo") == ["/evolution ", []], "Tab completes a unique command: %s" % [ConsoleCommands.complete("/evo")])
	var many: Array = ConsoleCommands.complete("/un")
	check(str(many[0]) == "/un" and "unban" in many[1] and "unlock-tips" in many[1], "several: the shared start and the choices: %s" % [many])
	check(ConsoleCommands.complete("/cheat al") == ["/cheat al", []], "no completion past the name")
	var lua: String = ConsoleCommands.rewrite_lua("game.player.insert{name='iron-plate'} game.player.print(#game.players) game.print('x')")
	check(lua == "__zp.insert{name='iron-plate'} __zprint(#game.players) __zgprint('x')", "game.player becomes the bridge's player, game.players stays: %s" % lua)
	var cmd: String = ConsoleCommands.lua_command("/c __factorio-3d-bridge__ game.player.name")
	check(cmd.begins_with("/c __factorio-3d-bridge__ local __zr = ") and cmd.contains("pcall(function() __zp.name\n")
		and cmd.count("\n") == 1, "the prelude goes after a mod's name, on the user's first line")
	# Not connected over RCON.
	con.has_rcon = func() -> bool: return false
	var r: String = await con.run("/editor")
	check(r.contains("Ctrl+F9"), "/editor: press Ctrl+F9 for Factorio itself: %s" % r)
	r = await con.run("/kick bob")
	check(r.contains("needs RCON"), "/kick needs RCON: %s" % r)
	r = await con.run("/c game.player.print(1)")
	check(r.contains("needs RCON") and sent_one("cmd").is_empty(), "Lua never goes through the bridge")
	var answer := func(lines: Array) -> void:
		var reply := func() -> void: m.handle({"t": "cmdr", "id": m._command_id, "l": lines})
		get_tree().create_timer(0.05).timeout.connect(reply)
	answer.call(["2.1.23"])
	r = await con.run("/version")
	check(r == "2.1.23" and sent_one("cmd").get("text") == "/version", "/version without RCON: the bridge answers (cmd, cmdr): %s" % r)
	# Over RCON.
	var to_rcon: Array = []
	con.has_rcon = func() -> bool: return true
	con.rcon = func(c: String) -> String:
		to_rcon.append(c)
		return "from rcon"
	r = await con.run("/time")
	check(r == "from rcon" and to_rcon[-1] == "/time", "/time goes over RCON when there is one")
	r = await con.run("/sc game.player.surface.name")
	check(str(to_rcon[-1]).begins_with("/sc local __zr") and str(to_rcon[-1]).contains("__zp.surface.name"), "/sc goes over RCON with the prelude")
	answer.call(["Researched every technology"])
	r = await con.run("/cheat")
	check(r == "Researched every technology" and to_rcon.size() == 2, "/cheat goes to the bridge even with RCON (Factorio's does nothing there)")
	r = await con.run("/my-mods-command x")
	check(to_rcon[-1] == "/my-mods-command x", "an unknown command goes to the server")
	r = await con.run("/help")
	check(r.contains("In Factorio itself (Ctrl+F9): ") and r.contains("/editor"), "/help lists the commands by where they run")
	r = await con.run("/h mc")
	check(r.contains("how long") and r.contains("over RCON"), "/help <alias> says what it does: %s" % r)
	sent()
	await con.run("/color red")
	check(sent_one("set_char_color").get("c") == [208.0, 6.0, 0.0], "/color red sets the character's colour (Factorio's red)")
	await con.run("/color 0 255 0")
	check(sent_one("set_char_color").get("c") == [0.0, 255.0, 0.0], "/color r g b")
	r = await con.run("/color nonsense")
	check(r.begins_with("/color"), "/color without a colour says how")
	# The console line: history, Tab, /clear, /ignore.
	m.handle({"t": "chat", "from": "Grief", "text": "spam"})
	chat._refresh()
	check(_texts(chat).has("Grief: spam"), "a chat line shows")
	await con.run("/ignore Grief")
	chat._refresh()
	check(not _texts(chat).has("Grief: spam"), "/ignore hides their lines")
	await con.run("/unignore Grief")
	await con.run("/clear")
	chat._refresh()
	check(not _texts(chat).has("Grief: spam") and chat._lines.get_child_count() == 0, "/clear empties the console")
	chat._history.clear()
	await chat._submit("first")
	await chat._submit("/time")
	chat.open()
	chat._input.text = "draft"
	chat.browse(1)
	check(chat._input.text == "/time", "Up: the last line typed")
	chat.browse(1)
	chat.browse(1)
	check(chat._input.text == "first", "Up again: the one before, and no further")
	chat.browse(-1)
	chat.browse(-1)
	check(chat._input.text == "draft", "Down past the newest: the line being typed")
	chat._input.text = "/chea"
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	chat._on_input_key(tab)
	check(chat._input.text == "/cheat ", "Tab on the line completes it")
	chat.close()
	con.rcon = old_rcon
	con.has_rcon = old_has
	sent()


## Turrets (turrets.gd) from the mod's turret states: folded until a target comes, raised at
## Factorio's preparing_speed, turned at its rotation_speed, shots no faster than the cooldown, a
## laser's beam, folded again after the target has gone.
func _turrets() -> void:
	var layer := TurretLayer.new()
	add_child(layer)
	var head: ModelLibrary.AnimPart = null
	var laser_head: ModelLibrary.AnimPart = null
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for("gun-turret"):
		if part.kind == "turret_head":
			head = part
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for("laser-turret"):
		if part.kind == "turret_head":
			laser_head = part
	check(head != null and laser_head != null, "turrets: the gun and laser turret models have their heads")
	if head == null or laser_head == null:
		layer.queue_free()
		return
	var base := Transform3D(Basis.IDENTITY, Vector3(10, 0, 10))
	var dt := 1.0 / 60.0
	var step := func(seconds: float) -> void:
		for i in int(round(seconds * 60.0)):
			layer._process(dt)
			layer.head_transform(7, head, base, dt)
			layer.head_transform(8, laser_head, base, dt)
	var folded_top := (layer.head_transform(7, head, base, 0.0) * head.mesh.get_aabb().get_center()).y
	layer.handle_states({"t": "ts", "l": [[7, 250, 0, 0, 20 * 256, 10 * 256], [8, 0, 0, 0, 10 * 256, 0]]})
	step.call(0.1)
	var st = layer.state_of(7)
	check(st != null and st.fold > 0.2 and st.fold < 1.0, "turrets: a gun turret raises once it has a target (%s)" % [st.fold if st else -1])
	layer.handle_states({"t": "ts", "l": [[7, 250, 5, 0, 20 * 256, 10 * 256], [8, 0, 1, 0, 10 * 256, 0]]})
	step.call(0.12)
	check(st.fold == 1.0 and st.fired >= 1 and st.fired <= 3, "turrets: raised in about 12 ticks (preparing_speed 0.08), then fires (%d)" % st.fired)
	var top := (layer.head_transform(7, head, base, 0.0) * head.mesh.get_aabb().get_center()).y
	check(top > folded_top, "turrets: the raised head stands higher than the folded one")
	step.call(0.5)
	check(st.fired == 5, "turrets: five reported shots drawn, one per cooldown (6 ticks): %d" % st.fired)
	check(absf(st.yaw - 0.25) < 0.01, "turrets: the head turned east at rotation_speed (%.3f)" % st.yaw)
	var laser = layer.state_of(8)
	check(laser != null and laser.fired == 1 and laser.beam_kind == "laser" and laser.beam_left > 0.0,
		"turrets: the laser turret holds its beam after rising (preparing_speed 0.05)")
	step.call(2.0)
	check(st.fold == 0.0 and laser.fold == 0.0 and laser.beam_left <= 0.0, "turrets: both fold away once their targets are gone")
	layer.handle_projectiles({"t": "pj"})
	layer.handle_states({"t": "ts", "l": [[8, 0, 1, 0, 10 * 256, 0]]})
	step.call(0.5)
	check(laser.fired == 2 and laser.beam_left <= 0.0, "turrets: once the game's beams come (pj), the laser fires without drawing its own beam")
	layer.queue_free()


## The asteroid chunks collectors.gd reads (ui_model.gd's).
class ChunkModel:
	signal asteroid_chunks_changed
	signal rocket_launched
	var asteroid_chunks: Array = []
	var asteroid_chunks_msec := 0

	func set_chunks(list: Array) -> void:
		asteroid_chunks = list
		asteroid_chunks_msec = Time.get_ticks_msec()
		asteroid_chunks_changed.emit()


## F5: asteroid chunks drifting past a platform (rockets.gd) keep their own tumble and place when
## the next update (every 10 ticks) comes, instead of snapping.
func _asteroid_chunks() -> void:
	var cm := ChunkModel.new()
	var layer = load("res://scripts/world/rockets.gd").new()
	layer.model = cm
	add_child(layer)
	cm.set_chunks([{"name": "metallic-asteroid-chunk", "position": Vector2(10, 0), "velocity": Vector2(3, 0)}])
	layer._place_chunks()
	var mmi: MultiMeshInstance3D = layer._chunk_meshes["metallic-asteroid-chunk"]
	var before: Transform3D = mmi.multimesh.get_instance_transform(0)
	# The game's next update has it a little further on than the client's estimate.
	cm.set_chunks([{"name": "metallic-asteroid-chunk", "position": Vector2(10.4, 0.1), "velocity": Vector2(3, 0)}])
	layer._place_chunks()
	var after: Transform3D = mmi.multimesh.get_instance_transform(0)
	check(after.origin.distance_to(before.origin) < 0.05 and after.basis.x.distance_to(before.basis.x) < 0.05,
		"an asteroid chunk's next update keeps its place and tumble (F5): moved %.3f tiles" % after.origin.distance_to(before.origin))
	check(is_equal_approx(float(cm.asteroid_chunks[0]["phase"]), float(cm.asteroid_chunks[0]["phase"])) and cm.asteroid_chunks[0].has("offset"),
		"the chunk carries its matched phase and the gap to ease off")
	# A chunk whose sent movement is wrong (here none, as on a travelling platform) moves on by
	# how far it really went, so later updates land where it is drawn (each 1/6 s apart).
	cm.set_chunks([{"name": "carbonic-asteroid-chunk", "position": Vector2(20, 0), "velocity": Vector2.ZERO}])
	var offsets: Array = []
	for i in range(1, 4):
		layer._chunks_msec = Time.get_ticks_msec() - 167
		cm.set_chunks([{"name": "carbonic-asteroid-chunk", "position": Vector2(20 + 0.5 * i, 0), "velocity": Vector2.ZERO}])
		offsets.append((cm.asteroid_chunks[0]["offset"] as Vector2).length())
	check(offsets[0] > 0.4 and offsets[2] < 0.1, "asteroid chunks move on by their measured speed, not the sent one: gaps %s" % [offsets])
	# H1, H6, H11: launches only on the surface shown; a waiting rocket stands down in its silo; robots fly high.
	layer.surface = "nauvis"
	layer._on_launch(1, Vector2(5, 5), "platform-1")
	var launches_elsewhere: int = layer._launches.size()
	layer._on_launch(1, Vector2(5, 5), "nauvis")
	check(launches_elsewhere == 0 and layer._launches.size() == 1 and Visuals.flying_height("rocket-silo-rocket") < -10.0
		and Visuals.flying_height("logistic-robot") >= 2.0,
		"a launch on another surface isn't drawn here; the waiting rocket sits in its shaft; robots fly above the machines (H1, H6, H11)")
	layer.queue_free()


## Asteroid collectors' arms (collectors.gd, F3) from `acol` and the chunks (`ach`): the head flies
## at a chunk in the catch circle at the arm's speed, takes it and pulls it in; the chain strings
## out behind it; filters and power hold it; a chunk the game says was caught draws the arm there.
func _collectors() -> void:
	var parts := {}
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for("asteroid-collector"):
		parts[part.kind] = part
	var links := parts.keys().filter(func(k: String) -> bool: return k.begins_with(CollectorLayer.LINK_PREFIX))
	check(parts.has("reach_collector_head") and parts.has("reach_collector_claw_l") and parts.has("reach_collector_claw_r")
		and links.size() == CollectorLayer.LINKS, "collectors: the model's arm has a head, two fingers and %d links (%d)" % [CollectorLayer.LINKS, links.size()])
	if not parts.has("reach_collector_head"):
		return
	var cm := ChunkModel.new()
	var layer := CollectorLayer.new()
	layer.model = cm
	add_child(layer)
	var base := Transform3D(Basis.IDENTITY, Vector3(10, 0, 20))  # facing north: the circle's centre is at (10, 15)
	var dt := 1.0 / 60.0
	var run := func(seconds: float) -> void:
		for i in int(round(seconds * 60.0)):
			layer._process(dt)
			layer.advance(5, base, dt)
	layer.handle({"t": "acol", "l": [[5, 1, 200, 1, []]]})
	var chunk := {"name": "metallic-asteroid-chunk", "position": Vector2(10, 14), "velocity": Vector2.ZERO}
	cm.set_chunks([chunk])
	var rest := base * CollectorLayer.HEAD_REST
	var far := rest.distance_to(Vector3(10, CollectorLayer.CHUNK_HEIGHT, 14))
	run.call(0.2)
	var head := layer.head_of(5)
	check(layer.arm_state(5)[0] == "reach" and absf(head.distance_to(rest) - 12.0 * 0.2) < 0.15,
		"collectors: the head flies at the chunk at the arm's speed, 0.2 tiles a tick (%.2f tiles in 0.2 s)" % head.distance_to(rest))
	var link_a: ModelLibrary.AnimPart = parts[CollectorLayer.LINK_PREFIX + "a"]
	var link_x: ModelLibrary.AnimPart = parts[CollectorLayer.LINK_PREFIX + "x"]
	var a_at := base * (layer.part_transform(5, link_a, base, 0.0) * link_a.pivot.origin)
	var x_xf: Transform3D = layer.part_transform(5, link_x, base, 0.0)
	check(a_at.distance_to(head) < 0.6 and x_xf == Transform3D.IDENTITY,
		"collectors: the first link follows just behind the head, the last stays stowed on a short reach")
	run.call((far - CollectorLayer.HEAD_RADIUS) / 12.0 - 0.2 + 0.05)
	check(layer.arm_state(5) == ["back", "metallic-asteroid-chunk"] and chunk.get("held", false),
		"collectors: the head takes the chunk when it reaches it (%.2f s for %.1f tiles) and pulls it in" % [(far - 0.6) / 12.0, far])
	run.call(far / 12.0 + 0.1)
	check(layer.arm_state(5) == ["idle", ""] and layer.head_of(5).distance_to(rest) < 0.01,
		"collectors: the arm is back at rest and the chunk dropped in")
	cm.set_chunks([])
	# A filter the chunk doesn't pass, and no power: the arm stays put.
	layer.handle({"t": "acol", "l": [[5, 1, 200, 1, ["oxide-asteroid-chunk"]]]})
	cm.set_chunks([{"name": "metallic-asteroid-chunk", "position": Vector2(12, 12), "velocity": Vector2.ZERO}])
	run.call(0.3)
	var filtered: String = layer.arm_state(5)[0]
	layer.handle({"t": "acol", "l": [[5, 1, 200, 0, []]]})
	run.call(0.3)
	check(filtered == "idle" and layer.arm_state(5)[0] == "idle", "collectors: a chunk the filters leave out, or no power, leaves the arm at rest")
	# The game says the collector caught a chunk the arm wasn't after: it reaches there and back.
	layer.handle({"t": "acol", "l": [[5, 1, 200, 1, []]]})
	cm.set_chunks([])
	layer.handle({"t": "acol", "g": [[5, "carbonic-asteroid-chunk", 7 * 256, 11 * 256]]})
	run.call(0.1)
	var st := layer.arm_state(5)
	run.call(1.2)
	check(st[0] == "reach" and (layer.arm_state(5) == ["back", "carbonic-asteroid-chunk"] or layer.arm_state(5) == ["idle", ""]),
		"collectors: g (a chunk the game caught) sends the arm there; it comes back with it (%s, then %s)" % [st, layer.arm_state(5)])
	# Better quality, more arms: the second is drawn by the layer itself.
	layer.handle({"t": "acol", "l": [[5, 2, 250, 1, []]]})
	cm.set_chunks([{"name": "metallic-asteroid-chunk", "position": Vector2(8, 13), "velocity": Vector2.ZERO},
		{"name": "oxide-asteroid-chunk", "position": Vector2(13, 13), "velocity": Vector2.ZERO}])
	run.call(0.2)
	check(layer.arm_state(5, 0)[0] == "reach" and layer.arm_state(5, 1)[0] == "reach"
		and layer.head_of(5, 0).distance_to(layer.head_of(5, 1)) > 1.0, "collectors: two arms go for two chunks at once")
	# Switched off (2), arms reaching out turn back and fold home; held (0) they'd stay out.
	layer.handle({"t": "acol", "l": [[5, 2, 250, 2, []]]})
	run.call(2.0)
	check(layer.arm_state(5, 0)[0] == "idle" and layer.arm_state(5, 1)[0] == "idle" and layer.head_of(5, 0).distance_to(rest) < 0.01
		and layer.head_of(5, 1).distance_to(rest) < 0.01, "collectors: switched off, the arms fold back home")
	layer.queue_free()


## What weapons fire (weapon_fx.gd): projectiles tracked by id and played out where they end,
## beams and fires coming and going with the lists, explosions the game made skipped when just
## played, and Factorio's sheets cut into pools when the install is there.
func _weapons() -> void:
	var sprites := SpriteFx.new()
	add_child(sprites)
	var wf := WeaponFx.new()
	wf.sprites = sprites
	add_child(wf)
	await get_tree().process_frame
	var installed := SoundBank.data_dir() != ""
	if installed:
		# The world's sounds decode on a worker: null on first ask, ready shortly after.
		var oggs := Array(DirAccess.get_files_at(SoundBank.data_dir().path_join("base/sound"))).filter(func(f: String) -> bool: return f.ends_with(".ogg"))
		if not oggs.is_empty():
			var ogg := "base/sound/" + str(oggs[0])
			var first := SoundBank.stream_soon(ogg)
			var until := Time.get_ticks_msec() + 5000
			while SoundBank.stream_soon(ogg) == null and Time.get_ticks_msec() < until:
				await get_tree().process_frame
			check(first == null and SoundBank.stream_soon(ogg) != null and SoundBank.stream(ogg) == SoundBank.stream_soon(ogg),
				"a world sound's first ask decodes it on a worker (null now, ready after), not on the main thread")
	check(wf.data.get("ex", {}).has("explosion") and wf.data.get("ammo", {}).get("shotgun-shell", {}).get("n") == 12.0
		and wf.dying_explosion("small-biter") == "small-biter-die" and is_equal_approx(wf.gun_cooldown("submachine-gun"), 0.1),
		"weapon_fx.json: explosions, ammo, dying explosions and gun cooldowns from Factorio's prototypes")
	if installed:
		# Atlases are cut from the sheets on worker threads (they cost fights 25-60 ms frames on
		# the main thread): nothing on the first ask, then ready.
		var cards_before := sprites.count()
		wf.explode("explosion-hit", Vector3.ZERO)
		var none_yet := sprites.count() == cards_before and wf.pools_pending() > 0
		wf.prewarm(["explosion", "explosion-hit", "rocket", "poison-cloud", "medium-scorchmark-tintable", "small-scorchmark-tintable"])
		var until := Time.get_ticks_msec() + 10000
		while wf.pools_pending() > 0 and Time.get_ticks_msec() < until:
			await get_tree().process_frame
		wf.explode("explosion-hit", Vector3.ZERO)
		check(none_yet and wf.pools_pending() == 0 and sprites.count() > cards_before,
			"weapon effects' atlases are made on a worker thread: nothing drawn on the first ask, drawn once made")
		wf._recent.clear()
	wf.handle({"t": "pj", "k": 100, "p": [5, "rocket", 512, 0, 6, "shotgun-pellet", 0, 512], "b": [9, "laser-beam", 0, 0, 1024, 0], "x": [], "e": []})
	wf.handle({"t": "pj", "k": 102, "p": [5, "rocket", 640, 0, 6, "shotgun-pellet", 0, 1024], "b": [9, "laser-beam", 0, 0, 1024, 0], "x": [], "e": []})
	var rocket = wf._flying.get(5)
	check(wf.flying_count() == 2 and rocket != null and is_equal_approx(rocket.vel.x, 15.0) and wf.beam_count() == 1,
		"pj: projectiles tracked by id with their speed (tiles a second), a beam")
	var cards := sprites.count()
	wf.handle({"t": "pj", "k": 104, "p": [6, "shotgun-pellet", 0, 1536], "b": {}, "x": [], "e": [5, 768, 0]})
	check(wf.flying_count() == 1 and wf.beam_count() == 0, "pj.e: an ended rocket goes, and a beam missing from the list")
	if installed:
		check(sprites.count() > cards and wf._recent.size() >= 1 and wf._recent[-1][0] == "explosion",
			"the rocket's explosion and scorch mark played where it ended (only_when_visible: the server makes none)")
		wf.handle({"t": "pj", "k": 106, "p": [], "b": [], "x": ["explosion", 785, 10], "e": []})
		check(wf._recent.size() == 1, "pj.x: the game's own explosion is skipped when the same was just played there")
	wf.handle({"t": "pj", "k": 108, "p": {}, "b": {}, "x": {}, "e": {}})
	check(wf.flying_count() == 0, "an empty pj clears what flew out of the area")
	wf.handle({"t": "gf", "k": 110, "l": [11, "fire-flame", 256, 256, -1, 12, "poison-cloud", -512, 0, 600]})
	check(wf.ground_count() == 2, "gf: a fire and a cloud")
	if installed:
		check(sprites.count() > 0 and wf._ground[12].cards.size() >= 8, "a poison cloud is drawn as Factorio's 16 smoke particles (capped)")
	wf.handle({"t": "gf", "k": 125, "l": {}})
	wf._process(3.0)
	check(wf.ground_count() == 0, "fires and clouds fade out once they leave the list")
	wf.in_space = true
	var before := sprites.count()
	wf._scorch("small-scorchmark-tintable", Vector3.ZERO)
	check(sprites.count() == before, "no scorch marks on a space platform")
	wf.reset()
	wf.queue_free()
	sprites.queue_free()


## The information windows: the alert bar (`al`: buttons, counts, tooltips, clicking through the
## entities, icons in the world), Factoriopedia (F2, Alt+click, the index's tabs and grid, pages,
## links, history), item tooltips' stats, the logistic networks window (L), the statistics' tabs,
## surfaces and graphs, rich text in the chat (icons, colours, gps links and pings) and the
## technology screen's details (effects, trigger tasks, infinite levels).
## The HUD and character screen as Factorio 2.1 has them (ui-hud): the top-right side menu
## (research, the 6+4 buttons, the minimap's place), the shortcut bar's chooser and new shortcuts,
## the quickbar's page chooser, the character screen's parts, chat, recipe tooltips.
func _hud(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var m = ui.model
	ui.close_all()
	ui.open_map(false)
	player.cursor_item = ""
	ui.hand = {}
	sent()
	for i in 3:
		await get_tree().process_frame

	# --- top right: research, side menu, minimap ------------------------------------------------
	var view: Vector2 = ui.size
	var menu: Rect2 = ui.side_menu.get_global_rect()
	check(is_equal_approx(menu.end.x, view.x) and is_zero_approx(menu.position.y), "the side menu sits flush in the top-right corner: %s" % menu)
	check(is_equal_approx(menu.size.x, Kit.px(256)), "it is slot_window_frame's 8 + 240 + 8 wide: %s" % menu.size.x)
	check(menu.encloses(ui.research_hud.get_global_rect()), "the research panel is in it")
	check(not ui.minimap.visible or menu.encloses(ui.minimap.get_global_rect().grow(-0.5)), "the minimap sits in it, under the buttons")
	check(ui.research_hud.get_global_rect().end.y < ui.minimap.get_global_rect().position.y, "research above the minimap")
	if ui.minimap.visible:  # the frame sat up and to the left of its place
		var slot_rect: Rect2 = ui.side_menu.minimap_slot.get_global_rect()
		var map_rect: Rect2 = ui.minimap._frame.get_global_rect()
		check(map_rect.size.x == ui.minimap.side_px() and ui.minimap.size == map_rect.size, "the minimap's Control is its frame's size: %s, %s" % [ui.minimap.size, map_rect])
		check(absf(map_rect.get_center().x - slot_rect.get_center().x) <= 1.0 and is_equal_approx(map_rect.position.y, slot_rect.position.y)
			and is_equal_approx(map_rect.size.y, slot_rect.size.y), "the minimap fills its place in the side menu: %s in %s" % [map_rect, slot_rect])
	check(ui.entity_info.global_position.y >= menu.end.y, "the entity info goes under the side menu")
	check(ui.side_menu.button("production") != null and ui.side_menu.button("mute") != null and SideMenu.BUTTONS.size() == 10,
		"Factorio's ten side menu buttons")
	ui._on_side_button("production")
	await get_tree().process_frame
	check(ui.stats.is_open() and sent_one("stats").get("kind") == "item", "the production button opens production statistics")
	ui.stats.visible = false
	ui._on_side_button("logistic_networks")
	check(ui.networks.is_open(), "the logistic networks button opens them")
	ui.networks.open(false)
	var was_on := bool(FxSettings.enabled.get("master", true))
	ui._on_side_button("mute")
	check(bool(FxSettings.enabled.get("master", true)) != was_on, "the speaker button mutes all sounds")
	await get_tree().process_frame
	check(ui.side_menu.button("mute").has_meta("muted") == was_on, "and shows the muted speaker")
	ui._on_side_button("mute")
	check(bool(FxSettings.enabled.get("master", true)) == was_on, "and unmutes them")
	var tip = ui.side_menu.button("production")._make_custom_tooltip("Production statistics (P)")
	check(tip != null and _texts(tip).has("P") and _texts(tip).has("Production statistics"), "side buttons have Factorio's tooltip, the key apart: %s" % [_texts(tip) if tip != null else []])
	if tip != null:
		tip.free()

	var saved_techs: Dictionary = m.techs.duplicate(true)
	var tech := {"order": "a", "prerequisites": [], "ingredients": [], "count": 10, "seconds": 10.0, "state": 1, "trigger": "",
		"effects": [], "level": 1, "max_level": 1, "trigger_detail": [], "saved": 0.0, "formula": ""}
	m.techs["automation"] = tech.duplicate()
	m.handle({"t": "rs", "cur": "automation", "pr": 100, "q": []})
	m.handle({"t": "rs", "cur": "", "pr": 0, "q": []})  # cancelled, not finished
	await get_tree().process_frame
	var r = ui.research_hud
	check(r._hint.visible and "".join(_texts(r._hint)).begins_with("Press T to start"), "no research: \"Press T to start a new research.\": %s" % [_texts(r._hint)])
	m.handle({"t": "rs", "cur": "automation", "pr": 370, "q": []})
	await get_tree().process_frame
	check(not r._hint.visible and r._name.visible and r._percent.text == "37%", "researching: the name, the bar and the percentage: %s" % r._percent.text)
	m.techs["automation"]["state"] = 2
	m.handle({"t": "rs", "cur": "", "pr": 0, "q": []})
	await get_tree().process_frame
	check(r.finished == "automation" and r._name.text.ends_with("finished. Press T.") and r._percent.text == "100%",
		"a finished research says so until the next starts: %s" % r._name.text)
	m.handle({"t": "rs", "cur": "automation", "pr": 0, "q": []})
	check(r.finished == "", "the next research clears it")
	m.techs["automation"]["ingredients"] = [["automation-science-pack", 1]]
	var now := Time.get_ticks_msec()
	r._samples.clear()
	r.note_progress(now - 30000, "automation", 2.0)
	r.note_progress(now - 10, "automation", 4.0)
	var rtip = r._make_custom_tooltip("Technologies (T)")
	var rtexts: Array = _texts(rtip)
	check(rtexts.has("Science production information") and rtexts.has("Progress:") and rtexts.has("× 10")
		and rtexts.has("Science per minute:"), "the research tooltip is Factorio's science production information: %s" % [rtexts])
	check(absf(r.rate_now("automation") - 4.0) < 0.1, "science per minute from the progress seen: %s" % r.rate_now("automation"))
	check(r.duration(1446) == "24m6s", "Factorio's remaining time format")
	rtip.free()
	m.techs.clear()
	m.techs.merge(saved_techs)

	# --- the shortcut bar: every shortcut, the chooser -------------------------------------------
	var bar = ui.shortcuts
	for name in ["import", "book", "tall", "green-wire", "red-wire"]:
		check(bar.button(name) != null, "Factorio's %s shortcut is on the bar" % name)
	check(not bar.button("spidertron").visible and not bar.button("artillery").visible, "the remotes stay off the bar until researched")
	bar.update_unlocks({"spidertron": {"state": 2}})
	check(bar.button("spidertron").visible, "a researched remote shows")
	bar.update_unlocks(m.techs)
	bar._expand.button_pressed = true
	await get_tree().process_frame
	check(bar.chooser_open() and bar._expand.button_pressed, "the ⋮ button opens the shortcut chooser")
	var copy_box: CheckBox = bar._rows["copy"][1]
	check(copy_box.button_pressed and bar._rows["artillery"][1].disabled, "rows: ticked when shown, greyed out when not researched")
	var shown: int = bar.shown_count()
	copy_box.button_pressed = false
	await get_tree().process_frame
	check(not bar.button("copy").visible and bar.shown_count() == shown - 1, "unticking a shortcut takes it off the bar")
	var hidden = Settings.get_value("interface", "hidden_shortcuts")
	check(hidden is Array and (hidden as Array).has("copy"), "and the choice is kept in the settings")
	copy_box.button_pressed = true
	check(bar.button("copy").visible, "ticking it puts it back")
	bar._filter("wire")
	check(bar._rows["red-wire"][0].visible and not bar._rows["undo"][0].visible, "the chooser's search filters its rows")
	bar._filter("")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not bar.chooser_open(), "Esc closes the chooser")
	ui._on_shortcut("import")
	check(ui.planners._string_box.visible and ui.planners._string_mode == "import", "Import string opens the import box")
	ui.planners._string_box.visible = false
	var had_tall := bool(Settings.get_value("interface", "hide_tall"))
	Settings.set_value("interface", "hide_tall", false)
	ui._on_shortcut("tall")
	check(bar.is_on("tall") and bool(Settings.get_value("interface", "hide_tall")), "the tall entities toggle turns the fade on and shows pressed")
	ui._on_shortcut("tall")
	check(not bar.is_on("tall") and not bool(Settings.get_value("interface", "hide_tall")), "and off again")
	Settings.set_value("interface", "hide_tall", had_tall)
	var order: Array = []
	for sc in bar.SHORTCUTS:
		order.append(str(sc[0]))
	check(order.slice(order.find("upgrade"), order.find("red-wire") + 1) == ["upgrade", "roboport", "exoskeleton", "copper-wire", "green-wire", "red-wire"],
		"the shortcuts in Factorio's order: planners, the equipment toggles, copper, green, red wire: %s" % [order])
	check(bar.button("red-wire").theme_type_variation == "FPageButton" and bar.button("green-wire").theme_type_variation == "FPageButton",
		"the wire shortcuts are plain grey buttons, as Factorio's")
	if ui.player != null and ui.player.get("_redo") is Array:
		(ui.player.get("_redo") as Array).clear()
		await get_tree().process_frame
		check(bar.button("redo").disabled, "redo is greyed with nothing to redo")
	sent()

	# --- the side menu's windows: bonuses, achievements, alerts settings, tips and tricks ---------
	for which in ["bonuses", "achievements", "alerts", "tips"]:
		ui._on_side_button(which)
		await get_tree().process_frame
		var w = {"bonuses": ui.bonuses, "achievements": ui.achievements, "alerts": ui.alerts_config, "tips": ui.tips}[which]
		check(w.is_open(), "the side menu's %s button opens its window" % which)
		ui._on_side_button(which)
		check(not w.is_open(), "and closes it again")
	ui.open_global("bonuses")
	ui.open_global("tips")
	check(ui.tips.is_open() and not ui.bonuses.is_open(), "one game-wide window at a time")
	if not ui.tips.tips().is_empty():
		var first := str(ui.tips.tips()[0][0])
		ui.tips.select(first)
		check(ui.tips.find_child("Tip_" + first, true, false) != null and ui.tips.selected == first, "a tip is listed and can be selected")
	ui.close_all()
	check(not ui.tips.is_open(), "Esc / close_all closes the tips")
	ui.chat.console.run("/permissions")
	check(ui.permissions.is_open(), "/permissions opens the permissions window, as in Factorio")
	ui.close_all()

	# --- quickbar tooltips, the ammo bar, the minimap's hover ---------------------------------------
	var qslot = ui.quickbar._slots[0]
	ui.quickbar._show(qslot, "iron-plate", "1")
	var qtip = qslot._make_custom_tooltip("")
	var qtexts: Array = _texts(qtip)
	check(qtexts.has("Middle-click") and qtexts.has(" to clear shortcut."), "a pinned quickbar slot's tooltip: the item, then \"Middle-click to clear shortcut.\": %s" % [qtexts])
	qtip.free()
	ui.quickbar._show(qslot, "", "1")
	check(qslot._make_custom_tooltip("") == null, "an empty quickbar slot has no tooltip, as Factorio's")
	m.quickbar[3] = "iron-plate"
	ui._on_quickbar_clicked(3, MOUSE_BUTTON_MIDDLE)
	check(sent().any(func(c) -> bool: return str(c.get("t", "")) == "qb_set") or str(m.quickbar[3]) == "", "middle-click clears a quickbar slot")
	m.set_guns(1, [["pistol", "firearm-magazine", 10, 4, 10], ["", "", 0, 0, 0], ["", "", 0, 0, 0]])
	await get_tree().process_frame
	var ammo_slot = ui.weapons._ammo[0]
	check(is_equal_approx(ammo_slot.ammo_bar, 0.4) and ammo_slot.tip_lines[0][0] == "Ammo: 4/10",
		"the ammo slot's green bar and \"Ammo: 4/10\" from the magazine's rounds: %s %s" % [ammo_slot.ammo_bar, ammo_slot.tip_lines])
	m.set_guns(1, [["pistol", "firearm-magazine", 10, 10, 10], ["", "", 0, 0, 0], ["", "", 0, 0, 0]])
	await get_tree().process_frame
	check(ammo_slot.ammo_bar >= 1.0, "a full magazine has no bar")
	var mtip = ui.minimap._area._make_custom_tooltip(ui.minimap._area.tooltip_text)
	var mtexts: Array = []
	for row in mtip.get_children():
		mtexts += _texts(row)
	check(mtexts.has("Map") and mtexts.has("Shift + Mouse wheel"), "the minimap's tooltip: Map (M) and Shift + Mouse wheel to zoom: %s" % [mtexts])
	mtip.free()
	var zoom_was := float(ui.minimap.settings.get_value("map/minimap_zoom"))
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	ui.minimap._on_area_input(wheel)
	check(is_equal_approx(float(ui.minimap.settings.get_value("map/minimap_zoom")), zoom_was), "the wheel alone doesn't zoom the minimap")
	wheel.shift_pressed = true
	ui.minimap._on_area_input(wheel)
	check(float(ui.minimap.settings.get_value("map/minimap_zoom")) > zoom_was, "Shift + wheel does")
	ui.minimap.settings.set_value("map/minimap_zoom", zoom_was)

	# --- the character's logistic sections and colour -----------------------------------------------
	m.handle({"t": "clog", "on": 1, "trash": 0, "l": [["iron-plate", 100, -1]], "lgs": ["Main"],
		"sec": [{"i": 1, "g": "Main", "on": 1, "m": 1, "man": 1, "f": [["iron-plate", "normal", 100, -1, "", -1]]},
			{"i": 2, "g": "", "on": 0, "m": 1, "man": 1, "f": []}]})
	m.handle({"t": "ccol", "c": [10, 20, 200]})
	ui.window.open_crafting(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var lg = ui.window._logistics
	var secs = lg.find_child("Sections", true, false)
	check(secs != null and _all_texts(secs).has("Main") and _all_texts(secs).has("[No group assigned]") and _all_texts(secs).has("Add section"),
		"the character's logistics show each section with its group, and Add section: %s" % [_all_texts(secs) if secs != null else []])
	sent()
	var add_button: Button = null
	for b in secs.find_children("*", "Button", true, false):
		if (b as Button).text == "Add section":
			add_button = b
	add_button.pressed.emit()
	var add_cmd := sent_one("set_section")
	check(add_cmd.get("u") == 0 and add_cmd.get("i") == 0, "Add section sends set_section for the character (u 0): %s" % add_cmd)
	var swatch: ColorPickerButton = ui.window.find_child("ColorSwatch", true, false)
	check(swatch != null and swatch.color.is_equal_approx(Color8(10, 20, 200)), "the colour button shows the character's colour (ccol)")
	swatch.color = Color8(255, 0, 0)
	swatch.popup_closed.emit()
	var col_cmd := sent_one("set_char_color")
	check(col_cmd.get("c") == [255.0, 0.0, 0.0] or col_cmd.get("c") == [255, 0, 0], "a colour picked goes to the bridge: %s" % col_cmd)
	ui.close_all()

	# --- the quickbar's page chooser --------------------------------------------------------------
	var qb = ui.quickbar
	qb._pages[0].pressed.emit()
	await get_tree().process_frame
	check(qb.chooser_open() and qb._chooser_row == 0, "a page button opens the page chooser for its row")
	check(qb._chooser_pages.size() == 10 and str(qb._chooser_pages[10].text) == "0", "ten pages, 0 for the tenth")
	await get_tree().process_frame
	var cr: Rect2 = qb.chooser.get_global_rect()
	var fr: Rect2 = qb.frame.get_global_rect()
	check(is_equal_approx(cr.position.x, fr.position.x) and (cr.end.y <= fr.position.y + 0.5 or is_zero_approx(cr.position.y)),
		"the chooser sits over the quickbar, on its left edge (or at the top when there's no room): %s %s" % [cr, fr])
	qb.pick_page(7)
	check(m.quickbar_upper_page() == 7 and not qb.chooser_open(), "picking a page shows it in that row and closes the chooser")
	check(str(qb._pages[0].text) == "7", "the upper row's button says 7")
	qb.open_chooser(1, true)
	qb.pick_page(4)
	check(not m.server_quickbar or sent_one("qb_page").get("p") == 4, "the lower row asks the mod for its page")
	m.quickbar_upper = 0
	qb.refresh()
	qb.open_chooser(1, true)
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not qb.chooser_open(), "Esc closes the page chooser")
	sent()

	# --- the character screen ----------------------------------------------------------------------
	ui.window.open_crafting(true)
	await get_tree().process_frame
	await get_tree().process_frame
	var w = ui.window
	check(not w._sort_button.visible, "no sort button: Factorio 2.1 sorts by itself")
	var color_buttons := _all_buttons(w._char_frame).filter(func(b: Button) -> bool: return b.tooltip_text == "Color" and b.is_visible_in_tree())
	check(color_buttons.size() == 2, "the colour picker and colour buttons over the inventory")
	check(w._stripes.is_visible_in_tree(), "the empty striped rows under the slots")
	var crafting = w._crafting
	check(crafting.search.get_parent() is HBoxContainer and crafting.search.get_parent() != crafting, "the recipe search sits in Crafting's title bar")
	check(crafting._tabs.columns <= CraftingPanel.TABS_PER_ROW, "group tabs wrap at five a row")
	if m.has_signal("logistics_changed"):
		m.set("char_requests", [{"item": "iron-plate", "min": 50, "max": -1}])
		m.set("char_requests_on", true)
		w._logistics_sig = "-"
		w._refresh_logistics()
		check(_find_checkbox(w._logistics, "Personal logistics") != null and _find_checkbox(w._logistics, "Trash unrequested") != null,
			"Personal logistics and Trash unrequested, Factorio's labels")
		check(_find_button(w._logistics, "Add section") != null and _texts(w._logistics).has("Main"), "the Main section and Add section")
	ui.close_all()

	# --- recipe tooltips, chat ----------------------------------------------------------------------
	var lines: Array = CraftingPanel.recipe_tip_lines(m, {"ingredients": [["iron-plate", 2]], "energy": 0.5,
		"products": [["iron-gear-wheel", 1]]})
	var heads := lines.map(func(l: Array) -> String: return str(l[0]))
	check(heads.has("Ingredients:") and heads.has("Products:") and heads.any(func(t: String) -> bool: return t.ends_with("Crafting time")),
		"Factorio's recipe tooltip: ingredients, crafting time, products: %s" % [heads])
	ui.chat.open()
	await get_tree().process_frame
	check(ui.chat.backdrop_shown and ui.chat._input.placeholder_text == "", "the open console: a dark backdrop, a plain input line")
	check(ui.chat.get_global_rect().end.x >= ui.quickbar.frame.get_global_rect().end.x - 1.0, "as wide as the HUD up to the quickbar's right edge")
	ui.chat.close()
	await get_tree().process_frame
	check(not ui.chat.backdrop_shown, "closed: no backdrop")
	sent()


func _info(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var m = ui.model
	ui.close_all()
	player.cursor_item = ""
	sent()

	# --- alerts -----------------------------------------------------------------------------------
	m.handle({"t": "al", "l": [["no_ammo", 3, [[2560, 0, 1, "gun-turret", 11], [5120, 0, 1, "gun-turret", 12]]],
		["no_material", 1, [[0, 2560, 1, "transport-belt", 13, "transport-belt"]]],
		["output_full", 929, [[7680, 0, 1, "assembling-machine-1", 14]]]]})
	for i in 2:
		await get_tree().process_frame
	var ammo: Button = ui.alerts._buttons.get("no_ammo")
	check(ammo != null and ammo.visible and ammo.get("count") == 3 and ammo.text == "" and ui.alerts._buttons.has("no_material")
		and (ammo.get("picture") != null or GuiAssets.core_sprite("icons/alerts/ammo-icon-red.png") == null),
		"al: a button per kind of alert, with its picture and its count drawn in the corner (not Godot's text over the icon)")
	var full: Button = ui.alerts._buttons.get("output_full")
	check((full == null or not full.visible) and not ui.alerts._lists.has("output_full"),
		"output full (not a Factorio alert) is left off the bar by default")
	var tip: Array = ui.alerts.tooltip_lines("no_ammo")
	check(str(tip[0][0]) == "3 turrets just ran out of ammunition." and str(tip[1][0]).ends_with("× 2") and str(tip[1][1]) == "gun-turret"
		and str(tip[2][0]) == "and 1 more", "the alert's tooltip says it in Factorio's words and lists the entities: %s" % [tip])
	check(str(ui.alerts.tooltip_lines("no_material")[1][0]).contains("needs"), "a ghost's alert says what it needs")
	var looked: Array = []
	var catch := func(at: Vector2) -> void: looked.append(at)
	ui.alerts.show_at.connect(catch)
	ammo.pressed.emit()
	ammo.pressed.emit()
	ammo.pressed.emit()
	ui.alerts.show_at.disconnect(catch)
	check(looked == [Vector2(10, 0), Vector2(20, 0), Vector2(10, 0)], "clicking an alert looks at its entities one after another: %s" % [looked])
	check(ui.alerts._icons != null and ui.alerts._icons.shown.get("no_ammo") == 2 and ui.alerts._icons.shown.get("no_material") == 1,
		"alert icons over the entities in the world: %s" % [ui.alerts._icons.shown if ui.alerts._icons != null else null])
	# Icons only over entities the 3D world holds. The mod's lists are seconds old, so a
	# building mined since (or one on a surface the world doesn't show) left its icon on empty ground.
	var fake_world := GDScript.new()
	fake_world.source_code = "extends RefCounted\nvar entities := {}\n"
	fake_world.reload()
	var fake_movers := GDScript.new()
	fake_movers.source_code = "extends RefCounted\nfunc position_of(unit: int) -> Variant:\n\treturn Vector3(30, 0, 4) if unit == 77 else null\n"
	fake_movers.reload()
	var icons = ui.alerts._icons
	var fw = fake_world.new()
	var turret_rec := WorldMirror.Rec.new()
	turret_rec.key = 11
	turret_rec.unit = 11
	turret_rec.pos = Vector2(10, 0)
	fw.entities[11] = turret_rec
	icons.world = fw
	icons.movers = fake_movers.new()
	m.handle({"t": "al", "l": [["no_ammo", 2, [[2560, 0, 1, "gun-turret", 11], [5120, 0, 1, "gun-turret", 12]]],
		["no_fuel", 1, [[9000, 9000, 1, "burner-mining-drill", 99]]],
		["train_fuel", 1, [[7680, 1024, 1, "locomotive", 77, "5"]]]]})
	await get_tree().process_frame
	check(icons.shown.get("no_ammo") == 1 and icons.shown.get("no_fuel") == 0 and icons.shown.get("train_fuel") == 1,
		"alert icons are drawn only over entities the world has (a mined drill's goes, a train's follows its locomotive): %s" % [icons.shown])
	check(icons.placed.get("train_fuel", []).size() == 1 and (icons.placed["train_fuel"][0] as Vector3).x == 30.0,
		"the train's icon is over the locomotive where it is drawn: %s" % [icons.placed.get("train_fuel")])
	var fuel_button = ui.alerts._buttons.get("no_fuel")
	check((fuel_button == null or not fuel_button.visible) and icons.shown.has("no_fuel"),
		"no fuel is an icon over the entity, not on the alert bar, as in Factorio (H5)")
	# Owner: low power over random machines. Factorio draws its blinking no-power icon only for no
	# power; a brownout (low_power) has no icon, nor does `pw`'s "not connected" (the alerts' unplugged
	# icon covers it). Factorio draws the 64-pixel picture at half size: one tile.
	var pwld := WorldMirror.new()
	for u in [41, 42, 43]:
		var prec := WorldMirror.Rec.new()
		prec.key = u
		prec.unit = u
		prec.pos = Vector2(u, 0)
		pwld.entities[u] = prec
	var power := FluidsPowerScript.new()
	add_child(power)
	power.world = pwld
	power.handle({"t": "pw", "k": 7, "part": 1, "parts": 1, "l": [41, 0, 42, 1, 43, 2]})
	await get_tree().process_frame
	var picon: Transform3D = power.icon_spots[0] if power.icon_spots.size() > 0 else Transform3D()
	check(power.icon_count() == 1 and is_equal_approx(picon.origin.x, 41.0) and is_equal_approx(picon.basis.x.length(), 1.0)
		and power.power_state(42) == FluidsPowerScript.LOW_POWER and power.has_no_power(43),
		"the no-power icon only over the machine with no power, one tile wide; low power and not connected get none: %d %s %s" % [power.icon_count(), picon, power.unpowered])
	power.world = null
	power.queue_free()
	pwld.free()
	icons.world = null
	icons.movers = null
	# An alert on another surface opens that surface's map, centred on it.
	var si_was: int = m.character_si
	m.character_si = 1
	m.handle({"t": "al", "l": [["no_ammo", 1, [[40 * 256, 8 * 256, 3, "gun-turret", 21]]]]})
	await get_tree().process_frame
	ui.alerts._buttons.get("no_ammo").pressed.emit()
	check(ui.map_open() and m.map_si == 3 and ui.map_view.centre == Vector2(40, 8) and not ui.map_view.following,
		"clicking an alert on another surface shows it on that surface's map: si %d at %s" % [m.map_si, ui.map_view.centre])
	ui.open_map(false)
	m.character_si = si_was
	m.handle({"t": "al", "l": []})
	await get_tree().process_frame
	check(not ammo.visible and ui.alerts._icons.shown.get("no_ammo") == 0, "alerts that ended go away")

	# --- Factoriopedia ----------------------------------------------------------------------------
	sent()
	key(KEY_F2)
	await get_tree().process_frame
	check(ui.pedia.is_open() and sent().any(func(c) -> bool: return c.get("t") == "pedia_index"), "F2 opens Factoriopedia and asks for its index")
	m.handle({"t": "pidx", "part": 1, "parts": 2, "g": [["logistics", "a"], ["intermediate-products", "c"], ["technologies", "zzz"]],
		"l": [["item", "transport-belt", "logistics", "belt", "a"], ["item", "wooden-chest", "logistics", "storage", "a"]]})
	m.handle({"t": "pidx", "part": 2, "parts": 2, "l": [["item", "iron-plate", "intermediate-products", "raw-material", "a"],
		["recipe", "basic-oil-processing", "intermediate-products", "fluid-recipes", "a"], ["technology", "automation", "technologies", "technologies", "a"]]})
	await get_tree().process_frame
	var tab_buttons: Array = ui.pedia._tabs.get_children().filter(func(c) -> bool: return c is Button)
	check(m.pedia_index.size() == 5 and tab_buttons.size() == 2 and ui.pedia._tabs.get_child_count() == 6 and ui.pedia.grid_rows().size() == 2
		and ui.pedia.grid_rows()[0].get_child_count() == 10,
		"the index's groups are tabs (technologies have none; the row filled), the group's things rows by subgroup, ten wide (%d tabs, %d rows)" % [tab_buttons.size(), ui.pedia.grid_rows().size()])
	ui.pedia._search.text = "iron"
	ui.pedia._fill_grid()
	check(ui.pedia.grid_rows().size() == 1 and ui.pedia.row_things(ui.pedia.grid_rows()[0]).size() == 1, "search finds things across every group")
	ui.pedia._search.text = ""
	ui.pedia._fill_grid()
	ui.open_pedia("entity", "transport-belt")
	check(ui.pedia.kind == "item" and ui.pedia.thing == "transport-belt" and m._pedia_asked.has("item/transport-belt"),
		"an entity an item builds opens the item's page (as Factoriopedia does), asked for: %s" % [m._pedia_asked.keys()])
	m.handle({"t": "pedia", "kind": "item", "name": "transport-belt", "found": 1, "d": {"stack": 100, "made": ["transport-belt"],
		"used": ["fast-transport-belt", "underground-belt"], "entity": {"type": "transport-belt", "hp": 150, "belt": 15, "res": [["fire", 0, 90]]}}})
	m.handle({"t": "pedia", "kind": "recipe", "name": "transport-belt", "found": 1, "d": {"ing": [["item", "iron-plate", 1], ["item", "iron-gear-wheel", 1]],
		"prod": [["item", "transport-belt", 2]], "time": 0.5, "made_in": ["assembling-machine-1"], "unlocked": ["logistics"]}})
	for i in 3:
		await get_tree().process_frame
	var texts: Array = _texts(ui.pedia._page)
	check(texts.has("Stack size:") and texts.has(" 100") and texts.has("Speed:") and texts.has("Base health:") and texts.has("Used in")
		and texts.has("Ingredients") and texts.has("Products") and texts.has("Made in") and texts.has("0.5 s") and texts.has(" Crafting time")
		and texts.has("Iron gear wheel") and texts.has("Resistances") and ui.pedia._page_title.text == "Transport belt (Recipe/Item/Entity)",
		"the page as Factoriopedia's: title with every kind, stats box, Ingredients / time / Products, Made in, Used in: %s %s" % [ui.pedia._page_title.text, texts])
	check(ui.pedia._page.find_child("Tech_logistics", true, false) != null, "Unlocked by shows the technology's card")
	var links: Array = []
	_collect(ui.pedia._page, links)
	var used: Array = links.filter(func(b) -> bool: return b.thing == "underground-belt")
	check(not used.is_empty(), "what it's used in links to those pages")
	if not used.is_empty():
		used[0].pressed.emit()
	check(ui.pedia.thing == "underground-belt" and not ui.pedia._back.disabled, "a link opens its page; back is possible")
	ui.pedia._back.pressed.emit()
	check(ui.pedia.thing == "transport-belt" and not ui.pedia._forward.disabled, "back goes to the last page, forward is possible")
	m.handle({"t": "pedia", "kind": "item", "name": "coal", "found": 1, "d": {"stack": 50, "fuel": 4000000, "fcat": ["chemical"]}})
	var info: Array = ui.item_info("coal")
	check(info.has(["Fuel value: 4 MJ"]) and info.has(["Stack size: 50"]), "item tooltips get Factorio's stats (fuel value, stack size): %s" % [info])
	key(KEY_F2)
	await get_tree().process_frame
	check(not ui.pedia.is_open(), "F2 again closes it")
	# Alt+click on an inventory slot opens its page.
	hud.set_inventory([["iron-plate", 60]])
	ui.toggle_inventory()
	await get_tree().process_frame
	await get_tree().process_frame
	var slot: Control = _find_slot_item(ui.window, "iron-plate")
	if slot != null:
		# What _input does with the hovered control (the GUI's hover itself isn't reliable in a
		# headless run: it depended on what earlier sections did).
		check(ui.alt_click(slot), "Alt+click on a slot is taken")
		await get_tree().process_frame
	check(slot != null and ui.pedia.is_open() and ui.pedia.thing == "iron-plate" and player.cursor_item == "",
		"Alt+click on an inventory slot opens its Factoriopedia page (and picks nothing up)")
	ui.close_all()

	# --- logistic networks (L) --------------------------------------------------------------------
	# A player with a camera rig, so the remote view can start.
	var rig_script := GDScript.new()
	rig_script.source_code = "extends Node3D\nvar target: Node3D = null\n"
	rig_script.reload()
	var rp_script := GDScript.new()
	rp_script.source_code = "extends Node\nvar rig: Node3D = null\nvar avatar: Node3D = null\nvar cursor_item := \"\"\nvar cursor_tool := \"\"\n"
	rp_script.reload()
	var real_player = ui.player
	var rig_player: Node = rp_script.new()
	var world_holder := Node3D.new()
	add_child(world_holder)
	rig_player.rig = rig_script.new()
	rig_player.avatar = Node3D.new()
	world_holder.add_child(rig_player.rig)
	world_holder.add_child(rig_player.avatar)
	add_child(rig_player)
	ui.player = rig_player
	sent()
	key(KEY_L)
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.networks.is_open() and sent_one("lnets").size() > 0, "L opens the logistic networks window and asks for them")
	m.handle({"t": "lnets", "l": [[4, 1, "nauvis", [998, 1000], [201, 201], 34, 22, 138, 108, 2560, 512, ""],
		[9, 4, "vulcanus", [10, 12], [0, 5], 2, 1, 3, 1, 0, 0, "[item=iron-plate] Mall"]]})
	m.handle({"t": "lnet", "id": 4, "found": 1, "log": [998, 1000], "con": [201, 201], "items": [["stone", 17750], ["copper-cable", 9600]]})
	await get_tree().process_frame
	var net_texts := _texts(ui.networks)
	var robots_slot = ui.networks.find_child("Member_logistic-robot", true, false)
	check(ui.networks.selected == 4 and ui.networks._items.get_child(1).get("item") == "copper-cable" and robots_slot != null and robots_slot.count == 1000
		and robots_slot.tip_title == "Logistic robots: 998 / 1000 available" and net_texts.any(func(t) -> bool: return str(t).begins_with("[Iron plate] Mall")),
		"every network with its robots, the selected one's items: %s" % [net_texts.slice(0, 12)])
	var looks: Array = []
	var catch_net := func(at: Vector2, si: int) -> void: looks.append([at, si])
	ui.networks.show_at.connect(catch_net)
	(ui.networks.find_child("LookAtIt", true, false) as Button).pressed.emit()
	ui.networks.show_at.disconnect(catch_net)
	check(looks == [[Vector2(10, 2), 1]], "Look at it goes to a roboport of the network: %s" % [looks])
	await get_tree().process_frame
	check(ui.remote and ui.remote_frame.visible and ui.remote_frame.networks_open and not ui.map_view.surfaces_panel.visible
		and not (ui.remote_frame.title_bar.find_child("Search", true, false) as Control).visible,
		"as in Factorio it opens in the remote view: the frame's title bar without search, its frames where the Surfaces panel was %s")
	ui.networks.open(true)
	key(KEY_L)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not ui.networks.is_open() and not ui.remote, "L again closes it, and the remote view it opened")
	key(KEY_L)
	await get_tree().process_frame
	await get_tree().process_frame
	ui.remote_frame.close_requested.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not ui.networks.is_open() and not ui.remote, "the remote view's close closes the networks window too")
	ui.player = real_player
	rig_player.queue_free()
	world_holder.queue_free()

	# --- statistics: tabs, surfaces, graphs ------------------------------------------------------
	sent()
	key(KEY_P)
	await get_tree().process_frame
	sent()
	check(ui.stats._tabs.get_child_count() == 5 and ui.stats._scales.get_child_count() == 9,
		"production statistics has Factorio's tabs (Items, Fluids, Buildings, Pollution, Kills) and nine time scales (5s ... All)")
	_find_button(ui.stats, "Pollution").pressed.emit()
	var ask := sent_one("stats")
	check(ask.get("kind") == "pollution" and ask.get("g") == [], "the Pollution tab asks for pollution with graph lines: %s" % [ask])
	m.handle({"t": "stats", "kind": "pollution", "prec": ask.get("prec", 2), "si": 1, "l": [["boiler", 30.0, 0.0, 1800, 0], ["grass-1", 0.0, 20.0, 0, 1200]],
		"gr": [["boiler", [1, 2, 3], [0, 0, 0]], ["grass-1", [0, 0, 0], [5, 4, 3]]]})
	await get_tree().process_frame
	var side0: Node = ui.stats._sides[0]["grid"]
	var side1: Node = ui.stats._sides[1]["grid"]
	check(ui.stats._in_graph.lines.size() == 2 and ui.stats._colors.size() == 2 and side0.find_child("Row_boiler", false, false) != null
		and side0.find_child("Row_grass-1", false, false) == null and side1.find_child("Row_grass-1", false, false) != null,
		"two panels, each with a graph line per drawn row and its own rows (produced left, consumed right)")
	sent()
	(ui.stats._sides[0]["universe"] as CheckBox).button_pressed = true
	check(sent_one("stats").get("si") == 0 and (ui.stats._sides[1]["universe"] as CheckBox).button_pressed,
		"Universe statistics asks for every surface's statistics (both panels' boxes follow)")
	(ui.stats._sides[0]["universe"] as CheckBox).button_pressed = false
	sent()
	var row_boiler: Control = side0.find_child("Row_boiler", false, false)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	row_boiler.gui_input.emit(click)
	check(not (sent_one("stats").get("g", []) as Array).has("boiler"), "clicking a drawn row takes its line away")
	sent()
	(ui.stats._sides[0]["box"].find_child("Reset", true, false) as Button).pressed.emit()
	check(ui.stats.graph_names.is_empty() and (sent_one("stats").get("g", []) as Array).has("boiler"), "reset draws the busiest again")
	sent()
	(ui.stats._scales.get_child(8) as Button).pressed.emit()
	check(sent_one("stats").get("prec") == 9 and ui.stats.prec == ui.stats.ALL, "All asks for prec 9 (rows by all-time totals)")
	m.handle({"t": "stats", "kind": "pollution", "prec": 9, "si": 1, "l": [["boiler", 30.0, 0.0, 1800, 0]], "gr": []})
	await get_tree().process_frame
	check(_texts(ui.stats._sides[0]["grid"]).has("1.8k"), "All shows the all-time totals: %s" % [_texts(ui.stats._sides[0]["grid"])])
	ui.stats.toggle_search()
	ui.stats._search_box.text = "nothing like it"
	ui.stats._search_box.text_changed.emit(ui.stats._search_box.text)
	check(ui.stats._sides[0]["grid"].find_child("Row_boiler", false, false) == null, "the search hides rows that don't match")
	ui.stats.toggle_search()
	(ui.stats._scales.get_child(0) as Button).pressed.emit()
	ui.stats.visible = false
	ui.stats.toggle("electric", {"u": 9})
	await get_tree().process_frame
	check(ui.stats._title.text == "Electric network info" and ui.stats._summary.visible and not ui.stats._tabs.visible
		and ui.stats._sides[2]["box"].visible, "a pole opens Electric network info: summary bars, no tabs, three panels")
	m.handle({"t": "stats", "kind": "electric", "prec": ui.stats.prec, "l": [["steam-engine", 0.0, 540.0, 0, 32400],
		["inserter", 540.0, 0.0, 792, 0]], "st": [["accumulator", 1000, 5000000]]})
	await get_tree().process_frame
	check(_texts(ui.stats).has("9 W / 9 W") and _texts(ui.stats).has("5 MJ") and ui.stats._sides[2]["grid"].find_child("Row_accumulator", false, false) != null,
		"satisfaction, the accumulators' charge and their rows: %s" % [_texts(ui.stats._summary)])
	m.handle({"t": "stats", "kind": "electric", "prec": ui.stats.prec, "l": [["steam-engine", 0.0, 540.0, 0, 32400]],
		"st": [], "ef": [500, 1000, 500, 2000, 2500000, 5000000]})
	await get_tree().process_frame
	check(_texts(ui.stats).has("30 kW / 60 kW") and _texts(ui.stats).has("30 kW / 120 kW") and _texts(ui.stats).has("2.5 MJ / 5 MJ")
		and is_equal_approx((ui.stats._bars["Satisfaction"][0] as ProgressBar).value, 0.5),
		"the summary bars from the network's last update (flow_last_tick): %s" % [_texts(ui.stats._summary)])
	ui.stats.visible = false

	# --- the game-wide windows: bonuses, alerts configuration, achievements, permissions -----------
	sent()
	ui.open_global("bonuses")
	check(ui.bonuses.is_open() and sent_one("bonuses").get("t") == "bonuses", "the Bonuses window asks for the force's bonuses")
	m.handle({"t": "bonus", "l": [["inserter_stack_size_bonus", 1, ["inserter"]], ["worker_robots_speed_modifier", 0.35, ["logistic-robot", "construction-robot"]],
		["worker_robots_storage_bonus", 1, ["logistic-robot", "construction-robot"]], ["ammo_damage:bullet", 0.8, ["firearm-magazine"]],
		["turret_attack:gun-turret", 0.4, ["gun-turret"]]]})
	await get_tree().process_frame
	var bt := _texts(ui.bonuses)
	check(bt.has("Inserter capacity: +1") and bt.has("Movement speed: +35%\nCargo capacity: +1") and bt.has("Damage: +80%")
		and bt.has("Damage: +40%\n(Stacks with ammo bonuses)") and ui.bonuses._grid.get_child_count() % 4 == 0,
		"bonuses in Factorio's words, the same things' bonuses in one cell, four to a row: %s" % [bt])
	ui.open_global("bonuses")
	check(not ui.bonuses.is_open(), "its toggle closes it")
	ui.open_global("alerts")
	var ac = ui.alerts_config
	check(ac.is_open() and ac._table.get_child_count() == 5 * (1 + ac.TYPES.size()), "Alerts configuration: Icon, Name, Muted, Disabled, Latest for every alert type")
	(ac.find_child("SortName", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check(ac.sort_by == "Name" and ac.rows()[0][1][0] == "Asteroid collector blocked", "clicking Name sorts by name")
	ac.set_flag("Entity destroyed", "disabled", true)
	check(ui.alerts.hidden_kinds.has("destroyed"), "a disabled alert leaves the alert bar")
	ac.set_flag("Entity destroyed", "disabled", false)
	check(not ui.alerts.hidden_kinds.has("destroyed"), "and comes back")
	ac.open(false)
	ui.open_global("achievements")
	check(ui.achievements.is_open() and str(ui.achievements._earned.text).begins_with("Earned 0 of"), "Achievements: the progress line (modded: none earned)")
	ui.achievements.open(false)
	sent()
	ui.open_global("permissions")
	check(sent_one("perms").get("t") == "perms", "the Permissions window asks for the groups")
	m.handle({"t": "perms", "me": "", "l": [["Default", ["Alice", "Bob"]], ["Admin", ["Carol"]]]})
	await get_tree().process_frame
	var pw = ui.permissions
	check(pw.selected == "Default" and (pw.find_child("Row_Default", true, false) as Button).theme_type_variation == "FListItemSelected"
		and pw._members.get_child_count() == 2, "the first group is selected, its players listed")
	(pw.find_child("Row_Admin", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	check(pw.selected == "Admin" and _texts(pw._members) == ["Carol"], "clicking a group shows its players")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not pw.is_open(), "Esc closes it")

	# --- rich text and the chat ----------------------------------------------------------------------
	check(RichText.plain("[item=iron-plate] for [color=1,0,0]Alice[/color] at [gps=10,-5]") == "[Iron plate] for Alice at [10, -5]",
		"rich text without its tags: %s" % RichText.plain("[item=iron-plate] for [color=1,0,0]Alice[/color] at [gps=10,-5]"))
	var plat_label := RichText.label("[planet=vulcanus] smelter")
	check(RichText.parse("[planet=vulcanus] smelter")[0]["t"] == "icon" and plat_label.get_parsed_text().contains("smelter"),
		"a platform name with [planet=vulcanus] is drawn with the planet's icon (the platform panel's rows)")
	plat_label.free()
	var toks: Array = RichText.parse("[font=default-bold]A[/font][color=red]B[/color][train=5][unknown=x]")
	check(toks.size() == 4 and toks[0]["font"] == "bold" and toks[1]["color"] == RichText.COLORS["red"] and toks[2]["t"] == "train"
		and toks[3]["s"] == "[unknown=x]", "fonts, colours, trains; unknown tags stay as written: %s" % [toks])
	var pings: int = m.live_pings().size()
	m.handle({"t": "chat", "from": "Alice", "c": [1, 0.5, 0], "text": "Iron at [gps=10,-5,nauvis] [item=iron-plate] [color=red]now[/color]"})
	await get_tree().process_frame
	var line: RichTextLabel = ui.chat._lines.get_child(ui.chat._lines.get_child_count() - 1)
	check(line.get_parsed_text().begins_with("Alice: Iron at ") and line.get_parsed_text().contains("[10, -5]") and m.live_pings().size() == pings + 1,
		"a chat line in rich text: the name, icons, colours, the gps link; it pings the map: %s" % line.get_parsed_text())
	var gps_seen: Array = []
	var catch_gps := func(at: Vector2, _s: String, clicked: bool) -> void: gps_seen.append([at, clicked])
	ui.chat.gps.connect(catch_gps)
	line.meta_clicked.emit("gps:10,-5,nauvis")
	ui.chat.gps.disconnect(catch_gps)
	check(gps_seen == [[Vector2(10, -5), true]], "clicking a gps link looks there")

	# --- the technology screen's details -------------------------------------------------------------
	m.handle({"t": "techs", "part": 1, "parts": 1, "l": [
		["automation", "a", [], [["automation-science-pack", 1]], 10, 10, 2, "", [["unlock-recipe", "assembling-machine-1", 0]], 1, 1, [], 0, ""],
		["steam-power", "a", [], [], 1, 0, 1, "craft-item", [["unlock-recipe", "boiler", 0]], 1, 1, ["craft-item", "iron-plate", 50], 0, ""],
		["mining-productivity-3", "b", ["automation"], [["automation-science-pack", 1]], 1000, 60, 1, "", [["mining-drill-productivity-bonus", "", 0.1]],
			7, -1, [], 250, "1000*(L - 2)"]]})
	ui.open_research(true)
	ui.research.select("mining-productivity-3")
	await get_tree().process_frame
	await get_tree().process_frame
	var rt := _texts(ui.research)
	check(rt.has("Mining productivity 7 (Available)") and rt.has("Infinite technology: each level costs more") and rt.has("Units: 1000*(L - 2) (L: the level)")
		and rt.has("25% researched before it was stopped") and rt.any(func(t) -> bool: return str(t).contains("Mining drill productivity bonus")),
		"an infinite technology by its level, its formula, kept progress and bonus: %s" % [rt.filter(func(t) -> bool: return str(t) != "").slice(0, 30)])
	ui.research.select("steam-power")
	await get_tree().process_frame
	await get_tree().process_frame
	rt = _texts(ui.research)
	check(rt.has("Craft 50 × Iron plate") and rt.has("Effects"), "a trigger technology's task and what it unlocks")
	ui.research.select("automation")
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.research._tree_slots.has("mining-productivity-3") and ui.research._tree_slots["mining-productivity-3"].position.y > ui.research._tree_slots["automation"].position.y
		and ui.research._tree_slots["automation"].size.x > ui.research._tree_slots["mining-productivity-3"].size.x,
		"the tree centres on the selected technology, drawn large, with what needs it below")
	ui.research.go_back()
	check(ui.research.selected == "steam-power", "back goes to the technology selected before")
	ui.research.go_forward()
	check(ui.research.selected == "automation", "and forward again")
	ui.research._search.text = "boiler"
	ui.research._refresh_tree()
	check(ui.research._slots["steam-power"].modulate.a == 1.0 and ui.research._slots["automation"].modulate.a < 1.0,
		"the technology search finds what unlocks a recipe; the rest dims")
	ui.research._search.text = ""
	ui.close_all()


func _collect(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c.get("thing") != null and c is Button:
			out.append(c)
		_collect(c, out)


func _find_slot_item(node: Node, item: String) -> Control:
	for c in node.get_children():
		if c is Button and c.get("item") == item and (c as Control).is_visible_in_tree():
			return c
		var found := _find_slot_item(c, item)
		if found != null:
			return found
	return null


## Factorio's marks in the world: the build cursor's model ghost (its model, end and way, red where
## something's in the way) and belt arrows, hover marks (selection corners, inserter arrows, fluid
## connections, a drill's area and output), roboport areas, Alt-mode with no recipe, and clicking
## anywhere on a train.
func _world_marks(hud: Hud) -> void:
	var m: UiModel = hud.ui.model
	var world := WorldMirror.new()
	world.protos.add_entities([
		[1, "transport-belt", "transport-belt", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[2, "underground-belt", "underground-belt", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[3, "long-handed-inserter", "inserter", -0.5, -0.5, 0.5, 0.5, 200, 60, 60, 1, 1],
		[4, "roboport", "roboport", -2, -2, 2, 2, 120, 120, 120, 4, 4],
		[5, "electric-mining-drill", "mining-drill", -1.5, -1.5, 1.5, 1.5, 120, 120, 120, 3, 3],
		[6, "steam-engine", "generator", -1.5, -2.5, 1.5, 2.5, 120, 120, 120, 3, 5],
		[7, "locomotive", "locomotive", -1, -3, 1, 3, 120, 120, 120, 2, 6],
		[8, "assembling-machine-2", "assembling-machine", -1.5, -1.5, 1.5, 1.5, 120, 120, 120, 3, 3],
	])
	m.handle({"t": "eprops", "l": [[2, 5, 0, 0], [3, 0, 0, 0, {"ip": [0, -2], "id": [0, 2.2]}], [4, 0, 0, 0, {"lr": 25, "cr": 55}],
		[5, 0, 0, 0, {"mr": 2.49, "vp": [0, -1.85], "fb": [[-1, 0, 12, "b"]], "fo": 1}],
		[6, 0, 0, 0, {"fb": [[0, 2, 8, "b"], [0, -2, 0, "b"]]}], [8, 0, 0, 0, {"fb": [[0, -1, 0, "i"], [0, 1, 8, "o"]], "fo": 1}]]})
	check(m.eprops[3]["x"].get("ip") == [0, -2] and m.eprops[2]["x"].is_empty(), "eprops' overlay is kept")
	world.chunks[Vector2i.ZERO] = ChunkView.new()
	var input := PlayerInput.new()
	input.world = world
	input.hud = hud

	# --- the build cursor: model, end, way, arrows ------------------------------------------------
	var belt: ProtoDB.EntityProto = world.protos.entity(1)
	check(ModelLibrary.mesh_for_entity("transport-belt", "transport-belt", input.build_extra(belt, Vector2(3.5, 3.5), 4), 4) != null,
		"a held belt is drawn as its model")
	var belt_marks := CursorOverlay.marks_for("transport-belt", {}, Vector2(3.5, 3.5), 4, true)
	check(belt_marks.size() == 1 and belt_marks[0]["dir"].is_equal_approx(Vector2(1, 0)), "a belt being placed east shows an arrow east")
	check(CursorOverlay.marks_for("transport-belt", {}, Vector2(3.5, 3.5), 4, false).is_empty(), "but not when hovered")
	var under: ProtoDB.EntityProto = world.protos.entity(2)
	check(input.build_extra(under, Vector2(10.5, 5.5), 4) == {"u": "i"}, "an underground with nothing behind it is an entrance")
	world._add([50, 2, 7 * 256 + 128, 5 * 256 + 128, 4, {"u": "i"}])
	check(input.build_extra(under, Vector2(10.5, 5.5), 4) == {"u": "o"}, "one ahead of an entrance facing the same way is its exit")
	check(input.build_extra(under, Vector2(10.5, 5.5), 12) == {"u": "i"}, "facing the other way it is an entrance")
	check(input.build_extra(under, Vector2(14.5, 5.5), 4) == {"u": "i"}, "out of reach it is an entrance")
	check(ModelLibrary.turn_dir("underground-belt", 4, {"u": "o"}) == 12 and ModelLibrary.turn_dir("underground-belt", 4, {"u": "i"}) == 4,
		"an exit's model is turned round (its direction is the way items go, its model faces its entrance)")
	check(ModelLibrary.turn_dir("furnace", 8, {}, "crusher") == 0 and ModelLibrary.turn_dir("furnace", 12, {}, "crusher") == 0
		and ModelLibrary.model_name("crusher", "furnace", {}, 8) == "crusher"
		and ModelLibrary.model_name("crusher", "furnace", {}, 4) == "crusher-east"
		and ModelLibrary.model_name("crusher", "furnace", {}, 12) == "crusher-east",
		"a crusher facing south looks like facing north, west like east: a model per picture, unturned")
	check(ModelLibrary.turn_dir("assembling-machine", 12, {}, "foundry") == 0, "a foundry looks the same every way round")
	# The burner drill's stand never turns in Factorio: a model per direction, drawn unturned, with
	# its auger, gears and rod moving while it works.
	var drill_kinds := {}
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for_entity("burner-mining-drill", "mining-drill", {}, 4):
		drill_kinds[part.kind] = true
	check(ModelLibrary.model_name("burner-mining-drill", "mining-drill", {}, 4) == "burner-mining-drill-east"
		and ModelLibrary.model_name("burner-mining-drill", "mining-drill", {}, 12) == "burner-mining-drill-west"
		and ModelLibrary.model_name("burner-mining-drill", "mining-drill", {}, 0) == "burner-mining-drill"
		and ModelLibrary.turn_dir("mining-drill", 8, {}, "burner-mining-drill") == 0
		and ModelLibrary.mesh_for_entity("burner-mining-drill", "mining-drill", {}, 8) != ModelLibrary.mesh_for("burner-mining-drill")
		and drill_kinds.has("spin_drill") and drill_kinds.has("gear_bmd_ns") and drill_kinds.has("gear_bmd_r_ew")
		and drill_kinds.has("slide_bmd_rod"),
		"the burner drill: a model per direction, unturned, its auger, gears and rod moving: %s" % [drill_kinds.keys()])
	# Steam power: Factorio renders each direction on its own, so a model per direction, unturned;
	# the steam engine has one per axis, its east-west flywheel turning about north-south.
	var engine_kinds := {}
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for_entity("steam-engine", "generator", {}, 12):
		engine_kinds[part.kind] = part.axis
	var pump_slides := []
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for_entity("offshore-pump", "offshore-pump", {}, 4):
		pump_slides.append(part.slide)
	check(ModelLibrary.model_name("boiler", "boiler", {}, 8) == "boiler-south"
		and ModelLibrary.model_name("steam-engine", "generator", {}, 8) == "steam-engine"
		and ModelLibrary.model_name("steam-engine", "generator", {}, 12) == "steam-engine-east"
		and ModelLibrary.turn_dir("generator", 12, {}, "steam-engine") == 0
		and ModelLibrary.turn_dir("offshore-pump", 4, {}, "offshore-pump") == 0
		and ModelLibrary.mesh_for_entity("boiler", "boiler", {}, 4) != ModelLibrary.mesh_for("boiler")
		and ModelLibrary.mesh_for_entity("burner-generator", "burner-generator", {}, 4) == ModelLibrary.mesh_for("steam-engine-east")
		and engine_kinds.get("spin_flywheel_ns", Vector3.ZERO) == Vector3.BACK
		and pump_slides.size() == 2 and pump_slides[0] == Vector3(0.16, 0.0, 0.0),
		"steam power: a model per direction, unturned, flywheel and pistons moving their way: %s %s" % [engine_kinds, pump_slides])
	# The pipe-to-ground's pictures and the valves' plates aren't turned copies: a model each way round.
	check(ModelLibrary.model_name("pipe-to-ground", "pipe-to-ground", {}, 4) == "pipe-to-ground-east"
		and ModelLibrary.model_name("pipe-to-ground", "pipe-to-ground", {}, 0) == "pipe-to-ground"
		and ModelLibrary.turn_dir("pipe-to-ground", 12, {}, "pipe-to-ground") == 0
		and ModelLibrary.model_name("overflow-valve", "valve", {}, 8) == "overflow-valve-south"
		and ModelLibrary.turn_dir("valve", 8, {}, "overflow-valve") == 0,
		"pipe-to-ground and valves: a model per direction, unturned")
	# Cargo bays frame the cargo area with Factorio's connection tileset, per 2x2 cell: a lone
	# cell's corner, a wall where a neighbour joins beside it, inner corners, nothing inside.
	check(ModelLibrary.cargo_pieces(56) == ["cargo-bay-corner-nw"] and ModelLibrary.cargo_pieces(248) == ["cargo-bay-wall-n"]
		and ModelLibrary.cargo_pieces(250) == ["cargo-bay-inner-nw", "cargo-bay-inner-ne"]
		and ModelLibrary.cargo_pieces(42) == ["cargo-bay-wall-w", "cargo-bay-inner-ne", "cargo-bay-inner-se"]
		and ModelLibrary.cargo_pieces(255).is_empty(), "cargo bays: the connection pieces follow Factorio's tileset")
	var cw := WorldMirror.new()
	cw.protos.add_entities([[1, "space-platform-hub", "space-platform-hub", -4, -4, 4, 4, 120, 120, 120, 8, 8],
		[2, "cargo-bay", "cargo-bay", -2, -2, 2, 2, 120, 120, 120, 4, 4]])
	for c in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
		cw.chunks[c] = ChunkView.new()
	cw._add([1, 2, 30 * 256, 20 * 256, 0])  # a lone bay: a corner in each cell
	var lone_cb := int(cw.entities[1].extra.get("cb", -1))
	cw._add([2, 1, 0, 0, 0])  # the hub, and two bays north of it: one in line, one half past its corner
	cw._add([3, 2, 0, -6 * 256, 0])
	cw._add([4, 2, 4 * 256, -6 * 256, 0])
	var cells := func(key) -> Array:
		var cb := int(cw.entities[key].extra.get("cb", -1))
		return [0, 1, 2, 3].map(func(k): return ModelLibrary.cargo_pieces((cb >> (8 * k)) & 255))
	var in_line: Array = cells.call(3)
	var past: Array = cells.call(4)
	check(lone_cb >= 0 and ModelLibrary.cargo_pieces(lone_cb & 255) == ["cargo-bay-corner-nw"]
		and ModelLibrary.cargo_pieces((lone_cb >> 24) & 255) == ["cargo-bay-corner-se"]
		and in_line == [["cargo-bay-corner-nw"], ["cargo-bay-wall-n"], ["cargo-bay-wall-w"], []]
		and past == [["cargo-bay-wall-n"], ["cargo-bay-corner-ne"], ["cargo-bay-inner-se"], ["cargo-bay-corner-se"]],
		"cargo bays: framed alone, joined to the hub and each other with no wall between: %s %s" % [in_line, past])
	cw._remove(3)
	check(cells.call(4)[0] == ["cargo-bay-corner-nw"], "cargo bays: a bay taken away opens its neighbour's side again")
	# Ghost bays (and the held bay's preview) are framed as they will be: joined to the hub and to
	# each other, while a built bay's frame doesn't open for a ghost beside it.
	cw.protos.add_entities([[3, "entity-ghost", "entity-ghost", -2, -2, 2, 2, 120, 120, 120, 4, 4]])
	var bay_proto: ProtoDB.EntityProto = cw.protos.entity(2)
	var before_ghost := int(cw.entities[4].extra.get("cb", -1))
	cw._add([5, 3, -6 * 256, -2 * 256, 0, {"gh": 2}])  # west of the hub
	cw._add([6, 3, -10 * 256, -2 * 256, 0, {"gh": 2}])  # west of that ghost
	cw._add([7, 3, 8 * 256, -6 * 256, 0, {"gh": 2}])  # east of the built bay 4
	var ghost_cells := func(x: float, y: float) -> Array:
		var cb := cw.cargo_mask(WorldMirror.cargo_rect(bay_proto, Vector2(x, y)), true)
		return [0, 1, 2, 3].map(func(k): return ModelLibrary.cargo_pieces((cb >> (8 * k)) & 255))
	var lone_ghost: Array = ghost_cells.call(30.0, 40.0)
	var by_hub: Array = ghost_cells.call(-6.0, -2.0)
	check(lone_ghost == [["cargo-bay-corner-nw"], ["cargo-bay-corner-ne"], ["cargo-bay-corner-sw"], ["cargo-bay-corner-se"]]
		and by_hub == [["cargo-bay-wall-n"], ["cargo-bay-wall-n"], ["cargo-bay-wall-s"], ["cargo-bay-wall-s"]]
		and int(cw.entities[4].extra.get("cb", -1)) == before_ghost
		and ModelLibrary.cargo_places(cw.cargo_mask(WorldMirror.cargo_rect(bay_proto, Vector2(30, 40))), Vector3(30, 0, 40))[3]
			== ["cargo-bay-corner-se", Vector3(31, 0, 41)],
		"cargo bays: a ghost is framed to its 4x4, joined to the hub and other ghosts, built bays unmoved: %s %s" % [lone_ghost, by_hub])
	cw._remove(6)
	check(ghost_cells.call(-6.0, -2.0)[0] == ["cargo-bay-corner-nw"], "cargo bays: a ghost taken away opens its neighbour ghost's side")
	cw.free()
	# Inserter platforms: Factorio's four renders sit a little differently, a model for each.
	var platforms_ok := true
	for ins in ["burner-inserter", "inserter", "long-handed-inserter", "fast-inserter", "bulk-inserter", "stack-inserter"]:
		platforms_ok = platforms_ok and ModelLibrary.model_name(ins, "inserter", {}, 4) == ins + "-east" \
			and ModelLibrary.model_name(ins, "inserter", {}, 8) == ins + "-south" \
			and ModelLibrary.turn_dir("inserter", 12, {}, ins) == 0 \
			and ModelLibrary.mesh_for_entity(ins, "inserter", {}, 12) is ArrayMesh \
			and ModelLibrary.mesh_for_entity(ins, "inserter", {}, 12) != ModelLibrary.mesh_for(ins)
	check(platforms_ok, "inserter platforms: a model per direction, drawn unturned")
	# The pumpjack and the chemical plant too: every direction its own model, unturned, with the
	# pumpjack's beam rocking on its upright frame and the plant's light blinking in each.
	var facing_ok := true
	# FUE5's models (assets/models/fue5/) have no upright beam or lamp: only their facings are checked.
	var jack_ours := not ModelLibrary._source("pumpjack").contains("/assets/models/fue5/")
	var plant_ours := not ModelLibrary._source("chemical-plant").contains("/assets/models/fue5/")
	for dir in [0, 4, 8, 12]:
		var jack := {}
		for part: ModelLibrary.AnimPart in ModelLibrary.parts_for_entity("pumpjack", "mining-drill", {}, dir):
			jack[part.kind] = part.upright
		var plant := ModelLibrary.mesh_for_entity("chemical-plant", "assembling-machine", {}, dir)
		facing_ok = facing_ok and (not jack_ours or (jack.get("rock_beam", false) and jack.get("spin_crank", false) and jack.has("still"))) \
			and (not plant_ours or ModelLibrary.glows(plant)) and ModelLibrary.turn_dir("mining-drill", dir, {}, "pumpjack") == 0 \
			and ModelLibrary.turn_dir("assembling-machine", dir, {}, "chemical-plant") == 0
	check(facing_ok and ModelLibrary.model_name("pumpjack", "mining-drill", {}, 8) == "pumpjack-south"
		and ModelLibrary.model_name("chemical-plant", "assembling-machine", {}, 4) == "chemical-plant-east"
		and ModelLibrary.mesh_for_entity("chemical-plant", "assembling-machine", {}, 12) != ModelLibrary.mesh_for("chemical-plant"),
		"the pumpjack and chemical plant: a model per direction, unturned, beam, crank and light moving in each")
	world._add([51, 6, 20 * 256, 20 * 256 + 128, 0])
	check(input._blocked(belt, Vector2(20.5, 20.5), Vector2i.ONE), "something in the way blocks the build (the ghost turns red)")

	# --- hover: selection corners, inserters, fluids, drills, roboports ---------------------------
	var ins: ProtoDB.EntityProto = world.protos.entity(3)
	var marks := input.hover_marks(ins, Vector2(0.5, 0.5), 4)
	var corners: Array = marks.filter(func(k): return k["k"] == "brackets")
	check(corners.size() == 1 and corners[0]["at"] == Vector2(0.5, 0.5) and corners[0]["half"] == Vector2(0.5, 0.5), "hover shows the selection box's corners")
	var arrows: Array = marks.filter(func(k): return k["k"] == "arrow")
	check(arrows.size() == 2 and arrows[0]["at"].is_equal_approx(Vector2(2.5, 0.5)) and arrows[1]["at"].is_equal_approx(Vector2(-1.7, 0.5))
		and arrows[0]["dir"].is_equal_approx(Vector2(-1, 0)),
		"a long inserter facing east: pickup arrow 2 east, drop arrow 2.2 west, pointing west (as in 2.1.23): %s" % [arrows])
	var engine := input.hover_marks(world.protos.entity(6), Vector2(0, 0.5), 4).filter(func(k): return k["k"] == "arrow")
	check(engine.size() == 2 and engine[0]["both"] and engine[0]["at"].is_equal_approx(Vector2(-2.62, 0.5)),
		"a steam engine facing east: two-way fluid arrows past its west and east ends: %s" % [engine])
	check(input.hover_marks(world.protos.entity(8), Vector2(0.5, 0.5), 0).size() == 1,
		"an assembler's fluid connections stay hidden (they show only with a fluid recipe)")
	var drill := input.hover_marks(world.protos.entity(5), Vector2(0.5, 0.5), 8)
	var drill_area: Array = drill.filter(func(k): return k["k"] == "area")
	var drill_out: Array = drill.filter(func(k): return k["k"] == "arrow")
	check(drill_area.size() == 1 and drill_area[0]["rect"].size.is_equal_approx(Vector2(4.98, 4.98))
		and drill_out.size() == 1 and drill_out[0]["at"].is_equal_approx(Vector2(0.5, 2.35)) and drill_out[0]["dir"].is_equal_approx(Vector2(0, 1)),
		"a drill facing south: its mining area and its output arrow south of it")
	var robo := input.hover_marks(world.protos.entity(4), Vector2(10, 10), 0).filter(func(k): return k["k"] == "area")
	check(robo.size() == 2 and robo[0]["rect"] == Rect2(-45, -45, 110, 110) and robo[1]["rect"] == Rect2(-15, -15, 50, 50)
		and robo[1]["edge"] == CursorOverlay.LOGISTIC_EDGE and robo[0]["edge"] == CursorOverlay.CONSTRUCTION_EDGE,
		"a roboport shows its construction (green) and logistic (orange) areas")
	check(CursorOverlay.marks_for("roboport", m.eprops[4]["x"], Vector2(10, 10), 0, true).size() == 2, "and so does one being placed")
	# H14: roboports whose logistic squares meet are linked, and Factorio draws the lines between them
	# while one is hovered (the game's own links, hinfo rn; the rule until it answers) or held.
	var links := RoboportLinksScript.new(null)
	links._ports[Vector2i(0, 0)] = [[Vector2(10, 10), 4, 501]]
	links._ports[Vector2i(1, 0)] = [[Vector2(55, 10), 4, 502]]
	links._ports[Vector2i(4, 0)] = [[Vector2(140, 10), 4, 503]]
	var held_links: Array = links.held_lines(Vector2(100, 10), 25.0)
	check(RoboportLinksScript.linked(Vector2.ZERO, 25.0, Vector2(50, 0), 25.0) and not RoboportLinksScript.linked(Vector2.ZERO, 25.0, Vector2(51, 0), 25.0)
		and held_links.size() == 3 and links.hovered_lines(Vector2(10, 10), 25.0, 501, [Vector2(55, 10)]).size() == 1
		and links.hovered_lines(Vector2(10, 10), 25.0, 501, null) == [[Vector2(10, 10), Vector2(55, 10)]]
		and links.hovered_lines(Vector2(10, 10), 25.0, 501, []).is_empty(),
		"roboport links: the held one's to its neighbours and theirs to each other, a hovered one's from the game (H14): %s" % [held_links])
	var overlay := CursorOverlay.new()
	add_child(overlay)
	overlay.show_marks(marks + robo + [CursorOverlay.line(Vector2(10, 10), Vector2(55, 10))])
	check(overlay.visible and overlay.mesh.get_surface_count() == 1, "the marks are drawn")
	overlay.show_marks([])
	check(not overlay.visible, "and hidden with none")
	overlay.queue_free()

	# --- Alt-mode: a machine with no recipe shows nothing -------------------------------------------
	m.handle({"t": "ai", "l": [[123, "recipe", "iron-gear-wheel"], [124, "recipe", ""]]})
	check(m.alt_icons.has(123) and not m.alt_icons.has(124), "Alt-mode: nothing over a machine whose recipe is empty")
	m.handle({"t": "ai", "l": [[124, "recipe", "iron-gear-wheel"]]})
	check(not m.alt_icons.has(123), "a machine whose recipe was cleared drops out with the next list")
	m.alt_icons.clear()

	# --- clicking a train anywhere on it -------------------------------------------------------------
	var movers := MoverLayer.new()
	movers.protos = world.protos
	add_child(movers)
	movers.handle({"t": "mv", "k": 1, "l": [[900, 7, 50 * 256, 50 * 256, 250]]})  # a locomotive facing east
	movers._process(10.0)
	var down := Vector3(0, -1, 0)
	var hit := movers.pick_ray(Vector3(52.6, 20, 50.3), down, ["locomotive"])
	check(not hit.is_empty() and int(hit[0]) == 900, "a click near the end of a locomotive (east of its middle, it faces east) opens it")
	check(movers.pick_ray(Vector3(50.3, 20, 52.6), down, ["locomotive"]).is_empty(), "beside it, it doesn't")
	var slant := Vector3(0, -1, 2).normalized()  # meets the ground at (50, 53), two tiles past the loco
	check(not movers.pick_ray(Vector3(50, 20, 13), slant, ["locomotive"]).is_empty(),
		"a click on the loco's side, over ground behind it, opens it")
	check(movers.pick(Vector2(52.6, 50.3), 1.6, ["locomotive"]).is_empty(), "(the old pick by distance to the middle missed it)")

	# --- the remote view fogs over and hides what no radar sees (remote_fog.gd) -----------------------
	var fog := RemoteFog.new()
	add_child(fog)
	movers.fog = fog
	fog.world = world
	var fog_chunks := {}
	# A radar's chunk, one of its chunks still on its way, one next to its 7 x 7, one far off.
	for c in [Vector2i(10, 10), Vector2i(12, 10), Vector2i(14, 10), Vector2i(20, 20)]:
		var fcv := ChunkView.new()
		fcv.loaded = c != Vector2i(12, 10)  # (no tiles: counts as ground drawn)
		world.add_child(fcv)
		world.chunks[c] = fcv
		fog_chunks[c] = fcv
	fog.update(true, Vector2(50, 50))
	movers._process(0.016)
	check(not fog.hiding() and movers.node_of(900).visible, "remote view: until the mod says what radars see, nothing is hidden")
	fog.handle({"t": "cov", "si": 1, "l": [10, 10, 3], "x": -300 * 256, "y": 0, "cr": 96})
	fog.update(true, Vector2(50, 50))
	movers._process(0.016)
	var fog_quad: MeshInstance3D = fog.get_node("RemoteFog")
	check(fog.hiding() and fog_quad.visible and not movers.node_of(900).visible,
		"remote view: the fog pass is on and a locomotive neither the radar nor the character sees is hidden")
	check(fog.seen(Vector2(330, 330)) and fog.seen(Vector2(-200, 0)) and not fog.seen(Vector2(500, 0)) and not fog.seen(Vector2(100, 10)),
		"remote view: a radar's 7 x 7 chunks and the chunks whose middle is within 112 tiles of the character are seen, nothing else")
	check(fog._image.get_pixelv(Vector2i(10, 10) - fog._origin).r > 0.5 and fog._image.get_pixelv(Vector2i(20, 20) - fog._origin).r < 0.5,
		"remote view: the fog's texture marks the radar's chunks seen and others not")
	var on_its_way := Vector2i(12, 10) - fog._origin
	check(fog.seen(Vector2(12 * 32 + 5, 10 * 32 + 5)) and fog._image.get_pixelv(on_its_way).r < 0.5,
		"remote view: a seen chunk whose ground hasn't arrived stays under the fog (no bare background)")
	fog_chunks[Vector2i(12, 10)].loaded = true
	fog._hide_chunks()
	fog.update(true, Vector2(50, 50))
	check(fog._image.get_pixelv(on_its_way).r > 0.5, "remote view: once its ground is drawn the fog lifts off it")
	check(fog_chunks[Vector2i(10, 10)].visible and fog_chunks[Vector2i(14, 10)].visible
		and not fog_chunks[Vector2i(20, 20)].visible and not world.chunks[Vector2i.ZERO].visible and fog.hidden_chunks() == 2,
		"remote view: chunks wholly under the fog aren't drawn; a seen one and its neighbour (under the soft edge) are")
	# Wires starting in a chunk no radar sees are hidden under the fog too.
	var fog_wires := WireLayerScript.new()
	fog_wires.fog = fog
	var seen_wire := MeshInstance3D.new()
	var unseen_wire := MeshInstance3D.new()
	fog_wires.add_child(seen_wire)
	fog_wires.add_child(unseen_wire)
	fog_wires._meshes[Vector2i(10, 10)] = seen_wire
	fog_wires._meshes[Vector2i(20, 20)] = unseen_wire
	fog_wires._apply_fog()
	var wires_fogged := seen_wire.visible and not unseen_wire.visible
	fog.update(false, Vector2(50, 50))
	fog_wires._apply_fog()
	check(wires_fogged and unseen_wire.visible, "remote view: wires where no radar sees are hidden, and back on leaving it")
	fog_wires.free()
	fog.update(true, Vector2(50, 50))
	# H13: a roboport's construction area counts as seen too (the UI model's list from `mrp`): one at
	# 648 tiles reaching 55 holds the middles of chunks 19-21 each way, not chunk 22's.
	var rp_model := UiModel.new()
	fog.model = rp_model
	rp_model.handle({"t": "mrp", "si": 1, "q": 1, "part": 1, "last": 1, "l": [648 * 256, 648 * 256, 25 * 256, 55 * 256]})
	fog.handle({"t": "cov", "si": 1, "l": [10, 10, 3], "x": -300 * 256, "y": 0, "cr": 96})  # left and back: cov again
	fog.update(true, Vector2(50, 50))
	check(fog.seen(Vector2(20 * 32 + 5, 20 * 32 + 5)) and fog.seen(Vector2(21 * 32 + 5, 19 * 32 + 5)) and not fog.seen(Vector2(22 * 32 + 5, 20 * 32 + 5)),
		"remote view: a roboport's construction area counts as seen, past it doesn't (H13)")
	check(fog._image.get_pixelv(Vector2i(20, 20) - fog._origin).r > 0.5 and fog_chunks[Vector2i(20, 20)].visible,
		"remote view: the fog lifts there and the chunk is drawn again")
	fog.model = null
	fog._dirty = true
	fog.update(true, Vector2(50, 50))
	var fog_mat := fog_quad.material_override as ShaderMaterial
	check(fog_mat.render_priority > 2 and fog_mat.render_priority < 10 and not fog_mat.shader.code.contains("hint_screen_texture"),
		"remote view: the fog is drawn over ghosts, smoke and item cards, under the build preview, without copying the screen")
	fog.update(false, Vector2(50, 50))
	movers._process(0.016)
	check(not fog_quad.visible and movers.node_of(900).visible and fog.seen(Vector2(500, 0)), "leaving the remote view shows everything again")
	check(fog_chunks[Vector2i(20, 20)].visible and world.chunks[Vector2i.ZERO].visible and fog.hidden_chunks() == 0,
		"leaving the remote view draws the chunks the fog hid again")
	for c in fog_chunks:
		world.chunks.erase(c)
		fog_chunks[c].free()
	fog.queue_free()
	movers.fog = null
	movers.queue_free()
	input.free()
	world.chunks[Vector2i.ZERO].free()
	world.free()


## Tiles in the cursor, capsules, the rail planner and drag building (tile_brush.gd,
## capsule_aim.gd, rail_planner.gd, drag_build.gd), on a world of the test's own.
func _build_tools(hud: Hud) -> void:
	PlayerInput.define_actions()
	var m: UiModel = hud.ui.model
	var world := WorldMirror.new()
	world.protos.add_entities([
		[1, "transport-belt", "transport-belt", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[2, "underground-belt", "underground-belt", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[3, "pipe", "pipe", -0.5, -0.5, 0.5, 0.5, 120, 120, 120, 1, 1],
		[4, "pipe-to-ground", "pipe-to-ground", -0.5, -0.5, 0.5, 0.5, 120, 120, 120, 1, 1],
		[5, "small-electric-pole", "electric-pole", -0.25, -0.25, 0.25, 0.25, 120, 90, 60, 1, 1],
		[6, "wooden-chest", "container", -0.5, -0.5, 0.5, 0.5, 150, 110, 60, 1, 1],
		[7, "straight-rail", "straight-rail", -1, -1, 1, 1, 130, 120, 110, 2, 2],
		[8, "stone-furnace", "furnace", -1, -1, 1, 1, 130, 120, 110, 2, 2],
	])
	world.protos.add_tiles([[1, "grass-1", 60, 90, 30], [2, "water", 50, 80, 120], [3, "concrete", 120, 120, 120]])
	var cv := ChunkView.new()
	world.chunks[Vector2i.ZERO] = cv
	cv.tile_ids.resize(ChunkView.SIZE * ChunkView.SIZE)
	cv.tile_ids.fill(1)
	cv.tile_ids[3 * ChunkView.SIZE + 5] = 2  # water at (5, 3)
	m.handle({"t": "eprops", "l": [[2, 5, 0, 0], [4, 10, 0, 0], [5, 0, 7.5, 2.5]]})
	m.handle({"t": "iuse", "part": 1, "parts": 1, "l": [["concrete", "t", "concrete", "", [1]],
		["hazard-concrete", "t", "hazard-concrete-left", "hazard-concrete-right", [1, 3]], ["grenade", "c", "throw", 15, 6.5],
		["rail", "r", "rail-support", 1], ["transport-belt", "b", "underground-belt"], ["pipe", "p", "pipe-to-ground"]]})
	check(m.item_uses["concrete"]["t"][2].has(1) and not m.item_uses["concrete"]["t"][2].has(2) and m.item_uses["grenade"]["c"][1] == 15.0
		and m.item_uses["rail"]["r"] == ["rail-support", 1] and m.item_uses["pipe"]["p"] == "pipe-to-ground", "iuse is read into item_uses")
	var had_slots: bool = m.has_slots
	m.has_slots = false
	hud.set_inventory([["concrete", 50], ["grenade", 5], ["rail", 100], ["rail-support", 5], ["transport-belt", 50],
		["underground-belt", 10], ["pipe", 50], ["pipe-to-ground", 10], ["small-electric-pole", 10], ["stone-furnace", 10]])
	var input := PlayerInput.new()
	input.world = world
	input.hud = hud
	for tool in [input.tile_brush, input.rail_planner, input.capsule_aim]:
		tool.pi = input
		add_child(tool)
	input.drag.pi = input
	sent()
	# From the remote view an open asks the mod for remote use (rv); from the character's view not.
	hud.ui.remote = true
	input._request_open(77, {"t": "open", "u": 77, "p": 1, "x": 0, "y": 0})
	await get_tree().process_frame
	var remote_open := sent_one("open")
	hud.ui.remote = false
	input._request_open(77, {"t": "open", "u": 77, "p": 1, "x": 0, "y": 0})
	await get_tree().process_frame
	var near_open := sent_one("open")
	check(remote_open.get("rv") == 1 and not near_open.has("rv"), "opening from the remote view asks for remote use (rv): %s %s" % [remote_open, near_open])
	hud.screen.close_local()
	sent()
	# F6: a module held and clicked on a building (or ghost) asks the mod for it (modreq), from the
	# remote view too; the click doesn't build or open anything.
	m.handle({"t": "iuse", "part": 2, "parts": 2, "l": [["speed-module", "m", "speed"]]})
	var machine := WorldMirror.Rec.new()
	machine.unit = 91
	machine.proto_id = 8
	machine.pos = Vector2(3, 3)
	machine.fixed = Vector2i(768, 768)
	input.cursor_item = "speed-module"
	input.hovered = machine
	input.has_ground = true
	input.ground = Vector2(3, 3)
	hud.ui.remote = true
	var mclick := InputEventMouseButton.new()
	mclick.button_index = MOUSE_BUTTON_LEFT
	mclick.pressed = true
	input._mouse_button(mclick)
	await get_tree().process_frame
	var mods_sent := sent()
	hud.ui.remote = false
	var modreq: Dictionary = mods_sent[0] if mods_sent.size() == 1 else {}
	check(modreq.get("t") == "modreq" and modreq.get("item") == "speed-module" and int(modreq.get("u", 0)) == 91
		and int(modreq.get("x", 0)) == 768 and not input._lmb_down, "a module clicked on a building asks for it (modreq, F6): %s" % [mods_sent])
	input.cursor_item = ""
	input.hovered = null
	# F6: the build preview is red over empty space (a platform's edge), with the reason.
	world.protos.add_tiles([[4, "empty-space", 0, 0, 0]])
	cv.tile_ids[3 * ChunkView.SIZE + 8] = 4  # empty space at (8, 3)
	check(input._on_void(Vector2(8.5, 3.5), Vector2i.ONE) and input._on_void(Vector2(8.0, 3.0), Vector2i(2, 2))
		and not input._on_void(Vector2(10.5, 3.5), Vector2i.ONE), "the build preview knows empty space under a footprint (F6)")
	cv.tile_ids[3 * ChunkView.SIZE + 8] = 1
	# F6: a ghost is picked by its entity's box (2.1.23's entity-ghost prototype has none), so a
	# module can be clicked onto a furnace's ghost anywhere on it.
	world.protos.add_entities([[9, "entity-ghost", "entity-ghost", 0, 0, 0, 0, 200, 200, 200, 1, 1]])
	world._add([95, 9, 7 * 256, 7 * 256, 0, {"gh": 8}])
	var picked: WorldMirror.Rec = world.pick(Vector2(7.7, 6.4))
	check(picked != null and picked.unit == 95 and world.pick(Vector2(8.2, 7.0)) == null, "a ghost is picked by its entity's box (F6)")
	world._remove(95)
	# Hovering a beacon asks the mod about it (hinfo); the entity info then lists its modules,
	# effectivity, the machines it reaches and what it hands on; a machine its beacons and effects.
	world.protos.add_entities([[10, "beacon", "beacon", -1.5, -1.5, 1.5, 1.5, 130, 120, 130, 3, 3],
		[11, "assembling-machine-2", "assembling-machine", -1.5, -1.5, 1.5, 1.5, 110, 140, 170, 3, 3]])
	var brec := WorldMirror.Rec.new()
	brec.key = 96
	brec.unit = 96
	brec.proto_id = 10
	brec.fixed = Vector2i(2560, 768)
	var einfo = hud.ui.entity_info
	var einfo_player = einfo.player
	einfo.player = input
	sent()
	einfo.show_entity(brec)
	var hask := sent_one("hinfo")
	m.handle({"t": "hinfo", "q": int(hask.get("q", 0)), "u": 96, "eff": {"sp": 1500, "co": 2100, "q": -25}, "m": [["speed-module-3", 2]],
		"n": 3, "de": 1500})
	einfo.show_entity(brec)
	var btext := "|".join(PackedStringArray(_texts(einfo._lines))).replace(":| ", ": ")
	check(int(hask.get("u", 0)) == 96 and int(hask.get("x", 0)) == 2560 and btext.contains("Modules:") and btext.contains("x2")
		and btext.contains("Distribution effectivity: 150%") and btext.contains("Machines affected: 3")
		and btext.contains("Module effects:") and btext.contains("Speed: +150%") and btext.contains("Consumption: +210%") and btext.contains("Quality: -2.5%"),
		"hovering a beacon asks hinfo and shows what it hands on: %s %s" % [hask, btext])
	einfo.show_entity(brec)
	check(sent_one("hinfo").is_empty(), "the same beacon isn't asked about again within a second")
	var arec := WorldMirror.Rec.new()
	arec.key = 97
	arec.unit = 97
	arec.proto_id = 11
	arec.fixed = Vector2i(768, 768)
	einfo.show_entity(arec)
	var aask := sent_one("hinfo")
	m.handle({"t": "hinfo", "q": int(aask.get("q", 0)) - 1, "u": 96, "eff": {"sp": 1}})
	check(m.hover_info.is_empty(), "an answer about an entity no longer hovered is dropped")
	m.handle({"t": "hinfo", "q": int(aask.get("q", 0)), "u": 97, "eff": {"sp": 3000, "co": 4200}, "b": 2})
	einfo.show_entity(arec)
	var atext := "|".join(PackedStringArray(_texts(einfo._lines))).replace(":| ", ": ")
	check(int(aask.get("u", 0)) == 97 and atext.contains("Beacons: 2") and atext.contains("Speed: +300%") and not atext.contains("Machines affected"),
		"hovering a machine shows the beacons reaching it and its effects: %s" % atext)
	# H20: an electric machine's "Consumes electricity": Max. and Min. consumption from the mod's
	# hinfo (with its modules) and the Electricity bar from its buffer, at the panel's foot.
	m.pedia_pages["entity/assembling-machine-2"] = {"found": true, "d": {"etype": "electric", "energy": 150000.0, "drain": 5000.0, "hp": 350}}
	m.handle({"t": "hinfo", "q": m._hinfo_q, "u": 97, "eff": {"sp": 3000, "co": 4200}, "b": 2,
		"el": {"e": 2500, "b": 5000, "mx": 155000, "mn": 5000}})
	einfo.show_entity(arec)
	var etext := "|".join(PackedStringArray(_texts(einfo._lines))).replace(":| ", ": ")
	var ebar = einfo._lines.find_child("Electricity", true, false)
	check(etext.contains("Consumes electricity") and etext.contains("Max. consumption: 155 kW") and etext.contains("Min. consumption: 5.0 kW")
		and not etext.contains("Energy consumption") and ebar is ProgressBar and int(ebar.value) == 500
		and etext.find("Consumes electricity") > etext.find("Health"),
		"a powered machine's entity info ends with Consumes electricity and its Electricity bar (H20): %s" % etext)
	check(EntityInfoScript.power_text(217000.0) == "217 kW" and EntityInfoScript.power_text(7000.0) == "7.0 kW"
		and EntityInfoScript.power_text(1.2e6) == "1.2 MW", "power written as Factorio's entity info writes it")
	m.pedia_pages.erase("entity/assembling-machine-2")
	einfo.show_entity(null)
	einfo.player = einfo_player
	# W walks the way the camera looks, at any angle (`a`, thousandths of a turn), with the
	# nearest of Factorio's 8 directions as `d` for mods without `a`; letting go stops.
	var walk_rig := CameraRig.new()
	add_child(walk_rig)
	walk_rig.rotation.y = 0.37
	await get_tree().process_frame
	input.rig = walk_rig
	get_viewport().gui_release_focus()  # a search box from the checks above would take the keys
	Input.action_press("move_up")
	input._update_walk(0.016)
	Input.action_release("move_up")
	await get_tree().process_frame
	var walk_go := sent_one("walk")
	input._update_walk(0.016)
	await get_tree().process_frame
	var walk_stop := sent_one("walk")
	var fwd := walk_rig.ground_forward()
	var want_turn := posmod(roundi(atan2(fwd.x, -fwd.z) / TAU * 1000.0), 1000)
	check(int(walk_go.get("a", -1)) == want_turn and want_turn % 125 != 0 and int(walk_go.get("d", -1)) == posmod(roundi(want_turn / 125.0), 8) * 2
		and int(walk_stop.get("d", 0)) == -1 and not walk_stop.has("a"),
		"WASD walks at the camera's angle (a) and stops on release: %s %s, want %d" % [walk_go, walk_stop, want_turn])
	input.rig = null
	walk_rig.queue_free()

	# --- tiles --------------------------------------------------------------------------------------
	check(TileBrush.brush(Vector2(4.6, 3.6), 2) == [Vector2i(4, 3), Vector2i(5, 3), Vector2i(4, 4), Vector2i(5, 4)]
		and TileBrush.brush(Vector2(4.6, 3.6), 3)[0] == Vector2i(3, 2), "the brush: even sizes on the nearest corner, odd ones on the tile (as tiles.lua)")
	input.tile_brush.size = 2
	var states := input.tile_brush.tile_states("concrete", Vector2(4.6, 3.6), false)
	var by_tile := {}
	for st in states:
		by_tile[st[0]] = st[1]
	check(by_tile[Vector2i(5, 3)] == "bad" and by_tile[Vector2i(4, 3)] == "ok", "the brush is red on water (iuse's tiles it may go on), green elsewhere")
	input.cursor_item = "concrete"
	for code in [KEY_KP_ADD, KEY_KP_ADD, KEY_KP_SUBTRACT]:
		var ev := Controls.key_event(code)
		ev.pressed = true
		input._unhandled_input(ev)
	check(input.tile_brush.size == 3, "Numpad + / - make the tile area larger and smaller")
	input.tile_brush.size = 2
	input.tile_brush.paint("concrete", Vector2(4.6, 3.6), false, 0.016)
	await get_tree().process_frame
	var t := sent_one("tile")
	check(t.get("item") == "concrete" and int(t.get("n", 0)) == 2 and not t.has("ghost"), "holding the button paints: `tile` with the brush size")
	input.tile_brush.mine(Vector2(4.6, 3.6), 1.0)
	await get_tree().process_frame
	check(int(sent_one("tile_mine").get("n", 0)) == 2, "the right button mines the tiles under the brush")
	input.cursor_item = "hazard-concrete"
	input._rotate(false)
	input.tile_brush.paint("hazard-concrete", Vector2(8.5, 3.5), true, 1.0)
	await get_tree().process_frame
	t = sent_one("tile")
	check(int(t.get("r", 0)) == 1 and int(t.get("ghost", 0)) == 1, "R turns hazard concrete's stripes; Shift paints tile ghosts")
	input.tile_brush.update_preview("hazard-concrete", true, Vector2(8.5, 3.5), false, false)
	check(input.tile_brush.visible and input.tile_brush.preview_counts()["shown"] == 4, "the brush is drawn at the cursor")
	input.tile_brush.update_preview("transport-belt", true, Vector2(8.5, 3.5), false, false)
	check(not input.tile_brush.visible, "and not for other items")

	# --- capsules -----------------------------------------------------------------------------------
	input.capsule_aim.hold("grenade", Vector2(3, 3), 0.016)
	await get_tree().process_frame
	var th := sent_one("throw")
	check(th.get("item") == "grenade" and int(th.get("x", 0)) == 768, "a click throws the capsule at the cursor (`throw`)")
	input.capsule_aim.hold("grenade", Vector2(3, 3), 0.1)
	await get_tree().process_frame
	check(sent_one("throw").is_empty(), "held, it throws again only after the capsule's cooldown")

	# --- the rail planner ---------------------------------------------------------------------------
	world._add([60, 7, 1 * 256, 1 * 256, 0])  # a north-south straight rail on (1, 1): ends (1, 0) north, (1, 2) south
	var end_n := input.rail_planner.nearest_end(Vector2(1.4, -0.6))
	check(end_n.size() == 3 and end_n[0] == Vector2i(1, 0) and int(end_n[1]) == 0, "the rail end nearest the cursor is found: %s" % [end_n])
	var straight := RailPlanner.find_path(Vector2i(1, 0), 0, 0, Vector2(1, -10))
	check(straight.size() == 5 and straight.all(func(p): return p["name"] == "straight-rail"), "straight ahead the path is straight rails")
	var bend := RailPlanner.find_path(Vector2i(1, 0), 0, 0, Vector2(12, -20))
	var joined := true
	var at := Vector2i(1, 0)
	var dir := 0
	var ext: Dictionary = RailPlanner.data()["ext"]
	for p in bend:
		var found := false
		for e in ext[str(dir)]:
			if str(e[0]) == p["name"] and int(e[1]) == p["dir"] and at + Vector2i(int(e[2]), int(e[3])) == p["pos"]:
				found = true
		joined = joined and found
		at = p["end"][0]
		dir = p["end"][1]
	check(not bend.is_empty() and joined and Vector2(at).distance_to(Vector2(12, -20)) <= 1.2
		and bend.any(func(p): return str(p["name"]).begins_with("curved")), "a path that turns: each piece one of Factorio's extensions from the last end")
	var t0 := Time.get_ticks_usec()
	var far := RailPlanner.find_path(Vector2i(1, 0), 0, 0, Vector2(60, -70))
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	check(not far.is_empty() and ms < 100.0, "a long winding path is found quickly (%.1f ms, %d pieces)" % [ms, far.size()])
	input.cursor_item = "rail"
	# Factorio's green arrows mark the free rail ends near the cursor before anchoring.
	input.rail_planner.update("rail", true, Vector2(2, 1), false)
	var free_arrows: Array = input.rail_planner.arrows.duplicate()
	check(not free_arrows.is_empty() and free_arrows.all(func(e): return e[3] == "free")
		and free_arrows.any(func(e): return e[0] == Vector2i(1, 0)) and input.rail_planner._arrows[0].visible,
		"holding rails shows Factorio's arrows at the free rail ends near the cursor: %s" % [free_arrows])
	check(input.rail_planner.click("rail", Vector2(1.2, -0.4), false) and input.rail_planner.anchor["pos"] == Vector2i(1, 0),
		"a click by a free rail end anchors the planner there")
	input.rail_planner.update("rail", true, Vector2(1, -10), false)
	check(input.rail_planner.arrows.size() == 1 and input.rail_planner.arrows[0][3] == "anchored",
		"once anchored only the anchored end's arrow is drawn")
	check(input.rail_planner.path.size() == 5 and input.rail_planner.rails_needed() == 5, "the path to the cursor is planned (5 rails)")
	input.rail_planner.click("rail", Vector2(1, -10), false)
	await get_tree().process_frame
	var rails := sent_one("rails")
	check(rails.get("item") == "rail" and (rails.get("l", []) as Array).size() == 5 and input.rail_planner.anchor["pos"] == Vector2i(1, -10),
		"a second click builds it (`rails`) and the planner carries on from its end")
	input.rail_planner.toggle_layer()
	input.rail_planner.update("rail", true, Vector2(1, -40), false)
	var names: Array = input.rail_planner.path.map(func(p): return str(p["name"]))
	check(names.has("rail-ramp") and names.has("rail-support") and names.has("elevated-straight-rail") and names[0] == "rail-support",
		"toggle rail layer: a ramp up, elevated rails, their supports listed first: %s" % [names])
	input.rail_planner.clear()
	check(not input.rail_planner.click("rail", Vector2(20, 20), false), "away from a rail end a click builds a plain straight rail")

	# --- drag building ------------------------------------------------------------------------------
	var belt: ProtoDB.EntityProto = world.protos.entity(1)
	input.cursor_item = "transport-belt"
	input.build_dir = 4
	input.drag.begin("transport-belt", belt, Vector2(10.5, 10.5), false)
	input.drag.update(Vector2(13.5, 10.5))
	input.drag.update(Vector2(13.5, 7.5))
	var steps := input.drag.sent.map(func(c): return [int(c["x"]) / 256, int(c["y"]) / 256, int(c["d"])])
	check(steps == [[10, 10, 4], [11, 10, 4], [12, 10, 4], [13, 10, 4], [13, 10, 0], [13, 9, 0], [13, 8, 0], [13, 7, 0]],
		"belts follow the cursor and turn the corner (the belt where it turns points the new way): %s" % [steps])
	input.drag.end()
	world._add([61, 6, 22 * 256 + 128, 10 * 256 + 128, 0])  # a chest in the way
	input.build_dir = 4
	input.drag.begin("transport-belt", belt, Vector2(20.5, 10.5), false)
	input.drag.update(Vector2(23.5, 10.5))
	steps = input.drag.sent.map(func(c): return [str(c["item"]), int(c["x"]) / 256, int(c["d"])])
	check(steps == [["transport-belt", 20, 4], ["transport-belt", 21, 4], ["underground-belt", 21, 4], ["underground-belt", 23, 4]],
		"smart belt building: the last belt before the chest becomes an underground, its exit past it: %s" % [steps])
	input.drag.end()
	world._add([62, 1, 4 * 256 + 128, 24 * 256 + 128, 0])  # a belt crossing the line (north)
	world._add([64, 1, 9 * 256 + 128, 24 * 256 + 128, 4])  # and one along it (east), which is replaced
	input.drag.begin("transport-belt", belt, Vector2(2.5, 24.5), false)
	input.drag.update(Vector2(6.5, 24.5))
	input.drag.update(Vector2(9.5, 24.5))
	steps = input.drag.sent.map(func(c): return [str(c["item"]), int(c["x"]) / 256])
	check(steps.slice(0, 5) == [["transport-belt", 2], ["transport-belt", 3], ["underground-belt", 3], ["underground-belt", 5],
		["transport-belt", 6]] and steps[-1] == ["transport-belt", 9], "a belt line crossing the way is jumped too; one along it is built over: %s" % [steps])
	input.drag.end()
	Settings.set_value("interface", "smart_belt_building", false, false)
	input.drag.begin("transport-belt", belt, Vector2(20.5, 16.5), false)
	world._add([65, 6, 22 * 256 + 128, 16 * 256 + 128, 0])
	input.drag.update(Vector2(24.5, 16.5))
	steps = input.drag.sent.map(func(c): return [str(c["item"]), int(c["x"]) / 256])
	check(steps == [["transport-belt", 20], ["transport-belt", 21], ["transport-belt", 23], ["transport-belt", 24]],
		"without smart belt building the obstacle is just skipped: %s" % [steps])
	Settings.set_value("interface", "smart_belt_building", true, false)
	input.drag.end()
	var pipe: ProtoDB.EntityProto = world.protos.entity(3)
	world._add([63, 6, 24 * 256 + 128, 28 * 256 + 128, 0])
	input.build_dir = 0
	input.drag.begin("pipe", pipe, Vector2(22.5, 28.5), false)
	input.drag.update(Vector2(26.5, 28.5))
	steps = input.drag.sent.map(func(c): return [str(c["item"]), int(c["x"]) / 256, int(c["d"])])
	check(steps.has(["pipe-to-ground", 23, 12]) and steps.has(["pipe-to-ground", 25, 4]) and steps[-1] == ["pipe", 26, 4],
		"pipes drag in a line; pipes-to-ground over the chest, facing back at the entrance and on at the exit: %s" % [steps])
	input.drag.end()
	var pole: ProtoDB.EntityProto = world.protos.entity(5)
	input.drag.begin("small-electric-pole", pole, Vector2(0.5, 20.5), false)
	for x in range(1, 17):
		input.drag.update(Vector2(x + 0.5, 20.5))
	steps = input.drag.sent.map(func(c): return int(c["x"]) / 256)
	check(steps == [0, 7, 14], "poles go along the line at the wire reach (7.5): %s" % [steps])
	input.drag.end()
	var furnace: ProtoDB.EntityProto = world.protos.entity(8)
	input.drag.begin("stone-furnace", furnace, Vector2(0, 26), false)
	for x in range(1, 7):
		input.drag.update(Vector2(x, 26))
	steps = input.drag.sent.map(func(c): return float(c["x"]) / 256.0)
	check(steps == [0.0, 2.0, 4.0, 6.0], "other buildings go one footprint after another along the line: %s" % [steps])
	input.drag.end()
	sent()
	m.has_slots = had_slots
	for tool in [input.tile_brush, input.rail_planner, input.capsule_aim]:
		tool.queue_free()
	# PlayerInput's own previews, made before _ready (which a test doesn't run) adds them anywhere.
	for n in [input._ghost, input._drag_box, input._reach_box, input._reach_lines, input._ghost_model, input._overlay]:
		n.free()
	input.free()
	cv.free()
	world.free()


## The minimap, the map view (M, Esc), the tag dialog's commands, and how charts are asked for.
func _map(ui) -> void:
	ui.map_cache.flush()
	check(ui.map_cache.is_charted(Vector2i(1, -2)) and not ui.map_cache.is_charted(Vector2i(5, 0)), "charts reach the map's pages")
	check(ui.minimap.visible, "minimap shows")
	sent()
	key(KEY_M)
	await get_tree().process_frame
	check(ui.map_open() and ui.minimap.visible, "M opens the map; the minimap stays (H22)")
	var view = ui.map_view
	view.centre = Vector2(300, -200)
	view.following = false
	view.zoom = 2.0
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.minimap.look_at == Vector2(300, -200) and ui.minimap._drawn_at == Vector2(300, -200) and ui.minimap.map_asks,
		"in the map view the minimap follows the map's view, which does the asking (H22): %s" % [ui.minimap._drawn_at])
	view.centre = Vector2.ZERO
	await get_tree().process_frame
	# Right click on empty ground: create a tag there.
	var spot: Vector2 = view.tiles_to_screen(Vector2(-20, 12))
	view.edit_tag_at(spot)
	check(view.dialog.is_open() and not view.dialog.editing, "right click opens the create-tag dialog")
	view.dialog.text_field.text = "Copper"
	view.dialog._pick("copper-ore")
	view.dialog._confirm()
	var add := sent_one("tag_add")
	check(add.get("text") == "Copper" and add.get("icon") == ["item", "copper-ore"]
		and absf(float(add.get("x", 0)) / 256.0 + 20.0) < 0.5 and absf(float(add.get("y", 0)) / 256.0 - 12.0) < 0.5
		and not view.dialog.is_open(), "confirm sends tag_add at the clicked spot")
	# On the existing tag (id 3 at 5, -2): edit, then delete.
	view.edit_tag_at(view.tiles_to_screen(Vector2(5, -2)))
	check(view.dialog.editing and view.dialog.text_field.text == "base" and view.dialog.icon_name == "iron-plate", "right click on a tag edits it")
	view.dialog.deleted.emit()
	view.dialog.close()
	check(sent_one("tag_del").get("id") == 3, "delete sends tag_del")
	view.edit_tag_at(view.tiles_to_screen(Vector2(5, -2)))
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not view.dialog.is_open() and ui.map_open(), "Esc closes the tag dialog first")
	var before: Vector2 = view.centre
	view.zoom_by(2.0, Vector2(10, 10))
	check(view.zoom == 4.0 and view.centre != before, "wheel zoom keeps the point under the mouse")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not ui.map_open() and ui.minimap.visible, "Esc closes the map")
	await get_tree().process_frame
	check(ui.minimap.look_at == Vector2.INF and not ui.minimap.map_asks, "and the minimap follows the character again")
	key(KEY_M)
	await get_tree().process_frame
	key(KEY_M)
	await get_tree().process_frame
	check(not ui.map_open(), "M again closes it")
	# The game menu (front_end.gd) gets Esc before the HUD and asks ui.escape(), so
	# everything the HUD can have open must say yes there, not only the windows in is_open().
	check(not ui.escape(), "with nothing open Esc is left to the game menu")
	var esc_cases := {
		"the map view": [func() -> void: ui.open_map(true), func() -> bool: return ui.map_open()],
		"the quickbar's page chooser": [func() -> void: ui.quickbar.open_chooser(0, true), func() -> bool: return ui.quickbar.chooser_open()],
		"the remote view": [func() -> void: ui.remote = true, func() -> bool: return ui.remote],
		"the blueprint library": [func() -> void: ui.planners.toggle_library(), func() -> bool: return ui.planners.library_window.is_open()],
		"the inventory": [func() -> void: ui.toggle_inventory(), func() -> bool: return ui.is_open()],
	}
	for what in esc_cases:
		esc_cases[what][0].call()
		await get_tree().process_frame
		var was_open: bool = esc_cases[what][1].call()
		var took := bool(ui.escape())
		check(was_open and took and not esc_cases[what][1].call(), "Esc closes %s instead of opening the game menu" % what)
		ui.close_all()
	check(not ui.escape(), "and then nothing is left open")
	# Requests: a 40 x 10 chunk area goes out as two blocks (the mod takes 32 x 32 at most), one at
	# a time; asking for the same area again sends nothing until the refresh.
	var cache = ui.map_cache
	sent()
	var n0: int = cache.requests_sent
	cache.want(Rect2i(0, 0, 40, 10), 4, 60.0)
	var req := sent_one("map")
	check(req.get("res") == 4 and int(req.get("cx2", 99)) - int(req.get("cx1", 0)) < 32 and cache.requests_sent == n0 + 1, "map request in blocks of 32 chunks")
	cache.want(Rect2i(0, 0, 40, 10), 4, 60.0)
	check(cache.requests_sent == n0 + 1, "same area: no new request while the first block is coming")
	# Settings: the minimap's switch and size.
	var settings = UiSettings.shared()
	settings.set_value("map/minimap", false)
	check(not ui.minimap.visible, "minimap setting hides it")
	settings.set_value("map/minimap", true)
	settings.set_value("map/minimap_size", 9999)
	check(settings.get_value("map/minimap_size") == 480 and ui.minimap.size.x == ui.minimap.side_px(), "minimap size is clamped and applied (as far as the window has room)")
	ui.minimap.set_max_side(INF)
	check(ui.minimap.size.x == Kit.px(480), "with room it is the full size")
	settings.set_value("map/minimap_size", 240)
	var cfg := ConfigFile.new()
	check(cfg.load(TEST_SETTINGS) == OK and cfg.get_value("map", "minimap_size") == 240, "UI settings are saved in the one settings file")
	Settings.set_value("map", "minimap", false)
	check(not ui.minimap.visible, "a change through settings.gd reaches the minimap too")
	Settings.set_value("map", "minimap", true)

	# The map view's layers: they come with the charts and follow the map view's switches.
	var m = ui.model
	m.handle({"t": "chart", "cx": 0, "cy": 0, "n": 1, "pal": [[10, 20, 30]], "px": [0], "ov": [
		["e", 2560, 2560, 2.5], ["t", 2816, 2560, 18], ["l", 3072, 3072, 25, 55], ["s", 2048, 2048, "Iron"],
		["g", 1536, 1536, 1], ["c", 3584, 2048, "iron-gear-wheel"], ["b", 1024, 1024]]})
	var ov: Array = m.map_overlays.get(Vector2i(0, 0), [])
	check(ov.size() == 7 and ov[0][0] == "e" and ov[0][1] == 10.0 and ov[3][3] == "Iron", "chart overlays reach the model in tiles")
	key(KEY_M)
	await get_tree().process_frame
	view.centre = Vector2(10, 10)
	view.following = false
	view.zoom = 4.0
	view._redraw = true
	await get_tree().process_frame
	var turrets: Button = view.panel.find_child("map-show_turrets", true, false)
	check(turrets != null and not turrets.button_pressed and not view.layers._groups["turret"][0].visible, "turret coverage is off by default")
	check(turrets.toggle_mode and turrets.theme_type_variation == "FSideButton" and turrets.tooltip_text == "Turret coverage"
		and view.panel.find_child("TrainsOverview", true, false) == null,
		"Factorio's map view settings: an icon toggle per layer with its name as the tooltip, no extra Trains button")
	turrets.button_pressed = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(bool(settings.get_value("map/show_turrets")) and view.layers._groups["turret"][0].visible, "the map view's switch turns turret coverage on")
	check(view.layers._visible_entries(0).size() == 7, "the layers find the chunk's entries in view")
	settings.set_value("map/show_electric", false)
	var electric: Button = view.panel.find_child("map-show_electric", true, false)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not electric.button_pressed and not view.layers._groups["electric"][0].visible, "a switch changed in Settings shows on the map view")
	settings.set_value("map/show_electric", true)
	settings.set_value("map/show_turrets", false)

	# The surface switcher: a button per planet and platform; another surface's map is asked for
	# with its `si`, its charts are kept apart, and closing the map goes back to the character's.
	m.set_character_surface(1)
	m.handle({"t": "surfs", "l": [[1, "nauvis", "nauvis", "", 0], [3, "vulcanus", "vulcanus", "", 0], [5, "platform-1", "", "Orbiter", 1]]})
	await get_tree().process_frame
	var vulcanus: Button = view.surfaces_panel.find_child("Surface3", true, false)
	check(view.surfaces_panel.visible and vulcanus != null and view.surfaces_panel.find_child("Surface5", true, false) != null,
		"the map lists the planets and platforms to switch to")
	# H13: the map's logistic layer shows every roboport of the surface (`mrp`), not only those in the
	# charts loaded, and their construction areas count as seen (not dimmed).
	var was_ready: bool = Bridge.world_ready
	Bridge.world_ready = true
	sent()
	m.ask_roboports(1)
	var mrp_ask := sent_one("mrp")
	m.ask_roboports(1)
	var mrp_again := sent_one("mrp")
	Bridge.world_ready = was_ready
	check(int(mrp_ask.get("si", 0)) == 1 and mrp_again.is_empty(), "a map asks for its surface's roboports (mrp), not again for 10 s: %s" % [mrp_ask])
	var mq := int(mrp_ask.get("q", 0))
	m.handle({"t": "mrp", "si": 1, "q": mq, "part": 1, "last": 0, "l": [1000 * 256, 1000 * 256, 25 * 256, 55 * 256]})
	check(m.roboports_of(1).is_empty(), "a list in parts counts once its last part is in")
	m.handle({"t": "mrp", "si": 1, "q": mq, "part": 2, "last": 1, "l": [3072, 3072, 25 * 256, 55 * 256]})
	check(m.roboports_of(1).size() == 8 and m.roboport_covers(1, Vector2i(31, 31)) and m.roboport_covers(1, Vector2i(30, 32))
		and not m.roboport_covers(1, Vector2i(34, 31)) and not m.roboport_covers(3, Vector2i(31, 31)),
		"the roboports arrive, and the chunks whose middle a construction area holds count as seen")
	m.handle({"t": "mtr", "si": 1, "part": 1, "parts": 1, "l": [], "cov": []})
	check(m.map_coverage_known and m.chunk_covered(Vector2i(31, 31), Vector2(-5000, 0)) and not m.chunk_covered(Vector2i(40, 40), Vector2(-5000, 0)),
		"the map dims what no radar sees but not a roboport's construction area (H13)")
	view.centre = Vector2(1000, 1000)
	view.zoom = 1.0
	view.layers.redraw(view.centre, view.scale_now())
	var far_squares: Array = view.layers.roboport_squares("construction")
	check(far_squares.size() == 1 and is_equal_approx(far_squares[0].size.x, 110.0 * view.scale_now()),
		"the map view draws a roboport far from every chart loaded: %s" % [far_squares])
	view.centre = Vector2(12, 12)
	view.layers.redraw(view.centre, view.scale_now())
	check(view.layers.roboport_squares("logistic").size() == 1, "one in a chart's rows and the list is drawn once")
	m.handle({"t": "mrp", "si": 1, "q": mq, "part": 1, "last": 1, "l": []})
	check(view.layers.roboport_squares("logistic").size() == 1 and not m.roboport_covers(1, Vector2i(31, 31)),
		"the list empties; a roboport the charts show is still drawn from them")
	view.centre = Vector2.ZERO
	view.zoom = 4.0
	var plain: Array = view._plain_name("[item=space-science-pack] run [planet=vulcanus]")
	check(not str(plain[0]).contains("[") and str(plain[0]).contains("run") and plain[1] == "space-science-pack",
		"a platform's rich-text name shows as words, its first item as the icon: %s" % [plain])
	sent()
	vulcanus.pressed.emit()
	await get_tree().process_frame
	var lpad_ask := {}
	for msg in sent():
		if msg.get("t", "") == "lpad":
			lpad_ask = msg
	check(int(lpad_ask.get("si", 0)) == 3 and view.centre == Vector2.ZERO, "switching to a planet asks where its landing pad is (H23): %s" % [lpad_ask])
	m.handle({"t": "lpad", "si": 3, "q": int(lpad_ask.get("q", 0)), "x": 40 * 256, "y": -30 * 256})
	check(view.centre == Vector2(40, -30), "and the map centres on it: %s" % [view.centre])
	view.show_surface(3)
	lpad_ask = sent_one("lpad")
	view.zoom_by(1.0 / view.ZOOM_STEP, Vector2(10, 10))
	var moved: Vector2 = view.centre
	m.handle({"t": "lpad", "si": 3, "q": int(lpad_ask.get("q", 0)), "x": 400 * 256, "y": 0})
	check(view.centre == moved, "an answer after the view was moved leaves it where it is")
	view.zoom = 4.0
	cache._last_send = -1e9
	cache.want(Rect2i(-2, -2, 4, 4), 4, 60.0)
	var vreq := sent_one("map")
	check(m.map_si == 3 and int(vreq.get("si", 0)) == 3 and not cache.is_charted(Vector2i(1, -2)), "switching asks for that surface's map")
	m.handle({"t": "chart", "cx": 0, "cy": 0, "n": 1, "pal": [[200, 80, 20]], "px": [0], "si": 3})
	m.handle({"t": "chart", "cx": 7, "cy": 7, "n": 1, "pal": [[1, 2, 3]], "px": [0], "si": 1})
	m.handle({"t": "tags", "l": [[9, 0, 0, "Lava", "", ""]], "si": 3})
	check(cache.is_charted(Vector2i(0, 0)) and not cache.is_charted(Vector2i(7, 7)) and m.map_tags.size() == 1,
		"charts and tags of the shown surface are kept, a late chart of the other is dropped")
	view.edit_tag_at(view.tiles_to_screen(Vector2(30, 30)))
	view.dialog.text_field.text = "Here"
	view.dialog._confirm()
	check(int(sent_one("tag_add").get("si", 0)) == 3, "a tag goes on the shown surface")
	# Factorio's Remote view frame: title bar and Surfaces; no Add tag / Add ping panel (on purpose).
	await get_tree().process_frame
	var frame = ui.remote_frame
	check(frame.visible and frame.mode == "map" and view.surfaces_panel.get_parent() == frame and _texts(frame).has("Remote view")
		and _texts(frame).has("Surfaces") and frame.find_child("SpaceMap", true, false) != null and frame.find_child("AddPlatform", true, false) != null,
		"the map is framed as Factorio's Remote view: title bar, Surfaces (Space map, Planets, Platforms, + Add space platform)")
	check(frame.find_child("AddTag", true, false) == null and frame.find_child("AddPing", true, false) == null
		and frame.find_child("Quick_coal", true, false) == null and not _texts(frame).has("Add tag"),
		"no Add tag / Add ping panel or quick tag icons on the map")
	check(view.panel.visible and ui.minimap.visible and view.panel.get_global_rect().position.y >= ui.minimap.get_global_rect().end.y,
		"the map view settings go under the minimap, which the map view keeps (H22)")
	sent()
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	right.position = view.tiles_to_screen(Vector2(3, 3))
	view._gui_input(right)
	right = right.duplicate()
	right.pressed = false
	view._gui_input(right)
	var ask := sent_one("unghost")
	check(not view.dialog.is_open() and ask.get("x") == 3 * 256 and ask.get("y") == 3 * 256,
		"a right-click on the map first asks the mod to remove a ghost there: %s" % [ask])
	m.handle({"t": "unghost", "q": int(ask.get("q", 0)), "n": 1})
	check(not view.dialog.is_open(), "a ghost was removed: no tag dialog")
	right = right.duplicate()
	right.pressed = true
	view._gui_input(right)
	ask = sent_one("unghost")
	m.handle({"t": "unghost", "q": int(ask.get("q", 0)), "n": 0})
	check(view.dialog.is_open(), "no ghost there: the right-click opens the tag dialog, as before")
	view.dialog.close()
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(m.map_si == 0 and cache.is_charted(Vector2i(1, -2)) and cache._stash.has(3),
		"closing the map goes back to the character's surface and its charts")
	key(KEY_M)
	await get_tree().process_frame
	key(KEY_ESCAPE)
	await get_tree().process_frame
	settings.set_value("map/minimap_tags", false)
	check(not bool(Settings.get_value("map", "minimap_tags")), "tags on the minimap can be switched off")
	settings.set_value("map/minimap_tags", true)

	# The older ui.cfg and audio.cfg are read into the one file, once.
	var legacy_ui := ConfigFile.new()
	legacy_ui.set_value("map", "minimap_size", 300)
	legacy_ui.set_value("map", "minimap", false)
	legacy_ui.save("user://ui-test-legacy-ui.cfg")
	var legacy_audio := ConfigFile.new()
	legacy_audio.set_value("audio", "music", 0.4)
	legacy_audio.set_value("effects", "enabled", false)
	legacy_audio.save("user://ui-test-legacy-audio.cfg")
	Settings.legacy = {"user://ui-test-legacy-ui.cfg": {"map": "map"}, "user://ui-test-legacy-audio.cfg": {"audio": "sound"}}
	DirAccess.remove_absolute("user://ui-test-migrated.cfg")
	Settings.use_file("user://ui-test-migrated.cfg")
	check(Settings.get_value("map", "minimap_size") == 300 and Settings.get_value("map", "minimap") == false
		and is_equal_approx(float(Settings.get_value("sound", "music")), 0.4) and Settings.get_value("graphics", "effects") == false,
		"ui.cfg and audio.cfg values are migrated into settings.cfg")
	Settings.set_value("map", "minimap_size", 200)
	Settings.use_file("user://ui-test-migrated.cfg")
	check(Settings.get_value("map", "minimap_size") == 200, "and only once")
	Settings.legacy = {}
	Settings.use_file(TEST_SETTINGS)

	# UI scale changes live: Ctrl+= / Ctrl+- step through Factorio's scales, Ctrl+0 is automatic.
	Settings.set_value("interface", "ui_scale", "1.5")
	check(is_equal_approx(Settings.wanted_ui_scale(), 1.5), "a chosen UI scale is the one wanted")
	Settings.step_ui_scale(1)
	check(Settings.get_value("interface", "ui_scale") == "1.75", "Ctrl+= steps up to the next scale")
	Settings.step_ui_scale(-2)
	check(Settings.get_value("interface", "ui_scale") == "1.25", "Ctrl+- steps down, as the dropdown stores it")
	Settings.set_value("interface", "ui_scale", "2.0")
	Settings.step_ui_scale(1)
	check(Settings.get_value("interface", "ui_scale") == "2.0", "and stops at 200%")
	check(InputMap.has_action("increase_ui_scale") and InputMap.has_action("reset_ui_scale"), "the UI scale keys are controls")
	Settings.set_value("interface", "ui_scale", "auto")
	for f in ["user://ui-test-legacy-ui.cfg", "user://ui-test-legacy-audio.cfg", "user://ui-test-migrated.cfg"]:
		DirAccess.remove_absolute(f)


## The Settings window's tabs, key bindings, the map generator and the mods list, with the server
## folders pointed at a test folder.
func _menus() -> void:
	var data := OS.get_user_data_dir().path_join("ui-test-server")
	DirAccess.make_dir_recursive_absolute(data.path_join("mods/factorio-3d-bridge"))
	DirAccess.make_dir_recursive_absolute(data.path_join("mods/some-mod"))
	_write(data.path_join("mods/factorio-3d-bridge/info.json"), JSON.stringify({"name": "factorio-3d-bridge", "version": "0.2.0", "title": "Zenith bridge"}))
	_write(data.path_join("mods/some-mod/info.json"), JSON.stringify({"name": "some-mod", "version": "1.0.0", "title": "Some mod"}))
	DirAccess.remove_absolute(data.path_join("mods/mod-list.json"))
	Settings.set_value("factorio", "server_data", data)

	var w: Node = SettingsWindow.new()
	add_child(w)
	await get_tree().process_frame
	var find := func(n: String) -> Node: return w.find_child(n, true, false)
	check(w.current_tab() == "Graphics" and find.call("graphics-effects") != null, "the settings window opens on Graphics")
	(find.call("graphics-effects") as CheckBox).button_pressed = false
	check(not FxSettings.effects_enabled, "Show smoke and particles turns the effects off")
	(find.call("graphics-effects") as CheckBox).button_pressed = true
	(find.call("graphics-brightness") as HSlider).value = 1.2
	check(is_equal_approx(float(Settings.get_value("graphics", "brightness")), 1.2), "brightness applies while dragged")
	var env := Environment.new()
	Settings.apply_environment(env)
	check(env.adjustment_enabled and is_equal_approx(env.adjustment_brightness, 1.2), "and adjusts the 3D environment")
	(find.call("graphics-brightness") as HSlider).value = 1.0
	var filter: Node = ColorFilter.new()
	add_child(filter)
	var filters := find.call("graphics-color_filter") as OptionButton
	filters.select(2)
	filters.item_selected.emit(2)
	check(Settings.get_value("graphics", "color_filter") == "deuteranopia" and filter.visible, "a colour filter covers the screen")
	filters.select(0)
	filters.item_selected.emit(0)
	check(not filter.visible, "and None takes it away")
	filter.queue_free()
	# Graphics presets: High is today's defaults; a preset sets its settings together and the
	# individual settings stay; changing one by hand shows Custom.
	for key in Settings.PRESETS["high"]:
		check(Settings.PRESETS["high"][key] == Settings.DEFAULTS["graphics"][key], "the High preset keeps the default %s" % key)
	for preset in Settings.PRESETS:
		check((Settings.PRESETS[preset] as Dictionary).keys() == (Settings.PRESETS["high"] as Dictionary).keys(), "the %s preset sets the same settings as High" % preset)
	var preset_box := find.call("graphics-preset") as OptionButton
	check(preset_box != null and str(preset_box.get_item_metadata(preset_box.selected)) == Settings.preset_now(), "the Graphics tab shows the preset in use")
	for i in preset_box.item_count:
		if preset_box.get_item_metadata(i) == "low":
			preset_box.select(i)
			preset_box.item_selected.emit(i)
	await get_tree().process_frame
	check(Settings.get_value("graphics", "shadows") == "low" and Settings.get_value("graphics", "ssao") == false
		and int(Settings.get_value("graphics", "view_radius")) == 5 and Settings.preset_now() == "low", "the Low preset sets shadows, SSAO and view distance together")
	check(str((find.call("graphics-shadows") as OptionButton).get_item_metadata((find.call("graphics-shadows") as OptionButton).selected)) == "low",
		"and the tab's controls show the new values")
	Settings.set_value("graphics", "view_radius", 6)
	preset_box = find.call("graphics-preset") as OptionButton
	check(Settings.preset_now() == "custom" and str(preset_box.get_item_metadata(preset_box.selected)) == "custom", "a setting changed by hand makes it Custom")
	Settings.apply_preset("high")
	check(Settings.preset_now() == "high" and Settings.get_value("graphics", "shadows") == "high" and int(Settings.get_value("graphics", "view_radius")) == 10,
		"High puts the defaults back")
	var project := ConfigFile.new()
	project.load("res://project.godot")
	check(int(project.get_value("rendering", "driver/threads/thread_model", 0)) == Settings.THREAD_SAFE
		and not bool(Settings.DEFAULTS["graphics"]["render_thread"])
		and str(project.get_value("application", "config/project_settings_override", "")) == Settings.ENGINE_OVERRIDES,
		"the renderer runs on the main thread by default (stable; Godot's separate thread is experimental), which the settings can override")
	var engine_before := FileAccess.get_file_as_string(Settings.ENGINE_OVERRIDES) if FileAccess.file_exists(Settings.ENGINE_OVERRIDES) else ""
	var render_thread := find.call("graphics-render_thread") as CheckBox
	# Off first: a test settings file kept from an earlier run may have it on already.
	render_thread.button_pressed = false
	render_thread.button_pressed = true
	var engine := ConfigFile.new()
	engine.load(Settings.ENGINE_OVERRIDES)
	check(int(engine.get_value("rendering", "driver/threads/thread_model", 0)) == Settings.THREAD_SEPARATE, "turning it on writes the separate render thread for the next start")
	render_thread.button_pressed = false
	engine.load(Settings.ENGINE_OVERRIDES)
	check(int(engine.get_value("rendering", "driver/threads/thread_model", 0)) == Settings.THREAD_SAFE, "and off, the main-thread renderer")
	if engine_before == "":
		DirAccess.remove_absolute(Settings.ENGINE_OVERRIDES)
	else:
		var restore := FileAccess.open(Settings.ENGINE_OVERRIDES, FileAccess.WRITE)
		restore.store_string(engine_before)
		restore.close()

	w.open_tab("Sound")
	await get_tree().process_frame
	(find.call("sound-walking") as HSlider).value = 0.5
	var bus := AudioServer.get_bus_index("Walking")
	check(bus >= 0 and absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.01 and AudioServer.get_bus_send(bus) == "Effects",
		"the walking slider sets its bus, part of the game effects")
	(find.call("sound-walking_on") as CheckBox).button_pressed = false
	check(AudioServer.is_bus_mute(bus) and Settings.get_value("sound", "walking_on") == false, "its box mutes it")
	(find.call("sound-walking_on") as CheckBox).button_pressed = true
	check(not AudioServer.is_bus_mute(bus), "and unmutes it")

	w.open_tab("Interface")
	await get_tree().process_frame
	var delay := find.call("interface-tooltip_delay") as HSlider
	delay.value = 1.25
	delay.drag_ended.emit(true)
	check(is_equal_approx(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec")), 1.25), "tooltip delay goes to Godot's tooltips")
	(find.call("map-show_robots") as CheckBox).button_pressed = false
	check(UiSettings.shared().get_value("map/show_robots") == false, "the map view switches are in Interface too")
	(find.call("map-show_robots") as CheckBox).button_pressed = true

	w.open_tab("Other")
	await get_tree().process_frame
	var autosave := find.call("factorio-autosave_interval") as OptionButton
	for i in autosave.item_count:
		if autosave.get_item_metadata(i) == 5:
			autosave.select(i)
			autosave.item_selected.emit(i)
	var launcher := ServerLauncher.new()
	launcher._data = data
	var server_settings = JSON.parse_string(FileAccess.get_file_as_string(launcher._server_settings({"name": "Test host", "port": 34999, "lan": true, "max_players": 4})))
	check(server_settings is Dictionary and int(server_settings["autosave_interval"]) == 5 and server_settings["name"] == "Test host"
		and server_settings["visibility"]["lan"] == true and int(server_settings["max_players"]) == 4, "autosave and host settings reach the server's settings file")
	launcher.free()

	w.open_tab("Mod settings")
	await get_tree().process_frame
	check(w.current_tab() == "Mod settings", "mod settings explain where to change them without a launched server")

	# Factorio's way in the game: one page at a time from the Settings list, titled "<Page> settings"
	var page: Node = SettingsWindow.new()
	page.page_mode = true
	page.start_tab = "Sound"
	add_child(page)
	await get_tree().process_frame
	var page_labels: Array = page.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	check(page.current_tab() == "Sound" and page_labels.has("Sound settings") and not page.find_child("TabGraphics", true, false).is_visible_in_tree(),
		"a settings page alone: its title, no tab row")
	var confirmed := [false]
	page.confirmed.connect(func() -> void: confirmed[0] = true)
	(page.find_child("Confirm", true, false) as Button).pressed.emit()
	check(confirmed[0], "Confirm closes the settings")
	page.queue_free()

	PlayerInput.define_actions()
	Settings.apply_bindings()
	w.open_tab("Controls")
	await get_tree().process_frame
	check(find.call("controls-rotate-1") != null and _texts(w).has("Basic interaction") and _texts(w).has("Movement"), "controls are grouped like Factorio's")
	(find.call("controls-rotate-1") as Button).pressed.emit()
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_H
	ev.keycode = KEY_H
	ev.shift_pressed = true
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame
	check(Settings.keys_for("rotate") == [KEY_R, KEY_H | KEY_MASK_SHIFT], "a key with Shift becomes the alternative binding")
	var shift_h := false
	for e in InputMap.action_get_events("rotate"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_H and (e as InputEventKey).shift_pressed:
			shift_h = true
	check(shift_h, "and is in the input map with its modifier")
	var plain_h := InputEventKey.new()
	plain_h.physical_keycode = KEY_H
	plain_h.pressed = true
	var with_shift := plain_h.duplicate()
	with_shift.shift_pressed = true
	check(not plain_h.is_action_pressed("rotate") and with_shift.is_action_pressed("rotate"), "Shift + H fires it, H alone doesn't")
	Settings.bind_slot("pick_up", 1, KEY_R)
	check(Settings.conflicts("pick_up", KEY_R).has("rotate"), "a key used twice is a conflict")
	w.open_tab("Controls")
	await get_tree().process_frame
	check((find.call("controls-pick_up-1") as Button).tooltip_text.contains("Rotate"), "and the binding says what else uses it")
	(find.call("ResetControls") as Button).pressed.emit()
	check(Settings.keys_for("rotate") == Settings.default_keys("rotate") and not Settings.has_value("controls", "rotate"), "reset puts the defaults back")
	w.queue_free()

	# The map generator. It starts from the last settings played (Settings [new_game]), which a
	# later step of this test stores in the test's settings file: clear them, or every other run
	# starts from that run's changes.
	Settings.set_value("new_game", "settings", null)
	Settings.set_value("new_game", "seed", null)
	var gen: Node = MapGeneratorWindow.new()
	add_child(gen)
	await get_tree().process_frame
	check(gen.settings["gen"]["autoplace_controls"].has("iron-ore") and gen.settings["gen"]["autoplace_controls"].has("tungsten_ore"), "the map generator has every resource, Space Age's too")
	var rich := gen.find_child("gen-autoplace_controls-iron-ore-richness", true, false) as HSlider
	rich.value = 8
	check(is_equal_approx(float(gen.settings["gen"]["autoplace_controls"]["iron-ore"]["richness"]), 2.0) and MapGen.changed_count(gen.settings) == 1, "a resource slider changes its richness")
	var preset := gen.find_child("Preset", true, false) as OptionButton
	for i in preset.item_count:
		if preset.get_item_metadata(i) == "rich-resources":
			preset.select(i)
			preset.item_selected.emit(i)
	check(gen.settings["preset"] == "rich-resources" and MapGen.changed_count(gen.settings) == 0, "a preset sets its values")
	gen.open_tab("Terrain")
	await get_tree().process_frame
	(gen.find_child("gen-autoplace_controls-water-frequency", true, false) as HSlider).value = 8
	check(is_equal_approx(float(gen.settings["gen"]["autoplace_controls"]["water"]["frequency"]), 0.5), "water scale 200% is frequency 0.5")
	gen.open_tab("Enemy")
	await get_tree().process_frame
	(gen.find_child("gen-peaceful_mode", true, false) as CheckBox).button_pressed = true
	(gen.find_child("map-enemy_expansion-max_expansion_cooldown", true, false) as SpinBox).value = 30
	check(gen.settings["gen"]["peaceful_mode"] == true and int(gen.settings["map"]["enemy_expansion"]["max_expansion_cooldown"]) == 30 * 3600, "peaceful mode and expansion cooldown in minutes")
	var played := []
	gen.play.connect(func(n: String, st: Dictionary, sd: String, _ex: String) -> void: played.append([n, st, sd]))
	(gen.find_child("Seed", true, false) as LineEdit).text = "123"
	(gen.find_child("Seed", true, false) as LineEdit).text_changed.emit("123")
	(gen.find_child("Play", true, false) as Button).pressed.emit()
	check(played.size() == 1 and played[0][2] == "123" and played[0][1]["gen"]["peaceful_mode"] == true, "Play hands the settings and seed on")
	check(Settings.has_value("new_game", "settings") and str(Settings.get_value("new_game", "seed")) == "123", "and they are remembered for next time")
	gen.queue_free()
	var again: Node = MapGeneratorWindow.new()
	add_child(again)
	await get_tree().process_frame
	check(again.settings["gen"]["peaceful_mode"] == true and again.seed_text == "123", "the next new game starts from them")
	again.queue_free()

	# The mods list writes mod-list.json, with the DLC's dependencies.
	var mods: Node = ModsWindow.new()
	add_child(mods)
	await get_tree().process_frame
	var names: Array = mods._mods.map(func(x: Dictionary) -> String: return x["name"])
	check(names.has("factorio-3d-bridge") and names.has("some-mod") and (mods.find_child("factorio-3d-bridge", true, false) as CheckBox).disabled, "the mods list shows the server's mods, the bridge always on")
	mods.set_enabled("some-mod", false)
	if names.has("space-age"):
		mods.set_enabled("quality", false)
		var states := ModsWindow._list_states()
		check(states.get("quality") == false and states.get("space-age") == false and states.get("some-mod") == false, "turning Quality off turns Space Age off too")
		mods.set_enabled("space-age", true)
		states = ModsWindow._list_states()
		check(states.get("quality") == true and states.get("elevated-rails") == true and states.get("space-age") == true, "and Space Age brings its DLC back")
		mods.set_enabled("space-age", false)
		check(not MapGen.controls_for(MapGen.enabled_mods()).any(func(c: Array) -> bool: return c[0] == "tungsten_ore"), "without Space Age the map generator leaves its planets out")
		mods.set_enabled("space-age", true)
	else:
		check(ModsWindow._list_states().get("some-mod") == false, "a mod can be turned off")
	mods.queue_free()
	Settings.reset_value("factorio", "server_data")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Plays the windows the way a player would.
func _play(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var m = ui.model
	sent()
	player.cursor_item = ""
	ui.close_all()

	# --- the cursor stack: pick up, put down, split, swap, put back --------------------------
	m.handle({"t": "slots", "l": {"main": [["transport-belt", 50], ["iron-plate", 100], 0, 0, 0, 0, 0, 0, 0, 0],
		"guns": [["pistol", 1], ["submachine-gun", 1], 0], "ammo": [["firearm-magazine", 10], 0, 0], "armor": [0]}})
	ui.toggle_inventory()
	click_main(ui, 1)
	await get_tree().process_frame
	check(player.cursor_item == "transport-belt" and ui.hand.get("index") == 1, "click picks the stack up")
	check(ui.hand_count() == 50 and ui.cursor.item == "transport-belt" and ui.cursor.count == 50, "the cursor shows the stack and its count")
	check(ui.window._grid.get_child(0).hand, "its slot shows Factorio's hand")
	click_main(ui, 5)
	var mv := sent_one("move")
	check(mv.get("from") == "main" and mv.get("fi") == 1 and mv.get("to") == "main" and mv.get("ti") == 5 and int(mv.get("n", -1)) == 0,
		"click on an empty slot moves the stack there")
	check(player.cursor_item == "" and ui.hand.is_empty(), "and empties the cursor")
	click_main(ui, 2, MOUSE_BUTTON_RIGHT)
	check(player.cursor_item == "iron-plate" and int(ui.hand.get("n", 0)) == 50 and ui.hand_count() == 50, "right click picks up half")
	await get_tree().process_frame
	var half_slot: Slot = ui.window._grid.get_child(1)
	check(not half_slot.hand and ui.window.hand_slot.is_empty(),
		"a split leaves no hand on its slot (2.1.23: hand_location nil), the rest shows as a stack")
	click_main(ui, 6)
	mv = sent_one("move")
	check(mv.get("fi") == 2 and mv.get("ti") == 6 and int(mv.get("n", 0)) == 50, "and puts down only that half")
	click_main(ui, 1)
	click_main(ui, 2)
	check(sent_one("move").is_empty(), "a stack onto another item: nothing moves (2.1.23 puts the held stack back in its hand slot)")
	check(player.cursor_item == "iron-plate" and ui.hand.get("index") == 2, "and picks up the clicked one, the hand on its slot")
	ui.hand = {}
	player.cursor_item = ""
	click_main(ui, 1)
	click_main(ui, 3, MOUSE_BUTTON_RIGHT)
	mv = sent_one("move")
	check(int(mv.get("n", 0)) == 1 and player.cursor_item == "transport-belt", "right click with a stack drops one and keeps holding")
	click_main(ui, 1)
	check(player.cursor_item == "" and sent_one("move").is_empty(), "click on its own slot puts it back")
	click_main(ui, 1)
	key(KEY_Q)  # player_input.gd's Q isn't here; holding nothing must drop the hand too
	player.cursor_item = ""
	await get_tree().process_frame
	check(ui.hand.is_empty(), "the hand is forgotten when the cursor is emptied elsewhere")
	click_main(ui, 1)
	m.handle({"t": "slots", "l": {"main": [0, ["iron-plate", 100], 0, 0, ["transport-belt", 30], 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	check(ui.hand.get("index") == 5 and ui.hand_count() == 30, "a used-up stack refills the cursor from another one")
	ui.hand = {}
	player.cursor_item = ""

	# --- a machine screen: moves by slot, Shift transfers, status, fluids --------------------
	var screen: MachineScreen = hud.screen
	screen.unit = 77
	screen.handle({"t": "gui", "u": 77, "p": 0, "kind": "container", "inv": {"chest": [["coal", 10]]},
		"slots": {"chest": [["coal", 10], 0, 0, 0]}, "status": "working"})
	await get_tree().process_frame
	check(screen.is_open() and ui.window.is_open(), "a chest's screen opens beside the inventory")
	screen.slot_clicked.emit("chest", 1, "coal", 10, MOUSE_BUTTON_LEFT, false, false)
	check(player.cursor_item == "coal" and ui.hand.get("role") == "chest" and not ui.can_build_from_hand(), "click picks up a chest stack")
	click_main(ui, 7)
	mv = sent_one("move")
	check(mv.get("from") == "chest" and mv.get("to") == "main" and mv.get("ti") == 7 and int(mv.get("u", 0)) == 77, "and moves it into the inventory slot")
	click_main(ui, 2, MOUSE_BUTTON_LEFT, true)
	var put := sent_one("xfer")
	check(put.get("from") == "main" and put.get("fi") == 2 and put.get("k") == "stack" and int(put.get("u", 0)) == 77,
		"Shift+click moves that inventory stack into the machine (xfer stack)")
	click_main(ui, 2, MOUSE_BUTTON_LEFT, false, true)
	check(sent_one("xfer").get("k") == "all", "Ctrl+click moves all of that item (xfer all)")
	click_main(ui, 4, MOUSE_BUTTON_LEFT, false, true)
	var everything := sent_one("xfer")
	check(everything.get("k") == "all" and everything.get("fi") == 4, "Ctrl+click on an empty slot moves everything")
	click_main(ui, 4, MOUSE_BUTTON_LEFT, true)
	check(sent_one("xfer").is_empty(), "Shift+click on an empty slot does nothing")
	# F6: a screen opened from the remote view out of reach (`far`): a module held and clicked into
	# a module slot is asked for (modreq with the slot), right click takes the request back, and the
	# requested module shows faintly in its slot (mrq).
	m.handle({"t": "iuse", "part": 1, "parts": 1, "l": [["speed-module", "m", "speed"]]})
	screen.handle({"t": "gui", "u": 77, "p": 0, "kind": "lab", "inv": {"input": [], "modules": []},
		"slots": {"input": [0, 0], "modules": [0, 0]}, "far": 1, "mrq": ["", "speed-module"]})
	await get_tree().process_frame
	ui.hand = {}
	player.cursor_item = "speed-module"
	sent()
	screen.slot_clicked.emit("modules", 1, "", 0, MOUSE_BUTTON_LEFT, false, false)
	var asked := sent_one("modreq")
	screen.slot_clicked.emit("modules", 2, "", 0, MOUSE_BUTTON_RIGHT, false, false)
	var unasked := sent_one("modreq")
	var faint := 0
	for n in screen.find_children("*", "", true, false):
		if n.get("filter_item") == "speed-module":
			faint += 1
	check(m.is_module("speed-module") and not m.is_module("coal") and asked.get("item") == "speed-module" and int(asked.get("s", 0)) == 1
		and not asked.has("q")
		and int(asked.get("u", 0)) == 77 and int(unasked.get("clr", 0)) == 1 and int(unasked.get("s", 0)) == 2 and faint == 1,
		"far screen: a held module asks for itself in a module slot, right click cancels, requests show (F6): %s %s %d" % [asked, unasked, faint])
	player.cursor_item = ""
	screen.handle({"t": "gui", "u": 77, "p": 0, "kind": "container", "inv": {"chest": [["coal", 10]]},
		"slots": {"chest": [["coal", 10], 0, 0, 0]}, "status": "working"})
	await get_tree().process_frame
	sent()
	screen.slot_clicked.emit("chest", 1, "coal", 10, MOUSE_BUTTON_LEFT, true, false)
	var take := sent_one("xfer")
	check(take.get("from") == "chest" and take.get("fi") == 1 and take.get("k") == "stack" and int(take.get("u", 0)) == 77,
		"Shift+click takes that machine stack")
	click_main(ui, 2)
	screen.slot_clicked.emit("chest", 3, "", 0, MOUSE_BUTTON_LEFT, false, false)
	mv = sent_one("move")
	check(mv.get("from") == "main" and mv.get("fi") == 2 and mv.get("to") == "chest" and mv.get("ti") == 3 and int(mv.get("u", 0)) == 77,
		"an inventory stack goes into a chosen chest slot")
	check(MachineScreen.status_text("no_ingredients") == "No ingredients" and MachineScreen.status_text("full_output") == "Output full",
		"status names read like Factorio's")
	check(MachineScreen.status_color("working") == "green" and MachineScreen.status_color("no_power") == "red"
		and MachineScreen.status_color("low_power") == "yellow", "status dots are green, red or yellow")
	screen.handle({"t": "gui", "u": 77, "p": 0, "kind": "furnace", "inv": {"input": [["iron-ore", 5]], "fuel": [["coal", 2]], "output": []},
		"slots": {"input": [["iron-ore", 5]], "fuel": [["coal", 2]], "output": [0]}, "status": "no_fuel", "pw": 400,
		"fb": [["water", 150, 200, 15]], "recipe": "iron-plate", "pr": 300})
	await get_tree().process_frame
	var texts := _texts(screen)
	check(texts.has("No fuel") and texts.has("30%") and not texts.has("Energy") and not texts.has("Fluids"),
		"a furnace shows its status and progress, and no energy or fluid rows (as in Factorio)")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not screen.is_open() and not ui.is_open() and sent_one("close").size() > 0, "Esc closes the machine and the window and tells the mod")
	check(player.cursor_item == "" or ui.hand.is_empty(), "a machine stack in the cursor is dropped when its screen closes")
	player.cursor_item = ""

	# --- production windows laid out as Factorio's (production_panels.gd) ----------------------
	var old_protos = screen.protos
	var pp := ProtoDB.new()
	pp.add_entities([[1, "assembling-machine-2", "assembling-machine", -1.5, -1.5, 1.5, 1.5, 1, 1, 1, 3, 3],
		[2, "pumpjack", "mining-drill", -1.5, -1.5, 1.5, 1.5, 1, 1, 1, 3, 3],
		[3, "nuclear-reactor", "reactor", -2.5, -2.5, 2.5, 2.5, 1, 1, 1, 5, 5],
		[4, "heat-exchanger", "boiler", -1.5, -1, 1.5, 1, 1, 1, 1, 3, 2],
		[5, "lab", "lab", -1.5, -1.5, 1.5, 1.5, 1, 1, 1, 3, 3],
		[6, "requester-chest", "logistic-container", -0.5, -0.5, 0.5, 0.5, 1, 1, 1, 1, 1],
		[7, "recycler", "furnace", -1, -2, 1, 2, 1, 1, 1, 2, 4]])
	screen.protos = pp
	screen.request(78, {"t": "open", "u": 78, "p": 1, "x": 0, "y": 0})
	sent()
	var asm_msg := {"t": "gui", "u": 78, "p": 1, "kind": "crafter", "recipe": "electronic-circuit", "pr": 870,
		"inv": {"input": [["iron-plate", 5]], "output": [["electronic-circuit", 24]], "modules": []},
		"slots": {"input": [["iron-plate", 5], 0], "output": [["electronic-circuit", 24]], "modules": [0, 0]},
		"rd": {"i": [["item", "iron-plate", 1], ["item", "copper-cable", 3]], "o": [["item", "electronic-circuit", 1]], "e": 0.5},
		"pb": 80, "bp": 400, "status": "item_ingredient_shortage", "rl": ["electronic-circuit", "iron-gear-wheel", "inserter"],
		"rg": [["intermediate-products", "c", "b x", "e"], ["intermediate-products", "c", "b x", "c"], ["logistics", "a", "c inserter", "b"]],
		"ql": ["normal", "uncommon"]}
	screen.handle(asm_msg)
	await get_tree().process_frame
	texts = _texts(screen)
	check(texts.has(Kit.recipe_name("electronic-circuit")) and texts.has("87%") and ui.window._char_frame.visible,
		"an assembler: the recipe row with its name, the progress bar's %, beside the inventory")
	var cable := _find_slot_tip(screen, Kit.pretty("copper-cable"))
	var circuit := _find_slot_tip(screen, Kit.pretty("electronic-circuit"))
	check(cable != null and cable.theme_type_variation == "FRedSlot" and cable.filter_item == "copper-cable",
		"a missing ingredient is a red slot with its ghost")
	check(circuit != null and circuit.theme_type_variation == "FYellowSlot", "a product waiting in the output is gold")
	check(MachineScreen.status_color("item_ingredient_shortage") == "red", "ingredient shortage has Factorio's red dot")
	var bonus_bars := screen.find_children("*", "ProgressBar", true, false).filter(func(b): return (b as ProgressBar).tooltip_text.begins_with("Productivity"))
	check(bonus_bars.size() == 1, "the purple productivity bar under the progress bar")
	var gear: Button = screen.find_child("ChangeRecipe", true, false)
	check(gear != null, "the gear button changes the recipe")
	if gear != null:
		gear.pressed.emit()
	await get_tree().process_frame
	check(screen.choosing_recipe() and not screen.shows_inventory() and screen.title_text() == "Select a recipe for assembling"
		and not ui.window._char_frame.visible, "the gear opens Factorio's recipe chooser as a window of its own")
	var tabs := screen.find_children("*", "Button", true, false).filter(func(b): return (b as Button).theme_type_variation == "FTab")
	check(tabs.size() == 2, "the chooser has a tab per item group")
	key(KEY_F, false, true)
	await get_tree().process_frame
	var chooser_search: LineEdit = screen.find_child("ChooserSearch", true, false)
	check(chooser_search != null and chooser_search.visible and chooser_search.has_focus(), "Ctrl+F focuses the chooser's search")
	if chooser_search != null:
		chooser_search.text = "inserter"
		chooser_search.text_changed.emit("inserter")
	await get_tree().process_frame
	check(_find_slot_tip(screen, Kit.recipe_name("inserter")) != null and _find_slot_tip(screen, Kit.recipe_name("electronic-circuit")) == null,
		"typing filters the recipes across every group")
	if chooser_search != null:
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		chooser_search.gui_input.emit(esc)
	await get_tree().process_frame
	check(chooser_search != null and chooser_search.text == "" and _find_slot_tip(screen, Kit.recipe_name("electronic-circuit")) != null,
		"Esc clears the search")
	if chooser_search != null:
		chooser_search.release_focus()
	var uncommon := screen.find_children("*", "Button", true, false).filter(func(b): return (b as Button).tooltip_text == Kit.pretty("uncommon").capitalize())
	if not uncommon.is_empty():
		(uncommon[0] as Button).pressed.emit()
	await get_tree().process_frame
	var gear_slot := _find_slot_tip(screen, Kit.recipe_name("iron-gear-wheel"))
	if gear_slot != null:
		gear_slot.clicked.emit(MOUSE_BUTTON_LEFT, false)
	var sr := sent_one("set_recipe")
	check(sr.get("recipe") == "iron-gear-wheel" and sr.get("q") == "uncommon" and not screen.choosing_recipe(),
		"picking a recipe sets it with the ingredient quality and goes back to the machine")
	asm_msg.erase("recipe")
	asm_msg.erase("rd")
	screen.handle(asm_msg)
	await get_tree().process_frame
	check(screen.choosing_recipe() and screen.title_text() == "Select a recipe for assembling",
		"an assembler without a recipe opens as the chooser, as in Factorio")

	screen.request(79, {"t": "open", "u": 79, "p": 2, "x": 0, "y": 0})
	screen.handle({"t": "gui", "u": 79, "p": 2, "kind": "other", "inv": {"modules": []}, "slots": {"modules": [0, 0]},
		"mp": 450, "mt": "crude-oil", "mr": 430, "pb": 300, "bp": 750, "status": "waiting_for_space_in_destination"})
	await get_tree().process_frame
	texts = _texts(screen)
	check(texts.has("45%") and texts.has("4.3/s") and texts.has("Target full"), "a pumpjack: mining %, its yield per second")
	screen.handle({"t": "gui", "u": 79, "p": 2, "kind": "other", "inv": {"modules": []}, "slots": {"modules": [0, 0]},
		"mp": 900, "mt": "crude-oil", "mr": 430, "pb": 300, "bp": 750, "status": "working"})
	check(_texts(screen).has("90%"), "the mining bar follows mp without a rebuild")

	screen.request(80, {"t": "open", "u": 80, "p": 3, "x": 0, "y": 0})
	screen.handle({"t": "gui", "u": 80, "p": 3, "kind": "other", "inv": {"fuel": [["uranium-fuel-cell", 1]], "burnt": []},
		"slots": {"fuel": [["uranium-fuel-cell", 1]], "burnt": [0]}, "bn": 400, "tc": 67215, "temp": 672, "tmax": 1000})
	await get_tree().process_frame
	check(_texts(screen).has("Temperature: 672.15 °C") and screen.find_child("BurnerBar", true, false) != null,
		"a reactor: the fuel row with its burner bar, the temperature bar")
	screen.request(81, {"t": "open", "u": 81, "p": 4, "x": 0, "y": 0})
	screen.handle({"t": "gui", "u": 81, "p": 4, "kind": "other", "inv": {}, "tc": 50010, "temp": 500, "tmax": 1000,
		"fb": [["water", 200, 200, 15]]})
	await get_tree().process_frame
	check(not screen.shows_inventory() and not ui.window._char_frame.visible and not _texts(screen).has("Fluids"),
		"a heat exchanger opens compact, without fluid rows")

	screen.request(82, {"t": "open", "u": 82, "p": 5, "x": 0, "y": 0})
	screen.handle({"t": "gui", "u": 82, "p": 5, "kind": "lab", "inv": {"input": [["automation-science-pack", 3]]},
		"slots": {"input": [["automation-science-pack", 3], 0]}, "li": ["automation-science-pack", "logistic-science-pack"]})
	await get_tree().process_frame
	var ghost_pack := screen.find_children("*", "Button", true, false).filter(func(b): return b.get("filter_item") == "logistic-science-pack")
	check(ghost_pack.size() == 1, "a lab's empty pack slot shows the pack's ghost")

	screen.request(83, {"t": "open", "u": 83, "p": 6, "x": 0, "y": 0})
	screen.handle({"t": "gui", "u": 83, "p": 6, "kind": "container", "inv": {"chest": [], "trash": []},
		"slots": {"chest": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], "trash": [0, 0]}, "bar": 12,
		"lg": {"mode": "requester", "requests": []},
		"lc": {"tu": 0, "rb": 0, "sec": [{"i": 1, "g": "", "on": 1, "m": 1, "man": 1, "f": [["iron-plate", "", 100, -1, "", -1]]}]},
		"lgs": ["Mall", "Science"]})
	await get_tree().process_frame
	var limit_x: Node = screen.find_child("LimitButton", true, false)
	check(limit_x != null and limit_x.get_parent() is GridContainer and limit_x.get_index() == 12,
		"the chest's red X sits in the grid, in the cell after the last slot")
	check(_texts(screen).has("Normal") and _texts(screen).has("Logistic requests") and _texts(screen).has("[No group assigned]")
		and _texts(screen).has("Trash slots"), "a requester chest: Normal, Logistic requests, its sections, trash slots")
	var trash_box := _find_checkbox(screen, "Trash unrequested")
	if trash_box != null:
		trash_box.button_pressed = true
	check(sent_one("set_chest_logistics").get("tu") == 1, "Trash unrequested sends set_chest_logistics")
	var buffers := _find_checkbox(screen, "Request from buffer chests")
	if buffers != null:
		buffers.button_pressed = true
	check(sent_one("set_chest_logistics").get("rb") == 1, "Request from buffer chests too")
	var pencil: Button = screen.find_child("GroupButton", true, false)
	if pencil != null:
		pencil.pressed.emit()
	var group_box: LineEdit = screen.find_child("GroupName", true, false)
	check(group_box != null and group_box.is_visible_in_tree(), "the section's pencil opens its group picker")
	if group_box != null:
		group_box.text = "Mall"
		group_box.text_submitted.emit("Mall")
	var sg := sent_one("set_section")
	check(sg.get("g") == "Mall" and sg.get("i") == 1, "a group name puts the section in that group")

	screen.request(84, {"t": "open", "u": 84, "p": 7, "x": 0, "y": 0})
	var outs: Array = []
	for i in 12:
		outs.append(0)
	outs[0] = ["iron-plate", 3]
	screen.handle({"t": "gui", "u": 84, "p": 7, "kind": "furnace", "inv": {"input": [], "output": [["iron-plate", 3]]},
		"slots": {"input": [0], "output": outs, "modules": [0, 0, 0, 0]}})
	await get_tree().process_frame
	var out_grid := screen.find_children("*", "GridContainer", true, false).filter(func(gr): return (gr as GridContainer).columns == 6)
	check(_texts(screen).has("No recipe set") and out_grid.size() == 1 and out_grid[0].get_child_count() == 12,
		"the recycler shows all 12 outputs, 6 x 2")
	screen.close_local()
	screen.protos = old_protos
	sent()

	# --- crafting: Factorio's clicks, the queue in the corner ---------------------------------
	m.set_recipe_details([{"name": "iron-gear-wheel", "group": "intermediate-products", "ingredients": [["iron-plate", 2]],
		"products": [["iron-gear-wheel", 1]], "energy": 0.5, "craftable": 50}], ["intermediate-products"])
	ui.toggle_inventory()
	await get_tree().process_frame
	var recipe_slot = _find_recipe_slot(ui, "iron-gear-wheel")
	check(recipe_slot != null, "the recipe is in the crafting grid")
	if recipe_slot != null:
		recipe_slot.clicked.emit(MOUSE_BUTTON_RIGHT, false)
		check(int(sent_one("craft").get("n", 0)) == 5, "right click crafts 5")
		recipe_slot.clicked.emit(MOUSE_BUTTON_LEFT, true)
		check(int(sent_one("craft").get("n", 0)) == 50, "Shift+click crafts as many as possible")
	m.handle({"t": "cq", "pr": 500, "l": [[1, "iron-gear-wheel", 3, 0], [2, "transport-belt", 2, 0]]})
	await get_tree().process_frame
	var q = ui.craft_queue
	check(q._slots.size() >= 2 and q._slots[0].visible and q._slots[1].visible and q._slots[0].count == 3, "the crafting queue shows each entry")
	check(is_equal_approx(q._slots[0].progress, 0.5) and q._slots[1].progress < 0.0, "the first has the progress pie")
	q._slots[1].clicked.emit(MOUSE_BUTTON_LEFT, false)
	var cancel := sent_one("cancel_craft")
	check(int(cancel.get("i", 0)) == 2 and int(cancel.get("n", 0)) == 1, "click cancels one")
	q._slots[0].clicked.emit(MOUSE_BUTTON_RIGHT, false)
	check(int(sent_one("cancel_craft").get("n", 0)) == 5, "right click cancels five")
	m.handle({"t": "cq", "pr": 0, "l": []})
	await get_tree().process_frame
	check(not q._slots[0].visible, "an empty queue shows nothing")
	ui.close_all()

	# --- weapons and health -------------------------------------------------------------------
	hud.set_guns(1, [["pistol", "firearm-magazine", 10], ["submachine-gun", "", 0], ["", "", 0]])
	m.other_slots.erase("guns")
	m.other_slots.erase("ammo")
	m.guns_changed.emit()
	var w = ui.weapons
	check(w._guns[0].item == "pistol" and w._guns[0].button_pressed and w._ammo[0].count == 10, "the weapon slots show the selected gun and its ammo")
	check(w._guns[1].item == "submachine-gun" and not w._guns[1].button_pressed and w._ammo[1].item == "", "and the others")
	w._guns[1].clicked.emit(MOUSE_BUTTON_LEFT, false)
	check(int(sent_one("gun").get("i", 0)) == 2, "clicking a gun uses it")
	hud.set_health(100, 250)
	check(hud.health_bar.visible and hud.health_bar.value == 100, "the health bar shows while hurt")
	hud.set_health(250, 250)
	check(not hud.health_bar.visible, "and hides at full health")
	hud.set_mining(40)
	check(hud.mining_bar.visible and hud.mining_bar.get_parent() == ui.quickbar, "mining progress sits over the quickbar")
	hud.set_mining(-1)

	# --- technologies (T) ---------------------------------------------------------------------
	m.handle({"t": "techs", "part": 1, "parts": 1, "l": [
		["automation", "a", [], [["automation-science-pack", 1]], 10, 10, 2, ""],
		["electronics", "b", ["automation"], [["automation-science-pack", 1]], 30, 15, 1, ""],
		["logistics-2", "c", ["electronics"], [["automation-science-pack", 1], ["logistic-science-pack", 1]], 200, 30, 0, ""]]})
	m.handle({"t": "rs", "cur": "", "pr": 0, "q": []})
	ui.research.selected = ""  # an earlier check selected "automation"
	key(KEY_T)
	await get_tree().process_frame
	await get_tree().process_frame
	var r = ui.research
	check(r.is_open() and ui.is_open(), "T opens the technology screen")
	check(r._slots.size() == 3 and r.selected == "electronics", "every technology is in the tree; an available one is selected")
	check(r._tree_slots["logistics-2"].position.y > r._tree_slots["electronics"].position.y and r._tree_slots["electronics"].position.y > r._tree_slots["automation"].position.y,
		"the tree: what it needs above the selected technology, what needs it below")
	check(r._list.get_child(0) == r._slots["electronics"] and r._list.get_child(2) == r._slots["automation"],
		"the list of technologies: available first, researched last")
	var start: Button = _find_button(r, "Start research")
	check(start != null and not start.disabled, "an available technology can be started")
	if start != null:
		start.pressed.emit()
		check(sent_one("research").get("name") == "electronics", "Start research sends it")
	m.handle({"t": "rs", "cur": "electronics", "pr": 400, "q": []})
	await get_tree().process_frame
	check(r._slots["electronics"].progress > 0.39 and r._slots["electronics"].queue_place == 1, "its slot shows the progress")
	var cancel_button: Button = _find_button(r, "Cancel research")
	check(cancel_button != null, "the research in progress can be cancelled")
	if cancel_button != null:
		cancel_button.pressed.emit()
		check(sent_one("research_cancel").get("name") == "electronics", "Cancel research sends it")
	r.select("logistics-2")
	await get_tree().process_frame
	start = _find_button(r, "Add to queue")
	check(start != null and start.disabled, "a technology that isn't available yet can't be queued")
	ui.toggle_inventory()
	check(not ui.is_open(), "E closes the technology screen")
	key(KEY_T)
	await get_tree().process_frame
	key(KEY_T)
	await get_tree().process_frame
	check(not r.is_open(), "T again closes it")

	# --- keys that mustn't reach buttons, and the mouse over windows --------------------------
	ui.toggle_inventory()
	click_main(ui, 2)
	await get_tree().process_frame
	check(get_viewport().gui_get_focus_owner() == null, "nothing in the UI takes keyboard focus (Space, Enter, Tab, arrows stay game keys)")
	ui.close_all()
	ui.hand = {}
	player.cursor_item = ""
	check(not ui.mouse_over_gui() or DisplayServer.get_name() != "headless", "no window under a headless mouse")

	# --- tooltips and scale --------------------------------------------------------------------
	var tip = Kit.tooltip("Iron plate", [["100", "iron-plate"], ["Red", "", Kit.RED_TEXT]])
	check(tip is Control and tip.get_child_count() == 3, "a Factorio tooltip has its title and lines")
	tip.free()
	check(Kit.scale_for(720) == 1.0 and Kit.scale_for(1080) == 1.0 and Kit.scale_for(1440) == 1.25 and Kit.scale_for(1659) == 1.5
		and Kit.scale_for(2160) == 2.0, "UI scale like Factorio's: 1280x720 and 1080p 100%, 2880x1659 150%")



## Blueprints and planners: Factorio's exchange strings, the library (B) with its books, search,
## moves and import, taking records into the cursor, the blueprint, book and planner windows and
## what they write back, the mod's undo entries, the selection highlight and quality cycling.
func _planners(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var m = ui.model
	var pl = ui.planners
	ui.close_all()
	player.cursor_item = ""
	ui.hand = {}
	sent()

	# --- exchange strings: one Factorio 2.1.23 wrote (export_stack), decoded and written again --------
	var decoded := BpString.decode(FACTORIO_STRING)
	check(BpString.kind(decoded) == "blueprint" and BpString.label(decoded) == "Belt to chest"
		and BpString.icons(decoded) == [["item", "transport-belt"], ["item", "iron-chest"]], "a string from Factorio decodes: label, icons")
	check(BpString.components(decoded) == [["transport-belt", 3, "entity"], ["stone-path", 2, "tile"], ["inserter", 1, "entity"],
		["iron-chest", 1, "entity"]], "its components, most first: %s" % [BpString.components(decoded)])
	var again := BpString.decode(BpString.encode(decoded))
	check(BpString._plain(again) == BpString._plain(decoded) and BpString.encode(decoded).begins_with("0e"), "and encodes back to the same record (zlib, base64, version 0)")
	check(BpString.decode("not a string").is_empty() and BpString.decode("0" + Marshalls.utf8_to_base64("x")).is_empty(), "anything else decodes to nothing")
	var trimmed := decoded.duplicate(true)
	BpString.remove_component(trimmed, "transport-belt", "entity")
	check(BpString.components(trimmed).size() == 3 and not BpString.components(trimmed).any(func(c): return c[0] == "transport-belt"),
		"taking a component out removes every one of it")

	# --- the library: add, books, move, search, keep in user:// -----------------------------------
	BpLibrary.save_path = "user://test-blueprint-library.json"
	DirAccess.remove_absolute(BpLibrary.save_path)
	pl.library.load_file()
	var lib = pl.library
	check(lib.records.is_empty(), "a fresh library is empty")
	check(pl.import_string(FACTORIO_STRING), "Import string adds a pasted Factorio string to My blueprints")
	lib.add([], m.planners.empty("blueprint_book"))
	lib.add([], BpString.empty("deconstruction_planner"))
	check(lib.records.size() == 3 and BpString.kind(lib.records[1]) == "blueprint_book", "new book and planner from the library's buttons")
	check(lib.into_book([], 0, 1) and lib.records.size() == 2 and lib.list_at([0]).size() == 1, "a blueprint dropped on a book goes in as a page")
	lib.add([0], decoded)
	check(lib.list_at([0]).size() == 2 and int(BpString.pages(lib.records[0])[1][0]) == 1, "pages are numbered in order")
	check(lib.search("chest").size() == 2 and lib.search("chest")[0][0] == [0, 0], "search finds labels inside books: %s" % [lib.search("chest").map(func(e): return e[0])])
	lib.move([], 1, 0)
	check(BpString.kind(lib.records[0]) == "deconstruction_planner", "drag moves a record")
	lib.out_of_book([1], 0)
	check(lib.records.size() == 3 and lib.list_at([1]).size() == 1, "a page dragged out of the book goes up a level")
	var reloaded := BpLibrary.new()
	check(reloaded.records.size() == 3 and BpString.label(reloaded.records[2]) == "Belt to chest", "the library is kept in user:// and read back")

	# --- the window (B): tabs, take into the cursor, open books, the game's tab ---------------------
	var ev := Controls.key_event(KEY_B)
	ev.pressed = true
	get_viewport().push_input(ev)
	await get_tree().process_frame
	check(pl.library_window.is_open() and ui.is_open(), "B opens the blueprint library")
	check(sent_one("bp_lib").size() > 0, "and asks the mod for the game's and the player's libraries")
	m.handle({"t": "bpl", "src": "game", "who": "", "l": [[1, "blueprint", "Smelter", [["item", "stone-furnace"]]]]})
	m.handle({"t": "bpl", "src": "player", "who": "owner", "l": [[1, "blueprint-book", "Trains", []], [2, "upgrade-planner", "", []]]})
	await get_tree().process_frame
	check(m.planners.game_library.size() == 1 and m.planners.player_name == "owner" and _find_button(pl.library_window, "owner's blueprints") != null,
		"a taken-over player's library gets its own tab")
	check(ui.window.side == pl.library_window and ui.window._char_caption.text == "Blueprint library",
		"the library is the right half of one window with the inventory, titled Blueprint library")
	var grid_slots: Array = pl.library_window.record_slots()
	check(grid_slots.size() == 3, "My blueprints lists its three records")
	check(_texts(pl.library_window).has("Belt to chest"), "the list view shows each record's name beside its picture")
	grid_slots[2].clicked.emit(MOUSE_BUTTON_LEFT, false)
	var written := sent_one("bp_set")
	check(written.get("i") == -1 and BpString.label(BpString.decode(str(written.get("s", "")))) == "Belt to chest",
		"clicking a record writes it into the mod's cursor stack (bp_set -1)")
	m.handle({"t": "bp_ok", "q": int(written.get("q", 0)), "i": -1, "item": "blueprint"})
	check(player.cursor_item == "blueprint" and player.cursor_slot == -1, "and holds it from there")
	player.cursor_item = ""
	grid_slots[1].clicked.emit(MOUSE_BUTTON_RIGHT, false)
	await get_tree().process_frame
	check(pl.library_window.path == [1] and pl.library_window.record_slots().size() == 1,
		"right click on a book opens it in place")
	pl.library_window._go_back()
	check(pl.library_window.path == [] and not pl.library_window._forward.disabled, "back returns from the book, forward is offered")
	pl.library_window._go_forward()
	check(pl.library_window.path == [1], "and forward goes into it again")
	pl.library_window._go_up()
	pl.library_window.view = "grid"
	pl.library_window.refresh()
	check(pl.library_window.record_slots().size() == 3 and pl.library_window.find_child("View_grid", true, false) != null,
		"the small icons view lists the same records")
	pl.library_window.view = "list"
	pl.library_window.show_tab("game")
	await get_tree().process_frame
	var game_slots: Array = pl.library_window.record_slots()
	game_slots[0].clicked.emit(MOUSE_BUTTON_LEFT, false)
	var rec := sent_one("bp_rec")
	check(rec.get("src") == "game" and rec.get("ix") == 1 and rec.get("to") == -1, "a game record goes straight into the cursor (bp_rec to -1)")
	pl.library_window.show_tab("mine")
	pl.library_window.open(false)
	check(ui.window.side == null and not ui.window.visible, "closing the library closes its window")

	# --- the mod's string in parts, and its answers ---------------------------------------------------
	var got := []
	var q: int = m.planners.export_stack(7, func(r, _t, info): got.append([r, info]))
	check(sent_one("bp_get").get("i") == 7, "bp_get asks for slot 7")
	m.handle({"t": "bp", "q": q, "part": 2, "parts": 2, "s": FACTORIO_STRING.substr(100), "item": "blueprint", "i": 7})
	check(got.is_empty(), "a string waits for all its parts")
	m.handle({"t": "bp", "q": q, "part": 1, "parts": 2, "s": FACTORIO_STRING.substr(0, 100), "item": "blueprint", "i": 7})
	check(got.size() == 1 and BpString.label(got[0][0]) == "Belt to chest" and m.planners.version == 562954249895938,
		"then decodes, and the game's version is kept for new records")
	var long_label := ""
	for i in 3000:  # digits that don't compress much
		long_label += str(hash(i))
	var big := decoded.duplicate(true)
	BpString.body(big)["label"] = long_label
	m.planners.write(0, big)
	var parts: Array = sent().filter(func(c): return c.get("t") == "bp_set")
	check(parts.size() >= 2 and parts.all(func(c): return c.has("d") and int(c["parts"]) == parts.size()), "a long string goes to the mod in parts")
	m.handle({"t": "quals", "l": [["normal", 0, 1], ["uncommon", 1, 1], ["rare", 2, 0]]})
	check(m.planners.unlocked_qualities() == ["normal", "uncommon"], "quals: the qualities the force has")
	m.handle({"t": "hist", "h": 12, "what": "blueprint"})
	check(player.remembered == [[12, "blueprint"]], "hist: the mod's undo entry goes on the player's undo list")

	# --- the blueprint window: from an inventory slot, edited, saved back ---------------------------------
	m.set_inventory_slots([["blueprint", 1], ["deconstruction-planner", 1], ["upgrade-planner", 1], ["blueprint-book", 1]], 80)
	ui.window.open_crafting(true)
	click_main(ui, 1, MOUSE_BUTTON_RIGHT)
	var get_cmd := sent_one("bp_get")
	check(get_cmd.get("i") == 1 and player.cursor_item == "", "right click on a blueprint in the inventory asks for it (no half stack picked up)")
	m.handle({"t": "bp", "q": int(get_cmd.get("q", 0)), "part": 1, "parts": 1, "s": FACTORIO_STRING, "item": "blueprint", "i": 1})
	await get_tree().process_frame
	var bw = pl.bp_window
	check(bw.is_open() and bw._title.text == "Blueprint item" and (bw._sub["caption"] as Label).text == "Belt to chest"
		and _texts(bw).has("Components ⓘ") and _texts(bw).has("Preview"),
		"its window (Blueprint item) opens with the name, components and preview")
	var comps: Array = bw.find_child("Components", true, false).get_children().filter(func(c): return c is Slot)
	check(comps.size() == 4 and comps[0].item == "transport-belt" and comps[0].count == 3, "the components show with their counts")
	comps[2].clicked.emit(MOUSE_BUTTON_LEFT, false)  # the inserter
	(bw._sub["pencil"] as Button).pressed.emit()
	check((bw._sub["edit"] as LineEdit).visible, "the pencil turns the name into a text box")
	(bw._sub["edit"] as LineEdit).text = "Edited"
	(bw._sub["edit"] as LineEdit).text_submitted.emit("Edited")
	check((bw._sub["caption"] as Label).text == "Edited", "Enter renames it")
	var belt_no := int(BpString._list(BpString.body(bw.record).get("entities"))[0].get("entity_number", 0))
	bw.preview_clicked(belt_no, MOUSE_BUTTON_RIGHT)
	check(bw.removed.has(belt_no) and BpString.components(bw.result())[0][1] == 2, "right click in the preview removes an entity")
	bw.preview_clicked(belt_no, MOUSE_BUTTON_LEFT)
	check(not bw.removed.has(belt_no), "left click restores it")
	(bw.find_child("SnapToGrid", true, false) as CheckBox).button_pressed = true
	(bw.find_child("SnapX", true, false) as LineEdit).text = "6"
	(bw.find_child("SnapX", true, false) as LineEdit).text_changed.emit("6")
	(bw.find_child("AbsoluteSnapping", true, false) as CheckBox).button_pressed = true
	await get_tree().process_frame
	(bw.find_child("Save", true, false) as Button).pressed.emit()
	var saved := sent_one("bp_set")
	var out := BpString.decode(str(saved.get("s", "")))
	var body: Dictionary = BpString._plain(BpString.body(out))
	check(saved.get("i") == 1 and BpString.label(out) == "Edited" and not BpString.components(out).any(func(c): return c[0] == "inserter")
		and body.get("snap-to-grid") == {"x": 6, "y": 1} and body.get("absolute-snapping") == true,
		"Save writes it back to its slot: label, a component taken out, snap to grid, absolute snapping: %s" % [body.keys()])
	check(not bw.is_open(), "and closes the window")

	# --- the book window: pages, the active one, reorder, open a page --------------------------------------
	var book: Dictionary = m.planners.empty("blueprint_book")
	var page_b := decoded.duplicate(true)
	BpString.body(page_b)["label"] = "Second"
	BpString.set_pages(book, [decoded, page_b])
	pl.edit(book, {"kind": "slot", "slot": 4})
	await get_tree().process_frame
	var bk = pl.book_window
	var pages: Array = _slots_named(bk, "Page")
	check(bk.is_open() and ui.window.side == bk and ui.window._char_caption.text == "Blueprint book" and pages.size() == 2 and pages[0].marked,
		"a book is the right half of one window with the inventory, its pages listed, the active one framed")
	check(_texts(bk).has("Second") and bk.find_child("AddPage", true, false) != null, "each page with its name, and an empty slot to add one")
	bk._page_dropped(1, bk._owner, 0)
	check(BpString.label(BpString.pages(bk.record)[0][1]) == "Second", "dragging a page reorders the book")
	pages = _slots_named(bk, "Page")
	pages[1].clicked.emit(MOUSE_BUTTON_RIGHT, false)
	check(bw.is_open() and bk.is_open() and str(bw.source.get("kind")) == "page" and (bw._sub["caption"] as Label).text == "Belt to chest",
		"right click opens a page in the blueprint window, over the book")
	bw._set_label("Page edited")
	(bw.find_child("Save", true, false) as Button).pressed.emit()
	check(not bw.is_open() and BpString.label(BpString.pages(bk.record)[1][1]) == "Page edited", "saving the page puts it back into the book")
	check(sent_one("bp_set").is_empty(), "the book isn't written while it is open")
	bk.view = "slots"
	bk._show()
	check(_slots_named(bk, "Page").size() == 2, "the large icons view shows the same pages")
	ui.close_all()
	check(sent_one("bp_set").get("i") == 4 and ui.window.side == null, "closing the book writes it to its slot, as Factorio keeps every change")
	# A click on a page takes it out of the book into the cursor; the active page stays the same page.
	var book2: Dictionary = m.planners.empty("blueprint_book")
	BpString.set_pages(book2, [decoded, page_b])
	BpString.body(book2)["active_index"] = 1
	pl.edit(book2, {"kind": "slot", "slot": 4})
	await get_tree().process_frame
	sent()
	_slots_named(bk, "Page")[0].clicked.emit(MOUSE_BUTTON_LEFT, false)
	var writes: Array = sent().filter(func(c): return c.get("t") == "bp_set")
	check(BpString.pages(bk.record).size() == 1 and BpString.label(BpString.pages(bk.record)[0][1]) == "Second"
		and int(BpString.body(bk.record)["active_index"]) == 0 and writes.any(func(c): return c.get("i") == 4)
		and writes.any(func(c): return c.get("i") == -1 and BpString.label(BpString.decode(str(c.get("s", "")))) == "Belt to chest"),
		"click on a page: the book loses it at once and the cursor gets it; the active page stays \"Second\"")
	# The book's upgrade button: an upgrade planner's mappings applied to every page.
	var planner := {"upgrade_planner": {"item": "upgrade-planner", "settings": {"mappers": [
		{"index": 0, "from": {"type": "entity", "name": "transport-belt"}, "to": {"type": "entity", "name": "fast-transport-belt"}}]}}}
	var changed: int = bk.apply_upgrade(planner)
	check(changed > 0 and BpString.components(BpString.pages(bk.record)[0][1]).any(func(c): return c[0] == "fast-transport-belt"),
		"the book's upgrade button maps every page's entities (%d)" % changed)
	ui.close_all()
	sent()
	# The blueprint window's header: Factorio's six buttons; select new contents, upgrade.
	pl.edit(decoded, {"kind": "slot", "slot": 1})
	await get_tree().process_frame
	check(bw.find_child("ReselectButton", true, false) != null and bw.find_child("UpgradeButton", true, false) != null
		and (bw.find_child("ParametriseButton", true, false) as Button).disabled and bw.find_child("DeleteButton", true, false) != null
		and _find_checkbox(bw, "Tiles") == null, "the blueprint window's header has Factorio's six buttons (parametrise can't be used), and no Include section")
	bw.apply_upgrade(planner)
	check(BpString.components(bw.result()).any(func(c): return c[0] == "fast-transport-belt"), "upgrade: the planner's mappings applied to the blueprint")
	(bw.find_child("ReselectButton", true, false) as Button).pressed.emit()
	check(not bw.is_open() and player.cursor_tool == "blueprint" and player.reselect_slot == 1, "select new contents: the blueprint tool, aimed at this blueprint")
	m.handle({"t": "bp_ok", "q": 0, "i": 1, "item": "blueprint", "new": 1})
	check(sent_one("bp_get").get("i") == 1, "and when the mod has filled it, its window opens again")
	player.cursor_tool = ""
	ui.close_all()
	# Import string and a new book are on the shortcut bar, as in Factorio (not in the library).
	check(ui.shortcuts._buttons.has("import") and ui.shortcuts._buttons.has("book") and pl.library_window.find_child("ImportString", true, false) == null,
		"Import string and New blueprint book are shortcut bar buttons; the library has no buttons of its own")
	sent()
	ui._on_shortcut("book")
	var nb := sent_one("bp_set")
	check(nb.get("i") == -1 and BpString.kind(BpString.decode(str(nb.get("s", "")))) == "blueprint_book", "the book shortcut puts a new book in the cursor")
	ui._on_shortcut("import")
	check(pl._string_box.visible and pl._string_mode == "import", "the import shortcut opens the string box")
	pl._string_text.text = FACTORIO_STRING
	pl._on_string_ok()
	var imp := sent_one("bp_set")
	check(imp.get("i") == -1 and BpString.label(BpString.decode(str(imp.get("s", "")))) == "Belt to chest", "Import puts the blueprint in the cursor, as Factorio does")

	# --- the deconstruction and upgrade planners ------------------------------------------------------------
	var pw = pl.planner_window
	pl.edit(BpString.empty("deconstruction_planner"), {"kind": "slot", "slot": 2})
	await get_tree().process_frame
	check(pw.is_open() and ui.window.side == pw and ui.window._char_caption.text == "Deconstruction planner"
		and pw._title.text == "Deconstruction planner" and pw.find_child("EntityFilters", true, false).get_child_count() == 30,
		"the deconstruction planner joins the inventory: its Entities tab has 30 filters")
	check(_texts(pw).has("Trees/rocks only") and _find_button(pw, "Whitelist") != null and _find_button(pw, "Tiles") != null,
		"Trees/rocks only, the Whitelist / Blacklist switch and the Tiles tab")
	pw.set_filter("entity_filters", 0, "wooden-chest")
	pw.set_filter("entity_filters", 3, "iron-chest")
	_find_button(pw, "Blacklist").pressed.emit()
	await get_tree().process_frame
	(pw.find_child("Tab_tiles", true, false) as Button).pressed.emit()
	check(pw.find_child("TileFilters", true, false) != null and pw.find_child("EntityFilters", true, false) == null, "the Tiles tab: tile filters")
	(pw.find_child("TileSelectionMode", true, false) as OptionButton).item_selected.emit(3)
	check(sent_one("bp_set").is_empty(), "nothing is written while the window is open")
	pw.close()
	var st: Dictionary = BpString._plain(BpString.body(BpString.decode(str(sent_one("bp_set").get("s", ""))))["settings"])
	check(st.get("entity_filters") == [{"name": "wooden-chest", "index": 0}, {"name": "iron-chest", "index": 3}]
		and st.get("entity_filter_mode") == 1 and st.get("tile_selection_mode") == 3,
		"closing it writes the filters (0-based, as 2.x writes them), blacklist and tile mode: %s" % [st])
	check(ui.window.side == null, "and takes it out of the window")
	pl.edit(BpString.empty("upgrade_planner"), {"kind": "slot", "slot": 3})
	await get_tree().process_frame
	check(pw._title.text == "Upgrade planner" and _texts(pw).count("From") == 4 and pw.find_child("Mapper15_from", true, false) != null
		and pw.find_child("Mapper16_from", true, false) == null, "an empty upgrade planner: four From / To pairs, four rows")
	pw.set_mapper(0, "from", "transport-belt")
	pw.set_mapper(0, "to", "fast-transport-belt")
	pw.set_mapper(15, "from", "inserter")
	check(pw.find_child("Mapper16_from", true, false) != null, "filling the last row adds the next")
	ui.close_all()
	st = BpString._plain(BpString.body(BpString.decode(str(sent_one("bp_set").get("s", ""))))["settings"])
	check((st.get("mappers") as Array).size() == 2 and st.get("mappers")[0] == {"index": 0, "from": {"type": "entity", "name": "transport-belt"}, "to": {"type": "entity", "name": "fast-transport-belt"}},
		"the mapper rules are written when it closes: %s" % [st.get("mappers")])

	# --- Alt+B's area: the new blueprint's window opens; the upgrade shortcut gives a new planner ------------
	m.handle({"t": "bp_ok", "q": 0, "i": 5, "item": "blueprint", "new": 1})
	check(sent_one("bp_get").get("i") == 5, "a blueprint made from an area opens its window (asks for it)")
	ui.close_all()
	m.set_inventory_slots([], 80)
	ui._on_shortcut("upgrade")
	var up := sent_one("bp_set")
	check(up.get("i") == -1 and BpString.kind(BpString.decode(str(up.get("s", "")))) == "upgrade_planner",
		"the upgrade planner shortcut without one gives a new one in the cursor")

	# --- player_input: which stack, undo entries, quality, the selection highlight, book pages ---------------
	var world := WorldMirror.new()
	world.protos.add_entities([
		[1, "wooden-chest", "container", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[2, "tree-01", "tree", -0.4, -0.4, 0.4, 0.4, 40, 110, 40, 1, 1],
		[3, "transport-belt", "transport-belt", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
	])
	world.chunks[Vector2i.ZERO] = ChunkView.new()
	world._add([70, 1, 2 * 256 + 128, 2 * 256 + 128, 0])
	world._add([0, 2, 3 * 256 + 128, 2 * 256 + 128, 0])
	world._add([71, 3, 4 * 256 + 128, 2 * 256 + 128, 0, {"d": 1}])
	var input := PlayerInput.new()
	input.world = world
	input.hud = hud
	input.hold("deconstruction-planner", -1)
	check(input.planner_slot() == -1 and sent_one("bp_get").get("i") == -1, "a planner held from the library is slot -1; its settings are fetched")
	var area := Rect2(1, 1, 5, 3)
	check(input.selected_by("decon", area, false).size() == 3, "a planner without filters takes everything in the box")
	pl.held_record = {"deconstruction_planner": {"settings": {"trees_and_rocks_only": true}}}
	check(input.selected_by("decon", area, false).map(func(e): return e.proto_id) == [2], "trees and rocks only: the tree")
	pl.held_record = {"deconstruction_planner": {"settings": {"entity_filters": [{"name": "wooden-chest", "index": 0}]}}}
	check(input.selected_by("decon", area, false).map(func(e): return e.proto_id) == [1], "a whitelist: the chest")
	check(input.selected_by("decon", area, true).map(func(e): return e.proto_id) == [3], "Shift (cancel): what is marked")
	pl.held_record = {"upgrade_planner": {"settings": {"mappers": [{"from": {"type": "entity", "name": "transport-belt"}, "index": 0}]}}}
	check(input.selected_by("upgrade", area, false).map(func(e): return e.proto_id) == [3], "an upgrade planner: what it maps")
	check(input.selected_by("blueprint", area, false).map(func(e): return e.proto_id).has(1)
		and not input.selected_by("blueprint", area, false).map(func(e): return e.proto_id).has(2), "a blueprint selection: buildings, not trees")
	input.hold("wooden-chest")
	input.cycle_quality(1)
	check(input.cursor_quality == "uncommon", "Ctrl+wheel: the next quality the force has")
	input.cycle_quality(1)
	check(input.cursor_quality == "uncommon", "and no further than it has")
	input.hold("transport-belt")
	check(input.cursor_quality == "normal", "another item starts at normal")
	input.remember_mod(40, "deconstruction")
	sent()
	input.undo()
	check(sent_one("undo").get("h") == 40, "Ctrl+Z on a mod entry sends undo with its id")
	input.redo()
	check(sent_one("redo").get("h") == 40, "Ctrl+Y redo")
	input._remember({"do": "build", "item": "wooden-chest", "x": 2.5, "y": 2.5, "d": 0})
	input.undo()
	check(sent_one("decon").get("nh") == 1, "undoing a build marks it with nh, so the mod doesn't remember the undo itself")
	input.hold("blueprint-book", -1)
	pl.held_record = book
	BpString.body(pl.held_record)["active_index"] = 0
	sent()
	input._cycle_book(1)
	check(sent_one("bp_page").get("a") == 2 and int(BpString.body(pl.held_record)["active_index"]) == 1, "Shift+wheel: the book's next page")
	input._cycle_book(1)
	check(sent_one("bp_page").get("a") == 1, "round to the first again")
	# Factorio's selection colours (item.lua's border_color): select, Shift, right-drag.
	check(PlayerInput.selection_color("decon", false) == Color8(255, 24, 24) and PlayerInput.selection_color("decon", true) == Color8(239, 153, 34)
		and PlayerInput.selection_color("upgrade", false) == Color8(71, 255, 73) and PlayerInput.selection_color("upgrade", false, true) == Color8(246, 255, 0)
		and PlayerInput.selection_color("blueprint", false) == Color8(57, 156, 251) and PlayerInput.selection_color("copy", false) == Color(1, 1, 1),
		"selection boxes in Factorio's colours: deconstruct red, cancel orange, upgrade green, downgrade yellow, blueprint blue, copy white")
	# The copied buildings follow the mouse where Factorio pastes them. A clipboard real
	# Factorio 2.1.23 sent (three chests and an assembler) and where its paste put them.
	world.protos.add_entities([[4, "assembling-machine-1", "assembling-machine", -1.5, -1.5, 1.5, 1.5, 150, 150, 150, 3, 3]])
	var clip := [{"p": 1, "at": Vector2(-3, -1), "d": 0}, {"p": 1, "at": Vector2(-2, -1), "d": 0},
		{"p": 1, "at": Vector2(-1, -1), "d": 0}, {"p": 4, "at": Vector2(2, 0), "d": 0}]
	for c in [[Vector2(20.3, 20.6), 0, [Vector2(17.5, 19.5), Vector2(22.5, 20.5)]], [Vector2(40.7, 20.2), 0, [Vector2(37.5, 19.5), Vector2(42.5, 20.5)]],
			[Vector2(60.2, 20.9), 4, [Vector2(61.5, 17.5), Vector2(60.5, 22.5)]]]:
		input.ground = c[0]
		input.build_dir = c[1]
		var centre := input._paste_centre(clip[0], c[1] / 4)
		var first: Vector2 = clip[0]["at"]
		var asm: Vector2 = clip[3]["at"]
		if c[1] == 4:
			first = Vector2(-first.y, first.x)
			asm = Vector2(-asm.y, asm.x)
		check((centre + first).is_equal_approx(c[2][0]) and (centre + asm).is_equal_approx(c[2][1]),
			"pasting at %s turned %d: the preview's chest and assembler where Factorio puts them: %s %s" % [c[0], c[1], centre + first, centre + asm])
	input.build_dir = 0
	input._box_edges()
	check(input._drag_box.mesh == null and input._drag_box.get_child_count() == 4, "the selection box is only its border (four edges), as Factorio draws it")
	# A held blueprint: placed as the button goes down, with Factorio's build modes, and again along a drag.
	input.hold("blueprint", 1)
	pl.held_slot = 1
	pl.held_record = decoded.duplicate(true)
	sent()
	input.place_blueprint(Vector2(10, 5), 1)
	var bpc := sent_one("blueprint")
	check(bpc.get("bm") == 1 and bpc.get("i") == 1 and bpc.get("x") == 2560 and not bpc.has("sf"), "Shift+click places it forced (bm 1)")
	input.place_blueprint(Vector2(10, 5), 2)
	check(sent_one("blueprint").get("sf") == 1, "Ctrl+Shift+click super-forced")
	var step: Vector2i = pl.held_step(world.protos, 0)
	check(step.x >= 1 and step.y >= 1, "the blueprint's drag step is its size: %s" % [step])
	input._lmb_down = true
	input.has_ground = true
	input._bp_mode = 0
	input._bp_axis = Vector2.ZERO
	input._bp_last = Vector2(10, 5)
	input.ground = Vector2(10 + step.x * 2.2, 5.2)
	input._update_blueprint_drag()
	var placed: Array = sent().filter(func(c): return c.get("t") == "blueprint")
	check(placed.size() == 2 and placed[0].get("x") == int((10 + step.x) * 256) and placed[1].get("x") == int((10 + step.x * 2) * 256)
		and placed[0].get("y") == 5 * 256 and placed[0].get("bm") == 0, "dragging places it again every step along the drag: %s" % [placed])
	input._lmb_down = false
	input._bp_last = Vector2.INF
	# The upgrade planner's right-drag downgrades.
	input.hold("upgrade-planner", 3)
	input._reverse_from = Vector2(1, 1)
	input.ground = Vector2(6, 4)
	input._use_planner(false, true)
	var down := sent_one("upgrade")
	check(down.get("down") == 1 and down.get("i") == 3 and down.get("x1") == 256 and down.get("cancel") == 0, "right-drag with an upgrade planner: downgrade (down 1)")
	input._reverse_from = Vector2.INF
	input.has_ground = false
	# The red delete button destroys an inventory planner (bp_del).
	pl.edit(BpString.empty("deconstruction_planner"), {"kind": "slot", "slot": 2})
	(pw.find_child("DeleteButton", true, false) as Button).pressed.emit()
	check(sent_one("bp_del").get("i") == 2 and not pw.is_open(), "the planner's delete button destroys it (bp_del) and closes the window")
	input.hold("")
	input.free()
	world.chunks[Vector2i.ZERO].free()
	world.free()
	ui.close_all()
	DirAccess.remove_absolute(BpLibrary.save_path)


## Factorio parity: the controls, windows and entity screens added for it.
func _parity(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var m = ui.model
	ui.close_all()
	player.cursor_item = ""
	ui.hand = {}
	sent()

	# --- controls: InputMap actions with modifiers, exact matching, rebinding ------------------
	var shift_r := Controls.key_event(KEY_R | KEY_MASK_SHIFT)
	shift_r.pressed = true
	var plain_r := Controls.key_event(KEY_R)
	plain_r.pressed = true
	check(Controls.pressed(shift_r, "reverse_rotate") and not Controls.pressed(shift_r, "rotate") and Controls.pressed(plain_r, "rotate"),
		"R and Shift+R are different controls")
	var ctrl_c := Controls.key_event(KEY_C | KEY_MASK_CTRL)
	ctrl_c.pressed = true
	check(Controls.pressed(ctrl_c, "copy") and not Controls.pressed(ctrl_c, "shoot_cursor"), "Ctrl+C copies, it doesn't shoot")
	check(OS.find_keycode_from_string(OS.get_keycode_string(KEY_V | KEY_MASK_CTRL)) == (KEY_V | KEY_MASK_CTRL), "a binding with modifiers survives being saved as text")
	check(ControlsInfo.name_of("drop_item") == "Drop item" and ControlsInfo.group_of("quickbar_page_3") == "Quickbar"
		and ControlsInfo.name_of("give_blueprint") == "Blueprint",
		"actions carry Factorio's names for the Controls tab")

	# --- quickbar pages (Shift+1-0, X) ------------------------------------------------------------
	var qb_swap: Array = []
	qb_swap.resize(100)
	qb_swap.fill("")
	qb_swap[12] = "iron-chest"
	qb_swap[21] = "wooden-chest"
	qb_swap[60] = "transport-belt"
	m.handle({"t": "qb", "p": 2, "sel": 0, "held": "", "l": qb_swap})
	sent()
	key(KEY_3, true)
	await get_tree().process_frame
	check(sent_one("qb_page").get("p") == 3 and m.quickbar_page == 3 and str(ui.quickbar._pages[1].text) == "3",
		"Shift+3 shows quickbar page 3")
	ui.quickbar.open_chooser(0, true)
	ui.quickbar.pick_page(7)
	player.cursor_item = "transport-belt"
	await get_tree().process_frame
	check(m.quickbar_upper_page() == 7 and m.quickbar_page == 3
		and str(ui.quickbar._pages[0].text) == "7" and str(ui.quickbar._pages[1].text) == "3"
		and ui.quickbar._upper[0].item == "transport-belt" and ui.quickbar._slots[1].item == "wooden-chest"
		and ui.quickbar._upper[0].button_pressed and not ui.quickbar._slots[0].button_pressed,
		"the two quickbar rows show pages 7 (upper) and 3 (lower)")
	ui.quickbar.open_chooser(1, true)
	check(ui.quickbar._pages[1].button_pressed and (ui.quickbar._chooser_pages[3] as Button).button_pressed
		and not (ui.quickbar._chooser_pages[7] as Button).button_pressed,
		"the open chooser highlights the row's page button")
	key(KEY_X)
	await get_tree().process_frame
	check(sent_one("qb_page").get("p") == 7 and m.quickbar_page == 7 and m.quickbar_upper_page() == 3
		and str(ui.quickbar._pages[0].text) == "3" and str(ui.quickbar._pages[1].text) == "7"
		and ui.quickbar._slots[0].item == "transport-belt" and ui.quickbar._upper[1].item == "wooden-chest"
		and ui.quickbar._slots[0].button_pressed and not ui.quickbar._upper[0].button_pressed,
		"X swaps the two active quickbar rows")
	check(ui.quickbar._pages[1].button_pressed and (ui.quickbar._chooser_pages[7] as Button).button_pressed
		and not (ui.quickbar._chooser_pages[3] as Button).button_pressed,
		"and the highlighted page button follows")
	ui.quickbar.open_chooser(0, true)
	check(ui.quickbar._pages[0].button_pressed and (ui.quickbar._chooser_pages[3] as Button).button_pressed,
		"upper row's chooser highlights its swapped page")
	key(KEY_X)
	await get_tree().process_frame
	check(sent_one("qb_page").get("p") == 3 and m.quickbar_page == 3 and m.quickbar_upper_page() == 7
		and str(ui.quickbar._pages[0].text) == "7" and str(ui.quickbar._pages[1].text) == "3"
		and (ui.quickbar._chooser_pages[7] as Button).button_pressed
		and not (ui.quickbar._chooser_pages[3] as Button).button_pressed,
		"X again swaps the two rows back and the chooser highlight follows")
	ui.quickbar.open_chooser(0, false)
	player.cursor_item = ""
	await get_tree().process_frame
	PlayerInput.define_actions()
	Settings.apply_bindings()
	Settings.bind_slot("rotate_quickbars", 0, KEY_Y)
	key(KEY_X)
	await get_tree().process_frame
	check(m.quickbar_page == 3 and m.quickbar_upper_page() == 7 and sent().is_empty(),
		"once rotate_quickbars is rebound, X no longer swaps")
	key(KEY_Y)
	await get_tree().process_frame
	check(sent_one("qb_page").get("p") == 7 and m.quickbar_page == 7 and m.quickbar_upper_page() == 3,
		"the rebound rotate_quickbars key swaps the two rows")
	Settings.bind("rotate_quickbars", [])
	check(Settings.keys_for("rotate_quickbars") == [KEY_X, 0], "rotate_quickbars binding restored to default")
	qb_swap[21] = ""
	qb_swap[60] = ""
	m.quickbar_upper = 0
	m.handle({"t": "qb", "p": 2, "sel": 0, "held": "", "l": qb_swap})
	sent()

	# --- statistics (P, K), chat (`, /), research progress, Alt-mode --------------------------
	key(KEY_P)
	await get_tree().process_frame
	var st := sent_one("stats")
	check(ui.stats.is_open() and st.get("kind") == "item" and st.get("prec") == 1, "P opens production statistics on 5s and asks for them")
	m.handle({"t": "stats", "kind": "item", "prec": 1, "l": [["iron-plate", 42.0, 11.5, 2520, 690]]})
	await get_tree().process_frame
	check(_texts(ui.stats).has("42/m") and _texts(ui.stats).has("11.5/m"), "the rows show the rates per minute: %s" % [_texts(ui.stats)])
	key(KEY_K)
	await get_tree().process_frame
	check(ui.stats.is_open() and ui.stats.kind == "kill" and sent_one("stats").get("kind") == "kill" and ui.stats._tabs.visible
		and (ui.stats._tabs.get_child(4) as Button).button_pressed, "K switches to the production window's Kills tab")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not ui.stats.is_open(), "Esc closes statistics")
	key(KEY_SLASH)
	await get_tree().process_frame
	check(ui.chat.is_open() and ui.typing(), "/ opens the console line, which takes the keys")
	ui.chat._submit("hello factory")
	check(sent_one("chat").get("text") == "hello factory", "Enter says it in the game's chat")
	check(not ui.chat.is_open(), "and closes the line")
	m.handle({"t": "chat", "from": "Player", "text": "hi 3D"})
	await get_tree().process_frame
	ui.chat._refresh()
	check(_texts(ui.chat).has("Player: hi 3D"), "the game's chat shows: %s" % [_texts(ui.chat)])
	m.handle({"t": "rs", "cur": "automation", "pr": 500, "q": []})
	check(ui.research_hud.visible and _texts(ui.research_hud).size() > 0, "the research in progress shows (top right, in the side menu)")
	ui.set_alt_mode(true)
	check(sent_one("alt").get("on") == 1 and ui.alt_overlay.on, "Alt-mode asks the mod for its icons")
	m.handle({"t": "ai", "l": [[123, "recipe", "iron-gear-wheel"]]})
	check(m.alt_icons.get(123) == ["recipe", "iron-gear-wheel"], "ai message")
	ui.set_alt_mode(false)
	check(sent_one("alt").get("on") == 0 and m.alt_icons.is_empty(), "Alt-mode off forgets them")
	m.handle({"t": "clip", "l": [[5, 256, -512, 4]]})
	check(m.clipboard.size() == 1 and m.clipboard[0]["at"] == Vector2(1, -2) and m.clipboard[0]["d"] == 4, "clip message")
	m.handle({"t": "eprops", "r": 1, "l": [[7, 5, 0, 0], [8, 0, 7.5, 2.5]]})
	check(m.eprops.get(7, {}).get("under") == 5.0 and m.eprops.get(8, {}).get("supply") == 2.5, "eprops message")

	# --- the shortcut bar ------------------------------------------------------------------------
	ui._on_shortcut("alt")
	check(ui.alt_mode and sent_one("alt").get("on") == 1, "the Alt-mode shortcut toggles it")
	ui._on_shortcut("alt")
	sent()

	# --- crafting search ---------------------------------------------------------------------------
	key(KEY_F, false, true)
	await get_tree().process_frame
	var crafting = ui.window._crafting
	check(ui.window.is_open() and crafting.search.visible and crafting.search.has_focus(), "Ctrl+F opens crafting and its search")
	crafting.search.text = "gear"
	crafting._fill_grid()
	var found_gear := _find_recipe_slot(ui, "iron-gear-wheel") != null
	crafting.search.text = "nothing like this"
	crafting._fill_grid()
	check(found_gear and _find_recipe_slot(ui, "iron-gear-wheel") == null, "search filters recipes by name")
	crafting.search.text = ""
	crafting.search.release_focus()
	crafting._fill_grid()
	ui.window.show_tab("Logistics")
	check(_texts(ui.window._logistics).size() >= 1, "the Logistics tab shows something (requests or a note)")
	ui.window.show_tab("Crafting")
	ui.close_all()

	# --- inventory slot filters (middle click) ------------------------------------------------------
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 10], 0, 0]}})
	sent()
	click_main(ui, 1, MOUSE_BUTTON_MIDDLE)
	var fl := sent_one("inv_filter")
	check(fl.get("i") == 1 and fl.get("item") == "iron-plate", "middle click filters a slot to its item")
	m.handle({"t": "slots", "l": {"main": [0, 0, 0]}, "fl": [[1, "iron-plate"]]})
	ui.toggle_inventory()
	await get_tree().process_frame
	check(m.main_filters.get(1) == "iron-plate" and ui.window._grid.get_child(0).filter_item == "iron-plate", "the filter shows in the empty slot")
	click_main(ui, 1, MOUSE_BUTTON_MIDDLE)
	check(sent_one("inv_filter").get("item") == "", "middle click on a filtered empty slot clears it")
	ui.close_all()

	# --- machine screens: inserter, splitter, chest bar, combinator, train stop -----------------
	var screen: MachineScreen = hud.screen
	var old_protos = screen.protos
	screen.protos = _logic_protos()
	screen.request(900, {"t": "open", "u": 900, "p": 1, "x": 0, "y": 0})
	sent()
	screen.handle({"t": "gui", "u": 900, "p": 1, "kind": "inserter", "inv": {}, "ins": {"n": 5, "f": ["", "", "", "", ""], "m": "whitelist", "use": 0, "st": 0, "max": 3}})
	await get_tree().process_frame
	var mode_switch = screen.find_child("FilterMode", true, false)
	check(mode_switch != null and mode_switch.left_label.text == "Whitelist", "an inserter shows Factorio's whitelist / blacklist switch")
	if mode_switch != null:
		mode_switch.pick("right")
	check(sent_one("set_inserter").get("m") == "blacklist", "switching to blacklist sends it")
	player.cursor_item = "iron-plate"
	var filter_slot := _find_slot_tip(screen, "Filter")
	if filter_slot != null:
		filter_slot.clicked.emit(MOUSE_BUTTON_LEFT, false)
	var si := sent_one("set_inserter")
	check(si.get("f", [])[0] == "iron-plate" and si.get("use") == 1, "a filter slot clicked with an item held sets that filter (and uses filters)")
	player.cursor_item = ""
	if filter_slot != null:
		filter_slot.clicked.emit(MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame
	check(ui.picker.is_open(), "with nothing held it opens Factorio's item chooser")
	ui.picker._callback.call("item", "copper-plate")
	ui.picker.close()
	check(sent_one("set_inserter").get("f", [])[0] == "copper-plate", "and the chosen item becomes the filter")
	screen.handle({"t": "gui", "u": 900, "p": 1, "kind": "splitter", "inv": {}, "spl": {"i": "none", "o": "none", "f": ""}})
	await get_tree().process_frame
	var input_pri := _find_checkbox(screen, "Input priority")
	if input_pri != null:
		input_pri.button_pressed = true
	check(sent_one("set_splitter").get("i") == "left", "a splitter's input priority: ticking it sends the switch's side")
	var out_sw = screen.find_child("Priority_o", true, false)
	check(out_sw != null and not out_sw.enabled, "the output side's switch is greyed until Output priority is ticked")
	screen.handle({"t": "gui", "u": 900, "p": 1, "kind": "container", "inv": {"chest": [["iron-plate", 5]]},
		"slots": {"chest": [["iron-plate", 5], 0, 0, 0, 0, 0, 0, 0]}, "bar": 8})
	await get_tree().process_frame
	var limit := _find_slot_tip(screen, "Limit")
	check(limit != null, "a chest with a bar shows the limit button")
	if limit != null:
		limit.clicked.emit(MOUSE_BUTTON_LEFT, false)
		await get_tree().process_frame
		screen._stack_slot("chest", 4, {}).clicked.emit(MOUSE_BUTTON_LEFT, false)
	check(sent_one("set_bar").get("n") == 3, "the X then slot 4 limits the chest to 3 slots")
	screen.handle({"t": "gui", "u": 900, "p": 1, "kind": "container", "inv": {"chest": []},
		"slots": {"chest": [0, 0, 0, 0, 0, 0, 0, 0]}, "bar": 3})
	await get_tree().process_frame
	check(screen._stack_slot("chest", 5, {}).blocked and not screen._stack_slot("chest", 2, {}).blocked, "slots past the bar are red")
	screen.handle({"t": "gui", "u": 900, "p": 1, "kind": "combinator", "inv": {}, "cb": {"enabled": true, "signals": [["item", "iron-plate", 10]]},
		"sig": {"r": [["item", "iron-plate", 10]], "g": [], "ri": 7}})
	await get_tree().process_frame
	check(_texts(screen).has("Connected to:") and _texts(screen).has("7"), "a combinator's strip says which network it is connected to")
	var out = screen.find_child("OutputSwitch", true, false)
	if out != null:
		out.pick("left")
	check(sent_one("set_cb").get("cb", {}).get("enabled") == false, "a constant combinator's Off/On switch")
	await _circuit_screens(screen, ui)
	screen.handle({"t": "gui", "u": 900, "p": 1, "kind": "stop", "inv": {}, "stop": {"name": "Iron", "limit": -1, "count": 1}})
	await get_tree().process_frame
	var lim := _find_checkbox(screen, "Enable train limit")
	if lim != null:
		lim.button_pressed = true
	check(sent_one("set_stop").get("limit") == 1, "a train stop's limit")
	screen.handle({"t": "gui", "u": 900, "p": 1, "kind": "stop", "inv": {}, "stop": {"name": "Iron", "limit": -1, "count": 1, "pri": 50,
		"train": 0, "cb": {"wired": 1, "en": 0, "send": 1, "read": 0, "stopped": 1, "limit": 0, "count": 0, "pri": 0,
		"stopped_sig": {"type": "virtual", "name": "signal-T"}}}})
	await get_tree().process_frame
	var dock = screen.circuit_dock
	var read := _find_checkbox(dock, "Read train contents")
	if read != null:
		read.button_pressed = true
	var stop_cmd := sent_one("set_stop")
	check(read != null and _find_checkbox(dock, "Send to train").button_pressed and stop_cmd.get("cb", {}).get("read") == 1,
		"a train stop's circuit settings: in the docked circuit window, they show and send cb")
	check(_find_slot_tip(dock, "Signal-T") != null or _find_slot_tip(dock, Kit.pretty("signal-T")) != null, "and the stopped train's signal")
	check(dock.is_open("circuit") and dock.circuit_button.visible and dock.circuit_button.button_pressed,
		"a wired stop opens its circuit window, its title bar button lit")
	dock.circuit_button.button_pressed = false
	check(not dock.is_open("circuit") and not dock.visible, "the title bar button closes it")
	dock.circuit_button.button_pressed = true
	screen.handle({"t": "gui", "u": 900, "p": 14, "kind": "train", "inv": {}, "tr": {"id": 1, "state": "wait_station", "manual": false,
		"station": "", "dest": "", "sched": {"current": 1, "records": [{"station": "Iron", "wait_conditions": [{"type": "time", "compare_type": "or", "ticks": 600}]}]}}})
	await get_tree().process_frame
	check(_texts(screen).has("Iron") and _find_button(screen, "Time passed") != null, "a train's schedule shows its stops and waits")
	var go := screen.find_child("Go1", true, false) as Button
	if go != null:
		go.pressed.emit()
	check(sent_one("train_go").get("i") == 1, "Go sends the train to that stop")
	# The full train window: every wait condition, interrupts, go to station, cargo, fuel, camera.
	screen.handle({"t": "gui", "u": 900, "p": 14, "kind": "train", "inv": {}, "tr": {"id": 1, "state": "on_the_path", "manual": 0,
		"station": "", "dest": "Iron", "speed": 200, "pos": [2560, 2560], "cargo": [["iron-plate", 400]], "fluids": [], "fuel": [["coal", 20]],
		"stops": ["Copper", "Iron"], "sched": {"current": 1, "group": "", "records": [{"station": "Iron", "wait_conditions": [
			{"type": "item_count", "compare_type": "and", "condition": {"first_signal": {"type": "item", "name": "iron-plate"}, "comparator": ">", "constant": 100}},
			{"type": "inactivity", "compare_type": "or", "ticks": 300}]}],
			"interrupts": [{"name": "Refuel", "conditions": [{"type": "fuel_item_count_any", "compare_type": "and"}],
				"targets": [{"station": "Copper", "wait_conditions": []}], "inside_interrupt": false}]}}})
	await get_tree().process_frame
	check(_find_button(screen, "Item count") != null and _find_button(screen, "Inactivity") != null and _find_button(screen, "OR") != null,
		"wait conditions show their type and the AND/OR button")
	check(_texts(screen).has("Refuel") and _find_button(screen, "Fuel count (any locomotive)") != null, "interrupts show with their conditions")
	check(screen.has_meta("train_camera") and (screen.get_meta("train_camera") as Camera3D).position.x == 10.0, "a camera above the train")
	var inactivity := _find_button(screen, "Inactivity") as OptionButton
	if inactivity != null:
		inactivity.item_selected.emit(0)
	var sched_cmd := sent_one("set_schedule")
	check(sched_cmd.get("records", [{}])[0].get("wait_conditions", [{}, {}])[1].get("type") == "time", "changing a condition's type sends the schedule")
	var add_station := screen.find_child("AddStation", true, false)
	if add_station != null:
		add_station.get_meta("pick").call(0, true)
	check(sent_one("train_temp").get("station") == "Copper", "Ctrl+click on a station in + Add station sends a temporary stop")
	if add_station != null:
		add_station.get_meta("pick").call(1, false)
	var added: Array = sent_one("set_schedule").get("records", [])
	check(added.size() == 2 and added[1].get("station") == "Iron", "a plain click adds the station to the schedule")
	var interrupt_field: LineEdit = null
	for e in screen.find_children("*", "LineEdit", true, false):
		if (e as LineEdit).placeholder_text == "Name":
			interrupt_field = e
	if interrupt_field != null:
		interrupt_field.text_submitted.emit("Depot")
	var ints: Array = sent_one("set_interrupts").get("interrupts", [])
	check(ints.size() == 2 and ints[1]["name"] == "Depot", "a new interrupt is added by name")
	m.request_trains_overview(true)
	await get_tree().process_frame
	check(sent_one("trains_list").get("t") == "trains_list" and ui.trains_window.is_open(), "All trains opens the trains overview")
	m.handle({"t": "trl", "part": 1, "parts": 1, "l": [[1, "wait_station", 0, "Iron", "", 3, 700, 2560, 2560, 1, 0, [["iron-plate", 400]], []],
		[2, "manual_control", 1, "", "", 2, 710, 0, 0, 1, 0, [], []]]})
	await get_tree().process_frame
	var row2: Node = ui.trains_window.find_child("Train2", true, false)
	check(ui.trains_window.find_child("Train1", true, false) != null and row2 != null and _texts(ui.trains_window).has("Waiting at Iron"),
		"the overview lists every train with its state")
	var view: Node = row2.find_child("View", true, false) if row2 != null else null
	check(view != null and view.unit == 710 and _find_button(row2, "Manual") == null and _find_button(row2, "Automatic") == null,
		"a card shows a live view of the train from above (its locomotive), and no automatic / manual switch (Factorio's has none)")
	# A train the client isn't drawing (far away) gets no 3D view, only the chart, asked for.
	var no_view: bool = view != null and view.find_children("*", "SubViewport", true, false).is_empty()
	if view != null:
		view._asked_at = -1e9
		view._ask_chart()
	check(no_view and ui.map_cache.spots.size() > 0, "a far train's card makes no 3D view; it asks for the chart around the train: %s" % [ui.map_cache.spots])
	ui.map_cache.spots.clear()
	if view != null:
		view._make_view()
	var vp: SubViewport = view.find_children("*", "SubViewport", true, false)[0] if view != null else null
	check(vp != null and vp.world_3d == ui.get_viewport().world_3d and vp.render_target_update_mode != SubViewport.UPDATE_ALWAYS,
		"near, the view shares the client's world and renders only now and then")
	var tw = ui.trains_window
	check(_texts(tw).has("Train overview") and (tw._tab_buttons["Trains"] as Button).text == "Trains  2"
		and not tw._banner.visible, "Factorio's Train overview: tabs with counts, a card per train")
	var by_stop: Button = tw.find_child("List_Iron", true, false)
	var found_stop := by_stop != null
	if found_stop:
		by_stop.pressed.emit()
	await get_tree().process_frame
	check(found_stop and tw.find_child("Train1", true, false) != null and tw.find_child("Train2", true, false) == null,
		"the list on the left filters the cards (trains for Iron)")
	tw.show_tab("Groups")
	await get_tree().process_frame
	check(tw.filter == "" and tw._banner.visible == false, "the Groups tab lists every train under All")
	tw.show_tab("Trains")
	var look_at := []
	var catch_look := func(at: Vector2) -> void: look_at.append(at)
	tw.show_at.connect(catch_look)
	var card_click := InputEventMouseButton.new()
	card_click.button_index = MOUSE_BUTTON_LEFT
	card_click.pressed = true
	(tw.find_child("Train1", true, false) as Control).gui_input.emit(card_click)
	tw.show_at.disconnect(catch_look)
	check(look_at == [Vector2(10, 10)], "clicking a train's card looks at it: %s" % [look_at])
	tw.open(true)
	m.handle({"t": "trl", "part": 1, "parts": 1, "l": []})
	await get_tree().process_frame
	check(tw._banner.visible, "no trains: Factorio's red \"No Trains found.\" banner")
	ui.trains_window.open(false)
	await _logic_windows(screen, ui)
	await _logic2_windows(screen, ui)
	screen.close()
	screen.protos = old_protos

	# --- splitting transfers with a machine open ------------------------------------------------
	screen.request(901, {"t": "open", "u": 901, "p": 1, "x": 0, "y": 0})
	screen.handle({"t": "gui", "u": 901, "p": 1, "kind": "container", "inv": {"chest": [["coal", 9]]}, "slots": {"chest": [["coal", 9], 0]}})
	await get_tree().process_frame
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 100], ["iron-plate", 50], 0]}})
	sent()
	click_main(ui, 1, MOUSE_BUTTON_RIGHT, true)
	check(sent_one("xfer").get("k") == "half", "Shift+right click puts half the stack in")
	click_main(ui, 1, MOUSE_BUTTON_RIGHT, false, true)
	check(sent_one("xfer").get("k") == "allhalf", "Ctrl+right click puts half of each stack of the item in")
	ui._on_machine_slot("chest", 1, "coal", 9, MOUSE_BUTTON_RIGHT, true, false)
	var half_take := sent_one("xfer")
	check(half_take.get("k") == "half" and half_take.get("from") == "chest", "Shift+right click on the machine takes half the stack")
	await _input_rules(hud, player, screen)
	screen.close()
	ui.close_all()


## Slot rules recorded from Factorio 2.1.23 itself (tools/ui_reference/f3d-ui-capture/rules.lua:
## cursor_transfer, cursor_split, stack_transfers, clear_cursor, pipette): merging what fits, a full
## stack left alone, one into the hand's own slot, dragging a stack across slots (left spreads it,
## right puts one in each), the middle click's item chooser, the pipette's biggest stack, Q
## putting a machine's stack into the inventory, and how the hand's slot is drawn.
func _input_rules(hud: Hud, player: Node, screen: MachineScreen) -> void:
	var ui = hud.ui
	var m = ui.model
	screen.close()
	ui.close_all()
	ui.hand = {}
	player.cursor_item = ""
	ui.toggle_inventory()
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 80], ["iron-plate", 50], 0, 0, 0, 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	sent()
	click_main(ui, 1)
	await get_tree().process_frame
	var whole: Slot = ui.window._grid.get_child(0)
	check(whole.hand and whole.hand_left == -1, "a stack picked up whole leaves Factorio's hand alone on its slot")
	click_main(ui, 2)
	var mv := sent_one("move")
	check(mv.get("fi") == 1 and mv.get("ti") == 2 and player.cursor_item == "iron-plate" and ui.hand.has("merge"),
		"a click onto the same item moves what fits and keeps holding until the mod answers")
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 30], ["iron-plate", 100], 0, 0, 0, 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	check(player.cursor_item == "iron-plate" and ui.hand.get("index") == 1 and ui.hand_count() == 30 and not ui.hand.has("merge"),
		"what didn't fit stays in the cursor (2.1.23: 80 onto 50 leaves 30 held)")
	click_main(ui, 3)
	sent()
	m.handle({"t": "slots", "l": {"main": [0, ["iron-plate", 100], ["iron-plate", 30], 0, 0, 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	check(player.cursor_item == "" and ui.hand.is_empty(), "a put-down that empties the hand's slot empties the cursor (no refill)")

	# right click on the hand's own slot puts one back
	click_main(ui, 3)
	click_main(ui, 3, MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	var own: Slot = ui.window._grid.get_child(2)
	check(sent_one("move").is_empty() and ui.hand_count() == 29 and own.hand_left == 1,
		"right click on the hand's slot puts one back there (2.1.23: 1 in the slot, 36 of 37 held)")
	click_main(ui, 3)
	check(ui.hand.is_empty(), "and a click there puts the rest back")

	# dragging: the right button puts one in each slot crossed
	click_main(ui, 3)
	click_main(ui, 5, MOUSE_BUTTON_RIGHT)
	ui._spread_to("main", 6, 0)
	ui._spread_to("main", 6, 0)
	ui._spread_to("main", 2, 0)
	var ones := sent().filter(func(c): return c.get("t") == "move" and int(c.get("n", 0)) == 1)
	check(ones.size() == 3 and ones[1].get("ti") == 6 and ones[2].get("ti") == 2,
		"right drag puts one in each slot crossed, once each, onto the same item too")
	ui._spread = {}
	ui.clear_cursor()
	# the left button spreads the stack evenly; what doesn't divide stays held
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 50], 0, 0, 0, 0, 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	sent()
	click_main(ui, 1)
	click_main(ui, 5)
	ui._spread_to("main", 6, 0)
	var moves := sent()
	check(moves.size() == 2 and moves[1].get("fi") == 5 and moves[1].get("ti") == 6 and int(moves[1].get("n")) == 25,
		"left drag over a second slot: half of the 50 goes on")
	ui._spread_to("main", 7, 0)
	moves = sent()
	var to7 := 0
	var back := 0
	for c in moves:
		if c.get("ti") == 7:
			to7 += int(c["n"])
		elif c.get("ti") == 1:
			back += int(c["n"])
	check(to7 == 16 and back == 2 and player.cursor_item == "iron-plate" and ui.hand.get("index") == 1,
		"a third slot: 16 each, the 2 left over back in the cursor")
	ui._spread = {}
	# the same through mouse motion over a slot with the button held
	ui.clear_cursor()
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 50], 0, 0, 0, 0, 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	sent()
	click_main(ui, 1)
	click_main(ui, 5)
	var target: Control = ui.window._grid.get_child(7)
	var motion := InputEventMouseMotion.new()
	motion.position = target.get_global_rect().get_center()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	ui._input(motion)
	moves = sent()
	check(moves.size() == 2 and moves[1].get("ti") == 8, "dragging over a slot with the left button held spreads onto it")
	motion.button_mask = 0
	ui._input(motion)
	check(ui._spread.is_empty(), "letting go ends the spreading")
	ui.clear_cursor()

	# middle click: an empty slot with nothing held asks which item to filter it to
	ui._on_character_slot("main", 9, MOUSE_BUTTON_MIDDLE, false, false)
	check(ui.picker.is_open(), "middle click on an empty slot opens the item chooser for its filter")
	ui.picker.close()

	# the pipette takes the biggest stack; Q puts a machine's stack into the inventory
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 5], ["transport-belt", 30], ["transport-belt", 100], 0, 0, 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	check(ui.pick_from_inventory("transport-belt") and ui.hand.get("index") == 3 and ui.hand_count() == 100,
		"pipette: the biggest stack of the item, with its hand (2.1.23 takes a full stack)")
	ui.clear_cursor()
	screen.unit = 78
	screen.handle({"t": "gui", "u": 78, "p": 0, "kind": "container", "inv": {"chest": [["coal", 10]]},
		"slots": {"chest": [["coal", 10], 0, 0, 0]}, "status": "working"})
	await get_tree().process_frame
	sent()
	screen.slot_clicked.emit("chest", 1, "coal", 10, MOUSE_BUTTON_LEFT, false, false)
	await get_tree().process_frame
	check(ui.window.hand_slot.is_empty() and screen.hand_slot.size() == 3, "a stack from a chest: the hand array carries the count")
	ui.clear_cursor()
	var back_in := sent_one("xfer")
	check(back_in.get("from") == "chest" and back_in.get("k") == "stack" and int(back_in.get("u", 0)) == 78 and player.cursor_item == "",
		"Q with a chest's stack puts it in the inventory (2.1.23's clear_cursor)")
	screen.close()
	ui.close_all()


## The character's gear: the armour's equipment grid in the character window (picking up, moving,
## putting from the inventory, Shift+click both ways), Alt+F / Alt+E and the shortcuts, the
## Character tab, the shield and energy bars, the damage flash and low-health tint, the respawn
## screen, the players window and the names over other players' characters.
func _gear(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var m = ui.model
	ui.close_all()
	player.cursor_item = ""
	ui.hand = {}
	m.handle({"t": "slots", "l": {"main": [["energy-shield-equipment", 2], 0, ["iron-plate", 10], 0], "armor": [["power-armor-mk2", 1]]}})
	m.handle({"t": "eq", "kind": "char", "u": 77, "w": 10, "h": 10, "sh": 30, "msh": 150, "bat": 5000000, "mbat": 100000000,
		"gen": 750000, "mv": 300, "inv": 0, "mvon": 1, "nv": 1, "rb": 1, "l": [
			["fission-reactor-equipment", 0, 0, 4, 4, "normal", 0, 0, 0, 0, 0],
			["energy-shield-mk2-equipment", 4, 0, 2, 2, "normal", 1000, 360000, 30, 150, 0],
			["exoskeleton-equipment", 6, 0, 2, 4, "normal", 400000, 400000, 0, 0, 0],
			["personal-roboport-equipment", 8, 0, 2, 2, "normal", 1, 35000000, 0, 0, 0]]})
	check(m.grid("char")["w"] == 10 and m.equipment_at("char", Vector2i(7, 3)).get("name") == "exoskeleton-equipment"
		and m.equipment_at("char", Vector2i(5, 5)).is_empty(), "eq message: the grid and what covers each cell")
	ui.toggle_inventory()
	await get_tree().process_frame
	check(not ui.window._armor_frame.visible, "the armour's grid stays shut with the inventory, as in Factorio")
	ui._on_character_slot("armor", 1, MOUSE_BUTTON_RIGHT, false, false)
	check(ui.window.armor_open, "right click on the armour opens its grid")
	await get_tree().process_frame
	check(ui.window._armor_frame.visible and ui.window.side == ui.window._armor_frame
		and ui.window.armor_grid.custom_minimum_size == Vector2(10, 10) * float(Kit.px(40)) and not ui.window._crafting_frame.visible,
		"the armour opens as its own window: the inventory and the whole 10x10 grid, no crafting")
	check(_texts(ui.window).has("Power armor MK2") or _texts(ui.window).has("Power armor mk2"), "titled with the armour's name")
	check(_texts(ui.window).has("Equipment grid") and _texts(ui.window).has("Equipment grid size:") and _texts(ui.window).has("10×10")
		and _texts(ui.window).has("Shield capacity:") and _texts(ui.window).has("150") and _texts(ui.window).has("100 MJ")
		and _texts(ui.window).has("• Max. robots:") and _texts(ui.window).has("10"),
		"with Factorio's summary under it: grid size, battery and shield capacity, the roboport's robots")
	sent()
	# Click a piece: it is picked up; click an empty cell: it moves there.
	ui._on_grid_clicked("char", Vector2i(7, 2), MOUSE_BUTTON_LEFT, false)
	check(player.cursor_item == "exoskeleton-equipment" and ui.hand.get("role") == "grid" and ui.hand.get("cell") == Vector2i(6, 0),
		"a click on a piece picks it up (by any of its cells)")
	ui._process(0.0)
	check(ui.window.armor_grid.grabbed == Vector2i(6, 0) and ui.window.armor_grid.held_size == Vector2i(2, 4),
		"the grid shows it grabbed, and where it would go")
	ui._on_grid_clicked("char", Vector2i(0, 5), MOUSE_BUTTON_LEFT, false)
	var mv := sent_one("eq_move")
	check(mv.get("x") == 6 and mv.get("y") == 0 and mv.get("tx") == 0 and mv.get("ty") == 5 and mv.get("kind") == "char"
		and player.cursor_item == "", "a click elsewhere in the grid moves it there (eq_move)")
	# Pick up, then click an empty inventory slot: back into the inventory there.
	ui._on_grid_clicked("char", Vector2i(8, 1), MOUSE_BUTTON_LEFT, false)
	click_main(ui, 2)
	var tk := sent_one("eq_take")
	check(tk.get("x") == 8 and tk.get("y") == 0 and tk.get("ti") == 2 and ui.hand.is_empty(), "and onto an empty inventory slot (eq_take into it)")
	# A stack of equipment from the inventory onto the grid.
	click_main(ui, 1)
	check(player.cursor_item == "energy-shield-equipment" and ui.hand.get("role") == "main", "equipment picked up in the inventory")
	ui._process(0.0)
	check(ui.window.armor_grid.held_item == "energy-shield-equipment", "the grid shows where the held equipment would go")
	ui._on_grid_clicked("char", Vector2i(4, 4), MOUSE_BUTTON_LEFT, false)
	var put := sent_one("eq_put")
	check(put.get("fi") == 1 and put.get("x") == 4 and put.get("y") == 4 and put.get("kind") == "char", "clicked into the grid at that cell (eq_put)")
	ui._drop_hand()
	# Shift+click both ways.
	click_main(ui, 1, MOUSE_BUTTON_LEFT, true)
	put = sent_one("eq_put")
	check(put.get("fi") == 1 and not put.has("x"), "Shift+click on equipment in the inventory puts it where it fits")
	click_main(ui, 3, MOUSE_BUTTON_LEFT, true)
	check(sent_one("eq_put").is_empty(), "but not iron plates")
	ui._on_grid_clicked("char", Vector2i(5, 1), MOUSE_BUTTON_LEFT, true)
	tk = sent_one("eq_take")
	check(tk.get("x") == 4 and tk.get("y") == 0 and not tk.has("ti"), "Shift+click on a piece takes it to the inventory")
	# Alt+F and Alt+E, and their shortcuts.
	for code in [KEY_F, KEY_E]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.alt_pressed = true
		ev.pressed = true
		get_viewport().push_input(ev)
		await get_tree().process_frame
	var toggles: Array = sent().filter(func(c): return c.get("t") == "eq_toggle")
	check(toggles.size() == 2 and toggles[0].get("what") == "roboport" and toggles[0].get("on") == 0
		and toggles[1].get("what") == "movement" and toggles[1].get("on") == 0, "Alt+F and Alt+E switch the roboport and exoskeletons off")
	ui._process(0.0)
	check(ui.shortcuts._buttons["roboport"].visible and ui.shortcuts._buttons["roboport"].button_pressed
		and ui.shortcuts._buttons["exoskeleton"].visible, "the shortcut bar has both switches while the armour has the equipment")
	ui._on_shortcut("exoskeleton")
	check(sent_one("eq_toggle").get("what") == "movement", "the exoskeleton shortcut switches it")
	var cb := _find_checkbox(ui.window, "Personal roboport")
	check(cb == null or not cb.is_visible_in_tree(), "the armour window has no switches (Factorio has them on the shortcut bar)")
	# The Character tab.
	m.handle({"t": "cinfo", "craft": 1000, "mine": 1500, "run": 1000, "speed": 195, "eqmv": 300, "reach": 100, "build": 100,
		"rreach": 27, "pick": 11, "loot": 20, "drop": 100, "invb": 10, "eqinv": 20, "trash": 10, "hp": 250, "hpb": 0, "robots": 4, "slots": 110})
	ui.window.show_tab("Character")
	var info: Array = _texts(ui.window)
	check(info.has("Mining speed") and info.has("150%  (+50%)") and info.has("2.7") and info.has("110  (+10 bonus, +20 armor)")
		and info.has("100%  (+30% equipment)"), "the Character tab: bonuses, distances, slots, the equipment's running bonus")
	ui.window.show_tab("Crafting")
	ui.close_all()
	m.handle({"t": "eq", "kind": "char", "u": 77, "w": 0, "h": 0, "l": []})
	ui._process(0.0)
	check(not ui.window._armor_frame.visible and not ui.shortcuts._buttons["roboport"].visible, "without a grid: no armour panel, no switches")
	# Shield, energy, damage.
	hud.set_health(250, 250)
	hud.set_shield(150, 150)
	check(not hud.shield_bar.visible, "a full shield isn't shown")
	hud.set_shield(90, 150)
	check(hud.shield_bar.visible and hud.shield_bar.value == 90 and hud.damage.flash > 0.9, "a hit on the shield shows it over the health bar, with a red flash")
	hud.damage.flash = 0.0
	m.handle({"t": "eq", "kind": "char", "u": 77, "w": 2, "h": 2, "sh": 0, "msh": 0, "bat": 10, "mbat": 100, "gen": 0, "mv": 0, "inv": 0,
		"mvon": 1, "nv": 0, "l": [["battery-equipment", 0, 0, 1, 2, "normal", 10, 100, 0, 0, 0]]})
	check(hud.energy_bar.visible and hud.energy_bar.value == 10, "batteries that aren't full show their charge")
	hud.set_health(200, 250)
	check(hud.damage.flash > 0.9 and hud.damage.low == 0.0 and hud.damage.visible, "losing health flashes the screen's edges")
	hud.set_health(25, 250)
	check(hud.damage.low > 0.5, "low health tints the screen red")
	hud.set_health(250, 250)
	hud.damage.flash = 0.0
	hud.damage._process(0.0)
	check(hud.damage.low == 0.0 and not hud.damage.visible, "healed: no tint")
	# The respawn screen.
	m.handle({"t": "dead", "left": 600, "x": 256, "y": 512})
	await get_tree().process_frame
	check(ui.death_screen.visible and _texts(ui.death_screen).has("You died. Bad luck. Respawn in 10 seconds.")
		and not ui.death_screen._button.visible and ui.death_screen.died_at == Vector2(1, 2), "dead: Factorio's respawn screen counts down")
	m.handle({"t": "dead", "left": 0})
	ui.death_screen._process(0.0)
	check(ui.death_screen._button.visible, "with nothing left to wait for, the Respawn button")
	ui.death_screen._button.pressed.emit()
	check(not sent_one("respawn").is_empty(), "which asks for the respawn")
	ui.death_screen.alive()
	check(not ui.death_screen.visible, "the new character's `me` closes it")
	# Players.
	m.handle({"t": "pl", "me": 1, "u": 77, "l": [[1, "engineer", 1, 0, 55, 255, 77, "nauvis", 1, 0, ""],
		[2, "friend", 1, 255, 120, 0, 900, "vulcanus", 0, 0, "[builder]"], [3, "gone", 0, 90, 90, 90, 0, "nauvis", 0, 0, ""]]})
	ui.players_window.toggle()
	await get_tree().process_frame
	var names: Array = _texts(ui.players_window)
	check(ui.players_window.visible and names.has("engineer  (you)") and names.has("friend [builder]") and names.has("Offline")
		and names.has("Player management") and names.has("2 online"), "the players window lists everyone, online first, with tags")
	check(m.player_of_unit(900).get("name") == "friend", "a player by their character")
	key(KEY_ESCAPE)
	await get_tree().process_frame
	check(not ui.players_window.visible, "Esc closes it")
	var movers := MoverLayer.new()
	var protos := ProtoDB.new()
	protos.add_entities([[3, "character", "character", -0.2, -0.2, 0.2, 0.2, 1, 1, 1, 1, 1]])
	movers.protos = protos
	add_child(movers)
	movers.handle({"t": "mv", "k": 1, "part": 1, "parts": 1, "l": [[900, 3, 2560, 2560], [77, 3, 0, 0]]})
	var tags := PlayerTags.new()
	tags.movers = movers
	tags.model = m
	add_child(tags)
	movers.puppet_unit = 77
	tags._process(0.0)
	var label: Label3D = tags.get_child(0) if tags.get_child_count() > 0 else null
	check(tags.count() == 1 and label != null and label.text == "friend [builder]" and label.position.y > 2.0,
		"another player's name floats over their character, not over our own")
	tags.queue_free()
	movers.queue_free()
	sent()
## Circuit settings (gui.cc), combinators in full and the entity settings of entity_settings.gd.
func _circuit_screens(screen: MachineScreen, ui) -> void:
	var gui := func(kind: String, extra: Dictionary) -> void:
		var msg := {"t": "gui", "u": 900, "p": 1, "kind": kind, "inv": {}}
		msg.merge(extra, true)
		screen.handle(msg)
	# Constant combinator sections.
	gui.call("combinator", {"cb": {"enabled": true, "signals": [["item", "iron-plate", 10]],
		"sections": [{"g": "", "on": 1, "m": 1, "s": [["item", "iron-plate", 10]]}]}})
	await get_tree().process_frame
	var add_section := _find_button(screen, "Add section")
	if add_section != null:
		add_section.pressed.emit()
	var cb: Dictionary = sent_one("set_cb").get("cb", {})
	check(cb.get("sections", []).size() == 2 and cb["sections"][1].get("on") == 1, "a constant combinator gets a second section")
	# A signal's value: Factorio's "Set request" popup (the chooser, the number, a slider, the tick).
	gui.call("combinator", {"cb": {"enabled": true, "signals": [["item", "iron-plate", 10]],
		"sections": [{"g": "", "on": 1, "m": 1, "s": [["item", "iron-plate", 10]]}]}})
	await get_tree().process_frame
	var sig_grid = screen.find_child("Signals", true, false)
	if sig_grid != null:
		(sig_grid.get_child(0) as Slot).clicked.emit(MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame
	var vbox := ui.picker.find_child("ConstantBox", true, false) as LineEdit
	var vtick := ui.picker.find_child("ValueOk", true, false) as Button
	check(ui.picker.is_open() and ui.picker._title.text == "Set request" and vbox != null and vbox.text == "10" and vtick != null and vtick.visible,
		"clicking a signal opens Set request with its value")
	if vbox != null:
		vbox.text = "25"
		vtick.pressed.emit()
	cb = sent_one("set_cb").get("cb", {})
	check(not ui.picker.is_open() and int(cb.get("sections", [{}])[0].get("s", [[0, 0, 0]])[0][2]) == 25, "the tick sets the signal's value")
	# Decider: conditions with and/or and networks, outputs.
	gui.call("combinator", {"cb": {"conditions": [{"first_signal": {"type": "item", "name": "iron-plate"}, "comparator": ">", "constant": 5}],
		"outputs": [{"signal": {"type": "virtual", "name": "signal-A"}, "copy_count_from_input": true}]}})
	await get_tree().process_frame
	var add_cond := _find_button(screen, "+ Add condition")
	if add_cond != null:
		add_cond.pressed.emit()
	cb = sent_one("set_cb").get("cb", {})
	check(cb.get("conditions", []).size() == 2 and cb["conditions"][1].get("compare_type") == "or", "a decider gets a second condition (or)")
	gui.call("combinator", {"cb": {"conditions": [{"first_signal": {"type": "item", "name": "iron-plate"}, "comparator": ">", "constant": 5},
		{"first_signal": {"type": "virtual", "name": "signal-B"}, "comparator": "<", "constant": 3, "compare_type": "or"}],
		"outputs": [{"signal": {"type": "virtual", "name": "signal-A"}, "copy_count_from_input": true}]}})
	await get_tree().process_frame
	var andor := screen.find_child("AndOr", true, false) as Button
	if andor != null:
		andor.pressed.emit()
	cb = sent_one("set_cb").get("cb", {})
	check(cb.get("conditions", [{}, {}])[1].get("compare_type") == "and", "and/or between conditions")
	var green := screen.find_child("NetG", true, false) as CheckBox
	if green != null:
		green.button_pressed = false
	cb = sent_one("set_cb").get("cb", {})
	check(cb.get("conditions", [{}])[0].get("first_signal_networks", {}) == {"red": true, "green": false}, "a condition's signal read from the red network only")
	var const_out := screen.find_child("OutConst", true, false) as CheckBox
	if const_out != null:
		const_out.button_pressed = true
	cb = sent_one("set_cb").get("cb", {})
	check(cb.get("outputs", [{}])[0].get("copy_count_from_input") == false, "an output switches from the input count to a constant")
	# Selector: every mode.
	gui.call("combinator", {"cb": {"operation": "select", "select_max": true, "index_constant": 0}})
	await get_tree().process_frame
	var mode := screen.find_child("SelectorMode", true, false) as OptionButton
	check(mode != null and mode.item_count == CircuitPanel.SELECTOR_MODES.size(), "the selector lists every mode")
	if mode != null:
		mode.item_selected.emit(6)
	check(sent_one("set_cb").get("cb", {}).get("operation") == "quality-transfer", "choosing a selector mode sends it")
	gui.call("combinator", {"cb": {"operation": "quality-transfer", "quality_destination_signal": {"type": "virtual", "name": "signal-each"}}})
	await get_tree().process_frame
	check(_find_button(screen, "Quality from a signal") != null and _texts(screen).has("Output signal"), "quality transfer shows its settings")
	# The circuit connection of an inserter, with its network id.
	gui.call("inserter", {"ins": {"n": 0, "f": [], "st": 0, "max": 3, "sp": "none"}, "cc": {"o": "inserter", "w": 1, "nets": {"r": 5, "g": 0},
		"f": {"circuit_enable_disable": 0, "circuit_condition": {"comparator": "<", "constant": 0}, "circuit_read_hand_contents": 1,
		"circuit_hand_read_mode": "pulse", "circuit_set_stack_size": 0, "circuit_stack_control_signal": {}, "connect_to_logistic_network": 0,
		"logistic_condition": {"comparator": "<", "constant": 0}}, "ln": 1}, "sig": {"r": [["item", "iron-plate", 4]], "g": [], "ri": 5}})
	await get_tree().process_frame
	var dock = screen.circuit_dock
	check(_texts(dock).has("Circuit connection") and _texts(dock).has("Red network 5") and _texts(dock).has("Logistic connection")
		and _texts(dock).has("Input") and _texts(dock).has("Output"),
		"an inserter's circuit and logistic connection are in the docked windows, Input and Output apart, with the network id")
	check(dock.logistic_button.visible and not dock.is_open("logistic"), "the logistic window opens from its own title bar button")
	var enable := _find_checkbox(dock, "Enable if")
	if enable != null:
		enable.button_pressed = true
	var en_f: Dictionary = sent_one("set_cc").get("f", {})
	check(en_f.size() == 1 and int(en_f.get("circuit_enable_disable", 0)) == 1, "Enable/disable sends set_cc")
	var hold := _find_button(dock, "Hold")
	if hold != null:
		hold.button_pressed = true
	check(sent_one("set_cc").get("f", {}).get("circuit_hand_read_mode") == "hold", "the hand read mode")
	var spoiled := _find_button(screen, "Spoiled first")
	check(spoiled != null and spoiled.disabled, "Spoiled first / Fresh first are greyed until Spoiled priority is ticked")
	var spoil := _find_checkbox(screen, "Spoiled priority")
	if spoil != null:
		spoil.button_pressed = true
	check(sent_one("set_inserter").get("sp") == "spoiled-first", "an inserter's spoil priority")
	# A lamp's colour.
	gui.call("other", {"p": 11, "ao": 0, "col": [255, 255, 255], "cc": {"o": "lamp", "w": 1, "nets": {"r": 0, "g": 2}, "f": {"circuit_enable_disable": 0,
		"circuit_condition": {"comparator": "<", "constant": 0}, "use_colors": 1, "color_mode": "components",
		"red_signal": {"type": "virtual", "name": "signal-red"}, "rgb_signal": {"type": "virtual", "name": "signal-white"}}}})
	await get_tree().process_frame
	check(_texts(dock).has("Red") and not _texts(dock).has("RGB"), "a lamp in components mode shows its red signal, not the packed one")
	var always := _find_checkbox(screen, "Always on")
	if always != null:
		always.button_pressed = true
	check(sent_one("set_lamp").get("ao") == 1, "a lamp's Always on")
	var picker := screen.find_child("ColorPicker", true, false) as ColorPickerButton
	if picker != null:
		picker.color = Color8(255, 0, 0)
		picker.popup_closed.emit()
	check(sent_one("set_color").get("c", []).map(func(v): return int(v)) == [255, 0, 0], "a lamp's colour")
	# Programmable speaker.
	gui.call("other", {"p": 12, "spk": {"vol": 0.5, "mode": "local", "poly": 0, "vctl": 0, "vsig": {}, "inst": 0, "note": 0, "pitch": 0, "stop": 0,
		"al": {"show": 0, "map": 0, "icon": {}, "msg": ""}, "il": [["alarms", ["alarm-1", "alarm-2"]], ["piano", ["C4", "D4", "E4"]]]}})
	await get_tree().process_frame
	var inst := screen.find_child("Instrument", true, false) as OptionButton
	if inst != null:
		inst.item_selected.emit(1)
	check(sent_one("set_speaker").get("inst") == 1, "a speaker's instrument")
	var show := _find_checkbox(screen, "Show alert")
	if show != null:
		show.button_pressed = true
	check(sent_one("set_speaker").get("al", {}).get("show") == 1, "a speaker's alert")
	var glob := _find_button(screen, "Universe")
	if glob != null:
		glob.button_pressed = true
	check(sent_one("set_speaker").get("mode") == "global", "a speaker's playback")
	# Pump filter and turret targets go through the chooser.
	gui.call("other", {"p": 13, "pf": "", "fb": [["water", 50, 100]]})
	await get_tree().process_frame
	var fluid_slot := _find_slot_tip(screen, "Fluid filter")
	if fluid_slot != null:
		fluid_slot.clicked.emit(MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame
	check(ui.picker.is_open() and ui.picker._kinds == ["fluid"], "a pump's filter opens the chooser for fluids")
	check(not _texts(screen).has("Fluids"), "a pump shows no fluid box rows, as in Factorio")
	ui.picker._callback.call("fluid", "water")
	ui.picker.close()
	check(sent_one("set_pump").get("f") == "water", "a pump's fluid filter")
	gui.call("turret", {"tgt": {"l": ["small-biter"], "ign": 0}})
	await get_tree().process_frame
	var add_target := _find_slot_tip(screen, "Add a priority target")
	if add_target != null:
		add_target.clicked.emit(MOUSE_BUTTON_LEFT, false)
	await get_tree().process_frame
	check(ui.picker.is_open() and ui.picker._kinds == ["entity"], "a turret's targets open the chooser for entities")
	ui.picker._callback.call("entity", "medium-biter")
	ui.picker.close()
	check(sent_one("set_targets").get("l") == ["small-biter", "medium-biter"], "a priority target is added")
	var ign := _find_checkbox(screen, "Ignore unlisted targets")
	if ign != null:
		ign.button_pressed = true
	check(sent_one("set_targets").get("ign") == 1, "ignore unprioritised targets")
	# Display panel messages.
	gui.call("panel", {"p": 18, "dp": {"text": "Hi", "icon": {}, "show": 0, "chart": 0, "msgs": []}, "sig": {"r": [], "g": [], "ri": 3}})
	await get_tree().process_frame
	var add_msg := _find_button(screen, "+ Add message")
	if add_msg != null:
		add_msg.pressed.emit()
	check(sent_one("set_panel").get("msgs", []).size() == 1, "a display panel gets a message with a condition")
	var chart := _find_checkbox(screen, "Show tag in chart")
	if chart != null:
		chart.button_pressed = true
	check(sent_one("set_panel").get("chart") == 1, "a display panel's Show tag in chart")
	var text_box := screen.find_child("PanelText", true, false) as TextEdit
	if text_box != null:
		text_box.text = "Two lines"
	var confirm := screen.find_child("Confirm", true, false) as Button
	if confirm != null:
		confirm.pressed.emit()
	check(sent_one("set_panel").get("text") == "Two lines", "a display panel's text is sent with the green tick")


## The wire tools: what a click sends, reach, letting go, removing a pole's cables, drawing.
func _wires(hud: Hud) -> void:
	var m: UiModel = hud.ui.model
	var world := WorldMirror.new()
	world.protos.add_entities([
		[1, "constant-combinator", "constant-combinator", -0.5, -0.5, 0.5, 0.5, 200, 180, 0, 1, 1],
		[2, "decider-combinator", "decider-combinator", -0.5, -1, 0.5, 1, 200, 180, 0, 1, 2],
		[3, "small-electric-pole", "electric-pole", -0.25, -0.25, 0.25, 0.25, 120, 90, 60, 1, 1],
		[4, "small-lamp", "lamp", -0.5, -0.5, 0.5, 0.5, 200, 200, 160, 1, 1],
	])
	m.handle({"t": "eprops", "l": [[1, 0, 0, 0, {"cw": 9}], [2, 0, 0, 0, {"cw": 9}], [3, 0, 7.5, 2.5, {"cw": 7.5}], [4, 0, 0, 0, {"cw": 9}]]})
	world.chunks[Vector2i.ZERO] = ChunkView.new()
	world._add([60, 1, 2 * 256 + 128, 2 * 256 + 128, 0])
	world._add([61, 2, 4 * 256 + 128, 2 * 256, 0])
	world._add([62, 3, 0 * 256 + 128, 6 * 256 + 128, 0])
	world._add([63, 3, 20 * 256 + 128, 6 * 256 + 128, 0])
	world._add([64, 4, 6 * 256 + 128, 2 * 256 + 128, 0, {"g": [61]}])
	var tool := WireTool.new()
	tool.world = world
	tool.model = m
	add_child(tool)
	sent()
	var alt_r := Controls.key_event(KEY_R | KEY_MASK_ALT)
	alt_r.pressed = true
	check(Controls.pressed(alt_r, "give_red_wire") and not Controls.pressed(alt_r, "rotate"), "Alt+R gives red wire (not rotate)")
	var e: Dictionary = world.entities
	check(tool.click("red-wire", e[60], Vector2(2.5, 2.5)) == "" and sent().is_empty() and not tool.from.is_empty(),
		"a first click takes the wire from the entity")
	tool.update("red-wire", null, Vector2(3.5, 3.5), true)
	check(tool._mesh.get_surface_count() == 1, "the wire is drawn to the mouse with its reach")
	tool.click("red-wire", e[61], Vector2(4.5, 2.6))
	var w := sent_one("wire")
	check(w.get("k") == "r" and w.get("a", {}).get("u") == 60 and w.get("b", {}).get("u") == 61 and int(w.get("b", {}).get("my", 0)) == roundi(2.6 * 256),
		"the second click connects them, with where it landed (the combinator's side)")
	check((tool.from["rec"] as WorldMirror.Rec).unit == 61, "the wire then hangs from the second entity")
	tool.click("red-wire", e[61], Vector2(4.5, 2.6))
	check(tool.from.is_empty() and sent().is_empty(), "clicking it again lets go")
	check(tool.click("copper-wire", e[64], Vector2(6.5, 2.5)) != "", "copper wire doesn't go on a lamp")
	tool.click("copper-wire", e[62], Vector2(0.5, 6.5))
	check(tool.click("copper-wire", e[63], Vector2(20.5, 6.5)) == "Wire can't reach that far" and sent().is_empty(), "a pole out of reach is refused")
	check(tool.cancel() and tool.from.is_empty(), "right click lets go of the wire")
	tool.clear_cables(e[62])
	check(sent_one("wire_clear").get("u") == 62, "Shift+click on a pole removes its cables")
	var input := PlayerInput.new()
	input.world = world
	check(input._openable(e[64]), "a wired lamp opens (anything on a circuit network does)")
	input.free()
	tool.queue_free()


func _find_slot_tip(node: Node, title: String) -> Node:
	for child in node.get_children():
		if child.get("tip_title") == title and not child.is_queued_for_deletion():
			return child
		var found := _find_slot_tip(child, title)
		if found != null:
			return found
	return null


## Slots named <prefix><n> under a node, in order.
func _slots_named(node: Node, prefix: String) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Slot and str(child.name).begins_with(prefix) and str(child.name).substr(prefix.length()).is_valid_int() \
				and not child.is_queued_for_deletion():
			out.append(child)
		else:
			out.append_array(_slots_named(child, prefix))
	return out


func _find_checkbox(node: Node, text: String) -> CheckBox:
	for child in node.get_children():
		if child is CheckBox and (child as CheckBox).text == text and not child.is_queued_for_deletion():
			return child
		var c := _find_checkbox(child, text)
		if c != null:
			return c
	return null


## Every label's text under a node, at any depth.
func _all_texts(node: Node) -> Array:
	var out: Array = []
	for child in node.find_children("*", "", true, false):
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
	return out


func _texts(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		elif child is RichTextLabel:
			out.append((child as RichTextLabel).get_parsed_text())
		elif child is Button and (child as Button).text != "":
			out.append((child as Button).text)
		out.append_array(_texts(child))
	return out


func _find_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and (child as Button).text == text and not child.is_queued_for_deletion():
			return child
		var b := _find_button(child, text)
		if b != null:
			return b
	return null


func _find_recipe_slot(ui, recipe: String) -> Node:
	var stack: Array = [ui.window]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta("recipe") and str(n.get_meta("recipe")) == recipe and not n.is_queued_for_deletion():
			return n
		stack.append_array(n.get_children())
	return null


## The HUD's pieces stay on screen and apart at common window sizes, both at Factorio's automatic UI
## scale and at 200%. The HUD is laid out in a smaller area at this test's scale instead of
## rebuilding it at each scale: the same layout, divided by the scale.
func _layout(hud: Hud) -> void:
	var ui = hud.ui
	var root: Control = hud.get_child(0)
	ui.close_all()
	ui.open_map(false)
	ui.debug_overlay = true
	ui.model.handle({"t": "rs", "cur": "automation", "pr": 250, "q": []})
	ui.model.handle({"t": "cq", "pr": 300, "l": [[1, "iron-gear-wheel", 3, 0], [2, "transport-belt", 2, 0]]})
	ui.model.handle({"t": "al", "l": [["no_power", 3, [[0, 0, 1, "assembling-machine-1", 5]]]]})
	hud.cursor_label.text = "12 km/h · WASD drive · Enter: get out"
	var had_help := bool(Settings.get_value("interface", "show_help"))
	Settings.set_value("interface", "show_help", true)
	hud.help.visible = true
	var platforms := PanelContainer.new()  # stands in for main.gd's platform panel
	platforms.custom_minimum_size = Kit.pxv(300, 140)
	hud.add_child(platforms)
	ui.platform_panel = platforms
	root.anchor_right = 0.0
	root.anchor_bottom = 0.0
	var pieces := {"debug line": ui.status_label, "research": ui.research_hud, "platforms": platforms, "minimap": ui.minimap,
		"quickbar": ui.quickbar, "weapons": ui.weapons, "shortcuts": ui.shortcuts, "alerts": ui.alerts,
		"crafting queue": ui.craft_queue, "driving line": hud.cursor_label, "help": hud.help}
	for window in [Vector2(1280, 720), Vector2(1626, 971), Vector2(1920, 1080), Vector2(2560, 1440)]:
		for ui_scale in [Kit.scale_for(window.y), 2.0]:
			var view: Vector2 = (window / (ui_scale / Kit.scale)).floor()
			root.size = view
			for i in 4:
				await get_tree().process_frame
			var where := "%dx%d at %d%%" % [window.x, window.y, roundi(ui_scale * 100.0)]
			var rects := {}
			for piece in pieces:
				var c: Control = pieces[piece]
				if c.is_visible_in_tree() and c.self_modulate.a > 0.0:
					rects[piece] = c.get_global_rect()
			check(rects.size() == pieces.size() or (ui_scale > 1.25 and rects.size() == pieces.size() - 1 and not rects.has("help")),
				"%s: every piece shows (missing: %s)" % [where, ", ".join(pieces.keys().filter(func(p): return not rects.has(p)))])
			var screen := Rect2(Vector2.ZERO, view)
			var names: Array = rects.keys()
			for i in names.size():
				var a: Rect2 = rects[names[i]]
				check(screen.encloses(a.grow(-0.5)), "%s: %s %s on screen (%s)" % [where, names[i], a, view])
				for j in range(i + 1, names.size()):
					var b: Rect2 = rects[names[j]]
					check(not a.grow(-0.5).intersects(b.grow(-0.5)), "%s: %s %s and %s %s apart" % [where, names[i], a, names[j], b])
			# F2: on a platform its panel sits right under the minimap, against the right edge, or
			# beside it when the shortcut bar would have no room.
			var side: Rect2 = ui.side_menu.get_global_rect()
			var pr: Rect2 = rects.get("platforms", Rect2())
			var below := absf(pr.position.y - side.end.y) < 1.0 and absf(pr.end.x - view.x) < 1.0
			var beside := absf(pr.position.y - side.position.y) < 1.0 and pr.end.x <= side.position.x
			check(below or beside,
				"%s: the platform panel sits under the minimap (F2): %s by %s" % [where, pr, side])
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.platform_panel = null
	platforms.queue_free()
	# The help panel: off by default (Factorio has none) and hidden while a window is open.
	check(Settings.DEFAULTS["interface"]["show_help"] == false, "the help panel is off by default")
	ui.window.open_crafting(true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not hud.help.visible, "the help panel hides while a window is open")
	ui.close_all()
	Settings.set_value("interface", "show_help", had_help)
	ui.debug_overlay = false


## A picture of the HUD in a busy state: inventory with a stack in the cursor, the crafting queue,
## weapons, the health bar and a message.
func _picture(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.55, 0.35)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	hud.get_child(0).add_child(bg)
	hud.get_child(0).move_child(bg, 0)
	ui.model.set_inventory_slots([["transport-belt", 50], ["iron-plate", 7], ["coal", 20]], 80)
	ui.model.handle({"t": "cq", "pr": 300, "l": [[1, "iron-gear-wheel", 3, 0], [2, "transport-belt", 2, 0]]})
	ui.model.pin(0, "transport-belt")
	ui.model.pin(1, "inserter")
	ui.toggle_inventory()
	click_main(ui, 1)
	hud.set_health(120, 250)
	hud.set_mining(60)
	hud.show_message("Out of reach")
	ui._hover_at = get_viewport().get_visible_rect().size * Vector2(0.5, 0.35)
	ui._hover()
	ui.cursor.over_world_too = true  # no world here to say whether a ghost shows
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[-1])


## Space Age's screens (space_panels.gd, space_map.gd, planet_info.gd): the hub, a silo, a landing
## pad, a collector, quality and freshness in slots, the space map, the planet panel.
func _space(hud: Hud, player: Node) -> void:
	var ui = hud.ui
	var m = ui.model
	ui.close_all()
	player.cursor_item = ""
	sent()
	var screen: MachineScreen = hud.screen

	# --- slots: quality icons and the freshness bar, everywhere slots are drawn -------------------
	m.handle({"t": "slots", "l": {"main": [["iron-plate", 100, "rare"], ["yumako", 10, "normal", 250], 0]}})
	ui.toggle_inventory()
	await get_tree().process_frame
	var rare := _find_slot_tip(ui.window, "Iron plate")
	check(rare != null and rare.quality == "rare" and rare.freshness < 0.0, "an inventory slot knows its stack's quality")
	var fruit := _find_slot_tip(ui.window, "Yumako")
	check(fruit != null and is_equal_approx(fruit.freshness, 0.25), "and a spoiling stack's freshness (the bar)")
	check(fruit != null and fruit.tip_lines.any(func(l): return str(l[0]) == "Freshness: 25%"), "the tooltip says how fresh it is")
	ui.close_all()

	# --- the hub: the platform, its schedule, its requests from planets --------------------------
	var hub_msg := {"t": "gui", "u": 600, "p": 0, "kind": "hub", "inv": {"chest": [["iron-plate", 40]], "trash": []},
		"slots": {"chest": [["iron-plate", 40, "uncommon"], 0], "trash": [0]}, "status": "working", "ql": ["normal", "uncommon", "rare"],
		"hub": {"i": 1, "n": "Mock Orbiter", "st": "on_the_path", "pa": 0, "sp": 120.0, "w": 1250000, "from": "nauvis", "to": "vulcanus",
			"d": 400, "len": 15000, "th": [2, 2], "fuel": [["thruster-fuel", 1600, 2000]], "prov": 0, "dest": ["nauvis", "vulcanus"],
			"sched": {"current": 1, "group": "", "records": [{"station": "vulcanus", "wait_conditions": [{"type": "all_requests_satisfied", "compare_type": "and"}]}],
				"interrupts": []},
			"sec": [{"i": 1, "g": "", "on": 1, "m": 1, "man": 1, "f": [["iron-plate", "normal", 200, -1, "nauvis", -1]]}]}}
	screen.request(600, {"t": "open", "u": 600, "p": 0, "x": 0, "y": 0})
	sent()
	screen.handle(hub_msg)
	await get_tree().process_frame
	check(screen.is_open() and _texts(screen).has("Travelling: Nauvis → Vulcanus"), "a hub's screen shows the platform's trip")
	check(_texts(screen).any(func(t): return str(t).contains("Weight 1250 t") and str(t).contains("Thrusters 2 / 2 working")),
		"its speed, weight and thrusters")
	var pause := _find_button(screen, "Pause")
	if pause != null:
		pause.pressed.emit()
	check(sent_one("set_hub").get("pa") == 1, "Pause pauses the platform")
	var go := _find_button(screen, "Go")
	if go != null:
		go.pressed.emit()
	var tg := sent_one("train_go")
	check(tg.get("i") == 1 and int(tg.get("u", 0)) == 600, "Go sends the platform to that stop (the hub takes the train commands)")
	var prov := _find_checkbox(screen, "Provide materials to other platforms")
	if prov != null:
		prov.button_pressed = true
	check(sent_one("set_hub").get("prov") == 1, "provide to other platforms")
	var hub_columns := screen._columns.get_children().filter(func(c): return c.has_meta("extra_column"))
	check(hub_columns.size() == 2, "the hub's window has Factorio's three columns")
	var req: Node = null
	for b in _all_buttons(screen):
		if b.get("tip_title") == "Iron plate" and b.get("count") == 200:
			req = b
	check(req != null, "a request from a planet shows as a slot with its minimum")
	if req != null:
		req.clicked.emit(MOUSE_BUTTON_LEFT, false)
		await get_tree().process_frame
	var set_button := _find_button(screen, "Set")
	if set_button != null:
		set_button.pressed.emit()
	var sec := sent_one("set_section")
	var f0: Array = sec.get("f", [[]])[0] if sec.get("f") is Array else []
	check(int(sec.get("i", 0)) == 1 and f0.size() == 6 and f0[0] == "iron-plate" and int(f0[2]) == 200 and int(f0[3]) == -1
		and f0[4] == "nauvis" and int(f0[5]) == -1,
		"editing a request sends its section, import from planet and minimum delivery included")
	var add_section := _find_button(screen, "Add section")
	if add_section != null:
		add_section.pressed.emit()
	check(sent_one("set_section").get("i") == 0, "Add section")
	var moving: Dictionary = hub_msg.duplicate(true)
	moving["hub"]["d"] = 700
	screen.handle(moving)
	check(_texts(screen).any(func(t): return str(t).contains("10k / 15k km")), "the trip moves on without rebuilding the window")
	# A long schedule scrolled down stays where it is when the screen is rebuilt (the
	# hub's inventory changes every second on a busy platform).
	var long_msg: Dictionary = moving.duplicate(true)
	var stops: Array = []
	for i in 16:
		stops.append({"station": "vulcanus" if i % 2 == 0 else "nauvis", "wait_conditions": [{"type": "time", "compare_type": "and", "ticks": 1800}]})
	long_msg["hub"]["sched"]["records"] = stops
	screen.handle(long_msg)
	for i in 3:
		await get_tree().process_frame
	var hub_scroll := func() -> ScrollContainer:
		var col: Node = screen._columns.get_children().filter(func(c): return c.has_meta("extra_column")).back()
		var found := col.find_children("*", "ScrollContainer", true, false)
		return found[0] if not found.is_empty() else null
	var before: ScrollContainer = hub_scroll.call()
	var room := before.get_v_scroll_bar().max_value - before.get_v_scroll_bar().page if before != null else 0.0
	if before != null:
		before.scroll_vertical = 150
	var refilled: Dictionary = long_msg.duplicate(true)
	refilled["slots"]["chest"] = [["iron-plate", 41, "uncommon"], 0]
	screen.handle(refilled)
	for i in 3:
		await get_tree().process_frame
	var after: ScrollContainer = hub_scroll.call()
	check(room > 150.0 and after != null and after != before and after.scroll_vertical == 150,
		"the hub's schedule keeps its scroll place when the screen is rebuilt: %s of %s" % [after.scroll_vertical if after != null else -1, room])
	screen.close()
	sent()

	# --- a silo: parts, automatic launch, launch to a platform ---------------------------------------
	screen.request(601, {"t": "open", "u": 601, "p": 0, "x": 0, "y": 0})
	sent()
	screen.handle({"t": "gui", "u": 601, "p": 0, "kind": "silo", "inv": {"input": [], "rocket": [["space-platform-starter-pack", 1]]},
		"slots": {"input": [0, 0, 0], "rocket": [["space-platform-starter-pack", 1], 0]}, "status": "working",
		"rk": {"parts": 50, "need": 50, "st": "rocket_ready", "auto": 0, "to": [[2, "Platform 2", "waiting_for_starter_pack"]]}})
	await get_tree().process_frame
	check(_texts(screen).has("Rocket parts: 50 / 50") and _texts(screen).has("Rocket inventory"), "a silo shows its parts and the rocket's inventory")
	check(_texts(screen).has("Rocket progress") and _texts(screen).count("100%") >= 2 and _texts(screen).has("Trash unrequested"),
		"a silo: Rocket progress with its two bars, and its requests in the second column")
	var auto := _find_checkbox(screen, "Send to orbit automatically")
	if auto != null:
		auto.button_pressed = true
	check(sent_one("set_silo").get("auto") == 1, "automatic launches")
	var launch := _find_button(screen, "Launch")
	check(launch != null and not launch.disabled, "Launch, with the rocket ready")
	if launch != null:
		launch.pressed.emit()
	check(sent_one("silo_launch").get("to") == 2, "launches to the platform waiting for its starter pack")
	var no_ride := _find_button(screen, "Ride")
	check(no_ride != null and no_ride.disabled, "no ride to a platform still waiting for its starter pack")
	screen.handle({"t": "gui", "u": 601, "p": 0, "kind": "silo", "inv": {"input": [], "rocket": []},
		"slots": {"input": [0, 0, 0], "rocket": [0, 0]}, "status": "working",
		"rk": {"parts": 50, "need": 50, "st": "rocket_ready", "auto": 0, "to": [[3, "Orbiter", "waiting_at_station"]]}})
	await get_tree().process_frame
	var ride_button := _find_button(screen, "Ride")
	check(ride_button != null and not ride_button.disabled, "Ride, with the rocket ready and a platform with a hub in orbit")
	if ride_button != null:
		ride_button.pressed.emit()
	var rode := sent()
	check(rode.any(func(m): return m.get("t") == "ride" and m.get("u") == 601 and m.get("to") == 3) and screen.unit == 0,
		"Ride sends ride to the platform and closes the silo's screen: %s" % [rode])
	screen.close()
	sent()

	# --- a landing pad, a collector, a crafter's recipe quality and effects ---------------------------
	screen.request(602, {"t": "open", "u": 602, "p": 0, "x": 0, "y": 0})
	sent()
	screen.handle({"t": "gui", "u": 602, "p": 0, "kind": "pad", "inv": {"chest": [], "trash": []}, "slots": {"chest": [0], "trash": [0]},
		"pad": {"sec": [], "cb": {"read": 1, "req": 0, "empty": 0}}})
	await get_tree().process_frame
	var set_req := _find_checkbox(screen, "Set requests")
	if set_req != null:
		set_req.button_pressed = true
	check(sent_one("set_pad").get("req") == 1, "a landing pad's circuit settings")
	screen.close()
	sent()
	screen.request(603, {"t": "open", "u": 603, "p": 0, "x": 0, "y": 0})
	sent()
	screen.handle({"t": "gui", "u": 603, "p": 0, "kind": "collector", "inv": {"output": []}, "slots": {"output": [0]},
		"col": {"n": 3, "f": ["", "", ""]}})
	await get_tree().process_frame
	var chunk_filter := _find_slot_tip(screen, "No filter")
	if chunk_filter != null:
		chunk_filter.clicked.emit(MOUSE_BUTTON_LEFT, false)
	var sc := sent_one("set_collector")
	check(str(sc.get("f", [""])[0]).ends_with("-asteroid-chunk"), "a collector's filter slot picks an asteroid chunk")
	screen.close()
	sent()
	screen.request(604, {"t": "open", "u": 604, "p": 0, "x": 0, "y": 0})
	sent()
	screen.handle({"t": "gui", "u": 604, "p": 0, "kind": "crafter", "inv": {}, "recipe": "iron-gear-wheel", "rq": "rare",
		"ql": ["normal", "uncommon", "rare"], "eff": {"q": 25, "sp": -50}, "rl": ["iron-gear-wheel", "transport-belt"]})
	await get_tree().process_frame
	check(_texts(screen).has("Quality +2.5%") and _texts(screen).has("Speed -5.0%"), "module effects, quality among them")
	screen._picking = true
	screen._rebuild_now()
	await get_tree().process_frame
	var uncommon: Button = null
	for b in _all_buttons(screen):
		if b.tooltip_text == "Uncommon":
			uncommon = b
	if uncommon != null:
		uncommon.pressed.emit()
	var belt_recipe := _find_slot_tip(screen, "Transport belt")
	if belt_recipe != null:
		belt_recipe.clicked.emit(MOUSE_BUTTON_LEFT, false)
	var sr := sent_one("set_recipe")
	check(sr.get("recipe") == "transport-belt" and sr.get("q") == "uncommon", "the recipe picker sets the recipe's quality")
	screen.close()
	sent()

	# --- the space map, the planet panel, "can't build here", chunks and belt quality --------------
	m.handle({"t": "smap", "loc": [["nauvis", "planet", 0, -5000, 1, 1], ["vulcanus", "planet", 9000, 4000, 1, 0],
		["aquilo", "planet", 2000, 20000, 0, 0]], "con": [["nauvis", "vulcanus", 15000, 120], ["vulcanus", "aquilo", 30000, 900]]})
	check(m.space_locations.size() == 3 and m.space_connections[1]["danger"] == 0.9 and m.space_locations[0]["position"] == Vector2(0, -5),
		"smap message")
	ui.open_space_map(true)
	check(ui.space_map.is_open() and sent_one("smap").get("t") == "smap", "the space map opens and asks for the solar system")
	m.map_surfaces = [{"si": 1, "name": "nauvis", "planet": "nauvis", "platform": "", "pf": 0},
		{"si": 3, "name": "vulcanus", "planet": "vulcanus", "platform": "", "pf": 0}]
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.remote_frame.visible and ui.remote_frame.mode == "space" and ui.space_map.size.x > 0.0 and not ui.minimap.visible
		and ui.map_view.surfaces_panel.visible and (ui.map_view.surfaces_panel.find_child("SpaceMap", true, false) as Button).theme_type_variation == "FListItemSelected",
		"the space map is full screen in the Remote view frame, its row chosen in the Surfaces panel, the minimap hidden")
	# Hovering a route between planets highlights it and tells its distance and danger.
	var map_scale_was: float = ui.space_map.view_scale
	ui.space_map.view_center = Vector2(4.5, -0.5)
	ui.space_map.view_scale = 40.0  # the test's window is tiny: zoom in so the planets don't cover the route
	var route_ends: Array = ui.space_map._route_ends(0)
	var on_route: Vector2 = (route_ends[0] + route_ends[1]) * 0.5
	var hovered: Dictionary = ui.space_map.pick(on_route)
	var route_tip: String = ui.space_map._get_tooltip(on_route)
	check(hovered.get("route") == 0 and route_tip.contains("15 000 km") and route_tip.contains("Asteroids: Low") and route_tip.contains("—"),
		"a route on the space map: hover shows both ends, the distance and the asteroid danger: %s" % [route_tip])
	ui.space_map.view_scale = map_scale_was
	check(ui.space_map.km(1234567) == "1 234 567" and ui.space_map.danger_text(0.9) == "High", "distances written in full, danger in words")
	# A platform: parked at Nauvis, then selected on the map (its panel), then looked at.
	var pf_script := GDScript.new()
	pf_script.source_code = "extends Control\nvar platforms := {}\nvar on := 0\n"
	pf_script.reload()
	var pf_stub: Control = pf_script.new()
	pf_stub.platforms = {5: {"i": 5, "n": "Orbiter", "st": "waiting_at_station", "pa": 0, "hub": 9, "sp": 0.0, "w": 86600, "loc": "nauvis"}}
	add_child(pf_stub)
	var old_panel = ui.platform_panel
	ui.platform_panel = pf_stub
	m.map_surfaces = [{"si": 1, "name": "nauvis", "planet": "nauvis", "platform": "", "pf": 0},
		{"si": 3, "name": "vulcanus", "planet": "vulcanus", "platform": "", "pf": 0},
		{"si": 4, "name": "platform-5", "planet": "", "platform": "Orbiter", "pf": 5}, {"si": 6, "name": "f3d-lab", "planet": "", "platform": "", "pf": 0}]
	m.map_surfaces_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var spots: Array = ui.space_map._platform_spots()
	check(spots.size() == 1 and _texts(ui.map_view.surfaces_panel).has("Other") and _texts(ui.map_view.surfaces_panel).has("f3d-lab")
		and ui.map_view.surfaces_panel.find_child("Surface4", true, false).find_child("At", true, false) != null,
		"the platform is drawn by its planet; the Surfaces panel has Other and the platform row its planet: %s" % [_texts(ui.map_view.surfaces_panel)])
	if not spots.is_empty():
		ui.space_map.click(spots[0][0])
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.space_map.selected == 5 and ui.remote_frame.info_panel.visible and _texts(ui.remote_frame.info_panel).has("Stopped at Nauvis")
		and _texts(ui.remote_frame.info_panel).has(" 86.6 tons"),
		"a click selects a platform: Factorio's panel under the tag icons (where, speed, mass): %s" % [_texts(ui.remote_frame.info_panel)])
	if not spots.is_empty():
		ui.space_map.click(spots[0][0])
	check(not ui.space_map.is_open() and ui.map_view.is_open() and m.map_si == 4, "a second click looks at the platform in remote view")
	await get_tree().process_frame
	await get_tree().process_frame
	check(ui.remote_frame.info_panel.visible, "the map of a platform shows its panel too")
	# G1, as Factorio 2.1.23 draws it (capture.py --only platform_panel): travelling, the strip holds the
	# planet it left, the bar of the way done with the distance come at its end, and the next planet;
	# under it the speed and mass. The panel sits under the map view settings.
	pf_stub.platforms[5] = {"i": 5, "n": "Orbiter", "st": "on_the_path", "pa": 0, "hub": 9, "sp": 150.0, "w": 86600,
		"from": "nauvis", "to": "vulcanus", "d": 250, "len": 15000}
	await get_tree().process_frame
	await get_tree().process_frame
	var info_p: Control = ui.remote_frame.info_panel
	var jtexts := "|".join(PackedStringArray(_texts(info_p)))
	var jbar := info_p.find_child("JourneyBar", true, false) as ProgressBar
	var jfrom := info_p.find_child("JourneyFrom", true, false) as Button
	var jto := info_p.find_child("JourneyTo", true, false) as Button
	# The planets' icons come from a Factorio install (none in CI).
	var icons_ok := SoundBank.data_dir() == "" or (jfrom != null and jfrom.icon != null)
	check(jbar != null and jbar.value == 250 and jfrom != null and jfrom.tooltip_text == "Nauvis" and icons_ok
		and jto != null and jto.tooltip_text == "Vulcanus" and jtexts.contains("3 750 km") and jtexts.contains(" 150.00 km/s")
		and jtexts.contains(" 86.6 tons") and not jtexts.contains("Stopped at"),
		"the map of a travelling platform shows Factorio's strip: planet left, bar with the distance come, next planet: %s" % jtexts)
	var settings_r: Rect2 = ui.map_view.panel.get_global_rect()
	check(ui.map_view.panel.is_visible_in_tree() and info_p.get_global_rect().position.y >= settings_r.end.y - 0.5,
		"the platform's panel sits under the map view settings, as Factorio's: %s under %s" % [info_p.get_global_rect(), settings_r])
	# Stopped (paused, waiting at its stop, or done and waiting for cargo before it leaves) Factorio says
	# "Stopped at Nauvis" with the planet's icon; ours adds where it goes next (H7), with that planet's icon.
	pf_stub.platforms[5] = {"i": 5, "n": "Orbiter", "st": "waiting_for_departure", "pa": 0, "hub": 9, "sp": 0.0, "w": 60000,
		"loc": "nauvis", "nx": "vulcanus"}
	await get_tree().process_frame
	await get_tree().process_frame
	var wtexts := "|".join(PackedStringArray(_texts(info_p)))
	var next_row := info_p.find_child("NextStop", true, false)
	check(wtexts.contains("Stopped at Nauvis") and wtexts.contains(" 60 tons") and wtexts.contains(" 0.00 km/s") and next_row != null
		and _texts(next_row).has("Next stop:") and _texts(next_row).has(" Vulcanus") and info_p.find_child("JourneyBar", true, false) == null,
		"waiting for its cargo before leaving: Factorio's Stopped at Nauvis, and the next stop with its icon (H7): %s" % wtexts)
	pf_stub.platforms[5] = {"i": 5, "n": "Orbiter", "st": "paused", "pa": 1, "hub": 9, "sp": 0.0, "w": 1000, "loc": "nauvis"}
	await get_tree().process_frame
	await get_tree().process_frame
	wtexts = "|".join(PackedStringArray(_texts(info_p)))
	check(wtexts.contains("Stopped at Nauvis") and wtexts.contains(" 1 ton") and info_p.find_child("NextStop", true, false) == null,
		"paused, Factorio still says Stopped at (no Paused at), one ton: %s" % wtexts)
	# H3: zoomed into the platform's world from Nauvis (the remote view of another surface), its panel
	# shows under the minimap (the HUD's platform panel, watching that platform), the frame's goes.
	pf_stub.platforms[5] = {"i": 5, "n": "Orbiter", "st": "on_the_path", "pa": 0, "hub": 9, "sp": 150.0, "w": 86600,
		"from": "nauvis", "to": "vulcanus", "d": 250, "len": 15000}
	var hud_pp := PlatformPanel.new()
	hud.add_child(hud_pp)
	hud_pp.handle({"on": 0, "here": "nauvis", "dest": ["nauvis", "vulcanus"], "l": [pf_stub.platforms[5]]})
	ui.platform_panel = hud_pp
	ui.open_map(false)
	ui.remote = true
	ui.viewing_si = 4
	await get_tree().process_frame
	await get_tree().process_frame
	var corner: Rect2 = ui.side_menu.get_global_rect()
	var hud_r := hud_pp.get_global_rect()
	# under the minimap, or beside it on a window too short for that (F2)
	var placed := absf(hud_r.position.y - corner.end.y) < 1.0 or (absf(hud_r.position.y - corner.position.y) < 1.0 and hud_r.end.x <= corner.position.x)
	check(hud_pp.visible and hud_pp.find_child("JourneyBar", true, false) != null and not ui.remote_frame.info_panel.is_visible_in_tree()
		and placed and absf(hud_r.size.x - corner.size.x) < 1.0
		and not (hud_pp.find_child("DropRow", true, false) as Control).visible,
		"the remote view of a platform shows its panel under the minimap, as wide as the column (H3): %s under %s" % [hud_r, corner])
	ui.viewing_si = 0
	ui.remote = false
	await get_tree().process_frame
	check(not hud_pp.visible, "back to the character on Nauvis, the panel goes")
	# On board: Factorio's "Drop to a planet" with the character's icon, and the red cross that cancels.
	var aboard := {"i": 5, "n": "Orbiter", "st": "on_the_path", "pa": 0, "hub": 9, "sp": 150.0, "w": 86600,
		"from": "nauvis", "to": "vulcanus", "d": 250, "len": 15000}
	hud_pp.handle({"on": 5, "dest": ["nauvis", "solar-system-edge", "vulcanus"], "l": [aboard]})
	await get_tree().process_frame
	var drop_b := hud_pp.find_child("Drop", true, false) as Button
	var cancel_b := hud_pp.find_child("CancelDrop", true, false) as Button
	check(hud_pp.visible and drop_b != null and drop_b.is_visible_in_tree() and drop_b.text == "Drop to a planet" and cancel_b.disabled,
		"on board the panel has Factorio's Drop to a planet, the cross unlit")
	sent()
	drop_b.pressed.emit()
	var choices := hud_pp.find_child("DropChoices", true, false) as Control
	check(choices.visible and choices.find_child("DropTo_vulcanus", true, false) != null
		and choices.find_child("DropTo_solar-system-edge", true, false) == null, "it lists the planets to drop to: %s" % [_texts(choices)])
	(choices.find_child("DropTo_vulcanus", true, false) as Button).pressed.emit()
	check(not choices.visible and drop_b.text == "Dropping to Vulcanus" and not cancel_b.disabled and sent_one("land").is_empty(),
		"travelling, a drop to Vulcanus waits for the platform to get there (Dropping to Vulcanus)")
	aboard = {"i": 5, "n": "Orbiter", "st": "waiting_at_station", "pa": 0, "hub": 9, "sp": 0.0, "w": 86600, "loc": "vulcanus"}
	hud_pp.handle({"on": 5, "dest": ["nauvis", "vulcanus"], "l": [aboard]})
	check(sent_one("land").get("t") == "land" and hud_pp.dropping_to == "" and drop_b.text == "Drop to a planet",
		"stopped at Vulcanus, it drops (land)")
	drop_b.pressed.emit()
	(hud_pp.find_child("DropTo_nauvis", true, false) as Button).pressed.emit()
	cancel_b.pressed.emit()
	check(hud_pp.dropping_to == "" and cancel_b.disabled and sent_one("land").is_empty(), "the red cross cancels a planned drop")
	ui.platform_panel = pf_stub
	hud_pp.queue_free()
	ui.open_map(false)
	ui.open_space_map(true)
	var planet_at: Vector2 = ui.space_map.to_screen(m.space_locations[1]["position"])
	ui.space_map.click(planet_at)
	check(not ui.space_map.is_open() and ui.map_view.is_open() and m.map_si == 3, "clicking a planet shows it in remote view (the map's surface switcher)")
	ui.platform_panel = old_panel
	pf_stub.queue_free()
	ui.open_map(false)
	sent()
	m.handle({"t": "planet", "name": "space", "props": {"gravity": 0, "pressure": 0, "solar-power": 300}, "day": 25000, "always": 1,
		"heat": [], "nb": [[42, "gravity", 0.1, 1000000000]]})
	check(m.cant_build_reason(42) == "Can't build here: gravity is 0.0 m/s², it needs at least 0.1 m/s²" and m.cant_build_reason(7) == "",
		"planet.nb: why something can't be built here")
	ui.toggle_inventory()
	await get_tree().process_frame
	check(_texts(ui.window).has("Space") and _texts(ui.window).has("Gravity") and _texts(ui.window).has("300%"),
		"the character screen shows the planet's properties")
	ui.close_all()
	m.handle({"t": "ach", "l": [["metallic-asteroid-chunk", 2560, -512, 0, 768]]})
	check(m.asteroid_chunks.size() == 1 and m.asteroid_chunks[0]["velocity"] == Vector2(0, 3), "ach message")
	m.handle({"t": "bq", "l": [[77, "rare"]]})
	check(m.belt_quality.get(77) == "rare", "bq message")
	m.handle({"t": "ach", "l": []})
	m.handle({"t": "bq", "l": []})
	sent()


func _all_buttons(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Button and not child.is_queued_for_deletion():
			out.append(child)
		out.append_array(_all_buttons(child))
	return out


## The second pass on those windows: tanks, spidertrons and their remote, artillery, pipes and
## tanks' pipelines, heat pipes, decider conditions that hold, the signal-or-constant operand,
## train groups and the train camera's remote view, what opens a window.
func _logic2_windows(screen: MachineScreen, ui) -> void:
	const LogicWindows := preload("res://scripts/ui/factorio/logic_windows.gd")
	const SpiderRemote := preload("res://scripts/player/spider_remote.gd")
	var gui := func(kind: String, extra: Dictionary) -> void:
		var msg := {"t": "gui", "u": 900, "p": 1, "kind": kind, "inv": {}}
		msg.merge(extra, true)
		screen.handle(msg)
	sent()
	# Tank: three guns over three ammo slots, then the equipment grid button.
	LogicWindows.vehicle_grid_open = false
	gui.call("vehicle", {"p": 28, "inv": {"fuel": [["solid-fuel", 20]], "trunk": [], "car_ammo": []},
		"slots": {"fuel": [["solid-fuel", 20], 0], "car_ammo": [0, 0, 0], "trunk": [0, 0, 0, 0]},
		"guns": ["tank-cannon", "tank-machine-gun", "tank-flamethrower"], "bu": 700, "veh": {"grid": 1}})
	await get_tree().process_frame
	var guns = screen.find_child("Guns", true, false)
	var grid_button := screen.find_child("EquipmentGrid", true, false) as Button
	check(guns != null and guns.get_child(0).get_child_count() == 3 and grid_button != null and screen.find_child("SpiderTargeting", true, false) == null,
		"a tank: its three guns over their ammo slots and the equipment grid button")
	if grid_button != null:
		grid_button.button_pressed = true
	check(LogicWindows.vehicle_grid_open, "the grid button shows the vehicle's equipment grid")
	LogicWindows.vehicle_grid_open = false
	# Spidertron: the name strip (rename, colour) and Auto targeting.
	gui.call("vehicle", {"p": 29, "col": [229, 113, 0], "inv": {"trunk": [], "car_ammo": []}, "slots": {"car_ammo": [0, 0, 0, 0], "trunk": [0, 0]},
		"guns": ["spidertron-rocket-launcher-1", "spidertron-rocket-launcher-2", "spidertron-rocket-launcher-3", "spidertron-rocket-launcher-4"],
		"veh": {"grid": 1, "lbl": "Spidey", "at": [1, 0]}})
	await get_tree().process_frame
	check(_texts(screen).has("Spidey") and screen.find_child("ColorPicker", true, false) != null and _texts(screen).has("Auto targeting"),
		"a spidertron: its name and colour in the strip, Auto targeting")
	var with_gunner := screen.find_child("WithGunner", true, false) as CheckBox
	if with_gunner != null:
		with_gunner.button_pressed = true
	check(sent_one("set_vehicle").get("wi") == 1, "With gunner sends set_vehicle wi")
	var rename := screen.find_child("Rename", true, false) as Button
	var field := screen.find_child("VehicleNameField", true, false) as LineEdit
	if rename != null and field != null:
		rename.pressed.emit()
		field.text_submitted.emit("Spider 2")
	check(sent_one("set_vehicle").get("lbl") == "Spider 2", "the pencil renames the spidertron")
	# Artillery: Auto targeting, no target priorities; the wagon too.
	gui.call("turret", {"p": 30, "inv": {"turret_ammo": []}, "slots": {"turret_ammo": [0]}, "tgt": {"l": [], "ign": 0}, "art": 1})
	await get_tree().process_frame
	var auto := screen.find_child("AutoTargeting", true, false) as CheckBox
	check(auto != null and auto.button_pressed and not _texts(screen).has("Target priorities"), "an artillery turret: Auto targeting, no target priorities")
	if auto != null:
		auto.button_pressed = false
	check(sent_one("set_artillery").get("on") == 0, "unticking Auto targeting sends set_artillery")
	gui.call("train", {"p": 31, "inv": {"ammo": []}, "slots": {"ammo": [0]}, "art": 0,
		"tr": {"id": 1, "state": "on_the_path", "manual": 0, "station": "", "dest": "", "sched": {"current": 1, "group": "", "records": []}}})
	await get_tree().process_frame
	auto = screen.find_child("AutoTargeting", true, false) as CheckBox
	check(auto != null and not auto.button_pressed, "an artillery wagon: Auto targeting over its shells")
	# Storage tank and pipe: the contents, the pipeline and the flush buttons.
	gui.call("other", {"p": 16, "fb": [["crude-oil", 25000, 25000, 25]], "pl": ["crude-oil", 106100, 106100]})
	await get_tree().process_frame
	check(_texts(screen).has("Storage tank contents:") and _texts(screen).has("Pipeline contents:") and _texts(screen).has("106100 of 106100"),
		"a storage tank: its contents and the pipeline's")
	var flush_pipe = screen.find_child("Flush1", true, false)
	var flush_button = flush_pipe.find_child("FlushButton", true, false) as Button if flush_pipe != null else null
	if flush_button != null:
		flush_button.pressed.emit()
	check(sent_one("flush").get("pipe") == 1, "the pipeline's red button flushes the pipeline")
	gui.call("other", {"p": 32, "fb": [["", 0, 100, 0]], "pl": ["", 0, 4800]})
	await get_tree().process_frame
	var empty_flush = screen.find_child("Flush0", true, false)
	var empty_button = empty_flush.find_child("FlushButton", true, false) as Button if empty_flush != null else null
	check(_texts(screen).has("No fluid") and _texts(screen).has("N/A") and _texts(screen).has("0.00 of 100") and _texts(screen).has("Pipe contents:")
		and empty_button != null and empty_button.disabled, "an empty pipe: No fluid, N/A, 0.00 of 100, its flush button greyed")
	gui.call("other", {"p": 33, "temp": 656, "tc": 65613, "tmax": 1000})
	await get_tree().process_frame
	check(_texts(screen).has("Temperature: 656.13 °C"), "a heat pipe: its temperature in the red bar")
	# Decider: a condition that holds is green, worked out from the input signals.
	var cond_cb := {"conditions": [{"first_signal": {"type": "virtual", "name": "signal-T"}, "comparator": "<", "constant": 1100},
		{"first_signal": {"type": "virtual", "name": "signal-X"}, "comparator": "=", "constant": 0, "compare_type": "and"}], "outputs": []}
	gui.call("combinator", {"p": 26, "cb": cond_cb, "sig": {"r": [], "g": [["virtual", "signal-T", 1300]], "gi": 26}})
	await get_tree().process_frame
	var c1 = screen.find_child("Condition1", true, false)
	var c2 = screen.find_child("Condition2", true, false)
	check(c1 != null and c2 != null and not c1.get_meta("holds") and c2.get_meta("holds"),
		"T(1300) < 1100 doesn't hold, X = 0 does: the second condition is green")
	check(CircuitPanel.condition_holds({"first_signal": {"type": "virtual", "name": "signal-anything"}, "comparator": ">", "constant": 5},
		{"r": [["item", "iron-plate", 3], ["item", "coal", 9]]}) and not CircuitPanel.condition_holds(
		{"first_signal": {"type": "virtual", "name": "signal-everything"}, "comparator": ">", "constant": 5},
		{"r": [["item", "iron-plate", 3], ["item", "coal", 9]]}), "Anything and Everything over the input signals")
	check(not CircuitPanel.condition_holds({"first_signal": {"type": "item", "name": "coal"}, "comparator": ">", "constant": 5,
		"first_signal_networks": {"red": false, "green": true}}, {"r": [["item", "coal", 9]]}), "an operand reads only the networks ticked beside it")
	# The second operand is one signal-or-constant button: the chooser with its Constant row.
	var operand := screen.find_child("SecondOperand", true, false) as Button
	check(operand != null and operand.text == "1.1k", "the constant shows on the operand button, as Factorio writes it: %s" % [operand.text if operand != null else ""])
	if operand != null:
		operand.pressed.emit()
	await get_tree().process_frame
	var crow = ui.picker.find_child("ConstantRow", true, false)
	var cbox := ui.picker.find_child("ConstantBox", true, false) as LineEdit
	check(ui.picker.is_open() and crow != null and crow.visible and cbox != null and cbox.text == "1100", "clicking it opens the chooser with the constant")
	if cbox != null:
		cbox.text = "42"
		cbox.text_submitted.emit("42")
	var dcb: Dictionary = sent_one("set_cb").get("cb", {})
	check(not ui.picker.is_open() and dcb.get("conditions", [{}])[0].get("constant") == 42, "Enter sets the constant")
	# Locomotive in a group: "[2]", the Change train group popup, the camera into remote view.
	var followed: Array = []
	var old_follow: Callable = screen.remote_follow
	screen.remote_follow = func(unit: int, at: Vector2) -> void: followed.append([unit, at])
	gui.call("train", {"p": 14, "col": [242, 120, 0], "inv": {"fuel": []}, "slots": {"fuel": [0, 0, 0]},
		"tr": {"id": 1, "state": "on_the_path", "manual": 0, "station": "", "dest": "Iron", "name": "Loco", "stops": ["Iron"], "pos": [2560, 512],
			"gc": 2, "groups": [["Copper", 2], ["Iron", 3]], "sched": {"current": 1, "group": "Copper", "records": []}}})
	await get_tree().process_frame
	check(_texts(screen).has("Copper") and _texts(screen).has("[2]"), "a train in a group: the group's name and its count")
	var change := screen.find_child("ChangeGroup", true, false) as Button
	if change != null:
		change.pressed.emit()
	await get_tree().process_frame
	var group_field := screen.find_child("GroupField", true, false) as LineEdit
	check(group_field != null and group_field.text == "Copper" and screen.find_child("Groups", true, false) != null, "the pencil opens Change train group")
	if group_field != null:
		group_field.text = "Iron"
		group_field.text_submitted.emit("Iron")
	var sg := sent_one("set_train_group")
	check(sg.get("g") == "Iron" and sg.get("all") == 0, "Enter moves the train to that group")
	var cam := screen.find_child("TrainCamera", true, false) as Control
	if cam != null:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		cam.gui_input.emit(click)
	check(followed.size() == 1 and followed[0][0] == 900 and followed[0][1] == Vector2(10, 2), "clicking the camera follows the train in remote view: %s" % [followed])
	screen.remote_follow = old_follow
	# The spidertron remote: a click sends the selection, Shift queues; spd draws the waypoints.
	var remote := SpiderRemote.new()
	check(remote.left(null, Vector2(5, 5), Vector2(5, 5), false) != "" and sent_one("spider_go").is_empty(), "with nothing selected a click only says so")
	remote.selected = [610]
	remote.left(null, Vector2(5, 5), Vector2(5.1, 5), true)
	var go := sent_one("spider_go")
	check(go.get("l", []).map(func(v): return int(v)) == [610] and int(go.get("q", 0)) == 1 and int(go.get("x", 0)) == int(5.1 * 256),
		"Shift+click queues a waypoint for the selection: %s" % [go])
	remote._on_message({"t": "spd", "l": [[610, [[1280, 256], [2560, 512]]]]})
	check(remote.waypoints.get(610) == [Vector2(5, 1), Vector2(10, 2)], "spd: each spidertron's waypoints")
	remote.left(null, Vector2(0, 0), Vector2(20, 20), false)
	check(remote.selected.is_empty(), "a drag over no spidertron empties the selection")
	check(PlayerInput.OPENABLE_TYPES.has("pipe") and PlayerInput.OPENABLE_TYPES.has("land-mine") and not PlayerInput.OPENABLE_TYPES.has("generator")
		and not PlayerInput.OPENABLE_MOVERS.has("fluid-wagon"), "what opens a window is 2.1.23's list (rules_openable)")
	sent()


## Prototypes for the entity windows that go by type (ids as the screen tests send them).
func _logic_protos() -> ProtoDB:
	var p := ProtoDB.new()
	var rows: Array = []
	for e in [[1, "wooden-chest", "container"], [11, "small-lamp", "lamp"], [12, "programmable-speaker", "programmable-speaker"],
			[13, "pump", "pump"], [14, "locomotive", "locomotive"], [15, "cargo-wagon", "cargo-wagon"],
			[16, "storage-tank", "storage-tank"], [17, "train-stop", "train-stop"], [18, "display-panel", "display-panel"],
			[19, "rail-signal", "rail-signal"], [20, "car", "car"], [21, "burner-inserter", "inserter"], [22, "gun-turret", "ammo-turret"],
			[23, "roboport", "roboport"], [24, "small-electric-pole", "electric-pole"], [25, "power-switch", "power-switch"],
			[26, "decider-combinator", "decider-combinator"], [27, "arithmetic-combinator", "arithmetic-combinator"],
			[28, "tank", "car"], [29, "spidertron", "spider-vehicle"], [30, "artillery-turret", "artillery-turret"],
			[31, "artillery-wagon", "artillery-wagon"], [32, "pipe", "pipe"], [33, "heat-pipe", "heat-pipe"]]:
		rows.append([e[0], e[1], e[2], -0.5, -0.5, 0.5, 0.5, 120, 120, 120, 1, 1])
	p.add_entities(rows)
	return p


## The logistics, logic, train and vehicle windows in Factorio's layout (logic_windows.gd,
## train_window.gd, circuit_panel.gd, circuit_window.gd): what each control sends.
func _logic_windows(screen: MachineScreen, ui) -> void:
	var gui := func(kind: String, extra: Dictionary) -> void:
		var msg := {"t": "gui", "u": 900, "p": 1, "kind": kind, "inv": {}}
		msg.merge(extra, true)
		screen.handle(msg)
	sent()
	# A burner inserter: the hand, the fuel slot and its bar, updated without a rebuild.
	gui.call("inserter", {"p": 21, "inv": {"fuel": [["coal", 2]]}, "slots": {"fuel": [["coal", 2]]}, "bu": 400,
		"ins": {"n": 0, "f": [], "st": 0, "max": 3, "h": ["iron-plate", 1]}})
	await get_tree().process_frame
	var hand = screen.find_child("Hand", true, false)
	var burner = screen.find_child("BurnerBar", true, false)
	check(hand != null and hand.item == "iron-plate" and burner != null and int(burner.value) == 400, "an inserter shows its hand, its fuel and the burning bar")
	gui.call("inserter", {"p": 21, "inv": {"fuel": [["coal", 2]]}, "slots": {"fuel": [["coal", 2]]}, "bu": 200,
		"ins": {"n": 0, "f": [], "st": 0, "max": 3}})
	await get_tree().process_frame
	check(screen.find_child("Hand", true, false) == hand and hand.item == "" and int(burner.value) == 200,
		"the hand and the bar change in place, without rebuilding the window")
	var size = screen.find_child("HandSize", true, false)
	check(size != null and not size.enabled, "the hand size slider is greyed until Override hand size is ticked")
	var override := _find_checkbox(screen, "Override hand size")
	if override != null:
		override.button_pressed = true
	check(int(sent_one("set_inserter").get("st", 0)) == 3, "ticking Override hand size sends the slider's value")
	gui.call("inserter", {"p": 21, "ins": {"n": 0, "f": [], "st": 3, "max": 3}})
	await get_tree().process_frame
	size = screen.find_child("HandSize", true, false)
	if size != null:
		size.commit(2)
	check(int(sent_one("set_inserter").get("st", 0)) == 2, "moving the notched slider sends the hand size")
	# A power switch: State, Off / On.
	gui.call("switch", {"p": 25, "sw": 0})
	await get_tree().process_frame
	var power = screen.find_child("PowerSwitch", true, false)
	if power != null:
		power.pick("right")
	check(sent_one("set_switch").get("on") == 1, "a power switch's Off / On switch")
	# A rail signal: the status line only, in a window of its own.
	gui.call("other", {"p": 19, "status": "working"})
	await get_tree().process_frame
	check(_texts(screen).has("Working") and not screen.shows_inventory(), "a rail signal opens alone with its status")
	# Arithmetic combinator: Input / Output, the signal strips, the description.
	gui.call("combinator", {"p": 27, "cb": {"operation": "*", "first_signal": {"type": "item", "name": "iron-plate"}, "second_constant": 2},
		"sig": {"r": [["item", "iron-plate", 5]], "g": [], "ri": 3, "out": {"r": [["item", "iron-plate", -10]], "g": [], "ri": 4}}, "desc": ""})
	await get_tree().process_frame
	var ins_strip = screen.find_child("InputSignals", true, false)
	check(_texts(screen).has("Input:") and _texts(screen).has("Output:") and ins_strip != null and _texts(screen).has("-10"),
		"an arithmetic combinator: the Input / Output strip, the signal strips (negative counts too)")
	var add_desc := screen.find_child("AddDescription", true, false) as Button
	if add_desc != null:
		add_desc.pressed.emit()
	var desc_text := screen.find_child("DescriptionText", true, false) as TextEdit
	if desc_text != null:
		desc_text.text = "Doubles iron"
	var desc_ok := screen.find_child("ConfirmDescription", true, false) as Button
	if desc_ok != null:
		desc_ok.pressed.emit()
	check(sent_one("set_desc").get("text") == "Doubles iron", "Add description sends the combinator's description")
	# Decider: + Add else.
	gui.call("combinator", {"p": 26, "cb": {"conditions": [{"comparator": "<", "constant": 0}], "outputs": []}})
	await get_tree().process_frame
	var add_else := screen.find_child("AddElseOutputs", true, false) as Button
	if add_else != null:
		add_else.pressed.emit()
	await get_tree().process_frame
	if ui.picker.is_open():
		ui.picker._callback.call("virtual", "signal-A")
		ui.picker.close()
	var dc: Dictionary = sent_one("set_cb").get("cb", {})
	check(dc.get("else_outputs", [{}])[0].get("signal", {}).get("name") == "signal-A", "+ Add else adds an else output")
	# Train stop: rename, train limit slider, priority, the train cards.
	gui.call("stop", {"p": 17, "col": [242, 0, 0], "stop": {"name": "Iron", "limit": 2, "count": 1, "pri": 50, "train": 0,
		"trs": [[4, "on_the_path", 1, 700], [5, "wait_station", 0, 710]]}})
	await get_tree().process_frame
	check(not screen.shows_inventory() and screen.find_child("Train4", true, false) != null and screen.find_child("Train5", true, false) == null,
		"a train stop opens alone; Trains on the way shows the train heading there")
	var with_tab := screen.find_child("TabTrainswiththisstop(2)", true, false) as Button
	if with_tab != null:
		with_tab.pressed.emit()
	await get_tree().process_frame
	check(screen.find_child("Train5", true, false) != null, "Trains with this stop shows every train with it in its schedule")
	var lim = screen.find_child("TrainLimit", true, false)
	if lim != null:
		lim.commit(4)
	check(sent_one("set_stop").get("limit") == 4, "the train limit slider")
	var pri = screen.find_child("Priority", true, false)
	if pri != null:
		pri.commit(80)
	check(sent_one("set_stop").get("pri") == 80, "the priority slider")
	var rename := screen.find_child("Rename", true, false) as Button
	var name_field := screen.find_child("StopNameField", true, false) as LineEdit
	if rename != null and name_field != null:
		rename.pressed.emit()
		name_field.text_submitted.emit("Copper")
	check(sent_one("set_stop").get("name") == "Copper", "the pencil renames the stop")
	# Locomotive: alone, its name and colour, the Fuel tab.
	gui.call("train", {"p": 14, "col": [242, 120, 0], "inv": {"fuel": [["coal", 20]]}, "slots": {"fuel": [["coal", 20], 0, 0]}, "bu": 500,
		"tr": {"id": 1, "state": "on_the_path", "manual": 0, "station": "", "dest": "Iron", "name": "Copper", "stops": ["Iron"],
			"sched": {"current": 1, "group": "", "records": [{"station": "Iron", "wait_conditions": []}]}}})
	await get_tree().process_frame
	check(not screen.shows_inventory() and _texts(screen).has("Copper") and screen.find_child("ColorPicker", true, false) != null,
		"a locomotive opens alone with its name and colour")
	var mode = screen.find_child("TrainMode", true, false)
	if mode != null:
		mode.pick("right")
	check(sent_one("train_mode").get("auto") == 0, "the Automatic / Manual switch sends manual")
	var fuel_tab := screen.find_child("TabFuel", true, false) as Button
	if fuel_tab != null:
		fuel_tab.pressed.emit()
	await get_tree().process_frame
	check(screen.find_child("Slots_fuel", true, false) != null and screen.find_child("Schedule", true, false) == null, "the Fuel tab shows the fuel slots")
	var sched_tab := screen.find_child("TabSchedule", true, false) as Button
	if sched_tab != null:
		sched_tab.pressed.emit()
	await get_tree().process_frame
	var add_wait = screen.find_child("AddWait", true, false)
	if add_wait != null:
		add_wait.get_meta("pick").call(0, false)
	var recs: Array = sent_one("set_schedule").get("records", [])
	check(recs.size() == 1 and recs[0].get("wait_conditions", []).size() == 1 and recs[0]["wait_conditions"][0].get("type") == "time",
		"+ Add wait condition adds the chosen condition")
	# Rich text icons in names players write: a stop's name, a schedule's stations and the
	# "+ Add station" list, a train group's name, a logistic group's name and the overview's cards.
	var g8_plain = RichText.text_label("Iron")
	var g8_rich = RichText.text_label("[item=iron-plate] Iron", "FHeading")
	var g8_split: Array = RichText.icon_and_text("[item=iron-plate] Iron [virtual-signal=signal-A]")
	check(g8_plain is Label and g8_rich is RichTextLabel and (g8_rich as RichTextLabel).get_parsed_text().contains("Iron")
		and not (g8_rich as RichTextLabel).get_parsed_text().contains("[item") and g8_split[0] != null and str(g8_split[1]).begins_with("Iron [") and not str(g8_split[1]).contains("item="),
		"names with rich text icons get a label that draws them; one icon and plain text where only one fits: %s" % [g8_split])
	g8_plain.free()
	g8_rich.free()
	gui.call("stop", {"p": 17, "col": [242, 0, 0], "stop": {"name": "[item=iron-plate] Iron", "limit": 2, "count": 1, "pri": 50, "train": 0, "trs": []}})
	await get_tree().process_frame
	var g8_stop = screen.find_child("StopName", true, false)
	check(g8_stop is RichTextLabel and (g8_stop as RichTextLabel).get_parsed_text().strip_edges() == "Iron",
		"a train stop's name draws its icon: %s" % [g8_stop])
	gui.call("train", {"p": 14, "col": [242, 120, 0], "inv": {"fuel": []}, "slots": {"fuel": [0, 0, 0]}, "bu": 500,
		"tr": {"id": 1, "state": "on_the_path", "manual": 0, "station": "", "dest": "", "name": "", "stops": ["[item=copper-plate] Copper", "Iron"],
			"sched": {"current": 1, "group": "[item=coal] Coal run", "records": [{"station": "[item=copper-plate] Copper", "wait_conditions": []}]}}})
	await get_tree().process_frame
	var g8_station = screen.find_child("Station1", true, false)
	var g8_group = screen.find_child("TrainName", true, false)
	var g8_add := screen.find_child("AddStation", true, false) as MenuButton
	check(g8_station is RichTextLabel and (g8_station as RichTextLabel).get_parsed_text().strip_edges() == "Copper" and g8_group is RichTextLabel
		and g8_add != null and g8_add.get_popup().get_item_text(0) == "Copper" and g8_add.get_popup().get_item_icon(0) != null
		and g8_add.get_popup().get_item_text(1) == "Iron",
		"a schedule's station, the train group and + Add station's list draw their icons")
	var g8_card: Button = ui.trains_window._station_card("[item=iron-plate] Iron", 2)
	check(g8_card.text == "Iron\n2 trains" and g8_card.icon == RichText.icon("item", "iron-plate"),
		"the train overview's station card shows the name's icon: %s" % g8_card.text)
	g8_card.free()
	# Cargo wagon: only its cargo and the red X.
	gui.call("train", {"p": 15, "inv": {"cargo": [["iron-plate", 50]]}, "slots": {"cargo": [["iron-plate", 50], 0, 0, 0]}, "bar": 4,
		"tr": {"id": 1, "state": "on_the_path", "manual": 0, "station": "", "dest": "Iron", "sched": {"current": 1, "group": "", "records": []}}})
	await get_tree().process_frame
	check(screen.shows_inventory() and screen.find_child("Schedule", true, false) == null and _find_slot_tip(screen, "Limit") != null,
		"a cargo wagon shows its cargo and the limit button, not the train's schedule")
	_find_slot_tip(screen, "Limit").clicked.emit(MOUSE_BUTTON_RIGHT, false)
	check(sent_one("set_bar").get("n") == 4, "right click on the red X: no limit on the wagon")
	# Car: fuel and its bar, the gun over its ammo slot, the trunk.
	gui.call("vehicle", {"p": 20, "inv": {"fuel": [["coal", 5]], "trunk": [], "car_ammo": []}, "slots": {"fuel": [["coal", 5]], "car_ammo": [0],
		"trunk": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}, "guns": ["vehicle-machine-gun"], "bu": 800})
	await get_tree().process_frame
	var guns = screen.find_child("Guns", true, false)
	check(guns != null and guns.get_child(0).get_child(0).item == "vehicle-machine-gun" and _texts(screen).has("Trunk") and screen.find_child("BurnerBar", true, false) != null,
		"a car: fuel with its bar, the gun over its ammo, the trunk")
	# Gun turret: the ammo row and target priorities; roboport rows.
	gui.call("turret", {"p": 22, "inv": {"turret_ammo": []}, "slots": {"turret_ammo": [0]}, "tgt": {"l": [], "ign": 0}})
	await get_tree().process_frame
	check(screen.find_child("Slots_turret_ammo", true, false) != null and _texts(screen).has("Target priorities"), "a turret: its ammo row and target priorities")
	gui.call("roboport", {"p": 23, "inv": {"robots": [], "repair": []}, "slots": {"robots": [0, 0, 0, 0, 0, 0, 0], "repair": [0, 0, 0, 0, 0, 0, 0]}})
	await get_tree().process_frame
	check(screen.find_child("Slots_robots", true, false) != null and screen.find_child("Slots_repair", true, false) != null
		and not _texts(screen).has("Robots"), "a roboport: two rows of slots without headings")
	# Storage tank: its fluid row.
	gui.call("other", {"p": 16, "fb": [["crude-oil", 12500, 25000, 25]]})
	await get_tree().process_frame
	check(_texts(screen).has("50%") and _texts(screen).has("12500 of 25000"), "a storage tank: fill in percent and its contents")
	# A pole opens the electric network statistics instead of a window.
	var opened: Array = []
	var old_stats: Callable = screen.open_stats
	screen.open_stats = func(kind: String, target: Dictionary) -> void: opened.append([kind, target])
	gui.call("pole", {"p": 24})
	await get_tree().process_frame
	check(opened.size() == 1 and opened[0][0] == "electric" and not screen.is_open(), "a pole opens Factorio's electric network info")
	screen.open_stats = old_stats
	screen.request(900, {"t": "open", "u": 900, "p": 1, "x": 0, "y": 0})
	sent()


## Owner's play-test icons (#13 books' and blueprints' icons, #24 technologies). The index is
## checked always; the pictures only with a Factorio install (they're never in the repo).
func _icons(hud: Hud) -> void:
	var ui = hud.ui
	var m = ui.model
	m.handle({"t": "slots", "l": {"main": [["blueprint-book", 1], ["blueprint", 1], ["iron-plate", 10], 0, 0, 0, 0, 0, 0, 0]},
		"ic": [[1, [["item", "iron-plate"], ["virtual", "signal-A"]]], [2, [["item", "transport-belt"]]]]})
	check(m.main_slots[0].get("icons") == [["item", "iron-plate"], ["virtual", "signal-A"]] and not m.main_slots[2].has("icons"),
		"slots' ic gives a book its icons, and nothing else any")
	ui.toggle_inventory()
	await get_tree().process_frame
	var book_slot: Slot = ui.window._grid.get_child(0)
	var plate_slot: Slot = ui.window._grid.get_child(2)
	check(book_slot.item == "blueprint-book" and book_slot.record_icons.size() == 2 and plate_slot.record_icons.is_empty(),
		"the inventory's book slot draws its two icons over the book")
	ui.close_all()
	var bar: Array = []
	bar.resize(100)
	bar.fill("")
	bar[0] = "blueprint-book"
	m.handle({"t": "qb", "p": 1, "sel": 0, "held": "", "l": bar})
	await get_tree().process_frame
	ui.quickbar.refresh()
	var pinned: Slot = ui.quickbar._slots[0]
	check(pinned.item == "blueprint-book" and pinned.record_icons.size() == 2, "a book pinned to the quickbar shows its icons too: %s" % [pinned.record_icons])
	bar[0] = ""
	m.handle({"t": "qb", "p": 1, "sel": 0, "held": "", "l": bar})
	m.handle({"t": "slots", "l": {"main": [["blueprint-book", 1], 0, 0, 0, 0, 0, 0, 0, 0, 0]}})
	check(not m.main_slots[0].has("icons"), "icons cleared again without ic")
	# A filter inserter's Alt-mode icon shows every filter, shrunk to fit the one icon's room.
	m.handle({"t": "ai", "l": [[901, "item", "iron-plate", ["copper-plate", "coal", "stone", "wood"]], [902, "recipe", "iron-gear-wheel"]]})
	check(m.alt_icons[901] == ["item", "iron-plate", "copper-plate", "coal", "stone", "wood"] and m.alt_icons[902] == ["recipe", "iron-gear-wheel"],
		"ai's extra filters are kept: %s" % [m.alt_icons.get(901)])
	var fits := true
	for n in range(1, 6):
		var cells: Array = AltOverlay.grid(n)
		var rects: Array[Rect2] = []
		for c in cells:
			rects.append(Rect2(c[0], Vector2(c[1], c[1])))
		for i in rects.size():
			fits = fits and Rect2(0, 0, 1, 1).grow(0.0001).encloses(rects[i])
			for j in range(i + 1, rects.size()):
				fits = fits and rects[i].intersection(rects[j]).get_area() < 0.0001
	check(fits and AltOverlay.grid(1)[0][1] == 1.0 and AltOverlay.grid(2)[0][1] == 0.5 and AltOverlay.grid(5)[0][1] == 1.0 / 3.0,
		"1 to 5 filters fit in the icon's square without overlapping (one alone keeps the full size)")
	# In first person the icons are 3D quads with the depth test on, so buildings hide them.
	var holder := Node3D.new()
	add_child(holder)
	var w3 := WorldMirror.new()
	holder.add_child(w3)
	w3.protos.add_entities([[8, "assembling-machine-1", "assembling-machine", -1.5, -1.5, 1.5, 1.5, 150, 150, 150, 3, 3]])
	w3.chunks[Vector2i.ZERO] = ChunkView.new()
	w3._add([950, 8, 5 * 256 + 128, 5 * 256 + 128, 0])
	var fp_gs := GDScript.new()
	fp_gs.source_code = "extends Node3D\nvar world\nvar rig\nvar camera: Camera3D\nvar first_person := true\n"
	fp_gs.reload()
	var fp_rig: Node3D = fp_gs.new()
	fp_rig.camera = Camera3D.new()
	fp_rig.add_child(fp_rig.camera)
	holder.add_child(fp_rig)
	var fp_player: Node3D = fp_gs.new()
	fp_player.world = w3
	fp_player.rig = fp_rig
	var overlay := AltOverlay.new()
	overlay.model = m
	overlay.player = fp_player
	overlay.on = true
	add_child(overlay)
	m.handle({"t": "ai", "l": [[950, "item", "iron-plate", ["coal"]]]})
	overlay._draw()
	var shown_quads := overlay._quads.filter(func(q): return q.visible)
	check(shown_quads.size() == 2 and (shown_quads[0].material_override as ShaderMaterial).shader == load("res://shaders/billboard_icon_depth.gdshader")
		and shown_quads[0].position.y > 1.0, "first person: Alt-mode icons are depth-tested quads over the building")
	fp_rig.first_person = false
	overlay._quads_used = 0
	overlay._hide_quads()
	overlay.on = false
	overlay._process(0.0)
	check(overlay._quads.all(func(q): return not q.visible), "and none are left in the world once Alt-mode is off")
	overlay.queue_free()
	holder.queue_free()
	m.handle({"t": "ai", "l": []})
	var techs: Dictionary = ItemIcons.index().get("technology", {})
	check(techs.size() > 250 and techs.has("recycling") and techs.has("planet-discovery-vulcanus") and techs.has("follower-robot-count-1"),
		"icons.json has every technology's icon, those technology.lua doesn't name too: %d" % techs.size())
	check((techs.get("physical-projectile-damage-1", []) as Array).size() == 2, "a bonus technology's icon is its picture and the badge")
	# Copper wires between poles ride with the chart and are drawn with the electric layer.
	m.handle({"t": "chart", "cx": 0, "cy": 0, "n": 1, "pal": [[20, 220, 40]], "px": [0],
		"ov": [["e", 5 * 256, 5 * 256, 2.5], ["w", 5 * 256, 5 * 256, 12 * 256, 5 * 256]]})
	var wire_entries: Array = (m.map_overlays.get(Vector2i(0, 0), []) as Array).filter(func(r): return str(r[0]) == "w")
	check(wire_entries.size() == 1 and is_equal_approx(float(wire_entries[0][3]), 12.0) and is_equal_approx(float(wire_entries[0][4]), 5.0),
		"a chart's copper wire keeps both ends, in tiles: %s" % [wire_entries])
	ui.map_view.layers.redraw(Vector2(8, 5), 8.0)
	await get_tree().process_frame
	# The minimap preloads what the map view shows on opening, once in a while, when idle.
	var mm = ui.minimap
	var mcache = ui.map_cache
	mcache._blocks.clear()
	mcache._pending.clear()
	mm._preloading = false
	mm._preloaded_at = -1e9
	var own := Rect2i(-1, -1, 3, 3)
	mm._ask(own, 4, Vector2.ZERO)
	var big: Rect2i = mcache._goal
	var preloading_now: bool = mm._preloading
	mcache._blocks.clear()
	mcache._pending.clear()
	mm._ask(own, 4, Vector2.ZERO)
	mm._ask(own, 4, Vector2.ZERO)
	var half_view: Vector2 = mm.get_viewport_rect().size / 2.0 / (mm.PRELOAD_ZOOM * Kit.scale)
	var expected: Rect2i = MapCache.chunks_of(Rect2(-half_view, half_view * 2.0))
	check(preloading_now and big == expected and not mm._preloading and mcache._goal == own,
		"the minimap asks once for the map view's opening area, then for its own again: %s then %s" % [big, mcache._goal])
	mm._ask(own, 4, Vector2.ZERO)
	check(not mm._preloading, "and not again until PRELOAD_EVERY has passed")
	mcache._blocks.clear()
	mcache._pending.clear()
	mcache.spots.clear()
	mcache.spots.append(Rect2i(40, 40, 3, 3))
	mm._ask(own, 4, Vector2.ZERO)
	check(mcache._goal == Rect2i(40, 40, 3, 3) and mcache.spots.is_empty(), "a train card's spot is charted by the minimap when idle")
	mcache._blocks.clear()
	mcache._pending.clear()
	mm._ask(own, 4, Vector2.ZERO)
	mm._ask(own, 4, Vector2.ZERO)
	# Demolisher territories' borders, from `terr` in two parts: two chunks side by side have six
	# outer sides (the shared one isn't a border); a lone chunk four.
	m.handle({"t": "terr", "part": 1, "parts": 2, "l": [[1, 2, 2, 2]]})
	var after_first: int = m.territory_edges.size()
	m.handle({"t": "terr", "part": 2, "parts": 2, "l": [[-5, 0]]})
	check(after_first == 0 and m.territory_edges.size() == 20 and m.territory_edges.has(Vector2(32, 64)),
		"terr parts make the territories' borders, in tiles: %d points" % m.territory_edges.size())
	var terr_layer := TerritoryLayer.new()
	terr_layer.model = m
	add_child(terr_layer)
	check(terr_layer.mesh != null and terr_layer.mesh.get_surface_count() == 1, "the borders are drawn on the ground in the world")
	# The map view stripes the territories' ground, on the surface they are on only.
	check(m.territory_chunks.size() == 3 and m.territories_shown(), "terr keeps the territories' chunks for the map's stripes")
	var stripe_area := 0.0
	var tarea := Rect2(32, 64, 32, 32)
	var speriod := MapLayersScript.stripe_period(1.0)
	var sk := floorf(96.0 / speriod) * speriod
	while sk < 96.0 + 64.0:
		var sband := MapLayersScript.stripe_band(tarea, sk, sk + speriod / 2.0)
		for vi in sband.size():
			var sa := sband[vi]
			var sb := sband[(vi + 1) % sband.size()]
			stripe_area += (sa.x * sb.y - sb.x * sa.y) / 2.0
		sk += speriod
	check(absf(stripe_area - 512.0) < 0.5 and speriod * 1.0 >= MapLayersScript.STRIPE_PX * 2.0 and MapLayersScript.stripe_period(0.1) > speriod,
		"the stripes cover half of each territory chunk, wider in tiles when zoomed out: %.1f of 1024, speriod %d" % [stripe_area, speriod])
	m.handle({"t": "terr", "part": 1, "parts": 1, "si": 7, "l": [[1, 2]]})
	check(not m.territories_shown(), "territories on another surface aren't drawn on this map")
	var tl := MapLayersScript.new()
	tl.model = m
	tl.size = Vector2(400, 300)
	add_child(tl)
	m.handle({"t": "terr", "part": 1, "parts": 1, "si": m.shown_surface(), "l": [[1, 2]]})
	tl.redraw(Vector2(48, 80), 4.0)
	await get_tree().process_frame
	check(m.territories_shown(), "the world's own surface's territories are drawn")
	tl.queue_free()
	m.handle({"t": "terr", "part": 1, "parts": 1, "l": []})
	check(m.territory_edges.is_empty() and terr_layer.mesh == null and m.territory_chunks.is_empty(), "an empty terr clears them")
	terr_layer.queue_free()
	# Demolishers (`seg`): the head, segments and tail drawn with their models at their prototypes'
	# scales, gliding to where the mod puts them, the head led ahead of the segment behind it.
	var dprotos := ProtoDB.new()
	dprotos.add_entities([[1, "small-demolisher", "segmented-unit", -1.5, -1.5, 1.5, 1.5, 90, 60, 50, 3, 3],
		[2, "small-demolisher-segment-x0_68", "segment", -2, -0.7, 2, 0.7, 90, 60, 50, 4, 1],
		[3, "small-demolisher-tail-x0_32", "segment", -1, -1, 1, 1, 90, 60, 50, 2, 2]])
	var dem := DemolisherLayer.new()
	dem.model = m
	dem.protos = dprotos
	add_child(dem)
	m.handle({"t": "seg", "l": [[90000, 1, [1, 0, 0, 0, 2, 0, 512, 0, 3, 0, 1280, 0]]]})
	dem._process(0.0)
	dem._process(1.0)
	var dparts: Array = dem.parts_of(90000)
	check(dem.count() == 1 and dparts.size() == 3 and dparts[0][0] == "demolisher-head" and dparts[1][0] == "demolisher-segment"
		and dparts[2][0] == "demolisher-tail" and (dparts[0][1] as Vector3).z < -0.5 and is_equal_approx((dparts[2][1] as Vector3).z, 5.0),
		"a demolisher's head, segment and tail are drawn where seg puts them, the head led ahead: %s" % [dparts])
	m.handle({"t": "seg", "l": [[90000, 1, [1, 0, 2560, 0, 2, 0, 3072, 0, 3, 0, 3840, 0]]]})
	dem._process(0.0)
	dem._process(1.0 / 60.0)
	var mid: float = (dem.parts_of(90000)[2][1] as Vector3).z
	check(mid > 5.0 and mid < 15.0, "its parts glide to their next places (the tail between 5 and 15: %.2f)" % mid)
	dem._process(DemolisherLayer.STALE + 1.0)
	check(dem.count() == 0, "without seg for a while the demolishers are taken away")
	dem.queue_free()
	# Pentapods: a stomper's five legs, each an upper and a lower part, bent to where the mod's
	# feet stand (vehicle_anim.gd, Factorio's leg table for the stomper).
	var vanim := VehicleAnim.new()
	vanim.model = m
	add_child(vanim)
	var sprotos := ProtoDB.new()
	sprotos.add_entities([[4, "big-stomper-pentapod", "spider-unit", -4, -4, 4, 4, 160, 120, 60, 8, 8]])
	var smov := MoverLayer.new()
	smov.protos = sprotos
	var snode: Node3D = smov._make_node(sprotos.entity(4))
	add_child(snode)
	vanim.attach(4000, snode, "big-stomper-pentapod")
	var srig = vanim._rigs.get(4000)
	check(srig != null and srig.kind == "spider" and srig.legs.size() == 5 and is_equal_approx(srig.knee_at, 0.55),
		"a stomper is rigged on its five legs with its own knee: %s" % [srig.legs.size() if srig != null else -1])
	var feet := []
	for i in 5:
		var g: Vector2 = (VehicleAnim.STOMPER_LEGS[i][1] as Vector2) * 0.8
		feet += [int(g.x * 256), int(g.y * 256)]
	m.handle({"t": "legs", "l": [[4000, feet]]})
	vanim._on_planet_data()
	for i in 8:  # within FEET_STALE, while the mod's feet count
		vanim._process(0.05)
	var reached := true
	if srig != null:
		for i in srig.legs.size():
			var want: Vector2 = (VehicleAnim.STOMPER_LEGS[i][1] as Vector2) * 0.8
			reached = reached and Vector2(srig.legs[i].foot.x, srig.legs[i].foot.z).distance_to(want) < 0.1
	check(srig != null and reached, "its feet step to where the mod's feet stand")
	snode.queue_free()
	smov.free()
	vanim.queue_free()
	# Pollution from the charts, a map view switch, tinted stronger where there is more.
	m.handle({"t": "chart", "cx": 2, "cy": 0, "n": 1, "pal": [[20, 220, 40]], "px": [0], "pol": 900})
	check(m.map_pollution.get(Vector2i(2, 0)) == 900 and UiSettings.MAP_LAYERS.any(func(l): return l[0] == "map/show_pollution")
		and MapLayersScript.pollution_alpha(9000.0) > MapLayersScript.pollution_alpha(90.0) and MapLayersScript.pollution_alpha(0.0) == 0.0,
		"a chart's pollution is kept and the map's Pollution switch tints it, more for more")
	m.handle({"t": "chart", "cx": 2, "cy": 0, "n": 1, "pal": [[20, 220, 40]], "px": [0]})
	check(not m.map_pollution.has(Vector2i(2, 0)), "and a chart without pol clears it")
	# Recipe icons, robots, signals and stops on the map are drawn over the coverage areas.
	for layers in [ui.map_view.layers, ui.minimap._layers]:
		check(layers.get_child(layers.get_child_count() - 1) == layers.marks and not layers.has_method("_draw"),
			"the map's markers draw last, over the electric, logistic and turret areas")
	# Trains on the map: asked for while a map is open, at most once a second, kept per surface.
	sent()
	var was_ready: bool = Bridge.world_ready
	Bridge.world_ready = true
	m._map_trains_asked = -1000000
	m.ask_map_trains()
	m.ask_map_trains()
	Bridge.world_ready = was_ready
	await get_tree().process_frame
	var train_asks := sent().filter(func(c): return c.get("t", "") == "mtr")
	check(train_asks.size() == 1, "a map asks for the trains on it (mtr), at most once a second: %s" % [train_asks])
	var here: int = m.shown_surface()
	m.handle({"t": "mtr", "si": here, "part": 1, "parts": 2, "l": [256, 512, 250, 1485, 460, 0xEB1200]})
	var after_part: int = m.map_trains.size()
	m.handle({"t": "mtr", "si": here, "part": 2, "parts": 2, "l": [2048, 512, 250, 1485, 460, 0x9A9A9A]})
	m.handle({"t": "mtr", "si": here + 7, "part": 1, "parts": 1, "l": []})
	check(after_part == 0 and m.map_trains.size() == 12 and m.map_trains[6] == 2048,
		"mtr parts make the map's trains, and another surface's don't replace them")
	ui.map_view.layers.redraw(Vector2.ZERO, 4.0)
	await get_tree().process_frame
	m.handle({"t": "mtr", "si": here, "part": 1, "parts": 1, "l": {}})
	check(m.map_trains.is_empty(), "an empty mtr clears the map's trains")
	# What radars cover (cov): the rest of the charted map is dimmed, except round the character.
	m.handle({"t": "mtr", "si": here, "part": 1, "parts": 1, "l": [], "cov": [20, 0, 3]})
	check(m.map_coverage_known and m.chunk_covered(Vector2i(22, 3), Vector2.ZERO) and not m.chunk_covered(Vector2i(24, 0), Vector2.ZERO)
		and m.chunk_covered(Vector2i(1, 1), Vector2.ZERO) and not m.chunk_covered(Vector2i(10, 0), Vector2.ZERO),
		"cov: a radar's square of chunks and the ground round the character count as seen, the rest not")
	ui.map_view.layers.redraw(Vector2.ZERO, 0.5)
	await get_tree().process_frame
	m.handle({"t": "mtr", "si": here, "part": 1, "parts": 1, "l": [], "cov": []})
	# D3/D9: quality marks only in Alt-mode; quality marks and alert icons depth tested and cut out.
	var qm := QualityMarksScript.new()
	check(qm.alt_mode == false and QualityMarksScript.IconShader.resource_path.ends_with("billboard_icon_cut.gdshader")
		and AlertIconsScript.IconShader.resource_path.ends_with("billboard_icon_cut.gdshader")
		and ui.has_signal("alt_mode_changed"),
		"quality marks wait for Alt-mode; quality marks and alert icons are hidden behind buildings and don't flicker")
	qm.free()
	# Belts far away show an icon per lane (bfar), and the client asks for them (bfar r).
	var lanes := BeltLanesScript.new()
	add_child(lanes)
	check(lanes._materials.size() == 1, "lane icons' shader is set up at start-up, not with the first far belt (21 ms on a real base)")
	lanes.sync = true
	lanes.handle({"t": "bfar", "cx": 3, "cy": 1, "l": [100 * 256, 40 * 256, 4, 1, 2, 101 * 256, 40 * 256, 4, 0, 2]})
	var lane_icons: int = lanes.icons_in(Vector2i(3, 1))
	# A chunk's lanes that arrive before the chunk itself is loaded are drawn once it is: the mod
	# sends them only when they change, so a steady belt stayed bare (owner's screenshots).
	var lane_world := WorldMirror.new()
	var lanes_late := BeltLanesScript.new()
	lanes_late.world = lane_world
	add_child(lanes_late)
	lanes_late.handle({"t": "bfar", "cx": 5, "cy": 2, "l": [170 * 256, 70 * 256, 4, 1, 2]})
	for i in 10:
		await get_tree().process_frame
	var lanes_early: int = lanes_late.icons_in(Vector2i(5, 2))
	var lanes_late_cv := ChunkView.new()
	lane_world.chunks[Vector2i(5, 2)] = lanes_late_cv
	lane_world.entities_changed.emit(Vector2i(5, 2))
	var lanes_until := Time.get_ticks_msec() + 3000
	while lanes_late.icons_in(Vector2i(5, 2)) == 0 and Time.get_ticks_msec() < lanes_until:
		await get_tree().process_frame
	check(lanes_early == 0 and lanes_late.icons_in(Vector2i(5, 2)) == 2,
		"far belt icons sent before their chunk loaded are drawn when it arrives (%d, then %d)" % [lanes_early, lanes_late.icons_in(Vector2i(5, 2))])
	lanes_late.queue_free()
	lanes_late_cv.free()
	lane_world.free()
	lanes.handle({"t": "bfar", "cx": 3, "cy": 1, "l": []})
	check(lane_icons == 3 and lanes.icons_in(Vector2i(3, 1)) == 0 and Settings.get_value("graphics", "belt_far_distance") != null,
		"bfar: an icon per lane carrying something, an empty list clears the chunk, with a distance setting")
	# A lane is drawn with as many icons as it holds, spread along the belt, neighbours a step apart.
	var dense: Dictionary = BeltLanesScript.Job.build([100 * 256, 40 * 256, 4, 1, 2, 101 * 256, 40 * 256, 4, 0, 2], [4, 4, 0, 2], 0.2)
	var dense_xs: Array = []
	var dense_buf: PackedFloat32Array = dense.get(1, PackedFloat32Array())
	for j in dense_buf.size() / 12:
		dense_xs.append(snappedf(dense_buf[j * 12 + 3], 0.001))
	check(BeltLanesScript.Job.icon_count(dense) == 10 and dense_xs == [99.625, 99.875, 100.125, 100.375]
		and dense_buf.size() >= 24 and dense_buf[7] != dense_buf[19],
		"bfar c: a full lane is four icons along its belt (an east belt's along x), every other one a step higher: %s" % [dense_xs])
	lanes.near = 48
	check(int(Settings.DEFAULTS["graphics"]["belt_near_distance"]) == 24 and is_equal_approx(lanes.near_edge(), 46.0),
		"Belt items in full: 24 tiles by default, and lane icons start just inside whatever it is set to")
	# Lane icons start where the items drawn now were read (bi fx, fy, fr), not round the camera,
	# which runs ahead while panning; at any Belt items in full distance.
	lanes.focus = Vector2(300, 0)
	lanes.covered = Vector3(200, 10, 64)
	var handover_ok := lanes.hand_over_centre() == Vector2(200, 10) and is_equal_approx(lanes.near_edge(), 62.0)
	lanes.covered = Vector3(0, 0, -1)
	check(handover_ok and lanes.hand_over_centre() == Vector2(300, 0) and is_equal_approx(lanes.near_edge(), 46.0),
		"lane icons hand over at the square belt items cover, else round the focus")
	# The worker path: messages wait for a job, chunks are made within the frame budget.
	lanes.sync = false
	lanes.handle({"t": "bfar", "cx": 4, "cy": 1, "l": [130 * 256, 40 * 256, 0, 1, 2], "c": [4, 3]})
	lanes.handle({"t": "bfar", "cx": 4, "cy": 1, "l": [130 * 256, 40 * 256, 0, 1, 2], "c": [2, 3]})
	var until_lanes := Time.get_ticks_msec() + 5000
	while lanes.waiting() > 0 and Time.get_ticks_msec() < until_lanes:
		lanes._process(0.016)
		await get_tree().process_frame
	check(lanes.icons_in(Vector2i(4, 1)) == 5, "bfar on a worker thread: the newest message for a chunk wins (%d icons)" % lanes.icons_in(Vector2i(4, 1)))
	# An icon not loaded yet is loaded on a worker thread too (a tinted one took 30 ms), its chunk waiting.
	var lane_protos := ProtoDB.new()
	lane_protos.add_items([[7, "zenith-test-lane-item"]])
	lanes.protos = lane_protos
	var icon_was_cached: bool = BeltLanesScript.ItemIcons.is_cached("zenith-test-lane-item")
	lanes.handle({"t": "bfar", "cx": 5, "cy": 1, "l": [160 * 256, 40 * 256, 0, 7, 0], "c": [2, 0]})
	until_lanes = Time.get_ticks_msec() + 5000
	while lanes.waiting() > 0 and Time.get_ticks_msec() < until_lanes:
		lanes._process(0.016)
		await get_tree().process_frame
	check(not icon_was_cached and lanes.icons_in(Vector2i(5, 1)) == 2 and BeltLanesScript.ItemIcons.is_cached("zenith-test-lane-item")
		and lanes._icon_task < 0, "bfar: a new item's icon is loaded on a worker and cached, then its chunk is drawn")
	lanes.queue_free()
	# An update drops at once the items outside the square it covers (lane icons take over there).
	var sq_items = BeltItemsScript.new()
	add_child(sq_items)
	sq_items._sync = true
	sq_items.handle({"t": "bi", "k": 600, "fx": 0, "fy": 0, "fr": 24, "l": [1, 1, -10 * 256, 0, 2, 1, 20 * 256, 0]})
	sq_items._process(0.016)
	sq_items.handle({"t": "bi", "k": 606, "fx": 30 * 256, "fy": 0, "fr": 24, "l": [2, 1, 20 * 256, 0]})
	sq_items._process(0.016)
	check(sq_items.count() == 1 and sq_items.covered() == Vector3(30, 0, 24),
		"belt items: an item outside the new update's square goes at once, and the square is known: %d, %s" % [sq_items.count(), sq_items.covered()])
	sq_items.queue_free()
	# Items on a real server's belts were thought invisible: a full loop of plain iron plates far from
	# the map's origin (busy_base.py --big), sent as differences with the square round the character.
	# Each one must land in its kind's drawn instances, where it was sent, above the belt model's top.
	var belt_top := 0.0
	var belt_mesh: Mesh = ModelLibrary.mesh_for("transport-belt")
	if belt_mesh != null:
		belt_top = belt_mesh.get_aabb().end.y
	var far_items = BeltItemsScript.new()
	add_child(far_items)
	far_items._sync = true
	var far_list := []
	var far_prev := [0, 0, 0, 0]
	for n in 40:
		var row := [5000 + n, 1, int((-48.5 + n * 0.25) * 256), int((56.5 + (0.25 if n % 2 == 0 else -0.25)) * 256)]
		for k in 4:
			far_list.append(row[k] - far_prev[k])
		far_prev = row
	far_items.handle({"t": "bi", "k": 900, "z": 1, "fx": int(-40.0 * 256), "fy": int(55.0 * 256), "fr": 24, "l": far_list})
	for f in 3:  # the kind's look is made after the first job, its slots written by the next
		far_items._process(0.016)
		far_items.handle({"t": "bi", "k": 906 + f * 6, "z": 1, "fx": int(-40.0 * 256), "fy": int(55.0 * 256), "fr": 24, "l": far_list})
	far_items._process(0.016)
	var far_mmi: MultiMeshInstance3D = far_items._cards._kinds.get(1)
	var far_ok := far_mmi != null and far_mmi.multimesh.visible_instance_count == 40
	if far_ok:
		var fb: PackedFloat32Array = far_mmi.multimesh.buffer
		for n in 40:
			var o := n * BeltItemsScript.STRIDE
			var want := Vector2(-48.5 + n * 0.25, 56.5 + (0.25 if n % 2 == 0 else -0.25))
			if Vector2(fb[o + 3], fb[o + 11]).distance_to(want) > 0.01 or fb[o + 7] <= belt_top or fb[o] == 0.0:
				far_ok = false
	check(far_ok and far_items.count() == 40, "belt items far from the origin, as a real server sends them, are all drawn where sent and above the belt (%d tracked, top %.3f)" % [far_items.count(), belt_top])
	far_items.queue_free()
	# Factorio's table_to_json writes a float that isn't finite as a bare inf or nan: such a message
	# (4 in a 30-minute session on a real busy base) was dropped whole. It is read, those as numbers.
	var bad_before := int(Bridge.stats.get("bad_json", 0))
	var not_finite = Bridge.parse('{"t":"zz","l":[1,inf,-inf,nan],"o":{"a":inf},"s":"inferno, nan"}')
	var fine = Bridge.parse('{"t":"zz","l":[1,2]}')
	check(not_finite is Dictionary and (not_finite["l"] as Array).map(func(v) -> float: return float(v)) == [1.0, 1e18, -1e18, 0.0] and float(not_finite["o"]["a"]) == 1e18
		and not_finite["s"] == "inferno, nan" and fine is Dictionary and Bridge.parse("{nope") == null
		and int(Bridge.stats.get("bad_json", 0)) == bad_before + 1,
		"a message with inf or nan is read with finite numbers, not dropped (%s)" % [not_finite])
	# With the renderer on its own thread a texture's upload happens there, later: the map's pages and
	# the remote fog's mask are drawn into again meanwhile, so each upload must get its own copy (the
	# render thread read an empty image in texture_2d_update on the real base).
	var page_cache = MapCache.new(UiModel.new())
	var page: Array = page_cache._page(Vector2i.ZERO)
	page_cache._dirty[Vector2i.ZERO] = true
	page_cache.flush()
	var uploaded: Image = (page[1] as ImageTexture).get_image()
	(page[0] as Image).set_pixel(0, 0, Color.RED)
	page_cache._dirty[Vector2i.ZERO] = true
	page_cache.flush()
	var fog_script := FileAccess.get_file_as_string("res://scripts/world/remote_fog.gd")
	check(page[1] != null and (uploaded == null or not is_same(uploaded, page[0])) and fog_script.count("_texture.update(_image)") == 0,
		"map pages and the fog mask upload a copy of their image, not the one drawn into next")
	# A model asked for during play is read on a worker thread, never on the main thread: the export's
	# ModelLibrary.slowest said "parsed here" for the inserter arms' pieces (2-4 ms each, first arm seen).
	var arm_names := ["inserter-arm-bulk-upper", "inserter-arm-bulk-hand-open", "inserter-arm-bulk-hand-closed"]
	for n in arm_names:
		ModelLibrary._cache.erase(n)
		ModelLibrary._jobs.erase(n)
		ModelLibrary._job_order.erase(n)
	var arms_layer: Node3D = preload("res://scripts/world/inserter_arms.gd").new()
	add_child(arms_layer)
	var slow_before := ModelLibrary.slowest.size()
	var arms_first = arms_layer._pieces_for("bulk-inserter")
	var arms_queued := arm_names.all(func(n: String) -> bool: return ModelLibrary._jobs.has(n))
	var until_arms := Time.get_ticks_msec() + 10000
	while arms_layer._pieces_for("bulk-inserter") == null and Time.get_ticks_msec() < until_arms:
		ModelLibrary.poll()
		await get_tree().process_frame
	var parsed_here := ModelLibrary.slowest.slice(slow_before).filter(func(r: Array) -> bool: return r.size() > 4 and r[4] == "parsed here")
	check(arms_first == null and arms_queued and arms_layer._pieces_for("bulk-inserter") != null and parsed_here.is_empty(),
		"inserter arm pieces wait for their models, read on worker threads (%s)" % [parsed_here])
	arms_layer.queue_free()
	# D1/D4: flat things that overlap never share a height: decoratives by Factorio's render layer
	# (then a step per tile), items on belts a step apart by id.
	var lifts: Dictionary = DecorativeLayer.LAYER_LIFT
	check(lifts["decals"] < lifts["ground-layer-1"] and lifts["ground-layer-4"] < lifts["floor"] and lifts["floor"] < lifts["decorative"]
		and DecorativeLayer.TILE_STEP * DecorativeLayer.TILE_STEPS <= lifts["ground-layer-1"] - lifts["decals"],
		"flat decoratives lie in Factorio's layer order, steps within a layer never reaching the next")
	check(BeltItemsScript.LAYERS > 1 and BeltItemsScript.LAYER_STEP > 0.0, "items on belts sit a step apart by id, so overlapping cards don't flicker")
	# Belt items' updates are worked on a worker thread: the same items, buffers and glide as on the
	# main thread, an item missing from two updates goes, and nothing jumps when an update lands.
	var layers: Array = []
	for sync in [false, true]:
		var bil = BeltItemsScript.new()
		add_child(bil)
		bil._sync = sync
		var bil_list := []
		for n in 300:
			bil_list.append_array([1000 + n, 1 + n % 3, (n % 30) * 256 + 128, (n / 30) * 256 + 64])
		bil.handle({"t": "bi", "k": 600, "l": bil_list})
		var until_job := Time.get_ticks_msec() + 5000
		while (bil._task >= 0 or not bil._inbox.is_empty() or bil.count() == 0) and Time.get_ticks_msec() < until_job:
			await get_tree().process_frame
		bil.position_of(1005)
		var moved := []
		for n in 299:  # item 1299 is missing from this update and the next
			moved.append_array([1000 + n, 1 + n % 3, (n % 30) * 256 + 128 + 64, (n / 30) * 256 + 64])
		bil.handle({"t": "bi", "k": 612, "l": moved})
		until_job = Time.get_ticks_msec() + 5000
		while (bil._task >= 0 or not bil._inbox.is_empty() or bil._rewrite) and Time.get_ticks_msec() < until_job:
			await get_tree().process_frame
		layers.append([bil.count(), bil.position_of(1005), bil._cards.kind_count(), bil._positions.get(1005)])
		for k in [624, 636]:  # gone when the third update after it was last seen begins, as before
			bil.handle({"t": "bi", "k": k, "l": moved})
		until_job = Time.get_ticks_msec() + 5000
		while (bil._task >= 0 or not bil._inbox.is_empty()) and Time.get_ticks_msec() < until_job:
			await get_tree().process_frame
		layers.append(bil.count())
		bil.queue_free()
	check(layers[0][0] == 300 and layers[1] == 299 and layers[0][2] == 3, "belt items on a worker thread: 300 tracked in 3 kinds, the one missing from updates goes (%s)" % [layers])
	check(layers[0][3] != null and layers[2][3] != null and (layers[0][3][0] as Vector3).is_equal_approx(layers[2][3][0])
		and (layers[0][3][1] as Vector3).is_equal_approx(layers[2][3][1]) and layers[0][0] == layers[2][0] and layers[3] == 299,
		"and the worker and the main thread put an item in the same place (%s)" % [layers])
	# The glide is folded where the item will be drawn: right after an update lands it continues
	# from where it was, a quarter tile from its old spot towards its new one at most.
	var glide_at = layers[0][1]
	check(glide_at != null and (glide_at as Vector3).x >= 5.5 - 0.01 and (glide_at as Vector3).x <= 5.75 + 0.01,
		"an item continues its glide across an update (x %s between 5.5 and 5.75)" % [glide_at])
	# Ground clutter is drawn around the character (the rig's target), not the camera.
	var decor := DecorativeLayer.new()
	var follow := Node3D.new()
	add_child(decor)
	add_child(follow)
	follow.global_position = Vector3(500, 0, 500)
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nvar target: Node3D\n"
	gs.reload()
	var rig_node: Node3D = gs.new()
	rig_node.target = follow
	rig_node.global_position = Vector3(0, 60, 0)  # the camera far from the character
	add_child(rig_node)
	decor.rig = rig_node
	for c in [Vector2i(15, 15), Vector2i(19, 15), Vector2i(20, 15), Vector2i(22, 15), Vector2i(0, 0)]:
		var n := Node3D.new()
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = MultiMesh.new()
		inst.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		inst.multimesh.instance_count = 100
		n.add_child(inst)
		decor.add_child(n)
		decor._chunks[c] = n
	decor._cull()
	var drawn := func(c: Vector2i) -> int: return (decor._chunks[c].get_child(0) as MultiMeshInstance3D).multimesh.visible_instance_count
	check(decor._chunks[Vector2i(15, 15)].visible and decor._chunks[Vector2i(19, 15)].visible and not decor._chunks[Vector2i(0, 0)].visible,
		"clutter shows around the character and not around the camera")
	check(drawn.call(Vector2i(15, 15)) == 100 and drawn.call(Vector2i(19, 15)) == 50 and drawn.call(Vector2i(20, 15)) == 25
		and not decor._chunks[Vector2i(22, 15)].visible,
		"clutter thins with distance (all, half, a quarter) out to 192 tiles")
	for n in [decor, follow, rig_node]:
		n.queue_free()
	# A robot sent every 2 ticks, the messages arriving unevenly (two at once, then a gap),
	# moves the same distance every frame instead of lurching and stalling.
	var bots := MoverLayer.new()
	var bot_protos := ProtoDB.new()
	bot_protos.add_entities([[5, "logistic-robot", "logistic-robot", -0.2, -0.2, 0.2, 0.2, 1, 1, 1, 1, 1]])
	bots.protos = bot_protos
	add_child(bots)
	var xs: Array[float] = []
	var sent_tick := 0
	for frame in 120:
		# Messages for ticks up to this frame, delivered in bursts every 4 frames.
		if frame % 4 == 0:
			while sent_tick <= frame:
				bots.handle({"t": "mv", "k": sent_tick, "l": [[901, 5, roundi(sent_tick * 0.1 * 256), 0]]})
				sent_tick += 2
		bots._process(1.0 / 60.0)
		xs.append((bots.position_of(901) as Vector3).x)
	var steps: Array[float] = []
	for i in range(30, xs.size()):
		steps.append(xs[i] - xs[i - 1])
	var lo: float = steps.min()
	var hi: float = steps.max()
	check(lo > 0.07 and hi < 0.13, "a robot moves steadily between uneven updates: %.3f to %.3f tiles a frame at 0.1 a tick" % [lo, hi])
	# A busy save runs the server slower than 60 UPS: here 40, a message every 3 frames. The client's
	# clock follows the game's measured rate, so the robot still moves the same distance every frame
	# instead of running ahead, waiting and lurching on.
	var slow := MoverLayer.new()
	slow.protos = bot_protos
	add_child(slow)
	var sx: Array[float] = []
	var game_tick := 0.0
	var slow_sent := 0
	for frame in 300:
		game_tick += 40.0 / 60.0
		while slow_sent <= game_tick:
			slow.handle({"t": "mv", "k": slow_sent, "l": [[904, 5, roundi(slow_sent * 0.1 * 256), 0]]})
			slow_sent += 2
		slow._process(1.0 / 60.0)
		sx.append((slow.position_of(904) as Vector3).x)
	var slow_steps: Array[float] = []
	for i in range(150, sx.size()):
		slow_steps.append(sx[i] - sx[i - 1])
	var slow_lo: float = slow_steps.min()
	var slow_hi: float = slow_steps.max()
	check(slow_lo > 0.055 and slow_hi < 0.08 and absf(slow.clock.rate - 40.0) < 3.0,
		"at 40 UPS a robot still moves steadily: %.3f to %.3f tiles a frame (0.067 expected), clock at %.1f ticks a second"
		% [slow_lo, slow_hi, slow.clock.rate])
	slow.queue_free()
	# F1: Factorio reports a flying robot's position about every 20 ticks, a tile at a time
	# (2.1.23), while it draws it gliding at 0.05 tiles a tick. Sent every 2 ticks, the position
	# repeats nine times and then jumps: the robot must still glide, not hop a tile at a time.
	var coarse := MoverLayer.new()
	coarse.protos = bot_protos
	add_child(coarse)
	var cx: Array[float] = []
	for frame in 400:
		if frame % 2 == 0:
			var k := frame
			coarse.handle({"t": "mv", "k": k, "l": [[905, 5, (k / 20) * 256, 0]]})
		coarse._process(1.0 / 60.0)
		cx.append((coarse.position_of(905) as Vector3).x)
	var coarse_steps: Array[float] = []
	for i in range(200, cx.size()):
		coarse_steps.append(cx[i] - cx[i - 1])
	var coarse_lo: float = coarse_steps.min()
	var coarse_hi: float = coarse_steps.max()
	check(coarse_lo > 0.03 and coarse_hi < 0.07,
		"a robot whose position Factorio moves a tile every 20 ticks glides: %.3f to %.3f tiles a frame (0.05)" % [coarse_lo, coarse_hi])
	coarse.queue_free()
	_update_rates()
	_robot_swarm()
	_gpu_movers()
	bots.handle({"t": "mv", "k": sent_tick, "l": [[901, 5, 500 * 256, 0]]})
	bots._process(1.0 / 60.0)
	check((bots.position_of(901) as Vector3).x > 400.0, "a long jump is a teleport, not a slow glide")
	# Locomotives carry two headlights that come on at night, as Factorio's front_light.
	bot_protos.add_entities([[6, "locomotive", "locomotive", -1.0, -3.0, 1.0, 3.0, 1, 1, 1, 2, 6]])
	bots.handle({"t": "mv", "k": sent_tick + 1, "l": [[903, 6, 0, 10 * 256, 0]]})
	var loco = bots._movers[903]
	bots.set_night(0.0)
	var dark_by_day: bool = loco.headlights.size() == 2 and not loco.headlights[0].visible
	bots.set_night(1.0)
	check(dark_by_day and loco.headlights[0].visible and loco.headlights[0].light_energy > 1.0 and loco.headlights[1].position.z < -2.0,
		"a locomotive's two headlights at its nose, on at night only")
	bots.set_night(0.0)
	# A train appears facing its way instead of swinging round from north.
	bots.handle({"t": "mv", "k": sent_tick + 2, "l": [[902, 5, 0, 0, 250]]})
	check(is_equal_approx(bots.yaw_of(902), Visuals.orientation_yaw(0.25)), "a new mover appears facing its orientation")
	bots.queue_free()
	# No instant boarding of a platform in orbit, and no list of them on a planet either (owner).
	var pp := PlatformPanel.new()
	add_child(pp)
	pp.handle({"on": 0, "here": "nauvis", "dest": [], "l": [{"i": 2, "n": "Orbiter", "loc": "nauvis", "st": "paused"}]})
	check(not pp.visible and not _texts(pp).has("Board") and not _texts(pp).has("Orbiter"),
		"on a planet the platform panel stays hidden: no platforms-over list, no Board button")
	pp.handle({"on": 2, "dest": ["nauvis"], "l": [{"i": 2, "n": "Orbiter", "st": "waiting_at_station", "loc": "nauvis", "sp": 0.0, "pa": 0}]})
	sent()
	var drop := pp.find_child("Drop", true, false) as Button
	if drop != null:
		drop.pressed.emit()
	var to_nauvis := pp.find_child("DropTo_nauvis", true, false) as Button
	if to_nauvis != null:
		to_nauvis.pressed.emit()
	check(pp.visible and drop != null and drop.is_visible_in_tree() and to_nauvis != null and sent_one("land").get("t") == "land",
		"on board over Nauvis, Drop to a planet and Nauvis ride a cargo pod down at once (land), not the old instant drop")
	pp.queue_free()
	# Zooming the map in past its closest level drops into Factorio's angle there, and back out.
	var cam_holder := Node3D.new()
	add_child(cam_holder)
	var cam_rig := CameraRig.new()
	cam_holder.add_child(cam_rig)
	var walker := Node3D.new()
	cam_holder.add_child(walker)
	cam_rig.target = walker
	var view_gs := GDScript.new()
	view_gs.source_code = "extends Node\nvar rig\nvar avatar\n"
	view_gs.reload()
	var viewer: Node = view_gs.new()
	viewer.rig = cam_rig
	viewer.avatar = walker
	var player_was = ui.player
	ui.player = viewer
	ui._zoom_into_world(Vector2(40, 12))
	var dropped: bool = ui.remote and cam_rig.in_factorio_view() and cam_rig.orthographic
	ui.end_remote_view()
	check(dropped and not cam_rig.in_factorio_view() and not cam_rig.orthographic and cam_rig.target == walker,
		"zooming the map in drops into the world at Factorio's angle, leaving puts the camera back")
	# The projection is a setting (Settings > Camera), no longer the O key; Factorio's view stays
	# orthographic and leaving it returns to the setting.
	var ortho_was = Settings.get_value("camera", "orthographic")
	Settings.set_value("camera", "orthographic", true)
	cam_rig.apply_settings()
	var set_ortho := cam_rig.orthographic
	cam_rig.toggle_factorio_view()
	Settings.set_value("camera", "orthographic", false)
	cam_rig.apply_settings()
	var f6_ortho := cam_rig.orthographic
	cam_rig.toggle_factorio_view()
	check(set_ortho and f6_ortho and not cam_rig.orthographic and not Controls.LIST.any(func(a: Array) -> bool: return a[0] == "toggle_ortho"),
		"Projection setting: orthographic when chosen, F6 always orthographic, back to the setting after; no O key")
	Settings.set_value("camera", "orthographic", ortho_was)
	cam_rig.apply_settings()
	# Owner's H17: the map's remote view has a projection of its own, and F7 switches the one in use.
	var map_ortho_was = Settings.get_value("camera", "map_orthographic")
	Settings.set_value("camera", "map_orthographic", false)
	Settings.set_value("camera", "orthographic", false)
	cam_rig.apply_settings()
	ui._zoom_into_world(Vector2(40, 12))
	cam_rig._process(0.0)
	var map_persp: bool = cam_rig.camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	var h17_map_said: String = cam_rig.toggle_projection()
	cam_rig._process(0.0)
	var map_f7: bool = cam_rig.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and bool(Settings.get_value("camera", "map_orthographic"))
	ui.end_remote_view()
	cam_rig._process(0.0)
	var normal_back: bool = not cam_rig.in_remote and cam_rig.camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	var h17_normal_said: String = cam_rig.toggle_projection()
	var normal_f7: bool = cam_rig.orthographic and bool(Settings.get_value("camera", "orthographic"))
	cam_rig.toggle_projection()
	check(map_persp and map_f7 and h17_map_said.begins_with("Map view") and normal_back and normal_f7 and h17_normal_said.begins_with("Normal view")
		and Controls.LIST.any(func(a: Array) -> bool: return a[0] == "toggle_projection" and a[2] == [KEY_F7]),
		"H17: the map's view keeps its own projection, F7 switches the one in use (map, then normal) and saves it")
	Settings.set_value("camera", "map_orthographic", map_ortho_was)
	Settings.set_value("camera", "orthographic", ortho_was)
	cam_rig.apply_settings()
	# Owner's H19: Settings > Camera > Furthest zoom sets how far the wheel zooms out.
	var max_zoom_was = Settings.get_value("camera", "max_zoom")
	var zoom_goal_was: float = cam_rig._distance_goal
	Settings.set_value("camera", "max_zoom", 300)
	cam_rig.apply_settings()
	cam_rig.zoom(100.0)
	var far_goal: float = cam_rig._distance_goal
	Settings.set_value("camera", "max_zoom", 60)
	cam_rig.apply_settings()
	var near_goal: float = cam_rig._distance_goal
	cam_rig.zoom(100.0)
	check(is_equal_approx(far_goal, 300.0) and is_equal_approx(near_goal, 60.0) and is_equal_approx(cam_rig._distance_goal, 60.0),
		"H19: the furthest zoom follows its setting (300 lets the wheel out to 300, 60 pulls the view in): %.0f, %.0f" % [far_goal, near_goal])
	Settings.set_value("camera", "max_zoom", max_zoom_was)
	cam_rig.apply_settings()
	cam_rig._distance_goal = zoom_goal_was
	# F6 snaps to Factorio's view on every press unless the view is exactly Factorio's.
	# Zoomed, turned or tilted there (the wheel, a nudge of the middle mouse), a press went back to
	# the view before instead, so it took another to get Factorio's view.
	cam_rig.pitch_degrees = 60.0
	cam_rig.zoom(1.0)
	var before_f6: float = cam_rig._distance_goal
	cam_rig.toggle_factorio_view()
	var snapped: Array = [cam_rig._yaw_goal, cam_rig.pitch_degrees, cam_rig._distance_goal]
	var f6_ok := true
	for nudge in ["zoom", "turn", "tilt"]:
		match nudge:
			"zoom": cam_rig.zoom(1.25)
			"turn": cam_rig.rotate_free(3.0)
			"tilt": cam_rig.tilt(-2.0)
		cam_rig.toggle_factorio_view()
		f6_ok = f6_ok and cam_rig.in_factorio_view() and [cam_rig._yaw_goal, cam_rig.pitch_degrees, cam_rig._distance_goal] == snapped
	cam_rig.toggle_factorio_view()
	check(f6_ok and not cam_rig.in_factorio_view() and cam_rig.pitch_degrees == 60.0 and cam_rig._distance_goal == before_f6,
		"F6 after zooming, turning or tilting Factorio's view snaps back to it at once; once more goes back to the view before")
	cam_rig.first_person = true
	cam_rig.toggle_factorio_view()
	var from_fp: bool = cam_rig.in_factorio_view() and not cam_rig.first_person
	cam_rig.toggle_factorio_view()
	check(from_fp, "F6 in first person leaves it for Factorio's view")
	cam_rig.toggle_factorio_view()
	cam_rig.zoom(1.3)
	ui._zoom_into_world(Vector2(40, 12))
	ui.end_remote_view()
	check(not cam_rig.in_factorio_view() and cam_rig._saved_view.is_empty() and cam_rig.pitch_degrees == 60.0,
		"leaving the map's remote view goes back to the view before Factorio's, even zoomed in it")
	# H8: in a platform's hub (a remote view with no character to go back to) M opens the map.
	var hub_was: Vector2 = ui.hub_at
	var remote_was: bool = ui.remote
	ui.hub_at = Vector2(3, 4)
	ui.remote = true
	ui.open_map(true)
	var hub_map_open: bool = ui.map_open()
	ui.open_map(false)
	ui.hub_at = hub_was
	ui.remote = remote_was
	check(hub_map_open, "M opens the map while the character sits in a platform's hub, travelling or not (H8)")
	# Zooming into another surface's map asks the mod to stream that surface (view), and leaving
	# the remote view goes back to the character's.
	sent()
	var other_si: int = ui.model.character_si + 5
	ui.model.map_si = other_si
	ui._zoom_into_world(Vector2(8, 9))
	var view_ask := sent_one("view")
	var viewing_was: int = ui.viewing_si
	ui.end_remote_view()
	var view_back := sent_one("view")
	check(view_ask.get("si") == other_si and view_ask.get("x") == 8 * 256 and viewing_was == other_si
		and view_back.get("si") == 0 and ui.viewing_si == 0,
		"zooming into another surface's map views that surface, and leaving goes back: %s %s" % [view_ask, view_back])
	ui.model.map_si = 0
	await _check_ride(cam_rig, viewer, ui)
	ui.player = player_was
	viewer.free()
	cam_holder.queue_free()
	# The character's own position, sent every 2 ticks and arriving unevenly, moves evenly, so
	# the run cycle steps evenly too (exoskeleton speed: 0.3 tiles a tick).
	var runner := Avatar.new()
	add_child(runner)
	var rx: Array[float] = []
	var rtick := 0
	for frame in 150:  # the clock measures the game's rate over its first half second
		if frame % 4 == 0:
			while rtick <= frame:
				runner.update_from({"t": "me", "k": rtick, "u": 1, "x": roundi(rtick * 0.3 * 256), "y": 0, "d": 4, "w": 1, "hp": 250, "q": 0})
				rtick += 2
		runner._process(1.0 / 60.0)
		rx.append(runner.position.x)
	var rsteps: Array[float] = []
	for i in range(60, rx.size()):
		rsteps.append(rx[i] - rx[i - 1])
	check(rsteps.min() > 0.27 and rsteps.max() < 0.33, "the character runs at an even speed between uneven updates: %.3f to %.3f a frame at 0.3" % [rsteps.min(), rsteps.max()])
	runner.queue_free()
	# On a busy save the server runs below 60 UPS (here 40, a `me` every 3 frames): the avatar's clock
	# follows the measured rate, so the character still runs evenly instead of lurching.
	var slow_runner := Avatar.new()
	add_child(slow_runner)
	var srx: Array[float] = []
	var s_game := 0.0
	var s_sent := 0
	for frame in 300:
		s_game += 40.0 / 60.0
		while s_sent <= s_game:
			slow_runner.update_from({"t": "me", "k": s_sent, "u": 1, "x": roundi(s_sent * 0.15 * 256), "y": 0, "d": 4, "w": 1, "hp": 250, "q": 0})
			s_sent += 2
		slow_runner._process(1.0 / 60.0)
		srx.append(slow_runner.position.x)
	var srsteps: Array[float] = []
	for i in range(150, srx.size()):
		srsteps.append(srx[i] - srx[i - 1])
	check(srsteps.min() > 0.085 and srsteps.max() < 0.115 and absf(slow_runner._clock.rate - 40.0) < 3.0,
		"at 40 UPS the character still runs evenly: %.3f to %.3f tiles a frame (0.100 expected), clock at %.1f ticks a second"
		% [srsteps.min(), srsteps.max(), slow_runner._clock.rate])
	slow_runner.queue_free()
	# Walking at 20 degrees the mod zig-zags between north and north-east (puppet.lua's
	# angle_step); the avatar is drawn straight along the line, facing it, at an even speed.
	var zig := Avatar.new()
	add_child(zig)
	var za := 56  # thousandths of a turn
	var zrad := za / 1000.0 * TAU
	var zline := Vector2(sin(zrad), -cos(zrad))
	var zpos := Vector2.ZERO
	var zerr := 0.0
	var ztick := 0
	var real_side := 0.0
	var drawn_side: Array[float] = []
	var drawn_along: Array[float] = []
	for frame in 150:
		if frame % 4 == 0:
			while ztick <= frame:
				for i in 2:
					var zlo := int(floor(za / 1000.0 * 8.0)) % 8
					var slo := sin(zlo / 8.0 * TAU - zrad)
					var shi := sin((zlo + 1) / 8.0 * TAU - zrad)
					var pick := zlo + 1 if absf(zerr + shi) < absf(zerr + slo) else zlo
					zerr += shi if pick != zlo else slo
					zpos += Vector2(sin(pick / 8.0 * TAU), -cos(pick / 8.0 * TAU)) * 0.15
				ztick += 2
				real_side = maxf(real_side, absf(zline.cross(zpos)))
				zig.update_from({"t": "me", "k": ztick, "u": 1, "x": roundi(zpos.x * 256), "y": roundi(zpos.y * 256), "d": 2, "w": 1, "a": za, "hp": 250, "q": 0})
		zig._process(1.0 / 60.0)
		var at := Vector2(zig.position.x, zig.position.z)
		drawn_side.append(zline.cross(at))
		drawn_along.append(zline.dot(at))
	var jitter := 0.0
	var zsteps: Array[float] = []
	for i in range(40, drawn_side.size()):
		jitter = maxf(jitter, absf(drawn_side[i] - drawn_side[i - 1]))
		zsteps.append(drawn_along[i] - drawn_along[i - 1])
	var face_off := absf(wrapf(zig.rotation.y + zrad, -PI, PI))
	check(real_side > 0.02 and jitter < 0.004 and zsteps.min() > 0.12 and zsteps.max() < 0.16 and face_off < 0.02,
		"walking at an angle is drawn straight along it: the real path strays %.3f tiles, the drawn one moves %.4f sideways a frame at most, %.3f to %.3f along, facing %.3f off"
		% [real_side, jitter, zsteps.min(), zsteps.max(), face_off])
	# Stopping, the drawn character comes back to where the real one is.
	for frame in 30:
		if frame % 2 == 0:
			ztick += 2
			zig.update_from({"t": "me", "k": ztick, "u": 1, "x": roundi(zpos.x * 256), "y": roundi(zpos.y * 256), "d": 2, "w": 0, "hp": 250, "q": 0})
		zig._process(1.0 / 60.0)
	check(Vector2(zig.position.x, zig.position.z).distance_to(zpos) < 0.01, "and on stopping it is drawn where the character really is")
	zig.queue_free()
	# The character's flashlight, a cone ahead of it at night.
	var me := Avatar.new()
	add_child(me)
	me.set_night(0.2)
	var off: bool = not me._flashlight.visible
	me.set_night(0.9)
	check(off and me._flashlight.visible and me._flashlight.light_energy > 1.0 and me._flashlight.rotation.x < 0.0,
		"the character's flashlight lights the ground ahead, from darkness 0.3 as in Factorio")
	# F7: the character's own body and tools cast no shadow from its lights (its head and arms
	# crossed the flashlight while running), and the facing, which the flashlight follows, keeps an
	# angled walk's line through a message without the angle and on stopping.
	var self_shadow := false
	var self_meshes := 0
	for node in me.find_children("*", "GeometryInstance3D", true, false):
		self_meshes += 1
		if (node as GeometryInstance3D).layers & me._flashlight.shadow_caster_mask or (node as GeometryInstance3D).layers & me._lantern.shadow_caster_mask:
			self_shadow = true
	check(self_meshes > 0 and not self_shadow and me._flashlight.shadow_enabled,
		"the character's lights cast no shadows of the character itself (F7): %d meshes" % self_meshes)
	var line_yaw := -56 / 1000.0 * TAU
	var yaws: Array[float] = []
	for msg in [{"k": 2, "d": 0, "w": 1, "a": 56}, {"k": 4, "d": 2, "w": 1}, {"k": 6, "d": 0, "w": 1, "a": 56},
			{"k": 8, "d": 2, "w": 0}, {"k": 10, "d": 0, "w": 0}]:
		me.update_from(msg.merged({"t": "me", "u": 1, "x": 0, "y": 0, "hp": 250, "q": 0}))
		yaws.append(absf(wrapf(me._yaw_goal - line_yaw, -PI, PI)))
	me.update_from({"t": "me", "k": 12, "u": 1, "x": 0, "y": 0, "d": 4, "w": 0, "hp": 250, "q": 0})
	var turned := absf(wrapf(me._yaw_goal - Visuals.direction_yaw(4), -PI, PI)) < 0.001
	me.update_from({"t": "me", "k": 14, "u": 1, "x": 0, "y": 0, "d": 0, "w": 1, "a": 56, "hp": 250, "q": 0})
	for k in range(16, 40, 2):  # then a walk with no angle: after ANGLE_HOLD ticks it faces its direction
		me.update_from({"t": "me", "k": k, "u": 1, "x": 0, "y": 0, "d": 0, "w": 1, "hp": 250, "q": 0})
	var plain := absf(wrapf(me._yaw_goal - Visuals.direction_yaw(0), -PI, PI)) < 0.001
	check(yaws.max() < 0.001 and turned and plain,
		"the character keeps facing an angled walk's line through the zig-zag's steps and stopping, and turns to a new direction (F7): %s" % [yaws])
	me.queue_free()
	# F8: the run cycle steps with the distance walked at Factorio's pace: 22 frames per
	# distance_per_frame 0.13 / animation_speed 0.6 tiles (the mech's 0.37).
	var legs := CharacterAnimScript.new()
	var legs_pose := CharacterPoseScript.new()
	var loops := 0.0
	for i in 100:
		var before: float = legs._run_phase
		legs.running = true
		legs.step(legs_pose, 1.0 / 60.0, 0.15)
		loops += fposmod(legs._run_phase - before, TAU) / TAU
	var per_loop := 15.0 / loops
	legs.mech = true
	var mech_before: float = legs._run_phase
	legs.step(legs_pose, 1.0 / 60.0, 1.0)
	var mech_per_loop := 1.0 / (fposmod(legs._run_phase - mech_before, TAU) / TAU)
	check(absf(per_loop - 4.767) < 0.01 and absf(mech_per_loop - 7.73) < 0.01,
		"the run cycle takes Factorio's 4.77 tiles a loop (7.73 in mech armour), not 2.86 (F8): %.3f, %.3f" % [per_loop, mech_per_loop])
	# F4: a travelling platform's sky has the planet it left only over the route's first 12% and
	# the next one only over the last; `d` is thousandths of the route.
	var MainSky = load("res://scripts/main.gd")
	var route := {"from": "nauvis", "to": "vulcanus", "len": 15000}
	var sky_at := func(d: int) -> Array: return MainSky.planet_in_sky(route.merged({"d": d}))
	var early: Array = sky_at.call(30)
	var middle: Array = sky_at.call(300)
	var middle2: Array = sky_at.call(700)
	var late: Array = sky_at.call(960)
	var stopped: Array = MainSky.planet_in_sky({"loc": "fulgora"})
	check(early[0] == "nauvis" and early[1] > 0.7 and middle[0] == "" and middle2[0] == "" and late[0] == "vulcanus"
		and late[1] > 0.6 and stopped[0] == "fulgora" and stopped[1] == 1.0,
		"a travelling platform shows the planet left, then none, then the next (F4): %s %s %s %s %s" % [early, middle, middle2, late, stopped])
	# F04: in mech armour the character is drawn as the mech (its own model and rig), and back.
	var mech := Avatar.new()
	add_child(mech)
	var plain_rig: Node = mech._rig
	var plain_top := mech._pose.head_of("head").y if mech._pose != null else 0.0
	mech.set_armor("light-armor")
	var kept: bool = mech._rig == plain_rig and not mech.is_mech() and mech.look == "character"
	# Armour looks: Factorio draws heavy and modular armour with its level 2 layer, power armour
	# with level 3, each on the character's own skeleton (so its bones stay where they were).
	var looks := []
	var same_bones := true
	for item in ["heavy-armor", "modular-armor", "power-armor", "power-armor-mk2", "light-armor"]:
		mech.set_armor(item)
		looks.append(mech.look)
		if mech._pose != null and absf(mech._pose.head_of("head").y - plain_top) > 0.001:
			same_bones = false
	check(looks == ["character-armor-2", "character-armor-2", "character-armor-3", "character-armor-3", "character"]
		and same_bones and mech._rig.get_parent() == mech and not mech.is_mech(),
		"each armour swaps the character to Factorio's look for it, on the same skeleton (N43): %s" % [looks])
	var others := Creatures.new()
	var other := Node3D.new()
	others.add(900, "character", other)
	var plain_node := Node3D.new()
	others.add(901, "character", plain_node)
	others.set_looks({900: Avatar.look_for("power-armor"), 902: Avatar.look_for("heavy-armor")})
	check(others.look_of(900) == "character-armor-3" and others.look_of(901) == "character"
		and Avatar.look_for("mech-armor") == "character-mech-armor" and Avatar.look_for("") == "character",
		"other players' characters wear their armour's look from `pl` (N43): %s, %s" % [others.look_of(900), others.look_of(901)])
	others.free()
	other.free()
	plain_node.free()
	# Dying enemies fall the way their corpse model lies (creature_poses.json, fitted to Factorio's
	# corpse sprites), every tier at its size, so the corpse that replaces them lies where they fell.
	var falls := Creatures.new()
	var fell := []
	for n in ["small-biter", "behemoth-biter", "medium-spitter", "big-spitter", "small-worm-turret", "big-worm-turret"]:
		var f := falls.fall_of(n)
		if f.is_empty():
			continue
		var d := Creatures.Dying.new()
		d.name = n
		d.seconds = 1.0
		d.age = 1.0
		var k: float = falls._scale_of(n)
		var end: Transform3D = falls._collapse(d)
		d.age = 0.0
		var start: Transform3D = falls._collapse(d)
		var at: Vector3 = f["at"] * k
		if (end * at).is_equal_approx(f["to"] * k) and (start * at).is_equal_approx(at):
			fell.append(n)
	falls.free()
	check(fell.size() == 6, "dying biters, spitters and worms fall into their corpses' poses, every tier: %s" % [fell])
	# Fights: corpses lie in one MultiMesh per model per 16-tile cell, bounded by it, built once
	# (not every frame), and live creatures' layers are bounded by where they are, so neither is
	# drawn out of view or in every shadow split (a 150-enemy wave: 1.7 -> 7.2 million triangles).
	var heap := Creatures.new()
	add_child(heap)
	var corpse_model := "small-biter-corpse"
	var wait_until := Time.get_ticks_msec() + 10000
	while not (ModelLibrary.ready(corpse_model) and ModelLibrary.ready("small-biter")) and Time.get_ticks_msec() < wait_until:
		ModelLibrary.poll()
		await get_tree().process_frame
	if ModelLibrary.mesh_for(corpse_model) != null:
		heap._add_corpse(corpse_model, Transform3D(Basis.IDENTITY, Vector3(5, 0, 5)))
		heap._add_corpse(corpse_model, Transform3D(Basis.IDENTITY, Vector3(6, 0, 7)))
		heap._add_corpse(corpse_model, Transform3D(Basis.IDENTITY, Vector3(300, 0, 5)))
		heap._process(0.016)
		var built: Array = heap._cells.values().map(func(c) -> bool: return c.dirty)
		var heap_walker := Node3D.new()
		heap_walker.position = Vector3(-40, 0, 10)
		heap.add(77, "small-biter", heap_walker)
		heap._process(0.016)
		heap._process(0.016)
		var corpse_boxes: Array = []
		var live_cells: Dictionary = heap._layers.get("small-biter", {})
		var live_layer: MultiMeshInstance3D = live_cells.values()[0].mmi if live_cells.size() == 1 else null
		var live_box := live_layer.custom_aabb if live_layer != null else AABB()
		for mmi: MultiMeshInstance3D in heap.find_children("*", "MultiMeshInstance3D", false, false):
			if mmi != live_layer and mmi.multimesh.visible_instance_count > 0 and mmi.multimesh.use_custom_data:
				corpse_boxes.append(mmi.custom_aabb)
		check(heap._cells.size() == 2 and corpse_boxes.size() == 2 and corpse_boxes.all(func(b: AABB) -> bool: return b.size.x <= 48.0)
			and built == [false, false] and live_box.has_point(Vector3(-40, 1, 10)) and live_box.size.x < 20.0,
			"corpses are drawn per 16-tile cell and built once, live creatures bounded by where they are: %s, %s %s" % [corpse_boxes, live_box, heap._layers.keys()])
		# A corpse joining a built cell is added to what it holds, not the cell built again.
		var first_cell = heap._cells.get(Vector2i(0, 0))
		var first_layer: MultiMeshInstance3D = first_cell.layers.get(corpse_model) if first_cell != null else null
		heap._add_corpse(corpse_model, Transform3D(Basis.IDENTITY, Vector3(7, 0, 6)))
		var queued: bool = first_cell != null and not first_cell.dirty and first_cell.pending.size() == 1
		heap._process(0.016)
		check(queued and first_layer != null and first_layer.multimesh.visible_instance_count == 3 and first_cell.pending.is_empty()
			and (first_cell.buffers[corpse_model] as PackedFloat32Array).size() == 48 and not first_cell.dirty,
			"a new corpse in a built cell is added to it, not the cell built again: %d drawn" % [first_layer.multimesh.visible_instance_count if first_layer != null else -1])
		# Creatures' view LODs come as a new mesh the layer swaps to: rebuilding the mesh in place
		# while it was drawn stalled the renderer 330-600 ms at a fight's first corpses.
		var source: Mesh = ModelLibrary.mesh_for("small-biter")
		var lod_until := Time.get_ticks_msec() + 15000
		while ModelLods.lod_copy(source) == null and Time.get_ticks_msec() < lod_until:
			ModelLods.poll()
			await get_tree().process_frame
		heap._process(0.016)
		var swapped: Mesh = live_layer.multimesh.mesh if live_layer != null else null
		check(ModelLods.lod_copy(source) != null and swapped == ModelLods.lod_copy(source) and swapped != source,
			"live creatures switch to a copy of their mesh with view LODs, the shared mesh left as it is")
		heap_walker.free()
	heap.free()
	mech.set_armor("mech-armor")
	var mech_top := mech._pose.head_of("head").y if mech._pose != null else 0.0
	var swapped: bool = mech.is_mech() and mech._rig != plain_rig and mech._rig.get_parent() == mech \
		and mech._anim.mech and mech_top > plain_top * 1.3
	mech.update_from({"t": "me", "u": 1, "x": 0, "y": 0, "d": 0, "w": 0, "hp": 250, "q": 0, "m": 50, "mx": 0, "my": 256})
	for i in 30:
		mech._process(1.0 / 60.0)
	var no_tools: bool = not mech._pickaxe.visible and not mech._gun.visible
	var muzzle := mech.muzzle_position()
	mech.set_armor("")
	check(kept and swapped and no_tools and muzzle.y > 1.3 and not mech.is_mech() and not mech._anim.mech,
		"mech armour draws the character as the mech, with no pickaxe or hand gun, and back (F04): head %.2f -> %.2f, muzzle %s"
		% [plain_top, mech_top, muzzle])
	mech.queue_free()
	var ents: Dictionary = ItemIcons.index().get("entity", {})
	check(ents.has("straight-rail") and ents.has("big-rock") and not ents.has("transport-belt"),
		"icons.json has the icons of entities no item is named after: %d" % ents.size())
	if ItemIcons.find_data_dir() == "":
		print("skip technology pictures: no Factorio install")
		return
	for e in ["straight-rail", "big-rock", "curved-rail-a"]:
		var tex := Kit.item_icon(e)
		check(tex != null and not Kit._swatches.has(e), "%s's tooltip shows its icon, not a coloured square" % e)
	# The planet below a platform is Factorio's own picture of it.
	var MainScript = load("res://scripts/main.gd")
	check(MainScript.planet_picture("nauvis") != null and MainScript.planet_picture("vulcanus") != null and MainScript.planet_picture("") == null,
		"the real planets' pictures for space's sky")
	# Their whole-surface maps for the sphere below the platform, read on a worker thread.
	var first_maps: Dictionary = MainScript.planet_maps_soon("vulcanus")
	var maps_until := Time.get_ticks_msec() + 10000
	while MainScript.planet_maps_soon("vulcanus").is_empty() and Time.get_ticks_msec() < maps_until:
		await get_tree().process_frame
	var vmaps: Dictionary = MainScript.planet_maps_soon("vulcanus")
	check(first_maps.is_empty() and vmaps.has("map") and vmaps.has("clouds") and vmaps.has("emission")
		and (vmaps["map"] as Texture2D).get_width() >= 2048 and MainScript.planet_maps_soon("space-location-x").is_empty(),
		"a planet's 2048-wide surface, cloud and glow maps load on a worker for the sphere below a platform")
	var near := func(x: float) -> float: return PlatformPanel.planet_nearness(x, 0.12)
	check(near.call(0.0) == 1.0 and near.call(0.06) > 0.4 and near.call(0.06) < 0.6 and near.call(0.5) == 0.0 and near.call(0.97) > 0.7,
		"while travelling, the planet left falls away and the next one comes near")
	var missing := []
	for t in techs:
		if GuiAssets.tech_icon(t) == null:
			missing.append(t)
	check(missing.is_empty(), "every technology has a picture (none falls back to the red science pack): %s" % [missing])
	var bonus := GuiAssets.tech_icon("physical-projectile-damage-1").get_image()
	bonus.decompress()
	check(bonus.get_size() == Vector2i(256, 256) and bonus.get_pixel(228, 228).a > 0.5,
		"the bonus badge is drawn in the bottom-right corner, 256 px as Factorio's tech icons: %s" % [bonus.get_pixel(228, 228)])


## Flying robots are drawn together, one MultiMesh per robot kind and part (robot_swarm.gd),
## with their animation (flying, cargo lamp, working, arms) in each instance's data, instead of a
## node and several MeshInstance3Ds each.
## A server under load slows the mod's costliest updates down (`rate`): movers and belt items then
## come two, four or eight times further apart, each message saying how far (`p`). They must still
## move the same distance every frame: no stall at the end of each gap, no jump at the next update,
## and no stop or step back when the spacing changes under way.
func _update_rates() -> void:
	var car_protos := ProtoDB.new()
	car_protos.add_entities([[8, "car", "car", -0.7, -1.0, 0.7, 1.0, 1, 1, 1, 1, 1]])
	# Movers: a car at 0.1 tiles a tick, sent every 2 ticks, then every 4 (rate 1) and every 16
	# (rate 3, quadrupled again), at 60 UPS and 60 frames a second. As the mod does (rate.lua), after
	# a slow-down they still come at the old rate for 120 ticks while already saying the new one.
	for spacing in [[2, 4], [4, 8], [2, 16]]:
		var cars := MoverLayer.new()
		cars.protos = car_protos
		add_child(cars)
		var xs: Array[float] = []
		var switch_frame := 120
		for frame in 480:
			var p: int = spacing[0] if frame < switch_frame else spacing[1]
			var every: int = spacing[0] if frame < switch_frame + 120 else spacing[1]
			if frame % every == 0:
				cars.handle({"t": "mv", "k": frame, "p": p, "l": [[950, 8, roundi(frame * 0.1 * 256), 0]]})
			cars._process(1.0 / 60.0)
			xs.append(cars._movers[950].node.position.x)
		var steady: Array[float] = []
		var during: Array[float] = []
		for i in range(60, xs.size()):
			var s := xs[i] - xs[i - 1]
			if i >= switch_frame + 180:
				steady.append(s)
			elif i >= switch_frame:
				during.append(s)
		check(steady.min() > 0.085 and steady.max() < 0.115,
			"movers every %d ticks (then %d) glide evenly: %.3f to %.3f tiles a frame (0.1)" % [spacing[0], spacing[1], steady.min(), steady.max()])
		check(during.min() > 0.03 and during.max() < 0.16,
			"and while the spacing goes from %d to %d ticks they slow a little but never stop or jump: %.3f to %.3f" % [spacing[0], spacing[1], during.min(), during.max()])
		cars.queue_free()
	# Belt items every 6 ticks (as normal), 12 (doubled), 24 (quadrupled) and 48 (rate 3 on a busy
	# base), a turbo belt's 0.125 tiles a tick: 6 tiles between the last two updates, which used to
	# count as being moved some other way and snap.
	for p in [6, 12, 24, 48]:
		var belt = BeltItemsScript.new()
		add_child(belt)
		belt._sync = true
		var bx: Array[float] = []
		for frame in 360:
			if frame % p == 0:
				belt.handle({"t": "bi", "k": 6000 + frame, "p": p, "l": [7001, 1, roundi((20.0 + frame * 0.125) * 256), 40 * 256]})
			belt._process(1.0 / 60.0)
			var at = belt.position_of(7001)
			bx.append((at as Vector3).x if at != null else NAN)
		var steps: Array[float] = []
		for i in range(p * 2 + 30, bx.size()):
			steps.append(bx[i] - bx[i - 1])
		var lo: float = steps.min()
		var hi: float = steps.max()
		check(lo > 0.1 and hi < 0.15,
			"belt items every %d ticks glide evenly: %.3f to %.3f tiles a frame (0.125)" % [p, lo, hi])
		belt.queue_free()
	# And across a change, as the mod does it (rate.lua): every 6 ticks, then (rate 3) saying 48
	# while still coming every 6 for 120 ticks as the client eases in, then every 48 on ticks of
	# their own. Items slow down meanwhile, but never stop or jump.
	var changing = BeltItemsScript.new()
	add_child(changing)
	changing._sync = true
	var cx: Array[float] = []
	for frame in 600:
		var said := 6 if frame < 120 else 48
		if (frame < 240 and frame % 6 == 0) or frame % 48 == 1:
			changing.handle({"t": "bi", "k": 6000 + frame, "p": said, "l": [7002, 1, roundi((20.0 + frame * 0.125) * 256), 40 * 256]})
		changing._process(1.0 / 60.0)
		var at = changing.position_of(7002)
		cx.append((at as Vector3).x if at != null else NAN)
	var csteps: Array[float] = []
	var csteady: Array[float] = []
	for i in range(30, cx.size()):
		csteps.append(cx[i] - cx[i - 1])
		if i >= 420:
			csteady.append(cx[i] - cx[i - 1])
	check(csteps.min() > 0.05 and csteps.max() < 0.15 and csteady.min() > 0.11 and csteady.max() < 0.14,
		"belt items slow a little but never stop or jump as their updates go from every 6 ticks to every 48: %.3f to %.3f tiles a frame, then %.3f to %.3f"
		% [csteps.min(), csteps.max(), csteady.min(), csteady.max()])
	changing.queue_free()
	# A slow server (40 UPS: a tick every 1.5 frames) with updates every 24 ticks: items glide at the
	# game's measured rate, not stopping at the end of each gap.
	var slow_belt = BeltItemsScript.new()
	add_child(slow_belt)
	slow_belt._sync = true
	var sbx: Array[float] = []
	var game_tick := 0.0
	var sent := 0
	for frame in 600:
		game_tick += 40.0 / 60.0
		while sent <= game_tick:
			slow_belt.handle({"t": "bi", "k": 9000 + sent, "p": 24, "l": [7003, 1, roundi((20.0 + sent * 0.125) * 256), 40 * 256]})
			sent += 24
		slow_belt._process(1.0 / 60.0)
		var sat = slow_belt.position_of(7003)
		sbx.append((sat as Vector3).x if sat != null else NAN)
	var sbsteps: Array[float] = []
	for i in range(300, sbx.size()):
		sbsteps.append(sbx[i] - sbx[i - 1])
	check(sbsteps.min() > 0.065 and sbsteps.max() < 0.1,
		"at 40 UPS belt items every 24 ticks still glide evenly: %.3f to %.3f tiles a frame (0.083)" % [sbsteps.min(), sbsteps.max()])
	slow_belt.queue_free()


## Movers drawn on the GPU (mover_records.gd): written only when a position arrives, a record put
## where the shader would draw it (records.position, the shader's code on the CPU) must match where
## movers.gd's old per-frame CPU code drew it (_drawn_at at the clock less the lag eased every frame),
## in every case the earlier glide checks cover: messages in bursts, Factorio's coarse robot
## positions, a 40 UPS server, its updates slowed down (`rate`); and the facing must ease the same.
func _gpu_movers() -> void:
	ModelLibrary.mesh_for("logistic-robot")
	var protos := ProtoDB.new()
	protos.add_entities([[5, "logistic-robot", "logistic-robot", -0.2, -0.2, 0.2, 0.2, 1, 1, 1, 1, 1]])
	# [name, frames, message for frame (or null), game ticks a frame]
	var cases := [
		["bursts", 240, func(f: int) -> Array: return range(f - 3 if f % 4 == 0 else f + 1, f + 1).filter(func(k: int) -> bool: return k >= 0 and k % 2 == 0), 1.0],
		["coarse", 400, func(f: int) -> Array: return [f] if f % 2 == 0 else [], 1.0],
		["40 UPS", 360, func(f: int) -> Array: return [roundi(f * 40.0 / 60.0)] if roundi(f * 40.0 / 60.0) % 2 == 0 and roundi(f * 40.0 / 60.0) != roundi((f - 1) * 40.0 / 60.0) else [], 40.0 / 60.0],
		["slowed", 480, func(f: int) -> Array: return [f] if (f < 180 and f % 2 == 0) or f % 8 == 0 else [], 1.0],
	]
	for case in cases:
		var layer := MoverLayer.new()
		layer.protos = protos
		add_child(layer)
		var worst := 0.0
		var worst_yaw := 0.0
		var cpu_lag := -1.0
		var cpu_yaw := 0.0
		var on_record := false
		# While its updates go from every 2 ticks to every 8 the clock is steered to the new spacing,
		# and the old code eased the lag by frames, the record by the clock: a little apart meanwhile,
		# but never stopping, stepping back or jumping.
		var easing := 0.0
		var steps: Array[float] = []
		var last_x := NAN
		for f in int(case[1]):
			for k: int in case[2].call(f):
				var x := 0.0
				var y := 0.0
				if case[0] == "coarse":
					x = floorf(k / 20.0)  # a tile every 20 ticks, as Factorio reports a flying robot
				else:
					x = k * 0.1
					y = 2.0 * sin(k * 0.02)  # a curve, so corners count
				var turn := roundi(fposmod(k * 0.002, 1.0) * 1000.0)
				var msg := {"t": "mv", "k": k, "l": [[910, 5, roundi(x * 256), roundi(y * 256), turn]]}
				if case[0] == "slowed" and f >= 180:
					msg["p"] = 8
				layer.handle(msg)
			layer._process(1.0 / 60.0)
			var m = layer._movers.get(910)
			if m == null or layer.clock.tick < 0.0:
				continue
			# movers.gd's old per-frame path for the same mover.
			var want := maxf(layer.clock.gap * MoverLayer.GameClock.DELAY_SENDS, m.key_gap + layer.clock.gap)
			cpu_lag = want if cpu_lag < 0.0 else move_toward(cpu_lag, want, 1.0 / 60.0 * layer.clock.rate * (0.5 if want > cpu_lag else 1.0))
			var cpu: Vector3 = MoverLayer._drawn_at(m, layer.clock.tick - cpu_lag)
			cpu_yaw = lerp_angle(cpu_yaw, m.yaw_goal, 1.0 - exp(-1.0 / 60.0 * MoverLayer.FOLLOW_RATE)) if f > 0 else m.yaw_goal
			on_record = m.slot >= 0
			if f >= 60:
				var gpu: Vector3 = layer.position_of(910)
				var apart := Vector2(gpu.x - cpu.x, gpu.z - cpu.z).length()
				if case[0] == "slowed" and f >= 180 and f < 330:
					easing = maxf(easing, apart)
				else:
					worst = maxf(worst, apart)
				worst_yaw = maxf(worst_yaw, absf(angle_difference(layer.yaw_of(910), cpu_yaw)))
				if not is_nan(last_x) and f >= 200:  # once the coarse robot's spacing is learnt (F1)
					steps.append(gpu.x - last_x)
				last_x = gpu.x
		check(on_record and worst < 0.02 and worst_yaw < 0.02 and easing < 0.1 and steps.min() > 0.02 and steps.max() < 0.16,
			"a robot drawn from its record is where the old CPU code drew it (%s): %.4f tiles (%.4f while its updates slow), %.4f radians at worst; %.3f to %.3f tiles a frame"
			% [case[0], worst, easing, worst_yaw, steps.min(), steps.max()])
		layer.queue_free()
	# The records' two clocks: a record written just before an epoch ends is drawn on through the
	# next one and, moved onto the newer clock, through the one after (float precision holds in a
	# long game).
	var rec = MoverLayer.MoverRecords.new()
	var rslot: int = rec.alloc()
	var e: float = MoverLayer.MoverRecords.EPOCH
	var rspots: Array[Vector3] = [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(2, 1, 0), Vector3(3, 1, 0)]
	var rticks: Array[float] = [2.0 * e - 20.0, 2.0 * e - 10.0, 2.0 * e, 2.0 * e + 10.0]
	rec.frame(2.0 * e - 15.0, 60.0, 0.016)
	rec.write(rslot, rspots, rticks, 0, 1.0, 3.0, 0.0, 2.0 * e - 15.0, 4.0, 2.0, 2.0, 2.0, 0.25, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	var off := 0.0
	for t in [2.0 * e - 15.0, 2.0 * e - 1.0, 2.0 * e + 1.0, 2.0 * e + 9.0, 3.0 * e - 2.0, 3.0 * e + 1.0, 4.0 * e + 5.0]:
		rec.frame(t, 60.0, 0.016)
		var expect := clampf((t - 4.0 - (2.0 * e - 20.0)) * 0.1, 0.0, 3.0)
		off = maxf(off, absf((rec.position(rslot) as Vector3).x - expect))
	check(off < 0.002, "a record is drawn where it should be across the clocks' epochs: %.4f tiles off at worst" % off)
	# Walking biters: their instances only point at their records (slot + 1 in the custom data's b,
	# a plain transform at their square's middle) and use the mover shader; an attack (`en`) poses
	# one here, its end gives it back to the shader, and one that dies falls from where it was drawn.
	ModelLibrary.mesh_for("small-biter")
	ModelLibrary.mesh_for("small-biter-corpse")
	var bprotos := ProtoDB.new()
	bprotos.add_entities([[9, "small-biter", "unit", -0.2, -0.2, 0.2, 0.2, 1, 1, 1, 1, 1]])
	var biters := MoverLayer.new()
	biters.protos = bprotos
	add_child(biters)
	var near := Node3D.new()  # the character, near: posed creatures are worked out every frame
	near.position = Vector3(45, 0, 15)
	biters.creatures.target = near
	for f in 60:
		if f % 2 == 0:
			biters.handle({"t": "mv", "k": f, "l": [[920, 9, roundi((40.0 + f * 0.1) * 256), roundi(10.0 * 256), 250],
				[921, 9, roundi(50.0 * 256), roundi(20.0 * 256), 0]]})
		biters._process(1.0 / 60.0)
		biters.creatures._process(1.0 / 60.0)
	var cr = biters.creatures
	var walker = cr._creatures.get(920)
	var layer = walker.walker if walker != null else null
	var custom := Color()
	var origin := Vector3.ZERO
	var shader_ok := false
	if layer != null:
		var b: PackedFloat32Array = layer.buffer
		var o: int = walker.index * 16
		custom = Color(b[o + 12], b[o + 13], b[o + 14], b[o + 15])
		origin = Vector3(b[o + 3], b[o + 7], b[o + 11])
		var mat := (layer.mmi.multimesh.mesh as Mesh).surface_get_material(0) as ShaderMaterial
		shader_ok = mat != null and mat.shader == preload("res://shaders/factorio_material_mover.gdshader")
	var biter_at = biters.position_of(920)
	check(walker != null and walker.slot >= 0 and int(custom.b) == walker.slot + 1 and origin.is_equal_approx(Vector3(48, 0, 16))
		and shader_ok and biter_at != null and (biter_at as Vector3).x > 40.5,
		"a walking biter's instance points at its record (b = slot + 1), set once at its square's middle, drawn with the mover shader: %s %s %s"
		% [custom, origin, biter_at])
	var st: Dictionary = biters.records.state(walker.slot) if walker != null else {}
	var g: Vector2 = biters.records.creature_gait(st) if not st.is_empty() else Vector2.ZERO
	check(not st.is_empty() and float(st["speed"]) > 5.0 and g.y > 0.99 and is_equal_approx(float(st["kind"].y), TAU / 2.0),
		"its record walks it at 6 tiles a second with full gait, a loop of legs every 2 tiles: %s" % [st.get("speed"), ])
	cr.handle_attacks({"l": [921, roundi(51.0 * 256), roundi(20.0 * 256)]})
	var posed: bool = cr._posed.has(921) and cr._creatures[921].walker == null
	for f in 60:
		cr._process(1.0 / 60.0)
	var back: bool = not cr._posed.has(921) and cr._creatures[921].walker != null
	var at_death: Vector3 = biters.position_of(920)
	biters.remove(920)
	var dying: Array = cr._dying
	near.free()
	check(posed and back and dying.size() == 1 and (dying[0].xform.origin as Vector3).distance_to(at_death) < 0.001,
		"an attacking biter is posed here, back on its record once the attack lapses; one that dies falls where it was drawn: %s %s %d"
		% [posed, back, dying.size()])
	biters.queue_free()


func _robot_swarm() -> void:
	for name in ["logistic-robot", "construction-robot", "defender"]:
		ModelLibrary.mesh_for(name)
	var layer := MoverLayer.new()
	var p := ProtoDB.new()
	p.add_entities([[5, "logistic-robot", "logistic-robot", -0.2, -0.2, 0.2, 0.2, 1, 1, 1, 1, 1],
		[6, "construction-robot", "construction-robot", -0.2, -0.2, 0.2, 0.2, 1, 1, 1, 1, 1],
		[7, "defender", "combat-robot", -0.2, -0.2, 0.2, 0.2, 1, 1, 1, 1, 1]])
	layer.protos = p
	add_child(layer)
	layer.vehicles.model = {"robot_cargo": {1000: {"item": 1, "count": 4}}}
	# 200 logistic robots flying east at 0.05 tiles a tick, 99 construction robots hovering, a defender.
	var records := func(k: int, logistic: int) -> Array:
		var l: Array = []
		for i in logistic:
			l.append([1000 + i, 5, roundi((i * 2 + k * 0.05) * 256), 0])
		for j in 99:
			l.append([2000 + j, 6, j * 256, 10 * 256])
		l.append([3000, 7, 0, 20 * 256])
		return l
	for frame in 90:
		if frame % 2 == 0:
			layer.handle({"t": "mv", "k": frame, "l": records.call(frame, 200)})
		layer._process(1.0 / 60.0)
	var swarm := layer.robots
	var meshes := 0
	var in_tree := 0
	for m in layer._movers.values():
		meshes += m.node.get_child_count()
		in_tree += 1 if m.node.is_inside_tree() else 0
	var parts := swarm.instances()
	check(layer.count() == 300 and swarm.count() == 300 and meshes == 0 and in_tree == 0 and parts.size() > 0 and parts.size() <= 20,
		"300 robots are drawn by %d MultiMeshes, not %d nodes of their own" % [parts.size(), in_tree])
	var shader_ok := true
	for mmi in parts:
		if mmi.material_override == null:
			var mat := mmi.multimesh.mesh.surface_get_material(0) as ShaderMaterial
			shader_ok = shader_ok and mat != null and mat.shader == preload("res://shaders/factorio_material_robot.gdshader")
	check(shader_ok, "robots' parts use the robot shader, their shadows the drop-shadow material")
	var at := func(unit: int) -> Array: return swarm.drawn(layer._movers[unit].bot)
	var flying: Array = at.call(1000)
	var empty: Array = at.call(1001)
	var hovering: Array = at.call(2000)
	var defender: Array = at.call(3000)
	var node_at: Vector3 = layer.position_of(1000)
	check(not flying.is_empty() and (flying[0] as Transform3D).origin.distance_to(node_at) < 0.001 and node_at.x > 0.5
		and (flying[1] as Color).r > 0.3 and int((flying[1] as Color).b) == 1 and int((empty[1] as Color).b) == 0,
		"a flying robot is drawn where it glides, its thrusters out, the cargo lamp lit only with cargo: %s %s" % [flying, empty])
	check(int((hovering[1] as Color).b) == 2 and (hovering[1] as Color).a > 0.3 and (hovering[1] as Color).r < 0.05
		and (defender[1] as Color).g == 0.0,
		"a construction robot hovering in place works with its arms out; a defender doesn't bob: %s %s" % [hovering, defender])
	check(layer.robot_near(node_at, 1.0) and not layer.robot_near(node_at + Vector3(0, 0, 300), 2.0),
		"robot_near finds the robots through its grid")
	# Half the logistic robots leave: the rest keep their own places after the slots are reused.
	for frame in range(90, 110):
		if frame % 2 == 0:
			layer.handle({"t": "mv", "k": frame, "l": records.call(frame, 100)})
		layer._process(1.0 / 60.0)
	var wrong := 0
	for unit in layer._movers:
		var d: Array = swarm.drawn(layer._movers[unit].bot)
		if d.is_empty() or (d[0] as Transform3D).origin.distance_to(layer.position_of(unit)) > 0.001:
			wrong += 1
	check(swarm.count() == 200 and layer.count() == 200 and wrong == 0,
		"robots that leave are dropped and the others drawn where they are: %d drawn, %d wrong" % [swarm.count(), wrong])
	layer.vehicles.model = null  # a stand-in: vehicle_anim.gd wants ui_model.gd's signals
	layer.queue_free()
