extends Node3D
## Lamps at night. A lamp is lit when the mod reports it working (it has power) and it is dark
## enough, like Factorio's lamps; one the mod reports without power (`pw`) stays dark even if its
## working state is stale, and at low power it glows dimmer. Every lit lamp gets a glowing bulb;
## only the ones nearest the camera get a real light, since each light costs rendering time.

const ProtoDB := preload("res://scripts/world/protos.gd")

## Factorio's lamps switch on at about this darkness.
const ON_DARKNESS := 0.3
const MAX_LIGHTS := 48
const MAX_BULBS := 4096
const BULB_HEIGHT := 0.8
const REFRESH := 0.5

var protos: ProtoDB
## The world mirror: entities and machine working states.
var world: Node3D
## 0 in daylight, ~0.85 at night. Set by main from the `sky` messages.
var darkness := 0.0
var focus := Vector2.ZERO
## fluids_power.gd, for machines short of power (optional).
var power: Node
## The remote view's fog (remote_fog.gd): lamps no radar sees stay dark under it.
var fog: Node

var _lights: Array[OmniLight3D] = []
var _bulbs: MultiMeshInstance3D
var _timer := 0.0
var _lit := 0
## The lamps in each chunk (unit numbers), found again when a chunk's entities change: going
## through every machine's working state for the lamps among them took ~4 ms twice a second at night
## on the owner's save.
var _lamps := {}  # chunk -> Array of units
var _is_lamp := {}  # proto id -> bool


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 10
	mesh.rings = 5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.93, 0.7)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.55)
	m.emission_energy_multiplier = 3.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	_bulbs = MultiMeshInstance3D.new()
	_bulbs.multimesh = mm
	_bulbs.material_override = m
	_bulbs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bulbs)
	for i in MAX_LIGHTS:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.86, 0.6)
		light.light_energy = 1.6
		light.omni_range = 7.0
		light.visible = false
		add_child(light)
		_lights.append(light)
	if world != null and world.has_signal("entities_changed"):
		world.entities_changed.connect(_on_entities_changed)


func _on_entities_changed(c: Vector2i) -> void:
	var cv = world.chunks.get(c)
	if cv == null:
		_lamps.erase(c)
		return
	var units: Array = []
	for rec in cv.entities.values():
		var lamp = _is_lamp.get(rec.proto_id)
		if lamp == null:
			var proto: ProtoDB.EntityProto = protos.entity(rec.proto_id) if protos != null else null
			lamp = proto != null and proto.type == "lamp"
			_is_lamp[rec.proto_id] = lamp
		if lamp:
			units.append(rec.unit)
	if units.is_empty():
		_lamps.erase(c)
	else:
		_lamps[c] = units


func lit_count() -> int:
	return _lit


func _process(delta: float) -> void:
	_timer += delta
	if _timer < REFRESH:
		return
	_timer = 0.0
	var lit: Array[Vector2] = []
	var dim := {}  # positions of lamps at low power
	if darkness >= ON_DARKNESS and world != null and protos != null:
		for c in _lamps.keys():
			if not world.chunks.has(c):
				_lamps.erase(c)
				continue
			for unit in _lamps[c]:
				if int(world.working.get(unit, 0)) != 1:
					continue
				var rec = world.entities.get(unit)
				if rec == null or (fog != null and not fog.seen(rec.pos)):
					continue
				if power == null or not power.has_no_power(unit):
					lit.append(rec.pos)
					if power != null and power.power_state(unit) == 1:
						dim[rec.pos] = true
	var near := func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(focus) < b.distance_squared_to(focus)
	lit.sort_custom(near)
	_lit = mini(lit.size(), MAX_BULBS)
	var mm := _bulbs.multimesh
	if mm.instance_count < _lit:
		mm.instance_count = maxi(_lit, mm.instance_count * 2)
	mm.visible_instance_count = _lit
	for i in _lit:
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(lit[i].x, BULB_HEIGHT, lit[i].y)))
	for i in _lights.size():
		var light := _lights[i]
		light.visible = i < _lit
		if light.visible:
			light.position = Vector3(lit[i].x, BULB_HEIGHT + 0.6, lit[i].y)
			light.light_energy = 0.7 if dim.has(lit[i]) else 1.6
