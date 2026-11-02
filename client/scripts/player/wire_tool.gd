extends Node3D
## Factorio's wire tools (Alt+R red, Alt+G green, Alt+C copper; the shortcut bar too): click an
## entity to take a wire from it, then another to connect them, or to disconnect them if that
## wire is already there. The wire then hangs from the second one, so a row can be wired click by
## click; clicking the entity it hangs from again lets go of it, right click too. While a wire
## hangs from an entity it is drawn from there to the mouse with a ring on the ground for how far
## it reaches (`eprops`: a pole's wire reach, `cw` circuit wire reach, a power switch's `ww`);
## past that the wire turns grey and the click is refused. Which connector a click takes (a
## combinator's input or output side, a power switch's left or right) the mod works out from where
## the click landed (wiring.lua). player_input.gd owns one and hands it the clicks.

const WorldMirror := preload("res://scripts/world/world.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")

## Tool name (player_input.gd's cursor_tool) -> the wire kind on the wire ("r", "g", "w").
const KINDS := {"red-wire": "r", "green-wire": "g", "copper-wire": "w"}
const COLORS := {"r": Color(0.9, 0.15, 0.1), "g": Color(0.15, 0.75, 0.15), "w": Color(0.85, 0.5, 0.2)}
const TOO_FAR := Color(0.55, 0.55, 0.55)
const COPPER_TYPES := ["electric-pole", "power-switch"]
const RING_SEGMENTS := 64
const SAG := 0.045

var world: WorldMirror
var wires = null  # wires.gd: where wires meet each entity
var model = null  # ui_model.gd: eprops, and the commands
## The end the wire hangs from: {rec, end (the command's end), at (Vector3)}; empty when none.
var from := {}

var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mi.mesh = _mesh
	_mi.material_override = _material
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)


static func is_wire(tool: String) -> bool:
	return KINDS.has(tool)


## Lets go of the hanging wire; true if there was one (right click does this before putting the
## tool away).
func cancel() -> bool:
	var had := not from.is_empty()
	from = {}
	_mesh.clear_surfaces()
	return had


## Whether an entity takes this kind of wire: copper on poles and power switches, circuit wires on
## anything with a circuit wire reach (or a pole). Unknown prototypes are let through: the mod
## decides.
func takes(rec: WorldMirror.Rec, kind: String) -> bool:
	var proto: ProtoDB.EntityProto = world.protos.entity(rec.proto_id) if rec != null else null
	if rec == null or rec.unit == 0 or proto == null:
		return false
	if kind == "w":
		return COPPER_TYPES.has(proto.type)
	return reach(rec, kind) > 0.0 or proto.type == "electric-pole" or model == null or model.eprops.is_empty()


## How far a wire of `kind` reaches from the entity, in tiles (0: unknown or none).
func reach(rec: WorldMirror.Rec, kind: String) -> float:
	if model == null or rec == null:
		return 0.0
	var e: Dictionary = model.eprops.get(rec.proto_id, {})
	var x: Dictionary = e.get("x", {})
	if kind == "w":
		return float(e.get("wire", 0.0)) if float(e.get("wire", 0.0)) > 0.0 else float(x.get("ww", 0.0))
	return float(x.get("cw", 0.0)) if float(x.get("cw", 0.0)) > 0.0 else float(e.get("wire", 0.0))


## The reach between two ends: the shorter of the two, as Factorio's.
func _limit(a: WorldMirror.Rec, b: WorldMirror.Rec, kind: String) -> float:
	var ra := reach(a, kind)
	var rb := reach(b, kind) if b != null else 0.0
	if ra > 0.0 and rb > 0.0:
		return minf(ra, rb)
	return maxf(ra, rb)


static func end_of(rec: WorldMirror.Rec, at: Vector2) -> Dictionary:
	return {"u": rec.unit, "p": rec.proto_id, "x": rec.fixed.x, "y": rec.fixed.y,
		"mx": int(roundf(at.x * 256.0)), "my": int(roundf(at.y * 256.0))}


func _attach(rec: WorldMirror.Rec, kind: String) -> Vector3:
	if wires != null:
		return wires.attach_point(rec, kind)
	return Vector3(rec.pos.x, 1.0, rec.pos.y)


## A left click with the wire tool `tool` on `rec` (null: nothing there) at ground point `at`.
## Returns a message for the player, or "".
func click(tool: String, rec: WorldMirror.Rec, at: Vector2) -> String:
	var kind: String = KINDS.get(tool, "")
	if kind == "" or rec == null:
		return ""
	if not takes(rec, kind):
		return "Copper wire connects electric poles and power switches" if kind == "w" else "That can't take a circuit wire"
	if from.is_empty():
		from = {"rec": rec, "end": end_of(rec, at), "at": _attach(rec, kind)}
		return ""
	var a: WorldMirror.Rec = from["rec"]
	if a.unit == rec.unit and not _sides_differ(rec, from["end"], at):
		cancel()
		return ""
	var limit := _limit(a, rec, kind)
	if limit > 0.0 and a.pos.distance_to(rec.pos) > limit + 0.01:
		return "Wire can't reach that far"
	model.wire(kind, from["end"], end_of(rec, at))
	from = {"rec": rec, "end": end_of(rec, at), "at": _attach(rec, kind)}
	return ""


## A combinator clicked on its other side (input vs output): a wire from itself to itself.
func _sides_differ(rec: WorldMirror.Rec, first: Dictionary, at: Vector2) -> bool:
	var proto: ProtoDB.EntityProto = world.protos.entity(rec.proto_id)
	if proto == null or not proto.type in ["arithmetic-combinator", "decider-combinator", "selector-combinator"]:
		return false
	var yaw := float(rec.dir) / 16.0 * TAU
	var forward := Vector2(sin(yaw), -cos(yaw))
	var a := (Vector2(int(first["mx"]), int(first["my"])) / 256.0 - rec.pos).dot(forward)
	var b := (at - rec.pos).dot(forward)
	return (a > 0.0) != (b > 0.0)


## Shift+click on a pole: removes its copper cables.
func clear_cables(rec: WorldMirror.Rec) -> bool:
	var proto: ProtoDB.EntityProto = world.protos.entity(rec.proto_id) if rec != null else null
	if proto == null or proto.type != "electric-pole" or rec.unit == 0:
		return false
	model.wire_clear({"u": rec.unit, "p": rec.proto_id, "x": rec.fixed.x, "y": rec.fixed.y})
	if not from.is_empty() and (from["rec"] as WorldMirror.Rec).unit == rec.unit:
		cancel()
	return true


## Draws the hanging wire to the mouse (or the hovered entity's connection) and the reach ring.
func update(tool: String, hovered: WorldMirror.Rec, at: Vector2, has_ground: bool) -> void:
	_mesh.clear_surfaces()
	var kind: String = KINDS.get(tool, "")
	if kind == "" or from.is_empty() or not has_ground:
		return
	var a: WorldMirror.Rec = from["rec"]
	if not world.entities.has(a.key):
		cancel()
		return
	var start: Vector3 = from["at"]
	var target: WorldMirror.Rec = hovered if hovered != null and hovered.unit != 0 and takes(hovered, kind) else null
	var end: Vector3 = _attach(target, kind) if target != null else Vector3(at.x, 0.15, at.y)
	var limit := _limit(a, target, kind)
	var dist := a.pos.distance_to(target.pos if target != null else at)
	var color: Color = COLORS[kind] if limit <= 0.0 or dist <= limit + 0.01 else TOO_FAR
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_span(start, end, color)
	if limit > 0.0:
		_ring(Vector3(a.pos.x, 0.06, a.pos.y), limit, Color(color.r, color.g, color.b, 0.55))
	_mesh.surface_end()


## The wire as a sagging ribbon, crossed so it shows from any side.
func _span(a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	var points: Array[Vector3] = []
	for i in 13:
		var t := i / 12.0
		var p := a.lerp(b, t)
		p.y -= 4.0 * t * (1.0 - t) * length * SAG
		points.append(p)
	for i in points.size() - 1:
		var p0 := points[i]
		var p1 := points[i + 1]
		var along := (p1 - p0).normalized()
		var side := along.cross(Vector3.UP).normalized() * 0.035
		if side.length() < 0.001:
			side = Vector3(0.035, 0, 0)
		var up := along.cross(side).normalized() * 0.035
		for off: Vector3 in [side, up]:
			_quad(p0 - off, p0 + off, p1 + off, p1 - off, color)


func _ring(c: Vector3, r: float, color: Color) -> void:
	var w := 0.06
	for i in RING_SEGMENTS:
		var a0 := TAU * i / RING_SEGMENTS
		var a1 := TAU * (i + 1) / RING_SEGMENTS
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		_quad(c + d0 * (r - w), c + d0 * (r + w), c + d1 * (r + w), c + d1 * (r - w), color)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for p in [a, b, c, a, c, d]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(p)
