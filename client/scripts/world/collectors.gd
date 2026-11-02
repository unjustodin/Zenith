extends Node3D
## Asteroid collectors' arms as Factorio moves them (F3): each arm's grabber head flies straight
## at an asteroid chunk in the collector's catch circle at the arm's speed, closes on it, and is
## pulled back in with it; the chain of links strings out behind the head, bending from the
## intake towards it.
##
## 2.1.23 shows scripts nothing of the arms (collectors.lua), so the head's target is picked here
## as Factorio does from the chunks the mod sends (`ach`, ui_model.asteroid_chunks): one its
## filters take inside the circle (collection_radius 7.5 round a point 5 tiles in front), the
## nearest; the head reaches it after distance / speed, which is when the game takes the chunk
## (measured: 0.2 tiles a tick from the collector, back to 1.5 tiles from its centre). The mod's
## `acol` gives each collector's arms, speed, filters and whether its arms move, and `g` the
## chunks really caught: an arm that went for another one turns to the caught one at double
## speed, so the picture never disagrees with the game for long.
##
## anim.gd hands every part of the model's arm (anim_reach_collector_*: head, two fingers, 24
## links) to part_transform() each frame. Collectors of better quality have more arms: the first
## is the model's own parts, the others are drawn here with the same meshes.

const ModelLibrary := preload("res://scripts/world/model_library.gd")

const CATCH_RADIUS := 7.5
const CATCH_OFFSET := 5.0
const HEAD_RADIUS := 0.6     # the head grabs a chunk this close (head_collection_radius)
const DEPOSIT := 1.5         # the chunk drops into the collector this close to its centre
const DEFAULT_SPEED := 0.2   # tiles a tick, arm_speed_base
const CATCH_UP := 2.0        # how much faster an arm turns to a chunk the game says it caught
const CHUNK_HEIGHT := 0.6    # rockets.gd draws the chunks this high
const CHUNK_SCALE := 0.45
## Where the head rests and the links are stowed in the model (tools/models/space_platform.py
## HEAD_REST, LINK_REST in Blender's x, y, z).
const HEAD_REST := Vector3(0.02, 1.15, -1.5)
const LINK_PITCH := 0.45     # a link's length along the chain
const LINK_STRETCH := 1.6    # links stretch this much at most before gaps open between them
const LINKS := 24
const LINK_PREFIX := "reach_collector_link_"
const CLAW_OPEN := 0.75      # radians each finger turns out, fully open
const RELEASE_AFTER := 0.5   # seconds a chunk may stay listed after its grab before it counts as missed

enum { IDLE, REACH, BACK }


class Arm:
	var state := IDLE
	var head := Vector3.ZERO      # world
	var target = null             # the chunk (ui_model.asteroid_chunks entry) it reaches for
	var fixed_at := Vector2.INF   # a caught chunk's place from `g` it turns to, else INF
	var fixed_name := ""
	var carry := ""               # the chunk's name while it holds one
	var carry_at := 0.0           # _time it grabbed it
	var carry_from := Vector2.ZERO  # where, and how the chunk was moving (to find it in later lists)
	var carry_vel := Vector2.ZERO
	var open := 0.0               # fingers, 0 closed to 1 open
	var tangent := Vector3.FORWARD  # the head's heading, world


class Collector:
	var unit := 0
	var arms := 1
	var speed := DEFAULT_SPEED * 60.0  # tiles a second
	var moving := true
	var folded := false            # switched off: the arms go home and stay there
	var filters: Array = []
	var known := false             # an `acol` row arrived for it
	var base := Transform3D.IDENTITY
	var frame := -1                # the frame it was last stepped in
	var list: Array = []           # Arm
	var held: Array = []           # MeshInstance3D per arm: the chunk it holds


var model   # ui_model.gd: asteroid_chunks
var world   # world.gd: working states, for collectors no `acol` has described yet

var _collectors := {}  # unit -> Collector
var _time := 0.0
var _chunk_meshes := {}  # chunk name -> Mesh
## Extra arms (quality collectors): part kind -> {"mm": MultiMesh, "xf": [Transform3D], "custom": [Color]}
var _extra := {}
var _extra_frame := -1
var _last_list_msec := 0  # when the chunk list before this one arrived


func _ready() -> void:
	if model != null and model.has_signal("asteroid_chunks_changed"):
		model.asteroid_chunks_changed.connect(_on_chunks)


func reset() -> void:
	for c: Collector in _collectors.values():
		for h in c.held:
			(h as Node).queue_free()
	_collectors.clear()
	for e in _extra.values():
		(e["mm"] as MultiMesh).visible_instance_count = 0


## `acol`: the collectors' arms, speeds, filters and whether they move (`l`); chunks caught (`g`).
func handle(msg: Dictionary) -> void:
	if msg.has("l"):
		var seen := {}
		for r in _array(msg.get("l")):
			if not (r is Array and r.size() >= 5):
				continue
			var c := _collector(int(r[0]))
			c.arms = maxi(1, int(r[1]))
			c.speed = int(r[2]) / 1000.0 * 60.0
			c.moving = int(r[3]) == 1
			c.folded = int(r[3]) == 2
			c.filters = _array(r[4]).map(func(f) -> String: return str(f))
			c.known = true
			seen[c.unit] = true
		for unit in _collectors.keys():
			if not seen.has(unit) and (_collectors[unit] as Collector).known:
				_forget(unit)
	for g in _array(msg.get("g")):
		if g is Array and g.size() >= 4:
			_caught(int(g[0]), str(g[1]), Vector2(int(g[2]), int(g[3])) / 256.0)


## A part of a collector's arm, turned to where the first arm has it now (model space, after
## `base`). The first call for a collector in a frame moves its arms on.
func part_transform(unit: int, part: ModelLibrary.AnimPart, base: Transform3D, delta: float, custom := Color(0, 0, 0, 1)) -> Transform3D:
	var c := _collector(unit)
	c.base = base
	var frame := Engine.get_process_frames()
	if c.frame != frame:
		c.frame = frame
		_step(c, delta)
	if frame != _extra_frame:
		_flush_extra()
		_extra_frame = frame
	for i in range(1, mini(c.arms, c.list.size())):
		_queue_extra(part, base * _arm_transform(c, c.list[i], part), custom)
	return _arm_transform(c, c.list[0], part)


## Moves a collector's arms on by `delta` seconds (part_transform does this once a frame).
func advance(unit: int, base: Transform3D, delta: float) -> void:
	var c := _collector(unit)
	c.base = base
	c.frame = Engine.get_process_frames()
	_step(c, delta)


## Where an arm's head is (world), for tests and looking at.
func head_of(unit: int, arm := 0) -> Vector3:
	var c: Collector = _collectors.get(unit)
	return (c.list[arm] as Arm).head if c != null and arm < c.list.size() else Vector3.INF


## An arm's state: "idle", "reach" or "back", and what it holds ("" for nothing).
func arm_state(unit: int, arm := 0) -> Array:
	var c: Collector = _collectors.get(unit)
	if c == null or arm >= c.list.size():
		return ["", ""]
	var a: Arm = c.list[arm]
	return [["idle", "reach", "back"][a.state], a.carry]


func _process(delta: float) -> void:
	_time += delta
	# Extra arms of collectors anim.gd stopped handing over (out of range) aren't drawn stale.
	if Engine.get_process_frames() - _extra_frame > 2:
		_flush_extra()


# --- arms -------------------------------------------------------------------------------------

func _collector(unit: int) -> Collector:
	var c: Collector = _collectors.get(unit)
	if c == null:
		c = Collector.new()
		c.unit = unit
		_collectors[unit] = c
	return c


func _forget(unit: int) -> void:
	var c: Collector = _collectors.get(unit)
	if c == null:
		return
	for a: Arm in c.list:
		_unhold(a)
	for h in c.held:
		(h as Node).queue_free()
	_collectors.erase(unit)


func _rest(c: Collector) -> Vector3:
	return c.base * HEAD_REST


func _forward(c: Collector) -> Vector3:
	return (c.base.basis * Vector3.FORWARD).normalized()


func _step(c: Collector, delta: float) -> void:
	var rest := _rest(c)
	while c.list.size() < c.arms:
		var a := Arm.new()
		a.head = rest
		a.tangent = _forward(c)
		c.list.append(a)
	while c.held.size() < c.list.size():
		var mi := MeshInstance3D.new()
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		c.held.append(mi)
	var moving := c.moving if c.known else (world != null and int(world.working.get(c.unit, 0)) == 1)
	var step := c.speed * delta
	for i in c.list.size():
		var a: Arm = c.list[i]
		if i >= c.arms:
			a.head = rest
			a.state = IDLE
			continue
		if c.folded and c.known and a.state == REACH:
			a.state = BACK  # turned off on its way out: back home empty
			a.target = null
		if moving and a.state == IDLE:
			_pick(c, a)
		# Switched off, an arm on its way home still gets there; it picks nothing new.
		if moving or (c.folded and c.known and a.state == BACK):
			match a.state:
				REACH:
					var goal := _goal(a)
					var fast := step * (CATCH_UP if a.fixed_at != Vector2.INF else 1.0)
					a.head = a.head.move_toward(goal, fast)
					if a.head.distance_to(goal) <= HEAD_RADIUS * 0.5 or (a.fixed_at == Vector2.INF and a.head.distance_to(goal) <= HEAD_RADIUS):
						_grab(a, goal)
				BACK:
					a.head = a.head.move_toward(rest, step)
					if a.head.distance_to(rest) < 0.01:
						a.state = IDLE
						a.carry = ""
		a.open = move_toward(a.open, 1.0 if a.state == REACH else 0.0, delta * (3.0 if a.state == REACH else 6.0))
		var held: MeshInstance3D = c.held[i]
		held.visible = a.carry != ""
		if held.visible:
			held.mesh = _chunk_mesh(a.carry)
			var spin := Basis(Vector3(0.3, 1, 0.2).normalized(), _time * 0.8 + i)
			held.global_transform = Transform3D(spin.scaled(Vector3.ONE * CHUNK_SCALE), a.head + a.tangent * 0.35)


## The nearest chunk the collector's filters take in its catch circle that no arm has yet.
func _pick(c: Collector, a: Arm) -> void:
	if model == null:
		return
	var centre3 := c.base * Vector3(0.0, 0.0, -CATCH_OFFSET)
	var centre := Vector2(centre3.x, centre3.z)
	var rest := _rest(c)
	var dt := _since_chunks()
	var best = null
	var best_d := INF
	for ch in model.asteroid_chunks:
		if ch.get("held", false) or ch.get("claimed", false):
			continue
		if not c.filters.is_empty() and not c.filters.has(str(ch["name"])):
			continue
		var p: Vector2 = ch["position"] + ch["velocity"] * dt
		if p.distance_to(centre) > CATCH_RADIUS:
			continue
		var d := Vector2(rest.x, rest.z).distance_to(p)
		if d < best_d:
			best_d = d
			best = ch
	if best != null:
		best["claimed"] = true
		a.target = best
		a.fixed_at = Vector2.INF
		a.state = REACH


func _goal(a: Arm) -> Vector3:
	if a.fixed_at != Vector2.INF:
		return Vector3(a.fixed_at.x, CHUNK_HEIGHT, a.fixed_at.y)
	var p: Vector2 = a.target["position"] + a.target["velocity"] * _since_chunks()
	return Vector3(p.x, CHUNK_HEIGHT, p.y)


func _grab(a: Arm, at: Vector3) -> void:
	if a.fixed_at != Vector2.INF:
		a.carry = a.fixed_name
		a.carry_vel = Vector2.ZERO
	else:
		a.carry = str(a.target["name"])
		a.carry_vel = a.target["velocity"]
		a.target["held"] = true
	a.carry_from = Vector2(at.x, at.z)
	a.carry_at = _time
	a.target = null
	a.fixed_at = Vector2.INF
	a.state = BACK


func _unhold(a: Arm) -> void:
	if a.target != null:
		a.target.erase("claimed")
	a.target = null


## `g`: the game took chunk `name` at `at` for this collector. An arm already there (holding it or
## about to) carries on; otherwise the nearest free arm turns to it.
func _caught(unit: int, name: String, at: Vector2) -> void:
	var c: Collector = _collectors.get(unit)
	if c == null or c.list.is_empty():
		return
	for a: Arm in c.list:
		if a.state == BACK and a.carry == name and a.carry_from.distance_to(at) < 2.0 + a.carry_vel.length() * (_time - a.carry_at):
			return
		if a.state == REACH and a.fixed_at == Vector2.INF and a.target != null and str(a.target["name"]) == name:
			var p: Vector2 = a.target["position"] + a.target["velocity"] * _since_chunks()
			if p.distance_to(at) < 2.0:
				return
	var best: Arm = null
	for a: Arm in c.list:
		if a.state == IDLE or (a.state == REACH and a.fixed_at == Vector2.INF):
			if best == null or a.head.distance_to(Vector3(at.x, CHUNK_HEIGHT, at.y)) < best.head.distance_to(Vector3(at.x, CHUNK_HEIGHT, at.y)):
				best = a
	if best == null:
		return
	_unhold(best)
	best.fixed_at = at
	best.fixed_name = name
	best.state = REACH
	# The chunk itself is gone from the game, so it is drawn in the open claw until it closes.
	_hide_near(name, at)


func _hide_near(name: String, at: Vector2) -> void:
	if model == null:
		return
	var dt := _since_chunks()
	for ch in model.asteroid_chunks:
		if str(ch["name"]) == name and (ch["position"] + ch["velocity"] * dt).distance_to(at) < 1.0:
			ch["held"] = true


## A new chunk list: arms keep their chunks (found where they drifted to); a chunk an arm went for
## that is gone was caught (by this arm if its head was close) or is lost; one held too long while
## still listed wasn't caught after all.
func _on_chunks() -> void:
	var list: Array = model.asteroid_chunks
	var msec := int(model.asteroid_chunks_msec)
	var gap := (msec - _last_list_msec) / 1000.0 if _last_list_msec > 0 else 0.0
	_last_list_msec = msec
	for c: Collector in _collectors.values():
		for a: Arm in c.list:
			if a.state == REACH and a.fixed_at == Vector2.INF and a.target != null:
				var p: Vector2 = a.target["position"] + a.target["velocity"] * gap
				var found = _find(list, str(a.target["name"]), p, 0.5)
				if found != null:
					found["claimed"] = true
					a.target = found
				elif a.head.distance_to(Vector3(p.x, CHUNK_HEIGHT, p.y)) < 3.0:
					a.fixed_at = p
					a.fixed_name = str(a.target["name"])
					a.target = null
				else:
					a.target = null
					a.state = BACK
			elif a.state == BACK and a.carry != "" and a.carry_vel != Vector2.ZERO:
				var at := a.carry_from + a.carry_vel * (_time - a.carry_at)
				for ch in list:
					if str(ch["name"]) == a.carry and ch["position"].distance_to(at) < 0.5:
						if _time - a.carry_at > RELEASE_AFTER:
							a.carry = ""  # still floating there: the game didn't take it
						else:
							ch["held"] = true
						break


## The entry of `list` that is chunk `name` drifted on to `at`, or null.
static func _find(list: Array, name: String, at: Vector2, within: float):
	for ch in list:
		if str(ch["name"]) == name and (ch["position"] as Vector2).distance_to(at) < within:
			return ch
	return null


func _since_chunks() -> float:
	if model == null:
		return 0.0
	return (Time.get_ticks_msec() - int(model.asteroid_chunks_msec)) / 1000.0


# --- drawing ----------------------------------------------------------------------------------

## The part's transform for arm `a` (model space).
func _arm_transform(c: Collector, a: Arm, part: ModelLibrary.AnimPart) -> Transform3D:
	var inv := c.base.affine_inverse()
	var head := inv * a.head
	var rest := HEAD_REST
	var span := head - rest
	var length := span.length()
	var fwd := Vector3.FORWARD
	var tangent := fwd
	var c1 := rest + fwd * length * 0.35
	var c2 := head
	if length > 0.05:
		c2 = head - span.normalized() * length * 0.25
		tangent = (head - c2).normalized()
		if tangent.length() < 0.5:
			tangent = span.normalized()
	a.tangent = (c.base.basis * tangent).normalized()
	var kind := part.kind
	if kind == "reach_collector_head":
		if length < 0.01:
			return Transform3D.IDENTITY
		return Transform3D(_facing(tangent), head) * part.pivot.affine_inverse()
	if kind.begins_with("reach_collector_claw_"):
		var side := 1.0 if kind.ends_with("_l") else -1.0
		var offset := part.pivot.origin - HEAD_REST
		var turn := Transform3D(Basis(Vector3.UP, side * a.open * CLAW_OPEN), offset)
		var pivot_inv := part.pivot.affine_inverse()
		if length < 0.01 and a.open == 0.0:
			return Transform3D.IDENTITY
		return Transform3D(_facing(tangent), head) * turn * pivot_inv
	if kind.begins_with(LINK_PREFIX):
		var index := kind.unicode_at(kind.length() - 1) - "a".unicode_at(0)
		var pitch := LINK_PITCH
		if length > LINKS * LINK_PITCH:
			pitch = length / LINKS
		var shown := mini(LINKS, int(ceil(length / pitch)))
		if index >= shown or length < 0.3:
			return Transform3D.IDENTITY
		# Link 0 sits just behind the head, the others along the curve back to the intake.
		var t := clampf(1.0 - (index + 0.5) * pitch / length, 0.0, 1.0)
		var at := _bezier(rest, c1, c2, head, t)
		var dir := _bezier_tangent(rest, c1, c2, head, t)
		var stretch := clampf(pitch / LINK_PITCH, 1.0, LINK_STRETCH)
		var basis := _facing(dir) * Basis.from_scale(Vector3(1.0, 1.0, stretch))
		return Transform3D(basis, at) * part.pivot.affine_inverse()
	return Transform3D.IDENTITY


static func _facing(dir: Vector3) -> Basis:
	if dir.length() < 0.001:
		return Basis.IDENTITY
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.BACK
	return Basis.looking_at(d, up)


static func _bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t


static func _bezier_tangent(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	var d := (p1 - p0) * 3.0 * u * u + (p2 - p1) * 6.0 * u * t + (p3 - p2) * 3.0 * t * t
	return d if d.length() > 0.0001 else p3 - p0


func _chunk_mesh(name: String) -> Mesh:
	if _chunk_meshes.has(name):
		return _chunk_meshes[name]
	var mesh := ModelLibrary.mesh_for("small-%s-asteroid" % name.trim_suffix("-asteroid-chunk"))
	if mesh == null:
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 0.9
		mesh = s
	_chunk_meshes[name] = mesh
	return mesh


func _queue_extra(part: ModelLibrary.AnimPart, xf: Transform3D, custom: Color) -> void:
	var e: Dictionary = _extra.get(part.kind, {})
	if e.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = part.mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)
		e = {"mm": mm, "xf": [], "custom": []}
		_extra[part.kind] = e
	e["xf"].append(xf)
	e["custom"].append(custom)


func _flush_extra() -> void:
	for e in _extra.values():
		var mm: MultiMesh = e["mm"]
		var xf: Array = e["xf"]
		if mm.instance_count < xf.size():
			mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
			mm.set_instance_custom_data(i, e["custom"][i])
		mm.visible_instance_count = xf.size()
		xf.clear()
		(e["custom"] as Array).clear()


static func _array(v) -> Array:
	return v if v is Array else []
