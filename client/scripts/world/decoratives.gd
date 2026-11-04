extends Node3D
## Factorio's decoratives (grass, flowers, small rocks, decals) near the camera. The mod sends them
## per chunk (`dec`, ids from `dprotos`) when the hello asks (`dc`, Settings → Graphics →
## Decoratives). Each decorative in a chunk is one MultiMeshInstance3D: every instance one of the
## decorative's pictures, read from the player's Factorio install with the regions listed in
## client/data/decoratives.json (tools/decor_index.py). Most lie flat on the ground as Factorio
## draws them; plants on the "object" layer stand up as cards turned to the camera
## (shaders/decorative.gdshader). Without an install nothing is drawn.
##
## The density setting keeps a share of them, the same ones every time (by position).
##
## A chunk is built on a worker thread (10-55 ms each on the main thread while walking, and a
## decorative's first appearance read its pictures from the install there, up to 300 ms): its
## instances' transforms are worked out into a MultiMesh buffer and new pictures loaded into an
## atlas image (BuildJob, KindData). The main thread then only makes the MultiMeshes and new
## decoratives' textures, within FINISH_USEC a frame; the chunk's old clutter stays until then.

const ItemIcons := preload("res://scripts/world/item_icons.gd")
const FrameBudget := preload("res://scripts/world/frame_budget.gd")
const SHADER := preload("res://shaders/decorative.gdshader")
const SHADER_FLAT := preload("res://shaders/decorative_flat.gdshader")
const INDEX := "res://data/decoratives.json"

const CHUNK := 32
## Factorio's pictures: 32 pixels a tile at scale 1.
const PX_PER_TILE := 32.0
## Chunks further than this from the character (tiles, from the chunk's nearest edge) aren't drawn.
## Measured from the character, not the camera: the camera sits far back and up, so its own
## visibility range left the ground near the character bare and drew clutter behind it.
const DRAW_DISTANCE := 192.0
## Level of detail: past FULL_DISTANCE a chunk draws half its clutter, past HALF_DISTANCE a
## quarter. Each chunk's instances are in a fixed random order, so drawing the first part thins
## the clutter evenly rather than cutting it off.
const FULL_DISTANCE := 80.0
const HALF_DISTANCE := 136.0
## Decoratives on this render layer stand up (Gleba's plants, corals, icebergs); the rest (grass,
## flowers, small rocks, decals: "decals", "decorative", "floor", "ground-layer-*") lie flat.
const UPRIGHT_LAYER := "object"
## Flat decoratives lie just over the ground, in Factorio's render layer order (decals under ground
## layers under floor under decoratives). At one height, overlapping ones (biter creep over grass
## patches) fought over every pixel and flickered.
const LAYER_LIFT := {"decals": 0.010, "ground-layer-1": 0.016, "ground-layer-2": 0.019, "ground-layer-3": 0.022,
	"ground-layer-4": 0.025, "ground-layer-5": 0.028, "floor": 0.031, "decorative": 0.036}
## Within a layer, each tile's decorative a step higher or lower (fixed by its tile), so two of the
## same layer overlapping resolve the same way every frame.
const TILE_STEP := 0.0012
const TILE_STEPS := 4
## Main-thread time a frame spends making finished chunks' MultiMeshes (at least one chunk).
const FINISH_USEC := 3000  # its slice in frame_budget.gd
## Floats per instance in a MultiMesh buffer: a 3x4 transform, then the custom data.
const STRIDE := 16


## One decorative's pictures as loaded on a worker thread: the atlas (variants side by side) and
## where each variant is in it.
class KindData:
	var name := ""
	var atlas: Image  # until its texture is made (_kind)
	var upright := false
	var lift := 0.02
	## Per variant: Vector4(u start, u width, v height, 0) in the atlas, its size in tiles and its
	## shift in tiles.
	var uvs: Array[Vector4] = []
	var sizes: Array[Vector2] = []
	var shifts: Array[Vector2] = []


## One decorative's pictures, ready to draw (made on the main thread from its KindData).
class Kind:
	var name := ""
	var material: ShaderMaterial
	var mesh: Mesh
	var upright := false


## A chunk's clutter worked out on a worker thread: per decorative [name, buffer, instances, KindData].
class BuildJob:
	var chunk := Vector2i.ZERO
	var version := 0
	var list: Array = []
	var density := 1.0
	var names := {}
	var data_dir := ""
	var groups: Array = []


## Shared between games: the index, the pictures read from it (null: none) and the decoratives
## made from them.
static var _index := {}
static var _kind_data := {}
static var _kinds := {}
static var _flat_order := {}  # flat decorative -> its rank in the drawing order (_flat_priority)
## Worker threads read pictures one at a time (and each only once).
static var _kind_mutex := Mutex.new()

var enabled := true
var density := 1.0
## Tiles from the focus to the last clutter drawn (Settings > Graphics > Decorative distance).
var distance := DRAW_DISTANCE
## Where the focus was, and the distance, when _cull last looked; it looks again past CULL_STEP tiles.
const CULL_STEP := 0.5
var _culled_at := Vector2.INF
var _culled_distance := -1.0
## Chunks still loaded (world.gd's): others are dropped now and then.
var world: Node
## The camera rig (main.gd): clutter is drawn around what it follows, the character (or the remote
## view's point); without it, everything loaded shows.
var rig: Node

var _names := {}  # id -> name
var _parts := {}  # Vector2i -> {"parts": n, "got": n, "l": flat list}
var _chunks := {}  # Vector2i -> Node3D holding that chunk's MultiMeshInstance3Ds
var _lists := {}  # Vector2i -> the chunk's last full list, to rebuild when the density changes
var _sweep := 0.0
var _shares := {}  # Vector2i -> the share of the chunk's clutter drawn now (1, 0.5, 0.25, 0)
var _versions := {}  # Vector2i -> the number of the chunk's latest build (older jobs' results are dropped)
var _jobs: Array = []  # [task id, BuildJob], oldest first


func reset() -> void:
	_names.clear()
	_parts.clear()
	_lists.clear()
	_versions.clear()
	for node in _chunks.values():
		node.queue_free()
	_chunks.clear()


func count() -> int:
	var n := 0
	for l in _lists.values():
		n += l.size() >> 2
	return n


func set_options(on: bool, share: float) -> void:
	var rebuild := not is_equal_approx(share, density)
	enabled = on
	density = clampf(share, 0.0, 1.0)
	visible = on
	if rebuild:
		for c in _lists.keys():
			_build(c)


func handle(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"dprotos":
			for rec in _array(msg.get("l")):
				if rec is Array and rec.size() >= 2:
					_names[_int(rec[0])] = str(rec[1])
		"dec":
			var c := Vector2i(_int(msg.get("cx")), _int(msg.get("cy")))
			var part := _int(msg.get("part", 1))
			var p: Dictionary = _parts.get(c, {})
			if part == 1 or p.is_empty():
				p = {"parts": _int(msg.get("parts", 1)), "got": 0, "l": []}
				_parts[c] = p
			p["got"] = int(p["got"]) + 1
			(p["l"] as Array).append_array(_array(msg.get("l")))
			if int(p["got"]) >= int(p["parts"]):
				_parts.erase(c)
				_lists[c] = p["l"]
				_build(c)


func _process(delta: float) -> void:
	if _jobs.is_empty():
		FrameBudget.waiting(&"decoratives", 0)
	else:
		var t0 := Time.get_ticks_usec()
		var allow := FrameBudget.grant(&"decoratives")
		if allow > 0:
			_finish_jobs(allow)
		FrameBudget.spent(&"decoratives", Time.get_ticks_usec() - t0, _jobs.size())
	_cull()
	_sweep += delta
	if _sweep < 2.0 or world == null:
		return
	_sweep = 0.0
	for c in _lists.keys():
		if not world.chunks.has(c):
			_drop(c)


## Shows the chunks near the focus only: one distance per chunk, again whenever the focus has moved
## a little or the distance changed; a chunk whose MultiMeshes were just made is culled alone (_replace).
func _cull() -> void:
	var focus: Node3D = rig.get("target") if rig != null and is_instance_valid(rig) else null
	if focus == null or not is_instance_valid(focus):
		return
	var at := Vector2(focus.global_position.x, focus.global_position.z)
	if at.distance_squared_to(_culled_at) < CULL_STEP * CULL_STEP and distance == _culled_distance:
		return
	_culled_at = at
	_culled_distance = distance
	for c: Vector2i in _chunks:
		_cull_one(c, _chunks[c], at)


## One chunk's clutter shown, and how much of it, from its distance to `at`.
func _cull_one(c: Vector2i, node: Node3D, at: Vector2) -> void:
	var area := Rect2(Vector2(c) * CHUNK, Vector2(CHUNK, CHUNK))
	var near := area.get_center() + (at - area.get_center()).clamp(-area.size * 0.5, area.size * 0.5)
	var d := near.distance_to(at)
	var share := 0.0 if d > distance else (1.0 if d <= FULL_DISTANCE else (0.5 if d <= HALF_DISTANCE else 0.25))
	node.visible = share > 0.0
	if share > 0.0 and _shares.get(c, -1.0) != share:
		_shares[c] = share
		for inst in node.get_children():
			var mm := (inst as MultiMeshInstance3D).multimesh
			mm.visible_instance_count = ceili(mm.instance_count * share)


func _drop(c: Vector2i) -> void:
	_lists.erase(c)
	_versions.erase(c)
	_shares.erase(c)
	_parts.erase(c)
	var node: Node3D = _chunks.get(c)
	if node != null:
		node.queue_free()
		_chunks.erase(c)


## Rebuilds a chunk's MultiMeshes from its list: [id, x, y, amount, ...], x and y the tile in the
## chunk. The work is done on a worker thread (_run_job); an empty list clears the chunk at once.
func _build(c: Vector2i) -> void:
	var version := int(_versions.get(c, 0)) + 1
	_versions[c] = version
	var l: Array = _lists.get(c, [])
	var data_dir := ItemIcons.factorio_data_dir()
	if l.is_empty() or data_dir == "":
		_replace(c, null)
		return
	var job := BuildJob.new()
	job.chunk = c
	job.version = version
	job.list = l
	job.density = density
	job.names = _names.duplicate()
	job.data_dir = data_dir
	_jobs.append([WorkerThreadPool.add_task(_run_job.bind(job), false, "decoratives"), job])


## Makes the MultiMeshes of finished jobs, oldest first, for up to `usec` (at least one chunk).
func _finish_jobs(usec: int) -> void:
	var start := Time.get_ticks_usec()
	var made := 0
	while not _jobs.is_empty():
		var entry: Array = _jobs[0]
		var waited := int(entry[0]) < 0
		if not (waited or WorkerThreadPool.is_task_completed(entry[0])) or (made > 0 and Time.get_ticks_usec() - start > usec):
			return
		_jobs.pop_front()
		if not waited:
			WorkerThreadPool.wait_for_task_completion(entry[0])
		var job: BuildJob = entry[1]
		if int(_versions.get(job.chunk, -1)) != job.version:
			continue  # built again since, or dropped
		_replace(job.chunk, _node_for(job))
		made += 1


## Waits for every chunk being built and shows them (tests; a world being left).
func finish_jobs() -> void:
	_wait_all()
	_finish_jobs(1 << 30)


func _exit_tree() -> void:
	_wait_all()
	_jobs.clear()


## Waits for the jobs on worker threads (each only once: their task ids become -1).
func _wait_all() -> void:
	for entry in _jobs:
		if int(entry[0]) >= 0:
			WorkerThreadPool.wait_for_task_completion(entry[0])
			entry[0] = -1


func _replace(c: Vector2i, node: Node3D) -> void:
	var old: Node3D = _chunks.get(c)
	if old != null:
		old.queue_free()
		_chunks.erase(c)
	if node != null:
		_shares.erase(c)  # set again for the new MultiMeshes
		add_child(node)
		_chunks[c] = node
		# Only this chunk culled now, from where the last pass was: every chunk's clutter arriving
		# made the next frame cull all of them, nearly every frame while walking.
		if _culled_at.is_finite():
			_cull_one(c, node, _culled_at)
		else:
			_culled_at = Vector2.INF


## The chunk's node with a MultiMesh per decorative from a finished job, or null if it has none.
func _node_for(job: BuildJob) -> Node3D:
	if job.groups.is_empty():
		return null
	var node := Node3D.new()
	node.name = "Decor %d,%d" % [job.chunk.x, job.chunk.y]
	for g: Array in job.groups:
		var kind := _kind(str(g[0]), g[3])
		if kind == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = kind.mesh
		mm.instance_count = int(g[2])
		mm.buffer = g[1]
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = kind.material
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(inst)
	return node


## A chunk's clutter on a worker thread: per decorative its instances' transforms and atlas
## regions, in a fixed random order (so the first part of the list, drawn far away by _cull, is an
## even thinning); new decoratives' pictures are read here too.
static func _run_job(job: BuildJob) -> void:
	var c := job.chunk
	var l := job.list
	var groups := {}  # id -> [x, y, ...] tiles kept
	for i in range(0, l.size() - 3, 4):
		var id := _int(l[i])
		var x := c.x * CHUNK + _int(l[i + 1])
		var y := c.y * CHUNK + _int(l[i + 2])
		if job.density < 1.0 and posmod(hash(Vector2i(x, y)), 1000) >= int(job.density * 1000.0):
			continue
		if not groups.has(id):
			groups[id] = []
		groups[id].append_array([x, y])
	for id in groups:
		var name := str(job.names.get(id, ""))
		var data := _kind_data_for(name, job.data_dir)
		if data == null:
			continue
		var tiles: Array = groups[id]
		var count := tiles.size() >> 1
		var order: Array = range(count)
		order.sort_custom(func(a: int, b: int) -> bool: return hash(Vector3i(tiles[a * 2], tiles[a * 2 + 1], 5)) < hash(Vector3i(tiles[b * 2], tiles[b * 2 + 1], 5)))
		var buffer := PackedFloat32Array()
		buffer.resize(count * STRIDE)
		for j in count:
			var k: int = order[j]
			var x: int = tiles[k * 2]
			var y: int = tiles[k * 2 + 1]
			var v := posmod(hash(Vector3i(x, y, 11)), data.uvs.size())
			var size: Vector2 = data.sizes[v]
			var shift: Vector2 = data.shifts[v]
			var lift := data.lift + TILE_STEP * posmod(hash(Vector2i(x, y)), TILE_STEPS)
			var origin := Vector3(x + 0.5 + shift.x, lift, y + 0.5 + shift.y)
			var scale := Vector3(size.x, 1.0, size.y)
			if data.upright:
				# Standing: the picture's bottom on the ground; its shift moves it sideways only.
				origin = Vector3(x + 0.5 + shift.x, 0.0, y + 0.5)
				scale = Vector3(size.x, size.y, 1.0)
			# The transform's rows (a scale, then the place), then the atlas region as custom data.
			var o := j * STRIDE
			buffer[o] = scale.x
			buffer[o + 3] = origin.x
			buffer[o + 5] = scale.y
			buffer[o + 7] = origin.y
			buffer[o + 10] = scale.z
			buffer[o + 11] = origin.z
			buffer[o + 12] = data.uvs[v].x
			buffer[o + 13] = data.uvs[v].y
			buffer[o + 14] = data.uvs[v].z
		job.groups.append([name, buffer, count, data])


## The decorative ready to draw, made from its pictures (read by the job), or null.
static func _kind(name: String, data: KindData) -> Kind:
	if name == "":
		return null
	if _kinds.has(name):
		return _kinds[name]
	var kind: Kind = null
	if data != null:
		kind = Kind.new()
		kind.name = name
		kind.upright = data.upright
		kind.material = ShaderMaterial.new()
		kind.material.shader = SHADER if kind.upright else SHADER_FLAT
		kind.material.set_shader_parameter("atlas", ImageTexture.create_from_image(data.atlas))
		data.atlas = null  # the texture has it now; jobs only read the regions
		if kind.upright:
			kind.material.set_shader_parameter("upright", true)
		else:
			kind.material.render_priority = _flat_priority(name)
		if kind.upright:
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			quad.center_offset = Vector3(0.0, 0.5, 0.0)
			kind.mesh = quad
		else:
			var plane := PlaneMesh.new()
			plane.size = Vector2.ONE
			kind.mesh = plane
	_kinds[name] = kind
	return kind


## The decorative's pictures as one atlas (variants side by side), or null without any. Read once,
## on whichever thread asks first (worker threads, from _run_job).
static func _kind_data_for(name: String, data_dir: String) -> KindData:
	if name == "":
		return null
	_kind_mutex.lock()
	if not _kind_data.has(name):
		var data: KindData = null
		var entry = index().get(name)
		if entry is Dictionary and data_dir != "":
			var images: Array[Image] = []
			var pics: Array = []
			var files := {}  # path -> Image, as a sheet holds several variants
			for pic in entry.get("pics", []):
				var image := _region(data_dir, pic, files)
				if image != null:
					images.append(image)
					pics.append(pic)
			if not images.is_empty():
				data = _make_kind_data(name, entry, images, pics)
		_kind_data[name] = data
	var out: KindData = _kind_data[name]
	_kind_mutex.unlock()
	return out


static func _make_kind_data(name: String, entry: Dictionary, images: Array[Image], pics: Array) -> KindData:
	var cell := Vector2i.ZERO
	for image in images:
		cell = Vector2i(maxi(cell.x, image.get_width()), maxi(cell.y, image.get_height()))
	var atlas := Image.create(cell.x * images.size(), cell.y, false, Image.FORMAT_RGBA8)
	var kind := KindData.new()
	kind.name = name
	kind.upright = str(entry.get("layer", "")) == UPRIGHT_LAYER
	kind.lift = float(LAYER_LIFT.get(str(entry.get("layer", "")), 0.036))
	for i in images.size():
		var image := images[i]
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(i * cell.x, 0))
		var pic: Array = pics[i]
		var pic_scale := float(pic[5])
		kind.uvs.append(Vector4(float(i * cell.x) / atlas.get_width(), float(image.get_width()) / atlas.get_width(),
			float(image.get_height()) / atlas.get_height(), 0.0))
		kind.sizes.append(Vector2(image.get_width(), image.get_height()) * pic_scale / PX_PER_TILE)
		kind.shifts.append(Vector2(float(pic[6]), float(pic[7])))
	if not kind.upright:
		atlas.fix_alpha_edges()  # blended (decorative_flat.gdshader): mipmaps without dark rims
	atlas.generate_mipmaps()
	kind.atlas = atlas
	return kind


## A flat decorative's place in the fixed drawing order: blended pictures are otherwise sorted by
## distance, and overlapping ones of two kinds would swap as the camera moves. Factorio's layer
## first (decals under ground layers under floor under decoratives), then the name, spread over the
## render priorities under 0, so the flat clutter is drawn before other see-through things (ghosts,
## item cards). With more kinds than priorities a few neighbours share one.
static func _flat_priority(name: String) -> int:
	if _flat_order.is_empty():
		var flat: Array = []
		for n: String in index():
			var entry: Dictionary = index()[n]
			if str(entry.get("layer", "")) != UPRIGHT_LAYER:
				flat.append([float(LAYER_LIFT.get(str(entry.get("layer", "")), 0.036)), n])
		flat.sort()
		for i in flat.size():
			_flat_order[flat[i][1]] = i
	var rank := int(_flat_order.get(name, _flat_order.size()))
	var slots := Material.RENDER_PRIORITY_MAX - Material.RENDER_PRIORITY_MIN  # under 0: 128 of them
	return Material.RENDER_PRIORITY_MIN + mini(rank * (slots / 2) / maxi(_flat_order.size(), 1), slots / 2 - 1)


## [file, x, y, width, height, scale, shift x, shift y] -> that region of the file, or null.
static func _region(data_dir: String, pic: Array, files: Dictionary) -> Image:
	if pic.size() < 8:
		return null
	var path := data_dir.path_join(str(pic[0]))
	var image: Image = files.get(path)
	if image == null:
		if not FileAccess.file_exists(path):
			return null
		image = Image.load_from_file(path)
		if image == null:
			return null
		image.convert(Image.FORMAT_RGBA8)
		files[path] = image
	var r := Rect2i(int(pic[1]), int(pic[2]), int(pic[3]), int(pic[4])).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return null
	return image.get_region(r)


## tools/decor_index.py's {name: {layer, box, pics}}; empty if the file is missing.
static func index() -> Dictionary:
	if _index.is_empty() and FileAccess.file_exists(INDEX):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		if parsed is Dictionary:
			_index = parsed
	return _index


static func _array(v) -> Array:
	return v if v is Array else []


## A number from the wire, 0 for anything else (null, a list, a string).
static func _int(v) -> int:
	return int(v) if v is int or v is float else 0
