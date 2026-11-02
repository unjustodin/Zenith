extends RefCounted
## api.camera: an add-on takes Zenith's camera, moves it as it likes, and hands it back; the
## player's own view (the angled view, Factorio's view, first person, the zoom) comes back exactly
## as it was. One add-on has the camera at a time. While it does:
##   - the world loads round where the camera looks (the ground under the middle of the screen),
##     or round the character, or round a point the add-on names (set_focus);
##   - with "input" (the default) the player's own controls are off (the character stops) and the
##     add-on's camera keys work (addon_keys.gd), even where they share a key with Zenith's;
##   - Zenith takes it back by itself when it needs it (a ride to a platform starts, the game ends,
##     the add-on is switched off): `lost` says so.

## Zenith took the camera back (not after release()).
signal lost

var _host
var _api
var _focus = null  # Vector2 tiles, or null: as take()'s "focus" says
var _focus_mode := "camera"
var _input := true
var _mouse := false


func _init(host, api) -> void:
	_host = host
	_api = api


## Takes the camera. Options: "input" (bool, default true: the player's controls are off and the
## add-on's camera keys on), "focus" ("camera", the default: the world loads round where the camera
## looks; "character": round the character). False when it can't now (no game, another add-on has
## it, a ride to a platform, VR).
func take(options := {}) -> bool:
	_input = bool(options.get("input", true))
	_focus_mode = str(options.get("focus", "camera"))
	_focus = null
	return _host.take_camera(_api, _input)


## Hands the camera back to the player's view.
func release() -> void:
	_mouse = false
	_host.release_camera(_api)


func has() -> bool:
	return _host.camera_holder() == _api


## Whether the player's controls are off while this add-on has the camera.
func has_input() -> bool:
	return has() and _input


## The camera itself while this add-on has it, else null: set its transform, fov, projection,
## size, near/far and attributes (depth of field) as needed. All of it is put back on release.
func node() -> Camera3D:
	return _host.rig().camera if has() and _host.rig() != null else null


## The camera's place and turn now (also while the player has it: where to start a shot from).
func transform() -> Transform3D:
	var rig = _host.rig()
	return rig.camera.global_transform if rig != null else Transform3D.IDENTITY


func fov() -> float:
	var rig = _host.rig()
	return rig.camera.fov if rig != null else 35.0


## Where the player's own view would have the camera now (round the character), and its field of
## view: glide there before release() and the hand-back is seamless.
func player_view() -> Transform3D:
	var rig = _host.rig()
	return rig.own_view() if rig != null else Transform3D.IDENTITY


func player_fov() -> float:
	var rig = _host.rig()
	if rig == null:
		return 35.0
	return rig.FIRST_PERSON_FOV if rig.first_person else 35.0


## Whether the player's view is orthographic (Factorio's view, or the setting): an add-on gliding
## back may want to end in the same projection.
func player_orthographic() -> bool:
	var rig = _host.rig()
	return rig != null and rig.orthographic and not rig.first_person


func set_transform(t: Transform3D) -> void:
	var cam := node()
	if cam != null:
		cam.global_transform = t.orthonormalized()


## Puts the camera at `eye` looking at `at`.
func look_from(eye: Vector3, at: Vector3) -> void:
	var cam := node()
	if cam == null or eye.is_equal_approx(at):
		return
	var dir := (at - eye).normalized()
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	cam.global_transform = Transform3D(Basis.looking_at(dir, up), eye)


## Where the world loads and live data is asked for while this add-on has the camera: a ground
## point (Vector2, tiles), or null for take()'s "focus" choice.
func set_focus(point) -> void:
	_focus = point if point is Vector2 else null


## The point the world loads round now (tiles).
func focus() -> Vector2:
	var rig = _host.rig()
	return rig.focus_point() if rig != null else Vector2.ZERO


## The mouse captured (hidden, its motion turns the view, as in first person) while this add-on has
## the camera; Zenith gives it back while a window or menu is open.
func capture_mouse(on: bool) -> void:
	_mouse = on


func mouse_captured() -> bool:
	return _mouse and has()


## The ground point (Vector3, y = 0) under a screen position, or null.
func ground_point(screen_pos: Vector2):
	var rig = _host.rig()
	if rig == null:
		return null
	var cam: Camera3D = rig.camera
	return Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))


## The ground point under the middle of the screen, or null when looking above the horizon.
func center_ground():
	var rig = _host.rig()
	if rig == null:
		return null
	return ground_point(rig.get_viewport().get_visible_rect().size * 0.5)


## Where the world should load round now (the host asks each frame while this add-on has it).
func _focus_point() -> Vector2:
	if _focus is Vector2:
		return _focus
	if _focus_mode == "character":
		var avatar = _host.game_node("avatar")
		if avatar is Node3D:
			return Vector2(avatar.global_position.x, avatar.global_position.z)
	var t := transform()
	var o := t.origin
	var d := -t.basis.z
	if d.y < -0.05:
		var reach := minf(-o.y / d.y, 400.0)
		var p := o + d * reach
		return Vector2(p.x, p.z)
	var flat := Vector2(d.x, d.z)
	return Vector2(o.x, o.z) + (flat.normalized() * 60.0 if flat.length() > 0.01 else Vector2.ZERO)


func _lost() -> void:
	_mouse = false
	lost.emit()
