extends Node
## Factorio's "Toggle visibility of tall entities" in 3D: while it is on (Settings → Interface,
## [interface] hide_tall, or the shortcut bar's button), buildings and trees taller than 2 tiles
## (model_library.gd's TALL) fade out when they stand between the camera and the character or the
## point under the mouse. The work is in the model shader (factorio_material.gdshaderinc); this
## only sets its global uniforms each frame, so MultiMesh drawing stays as it is.

const Settings := preload("res://scripts/menu/settings.gd")

var rig: Node3D  # camera_rig.gd
var avatar: Node3D

var _was_on := false


func _process(_delta: float) -> void:
	var on := bool(Settings.get_value("interface", "hide_tall"))
	var cam := get_viewport().get_camera_3d()
	if on != _was_on:
		_was_on = on
		RenderingServer.global_shader_parameter_set("f3d_fade", 1.0 if on else 0.0)
	if not on or cam == null:
		return
	var eye := cam.global_position
	var target := avatar.global_position + Vector3(0, 1, 0) if avatar != null and is_instance_valid(avatar) else eye
	RenderingServer.global_shader_parameter_set("f3d_fade_eye", eye)
	RenderingServer.global_shader_parameter_set("f3d_fade_target", target)
	RenderingServer.global_shader_parameter_set("f3d_fade_cursor", ground_under_mouse(cam, target))


## Where the mouse points on the ground (height 0), or `fallback` when it points at the sky.
static func ground_under_mouse(cam: Camera3D, fallback: Vector3) -> Vector3:
	var mouse := cam.get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	if dir.y > -0.001:
		return fallback
	return from + dir * (-from.y / dir.y)
