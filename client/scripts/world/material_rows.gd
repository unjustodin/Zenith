extends RefCounted
## One material per model (docs/PERFORMANCE-PLAN.md 6). A model's surfaces were one per glTF material
## (6.3 on average), each its own draw per MultiMesh and again per shadow split. model_library.gd now
## merges the surfaces that share a shader (solid, see-through, leaf cards) into one, each vertex
## carrying its material's row in CUSTOM2.r, and gives it one material whose table holds every
## row's per-material uniforms (factorio_material.gdshaderinc: material_rows and material_table).
##
## The rows are the per-material ShaderMaterials the surfaces had before (model_library.gd
## _factorio, shared between models), kept in order as meta on the merged material: whatever
## changed a surface's material by its name (a tier's paint, a belt's moving surface, a creature
## tier's carapace, burnt remnants) changes that row's own copy (edit) and the table is written
## again (compile). Uniforms such a row was given that are not per-row (ROW_PARAMS) are the
## model's: compile sets them on the merged material (a belt's speed, a tint over the whole model).

const ModelLods := preload("res://scripts/world/model_lods.gd")
const INCLUDE := "res://shaders/factorio_material.gdshaderinc"

const MAX_ROWS := 24
## The row_emission flags (factorio_material.gdshaderinc).
const FLAG_GLOW := 1
const FLAG_FADES := 2
const FLAG_BELT := 4
const FLAG_NO_SPRITE := 8
## The uniforms each row has its own value of, in the table.
const ROW_PARAMS := ["albedo", "roughness", "metallic", "emission", "emission_energy", "activity_glow", "glow_fades",
	"glow_flicker", "glow_pulse", "glow_rate", "vertex_data", "edge_data", "view_data", "part_data", "part_colors",
	"part_weathering", "part_light", "ao_strength", "grime", "grime_color", "ground_grime_height", "edge_wear", "edge_color",
	"edge_metallic", "rust", "rust_color", "streaks", "dust", "dust_color", "desaturate", "value", "grain"]
## The vec4s a row takes in material_table.
const ROW_SIZE := 11
## Meta on a row changed by edit(): only those are looked at for the model's own uniforms.
const EDITED_META := ModelLods.ROW_EDITED_META

static var _defaults := {}  # uniform name -> the shader's default
static var _not_lifted := {}
static var _names := {}  # Shader -> its uniforms' names


## The row materials of a merged material, [] for any other.
static func rows(material: Material) -> Array:
	if material != null and material.has_meta(ModelLods.ROWS_META):
		return material.get_meta(ModelLods.ROWS_META)
	return []


## A merged material for these row materials (all of one shader).
static func make(row_materials: Array) -> ShaderMaterial:
	var first: ShaderMaterial = row_materials[0]
	var out := ShaderMaterial.new()
	out.shader = first.shader
	out.resource_name = first.resource_name
	out.set_meta(ModelLods.ROWS_META, row_materials.duplicate())
	compile(out)
	return out


## A material with the rows `pick` chooses (Callable(ShaderMaterial) -> bool) changed by `change`
## (Callable(ShaderMaterial)), each on its own copy; for a material without rows, a copy of it
## changed if it is picked. `material` itself when nothing is picked.
static func edit(material: Material, pick: Callable, change: Callable) -> Material:
	var sm := material as ShaderMaterial
	if sm == null:
		return material
	var list := rows(sm)
	if list.is_empty():
		if not pick.call(sm):
			return material
		var copy := ModelLods.copy_material(sm)
		change.call(copy)
		return copy
	var fresh := list.duplicate()
	var picked := false
	for i in fresh.size():
		if pick.call(fresh[i]):
			var row := ModelLods.copy_material(fresh[i])
			change.call(row)
			row.set_meta(EDITED_META, true)
			fresh[i] = row
			picked = true
	if not picked:
		return material
	var out := ModelLods.copy_material(sm)
	out.set_meta(ModelLods.ROWS_META, fresh)
	compile(out)
	return out


## Every row (or the material itself, without rows) changed by `change`.
static func edit_all(material: Material, change: Callable) -> Material:
	return edit(material, func(_m: ShaderMaterial) -> bool: return true, change)


## Writes the merged material's table from its rows, and the model-wide uniforms edited rows were
## given onto it.
static func compile(material: ShaderMaterial) -> void:
	var list := rows(material)
	var table: Array[Vector4] = []
	var any_glow := false
	var lifted := {}
	for row: ShaderMaterial in list:
		table.append_array(row_vectors(row))
		if bool(_value(row, "activity_glow")):
			any_glow = true
		if row.has_meta(EDITED_META):
			for u in _uniform_names(row.shader):
				if not _not_lifted.has(u) and not lifted.has(u):
					var value: Variant = row.get_shader_parameter(u)
					if value != null:
						lifted[u] = value
	material.set_shader_parameter("material_table", table)
	material.set_shader_parameter("material_rows", list.size())
	# What GDScript asks of a material (ModelLibrary.glows, the far merge) answers for the model.
	material.set_shader_parameter("activity_glow", any_glow)
	for u in lifted:
		material.set_shader_parameter(u, lifted[u])


## A row material's ROW_SIZE vec4s in material_table (factorio_material.gdshaderinc's layout).
static func row_vectors(row: ShaderMaterial) -> Array[Vector4]:
	var v := values(row)
	var flags := 0
	if bool(v["activity_glow"]):
		flags |= FLAG_GLOW
	if bool(v["glow_fades"]):
		flags |= FLAG_FADES
	var speed: Variant = row.get_shader_parameter("belt_speed")
	if speed != null and float(speed) != 0.0:
		flags |= FLAG_BELT
	var cells: Variant = row.get_shader_parameter("sprite_cells")
	if cells != null and int(cells) == 0:
		flags |= FLAG_NO_SPRITE
	var albedo: Color = v["albedo"]
	var emission: Color = v["emission"]
	var energy := float(v["emission_energy"])
	var light: Vector2 = v["part_light"]
	var out: Array[Vector4] = [
		Vector4(albedo.r, albedo.g, albedo.b, albedo.a),
		Vector4(emission.r * energy, emission.g * energy, emission.b * energy, flags),
		Vector4(float(v["roughness"]), float(v["metallic"]), float(v["edge_metallic"]), float(v["ground_grime_height"])),
		Vector4(float(v["part_data"]) if bool(v["part_colors"]) else 0.0, float(v["glow_flicker"]), float(v["glow_pulse"]), float(v["glow_rate"])),
		Vector4(float(v["ao_strength"]), float(v["streaks"]), float(v["desaturate"]), float(v["value"])),
		Vector4(float(v["grain"]), light.x, light.y, 0.0),
		v["part_weathering"],
		_with(v["grime_color"], v["grime"]),
		_with(v["edge_color"], v["edge_wear"]),
		_with(v["rust_color"], v["rust"]),
		_with(v["dust_color"], v["dust"]),
	]
	return out


static func _with(color: Color, w: Variant) -> Vector4:
	return Vector4(color.r, color.g, color.b, float(w))


## A row material's per-row uniforms as the shader gets them: colours linear (Godot converts the
## source_color uniforms, set or left at their defaults: checked by rendering one), part_weathering a
## Vector4, the rest as they are.
static func values(row: ShaderMaterial) -> Dictionary:
	var out := {}
	for u: String in ROW_PARAMS:
		var value: Variant = _value(row, u)
		if value is Color:
			value = (value as Color).srgb_to_linear()
		out[u] = value
	var w: Variant = out["part_weathering"]
	if not (w is Vector4):
		var c: Color = w if w is Color else Color.WHITE
		out["part_weathering"] = Vector4(c.r, c.g, c.b, c.a)
	return out


## A uniform's value on a material, or the shader's default when it isn't set.
static func _value(material: ShaderMaterial, name: String) -> Variant:
	var value: Variant = material.get_shader_parameter(name)
	if value != null:
		return value
	if _defaults.is_empty():
		_read_defaults()
	return _defaults.get(name)


## The defaults of the include's uniforms, read from its code: the RenderingServer has none to give
## headless (its dummy renderer), where the tests run. A source_color default is a Color, as the
## renderer takes it (converted like a set colour).
static func _read_defaults() -> void:
	var include := load(INCLUDE) as ShaderInclude
	var re := RegEx.new()
	re.compile("uniform\\s+(\\w+)\\s+(\\w+)\\s*(:[^=;]*)?=\\s*([^;]+);")
	for m in re.search_all(include.code if include != null else ""):
		var type := m.get_string(1)
		var text := m.get_string(4).strip_edges()
		var colour := m.get_string(3).contains("source_color")
		var nums: Array[float] = []
		var inner := text.substr(text.find("(") + 1, text.rfind(")") - text.find("(") - 1) if text.contains("(") else text
		for part in inner.split(","):
			nums.append(float(part.strip_edges()))
		var size := {"vec2": 2, "vec3": 3, "vec4": 4}.get(type, 1) as int
		while nums.size() < size:
			nums.append(nums[0])  # vec4(1.0): every component
		var value: Variant = null
		match type:
			"bool":
				value = text == "true"
			"int":
				value = int(nums[0])
			"float":
				value = nums[0]
			"vec2":
				value = Vector2(nums[0], nums[1])
			"vec3":
				value = Color(nums[0], nums[1], nums[2]) if colour else Vector3(nums[0], nums[1], nums[2])
			"vec4":
				value = Color(nums[0], nums[1], nums[2], nums[3]) if colour else Vector4(nums[0], nums[1], nums[2], nums[3])
		if value != null:
			_defaults[m.get_string(2)] = value


static func _uniform_names(shader: Shader) -> PackedStringArray:
	if not _names.has(shader):
		if _not_lifted.is_empty():
			# The rows' own values and flags stay in the table; belt_speed, belt_shape and the rest
			# are the model's.
			for u in ROW_PARAMS + ["material_table", "material_rows", "sprite_cells"]:
				_not_lifted[u] = true
		var names := PackedStringArray()
		for u: Dictionary in shader.get_shader_uniform_list():
			names.append(str(u["name"]))
		_names[shader] = names
	return _names[shader]
