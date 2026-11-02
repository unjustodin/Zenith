extends Control
## Factorio's Alt-mode (Alt): over each machine near the camera the icon of what it is set to make
## or let through (an assembler's or furnace's recipe, an inserter's, splitter's or storage chest's
## filter), from the mod's `ai` (ui_model.alt_icons), and on every pipe, underground pipe, pump and
## tank the icon of the fluid in it (fluids_power.gd's `fl`). As in Factorio the icons have no
## disc behind them, only a soft dark shadow, and are drawn flat over the world at the entity's
## position projected through the camera, sized with the zoom.
##
## factorio_ui.gd sets `player` (player_input.gd: its world mirror and camera rig).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const WorldMirror := preload("res://scripts/world/world.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const DepthIcon := preload("res://shaders/billboard_icon_depth.gdshader")

## The icon is this many tiles across (measured on Factorio's alt-mode over assemblers).
const ICON_TILES := 1.2
## A fluid's icon on a pipe.
const FLUID_TILES := 0.55
const FLUID_TYPES := ["pipe", "pipe-to-ground", "pump", "storage-tank", "infinity-pipe"]
const SHADOW := Color(0, 0, 0, 0.6)

var model
var player: Node = null
var on := false

var _shadow: Texture2D
## First person: the icons as 3D quads with the depth test on, so buildings in front hide them
## (from above, nothing stands between the camera and an icon). Pooled; a material per picture.
var _quads: Array[MeshInstance3D] = []
var _quad_holder: Node3D
var _quad_materials := {}  # Texture2D -> ShaderMaterial
var _quads_used := 0
## The remote view's fog (the player's remote_fog): no icons for what no radar sees.
var _fog: Node = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = Kit.ICON_FILTER
	# Factorio's icon shadow: a soft dark blur, darkest in the middle.
	var g := Gradient.new()
	g.set_color(0, SHADOW)
	g.set_color(1, Color(0, 0, 0, 0))
	g.add_point(0.55, Color(0, 0, 0, SHADOW.a * 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_shadow = t


func _process(_delta: float) -> void:
	if on:
		queue_redraw()
	elif _quads_used > 0 or (not _quads.is_empty() and _quads[0].visible):
		_quads_used = 0
		_hide_quads()


func _draw() -> void:
	_quads_used = 0
	if not on or model == null or player == null:
		_hide_quads()
		return
	var world = player.get("world")
	var rig = player.get("rig")
	if world == null or rig == null:
		_hide_quads()
		return
	var camera: Camera3D = rig.camera
	_in_3d = bool(rig.get("first_person"))
	_fog = player.get("remote_fog")
	for unit in model.alt_icons:
		var icon: Array = model.alt_icons[unit]
		var textures: Array[Texture2D] = []
		for i in range(1, icon.size()):  # a filter inserter's filters, every one
			textures.append(Kit.item_icon(str(icon[i])))
		_draw_icon(world, camera, unit, textures, ICON_TILES)
	var parent: Node = world.get_parent()
	var fluids_layer = parent.get_node_or_null("FluidsPower") if parent != null else null
	if fluids_layer == null:
		_hide_quads()
		return
	for unit in fluids_layer.fluids:
		var r: WorldMirror.Rec = world.entities.get(unit)
		if r == null:
			continue
		var proto = world.protos.entity(r.proto_id)
		if proto == null or not FLUID_TYPES.has(proto.type):
			continue
		var boxes: Array = fluids_layer.fluids[unit]
		for b in boxes:
			var fluid := str(b.get("fluid", ""))
			if fluid != "" and float(b.get("amount", 0.0)) > 0.0:
				_draw_icon(world, camera, unit, [Kit.item_icon(fluid)], FLUID_TILES)
				break
	_hide_quads()


## Cells of a grid for `n` icons in a square of side 1 (top-left corners and the cell's side), as
## Factorio fits a filter inserter's filters into the one icon's room: 2 side by side, 3 and 4 in a
## 2 x 2 square, 5 in 3 + 2; a last row that isn't full is centred.
static func grid(n: int) -> Array:
	var cols := ceili(sqrt(float(n)))
	var rows := ceili(float(n) / cols)
	var cell := 1.0 / maxi(cols, rows)
	var top := (1.0 - rows * cell) * 0.5
	var out := []
	for i in n:
		var row := i / cols
		var in_row := mini(cols, n - row * cols)
		var left := (1.0 - in_row * cell) * 0.5
		out.append([Vector2(left + (i % cols) * cell, top + row * cell), cell])
	return out


func _draw_icon(world, camera: Camera3D, unit, textures: Array[Texture2D], tiles: float) -> void:
	var r: WorldMirror.Rec = world.entities.get(unit)
	if r == null or textures.is_empty():
		return
	var proto = world.protos.entity(r.proto_id)
	if proto == null:
		return
	var c: Vector2 = WorldMirror.selection_rect(proto, r.pos, r.dir).get_center()
	if _fog != null and not _fog.seen(c):
		return
	var at := Vector3(c.x, Visuals.height_for(proto), c.y)
	if _in_3d:
		_place_quads(world, camera, at + Vector3(0, tiles * 0.5, 0), textures, tiles)
		return
	if camera.is_position_behind(at):
		return
	var p := camera.unproject_position(at)
	var edge := camera.unproject_position(at + camera.global_basis.x * tiles * 0.5)
	var half := clampf(p.distance_to(edge), Kit.px(4), Kit.px(40))
	var cells := grid(textures.size())
	for i in textures.size():
		if textures[i] == null:
			continue
		var side: float = half * 2.0 * float(cells[i][1])
		var corner: Vector2 = p - Vector2(half, half) + (cells[i][0] as Vector2) * half * 2.0
		var s := side * 0.65
		var mid := corner + Vector2(side, side) * 0.5
		draw_texture_rect(_shadow, Rect2(mid - Vector2(s, s), Vector2(s, s) * 2.0), false)
		draw_texture_rect(textures[i], Rect2(corner, Vector2(side, side)), false)


var _in_3d := false


## First person: the icons over `top` as camera-facing quads in the world, in the same grid.
func _place_quads(world, camera: Camera3D, top: Vector3, textures: Array[Texture2D], tiles: float) -> void:
	if _quad_holder == null or not is_instance_valid(_quad_holder):
		_quad_holder = Node3D.new()
		_quad_holder.name = "AltIcons3D"
		(world as Node).get_parent().add_child(_quad_holder)
		_quads.clear()
	var right := camera.global_basis.x
	var up := camera.global_basis.y
	var cells := grid(textures.size())
	for i in textures.size():
		if textures[i] == null:
			continue
		if _quads_used >= _quads.size():
			var q := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2.ONE
			q.mesh = mesh
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_quad_holder.add_child(q)
			_quads.append(q)
		var q := _quads[_quads_used]
		_quads_used += 1
		var side: float = tiles * float(cells[i][1])
		var mid: Vector2 = (cells[i][0] as Vector2) + Vector2(cells[i][1], cells[i][1]) * 0.5 - Vector2(0.5, 0.5)
		q.position = top + right * mid.x * tiles - up * mid.y * tiles
		q.scale = Vector3(side, side, side)
		q.material_override = _quad_material(textures[i])
		q.visible = true


func _quad_material(texture: Texture2D) -> ShaderMaterial:
	var m: ShaderMaterial = _quad_materials.get(texture)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = DepthIcon
		m.set_shader_parameter("icon", texture)
		_quad_materials[texture] = m
	return m


## Hides the quads this frame didn't use (all of them out of first person).
func _hide_quads() -> void:
	for i in range(_quads_used, _quads.size()):
		_quads[i].visible = false
