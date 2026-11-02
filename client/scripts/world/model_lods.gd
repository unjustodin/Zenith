extends RefCounted
## Levels of detail for the models in chunks (chunk_view.gd), made on worker threads:
##
## - A shadow stand-in per model: the same shape welded to bare positions, with Godot's automatic
##   LODs, drawn only into the sun's shadow map. The shadow pass drew every caster in view about
##   four times (once per shadow split): on a 20,000-entity base 20 million triangles a frame
##   against 0.5 million in the view itself.
## - LODs for the model itself. Its faces are split by part colours and hard edges, which left
##   Godot's own simplifier nothing to merge (the assembler's 13,900 triangles not at all), so each
##   surface is simplified as welded positions and every corner of a simplified triangle takes the
##   model's own vertex there whose normal fits the triangle best. Godot picks a LOD per chunk by
##   distance, for under Viewport.mesh_lod_threshold pixels of error (Settings > Graphics > Level of
##   detail), so the models near the character stay whole.
##
## Welding and simplifying take up to ~25 ms a model; until a model's job is done its chunks draw
## it whole and it casts its own shadow.

## Surfaces smaller than this keep their own shadow and get no LODs: they would save next to nothing.
const MIN_TRIANGLES := 200
## Jobs at once (terrain meshing shares the worker pool).
const JOBS := 2
## Simplified versions kept per surface, finest first.
const MAX_LODS := 4
## The custom channel formats in a surface's format, which add_surface_from_arrays needs again.
const CUSTOM_FORMATS := 0xFFF << Mesh.ARRAY_FORMAT_CUSTOM_BASE
## Meta on an ArrayMesh holding its surfaces' arrays on the CPU (model_library.gd keeps them):
## Mesh.surface_get_arrays reads them back from the GPU, which stalls the frame.
const ARRAYS_META := &"f3d_arrays"
## Meta on a model's merged material: its rows' materials (material_rows.gd).
const ROWS_META := &"f3d_rows"
const ROW_EDITED_META := &"f3d_row_edited"


## A surface's arrays, from the CPU copy when the mesh has one: a deep copy, safe to change (the
## packed arrays inside an Array are shared, not copied, when it is duplicated shallowly).
static func arrays_of(mesh: Mesh, i: int) -> Array:
	if mesh.has_meta(ARRAYS_META):
		var kept: Array = mesh.get_meta(ARRAYS_META)
		if i < kept.size():
			return (kept[i] as Array).duplicate(true)
	return mesh.surface_get_arrays(i)


static var _uniforms := {}  # Shader -> its uniforms' names


## A copy of a ShaderMaterial, as duplicate() makes it, without duplicate()'s cost: that asks the
## RenderingServer for the shader's parameters and each one's default, which waits for the render
## thread when it runs on its own (seconds over a model's first appearance). The names are asked
## once per shader; unset parameters keep the shader's defaults, as duplicate() copies them.
static func copy_material(source: ShaderMaterial) -> ShaderMaterial:
	var out := ShaderMaterial.new()
	out.resource_name = source.resource_name
	out.shader = source.shader
	out.render_priority = source.render_priority
	out.next_pass = source.next_pass
	# A merged material's rows (a copy of the list: editing the copy's rows leaves the source's),
	# and a row's mark that it was edited (material_rows.gd).
	for meta in [ROWS_META, ROW_EDITED_META]:
		if source.has_meta(meta):
			var value: Variant = source.get_meta(meta)
			out.set_meta(meta, (value as Array).duplicate() if value is Array else value)
	if source.shader == null:
		return out
	if not _uniforms.has(source.shader):
		var names := PackedStringArray()
		for u: Dictionary in source.shader.get_shader_uniform_list():
			names.append(str(u["name"]))
		_uniforms[source.shader] = names
	for name: String in _uniforms[source.shader]:
		var value: Variant = source.get_shader_parameter(name)
		if value != null:
			out.set_shader_parameter(name, value)
	return out


class Job:
	## Per surface of the source mesh: [vertices, normals or null, indices or null, material rows or null].
	var surfaces: Array = []
	## Whether to make LODs for the source mesh's own surfaces too.
	var view_lods := true
	## Whether to make the shadow stand-in (off: only the view LODs, see request_view_lods).
	var proxy := true
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	## LOD size -> indices (ImporterMesh's LODs, for ArrayMesh.add_surface_from_arrays).
	var lods := {}
	## Per source surface: its LODs in its own vertices (empty: none).
	var surface_lods: Array = []

	func run() -> void:
		if not proxy:
			for s in surfaces:
				surface_lods.append(ModelLodsMath.surface_lods(s[0], s[1], s[2], s[3]))
			return
		var welded := ModelLodsMath.weld(surfaces)
		vertices = welded[0]
		indices = welded[1]
		var sign := 1.0
		for s in surfaces:
			sign = ModelLodsMath.winding(s[0], s[1], s[2])
			break
		normals = ModelLodsMath.smooth_normals(vertices, indices, sign)
		var simplified := ModelLodsMath.simplify(vertices, normals, indices)
		indices = simplified[0]
		lods = simplified[1]
		if not view_lods:
			return
		for s in surfaces:
			surface_lods.append(ModelLodsMath.surface_lods(s[0], s[1], s[2], s[3]))


## The arithmetic, apart so the jobs above read plainly. Static: it runs on worker threads.
class ModelLodsMath:
	## [welded vertices, indices into them, original vertex -> welded] for surfaces of
	## [vertices, normals, indices or null]. `rows` (a merged surface's material row per vertex,
	## material_rows.gd) keeps vertices of different materials apart, so simplifying moves no
	## material's border into another's, as when each material was a surface of its own.
	static func weld(surfaces: Array, rows: Variant = null) -> Array:
		var weld_of := {}
		var verts := PackedVector3Array()
		var idx := PackedInt32Array()
		var remap := PackedInt32Array()
		var by_row := rows is PackedFloat32Array and not (rows as PackedFloat32Array).is_empty()
		for s in surfaces:
			var src: PackedVector3Array = s[0]
			var local := PackedInt32Array()
			local.resize(src.size())
			for k in src.size():
				var key: Variant = Vector3i((src[k] * 1024.0).round())
				if by_row:
					var at3: Vector3i = key
					key = Vector4i(at3.x, at3.y, at3.z, int(rows[k]))
				var at: int = weld_of.get(key, -1)
				if at < 0:
					at = verts.size()
					weld_of[key] = at
					verts.append(src[k])
				local[k] = at
			remap.append_array(local)
			if s[2] == null:
				for k in src.size():
					idx.append(local[k])
			else:
				for k in (s[2] as PackedInt32Array):
					idx.append(local[k])
		return [verts, idx, remap]

	## +1 when a triangle's (b - a) x (c - a) points the way its vertices' normals do, -1 when
	## against them (Godot's front faces wind clockwise, so imported models give -1).
	static func winding(verts: PackedVector3Array, normals, idx) -> float:
		if not (normals is PackedVector3Array) or (normals as PackedVector3Array).size() != verts.size():
			return -1.0
		var n: PackedVector3Array = normals
		var count := (idx as PackedInt32Array).size() if idx != null else verts.size()
		var total := 0.0
		for t in range(0, mini(count, 3000) - 2, 3):
			var a := t
			var b := t + 1
			var c := t + 2
			if idx != null:
				a = idx[t]
				b = idx[t + 1]
				c = idx[t + 2]
			total += (verts[b] - verts[a]).cross(verts[c] - verts[a]).dot(n[a] + n[b] + n[c])
		return 1.0 if total >= 0.0 else -1.0

	static func smooth_normals(verts: PackedVector3Array, idx: PackedInt32Array, sign := -1.0) -> PackedVector3Array:
		var sums: Array[Vector3] = []
		sums.resize(verts.size())
		sums.fill(Vector3.ZERO)
		for t in range(0, idx.size() - 2, 3):
			var a := verts[idx[t]]
			var face := (verts[idx[t + 1]] - a).cross(verts[idx[t + 2]] - a) * sign
			for k in 3:
				sums[idx[t + k]] += face
		var out := PackedVector3Array()
		out.resize(verts.size())
		for i in verts.size():
			out[i] = sums[i].normalized() if sums[i].length_squared() > 0.0 else Vector3.UP
		return out

	## [indices, {LOD size: indices}] from Godot's simplifier.
	static func simplify(verts: PackedVector3Array, normals: PackedVector3Array, idx: PackedInt32Array) -> Array:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = idx
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		im.generate_lods(180.0, 180.0, [])
		var lods := {}
		for l in mini(im.get_surface_lod_count(0), MAX_LODS):
			lods[im.get_surface_lod_size(0, l)] = im.get_surface_lod_indices(0, l)
		return [im.get_surface_arrays(0)[Mesh.ARRAY_INDEX], lods]

	## LODs of one surface in its own vertices: {LOD size: indices}, empty when it is too small.
	## `rows`: a merged surface's material row per vertex (weld).
	static func surface_lods(src: PackedVector3Array, src_normals, src_idx, rows: Variant = null) -> Dictionary:
		var triangles := (src_idx as PackedInt32Array).size() / 3 if src_idx != null else src.size() / 3
		if triangles < MIN_TRIANGLES:
			return {}
		var welded := weld([[src, src_normals, src_idx]], rows)
		var verts: PackedVector3Array = welded[0]
		var remap: PackedInt32Array = welded[2]
		# Each welded vertex's own vertices, to pick from.
		var owners: Array = []
		owners.resize(verts.size())
		for k in remap.size():
			if owners[remap[k]] == null:
				owners[remap[k]] = []
			(owners[remap[k]] as Array).append(k)
		var sign := winding(src, src_normals, src_idx)
		var simplified := simplify(verts, smooth_normals(verts, welded[1], sign), welded[1])
		var out := {}
		var has_normals := src_normals is PackedVector3Array and (src_normals as PackedVector3Array).size() == src.size()
		for size in simplified[1]:
			var lod: PackedInt32Array = simplified[1][size]
			var mapped := PackedInt32Array()
			mapped.resize(lod.size())
			for t in range(0, lod.size() - 2, 3):
				var face := (verts[lod[t + 1]] - verts[lod[t]]).cross(verts[lod[t + 2]] - verts[lod[t]]) * sign
				for k in 3:
					var choices: Array = owners[lod[t + k]]
					var best: int = choices[0]
					if has_normals and choices.size() > 1:
						var best_fit := -INF
						for v: int in choices:
							var fit: float = (src_normals as PackedVector3Array)[v].dot(face)
							if fit > best_fit:
								best_fit = fit
								best = v
					mapped[t + k] = best
			out[size] = mapped
		return out


static var _proxies := {}  # Mesh -> ArrayMesh (empty until its job is done), or null: none
static var _ready := {}  # proxy ArrayMesh -> true once it has its shape
static var _view_only := {}  # Mesh -> true: asked for view LODs only (request_view_lods)
static var _lod_copies := {}  # Mesh -> its copy with view LODs (request_view_lods), once made


## The copy of `mesh` with view LODs that request_view_lods made, or null (not asked, not ready,
## or too small to simplify).
static func lod_copy(mesh: Mesh) -> ArrayMesh:
	return _lod_copies.get(mesh)
static var _queue: Array = []  # [Job, proxy, source mesh] waiting for a worker
static var _running: Array = []  # [task id, Job, proxy, source mesh]
## Goes up whenever proxies become ready, so chunks built before can switch to them.
static var generation := 0
## Models given LODs of their own so far (for tests and probes).
static var lod_models := 0
## Main-thread time spent here (for --stutter-probe).
static var main_usec := 0
static var _material: StandardMaterial3D
## The stand-ins' GeometryInstance3D.lod_bias away from the character: Godot picks a mesh's LOD for
## under a pixel of error in the view, but these only shade ground 32 tiles or more away, through
## a shadow map coarser than the screen, so they may simplify sooner (Level of detail setting).
static var lod_bias := 0.25
## Settings > Graphics > Level of detail: the pixels of error the view allows (QUALITY).
static var lod_threshold := 1.0
## Whether models get LODs of their own (off: only shadow stand-ins; for comparisons).
static var view_lods := true

## Settings > Graphics > Level of detail: Viewport.mesh_lod_threshold (pixels of error the view
## allows) and the far shadow stand-ins' lod_bias. Medium (High's preset) was 2 px: on a copy of
## the owner's save 4 px drew 2.0 ms less GPU a frame from the default view (2.6 zoomed out, 3.6
## at the furthest zoom) with no difference to see in screenshots near or far; the stand-ins'
## lod_bias alone was worth 0.04 ms. 6 px (another 0.95 ms) took the dots off green circuits on belts.
const QUALITY := {"high": [1.0, 0.25], "medium": [4.0, 0.15], "low": [4.0, 0.08]}
## Before that (--legacy-render, the stutter probe's "legacy render").
const LEGACY_THRESHOLDS := {"high": 1.0, "medium": 2.0, "low": 4.0}
static var _legacy := "--legacy-render" in OS.get_cmdline_user_args()


## The shadow stand-in for `mesh` (maybe still being made: see is_ready), or null when the model
## casts its own shadow (small, or a creature whose limbs move in the shader). Asking for it also
## starts the model's own LODs.
static func proxy_for(mesh: Mesh) -> ArrayMesh:
	if _proxies.has(mesh):
		return _proxies[mesh]
	var t0 := Time.get_ticks_usec()
	var proxy: ArrayMesh = null
	var job := _job_for(mesh as ArrayMesh)
	main_usec += Time.get_ticks_usec() - t0
	if job != null:
		proxy = ArrayMesh.new()
		_queue.append([job, proxy, mesh])
	_proxies[mesh] = proxy
	return proxy


## View LODs only, no shadow stand-in, for a mesh whose shadow must stay its own: creatures, whose
## limbs bend in the shader (a static stand-in's shadow wouldn't walk). The LODs keep the model's
## own vertices, so the rig's data in them still bends what is left. Asked once per mesh; the
## result is a new mesh (lod_copy), which the asker swaps in: rebuilding a mesh in place while it
## is drawn (as _give_lods does) stalled the renderer for 330-600 ms at a fight's first corpses.
static func request_view_lods(mesh: ArrayMesh) -> void:
	if mesh == null or not view_lods or _view_only.has(mesh):
		return
	_view_only[mesh] = true
	var job := Job.new()
	job.proxy = false
	for i in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return
		var arrays := arrays_of(mesh, i)
		if arrays[Mesh.ARRAY_BONES] != null:
			return
		job.surfaces.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_INDEX], arrays[Mesh.ARRAY_CUSTOM2]])
	_queue.append([job, null, mesh])


static func is_ready(proxy: ArrayMesh) -> bool:
	return _ready.has(proxy)


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _material


static func _job_for(mesh: ArrayMesh) -> Job:
	if mesh == null:
		return null
	var job := Job.new()
	job.view_lods = view_lods
	var triangles := 0
	for i in mesh.get_surface_count():
		var sm := mesh.surface_get_material(i) as ShaderMaterial
		var rig = sm.get_shader_parameter("rig_mode") if sm != null else null
		if rig != null and int(rig) != 0:
			return null
		# A tree's crown is many separate leaf cards, which simplifying merges into other shapes, so
		# each LOD switch as the camera moved relit whole crowns (flicker). Trees keep their own
		# mesh in view; their shadow stand-in still simplifies.
		if sm != null and sm.resource_name.begins_with("leafcard"):
			job.view_lods = false
		if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
			return null
		var arrays := arrays_of(mesh, i)
		if arrays[Mesh.ARRAY_BONES] != null:
			job.view_lods = false
		var idx = arrays[Mesh.ARRAY_INDEX]
		job.surfaces.append([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], idx, arrays[Mesh.ARRAY_CUSTOM2]])
		triangles += (idx as PackedInt32Array).size() / 3 if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return job if triangles >= MIN_TRIANGLES else null


## Starts waiting jobs and shows finished ones. True when some proxy became ready.
static func poll() -> bool:
	var t0 := Time.get_ticks_usec()
	var done := false
	for i in range(_running.size() - 1, -1, -1):
		var entry: Array = _running[i]
		if int(entry[0]) >= 0:  # -1: finish_all() already waited for it
			if not WorkerThreadPool.is_task_completed(entry[0]):
				continue
			WorkerThreadPool.wait_for_task_completion(entry[0])
		_running.remove_at(i)
		var job: Job = entry[1]
		var proxy: ArrayMesh = entry[2]
		if proxy != null and job.indices.size() >= 3:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = job.vertices
			arrays[Mesh.ARRAY_NORMAL] = job.normals
			arrays[Mesh.ARRAY_INDEX] = job.indices
			proxy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], job.lods)
			proxy.surface_set_material(0, material())
			_ready[proxy] = true
			done = true
		if proxy == null and _view_only.has(entry[3]):
			var copy := _copy_with_lods(entry[3] as ArrayMesh, job.surface_lods)
			if copy != null:
				_lod_copies[entry[3]] = copy
		else:
			_give_lods(entry[3] as ArrayMesh, job.surface_lods)
	while _running.size() < JOBS and not _queue.is_empty():
		var next: Array = _queue.pop_front()
		_running.append([WorkerThreadPool.add_task((next[0] as Job).run, false, "model lods"), next[0], next[1], next[2]])
	if done:
		generation += 1
	main_usec += Time.get_ticks_usec() - t0
	return done


## Rebuilds the model's surfaces in place with their LODs: the Mesh stays the same object, so every
## MultiMesh drawing it keeps it.
static func _give_lods(mesh: ArrayMesh, per_surface: Array) -> void:
	if mesh == null or per_surface.size() != mesh.get_surface_count() or per_surface.all(func(l: Dictionary) -> bool: return l.is_empty()):
		return
	var kept: Array = []
	for i in mesh.get_surface_count():
		kept.append([arrays_of(mesh, i), mesh.surface_get_material(i), mesh.surface_get_format(i), mesh.surface_get_name(i)])
	mesh.clear_surfaces()
	for i in kept.size():
		var s: Array = kept[i]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s[0], [], per_surface[i], int(s[2]) & CUSTOM_FORMATS)
		mesh.surface_set_material(i, s[1])
		mesh.surface_set_name(i, s[3])
	lod_models += 1


## A new mesh with `mesh`'s surfaces and these LODs (null when none were made), keeping the CPU
## copy of its arrays.
static func _copy_with_lods(mesh: ArrayMesh, per_surface: Array) -> ArrayMesh:
	if mesh == null or per_surface.size() != mesh.get_surface_count() or per_surface.all(func(l: Dictionary) -> bool: return l.is_empty()):
		return null
	var out := ArrayMesh.new()
	var kept: Array = []
	for i in mesh.get_surface_count():
		var arrays := arrays_of(mesh, i)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], per_surface[i], mesh.surface_get_format(i) & CUSTOM_FORMATS)
		out.surface_set_material(i, mesh.surface_get_material(i))
		out.surface_set_name(i, mesh.surface_get_name(i))
		kept.append(arrays)
	out.set_meta(ARRAYS_META, kept)
	out.resource_name = mesh.resource_name
	lod_models += 1
	return out


static func busy() -> bool:
	return not _queue.is_empty() or not _running.is_empty()


## Waits for the jobs on worker threads (a world leaving the tree, or the game quitting). What they
## made is still shown by the next poll(), and waiting jobs stay queued for the next world.
static func finish_all() -> void:
	for entry in _running:
		if int(entry[0]) >= 0:
			WorkerThreadPool.wait_for_task_completion(entry[0])
			entry[0] = -1


## Settings > Graphics > Level of detail.
static func apply_quality(quality: String, viewport: Viewport) -> void:
	var q: Array = QUALITY.get(quality, QUALITY["high"])
	if viewport != null:
		viewport.mesh_lod_threshold = float(LEGACY_THRESHOLDS.get(quality, 1.0)) if _legacy else q[0]
	lod_bias = q[1]
	lod_threshold = q[0]
