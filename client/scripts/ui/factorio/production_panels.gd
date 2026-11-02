extends RefCounted
## Factorio's production windows, the right half of the entity window, laid out as Factorio 2.1
## draws them (tools/ui_reference's pictures): under the status line the entity preview (the
## machine on a checkerboard), then rows split by thin lines:
##   crafters:  the recipe row (icon, name, gear "change recipe" button), the ingredient slots
##              (ghost icons, red when short), a progress bar with its % and a purple
##              productivity bar under it, the product slots (gold while they hold something)
##   furnaces:  the product row (no gear), source + bar + result; the recycler's 12 outputs
##   drills:    the mining bar with %, the productivity bar, the resource's icon (and a pumpjack's
##              yield per second)
##   burners:   the fuel slot(s), the red "fuel left" bar, the burnt result slot(s)
##   heat:      the red temperature bar ("Temperature: 671.69 °C")
##   labs:      the research box (icon, name, green bar, %), one slot per science pack with ghosts
##   modules:   a bare row of module slots, faint cells after them
##   chests:    the 10-wide grid with the red X limit button inside it; logistic chests' filters,
##              requests (sections, Factorio's checkboxes) and trash slots
## and Factorio's recipe chooser ("Select a recipe for assembling": group tabs, a 10-wide grid, the
## ingredient quality row). machine_screen.gd calls these with itself as `screen`.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const ModelLibrary := preload("res://scripts/world/model_library.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")

## Factorio's colours: production_progressbar (green), heat_progressbar (red), burning_progressbar,
## bonus_progressbar (purple).
const PRODUCTION_GREEN := Color8(43, 227, 39)
const HEAT_RED := Color8(218, 69, 53)
const BURNING_RED := Color(1, 0, 0)
const BONUS_PURPLE := Color(0.8, 0.1, 0.8)
## The entity preview: 400 x 148 inside its deep frame; 32 pixels a tile, like the game's sprites.
const PREVIEW_HEIGHT := 148
const PREVIEW_TILE := 32.0
const CHECKER := [Color8(46, 46, 46), Color8(57, 57, 57)]
## Entity types each layout covers (the rest keep machine_screen.gd's generic rows).
const DRILL_TYPES := ["mining-drill"]
const BURNER_TYPES := ["boiler", "reactor", "burner-generator", "fusion-reactor", "generator"]
## Types whose fluid boxes Factorio doesn't show in their window (crafters show them as slots).
const NO_FLUID_TYPES := ["assembling-machine", "furnace", "mining-drill", "boiler", "reactor", "offshore-pump",
	"fusion-reactor", "fusion-generator", "rocket-silo", "generator", "burner-generator", "lab"]
## Rows of the recipe chooser's grid (more scroll).
const CHOOSER_ROWS := 5


# --- small pieces ----------------------------------------------------------------------------------

## Factorio's horizontal line between a window's rows (a dark line over a light one).
static func line() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [Color8(30, 29, 30), Color8(80, 79, 80)]:
		var r := ColorRect.new()
		r.color = c
		r.custom_minimum_size.y = maxf(1.0, Kit.px(1))
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)
	return box


## The faint square Factorio draws in the unused cells of a machine's slot rows (on the light
## frame, not the deep slot recess).
static func faint_cell() -> Control:
	var m := MarginContainer.new()
	m.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, Kit.px(10))
	var p := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.06)
	box.border_color = Color(0, 0, 0, 0.16)
	box.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", box)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(p)
	return m


static func bold(text: String, color := Color.WHITE) -> Label:
	var l := Kit.label(text)
	l.add_theme_font_override("font", Kit.font("bold"))
	l.add_theme_color_override("font_color", color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func icon(texture: Texture2D, size := 32) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Kit.pxv(size, size)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.texture_filter = Kit.ICON_FILTER
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	return t


## A progress bar `height` tall with Factorio's embedded text at the right ("87%"), black where the
## bar has filled under it. `value` 0..1.
static func text_bar(color: Color, value: float, text: String, height := 24) -> ProgressBar:
	var bar := Kit.progress_bar(color)
	bar.max_value = 1000
	bar.value = clampf(value, 0.0, 1.0) * 1000.0
	bar.custom_minimum_size = Vector2(Kit.px(40), Kit.px(height))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if text != "":
		var l := Kit.label(text)
		l.name = "Text"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.offset_right = -Kit.px(6)
		bar.add_child(l)
		bar.set_meta("text_label", l)
		_bar_text_color(bar)
		bar.value_changed.connect(func(_v: float) -> void: _bar_text_color(bar))
	return bar


static func _bar_text_color(bar: ProgressBar) -> void:
	var l: Label = bar.get_meta("text_label") if bar.has_meta("text_label") else null
	if l != null:
		var filled_under_text := bar.value / maxf(1.0, bar.max_value) > 0.88
		l.add_theme_color_override("font_color", Color.BLACK if filled_under_text else Color.WHITE)


## Sets a text_bar's value (0..1) and its "N%" text.
static func set_percent(bar: ProgressBar, value: float) -> void:
	bar.value = clampf(value, 0.0, 1.0) * 1000.0
	var l: Label = bar.get_meta("text_label") if bar.has_meta("text_label") else null
	if l != null:
		l.text = "%d%%" % floori(clampf(value, 0.0, 1.0) * 100.0)


## The thin bars (8 px): the burner's fuel left, the productivity bonus.
static func thin_bar(color: Color, value: float) -> ProgressBar:
	var bar := Kit.progress_bar(color)
	bar.max_value = 1000
	bar.value = clampf(value, 0.0, 1.0) * 1000.0
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


static func _row(gap := 0) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", Kit.px(gap))
	return r


## A row of `role`'s slots, `columns` wide, faint cells filling the rest of the row (Factorio's bare
## module and lab rows).
static func bare_row(screen, role: String, columns := Kit.COLUMNS, ghosts: Array = []) -> Control:
	var grid := Kit.slot_grid(columns)
	var stacks: Array = screen._slot_list(role)
	var exact: bool = screen.knows_slots(role)
	# Modules asked for (F6) show faintly in their slots until the robots bring them.
	var requested: Array = screen.module_requests() if role == "modules" and ghosts.is_empty() else []
	for i in stacks.size():
		var s: Slot = screen._stack_slot(role, i + 1 if exact else 0, stacks[i])
		if (stacks[i] as Dictionary).is_empty() and i < ghosts.size():
			s.filter_item = str(ghosts[i])
		elif (stacks[i] as Dictionary).is_empty() and i < requested.size() and str(requested[i]) != "":
			s.filter_item = str(requested[i])
			s.set_tip(Kit.pretty(str(requested[i])), [["Requested: the robots bring it"],
				["Right click: cancel the request", "", Kit.DISABLED_TEXT]])
		grid.add_child(s)
	var cells := stacks.size()
	while cells == 0 or cells % columns != 0:
		grid.add_child(faint_cell())
		cells += 1
	return grid


# --- the entity preview ------------------------------------------------------------------------------

## The entity on Factorio's checkerboard: its 3D model, seen from the game's angle, in a world of its
## own (only the model and a light), or its icon without a model.
static func preview(proto_name: String, proto_type: String, footprint: Vector2) -> Control:
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(Kit.px(Kit.SLOT * Kit.COLUMNS - 8), Kit.px(PREVIEW_HEIGHT))
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var checker := func() -> void:
		var cell := float(Kit.px(32))
		var cols := ceili(holder.size.x / cell)
		var rows := ceili(holder.size.y / cell)
		for y in rows:
			for x in cols:
				holder.draw_rect(Rect2(Vector2(x, y) * cell, Vector2(cell, cell)), CHECKER[(x + y) % 2])
	holder.draw.connect(checker)
	frame.add_child(holder)
	var mesh: Mesh = ModelLibrary.mesh_for_entity(proto_name, proto_type, {}) if proto_name != "" else null
	if mesh == null:
		var t := icon(Kit.item_icon(proto_name), 48)
		t.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		holder.add_child(t)
		return frame
	var view := SubViewportContainer.new()
	view.stretch = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var model := MeshInstance3D.new()
	model.mesh = mesh
	vp.add_child(model)
	# The moving parts (a pumpjack's beam, a drill's head) are separate meshes in model space.
	for part in ModelLibrary.parts_for_entity(proto_name, proto_type, {}):
		var piece := MeshInstance3D.new()
		piece.mesh = part.mesh
		vp.add_child(piece)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	# From the upper left, as the game's sprites are lit (their shadows fall to the right).
	sun.rotation_degrees = Vector3(-50, -40, 0)
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.environment.ambient_light_energy = 1.2
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var aabb := mesh.get_aabb()
	var tall := maxf(aabb.size.y, 0.5)
	# 32 pixels a tile like the sprites, smaller when the entity wouldn't fit.
	var fit := maxf(maxf(footprint.y, aabb.size.z) * 0.71 + tall * 0.71, maxf(footprint.x, aabb.size.x) * PREVIEW_HEIGHT / 400.0)
	cam.size = maxf(PREVIEW_HEIGHT / PREVIEW_TILE, fit * 1.2)
	var centre := Vector3(aabb.get_center().x, tall * 0.4, aabb.get_center().z)
	var eye := centre + Vector3(0, 25, 30)  # about 40 degrees up, like the game's sprites
	cam.transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), eye)
	cam.current = true
	vp.add_child(cam)
	view.add_child(vp)
	holder.add_child(view)
	return frame


# --- crafters ------------------------------------------------------------------------------------------

## The recipe's ingredients and products ({i: [[type, name, amount]], o: [...]}): `gui.rd`, else
## the hand recipe's details the UI model has.
static func recipe_details(screen, recipe: String) -> Dictionary:
	var rd = screen._last.get("rd")
	if rd is Dictionary:
		return rd
	if recipe != "" and screen.model != null:
		var r: Dictionary = screen.model.recipe(recipe)
		if not r.is_empty() and not (r["ingredients"] as Array).is_empty():
			var to_rd := func(l: Array) -> Array: return l.map(func(p): return ["item", str(p[0]), float(p[1])])
			return {"i": to_rd.call(r["ingredients"]), "o": to_rd.call(r["products"])}
	return {}


## The recipe row: its icon, its name and, unless the recipe is fixed, the gear button.
static func recipe_row(recipe: String, fixed: bool, on_gear: Callable) -> Control:
	var r := _row(12)
	r.custom_minimum_size.y = Kit.px(40)
	if recipe == "":
		r.add_child(bold("No recipe set"))
	else:
		var t := icon(Kit.item_icon(recipe))
		t.tooltip_text = Kit.recipe_name(recipe)
		r.add_child(t)
		r.add_child(bold(Kit.recipe_name(recipe)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(spacer)
	if not fixed:
		var gear := Button.new()
		gear.name = "ChangeRecipe"
		gear.focus_mode = Control.FOCUS_NONE
		gear.custom_minimum_size = Kit.pxv(40, 40)
		gear.tooltip_text = "Change recipe"
		var tex := GuiAssets.core_sprite("icons/change-recipe.png")
		if tex != null:
			gear.icon = tex
			gear.expand_icon = true
			gear.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			gear.add_theme_constant_override("icon_max_width", Kit.px(28))
		else:
			gear.text = "⚙"
		gear.pressed.connect(on_gear)
		r.add_child(gear)
	return r


## Total of `name` in the machine's `role` (items) or its fluid boxes (fluids).
static func _have(screen, role: String, type: String, name: String) -> float:
	if type == "fluid":
		var total := 0.0
		var fb = screen._last.get("fb")
		if fb is Array:
			for b in fb:
				if b is Array and b.size() >= 2 and str(b[0]) == name:
					total += float(b[1])
		return total
	var n := 0
	for st in screen._slot_list(role):
		if st is Dictionary and str(st.get("item", "")) == name:
			n += int(st["count"])
	return n


## The slot (1-based) of `role` that holds `name`, else the first empty one, else 0.
static func _slot_of(screen, role: String, name: String) -> int:
	if not screen.knows_slots(role):
		return 0
	var list: Array = screen._slot_list(role)
	for i in list.size():
		if str(list[i].get("item", "")) == name:
			return i + 1
	for i in list.size():
		if (list[i] as Dictionary).is_empty():
			return i + 1
	return 0


## One ingredient or product of the recipe as a slot: what the machine holds of it (a ghost when
## nothing), red when an ingredient is short, gold when a product is waiting.
static func recipe_slot(screen, role: String, entry: Array, product: bool) -> Slot:
	var type := str(entry[0])
	var name := str(entry[1])
	var need := float(entry[2]) if entry.size() > 2 else 1.0
	var have := _have(screen, role, type, name)
	var index := 0 if type == "fluid" else _slot_of(screen, role, name)
	var stack: Dictionary = {} if have <= 0 or type == "fluid" else {"item": name, "count": int(have)}
	var s: Slot
	if type == "fluid":
		s = Slot.new()
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		if have > 0:
			s.set_stack(name, roundi(have))
		s.set_tip(Kit.pretty(name), [["%s / %s per craft" % [str(roundi(have)), _num(need)]]])
	else:
		s = screen._stack_slot(role, index, stack)
	if have <= 0:
		s.filter_item = name  # Factorio's ghost of what goes there
		if s.tip_title == "":
			s.set_tip(Kit.pretty(name), [["%s per craft" % _num(need), "", Kit.DISABLED_TEXT]])
	if not product and have < need:
		s.theme_type_variation = "FRedSlot"
	elif product and have > 0:
		s.theme_type_variation = "FYellowSlot"
	return s


static func _num(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else ("%.2f" % v).rstrip("0").rstrip(".")


## The middle of a production row: the progress bar with %, and the purple productivity bar under
## it when the machine has a bonus. Returns [column, progress bar].
static func progress_column(screen, value: float) -> Array:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(2))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var bar := text_bar(PRODUCTION_GREEN, value, "0%")
	bar.name = "ProgressBar"
	set_percent(bar, value)
	col.add_child(bar)
	if int(screen._last.get("pb", 0)) > 0:
		var bonus := thin_bar(BONUS_PURPLE, int(screen._last.get("bp", 0)) / 1000.0)
		bonus.tooltip_text = "Productivity bonus: +%d%%" % roundi(int(screen._last["pb"]) / 10.0)
		bonus.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(bonus)
	return [col, bar]


## An assembler's window below the preview. Returns the progress bar (machine_screen.gd updates it).
static func crafter(screen, body: Control, recipe: String, on_gear: Callable) -> ProgressBar:
	var fixed := int(screen._last.get("fixed", 0)) == 1 or str(screen._last.get("kind", "")) == "silo"
	body.add_child(recipe_row(recipe, fixed, on_gear))
	body.add_child(line())
	var rd := recipe_details(screen, recipe)
	var row := _row(0)
	row.add_theme_constant_override("separation", Kit.px(4))
	var ins: Array = rd.get("i", []) if rd.get("i") is Array else []
	var outs: Array = rd.get("o", []) if rd.get("o") is Array else []
	var ingredients := _row(0)
	if rd.is_empty():
		ingredients.add_child(bare_row(screen, "input", maxi(1, (screen._slot_list("input") as Array).size())))
	for e in ins:
		if e is Array and e.size() >= 3:
			ingredients.add_child(recipe_slot(screen, "input", e, false))
	row.add_child(ingredients)
	var pc := progress_column(screen, int(screen._last.get("pr", 0)) / 1000.0)
	row.add_child(pc[0])
	var products := _row(0)
	if rd.is_empty():
		products.add_child(bare_row(screen, "output", maxi(1, (screen._slot_list("output") as Array).size())))
	for e in outs:
		if e is Array and e.size() >= 3:
			products.add_child(recipe_slot(screen, "output", e, true))
	row.add_child(products)
	body.add_child(row)
	body.add_child(line())
	if screen.knows_slots("fuel"):
		body.add_child(burner_row(screen))
	if screen.knows_slots("modules"):
		body.add_child(bare_row(screen, "modules"))
	return pc[1]


# --- furnaces -------------------------------------------------------------------------------------------

## A furnace (and the recycler): the product row, source + bar + result, the fuel row, modules.
static func furnace(screen, body: Control) -> ProgressBar:
	var recipe := str(screen._last.get("recipe", screen._last.get("rp", "")))
	var rd := recipe_details(screen, recipe)
	var outs: Array = rd.get("o", []) if rd.get("o") is Array else []
	var product := ""
	if outs.size() == 1 and outs[0] is Array:
		product = str(outs[0][1])
	var head := _row(12)
	head.custom_minimum_size.y = Kit.px(40)
	if product != "" and recipe != "":
		head.add_child(icon(Kit.item_icon(product)))
		head.add_child(bold(Kit.pretty(product)))
	else:
		head.add_child(bold("No recipe set"))
	body.add_child(head)
	body.add_child(line())
	var row := _row(4)
	for i in maxi(1, (screen._slot_list("input") as Array).size()):
		var stacks: Array = screen._slot_list("input")
		row.add_child(screen._stack_slot("input", i + 1 if screen.knows_slots("input") else 0, stacks[i] if i < stacks.size() else {}))
	var pc := progress_column(screen, int(screen._last.get("pr", 0)) / 1000.0)
	row.add_child(pc[0])
	var outputs: Array = screen._slot_list("output")
	var many := outputs.size() > 4
	if not many:
		for i in maxi(1, outputs.size()):
			var st: Dictionary = outputs[i] if i < outputs.size() else {}
			var s: Slot = screen._stack_slot("output", i + 1 if screen.knows_slots("output") else 0, st)
			if not st.is_empty():
				s.theme_type_variation = "FYellowSlot"
			row.add_child(s)
	body.add_child(row)
	if many:  # the recycler: its 12 outputs as a 6 x 2 grid at the right, faint cells to the left
		var out_row := _row(0)
		var faint := Kit.slot_grid(4)
		for i in 8:
			faint.add_child(faint_cell())
		out_row.add_child(faint)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		out_row.add_child(spacer)
		var grid := Kit.slot_grid(6)
		for i in outputs.size():
			var s: Slot = screen._stack_slot("output", i + 1 if screen.knows_slots("output") else 0, outputs[i])
			if not (outputs[i] as Dictionary).is_empty():
				s.theme_type_variation = "FYellowSlot"
			grid.add_child(s)
		out_row.add_child(grid)
		body.add_child(out_row)
	body.add_child(line())
	if screen.knows_slots("fuel"):
		body.add_child(burner_row(screen))
	if screen.knows_slots("modules"):
		body.add_child(bare_row(screen, "modules"))
	return pc[1]


# --- burners and heat -------------------------------------------------------------------------------

## The fuel slot(s), the red bar of the fuel left in the burning item, the burnt result slot(s).
static func burner_row(screen) -> Control:
	var row := _row(8)
	var fuel := Kit.slot_grid(maxi(1, (screen._slot_list("fuel") as Array).size()))
	var stacks: Array = screen._slot_list("fuel")
	var empty_fuel := _fuel_placeholder(screen)
	for i in maxi(1, stacks.size()):
		var s: Slot = screen._stack_slot("fuel", i + 1 if screen.knows_slots("fuel") else 0, stacks[i] if i < stacks.size() else {})
		if empty_fuel != null:
			s.empty_icon = empty_fuel
		fuel.add_child(s)
	row.add_child(fuel)
	var bar := thin_bar(BURNING_RED, int(screen._last.get("bn", 0)) / 1000.0)
	bar.name = "BurnerBar"
	bar.tooltip_text = "Fuel left in the burning item"
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(bar)
	if screen.knows_slots("burnt"):
		var burnt: Array = screen._slot_list("burnt")
		var grid := Kit.slot_grid(maxi(1, burnt.size()))
		for i in burnt.size():
			grid.add_child(screen._stack_slot("burnt", i + 1, burnt[i]))
		row.add_child(grid)
	return row


## The empty fuel slot's placeholder: fuel, or a biochamber's nutrients, or a spawner's food.
static func _fuel_placeholder(screen) -> Texture2D:
	match str(screen.proto_name):
		"biochamber":
			return GuiAssets.core_sprite("icons/mip/empty-nutrients-slot.png")
		"captive-biter-spawner":
			return GuiAssets.core_sprite("icons/mip/empty-food-slot.png")
	return GuiAssets.core_sprite("icons/mip/empty-fuel-slot.png")


## Factorio's heat bar: red, full width, "Temperature: 671.69 °C" inside it.
static func temperature_bar(screen) -> Control:
	var t := int(screen._last.get("tc", int(screen._last.get("temp", 0)) * 100)) / 100.0
	var top := float(screen._last.get("tmax", 1000.0))
	# From the 15 °C everything starts at to the maximum, as Factorio fills it.
	var bar := text_bar(HEAT_RED, (t - 15.0) / maxf(1.0, top - 15.0), "Temperature: %.2f °C" % t)
	bar.name = "TemperatureBar"
	return bar


## Boilers, reactors, heating towers, fusion reactors: the fuel row and the temperature bar.
static func burner(screen, body: Control) -> void:
	if screen.knows_slots("fuel"):
		body.add_child(burner_row(screen))
	if screen._last.has("tc") or screen._last.has("temp"):
		body.add_child(temperature_bar(screen))
	if screen.knows_slots("modules"):
		body.add_child(bare_row(screen, "modules"))


# --- mining drills ------------------------------------------------------------------------------------

## The mining bar with %, the productivity bar under it, the resource at the right (a pumpjack's
## yield under its icon); then the fuel row (burner drill) and the module row.
static func drill(screen, body: Control) -> ProgressBar:
	var row := _row(8)
	var pc := progress_column(screen, int(screen._last.get("mp", 0)) / 1000.0)
	row.add_child(pc[0])
	var mt := str(screen._last.get("mt", ""))
	if mt != "":
		var res := Control.new()
		res.custom_minimum_size = Kit.pxv(40, 40)
		var t := icon(_resource_icon(mt))
		t.position = Kit.pxv(4, 0)
		t.size = Kit.pxv(32, 32)
		t.tooltip_text = Kit.entity_name(mt)
		res.add_child(t)
		if screen._last.has("mr"):
			var l := Kit.label(("%.1f/s" % (int(screen._last["mr"]) / 100.0)))
			l.add_theme_font_override("font", Kit.font("bold"))
			l.add_theme_font_size_override("font_size", Kit.px(12))
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", Kit.px(3))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.position = Kit.pxv(-6, 20)
			l.size = Kit.pxv(52, 18)
			res.add_child(l)
		row.add_child(res)
	body.add_child(row)
	if screen.knows_slots("fuel"):
		body.add_child(line())
		body.add_child(burner_row(screen))
	if screen.knows_slots("modules"):
		body.add_child(bare_row(screen, "modules"))
	return pc[1]


## A resource's icon: its item (iron ore), or its fluid (crude oil).
static func _resource_icon(name: String) -> Texture2D:
	return Kit.item_icon(name)


# --- labs ---------------------------------------------------------------------------------------------

## The research box (tech icon, name, green bar, %), the science pack slots (one per pack the lab
## takes, ghosts where empty), the modules.
static func lab(screen, body: Control) -> void:
	var tech := str(screen.model.research) if screen.model != null else ""
	var progress := float(screen.model.research_progress) if screen.model != null else 0.0
	# Factorio's research box: a slightly darker inset than the panel, not the deep frame.
	var box := PanelContainer.new()
	var inset := StyleBoxFlat.new()
	inset.bg_color = Color8(47, 46, 47)
	inset.border_color = Color8(25, 24, 25)
	inset.set_border_width_all(maxi(1, Kit.px(1)))
	box.add_theme_stylebox_override("panel", inset)
	var m := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, Kit.px(8))
	box.add_child(m)
	var r := _row(12)
	m.add_child(r)
	if tech != "":
		r.add_child(icon(GuiAssets.tech_icon(tech)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", Kit.px(2))
	col.add_child(bold(Kit.tech_name(tech) if tech != "" else "No research in progress. Press T."))
	var bar_row := _row(8)
	var bar := thin_bar(Kit.BAR_GREEN, progress)
	bar_row.add_child(bar)
	bar_row.add_child(Kit.label("%d%%" % floori(progress * 100.0)))
	col.add_child(bar_row)
	r.add_child(col)
	body.add_child(box)
	var li = screen._last.get("li")
	if li is Array:
		screen.set_meta("lab_inputs", li)
	var packs: Array = screen.get_meta("lab_inputs") if screen.has_meta("lab_inputs") else []
	var pack_row := bare_row(screen, "input", Kit.COLUMNS, packs)
	# What's left of each slot's top pack: Factorio's orange pie over the slot (`gui.ld`).
	var ld = screen._last.get("ld")
	if ld is Array:
		for entry in ld:
			if entry is Array and entry.size() >= 2 and int(entry[0]) >= 1 and int(entry[0]) <= pack_row.get_child_count():
				var s = pack_row.get_child(int(entry[0]) - 1)
				if s is Slot:
					(s as Slot).set_progress(int(entry[1]) / 1000.0)
	body.add_child(pack_row)
	if screen.knows_slots("modules"):
		body.add_child(bare_row(screen, "modules"))


# --- chests -------------------------------------------------------------------------------------------

## The chest's slots, 10 wide, with Factorio's red X limit button in the cell at the bar (slots past
## it red), faint cells to the end of the row.
static func chest_grid(screen, role: String, x_button: Control, scroll_rows := 0) -> Control:
	var grid := Kit.slot_grid(Kit.COLUMNS)
	var stacks: Array = screen._slot_list(role)
	var exact: bool = screen.knows_slots(role)
	var bar := int(screen._last.get("bar", stacks.size()))
	var cells := 0
	for i in stacks.size():
		if x_button != null and i == bar:
			grid.add_child(x_button)
			cells += 1
		grid.add_child(screen._stack_slot(role, i + 1 if exact else 0, stacks[i]))
		cells += 1
	if x_button != null and bar >= stacks.size():
		grid.add_child(x_button)
		cells += 1
	while cells == 0 or cells % Kit.COLUMNS != 0:
		grid.add_child(faint_cell())
		cells += 1
	if scroll_rows > 0 and cells > Kit.COLUMNS * scroll_rows:  # a hub's hundreds of slots scroll
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.focus_mode = Control.FOCUS_NONE
		scroll.custom_minimum_size = Vector2(0, Kit.px(Kit.SLOT * scroll_rows))
		scroll.add_child(grid)
		return scroll
	return grid


## Factorio's "Rocket progress": the rocket parts built, then the rocket's way to ready (both green
## with their %).
const LAUNCH_STEPS := ["building_rocket", "create_rocket", "lights_blinking_open", "doors_opening", "doors_opened",
	"rocket_rising", "arms_advance", "rocket_ready"]


static func rocket_progress(rk: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(6))
	box.add_child(line())
	box.add_child(Kit.label("Rocket progress", "FHeading"))
	var parts := float(rk.get("parts", 0)) / maxf(1.0, float(rk.get("need", 1)))
	var built := text_bar(PRODUCTION_GREEN, parts, "0%")
	set_percent(built, parts)
	built.tooltip_text = "Rocket parts: %d / %d" % [int(rk.get("parts", 0)), int(rk.get("need", 1))]
	built.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(built)
	var st := str(rk.get("st", ""))
	var step := LAUNCH_STEPS.find(st)
	var ready := 1.0 if step < 0 and st != "" else maxf(0.0, step) / float(LAUNCH_STEPS.size() - 1)
	var launch := text_bar(PRODUCTION_GREEN, ready, "0%")
	set_percent(launch, ready)
	launch.tooltip_text = "The rocket on its way to the launch"
	launch.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(launch)
	return box


## "Rocket capacity usage" with its bar ("0 g/1 ton", `gui.rw`: grams in the rocket, grams it lifts).
static func rocket_capacity(rw: Array) -> Control:
	var r := _row(8)
	r.add_child(Kit.label("Rocket capacity usage"))
	var used := float(rw[0]) if rw.size() > 0 else 0.0
	var lift := maxf(1.0, float(rw[1]) if rw.size() > 1 else 1000000.0)
	var bar := text_bar(PRODUCTION_GREEN, used / lift, "%s/%s" % [_weight_text(used), _weight_text(lift)], 20)
	r.add_child(bar)
	return r


## Factorio's weights: "0 g", "250 kg", "1 ton".
static func _weight_text(grams: float) -> String:
	if grams >= 1000000.0:
		var t := grams / 1000000.0
		return "%s ton" % _num(snappedf(t, 0.01))
	if grams >= 1000.0:
		return "%s kg" % _num(snappedf(grams / 1000.0, 0.1))
	return "%d g" % roundi(grams)


## A heading with the logistic network dot at the right (green: in a network, red: not).
static func network_heading(text: String, connected: bool) -> Control:
	var r := _row(8)
	var l := Kit.label(text, "FHeading")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	var dot_tex := GuiAssets.status_dot("green" if connected else "red")
	if dot_tex != null:
		var dot := icon(dot_tex, 16)
		dot.tooltip_text = "Connected to a logistic network" if connected else "Not connected to a logistic network"
		r.add_child(dot)
	return r


## A storage chest's "Logistic filters" and its one filter slot.
static func storage_filter(screen, lg: Dictionary, choose: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	box.add_child(network_heading("Logistic filters", lg.get("net") is Dictionary))
	var slot: Control = choose.call()
	slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(slot)
	return box


## Requester and buffer chests: "Logistic requests" with the network dot, "Trash unrequested" (and
## the requester's "Request from buffer chests"), the request sections, then "Trash slots".
static func chest_requests(screen, lg: Dictionary, lc: Dictionary, sections: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	box.add_child(network_heading("Logistic requests", lg.get("net") is Dictionary))
	var unit: int = screen.unit
	var tu := func(on: bool) -> void: Bridge.send({"t": "set_chest_logistics", "u": unit, "tu": 1 if on else 0})
	var c1 := MenuKit.checkbox("Trash unrequested", int(lc.get("tu", 0)) == 1)
	c1.toggled.connect(tu)
	box.add_child(c1)
	if lc.has("rb"):
		var rb := func(on: bool) -> void: Bridge.send({"t": "set_chest_logistics", "u": unit, "rb": 1 if on else 0})
		var c2 := MenuKit.checkbox("Request from buffer chests", int(lc.get("rb", 0)) == 1)
		c2.toggled.connect(rb)
		box.add_child(c2)
	box.add_child(sections)
	return box


## "Trash slots": 2 rows of 10, each empty one with the trash can.
static func trash_slots(screen) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	box.add_child(Kit.label("Trash slots", "FHeading"))
	var grid := Kit.slot_grid(Kit.COLUMNS)
	var stacks: Array = screen._slot_list("trash")
	var can := GuiAssets.core_sprite("icons/mip/empty-trash-slot.png")
	var cells := maxi(stacks.size(), 20)
	for i in cells:
		var st: Dictionary = stacks[i] if i < stacks.size() else {}
		var s: Slot = screen._stack_slot("trash", i + 1 if screen.knows_slots("trash") and i < stacks.size() else 0, st)
		s.empty_icon = can
		if i >= stacks.size():
			s.disabled = true
		grid.add_child(s)
	box.add_child(grid)
	return box


## The force's logistic groups (`gui.lgs`, sent with the recipe list's messages; kept between them).
static func logistic_groups(screen) -> Array:
	var lgs = screen._last.get("lgs")
	if lgs is Array:
		screen.set_meta("logistic_groups", lgs)
	return screen.get_meta("logistic_groups") if screen.has_meta("logistic_groups") else []


## Factorio's group picker under a section's header (the pencil): a name box (Enter: that group, a
## new name makes one, empty: no group; Esc: cancel) and the force's groups to pick from.
static func group_editor(screen, index: int, current: String) -> Control:
	var unit: int = screen.unit
	var box := VBoxContainer.new()
	box.name = "GroupEditor"
	box.visible = false
	box.add_theme_constant_override("separation", Kit.px(4))
	var set_group := func(g: String) -> void:
		Bridge.send({"t": "set_section", "u": unit, "i": index, "g": g.strip_edges()})
		box.visible = false
	var r := _row(6)
	var name_box := MenuKit.textbox(current, "Group name ([No group assigned] when empty)")
	name_box.name = "GroupName"
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.text_submitted.connect(func(t: String) -> void: set_group.call(t))
	var on_key := func(ev: InputEvent) -> void:
		var k := ev as InputEventKey
		if k != null and k.pressed and k.physical_keycode == KEY_ESCAPE:
			box.visible = false
			name_box.release_focus()
			name_box.accept_event()
	name_box.gui_input.connect(on_key)
	r.add_child(name_box)
	var ok := Button.new()
	ok.theme_type_variation = "FGreenButton"
	ok.focus_mode = Control.FOCUS_NONE
	ok.custom_minimum_size = Kit.pxv(28, 28)
	ok.tooltip_text = "Confirm"
	var tick := GuiAssets.core_sprite("icons/mip/check-mark-white.png")
	if tick != null:
		ok.icon = tick
		ok.expand_icon = true
	else:
		ok.text = "✓"
	ok.pressed.connect(func() -> void: set_group.call(name_box.text))
	r.add_child(ok)
	box.add_child(r)
	var groups := logistic_groups(screen)
	if not groups.is_empty():
		var list := HFlowContainer.new()
		list.add_theme_constant_override("h_separation", Kit.px(4))
		list.add_theme_constant_override("v_separation", Kit.px(4))
		for g in groups:
			var name := str(g)
			var b := MenuKit.button(name)
			RichText.decorate_button(b, name)
			b.toggle_mode = true
			b.button_pressed = name == current
			b.pressed.connect(func() -> void: set_group.call(name))
			list.add_child(b)
		box.add_child(list)
	return box


## Factorio's logistic sections: a header per section (on/off box, its group or "[No group
## assigned]", the rename pencil, the red delete button), its request slots 10 wide, then the
## full-width "Add section" button. `slots(section, filters, send)` draws a section's slots.
static func sections(screen, secs: Array, slots: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	var unit: int = screen.unit
	for sec in secs:
		if not (sec is Dictionary):
			continue
		var i := int(sec.get("i", 0))
		var head := Kit.panel("FSubheader")
		var hr := _row(8)
		head.add_child(hr)
		var on := MenuKit.checkbox("", int(sec.get("on", 1)) == 1)
		var set_on := func(v: bool) -> void: Bridge.send({"t": "set_section", "u": unit, "i": i, "on": 1 if v else 0})
		on.toggled.connect(set_on)
		hr.add_child(on)
		var group := str(sec.get("g", ""))
		if group != "":
			var group_title := RichText.text_label(group, "FHeading", Kit.CAPTION)
			group_title.name = "GroupTitle"
			hr.add_child(group_title)
		else:
			hr.add_child(bold("[No group assigned]", Kit.CAPTION))
		var pencil := Button.new()
		pencil.focus_mode = Control.FOCUS_NONE
		pencil.theme_type_variation = "FFrameAction"
		pencil.custom_minimum_size = Kit.pxv(20, 20)
		pencil.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pencil.tooltip_text = "Group"
		var pen := GuiAssets.core_sprite("rename-icon.png")
		if pen != null:
			pencil.icon = pen
			pencil.expand_icon = true
		pencil.name = "GroupButton"
		var editor := group_editor(screen, i, group)
		var toggle_editor := func() -> void:
			editor.visible = not editor.visible
			if editor.visible:
				(editor.find_child("GroupName", true, false) as LineEdit).grab_focus()
		pencil.pressed.connect(toggle_editor)
		hr.add_child(pencil)
		if float(sec.get("m", 1)) != 1.0:
			hr.add_child(Kit.label("× %s" % _num(float(sec.get("m", 1)))))
		var fill := Kit.panel("FDraggable")
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fill.custom_minimum_size.y = Kit.px(24)
		fill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hr.add_child(fill)
		var del := Button.new()
		del.theme_type_variation = "FRedButton"
		del.focus_mode = Control.FOCUS_NONE
		del.custom_minimum_size = Kit.pxv(28, 28)
		del.tooltip_text = "Delete section"
		var trash := GuiAssets.core_sprite("icons/mip/trash-white.png")
		if trash != null:
			del.icon = trash
			del.expand_icon = true
		else:
			del.text = "✕"
		del.pressed.connect(func() -> void: Bridge.send({"t": "set_section", "u": unit, "i": i, "del": 1}))
		hr.add_child(del)
		box.add_child(head)
		box.add_child(editor)
		var filters: Array = (sec.get("f") as Array).duplicate(true) if sec.get("f") is Array else []
		var send := func(l: Array) -> void: Bridge.send({"t": "set_section", "u": unit, "i": i, "f": l})
		box.add_child(slots.call(sec, filters, send))
	var add := MenuKit.button("Add section")
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(func() -> void: Bridge.send({"t": "set_section", "u": unit, "i": 0}))
	box.add_child(add)
	return box


# --- the agricultural tower ---------------------------------------------------------------------------

## "Input" (seeds) and "Output" rows, faint cells to the end of each row.
static func agricultural_tower(screen, body: Control) -> void:
	for pair in [["Input", "input"], ["Output", "output"]]:
		if screen.knows_slots(pair[1]) or screen._last.get("inv", {}).has(pair[1]):
			body.add_child(Kit.label(pair[0], "FHeading"))
			body.add_child(bare_row(screen, pair[1]))


# --- the recipe chooser -------------------------------------------------------------------------------

## Factorio's "Select a recipe for assembling": the item group tabs (when the recipes span several
## groups), the selected group's recipes 10 wide (a new row per subgroup), and with quality the
## "Ingredient quality" row with its tick. pick(recipe) sets one; done() closes the chooser.
static func recipe_chooser(screen, recipes: Array, groups: Array, current: String, group: String,
		on_group: Callable, pick: Callable, quality: String, on_quality: Callable, done: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	# [recipe, group, group order, subgroup key, order], sorted like Factorio's grid.
	var rows: Array = []
	for i in recipes.size():
		var g: Array = groups[i] if i < groups.size() and groups[i] is Array and (groups[i] as Array).size() >= 4 else ["", "", "", ""]
		rows.append([str(recipes[i]), str(g[0]), str(g[1]), str(g[2]), str(g[3])])
	rows.sort_custom(func(a, b) -> bool:
		for k in [2, 1, 3, 4, 0]:
			if a[k] != b[k]:
				return a[k] < b[k]
		return false)
	var group_names: Array = []
	for r in rows:
		if not group_names.has(r[1]):
			group_names.append(r[1])
	if not group_names.has(group):
		group = ""
		for r in rows:
			if r[0] == current:
				group = r[1]
		if group == "" and not group_names.is_empty():
			group = group_names[0]
	var deep := Kit.panel("FDeepFrame")
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	deep.add_child(inner)
	if group_names.size() > 1:
		var tabs := HBoxContainer.new()
		tabs.add_theme_constant_override("separation", 0)
		for g in group_names:
			var b := Button.new()
			b.theme_type_variation = "FTab"
			b.toggle_mode = true
			b.button_pressed = g == group
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Kit.pxv(Kit.SLOT * Kit.COLUMNS / maxf(1.0, minf(group_names.size(), 6.0)), 64)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.tooltip_text = Kit.group_name(str(g))
			var tex := GuiAssets.group_icon(str(g))
			if tex != null:
				b.icon = tex
				b.expand_icon = true
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				b.add_theme_constant_override("icon_max_width", Kit.px(56))
			else:
				b.text = Kit.group_name(str(g))
				b.clip_text = true
			var name := str(g)
			b.pressed.connect(func() -> void: on_group.call(name))
			tabs.add_child(b)
		inner.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.custom_minimum_size = Vector2(Kit.px(Kit.SLOT * Kit.COLUMNS), Kit.px(Kit.SLOT * CHOOSER_ROWS))
	var grid := Kit.slot_grid()
	scroll.add_child(grid)
	inner.add_child(scroll)
	# The recipes of the group, or with a search every recipe whose name has the text, Factorio's way.
	var fill := func(query: String) -> void:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
		query = query.strip_edges().to_lower()
		var cells := 0
		var sub := ""
		for r in rows:
			if query != "":
				if not (Kit.recipe_name(str(r[0])).to_lower().contains(query) or str(r[0]).contains(query)):
					continue
			elif group_names.size() > 1 and r[1] != group:
				continue
			if cells > 0 and r[3] != sub and cells % Kit.COLUMNS != 0 and query == "":
				while cells % Kit.COLUMNS != 0:
					grid.add_child(Kit.empty_cell())
					cells += 1
			sub = r[3]
			var name: String = r[0]
			var s := Slot.new()
			s.theme_type_variation = "FSlotButton"
			s.toggle_mode = true
			s.button_pressed = name == current
			s.set_stack(name, -1)
			s.set_tip(Kit.recipe_name(name))
			var on_pick := func(button_index: int, _shift: bool) -> void:
				if button_index == MOUSE_BUTTON_LEFT:
					pick.call(name)
			s.clicked.connect(on_pick)
			grid.add_child(s)
			cells += 1
		while cells < Kit.COLUMNS * CHOOSER_ROWS or cells % Kit.COLUMNS != 0:
			grid.add_child(Kit.empty_cell())
			cells += 1
	# Factorio's search (Ctrl+F or the title bar's magnifier): shown while it has focus or text; Esc
	# clears it, then hides it.
	var search := MenuKit.textbox(str(screen.get_meta("chooser_search", "")), "Search recipes (Esc: clear)")
	search.name = "ChooserSearch"
	search.visible = search.text != ""
	var on_text := func(t: String) -> void:
		screen.set_meta("chooser_search", t)
		fill.call(t)
	search.text_changed.connect(on_text)
	var on_key := func(ev: InputEvent) -> void:
		var k := ev as InputEventKey
		if k != null and k.pressed and k.physical_keycode == KEY_ESCAPE:
			if search.text != "":
				search.text = ""
				on_text.call("")
			else:
				search.visible = false
				search.release_focus()
			search.accept_event()
	search.gui_input.connect(on_key)
	box.add_child(search)
	box.move_child(search, 0)
	fill.call(search.text)
	box.add_child(deep)
	var qualities: Array = screen._last.get("ql") if screen._last.get("ql") is Array else []
	if qualities.size() > 1:
		var foot := Kit.panel("FSubheader")
		var fr := _row(4)
		foot.add_child(fr)
		var l := Kit.label("Ingredient quality")
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fr.add_child(l)
		var group_q := ButtonGroup.new()
		for q in qualities:
			var qb := Button.new()
			qb.theme_type_variation = "FSlotButton"
			qb.toggle_mode = true
			qb.button_group = group_q
			qb.focus_mode = Control.FOCUS_NONE
			qb.custom_minimum_size = Kit.pxv(28, 28)
			qb.button_pressed = str(q) == quality
			qb.tooltip_text = Kit.pretty(str(q)).capitalize()
			var qt := Slot.quality_icon(str(q)) if str(q) != "normal" else GuiAssets.data_sprite("base/graphics/icons/quality-normal.png")
			if qt != null:
				qb.icon = qt
				qb.expand_icon = true
			else:
				qb.text = str(q).substr(0, 1).to_upper()
			var qname := str(q)
			qb.pressed.connect(func() -> void: on_quality.call(qname))
			fr.add_child(qb)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fr.add_child(spacer)
		var ok := Button.new()
		ok.theme_type_variation = "FGreenButton"
		ok.focus_mode = Control.FOCUS_NONE
		ok.custom_minimum_size = Kit.pxv(28, 28)
		ok.tooltip_text = "Confirm"
		var tick := GuiAssets.core_sprite("icons/mip/check-mark-white.png")
		if tick != null:
			ok.icon = tick
			ok.expand_icon = true
		else:
			ok.text = "✓"
		ok.pressed.connect(done)
		fr.add_child(ok)
		box.add_child(foot)
	return box
