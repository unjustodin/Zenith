extends Control
## The Factorio-style UI: the character window (inventory with crafting or a machine screen), the
## technology screen, the quickbar with the weapon slots beside it, the crafting queue, the stack
## in the cursor, all drawn with kit.gd from the player's Factorio install, and the data they show
## (ui_model.gd). hud.gd creates it; player_input.gd sets `player` so the UI can read and set the
## held item.
##
## The cursor works like Factorio 2.1's (the rules recorded from the game by
## tools/ui_reference/f3d-ui-capture/rules.lua): click a stack to pick it up (right click: the
## bigger half), click another slot to put it there (onto the same item what fits, the rest stays
## held; onto another item that one is picked up instead; right click puts one), click its own slot
## or press Q to put it back; drag the held stack across slots to spread it (right button: one in
## each); Shift+click moves a stack to the other inventory (Ctrl+click: every stack of the item),
## through the mod's `xfer`. The bridge's character has no cursor of its own, so the
## picked-up stack stays in its slot (shown with Factorio's hand) and a click sends `move`. Held
## items build like the quickbar's.
##
## Keys handled here (InputMap actions, controls.gd, rebindable): 1-0 quickbar (with the window
## open, pin the hovered or held item instead), Shift+1-0 quickbar pages, X swap quickbars, T the technology
## screen, M the map (minimap.gd in the corner, map_view.gd), P and K production and kill statistics
## (stats_window.gd), ` and / the chat and console (chat_window.gd), Ctrl+F crafting search, F4 the
## debug overlay (the HUD's status line), and Esc (fixed), which closes the item chooser, the chat,
## the map's tag dialog, the map, then the windows. E stays in player_input.gd, which knows what is
## hovered.
##
## Also here: Alt-mode's icons (alt_overlay.gd), Factorio's top-right side menu (side_menu.gd:
## the research in progress, research_progress.gd, the 6+4 buttons and the minimap's place), the
## entity info panel under it (entity_info.gd), the shortcut bar right of the quickbar
## (shortcut_bar.gd, with its chooser) and Factorio's item chooser (item_picker.gd) that machine
## screens use for filters, requests and signals.
##
## Debug options (after `--`): --ui=inventory, --ui=character (its Character tab), --ui=players,
## --ui=research or --ui=map opens that window at start; --ui=shortcut-chooser and --ui=page-chooser
## open the shortcut bar's and the quickbar's choosers after 3 s;
## --ui-sample feeds sample recipe details (groups, ingredients) through the model's hooks and
## pins a few items, to see the full layout against the mock; --ui-hover=<x>,<y> moves the mouse
## there after 5 s (to screenshot a tooltip or the cursor), --ui-hover-unit=<unit> over that entity
## wherever it is drawn (its entity info); --ui-hold=<item> picks up the first
## stack of that item after 4 s; --ui-craft=<recipe>:<n> hand-crafts after 3 s (the queue);
## --ui-scale=<factor> overrides the UI scale; --map opens the map view at start, --map-zoom=<gui
## pixels per tile> sets its zoom, --map-tag=<x>,<y>,<icon>,<text> adds a tag after 3 s (icon may be
## empty), --map-edit=<x>,<y> opens the tag dialog at that screen point after 5 s; --alt-mode turns
## Alt-mode on after 3 s, --stats=<item|fluid|kill> opens that statistics window after 3 s,
## --chat=<text> says it after 3 s and opens the console line, --remote=<x>,<y> looks there in
## remote view after 3 s, --map-surface=<surface index> switches the map to that surface after 6 s
## (--remote-surface=<surface index> looks at its world in the remote view then);
## --ui=space the space map (--ui=space-platform with a platform selected), --ui=networks opens the logistic networks window, --pedia=<kind>:<name> Factoriopedia on that page
## after 4 s, --research=<technology> selects it in the technology screen after 4 s; --ui=bonuses,
## --ui=alerts, --ui=achievements and --ui=permissions open that game-wide window after 2 s.
## --ui-circuit opens the open entity's circuit connection window after 8 s (with --open=...).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const CharacterWindow := preload("res://scripts/ui/factorio/character_window.gd")
const MachineScreen := preload("res://scripts/ui/factorio/machine_screen.gd")
const Quickbar := preload("res://scripts/ui/factorio/quickbar.gd")
const ResearchWindow := preload("res://scripts/ui/factorio/research_window.gd")
const CraftQueue := preload("res://scripts/ui/factorio/craft_queue.gd")
const WeaponHud := preload("res://scripts/ui/factorio/weapon_hud.gd")
const CursorStack := preload("res://scripts/ui/factorio/cursor_stack.gd")
const MapCache := preload("res://scripts/ui/factorio/map_cache.gd")
const Minimap := preload("res://scripts/ui/factorio/minimap.gd")
const MapView := preload("res://scripts/ui/factorio/map_view.gd")
const Controls := preload("res://scripts/player/controls.gd")
const ItemPicker := preload("res://scripts/ui/factorio/item_picker.gd")
const AltOverlay := preload("res://scripts/ui/factorio/alt_overlay.gd")
const EntityInfo := preload("res://scripts/ui/factorio/entity_info.gd")
const ResearchProgress := preload("res://scripts/ui/factorio/research_progress.gd")
const SideMenu := preload("res://scripts/ui/factorio/side_menu.gd")
const FxSettings := preload("res://scripts/fx/fx_settings.gd")
const ChatWindow := preload("res://scripts/ui/factorio/chat_window.gd")
const StatsWindow := preload("res://scripts/ui/factorio/stats_window.gd")
const ShortcutBar := preload("res://scripts/ui/factorio/shortcut_bar.gd")
const Alerts := preload("res://scripts/ui/factorio/alerts.gd")
const TrainsWindow := preload("res://scripts/ui/factorio/trains_window.gd")
const DeathScreen := preload("res://scripts/ui/factorio/death_screen.gd")
const PlayersWindow := preload("res://scripts/ui/factorio/players_window.gd")
const EquipmentGrid := preload("res://scripts/ui/factorio/equipment_grid.gd")
const PlannerUi := preload("res://scripts/ui/factorio/planner_ui.gd")
const SpaceMap := preload("res://scripts/ui/factorio/space_map.gd")
const Factoriopedia := preload("res://scripts/ui/factorio/factoriopedia.gd")
const NetworksWindow := preload("res://scripts/ui/factorio/networks_window.gd")
const TechSlot := preload("res://scripts/ui/factorio/tech_slot.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const Info := preload("res://scripts/ui/factorio/info_text.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const RemoteFrame := preload("res://scripts/ui/factorio/remote_frame.gd")
const BonusesWindow := preload("res://scripts/ui/factorio/bonuses_window.gd")
const AlertsConfig := preload("res://scripts/ui/factorio/alerts_config.gd")
const AchievementsWindow := preload("res://scripts/ui/factorio/achievements_window.gd")
const PermissionsWindow := preload("res://scripts/ui/factorio/permissions_window.gd")
const TipsWindow := preload("res://scripts/ui/factorio/tips_window.gd")

## Gap between the HUD's pieces and from the window's edges (GUI pixels).
const MARGIN := 8
## Entity types the item chooser offers as a turret's priority targets.
const TARGET_TYPES := ["unit", "unit-spawner", "turret", "spider-unit", "segmented-unit", "asteroid", "character"]
## The help panel's widest (GUI pixels).
const HELP_WIDTH := 340
## Measured on Factorio 2.1 at 1920x1080, 100%: the quickbar's frame starts 258 GUI pixels left of
## the screen's centre, and the shortcut bar's frame touches it.
const QUICKBAR_LEFT := 258
const BAR_GAP := 0
## Room the shortcut bar and alerts keep under the platform panel, else the panel goes beside the
## minimap (GUI pixels: two rows of shortcuts and a row of alerts).
const SHORTCUTS_MIN_HEIGHT := 2 * 40 + 44
## Below this many GUI pixels of height the quickbar shows one row.
const TWO_ROWS_HEIGHT := 600
const HELP := "E: inventory · T: technologies · M: map · P / K: statistics · L: logistic networks · F2 / Alt+click: Factoriopedia · `: chat · Alt: Alt-mode · 1-0: quickbar (inventory open: pin the hovered item) · F4: debug info"
## The open machine's inventories (the rest are the character's).
const MACHINE_ROLES := ["chest", "input", "output", "fuel", "burnt", "modules", "cargo", "trunk", "turret_ammo", "car_ammo",
	"robots", "repair", "rocket"]

var model := UiModel.new()
## Set by hud.gd before this enters the tree.
var screen: MachineScreen
var window: CharacterWindow
var research: ResearchWindow
var quickbar: Quickbar
var craft_queue: CraftQueue
var weapons: WeaponHud
var cursor: CursorStack
var map_cache: MapCache
var minimap: Minimap
var map_view: MapView
var picker: ItemPicker
var alt_overlay: AltOverlay
var entity_info: EntityInfo
var research_hud: ResearchProgress
## The top-right corner: research, the side menu's buttons and the minimap's frame.
var side_menu: SideMenu
var chat: ChatWindow
var stats: StatsWindow
var trains_window: TrainsWindow
## The blueprint library (B), blueprint and planner windows (planner_ui.gd).
var planners: PlannerUi
var space_map: SpaceMap
var shortcuts: ShortcutBar
var alerts: Alerts
## Factorio's respawn screen while the character is dead, and the players list.
var death_screen: DeathScreen
var players_window: PlayersWindow
var pedia: Factoriopedia
var networks: NetworksWindow
## The remote view was started by the logistic networks window (it ends when that closes).
var _networks_remote := false
## Factorio's "Remote view" frame round the map and the world seen from afar (remote_frame.gd).
var remote_frame: RemoteFrame
## Factorio's game-wide windows opened from its tool bar (open_global): bonuses, alerts
## configuration, achievements, permissions, tips and tricks.
var bonuses: BonusesWindow
var alerts_config: AlertsConfig
var achievements: AchievementsWindow
var permissions: PermissionsWindow
var tips: TipsWindow
## Alt-mode (Alt): icons over machines.
var alt_mode := false
## Alt-mode went on or off (quality marks follow it).
signal alt_mode_changed(on: bool)
## Remote view (zooming into the world from the map): the camera looks elsewhere, WASD moves it,
## Esc or M goes back to the character.
var remote := false
## The surface the remote view shows when it isn't the character's (0: the character's).
var viewing_si := 0
var _remote_anchor: Node3D = null
var _map_factorio_view := false  # the remote view switched to Factorio's angle when the map zoomed in
## The mover remote view follows (remote_follow), 0 none.
var _remote_follow := 0
## Inside a space platform's hub: the character sits in it and the platform is seen and
## worked from the remote view round it, as Factorio does; leaving the remote view comes back to
## the hub, not the character. INF when not in a hub.
var hub_at := Vector2.INF
var _remote_label: Label
## Runs a console command (main.gd: over RCON when the client started the server); see chat_window.gd.
var run_command := Callable()
## Callable() -> bool: whether run_command reaches the server's console now (main.gd).
var has_rcon := Callable()
## player_input.gd: its `cursor_item` and `hold(item)`. Untyped to avoid a preload cycle.
var player: Node = null
## The HUD's status line: shown while not connected, otherwise only with F4.
var status_label: Label = null
var debug_overlay := false
## Placed by layout() with the rest: the help (hud.gd, F1), the driving line, and main.gd's
## platform panel (Space Age).
var help_label: Label = null
var cursor_label: Label = null
var platform_panel: Control = null
## Where the stack in the cursor came from: {"role", "index" (1-based), "n" (0: all, else how
## many were picked up), "unit" (the machine's, for its roles)}; {} when the held item came from
## the quickbar or nowhere in particular.
var hand := {}

## A held stack dragged across slots with a button down (Factorio's drag splitting): {"button",
## "item", "total" (left: what the cursor held at the first slot), "origin" ([role, index, unit]:
## where the rest goes back to), "slots" ([[role, index, unit], ...] visited), "added" (how many
## each got)}; {} when not dragging.
var _spread := {}
var _hover_at := Vector2(-1, -1)
var _shortcuts_room := Rect2()
var _shortcuts_shown := -1
var _help_fit := []
var _hovering := false
## --ui-hover-unit: the entity whose middle the hover follows (0: none).
var _hover_unit := 0


func _init() -> void:
	Kit.configure(DisplayServer.window_get_size().y)
	Controls.define()  # main.gd defines them first; tests may not


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Kit.theme()
	texture_filter = Kit.FILTER
	get_tree().root.theme = theme  # for tooltips, which are windows of their own

	# Alt-mode's icons lie over the world, under everything else.
	alt_overlay = AltOverlay.new()
	alt_overlay.model = model
	add_child(alt_overlay)
	# The map view first, so the quickbar and windows stay on top of it as in Factorio.
	map_cache = MapCache.new(model)
	map_view = MapView.new()
	map_view.cache = map_cache
	map_view.model = model
	map_view.character = character_on_map
	add_child(map_view)
	minimap = Minimap.new()
	minimap.cache = map_cache
	minimap.model = model
	minimap.character = character_on_map
	minimap.open_map.connect(func() -> void: open_map(true))
	add_child(minimap)
	map_view.zoom_to_world.connect(_zoom_into_world)
	remote_frame = RemoteFrame.new()
	remote_frame.map_view = map_view
	add_child(remote_frame)
	var leave_remote := func() -> void:
		if map_view.is_open():
			open_map(false)
		elif remote:
			end_remote_view()
	remote_frame.close_requested.connect(leave_remote)
	remote_frame.close_requested.connect(func() -> void: networks.open(false))
	remote_frame.close_requested.connect(func() -> void: open_space_map(false))
	var back_home := func() -> void:
		if space_map.is_open():
			open_space_map(false)
		if remote:
			end_remote_view()
		elif map_view.is_open():
			map_view.show_surface(0)
	remote_frame.reset_requested.connect(back_home)
	remote_frame.info_panel.drop_requested.connect(func() -> void: _frame_drop("?"))
	remote_frame.info_panel.drop_chosen.connect(_frame_drop)
	remote_frame.info_panel.drop_cancelled.connect(func() -> void: _frame_drop(""))
	var other_surface := func(si: int) -> void:
		if remote and si != 0:
			end_remote_view()
			map_view.open(true)
			map_view.show_surface(si)
	map_view.surface_chosen.connect(other_surface)
	# A surface chosen in the Surfaces panel while the space map shows: its map instead.
	var from_space := func(si: int) -> void:
		if space_map.is_open():
			open_space_map(false)
			open_map(true)
			map_view.show_surface(si)
	map_view.surface_chosen.connect(from_space)
	_remote_label = Kit.label("Remote view · WASD: move · Esc or M: back to the character", "FGameLabel")
	_remote_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_remote_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_remote_label.offset_top = Kit.px(12)
	_remote_label.visible = false
	add_child(_remote_label)

	craft_queue = CraftQueue.new()
	craft_queue.model = model
	add_child(craft_queue)

	quickbar = Quickbar.new()
	quickbar.model = model
	quickbar.slot_clicked.connect(_on_quickbar_clicked)
	add_child(quickbar)

	weapons = WeaponHud.new()
	weapons.model = model
	weapons.holding = func() -> bool: return held_item() != "" or not hand.is_empty()
	weapons.slot_clicked.connect(_on_character_slot)
	weapons.open_requested.connect(toggle_inventory)
	add_child(weapons)
	quickbar.upper_clicked.connect(_on_upper_quickbar_clicked)
	quickbar.page_slot_clicked.connect(_on_page_slot_clicked)

	shortcuts = ShortcutBar.new()
	shortcuts.pressed.connect(_on_shortcut)
	add_child(shortcuts)
	model.research_changed.connect(func() -> void: shortcuts.update_unlocks(model.techs))

	alerts = Alerts.new()
	alerts.model = model
	alerts.show_at.connect(remote_view)
	alerts.show_on_surface.connect(func(at: Vector2, si: int) -> void:
		if remote:
			end_remote_view()
		open_map(true)
		map_view.look_at_on(si, at))
	alerts.say.connect(hud_message)
	add_child(alerts)

	research_hud = ResearchProgress.new()
	research_hud.model = model
	research_hud.open_requested.connect(func() -> void: open_research(true))
	side_menu = SideMenu.new()
	side_menu.research = research_hud
	side_menu.pressed.connect(_on_side_button)
	add_child(side_menu)
	move_child(side_menu, minimap.get_index())  # the minimap draws over the menu's frame

	entity_info = EntityInfo.new()
	entity_info.model = model
	add_child(entity_info)

	chat = ChatWindow.new()
	chat.model = model
	add_child(chat)

	window = CharacterWindow.new()
	window.model = model
	window.screen = screen
	window.slot_clicked.connect(_on_character_slot)
	window.close_requested.connect(close_all)
	# window.color_requested: the colour goes to the bridge from the window itself (set_char_color).
	window.grid_clicked.connect(_on_grid_clicked)
	add_child(window)
	screen.slot_clicked.connect(_on_machine_slot)

	research = ResearchWindow.new()
	research.model = model
	research.close_requested.connect(close_all)
	add_child(research)

	stats = StatsWindow.new()
	stats.model = model
	stats.close_requested.connect(func() -> void: stats.visible = false)
	add_child(stats)

	trains_window = TrainsWindow.new()
	trains_window.model = model
	trains_window.close_requested.connect(func() -> void: trains_window.open(false))
	var look_at_train := func(at: Vector2) -> void:
		trains_window.open(false)
		remote_view(at)
	trains_window.show_at.connect(look_at_train)
	add_child(trains_window)

	players_window = PlayersWindow.new()
	players_window.model = model
	add_child(players_window)
	death_screen = DeathScreen.new()
	death_screen.model = model
	add_child(death_screen)
	space_map = SpaceMap.new()
	space_map.model = model
	space_map.close_requested.connect(func() -> void: open_space_map(false))
	space_map.show_place.connect(show_place)
	add_child(space_map)
	# Full screen where the map view is, under the HUD and the Remote view frame, as Factorio's.
	move_child(space_map, map_view.get_index() + 1)
	map_view.space_map_requested.connect(func() -> void: open_space_map(true))
	networks = NetworksWindow.new()
	networks.model = model
	networks.close_requested.connect(func() -> void: networks.open(false))
	networks.show_at.connect(_look_on_surface)
	add_child(networks)

	bonuses = BonusesWindow.new()
	alerts_config = AlertsConfig.new()
	achievements = AchievementsWindow.new()
	permissions = PermissionsWindow.new()
	tips = TipsWindow.new()
	for w in [bonuses, alerts_config, achievements, permissions, tips]:
		w.model = model
		add_child(w)
	alerts_config.alerts = alerts
	alerts_config.apply()

	pedia = Factoriopedia.new()
	pedia.model = model
	pedia.close_requested.connect(func() -> void: pedia.open(false))
	var to_tech := func(tech: String) -> void:
		pedia.open(false)
		open_research(true)
		research.select(tech)
	pedia.open_technology.connect(to_tech)
	add_child(pedia)
	chat.gps.connect(_on_gps)
	Slot.info = item_info
	model.inventory_changed.connect(_prefetch_items)

	picker = ItemPicker.new()
	picker.items = func() -> Array: return _protos().item_names.values() if _protos() != null else []
	picker.fluids = func() -> Array: return _protos().fluid_names.values() if _protos() != null else []
	picker.entities = func() -> Array:
		var out: Array = []
		if _protos() != null:
			for e in _protos().entities.values():
				if e.type in TARGET_TYPES:
					out.append(e.name)
		return out
	add_child(picker)
	planners = PlannerUi.new()
	planners.ui = self
	add_child(planners)
	move_child(picker, -1)  # the item chooser over the planner windows
	screen.model = model
	screen.picker = picker
	screen.held_item = held_item
	screen.stop_names = stop_names
	screen.open_stats = func(kind: String, target: Dictionary) -> void: stats.toggle(kind, target)
	screen.remote_follow = remote_follow
	chat.console.open_window = open_global
	chat.console.rcon = func(command: String) -> String:
		if not run_command.is_valid():
			return ""
		return await run_command.call(command)
	chat.console.has_rcon = func() -> bool: return has_rcon.is_valid() and bool(has_rcon.call())

	cursor = CursorStack.new()
	add_child(cursor)

	Settings.listen(_on_setting)
	_apply_settings()
	if bool(Settings.get_value("interface", "alt_mode")):
		set_alt_mode.call_deferred(true)

	for arg in OS.get_cmdline_user_args():
		if arg == "--ui=inventory":
			window.open_crafting(true)
		elif arg == "--ui=armor":  # the armour's grid open beside the inventory
			window.open_crafting(true)
			window.open_armor(true)
		elif arg == "--ui=character":  # the character window's Character tab
			window.open_crafting(true)
			window.show_tab.call_deferred("Character")
		elif arg == "--ui=shortcut-chooser":  # the shortcut bar's ⋮ chooser
			get_tree().create_timer(3.0).timeout.connect(func() -> void: shortcuts.open_chooser(true))
		elif arg == "--ui=page-chooser":  # the quickbar's page chooser (the lower row's)
			get_tree().create_timer(3.0).timeout.connect(func() -> void: quickbar.open_chooser(1, true))
		elif arg == "--ui=players":
			players_window.toggle.call_deferred()
		elif arg == "--ui=map":
			open_map.call_deferred(true)
		elif arg == "--ui=research":
			open_research.call_deferred(true)
		elif arg == "--ui=space":
			get_tree().create_timer(3.0).timeout.connect(func() -> void: open_space_map(true))
		elif arg == "--ui=space-platform":  # the space map with the first platform selected
			var pick := func() -> void:
				open_space_map(true)
				if space_map.platforms != null and not space_map.platforms.platforms.is_empty():
					space_map.select(int(space_map.platforms.platforms.keys()[0]))
			get_tree().create_timer(3.0).timeout.connect(pick)
		elif arg == "--ui=networks":
			get_tree().create_timer(2.0).timeout.connect(func() -> void: networks.open(true))
		elif arg.begins_with("--pedia="):
			var spec := arg.get_slice("=", 1)
			get_tree().create_timer(4.0).timeout.connect(func() -> void: open_pedia(spec.get_slice(":", 0), spec.get_slice(":", 1)))
		elif arg.begins_with("--research="):
			var tech := arg.get_slice("=", 1)
			get_tree().create_timer(4.0).timeout.connect(func() -> void: research.select(tech))
		elif arg in ["--ui=bonuses", "--ui=alerts", "--ui=achievements", "--ui=permissions", "--ui=tips"]:
			var which := arg.get_slice("=", 1)
			get_tree().create_timer(2.0).timeout.connect(func() -> void: open_global(which))
		elif arg == "--ui=trains":
			trains_window.open.call_deferred(true)
		elif arg == "--ui-sample":
			_load_sample()
		elif arg.begins_with("--ui-hover="):
			var xy := arg.get_slice("=", 1)
			_hover_at = Vector2(float(xy.get_slice(",", 0)), float(xy.get_slice(",", 1)))
			get_tree().create_timer(5.0).timeout.connect(_hover)
		elif arg.begins_with("--ui-hover-unit="):
			# Screenshots of the entity info: the mouse is taken to be over that entity wherever it is drawn.
			_hover_unit = int(arg.get_slice("=", 1))
			get_tree().create_timer(5.0).timeout.connect(_hover)
		elif arg.begins_with("--ui-press="):
			# Screenshots of popups (tools/ui_reference/ours.py): presses the named control after 7 s.
			var target := arg.get_slice("=", 1)
			get_tree().create_timer(7.0).timeout.connect(func() -> void: _debug_press(target))
		elif arg.begins_with("--ui-hold="):
			var item := arg.get_slice("=", 1)
			get_tree().create_timer(4.0).timeout.connect(func() -> void: _debug_hold(item))
		elif arg == "--map":
			open_map.call_deferred(true)
		elif arg.begins_with("--map-surface="):  # the map's surface switcher, after 6 s (screenshots)
			var si := int(arg.get_slice("=", 1))
			get_tree().create_timer(6.0).timeout.connect(func() -> void: map_view.show_surface(si))
		elif arg.begins_with("--remote-surface="):  # that surface's world in the remote view, after 6 s (screenshots)
			var rsi := int(arg.get_slice("=", 1))
			var look := func() -> void:
				open_map(true)
				map_view.show_surface(rsi)
				_zoom_into_world(Vector2.ZERO)
			get_tree().create_timer(6.0).timeout.connect(look)
		elif arg.begins_with("--map-zoom="):
			map_view.zoom = clampf(float(arg.get_slice("=", 1)), MapView.MIN_ZOOM, MapView.MAX_ZOOM)
		elif arg.begins_with("--map-tag="):
			var parts := arg.get_slice("=", 1).split(",", true, 3)
			if parts.size() == 4:
				var add := func() -> void: model.add_map_tag(Vector2(float(parts[0]), float(parts[1])), parts[3], "item", parts[2])
				get_tree().create_timer(3.0).timeout.connect(add)
		elif arg.begins_with("--map-edit="):
			var xy := arg.get_slice("=", 1)
			var edit := func() -> void: map_view.edit_tag_at(Vector2(float(xy.get_slice(",", 0)), float(xy.get_slice(",", 1))))
			get_tree().create_timer(5.0).timeout.connect(edit)
		elif arg.begins_with("--remote="):
			var at := Vector2(float(arg.get_slice("=", 1).get_slice(",", 0)), float(arg.get_slice("=", 1).get_slice(",", 1)))
			get_tree().create_timer(3.0).timeout.connect(func() -> void: remote_view(at))
		elif arg == "--ui-circuit":  # the open entity's circuit connection window, after 8 s (screenshots)
			var circuit := func() -> void:
				var b: Button = screen.circuit_dock.circuit_button
				if b != null and b.visible:
					b.button_pressed = true
			get_tree().create_timer(8.0).timeout.connect(circuit)
		elif arg == "--alt-mode":
			get_tree().create_timer(3.0).timeout.connect(func() -> void: set_alt_mode(true))
		elif arg.begins_with("--stats="):
			var kind := arg.get_slice("=", 1)
			get_tree().create_timer(3.0).timeout.connect(func() -> void: stats.toggle(kind))
		elif arg.begins_with("--chat="):
			var text := arg.get_slice("=", 1)
			var say := func() -> void:
				model.say(text)
				chat.open()
			get_tree().create_timer(3.0).timeout.connect(say)
		elif arg.begins_with("--ui-craft="):
			var spec := arg.get_slice("=", 1)
			var craft := func() -> void: model.craft(spec.get_slice(":", 0), maxi(1, int(spec.get_slice(":", 1))))
			get_tree().create_timer(3.0).timeout.connect(craft)


func _process(_delta: float) -> void:
	_follow_remote()
	# Before the minimap's own _process (children run after their parent).
	minimap.look_at = minimap_look()
	minimap.map_asks = map_view.is_open()
	if _hovering:
		if _hover_unit > 0:
			_follow_hover_unit()
		_push_hover()
	var held := held_item()
	_check_hand(held)
	quickbar.set_held(held)
	# Factorio marks only a stack picked up whole (not a split, nor a one-item stack's right click).
	var hand_slot := [hand["role"], hand["index"], int(hand["n"])] if not hand.is_empty() and hand["role"] != "grid" and not hand.get("nohand", false) else []
	window.set_hand_slot(hand_slot if not hand_slot.is_empty() and not MACHINE_ROLES.has(hand["role"]) else [])
	screen.set_hand_slot(hand_slot if not hand_slot.is_empty() and MACHINE_ROLES.has(hand["role"]) else [])
	Slot.spreading = not _spread.is_empty()
	cursor.item = held
	_grey_undo()
	var tool = player.get("cursor_tool") if player != null else null
	cursor.count = hand_count() if tool == null or str(tool) == "" else -1
	cursor.over_gui = mouse_over_gui()
	alt_overlay.player = player
	entity_info.player = player
	alerts.player = player
	research_hud.visible = research_hud.get_meta("enabled", true)
	side_menu.set_muted(not bool(FxSettings.enabled.get("master", true)))
	shortcuts.set_on("alt", alt_mode)
	_update_equipment_shortcuts()
	_show_held_equipment(held)
	if status_label != null:
		status_label.visible = debug_overlay or not Bridge.world_ready
	_networks_in_remote()
	remote_frame.networks_open = networks.is_open()
	_update_space_frame()
	# From a hub the platform is just there, with its panel: no "Remote view" frame over it.
	remote_frame.show_for("map" if map_view.is_open() else ("space" if space_map.is_open() else ("world" if remote and not _at_hub() else "")))
	layout()
	# After layout(): the minimap has been put in its place for this frame.
	# Without the minimap, a rect of no height where its place begins: the column starts there.
	var slot := side_menu.minimap_slot.get_global_rect()
	remote_frame.right_column = minimap.get_global_rect() if minimap.visible else Rect2(slot.position, Vector2(slot.size.x, 0.0))
	var side_grid := side_menu.button("blueprint_library").get_parent() as Control if side_menu.button("blueprint_library") != null else null
	remote_frame.buttons_rect = side_grid.get_global_rect() if side_grid != null else Rect2()


## Places the HUD around the edges as Factorio does: the quickbar bottom centre with the weapon
## slots left of it and the shortcut bar right of it, the alerts over the shortcut bar, the side
## menu (research, buttons, minimap) flush in the top-right corner with the platform panel (on a
## platform) and the entity info under it, and top left the debug line. The weapon slots and the
## shortcut bar shrink (the shortcut bar first wraps) when the window is too small for them at the
## UI scale. The help goes in what is left on
## the left side. Runs every frame; the measuring is cached.
func layout() -> void:
	var m := float(Kit.px(MARGIN))
	var view := size
	# Factorio's bottom bar: the tool bar in the corner, the quickbar QUICKBAR_LEFT GUI pixels left of
	# the centre (where 2.1 puts it at 1920x1080), the shortcut bar right beside it. When the window
	# is too narrow the quickbar keeps clear of the tool bar, which shrinks.
	weapons.scale = Vector2.ONE
	weapons.reset_size()
	quickbar.set_two_rows(view.y >= Kit.px(TWO_ROWS_HEIGHT))
	quickbar.reset_size()
	var qw := quickbar.size.x
	var want := view.x * 0.5 - Kit.px(QUICKBAR_LEFT)
	quickbar.global_position.y = view.y - quickbar.size.y  # its height changes with the bars over it
	quickbar.global_position.x = clampf(maxf(want, minf(weapons.size.x + Kit.px(BAR_GAP), (view.x - qw) * 0.5)), 0.0, maxf(0.0, view.x - qw))
	var bar := quickbar.frame.get_global_rect()
	var bottom := quickbar.get_global_rect()
	if window != null:  # entity and character windows centre above the HUD, as Factorio does
		window.set_bottom_room(view.y - bar.position.y)
	var f := clampf((bar.position.x - Kit.px(BAR_GAP)) / maxf(1.0, weapons.size.x), 0.1, 1.0)
	weapons.scale = Vector2(f, f)
	weapons.global_position = Vector2(0.0, view.y - weapons.size.y * f)
	var arms := weapons.get_global_rect()
	chat.right_edge = bar.end.x  # Factorio's open console reaches the quickbar's right edge

	# Top right, flush with the corner: research, the side menu's buttons, the minimap.
	# The minimap's side from its setting, not its Control's size: that lags a frame behind the
	# offsets set below, which left the frame up and to the left of its place.
	var mm_side := minimap.side_px()
	side_menu.set_minimap_side(mm_side if minimap.visible else 0.0)
	side_menu.reset_size()
	# In the remote view Factorio moves the corner down under the frame's title bar.
	var corner_top := float(Kit.px(RemoteFrame.TITLE_HEIGHT + RemoteFrame.BORDER)) if remote_frame != null and remote_frame.visible else 0.0
	side_menu.global_position = Vector2(view.x - side_menu.size.x - (Kit.px(RemoteFrame.BORDER) if corner_top > 0.0 else 0), corner_top)
	if minimap.visible:  # a short window: the minimap shrinks to stay above the quickbar
		var room := floorf(bottom.position.y - m - side_menu.minimap_slot.get_global_rect().position.y)
		if room != minimap.max_side:
			minimap.set_max_side(room)
			mm_side = minimap.side_px()
			side_menu.set_minimap_side(mm_side)
			side_menu.reset_size()
	if minimap.visible:
		var place := side_menu.minimap_slot.get_global_rect()
		minimap.offset_left = place.position.x + floorf((place.size.x - mm_side) * 0.5) - view.x
		minimap.offset_right = minimap.offset_left + mm_side
		minimap.offset_top = place.position.y
		minimap.offset_bottom = place.position.y + mm_side
	var mini := side_menu.get_global_rect()
	# On a platform its speed and journey sit right under the minimap, as Factorio 2.x has them (F2);
	# when that leaves no room for the shortcut bar (a short window, a big UI scale), beside it.
	var under := mini.end.y
	var right_edge := mini.position.x  # where the top-right corner's pieces begin
	if platform_panel != null and is_instance_valid(platform_panel):
		platform_panel.custom_minimum_size.x = mini.size.x  # as wide as the column over it, as Factorio's
		platform_panel.reset_size()
		var ps := platform_panel.size
		if mini.end.y + ps.y + Kit.px(SHORTCUTS_MIN_HEIGHT) <= bar.position.y - m:
			platform_panel.global_position = Vector2(view.x - ps.x, mini.end.y)
			if platform_panel.visible:
				under = mini.end.y + ps.y
		else:
			platform_panel.global_position = Vector2(mini.position.x - ps.x - m, mini.position.y)
			if platform_panel.visible:
				right_edge = platform_panel.global_position.x
	var right := Rect2(bar.end.x + Kit.px(BAR_GAP), under + m, view.x - m - bar.end.x - Kit.px(BAR_GAP), bar.end.y - under - m)
	if right != _shortcuts_room or shortcuts.shown_count() != _shortcuts_shown:
		_shortcuts_room = right
		_shortcuts_shown = shortcuts.shown_count()
		_fit_shortcuts(right)
	shortcuts.reset_size()
	var sf := shortcuts.scale.x
	shortcuts.global_position = Vector2(right.position.x, bar.end.y - shortcuts.size.y * sf)
	var keys := shortcuts.get_global_rect()
	alerts.scale = shortcuts.scale
	alerts.reset_size()
	var alerts_w := alerts.size.x * sf
	alerts.global_position = Vector2(clampf(keys.end.x - alerts_w, m, view.x - m - alerts_w), keys.position.y - Kit.px(4) * sf - alerts.size.y * sf)
	var info_top := under  # flush under the side menu (and the platform panel), as Factorio
	if map_open() and map_view.panel.is_visible_in_tree():
		info_top = map_view.panel.get_global_rect().end.y + m  # under the map view's settings, not over them
	if remote_frame != null and remote_frame.info_panel.is_visible_in_tree():
		info_top = maxf(info_top, remote_frame.info_panel.get_global_rect().end.y + m)  # and a platform's panel
	entity_info.global_position = Vector2(view.x - entity_info.size.x, info_top)

	# The crafting queue right of the tool bar along the bottom, as Factorio has it, or over the tool
	# bar when it would run into the quickbar.
	craft_queue.reset_size()
	if arms.end.x + m + craft_queue.size.x <= bar.position.x - m:
		craft_queue.global_position = Vector2(arms.end.x + m, view.y - Kit.px(4) - craft_queue.size.y)
	else:  # over the tool bar (and over the driving line on the quickbar when it reaches that far)
		var top := arms.position.y
		if m + craft_queue.size.x > bar.position.x:
			top = minf(top, bottom.position.y - maxf(Kit.px(18), cursor_label.size.y if cursor_label != null else 0.0) - Kit.px(2))
		craft_queue.global_position = Vector2(m, top - m - craft_queue.size.y)
	var queue := craft_queue.get_global_rect() if craft_queue.visible and craft_queue.size.y > 0.0 else Rect2()
	var low := minf(arms.position.y, queue.position.y) if queue.has_area() else arms.position.y
	# The driving line just over the quickbar; its line is kept free even while it is empty.
	var line := float(Kit.px(18))
	if cursor_label != null:
		cursor_label.reset_size()
		line = maxf(line, cursor_label.size.y)
		cursor_label.global_position = Vector2(bar.position.x, bottom.position.y - Kit.px(2) - line)
	var driving := Rect2(bar.position.x, bottom.position.y - Kit.px(2) - line, bar.size.x, line)

	# Top left, under the debug line when it shows.
	var y := m
	if status_label != null and status_label.visible:
		y = status_label.get_global_rect().end.y + Kit.px(4)

	if help_label != null:
		var w := minf(Kit.px(HELP_WIDTH), right_edge - 2.0 * m)
		var room := Rect2(m, y, w, low - m - y)
		for r: Rect2 in [bottom, driving, keys, alerts.get_global_rect()]:
			if r.has_area() and r.position.x < room.end.x:
				room.size.y = minf(room.size.y, r.position.y - m - room.position.y)
		_fit_help(room)
		# Factorio has no such panel: it never sits under a window (the windows centre over its place).
		help_label.visible = bool(Settings.get_value("interface", "show_help")) and not is_open()


## The shortcut bar's columns and scale for the space right of the quickbar, keeping a row of
## alerts' height over it: as big as possible, then with as few rows as possible.
func _fit_shortcuts(room: Rect2) -> void:
	var alert_h := float(Kit.px(Kit.SLOT) + Kit.px(4))
	var best := -1.0
	var best_cols := 5
	var best_rows := 2
	for cols in range(2, ShortcutBar.SHORTCUTS.size() + 1):
		shortcuts.set_columns(cols)
		var need := shortcuts.get_combined_minimum_size()
		var fit := minf(1.0, minf(room.size.x / need.x, room.size.y / (need.y + alert_h)))
		var rows := ceili(float(shortcuts.shown_count()) / cols)
		# As big as possible, then Factorio's two rows (the quickbar's height), then the fewest
		# columns (3x3 rather than 4+4+1).
		var better := fit > best + 0.001
		if absf(fit - best) <= 0.001:
			better = absi(rows - 2) < absi(best_rows - 2) or (rows == best_rows and cols < best_cols)
		if better:
			best = fit
			best_rows = rows
			best_cols = cols
	shortcuts.set_columns(best_cols)
	shortcuts.scale = Vector2.ONE * clampf(best, 0.1, 1.0)


## The help in `room`: its width, the font smaller when it doesn't fit, then only its first lines
## (the first says how to hide it). Too little room hides it, leaving F1's visibility alone.
func _fit_help(room: Rect2) -> void:
	if not help_label.has_meta("full_text"):
		help_label.set_meta("full_text", help_label.text)
	var full := str(help_label.get_meta("full_text"))
	var key := [room, full]
	if key == _help_fit:
		help_label.global_position = room.position
		return
	_help_fit = key
	var w := floorf(room.size.x)
	var lines := full.split("\n")
	var font := Kit.px(10)
	var fits := false
	if w >= Kit.px(120):
		for fs in [13, 12, 11, 10]:
			font = Kit.px(fs)
			if _help_height(full, w, font) <= room.size.y:
				fits = true
				break
		while not fits and lines.size() > 1:
			lines.resize(lines.size() - 1)
			fits = _help_height("\n".join(lines), w, font) <= room.size.y
	help_label.self_modulate.a = 1.0 if fits else 0.0
	help_label.text = "\n".join(lines)
	help_label.add_theme_font_size_override("font_size", font)
	help_label.size = Vector2(w, 0.0)
	help_label.get_line_count()  # shapes it, so the size below is the text's
	help_label.update_minimum_size()
	help_label.size = Vector2(w, 0.0)
	help_label.global_position = room.position


## How tall the help is with this text, width and font size.
func _help_height(text: String, w: float, font: int) -> float:
	help_label.text = text
	help_label.add_theme_font_size_override("font_size", font)
	help_label.size = Vector2(w, help_label.size.y)
	var n := help_label.get_line_count()
	var spacing := help_label.get_theme_constant("line_spacing")
	return n * (help_label.get_line_height() + spacing) - spacing + help_label.get_theme_stylebox("normal").get_minimum_size().y


func held_item() -> String:
	return str(player.cursor_item) if player != null else ""


## How many the cursor holds: the picked-up stack (or the part of it), else all in the inventory.
func hand_count() -> int:
	var held := held_item()
	if held == "":
		return -1
	if player.get("cursor_slot") != null and int(player.cursor_slot) == -1:
		return 1  # taken from the library: the mod's cursor stack, not the inventory
	if not hand.is_empty():
		if hand["role"] == "grid":
			return 1
		var stack := _stack(hand["role"], int(hand["index"]))
		if stack.get("item", "") == held:
			var n := int(stack["count"])
			return mini(n, int(hand["n"])) if int(hand["n"]) > 0 else n
	return model.count_of(held)


## Building from the cursor uses the character's main inventory, so a stack picked up from a
## machine is only moved, not built.
func can_build_from_hand() -> bool:
	return hand.is_empty() or hand["role"] == "main"


## Where the mouse is (or --ui-hover's point, for screenshots).
func mouse_position() -> Vector2:
	return _hover_at if _hovering else get_viewport().get_mouse_position()


## The mouse is over a window, slot or button rather than the world.
func mouse_over_gui() -> bool:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		return false
	return get_viewport().gui_get_hovered_control() != null


## When the cursor's item changed elsewhere (quickbar, Q) the hand is forgotten; when its slot was
## used up, it moves to another stack of the item, as Factorio refills the cursor.
func _check_hand(held: String) -> void:
	if hand.is_empty():
		return
	if hand["role"] == "grid":
		# Equipment picked up from a grid stays in the cursor while it is still there.
		if held == "" or model.equipment_at(str(hand["kind"]), hand["cell"]).get("name", "") != held:
			hand = {}
		return
	if MACHINE_ROLES.has(hand["role"]) and not screen.is_open():
		_drop_hand()
		return
	if hand.has("merge"):
		# A click put the held stack onto a stack of the same item: what didn't fit stays in the
		# cursor, as in Factorio. The mod answers with the target's new count.
		var target: Array = hand["merge"]
		var now := int(_stack(target[0], int(target[1])).get("count", 0))
		if now != int(hand["before"]):
			var fitted := now - int(hand["before"])
			hand.erase("merge")
			if int(hand["n"]) > 0:
				hand["n"] = int(hand["n"]) - fitted
				if int(hand["n"]) <= 0:
					_drop_hand()
					return
			elif _stack(hand["role"], int(hand["index"])).get("item", "") != held:
				_drop_hand()  # all of it fitted
				return
		elif Time.get_ticks_msec() - int(hand["at"]) > 3000:
			hand.erase("merge")  # nothing fitted (the target was full): the cursor keeps it all
	if held == "" or (hand["role"] != "main" and _stack(hand["role"], int(hand["index"])).get("item", "") != held):
		hand = {}
		return
	if hand["role"] == "main" and model.stack_at("main", int(hand["index"])).get("item", "") != held:
		hand = {}
		for i in model.main_slots.size():
			if model.main_slots[i].get("item", "") == held:
				hand = {"role": "main", "index": i + 1, "n": 0, "unit": 0}
				break


func _stack(role: String, index: int) -> Dictionary:
	return screen.stack_at(role, index) if MACHINE_ROLES.has(role) else model.stack_at(role, index)


func _knows_slots(role: String) -> bool:
	return screen.knows_slots(role) if MACHINE_ROLES.has(role) else model.knows_slots(role)


## E with nothing hovered: Factorio's inventory, or closes whatever is open.
func toggle_inventory() -> void:
	if is_open():
		close_all()
	else:
		window.open_crafting(true)


func open_research(on: bool) -> void:
	if on:
		if screen.unit != 0:
			screen.close()
		window.open_crafting(false)
	research.open(on)


func is_open() -> bool:
	return window.is_open() or research.is_open() or stats.is_open() or trains_window.is_open() or players_window.visible or planners.is_open() or space_map.is_open() or pedia.is_open() or networks.is_open() 		or bonuses.is_open() or alerts_config.is_open() or achievements.is_open() or permissions.is_open() or tips.is_open()


## Opens (or closes) one of Factorio's game-wide windows by name: "bonuses", "alerts" (the alerts
## configuration), "achievements", "permissions", "tips". Factorio opens them from its side menu
## (permissions from its /permissions command). One at a time, as in Factorio.
func open_global(which: String) -> void:
	var windows := {"bonuses": bonuses, "alerts": alerts_config, "achievements": achievements, "permissions": permissions, "tips": tips}
	for other in windows:
		if other != which and windows[other].is_open():
			windows[other].open(false)
	var w = windows.get(which)
	if w != null:
		w.toggle()


## Typing in a text field (the chat, a search): the keys aren't controls.
func typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


## Settings → Interface → In the game: which HUD parts show.
func _apply_settings() -> void:
	shortcuts.visible = bool(Settings.get_value("interface", "shortcut_bar"))
	shortcuts.set_on("tall", bool(Settings.get_value("interface", "hide_tall")))
	research_hud.set_meta("enabled", bool(Settings.get_value("interface", "research_progress")))
	research_hud._refresh()
	entity_info.set_meta("enabled", bool(Settings.get_value("interface", "entity_info")))
	alerts.visible = bool(Settings.get_value("interface", "alerts"))


func _on_setting(section: String, key: String) -> void:
	if section == "interface" and is_inside_tree():
		_apply_settings()


func _exit_tree() -> void:
	Settings.unlisten(_on_setting)


## Alt-mode on or off (Alt, or the shortcut); remembered in the settings, like Factorio's.
func set_alt_mode(on: bool) -> void:
	if on != alt_mode:
		Settings.set_value("interface", "alt_mode", on)
	alt_mode = on
	alt_overlay.on = on
	alt_overlay.queue_redraw()
	model.set_alt_mode(on)
	alt_mode_changed.emit(on)


## Alt+L: the character's logistic requests on or off (needs the logistics data from
## claude/cloud-logistics; ui_model.char_requests_on).
func toggle_personal_logistics() -> void:
	var on = model.get("char_requests_on")
	if on == null:
		Bridge.send({"t": "set_char_requests", "on": 0})
		return
	Bridge.send({"t": "set_char_requests", "on": 0 if on else 1})


## The hovered entity for the info panel (player_input.gd, every frame), or null.
func set_selected(r) -> void:
	entity_info.show_entity(r if entity_info.get_meta("enabled", true) else null)


func entity_name(name: String) -> String:
	return Kit.entity_name(name)


## The world's prototypes (player_input.gd's world mirror), or null before the game is built.
func _protos():
	var world = player.get("world") if player != null else null
	return world.protos if world != null else null


## Names of the train stops in the loaded chunks, for adding schedule records.
func stop_names() -> Array:
	var world = player.get("world") if player != null else null
	var names: Array = []
	if world == null:
		return names
	for r in world.entities.values():
		if r.extra.has("n") and not names.has(str(r.extra["n"])):
			names.append(str(r.extra["n"]))
	names.sort()
	return names


## The side menu's buttons (top right) open what Factorio's open; windows the client doesn't have
## yet say so.
func _on_side_button(name: String) -> void:
	match name:
		"blueprint_library":
			planners.toggle_library()
		"production":
			stats.toggle("item")
		"factoriopedia":
			pedia.open(not pedia.is_open())
		"trains":
			trains_window.open(not trains_window.is_open())
		"logistic_networks":
			networks.toggle()
		"mute":
			FxSettings.set_enabled("master", not bool(FxSettings.enabled.get("master", true)))
		"bonuses", "achievements", "alerts", "tips":
			open_global(name)
		_:
			if has_method("open_" + name):  # windows added by other parts of the UI
				call("open_" + name)
			else:
				hud_message("%s isn't in the 3D client yet" % SideMenu.BUTTONS.filter(func(b: Array) -> bool: return b[0] == name)[0][2])


## Factorio greys undo and redo while there is nothing to undo or redo.
func _grey_undo() -> void:
	if player == null or shortcuts == null:
		return
	for pair in [["undo", "_undo"], ["redo", "_redo"]]:
		var b := shortcuts.button(pair[0])
		var stack = player.get(pair[1])
		if b != null and stack is Array:
			b.disabled = (stack as Array).is_empty()


## The shortcut bar's buttons do what their keys do.
func _on_shortcut(name: String) -> void:
	if player == null:
		return
	match name:
		"undo":
			player.undo()
		"redo":
			player.redo()
		"copy", "cut", "blueprint", "decon", "copper-wire", "red-wire", "green-wire":
			player.hold_tool(name)
		"paste":
			if model.clipboard.is_empty():
				return
			player.hold_tool("paste")
		"upgrade":
			if model.count_of("upgrade-planner") > 0:
				player.hold("upgrade-planner")
			else:
				planners.give_new("upgrade_planner")
		"import":
			planners.show_string("import", "")
		"book":
			planners.give_new("blueprint_book")
		"alt":
			set_alt_mode(not alt_mode)
		"tall":  # Factorio's tall-entities toggle: tall_fade.gd fades the ones in the way
			Settings.set_value("interface", "hide_tall", not bool(Settings.get_value("interface", "hide_tall")))
		"spidertron":
			player.hold_tool("spidertron")
		"artillery", "discharge":
			hud_message("Remotes aren't in the 3D client yet")
		"roboport":
			toggle_personal_roboport()
		"exoskeleton":
			toggle_equipment_movement()


## Factorio's space map (the solar system, platforms and routes), full screen in the remote view.
## The platform panel and the Surfaces panel's "Space map" open it.
func open_space_map(on: bool) -> void:
	if platform_panel != null and is_instance_valid(platform_panel):
		space_map.platforms = platform_panel
	if on == space_map.is_open():
		return
	if on:
		if remote:
			end_remote_view()
		map_view.open(false)
	space_map.open(on)
	minimap.set_map_open(on)


## The remote view frame around the space map and the map: the Surfaces panel's "Space map" row,
## the platforms' planets, and the panel of the platform selected (or shown).
func _update_space_frame() -> void:
	var panel_ok := platform_panel != null and is_instance_valid(platform_panel) and platform_panel.get("platforms") is Dictionary
	if panel_ok and map_view.platforms != platform_panel:
		map_view.platforms = platform_panel
		space_map.platforms = platform_panel
		map_view.refresh_surfaces()
	map_view.set_space_open(space_map.is_open())
	var info := {}
	if space_map.is_open() and space_map.selected != 0 and space_map.platforms != null:
		info = space_map.platforms.platforms.get(space_map.selected, {})
	elif map_view.is_open():
		info = map_view.shown_platform()
	remote_frame.platform_info = info
	var pp = platform_panel  # main.gd's platform_panel.gd (untyped: tests put stand-ins here)
	if panel_ok and pp.has_method("watch"):
		pp.watch(_watched_platform())
		# On board, the frame's panel drops to a planet through the HUD's (one planned drop).
		var pi = remote_frame.info_panel
		remote_frame.platform_board = int(pp.on) != 0 and int(info.get("i", 0)) == int(pp.on)
		pi.dropping_to = pp.dropping_to if remote_frame.platform_board else ""


## The frame's panel on board: "?" its "Drop to a planet" list, a planet picked, or "" the red cross,
## through the HUD's panel (one planned drop).
func _frame_drop(planet: String) -> void:
	var pp = platform_panel
	if pp == null or not pp.has_method("drop_to"):
		return
	var pi = remote_frame.info_panel
	if planet == "?":
		pi.choose_drop([] if pi.choosing_drop() else pp.planets())
	elif planet == "":
		pp.plan_drop("")
	else:
		pi.choose_drop([])
		pp.drop_to(planet)


## The platform whose panel goes under the minimap (H3): the one the remote view shows from elsewhere,
## else the character's (-1); none (0) while the map or the space map, with panels of their own, is open.
func _watched_platform() -> int:
	if map_view.is_open() or space_map.is_open():
		return 0
	if remote and viewing_si != 0:
		for entry in model.map_surfaces:
			if int(entry["si"]) == viewing_si:
				return int(entry.get("pf", 0))
		return 0
	return -1


## A planet (by name) or platform (by index) from the space map: its surface in the map view,
## through the map's surface switcher.
func show_place(planet: String, platform: int) -> void:
	for entry in model.map_surfaces:
		if (planet != "" and str(entry["planet"]) == planet) or (platform != 0 and int(entry["pf"]) == platform):
			open_space_map(false)
			open_map(true)
			map_view.show_surface(int(entry["si"]))
			return
	hud_message("There's nothing to see there yet" if planet != "" else "That platform isn't built yet")


## M: the map view over the world (the minimap follows its view). Opening it ends a remote view.
func open_map(on: bool) -> void:
	# M in a remote view goes back to the character; in a platform's hub, which is a remote view
	# with no character to go back to, it opens the map (H8: the map couldn't open in space).
	if on and remote and not in_hub():
		end_remote_view()
		return
	map_view.open(on)
	minimap.set_map_open(space_map.is_open())  # the map view keeps the minimap, following it (H22)


## Where the minimap looks (H22), as Factorio's does: the map view's middle while it is open, the 3D
## remote view's point on the character's surface (another surface's world isn't the map's), else
## the character (Vector2.INF).
func minimap_look() -> Vector2:
	if map_view.is_open():
		return map_view.centre
	if remote and viewing_si == 0 and _remote_anchor != null:
		return Vector2(_remote_anchor.position.x, _remote_anchor.position.z)
	return Vector2.INF


## Factorio 2.0's remote view: the camera goes to a point of the map and the world loads around it
## (the client subscribes to chunks around wherever the camera looks).
func remote_view(at: Vector2) -> void:
	var rig = player.get("rig") if player != null else null
	if rig == null:
		return
	if _remote_anchor == null:
		_remote_anchor = Node3D.new()
		_remote_anchor.name = "RemoteView"
		rig.get_parent().add_child(_remote_anchor)
	_remote_anchor.position = Vector3(at.x, 0.0, at.y)
	rig.global_position = _remote_anchor.position
	rig.target = _remote_anchor
	rig.set("in_remote", true)
	remote = true
	map_view.open(false)
	minimap.set_map_open(false)


## Remote view that keeps a mover (a train's front, a vehicle) in the middle until the view is
## panned or left, as Factorio's train window does when its camera is clicked.
func remote_follow(unit: int, at: Vector2) -> void:
	remote_view(at)
	_remote_follow = unit


func _follow_remote() -> void:
	if not remote or _remote_follow == 0 or _remote_anchor == null:
		return
	var movers = player.get("movers") if player != null else null
	var at = movers.position_of(_remote_follow) if movers != null else null
	if at is Vector3:
		_remote_anchor.position = Vector3(at.x, 0.0, at.z)


## Zoomed in past the map's closest level: the world there, seen from Factorio's own angle (F6),
## as the map hands over to the game's view in Factorio. Leaving the remote view
## puts the camera back as it was.
func _zoom_into_world(at: Vector2) -> void:
	# Another surface's map: the mod streams that surface's world while the remote view is on it.
	var si: int = model.map_si
	if si > 0 and si != model.character_si:
		viewing_si = si
		Bridge.send({"t": "view", "si": si, "x": roundi(at.x * 256), "y": roundi(at.y * 256)})
	remote_view(at)
	var rig = player.get("rig") if player != null else null
	if remote and rig != null and rig.has_method("in_factorio_view") and not rig.in_factorio_view():
		rig.toggle_factorio_view()
		_map_factorio_view = true
	# Zooming back out goes to the map again (issue #4), at Settings > Camera > Zoom out to the map at
	# (240 tiles by default; it was four times the opening distance, capped by Furthest zoom at 140).
	if remote and rig != null and "map_handoff_distance" in rig:
		var opened := float(rig.get("_distance_goal"))
		rig.map_handoff_distance = maxf(float(Settings.get_value("camera", "map_zoom_out")), opened * 1.5)
		if not rig.zoomed_out_to_map.is_connected(_zoom_out_to_map):
			rig.zoomed_out_to_map.connect(_zoom_out_to_map)


func _zoom_out_to_map() -> void:
	# In a hub the remote view stays round the hub and the map opens over it.
	if not remote:
		return
	var si := viewing_si
	var at := Vector2(_remote_anchor.position.x, _remote_anchor.position.z) if _remote_anchor != null else Vector2.INF
	end_remote_view()
	open_map(true)
	if at != Vector2.INF:
		map_view.return_from_world(si, at)


## The character is inside a platform's hub at `at` (ride.gd): the remote view there, for good.
func enter_hub(at: Vector2) -> void:
	hub_at = at
	remote_view(at)


func leave_hub() -> void:
	if hub_at == Vector2.INF:
		return
	hub_at = Vector2.INF
	end_remote_view()


func in_hub() -> bool:
	return hub_at != Vector2.INF


func end_remote_view() -> void:
	# In a hub there is no character to go back to: back to the hub instead.
	if hub_at != Vector2.INF:
		if viewing_si != 0:
			viewing_si = 0
			Bridge.send({"t": "view", "si": 0})
		_remote_follow = 0
		if _remote_anchor != null:
			_remote_anchor.position = Vector3(hub_at.x, 0.0, hub_at.y)
		return
	_remote_follow = 0
	if viewing_si != 0:
		viewing_si = 0
		Bridge.send({"t": "view", "si": 0})
	var rig = player.get("rig") if player != null else null
	if rig != null:
		rig.target = player.get("avatar")
		rig.set("in_remote", false)
		rig.set("map_handoff_distance", INF)
		if _map_factorio_view and rig.has_method("leave_factorio_view"):
			rig.leave_factorio_view()
	_map_factorio_view = false
	remote = false
	_remote_label.visible = false


## WASD while in remote view: moves the view (tiles).
func pan_remote(by: Vector2) -> void:
	_remote_follow = 0
	if _remote_anchor != null:
		_remote_anchor.position += Vector3(by.x, 0.0, by.y)


func map_open() -> bool:
	return map_view.is_open()


## [position (tiles), heading (radians clockwise from north)] of the character, for the maps.
func character_on_map() -> Array:
	var avatar = player.get("avatar") if player != null else null
	if avatar is Node3D:
		var a := avatar as Node3D
		return [Vector2(a.position.x, a.position.z), -a.rotation.y]
	return [Vector2.ZERO, 0.0]


## Closes the character window, any machine screen, the technology screen and statistics (E,
## Esc, ×).
func close_all() -> void:
	if screen.unit != 0:
		screen.close()
	window.open_crafting(false)
	research.open(false)
	stats.visible = false
	trains_window.open(false)
	players_window.visible = false
	planners.close_all()
	open_space_map(false)
	pedia.open(false)
	networks.open(false)
	for w in [bonuses, alerts_config, achievements, permissions, tips]:
		w.open(false)
	picker.close()


## Esc: closes the topmost thing the HUD has open (a chooser, the chat, a blueprint window, the
## map, the remote view, the windows). False when nothing was open, so Esc opens the game menu.
## front_end.gd asks this first: it gets Esc before the HUD does.
func escape() -> bool:
	if picker.is_open():
		picker.close()
	elif shortcuts.chooser_open():
		shortcuts.open_chooser(false)
	elif quickbar.chooser_open():
		quickbar.open_chooser(0, false)
	elif chat.is_open():
		chat.close()
	elif planners.escape():
		pass
	elif map_view.escape():
		minimap.set_map_open(space_map.is_open())
	elif remote and not _at_hub():
		end_remote_view()
	elif is_open() or screen.unit != 0:
		close_all()
	else:
		return false
	return true


## In a hub with the view on it already (and the hub's surface shown): Esc goes on to the menu.
func _at_hub() -> bool:
	return hub_at != Vector2.INF and viewing_si == 0 and _remote_anchor != null 		and Vector2(_remote_anchor.position.x, _remote_anchor.position.z).distance_to(hub_at) < 1.0


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		if escape():
			get_viewport().set_input_as_handled()
		return
	var handled := true
	if Controls.pressed(event, "open_technology"):
		open_research(not research.is_open())
	elif Controls.pressed(event, "toggle_map"):
		open_map(not map_view.is_open())
	elif Controls.pressed(event, "debug_line"):
		debug_overlay = not debug_overlay
	elif Controls.pressed(event, "production_statistics"):
		stats.toggle("item")
	elif Controls.pressed(event, "kill_statistics"):
		stats.toggle("kill")
	elif Controls.pressed(event, "logistic_networks"):
		networks.toggle()
	elif Controls.pressed(event, "toggle_factoriopedia"):
		pedia.open(not pedia.is_open())
	elif Controls.pressed(event, "toggle_console"):
		chat.open(key.physical_keycode == KEY_SLASH)
	elif Controls.pressed(event, "focus_search"):
		if not window.is_open():
			window.open_crafting(true)
		window.focus_search()
	elif Controls.pressed(event, "toggle_personal_roboport"):
		toggle_personal_roboport()
	elif Controls.pressed(event, "toggle_equipment_movement_bonus"):
		toggle_equipment_movement()
	elif Controls.pressed(event, "toggle_players"):
		players_window.toggle()
	elif Controls.pressed(event, "blueprint_library"):
		planners.toggle_library()
	elif Controls.pressed(event, "rotate_quickbars"):
		model.swap_quickbars()
	else:
		handled = false
		for i in 10:
			if Controls.pressed(event, "quickbar_page_%d" % (i + 1)):
				model.select_quickbar_page(i + 1)
				handled = true
				break
			if Controls.pressed(event, "quickbar_%d" % (i + 1)):
				handled = true
				if window.is_open():
					var item := window.hovered_item if window.hovered_item != "" else held_item()
					if item != "":
						model.pin(i, item)
						break
				_select(i)
				break
	if handled:
		get_viewport().set_input_as_handled()


## Factorio's stat lines for an item's tooltip (Slot.info), from its Factoriopedia page (asked for
## the first time; the lines show from the next hover).
func item_info(item: String) -> Array:
	var d: Dictionary = model.pedia_data("item", item)
	if d.is_empty():
		return []
	return Info.item_lines(d)


## Asks for the pages of what the inventory holds, so their tooltips have the stats at once.
func _prefetch_items() -> void:
	var asked := 0
	for s in model.main_slots:
		var item := str(s.get("item", "")) if s is Dictionary else ""
		if item != "" and not model.pedia_pages.has("item/" + item) and asked < 20:
			model.pedia_page("item", item)
			asked += 1


## Factoriopedia on a thing's page (Alt+click in the world or on a window).
func open_pedia(kind: String, name: String) -> void:
	if name != "":
		pedia.open_page(kind, name)


## Alt+click on a window's slot opens its Factoriopedia page, as in Factorio (before the slot sees
## the click).
func _input(event: InputEvent) -> void:
	if not _spread.is_empty():
		var motion := event as InputEventMouseMotion
		var up := event as InputEventMouseButton
		if up != null and not up.pressed and up.button_index == int(_spread["button"]):
			_spread = {}
		elif motion != null:
			if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT if int(_spread["button"]) == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) == 0:
				_spread = {}
			else:
				var s := _slot_under(motion.position)
				if s != null:
					_spread_to(s.slot_role, s.slot_index, screen.unit if MACHINE_ROLES.has(s.slot_role) else 0)
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or not mb.alt_pressed or not mouse_over_gui():
		return
	if alt_click(get_viewport().gui_get_hovered_control()):
		get_viewport().set_input_as_handled()


## Alt+click on control `c`: the page of the slot or technology it is (or is in). False when it
## isn't one (or is a Factoriopedia link, which handles its own click).
func alt_click(c: Node) -> bool:
	while c != null:
		if c is TechSlot:
			open_pedia("technology", (c as TechSlot).tech)
			break
		if c is Slot and ((c as Slot).item != "" or (c as Slot).filter_item != ""):
			var s := c as Slot
			open_pedia("item", s.item if s.item != "" else s.filter_item)
			break
		if c is Factoriopedia.LinkSlot:
			return false
		c = c.get_parent()
	if c == null:
		return false
	if player != null and player.has_method("alt_clicked"):
		player.alt_clicked()
	return true


## A gps link in the chat: clicked, it looks there (on this surface) and pings the map; posted, it
## pings the map.
func _on_gps(at: Vector2, surface: String, clicked: bool) -> void:
	model.ping(at)
	if not clicked:
		return
	var here := ""
	for s in model.map_surfaces:
		if int(s["si"]) == model.character_si:
			here = str(s["name"])
	if surface != "" and here != "" and surface != here:
		hud_message("That is on %s" % surface)
		return
	remote_view(at)


## Looks at a position on a surface (index; 0: any): remote view on the character's own surface.
func _look_on_surface(at: Vector2, si: int) -> void:
	if si != 0 and model.character_si != 0 and si != model.character_si:
		hud_message("That network is on another surface")
		return
	_networks_remote = true
	remote_view(at)


## Factorio 2.1 shows the logistic networks window in the remote view: opening it starts one (at
## the character until a network is chosen), closing it ends the one it started.
func _networks_in_remote() -> void:
	if networks.is_open() and not remote and not map_view.is_open():
		_networks_remote = true
		var me := character_on_map()
		remote_view(me[0])
	elif not networks.is_open() and _networks_remote:
		_networks_remote = false
		if remote:
			end_remote_view()


## A message over the world, through the HUD (whose label this window doesn't own).
func hud_message(text: String) -> void:
	var hud = get_parent()
	while hud != null and not hud.has_method("show_message"):
		hud = hud.get_parent()
	if hud != null:
		hud.show_message(text)


## Holds the slot's item for building, or puts it away if it is already held.
func _select(index: int) -> void:
	var item: String = model.quickbar[index]
	if item == "" or player == null:
		return
	hand = {}
	player.hold("" if held_item() == item else item)


func _on_quickbar_clicked(index: int, button_index: int) -> void:
	if button_index == MOUSE_BUTTON_RIGHT or button_index == MOUSE_BUTTON_MIDDLE:  # Factorio: middle-click clears
		model.unpin(index)
	elif button_index == MOUSE_BUTTON_LEFT:
		var held := held_item()
		if held != "" and held != model.quickbar[index]:
			model.pin(index, held)
		else:
			_select(index)


## The quickbar's upper row: the same as the lower row's clicks, on that page.
func _on_upper_quickbar_clicked(index: int, button_index: int) -> void:
	_on_page_slot_clicked(model.quickbar_upper_page(), index, button_index)


## A slot of any quickbar page (the upper row, the page chooser's rows).
func _on_page_slot_clicked(page: int, index: int, button_index: int) -> void:
	var item := str(model.quickbar_page_items(page)[index])
	if button_index == MOUSE_BUTTON_RIGHT or button_index == MOUSE_BUTTON_MIDDLE:
		model.pin_on_page(page, index, "")
	elif button_index == MOUSE_BUTTON_LEFT:
		var held := held_item()
		if held != "" and held != item:
			model.pin_on_page(page, index, held)
		elif item != "" and player != null:
			hand = {}
			player.hold("" if held == item else item)


## A slot of the character's inventories. Shift (Ctrl: every one of the item) moves the stack into
## the open machine.
func _on_character_slot(role: String, index: int, button_index: int, shift: bool, ctrl: bool) -> void:
	if role == "armor" and button_index == MOUSE_BUTTON_RIGHT and hand.is_empty() and held_item() == "" 			and int(model.grid("char").get("w", 0)) > 0:
		# Right click on armour with a grid opens the grid, as in Factorio.
		if not window.is_open():
			window.open_crafting(true)
		window.open_armor(not window.armor_open)
		return
	if button_index == MOUSE_BUTTON_MIDDLE:
		if role == "main":
			_toggle_filter(index)
		return
	var stack := model.stack_at(role, index)
	if not hand.is_empty() and hand["role"] == "grid" and role == "main":
		# Equipment from a grid back into the inventory: into this slot if it is empty.
		model.take_equipment(str(hand["kind"]), hand["cell"], index if stack.is_empty() else 0)
		_drop_hand()
		return
	if shift and role == "main" and not stack.is_empty() and _equipment_target() != "" and is_equipment(str(stack["item"])):
		# Shift+click on equipment: into the open vehicle's grid, else the armour's (where it fits).
		model.put_equipment(_equipment_target(), index)
		return
	# Right click on a blueprint, book or planner opens its window, as in Factorio.
	if button_index == MOUSE_BUTTON_RIGHT and role == "main" and not shift and not ctrl 			and PlannerUi.PLANNER_ITEMS.has(str(stack.get("item", ""))) and held_item() == "":
		planners.open_slot(index)
		return
	if shift or ctrl:
		_transfer(role, index, stack, button_index, ctrl, screen.unit if screen.is_open() else 0)
		return
	_click_slot(role, index, stack, button_index, 0)


## Factorio's Shift and Ctrl clicks on a slot, to "the other inventory" (the open machine, or the
## character from it; with nothing open, the main inventory and the gun, ammo and armour slots):
## Shift this stack (right click: half of it), Ctrl every stack of the item, or of everything from
## an empty slot (right click: half of each). The mod does the moving (`xfer`).
func _transfer(role: String, index: int, stack: Dictionary, button_index: int, ctrl: bool, unit: int) -> void:
	if button_index != MOUSE_BUTTON_LEFT and button_index != MOUSE_BUTTON_RIGHT:
		return
	if stack.is_empty() and not ctrl:
		return
	if stack.is_empty() and unit == 0:
		return  # "everything" needs another inventory to go to
	var half := button_index == MOUSE_BUTTON_RIGHT
	model.xfer(role, index, ("allhalf" if half else "all") if ctrl else ("half" if half else "stack"), unit)


## Factorio's middle click on an inventory slot: filter it to its item (or the held one), or clear
## the filter it has.
func _toggle_filter(index: int) -> void:
	var current: String = model.main_filters.get(index, "")
	var stack := model.stack_at("main", index)
	var item: String = str(stack.get("item", "")) if not stack.is_empty() else held_item()
	if current != "" and (item == "" or item == current):
		model.set_slot_filter(index, "")
	elif item != "":
		model.set_slot_filter(index, item)
	else:
		# An empty slot with nothing held: Factorio asks which item to filter it to.
		var chosen := func(_kind: String, name: String) -> void: model.set_slot_filter(index, name)
		picker.choose(["item"], chosen)


## A cell of an equipment grid ("char": the armour's, "veh": the open vehicle's), clicked like
## Factorio's: with equipment from the inventory in the cursor it goes there; with nothing, the
## piece there is picked up, and a click elsewhere in the grid moves it (on itself: put back);
## Shift+click or right click takes a piece into the inventory.
func _on_grid_clicked(kind: String, cell: Vector2i, button_index: int, shift: bool) -> void:
	var e := model.equipment_at(kind, cell)
	if (shift or button_index == MOUSE_BUTTON_RIGHT) and not e.is_empty():
		if not hand.is_empty() and hand["role"] == "grid" and hand["cell"] == Vector2i(int(e["x"]), int(e["y"])):
			_drop_hand()
		model.take_equipment(kind, Vector2i(int(e["x"]), int(e["y"])))
		return
	if button_index != MOUSE_BUTTON_LEFT:
		return
	var held := held_item()
	if not hand.is_empty() and hand["role"] == "grid":
		var from: Vector2i = hand["cell"]
		if str(hand["kind"]) != kind:
			hud_message("Put it in the inventory first")
		elif cell != from:
			model.move_equipment(kind, from, cell)
		_drop_hand()
		return
	if held != "" and not hand.is_empty() and hand["role"] == "main":
		model.put_equipment(kind, int(hand["index"]), cell)
		return
	if held != "" and hand.is_empty():
		var slot := _slot_of(held)
		if slot > 0:
			model.put_equipment(kind, slot, cell)
			return
	if not e.is_empty() and player != null:
		player.hold(str(e["name"]))
		hand = {"role": "grid", "kind": kind, "cell": Vector2i(int(e["x"]), int(e["y"])), "index": 0, "n": 0, "unit": 0}


## The main inventory slot (1-based) holding an item, or 0 ("": the first empty slot).
func _slot_of(item: String) -> int:
	for i in model.main_slots.size():
		if model.main_slots[i].get("item", "") == item:
			return i + 1
	return 0


## Where Shift+click sends equipment: the open vehicle's grid, else the armour's; "" with neither.
func _equipment_target() -> String:
	var v := model.grid("veh")
	if screen.is_open() and int(v.get("w", 0)) > 0 and int(v.get("unit", 0)) == screen.unit:
		return "veh"
	if not screen.is_open() and int(model.grid("char").get("w", 0)) > 0:
		return "char"
	return ""


## Equipment is the item that places it; Factorio's own are all called "...-equipment", and any
## other is known once one sits in a grid.
func is_equipment(item: String) -> bool:
	if item.ends_with("-equipment"):
		return true
	for kind in ["char", "veh"]:
		for e in model.grid(kind).get("equipment", []):
			if str(e["name"]) == item:
				return true
	return false


## The grids show where the equipment in the cursor would go.
func _show_held_equipment(held: String) -> void:
	var grabbed := Vector2i(-1, -1)
	var size := Vector2i.ONE
	var item := held if held != "" and is_equipment(held) else ""
	if not hand.is_empty() and hand["role"] == "grid":
		grabbed = hand["cell"]
		var e := model.equipment_at(str(hand["kind"]), grabbed)
		size = Vector2i(int(e.get("w", 1)), int(e.get("h", 1)))
	elif item != "":
		size = EquipmentGrid.shape_of(item, model)
	for g in [window.armor_grid, window.vehicle_grid]:
		if g == null:
			continue
		var mine: bool = not hand.is_empty() and hand["role"] == "grid" and str(hand["kind"]) == g.kind
		g.set_held(item, size, grabbed if mine else Vector2i(-1, -1))


## Factorio's Alt+F: personal roboports on or off.
func toggle_personal_roboport() -> void:
	var g := model.grid("char")
	if int(g.get("roboport_on", -1)) < 0 or not _grid_has(g, "roboport"):
		hud_message("No personal roboport in the armor")
		return
	var on := int(g["roboport_on"]) == 0
	model.toggle_equipment("roboport", on)
	hud_message("Personal roboport " + ("on" if on else "off"))


## Factorio's Alt+E: the exoskeletons' movement bonus on or off.
func toggle_equipment_movement() -> void:
	var g := model.grid("char")
	if not _grid_has(g, "exoskeleton"):
		hud_message("No exoskeleton in the armor")
		return
	var on := not bool(g.get("movement_on", true))
	model.toggle_equipment("movement", on)
	hud_message("Exoskeleton " + ("on" if on else "off"))


static func _grid_has(g: Dictionary, part: String) -> bool:
	for e in g.get("equipment", []):
		if str(e["name"]).contains(part):
			return true
	return false


## The roboport and exoskeleton shortcuts show while the armour has them, pressed while on.
func _update_equipment_shortcuts() -> void:
	var g := model.grid("char")
	shortcuts.show_shortcut("roboport", _grid_has(g, "roboport"))
	shortcuts.show_shortcut("exoskeleton", _grid_has(g, "exoskeleton"))
	shortcuts.set_on("roboport", int(g.get("roboport_on", 0)) == 1)
	shortcuts.set_on("exoskeleton", bool(g.get("movement_on", true)))


## A slot of the open machine. Shift (Ctrl: all of that item) takes the stack into the inventory.
func _on_machine_slot(role: String, index: int, item: String, count: int, button_index: int, shift: bool, ctrl: bool) -> void:
	if button_index == MOUSE_BUTTON_MIDDLE:
		return
	# From the remote view out of reach, as Factorio 2.x: a module held and clicked into a module
	# slot is asked for, right click takes the request back (F6).
	if role == "modules" and index > 0 and screen.far():
		var target := {"u": screen.unit}
		if button_index == MOUSE_BUTTON_RIGHT:
			model.request_module(target, "", "normal", index, true)
		elif model.is_module(held_item()) and item == "":
			var quality = player.get("cursor_quality") if player != null else null
			model.request_module(target, held_item(), str(quality) if quality is String else "normal", index)
		elif item == "":
			hud_message("Hold a module to ask for it here")
		else:
			hud_message("Out of reach")
		return
	if shift or ctrl:
		if index > 0:
			_transfer(role, index, {} if item == "" else {"item": item, "count": count}, button_index, ctrl, screen.unit)
		elif item != "":  # no slot data: the slot is the item's total
			var n := count if not ctrl else 1 << 30
			if button_index == MOUSE_BUTTON_RIGHT:
				n = ceili(count / 2.0)
			screen.take(role if not ctrl else "", item, n)
		return
	if index == 0:  # no slot data: the slot is the item's total, so a click takes it
		if held_item() != "" and not hand.is_empty() and hand["role"] == "main":
			screen.put(held_item(), hand_count())
			_drop_hand()
		elif item != "":
			screen.take(role, item, ceili(count / 2.0) if button_index == MOUSE_BUTTON_RIGHT else count)
		return
	var stack := {} if item == "" else {"item": item, "count": count}
	_click_slot(role, index, stack, button_index, screen.unit)


## Factorio's slot click: pick up, put down, swap, merge, put back, or (right click) half / one.
func _click_slot(role: String, index: int, stack: Dictionary, button_index: int, unit: int) -> void:
	var held := held_item()
	if held == "" or hand.is_empty():
		# An empty cursor, or one holding a quickbar item (not any stack in particular): pick up.
		if stack.is_empty():
			if held != "":
				_drop_hand()
			return
		# Right click takes the bigger half (37: 19 in the cursor, 18 stay), as in Factorio 2.1.
		var half := button_index == MOUSE_BUTTON_RIGHT and int(stack["count"]) > 1
		_pick_up(role, index, unit, str(stack["item"]), ceili(int(stack["count"]) / 2.0) if half else 0)
		if button_index == MOUSE_BUTTON_RIGHT:
			hand["nohand"] = true
		return
	var from_role: String = hand["role"]
	var from_index := int(hand["index"])
	if from_role == role and from_index == index:
		if button_index == MOUSE_BUTTON_RIGHT and int(hand["n"]) > 1:
			hand["n"] = int(hand["n"]) - 1  # one back into its own slot
		elif button_index == MOUSE_BUTTON_RIGHT and int(hand["n"]) == 0 and int(stack.get("count", 0)) > 1:
			hand["n"] = int(stack["count"]) - 1
		else:
			_drop_hand()  # back where it came from
		return
	if not (_knows_slots(from_role) and _knows_slots(role)):
		# An old mod: no moves by slot, only take and put.
		if MACHINE_ROLES.has(role) and from_role == "main":
			screen.put(held, hand_count())
		elif MACHINE_ROLES.has(from_role) and role == "main":
			screen.take(from_role, held, hand_count())
		_drop_hand()
		return
	var u := int(hand["unit"]) if MACHINE_ROLES.has(from_role) else unit
	var same: bool = not stack.is_empty() and str(stack["item"]) == held
	if button_index == MOUSE_BUTTON_RIGHT:
		if stack.is_empty() or same:
			_place_one(role, index, u)
			_spread = {"button": MOUSE_BUTTON_RIGHT, "item": held, "visited": [[role, index]]}
		return
	if button_index != MOUSE_BUTTON_LEFT:
		return
	if not stack.is_empty() and not same and not MACHINE_ROLES.has(from_role) and not hand.get("nohand", false):
		# A different item, with the held stack's hand in the character's inventory: Factorio (2.1.23)
		# puts the held stack back in its hand slot and picks up the clicked one, so nothing moves.
		_pick_up(role, index, unit, str(stack["item"]), 0)
		if MACHINE_ROLES.has(role):
			hand["nohand"] = true
		return
	var total := hand_count()
	var origin_left := int(_stack(from_role, from_index).get("count", 0)) - total
	model.move(from_role, from_index, role, index, int(hand["n"]), u)
	if same:
		# Onto the same item: as much as fits; the rest stays in the cursor (_check_hand).
		hand["merge"] = [role, index]
		hand["before"] = int(stack["count"])
		hand["at"] = Time.get_ticks_msec()
	elif not stack.is_empty() and int(hand["n"]) == 0:
		# Swapped: the other stack is now where the cursor's came from, and in the cursor.
		hand = {"role": from_role, "index": hand["index"], "n": 0, "unit": hand["unit"]}
		player.hold(str(stack["item"]))
		if MACHINE_ROLES.has(from_role):
			hand["nohand"] = true
	else:
		_drop_hand()
		if stack.is_empty():
			_spread = {"button": MOUSE_BUTTON_LEFT, "item": held, "total": total, "origin": [from_role, from_index],
				"origin_left": maxi(origin_left, 0), "unit": u, "slots": [[role, index]], "added": [total]}


## Right click with a stack held: one of it into this slot.
func _place_one(role: String, index: int, unit: int) -> void:
	model.move(hand["role"], int(hand["index"]), role, index, 1, unit)
	if int(hand["n"]) > 1:
		hand["n"] = int(hand["n"]) - 1
	elif int(hand["n"]) == 1 or hand_count() <= 1:
		_drop_hand()


## Dragging a held stack across slots with the button still down, as in Factorio: the left button
## spreads what the cursor held at the first slot evenly over every slot crossed (what doesn't
## divide stays in the cursor), the right button puts one in each.
func _spread_to(role: String, index: int, unit: int) -> void:
	var stack := _stack(role, index)
	if not stack.is_empty() and str(stack["item"]) != str(_spread["item"]):
		return
	if int(_spread["button"]) == MOUSE_BUTTON_RIGHT:
		var visited: Array = _spread["visited"]
		if visited.has([role, index]) or hand.is_empty() or held_item() != str(_spread["item"]):
			return
		visited.append([role, index])
		if [hand["role"], int(hand["index"])] != [role, index]:
			_place_one(role, index, unit)
		return
	var slots: Array = _spread["slots"]
	var origin: Array = _spread["origin"]
	if slots.has([role, index]) or origin == [role, index] or not stack.is_empty():
		return
	var total := int(_spread["total"])
	var k := slots.size() + 1
	var each := total / k
	if each <= 0:
		return
	var added: Array = _spread["added"]
	var u := int(_spread["unit"])
	var need := each
	var back := 0
	for i in slots.size():
		var excess := int(added[i]) - each
		var to_new := mini(excess, need)
		if to_new > 0:
			model.move(slots[i][0], int(slots[i][1]), role, index, to_new, u)
			need -= to_new
		if excess - to_new > 0:
			model.move(slots[i][0], int(slots[i][1]), origin[0], int(origin[1]), excess - to_new, u)
			back += excess - to_new
		added[i] = each
	slots.append([role, index])
	added.append(each)
	var rest := total - k * each
	if rest > 0:
		# What doesn't divide evenly is held again (it went back to the slot it came from).
		hand = {"role": origin[0], "index": int(origin[1]), "n": rest if int(_spread["origin_left"]) > 0 else 0,
			"unit": u if MACHINE_ROLES.has(origin[0]) else 0}
		if player != null:
			player.hold(str(_spread["item"]))
	elif back > 0 or not hand.is_empty():
		_drop_hand()


## The inventory slot under the mouse (one with a role: the character's or the open machine's).
func _slot_under(at: Vector2) -> Slot:
	var found: Array = []
	_collect_slots(window, found)
	_collect_slots(screen, found)
	for s in found:
		if (s as Slot).get_global_rect().has_point(at):
			return s
	return null


static func _collect_slots(node: Node, out: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Slot and (node as Slot).slot_role != "":
		out.append(node)
	for c in node.get_children():
		_collect_slots(c, out)


## Q with a stack held: back to the slot it came from (Factorio's clear cursor). The bridge's
## stack never left that slot, so only the cursor and the hand are emptied.
func clear_cursor() -> void:
	_spread = {}
	if not hand.is_empty() and MACHINE_ROLES.has(hand["role"]) and screen.is_open():
		# Taken from a machine: Factorio's clear cursor puts it in the character's inventory.
		var n := int(hand["n"])
		if n > 0:
			var free := _slot_of("")
			if free > 0:
				model.move(hand["role"], int(hand["index"]), "main", free, n, int(hand["unit"]))
		else:
			model.xfer(hand["role"], int(hand["index"]), "stack", int(hand["unit"]))
	_drop_hand()


## The pipette's stack: the first stack of the item in the main inventory goes in the cursor, its
## slot marked with the hand. False when there is none.
func pick_from_inventory(item: String) -> bool:
	var slot := 0
	var most := 0
	for i in model.main_slots.size():
		var st: Dictionary = model.main_slots[i]
		if st.get("item", "") == item and int(st.get("count", 0)) > most:
			slot = i + 1  # 2.1.23's pipette takes a full stack: the biggest
			most = int(st["count"])
	if slot == 0 or player == null:
		return false
	_pick_up("main", slot, 0, item, 0)
	return true


## Q over a window with nothing held: the item of the slot under the mouse (any slot: inventory,
## recipe, filter, signal), from the inventory, or as a ghost cursor when it builds something and
## there is none. False when the mouse isn't over an item slot.
func slot_pipette() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	while c != null and not c is Slot:
		c = c.get_parent() as Control
	if c == null:
		return false
	var s := c as Slot
	var item := s.item if s.item != "" else s.filter_item
	if item == "" or player == null:
		return false
	if s.slot_role != "" and s.item != "" and not MACHINE_ROLES.has(s.slot_role):
		var stack := model.stack_at(s.slot_role, s.slot_index)
		if not stack.is_empty():
			_pick_up(s.slot_role, s.slot_index, 0, item, 0)
			return true
	if pick_from_inventory(item):
		return true
	var w = player.get("world")
	if w != null and w.protos.placed_entity(item) != null:
		hand = {}
		player.hold(item)
		hud_message("None in the inventory: builds ghosts")
		return true
	hud_message("You have no %s" % Kit.pretty(item))
	return true


func _pick_up(role: String, index: int, unit: int, item: String, n: int) -> void:
	if player == null:
		return
	hand = {"role": role, "index": index, "n": n, "unit": unit}
	player.hold(item)


func _drop_hand() -> void:
	hand = {}
	if player != null:
		player.hold("")


## --ui-hover: from now on the mouse is taken to be there (the motion is sent again every frame,
## so the real mouse doesn't move the tooltip or the cursor away).
func _hover() -> void:
	_hovering = true
	cursor.debug_at = _hover_at
	_push_hover()


func _follow_hover_unit() -> void:
	var world = player.get("world") if player != null else null
	var rec = world.entities.get(_hover_unit) if world != null else null
	var cam := get_viewport().get_camera_3d()
	if rec != null and cam != null:
		_hover_at = cam.unproject_position(Vector3(rec.pos.x, 0.3, rec.pos.y))
		cursor.debug_at = _hover_at


func _push_hover() -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = _hover_at
	motion.global_position = _hover_at
	get_viewport().push_input(motion)


## --ui-press: the named button (or slot, or a grid's first slot) is pressed as a click would.
func _debug_press(target: String) -> void:
	var n := get_tree().root.find_child(target, true, false)
	if n is GridContainer and n.get_child_count() > 0:
		n = n.get_child(0)
	if n is Slot:
		(n as Slot).clicked.emit(MOUSE_BUTTON_LEFT, false)
	elif n is BaseButton:
		(n as BaseButton).pressed.emit()


## --ui-hold: picks up the first stack of an item, like a click on it.
func _debug_hold(item: String) -> void:
	for i in model.main_slots.size():
		if model.main_slots[i].get("item", "") == item:
			_pick_up("main", i + 1, 0, item, 0)
			return
	if player != null:
		player.hold(item)


## Sample data in the shape of the mod's `rdet` (see ui_model.gd), for the mock's hand recipes.
## Lets the crafting tabs, ingredient tooltips and red "can't craft" slots be seen and tested
## without the mod's data.
func _load_sample() -> void:
	model.set_recipe_details([
		{"name": "wooden-chest", "group": "logistics", "subgroup": "storage", "order": "a", "energy": 0.5, "ingredients": [["wood", 2]], "products": [["wooden-chest", 1]]},
		{"name": "iron-chest", "group": "logistics", "subgroup": "storage", "order": "b", "energy": 0.5, "ingredients": [["iron-plate", 8]], "products": [["iron-chest", 1]]},
		{"name": "transport-belt", "group": "logistics", "subgroup": "belt", "order": "a", "energy": 0.5, "ingredients": [["iron-gear-wheel", 1], ["iron-plate", 1]], "products": [["transport-belt", 2]]},
		{"name": "burner-mining-drill", "group": "production", "subgroup": "extraction-machine", "order": "a", "energy": 2.0, "ingredients": [["iron-gear-wheel", 3], ["stone-furnace", 1], ["iron-plate", 3]], "products": [["burner-mining-drill", 1]]},
		{"name": "stone-furnace", "group": "production", "subgroup": "smelting-machine", "order": "a", "energy": 0.5, "ingredients": [["stone", 5]], "products": [["stone-furnace", 1]]},
		{"name": "iron-gear-wheel", "group": "intermediate-products", "subgroup": "intermediate-product", "order": "a", "energy": 0.5, "ingredients": [["iron-plate", 2]], "products": [["iron-gear-wheel", 1]]},
		{"name": "copper-cable", "group": "intermediate-products", "subgroup": "intermediate-product", "order": "b", "energy": 0.5, "ingredients": [["copper-plate", 1]], "products": [["copper-cable", 2]]},
	], ["logistics", "production", "intermediate-products", "combat"])
	var pins := ["transport-belt", "inserter", "wooden-chest", "stone-furnace", "burner-mining-drill", "small-electric-pole", "", "", "", "iron-plate"]
	for i in pins.size():
		if pins[i] != "":
			model.pin(i, pins[i])
