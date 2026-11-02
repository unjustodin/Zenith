extends Node3D
## Flying robots drawn together (the frame rate dropped with many robots in view). Each robot
## used to be a node with a MeshInstance3D per part and a flattened copy of each for its drop
## shadow, moved and animated one by one by vehicle_anim.gd: about 13 draw calls and objects a
## robot, and 9 ms of script a frame for 1,000 robots. Each robot kind is one MultiMesh per part
## (and one per part for the shadows).
##
## Where a robot is drawn and how it is animated (its bob, thrusters swung back as it flies, the
## cargo or empty lamp, a construction robot working with its arms out) come from its record
## (mover_records.gd), which movers.gd writes when a new position of it arrives: the robot shader
## (factorio_material_robot.gdshader) and the shadows' (robot_shadow.gdshader) work it all out.
## An instance holds only its record's slot (INSTANCE_CUSTOM.r) and is written when a robot comes
## or goes, so nothing here runs per robot per frame but a slice a frame of the cargo check and,
## ten times a second, construction robots at work throwing sparks.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const VehicleAnim := preload("res://scripts/world/vehicle_anim.gd")
const MoverRecords := preload("res://scripts/world/mover_records.gd")
const RobotShader := preload("res://shaders/factorio_material_robot.gdshader")
const RobotAlphaShader := preload("res://shaders/factorio_material_robot_alpha.gdshader")
const ShadowShader := preload("res://shaders/robot_shadow.gdshader")

## The robots drawn here: their models' parts are all this knows how to move. Combat robots have a
## body only and don't bob (vehicle_anim.gd never rigged them); capture robots' cables stay nodes.
const KINDS := {"logistic-robot": "logistic", "construction-robot": "construction"}
const PART_CODES := {"thrusters": 1, "lamp_cargo": 2, "lamp_empty": 3, "lamp_nozzle": 4, "arms": 5}
const STRIDE := 16  # floats an instance: a 3x4 transform, then INSTANCE_CUSTOM
## Instances are drawn wherever their records put them, so the MultiMeshes' own bounds (all at the
## origin) mean nothing: they are drawn wherever the camera looks (as their bounds round a swarm
## spread over a base mostly were anyway).
const BOUNDS := AABB(Vector3(-100000.0, -100.0, -100000.0), Vector3(200000.0, 400.0, 200000.0))
## Robots looked at a frame for cargo (ui_model.gd's robot_cargo), and seconds between looks at
## construction robots for work.
const CARGO_SLICE := 64
const WORK_LOOK := 0.1


class Bot:
	var unit := 0
	var batch: Batch
	var slot := 0  # its instance in the batch
	var record := -1  # its record (mover_records.gd)
	var phase := 0.0  # its bob's (in its record)
	var hidden := false  # movers.gd: the remote view's fog hides it (no sparks)
	var cargo := false
	var spark := 0.0


class Batch:
	var name := ""
	var kind := ""  # KINDS, or "" (a body only)
	var source: Mesh  # the model's body as ModelLibrary had it (rebuilt when that changes)
	var parts: Array[MultiMeshInstance3D] = []
	var shadows: Array[MultiMeshInstance3D] = []
	var bots: Array[Bot] = []
	var capacity := 0
	var buffer := PackedFloat32Array()
	var dirty := false
	var shown := -1
	var sweep := 0  # where the cargo check got to


## ui_model.gd's robot_cargo and sprite_fx.gd's sparks, through vehicle_anim.gd (main.gd sets them there).
var vehicles: Node
## The movers' records (movers.gd sets it).
var records: MoverRecords

## False with --robot-nodes: robots are drawn the old way, a node each (for comparing).
static var enabled := not OS.get_cmdline_user_args().has("--robot-nodes")
## The last frame's draw time, microseconds (--robot-probe).
var draw_usec := 0

var _batches := {}  # proto name -> Batch
var _shadow_material: ShaderMaterial
var _look := 0.0


## Whether robots of this prototype are drawn here (their model must be ready).
static func handles(proto_name: String, proto_type: String) -> bool:
	if not enabled or not (KINDS.has(proto_name) or proto_type == "combat-robot"):
		return false
	return ModelLibrary.mesh_for(proto_name) != null


func add(unit: int, proto_name: String) -> Bot:
	var batch: Batch = _batches.get(proto_name)
	if batch == null:
		batch = _make_batch(proto_name)
		_batches[proto_name] = batch
	var bot := Bot.new()
	bot.unit = unit
	bot.batch = batch
	bot.slot = batch.bots.size()
	bot.phase = float(posmod(unit * 7919, 1000)) / 1000.0 * TAU
	bot.cargo = _cargo().has(unit)
	batch.bots.append(bot)
	return bot


## Its record's flags for a new robot: animated (not a combat robot), a builder, carrying cargo.
func flags_for(bot: Bot) -> int:
	var flags := 0
	if bot.batch.kind != "":
		flags |= MoverRecords.ANIMATED
	if bot.batch.kind == "construction":
		flags |= MoverRecords.BUILDER
	if bot.cargo:
		flags |= MoverRecords.CARGO
	return flags


## Its instance draws record `record` from now on.
func place(bot: Bot, record: int) -> void:
	bot.record = record
	var batch := bot.batch
	if batch == null:
		return
	if batch.bots.size() > batch.capacity:
		_grow(batch, batch.bots.size())
	_write_instance(batch, bot.slot, record)
	batch.dirty = true


static func _write_instance(batch: Batch, i: int, record: int) -> void:
	var b := batch.buffer
	var o := i * STRIDE
	# A plain transform at the origin: the shader puts the robot where its record says.
	b[o] = 1.0
	b[o + 1] = 0.0
	b[o + 2] = 0.0
	b[o + 3] = 0.0
	b[o + 4] = 0.0
	b[o + 5] = 1.0
	b[o + 6] = 0.0
	b[o + 7] = 0.0
	b[o + 8] = 0.0
	b[o + 9] = 0.0
	b[o + 10] = 1.0
	b[o + 11] = 0.0
	b[o + 12] = float(record)
	b[o + 13] = 0.0
	b[o + 14] = 0.0
	b[o + 15] = 0.0


func remove(bot: Bot) -> void:
	var batch := bot.batch
	if batch == null or bot.slot >= batch.bots.size() or batch.bots[bot.slot] != bot:
		return
	var last: Bot = batch.bots[batch.bots.size() - 1]
	batch.bots[bot.slot] = last
	last.slot = bot.slot
	batch.bots.resize(batch.bots.size() - 1)
	if last != bot:
		_write_instance(batch, last.slot, last.record)
	batch.dirty = true
	bot.batch = null


func clear() -> void:
	for batch: Batch in _batches.values():
		_free_batch(batch)
		# Bots and their batch point at each other: let go of both, or neither is ever freed.
		for bot in batch.bots:
			bot.batch = null
		batch.bots.clear()
	_batches.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for batch: Batch in _batches.values():
			for bot in batch.bots:
				bot.batch = null
			batch.bots.clear()


## Robots drawn (all kinds).
func count() -> int:
	var n := 0
	for batch: Batch in _batches.values():
		n += batch.bots.size()
	return n


## MultiMeshInstance3Ds drawing robots and their shadows (the UI test counts them).
func instances() -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for batch: Batch in _batches.values():
		out.append_array(batch.parts)
		out.append_array(batch.shadows)
	return out


## A robot as the shader draws it now: [transform, its animation as Color(flying, bob phase, flags,
## reach)], from the record its instance points at, or [] (the UI test).
func drawn(bot: Bot) -> Array:
	var batch := bot.batch
	if batch == null or records == null or batch.parts.is_empty() or bot.slot >= batch.bots.size():
		return []
	var record := int(batch.buffer[bot.slot * STRIDE + 12])
	var st := records.state(record)
	var anim := MoverRecords.robot_anim(st)
	return [Transform3D(Basis(Vector3.UP, st["yaw"]), st["pos"]), Color(anim.x, anim.y, anim.z, anim.w)]


## A model change (Settings > Graphics > Model look, a reload) gives the robots their new meshes.
func refresh() -> void:
	for name in _batches.keys():
		var batch: Batch = _batches[name]
		if ModelLibrary.mesh_for(name) != batch.source:
			var bots := batch.bots
			_free_batch(batch)
			var fresh := _make_batch(name)
			fresh.bots = bots
			for bot in bots:
				bot.batch = fresh
			_grow(fresh, bots.size())
			for bot in bots:
				_write_instance(fresh, bot.slot, bot.record)
			fresh.dirty = true
			_batches[name] = fresh


## Once a frame (movers.gd): instances that came or went go to the MultiMeshes, cargo lamps follow
## ui_model.gd's robot_cargo, and working construction robots throw sparks.
func draw(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_draw(delta)
	draw_usec = Time.get_ticks_usec() - started


func _draw(delta: float) -> void:
	var cargo := _cargo()
	_look -= delta
	var look := _look <= 0.0
	if look:
		_look = WORK_LOOK
	for batch: Batch in _batches.values():
		var n := batch.bots.size()
		if n > batch.capacity:
			_grow(batch, n)
		if batch.dirty:
			batch.dirty = false
			for mmi in batch.parts:
				RenderingServer.multimesh_set_buffer(mmi.multimesh.get_rid(), batch.buffer)
			for mmi in batch.shadows:
				RenderingServer.multimesh_set_buffer(mmi.multimesh.get_rid(), batch.buffer)
		if n != batch.shown:
			batch.shown = n
			for mmi in batch.parts:
				mmi.multimesh.visible_instance_count = n
				mmi.visible = n > 0
			for mmi in batch.shadows:
				mmi.multimesh.visible_instance_count = n
				mmi.visible = n > 0
		if n == 0 or records == null:
			continue
		if batch.kind != "":
			var end := mini(batch.sweep + CARGO_SLICE, n)
			for i in range(batch.sweep, end):
				var bot: Bot = batch.bots[i]
				var has := cargo.has(bot.unit)
				if has != bot.cargo:
					bot.cargo = has
					records.set_flag(bot.record, MoverRecords.CARGO, has)
			batch.sweep = end if end < n else 0
		if look and batch.kind == "construction":
			_sparks(batch, WORK_LOOK)


## Construction robots standing still for VehicleAnim.WORK_STILL work: sparks fly from their nozzle
## now and then, as vehicle_anim.gd threw them. A robot stands once the clock is past its record's
## last point (robots are drawn stopping there until the next comes).
func _sparks(batch: Batch, step: float) -> void:
	var sprites: Node = vehicles.get("sprites") if vehicles != null else null
	if sprites == null:
		return
	var rate := maxf(records.rate, 1.0)
	var d := records.data
	for bot in batch.bots:
		if bot.hidden or bot.record < 0:
			continue
		if (records.tick - records.last_tick(bot.record)) / rate <= VehicleAnim.WORK_STILL:
			continue
		bot.spark -= step
		if bot.spark > 0.0:
			continue
		bot.spark = VehicleAnim.SPARK_EVERY * randf_range(0.6, 1.4)
		var o := bot.record * MoverRecords.FLOATS
		var yaw: float = d[o + 17]
		var at := Vector3(d[o + 6], d[o + 13], d[o + 7])
		sprites.call("emit", "sparks", at + Vector3(-0.35 * sin(yaw), 0.0, -0.35 * cos(yaw)), 0.45, 0.35)


func _cargo() -> Dictionary:
	var model = vehicles.get("model") if vehicles != null else null
	if model == null:
		return {}
	var cargo = model.get("robot_cargo") if model is Object else model.get("robot_cargo", {})
	return cargo if cargo is Dictionary else {}


func _grow(batch: Batch, needed: int) -> void:
	var capacity := maxi(64, batch.capacity)
	while capacity < needed:
		capacity *= 2
	if capacity == batch.capacity:
		return
	batch.capacity = capacity
	batch.buffer.resize(capacity * STRIDE)
	for mmi in batch.parts:
		mmi.multimesh.instance_count = capacity
	for mmi in batch.shadows:
		mmi.multimesh.instance_count = capacity
	batch.shown = -1
	batch.dirty = true


func _make_batch(proto_name: String) -> Batch:
	var batch := Batch.new()
	batch.name = proto_name
	batch.kind = KINDS.get(proto_name, "")
	batch.source = ModelLibrary.mesh_for(proto_name)
	if batch.source == null:
		return batch
	var meshes: Array = [[batch.source, 0, Transform3D.IDENTITY]]
	for part: ModelLibrary.AnimPart in ModelLibrary.parts_for(proto_name):
		meshes.append([part.mesh, int(PART_CODES.get(part.kind, 0)), part.pivot])
	for entry in meshes:
		var mesh: Mesh = entry[0]
		if mesh == null:
			continue
		batch.parts.append(_instance(_robot_mesh(mesh, int(entry[1]), entry[2], batch.kind != ""), null))
		batch.shadows.append(_instance(mesh, _shadow()))
	return batch


func _instance(mesh: Mesh, material: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # the drop shadow is the shadow
	mmi.custom_aabb = BOUNDS
	if material != null:
		mmi.material_override = material
	add_child(mmi)
	return mmi


## A copy of a part's mesh whose model materials use the robot shader, told which part it is.
## Built from the CPU arrays and copied materials: duplicate() reads both back from the
## RenderingServer, which waits for the render thread when it runs on its own.
static func _robot_mesh(mesh: Mesh, code: int, pivot: Transform3D, bobs: bool) -> Mesh:
	var out := ArrayMesh.new()
	var source := mesh as ArrayMesh
	for i in mesh.get_surface_count():
		var custom := source.surface_get_format(i) & ModelLods.CUSTOM_FORMATS if source != null else 0
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), ModelLods.arrays_of(mesh, i), [], {}, custom)
		out.surface_set_material(i, mesh.surface_get_material(i))
	for i in out.get_surface_count():
		var material := out.surface_get_material(i) as ShaderMaterial
		var alpha := material != null and material.shader == ModelLibrary.FactorioAlphaShader
		var copy: ShaderMaterial
		if material != null and (alpha or material.shader == ModelLibrary.FactorioShader):
			copy = ModelLods.copy_material(material)
		else:
			# Every part must read the robot's record to be drawn where it is: a material of another
			# kind becomes a plain one of the robot shader in its colour.
			copy = ShaderMaterial.new()
			copy.shader = RobotShader
			var plain := out.surface_get_material(i) as BaseMaterial3D
			copy.set_shader_parameter("albedo", plain.albedo_color if plain != null else Color(0.5, 0.5, 0.5))
			copy.set_shader_parameter("vertex_data", 0.0)
			copy.set_shader_parameter("edge_data", 0.0)
			copy.set_shader_parameter("view_data", 0.0)
		copy.shader = RobotAlphaShader if alpha else RobotShader
		copy.set_shader_parameter("robot_part", code)
		copy.set_shader_parameter("robot_pivot", pivot.origin)
		copy.set_shader_parameter("robot_axis", pivot.basis.x.normalized())
		copy.set_shader_parameter("robot_bob", VehicleAnim.ROBOT_BOB if bobs else 0.0)
		copy.set_shader_parameter("robot_bob_rate", VehicleAnim.ROBOT_BOB_RATE)
		out.surface_set_material(i, copy)
	return out


func _shadow() -> ShaderMaterial:
	if _shadow_material == null:
		_shadow_material = ShaderMaterial.new()
		_shadow_material.shader = ShadowShader
	return _shadow_material


func _free_batch(batch: Batch) -> void:
	for mmi in batch.parts:
		mmi.queue_free()
	for mmi in batch.shadows:
		mmi.queue_free()
	batch.parts.clear()
	batch.shadows.clear()
