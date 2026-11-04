extends RefCounted
## The main thread's sliced work (messages, chunk builds, terrain, models, clutter, far lanes,
## wires, far merging...) asks here how long it may run this frame (grant) and says what it used
## and how much it still has queued (spent).
##
## Each of those systems had a slice of its own (HANDLE_USEC, REBUILD_USEC, FINISH_USEC...),
## sensible alone; but while the character moves every queue has work, so every system spent its
## whole slice every frame and the frame became their sum. With `shared` on they share one
## allowance a frame instead (POOL_*), handed out by priority: a system gets what is left of the
## pool after what the higher ones still to run this frame want (their last use), so the near
## chunks and the character's surroundings come first and far clutter, far belts, wires and
## merging take what remains. A system with work waiting that got nothing for STARVE_FRAMES frames
## gets MIN_SLICE, so everything keeps draining. With `shared` off each system gets its own slice
## as before (and the numbers are still recorded, for --stutter-probe).

## [priority (lower first), the system's own slice in µs (its old constant, and its most from the
## pool), its floor: what it gets whenever it asks, pool or deadline (the near work always moves:
## the old code did at least one message, one build, one chunk freed a frame)].
const SYSTEMS := {
	&"messages": [0, 4000, 1000],  # bridge.gd: messages handled (they feed everything else)
	&"terrain": [1, 3000, 500],  # world.gd: finished terrain meshes put in (holes in the ground)
	&"build": [2, 6000, 1500],  # world.gd: chunks' buildings built, nearest first
	&"models": [3, 4000, 500],  # model_library.gd: models made on workers finished here
	&"unload": [4, 1500, 300],  # world.gd: unloaded chunks taken apart
	&"shadows": [5, 1000, 300],  # world.gd: chunks' shadow tiers set
	&"pick": [5, 1500, 0],  # world.gd: the index of what is under the mouse
	&"decoratives": [6, 3000, 0],  # decoratives.gd: clutter built on workers put in
	&"lanes": [6, 2000, 0],  # belt_lanes.gd: far belt icons put in
	&"wires": [7, 1500, 0],  # wires.gd: chunks' wires drawn again
	&"far_collect": [8, 1000, 0],  # far_chunks.gd: far chunks' entities gathered for merging
	&"far_install": [8, 1500, 0],  # far_chunks.gd: finished merges put in
	&"anim_migrate": [9, 300, 0],  # anim.gd: groups moved onto the newer clock
	&"mover_migrate": [9, 300, 0],  # mover_records.gd: the same for movers' records
}

## The frame the sliced work aims for when no FPS cap says otherwise.
const TARGET_USEC := 16667
## What the frame needs besides the sliced work and the other scripts: the renderer's CPU side, the
## UI canvas, deferred calls (docs/PERFORMANCE-AUDIT.md: about 5 ms on the owner's save).
const RESERVE_USEC := 5000
## The pool is what is left under the target after the frame's other work, within these.
const POOL_MIN := 3000
const POOL_MAX := 6000
## Standing (no work in the higher systems) the pool may grow to this, so a backlog drains fast.
const POOL_IDLE := 10000
## The near systems (priority up to NEAR_PRIORITY) leave this much of the pool to the rest while
## any of those has work waiting, so far clutter, lanes, wires and merging keep moving while the
## character walks (and new chunks always wait).
const NEAR_PRIORITY := 3
const LOW_RESERVE := 1000
const STARVE_FRAMES := 20
const MIN_SLICE := 500
## A slice that ran this far past what it was granted counts as an overrun.
const OVERRUN_SLACK := 1000

static var shared := true
## Forced on or off from the command line (--frame-budget=shared|separate).
static var _arg_checked := false

static var _frame := -1
static var pool := POOL_MAX
## When this frame's scripts started (the first system to ask: Bridge, an autoload, runs first),
## for the deadline: a frame whose other scripts already took most of it (a fight's effects, a
## burst of input) leaves the sliced work only what is left before TARGET_USEC - RESERVE_USEC.
static var _frame_start := 0
## For the UI test: no deadline.
static var test_no_deadline := false
## This frame: system -> µs used, µs granted (the most of the frame's grants), whether it ran.
static var used := {}
static var granted := {}
## The last reported work waiting per system (items, chunks, messages...).
static var queued := {}
## What each system used the last frame it ran with work waiting (for the reservations).
static var _last_use := {}
static var _starved := {}  # system -> frames in a row it was granted nothing with work waiting
static var used_total := 0
## Overruns so far by system (for --stutter-probe and the UI test).
static var overruns := {}
## The other scripts' time a frame (Godot's process time minus the sliced work), smoothed.
static var _other_ema := 6000.0
static var _last_frame_used := 0
## For the UI test: a frame's other work fixed, instead of Godot's measured process time.
static var test_other_usec := -1


static func _check_arg() -> void:
	_arg_checked = true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frame-budget="):
			shared = arg.get_slice("=", 1) != "separate"


## Starts a new frame's books when the frame changed (the first system to ask in a frame).
static func _roll() -> void:
	var f := Engine.get_process_frames()
	if f == _frame:
		return
	if not _arg_checked:
		_check_arg()
	_frame = f
	_frame_start = Time.get_ticks_usec()
	var other := float(test_other_usec) if test_other_usec >= 0 \
		else Performance.get_monitor(Performance.TIME_PROCESS) * 1.0e6 - _last_frame_used
	_other_ema = lerpf(_other_ema, maxf(other, 0.0), 0.1)
	var target := TARGET_USEC
	if Engine.max_fps >= 30 and Engine.max_fps < 60:
		target = int(1.0e6 / Engine.max_fps)
	var busy := false
	for s in queued:
		if int(queued[s]) > 0 and int(SYSTEMS[s][0]) <= 3:
			busy = true
	pool = clampi(int(target - RESERVE_USEC - _other_ema), POOL_MIN, POOL_MAX if busy else POOL_IDLE)
	_last_frame_used = used_total
	used_total = 0
	used.clear()
	granted.clear()


## How long `system` may run now, in µs. 0: nothing this frame (it does nothing, not even one item).
## `scale` multiplies its own slice (messages with a backlog take twice theirs).
static func grant(system: StringName, scale := 1) -> int:
	_roll()
	var own := int(SYSTEMS[system][1]) * scale
	if not shared:
		granted[system] = own
		return own
	var prio := int(SYSTEMS[system][0])
	# Kept for the higher systems that haven't run yet this frame and have work waiting.
	var reserve := 0
	var low_waits := false
	for s in SYSTEMS:
		var p := int(SYSTEMS[s][0])
		if p < prio and not used.has(s) and int(queued.get(s, 0)) > 0:
			reserve += mini(int(_last_use.get(s, SYSTEMS[s][1])), int(SYSTEMS[s][1]))
		elif p > NEAR_PRIORITY and int(queued.get(s, 0)) > 0:
			low_waits = true
	if prio <= NEAR_PRIORITY and low_waits:
		reserve += LOW_RESERVE
	var left := pool - used_total - reserve
	if not test_no_deadline:
		var target := TARGET_USEC if Engine.max_fps < 30 or Engine.max_fps >= 60 else int(1.0e6 / Engine.max_fps)
		left = mini(left, _frame_start + target - RESERVE_USEC - Time.get_ticks_usec() - reserve)
	var g := mini(left, own)
	if g < MIN_SLICE:
		g = 0
		if int(queued.get(system, 0)) > 0:
			var n := int(_starved.get(system, 0)) + 1
			_starved[system] = n
			if n >= STARVE_FRAMES:
				g = MIN_SLICE
	g = maxi(g, int(SYSTEMS[system][2]) * scale)
	if g > 0:
		_starved.erase(system)
	granted[system] = maxi(int(granted.get(system, 0)), g)
	return g


## `system` ran for `usec` µs and has `waiting` left (0 when its queue is empty).
static func spent(system: StringName, usec: int, waiting: int) -> void:
	_roll()
	used[system] = int(used.get(system, 0)) + usec
	used_total += usec
	queued[system] = waiting
	if waiting > 0 or usec > 0:
		_last_use[system] = usec
	var g := int(granted.get(system, int(SYSTEMS[system][1])))
	if usec > g + OVERRUN_SLACK:
		overruns[system] = int(overruns.get(system, 0)) + 1


## Only the work waiting changed (a system with nothing to do this frame).
static func waiting(system: StringName, n: int) -> void:
	queued[system] = n


## This frame's books for --stutter-probe: {system: [µs used, µs granted, waiting]}, and "pool".
static func snapshot() -> Dictionary:
	var out := {"pool": pool}
	for s in SYSTEMS:
		var u := int(used.get(s, 0))
		var q := int(queued.get(s, 0))
		if u > 0 or q > 0:
			out[s] = [u, int(granted.get(s, 0)), q]
	return out


## For tests: everything back to its start.
static func reset() -> void:
	_frame = -1
	used.clear()
	granted.clear()
	queued.clear()
	_last_use.clear()
	_starved.clear()
	overruns.clear()
	used_total = 0
	_last_frame_used = 0
	_other_ema = 6000.0
	pool = POOL_MAX
