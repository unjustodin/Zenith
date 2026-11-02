extends Node3D
## The angled view: a camera close behind and above the character that follows it, rotates in 90°
## steps (or freely with the middle mouse button), tilts, and zooms with the wheel.
## Settings → Camera (settings.gd) picks the view a game starts in, the mouse look speed and
## whether it is inverted; --camera=... wins over the setting.

const MIN_DISTANCE := 6.0
## The furthest zoom by default; Settings > Camera > Furthest zoom changes it.
const MAX_DISTANCE := 140.0
const MAX_ZOOM_RANGE := Vector2(60.0, 400.0)
# Below 20° the far edge of the loaded chunks comes into view; above 85° yaw stops making sense.
const MIN_PITCH := 20.0
const MAX_PITCH := 85.0
## Factorio's own view: orthographic, north up, looking down at the angle its sprites were
## rendered at (fitted in tools/models/compare.py), at its default zoom of 32 px per tile.
const FACTORIO_PITCH := 48.0
const FACTORIO_PX_PER_TILE := 32.0
## Orthographic size per unit of distance (see _process).
const ORTHO_SCALE := 0.65
## First person: eye height of the 1.7-tile character, field of view, mouse look speed.
const EYE_HEIGHT := 1.55
const FIRST_PERSON_FOV := 75.0
const LOOK_DEGREES_PER_PIXEL := 0.15
const Settings := preload("res://scripts/menu/settings.gd")

## Seeing the world through the character's eyes (F5). The mouse is captured and looks around;
## building and mining aim at the middle of the screen (aim_position).
var first_person := false
## Mouse look speed (a multiple of LOOK_DEGREES_PER_PIXEL) and -1 when inverted (Settings).
var look_speed := 1.0
var look_sign := 1.0
var _look_yaw := 0.0
var _look_pitch := 10.0  # degrees below the horizon
var _crosshair: CanvasLayer

var target: Node3D
## 45° looks across the grid diagonally, like an isometric game; 0° is Factorio's north-up view.
var yaw_degrees := 45.0
var pitch_degrees := 50.0
var distance := 30.0
var orthographic := false
var camera := Camera3D.new()
## How far the wheel zooms out (Settings > Camera > Furthest zoom).
var max_distance := MAX_DISTANCE
## In the remote view (factorio_ui.gd sets it), the map's own projection applies instead of
## `orthographic` (Settings > Camera, one for the map and one for the normal view).
var in_remote := false
var remote_orthographic := true

## VR (scripts/vr/vr_session.gd): the headset's camera, which then decides which way is forward
## for walking, and the controller's laser as [origin, direction], which then stands in for the
## mouse's ray.
var vr_view: Node3D
var vr_pointer: Array = []
## VR tabletop: the ground point at the table's centre, where chunks load and live data is asked
## for (focus_point), even when the table shows somewhere away from the character.
var vr_focus := Vector2.INF

var _yaw_goal := 45.0
var _distance_goal := 30.0
## The view to go back to when Factorio's view is toggled off; empty when it isn't on.
var _saved_view := {}
## Factorio's view as last snapped to: [yaw, pitch, distance].
var _factorio_snap: Array = []
## A ride's camera (scripts/world/ride.gd): the view to go back to, empty when none is on, and the
## pitch it eases towards.
var _cine_saved := {}
var _cine_pitch := 50.0
## An add-on's camera (scripts/addons/addon_host.gd): while one has it, the camera stays where the
## add-on puts it (top level, in world space) and the rig itself stands at `taken_focus`, so
## focus_point() (where chunks load and live data is asked for) follows the add-on's shot. What
## the camera was before, to put back: empty while no add-on has it.
var _taken := {}
var taken_focus := Vector2.INF


func _ready() -> void:
	camera.fov = 35.0
	camera.near = 0.5
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()
	_configure_from_command_line()
	if target != null:
		global_position = target.global_position
	# --camera=factorio starts in Factorio's view (handy for screenshots).
	if "--camera=factorio" in OS.get_cmdline_user_args():
		toggle_factorio_view.call_deferred()
	# --camera=first-person starts in the character's eyes (for screenshots).
	if "--camera=first-person" in OS.get_cmdline_user_args():
		toggle_first_person.call_deferred()
	apply_settings()
	if not Settings.has_arg("--camera="):
		match str(Settings.get_value("camera", "default_view")):
			"factorio":
				toggle_factorio_view.call_deferred()
			"first_person":
				toggle_first_person.call_deferred()


## Mouse look speed and inversion, and the projection, from the settings (called again when they
## change). A `--camera=` view keeps its own projection; in Factorio's view the setting applies on
## leaving it.
func apply_settings() -> void:
	look_speed = clampf(float(Settings.get_value("camera", "look_sensitivity")), 0.05, 10.0)
	look_sign = -1.0 if bool(Settings.get_value("camera", "invert_y")) else 1.0
	max_distance = clampf(float(Settings.get_value("camera", "max_zoom")), MAX_ZOOM_RANGE.x, MAX_ZOOM_RANGE.y)
	_distance_goal = minf(_distance_goal, max_distance)
	remote_orthographic = bool(Settings.get_value("camera", "map_orthographic"))
	if Settings.has_arg("--camera="):
		return
	var ortho := bool(Settings.get_value("camera", "orthographic"))
	if not _saved_view.is_empty():
		_saved_view["ortho"] = ortho
	if not in_factorio_view():
		orthographic = ortho


func _process(delta: float) -> void:
	if not _taken.is_empty():
		if taken_focus != Vector2.INF:
			global_position = Vector3(taken_focus.x, 0.0, taken_focus.y)
		return
	if first_person:
		# Locked to the character: any lag would feel like a lurching head.
		if target != null:
			global_position = target.global_position
		var look := Basis(Vector3.UP, deg_to_rad(_look_yaw)) * Basis(Vector3.RIGHT, -deg_to_rad(_look_pitch))
		camera.transform = Transform3D(look, Vector3(0.0, EYE_HEIGHT, 0.0))
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		return
	if target != null:
		global_position = global_position.lerp(target.global_position, 1.0 - exp(-delta * 8.0))
	yaw_degrees = lerpf(yaw_degrees, _yaw_goal, 1.0 - exp(-delta * 10.0))
	# A ride's camera moves slowly, as a film's would.
	var rate := 1.6 if not _cine_saved.is_empty() else 10.0
	distance = lerpf(distance, _distance_goal, 1.0 - exp(-delta * rate))
	if not _cine_saved.is_empty():
		pitch_degrees = lerpf(pitch_degrees, _cine_pitch, 1.0 - exp(-delta * rate))
	var turn := Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * Basis(Vector3.RIGHT, -deg_to_rad(pitch_degrees))
	camera.transform = Transform3D(turn, turn * Vector3(0.0, 0.0, distance))
	if (remote_orthographic if in_remote else orthographic):
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = distance * ORTHO_SCALE
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE


## In Factorio's view (toggle_factorio_view) as it was snapped to, with the view before it to go
## back to. Turned, tilted or zoomed since, it isn't any more (the view before is still kept).
func in_factorio_view() -> bool:
	return not _saved_view.is_empty() and not first_person and orthographic and _factorio_snap == [_yaw_goal, pitch_degrees, _distance_goal]


## Jumps straight to Factorio's view centred on the character, or back to the view before it.
## F6 sometimes took several presses. Turning, tilting or zooming in Factorio's view
## (a nudge of the middle mouse, the wheel) left it marked as on, so the next press went back to
## the view before instead of snapping, and in first person the snap didn't show at all. Now a
## press snaps whenever the view isn't exactly Factorio's, and goes back only from it.
func toggle_factorio_view() -> void:
	if in_factorio_view():
		leave_factorio_view()
		return
	if first_person:
		toggle_first_person()
	if _saved_view.is_empty():
		_saved_view = {"yaw": _yaw_goal, "pitch": pitch_degrees, "distance": _distance_goal, "ortho": orthographic}
	# Ground tiles in Factorio are FACTORIO_PX_PER_TILE apart on screen vertically too; through a
	# camera pitched down by FACTORIO_PITCH a tile spans sin(pitch) of its length.
	var tiles_high := get_viewport().get_visible_rect().size.y / FACTORIO_PX_PER_TILE
	var size := tiles_high * sin(deg_to_rad(FACTORIO_PITCH))
	_snap(360.0 * roundf(_yaw_goal / 360.0), FACTORIO_PITCH, size / ORTHO_SCALE, true)
	_factorio_snap = [_yaw_goal, pitch_degrees, _distance_goal]
	if target != null:
		global_position = target.global_position


## Back to the view before Factorio's, if Factorio's (as snapped to, or changed since) is on.
func leave_factorio_view() -> void:
	if not _saved_view.is_empty():
		_snap(_saved_view["yaw"], _saved_view["pitch"], _saved_view["distance"], _saved_view["ortho"])
		_saved_view = {}


func _snap(yaw: float, pitch: float, dist: float, ortho: bool) -> void:
	_yaw_goal = yaw
	yaw_degrees = yaw
	pitch_degrees = pitch
	_distance_goal = clampf(dist, MIN_DISTANCE, max_distance)
	distance = _distance_goal
	orthographic = ortho


## F7: flips the projection of the view in use, the map's remote view or the normal
## view, and keeps it as that view's setting. Factorio's view (F6) stays orthographic: there F7
## changes the normal view's, used on leaving it. Returns a line saying what it is now.
func toggle_projection() -> String:
	var key := "map_orthographic" if in_remote else "orthographic"
	var ortho := not bool(Settings.get_value("camera", key))
	Settings.set_value("camera", key, ortho)
	var kind := "orthographic" if ortho else "perspective"
	if in_remote:
		remote_orthographic = ortho
		return "Map view: " + kind
	if in_factorio_view():
		_saved_view["ortho"] = ortho
		return "Normal view: %s (Factorio's view stays orthographic)" % kind
	orthographic = ortho
	return "Normal view: " + kind


## `--camera=<yaw>,<pitch>,<distance>[,ortho]` starts with that view, for repeatable screenshots
## (`--camera=0,48,14,ortho` is close to Factorio's own view).
func _configure_from_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--camera=") or arg in ["--camera=factorio", "--camera=first-person"]:
			continue
		var parts := arg.get_slice("=", 1).split(",")
		if parts.size() >= 3:
			_yaw_goal = float(parts[0])
			yaw_degrees = _yaw_goal
			pitch_degrees = clampf(float(parts[1]), MIN_PITCH, MAX_PITCH)
			_distance_goal = clampf(float(parts[2]), MIN_DISTANCE, MAX_ZOOM_RANGE.y)
			distance = _distance_goal
		orthographic = parts.size() >= 4 and parts[3] == "ortho"


## Into the character's eyes, facing the way the camera faced, or back out to the view before.
## A ride's camera (ride.gd): eases to this pitch and distance, out of first person and Factorio's
## view, until cinematic_end() puts the view back.
func cinematic(pitch: float, dist: float) -> void:
	if _cine_saved.is_empty():
		_cine_saved = {"pitch": pitch_degrees, "distance": _distance_goal, "factorio": in_factorio_view(), "fp": first_person}
		if first_person:
			toggle_first_person()
		if in_factorio_view():
			toggle_factorio_view()
	_cine_pitch = pitch
	_distance_goal = clampf(dist, MIN_DISTANCE, max_distance)


func cinematic_end() -> void:
	if _cine_saved.is_empty():
		return
	var saved := _cine_saved
	_cine_saved = {}
	pitch_degrees = float(saved["pitch"])
	_distance_goal = float(saved["distance"])
	if bool(saved["factorio"]):
		toggle_factorio_view()
	if bool(saved["fp"]):
		toggle_first_person()


func in_cinematic() -> bool:
	return not _cine_saved.is_empty()


## An add-on takes the camera: from now on it moves it (`camera`, in world space) until
## hand_back(). The player's own view (first person, Factorio's view, zoom) is kept as it was.
func take_over() -> void:
	if not _taken.is_empty():
		return
	_taken = {"fov": camera.fov, "near": camera.near, "far": camera.far, "projection": camera.projection,
		"size": camera.size, "attributes": camera.attributes, "keep_aspect": camera.keep_aspect,
		"crosshair": _crosshair != null and _crosshair.visible}
	var at := camera.global_transform
	camera.top_level = true
	camera.global_transform = at
	if _crosshair != null:
		_crosshair.visible = false


## The camera back to the player's view exactly as it was, round the character again.
func hand_back() -> void:
	if _taken.is_empty():
		return
	var t := _taken
	_taken = {}
	taken_focus = Vector2.INF
	camera.top_level = false
	camera.fov = float(t["fov"])
	camera.near = float(t["near"])
	camera.far = float(t["far"])
	camera.projection = t["projection"]
	camera.size = float(t["size"])
	camera.attributes = t["attributes"]
	camera.keep_aspect = t["keep_aspect"]
	if bool(t["crosshair"]):
		_crosshair.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if first_person else Input.MOUSE_MODE_VISIBLE
	if target != null:
		global_position = target.global_position
	_process(0.0)  # the camera in its place now, not a frame late


func taken() -> bool:
	return not _taken.is_empty()


## Where the player's own view would put the camera now, round the character (an add-on glides
## there before handing the camera back).
func own_view() -> Transform3D:
	var at := target.global_position if target != null else global_position
	if first_person:
		var look := Basis(Vector3.UP, deg_to_rad(_look_yaw)) * Basis(Vector3.RIGHT, -deg_to_rad(_look_pitch))
		return Transform3D(look, at + Vector3(0.0, EYE_HEIGHT, 0.0))
	var turn := Basis(Vector3.UP, deg_to_rad(_yaw_goal)) * Basis(Vector3.RIGHT, -deg_to_rad(pitch_degrees))
	return Transform3D(turn, at + turn * Vector3(0.0, 0.0, _distance_goal))


func toggle_first_person() -> void:
	first_person = not first_person
	if first_person:
		_look_yaw = yaw_degrees
		_look_pitch = 10.0
		camera.fov = FIRST_PERSON_FOV
		camera.near = 0.05
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		camera.fov = 35.0
		camera.near = 0.5
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_crosshair(first_person)
	if target != null and target.has_method("set_first_person"):
		target.set_first_person(first_person)


## Mouse look in first person, from a mouse motion in pixels.
func look(relative: Vector2) -> void:
	_look_yaw -= relative.x * LOOK_DEGREES_PER_PIXEL * look_speed
	_look_pitch = clampf(_look_pitch + relative.y * LOOK_DEGREES_PER_PIXEL * look_speed * look_sign, -85.0, 85.0)


## Where the player aims on screen: the cursor, or the crosshair in first person.
func aim_position() -> Vector2:
	if first_person:
		return get_viewport().get_visible_rect().size * 0.5
	return get_viewport().get_mouse_position()


## Windows (inventory, machine screens) need the cursor; first person gives it back while one is
## open and takes it again when they close.
func set_cursor_needed(needed: bool) -> void:
	if first_person:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if needed else Input.MOUSE_MODE_CAPTURED


func _show_crosshair(show: bool) -> void:
	if _crosshair == null:
		_crosshair = CanvasLayer.new()
		var root := CenterContainer.new()
		root.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(4, 4)
		dot.color = Color(1, 1, 1, 0.85)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(dot)
		_crosshair.add_child(root)
		add_child(_crosshair)
	_crosshair.visible = show


func rotate_step(steps: int) -> void:
	_yaw_goal += 90.0 * steps


func rotate_free(degrees: float) -> void:
	_yaw_goal += degrees
	yaw_degrees += degrees


func tilt(degrees: float) -> void:
	pitch_degrees = clampf(pitch_degrees + degrees, MIN_PITCH, MAX_PITCH)


func zoom(factor: float) -> void:
	_distance_goal = clampf(_distance_goal * factor, MIN_DISTANCE, max_distance)


## Where the camera looks, on the ground (tiles).
func focus_point() -> Vector2:
	if vr_focus != Vector2.INF:
		return vr_focus
	return Vector2(global_position.x, global_position.z)


## Camera forward and right flattened onto the ground, for camera-relative movement.
func ground_forward() -> Vector3:
	var basis := (vr_view if vr_view != null else camera).global_transform.basis
	var f := -basis.z
	f.y = 0.0
	if f.length() < 0.01:  # looking straight down (an add-on's overhead shot): screen up is forward
		f = basis.y
		f.y = 0.0
	return f.normalized()


func ground_right() -> Vector3:
	var r := (vr_view if vr_view != null else camera).global_transform.basis.x
	r.y = 0.0
	return r.normalized()


## The point on the ground under a screen position, or null.
func ground_point(screen_pos: Vector2):
	var r := ray(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(r[0], r[1])


## [origin, direction] of the ray under a screen position: the mouse's, or the VR laser.
func ray(screen_pos: Vector2) -> Array:
	if vr_pointer.size() == 2:
		return vr_pointer
	return [camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos)]
