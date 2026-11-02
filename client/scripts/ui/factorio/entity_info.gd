extends PanelContainer
## Factorio's entity info panel on the right of the screen: what the mouse is over in the world,
## with its name, quality, health, working state, recipe (when Alt-mode or a screen told us),
## train stop name (rich text), ore left, ghost (with the item it needs and how many the inventory has)
## and deconstruction / upgrade marks, then the entity's stats from Factoriopedia's data (crafting
## speed, energy, pollution, health, resistances, module slots...), as Factorio's tooltips list them. factorio_ui.gd places it
## under the minimap and calls show_entity() every frame with the hovered entity (or null).
##
## Laid out as Factorio 2.1's (measured on tools/ui_reference/hover.py's pictures): as wide as the
## side menu (256) and flush with it, a picture of the entity on a dark strip (its icon here, where
## Factorio films it), the name on the tooltip's cream title bar, a status dot and word, then the
## lines; no key hints.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const WorldMirror := preload("res://scripts/world/world.gd")
const Info := preload("res://scripts/ui/factorio/info_text.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")

const WIDTH := 256  # the side menu's width: Factorio's panel sits flush under it
const PICTURE := 96
## Entities whose modules and beacons the mod is asked about (`hinfo`).
const EFFECT_TYPES := ["beacon", "assembling-machine", "furnace", "mining-drill", "lab", "rocket-silo"]
const EFFECT_NAMES := [["sp", "Speed"], ["pr", "Productivity"], ["co", "Consumption"], ["po", "Pollution"], ["q", "Quality"]]
## The "Consumes electricity" heading and the Electricity bar, sampled from Factorio's panel.
const HEADING := Color(1.0, 211 / 255.0, 73 / 255.0)
const BAR := Color(40 / 255.0, 209 / 255.0, 36 / 255.0)
## fluids_power.gd's power states (`pw`) as Factorio's status line words them.
const POWER_STATUS := {0: ["No power", "red"], 1: ["Low power", "yellow"], 2: ["Not plugged in electric network", "red"]}

var model
var player: Node = null

var _title: Label
var _icon: TextureRect
var _status: Label
var _dot: TextureRect
var _lines := VBoxContainer.new()
var _health: ProgressBar
var _key := ""


func _ready() -> void:
	theme_type_variation = "FTooltip"
	add_theme_stylebox_override("panel", Kit.style_with_margins("tooltip", 4, 4, 4, 6))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = Kit.px(WIDTH)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	# the picture: Factorio films the entity; the client shows its icon on the same dark strip
	var picture := Kit.panel("FDeepFrame")
	picture.custom_minimum_size.y = Kit.px(PICTURE)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Kit.pxv(64, 64)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.texture_filter = Kit.ICON_FILTER
	picture.add_child(_icon)
	var head := Kit.panel("FTooltipTitle")
	box.add_child(head)
	_title = Kit.label("", "FTooltipTitleLabel")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = Kit.px(WIDTH - 28)
	head.add_child(_title)
	var body := MarginContainer.new()
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, Kit.px(6))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Kit.px(2))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(column)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", Kit.px(6))
	column.add_child(status)
	_dot = TextureRect.new()
	_dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dot.custom_minimum_size = Kit.pxv(14, 14)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.add_child(_dot)
	_status = Kit.label("")
	status.add_child(_status)
	# Factorio shows health as a line; the bar is kept for nothing but compatibility
	_health = Kit.progress_bar(Color(0.1, 0.9, 0.1))
	_health.max_value = 1000
	_health.visible = false
	_lines.add_theme_constant_override("separation", Kit.px(2))
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_lines)


## The hovered entity (a world record) or null.
func show_entity(r) -> void:
	if r == null or player == null:
		visible = false
		_key = ""
		return
	var world = player.get("world")
	var proto = world.protos.entity(r.proto_id) if world != null else null
	if proto == null:
		visible = false
		return
	var health := _health_of(r)
	var working := int(world.working.get(r.unit, -1)) if r.unit > 0 else -1
	var icon: Array = model.alt_icons.get(r.unit, []) if model != null and r.unit > 0 else []
	var inner_name: String = proto.name
	if proto.type == "entity-ghost" and r.extra.has("gh") and world.protos.entity(int(r.extra["gh"])) != null:
		inner_name = world.protos.entity(int(r.extra["gh"])).name
	var stats: Dictionary = model.pedia_data("entity", inner_name) if model != null else {}
	var electric: bool = str(stats.get("etype", "")) == "electric" and proto.type != "entity-ghost"
	var effects := {}
	if model != null and r.unit > 0 and (proto.type in EFFECT_TYPES or electric):
		model.ask_hover_info(r.unit, r.proto_id, r.fixed)
		if int(model.hover_info.get("u", 0)) == r.unit:
			effects = model.hover_info
	var power := _power_state(r)
	var key := "%s|%s|%s|%s|%s|%d|%s|%d" % [str(r.key), JSON.stringify(r.extra), health, working, JSON.stringify(icon), stats.size(),
		JSON.stringify(effects), power]
	visible = true
	if key == _key:
		return
	_key = key
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	var shown_name: String = proto.name
	if proto.type == "entity-ghost" and r.extra.has("gh"):
		var inner = world.protos.entity(int(r.extra["gh"]))
		if inner != null:
			shown_name = inner.name
		_line("Ghost: robots will build it", Kit.DISABLED_TEXT)
		var item := _item_for(world, shown_name)
		if item != "":
			var have: int = model.count_of(item) if model != null else 0
			_line("Needs: %s (you have %d)" % [Kit.pretty(item), have], Kit.GREEN_TEXT if have > 0 else Kit.RED_TEXT, item)
	_title.text = Kit.entity_name(shown_name)
	_icon.texture = Kit.item_icon(shown_name)
	if r.extra.has("q"):
		_line("Quality: %s" % str(r.extra["q"]).capitalize(), Kit.YELLOW_TEXT)
	_health.value = roundi(maxf(health, 0.0) * 1000.0)
	# Factorio's status: a coloured dot and the word; short of power says so, as Factorio's does
	_status.get_parent().visible = working >= 0 or power >= 0
	if power >= 0:
		_status.text = POWER_STATUS[power][0]
		_dot.texture = GuiAssets.status_dot(POWER_STATUS[power][1])
	elif working >= 0:
		_status.text = "Working" if working == 1 else "Not working"
		_dot.texture = GuiAssets.status_dot("green" if working == 1 else "yellow")
	if icon.size() >= 2:
		_line(("Recipe: " if icon[0] == "recipe" else "Filter: ") + (Kit.recipe_name(str(icon[1])) if icon[0] == "recipe" else Kit.pretty(str(icon[1]))))
	if r.extra.has("a"):
		_line("Remaining: %s" % Kit.count_text(int(r.extra["a"])))
	if r.extra.has("n"):
		var station := RichText.label("Station: " + str(r.extra["n"]), Kit.WHITE)
		station.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lines.add_child(station)
	if r.extra.has("d"):
		_line("Marked for deconstruction", Kit.RED_TEXT)
	if r.extra.has("up"):
		var target = world.protos.entity(int(r.extra["up"]))
		_line("To be upgraded to %s" % (Kit.entity_name(target.name) if target != null else "?"), Kit.GREEN_TEXT)
	_effect_lines(effects, proto.type == "beacon")
	var health_shown := false
	for line in Info.entity_lines(stats):
		if str(line[0]).begins_with("Size"):
			continue
		if electric and (str(line[0]).begins_with("Energy consumption") or str(line[0]).begins_with("Drain")):
			continue  # under "Consumes electricity" below, as Factorio has them
		if str(line[0]).begins_with("Health") and health >= 0.0 and stats.has("hp"):
			# the current health over the most, as Factorio's panel has it
			_line("Health: %d/%d" % [roundi(health * float(stats["hp"])), roundi(float(stats["hp"]))])
			health_shown = true
			continue
		_line(str(line[0]), line[2] if line.size() > 2 else Kit.WHITE)
	if not health_shown and health >= 0.0 and health < 1.0:
		_line("Health: %d%%" % roundi(health * 100.0))
	if electric:
		_electricity(stats, effects.get("el", {}))
	reset_size()


## Factorio's "Consumes electricity" part at the foot of the panel (H20): a rule across, the
## lightning and the yellow heading over a fainter rule, Max. and Min. consumption (the mod's live
## figures with modules and beacons, else the prototype's), and the Electricity bar: the machine's
## buffer, full when it has all the power it wants.
func _electricity(stats: Dictionary, el: Dictionary) -> void:
	var most := float(el.get("mx", stats.get("energy", 0.0)))
	var least := float(el.get("mn", stats.get("drain", 0.0)))
	if most <= 0.0 and el.is_empty():
		return
	_lines.add_child(_rule(Color(0.03, 0.02, 0.02), Color(0.45, 0.4, 0.33), Kit.px(3)))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Kit.px(6))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bolt := TextureRect.new()
	bolt.texture = _bolt_icon()
	bolt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bolt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bolt.custom_minimum_size = Kit.pxv(16, 16)
	bolt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bolt.texture_filter = Kit.ICON_FILTER
	head.add_child(bolt)
	var title := Kit.label("Consumes electricity", "FHeading")
	title.add_theme_color_override("font_color", HEADING)
	head.add_child(title)
	_lines.add_child(head)
	_lines.add_child(_rule(Color(0.23, 0.22, 0.2), Color(0, 0, 0, 0), 1))
	_line("Max. consumption: %s" % power_text(most))
	if least > 0.0:
		_line("Min. consumption: %s" % power_text(least))
	if el.has("b") and float(el["b"]) > 0.0:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(6))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Kit.label("Electricity:")
		label.add_theme_font_override("font", Kit.font("bold"))
		row.add_child(label)
		var bar := Kit.progress_bar(BAR)
		bar.max_value = 1000
		bar.value = roundi(clampf(float(el["e"]) / float(el["b"]), 0.0, 1.0) * 1000.0)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.name = "Electricity"
		row.add_child(bar)
		_lines.add_child(row)


## A horizontal rule: `top` over `bottom` (Factorio's dark-then-light line), `height` pixels.
static func _rule(top: Color, bottom: Color, height: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [top, bottom]:
		if c.a <= 0.0:
			continue
		var line := ColorRect.new()
		line.color = c
		line.custom_minimum_size.y = maxi(1, height - 1) if c == top else 1
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(line)
	return box


## Watts as Factorio's entity info writes them: 217 kW, 77.5 kW, 7.0 kW, 1.2 MW.
static func power_text(w: float) -> String:
	var prefixes := [[1e9, "G"], [1e6, "M"], [1e3, "k"], [1.0, ""]]
	for p in prefixes:
		if absf(w) >= float(p[0]) or str(p[1]) == "":
			var v := w / float(p[0])
			return ("%d" % roundi(v) if absf(v) >= 100.0 else "%.1f" % v) + " %sW" % p[1]
	return "0 W"


## Factorio's tooltip lightning (the left picture of its sheet, which holds smaller ones beside it).
static func _bolt_icon() -> Texture2D:
	var sheet := GuiAssets.core_sprite("icons/tooltips/tooltip-category-electricity.png")
	if sheet == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, sheet.get_height() * 0.8, sheet.get_height())
	return atlas


## The hovered machine's power from fluids_power.gd (`pw`): -1 powered (or not electric), 0 no
## power, 1 low power, 2 not connected to any pole.
func _power_state(r) -> int:
	if r.unit == 0 or player == null or player.get_parent() == null:
		return -1
	var power = player.get_parent().get_node_or_null("FluidsPower")
	return int(power.power_state(r.unit)) if power != null and power.has_method("power_state") else -1


## What Factorio's entity info adds for modules and beacons: the modules in it, a beacon's
## distribution effectivity and the machines it reaches, a machine's beacons, then the effects (a
## machine's total; a beacon's its modules' sum, which 2.1.23 reports before the distribution
## effectivity), green where they help, red where they cost.
func _effect_lines(info: Dictionary, beacon: bool) -> void:
	if info.is_empty():
		return
	var mods: Array = info.get("m", [])
	if not mods.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(4))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := Kit.label("Modules:")
		head.add_theme_font_override("font", Kit.font("bold"))
		row.add_child(head)
		for m in mods:
			var t := TextureRect.new()
			t.texture = Kit.item_icon(str(m[0]))
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.custom_minimum_size = Kit.pxv(20, 20)
			t.texture_filter = Kit.ICON_FILTER
			t.tooltip_text = Kit.pretty(str(m[0]))
			row.add_child(t)
			row.add_child(Kit.label("x%d" % int(m[1])))
		_lines.add_child(row)
	if beacon:
		if info.has("de"):
			_line("Distribution effectivity: %s" % effect_text(int(info["de"])).trim_prefix("+"))
		if info.has("n"):
			_line("Machines affected: %d" % int(info["n"]))
	elif info.has("b"):
		_line("Beacons: %d" % int(info["b"]))
	var eff: Dictionary = info.get("eff", {})
	if eff.is_empty():
		return
	_line("Module effects:" if beacon else "Effects:")
	for e in EFFECT_NAMES:
		if eff.has(e[0]):
			_line("%s: %s" % [e[1], effect_text(int(eff[e[0]]))], Kit.GREEN_TEXT if effect_helps(e[0], int(eff[e[0]])) else Kit.RED_TEXT)


## An effect in thousandths as Factorio writes it: +150%, -15%, +2.5%.
static func effect_text(thousandths: int) -> String:
	var number := ("%d" % (thousandths / 10)) if thousandths % 10 == 0 else ("%.1f" % (thousandths / 10.0))
	return ("+" if thousandths > 0 else "") + number + "%"


## Speed, productivity and quality help when they go up; consumption and pollution when they go down.
static func effect_helps(kind: String, thousandths: int) -> bool:
	return thousandths > 0 if kind in ["sp", "pr", "q"] else thousandths < 0


func _line(text: String, color := Kit.WHITE, item := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	for part in Kit.key_value_labels(text, color):
		row.add_child(part)
	if item == "":
		_lines.add_child(row)
		return
	var l := row
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(4))
	var t := TextureRect.new()
	t.texture = Kit.item_icon(item)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Kit.pxv(20, 20)
	t.texture_filter = Kit.ICON_FILTER
	row.add_child(t)
	row.add_child(l)
	_lines.add_child(row)


## The item that builds an entity: the one of the same name, or the one whose place result it is
## (the rail planner builds rails).
static func _item_for(world, entity: String) -> String:
	if world.protos.item_names.values().has(entity):
		return entity
	for item in world.protos.item_places:
		if str(world.protos.item_places[item]) == entity:
			return str(item)
	return ""


## 0..1 from the combat layer's health bars (entities below full health), 1 otherwise, -1 for
## entities without health (ore).
func _health_of(r) -> float:
	if r.unit == 0:
		return -1.0
	var combat = player.get("combat")
	var hp = combat.get("_health") if combat != null else null
	if hp is Dictionary and (hp as Dictionary).has(r.unit):
		return float(hp[r.unit])
	return 1.0
