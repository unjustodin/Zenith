extends Node3D
## Inserter arms near the camera. The mod sends each inserter's hand position and held item a
## few times a second (`ih`); the inserter's base is the static entity with the same unit number.
## Each arm swings (angle and reach around its base) from where it is drawn to the new hand
## position until the next update, so the hand follows an arc rather than cutting across, and
## the drawn arm then follows that path with a little smoothing, so updates arriving early or
## late don't make it stop and start.
##
## The arm is two pieces of Wube's printable inserter (tools/models/wube_recipes.py,
## `inserter-arm-<family>-*`): the upper arm, rising from the shoulder on the base to an elbow,
## and the hand, reaching down from the elbow to the wrist over the belt (two-bone IK, solved per
## frame), open, or closed while it holds an item. Each inserter has its family's pieces (basic,
## long, bulk, stack) in its own colour (ARM_TINTS, picked from its sprites), stretched along
## their length to its reach. Without those models: a placeholder turntable, two boxes and a
## hand with two fingers. Everything is instanced: one MultiMesh per part (and per prototype).

const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ItemCards := preload("res://scripts/world/item_cards.gd")

const MISSING_FRAMES := 2
## The placeholder base is Visuals.HEIGHTS["inserter"] tall; the arm stands on it.
const SHOULDER_HEIGHT := 0.5
const HAND_HEIGHT := 0.36  # wrist height: the hand's fingers reach down to the items
const UPPER_ARM := 0.62
const FOREARM := 0.62
const ARM_THICKNESS := 0.065
const TURNTABLE := Vector3(0.3, 0.08, 0.3)
const SHOULDER := Vector3(0.14, 0.14, 0.16)
const HAND_SIZE := Vector3(0.14, 0.05, 0.2)
const FINGER_SIZE := Vector3(0.025, 0.12, 0.05)
const ITEM_DROP := 0.14  # how far below the wrist the held item hangs
## Smoothing of the drawn arm towards the interpolated path, per second.
const FOLLOW_RATE := 30.0
const STEEL := Color(0.52, 0.52, 0.5)
const ModelLibrary := preload("res://scripts/world/model_library.gd")
## Inserter prototype -> arm family (inserter-arm-<family>-*.glb); anything else is basic.
const ARM_FAMILIES := {"long-handed-inserter": "long", "bulk-inserter": "bulk", "stack-inserter": "stack"}
## Arm paint per prototype: [upper arm, hand], from its sprites (hand-base.png, hand-open.png)
## as tools/models/part_colors.py turns a sprite's colour into an albedo (the densest colour of
## the paint, divided by the light Factorio painted in from above, exposure and saturation). The
## upper arm is darker than the hand in every tier. The stack inserter's upper arm is worn steel
## round a yellow inset (their mean), its hand's paint the bright yellow of its forearms.
const ARM_TINTS := {
	"burner-inserter": [Color("56514e"), Color("5d453b")], "inserter": [Color("9a5206"), Color("cb7000")],
	"long-handed-inserter": [Color("93221f"), Color("d2431f")], "fast-inserter": [Color("0a6597"), Color("5581bc")],
	"bulk-inserter": [Color("487c01"), Color("628728")], "stack-inserter": [Color("816347"), Color("be8f00")],
}
const ARM_EDGE_WEAR := 0.12
## Per family: upper arm (shoulder to elbow) and hand (elbow to wrist) as modelled, in tiles,
## and how much both are stretched so the hand reaches the inserter's drop position.
const ARM_LENGTHS := {
	"basic": [0.792, 0.604, 1.0], "long": [1.152, 0.964, 1.07],
	"bulk": [0.792, 0.504, 1.05], "stack": [0.792, 0.584, 1.02],
}
## The Wube base's top, where the arm's tab plugs in.
const MODEL_SHOULDER := 0.38
enum ArmPiece { UPPER, OPEN, CLOSED }
const DARK_STEEL := Color(0.3, 0.3, 0.3)

## Part meshes in draw order; each is a unit-ish box (or cylinder) scaled per instance.
enum Part { TURNTABLE, SHOULDER, UPPER, FOREARM, HAND, FINGERS }


class Arm:
	var base := Vector2.ZERO  # tiles
	var proto_name := ""
	var color := Color.WHITE
	var item_id := 0
	var from_angle := 0.0
	var to_angle := 0.0
	var from_reach := 0.0
	var to_reach := 0.0
	var path_angle := 0.0  # where the update interpolation has it
	var path_reach := 0.0
	var angle := 0.0  # where it is drawn
	var reach := 0.0


var protos: ProtoDB:
	set(value):
		protos = value
		_cards.protos = value
## The world mirror, for each inserter's position and prototype.
var world: Node3D

var _cards := ItemCards.new()
var _arms := {}  # unit -> Arm
var _missing := {}
var _seen := {}
var _frame_tick := -1
var _frame_msec := 0
var _frame_length := 0.1
var _parts: Array[MultiMeshInstance3D] = []
## Prototype name -> [MultiMeshInstance3D per ArmPiece], or null when its models are missing.
var _model_parts := {}


func _ready() -> void:
	_cards.name = "HeldItems"
	add_child(_cards)
	for p in Part.size():
		var mesh: Mesh
		if p == Part.TURNTABLE or p == Part.SHOULDER:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 1.0
			cyl.radial_segments = 12
			cyl.rings = 1
			mesh = cyl
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			mesh = box
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = Visuals.instance_material()
		add_child(mmi)
		_parts.append(mmi)


func reset() -> void:
	_cards.reset()
	_arms.clear()
	_missing.clear()
	_seen.clear()
	_frame_tick = -1


func count() -> int:
	return _arms.size()


## One part of an update: {t: "ih", k: tick, part, parts, l: [unit, hand x, hand y, item id, ...]}
func handle(msg: Dictionary) -> void:
	var k := int(msg.get("k", 0))
	if k != _frame_tick:
		_end_frame()
		if _frame_tick >= 0 and k > _frame_tick:
			# Averaged, so one late packet doesn't change how fast every arm moves. Up to a second:
			# a slowed-down mod (`rate` 3) sends hands every 12 ticks, or 24 with a long interval.
			var length := clampf((k - _frame_tick) / 60.0, 1.0 / 60.0, 1.0)
			_frame_length = lerpf(_frame_length, length, 0.5)
		_frame_tick = k
		_frame_msec = Time.get_ticks_msec()
	var list = msg.get("l")
	if not (list is Array):
		return
	# z = 1: every number is the difference from the hand before it (see belt_items.gd).
	var deltas := int(msg.get("z", 0)) == 1
	var v := [0, 0, 0, 0]
	var i := 0
	while i + 3 < list.size():
		for j in 4:
			v[j] = v[j] + int(list[i + j]) if deltas else int(list[i + j])
		_update(v[0], Vector2(v[1], v[2]) / 256.0, v[3])
		i += 4


func _update(unit: int, hand: Vector2, item_id: int) -> void:
	var rec = world.entities.get(unit) if world != null else null
	if rec == null:
		return  # its chunk isn't loaded
	_seen[unit] = true
	var rel: Vector2 = hand - rec.pos
	var arm: Arm = _arms.get(unit)
	if arm == null:
		arm = Arm.new()
		arm.angle = rel.angle()
		arm.reach = rel.length()
		arm.path_angle = arm.angle
		arm.path_reach = arm.reach
		_arms[unit] = arm
	var proto: ProtoDB.EntityProto = protos.entity(rec.proto_id) if protos != null else null
	arm.color = proto.color if proto != null else Color.GOLDENROD
	arm.proto_name = proto.name if proto != null else ""
	arm.base = rec.pos
	arm.item_id = item_id
	arm.from_angle = arm.path_angle
	arm.from_reach = arm.path_reach
	arm.to_angle = rel.angle()
	arm.to_reach = rel.length()


func _end_frame() -> void:
	if _frame_tick < 0:
		return
	for unit in _arms.keys():
		if _seen.has(unit):
			_missing.erase(unit)
		else:
			var n: int = _missing.get(unit, 0) + 1
			if n >= MISSING_FRAMES:
				_arms.erase(unit)
				_missing.erase(unit)
			else:
				_missing[unit] = n
	_seen.clear()


func _process(delta: float) -> void:
	var t := clampf((Time.get_ticks_msec() - _frame_msec) / (_frame_length * 1000.0), 0.0, 1.0)
	var follow := 1.0 - exp(-delta * FOLLOW_RATE)
	var lists := []
	for p in Part.size():
		lists.append([])
	var colors: Array[Color] = []
	var held := {}  # item id -> Array of positions
	var held_yaws := {}  # item id -> Array of turns
	var model_lists := {}  # proto name -> [Array of Transform3D per ArmPiece]
	for unit in _arms:
		if world != null and not world.entities.has(unit):
			continue  # mined since the last update
		var arm: Arm = _arms[unit]
		arm.path_angle = lerp_angle(arm.from_angle, arm.to_angle, t)
		arm.path_reach = lerpf(arm.from_reach, arm.to_reach, t)
		arm.angle = lerp_angle(arm.angle, arm.path_angle, follow)
		arm.reach = lerpf(arm.reach, arm.path_reach, follow)
		var wrist: Vector3
		if _pieces_for(arm.proto_name) != null:
			if not model_lists.has(arm.proto_name):
				model_lists[arm.proto_name] = [[], [], []]
			wrist = _draw_model_arm(arm, model_lists[arm.proto_name])
		else:
			wrist = _draw_arm(arm, lists)
			colors.append(arm.color)
		if arm.item_id > 0:
			if not held.has(arm.item_id):
				held[arm.item_id] = []
				held_yaws[arm.item_id] = []
			held[arm.item_id].append(wrist - Vector3(0.0, ITEM_DROP, 0.0))
			held_yaws[arm.item_id].append(ItemCards.yaw_for(unit))
	for p in _parts.size():
		var mm := _parts[p].multimesh
		var xforms: Array = lists[p]
		var per_arm := 2 if p == Part.FINGERS else 1
		if mm.instance_count < xforms.size():
			mm.instance_count = maxi(xforms.size(), mm.instance_count * 2)
		mm.visible_instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_color(i, _part_color(p, colors[i if per_arm == 1 else i >> 1]))
	for proto_name in _model_parts:
		var pieces = _model_parts[proto_name]
		if pieces == null:
			continue
		var per_piece: Array = model_lists.get(proto_name, [[], [], []])
		for p in ArmPiece.size():
			var mm: MultiMesh = pieces[p].multimesh
			var xforms: Array = per_piece[p]
			if mm.instance_count < xforms.size():
				mm.instance_count = maxi(xforms.size(), mm.instance_count * 2)
			mm.visible_instance_count = xforms.size()
			for i in xforms.size():
				mm.set_instance_transform(i, xforms[i])
	_cards.draw(held, held_yaws)


## The arm pieces of an inserter prototype, made on first use; null without the models.
func _pieces_for(proto_name: String):
	if _model_parts.has(proto_name):
		return _model_parts[proto_name]
	var family: String = ARM_FAMILIES.get(proto_name, "basic")
	# Made on worker threads (reading one here cost 2-4 ms a piece): the plain arm stands in until then.
	var waiting := false
	for piece in ["upper", "hand-open", "hand-closed"]:
		if not ModelLibrary.ready("inserter-arm-%s-%s" % [family, piece]):
			waiting = true
	if waiting:
		return null
	var out := []
	for piece in ["upper", "hand-open", "hand-closed"]:
		var mesh := ModelLibrary.mesh_for("inserter-arm-%s-%s" % [family, piece])
		if not (mesh is ArrayMesh):
			for mmi in out:
				mmi.queue_free()
			out.clear()
			break
		if ARM_TINTS.has(proto_name):
			mesh = ModelLibrary._tinted(mesh as ArrayMesh, ARM_TINTS[proto_name][0 if piece == "upper" else 1])
			# The arm pieces are thin: nearly every face is a bevel or rim to the weathering, which
			# chipped them all to bare steel. The sprites' arms are painted with a little wear.
			ModelLibrary.set_named(mesh as ArrayMesh, ModelLibrary.TIER_MATERIAL, "edge_wear", ARM_EDGE_WEAR)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "%s_%s" % [proto_name, piece]
		add_child(mmi)
		out.append(mmi)
	_model_parts[proto_name] = out if not out.is_empty() else null
	return _model_parts[proto_name]


## Adds one arm's piece transforms (Wube's models) to `lists` (indexed by ArmPiece); returns
## the wrist position.
func _draw_model_arm(arm: Arm, lists: Array) -> Vector3:
	var lengths: Array = ARM_LENGTHS[ARM_FAMILIES.get(arm.proto_name, "basic")]
	var stretch: float = lengths[2]
	var upper: float = lengths[0] * stretch
	var fore: float = lengths[1] * stretch
	var turn := Basis(Vector3.UP, -arm.angle)
	var out := turn * Vector3.RIGHT
	var shoulder := Vector3(arm.base.x, MODEL_SHOULDER, arm.base.y)
	var wrist := Vector3(arm.base.x, HAND_HEIGHT, arm.base.y) + out * arm.reach
	var elbow := _elbow(shoulder, wrist, out, upper, fore)
	lists[ArmPiece.UPPER].append(_piece(shoulder, elbow, turn, lengths[0]))
	var hand := ArmPiece.CLOSED if arm.item_id > 0 else ArmPiece.OPEN
	lists[hand].append(_piece(elbow, wrist, turn, lengths[1]))
	return wrist


## A model piece (joint at its origin, pointing north, lying flat) from joint a to joint b,
## stretched from its modelled `length`.
func _piece(a: Vector3, b: Vector3, turn: Basis, length: float) -> Transform3D:
	var along := b - a
	var d := maxf(along.length(), 0.01)
	var z := -along / d
	var x := turn * Vector3.BACK
	var y := z.cross(x).normalized()
	if y.y < 0.0:
		y = -y
	x = y.cross(z).normalized()
	# The piece lies on y = 0 with its joints about half its thickness up.
	return Transform3D(Basis(x, y, z * (d / length)), a - y * 0.05)


## Adds one arm's part transforms to `lists` (indexed by Part); returns the wrist position.
func _draw_arm(arm: Arm, lists: Array) -> Vector3:
	var base_top := Visuals.HEIGHTS.get("inserter", 0.3) as float
	# Factorio's angle is clockwise from east on screen (y points south); Godot's yaw is
	# counter-clockwise seen from above, so the arm turns by -angle.
	var turn := Basis(Vector3.UP, -arm.angle)
	var out := turn * Vector3.RIGHT  # horizontal, towards the hand
	var shoulder := Vector3(arm.base.x, SHOULDER_HEIGHT, arm.base.y)
	var wrist := Vector3(arm.base.x, HAND_HEIGHT, arm.base.y) + out * arm.reach
	var elbow := _elbow(shoulder, wrist, out, UPPER_ARM, FOREARM)

	var table_y := base_top + TURNTABLE.y * 0.5
	lists[Part.TURNTABLE].append(Transform3D(turn * Basis.from_scale(TURNTABLE), Vector3(arm.base.x, table_y, arm.base.y)))
	var post := Vector3(SHOULDER.x, SHOULDER_HEIGHT - base_top, SHOULDER.z)
	lists[Part.SHOULDER].append(Transform3D(turn * Basis.from_scale(post), Vector3(arm.base.x, (base_top + SHOULDER_HEIGHT) * 0.5 + 0.02, arm.base.y)))
	lists[Part.UPPER].append(_segment(shoulder, elbow, turn, ARM_THICKNESS * 1.3))
	lists[Part.FOREARM].append(_segment(elbow, wrist, turn, ARM_THICKNESS))
	# The hand stays level, across the arm; two fingers hang from its sides.
	var hand_at := wrist + Vector3(0.0, HAND_SIZE.y * 0.5, 0.0)
	lists[Part.HAND].append(Transform3D(turn * Basis.from_scale(HAND_SIZE), hand_at))
	var across := turn * Vector3.BACK
	for side: float in [-1.0, 1.0]:
		var finger: Vector3 = wrist + across * (side * (HAND_SIZE.z * 0.5 - FINGER_SIZE.z * 0.5)) - Vector3(0.0, FINGER_SIZE.y * 0.5, 0.0)
		lists[Part.FINGERS].append(Transform3D(turn * Basis.from_scale(FINGER_SIZE), finger))
	return wrist


## Where the elbow goes: two-bone IK in the arm's vertical plane, bending upwards.
func _elbow(shoulder: Vector3, wrist: Vector3, out: Vector3, upper: float, fore: float) -> Vector3:
	var to_wrist := wrist - shoulder
	var d := clampf(to_wrist.length(), 0.05, upper + fore - 0.001)
	var horizontal := Vector2(to_wrist.x, to_wrist.z).dot(Vector2(out.x, out.z))
	var dir_angle := atan2(to_wrist.y, horizontal)  # of the shoulder-wrist line, from level
	var cos_a := (upper * upper + d * d - fore * fore) / (2.0 * upper * d)
	var lift := dir_angle + acos(clampf(cos_a, -1.0, 1.0))
	return shoulder + out * (cos(lift) * upper) + Vector3.UP * (sin(lift) * upper)


## A box from a to b, `thickness` square, turned with the arm.
func _segment(a: Vector3, b: Vector3, turn: Basis, thickness: float) -> Transform3D:
	var along := b - a
	var length := maxf(along.length(), 0.01)
	var x := along / length
	var z := turn * Vector3.BACK
	var y := z.cross(x).normalized()
	z = x.cross(y)
	var basis := Basis(x * length, y * thickness, z * thickness)
	return Transform3D(basis, (a + b) * 0.5)


func _part_color(part: int, color: Color) -> Color:
	match part:
		Part.TURNTABLE:
			return color.darkened(0.2)
		Part.UPPER:
			return color.darkened(0.1)
		Part.HAND:
			return color.darkened(0.35)
		Part.FINGERS, Part.SHOULDER:
			return DARK_STEEL
	return STEEL
