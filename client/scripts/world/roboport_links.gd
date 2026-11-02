extends RefCounted
## Which roboports are linked into one logistic network (H14), for the lines Factorio draws between
## them while a roboport is hovered or held. A hovered roboport's links come from the game itself
## (`hinfo` `rn`, LuaLogisticCell.neighbours); for the rest (the held one's preview and the others
## round it) Factorio's rule stands in: two roboports join when their logistic squares meet, each
## square reaching its logistic radius (`eprops` `lr`) and the other's connection distance (the same,
## for every roboport in the game). Roboports are kept per chunk as the world's chunks change.

const WorldMirror := preload("res://scripts/world/world.gd")

var world: WorldMirror
## The held roboport's links are looked for this far from it (tiles).
var reach := 160.0
## proto id -> logistic radius (tiles), for roboport prototypes; set by the owner from `eprops`.
var radius_of := func(_proto_id: int) -> float: return 25.0

var _ports := {}  # chunk -> [[position (tiles), proto id, unit], ...]
var _is_port := {}  # proto id -> bool


func _init(w: WorldMirror) -> void:
	world = w
	if world != null and world.has_signal("entities_changed"):
		world.entities_changed.connect(_on_entities_changed)
		for c in world.chunks:
			_on_entities_changed(c)


func _on_entities_changed(c: Vector2i) -> void:
	var cv = world.chunks.get(c)
	if cv == null:
		_ports.erase(c)
		return
	var list: Array = []
	for rec in cv.entities.values():
		var port = _is_port.get(rec.proto_id)
		if port == null:
			var proto = world.protos.entity(rec.proto_id)
			port = proto != null and proto.type == "roboport"
			_is_port[rec.proto_id] = port
		if port:
			list.append([rec.pos, rec.proto_id, rec.unit])
	if list.is_empty():
		_ports.erase(c)
	else:
		_ports[c] = list


## Whether roboports at `a` and `b` with logistic radii `ra` and `rb` are linked: their squares meet.
static func linked(a: Vector2, ra: float, b: Vector2, rb: float) -> bool:
	var d := (a - b).abs()
	return d.x <= ra + rb and d.y <= ra + rb


## The roboports within `distance` of `at`: [[position, radius, unit], ...].
func near(at: Vector2, distance: float) -> Array:
	var out: Array = []
	var lo := Vector2i(floori((at.x - distance) / WorldMirror.CHUNK), floori((at.y - distance) / WorldMirror.CHUNK))
	var hi := Vector2i(floori((at.x + distance) / WorldMirror.CHUNK), floori((at.y + distance) / WorldMirror.CHUNK))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			for p in _ports.get(Vector2i(cx, cy), []):
				if (p[0] as Vector2).distance_to(at) <= distance:
					out.append([p[0], float(radius_of.call(int(p[1]))), int(p[2])])
	return out


## The lines Factorio shows while a roboport of logistic radius `radius` is held at `at`: every link
## between the roboports round it, and the ones the held roboport would make there. [[a, b], ...].
func held_lines(at: Vector2, radius: float) -> Array:
	var ports := near(at, reach)
	var out: Array = []
	for i in ports.size():
		var a: Array = ports[i]
		if linked(at, radius, a[0], a[1]):
			out.append([at, a[0]])
		for j in range(i + 1, ports.size()):
			var b: Array = ports[j]
			if linked(a[0], a[1], b[0], b[1]):
				out.append([a[0], b[0]])
	return out


## A hovered roboport's lines: to the roboports the game says it is linked to (`rn`), or, until the
## mod has answered, to the ones the rule links it to.
func hovered_lines(at: Vector2, radius: float, unit: int, from_game: Variant) -> Array:
	var out: Array = []
	if from_game is Array:
		for p in from_game:
			out.append([at, p])
		return out
	for p in near(at, radius * 2.0 + 30.0):
		if int(p[2]) != unit and linked(at, radius, p[0], p[1]):
			out.append([at, p[0]])
	return out
