extends SceneTree
## Every model made the new way (its .glb parsed and merged on a worker thread, model_library.gd
## Load) against the old way (the imported scene flattened with SurfaceTool, one surface per
## material): the new mesh has one surface per shader (solid, see-through, leaf cards: one material
## per model, material_rows.gd), and each old surface is one row of it, with the same triangles,
## vertex data and material values (the row in the merged material's table); the same bounds and
## moving parts. Also checks that ready() doesn't block and poll() finishes the jobs, and that
## the materials changed by name after loading (tiers, belts, remnants, tints) change only their
## rows. Run headless:
##   godot --headless --path client -s res://tests/model_load_test.gd [-- name ...]
## Prints "MODEL LOAD FAILS: 0" when all match; quits with 1 otherwise.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const MaterialRows := preload("res://scripts/world/material_rows.gd")

## How far a corner's value may drift between the two ways, on average, by array.
const PER_CORNER := {Mesh.ARRAY_NORMAL: 0.03}
var _fails := 0
var _checked := 0
var _surfaces_before := 0
var _surfaces_after := 0


func _initialize() -> void:
	var names: Array = OS.get_cmdline_user_args()
	if names.is_empty():
		for f in DirAccess.get_files_at("res://assets/models"):
			if f.ends_with(".glb"):
				names.append(f.get_basename())
		# Models under their own licence, in subfolders (fue5/locomotive...).
		for sub in ModelLibrary.MODEL_SUBDIRS:
			for f in DirAccess.get_files_at("res://assets/models/" + sub):
				if f.ends_with(".glb"):
					names.append(sub + f.get_basename())
	# Both settings: merged materials (one surface per shader) and a surface per material.
	for name in names:
		_compare(str(name), true)
		_compare(str(name), false)
	ModelLibrary.merge_materials = true
	if OS.get_cmdline_user_args().is_empty():
		_edits_check()
	_async_check()


func _fail(what: String) -> void:
	_fails += 1
	if _fails <= 60:
		print("FAIL ", what)


func _compare(name: String, combine: bool) -> void:
	var res_path := "res://assets/models/%s.glb" % name
	var old_parts: Array = []
	var root := (load(res_path) as PackedScene).instantiate()
	var old := ModelLibrary._flatten(root, old_parts)
	root.free()
	var load := ModelLibrary.Load.new()
	load.path = res_path
	load.combine = combine
	load.run()
	if not load.ok:
		_fail("%s: the glb didn't parse" % name)
		return
	var new_parts: Array = []
	var new := ModelLibrary._commit_load(load, new_parts)
	_checked += 1 if combine else 0
	_same_mesh(name, old, new, combine)
	if old_parts.size() != new_parts.size():
		_fail("%s: %d moving parts, was %d" % [name, new_parts.size(), old_parts.size()])
		return
	for i in old_parts.size():
		var a: ModelLibrary.AnimPart = old_parts[i]
		var b: ModelLibrary.AnimPart = new_parts[i]
		if a.kind != b.kind or not a.pivot.is_equal_approx(b.pivot) or a.axis != b.axis or a.slide != b.slide or a.upright != b.upright or a.lit != b.lit:
			_fail("%s: part %d is %s at %s, was %s at %s" % [name, i, b.kind, b.pivot, a.kind, a.pivot])
		_same_mesh("%s part %s" % [name, a.kind], a.mesh, b.mesh, combine)


static func _textured(m: ShaderMaterial) -> bool:
	return m.get_shader_parameter("use_albedo_tex") == true or m.get_shader_parameter("use_orm_tex") == true


## The new mesh's surfaces as rows: [[surface, row, its material (the row's), the merged one], ...].
static func _rows_of(mesh: Mesh) -> Array:
	var out: Array = []
	for j in mesh.get_surface_count():
		var m := mesh.surface_get_material(j) as ShaderMaterial
		var rows := MaterialRows.rows(m)
		if rows.is_empty():
			out.append([j, -1, m, m])
		else:
			for r in rows.size():
				out.append([j, r, rows[r], m])
	return out


func _same_mesh(what: String, old: Mesh, new: Mesh, combine: bool) -> void:
	if (old == null) != (new == null):
		_fail("%s: mesh %s, was %s" % [what, new, old])
		return
	if old == null:
		return
	if combine:
		_surfaces_before += old.get_surface_count()
		_surfaces_after += new.get_surface_count()
	# Merged: one surface per shader, and one per textured material (never merged); else as before.
	var expected := old.get_surface_count()
	if combine:
		var shaders := {}
		var textured := 0
		for i in old.get_surface_count():
			var m := old.surface_get_material(i) as ShaderMaterial
			if _textured(m):
				textured += 1
			else:
				shaders[m.shader] = true
		expected = shaders.size() + textured
	if new.get_surface_count() != expected:
		_fail("%s: %d surfaces, %d expected (merged %s)" % [what, new.get_surface_count(), expected, combine])
	var tolerance := maxf(old.get_aabb().size.length() * 0.002, 0.002)
	if not _close(old.get_aabb().position, new.get_aabb().position, tolerance) or not _close(old.get_aabb().size, new.get_aabb().size, tolerance):
		_fail("%s: bounds %s, was %s" % [what, new.get_aabb(), old.get_aabb()])
	# Old surfaces, in order, are the new rows of their shader, in order.
	var rows := _rows_of(new)
	var used := {}
	var arrays_cache := {}
	for i in old.get_surface_count():
		var ma := old.surface_get_material(i) as ShaderMaterial
		var found: Array = []
		for k in rows.size():
			if not used.has(k) and (rows[k][2] as ShaderMaterial).shader == ma.shader and _textured(rows[k][2]) == _textured(ma):
				found = rows[k]
				used[k] = true
				break
		if found.is_empty():
			_fail("%s surface %d: no row for %s" % [what, i, ma.resource_name])
			continue
		var mb: ShaderMaterial = found[2]
		var merged: ShaderMaterial = found[3]
		if mb.resource_name != ma.resource_name:
			_fail("%s surface %d: row %s, was %s" % [what, i, mb.resource_name, ma.resource_name])
			continue
		for p in ["vertex_data", "edge_data", "view_data", "part_data", "activity_glow", "albedo", "emission_energy"]:
			if str(ma.get_shader_parameter(p)) != str(mb.get_shader_parameter(p)):
				_fail("%s surface %d: %s %s, was %s" % [what, i, p, mb.get_shader_parameter(p), ma.get_shader_parameter(p)])
		if str(ma.get_shader_parameter("tall")) != str(merged.get_shader_parameter("tall")):
			_fail("%s surface %d: tall %s, was %s" % [what, i, merged.get_shader_parameter("tall"), ma.get_shader_parameter("tall")])
		if int(found[1]) >= 0:
			_same_row(what + " surface %d" % i, ma, merged, int(found[1]))
		var j: int = found[0]
		if not arrays_cache.has(j):
			arrays_cache[j] = new.surface_get_arrays(j)
		var a := old.surface_get_arrays(i)
		var b: Array = arrays_cache[j]
		var ta := _triangles(a)
		var corners := _corners(b, int(found[1]))
		if corners.size() / 3 != ta:
			_fail("%s surface %d: %d triangles, was %d" % [what, i, corners.size() / 3, ta])
			continue
		# Vertex data compared as sums over the triangles' corners (vertices may be split or
		# ordered differently): positions, normals, colours, UV2, part colours. The import stores
		# positions in 16 bits and welds corners of zero-area triangles to neighbours with other
		# normals, so the sums may drift a little per corner (PER_CORNER). A row's missing array is
		# zeros in the merged surface: its material says so (vertex_data and the rest).
		for t in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_CUSTOM1]:
			if a[t] == null:
				continue
			if b[t] == null:
				_fail("%s surface %d: array %d missing" % [what, i, t])
				continue
			var sa := _corner_sum(a, t, _corners(a, -1))
			var sb := _corner_sum(b, t, corners)
			var allowed := maxf(ta * 3 * (tolerance if t == Mesh.ARRAY_VERTEX else float(PER_CORNER.get(t, 0.01))), 0.01)
			if sa.distance_to(sb) > allowed:
				_fail("%s surface %d: array %d sums to %s, was %s" % [what, i, t, sb, sa])


## The merged material's table row `r` holds what the old material gave its surface.
func _same_row(what: String, old: ShaderMaterial, merged: ShaderMaterial, r: int) -> void:
	if int(merged.get_shader_parameter("material_rows")) != MaterialRows.rows(merged).size():
		_fail("%s: material_rows %s for %d rows" % [what, merged.get_shader_parameter("material_rows"), MaterialRows.rows(merged).size()])
	var got := _row(merged, r)
	var want := MaterialRows.row_vectors(old)
	for k in want.size():
		if not got[k].is_equal_approx(want[k]):
			_fail("%s: row %d vec4 %d is %s, was %s" % [what, r, k, got[k], want[k]])
	# A few straight from the old material's own uniforms.
	var albedo: Color = old.get_shader_parameter("albedo") if old.get_shader_parameter("albedo") != null else Color.WHITE
	var lin := albedo.srgb_to_linear()
	var rough: Variant = old.get_shader_parameter("roughness")
	var part := float(old.get_shader_parameter("part_data")) if bool(old.get_shader_parameter("part_colors")) else 0.0
	if not Vector3(got[0].x, got[0].y, got[0].z).is_equal_approx(Vector3(lin.r, lin.g, lin.b)) \
			or (rough != null and not is_equal_approx(got[2].x, float(rough))) or not is_equal_approx(got[3].x, part):
		_fail("%s: row %d albedo %s roughness %s part %s, was %s %s %s" % [what, r, got[0], got[2].x, got[3].x, lin, rough, part])


## Row `r` of a merged material's table.
static func _row(merged: ShaderMaterial, r: int) -> Array:
	var table: Array = merged.get_shader_parameter("material_table")
	return table.slice(r * MaterialRows.ROW_SIZE, (r + 1) * MaterialRows.ROW_SIZE)


static func _close(a: Vector3, b: Vector3, tolerance: float) -> bool:
	return absf(a.x - b.x) <= tolerance and absf(a.y - b.y) <= tolerance and absf(a.z - b.z) <= tolerance


static func _triangles(arrays: Array) -> int:
	if arrays[Mesh.ARRAY_INDEX] != null and not (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## The triangles' corners (vertex indices) of a surface, only those of row `row` (CUSTOM2) when it
## isn't -1. A triangle's corners must share their row.
func _corners(arrays: Array, row: int) -> PackedInt32Array:
	var all := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null and not (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
		all = arrays[Mesh.ARRAY_INDEX]
	else:
		all.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		for k in all.size():
			all[k] = k
	if row < 0:
		return all
	var rows: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM2]
	var out := PackedInt32Array()
	for t in range(0, all.size() - 2, 3):
		var r := int(rows[all[t]])
		if r != int(rows[all[t + 1]]) or r != int(rows[all[t + 2]]):
			_fail("a triangle's corners are in rows %d, %d, %d" % [r, rows[all[t + 1]], rows[all[t + 2]]])
		if r == row:
			out.append(all[t])
			out.append(all[t + 1])
			out.append(all[t + 2])
	return out


## The sum of an array's values over these corners, as a Vector4.
static func _corner_sum(arrays: Array, t: int, corners: PackedInt32Array) -> Vector4:
	var data = arrays[t]
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per: int = data.size() / maxi(count, 1)
	var sum := Vector4.ZERO
	for c in corners:
		match typeof(data):
			TYPE_PACKED_VECTOR3_ARRAY:
				var v: Vector3 = data[c]
				sum += Vector4(v.x, v.y, v.z, 0.0)
			TYPE_PACKED_VECTOR2_ARRAY:
				var v: Vector2 = data[c]
				sum += Vector4(v.x, v.y, 0.0, 0.0)
			TYPE_PACKED_COLOR_ARRAY:
				var v: Color = data[c]
				sum += Vector4(v.r, v.g, v.b, v.a)
			TYPE_PACKED_FLOAT32_ARRAY:
				for k in mini(per, 4):
					sum[k] += data[c * per + k]
			TYPE_PACKED_BYTE_ARRAY:
				for k in mini(per, 4):
					sum[k] += data[c * per + k] / 255.0
	return sum


## The row of `material` (merged) whose row material is named `row_name`, or -1.
static func _row_named(material: Material, row_name: String) -> int:
	var rows := MaterialRows.rows(material)
	for r in rows.size():
		if (rows[r] as ShaderMaterial).resource_name.contains(row_name):
			return r
	return -1


## Materials changed by name after loading change only their rows (material_rows.gd edit).
func _edits_check() -> void:
	# The row uniforms' defaults, read from the include's code (headless has no renderer to ask).
	MaterialRows._value(ShaderMaterial.new(), "grain")
	var kinds := {"albedo": TYPE_COLOR, "emission": TYPE_COLOR, "grime_color": TYPE_COLOR, "edge_color": TYPE_COLOR,
		"rust_color": TYPE_COLOR, "dust_color": TYPE_COLOR, "part_weathering": TYPE_VECTOR4,
		"part_light": TYPE_VECTOR2, "activity_glow": TYPE_BOOL, "part_colors": TYPE_BOOL, "glow_fades": TYPE_BOOL}
	for u: String in MaterialRows.ROW_PARAMS:
		var d: Variant = MaterialRows._defaults.get(u)
		if typeof(d) != int(kinds.get(u, TYPE_FLOAT)):
			_fail("the default of %s is %s" % [u, d])
	if MaterialRows._defaults.get("grime_color") != Color(0.13, 0.11, 0.09) or not is_equal_approx(float(MaterialRows._defaults.get("grain", 0.0)), 0.08) \
			or MaterialRows._defaults.get("part_weathering") != Vector4(0.4, 0.2, 0.6, 0.1) or MaterialRows._defaults.get("albedo") != Color(1, 1, 1, 1):
		_fail("the row uniforms' defaults misread: %s" % MaterialRows._defaults)
	# A tier's paint (express underground belt): the row recoloured, no sprite or part colours there.
	var base := ModelLibrary.mesh_for("underground-belt-input")
	var tier := ModelLibrary.mesh_for("express-underground-belt-input")
	var bm := base.surface_get_material(0) as ShaderMaterial
	var tm := tier.surface_get_material(0) as ShaderMaterial
	var paint := _row_named(tm, ModelLibrary.TIER_MATERIAL)
	if paint < 0 or MaterialRows.rows(bm).size() != MaterialRows.rows(tm).size():
		_fail("the express underground's paint isn't a row of its one material (%d rows)" % MaterialRows.rows(tm).size())
	else:
		var colour: Color = ModelLibrary.TIER_TINTS["express-underground-belt"][1]
		var lin := colour.srgb_to_linear()
		var a: Vector4 = _row(tm, paint)[0]
		var flags := int((_row(tm, paint)[1] as Vector4).w)
		var d: Vector4 = _row(tm, paint)[3]
		if not Vector3(a.x, a.y, a.z).is_equal_approx(Vector3(lin.r, lin.g, lin.b)) or (flags & MaterialRows.FLAG_NO_SPRITE) == 0 or d.x != 0.0:
			_fail("the express underground's paint row: albedo %s, flags %d, part colours %s" % [a, flags, d.x])
		for r in MaterialRows.rows(tm).size():
			if r != paint and _row(tm, r) != _row(bm, r):
				_fail("the express underground's row %d changed with the paint" % r)
		if MaterialRows.rows(bm)[paint] == MaterialRows.rows(tm)[paint]:
			_fail("the tier's paint row is the base's own material, not a copy")
	# A belt's moving surface: its row flagged, the speed and chevron the model's.
	var belt := ModelLibrary.mesh_for("fast-transport-belt").surface_get_material(0) as ShaderMaterial
	var moving := _row_named(belt, ModelLibrary.BELT_MATERIAL)
	if moving < 0:
		_fail("the fast belt's moving surface isn't a row")
	else:
		var flags := int((_row(belt, moving)[1] as Vector4).w)
		var others := 0
		for r in MaterialRows.rows(belt).size():
			if r != moving and int((_row(belt, r)[1] as Vector4).w) & MaterialRows.FLAG_BELT:
				others += 1
		if (flags & MaterialRows.FLAG_BELT) == 0 or others > 0 or not is_equal_approx(float(belt.get_shader_parameter("belt_speed")), 3.75) \
				or belt.get_shader_parameter("belt_chevron") != ModelLibrary.BELT_CHEVRONS["fast-"]:
			_fail("the fast belt: belt flag %d (others %d), speed %s, chevron %s" % [flags, others, belt.get_shader_parameter("belt_speed"), belt.get_shader_parameter("belt_chevron")])
	# The infinity pipe: the pipe tinted as a whole.
	var pipe := ModelLibrary.mesh_for("infinity-pipe").surface_get_material(0) as ShaderMaterial
	if pipe.get_shader_parameter("model_tint") != ModelLibrary.WHOLE_TINTS["infinity-pipe"][1]:
		_fail("the infinity pipe's tint is %s" % pipe.get_shader_parameter("model_tint"))
	# A remnant: every row burnt (no sprite, no glow, darker), the model's sprite and motion off.
	var burnt := ModelLibrary._burnt(ModelLibrary.mesh_for("heating-tower").surface_get_material(0)) as ShaderMaterial
	var all_burnt := MaterialRows.rows(burnt).size() > 1
	for r in MaterialRows.rows(burnt).size():
		var flags := int((_row(burnt, r)[1] as Vector4).w)
		var tone: Vector4 = _row(burnt, r)[4]
		all_burnt = all_burnt and (flags & MaterialRows.FLAG_NO_SPRITE) != 0 and (flags & MaterialRows.FLAG_GLOW) == 0 and is_equal_approx(tone.w, 0.45)
	if not all_burnt or burnt.get_shader_parameter("activity_glow") != false or burnt.get_shader_parameter("animated") != false:
		_fail("the heating tower's remnant isn't burnt in every row (%d rows)" % MaterialRows.rows(burnt).size())
	if not ModelLibrary.glows(ModelLibrary.mesh_for("heating-tower")):
		_fail("the heating tower's fire doesn't count as glowing")


## ready() starts a job and returns at once; poll() finishes it; the mesh is the one mesh_for gives.
func _async_check() -> void:
	var name := "assembling-machine-2"
	var t0 := Time.get_ticks_usec()
	var first := ModelLibrary.ready(name)
	var asked_usec := Time.get_ticks_usec() - t0
	if first:
		_fail("ready(%s) was true before any job ran" % name)
	if asked_usec > 3000:
		_fail("ready() took %d us: it should only queue a job" % asked_usec)
	var gen := ModelLibrary.generation
	var frames := 0
	while not ModelLibrary.ready(name) and frames < 600:
		ModelLibrary.poll()
		frames += 1
		OS.delay_msec(5)
	if frames >= 600:
		_fail("the job for %s never finished" % name)
	elif ModelLibrary.generation == gen:
		_fail("generation didn't go up when %s was ready" % name)
	var mesh := ModelLibrary.mesh_for(name)
	if mesh == null or not mesh.has_meta(ModelLods.ARRAYS_META):
		_fail("%s has no CPU arrays kept" % name)
	# Its remnant is broken up on a worker thread too, the same as done on the spot.
	var waited := 0
	while not ModelLibrary.remnant_ready(name) and waited < 600:
		ModelLibrary.poll()
		waited += 1
		OS.delay_msec(5)
	var remnant := ModelLibrary.remnant_mesh(name)
	var direct := {}
	var src := ModelLibrary.mesh_for(name) as ArrayMesh
	ModelLibrary._broken_arrays(ModelLibrary._surfaces_of(src), maxf(src.get_aabb().end.y, 0.1), hash(name), direct)
	var same := remnant != null and remnant.get_surface_count() == direct.size()
	if same:
		var k := 0
		for i in direct.keys():
			same = same and _triangles(remnant.surface_get_arrays(k)) == _triangles(direct[i])
			k += 1
	if not same:
		_fail("the remnant made on a worker thread differs from one made directly (%s surfaces, %d direct, waited %d)" % [remnant.get_surface_count() if remnant else -1, direct.size(), waited])
	# A tier made from a ready base, and a model with no file: ready at once.
	if not ModelLibrary.ready("no-such-model-anywhere"):
		_fail("a model with no file wasn't ready at once")
	print("MODEL LOAD checked %d models | surfaces %d -> %d | ready() %d us | job done after %d polls | FAILS: %d"
		% [_checked, _surfaces_before, _surfaces_after, asked_usec, frames, _fails])
	print("MODEL LOAD FAILS: %d" % _fails)
	quit(1 if _fails > 0 else 0)
