extends Node
## --terrain-probe: measures how long the ground takes to appear. Every 5 s it prints, for the
## chunks that got their ground in that time, the wait from subscribing to the chunk's tiles
## arriving and from there to the ground being drawn; how long chunks near the focus were holes
## (no ground drawn); terrain build count and cost; and the slowest frames.

const CHUNK := 32
const INTERVAL := 5.0

var world  # world.gd

var _timer := 0.0
var _seen := {}  # ChunkView instance id -> true once its ground was counted
var _arrive: Array[float] = []  # ms, subscribe -> tiles
var _draw: Array[float] = []  # ms, tiles -> ground drawn
var _total: Array[float] = []  # ms, subscribe -> ground drawn
var _hole_near := 0.0  # chunk-seconds of holes within 1 chunk of the focus chunk
var _hole_view := 0.0  # ... within 2 chunks (about what the camera sees)
var _frames: Array[float] = []
var _builds_before := 0
var _build_usec_before := 0
var _worker_usec_before := 0
var _ent_before := 0
var _ent_usec_before := 0
var _slow_frames: Array[String] = []
var _all_total: Array[float] = []
var _all_hole_view := 0.0
var _all_hitches := 0


func _process(delta: float) -> void:
	if world == null or not Bridge.world_ready:
		return
	_frames.append(delta * 1000.0)
	if delta > 0.05 and _slow_frames.size() < 8:
		_slow_frames.append("%d" % int(delta * 1000.0))
	var center: Vector2i = world.chunk_of(world.focus())
	for cv in world.chunks.values():
		var d: Vector2i = (cv.coord - center).abs()
		var ring := maxi(d.x, d.y)
		if not cv.has_ground():
			if ring <= 1:
				_hole_near += delta
			if ring <= 2:
				_hole_view += delta
			continue
		var id: int = cv.get_instance_id()
		if _seen.has(id) or cv.drawn_msec == 0 or cv.tiles_msec == 0:
			continue
		_seen[id] = true
		_arrive.append(float(cv.tiles_msec - cv.created_msec))
		_draw.append(float(cv.drawn_msec - cv.tiles_msec))
		_total.append(float(cv.drawn_msec - cv.created_msec))
	_timer += delta
	if _timer >= INTERVAL:
		_timer = 0.0
		_report()


func _report() -> void:
	var builds: int = world.terrain_builds - _builds_before
	var usec: int = world.terrain_build_usec - _build_usec_before
	_builds_before = world.terrain_builds
	_build_usec_before = world.terrain_build_usec
	var worker: int = world.terrain_worker_usec - _worker_usec_before
	_worker_usec_before = world.terrain_worker_usec
	var ents: int = world.entity_builds - _ent_before
	var ent_usec: int = world.entity_build_usec - _ent_usec_before
	_ent_before = world.entity_builds
	_ent_usec_before = world.entity_build_usec
	var hitches := 0
	for f in _frames:
		if f > 33.0:
			hitches += 1
	_all_total.append_array(_total)
	_all_hole_view += _hole_view
	_all_hitches += hitches
	print("TERRAIN %d chunks | sub->tiles %s | tiles->ground %s | sub->ground %s | holes near %.1f view %.1f chunk-s | %d builds, %.2f ms each on workers, main thread %.0f ms | %d entity builds %.0f ms | frames p50 %.1f p99 %.1f max %.1f ms, %d over 33 ms (slow: %s) | queued %d, gaps %d, loaded %d/%d | all: sub->ground %s, holes %.1f, hitches %d" % [
		_total.size(), _stats(_arrive), _stats(_draw), _stats(_total), _hole_near, _hole_view,
		builds, worker / 1000.0 / maxf(builds, 1), usec / 1000.0, ents, ent_usec / 1000.0,
		_pct(_frames, 0.5), _pct(_frames, 0.99), _pct(_frames, 1.0), hitches, ",".join(_slow_frames), world.terrain_queue_size(), int(Bridge.stats.get("gaps", 0)), world.loaded_chunk_count(), world.chunks.size(),
		_stats(_all_total), _all_hole_view, _all_hitches])
	_arrive.clear()
	_draw.clear()
	_total.clear()
	_frames.clear()
	_slow_frames.clear()
	_hole_near = 0.0
	_hole_view = 0.0


func _stats(a: Array[float]) -> String:
	if a.is_empty():
		return "-"
	return "p50 %d p90 %d max %d ms" % [_pct(a, 0.5), _pct(a, 0.9), _pct(a, 1.0)]


func _pct(a: Array[float], p: float) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return s[clampi(int(ceil(p * s.size())) - 1, 0, s.size() - 1)]
