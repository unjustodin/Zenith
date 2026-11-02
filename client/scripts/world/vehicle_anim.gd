extends Node
## Vehicles' and robots' own animations, as Factorio draws them, on the movers' nodes (movers.gd
## makes a MeshInstance3D per moving part, `anim_<kind>` in the model, at rest in model space;
## this sets their transforms and glow every frame). Wheels, tracks' road wheels and turrets are
## moved by movers.gd and turrets.gd; this does the rest:
##
## - spidertron: each leg is an upper and a lower part stretched between hip, knee and foot as
##   Factorio stretches its leg sprites (knee 40% of the way out, as high over the higher of
##   hip and foot as the model has it over its hip). The feet stand where the mod says its
##   spider-leg entities stand (`legs`); a foot that moves steps there in an arc. Without the
##   mod's feet (an older mod, the mock) the legs step by themselves: Factorio's two walking
##   groups in turn, each foot back to its ground_position when it strays. The shell turns
##   with the torso's aim (turrets.gd) and the body bobs, more while it walks. Gleba's strafers
##   and stompers (pentapods) walk the same way on their five legs, each with its own
##   prototype's leg table, knee and step size;
## - logistic robots swing their legs (the thrusters) back and light their tips while they fly,
##   and show the antenna's red ball while they carry cargo (`rc`), white without; construction
##   robots hovering in one place are working: their nozzle light flickers on Factorio's two
##   working frames, the arms reach forward and Factorio's sparks fly; all robots bob a little;
## - capture robots sway their hanging cables on the capture animation's 128-tick loop, the tips
##   pulsing;
## - cargo pods open high in the sky (antenna up, then three panels out, pod-opening.png) and
##   close before they come down; their thruster burns while rockets.gd moves them up or down;
## - the tank's treads slide forward by the distance driven.
## Every mover's glowing materials are lit here (f3d_glow), since a single MeshInstance3D has no
## INSTANCE_CUSTOM to carry the buildings' working glow.

const ModelLibrary := preload("res://scripts/world/model_library.gd")

## Factorio's spidertron legs (spider_engine.legs, base/prototypes/entity/spidertron.lua, from
## `factorio --dump-data`), in the order the mod sends their feet: mount position, ground
## position (x east, y south, tiles) and walking group.
const SPIDER_LEGS := [
	[Vector2(0.46875, -0.6875), Vector2(2.25, -2.5), 1], [Vector2(0.71875, -0.3125), Vector2(3.0, -1.0), 2],
	[Vector2(0.78125, 0.125), Vector2(3.0, 1.0), 1], [Vector2(0.46875, 0.53125), Vector2(2.25, 2.5), 2],
	[Vector2(-0.46875, -0.6875), Vector2(-2.25, -2.5), 2], [Vector2(-0.71875, -0.3125), Vector2(-3.0, -1.0), 1],
	[Vector2(-0.78125, 0.125), Vector2(-3.0, 1.0), 2], [Vector2(-0.46875, 0.53125), Vector2(-2.25, 2.5), 1],
]
const KNEE_AT := 0.4  # spider-leg knee_distance_factor
## Pentapods' spider_engine.legs, big tiers (`factorio --dump-data`; gleba.py builds the same):
## mount and ground position (x east, y south) and walking group, in the order the mod sends
## their feet. The small and medium tiers are these scaled (PENTAPOD_TIERS).
const STOMPER_LEGS := [
	[Vector2(-1.0345, -1.4239), Vector2(-6.5832, -9.061), 1], [Vector2(-1.6739, 0.5439), Vector2(-10.6518, 3.461), 3],
	[Vector2(0.0, 1.76), Vector2(0.0, 11.2), 5], [Vector2(1.6739, 0.5439), Vector2(10.6518, 3.461), 2],
	[Vector2(1.0345, -1.4239), Vector2(6.5832, -9.061), 4],
]
const STRAFER_LEGS := [
	[Vector2(-0.3236, -0.2351), Vector2(-6.4721, -4.7023), 1], [Vector2(-0.3236, 0.2351), Vector2(-6.4721, 4.7023), 3],
	[Vector2(0.1236, 0.3804), Vector2(2.4721, 7.6085), 5], [Vector2(0.4, 0.0), Vector2(8.0, 0.0), 2],
	[Vector2(0.1236, -0.3804), Vector2(2.4721, -7.6085), 4],
]
const PENTAPOD_TIERS := {"small": 0.5625, "medium": 0.75, "big": 1.0}
## kind -> [legs, the legs' knee_distance_factor, their minimal_step_size (big tier)]
const LEG_TABLES := {"spidertron": [SPIDER_LEGS, KNEE_AT, 1.0], "stomper": [STOMPER_LEGS, 0.55, 1.76],
	"strafer": [STRAFER_LEGS, 0.5, 1.6]}
## Steps: how high a foot lifts, its speed (Factorio's legs accelerate from 0.06 to well over
## a tile a tick; a step of a tile or two takes about a fifth of a second), and when a foot
## steps by itself: more than minimal_step_size from where it should stand while walking, or
## a quarter of that standing still.
const STEP_LIFT := 0.7  # at the spidertron's size; bigger legs lift higher and step faster
const STEP_SPEED := 9.0
const STEP_MIN_TIME := 0.12
const STEP_TRIGGER := 1.0
const STEP_TIDY := 0.25
const STEP_LEAD := 0.35  # seconds of the body's motion a foot steps ahead
const FEET_STALE := 0.5  # seconds without the mod's feet before the legs step by themselves
## The torso's bob: tiles up and down, standing and walking, and how fast standing.
const BOB_IDLE := 0.04
const BOB_WALK := 0.1
const BOB_RATE := 0.5
## Robots.
const ROBOT_BOB := 0.035
const ROBOT_BOB_RATE := 0.7
const THRUSTER_SWING := -0.5  # radians the legs swing back at full speed
const ROBOT_FULL_SPEED := 2.5  # tiles a second counted as flying flat out
const WORK_STILL := 0.3  # seconds a construction robot hovers in place before it works
const WORK_FRAME := 1.0 / (0.3 * 60.0)  # working animation: 2 frames at 0.3 a tick
const ARMS_REACH := 0.6
const SPARK_EVERY := 0.25
## Capture robots: capture_animation, 32 frames at 0.25 a tick.
const CAPTURE_LOOP := 32.0 / 0.25 / 60.0
const CABLE_SWAY := 0.07
## Cargo pods: open above this height, in this long (pod-opening, 34 frames), flame when moving
## up or down faster than this (tiles a second).
const POD_OPEN_HEIGHT := 18.0
const POD_OPEN_TIME := 34.0 / 30.0
const POD_ANTENNA_RISE := 0.3
const POD_THRUST_SPEED := 0.5
## The tank's treads: their spacing along the track (military.py track(), stretched with the hull).
const TREAD_SPACING := {"tank": (1.38 + 1.42 - 0.08) / 25.0 * 1.071}

const RIG_KINDS := {"spidertron": "spider", "logistic-robot": "logistic", "construction-robot": "construction",
	"capture-robot": "capture", "cargo-pod": "pod", "tank": "tracks"}


class Leg:
	var upper: MeshInstance3D
	var lower: MeshInstance3D
	var hip0 := Vector3.ZERO  # at rest, in the node's space
	var knee0 := Vector3.ZERO
	var foot0 := Vector3.ZERO
	var rest := Vector3.ZERO  # where the foot stands (node space) when the spider is still
	var group := 1
	var knee_rise := 1.25  # the model's knee over its hip at rest
	var foot := Vector3.ZERO  # drawn, world space (y is the lift)
	var from := Vector3.ZERO  # a step's start and end, world space on the ground
	var to := Vector3.ZERO
	var step := -1.0  # progress 0 to 1, or -1 when planted


class Rig:
	var kind := ""
	var unit := 0
	var node: Node3D
	var body: MeshInstance3D
	var parts := {}  # part kind -> [[MeshInstance3D, AnimPart], ...]
	var meshes: Array[MeshInstance3D] = []
	var last := Vector3.ZERO
	var velocity := Vector3.ZERO  # smoothed, tiles a second
	var phase := 0.0
	var still := 0.0  # seconds hovering in place
	var amount := 0.0  # robots: flying (0-1); pods: open (0-1)
	var travelled := 0.0
	var spark := 0.0
	var legs: Array[Leg] = []
	var feet_seen := -INF  # when the mod's feet last came for this spider
	var stepping_group := 0
	var placed := false
	var knee_at := KNEE_AT
	var step_size := STEP_TRIGGER  # minimal_step_size
	var size := 1.0  # the legs' reach against the spidertron's


## ui_model.gd (legs, robot_cargo), turrets.gd (the spidertron's torso), sprite_fx.gd (sparks):
## main.gd sets them.
var model
var turrets: Node
var sprites: Node

var _rigs := {}  # unit -> Rig
var _time := 0.0
var _feet_at := {}  # unit -> time the mod's feet for it last came
## The last frame's _process time, microseconds (--robot-probe).
var process_usec := 0


func _ready() -> void:
	# After rockets.gd has lifted the cargo pods this frame, so their climb shows here.
	process_priority = 10


## A new mover's node (movers.gd): lights its glowing materials, and rigs it if it animates.
func attach(unit: int, node: Node3D, proto_name: String) -> void:
	var rig := Rig.new()
	rig.unit = unit
	rig.node = node
	rig.kind = RIG_KINDS.get(proto_name, "")
	rig.last = node.position
	rig.phase = float(posmod(unit * 7919, 1000)) / 1000.0 * TAU
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		rig.meshes.append(mi)
		mi.set_instance_shader_parameter("f3d_glow", 1.0)
		if child.has_meta("part"):
			var part: ModelLibrary.AnimPart = child.get_meta("part")
			var list: Array = rig.parts.get(part.kind, [])
			list.append([mi, part])
			rig.parts[part.kind] = list
		else:
			rig.body = mi
	if proto_name == "rocket-silo-rocket":
		# Its engines glow only once they start (rockets.gd lights the launching one).
		for mi in rig.meshes:
			mi.set_instance_shader_parameter("f3d_glow", 0.0)
	if rig.kind == "" and proto_name.ends_with("-pentapod") and not proto_name.contains("wriggler"):
		rig.kind = "spider"  # strafers and stompers
	if rig.kind == "":
		return
	if rig.kind == "spider":
		_rig_legs(rig, proto_name)
	_rigs[unit] = rig


func detach(unit: int) -> void:
	_rigs.erase(unit)


func reset() -> void:
	_rigs.clear()
	_feet_at.clear()


func count() -> int:
	return _rigs.size()


func _on_planet_data() -> void:
	if model == null:
		return
	for unit in model.legs:
		_feet_at[int(unit)] = _time


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_animate(delta)
	process_usec = Time.get_ticks_usec() - started


func _animate(delta: float) -> void:
	_time += delta
	if model != null and not model.planet_data_changed.is_connected(_on_planet_data):
		model.planet_data_changed.connect(_on_planet_data)
	if delta <= 0.0:
		return
	for rig: Rig in _rigs.values():
		if not is_instance_valid(rig.node):
			continue
		var moved := rig.node.position - rig.last
		rig.last = rig.node.position
		if moved.length() > 4.0:
			moved = Vector3.ZERO  # a teleport
		rig.velocity = rig.velocity.lerp(moved / delta, 1.0 - exp(-delta * 8.0))
		match rig.kind:
			"spider":
				_spider(rig, delta)
			"logistic", "construction":
				_robot(rig, delta)
			"capture":
				_capture(rig, delta)
			"pod":
				_pod(rig, delta)
			"tracks":
				_tracks(rig, moved)


# --- spidertron --------------------------------------------------------------------------------

## Pairs each upper leg with its lower one and with Factorio's leg of the same mount (the
## spidertron's, or a pentapod's at its tier's scale).
func _rig_legs(rig: Rig, proto_name: String) -> void:
	var table: Array = LEG_TABLES["spidertron"]
	var scale := 1.0
	for kind in ["stomper", "strafer"]:
		if proto_name.contains(kind):
			table = LEG_TABLES[kind]
			scale = float(PENTAPOD_TIERS.get(proto_name.get_slice("-", 0), 1.0))
	var legs: Array = table[0]
	rig.knee_at = float(table[1])
	rig.step_size = float(table[2]) * scale
	var reach := 0.0
	for l in legs:
		reach += (l[1] as Vector2).length() * scale / legs.size()
	rig.size = reach / 2.9  # the spidertron's feet stand about 2.9 tiles out
	var uppers: Array = rig.parts.get("leg_upper", [])
	var lowers: Array = rig.parts.get("leg_lower", [])
	var used := {}
	for pair in uppers:
		var leg := Leg.new()
		leg.upper = pair[0]
		var part: ModelLibrary.AnimPart = pair[1]
		leg.hip0 = part.pivot.origin
		var dir := Vector2(leg.hip0.x, leg.hip0.z).angle()
		var best := -1
		for i in lowers.size():
			var k: Vector3 = (lowers[i][1] as ModelLibrary.AnimPart).pivot.origin
			if not used.has(i) and (best < 0 or _off(Vector2(k.x, k.z).angle(), dir) < _off(_flat_angle(lowers[best][1]), dir)):
				best = i
		if best < 0:
			continue
		used[best] = true
		leg.lower = lowers[best][0]
		leg.knee0 = (lowers[best][1] as ModelLibrary.AnimPart).pivot.origin
		leg.knee_rise = leg.knee0.y - leg.hip0.y
		var index := 0
		for i in legs.size():
			if _off((legs[i][0] as Vector2).angle(), dir) < _off((legs[index][0] as Vector2).angle(), dir):
				index = i
		var g: Vector2 = (legs[index][1] as Vector2) * scale
		leg.foot0 = Vector3(g.x, 0.0, g.y)
		leg.rest = leg.foot0
		leg.group = int(legs[index][2])
		rig.legs.resize(maxi(rig.legs.size(), index + 1))
		rig.legs[index] = leg
	# Legs the model doesn't have (another spider's) are dropped.
	var kept: Array[Leg] = []
	for leg in rig.legs:
		if leg != null:
			kept.append(leg)
	if kept.size() != rig.legs.size():
		rig.legs = kept


static func _off(a: float, b: float) -> float:
	return absf(angle_difference(a, b))


static func _flat_angle(part: ModelLibrary.AnimPart) -> float:
	return Vector2(part.pivot.origin.x, part.pivot.origin.z).angle()


func _spider(rig: Rig, delta: float) -> void:
	if rig.legs.is_empty():
		return
	var speed := Vector2(rig.velocity.x, rig.velocity.z).length()
	var walking := clampf(speed / 2.0, 0.0, 1.0)
	rig.travelled += speed * delta
	# Bob: slow breathing standing still, a bounce per step walking.
	rig.phase += delta * TAU * BOB_RATE
	var bob := lerpf(BOB_IDLE * sin(rig.phase), BOB_WALK * absf(sin(rig.travelled * PI / 1.6)) - BOB_WALK * 0.5, walking)
	bob *= sqrt(rig.size)
	if rig.body != null:
		rig.body.position.y = bob
	for pair in rig.parts.get("torso", []):
		var mi: MeshInstance3D = pair[0]
		var part: ModelLibrary.AnimPart = pair[1]
		var yaw := 0.0
		var st = turrets.call("state_of", rig.unit) if turrets != null else null
		if st != null:
			yaw = wrapf(-float(st.yaw) * TAU - rig.node.rotation.y, -PI, PI)
		mi.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, bob, 0.0)) * part.turned(yaw)
	var xf := rig.node.global_transform
	var mod_feet = model.legs.get(rig.unit) if model != null else null
	var fresh := mod_feet != null and _time - float(_feet_at.get(rig.unit, -INF)) < FEET_STALE \
		and (mod_feet as PackedVector2Array).size() >= rig.legs.size()
	if not rig.placed:
		for leg in rig.legs:
			leg.foot = _ground(xf * leg.rest)
			leg.from = leg.foot
			leg.to = leg.foot
		rig.placed = true
	if fresh:
		var feet: PackedVector2Array = mod_feet
		for i in rig.legs.size():
			var at := Vector3(feet[i].x, 0.0, feet[i].y)
			if at.distance_to(rig.legs[i].to) > 0.05:
				_step_to(rig.legs[i], at)
	else:
		_own_steps(rig, xf)
	var hip_lift := Vector3(0.0, bob, 0.0)
	for leg in rig.legs:
		if leg.step >= 0.0:
			var span := maxf(leg.from.distance_to(leg.to), 0.01)
			var time := maxf(span / (STEP_SPEED * sqrt(rig.size)), STEP_MIN_TIME)
			leg.step = minf(leg.step + delta / time, 1.0)
			leg.foot = leg.from.lerp(leg.to, leg.step)
			leg.foot.y = STEP_LIFT * rig.size * minf(span / (1.5 * rig.size), 1.0) * sin(leg.step * PI)
			if leg.step >= 1.0:
				leg.step = -1.0
				leg.foot = leg.to
		_pose_leg(leg, leg.hip0 + hip_lift, xf.affine_inverse() * leg.foot, rig.knee_at)


## A foot starts (or turns, mid-step, towards) a step to `to`.
func _step_to(leg: Leg, to: Vector3) -> void:
	to = _ground(to)
	if leg.step < 0.0:
		leg.from = leg.foot
		leg.from.y = 0.0
		leg.step = 0.0
	leg.to = to


## Legs stepping by themselves: one walking group at a time, each foot back to its ground
## position (and a little ahead while walking) when it strays too far.
func _own_steps(rig: Rig, xf: Transform3D) -> void:
	for leg in rig.legs:
		if leg.step >= 0.0 and leg.group == rig.stepping_group:
			return  # a group is still mid-step
	var moving := Vector2(rig.velocity.x, rig.velocity.z).length() > 0.1
	var lead := rig.velocity * STEP_LEAD
	lead.y = 0.0
	var trigger := rig.step_size if moving else rig.step_size * STEP_TIDY
	var worst := 0.0
	var group := 0
	for leg in rig.legs:
		var want := xf * leg.rest + lead
		var d := Vector2(want.x - leg.to.x, want.z - leg.to.z).length()
		if d > trigger and d > worst and leg.group != rig.stepping_group:
			worst = d
			group = leg.group
	if group == 0:
		# Only the group that just stepped is out of place: let it go again.
		for leg in rig.legs:
			var want := xf * leg.rest + lead
			if Vector2(want.x - leg.to.x, want.z - leg.to.z).length() > trigger * 1.5:
				group = leg.group
				break
	if group == 0:
		return
	rig.stepping_group = group
	for leg in rig.legs:
		if leg.group == group:
			_step_to(leg, xf * leg.rest + lead)


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


## Bends a leg between its hip and foot (node space): the knee `knee_at` of the way out and as
## high over the higher end as the model's knee stands over its hip; each part stretched along
## its length as Factorio stretches its leg sprites.
static func _pose_leg(leg: Leg, hip: Vector3, foot: Vector3, knee_at: float) -> void:
	var knee := hip.lerp(foot, knee_at)
	knee.y = maxf(hip.y, foot.y) + leg.knee_rise
	leg.upper.transform = _segment(leg.hip0, leg.knee0, hip, knee)
	leg.lower.transform = _segment(leg.knee0, leg.foot0, knee, foot)


## The transform taking a part modelled from a0 to b0 onto a1 to b1: turned without twisting
## about the vertical, stretched along its length.
static func _segment(a0: Vector3, b0: Vector3, a1: Vector3, b1: Vector3) -> Transform3D:
	var f0 := _frame(b0 - a0)
	var f1 := _frame(b1 - a1)
	var stretch := (b1 - a1).length() / maxf((b0 - a0).length(), 0.001)
	var basis := f1 * Basis.from_scale(Vector3(1.0, 1.0, stretch)) * f0.transposed()
	return Transform3D(basis, a1 - basis * a0)


## An orthonormal frame whose z is along `d`, x level.
static func _frame(d: Vector3) -> Basis:
	var z := d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


# --- robots ------------------------------------------------------------------------------------

func _robot(rig: Rig, delta: float) -> void:
	var speed := rig.velocity.length()
	rig.amount = move_toward(rig.amount, clampf(speed / ROBOT_FULL_SPEED, 0.0, 1.0), delta * 3.0)
	rig.still = rig.still + delta if speed < 0.08 else 0.0
	rig.phase += delta * TAU * ROBOT_BOB_RATE
	var lift := Vector3(0.0, ROBOT_BOB * sin(rig.phase), 0.0)
	if rig.body != null:
		rig.body.position = lift
	for pair in rig.parts.get("thrusters", []):
		var mi: MeshInstance3D = pair[0]
		mi.transform = Transform3D(Basis.IDENTITY, lift) * _pitched(pair[1], THRUSTER_SWING * rig.amount)
		mi.set_instance_shader_parameter("f3d_glow", 0.3 + 0.7 * rig.amount)
	var cargo: bool = model != null and model.robot_cargo.has(rig.unit)
	for pair in rig.parts.get("lamp_cargo", []):
		_place(pair, lift, cargo)
	for pair in rig.parts.get("lamp_empty", []):
		_place(pair, lift, not cargo)
	var working := rig.kind == "construction" and rig.still > WORK_STILL
	var frame := int(_time / WORK_FRAME) % 2
	for pair in rig.parts.get("lamp_nozzle", []):
		_place(pair, lift, true)
		(pair[0] as MeshInstance3D).set_instance_shader_parameter("f3d_glow", (1.0 if frame == 0 else 0.3) if working else 0.6)
	for pair in rig.parts.get("arms", []):
		var mi: MeshInstance3D = pair[0]
		var reach: float = float(mi.get_meta("reach", 0.0))
		reach = move_toward(reach, ARMS_REACH if working else 0.0, delta * 3.0)
		mi.set_meta("reach", reach)
		mi.transform = Transform3D(Basis.IDENTITY, lift) * _pitched(pair[1], reach)
	if working and sprites != null:
		rig.spark -= delta
		if rig.spark <= 0.0:
			rig.spark = SPARK_EVERY * randf_range(0.6, 1.4)
			var at := rig.node.global_transform * Vector3(0.0, 0.0, -0.35)
			sprites.call("emit", "sparks", at, 0.45, 0.35)


## A part tipped about its pivot's east-west axis (+ forward and down, - back).
static func _pitched(part: ModelLibrary.AnimPart, angle: float) -> Transform3D:
	return part.pivot * Transform3D(Basis(Vector3.RIGHT, angle), Vector3.ZERO) * part.pivot.affine_inverse()


static func _place(pair: Array, lift: Vector3, shown: bool) -> void:
	var mi: MeshInstance3D = pair[0]
	mi.visible = shown
	mi.position = lift


# --- capture robots ----------------------------------------------------------------------------

func _capture(rig: Rig, delta: float) -> void:
	rig.phase += delta * TAU / CAPTURE_LOOP
	var k := 0
	for pair in rig.parts.get("cable", []):
		var mi: MeshInstance3D = pair[0]
		var part: ModelLibrary.AnimPart = pair[1]
		var a := rig.phase + k * 2.1
		var sway := Basis(Vector3.RIGHT, CABLE_SWAY * sin(a)) * Basis(Vector3.BACK, CABLE_SWAY * 0.7 * sin(a * 2.0 + k))
		mi.transform = part.pivot * Transform3D(sway, Vector3.ZERO) * part.pivot.affine_inverse()
		mi.set_instance_shader_parameter("f3d_glow", 0.55 + 0.45 * sin(a * 2.0))
		k += 1


# --- cargo pods --------------------------------------------------------------------------------

func _pod(rig: Rig, delta: float) -> void:
	var height := rig.node.position.y
	rig.amount = move_toward(rig.amount, 1.0 if height > POD_OPEN_HEIGHT else 0.0, delta / POD_OPEN_TIME)
	# The antenna comes out over the first third, the panels swing out over the rest.
	var antenna := clampf(rig.amount / 0.3, 0.0, 1.0)
	var panels := clampf((rig.amount - 0.3) / 0.7, 0.0, 1.0)
	for pair in rig.parts.get("antenna", []):
		(pair[0] as MeshInstance3D).position = Vector3(0.0, POD_ANTENNA_RISE * (antenna - 1.0), 0.0)
	for pair in rig.parts.get("panel", []):
		var mi: MeshInstance3D = pair[0]
		var part: ModelLibrary.AnimPart = pair[1]
		var out := Vector3(part.pivot.origin.x, 0.0, part.pivot.origin.z).normalized()
		var axis := out.cross(Vector3.UP).normalized()
		var turn := Basis(axis, panels * PI * 0.5)
		mi.transform = part.pivot * Transform3D(part.pivot.basis.inverse() * turn * part.pivot.basis, Vector3.ZERO) \
			* part.pivot.affine_inverse()
	var thrust := clampf(absf(rig.velocity.y) / 6.0, 0.0, 1.0) if absf(rig.velocity.y) > POD_THRUST_SPEED else 0.0
	for pair in rig.parts.get("flame", []):
		var mi: MeshInstance3D = pair[0]
		mi.visible = thrust > 0.0
		if thrust > 0.0:
			var flicker := 0.85 + 0.15 * sin(_time * 41.0 + rig.phase)
			mi.scale = Vector3(1.0, (0.5 + 0.5 * thrust) * flicker, 1.0)


# --- tracks ------------------------------------------------------------------------------------

func _tracks(rig: Rig, moved: Vector3) -> void:
	var forward := -rig.node.global_transform.basis.z
	rig.travelled += moved.dot(forward)
	var spacing: float = TREAD_SPACING.get("tank", 0.12)
	var slide := fposmod(rig.travelled, spacing)
	for pair in rig.parts.get("tread", []):
		(pair[0] as MeshInstance3D).position = Vector3(0.0, 0.0, -slide)
