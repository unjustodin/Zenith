extends Node
## --robot-probe=<out.json>[@seconds]: stands still and records what each frame costs with the
## movers in view (the frame rate drops with many robots): frame time, the movers' and their
## animations' script time (movers.gd, vehicle_anim.gd), message handling, the renderer's draw calls,
## objects and primitives, its CPU and GPU time. Waits until the mover count has held (within a
## few: trains come and go) for 3 s with every model made, or 60 s at most, then records, writes a
## summary to the file, prints it and quits. Run it windowed (headless has no GPU work to measure),
## with the mock's --robots N.

const SETTLE := 3.0
const DEFAULT_SECONDS := 10.0
const MAX_WAIT := 60.0

var movers: Node  # movers.gd
var out_path := ""

var _seconds := DEFAULT_SECONDS
var _settled := 0.0
var _waited := 0.0
var _count := -1
var _left := 0.0
var _last_usec := 0
var _handle_before := 0
## [ms, movers ms, vehicles ms, handle ms, draw calls, objects, primitives, render cpu ms, gpu ms,
## all _process ms, physics ms, robot_swarm.gd's draw ms (part of movers ms)]
var _frames: Array = []
var _done := false


func _ready() -> void:
	process_priority = 1000  # last: the counters hold this frame's work
	var spec := out_path.split("@")
	out_path = spec[0]
	if spec.size() > 1:
		_seconds = float(spec[1])
	_left = _seconds
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _process(delta: float) -> void:
	if _done or movers == null or not Bridge.world_ready:
		return
	var now := Time.get_ticks_usec()
	var handle := int(Bridge.stats.get("handle_usec", 0))
	_waited += delta
	if _settled < SETTLE and _waited < MAX_WAIT:
		var n: int = movers.count()
		# Trains and cars come and go at the edge of the area: a few either way is settled.
		if absi(n - _count) > maxi(3, _count / 50) or n == 0 or movers.waiting() > 0:
			_count = n
			_settled = 0.0
		else:
			_settled += delta
		_last_usec = now
		_handle_before = handle
		return
	var vp := get_viewport().get_viewport_rid()
	_frames.append([(now - _last_usec) / 1000.0, movers.process_usec / 1000.0, movers.vehicles.process_usec / 1000.0,
		(handle - _handle_before) / 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		movers.robots.draw_usec / 1000.0])
	_last_usec = now
	_handle_before = handle
	_left -= delta
	if _left <= 0.0:
		_finish()


static func _median(frames: Array, k: int) -> float:
	var a: Array = frames.map(func(r: Array) -> float: return float(r[k]))
	a.sort()
	return a[a.size() / 2] if not a.is_empty() else 0.0


static func _p99(frames: Array, k: int) -> float:
	var a: Array = frames.map(func(r: Array) -> float: return float(r[k]))
	a.sort()
	return a[clampi(int(ceil(0.99 * a.size())) - 1, 0, a.size() - 1)] if not a.is_empty() else 0.0


func _finish() -> void:
	_done = true
	var names := ["frame_ms", "movers_ms", "vehicles_ms", "handle_ms", "draw_calls", "objects", "primitives", "render_cpu_ms", "gpu_ms", "process_ms", "physics_ms", "swarm_ms"]
	var summary := {"movers": movers.count(), "frames": _frames.size(), "fps": _frames.size() / _seconds}
	for k in names.size():
		summary[names[k]] = snappedf(_median(_frames, k), 0.01)
		summary[names[k] + "_p99"] = snappedf(_p99(_frames, k), 0.01)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"summary": summary, "frames": _frames}))
		f.close()
	print("ROBOTS ", JSON.stringify(summary))
	get_tree().quit()
