extends Node3D
## The flat UI in VR: the HUD (Factorio's windows, quickbar, minimap: scripts/ui/hud.gd) moved
## into a SubViewport and shown on a panel floating beside the player. The right controller's
## laser is the mouse on it (hit + pointer events, pushed into the SubViewport); keys and input
## actions from the desktop keyboard are passed on to it too, as the HUD no longer sits in the
## window that receives them.

## Pixels of the UI, and the panel's size in metres (it is scaled with the world in tabletop mode).
const PIXELS := Vector2i(1600, 1000)
const METRES := Vector2(1.2, 0.75)

var viewport := SubViewport.new()
var hud: CanvasLayer

var _quad := MeshInstance3D.new()
var _pointer := Vector2(-1, -1)  # last position pushed, in viewport pixels
var _buttons := {}  # MouseButton -> held


func _ready() -> void:
	viewport.size = PIXELS
	viewport.transparent_bg = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var mesh := QuadMesh.new()
	mesh.size = METRES
	_quad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = viewport.get_texture()
	material.no_depth_test = false
	_quad.material_override = material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)


## Takes the HUD out of the main window into the panel (once per game).
func adopt(new_hud: CanvasLayer) -> void:
	if hud == new_hud:
		return
	hud = new_hud
	hud.reparent(viewport, false)


## Gives the HUD back to `parent` (leaving VR) or frees it with the game.
func release() -> void:
	if hud != null and is_instance_valid(hud) and hud.get_parent() == viewport:
		hud.queue_free()
	hud = null


## Where a ray from `from` along `dir` (world) meets the panel, in viewport pixels, or null.
func hit(from: Vector3, dir: Vector3):
	if not visible:
		return null
	var inv := _quad.global_transform.affine_inverse()
	var o := inv * from
	var d := inv.basis * dir
	if absf(d.z) < 1e-6:
		return null
	var t := -o.z / d.z
	if t <= 0.0:
		return null
	var p := o + d * t
	var uv := Vector2(p.x / METRES.x + 0.5, 0.5 - p.y / METRES.y)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return null
	return uv * Vector2(PIXELS)


## The distance from `from` to where the ray meets the panel (for drawing the laser).
func distance_to(from: Vector3, at_pixels: Vector2) -> float:
	var uv := at_pixels / Vector2(PIXELS)
	var local := Vector3((uv.x - 0.5) * METRES.x, (0.5 - uv.y) * METRES.y, 0.0)
	return from.distance_to(_quad.global_transform * local)


## The pointer moved to `at` (pixels) on the panel.
func point(at: Vector2) -> void:
	if at.is_equal_approx(_pointer):
		return
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - _pointer if _pointer.x >= 0.0 else Vector2.ZERO
	e.button_mask = _mask()
	_pointer = at
	viewport.push_input(e)


## A mouse button pressed or released at `at` (pixels) on the panel.
func button(index: MouseButton, pressed: bool, at: Vector2) -> void:
	point(at)
	_buttons[index] = pressed
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = at
	e.global_position = at
	e.button_mask = _mask()
	viewport.push_input(e)


func wheel(up: bool, at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = pressed
		e.position = at
		e.global_position = at
		viewport.push_input(e)


## The pointer left the panel: no control is hovered any more.
func leave() -> void:
	if _pointer.x < 0.0:
		return
	point(Vector2(-10, -10))
	_pointer = Vector2(-1, -1)


func _input(event: InputEvent) -> void:
	# The desktop keyboard (and actions sent as events) still drive the HUD's keys: E, T, M, Esc...
	if hud != null and (event is InputEventKey or event is InputEventAction):
		viewport.push_input(event)


func _mask() -> int:
	var m := 0
	for b in _buttons:
		if _buttons[b]:
			m |= 1 << (int(b) - 1)
	return m
