extends Node3D
## VR through OpenXR (SteamVR, Meta Quest over Link, Windows Mixed Reality, Index, Vive):
##
##   godot --path client --xr-mode on -- --vr                 # tabletop (the default)
##   godot --path client --xr-mode on -- --vr=first-person
##   ... -- --vr --vr-hand=left                                # the laser in the left hand
##
## (add --factorio-port=34200 to connect at once: the menu is only on the desktop window). Off
## unless asked for; without OpenXR running --vr only warns.
##
## Tabletop works like a map editor: the factory is a model on a table at waist height. Grab it
## with a grip and drag it; grab with both grips to move, zoom (hands apart / together) and turn
## it at once. The chunks and live data follow the table's centre, so you can look around the
## whole map while the character stays put. First person: you stand on the character, a tile to
## a metre.
##
## The same buttons in both modes, on any controller with OpenXR's usual inputs (Quest, Index,
## Vive, WMR). Pointer hand (right unless --vr-hand=left):
##   trigger       left click: build, open, select; hold to drag-build
##   A / X         right click: mine, cancel; hold to keep mining
##   B / Y         rotate (R)
##   stick         tabletop: left/right turns the table 45°, up/down zooms; first person: turn 30°
##   stick press   pipette (Q)
##   grip          grab the table
## Other hand:
##   grip          grab the table (with the other grip: move, zoom and turn)
##   trigger       Shift, held: ghosts, shift-clicks
##   stick         walk (the way you look)
##   stick press   tabletop: the table back on the character, at your height
##   A / X         character screen (E)
##   B / Y         show the HUD panel in front of you, or hide it
##   menu          Esc
## The laser on the HUD panel is the mouse there (trigger to click, stick up/down to scroll).
## The desktop keyboard keeps working.

const VrPanel := preload("res://scripts/vr/vr_panel.gd")

enum Mode { TABLETOP, FIRST_PERSON }

## Tabletop: the table's centre is this far in front of the play space's origin (on the floor,
## facing -z), at a height that follows you (recentre).
const TABLE_FORWARD := 0.55
const DEFAULT_TABLE_HEIGHT := 0.85
const DEFAULT_SCALE := 16.0  # world tiles per metre: a 3x3 assembler is 19 cm
const MIN_SCALE := 2.0
const MAX_SCALE := 150.0
const ZOOM_SPEED := 1.6  # per second at full stick
const TABLE_TURN_DEGREES := 45.0
const SNAP_TURN_DEGREES := 30.0
const STICK_DEAD_ZONE := 0.25
const LASER_LENGTH := 400.0  # world units, when it hits nothing
const PANEL_DISTANCE := 0.9  # metres in front of the head when summoned

## main.gd: in_game(), rig, avatar, hud.
var main: Node
var mode := Mode.TABLETOP
var running := false

var origin := XROrigin3D.new()
var head := XRCamera3D.new()
var left := XRController3D.new()
var right := XRController3D.new()
## Which controller has the laser, and the other.
var pointer_hand: XRController3D
var other_hand: XRController3D
var panel := VrPanel.new()

var _laser := MeshInstance3D.new()
var _hands: Array[MeshInstance3D] = []
## Tabletop: tiles per metre, the play space's turn, where it is on the map (xz), the table's
## height in metres, and whether the table follows the character.
var _scale := DEFAULT_SCALE
var _yaw := 0.0
var _at := Vector2.ZERO
var _height := DEFAULT_TABLE_HEIGHT
var _follow := true
var _recentre_in := 1.0  # seconds until the first recentre, once the headset reports a height
## A grab in progress: {hands, world (the map point between them), scale, yaw, span, angle}.
var _grab := {}
var _turned := false  # stick turns and scrolls wait for the stick to come back
var _held := {}  # controller + button -> pressed last frame
var _shift := false
var _game_hud: CanvasLayer
var _panel_pose := Transform3D.IDENTITY  # metres, play space


static func requested() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg == "--vr" or arg.begins_with("--vr="):
			return true
	return false


func _ready() -> void:
	var left_handed := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--vr=first-person":
			mode = Mode.FIRST_PERSON
		elif arg == "--vr-hand=left":
			left_handed = true
	pointer_hand = left if left_handed else right
	other_hand = right if left_handed else left
	_panel_pose = Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)) * Basis(Vector3.RIGHT, deg_to_rad(-15.0)), Vector3(-0.6, 1.25, -0.55))
	var xr := XRServer.find_interface("OpenXR")
	if xr == null or not xr.is_initialized():
		push_warning("VR: OpenXR isn't running. Start the client with --xr-mode on, with a headset and its runtime (SteamVR, Meta Link) on.")
		return
	get_viewport().use_xr = true
	# The headset paces the frames; the desktop window's vsync would halve them.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	running = true
	_build_nodes()
	print("VR: OpenXR running, %s mode, laser in the %s hand" % ["first person" if mode == Mode.FIRST_PERSON else "tabletop",
		"left" if left_handed else "right"])


func _build_nodes() -> void:
	origin.name = "XROrigin"
	add_child(origin)
	head.name = "Head"
	head.near = 0.05
	head.far = 4000.0
	origin.add_child(head)
	for c in [left, right]:
		c.tracker = "left_hand" if c == left else "right_hand"
		c.name = "LeftHand" if c == left else "RightHand"
		origin.add_child(c)
		var hand := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.03, 0.12)
		hand.mesh = box
		c.add_child(hand)
		_hands.append(hand)
	var ray := CylinderMesh.new()
	ray.top_radius = 0.003
	ray.bottom_radius = 0.003
	ray.height = 1.0
	ray.radial_segments = 6
	_laser.mesh = ray
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.75, 0.25, 0.8)
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser.material_override = glow
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pointer_hand.add_child(_laser)
	panel.name = "Panel"
	origin.add_child(panel)
	panel.visible = false
	head.make_current()


func _process(delta: float) -> void:
	if not running:
		return
	var game: bool = main != null and main.in_game() and main.rig != null and is_instance_valid(main.rig)
	if not game:
		_leave_game()
		return
	_enter_game()
	if not head.current:
		head.make_current()  # the camera rig makes its own camera current when a game starts
	if mode == Mode.FIRST_PERSON:
		_first_person()
	else:
		_tabletop(delta)
	var s := origin.world_scale
	# Controllers move in scaled space but keep scale 1: their models, the laser and the panel are
	# in metres times the world scale, so they look the same size whatever the zoom.
	for hand in _hands:
		hand.transform = Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(0.0, 0.0, 0.03 * s))
	panel.transform = Transform3D(_panel_pose.basis.scaled(Vector3.ONE * s), _panel_pose.origin * s)
	_walk()
	_pointer()
	_buttons()


func _enter_game() -> void:
	if _game_hud == main.hud:
		return
	_game_hud = main.hud
	panel.adopt(main.hud)
	panel.visible = true
	main.rig.vr_view = head
	if main.avatar != null and main.avatar.has_method("set_first_person"):
		main.avatar.set_first_person(mode == Mode.FIRST_PERSON)
	_follow = true
	_recentre_in = 1.0


func _leave_game() -> void:
	if _game_hud == null:
		return
	panel.release()
	panel.visible = false
	_game_hud = null
	_grab = {}
	_release_walk()
	_set_shift(false)


# --- first person -----------------------------------------------------------------------------

## You stand on the character: the play space moves so that your head is above it.
func _first_person() -> void:
	origin.world_scale = 1.0
	var stick := _stick(pointer_hand)
	if absf(stick.x) > 0.7 and not _turned:
		_yaw -= signf(stick.x) * deg_to_rad(SNAP_TURN_DEGREES)
		_turned = true
	elif absf(stick.x) < 0.3 and absf(stick.y) < 0.3:
		_turned = false
	var basis := Basis(Vector3.UP, _yaw)
	var at: Vector3 = main.avatar.global_position
	var head_offset := basis * Vector3(head.position.x, 0.0, head.position.z)
	origin.global_transform = Transform3D(basis, Vector3(at.x, 0.0, at.z) - head_offset)
	main.rig.vr_focus = Vector2.INF


# --- tabletop ---------------------------------------------------------------------------------

## The play space on the map: `_scale` tiles per metre, turned by `_yaw`, at `_at`, lowered so
## the ground is `_height` metres above the floor.
func _tabletop(delta: float) -> void:
	if _recentre_in > 0.0:
		_recentre_in -= delta
		if _recentre_in <= 0.0:
			_recentre()
	_grab_update()
	if _grab.is_empty():
		var stick := _stick(pointer_hand)
		var r := _ray()
		var on_panel: bool = panel.hit(r[0], r[1]) != null
		if absf(stick.x) > 0.7 and not _turned and not on_panel:
			_turn_about_centre(-signf(stick.x) * deg_to_rad(TABLE_TURN_DEGREES))
			_turned = true
		elif absf(stick.x) < 0.3 and absf(stick.y) < 0.3:
			_turned = false
		if absf(stick.y) > STICK_DEAD_ZONE and not on_panel:
			_zoom_about_centre(exp(-stick.y * ZOOM_SPEED * delta))
	if _follow:
		var at: Vector3 = main.avatar.global_position
		_place_centre(Vector2(at.x, at.z))
	_apply_origin()
	var c := _centre_world()
	main.rig.vr_focus = Vector2(c.x, c.z)


func _apply_origin() -> void:
	origin.world_scale = _scale
	origin.global_transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(_at.x, -_height * _scale, _at.y))


## The map point under a play-space point (metres), on the ground.
func _world_of(p: Vector3) -> Vector3:
	var w := Basis(Vector3.UP, _yaw) * (p * _scale)
	return Vector3(_at.x + w.x, 0.0, _at.y + w.z)


func _table_centre() -> Vector3:
	return Vector3(0.0, _height, -TABLE_FORWARD)


func _centre_world() -> Vector3:
	return _world_of(_table_centre())


## Moves the play space so the table's centre shows `ground` (map tiles).
func _place_centre(ground: Vector2) -> void:
	var w := Basis(Vector3.UP, _yaw) * (_table_centre() * _scale)
	_at = Vector2(ground.x - w.x, ground.y - w.z)


func _zoom_about_centre(factor: float) -> void:
	var c := _centre_world()
	_scale = clampf(_scale * factor, MIN_SCALE, MAX_SCALE)
	_place_centre(Vector2(c.x, c.z))


func _turn_about_centre(angle: float) -> void:
	var c := _centre_world()
	_yaw += angle
	_place_centre(Vector2(c.x, c.z))


## The table back on the character, a comfortable height below your eyes, zoomed as it was.
func _recentre() -> void:
	_follow = true
	if head.position.y > 0.3 * origin.world_scale:
		_height = clampf(head.position.y / origin.world_scale - 0.55, 0.45, 1.5)


## Grips: one hand drags the map; two hands drag, zoom and turn it about their midpoint (the map
## point that was between the hands stays between them).
func _grab_update() -> void:
	var holding: Array = []
	for c in [pointer_hand, other_hand]:
		if _pressed(c, "grip_click"):
			holding.append(c)
	grab_step(holding)


## One frame of grabbing with these controllers (tests/vr_test.gd drives it without a headset).
func grab_step(holding: Array) -> void:
	if holding.is_empty():
		_grab = {}
		return
	if _grab.get("hands", []) != holding:
		# Started, or a hand joined or let go: carry on from here.
		_grab = {"hands": holding, "world": _world_of(_mid(holding)), "scale": _scale, "yaw": _yaw,
			"span": _span(holding), "angle": _angle(holding)}
		_follow = false
		if running:
			for c in holding:
				(c as XRController3D).trigger_haptic_pulse("haptic", 0.0, 0.3, 0.05, 0.0)
		return
	if holding.size() == 2:
		var span := _span(holding)
		if span > 0.02 and float(_grab["span"]) > 0.02:
			_scale = clampf(float(_grab["scale"]) * float(_grab["span"]) / span, MIN_SCALE, MAX_SCALE)
		_yaw = float(_grab["yaw"]) - (_angle(holding) - float(_grab["angle"]))
	# Keep the grabbed map point under the hands' midpoint.
	var w := Basis(Vector3.UP, _yaw) * (_mid(holding) * _scale)
	var target: Vector3 = _grab["world"]
	_at = Vector2(target.x - w.x, target.z - w.z)


func _mid(hands: Array) -> Vector3:
	var sum := Vector3.ZERO
	for c in hands:
		sum += _metres(c)
	return sum / hands.size()


func _span(hands: Array) -> float:
	if hands.size() < 2:
		return 0.0
	var a := _metres(hands[0])
	var b := _metres(hands[1])
	return Vector2(a.x - b.x, a.z - b.z).length()


func _angle(hands: Array) -> float:
	if hands.size() < 2:
		return 0.0
	var d := _metres(hands[1]) - _metres(hands[0])
	return atan2(d.x, d.z)


## A controller's position in the play space, in metres (its node position is scaled).
func _metres(c: XRController3D) -> Vector3:
	return c.position / maxf(origin.world_scale, 1e-4)


# --- both modes -------------------------------------------------------------------------------

## The other hand's stick walks the character (player_input.gd reads the move actions, turned
## by the head's direction through rig.vr_view).
func _walk() -> void:
	var stick := _stick(other_hand)
	if stick.length() < STICK_DEAD_ZONE:
		_release_walk()
		return
	_set_action("move_right", maxf(stick.x, 0.0))
	_set_action("move_left", maxf(-stick.x, 0.0))
	_set_action("move_up", maxf(stick.y, 0.0))
	_set_action("move_down", maxf(-stick.y, 0.0))


func _release_walk() -> void:
	for action in ["move_right", "move_left", "move_up", "move_down"]:
		_set_action(action, 0.0)


func _set_action(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


## [from, direction] of the laser, in world space.
func _ray() -> Array:
	return [pointer_hand.global_position, -pointer_hand.global_basis.z.normalized()]


## The laser: on the panel it is the UI's mouse; elsewhere it is where the camera's mouse ray
## would be (rig.vr_pointer), so hovering, building and mining work as with the mouse.
func _pointer() -> void:
	var r := _ray()
	var from: Vector3 = r[0]
	var dir: Vector3 = r[1]
	var on_panel = panel.hit(from, dir)
	var length := LASER_LENGTH
	if on_panel != null:
		panel.point(on_panel)
		length = panel.distance_to(from, on_panel)
		main.rig.vr_pointer = [from, Vector3.UP]  # nothing on the ground under a window
		# The stick scrolls lists on the panel.
		var stick := _stick(pointer_hand)
		if absf(stick.y) > 0.6 and not _turned:
			panel.wheel(stick.y > 0.0, on_panel)
			_turned = true
	else:
		panel.leave()
		main.rig.vr_pointer = [from, dir]
		var ground = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
		if ground != null:
			length = from.distance_to(ground)
	# A cylinder along the controller's -z, as long as the ray, a few millimetres thick at any zoom.
	var w := origin.world_scale
	_laser.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)) * Basis.from_scale(Vector3(w, length, w)), Vector3(0.0, 0.0, -length * 0.5))


func _buttons() -> void:
	var r := _ray()
	var on_panel = panel.hit(r[0], r[1])
	_set_shift(_pressed(other_hand, "trigger_click"))
	_mouse(pointer_hand, "trigger_click", MOUSE_BUTTON_LEFT, on_panel)
	_mouse(pointer_hand, "ax_button", MOUSE_BUTTON_RIGHT, on_panel)
	if _edge(pointer_hand, "by_button"):
		_action("rotate")
	if _edge(pointer_hand, "primary_click"):
		_action("pipette")
	if _edge(other_hand, "ax_button"):
		_action("open_screen")
	if _edge(other_hand, "by_button"):
		_toggle_panel()
	if _edge(other_hand, "menu_button"):
		_key(KEY_ESCAPE)
	if _edge(other_hand, "primary_click") and mode == Mode.TABLETOP:
		_recentre()


## Shows the HUD panel in front of you (where you look, a little below eye level), or hides it
## when it is already there.
func _toggle_panel() -> void:
	if panel.visible and _panel_in_view():
		panel.visible = false
		return
	panel.visible = true
	var s := maxf(origin.world_scale, 1e-4)
	var eye := head.position / s
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var at := eye + forward * PANEL_DISTANCE + Vector3(0.0, -0.2, 0.0)
	# The quad's front (+z) towards you, tipped back a little like a lectern.
	var facing := Basis.looking_at(-forward, Vector3.UP)
	_panel_pose = Transform3D(facing * Basis(Vector3.RIGHT, deg_to_rad(-10.0)), at)


func _panel_in_view() -> bool:
	var to_panel := (panel.global_position - head.global_position).normalized()
	return to_panel.dot(-head.global_basis.z) > 0.6


func _mouse(c: XRController3D, button: String, index: MouseButton, on_panel) -> void:
	var now := _pressed(c, button)
	var key := c.name + button
	if now == bool(_held.get(key, false)):
		return
	_held[key] = now
	if now:
		c.trigger_haptic_pulse("haptic", 0.0, 0.2, 0.03, 0.0)
	if on_panel != null:
		panel.button(index, now, on_panel)
		return
	# Into the main window, where player_input.gd takes it: hovering and the ground come from
	# rig.vr_pointer, not the event's position.
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = now
	e.shift_pressed = _shift
	e.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(e)


## The other hand's trigger is Shift, for the clicks and keys that read it.
func _set_shift(on: bool) -> void:
	if on == _shift:
		return
	_shift = on
	var e := InputEventKey.new()
	e.keycode = KEY_SHIFT
	e.physical_keycode = KEY_SHIFT
	e.pressed = on
	Input.parse_input_event(e)


func _action(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)


func _stick(c: XRController3D) -> Vector2:
	return c.get_vector2("primary")


func _pressed(c: XRController3D, button: String) -> bool:
	return c.is_button_pressed(button)


func _edge(c: XRController3D, button: String) -> bool:
	var now := _pressed(c, button)
	var key := c.name + button
	var was := bool(_held.get(key, false))
	_held[key] = now
	return now and not was
