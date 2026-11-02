extends Node3D
## The VR pieces that don't need a headset: the HUD panel (scripts/vr/vr_panel.gd) takes a
## CanvasLayer, a ray hits it where expected and clicks reach its buttons; keys are passed on to
## it; and without OpenXR the session (vr_session.gd) stays off. Exits 1 if a check fails; CI
## also fails on any SCRIPT ERROR in the output.
##
##   godot --headless --path client res://tests/vr_test.tscn

const VrPanel := preload("res://scripts/vr/vr_panel.gd")
const VrSession := preload("res://scripts/vr/vr_session.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", what)


## The tabletop's grab, zoom and turn, with controllers placed by hand (no headset): the map
## point held stays in the hand.
func _check_tabletop(session: Node3D) -> void:
	var origin: XROrigin3D = session.origin
	session.add_child(origin)
	var a := XRController3D.new()
	var b := XRController3D.new()
	origin.add_child(a)
	origin.add_child(b)
	session._scale = 16.0
	session._yaw = 0.0
	session._at = Vector2(100.0, 50.0)
	session._height = 0.85
	session._apply_origin()
	var put := func(c: XRController3D, metres: Vector3) -> void:
		c.position = metres * origin.world_scale

	# One hand drags: the map point first under the hand stays under it.
	put.call(a, Vector3(0.1, 0.9, -0.5))
	session.grab_step([a])
	var held: Vector3 = session._world_of(Vector3(0.1, 0.9, -0.5))
	put.call(a, Vector3(0.3, 0.9, -0.4))
	session.grab_step([a])
	session._apply_origin()
	var now: Vector3 = session._world_of(Vector3(0.3, 0.9, -0.4))
	check(now.distance_to(held) < 0.01, "one grip drags the map with the hand: %s vs %s" % [now, held])
	check(not session._follow, "and the table stops following the character")
	session.grab_step([])
	check(session._grab.is_empty(), "letting go ends the grab")

	# Two hands pulled apart: twice the size (half the tiles per metre), the point between them stays.
	put.call(a, Vector3(-0.2, 0.9, -0.5))
	put.call(b, Vector3(0.2, 0.9, -0.5))
	session.grab_step([a, b])
	var mid: Vector3 = session._world_of(Vector3(0.0, 0.9, -0.5))
	var scale_before: float = session._scale
	put.call(a, Vector3(-0.4, 0.9, -0.5))
	put.call(b, Vector3(0.4, 0.9, -0.5))
	session.grab_step([a, b])
	session._apply_origin()
	check(absf(session._scale - scale_before * 0.5) < 0.01, "hands apart zoom in: %.2f -> %.2f" % [scale_before, session._scale])
	check(session._world_of(Vector3(0.0, 0.9, -0.5)).distance_to(mid) < 0.01, "the point between the hands stays there")

	# Two hands turned a quarter round the same midpoint: the map turns with them.
	put.call(a, Vector3(0.0, 0.9, -0.9))
	put.call(b, Vector3(0.0, 0.9, -0.1))
	session.grab_step([a, b])
	session._apply_origin()
	check(absf(wrapf(session._yaw - PI / 2.0, -PI, PI)) < 0.01, "hands turned a quarter turn the map a quarter: %.3f" % session._yaw)
	check(session._world_of(Vector3(0.0, 0.9, -0.5)).distance_to(mid) < 0.05, "still about the same point")
	session.grab_step([])

	# The stick zooms and turns about the table's centre.
	var centre: Vector3 = session._centre_world()
	session._zoom_about_centre(2.0)
	check(session._centre_world().distance_to(centre) < 0.01, "zooming keeps the table's centre")
	session._turn_about_centre(deg_to_rad(45.0))
	check(session._centre_world().distance_to(centre) < 0.01, "turning keeps the table's centre")
	# The ground is at the table's height: a play-space point at that height maps to y 0.
	session._apply_origin()
	var ground := origin.global_transform * (Vector3(0.0, session._height, -0.5) * origin.world_scale)
	check(absf(ground.y) < 0.01, "the map's ground is at the table's height: %.3f" % ground.y)


func _ready() -> void:
	var session: Node3D = VrSession.new()
	add_child(session)
	check(not session.running, "without OpenXR the session stays off")

	var panel: Node3D = VrPanel.new()
	add_child(panel)
	panel.position = Vector3(0.0, 1.0, -2.0)
	var hud := CanvasLayer.new()
	var button := Button.new()
	button.position = Vector2(700, 400)
	button.size = Vector2(200, 200)
	hud.add_child(button)
	var clicks := [0]
	button.pressed.connect(func() -> void: clicks[0] += 1)
	var keys := [0]
	var catcher := Control.new()
	catcher.set_script(preload("res://tests/vr_test_keys.gd"))
	catcher.counter = keys
	hud.add_child(catcher)
	add_child(hud)
	panel.adopt(hud)
	check(hud.get_parent() == panel.viewport, "the HUD moves into the panel's viewport")
	await get_tree().process_frame

	# Straight at the panel's centre: the middle of its pixels.
	var at = panel.hit(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0))
	check(at != null and (at as Vector2).distance_to(Vector2(800, 500)) < 1.0, "a ray at the centre hits the middle: %s" % str(at))
	check(panel.hit(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0)) == null, "a ray pointing away misses")
	check(panel.hit(Vector3(5.0, 1.0, 0.0), Vector3(0.0, 0.0, -1.0)) == null, "a ray beside the panel misses")
	var corner = panel.hit(Vector3(-0.6 + 0.06, 1.0 + 0.375 - 0.0375, 0.0), Vector3(0.0, 0.0, -1.0))
	check(corner != null and (corner as Vector2).distance_to(Vector2(80, 50)) < 1.0, "top left is pixel (0, 0): %s" % str(corner))
	check(absf(panel.distance_to(Vector3(0.0, 1.0, 0.0), Vector2(800, 500)) - 2.0) < 0.01, "distance to the panel")

	panel.button(MOUSE_BUTTON_LEFT, true, Vector2(800, 500))
	panel.button(MOUSE_BUTTON_LEFT, false, Vector2(800, 500))
	await get_tree().process_frame
	check(clicks[0] == 1, "a click on the panel presses the button under it (%d)" % clicks[0])
	panel.leave()

	var key := InputEventKey.new()
	key.keycode = KEY_E
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	check(keys[0] == 1, "a key pressed in the window reaches the HUD in the panel (%d)" % keys[0])

	panel.release()
	await get_tree().process_frame
	check(not is_instance_valid(hud), "release frees the HUD with the game")

	_check_tabletop(session)
	print("vr test: %s" % ("all passed" if fails == 0 else "%d failed" % fails))
	get_tree().quit(1 if fails > 0 else 0)
