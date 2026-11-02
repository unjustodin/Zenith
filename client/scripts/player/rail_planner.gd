extends Node3D
## Factorio 2.x's rail planner: with rails in the cursor, Factorio's green arrows mark the free rail
## ends near the cursor, and a click on (or near) one anchors the planner there; from then on the path of straight, half-diagonal and curved pieces
## from the anchor to the cursor is drawn translucent (blue past the rails you have: those become
## ghosts, red where something is in the way), and a click (or letting go of a drag) builds it and
## moves the anchor to its end. Toggle rail layer (Alt+R) lifts the path onto elevated rails with a
## ramp, and elevated paths get their supports. Right click or Q drops the anchor.
##
## The geometry is Factorio's own (client/data/rail_extensions.json, read from the game's
## LuaRailEnd.get_rail_extensions), so every piece joins where the game says; the mod builds the
## pieces (`rails`) and makes ghosts of what the character can't pay for or reach.

const WorldMirror := preload("res://scripts/world/world.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const GhostShader := preload("res://shaders/ghost.gdshader")
const ItemIcons := preload("res://scripts/world/item_icons.gd")

const DATA_PATH := "res://data/rail_extensions.json"
## Rails each piece costs (items_to_place_this, checked in 2.1.23).
const COST := {"straight-rail": 1, "half-diagonal-rail": 2, "curved-rail-a": 3, "curved-rail-b": 3}
const MAX_EXPANSIONS := 6000
## The planner plans this far from its rail end at most (the path to a cursor further off isn't drawn).
const MAX_REACH := 120.0
const MAX_PIECES := 120
## The character's build_distance and the mod's slack: pieces further away become ghosts.
const REACH := 11.5
## A free rail end this close to the cursor is snapped to when anchoring.
const SNAP := 2.5
## Elevated rails need a support within its range (rail-support: 11 tiles; checked in 2.1.23):
## one goes at a rail end every SUPPORT_STEP tiles of track.
const SUPPORT_STEP := 14.0
## Factorio's rail planner arrows (utility sprites, read from the install): 82 x 44 px at scale 0.5,
## pointing north in the picture. Free ends within ARROW_RADIUS of the cursor get one.
const ARROW_FILES := {"free": "rail-planner-indication-arrow.png", "anchored": "rail-planner-indication-arrow-anchored.png"}
const ARROW_SIZE := Vector2(82.0, 44.0) / 64.0
const ARROW_RADIUS := 16.0
const MAX_ARROWS := 24
## How high elevated rails' ends are drawn (rail-ramp's top).
const ELEVATED_Y := 3.0
const TINTS := {"ok": Color(0.85, 1.0, 0.85, 0.5), "ghost": Color(0.58, 0.68, 1.0, 0.42), "bad": Color(1.0, 0.3, 0.25, 0.5)}

static var _data := {}

## player_input (world, hud, avatar); untyped to keep the scripts apart.
var pi: Node
## The anchored rail end: {"pos": Vector2i, "dir": int, "layer": 0|1}, or {}.
var anchor := {}
## Toggle rail layer: the path ends on this layer (0 ground, 1 elevated).
var target_layer := 0
## The path to the cursor: [{"name", "pos" (Vector2i), "dir", "state": "ok"|"ghost"|"bad"}], and
## where it ends.
var path: Array = []
var path_end := {}

var _pool: Array[MeshInstance3D] = []
var _arrows: Array[MeshInstance3D] = []
var _arrow_materials := {}
## The arrows shown now: [[pos (Vector2i), dir, layer, "free" | "anchored"], ...].
var arrows: Array = []
var _materials := {}
var _last_goal := Vector2i(1 << 30, 1 << 30)
var _last_anchor := {}


func _ready() -> void:
	for k in TINTS:
		var m := ShaderMaterial.new()
		m.shader = GhostShader
		m.set_shader_parameter("tint", TINTS[k])
		_materials[k] = m


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


## The held item is a rail planner (`iuse` "r"): [support entity, elevated allowed] or [].
func use_of(item: String) -> Array:
	var u: Dictionary = pi.hud.ui.model.item_uses.get(item, {})
	return u.get("r", [])


static func base_name(name: String) -> String:
	return name.substr(9) if name.begins_with("elevated-") else name


static func _v(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## The two ends of a rail piece: [[position, end direction, layer], ...].
static func ends_of(name: String, pos: Vector2i, dir: int) -> Array:
	var out: Array = []
	if name == "rail-ramp":
		# Ramps turn in quarter turns: the table has a north-facing one.
		for e in data().get("ramp", []):
			var off := Vector2(float(e[0]), float(e[1]))
			for _t in dir / 4:
				off = Vector2(-off.y, off.x)
			out.append([pos + Vector2i(roundi(off.x), roundi(off.y)), posmod(int(e[2]) + dir, 16), int(e[3])])
		return out
	var layer := 1 if name.begins_with("elevated-") else 0
	var key := "%s/%d" % [base_name(name), dir]
	for e in data().get("ends", {}).get(key, []):
		out.append([pos + _v(e), int(e[2]), layer])
	return out


## Free rail ends of existing rails (and their ghosts) near a point: [[pos, dir, layer], ...]. An
## end is free when no other rail has an end on the same spot facing back at it.
func free_ends(near: Vector2, radius: float) -> Array:
	var seen := {}  # "x,y,dir,layer" -> count
	var list: Array = []
	var center := WorldMirror.chunk_of(near)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cv = pi.world.chunks.get(center + Vector2i(dx, dy))
			if cv == null:
				continue
			for r in cv.entities.values():
				var proto: ProtoDB.EntityProto = pi.world.protos.entity(r.proto_id)
				if proto == null:
					continue
				if proto.type == "entity-ghost" and r.extra.has("gh"):
					proto = pi.world.protos.entity(int(r.extra["gh"]))
					if proto == null:
						continue
				if not (ModelLibrary.RAIL_TYPES.has(proto.type) or proto.type == "rail-ramp"):
					continue
				if r.pos.distance_to(near) > radius + 8.0:
					continue
				var at := Vector2i(roundi(r.pos.x), roundi(r.pos.y))
				for e in ends_of(proto.type, at, r.dir):
					var k := "%d,%d,%d,%d" % [e[0].x, e[0].y, e[1], e[2]]
					seen[k] = int(seen.get(k, 0)) + 1
					list.append(e)
	var out: Array = []
	for e in list:
		var back := "%d,%d,%d,%d" % [e[0].x, e[0].y, posmod(int(e[1]) + 8, 16), e[2]]
		if not seen.has(back) and Vector2(e[0]).distance_to(near) <= radius:
			out.append(e)
	return out


## The free end nearest the point within SNAP, or [].
func nearest_end(near: Vector2) -> Array:
	var best: Array = []
	var best_d := SNAP
	for e in free_ends(near, SNAP):
		var d := Vector2(e[0]).distance_to(near)
		if d <= best_d:
			best = e
			best_d = d
	return best


## The cheapest path of pieces from an end (position, direction it points along, layer) to within
## a tile of the goal, by A* over Factorio's extensions; [] if none within the search budget.
static func find_path(start: Vector2i, dir: int, layer: int, goal: Vector2) -> Array:
	var ext: Dictionary = data().get("ext", {})
	if ext.is_empty():
		return []
	var prefix := "elevated-" if layer == 1 else ""
	if Vector2(start).distance_to(goal) > MAX_REACH:
		return []
	var heap: Array = []  # binary heap of [f, g, pos, dir] by f
	_push(heap, [Vector2(start).distance_to(goal), 0.0, start, dir])
	var came := {}  # state key -> [prev key, piece]
	var best_g := {_key(start, dir): 0.0}
	var expansions := 0
	while not heap.is_empty() and expansions < MAX_EXPANSIONS:
		var cur: Array = _pop(heap)
		var pos: Vector2i = cur[2]
		var d: int = cur[3]
		var g: float = cur[1]
		var k := _key(pos, d)
		if g > float(best_g.get(k, INF)) + 0.001:
			continue
		if Vector2(pos).distance_to(goal) <= 1.2 and pos != start:
			return _unwind(came, k)
		expansions += 1
		for e in ext.get(str(d), []):
			var name := str(e[0])
			var npos := pos + Vector2i(int(e[5]), int(e[6]))
			var nd := int(e[4])
			var step := Vector2(npos - pos).length()
			if name.begins_with("curved"):
				step += 0.6  # Factorio's planner keeps straight where it can
			var ng := g + step
			var nk := _key(npos, nd)
			if ng < float(best_g.get(nk, INF)):
				best_g[nk] = ng
				came[nk] = [k, {"name": prefix + name, "pos": pos + Vector2i(int(e[2]), int(e[3])), "dir": int(e[1]),
					"end": [npos, nd]}]
				_push(heap, [ng + Vector2(npos).distance_to(goal), ng, npos, nd])
	return []


static func _push(heap: Array, item: Array) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if heap[parent][0] <= item[0]:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = item


static func _pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if heap.is_empty():
		return top
	var i := 0
	var n := heap.size()
	while true:
		var c := i * 2 + 1
		if c >= n:
			break
		if c + 1 < n and heap[c + 1][0] < heap[c][0]:
			c += 1
		if heap[c][0] >= last[0]:
			break
		heap[i] = heap[c]
		i = c
	heap[i] = last
	return top


static func _key(p: Vector2i, d: int) -> String:
	return "%d,%d,%d" % [p.x, p.y, d]


static func _unwind(came: Dictionary, k: String) -> Array:
	var out: Array = []
	while came.has(k):
		var step: Array = came[k]
		out.push_front(step[1])
		k = step[0]
		if out.size() > MAX_PIECES:
			return []
	return out


## Supports for an elevated path: one at a rail end every SUPPORT_STEP tiles, the first after
## the anchor's (a ramp's top carries its own), and one near the end.
static func supports_for(pieces: Array, support: String, from_ramp: bool) -> Array:
	var out: Array = []
	if support == "":
		return out
	var run := 7.0 if from_ramp else SUPPORT_STEP
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		if not str(p["name"]).begins_with("elevated-"):
			continue
		var step := Vector2(p["end"][0] - p["pos"]).length() * 2.0
		run += step
		if run >= SUPPORT_STEP or i == pieces.size() - 1 and run >= SUPPORT_STEP * 0.5:
			out.append({"name": support, "pos": p["end"][0], "dir": posmod(int(p["end"][1]), 8), "end": p["end"]})
			run = 0.0
	return out


## Works out the path for this frame (only when the anchor or the cursor tile changed).
func update(item: String, has_ground: bool, ground: Vector2, ghost_mode: bool) -> void:
	var use := use_of(item)
	if use.is_empty() or not has_ground:
		_show([])
		_show_arrows([])
		return
	if anchor.is_empty():
		path = []
		_show([])
		var free: Array = []
		for e in free_ends(ground, ARROW_RADIUS):
			free.append([e[0], e[1], e[2], "free"])
		free.sort_custom(func(a: Array, b: Array) -> bool: return Vector2(a[0]).distance_squared_to(ground) < Vector2(b[0]).distance_squared_to(ground))
		_show_arrows(free.slice(0, MAX_ARROWS))
		return
	_show_arrows([[anchor["pos"], anchor["dir"], anchor["layer"], "anchored"]])
	var goal := Vector2i(roundi(ground.x), roundi(ground.y))
	if goal == _last_goal and anchor == _last_anchor:
		_show(path)
		return
	_last_goal = goal
	_last_anchor = anchor.duplicate()
	var pieces: Array = []
	var start: Vector2i = anchor["pos"]
	var dir: int = anchor["dir"]
	var layer: int = anchor["layer"]
	var ramped := false
	if target_layer != layer and dir % 4 == 0 and int(use[1]) == 1:
		# A ramp first: up from the ground, or down from elevated rails (it then faces back).
		var ramp_dir := dir if layer == 0 else posmod(dir + 8, 16)
		var ahead := Vector2i(roundi(sin(dir / 16.0 * TAU)), -roundi(cos(dir / 16.0 * TAU)))
		pieces.append({"name": "rail-ramp", "pos": start + ahead * 8, "dir": ramp_dir, "end": [start + ahead * 16, dir]})
		start = start + ahead * 16
		layer = target_layer
		ramped = true
	pieces.append_array(find_path(start, dir, layer, ground))
	if pieces.size() == int(ramped):
		path = []
		path_end = {}
		_show([])
		return
	var supports := supports_for(pieces, str(use[0]), ramped and layer == 1)
	var have: int = pi.hud.count_of(item)
	var reach_from: Vector2 = pi.avatar.ground_position() if pi.avatar != null else ground
	var spent := 0
	path = []
	for s in supports:
		s["state"] = "ghost" if ghost_mode or pi.hud.count_of(str(s["name"])) == 0 else "ok"
		path.append(s)
	for p in pieces:
		var cost := int(COST.get(base_name(str(p["name"])), 1))
		var state := "ok"
		if ghost_mode or spent + cost > have or Vector2(p["pos"]).distance_to(reach_from) > REACH:
			state = "ghost"
		else:
			spent += cost
		if _blocked(p):
			state = "bad"
		p["state"] = state
		path.append(p)
	var last: Array = pieces[-1]["end"]
	path_end = {"pos": last[0], "dir": last[1], "layer": layer}
	_show(path)


## Something other than rails, ore or ghosts on the piece's spot.
func _blocked(p: Dictionary) -> bool:
	var at := Vector2(p["pos"])
	var r: WorldMirror.Rec = pi.world.pick(at)
	if r == null:
		return false
	var proto: ProtoDB.EntityProto = pi.world.protos.entity(r.proto_id)
	if proto == null:
		return false
	return not (ModelLibrary.RAIL_TYPES.has(proto.type) or proto.type in ["resource", "entity-ghost", "rail-ramp",
		"rail-support", "rail-signal", "rail-chain-signal", "tile-ghost"])


## Click: anchors at a free end near the cursor, or builds the path and moves the anchor to its
## end. Returns true when the click was the planner's.
func click(item: String, ground: Vector2, ghost_mode: bool) -> bool:
	if use_of(item).is_empty():
		return false
	if anchor.is_empty():
		var e := nearest_end(ground)
		if e.is_empty():
			return false  # no rail end nearby: an ordinary straight rail is built
		anchor = {"pos": e[0], "dir": int(e[1]), "layer": int(e[2])}
		target_layer = anchor["layer"]
		return true
	return build(item, ghost_mode)


func build(item: String, ghost_mode: bool) -> bool:
	if path.is_empty():
		return true
	for p in path:
		if p["state"] == "bad":
			pi.hud.show_message("Can't build the rails there")
			return true
	var l: Array = []
	for p in path:
		l.append([str(p["name"]), int(p["pos"].x * 256), int(p["pos"].y * 256), int(p["dir"])])
	var cmd := {"t": "rails", "item": item, "l": l}
	if ghost_mode:
		cmd["ghost"] = 1
	Bridge.send(cmd)
	anchor = path_end.duplicate()
	target_layer = int(anchor.get("layer", 0))
	path = []
	_last_goal = Vector2i(1 << 30, 1 << 30)
	return true


func clear() -> void:
	anchor = {}
	path = []
	path_end = {}
	_show([])
	_show_arrows([])


## Factorio's arrow at each rail end, flat on the rails just past the end, pointing out of it.
func _show_arrows(list: Array) -> void:
	arrows = list
	while _arrows.size() < list.size():
		var m := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = ARROW_SIZE
		m.mesh = plane
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_arrows.append(m)
	for i in _arrows.size():
		var m := _arrows[i]
		m.visible = i < list.size()
		if not m.visible:
			continue
		var e: Array = list[i]
		var a := int(e[1]) / 16.0 * TAU
		var out := Vector2(sin(a), -cos(a))
		var at := Vector2(e[0]) + out * (ARROW_SIZE.y / 2.0 + 0.1)
		m.transform = Transform3D(Basis(Vector3.UP, -a), Vector3(at.x, 0.15 + ELEVATED_Y * int(e[2]), at.y))
		m.material_override = _arrow_material(str(e[3]))


func _arrow_material(kind: String) -> Material:
	if _arrow_materials.has(kind):
		return _arrow_materials[kind]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 2
	var data := ItemIcons.factorio_data_dir()
	var path := data.path_join("core/graphics/arrows").path_join(ARROW_FILES.get(kind, ARROW_FILES["free"])) if data != "" else ""
	var image := Image.load_from_file(path) if path != "" and FileAccess.file_exists(path) else null
	if image != null:
		mat.albedo_texture = ImageTexture.create_from_image(image)
	else:
		mat.albedo_color = Color(0.2, 0.9, 0.2, 0.85) if kind == "free" else Color(0.95, 0.75, 0.2, 0.85)
	_arrow_materials[kind] = mat
	return mat


func toggle_layer() -> void:
	target_layer = 1 - target_layer
	_last_goal = Vector2i(1 << 30, 1 << 30)
	pi.hud.show_message("Rails end elevated" if target_layer == 1 else "Rails end on the ground")


## Rails needed for the path, for the cursor's label.
func rails_needed() -> int:
	var n := 0
	for p in path:
		n += int(COST.get(base_name(str(p["name"])), 0))
	return n


func _show(pieces: Array) -> void:
	while _pool.size() < pieces.size():
		var m := MeshInstance3D.new()
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		_pool.append(m)
	for i in _pool.size():
		var m := _pool[i]
		m.visible = i < pieces.size()
		if not m.visible:
			continue
		var p: Dictionary = pieces[i]
		var name := str(p["name"])
		var mesh := ModelLibrary.mesh_for_entity(name, name, {}, int(p["dir"]))
		if mesh == null:
			mesh = Visuals.box_mesh()
		m.mesh = mesh
		var yaw := Visuals.direction_yaw(ModelLibrary.turn_dir(name, int(p["dir"])))
		m.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p["pos"].x, 0.0, p["pos"].y))
		m.material_override = _materials[str(p.get("state", "ok"))]
