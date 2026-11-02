extends RefCounted
## Factorio 2.1's locomotive and train stop windows (tools/ui_reference: entity_locomotive,
## entity_train_stop), for logic_windows.gd.
##
## Locomotive: the train's name strip with its colour, the status, a camera on the train where
## Factorio has the entity preview, "Drive remotely", the Automatic/Manual switch, then the Schedule
## and Fuel tabs. The schedule is Factorio's list: each station a dark bar (go button, name,
## remove), its wait conditions beside an AND/OR column, "+ Add wait condition", "+ Add station",
## then "Interrupts (i)" and "+ Add interrupt". Ctrl+click on a station in "+ Add station"'s list
## sends the train there now as a temporary stop, as Ctrl+click on the map does in Factorio.
##
## Train stop: a wide window, the stop on the left (name strip with rename and colour, status,
## "Enable train limit" and "Priority (i)" with their notched sliders) and the tabs "Trains on the
## way (n)" / "Trains with this stop (n)" on the right, a card per train or Factorio's red banner.

const TrainView := preload("res://scripts/ui/factorio/train_view.gd")
const Kit := preload("res://scripts/ui/factorio/kit.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const LogicKit := preload("res://scripts/ui/factorio/logic_kit.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")

## The tab last shown in a locomotive's and a train stop's window.
static var loco_tab := "schedule"
static var stop_tab := "on_the_way"

const GUTTER := 100  # the AND/OR column left of the wait conditions
## The "[2]" after a train group's name.
const GROUP_COUNT := Color8(128, 206, 240)
const STATE_TEXT := {
	"on_the_path": "On the way", "path_lost": "Path lost", "no_schedule": "No schedule", "no_path": "No path",
	"arrive_signal": "Arriving at signal", "wait_signal": "Waiting at signal", "arrive_station": "Arriving at station",
	"wait_station": "Waiting at station", "manual_control_stop": "Manual control", "manual_control": "Manual control",
	"destination_full": "Destination full",
}


static func state_text(s: String) -> String:
	return STATE_TEXT.get(s, s.replace("_", " ").capitalize())


# --- locomotive ----------------------------------------------------------------------------------

static func locomotive(screen, last: Dictionary, body: VBoxContainer) -> void:
	var tr: Dictionary = last.get("tr") if last.get("tr") is Dictionary else {}
	var sched: Dictionary = tr.get("sched") if tr.get("sched") is Dictionary else {}
	var group := str(sched.get("group", ""))
	var sh := LogicKit.subheader()
	var head: HBoxContainer = sh[1]
	var name := group if group != "" else str(tr.get("name", ""))
	if name == "":
		name = Kit.entity_name(str(screen.proto_name))
	var title := RichText.text_label(name, "FHeading", Kit.WHITE)
	title.name = "TrainName"
	head.add_child(title)
	if group != "" and tr.has("gc"):
		# "[2]": how many trains the group has, in Factorio's blue.
		var count := Kit.label("[%d]" % int(tr["gc"]), "FHeading")
		count.name = "GroupCount"
		count.add_theme_color_override("font_color", GROUP_COUNT)
		count.tooltip_text = "Number of trains in this train group."
		count.mouse_filter = Control.MOUSE_FILTER_STOP
		head.add_child(count)
	var pencil := LogicKit.rename_button("Change train group", func() -> void: group_dialog(screen, tr))
	pencil.name = "ChangeGroup"
	head.add_child(pencil)
	if last.get("col") is Array:
		LogicKit.push_right(head, LogicKit.color_buttons(screen, last["col"]))
	var strip := LogicKit.bleed(sh[0])
	body.add_child(strip)
	body.move_child(strip, 0)
	body.add_child(camera(screen, tr, 396, 150))
	var drive := MenuKit.button("Drive remotely", "FGreenButton")
	drive.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drive.disabled = true
	drive.tooltip_text = "Not in the 3D client: get in the locomotive to drive it"
	body.add_child(drive)
	var manual := bool(tr.get("manual", false))
	var sw := LogicKit.switch("Automatic", "Manual", "right" if manual else "left",
		func(s: String) -> void: screen.model.set_train_automatic(screen.unit, s == "left"))
	sw.name = "TrainMode"
	body.add_child(sw)
	body.add_child(LogicKit.line())
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", Kit.px(2))
	for t in [["schedule", "Schedule"], ["fuel", "Fuel"]]:
		var key: String = t[0]
		tabs.add_child(_tab(str(t[1]), loco_tab == key, func() -> void:
			loco_tab = key
			screen._rebuild_now()))
	body.add_child(tabs)
	if loco_tab == "fuel":
		body.add_child(LogicKit.fuel_row(screen))
	else:
		body.add_child(schedule(screen, tr))


static func _tab(text: String, on: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.name = "Tab" + text.replace(" ", "")
	b.theme_type_variation = "FTab"
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Kit.pxv(84, 32)
	b.add_theme_font_override("font", Kit.font("bold"))
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Kit.WHITE)
	b.pressed.connect(on_press)
	return b


## The camera on the train, where Factorio has the entity preview: the 3D world seen from above
## its front; machine_screen.gd keeps it over the train (meta "train_camera"). A click on it follows
## the train in remote view, as Factorio's train window does.
static func camera(screen, tr: Dictionary, w: int, h: int) -> Control:
	var frame: Control = EntityPanels._train_camera(screen, tr)
	var holder: SubViewportContainer = frame.get_child(0)
	holder.custom_minimum_size = Kit.pxv(w, h)  # the viewport follows (stretch)
	holder.name = "TrainCamera"
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.tooltip_text = "Click: follow the train in remote view"
	holder.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			follow_train(screen, screen._last.get("tr") if screen._last.get("tr") is Dictionary else tr))
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return frame


## Remote view on the train, following the opened carriage (factorio_ui.gd's remote_follow).
static func follow_train(screen, tr: Dictionary) -> void:
	var pos = tr.get("pos")
	if not screen.remote_follow.is_valid() or not (pos is Array and (pos as Array).size() >= 2):
		return
	screen.remote_follow.call(screen.unit, Vector2(int(pos[0]), int(pos[1])) / 256.0)


## Factorio's "Change train group" popup under the name strip: the group's name in a text box,
## the force's groups to pick from with their train counts, and the green tick. Enter or the tick
## moves this train into that group (a new name makes one, an empty one leaves its group); with
## Ctrl held the whole group is renamed instead, as Factorio's "Apply change" says.
static func group_dialog(screen, tr: Dictionary) -> void:
	var old: Node = screen.get_node_or_null("TrainGroupDialog")
	if old != null:
		old.queue_free()
		return
	var sched: Dictionary = tr.get("sched") if tr.get("sched") is Dictionary else {}
	var current := str(sched.get("group", ""))
	var pop := PanelContainer.new()
	pop.name = "TrainGroupDialog"
	pop.theme_type_variation = "FFrame"
	pop.top_level = true
	pop.z_index = 10
	var box := EntityPanels.column(6)
	pop.add_child(LogicKit.padded(box, 8, 6))
	var head := EntityPanels.row(8)
	head.add_child(Kit.label("Change train group", "FHeading"))
	var close := Kit.close_button()
	close.pressed.connect(func() -> void: pop.queue_free())
	LogicKit.push_right(head, close)
	box.add_child(head)
	var row := EntityPanels.row(6)
	var field := MenuKit.textbox(current, "[No group assigned]")
	field.name = "GroupField"
	field.custom_minimum_size.x = Kit.px(260)
	row.add_child(field)
	var apply := func() -> void:
		var all := Input.is_key_pressed(KEY_CTRL) and current != ""
		Bridge.send({"t": "set_train_group", "u": screen.unit, "g": field.text.strip_edges(), "all": 1 if all else 0})
		pop.queue_free()
	field.text_submitted.connect(func(_t: String) -> void: apply.call())
	var ok := Button.new()
	ok.name = "ApplyGroup"
	ok.theme_type_variation = "FGreenButton"
	ok.custom_minimum_size = Kit.pxv(28, 28)
	ok.focus_mode = Control.FOCUS_NONE
	ok.tooltip_text = "Apply change\nHold Control while submitting to rename the entire group."
	var tick := GuiAssets.core_sprite("icons/mip/confirm.png")
	if tick != null:
		ok.icon = tick
		ok.expand_icon = true
		ok.add_theme_constant_override("icon_max_width", Kit.px(20))
	else:
		ok.text = "✔"
	ok.pressed.connect(apply)
	row.add_child(ok)
	box.add_child(row)
	# The force's groups, "[No group assigned]" first, each with its train count; the train's own
	# group is orange. A click puts its name in the box.
	var groups: Array = tr.get("groups") if tr.get("groups") is Array else []
	var frame := Kit.panel("FDeepFrame")
	var list := EntityPanels.column(0)
	list.name = "Groups"
	frame.add_child(list)
	var rows := 0
	for g in groups:
		if not (g is Array) or (g as Array).size() < 2:
			continue
		var gname := str(g[0])
		var b := Button.new()
		b.name = "Group_" + (gname if gname != "" else "none")
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = gname == current
		b.custom_minimum_size = Kit.pxv(280, 28)
		var line := EntityPanels.row(6)
		line.set_anchors_preset(Control.PRESET_FULL_RECT)
		line.offset_left = Kit.px(8)
		line.offset_right = -Kit.px(8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ink := Kit.BLACK if gname == current else Kit.WHITE
		var nl: Control = RichText.text_label(gname, "", ink) if gname != "" else Kit.label("[No group assigned]")
		nl.set("vertical_alignment", VERTICAL_ALIGNMENT_CENTER)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cl := Kit.label(str(int(g[1])))
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		for l in [nl, cl]:
			l.add_theme_color_override("font_color", ink)
		line.add_child(nl)
		LogicKit.push_right(line, cl)
		b.add_child(line)
		var bg := StyleBoxFlat.new()
		bg.bg_color = LogicKit.ACTIVE if gname == current else Color8(36, 35, 36)
		var hover := bg.duplicate() as StyleBoxFlat
		hover.bg_color = LogicKit.ACTIVE.lightened(0.15) if gname == current else Color8(60, 59, 60)
		for state in ["normal", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, bg)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("hover_pressed", hover)
		b.pressed.connect(func() -> void:
			field.text = gname
			field.grab_focus())
		list.add_child(b)
		rows += 1
	while rows < 4:  # Factorio's list keeps a few empty rows
		var empty := Control.new()
		empty.custom_minimum_size = Kit.pxv(280, 28)
		list.add_child(empty)
		rows += 1
	box.add_child(frame)
	screen.add_child(pop)
	var at: Vector2 = screen.get_global_rect().position + Vector2(Kit.px(12), Kit.px(84))
	pop.position = at
	field.grab_focus()
	field.select_all()


## The Schedule tab: whether the train is in a group, the stations with their wait conditions,
## "+ Add station", the interrupts and "+ Add interrupt".
static func schedule(screen, tr: Dictionary) -> Control:
	var box := EntityPanels.column(6)
	box.name = "Schedule"
	var sched: Dictionary = tr.get("sched") if tr.get("sched") is Dictionary else {}
	var in_group := str(sched.get("group", "")) != ""
	box.add_child(LogicKit.info_label("Train is in a group" if in_group else "Train is not in a group",
		"Trains in a group share their schedule and interrupts", "FHeading"))
	var stops: Array = tr.get("stops", []) if tr.get("stops") is Array else []
	if stops.is_empty() and screen.stop_names.is_valid():
		stops = screen.stop_names.call()
	var records: Array = (sched.get("records") as Array).duplicate(true) if sched.get("records") is Array else []
	var send := func(l: Array) -> void: screen.model.set_schedule(screen.unit, l)
	var frame := Kit.panel("FDeepFrame")
	var list := EntityPanels.column(4)
	frame.add_child(LogicKit.padded(list, 4, 4))
	_records(screen, list, records, int(sched.get("current", 0)), stops, true, send)
	list.add_child(_add_station(screen, records, stops, send, true))
	var ih := LogicKit.subheader()
	(ih[1] as HBoxContainer).add_child(LogicKit.info_label("Interrupts", "Interrupts send the train somewhere else when their conditions hold", "FHeading"))
	list.add_child(ih[0])
	var interrupts: Array = sched.get("interrupts", []) if sched.get("interrupts") is Array else []
	_interrupts(screen, list, interrupts, stops)
	box.add_child(frame)
	return box


## Each record: the station's dark bar, then its wait conditions and "+ Add wait condition".
static func _records(screen, list: VBoxContainer, records: Array, current: int, stops: Array, can_go: bool, on_change: Callable) -> void:
	for i in records.size():
		var index := i
		var rec: Dictionary = records[i] if records[i] is Dictionary else {}
		var bar := Kit.panel("FSubheader")
		bar.custom_minimum_size.y = Kit.px(32)
		var r := EntityPanels.row(8)
		bar.add_child(r)
		if can_go:
			var go := Button.new()
			go.name = "Go%d" % (i + 1)
			go.custom_minimum_size = Kit.pxv(28, 28)
			go.focus_mode = Control.FOCUS_NONE
			go.toggle_mode = true
			go.button_pressed = i + 1 == current
			go.tooltip_text = "The train is going here" if i + 1 == current else "Go to this station now"
			var icon := GuiAssets.core_sprite("icons/mip/stop.png" if i + 1 == current else "icons/mip/play.png")
			if icon != null:
				go.icon = icon
				go.expand_icon = true
				go.add_theme_constant_override("icon_max_width", Kit.px(16))
			else:
				go.text = "■" if i + 1 == current else "▶"
			go.pressed.connect(func() -> void: screen.model.train_go(screen.unit, index + 1))
			r.add_child(go)
		var title := str(rec.get("station", "")) if rec.has("station") else "Rail %s" % str(rec.get("rail", ""))
		if bool(rec.get("temporary", false)):
			title += " (temporary)"
		var name := RichText.text_label(title)
		name.name = "Station%d" % (i + 1)
		name.set("vertical_alignment", VERTICAL_ALIGNMENT_CENTER)
		r.add_child(name)
		var remove := Kit.close_button()
		remove.name = "Remove%d" % (i + 1)
		remove.tooltip_text = "Remove this station"
		remove.pressed.connect(func() -> void:
			var l := records.duplicate(true)
			l.remove_at(index)
			on_change.call(l))
		LogicKit.push_right(r, remove)
		list.add_child(bar)
		var waits: Array = rec.get("wait_conditions", []) if rec.get("wait_conditions") is Array else []
		var set_waits := func(w: Array) -> void:
			var l := records.duplicate(true)
			l[index]["wait_conditions"] = w
			on_change.call(l)
		_waits(screen, list, waits, stops, set_waits)


## Wait conditions: an AND/OR button in the left column before each one after the first, the
## condition in its grey frame, and "+ Add wait condition".
static func _waits(screen, list: VBoxContainer, waits: Array, stops: Array, on_change: Callable) -> void:
	for i in waits.size():
		var index := i
		var w: Dictionary = waits[i] if waits[i] is Dictionary else {}
		var r := EntityPanels.row(4)
		var gutter := CenterContainer.new()
		gutter.custom_minimum_size.x = Kit.px(GUTTER)
		if i > 0:
			var and_or := MenuKit.button(str(w.get("compare_type", "and")).to_upper())
			and_or.custom_minimum_size = Kit.pxv(60, 28)
			and_or.name = "AndOr%d" % (i + 1)
			and_or.tooltip_text = "AND: both must hold · OR: either"
			and_or.pressed.connect(func() -> void:
				var l := waits.duplicate(true)
				l[index]["compare_type"] = "or" if str(w.get("compare_type", "and")) == "and" else "and"
				on_change.call(l))
			gutter.add_child(and_or)
		r.add_child(gutter)
		var changed := func(c) -> void:
			var l := waits.duplicate(true)
			if c == null:
				l.remove_at(index)
			else:
				l[index] = c
			on_change.call(l)
		var frame := Kit.panel("FShallowFrame")
		frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame.add_child(LogicKit.padded(_condition(screen, w, stops, changed), 6, 2))
		r.add_child(frame)
		list.add_child(r)
	var add_row := EntityPanels.row(4)
	var gap := Control.new()
	gap.custom_minimum_size.x = Kit.px(GUTTER)
	add_row.add_child(gap)
	var add := _menu_button("+ Add wait condition", EntityPanels.WAIT_TYPES.map(func(p): return str(p[1])))
	add.name = "AddWait"
	var pick := func(k: int, _temporary: bool) -> void:
		var l := waits.duplicate(true)
		l.append(EntityPanels._new_wait(str(EntityPanels.WAIT_TYPES[k][0]), "and"))
		on_change.call(l)
	_on_pick(add, pick)
	add_row.add_child(add)
	list.add_child(add_row)


## One wait condition: its type, what it needs, and remove. on_change(condition, or null).
static func _condition(screen, w: Dictionary, stops: Array, on_change: Callable) -> Control:
	var r := EntityPanels.row(4)
	var t := str(w.get("type", "time"))
	var types := EntityPanels.WAIT_TYPES.map(func(p): return [p[1], p[0]])
	if not EntityPanels.WAIT_TYPES.any(func(p): return p[0] == t):
		types.append([t.replace("_", " ").capitalize(), t])
	var kind := MenuKit.dropdown(types, t)
	kind.custom_minimum_size.x = Kit.px(150)
	var compare := str(w.get("compare_type", "and"))
	kind.item_selected.connect(func(i: int) -> void: on_change.call(EntityPanels._new_wait(str(types[i][1]), compare)))
	r.add_child(kind)
	var set_field := func(key: String, value) -> void:
		var c := w.duplicate(true)
		c[key] = value
		on_change.call(c)
	if t == "time" or t == "inactivity":
		r.add_child(EntityPanels.dark_number_box(int(w.get("ticks", 0)) / 60, func(v: int) -> void: set_field.call("ticks", maxi(0, v) * 60), 56))
		r.add_child(Kit.label("s"))
	elif t in EntityPanels.CONDITION_WAITS:
		var cond: Dictionary = (w.get("condition") as Dictionary).duplicate(true) if w.get("condition") is Dictionary else {"comparator": "<", "constant": 0}
		var kinds: Array = ["fluid"] if t == "fluid_count" else (["item", "fluid", "virtual"] if t == "circuit" else ["item"])
		r.add_child(EntityPanels._condition_editor(screen, cond, kinds, func(c: Dictionary) -> void: set_field.call("condition", c)))
	elif t in EntityPanels.STATION_WAITS:
		var names: Array = stops.duplicate()
		var current := str(w.get("station", ""))
		if current != "" and not names.has(current):
			names.push_front(current)
		var pick := MenuKit.dropdown(names.map(func(n): return [n, n]), current)
		pick.custom_minimum_size.x = Kit.px(140)
		RichText.decorate_items(pick, names)
		pick.item_selected.connect(func(i: int) -> void: set_field.call("station", str(names[i])))
		r.add_child(pick)
	elif t == "damage_taken":
		r.add_child(EntityPanels.dark_number_box(int(w.get("damage", 0)), func(v: int) -> void: set_field.call("damage", maxi(0, v)), 70))
	var remove := Kit.close_button()
	remove.tooltip_text = "Remove this condition"
	remove.pressed.connect(func() -> void: on_change.call(null))
	LogicKit.push_right(r, remove)
	return r


## A wide grey button opening a list (Factorio's "+ Add station" and "+ Add wait condition").
static func _menu_button(text: String, items: Array) -> MenuButton:
	var b := MenuButton.new()
	b.text = text
	b.flat = false
	b.theme_type_variation = "Button"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = Kit.px(28)
	b.focus_mode = Control.FOCUS_NONE
	var p := b.get_popup()
	for i in items.size():
		p.add_item(str(items[i]), i)
	return b


## What picking item k does (pick(k, ctrl held)); kept as the button's "pick" meta for tests.
static func _on_pick(b: MenuButton, pick: Callable) -> void:
	b.set_meta("pick", pick)
	b.get_popup().id_pressed.connect(func(id: int) -> void: pick.call(id, Input.is_key_pressed(KEY_CTRL)))


static func _add_station(screen, records: Array, stops: Array, on_change: Callable, can_go: bool) -> Control:
	var add := _menu_button("+ Add station", stops)
	add.name = "AddStation"
	RichText.decorate_items(add.get_popup(), stops)
	add.tooltip_text = "Control + Left-click: insert a temporary stop" if can_go else ""
	add.disabled = stops.is_empty()
	var pick := func(k: int, temporary: bool) -> void:
		if k < 0 or k >= stops.size():
			return
		if temporary and can_go:
			screen.model.train_go_to_station(screen.unit, str(stops[k]))
			return
		var l := records.duplicate(true)
		l.append({"station": str(stops[k]), "wait_conditions": [{"type": "time", "compare_type": "or", "ticks": 30 * 60}]})
		on_change.call(l)
	_on_pick(add, pick)
	return add


## The interrupts: each one's bar (name, whether it may interrupt another interrupt, remove), its
## conditions and targets; then "+ Add interrupt", which asks for a name.
static func _interrupts(screen, list: VBoxContainer, interrupts: Array, stops: Array) -> void:
	var send := func(l: Array) -> void: screen.model.set_interrupts(screen.unit, l)
	for i in interrupts.size():
		var index := i
		var it: Dictionary = interrupts[i] if interrupts[i] is Dictionary else {}
		var bar := Kit.panel("FSubheader")
		bar.custom_minimum_size.y = Kit.px(32)
		var r := EntityPanels.row(8)
		bar.add_child(r)
		var title := RichText.text_label(str(it.get("name", "")), "FHeading")
		title.set("vertical_alignment", VERTICAL_ALIGNMENT_CENTER)
		r.add_child(title)
		var inside := EntityPanels.checkbox("Interrupt other interrupts", bool(it.get("inside_interrupt", false)), func(on: bool) -> void:
			var l := interrupts.duplicate(true)
			l[index]["inside_interrupt"] = on
			send.call(l))
		LogicKit.push_right(r, inside)
		var remove := Kit.close_button()
		remove.tooltip_text = "Remove this interrupt"
		remove.pressed.connect(func() -> void:
			var l := interrupts.duplicate(true)
			l.remove_at(index)
			send.call(l))
		r.add_child(remove)
		list.add_child(bar)
		list.add_child(LogicKit.grey("Conditions"))
		var conds: Array = it.get("conditions", []) if it.get("conditions") is Array else []
		_waits(screen, list, conds, stops, func(w: Array) -> void:
			var l := interrupts.duplicate(true)
			l[index]["conditions"] = w
			send.call(l))
		list.add_child(LogicKit.grey("Targets"))
		var targets: Array = it.get("targets", []) if it.get("targets") is Array else []
		var set_targets := func(t: Array) -> void:
			var l := interrupts.duplicate(true)
			l[index]["targets"] = t
			send.call(l)
		_records(screen, list, targets, 0, stops, false, set_targets)
		list.add_child(_add_station(screen, targets, stops, set_targets, false))
	var field := MenuKit.textbox("", "Name")
	field.visible = false
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_submitted.connect(func(t: String) -> void:
		field.release_focus()
		if t.strip_edges() == "":
			return
		var l := interrupts.duplicate(true)
		l.append({"name": t.strip_edges(), "conditions": [], "targets": [], "inside_interrupt": false})
		send.call(l))
	var add := LogicKit.wide_button("+ Add interrupt", func() -> void:
		field.visible = true
		field.grab_focus())
	add.name = "AddInterrupt"
	list.add_child(add)
	list.add_child(field)


# --- train stop ----------------------------------------------------------------------------------

static func stop(screen, st: Dictionary, body: VBoxContainer) -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", Kit.px(12))
	var left := EntityPanels.column(8)
	left.custom_minimum_size.x = Kit.px(300)
	cols.add_child(left)
	# The name strip: the name with its rename button, then the map button and the colour.
	var sh := LogicKit.subheader()
	var head: HBoxContainer = sh[1]
	var title := RichText.text_label(str(st.get("name", "")), "FHeading", Kit.WHITE)
	title.name = "StopName"
	head.add_child(title)
	var field := MenuKit.textbox(str(st.get("name", "")))
	field.name = "StopNameField"
	field.visible = false
	field.custom_minimum_size.x = Kit.px(170)
	field.text_submitted.connect(func(t: String) -> void:
		field.release_focus()
		if t.strip_edges() != "":
			screen.model.set_stop(screen.unit, t.strip_edges()))
	head.add_child(field)
	var rename := LogicKit.rename_button("Rename", func() -> void:
		title.visible = false
		field.visible = true
		field.grab_focus()
		field.select_all())
	rename.name = "Rename"
	head.add_child(rename)
	var colors := LogicKit.color_buttons(screen, screen._last.get("col", [255, 255, 255]))
	LogicKit.push_right(head, colors)
	var strip := LogicKit.bleed(sh[0])
	strip.add_theme_constant_override("margin_right", 0)
	left.add_child(strip)
	# The status line and preview machine_screen.gd put first move into the left column.
	for c in body.get_children():
		body.remove_child(c)
		left.add_child(c)
	var limit := int(st.get("limit", -1))
	var lim_row := EntityPanels.row(8)
	var lim_slider := LogicKit.notched(0, maxi(10, limit), maxi(0, limit), limit >= 0,
		func(v: int) -> void: screen.model.set_stop(screen.unit, "", maxi(0, v)))
	lim_slider.name = "TrainLimit"
	lim_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var limited := EntityPanels.checkbox("Enable train limit", limit >= 0, func(on: bool) -> void:
		screen.model.set_stop(screen.unit, "", maxi(1, lim_slider.value) if on else -1))
	limited.custom_minimum_size.x = Kit.px(130)
	lim_row.add_child(limited)
	lim_row.add_child(lim_slider)
	left.add_child(lim_row)
	var pri_row := EntityPanels.row(8)
	var pri_label := LogicKit.info_label("Priority", "Trains go to the stop with the highest priority first (0-255)")
	pri_label.custom_minimum_size.x = Kit.px(130)
	pri_row.add_child(pri_label)
	var pri := LogicKit.notched(0, 255, int(st.get("pri", 50)), true,
		func(v: int) -> void: screen.model.set_stop_settings(screen.unit, {"pri": clampi(v, 0, 255)}))
	pri.name = "Priority"
	pri.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pri_row.add_child(pri)
	left.add_child(pri_row)
	cols.add_child(_stop_trains(screen, st))
	body.add_child(cols)


## The right side: the two tabs and a card per train, or Factorio's red banner.
static func _stop_trains(screen, st: Dictionary) -> Control:
	var right := EntityPanels.column(0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var trs: Array = st.get("trs") if st.get("trs") is Array else []
	var coming := trs.filter(func(t): return t is Array and t.size() >= 4 and int(t[2]) == 1)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", Kit.px(2))
	for t in [["on_the_way", "Trains on the way", coming.size()], ["with_stop", "Trains with this stop", trs.size()]]:
		var key: String = t[0]
		var b := _tab("%s (%d)" % [t[1], t[2]], stop_tab == key, func() -> void:
			stop_tab = key
			screen._rebuild_now())
		b.custom_minimum_size.x = Kit.px(150)
		tabs.add_child(b)
	right.add_child(tabs)
	var pane := Kit.panel("FDeepFrame")
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.custom_minimum_size = Kit.pxv(636, 440)
	var inner := EntityPanels.column(0)
	pane.add_child(inner)
	var shown: Array = coming if stop_tab == "on_the_way" else trs
	if shown.is_empty():
		var banner := PanelContainer.new()
		var red := StyleBoxFlat.new()
		red.bg_color = Color8(110, 38, 38)
		red.content_margin_top = Kit.px(6)
		red.content_margin_bottom = Kit.px(6)
		banner.add_theme_stylebox_override("panel", red)
		var l := Kit.label("⚠ There are no trains on the way to this stop." if stop_tab == "on_the_way"
			else "⚠ There are no trains with this stop in their schedule.", "FHeading")
		l.add_theme_color_override("font_color", Kit.WHITE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.add_child(l)
		banner.name = "NoTrains"
		inner.add_child(banner)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.name = "TrainCards"
	grid.add_theme_constant_override("h_separation", Kit.px(4))
	grid.add_theme_constant_override("v_separation", Kit.px(4))
	for t in shown:
		grid.add_child(_train_card(screen, t))
	inner.add_child(grid)
	right.add_child(pane)
	return right


## A train's card: a live view of the train from above (train_view.gd, as Factorio's minimap of
## it), its number, what it is doing, and whether it is coming here.
static func _train_card(screen, t: Array) -> Control:
	var card := Kit.panel("FShallowFrame")
	card.custom_minimum_size = Kit.pxv(206, 210)
	var col := EntityPanels.column(4)
	card.add_child(LogicKit.padded(col, 8, 6))
	var view := TrainView.new()
	view.name = "View"
	view.custom_minimum_size = Kit.pxv(190, 110)
	var model = screen.get("model")
	var at := Vector2.ZERO
	var known := false
	if model != null:
		for tr in model.trains_overview:
			if int(tr["id"]) == int(t[0]):
				at = tr["position"]
				known = true
	var unit := int(t[3]) if t.size() >= 4 else 0
	view.show_train(unit, at)
	var tree: SceneTree = screen.get_tree() if screen.is_inside_tree() else null
	if tree != null:
		view.movers = tree.root.find_child("Movers", true, false)
		var up: Node = screen
		while up != null and up.get("map_cache") == null:
			up = up.get_parent()
		view.cache = up.get("map_cache") if up != null else null
	view.visible = known or unit != 0
	col.add_child(view)
	col.add_child(Kit.label("Train %d" % int(t[0]), "FHeading"))
	col.add_child(Kit.label(state_text(str(t[1]))))
	if int(t[2]) == 1:
		col.add_child(LogicKit.grey("Heading here"))
	card.name = "Train%d" % int(t[0])
	return card
