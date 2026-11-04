extends Node3D
## The client's copy of the static world: terrain and entities in the chunks around the camera.
## Applies chunk snapshots and deltas from the mod and keeps the chunk subscription current.

const ProtoDB := preload("res://scripts/world/protos.gd")
const ChunkView := preload("res://scripts/world/chunk_view.gd")
const Anim := preload("res://scripts/world/anim.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const TerrainMesher := preload("res://scripts/world/terrain_mesher.gd")
const TerrainTextures := preload("res://scripts/world/terrain_textures.gd")
const ModelLods := preload("res://scripts/world/model_lods.gd")
const FarChunks := preload("res://scripts/world/far_chunks.gd")
const FrameBudget := preload("res://scripts/world/frame_budget.gd")

const CHUNK := 32
const SUBSCRIBE_REFRESH := 5.0  # resend the subscription now and then in case it was lost
## Chunks are asked for a few at a time, nearest the focus first, and more only once those are
## drawn: walking at a long view distance, every chunk edge crossed asked for a whole new row (29
## at Ultra), which arrived and was built together and stuttered (owner's desktop, 18 fps running).
## While the focus moves at most STREAM_MOVING chunks are on their way, standing STREAM_STILL (the
## first load), checked every STREAM_STEP seconds.
const STREAM_MOVING := 8
const STREAM_STILL := 32
const STREAM_STEP := 0.15
const MOVING_FOR := 1.5  # seconds after the focus last changed chunk that it counts as moving
const FOCUS_INTERVAL := 0.25
const REBUILDS_PER_FRAME := 6
# Main-thread time a frame may spend rebuilding chunks' entities (at least one is rebuilt): a busy
# chunk takes 10-30 ms, and six of them in a frame made walking into a big base stutter.
const REBUILD_USEC := 6000
## Message handling (Bridge) and chunk rebuilds share this much of a frame: walking into new chunks
## on the owner's save, both at their own full allowance plus everything else made 20 ms frames.
## Rebuilds get what handling left, at least REBUILD_MIN_USEC so chunks keep coming.
const FRAME_WORK_USEC := 7000
const REBUILD_MIN_USEC := 1500
# New MultiMeshes a frame may add, in their meshes' surfaces (ChunkView.Budget): what the renderer
# takes on outside any script. A chunk's MultiMeshes drawn before are filled again in place, and
# don't count.
const NEW_SURFACES := 160
# Main-thread time a frame may spend freeing chunks no longer wanted (at least one).
const UNLOAD_USEC := 1500
# Terrain meshes take 4-6 ms each with Factorio's tile textures and transitions, and come in
# bursts (a chunk arriving also rebuilds its neighbours), so they're built on worker threads
# (terrain_mesher.gd): this many at once, chunks without ground first, nearest first. Two a frame
# on the main thread left holes for seconds on a big base and made the frames that built them slow.
const TERRAIN_JOBS := 4
# Main-thread time a frame may spend turning finished jobs into meshes.
const TERRAIN_APPLY_USEC := 3000
# A chunk still empty this long after subscribing was lost along with whatever resync should
# have recovered it (a gap can't say which chunks it hit). Asking again for one still on its way
# costs nothing: the mod queues each chunk once. Not waiting for the stream to go quiet: on a
# busy base it never does, and lost chunks stayed holes for good.
const MISSING_CHUNK_MSEC := 4000
const WATCHDOG_INTERVAL := 3.0

## A chunk's entities were redrawn (something in it changed) or it was unloaded. Overlays drawn
## from entity records (wires, ghosts, marks) rebuild from this.
signal entities_changed(chunk: Vector2i)
## A record's Alt-mode arrows changed without the chunk being drawn again (`aiu` fa).
signal alt_changed(chunk: Vector2i)


## A static entity as last reported by the server.
class Rec:
	var key  # unit number (int) or "proto:x:y" (String) for entities without one
	var unit := 0
	var proto_id := 0
	var pos := Vector2.ZERO  # tiles
	var fixed := Vector2i.ZERO  # 1/256 tiles, exactly as sent
	var dir := 0
	var extra := {}
	var chunk := Vector2i.ZERO


var protos := ProtoDB.new()
## Chunks loaded around the focus, as a radius in chunks (3 -> 7x7 chunks).
var view_radius := 5
## Live updates (movers, machine states) are requested within this many tiles of the focus.
var focus_radius := 96
## The 3D remote view is on (set_remote_view).
var remote_view := false
## The sun, whose shadow map decides which chunks cast shadows (_update_shadow_casters).
var sun: DirectionalLight3D
## Chunks that cast shadows now (for --perf probes and the UI test).
var shadow_casters := 0
var _shadow_key: Array = []

var chunks := {}  # Vector2i -> ChunkView
var entities := {}  # key -> Rec
var _ghosts := {}  # Vector2i fixed position -> key of the ghost standing there
var _tile_ghosts := {}  # Vector2i tile -> key of the tile ghost on it (extra.tg)
var _pipes := {}  # Vector2i tile -> key of the pipe or pipe-to-ground on it
var _walls := {}  # Vector2i tile -> key of the wall or gate on it
var _cargo := {}  # key of a hub, cargo bay or landing pad -> Rect2i of its tiles
var _cargo_tiles := {}  # Vector2i tile -> how many of them cover it
var _cargo_ghosts := {}  # the same for ghosts of them: ghost bays join each other, built ones don't
var _cargo_ghost_tiles := {}
## Keys of remnants (ModelLibrary.REMNANT_TYPES): building over one removes it in the game, which
## raises no event, so a new entity clears those under it here (_clear_remnants_under).
var _remnants := {}
var working := {}  # unit -> 0/1
## Turns moving parts and fades glows in the chunks near the focus.
var animator := Anim.new()
## Far chunks' buildings merged into one mesh each.
var far_chunks := FarChunks.new()

var _focus := Vector2.ZERO
var _subscribed: Array = []
var _sub_timer := 0.0
var _stream_timer := 0.0
var _moved_msec := 0
var _focus_timer := 0.0
var _last_focus_sent := Vector2(INF, INF)
var _dirty := {}  # Vector2i -> true
var _pending := {}  # Vector2i -> true: chunks built with MultiMeshes still to add (ChunkView.pending)
var _unloaded: Array = []  # ChunkViews no longer wanted, still to free
var _dirty_terrain := {}
var _terrain_jobs := {}  # Vector2i -> [task id, TerrainMesher, ChunkView]
## Chunks drawn without some tile pictures, which were still loading: Vector2i -> missing ids.
var _waiting_gfx := {}
## Per tile id, the graphics terrain jobs use (TerrainMesher.gfx_of). Replaced, never changed,
## when more pictures are ready, as running jobs hold the old one.
var _gfx_table: Array = []
var _gfx_generation := -1
var _watchdog_timer := 0.0
## Terrain builds so far, their main-thread time and their time on worker threads (for
## --terrain-probe).
var terrain_builds := 0
var terrain_build_usec := 0
var terrain_worker_usec := 0
var entity_builds := 0
var entity_build_usec := 0
## Main-thread time by part of this node's _process, microseconds so far (for --stutter-probe).
var prof := {}


func _prof(key: String, t0: int) -> void:
	prof[key] = int(prof.get(key, 0)) + Time.get_ticks_usec() - t0


func _ready() -> void:
	Bridge.resync_chunks = resync_list
	animator.name = "Animator"
	animator.world = self
	add_child(animator)
	far_chunks.name = "FarChunks"
	far_chunks.world = self
	add_child(far_chunks)
	if "--terrain-probe" in OS.get_cmdline_user_args():
		var probe: Node = preload("res://scripts/debug/terrain_probe.gd").new()
		probe.world = self
		add_child(probe)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stutter-probe="):
			var stutter: Node = preload("res://scripts/debug/stutter_probe.gd").new()
			stutter.world = self
			stutter.out_path = arg.get_slice("=", 1)
			add_child(stutter)
		if arg.begins_with("--flicker-probe="):
			var flicker: Node = preload("res://scripts/debug/flicker_probe.gd").new()
			flicker.world = self
			flicker.out_dir = arg.get_slice("=", 1)
			add_child(flicker)


static func static_key(proto_id: int, fx: int, fy: int) -> String:
	return "%d:%d:%d" % [proto_id, fx, fy]


static func chunk_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CHUNK), floori(pos.y / CHUNK))


## Forgets the world. A surface change (`surface`) keeps the prototype dictionaries.
func reset(keep_protos := false) -> void:
	# Hidden now and freed over the next frames (_free_unloaded): freeing all 441 at once after a
	# respawn or a surface change took a quarter of a second.
	for cv in chunks.values():
		cv.visible = false
		_unloaded.append(cv)
	chunks.clear()
	entities.clear()
	_ghosts.clear()
	_tile_ghosts.clear()
	_pipes.clear()
	_walls.clear()
	_cargo.clear()
	_cargo_tiles.clear()
	_cargo_ghosts.clear()
	_cargo_ghost_tiles.clear()
	working.clear()
	_stated.clear()
	animator.reset()
	if not keep_protos:
		protos.clear()
	_subscribed = []
	_asked = {}
	_coming = {}
	_dirty.clear()
	_pending.clear()
	_partial.clear()
	_dirty_terrain.clear()
	_waiting_gfx.clear()
	# Every chunk drawn with the old surface's ground is gone: room for the new one's.
	TerrainTextures.trim()
	_last_focus_sent = Vector2(INF, INF)


func set_focus(pos: Vector2) -> void:
	_focus = pos


func focus() -> Vector2:
	return _focus


func entity_count() -> int:
	return entities.size()


func loaded_chunk_count() -> int:
	var n := 0
	for cv in chunks.values():
		if cv.loaded:
			n += 1
	return n


func handle(msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"protos":
			protos.add_entities(_array(msg.get("l")))
		"tprotos":
			protos.add_tiles(_array(msg.get("l")))
		"iprotos":
			protos.add_items(_array(msg.get("l")))
		"fprotos":
			protos.add_fluids(_array(msg.get("l")))
		"ready":
			_subscribed = []  # subscribe on the next frame
			_asked = {}
			_coming = {}
		"chunk":
			_on_chunk(msg)
		"ents":
			var cv: ChunkView = chunks.get(Vector2i(int(msg.get("cx", 0)), int(msg.get("cy", 0))))
			if cv != null:
				cv.got_part(int(msg.get("part", 1)))
			for rec in _array(msg.get("e")):
				_add(rec)
		"add", "upd":
			_add(msg.get("e"))
			if str(msg.get("t", "")) == "add":
				_clear_remnants_under(msg.get("e"))
		"del":
			var unit := int(msg.get("u", 0))
			if unit > 0:
				_remove(unit)
			else:
				_remove(static_key(int(msg.get("p", 0)), int(msg.get("x", 0)), int(msg.get("y", 0))))
		"tiles":
			_on_tiles(_array(msg.get("l")))
		"st":
			_on_states(_array(msg.get("l")))
		"aiu":
			_on_alt_icons(_array(msg.get("l")))
			_on_alt_fluids(_array(msg.get("fa")))


func _on_chunk(msg: Dictionary) -> void:
	var c := Vector2i(int(msg.get("cx", 0)), int(msg.get("cy", 0)))
	var cv: ChunkView = chunks.get(c)
	if cv == null:
		return  # no longer wanted
	for key in cv.entities.keys():
		entities.erase(key)
		if _cargo.has(key) or _cargo_ghosts.has(key):
			_remove_cargo(key)  # a bay gone while the chunk was resent must open its neighbours' sides
	cv.clear_entities()
	var before := cv.tile_ids
	var was_loaded := cv.loaded
	if msg.get("none", false):
		cv.mark_missing()
		cv.start_snapshot(0)
	else:
		var rle := _array(msg.get("tiles"))
		cv.set_tiles_rle(rle)
		if cv.tiles_msec == 0:
			cv.tiles_msec = Time.get_ticks_msec()
		cv.start_snapshot(int(msg.get("parts", 1)))
		# Start reading the pictures of new kinds of ground now, before the chunk is meshed.
		for i in range(0, rle.size(), 2):
			var id := int(rle[i])
			if id < protos.tile_names.size() and not protos.is_void(id):
				TerrainTextures.lookup(protos.tile_names[id])
	_dirty[c] = true
	# The mod resends every chunk now and then to heal losses; the ground rarely changed.
	if was_loaded and cv.tile_ids == before:
		return
	_dirty_terrain[c] = true
	_dirty_terrain_around(c)


## [unit, proto id, x, y, direction, extra?] with x, y in 1/256 tiles.
func _add(a) -> void:
	if not (a is Array) or a.size() < 5:
		return
	var r := Rec.new()
	r.unit = int(a[0])
	r.proto_id = int(a[1])
	r.fixed = Vector2i(int(a[2]), int(a[3]))
	r.pos = Vector2(r.fixed) / 256.0
	r.dir = int(a[4])
	if a.size() > 5 and a[5] is Dictionary:
		r.extra = a[5]
		if r.extra.has("pc"):
			r.extra["pc_mod"] = true
		# A cliff has no direction of its own: its piece is turned to its orientation.
		var cliff = ModelLibrary.CLIFF_PIECES.get(str(r.extra.get("co", "")))
		if cliff != null:
			r.dir = int(cliff[1])
	r.key = r.unit if r.unit > 0 else static_key(r.proto_id, r.fixed.x, r.fixed.y)
	r.chunk = chunk_of(r.pos)
	var cv: ChunkView = chunks.get(r.chunk)
	if cv == null:
		return
	if r.unit != 0 and working.has(r.unit):
		_stated_in(r.chunk)[r.unit] = true
	if entities.has(r.key):
		_remove(r.key)
	# A ghost (extra.gh) goes when its entity is built on its spot, which robots do without telling.
	if r.extra.has("tg"):
		_tile_ghosts[Vector2i(floori(r.pos.x), floori(r.pos.y))] = r.key
	if r.extra.has("gh"):
		_ghosts[r.fixed] = r.key
	elif _ghosts.has(r.fixed):
		var ghost: Rec = entities.get(_ghosts[r.fixed])
		if ghost != null and int(ghost.extra.get("gh", 0)) == r.proto_id:
			_remove(ghost.key)
	entities[r.key] = r
	cv.entities[r.key] = r
	if r.extra.has("ai") and not alt_icon(r).is_empty():
		cv.alt[r.key] = r
	cv.pick_grid = []
	var rp := protos.entity(r.proto_id)
	if rp != null and ModelLibrary.REMNANT_TYPES.has(rp.type):
		_remnants[r.key] = r
	_dirty[r.chunk] = true
	if _is_pipe(r):
		_pipes[_tile_of(r)] = r.key
		_connect_pipes_around(_tile_of(r))
	if _is_wall(r):
		_walls[_tile_of(r)] = r.key
		_connect_walls_around(_tile_of(r))
	if _is_cargo(r):
		_add_cargo(r, false)
	elif _is_cargo_ghost(r):
		_add_cargo(r, true)


## Alt-mode's icons that changed with no new record (issue #9, `aiu`): [unit, kind, name, more?],
## kind "" when it shows none now. Only the icon changes; the chunk isn't drawn again.
func _on_alt_icons(list: Array) -> void:
	for row in list:
		if not (row is Array) or row.size() < 2:
			continue
		var r: Rec = entities.get(int(row[0]))
		if r == null:
			continue
		var cv: ChunkView = chunks.get(r.chunk)
		if str(row[1]) == "" or row.size() < 3:
			r.extra.erase("ai")
			if cv != null:
				cv.alt.erase(r.key)
			continue
		r.extra["ai"] = row.slice(1)
		if cv != null:
			cv.alt[r.key] = r


## A crafting machine's recipe's fluids changed (`aiu` fa: [unit, mask], 1 in, 2 out): Alt-mode's
## machine arrows (alt_arrows.gd) follow.
func _on_alt_fluids(list: Array) -> void:
	for row in list:
		if not (row is Array) or row.size() < 2:
			continue
		var r: Rec = entities.get(int(row[0]))
		if r == null:
			continue
		if int(row[1]) > 0:
			r.extra["fa"] = int(row[1])
		else:
			r.extra.erase("fa")
		alt_changed.emit(r.chunk)


## Alt-mode's icon of a record as [kind, name, more names...], or [] for none.
static func alt_icon(r: Rec) -> Array:
	var ai = r.extra.get("ai")
	if not (ai is Array) or ai.size() < 2 or str(ai[1]) == "":
		return []
	var icon := [str(ai[0]), str(ai[1])]
	if ai.size() >= 3 and ai[2] is Array:  # a filter inserter's other filters
		for f in ai[2]:
			icon.append(str(f))
	return icon


## Factorio removes remnants an entity is built over (CorpsePrototype remove_on_entity_placement).
func _clear_remnants_under(a) -> void:
	if _remnants.is_empty() or not (a is Array) or a.size() < 5:
		return
	var proto := protos.entity(int(a[1]))
	if proto == null or ModelLibrary.REMNANT_TYPES.has(proto.type) or ModelLibrary.hidden(proto.name):
		return
	var pos := Vector2(int(a[2]), int(a[3])) / 256.0
	var lo := proto.box_min
	var hi := proto.box_max
	if int(a[4]) % 8 == 4:  # east or west: the box turns
		lo = Vector2(-proto.box_max.y, proto.box_min.x)
		hi = Vector2(-proto.box_min.y, proto.box_max.x)
	var box := Rect2(pos + lo, hi - lo)
	for key in _remnants.keys():
		var r: Rec = _remnants[key]
		if box.has_point(r.pos):
			_remove(key)


func _remove(key) -> void:
	var r: Rec = entities.get(key)
	if r == null:
		return
	entities.erase(key)
	_remnants.erase(key)
	if _ghosts.get(r.fixed) == key:
		_ghosts.erase(r.fixed)
	var tile := Vector2i(floori(r.pos.x), floori(r.pos.y))
	if _tile_ghosts.get(tile) == key:
		_tile_ghosts.erase(tile)
	if _pipes.get(_tile_of(r)) == key:
		_pipes.erase(_tile_of(r))
		_connect_pipes_around(_tile_of(r))
	if _walls.get(_tile_of(r)) == key:
		_walls.erase(_tile_of(r))
		_connect_walls_around(_tile_of(r))
	if _cargo.has(key) or _cargo_ghosts.has(key):
		_remove_cargo(key)
	var cv: ChunkView = chunks.get(r.chunk)
	if cv != null:
		cv.entities.erase(key)
		cv.alt.erase(key)
		cv.pick_grid = []
		_dirty[r.chunk] = true


## Pipes are drawn with the piece of Factorio's pipe kit that matches their connections
## (model_library.gd): `extra.pc`, a bit each for north, east, south, west (1, 2, 4, 8). The real
## mod sends it (pipe_mask in world.lua, machines included) and is trusted; for older mods and
## the mock it's worked out here from neighbouring pipes and pipes-to-ground, so a pipe ending
## at a machine shows an end cap there.
const PIPE_STEPS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


func _is_pipe(r: Rec) -> bool:
	var proto: ProtoDB.EntityProto = protos.entity(r.proto_id)
	return proto != null and (proto.type == "pipe" or proto.type == "infinity-pipe" or proto.type == "pipe-to-ground" or proto.type == "heat-pipe") 		and not r.extra.has("gh")


static func _tile_of(r: Rec) -> Vector2i:
	return Vector2i(floori(r.pos.x), floori(r.pos.y))


func _connect_pipes_around(tile: Vector2i) -> void:
	_connect_pipe(tile)
	for step in PIPE_STEPS:
		_connect_pipe(tile + step)


func _connect_pipe(tile: Vector2i) -> void:
	var r: Rec = entities.get(_pipes.get(tile, -1))
	if r == null or r.extra.has("pc_mod"):
		return
	# Heat pipes join only heat pipes (a reactor's or heat exchanger's connections aren't known
	# here, so a heat pipe ending at one shows its end cap), fluid pipes only fluid pipes.
	var heat := protos.entity(r.proto_id).type == "heat-pipe"
	if not heat and not protos.entity(r.proto_id).type in ["pipe", "infinity-pipe"]:
		return
	var mask := 0
	for i in 4:
		var other: Rec = entities.get(_pipes.get(tile + PIPE_STEPS[i], -1))
		if other == null:
			continue
		if heat != (protos.entity(other.proto_id).type == "heat-pipe"):
			continue
		# A pipe-to-ground joins only the pipe its above-ground end faces (direction 0 north,
		# 4 east, 8 south, 12 west, so facing back at this tile is the opposite of step i).
		if protos.entity(other.proto_id).type == "pipe-to-ground" and other.dir != ((i + 2) % 4) * 4:
			continue
		mask |= 1 << i
	if int(r.extra.get("pc", -1)) != mask:
		r.extra["pc"] = mask
		_dirty[r.chunk] = true


## Walls are drawn with the piece that joins their neighbours (model_library.gd, WALL_SHAPES):
## `extra.wc`, a bit each for north, east, south, west (1, 2, 4, 8), like pipes. A wall joins
## the walls next to it, and a gate that runs the same way (a gate facing north or south stands
## in a north-south wall). Bit 16: the walls to the east, south and south-east make a 2x2 block,
## and the gap in its middle is filled (Factorio's "filling" picture).
func _is_wall(r: Rec) -> bool:
	var proto: ProtoDB.EntityProto = protos.entity(r.proto_id)
	return proto != null and (proto.type == "wall" or proto.type == "gate") and not r.extra.has("gh")


func _connect_walls_around(tile: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			_connect_wall(tile + Vector2i(dx, dy))


func _connect_wall(tile: Vector2i) -> void:
	var r: Rec = entities.get(_walls.get(tile, -1))
	if r == null or protos.entity(r.proto_id).type != "wall":
		return
	var mask := 0
	for i in 4:
		var other: Rec = entities.get(_walls.get(tile + PIPE_STEPS[i], -1))
		if other == null:
			continue
		if protos.entity(other.proto_id).type == "gate" and (other.dir / 4) % 2 != i % 2:
			continue
		mask |= 1 << i
	if mask & 6 == 6:
		var corner: Rec = entities.get(_walls.get(tile + Vector2i(1, 1), -1))
		if corner != null and protos.entity(corner.proto_id).type == "wall":
			mask |= 16
	if int(r.extra.get("wc", -1)) != mask:
		r.extra["wc"] = mask
		_dirty[r.chunk] = true


## Cargo bays draw the edges of the cargo area they belong to (ModelLibrary.cargo_pieces):
## `extra.cb`, a neighbour mask for each of the bay's four 2x2 cells, from the tiles covered by
## hubs, bays and landing pads. Factorio doesn't hold bays to a 2-tile grid, so a neighbouring
## cell counts as cargo area when at least half its tiles are.
func _is_cargo(r: Rec) -> bool:
	var proto: ProtoDB.EntityProto = protos.entity(r.proto_id)
	return proto != null and ModelLibrary.CARGO_TYPES.has(proto.type) and not r.extra.has("gh")


func _is_cargo_ghost(r: Rec) -> bool:
	var proto: ProtoDB.EntityProto = protos.entity(int(r.extra.get("gh", -1)))
	return proto != null and ModelLibrary.CARGO_TYPES.has(proto.type)


func _cargo_rect(r: Rec) -> Rect2i:
	return cargo_rect(protos.entity(int(r.extra["gh"]) if r.extra.has("gh") else r.proto_id), r.pos)


## The tiles a hub, bay or landing pad at `pos` covers.
static func cargo_rect(proto: ProtoDB.EntityProto, pos: Vector2) -> Rect2i:
	var lo := Vector2i(roundi(pos.x + proto.box_min.x), roundi(pos.y + proto.box_min.y))
	var hi := Vector2i(roundi(pos.x + proto.box_max.x), roundi(pos.y + proto.box_max.y))
	return Rect2i(lo, hi - lo)


func _add_cargo(r: Rec, ghost: bool) -> void:
	if _cargo.has(r.key) or _cargo_ghosts.has(r.key):
		_remove_cargo(r.key)
	var area := _cargo_ghosts if ghost else _cargo
	var tiles := _cargo_ghost_tiles if ghost else _cargo_tiles
	var rect := _cargo_rect(r)
	area[r.key] = rect
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			tiles[Vector2i(x, y)] = int(tiles.get(Vector2i(x, y), 0)) + 1
	_connect_cargo_near(rect)


func _remove_cargo(key) -> void:
	var ghost := _cargo_ghosts.has(key)
	var area := _cargo_ghosts if ghost else _cargo
	var tiles := _cargo_ghost_tiles if ghost else _cargo_tiles
	var rect: Rect2i = area[key]
	area.erase(key)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var t := Vector2i(x, y)
			var left := int(tiles.get(t, 0)) - 1
			if left > 0:
				tiles[t] = left
			else:
				tiles.erase(t)
	_connect_cargo_near(rect)


func _connect_cargo_near(rect: Rect2i) -> void:
	var near := rect.grow(4)
	for key in _cargo:
		if near.intersects(_cargo[key]):
			var r: Rec = entities.get(key)
			if r != null and protos.entity(r.proto_id).type == "cargo-bay":
				_connect_cargo(r)
	# Ghost bays nearby join the built ones too (ghosts.gd works theirs out when it redraws).
	for corner in [near.position, near.end, Vector2i(near.position.x, near.end.y), Vector2i(near.end.x, near.position.y)]:
		var c := chunk_of(Vector2(corner))
		if chunks.has(c):
			_dirty[c] = true


const CARGO_AROUND := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]


func _connect_cargo(r: Rec) -> void:
	var cb := cargo_mask(_cargo[r.key])
	if int(r.extra.get("cb", -1)) != cb:
		r.extra["cb"] = cb
		_dirty[r.chunk] = true


## extra.cb for a bay over `rect`, from the built cargo area round it (and with `ghosts`, the ghost
## bays' too). The bay's own tiles count even before it is built, so a ghost bay and the held bay's
## preview are framed as it will be.
func cargo_mask(rect: Rect2i, ghosts := false) -> int:
	var cb := 0
	for k in 4:
		var cell := rect.position + Vector2i(k % 2, k / 2) * 2
		var mask := 0
		for b in 8:
			var at: Vector2i = cell + CARGO_AROUND[b] * 2
			var covered := 0
			for t in [at, at + Vector2i(1, 0), at + Vector2i(0, 1), at + Vector2i(1, 1)]:
				if _cargo_tiles.has(t) or rect.has_point(t) or (ghosts and _cargo_ghost_tiles.has(t)):
					covered += 1
			if covered >= 2:
				mask |= 1 << b
		cb |= mask << (8 * k)
	return cb


## Flat [x, y, tile id, ...]
func _on_tiles(list: Array) -> void:
	var i := 0
	while i + 2 < list.size():
		var x := int(list[i])
		var y := int(list[i + 1])
		var c := Vector2i(floori(x / float(CHUNK)), floori(y / float(CHUNK)))
		var cv: ChunkView = chunks.get(c)
		if cv != null:
			var local := Vector2i(x - c.x * CHUNK, y - c.y * CHUNK)
			cv.set_tile(local, int(list[i + 2]))
			# A tile ghost goes when its tile is laid (robots don't say).
			var tg: Rec = entities.get(_tile_ghosts.get(Vector2i(x, y), -1))
			if tg != null and int(tg.extra.get("tg", 0)) == int(list[i + 2]):
				_remove(tg.key)
			_dirty_terrain[c] = true
			# Banks and foam next door depend on tiles along this chunk's edge.
			if local.x == 0 or local.y == 0 or local.x == CHUNK - 1 or local.y == CHUNK - 1:
				_dirty_terrain_around(c)
		i += 3


## Tile id at a world tile position, or -1 if its chunk isn't loaded (or doesn't exist).
func tile_at(x: int, y: int) -> int:
	var c := Vector2i(floori(x / float(CHUNK)), floori(y / float(CHUNK)))
	var cv: ChunkView = chunks.get(c)
	if cv == null or cv.tile_ids.size() != CHUNK * CHUNK:
		return -1
	return cv.tile_ids[(y - c.y * CHUNK) * CHUNK + (x - c.x * CHUNK)]


## A chunk's banks and shore foam depend on its neighbours' edge tiles (an unloaded neighbour
## gets banks, as it might be water), so neighbours rebuild whenever a chunk's tiles arrive or
## go. Chunks without tiles have no terrain to rebuild.
func _dirty_terrain_around(c: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			var cv: ChunkView = chunks.get(n)
			if n != c and cv != null and cv.tile_ids.size() == CHUNK * CHUNK:
				_dirty_terrain[n] = true


## Flat [unit, 0/1, ...]
func _on_states(list: Array) -> void:
	var i := 0
	while i + 1 < list.size():
		var unit := int(list[i])
		var state := int(list[i + 1])
		var was: int = working.get(unit, -1)
		working[unit] = state
		# Models show the state through anim.gd; placeholders change colour, so rebuild.
		var r: Rec = entities.get(unit)
		if r != null:
			if was < 0:
				_stated_in(r.chunk)[unit] = true
			var cv: ChunkView = chunks.get(r.chunk)
			if cv != null and cv.placeholder_keys.has(r.key):
				_dirty[r.chunk] = true
			if state != was:
				animator.state_changed(r)
		i += 2


## The units with a state (`working`) by their record's chunk, for what looks at machines near a
## point a few times a second (fx.gd's sounds and smoke, working_glow.gd): they went through every
## state in the world, tens of thousands on a big base, 2-5 ms each time while walking.
var _stated := {}  # Vector2i -> {unit: true}


func _stated_in(c: Vector2i) -> Dictionary:
	var units: Dictionary = _stated.get(c, {})
	if units.is_empty():
		_stated[c] = units
	return units


## The units with a state whose record lies in the chunks within `radius` tiles of `at` (a square).
func working_near(at: Vector2, radius: float) -> Array:
	var out: Array = []
	var lo := chunk_of(at - Vector2(radius, radius))
	var hi := chunk_of(at + Vector2(radius, radius))
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var c := Vector2i(cx, cy)
			var units: Dictionary = _stated.get(c, {})
			for unit in units.keys():
				var r: Rec = entities.get(unit)
				if r == null or r.chunk != c:
					units.erase(unit)  # gone, or moved to another chunk's set
				else:
					out.append(unit)
	return out


func _process(delta: float) -> void:
	if not Bridge.world_ready:
		return
	var t0 := Time.get_ticks_usec()
	_update_subscription(delta)
	_prof("subscribe", t0)
	_free_unloaded()
	_update_focus(delta)
	t0 = Time.get_ticks_usec()
	if ModelLibrary.poll():
		# Models made on worker threads are ready: draw the chunks that left them out.
		for c in chunks:
			if (chunks[c] as ChunkView).waiting_models:
				_dirty[c] = true
	_prof("models_poll", t0)
	_rebuild_dirty()
	t0 = Time.get_ticks_usec()
	_update_shadow_casters()
	_prof("shadows", t0)
	_watch_for_missing(delta)
	if track_latency:
		_track_latency(delta)


## --stutter-probe: how long chunks take to appear. A chunk entering the wanted square round the
## focus is noted, and again if it comes within NEAR_RING chunks of the focus still not drawn (in
## view at the default camera); once drawn (its ground and buildings), the time it took goes to
## drawn_latency as [ms since wanted, its ring from the focus's chunk then, ms since it came near
## or -1]. undrawn() is how many wanted aren't drawn yet, near_undrawn how many of them are near.
const NEAR_RING := 2
var near_undrawn := 0
var _near_at := {}
var track_latency := false
var drawn_latency: Array = []
var _wanted_at := {}  # Vector2i -> msec it was first wanted (while not drawn)
var _latency_timer := 0.0
var _latency_center := Vector2i(0x7fffffff, 0)


func _track_latency(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _wanted_center != _latency_center:
		_latency_center = _wanted_center
		var wanted := {}
		for c in _wanted:
			wanted[c] = true
			if not _wanted_at.has(c) and not _drawn(c):
				_wanted_at[c] = now
		for c in _wanted_at.keys():
			if not wanted.has(c):
				_wanted_at.erase(c)  # left the square before it was drawn
				_near_at.erase(c)
	_latency_timer += delta
	if _latency_timer < 0.05:
		return
	_latency_timer = 0.0
	near_undrawn = 0
	for c: Vector2i in _wanted_at.keys():
		var ring := maxi(absi(c.x - _wanted_center.x), absi(c.y - _wanted_center.y))
		if _drawn(c):
			drawn_latency.append([now - int(_wanted_at[c]), ring, now - int(_near_at[c]) if _near_at.has(c) else -1])
			_wanted_at.erase(c)
			_near_at.erase(c)
		elif ring <= NEAR_RING:
			near_undrawn += 1
			if not _near_at.has(c):
				_near_at[c] = now


func undrawn() -> int:
	return _wanted_at.size()


## A gap can't say what it lost, so this guesses: chunks known to be incomplete, chunks still
## empty long after the stream went quiet, and if neither, the lost message was probably a
## change near the player, so the 3x3 chunks around the focus.
func resync_list() -> Array:
	var list: Array = []
	for cv in chunks.values():
		if _missing(cv):
			list.append([cv.coord.x, cv.coord.y])
	if list.is_empty():
		var center := chunk_of(_focus)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := center + Vector2i(dx, dy)
				if chunks.has(c):
					list.append([c.x, c.y])
	return list


func _watch_for_missing(delta: float) -> void:
	_watchdog_timer += delta
	if _watchdog_timer < WATCHDOG_INTERVAL:
		return
	_watchdog_timer = 0.0
	for cv in chunks.values():
		if _missing(cv):
			Bridge.request_resync(false)
			return


func _missing(cv: ChunkView) -> bool:
	return cv.is_incomplete() or (not cv.loaded and Time.get_ticks_msec() - cv.created_msec > MISSING_CHUNK_MSEC)


var _wanted: Array = []  # the chunks round the focus, nearest first
var _wanted_center := Vector2i(0x7fffffff, 0)
var _wanted_radius := -1
var _asked := {}  # _subscribed as a set
var _coming := {}  # chunks asked for and not drawn yet
var _wanted_moved := false  # _wanted changed since the last step


## The offsets of a square of chunks `radius` round its middle, nearest first (by squared distance,
## then row by row). The subscription list used to be sorted with a GDScript comparison whenever the
## focus crossed a chunk edge: 841 chunks at Ultra, 3-12 ms in one frame while walking (docs/
## PERFORMANCE-AUDIT.md 4.7). Now one pass into buckets, and only when the radius changes.
static var _ring_orders := {}


static func ring_order(radius: int) -> Array:
	var order: Array = _ring_orders.get(radius, [])
	if not order.is_empty():
		return order
	var buckets := {}  # squared distance -> offsets
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d := dx * dx + dy * dy
			if not buckets.has(d):
				buckets[d] = []
			(buckets[d] as Array).append(Vector2i(dx, dy))
	var distances: Array = buckets.keys()
	distances.sort()
	for d in distances:
		order.append_array(buckets[d])
	_ring_orders[radius] = order
	return order


func _update_subscription(delta: float) -> void:
	var center := chunk_of(_focus)
	# The wanted list only changes with the focus's chunk or the view radius.
	if center != _wanted_center or view_radius != _wanted_radius:
		if center != _wanted_center:
			_moved_msec = Time.get_ticks_msec()
		_wanted_center = center
		_wanted_radius = view_radius
		_wanted = []
		for offset: Vector2i in ring_order(view_radius):
			_wanted.append(center + offset)
		_wanted_moved = true
		_stream_timer = STREAM_STEP  # the next step now: the chunks no longer wanted go at once
	_sub_timer += delta
	_stream_timer += delta
	if _stream_timer < STREAM_STEP and _sub_timer < SUBSCRIBE_REFRESH:
		return
	_stream_timer = 0.0
	# What was asked for and is still wanted stays; then the nearest of the rest, while fewer than
	# the allowance are on their way (asked for, not drawn yet). Worked out again only when the
	# focus crossed a chunk edge, a chunk can be added or the subscription is resent: most steps
	# while walking have nothing to do.
	var allowed := STREAM_MOVING if Time.get_ticks_msec() - _moved_msec < MOVING_FOR * 1000.0 else STREAM_STILL
	for c in _coming.keys():
		if _drawn(c) or absi(c.x - center.x) > view_radius or absi(c.y - center.y) > view_radius:
			_coming.erase(c)  # drawn, or no longer wanted (it goes below)
	var refresh := _sub_timer >= SUBSCRIBE_REFRESH
	if not (_wanted_moved or refresh or (_coming.size() < allowed and _subscribed.size() < _wanted.size())):
		return
	_wanted_moved = false
	# One pass in the wanted list's order, so the list comes out nearest first (the mod sends
	# chunks in this order).
	var list: Array = []
	var keep := {}
	for c in _wanted:
		if _asked.has(c):
			list.append(c)
			keep[c] = true
		elif _coming.size() < allowed:
			list.append(c)
			keep[c] = true
			_coming[c] = true
			if not chunks.has(c):
				var cv := ChunkView.new()
				cv.coord = c
				cv.name = "Chunk_%d_%d" % [c.x, c.y]
				ChunkView.count("new_chunk")
				add_child(cv)
				chunks[c] = cv
	# Chunks no longer wanted leave at once; their records and nodes go over the next frames
	# (_free_unloaded).
	for c in chunks.keys():
		if not keep.has(c):
			_unload(c)
	for c in _coming.keys():
		if not keep.has(c):
			_coming.erase(c)
	_asked = keep
	if refresh or list != _subscribed:
		_sub_timer = 0.0
		_subscribed = list
		var out: Array = []
		for c in list:
			out.append([c.x, c.y])
		Bridge.send({"t": "sub", "c": out})


## Builds a chunk's entities again (far_chunks.gd, when it swaps between merged and full).
func redraw(c: Vector2i) -> void:
	if chunks.has(c):
		_dirty[c] = true


## Whether a chunk asked for has arrived and is drawn (its ground, and its buildings built).
func _drawn(c: Vector2i) -> bool:
	var cv: ChunkView = chunks.get(c)
	return cv != null and cv.loaded and cv.has_ground() and not _dirty.has(c) and not _pending.has(c) and not _partial.has(c)


func _unload(c: Vector2i) -> void:
	var cv: ChunkView = chunks[c]
	ChunkView.count("unload")
	chunks.erase(c)
	_dirty.erase(c)
	_pending.erase(c)
	_partial.erase(c)
	_dirty_terrain.erase(c)
	_waiting_gfx.erase(c)
	# Its records leave `entities`, entities_changed goes out and it is freed within a time budget
	# (_free_unloaded): walking over a chunk's edge lets a whole row of 29 go at once, and a busy
	# chunk's thousands of records and 60-150 nodes took 1.5-5 ms each. Until then it stays drawn
	# past the view's edge.
	_unload_keys[cv] = [cv.entities.keys(), 0]
	_unloaded.append(cv)


## Unloaded chunks waiting for their records to leave `entities`: ChunkView -> [keys, next].
var _unload_keys := {}


## Takes unloaded chunks apart within UNLOAD_USEC a frame (at least one step): their records out of
## `entities` (only those still theirs: the chunk may have come back meanwhile), entities_changed,
## then their nodes one by one (a busy chunk's took up to 5 ms freed at once), then the chunk.
func _free_unloaded() -> void:
	if _unloaded.is_empty():
		FrameBudget.waiting(&"unload", 0)
		return
	var t0 := Time.get_ticks_usec()
	var steps := 0
	var allow := FrameBudget.grant(&"unload")
	while allow > 0 and not _unloaded.is_empty():
		if steps > 0 and Time.get_ticks_usec() - t0 > allow:
			break
		var cv: ChunkView = _unloaded[0]
		if not is_instance_valid(cv):
			_unloaded.pop_front()
			_unload_keys.erase(cv)
			continue
		var job: Array = _unload_keys.get(cv, [])
		if not job.is_empty():
			var keys: Array = job[0]
			var i := int(job[1])
			while i < keys.size():
				var key = keys[i]
				if entities.get(key) == cv.entities.get(key):
					entities.erase(key)
				i += 1
				steps += 1
				if (i & 63) == 0 and Time.get_ticks_usec() - t0 > allow:
					break
			if i < keys.size():
				job[1] = i
				break
			_unload_keys.erase(cv)
			entities_changed.emit(cv.coord)
			steps += 1
			continue
		if cv.visible:
			cv.visible = false
		var n := cv.get_child_count()
		if n > 0:
			cv.get_child(n - 1).free()
		else:
			_unloaded.pop_front()
			cv.free()
		steps += 1
	_prof("unload_free", t0)
	FrameBudget.spent(&"unload", Time.get_ticks_usec() - t0, _unloaded.size())


## How much streaming work waits (for --stutter-probe): chunks part-way through a build, chunks
## whose shadow settings are still to be set, unloaded chunks' records still to go.
func stream_queues() -> Dictionary:
	var records := 0
	for job: Array in _unload_keys.values():
		records += (job[0] as Array).size() - int(job[1])
	return {"partial": _partial.size(), "shadow": maxi(_shadow_todo.size() - _shadow_next, 0), "free_records": records}


## How far from the camera the mod streams moving things and machine states (the "Entity distance"
## setting); a change goes out at once.
func set_focus_radius(r: int) -> void:
	if r != focus_radius:
		focus_radius = r
		_last_focus_sent = Vector2(INF, INF)


## The 3D remote view is on: the mod then sends moving things only where radars see (focus `rv`).
func set_remote_view(on: bool) -> void:
	if on != remote_view:
		remote_view = on
		_last_focus_sent = Vector2(INF, INF)
		_focus_timer = FOCUS_INTERVAL


func _update_focus(delta: float) -> void:
	_focus_timer += delta
	if _focus_timer < FOCUS_INTERVAL:
		return
	_focus_timer = 0.0
	if _focus.distance_to(_last_focus_sent) < 1.0:
		return
	_last_focus_sent = _focus
	var msg := {"t": "focus", "x": int(_focus.x * 256.0), "y": int(_focus.y * 256.0), "r": focus_radius}
	if remote_view:
		msg["rv"] = 1
	Bridge.send(msg)


func _rebuild_dirty() -> void:
	var tp := Time.get_ticks_usec()
	if TerrainTextures.poll():
		_refresh_gfx_table()
		# Chunks drawn without a picture that is ready now are built again with it.
		for c in _waiting_gfx.keys():
			for id in _waiting_gfx[c]:
				if id < _gfx_table.size() and _gfx_table[id] != null:
					_dirty_terrain[c] = true
					_waiting_gfx.erase(c)
					break
	_prof("terrain_poll", tp)
	tp = Time.get_ticks_usec()
	_finish_terrain_jobs()
	_prof("terrain_finish", tp)
	tp = Time.get_ticks_usec()
	_start_terrain_jobs()
	_prof("terrain_start", tp)
	var center := chunk_of(_focus)
	var nearer := func(a: Vector2i, b: Vector2i) -> bool: return (a - center).length_squared() < (b - center).length_squared()
	# One budget object, filled again each frame: a build part-way through holds on to it.
	var surfaces := _surfaces
	surfaces.left = NEW_SURFACES
	var build_t0 := Time.get_ticks_usec()
	if _dirty.is_empty() and _partial.is_empty() and _pending.is_empty():
		FrameBudget.waiting(&"build", 0)
		return
	var granted := FrameBudget.grant(&"build")
	if FrameBudget.shared and granted <= 0:
		FrameBudget.spent(&"build", 0, _dirty.size() + _partial.size() + _pending.size())
		return
	# Chunks already built go on adding what they left for later first, nearest first.
	if not _pending.is_empty():
		tp = Time.get_ticks_usec()
		var order: Array = _pending.keys()
		order.sort_custom(nearer)
		for c: Vector2i in order:
			if surfaces.left <= 0:
				break
			var pcv: ChunkView = chunks.get(c)
			if pcv != null and pcv.building:
				continue
			if pcv == null or pcv.add_pending(working, animator, surfaces):
				_pending.erase(c)
		_prof("pending", tp)
	# The time for builds starts after the MultiMeshes left for later were added (as before).
	var started := Time.get_ticks_usec()
	var allowed := clampi(FRAME_WORK_USEC - Bridge.frame_handle_usec, REBUILD_MIN_USEC, REBUILD_USEC)
	# Builds stop part-way at the deadline instead of finishing a busy chunk whatever it costs (10-24
	# ms), so when chunks queue up they get the whole REBUILD_USEC: as many built as before, in frames
	# of a bounded length.
	if _dirty.size() + _partial.size() > REBUILDS_PER_FRAME:
		allowed = REBUILD_USEC
	# With the frame's work shared (frame_budget.gd) the builds take what the scheduler gives them,
	# and nothing at all when it gives nothing.
	if FrameBudget.shared:
		allowed = granted - (started - build_t0)
		if allowed <= 0:
			FrameBudget.spent(&"build", Time.get_ticks_usec() - build_t0, _dirty.size() + _partial.size() + _pending.size())
			return
	var until := started + allowed
	var budget := REBUILDS_PER_FRAME
	# Builds part-way through carry on first, nearest first.
	if not _partial.is_empty():
		var order: Array = _partial.keys()
		order.sort_custom(nearer)
		for c: Vector2i in order:
			if budget < REBUILDS_PER_FRAME and Time.get_ticks_usec() > until:
				break
			var bcv: ChunkView = chunks.get(c)
			if bcv == null or not bcv.building:
				_partial.erase(c)
				continue
			var tb := Time.get_ticks_usec()
			bcv.resume_build(until)
			budget -= 1
			if bcv.building:
				_prof("build", tb)
			else:
				_partial.erase(c)
				_built(c, bcv, tb)
	var waiting: Array = _dirty.keys()
	if waiting.size() > budget:
		# Nearest the focus first, so after a jump the buildings round the character come first.
		waiting.sort_custom(nearer)
	for c in waiting:
		if budget <= 0 or (budget < REBUILDS_PER_FRAME and Time.get_ticks_usec() > until):
			break
		# Building more now would only queue more for the renderer: wait for the next frame.
		if surfaces.left <= 0:
			break
		var cv: ChunkView = chunks.get(c)
		if cv != null:
			if cv.building:
				continue  # built again once the build part-way through is done (it stays dirty)
			var t0 := Time.get_ticks_usec()
			# Stops part-way at the frame's deadline and carries on next frame (_partial).
			cv.build_entities(protos, working, animator, surfaces, until)
			ChunkView.count("rebuilds")
			budget -= 1
			if cv.building:
				_partial[c] = true
				_pending.erase(c)
				_prof("build", t0)
			else:
				_built(c, cv, t0)
		_dirty.erase(c)
	FrameBudget.spent(&"build", Time.get_ticks_usec() - build_t0, _dirty.size() + _partial.size() + _pending.size())


var _surfaces := ChunkView.Budget.new(NEW_SURFACES)
var _partial := {}  # Vector2i -> true: chunks whose build stopped part-way (ChunkView.building)


## A chunk's build is done (started at `t0`, its last part this frame).
func _built(c: Vector2i, cv: ChunkView, t0: int) -> void:
	if cv.pending.is_empty():
		_pending.erase(c)
	else:
		_pending[c] = true
	_prof("build", t0)
	var te := Time.get_ticks_usec()
	entities_changed.emit(c)
	_prof("changed_signal", te)
	entity_build_usec += Time.get_ticks_usec() - t0
	entity_builds += 1


# How tall the tallest things are, for how far their shadows reach (a rocket silo's top; trees
# are 4-7 tiles).
const SHADOW_CASTER_HEIGHT := 16.0
# Chunks this many rings round the character's keep their shadows' full detail (the stand-ins
# simplify there only below a pixel of error, model_lods.gd); further out they simplify sooner.
const NEAR_SHADOW_RINGS := 1
# The view moves this far (tiles), or turns about a degree, before the casters are worked out again;
# the region is grown by as much to cover it.
const SHADOW_SLACK := 4.0


## The sun's shadow map covers what the camera sees out to its max distance, but Godot draws every
## caster in the light's box into it, out to the horizon in the sun's direction, once per shadow
## split: on a 20,000-entity base the shadow pass drew 1,400 draw calls and 20-28 million
## triangles a frame, against 0.5 million for the view itself. Only chunks whose shadows can fall
## inside the covered ground cast any, through their models' stand-ins (model_lods.gd).
func _update_shadow_casters() -> void:
	if ModelLods.poll():
		_shadow_key = []
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var on := sun != null and sun.shadow_enabled and sun.is_visible_in_tree() and cam != null
	# Worked out again only when the view, the sun or the chunks change by more than the region's
	# slack (SHADOW_SLACK).
	var key: Array = [on, chunks.size(), ModelLods.generation, ModelLods.lod_bias, chunk_of(_focus)]
	if on:
		var basis := cam.global_basis
		key.append_array([(cam.global_position / (SHADOW_SLACK * 0.5)).round(), (basis.z * 50.0).round(), (basis.x * 50.0).round(),
			roundi(cam.fov), roundi(cam.size), cam.projection, ((-sun.global_basis.z) * 20.0).round(), sun.directional_shadow_max_distance])
	if key != _shadow_key:
		_shadow_key = key
		# Gone through over the next frames (SHADOW_USEC a frame): when the focus crosses a chunk
		# edge every chunk's tier is looked at, and those that change set their MultiMeshes' shadow
		# casting, which made 4-13 ms frames while walking (docs/PERFORMANCE-AUDIT.md 4.7). A new
		# chunk casts from the start (SHADOWS_NEAR), so nothing waits for its shadow.
		_shadow_on = on
		_shadow_hull = shadow_region(cam, sun) if on else PackedVector2Array()
		_shadow_rows = {}
		_shadow_center = chunk_of(_focus)
		# A pass cut short by a new one goes on where it was, so the view moving every few frames
		# doesn't leave the same chunks always last.
		var at := _shadow_start + _shadow_next if _shadow_next < _shadow_todo.size() else 0
		_shadow_todo = chunks.values()
		_shadow_start = at % maxi(_shadow_todo.size(), 1)
		_shadow_next = 0
		_shadow_count = 0
	if _shadow_next >= _shadow_todo.size():
		FrameBudget.waiting(&"shadows", 0)
		return
	var size := _shadow_todo.size()
	var did := 0
	# Tests lift shadow_usec to set every chunk at once.
	var from_budget := shadow_usec == SHADOW_USEC
	var allow := FrameBudget.grant(&"shadows") if from_budget else shadow_usec
	var t0 := Time.get_ticks_usec()
	while not (from_budget and allow <= 0) and _shadow_next < size:
		if did > 0 and Time.get_ticks_usec() - t0 > allow:
			break
		var cv = _shadow_todo[(_shadow_start + _shadow_next) % size]
		_shadow_next += 1
		did += 1
		if not is_instance_valid(cv) or chunks.get(cv.coord) != cv:
			continue
		var tier := ChunkView.SHADOWS_NEAR
		if _shadow_on:
			var ring := maxi(absi(cv.coord.x - _shadow_center.x), absi(cv.coord.y - _shadow_center.y))
			if not _chunk_meets_hull(cv.coord):
				tier = ChunkView.SHADOWS_NONE
			elif ring > NEAR_SHADOW_RINGS:
				tier = ChunkView.SHADOWS_FAR
		(cv as ChunkView).set_shadow_tier(tier)
		if tier != ChunkView.SHADOWS_NONE:
			_shadow_count += 1
	if _shadow_next >= size:
		shadow_casters = _shadow_count
		_shadow_todo = []
		_shadow_next = 0
		_shadow_start = 0
	FrameBudget.spent(&"shadows", Time.get_ticks_usec() - t0, maxi(_shadow_todo.size() - _shadow_next, 0))


# Main-thread time a frame for setting chunks' shadow tiers (at least one chunk).
const SHADOW_USEC := 1000
var shadow_usec := SHADOW_USEC  # tests lift it to set every chunk at once
var _shadow_on := false
var _shadow_hull := PackedVector2Array()
var _shadow_rows := {}  # chunk row -> hull_row() of _shadow_hull
var _shadow_center := Vector2i.ZERO
var _shadow_todo: Array = []  # chunks still to set, in no particular order
var _shadow_next := 0  # how many of _shadow_todo are done, from _shadow_start round
var _shadow_start := 0
var _shadow_count := 0


## The ground (x, z in tiles) whose casters can throw a shadow into what the camera sees within
## the sun's shadow distance: the outline of the view out to that distance, grown by the longest
## shadow (a convex polygon).
static func shadow_region(cam: Camera3D, light: DirectionalLight3D) -> PackedVector2Array:
	var far := minf(light.directional_shadow_max_distance, cam.far)
	var size := cam.get_viewport().get_visible_rect().size
	var down := -light.global_transform.basis.z
	var reach := SHADOW_CASTER_HEIGHT / maxf(tan(asin(clampf(-down.y, 0.0, 1.0))), 0.25) + SHADOW_SLACK + far * 0.02
	var points := PackedVector2Array()
	for corner in [Vector2.ZERO, Vector2(size.x, 0.0), Vector2(0.0, size.y), size]:
		for depth in [cam.near, far]:
			var p := cam.project_position(corner, depth)
			# Grown by the reach as a square round each corner: the hull of those holds the
			# outline grown by at least the reach.
			for d in [Vector2(-reach, -reach), Vector2(reach, -reach), Vector2(-reach, reach), Vector2(reach, reach)]:
				points.append(Vector2(p.x, p.z) + d)
	return Geometry2D.convex_hull(points)


## Whether a rectangle and a convex polygon (Geometry2D.convex_hull's, closed) overlap: no
## separating axis among the rectangle's two and the polygon's edges.
static func _rect_meets_hull(rect: Rect2, hull: PackedVector2Array) -> bool:
	if hull.size() < 4:
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var middle := Vector2.ZERO
	for i in hull.size() - 1:
		lo = lo.min(hull[i])
		hi = hi.max(hull[i])
		middle += hull[i]
	if not rect.intersects(Rect2(lo, hi - lo)):
		return false
	middle /= hull.size() - 1
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in hull.size() - 1:
		var edge := hull[i + 1] - hull[i]
		var normal := Vector2(edge.y, -edge.x)
		# The hull lies on its middle's side of each edge; the rectangle is outside if all its
		# corners lie beyond one.
		var inner := signf(normal.dot(middle - hull[i]))
		var outside := true
		for c in corners:
			if signf(normal.dot(c - hull[i])) != -inner:
				outside = false
				break
		if outside:
			return false
	return true


## Whether chunk `c` meets the shadow region (_rect_meets_hull's answer): the region's extent along
## each row of chunks is worked out once a pass, so each chunk is one comparison. The hull test for
## each of ~800 chunks was most of the shadow pass's time.
func _chunk_meets_hull(c: Vector2i) -> bool:
	var row: Vector2 = _shadow_rows.get(c.y, Vector2.INF)
	if row == Vector2.INF:
		row = hull_row(_shadow_hull, float(c.y * CHUNK), float(c.y * CHUNK + CHUNK))
		_shadow_rows[c.y] = row
	return row.x <= float(c.x * CHUNK + CHUNK) and row.y >= float(c.x * CHUNK)


## How far a convex polygon (Geometry2D.convex_hull's, closed) reaches along x between y0 and y1:
## (min x, max x), or (INF, -INF) where it doesn't reach. A rectangle spanning y0..y1 meets the
## polygon exactly when its x range overlaps this (the polygon's slice of the band is convex).
static func hull_row(hull: PackedVector2Array, y0: float, y1: float) -> Vector2:
	var lo := INF
	var hi := -INF
	if hull.size() < 4:
		return Vector2(lo, hi)
	for i in hull.size() - 1:
		var a := hull[i]
		var b := hull[i + 1]
		if maxf(a.y, b.y) < y0 or minf(a.y, b.y) > y1:
			continue
		var xa := a.x
		var xb := b.x
		if a.y != b.y:
			xa = lerpf(a.x, b.x, clampf((y0 - a.y) / (b.y - a.y), 0.0, 1.0))
			xb = lerpf(a.x, b.x, clampf((y1 - a.y) / (b.y - a.y), 0.0, 1.0))
		lo = minf(lo, minf(xa, xb))
		hi = maxf(hi, maxf(xa, xb))
	return Vector2(lo, hi)


func terrain_queue_size() -> int:
	return _dirty_terrain.size() + _terrain_jobs.size()


func _refresh_gfx_table() -> void:
	_gfx_generation = TerrainTextures.generation
	var table: Array = []
	table.resize(protos.tile_names.size())
	var nothing := TerrainTextures.TileGfx.new()  # empty space: never drawn
	for id in table.size():
		table[id] = nothing if protos.is_void(id) else TerrainTextures.peek(protos.tile_names[id])
	_gfx_table = table


## Starts terrain jobs for dirty chunks: chunks with no ground yet first (holes), then the
## nearest to the focus.
func _start_terrain_jobs() -> void:
	if _dirty_terrain.is_empty() or _terrain_jobs.size() >= TERRAIN_JOBS:
		return
	if _gfx_generation != TerrainTextures.generation or _gfx_table.size() != protos.tile_names.size():
		_refresh_gfx_table()
	var center := chunk_of(_focus)
	var order: Array = []
	for c: Vector2i in _dirty_terrain:
		if _terrain_jobs.has(c):
			continue  # again once the one running is done
		var cv: ChunkView = chunks.get(c)
		var rank := (c - center).length_squared() + (0 if cv == null or not cv.has_ground() else 10000)
		order.append([rank, c])
	order.sort()
	for entry in order:
		if _terrain_jobs.size() >= TERRAIN_JOBS:
			break
		var c: Vector2i = entry[1]
		_dirty_terrain.erase(c)
		var cv: ChunkView = chunks.get(c)
		if cv == null:
			continue
		if cv.tile_ids.size() != CHUNK * CHUNK:
			cv.clear_terrain()
			continue
		var job := TerrainMesher.new()
		job.coord = c
		job.tile_ids = cv.tile_ids
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var n: ChunkView = chunks.get(c + Vector2i(dx, dy))
				job.around.append(n.tile_ids if n != null else PackedInt32Array())
		job.colors = protos.tile_colors
		job.kind_of = protos.tile_is_water
		job.gfx_of = _gfx_table
		job.textured = TerrainTextures.active()
		job.slots = cv.slots
		_terrain_jobs[c] = [WorkerThreadPool.add_task(job.run, false, "terrain"), job, cv]


## Shows the terrain jobs that are done, within a time budget.
func _finish_terrain_jobs() -> void:
	if _terrain_jobs.is_empty():
		FrameBudget.waiting(&"terrain", 0)
		return
	var t0 := Time.get_ticks_usec()
	var allow := FrameBudget.grant(&"terrain")
	for c: Vector2i in _terrain_jobs.keys():
		if allow <= 0 or Time.get_ticks_usec() - t0 > allow:
			break
		var entry: Array = _terrain_jobs[c]
		if not WorkerThreadPool.is_task_completed(entry[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(entry[0])
		_terrain_jobs.erase(c)
		var job: TerrainMesher = entry[1]
		var cv = entry[2]
		if not is_instance_valid(cv) or chunks.get(c) != cv:
			continue  # unloaded meanwhile
		var t1 := Time.get_ticks_usec()
		cv.apply_terrain(job)
		terrain_build_usec += Time.get_ticks_usec() - t1
		terrain_worker_usec += job.usec
		terrain_builds += 1
		_waiting_gfx.erase(c)
		if job.missing.is_empty():
			continue
		# Drawn in map colours where pictures are missing: read them, and build again when ready.
		_waiting_gfx[c] = job.missing
		for id in job.missing:
			if id < protos.tile_names.size() and TerrainTextures.lookup(protos.tile_names[id]) != null:
				_dirty_terrain[c] = true  # ready already
				_waiting_gfx.erase(c)
				break
	var done := 0
	for entry: Array in _terrain_jobs.values():
		if WorkerThreadPool.is_task_completed(entry[0]):
			done += 1
	FrameBudget.spent(&"terrain", Time.get_ticks_usec() - t0, done)


func _exit_tree() -> void:
	for entry in _terrain_jobs.values():
		WorkerThreadPool.wait_for_task_completion(entry[0])
	_terrain_jobs.clear()
	TerrainTextures.finish_all()
	ModelLods.finish_all()


## The entity under a point on the ground (tiles), preferring the smallest selection box,
## and buildings over the ore underneath them.
## The model an entity is drawn with if it is ready, else null (as with no model) while it is made
## on a worker thread: the entity's chunk is drawn again, with entities_changed, once it is.
func ready_mesh(proto: ProtoDB.EntityProto, rec: Rec, dir := 0) -> Mesh:
	if ModelLibrary.entity_ready(proto.name, proto.type, rec.extra, dir):
		return ModelLibrary.mesh_for_entity(proto.name, proto.type, rec.extra, dir)
	var cv: ChunkView = chunks.get(rec.chunk)
	if cv != null:
		cv.waiting_models = true
	return null


func pick(point: Vector2) -> Rec:
	var best: Rec = null
	var best_area := INF
	var center := chunk_of(point)
	var cell := Vector2i(floori(point.x / PICK_CELL), floori(point.y / PICK_CELL))
	var reach := _pick_reach()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cv: ChunkView = chunks.get(center + Vector2i(dx, dy))
			if cv == null:
				continue
			# A neighbour's entities reach the point only if it is near that chunk: indexing all nine
			# chunks (a busy one takes several ms) as new ones came under the mouse while walking
			# made 10-40 ms frames.
			if (dx != 0 or dy != 0) and not Rect2(Vector2(cv.coord * CHUNK), Vector2(CHUNK, CHUNK)).grow(reach).has_point(point):
				continue
			for entry: Array in _pick_grid(cv).get(cell, []):
				if (entry[1] as Rect2).has_point(point) and float(entry[2]) < best_area:
					best_area = entry[2]
					best = entry[0]
	return best


## Squares of the pick index, tiles.
const PICK_CELL := 2.0
## How high elevated rails run (rail_planner.gd's ELEVATED_Y), and a ramp's length.
const ELEVATED_HEIGHT := 3.0
const RAMP_LENGTH := 16.0


## The height of the rails at `point` for rolling stock there (H24: trains ran under elevated rails):
## up a ramp by how far along it, ELEVATED_HEIGHT on elevated rails, 0 on ground rails. Where both
## pass (a bridge over a ground line) `was` decides: the stock stays on the level it was on.
func rail_height(point: Vector2, was: float) -> float:
	var ground := false
	var elevated := false
	var center := chunk_of(point)
	var cell := Vector2i(floori(point.x / PICK_CELL), floori(point.y / PICK_CELL))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cv: ChunkView = chunks.get(center + Vector2i(dx, dy))
			if cv == null:
				continue
			for entry: Array in _pick_grid(cv).get(cell, []):
				if not (entry[1] as Rect2).has_point(point):
					continue
				var rec: Rec = entry[0]
				var proto: ProtoDB.EntityProto = protos.entity(rec.proto_id)
				if proto == null:
					continue
				if proto.type == "rail-ramp":
					var a := float(rec.dir) / 16.0 * TAU
					var uphill := Vector2(sin(a), -cos(a))
					return ELEVATED_HEIGHT * clampf((point - rec.pos).dot(uphill) / RAMP_LENGTH + 0.5, 0.0, 1.0)
				if proto.name.begins_with("elevated-"):
					elevated = true
				elif ModelLibrary.RAIL_TYPES.has(proto.type):
					ground = true
	if elevated and (not ground or was > ELEVATED_HEIGHT * 0.5):
		return ELEVATED_HEIGHT
	return 0.0


var _reach := [-1, 0.0]  # [entity prototypes counted, the reach]


## How far any entity's selection box reaches from its position (tiles), and a cell more, as an
## entity is kept in the chunk of its position.
func _pick_reach() -> float:
	if int(_reach[0]) != protos.entities.size():
		var most := 0.0
		for proto in protos.entities.values():
			if proto != null:
				most = maxf(most, maxf(maxf(absf(proto.box_min.x), absf(proto.box_min.y)), maxf(absf(proto.box_max.x), absf(proto.box_max.y))))
		_reach = [protos.entities.size(), most + PICK_CELL]
	return float(_reach[1])


## A chunk's entities by the PICK_CELL squares their selection boxes touch, with each box and the
## area pick() ranks it by (smallest first; ore and tile ghosts under the rest). Picking used to
## test every entity in nine chunks every frame (2 ms on a busy base); entities rarely change.
## Built a slice at a time, PICK_BUILD_USEC a frame across chunks: walking with the mouse over the
## view, each new busy chunk under it took 10-27 ms to index in one frame on the owner's save. A
## chunk part-way through picks from what is indexed so far.
func _pick_grid(cv: ChunkView) -> Dictionary:
	var gen := protos.entities.size()
	if cv.pick_grid.size() == 2 and int(cv.pick_grid[0]) == gen:
		return cv.pick_grid[1]
	if cv.pick_grid.size() != 4 or int(cv.pick_grid[0]) != gen:
		cv.pick_grid = [gen, {}, cv.entities.values(), 0]  # [generation, grid, records, next]
	var frame := Engine.get_process_frames()
	if frame != _pick_frame:
		_pick_frame = frame
		_pick_spent = 0
		_pick_allow = FrameBudget.grant(&"pick")
	var started := Time.get_ticks_usec()
	var grid: Dictionary = cv.pick_grid[1]
	var recs: Array = cv.pick_grid[2]
	var i := int(cv.pick_grid[3])
	var allow := _pick_allow if pick_build_usec == PICK_BUILD_USEC else pick_build_usec
	while i < recs.size():
		if (i & 15) == 0 and _pick_spent + Time.get_ticks_usec() - started > allow:
			break
		_index_pick(grid, recs[i])
		i += 1
	_pick_spent += Time.get_ticks_usec() - started
	FrameBudget.spent(&"pick", Time.get_ticks_usec() - started, recs.size() - i)
	if i >= recs.size():
		cv.pick_grid = [gen, grid]
	else:
		cv.pick_grid[3] = i
	return grid


var _pick_frame := -1
var _pick_spent := 0
var _pick_allow := PICK_BUILD_USEC
const PICK_BUILD_USEC := 1500
var pick_build_usec := PICK_BUILD_USEC  # tests lift it to compare a whole index


func _index_pick(grid: Dictionary, r: Rec) -> void:
	if r == null:
		return
	var proto: ProtoDB.EntityProto = protos.entity(r.proto_id)
	if proto == null:
		return
	# A ghost is picked by the box of what it will build (F6): Factorio's entity-ghost
	# prototype has a box of its own that doesn't fit it.
	var shape := proto
	if proto.type == "entity-ghost" and r.extra.has("gh"):
		var inner: ProtoDB.EntityProto = protos.entity(int(r.extra["gh"]))
		if inner != null:
			shape = inner
	var rect := selection_rect(shape, r.pos, r.dir)
	var area := rect.get_area()
	if proto.type == "resource":
		area += 1000.0
	elif proto.type == "tile-ghost":
		area += 2000.0  # under everything else, like the tile it stands for
	var entry := [r, rect, area]
	var lo := Vector2i(floori(rect.position.x / PICK_CELL), floori(rect.position.y / PICK_CELL))
	var hi := Vector2i(floori(rect.end.x / PICK_CELL), floori(rect.end.y / PICK_CELL))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			if not grid.has(c):
				grid[c] = []
			(grid[c] as Array).append(entry)


## The selection box of `proto` placed at `pos` facing `dir`, in tiles. Directions between the
## four main ones are rounded to the nearest of them.
static func selection_rect(proto: ProtoDB.EntityProto, pos: Vector2, dir: int) -> Rect2:
	var a := proto.box_min
	var b := proto.box_max
	match posmod(int(round(dir / 4.0)), 4):
		1:  # east: (x, y) -> (-y, x)
			a = Vector2(-proto.box_max.y, proto.box_min.x)
			b = Vector2(-proto.box_min.y, proto.box_max.x)
		2:  # south: (x, y) -> (-x, -y)
			a = -proto.box_max
			b = -proto.box_min
		3:  # west: (x, y) -> (y, -x)
			a = Vector2(proto.box_min.y, -proto.box_max.x)
			b = Vector2(proto.box_max.y, -proto.box_min.x)
	return Rect2(pos + a, b - a)


static func _array(v) -> Array:
	return v if v is Array else []
