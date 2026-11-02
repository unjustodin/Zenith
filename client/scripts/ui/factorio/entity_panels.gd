extends RefCounted
## Widgets the entity windows share (checkboxes, radio buttons, number boxes, signal and filter
## slots that open Factorio's chooser, the circuit condition editor, the train camera), and the
## logistic chests' requests and filter with their network. The windows themselves are in
## logic_windows.gd, train_window.gd, circuit_panel.gd, entity_settings.gd and space_panels.gd.
## Each builder takes the screen (its `unit`, `model`, `picker`, `held_item`, `_last`...).
##
## Changes are sent at once (the mod's next `gui` shows them), as Factorio applies GUI edits
## immediately. Logistics (`gui.lg`) are described in docs/PROTOCOL.md.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")

const ARITHMETIC_OPS := ["*", "/", "+", "-", "%", "^", "<<", ">>", "AND", "OR", "XOR"]
const COMPARATORS := [">", "<", "=", "≥", "≤", "≠"]
## Factorio's train wait conditions (WaitConditionType), in the order its menu lists them.
const WAIT_TYPES := [["time", "Time passed"], ["inactivity", "Inactivity"], ["full", "Full cargo"], ["empty", "Empty cargo"],
	["not_empty", "Has cargo"], ["item_count", "Item count"], ["fluid_count", "Fluid count"], ["circuit", "Circuit condition"],
	["passenger_present", "Passenger present"], ["passenger_not_present", "Passenger not present"],
	["fuel_item_count_all", "Fuel count (all locomotives)"], ["fuel_item_count_any", "Fuel count (any locomotive)"],
	["fuel_full", "Fuel full"], ["destination_full_or_no_path", "Destination full or no path"],
	["specific_destination_full", "Specific destination full"], ["specific_destination_not_full", "Specific destination not full"],
	["at_station", "At station"], ["not_at_station", "Not at station"], ["damage_taken", "Damage taken"]]
## Wait conditions with a circuit condition, and those naming a station.
const CONDITION_WAITS := ["item_count", "fluid_count", "circuit", "fuel_item_count_all", "fuel_item_count_any"]
const STATION_WAITS := ["specific_destination_full", "specific_destination_not_full", "at_station", "not_at_station"]
## Slot grids inside a pane: one fewer than the inventory's 10, so the pane's margins keep the
## screen as wide as the inventory beside it.
const PANE_COLUMNS := 9

static var _theme: Theme = null


## MenuKit's theme (checkboxes, text fields, sliders, dropdowns) with Factorio's radio buttons.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.merge_with(MenuKit.theme())
	t.set_icon("radio_unchecked", "CheckBox", MenuKit._atlas_icon([[0, 160, 24, 24]], Color8(200, 200, 200)))
	t.set_icon("radio_checked", "CheckBox", MenuKit._atlas_icon([[0, 160, 24, 24], [72, 160, 24, 24]], Color8(255, 175, 0)))
	_theme = t
	return t


# --- small widgets -------------------------------------------------------------------------------

static func heading(text: String) -> Label:
	return Kit.label(text, "FHeading")


static func row(gap := 8) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", Kit.px(gap))
	return r


static func column(gap := 6) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", Kit.px(gap))
	return c


## A light pane (inside_shallow_frame) around a column, as Factorio groups settings.
static func pane(content: Control) -> Control:
	var shallow := Kit.panel("FShallowFrame")
	var m := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, Kit.px(12 if side == "left" or side == "right" else 8))
	shallow.add_child(m)
	m.add_child(content)
	return shallow


static func button(text: String, on_press: Callable, width := 0) -> Button:
	var b := MenuKit.button(text)
	if width > 0:
		b.custom_minimum_size.x = Kit.px(width)
	b.pressed.connect(on_press)
	return b


static func checkbox(text: String, on: bool, on_toggle: Callable) -> CheckBox:
	var c := MenuKit.checkbox(text, on)
	c.toggled.connect(on_toggle)
	return c


## Radio buttons in a row; on_pick(value) gets the chosen one's value.
static func radios(options: Array, current: String, on_pick: Callable) -> HBoxContainer:
	var r := row(12)
	var group := ButtonGroup.new()
	for o in options:
		var c := CheckBox.new()
		c.text = str(o[1])
		c.button_group = group
		c.focus_mode = Control.FOCUS_NONE
		c.button_pressed = str(o[0]) == current
		var value := str(o[0])
		var pick := func(on: bool) -> void:
			if on and value != current:
				on_pick.call(value)
		c.toggled.connect(pick)
		r.add_child(c)
	return r


static func number_box(value: int, on_set: Callable, width := 80) -> LineEdit:
	var e := MenuKit.textbox(str(value))
	e.custom_minimum_size.x = Kit.px(width)
	var commit := func(text: String) -> void:
		if text.strip_edges().is_valid_int():
			on_set.call(int(text.strip_edges()))
	e.text_submitted.connect(commit)
	var on_exit := func() -> void: commit.call(e.text)
	e.focus_exited.connect(on_exit)
	return e


## The dark number field of Factorio's conditions and wait conditions (a comparison's constant):
## white text, centred, as tall as a slot.
static func dark_number_box(value: int, on_set: Callable, width := 56) -> LineEdit:
	var e := number_box(value, on_set, width)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.custom_minimum_size.y = Kit.px(36)
	e.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color8(28, 27, 28)
	normal.set_border_width_all(Kit.px(1))
	normal.border_color = Color8(12, 12, 12)
	normal.set_corner_radius_all(Kit.px(3))
	normal.set_content_margin_all(Kit.px(4))
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color8(255, 175, 0)
	e.add_theme_stylebox_override("normal", normal)
	e.add_theme_stylebox_override("focus", focus)
	e.add_theme_stylebox_override("read_only", normal)
	e.add_theme_color_override("font_color", Kit.WHITE)
	e.add_theme_color_override("caret_color", Kit.WHITE)
	e.add_theme_font_size_override("font_size", Kit.px(16))
	return e


## A filter / signal slot: shows `name`; click: the held item, or Factorio's chooser (kinds:
## "item", "fluid", "virtual"); right click clears. on_set(type, name) gets the change ("" clears).
static func choose_slot(screen, name: String, kinds: Array, on_set: Callable, tip := "") -> Slot:
	var s := Slot.new()
	s.theme_type_variation = "FSlotButton"
	s.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	s.set_stack(name, -1)
	s.set_tip(Kit.pretty(name) if name != "" else (tip if tip != "" else "Not set"),
		[["Click: choose · Right click: clear", "", Kit.DISABLED_TEXT]])
	var on_click := func(button_index: int, _shift: bool) -> void:
		if button_index == MOUSE_BUTTON_RIGHT:
			on_set.call("item", "")
		elif button_index == MOUSE_BUTTON_LEFT:
			var held: String = screen.held_item.call() if screen.held_item.is_valid() else ""
			if held != "" and kinds.has("item"):
				on_set.call("item", held)
			elif screen.picker != null:
				screen.picker.choose(kinds, on_set)
	s.clicked.connect(on_click)
	return s


static func _signal_name(sig) -> String:
	if sig is Dictionary:
		var n = sig.get("name", "")
		return str(n.get("name", "")) if n is Dictionary else str(n)
	return ""


static func _signal_type(sig) -> String:
	return str(sig.get("type", "item")) if sig is Dictionary else "item"


# --- conditions and trains -----------------------------------------------------------------------

## A circuit condition {first_signal, comparator, constant | second_signal} as Factorio edits it:
## signal, comparator, then a constant or a second signal. on_change(condition) gets the new one.
static func _condition_editor(screen, cond: Dictionary, kinds: Array, on_change: Callable) -> Control:
	var r := row(4)
	var set_field := func(key: String, value) -> void:
		var c := cond.duplicate(true)
		if value == null:
			c.erase(key)
		else:
			c[key] = value
		on_change.call(c)
	var set_first := func(type_name: String, name: String) -> void:
		set_field.call("first_signal", {"type": type_name, "name": name} if name != "" else null)
	r.add_child(choose_slot(screen, _signal_name(cond.get("first_signal")), kinds, set_first, "Signal"))
	var cmp := MenuKit.dropdown(COMPARATORS.map(func(o): return [o, o]), str(cond.get("comparator", "<")))
	cmp.custom_minimum_size.x = Kit.px(56)
	cmp.item_selected.connect(func(i: int) -> void: set_field.call("comparator", COMPARATORS[i]))
	r.add_child(cmp)
	var second := _signal_name(cond.get("second_signal"))
	var set_second := func(type_name: String, name: String) -> void:
		var c := cond.duplicate(true)
		if name == "":
			c.erase("second_signal")
		else:
			c["second_signal"] = {"type": type_name, "name": name}
			c.erase("constant")
		on_change.call(c)
	r.add_child(choose_slot(screen, second, ["item", "fluid", "virtual"], set_second, "Second signal (or a constant)"))
	if second == "":
		r.add_child(dark_number_box(int(cond.get("constant", 0)), func(v: int) -> void: set_field.call("constant", v), 56))
	return r


## A wait condition of that type with Factorio's defaults.
static func _new_wait(t: String, compare := "and") -> Dictionary:
	var w := {"type": t, "compare_type": compare}
	if t == "time":
		w["ticks"] = 30 * 60
	elif t == "inactivity":
		w["ticks"] = 5 * 60
	elif t in CONDITION_WAITS:
		w["condition"] = {"comparator": "<", "constant": 0}
	elif t == "damage_taken":
		w["damage"] = 1000
	return w


## The locomotive's camera, as Factorio's train window has: the 3D world seen from above the front
## of the train. A second camera in the game's own world, so it shows what the client has loaded
## around there; machine_screen.gd moves it with the train (meta "train_camera").
static func _train_camera(screen, tr: Dictionary) -> Control:
	var frame := Kit.panel("FDeepFrame")
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(Kit.px(260), Kit.px(190))
	var vp := SubViewport.new()
	vp.size = Vector2i(Kit.px(260), Kit.px(190))
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	var main: Viewport = screen.get_viewport()
	if main != null:
		vp.world_3d = main.world_3d
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.current = true
	vp.add_child(cam)
	holder.add_child(vp)
	frame.add_child(holder)
	screen.set_meta("train_camera", cam)
	var pos = tr.get("pos")
	if pos is Array and pos.size() >= 2:
		aim_train_camera(cam, Vector2(int(pos[0]), int(pos[1])) / 256.0)
	return frame


## Puts the train camera above a map position (tiles), looking down from the south like the game.
static func aim_train_camera(cam: Camera3D, at: Vector2) -> void:
	var eye := Vector3(at.x, 22.0, at.y + 16.0)
	cam.transform = Transform3D(Basis.looking_at(Vector3(at.x, 0.0, at.y) - eye, Vector3.UP), eye)


# --- logistics (claude/cloud-logistics shapes) ----------------------------------------------------

## gui.lg: {mode, requests?: [[item, min, max, quality?]], filter?, net?: {id, log, con, items}}.
static func logistics(screen, lg: Dictionary) -> Control:
	var box := column(8)
	var mode := str(lg.get("mode", ""))
	if lg.get("requests") is Array or mode in ["requester", "buffer"]:
		box.add_child(heading("Logistic requests"))
		var list: Array = (lg.get("requests") as Array).duplicate(true) if lg.get("requests") is Array else []
		var set_requests := func(l: Array) -> void: Bridge.send({"t": "set_requests", "u": screen.unit, "l": l})
		box.add_child(request_grid(screen, list, set_requests))
	if lg.has("filter") or mode == "storage":
		var f := row(8)
		f.add_child(Kit.label("Filter"))
		var set_filter := func(_t: String, item: String) -> void: Bridge.send({"t": "set_storage_filter", "u": screen.unit, "item": item})
		f.add_child(choose_slot(screen, str(lg.get("filter", "")), ["item"], set_filter, "Anything"))
		box.add_child(f)
	var net = lg.get("net")
	if net is Dictionary:
		box.add_child(network_info(net))
	elif mode != "":
		var none := Kit.label("Not in a logistic network")
		none.add_theme_color_override("font_color", Kit.RED_TEXT)
		box.add_child(none)
	return pane(box)


## Request slots: the item with its minimum as the count; click an empty one to add (the held item
## or the chooser), click a used one to edit min / max below, right click to remove. on_change(l)
## gets the wire list [[item, min, max (-1 none)], ...].
static func request_grid(screen, list: Array, on_change: Callable, columns := PANE_COLUMNS) -> Control:
	var box := column(4)
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var grid := Kit.slot_grid(columns)
	frame.add_child(grid)
	var edit := row(8)
	var min_box := MenuKit.textbox("", "Min")
	var max_box := MenuKit.textbox("", "Max (empty: none)")
	min_box.custom_minimum_size.x = Kit.px(80)
	max_box.custom_minimum_size.x = Kit.px(120)
	edit.visible = false
	var selected := [-1]
	var commit := func(_t := "") -> void:
		var i: int = selected[0]
		if i < 0 or i >= list.size():
			return
		if min_box.text.strip_edges().is_valid_int():
			list[i][1] = maxi(0, int(min_box.text.strip_edges()))
		list[i][2] = int(max_box.text.strip_edges()) if max_box.text.strip_edges().is_valid_int() else -1
		on_change.call(list)
	min_box.text_submitted.connect(commit)
	max_box.text_submitted.connect(commit)
	var cells := ceili((list.size() + 1) / float(columns)) * columns
	for i in cells:
		var index := i
		var s := Slot.new()
		s.theme_type_variation = "FSlotButton"
		if i < list.size() and list[i] is Array and list[i].size() >= 3:
			var r: Array = list[i]
			s.set_stack(str(r[0]), int(r[1]))
			s.set_tip(Kit.pretty(str(r[0])), [["Min %d · Max %s" % [int(r[1]), "none" if int(r[2]) < 0 else str(int(r[2]))]],
				["Click: change · Right click: remove", "", Kit.DISABLED_TEXT]])
		else:
			s.set_tip("Add a request", [["Click: choose an item (or the one held)", "", Kit.DISABLED_TEXT]])
		var on_click := func(button_index: int, _shift: bool) -> void:
			if index < list.size():
				if button_index == MOUSE_BUTTON_RIGHT:
					list.remove_at(index)
					on_change.call(list)
				elif button_index == MOUSE_BUTTON_LEFT:
					selected[0] = index
					edit.visible = true
					min_box.text = str(int(list[index][1]))
					max_box.text = "" if int(list[index][2]) < 0 else str(int(list[index][2]))
					min_box.grab_focus()
			elif button_index == MOUSE_BUTTON_LEFT:
				var add := func(_type: String, item: String) -> void:
					if item != "":
						list.append([item, 50, -1])
						on_change.call(list)
				var held: String = screen.held_item.call() if screen.held_item.is_valid() else ""
				if held != "":
					add.call("item", held)
				elif screen.picker != null:
					screen.picker.choose(["item"], add)
		s.clicked.connect(on_click)
		grid.add_child(s)
	box.add_child(frame)
	edit.add_child(Kit.label("Min"))
	edit.add_child(min_box)
	edit.add_child(Kit.label("Max"))
	edit.add_child(max_box)
	edit.add_child(button("Set", func() -> void: commit.call(), 60))
	box.add_child(edit)
	return box


## A logistic network: robots available / all, and what its storage holds (net.items).
static func network_info(net: Dictionary) -> Control:
	var box := column(4)
	var log_r: Array = net.get("log", [0, 0]) if net.get("log") is Array else [0, 0]
	var con_r: Array = net.get("con", [0, 0]) if net.get("con") is Array else [0, 0]
	box.add_child(heading("Logistic network %d" % int(net.get("id", 0))))
	if log_r.size() >= 2 and con_r.size() >= 2:
		box.add_child(Kit.label("Logistic robots: %d / %d available · Construction robots: %d / %d available" % [
			int(log_r[0]), int(log_r[1]), int(con_r[0]), int(con_r[1])]))
	var items: Array = net.get("items", []) if net.get("items") is Array else []
	if not items.is_empty():
		var frame := Kit.panel("FDeepFrame")
		frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var grid := Kit.slot_grid(PANE_COLUMNS)
		frame.add_child(grid)
		for it in items.slice(0, 36):
			if it is Array and it.size() >= 2:
				var s := Slot.new()
				s.mouse_filter = Control.MOUSE_FILTER_PASS
				s.set_stack(str(it[0]), int(it[1]))
				s.set_tip(Kit.pretty(str(it[0])), [["%d in the network" % int(it[1])]])
				grid.add_child(s)
		box.add_child(frame)
	return box
