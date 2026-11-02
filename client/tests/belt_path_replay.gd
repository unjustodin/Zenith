extends Node
## Replays items recorded on real belts through belt_items.gd and writes where each is drawn every
## frame, for tools/belt_path_check.py to measure how far they stray off their lanes (owner: items
## floated off belts on a dense base). No server: the recording (tools/belt_path_check.py --record,
## in real Factorio) has the belts, every lane's line and each item's place every tick.
##
##   godot --headless --path client res://tests/belt_path_replay.tscn -- --truth=<truth.json>
##       --out=<drawn.json> [--period=6] [--straight] [--lead=<ticks>]
##
## --period: ticks between updates (6 as the mod sends them, 12-48 when it is slowed down);
## --straight: no belts given, so items glide in straight lines as before the lane paths;
## --lead: items carried on from a read this many ticks early, as the mod's slices do.

const BeltItems := preload("res://scripts/world/belt_items.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const WorldMirror := preload("res://scripts/world/world.gd")


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var truth = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("truth", ""))))
	if not (truth is Dictionary):
		push_error("no truth file")
		get_tree().quit(1)
		return
	var period := int(args.get("period", "6"))
	var lead := int(args.get("lead", "0"))
	var protos := ProtoDB.new()
	var ids := {}
	var list: Array = []
	for b in truth["belts"]:
		var name := str(b[0])
		if not ids.has(name):
			ids[name] = ids.size() + 1
			list.append([ids[name], name, str(b[1]), -0.5, -0.5, 0.5, 0.5, 128, 128, 128, 1, 1])
	protos.add_entities(list)
	protos.add_items([[1, ""]])
	var items := BeltItems.new()
	items.protos = protos
	add_child(items)
	items._sync = true  # after _ready, which reads it from the command line
	if not args.has("straight"):
		var by_chunk := {}
		var unit := 1
		for b in truth["belts"]:
			var r := WorldMirror.Rec.new()
			r.unit = unit
			unit += 1
			r.proto_id = ids[str(b[0])]
			r.pos = Vector2(float(b[2]), float(b[3]))
			r.fixed = Vector2i(roundi(r.pos.x * 256), roundi(r.pos.y * 256))
			r.dir = int(b[4])
			var t := str(b[1])
			if t == "transport-belt":
				r.extra = {"s": str(b[5])}
			elif t == "underground-belt":
				r.extra = {"u": str(b[5])}
			r.chunk = WorldMirror.chunk_of(r.pos)
			r.key = r.unit
			if not by_chunk.has(r.chunk):
				by_chunk[r.chunk] = []
			by_chunk[r.chunk].append(r)
		for c in by_chunk:
			items.index_chunk(c, by_chunk[c])
	# Each item's place by tick: uid -> {tick: [x, y, flags]}.
	var tracks := {}
	var first := 1 << 40
	var last := 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for tr in truth["tracks"]:
		var by_tick := {}
		var l: Array = tr[1]
		for i in range(0, l.size() - 3, 4):
			var t := int(l[i])
			by_tick[t] = [int(l[i + 1]), int(l[i + 2]), int(l[i + 3])]
			first = mini(first, t)
			last = maxi(last, t)
			lo = Vector2(minf(lo.x, l[i + 1] / 256.0), minf(lo.y, l[i + 2] / 256.0))
			hi = Vector2(maxf(hi.x, l[i + 1] / 256.0), maxf(hi.y, l[i + 2] / 256.0))
		tracks[int(tr[0])] = by_tick
	var mid := (lo + hi) * 0.5
	var half := ceili(maxf(hi.x - lo.x, hi.y - lo.y) * 0.5) + 2
	var frames: Array = []
	var start := first + lead + 1
	if args.has("ticks"):
		last = mini(last, start + int(args["ticks"]))
	var t0 := Time.get_ticks_msec()
	print("belt-path-replay: %d items, ticks %d to %d" % [tracks.size(), start, last])
	for tick in range(start, last + 1):
		if (tick - start) % 100 == 0:
			print("  tick %d, %d ms, %d items, %d jobs" % [tick - start, Time.get_ticks_msec() - t0, items.count(), items.stats["jobs"]])
		if (tick - start) % period == 0:
			var l: Array = []
			for uid in tracks:
				var at = tracks[uid].get(tick - lead)
				var now = tracks[uid].get(tick)
				if at == null or now == null or (int(at[2]) & 2) != 0:
					continue
				var x := float(at[0])
				var y := float(at[1])
				if lead > 0:
					# The mod's slices: read `lead` ticks early and carried on at the speed between the
					# item's last two reads, in a straight line (belt_items.lua).
					var before = tracks[uid].get(tick - lead - period)
					if before != null:
						x += (x - float(before[0])) / period * lead
						y += (y - float(before[1])) / period * lead
				l.append_array([uid, 1, roundi(x), roundi(y)])
			items.handle({"t": "bi", "k": tick, "p": period, "fx": roundi(mid.x * 256), "fy": roundi(mid.y * 256), "fr": half, "l": l})
		items._process(1.0 / 60.0)
		var row: Array = [tick, items._drawn]
		for uid in tracks:
			if not items._positions.has(uid):
				items.position_of(uid)
				continue
			var at = items.position_of(uid)
			if at == null:
				row.append_array([uid, 0, 0, 0])
			else:
				row.append_array([uid, snappedf(at.x, 0.0001), snappedf(at.z, 0.0001), 1])
		frames.append(row)
	var stats: Dictionary = items.stats
	var f := FileAccess.open(str(args.get("out", "user://belt_drawn.json")), FileAccess.WRITE)
	f.store_string(JSON.stringify({"period": period, "lead": lead, "straight": args.has("straight"), "frames": frames, "stats": stats}))
	f.close()
	print("belt-path-replay: %d frames, %d items, glides %s (not known, straight, path, snapped, too far), worker %.1f ms over %d jobs (worst %.1f)" % [
		frames.size(), tracks.size(), stats["routes"], stats["worker_usec"] / 1000.0, stats["jobs"], stats["worst_job_usec"] / 1000.0])
	get_tree().quit(0)
