extends RefCounted
## Nauvis's creatures as models: which model each prototype uses, at what size and colour, and
## the limb data the material animates them with.
##
## Factorio draws small, medium, big and behemoth biters (spitters, worms) from one sprite sheet,
## scaled and tinted. So does this: each family has one model, built at the big tier's size from
## Wube's printable model (tools/models/wube_recipes.py), and the other tiers are that model
## scaled (its geometry, so the sprite projection and the limbs scale with it) with the tier's
## colour on its carapace (Factorio's mask tint). Pose variants follow the same names:
## `<tier>-biter-attack`, `<tier>-biter-corpse`.
##
## Limbs move in the vertex shader (factorio_material.gdshaderinc, rig_*): every vertex carries
## its limb and how much it follows it (UV), and res://data/creature_rigs.json (written by
## tools/models/wube_rig.py) has each limb's joint, axes and gait. Walking creatures get their
## gait phase from creatures.gd through INSTANCE_CUSTOM; worms and spawners run on their own.

const ModelLods := preload("res://scripts/world/model_lods.gd")
const MaterialRows := preload("res://scripts/world/material_rows.gd")
const RIGS_PATH := "res://data/creature_rigs.json"
## Material name fragments that take the tier's colour.
const TINTED := ["chitin", "flesh_worm", "flesh_spawner_dome"]

## Prototype name -> [model it is drawn with, scale, carapace colour or null].
## Scales from Factorio's enemy-constants.lua. Biters' and spitters' colours were sampled from
## each tier's run sprite with both mask layers tinted as Factorio draws them (the lit 30 % of
## the carapace, tools/models/creature_score.py's sheets); the big tiers take theirs too, as
## their models' own carapace came out too purple. Worms' were sampled the same way from the
## prepared sprite's plates (the mask layer tinted as Factorio draws it); spawners' are their mask
## tint as it shows on the sprite.
const ALIASES := {
	"small-biter": ["big-biter", 0.5, Color(0.435, 0.347, 0.201)],
	"medium-biter": ["big-biter", 0.7, Color(0.399, 0.251, 0.261)],
	"big-biter": ["big-biter", 1.0, Color(0.175, 0.311, 0.368)],
	"behemoth-biter": ["big-biter", 1.2, Color(0.264, 0.389, 0.081)],
	"small-spitter": ["big-spitter", 0.5, Color(0.442, 0.347, 0.158)],
	"medium-spitter": ["big-spitter", 0.7, Color(0.436, 0.253, 0.271)],
	"big-spitter": ["big-spitter", 1.0, Color(0.227, 0.279, 0.319)],
	"behemoth-spitter": ["big-spitter", 1.2, Color(0.28, 0.347, 0.066)],
	"small-worm-turret": ["big-worm-turret", 0.65, Color(0.303, 0.213, 0.147)],
	"medium-worm-turret": ["big-worm-turret", 0.83, Color(0.316, 0.169, 0.144)],
	"big-worm-turret": ["big-worm-turret", 1.0, Color(0.275, 0.195, 0.175)],
	"behemoth-worm-turret": ["big-worm-turret", 1.2, Color(0.272, 0.212, 0.132)],
	"spitter-spawner": ["biter-spawner", 1.0, Color(0.8, 0.45, 0.45)],
	# Gleba's wrigglers (tools/models/gleba.py): the run sprite at 0.36 / 0.48 / 0.6, their legs
	# (the mask layer) in each tier's tint over the grey, lit, as Factorio draws them.
	"small-wriggler-pentapod": ["big-wriggler-pentapod", 0.6, Color(0.258, 0.247, 0.064)],
	"medium-wriggler-pentapod": ["big-wriggler-pentapod", 0.8, Color(0.374, 0.219, 0.071)],
	"big-wriggler-pentapod": ["big-wriggler-pentapod", 1.0, Color(0.315, 0.143, 0.097)],
	# The premature ones a dying stomper or strafer lets out: the same pictures, scale and tints in
	# Factorio (make_wriggler), only losing health over time. Without these they were orange boxes.
	"small-wriggler-pentapod-premature": ["big-wriggler-pentapod", 0.6, Color(0.258, 0.247, 0.064)],
	"medium-wriggler-pentapod-premature": ["big-wriggler-pentapod", 0.8, Color(0.374, 0.219, 0.071)],
	"big-wriggler-pentapod-premature": ["big-wriggler-pentapod", 1.0, Color(0.315, 0.143, 0.097)],
	# Factorio draws the small Gleba spawner's corpse with the big one's picture at a third of
	# its scale (0.3 against 0.9).
	"gleba-spawner-small-corpse": ["gleba-spawner-corpse", 1.0 / 3.0, null],
}
## Pose variants of a family share its tiers: "small-biter-attack" is "big-biter-attack" at 0.5.
const POSES := ["-attack", "-corpse", "-corpse-1", "-corpse-2", "-corpse-3"]

static var _rigs := {}
static var _loaded := false


## The model file a prototype (or pose variant) is drawn with, or "" when it is its own.
static func base_model(name: String) -> String:
	var alias = _alias(name)
	if alias is Array:
		return str(alias[0])
	return ""


## [model, scale, tint] for an aliased name (a tier, or a tier's pose variant), or null.
static func _alias(name: String):
	if ALIASES.has(name):
		return ALIASES[name]
	for pose in POSES:
		if name.ends_with(pose):
			var tier := name.trim_suffix(pose)
			if ALIASES.has(tier):
				var a: Array = ALIASES[tier]
				return [str(a[0]) + pose, a[1], a[2]]
	return null


## True for prototypes creatures.gd draws (walking ones: biters, spitters, characters).
static func walks(name: String) -> bool:
	var model := base_model(name)
	if model == "":
		model = name
	return rig(model).get("mode", "") in ["walk", "pose"]


## True for worms (rig mode "worm"): anim.gd raises, folds and aims them.
static func is_worm(name: String) -> bool:
	var model := base_model(name)
	return rig(name if model == "" else model).get("mode", "") == "worm"


## The limb table of a model (creature_rigs.json), or {}.
static func rig(model: String) -> Dictionary:
	if not _loaded:
		_loaded = true
		var text := FileAccess.get_file_as_string(RIGS_PATH)
		var parsed = JSON.parse_string(text) if text != "" else null
		if parsed is Dictionary:
			_rigs = parsed
	var entry = _rigs.get(model)
	return entry if entry is Dictionary else {}


## Called by model_library.gd on a freshly flattened model: scales a tier's copy, tints its
## carapace, and gives its materials the limb data. Returns the mesh to use.
static func prepare(mesh: ArrayMesh, name: String) -> ArrayMesh:
	if mesh == null:
		return mesh
	var found = _alias(name)
	var alias: Array = found if found is Array else []
	var model := name if alias.is_empty() else str(alias[0])
	var limbs := rig(model)
	var scale := 1.0 if alias.is_empty() else float(alias[1])
	if alias.is_empty() and limbs.is_empty():
		return mesh
	var tint = null if alias.is_empty() else alias[2]
	var out := _scaled(mesh, scale) if scale != 1.0 else mesh
	# The carapace's rows of a merged material (material_rows.gd), or a surface's own material.
	var carapace := func(m: ShaderMaterial) -> bool: return tint != null and _tinted(m.resource_name)
	var recolour := func(m: ShaderMaterial) -> void:
		var albedo: Color = m.get_shader_parameter("albedo")
		m.set_shader_parameter("albedo", Color(tint, albedo.a))
		m.set_shader_parameter("part_colors", false)  # sampled from the big tier's sprite
	var glowing := func(m: ShaderMaterial) -> void: m.set_shader_parameter("activity_glow", true)
	for i in out.get_surface_count():
		var material := out.surface_get_material(i) as ShaderMaterial
		if material == null:
			continue
		var copy := ModelLods.copy_material(MaterialRows.edit(material, carapace, recolour) as ShaderMaterial)
		if not limbs.is_empty():
			if str(limbs.get("mode", "")) == "worm":
				# Bent and raised in the shader from the instance's state (anim.gd sets it,
				# through the same custom data a machine's glow uses).
				copy = MaterialRows.edit_all(copy, glowing) as ShaderMaterial
			_set_rig(copy, limbs, scale)
			if str(limbs.get("mode", "")) == "worm":
				copy.set_shader_parameter("rig_mode", 4)
				copy.set_shader_parameter("worm_height", out.get_aabb().end.y)
		out.surface_set_material(i, copy)
	return out


static func _tinted(material_name: String) -> bool:
	for fragment in TINTED:
		if material_name.contains(fragment):
			return true
	return false


static func _set_rig(material: ShaderMaterial, limbs: Dictionary, scale: float) -> void:
	if str(limbs.get("mode", "")) == "pose":
		# A skeleton (the character): every bone at rest until someone poses it
		# (character_pose.gd, on its own copy of the materials).
		var rows: Array[Vector4] = []
		for i in 16:
			rows.append_array([Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0)])
		material.set_shader_parameter("rig_mode", 3)
		material.set_shader_parameter("rig_bone", rows)
		return
	var joints := PackedVector3Array()
	var swings := PackedVector3Array()
	var lifts := PackedVector3Array()
	var gaits: Array[Vector4] = []
	for limb in limbs.get("limbs", []):
		var j: Array = limb["joint"]
		var s: Array = limb["swing"]
		var l: Array = limb["lift"]
		var g: Array = limb["gait"]
		# glTF -> Godot keeps the axes (both y up, -z north).
		joints.append(Vector3(float(j[0]), float(j[1]), float(j[2])) * scale)
		swings.append(Vector3(float(s[0]), float(s[1]), float(s[2])))
		lifts.append(Vector3(float(l[0]), float(l[1]), float(l[2])))
		gaits.append(Vector4(float(g[0]), float(g[1]), float(g[2]), float(g[3])))
	while joints.size() < 12:
		joints.append(Vector3.ZERO)
		swings.append(Vector3.UP)
		lifts.append(Vector3.RIGHT)
		gaits.append(Vector4.ZERO)
	material.set_shader_parameter("rig_mode", 2 if str(limbs.get("mode", "walk")) == "idle" else 1)
	material.set_shader_parameter("rig_rate", float(limbs.get("rate", 1.0)))
	material.set_shader_parameter("rig_joint", joints)
	material.set_shader_parameter("rig_swing", swings)
	material.set_shader_parameter("rig_lift", lifts)
	material.set_shader_parameter("rig_gait", gaits)


## A copy of the mesh with every vertex scaled about the origin (normals unchanged).
static func _scaled(mesh: ArrayMesh, scale: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	var kept: Array = []
	for i in mesh.get_surface_count():
		var arrays := ModelLods.arrays_of(mesh, i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for k in verts.size():
			verts[k] *= scale
		arrays[Mesh.ARRAY_VERTEX] = verts
		# Keep the custom channels' formats (the baked views in CUSTOM0); the copy is uncompressed.
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(i) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.surface_set_material(i, mesh.surface_get_material(i))
		out.surface_set_name(i, mesh.surface_get_name(i))
		kept.append(arrays)
	out.set_meta(ModelLods.ARRAYS_META, kept)
	return out
