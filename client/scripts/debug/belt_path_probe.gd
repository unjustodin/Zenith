extends Node
## --belt-path-probe=<out.json>[@seconds[@settle]]: where the client draws each item on belts every
## frame, for tools/belt_path_check.py to measure against the lanes the server records meanwhile
## (`belt_path_check.py record`), and what belt_items.gd costs: its main-thread time a frame, its
## jobs' time on the worker, how items glided. Waits `settle` seconds (default 10) after the world
## is ready, records for `seconds` (default 20), writes the file, prints the summary and quits.
## With an out path of "-" it records no positions (cost only).

const MAX_ITEMS := 4000

var main: Node  # main.gd: its belt_items
var out_path := ""

var _seconds := 20.0
var _settle := 10.0
var _t := 0.0
var _started := false
var _frames: Array = []
var _uids := {}
var _dt: Array[float] = []
var _base := {}


func _ready() -> void:
	process_priority = 1000  # after the layers have drawn this frame
	var spec := out_path.split("@")
	out_path = spec[0]
	if spec.size() > 1:
		_seconds = float(spec[1])
	if spec.size() > 2:
		_settle = float(spec[2])


func _process(delta: float) -> void:
	if main == null or not Bridge.world_ready or main.belt_items == null:
		return
	var belt = main.belt_items
	_t += delta
	if _t < _settle:
		return
	if not _started:
		_started = true
		_base = belt.stats.duplicate(true) if "stats" in belt else {}
		print("belt-path-probe: recording %.0f s" % _seconds)
	_dt.append(delta)
	if out_path != "-":
		if belt._task < 0 and _uids.size() < MAX_ITEMS:
			for uid in belt._state.items:
				if _uids.size() >= MAX_ITEMS:
					break
				_uids[uid] = true
		var row: Array = [Bridge.server_tick, belt._drawn]
		for uid in _uids:
			var known: bool = belt._positions.has(uid)
			var at = belt.position_of(uid)
			if not known:
				continue
			if at == null:
				row.append_array([uid, 0, 0, 0])
			else:
				row.append_array([uid, snappedf(at.x, 0.0001), snappedf(at.z, 0.0001), 1])
		_frames.append(row)
	if _t >= _settle + _seconds:
		_finish(belt)


func _finish(belt) -> void:
	set_process(false)
	var times := _dt.duplicate()
	times.sort()
	var frames := "frames p50 %.1f ms, p99 %.1f ms" % [times[times.size() / 2] * 1000.0, times[mini(times.size() - 1, int(times.size() * 0.99))] * 1000.0]
	if not ("stats" in belt):  # belt_items.gd from before it kept them: where items are drawn only
		print("belt-path-probe: %d items now; %s" % [belt.count(), frames])
		_write({"period": 0, "frames": _frames})
		return
	var st: Dictionary = belt.stats
	var d := {}
	for k in ["frames", "main_usec", "jobs", "worker_usec", "indexed", "index_usec", "write_usec", "cached", "fresh", "missing"]:
		d[k] = int(st.get(k, 0)) - int(_base.get(k, 0))
	d["worst_job_usec"] = st["worst_job_usec"]
	var routes: Array = []
	for k in 5:
		routes.append(int(st["routes"][k]) - int(_base["routes"][k]))
	d["routes"] = routes
	var summary := "belt-path-probe: %d items now, belt items %.3f ms a frame on the main thread, %.2f ms a job on a worker (%.1f jobs a second, worst %.1f ms; indexing belts %d chunks, %.2f ms a job, writing %.2f ms a job, %d glides on a known run, %d new items, %d missing), glides %s (not known, straight, path, snapped, too far); %s" % [
		belt.count(), d["main_usec"] / 1000.0 / maxi(d["frames"], 1), d["worker_usec"] / 1000.0 / maxi(d["jobs"], 1),
		d["jobs"] / _seconds, d["worst_job_usec"] / 1000.0, d["indexed"], d["index_usec"] / 1000.0 / maxi(d["jobs"], 1), d["write_usec"] / 1000.0 / maxi(d["jobs"], 1), d["cached"], d["fresh"], d["missing"], routes, frames]
	print(summary)
	print("belt-path-probe: of a job, routing items not on a known run %.2f ms, folding glides %.2f ms (since the start); routes found without a walk %d, walked by the kind of belt they began on (straight, left, right, entrance, exit, splitter, other) %s" % [
		st.get("route_usec", 0) / 1000.0 / maxi(st["jobs"], 1), st.get("fold_usec", 0) / 1000.0 / maxi(st["jobs"], 1), st.get("runs", 0), st.get("walks", [])])
	_write({"period": 0, "frames": _frames, "stats": d, "summary": summary})


func _write(data: Dictionary) -> void:
	if out_path != "-" and out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
	get_tree().quit(0)
