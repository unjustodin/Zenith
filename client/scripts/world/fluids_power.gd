extends Node3D
## Fluids and power from the mod: what is in each fluid box near the camera (`fl`) and which
## machines are short of power (`pw`), shown the way Factorio shows them: a blinking red
## lightning icon over a machine with no power, a level window on storage tanks in the fluid's
## colour, and a line under the cursor naming the hovered entity's fluid and amount. Low power
## has no icon, as in Factorio (a brownout only slows machines; the entity info says "Low power"):
## drawing one put lightning over machines Factorio shows as fine. Machines no pole reaches get
## Factorio's unplugged icon from the alerts (alert_icons.gd). Wires between poles are wires.gd.

const WorldMirror := preload("res://scripts/world/world.gd")
const ProtoDB := preload("res://scripts/world/protos.gd")
const Visuals := preload("res://scripts/world/visuals.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")
## The red no-power alert, depth tested like alert_icons.gd's (no flicker, hidden behind buildings).
const IconShader := preload("res://shaders/billboard_icon_cut.gdshader")

const NO_POWER := 0
## Low power: no icon (Factorio draws none), but the entity info's status and dimmer lamps.
const LOW_POWER := 1
## Not connected to any pole: alert_icons.gd draws Factorio's unplugged icon from the alerts.
const NOT_CONNECTED := 2
## Factorio draws its 64-pixel alert pictures at half size: 32 pixels, one tile.
const ICON_SIZE := 1.0
## Factorio's no-power icon blinks: seconds per blink.
const BLINK := 1.0
## A storage tank's window: width and height in tiles, and how far up its middle is, as a
## share of the tank's height.
const WINDOW_SIZE := Vector2(0.42, 1.1)
const WINDOW_MIDDLE := 0.5

var world: WorldMirror
## The player input, for the hovered entity (`hovered`).
var input: Node
## unit -> [{"box", "fluid", "amount", "capacity", "temperature"}, ...]
var fluids := {}
## unit -> 0 (no power), 1 (low power) or 2 (not connected); machines with enough power aren't listed.
var unpowered := {}
## unit -> temperature (°C) of heat pipes, reactors and heat interfaces (`ht`).
var heat := {}

var _incoming := {"fl": {}, "pw": {}, "ht": {}}
var _frame := {"fl": -1, "pw": -1, "ht": -1}
var _icons: MultiMeshInstance3D  # the no-power icons
## Where the no-power icons are drawn (tests).
var icon_spots: Array[Transform3D] = []
var _windows: MultiMeshInstance3D
var _label := Label.new()
var _visuals_dirty := false
var _model_generation := -1

static var _core_textures := {}  # path under data/ -> Texture2D or null


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := ShaderMaterial.new()
	m.shader = IconShader
	var texture := core_texture("core/graphics/icons/alerts/electricity-icon-red.png")
	m.set_shader_parameter("icon", texture if texture != null else _fallback_texture(Color(0.9, 0.2, 0.15)))
	m.set_shader_parameter("blink_period", BLINK)
	_icons = _multimesh(quad, m, false)

	var window := BoxMesh.new()
	window.size = Vector3.ONE
	var glass := StandardMaterial3D.new()
	glass.vertex_color_use_as_albedo = true
	glass.roughness = 0.25
	glass.metallic = 0.2
	_windows = _multimesh(window, glass, true)

	var layer := CanvasLayer.new()
	add_child(layer)
	_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.visible = false
	layer.add_child(_label)


func _multimesh(mesh: Mesh, material: Material, colors: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func reset() -> void:
	fluids.clear()
	unpowered.clear()
	heat.clear()
	for t in _frame:
		_frame[t] = -1
		_incoming[t] = {}
	_visuals_dirty = true


## True when the machine has no power or isn't connected (low power counts as powered, dimly).
func has_no_power(unit: int) -> bool:
	var state := int(unpowered.get(unit, -1))
	return state == NO_POWER or state == NOT_CONNECTED


func power_state(unit: int) -> int:
	return int(unpowered.get(unit, -1))


## One part of `fl` ([unit, box, fluid id, amount, capacity, temperature, ...]), `pw`
## ([unit, 0|1|2, ...]) or `ht` ([unit, temperature, ...]); a complete update replaces the last.
func handle(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	if not _frame.has(t):
		return
	var k := int(msg.get("k", 0))
	if k != int(_frame[t]):
		_frame[t] = k
		_incoming[t] = {}
	var into: Dictionary = _incoming[t]
	var list = msg.get("l")
	if list is Array:
		if t == "fl":
			var i := 0
			while i + 5 < list.size():
				var unit := int(list[i])
				if not into.has(unit):
					into[unit] = []
				(into[unit] as Array).append({"box": int(list[i + 1]), "fluid": world.protos.fluid_name(int(list[i + 2])),
					"amount": int(list[i + 3]), "capacity": int(list[i + 4]), "temperature": int(list[i + 5])})
				i += 6
		else:
			var i := 0
			while i + 1 < list.size():
				into[int(list[i])] = int(list[i + 1])
				i += 2
	if int(msg.get("part", 1)) < int(msg.get("parts", 1)):
		return
	if t == "fl":
		fluids = into
	elif t == "ht":
		heat = into
	else:
		unpowered = into
	_incoming[t] = {}
	_visuals_dirty = true


func _process(_delta: float) -> void:
	if world == null:
		return
	if _model_generation != ModelLibrary.generation:
		_model_generation = ModelLibrary.generation  # tops of models that were still being made
		_visuals_dirty = true
	if _visuals_dirty:
		_visuals_dirty = false
		_update_icons()
		_update_windows()
	_update_label()


## Icons sit just above the machine, like Factorio's alerts over the entity; only for no power.
func _update_icons() -> void:
	var list: Array[Transform3D] = []
	for unit in unpowered:
		var rec: WorldMirror.Rec = world.entities.get(unit)
		if rec == null or int(unpowered[unit]) != NO_POWER:
			continue
		var top := entity_top(rec)
		list.append(Transform3D(Basis.from_scale(Vector3.ONE * ICON_SIZE), Vector3(rec.pos.x, top + 0.25 + ICON_SIZE * 0.5, rec.pos.y)))
	icon_spots = list
	var mm := _icons.multimesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])


## How many no-power icons are drawn (tests).
func icon_count() -> int:
	return _icons.multimesh.instance_count if _icons != null else 0


## Storage tanks show how full they are through a window on their south face (the side the
## camera looks at), the fluid's colour rising behind dark glass.
func _update_windows() -> void:
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	for unit in fluids:
		var rec: WorldMirror.Rec = world.entities.get(unit)
		if rec == null:
			continue
		var proto: ProtoDB.EntityProto = world.protos.entity(rec.proto_id)
		if proto == null or proto.type != "storage-tank":
			continue
		var box: Dictionary = (fluids[unit] as Array)[0]
		var fill := clampf(float(box["amount"]) / maxf(float(box["capacity"]), 1.0), 0.0, 1.0)
		var top := entity_top(rec)
		var face := _south_face(rec, proto)
		var middle := top * WINDOW_MIDDLE
		var size := Vector2(WINDOW_SIZE.x, minf(WINDOW_SIZE.y, top * 0.6))
		var at := Vector3(rec.pos.x, middle, face)
		xforms.append(Transform3D(Basis.from_scale(Vector3(size.x + 0.08, size.y + 0.08, 0.03)), at))
		colors.append(Color(0.08, 0.09, 0.1))
		if fill > 0.0:
			var h := size.y * fill
			var fluid_color: Color = world.protos.fluid_colors.get(str(box["fluid"]), Color(0.3, 0.5, 0.8))
			xforms.append(Transform3D(Basis.from_scale(Vector3(size.x, h, 0.03)), at + Vector3(0.0, (h - size.y) * 0.5, 0.012)))
			# Dark fluids (crude oil) stay dark but still read against the black glass.
			colors.append(fluid_color.lerp(Color.WHITE, 0.08))
	var mm := _windows.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])


func _south_face(rec: WorldMirror.Rec, proto: ProtoDB.EntityProto) -> float:
	var mesh := world.ready_mesh(proto, rec)
	if mesh != null:
		return rec.pos.y + mesh.get_aabb().end.z + 0.02
	var rect := WorldMirror.selection_rect(proto, rec.pos, rec.dir)
	return rect.end.y - rect.size.y * (1.0 - Visuals.SHRINK) * 0.5 + 0.02


## The hovered entity's fluid and power, by the cursor, like the lines in Factorio's entity info.
func _update_label() -> void:
	var rec: WorldMirror.Rec = input.get("hovered") if input != null else null
	if rec == null or rec.unit == 0:
		_label.visible = false
		return
	var lines: PackedStringArray = []
	for box in fluids.get(rec.unit, []):
		var line := "%s: %s / %s" % [LocaleNames.item(str(box["fluid"])), _amount(int(box["amount"])), _amount(int(box["capacity"]))]
		if int(box["temperature"]) != 15:
			line += " at %d °C" % int(box["temperature"])
		lines.append(line)
	if heat.has(rec.unit):
		lines.append("Temperature: %d °C" % int(heat[rec.unit]))
	# Power is the entity info's status line, as in Factorio (entity_info.gd), not this one.
	if lines.is_empty():
		_label.visible = false
		return
	_label.text = "\n".join(lines)
	_label.position = get_viewport().get_mouse_position() + Vector2(18, 18)
	_label.visible = true


## Like Factorio's fluid amounts: 180, 1.5k, 25k.
static func _amount(n: int) -> String:
	if n < 1000:
		return str(n)
	return ("%.1f" % (n / 1000.0)).trim_suffix(".0") + "k"


## The top of the entity as drawn: its model, or its placeholder box.
func entity_top(rec: WorldMirror.Rec) -> float:
	var proto: ProtoDB.EntityProto = world.protos.entity(rec.proto_id)
	if proto == null:
		return 1.0
	var mesh := world.ready_mesh(proto, rec)
	if mesh != null:
		return mesh.get_aabb().end.y
	return Visuals.height_for(proto)


## A texture from Factorio's own data folder (`core/graphics/...`), read at runtime from the
## player's install like item icons; null without one. Icons that carry their smaller mipmaps
## to the right (a 120x64 image) are cut to the square on the left.
static func core_texture(path: String) -> Texture2D:
	if _core_textures.has(path):
		return _core_textures[path]
	var texture: Texture2D = null
	var dir := ItemIcons.factorio_data_dir()
	if dir != "" and FileAccess.file_exists(dir.path_join(path)):
		var image := Image.load_from_file(dir.path_join(path))
		if image != null:
			image.convert(Image.FORMAT_RGBA8)
			var h := image.get_height()
			if image.get_width() > h * 3 / 2:
				image = image.get_region(Rect2i(0, 0, h, h))
			image.fix_alpha_edges()  # as GuiAssets: no dark rim in the smaller mipmaps
			image.generate_mipmaps()
			texture = ImageTexture.create_from_image(image)
	_core_textures[path] = texture
	return texture


## Without a Factorio install: a plain disc in the icon's colour.
static func _fallback_texture(color: Color) -> Texture2D:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length()
			image.set_pixel(x, y, color if d < 14.0 else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)
