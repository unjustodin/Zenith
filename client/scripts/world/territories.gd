extends MeshInstance3D
## Vulcanus' demolisher territories in the world: their borders as thin red strips on the ground,
## where Factorio draws them red. From ui_model.gd's territory_edges (`terr`): one
## mesh for all of them, rebuilt when they change.

const WIDTH := 0.18  # tiles
const HEIGHT := 0.06  # just over the ground
const COLOR := Color(0.9, 0.12, 0.08, 0.7)

var model  # ui_model.gd


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = COLOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m
	if model != null:
		model.territories_changed.connect(rebuild)
	rebuild()


func rebuild() -> void:
	var edges: PackedVector2Array = model.territory_edges if model != null else PackedVector2Array()
	if edges.is_empty():
		mesh = null
		return
	var verts := PackedVector3Array()
	for i in range(0, edges.size() - 1, 2):
		var a := edges[i]
		var b := edges[i + 1]
		var side := (b - a).normalized().orthogonal() * WIDTH * 0.5
		var p := [a - side, a + side, b + side, b - side]
		for k in [0, 1, 2, 0, 2, 3]:
			var v: Vector2 = p[k]
			verts.append(Vector3(v.x, HEIGHT, v.y))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = am
