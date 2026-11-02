extends RefCounted
## Factorio's spidertron remote (the shortcut bar's "Create spidertron remote", an rts tool):
## drag to select spidertrons (Shift+drag adds to the selection, right-drag removes), then click
## the ground to send them there or Shift+click to queue another waypoint. The selection lives
## here, since the bridge's character has no player of its own; the mod moves the spidertrons
## (`spider_go`) and says where they are heading (`spd`), which is drawn as Factorio's waypoint
## marks.

const CursorOverlay := preload("res://scripts/player/cursor_overlay.gd")

## The remote's selection colours (base/prototypes/item.lua: select, alt_select, reverse_select).
const SELECT := Color8(71, 255, 73)
const ADD := Color8(239, 153, 34)
const REMOVE := Color8(246, 255, 0)
## A press and release closer than this (tiles) is a click, not a drag.
const CLICK := 0.4
## How often the waypoints are asked for while the remote is held with spidertrons selected.
const QUERY_MSEC := 1000

## Selected spidertrons' unit numbers, in the order they were picked.
var selected: Array = []
## unit -> [Vector2, ...]: each selected spidertron's queued waypoints (`spd`).
var waypoints := {}
var _last_query := 0


func _init() -> void:
	Bridge.message_received.connect(_on_message)


func _on_message(msg: Dictionary) -> void:
	if str(msg.get("t", "")) != "spd" or not (msg.get("l") is Array):
		return
	for rec in msg["l"]:
		if rec is Array and rec.size() >= 2 and rec[1] is Array:
			var points: Array = []
			for p in rec[1]:
				if p is Array and p.size() >= 2:
					points.append(Vector2(int(p[0]), int(p[1])) / 256.0)
			waypoints[int(rec[0])] = points


## The spidertrons (movers of type spider-vehicle) standing in `rect` (tiles).
static func spiders_in(movers, rect: Rect2) -> Array:
	var out: Array = []
	if movers == null:
		return out
	for unit in movers._movers:
		var m = movers._movers[unit]
		var proto = movers.protos.entity(m.proto_id) if movers.protos != null else null
		if proto == null or proto.type != "spider-vehicle":
			continue
		var at := Vector2(m.node.position.x, m.node.position.z)
		var half: Vector2 = proto.size() * 0.5
		if Rect2(at - half, half * 2.0).intersects(rect, true):
			out.append(int(unit))
	return out


## A left press went up at `to` after going down at `from` (tiles): a drag selects (Shift adds), a
## click on a spidertron picks it, a click elsewhere sends the selection there (Shift queues).
func left(movers, from: Vector2, to: Vector2, shift: bool) -> String:
	var rect := Rect2(from, Vector2.ZERO).expand(to)
	var click := from.distance_to(to) < CLICK
	var under := spiders_in(movers, rect.grow(0.1 if click else 0.0))
	if click and under.is_empty():
		if selected.is_empty():
			return "No spidertron selected: drag over spidertrons to select them"
		Bridge.send({"t": "spider_go", "l": selected.duplicate(), "x": int(to.x * 256.0), "y": int(to.y * 256.0), "q": 1 if shift else 0})
		return ""
	if not shift:
		selected.clear()
		waypoints.clear()
	for u in under:
		if not selected.has(u):
			selected.append(u)
	query(true)
	return ""


## A right drag (reverse select) takes the spidertrons in it out of the selection.
func right(movers, from: Vector2, to: Vector2) -> void:
	for u in spiders_in(movers, Rect2(from, Vector2.ZERO).expand(to).grow(0.1)):
		selected.erase(u)
		waypoints.erase(u)


## Asks for the selection's waypoints (at most once a second unless `now`).
func query(now := false) -> void:
	if selected.is_empty():
		return
	var t := Time.get_ticks_msec()
	if now or t - _last_query >= QUERY_MSEC:
		_last_query = t
		Bridge.send({"t": "spider_q", "l": selected.duplicate()})


## Marks for cursor_overlay.gd: green brackets round each selected spidertron that is in view,
## and a small square at each of its waypoints.
func marks(movers) -> Array:
	var out: Array = []
	if movers == null:
		return out
	for u in selected:
		var at = movers.position_of(u)
		if at is Vector3:
			out.append(CursorOverlay.brackets(Vector2(at.x, at.z), Vector2(1.5, 1.5), 0.0, SELECT))
		for p in waypoints.get(u, []):
			out.append(CursorOverlay.area(Rect2(p - Vector2(0.3, 0.3), Vector2(0.6, 0.6)), Color(SELECT, 0.35), SELECT))
	return out


## The colour of the box being dragged: green, orange with Shift (add), yellow right-dragged.
static func box_color(shift: bool, reverse: bool) -> Color:
	return REMOVE if reverse else (ADD if shift else SELECT)
