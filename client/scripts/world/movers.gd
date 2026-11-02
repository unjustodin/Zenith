extends Node3D
## Things that move: biters, cars, trains, robots, asteroids, other characters. The mod sends their
## positions every few ticks within the focus radius. Each is drawn on the game's own clock (the
## messages' tick), a little behind it, between its last two positions: steady motion, where
## chasing each new position made fast movers (robots, asteroids) lurch and stall.
## A mover missing from several frames in a row has left the area (or died) and is removed.
##
## Flying robots and walking creatures, hundreds at a time in a fight or over a busy base, are drawn
## on the GPU instead (mover_records.gd): when a new position of one arrives, its last few positions
## and the clock ticks it is drawn at each go into its record, and the shaders work out where it is
## each frame. Nothing is done for them here per frame; where one is drawn is worked out when
## something asks (position_of, robot_near). The rest (cars, trains, spidertrons, pods, characters),
## few and with parts moved by vehicle_anim.gd, are still moved here every frame on their nodes.

const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const Creatures := preload("res://scripts/world/creatures.gd")
const CreatureModels := preload("res://scripts/world/creature_models.gd")
const Avatar := preload("res://scripts/player/avatar.gd")
const GameClock := preload("res://scripts/world/game_clock.gd")
const VehicleAnim := preload("res://scripts/world/vehicle_anim.gd")
const RobotSwarm := preload("res://scripts/world/robot_swarm.gd")
const MoverRecords := preload("res://scripts/world/mover_records.gd")

const MISSING_FRAMES := 3
const FOLLOW_RATE := 15.0
## A jump this far (tiles) between two positions is a teleport, not motion: no gliding across.
const TELEPORT := 12.0
## Tiles a tick, a little over the fastest train's (a locomotive's 1.2 with the best fuel's bonus).
const TRAIN_SPEED := 1.6
## Positions kept per mover, enough to cover a burst of late messages, and more while it is drawn
## further back than they reach.
const HISTORY := 8
const HISTORY_MAX := 48
## Longer than this between two positions is standing still, not a coarse update (Factorio moves a
## flying robot's reported position about every 20 ticks).
const STILL_TICKS := 40.0
const ENEMY_TYPES := ["unit", "spider-unit", "segmented-unit", "segment"]
## Flying robots get Factorio's drop shadow instead of a lit one: their model squashed flat on
## the ground, offset as their shadow sprites are (31.75, 19.75 px at scale 0.5 from the robot's
## position: 0.99 tiles east, 0.62 tiles down the screen, which is 0.83 tiles south on the ground).
const ROBOT_TYPES := {"logistic-robot": true, "construction-robot": true, "combat-robot": true, "capture-robot": true}
const SHADOW_OFFSET := Vector3(0.99, 0.0, 0.83)
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.45)
## Cells (tiles) of the grid robot_near and friendly_near look in.
const GRID := 8.0
## Creatures moved here (characters, and creatures whose model can't walk on the GPU) further than
## these from the focus are moved every second and every third frame (their walk is animated in the
## shader, so only their place steps).
const CREATURE_NEAR := 40.0
const CREATURE_FAR := 80.0
## GPU-drawn movers checked against the remote view's fog a frame (a slice of them, round and round).
const FOG_SLICE := 64
## Tiles a GPU-drawn robot can be drawn from its newest position (it is drawn about a step behind).
const DRAWN_SLACK := 3.0


class Mover:
	var unit := 0
	var node: Node3D
	var target := Vector3.ZERO
	var yaw_goal := 0.0
	var oriented := false
	var missing := 0
	var enemy := false
	var robot := false
	var shadow: Node3D  # robots' drop shadow, or null
	## Drawn with the others of its kind (robot_swarm.gd), its node left empty; or null.
	var bot: RobotSwarm.Bot
	var type := ""  # its prototype's type
	var height := 0.0  # Visuals.flying_height of its type
	var on_rails := false  # rolling stock: drawn at the rails' height under it (elevated, ramps)
	var rail_h := 0.0
	## Wheels (a car's, a train's axles): [MeshInstance3D, AnimPart, radius, steers].
	var wheels: Array = []
	var roll := 0.0
	var steer := 0.0

	## A locomotive's headlights (Factorio's `front_light`: two cones 0.6 tiles either side).
	var headlights: Array[SpotLight3D] = []

	var proto_id := 0
	var fixed := Vector2i.ZERO  # the latest position as sent, for commands that name the mover
	## The last few positions it moved to and their ticks, oldest first (messages can arrive in
	## bursts). Only changes are kept: Factorio moves robots' (and asteroids') reported position
	## about every 20 ticks, a tile at a time (2.1.23), though it draws them gliding.
	var ticks: Array[float] = []
	var spots: Array[Vector3] = []
	## Ticks between its position changes, measured: 2 for a car, about 20 for a robot.
	var key_gap := 2.0
	var lag := -1.0  # ticks behind the clock it is drawn, eased (_process_movers)
	var from := Vector3.ZERO  # the position before the newest (its direction of travel)
	var to_tick := -1.0
	var fogged := false  # hidden by the remote view where no radar sees
	## Drawn by creatures.gd; `stagger` spreads far ones' updates over frames (_process_movers).
	var creature := false
	var stagger := 0
	## Its record (mover_records.gd) when the GPU draws it, else -1: its node isn't moved then.
	var slot := -1
	var rec_flags := 0  # its record's flags (BUILDER, ANIMATED, CARGO; HIDDEN is `fogged`)
	var kind := Vector4.ZERO  # its record's kind values (creatures: gait seed, radians a tile, bob scale)
	var walked := 0.0  # tiles it walked to its newest position (creatures' gait)
	var recorded := false  # its record has been written (it has a position)
	var cell := Vector2i(1 << 30, 0)  # its cell in _robot_grid (GPU-drawn robots)


var protos: ProtoDB
## Types that ride rails, drawn at the rails' height (elevated rails, ramps).
const ROLLING_STOCK := {"locomotive": true, "cargo-wagon": true, "fluid-wagon": true, "artillery-wagon": true,
	"infinity-cargo-wagon": true}
## The world mirror (world.gd), for the rails under rolling stock (rail_height). Untyped.
var world
## The character the client controls is drawn by the avatar instead.
var puppet_unit := 0
## The remote view's coverage (remote_fog.gd), or null: movers where it doesn't see are hidden.
var fog: Node3D = null

var _movers := {}  # unit -> Mover
## The movers moved here every frame (not drawn from a record): unit -> Mover.
var _node_movers := {}
## Records of the movers the GPU draws.
var records := MoverRecords.new()
## GPU-drawn robots by GRID cell of their newest position, kept as positions arrive: cell -> {Mover: true}.
var _robot_grid := {}
var _fogging := false
var _fog_list: Array = []  # GPU-drawn movers' units, checked against the fog a slice a frame
var _fog_at := 0
var _beam := 0.0  # how much the headlights show (Avatar.beam of the night)
var _frame_tick := -1
## The game's tick as the client reckons it, run on at the game's measured rate (game_clock.gd).
var clock := GameClock.new()
var _seen := {}
## Movers whose model is still being made on a worker thread (ModelLibrary.ready): unit -> true.
## They move about with nothing drawn and get their model (_dress) once it is ready.
var _waiting := {}
var _model_generation := -1
var _materials := {}  # proto id -> Material
var _shadow_material: StandardMaterial3D
## Biters and spitters are drawn and animated together (creatures.gd); their nodes stay empty.
var creatures := Creatures.new()
## Vehicles' and robots' moving parts and glow (spidertron legs, robots, cargo pods, treads).
var vehicles := VehicleAnim.new()
## Flying robots, drawn together.
var robots := RobotSwarm.new()
## Non-enemy movers moved here by GRID cell, built at most once a frame when asked (robot_near, friendly_near).
var _grid := {}
var _grid_frame := -1
var _frame := 0
## The last frame's _process time, microseconds (--robot-probe).
var process_usec := 0


func _ready() -> void:
	creatures.name = "Creatures"
	add_child(creatures)
	vehicles.name = "VehicleAnim"
	add_child(vehicles)
	robots.name = "Robots"
	robots.vehicles = vehicles
	robots.records = records
	add_child(robots)
	creatures.pose_source = records.state
	creatures.records = records


func reset() -> void:
	for m in _movers.values():
		_free(m)
	_movers.clear()
	_node_movers.clear()
	_robot_grid.clear()
	_fog_list.clear()
	_seen.clear()
	_waiting.clear()
	_frame_tick = -1
	clock = GameClock.new()
	creatures.clear()
	vehicles.reset()
	robots.clear()
	_grid.clear()


func count() -> int:
	return _movers.size()


func _notification(what: int) -> void:
	# Robots' nodes are kept out of the tree (_dress), so nothing else frees them.
	if what == NOTIFICATION_PREDELETE:
		for m: Mover in _movers.values():
			if is_instance_valid(m.node) and not m.node.is_inside_tree():
				m.node.free()


## Movers still waiting for their model (--robot-probe waits for none).
func waiting() -> int:
	return _waiting.size()


## One part of a frame: {t: "mv", k: tick, part, parts, l: [[unit, proto, x, y, orientation?], ...]}
func handle(msg: Dictionary) -> void:
	var k := int(msg.get("k", 0))
	if k != _frame_tick:
		_end_frame()
		_frame_tick = k
	# p: the ticks until the next update, longer while the mod is slowed down (`rate`).
	clock.heard(k, float(msg.get("p", 0)))
	var list = msg.get("l")
	if not (list is Array):
		return
	# z = 1: a record's first four numbers are the differences from the record before it.
	var deltas := int(msg.get("z", 0)) == 1
	var unit := 0
	var proto := 0
	var x := 0
	var y := 0
	for rec in list:
		if rec is Array and rec.size() >= 4:
			var r: Array = rec
			if deltas:
				unit += int(r[0])
				proto += int(r[1])
				x += int(r[2])
				y += int(r[3])
			else:
				unit = int(r[0])
				proto = int(r[1])
				x = int(r[2])
				y = int(r[3])
			_update(unit, proto, x, y, r)


func _end_frame() -> void:
	if _frame_tick < 0:
		return
	for unit in _movers.keys():
		var m: Mover = _movers[unit]
		if _seen.has(unit):
			m.missing = 0
		else:
			m.missing += 1
			if m.missing >= MISSING_FRAMES:
				creatures.remove(unit)
				_free(m)
				_movers.erase(unit)
				_node_movers.erase(unit)
				_waiting.erase(unit)
				vehicles.detach(unit)
	_seen.clear()


## One mover's record: its unit, prototype and place (fixed), and `rec` for its orientation.
## The prototype is looked up only for a new mover (or one whose prototype changed).
func _update(unit: int, proto_id: int, x: int, y: int, rec: Array) -> void:
	if unit == puppet_unit:
		return
	_seen[unit] = true
	var m: Mover = _movers.get(unit)
	if m == null or m.proto_id != proto_id:
		var proto: ProtoDB.EntityProto = protos.entity(proto_id)
		if proto == null:
			return
		if m == null:
			m = Mover.new()
			m.unit = unit
			m.node = Node3D.new()
			m.node.position = Vector3(x / 256.0, Visuals.flying_height(proto.type), y / 256.0)
			if proto.type == "locomotive":
				_add_headlights(m)
			m.enemy = ENEMY_TYPES.has(proto.type)
			m.robot = ROBOT_TYPES.has(proto.type)
			add_child(m.node)
			_movers[unit] = m
			_node_movers[unit] = m
			m.proto_id = proto_id
			if _model_ready(proto):
				_dress(unit, m, proto)
			else:
				_waiting[unit] = true
		m.type = proto.type
		m.height = Visuals.flying_height(proto.type)
		m.on_rails = ROLLING_STOCK.has(proto.type)
	var pos := Vector3(x / 256.0, m.height, y / 256.0)
	var tick := float(_frame_tick)
	# A train at full speed covers 1.4 tiles a tick: further than TELEPORT between the updates of a
	# slowed-down mod (`rate`), so the limit grows with the time since the last one.
	var teleport := maxf(TELEPORT, (tick - m.to_tick) * TRAIN_SPEED)
	var fresh := m.to_tick < 0.0 or pos.distance_to(m.target) > teleport or tick - m.to_tick > maxf(60.0, clock.gap * 4.0)
	var changed := fresh
	if fresh:
		# New, teleported, or not seen for a second: no gliding from where it was.
		m.ticks.clear()
		m.spots.clear()
		m.from = pos
		m.node.position = pos
	elif tick > m.to_tick:
		m.from = m.target
	if m.ticks.is_empty():
		m.ticks.append(tick)
		m.spots.append(pos)
	elif tick > m.ticks[-1] and pos != m.spots[-1]:
		var since := tick - m.ticks[-1]
		if since > maxf(m.key_gap * 3.0, STILL_TICKS):
			# It stood still: it set off about one step's time ago, not at the old position's tick.
			m.ticks.append(tick - m.key_gap)
			m.spots.append(m.spots[-1])
		else:
			m.key_gap = lerpf(m.key_gap, clampf(since, 1.0, STILL_TICKS), 0.5)
		m.walked += Vector2(pos.x - m.spots[-1].x, pos.z - m.spots[-1].z).length()
		m.ticks.append(tick)
		m.spots.append(pos)
		changed = true
		# Kept back as far as it is drawn behind (further while the mod is slowed down, `rate`):
		# drawn before its oldest position it would stand there.
		var keep := maxf(m.lag, clock.gap * GameClock.DELAY_SENDS) + m.key_gap * 2.0
		while m.ticks.size() > HISTORY_MAX or (m.ticks.size() > HISTORY and m.ticks[1] < tick - keep):
			m.ticks.remove_at(0)
			m.spots.remove_at(0)
	elif tick == m.ticks[-1] and pos != m.spots[-1]:
		m.spots[m.spots.size() - 1] = pos
		changed = true
	m.to_tick = tick
	m.target = pos
	m.proto_id = proto_id
	m.fixed = Vector2i(x, y)
	m.oriented = rec.size() >= 5
	var goal_was := m.yaw_goal
	if m.oriented:
		m.yaw_goal = Visuals.orientation_yaw(float(rec[4]) / 1000.0)
		if fresh:
			m.node.rotation.y = m.yaw_goal  # appear facing its way, not turning into it
	else:
		var step: Vector3 = m.target - m.from
		if Vector2(step.x, step.z).length() > 0.02:
			m.yaw_goal = atan2(-step.x, -step.z)
	if m.slot >= 0 and (changed or absf(m.yaw_goal - goal_was) > 0.0001):
		_write(m, fresh)


## Writes a GPU-drawn mover's record (mover_records.gd) from its history: its last four positions and
## their ticks, its lag (eased from where it is now towards what this update says, as
## _process_movers eases a node mover's), and what carries on from how it is drawn now (its facing,
## speed, flying, arms), so nothing jumps.
func _write(m: Mover, fresh: bool) -> void:
	var now := clock.tick
	if now < 0.0 or m.ticks.is_empty():
		return  # written once it has a position (a new mover is dressed before its first is kept)
	var want := maxf(clock.gap * GameClock.DELAY_SENDS, m.key_gap + clock.gap)
	var yaw0 := m.node.rotation.y
	var c0 := 0.0
	var c1 := 0.0
	var l0 := m.lag if m.lag >= 0.0 else want
	if m.recorded:
		yaw0 = records.yaw_at(m.slot, now)
		l0 = records.lag_at(m.slot, now)
		if m.bot != null:
			# Robots come every 20 ticks or so: their animation's state is worked out in full.
			var anim := MoverRecords.robot_anim(records.state(m.slot))
			c0 = anim.x
			c1 = anim.w
	if fresh and m.oriented:
		yaw0 = m.yaw_goal
	m.recorded = true
	m.lag = l0
	var flags := m.rec_flags | (MoverRecords.HIDDEN if m.fogged else 0)
	# The lag eases as _process_movers eases a node mover's: towards two of the clock's gaps or a gap
	# and its own spacing, while the clock's gap eases to the one the messages say (`p`). The walked
	# distance is kept below a loop of the gait, where it repeats, so the number stays small.
	records.write(m.slot, m.spots, m.ticks, flags, m.height, m.walked, TAU / m.kind.y if m.kind.y > 0.0 else 0.0,
		now, l0, clock.gap, clock.gap_goal(), m.key_gap, clock.ease,
		yaw0, m.yaw_goal, c0, c1, m.kind.x, m.kind.y, m.kind.z, 1.5 if m.key_gap <= 4.0 else 1.0)
	if m.bot != null:
		_place_in_grid(m)
	elif m.creature:
		creatures.placed(m.unit, m.target)
	if _fogging:
		_fog_check(m)


## Where a mover is drawn now: its node, or for one the GPU draws, its record worked out here.
func _drawn_now(m: Mover) -> Vector3:
	if m.slot < 0 or not m.recorded:
		return m.node.position
	return records.position(m.slot)


func _place_in_grid(m: Mover) -> void:
	var cell := Vector2i(floori(m.target.x / GRID), floori(m.target.z / GRID))
	if cell == m.cell:
		return
	_leave_grid(m)
	m.cell = cell
	var list: Dictionary = _robot_grid.get(cell, {})
	if list.is_empty():
		_robot_grid[cell] = list
	list[m] = true


func _leave_grid(m: Mover) -> void:
	var old: Dictionary = _robot_grid.get(m.cell, {})
	old.erase(m)
	if old.is_empty():
		_robot_grid.erase(m.cell)
	m.cell = Vector2i(1 << 30, 0)


func _fog_check(m: Mover) -> void:
	var hide: bool = _fogging and not fog.seen(Vector2(m.target.x, m.target.z))
	if hide != m.fogged:
		m.fogged = hide
		records.set_flag(m.slot, MoverRecords.HIDDEN, hide)
		if m.bot != null:
			m.bot.hidden = hide


## GPU-drawn movers and the remote view's fog: all of them when it comes or goes, else a slice a
## frame (its coverage changes about once a second), besides each one as its position arrives.
func _fog_records(fogging: bool) -> void:
	if fogging != _fogging:
		_fogging = fogging
		for m: Mover in _movers.values():
			if m.slot >= 0:
				_fog_check(m)
		_fog_list.clear()
		_fog_at = 0
		return
	if not fogging:
		return
	if _fog_at >= _fog_list.size():
		_fog_list.clear()
		_fog_at = 0
		for unit in _movers:
			if (_movers[unit] as Mover).slot >= 0:
				_fog_list.append(unit)
	var end := mini(_fog_at + FOG_SLICE, _fog_list.size())
	for i in range(_fog_at, end):
		var m: Mover = _movers.get(_fog_list[i])
		if m != null and m.slot >= 0:
			_fog_check(m)
	_fog_at = end


## Where a mover is at tick `drawn`: between the two positions around it, or a little past the
## newest (up to half a send) when the next one is late. Coarse movers (robots) aren't run on past
## their newest position: they stop there, or the next one comes.
static func _drawn_at(m: Mover, drawn: float) -> Vector3:
	var n := m.ticks.size()
	if n < 2 or drawn <= m.ticks[0]:
		return m.spots[0] if n > 0 else m.target
	for i in range(1, n):
		if drawn <= m.ticks[i]:
			return m.spots[i - 1].lerp(m.spots[i], (drawn - m.ticks[i - 1]) / (m.ticks[i] - m.ticks[i - 1]))
	var span := m.ticks[n - 1] - m.ticks[n - 2]
	var f := minf((drawn - m.ticks[n - 2]) / span, 1.5 if m.key_gap <= 4.0 else 1.0)
	return m.spots[n - 2].lerp(m.spots[n - 1], f)


## Night from 0 to 1 (main.gd, with the sky): locomotives' headlights come on above 0.3.
func set_night(n: float) -> void:
	_beam = Avatar.beam(n)
	for m in _movers.values():
		for h: SpotLight3D in m.headlights:
			h.light_energy = 7.0 * _beam
			h.visible = _beam > 0.01


func _add_headlights(m: Mover) -> void:
	for side in [-0.6, 0.6]:
		var h := SpotLight3D.new()
		h.light_color = Color(1.0, 0.9, 0.9)
		h.spot_range = 30.0
		h.spot_angle = 18.0
		h.spot_attenuation = 0.5
		h.position = Vector3(side, 1.4, -3.2)  # the locomotive's nose (models face north, -Z)
		h.rotation.x = deg_to_rad(-6.0)
		h.light_energy = 7.0 * _beam
		h.visible = _beam > 0.01
		m.node.add_child(h)
		m.headlights.append(h)


## Drops a mover at once (it died) instead of waiting for it to stop showing up.
func remove(unit: int) -> void:
	var m: Mover = _movers.get(unit)
	if m != null:
		creatures.remove(unit, true)  # first: a GPU-drawn one falls where its record has it
		_free(m)
		_movers.erase(unit)
		_node_movers.erase(unit)
		_waiting.erase(unit)
		vehicles.detach(unit)


## Where a mover is drawn, or null.
func position_of(unit: int) -> Variant:
	var m: Mover = _movers.get(unit)
	if m == null:
		return null
	return _drawn_now(m)


## Which way a mover faces as drawn now (radians about up), or 0 for none.
func yaw_of(unit: int) -> float:
	var m: Mover = _movers.get(unit)
	if m == null:
		return 0.0
	if m.slot < 0 or not m.recorded:
		return m.node.rotation.y
	return records.state(m.slot)["yaw"]


## [[unit, node], ...] of the movers of one prototype type (rockets.gd lifts cargo pods and hides
## a launching rocket).
## A mover's node and prototype name (turrets.gd turns vehicles' turrets), or null / "".
func node_of(unit: int) -> Node3D:
	var m: Mover = _movers.get(unit)
	return m.node if m != null else null


func proto_name_of(unit: int) -> String:
	var m: Mover = _movers.get(unit)
	if m == null:
		return ""
	var proto: ProtoDB.EntityProto = protos.entity(m.proto_id)
	return proto.name if proto != null else ""


func units_of_type(type: String) -> Array:
	var out: Array = []
	for unit in _movers:
		var m: Mover = _movers[unit]
		if m.type == type:
			out.append([unit, m.node])
	return out


## True when a flying robot is drawn within `radius` tiles of `from` (on the ground plane).
func robot_near(from: Vector3, radius: float) -> bool:
	for m: Mover in _near(from, radius):
		if m.robot and _within(m, from, radius):
			return true
	return false


## Whether a mover is drawn within `radius` (on the ground plane) of `from`. A GPU-drawn one is first
## ruled out by its newest position (it is drawn within DRAWN_SLACK of it), its record worked out
## only when it may be.
func _within(m: Mover, from: Vector3, radius: float) -> bool:
	var at := m.node.position
	if m.slot >= 0 and m.recorded:
		if Vector2(m.target.x - from.x, m.target.z - from.z).length() > radius + DRAWN_SLACK:
			return false
		at = records.position(m.slot)
	return Vector2(at.x - from.x, at.z - from.z).length() <= radius


## The non-enemy movers in the grid cells within `radius` (on the ground plane) of `from`: every
## roboport and gate asks, and looking through a thousand robots for each was most of anim.gd's time.
## GPU-drawn robots are kept in their cells as their positions arrive (_robot_grid), the few moved
## here put in theirs at most once a frame.
func _near(from: Vector3, radius: float) -> Array:
	var out: Array = []
	var r := radius + DRAWN_SLACK
	for cx in range(floori((from.x - r) / GRID), floori((from.x + r) / GRID) + 1):
		for cz in range(floori((from.z - r) / GRID), floori((from.z + r) / GRID) + 1):
			var robots_here: Dictionary = _robot_grid.get(Vector2i(cx, cz), {})
			if not robots_here.is_empty():
				out.append_array(robots_here.keys())
	if _grid_frame != _frame:
		_grid_frame = _frame
		_grid.clear()
		for m: Mover in _node_movers.values():
			if not m.enemy:
				var cell := Vector2i(floori(m.node.position.x / GRID), floori(m.node.position.z / GRID))
				var list: Array = _grid.get(cell, [])
				if list.is_empty():
					_grid[cell] = list
				list.append(m)
	for cx in range(floori((from.x - radius) / GRID), floori((from.x + radius) / GRID) + 1):
		for cz in range(floori((from.z - radius) / GRID), floori((from.z + radius) / GRID) + 1):
			var list: Array = _grid.get(Vector2i(cx, cz), [])
			if not list.is_empty():
				out.append_array(list)
	return out

## The mover of one of these types nearest a ground point, within `radius` tiles:
## [unit, proto id, fixed position], or [] (player_input.gd opens vehicles and wagons this way).
func pick(point: Vector2, radius: float, types: Array) -> Array:
	var best: Array = []
	var best_distance := radius
	for unit in _movers:
		var m: Mover = _movers[unit]
		if not types.has(m.type):
			continue
		var d := Vector2(m.node.position.x, m.node.position.z).distance_to(point)
		if d <= best_distance:
			best_distance = d
			best = [unit, m.proto_id, m.fixed]
	return best


## The mover of one of these types that the mouse ray (`from`, `dir`, world space) hits first:
## [unit, proto id, fixed position, centre (Vector2 tiles), half size (Vector2), yaw], or [].
## Each mover is hit within its selection box turned by its orientation, as tall as its model
## (and anywhere on the model, where that sticks out of the box), so a click anywhere on a train,
## car, tank or spidertron opens it, not the rail or ground behind it.
func pick_ray(from: Vector3, dir: Vector3, types: Array) -> Array:
	var best: Array = []
	var best_distance := INF
	var wanted := {}
	for t in types:
		wanted[t] = true
	for unit in _movers:
		var m: Mover = _movers[unit]
		if not wanted.has(m.type):
			continue
		var proto: ProtoDB.EntityProto = protos.entity(m.proto_id)
		if proto == null:
			continue
		var box := pick_box(m.node, proto)
		var inv := m.node.global_transform.affine_inverse()
		var hit = box.intersects_ray(inv * from, inv.basis * dir)
		if hit == null:
			continue
		var d := (m.node.global_transform * (hit as Vector3)).distance_to(from)
		if d < best_distance:
			best_distance = d
			var c := proto.center()
			var at := m.node.global_transform * Vector3(c.x, 0.0, c.y)
			best = [unit, m.proto_id, m.fixed, Vector2(at.x, at.z), proto.size() * 0.5, m.node.rotation.y]
	return best


## A mover's box for picking, in its node's space: the selection box (x east, z south when facing
## north), as tall as the model, grown to take in the model where it sticks out.
static func pick_box(node: Node3D, proto: ProtoDB.EntityProto) -> AABB:
	var box := AABB(Vector3(proto.box_min.x, 0.0, proto.box_min.y), Vector3(proto.size().x, Visuals.height_for(proto), proto.size().y))
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			box = box.merge(mi.transform * mi.mesh.get_aabb())
	return box


## Where the nearest enemy within `max_range` of `from` is drawn, or null.
func nearest_enemy(from: Vector3, max_range: float) -> Variant:
	var best = null
	var best_distance := max_range
	for m: Mover in _movers.values():
		if m.enemy:
			if m.slot >= 0 and m.recorded and m.target.distance_to(from) > best_distance + DRAWN_SLACK:
				continue
			var at := _drawn_now(m)
			var d := at.distance_to(from)
			if d <= best_distance:
				best_distance = d
				best = at
	return best


## True when a mover of the player's side (a vehicle, a train, a robot) is within `max_range`
## of `from`: gates open for them (anim.gd).
func friendly_near(from: Vector3, max_range: float) -> bool:
	for m: Mover in _near(from, max_range):
		if _within(m, from, max_range):
			return true
	return false


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_process_movers(delta)
	process_usec = Time.get_ticks_usec() - started


func _process_movers(delta: float) -> void:
	_frame += 1
	if _model_generation != ModelLibrary.generation:
		_model_generation = ModelLibrary.generation
		robots.refresh()
		for unit in _waiting.keys():
			var m: Mover = _movers.get(unit)
			var proto: ProtoDB.EntityProto = protos.entity(m.proto_id) if m != null else null
			if proto == null:
				_waiting.erase(unit)
			elif _model_ready(proto):
				_waiting.erase(unit)
				_dress(unit, m, proto)
	var t := 1.0 - exp(-delta * FOLLOW_RATE)
	var drawn := clock.advance(delta)
	records.frame(clock.tick, clock.rate, delta)
	var fogging: bool = fog != null and fog.hiding()
	_fog_records(fogging)
	var behind := clock.gap * GameClock.DELAY_SENDS
	var now := clock.tick
	var focus := Vector2.INF
	if creatures.target != null:
		focus = Vector2(creatures.target.position.x, creatures.target.position.z)
	for m: Mover in _node_movers.values():
		if m.creature and focus != Vector2.INF and not m.fogged:
			var away := focus.distance_squared_to(Vector2(m.node.position.x, m.node.position.z))
			if away > CREATURE_FAR * CREATURE_FAR:
				if (_frame + m.stagger) % 3 != 0:
					continue
			elif away > CREATURE_NEAR * CREATURE_NEAR and (_frame + m.stagger) % 2 != 0:
				continue
		if fogging or m.fogged:
			var hide: bool = fogging and not fog.seen(Vector2(m.target.x, m.target.z))
			if hide != m.fogged:
				m.fogged = hide
				m.node.visible = not hide
				if m.shadow != null:
					m.shadow.visible = not hide
		# Drawn a step behind its own updates too, so a robot's next position is nearly always in.
		# Eased like the clock's gap: when updates come further apart (the mod's `rate`) the mover
		# learns its new spacing in a few updates, and jumping back that far would step it backwards.
		var want := maxf(behind, m.key_gap + clock.gap)
		if m.lag < 0.0:
			m.lag = want
		else:
			m.lag = move_toward(m.lag, want, delta * clock.rate * (0.5 if want > m.lag else 1.0))
		var lag := m.lag
		var was: Vector3 = m.node.position
		var yaw_was: float = m.node.rotation.y
		m.node.position = _drawn_at(m, now - lag) if drawn >= 0.0 else m.node.position
		if m.on_rails and world != null:
			var goal: float = world.rail_height(Vector2(m.node.position.x, m.node.position.z), m.rail_h)
			m.rail_h = move_toward(m.rail_h, goal, delta * 6.0)
			m.node.position.y = m.rail_h
		m.node.rotation.y = lerp_angle(m.node.rotation.y, m.yaw_goal, t)
		if not m.wheels.is_empty():
			_roll_wheels(m, m.node.position - was, wrapf(m.node.rotation.y - yaw_was, -PI, PI), delta)
		if m.shadow != null:
			m.shadow.position = Vector3(m.node.position.x, 0.03, m.node.position.z) + SHADOW_OFFSET
			m.shadow.rotation.y = m.node.rotation.y
	robots.draw(delta)


## Moves a mover onto its record: the GPU draws it from now on (robots, walking creatures).
func _to_record(m: Mover, kind: Vector4, flags: int) -> void:
	m.slot = records.alloc()
	m.kind = kind
	m.rec_flags = flags
	_node_movers.erase(m.unit)
	_write(m, false)


## Gives a mover its model: biters and the like go to creatures.gd (their node stays empty), the
## rest get the model's mesh and moving parts under their node.
## Rolling stock wears the colour its player gave it (H21), from its record's extra.col.
func _paint(unit: int, m: Mover) -> void:
	if not m.on_rails or world == null:
		return
	var rec = world.entities.get(unit)
	if rec == null or not (rec.extra is Dictionary) or not rec.extra.has("col"):
		return
	var c: Array = rec.extra["col"]
	var paint := Color(int(c[0]) / 255.0, int(c[1]) / 255.0, int(c[2]) / 255.0)
	for mi in m.node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_instance_shader_parameter("f3d_paint", paint)


func _dress(unit: int, m: Mover, proto: ProtoDB.EntityProto) -> void:
	if m.robot and RobotSwarm.handles(proto.name, proto.type):
		m.bot = robots.add(unit, proto.name)
		remove_child(m.node)  # nothing under it to draw or move
		_to_record(m, Vector4(m.bot.phase, 0.0, 0.0, 0.0), robots.flags_for(m.bot))
		robots.place(m.bot, m.slot)
		return
	var creature := CreatureModels.walks(proto.name) and ModelLibrary.mesh_for(proto.name) != null
	if not creature:
		var made := _make_node(proto)
		for child in made.get_children():
			made.remove_child(child)
			m.node.add_child(child)
		made.free()
		m.wheels = _wheels_of(m.node)
	if m.robot:
		m.shadow = _make_shadow(m.node)
		if m.shadow != null:
			add_child(m.shadow)
	if creature:
		m.creature = true
		m.stagger = unit % 6
		# Walking on the GPU from its record where its model can (creatures.gd gait()); else
		# creatures.gd draws it from the node's local transform, moved here every frame. In the tree
		# every move made Godot work out the empty node's global transform: ~4 ms a frame with 500
		# biters attacking on the owner's save. Kept out of the tree, as robots' nodes are.
		remove_child(m.node)
		var gait := creatures.gait(proto.name)
		if gait != Vector2.ZERO:
			var slot := records.alloc()
			creatures.add(unit, proto.name, m.node, slot)
			_to_record_slot(m, slot, Vector4(fposmod(unit * 2.39996, TAU), gait.x, gait.y, 0.0))
		else:
			creatures.add(unit, proto.name, m.node)
	else:
		vehicles.attach(unit, m.node, proto.name)
	_paint(unit, m)


## Whether the mover's model (or its shared one, mover_model) is ready, asking for it if not.
static func _model_ready(proto: ProtoDB.EntityProto) -> bool:
	if not ModelLibrary.ready(proto.name):
		return false
	if ModelLibrary.mesh_for(proto.name) == null:
		var shared := ModelLibrary.mover_model(proto.name)
		if not shared.is_empty():
			return ModelLibrary.ready(str(shared[0]))
	return true


func _make_node(proto: ProtoDB.EntityProto) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var mesh := ModelLibrary.mesh_for(proto.name)
	var shared := ModelLibrary.mover_model(proto.name) if mesh == null else []
	if not shared.is_empty():
		mesh = ModelLibrary.mesh_for(str(shared[0]))
		if mesh != null:
			mi.scale = Vector3.ONE * float(shared[1])
	if mesh != null:
		mi.mesh = mesh
		# Moving parts (a car's or tank's turret, the artillery wagon's cannon) drawn at rest:
		# their meshes are in model space, so they sit where the model has them.
		for part: ModelLibrary.AnimPart in ModelLibrary.parts_for(proto.name):
			var part_mi := MeshInstance3D.new()
			part_mi.mesh = part.mesh
			part_mi.set_meta("part", part)  # vehicle_anim.gd moves the rest
			if part.kind.begins_with("wheel"):
				part_mi.set_meta("wheel", part)
			elif part.kind == "turret_head":
				part_mi.set_meta("turret_head", part)  # turned by turrets.gd
			root.add_child(part_mi)
	else:
		var height := Visuals.height_for(proto)
		mi.mesh = Visuals.box_mesh()
		mi.transform = Visuals.placeholder_transform(proto, Vector2.ZERO, 0, height)
		mi.material_override = _material_for(proto)
	root.add_child(mi)
	return root


## Wheel parts (`anim_wheel_*`) of a mover's model, found under its node.
func _wheels_of(root: Node3D) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child.has_meta("wheel"):
			var part: ModelLibrary.AnimPart = child.get_meta("wheel")
			var radius := maxf(part.mesh.get_aabb().size.y * 0.5, 0.05)
			out.append([child, part, radius, part.kind == "wheel_front"])
	return out


## Wheels roll with the distance driven (backwards when reversing) and a car's front wheels
## steer into its turn.
func _roll_wheels(m: Mover, moved: Vector3, turned: float, delta: float) -> void:
	var forward := -m.node.global_transform.basis.z
	var distance := moved.dot(forward)
	if absf(distance) > 2.0:
		distance = 0.0  # a jump (teleport, new surface)
	m.roll = fposmod(m.roll - distance / 0.36, TAU)
	# Steering from how fast it turns for the distance covered (a 1.66-tile wheelbase).
	var goal := 0.0
	if absf(distance) > 0.0005:
		goal = clampf(turned / distance * 1.66, -0.6, 0.6)
	m.steer = lerpf(m.steer, goal, 1.0 - exp(-delta * 6.0))
	for w in m.wheels:
		var mi: MeshInstance3D = w[0]
		var part: ModelLibrary.AnimPart = w[1]
		var roll := m.roll * 0.36 / float(w[2])
		var turn := Basis(Vector3.RIGHT, roll)
		if w[3]:
			turn = Basis(Vector3.UP, m.steer) * turn
		mi.transform = part.pivot * Transform3D(turn, Vector3.ZERO) * part.pivot.affine_inverse()


## As _to_record, with the slot already handed out (creatures.gd needs it before the first record).
func _to_record_slot(m: Mover, slot: int, kind: Vector4) -> void:
	m.slot = slot
	m.kind = kind
	m.rec_flags = 0
	_node_movers.erase(m.unit)
	_write(m, false)


func _free(m: Mover) -> void:
	if m.slot >= 0:
		records.release(m.slot)
		m.slot = -1
	if m.bot != null:
		_leave_grid(m)
	m.node.queue_free()
	if m.bot != null:
		robots.remove(m.bot)
		m.bot = null
	if m.shadow != null:
		m.shadow.queue_free()


## A robot's drop shadow: its meshes flattened onto the ground in a see-through black. The robot
## itself then casts no lit shadow, so there's one shadow, where Factorio draws it.
func _make_shadow(node: Node3D) -> Node3D:
	var root: Node3D = null
	if _shadow_material == null:
		_shadow_material = StandardMaterial3D.new()
		_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shadow_material.albedo_color = SHADOW_COLOR
		_shadow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if root == null:
			root = Node3D.new()
		var flat := MeshInstance3D.new()
		flat.mesh = mi.mesh
		flat.transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.01, 1.0)), Vector3.ZERO) * mi.transform
		flat.material_override = _shadow_material
		flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(flat)
	return root


func _material_for(proto: ProtoDB.EntityProto) -> Material:
	if not _materials.has(proto.id):
		var color := proto.color
		if ENEMY_TYPES.has(proto.type):
			color = Color(0.75, 0.25, 0.2)  # enemies
		_materials[proto.id] = Visuals.solid_material(color)
	return _materials[proto.id]
