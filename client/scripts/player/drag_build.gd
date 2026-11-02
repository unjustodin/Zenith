extends RefCounted
## Building while the left button is held, as Factorio 2.x does it:
##   belts follow the cursor and turn corners (the belt where the line turns is turned to the new
##       way); with "Smart belt building" (Settings → Interface, on by default) an obstacle or a
##       belt line crossing the way is jumped with a pair of the belt's undergrounds once the
##       cursor is past it and within the underground's reach. "Lock belt building to straight
##       line" keeps belts on the first line instead.
##   pipes drag in a straight line and jump obstacles with a pair of pipes-to-ground;
##   electric poles go along the line at their wire reach from the last one;
##   anything else is placed along the line, one footprint after another;
## and a faster belt (or anything of the same fast-replace kind) dragged over a line replaces it,
## which the mod's `build` does. Shift (or none left, or remote view) makes it all ghosts.

const ProtoDB := preload("res://scripts/world/protos.gd")
const WorldMirror := preload("res://scripts/world/world.gd")
const Settings := preload("res://scripts/menu/settings.gd")

const DIRS := {Vector2i(0, -1): 0, Vector2i(1, 0): 4, Vector2i(0, 1): 8, Vector2i(-1, 0): 12}

## player_input (world, hud, build_dir, _blocked, _remember); untyped to keep the scripts apart.
var pi: Node

var _active := false
var _item := ""
var _proto: ProtoDB.EntityProto = null
var _ghost := false
var _start := Vector2i.ZERO
## The line's axis once the cursor first moved off the start tile (Vector2i.ZERO before that).
var _axis := Vector2i.ZERO
## The tile last stepped onto (belts walk tile by tile to the cursor).
var _cur := Vector2i.ZERO
## The last tile built on, its direction, and whether it was an underground.
var _last_built := Vector2i.ZERO
var _last_dir := 0
var _has_last := false
## An obstacle being jumped: the tile before it (where the entrance goes) and the way along, or none.
var _gap_from := Vector2i.ZERO
var _gap_dir := -1
## Where the last piece of a line went (poles: the last pole; others: the last footprint).
var _line_last := Vector2i.ZERO
## Footprint lines: where the first one went (the cursor) and how many followed.
var _line_pos0 := Vector2.ZERO
var _line_k := 0
## Commands sent during this drag, for tests: [cmd, ...].
var sent: Array = []


func begin(item: String, proto: ProtoDB.EntityProto, ground: Vector2, ghost: bool) -> void:
	_active = true
	_item = item
	_proto = proto
	_ghost = ghost
	_start = Vector2i(floori(ground.x), floori(ground.y))
	_cur = _start
	_axis = Vector2i.ZERO
	_has_last = false
	_gap_dir = -1
	sent = []
	# The first one goes exactly where a click puts it (the mod snaps it to the grid).
	_send_at(_item, ground, int(pi.build_dir))
	_last_built = _start
	_last_dir = int(pi.build_dir)
	_has_last = true
	_line_last = _start
	_line_k = 0
	_line_pos0 = ground


func end() -> void:
	_active = false


func active() -> bool:
	return _active


## Called every frame while the button is held, with the cursor's ground point.
func update(ground: Vector2) -> void:
	if not _active:
		return
	var tile := Vector2i(floori(ground.x), floori(ground.y))
	if tile == _cur:
		return
	if _axis == Vector2i.ZERO:
		var d := tile - _start
		_axis = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	if _proto.type == "transport-belt" and not bool(Settings.get_value("interface", "lock_belt_straight")):
		_follow(tile)
	else:
		_along_line(tile)


## Belts: one tile at a time towards the cursor, the longer way first.
func _follow(target: Vector2i) -> void:
	var guard := 0
	while _cur != target and guard < 64:
		guard += 1
		var d := target - _cur
		var step := Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
		_step_belt(_cur + step, int(DIRS[step]))
		_cur += step


## Straight-line entities: the cursor projected on the first line.
func _along_line(tile: Vector2i) -> void:
	var along := (tile - _start).x * _axis.x + (tile - _start).y * _axis.y
	var target := _start + _axis * along
	if along < 0:
		return  # Factorio doesn't build back past where the drag started
	var dir := int(DIRS.get(_axis, int(pi.build_dir)))
	while _cur != target:
		var next := _cur + _axis if (target - _cur).x * _axis.x + (target - _cur).y * _axis.y > 0 else _cur - _axis
		match _proto.type:
			"transport-belt":
				_step_belt(next, dir)
			"pipe":
				_step_pipe(next, dir)
			"electric-pole":
				_step_pole(next)
			_:
				_step_footprint(next, dir)
		_cur = next


func _step_belt(next: Vector2i, dir: int) -> void:
	pi.build_dir = dir
	if _gap_dir >= 0:
		_continue_gap(next, dir, _under_item("b"))
		return
	# The line turns: the belt where it turns points the new way (Factorio's corner).
	if _has_last and _last_dir != dir and _gap_dir < 0 and _last_built == next - _vec(dir):
		_place(_last_built, dir, null)
	if _obstacle(next, dir):
		if bool(Settings.get_value("interface", "smart_belt_building")) and _under_item("b") != "" and _has_last:
			_gap_from = _last_built
			_gap_dir = dir
		return
	_place(next, dir, null)


func _step_pipe(next: Vector2i, dir: int) -> void:
	if _gap_dir >= 0:
		_continue_gap(next, dir, _under_item("p"))
		return
	if _obstacle(next, dir):
		if _under_item("p") != "" and _has_last:
			_gap_from = _last_built
			_gap_dir = dir
		return
	_place(next, dir, null)


## Past the obstacle: an underground (pipe-to-ground) pair when the free tile is within reach, the
## entrance replacing the last piece before it.
func _continue_gap(next: Vector2i, dir: int, under_item: String) -> void:
	if dir != _gap_dir:
		_gap_dir = -1
		return
	if _obstacle(next, dir):
		return
	var under_proto: ProtoDB.EntityProto = pi.world.protos.placed_entity(under_item)
	var reach := 0
	if under_proto != null:
		reach = int(pi.hud.ui.model.eprops.get(under_proto.id, {}).get("under", 0.0))
	var dist := absi((next - _gap_from).x) + absi((next - _gap_from).y)
	_gap_dir = -1
	if under_proto == null or dist > reach:
		_place(next, dir, null)  # too far for the underground: the line starts again past it
		return
	if under_proto.type == "pipe-to-ground":
		# A pipe-to-ground's direction is its above-ground connection: back along the line at the
		# entrance, forward at the exit (checked in 2.1.23).
		_send(under_item, _gap_from, posmod(dir + 8, 16))
		_send(under_item, next, dir)
	else:
		# The mod makes the second of a pair the exit (both face the way items go).
		_send(under_item, _gap_from, dir)
		_send(under_item, next, dir)
	_last_built = next
	_last_dir = dir
	_has_last = true


func _step_pole(next: Vector2i) -> void:
	var wire := float(pi.hud.ui.model.eprops.get(_proto.id, {}).get("wire", 0.0))
	if wire <= 0.0:
		_step_footprint(next, int(pi.build_dir))
		return
	if Vector2(next - _line_last).length() > floorf(wire):
		# Past the reach: the pole goes on the furthest free tile back towards the last one.
		var back := next - _axis
		while back != _line_last and _obstacle(back, int(pi.build_dir)):
			back -= _axis
		if back != _line_last:
			_place(back, int(pi.build_dir), null)
			_line_last = back


func _step_footprint(next: Vector2i, dir: int) -> void:
	var size: Vector2i = _proto.tile_size
	if dir == 4 or dir == 12:
		size = Vector2i(size.y, size.x)
	var span := absi(_axis.x) * size.x + absi(_axis.y) * size.y
	var along := (next - _start).x * _axis.x + (next - _start).y * _axis.y
	while (_line_k + 1) * span <= along:
		_line_k += 1
		_send_at(_item, _line_pos0 + Vector2(_axis * span * _line_k), int(pi.build_dir))


static func _vec(dir: int) -> Vector2i:
	for v in DIRS:
		if DIRS[v] == dir:
			return v
	return Vector2i.ZERO


## The belt's or pipe's own underground ("b" / "p" in `iuse`) if the character has some, or "".
func _under_item(kind: String) -> String:
	var u: Dictionary = pi.hud.ui.model.item_uses.get(_item, {})
	var under := str(u.get(kind, ""))
	if under == "" or (not _ghost and pi.hud.count_of(under) == 0):
		return ""
	return under


## In the way of the line: what player_input's build check calls blocked, and for belts a belt
## crossing the line (a belt along it is replaced or turned instead).
func _obstacle(tile: Vector2i, dir: int) -> bool:
	var pos := Vector2(tile) + Vector2(0.5, 0.5)
	if pi._blocked(_proto, pos, Vector2i.ONE):
		return true
	if _proto.type == "transport-belt" and bool(Settings.get_value("interface", "smart_belt_building")):
		var r: WorldMirror.Rec = pi.world.pick(pos)
		if r != null:
			var p: ProtoDB.EntityProto = pi.world.protos.entity(r.proto_id)
			if p != null and p.type == "transport-belt" and (r.dir % 8) != (dir % 8):
				return true
	return false


func _place(tile: Vector2i, dir: int, _ground) -> void:
	var size: Vector2i = _proto.tile_size
	if dir == 4 or dir == 12:
		size = Vector2i(size.y, size.x)
	_send(_item, tile, dir, size)
	_last_built = tile
	_last_dir = dir
	_has_last = true


func _send(item: String, tile: Vector2i, dir: int, size := Vector2i.ONE) -> void:
	# The mod snaps to the grid: aim at the footprint's centre.
	var at := Vector2(tile) + Vector2(0.5, 0.5)
	if size.x % 2 == 0:
		at.x = float(tile.x)
	if size.y % 2 == 0:
		at.y = float(tile.y)
	_send_at(item, at, dir)


func _send_at(item: String, at: Vector2, dir: int) -> void:
	var cmd := {"t": "build", "item": item, "x": int(at.x * 256.0), "y": int(at.y * 256.0), "d": dir}
	if _ghost or pi.hud.count_of(item) == 0:
		cmd["ghost"] = 1
	if pi._lmb_super:
		cmd["sf"] = 1  # Ctrl+Shift: super-forced, what's in the way is marked for deconstruction
	if pi.build_mirror:
		cmd["m"] = 1
	if pi.cursor_quality != "normal":
		cmd["q"] = pi.cursor_quality
	Bridge.send(cmd)
	sent.append(cmd)
	if not cmd.has("ghost"):
		pi._remember({"do": "build", "item": item, "x": at.x, "y": at.y, "d": dir})
