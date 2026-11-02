extends Node
## --glide-probe=<out.json>[@seconds per level]: checks that moving things still glide when the mod
## sends them less often (`rate`, Bridge.set_update_rate). Goes through rate levels 0, 1, 2 and 3,
## holding each for the given seconds (default 30: 8 to settle, the rest recorded), and records
## every frame where each mover and up to MAX_ITEMS belt items are drawn. For each kind of thing that
## moved it reports its speed and how often it stopped and went (a stall: a frame or few at under a
## fifth of its usual speed between frames at its usual speed) or jumped (over three times its usual
## speed in one frame). Writes the summary to the file, prints it, sets the level back to 0 and quits.

const SETTLE := 8.0
const MAX_ITEMS := 3000
const LEVELS := [0, 1, 2, 3]

var main: Node  # main.gd: its movers and belt_items
var out_path := ""

var _seconds := 30.0
var _level_i := -1
var _left := 0.0
var _started := false
## key -> [kind, Array of speeds (tiles a second, NAN when it wasn't drawn), last position]
var _tracks := {}
var _uids: Array = []
var _results := {}
var _frames := 0
var _dt: Array[float] = []


func _ready() -> void:
	process_priority = 1000  # after the layers have drawn this frame
	var spec := out_path.split("@")
	out_path = spec[0]
	if spec.size() > 1:
		_seconds = float(spec[1])


func _process(delta: float) -> void:
	if main == null or not Bridge.world_ready or main.movers == null or main.belt_items == null:
		return
	if not _started:
		_started = true
		_next_level()
		return
	_left -= delta
	if _left <= 0.0:
		_finish_level()
		if _level_i + 1 >= LEVELS.size():
			_write()
			return
		_next_level()
		return
	if _left > _seconds - SETTLE:
		return
	_frames += 1
	_dt.append(delta)
	var movers = main.movers
	for unit in movers._movers:
		var m = movers._movers[unit]
		_step("m%d" % unit, m.type, movers.position_of(unit), delta)
	var belt = main.belt_items
	if _uids.is_empty() and belt._task < 0:
		var n := 0
		for uid in belt._state.items:
			_uids.append(uid)
			n += 1
			if n >= MAX_ITEMS:
				break
	for uid in _uids:
		var at = belt.position_of(uid)
		if at != null:
			_step("b%d" % uid, "belt item", at, delta)


func _step(key: String, kind: String, at: Vector3, delta: float) -> void:
	var t: Array = _tracks.get(key, [])
	if t.is_empty():
		t = [kind, [], at]
		_tracks[key] = t
		return
	var was: Vector3 = t[2]
	(t[1] as Array).append(Vector2(at.x - was.x, at.z - was.z).length() / maxf(delta, 0.001))
	t[2] = at


func _next_level() -> void:
	_level_i += 1
	Bridge.set_update_rate(LEVELS[_level_i])
	_left = _seconds
	_tracks.clear()
	_uids.clear()
	_frames = 0
	_dt.clear()


## Per kind: things that moved, their median speed, stalls and jumps per thing-minute.
func _finish_level() -> void:
	var kinds := {}
	var standing := {}  # kind -> things that stood still the whole time
	for key in _tracks:
		var t: Array = _tracks[key]
		var speeds: Array = t[1]
		if speeds.size() < 60:
			continue
		var sorted := speeds.duplicate()
		sorted.sort()
		var usual: float = sorted[int(sorted.size() * 0.75)]  # its usual speed while it moves
		if usual < 0.3:
			standing[t[0]] = int(standing.get(t[0], 0)) + 1
			continue  # standing (or nearly): a full belt backed up, a parked car
		var stalls := 0
		var jumps := 0
		var i := 3
		while i < speeds.size() - 3:
			var s: float = speeds[i]
			if s < usual * 0.2:
				var before := false
				var after := false
				for j in range(1, 4):
					before = before or speeds[i - j] > usual * 0.6
					after = after or speeds[i + j] > usual * 0.6
				if before and after:
					stalls += 1
					i += 3
					continue
			elif s > usual * 3.0 and s * 0.0167 > 0.05:
				jumps += 1
			i += 1
		var k: Dictionary = kinds.get(t[0], {"things": 0, "frames": 0, "stalls": 0, "jumps": 0, "speeds": []})
		k["things"] += 1
		k["frames"] += speeds.size()
		k["stalls"] += stalls
		k["jumps"] += jumps
		(k["speeds"] as Array).append(sorted[sorted.size() / 2])
		kinds[t[0]] = k
	var out := {}
	var minutes_per_frame := 1.0 / 3600.0  # at 60 fps; frames are counted, not seconds
	var mean_dt := 0.0
	for d in _dt:
		mean_dt += d
	mean_dt = mean_dt / maxf(1.0, _dt.size())
	for kind in kinds:
		var k: Dictionary = kinds[kind]
		var minutes: float = k["frames"] * mean_dt / 60.0
		var med: Array = k["speeds"]
		med.sort()
		out[kind] = {"things": k["things"], "median_speed": snappedf(med[med.size() / 2], 0.01),
			"stalls_per_minute": snappedf(k["stalls"] / maxf(minutes, 0.001), 0.01),
			"jumps_per_minute": snappedf(k["jumps"] / maxf(minutes, 0.001), 0.01),
			"stalls": k["stalls"], "jumps": k["jumps"]}
	var level: int = LEVELS[_level_i]
	_results[str(level)] = {"standing": standing, "frames": _frames, "fps": snappedf(1.0 / maxf(mean_dt, 0.0001), 0.1),
		"ups": snappedf(main.movers.clock.rate, 0.1), "kinds": out}
	print("glide-probe: rate %d: %s" % [level, JSON.stringify(_results[str(level)])])


func _write() -> void:
	Bridge.set_update_rate(0)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_results, "  "))
		f.close()
	print("glide-probe: written to %s" % out_path)
	set_process(false)
	get_tree().quit()
