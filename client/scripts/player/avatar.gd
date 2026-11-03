extends Node3D
## The character the client controls, drawn from the mod's "me" messages. In a vehicle it is
## hidden and follows the vehicle (the camera follows it), and the vehicle is drawn as a mover.

const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const CharacterPose := preload("res://scripts/player/character_pose.gd")
const CharacterAnim := preload("res://scripts/player/character_anim.gd")
const GameClock := preload("res://scripts/world/game_clock.gd")

const FOLLOW_RATE := 18.0

var unit := 0
var walking := false
var health := 0
var max_health := 250
## The mod says the character is firing (its ammo went down a moment ago).
var firing := false
var craft_queue := 0
## Mining progress 0..100, or -1 when not mining.
var mining := -1
var mining_at := Vector2.ZERO
## The vehicle the character sits in (its unit number), or 0, and its speed in km/h.
var vehicle := 0
var vehicle_speed := 0.0

var _target := Vector3.ZERO
## The last few positions the mod sent and their ticks (`me`'s k): the avatar is drawn between them
## GameClock.DELAY_SENDS behind the game's clock, so it moves at an even speed and the run cycle
## steps evenly (chasing each position made it surge and sag, worst at exoskeleton
## speed). The clock runs at the game's measured tick rate, so a slow server doesn't make it lurch.
var _ticks: Array[float] = []
var _spots: Array[Vector3] = []
var _clock := GameClock.new()
## Each sent position's walk angle (`me`'s a, in turns), or -1 when not walking at an angle.
var _angles: Array[float] = []
## The angle of the stretch drawn now (-1: none); how far the avatar is drawn from the real
## position to keep it on the line, and the last real position drawn.
var _drawn_angle := -1.0
var _offset := Vector3.ZERO
var _last_goal := Vector3.ZERO
var _smooth_set := false
## Walking at an angle, Factorio's character zig-zags between two of its 8 directions about the
## line (puppet.lua). The avatar is drawn along the line: movement along it is followed exactly,
## sideways movement only through a slow filter, and never more than MAX_OFF from the real position,
## so sliding along a wall still shows. Without an angle it catches up at once.
const SIDE_RATE := 3.0
const MAX_OFF := 0.2
var _yaw_goal := 0.0
## The last angled walk's facing (NAN: none) and its tick, kept through the zig-zag's steps.
var _line_yaw := NAN
var _line_tick := -1.0
const ANGLE_HOLD := 10.0
## The character's own render layer: its lights cast no shadows of it (F7: running, its head and
## swinging arms passed in front of the flashlight, so the cone flickered with every stride).
const SELF_LAYER := 1 << 19
const NOT_SELF := 0xFFFFFFFF & ~SELF_LAYER
var _lantern := OmniLight3D.new()
## Factorio's character also lights a cone ahead of it at night (its `light`'s oriented cone,
## shifted 13 tiles forward): a flashlight.
var _flashlight := SpotLight3D.new()
var _body: Array = []  # the nodes hidden while in a vehicle or seen from inside (first person)
var _first_person := false
## The character model (Wube's, skinned: character_pose.gd), drawn as a one-instance MultiMesh
## with its own copy of the materials, which carry the pose.
var _rig: MultiMeshInstance3D
var _pose: CharacterPose
var _anim := CharacterAnim.new()
var _materials: Array[ShaderMaterial] = []
var _pickaxe: Node3D
var _gun: Node3D
var _last := Vector3.ZERO
var _has_state := false
## Where the character is shooting (world position), or null: set by combat.gd.
var aim_target = null
## --anim-pose=<run|idle|mine|aim|ready|runaim|runready|dead>: hold one animation.
var _demo := ""
## The item in the armour slot (set_armor), the look drawn for it, and whether that is the mech's.
var armor := ""
var look := BODY_MODEL
var _mech := false

const BODY_MODEL := "character"
const MECH_ARMOR := "mech-armor"
const MECH_MODEL := "character-mech-armor"
## Factorio's look per armour (entities.lua's character animations): heavy and modular armour add
## the level 2 layer, power armour the level 3 one; light armour (and modded armour) keeps the plain
## look. The looks share the character's skeleton and animations (tools/models/armour_looks.py).
const LOOKS := {"heavy-armor": "character-armor-2", "modular-armor": "character-armor-2",
	"power-armor": "character-armor-3", "power-armor-mk2": "character-armor-3", MECH_ARMOR: MECH_MODEL}

## The hand's grip in the rest pose (right hand, the model's frame), where tools are held.
const GRIP := Vector3(0.26, 0.73, -0.04)
## The pickaxe's handle: turned this far from pointing forwards (-Z) towards down.
const PICK_ANGLE := -0.97
## Gun muzzle in the gun's own frame (barrel along -Z).
const MUZZLE := Vector3(0.0, 0.08, -0.64)
## Factorio's running_speed 0.15 tiles a tick, for --anim-pose.
const DEMO_SPEED := 9.0


func _ready() -> void:
	# Factorio's character carries a light at night, so the player is never in the dark.
	_lantern.light_color = Color(1.0, 0.92, 0.8)
	_lantern.omni_range = 11.0
	_lantern.position = Vector3(0, 2.5, 0)
	_lantern.light_energy = 0.0
	_lantern.shadow_enabled = true
	add_child(_lantern)
	_flashlight.light_color = Color(1.0, 0.95, 0.88)
	_flashlight.spot_range = 26.0
	_flashlight.spot_angle = 24.0
	_flashlight.spot_attenuation = 0.6
	_flashlight.position = Vector3(0, 1.6, -0.3)
	_flashlight.rotation.x = deg_to_rad(-8.0)  # down onto the ground ahead (forward is -Z)
	_flashlight.shadow_enabled = true
	_flashlight.light_energy = 0.0
	_flashlight.visible = false
	add_child(_flashlight)
	_lantern.shadow_caster_mask = NOT_SELF
	_flashlight.shadow_caster_mask = NOT_SELF
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--anim-pose="):
			_demo = arg.get_slice("=", 1)
	var body: GeometryInstance3D = MeshInstance3D.new()
	var rigged := _make_rig(BODY_MODEL)
	if rigged != null:
		body = rigged
		_pickaxe = _make_pickaxe()
		_gun = _make_gun()
		for tool in [_pickaxe, _gun]:
			tool.visible = false
			add_child(tool)
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.7
		(body as MeshInstance3D).mesh = capsule
		body.position.y = 0.85
		body.material_override = Visuals.solid_material(Color(0.95, 0.6, 0.15))
		# A nose, so you can see which way the character faces.
		var nose := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.15, 0.15, 0.3)
		nose.mesh = box
		nose.position = Vector3(0, 1.35, -0.3)
		nose.material_override = Visuals.solid_material(Color(0.2, 0.2, 0.2))
		add_child(nose)
		_body.append(nose)
	add_child(body)
	_body.append(body)
	_own_layer(self)


## Puts the character's meshes (body, tools) on SELF_LAYER, so its own lights don't shadow them.
static func _own_layer(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).layers = SELF_LAYER
	for child in node.get_children():
		_own_layer(child)


## The skinned body drawn with `model` (character.glb, or the mech's), as a one-instance
## MultiMesh with its own materials; sets _rig, _pose and _materials. Null (and nothing
## changed) without the model or its rig.
func _make_rig(model_name: String) -> MultiMeshInstance3D:
	var model := ModelLibrary.mesh_for(model_name)
	var pose := CharacterPose.new()
	if not (model is ArrayMesh and pose.load_rig(model_name)):
		return null
	_pose = pose
	_materials.clear()
	_rig = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _own_copy(model as ArrayMesh)
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, Color(0, 0, 0, 1))
	_rig.multimesh = mm
	# The pose moves vertices outside the mesh's own box (a raised pickaxe, lying dead).
	_rig.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4.5, 4))
	return _rig


## The armour in the character's armour slot (item name, "" for none): the body swaps to that
## armour's look (LOOKS; in mech armour a walking suit with a rig of its own).
func set_armor(item: String) -> void:
	armor = item
	var want := look_for(item)
	if want == look or _rig == null:
		return
	var old := _rig
	var fresh := _make_rig(want)
	if fresh == null:
		return  # no model or rig for that look in this build: keep the one drawn
	look = want
	_mech = want == MECH_MODEL
	_anim.mech = _mech
	_body.erase(old)
	old.queue_free()
	add_child(fresh)
	_own_layer(fresh)
	_body.append(fresh)
	_update_body()


## The model Factorio's look for armour `item` is drawn with.
static func look_for(item: String) -> String:
	return str(LOOKS.get(item, BODY_MODEL))


func is_mech() -> bool:
	return _mech


## The model with its own materials, so this character's pose doesn't move other characters.
func _own_copy(model: ArrayMesh) -> ArrayMesh:
	# Built surface by surface: a duplicate() of an imported mesh doesn't draw.
	var out := ArrayMesh.new()
	for i in model.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ModelLibrary.ModelLods.arrays_of(model, i), [], {},
			model.surface_get_format(i) & ~Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.surface_set_name(i, model.surface_get_name(i))
		var m := model.surface_get_material(i) as ShaderMaterial
		if m != null:
			m = ModelLibrary.ModelLods.copy_material(m)
			_materials.append(m)
		out.surface_set_material(i, m)
	return out


## Factorio's pickaxe: a wooden handle with an iron head, the handle along -Z from the grip.
func _make_pickaxe() -> Node3D:
	var root := Node3D.new()
	var wood := Visuals.solid_material(Color(0.45, 0.29, 0.16))
	var iron := Visuals.solid_material(Color(0.42, 0.43, 0.45))
	iron.metallic = 0.6
	iron.roughness = 0.5
	var handle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.022
	cyl.bottom_radius = 0.026
	cyl.height = 0.58
	handle.mesh = cyl
	handle.material_override = wood
	handle.rotation.x = PI / 2.0
	handle.position.z = -0.2
	root.add_child(handle)
	# The head: two tapering spikes, curving a little back towards the hand.
	for side in [-1.0, 1.0]:
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.006
		cone.bottom_radius = 0.034
		cone.height = 0.2
		cone.radial_segments = 6
		spike.mesh = cone
		spike.material_override = iron
		spike.position = Vector3(0.0, side * 0.1, -0.45)
		spike.rotation.x = (0.0 if side > 0 else PI) + side * 0.25
		root.add_child(spike)
	var collar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.06, 0.07, 0.07)
	collar.mesh = box
	collar.material_override = iron
	collar.position.z = -0.47
	root.add_child(collar)
	return root


## The character's gun (Factorio's submachine gun as its sprites show it: a dark steel body,
## a magazine under it, a wooden stock), barrel along -Z from the grip.
func _make_gun() -> Node3D:
	var root := Node3D.new()
	var steel := Visuals.solid_material(Color(0.2, 0.21, 0.22))
	steel.metallic = 0.7
	steel.roughness = 0.45
	var wood := Visuals.solid_material(Color(0.38, 0.24, 0.13))
	var parts := [
		[Vector3(0.07, 0.09, 0.42), Vector3(0.0, 0.07, -0.14), steel],  # receiver
		[Vector3(0.035, 0.035, 0.3), Vector3(0.0, 0.08, -0.48), steel],  # barrel
		[Vector3(0.05, 0.12, 0.05), Vector3(0.0, 0.0, 0.0), steel],  # grip
		[Vector3(0.06, 0.08, 0.2), Vector3(0.0, 0.05, 0.16), wood],  # stock
		[Vector3(0.05, 0.14, 0.07), Vector3(0.0, -0.02, -0.24), steel],  # magazine
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[0]
		mi.mesh = box
		mi.position = p[1]
		mi.material_override = p[2]
		root.add_child(mi)
	return root


func snap_to(pos: Vector2) -> void:
	_target = Vector3(pos.x, 0, pos.y)
	position = _target
	_ticks.clear()
	_spots.clear()
	_angles.clear()
	_smooth_set = false


## {t: "me", u, x, y, d, w, hp, q, mhp?, sh?, m?, mx?, my?, v?, vs?}
func update_from(msg: Dictionary) -> void:
	unit = int(msg.get("u", unit))
	_target = Vector3(int(msg.get("x", 0)) / 256.0, 0.0, int(msg.get("y", 0)) / 256.0)
	_sample(float(msg.get("k", -1)), _target, float(msg["a"]) / 1000.0 if msg.has("a") else -1.0)
	walking = int(msg.get("w", 0)) == 1
	_yaw_goal = _facing_yaw(msg)
	health = int(msg.get("hp", 0))
	_has_state = msg.has("hp")
	max_health = maxi(1, int(msg.get("mhp", max_health)))
	firing = int(msg.get("sh", 0)) == 1
	craft_queue = int(msg.get("q", 0))
	vehicle = int(msg.get("v", 0))
	# Thousandths of a tile per tick; a tile is a metre.
	vehicle_speed = int(msg.get("vs", 0)) / 1000.0 * 60.0 * 3.6
	_update_body()
	if msg.has("m"):
		mining = int(msg["m"])
		mining_at = Vector2(int(msg.get("mx", 0)), int(msg.get("my", 0))) / 256.0
	else:
		mining = -1


## Which way the body faces for a `me`: an angled walk's line (`a`); else the 8-way direction,
## except that the line is kept while that direction is one of the two the zig-zag steps between
## (a message without `a` mid-walk, or stopping after one): otherwise the body, and the
## flashlight with it, would swing 22 degrees back and forth. A walk without an angle
## for ANGLE_HOLD ticks, or a direction off the line, ends it.
func _facing_yaw(msg: Dictionary) -> float:
	var k := float(msg.get("k", -1))
	if msg.has("a"):
		_line_yaw = -float(msg["a"]) / 1000.0 * TAU
		_line_tick = k
		return _line_yaw
	var d_yaw := Visuals.direction_yaw(int(msg.get("d", 0)))
	if is_nan(_line_yaw):
		return d_yaw
	var stale := walking and k >= 0.0 and _line_tick >= 0.0 and k - _line_tick > ANGLE_HOLD
	if stale or absf(wrapf(d_yaw - _line_yaw, -PI, PI)) > PI / 4.0 + 0.01:
		_line_yaw = NAN
		return d_yaw
	return _line_yaw


## Hides the body while the camera is inside it.
func set_first_person(on: bool) -> void:
	_first_person = on
	_update_body()


func _update_body() -> void:
	for node in _body:
		(node as Node3D).visible = vehicle == 0 and not _first_person


## `night`: 0 in daylight, 1 at full darkness.
func set_night(night: float) -> void:
	_lantern.light_energy = 1.8 * night
	_lantern.visible = night > 0.01
	var cone := beam(night)
	_flashlight.light_energy = 6.0 * cone
	_flashlight.visible = cone > 0.01


## How much of a cone light (the flashlight, locomotives' headlights) shows: Factorio switches them
## on above darkness 0.3 (`minimum_darkness`), faded in here instead of popping.
static func beam(night: float) -> float:
	return smoothstep(0.3, 0.5, night)


func ground_position() -> Vector2:
	return Vector2(position.x, position.z)


## Remembers a sent position at game tick `k` (none when the message has no tick: then the avatar
## just follows the newest).
func _sample(k: float, at: Vector3, angle := -1.0) -> void:
	if k < 0.0:
		_ticks.clear()
		_spots.clear()
		_angles.clear()
		return
	var n := _ticks.size()
	if n > 0 and k < _ticks[n - 1]:
		_clock = GameClock.new()  # the game went back (a save loaded)
	if n > 0 and (at.distance_to(_spots[n - 1]) > 8.0 or k - _ticks[n - 1] > 60.0 or k < _ticks[n - 1]):
		_ticks.clear()  # a teleport, a new surface or a long gap: start again from here
		_spots.clear()
		_angles.clear()
		_smooth_set = false
		n = 0
	if n > 0 and k == _ticks[n - 1]:
		_spots[n - 1] = at
		_angles[n - 1] = angle
		return
	_clock.heard(k)
	_ticks.append(k)
	_spots.append(at)
	_angles.append(angle)
	if _ticks.size() > 8:
		_ticks.remove_at(0)
		_spots.remove_at(0)
		_angles.remove_at(0)


## Where the avatar is drawn now: between the sent positions around the clock's drawn tick, else
## the newest.
func _drawn_target(delta: float) -> Vector3:
	var drawn := _clock.advance(delta)
	var n := _ticks.size()
	_drawn_angle = -1.0
	if n < 2:
		return _target
	if drawn <= _ticks[0]:
		return _spots[0]
	for i in range(1, n):
		if drawn <= _ticks[i]:
			# The stretch walks at an angle only when both ends do (a stop or start draws as it is).
			if _angles[i - 1] >= 0.0 and _angles[i] >= 0.0:
				_drawn_angle = _angles[i]
			return _spots[i - 1].lerp(_spots[i], (drawn - _ticks[i - 1]) / (_ticks[i] - _ticks[i - 1]))
	return _spots[n - 1]


## The drawn position `goal` with the sideways zig-zag of an angled walk taken out: each frame's
## sideways step goes into an offset that fades at SIDE_RATE (FOLLOW_RATE without an angle).
func _along_line(goal: Vector3, delta: float) -> Vector3:
	if not _smooth_set or goal.distance_to(_last_goal) > 2.0:
		_offset = Vector3.ZERO
		_last_goal = goal
		_smooth_set = true
		return goal
	var moved := goal - _last_goal
	_last_goal = goal
	if _drawn_angle >= 0.0:
		var rad := _drawn_angle * TAU
		var heading := Vector3(sin(rad), 0.0, -cos(rad))
		_offset -= moved - heading * moved.dot(heading)
		_offset -= heading * _offset.dot(heading)
		_offset *= exp(-delta * SIDE_RATE)
	else:
		_offset *= exp(-delta * FOLLOW_RATE)
	_offset = _offset.limit_length(MAX_OFF)
	return goal + _offset


func _process(delta: float) -> void:
	var t := 1.0 - exp(-delta * FOLLOW_RATE)
	var goal := _along_line(_drawn_target(delta), delta)
	position = goal if _ticks.size() >= 2 and position.distance_to(goal) < 2.0 else position.lerp(goal, t)
	rotation.y = lerp_angle(rotation.y, _body_yaw(), t)
	if _rig != null:
		_animate(delta)


## Which way the legs face: where the character walks, except while shooting, when it faces
## the target standing, and runs backwards rather than twist round further than its waist can.
func _body_yaw() -> float:
	if not (firing and aim_target != null):
		return _yaw_goal
	var to: Vector3 = aim_target - position
	var aim_yaw := atan2(-to.x, -to.z)
	if not walking:
		return aim_yaw
	if absf(wrapf(aim_yaw - _yaw_goal, -PI, PI)) > CharacterAnim.MAX_TWIST + 0.35:
		return _yaw_goal + PI
	return _yaw_goal


## The skeleton's pose for this frame (character_anim.gd), and the tool in the hand.
func _animate(delta: float) -> void:
	var moved := Vector3(position.x - _last.x, 0.0, position.z - _last.z)
	_last = position
	if moved.length() > 1.0:
		moved = Vector3.ZERO  # a teleport (snap_to, a new surface)
	var facing := -global_transform.basis.z
	var distance := moved.dot(facing.normalized())
	_anim.running = walking
	_anim.mining = mining >= 0
	_anim.firing = firing
	_anim.aiming = firing and aim_target != null
	_anim.dead = _has_state and health <= 0
	_anim.aim_twist = 0.0
	if aim_target != null:
		var to: Vector3 = aim_target - position
		_anim.aim_twist = wrapf(atan2(-to.x, -to.z) - rotation.y, -PI, PI)
	if _demo != "":
		distance = _demo_state(delta)
	_anim.step(_pose, delta, distance)
	var rows := _pose.rows()
	for m in _materials:
		m.set_shader_parameter("rig_bone", rows)
	var shown := vehicle == 0 and not _first_person
	_pickaxe.visible = _anim.pickaxe_shown and shown
	_gun.visible = _anim.gun_shown and shown
	var grip := Transform3D(Basis.IDENTITY, GRIP)
	if _pickaxe.visible:
		# The handle carries on from the forearm, angled forwards: down past the knee at rest,
		# behind the head with the arm raised, into the ground at the strike.
		_pickaxe.transform = _pose.frame("forearm_r", grip * Transform3D(Basis(Vector3.RIGHT, PICK_ANGLE), Vector3.ZERO))
	if _gun.visible:
		# The barrel along the forearm (pointing down at rest), its top facing forwards.
		_gun.transform = _pose.frame("forearm_r", grip * Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO))


## A shot going off (weapon_fx.gd, on each `shot`): the gun kicks back.
func kick(strength := 1.0) -> void:
	_anim.kick(strength)


## Where shots leave the gun (world): muzzle flashes, beams, projectiles' first height.
func muzzle_position() -> Vector3:
	if _mech and _pose != null:
		# The mech's right forearm is its gun: its bone ends at the muzzle.
		return global_transform * _pose.point("forearm_r", _pose.tail_of("forearm_r"))
	if _gun != null and _gun.visible:
		return _gun.global_transform * MUZZLE
	return position + Vector3(0, 1.1, 0)


func _demo_state(delta: float) -> float:
	_anim.running = _demo in ["run", "runaim", "runready"]
	_anim.mining = _demo == "mine"
	_anim.aiming = _demo in ["aim", "runaim"]
	_anim.firing = _anim.aiming or (_demo in ["ready", "runready"] and Time.get_ticks_msec() < 2000)
	_anim.aim_twist = 0.6 if _demo == "runaim" else 0.0
	_anim.dead = _demo == "dead"
	return DEMO_SPEED * delta if _anim.running else 0.0
