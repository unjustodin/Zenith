extends Node3D
## Builds the scene: lighting, the world mirror, movers, belt items, items on the ground,
## inserter arms, lamps, fluids and power, wires, ghosts, combat (health bars, deaths, shots), the player's avatar,
## the camera, the HUD and input, sound and effects (scripts/fx), and routes the bridge's messages to them.
## The sun and sky follow the game's time of day ("sky" messages): scripts/world/sky.gd draws each
## planet's sky, clouds and their shadows. On a space platform the
## backdrop is space (shaders/space_sky.gdshader), with the planet the platform is stopped at, and
## a panel shows the platform (scripts/ui/factorio/platform_panel.gd).
##
## The program starts in the menu (scripts/menu/front_end.gd: main menu, world selection, the
## server it launches, settings); the game's nodes are built by start_game() when a world is
## entered and freed by end_game() on the way back. Options that only make sense in a game
## (--factorio-port, --port, --open, --ui..., --camera..., --fx-demo, --no-menu) skip the menu and
## connect to 127.0.0.1:<--factorio-port, 34200> straight away, as before the menu existed.
##
## Command-line options (after `--`): --factorio-port=34200 --port=34201 --models=<dir> --addons=<dir>
## (scripts/addons/addon_loader.gd)
## --factorio-data=<Factorio's data folder, for item icons> --open=<unit> (player_input.gd)
## --review-shots=<dir>[@seconds] saves model review shots and quits (scripts/debug/review_shots.gd).
## --screenshot=<file.png>[@seconds] saves the window once, after that many seconds (default 10);
## with --clean-shot the HUD and the character are hidden first.
## --plat-board=<platform index>@<seconds> sends plat_board then (0: down to the planet), to try
## a surface change without clicking. --ride=<platform index>@<seconds> rides the rocket of the
## nearest silo up to that platform, and --land=<seconds> goes down from the hub, without clicking
## (scripts/world/ride.gd).
## Sound options (--volume, --sfx-volume, --music-volume, --mute, --sfx-log...): fx_settings.gd.
## Settings (user://settings.cfg) and the menu's own options: scripts/menu/settings.gd, front_end.gd.

const ModelLods := preload("res://scripts/world/model_lods.gd")
const WorldMirror := preload("res://scripts/world/world.gd")
const UpsGovernor := preload("res://scripts/world/ups_governor.gd")
const MoverLayer := preload("res://scripts/world/movers.gd")
const RemoteFog := preload("res://scripts/world/remote_fog.gd")
const BeltItemLayer := preload("res://scripts/world/belt_items.gd")
const BeltLaneLayer := preload("res://scripts/world/belt_lanes.gd")
const GroundItemLayer := preload("res://scripts/world/ground_items.gd")
const DecorativeLayer := preload("res://scripts/world/decoratives.gd")
const InserterArmLayer := preload("res://scripts/world/inserter_arms.gd")
const LampLayer := preload("res://scripts/world/lamp_lights.gd")
const FluidsPowerLayer := preload("res://scripts/world/fluids_power.gd")
const WireLayer := preload("res://scripts/world/wires.gd")
const GhostLayer := preload("res://scripts/world/ghosts.gd")
const CombatLayer := preload("res://scripts/world/combat.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const Avatar := preload("res://scripts/player/avatar.gd")
const CameraRig := preload("res://scripts/player/camera_rig.gd")
const PlayerInput := preload("res://scripts/player/player_input.gd")
const TallFade := preload("res://scripts/world/tall_fade.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")
const Fx := preload("res://scripts/fx/fx.gd")
const TurretLayer := preload("res://scripts/world/turrets.gd")
const ReviewShots := preload("res://scripts/debug/review_shots.gd")
const AnimShots := preload("res://scripts/debug/anim_shots.gd")
const WorkingGlow := preload("res://scripts/world/working_glow.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const FrontEnd := preload("res://scripts/menu/front_end.gd")
const RocketLayer := preload("res://scripts/world/rockets.gd")
const CollectorLayer := preload("res://scripts/world/collectors.gd")
const Ride := preload("res://scripts/world/ride.gd")
const GameSwap := preload("res://scripts/menu/game_swap.gd")
const TerritoryLayer := preload("res://scripts/world/territories.gd")
const DemolisherLayer := preload("res://scripts/world/demolishers.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const QualityMarks := preload("res://scripts/world/quality_marks.gd")
const SunShadows := preload("res://scripts/world/sun_shadows.gd")
const AddonHost := preload("res://scripts/addons/addon_host.gd")

## Options that start a game at once, without the menu.
const DIRECT_OPTIONS := ["--factorio-port=", "--port=", "--open=", "--ui=", "--ui-sample", "--ui-hold=",
	"--ui-craft=", "--ui-hover=", "--ui-press=", "--camera=", "--fx-demo", "--no-menu"]
const PlatformPanel := preload("res://scripts/ui/factorio/platform_panel.gd")
const PlayerTags := preload("res://scripts/world/player_tags.gd")
const PlanetSky := preload("res://scripts/world/sky.gd")
const VrSession := preload("res://scripts/vr/vr_session.gd")
const SPACE_SKY := preload("res://shaders/space_sky.gdshader")
## Roughly each planet's colour from orbit, for the space backdrop.
const PLANET_COLORS := {
	"nauvis": Color(0.26, 0.42, 0.52), "vulcanus": Color(0.62, 0.32, 0.16), "gleba": Color(0.42, 0.5, 0.28),
	"fulgora": Color(0.5, 0.38, 0.42), "aquilo": Color(0.62, 0.76, 0.86),
}

var world: WorldMirror
var movers: MoverLayer
var remote_fog: RemoteFog
var belt_items: BeltItemLayer
var belt_lanes: BeltLaneLayer
var ground_items: GroundItemLayer
var decoratives: DecorativeLayer
var arms: InserterArmLayer
var lamps: LampLayer
var fluids_power: FluidsPowerLayer
var wires: WireLayer
var ghosts: GhostLayer
var combat: CombatLayer
var avatar: Avatar
var rig: CameraRig
var hud: Hud
var input: PlayerInput
var fx: Fx
var turrets: TurretLayer
var front_end: FrontEnd
## Everything of a game, freed as one on the way back to the menu.
var _game: Node3D = null
var platform_panel: PlatformPanel
var player_tags: PlayerTags
## Night vision equipment's light, 0..1 (it turns on by itself when dark, as in Factorio).
var _night_vision := 0.0
## Rockets leaving, cargo pods landing, asteroid chunks (Space Age).
var rockets: RocketLayer
## Asteroid collectors' arms catching chunks.
var collectors: CollectorLayer
var demolishers: DemolisherLayer
## Riding a rocket up to a platform's hub, life in the hub, a cargo pod down.
var ride: Ride
var quality_marks: QualityMarks
## Holds the game at 60 UPS by asking the bridge for less while the game runs slow.
var ups_governor: UpsGovernor
## Add-ons, for the whole run (menus too).
var addons: AddonHost

var _status_timer := 0.0
var _packets_before := 0
## The game's updates per second for the debug line: server ticks per real second, smoothed.
var _tick_before := -1
var _ups := 0.0
var _headless := DisplayServer.get_name() == "headless"
var _log_timer := 0.0
var _env: Environment
var _sun: DirectionalLight3D
var sun_shadows: SunShadows
## Time of day as drawn, eased towards the latest "sky" message. Daytime 0 is noon.
var _daytime := 0.15
var _darkness := 0.0
var _sky_daytime := 0.15
var _sky_darkness := 0.0
## On a space platform: space instead of the planet's sky.
var _space := false
var _space_material: ShaderMaterial
var _planet_sky: PlanetSky
var _planet_sky_res: Sky
var _space_sky: Sky


func _ready() -> void:
	Settings.apply_startup(DisplayServer.window_get_size().y)
	Settings.apply_window(get_tree().root)
	FxSettings.load_settings()
	ModelLibrary.configure_from_command_line()
	ItemIcons.configure_from_command_line()
	LocaleNames.configure_from_command_line()
	PlayerInput.define_actions()
	Settings.apply_bindings()
	Settings.listen(_on_setting_changed)
	# "Automatic" UI scale follows the window's height, so a resize can change it.
	get_tree().root.size_changed.connect(func() -> void: Settings.apply_ui_scale(get_tree().root))
	Settings.apply_ui_scale(get_tree().root)

	Bridge.welcomed.connect(_on_welcome)
	Bridge.message_received.connect(_on_message)
	Bridge.connection_lost.connect(_on_connection_lost)

	# VR (--vr with --xr-mode on): the headset, controllers and the HUD on a panel.
	if VrSession.requested():
		var vr := VrSession.new()
		vr.name = "VR"
		vr.main = self
		add_child(vr)

	front_end = FrontEnd.new()
	front_end.main = self
	add_child(front_end)
	# Add-ons (scripts/addons/, docs/ADDONS.md), after the menu: they get input before it does.
	addons = AddonHost.new()
	addons.main = self
	add_child(addons)
	var direct := false
	for option in DIRECT_OPTIONS:
		if Settings.has_arg(option):
			direct = true
	if direct:
		start_game()
		Bridge.connect_to("127.0.0.1", Bridge.factorio_port, Bridge.listen_port)
		front_end.open_direct("127.0.0.1:%d" % Bridge.factorio_port)
	else:
		front_end.open_menu()

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			var spec := arg.get_slice("=", 1)
			var delay := 10.0
			if spec.contains("@"):
				delay = float(spec.get_slice("@", 1))
				spec = spec.get_slice("@", 0)
			_save_screenshot_later(spec, delay)
		elif arg.begins_with("--plat-board="):
			var spec := arg.get_slice("=", 1)
			_board_later(int(spec.get_slice("@", 0)), float(spec.get_slice("@", 1)) if spec.contains("@") else 5.0)
		elif arg.begins_with("--ride="):
			var spec := arg.get_slice("=", 1)
			_ride_later(int(spec.get_slice("@", 0)), float(spec.get_slice("@", 1)) if spec.contains("@") else 8.0)
		elif arg.begins_with("--land="):
			_land_later(float(arg.get_slice("=", 1)))


func _board_later(index: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	Bridge.send({"t": "plat_board", "i": index})


## Opens the silo nearest the character and rides its rocket to platform `index`, as the Ride
## button does.
func _ride_later(index: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if world == null:
		return
	var best: WorldMirror.Rec = null
	for key in world.entities:
		var r: WorldMirror.Rec = world.entities[key]
		var p = world.protos.entity(r.proto_id)
		if p != null and p.type == "rocket-silo" and (best == null or r.pos.distance_to(avatar.ground_position()) < best.pos.distance_to(avatar.ground_position())):
			best = r
	if best == null:
		print("--ride: no rocket silo in the world")
		return
	Bridge.send({"t": "open", "u": best.unit, "p": best.proto_id, "x": best.fixed.x, "y": best.fixed.y})
	await get_tree().create_timer(0.5).timeout
	Bridge.send({"t": "ride", "u": best.unit, "to": index})
	Bridge.send({"t": "close"})


func _land_later(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	Bridge.send({"t": "land"})


## A console command from the chat (/...): over RCON when this client started the server.
func _run_command(command: String) -> String:
	if not _has_rcon():
		return "Commands need RCON: start the server from this client's menu"
	return await front_end.launcher.rcon.run(get_tree(), command)


func _has_rcon() -> bool:
	var launcher = front_end.launcher if front_end != null else null
	return launcher != null and launcher.is_running() and launcher.rcon.is_open()


func in_game() -> bool:
	return _game != null


## Builds the game's nodes: the world mirror and its layers, the avatar, camera, HUD, input, sound.
func start_game() -> void:
	if _game != null:
		return
	_game = Node3D.new()
	_game.name = "Game"
	add_child(_game)
	move_child(_game, 0)
	_build_environment()

	world = WorldMirror.new()
	world.name = "World"
	world.sun = _sun
	_game.add_child(world)

	movers = MoverLayer.new()
	movers.name = "Movers"
	movers.protos = world.protos
	movers.world = world
	_game.add_child(movers)

	ups_governor = UpsGovernor.new()
	ups_governor.name = "UpsGovernor"
	ups_governor.changed.connect(_apply_game_settings)
	ups_governor.budget_changed.connect(Bridge.set_work_budget)
	_game.add_child(ups_governor)

	remote_fog = RemoteFog.new()
	remote_fog.name = "RemoteFog"
	_game.add_child(remote_fog)
	movers.fog = remote_fog
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--robot-probe="):
			var probe: Node = preload("res://scripts/debug/robot_probe.gd").new()
			probe.movers = movers
			probe.out_path = arg.get_slice("=", 1)
			add_child(probe)
		elif arg.begins_with("--glide-probe="):
			var glide: Node = preload("res://scripts/debug/glide_probe.gd").new()
			glide.main = self
			glide.out_path = arg.get_slice("=", 1)
			add_child(glide)
		elif arg.begins_with("--belt-path-probe="):
			var belts: Node = preload("res://scripts/debug/belt_path_probe.gd").new()
			belts.main = self
			belts.out_path = arg.get_slice("=", 1)
			add_child(belts)
		elif arg.begins_with("--quit-probe="):
			var quitter: Node = preload("res://scripts/debug/quit_probe.gd").new()
			quitter.main = self
			quitter.seconds = float(arg.get_slice("=", 1))
			add_child(quitter)
		elif arg.begins_with("--soak-probe="):
			var soak: Node = preload("res://scripts/debug/soak_probe.gd").new()
			var spec := arg.get_slice("=", 1).split("@")
			soak.main = self
			soak.out_path = spec[0]
			if spec.size() > 1:
				soak.minutes = float(spec[1])
			add_child(soak)
		elif arg.begins_with("--ups-probe="):
			var ups_probe: Node = preload("res://scripts/debug/ups_probe.gd").new()
			ups_probe.main = self
			ups_probe.out_path = arg.substr(arg.find("=") + 1)
			add_child(ups_probe)
	remote_fog.world = world

	belt_items = BeltItemLayer.new()
	belt_items.name = "BeltItems"
	belt_items.protos = world.protos
	belt_items.world = world
	_game.add_child(belt_items)
	belt_lanes = BeltLaneLayer.new()
	belt_lanes.name = "BeltLanes"
	belt_lanes.protos = world.protos
	belt_lanes.world = world
	belt_lanes.distance = clampi(int(Settings.get_value("graphics", "belt_far_distance")), 0, 640)
	belt_lanes.near = clampi(int(Settings.get_value("graphics", "belt_near_distance")), 8, 96)
	_game.add_child(belt_lanes)

	ground_items = GroundItemLayer.new()
	ground_items.name = "GroundItems"
	ground_items.protos = world.protos
	_game.add_child(ground_items)

	decoratives = DecorativeLayer.new()
	decoratives.name = "Decoratives"
	decoratives.world = world
	_game.add_child(decoratives)

	arms = InserterArmLayer.new()
	arms.name = "InserterArms"
	arms.protos = world.protos
	arms.world = world
	_game.add_child(arms)

	lamps = LampLayer.new()
	lamps.name = "Lamps"
	lamps.protos = world.protos
	lamps.world = world
	_game.add_child(lamps)
	var glow := WorkingGlow.new()
	glow.name = "WorkingGlow"
	glow.world = world
	_game.add_child(glow)

	fluids_power = FluidsPowerLayer.new()
	fluids_power.name = "FluidsPower"
	fluids_power.world = world
	_game.add_child(fluids_power)
	lamps.power = fluids_power

	wires = WireLayer.new()
	wires.name = "Wires"
	wires.world = world
	_game.add_child(wires)
	lamps.fog = remote_fog
	wires.fog = remote_fog

	ghosts = GhostLayer.new()
	ghosts.name = "Ghosts"
	ghosts.world = world
	_game.add_child(ghosts)

	avatar = Avatar.new()
	avatar.name = "Avatar"
	_game.add_child(avatar)

	combat = CombatLayer.new()
	combat.name = "Combat"
	combat.world = world
	combat.movers = movers
	combat.avatar = avatar
	_game.add_child(combat)

	rig = CameraRig.new()
	rig.name = "CameraRig"
	rig.target = avatar
	decoratives.rig = rig
	_game.add_child(rig)
	var tall_fade := TallFade.new()  # the tall-entities toggle's fade (shader uniforms)
	tall_fade.name = "TallFade"
	tall_fade.rig = rig
	tall_fade.avatar = avatar
	_game.add_child(tall_fade)
	if ReviewShots.requested():
		var shots := ReviewShots.new()
		shots.rig = rig
		shots.avatar = avatar
		shots.game = _game
		_game.add_child(shots)
	if AnimShots.requested():
		var clip := AnimShots.new()
		clip.game = _game
		_game.add_child(clip)

	hud = Hud.new()
	hud.name = "Hud"
	_game.add_child(hud)
	hud.screen.protos = world.protos
	hud.ui.run_command = _run_command
	hud.ui.has_rcon = _has_rcon
	remote_fog.model = hud.ui.model  # roboports reveal under the remote view's fog too (H13)

	rockets = RocketLayer.new()
	rockets.name = "Rockets"
	rockets.movers = movers
	rockets.model = hud.ui.model
	var territories := TerritoryLayer.new()
	territories.name = "Territories"
	territories.model = hud.ui.model
	_game.add_child(territories)
	demolishers = DemolisherLayer.new()
	demolishers.name = "Demolishers"
	demolishers.model = hud.ui.model
	demolishers.protos = world.protos
	_game.add_child(demolishers)
	_game.add_child(rockets)
	collectors = CollectorLayer.new()
	collectors.name = "Collectors"
	collectors.model = hud.ui.model
	collectors.world = world
	_game.add_child(collectors)
	world.animator.collectors = collectors
	quality_marks = QualityMarks.new()
	quality_marks.name = "QualityMarks"
	quality_marks.world = world
	quality_marks.belt_items = belt_items
	quality_marks.model = hud.ui.model
	quality_marks.alt_mode = hud.ui.alt_mode
	hud.ui.alt_mode_changed.connect(func(on: bool) -> void: quality_marks.alt_mode = on)
	_game.add_child(quality_marks)

	platform_panel = PlatformPanel.new()
	platform_panel.name = "PlatformPanel"
	hud.add_child(platform_panel)
	hud.move_child(platform_panel, 0)  # under the windows, as Factorio's HUD panels are
	hud.ui.platform_panel = platform_panel  # under the minimap, top right (factorio_ui.gd layout)
	platform_panel.space_map_requested.connect(func() -> void: hud.ui.open_space_map(true))
	# Mech armour changes how the character is drawn (avatar.set_armor).
	var armor_changed := func() -> void:
		avatar.set_armor(str(hud.ui.model.stack_at("armor", 1).get("item", "")))
	hud.ui.model.inventory_changed.connect(armor_changed)
	# Other players' characters wear their armour's look too (`pl` says what each wears).
	var looks_changed := func() -> void:
		var looks := {}
		for p: Dictionary in hud.ui.model.players:
			if int(p["unit"]) != 0 and str(p.get("armor", "")) != "":
				looks[int(p["unit"])] = Avatar.look_for(str(p["armor"]))
		movers.creatures.set_looks(looks)
	hud.ui.model.players_changed.connect(looks_changed)
	# Lightning rods and collectors glow where a strike lands (anim.gd).
	hud.ui.model.lightning_struck.connect(world.animator.strike)

	player_tags = PlayerTags.new()
	player_tags.name = "PlayerTags"
	player_tags.movers = movers
	player_tags.model = hud.ui.model
	_game.add_child(player_tags)

	input = PlayerInput.new()
	input.name = "Input"
	input.world = world
	input.remote_fog = remote_fog
	input.rig = rig
	input.hud = hud
	input.combat = combat
	input.avatar = avatar
	input.movers = movers
	input.wires = wires
	_game.add_child(input)
	fluids_power.input = input

	fx = Fx.new()
	fx.name = "Fx"
	fx.world = world
	fx.movers = movers
	fx.combat = combat
	fx.avatar = avatar
	fx.rig = rig
	_game.add_child(fx)
	turrets = TurretLayer.new()
	turrets.name = "Turrets"
	turrets.movers = movers
	turrets.fx = fx
	_game.add_child(turrets)
	world.animator.turrets = turrets
	movers.vehicles.model = hud.ui.model
	movers.vehicles.turrets = turrets
	movers.vehicles.sprites = fx.sprites
	ride = Ride.new()
	ride.name = "Ride"
	ride.avatar = avatar
	ride.rig = rig
	ride.rockets = rockets
	ride.ui = hud.ui
	ride.input = input
	_game.add_child(ride)
	_apply_game_settings()
	addons.game_started()


## Frees the game's nodes and disconnects (the menu takes over).
func end_game() -> void:
	Bridge.disconnect_from()
	if _game == null:
		return
	addons.game_ended()  # while the game's nodes are still there
	if rig != null and rig.first_person:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_game.queue_free()
	_game = null
	world = null
	movers = null
	belt_items = null
	ground_items = null
	decoratives = null
	arms = null
	lamps = null
	fluids_power = null
	wires = null
	ghosts = null
	combat = null
	avatar = null
	rig = null
	hud = null
	platform_panel = null
	player_tags = null
	rockets = null
	collectors = null
	ride = null
	quality_marks = null
	input = null
	fx = null
	turrets = null
	_env = null
	_sun = null
	# The space sky belonged to the freed environment.
	_space_material = null
	_space = false
	_planet_sky = null
	_planet_sky_res = null
	_space_sky = null


## Input to the game on or off (off while a menu covers it): walking, mining, keys.
func set_game_input(on: bool) -> void:
	if input == null:
		return
	input.set_process(on)
	input.set_process_unhandled_input(on)
	hud.ui.set_process_unhandled_input(on)
	if not on:
		Bridge.send({"t": "walk", "d": -1})
		Bridge.send({"t": "shoot", "m": -1, "x": 0, "y": 0})


func loaded_chunks() -> int:
	return world.loaded_chunk_count() if world != null else 0


## Factorio's UI scale keys work everywhere, in the menus too (Ctrl+= / Ctrl+- / Ctrl+0).
func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if _game != null and hud.ui.typing():
		return
	if event.is_action("increase_ui_scale", true):
		Settings.step_ui_scale(1)
	elif event.is_action("decrease_ui_scale", true):
		Settings.step_ui_scale(-1)
	elif event.is_action("reset_ui_scale", true):
		Settings.set_value("interface", "ui_scale", "auto")
	else:
		return
	get_viewport().set_input_as_handled()
	if _game != null:
		hud.show_message("UI scale %d%%" % roundi(Settings.wanted_ui_scale() * 100.0))


func _on_setting_changed(section: String, _key: String) -> void:
	if section in ["graphics", "interface", "camera"]:
		_apply_game_settings()


## Settings that apply to a running game: shadows, ambient occlusion, brightness, contrast and
## saturation, view distance, help, F4.
func _apply_game_settings() -> void:
	if _game == null:
		return
	Settings.apply_environment(_env)
	_sun.shadow_enabled = Settings.shadow_size() > 0
	if _sun.shadow_enabled:
		# Atlas, splits, distance (fitted to the view), blending and filter by quality (sun_shadows.gd).
		sun_shadows.apply_quality(str(Settings.get_value("graphics", "shadows")))
	_env.ssao_enabled = bool(Settings.get_value("graphics", "ssao"))
	_planet_sky.set_clouds(bool(Settings.get_value("graphics", "clouds")))
	# Every distance the bridge works for in the game's tick, under the player's own setting while the
	# UPS governor holds it back (ups_governor.gd).
	var held := ups_governor
	world.view_radius = clampi(int(held.limit("view", float(Settings.get_value("graphics", "view_radius")))), 1, 20)
	ModelLods.apply_quality(str(Settings.get_value("graphics", "lod_quality")), get_viewport())
	world.far_chunks.enabled = bool(Settings.get_value("graphics", "merge_far"))
	belt_lanes.distance = clampi(int(held.limit("far", float(Settings.get_value("graphics", "belt_far_distance")))), 0, 640)
	belt_lanes.near = clampi(int(held.limit("near", float(Settings.get_value("graphics", "belt_near_distance")))), 8, 96)
	belt_lanes.smooth = bool(Settings.get_value("graphics", "belt_smooth")) and held.limit("smooth", 1.0) >= 1.0
	decoratives.set_options(bool(Settings.get_value("graphics", "decoratives")), float(Settings.get_value("graphics", "decorative_density")))
	decoratives.distance = clampf(float(Settings.get_value("graphics", "decorative_distance")), 32.0, 320.0)
	Bridge.decoratives = decoratives.enabled
	world.set_focus_radius(clampi(int(held.limit("entity", float(Settings.get_value("graphics", "entity_radius")))), 16, 256))
	hud.ui.map_cache.refresh_scale = held.limit("map", 1.0)
	Bridge.set_update_rate(int(held.limit("rate", 0.0)))
	Settings.fps_hold = int(held.limit("fps", 0.0))
	Engine.max_fps = Settings.fps_limit()
	hud.help.visible = bool(Settings.get_value("interface", "show_help"))
	hud.ui.debug_overlay = bool(Settings.get_value("interface", "debug_overlay"))
	rig.apply_settings()


func _save_screenshot_later(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	# --clean-shot: just the world, for model screenshots (the character stands on the model).
	if OS.get_cmdline_user_args().has("--clean-shot") and _game != null:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		hud.visible = false
		avatar.visible = false
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("screenshot %s: %s" % [path, error_string(err)])


func _on_welcome(msg: Dictionary) -> void:
	if _game == null:
		return
	world.reset()
	movers.reset()
	belt_items.reset()
	belt_lanes.reset()
	ground_items.reset()
	decoratives.reset()
	arms.reset()
	fluids_power.reset()
	wires.reset()
	ghosts.reset()
	combat.reset()
	fx.reset()
	turrets.reset()
	rockets.reset()
	collectors.reset()
	quality_marks.reset()
	hud.reset()
	avatar.unit = int(msg.get("u", 0))
	movers.puppet_unit = avatar.unit
	avatar.snap_to(Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0)
	rig.global_position = avatar.global_position
	world.set_focus(avatar.ground_position())
	hud.ui.model.set_character_surface(int(msg.get("si", 0)))
	platform_panel.reset()
	platform_panel.surface_changed(int(msg.get("pf", 0)), str(msg.get("planet", "")))
	_planet_sky.set_planet(str(msg.get("planet", "nauvis")))
	fx.set_planet(str(msg.get("planet", "nauvis")), int(msg.get("pf", 0)) > 0)
	_set_space(int(msg.get("pf", 0)) > 0)
	var mode := "server" if msg.get("mp", false) else "single-player"
	hud.show_message("Connected to Factorio (%s, surface %s)" % [mode, str(msg.get("surface", "?"))])


## The character is on another surface now (a space platform or back): drop the world, keep
## the prototypes, inventory and the rest of the UI, and let the world subscribe around it again.
func _on_surface(msg: Dictionary) -> void:
	world.reset(true)
	movers.reset()
	belt_items.reset()
	belt_lanes.reset()
	ground_items.reset()
	decoratives.reset()
	arms.reset()
	fluids_power.reset()
	wires.reset()
	ghosts.reset()
	combat.reset()
	fx.reset()
	turrets.reset()
	rockets.reset()
	rockets.surface = str(msg.get("surface", ""))
	collectors.reset()
	quality_marks.reset()
	hud.screen.close_local()
	hud.set_mining(-1)
	hud.ui.map_cache.reset()
	var at := Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0
	# `view`: the remote view looks at another surface; the character stays where it is, unseen.
	var viewing := int(msg.get("view", 0)) == 1
	avatar.visible = not viewing
	if viewing:
		hud.ui.model.set_map_surface(int(msg.get("si", 0)))
		world.set_focus(at)
	else:
		hud.ui.model.set_character_surface(int(msg.get("si", 0)))
		avatar.snap_to(at)
		# Riding a pod the camera follows the ride (ride.gd), which fades over the change.
		if not ride.riding():
			rig.global_position = avatar.global_position
		world.set_focus(avatar.ground_position())
	var pf := int(msg.get("pf", 0))
	platform_panel.surface_changed(pf, str(msg.get("planet", "")))
	_planet_sky.set_planet(str(msg.get("planet", "nauvis")))
	fx.set_planet(str(msg.get("planet", "nauvis")), pf > 0)
	_set_space(pf > 0)
	hud.show_message("Now on %s" % (str(msg.get("surface", "?")) if pf > 0 else LocaleNames.space_location(str(msg.get("planet", msg.get("surface", "?"))))))


func _on_message(msg: Dictionary) -> void:
	if _game == null:
		return
	fx.handle(msg)  # first: it looks up entities and movers before they are removed
	match str(msg.get("t", "")):
		"me":
			avatar.update_from(ride.handle_me(msg))
			movers.puppet_unit = avatar.unit
			hud.set_mining(avatar.mining)
			hud.set_health(avatar.health, avatar.max_health)
			hud.set_shield(int(msg.get("sd", 0)), int(msg.get("msd", 0)))
			hud.ui.death_screen.alive()
		"mv":
			movers.handle(msg)
		# Live state is sent at once, but on a real game the prototype dictionaries take several
		# ticks to arrive; an item drawn before its name is known would never get its icon.
		"bi":
			if Bridge.world_ready:
				belt_items.handle(msg)
		"bfar":
			if Bridge.world_ready:
				belt_lanes.handle(msg)
		"ih":
			if Bridge.world_ready:
				arms.handle(msg)
		"gi":
			if Bridge.world_ready:
				ground_items.handle(msg)
		"dprotos", "dec":
			decoratives.handle(msg)
		"hp":
			combat.handle_health(msg)
		"tf":
			turrets.handle_fire(msg)
		"ts":
			turrets.handle_states(msg)
			fx.weapons.prewarm_fights()  # turrets in view: their effects made before the first shot
			movers.creatures.prewarm()
		"acol":
			collectors.handle(msg)
		"pj":
			turrets.handle_projectiles(msg)  # fx.gd's weapon_fx.gd draws them too (fx.handle above)
		"shot", "gf":
			pass  # fx.gd (weapon_fx.gd) draws them
		"died":
			combat.handle_died(msg)
			var dead = world.protos.entity(int(msg.get("p", 0)))
			if dead != null:
				movers.creatures.died_at(dead.name, Vector3(int(msg.get("x", 0)) / 256.0, 0.0, int(msg.get("y", 0)) / 256.0))
		"en":
			movers.creatures.handle_attacks(msg)
			fx.weapons.prewarm_fights()
			movers.creatures.prewarm()
		"guns":
			hud.set_guns(int(msg.get("sel", 1)), _array(msg.get("l")))
		"fl", "pw", "ht":
			if Bridge.world_ready:
				fluids_power.handle(msg)
		"surface":
			_on_surface(msg)
		"raise":
			GameSwap.show_client()
		"cov":
			remote_fog.handle(msg)
		"plat":
			platform_panel.handle(msg)
			_show_planet_for(platform_panel.current())
		"sky":
			_sky_daytime = int(msg.get("d", 0)) / 1000.0
			_sky_darkness = int(msg.get("n", 0)) / 1000.0
		"inv":
			hud.set_inventory(_array(msg.get("l")))
		"recipes":
			hud.set_recipes(_array(msg.get("l")))
		"gui":
			hud.screen.handle(msg)
		"msg":
			# A research notification names the technology, so it can be shown in the player's language.
			if msg.has("tech"):
				hud.show_message("Research completed: %s" % LocaleNames.technology(str(msg["tech"])))
			else:
				hud.show_message(str(msg.get("text", "")))
		_:
			if not hud.ui.model.handle(msg):  # UI data (scripts/ui/factorio/ui_model.gd)
				world.handle(msg)


func _on_connection_lost() -> void:
	if hud == null:
		return
	hud.show_message("Lost connection to Factorio")
	hud.set_mining(-1)


func _process(delta: float) -> void:
	if _game == null:
		return
	world.set_focus(rig.focus_point())
	belt_lanes.focus = rig.focus_point()
	belt_lanes.covered = belt_items.covered()
	# Factorio's remote view: dark fog where no radar sees, and nothing drawn there.
	world.set_remote_view(hud.ui.remote)
	remote_fog.update(hud.ui.remote, rig.focus_point())
	_update_sky(delta)
	_sync_sky_view()
	_status_timer += delta
	if _status_timer >= 0.5:
		_update_status(_status_timer)
		_status_timer = 0.0
	# Headless runs have no HUD to look at, so the status goes to stdout instead.
	_log_timer += delta
	if _headless and _log_timer >= 5.0:
		_log_timer = 0.0
		print(hud.status.text.replace("\n", " | "))


func _update_status(elapsed: float) -> void:
	var packets: int = Bridge.stats["packets"]
	var rate := (packets - _packets_before) / elapsed
	_packets_before = packets
	var tick := Bridge.server_tick
	if _tick_before >= 0 and tick >= _tick_before:
		var ups := (tick - _tick_before) / elapsed
		_ups = lerpf(_ups, ups, 0.5) if _ups > 0.0 else ups
	_tick_before = tick
	if Bridge.bind_error != OK:
		hud.status.text = "Can't open UDP port %d. Is another client already running?" % Bridge.listen_port
	elif not Bridge.connected:
		hud.status.text = "Waiting for Factorio on 127.0.0.1:%d\nStart it with --enable-lua-udp %d and the factorio-3d-bridge mod (see docs/RUNNING.md)" % [Bridge.factorio_port, Bridge.factorio_port]
	elif not Bridge.world_ready:
		hud.status.text = "Connected. Loading prototypes..."
	else:
		hud.status.text = "tick %d · %d chunks · %d entities · %d moving · %d on belts · %d on the ground · %d arms · %d lamps lit · %d wires · %d ghosts · %d packets/s · %d gaps · %.1f UPS · %d FPS\nhealth %d · crafting %d · %s" % [
			Bridge.server_tick, world.loaded_chunk_count(), world.entity_count(), movers.count(), belt_items.count(), ground_items.count(), arms.count(), lamps.lit_count(), wires.span_count(), ghosts.ghost_count(),
			int(rate), int(Bridge.stats["gaps"]), _ups, int(Engine.get_frames_per_second()), avatar.health, avatar.craft_queue, fx.status()]
		var held := ups_governor.status()
		if held != "":
			hud.status.text += "\n" + held
		var merged := world.far_chunks.status()
		if merged != "":
			hud.status.text += "\n" + merged


func _build_environment() -> void:
	var env := Environment.new()
	_planet_sky = PlanetSky.new()
	_planet_sky.name = "Sky"
	_game.add_child(_planet_sky)
	_planet_sky_res = Sky.new()
	_planet_sky_res.sky_material = _planet_sky.sky_material
	# Reflections only need a rough picture of the sky, refreshed a little each frame.
	_planet_sky_res.radiance_size = Sky.RADIANCE_SIZE_32
	_planet_sky_res.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = _planet_sky_res
	env.background_color = Color(0.55, 0.62, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	_env = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_game.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	_game.add_child(sun)
	_sun = sun
	sun_shadows = SunShadows.new()
	sun_shadows.name = "SunShadows"
	sun_shadows.sun = sun
	_game.add_child(sun_shadows)


## The planet straight below a stopped platform (space_sky.gdshader's planet_radius, radians: its
## edge 38 degrees under the horizon, so it fills the view's lower part), and how much
## of a route it takes to fall away or come near.
const PLANET_RADIUS := 0.9
const PLANET_FADE := 0.12


## Space behind a platform, or the planet's sky.
func _set_space(on: bool) -> void:
	_space = on
	if on:
		if _space_material == null:
			_space_material = ShaderMaterial.new()
			_space_material.shader = SPACE_SKY
			_space_sky = Sky.new()
			_space_sky.sky_material = _space_material
		_env.sky = _space_sky
		_show_planet_for(platform_panel.current())
	else:
		_env.sky = _planet_sky_res


## The planet in the platform's sky: the one it is stopped at; while travelling, the one it left
## falling away over the first part of the route and the next one growing over the last,
## nothing in between.
func _show_planet_for(rec: Dictionary) -> void:
	var shown := planet_in_sky(rec)
	_show_planet(shown[0], shown[1])


## [location, size 0-1] of the planet a platform's `plat` record puts in its sky ("" for none).
## `d` is how far along the route in thousandths (`len` is the route's length in km, F4: reading
## d / len kept every route in its first 12%, so the planet left never went away).
static func planet_in_sky(rec: Dictionary) -> Array:
	if rec.get("to") == null or str(rec.get("to")) == "":
		return [str(rec.get("loc", "")) if rec.get("loc") != null else "", 1.0]
	var t := clampf(float(rec.get("d", 0)) / 1000.0, 0.0, 1.0)
	var near := PlatformPanel.planet_nearness(t, PLANET_FADE)
	if near <= 0.0:
		return ["", 0.0]
	return [str(rec.get("from", "")) if t < 0.5 else str(rec.get("to", "")), near]



func _show_planet(location: String, size := 1.0) -> void:
	if _space_material == null:
		return
	_space_material.set_shader_parameter("planet_radius", PLANET_RADIUS * maxf(size, 0.05))
	_space_material.set_shader_parameter("planet_on", 1.0 if PLANET_COLORS.has(location) else 0.0)
	if PLANET_COLORS.has(location):
		var c: Color = PLANET_COLORS[location]
		_space_material.set_shader_parameter("planet_color", Vector3(c.r, c.g, c.b))
	# The real planet: Factorio's star map picture of it, where the install has one.
	var tex := planet_picture(location)
	_space_material.set_shader_parameter("planet_tex_on", 1.0 if tex != null else 0.0)
	if tex != null:
		_space_material.set_shader_parameter("planet_tex", tex)
	# Its whole surface on a sphere once the maps are loaded (on a worker: 2048 x 1024 each).
	var maps := planet_maps_soon(location)
	_space_material.set_shader_parameter("planet_map_on", 1.0 if maps.has("map") else 0.0)
	_space_material.set_shader_parameter("planet_clouds_on", 1.0 if maps.has("clouds") else 0.0)
	_space_material.set_shader_parameter("planet_emission_on", 1.0 if maps.has("emission") else 0.0)
	for key in maps:
		_space_material.set_shader_parameter("planet_" + str(key), maps[key])


static var _planet_maps := {}  # location -> {"map", "clouds"?, "emission"?: Texture2D}, {} without
static var _planet_images := {}  # location -> {key: Image}, from the worker
static var _planet_tasks := {}  # location -> WorkerThreadPool task id
static var _planet_lock := Mutex.new()


## Factorio's maps of a planet's surface (space-age/graphics/space/<planet>.png, its clouds and
## emission), as textures, once loaded: {} until then (asked again with the next `plat`) and for
## places without them. They are read and mipmapped on a worker thread.
static func planet_maps_soon(location: String) -> Dictionary:
	if location == "":
		return {}
	if _planet_maps.has(location):
		return _planet_maps[location]
	if _planet_tasks.has(location):
		var task: int = _planet_tasks[location]
		if not WorkerThreadPool.is_task_completed(task):
			return {}
		WorkerThreadPool.wait_for_task_completion(task)
		_planet_tasks.erase(location)
		_planet_lock.lock()
		var images: Dictionary = _planet_images.get(location, {})
		_planet_images.erase(location)
		_planet_lock.unlock()
		var out := {}
		for key in images:
			out[key] = ImageTexture.create_from_image(images[key])
		_planet_maps[location] = out
		return out
	var dir := ItemIcons.find_data_dir()
	var base := dir.path_join("space-age/graphics/space/%s" % location) if dir != "" else ""
	if base == "" or not FileAccess.file_exists(base + ".png"):
		_planet_maps[location] = {}
		return {}
	_planet_tasks[location] = WorkerThreadPool.add_task(_load_planet_maps.bind(location, base), false, "planet maps")
	return {}


static func _load_planet_maps(location: String, base: String) -> void:
	var images := {}
	for pair in [["map", ""], ["clouds", "-cloud"], ["emission", "-emission"]]:
		var path: String = base + str(pair[1]) + ".png"
		if not FileAccess.file_exists(path):
			continue
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			continue
		image.generate_mipmaps()
		images[pair[0]] = image
	_planet_lock.lock()
	_planet_images[location] = images
	_planet_lock.unlock()


## Factorio's picture of a planet (its star map sprite), or null without the install or one.
static func planet_picture(location: String) -> Texture2D:
	if location == "":
		return null
	for path in ["space-age/graphics/icons/starmap-planet-%s.png", "base/graphics/icons/starmap-planet-%s.png"]:
		var t := GuiAssets.data_sprite(path % location)
		if t != null:
			return t
	return null


## Eases towards the game's time of day (it only arrives once a second) and lights the scene
## for it: the sun's height and colour, ambient light and sky, the character's light, lamps.
func _update_sky(delta: float) -> void:
	var blend := minf(1.0, delta * 2.0)
	_daytime = fposmod(_daytime + wrapf(_sky_daytime - _daytime, -0.5, 0.5) * blend, 1.0)
	_darkness = lerpf(_darkness, _sky_darkness, blend)
	if _planet_sky.forced_daytime >= 0.0:  # --sky=<planet>@<daytime>, for screenshots
		_daytime = _planet_sky.forced_daytime
		_darkness = clampf(0.5 - 2.5 * cos(TAU * _daytime), 0.0, 0.85)
	var night := clampf(_darkness / 0.85, 0.0, 1.0)
	_planet_sky.apply(_env, _sun, _daytime, night, delta, _space)
	# Night vision equipment: Factorio's turns on past half darkness while it has power and lifts
	# the night with its colour lookup (a brighter, greener picture).
	var nv_on := bool(hud.ui.model.grid("char").get("night_vision", false)) and _darkness >= 0.5
	_night_vision = move_toward(_night_vision, 1.0 if nv_on else 0.0, delta * 2.0)
	if _night_vision > 0.0:
		_env.ambient_light_energy += 1.4 * _night_vision
		_env.ambient_light_color = _env.ambient_light_color.lerp(Color(0.62, 0.86, 0.62), 0.6 * _night_vision)
	avatar.set_night(night)
	movers.set_night(night)
	lamps.darkness = _darkness
	lamps.focus = rig.focus_point()


## The camera, for the sky shaders (sky_view.gdshaderinc): under an orthographic camera Godot's sky
## rays come out nearly 180° wide, so the shaders are given the real orientation and field of view
##. The planet below a platform stays put (space_sky.gdshader's planet_dir, F4).
func _sync_sky_view() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var ortho := cam.projection == Camera3D.PROJECTION_ORTHOGONAL
	var size := get_viewport().get_visible_rect().size
	var t := tan(deg_to_rad(cam.fov) * 0.5)
	var view_tan := Vector2(t * size.x / maxf(size.y, 1.0), t)
	if cam.keep_aspect == Camera3D.KEEP_WIDTH:
		view_tan = Vector2(t, t * size.y / maxf(size.x, 1.0))
	for m: ShaderMaterial in [_planet_sky.sky_material, _space_material]:
		if m == null:
			continue
		m.set_shader_parameter("view_ortho", 1.0 if ortho else 0.0)
		if ortho:
			m.set_shader_parameter("view_basis", cam.global_transform.basis.orthonormalized())
			m.set_shader_parameter("view_tan", view_tan)


static func _array(v) -> Array:
	return v if v is Array else []
