extends RefCounted
## The lanes of the belts round the focus, so items on belts (belt_items.gd) travel along their
## lane between two updates instead of in a straight line: round a curve's arc, through a splitter,
## out of sight between an underground's ends, onto the near lane of a belt they are side-loaded
## onto, and never across empty ground (owner: items floated off belts on a dense base, cutting
## across curves, over splitters and undergrounds, and sat over buildings).
##
## Measured in Factorio 2.1.23 (get_line_item_position along every line): a lane's centre is
## 0.234 either side of its belt's; a curve's lanes are quarter circles about the curve's inner
## corner, radius 0.5 + 0.234 outside and 0.5 - 0.234 inside; a splitter's input lanes run 0.7
## tiles in from its back edge and items carry on from there on the output lane of either half,
## jumping across; an underground entrance's lanes go under at its middle and come up at its exit's
## middle; an item side-loaded onto a belt jumps onto the lane on its side where it crosses it.
##
## Everything here runs on belt_items.gd's worker thread, on records the main thread hands over.

const WorldMirror := preload("res://scripts/world/world.gd")

const LANE := 0.234
const SPLIT_AT := 0.7
## How far in front of an underground entrance its exit is looked for (a turbo underground spans 10).
const UG_REACH := 12
## Items carried on a lane: points this far apart (tiles) along the way, at most MAX_POINTS. A chord
## of 0.15 on the outer lane of a curve is 0.004 tiles inside its arc.
const SPACING := 0.15
const MAX_POINTS := 64
## A point counts as on a lane within this (positions come in 1/256 tile).
const ON_LANE := 0.02
## The new position is matched to a lane within this: the mod carries an item read a few ticks
## early on in a straight line to the update's tick, which leaves a curve by up to a few tenths.
const MATCH := 0.35
## How many straight belts a run is followed along at most (each belt remembers where its run ends,
## for the items on it to glide there without another look: belt_items.gd).
const RUN_AHEAD := 256
## A side-loaded item's step across onto its new lane counts as this much of its way (Factorio
## moves it the 0.27 to 0.73 tiles there in one tick, as fast as a jump).
const SIDE_STEP := 0.1

enum { STRAIGHT, LEFT, RIGHT, UG_IN, UG_OUT, SPLITTER, OTHER }
## What a route() found.
enum { NONE, LINE, PATH, SNAP }

## Unit vectors by direction (0 north, 1 east, 2 south, 3 west): ahead, and to the right of it.
const AHEAD := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
const RIGHT_OF := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]
## Prototype types and what they are here (a transport belt is straight or a curve by its shape).
const TYPES := {"transport-belt": STRAIGHT, "underground-belt": UG_IN, "splitter": SPLITTER,
	"loader": OTHER, "loader-1x1": OTHER, "linked-belt": OTHER, "lane-splitter": OTHER}


## Where along its path's points (Graph.points) an item is at t (0 to 1), as belt_path.gdshaderinc
## works it out: x, y, z from its place, w 1 where it shows.
static func path_at(path: PackedFloat32Array, t: float) -> Vector4:
	var pieces := path.size() / 4 - 1
	var f := clampf(t, 0.0, 1.0) * pieces
	var i := mini(int(f), pieces - 1)
	var u := f - i
	var a := i * 4
	return Vector4(lerpf(path[a], path[a + 4], u), lerpf(path[a + 1], path[a + 5], u),
		lerpf(path[a + 2], path[a + 6], u), lerpf(path[a + 3], path[a + 7], u))


class Belt:
	var kind := 0
	var d := 0  # the way items leave it, 0-3
	var c := Vector2.ZERO  # its centre
	var proto := 0
	var exit: Belt = null  # an entrance's exit, looked for in Graph.generation `paired`
	var paired := -1
	## Its lanes' pieces by lane * 4 + part (Graph.piece), made when first needed; an entrance's
	## again in each generation (its exit may have changed).
	var pieces: Array = []
	var built := -1
	## A straight belt: where the run of straight belts it is in ends (Graph.run_on), worked out in
	## generation `run_gen`.
	var run_end := 0.0
	var run_gen := -1


## Where a route ends up: the lane's pieces walked (each [belt, lane, part, from s, to s, step]),
## where the item is now, and which way it got there.
class Route:
	var kind := NONE
	var end := Vector2.ZERO
	var segs: Array = []  # [belt, lane, part, s0, s1, step] in order; step: a side-load's step onto it
	var length := 0.0
	var belt: Belt = null  # where `end` is
	var lane := 0
	var part := 0
	var s := 0.0
	## Where it ends up on a straight piece of lane: the lane's direction (0-3, -1 not on one) and
	## where it runs straight on to (run_on()), as a distance along that direction from the map's
	## origin.
	var run_d := -1
	var run_end := 0.0


# A piece of lane, as a PackedFloat64Array: [arc (0 line, 1 arc), start x, y, direction x, y,
# length, then for an arc: corner x, y, radius, start angle, turn (1 right, -1 left)].
const P_ARC := 0
const P_LEN := 5


class Graph:
	var tiles := {}  # Vector2i -> Belt (a splitter on both of its tiles)
	var chunk_tiles := {}  # Vector2i chunk -> Array of its belts' tiles
	var trusted := {}  # Vector2i chunk -> true when its whole snapshot was indexed
	var signs := {}  # Vector2i chunk -> what its belts were when indexed (signature())
	## Bumped whenever the belts change: routes worked out before may no longer hold.
	var generation := 0
	## Prototype id -> TYPES value, from the main thread.
	var kinds := {}
	## route()'s answer, overwritten by the next call.
	var last := Route.new()
	## Routes found along a run of straight belts, and walked along the lanes by the kind of belt
	## they started on (TYPES' values): what a busy base costs (probes).
	var runs := 0
	var walks := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])

	## A chunk's entity records (WorldMirror.Rec) replace what was indexed for it; `whole` when the
	## chunk's snapshot is complete, so a lane missing there is really missing.
	func index(c: Vector2i, recs: Array, whole: bool) -> void:
		# A chunk is drawn again for many reasons (a machine built, a model loaded); its belts seldom
		# changed, and then nothing changes here (items keep the runs they know).
		var sign := signature(recs)
		if signs.get(c) == sign:
			if whole:
				trusted[c] = true
			return
		drop(c)
		signs[c] = sign
		var list: Array = []
		for r: WorldMirror.Rec in recs:
			var k: int = kinds.get(r.proto_id, -1)
			if k < 0:
				continue
			var b := Belt.new()
			b.kind = k
			b.d = (r.dir >> 2) & 3
			b.c = r.pos
			b.proto = r.proto_id
			if k == STRAIGHT:
				var s := str(r.extra.get("s", "s"))
				b.kind = LEFT if s == "l" else (RIGHT if s == "r" else STRAIGHT)
			elif k == UG_IN and str(r.extra.get("u", "i")) == "o":
				b.kind = UG_OUT
			if b.kind == SPLITTER:
				var side: Vector2 = RIGHT_OF[b.d] * 0.5
				for p in [b.c - side, b.c + side]:
					var t := Vector2i(floori(p.x), floori(p.y))
					tiles[t] = b
					list.append(t)
			else:
				var t := Vector2i(floori(b.c.x), floori(b.c.y))
				tiles[t] = b
				list.append(t)
		chunk_tiles[c] = list
		if whole:
			trusted[c] = true
		generation += 1

	func drop(c: Vector2i) -> void:
		var list: Array = chunk_tiles.get(c, [])
		for t in list:
			var b: Belt = tiles.get(t)
			if b != null and WorldMirror.chunk_of(b.c) == c:
				tiles.erase(t)
		chunk_tiles.erase(c)
		trusted.erase(c)
		signs.erase(c)
		generation += 1

	## The belts among a chunk's records, as [how many, a sum of each one's place, way, prototype and
	## shape]: the same whatever order the records come in.
	func signature(recs: Array) -> Vector2i:
		var n := 0
		var sum := 0
		for r: WorldMirror.Rec in recs:
			if not kinds.has(r.proto_id):
				continue
			n += 1
			sum += ((r.fixed.x * 73856093) ^ (r.fixed.y * 19349663) ^ ((r.dir * 4099 + r.proto_id) * 83492791)
				^ hash(r.extra.get("s", r.extra.get("u", "")))) & 0x7fffffff
		return Vector2i(n, sum & 0x7fffffff)

	static func piece_point(pc: PackedFloat64Array, s: float) -> Vector2:
		if pc[P_ARC] == 0.0:
			return Vector2(pc[1] + pc[3] * s, pc[2] + pc[4] * s)
		var a := pc[9] + pc[10] * s / pc[8]
		return Vector2(pc[6] + cos(a) * pc[8], pc[7] + sin(a) * pc[8])


	## The nearest point of a piece to q at s0 or further along: (s, distance).
	static func piece_project(pc: PackedFloat64Array, q: Vector2, s0 := 0.0) -> Vector2:
		var s: float
		if pc[P_ARC] == 0.0:
			s = clampf((q.x - pc[1]) * pc[3] + (q.y - pc[2]) * pc[4], s0, pc[P_LEN])
		else:
			var rel := wrapf(pc[10] * (atan2(q.y - pc[7], q.x - pc[6]) - pc[9]), -PI, PI)
			s = clampf(rel * pc[8], s0, pc[P_LEN])
		return Vector2(s, q.distance_to(piece_point(pc, s)))

	func knows(p: Vector2) -> bool:
		return trusted.has(Vector2i(floori(p.x / 32.0), floori(p.y / 32.0)))

	func belt_at(p: Vector2) -> Belt:
		return tiles.get(Vector2i(floori(p.x), floori(p.y)))

	## Whether b is still indexed (an item's hint can outlive its belt).
	func alive(b: Belt) -> bool:
		return b != null and tiles.get(Vector2i(floori(b.c.x), floori(b.c.y))) == b

	# --- A belt's lanes, as pieces: (belt, lane, part), each a line or (curves) an arc. -------------

	## How many parts a belt's lane has: an entrance 2 (the second under the ground, when it has an
	## exit), a splitter 4 (input and output of each half: part = half * 2 + output).
	func parts(b: Belt) -> int:
		match b.kind:
			UG_IN:
				return 2 if exit_of(b) != null else 1
			SPLITTER:
				return 4
			OTHER:
				return 0
		return 1

	func exit_of(b: Belt) -> Belt:
		if b.paired == generation:
			return b.exit
		b.paired = generation
		b.exit = null
		var f: Vector2 = AHEAD[b.d]
		for i in range(1, UG_REACH + 1):
			var o: Belt = belt_at(b.c + f * i)
			if o != null and o.kind == UG_OUT and o.d == b.d and o.proto == b.proto:
				b.exit = o
				break
		return b.exit

	## The way items come into a curve.
	static func curve_in(b: Belt) -> int:
		return (b.d + 3) % 4 if b.kind == RIGHT else (b.d + 1) % 4

	## Whether items show there (not under the ground between an underground's ends).
	static func shows(b: Belt, part: int) -> bool:
		return not (b.kind == UG_IN and part == 1)

	func piece(b: Belt, lane: int, part: int) -> PackedFloat64Array:
		if b.kind == UG_IN and b.built != generation:
			b.pieces = []
			b.built = generation
		if b.pieces.is_empty():
			b.pieces.resize(8)
		var k := lane * 4 + part
		var pc = b.pieces[k]
		if pc == null:
			pc = _make(b, lane, part)
			b.pieces[k] = pc
		return pc

	func _make(b: Belt, lane: int, part: int) -> PackedFloat64Array:
		var f: Vector2 = AHEAD[b.d]
		var side: Vector2 = RIGHT_OF[b.d] * (LANE if lane == 1 else -LANE)
		var start := b.c - f * 0.5 + side
		var length := 1.0
		match b.kind:
			LEFT, RIGHT:
				var t := curve_in(b)
				var corner: Vector2 = b.c - AHEAD[t] * 0.5 + AHEAD[b.d] * 0.5
				var v: Vector2 = b.c - AHEAD[t] * 0.5 + RIGHT_OF[t] * (LANE if lane == 1 else -LANE) - corner
				var r := v.length()
				return PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 0.0, r * PI * 0.5, corner.x, corner.y, r, v.angle(),
					1.0 if b.kind == RIGHT else -1.0])
			UG_IN:
				if part == 0:
					length = 0.5
				else:
					var e := exit_of(b)
					start = b.c + side
					length = (e.c - b.c).dot(f) if e != null else 0.0
			UG_OUT:
				start = b.c + side
				length = 0.5
			SPLITTER:
				var half: Vector2 = RIGHT_OF[b.d] * (0.5 if part >= 2 else -0.5)
				if part % 2 == 0:
					start += half
					length = SPLIT_AT
				else:
					start += half + f * SPLIT_AT
					length = 1.0 - SPLIT_AT
			OTHER:
				length = 0.0
		return PackedFloat64Array([0.0, start.x, start.y, f.x, f.y, length])

	func length(b: Belt, lane: int, part: int) -> float:
		return piece(b, lane, part)[P_LEN]

	func point(b: Belt, lane: int, part: int, s: float) -> Vector2:
		return piece_point(piece(b, lane, part), s)

	## The lane piece nearest p on belt b: [lane, part, s, distance], or [] if none.
	func nearest(b: Belt, p: Vector2) -> Array:
		var best: Array = []
		for part in parts(b):
			for lane in 2:
				var pr := piece_project(piece(b, lane, part), p)
				if best.is_empty() or pr.y < float(best[3]):
					best = [lane, part, pr.x, pr.y]
		return best

	## Where items go at the end of a piece: [[belt, lane, part, s, step], ...] (step: a side-load's
	## step across onto the lane; a splitter's other half is a jump, of no length).
	func next(b: Belt, lane: int, part: int) -> Array:
		match b.kind:
			UG_IN:
				if part == 0:
					return [[b, lane, 1, 0.0, 0.0]] if exit_of(b) != null else []
				return [[exit_of(b), lane, 0, 0.0, 0.0]]
			SPLITTER:
				if part % 2 == 0:
					var h := part / 2
					return [[b, lane, h * 2 + 1, 0.0, 0.0], [b, lane, (1 - h) * 2 + 1, 0.0, 0.0]]
		var pc := piece(b, lane, part)
		return enter(piece_point(pc, pc[P_LEN]), b.d, lane)

	## Items reaching edge point e, going way t on `lane`, onto the belt over the edge.
	func enter(e: Vector2, t: int, lane: int) -> Array:
		var f: Vector2 = AHEAD[t]
		var o: Belt = belt_at(e + f * 0.5)
		if o == null:
			return []
		match o.kind:
			STRAIGHT, UG_IN, UG_OUT:
				if o.d == t:
					return [[o, lane, 0, 0.0, 0.0]] if o.kind != UG_OUT else []
				if o.d == (t + 2) % 4:
					return []
				# Side-loaded: onto the lane on the side they come from, where they cross it (onto an
				# underground's end, its open half: an entrance's back, an exit's front).
				var near := 0 if RIGHT_OF[o.d] == f else 1
				var s: float = (e - (o.c - AHEAD[o.d] * 0.5)).dot(AHEAD[o.d])
				if o.kind == UG_IN and s > 0.5 or o.kind == UG_OUT and s < 0.5:
					return []
				return [[o, near, 0, clampf(s - (0.5 if o.kind == UG_OUT else 0.0), 0.0, 1.0), SIDE_STEP]]
			LEFT, RIGHT:
				return [[o, lane, 0, 0.0, 0.0]] if curve_in(o) == t else []
			SPLITTER:
				if o.d != t:
					return []
				var h := 1 if (e - o.c).dot(RIGHT_OF[o.d]) > 0.0 else 0
				return [[o, lane, h * 2, 0.0, 0.0]]
		return []

	# --- Routes. --------------------------------------------------------------------------------

	## Where p is on a lane: [belt, lane, part, s, distance], or [] when it isn't on one. `hint` is
	## where the item was last: it is taken when p is on it (under the ground there is no belt at
	## p's tile), or when the belt at p's tile doesn't fit either.
	func locate(p: Vector2, hint: Belt) -> Array:
		var h: Array = []
		if alive(hint):
			h = nearest(hint, p)
			if not h.is_empty() and float(h[3]) < ON_LANE:
				return [hint, h[0], h[1], h[2], h[3]]
		var b := belt_at(p)
		if b != null and b != hint:
			var n := nearest(b, p)
			if not n.is_empty() and float(n[3]) < MATCH:
				return [b, n[0], n[1], n[2], n[3]]
		if not h.is_empty() and float(h[3]) < MATCH:
			return [hint, h[0], h[1], h[2], h[3]]
		return []

	## How an item drawn at p (last on `hint`) gets to q, at most `limit` tiles along its lanes in
	## sight. The answer is `last`: NONE (belts not known there), LINE (a straight glide to `end`),
	## PATH (along `segs`) or SNAP (put at `end`, not reachable from p).
	func route(p: Vector2, q: Vector2, hint: Belt, limit: float) -> Route:
		var out := last
		out.kind = NONE
		out.end = q
		out.belt = null
		out.length = 0.0
		out.run_d = -1
		# Most items ride a straight belt and stay on it, or on the straight belts in front of it.
		# (Not an item under the ground passing beneath that belt: its hint is the entrance.)
		var b: Belt = tiles.get(Vector2i(floori(p.x), floori(p.y)))
		if b != null and b.kind == STRAIGHT and (hint == null or hint.kind != UG_IN) and _straight_run(b, p, q, out):
			runs += 1
			return out
		# Further along the belt it is on: round a curve, under the ground at an entrance, through a
		# splitter's halves.
		if hint != null and hint.kind != STRAIGHT and hint.kind != OTHER and alive(hint) and _within(hint, p, q, out):
			runs += 1
			return out
		if not knows(p) or not knows(q):
			return out
		var start := locate(p, hint)
		if start.is_empty():
			# p is on no lane (put there before its belts were known): onto q's lane, if it has one.
			var at := locate(q, null)
			if not at.is_empty():
				out.kind = SNAP
				out.end = point(at[0], at[1], at[2], at[3])
			return out
		out.segs = []
		walks[(start[0] as Belt).kind] += 1
		return _walk(start, p, q, limit, out)

	## Where an item drawn at p (last on `hint`) is `dist` further along its lane (or at the lane's
	## end): LINE or PATH as route() gives, NONE when p isn't on a lane or the way forks (a
	## splitter: which half it took isn't known).
	func advance(p: Vector2, hint: Belt, dist: float) -> Route:
		var out := last
		out.kind = NONE
		out.end = p
		out.belt = null
		out.length = 0.0
		out.run_d = -1
		var start := locate(p, hint)
		if start.is_empty():
			return out
		out.segs = []
		var seen: Array = [[start[0], start[1], start[2], start[3], 0.0, -1, 0.0]]
		var left := dist
		while seen.size() < 32:
			var v: Array = seen[seen.size() - 1]
			var room := length(v[0], v[1], v[2]) - float(v[3])
			if left <= room:
				break
			var ways := next(v[0], v[1], v[2])
			if ways.size() > 1:
				out.kind = NONE
				return out
			if ways.is_empty():
				left = room
				break
			var n: Array = ways[0]
			seen.append([n[0], n[1], n[2], n[3], n[4], seen.size() - 1, 0.0])
			left -= room + float(n[4])
		var w: Array = seen[seen.size() - 1]
		return _chain(seen, seen.size() - 1, minf(float(w[3]) + maxf(left, 0.0), length(w[0], w[1], w[2])), out)

	## p on a lane of straight belt b, and q on the same line further on, over straight belts.
	func _straight_run(b: Belt, p: Vector2, q: Vector2, out: Route) -> bool:
		var f: Vector2 = AHEAD[b.d]
		var r: Vector2 = RIGHT_OF[b.d]
		var lat := (p - b.c).dot(r)
		if absf((q - b.c).dot(r) - lat) > ON_LANE or absf(absf(lat) - LANE) > ON_LANE:
			return false
		var ahead := (q - p).dot(f)
		if ahead < -ON_LANE:
			return false
		ahead = maxf(ahead, 0.0)
		var at := (p - b.c).dot(f) + 0.5 + ahead
		var on := b
		var k := 1
		while at > 1.0 + ON_LANE:
			on = belt_at(b.c + f * k)
			if on == null or on.kind != STRAIGHT or on.d != b.d:
				return false
			at -= 1.0
			k += 1
		out.kind = LINE
		out.end = p + f * ahead
		out.belt = on
		out.lane = 0 if lat < 0.0 else 1
		out.part = 0
		out.s = clampf(at, 0.0, 1.0)
		out.run_d = b.d
		out.run_end = run_on(on, out.lane, 0)
		return true

	## Where the lane runs straight on to from piece (b, lane, part), as a distance along its way
	## from the map's origin: over the straight belts in front, into an underground's entrance up to
	## where it goes under and into a splitter up to its fork. NAN for an arc or a hidden piece.
	func run_on(b: Belt, lane: int, part: int) -> float:
		var pc := piece(b, lane, part)
		if pc[P_ARC] != 0.0 or not shows(b, part):
			return NAN
		var tip := piece_point(pc, pc[P_LEN])
		var f: Vector2 = AHEAD[b.d]
		var end := tip.dot(f)
		if b.kind == UG_IN or (b.kind == SPLITTER and part % 2 == 0):
			return end
		var o := belt_at(tip + f * 0.5)
		if o == null or o.d != b.d:
			return end
		if o.kind != STRAIGHT:
			return end + (0.5 if o.kind == UG_IN else (SPLIT_AT if o.kind == SPLITTER else 0.0))
		if o.run_gen == generation:
			return o.run_end
		# Along the straight belts to the run's end, which each of them then remembers.
		var chain: Array = []
		var cur := o
		while cur != null and cur.kind == STRAIGHT and cur.d == b.d and chain.size() < RUN_AHEAD:
			if cur.run_gen == generation:
				end = cur.run_end
				cur = null
				break
			chain.append(cur)
			end += 1.0
			cur = belt_at(cur.c + f)
		if cur != null and cur.d == b.d:
			end += 0.5 if cur.kind == UG_IN else (SPLIT_AT if cur.kind == SPLITTER else 0.0)
		for x: Belt in chain:
			x.run_end = end
			x.run_gen = generation
		return end

	## p and q both on belt b's lanes, q further along (the same piece, or one it leads to on b: an
	## entrance's going under, a splitter's output of either half): the route without a walk.
	func _within(b: Belt, p: Vector2, q: Vector2, out: Route) -> bool:
		var n := parts(b)
		for lane in 2:
			for pa in n:
				var pc := piece(b, lane, pa)
				var sp := piece_project(pc, p)
				if sp.y > ON_LANE:
					continue
				for qa in n:
					if qa != pa and not ((b.kind == UG_IN and pa == 0 and qa == 1) or (b.kind == SPLITTER and pa % 2 == 0 and qa % 2 == 1)):
						continue
					var qc := piece(b, lane, qa)
					var sq := piece_project(qc, q, sp.x if qa == pa else 0.0)
					if sq.y <= ON_LANE and sq.x < qc[P_LEN] - 0.001:
						out.segs = []
						var seen: Array = [[b, lane, pa, sp.x, 0.0, -1, 0.0]]
						if qa != pa:
							seen.append([b, lane, qa, 0.0, 0.0, 0, 0.0])
						_chain(seen, seen.size() - 1, sq.x, out)
						return true
				return false
		return false

	## Follows the lanes from `start` (both ways out of a splitter) to the piece nearest q. What is
	## walked under the ground doesn't count towards `limit`: an item comes up at an exit however
	## long it was out of sight.
	func _walk(start: Array, p: Vector2, q: Vector2, limit: float, out: Route) -> Route:
		# Pieces visited: [belt, lane, part, s in, step, parent, length walked in sight to s in].
		var seen: Array = [[start[0], start[1], start[2], start[3], 0.0, -1, 0.0]]
		var best := -1
		var best_s := 0.0
		var best_d := INF
		var i := 0
		while i < seen.size():
			var v: Array = seen[i]
			var b: Belt = v[0]
			var lane: int = v[1]
			var part: int = v[2]
			var s_in: float = v[3]
			var pc := piece(b, lane, part)
			var pr := piece_project(pc, q, s_in)
			if pr.y < best_d - 0.001:
				best = i
				best_s = pr.x
				best_d = pr.y
				if pr.y < ON_LANE:
					break
			var walked: float = v[6] + (pc[P_LEN] - s_in if shows(b, part) else 0.0)
			if walked < limit and seen.size() < 64:
				for n: Array in next(b, lane, part):
					seen.append([n[0], n[1], n[2], n[3], n[4], i, walked + float(n[4])])
			i += 1
		if best < 0 or best_d > MATCH:
			var on := belt_at(q)
			if on != null and on.kind == OTHER:
				out.kind = LINE  # onto something not modelled here (a loader): straight, as before
				return out
			var n := nearest(on, q) if on != null else []
			if n.is_empty() or float(n[3]) >= MATCH or p.distance_to(q) < 1.0:
				# q is on no lane, or a lane close by that this one doesn't lead to: the mod carried
				# the item on in a straight line, past a lane's end (taken off the belt) or off a turn
				# (read some ticks early, the light mode). It goes on along its lane as far instead,
				# never over the ground or across to another lane.
				return _follow(seen, p.distance_to(q), q, out)
			# On a lane that can't be reached from here (moved some other way, a belt gone).
			out.kind = SNAP
			out.end = point(on, n[0], n[1], n[2])
			return out
		return _chain(seen, best, best_s, out)

	## Along the lanes from the start for `dist`, or to their end, taking the way on that leads
	## nearest q where there are two (a splitter).
	func _follow(seen: Array, dist: float, q: Vector2, out: Route) -> Route:
		var j := 0
		var left := dist
		while true:
			var v: Array = seen[j]
			var room := length(v[0], v[1], v[2]) - float(v[3])
			if left <= room:
				break
			var on := -1
			var on_d := INF
			for k in range(j + 1, seen.size()):
				if int(seen[k][5]) == j:
					var d := piece_project(piece(seen[k][0], seen[k][1], seen[k][2]), q, float(seen[k][3])).y
					if d < on_d:
						on = k
						on_d = d
			if on < 0:
				break
			left -= room + float(seen[on][4])
			j = on
		var w: Array = seen[j]
		var best_s := minf(float(w[3]) + maxf(left, 0.0), length(w[0], w[1], w[2]))
		return _chain(seen, j, best_s, out)

	## The pieces from the start to seen[best], ending at best_s: a LINE if they are one straight
	## lane in sight, else a PATH.
	func _chain(seen: Array, best: int, best_s: float, out: Route) -> Route:
		var chain: Array = []
		var j := best
		while j >= 0:
			chain.push_front(seen[j])
			j = int(seen[j][5])
		var straight := true
		var dir := Vector2.ZERO
		var across := 0.0
		for k in chain.size():
			var v: Array = chain[k]
			var b: Belt = v[0]
			var lane: int = v[1]
			var part: int = v[2]
			var pc := piece(b, lane, part)
			var s0: float = v[3]
			var s1: float = best_s if k == chain.size() - 1 else pc[P_LEN]
			out.segs.append([b, lane, part, s0, s1, float(v[4])])
			out.length += maxf(s1 - s0, 0.0) + float(v[4])
			if straight:
				if pc[P_ARC] != 0.0 or float(v[4]) > 0.0 or not shows(b, part):
					straight = false
				else:
					var a := Vector2(pc[1], pc[2])
					var f := Vector2(pc[3], pc[4])
					if k == 0:
						dir = f
						across = a.cross(f)
					elif f != dir or absf(a.cross(f) - across) > 0.01:
						straight = false
		var last_piece: Array = chain[chain.size() - 1]
		out.belt = last_piece[0]
		out.lane = last_piece[1]
		out.part = last_piece[2]
		out.s = best_s
		out.end = point(out.belt, out.lane, out.part, best_s)
		out.kind = LINE if straight or out.length < 0.001 else PATH
		var end := run_on(out.belt, out.lane, out.part)
		if not is_nan(end):
			out.run_d = out.belt.d
			out.run_end = end
		return out

	## A path's points, SPACING or less apart and evenly spread, from `from` (the item's place; y
	## its height): x, y, z offsets from it and whether it shows (1) or not (0).
	func points(r: Route, from: Vector3) -> PackedFloat32Array:
		var n := clampi(ceili(r.length / SPACING), 1, MAX_POINTS - 1)
		var out := PackedFloat32Array()
		out.resize((n + 1) * 4)
		var seg := 0
		var seg_start := 0.0  # distance along the route where seg's step onto it begins
		var pc := piece(r.segs[0][0], r.segs[0][1], r.segs[0][2])
		for k in n + 1:
			var at := r.length * k / n
			while seg < r.segs.size() - 1 and at > seg_start + seg_length(r.segs[seg]) + 1e-6:
				seg_start += seg_length(r.segs[seg])
				seg += 1
				pc = piece(r.segs[seg][0], r.segs[seg][1], r.segs[seg][2])
			var sg: Array = r.segs[seg]
			var into := at - seg_start
			var step: float = sg[5]
			var pt: Vector2
			if into < step:
				# Stepping across onto a side-loaded lane, from where the last piece ended.
				var to := piece_point(pc, float(sg[3]))
				var prev: Array = r.segs[maxi(seg - 1, 0)]
				pt = point(prev[0], prev[1], prev[2], float(prev[4])).lerp(to, into / step)
			else:
				pt = piece_point(pc, minf(float(sg[3]) + into - step, float(sg[4])))
			var o := k * 4
			if k > 0:  # the first point is where the item is drawn, whatever rounding put it off the lane
				out[o] = pt.x - from.x
				out[o + 2] = pt.y - from.z
			out[o + 3] = 1.0 if shows(sg[0], int(sg[2])) else 0.0
		return out

	static func seg_length(sg: Array) -> float:
		return maxf(float(sg[4]) - float(sg[3]), 0.0) + float(sg[5])

	## Where along a route's pieces (0 to 1 of its length) an item is: [belt, lane, part, s].
	static func along(segs: Array, length: float, t: float) -> Array:
		var d := length * clampf(t, 0.0, 1.0)
		for k in segs.size():
			var sg: Array = segs[k]
			var l := seg_length(sg)
			if d <= l or k == segs.size() - 1:
				return [sg[0], sg[1], sg[2], clampf(float(sg[3]) + d - float(sg[5]), float(sg[3]), float(sg[4]))]
			d -= l
		return []
