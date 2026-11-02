extends Node3D
## Wires between electric poles (and circuit wires between anything), drawn like Factorio's:
## thin copper lines sagging between the poles' insulators, red and green circuit wires beside
## them. Entity records list the unit numbers at the other ends in `extra.w` (copper), `r` and
## `g`; a wire may be listed by one end only. Each chunk gets one mesh holding the wires that
## start in it, rebuilt when the world redraws that chunk or a neighbour (the other end may be
## next door).

const WorldMirror := preload("res://scripts/world/world.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")

const KINDS := ["w", "r", "g"]
## Factorio's wire sprites: copper is a warm orange-brown, circuit wires plain red and green.
const COLORS := {"w": Color(0.72, 0.4, 0.12), "r": Color(0.78, 0.1, 0.06), "g": Color(0.12, 0.62, 0.12)}
const RADIUS := {"w": 0.022, "r": 0.016, "g": 0.016}
const SEGMENTS := 12
## The middle of a span hangs this much of its length below the straight line (a 7.5-tile span
## of small poles sags about 0.35 tiles, as in Factorio).
const SAG_PER_TILE := 0.045
const REBUILDS_PER_FRAME := 4
const REBUILD_USEC := 1500

## Where wires attach, in tiles from the pole's position (x east, y up, z south), for poles
## facing north: Factorio's `connection_points[1].wire`, in pixels on the sprite, with heights
## turned from the sprite's foreshortened view into 3D (x sqrt 2, which puts the small pole's
## insulators on its model's crossarm).
const POLE_POINTS := {
	# The tops of the insulators on Wube's pole model (tools/models/wube_recipes.py).
	"small-electric-pole": {"w": Vector3(0.02, 3.98, -0.18), "r": Vector3(0.46, 3.98, -0.18), "g": Vector3(-0.38, 3.98, -0.18)},
	# The middles of the insulators on these models (tools/models/electric.py `wire_*`): Factorio's
	# points seen through the sprite's camera (48 degrees down, the sprite's anchor height),
	# height = anchor + up / cos 48 degrees, which is where the sprites draw the insulators.
	"medium-electric-pole": {"w": Vector3(0.234, 4.947, 0.0), "r": Vector3(0.672, 4.48, 0.0), "g": Vector3(-0.234, 4.62, 0.0)},
	"big-electric-pole": {"w": Vector3(0.0, 5.784, 0.0), "r": Vector3(0.906, 4.967, 0.0), "g": Vector3(-0.906, 4.967, 0.0)},
	"substation": {"w": Vector3(0.0, 4.316, 0.0), "r": Vector3(0.688, 4.083, 0.0), "g": Vector3(-0.656, 4.13, 0.0)},
}

var world: WorldMirror

var _meshes := {}  # Vector2i chunk -> MeshInstance3D
var _dirty := {}  # Vector2i -> true
var _material: StandardMaterial3D
var _spans := 0
## The remote view's fog (remote_fog.gd): wires starting in chunks no radar sees are hidden.
var fog: Node
var _fogged := false


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.55
	_material.metallic = 0.3
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # thin tubes: no need to get the winding right
	if world != null:
		world.entities_changed.connect(_on_entities_changed)


func reset() -> void:
	for mi in _meshes.values():
		mi.queue_free()
	_meshes.clear()
	_dirty.clear()
	_spans = 0


func span_count() -> int:
	return _spans


func _on_entities_changed(c: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_dirty[c + Vector2i(dx, dy)] = true


func _process(_delta: float) -> void:
	_apply_fog()
	if world == null or _dirty.is_empty():
		return
	var budget := REBUILDS_PER_FRAME
	var started := Time.get_ticks_usec()
	for c in _dirty.keys():
		# Also within REBUILD_USEC (at least one): each new chunk dirties its eight neighbours, and on
		# the owner's busy save a frame of rebuilds took 4-7 ms while walking.
		if budget <= 0 or (budget < REBUILDS_PER_FRAME and Time.get_ticks_usec() - started > REBUILD_USEC):
			break
		_dirty.erase(c)
		_rebuild(c)
		budget -= 1


## The wires listed by entities in chunk `c`. A wire listed by both ends belongs to the end with
## the lower unit number, so it is drawn once.
func _rebuild(c: Vector2i) -> void:
	var old: MeshInstance3D = _meshes.get(c)
	if old != null:
		_spans -= int(old.get_meta("spans", 0))
		old.queue_free()
		_meshes.erase(c)
	var cv = world.chunks.get(c)
	if cv == null:
		return
	var tube := Tube.new()
	var spans := 0
	for rec: WorldMirror.Rec in cv.entities.values():
		if rec.unit == 0 or rec.extra.is_empty() or rec.extra.has("gh"):
			continue
		for kind: String in KINDS:
			for other_unit in _array(rec.extra.get(kind)):
				var other: WorldMirror.Rec = world.entities.get(int(other_unit))
				if other == null or other.extra.has("gh"):
					continue
				if other.unit < rec.unit and _lists(other, kind, rec.unit):
					continue
				_add_span(tube, attach_point(rec, kind), attach_point(other, kind), kind)
				spans += 1
	if spans == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = tube.mesh(_material)
	mi.set_meta("spans", spans)
	add_child(mi)
	_meshes[c] = mi
	_spans += spans


## Where a wire of `kind` meets the entity: the pole's insulator, or for anything else with a
## circuit connection (chests, inserters, combinators...) a point near its top.
func attach_point(rec: WorldMirror.Rec, kind: String) -> Vector3:
	var proto: ProtoDB.EntityProto = world.protos.entity(rec.proto_id)
	var base := Vector3(rec.pos.x, 0.0, rec.pos.y)
	if proto == null:
		return base + Vector3(0.0, 1.0, 0.0)
	var mesh := world.ready_mesh(proto, rec)
	var top := mesh.get_aabb().end.y if mesh != null else Visuals.height_for(proto)
	var points: Dictionary = POLE_POINTS.get(proto.name, {})
	if not points.is_empty():
		var p: Vector3 = points[kind]
		if mesh == null:
			# A placeholder box is shorter than the real pole: keep the insulators on top of it.
			var highest: Vector3 = points["w"]
			p.y *= top / highest.y
		return base + p
	var side := {"w": 0.0, "r": 0.12, "g": -0.12}
	return base + Vector3(side[kind], top * 0.85, 0.0)


func _add_span(tube: Tube, a: Vector3, b: Vector3, kind: String) -> void:
	var sag := a.distance_to(b) * SAG_PER_TILE
	var points := PackedVector3Array()
	for s in SEGMENTS + 1:
		var t := float(s) / SEGMENTS
		# A parabola is close enough to a catenary at this little sag.
		points.append(a.lerp(b, t) - Vector3(0.0, sag * 4.0 * t * (1.0 - t), 0.0))
	tube.add_line(points, RADIUS[kind], COLORS[kind])


static func _lists(rec: WorldMirror.Rec, kind: String, unit: int) -> bool:
	for u in _array(rec.extra.get(kind)):
		if int(u) == unit:
			return true
	return false


static func _array(v) -> Array:
	return v if v is Array else []


## Thin three-sided tubes along polylines, in one surface with vertex colours.
class Tube:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add_line(points: PackedVector3Array, radius: float, color: Color) -> void:
		var start := verts.size()
		var n := points.size()
		for i in n:
			var along := (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
			var side := along.cross(Vector3.UP)
			if side.length_squared() < 0.0001:
				side = Vector3.RIGHT
			side = side.normalized()
			var up := side.cross(along).normalized()
			for k in 3:
				var angle := TAU * k / 3.0
				var out := side * cos(angle) + up * sin(angle)
				verts.append(points[i] + out * radius)
				normals.append(out)
				colors.append(color)
		for i in n - 1:
			for k in 3:
				var a := start + i * 3 + k
				var b := start + i * 3 + (k + 1) % 3
				var c := a + 3
				var d := b + 3
				indices.append_array([a, c, b, b, c, d])

	func mesh(material: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, material)
		return m


## Under the remote view's fog, a chunk's wires show only where it is seen; out of it, all of them.
func _apply_fog() -> void:
	var hiding: bool = fog != null and fog.hiding()
	if not hiding and not _fogged:
		return
	_fogged = hiding
	for c in _meshes:
		var mi: MeshInstance3D = _meshes[c]
		if is_instance_valid(mi):
			mi.visible = not hiding or fog.seen(Vector2(c) * 32.0 + Vector2(16, 16))
