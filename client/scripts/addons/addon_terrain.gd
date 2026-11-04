extends RefCounted
## api.terrain (1.2): hills under the flat Factorio world, drawn only. Factorio stays flat and
## nothing an add-on gives here changes the game; Zenith lifts what it draws (the ground, every
## model, belts and their items, ghosts, wires, icons, effects) by the height under it, and the
## mouse's ground point and the camera follow (scripts/world/ground_height.gd).
##
## One field for the whole client: the last add-on to set it wins, and it is cleared when that
## add-on is switched off or the game ends.

const GroundHeight := preload("res://scripts/world/ground_height.gd")

var _host
var _api


func _init(host, api) -> void:
	_host = host
	_api = api


## Sets the heights: `heights` an Image (FORMAT_RF, heights in tiles; other formats are converted,
## their red channel read), its first texel's corner at world `origin` (x east, z south), each
## texel `tiles_per_texel` tiles square. Between texel centres the height is bilinear, outside
## the image it is 0: fade the edges to 0 yourself. Main thread only.
func set_heights(heights: Image, origin: Vector2, tiles_per_texel: float) -> void:
	GroundHeight.set_field(heights, origin, tiles_per_texel)
	_host.set("_terrain_owner", _api.id)


## Back to flat ground (only if this add-on's field is the one shown).
func clear() -> void:
	if str(_host.get("_terrain_owner")) == _api.id:
		GroundHeight.clear()
		_host.set("_terrain_owner", "")


## Whether a field is shown now, and which square it covers (Rect2 in tiles; empty when off).
func is_on() -> bool:
	return GroundHeight.is_on()


func area() -> Rect2:
	return GroundHeight.area()


## The height drawn under a world point, in tiles (0 when off).
func height_at(x: float, z: float) -> float:
	return GroundHeight.at(x, z)


## The tiles of a drawn chunk (32 x 32, row by row from its north-west corner) as kinds:
## 0 land, 1 water, 2 empty space (a platform's void); an empty array when the chunk isn't
## loaded. A copy, cheap enough to take for every chunk on the main thread and read on a worker.
func chunk_kinds(chunk: Vector2i) -> PackedByteArray:
	var w = _host.game_node("world")
	if w == null:
		return PackedByteArray()
	var cv = w.chunks.get(chunk)
	if cv == null:
		return PackedByteArray()
	var ids: PackedInt32Array = cv.tile_ids
	if ids.size() != 32 * 32:
		return PackedByteArray()
	var kinds: PackedByteArray = w.protos.tile_is_water
	var out := PackedByteArray()
	out.resize(ids.size())
	var n := kinds.size()
	for i in ids.size():
		var id := ids[i]
		out[i] = kinds[id] if id >= 0 and id < n else 0
	return out


## The cliffs of a drawn chunk: [{position (Vector2, the middle of its 4 x 4 cell), orientation}].
## The orientation is Factorio's ("west-to-east", "none-to-north"...): the cliff runs from the
## middle of one edge of its cell to the middle of another ("none": the cell's middle, where a
## chain ends), with the high ground on its left.
func cliffs_in_chunk(chunk: Vector2i) -> Array:
	var out: Array = []
	var w = _host.game_node("world")
	if w == null or not w.chunks.has(chunk):
		return out
	var cv = w.chunks[chunk]
	for key in cv.entities:
		var r = cv.entities[key]
		var proto = w.protos.entity(r.proto_id)
		if proto == null or proto.type != "cliff":
			continue
		out.append({"position": r.pos, "orientation": str(r.extra.get("co", ""))})
	return out


## Types whose ground isn't levelled under them: the land itself and what grows or lies on it.
const NOT_BUILDINGS := ["cliff", "tree", "simple-entity", "resource", "fish", "corpse", "rail-remnants",
	"item-entity", "character", "character-corpse", "unit", "spider-unit", "segmented-unit", "segment",
	"asteroid", "asteroid-chunk", "plant", "entity-ghost", "tile-ghost", "deconstructible-tile-proxy"]

var _changed := {}  # Vector2i -> true: chunks whose buildings came or changed (take_changed_chunks)
var _watching := false


## The buildings in a loaded chunk, for levelling the ground under them: [[Vector2 centre, Vector2
## half size], ...] in tiles (turned east or west, a building's long side follows it). Empty when
## the chunk isn't loaded.
func buildings_in_chunk(chunk: Vector2i) -> Array:
	var out: Array = []
	var w = _host.game_node("world")
	if w == null or not w.chunks.has(chunk):
		return out
	var cv = w.chunks[chunk]
	for key in cv.entities:
		var r = cv.entities[key]
		var proto = w.protos.entity(r.proto_id)
		if proto == null or NOT_BUILDINGS.has(proto.type):
			continue
		var size: Vector2 = proto.size()
		var d := posmod(int(r.dir), 16)
		if d == 4 or d == 12:
			size = Vector2(size.y, size.x)
		out.append([Vector2(r.pos), size * 0.5])
	return out


## Chunks whose buildings came, went or changed since the last call (a chunk loaded late, a
## building placed or mined): an add-on reads them again. The first call starts the watch.
func take_changed_chunks() -> Array:
	var w = _host.game_node("world")
	if not _watching and w != null:
		_watching = true
		w.entities_changed.connect(func(c: Vector2i) -> void: _changed[c] = true)
	var out := _changed.keys()
	_changed = {}
	return out
