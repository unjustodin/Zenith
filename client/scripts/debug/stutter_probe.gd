extends Node
## --stutter-probe=<out.json>[@route]: walks the character along a fixed route and records every
## frame's length and what ran in it on the main thread (stutters while moving on big worlds):
## models made for their first appearance (model_library.gd), level-of-detail work (model_lods.gd),
## chunk entity rebuilds, terrain applied, messages handled, the renderer's own CPU and GPU time,
## all scripts' _process together, and which of the game's nodes took it (markers between them).
## The first WARMUP seconds after the world is ready are kept apart as "load" (most models appear
## then); then it walks, writes the frames and a summary to the file, prints the summary and quits.
## Run it windowed: the costs that stall the GPU don't show headless. Against the mock's --busy base
## the default route walks from the start south through the factory, east along it and back north.

const Settings := preload("res://scripts/menu/settings.gd")
const WARMUP := 15.0
## --probe-warmup=<s>: a longer warm-up (a big save at long distances takes a while to load); with
## --probe-variants the variants also wait until no chunk is left to build (or 3 minutes).
var _warmup: float = float(Settings.arg_value("--probe-warmup=")) if Settings.has_arg("--probe-warmup=") else WARMUP
## --probe-shots=<dir>: with --probe-variants, a screenshot of each variant once it has settled.
var _shots_dir: String = Settings.arg_value("--probe-shots=") if Settings.has_arg("--probe-shots=") else ""
## [direction (Factorio's 16-way, -1 stands still), seconds]
const ROUTES := {
	"busy": [[8, 28.0], [4, 12.0], [0, 20.0]],
	"short": [[8, 6.0]],
	# Two laps of a loop round where it joined, at whatever speed the character runs: on the owner's
	# save its exoskeletons take it about 30 tiles a second (0.51 a tick), so each lap crosses
	# 150-300 tiles of the base each way and new chunks come in all the time ("While moving",
	# docs/PERFORMANCE-AUDIT.md).
	"fast": [[4, 5.0], [8, 3.0], [12, 10.0], [0, 6.0], [4, 10.0], [8, 3.0], [12, 5.0],
		[4, 5.0], [8, 3.0], [12, 10.0], [0, 6.0], [4, 10.0], [8, 3.0], [12, 5.0]],
	"stand": [[-1, 30.0]],  # stands where it joined: the steady cost of a busy view
	"stand75": [[-1, 75.0]],  # the same for longer (docs/PERFORMANCE-AUDIT.md: averages over a minute or more)
	"fight": [[-1, 150.0]],  # stands while tools/attack_wave.py sends enemies at a defended wall
	"variants": [[-1, 7200.0]],  # stands until --probe-variants has gone through its list
}
const WALK_REPEAT := 0.15

var world  # world.gd
var out_path := ""

var _route: Array = []
var _leg := 0
var _leg_left := 0.0
var _walk_timer := 0.0
var _warm := 0.0
var _last_usec := 0
## Per frame: [ms, model ms, lods ms, rebuild ms, terrain ms, handle ms, render cpu ms, gpu ms,
## models made, x, y, tick, all _process ms, physics ms, {node: _process ms}, GPU pipelines compiled,
## draw calls, primitives, {what is alive: count} (fights: creatures, corpses, effect cards, sounds),
## {phase: ms}, [view and shadow draws and primitives], and with --gpu-profile {render step: GPU ms},
## {render step: CPU ms} (_pass_times)]
var _frames: Array = []
var _load_frames: Array = []  # the same, for the first WARMUP seconds after the world is ready
var _before := {}
var _names_seen := 0
var _done := false
## --probe-variants (with a standing route): instead of one long stand, steps through VARIANTS of
## the render settings, VARIANT_SETTLE + VARIANT_MEASURE seconds each, and prints each one's frame
## and GPU time (its price, against "base"). Pass --probe-render-times with the separate thread.
var _variants := "--probe-variants" in OS.get_cmdline_user_args() or Settings.has_arg("--probe-variants=")
## --probe-variants=a,b: only these (and "base" first).
var _variant_list: Array = VARIANTS if not Settings.has_arg("--probe-variants=") else ["base"] + Array(Settings.arg_value("--probe-variants=").split(","))
var _variant := -1
var _variant_time := 0.0
var _variant_frames: Array = []
var _variant_results: Array = []
var _hidden: Array = []  # nodes a variant hid, shown again after it
var VARIANT_SETTLE := 3.0
var VARIANT_MEASURE := 8.0
## --probe-ab=<n>: each variant n times, each time between two of "base", so a slow drift of the
## scene or the graphics card's clocks cancels out (tools: compare each to the bases beside it).
## --probe-timing=<settle>,<measure>: seconds per step.
const VARIANTS := ["base", "ssao off", "ssao low", "shadows off", "shadow atlas 4096", "shadow distance 100",
	"shadow 2 splits", "hard shadows", "lod low", "decoratives off", "trees hidden", "walls hidden", "belts hidden", "terrain hidden", "entities hidden", "base again"]
## The render settings as they were before the first variant, which each variant goes back to.
var _base := {}
var _uncast: Array = []  # nodes a "... no shadow" variant stopped casting, cast again after it
var _shot := false  # this variant's screenshot (--probe-shots) is taken


## With the render thread on its own (project setting thread_model 2) the renderer's measured times
## can only be read by waiting for that thread, which would make every frame wait: they're left
## out there (-1), unless --probe-render-times asks for them anyway.
var _times: bool = ProjectSettings.get_setting("rendering/driver/threads/thread_model", 1) != 2 or "--probe-render-times" in OS.get_cmdline_user_args()


func _render_cpu(vp: RID) -> float:
	return RenderingServer.viewport_get_measured_render_time_cpu(vp) if _times else -1.0


func _render_gpu(vp: RID) -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(vp) if _times else -1.0


## Notes when the frame's _process calls start (first of all nodes), so the probe (last) knows how
## long every script's _process took together.
class FrameStart extends Node:
	var at := 0

	func _ready() -> void:
		process_priority = -1000

	func _process(_delta: float) -> void:
		at = Time.get_ticks_usec()


var _start := FrameStart.new()
## Markers after each child of the game's node and of main (tree order is process order at one
## priority): the time between two is the subtree's _process. [marker, the subtree's name]
var _marks: Array = []


## When this probe's _process ended last frame and when the renderer started and finished drawing
## after it (RenderingServer's frame_pre_draw and frame_post_draw): the time from the end of
## _process to the draw is deferred calls and freed nodes, the draw is the renderer's whole frame
## on the main thread (not only the viewport's measured time), the rest is presenting and input.
var _end_usec := 0
var _pre_usec := 0
var _post_usec := 0
var _world_prof := {}
var _nodes := 0
var _merged: Array = []


func _ready() -> void:
	process_priority = 1000  # last in the frame: the counters hold this frame's work
	if Settings.has_arg("--probe-timing="):
		var t := Settings.arg_value("--probe-timing=").split(",")
		VARIANT_SETTLE = float(t[0])
		VARIANT_MEASURE = float(t[1])
	if Settings.has_arg("--probe-ab="):
		var n := int(Settings.arg_value("--probe-ab="))
		var list: Array = ["base"]
		for v in _variant_list.slice(1):
			for i in n:
				list.append_array([v, "base"])
		_variant_list = list
	add_child(_start)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre_usec = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _post_usec = Time.get_ticks_usec())
	_add_marks.call_deferred()


func _add_marks() -> void:
	world.track_latency = true
	var game: Node = world.get_parent()
	for parent in [game.get_parent(), game]:
		for child in parent.get_children():
			if child is FrameStart:
				continue
			var mark := FrameStart.new()
			mark.name = "StutterMark"
			parent.add_child(mark)
			parent.move_child(mark, child.get_index() + 1)
			mark.process_priority = 0
			_marks.append([mark, str(child.name)])
	for child in world.get_children():
		if child.name == "Animator":
			var before := FrameStart.new()
			world.add_child(before)
			world.move_child(before, child.get_index())
			before.process_priority = 0
			_marks.append([before, "World itself"])  # world.gd and its children before the animator
			var mark := FrameStart.new()
			world.add_child(mark)
			world.move_child(mark, child.get_index() + 1)
			mark.process_priority = 0
			_marks.append([mark, "Animator"])  # world.gd's own _process runs before its children
	# Scripts that run after every priority-0 node (fx.gd at 2; sun_shadows.gd and vehicle_anim.gd
	# at 10): marks between the priorities split them from the rest.
	for p in [[1, "rest at priority 0"], [3, "fx.gd (priority 2)"], [999, "sun_shadows.gd, vehicle_anim.gd (priority 10)"]]:
		var late := FrameStart.new()
		late.name = "StutterMarkLate"
		add_child(late)
		late.process_priority = int(p[0])
		_marks.append([late, str(p[1])])
	var spec := out_path.split("@")
	out_path = spec[0]
	_route = ROUTES.get(spec[1] if spec.size() > 1 else "busy", ROUTES["busy"])
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), _times)


func _counters() -> Dictionary:
	const ModelLibrary := preload("res://scripts/world/model_library.gd")
	const ModelLods := preload("res://scripts/world/model_lods.gd")
	var pipelines := 0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		pipelines += int(Performance.get_monitor(m))
	return {"pipelines": pipelines, "model": ModelLibrary.load_usec, "lods": ModelLods.main_usec, "rebuild": world.entity_build_usec,
		"terrain": world.terrain_build_usec, "handle": int(Bridge.stats.get("handle_usec", 0)), "loads": ModelLibrary.loads}


func _process(delta: float) -> void:
	if _done or world == null or not Bridge.world_ready:
		return
	var now := Time.get_ticks_usec()
	var c := _counters()
	if _before.is_empty():
		_last_usec = now
		_before = c
		return
	var walking := _warm >= _warmup and (not _variants or _settled() or _warm > 180.0)
	if walking and _frames.is_empty():
		world.drawn_latency.clear()  # what appears while it walks, not while it joined
	if not walking:
		_warm += delta
	elif _leg >= _route.size():
		_finish()
		return
	else:
		if _leg_left <= 0.0:
			_leg_left = float(_route[_leg][1])
			_walk_timer = 0.0
		_walk_timer -= delta
		if _walk_timer <= 0.0:
			Bridge.send({"t": "walk", "d": int(_route[_leg][0])})
			_walk_timer = WALK_REPEAT
		_leg_left -= delta
		if _leg_left <= 0.0:
			_leg += 1
			if _leg >= _route.size():
				Bridge.send({"t": "walk", "d": -1})
	if walking and _variants:
		_step_variant(delta)
	var vp := get_viewport().get_viewport_rid()
	var f: Vector2 = world.focus()
	(_frames if walking else _load_frames).append([(now - _last_usec) / 1000.0, (c["model"] - _before["model"]) / 1000.0,
		(c["lods"] - _before["lods"]) / 1000.0, (c["rebuild"] - _before["rebuild"]) / 1000.0,
		(c["terrain"] - _before["terrain"]) / 1000.0, (c["handle"] - _before["handle"]) / 1000.0,
		_render_cpu(vp), _render_gpu(vp),
		c["loads"] - _before["loads"], snappedf(f.x, 0.1), snappedf(f.y, 0.1), Bridge.server_tick,
		(now - _start.at) / 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, _segments(),
		c["pipelines"] - _before["pipelines"], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), _alive(), _phases(), _passes(vp)] + _pass_times())
	_last_usec = now
	_before = c
	_end_usec = Time.get_ticks_usec()


## Draw calls and primitives of the view and of the shadow passes: [view draws, view prims,
## shadow draws, shadow prims].
func _passes(vp: RID) -> Array:
	return [RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)]


## With Godot started with --gpu-profile the renderer marks every step of its frame (Godot's own
## visual profiler reads the same marks): [{step: GPU ms}, {step: render CPU ms}], the step named by
## the mark that starts it, summed over the frame's viewports; [] without the flag. The marks read
## are the last frame the GPU finished, a frame or two behind this one.
var _rd: RenderingDevice
var _ts_frame := -1


func _pass_times() -> Array:
	if _rd == null:
		_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return []
	var n := _rd.get_captured_timestamps_count()
	if n <= 2 or _rd.get_captured_timestamps_frame() == _ts_frame:
		return []
	_ts_frame = _rd.get_captured_timestamps_frame()
	var gpu := {}
	var cpu := {}
	for i in range(1, n):
		var step := _rd.get_captured_timestamp_name(i - 1)
		if step.begins_with("vp_"):
			step = step.get_slice("_", 0) + "_" + step.get_slice("_", 1)
		var g := (_rd.get_captured_timestamp_gpu_time(i) - _rd.get_captured_timestamp_gpu_time(i - 1)) / 1.0e6  # ns
		var c := (_rd.get_captured_timestamp_cpu_time(i) - _rd.get_captured_timestamp_cpu_time(i - 1)) / 1.0e3  # µs
		gpu[step] = snappedf(float(gpu.get(step, 0.0)) + g, 0.001)
		cpu[step] = snappedf(float(cpu.get(step, 0.0)) + c, 0.001)
	return [gpu, cpu]


## Whether the world has nothing left to build: chunks, their MultiMeshes, terrain.
func _settled() -> bool:
	return world._dirty.is_empty() and world._pending.is_empty() and world.terrain_queue_size() == 0 \
		and not preload("res://scripts/world/model_lods.gd").busy()


## Where the last frame's time outside _process went, and world.gd's parts and chunk_view.gd's
## counters this frame: {name: ms or count}.
func _phases() -> Dictionary:
	var out := {}
	if _end_usec > 0 and _pre_usec > _end_usec and _post_usec > _pre_usec:
		out["flush"] = snappedf((_pre_usec - _end_usec) / 1000.0, 0.01)
		out["draw"] = snappedf((_post_usec - _pre_usec) / 1000.0, 0.01)
		out["present"] = snappedf((_start.at - _post_usec) / 1000.0, 0.01)
	for k in world.prof:
		var ms := (int(world.prof[k]) - int(_world_prof.get(k, 0))) / 1000.0
		if ms > 0.05:
			out["w_" + str(k)] = snappedf(ms, 0.01)
	_world_prof = world.prof.duplicate()
	# What waits: chunks to build, chunks with MultiMeshes still to add (and how many), terrain.
	out["q_dirty"] = world._dirty.size()
	out["q_pending"] = world._pending.size()
	var wants := 0
	for c in world._pending:
		var cv = world.chunks.get(c)
		if cv != null:
			wants += cv.pending.size()
	out["q_wants"] = wants
	out["q_terrain"] = world.terrain_queue_size()
	# Chunk streaming (world.gd): chunks wanted round the focus but not asked for yet, chunks
	# waiting to be freed, and (when world.gd has them) the queues of its spread-out work.
	out["q_unasked"] = maxi(world._wanted.size() - world._subscribed.size(), 0)
	out["q_free"] = world._unloaded.size()
	if world.has_method("stream_queues"):
		var queues: Dictionary = world.stream_queues()
		for k in queues:
			out["q_" + str(k)] = queues[k]
	out["q_messages"] = Bridge.waiting_count()
	out["q_undrawn"] = world.undrawn()
	out["q_near_undrawn"] = world.near_undrawn
	# The sliced systems' books this frame (frame_budget.gd): {system: [µs used, µs granted, waiting]}.
	out["fb"] = preload("res://scripts/world/frame_budget.gd").snapshot()
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	out["nodes_delta"] = nodes - _nodes
	_nodes = nodes
	var counters: Dictionary = preload("res://scripts/world/chunk_view.gd").counters
	for k in counters:
		if int(counters[k]) != 0:
			out["c_" + str(k)] = counters[k]
	counters.clear()
	return out


## What a fight leaves alive this frame: enemies drawn, corpses, effect cards, sounds, nodes.
func _alive() -> Dictionary:
	var game: Node = world.get_parent()
	var out := {"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT))}
	if _variants and _variant >= 0 and _variant < _variant_list.size():
		out["variant"] = str(_variant_list[_variant])  # tools/perf_audit.py --variants splits the frames by it
		out["settled"] = _variant_time > VARIANT_SETTLE * (4.0 if str(_variant_list[_variant]).begins_with("preset") else 1.0)
	# Far chunks merged and their triangles (far_chunks.gd), looked at once a second.
	if Engine.get_process_frames() % 60 == 0 or _merged.is_empty():
		_merged = world.far_chunks.census()
	out["merged"] = _merged[0]
	out["merged_tris"] = _merged[1]
	var movers: Node = game.get_node_or_null("Movers")
	if movers != null:
		out["movers"] = movers.count()
		out["creatures"] = movers.creatures.count()
		out["corpses"] = movers.creatures.corpse_count()
	var fx: Node = game.get_parent().get("fx") if game.get_parent() != null else null
	if fx != null:
		out["cards"] = fx.sprites.count()
		out["sounds"] = fx.sfx.busy_shots()
		out["flying"] = fx.weapons.flying_count()
		out["ground"] = fx.weapons.ground_count()
		out["beams"] = fx.weapons.beam_count()
		out["ms_sprites"] = int(fx.sprites.get("process_usec") if fx.sprites.get("process_usec") != null else 0) / 1000.0
		out["ms_weapons"] = int(fx.weapons.get("process_usec") if fx.weapons.get("process_usec") != null else 0) / 1000.0
	if movers != null:
		out["ms_creatures"] = int(movers.creatures.get("process_usec") if movers.creatures.get("process_usec") != null else 0) / 1000.0
		# Movers by kind (movers.gd's own loop, robots' buffers, vehicles' rigs) and how many attack.
		out["ms_movers"] = movers.process_usec / 1000.0
		out["ms_robots"] = movers.robots.draw_usec / 1000.0
		out["ms_vehicles"] = movers.vehicles.process_usec / 1000.0
		out["robots"] = movers.robots.count()
		out["attacking"] = int(movers.creatures.get("attacking") if movers.creatures.get("attacking") != null else 0)
		var parts = movers.creatures.get("parts_usec")
		if parts is Dictionary:
			for k in parts:
				out["ms_cr_" + str(k)] = int(parts[k]) / 1000.0
		out["cr_layers"] = int(movers.creatures.get("layers_seen") if movers.creatures.get("layers_seen") != null else 0)
	return out


func _step_variant(delta: float) -> void:
	_variant_time += delta
	# A preset changes the view distance: chunks come and go for a while first.
	var settle := VARIANT_SETTLE * (4.0 if _variant >= 0 and str(_variant_list[_variant]).begins_with("preset") else 1.0)
	# The screenshot reads the frame back from the GPU, a slow frame: taken before measuring.
	if _variant >= 0 and _variant_time > settle - 0.5 and not _shot and _shots_dir != "":
		_shot = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shots_dir.path_join("%02d-%s.png" % [_variant, str(_variant_list[_variant]).replace(" ", "_").replace("+", "_").replace("/", "_")]))
	if _variant >= 0 and _variant_time > settle and _frames.size() > 0:
		_variant_frames.append(_frames[_frames.size() - 1])
	if _variant >= 0 and _variant_time < settle + VARIANT_MEASURE:
		return
	if _variant >= 0:
		var s := summarize(_variant_frames)
		var col := func(k: int) -> Array: return _variant_frames.filter(func(r: Array) -> bool: return r.size() > 20).map(func(r: Array) -> float: return float(r[20][k]))
		_variant_results.append([_variant_list[_variant], s["p50"], s["p99"], s["gpu_p50"], s["render_cpu_p50"], s["draw_calls_p50"], s["primitives_p50"],
			pct(col.call(0), 0.5), pct(col.call(1), 0.5), pct(col.call(2), 0.5), pct(col.call(3), 0.5), world.shadow_casters])
		_set_variant(_variant_list[_variant], false)
	_variant += 1
	if _variant == 0:
		_census()
	_variant_time = 0.0
	_variant_frames = []
	_shot = false
	if _variant >= _variant_list.size():
		for r in _variant_results:
			print("VARIANT %-34s frame p50 %5.1f p99 %5.1f ms | gpu p50 %5.2f ms | render cpu p50 %5.2f ms | draw calls %d | primitives %d | view draws %d prims %d | shadow draws %d prims %d | casting chunks %d" % r)
		_leg = _route.size()
		return
	_set_variant(_variant_list[_variant], true)


## The models in the loaded chunks by triangles drawn at full detail (instances x triangles).
func _census() -> void:
	const ModelLibrary := preload("res://scripts/world/model_library.gd")
	var names := {}
	for model in ModelLibrary._cache:
		if ModelLibrary._cache[model] != null:
			names[ModelLibrary._cache[model]] = model
	var by := {}
	var planes := get_viewport().get_camera_3d().get_frustum()
	for cv in world.chunks.values():
		var box := AABB(Vector3(cv.coord.x * 32.0, 0.0, cv.coord.y * 32.0), Vector3(32, 16, 32))
		var seen := true
		for p: Plane in planes:
			var inner := Vector3(box.position.x if p.normal.x > 0.0 else box.end.x, box.position.y if p.normal.y > 0.0 else box.end.y,
				box.position.z if p.normal.z > 0.0 else box.end.z)
			seen = seen and not p.is_point_over(inner)
		if not seen:
			continue
		for mmi in cv._instances:
			if mmi.multimesh == null or mmi.multimesh.mesh == null or not mmi.visible:
				continue
			var mesh: Mesh = mmi.multimesh.mesh
			var tris := 0
			for i in mesh.get_surface_count():
				var arrays: Array = preload("res://scripts/world/model_lods.gd").arrays_of(mesh, i) if mesh.has_meta(&"f3d_arrays") else []
				if not arrays.is_empty():
					var idx = arrays[Mesh.ARRAY_INDEX]
					tris += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var key := str(names.get(mesh, ""))
			if key == "":
				var mat: Material = mmi.material_override if mmi.material_override != null else mesh.surface_get_material(0)
				key = "%s/%s/%s" % [mesh.get_class(), mesh.resource_name, mat.resource_name if mat != null else "-"]
			var e: Array = by.get(key, [0, tris])
			e[0] += mmi.multimesh.visible_instance_count if mmi.multimesh.visible_instance_count >= 0 else mmi.multimesh.instance_count
			by[key] = e
	var rows := by.keys().map(func(k) -> Array: return [k, by[k][0], by[k][1], by[k][0] * by[k][1]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[3] > b[3])
	for r in rows.slice(0, 25):
		print("CENSUS (chunks in view) %-34s instances %6d x %6d triangles = %9d" % r)


## The sun's shadow atlas and soft filter as sun_shadows.gd set them (Godot can't be asked).
func _atlas_now() -> int:
	var fitter: Node = world.get_parent().get_node_or_null("SunShadows")
	if fitter == null:
		return Settings.shadow_size()
	return int(fitter.LEGACY_ATLAS[fitter.quality]) if fitter.legacy else int(fitter.spec["atlas"])


func _soft_now() -> int:
	var fitter: Node = world.get_parent().get_node_or_null("SunShadows")
	if fitter == null or fitter.legacy:
		return RenderingServer.SHADOW_QUALITY_SOFT_LOW
	return int(fitter.spec["filter"])


func _set_variant(name: String, on: bool) -> void:
	var sun: DirectionalLight3D = world.sun
	var env: Environment = get_viewport().find_world_3d().environment
	if _base.is_empty():
		_base = {"distance": sun.directional_shadow_max_distance, "mode": sun.directional_shadow_mode, "blend": sun.directional_shadow_blend_splits,
			"split1": sun.directional_shadow_split_1, "split2": sun.directional_shadow_split_2, "split3": sun.directional_shadow_split_3,
			"fade": sun.directional_shadow_fade_start, "ssao": env.ssao_enabled, "atlas": _atlas_now(),
			"shadows": sun.shadow_enabled, "soft": _soft_now(),
			"lod": str(Settings.get_value("graphics", "lod_quality"))}
	var fitter: Node = world.get_parent().get_node_or_null("SunShadows")
	# The variants that set the sun's shadows themselves: the fitting (sun_shadows.gd) waits meanwhile.
	for prefix in ["shadow distance ", "shadow 2 splits", "shadow 4 splits", "splits ", "blend splits", "no blend splits"]:
		if name.begins_with(prefix) and fitter != null:
			fitter.set_process(not on and not fitter.legacy)
	# "a+b": both at once.
	if name.contains("+"):
		var parts := Array(name.split("+"))
		if not on:
			parts.reverse()
		for part: String in parts:
			_set_variant(part.strip_edges(), on)
		return
	# "fit [quality] key=value ...": sun_shadows.gd fitting the shadows to the view with that
	# quality's settings (high when none is named), these changed.
	if name.begins_with("fit"):
		if fitter == null:
			return
		if on:
			var words := Array(name.split(" ", false)).slice(1)
			var q: String = words.pop_front() if not words.is_empty() and fitter.QUALITY.has(words[0]) else "high"
			var s: Dictionary = (fitter.QUALITY[q] as Dictionary).duplicate()
			for kv: String in words:
				s[kv.get_slice("=", 0)] = float(kv.get_slice("=", 1))
			fitter.apply_spec(s)
			fitter.set_process(true)
		else:
			fitter.apply_quality(fitter.quality)
		return
	# "legacy render": the shadows and levels of detail as they were before sun_shadows.gd
	# (--legacy-render for a whole run).
	if name == "legacy render":
		const ModelLods := preload("res://scripts/world/model_lods.gd")
		if fitter == null:
			return
		if on:
			fitter.apply_legacy()
			get_viewport().mesh_lod_threshold = float(ModelLods.LEGACY_THRESHOLDS.get(str(_base["lod"]), 2.0))
		else:
			fitter.apply_quality(fitter.quality)
			ModelLods.apply_quality(str(_base["lod"]), get_viewport())
		return
	# The Level of detail setting's two parts on their own: the view's pixels of error, and the far
	# shadow stand-ins' lod_bias.
	if name.begins_with("lod threshold "):
		if not _base.has("threshold"):
			_base["threshold"] = get_viewport().mesh_lod_threshold
		get_viewport().mesh_lod_threshold = float(name.get_slice(" ", 2)) if on else float(_base["threshold"])
		return
	if name.begins_with("lod bias "):
		const ModelLods := preload("res://scripts/world/model_lods.gd")
		if not _base.has("bias"):
			_base["bias"] = ModelLods.lod_bias
		ModelLods.lod_bias = float(name.get_slice(" ", 2)) if on else float(_base["bias"])
		return
	if name.begins_with("shadow distance "):
		sun.directional_shadow_max_distance = float(name.get_slice(" ", 2)) if on else float(_base["distance"])
		return
	if name.begins_with("shadow atlas "):
		RenderingServer.directional_shadow_atlas_set_size(int(name.get_slice(" ", 2)) if on else int(_base["atlas"]), true)
		return
	if name.begins_with("splits "):  # "splits 0.05/0.15/0.4": the split distances as fractions
		var f := name.get_slice(" ", 1).split("/")
		sun.directional_shadow_split_1 = float(f[0]) if on else float(_base["split1"])
		sun.directional_shadow_split_2 = float(f[1]) if on and f.size() > 1 else float(_base["split2"])
		sun.directional_shadow_split_3 = float(f[2]) if on and f.size() > 2 else float(_base["split3"])
		return
	if name.begins_with("soft "):  # soft hard / very_low / low / medium / high / ultra
		var q := ["hard", "very_low", "low", "medium", "high", "ultra"].find(name.get_slice(" ", 1))
		RenderingServer.directional_soft_shadow_filter_set_quality(q if on else int(_base["soft"]))
		return
	if name.ends_with(" no shadow"):
		if not on:
			for node in _uncast:
				if is_instance_valid(node):
					(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_uncast.clear()
			if name.begins_with("terrain") or name.begins_with("far chunks"):
				world._shadow_key = []
			return
		var game: Node = world.get_parent()
		var roots: Array = []
		match name.trim_suffix(" no shadow"):
			"arms": roots = [game.get_node_or_null("InserterArms")]
			"items": roots = [game.get_node_or_null("BeltItems"), game.get_node_or_null("GroundItems")]
			"wires": roots = [game.get_node_or_null("Wires")]
			"movers": roots = [game.get_node_or_null("Movers")]
			"terrain":
				for cv in world.chunks.values():
					if cv._terrain != null and cv._terrain.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
						cv._terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						_uncast.append(cv._terrain)
			"far chunks":
				for cv in world.chunks.values():
					if cv.shadow_tier == preload("res://scripts/world/chunk_view.gd").SHADOWS_FAR:
						cv.set_shadow_tier(preload("res://scripts/world/chunk_view.gd").SHADOWS_NONE)
		for root in roots:
			if root == null:
				continue
			for node in root.find_children("*", "GeometryInstance3D", true, false):
				if (node as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
					(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					_uncast.append(node)
		print("VARIANT %s: %d nodes stop casting" % [name, _uncast.size()])
		return
	match name:
		"ssao off":
			env.ssao_enabled = not on
		"ssao low":
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW if on else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
		"ssao very low":
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_VERY_LOW if on else RenderingServer.ENV_SSAO_QUALITY_MEDIUM, true, 0.5, 2, 50.0, 300.0)
		"ssao full size":
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_MEDIUM, not on, 0.5, 2, 50.0, 300.0)
		"ssao on":
			env.ssao_enabled = on or bool(_base["ssao"])
		"shadow 4 splits":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if on else int(_base["mode"])
		"blend splits":
			sun.directional_shadow_blend_splits = on or bool(_base["blend"])
		"no blend splits":
			sun.directional_shadow_blend_splits = not on and bool(_base["blend"])
		"lod high":
			Settings.set_value("graphics", "lod_quality", "high" if on else str(_base["lod"]), false)
		"shadows off":
			sun.shadow_enabled = not on and bool(_base["shadows"])
		"shadow atlas 4096":
			RenderingServer.directional_shadow_atlas_set_size(4096 if on else Settings.shadow_size(), true)
		"shadow distance 100":
			sun.directional_shadow_max_distance = 100.0 if on else 150.0
		"shadow 2 splits":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if on else int(_base["mode"])
		"hard shadows":
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD if on else int(_base["soft"]))
		# Godot's depth pre-pass, where nothing forces it (SSAO does). Measures nothing useful: in a
		# running game it stops the terrain and models being drawn at all (seen in 4.7.2); set
		# rendering/driver/depth_prepass/enable in an override.cfg for a whole run instead.
		"prepass off":
			ProjectSettings.set_setting("rendering/driver/depth_prepass/enable", not on)
		"render scale 0.5":  # half the pixels each way: what scales with pixels, not vertices
			get_viewport().scaling_3d_scale = 0.5 if on else 1.0
		"fxaa off":
			get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if on else Viewport.SCREEN_SPACE_AA_FXAA
		"clouds off":
			Settings.set_value("graphics", "clouds", not on, false)
		"minimap hidden", "alerts hidden", "quickbar hidden", "entity info hidden":
			var script_name: String = {"minimap hidden": "minimap.gd", "alerts hidden": "alerts.gd", "quickbar hidden": "quickbar.gd",
				"entity info hidden": "entity_info.gd"}[name]
			for c in get_tree().root.find_children("*", "CanvasItem", true, false):
				var sc: Script = c.get_script()
				if sc != null and sc.resource_path.get_file() == script_name:
					(c as CanvasItem).visible = not on
		"ui hidden":
			for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
				(c as CanvasLayer).visible = not on
		"lod low":
			Settings.set_value("graphics", "lod_quality", "low" if on else str(_base["lod"]), false)
		"decoratives off":
			Settings.set_value("graphics", "decoratives", not on, false)
		"tree shadows off":
			const ModelLibrary := preload("res://scripts/world/model_library.gd")
			var tree_meshes := {}
			for model in ModelLibrary._cache:
				var m = ModelLibrary._cache[model]
				if m is Mesh and (str(model).begins_with("tree-") or str(model).begins_with("dead-") or str(model).begins_with("dry-")):
					tree_meshes[m] = true
			for cv in world.chunks.values():
				for pair in cv._shadow_pairs:
					if tree_meshes.has((pair[0] as MultiMeshInstance3D).multimesh.mesh):
						(pair[1] as MultiMeshInstance3D).visible = not on
				for mmi in cv._instances:
					if mmi.multimesh != null and tree_meshes.has(mmi.multimesh.mesh) and on:
						mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if not on:
				for cv in world.chunks.values():
					cv._apply_shadows()
		"preset low", "preset medium", "preset ultra":
			Settings.apply_preset(name.trim_prefix("preset ") if on else "high")
		"trees hidden", "walls hidden", "belts hidden", "all belts hidden", "inserters hidden", "terrain hidden", "entities hidden":
			const ModelLibrary := preload("res://scripts/world/model_library.gd")
			if not on:
				for node in _hidden:
					if is_instance_valid(node):
						(node as GeometryInstance3D).visible = true
				_hidden.clear()
				return
			var trees := {}
			var prefixes: Array = {"trees hidden": ["tree-", "dead-", "dry-"], "walls hidden": ["stone-wall"], "belts hidden": ["transport-belt"],
				"all belts hidden": ["transport-belt", "fast-transport-belt", "express-transport-belt", "turbo-transport-belt", "underground-belt",
					"fast-underground-belt", "express-underground-belt", "turbo-underground-belt"],
				"inserters hidden": ["inserter", "burner-inserter", "fast-inserter", "long-handed-inserter", "bulk-inserter", "stack-inserter"]}.get(name, [])
			for model in ModelLibrary._cache:
				for prefix: String in prefixes:
					if str(model).begins_with(prefix):
						trees[ModelLibrary._cache[model]] = true
			for cv in world.chunks.values():
				var nodes: Array = []
				if name == "terrain hidden":
					nodes = [cv._terrain] if cv._terrain != null else []
				else:
					for mmi in cv._instances:
						if name == "entities hidden" or (mmi.multimesh != null and trees.has(mmi.multimesh.mesh)):
							nodes.append(mmi)
				for node: GeometryInstance3D in nodes:
					if node.visible:
						node.visible = false
						_hidden.append(node)
			print("VARIANT %s hides %d nodes (%d meshes matched)" % [name, _hidden.size(), trees.size()])


## This frame's subtrees taking over a millisecond: {name: ms}. A marker sits right after its
## subtree, so the time from the marker before it (in time) to it is that subtree's; "before" is
## everything up to the first marker (autoloads such as Bridge, and main itself).
## --probe-fine: subtrees down to 0.01 ms (an average frame's breakdown), not only those over 0.1.
var SEGMENT_MIN_MS := 0.005 if "--probe-fine" in OS.get_cmdline_user_args() else 0.1


func _segments() -> Dictionary:
	var order := _marks.filter(func(e: Array) -> bool: return (e[0] as FrameStart).at >= _start.at)
	order.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as FrameStart).at < (b[0] as FrameStart).at)
	var out := {}
	var last := _start.at
	var label := "before"
	for entry in order:
		var mark: FrameStart = entry[0]
		var ms := (mark.at - last) / 1000.0
		if ms > SEGMENT_MIN_MS:
			var key: String = label if label == "before" else str(entry[1])
			out[key] = snappedf(float(out.get(key, 0.0)) + ms, 0.01 if SEGMENT_MIN_MS < 0.1 else 0.1)
		label = ""
		last = mark.at
	return out


static func pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(ceil(p * s.size())) - 1, 0, s.size() - 1)]


## The summary of a run's frames (also used by the UI test on made-up frames).
static func summarize(frames: Array) -> Dictionary:
	var ms: Array = frames.map(func(r: Array) -> float: return r[0])
	var over16 := 0
	var over33 := 0
	var over50 := 0
	var totals := [0.0, 0.0, 0.0, 0.0, 0.0]
	var slow_totals := [0.0, 0.0, 0.0, 0.0, 0.0]
	for r: Array in frames:
		for k in 5:
			totals[k] += r[k + 1]
		if r[0] > 16.7:
			over16 += 1
		if r[0] > 33.0:
			over33 += 1
			for k in 5:
				slow_totals[k] += r[k + 1]
		if r[0] > 50.0:
			over50 += 1
	var segments := {}
	for r: Array in frames:
		if r[0] > 33.0 and r.size() > 14:
			for k in (r[14] as Dictionary):
				segments[k] = snappedf(float(segments.get(k, 0.0)) + float(r[14][k]), 0.1)
	var worst := frames.duplicate()
	worst.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var col := func(k: int) -> Array: return frames.filter(func(r: Array) -> bool: return r.size() > k and float(r[k]) >= 0.0).map(func(r: Array) -> float: return float(r[k]))
	return {"frames": frames.size(), "p50": pct(ms, 0.5), "p99": pct(ms, 0.99), "worst": pct(ms, 1.0),
		"over16": over16, "over33": over33, "over50": over50,
		"render_cpu_p50": snappedf(pct(col.call(6), 0.5), 0.01), "gpu_p50": snappedf(pct(col.call(7), 0.5), 0.01),
		"gpu_p99": snappedf(pct(col.call(7), 0.99), 0.01), "process_p50": snappedf(pct(col.call(12), 0.5), 0.01),
		"process_p99": snappedf(pct(col.call(12), 0.99), 0.01), "draw_calls_p50": pct(col.call(16), 0.5),
		"primitives_p50": pct(col.call(17), 0.5),
		"main_ms_total": {"models": totals[0], "lods": totals[1], "rebuild": totals[2], "terrain": totals[3], "handle": totals[4]},
		"main_ms_in_frames_over_33": {"models": slow_totals[0], "lods": slow_totals[1], "rebuild": slow_totals[2], "terrain": slow_totals[3], "handle": slow_totals[4]},
		"segments_in_frames_over_33": segments, "worst_frames": worst.slice(0, 15)}


## Every 5 seconds of the run: frame and script times, draw calls and the most of each thing alive,
## so a fight's cost shows as it builds up and after.
static func _print_windows(frames: Array) -> void:
	var t := 0.0
	var window: Array = []
	for r: Array in frames:
		window.append(r)
		t += float(r[0]) / 1000.0
		if t < 5.0 and r != frames.back():
			continue
		var most := {}
		for w: Array in window:
			if w.size() > 18:
				for k: String in (w[18] as Dictionary):
					if k.begins_with("ms_"):
						most[k] = float(most.get(k, 0.0)) + float(w[18][k]) / window.size()  # the mean
					else:
						most[k] = maxi(int(most.get(k, 0)), int(w[18][k]))
		for k: String in most.keys():
			if k.begins_with("ms_"):
				most[k] = snappedf(most[k], 0.01)
		var segs := {}
		for w: Array in window:
			if w.size() > 14:
				for k in (w[14] as Dictionary):
					segs[k] = float(segs.get(k, 0.0)) + float(w[14][k]) / window.size()
		for k in segs.keys():
			segs[k] = snappedf(segs[k], 0.01)
			if segs[k] < 0.2:
				segs.erase(k)
		var s := summarize(window)
		print("WINDOW %3d frames | p50 %5.1f p99 %5.1f ms | process p50 %5.2f | gpu p50 %5.2f | draws %d | prims %d | most %s | mean ms by subtree %s" % [
			window.size(), s["p50"], s["p99"], s["process_p50"], s["gpu_p50"], s["draw_calls_p50"], s["primitives_p50"], JSON.stringify(most), JSON.stringify(segs)])
		window = []
		t = 0.0


func _finish() -> void:
	_done = true
	var merged: Array = world.far_chunks.census()
	print("FAR merged chunks %d, %d triangles, %d far; worker %.0f ms, main %.0f ms" % [merged[0], merged[1], merged[2],
		world.far_chunks.worker_usec / 1000.0, world.far_chunks.main_usec / 1000.0])
	var seen: Array = world.far_chunks.view_census()
	print("FAR in view: %d merged meshes, %d surfaces of far chunks' own MultiMeshes, %d of near chunks'" % seen)
	for row: Array in world.far_chunks.models().slice(0, 25):
		print("FAR model %-36s instances %6d x %5d triangles = %8d" % [row[0], row[1], row[2], int(row[1]) * int(row[2])])
	var phases := {"load": summarize(_load_frames), "walk": summarize(_frames)}
	var lat: Array = world.drawn_latency
	var lat_ms: Array = lat.map(func(r: Array) -> float: return float(r[0]))
	var near_ms: Array = lat.filter(func(r: Array) -> bool: return r.size() > 2 and float(r[2]) >= 0.0).map(func(r: Array) -> float: return float(r[2]))
	print("STUTTER chunks drawn while walking %d: wanted to drawn p50 %.0f p99 %.0f worst %.0f ms; came within 2 chunks of the focus still not drawn %d, from then: p50 %.0f p99 %.0f worst %.0f ms; still not drawn at the end %d; overruns %s" % [
		lat_ms.size(), pct(lat_ms, 0.5), pct(lat_ms, 0.99), pct(lat_ms, 1.0), near_ms.size(), pct(near_ms, 0.5), pct(near_ms, 0.99), pct(near_ms, 1.0),
		world.undrawn(), JSON.stringify(preload("res://scripts/world/frame_budget.gd").overruns)])
	var text := JSON.stringify({"summary": phases, "frames": _frames, "load_frames": _load_frames, "variants": _variant_results, "latency": lat,
		"frame_budget": "shared" if preload("res://scripts/world/frame_budget.gd").shared else "separate"})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	for phase in phases:
		var summary: Dictionary = phases[phase]
		print("STUTTER %s: frames %d | p50 %.1f p99 %.1f worst %.1f ms | over 16.7 ms %d, over 33 ms %d, over 50 ms %d | main ms total %s | in slow frames %s" % [
			phase, summary["frames"], summary["p50"], summary["p99"], summary["worst"], summary["over16"], summary["over33"], summary["over50"],
			JSON.stringify(summary["main_ms_total"]), JSON.stringify(summary["main_ms_in_frames_over_33"])])
		print("STUTTER %s: _process p50 %.2f p99 %.2f ms | render cpu p50 %.2f ms | gpu p50 %.2f p99 %.2f ms | draw calls p50 %d | primitives p50 %d" % [
			phase, summary["process_p50"], summary["process_p99"], summary["render_cpu_p50"], summary["gpu_p50"], summary["gpu_p99"],
			summary["draw_calls_p50"], summary["primitives_p50"]])
		print("STUTTER %s: _process by subtree in frames over 33 ms: %s" % [phase, JSON.stringify(summary["segments_in_frames_over_33"])])
		print("STUTTER %s worst frames [ms, models, lods, rebuild, terrain, handle, render cpu, gpu, models made, x, y, tick, all process, physics, {node: ms}, pipelines]:" % phase)
		for r in summary["worst_frames"].slice(0, 8):
			print("  ", JSON.stringify(r))
	_print_windows(_frames)
	var by_type: Array = Bridge.handle_usec.keys().map(func(k) -> Array: return [snappedf(Bridge.handle_usec[k] / 1000.0, 0.1), k])
	by_type.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("STUTTER message handling by type, ms over the whole run: %s" % JSON.stringify(by_type.slice(0, 16)))
	const ModelLibrary := preload("res://scripts/world/model_library.gd")
	var slow := ModelLibrary.slowest.duplicate()
	slow.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var slow_msgs: Array = Bridge.slow_messages.duplicate()
	slow_msgs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("STUTTER messages over 8 ms to handle (ms, type, bytes), %d: %s" % [slow_msgs.size(), JSON.stringify(slow_msgs.slice(0, 15))])
	print("STUTTER memory: static %.0f MB, video %.0f MB" % [Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	print("SLOWEST models made on the main thread (ms, name), %d over 2 ms:" % slow.size())
	for r in slow.slice(0, 12):
		print("  ", r)
	preload("res://scripts/menu/exit_guard.gd").arm()
	get_tree().quit()
