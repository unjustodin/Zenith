extends Node3D
## One 32x32-tile chunk: a terrain mesh plus its static entities, drawn with one MultiMesh per
## model (or per placeholder shape). Rebuilt whenever its contents change. A model's moving
## parts get a MultiMesh each, which the model shader (or anim.gd) moves between rebuilds (anim_groups).

const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const Anim := preload("res://scripts/world/anim.gd")
const TerrainMesher := preload("res://scripts/world/terrain_mesher.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const FarChunks := preload("res://scripts/world/far_chunks.gd")

const SIZE := 32
## Entity types whose models get a per-entity random turn and size (see _model_transform).
const VARIED_TYPES := {"tree": true, "simple-entity": true, "resource": true}

var coord := Vector2i.ZERO
var tile_ids := PackedInt32Array()
## False until the chunk's snapshot has arrived (or the chunk doesn't exist on the server).
var loaded := false
var created_msec := Time.get_ticks_msec()
## When the chunk's tiles first arrived and its ground was first drawn (0: not yet).
var tiles_msec := 0
var drawn_msec := 0
var entities := {}  # key -> WorldMirror.Rec
## world.gd pick()'s index of `entities` by PICK_CELL square: built when first needed, emptied
## whenever an entity comes or goes. [protos count it was built with, {cell: [[rec, rect, area]]}]
var pick_grid: Array = []
## The snapshot being received: how many `ents` parts its header announced (-1 before any
## header), and which have arrived.
var parts_expected := -1
var parts_got := {}

## Anim.Group per moving part and per glowing model, for anim.gd.
var anim_groups: Array = []
## Keys of entities drawn as placeholders, whose colour shows the working state (a state
## change needs a rebuild; models show it through anim_groups instead).
var placeholder_keys := {}
## True when something here wasn't drawn because its model is still being made on a worker thread
## (ModelLibrary.ready): world.gd draws the chunk again once models become ready. Ghosts, wires and
## the like set it too, as they are drawn again with the chunk (entities_changed).
var waiting_models := false
## Far from the camera, the buildings are one merged mesh (far_chunks.gd).
var far := FarChunks.State.new()

var _terrain: MeshInstance3D
## How this chunk's things cast shadows (world.gd _update_shadow_casters): through the models'
## stand-ins (model_lods.gd), which simplify only below a pixel of error near the character
## (SHADOWS_NEAR) and sooner further out (SHADOWS_FAR), or not at all beyond where their shadows
## could fall on ground the sun's shadow map covers (SHADOWS_NONE). The shadow pass draws every
## caster in the light's long box, so far chunks cost as much there as near ones.
enum { SHADOWS_NONE, SHADOWS_FAR, SHADOWS_NEAR }
var shadow_tier := SHADOWS_NEAR
## [model's MultiMeshInstance3D, its shadow stand-in's (shown while it is ready), the proxy]
var _shadow_pairs: Array = []
var _proxy_generation := -1
var _lod_bias := -1.0
## Each tile's texture slot (x + 64 * y), kept between rebuilds: it depends only on this chunk's
## tiles and their pictures, and neighbours arriving rebuild the terrain several times. Empty:
## work them out again (terrain_mesher.gd).
var slots := PackedInt32Array()
var _instances: Array[MultiMeshInstance3D] = []
## The MultiMeshes drawn now by what they draw (Want.key), and the models' shadow stand-ins by
## model: kept from one build to the next and filled again.
var _nodes := {}
var _shadows := {}
## What the last build still has to add (Want), taken in world.gd's order of chunks.
var pending: Array = []
## Shadow stand-ins not made yet: only chunks with some redo their shadows when more are ready.
var _unready := 0
## What chunks did this frame, for --stutter-probe (which empties it): {name: count}.
static var counters := {}


static func count(key: String, n := 1) -> void:
	counters[key] = int(counters.get(key, 0)) + n


func set_tiles_rle(rle: Array) -> void:
	tile_ids.resize(SIZE * SIZE)
	var i := 0
	var n := 0
	while i + 1 < rle.size() and n < SIZE * SIZE:
		var id := int(rle[i])
		var count := int(rle[i + 1])
		for _k in count:
			if n >= SIZE * SIZE:
				break
			tile_ids[n] = id
			n += 1
		i += 2
	loaded = true
	slots = PackedInt32Array()


func set_tile(local: Vector2i, id: int) -> void:
	if tile_ids.size() == SIZE * SIZE:
		tile_ids[local.y * SIZE + local.x] = id
		slots = PackedInt32Array()


func mark_missing() -> void:
	tile_ids = PackedInt32Array()
	loaded = true


func clear_entities() -> void:
	entities.clear()
	pick_grid = []


func start_snapshot(parts: int) -> void:
	parts_expected = parts
	parts_got.clear()


func got_part(part: int) -> void:
	# A part we already have means a new snapshot started and its header was lost.
	if parts_got.has(part):
		parts_expected = -1
		parts_got.clear()
	parts_got[part] = true


## Some of the snapshot is known to be missing: a part, or the header in front of parts that came.
func is_incomplete() -> bool:
	if parts_expected < 0:
		return not parts_got.is_empty()
	return parts_got.size() < parts_expected


## Shows the terrain a TerrainMesher job built for this chunk (on a worker thread, see world.gd).
func apply_terrain(job: TerrainMesher) -> void:
	slots = job.slots if job.missing.is_empty() else PackedInt32Array()
	var mesh := ArrayMesh.new()
	if job.land.has_faces():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.land.arrays(), [], {}, TerrainMesher.TerrainSurface.FORMAT)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Visuals.terrain_material())
	if job.water.has_faces():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job.water.arrays(), [], {}, TerrainMesher.TerrainSurface.FORMAT)
		mesh.surface_set_material(mesh.get_surface_count() - 1, Visuals.water_material())
	if _terrain == null:
		_terrain = MeshInstance3D.new()
		# Flat ground shades nothing worth a shadow pass (0.14-0.5 ms of GPU on the owner's save).
		_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_terrain)
	_terrain.mesh = mesh
	if drawn_msec == 0:
		drawn_msec = Time.get_ticks_msec()


func clear_terrain() -> void:
	if _terrain != null:
		_terrain.queue_free()
		_terrain = null


func set_shadow_tier(tier: int) -> void:
	if tier == shadow_tier and _lod_bias == ModelLods.lod_bias:
		if _proxy_generation == ModelLods.generation:
			return
		# More stand-ins are ready somewhere: only a chunk waiting for one has anything to change.
		_proxy_generation = ModelLods.generation
		if _unready == 0:
			return
	shadow_tier = tier
	_apply_shadows()


## Sets each MultiMesh's shadow casting for the tier and the stand-ins ready now. Only what changes
## is set: Godot passes every such setting on to the renderer, which then works the instance out
## again, and setting them all on every chunk whenever another stand-in was ready made 40-55 ms
## frames on a big base.
func _apply_shadows() -> void:
	_proxy_generation = ModelLods.generation
	_lod_bias = ModelLods.lod_bias
	var cast := _cast(shadow_tier != SHADOWS_NONE)
	FarChunks.set_cast(self, cast)
	var bias := 1.0 if shadow_tier == SHADOWS_NEAR else ModelLods.lod_bias
	var stood_in := {}
	_unready = 0
	for pair in _shadow_pairs:
		var ready := ModelLods.is_ready(pair[2])
		if not ready:
			_unready += 1
		var stand_in := shadow_tier != SHADOWS_NONE and ready and not FarChunks.hides(self, pair[0])
		var proxy_mmi: MultiMeshInstance3D = pair[1]
		if proxy_mmi.visible != stand_in:
			proxy_mmi.visible = stand_in
		if proxy_mmi.lod_bias != bias:
			proxy_mmi.lod_bias = bias
		if stand_in:
			stood_in[pair[0]] = true
	for mmi in _instances:
		_set_cast(mmi, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if stood_in.has(mmi) else cast)


static func _set_cast(node: GeometryInstance3D, setting: GeometryInstance3D.ShadowCastingSetting) -> void:
	if node.cast_shadow != setting:
		node.cast_shadow = setting


static func _cast(on: bool) -> GeometryInstance3D.ShadowCastingSetting:
	return GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Instances whose shadows the stand-ins draw now (for tests and the perf probe).
func proxy_count() -> int:
	var n := 0
	for pair in _shadow_pairs:
		if (pair[1] as MultiMeshInstance3D).visible:
			n += 1
	return n


## Whether there's ground to see, or the chunk has none (not generated on the server).
func has_ground() -> bool:
	return _terrain != null or (loaded and tile_ids.is_empty())


## How many new MultiMeshes the chunks built in one frame may still add, counted in their meshes'
## surfaces (world.gd makes one a frame and hands it to each chunk it builds). Godot takes on a
## MultiMesh that starts being drawn at about 0.1 ms of the renderer's time, outside any script,
## and a busy chunk has 60-150 of them: several chunks arriving in one frame made 40-90 ms frames
## while walking on a big base. What doesn't fit waits in `pending` for the next frames.
class Budget:
	var left := 0

	func _init(n: int) -> void:
		left = n


## One MultiMesh a build wants: its key in _nodes and what it draws.
class Want:
	var key  # the model's Mesh, [model, part index] for a moving part, "box" or "cone" for placeholders
	var mesh: Mesh
	var xforms: Array
	var colors: Array = []
	var material: Material
	var custom := false
	var recs: Array = []  # [rec, proto type] per instance, for its anim group
	var part: ModelLibrary.AnimPart
	var group := false  # handed to anim.gd (glowing models and moving parts)


## Rebuilds the entity MultiMeshes. `working` maps unit numbers to machine working state;
## `anim` (anim.gd) gives moving parts their current angle and glows their current activity.
## A MultiMesh drawn before is filled again in place (nothing new for the renderer to take on);
## new ones are added within `budget` (none: all at once), the rest by add_pending().
func build_entities(protos: ProtoDB, working: Dictionary, anim: Anim = null, budget: Budget = null) -> void:
	anim_groups.clear()
	placeholder_keys.clear()
	waiting_models = false
	pending.clear()

	var by_model := {}  # Mesh -> Array of Transform3D
	var recs_by_model := {}  # Mesh -> Array of [rec, proto type]
	var parts_by_model := {}  # Mesh -> Array of ModelLibrary.AnimPart
	var boxes: Array[Transform3D] = []
	var box_colors: Array[Color] = []
	var cones: Array[Transform3D] = []
	var cone_colors: Array[Color] = []
	var merged := FarChunks.skips(self)

	for rec in entities.values():
		var proto: ProtoDB.EntityProto = protos.entity(rec.proto_id)
		if proto == null or rec.extra.has("gh") or rec.extra.has("tg") or ModelLibrary.hidden(proto.name):
			continue  # ghosts (and tile ghosts) are drawn by ghosts.gd
		if ModelLibrary.REMNANT_TYPES.has(proto.type):
			var remnant := _remnant(protos, proto, rec)
			if remnant.is_empty():
				waiting_models = true
				continue
			var rmesh: Mesh = remnant[0]
			if merged and FarChunks.merges(proto.type, rmesh):
				continue
			if not by_model.has(rmesh):
				by_model[rmesh] = []
				recs_by_model[rmesh] = []
				parts_by_model[rmesh] = []
			by_model[rmesh].append(remnant[1])
			recs_by_model[rmesh].append([rec, proto.type])
			continue
		if not ModelLibrary.entity_ready(proto.name, proto.type, rec.extra, rec.dir):
			waiting_models = true  # nothing drawn until its model is made (no placeholder popping up)
			continue
		var mesh := ModelLibrary.mesh_for_entity(proto.name, proto.type, rec.extra, rec.dir)
		if merged and FarChunks.merges(proto.type, mesh):
			continue
		if mesh != null:
			if not by_model.has(mesh):
				by_model[mesh] = []
				recs_by_model[mesh] = []
				parts_by_model[mesh] = ModelLibrary.parts_for_entity(proto.name, proto.type, rec.extra, rec.dir)
			by_model[mesh].append(_model_transform(proto, rec))
			recs_by_model[mesh].append([rec, proto.type])
			if rec.extra.has("cb"):
				if _add_cargo_pieces(rec, by_model[mesh][-1], by_model, recs_by_model, parts_by_model):
					waiting_models = true
			continue
		placeholder_keys[rec.key] = true
		var height := Visuals.height_for(proto)
		if proto.type == "resource":
			height = Visuals.resource_height(int(rec.extra.get("a", 1000)))
		var color := ModelLibrary.NEUTRAL_COLOR if ModelLibrary.NEUTRAL_PROTOS.has(proto.name) else proto.color
		if working.get(rec.unit, 0) == 1:
			color = color.lightened(0.35)
		var xform := Visuals.placeholder_transform(proto, rec.pos, rec.dir, height)
		if Visuals.is_cone(proto):
			cones.append(xform)
			cone_colors.append(color)
		else:
			boxes.append(xform)
			box_colors.append(color)

	var wants: Array[Want] = []
	for model in by_model:
		var glows := ModelLibrary.glows(model)
		wants.append(_want(model, model, by_model[model], [], null, glows, recs_by_model[model], null, glows))
		var parts: Array = parts_by_model[model]
		for i in parts.size():
			var part: ModelLibrary.AnimPart = parts[i]
			wants.append(_want([model, i], part.mesh, by_model[model], [], null, true, recs_by_model[model], part, true))
	if not boxes.is_empty():
		wants.append(_want("box", Visuals.box_mesh(), boxes, box_colors, Visuals.instance_material(), false, [], null, false))
	if not cones.is_empty():
		wants.append(_want("cone", Visuals.cone_mesh(), cones, cone_colors, Visuals.instance_material(), false, [], null, false))
	var wanted := {}
	for w in wants:
		wanted[w.key] = true
	for key in _nodes.keys():
		if not wanted.has(key):
			_drop(key)
	for w in wants:
		if budget == null or budget.left > 0 or _nodes.has(w.key):
			_apply(w, working, anim, budget)
		else:
			pending.append(w)
	_refresh_lists()
	_apply_shadows()
	FarChunks.built(self, merged)


## Adds MultiMeshes a build left for later, within `budget`. True once none are left.
func add_pending(working: Dictionary, anim: Anim, budget: Budget) -> bool:
	if pending.is_empty():
		return true
	while not pending.is_empty() and budget.left > 0:
		_apply(pending.pop_front(), working, anim, budget)
	_refresh_lists()
	_apply_shadows()
	FarChunks.built(self, null)
	return pending.is_empty()


func _want(key, mesh: Mesh, xforms: Array, colors: Array, material: Material, custom: bool, recs: Array,
		part: ModelLibrary.AnimPart, group: bool) -> Want:
	var w := Want.new()
	w.key = key
	w.mesh = mesh
	w.xforms = xforms
	w.colors = colors
	w.material = material
	w.custom = custom
	w.recs = recs
	w.part = part
	w.group = group
	return w


## Draws a Want: into its MultiMesh from before, or a new one (taken from `budget`).
func _apply(w: Want, working: Dictionary, anim: Anim, budget: Budget) -> void:
	var mmi: MultiMeshInstance3D = _nodes.get(w.key)
	if mmi == null:
		mmi = _new_mmi(w.material)
		_nodes[w.key] = mmi
		if budget != null:
			budget.left -= maxi(w.mesh.get_surface_count(), 1)
		count("mmi")
		count("surfaces", w.mesh.get_surface_count())
	Anim.setup_part(w.part)  # its bounds over its whole motion, before the MultiMesh takes them
	_fill(mmi.multimesh, w.mesh, w.xforms, w.colors, w.custom)
	count("instances", w.xforms.size())
	if w.group:
		_add_group(mmi.multimesh, w.part, w.xforms, w.recs, working, anim)
	if w.part == null and w.key is Mesh:
		_shadow_proxy(w.key, w.xforms, budget)


func _new_mmi(material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = _cast(shadow_tier != SHADOWS_NONE)
	if material != null:
		mmi.material_override = material
	add_child(mmi)
	return mmi


## Fills a MultiMesh with these instances, keeping its buffer when the count stays the same.
static func _fill(mm: MultiMesh, mesh: Mesh, xforms: Array, colors: Array, custom: bool) -> void:
	var with_colors := not colors.is_empty()
	if mm.use_colors != with_colors or mm.use_custom_data != custom:
		mm.instance_count = 0  # the formats change only while it is empty
		mm.use_colors = with_colors
		mm.use_custom_data = custom
	if mm.mesh != mesh:
		mm.mesh = mesh
	if mm.instance_count != xforms.size():
		mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if with_colors:
			mm.set_instance_color(i, colors[i])


func _drop(key) -> void:
	var mmi: Node = _nodes.get(key)
	if mmi != null:
		mmi.free()
	_nodes.erase(key)
	var shadow: Node = _shadows.get(key)
	if shadow != null:
		shadow.free()
	_shadows.erase(key)


## _instances and _shadow_pairs from the MultiMeshes drawn now.
func _refresh_lists() -> void:
	_instances.clear()
	for key in _nodes:
		_instances.append(_nodes[key])
	_shadow_pairs.clear()
	for model in _shadows:
		var proxy_mmi: MultiMeshInstance3D = _shadows[model]
		_shadow_pairs.append([_nodes[model], proxy_mmi, proxy_mmi.multimesh.mesh])


## A cargo bay's edge pieces on its 2x2 cells (ModelLibrary.cargo_pieces, extra.cb from world.gd),
## drawn unturned like Factorio's connection tileset. True while some piece's model is being made.
func _add_cargo_pieces(rec, base: Transform3D, by_model: Dictionary, recs_by_model: Dictionary, parts_by_model: Dictionary) -> bool:
	var waiting := false
	for place in ModelLibrary.cargo_places(int(rec.extra["cb"]), base.origin):
		if not ModelLibrary.ready(place[0]):
			waiting = true
			continue
		var mesh := ModelLibrary.mesh_for(place[0])
		if mesh == null:
			continue
		if not by_model.has(mesh):
			by_model[mesh] = []
			recs_by_model[mesh] = []
			parts_by_model[mesh] = []
		by_model[mesh].append(Transform3D(Basis(), place[1]))
		recs_by_model[mesh].append([rec, "cargo-bay"])
	return waiting


## The model's shadow stand-in at the same places, cast in place of the model's own shadow once ready.
func _shadow_proxy(model: Mesh, xforms: Array, budget: Budget) -> void:
	var proxy := ModelLods.proxy_for(model)
	if proxy == null:
		return
	var mmi: MultiMeshInstance3D = _shadows.get(model)
	if mmi == null:
		count("shadow_mmi")
		mmi = _new_mmi(ModelLods.material())
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		mmi.visible = false
		_shadows[model] = mmi
		if budget != null:
			budget.left -= 1
	_fill(mmi.multimesh, proxy, xforms, [], false)
	# The proxy may still be empty: give it the model's bounds so it isn't culled once filled.
	mmi.custom_aabb = _bounds(model.get_aabb(), xforms)


## The box round every instance of a mesh with bounds `box`: worked out here rather than asked of
## the MultiMesh, which waits for the render thread when that runs on its own.
static func _bounds(box: AABB, xforms: Array) -> AABB:
	var out := AABB()
	for i in xforms.size():
		var b: AABB = (xforms[i] as Transform3D) * box
		out = b if i == 0 else out.merge(b)
	return out


## A remnant's [mesh, transform]: the model of what died (extra.rm), broken, turned the way it
## faced; else rubble the size of it, turned at random. [] while the model is still being made.
func _remnant(protos: ProtoDB, proto: ProtoDB.EntityProto, rec) -> Array:
	var src: ProtoDB.EntityProto = protos.entity(int(rec.extra.get("rm", 0)))
	var at := Vector3(rec.pos.x, 0.0, rec.pos.y)
	if src != null:
		var variant := ModelLibrary.model_name(src.name, src.type, {}, rec.dir)
		if not ModelLibrary.remnant_ready(variant):
			return []
		var mesh := ModelLibrary.remnant_mesh(variant)
		if mesh == null:
			if not ModelLibrary.remnant_ready(src.name):
				return []
			mesh = ModelLibrary.remnant_mesh(src.name)
		if mesh != null:
			var yaw := Visuals.direction_yaw(ModelLibrary.turn_dir(src.type, rec.dir, {}, src.name))
			return [mesh, Transform3D(Basis(Vector3.UP, yaw), at)]
	var size := (src if src != null else proto).size().clamp(Vector2(0.6, 0.6), Vector2(8.0, 8.0))
	var turn := float(hash(rec.fixed) & 0xffff) / 65536.0 * TAU
	return [ModelLibrary.rubble_mesh(), Transform3D(Basis(Vector3.UP, turn) * Basis.from_scale(Vector3(size.x, 1.0, size.y)), at)]


## Where a model instance goes. Trees, rocks and ore tiles have no meaningful direction, so
## each gets its own turn and size from a hash of its position (stable across rebuilds and
## sessions); otherwise a forest looks stamped from one mould. Richer ore tiles stand taller.
## Models wearing Factorio's sprite keep facing the way the sprite was drawn, so it fits them.
func _model_transform(proto: ProtoDB.EntityProto, rec) -> Transform3D:
	var at := Vector3(rec.pos.x, 0.0, rec.pos.y)
	if not VARIED_TYPES.has(proto.type):
		return ModelLibrary.placed(proto.name, proto.type, rec.dir, rec.extra, at)
	var h := hash(rec.fixed)
	var yaw := 0.0 if ModelLibrary.projected(proto.name) else float(h & 0xffff) / 65536.0 * TAU
	var size := 0.9 + 0.2 * float((h >> 16) & 0xff) / 255.0
	var height := size
	if proto.type == "resource":
		var amount := maxf(float(rec.extra.get("a", 1000)), 1.0)
		height *= 0.6 + 0.6 * clampf(log(amount) / log(10000.0), 0.0, 1.0)
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size, height, size)), at)


## A moving part's or glowing model's instances, handed to anim.gd, which sets them to where their
## entities' states have them now (most move in the shader from there).
func _add_group(mm: MultiMesh, part: ModelLibrary.AnimPart, xforms: Array, recs: Array, working: Dictionary, anim: Anim) -> void:
	var group := Anim.Group.new()
	group.mm = mm
	group.part = part
	for i in xforms.size():
		var rec = recs[i][0]
		var base: Transform3D = xforms[i]
		if part != null and part.upright:
			base = Transform3D(Basis.IDENTITY, base.origin)
		group.keys.append(rec.key)
		group.units.append(rec.unit)
		group.bases.append(base)
		group.stateful.append(1 if Anim.has_state(str(recs[i][1])) else 0)
		var custom := Anim.custom_for(rec, 1.0)
		if part != null and part.upright:
			custom.b = 0.0  # its sprite is drawn facing north
		group.customs.append(custom)
	Anim.place(group, anim, working)
	anim_groups.append(group)
