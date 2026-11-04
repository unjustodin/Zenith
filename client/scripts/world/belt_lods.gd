extends RefCounted
## Belts far away drawn as stand-ins of a handful of triangles (docs/PERFORMANCE-AUDIT.md 4.1).
## Every belt tier, curve and underground end is Wube's printable belt, about 1,450 triangles a
## tile: at a busy base two thirds of the GPU's work, nearly all of it in triangles smaller than a
## pixel once the camera is pulled back. Where a tile is drawn smaller than FLAT_BELOW pixels at a
## chunk's nearest belt (from the camera's distance, field of view or orthographic size and the
## window's height, so zooming, the field of view and the F6 view all count), the chunk's belts,
## undergrounds and splitters are drawn with their stand-ins instead, and in full again above
## FULL_ABOVE (the gap keeps a chunk at the edge from swapping back and forth).
##
## A stand-in is the model's top as flat cells on a few grid lines per kind (a straight belt: its
## two rails and its bed; a curve: those in arcs; an underground end: its hood in steps and the open
## bed; a splitter: a coarse grid), with walls down to whatever is lower beside them. Each cell
## takes the model's own surface (material) found on top there and its corners the model's own
## vertex data nearest them (part colours, occlusion, worn edges, the sprite's visibility), so the
## same materials draw it: the belt surface's slats and the tier's chevron scroll in the shader as
## on the full model, tiers keep their paint. The bed's top is the full model's (items on belts and
## far lane icons sit on it as before). Stand-ins cast no shadow; the full model's shadow stand-in
## (model_lods.gd) is hidden with it. They are made once per model on a worker thread; until then
## the full model is drawn.

const ModelLods := preload("res://scripts/world/model_lods.gd")
const MaterialRows := preload("res://scripts/world/material_rows.gd")

## Pixels a tile is drawn at, at a chunk's nearest belt, below which its belts go flat, and above
## which they are drawn in full again. The default camera draws its farthest ground at about 28 px a
## tile in a 1080-pixel window and Factorio's view (F6) at 32, so belts stay whole there; at 20 px
## the belt's rails are a pixel wide and its rollers half one.
const FLAT_BELOW := 20.0
const FULL_ABOVE := 24.0
## Entity types drawn with stand-ins far away.
const TYPES := {"transport-belt": true, "underground-belt": true, "linked-belt": true, "splitter": true, "lane-splitter": true}
## The key of a stand-in's MultiMesh in chunk_view.gd (_nodes[[model, FLAT]]).
const FLAT := &"flat"
## Jobs at once on worker threads.
const JOBS := 2
## Seconds between looks when the camera hasn't moved.
const CHECK_INTERVAL := 0.25

## --no-belt-stand-ins: full belts everywhere (for comparing).
static var enabled := not ("--no-belt-stand-ins" in OS.get_cmdline_user_args())
## Mesh -> its stand-in (ArrayMesh, empty until its job is done), or null: none (not a mesh it can make).
static var _stand_ins := {}
static var _ready := {}  # stand-in -> true once it has its shape
static var _queue: Array = []  # [Job, stand-in, source mesh]
static var _running: Array = []  # [task id, Job, stand-in, source mesh]
## Goes up whenever stand-ins become ready: chunks that drew a belt without one are built again.
static var generation := 0
## Chunks with belts (chunk_view.gd track/untrack): ChunkView -> true.
static var _chunks := {}
static var _dirty := false
static var _timer := 0.0
static var _last_view := []
## Main-thread time spent here (for probes).
static var main_usec := 0


## The plan a stand-in is made on: "s" straight, "l"/"r" curves, "u" underground ends, "x" splitters.
static func kind_of(proto_type: String, extra: Dictionary) -> String:
	match proto_type:
		"transport-belt":
			return str(extra.get("s", "s"))
		"underground-belt", "linked-belt":
			return "u"
	return "x"


## The stand-in for `mesh`, or null while it is being made (see made()) or when there is none.
static func stand_in(mesh: Mesh, kind: String) -> ArrayMesh:
	if not enabled or mesh == null:
		return null
	if _stand_ins.has(mesh):
		var out: ArrayMesh = _stand_ins[mesh]
		if out == null or not _ready.has(out):
			return null
		_same_materials(out, mesh as ArrayMesh)
		return out
	var t0 := Time.get_ticks_usec()
	var job := _job_for(mesh as ArrayMesh, kind)
	var out: ArrayMesh = null
	if job != null:
		out = ArrayMesh.new()
		_queue.append([job, out, mesh])
	_stand_ins[mesh] = out
	main_usec += Time.get_ticks_usec() - t0
	return null


## Whether a stand-in for `mesh` is still to come (asked, not made yet).
static func coming(mesh: Mesh) -> bool:
	var out: ArrayMesh = _stand_ins.get(mesh)
	return out != null and not _ready.has(out)


## A model's materials may be swapped after its stand-in was made (material_rows.gd edits): the
## stand-in follows.
static func _same_materials(out: ArrayMesh, mesh: ArrayMesh) -> void:
	var from: PackedInt32Array = out.get_meta(&"f3d_from", PackedInt32Array())
	for i in out.get_surface_count():
		if i < from.size() and from[i] < mesh.get_surface_count():
			var m := mesh.surface_get_material(from[i])
			if out.surface_get_material(i) != m:
				out.surface_set_material(i, m)


static func track(cv) -> void:
	if not _chunks.has(cv):
		_chunks[cv] = true
		_dirty = true


static func untrack(cv) -> void:
	_chunks.erase(cv)


## Each frame (far_chunks.gd): finishes stand-ins made on workers, and sets each chunk with belts
## flat or full by how big a tile is drawn at its nearest belt.
static func update(world, cam: Camera3D, delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_poll(world)
	_timer += delta
	if cam == null:
		main_usec += Time.get_ticks_usec() - t0
		return
	var vp := cam.get_viewport()
	var size := vp.get_visible_rect().size if vp != null else Vector2(1920, 1080)
	var scale := 1.0
	if vp != null and vp.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
		scale = vp.scaling_3d_scale
	var view := [cam.global_transform, cam.projection, cam.fov, cam.size, size, scale, enabled]
	if not _dirty and _timer < CHECK_INTERVAL and view == _last_view:
		main_usec += Time.get_ticks_usec() - t0
		return
	_timer = 0.0
	_dirty = false
	_last_view = view
	var at := cam.global_position
	var pixels := (size.x if cam.keep_aspect == Camera3D.KEEP_WIDTH else size.y) * scale
	for cv in _chunks.keys():
		if not is_instance_valid(cv):
			_chunks.erase(cv)
			continue
		var px := tile_pixels(cam, at, pixels, cv.belt_bounds)
		var flat: bool = cv.belt_flat
		if not enabled or px > FULL_ABOVE:
			flat = false
		elif px < FLAT_BELOW:
			flat = true
		cv.set_belt_flat(flat)
	main_usec += Time.get_ticks_usec() - t0


## How many pixels tall one tile is drawn at the nearest point of `box`: `pixels` is the window's
## height (or width, for a camera keeping its width) in rendered pixels.
static func tile_pixels(cam: Camera3D, at: Vector3, pixels: float, box: AABB) -> float:
	if cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return pixels / maxf(cam.size, 0.001)
	var d := at.distance_to(at.clamp(box.position, box.end))
	return pixels / (2.0 * tan(deg_to_rad(cam.fov) * 0.5) * maxf(d, 0.01))


static func _poll(world) -> void:
	var done := false
	for i in range(_running.size() - 1, -1, -1):
		var entry: Array = _running[i]
		if not WorkerThreadPool.is_task_completed(entry[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(entry[0])
		_running.remove_at(i)
		_commit(entry[1], entry[2], entry[3])
		done = true
	while _running.size() < JOBS and not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_running.append([WorkerThreadPool.add_task((next[0] as Job).run, false, "belt stand-in"), next[0], next[1], next[2]])
	if not done:
		return
	generation += 1
	if world == null:
		return
	for cv in _chunks.keys():
		if is_instance_valid(cv) and cv.belt_waiting:
			world.redraw(cv.coord)


## Makes every stand-in asked for now, waiting for the workers (tests).
static func finish_all() -> void:
	while not _queue.is_empty() or not _running.is_empty():
		for entry in _running:
			WorkerThreadPool.wait_for_task_completion(entry[0])
			entry[0] = -1
		for entry in _running:
			_commit(entry[1], entry[2], entry[3])
		_running.clear()
		while _running.size() < JOBS and not _queue.is_empty():
			var next: Array = _queue.pop_front()
			_running.append([WorkerThreadPool.add_task((next[0] as Job).run, false, "belt stand-in"), next[0], next[1], next[2]])
	generation += 1


static func _commit(job: Job, out: ArrayMesh, mesh: ArrayMesh) -> void:
	var from := PackedInt32Array()
	for s in job.out.size():
		var arrays: Array = job.out[s]
		if arrays.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, job.formats[s])
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(s))
		from.append(s)
	out.set_meta(&"f3d_from", from)
	out.resource_name = mesh.resource_name + " (far)"
	_ready[out] = true


static func is_ready(out: ArrayMesh) -> bool:
	return _ready.has(out)


## The job for a model, made from its arrays on the CPU (null: none kept, or bones).
static func _job_for(mesh: ArrayMesh, kind: String) -> Job:
	if mesh == null or not mesh.has_meta(ModelLods.ARRAYS_META):
		return null
	var job := Job.new()
	job.kind = kind
	job.box = mesh.get_aabb()
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return null
		var arrays := ModelLods.arrays_of(mesh, i)
		if arrays[Mesh.ARRAY_BONES] != null:
			return null
		job.surfaces.append(arrays)
		job.formats.append(mesh.surface_get_format(i) & ModelLods.CUSTOM_FORMATS)
		# Which of its materials (or rows of one merged material) are the moving belt surface.
		var material := mesh.surface_get_material(i)
		var belt := []
		var rows := MaterialRows.rows(material)
		for m in (rows if not rows.is_empty() else [material]):
			belt.append(m != null and str(m.resource_name).contains("belt_surface"))
		job.belt_rows.append(belt)
	return job


## Builds one stand-in on a worker thread.
class Job:
	var kind := "s"
	var box := AABB()
	## Per source surface: its arrays, its custom formats, which of its rows are belt surface.
	var surfaces: Array = []
	var formats: Array = []
	var belt_rows: Array = []
	## Per source surface: the stand-in's arrays ([] when nothing of it is on top).
	var out: Array = []

	## The model's triangles in a coarse grid over the ground, to find what is on top quickly.
	const BUCKETS := 12
	var _tris: Array = []  # [a, b, c, surface, row]
	var _buckets: Array = []

	func run() -> void:
		_index()
		var grid := _grid()
		var corners: Array = grid[0]
		var nx := corners.size() - 1
		var nz: int = (corners[0] as Array).size() - 1
		var walls_along: bool = grid[1]
		# Each cell: [height, surface, row] or null (nothing there).
		var cells: Array = []
		for i in nx:
			var col: Array = []
			for j in nz:
				col.append(_sample_cell(corners[i][j], corners[i + 1][j], corners[i + 1][j + 1], corners[i][j + 1]))
			cells.append(col)
		var builders: Array = []
		for s in surfaces.size():
			builders.append(Builder.new(surfaces[s]))
		for i in nx:
			for j in nz:
				var cell = cells[i][j]
				if cell == null:
					continue
				var h: float = cell[0]
				var b: Builder = builders[cell[1]]
				var p00: Vector2 = corners[i][j]
				var p10: Vector2 = corners[i + 1][j]
				var p11: Vector2 = corners[i + 1][j + 1]
				var p01: Vector2 = corners[i][j + 1]
				b.quad([_v3(p00, h), _v3(p10, h), _v3(p11, h), _v3(p01, h)], Vector3.UP, cell[2])
				# Walls where what is beside it is lower: across always, along only where asked
				# (a belt's ends meet the next belt's).
				var mid := (p00 + p10 + p11 + p01) * 0.25
				_wall(b, cell, p00, p01, mid, cells, i - 1, j)
				_wall(b, cell, p10, p11, mid, cells, i + 1, j)
				if walls_along or j > 0:
					_wall(b, cell, p00, p10, mid, cells, i, j - 1)
				if walls_along or j < nz - 1:
					_wall(b, cell, p01, p11, mid, cells, i, j + 1)
		for s in surfaces.size():
			out.append((builders[s] as Builder).arrays())
		surfaces = []
		_tris = []
		_buckets = []

	func _wall(b: Builder, cell: Array, e0: Vector2, e1: Vector2, mid: Vector2, cells: Array, ni: int, nj: int) -> void:
		var low := 0.0
		if ni >= 0 and ni < cells.size() and nj >= 0 and nj < (cells[0] as Array).size() and cells[ni][nj] != null:
			low = float(cells[ni][nj][0])
		var h: float = cell[0]
		if low >= h - 0.005:
			return
		var edge := e1 - e0
		var out2 := Vector2(edge.y, -edge.x).normalized()
		if out2.dot((e0 + e1) * 0.5 - mid) < 0.0:
			out2 = -out2
		b.quad([_v3(e0, low), _v3(e1, low), _v3(e1, h), _v3(e0, h)], Vector3(out2.x, 0.0, out2.y), cell[2])

	static func _v3(p: Vector2, y: float) -> Vector3:
		return Vector3(p.x, y, p.y)

	## [corner points [i][j] (x across, z along), whether the ends get walls] for the kind.
	func _grid() -> Array:
		var x0 := box.position.x
		var x1 := box.end.x
		var z0 := box.position.z
		var z1 := box.end.z
		match kind:
			"s":
				# The rails, then the bed between them (as wide as the belt surface).
				var bed := _belt_half_width(0.415)
				return [_rect([x0, -bed, bed, x1], [z0, z1]), false]
			"l", "r":
				# Quarter rings about the curve's inner corner (as the shader's belt_shape).
				var side := 1.0 if kind == "l" else -1.0
				var centre := Vector2(-0.5 * side, -0.5)
				var bed := _belt_half_width(0.415)
				var radii := [0.5 - (0.5 - 0.02), 0.5 - bed, 0.5 + bed, maxf(x1 - x0, z1 - z0)]
				var cols: Array = []
				for r in radii:
					var col: Array = []
					for k in 7:
						var a := float(k) / 6.0 * PI * 0.5
						col.append(centre + Vector2(cos(a) * side, sin(a)) * float(r))
					cols.append(col)
				return [cols, false]
			"u":
				# Its cheeks, the hood rising in steps, the open bed and the lip.
				return [_rect([x0, x0 + 0.13, x1 - 0.13, x1], [z0, -0.3, -0.1, 0.1, 0.32, 0.43, z1]), true]
		# Splitters: a grid of cells about a quarter tile.
		var xs: Array = []
		var n := maxi(2, int(round((x1 - x0) / 0.25)))
		for k in n + 1:
			xs.append(lerpf(x0, x1, float(k) / n))
		var zs: Array = []
		var m := maxi(2, int(round((z1 - z0) / 0.25)))
		for k in m + 1:
			zs.append(lerpf(z0, z1, float(k) / m))
		return [_rect(xs, zs), true]

	## Half the width of the model's belt surface (its widest extent across), else `fallback`.
	func _belt_half_width(fallback: float) -> float:
		var w := 0.0
		for t: Array in _tris:
			if _is_belt(t[3], t[4]):
				for k in 3:
					w = maxf(w, absf((t[k] as Vector3).x))
		return w if w > 0.2 and w < 0.49 else fallback

	func _is_belt(s: int, row: int) -> bool:
		var rows: Array = belt_rows[s]
		return row >= 0 and row < rows.size() and bool(rows[row])

	static func _rect(xs: Array, zs: Array) -> Array:
		var out: Array = []
		for x in xs:
			var col: Array = []
			for z in zs:
				col.append(Vector2(float(x), float(z)))
			out.append(col)
		return out

	## A cell's [height, surface, row]: what is on top at nine points inside it, by majority; its
	## height their median (the belt surface's highest, so items sit on it as on the full model).
	## Null when most of them hit nothing.
	func _sample_cell(p00: Vector2, p10: Vector2, p11: Vector2, p01: Vector2) -> Variant:
		var hits: Array = []
		for u: float in [1.0 / 6.0, 0.5, 5.0 / 6.0]:
			for v: float in [1.0 / 6.0, 0.5, 5.0 / 6.0]:
				var p := p00.lerp(p10, u).lerp(p01.lerp(p11, u), v)
				var hit := _top(p)
				if not hit.is_empty():
					hits.append(hit)
		if hits.size() < 4:
			return null
		var votes := {}
		for hit: Array in hits:
			var key := Vector2i(hit[1], hit[2])
			votes[key] = int(votes.get(key, 0)) + 1
		var best := Vector2i(-1, -1)
		for key in votes:
			if best.x < 0 or votes[key] > votes[best]:
				best = key
		var heights: Array = []
		for hit: Array in hits:
			if Vector2i(hit[1], hit[2]) == best:
				heights.append(float(hit[0]))
		heights.sort()
		var h: float = heights[heights.size() - 1] if _is_belt(best.x, best.y) else heights[heights.size() / 2]
		return [h, best.x, best.y]

	## The highest triangle over a point: [height, surface, row], or [].
	func _top(p: Vector2) -> Array:
		var bucket := _bucket_of(p)
		if bucket < 0:
			return []
		var best: Array = []
		for t: int in _buckets[bucket]:
			var tri: Array = _tris[t]
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c: Vector3 = tri[2]
			var d := (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
			if absf(d) < 1e-9:
				continue
			var l1 := ((p.x - a.x) * (c.z - a.z) - (c.x - a.x) * (p.y - a.z)) / d
			var l2 := ((b.x - a.x) * (p.y - a.z) - (p.x - a.x) * (b.z - a.z)) / d
			if l1 < -1e-5 or l2 < -1e-5 or l1 + l2 > 1.0 + 1e-5:
				continue
			var y := a.y + l1 * (b.y - a.y) + l2 * (c.y - a.y)
			if best.is_empty() or y > float(best[0]):
				best = [y, tri[3], tri[4]]
		return best

	func _bucket_of(p: Vector2) -> int:
		var u := (p.x - box.position.x) / maxf(box.size.x, 0.001)
		var v := (p.y - box.position.z) / maxf(box.size.z, 0.001)
		if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
			return -1
		return mini(int(u * BUCKETS), BUCKETS - 1) * BUCKETS + mini(int(v * BUCKETS), BUCKETS - 1)

	func _index() -> void:
		_buckets = []
		for k in BUCKETS * BUCKETS:
			_buckets.append([])  # plain Arrays: a PackedInt32Array taken out of an Array is a copy
		for s in surfaces.size():
			var arrays: Array = surfaces[s]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx = arrays[Mesh.ARRAY_INDEX]
			var rows := Builder.row_of(arrays)
			var count: int = (idx as PackedInt32Array).size() if idx != null else verts.size()
			for t in range(0, count - 2, 3):
				var ia: int = idx[t] if idx != null else t
				var ib: int = idx[t + 1] if idx != null else t + 1
				var ic: int = idx[t + 2] if idx != null else t + 2
				var a := verts[ia]
				var b := verts[ib]
				var c := verts[ic]
				# Only faces that can be seen from above.
				if absf((b - a).cross(c - a).y) < 1e-7:
					continue
				var row := int(rows[ia]) if not rows.is_empty() else 0
				var n := _tris.size()
				_tris.append([a, b, c, s, row])
				var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
				var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
				var u0 := clampi(int((lo.x - box.position.x) / maxf(box.size.x, 0.001) * BUCKETS), 0, BUCKETS - 1)
				var u1 := clampi(int((hi.x - box.position.x) / maxf(box.size.x, 0.001) * BUCKETS), 0, BUCKETS - 1)
				var v0 := clampi(int((lo.y - box.position.z) / maxf(box.size.z, 0.001) * BUCKETS), 0, BUCKETS - 1)
				var v1 := clampi(int((hi.y - box.position.z) / maxf(box.size.z, 0.001) * BUCKETS), 0, BUCKETS - 1)
				for u in range(u0, u1 + 1):
					for v in range(v0, v1 + 1):
						(_buckets[u * BUCKETS + v] as Array).append(n)


## A stand-in's surface made from one of the model's: new corners, each copying the vertex data of
## the model's vertex nearest it (of the same material row, facing the same way where there is one).
class Builder:
	var src: Array
	var rows := PackedFloat32Array()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var picks := PackedInt32Array()  # per new corner, the source vertex it copies
	## Per new corner, the shading (COLOR: the occlusion baked in) it takes instead of its pick's:
	## a top's is the average over the model's vertices under it, rails' crevices and rollers' gaps
	## and all, which a single vertex (often a bright ridge) doesn't stand for.
	var shading := PackedColorArray()
	var indices := PackedInt32Array()

	func _init(arrays: Array) -> void:
		src = arrays
		rows = row_of(arrays)

	## Each vertex's material row (merged materials' CUSTOM2.r), or empty with one material.
	static func row_of(arrays: Array) -> PackedFloat32Array:
		var out := PackedFloat32Array()
		var c2 = arrays[Mesh.ARRAY_CUSTOM2]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if c2 == null or verts.is_empty():
			return out
		var stride: int = c2.size() / verts.size()
		if stride < 1:
			return out
		out.resize(verts.size())
		for k in verts.size():
			out[k] = float(c2[k * stride])
		return out

	## A quad (corners in order round it) facing `normal`, of material row `row`.
	func quad(p: Array, normal: Vector3, row: int) -> void:
		var base := verts.size()
		var mean := _mean_shading(p, row) if normal.y > 0.5 else Color(-1, -1, -1, -1)
		for k in 4:
			verts.append(p[k])
			normals.append(normal)
			var pick := _nearest(p[k], normal, row)
			picks.append(pick)
			shading.append(mean if mean.a >= 0.0 else _shading_of(pick))
		# Godot's front faces wind clockwise seen from the front.
		var flip: bool = ((p[1] as Vector3) - p[0]).cross((p[2] as Vector3) - p[0]).dot(normal) > 0.0
		for t in [[0, 1, 2], [0, 2, 3]]:
			indices.append(base + t[0])
			indices.append(base + (t[2] if flip else t[1]))
			indices.append(base + (t[1] if flip else t[2]))

	func _shading_of(k: int) -> Color:
		var c = src[Mesh.ARRAY_COLOR]
		return (c as PackedColorArray)[k] if c != null else Color.WHITE

	## The average COLOR of the model's vertices of this row inside the quad's box on the ground
	## (alpha -1: none there, or no COLOR).
	func _mean_shading(p: Array, row: int) -> Color:
		var c = src[Mesh.ARRAY_COLOR]
		if c == null:
			return Color(-1, -1, -1, -1)
		var lo := Vector2(INF, INF)
		var hi := -lo
		for q: Vector3 in p:
			lo = lo.min(Vector2(q.x, q.z))
			hi = hi.max(Vector2(q.x, q.z))
		var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for k in sv.size():
			if not rows.is_empty() and int(rows[k] + 0.5) != row:
				continue
			var v := sv[k]
			if v.x < lo.x or v.x > hi.x or v.z < lo.y or v.z > hi.y:
				continue
			var col: Color = (c as PackedColorArray)[k]
			sum += col
			n += 1
		return sum / float(n) if n > 0 else Color(-1, -1, -1, -1)

	func _nearest(at: Vector3, normal: Vector3, row: int) -> int:
		var sv: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var sn = src[Mesh.ARRAY_NORMAL]
		var best := 0
		var best_d := INF
		for pass_ in 2:
			for k in sv.size():
				if not rows.is_empty() and int(rows[k] + 0.5) != row:
					continue
				if pass_ == 0 and sn != null and (sn[k] as Vector3).dot(normal) < 0.5:
					continue
				var d := sv[k].distance_squared_to(at)
				if d < best_d:
					best_d = d
					best = k
			if best_d < INF:
				break
		return best

	## The surface's arrays: the source's arrays that are there, each corner's from its pick.
	func arrays() -> Array:
		if indices.is_empty():
			return []
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_INDEX] = indices
		var count := (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for a in [Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2,
				Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			var from = src[a]
			if from == null or count == 0:
				continue
			var stride: int = from.size() / count
			var to = from.duplicate()
			to.resize(picks.size() * stride)
			for k in picks.size():
				for e in stride:
					to[k * stride + e] = from[picks[k] * stride + e]
			out[a] = to
		if out[Mesh.ARRAY_COLOR] != null:
			out[Mesh.ARRAY_COLOR] = shading
		return out
