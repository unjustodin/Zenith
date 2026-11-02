extends RefCounted
## Movers drawn on the GPU: flying robots (robot_swarm.gd) and walking creatures (creatures.gd).
## Each has a record in one float texture (f3d_movers), written by movers.gd only when a new position
## of it arrives: its last four positions and their game ticks, its lag behind the clock, its facing
## and so on (mover_records.gdshaderinc has the layout).
## Every frame only the clock goes to the GPU (f3d_mover_clock, and the texture when records
## changed); the shaders work out where each mover is drawn, as movers.gd did per mover per frame
## (_drawn_at): with ~500 biters or robots in view that was 2-4 ms of script a frame.
##
## The clock is the game's tick as movers.gd draws it (game_clock.gd). A float32 holds a tick count
## to about a millisecond only up to a few hours of game, so the shader gets two clocks, the ticks
## since the latest even and odd EPOCH began, and each record says which one its ticks are on: a
## record written in epoch k stays good through epoch k + 1, and frame() moves records not written
## since onto the newer clock, a few a frame, before the older clock starts again.
##
## state() works out a record on the CPU the same way as the shader, for what still needs a mover's
## place (following one, picking, tags, sparks, a creature that starts to attack) and for tests.

const TEXELS := 8  # texels a record
const ROW := 1024  # texels a row of the texture
const FLOATS := TEXELS * 4
const PER_ROW := ROW / TEXELS
const EPOCH := 16384.0  # clock ticks
## Seconds before the shader's seconds clock wraps: a whole number of creatures' idle gait loops
## (0.15 a second: creatures.gd IDLE_LOOPS).
const IDLE_PERIOD := 200.0
const MIGRATE_USEC := 300
const TURN_RATE := 15.0  # movers.gd FOLLOW_RATE

## Record flags (texel 3, x).
const ODD := 1  # on the odd epoch's clock
const HIDDEN := 2  # the remote view's fog hides it
const BUILDER := 4  # a construction robot: works when it stands still
const CARGO := 8  # a robot carrying cargo
const ANIMATED := 16  # a robot that bobs, swings its thrusters and so on (not combat robots)

## Robots (robot_swarm.gd and the shader): flying at full speed, standing before work, arms out.
const ROBOT_FULL_SPEED := 2.5
const ROBOT_WORK_STILL := 0.3
const ROBOT_ARMS_REACH := 0.6

var data := PackedFloat32Array()
## Per slot: the clock ticks (absolute, float64) of A, B, C, D and of the write, and the epoch it
## was written in: what moving it onto another clock needs.
var _ticks := PackedFloat64Array()
var _epochs := PackedInt32Array()
var _live := PackedByteArray()
var _free: Array[int] = []
var _rows := 0
var _used := 0  # slots handed out at some point (the highest + 1)
var live := 0
var _dirty := false
var _image: Image
var texture: ImageTexture
## The clock now (movers.gd's GameClock tick), the game's ticks a second, and the shader's seconds.
var tick := 0.0
var rate := 60.0
var seconds := 0.0
var _epoch := 0
var _migrate: Array[int] = []
## Which store's texture the shaders read (a second one is the main menu's background).
static var _active: WeakRef
## Microseconds the last frame() took, and records written since the store was made (probes).
var frame_usec := 0
var writes := 0


func alloc() -> int:
	var slot: int
	if not _free.is_empty():
		slot = _free.pop_back()
	else:
		slot = _used
		_used += 1
		if _used > _rows * PER_ROW:
			_grow()
	_live[slot] = 1
	live += 1
	# Hidden until its first record is written.
	data[slot * FLOATS + 12] = float(HIDDEN)
	_dirty = true
	return slot


func release(slot: int) -> void:
	if slot < 0 or slot >= _used or _live[slot] == 0:
		return
	_live[slot] = 0
	live -= 1
	_free.append(slot)
	# Hidden, so an instance still pointing at it this frame draws nothing.
	var o := slot * FLOATS + 12
	data[o] = float(int(data[o]) | HIDDEN)
	_dirty = true


func _grow() -> void:
	_rows = maxi(8, _rows * 2)
	data.resize(_rows * ROW * 4)
	_ticks.resize(_rows * PER_ROW * 5)
	_epochs.resize(_rows * PER_ROW)
	_live.resize(_rows * PER_ROW)
	_image = null  # a new texture of the new size (frame())
	_dirty = true


## The base the clock of `parity` counts from in epoch `k`: the latest epoch of that parity.
static func _base(parity: int, k: int) -> float:
	return (k if posmod(k, 2) == parity else k - 1) * EPOCH


func _epoch_of(t: float) -> int:
	return floori(t / EPOCH)


## Writes a mover's record from its history (`spots` and `ticks`, oldest first: the last four, the
## oldest repeated when there are fewer), its height, the distance it walked to its newest position
## (kept below `loop`, where its gait repeats, when that is above 0), the clock tick now, its lag
## now, the clock's gap now and the gap it eases to (at `ease` ticks a tick growing), its own ticks
## between positions, its facing now and the facing it turns to, two values carried from now
## (c0, c1) and its kind's three (k0-k2), and how far past the last point it runs on (`ext`, of the
## last step). Called for every position that arrives, so it does no more than write.
func write(slot: int, spots: Array[Vector3], ticks: Array[float], flags: int, height: float, walked: float, loop: float,
		now: float, lag0: float, gap0: float, gap_goal: float, key_gap: float, ease: float, yaw0: float, yaw_goal: float,
		c0: float, c1: float, k0: float, k1: float, k2: float, ext: float) -> void:
	# On the clock frame() last set (a record from just past an epoch's start is still good, and is
	# moved on with the rest), unless the clock jumped (the first message, a save loaded).
	if absi(_epoch_of(now) - _epoch) > 1:
		_set_epoch(_epoch_of(now))
	var k := _epoch
	var parity := posmod(k, 2)
	var base := _base(parity, k)
	var o := slot * FLOATS
	var to := slot * 5
	var d := data
	var n := ticks.size()
	var first := maxi(0, n - 4)
	var length := 0.0
	var last := Vector3.ZERO
	for i in 4:
		var j := maxi(first, n - 4 + i)
		var p: Vector3 = spots[j]
		d[o + i * 2] = p.x
		d[o + i * 2 + 1] = p.z
		d[o + 8 + i] = ticks[j] - base
		_ticks[to + i] = ticks[j]
		if i > 0:
			length += Vector2(p.x - last.x, p.z - last.z).length()
		last = p
	walked -= length
	if loop > 0.0:
		walked = fposmod(walked, loop)
	d[o + 12] = float((flags & ~ODD) | (ODD if parity == 1 else 0))
	d[o + 13] = height
	d[o + 14] = walked
	d[o + 15] = now - base
	d[o + 16] = yaw0
	d[o + 17] = yaw_goal
	d[o + 18] = c0
	d[o + 19] = c1
	d[o + 20] = k0
	d[o + 21] = k1
	d[o + 22] = k2
	d[o + 23] = ext
	d[o + 24] = lag0
	d[o + 25] = gap0
	d[o + 26] = gap_goal
	d[o + 27] = key_gap
	d[o + 28] = ease
	_ticks[to + 4] = now
	_epochs[slot] = k
	_dirty = true
	writes += 1


func flags_of(slot: int) -> int:
	return int(data[slot * FLOATS + 12]) & ~ODD


## Sets or clears flags (HIDDEN, CARGO) without writing the rest.
func set_flag(slot: int, flag: int, on: bool) -> void:
	var o := slot * FLOATS + 12
	var was := int(data[o])
	var now := (was | flag) if on else (was & ~flag)
	if now != was:
		data[o] = float(now)
		_dirty = true


## The clock tick at which a record's mover is drawn at its last point, as its lag is now (absolute).
func last_tick(slot: int) -> float:
	return _ticks[slot * 5 + 3] + _lag(slot, tick)


## A record's lag at clock tick `t` (absolute), as the shader works it out (mover_lag).
func _lag(slot: int, t: float) -> float:
	return _lag_after(slot * FLOATS, maxf(t - _ticks[slot * 5 + 4], 0.0))


## The lag `ticks` clock ticks after the record at `o` was written: eased towards what the mover
## wants (two of the clock's gaps, or a gap and its own spacing) while the clock's gap eases too.
func _lag_after(o: int, ticks: float) -> float:
	var d := data
	var l0: float = d[o + 24]
	var g0: float = d[o + 25]
	var gg: float = d[o + 26]
	var gap := move_toward(g0, gg, ticks * (d[o + 28] if gg > g0 else 1.0))
	var want := maxf(2.0 * gap, d[o + 27] + gap)
	return minf(l0 + 0.5 * ticks, want) if want >= l0 else maxf(l0 - ticks, want)


## A mover's lag at clock tick `t` (absolute) as its record has it (movers.gd carries it on).
func lag_at(slot: int, t: float) -> float:
	return _lag(slot, t)


## A mover's facing at clock tick `t` (absolute) as its record has it (as state()["yaw"]).
func yaw_at(slot: int, t: float) -> float:
	var o := slot * FLOATS
	var since := maxf(t - _ticks[slot * 5 + 4], 0.0) / maxf(rate, 1.0)
	return data[o + 17] + wrapf(data[o + 16] - data[o + 17], -PI, PI) * exp(-TURN_RATE * since)


## Once a frame: the clock, records moved onto a newer clock, and the texture if records changed.
func frame(clock_tick: float, ticks_a_second: float, delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	tick = clock_tick
	rate = ticks_a_second
	seconds = fposmod(seconds + delta, IDLE_PERIOD)
	var k := _epoch_of(maxf(tick, 0.0))
	if k != _epoch:
		_set_epoch(k)
	if not _migrate.is_empty():
		_move_some()
	if live > 0:
		var active: RefCounted = _active.get_ref() if _active != null else null
		if active != self:
			_active = weakref(self)
			if texture != null:
				RenderingServer.global_shader_parameter_set(&"f3d_movers", texture)
		var c := clocks()
		RenderingServer.global_shader_parameter_set(&"f3d_mover_clock", Vector4(c.x, c.y, rate, seconds))
		if _dirty:
			_upload()
	frame_usec = Time.get_ticks_usec() - t0


func _set_epoch(k: int) -> void:
	_epoch = k
	_migrate.clear()
	for slot in _used:
		if _live[slot] != 0 and _epochs[slot] != k:
			_migrate.append(slot)


## The two clocks now: the tick since the latest even and odd epoch began.
func clocks() -> Vector2:
	var k := _epoch
	return Vector2(tick - _base(0, k), tick - _base(1, k))


## Moves records still on an older clock onto the newest one, within MIGRATE_USEC.
func _move_some() -> void:
	var t0 := Time.get_ticks_usec()
	var k := _epoch
	var parity := posmod(k, 2)
	var base := _base(parity, k)
	while not _migrate.is_empty() and Time.get_ticks_usec() - t0 < MIGRATE_USEC:
		var slot: int = _migrate.pop_back()
		if _live[slot] == 0 or _epochs[slot] == k:
			continue
		var o := slot * FLOATS
		var to := slot * 5
		for i in 4:
			data[o + 8 + i] = _ticks[to + i] - base
		data[o + 15] = _ticks[to + 4] - base
		data[o + 12] = float((int(data[o + 12]) & ~ODD) | (ODD if parity == 1 else 0))
		_epochs[slot] = k
		_dirty = true


func _upload() -> void:
	_dirty = false
	var bytes := data.to_byte_array()
	if _image == null:
		_image = Image.create_from_data(ROW, _rows, false, Image.FORMAT_RGBAF, bytes)
		# A texture of a new size is a new texture: the shaders' global is pointed at it (rare: the
		# store doubles when it fills).
		texture = ImageTexture.create_from_image(_image)
		RenderingServer.global_shader_parameter_set(&"f3d_movers", texture)
		_active = weakref(self)
		return
	_image.set_data(ROW, _rows, false, Image.FORMAT_RGBAF, bytes)
	texture.update(_image)


## A record worked out as the shader does it, at the clock now: {pos, yaw, walked, speed, still,
## since, flags, carried (Vector4), kind (Vector4)}. Speeds in tiles a second, times in seconds.
func state(slot: int) -> Dictionary:
	var o := slot * FLOATS
	var d := data
	var flags := int(d[o + 12])
	var c := clocks()
	# As the shader sees it: float32 numbers.
	var now := _f32(c.y if flags & ODD else c.x)
	var r := maxf(rate, 1.0)
	var after := maxf(now - d[o + 15], 0.0)
	var lag := _lag_after(o, after)
	var drawn := now - lag
	var pace := 1.0 - (lag - _lag_after(o, maxf(after - 1.0, 0.0)))
	var at := Vector2(d[o], d[o + 1])
	var walked := 0.0
	var speed := 0.0
	var still := 0.0
	if drawn > d[o + 8]:
		var found := false
		for i in 3:
			var a := Vector2(d[o + i * 2], d[o + i * 2 + 1])
			var b := Vector2(d[o + i * 2 + 2], d[o + i * 2 + 3])
			var len := a.distance_to(b)
			var span: float = d[o + 9 + i] - d[o + 8 + i]
			if not found and drawn <= d[o + 9 + i]:
				var f: float = (drawn - d[o + 8 + i]) / span if span > 1e-4 else 1.0
				at = a.lerp(b, f)
				speed = len / span if span > 1e-4 else 0.0
				walked += len * f
				found = true
			elif not found:
				walked += len
		if not found:
			var c2 := Vector2(d[o + 4], d[o + 5])
			var d3 := Vector2(d[o + 6], d[o + 7])
			var span: float = d[o + 11] - d[o + 10]
			var len := c2.distance_to(d3)
			var ext: float = d[o + 23]
			if span > 1e-4:
				var f: float = (drawn - d[o + 10]) / span
				if f < ext:
					speed = len / span
				else:
					still = drawn - (d[o + 10] + ext * span)
					f = ext
				at = c2.lerp(d3, f)
				walked += len * (f - 1.0)
			else:
				at = d3
				still = drawn - d[o + 11]
	var since := maxf(now - d[o + 15], 0.0) / r
	var turn := wrapf(d[o + 16] - d[o + 17], -PI, PI)
	var average := walked / maxf(drawn - d[o + 8], 0.5) * pace * r if drawn > d[o + 8] else 0.0
	return {"pos": Vector3(at.x, d[o + 13], at.y), "yaw": d[o + 17] + turn * exp(-TURN_RATE * since),
		"walked": d[o + 14] + walked, "speed": speed * pace * r, "average": average, "still": still / r, "since": since, "flags": flags,
		"carried": Vector4(d[o + 16], d[o + 17], d[o + 18], d[o + 19]), "kind": Vector4(d[o + 20], d[o + 21], d[o + 22], d[o + 23])}


## Only where a record's mover is drawn now (as state()["pos"], with less to do).
func position(slot: int) -> Vector3:
	var o := slot * FLOATS
	var d := data
	var c := clocks()
	var now := _f32(c.y if int(d[o + 12]) & ODD else c.x)
	var drawn := now - _lag_after(o, maxf(now - d[o + 15], 0.0))
	if drawn <= d[o + 8]:
		return Vector3(d[o], d[o + 13], d[o + 1])
	for i in 3:
		if drawn <= d[o + 9 + i]:
			var span: float = d[o + 9 + i] - d[o + 8 + i]
			var f: float = (drawn - d[o + 8 + i]) / span if span > 1e-4 else 1.0
			return Vector3(lerpf(d[o + i * 2], d[o + i * 2 + 2], f), d[o + 13], lerpf(d[o + i * 2 + 1], d[o + i * 2 + 3], f))
	var span: float = d[o + 11] - d[o + 10]
	if span <= 1e-4:
		return Vector3(d[o + 6], d[o + 13], d[o + 7])
	var f := minf((drawn - d[o + 10]) / span, d[o + 23])
	return Vector3(lerpf(d[o + 4], d[o + 6], f), d[o + 13], lerpf(d[o + 5], d[o + 7], f))


static func _f32(x: float) -> float:
	var a := PackedFloat32Array([x])
	return a[0]


## A robot's animation now from its state, as the robot shader works it out: Vector4(how much it
## flies, its bob's phase, flags (1 cargo, 2 working), its arms' reach).
static func robot_anim(st: Dictionary) -> Vector4:
	var flags: int = st["flags"]
	if not flags & ANIMATED:
		return Vector4.ZERO
	var carried: Vector4 = st["carried"]
	var since: float = st["since"]
	var amount := move_toward(carried.z, clampf(float(st["speed"]) / ROBOT_FULL_SPEED, 0.0, 1.0), 3.0 * since)
	var working: bool = flags & BUILDER and float(st["still"]) > ROBOT_WORK_STILL
	var reach := 0.0
	if working:
		var began := maxf(since - (float(st["still"]) - ROBOT_WORK_STILL), 0.0)
		reach = move_toward(move_toward(carried.w, 0.0, 3.0 * began), ROBOT_ARMS_REACH, 3.0 * (since - began))
	else:
		reach = move_toward(carried.w, 0.0, 3.0 * since)
	return Vector4(amount, (st["kind"] as Vector4).x, (1.0 if flags & CARGO else 0.0) + (2.0 if working else 0.0), reach)


## A walking creature's gait phase and strength now, as the shader works them out: the strength from
## its speed over its record's path so far (from A to where it is drawn: a few ticks, a smoothing
## of its speed as creatures.gd eased it).
func creature_gait(st: Dictionary) -> Vector2:
	var kind: Vector4 = st["kind"]
	var phase := kind.x + kind.y * float(st["walked"]) + 0.15 * TAU * seconds
	return Vector2(phase, clampf(float(st["average"]) / 1.5, 0.0, 1.0))
