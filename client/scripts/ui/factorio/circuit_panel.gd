extends RefCounted
## Factorio's "Circuit connection" and "Logistic connection" settings from the mod's `gui.cc`
## (circuit_settings.lua): {o (control behaviour type), w (on a circuit network), ln (inside a
## logistic network), nets {r, g} (network ids), f {field: value}}, for circuit_window.gd's docked
## window. SPECS lists, per behaviour type, the rows Factorio's window has in its order and words;
## rows that read out to the network go under "Output", the rest under "Input". A field the mod
## sends that no spec names still gets a plain row, so nothing is left out. Changes go to the mod
## at once as `set_cc` with just the changed field, as Factorio applies them immediately.
##
## Also the combinators' windows in Factorio's layout: the "Input / Output: Connected to" strip,
## arithmetic (Input and Output), decider (Conditions with AND/OR and R/G, Outputs and Else
## outputs), selector (every mode), constant (the Output switch and sections), the input and output
## signal strips and "Add description".
##
## Row specs: ["b", field, label, children?] a checkbox whose children show under it (greyed while
## it is unticked); ["c", field, label?] a condition; ["s", field, label?] a signal; ["e", field,
## [[value, label]...]] radio buttons. A child may end with {field: value} to show only while that
## field has the value.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const LogicKit := preload("res://scripts/ui/factorio/logic_kit.gd")

const SIGNAL_KINDS := ["item", "fluid", "virtual"]
const ENABLE := ["b", "circuit_enable_disable", "Enable if", [["c", "circuit_condition"]]]
const CRAFTER := [
	["b", "circuit_read_contents", "Read contents", [["b", "include_in_crafting", "Include in crafting"]]],
	["b", "circuit_read_ingredients", "Read ingredients"],
	["b", "circuit_read_recipe_finished", "Read recipe finished", [["s", "circuit_recipe_finished_signal"]]],
	["b", "circuit_read_working", "Read working", [["s", "circuit_working_signal"]]],
	["b", "read_fuel", "Read fuel"],
	ENABLE,
]
const CHEST := [
	["b", "read_contents", "Read contents"],
	["b", "read_empty_slots", "Read empty slots", [["s", "empty_slots_signal"]]],
]
const RAIL_SIGNAL := [
	["b", "close_signal", "Close signal", [["c", "circuit_condition"]]],
	["b", "read_signal", "Read signal", [["s", "red_signal", "Red"], ["s", "orange_signal", "Yellow"], ["s", "green_signal", "Green"],
		["s", "blue_signal", "Blue"]]],
]
const SPECS := {
	"generic_on_off": [ENABLE],
	"land_mine": [ENABLE],
	"inserter": [
		["b", "circuit_set_filters", "Set filters"],
		ENABLE,
		["b", "circuit_read_hand_contents", "Read hand contents", [["e", "circuit_hand_read_mode", [["pulse", "Pulse"], ["hold", "Hold"]]]]],
		["b", "circuit_set_stack_size", "Set stack size", [["s", "circuit_stack_control_signal"]]],
	],
	"transport_belt": [
		ENABLE,
		["b", "read_contents", "Read belt contents", [["e", "read_contents_mode",
			[["pulse", "Pulse"], ["hold", "Hold"], ["entire_belt_hold", "Hold (all belts)"]]]]],
	],
	"assembling_machine": [["b", "circuit_set_recipe", "Set recipe"]] + CRAFTER,
	"furnace": CRAFTER,
	"lamp": [
		ENABLE,
		["b", "use_colors", "Use colors", [
			["e", "color_mode", [["color_mapping", "Color mapping"], ["components", "Components (RGB)"], ["packed_rgb", "Packed RGB"]]],
			["s", "red_signal", "Red", {"color_mode": "components"}], ["s", "green_signal", "Green", {"color_mode": "components"}],
			["s", "blue_signal", "Blue", {"color_mode": "components"}], ["s", "rgb_signal", "RGB", {"color_mode": "packed_rgb"}],
		]],
	],
	"mining_drill": [
		ENABLE,
		["b", "circuit_read_resources", "Read resources", [["e", "resource_read_mode", [["this_miner", "This miner"], ["entire_patch", "Entire patch"]]]]],
	],
	"pump": [ENABLE, ["b", "set_filter", "Set filter"]],
	"train_stop": [],  # the stop's own window has the rest (entity_panels.gd)
	"turret": [
		ENABLE,
		["b", "read_ammo", "Read ammo"],
		["b", "set_priority_list", "Set priority list"],
		["b", "set_ignore_unlisted_targets", "Set ignore unlisted targets", [["c", "ignore_unlisted_targets_condition"]]],
	],
	"artillery_turret": [ENABLE, ["b", "read_ammo", "Read ammo"]],
	"boiler": [ENABLE, ["b", "read_fuel", "Read fuel"]],
	"loader": [["b", "circuit_set_filters", "Set filters"], ENABLE, ["b", "circuit_read_transfers", "Read transfers"]],
	"agricultural_tower": [
		ENABLE,
		["b", "read_contents", "Read contents"],
		["b", "enable_planting_condition", "Planting condition", [["c", "planting_condition"]]],
		["b", "enable_harvesting_condition", "Harvesting condition", [["c", "harvesting_condition"]]],
	],
	"asteroid_collector": [ENABLE, ["b", "set_filter", "Set filter"], ["b", "read_content", "Read contents", [["b", "include_hands", "Include hands"]]]],
	"rail_signal": RAIL_SIGNAL,
	"rail_chain_signal": RAIL_SIGNAL,
	"container": CHEST,
	"proxy_container": CHEST,
	"logistic_container": [
		["b", "read_contents", "Read contents"],
		["b", "set_requests", "Set requests"],
		["b", "circuit_condition_enabled", "Enable if", [["c", "circuit_condition"]]],
		["b", "read_empty_slots", "Read empty slots", [["s", "empty_slots_signal"]]],
	],
	"roboport": [
		["e", "read_items_mode", [["none", "None"], ["logistics", "Read logistic network contents"], ["missing_requests", "Read missing requests"]]],
		["b", "read_robot_stats", "Read robot statistics", [
			["s", "available_logistic_output_signal", "Available logistic robots"], ["s", "total_logistic_output_signal", "Total logistic robots"],
			["s", "available_construction_output_signal", "Available construction robots"],
			["s", "total_construction_output_signal", "Total construction robots"], ["s", "roboport_count_output_signal", "Roboports"],
		]],
	],
	"accumulator": [["b", "read_charge", "Read charge"], ["s", "output_signal", "Output signal"]],
	"wall": [["b", "open_gate", "Open gate", [["c", "circuit_condition"]]], ["b", "read_sensor", "Read sensor", [["s", "output_signal"]]]],
	"programmable_speaker": [],  # the speaker's own window has its condition (logic_windows.gd)
	"reactor": [["b", "read_fuel", "Read fuel"], ["b", "read_temperature", "Read temperature", [["s", "temperature_signal"]]]],
	"heat_pipe": [["b", "read_temperature", "Read temperature", [["s", "temperature_signal"]]]],
	"single_fluid_box": [
		["e", "circuit_exclusive_mode_of_operation", [["none", "None"], ["send_contents", "Read contents"], ["send_segment_contents", "Read segment contents"]]],
		["b", "read_temperature", "Read temperature", [["s", "temperature_signal"]]],
	],
	"radar": [["e", "mode", [["surface", "Surface"], ["universe", "Universe"]]], ["s", "universe_channel", "Channel", {"mode": "universe"}]],
	"lab": [
		["b", "read_contents", "Read contents"], ["b", "read_fuel", "Read fuel"], ["b", "read_research_cost", "Read research cost"],
		["b", "read_technology_level", "Read technology level", [["s", "technology_level_signal"]]], ["b", "set_research", "Set research"],
	],
	"splitter": [
		["b", "set_input_side", "Set input side", [["c", "input_left_condition", "Left"], ["c", "input_right_condition", "Right"]]],
		["b", "set_output_side", "Set output side", [["c", "output_left_condition", "Left"], ["c", "output_right_condition", "Right"]]],
		["b", "set_filter", "Set filter"],
	],
	"rocket_silo": [
		["e", "read_mode", [["none", "None"], ["logistic_inventory", "Read logistic inventory"], ["orbital_requests", "Read orbital requests"]]],
		["b", "read_launched", "Read launched", [["s", "launched_signal"]]],
	],
	"cargo_landing_pad": [
		["b", "read_contents", "Read contents"], ["b", "set_requests", "Set requests"],
		["b", "read_empty_slots", "Read empty slots", [["s", "empty_slots_signal"]]],
	],
	"space_platform_hub": [
		["b", "read_contents", "Read contents"], ["b", "set_requests", "Set requests"], ["b", "send_to_platform", "Send to platform"],
		["b", "read_moving_from", "Read moving from"], ["b", "read_moving_to", "Read moving to"],
		["b", "read_speed", "Read speed", [["s", "speed_signal"]]], ["b", "read_damage_taken", "Read damage taken", [["s", "damage_taken_signal"]]],
		["b", "read_empty_slots", "Read empty slots", [["s", "empty_slots_signal"]]],
	],
}
## Logistic connection rows (types with LuaGenericOnOffControlBehavior).
const LOGISTIC := ["b", "connect_to_logistic_network", "Connect to logistic network", [["c", "logistic_condition"]]]
const COMPARATORS := [">", "<", "=", "≥", "≤", "≠"]
const QUALITIES := ["normal", "uncommon", "rare", "epic", "legendary"]


# --- the circuit and logistic connection (circuit_window.gd's contents) --------------------------

## Fields read out to the network go under "Output", the rest (conditions, set_*) under "Input",
## as Factorio's circuit connection window splits them.
static func _section_of(row_spec: Array) -> String:
	var f := str(row_spec[1])
	return "Output" if f.contains("read") or f.begins_with("send_") or f.ends_with("output_signal") else "Input"


## The circuit connection's sections for gui.cc: [[title, [row controls]], ...]; empty when the
## behaviour type has no settings.
static func sections(screen, cc: Dictionary) -> Array:
	var f: Dictionary = cc.get("f") if cc.get("f") is Dictionary else {}
	var spec: Array = SPECS.get(str(cc.get("o", "")), [])
	if spec.is_empty() and SPECS.has(str(cc.get("o", ""))):
		return []  # settings the entity's own window shows
	var send := func(field: String, value) -> void: screen.model.set_circuit(screen.unit, {field: value})
	var by := {"Input": [], "Output": []}
	for row_spec in spec:
		var r := _row(screen, row_spec, f, send, true)
		if r != null:
			by[_section_of(row_spec)].append(r)
	for field in _unlisted(spec, f):
		var r := _plain_row(screen, str(field), f, send)
		if r != null:
			by["Input"].append(r)
	var out: Array = []
	for title in ["Input", "Output"]:
		if not (by[title] as Array).is_empty():
			out.append([title, by[title]])
	return out


## The logistic connection's row, or null when the entity can't connect to a logistic network.
static func logistic_row(screen, cc: Dictionary) -> Control:
	var f: Dictionary = cc.get("f") if cc.get("f") is Dictionary else {}
	if not f.has("connect_to_logistic_network"):
		return null
	var send := func(field: String, value) -> void: screen.model.set_circuit(screen.unit, {field: value})
	return _row(screen, LOGISTIC, f, send, true)


## "Red network 5  Green network 6", or "Not connected".
static func network_line(nets) -> Control:
	var r := EntityPanels.row(6)
	var parts := 0
	if nets is Dictionary:
		for wire in [["r", "red", LogicKit.RED_WIRE], ["g", "green", LogicKit.GREEN_WIRE]]:
			var id := int(nets.get(wire[0], 0))
			if id > 0:
				var l := Kit.label("%s network %d" % [str(wire[1]).capitalize(), id])
				l.add_theme_color_override("font_color", wire[2])
				r.add_child(l)
				parts += 1
	if parts == 0:
		r.add_child(Kit.label("Not connected"))
	r.name = "CircuitNetworks"
	return r


## Fields the mod sent that no row of the spec shows (a newer game's settings).
static func _unlisted(spec: Array, f: Dictionary) -> Array:
	var named := {"connect_to_logistic_network": true, "logistic_condition": true}
	var stack: Array = spec.duplicate()
	while not stack.is_empty():
		var s = stack.pop_back()
		if s is Array and s.size() >= 2:
			named[str(s[1])] = true
			if s.size() >= 4 and s[3] is Array:
				stack.append_array(s[3])
	var out: Array = []
	for k in f.keys():
		if not named.has(str(k)):
			out.append(k)
	out.sort()
	return out


static func _shown(row_spec: Array, f: Dictionary) -> bool:
	var last = row_spec[row_spec.size() - 1]
	if last is Dictionary:
		for k in last:
			if str(f.get(k, "")) != str(last[k]):
				return false
	return f.has(str(row_spec[1]))


## One row of a spec. As in Factorio, what belongs to a checkbox stays on screen under it, greyed
## while it is unticked.
static func _row(screen, row_spec: Array, f: Dictionary, send: Callable, enabled: bool) -> Control:
	if not _shown(row_spec, f):
		return null
	var kind := str(row_spec[0])
	var field := str(row_spec[1])
	match kind:
		"b":
			var col := EntityPanels.column(4)
			var on := int(f.get(field, 0)) == 1
			var cb := EntityPanels.checkbox(str(row_spec[2]), on, func(v: bool) -> void: send.call(field, 1 if v else 0))
			cb.name = field
			cb.disabled = not enabled
			cb.add_theme_font_override("font", Kit.font("bold"))
			col.add_child(cb)
			if row_spec.size() >= 4 and row_spec[3] is Array:
				var inner := EntityPanels.column(4)
				var pad := MarginContainer.new()
				pad.add_theme_constant_override("margin_left", Kit.px(4))
				pad.add_child(inner)
				for child in row_spec[3]:
					var c := _row(screen, child, f, send, enabled and on)
					if c != null:
						inner.add_child(c)
				if inner.get_child_count() > 0:
					col.add_child(pad)
			return col
		"c":
			var r := EntityPanels.row(6)
			if row_spec.size() >= 3 and row_spec[2] is String:
				r.add_child(Kit.label(str(row_spec[2])))
			var cond: Dictionary = (f.get(field) as Dictionary).duplicate(true) if f.get(field) is Dictionary else {"comparator": "<", "constant": 0}
			cond.erase("ful")
			r.add_child(EntityPanels._condition_editor(screen, cond, SIGNAL_KINDS, func(c: Dictionary) -> void: send.call(field, c)))
			_enable_all(r, enabled)
			return r
		"s":
			var r := EntityPanels.row(6)
			var set_sig := func(type_name: String, name: String) -> void:
				send.call(field, {"type": type_name, "name": name} if name != "" else {})
			r.add_child(EntityPanels.choose_slot(screen, EntityPanels._signal_name(f.get(field)), SIGNAL_KINDS, set_sig, "Signal"))
			var text: String = str(row_spec[2]) if row_spec.size() >= 3 and row_spec[2] is String else "Output signal"
			var l := Kit.label(text)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			r.add_child(l)
			_enable_all(r, enabled)
			return r
		"e":
			var radios := EntityPanels.radios(row_spec[2], str(f.get(field, "")), func(v: String) -> void: send.call(field, v))
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", Kit.px(2))
			for c in radios.get_children():
				radios.remove_child(c)
				col.add_child(c)
			radios.queue_free()
			col.name = field
			_enable_all(col, enabled)
			return col
	return null


## Greys a row's buttons, slots and fields (Factorio keeps them on screen).
static func _enable_all(node: Node, on: bool) -> void:
	if on:
		return
	var all: Array = node.find_children("*", "", true, false)
	all.append(node)
	for c in all:
		if c is BaseButton:
			(c as BaseButton).disabled = true
		elif c is LineEdit:
			(c as LineEdit).editable = false
	if node is CanvasItem:
		(node as CanvasItem).modulate.a = 0.6


## A row for a field no spec names: a checkbox, a condition, a signal or the value as text.
static func _plain_row(screen, field: String, f: Dictionary, send: Callable) -> Control:
	var v = f.get(field)
	var label := field.capitalize()
	if v is Dictionary and v.has("comparator"):
		return _row(screen, ["c", field, label], f, send, true)
	if (v is Dictionary or v is Array) and field.ends_with("_signal"):
		return _row(screen, ["s", field, label], f, send, true)
	if v is float or v is int:
		return _row(screen, ["b", field, label], f, send, true)
	return Kit.label("%s: %s" % [label, str(v).capitalize()])


## A train stop's circuit connection (gui.stop.cb) as sections: its own flags and signals.
static func stop_sections(screen, cb: Dictionary) -> Array:
	var set_key := func(key: String, value) -> void: screen.model.set_stop_settings(screen.unit, {"cb": {key: value}})
	var input := EntityPanels.column(6)
	var en := int(cb.get("en", 0)) == 1
	var en_box := EntityPanels.checkbox("Enable if", en, func(on: bool) -> void: set_key.call("en", 1 if on else 0))
	en_box.add_theme_font_override("font", Kit.font("bold"))
	input.add_child(en_box)
	var cond: Dictionary = (cb.get("cond") as Dictionary).duplicate(true) if cb.get("cond") is Dictionary else {"comparator": "<", "constant": 0}
	var cond_row := EntityPanels._condition_editor(screen, cond, SIGNAL_KINDS, func(c: Dictionary) -> void: set_key.call("cond", c))
	_enable_all(cond_row, en)
	input.add_child(cond_row)
	input.add_child(EntityPanels.checkbox("Send to train", int(cb.get("send", 0)) == 1, func(on: bool) -> void: set_key.call("send", 1 if on else 0)))
	var output := EntityPanels.column(6)
	output.add_child(EntityPanels.checkbox("Read train contents", int(cb.get("read", 0)) == 1, func(on: bool) -> void: set_key.call("read", 1 if on else 0)))
	for spec in [["stopped", "stopped_sig", "Read stopped train", output], ["limit", "limit_sig", "Set trains limit", input],
			["count", "count_sig", "Read trains count", output], ["pri", "pri_sig", "Set priority", input]]:
		var r := EntityPanels.row(8)
		var flag: String = spec[0]
		var sig_key: String = spec[1]
		var on := int(cb.get(flag, 0)) == 1
		r.add_child(EntityPanels.checkbox(spec[2], on, func(v: bool) -> void: set_key.call(flag, 1 if v else 0)))
		var set_sig := func(type_name: String, name: String) -> void:
			set_key.call(sig_key, {"type": type_name, "name": name} if name != "" else {})
		var slot := EntityPanels.choose_slot(screen, EntityPanels._signal_name(cb.get(sig_key)), SIGNAL_KINDS, set_sig, "Signal")
		_enable_all(slot, on)
		LogicKit.push_right(r, slot)
		(spec[3] as VBoxContainer).add_child(r)
	return [["Input", [input]], ["Output", [output]]]


# --- combinators ---------------------------------------------------------------------------------

## The combinator's kind from its settings and prototype.
static func combinator_kind(screen, cb: Dictionary) -> String:
	var proto := str(screen.proto_name)
	if cb.has("signals") or cb.has("sections") or proto == "constant-combinator":
		return "constant"
	if cb.has("conditions") or proto == "decider-combinator":
		return "decider"
	if proto == "selector-combinator" or SELECTOR_OPS.has(str(cb.get("operation", ""))):
		return "selector"
	return "arithmetic"


## Factorio's combinator window: the "Input / Output: Connected to" strip at the top, the
## combinator's settings, the input and output signals (arithmetic and decider), a line and
## "Add description".
static func combinator_window(screen, last: Dictionary, body: VBoxContainer) -> void:
	var cb: Dictionary = last["cb"]
	var kind := combinator_kind(screen, cb)
	var sig: Dictionary = last.get("sig") if last.get("sig") is Dictionary else {}
	var out: Dictionary = sig.get("out") if sig.get("out") is Dictionary else {}
	var sh := LogicKit.subheader()
	var head: HBoxContainer = sh[1]
	if kind == "constant":
		head.add_child(LogicKit.connected_line("", sig))
	else:
		head.add_child(LogicKit.connected_line("Input", sig))
		LogicKit.push_right(head, LogicKit.connected_line("Output", out))
	var strip := LogicKit.bleed(sh[0])
	body.add_child(strip)
	body.move_child(strip, 0)
	body.add_child(combinator(screen, cb))
	if kind == "arithmetic" or kind == "decider":
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", Kit.px(12))
		for part in [["Input signals", _tagged(sig), "InputSignals"], ["Output signals", _tagged(out), "OutputSignals"]]:
			var col := EntityPanels.column(4)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(Kit.label(str(part[0]), "FHeading"))
			col.add_child(LogicKit.signal_strip(part[1], Kit.COLUMNS, 1, str(part[2])))
			cols.add_child(col)
		body.add_child(cols)
	body.add_child(LogicKit.line())
	body.add_child(description(screen, str(last.get("desc", ""))))


## A side's signals with their wire: [[type, name, count, "r" | "g"], ...].
static func _tagged(sig: Dictionary) -> Array:
	var out: Array = []
	for wire in ["r", "g"]:
		var list = sig.get(wire)
		if list is Array:
			for s in list:
				if s is Array and s.size() >= 3:
					out.append([s[0], s[1], s[2], wire])
	return out


## "Add description": a text box that opens under it, sent with the confirm button.
static func description(screen, desc: String) -> Control:
	var box := EntityPanels.column(6)
	box.name = "Description"
	if desc != "":
		box.add_child(MenuKit.paragraph(desc, 400))
	var edit := EntityPanels.column(4)
	edit.visible = false
	var text := TextEdit.new()
	text.name = "DescriptionText"
	text.text = desc
	text.custom_minimum_size = Kit.pxv(400, 100)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.add_child(text)
	var ok := MenuKit.button("Confirm", "FGreenButton")
	ok.name = "ConfirmDescription"
	ok.pressed.connect(func() -> void: Bridge.send({"t": "set_desc", "u": screen.unit, "text": text.text}))
	edit.add_child(ok)
	var b := MenuKit.button("Edit description" if desc != "" else "Add description")
	b.name = "AddDescription"
	b.custom_minimum_size.x = Kit.px(116)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func() -> void:
		edit.visible = not edit.visible
		if edit.visible:
			text.grab_focus())
	box.add_child(b)
	box.add_child(edit)
	return box


static func _signal(sig) -> String:
	return EntityPanels._signal_name(sig)


static func _sig_value(type_name: String, name: String):
	return {"type": type_name, "name": name} if name != "" else null


## The second operand as Factorio's one "signal or constant" button: the signal's icon, or the
## constant written on a dark button ("1.1k"). A click opens the signal chooser with its Constant
## box (item_picker.gd choose_or_constant); right click clears the signal back to a constant.
static func _operand(screen, sig, constant, on_signal: Callable, on_constant: Callable) -> Control:
	var name := _signal(sig)
	var value := int(constant) if constant != null else 0
	var open := func() -> void:
		if screen.picker != null:
			screen.picker.choose_or_constant(SIGNAL_KINDS, on_signal, value, on_constant)
	if name != "":
		var s := Slot.new()
		s.name = "SecondOperand"
		s.theme_type_variation = "FSlotButton"
		s.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		s.set_stack(name, -1)
		s.set_tip(Kit.pretty(name), [["Click: a signal or a constant · Right click: clear", "", Kit.DISABLED_TEXT]])
		s.clicked.connect(func(button_index: int, _shift: bool) -> void:
			if button_index == MOUSE_BUTTON_RIGHT:
				on_constant.call(0)
			elif button_index == MOUSE_BUTTON_LEFT:
				open.call())
		return s
	var b := Button.new()
	b.name = "SecondOperand"
	b.text = ("-" if value < 0 else "") + Kit.count_text(absi(value))
	b.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%d\nClick: a signal or a constant" % value
	var dark := StyleBoxFlat.new()
	dark.bg_color = Color8(28, 27, 28)
	dark.set_border_width_all(Kit.px(1))
	dark.border_color = Color8(12, 12, 12)
	dark.set_corner_radius_all(Kit.px(3))
	var hover := dark.duplicate() as StyleBoxFlat
	hover.border_color = Color8(255, 175, 0)
	for state in ["normal", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, dark)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_color_override("font_color", Kit.WHITE)
	b.add_theme_color_override("font_hover_color", Kit.WHITE)
	b.add_theme_font_size_override("font_size", Kit.px(16))
	b.pressed.connect(open)
	return b


static func _comparator(current: String, on_pick: Callable) -> OptionButton:
	var cmp := MenuKit.dropdown(COMPARATORS.map(func(o): return [o, o]), current)
	cmp.custom_minimum_size.x = Kit.px(52)
	cmp.item_selected.connect(func(k: int) -> void: on_pick.call(COMPARATORS[k]))
	return cmp


## Arithmetic: Input (R/G, first signal, operation, R/G, second signal or constant) and Output.
static func arithmetic(screen, cb: Dictionary) -> Control:
	var send := func(c: Dictionary) -> void: screen.model.set_combinator(screen.unit, c)
	var with := func(key: String, value) -> void:
		var c := cb.duplicate(true)
		if value == null:
			c.erase(key)
		else:
			c[key] = value
		send.call(c)
	var signal_setter := func(sig_key: String, const_key: String) -> Callable:
		return func(type_name: String, name: String) -> void:
			var c := cb.duplicate(true)
			if name == "":
				c.erase(sig_key)
			else:
				c[sig_key] = {"type": type_name, "name": name}
				c.erase(const_key)
			send.call(c)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", Kit.px(12))
	var input := EntityPanels.column(4)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_child(Kit.label("Input", "FHeading"))
	var line := EntityPanels.row(6)
	line.add_child(LogicKit.wire_checks(cb.get("first_signal_networks"), func(n: Dictionary) -> void: with.call("first_signal_networks", n)))
	line.add_child(EntityPanels.choose_slot(screen, _signal(cb.get("first_signal")), SIGNAL_KINDS, signal_setter.call("first_signal", "first_constant"), "Signal"))
	var ops := MenuKit.dropdown(EntityPanels.ARITHMETIC_OPS.map(func(o): return [o, o]), str(cb.get("operation", "*")))
	ops.name = "Operation"
	ops.custom_minimum_size.x = Kit.px(56)
	ops.item_selected.connect(func(i: int) -> void: with.call("operation", EntityPanels.ARITHMETIC_OPS[i]))
	line.add_child(ops)
	line.add_child(LogicKit.wire_checks(cb.get("second_signal_networks"), func(n: Dictionary) -> void: with.call("second_signal_networks", n)))
	line.add_child(_operand(screen, cb.get("second_signal"), cb.get("second_constant"), signal_setter.call("second_signal", "second_constant"),
		func(v: int) -> void:
			var c := cb.duplicate(true)
			c.erase("second_signal")
			c["second_constant"] = v
			send.call(c)))
	input.add_child(line)
	cols.add_child(input)
	var output := EntityPanels.column(4)
	output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output.add_child(Kit.label("Output", "FHeading"))
	output.add_child(EntityPanels.choose_slot(screen, _signal(cb.get("output_signal")), SIGNAL_KINDS, signal_setter.call("output_signal", ""), "Output"))
	cols.add_child(output)
	return cols


## 2.x decider: Conditions on the left (each with an AND/OR button before it, R/G per operand,
## remove), Outputs and Else outputs on the right ("1" or "Input count" with R/G).
static func decider(screen, cb: Dictionary) -> Control:
	var conditions: Array = (cb.get("conditions") as Array).duplicate(true) if cb.get("conditions") is Array else []
	var outputs: Array = (cb.get("outputs") as Array).duplicate(true) if cb.get("outputs") is Array else []
	var else_outputs: Array = (cb.get("else_outputs") as Array).duplicate(true) if cb.get("else_outputs") is Array else []
	var send := func() -> void:
		var c := cb.duplicate(true)
		c["conditions"] = conditions
		c["outputs"] = outputs
		if not else_outputs.is_empty() or cb.has("else_outputs"):
			c["else_outputs"] = else_outputs
		screen.model.set_combinator(screen.unit, c)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", Kit.px(12))
	var left := EntityPanels.column(4)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(Kit.label("Conditions", "FHeading"))
	var frame := Kit.panel("FDeepFrame")
	var list := EntityPanels.column(4)
	list.name = "Conditions"
	frame.add_child(LogicKit.padded(list, 4, 4))
	for i in conditions.size():
		if conditions[i] is Dictionary:
			list.add_child(_decider_condition(screen, conditions, i, send))
	list.add_child(LogicKit.wide_button("+ Add condition", func() -> void:
		conditions.append({"comparator": "<", "constant": 0, "compare_type": "or"})
		send.call()))
	left.add_child(frame)
	cols.add_child(left)
	var right := EntityPanels.column(4)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(Kit.label("Outputs", "FHeading"))
	var out_frame := Kit.panel("FDeepFrame")
	var out_list := EntityPanels.column(4)
	out_frame.add_child(LogicKit.padded(out_list, 4, 4))
	out_list.add_child(_outputs_editor(screen, outputs, send, "Outputs", "+ Add output"))
	var eh := LogicKit.subheader()
	(eh[1] as HBoxContainer).add_child(LogicKit.info_label("Else outputs", "Sent while the conditions don't hold", "FHeading"))
	out_list.add_child(eh[0])
	out_list.add_child(_outputs_editor(screen, else_outputs, send, "ElseOutputs", "+ Add else"))
	right.add_child(out_frame)
	cols.add_child(right)
	return cols


## The green Factorio puts behind a decider condition while it holds.
const HOLDS := Color8(94, 182, 76)


## Whether a decider condition holds for the input signals (`gui.sig`: r / g lists of [type, name,
## count]): the bridge sends no per-condition result, so the client works it out as the game does.
## Each operand reads the networks ticked beside it (both unless set); Anything holds if some input
## signal passes, Everything if every one does (or there are none), Each like Anything.
static func condition_holds(c: Dictionary, sig: Dictionary) -> bool:
	var first := _signal(c.get("first_signal"))
	if first == "":
		return false
	var a_vals := _input_values(sig, c.get("first_signal_networks"))
	var second := _signal(c.get("second_signal"))
	var b := _value_of(_input_values(sig, c.get("second_signal_networks")), second) if second != "" else int(c.get("constant", 0))
	var cmp := str(c.get("comparator", "<"))
	match first:
		"signal-anything", "signal-each":
			for v in a_vals.values():
				if compare(int(v), cmp, b):
					return true
			return false
		"signal-everything":
			for v in a_vals.values():
				if not compare(int(v), cmp, b):
					return false
			return true
	return compare(_value_of(a_vals, first), cmp, b)


## name -> summed count of the input signals on the chosen networks ({red, green}, both by default).
static func _input_values(sig: Dictionary, nets) -> Dictionary:
	var n: Dictionary = nets if nets is Dictionary else {}
	var out := {}
	for wire in [["r", "red"], ["g", "green"]]:
		if not bool(n.get(wire[1], true)):
			continue
		var list = sig.get(wire[0])
		if list is Array:
			for s in list:
				if s is Array and s.size() >= 3 and int(s[2]) != 0:
					out[str(s[1])] = int(out.get(str(s[1]), 0)) + int(s[2])
	return out


static func _value_of(vals: Dictionary, name: String) -> int:
	return int(vals.get(name, 0))


static func compare(a: int, cmp: String, b: int) -> bool:
	match cmp:
		"<":
			return a < b
		">":
			return a > b
		"=":
			return a == b
		"≥", ">=":
			return a >= b
		"≤", "<=":
			return a <= b
		"≠", "!=":
			return a != b
	return false


static func _decider_condition(screen, conditions: Array, i: int, send: Callable) -> Control:
	var c: Dictionary = conditions[i]
	var outer := EntityPanels.row(4)
	var gutter := CenterContainer.new()
	gutter.custom_minimum_size.x = Kit.px(64)
	if i > 0:
		var andor := MenuKit.button(str(c.get("compare_type", "or")).to_upper())
		andor.custom_minimum_size = Kit.pxv(56, 28)
		andor.name = "AndOr"
		andor.tooltip_text = "AND: both must hold · OR: either"
		andor.pressed.connect(func() -> void:
			c["compare_type"] = "or" if str(c.get("compare_type", "or")) == "and" else "and"
			send.call())
		gutter.add_child(andor)
	outer.add_child(gutter)
	# The condition itself, on Factorio's green while it holds.
	var holder := PanelContainer.new()
	holder.name = "Condition%d" % (i + 1)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sig: Dictionary = screen._last.get("sig") if screen._last.get("sig") is Dictionary else {}
	var holds := condition_holds(c, sig)
	holder.set_meta("holds", holds)
	var bg := StyleBoxFlat.new()
	bg.bg_color = HOLDS if holds else Color(0, 0, 0, 0)
	bg.set_content_margin_all(Kit.px(2))
	holder.add_theme_stylebox_override("panel", bg)
	var r := EntityPanels.row(4)
	holder.add_child(r)
	outer.add_child(holder)
	r.add_child(LogicKit.wire_checks(c.get("first_signal_networks"), func(n: Dictionary) -> void:
		c["first_signal_networks"] = n
		send.call()))
	var set_first := func(t: String, n: String) -> void:
		if n == "":
			c.erase("first_signal")
		else:
			c["first_signal"] = {"type": t, "name": n}
		send.call()
	r.add_child(EntityPanels.choose_slot(screen, _signal(c.get("first_signal")), SIGNAL_KINDS, set_first, "Signal"))
	r.add_child(_comparator(str(c.get("comparator", "<")), func(v: String) -> void:
		c["comparator"] = v
		send.call()))
	r.add_child(LogicKit.wire_checks(c.get("second_signal_networks"), func(n: Dictionary) -> void:
		c["second_signal_networks"] = n
		send.call()))
	var set_second := func(t: String, n: String) -> void:
		if n == "":
			c.erase("second_signal")
		else:
			c["second_signal"] = {"type": t, "name": n}
			c.erase("constant")
		send.call()
	r.add_child(_operand(screen, c.get("second_signal"), c.get("constant", 0), set_second, func(v: int) -> void:
		c.erase("second_signal")
		c["constant"] = v
		send.call()))
	if conditions.size() > 1:
		var x := Kit.close_button()
		x.tooltip_text = "Remove this condition"
		x.pressed.connect(func() -> void:
			conditions.remove_at(i)
			send.call())
		LogicKit.push_right(r, x)
	return outer


static func _outputs_editor(screen, outputs: Array, send: Callable, node_name: String, add_text: String) -> Control:
	var col := EntityPanels.column(4)
	col.name = node_name
	for i in outputs.size():
		var o: Dictionary = outputs[i] if outputs[i] is Dictionary else {}
		outputs[i] = o
		var r := EntityPanels.row(6)
		var set_sig := func(t: String, n: String) -> void:
			if n == "":
				outputs.remove_at(i)
			else:
				o["signal"] = {"type": t, "name": n}
			send.call()
		r.add_child(EntityPanels.choose_slot(screen, _signal(o.get("signal")), SIGNAL_KINDS, set_sig, "Output"))
		var copy := bool(o.get("copy_count_from_input", true))
		var modes := EntityPanels.column(0)
		var group := ButtonGroup.new()
		var const_row := EntityPanels.row(4)
		var const_radio := CheckBox.new()
		const_radio.name = "OutConst"
		const_radio.button_group = group
		const_radio.focus_mode = Control.FOCUS_NONE
		const_radio.button_pressed = not copy
		const_radio.toggled.connect(func(on: bool) -> void:
			if on and copy:
				o["copy_count_from_input"] = false
				send.call())
		const_row.add_child(const_radio)
		const_row.add_child(EntityPanels.number_box(int(o.get("constant", 1)), func(v: int) -> void:
			o["constant"] = v
			send.call(), 56))
		modes.add_child(const_row)
		var input_row := EntityPanels.row(4)
		var input_radio := CheckBox.new()
		input_radio.name = "OutInput"
		input_radio.text = "Input count"
		input_radio.button_group = group
		input_radio.focus_mode = Control.FOCUS_NONE
		input_radio.button_pressed = copy
		input_radio.toggled.connect(func(on: bool) -> void:
			if on and not copy:
				o["copy_count_from_input"] = true
				send.call())
		input_row.add_child(input_radio)
		input_row.add_child(LogicKit.wire_checks(o.get("networks"), func(n: Dictionary) -> void:
			o["networks"] = n
			send.call(), false))
		modes.add_child(input_row)
		r.add_child(modes)
		var x := Kit.close_button()
		x.tooltip_text = "Remove this output"
		x.pressed.connect(func() -> void:
			outputs.remove_at(i)
			send.call())
		LogicKit.push_right(r, x)
		col.add_child(r)
	var add := LogicKit.wide_button(add_text, func() -> void:
		if screen.picker != null:
			screen.picker.choose(SIGNAL_KINDS, func(t: String, n: String) -> void:
				if n != "":
					outputs.append({"signal": {"type": t, "name": n}, "copy_count_from_input": true})
					send.call()))
	add.name = "Add" + node_name
	col.add_child(add)
	return col


## Selector combinator modes, Factorio's names, in its order, and what each does.
const SELECTOR_MODES := [["select", "Select input"], ["count", "Count inputs"], ["random", "Random input"],
	["stack-size", "Stack size"], ["rocket-capacity", "Rocket capacity"], ["quality-filter", "Quality filter"],
	["quality-transfer", "Quality transfer"], ["quality-select", "Select quality"], ["time", "Time"]]
const SELECTOR_OPS := ["select", "count", "random", "stack-size", "rocket-capacity", "quality-filter", "quality-transfer",
	"quality-select", "time"]
const SELECTOR_TEXT := {
	"select": "Selects a specific signal out of all input signals, based on criteria.",
	"count": "Outputs the number of distinct input signals.",
	"random": "Outputs one of the input signals at random.",
	"stack-size": "Outputs the stack size of each input item.",
	"rocket-capacity": "Outputs how many of each input item fit in a rocket.",
	"quality-filter": "Passes only the input signals of the chosen qualities.",
	"quality-transfer": "Outputs a signal with the quality of another signal.",
	"quality-select": "Outputs the highest or lowest quality among the input signals.",
	"time": "Outputs the game tick and the time of day.",
}


## The selector combinator: "Mode of operation", what the mode does, and its settings.
static func selector(screen, cb: Dictionary) -> Control:
	var box := EntityPanels.column(8)
	var op := str(cb.get("operation", "select"))
	var send := func(c: Dictionary) -> void: screen.model.set_combinator(screen.unit, c)
	var with := func(key: String, value) -> void:
		var c := cb.duplicate(true)
		if value == null:
			c.erase(key)
		else:
			c[key] = value
		send.call(c)
	var mode_row := EntityPanels.row(8)
	mode_row.add_child(Kit.label("Mode of operation", "FHeading"))
	var modes := MenuKit.dropdown(SELECTOR_MODES.map(func(m): return [m[1], m[0]]), op)
	modes.name = "SelectorMode"
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.item_selected.connect(func(i: int) -> void: send.call({"operation": SELECTOR_MODES[i][0]}))
	mode_row.add_child(modes)
	box.add_child(mode_row)
	box.add_child(MenuKit.paragraph(str(SELECTOR_TEXT.get(op, "")), 380))
	box.add_child(LogicKit.line())
	var sig_row := func(key: String, label: String) -> Control:
		var r := EntityPanels.row(6)
		r.add_child(EntityPanels.choose_slot(screen, _signal(cb.get(key)), SIGNAL_KINDS,
			func(t: String, n: String) -> void: with.call(key, _sig_value(t, n)), label))
		var l := Kit.label(label)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		r.add_child(l)
		return r
	match op:
		"select":
			var r := EntityPanels.row(6)
			r.add_child(Kit.label("Index"))
			r.add_child(_comparator(str(cb.get("index_comparator", "=")), func(v: String) -> void: with.call("index_comparator", v)))
			r.add_child(EntityPanels.choose_slot(screen, _signal(cb.get("index_signal")), SIGNAL_KINDS,
				func(t: String, n: String) -> void: with.call("index_signal", _sig_value(t, n)), "Index signal (or a constant)"))
			if _signal(cb.get("index_signal")) == "":
				r.add_child(EntityPanels.number_box(int(cb.get("index_constant", 0)), func(v: int) -> void: with.call("index_constant", v), 56))
			box.add_child(r)
			var sw := LogicKit.switch("Sort descending", "Sort ascending", "left" if bool(cb.get("select_max", true)) else "right",
				func(s: String) -> void: with.call("select_max", s == "left"))
			sw.name = "SortOrder"
			box.add_child(sw)
		"count":
			box.add_child(sig_row.call("count_signal", "Output signal"))
		"random":
			var r := EntityPanels.row(6)
			r.add_child(Kit.label("Update interval (ticks)"))
			r.add_child(EntityPanels.number_box(int(cb.get("random_update_interval", 0)), func(v: int) -> void:
				with.call("random_update_interval", maxi(0, v)), 80))
			box.add_child(r)
		"quality-filter":
			var qf: Dictionary = cb.get("quality_filter") if cb.get("quality_filter") is Dictionary else {}
			var r := EntityPanels.row(6)
			r.add_child(Kit.label("Quality"))
			r.add_child(_comparator(str(qf.get("comparator", "=")), func(v: String) -> void:
				with.call("quality_filter", {"quality": str(qf.get("quality", "normal")), "comparator": v})))
			r.add_child(_quality_dropdown(str(qf.get("quality", "normal")), func(q: String) -> void:
				with.call("quality_filter", {"quality": q, "comparator": str(qf.get("comparator", "="))})))
			box.add_child(r)
		"quality-transfer":
			var from_signal := bool(cb.get("select_quality_from_signal", false))
			box.add_child(EntityPanels.radios([["static", "Fixed quality"], ["signal", "Quality from a signal"]], "signal" if from_signal else "static",
				func(v: String) -> void: with.call("select_quality_from_signal", v == "signal")))
			if from_signal:
				box.add_child(sig_row.call("quality_source_signal", "Quality source"))
			else:
				var r := EntityPanels.row(6)
				r.add_child(Kit.label("Quality"))
				var q = cb.get("quality_source_static")
				var qname: String = str(q.get("name", "normal")) if q is Dictionary else (str(q) if q != null else "normal")
				r.add_child(_quality_dropdown(qname, func(v: String) -> void: with.call("quality_source_static", {"name": v})))
				box.add_child(r)
			box.add_child(sig_row.call("quality_destination_signal", "Output signal"))
		"quality-select":
			box.add_child(LogicKit.switch("Highest quality", "Lowest quality", "left" if bool(cb.get("select_highest_quality", true)) else "right",
				func(s: String) -> void: with.call("select_highest_quality", s == "left")))
		"time":
			box.add_child(sig_row.call("game_tick_signal", "Game tick"))
			box.add_child(sig_row.call("day_tick_signal", "Day tick"))
			box.add_child(sig_row.call("day_length_signal", "Day length"))
	return box


static func _quality_dropdown(current: String, on_pick: Callable) -> OptionButton:
	var d := MenuKit.dropdown(QUALITIES.map(func(q): return [q.capitalize(), q]), current)
	d.custom_minimum_size.x = Kit.px(130)
	d.item_selected.connect(func(i: int) -> void: on_pick.call(QUALITIES[i]))
	return d


## The constant combinator: "Output" with its Off/On switch, then its sections in a deep frame,
## each with its on/off checkbox, group name, rename and delete, and a 10-wide row of signals
## (click one to change its value, right click to remove it), and "Add section".
static func constant(screen, cb: Dictionary) -> Control:
	var sections: Array = (cb.get("sections") as Array).duplicate(true) if cb.get("sections") is Array else []
	if sections.is_empty():
		sections.append({"g": "", "on": 1, "m": 1, "s": (cb.get("signals") as Array).duplicate(true) if cb.get("signals") is Array else []})
	var on := bool(cb.get("enabled", true))
	var send := func(enabled: bool) -> void:
		screen.model.set_combinator(screen.unit, {"enabled": enabled, "sections": sections, "signals": sections[0].get("s", []) if not sections.is_empty() else []})
	var box := EntityPanels.column(6)
	box.add_child(Kit.label("Output", "FHeading"))
	var sw := LogicKit.switch("Off", "On", "right" if on else "left", func(s: String) -> void: send.call(s == "right"))
	sw.name = "OutputSwitch"
	box.add_child(sw)
	var frame := Kit.panel("FDeepFrame")
	var list := EntityPanels.column(4)
	frame.add_child(LogicKit.padded(list, 4, 4))
	for i in sections.size():
		list.add_child(_section(screen, sections[i], i, sections, func() -> void: send.call(on)))
	var add := LogicKit.wide_button("Add section", func() -> void:
		sections.append({"g": "", "on": 1, "m": 1, "s": []})
		send.call(on))
	add.name = "AddSection"
	list.add_child(add)
	box.add_child(frame)
	return box


static func _section(screen, sec: Dictionary, index: int, sections: Array, send: Callable) -> Control:
	var col := EntityPanels.column(4)
	col.name = "Section%d" % (index + 1)
	var bar := Kit.panel("FSubheader")
	bar.custom_minimum_size.y = Kit.px(32)
	var head := EntityPanels.row(6)
	bar.add_child(head)
	head.add_child(EntityPanels.checkbox("", int(sec.get("on", 1)) == 1, func(v: bool) -> void:
		sec["on"] = 1 if v else 0
		send.call()))
	var group := str(sec.get("g", ""))
	var title: Control = RichText.text_label(group, "FHeading", Kit.WHITE) if group != "" else Kit.label("[No group assigned]", "FHeading")
	title.add_theme_color_override("font_color", Kit.WHITE)
	title.set("vertical_alignment", VERTICAL_ALIGNMENT_CENTER)
	head.add_child(title)
	var field := MenuKit.textbox(group, "Group name")
	field.custom_minimum_size.x = Kit.px(180)
	field.visible = false
	field.tooltip_text = "Logistic group: sections with the same group share their signals"
	field.text_submitted.connect(func(t: String) -> void:
		field.release_focus()
		sec["g"] = t.strip_edges()
		send.call())
	head.add_child(field)
	head.add_child(LogicKit.rename_button("Set the group", func() -> void:
		title.visible = false
		field.visible = true
		field.grab_focus()))
	var trash := LogicKit.tool_button("icons/mip/trash.png", "Delete this section", func() -> void:
		sections.remove_at(index)
		send.call(), "FRedButton")
	LogicKit.push_right(head, trash)
	col.add_child(bar)
	var list: Array = sec.get("s") if sec.get("s") is Array else []
	sec["s"] = list
	var grid := Kit.slot_grid(Kit.COLUMNS)
	grid.name = "Signals"
	for i in ceili((list.size() + 1) / float(Kit.COLUMNS)) * Kit.COLUMNS:
		var k := i
		var entry: Array = list[i] if i < list.size() and list[i] is Array else []
		var s := Slot.new()
		s.theme_type_variation = "FSlotButton"
		if entry.size() >= 3:
			s.set_stack(str(entry[1]), int(entry[2]))
			s.set_tip(Kit.pretty(str(entry[1])), [["%d" % int(entry[2])], ["Click: the signal and its value · Right click: remove", "", Kit.DISABLED_TEXT]])
		else:
			s.set_tip("Add a signal", [["Click: choose a signal", "", Kit.DISABLED_TEXT]])
		s.clicked.connect(func(button_index: int, _shift: bool) -> void:
			if k < list.size():
				if button_index == MOUSE_BUTTON_RIGHT:
					list.remove_at(k)
					send.call()
				elif button_index == MOUSE_BUTTON_LEFT and screen.picker != null:
					# Factorio's "Set request" popup: swap the signal, or set its value below.
					var swap := func(type_name: String, name: String) -> void:
						if name != "":
							list[k] = [type_name, name, int(list[k][2])]
							send.call()
					var set_value := func(v: int) -> void:
						list[k][2] = v
						send.call()
					screen.picker.choose_with_value(SIGNAL_KINDS, swap, int(list[k][2]), set_value)
			elif button_index == MOUSE_BUTTON_LEFT and screen.picker != null:
				screen.picker.choose(SIGNAL_KINDS, func(type_name: String, name: String) -> void:
					if name != "":
						list.append([type_name, name, 1])
						send.call()))
		grid.add_child(s)
	col.add_child(grid)
	return col


## gui.cb for every combinator kind, without the window's strip and signals.
static func combinator(screen, cb: Dictionary) -> Control:
	match combinator_kind(screen, cb):
		"constant":
			return constant(screen, cb)
		"decider":
			return decider(screen, cb)
		"selector":
			return selector(screen, cb)
	return arithmetic(screen, cb)


## gui.sig: the networks' signals in one strip (each on its wire's colour) under the network ids.
static func signals(sig: Dictionary) -> Control:
	var box := EntityPanels.column(4)
	box.add_child(network_line({"r": int(sig.get("ri", 0)), "g": int(sig.get("gi", 0))}))
	var list := _tagged(sig)
	if sig.get("out") is Dictionary:
		list += _tagged(sig["out"])
	box.add_child(LogicKit.signal_strip(list, Kit.COLUMNS, 1, "Signals"))
	return box
