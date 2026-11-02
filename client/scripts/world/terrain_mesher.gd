extends RefCounted
## Builds one chunk's terrain mesh arrays, off the main thread (world.gd runs these on the
## WorkerThreadPool). Everything it reads is copied in by prepare() on the main thread, so a job
## never touches the scene, the prototype database or the texture cache while it runs: the
## chunk's tiles and its neighbours', a per-id table of tile graphics and colours, and the
## variant slots cached from the chunk's last build.
##
## Land tiles and banks go in one surface, water in another with its own material. With a
## Factorio install every tile carries its variant of Factorio's tile picture and which higher
## neighbours spread over its edges (see terrain_textures.gd and terrain.gdshader). A tile whose
## picture isn't loaded yet is drawn in its map colour, and its id is listed in `missing` so the
## world can load it and build the chunk again.

const TerrainTextures := preload("res://scripts/world/terrain_textures.gd")

const SIZE := 32
## Water is drawn below the land. Where land meets water (or a neighbour that isn't loaded yet)
## the land tile gets a bank face down past the water surface, so there's no gap to see through.
const WATER_Y := -0.2
const BANK_BOTTOM := -0.45
## With Factorio's textures the shore is a wet shelf just above the water instead of a bank: under
## the ragged edge of the ground, and reaching into the water tiles beside it. CUSTOM1.y tells
## the terrain shader which.
const SHELF_Y := WATER_Y + 0.01
const SHELF_UNDER_LAND := 1.0
const SHELF_OVER_WATER := 2.0
## What a tile is, for banks and shore foam. Unknown: its chunk isn't loaded. Void: empty space
## around a space platform, where nothing is drawn and the foundation's edge shows its depth.
const LAND := 0
const WATER := 1
const UNKNOWN := 2
const VOID := 3
const DECK_BOTTOM := -0.6
const PADDED := SIZE + 2  # a chunk's tiles plus a one-tile border from its neighbours
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## The 8 neighbours in the shaders' mask order: E W S N SE SW NE NW (Factorio's x east, y south).
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]
## The same neighbours as offsets in the padded arrays.
const OFFSETS: Array[int] = [1, -1, PADDED, -PADDED, PADDED + 1, PADDED - 1, 1 - PADDED, -1 - PADDED]

# --- input (set by prepare) -------------------------------------------------------------------
var coord := Vector2i.ZERO
var tile_ids := PackedInt32Array()
## The 3x3 chunks' tiles, row by row from the north-west (index 4 is this chunk); empty: not loaded.
var around: Array[PackedInt32Array] = []
var colors := PackedColorArray()  # per tile id
var kind_of := PackedByteArray()  # per tile id: 0 land, 1 water, 2 void (ProtoDB.tile_is_water)
var gfx_of: Array = []  # per tile id: TerrainTextures.TileGfx, or null while its picture isn't loaded
var textured := false
var slots := PackedInt32Array()  # cached variant slots (x + 64 * y), empty: work them out
# --- output -----------------------------------------------------------------------------------
var land: TerrainSurface
var water: TerrainSurface
## Ids drawn without their picture because it isn't loaded (yet).
var missing := PackedInt32Array()
var usec := 0  # how long run() took

var _plain := {}  # id -> TileGfx standing in for one whose picture isn't loaded


## Builds the arrays. Runs on a worker thread.
func run() -> void:
	var t0 := Time.get_ticks_usec()
	land = TerrainSurface.new()
	water = TerrainSurface.new()
	if tile_ids.size() == SIZE * SIZE:
		_mesh()
	usec = Time.get_ticks_usec() - t0


func _mesh() -> void:
	var ids := _padded_ids()
	var kinds := _tile_kinds(ids)
	# Per padded tile, for the neighbour checks: the layer it spreads over lower neighbours (-1 if
	# it doesn't) and its draw priority.
	var spreads := PackedInt32Array()
	var prio := PackedInt32Array()
	spreads.resize(ids.size())
	prio.resize(ids.size())
	for i in ids.size():
		var gi: TerrainTextures.TileGfx = _gfx(ids[i]) if ids[i] >= 0 else null
		spreads[i] = gi.layer if gi != null and gi.spills and not gi.water else -1
		prio[i] = gi.priority if gi != null else -1
	if slots.size() != SIZE * SIZE:
		slots = PackedInt32Array()
		slots.resize(SIZE * SIZE)
		var uniform := _uniform_blocks()
		for i in SIZE * SIZE:
			var gs := _gfx(tile_ids[i])
			var tx := i % SIZE
			var ty := i / SIZE
			var s := gs.slot(coord.x * SIZE + tx, coord.y * SIZE + ty, tx, ty, uniform) if gs.layer >= 0 else Vector2i.ZERO
			slots[i] = s.x + 64 * s.y
	var slot := TerrainTextures.slot_uv()
	var shore := PackedFloat32Array()
	var x0 := coord.x * SIZE
	var z0 := coord.y * SIZE
	for ty in SIZE:
		for tx in SIZE:
			var id := tile_ids[ty * SIZE + tx]
			var g := _gfx(id)
			var pi := (ty + 1) * PADDED + tx + 1
			if kinds[pi] == VOID:
				continue
			var color := _color(id)
			var x := float(x0 + tx)
			var z := float(z0 + ty)
			var uv := Rect2()
			if g.layer >= 0:
				var s := slots[ty * SIZE + tx]
				uv = Rect2(Vector2(s % 64, s / 64) * slot, slot)
				color = Color.WHITE
			if kinds[pi] == WATER:
				if shore.is_empty():
					shore = _shore_corners(kinds)
				var c := ty * (SIZE + 1) + tx
				var other := _other_water(ids, pi, g.layer)
				var shares := Vector4.ZERO
				if other >= 0:
					shares = Vector4(_share(ids, ty * PADDED + tx, other), _share(ids, ty * PADDED + tx + 1, other),
						_share(ids, (ty + 1) * PADDED + tx + 1, other), _share(ids, (ty + 1) * PADDED + tx, other))
				var wc := _color(id)
				water.quad(Vector3(x, WATER_Y, z), Vector3(x + 1.0, WATER_Y, z), Vector3(x + 1.0, WATER_Y, z + 1.0), Vector3(x, WATER_Y, z + 1.0), Vector3.UP,
					Color(wc, shore[c]), Color(wc, shore[c + 1]), Color(wc, shore[c + SIZE + 2]), Color(wc, shore[c + SIZE + 1]),
					uv, Color(g.layer, other, 0.0, 0.0), Color(), shares)
				var land_bits := _mask(kinds, pi, LAND) if textured else 0
				if land_bits != 0:
					# The wet shelf of the bank reaches into the water with a ragged edge.
					var lid := _land_neighbour(ids, pi)
					var lg := _gfx(lid)
					var lc := Color.WHITE if lg.layer >= 0 else _color(lid)
					land.quad(Vector3(x, SHELF_Y, z), Vector3(x + 1.0, SHELF_Y, z), Vector3(x + 1.0, SHELF_Y, z + 1.0), Vector3(x, SHELF_Y, z + 1.0), Vector3.UP,
						lc, lc, lc, lc, Rect2(), Color(lg.layer, -1.0, -1.0, 0.0), Color(land_bits, SHELF_OVER_WATER, 0.0, 0.0))
				continue
			if g.layer < 0:
				# A little per-tile variation on top of the shader's noise, so tiles stay readable.
				var shade := 0.94 + 0.06 * float(hash(Vector2i(x0 + tx, z0 + ty)) % 100) / 100.0
				color = Color(color.r * shade, color.g * shade, color.b * shade)
			var spread := _spreading(spreads, prio, pi, g.layer)
			var wet := _mask(kinds, pi, WATER) if textured else 0
			land.quad(Vector3(x, 0.0, z), Vector3(x + 1.0, 0.0, z), Vector3(x + 1.0, 0.0, z + 1.0), Vector3(x, 0.0, z + 1.0), Vector3.UP,
				color, color, color, color, uv, spread, Color(wet, 0.0, 0.0, 0.0))
			var plain := Color(g.layer, -1.0, -1.0, 0.0)
			if wet != 0:
				# The ground's edge is cut back raggedly along the water (terrain.gdshader); this
				# wet shelf just above the water shows underneath.
				land.quad(Vector3(x, SHELF_Y, z), Vector3(x + 1.0, SHELF_Y, z), Vector3(x + 1.0, SHELF_Y, z + 1.0), Vector3(x, SHELF_Y, z + 1.0), Vector3.UP,
					color, color, color, color, uv, plain, Color(wet, SHELF_UNDER_LAND, 0.0, 0.0))
				# And water under it all, where the coast bites into the tile.
				var wid := _water_neighbour(ids, pi)
				var wc := Color(_color(wid), 1.0)
				water.quad(Vector3(x, WATER_Y, z), Vector3(x + 1.0, WATER_Y, z), Vector3(x + 1.0, WATER_Y, z + 1.0), Vector3(x, WATER_Y, z + 1.0), Vector3.UP,
					wc, wc, wc, wc, Rect2(), Color(_gfx(wid).layer, -1.0, 0.0, 0.0))
			# Banks: the tile's own colour, darkening like wet soil towards the water. With
			# textures the shelf takes their place along the water.
			if kinds[pi + 1] == LAND and kinds[pi - 1] == LAND and kinds[pi + PADDED] == LAND and kinds[pi - PADDED] == LAND:
				continue
			var bank_top := color.darkened(0.25)
			var bank_bottom := color.darkened(0.6)
			for side in SIDES:
				var k := kinds[pi + side.y * PADDED + side.x]
				if k == LAND or (k == WATER and textured):
					continue
				var out := Vector3(side.x, 0.0, side.y)
				var edge := Vector3(x + 0.5, 0.0, z + 0.5) + out * 0.5
				# Left to right as seen from outside the tile, keeping the faces clockwise.
				var right := (-out).cross(Vector3.UP) * 0.5
				var down := Vector3(0.0, DECK_BOTTOM if k == VOID else BANK_BOTTOM, 0.0)
				land.quad(edge - right, edge + right, edge + right + down, edge - right + down, out,
					bank_top, bank_top, bank_bottom, bank_bottom, uv, plain, Color())


## The graphics of tile `id`, or a plain stand-in (map colour, no transitions) while its picture
## isn't loaded.
func _gfx(id: int) -> TerrainTextures.TileGfx:
	var g: TerrainTextures.TileGfx = gfx_of[id] if id >= 0 and id < gfx_of.size() else null
	if g != null:
		return g
	g = _plain.get(id)
	if g == null:
		g = TerrainTextures.TileGfx.new()
		g.water = id >= 0 and id < kind_of.size() and kind_of[id] == 1
		_plain[id] = g
		if id >= 0:
			missing.append(id)
	return g


func _color(id: int) -> Color:
	return colors[id] if id >= 0 and id < colors.size() else Color(0.35, 0.35, 0.3)


## Tile ids with a one-tile border taken from the neighbouring chunks, row by row (PADDED x
## PADDED), so banks, foam and transitions carry on across chunk edges. -1: not loaded.
func _padded_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	ids.resize(PADDED * PADDED)
	for py in PADDED:
		var ty := py - 1
		var cy := 0 if ty < 0 else (2 if ty >= SIZE else 1)
		var ly := posmod(ty, SIZE)
		for px in PADDED:
			var tx := px - 1
			var cx := 0 if tx < 0 else (2 if tx >= SIZE else 1)
			var src: PackedInt32Array = around[cy * 3 + cx]
			ids[py * PADDED + px] = src[ly * SIZE + posmod(tx, SIZE)] if src.size() == SIZE * SIZE else -1
	return ids


## Each padded tile's kind: land, water, void or unknown.
func _tile_kinds(ids: PackedInt32Array) -> PackedByteArray:
	var kinds := PackedByteArray()
	kinds.resize(PADDED * PADDED)
	for i in ids.size():
		var id := ids[i]
		if id < 0:
			kinds[i] = UNKNOWN
		elif id < kind_of.size() and kind_of[id] == 1:
			kinds[i] = WATER
		elif id < kind_of.size() and kind_of[id] == 2:
			kinds[i] = VOID
		else:
			kinds[i] = LAND
	return kinds


## For each variant size, which aligned blocks of this chunk are all one tile, block by block
## row by row: {2: PackedByteArray, 4: ..., 8: ...}. Blocks never cross a chunk edge.
func _uniform_blocks() -> Dictionary:
	var out := {}
	for s: int in [2, 4, 8]:
		var n := SIZE / s
		var flags := PackedByteArray()
		flags.resize(n * n)
		for by in n:
			for bx in n:
				var first := tile_ids[by * s * SIZE + bx * s]
				var same := 1
				for y in range(by * s, by * s + s):
					for x in range(bx * s, bx * s + s):
						if tile_ids[y * SIZE + x] != first:
							same = 0
							break
					if same == 0:
						break
				flags[by * n + bx] = same
		out[s] = flags
	return out


## Which higher natural tiles spread over tile `pi`'s edges, for the terrain shader: (own layer,
## lower spreading layer, upper spreading layer, mask of the lower + 256 * mask of the upper).
## Factorio draws every higher neighbour's transition in layer order; two cover nearly all ground.
## `spreads` and `prio` are per padded tile (see run).
static func _spreading(spreads: PackedInt32Array, prio: PackedInt32Array, pi: int, own: int) -> Color:
	var own_prio := prio[pi]
	var any := false
	for o in OFFSETS:
		var l := spreads[pi + o]
		if l >= 0 and l != own and prio[pi + o] > own_prio:
			any = true
			break
	if not any:
		return Color(own, -1.0, -1.0, 0.0)
	var layers := PackedInt32Array()
	var masks := PackedInt32Array()
	var prios := PackedInt32Array()
	for bit in 8:
		var n := pi + OFFSETS[bit]
		var l := spreads[n]
		if l < 0 or l == own or prio[n] <= own_prio:
			continue
		var k := layers.find(l)
		if k < 0:
			layers.append(l)
			masks.append(1 << bit)
			prios.append(prio[n])
		else:
			masks[k] |= 1 << bit
	match layers.size():
		0:
			return Color(own, -1.0, -1.0, 0.0)
		1:
			return Color(own, layers[0], -1.0, masks[0])
	# The two highest, lower first.
	var hi := 0
	for k in layers.size():
		if prios[k] > prios[hi]:
			hi = k
	var lo := 0 if hi != 0 else 1
	for k in layers.size():
		if k != hi and prios[k] > prios[lo]:
			lo = k
	return Color(own, layers[lo], layers[hi], masks[lo] + 256 * masks[hi])


## Bits of the 8 neighbours of `pi` that are of `kind`.
static func _mask(kinds: PackedByteArray, pi: int, kind: int) -> int:
	var bits := 0
	for bit in 8:
		if kinds[pi + OFFSETS[bit]] == kind:
			bits |= 1 << bit
	return bits


## The layer of a different water type next to water tile `pi` (deep water by shallow), or -1.
func _other_water(ids: PackedInt32Array, pi: int, layer: int) -> int:
	if layer < 0:
		return -1
	for d in NEIGHBOURS:
		var n := ids[pi + d.y * PADDED + d.x]
		if n >= 0:
			var ng := _gfx(n)
			if ng.water and ng.layer >= 0 and ng.layer != layer:
				return ng.layer
	return -1


## The land tile (id) next to water tile `pi` whose ground its shelf shows: a side neighbour
## first (NEIGHBOURS lists them first), and one with Factorio's picture over one without.
func _land_neighbour(ids: PackedInt32Array, pi: int) -> int:
	var best := -1
	for d in NEIGHBOURS:
		var n := ids[pi + d.y * PADDED + d.x]
		if n >= 0:
			var ng := _gfx(n)
			if not ng.water and (best < 0 or (_gfx(best).layer < 0 and ng.layer >= 0)):
				best = n
	return best


## A water tile (id) next to land tile `pi`, side neighbours first.
func _water_neighbour(ids: PackedInt32Array, pi: int) -> int:
	for d in NEIGHBOURS:
		var n := ids[pi + d.y * PADDED + d.x]
		if n >= 0 and _gfx(n).water:
			return n
	return -1


## Share of the water tiles around a tile corner (the 2x2 padded tiles from `pi`) that are of
## water layer `other`; the water shader blends the two types where it crosses one half.
func _share(ids: PackedInt32Array, pi: int, other: int) -> float:
	var wet := 0
	var hits := 0
	for k in [pi, pi + 1, pi + PADDED, pi + PADDED + 1]:
		var n := ids[k]
		if n < 0:
			continue
		var ng := _gfx(n)
		if ng.water:
			wet += 1
			if ng.layer == other:
				hits += 1
	return float(hits) / wet if wet > 0 else 0.0


## 1.0 at tile corners (SIZE + 1 squared, row by row) that touch a land tile, else 0.0. The
## water shader draws foam where this, interpolated across each tile, is high.
static func _shore_corners(kinds: PackedByteArray) -> PackedFloat32Array:
	var shore := PackedFloat32Array()
	shore.resize((SIZE + 1) * (SIZE + 1))
	for cy in SIZE + 1:
		for cx in SIZE + 1:
			# The corner's four tiles in padded coordinates are (cx, cy) to (cx + 1, cy + 1).
			var k := cy * PADDED + cx
			if kinds[k] == LAND or kinds[k + 1] == LAND or kinds[k + PADDED] == LAND or kinds[k + PADDED + 1] == LAND:
				shore[cy * (SIZE + 1) + cx] = 1.0
	return shore


## Mesh arrays for one terrain surface, filled a quad at a time. UV is the tile's slot in its
## texture layer; CUSTOM0 and CUSTOM1 carry per-tile data for the shaders.
class TerrainSurface:
	const FORMAT := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var origins := PackedVector2Array()  # UV2: the tile's corner, so shaders know which tile a pixel is in
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var indices := PackedInt32Array()

	## Corners a, b, c, d go clockwise as seen from the front (Godot's front-face winding).
	## `uv` maps a to its top-left corner and c to its bottom-right. `shares` replaces c0's third
	## value per corner (the water blend).
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, ca: Color, cb: Color, cc: Color, cd: Color,
			uv := Rect2(), c0 := Color(-1, -1, -1, 0), c1 := Color(), shares := Vector4.ZERO) -> void:
		# One append at a time: building literal arrays to append is several times slower.
		var v := verts.size()
		verts.append(a)
		verts.append(b)
		verts.append(c)
		verts.append(d)
		colors.append(ca)
		colors.append(cb)
		colors.append(cc)
		colors.append(cd)
		uvs.append(uv.position)
		uvs.append(Vector2(uv.end.x, uv.position.y))
		uvs.append(uv.end)
		uvs.append(Vector2(uv.position.x, uv.end.y))
		var o := Vector2(a.x, a.z)
		var plain := shares == Vector4.ZERO
		for k in 4:
			normals.append(normal)
			origins.append(o)
			custom0.append(c0.r)
			custom0.append(c0.g)
			custom0.append(c0.b if plain else shares[k])
			custom0.append(c0.a)
			custom1.append(c1.r)
			custom1.append(c1.g)
			custom1.append(c1.b)
			custom1.append(c1.a)
		indices.append(v)
		indices.append(v + 1)
		indices.append(v + 2)
		indices.append(v)
		indices.append(v + 2)
		indices.append(v + 3)

	func has_faces() -> bool:
		return not indices.is_empty()

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = verts
		a[Mesh.ARRAY_NORMAL] = normals
		a[Mesh.ARRAY_COLOR] = colors
		a[Mesh.ARRAY_TEX_UV] = uvs
		a[Mesh.ARRAY_TEX_UV2] = origins
		a[Mesh.ARRAY_CUSTOM0] = custom0
		a[Mesh.ARRAY_CUSTOM1] = custom1
		a[Mesh.ARRAY_INDEX] = indices
		return a
