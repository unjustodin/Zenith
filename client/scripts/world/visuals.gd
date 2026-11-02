extends RefCounted
## Shared placeholder meshes and materials, and the shape rules for entities that don't have a
## 3D model yet. A placeholder is the entity's selection box extruded to a height that suits
## its type, tinted with its map colour.

const ProtoDB := preload("res://scripts/world/protos.gd")
const TerrainShader := preload("res://shaders/terrain.gdshader")
const WaterShader := preload("res://shaders/water.gdshader")

## Placeholder height in tiles, by entity type.
const HEIGHTS := {
	"transport-belt": 0.15, "underground-belt": 0.45, "splitter": 0.35, "lane-splitter": 0.35,
	"loader": 0.4, "loader-1x1": 0.4, "linked-belt": 0.4,
	"inserter": 0.3, "pipe": 0.4, "pipe-to-ground": 0.45, "pump": 0.6, "heat-pipe": 0.25, "valve": 0.5,
	"straight-rail": 0.12, "half-diagonal-rail": 0.12, "curved-rail-a": 0.12, "curved-rail-b": 0.12,
	"legacy-straight-rail": 0.12, "legacy-curved-rail": 0.12, "rail-signal": 1.6, "rail-chain-signal": 1.6,
	"train-stop": 2.2, "electric-pole": 3.0, "lamp": 0.7, "power-switch": 0.8,
	"container": 0.8, "logistic-container": 0.8, "linked-container": 0.8, "infinity-container": 0.8,
	"assembling-machine": 2.2, "furnace": 1.6, "mining-drill": 1.4, "lab": 1.6, "boiler": 1.6,
	"generator": 2.0, "burner-generator": 1.6, "offshore-pump": 0.8, "storage-tank": 2.4, "radar": 2.6,
	"roboport": 2.6, "beacon": 2.0, "solar-panel": 0.5, "accumulator": 1.6, "reactor": 2.2,
	"rocket-silo": 4.0, "ammo-turret": 1.4, "electric-turret": 1.6, "fluid-turret": 1.4,
	"artillery-turret": 2.0, "turret": 1.2, "wall": 1.4, "gate": 1.2, "land-mine": 0.1,
	"arithmetic-combinator": 0.6, "decider-combinator": 0.6, "constant-combinator": 0.6,
	"selector-combinator": 0.6, "programmable-speaker": 1.4, "display-panel": 0.6,
	"tree": 3.0, "plant": 2.0, "simple-entity": 1.2, "simple-entity-with-owner": 1.0,
	"simple-entity-with-force": 1.0, "cliff": 2.5, "fish": 0.1, "resource": 0.15,
	"unit-spawner": 2.0, "market": 1.6, "agricultural-tower": 2.5,
	"unit": 0.9, "character": 1.7, "car": 1.4, "spider-vehicle": 2.0, "locomotive": 2.2,
	"cargo-wagon": 2.0, "fluid-wagon": 2.0, "artillery-wagon": 2.2,
	"logistic-robot": 0.4, "construction-robot": 0.4, "combat-robot": 0.4, "capture-robot": 0.4,
	"asteroid": 1.0, "spider-unit": 1.5, "segmented-unit": 1.5, "segment": 1.5,
}

## Types drawn as cones (canopies) instead of boxes.
const CONE_TYPES := {"tree": true, "plant": true}
## Types that fly: drawn this high above the ground.
## Logistic and construction robots: their model's middle (about 0.3 up) at the 1.5 tiles that
## lifts them the one tile up the screen Factorio draws them.
## How far a waiting rocket's base sits below the ground (its model is 16.9 tiles tall).
const ROCKET_SINK := 14.0
## Heights movers are drawn at by type. Robots fly well above the buildings, as Factorio draws them
## (H11: at 1.2 they skimmed the machines). A rocket waiting in its silo stands down in the shaft with
## only its nose in the open hatch (H6: at the ground it towered 17 tiles over the silo); rockets.gd
## starts a launch from there.
const FLYING := {"logistic-robot": 2.2, "construction-robot": 2.2, "combat-robot": 2.4, "capture-robot": 2.6,
	"rocket-silo-rocket": -ROCKET_SINK}
## Placeholders are drawn slightly smaller than their box so neighbours stay distinguishable.
const SHRINK := 0.92

static var _box: BoxMesh
static var _cone: CylinderMesh
static var _instance_material: StandardMaterial3D
static var _terrain_material: ShaderMaterial
static var _water_material: ShaderMaterial


static func height_for(proto: ProtoDB.EntityProto) -> float:
	if HEIGHTS.has(proto.type):
		return HEIGHTS[proto.type]
	var s := proto.size()
	return clampf(minf(s.x, s.y) * 0.6, 0.3, 3.0)


static func flying_height(type: String) -> float:
	return FLYING.get(type, 0.0)


## Ore patches: flat at low amounts, taller where the patch is rich.
static func resource_height(amount: int) -> float:
	var richness := clampf(log(maxf(amount, 1.0)) / log(10000.0), 0.0, 1.0)
	return 0.05 + 0.3 * richness


static func is_cone(proto: ProtoDB.EntityProto) -> bool:
	return CONE_TYPES.has(proto.type)


## Unit box, centred on the origin.
static func box_mesh() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	return _box


## Unit cone, centred on the origin.
static func cone_mesh() -> CylinderMesh:
	if _cone == null:
		_cone = CylinderMesh.new()
		_cone.top_radius = 0.0
		_cone.bottom_radius = 0.5
		_cone.height = 1.0
		_cone.radial_segments = 10
		_cone.rings = 1
	return _cone


## Takes its albedo from the per-instance colour of a MultiMesh.
static func instance_material() -> StandardMaterial3D:
	if _instance_material == null:
		_instance_material = StandardMaterial3D.new()
		_instance_material.vertex_color_use_as_albedo = true
		_instance_material.roughness = 0.85
	return _instance_material


## Land tiles: Factorio's tile pictures when terrain_textures.gd has them, else the tile's map
## colour (vertex colour) with procedural detail on top.
static func terrain_material() -> ShaderMaterial:
	if _terrain_material == null:
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = TerrainShader
	return _terrain_material


## Water tiles: animated ripples and shore foam (vertex alpha marks corners touching land).
static func water_material() -> ShaderMaterial:
	if _water_material == null:
		_water_material = ShaderMaterial.new()
		_water_material.shader = WaterShader
	return _water_material


static func solid_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	return m


static func ghost_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m


## Yaw for a Factorio direction (0..15, north = 0, clockwise). Models face north (-Z).
static func direction_yaw(direction: int) -> float:
	return -float(direction) / 16.0 * TAU


## Yaw for a Factorio orientation (0..1, north = 0, clockwise).
static func orientation_yaw(orientation: float) -> float:
	return -orientation * TAU


## Transform of a placeholder for `proto` at `pos` (tiles), facing `direction`, `height` tall.
static func placeholder_transform(proto: ProtoDB.EntityProto, pos: Vector2, direction: int, height: float) -> Transform3D:
	var yaw := direction_yaw(direction)
	var size := proto.size() * SHRINK
	var c := proto.center()
	var turn := Basis(Vector3.UP, yaw)
	var origin := Vector3(pos.x, 0.0, pos.y) + turn * Vector3(c.x, height * 0.5, c.y)
	return Transform3D(turn * Basis.from_scale(Vector3(size.x, height, size.y)), origin)
