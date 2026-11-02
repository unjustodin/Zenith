extends Node
## Far chunks merged (hierarchical LOD, docs/PERFORMANCE-PLAN.md 2). Past MERGE_FROM tiles from the
## camera a chunk's buildings are drawn as one mesh of one surface instead of a MultiMesh per model,
## per moving part and per surface (models average six surfaces, each a draw, and the shadow pass
## draws them again per split): one draw, one engine object, no moving parts. It is built on worker
## threads from each model simplified once as a whole, with the colour its materials would give each
## vertex baked in (Bake), and drawn with one shared material (far_merged.gdshader). Where the chunk's
## shadows can reach the view (world.gd's shadow tiers) the same mesh casts them.
##
## Trees and plants (cut-out leaf cards in their own shader), ore, fish, and nests and worms (moved
## in the shader) keep their MultiMeshes (KEEP_TYPES). Picking, ghosts, wires, alerts and the fog
## read world.gd's records or hide whole chunks, so they don't change.
##
## A chunk going far keeps its MultiMeshes until its merged mesh is made, then hides them (nothing is
## built); coming near again it shows them, unless something in it changed meanwhile (a build lets
## them go): then they are made again within world.gd's frame budget and the merged mesh goes once
## they are all in. A chunk first seen far isn't built in full until it comes near.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const MaterialRows := preload("res://scripts/world/material_rows.gd")
const ModelTextures := preload("res://scripts/world/model_textures.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const MergedShader := preload("res://shaders/far_merged.gdshader")
const FactorioAlphaShader := preload("res://shaders/factorio_material_alpha.gdshader")
const FactorioLeafShader := preload("res://shaders/factorio_material_leaf.gdshader")

const CHUNK := 32
## A chunk is merged once its nearest point is this far from the camera (tiles), or the sun's shadow
## distance if that is further (past it shadows fade out, so the simpler shapes casting them don't
## show), and drawn in full again once nearer than that less SLACK.
const MERGE_FROM := 128.0
const SLACK := 24.0
## Chunks within this distance of the focus (tiles) are always drawn in full: the character's
## surroundings animate and are what the player works on, however far the camera is pulled back.
const NEAR_FOCUS := 40.0
## Entity types left to their own MultiMeshes in far chunks.
const KEEP_TYPES := {"tree": true, "plant": true, "resource": true, "fish": true, "unit-spawner": true,
	"turret": true, "spider-leg": true}
## How simple each model is merged (tiles): the simplifier's coarsest level within SIMPLIFY_ERROR, then
## its vertices clustered in CELL-sized cubes (Bake): about two pixels at MERGE_FROM in a 900-pixel
## window. Times the square root of the Level of detail setting's pixels of error (model_lods.gd
## QUALITY: high 1, medium 1.4, low 2), as set when a model is first merged.
const SIMPLIFY_ERROR := 0.25
const CELL := 0.2
## Worker jobs at once: models baked and chunks merged (the pool also meshes terrain and loads models).
const BAKE_JOBS := 2
const MERGE_JOBS := 2
## Main-thread time a frame for gathering far chunks' entities (at least sixteen) and for putting
## finished merges in (at least one); seconds between looks at which chunks are far (sooner when
## the camera moved 8 tiles).
const COLLECT_USEC := 1000
const INSTALL_USEC := 1500
const CHECK_INTERVAL := 0.5

## Where a chunk's merge stands (State.phase).
enum { IDLE, ASKED, GATHERING, WAITING, MERGING }

## Settings > Graphics > Merge far buildings.
var enabled := true
## --far-merge-from=<tiles>: merge from this distance instead (screenshots of merged buildings up close).
var merge_from := 0.0
var world  # world.gd

## Per mesh: its Bake (done or not), and whether it can be merged at all.
static var _bakes := {}
static var _bakeable := {}
static var _material: ShaderMaterial
## Chunks whose builds asked for a merge (built()), taken in by _collect.
static var _asked: Array = []

var _check_timer := CHECK_INTERVAL
var _last_camera := Vector3.INF
var _last_enabled := true
var _far_count := 0
## [ChunkView, serial] being gathered, gathered and waiting for their models' bakes; merges running
## [task id, Merge, ChunkView]; bakes running [task id, Bake] and waiting.
var _collecting: Array = []
var _waiting: Array = []
var _merging: Array = []
var _baking: Array = []
var _bake_queue: Array = []
## Bakes finished and chunks gathered so far, and as last looked at.
var _progress := 0
var _stamp := -1
## Main-thread and worker time spent, and merges made (for the probe and tests).
var main_usec := 0
var worker_usec := 0
var merges_made := 0


## What a chunk's merged drawing stands at (ChunkView.far).
class State:
	## Wanted merged (far from the camera).
	var far := false
	## The merged mesh stands for the chunk's mergeable entities: its builds leave them out.
	var covers := false
	## Those entities have MultiMeshes now (the last build didn't leave them out): drawn, or hidden
	## (`hidden`) while the merged mesh stands for them, to be shown again without a build if the
	## chunk comes near before anything in it changes.
	var full := false
	var hidden: Array = []
	var phase := IDLE
	## Goes up with every new merge asked for: work of an older serial is dropped.
	var serial := 0
	var node: MeshInstance3D
	var triangles := 0
	## Gathering: the entities still to look at and the next one.
	var recs: Array = []
	var next := 0
	## Gathered: Mesh -> Array of Transform3D, and placeholders [Mesh, Transform3D, Color].
	var groups := {}
	var tinted: Array = []
	## In the merged mesh: Mesh -> instances, and whether it has placeholders.
	var counts := {}
	var placeholders := false
	## Looked at while waiting and found models not baked yet.
	var checked := false
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A model baked for merging, once per model on a worker thread: all its surfaces as one, with the
## colour each vertex is drawn in baked in (as factorio_material.gdshaderinc works it out: part colour
## or palette, the model's tint, greying, baked occlusion), simplified as a whole (welded positions,
## so parts and surfaces collapse together, which the models' own per-surface LODs can't), each
## simplified corner taking the model's own vertex there whose normal fits best (as model_lods.gd);
## then clustered: vertices in a CELL-sized cube become one, at their average place and colour, and
## triangles left with no area go. That last step is what brings walls of separate bricks, lattice
## poles and ties of rails down: the simplifier keeps every separate piece.
class Bake:
	## Per surface: [vertices, normals, COLOR, CUSTOM1, indices, params per row ({} leaves the row
	## out), each vertex's row (CUSTOM2) or null with one row, UV (textured models)]
	var surfaces: Array = []
	var simplify_error := SIMPLIFY_ERROR
	var cell := CELL
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var done := false
	var usec := 0

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		var all_verts := PackedVector3Array()
		var all_normals := PackedVector3Array()
		var all_colors := PackedColorArray()
		var all_idx := PackedInt32Array()
		for s: Array in surfaces:
			_surface(s, all_verts, all_normals, all_colors, all_idx)
		surfaces = []
		var idx := all_idx
		for level: Array in _levels(all_verts, all_normals, all_idx):
			if float(level[0]) <= simplify_error:
				idx = level[1]
		_cluster(all_verts, all_colors, idx)
		usec = Time.get_ticks_usec() - t0

	## The model's triangles `idx` with vertices clustered by `cell` (none: just the ones used).
	func _cluster(src: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array) -> void:
		var map := PackedInt32Array()
		map.resize(src.size())
		map.fill(-1)
		var of_cell := {}
		var sums := PackedVector3Array()
		var tints := PackedVector3Array()
		var alphas := PackedFloat32Array()
		var counts := PackedInt32Array()
		for k in idx:
			if map[k] >= 0:
				continue
			var key = Vector3i((src[k] / cell).floor()) if cell > 0.0 else k
			var at: int = of_cell.get(key, -1)
			if at < 0:
				at = counts.size()
				of_cell[key] = at
				sums.append(Vector3.ZERO)
				tints.append(Vector3.ZERO)
				alphas.append(cols[k].a)
				counts.append(0)
			map[k] = at
			sums[at] += src[k]
			tints[at] += Vector3(cols[k].r, cols[k].g, cols[k].b)
			counts[at] += 1
		# Triangles left with area, each once (keeping its winding: both sides of a plate stay).
		var used := PackedInt32Array()
		used.resize(counts.size())
		used.fill(-1)
		var seen := {}
		for t in range(0, idx.size() - 2, 3):
			var a := map[idx[t]]
			var b := map[idx[t + 1]]
			var c := map[idx[t + 2]]
			if a == b or b == c or a == c:
				continue
			var key := Vector3i(a, b, c) if a < b and a < c else (Vector3i(b, c, a) if b < c else Vector3i(c, a, b))
			if seen.has(key):
				continue
			seen[key] = true
			for v in [a, b, c]:
				if used[v] < 0:
					used[v] = verts.size()
					var n := float(counts[v])
					verts.append(sums[v] / n)
					var rgb := tints[v] / n
					colors.append(Color(rgb.x, rgb.y, rgb.z, alphas[v]))
				indices.append(used[v])

	## [[error, indices into the model's own vertices], ...], finest first, from Godot's simplifier
	## over the welded positions; [] for a model too small to bother.
	static func _levels(src: PackedVector3Array, src_normals: PackedVector3Array, idx: PackedInt32Array) -> Array:
		if idx.size() / 3 < ModelLods.MIN_TRIANGLES:
			return []
		var welded := ModelLods.ModelLodsMath.weld([[src, src_normals, idx]])
		var wv: PackedVector3Array = welded[0]
		var wi: PackedInt32Array = welded[1]
		var remap: PackedInt32Array = welded[2]
		var owners: Array = []
		owners.resize(wv.size())
		for k in remap.size():
			if owners[remap[k]] == null:
				owners[remap[k]] = []
			(owners[remap[k]] as Array).append(k)
		var sign := ModelLods.ModelLodsMath.winding(src, src_normals, idx)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = wv
		arrays[Mesh.ARRAY_NORMAL] = ModelLods.ModelLodsMath.smooth_normals(wv, wi, sign)
		arrays[Mesh.ARRAY_INDEX] = wi
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		im.generate_lods(180.0, 180.0, [])
		var out: Array = []
		for l in im.get_surface_lod_count(0):
			var lod := im.get_surface_lod_indices(0, l)
			var mapped := PackedInt32Array()
			mapped.resize(lod.size())
			for t in range(0, lod.size() - 2, 3):
				var face := (wv[lod[t + 1]] - wv[lod[t]]).cross(wv[lod[t + 2]] - wv[lod[t]]) * sign
				for k in 3:
					var choices: Array = owners[lod[t + k]]
					var best: int = choices[0]
					if choices.size() > 1:
						var best_fit := -INF
						for v: int in choices:
							var fit := src_normals[v].dot(face)
							if fit > best_fit:
								best_fit = fit
								best = v
					mapped[t + k] = best
			out.append([im.get_surface_lod_size(0, l), mapped])
		out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		return out

	## One surface's vertices, normals, colours and indices onto the model's.
	static func _surface(s: Array, all_verts: PackedVector3Array, all_normals: PackedVector3Array, all_colors: PackedColorArray,
			all_idx: PackedInt32Array) -> void:
		var src: PackedVector3Array = s[0]
		var n := src.size()
		var base := all_verts.size()
		all_verts.append_array(src)
		if s[1] is PackedVector3Array and (s[1] as PackedVector3Array).size() == n:
			all_normals.append_array(s[1])
		else:
			for k in n:
				all_normals.append(Vector3.UP)
		var params: Array = s[5]
		var rows := PackedFloat32Array()
		if s[6] is PackedFloat32Array and (s[6] as PackedFloat32Array).size() == n:
			rows = s[6]
		var last := params.size() - 1
		if s[4] is PackedInt32Array and not (s[4] as PackedInt32Array).is_empty():
			var idx: PackedInt32Array = s[4]
			for t in range(0, idx.size() - 2, 3):
				# A row left out (see-through light that fades away) drops its triangles.
				if (params[clampi(int(rows[idx[t]]), 0, last) if not rows.is_empty() else 0] as Dictionary).is_empty():
					continue
				all_idx.append(idx[t] + base)
				all_idx.append(idx[t + 1] + base)
				all_idx.append(idx[t + 2] + base)
		else:
			for k in range(0, n - 2, 3):
				if (params[clampi(int(rows[k]), 0, last) if not rows.is_empty() else 0] as Dictionary).is_empty():
					continue
				all_idx.append(k + base)
				all_idx.append(k + 1 + base)
				all_idx.append(k + 2 + base)
		var vcol := PackedColorArray()
		if s[2] is PackedColorArray and (s[2] as PackedColorArray).size() == n:
			vcol = s[2]
		var c1 := PackedFloat32Array()
		if s[3] is PackedFloat32Array and (s[3] as PackedFloat32Array).size() == n * 4:
			c1 = s[3]
		var row := -1
		var albedo: Color
		var tint: Color
		var part_share := 0.0
		var tinted := false
		var desaturate := 0.0
		var value := 1.0
		var ao_strength := 1.0
		var light := 1.0
		var metallic := 0.0
		# A textured model (never merged, so one row): each vertex takes its texture's colour there
		# (a small copy of it).
		var tex: Image = (params[0] as Dictionary).get("tex")
		var uv := PackedVector2Array()
		if tex != null and s.size() > 7 and s[7] is PackedVector2Array and (s[7] as PackedVector2Array).size() == n:
			uv = s[7]
		for v in n:
			var r := clampi(int(rows[v]), 0, last) if not rows.is_empty() else 0
			if r != row:
				row = r
				var p: Dictionary = params[r]
				if p.is_empty():
					p = params.filter(func(q: Dictionary) -> bool: return not q.is_empty())[0]  # unused vertices
				albedo = p["albedo"]
				tint = p["tint"]
				part_share = float(p["part_data"]) if bool(p["part_colors"]) else 0.0
				tinted = float(p["vertex_data"]) > 0.5 and not vcol.is_empty()
				desaturate = p["desaturate"]
				value = p["value"]
				ao_strength = p["ao_strength"]
				light = p["light"]
				metallic = p["metallic"]
			var rgb := Vector3(albedo.r, albedo.g, albedo.b)
			var pc := 0.0
			if not uv.is_empty():
				var t := uv[v]
				var w := tex.get_width()
				var h := tex.get_height()
				var c := tex.get_pixel(posmod(int(floor(t.x * w)), w), posmod(int(floor(t.y * h)), h)).srgb_to_linear()
				rgb *= Vector3(c.r, c.g, c.b)
				pc = 1.0
			elif part_share > 0.0 and not c1.is_empty():
				# Part colours are kept with headroom (rgb / 4, share * 0.25) unless the share is above 0.25.
				var a := c1[v * 4 + 3]
				var headroom := a <= 0.2501
				pc = clampf(a / 0.25 if headroom else a, 0.0, 1.0) * part_share
				rgb = rgb.lerp(Vector3(c1[v * 4], c1[v * 4 + 1], c1[v * 4 + 2]) * (4.0 if headroom else 1.0), pc)
			var ao := 1.0
			if tinted:
				var c := vcol[v]
				rgb *= Vector3(c.r, c.g, c.b)
				ao = c.a
			rgb *= Vector3(tint.r, tint.g, tint.b)
			var lum := rgb.dot(Vector3(0.299, 0.587, 0.114))
			rgb = rgb.lerp(Vector3(lum, lum, lum), desaturate * (1.0 - pc)) * lerpf(value, 1.0, pc)
			rgb *= lerpf(1.0, lerpf(1.0, ao, ao_strength), 0.65) * light
			var metal := clampf(metallic * lerpf(1.0, 0.1, pc), 0.0, 1.0)
			var packed := float(roundi(pc * 15.0) + 16 * roundi(metal * 15.0)) / 255.0
			all_colors.append(Color(sqrt(clampf(rgb.x, 0.0, 1.0)), sqrt(clampf(rgb.y, 0.0, 1.0)), sqrt(clampf(rgb.z, 0.0, 1.0)), packed))


## A chunk's merged mesh, made on a worker thread: every instance's baked model moved into place.
## The ArrayMesh is made here too (its arrays are packed on this thread; the renderer takes them at
## its next sync), so the main thread only hands it to the chunk's MeshInstance3D.
class Merge:
	var serial := 0
	var groups: Array = []  # [Bake, Array of Transform3D, Mesh]
	var tinted: Array = []  # [Bake, Transform3D, Color]
	var material: Material
	var mesh: ArrayMesh
	var triangles := 0
	var usec := 0

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		var all: Array = []
		var nf := 0
		for g: Array in groups:
			var bake: Bake = g[0]
			for xform: Transform3D in g[1]:
				all.append([bake, xform, null])
			nf += bake.indices.size() * (g[1] as Array).size()
		for t: Array in tinted:
			all.append(t)
			nf += (t[0] as Bake).indices.size()
		var verts := PackedVector3Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()
		indices.resize(nf)
		var wf := 0
		for entry: Array in all:
			var bake: Bake = entry[0]
			var xform: Transform3D = entry[1]
			var base := verts.size()
			verts.append_array(xform * bake.verts)
			if entry[2] == null:
				colors.append_array(bake.colors)
			else:
				# Placeholders: the prototype's colour, as a square root as the bake's are.
				var tint: Color = entry[2]
				for c in bake.colors:
					colors.append(Color(c.r * sqrt(tint.r), c.g * sqrt(tint.g), c.b * sqrt(tint.b), c.a))
			for k in bake.indices:
				indices[wf] = k + base
				wf += 1
		triangles = nf / 3
		if nf >= 3:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_INDEX] = indices
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
			mesh.surface_set_material(0, material)
		groups = []
		tinted = []
		usec = Time.get_ticks_usec() - t0


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = MergedShader
	return _material


func _ready() -> void:
	material()  # Godot sets a shader up with its first material: here rather than at the first merge
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--far-merge-from="):
			merge_from = float(arg.get_slice("=", 1))


func _exit_tree() -> void:
	for entry in _baking + _merging:
		WorkerThreadPool.wait_for_task_completion(entry[0])
	_baking.clear()
	_merging.clear()


# --- Hooks from chunk_view.gd ----------------------------------------------------------------

## Whether a build of this chunk leaves out what its merged mesh draws (or is about to).
static func skips(cv) -> bool:
	var s: State = cv.far
	return s.far and (s.covers or not s.full)


## Whether an entity of this type drawn with `mesh` (null: a placeholder) goes in a merged mesh.
static func merges(proto_type: String, mesh: Mesh) -> bool:
	return not KEEP_TYPES.has(proto_type) and (mesh == null or bakeable(mesh))


## After a chunk's build (`skipped`: whether it left the merged entities out), or after it added
## MultiMeshes a build left for later (`skipped` null).
static func built(cv, skipped) -> void:
	var s: State = cv.far
	if skipped != null:
		s.full = not skipped
		if skipped:
			s.hidden = []  # the build let them go
	if s.node != null:
		if not s.far and cv.pending.is_empty():
			_drop_merged(s)  # near again, every MultiMesh in
		elif s.far and s.covers and s.full:
			_hide_full(cv)  # MultiMeshes added while the merged mesh stands for them
	if skipped != null and s.far:
		ask(cv)  # what it holds may have changed


## Hides the chunk's MultiMeshes of what its merged mesh draws, and their shadow stand-ins.
static func _hide_full(cv) -> void:
	var s: State = cv.far
	var hid := false
	for key in cv._nodes:
		var mesh = key[0] if key is Array else key
		if (mesh is Mesh and s.counts.has(mesh)) or (key is String and s.placeholders):
			var mmi: MultiMeshInstance3D = cv._nodes[key]
			if mmi.visible:
				mmi.visible = false
				s.hidden.append(mmi)
				hid = true
	if hid:
		cv._apply_shadows()


## Whether this MultiMesh is hidden behind the merged mesh (chunk_view.gd keeps its stand-in's
## shadow off then).
static func hides(cv, mmi: MultiMeshInstance3D) -> bool:
	var s: State = cv.far
	return not s.hidden.is_empty() and s.hidden.has(mmi)


static func _drop_merged(s: State) -> void:
	s.node.queue_free()
	s.node = null
	s.covers = false
	s.triangles = 0


## The shadow casting the chunk's tier gives (chunk_view.gd _apply_shadows): a merged chunk inside the
## region whose shadows reach the view casts through its one simplified mesh.
static func set_cast(cv, cast: GeometryInstance3D.ShadowCastingSetting) -> void:
	var s: State = cv.far
	s.cast = cast
	if s.node != null and s.node.cast_shadow != cast:
		s.node.cast_shadow = cast


## Gathers a far chunk again and merges it.
static func ask(cv) -> void:
	var s: State = cv.far
	s.serial += 1
	s.phase = ASKED
	_asked.append(cv)


# --- Which meshes merge, and how ---------------------------------------------------------------

## A mesh merges when its arrays are on the CPU (model_library.gd keeps them; primitive meshes make
## them there) and none of its surfaces moves in the shader (creatures' rigs) or is cut out (leaves).
static func bakeable(mesh: Mesh) -> bool:
	if _bakeable.has(mesh):
		return _bakeable[mesh]
	var ok := mesh is PrimitiveMesh or (mesh is ArrayMesh and mesh.has_meta(ModelLods.ARRAYS_META))
	if ok:
		for i in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES:
				ok = false
				break
			var sm := mesh.surface_get_material(i) as ShaderMaterial
			if sm != null and (sm.shader == FactorioLeafShader or int(_param(sm, "rig_mode", 0)) != 0):
				ok = false
				break
	_bakeable[mesh] = ok
	return ok


static func _param(sm: ShaderMaterial, name: String, default: Variant) -> Variant:
	var v: Variant = sm.get_shader_parameter(name)
	return default if v == null else v


## What a surface's material makes of its vertices (the uniforms factorio_material reads, with its
## defaults), or {} for a surface left out: see-through light that fades away (a thruster's plume).
static func _surface_params(material: Material) -> Dictionary:
	var p := {"albedo": Color(0.2, 0.2, 0.2), "tint": Color.WHITE, "part_data": 0.0, "part_colors": true, "vertex_data": 0.0,
		"desaturate": 0.0, "value": 1.0, "ao_strength": 1.0, "light": 1.0, "metallic": 0.0}
	var sm := material as ShaderMaterial
	if sm != null:
		if sm.shader == FactorioAlphaShader and bool(_param(sm, "glow_fades", false)):
			return {}
		p["albedo"] = (_param(sm, "albedo", Color.WHITE) as Color).srgb_to_linear()
		p["tint"] = (_param(sm, "model_tint", Color.WHITE) as Color).srgb_to_linear()
		p["part_data"] = float(_param(sm, "part_data", 0.0))
		p["part_colors"] = bool(_param(sm, "part_colors", true))
		p["vertex_data"] = float(_param(sm, "vertex_data", 1.0))
		p["desaturate"] = float(_param(sm, "desaturate", 0.15))
		p["value"] = float(_param(sm, "value", 0.9))
		p["ao_strength"] = float(_param(sm, "ao_strength", 1.0))
		p["metallic"] = float(_param(sm, "metallic", 0.0))
		var albedo_tex: Texture2D = _param(sm, "albedo_tex", null) if bool(_param(sm, "use_albedo_tex", false)) else null
		if albedo_tex != null and albedo_tex.has_meta(ModelTextures.SMALL_META):
			p["tex"] = albedo_tex.get_meta(ModelTextures.SMALL_META)
		# Burnt remnants darken the part colours' light too; glowing parts are drawn half lit.
		p["light"] = (_param(sm, "part_light", Vector2(0.95, 0.6)) as Vector2).x / 0.95
		if bool(_param(sm, "activity_glow", false)):
			p["light"] = float(p["light"]) * 0.65
	elif material is BaseMaterial3D:
		p["albedo"] = (material as BaseMaterial3D).albedo_color.srgb_to_linear()
		p["metallic"] = (material as BaseMaterial3D).metallic
		if (material as BaseMaterial3D).vertex_color_use_as_albedo:
			p["albedo"] = Color.WHITE  # placeholders: the instance's colour comes on top
	return p


## The model's Bake when it is done; else starts it and returns null.
func _bake_for(mesh: Mesh) -> Bake:
	var bake: Bake = _bakes.get(mesh)
	if bake != null:
		return bake if bake.done else null
	bake = Bake.new()
	var coarser := sqrt(ModelLods.lod_threshold)
	bake.simplify_error = SIMPLIFY_ERROR * coarser
	bake.cell = CELL * coarser
	var kept: Array = mesh.get_meta(ModelLods.ARRAYS_META) if mesh.has_meta(ModelLods.ARRAYS_META) else []
	for i in mesh.get_surface_count():
		# A merged surface (material_rows.gd): each row's material, CUSTOM2 each vertex's row.
		var material := mesh.surface_get_material(i)
		var rows := MaterialRows.rows(material)
		var params: Array = []
		for m in (rows if not rows.is_empty() else [material]):
			params.append(_surface_params(m))
		if params.all(func(p: Dictionary) -> bool: return p.is_empty()):
			continue
		var a: Array = kept[i] if i < kept.size() else (mesh as PrimitiveMesh).get_mesh_arrays()
		bake.surfaces.append([a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], a[Mesh.ARRAY_COLOR], a[Mesh.ARRAY_CUSTOM1],
			a[Mesh.ARRAY_INDEX], params, a[Mesh.ARRAY_CUSTOM2] if not rows.is_empty() else null, a[Mesh.ARRAY_TEX_UV]])
	_bakes[mesh] = bake
	_bake_queue.append(bake)
	return null


# --- Each frame ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	_decide(delta)
	_collect()
	_poll_bakes()
	_start_merges()
	_install()
	var spent := Time.get_ticks_usec() - t0
	main_usec += spent
	world.prof["far"] = int(world.prof.get("far", 0)) + spent


## Which chunks are far: from the camera, MERGE_FROM with SLACK either way, never near the focus. A
## chunk going far is gathered for merging; one coming near is built in full again.
func _decide(delta: float) -> void:
	_check_timer += delta
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var at := cam.global_position if cam != null else Vector3(world.focus().x, 30.0, world.focus().y)
	if _check_timer < CHECK_INTERVAL and enabled == _last_enabled and at.distance_to(_last_camera) < 8.0:
		return
	if not enabled and not _last_enabled and _far_count == 0:
		return  # off, and nothing left merged
	_check_timer = 0.0
	_last_camera = at
	_last_enabled = enabled
	var focus: Vector2 = world.focus()
	var from := MERGE_FROM
	if world.sun != null:
		from = maxf(from, world.sun.directional_shadow_max_distance)
	if merge_from > 0.0:
		from = merge_from
	_far_count = 0
	for c: Vector2i in world.chunks:
		var cv = world.chunks[c]
		var s: State = cv.far
		var rect := Rect2(Vector2(c * CHUNK), Vector2(CHUNK, CHUNK))
		var lo := Vector3(rect.position.x, 0.0, rect.position.y)
		var d := at.distance_to(at.clamp(lo, lo + Vector3(CHUNK, 8.0, CHUNK)))
		var far := s.far
		var near_focus := focus.distance_to(focus.clamp(rect.position, rect.end))
		if merge_from > 0.0 and merge_from < NEAR_FOCUS:
			near_focus = INF  # --far-merge-from under NEAR_FOCUS: merged up close, for screenshots
		if not enabled or near_focus < NEAR_FOCUS:
			far = false
		elif d > from and near_focus > NEAR_FOCUS + SLACK * 0.5:
			far = true
		elif d < from - SLACK:
			far = false
		if far:
			_far_count += 1
		if far == s.far:
			continue
		s.far = far
		if far:
			if cv.loaded:
				ask(cv)
		else:
			s.serial += 1  # whatever was on its way is dropped
			s.phase = IDLE
			if not s.hidden.is_empty():
				# Its MultiMeshes are still there: shown again, no build.
				for mmi: MultiMeshInstance3D in s.hidden:
					if is_instance_valid(mmi):
						mmi.visible = true
				s.hidden = []
				cv._apply_shadows()
				if s.node != null:
					_drop_merged(s)
			elif not s.full:
				world.redraw(c)  # its MultiMeshes are made again; the merged mesh goes once they are in


## Gathers far chunks' mergeable entities, nearest the focus first, a slice at a time within
## COLLECT_USEC (on the main thread: the models' tables aren't for threads).
func _collect() -> void:
	if not _asked.is_empty():
		var focus: Vector2 = world.focus()
		var fresh: Array = []
		for cv in _asked:
			# A snapshot still arriving in parts is built again (and asks again) as each comes.
			if is_instance_valid(cv) and world.chunks.get(cv.coord) == cv and cv.far.phase == ASKED and not cv.is_incomplete():
				var s: State = cv.far
				s.phase = GATHERING
				s.recs = cv.entities.values()
				s.next = 0
				s.groups = {}
				s.tinted = []
				fresh.append([cv, s.serial])
		_asked.clear()
		var nearer := func(a: Array, b: Array) -> bool:
			return (Vector2(a[0].coord * CHUNK) - focus).length_squared() < (Vector2(b[0].coord * CHUNK) - focus).length_squared()
		fresh.sort_custom(nearer)
		_collecting.append_array(fresh)
	var started := Time.get_ticks_usec()
	var looked := 0
	while not _collecting.is_empty():
		var entry: Array = _collecting[0]
		if not _current(entry, GATHERING):
			_collecting.pop_front()
			continue
		var cv = entry[0]
		var s: State = cv.far
		while s.next < s.recs.size():
			if looked >= 16 and (looked & 15) == 0 and Time.get_ticks_usec() - started > COLLECT_USEC:
				return
			_gather(cv, s, s.recs[s.next])
			s.next += 1
			looked += 1
		_collecting.pop_front()
		s.recs = []
		s.phase = WAITING
		s.checked = false
		_waiting.append(entry)
		_progress += 1


## Whether a queued [ChunkView, serial] is still the chunk's latest, in `phase`.
func _current(entry: Array, phase: int) -> bool:
	var cv = entry[0]
	if not is_instance_valid(cv) or world.chunks.get(cv.coord) != cv:
		return false
	var s: State = cv.far
	return s.far and s.serial == int(entry[1]) and s.phase == phase


## One entity into its chunk's groups, as chunk_view.gd build_entities would draw it (merges() true).
func _gather(cv, s: State, rec) -> void:
	var protos = world.protos
	var proto = protos.entity(rec.proto_id)
	if proto == null or rec.extra.has("gh") or rec.extra.has("tg") or ModelLibrary.hidden(proto.name) or KEEP_TYPES.has(proto.type):
		return
	if ModelLibrary.REMNANT_TYPES.has(proto.type):
		var remnant: Array = cv._remnant(protos, proto, rec)
		if not remnant.is_empty() and bakeable(remnant[0]):
			_add(s, remnant[0], remnant[1])
		return
	if not ModelLibrary.entity_ready(proto.name, proto.type, rec.extra, rec.dir):
		return
	var mesh := ModelLibrary.mesh_for_entity(proto.name, proto.type, rec.extra, rec.dir)
	if mesh == null:
		var color: Color = ModelLibrary.NEUTRAL_COLOR if ModelLibrary.NEUTRAL_PROTOS.has(proto.name) else proto.color
		var shape: Mesh = Visuals.cone_mesh() if Visuals.is_cone(proto) else Visuals.box_mesh()
		s.tinted.append([shape, Visuals.placeholder_transform(proto, rec.pos, rec.dir, Visuals.height_for(proto)), color.srgb_to_linear()])
		return
	if not bakeable(mesh):
		return
	var xform: Transform3D = cv._model_transform(proto, rec)
	_add(s, mesh, xform)
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for_entity(proto.name, proto.type, rec.extra, rec.dir):
		# Parts at rest; lit parts (signal lenses) show only by state.
		if part.lit or part.mesh == null or not bakeable(part.mesh):
			continue
		_add(s, part.mesh, Transform3D(Basis.IDENTITY, xform.origin) if part.upright else xform)
	if rec.extra.has("cb"):
		for place: Array in ModelLibrary.cargo_places(int(rec.extra["cb"]), xform.origin):
			if ModelLibrary.ready(place[0]):
				var piece := ModelLibrary.mesh_for(place[0])
				if piece != null and bakeable(piece):
					_add(s, piece, Transform3D(Basis(), place[1]))


static func _add(s: State, mesh: Mesh, xform: Transform3D) -> void:
	if not s.groups.has(mesh):
		s.groups[mesh] = []
	(s.groups[mesh] as Array).append(xform)


## Takes in finished bakes and starts waiting ones.
func _poll_bakes() -> void:
	for i in range(_baking.size() - 1, -1, -1):
		var entry: Array = _baking[i]
		if not WorkerThreadPool.is_task_completed(entry[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(entry[0])
		var bake: Bake = entry[1]
		bake.done = true
		worker_usec += bake.usec
		_baking.remove_at(i)
		_progress += 1
	while _baking.size() < BAKE_JOBS and not _bake_queue.is_empty():
		var bake: Bake = _bake_queue.pop_front()
		_baking.append([WorkerThreadPool.add_task(bake.run, false, "far bake"), bake])


## Merges gathered chunks whose models are all baked, in the order gathered (nearest first). Looked
## at again only when a bake finished or a chunk was gathered since last time.
func _start_merges() -> void:
	var stamp := _progress
	var changed := stamp != _stamp
	_stamp = stamp
	var i := 0
	while i < _waiting.size() and _merging.size() < MERGE_JOBS:
		var entry: Array = _waiting[i]
		if not _current(entry, WAITING):
			_waiting.remove_at(i)
			continue
		var s: State = entry[0].far
		if not changed and s.checked:
			i += 1
			continue
		var ready := true
		var groups: Array = []
		for mesh: Mesh in s.groups:
			var bake := _bake_for(mesh)
			if bake == null:
				ready = false
			elif ready:
				groups.append([bake, s.groups[mesh], mesh])
		var tinted: Array = []
		for t: Array in s.tinted:
			var bake := _bake_for(t[0])
			if bake == null:
				ready = false
			elif ready:
				tinted.append([bake, t[1], t[2]])
		if not ready:
			s.checked = true
			i += 1
			continue
		_waiting.remove_at(i)
		s.phase = MERGING
		var merge := Merge.new()
		merge.serial = s.serial
		merge.groups = groups
		merge.tinted = tinted
		merge.material = material()
		s.counts = {}
		for g: Array in groups:
			s.counts[g[2]] = (g[1] as Array).size()
		s.placeholders = not tinted.is_empty()
		s.groups = {}
		s.tinted = []
		_merging.append([WorkerThreadPool.add_task(merge.run, false, "far merge"), merge, entry[0]])


## Puts finished merges in, within INSTALL_USEC.
func _install() -> void:
	var started := Time.get_ticks_usec()
	var i := 0
	while i < _merging.size():
		var entry: Array = _merging[i]
		if not WorkerThreadPool.is_task_completed(entry[0]):
			i += 1
			continue
		if Time.get_ticks_usec() - started > INSTALL_USEC:
			return
		WorkerThreadPool.wait_for_task_completion(entry[0])
		_merging.remove_at(i)
		var merge: Merge = entry[1]
		worker_usec += merge.usec
		if not _current([entry[2], merge.serial], MERGING):
			continue  # gathered again since, near again, or gone
		var cv = entry[2]
		var s: State = cv.far
		s.phase = IDLE
		if s.node == null:
			s.node = MeshInstance3D.new()
			s.node.name = "Merged"
			s.node.cast_shadow = s.cast
			cv.add_child(s.node)
		s.node.mesh = merge.mesh
		s.triangles = merge.triangles
		s.covers = true
		merges_made += 1
		cv.count("far_merges")
		s.node.visible = true
		if s.full:
			_hide_full(cv)  # kept hidden: coming near again before anything changes shows them


## [merged chunks drawn, their triangles, chunks far] now (for the probe and tests).
func census() -> Array:
	var n := 0
	var tris := 0
	var far := 0
	for cv in world.chunks.values():
		var s: State = cv.far
		if s.far:
			far += 1
		if s.node != null and s.node.visible:
			n += 1
			tris += s.triangles
	return [n, tris, far]


## The models in merged chunks drawn now by triangles: [[name, instances, triangles each], ...],
## most first (for the probe).
func models() -> Array:
	var names := {}
	for name in ModelLibrary._cache:
		if ModelLibrary._cache[name] != null:
			names[ModelLibrary._cache[name]] = name
	var by := {}
	for cv in world.chunks.values():
		var s: State = cv.far
		if s.node == null or not s.node.visible:
			continue
		for mesh in s.counts:
			by[mesh] = int(by.get(mesh, 0)) + int(s.counts[mesh])
	var rows: Array = []
	for mesh in by:
		var bake: Bake = _bakes.get(mesh)
		rows.append([str(names.get(mesh, mesh.resource_name)), by[mesh], bake.indices.size() / 3 if bake != null else 0])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) * int(a[2]) > int(b[1]) * int(b[2]))
	return rows


## What the camera's view holds by kind, in draws before shadows (for the probe): [merged meshes,
## far chunks' own MultiMesh surfaces (trees, ore...), near chunks' MultiMesh surfaces].
func view_census() -> Array:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var planes: Array[Plane] = []
	if cam != null:
		planes = cam.get_frustum()
	var out := [0, 0, 0]
	for cv in world.chunks.values():
		var box := AABB(Vector3(cv.coord.x * CHUNK, 0.0, cv.coord.y * CHUNK), Vector3(CHUNK, 16.0, CHUNK))
		var seen := true
		for p: Plane in planes:
			var inner := Vector3(box.position.x if p.normal.x > 0.0 else box.end.x, box.position.y if p.normal.y > 0.0 else box.end.y,
				box.position.z if p.normal.z > 0.0 else box.end.z)
			seen = seen and not p.is_point_over(inner)
		if not seen or not cv.visible:
			continue
		var s: State = cv.far
		if s.node != null and s.node.visible:
			out[0] += 1
		for mmi: MultiMeshInstance3D in cv._instances:
			if mmi.visible and mmi.multimesh.mesh != null and mmi.multimesh.instance_count > 0:
				out[1 if s.far else 2] += mmi.multimesh.mesh.get_surface_count()
	return out


## For the F4 line: "" when no chunk is merged.
func status() -> String:
	var c := census()
	if int(c[0]) == 0:
		return ""
	return "%d far chunks merged (%dk triangles), %d far" % [c[0], int(c[1]) / 1000, c[2]]


## Nothing left to gather, bake or merge (for tests).
func idle() -> bool:
	return _asked.is_empty() and _collecting.is_empty() and _waiting.is_empty() and _merging.is_empty() and _baking.is_empty() and _bake_queue.is_empty()
