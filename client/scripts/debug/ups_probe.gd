extends Node
## --ups-probe=<out.json>[@stand|walk][@variant,variant...]: what each of the client's knobs buys in
## the game's UPS. After WARMUP seconds it steps through VARIANTS (one knob lowered at a time, set
## straight on the layers, never in the settings), SETTLE + MEASURE seconds each, and records the
## game's ticks per real second over each measure window (as the F4 line measures it), the client's
## frame times, and the wall-clock window, so a tools/ups_probe.py --profile log can be matched to
## it. With @walk the character walks east and west in LEG-second legs the whole time. Writes the
## file, prints a table and quits. The UPS governor is switched off for the run.
## @governed=<seconds> instead leaves the governor on and prints a line a second for that long: the
## game's UPS (the governor's measure), its level and what it holds back, and the frame rate.

const WARMUP := 30.0
const SETTLE := 12.0
const MEASURE := 24.0
const LEG := 6.0

## name -> {knob: value}; knobs: updates (belt items sent moving), far (belt item distance, tiles), entity
## (focus radius, tiles), view (chunks), fps (Engine.max_fps), scale (3D render scale).
const VARIANTS := {
	"base": {},
	"updates 3000": {"updates": 3000},
	"updates 1500": {"updates": 1500},
	"far 64": {"far": 64},
	"far 0": {"far": 0},
	"entity 128": {"entity": 128},
	"entity 64": {"entity": 64},
	"view 7": {"view": 7},
	"view 5": {"view": 5},
	"fps 30": {"fps": 30},
	"scale 0.5": {"scale": 0.5},
	"floors": {"updates": 1500, "far": 0, "entity": 64, "view": 5},
	"base again": {},
}

var main  # main.gd
var out_path := ""

var _walk := false
var _names: Array = VARIANTS.keys()
var _warm := 0.0
var _index := -1
var _time := 0.0
var _start_tick := 0
var _start_msec := 0
var _start_unix := 0.0
var _frames: Array = []
var _results: Array = []
var _leg_time := 0.0
var _leg_dir := 4
var _walk_timer := 0.0
var _base := {}
var _governed := 0.0
var _log_timer := 0.0
var _log_time := 0.0


func _ready() -> void:
	var spec := out_path.split("@")
	out_path = spec[0]
	for part in spec.slice(1):
		if part == "walk":
			_walk = true
		elif part.begins_with("governed="):
			_governed = float(part.get_slice("=", 1))
		elif part != "stand":
			_names = ["base"] + Array(part.split(","))


func _process(delta: float) -> void:
	if main == null or not Bridge.world_ready:
		return
	if _walk:
		_walk_some(delta)
	if _governed > 0.0:
		_log_some(delta)
		return
	main.ups_governor.enabled = false
	if _index < 0:
		_warm += delta
		if _warm >= WARMUP:
			_base = {"updates": main.belt_lanes.cap, "far": main.belt_lanes.distance, "entity": main.world.focus_radius,
				"view": main.world.view_radius, "fps": Engine.max_fps, "scale": get_viewport().scaling_3d_scale}
			_next()
		return
	_time += delta
	if _time >= SETTLE:
		if _start_msec == 0:
			_start_msec = Time.get_ticks_msec()
			_start_tick = Bridge.server_tick
			_start_unix = Time.get_unix_time_from_system()
			_frames.clear()
		_frames.append(delta * 1000.0)
	if _time >= SETTLE + MEASURE:
		var secs := (Time.get_ticks_msec() - _start_msec) / 1000.0
		var sorted := _frames.duplicate()
		sorted.sort()
		var r := {"variant": _names[_index], "ups": snappedf((Bridge.server_tick - _start_tick) / secs, 0.01),
			"from": _start_unix, "to": Time.get_unix_time_from_system(),
			"frame_p50": snappedf(sorted[sorted.size() / 2], 0.01), "frame_p99": snappedf(sorted[int(sorted.size() * 0.99)], 0.01),
			"fps": snappedf(sorted.size() / secs, 0.1)}
		_results.append(r)
		print("ups-probe %s" % JSON.stringify(r))
		_next()


func _next() -> void:
	_index += 1
	_time = 0.0
	_start_msec = 0
	if _index >= _names.size():
		_finish()
		return
	var v: Dictionary = _base.duplicate()
	v.merge(VARIANTS.get(_names[_index], {}), true)
	main.belt_lanes.cap = main.belt_lanes.cap_of(float(v["updates"])) if float(v["updates"]) > 0.0 else 0
	main.belt_lanes.distance = int(v["far"])
	main.belt_lanes.near = mini(main.belt_lanes.distance, main.belt_lanes.MOVING_MAX)
	main.world.set_focus_radius(int(v["entity"]))
	main.world.view_radius = int(v["view"])
	Engine.max_fps = int(v["fps"])
	get_viewport().scaling_3d_scale = float(v["scale"])


func _log_some(delta: float) -> void:
	_log_time += delta
	_log_timer += delta
	if _log_timer < 1.0:
		return
	_log_timer = 0.0
	var g = main.ups_governor
	print("ups-gov %s" % JSON.stringify({"t": snappedf(_log_time, 0.1), "unix": Time.get_unix_time_from_system(), "ups": snappedf(g.ups, 0.01),
		"level": g.level, "held": g.status(), "fps": Engine.get_frames_per_second(), "entity": main.world.focus_radius,
		"updates": main.belt_lanes.cap, "far": main.belt_lanes.distance, "view": main.world.view_radius}))
	if _log_time >= _governed:
		set_process(false)
		Bridge.send({"t": "walk", "d": -1})
		get_tree().quit()


func _walk_some(delta: float) -> void:
	_leg_time += delta
	if _leg_time >= LEG:
		_leg_time = 0.0
		_leg_dir = 12 if _leg_dir == 4 else 4
	_walk_timer -= delta
	if _walk_timer <= 0.0:
		Bridge.send({"t": "walk", "d": _leg_dir})
		_walk_timer = 0.15


func _finish() -> void:
	set_process(false)
	Bridge.send({"t": "walk", "d": -1})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"walk": _walk, "results": _results}, "\t"))
	for r in _results:
		print("%-12s %6.2f UPS  frame p50 %5.2f p99 %6.2f ms" % [r["variant"], r["ups"], r["frame_p50"], r["frame_p99"]])
	get_tree().quit()
