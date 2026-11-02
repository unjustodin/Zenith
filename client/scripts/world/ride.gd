extends Node3D
## Riding to a space platform and back, as Factorio 2.x does it, from the
## mod's `me` (docs/PROTOCOL.md, "Riding to a platform"):
##   up      `ride` from a silo: the character walks into the rocket, the camera pulls back, the
##           engine lights, the rocket rises out of the silo and climbs at the game's own pace (its
##           height is how far the pod's position runs north of the silo, as Factorio draws it),
##           the view fades out high in the sky and in again in space, where the cargo pod comes
##           down onto the platform's hub and docks.
##   in hub  the character sits in the hub (`me.hub`): no avatar, the remote view round the hub
##           (factorio_ui.enter_hub: WASD pans, building places ghosts, screens open from afar).
##   down    `land` from the platform panel: the pod rises off the hub, fades out, and comes down
##           on the planet onto the landing pad or beside the spawn, where the character steps out.
## The character's own position is held meanwhile, and the world input is locked (the HUD stays,
## so the inventory and the Esc menu work, as in the game).

const ModelLibrary := preload("res://scripts/world/model_library.gd")

const BOARD_TIME := 1.2       # seconds to walk into the rocket
const IGNITE_AFTER := 5.0     # seconds into awaiting_launch (about 7.5 s in 2.1.23) the engine lights
const FADE_FROM := 120.0      # tiles up the rocket climbs before the view fades out...
const FADE_OVER := 70.0       # ...over this many more
const POD_FADE_AFTER := 4.5   # seconds a pod climbs off a hub before the view fades out
const FADE_IN := 1.2
const GROUND_WAIT := 2.0      # on a planet the ground needs a moment to stream in before the view opens
const DOCK_TIME := 1.3        # the pod sinks into the hub while parking
const HUB_TOP := 3.5          # where a pod parks on a hub, above the ground (2.1.23: 3.5 tiles north)

enum { IDLE, BOARDING, UP, ARRIVING, IN_HUB, LEAVING }

var avatar    # avatar.gd
var rig       # camera_rig.gd
var rockets   # rockets.gd
var ui        # factorio_ui.gd
var input     # player_input.gd: its world input is locked while riding

var state := IDLE
var _anchor := Node3D.new()      # what the camera follows meanwhile
var _pod := MeshInstance3D.new()  # the ridden pod, drawn here (not as a mover)
var _jet := MeshInstance3D.new()  # its engine, under it while it climbs or brakes
var _fade := ColorRect.new()
var _fade_layer := CanvasLayer.new()
var _fade_goal := 0.0
var _fade_rate := 1.0
var _hold := Vector2.ZERO        # where the avatar stays drawn (tiles)
var _board_from := Vector2.ZERO
var _ground := Vector2.ZERO      # the flight's ground point (tiles)
var _start_height := -1.0        # the pod's first height on this leg (its rest in the rocket)
var _height := 0.0               # tiles above the ground point, now
var _height_goal := 0.0
var _pod_at := Vector2.ZERO      # the pod's 2D position, smoothed (tiles)
var _pod_goal := Vector2.ZERO
var _ps := ""                    # the pod's state
var _t := 0.0                    # seconds in this state
var _locked := false
var _fade_in_at := -1.0          # seconds into ARRIVING when the view fades in


func _ready() -> void:
	_anchor.name = "RideView"
	add_child(_anchor)
	_pod.name = "RiddenPod"
	# The model is made on a worker thread (making it here cost 5 ms at start-up); a capsule stands
	# in until it is ready, or for good without it.
	ModelLibrary.ready("cargo-pod")
	var c := CapsuleMesh.new()
	c.radius = 0.8
	c.height = 2.6
	_pod.mesh = c
	_pod.visible = false
	add_child(_pod)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.45
	cone.bottom_radius = 0.02
	cone.height = 2.2
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.75, 0.35, 0.85)
	hot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone.material = hot
	_jet.mesh = cone
	_jet.position.y = -1.3
	_pod.add_child(_jet)
	_fade_layer.layer = 90  # over the world, under the menus
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade)
	add_child(_fade_layer)


func riding() -> bool:
	return state in [BOARDING, UP, ARRIVING, LEAVING]


func in_hub() -> bool:
	return state == IN_HUB


## The view's darkness now, 0 to 1 (tests).
func fade() -> float:
	return _fade.color.a


## Each `me`: follows the ride. Returns the message for the avatar: while riding or in a hub its
## position is the held one, so the avatar doesn't race off along the pod's track.
func handle_me(msg: Dictionary) -> Dictionary:
	var pod := int(msg.get("pod", 0))
	var hub := int(msg.get("hub", 0))
	var at := Vector2(int(msg.get("x", 0)), int(msg.get("y", 0))) / 256.0
	if pod == 0 and hub == 0:
		if state != IDLE:
			_finish(at)
		return msg
	if hub != 0:
		if state != IN_HUB:
			_dock(at)
		return _held(msg, at, false)
	var ps := str(msg.get("ps", ""))
	var up := int(msg.get("up", 0)) == 1
	var ground := Vector2(int(msg.get("gx", 0)), int(msg.get("gy", 0))) / 256.0
	if ps != _ps:
		_ps = ps
		_t = 0.0
	if rockets != null:
		rockets.ridden = pod
	if state == IDLE or state == IN_HUB:
		_start(up, ground, at)
	elif up and state == ARRIVING:
		_start(up, ground, at)  # a new leg
	elif not up and state in [UP, LEAVING, BOARDING]:
		_arrive(ground, at)
	_ground = ground
	_pod_goal = at
	var h := ground.y - at.y
	if _start_height < 0.0:
		_start_height = h
	_height_goal = maxf(0.0, h - (_start_height if up else 0.0))
	return _held(msg, _hold, state == BOARDING)


func _held(msg: Dictionary, at: Vector2, walking: bool) -> Dictionary:
	var out := msg.duplicate()
	out["x"] = roundi(at.x * 256.0)
	out["y"] = roundi(at.y * 256.0)
	out["w"] = 1 if walking else 0
	out.erase("m")
	return out


## A leg begins: from a silo on a planet (the rocket) or from a hub (a pod alone).
func _start(up: bool, ground: Vector2, at: Vector2) -> void:
	_lock(true)
	if ui != null:
		ui.close_all()
		ui.leave_hub()
	_ground = ground
	_start_height = -1.0
	_height = 0.0
	_pod_at = at
	_pod_goal = at
	if not up:  # joined mid-way (a reconnect): just watch the pod come down
		_arrive(ground, at)
		return
	var from_hub: bool = state == IN_HUB or (ui != null and ui.model.character_si != 0 and _on_platform())
	if from_hub:
		state = LEAVING
		_hold = ground
		_place_anchor(ground, 0.0)
		rig.target = _anchor
		rig.cinematic(30.0, 30.0)
	else:
		state = BOARDING
		_board_from = avatar.ground_position() if avatar != null else ground
		_hold = _board_from
		_place_anchor(ground, 2.0)
		rig.target = _anchor
		rig.cinematic(22.0, 55.0)
	_t = 0.0


func _on_platform() -> bool:
	return ui != null and ui.platform_panel != null and int(ui.platform_panel.on) != 0


## The pod is on its way down onto this surface (the platform's hub or the planet). Which of the two
## is decided as it flies (_fly_pod): `surface` may come a moment after the first `me` down.
func _arrive(ground: Vector2, at: Vector2) -> void:
	state = ARRIVING
	_ground = ground
	_start_height = -1.0
	_pod_at = at
	_pod_goal = at
	_height = maxf(0.0, ground.y - at.y)
	_height_goal = _height
	_hold = ground
	_set_fade(1.0)
	_fade_in_at = 0.3 if _on_platform() else GROUND_WAIT
	rig.target = _anchor
	rig.cinematic(30.0, 30.0)
	_place_anchor(at, _height)
	rig.global_position = _anchor.global_position


## The pod docked: the character is inside the hub at `at`.
func _dock(at: Vector2) -> void:
	state = IN_HUB
	_pod.visible = false
	if rockets != null:
		rockets.ridden = 0
	_set_fade(0.0, 2.0)
	rig.cinematic_end()
	_lock(false)
	_hold = at
	if ui != null:
		ui.enter_hub(at)


## Back on the ground (out of a pod) or out of the hub some other way.
func _finish(at: Vector2) -> void:
	state = IDLE
	_ps = ""
	_pod.visible = false
	if rockets != null:
		rockets.ridden = 0
	if ui != null:
		ui.leave_hub()
	if avatar != null:
		avatar.snap_to(at)
		avatar.visible = true
	if rig != null:
		rig.target = avatar
		rig.cinematic_end()
	_set_fade(0.0, 3.0)
	_lock(false)


func _lock(on: bool) -> void:
	if on == _locked:
		return
	_locked = on
	if input != null:
		input.set_process(not on)
		input.set_process_unhandled_input(not on)
		if on:
			Bridge.send({"t": "walk", "d": -1})


func _set_fade(alpha: float, seconds := 0.0) -> void:
	_fade_goal = alpha
	if seconds <= 0.0:
		_fade.color.a = alpha
	else:
		_fade_rate = 1.0 / seconds


func _place_anchor(at: Vector2, height: float) -> void:
	_anchor.position = Vector3(at.x, height, at.y)


func _process(delta: float) -> void:
	_fade.color.a = move_toward(_fade.color.a, _fade_goal, _fade_rate * delta)
	_fade_layer.visible = _fade.color.a > 0.001
	if state == IDLE:
		return
	_t += delta
	if avatar != null and state != BOARDING:
		avatar.visible = false
	# The game sends the pod's place every 2 ticks: glide between them.
	_height = lerpf(_height, _height_goal, 1.0 - exp(-delta * 10.0))
	_pod_at = _pod_at.lerp(_pod_goal, 1.0 - exp(-delta * 10.0))
	match state:
		BOARDING, UP:
			_rocket(delta)
		LEAVING, ARRIVING:
			_fly_pod()


## From the silo: the walk in, then the rocket on the game's height.
func _rocket(_delta: float) -> void:
	if state == BOARDING:
		var f := clampf(_t / BOARD_TIME, 0.0, 1.0)
		_hold = _board_from.lerp(_ground, f)
		if f >= 1.0:
			state = UP
			if avatar != null:
				avatar.visible = false
	var ignition := 0.0
	if _ps == "awaiting_launch":
		ignition = clampf((_t - IGNITE_AFTER) / 2.0, 0.0, 0.6)
	elif _ps != "":
		ignition = 1.0
	if rockets != null:
		rockets.drive(_ground, _height, ignition)
	# The camera rises with the rocket, a little below it, and the view fades out high up.
	_place_anchor(_ground, maxf(2.0, _height * 0.85))
	if _height > FADE_FROM:
		_set_fade(clampf((_height - FADE_FROM) / FADE_OVER, 0.0, 1.0))
	if _ps == "surface_transition":
		_set_fade(1.0, 0.4)


## A pod on its own: off a hub, onto a hub, down to a planet.
func _fly_pod() -> void:
	var h := _height
	if state == LEAVING:
		h += HUB_TOP  # it sets off from the hub's hatch, on top
	elif _on_platform():
		# Onto a hub: the game parks it on the hatch (its height then reads HUB_TOP), and it sinks in.
		h = maxf(HUB_TOP, _height)
		if _ps == "parking":
			h = lerpf(HUB_TOP, 0.4, clampf(_t / DOCK_TIME, 0.0, 1.0))
	_pod.visible = true
	if _pod.mesh is CapsuleMesh and ModelLibrary.ready("cargo-pod") and ModelLibrary.mesh_for("cargo-pod") != null:
		_pod.mesh = ModelLibrary.mesh_for("cargo-pod")
	# Its engine burns while it climbs, and brakes on the way down until it is nearly there.
	_jet.visible = (_ps == "ascending") or (_ps == "descending" and h > 1.5)
	_jet.scale = Vector3.ONE * (0.85 + 0.15 * sin(_t * 41.0))
	# Factorio's pod position is its ground point shifted north by its height; across, it is its own.
	_pod.position = Vector3(_pod_at.x, h, _ground.y)
	_pod.rotation = Vector3.ZERO
	_place_anchor(Vector2(_pod_at.x, _ground.y), maxf(1.0, h))
	if state == ARRIVING and _fade_in_at >= 0.0 and _t >= _fade_in_at:
		_fade_in_at = -1.0
		_set_fade(0.0, FADE_IN)
	if state == LEAVING and _ps == "ascending" and _t > POD_FADE_AFTER:
		_set_fade(1.0, 1.5)
	if _ps == "surface_transition":
		_set_fade(1.0, 0.3)
