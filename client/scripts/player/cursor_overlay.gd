extends MeshInstance3D
## Factorio's selection and placement marks, drawn flat just above the ground and over everything
## (no depth test, like Factorio's overlays on its sprites): the selection box's corner brackets
## round the hovered entity or vehicle; the yellow arrows of inserters (where they pick up and
## drop), of belts, splitters, undergrounds and loaders being placed (the way they run), of mining
## drills (where they drop) and of fluid connections (in, out, or both ways); and the areas of
## roboports (logistic orange, construction green) and mining drills; and the lines between linked
## roboports (H14, roboport_links.gd).
##
## marks_for() works the marks out as plain data from the mod's `eprops` overlay (ui_model.eprops
## "x"), so the UI test can check them; show() draws a list of marks.

const YELLOW := Color(1.0, 0.8, 0.1, 0.95)
const SELECTION := Color(1.0, 0.86, 0.3, 0.95)
const LOGISTIC_FILL := Color(1.0, 0.5, 0.05, 0.06)
const LOGISTIC_EDGE := Color(1.0, 0.5, 0.05, 0.85)
const CONSTRUCTION_FILL := Color(0.3, 0.85, 0.3, 0.04)
const CONSTRUCTION_EDGE := Color(0.3, 0.85, 0.3, 0.75)
const MINING_FILL := Color(0.55, 0.8, 1.0, 0.16)
const MINING_EDGE := Color(0.55, 0.8, 1.0, 0.6)
## A link between two roboports of one logistic network: the logistic area's orange, and how wide (tiles).
const LINK := Color(1.0, 0.53, 0.0, 0.9)
const LINK_WIDTH := 0.12
## Arrows are this long and wide (tiles).
const ARROW := Vector2(0.5, 0.42)
const LIFT := 0.06
const BELT_TYPES := ["transport-belt", "underground-belt", "splitter", "lane-splitter", "loader", "loader-1x1", "linked-belt"]

var _mesh := ImmediateMesh.new()


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 10
	material_override = m


## A Factorio vector (x east, y south) turned clockwise by a 16-way direction.
static func turn(v: Vector2, dir: int) -> Vector2:
	return v.rotated(float(dir) / 16.0 * TAU)


## The unit vector a 16-way direction points along (north is (0, -1)).
static func dir_vector(dir: int) -> Vector2:
	return turn(Vector2(0, -1), dir)


static func arrow(at: Vector2, towards: Vector2, both := false, color := YELLOW) -> Dictionary:
	return {"k": "arrow", "at": at, "dir": towards.normalized(), "both": both, "c": color}


static func area(rect: Rect2, fill: Color, edge: Color) -> Dictionary:
	return {"k": "area", "rect": rect, "fill": fill, "edge": edge}


## A straight line on the ground from `a` to `b` (tiles): roboport links.
static func line(a: Vector2, b: Vector2, color := LINK, width := LINK_WIDTH) -> Dictionary:
	return {"k": "line", "a": a, "b": b, "c": color, "w": width}


## Corner brackets round a box: `centre` and `half` size in tiles, turned by `yaw` (Godot's, about
## the up axis: a mover's rotation.y).
static func brackets(centre: Vector2, half: Vector2, yaw := 0.0, color := SELECTION) -> Dictionary:
	return {"k": "brackets", "at": centre, "half": half, "yaw": yaw, "c": color}


## The marks for an entity of `type` at `pos` facing `dir`, from its `eprops` overlay `x`; with
## `placing`, also what only shows while it is being placed (a belt's way).
static func marks_for(type: String, x: Dictionary, pos: Vector2, dir: int, placing: bool) -> Array:
	var out: Array = []
	if placing and BELT_TYPES.has(type):
		out.append(arrow(pos, dir_vector(dir)))
	if x.has("ip") and x.has("id"):
		var pick := turn(_vec(x["ip"]), dir)
		var drop := turn(_vec(x["id"]), dir)
		var flow := drop - pick
		out.append(arrow(pos + pick, flow))
		out.append(arrow(pos + drop, flow))
	if x.has("lr"):
		var c := float(x.get("cr", 0.0))
		if c > 0.0:
			out.append(area(Rect2(pos - Vector2(c, c), Vector2(c, c) * 2.0), CONSTRUCTION_FILL, CONSTRUCTION_EDGE))
		var l := float(x["lr"])
		out.append(area(Rect2(pos - Vector2(l, l), Vector2(l, l) * 2.0), LOGISTIC_FILL, LOGISTIC_EDGE))
	if x.has("mr"):
		var r := float(x["mr"])
		out.append(area(Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), MINING_FILL, MINING_EDGE))
		if x.has("vp"):
			out.append(arrow(pos + turn(_vec(x["vp"]), dir), dir_vector(dir)))
	if x.has("fb") and not x.has("fo"):
		for c in x["fb"]:
			if not (c is Array) or c.size() < 4:
				continue
			var way := dir_vector(int(c[2]) + dir)
			var at := pos + turn(Vector2(float(c[0]), float(c[1])), dir) + way * 0.62
			var flow := str(c[3])
			out.append(arrow(at, -way if flow == "i" else way, flow == "b"))
	return out


static func _vec(v) -> Vector2:
	return Vector2(float(v[0]), float(v[1])) if v is Array and v.size() >= 2 else Vector2.ZERO


## Draws these marks (replacing the last ones); an empty list hides them.
func show_marks(marks: Array) -> void:
	_mesh.clear_surfaces()
	visible = not marks.is_empty()
	if marks.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for m: Dictionary in marks:
		match str(m["k"]):
			"area":
				var r: Rect2 = m["rect"]
				_quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), m["fill"], LIFT * 0.5)
				var w := clampf(r.size.x * 0.004, 0.06, 0.2)
				_frame(r, w, m["edge"])
			"brackets":
				_brackets(m["at"], m["half"], float(m["yaw"]), m["c"])
			"arrow":
				_arrow(m["at"], m["dir"], bool(m["both"]), m["c"])
			"line":
				var a: Vector2 = m["a"]
				var b: Vector2 = m["b"]
				var side := (b - a).normalized().orthogonal() * float(m["w"]) * 0.5
				_quad(a + side, b + side, b - side, a - side, m["c"])
	_mesh.surface_end()


func _frame(r: Rect2, w: float, c: Color) -> void:
	var a := r.position
	var b := r.end
	_quad(a, Vector2(b.x, a.y), Vector2(b.x, a.y + w), Vector2(a.x, a.y + w), c)
	_quad(Vector2(a.x, b.y - w), Vector2(b.x, b.y - w), b, Vector2(a.x, b.y), c)
	_quad(a, Vector2(a.x + w, a.y), Vector2(a.x + w, b.y), Vector2(a.x, b.y), c)
	_quad(Vector2(b.x - w, a.y), Vector2(b.x, a.y), b, Vector2(b.x - w, b.y), c)


## Factorio's selection corners: an L in each corner, a third of the shorter side long at most.
func _brackets(centre: Vector2, half: Vector2, yaw: float, c: Color) -> void:
	var arm := clampf(minf(half.x, half.y) * 0.6, 0.15, 0.5)
	var w := 0.07
	var turned := func(p: Vector2) -> Vector2:
		var v := Vector3(p.x, 0.0, p.y).rotated(Vector3.UP, yaw)
		return centre + Vector2(v.x, v.z)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := Vector2(half.x * sx, half.y * sy)
			var along_x := Vector2(-sx * arm, 0.0)
			var along_y := Vector2(0.0, -sy * arm)
			var in_x := Vector2(-sx * w, 0.0)
			var in_y := Vector2(0.0, -sy * w)
			_quad(turned.call(corner), turned.call(corner + along_x), turned.call(corner + along_x + in_y), turned.call(corner + in_y), c)
			_quad(turned.call(corner), turned.call(corner + along_y), turned.call(corner + along_y + in_x), turned.call(corner + in_x), c)


## An arrow centred on `at` pointing along `d` (a unit vector); `both`: a head at each end.
func _arrow(at: Vector2, d: Vector2, both: bool, c: Color) -> void:
	var side := Vector2(-d.y, d.x)
	var half_len := ARROW.x * (0.75 if both else 0.5)
	var head := ARROW.x * (0.4 if both else 0.5)
	var shaft := ARROW.y * 0.32
	var tip := at + d * half_len
	var base := tip - d * head
	_tri(tip, base + side * ARROW.y * 0.5, base - side * ARROW.y * 0.5, c)
	var tail := at - d * half_len
	if both:
		var base2 := tail + d * head
		_tri(tail, base2 - side * ARROW.y * 0.5, base2 + side * ARROW.y * 0.5, c)
		tail = base2
	_quad(tail + side * shaft * 0.5, base + side * shaft * 0.5, base - side * shaft * 0.5, tail - side * shaft * 0.5, c)


func _tri(a: Vector2, b: Vector2, c: Vector2, color: Color, lift := LIFT) -> void:
	for p in [a, b, c]:
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(Vector3(p.x, lift, p.y))


func _quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color, lift := LIFT) -> void:
	_tri(a, b, c, color, lift)
	_tri(a, c, d, color, lift)
