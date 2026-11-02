extends Node
## Keyboard and mouse to bridge commands: walking, driving, mining, picking up, building,
## rotating, opening machine screens, shooting, and the rest of Factorio's world controls. Also
## draws Factorio's marks on the hovered entity (cursor_overlay.gd: selection corners, inserter,
## drill, fluid and roboport marks), the held item's entity as a translucent model where it would
## go (red where it can't: none left, out of reach, something in the way) with its marks, the box
## dragged with a planner or the copy tools, and the clipboard's ghosts while pasting.
##
## Keys are InputMap actions (controls.gd, rebindable in Settings). The mouse, as in Factorio:
##   left: build the held item (drag: along the way), open a machine, use a planner or tool
##   Shift+left: build a ghost of the held item; with nothing held, paste the copied settings
##   Ctrl+left / Ctrl+right: fast transfer: put the held stack (half) into the entity under the
##       mouse (a belt: onto its lanes), or with nothing held take its output (half); held down,
##       each entity the mouse crosses gets the same (Shift+left's paste too)
##   right: mine; Shift+right: copy the entity's settings
## and the keys: Q pipette (over an entity: hold its item in its quality, also instead of something
## else held, or its ghost if there are none; over a window's slot: that item) or clear the cursor; Z drop one held item (into the entity under the mouse, onto a belt,
## or on the ground); R / Shift+R rotate; H / V flip what is being built (or the entity under the
## mouse); Alt Alt-mode; Ctrl+C / Ctrl+X copy or cut an area (drag), Ctrl+V paste it; Ctrl+Z /
## Ctrl+Y undo and redo (this client's own building and mining, and what the mod remembers:
## blueprints placed, planner marks, pasted settings, rotations); Alt+B / Alt+D / Alt+U blueprint,
## deconstruction and upgrade tools; Alt+L personal logistic requests on or off. With a planner
## held, dragging draws Factorio's selection box in its colour and marks what it will take
## (Shift: cancel; an upgrade planner's right-drag downgrades). A held blueprint (a book: its active
## page) is placed when the button goes down, as in Factorio: a click places what can be built
## (normal), Shift+click forces it (trees and rocks in the way are marked for deconstruction),
## Ctrl+Shift+click super-forces it; dragging places it again every blueprint's length along the
## drag (its snap grid when it has one). Ctrl+Shift+left builds super-forced (trees and rocks in
## the way are marked for deconstruction); H / V flip a held blueprint too (the mod mirrors it,
## see planners.lua); Ctrl+mouse wheel cycles the held item's quality,
## Shift+mouse wheel the held book's pages. Alt+R / Alt+G / Alt+C red, green and copper wire (wire_tool.gd;
## Shift+click on a pole removes its copper cables).
##
## Over a window (the inventory, quickbar, ...) the mouse belongs to the UI: nothing in the world
## is hovered, built or aimed at through it. Keys still walk and shoot, as in Factorio.
##
## Walk, drive, mine, pickup and shoot commands only last half a second in the mod, so they are
## repeated while held.
## Command-line options (after `--`): --open=<unit> opens that entity's screen once it has loaded (a
## building, or a train carriage or car near the character); --rail-from=<x>,<y> anchors the rail
## planner at the rail end nearest that point once the world is in (for screenshots, with --ui-hold).

const Settings := preload("res://scripts/menu/settings.gd")
const WorldMirror := preload("res://scripts/world/world.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const CameraRig := preload("res://scripts/player/camera_rig.gd")
const CombatLayer := preload("res://scripts/world/combat.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const Avatar := preload("res://scripts/player/avatar.gd")
const Controls := preload("res://scripts/player/controls.gd")
const MoverLayer := preload("res://scripts/world/movers.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const CursorOverlay := preload("res://scripts/player/cursor_overlay.gd")
const RoboportLinks := preload("res://scripts/world/roboport_links.gd")
const WireTool := preload("res://scripts/player/wire_tool.gd")
const GhostShader := preload("res://shaders/ghost.gdshader")
const BpString := preload("res://scripts/ui/factorio/bp_string.gd")
const TileBrush := preload("res://scripts/player/tile_brush.gd")
const RailPlanner := preload("res://scripts/player/rail_planner.gd")
const CapsuleAim := preload("res://scripts/player/capsule_aim.gd")
const DragBuild := preload("res://scripts/player/drag_build.gd")
const SpiderRemote := preload("res://scripts/player/spider_remote.gd")

const REPEAT := 0.15
## A walk's angle is sent again once the wanted direction (keys turned by the camera, or the stick)
## moved this many thousandths of a turn (about 1 degree).
const TURN_STEP := 3
const STICK_DEAD_ZONE := 0.25
## The character's build_distance in Factorio.
const BUILD_REACH := 10.0
## Held like a building but used on release: a blueprint (or book) is placed, a planner dragged.
const PLANNERS := ["blueprint", "blueprint-book", "deconstruction-planner", "upgrade-planner"]
## Tools the shortcuts put in the cursor without an item in the inventory (Factorio spawns them):
## tool -> the item whose icon the cursor shows.
const TOOLS := {
	"copy": "copy-paste-tool", "cut": "cut-paste-tool", "paste": "blueprint",
	"blueprint": "blueprint", "decon": "deconstruction-planner",
	"red-wire": "red-wire", "green-wire": "green-wire", "copper-wire": "copper-wire",
	"spidertron": "spidertron-remote",
}
## Selection colours: the border_color of each tool's select / alt_select (Shift) / reverse_select
## (right-drag) in Factorio's item prototypes (base/prototypes/item.lua): blueprint blue (Shift a
## lighter blue), copy and cut white (copy with Shift cyan), deconstruction red, upgrade green,
## their Shift cancels orange, the upgrade planner's downgrade yellow.
const SELECT_COLORS := {
	"blueprint": Color8(57, 156, 251), "blueprint_alt": Color(0.3, 0.8, 1.0), "copy": Color(1, 1, 1), "copy_alt": Color(0, 1, 1),
	"cut": Color(1, 1, 1), "cut_alt": Color(1, 1, 1), "decon": Color8(255, 24, 24), "decon_alt": Color8(239, 153, 34),
	"upgrade": Color8(71, 255, 73), "upgrade_alt": Color8(239, 153, 34), "upgrade_reverse": Color8(246, 255, 0),
}
## The dragged box is only its border, as Factorio draws it (tiles wide); what it takes gets
## brackets in the same colour.
const BOX_EDGE := 0.06
## Trees and rocks: what "trees and rocks only" takes, and what blueprints and copies leave out.
const NATURE_TYPES := ["tree", "simple-entity", "cliff", "plant"]
## A left click with nothing held, or E, opens these: what Factorio 2.1.23 opens a window for
## (tools/ui_reference's rules_openable built and opened every buildable entity). Steam engines and
## turbines, solar panels, walls, gates, undergrounds, rails, fluid wagons, lightning rods, fusion
## generators and thrusters open nothing there.
const OPENABLE_TYPES := [
	"container", "logistic-container", "linked-container", "infinity-container", "assembling-machine",
	"furnace", "lab", "mining-drill", "boiler", "burner-generator", "reactor", "rocket-silo",
	"inserter", "splitter", "lane-splitter", "loader", "loader-1x1", "constant-combinator", "arithmetic-combinator",
	"decider-combinator", "selector-combinator", "train-stop", "locomotive", "cargo-wagon",
	"artillery-wagon", "roboport", "accumulator", "radar", "ammo-turret", "artillery-turret", "car",
	"spider-vehicle", "power-switch", "programmable-speaker", "display-panel", "lamp", "storage-tank",
	"pump", "offshore-pump", "electric-pole", "cargo-landing-pad", "space-platform-hub", "cargo-bay",
	"electric-energy-interface", "asteroid-collector", "agricultural-tower", "heat-interface",
	"electric-turret", "fluid-turret", "beacon", "fusion-reactor", "pipe", "pipe-to-ground", "heat-pipe",
	"land-mine", "transport-belt", "rail-signal", "rail-chain-signal",
]
## Movers a click opens: their inventories (a car's trunk, a wagon's cargo), a train's schedule.
const OPENABLE_MOVERS := ["car", "spider-vehicle", "locomotive", "cargo-wagon", "artillery-wagon"]
## Undo keeps this many of the client's own actions.
const HISTORY := 50

## --clean-shot (model screenshots): no hover highlight, whatever the mouse is over.
var _clean_shot := OS.get_cmdline_user_args().has("--clean-shot")
## Why the held entity can't be built on this surface ("" when it can), shown under the cursor.
var _build_refusal := ""
var world: WorldMirror
## The remote view's fog (remote_fog.gd), for what draws over the world (Alt-mode icons). Untyped.
var remote_fog: Node
var rig: CameraRig
var hud: Hud
var combat: CombatLayer
var avatar: Avatar
## Vehicles and wagons are movers, not world entities: they are opened through this.
var movers: MoverLayer = null
var wires = null  # wires.gd, for where a dragged wire hangs from
var wire_tool := WireTool.new()
## The spidertron remote's selection and waypoints (cursor_tool "spidertron").
var spider_remote := SpiderRemote.new()

## Item held for building ("" for none). Its entity is assumed to share the item's name.
var cursor_item := ""
## Which stack a held blueprint or planner is: 0 the first of that item (or the one picked up), -1
## the one taken from the library (the mod keeps it out of the inventory), else that main slot.
var cursor_slot := 0
## The quality the held item builds in (Ctrl+mouse wheel), Factorio 2.x.
var cursor_quality := "normal"
## A tool from a shortcut instead of an item (TOOLS), or "".
var cursor_tool := ""
var build_dir := 0
## Flip what is built (H / V): the entity is mirrored.
var build_mirror := false
var hovered: WorldMirror.Rec = null
var _alt_clicked := false
## The vehicle or wagon under the mouse (MoverLayer.pick_ray), or []; it wins over the rail or
## ground under it, so `hovered` is null then.
var hovered_mover: Array = []
var ground := Vector2.ZERO
var has_ground := false
## The mouse is over the UI this frame.
var over_gui := false
## The entity whose settings Shift+right click copied: {"u", "p", "x", "y", "name"} or {}.
var copied_settings := {}

var _walk_dir := -1
var _walk_turn := -1  # the angle last sent with walk, thousandths of a turn, or -1
var _walk_timer := 0.0
var _drive_code := 0  # the last drive command sent, as accelerate * 3 + steer; 0 is none
var _mine_timer := 0.0
var _mining := false
var _mine_target: WorldMirror.Rec = null
var _pickup_timer := 0.0
var _drop_timer := 0.0
var _shoot_mode := -1
var _shoot_timer := 0.0
var _rmb_down := false
## An upgrade planner's right-drag (Factorio's downgrade) is in progress from here.
var _reverse_from := Vector2.INF
## Blueprint drag-placing: where it was last placed, the axis the drag took (ZERO until it moved a
## step), the build mode of the click.
var _bp_last := Vector2.INF
var _bp_axis := Vector2.ZERO
var _bp_mode := 0
## Ctrl+click held down (MOUSE_BUTTON_LEFT / RIGHT, or NONE) and the entity it last went to; a
## Shift+left paste held down and the entity it last pasted to.
var _fast_button := MOUSE_BUTTON_NONE
var _fast_target: WorldMirror.Rec = null
var _paste_dragging := false
var _paste_target: WorldMirror.Rec = null
## The blueprint window's "Select new contents": the blueprint tool's area goes into this
## blueprint (a main slot, -1 the library one) instead of a new one; 0 none.
var reselect_slot := 0
var _lmb_down := false
var _remote_marked: WorldMirror.Rec = null  # marked for deconstruction during this right click (remote view)
var _lmb_shift := false  # Shift was held when the left button went down: ghosts, cancel boxes
var _lmb_super := false  # Ctrl+Shift: super-forced build (obstacles marked for deconstruction)
var _drag_from := Vector2.ZERO  # where a planner drag started
var _last_build_tile := Vector2i(1 << 30, 1 << 30)
var _rail_click := false  # this left click was the rail planner's (anchoring or building)
var _ghost := MeshInstance3D.new()
var _drag_box := MeshInstance3D.new()
## Build previews from `eprops`: a pole's supply area, an underground belt's reach, and lines to the
## poles a new pole would connect to.
var _reach_box := MeshInstance3D.new()
var _reach_lines := MeshInstance3D.new()
var _reach_mesh := ImmediateMesh.new()
var _ghost_ok := Visuals.ghost_material(Color(0.3, 1.0, 0.4, 0.35))
var _ghost_bad := Visuals.ghost_material(Color(1.0, 0.3, 0.25, 0.35))
var _ghost_blue := Visuals.ghost_material(Color(0.4, 0.65, 1.0, 0.35))
## The held item's entity as its model, translucent (ghost.gdshader): whitish where it can go,
## Factorio's ghost blue for a ghost, red where it can't.
var _ghost_model := MeshInstance3D.new()
var _ghost_model_tints := {"ok": Color(0.85, 1.0, 0.85, 0.5), "ghost": Color(0.58, 0.68, 1.0, 0.42), "bad": Color(1.0, 0.3, 0.25, 0.5)}
var _ghost_model_materials := {}
## A held cargo bay's edge pieces round it (ModelLibrary.cargo_places), as it would be framed there.
var _ghost_pieces: Array[MeshInstance3D] = []
## Selection brackets, arrows and areas (cursor_overlay.gd).
var _overlay := CursorOverlay.new()
## Which roboports are linked, for the lines between them (H14).
var roboport_links: RoboportLinks = null
var _paste_ghosts: Array[MeshInstance3D] = []
var _open_on_start := 0
var _rail_from := Vector2.INF
var _open_name_on_start := ""
## Undo and redo: what this client built and mined, newest last ({"do": "build"|"mine", "item",
## "x", "y" (tiles), "d"}).
var _undo: Array = []
var _redo: Array = []
## Tiles in the cursor (tile_brush.gd), the rail planner (rail_planner.gd), capsules
## (capsule_aim.gd) and building while dragging (drag_build.gd).
var tile_brush := TileBrush.new()
var rail_planner := RailPlanner.new()
var capsule_aim := CapsuleAim.new()
var drag := DragBuild.new()


## Registers the input actions (controls.gd) with their default keys. Call once before the scene
## starts; Settings → Controls (settings.gd apply_bindings) rebinds them after.
static func define_actions() -> void:
	Controls.define()


func _ready() -> void:
	for box in [_ghost, _drag_box, _reach_box]:
		box.mesh = Visuals.box_mesh()
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		box.visible = false
		world.add_child(box)
	_box_edges()
	_reach_box.material_override = Visuals.ghost_material(Color(0.35, 0.6, 1.0, 0.18))
	_reach_lines.mesh = _reach_mesh
	_reach_lines.material_override = Visuals.ghost_material(Color(0.95, 0.75, 0.3, 0.9))
	_reach_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(_reach_lines)
	for k in _ghost_model_tints:
		var m := ShaderMaterial.new()
		m.shader = GhostShader
		m.set_shader_parameter("tint", _ghost_model_tints[k])
		_ghost_model_materials[k] = m
	_ghost_model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost_model.visible = false
	world.add_child(_ghost_model)
	world.add_child(_overlay)
	roboport_links = RoboportLinks.new(world)
	roboport_links.radius_of = _logistic_radius
	wire_tool.world = world
	wire_tool.wires = wires
	wire_tool.model = hud.ui.model
	world.add_child(wire_tool)
	for tool in [tile_brush, rail_planner, capsule_aim]:
		tool.pi = self
		world.add_child(tool)
	drag.pi = self
	hud.ui.player = self
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--open="):
			var what := arg.get_slice("=", 1)
			if what.is_valid_int():
				_open_on_start = int(what)
			else:  # a prototype name: the nearest one (UI reference shots, tools/ui_reference)
				_open_name_on_start = what
		elif arg.begins_with("--rail-from="):
			var xy := arg.get_slice("=", 1).split(",")
			_rail_from = Vector2(float(xy[0]), float(xy[1]))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if rig.first_person and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			rig.look(mm.relative)
		elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			rig.rotate_free(-mm.relative.x * 0.3)
			rig.tilt(mm.relative.y * 0.3 * rig.look_sign)
	elif Controls.pressed(event, "reverse_rotate"):
		_rotate(true)
	elif Controls.pressed(event, "rotate"):
		_rotate(false)
	elif Controls.pressed(event, "pipette") or Controls.pressed(event, "clear_cursor"):
		_pipette_or_clear()
	elif Controls.pressed(event, "flip_horizontal"):
		_flip(false)
	elif Controls.pressed(event, "flip_vertical"):
		_flip(true)
	elif Controls.pressed(event, "alt_mode"):
		# Alt-mode toggles when Alt is let go, unless it was held for an Alt+click (Factoriopedia).
		_alt_clicked = false
	elif event is InputEventKey and event.is_action_released("alt_mode"):
		if not _alt_clicked:
			hud.ui.set_alt_mode(not hud.ui.alt_mode)
		_alt_clicked = false
	elif Controls.pressed(event, "copy"):
		hold_tool("copy")
	elif Controls.pressed(event, "cut"):
		hold_tool("cut")
	elif Controls.pressed(event, "paste"):
		if hud.ui.model.clipboard.is_empty():
			hud.show_message("The clipboard is empty")
		else:
			hold_tool("paste")
	elif Controls.pressed(event, "undo"):
		undo()
	elif Controls.pressed(event, "redo"):
		redo()
	elif Controls.pressed(event, "give_blueprint"):
		hold_tool("blueprint")
	elif Controls.pressed(event, "give_deconstruction_planner"):
		hold_tool("decon")
	elif Controls.pressed(event, "toggle_rail_layer") and cursor_tool == "" and not rail_planner.use_of(cursor_item).is_empty():
		# Alt+R is both the rail layer (this client's default) and Factorio's red wire: rails in
		# hand take it, anything else gives the wire.
		rail_planner.toggle_layer()
	elif Controls.pressed(event, "give_red_wire"):
		hold_tool("red-wire")
	elif Controls.pressed(event, "give_green_wire"):
		hold_tool("green-wire")
	elif Controls.pressed(event, "give_copper_wire"):
		hold_tool("copper-wire")
	elif Controls.pressed(event, "give_upgrade_planner"):
		if _slot_of("upgrade-planner") > 0:
			hold("upgrade-planner")
		else:
			hud.ui.planners.give_new("upgrade_planner")
	elif Controls.pressed(event, "cycle_quality_up"):
		cycle_quality(1)
	elif Controls.pressed(event, "cycle_quality_down"):
		cycle_quality(-1)
	elif Controls.pressed(event, "cycle_blueprint_forwards"):
		_cycle_book(1)
	elif Controls.pressed(event, "cycle_blueprint_backwards"):
		_cycle_book(-1)
	elif Controls.pressed(event, "toggle_personal_logistics"):
		hud.ui.toggle_personal_logistics()
	elif Controls.pressed(event, "larger_tile_area"):
		tile_brush.resize(1)
	elif Controls.pressed(event, "smaller_tile_area"):
		tile_brush.resize(-1)
	elif Controls.pressed(event, "camera_left"):
		rig.rotate_step(-1)
	elif Controls.pressed(event, "camera_right"):
		rig.rotate_step(1)
	elif Controls.pressed(event, "factorio_view"):
		rig.toggle_factorio_view()
	elif Controls.pressed(event, "first_person"):
		rig.toggle_first_person()
	elif Controls.pressed(event, "toggle_projection"):
		hud.show_message(rig.toggle_projection())
	elif Controls.pressed(event, "toggle_help"):
		Settings.set_value("interface", "show_help", not bool(Settings.get_value("interface", "show_help")))
		hud.help.visible = bool(Settings.get_value("interface", "show_help"))
	elif Controls.pressed(event, "open_screen"):
		# Factorio's E: closes whatever is open, else opens the inventory. Over a building that has
		# a screen it opens that instead (left click does too).
		if hud.ui.is_open():
			hud.ui.close_all()
		elif hovered != null and _openable(hovered):
			_open(hovered)
		elif not hovered_mover.is_empty():
			_open_mover()
		else:
			hud.ui.toggle_inventory()
	elif Controls.pressed(event, "next_gun"):
		_next_gun()
	elif Controls.pressed(event, "enter_vehicle"):
		# Beside a rocket silo, Enter is for getting into its rocket: its screen has the Ride buttons.
		var silo := _silo_near() if avatar.vehicle == 0 else null
		if silo != null:
			_open(silo)
		else:
			Bridge.send({"t": "enter"})


## A rocket silo the character stands beside (within 6 tiles of its edge), or null.
func _silo_near() -> WorldMirror.Rec:
	var me: Vector2 = avatar.ground_position()
	for key in world.entities:
		var r: WorldMirror.Rec = world.entities[key]
		if r.pos.distance_to(me) < 11.0:
			var p = world.protos.entity(r.proto_id)
			if p != null and p.type == "rocket-silo":
				return r
	return null


func _mouse_button(mb: InputEventMouseButton) -> void:
	match mb.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
			# Factorio: Ctrl+wheel the held item's quality, Shift+wheel a held book's pages.
			if mb.ctrl_pressed and cursor_item != "":
				cycle_quality(1 if up else -1)
			elif mb.shift_pressed and cursor_item == "blueprint-book":
				_cycle_book(-1 if up else 1)
			else:
				rig.zoom(0.9 if up else 1.1)
		MOUSE_BUTTON_RIGHT:
			if not mb.pressed:
				return
			if mb.ctrl_pressed and not mb.shift_pressed:
				_fast_button = MOUSE_BUTTON_RIGHT
				_fast_target = null
				_fast_transfer(true)
			elif mb.shift_pressed and not mb.ctrl_pressed:
				_copy_settings()
			elif WireTool.is_wire(cursor_tool) and wire_tool.cancel():
				pass  # the hanging wire goes first, then the tool
			elif cursor_tool == "spidertron" and has_ground:
				_reverse_from = ground  # the remote's reverse select: take spidertrons out
			elif cursor_tool != "":
				hold("")  # Factorio: right click puts a tool away
			elif cursor_item == "upgrade-planner" and has_ground:
				_reverse_from = ground  # Factorio's reverse select: downgrade
			elif not rail_planner.anchor.is_empty():
				rail_planner.clear()  # the rail planner lets go of its rail end
			else:
				_rmb_down = true
				_mine_timer = 0.0
		MOUSE_BUTTON_LEFT:
			if not mb.pressed:
				return
			if mb.alt_pressed and _open_pedia():
				return
			_drag_from = ground
			_last_build_tile = Vector2i(1 << 30, 1 << 30)
			_lmb_shift = mb.shift_pressed
			_lmb_super = mb.shift_pressed and mb.ctrl_pressed
			if mb.ctrl_pressed and not mb.shift_pressed:
				_fast_button = MOUSE_BUTTON_LEFT
				_fast_target = null
				_fast_transfer(false)
				return
			_lmb_down = true
			tile_brush.reset_drag()
			var ghost_click := mb.shift_pressed or hud.count_of(cursor_item) == 0 or hud.ui.remote
			if WireTool.is_wire(cursor_tool) or (mb.shift_pressed and cursor_item == "" and hovered != null and _is_pole(hovered)):
				_wire_click(mb.shift_pressed)
				_lmb_down = false
			elif cursor_tool == "" and cursor_item != "" and has_ground and rail_planner.click(cursor_item, ground, ghost_click):
				_rail_click = true
			elif cursor_tool == "paste":
				_paste()
				_lmb_down = false
			elif cursor_tool == "" and cursor_item in ["blueprint", "blueprint-book"] and has_ground:
				# Factorio places a blueprint as the button goes down, and again along a drag.
				_bp_mode = 2 if mb.shift_pressed and mb.ctrl_pressed else (1 if mb.shift_pressed else 0)
				_bp_axis = Vector2.ZERO
				_bp_last = blueprint_anchor(ground)
				place_blueprint(_bp_last, _bp_mode)
			elif mb.shift_pressed and cursor_item == "" and hovered != null:
				_paste_settings(hovered)
				_paste_dragging = true
				_lmb_down = false
			elif cursor_tool == "" and hovered != null and hud.ui.model.is_module(cursor_item):
				_module_click(hovered)
				_lmb_down = false
			elif cursor_item == "" and hovered != null and _openable(hovered):
				_open(hovered)
			elif cursor_item == "" and hovered == null and _open_mover():
				_lmb_down = false


## A module clicked on a building or ghost (F6), as in Factorio 2.x: the mod puts it in from the
## inventory within reach, and otherwise (remote view, a ghost, out of reach, none left) asks for it:
## the robots, or a platform's hub, bring it. The mod says why when it can't.
func _module_click(r: WorldMirror.Rec) -> void:
	hud.ui.model.request_module({"u": r.unit, "p": r.proto_id, "x": r.fixed.x, "y": r.fixed.y}, cursor_item, cursor_quality)


## Alt+click: Factoriopedia's page of the entity under the mouse (a ghost's: what it will build), or
## a train or vehicle.
func _open_pedia() -> bool:
	alt_clicked()
	var proto: ProtoDB.EntityProto = null
	if hovered != null:
		proto = world.protos.entity(hovered.proto_id)
		if proto != null and proto.type == "entity-ghost" and hovered.extra.has("gh"):
			proto = world.protos.entity(int(hovered.extra["gh"]))
	elif not hovered_mover.is_empty():
		proto = world.protos.entity(int(hovered_mover[1]))
	if proto == null:
		return false
	hud.ui.open_pedia("entity", proto.name)
	return true


## An Alt+click happened: letting go of Alt then doesn't toggle Alt-mode.
func alt_clicked() -> void:
	_alt_clicked = true


## Releases are watched everywhere, so letting go over the HUD still stops mining.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_rmb_down = false
		if _reverse_from != Vector2.INF and has_ground and cursor_item == "upgrade-planner":
			_use_planner(false, true)
		elif _reverse_from != Vector2.INF and has_ground and cursor_tool == "spidertron":
			spider_remote.right(movers, _reverse_from, ground)
		_reverse_from = Vector2.INF
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		drag.end()
		capsule_aim.release()
		# Letting go of a drag from a rail end builds the path to here.
		if _lmb_down and _rail_click and has_ground and not rail_planner.path.is_empty() and _drag_from.distance_to(ground) > 2.0:
			rail_planner.build(cursor_item, _lmb_shift or hud.count_of(cursor_item) == 0 or hud.ui.remote)
		_rail_click = false
		if _lmb_down and has_ground:
			if cursor_tool in ["copy", "cut", "blueprint", "decon"]:
				_use_tool(Input.is_key_pressed(KEY_SHIFT))
			elif cursor_tool == "spidertron":
				var said := spider_remote.left(movers, _drag_from, ground, Input.is_key_pressed(KEY_SHIFT))
				if said != "":
					hud.show_message(said)
			elif cursor_tool == "" and cursor_item in ["deconstruction-planner", "upgrade-planner"]:
				_use_planner(Input.is_key_pressed(KEY_SHIFT))
		_lmb_down = false
		_bp_last = Vector2.INF


func _process(delta: float) -> void:
	var tilt := Input.get_axis("camera_tilt_down", "camera_tilt_up")
	if tilt != 0.0:
		rig.tilt(tilt * 60.0 * delta)
	rig.set_cursor_needed(hud.ui.is_open() or hud.ui.map_open())
	if not Bridge.connected:
		return
	_update_ground()
	_update_walk(delta)
	_update_mining(delta)
	_update_pickup(delta)
	_update_drop(delta)
	_update_shooting(delta)
	_update_building(delta)
	_update_blueprint_drag()
	_update_drag_clicks()
	_update_highlights()
	wire_tool.update(cursor_tool, hovered, ground, has_ground)
	hud.ui.cursor.over_world_too = not (_ghost.visible or _ghost_model.visible)
	if _rail_from != Vector2.INF and Bridge.world_ready and cursor_item != "" and rail_planner.click(cursor_item, _rail_from, false):
		_rail_from = Vector2.INF
	if _open_name_on_start != "" and Bridge.world_ready:
		_open_on_start = _nearest_named(_open_name_on_start)
		if _open_on_start != 0:
			_open_name_on_start = ""
	if _open_on_start != 0 and Bridge.world_ready and world.entities.has(_open_on_start):
		_open(world.entities[_open_on_start])
		_open_on_start = 0
	elif _open_on_start != 0 and Bridge.world_ready and movers != null and movers.position_of(_open_on_start) != null:
		# A train carriage or a car (a mover): the mod finds it by unit near that point.
		var at: Vector3 = movers.position_of(_open_on_start)
		_request_open(_open_on_start, {"t": "open", "u": _open_on_start, "p": 0, "x": int(at.x * 256.0), "y": int(at.z * 256.0)})
		_open_on_start = 0
	if avatar != null and avatar.vehicle != 0:
		var kmh := roundi(absf(avatar.vehicle_speed))
		hud.cursor_label.text = "%d km/h · WASD drive · Enter: get out" % kmh
	elif cursor_tool == "" and not tile_brush.use_of(cursor_item).is_empty():
		hud.cursor_label.text = "Tile area %d × %d · Numpad + / -: size · Right click: mine tiles" % [tile_brush.size, tile_brush.size]
	elif cursor_tool == "" and not rail_planner.use_of(cursor_item).is_empty():
		if rail_planner.anchor.is_empty():
			hud.cursor_label.text = "Click a rail end to plan from it · %s: rail layer" % Controls.keys_text("toggle_rail_layer")
		else:
			hud.cursor_label.text = "%d rails · Click: build · Right click: let go%s" % [rail_planner.rails_needed(),
				" · elevated" if rail_planner.target_layer == 1 else ""]
	elif cursor_tool != "":
		hud.cursor_label.text = {"copy": "Drag to copy · Right click: cancel", "cut": "Drag to cut · Right click: cancel",
			"paste": "Click to paste · R: rotate · Right click: cancel", "blueprint": "Drag to make a blueprint · Right click: cancel",
			"decon": "Drag to deconstruct · Shift: cancel deconstruction",
			"red-wire": "Click two entities to connect them (again: disconnect) · Right click: let go",
			"green-wire": "Click two entities to connect them (again: disconnect) · Right click: let go",
			"copper-wire": "Click two poles to connect them (again: disconnect) · Shift+click a pole: remove its cables",
			"spidertron": "Drag: select spidertrons · Shift+drag: add · Right-drag: remove · Click: send · Shift+click: queue"}.get(cursor_tool, "")
	elif cursor_quality != "normal" and cursor_item != "":
		hud.cursor_label.text = "Quality: %s · Ctrl+wheel: change" % cursor_quality.capitalize()
	elif cursor_item == "deconstruction-planner" or cursor_item == "upgrade-planner":
		hud.cursor_label.text = "Drag to mark · Shift+drag: cancel · Right click the planner in the inventory: its settings"
	elif cursor_item == "blueprint-book":
		hud.cursor_label.text = "Click to place the active blueprint · Shift+wheel: pages"
	else:
		hud.cursor_label.text = _build_refusal


func _update_ground() -> void:
	over_gui = hud.ui.mouse_over_gui() and not rig.first_person
	var p = rig.ground_point(rig.aim_position() if rig.first_person else hud.ui.mouse_position())
	has_ground = p != null and not over_gui
	if has_ground:
		ground = Vector2(p.x, p.z)
	# A module held still picks what is under the mouse: clicking it puts the module in or asks for it.
	var picks := cursor_item == "" or (cursor_tool == "" and hud.ui.model.is_module(cursor_item))
	hovered = world.pick(ground) if has_ground and picks and not _clean_shot else null
	hovered_mover = []
	if hovered == null or not _openable(hovered):
		hovered_mover = _mover_under_mouse()
		if not hovered_mover.is_empty():
			hovered = null
	hud.ui.set_selected(hovered)


func _update_walk(delta: float) -> void:
	if avatar != null and avatar.vehicle != 0:
		_update_drive(delta)
		return
	_drive_code = 0
	# WASD moves the map while it is open, not the character; the console takes the keys too.
	var input := Vector2.ZERO if hud.ui.map_open() or hud.ui.typing() else Input.get_vector("move_left", "move_right", "move_down", "move_up")
	if hud.ui.remote:  # remote view: WASD moves the view
		var pan := rig.ground_right() * input.x + rig.ground_forward() * input.y
		hud.ui.pan_remote(Vector2(pan.x, pan.z) * 40.0 * delta * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0))
		input = Vector2.ZERO
	if input.length() <= 0.2 and not (hud.ui.map_open() or hud.ui.typing() or hud.ui.remote):
		input = _stick()
	var dir := -1
	var turn := -1
	if input.length() > 0.2:
		var world_dir := rig.ground_right() * input.x + rig.ground_forward() * input.y
		var angle := atan2(world_dir.x, -world_dir.z)  # clockwise from north
		dir = posmod(int(round(angle / (TAU / 8.0))), 8) * 2
		# Any angle, in thousandths of a turn; the mod steps between Factorio's 8 ways to follow it.
		turn = posmod(int(round(angle / TAU * 1000.0)), 1000)
	_walk_timer -= delta
	var turned := turn >= 0 and _walk_turn >= 0 and absi(posmod(turn - _walk_turn + 500, 1000) - 500) >= TURN_STEP
	if dir != _walk_dir or turned or (turn >= 0) != (_walk_turn >= 0) or (dir >= 0 and _walk_timer <= 0.0):
		Bridge.send({"t": "walk", "d": dir, "a": turn} if turn >= 0 else {"t": "walk", "d": dir})
		_walk_dir = dir
		_walk_turn = turn
		_walk_timer = REPEAT


## A gamepad's left stick, as the move actions' vector (up positive), or zero.
func _stick() -> Vector2:
	for pad in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), -Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if v.length() > STICK_DEAD_ZONE:
			return v
	return Vector2.ZERO


## In a vehicle W and S accelerate and reverse, A and D steer, relative to the vehicle as in
## Factorio, not the camera.
func _update_drive(delta: float) -> void:
	_walk_dir = -2  # walking resumes with a fresh command after getting out
	var a := 0
	var forward := 0.0 if hud.ui.typing() else Input.get_axis("move_down", "move_up")
	if forward > 0.2:
		a = 1
	elif forward < -0.2:
		a = 3
	var s := 0
	var steer := 0.0 if hud.ui.typing() else Input.get_axis("move_left", "move_right")
	if steer > 0.2:
		s = 1
	elif steer < -0.2:
		s = -1
	var code := a * 3 + s
	_walk_timer -= delta
	if code != _drive_code or (code != 0 and _walk_timer <= 0.0):
		Bridge.send({"t": "drive", "a": a, "s": s})
		_drive_code = code
		_walk_timer = REPEAT


func _update_mining(delta: float) -> void:
	# The entity being mined went away: it was mined, so undo can put a ghost back.
	if _mine_target != null and not world.entities.has(_mine_target.key):
		var proto: ProtoDB.EntityProto = world.protos.entity(_mine_target.proto_id)
		var item := item_for(_mine_target)
		if proto != null and item != "" and proto.type != "resource" and _mine_target.unit > 0:
			_remember({"do": "mine", "item": item, "x": _mine_target.pos.x, "y": _mine_target.pos.y, "d": _mine_target.dir})
		_mine_target = null
	if not _rmb_down:
		_remote_marked = null
		if _mining:
			Bridge.send({"t": "mine_stop"})
			_mining = false
			_mine_target = null
		return
	if not tile_brush.use_of(cursor_item).is_empty() and cursor_tool == "":
		# A tile in hand: the right button mines the placed tiles under the brush, as in Factorio.
		if has_ground and not hud.ui.remote:
			tile_brush.mine(ground, delta)
		return
	_mine_timer -= delta
	if _mine_timer > 0.0 or not has_ground:
		return
	_mine_timer = REPEAT
	var target: WorldMirror.Rec = world.pick(ground)
	if hud.ui.remote:
		# Remote view can't reach anything: mining marks it for deconstruction instead (Factorio 2.0).
		if target != null and target != _remote_marked:
			_remote_marked = target
			_mark_for_deconstruction(target)
		return
	if target != null:
		Bridge.send({"t": "mine", "u": target.unit, "p": target.proto_id, "x": target.fixed.x, "y": target.fixed.y})
		_mining = true
		_mine_target = target


## Marks one entity for deconstruction (the area under its middle), as mining it in remote view does.
func _mark_for_deconstruction(target: WorldMirror.Rec) -> void:
	var c: Vector2 = target.pos
	Bridge.send({"t": "decon", "i": 0, "x1": int((c.x - 0.1) * 256.0), "y1": int((c.y - 0.1) * 256.0),
		"x2": int((c.x + 0.1) * 256.0), "y2": int((c.y + 0.1) * 256.0)})


## Holding F picks up items on the ground around the character, like in Factorio.
func _update_pickup(delta: float) -> void:
	_pickup_timer -= delta
	if Input.is_action_pressed("pick_up") and not hud.ui.typing() and _pickup_timer <= 0.0:
		Bridge.send({"t": "pickup"})
		_pickup_timer = REPEAT


## Z drops one of the held item where the mouse is; held down it keeps dropping, like Factorio.
func _update_drop(delta: float) -> void:
	_drop_timer -= delta
	if not Input.is_action_pressed("drop_item", true) or hud.ui.typing():
		_drop_timer = 0.0
		return
	if _drop_timer > 0.0:
		return
	_drop_timer = REPEAT
	if cursor_item == "" or cursor_tool != "" or not has_ground:
		return
	Bridge.send({"t": "drop", "item": cursor_item, "x": int(ground.x * 256.0), "y": int(ground.y * 256.0)})


## Like Factorio: Space shoots at enemies near the character (the game picks the target), C at
## whatever is under the cursor.
func _update_shooting(delta: float) -> void:
	var mode := -1
	if not hud.ui.typing():
		if Input.is_action_pressed("shoot_cursor", true) and has_ground and not hud.ui.is_open():
			mode = 1
		elif Input.is_action_pressed("shoot_enemies"):
			mode = 0
	if combat != null:
		combat.aim_mode = mode
		combat.aim = ground
	_shoot_timer -= delta
	if mode != _shoot_mode or (mode >= 0 and _shoot_timer <= 0.0):
		Bridge.send({"t": "shoot", "m": mode, "x": int(ground.x * 256.0), "y": int(ground.y * 256.0)})
		_shoot_mode = mode
		_shoot_timer = REPEAT


func _next_gun() -> void:
	var n := hud.guns.size()
	for step in range(1, n + 1):
		var i := posmod(hud.selected_gun - 1 + step, n)
		var slot = hud.guns[i]
		if slot is Array and slot.size() >= 1 and str(slot[0]) != "":
			if i + 1 != hud.selected_gun:
				Bridge.send({"t": "gun", "i": i + 1})
			return


## Holding the left button builds on every new tile the cursor passes, like dragging belts.
## Planners are used on release, over the dragged area (Shift: cancel the marks; an upgrade
## planner's right-drag: downgrade).
func _use_planner(cancel: bool, reverse := false) -> void:
	var slot := planner_slot()
	if slot == 0:
		hud.show_message("You have no %s" % cursor_item)
		return
	var at := ground * 256.0
	var from := (_reverse_from if reverse else _drag_from) * 256.0
	var cmd := {"t": "decon" if cursor_item == "deconstruction-planner" else "upgrade", "i": slot,
		"x1": int(from.x), "y1": int(from.y), "x2": int(at.x), "y2": int(at.y), "cancel": 1 if cancel else 0}
	if reverse:
		cmd["down"] = 1
	Bridge.send(cmd)


## Places the held blueprint (a book: its active page) centred at `at`: mode 0 normal (a click), 1
## forced (Shift), 2 super-forced (Ctrl+Shift), Factorio's build modes.
func place_blueprint(at: Vector2, mode: int) -> void:
	var slot := planner_slot()
	if slot == 0:
		hud.show_message("You have no %s" % cursor_item)
		return
	var cmd := {"t": "blueprint", "i": slot, "x": int(at.x * 256.0), "y": int(at.y * 256.0), "d": build_dir, "bm": mode}
	if mode == 2:
		cmd["sf"] = 1
	if build_mirror:
		cmd["m"] = 1  # H / V: the mod places a mirrored copy (V is this turned half way round)
	Bridge.send(cmd)


## Where the held blueprint goes for the mouse at `at`: on whole tiles, or with snap to grid on
## its grid (absolute: the world's grid, moved by its offset), as its ghosts are drawn.
func blueprint_anchor(at: Vector2) -> Vector2:
	var snap: Dictionary = hud.ui.planners.held_snap()
	if snap.is_empty() or not bool(snap.get("absolute", false)):
		return Vector2(roundf(at.x), roundf(at.y))
	var grid: Vector2 = snap["grid"]
	var offset: Vector2 = snap["offset"]
	var cell := ((at - offset) / grid).floor() * grid + offset
	return cell + (grid * 0.5).round()


## Dragging with a blueprint: placed again every step along the drag's axis, as Factorio does.
func _update_blueprint_drag() -> void:
	if _bp_last == Vector2.INF or not _lmb_down or not has_ground or not (cursor_item in ["blueprint", "blueprint-book"]):
		return
	var step := Vector2(hud.ui.planners.held_step(world.protos, build_dir))
	if step.x <= 0 or step.y <= 0:
		return
	var d := ground - _bp_last
	if _bp_axis == Vector2.ZERO:
		if absf(d.x) >= step.x * 0.5 or absf(d.y) >= step.y * 0.5:
			_bp_axis = Vector2(signf(d.x), 0) if absf(d.x) / step.x >= absf(d.y) / step.y else Vector2(0, signf(d.y))
		else:
			return
	var along := d.dot(_bp_axis)
	var length := absf(step.dot(_bp_axis))
	var placed := 0
	while along >= length * 0.5 and placed < 8:
		_bp_last += _bp_axis * length
		place_blueprint(_bp_last, _bp_mode)
		along -= length
		placed += 1


## The shortcut tools, used over the dragged area: copy or cut it to the clipboard (then paste it),
## make a blueprint of it in the inventory, or mark it for deconstruction (Shift: unmark).
func _use_tool(cancel: bool) -> void:
	var a := _drag_from * 256.0
	var b := ground * 256.0
	var area := {"x1": int(a.x), "y1": int(a.y), "x2": int(b.x), "y2": int(b.y)}
	match cursor_tool:
		"decon":
			var cmd := {"t": "decon", "i": 0, "cancel": 1 if cancel else 0}
			cmd.merge(area)
			Bridge.send(cmd)
		"copy", "cut", "blueprint":
			var cmd := {"t": "copy", "cut": 1 if cursor_tool == "cut" else 0, "bp": 1 if cursor_tool == "blueprint" else 0}
			cmd.merge(area)
			if cursor_tool == "blueprint" and reselect_slot != 0:
				cmd["to"] = reselect_slot
			Bridge.send(cmd)
			if cursor_tool == "blueprint":
				hold("")
			else:
				build_dir = 0
				hold_tool("paste")  # the clipboard arrives as `clip`; until then nothing is drawn


## Ctrl+V or after a copy: the clipboard's ghosts, centred where the mouse is.
func _paste() -> void:
	if not has_ground or hud.ui.model.clipboard.is_empty():
		return
	Bridge.send({"t": "paste", "x": int(ground.x * 256.0), "y": int(ground.y * 256.0), "d": build_dir})


## The stack of the held blueprint or planner: the library's (-1), the one picked up from the
## inventory, or the first of its item; 0 for none.
func planner_slot() -> int:
	if cursor_slot != 0:
		return cursor_slot
	if not hud.ui.hand.is_empty() and hud.ui.hand["role"] == "main":
		return int(hud.ui.hand["index"])
	return _slot_of(cursor_item)


## The first main inventory slot (1-based) holding an item, from the mod's `slots`; 0 if none.
func _slot_of(item: String) -> int:
	var slots: Array = hud.ui.model.main_slots
	for i in slots.size():
		var s: Dictionary = slots[i]
		if s.get("item", "") == item:
			return i + 1
	return 0


func _update_building(delta := 0.0) -> void:
	if not _lmb_down or cursor_item == "" or cursor_tool != "" or not has_ground or PLANNERS.has(cursor_item):
		return
	# Shift+click, or nothing left of it (the pipette's ghost cursor): a ghost for the robots. In
	# remote view everything placed is a ghost, as in Factorio 2.0 (the mod wants charted ground).
	var ghost := _lmb_shift or hud.count_of(cursor_item) == 0 or hud.ui.remote
	if not tile_brush.use_of(cursor_item).is_empty():
		tile_brush.paint(cursor_item, ground, ghost, delta)
		return
	if not capsule_aim.use_of(cursor_item).is_empty():
		if not hud.ui.remote:
			capsule_aim.hold(cursor_item, ground, delta)
		return
	if _rail_click:
		return  # the rail planner's click: the path is built on release
	if world.protos.placed_entity(cursor_item) == null or not hud.ui.can_build_from_hand():
		return
	# Holding the button builds along the way, as Factorio drags (drag_build.gd).
	if not drag.active():
		drag.begin(cursor_item, world.protos.placed_entity(cursor_item), ground, ghost)
	else:
		drag.update(ground)


func _rotate(reverse: bool) -> void:
	if cursor_tool == "" and not tile_brush.use_of(cursor_item).is_empty():
		if str(tile_brush.use_of(cursor_item)[1]) != "":
			tile_brush.alt = not tile_brush.alt  # hazard concrete: the stripes the other way
		return
	if cursor_tool == "paste":
		build_dir = posmod(build_dir + (-4 if reverse else 4), 16)
	elif cursor_item != "" and (world.protos.placed_entity(cursor_item) != null or PLANNERS.has(cursor_item)):
		# Rails also go diagonally.
		var proto: ProtoDB.EntityProto = world.protos.placed_entity(cursor_item)
		var step := 2 if proto != null and proto.type == "straight-rail" else 4
		build_dir = posmod(build_dir + (-step if reverse else step), 16)
	elif hovered != null:
		# Nothing that builds in the cursor (or an item that doesn't, like a plate): R turns the
		# entity under the mouse, as in Factorio.
		Bridge.send({"t": "rotate", "u": hovered.unit, "p": hovered.proto_id, "x": hovered.fixed.x, "y": hovered.fixed.y, "rev": 1 if reverse else 0})


## H / V: flips what is being built, or the entity under the mouse (Factorio 2.0 mirrors it; a
## vertical flip is a horizontal one turned half way round).
func _flip(vertical: bool) -> void:
	if cursor_item != "" and cursor_tool == "":
		build_mirror = not build_mirror
		if vertical:
			build_dir = posmod(build_dir + 8, 16)
		hud.show_message("Flipped" if build_mirror else "Not flipped")
	elif hovered != null and hovered.unit > 0:
		Bridge.send({"t": "flip", "u": hovered.unit, "p": hovered.proto_id, "x": hovered.fixed.x, "y": hovered.fixed.y, "v": 1 if vertical else 0})


## Q: with nothing held over an entity, the pipette (its item, turned the same way; a ghost cursor
## when there are none); otherwise empties the cursor.
func _pipette_or_clear() -> void:
	if cursor_item == "" and over_gui and hud.ui.slot_pipette():
		return  # over a window: the item of the slot under the mouse (factorio_ui.gd)
	# Over an entity Q is the pipette, also with something else held (that goes back first, as in
	# 2.1.23); over nothing, or over what is already held, it clears the cursor.
	var item := item_for(hovered) if hovered != null and not over_gui and cursor_tool == "" else ""
	if item != "" and item != cursor_item:
		hud.ui.clear_cursor()
		hold("")
	if cursor_item == "" and item != "":
		var quality := str(hovered.extra.get("q", "normal"))
		hud.ui.pick_from_inventory(item)
		if cursor_item != item:
			hold(item)
		# Factorio's smart pipette picks the entity's own quality (a ghost's too).
		cursor_quality = quality if quality != "" else "normal"
		build_dir = hovered.dir
		if hud.count_of(item) == 0:
			hud.show_message("None in the inventory: builds ghosts")
		return
	hud.ui.clear_cursor()
	hold("")


## The item that builds an entity (its ghost's entity for a ghost), or "".
func item_for(r: WorldMirror.Rec) -> String:
	var proto: ProtoDB.EntityProto = world.protos.entity(r.proto_id)
	if proto == null:
		return ""
	if proto.type == "entity-ghost" and r.extra.has("gh"):
		proto = world.protos.entity(int(r.extra["gh"]))
		if proto == null:
			return ""
	if world.protos.item_names.values().has(proto.name):
		return proto.name
	for item in world.protos.item_places:
		if world.protos.item_places[item] == proto.name:
			return str(item)
	return ""


## Ctrl+click on an entity: the held stack in (right: half), or its output out (right: half), like
## Factorio's fast transfer. The mod checks reach and what fits.
func _fast_transfer(half: bool) -> void:
	if not has_ground:
		return
	var target: WorldMirror.Rec = world.pick(ground)
	if target == null or target.unit == 0:
		return
	_fast_target = target
	var cmd := {"t": "fast", "u": target.unit, "p": target.proto_id, "x": target.fixed.x, "y": target.fixed.y, "half": 1 if half else 0}
	if cursor_item != "" and cursor_tool == "":
		cmd["item"] = cursor_item
		var n: int = hud.ui.hand_count()
		if n > 0:
			cmd["n"] = n
		if cursor_quality != "normal":
			cmd["q"] = cursor_quality
	Bridge.send(cmd)


## Factorio lets Ctrl+click and Shift+click (paste settings) be dragged: holding the button with the
## key down, each further entity the mouse crosses gets the same transfer or paste once.
func _update_drag_clicks() -> void:
	if _fast_button != MOUSE_BUTTON_NONE:
		if not Input.is_mouse_button_pressed(_fast_button) or not Input.is_key_pressed(KEY_CTRL) or over_gui or not has_ground:
			if not Input.is_mouse_button_pressed(_fast_button):
				_fast_button = MOUSE_BUTTON_NONE
			return
		var target: WorldMirror.Rec = world.pick(ground)
		if target != null and target.unit != 0 and target != _fast_target:
			_fast_transfer(_fast_button == MOUSE_BUTTON_RIGHT)
	if _paste_dragging:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or not Input.is_key_pressed(KEY_SHIFT):
			_paste_dragging = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			return
		if hovered != null and hovered != _paste_target and not over_gui:
			_paste_settings(hovered)


## Shift+right click: remembers the entity to paste its settings from.
func _copy_settings() -> void:
	var target: WorldMirror.Rec = world.pick(ground) if has_ground else null
	if target == null or target.unit == 0:
		return
	var proto: ProtoDB.EntityProto = world.protos.entity(target.proto_id)
	copied_settings = {"u": target.unit, "p": target.proto_id, "x": target.fixed.x, "y": target.fixed.y,
		"name": proto.name if proto != null else ""}
	hud.show_message("Settings copied from %s" % (hud.ui.entity_name(proto.name) if proto != null else "entity"))


## Shift+left click: pastes the copied settings (recipe, filters, requests, combinator settings...)
## with LuaEntity.copy_settings.
func _paste_settings(target: WorldMirror.Rec) -> void:
	_paste_target = target
	if copied_settings.is_empty() or target.unit == 0 or target.unit == int(copied_settings["u"]):
		return
	Bridge.send({"t": "paste_settings", "f": [copied_settings["u"], copied_settings["p"], copied_settings["x"], copied_settings["y"]],
		"u": target.unit, "p": target.proto_id, "x": target.fixed.x, "y": target.fixed.y})


## Ctrl+Z: takes back the newest of this client's own building (marks it for deconstruction) or
## mining (puts a ghost back), as Factorio's undo does for a player. Ctrl+Y does it again.
func undo() -> void:
	if _undo.is_empty():
		hud.show_message("Nothing to undo")
		return
	var a: Dictionary = _undo.pop_back()
	_redo.append(a)
	_reverse(a, true)


func redo() -> void:
	if _redo.is_empty():
		hud.show_message("Nothing to redo")
		return
	var a: Dictionary = _redo.pop_back()
	_undo.append(a)
	_reverse(a, false)


## Undo (back = true) or redo an action: a build is undone by a deconstruction mark and redone by
## a ghost; a mining the other way round.
func _reverse(a: Dictionary, back: bool) -> void:
	if str(a["do"]) == "mod":
		if back:
			hud.ui.model.planners.undo(int(a["h"]))
		else:
			hud.ui.model.planners.redo(int(a["h"]))
		hud.show_message(("Undo: %s" if back else "Redo: %s") % str(a["what"]).capitalize())
		return
	var at := Vector2(float(a["x"]), float(a["y"])) * 256.0
	var place: bool = (str(a["do"]) == "mine") == back
	if place:
		Bridge.send({"t": "build", "item": a["item"], "x": int(at.x), "y": int(at.y), "d": int(a["d"]), "ghost": 1})
	else:
		# nh: the mod doesn't remember this one (it is the undo itself).
		Bridge.send({"t": "decon", "i": 0, "x1": int(at.x) - 32, "y1": int(at.y) - 32, "x2": int(at.x) + 32, "y2": int(at.y) + 32,
			"cancel": 0, "nh": 1})


## The mod remembered an action (`hist`): it goes on the undo list with this client's own.
func remember_mod(h: int, what: String) -> void:
	_remember({"do": "mod", "h": h, "what": what})


## Ctrl+mouse wheel: the held item's quality, through the qualities the force has (Factorio 2.x).
func cycle_quality(step: int) -> void:
	if cursor_item == "" or cursor_tool != "" or PLANNERS.has(cursor_item):
		return
	var list: Array = hud.ui.model.planners.unlocked_qualities()
	var at := maxi(list.find(cursor_quality), 0)
	var next: String = list[clampi(at + step, 0, list.size() - 1)]
	if next != cursor_quality:
		cursor_quality = next
		hud.show_message("Quality: %s" % next.capitalize())


## Shift+mouse wheel with a book held: its next or previous page.
func _cycle_book(step: int) -> void:
	if cursor_item == "blueprint-book":
		hud.ui.planners.cycle_book(planner_slot(), step)


func _remember(a: Dictionary) -> void:
	_undo.append(a)
	_redo.clear()
	while _undo.size() > HISTORY:
		_undo.pop_front()


func _openable(r: WorldMirror.Rec) -> bool:
	var proto: ProtoDB.EntityProto = world.protos.entity(r.proto_id)
	# Anything on a circuit network opens to its circuit settings (a belt, a wall, a rail signal).
	return r.unit > 0 and proto != null and (OPENABLE_TYPES.has(proto.type) or r.extra.has("r") or r.extra.has("g"))


func _is_pole(r: WorldMirror.Rec) -> bool:
	var proto: ProtoDB.EntityProto = world.protos.entity(r.proto_id)
	return proto != null and proto.type == "electric-pole"


## A click with a wire tool (or Shift+click on a pole: Factorio's "remove pole cables").
func _wire_click(shift: bool) -> void:
	var target: WorldMirror.Rec = hovered if hovered != null else (world.pick(ground) if has_ground else null)
	if shift and target != null and _is_pole(target) and cursor_tool in ["", "copper-wire"]:
		wire_tool.clear_cables(target)
		return
	var text := wire_tool.click(cursor_tool, target, ground)
	if text != "":
		hud.show_message(text)


## The vehicle or wagon the mouse ray hits (its oriented box and model), or [].
func _mover_under_mouse() -> Array:
	if movers == null or over_gui or cursor_item != "" or _clean_shot:
		return []
	var screen: Vector2 = rig.aim_position() if rig.first_person else hud.ui.mouse_position()
	var r := rig.ray(screen)
	return movers.pick_ray(r[0], r[1], OPENABLE_MOVERS)


## A click on a vehicle or wagon (a mover) opens its screen, like Factorio's.
func _open_mover() -> bool:
	var m: Array = hovered_mover
	if m.is_empty():
		return false
	var at: Vector2i = m[2]
	_request_open(int(m[0]), {"t": "open", "u": int(m[0]), "p": int(m[1]), "x": at.x, "y": at.y})
	return true


## The unit number of the nearest entity of this prototype the world mirror has, or 0.
func _nearest_named(proto_name: String) -> int:
	var best := 0
	var best_d := INF
	var here := Vector2(avatar.position.x, avatar.position.z) if avatar != null else Vector2.ZERO
	for key in world.entities:
		var r: WorldMirror.Rec = world.entities[key]
		if r.unit == 0 or world.protos.entity(r.proto_id) == null or world.protos.entity(r.proto_id).name != proto_name:
			continue
		var d := r.pos.distance_squared_to(here)
		if d < best_d:
			best_d = d
			best = r.unit
	return best


## Opens a building's screen. From the remote view it may be out of reach: the mod then opens it
## for its settings only, where radars cover it (`rv`), as Factorio 2.x does.
func _request_open(unit: int, cmd: Dictionary) -> void:
	if hud.ui.remote:
		cmd["rv"] = 1
		if hud.ui.viewing_si > 0:
			cmd["si"] = hud.ui.viewing_si
	hud.screen.request(unit, cmd)


func _open(r: WorldMirror.Rec) -> void:
	_request_open(r.unit, {"t": "open", "u": r.unit, "p": r.proto_id, "x": r.fixed.x, "y": r.fixed.y})


func _update_highlights() -> void:
	_ghost.visible = false
	_ghost_model.visible = false
	for piece in _ghost_pieces:
		piece.visible = false
	_drag_box.visible = false
	_reach_box.visible = false
	_reach_lines.visible = false
	var marks: Array = []
	if hovered != null:
		var proto: ProtoDB.EntityProto = world.protos.entity(hovered.proto_id)
		if proto != null:
			marks = hover_marks(proto, hovered.pos, hovered.dir)
			if proto.type == "roboport" and roboport_links != null:
				var info: Dictionary = hud.ui.model.hover_info
				var said = info.get("rn") if int(info.get("u", 0)) == hovered.unit else null
				for l in roboport_links.hovered_lines(hovered.pos, _logistic_radius(proto.id), hovered.unit, said):
					marks.append(CursorOverlay.line(l[0], l[1]))
	elif not hovered_mover.is_empty():
		marks.append(CursorOverlay.brackets(hovered_mover[3], hovered_mover[4], float(hovered_mover[5])))
	marks.append_array(_update_drag_box())
	if cursor_tool == "spidertron":
		spider_remote.query()
		marks.append_array(spider_remote.marks(movers))
	_update_paste_preview()
	var held := cursor_item if cursor_tool == "" else ""
	var ghost_mode := Input.is_key_pressed(KEY_SHIFT) or hud.count_of(cursor_item) == 0 or hud.ui.remote
	tile_brush.update_preview(held, has_ground, ground, ghost_mode, _rmb_down)
	capsule_aim.update_preview(held, has_ground, ground)
	rail_planner.update(held, has_ground, ground, ghost_mode)
	var placed: ProtoDB.EntityProto = world.protos.placed_entity(cursor_item) if cursor_item != "" and cursor_tool == "" else null
	if not rail_planner.anchor.is_empty() and not rail_planner.use_of(held).is_empty():
		placed = null  # the planner draws its path instead of one rail
	_build_refusal = ""
	if placed != null and has_ground:
		var proto := placed
		var size := proto.tile_size
		if build_dir == 4 or build_dir == 12:
			size = Vector2i(size.y, size.x)
		var pos := Vector2(_snap(ground.x, size.x), _snap(ground.y, size.y))
		if proto.type == "straight-rail":
			pos = Vector2(floorf(ground.x / 2.0) * 2.0 + 1.0, floorf(ground.y / 2.0) * 2.0 + 1.0)
		# Space Age: the planet's pressure, gravity or magnetic field may forbid it (planet.nb).
		_build_refusal = hud.ui.model.cant_build_reason(proto.id)
		# Empty space (round a platform) holds nothing up: red, as Factorio draws it (F6).
		if _build_refusal == "" and _on_void(pos, size):
			_build_refusal = "Can't build on empty space"
		var ok := (ghost_mode or (hud.ui.can_build_from_hand() and _in_reach(pos, size))) and not _blocked(proto, pos, size) \
			and _build_refusal == ""
		show_build_ghost(proto, pos, ok, ghost_mode)
		var x: Dictionary = hud.ui.model.eprops.get(proto.id, {}).get("x", {})
		marks.append_array(CursorOverlay.marks_for(proto.type, x, pos, build_dir, true))
		if proto.type == "roboport" and roboport_links != null:
			for l in roboport_links.held_lines(pos, _logistic_radius(proto.id)):
				marks.append(CursorOverlay.line(l[0], l[1]))
		_update_reach(proto, pos)
	_overlay.show_marks(marks)


## A roboport prototype's logistic radius (tiles) from its `eprops` overlay.
func _logistic_radius(proto_id: int) -> float:
	return float(hud.ui.model.eprops.get(proto_id, {}).get("x", {}).get("lr", 25.0))


## The held item's entity where it would go: its model (or a box without one) turned and flipped
## as it would be built, translucent, red when it can't be built there.
func show_build_ghost(proto: ProtoDB.EntityProto, pos: Vector2, ok: bool, ghost_mode: bool) -> void:
	var extra := build_extra(proto, pos, build_dir)
	var model := ModelLibrary.mesh_for_entity(proto.name, proto.type, extra, build_dir)
	var flip := Basis.from_scale(Vector3(-1, 1, 1)) if build_mirror else Basis.IDENTITY
	if model != null:
		_ghost_model.mesh = model
		_ghost_model.transform = ModelLibrary.placed(proto.name, proto.type, build_dir, extra, Vector3(pos.x, 0.0, pos.y), flip)
		_ghost_model.material_override = _ghost_model_materials[("ghost" if ghost_mode else "ok") if ok else "bad"]
		_ghost_model.visible = true
		if proto.type == "cargo-bay":
			_show_cargo_pieces(proto, pos, _ghost_model.material_override)
	else:
		_ghost.transform = Visuals.placeholder_transform(proto, pos, build_dir, Visuals.height_for(proto))
		_ghost.transform.basis = _ghost.transform.basis * flip
		_ghost.material_override = (_ghost_blue if ghost_mode else _ghost_ok) if ok else _ghost_bad
		_ghost.visible = true


## The held bay's frame: without it the preview is only the bay's machine, about 3 by 2 of its tiles.
func _show_cargo_pieces(proto: ProtoDB.EntityProto, pos: Vector2, material: Material) -> void:
	var cb := world.cargo_mask(WorldMirror.cargo_rect(proto, pos), true)
	var i := 0
	for place in ModelLibrary.cargo_places(cb, Vector3(pos.x, 0.0, pos.y)):
		if not ModelLibrary.ready(place[0]):
			continue
		if i == _ghost_pieces.size():
			var mi := MeshInstance3D.new()
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world.add_child(mi)
			_ghost_pieces.append(mi)
		var piece := _ghost_pieces[i]
		piece.mesh = ModelLibrary.mesh_for(place[0])
		piece.position = place[1]
		piece.set_meta("model", place[0])
		piece.material_override = material
		piece.visible = piece.mesh != null
		i += 1


## The held cargo bay's edge pieces shown: their model names, for tests.
func build_ghost_pieces() -> Array:
	return _ghost_pieces.filter(func(p): return p.visible).map(func(p): return p.get_meta("model"))


## Whether the build ghost is drawn, and red: [visible, can't place], for tests.
func build_ghost_state() -> Array:
	var shown := _ghost_model if _ghost_model.visible else _ghost
	return [shown.visible, shown.material_override == _ghost_model_materials["bad"] or shown.material_override == _ghost_bad]


## What hovering over an entity shows, like Factorio: its selection box's corners, and from its
## `eprops` overlay an inserter's pickup and drop arrows, a roboport's logistic and construction
## areas, a mining drill's area and output, fluid connections.
func hover_marks(proto: ProtoDB.EntityProto, pos: Vector2, dir: int) -> Array:
	var rect := WorldMirror.selection_rect(proto, pos, dir)
	var marks: Array = [CursorOverlay.brackets(rect.get_center(), rect.size * 0.5)]
	if proto.type != "entity-ghost":
		var x: Dictionary = hud.ui.model.eprops.get(proto.id, {}).get("x", {})
		marks.append_array(CursorOverlay.marks_for(proto.type, x, pos, dir, false))
	return marks


## The extra data the held item's model is picked by (ModelLibrary.model_name), as the entity would
## have it there: a straight belt, an underground's end (an exit when the nearest underground of its
## kind behind it facing the same way, or its ghost, is an entrance: the mod builds it so), a lone
## pipe or wall piece.
func build_extra(proto: ProtoDB.EntityProto, pos: Vector2, dir: int) -> Dictionary:
	match proto.type:
		"transport-belt":
			return {"s": "s"}
		"pipe", "heat-pipe":
			return {"pc": 0}
		"wall":
			return {"wc": 0}
		"underground-belt":
			var reach := int(hud.ui.model.eprops.get(proto.id, {}).get("under", 0.0))
			var back := -CursorOverlay.dir_vector(dir)
			for i in range(1, reach + 1):
				var r: WorldMirror.Rec = world.pick(pos + back * i)
				if r == null:
					continue
				var same := r.proto_id == proto.id or int(r.extra.get("gh", -1)) == proto.id
				if same and r.dir == dir:
					return {"u": "o" if str(r.extra.get("u", "i")) == "i" else "i"}
			return {"u": "i"}
	return {}


## Factorio's build previews: an electric pole's supply area (blue) and wires to the poles in reach;
## an underground belt's or pipe's reach along the way it faces. From the mod's `eprops`.
func _update_reach(proto: ProtoDB.EntityProto, pos: Vector2) -> void:
	var props: Dictionary = hud.ui.model.eprops.get(proto.id, {})
	if props.is_empty():
		return
	var supply := float(props.get("supply", 0.0))
	var wire := float(props.get("wire", 0.0))
	var under := float(props.get("under", 0.0))
	_reach_mesh.clear_surfaces()
	var lines := 0
	if supply > 0.0:
		_reach_box.transform = Transform3D(Basis.from_scale(Vector3(supply * 2.0, 0.04, supply * 2.0)), Vector3(pos.x, 0.03, pos.y))
		_reach_box.visible = true
	if wire > 0.0:
		_reach_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var center := WorldMirror.chunk_of(pos)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cv = world.chunks.get(center + Vector2i(dx, dy))
				if cv == null:
					continue
				for r in cv.entities.values():
					var other: ProtoDB.EntityProto = world.protos.entity(r.proto_id)
					if other != null and other.type == "electric-pole" and r.pos.distance_to(pos) <= wire and lines < 5:
						_reach_mesh.surface_add_vertex(Vector3(pos.x, 2.0, pos.y))
						_reach_mesh.surface_add_vertex(Vector3(r.pos.x, 2.0, r.pos.y))
						lines += 1
		if lines == 0:  # an empty surface isn't allowed
			_reach_mesh.surface_add_vertex(Vector3(pos.x, 2.0, pos.y))
			_reach_mesh.surface_add_vertex(Vector3(pos.x, 2.0, pos.y))
		_reach_mesh.surface_end()
		_reach_lines.visible = true
	if under > 0.0:
		var ahead := Vector2(sin(build_dir / 16.0 * TAU), -cos(build_dir / 16.0 * TAU))
		var mid := pos + ahead * (under + 1.0) * 0.5
		var long := Vector2(absf(ahead.x), absf(ahead.y)) * (under + 1.0) + Vector2(absf(ahead.y), absf(ahead.x))
		_reach_box.transform = Transform3D(Basis.from_scale(Vector3(maxf(long.x, 0.9), 0.04, maxf(long.y, 0.9))), Vector3(mid.x, 0.03, mid.y))
		_reach_box.visible = true


## The box being dragged with a planner or tool, in its colour, and Factorio's highlight round
## each entity it will take (marks for the overlay).
func _update_drag_box() -> Array:
	var reverse := _reverse_from != Vector2.INF and (cursor_item == "upgrade-planner" or cursor_tool == "spidertron")
	if not (_lmb_down or reverse) or not has_ground:
		return []
	var kind := cursor_tool
	if kind == "":
		kind = {"deconstruction-planner": "decon", "upgrade-planner": "upgrade"}.get(cursor_item, "")
	if kind == "" or kind == "paste":
		return []
	var shift := Input.is_key_pressed(KEY_SHIFT) and not reverse
	var cancel := shift and kind in ["decon", "upgrade"]
	var r := Rect2(_reverse_from if reverse else _drag_from, Vector2.ZERO).expand(ground)
	var color := selection_color(kind, shift, reverse) if kind != "spidertron" else SpiderRemote.box_color(shift, reverse)
	var material := Visuals.ghost_material(Color(color, 0.95))
	var t := BOX_EDGE
	var c := r.get_center()
	# top, bottom, left, right
	var edges := [[Vector2(c.x, r.position.y), Vector2(r.size.x + t, t)], [Vector2(c.x, r.end.y), Vector2(r.size.x + t, t)],
		[Vector2(r.position.x, c.y), Vector2(t, r.size.y + t)], [Vector2(r.end.x, c.y), Vector2(t, r.size.y + t)]]
	_drag_box.transform = Transform3D.IDENTITY
	for i in 4:
		var edge := _drag_box.get_child(i) as MeshInstance3D
		var at: Vector2 = edges[i][0]
		var sz: Vector2 = edges[i][1]
		edge.transform = Transform3D(Basis.from_scale(Vector3(sz.x, 0.04, sz.y)), Vector3(at.x, 0.05, at.y))
		edge.material_override = material
	_drag_box.visible = true
	var marks: Array = []
	if kind == "spidertron":
		for u in SpiderRemote.spiders_in(movers, r):
			var at = movers.position_of(u)
			if at is Vector3:
				marks.append(CursorOverlay.brackets(Vector2(at.x, at.z), Vector2(1.5, 1.5), 0.0, color))
		return marks
	for e in (selected_by(kind, r, cancel) if not reverse else downgraded_by(r)):
		var proto: ProtoDB.EntityProto = world.protos.entity(e.proto_id)
		var box := WorldMirror.selection_rect(proto, e.pos, e.dir)
		marks.append(CursorOverlay.brackets(box.get_center(), box.size * 0.5, 0.0, color))
		if marks.size() >= 400:
			break
	return marks


## The selection box: four thin edges under one node (the node itself draws nothing).
func _box_edges() -> void:
	_drag_box.mesh = null
	while _drag_box.get_child_count() < 4:
		var edge := MeshInstance3D.new()
		edge.mesh = Visuals.box_mesh()
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drag_box.add_child(edge)


## Factorio's selection colour of a tool: select, alt_select (Shift) or reverse_select (right-drag).
static func selection_color(kind: String, shift: bool, reverse := false) -> Color:
	if reverse and kind == "upgrade":
		return SELECT_COLORS["upgrade_reverse"]
	return SELECT_COLORS.get(kind + ("_alt" if shift else ""), SELECT_COLORS["blueprint"])


## What an upgrade planner's right-drag takes: what its mappings lead to (downgraded back).
func downgraded_by(r: Rect2) -> Array:
	var settings = BpString.body(hud.ui.planners.held_record).get("settings", {}) if not hud.ui.planners.held_record.is_empty() else {}
	var targets := {}
	if settings is Dictionary:
		for m in BpString._list(settings.get("mappers")):
			if m.get("to") is Dictionary and m.get("from") is Dictionary:
				targets[str(m["to"].get("name", ""))] = true
	var out: Array = []
	var c0 := WorldMirror.chunk_of(r.position)
	var c1 := WorldMirror.chunk_of(r.end)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cv = world.chunks.get(Vector2i(cx, cy))
			if cv == null:
				continue
			for e in cv.entities.values():
				var proto: ProtoDB.EntityProto = world.protos.entity(e.proto_id)
				if proto != null and r.has_point(e.pos) and targets.has(proto.name):
					out.append(e)
	return out


## The entities a selection of this kind over the rect takes, as Factorio picks them: the
## deconstruction planner by its filters (whitelist / blacklist, trees and rocks only), the
## upgrade planner what it has a mapping for, blueprints and copies the force's buildings (not
## trees, rocks or ore); with `cancel`, what carries that mark.
func selected_by(kind: String, r: Rect2, cancel: bool) -> Array:
	var out: Array = []
	var planner: Dictionary = hud.ui.planners.held_record if cursor_tool == "" else {}
	var settings = BpString.body(planner).get("settings", {}) if not planner.is_empty() else {}
	if not (settings is Dictionary):
		settings = {}
	var filters := {}
	for f in BpString._list(settings.get("entity_filters")):
		filters[str(f.get("name", ""))] = true
	var blacklist := int(settings.get("entity_filter_mode", 0)) == 1
	var nature_only := bool(settings.get("trees_and_rocks_only", false))
	var upgrades := {}
	for m in BpString._list(settings.get("mappers")):
		if m.get("from") is Dictionary:
			upgrades[str(m["from"].get("name", ""))] = true
	var c0 := WorldMirror.chunk_of(r.position)
	var c1 := WorldMirror.chunk_of(r.end)
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var cv = world.chunks.get(Vector2i(cx, cy))
			if cv == null:
				continue
			for e in cv.entities.values():
				if not r.has_point(e.pos):
					continue
				var proto: ProtoDB.EntityProto = world.protos.entity(e.proto_id)
				if proto == null or proto.type == "resource" or proto.type == "character":
					continue
				var nature := NATURE_TYPES.has(proto.type)
				var ok := false
				match kind:
					"decon":
						if cancel:
							ok = e.extra.has("d")
						elif nature_only:
							ok = nature
						elif filters.is_empty():
							ok = true
						else:
							ok = filters.has(proto.name) != blacklist
					"upgrade":
						ok = e.extra.has("up") if cancel else (upgrades.is_empty() or upgrades.has(proto.name)) and not nature and proto.type != "entity-ghost"
					_:
						ok = not nature and e.unit > 0
				if ok:
					out.append(e)
	return out


## While pasting, or holding a blueprint: its entities as blue ghosts around the mouse, turned with R.
func _update_paste_preview() -> void:
	var clip: Array = hud.ui.model.clipboard if cursor_tool == "paste" and has_ground else []
	if has_ground and cursor_tool == "" and cursor_item in ["blueprint", "blueprint-book"]:
		clip = hud.ui.planners.held_preview(world.protos)  # Factorio shows a held blueprint's ghosts
	while _paste_ghosts.size() < mini(clip.size(), 400):
		var m := MeshInstance3D.new()
		m.mesh = Visuals.box_mesh()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.material_override = _ghost_blue
		world.add_child(m)
		_paste_ghosts.append(m)
	var turn := build_dir / 4
	var centre := Vector2(roundf(ground.x), roundf(ground.y))
	if cursor_tool == "" and cursor_item in ["blueprint", "blueprint-book"]:
		centre = blueprint_anchor(ground)
	elif not clip.is_empty():
		centre = _paste_centre(clip[0], turn)
	for i in _paste_ghosts.size():
		var m := _paste_ghosts[i]
		m.visible = i < clip.size()
		if not m.visible:
			continue
		var e: Dictionary = clip[i]
		var proto: ProtoDB.EntityProto = world.protos.entity(int(e["p"]))
		if proto == null:
			m.visible = false
			continue
		var offset: Vector2 = e["at"]
		var ed := int(e["d"])
		if build_mirror and cursor_tool == "":
			# A flipped blueprint: mirrored east-west, then turned (the mod's mirrored copy).
			offset.x = -offset.x
			ed = (16 - ed) % 16
		for t in turn:
			offset = Vector2(-offset.y, offset.x)  # a quarter turn clockwise (y is south)
		m.transform = Visuals.placeholder_transform(proto, centre + offset, posmod(ed + build_dir, 16), Visuals.height_for(proto))


## Where the clipboard's middle goes (its offsets are from the middle of its footprints): the mouse,
## moved as little as puts its first entity on the tile grid, as Factorio pastes it.
func _paste_centre(first: Dictionary, turn: int) -> Vector2:
	var proto: ProtoDB.EntityProto = world.protos.entity(int(first["p"]))
	if proto == null:
		return Vector2(roundf(ground.x), roundf(ground.y))
	var offset: Vector2 = first["at"]
	for t in turn:
		offset = Vector2(-offset.y, offset.x)
	var size := proto.tile_size
	if posmod(int(first["d"]) + build_dir, 8) == 4:
		size = Vector2i(size.y, size.x)
	var at := ground + offset
	return ground + Vector2(_snap(at.x, size.x), _snap(at.y, size.y)) - at


## Within the character's build distance (to the footprint's nearest edge, as Factorio measures).
func _in_reach(pos: Vector2, size: Vector2i) -> bool:
	if avatar == null:
		return true
	var c := avatar.ground_position()
	var half := Vector2(size) * 0.5
	var d := Vector2(maxf(0.0, absf(c.x - pos.x) - half.x), maxf(0.0, absf(c.y - pos.y) - half.y))
	return d.length() <= BUILD_REACH


## Something other than ore, ghosts or what the item can replace (the same entity: it turns; the
## same type: a fast-replace, like a faster belt) is in the footprint. Movers aren't checked.
func _blocked(proto: ProtoDB.EntityProto, pos: Vector2, size: Vector2i) -> bool:
	var area := Rect2(pos - Vector2(size) * 0.5, Vector2(size)).grow(-0.05)
	var center := WorldMirror.chunk_of(pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cv = world.chunks.get(center + Vector2i(dx, dy))
			if cv == null:
				continue
			for r in cv.entities.values():
				var other: ProtoDB.EntityProto = world.protos.entity(r.proto_id)
				if other == null or other.type in ["resource", "entity-ghost", "tile-ghost"] or other.type == proto.type:
					continue
				if WorldMirror.selection_rect(other, r.pos, r.dir).intersects(area):
					return true
	return false


## Whether a tile under the footprint is empty space (nothing to stand on, as round a platform).
func _on_void(pos: Vector2, size: Vector2i) -> bool:
	var x0 := floori(pos.x - size.x * 0.5 + 0.05)
	var y0 := floori(pos.y - size.y * 0.5 + 0.05)
	for dy in size.y:
		for dx in size.x:
			if world.protos.is_void(world.tile_at(x0 + dx, y0 + dy)):
				return true
	return false


## Same grid snapping as the mod: odd sizes centre on a tile, even sizes on a tile corner (rails:
## a two-tile grid, see _update_highlights).
static func _snap(v: float, size: int) -> float:
	if size % 2 == 1:
		return floorf(v) + 0.5
	return floorf(v + 0.5)


## Puts an item in the cursor (the quickbar, a picked-up stack), or empties it with "". Anything
## can be held, as in Factorio; only what places an entity (or a planner) builds.
func hold(item: String, slot := 0) -> void:
	reselect_slot = 0
	if item != cursor_item:
		cursor_quality = "normal"
		rail_planner.clear()
		tile_brush.alt = false
	cursor_item = item
	cursor_tool = ""
	cursor_slot = slot if item != "" else 0
	wire_tool.cancel()
	if item == "":
		build_mirror = false
	if PLANNERS.has(item):
		hud.ui.planners.held_changed(item, planner_slot())


## Puts one of the shortcut tools (TOOLS) in the cursor.
func hold_tool(tool: String) -> void:
	hold(str(TOOLS.get(tool, "")))
	cursor_tool = tool
