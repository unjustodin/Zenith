extends Node3D
## Factorio's remote view outside radar coverage: nothing there is shown, only a dark fog, while
## what radars (or the character) see stays in full colour, and in Zenith what roboports' construction
## areas reach (H13: the UI model's list from `mrp`, asked for while the fog is on). While the remote
## view is on, the mod sends `cov` about once a second (each working radar's chunk and reveal
## distance, and the character's place); this keeps one texel a chunk of what is seen (and has its
## ground drawn already) round the view and draws the fog
## as a full-screen pass (shaders/remote_fog.gdshader) with a soft edge outside the border. Chunks
## the fog covers wholly (no seen neighbour) aren't drawn at all, which also saves their cost. The
## mod already leaves out movers it doesn't see; `seen()` lets the client hide any left over.
## Off (and free) outside the remote view.

const FOG_SHADER := preload("res://shaders/remote_fog.gdshader")
## Chunks a side of the coverage texture (8192 tiles), centred near the view.
const SIZE := 256
## Re-centred when the view gets this many chunks from the texture's middle.
const RECENTRE := 64
## Seconds between passes over the world's chunks (new ones arrive while the view moves).
const CHUNK_PASS := 0.25

## The world (world.gd), whose chunk nodes are hidden under the fog; null leaves them alone.
var world: Node3D = null
## The UI model (ui_model.gd), for the roboports' chunks (roboport_covers); null: radars only.
var model = null

var _quad := MeshInstance3D.new()
var _material := ShaderMaterial.new()
var _image := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
var _texture: ImageTexture
var _origin := Vector2i.ZERO
## Each working radar's square of chunks, from the latest `cov`.
var _radars: Array[Rect2i] = []
## The character's place and charting radius (tiles) when it is on the surface shown; radius < 0 none.
var _character := Vector2.ZERO
var _character_radius := -1.0
var _all := false
var _known := false
## The surface `cov` is about, and the roboports' version drawn.
var _si := 0
var _roboports_drawn := -1
var _active := false
var _dirty := true
var _pass_timer := 0.0
## Seen chunks with their ground drawn at the last pass (a change redraws the texture).
var _drawn := -1
## Chunk nodes hidden under the fog (coord -> node), shown again when it lifts.
var _hidden := {}


func _ready() -> void:
	_texture = ImageTexture.create_from_image(_image.duplicate() as Image)
	_material.shader = FOG_SHADER
	_material.set_shader_parameter("seen_texture", _texture)
	_material.set_shader_parameter("size", float(SIZE))
	# After the see-through things (ghosts, smoke, item cards, effects: up to 2), so the fog covers
	# them too; before the cursor's build preview and players' name tags (10).
	_material.render_priority = 5
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_quad.mesh = quad
	_quad.material_override = _material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 16384.0  # it covers the screen wherever it is
	_quad.name = "RemoteFog"
	_quad.visible = false
	add_child(_quad)


## `cov` from the mod.
func handle(msg: Dictionary) -> void:
	_radars.clear()
	var l: Variant = msg.get("l")
	var cov: Array = l if l is Array else []
	for i in range(0, cov.size() - 2, 3):
		var d := int(cov[i + 2])
		_radars.append(Rect2i(int(cov[i]) - d, int(cov[i + 1]) - d, 2 * d + 1, 2 * d + 1))
	_all = int(msg.get("all", 0)) == 1
	_si = int(msg.get("si", 0))
	if msg.has("cr"):
		_character = Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0
		_character_radius = float(msg.get("cr"))
	else:
		_character_radius = -1.0
	_known = true
	_dirty = true


## Every frame: whether the remote view is on, and where it looks (tiles). Leaving it forgets the
## coverage, so the next remote view waits for a fresh `cov` and shows everything until then.
func update(on: bool, at: Vector2) -> void:
	if not on and _active:
		_known = false
		_radars.clear()
	_active = on
	_quad.visible = hiding()
	if not _quad.visible:
		_show_chunks()
		return
	var chunk := Vector2i(floori(at.x / 32.0), floori(at.y / 32.0))
	var middle := _origin + Vector2i(SIZE / 2, SIZE / 2)
	if absi(chunk.x - middle.x) > RECENTRE or absi(chunk.y - middle.y) > RECENTRE:
		_origin = chunk - Vector2i(SIZE / 2, SIZE / 2)
		_dirty = true
	if model != null:
		model.ask_roboports(_si)
		if model.roboports_version != _roboports_drawn:
			_roboports_drawn = model.roboports_version
			_dirty = true
	_pass_timer += get_process_delta_time()
	if _dirty:
		_dirty = false
		_redraw()
		_pass_timer = CHUNK_PASS
	if _pass_timer >= CHUNK_PASS:
		_pass_timer = 0.0
		_hide_chunks()


## True while the remote view greys out and hides what no radar sees.
func hiding() -> bool:
	return _active and _known and not _all


## Whether the remote view sees this map position (tiles). Everything outside it.
func seen(pos: Vector2) -> bool:
	if not hiding():
		return true
	return _chunk_seen(Vector2i(floori(pos.x / 32.0), floori(pos.y / 32.0)))


func _chunk_seen(chunk: Vector2i) -> bool:
	# As the mod counts it (map.lua view_filter): a chunk whose centre is within the radius + 16.
	if _character_radius >= 0.0 and (Vector2(chunk) * 32.0 + Vector2(16, 16)).distance_to(_character) <= _character_radius + 16.0:
		return true
	for r in _radars:
		if r.has_point(chunk):
			return true
	return model != null and model.roboport_covers(_si, chunk)


## Whether this chunk or one of its eight neighbours is seen: the fog's soft edge lies over those,
## so they stay drawn.
func _near_seen(chunk: Vector2i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if _chunk_seen(chunk + Vector2i(dx, dy)):
				return true
	return false


## Whether the world has drawn this chunk's ground. A seen chunk that hasn't arrived yet (the remote
## view just jumped far from the character) stays under the fog until it has, instead of showing
## the bare background there; the fog then lifts off it.
func _ground_drawn(chunk: Vector2i) -> bool:
	if world == null:
		return true
	var chunks: Dictionary = world.get("chunks")
	var cv: Variant = chunks.get(chunk)
	return cv != null and cv.has_ground()


func _hide_chunks() -> void:
	if world == null:
		return
	var chunks: Dictionary = world.get("chunks")
	var drawn := 0
	for c in chunks:
		var cv: Node3D = chunks[c]
		if cv.has_ground() and _chunk_seen(c):
			drawn += 1
		var hide := not _near_seen(c)
		if hide and cv.visible:
			cv.visible = false
			_hidden[c] = cv
		elif not hide and _hidden.has(c):
			cv.visible = true
			_hidden.erase(c)
	for c in _hidden.keys():
		if not is_instance_valid(_hidden[c]) or chunks.get(c) != _hidden[c]:
			_hidden.erase(c)
	if drawn != _drawn:
		_drawn = drawn
		_dirty = true  # ground arrived (or went): the fog's texture again next frame


func _show_chunks() -> void:
	for c in _hidden:
		var cv: Variant = _hidden[c]
		if is_instance_valid(cv):
			cv.visible = true
	_hidden.clear()


## How many of the world's chunk nodes the fog hides now.
func hidden_chunks() -> int:
	return _hidden.size()


## Uploads a copy of the mask: with the renderer on its own thread the upload happens there later,
## and the next redraw writes into _image meanwhile (map_cache.gd's flush()).
func _redraw() -> void:
	_image.fill(Color.BLACK)
	var bounds := Rect2i(Vector2i.ZERO, Vector2i(SIZE, SIZE))
	if world != null:
		# Only chunks the world holds can have ground drawn: mark those seen with it.
		var chunks: Dictionary = world.get("chunks")
		for c: Vector2i in chunks:
			var local := c - _origin
			if bounds.has_point(local) and _chunk_seen(c) and _ground_drawn(c):
				_image.set_pixelv(local, Color.WHITE)
		_texture.update(_image.duplicate() as Image)
		_material.set_shader_parameter("origin_chunk", Vector2(_origin))
		return
	for r in _radars:
		var local := Rect2i(r.position - _origin, r.size).intersection(bounds)
		if local.has_area():
			_image.fill_rect(local, Color.WHITE)
	if model != null:
		var ports: PackedInt32Array = model.roboports_of(_si)
		for i in range(0, ports.size() - 3, 4):
			var c := Vector2i(floori(ports[i] / 8192.0), floori(ports[i + 1] / 8192.0))
			var reach := ceili(ports[i + 3] / 8192.0) + 1
			for x in range(c.x - reach, c.x + reach + 1):
				for y in range(c.y - reach, c.y + reach + 1):
					var local := Vector2i(x, y) - _origin
					if bounds.has_point(local) and model.roboport_covers(_si, Vector2i(x, y)):
						_image.set_pixelv(local, Color.WHITE)
	if _character_radius >= 0.0:
		var reach := ceili((_character_radius + 16.0) / 32.0) + 1
		var c := Vector2i(floori(_character.x / 32.0), floori(_character.y / 32.0))
		for x in range(c.x - reach, c.x + reach + 1):
			for y in range(c.y - reach, c.y + reach + 1):
				var local := Vector2i(x, y) - _origin
				if bounds.has_point(local) and _chunk_seen(Vector2i(x, y)):
					_image.set_pixelv(local, Color.WHITE)
	_texture.update(_image.duplicate() as Image)
	_material.set_shader_parameter("origin_chunk", Vector2(_origin))
