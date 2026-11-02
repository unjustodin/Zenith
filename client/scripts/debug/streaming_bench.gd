extends SceneTree
## What it costs Godot to take on and let go of a chunk's MultiMeshes, in the frame's script time,
## the time after _process (freed nodes) and the renderer's draw on the main thread:
## godot --path client -s res://scripts/debug/streaming_bench.gd -- --port=<free port>
## (windowed: the costs that matter are the renderer's). Prints one line per case.

const ModelLibrary := preload("res://scripts/world/model_library.gd")

const K := 60  # MultiMeshes taken on or let go of in one frame (a busy chunk's)
const PER := 8  # instances each
const BACKGROUND := 2500  # MultiMeshes standing still meanwhile (a loaded view's)
const CYCLES := 30

var _mesh: Mesh
var _box: BoxMesh
var _root: Node3D
var _still: Array = []
var _live: Array = []
var _case := 0
var _frame := 0
var _end := 0
var _pre := 0
var _post := 0
var _t0 := 0
var _rows := {}
const CASES := ["create_free", "create_buffer_free", "reuse_buffer", "reuse_resize", "hide_show", "remove_add",
	"shadow_same_2500", "shadow_flip_60", "create_custom_aabb_free"]


func _initialize() -> void:
	_mesh = ModelLibrary.mesh_for("assembling-machine-2")
	if _mesh == null:
		_mesh = BoxMesh.new()
	_root = Node3D.new()
	root.add_child(_root)
	var cam := Camera3D.new()
	_root.add_child(cam)
	cam.look_at_from_position(Vector3(0, 60, 60), Vector3.ZERO)
	_box = BoxMesh.new()
	_box.size = Vector3(0.5, 0.5, 0.5)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation = Vector3(-0.9, 0.5, 0)
	_root.add_child(sun)
	for i in BACKGROUND:
		var mmi := _make(Vector3((i % 50) * 3.0 - 75.0, 0, (i / 50) * 3.0 - 75.0), true)
		mmi.multimesh.mesh = _box
		_root.add_child(mmi)
		_still.append(mmi)
	RenderingServer.frame_pre_draw.connect(func() -> void: _pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _post = Time.get_ticks_usec())


func _make(at: Vector3, buffer: bool, custom_aabb := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh
	mm.instance_count = PER
	if custom_aabb:
		mm.custom_aabb = AABB(at - Vector3(20, 0, 20), Vector3(40, 10, 40))
	if buffer:
		mm.buffer = _buffer(at, PER)
	else:
		for k in PER:
			mm.set_instance_transform(k, Transform3D(Basis(), at + Vector3(k * 0.3, 0, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


static func _buffer(at: Vector3, n: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(n * 12)
	for k in n:
		var o := k * 12
		b[o] = 1.0
		b[o + 3] = at.x + k * 0.3
		b[o + 5] = 1.0
		b[o + 7] = at.y
		b[o + 10] = 1.0
		b[o + 11] = at.z
	return b


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	# Last frame's draw and flush, booked to what that frame did.
	if _frame > 20 and _end > 0 and _pre > _end and _post > _pre:
		var key := "%s/%s" % [CASES[_case], "on" if _frame % 2 == 1 else "off"]
		var row: Array = _rows.get(key, [0.0, 0.0, 0.0, 0])
		row[1] += (_pre - _end) / 1000.0
		row[2] += (_post - _pre) / 1000.0
		_rows[key] = row
	_frame += 1
	if _frame > 20 + CYCLES * 2:
		var on: Array = _rows.get(CASES[_case] + "/on", [0.0, 0.0, 0.0, 1])
		var off: Array = _rows.get(CASES[_case] + "/off", [0.0, 0.0, 0.0, 1])
		print("BENCH %-24s do: script %6.2f flush %6.2f draw %6.2f ms | undo: script %6.2f flush %6.2f draw %6.2f ms" % [CASES[_case],
			on[0] / CYCLES, on[1] / CYCLES, on[2] / CYCLES, off[0] / CYCLES, off[1] / CYCLES, off[2] / CYCLES])
		for n in _live:
			if is_instance_valid(n):
				n.queue_free()
		_live.clear()
		_case += 1
		_frame = 0
		if _case >= CASES.size():
			return true
		_end = Time.get_ticks_usec()
		return false
	if _frame <= 20:
		_end = Time.get_ticks_usec()
		return false
	var doing := _frame % 2 == 0
	_t0 = Time.get_ticks_usec()
	_step(CASES[_case], doing)
	var key := "%s/%s" % [CASES[_case], "on" if doing else "off"]
	var row: Array = _rows.get(key, [0.0, 0.0, 0.0, 0])
	row[0] += (Time.get_ticks_usec() - _t0) / 1000.0
	_rows[key] = row
	_end = Time.get_ticks_usec()
	return false


func _step(name: String, doing: bool) -> void:
	match name:
		"create_free", "create_buffer_free", "create_custom_aabb_free":
			if doing:
				for i in K:
					var mmi := _make(Vector3(i * 2.0 - 60.0, 0, -20.0), name != "create_free", name == "create_custom_aabb_free")
					_root.add_child(mmi)
					_live.append(mmi)
			else:
				for n in _live:
					n.queue_free()
				_live.clear()
		"reuse_buffer", "reuse_resize", "hide_show", "remove_add":
			if _live.is_empty():
				for i in K:
					var mmi := _make(Vector3(i * 2.0 - 60.0, 0, -20.0), true)
					_root.add_child(mmi)
					_live.append(mmi)
				return
			for i in K:
				var mmi: MultiMeshInstance3D = _live[i]
				match name:
					"reuse_buffer":
						if doing:
							mmi.multimesh.buffer = _buffer(Vector3(i * 2.0 - 60.0, 0, -20.0 + _frame * 0.01), PER)
					"reuse_resize":
						var n := PER + (4 if doing else 0)
						mmi.multimesh.instance_count = n
						mmi.multimesh.buffer = _buffer(Vector3(i * 2.0 - 60.0, 0, -20.0), n)
					"hide_show":
						mmi.visible = not doing
					"remove_add":
						if doing:
							_root.remove_child(mmi)
						else:
							_root.add_child(mmi)
		"shadow_same_2500":
			if doing:
				for mmi: MultiMeshInstance3D in _still:
					mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		"shadow_flip_60":
			for i in 60:
				(_still[i] as MultiMeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if doing else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
