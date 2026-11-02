extends Node3D
## Vulcanus' demolishers: a head, about forty segments and a tail, which Factorio moves as one
## segmented unit; the mod sends every segment's place and turn every two ticks (`seg`, ui_model.gd's
## demolishers). Each part is drawn with its model (vulcanus.py: head, segment, tail, lofted from
## Factorio's 128-direction sprites) at the scale its prototype name carries
## (`big-demolisher-segment-x1_52`, model_library.gd mover_model), and glides from where it was
## to where it is over the time between two messages, so the body follows the head along its path.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")

## Without a `seg` for this long (left Vulcanus, out of range) the demolishers are taken away.
const STALE := 2.0
## A part that jumps further than this (tiles) between two messages is placed, not glided.
const TELEPORT := 16.0
## Factorio draws the head over the first segment, which stands half a tile behind it and whose
## picture reaches further forward than the head's back: in 3D the segment would swallow the head.
## The head is drawn this far ahead along its heading (tiles at the big demolisher's scale).
const HEAD_LEAD := 2.2


class Part:
	var node: MeshInstance3D
	var proto := 0
	var model := ""
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var from_yaw := 0.0
	var to_yaw := 0.0


var model  # ui_model.gd
var protos: ProtoDB

var _units := {}  # unit -> Array[Part], head first
var _serial := -1
var _since := 0.0  # seconds since the latest `seg`
var _gap := 2.0 / 60.0  # seconds between two `seg`s, smoothed


func count() -> int:
	return _units.size()


## The drawn parts of a demolisher (for tests): [[model name, position, yaw], ...], head first.
func parts_of(unit: int) -> Array:
	var out := []
	for part: Part in _units.get(unit, []):
		out.append([part.model, part.node.position, part.node.rotation.y])
	return out


func _process(delta: float) -> void:
	_since += delta
	if model != null and int(model.demolishers_serial) != _serial:
		_serial = int(model.demolishers_serial)
		if _since > 0.0 and _since < 0.5:
			_gap = lerpf(_gap, _since, 0.2)
		_since = 0.0
		_update(model.demolishers)
	if _since > STALE and not _units.is_empty():
		_clear()
		return
	var t := clampf(_since / maxf(_gap, 0.001), 0.0, 1.0)
	for parts: Array in _units.values():
		for part: Part in parts:
			part.node.position = part.from.lerp(part.to, t)
			part.node.rotation.y = lerp_angle(part.from_yaw, part.to_yaw, t)


func _update(list: Dictionary) -> void:
	for unit in _units.keys():
		if not list.has(unit):
			for part: Part in _units[unit]:
				part.node.queue_free()
			_units.erase(unit)
	for unit in list:
		var segs: Array = list[unit].get("segments", [])
		var parts: Array = _units.get(unit, [])
		while parts.size() > segs.size():
			(parts.pop_back() as Part).node.queue_free()
		for i in segs.size():
			var seg: Dictionary = segs[i]
			var at := Vector3((seg["position"] as Vector2).x, 0.0, (seg["position"] as Vector2).y)
			var yaw := Visuals.orientation_yaw(float(seg["orientation"]))
			if i == 0:
				at += Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, -HEAD_LEAD * _scale_of(int(seg["proto"])))
			var part: Part = parts[i] if i < parts.size() else null
			if part == null or part.proto != int(seg["proto"]):
				if part != null:
					part.node.queue_free()
				part = _make(int(seg["proto"]))
				if part == null:
					part = Part.new()  # a part without a model: kept in line, drawn as nothing
					part.node = MeshInstance3D.new()
					add_child(part.node)
				part.proto = int(seg["proto"])
				part.from = at
				part.from_yaw = yaw
				if i < parts.size():
					parts[i] = part
				else:
					parts.append(part)
			else:
				part.from = part.node.position
				part.from_yaw = part.node.rotation.y
				if part.from.distance_to(at) > TELEPORT:
					part.from = at
					part.from_yaw = yaw
			part.to = at
			part.to_yaw = yaw
		_units[unit] = parts


func _scale_of(proto_id: int) -> float:
	var proto: ProtoDB.EntityProto = protos.entity(proto_id) if protos != null else null
	var shared := ModelLibrary.mover_model(proto.name) if proto != null else []
	return float(shared[1]) if not shared.is_empty() else 1.0


func _make(proto_id: int) -> Part:
	if protos == null:
		return null
	var proto: ProtoDB.EntityProto = protos.entity(proto_id)
	if proto == null:
		return null
	var shared := ModelLibrary.mover_model(proto.name)
	if shared.is_empty():
		return null
	var mesh := ModelLibrary.mesh_for(str(shared[0]))
	if mesh == null:
		return null
	var part := Part.new()
	part.model = str(shared[0])
	part.node = MeshInstance3D.new()
	part.node.mesh = mesh
	part.node.scale = Vector3.ONE * float(shared[1])
	# The lava glows (a lone MeshInstance3D has no INSTANCE_CUSTOM for the buildings' glow).
	part.node.set_instance_shader_parameter("f3d_glow", 1.0)
	add_child(part.node)
	return part


func _clear() -> void:
	for parts: Array in _units.values():
		for part: Part in parts:
			part.node.queue_free()
	_units.clear()
