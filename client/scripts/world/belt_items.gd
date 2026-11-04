extends Node3D
## Items on belts near the camera. The mod sends every item's position a few times a second
## (`bi`). Each item, tracked by its unique id, glides from where it is drawn to its new position
## over the time until the next update, so it is drawn one update behind the game.
##
## It glides along its lane (belt_paths.gd): round a curve, through a splitter, out of sight in an
## underground, onto the lane it is side-loaded onto. Gliding in a straight line from one update to
## the next took items off the belts wherever the two weren't on one straight lane (owner's
## play-test: items floating across curves, over splitters and undergrounds, over buildings). The
## belts round the square the items come from are indexed from world.gd's records on the job's
## thread, chunk by chunk as they change.
##
## Lanes that didn't change aren't sent again (`bl` in the hello; belt_items.lua): each part says
## which lane its items came from (`ln`), and an item whose lane wasn't in an update stays where it
## is until its lane comes again or is dropped (`dl`). On a busy base most lanes are backed up and
## hold still, so the mod reads and sends only the few that move.
##
## Thousands of items can be in view, so the gliding happens on the GPU (item_cards.gd,
## belt_path.gdshaderinc): an update writes each item's position and how far it moves until the
## next one (a straight step, or for the few that turn, its path's points in a texture), and a
## frame only sets how far along that the items are. Each item keeps its slot in its type's
## MultiMesh, so an update rewrites a whole slot only for items that just arrived.
##
## The hand-over to the far lane icons (belt_lanes.gd, `lanes`) never leaves a belt bare and
## never draws it twice (owner): an item that falls outside the square an update covers stays,
## held where it is, until its chunk's icons are made (and at most KEEP_UPDATES updates), and the
## icons of a chunk that still has such items stay hidden; both change when a job's result is
## drawn, in the same frame, as does the square the icons are hidden in. Items of a kind whose look
## isn't made yet aren't drawn, so their icons stay shown inside the square until it is.
##
## A stack (a stack inserter puts up to 4 items in one place on a belt: one entry, one unique id;
## `bi` st says its size) is drawn as a pile, as Factorio draws it: the item and up to three more
## copies, each a step higher (the kind's pile_step()), each in a slot of its own (Layer) that
## follows the item's glide.
##
## The work of an update (decoding it, moving every item, filling the buffers: 20-30 ms for 6,000
## items on a real busy base) runs on a worker thread (Job), on State that only the job touches
## while it runs. The main thread queues messages, starts a job with them, and gives the finished
## buffers to the MultiMeshes in a later frame.

const ProtoDB := preload("res://scripts/world/protos.gd")
const ItemCards := preload("res://scripts/world/item_cards.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const GameClock := preload("res://scripts/world/game_clock.gd")
const BeltPaths := preload("res://scripts/world/belt_paths.gd")
const WorldMirror := preload("res://scripts/world/world.gd")

## An item missing from this many updates in a row was taken off the belt; out of sight in an
## underground (the mod sends only what is inside a belt), it comes up at the exit: 120 updates is
## 12 seconds, under the longest underground at a yellow belt's speed.
const MISSING_FRAMES := 2
const MISSING_HIDDEN := 120
## Just above a placeholder belt (0.15 tall), when there is no belt model.
const PLACEHOLDER_HEIGHT := 0.16
## Neighbouring items on a lane are closer than a card is wide, so their cards overlap; at one
## height they fought over every pixel they share (red and green circuits flickering along a belt).
## Each item sits a step higher or lower by its id, so an overlap always resolves the same way.
const LAYER_STEP := 0.006
const LAYERS := 4
## Further than an item travels between updates: it was moved some other way, so don't glide. A turbo
## belt carries an item 1.5 tiles in the 12 ticks between updates on a busy base (belt_items.lua).
const SNAP_DISTANCE := 2.0
## A turbo belt's speed, tiles a tick, with some to spare: when the mod is slowed down (`rate`) the
## updates are further apart (bi p, up to 48 ticks: 6 tiles), so the snap distance grows with them.
const FASTEST_BELT := 0.15
## Ticks behind one gap behind the game's clock items are drawn at, for messages a frame or two late.
const DRAW_MARGIN := 2.0
## Items reach this far past the square an update covers (a belt on its edge is read whole).
const SQUARE_SLACK := 1.0
const STRIDE := ItemCards.STRIDE
const ON_LANE := BeltPaths.ON_LANE
## Belts are indexed this far past the square the items come from (an underground's exit beyond it).
const INDEX_MARGIN := 14.0
## The paths' texture: this many points a row, rows a power of two, at most MAX_ROWS (the code in
## an instance's custom data must stay an exact float: under 2^24).
const PATH_WIDTH := 1024
const MAX_ROWS := 256
## An item still under the ground: two points there, not shown.
const HIDDEN := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## An item kept outside the square for its chunk's icons (see above) goes after this many updates
## whatever happens (a chunk whose icons never come: no far lanes there).
const KEEP_UPDATES := 40
## Factorio's max_belt_stack_size (utility constants): the highest pile.
const MAX_STACK := 4
## A pile's copies turn this much more each, so a pile of models doesn't look like one tall block.
const PILE_TURN := 0.45


class Item:
	var item_id := 0
	var c := 1.0  # cosine and sine of its turn
	var s := 0.0
	var from := Vector3.ZERO  # where it was drawn when the last update began
	var step := Vector3.ZERO  # how far it glides until the next
	var slot := -1  # in its kind's MultiMesh, or -1 before it has one
	var seen := -1  # the update (State.frame) it was last in
	var missed := 0  # updates missed in a row
	var lane := 0  # the lane (bi ln key) it was last sent in, 0 none: held while that lane isn't sent
	var hint: BeltPaths.Belt = null  # the belt `from` is on, where the next route starts looking
	## Its glide along its lane's path when that isn't straight: points (x, y, z offsets from
	## `from`, and 1 where it shows), the route's pieces and length (where it is part way).
	var path := PackedFloat32Array()
	var segs: Array = []
	var length := 0.0
	## Tiles a tick along its lane in its last glide that wasn't along a known run (to carry it on
	## under the ground: it reaches an underground's entrance off its run).
	var speed := 0.0
	## Under the ground: which lane of its entrance (hint) it is on, and how far along the hidden
	## stretch (-1 not known), so it is carried on without looking for it.
	var under_lane := 0
	var under_s := -1.0
	## On a run of straight belts (graph generation `run_gen`, else -1): whether it runs north-south
	## (else east-west), and the stretch of that axis from where the item joined it to the run's end.
	## While it stays on that line (belts face 4 ways: its other coordinate stays put) and within
	## the stretch, it glides straight without looking anything up: most of a dense base's items,
	## every update.
	var run_z := false
	var run_min := 0.0
	var run_max := 0.0
	var run_gen := -1
	## The stack's size (bi st, 1 when not listed) and its copies above it, one Layer each.
	var count := 1
	var layers: Array = []
	var kept := 0  # updates it has been kept outside the square, waiting for its chunk's icons
	## Its glide in the last update it was in, when straight: what it goes on with in an update
	## it is missing from (carry_missing()).
	var last_step := Vector3.ZERO
	## Its path's place in the paths' texture in the _write() numbered code_at (its layers share it).
	var code := 0.0
	var code_at := -1


## One copy in a pile, k steps above its item, in a slot of the item's kind.
class Layer:
	var it: Item
	var k := 1
	var slot := -1
	var c := 1.0
	var s := 0.0


class Kind:
	var slots := []  # Item or null, by slot
	var free: Array[int] = []  # empty slots below slots.size()
	var fresh := []  # Items that need their whole slot written
	var emptied: Array[int] = []  # slots to hide
	var buf := PackedFloat32Array()  # the MultiMesh's instances, cap of them
	var cap := 0
	var lift := Vector3.ZERO  # item_cards.gd's lift(), turns() and pile_step() for this kind, once known
	var turns := false
	var pile := 0.07
	var known := false


## Everything the jobs work on. The main thread reads it only while no job runs.
class State:
	var items := {}  # unique id -> Item
	var kinds := {}  # item id -> Kind
	var frame := 0  # updates begun
	var tick := -1  # the game tick of the update being received
	var height := PLACEHOLDER_HEIGHT
	## The square the mod read the update round (bi fx, fy, fr): centre x, y and half side in
	## tiles; z < 0 before a mod that says so has sent one.
	var square := Vector3(0.0, 0.0, -1.0)
	## Ticks until the next update (bi p), or 0 when the mod doesn't say.
	var period := 0
	var snap := SNAP_DISTANCE
	var graph := BeltPaths.Graph.new()
	## Lane key -> the update (frame) it was last sent in. An item of a lane not sent in an update
	## is held: it stays where it is, not counted missing.
	var lane_frame := {}
	## Chunks with items kept outside the square, waiting for their far icons (Job.held_chunks).
	var held_chunks := {}


## One job: the messages queued since the last, applied to State on a worker thread.
class Job:
	var state: State
	var msgs: Array = []
	## How far the items will be along their glide when the result is drawn: an update that begins
	## folds it into where each item is (it stops where it is drawn and glides on from there).
	var fold := 0.0
	var fold_tick := 0.0  # the drawn tick then, where the new glide starts
	var full := false  # every slot written again (the MultiMeshes were dropped)
	var known := {}  # item id -> [lift, turns, pile step] for kinds item_cards.gd has made
	var watch: Array = []  # unique ids whose positions position_of() wants
	## Chunks whose far icons are made (belt_lanes.gd), or null with far icons off: items outside
	## the square go at once.
	var far_built = null
	var kinds = null  # belt prototypes (BeltPaths.Graph.kinds) when they changed
	var index: Array = []  # [chunk, its entity records, whole] to index
	var drops: Array = []  # chunks no longer indexed
	# Results
	var began := false  # an update began: its glide starts when the result is drawn
	var updates := 0  # updates begun after one already received
	var first_tick := -1  # the tick of the first update begun, and of the last one
	var last_tick := -1
	var prev_tick := -1  # the tick before the first one begun
	var written: Array = []  # [item id, buffer, items drawn, capacity] for kinds with known looks
	var unknown: Array = []  # item ids whose looks item_cards.gd must make first
	var count := 0
	var positions := {}  # unique id -> [from, step, path]
	var square := Vector3(0.0, 0.0, -1.0)
	var paths: Image = null  # the paths' points, when some item has one
	var usec := 0  # how long run() took
	var index_usec := 0  # of which indexing belts
	var write_usec := 0  # and writing the buffers
	var updated := 0  # items in the job's messages (those not routed, fresh or put somewhere went on along a known run)
	var fresh := 0  # items new to the client, and items missing from an update
	var missing := 0
	var held := 0  # items kept in place because their lane wasn't sent (bl)
	var held_chunks := {}  # chunks with items kept outside the square, waiting for their icons
	## Glides by how they went: belts not known (straight, as before), straight along a lane, along a
	## lane's path, put where they are (not reachable), and moved too far to glide.
	var routes := PackedInt32Array([0, 0, 0, 0, 0])
	var route_usec := 0  # of which routing items not on a known run, and folding glides as updates begin
	var fold_usec := 0
	static var hidden_path := PackedFloat32Array(HIDDEN)  # shared, never written to
	var gen := -1  # the graph's generation in this job (the belts don't change while it runs)
	static var _writes := 0  # numbers each _write(), for Item.code_at

	func run() -> void:
		var t0 := Time.get_ticks_usec()
		prev_tick = state.tick
		var g := state.graph
		if kinds != null:
			g.kinds = kinds
		for c in drops:
			g.drop(c)
		for e: Array in index:
			g.index(e[0], e[1], e[2])
		gen = g.generation
		index_usec = Time.get_ticks_usec() - t0
		for msg: Dictionary in msgs:
			_handle(msg)
		if began:
			carry_missing()
		var t1 := Time.get_ticks_usec()
		_write()
		write_usec = Time.get_ticks_usec() - t1
		count = state.items.size()
		square = state.square
		held_chunks = state.held_chunks.duplicate()
		for uid in watch:
			var it: Item = state.items.get(uid)
			if it != null:
				positions[uid] = [it.from, it.step, it.path]
		usec = Time.get_ticks_usec() - t0

	## One part of an update: {t: "bi", k: tick, part, parts, l: [unique id, item id, x, y, ...]}.
	## With z = 1 (we ask for it in the hello) every number is the difference from the item before it.
	func _handle(msg: Dictionary) -> void:
		var k := int(msg.get("k", 0))
		var sq := state.square
		if msg.has("fr"):
			sq = Vector3(int(msg.get("fx", 0)) / 256.0, int(msg.get("fy", 0)) / 256.0, int(msg.get("fr", 0)))
		if k != state.tick:
			var tb := Time.get_ticks_usec()
			_begin_frame(sq)
			fold_usec += Time.get_ticks_usec() - tb
			state.tick = k
			if first_tick < 0:
				first_tick = k
			last_tick = k
			state.period = int(msg.get("p", 0))
			state.snap = maxf(SNAP_DISTANCE, state.period * FASTEST_BELT)
		state.square = sq
		var list = msg.get("l")
		if not (list is Array):
			return
		var deltas := int(msg.get("z", 0)) == 1
		# Which lane each run of items came from: [key, count, ...]; every lane named was sent now.
		var ln = msg.get("ln")
		var by_lane := ln is Array
		var run := 0
		var left := 0
		var lane := 0
		if by_lane:
			for j in range(0, (ln as Array).size() - 1, 2):
				state.lane_frame[int(ln[j])] = state.frame
		var dl = msg.get("dl")
		if dl is Array and not (dl as Array).is_empty():
			_drop_lanes(dl)
		# Stacks' sizes by unique id; every item of the part not listed is a single one.
		var sizes := {}
		var st = msg.get("st")
		if st is Array:
			for j in range(0, (st as Array).size() - 1, 2):
				sizes[int(st[j])] = int(st[j + 1])
		var uid := 0
		var item_id := 0
		var x := 0
		var y := 0
		var i := 0
		var height := state.height
		while i + 3 < list.size():
			if deltas:
				uid += int(list[i])
				item_id += int(list[i + 1])
				x += int(list[i + 2])
				y += int(list[i + 3])
			else:
				uid = int(list[i])
				item_id = int(list[i + 1])
				x = int(list[i + 2])
				y = int(list[i + 3])
			if by_lane:
				while left == 0 and run + 1 < (ln as Array).size():
					lane = int(ln[run])
					left = int(ln[run + 1])
					run += 2
				if left > 0:
					left -= 1
				else:
					lane = 0
			var it := _update(uid, item_id, Vector3(x / 256.0, height + LAYER_STEP * posmod(uid, LAYERS), y / 256.0), lane)
			_set_count(it, int(sizes.get(uid, 1)))
			i += 4
		updated += list.size() / 4

	## Items the update left out go on at their last pace along the straight run they are on,
	## instead of stopping. The bridge reads
	## belts over several ticks on a busy base (Smooth belt items off, which Hold 60 UPS does under
	## load), so an item moving from a belt read later to one read earlier is in neither reading; it
	## stopped for an update and then jumped to where it was (owner: items "stop and jump around").
	## An item that was in the update keeps its new glide as its pace for next time. Held items
	## (their lane not sent: bl) stay still, as their belt is.
	func carry_missing() -> void:
		for uid in state.items:
			var it: Item = state.items[uid]
			if it.seen == state.frame:
				it.last_step = it.step if it.path.is_empty() else Vector3.ZERO
			elif not (it.lane != 0 and _held(it)) and it.path.is_empty() and it.missed < MISSING_FRAMES and not _under(it) 					and _stays_on_run(it, it.from + it.last_step):
				it.step = it.last_step

	## Whether `to` is still on the straight run of belts the item is on (a known run, this graph):
	## carried on past its end it would leave the belt where it turns.
	func _stays_on_run(it: Item, to: Vector3) -> bool:
		if state.graph.tiles.is_empty():
			return true  # belts not known (tests): items glide straight anyway
		if it.run_gen != gen:
			return false
		if it.run_z:
			return absf(to.x - it.from.x) <= ON_LANE and to.z >= it.run_min and to.z <= it.run_max
		return absf(to.z - it.from.z) <= ON_LANE and to.x >= it.run_min and to.x <= it.run_max

	## Whether an item missing from the last update was held there: its lane wasn't sent, and the
	## item was in that lane's last sending (one that left the lane since is missing).
	func _held(it: Item) -> bool:
		var f = state.lane_frame.get(it.lane)
		return f != null and int(f) != state.frame and it.seen >= int(f)

	## Lanes no longer read (out of the square, their belt gone): their items go at once.
	func _drop_lanes(keys: Array) -> void:
		var drop := {}
		for k in keys:
			drop[int(k)] = true
			state.lane_frame.erase(int(k))
		var gone: Array = []
		for uid in state.items:
			var it: Item = state.items[uid]
			if it.lane != 0 and drop.has(it.lane):
				if _wait_for_icons(it):
					it.lane = 0
				else:
					gone.append(uid)
		for uid in gone:
			_unplace(state.items[uid])
			state.items.erase(uid)

	## Whether an item outside the square stays (held) until its chunk's far icons are made.
	func _wait_for_icons(it: Item) -> bool:
		if far_built == null or it.kept >= KEEP_UPDATES:
			return false
		var c := Vector2i(floori(it.from.x / 32.0), floori(it.from.z / 32.0))
		if (far_built as Dictionary).has(c):
			return false
		state.held_chunks[c] = true
		return true

	func _update(uid: int, item_id: int, pos: Vector3, lane := 0) -> Item:
		var it: Item = state.items.get(uid)
		if it != null:
			it.lane = lane
		if it == null:
			it = Item.new()
			it.lane = lane
			it.item_id = item_id
			it.from = pos
			var a := ItemCards.yaw_for(uid)
			it.c = cos(a)
			it.s = sin(a)
			state.items[uid] = it
			_place(it)
			_settle(it)
			fresh += 1
			it.missed = 0
			it.seen = state.frame
			return it
		it.seen = state.frame
		it.missed = 0
		if it.item_id != item_id:
			_unplace(it)
			it.item_id = item_id
			_place(it)
		# Most of a dense base's items, every update: on along the run of straight belts it is on,
		# its lane known, nothing looked up (worked out here, not in _glide: this runs thousands of
		# times an update). An item with a path has no run.
		if it.run_gen == gen:
			if it.run_z:
				if absf(pos.x - it.from.x) <= ON_LANE and pos.z >= it.run_min and pos.z <= it.run_max:
					it.step = Vector3(0.0, 0.0, pos.z - it.from.z)
					return it
			elif absf(pos.z - it.from.z) <= ON_LANE and pos.x >= it.run_min and pos.x <= it.run_max:
				it.step = Vector3(pos.x - it.from.x, 0.0, 0.0)
				return it
		var tg := Time.get_ticks_usec()
		_glide(it, pos)
		route_usec += Time.get_ticks_usec() - tg
		return it

	## A stack of n: its pile has n - 1 copies above it, each in a slot of its kind.
	func _set_count(it: Item, n: int) -> void:
		n = clampi(n, 1, MAX_STACK)
		it.count = n
		if it.slot < 0 or it.layers.size() == n - 1:
			return
		var kind: Kind = state.kinds[it.item_id]
		while it.layers.size() > n - 1:
			var gone: Layer = it.layers.pop_back()
			kind.slots[gone.slot] = null
			kind.free.append(gone.slot)
			kind.emptied.append(gone.slot)
			gone.slot = -1
		while it.layers.size() < n - 1:
			var layer := Layer.new()
			layer.it = it
			layer.k = it.layers.size() + 1
			var a := atan2(it.s, it.c) + PILE_TURN * layer.k
			layer.c = cos(a)
			layer.s = sin(a)
			_put(kind, layer)
			it.layers.append(layer)

	## From where the item is drawn to `pos`: along its lane, or (belts not known there) straight.
	## Along its lanes it goes as far as they lead to pos, which may be further than a glide would
	## go when the mod's guess left the lane; moved some other way, it is put there.
	func _glide(it: Item, pos: Vector3) -> void:
		# Under the ground (HIDDEN) it may come up at an exit further away than a glide would go.
		# (Most items have no path: nothing to make or clear for them, thousands an update.)
		var under := false
		var g := state.graph
		if not it.path.is_empty():
			under = it.path[it.path.size() - 1] < 0.5
			it.path = PackedFloat32Array()
			it.segs = []
		it.run_gen = -1
		var far := it.from.distance_to(pos)
		var r := g.route(Vector2(it.from.x, it.from.z), Vector2(pos.x, pos.z), it.hint, maxf(state.snap, far) * 1.6)
		if r.kind == BeltPaths.NONE and (under or far >= state.snap):
			it.from = pos
			it.step = Vector3.ZERO
			_settle(it)
			routes[4] += 1
			return
		routes[r.kind] += 1
		match r.kind:
			BeltPaths.LINE:
				it.step = Vector3(r.end.x - it.from.x, 0.0, r.end.y - it.from.z)
				it.hint = r.belt
				it.speed = it.step.length() / maxf(state.period, 1.0)
				_keep_run(it, r, Vector2(it.from.x, it.from.z))
				if r.belt != null and not BeltPaths.Graph.shows(r.belt, r.part):
					it.path = hidden_path  # still under the ground
					it.under_lane = r.lane
					it.under_s = r.s
			BeltPaths.PATH:
				it.step = Vector3(r.end.x - it.from.x, 0.0, r.end.y - it.from.z)
				it.path = g.points(r, it.from)
				it.segs = r.segs
				it.length = r.length
				it.hint = r.belt
				it.speed = r.length / maxf(state.period, 1.0)
				_keep_run(it, r, r.end)
			BeltPaths.SNAP:
				it.from = Vector3(r.end.x, pos.y, r.end.y)
				it.step = Vector3.ZERO
				it.hint = null
				_settle(it)
			_:
				it.step = pos - it.from
				it.hint = null

	## A route that ends on a straight piece of lane: the item glides on along it without a look
	## while it stays on its line, from `at` (on the line) to where the lane runs straight to.
	func _keep_run(it: Item, r: BeltPaths.Route, at: Vector2) -> void:
		if r.run_d < 0 or is_nan(r.run_end):
			return
		var f: Vector2 = BeltPaths.AHEAD[r.run_d]
		it.run_z = f.x == 0.0
		var a := at.y if it.run_z else at.x
		var end := r.run_end * (f.y if it.run_z else f.x)  # f's component is 1 or -1
		it.run_min = minf(a, end) - ON_LANE
		it.run_max = maxf(a, end) + ON_LANE
		it.run_gen = gen

	## Out of sight under the ground (its path ends hidden: HIDDEN after an update began).
	static func _under(it: Item) -> bool:
		return not it.path.is_empty() and it.path[it.path.size() - 1] < 0.5

	## Whether an underground's entrance is within an update's travel in front of an item (it is
	## on one, or on the straight belts in front of one).
	func _entrance_ahead(it: Item) -> bool:
		var p := Vector2(it.from.x, it.from.z)
		var b: BeltPaths.Belt = state.graph.belt_at(p)
		if b == null or b.kind == BeltPaths.UG_IN:
			return b != null
		if b.kind != BeltPaths.STRAIGHT:
			return false
		var f: Vector2 = BeltPaths.AHEAD[b.d]
		var reach := it.speed * maxf(state.period, 1.0) + 1.0
		var k := 0.5
		while k <= reach:
			var o := state.graph.belt_at(p + f * k)
			if o == null or o.d != b.d or (o.kind != BeltPaths.STRAIGHT and o.kind != BeltPaths.UG_IN):
				return false
			if o.kind == BeltPaths.UG_IN:
				return true
			k += 1.0
		return false

	## An item missing from an update just before an underground's entrance went under (the mod
	## sends only what is inside a belt): it glides on into it at its speed, out of sight.
	func _carry_into_ground(it: Item) -> void:
		var g := state.graph
		it.run_gen = -1
		var r := g.advance(Vector2(it.from.x, it.from.z), it.hint, it.speed * maxf(state.period, 1.0))
		if r.kind != BeltPaths.PATH or BeltPaths.Graph.shows(r.belt, r.part):
			return
		it.step = Vector3(r.end.x - it.from.x, 0.0, r.end.y - it.from.z)
		it.path = g.points(r, it.from)
		it.segs = r.segs
		it.length = r.length
		it.hint = r.belt

	## An item under the ground isn't sent (it is outside every belt): it goes on at its speed
	## meanwhile, so it comes up at the exit when the game has it there, not all at once.
	func _carry_under(it: Item) -> void:
		var g := state.graph
		if it.hint == null or it.speed <= 0.0 or not g.alive(it.hint):
			return
		if it.under_s < 0.0:
			var at := g.locate(Vector2(it.from.x, it.from.z), it.hint)
			if at.is_empty() or at[0] != it.hint or int(at[2]) != 1:
				return
			it.under_lane = at[1]
			it.under_s = at[3]
		var pc := g.piece(it.hint, it.under_lane, 1)
		it.under_s = minf(it.under_s + it.speed * maxf(state.period, 1.0), pc[BeltPaths.P_LEN])
		var p := BeltPaths.Graph.piece_point(pc, it.under_s)
		it.from.x = p.x
		it.from.z = p.y

	## An item that doesn't glide (new, or put somewhere): onto its lane, and out of sight under
	## the ground.
	func _settle(it: Item) -> void:
		var g := state.graph
		it.run_gen = -1
		var p := Vector2(it.from.x, it.from.z)
		if not g.knows(p):
			return
		var at := g.locate(p, it.hint)
		if at.is_empty():
			it.hint = null
			return
		var b: BeltPaths.Belt = at[0]
		var q := g.point(b, int(at[1]), int(at[2]), float(at[3]))
		it.from.x = q.x
		it.from.z = q.y
		it.hint = b
		if not BeltPaths.Graph.shows(b, int(at[2])):
			it.path = hidden_path
			it.under_lane = at[1]
			it.under_s = at[3]

	func _place(it: Item) -> void:
		var kind: Kind = state.kinds.get(it.item_id)
		if kind == null:
			kind = Kind.new()
			state.kinds[it.item_id] = kind
		_put(kind, it)

	## An Item or a Layer into a free slot of its kind.
	func _put(kind: Kind, e) -> void:
		if kind.free.is_empty():
			e.slot = kind.slots.size()
			kind.slots.append(e)
		else:
			e.slot = kind.free.pop_back()
			kind.slots[e.slot] = e
		kind.fresh.append(e)

	## Takes an item and its pile's copies out of their kind (_set_count() puts the copies back).
	func _unplace(it: Item) -> void:
		var kind: Kind = state.kinds[it.item_id]
		for e in [it] + it.layers:
			kind.slots[e.slot] = null
			kind.free.append(e.slot)
			kind.emptied.append(e.slot)
			e.slot = -1
		it.layers = []

	## A new update begins: every item stops where it is drawn and waits for its new position;
	## items gone for MISSING_FRAMES updates are taken off, and at once those outside the square
	## the new update covers (`sq`): lane icons take over there when this is drawn. A second
	## update in one job was never drawn: its items glide on from where they stopped.
	func _begin_frame(sq: Vector3) -> void:
		if state.tick < 0:
			state.frame += 1
			began = true
			return
		var t := 0.0 if began else fold
		began = true
		updates += 1
		state.held_chunks = {}  # found again below, for the items still kept
		var gone: Array = []
		var edge := sq.z + SQUARE_SLACK
		for uid in state.items:
			var it: Item = state.items[uid]
			if it.path.is_empty():
				it.from += it.step * t
			elif not it.segs.is_empty():
				var o := BeltPaths.path_at(it.path, t)
				it.from += Vector3(o.x, o.y, o.z)
				var cur := BeltPaths.Graph.along(it.segs, it.length, t)
				if not cur.is_empty():
					it.hint = cur[0]
					it.under_lane = cur[1]
					it.under_s = cur[3] if int(cur[2]) == 1 else -1.0
				it.path = hidden_path if o.w < 0.5 else PackedFloat32Array()
				it.segs = []
				if o.w < 0.5:
					it.run_gen = -1  # under the ground, in line with the exit's lane: not on it yet
			# (else HIDDEN: it stays where it is, out of sight)
			it.step = Vector3.ZERO
			if sq.z >= 0.0 and (absf(it.from.x - sq.x) > edge or absf(it.from.z - sq.y) > edge):
				if _wait_for_icons(it):
					it.kept += 1
					it.seen = state.frame
					it.missed = 0
					it.lane = 0
				else:
					gone.append(uid)
			elif it.seen != state.frame and it.lane != 0 and _held(it):
				# Its lane wasn't sent: it holds still where it is (`bl`).
				it.seen = state.frame
				it.missed = 0
				held += 1
			elif it.seen != state.frame:
				it.missed += 1
				missing += 1
				if _under(it):
					_carry_under(it)
				elif it.speed > 0.0 and _entrance_ahead(it):
					_carry_into_ground(it)
				if it.missed >= (MISSING_HIDDEN if _under(it) else MISSING_FRAMES):
					gone.append(uid)
		for uid in gone:
			_unplace(state.items[uid])
			state.items.erase(uid)
		state.frame += 1

	## Writes every kind's buffer: whole slots for new items, positions and glides for the rest, and
	## the paths' texture.
	func _write() -> void:
		var tex := PackedFloat32Array()
		var texels := 0
		var room := PATH_WIDTH * MAX_ROWS
		_writes += 1
		var writing := _writes
		for item_id in state.kinds:
			var kind: Kind = state.kinds[item_id]
			var look: Array = known.get(item_id, [])
			if full:
				kind.known = false  # the looks may have changed (Settings > Items on belts)
			if not kind.known and not look.is_empty():
				kind.known = true
				kind.lift = look[0]
				kind.turns = look[1]
				kind.pile = float(look[2]) if look.size() > 2 else 0.07
				kind.fresh = kind.slots.filter(func(e) -> bool: return e != null)
			if full:
				kind.fresh = kind.slots.filter(func(e) -> bool: return e != null)
				kind.emptied = kind.free.duplicate()
			_compact(kind)
			var n := kind.slots.size()
			if n > kind.cap:
				kind.cap = maxi(n, kind.cap * 2)
				kind.buf.resize(kind.cap * STRIDE)
				kind.fresh = kind.slots.filter(func(e) -> bool: return e != null)
				kind.emptied = kind.free.duplicate()
			if not kind.known:
				unknown.append(item_id)
				continue
			var buf := kind.buf
			kind.buf = PackedFloat32Array()  # out of the kind while written, so writing doesn't copy it
			var up := kind.lift
			var turns := kind.turns
			for i in kind.emptied:
				if i < kind.cap:
					ItemCards.clear_slot(buf, i * STRIDE)
			kind.emptied.clear()
			var pile := kind.pile
			for e in kind.fresh:
				if e.slot < 0:
					continue
				if e is Layer:
					var layer: Layer = e
					ItemCards.write(buf, e.slot * STRIDE, layer.it.from + up + Vector3(0.0, pile * layer.k, 0.0),
						layer.c if turns else 1.0, layer.s if turns else 0.0, layer.it.step)
				else:
					var item: Item = e
					ItemCards.write(buf, e.slot * STRIDE, item.from + up, item.c if turns else 1.0, item.s if turns else 0.0, item.step)
			kind.fresh.clear()
			var o := 0
			for e in kind.slots:
				if e != null:
					var it: Item = e if e is Item else (e as Layer).it
					var lift := up.y + (pile * (e as Layer).k if e is Layer else 0.0)
					var p: Vector3 = it.from
					var d: Vector3 = it.step
					buf[o + 3] = p.x + up.x
					buf[o + 7] = p.y + lift
					buf[o + 11] = p.z + up.z
					buf[o + 12] = d.x
					buf[o + 13] = d.y
					buf[o + 14] = d.z
					if it.path.is_empty():
						buf[o + 15] = 0.0
					else:
						# A pile's copies share their item's path (written once a _write()).
						if it.code_at != writing:
							it.code_at = writing
							var path: PackedFloat32Array = it.path
							var k := path.size() / 4
							it.code = 0.0
							if texels + k <= room:
								it.code = 1.0 + texels * 64 + (k - 2)
								tex.append_array(path)
								texels += k
						buf[o + 15] = it.code
				o += STRIDE
			kind.buf = buf
			written.append([item_id, buf, n, kind.cap])
		if texels > 0:
			var rows := 1
			while rows * PATH_WIDTH < texels:
				rows *= 2
			tex.resize(rows * PATH_WIDTH * 4)
			paths = Image.create_from_data(PATH_WIDTH, rows, false, Image.FORMAT_RGBAF, tex.to_byte_array())

	## Drops empty slots at the end, and packs a kind whose slots are mostly empty (a belt that
	## emptied), so the GPU doesn't draw thousands of hidden items.
	func _compact(kind: Kind) -> void:
		while not kind.slots.is_empty() and kind.slots.back() == null:
			kind.slots.pop_back()
		var n := kind.slots.size()
		if kind.free.size() > 64 and kind.free.size() * 2 > n:
			var packed := []
			for e in kind.slots:
				if e != null:
					e.slot = packed.size()
					packed.append(e)
			kind.slots = packed
			kind.fresh = packed.duplicate()
			kind.free.clear()
			kind.emptied.clear()
			return
		if kind.free.size() > 0:
			var kept: Array[int] = []
			for i in kind.free:
				if i < n:
					kept.append(i)
			kind.free = kept


var protos: ProtoDB:
	set(value):
		protos = value
		_cards.protos = value

## world.gd: the belts items ride come from its entity records (entities_changed says which chunks
## changed). Without it items glide in straight lines (tests).
var world: WorldMirror = null:
	set(value):
		if world != null and world.entities_changed.is_connected(_on_entities_changed):
			world.entities_changed.disconnect(_on_entities_changed)
		world = value
		if world != null:
			world.entities_changed.connect(_on_entities_changed)

var _cards := ItemCards.new()
var _state := State.new()
## belt_lanes.gd (main.gd sets it): the far icons this layer hands over to.
var lanes: Node = null
var _belt_dirty := {}  # Vector2i chunk -> true: its entities changed since it was indexed
var _indexed := {}  # Vector2i chunk -> whether its whole snapshot was indexed, as the job's graph has it
var _kinds_count := -1  # protos.entities.size() when the belt prototypes were last given to a job
var _given: Array = []  # index_chunk()'s chunks for the next job
var _paths: ImageTexture = null
var _paths_image: Image = null  # what _paths was last made from (tests)
var _inbox: Array = []  # messages waiting for the next job
## A big update comes in many parts, which the bridge's message handling may spread over frames
## (bridge.gd HANDLE_USEC). They go to a job together, once all have come (or the next update
## does): a job with only some of them stopped the other items until theirs came, a frame or two
## later, and then they jumped on, splitting full lanes apart (owner: "the odd moments they split").
var _parts: Array = []
var _parts_tick := -1
var _job: Job = null
var _task := -1
var _known := {}  # item id -> [lift, turns], kinds item_cards.gd has made
var _rewrite := false  # every slot written again on the next job
## Items glide on the game's clock (the messages' ticks, run on at the game's measured rate), one
## gap between updates behind it: each glide runs from the drawn tick when its update came in
## (_from_tick) to that update's tick (_to_tick). The gap is what the updates say (`p`), eased in
## when the mod is slowed down (`rate`), so items keep an even speed when updates come further apart
## or the server runs slow; they stop only if an update is late.
var _clock := GameClock.new()
var _drawn := -1.0
var _from_tick := 0.0
var _to_tick := 1.0
var _count := 0
var _square := Vector3(0.0, 0.0, -1.0)
var _positions := {}  # unique id -> [from, step, path] for the ids position_of() asked about
var _watch := {}  # those ids
var _epoch := -1  # _cards.epoch when the buffers were last written
var _height_known := false
## --belt-items-sync: jobs run on the main thread at once (tests, comparing).
var _sync := false

## --item-bench: every 5 s, print frame times and this layer's own time (docs/RUNNING.md).
var _bench := false
var _bench_frames := 0
var _bench_time := 0.0
var _bench_worst := 0.0
var _bench_usec := 0
var _bench_worker_usec := 0
var _bench_jobs := 0
## Totals for probes: this layer's main-thread time, its jobs' time on the worker, and how items
## glided (Job.routes: not known, straight on a lane, along a path, snapped, moved too far).
var stats := {"frames": 0, "main_usec": 0, "jobs": 0, "worker_usec": 0, "worst_job_usec": 0, "routes": [0, 0, 0, 0, 0],
	"indexed": 0, "index_usec": 0, "write_usec": 0, "cached": 0, "fresh": 0, "missing": 0, "runs": 0, "walks": [0, 0, 0, 0, 0, 0, 0],
	"route_usec": 0, "fold_usec": 0, "held": 0}


func _ready() -> void:
	_clock.ease = 0.5  # drawn one gap behind: half speed while a longer gap is taken up
	_cards.name = "Cards"
	add_child(_cards)
	_bench = "--item-bench" in OS.get_cmdline_user_args()
	_sync = "--belt-items-sync" in OS.get_cmdline_user_args()
	if _bench:
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _exit_tree() -> void:
	_wait(false)


func reset() -> void:
	_parts = []
	_parts_tick = -1
	_wait(false)
	var height := _state.height
	_state = State.new()
	_state.height = height
	_inbox.clear()
	_belt_dirty.clear()
	_indexed.clear()
	_kinds_count = -1
	_cards.reset()
	_known.clear()
	_positions.clear()
	_count = 0
	_square = Vector3(0.0, 0.0, -1.0)
	_clock = GameClock.new()
	_clock.ease = 0.5
	_drawn = -1.0


func count() -> int:
	return _count


## The square round which the items drawn now were read: centre x, y and half side in tiles, or
## z < 0 when the mod doesn't say. belt_lanes.gd draws lane icons from its edge, so the two hand
## over where the items stop, not round the camera, which runs ahead of them while panning.
func covered() -> Vector3:
	return _square


func handle(msg: Dictionary) -> void:
	_clock.heard(float(msg.get("k", 0)), float(msg.get("p", 0)))
	var parts := int(msg.get("parts", 1))
	if parts <= 1:
		_flush_parts()
		_inbox.append(msg)
		return
	var k := int(msg.get("k", 0))
	if k != _parts_tick:
		_flush_parts()  # an update a part never came for goes as it is
		_parts_tick = k
	_parts.append(msg)
	if _parts.size() >= parts:
		_flush_parts()


## The parts held so far to the next job.
func _flush_parts() -> void:
	if not _parts.is_empty():
		_inbox.append_array(_parts)
		_parts = []
	_parts_tick = -1


## Waits for the running job and draws what it made (`apply`), or drops it (leaving the tree, a
## reset: nothing is made for a world that is going).
func _wait(apply := true) -> void:
	if _task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if apply:
		_apply(_job)
	_job = null


func _process(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_clock.advance(delta)
	if _clock.tick >= 0.0:
		_drawn = _clock.tick - _clock.gap - DRAW_MARGIN
	_cards.begin()
	if _epoch != _cards.epoch:
		_epoch = _cards.epoch
		_wait()
		_known.clear()
		_rewrite = true
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_wait()
	if _task < 0 and not _height_known:
		_find_height()
	if _task < 0 and (not _inbox.is_empty() or _rewrite):
		_start(delta)
	_cards.set_glide(_progress())
	var spent := Time.get_ticks_usec() - start
	stats["frames"] += 1
	stats["main_usec"] += spent
	if _bench:
		_bench_usec += spent
		_bench_report(delta)


func _on_entities_changed(c: Vector2i) -> void:
	_belt_dirty[c] = true


## A chunk's entity records (WorldMirror.Rec) given directly, without world.gd (tests, probes).
func index_chunk(c: Vector2i, recs: Array, whole := true) -> void:
	_given.append([c, recs, whole])


## Chunks a job indexes at most: the first square on a busy base is 64 chunks, about 50 us each to
## hand over here; the rest follow with the next updates (items there glide straight meanwhile).
const INDEX_PER_JOB := 12


## The chunks round the square the items come from, for the job to index (new to it, or changed
## since: world.gd's entities_changed) or drop (gone from it).
func _index_belts(job: Job) -> void:
	if protos == null:
		return
	if protos.entities.size() != _kinds_count:
		_kinds_count = protos.entities.size()
		var kinds := {}
		for id in protos.entities:
			var t: int = BeltPaths.TYPES.get((protos.entities[id] as ProtoDB.EntityProto).type, -1)
			if t >= 0:
				kinds[id] = t
		job.kinds = kinds
		for c in _indexed:
			_belt_dirty[c] = true
	job.index.append_array(_given)
	_given.clear()
	if world == null:
		return
	var sq := _square
	for i in range(job.msgs.size() - 1, -1, -1):
		var m: Dictionary = job.msgs[i]
		if m.has("fr"):
			sq = Vector3(int(m.get("fx", 0)) / 256.0, int(m.get("fy", 0)) / 256.0, int(m.get("fr", 0)))
			break
	if sq.z < 0.0:
		return
	var r := sq.z + INDEX_MARGIN
	var lo := WorldMirror.chunk_of(Vector2(sq.x - r, sq.y - r))
	var hi := WorldMirror.chunk_of(Vector2(sq.x + r, sq.y + r))
	for c: Vector2i in _indexed.keys():
		if c.x < lo.x or c.x > hi.x or c.y < lo.y or c.y > hi.y or not world.chunks.has(c):
			job.drops.append(c)
			_indexed.erase(c)
	var todo: Array = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			var c := Vector2i(x, y)
			var cv = world.chunks.get(c)
			if cv == null:
				continue
			var whole: bool = cv.parts_expected >= 0 and not cv.is_incomplete()
			if not _indexed.has(c) or _indexed[c] != whole or _belt_dirty.has(c):
				todo.append([c, whole])
	if todo.size() > INDEX_PER_JOB:
		var mid := WorldMirror.chunk_of(Vector2(sq.x, sq.y))
		todo.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] - mid).length_squared() < (b[0] - mid).length_squared())
		todo.resize(INDEX_PER_JOB)
	for e: Array in todo:
		var c: Vector2i = e[0]
		job.index.append([c, world.chunks[c].entities.values(), e[1]])
		_indexed[c] = e[1]
		_belt_dirty.erase(c)


## Items ride just above the belt surface: the top of the belt model, which differs between the
## procedural belt and the one converted from Wube's printable model. Asked for, not made here: the
## model is read on a worker thread (making it at start-up cost 5-15 ms on the main thread), and
## each update places its items at the height known then.
func _find_height() -> void:
	if not ModelLibrary.ready("transport-belt"):
		return
	_height_known = true
	var belt := ModelLibrary.mesh_for("transport-belt")
	if belt != null:
		_state.height = belt.get_aabb().end.y + 0.02


func _start(delta: float) -> void:
	var job := Job.new()
	job.state = _state
	job.msgs = _inbox
	_inbox = []
	job.full = _rewrite
	_rewrite = false
	job.known = _known.duplicate()
	job.watch = _watch.keys()
	_watch.clear()
	if lanes != null and is_instance_valid(lanes) and lanes.distance > 0:
		job.far_built = lanes.built_chunks()
	_index_belts(job)
	# Where the glide will be when this job's result is drawn: about a frame from now (now when the
	# job runs here and is drawn this frame).
	job.fold_tick = _drawn + (0.0 if _sync else delta * _clock.rate)
	job.fold = _progress_at(job.fold_tick)
	_job = job
	if _sync:
		job.run()
		_apply(job)
		_job = null
	else:
		_task = WorkerThreadPool.add_task(job.run, false, "belt items")


## A finished job's buffers to the MultiMeshes; kinds whose looks weren't made yet are made now
## and written by the next job.
func _apply(job: Job) -> void:
	for w: Array in job.written:
		_cards.put(int(w[0]), w[1], int(w[2]), int(w[3]))
	for item_id in job.unknown:
		_cards.prepare(item_id)
		_known[item_id] = [_cards.lift(item_id), _cards.turns(item_id), _cards.pile_step(item_id)]
	_rewrite = _rewrite or not job.unknown.is_empty()
	_count = job.count
	_square = job.square
	if lanes != null and is_instance_valid(lanes):
		# The icons change in this frame too: the square they leave out, the chunks still held by
		# items waiting for them, and the kinds not drawn yet (their icons stay shown).
		lanes.hand_over(job.square, job.held_chunks, job.unknown)
	_positions = job.positions
	if job.paths != null:
		_paths_image = job.paths
		if _paths == null or _paths.get_width() != job.paths.get_width() or _paths.get_height() != job.paths.get_height():
			_paths = ImageTexture.create_from_image(job.paths)
			_cards.set_paths(_paths)
		else:
			_paths.update(job.paths)
	stats["jobs"] += 1
	stats["worker_usec"] += job.usec
	stats["indexed"] += job.index.size()
	stats["index_usec"] += job.index_usec
	stats["write_usec"] += job.write_usec
	var routed := 0
	for k in 5:
		routed += job.routes[k]
	stats["cached"] += job.updated - routed - job.fresh
	stats["fresh"] += job.fresh
	stats["route_usec"] += job.route_usec
	stats["fold_usec"] += job.fold_usec
	stats["runs"] = _state.graph.runs
	stats["walks"] = Array(_state.graph.walks)
	stats["missing"] += job.missing
	stats["held"] += job.held
	stats["worst_job_usec"] = maxi(stats["worst_job_usec"], job.usec)
	for k in 5:
		stats["routes"][k] += job.routes[k]
	_bench_worker_usec += job.usec
	_bench_jobs += 1
	if job.began:
		# The glide reaches the newest update's place when the drawn clock reaches its tick.
		_from_tick = minf(job.fold_tick, job.last_tick - 1.0)
		_to_tick = job.last_tick


## Where an item (by unique id) is drawn now, or null (quality_marks.gd puts its quality there;
## under the ground it isn't drawn). Asked for once, it is known from the next update on.
func position_of(uid: int) -> Variant:
	_watch[uid] = true
	var p: Array = _positions.get(uid, [])
	if p.is_empty():
		return null
	var path: PackedFloat32Array = p[2]
	if path.is_empty():
		return (p[0] as Vector3) + (p[1] as Vector3) * _progress()
	var o := BeltPaths.path_at(path, _progress())
	if o.w < 0.5:
		return null
	return (p[0] as Vector3) + Vector3(o.x, o.y, o.z)


## How far items are along their glide from the last update to the next, 0 to 1.
func _progress() -> float:
	return _progress_at(_drawn)


func _progress_at(drawn: float) -> float:
	return clampf((drawn - _from_tick) / (_to_tick - _from_tick), 0.0, 1.0)


func _bench_report(delta: float) -> void:
	_bench_frames += 1
	_bench_time += delta
	_bench_worst = maxf(_bench_worst, delta)
	if _bench_time < 5.0:
		return
	var vp := get_viewport().get_viewport_rid()
	print("item-bench: %d items, %d kinds, frame %.2f ms avg, %.2f ms worst, %.0f FPS, belt items %.2f ms/frame, worker %.2f ms/job (%d jobs), render cpu %.2f ms, gpu %.2f ms" % [
		_count, _cards.kind_count(), _bench_time * 1000.0 / _bench_frames, _bench_worst * 1000.0,
		_bench_frames / _bench_time, _bench_usec / 1000.0 / _bench_frames,
		_bench_worker_usec / 1000.0 / maxi(_bench_jobs, 1), _bench_jobs,
		RenderingServer.viewport_get_measured_render_time_cpu(vp), RenderingServer.viewport_get_measured_render_time_gpu(vp)])
	_bench_frames = 0
	_bench_time = 0.0
	_bench_worst = 0.0
	_bench_usec = 0
	_bench_worker_usec = 0
	_bench_jobs = 0
