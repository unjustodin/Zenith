extends Node3D
## Items on belts far away: past the area where belt_items.gd draws every item, each lane
## of each belt is drawn as flat icons of what it carries, the way Factorio's zoomed-out view
## reads. The mod sends what each lane carries per chunk when it changes (`bfar`), out to the
## "Belt items far away" distance, which this asks for (`bfar` command). One MultiMesh per chunk per
## item; the shader leaves out the square where belt_items.gd draws the real items.
##
## A lane is drawn with as many icons as it holds items (`bfar` c, up to 4 a belt), so a full belt
## reads full. A chunk full of belts is thousands of icons: their buffers are worked out on a
## worker thread (Job), and the MultiMeshes made from them within a few milliseconds a frame. An
## item's icon not loaded yet is loaded on a worker too (IconJob), and its chunks wait for it: a
## tinted icon is composed pixel by pixel, which is what made one message take 30 ms (D6's probe).

const ProtoDB := preload("res://scripts/world/protos.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const WorldMirror := preload("res://scripts/world/world.gd")
const LaneShader := preload("res://shaders/belt_lane_icon.gdshader")

## Lane icons start this far inside the area where every item is drawn, so there is no gap.
const NEAR_OVERLAP := 2.0
## As big as the items' cards near the focus (item_cards.gd), so the hand-over doesn't show.
const ICON := 0.32
## A lane's centre is this far either side of the belt's (measured in 2.1.23).
const LANE := 0.234
## Neighbouring icons on a full lane overlap: every other one sits this much higher, so they don't
## fight over the pixels they share (as belt_items.gd's LAYER_STEP).
const LAYER_STEP := 0.006
## Main-thread time a frame may spend making chunks' MultiMeshes (at least one chunk is made).
const APPLY_USEC := 2000

var protos: ProtoDB
var world: WorldMirror
## Tiles from the focus; 0 draws nothing. Sent to the mod when it changes or after a (re)connect.
var distance := 160
## Tiles from the focus within which the mod sends every item on belts (belt_items.gd draws them):
## the "Belt items in full" setting, sent with the `bfar` command.
var near := 24
## Every item on belts read in one tick each update (settings.gd belt_smooth): sent as `u`, the
## mod's units a tick (belt_items.lua); off, the mod's own slices.
var smooth := true
const SMOOTH_UNITS := 10000000
var _sent_smooth := -1
var focus := Vector2.ZERO
## The square belt_items.gd's items were read round (its covered()): lane icons start at its edge,
## so the two hand over where the items stop, not round the camera, which runs ahead of them while
## panning. z < 0 (not known) falls back to `near` round `focus`.
var covered := Vector3(0.0, 0.0, -1.0)
## Make each message's icons at once on the main thread (tests).
var sync := false

var _chunks := {}  # Vector2i -> Node3D (a MultiMeshInstance3D per item)
var _materials := {}  # item id -> ShaderMaterial
var _quad := QuadMesh.new()
var _height := 0.2
var _height_known := false
var _sent := -1
var _sent_near := -1
var _pending := {}  # Vector2i -> [l, c]: the latest message per chunk not yet given to a job
## The latest message per chunk, kept while the chunk is subscribed: the mod sends a chunk's lanes
## only when they change, and a message that arrives before the chunk itself is loaded can't be
## drawn yet, so it is drawn from here when the chunk arrives (else a steady belt stayed bare).
var _latest := {}  # Vector2i -> [l, c]
var _done: Array = []  # [chunk, buffers by item] from finished jobs, still to be made into nodes
var _job: Job = null
var _task := -1
var _icons_wanted := {}  # item id -> name: icons for the next IconJob
var _icon_job: IconJob = null
var _icon_task := -1
## The longest a frame spent making chunks' nodes, microseconds (probes).
var worst_apply_usec := 0


## One batch of chunks' icons, worked out on a worker thread: buffers only, no nodes.
class Job:
	var msgs: Array = []  # [chunk, l, c]
	var height := 0.2
	var results: Array = []  # [chunk, {item id: PackedFloat32Array of TRANSFORM_3D instances}]

	func run() -> void:
		for m: Array in msgs:
			results.append([m[0], build(m[1], m[2], height)])

	## `l` [x, y, direction, lane 1 item, lane 2 item, ...]; `counts` [lane 1, lane 2, ...] per
	## belt, or empty (an older mod: one icon a lane).
	static func build(l: Array, counts: Array, height: float) -> Dictionary:
		var by_item := {}  # item id -> PackedFloat32Array
		var row := 0
		for i in range(0, l.size() - 4, 5):
			var at := Vector2(int(l[i]), int(l[i + 1])) / 256.0
			var a := int(l[i + 2]) / 16.0 * TAU
			var right := Vector2(cos(a), sin(a))
			var ahead := Vector2(sin(a), -cos(a))
			for lane in 2:
				var item := int(l[i + 3 + lane])
				if item == 0:
					continue
				var n := 1
				if row * 2 + lane < counts.size():
					n = clampi(int(counts[row * 2 + lane]), 1, 4)
				var buf: PackedFloat32Array = by_item.get(item, PackedFloat32Array())
				var o := buf.size()
				buf.resize(o + n * 12)
				var side := at + right * (LANE if lane == 1 else -LANE)
				for j in n:
					# Spread evenly along the belt, as items ride; lying flat and upright, as Factorio's.
					var p := side + ahead * ((j + 0.5) / n - 0.5)
					var k := o + j * 12
					buf[k] = 1.0
					buf[k + 3] = p.x
					buf[k + 5] = 1.0
					buf[k + 7] = height + LAYER_STEP * (j % 2)
					buf[k + 10] = 1.0
					buf[k + 11] = p.y
				by_item[item] = buf
			row += 1
		return by_item

	## How many icons a chunk's buffers hold.
	static func icon_count(by_item: Dictionary) -> int:
		var n := 0
		for item in by_item:
			n += (by_item[item] as PackedFloat32Array).size() / 12
		return n


## Item icons loaded from the install on a worker thread, past ItemIcons' cache.
class IconJob:
	var names := {}  # item id -> name
	var textures := {}  # item id -> Texture2D or null

	func run() -> void:
		for item in names:
			textures[item] = ItemIcons.load_uncached(names[item])


func _ready() -> void:
	_quad.size = Vector2(ICON, ICON)
	_quad.orientation = PlaneMesh.FACE_Y
	# The first material made with the lane shader cost 21 ms on the main thread (Godot sets the
	# shader up then; seen on a real base): made here at start-up, as model_library.gd's warm_up().
	_material(0)
	if world != null:
		world.entities_changed.connect(func(c: Vector2i) -> void:
			if not world.chunks.has(c):
				_pending.erase(c)
				_latest.erase(c)
				_drop(c)
			elif not _chunks.has(c) and not _pending.has(c) and _latest.has(c):
				_pending[c] = _latest[c])


func _exit_tree() -> void:
	_finish()
	_finish_icons()


func reset() -> void:
	_finish()
	_finish_icons()
	_icons_wanted.clear()
	_pending.clear()
	_latest.clear()
	_done.clear()
	for c in _chunks.keys():
		_drop(c)
	covered = Vector3(0.0, 0.0, -1.0)
	_sent = -1
	_sent_near = -1
	_sent_smooth = -1


func _process(_delta: float) -> void:
	if not Bridge.world_ready:
		_sent = -1
	elif _sent != distance or _sent_near != near or _sent_smooth != int(smooth):
		_sent = distance
		_sent_near = near
		_sent_smooth = int(smooth)
		Bridge.send({"t": "bfar", "r": distance, "n": near, "u": SMOOTH_UNITS if smooth else 0})
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_finish()
	if _task < 0 and not _pending.is_empty():
		_start()
	if _icon_task >= 0 and WorkerThreadPool.is_task_completed(_icon_task):
		_finish_icons()
	if _icon_task < 0 and not _icons_wanted.is_empty():
		_start_icons()
	_apply_some(APPLY_USEC)
	var centre := hand_over_centre()
	var edge := near_edge()
	for m in _materials.values():
		(m as ShaderMaterial).set_shader_parameter("focus", centre)
		(m as ShaderMaterial).set_shader_parameter("near", edge)
		(m as ShaderMaterial).set_shader_parameter("far", float(distance))


## Where lane icons start: a little inside the square whose items belt_items.gd draws.
func near_edge() -> float:
	var r := covered.z if covered.z >= 0.0 else float(near)
	return maxf(0.0, r - NEAR_OVERLAP)


## The centre of that square.
func hand_over_centre() -> Vector2:
	return Vector2(covered.x, covered.y) if covered.z >= 0.0 else focus


## Chunks waiting for a job or to be made into nodes (tests, probes).
func waiting() -> int:
	return _pending.size() + _done.size() + (_job.msgs.size() if _job != null else 0)


## `bfar` {cx, cy, l: [x, y, direction, lane 1 item, lane 2 item, ...], c: [lane 1 count, ...]}.
## Kept for the next job; a newer message for the same chunk replaces it.
func handle(msg: Dictionary) -> void:
	var c := Vector2i(int(msg.get("cx", 0)), int(msg.get("cy", 0)))
	var l: Array = msg.get("l") if msg.get("l") is Array else []
	var counts: Array = msg.get("c") if msg.get("c") is Array else []
	if l.is_empty():
		_latest.erase(c)
	else:
		_latest[c] = [l, counts]
	if sync:
		_make(c, Job.build(l, counts, _belt_height()))
		return
	_pending[c] = [l, counts]


## Just over the belt model's top, once the model is made (on a worker thread: making it here at
## start-up cost 5-15 ms on the main thread); a little under it until then.
func _belt_height() -> float:
	if not _height_known and ModelLibrary.ready("transport-belt"):
		_height_known = true
		var belt := ModelLibrary.mesh_for("transport-belt")
		if belt != null:
			_height = belt.get_aabb().end.y + 0.03
	return _height


func _start() -> void:
	var job := Job.new()
	job.height = _belt_height()
	for c in _pending:
		var m: Array = _pending[c]
		job.msgs.append([c, m[0], m[1]])
	_pending.clear()
	_job = job
	_task = WorkerThreadPool.add_task(job.run, false, "belt lanes")


## Waits for the running job and queues what it made.
func _finish() -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_done.append_array(_job.results)
	_job = null


func _start_icons() -> void:
	ItemIcons.prepare_for_threads()
	_icon_job = IconJob.new()
	_icon_job.names = _icons_wanted
	_icons_wanted = {}
	_icon_task = WorkerThreadPool.add_task(_icon_job.run, false, "belt lane icons")


func _finish_icons() -> void:
	if _icon_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_icon_task)
	_icon_task = -1
	for item in _icon_job.textures:
		ItemIcons.store(_icon_job.names[item], _icon_job.textures[item])
		_material(int(item))
	_icon_job = null


## Makes finished chunks' nodes for up to `usec`, at least one chunk. A chunk with an item whose
## icon isn't loaded yet waits for IconJob (later chunks wait behind it, so a newer message for the
## same chunk can't be overtaken).
func _apply_some(usec: int) -> void:
	var start := Time.get_ticks_usec()
	while not _done.is_empty():
		var r: Array = _done[0]
		var by_item: Dictionary = r[1]
		var missing := false
		for item in by_item:
			if not _materials.has(item):
				var name := protos.item_name(int(item)) if protos != null else ""
				if name == "" or ItemIcons.is_cached(name):
					_material(int(item))
				else:
					missing = true
					if _icon_job == null or not _icon_job.names.has(item):
						_icons_wanted[item] = name
		if missing:
			return
		_done.pop_front()
		_make(r[0], by_item)
		var spent := Time.get_ticks_usec() - start
		worst_apply_usec = maxi(worst_apply_usec, spent)
		if spent >= usec:
			return


func _make(c: Vector2i, by_item: Dictionary) -> void:
	_drop(c)
	if by_item.is_empty() or (world != null and not world.chunks.has(c)):
		return
	var node := Node3D.new()
	node.name = "Lanes %d,%d" % [c.x, c.y]
	for item in by_item:
		var buf: PackedFloat32Array = by_item[item]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _quad
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = _material(int(item))
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(inst)
	add_child(node)
	_chunks[c] = node


## How many lane icons a chunk has (tests).
func icons_in(c: Vector2i) -> int:
	var node: Node3D = _chunks.get(c)
	var n := 0
	if node != null:
		for inst in node.get_children():
			n += (inst as MultiMeshInstance3D).multimesh.instance_count
	return n


func _drop(c: Vector2i) -> void:
	var node: Node3D = _chunks.get(c)
	if node != null:
		node.queue_free()
		_chunks.erase(c)


func _material(item: int) -> ShaderMaterial:
	if _materials.has(item):
		return _materials[item]
	var m := ShaderMaterial.new()
	m.shader = LaneShader
	var name := protos.item_name(item) if protos != null else ""
	var tex := ItemIcons.texture_for(name) if name != "" else null
	if tex != null:
		m.set_shader_parameter("icon", tex)
	m.set_shader_parameter("focus", hand_over_centre())
	m.set_shader_parameter("near", near_edge())
	m.set_shader_parameter("far", float(distance))
	_materials[item] = m
	return m
