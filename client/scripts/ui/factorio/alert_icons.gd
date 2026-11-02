extends Node3D
## Factorio's alert pictures over the entities they are about (a turret out of ammo, a machine out
## of fuel or out of reach of poles, a ghost missing its material or robots, a train out of fuel...),
## blinking like the game's, on the character's surface. One MultiMesh per kind. "No power" isn't
## drawn here: fluids_power.gd draws it from `pw`.
##
## alerts.gd makes this and feeds it the mod's alert lists (the nearest of each kind).

const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
## Cut out with the depth test on: hidden behind buildings in front, and no blending order to swap
## (blended, they flickered against each other and the no-power icons). Shown with or without Alt-mode.
const IconShader := preload("res://shaders/billboard_icon_cut.gdshader")

## Kinds drawn over their entities: picture, blinking.
const DRAWN := {
	"no_ammo": ["ammo-icon-red.png", true], "no_fuel": ["fuel-icon-red.png", true],
	"unplugged": ["electricity-icon-unplugged.png", true], "no_material": ["no-building-material-icon.png", false],
	"no_robots": ["not-enough-construction-robots-icon.png", false], "no_repair": ["not-enough-repair-packs-icon.png", false],
	"train_fuel": ["fuel-icon-red.png", true], "train_path": ["no-path-icon.png", true],
	"collector": ["asteroid-collector-path-blocked-icon.png", true], "launch": ["destination-full-icon.png", true],
	"platform_storage": ["no-platform-storage-space-icon.png", true],
}
const SIZE := 1.0
const BLINK := 1.0

var world = null  # world.gd's mirror (entity heights), or null
var movers = null  # movers.gd (locomotives out of fuel), or null
var _meshes := {}  # kind -> MultiMeshInstance3D
## How many icons are drawn now, by kind (tests).
var shown := {}
## Where they are, by kind (tests).
var placed := {}


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for kind in DRAWN:
		var m := ShaderMaterial.new()
		m.shader = IconShader
		var t := GuiAssets.core_sprite("icons/alerts/" + str(DRAWN[kind][0]))
		if t == null:
			t = _disc(Color(0.9, 0.25, 0.15))
		m.set_shader_parameter("icon", t)
		m.set_shader_parameter("blink_period", BLINK if DRAWN[kind][1] else 0.0)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		_meshes[kind] = mmi


## lists: kind -> [{"position", "si", "unit", ...}]; si: the character's surface (0: unknown, draw all).
## An icon is drawn only over an entity the 3D world has: the mod's lists come from a
## pass over every surface that is seconds old, so a building mined, destroyed or on another surface
## (the remote view of another planet) would otherwise leave its icon over empty ground.
func show_alerts(lists: Dictionary, si: int) -> void:
	if _meshes.is_empty():
		return
	var power = get_parent().get_node_or_null("FluidsPower") if get_parent() != null else null
	for kind in DRAWN:
		var xforms: Array = []
		var at_list: Array = []
		for e in lists.get(kind, []):
			var at = _place(e, si, power)
			if at != null:
				at_list.append(at)
				xforms.append(Transform3D(Basis.from_scale(Vector3.ONE * SIZE), at))
		placed[kind] = at_list
		var mm: MultiMesh = (_meshes[kind] as MultiMeshInstance3D).multimesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		shown[kind] = xforms.size()


## Where an alert's icon goes, or null when the world doesn't hold its entity.
func _place(e: Dictionary, si: int, power) -> Variant:
	var unit := int(e.get("unit", 0))
	var p: Vector2 = e["position"]
	if world == null or unit == 0:
		# Nothing to check against (no world, or an entity without a unit number): the surface decides.
		if si != 0 and int(e.get("si", 0)) != 0 and int(e["si"]) != si:
			return null
		return Vector3(p.x, 1.6 + 0.3 + SIZE * 0.5, p.y)
	var rec = world.entities.get(unit)
	if rec != null:
		var top := 1.6
		if power != null and power.has_method("entity_top"):
			top = float(power.entity_top(rec))
		return Vector3(rec.pos.x, top + 0.3 + SIZE * 0.5, rec.pos.y)
	# Rolling stock is a mover, not part of the chunks.
	var m = movers.position_of(unit) if movers != null else null
	if m is Vector3:
		return Vector3(m.x, m.y + 2.8 + SIZE * 0.5, m.z)
	return null


static func _disc(color: Color) -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			image.set_pixel(x, y, color if Vector2(x - 15.5, y - 15.5).length() < 14.0 else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)
