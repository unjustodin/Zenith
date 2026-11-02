extends Node3D
## Entity ghosts and planner marks, drawn like Factorio's: a ghost (a record with `extra.gh`, the
## prototype it stands for) is that entity's model, or placeholder box, in a translucent
## blue-white; an entity marked for deconstruction (`extra.d`) gets Factorio's red cross over
## it, one marked for upgrade (`extra.up`) the green upgrade arrow. Per chunk, rebuilt when the
## world redraws the chunk (chunk_view.gd leaves ghosts out).

const WorldMirror := preload("res://scripts/world/world.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const FluidsPower := preload("res://scripts/world/fluids_power.gd")
const GhostShader := preload("res://shaders/ghost.gdshader")
const IconShader := preload("res://shaders/billboard_icon.gdshader")

const MARK_SIZE := 0.9
const REBUILDS_PER_FRAME := 4

var world: WorldMirror

var _nodes := {}  # Vector2i chunk -> Node3D holding that chunk's ghosts and marks
var _dirty := {}
var _ghost_material: ShaderMaterial
var _mark_materials := {}  # "d" / "up" -> ShaderMaterial
var _quad := QuadMesh.new()
var _ghosts := 0


func _ready() -> void:
	_ghost_material = ShaderMaterial.new()
	_ghost_material.shader = GhostShader
	var marks := {
		"d": ["core/graphics/cancel.png", Color(0.85, 0.1, 0.1)],
		"up": ["core/graphics/icons/upgrade-symbol.png", Color(0.2, 0.75, 0.2)],
	}
	for key in marks:
		var m := ShaderMaterial.new()
		m.shader = IconShader
		var texture := FluidsPower.core_texture(marks[key][0])
		m.set_shader_parameter("icon", texture if texture != null else FluidsPower._fallback_texture(marks[key][1]))
		_mark_materials[key] = m
	_quad.size = Vector2.ONE
	if world != null:
		world.entities_changed.connect(_on_entities_changed)


func reset() -> void:
	for n in _nodes.values():
		n.queue_free()
	_nodes.clear()
	_dirty.clear()
	_ghosts = 0


func ghost_count() -> int:
	return _ghosts


func _on_entities_changed(c: Vector2i) -> void:
	_dirty[c] = true


func _process(_delta: float) -> void:
	if world == null or _dirty.is_empty():
		return
	var budget := REBUILDS_PER_FRAME
	for c in _dirty.keys():
		if budget <= 0:
			break
		_dirty.erase(c)
		_rebuild(c)
		budget -= 1


func _rebuild(c: Vector2i) -> void:
	var old: Node3D = _nodes.get(c)
	if old != null:
		_ghosts -= int(old.get_meta("ghosts", 0))
		old.queue_free()
		_nodes.erase(c)
	var cv = world.chunks.get(c)
	if cv == null:
		return
	var by_model := {}  # Mesh -> Array of Transform3D
	var boxes: Array = []
	var marks := {"d": [], "up": []}
	var ghosts := 0
	var tiles: Array = []
	for rec: WorldMirror.Rec in cv.entities.values():
		if rec.extra.has("tg"):
			# A tile ghost: a flat translucent square on its tile, like Factorio's blue tile ghosts.
			tiles.append(Transform3D(Basis.from_scale(Vector3(0.96, 0.02, 0.96)), Vector3(floorf(rec.pos.x) + 0.5, 0.04, floorf(rec.pos.y) + 0.5)))
			ghosts += 1
			continue
		var shown: ProtoDB.EntityProto = world.protos.entity(rec.proto_id)
		if rec.extra.has("gh"):
			shown = world.protos.entity(int(rec.extra["gh"]))
			if shown == null:
				continue
			ghosts += 1
			if not ModelLibrary.entity_ready(shown.name, shown.type, rec.extra, rec.dir):
				cv.waiting_models = true  # drawn again with the chunk once the model is made
				continue
			var mesh := ModelLibrary.mesh_for_entity(shown.name, shown.type, rec.extra, rec.dir)
			if mesh != null:
				if not by_model.has(mesh):
					by_model[mesh] = []
				(by_model[mesh] as Array).append(ModelLibrary.placed(shown.name, shown.type, rec.dir, rec.extra, Vector3(rec.pos.x, 0.0, rec.pos.y)))
				if shown.type == "cargo-bay" and not _add_cargo_pieces(shown, rec, by_model):
					cv.waiting_models = true
			else:
				boxes.append(Visuals.placeholder_transform(shown, rec.pos, rec.dir, Visuals.height_for(shown)))
		if shown == null:
			continue
		for key in marks:
			if rec.extra.has(key):
				var top := _top(shown, rec)
				# Over the middle of the entity as seen from the camera, like Factorio's marks.
				var at := Vector3(rec.pos.x, top * 0.6 + 0.2, rec.pos.y)
				(marks[key] as Array).append(Transform3D(Basis.from_scale(Vector3.ONE * MARK_SIZE), at))
	if ghosts == 0 and (marks["d"] as Array).is_empty() and (marks["up"] as Array).is_empty():
		return
	var node := Node3D.new()
	node.set_meta("ghosts", ghosts)
	add_child(node)
	_nodes[c] = node
	_ghosts += ghosts
	for mesh in by_model:
		_add(node, mesh, by_model[mesh], _ghost_material)
	_add(node, Visuals.box_mesh(), boxes, _ghost_material)
	_add(node, Visuals.box_mesh(), tiles, _ghost_material)
	for key in marks:
		_add(node, _quad, marks[key], _mark_materials[key])


## A ghost bay's edge pieces, framed as it will be once built (world.cargo_mask): without them it
## would show only its machine, about 3 by 2 of its 4 by 4 tiles. False while a piece is being made.
func _add_cargo_pieces(proto: ProtoDB.EntityProto, rec: WorldMirror.Rec, by_model: Dictionary) -> bool:
	var cb := world.cargo_mask(WorldMirror.cargo_rect(proto, rec.pos), true)
	var ready := true
	for place in ModelLibrary.cargo_places(cb, Vector3(rec.pos.x, 0.0, rec.pos.y)):
		if not ModelLibrary.ready(place[0]):
			ready = false
			continue
		var mesh := ModelLibrary.mesh_for(place[0])
		if mesh != null:
			if not by_model.has(mesh):
				by_model[mesh] = []
			(by_model[mesh] as Array).append(Transform3D(Basis(), place[1]))
	return ready


func _top(proto: ProtoDB.EntityProto, rec: WorldMirror.Rec) -> float:
	var mesh := world.ready_mesh(proto, rec)
	if mesh != null:
		return mesh.get_aabb().end.y
	return Visuals.height_for(proto)


static func _add(parent: Node3D, mesh: Mesh, xforms: Array, material: Material) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
