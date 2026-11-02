extends RefCounted
## api.world: what this client knows of the game, read-only, from its own copy of the world. What
## it knows is what the bridge sends: buildings in the chunks drawn round the focus, moving things
## and trains within the entity distance of it (Settings → Graphics), the players' list. Positions
## are Godot's: x east and z south in tiles, y up (Factorio's (x, y) is (x, z) here).
##
## Moving things are named by the prototype types Factorio gives them: "locomotive", "cargo-wagon",
## "fluid-wagon", "artillery-wagon", "car", "spider-vehicle", "character" (other players; the
## client's own character is character()), "logistic-robot", "construction-robot",
## "combat-robot", "unit" (biters and spitters), "spider-unit", "rocket-silo-rocket", "cargo-pod"...
## Every function returns copies: changing them changes nothing.

const TRAIN_TYPES := ["locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon", "infinity-cargo-wagon"]
const ROBOT_TYPES := ["logistic-robot", "construction-robot", "combat-robot", "capture-robot"]

var _host


func _init(host) -> void:
	_host = host


func in_game() -> bool:
	return _host.in_game()


## The client's own character: {unit, position (Vector3), forward (Vector3, flat), vehicle (the
## unit it drives, 0 none), visible}; {} outside a game.
func character() -> Dictionary:
	var avatar = _host.game_node("avatar")
	if not avatar is Node3D:
		return {}
	var a := avatar as Node3D
	return {"unit": int(a.get("unit")), "position": a.global_position, "forward": _forward(a),
		"vehicle": int(a.get("vehicle")), "visible": a.visible}


## The moving things of these types (all when empty) near the focus:
## [{unit, type, name, position (Vector3, as drawn), forward (Vector3, flat)}].
func movers(types: Array = []) -> Array:
	var layer = _host.game_node("movers")
	var out: Array = []
	if layer == null:
		return out
	var wanted: Array = types if not types.is_empty() else _all_types(layer)
	for type in wanted:
		for pair in layer.units_of_type(str(type)):
			var unit := int(pair[0])
			var node: Node3D = pair[1]
			if node == null:
				continue
			out.append({"unit": unit, "type": str(type), "name": layer.proto_name_of(unit),
				"position": node.position, "forward": _forward(node)})
	return out


## One moving thing as movers() gives it, or {} when it is gone (or too far to be sent).
func mover(unit: int) -> Dictionary:
	var layer = _host.game_node("movers")
	if layer == null:
		return {}
	var node: Node3D = layer.node_of(unit)
	if node == null:
		return {}
	var name: String = layer.proto_name_of(unit)
	var proto = layer.protos.entities_by_name.get(name) if layer.get("protos") != null else null
	return {"unit": unit, "type": str(proto.type) if proto != null else "", "name": name,
		"position": node.position, "forward": _forward(node)}


## Trains with a carriage near the focus (sent about every half second):
## [{id, state (Factorio's train_state name), manual, speed (tiles a tick, negative backwards),
## station (unit of the stop it is at, 0 none), destination (stop name), carriages (units, front
## first)}].
func trains() -> Array:
	var model = _host.ui_model()
	var out: Array = []
	if model == null:
		return out
	for id in model.trains:
		var t: Dictionary = model.trains[id]
		out.append({"id": int(id), "state": str(t["state"]), "manual": bool(t["manual"]), "speed": float(t["speed"]),
			"station": int(t["station"]), "destination": str(t["dest"]), "carriages": (t["carriages"] as Array).duplicate()})
	return out


## The train a carriage belongs to, or 0.
func train_of(unit: int) -> int:
	var model = _host.ui_model()
	return int(model.train_of_unit.get(unit, 0)) if model != null else 0


## The players of the game: [{index, name, connected, color, unit (their character, 0 none),
## surface, me (the client's own)}].
func players() -> Array:
	var model = _host.ui_model()
	var out: Array = []
	if model == null:
		return out
	for p: Dictionary in model.players:
		out.append({"index": int(p["index"]), "name": str(p["name"]), "connected": bool(p["connected"]),
			"color": p["color"], "unit": int(p["unit"]), "surface": str(p["surface"]),
			"me": int(p["index"]) == int(model.me_player)})
	return out


## Rockets climbing from their silos now, as drawn: [Vector3].
func rockets() -> Array:
	var layer = _host.game_node("rockets")
	return layer.launch_positions() if layer != null and layer.has_method("launch_positions") else []


## The chunks drawn now (Vector2i, 32 tiles each).
func chunks() -> Array:
	var w = _host.game_node("world")
	return w.chunks.keys() if w != null else []


## The buildings (and trees, rocks...) of one drawn chunk, of these types (all when empty):
## [{unit, name, type, position (Vector2, tiles), direction (0-15), working (true, false, or null
## when unknown)}].
func entities_in_chunk(chunk: Vector2i, types: Array = []) -> Array:
	var w = _host.game_node("world")
	var out: Array = []
	if w == null or not w.chunks.has(chunk):
		return out
	var cv = w.chunks[chunk]
	for key in cv.entities:
		var r = cv.entities[key]
		var proto = w.protos.entity(r.proto_id)
		if proto == null or (not types.is_empty() and not types.has(proto.type)):
			continue
		var working = null
		if r.unit != 0 and w.working.has(r.unit):
			working = int(w.working[r.unit]) == 1
		out.append({"unit": r.unit, "name": proto.name, "type": proto.type, "position": r.pos, "direction": r.dir, "working": working})
	return out


## The same within `radius` tiles of a ground point.
func entities_near(point: Vector2, radius: float, types: Array = []) -> Array:
	var out: Array = []
	var c0 := Vector2i(floori((point.x - radius) / 32.0), floori((point.y - radius) / 32.0))
	var c1 := Vector2i(floori((point.x + radius) / 32.0), floori((point.y + radius) / 32.0))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			for e in entities_in_chunk(Vector2i(cx, cy), types):
				if (e["position"] as Vector2).distance_to(point) <= radius:
					out.append(e)
	return out


## The point the world is loaded round (tiles).
func focus() -> Vector2:
	var rig = _host.rig()
	return rig.focus_point() if rig != null else Vector2.ZERO


## The time of day as drawn: 0 noon, 0.5 midnight; and how dark it is, 0 to 0.85.
func daytime() -> float:
	var m = _host.main
	return float(m.get("_daytime")) if m != null and m.get("_daytime") != null else 0.0


func darkness() -> float:
	var m = _host.main
	return float(m.get("_darkness")) if m != null and m.get("_darkness") != null else 0.0


## The planet shown ("nauvis", "vulcanus"...), and whether it is a space platform.
func planet() -> String:
	var m = _host.main
	var sky = m.get("_planet_sky") if m != null else null
	return str(sky.planet) if sky != null else ""


func on_platform() -> bool:
	var m = _host.main
	return m != null and m.get("_space") == true


static func _forward(n: Node3D) -> Vector3:
	var f := -n.basis.z
	f.y = 0.0
	return f.normalized() if f.length() > 0.001 else Vector3.FORWARD


func _all_types(_layer) -> Array:
	return ["character", "car", "spider-vehicle", "cargo-pod", "rocket-silo-rocket", "unit", "spider-unit"] + TRAIN_TYPES + ROBOT_TYPES
