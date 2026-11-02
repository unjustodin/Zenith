extends RefCounted
## The character's skeleton: Wube's printable character, skinned by tools/models/wube_rig.py
## (every vertex follows up to two bones, blended by position, so joints stretch instead of
## tearing). The bones are posed here on the CPU and handed to the model's own copy of its
## materials as matrices (rig_mode 3 in factorio_material.gdshaderinc).
##
## A pose is a turn per bone about its head, in the model's frame at rest (the character facing
## north, -Z; its right is +X): X swings a hanging limb forward (and tips the spine and head
## back), Z swings a right limb out to the side (a left one in), Y twists. Children turn with
## their parents. The root also moves and turns the whole body (`root_offset`, `body_turn`).

const CreatureModels := preload("res://scripts/world/creature_models.gd")

var names: Array[String] = []
var parents := PackedInt32Array()
var heads := PackedVector3Array()
var tails := PackedVector3Array()
var index := {}
## Per bone, its turn (Euler angles, radians, YXZ), set each frame by the animation.
var turns := PackedVector3Array()
## Moves the whole body (tiles), after `body_turn`.
var root_offset := Vector3.ZERO
## Turns the whole body about `body_pivot` (falling over).
var body_turn := Basis.IDENTITY
var body_pivot := Vector3.ZERO
## Per bone: rest pose -> posed, in the model's frame.
var skins: Array[Transform3D] = []


func load_rig(model: String) -> bool:
	var rig := CreatureModels.rig(model)
	if str(rig.get("mode", "")) != "pose":
		return false
	for b in rig.get("bones", []):
		index[str(b["name"])] = names.size()
		names.append(str(b["name"]))
		parents.append(int(b["parent"]))
		var h: Array = b["head"]
		var t: Array = b["tail"]
		heads.append(Vector3(float(h[0]), float(h[1]), float(h[2])))
		tails.append(Vector3(float(t[0]), float(t[1]), float(t[2])))
	turns.resize(names.size())
	skins.resize(names.size())
	return not names.is_empty()


func clear() -> void:
	turns.fill(Vector3.ZERO)
	root_offset = Vector3.ZERO
	body_turn = Basis.IDENTITY


## Adds `amount` of a turn to a bone (poses are sums of weighted layers).
func add(bone: String, turn: Vector3, amount := 1.0) -> void:
	var i: int = index.get(bone, -1)
	if i >= 0:
		turns[i] += turn * amount


func compute() -> void:
	var root := Transform3D(Basis.IDENTITY, root_offset) \
		* Transform3D(body_turn, body_pivot - body_turn * body_pivot)
	for i in names.size():
		var r := Basis.from_euler(turns[i])
		var local := Transform3D(r, heads[i] - r * heads[i])
		skins[i] = (skins[parents[i]] if parents[i] >= 0 else root) * local


## Rows of every bone's matrix for the material's rig_bone (16 bones, the rest at rest).
func rows() -> Array[Vector4]:
	var out: Array[Vector4] = []
	for i in 16:
		var m: Transform3D = skins[i] if i < skins.size() else Transform3D.IDENTITY
		var b := m.basis
		for r in 3:
			out.append(Vector4(b.x[r], b.y[r], b.z[r], m.origin[r]))
	return out


## Where a point of the rest pose on `bone` is now, in the model's frame.
func point(bone: String, rest: Vector3) -> Vector3:
	return skins[index[bone]] * rest


## A frame carried by `bone`, given in the rest pose (a tool in the hand).
func frame(bone: String, rest: Transform3D) -> Transform3D:
	return skins[index[bone]] * rest


func head_of(bone: String) -> Vector3:
	return heads[index[bone]]


func tail_of(bone: String) -> Vector3:
	return tails[index[bone]]
