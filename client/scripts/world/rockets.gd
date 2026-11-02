extends Node3D
## Space Age's travel in 3D: a rocket leaving its silo, cargo pods coming down and going up, and
## asteroid chunks drifting past a platform.
##
## Rockets: on `rk` (a launch was ordered, ui_model.rocket_launched) the rocket model stands in the
## silo, its engine lights for ENGINE_START seconds (flame, light, smoke), then it climbs ever
## faster until it is far above the camera. The rocket mover the mod sends for that silo
## (rocket-silo-rocket) is hidden meanwhile, so it isn't drawn twice. When the character rides
## that rocket, ride.gd drives it instead (drive()): its height comes from the game's own flight.
## Cargo pods: the movers layer draws them where the mod puts them on the ground; this lifts them:
## a pod descending (`cp` state) drops from DESCENT_HEIGHT to the ground over DESCENT_TIME with a
## braking flame, one ascending rises away.
## Asteroid chunks (`ach`): one MultiMesh per chunk kind, each chunk moved on by its velocity
## between messages; one an asteroid collector holds is left to collectors.gd.

const ModelLibrary := preload("res://scripts/world/model_library.gd")
const Visuals := preload("res://scripts/world/visuals.gd")

const ENGINE_START := 2.5
const ACCELERATION := 2.5       # tiles/s² once off the pad: a slow start, as in Factorio
const FLIGHT_TIME := 14.0       # then the rocket is gone
const DESCENT_HEIGHT := 45.0
const DESCENT_TIME := 3.5
const ASCENT_ACCELERATION := 9.0
const CHUNK_SCALE := 0.45
const CHUNK_HEIGHT := 0.6
## A chunk within this many tiles of where one of its kind was drawn is the same chunk, moved on.
const MATCH_DISTANCE := 1.0
## How fast the gap between a chunk's drawn and sent place closes (per second).
const CHUNK_SETTLE := 6.0

var movers  # movers.gd
## The surface the world shows (main.gd sets it on `surface`): launches elsewhere aren't drawn here
## (H1: a launch on Nauvis drew a rocket at its silo's place on the platform being watched).
var surface := ""
## Where each of the game's own rockets (rocket-silo-rocket movers) was first seen.
var _rocket_start := {}
var model   # ui_model.gd
## The cargo pod the character rides in (ride.gd draws it), left alone here.
var ridden := 0

var _launches: Array = []        # [{"node", "flame", "light", "smoke", "at" (Vector2), "t"}]
var _pods := {}                  # unit -> {"state", "t"}
var _chunk_meshes := {}          # chunk name -> MultiMeshInstance3D
var _chunks_msec := 0            # when the chunks drawn now were sent (Time.get_ticks_msec)
var _flame_material: StandardMaterial3D


func _ready() -> void:
	# Asked for now, read on a worker thread: made here at a launch it took 36-48 ms in that frame
	# on the owner's save (its silos launch on their own).
	ModelLibrary.ready("rocket-silo-rocket")
	# ... and the smoke's material made now too: its first StandardMaterial3D shader was generated in
	# the launch's frame.
	_puff_mesh()
	_puff_fade()
	_flame_material = StandardMaterial3D.new()
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.albedo_color = Color(1.0, 0.72, 0.3)
	_flame_material.emission_enabled = true
	_flame_material.emission = Color(1.0, 0.6, 0.2)
	_flame_material.emission_energy_multiplier = 3.0
	_flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	model.rocket_launched.connect(_on_launch)
	model.asteroid_chunks_changed.connect(_on_chunks)


func reset() -> void:
	for l in _launches:
		(l["node"] as Node3D).queue_free()
	_launches.clear()
	_pods.clear()
	_rocket_start.clear()
	for mm in _chunk_meshes.values():
		(mm as MultiMeshInstance3D).multimesh.visible_instance_count = 0


func launch_count() -> int:
	return _launches.size()


## Where the rockets climbing now are drawn (add-ons' api.world.rockets()).
func launch_positions() -> Array:
	var out: Array = []
	for l: Dictionary in _launches:
		var n = l.get("node")
		if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
			out.append((n as Node3D).global_position)
	return out


## The ridden rocket at `at` (silo, tiles): `height` above the silo (tiles) and how far its engine
## has lit (0 to 1), from the game's flight (ride.gd). Starts the launch if `rk` hasn't yet.
func drive(at: Vector2, height: float, ignition: float) -> void:
	var l := _launch_at(at)
	if l.is_empty():
		_on_launch(0, at, "")
		l = _launches[-1]
	l["driven"] = true
	l["h"] = height
	l["ign"] = ignition
	l["seen"] = 0.0


## The rocket the ride drives at `at`, or null.
func driven_rocket(at: Vector2) -> Node3D:
	var l := _launch_at(at)
	return l["node"] if not l.is_empty() else null


func _launch_at(at: Vector2) -> Dictionary:
	for l in _launches:
		if (l["at"] as Vector2).distance_to(at) < 3.0:
			return l
	return {}


# --- rockets ----------------------------------------------------------------------------------

func _on_launch(_silo: int, at: Vector2, launch_surface: String) -> void:
	if surface != "" and launch_surface != "" and launch_surface != surface:
		return
	var root := Node3D.new()
	root.position = Vector3(at.x, -Visuals.ROCKET_SINK, at.y)
	var body := MeshInstance3D.new()
	body.mesh = ModelLibrary.mesh_for("rocket-silo-rocket") if ModelLibrary.ready("rocket-silo-rocket") else null
	if body.mesh == null:  # no model (or not read yet): a white rocket of the right size
		var c := CylinderMesh.new()
		c.top_radius = 0.9
		c.bottom_radius = 1.0
		c.height = 12.0
		body.mesh = c
		body.position.y = 6.0
	root.add_child(body)
	var flame := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.8
	cone.bottom_radius = 0.05
	cone.height = 4.0
	flame.mesh = cone
	flame.material_override = _flame_material
	flame.position.y = -2.0
	flame.scale = Vector3(0.01, 0.01, 0.01)
	root.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.omni_range = 30.0
	light.light_energy = 0.0
	light.position.y = -1.0
	root.add_child(light)
	var smoke := CPUParticles3D.new()
	smoke.amount = 90
	smoke.lifetime = 3.0
	smoke.emitting = false
	smoke.local_coords = false
	smoke.direction = Vector3(0, -1, 0)
	smoke.spread = 85.0
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 5.0
	smoke.gravity = Vector3(0, 0.5, 0)
	smoke.damping_min = 1.5
	smoke.damping_max = 2.5
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.0
	smoke.mesh = _puff_mesh()
	smoke.color_ramp = _puff_fade()
	smoke.position.y = -0.5
	root.add_child(smoke)
	add_child(root)
	_launches.append({"node": root, "flame": flame, "light": light, "smoke": smoke, "at": at, "t": 0.0})


## A soft round puff of smoke facing the camera.
static var _puff: QuadMesh = null
static func _puff_mesh() -> QuadMesh:
	if _puff != null:
		return _puff
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_puff = QuadMesh.new()
	_puff.size = Vector2(2.0, 2.0)
	_puff.material = mat
	return _puff


## Light grey smoke that thins out as it spreads.
static func _puff_fade() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(0.92, 0.9, 0.86, 0.9))
	g.set_color(1, Color(0.8, 0.8, 0.8, 0.0))
	return g


func _update_launches(delta: float) -> void:
	var done: Array = []
	for l in _launches:
		l["t"] = float(l["t"]) + delta
		var t: float = l["t"]
		var root: Node3D = l["node"]
		var flame: MeshInstance3D = l["flame"]
		var light: OmniLight3D = l["light"]
		var smoke: CPUParticles3D = l["smoke"]
		var driven := bool(l.get("driven", false))
		var ignition := clampf(t / ENGINE_START, 0.0, 1.0)
		var burn := clampf(t - ENGINE_START, 0.0, 2.0)
		if driven:
			ignition = float(l["ign"])
			burn = clampf(float(l["h"]) / 10.0, 0.0, 2.0)
		var flicker := 0.85 + 0.15 * sin(t * 37.0)
		flame.scale = Vector3(ignition, ignition * (1.0 + 0.6 * burn), ignition) * flicker
		light.light_energy = 6.0 * ignition * flicker
		(root.get_child(0) as MeshInstance3D).set_instance_shader_parameter("f3d_glow", ignition)  # rocket-static-emission
		if driven:
			smoke.emitting = ignition > 0.05 and float(l["h"]) < 40.0
			root.position.y = float(l["h"])
			l["seen"] = float(l["seen"]) + delta
		else:
			smoke.emitting = t > 0.3 and t < ENGINE_START + 3.0
			# Up out of the shaft as the engines start (the silo's rocket waits down in it), then away.
			var climb := maxf(0.0, t - ENGINE_START)
			root.position.y = -Visuals.ROCKET_SINK * (1.0 - smoothstep(0.0, ENGINE_START, t)) + 0.5 * ACCELERATION * climb * climb
		_hide_rocket_mover(l["at"])
		# A driven rocket goes when the ride stops driving it (the pod changed surface).
		if (driven and float(l["seen"]) > 1.5) or (not driven and t >= FLIGHT_TIME):
			done.append(l)
	for l in done:
		(l["node"] as Node3D).queue_free()
		_launches.erase(l)


## The silo's own rocket mover stays hidden while ours flies.
func _hide_rocket_mover(at: Vector2) -> void:
	if movers == null:
		return
	for pair in movers.units_of_type("rocket-silo-rocket"):
		var node: Node3D = pair[1]
		if Vector2(node.position.x, node.position.z).distance_to(at) < 6.0:
			node.visible = false


# --- cargo pods -------------------------------------------------------------------------------

func _update_pods(delta: float) -> void:
	if movers == null:
		return
	var seen := {}
	for pair in movers.units_of_type("cargo-pod"):
		var unit: int = pair[0]
		var node: Node3D = pair[1]
		if unit == ridden:
			node.visible = false
			continue
		seen[unit] = true
		var info = model.cargo_pods.get(unit)
		var state := str(info.get("state", "")) if info is Dictionary else ""
		var p: Dictionary = _pods.get(unit, {})
		if p.is_empty() or p["state"] != state:
			p = {"state": state, "t": 0.0}
			_pods[unit] = p
		p["t"] = float(p["t"]) + delta
		var t: float = p["t"]
		var h := 0.0
		var ground: Vector3 = node.position
		if state == "ascending":
			# Factorio has no height: a rising pod moves north across the map. Its climb is that
			# northward travel, from where it set off (H2: it slid across the ground instead).
			if not p.has("from"):
				p["from"] = Vector3(ground.x, 0.0, ground.z)
			var from: Vector3 = p["from"]
			h = maxf(0.0, from.z - ground.z) + 0.5 * ASCENT_ACCELERATION * t * t
			node.position.x = from.x
			node.position.z = from.z
		elif state == "descending":
			var f := clampf(1.0 - t / DESCENT_TIME, 0.0, 1.0)
			h = DESCENT_HEIGHT * f * f
		node.position.y = h
		node.visible = h < 200.0
	for unit in _pods.keys():
		if not seen.has(unit):
			_pods.erase(unit)


# --- asteroid chunks --------------------------------------------------------------------------

func _on_chunks() -> void:
	# Each update (every 10 ticks) is matched to the chunks already drawn, so a chunk keeps its own
	# tumble and eases off the small gap between where it was drawn and where the game has it,
	# instead of snapping (F5).
	var now := Time.get_ticks_msec()
	var since := (now - _chunks_msec) / 1000.0
	var was := {}  # name -> [[drawn position, phase, sent position, measured velocity or null], ...]
	for name in _chunk_meshes:
		var drawn: Array = []
		for c: Dictionary in (_chunk_meshes[name] as MultiMeshInstance3D).get_meta("chunks", []):
			drawn.append([_chunk_at(c, since), float(c.get("phase", 0.0)), c["position"], c.get("measured")])
		was[name] = drawn
	_chunks_msec = now
	var by_name := {}
	for c: Dictionary in model.asteroid_chunks:
		var phase := fposmod(c["position"].x * 1.7 + c["position"].y * 3.1, TAU)
		var offset := Vector2.ZERO
		var best := MATCH_DISTANCE
		var match_d: Array = []
		for d: Array in was.get(c["name"], []):
			var gap: Vector2 = d[0] - c["position"]
			if gap.length() < best:
				best = gap.length()
				phase = d[1]
				offset = gap
				match_d = d
		# The sent movement assumes 60 UPS and leaves out a travelling platform's own drift, so
		# moving a chunk on by it left a gap at every update, closed six times a second (a stutter).
		# A chunk seen before moves on by how far it really went between updates, smoothed.
		if not match_d.is_empty() and since > 0.05:
			var measured: Vector2 = (c["position"] - (match_d[2] as Vector2)) / since
			if match_d[3] != null:
				measured = (match_d[3] as Vector2).lerp(measured, 0.4)
			c["measured"] = measured
			c["velocity"] = measured
		c["phase"] = phase
		c["offset"] = offset
		var list: Array = by_name.get(c["name"], [])
		list.append(c)
		by_name[c["name"]] = list
	for name in _chunk_meshes:
		if not by_name.has(name):
			(_chunk_meshes[name] as MultiMeshInstance3D).multimesh.visible_instance_count = 0
	for name in by_name:
		var mmi := _chunk_mesh(str(name))
		var list: Array = by_name[name]
		if mmi.multimesh.instance_count < list.size():
			mmi.multimesh.instance_count = maxi(list.size(), mmi.multimesh.instance_count * 2)
		mmi.multimesh.visible_instance_count = list.size()
		mmi.set_meta("chunks", list)
	_place_chunks()


## A chunk's mesh: the small asteroid of its kind ("metallic-asteroid-chunk" -> small-metallic-asteroid), scaled down.
func _chunk_mesh(name: String) -> MultiMeshInstance3D:
	if _chunk_meshes.has(name):
		return _chunk_meshes[name]
	var kind := name.trim_suffix("-asteroid-chunk")
	var mesh := ModelLibrary.mesh_for("small-%s-asteroid" % kind)
	if mesh == null:
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 0.9
		mesh = s
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 16
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	_chunk_meshes[name] = mmi
	return mmi


## Where a chunk is drawn `dt` seconds after its update: moved on by its velocity, with the gap to
## where it was drawn before fading out over a fraction of a second.
static func _chunk_at(c: Dictionary, dt: float) -> Vector2:
	var offset: Vector2 = c.get("offset", Vector2.ZERO)
	return c["position"] + c["velocity"] * dt + offset * exp(-dt * CHUNK_SETTLE)


func _place_chunks() -> void:
	var dt := (Time.get_ticks_msec() - _chunks_msec) / 1000.0
	var t := Time.get_ticks_msec() / 1000.0
	for name in _chunk_meshes:
		var mmi: MultiMeshInstance3D = _chunk_meshes[name]
		var list: Array = mmi.get_meta("chunks", [])
		for i in mini(list.size(), mmi.multimesh.visible_instance_count):
			var c: Dictionary = list[i]
			# A chunk an asteroid collector's arm holds is drawn in its claw (collectors.gd).
			if c.get("held", false):
				mmi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO))
				continue
			var p := _chunk_at(c, dt)
			var spin := Basis(Vector3(0.3, 1, 0.2).normalized(), t * 0.8 + float(c.get("phase", 0.0)))
			mmi.multimesh.set_instance_transform(i, Transform3D(spin.scaled(Vector3.ONE * CHUNK_SCALE), Vector3(p.x, CHUNK_HEIGHT, p.y)))


func _process(delta: float) -> void:
	_update_launches(delta)
	_update_pods(delta)
	_hide_flying_rockets()
	_place_chunks()


## The game's own rocket moves north across the map once it lifts off (Factorio draws its height
## that way); our launch draws the flight, so a rocket mover that has moved is hidden (H2: rockets
## slid across the ground away from their silos).
func _hide_flying_rockets() -> void:
	if movers == null:
		return
	var seen := {}
	for pair in movers.units_of_type("rocket-silo-rocket"):
		var unit: int = pair[0]
		var node: Node3D = pair[1]
		seen[unit] = true
		var at := Vector2(node.position.x, node.position.z)
		if not _rocket_start.has(unit):
			_rocket_start[unit] = at
		if at.distance_to(_rocket_start[unit]) > 0.5:
			node.visible = false
	for unit in _rocket_start.keys():
		if not seen.has(unit):
			_rocket_start.erase(unit)
