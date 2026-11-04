extends Node3D
## Space Age's quality on things in the world, as Factorio marks them: the quality's icon in the
## bottom-left corner of a placed entity better than normal (`extra.q` in its record), and on
## items riding belts (`bq`, ui_model.belt_quality, at the item belt_items.gd draws). One
## MultiMesh of camera-facing icons per quality; a chunk's entities are gathered again when that
## chunk changes (gathering every record in the world each time took 10-20 ms a frame in Alt-mode
## on a big save while chunks streamed), belt items every frame. Only in Alt-mode (`alt_mode`, set by factorio_ui.gd), and hidden behind
## the buildings in front of them, as Factorio's.

const WorldMirror := preload("res://scripts/world/world.gd")
const IconShader := preload("res://shaders/billboard_icon_cut.gdshader")
const Slot := preload("res://scripts/ui/factorio/slot.gd")

const ENTITY_ICON := 0.42
const ITEM_ICON := 0.2

var world: WorldMirror
var belt_items  # belt_items.gd
var model  # ui_model.gd
var alt_mode := false

var _entity_marks := {}  # quality -> [Vector3]
var _chunk_marks := {}  # chunk -> {quality -> [Vector3]}
var _layers := {}  # quality -> MultiMeshInstance3D
var _dirty := true  # every chunk
var _dirty_chunks := {}  # chunk -> true


func _ready() -> void:
	if world != null:
		world.entities_changed.connect(func(c: Vector2i) -> void: _dirty_chunks[c] = true)


func reset() -> void:
	_entity_marks.clear()
	_chunk_marks.clear()
	_dirty_chunks.clear()
	_dirty = true
	for mmi in _layers.values():
		(mmi as MultiMeshInstance3D).multimesh.visible_instance_count = 0


func _layer(quality: String) -> MultiMeshInstance3D:
	if _layers.has(quality):
		return _layers[quality]
	var mat := ShaderMaterial.new()
	mat.shader = IconShader
	var icon := Slot.quality_icon(quality)
	if icon == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Slot.QUALITY_COLORS.get(quality, Color.WHITE))
		icon = ImageTexture.create_from_image(img)
	mat.set_shader_parameter("icon", icon)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = 32
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_layers[quality] = mmi
	return mmi


func _gather_entities() -> void:
	if _dirty:
		_dirty = false
		_chunk_marks.clear()
		for c in world.chunks:
			_dirty_chunks[c] = true
	if _dirty_chunks.is_empty():
		return
	for c in _dirty_chunks:
		_chunk_marks.erase(c)
		var cv = world.chunks.get(c)
		if cv == null:
			continue  # unloaded
		var marks := {}
		for r in cv.entities.values():
			var rec: WorldMirror.Rec = r
			var q = rec.extra.get("q")
			if q == null or str(q) == "normal":
				continue
			var proto = world.protos.entity(rec.proto_id)
			var half: Vector2 = proto.size() * 0.5 if proto != null else Vector2(0.5, 0.5)
			if rec.dir == 4 or rec.dir == 12:
				half = Vector2(half.y, half.x)
			var at := Vector3(rec.pos.x - half.x + ENTITY_ICON * 0.6, 0.35, rec.pos.y + half.y - ENTITY_ICON * 0.6)
			var list: Array = marks.get(str(q), [])
			list.append(at)
			marks[str(q)] = list
		if not marks.is_empty():
			_chunk_marks[c] = marks
	_dirty_chunks.clear()
	_entity_marks.clear()
	for c in _chunk_marks:
		for q in _chunk_marks[c]:
			var list: Array = _entity_marks.get(q, [])
			list.append_array(_chunk_marks[c][q])
			_entity_marks[q] = list


func _process(_delta: float) -> void:
	if world == null or model == null:
		return
	if not alt_mode:
		for mmi in _layers.values():
			(mmi as MultiMeshInstance3D).multimesh.visible_instance_count = 0
		return
	_gather_entities()
	var marks := {}  # quality -> [[position, size]]
	for q in _entity_marks:
		var list: Array = []
		for p in _entity_marks[q]:
			list.append([p, ENTITY_ICON])
		marks[q] = list
	if belt_items != null:
		for uid in model.belt_quality:
			var p = belt_items.position_of(int(uid))
			if p == null:
				continue
			var q := str(model.belt_quality[uid])
			var list: Array = marks.get(q, [])
			list.append([(p as Vector3) + Vector3(-0.12, 0.18, 0.12), ITEM_ICON])
			marks[q] = list
	for q in _layers:
		if not marks.has(q):
			(_layers[q] as MultiMeshInstance3D).multimesh.visible_instance_count = 0
	for q in marks:
		var mmi := _layer(str(q))
		var list: Array = marks[q]
		if mmi.multimesh.instance_count < list.size():
			mmi.multimesh.instance_count = maxi(list.size(), mmi.multimesh.instance_count * 2)
		mmi.multimesh.visible_instance_count = list.size()
		for i in list.size():
			var s: float = list[i][1]
			mmi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(s, s, s)), list[i][0]))
