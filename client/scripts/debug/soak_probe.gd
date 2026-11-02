extends Node
## --soak-probe=<out.json>[@minutes]: plays the client for a long session (30 minutes unless said)
## and records how it holds up: every SAMPLE seconds the memory (static, video, textures, buffers),
## objects and nodes, frame times over the last stretch, the bridge's gaps and resyncs and the
## server's UPS. Meanwhile it walks a square round where it joined, opens and closes the inventory,
## the research screen and the map (factorio_ui.gd, as their keys do), and now and then places a
## wooden chest beside the character and mines it again (the commands player_input.gd sends, so
## give the character some chests first). Writes the samples and a summary to the file, prints
## them, and quits. Each sample also has the scripts' time a frame (process_p50, process_p99):
## with the renderer on its own thread its GPU time can't be read without making frames wait.

const SAMPLE := 10.0
const WALK_REPEAT := 0.15
## [Factorio's 16-way direction, seconds]: a square, so it stays round the base it joined at.
const LOOP := [[4, 10.0], [8, 10.0], [12, 10.0], [0, 10.0]]
const WINDOW_EVERY := 45.0
const BUILD_EVERY := 60.0

var main: Node
var out_path := ""
var minutes := 30.0

var _t := 0.0
var _started := false
var _leg := 0
var _leg_left := 0.0
var _walk_timer := 0.0
var _paused := 0.0  # seconds left standing still (building)
var _sample_left := SAMPLE
var _frames: Array[float] = []
var _process_ms: Array[float] = []  # every script's _process together, per frame (Godot's TIME_PROCESS)
var _samples: Array = []
var _last_tick := 0
var _last_tick_msec := 0
var _window_left := WINDOW_EVERY
var _window_step := 0
var _window_open := ""
var _window_close_in := 0.0
var _build_left := BUILD_EVERY
var _chest_at := Vector2.INF
var _chest_mine_in := 0.0
var _chest_seen := false  # the chest placed last showed up in the world
var _builds := 0
var _builds_seen := 0
var _mines_seen := 0
var _first: Dictionary = {}
var _done := false


func _process(delta: float) -> void:
	if _done or not Bridge.world_ready or main.get("world") == null:
		return
	if not _started:
		_started = true
		_last_tick = Bridge.server_tick
		_last_tick_msec = Time.get_ticks_msec()
		print("SOAK started: %.0f minutes" % minutes)
	_t += delta
	_frames.append(delta * 1000.0)
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_walk(delta)
	_windows(delta)
	_build(delta)
	_sample_left -= delta
	if _sample_left <= 0.0:
		_sample_left += SAMPLE
		_sample()
	if _t >= minutes * 60.0:
		_finish()


func _walk(delta: float) -> void:
	if _paused > 0.0:
		_paused -= delta
		return
	if _leg_left <= 0.0:
		_leg = (_leg + 1) % LOOP.size()
		_leg_left = float(LOOP[_leg][1])
	_leg_left -= delta
	_walk_timer -= delta
	if _walk_timer <= 0.0:
		_walk_timer = WALK_REPEAT
		Bridge.send({"t": "walk", "d": int(LOOP[_leg][0])})


func _windows(delta: float) -> void:
	var ui = main.hud.ui
	if _window_open != "":
		_window_close_in -= delta
		if _window_close_in <= 0.0:
			match _window_open:
				"inventory": ui.toggle_inventory()
				"research": ui.open_research(false)
				"map": ui.open_map(false)
			_window_open = ""
		return
	_window_left -= delta
	if _window_left > 0.0:
		return
	_window_left = WINDOW_EVERY
	_window_open = ["inventory", "research", "map"][_window_step % 3]
	_window_step += 1
	_window_close_in = 4.0
	match _window_open:
		"inventory": ui.toggle_inventory()
		"research": ui.open_research(true)
		"map": ui.open_map(true)


func _build(delta: float) -> void:
	var world = main.world
	if _chest_at != Vector2.INF:
		_chest_mine_in -= delta
		var rec = world.pick(_chest_at)
		var is_chest: bool = rec != null and world.protos.entity(rec.proto_id) != null and world.protos.entity(rec.proto_id).name == "wooden-chest"
		if is_chest and not _chest_seen:
			_chest_seen = true
			_builds_seen += 1
		if _chest_mine_in > 0.0:
			return
		if is_chest:
			Bridge.send({"t": "mine", "u": rec.unit, "p": rec.proto_id, "x": rec.fixed.x, "y": rec.fixed.y})
			if _chest_mine_in < -6.0:
				_chest_at = Vector2.INF  # couldn't be mined: go on
		else:
			if _chest_seen:
				_mines_seen += 1
			_chest_at = Vector2.INF
		return
	_build_left -= delta
	if _build_left > 0.0:
		return
	_build_left = BUILD_EVERY
	Bridge.send({"t": "walk", "d": -1})
	_paused = 4.0
	var at: Vector2 = world.focus() + Vector2(2.5, 0.0)
	at = Vector2(floorf(at.x) + 0.5, floorf(at.y) + 0.5)
	Bridge.send({"t": "build", "item": "wooden-chest", "x": int(at.x * 256.0), "y": int(at.y * 256.0), "d": 0})
	_builds += 1
	_chest_at = at
	_chest_mine_in = 2.0
	_chest_seen = false


func _sample() -> void:
	var now := Time.get_ticks_msec()
	var ups := 0.0
	if now > _last_tick_msec:
		ups = (Bridge.server_tick - _last_tick) * 1000.0 / (now - _last_tick_msec)
	_last_tick = Bridge.server_tick
	_last_tick_msec = now
	var f := _frames.duplicate()
	f.sort()
	var over16 := 0
	var over33 := 0
	for ms in f:
		if ms > 16.7:
			over16 += 1
		if ms > 33.3:
			over33 += 1
	var mb := 1048576.0
	var s := {
		"t": snappedf(_t, 0.1),
		"static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / mb, 0.1),
		"video_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / mb, 0.1),
		"texture_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / mb, 0.1),
		"buffer_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / mb, 0.1),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"frames": f.size(),
		"p50": snappedf(f[f.size() / 2], 0.01) if not f.is_empty() else 0.0,
		"p99": snappedf(f[mini(f.size() - 1, int(f.size() * 0.99))], 0.01) if not f.is_empty() else 0.0,
		"worst": snappedf(f[f.size() - 1], 0.01) if not f.is_empty() else 0.0,
		"over16": over16,
		"process_p50": snappedf(_pct(_process_ms, 0.5), 0.01),
		"process_p99": snappedf(_pct(_process_ms, 0.99), 0.01),
		"over33": over33,
		"gaps": int(Bridge.stats.get("gaps", 0)),
		"resyncs": int(Bridge.stats.get("resyncs", 0)),
		"full_resyncs": int(Bridge.stats.get("full_resyncs", 0)),
		"ups": snappedf(ups, 0.1),
		"tick": Bridge.server_tick,
		"entities": main.world.entities.size(),
		"chunks": main.world.chunks.size(),
		"belt_items": main.belt_items.count() if main.belt_items != null else 0,
		"x": snappedf(main.world.focus().x, 0.1),
		"y": snappedf(main.world.focus().y, 0.1),
		"builds": _builds,
		"built_seen": _builds_seen,
		"mined_seen": _mines_seen,
	}
	_frames.clear()
	_process_ms.clear()
	if _first.is_empty():
		_first = s
	_samples.append(s)
	print("SOAK ", JSON.stringify(s))


static func _pct(values: Array[float], q: float) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	return v[mini(v.size() - 1, int(v.size() * q))]


func _finish() -> void:
	_done = true
	Bridge.send({"t": "walk", "d": -1})
	_sample()
	var last: Dictionary = _samples[_samples.size() - 1]
	var all_frames := 0
	var over16 := 0
	var over33 := 0
	var p99s: Array[float] = []
	for s: Dictionary in _samples:
		all_frames += int(s["frames"])
		over16 += int(s["over16"])
		over33 += int(s["over33"])
		p99s.append(float(s["p99"]))
	p99s.sort()
	# After the first few minutes (models, chunks and textures loading) memory should stay flat.
	var settled: Dictionary = _samples[mini(_samples.size() - 1, int(300.0 / SAMPLE))]
	var summary := {
		"minutes": snappedf(_t / 60.0, 0.1),
		"samples": _samples.size(),
		"frames": all_frames,
		"over16_pct": snappedf(100.0 * over16 / maxi(all_frames, 1), 0.01),
		"over33": over33,
		"p99_median": p99s[p99s.size() / 2],
		"worst": _samples.map(func(s: Dictionary) -> float: return s["worst"]).max(),
		"static_mb": [_first["static_mb"], settled["static_mb"], last["static_mb"]],
		"video_mb": [_first["video_mb"], settled["video_mb"], last["video_mb"]],
		"objects": [_first["objects"], settled["objects"], last["objects"]],
		"nodes": [_first["nodes"], settled["nodes"], last["nodes"]],
		"orphans": last["orphans"],
		"gaps": last["gaps"],
		"resyncs": last["resyncs"],
		"full_resyncs": last["full_resyncs"],
		"ups_min": _samples.slice(1).map(func(s: Dictionary) -> float: return s["ups"]).min() if _samples.size() > 1 else 0.0,
		"builds": _builds,
		"built_seen": _builds_seen,
		"mined_seen": _mines_seen,
	}
	print("SOAK SUMMARY ", JSON.stringify(summary))
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"summary": summary, "samples": _samples}, " "))
	preload("res://scripts/menu/exit_guard.gd").arm()
	get_tree().quit()
