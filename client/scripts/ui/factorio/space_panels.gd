extends RefCounted
## Space Age's entity windows for machine_screen.gd, from space.lua's `gui` fields:
##   hub        the space platform hub: the platform's state, its trip and speed, weight,
##              thrusters and their fuel, pause and "provide to other platforms"; its schedule
##              (stations, Factorio's platform wait conditions, interrupts); its requests from
##              planets as logistic sections (item, quality, minimum, maximum, "import from" and
##              the minimum delivery count)
##   silo       a rocket silo: the rocket parts, its status, "send to orbit automatically" and,
##              for each platform in orbit, Launch (to its hub, or its starter pack) and Ride (the
##              character goes up in the rocket, scripts/world/ride.gd)
##   pad        a cargo landing pad: its requests from orbit and its circuit settings
##   bay        a cargo bay: what it is connected to
##   collector  an asteroid collector's chunk filters
##   effects    a machine's module and beacon effects (quality among them)
## and quality_row, the quality buttons of recipe pickers and request editors.
## Like entity_panels.gd, each builder takes the screen (unit, model, picker, held_item, _last)
## and returns a Control; changes are sent at once.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const LocaleNames := preload("res://scripts/world/locale_names.gd")
const ProductionPanels := preload("res://scripts/ui/factorio/production_panels.gd")

## Factorio's platform wait conditions (WaitConditionType), in the order its menu lists them.
const PLATFORM_WAITS := [["time", "Time passed"], ["inactivity", "Inactivity"],
	["all_requests_satisfied", "All requests satisfied"], ["any_request_not_satisfied", "Any request not satisfied"],
	["any_request_zero", "Any request zero"], ["request_satisfied", "Request satisfied"],
	["request_not_satisfied", "Request not satisfied"], ["any_planet_import_zero", "Any planet import zero"],
	["item_count", "Item count"], ["fluid_count", "Fluid count"], ["circuit", "Circuit condition"],
	["damage_taken", "Damage taken"]]
const REQUEST_WAITS := ["request_satisfied", "request_not_satisfied"]
const STATES := {
	"waiting_at_station": "Waiting at %s", "on_the_path": "Travelling", "paused": "Paused",
	"no_schedule": "No schedule", "no_path": "No path", "waiting_for_departure": "Waiting for departure",
	"waiting_for_starter_pack": "Waiting for the starter pack", "starter_pack_requested": "Starter pack requested",
	"starter_pack_on_the_way": "Starter pack on the way",
}
## defines.rocket_silo_status in Factorio's words.
const SILO_STATES := {
	"building_rocket": "Building rocket", "create_rocket": "Creating rocket", "lights_blinking_open": "Preparing for launch",
	"doors_opening": "Opening doors", "doors_opened": "Doors opened", "rocket_rising": "Rocket rising",
	"arms_advance": "Arms advancing", "rocket_ready": "Rocket ready", "launch_starting": "Launch starting",
	"engine_starting": "Engine starting", "arms_retract": "Arms retracting", "rocket_flying": "Rocket flying",
	"lights_blinking_close": "Closing", "doors_closing": "Closing doors", "launch_started": "Launch started",
}
const EFFECT_NAMES := [["sp", "Speed"], ["pr", "Productivity"], ["co", "Consumption"], ["po", "Pollution"], ["q", "Quality"]]
const FUEL_COLOR := Color(0.85, 0.55, 0.2)
## How tall the hub's settings are before they scroll (GUI pixels).
const HUB_HEIGHT := 420


## A platform's name with Factorio's rich text ("[planet=vulcanus]") in plain words.
static func plain(name: String) -> String:
	var re := RegEx.create_from_string("\\[(item|planet|space-location|fluid|virtual-signal|entity|recipe)=([^\\],]+)[^\\]]*\\]")
	var out := name
	for m in re.search_all(name):
		var what := m.get_string(2)
		out = out.replace(m.get_string(0), LocaleNames.space_location(what) if m.get_string(1) in ["planet", "space-location"] else Kit.pretty(what))
	return out.strip_edges()


static func place(name: String) -> String:
	return LocaleNames.space_location(name) if name != "" else "?"


static func _dim(text: String) -> Label:
	var l := Kit.label(text)
	l.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	return l


static func _array(v) -> Array:
	return v if v is Array else []


# --- the hub -------------------------------------------------------------------------------------

## gui.hub (space.lua): the platform, its schedule and its requests.
static func hub(screen, h: Dictionary) -> Control:
	var box := EntityPanels.column(10)
	box.add_child(_platform_state(screen, h))
	box.add_child(EntityPanels.pane(_schedule(screen, h)))
	var sec: Array = _array(h.get("sec")).duplicate(true)
	box.add_child(EntityPanels.pane(sections(screen, sec, _array(h.get("dest")), true)))
	# The schedule and requests grow long on a real platform: they scroll, so the window fits.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.custom_minimum_size = Vector2(0, Kit.px(HUB_HEIGHT))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return scroll


## The hub window's third column, as Factorio's: the platform (its state, trip, speed, weight,
## thrusters and fuel, pause) and its schedule with interrupts, scrolling when long.
static func hub_platform(screen, h: Dictionary) -> Control:
	var box := EntityPanels.column(10)
	box.add_child(_platform_state(screen, h))
	box.add_child(_schedule(screen, h))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.custom_minimum_size = Vector2(0, Kit.px(HUB_HEIGHT))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return scroll


## The hub's "Provide materials to other platforms" box (over its inventory, as in Factorio).
static func provide_box(screen, h: Dictionary) -> Control:
	var unit: int = screen.unit
	var prov := func(on: bool) -> void: Bridge.send({"t": "set_hub", "u": unit, "prov": 1 if on else 0})
	var c := EntityPanels.checkbox("Provide materials to other platforms", int(h.get("prov", 0)) == 1, prov)
	c.tooltip_text = "Other platforms over the same planet can take this hub's items."
	return c


## A landing pad's circuit settings (Factorio puts them in its circuit connection panel).
static func pad_circuit(screen, p: Dictionary) -> Control:
	var box := EntityPanels.column(6)
	var cb: Dictionary = p.get("cb") if p.get("cb") is Dictionary else {}
	var unit: int = screen.unit
	box.add_child(EntityPanels.heading("Circuit connection"))
	for opt in [["read", "Read contents"], ["req", "Set requests"], ["empty", "Read empty slots"]]:
		var key := str(opt[0])
		var on := func(v: bool) -> void: Bridge.send({"t": "set_pad", "u": unit, key: 1 if v else 0})
		box.add_child(EntityPanels.checkbox(str(opt[1]), int(cb.get(key, 0)) == 1, on))
	return box


## The trip, speed, weight, thrusters and fuel; pause. Labels
## that change while travelling are kept in the screen's meta "hub_live" so refresh() updates them
## without rebuilding the window.
static func _platform_state(screen, h: Dictionary) -> Control:
	var box := EntityPanels.column(4)
	var title := EntityPanels.row(8)
	title.add_child(Kit.label(plain(str(h.get("n", "Space platform"))), "FHeading"))
	var state := Kit.label("")
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(state)
	var paused := int(h.get("pa", 0)) == 1
	var unit: int = screen.unit
	var pause_btn := EntityPanels.button("Resume" if paused else "Pause",
		func() -> void: Bridge.send({"t": "set_hub", "u": unit, "pa": 0 if paused else 1}), 90)
	title.add_child(pause_btn)
	box.add_child(title)
	var bar := Kit.progress_bar(Kit.BAR_GREEN)
	bar.max_value = 1000
	bar.custom_minimum_size = Kit.pxv(300, 10)
	bar.show_percentage = false
	box.add_child(bar)
	var info := Kit.label("")
	box.add_child(info)
	var fuel_box := EntityPanels.column(2)
	box.add_child(fuel_box)
	screen.set_meta("hub_live", {"state": state, "bar": bar, "info": info, "fuel": fuel_box})
	refresh(screen, {"hub": h})
	return EntityPanels.pane(box)


## Updates the hub's moving parts from a new `gui` (machine_screen.gd calls it every message).
static func refresh(screen, msg: Dictionary) -> void:
	var live = screen.get_meta("hub_live") if screen.has_meta("hub_live") else null
	var h = msg.get("hub")
	if not (live is Dictionary and h is Dictionary and is_instance_valid(live["state"])):
		return
	var st := str(h.get("st", ""))
	var loc := str(h.get("loc", ""))
	var travelling: bool = h.has("to")
	var text: String = STATES.get(st, st.capitalize())
	if st == "waiting_at_station":
		text = text % place(loc)
	elif travelling:
		text = "%s: %s → %s" % [text, place(str(h.get("from", ""))), place(str(h.get("to", "")))]
	elif loc != "":
		text = "%s at %s" % [text, place(loc)]
	(live["state"] as Label).text = text
	var bar: ProgressBar = live["bar"]
	bar.visible = travelling
	bar.value = int(h.get("d", 0))
	var parts: Array = ["Speed %s km/s" % str(snappedf(float(h.get("sp", 0.0)), 0.1))]
	if travelling and h.has("len"):
		var length := int(h["len"])
		parts.append("%s / %s km" % [Kit.count_text(int(length * int(h.get("d", 0)) / 1000.0)), Kit.count_text(length)])
	parts.append("Weight %d t" % roundi(int(h.get("w", 0)) / 1000.0))
	var th := _array(h.get("th"))
	if th.size() >= 2:
		parts.append("Thrusters %d / %d working" % [int(th[1]), int(th[0])])
	(live["info"] as Label).text = " · ".join(parts)
	var fuel_box: VBoxContainer = live["fuel"]
	for c in fuel_box.get_children():
		fuel_box.remove_child(c)
		c.queue_free()
	for f in _array(h.get("fuel")):
		if f is Array and f.size() >= 3:
			var r := EntityPanels.row(8)
			var name := Kit.label(Kit.pretty(str(f[0])))
			name.custom_minimum_size.x = Kit.px(150)
			r.add_child(name)
			var fb := Kit.progress_bar(FUEL_COLOR)
			fb.max_value = maxf(1.0, float(f[2]))
			fb.value = float(f[1])
			fb.custom_minimum_size = Kit.pxv(160, 10)
			fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			r.add_child(fb)
			r.add_child(Kit.label("%s / %s" % [Kit.count_text(int(f[1])), Kit.count_text(int(f[2]))]))
			fuel_box.add_child(r)


## The platform's schedule: each stop with its wait conditions (Go, remove), stops to add from the
## unlocked destinations, and interrupts. Sent with the train commands on the hub's unit.
static func _schedule(screen, h: Dictionary) -> Control:
	var box := EntityPanels.column(6)
	var sched: Dictionary = h.get("sched") if h.get("sched") is Dictionary else {}
	var dest := _array(h.get("dest"))
	var head := EntityPanels.row(8)
	head.add_child(EntityPanels.heading("Schedule"))
	if str(sched.get("group", "")) != "":
		head.add_child(_dim("Group: %s" % sched["group"]))
	box.add_child(head)
	var records: Array = _array(sched.get("records")).duplicate(true)
	var unit: int = screen.unit
	var send := func(l: Array) -> void: screen.model.set_schedule(unit, l)
	box.add_child(_records(screen, records, int(sched.get("current", 0)), dest, true, send))
	var interrupts: Array = _array(sched.get("interrupts")).duplicate(true)
	box.add_child(_interrupts(screen, interrupts, dest))
	return box


static func _records(screen, records: Array, current: int, dest: Array, can_go: bool, on_change: Callable) -> Control:
	var list := EntityPanels.column(4)
	for i in records.size():
		var index := i
		var rec: Dictionary = records[i] if records[i] is Dictionary else {}
		var r := EntityPanels.row(6)
		var marker := Kit.label("▶" if i + 1 == current else "")
		marker.custom_minimum_size.x = Kit.px(16)
		r.add_child(marker)
		var icon := TextureRect.new()
		icon.texture = planet_icon(str(rec.get("station", "")))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Kit.pxv(24, 24)
		r.add_child(icon)
		var name := Kit.label(place(str(rec.get("station", ""))))
		name.custom_minimum_size.x = Kit.px(160)
		r.add_child(name)
		if can_go:
			r.add_child(EntityPanels.button("Go", func() -> void: screen.model.train_go(screen.unit, index + 1), 44))
		var remove := func() -> void:
			var l := records.duplicate(true)
			l.remove_at(index)
			on_change.call(l)
		r.add_child(EntityPanels.button("✕", remove, 30))
		list.add_child(r)
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", Kit.px(22))
		var set_waits := func(w: Array) -> void:
			var l := records.duplicate(true)
			l[index]["wait_conditions"] = w
			on_change.call(l)
		indent.add_child(_waits(screen, _array(rec.get("wait_conditions")).duplicate(true), dest, set_waits))
		list.add_child(indent)
	var add := MenuKit.dropdown(dest.map(func(n): return [place(str(n)), n]), "")
	add.select(-1)
	add.custom_minimum_size.x = Kit.px(200)
	var add_stop := func(k: int) -> void:
		var l := records.duplicate(true)
		l.append({"station": str(dest[k]), "wait_conditions": [{"type": "all_requests_satisfied", "compare_type": "and"}]})
		on_change.call(l)
	add.item_selected.connect(add_stop)
	var add_row := EntityPanels.row(8)
	add_row.add_child(Kit.label("+ Add stop"))
	add_row.add_child(add)
	list.add_child(add_row)
	return list


## A platform wait condition of that type with Factorio's defaults.
static func new_wait(t: String, compare := "and") -> Dictionary:
	var w := {"type": t, "compare_type": compare}
	if t == "time":
		w["ticks"] = 30 * 60
	elif t == "inactivity":
		w["ticks"] = 5 * 60
	elif t in ["item_count", "fluid_count", "circuit"]:
		w["condition"] = {"comparator": "<", "constant": 0}
	elif t == "damage_taken":
		w["damage"] = 1000
	return w


static func _waits(screen, waits: Array, dest: Array, on_change: Callable) -> Control:
	var box := EntityPanels.column(2)
	for i in waits.size():
		var index := i
		var w: Dictionary = waits[i] if waits[i] is Dictionary else {}
		var changed := func(c) -> void:
			var l := waits.duplicate(true)
			if c == null:
				l.remove_at(index)
			else:
				l[index] = c
			on_change.call(l)
		box.add_child(_wait_row(screen, w, i == 0, dest, changed))
	var add := MenuKit.dropdown(PLATFORM_WAITS.map(func(p): return [p[1], p[0]]), "")
	add.select(-1)
	add.custom_minimum_size.x = Kit.px(190)
	var add_wait := func(k: int) -> void:
		var l := waits.duplicate(true)
		l.append(new_wait(str(PLATFORM_WAITS[k][0])))
		on_change.call(l)
	add.item_selected.connect(add_wait)
	var add_row := EntityPanels.row(6)
	add_row.add_child(Kit.label("+ Condition"))
	add_row.add_child(add)
	box.add_child(add_row)
	return box


static func _wait_row(screen, w: Dictionary, first: bool, dest: Array, on_change: Callable) -> Control:
	var r := EntityPanels.row(4)
	if not first:
		var andor := MenuKit.dropdown([["and", "and"], ["or", "or"]], str(w.get("compare_type", "and")))
		andor.custom_minimum_size.x = Kit.px(64)
		var set_andor := func(k: int) -> void:
			var c := w.duplicate(true)
			c["compare_type"] = "and" if k == 0 else "or"
			on_change.call(c)
		andor.item_selected.connect(set_andor)
		r.add_child(andor)
	var t := str(w.get("type", "time"))
	var types: Array = PLATFORM_WAITS.map(func(p): return [p[1], p[0]])
	if not PLATFORM_WAITS.any(func(p): return p[0] == t):
		types.append([t.replace("_", " ").capitalize(), t])
	var kind := MenuKit.dropdown(types, t)
	kind.custom_minimum_size.x = Kit.px(190)
	var compare := str(w.get("compare_type", "and"))
	kind.item_selected.connect(func(k: int) -> void: on_change.call(new_wait(str(types[k][1]), compare)))
	r.add_child(kind)
	var set_field := func(key: String, value) -> void:
		var c := w.duplicate(true)
		c[key] = value
		on_change.call(c)
	if t == "time" or t == "inactivity":
		r.add_child(EntityPanels.number_box(int(w.get("ticks", 0)) / 60, func(v: int) -> void: set_field.call("ticks", maxi(0, v) * 60), 56))
		r.add_child(Kit.label("s"))
	elif t in ["item_count", "fluid_count", "circuit"]:
		var cond: Dictionary = (w.get("condition") as Dictionary).duplicate(true) if w.get("condition") is Dictionary else {"comparator": "<", "constant": 0}
		var kinds: Array = ["fluid"] if t == "fluid_count" else (["item", "fluid", "virtual"] if t == "circuit" else ["item"])
		r.add_child(EntityPanels._condition_editor(screen, cond, kinds, func(c: Dictionary) -> void: set_field.call("condition", c)))
	elif t in REQUEST_WAITS:
		var cond: Dictionary = w.get("condition") if w.get("condition") is Dictionary else {}
		var set_item := func(_type: String, item: String) -> void:
			set_field.call("condition", {"name": item, "quality": str(cond.get("quality", "normal"))} if item != "" else {})
		r.add_child(EntityPanels.choose_slot(screen, EntityPanels._signal_name(cond), ["item"], set_item, "Item"))
	elif t == "any_planet_import_zero":
		var planets: Array = dest.duplicate()
		planets.push_front("")
		var pick := MenuKit.dropdown(planets.map(func(n): return [place(str(n)) if str(n) != "" else "Any planet", n]), str(w.get("planet", "")))
		pick.custom_minimum_size.x = Kit.px(150)
		pick.item_selected.connect(func(k: int) -> void: set_field.call("planet", str(planets[k])))
		r.add_child(pick)
	elif t == "damage_taken":
		r.add_child(EntityPanels.number_box(int(w.get("damage", 0)), func(v: int) -> void: set_field.call("damage", maxi(0, v)), 70))
	r.add_child(EntityPanels.button("✕", func() -> void: on_change.call(null), 30))
	return r


static func _interrupts(screen, interrupts: Array, dest: Array) -> Control:
	var box := EntityPanels.column(6)
	box.add_child(EntityPanels.heading("Interrupts"))
	var unit: int = screen.unit
	var send := func(l: Array) -> void: screen.model.set_interrupts(unit, l)
	for i in interrupts.size():
		var index := i
		var it: Dictionary = interrupts[i] if interrupts[i] is Dictionary else {}
		var r := EntityPanels.row(8)
		r.add_child(Kit.label(str(it.get("name", "")), "FHeading"))
		var set_inside := func(on: bool) -> void:
			var l := interrupts.duplicate(true)
			l[index]["inside_interrupt"] = on
			send.call(l)
		r.add_child(EntityPanels.checkbox("Interrupt other interrupts", bool(it.get("inside_interrupt", false)), set_inside))
		var remove := func() -> void:
			var l := interrupts.duplicate(true)
			l.remove_at(index)
			send.call(l)
		r.add_child(EntityPanels.button("✕", remove, 30))
		box.add_child(r)
		var inner := MarginContainer.new()
		inner.add_theme_constant_override("margin_left", Kit.px(22))
		var parts := EntityPanels.column(4)
		parts.add_child(_dim("Conditions"))
		var set_conds := func(w: Array) -> void:
			var l := interrupts.duplicate(true)
			l[index]["conditions"] = w
			send.call(l)
		parts.add_child(_waits(screen, _array(it.get("conditions")).duplicate(true), dest, set_conds))
		parts.add_child(_dim("Targets"))
		var set_targets := func(t: Array) -> void:
			var l := interrupts.duplicate(true)
			l[index]["targets"] = t
			send.call(l)
		parts.add_child(_records(screen, _array(it.get("targets")).duplicate(true), 0, dest, false, set_targets))
		inner.add_child(parts)
		box.add_child(inner)
	var add_row := EntityPanels.row(8)
	add_row.add_child(Kit.label("+ Add interrupt"))
	var field := MenuKit.textbox("", "Name")
	field.custom_minimum_size.x = Kit.px(180)
	var add := func(t: String) -> void:
		if t.strip_edges() == "":
			return
		var l := interrupts.duplicate(true)
		l.append({"name": t.strip_edges(), "conditions": [], "targets": [], "inside_interrupt": false})
		send.call(l)
	field.text_submitted.connect(add)
	add_row.add_child(field)
	box.add_child(add_row)
	return box


## A planet's (or space location's) icon from the player's install, or null.
static func planet_icon(name: String) -> Texture2D:
	if name == "":
		return null
	for path in ["space-age/graphics/icons/%s.png", "base/graphics/icons/%s.png"]:
		var t := GuiAssets.data_sprite(path % name)
		if t != null:
			return t
	return null


# --- logistic sections (the hub's requests from planets, the pad's from orbit) ------------------

## Factorio's logistic sections: each with its group name, an on/off box, the multiplier, and its
## request slots (the minimum as the count, the quality's icon). Click a slot to edit its quality,
## minimum, maximum and, on a hub, "import from" and the minimum delivery count; right click
## removes it; an empty slot adds the held item or one from the chooser.
static func sections(screen, secs: Array, dest: Array, hub_like: bool) -> Control:
	var box := EntityPanels.column(6)
	box.add_child(EntityPanels.heading("Requests from planets" if hub_like else "Requests"))
	var qualities := _array(screen._last.get("ql"))
	var slots := func(sec: Dictionary, filters: Array, send: Callable) -> Control:
		if int(sec.get("man", 1)) != 1:
			return _dim("Set by the game")
		return _request_slots(screen, filters, dest, qualities, hub_like, send, Kit.COLUMNS)
	box.add_child(ProductionPanels.sections(screen, secs, slots))
	return box


static func _request_slots(screen, filters: Array, dest: Array, qualities: Array, hub_like: bool, on_change: Callable,
		columns := EntityPanels.PANE_COLUMNS) -> Control:
	var box := EntityPanels.column(4)
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var grid := Kit.slot_grid(columns)
	frame.add_child(grid)
	var editor := EntityPanels.column(4)
	editor.visible = false
	var cells := ceili((filters.size() + 1) / float(columns)) * columns
	for i in cells:
		var index := i
		var s := Slot.new()
		s.theme_type_variation = "FSlotButton"
		if i < filters.size() and filters[i] is Array and filters[i].size() >= 6:
			var f: Array = filters[i]
			s.set_stack(str(f[0]), int(f[2]))
			s.set_extra({"quality": str(f[1])})
			var lines: Array = [["Min %d · Max %s" % [int(f[2]), "none" if int(f[3]) < 0 else str(int(f[3]))]]]
			if hub_like:
				lines.append(["Import from: %s" % (place(str(f[4])) if str(f[4]) != "" else "any planet")])
				if int(f[5]) >= 0:
					lines.append(["Minimum delivery: %d" % int(f[5])])
			lines.append(["Click: change · Right click: remove", "", Kit.DISABLED_TEXT])
			s.set_tip(Kit.pretty(str(f[0])), Slot.extra_lines({"quality": str(f[1])}) + lines)
		else:
			s.set_tip("Add a request", [["Click: choose an item (or the one held)", "", Kit.DISABLED_TEXT]])
		var on_click := func(button_index: int, _shift: bool) -> void:
			if index < filters.size():
				if button_index == MOUSE_BUTTON_RIGHT:
					var l := filters.duplicate(true)
					l.remove_at(index)
					on_change.call(l)
				elif button_index == MOUSE_BUTTON_LEFT:
					_edit_request(editor, filters, index, dest, qualities, hub_like, on_change)
			elif button_index == MOUSE_BUTTON_LEFT:
				var add := func(_type: String, item: String) -> void:
					if item != "":
						var l := filters.duplicate(true)
						l.append([item, "normal", 100, -1, "", -1])
						on_change.call(l)
				var held: String = screen.held_item.call() if screen.held_item.is_valid() else ""
				if held != "":
					add.call("item", held)
				elif screen.picker != null:
					screen.picker.choose(["item"], add)
		s.clicked.connect(on_click)
		grid.add_child(s)
	box.add_child(frame)
	box.add_child(editor)
	return box


## One request's editor under the slots: quality, min, max, and on a hub import from and the
## minimum delivery count; Set sends it.
static func _edit_request(editor: VBoxContainer, filters: Array, index: int, dest: Array, qualities: Array, hub_like: bool, on_change: Callable) -> void:
	for c in editor.get_children():
		editor.remove_child(c)
		c.queue_free()
	editor.visible = true
	var f: Array = (filters[index] as Array).duplicate()
	editor.add_child(Kit.label(Kit.pretty(str(f[0])), "FHeading"))
	if qualities.size() > 1:
		var set_q := func(q: String) -> void: f[1] = q
		editor.add_child(quality_row(qualities, str(f[1]) if str(f[1]) != "" else "normal", set_q))
	var r := EntityPanels.row(6)
	var min_box := MenuKit.textbox(str(int(f[2])), "Min")
	min_box.custom_minimum_size.x = Kit.px(70)
	var max_box := MenuKit.textbox("" if int(f[3]) < 0 else str(int(f[3])), "Max: none")
	max_box.custom_minimum_size.x = Kit.px(90)
	r.add_child(Kit.label("Min"))
	r.add_child(min_box)
	r.add_child(Kit.label("Max"))
	r.add_child(max_box)
	editor.add_child(r)
	var from_pick: OptionButton = null
	var mdc_box: LineEdit = null
	if hub_like:
		var r2 := EntityPanels.row(6)
		var places: Array = dest.duplicate()
		places.push_front("")
		from_pick = MenuKit.dropdown(places.map(func(n): return [place(str(n)) if str(n) != "" else "Any planet", n]), str(f[4]))
		from_pick.custom_minimum_size.x = Kit.px(150)
		r2.add_child(Kit.label("Import from"))
		r2.add_child(from_pick)
		mdc_box = MenuKit.textbox("" if int(f[5]) < 0 else str(int(f[5])), "Default")
		mdc_box.custom_minimum_size.x = Kit.px(80)
		r2.add_child(Kit.label("Minimum delivery"))
		r2.add_child(mdc_box)
		editor.add_child(r2)
	var commit := func() -> void:
		if min_box.text.strip_edges().is_valid_int():
			f[2] = maxi(0, int(min_box.text.strip_edges()))
		f[3] = int(max_box.text.strip_edges()) if max_box.text.strip_edges().is_valid_int() else -1
		if from_pick != null and from_pick.selected >= 0:
			f[4] = str(from_pick.get_item_metadata(from_pick.selected))
		if mdc_box != null:
			f[5] = int(mdc_box.text.strip_edges()) if mdc_box.text.strip_edges().is_valid_int() else -1
		var l := filters.duplicate(true)
		l[index] = f
		on_change.call(l)
	editor.add_child(EntityPanels.button("Set", commit, 60))


## Quality buttons (each quality's icon), the chosen one pressed; on_pick(quality) gets a choice.
static func quality_row(qualities: Array, current: String, on_pick: Callable) -> Control:
	var r := EntityPanels.row(2)
	r.add_child(Kit.label("Quality"))
	var group := ButtonGroup.new()
	for q in qualities:
		var name := str(q)
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = name == current
		b.custom_minimum_size = Kit.pxv(32, 32)
		b.expand_icon = true
		b.icon = Slot.quality_icon(name)
		if b.icon == null:
			b.text = name.substr(0, 1).to_upper()
		b.tooltip_text = name.capitalize()
		b.pressed.connect(func() -> void: on_pick.call(name))
		r.add_child(b)
	return r


# --- silo, landing pad, bay, collector, effects ---------------------------------------------------

## gui.rk: {parts, need, st, auto, to: [[platform, name, state], ...]}.
static func silo(screen, rk: Dictionary) -> Control:
	var box := EntityPanels.column(6)
	var parts := int(rk.get("parts", 0))
	var need := maxi(1, int(rk.get("need", 1)))
	var st := str(rk.get("st", ""))
	var head := EntityPanels.row(12)
	head.add_child(Kit.label("Rocket parts: %d / %d" % [parts, need]))
	if st != "":
		head.add_child(_dim(SILO_STATES.get(st, st.capitalize())))
	box.add_child(head)
	var unit: int = screen.unit
	var auto := func(on: bool) -> void: Bridge.send({"t": "set_silo", "u": unit, "auto": 1 if on else 0})
	box.add_child(EntityPanels.checkbox("Send to orbit automatically", int(rk.get("auto", 0)) == 1, auto))
	var to := _array(rk.get("to"))
	box.add_child(EntityPanels.heading("Launch to"))
	if to.is_empty():
		box.add_child(_dim("No platform in orbit here"))
	var ready := st == "rocket_ready"
	for t in to:
		if not (t is Array and t.size() >= 3):
			continue
		var r := EntityPanels.row(8)
		var name := Kit.label(plain(str(t[1])))
		name.custom_minimum_size.x = Kit.px(180)
		r.add_child(name)
		var waiting := str(t[2]) in ["waiting_for_starter_pack", "starter_pack_requested"]
		r.add_child(_dim("waiting for its starter pack" if waiting else STATES.get(str(t[2]), str(t[2])).replace(" at %s", "")))
		var index := int(t[0])
		var b := EntityPanels.button("Launch", func() -> void: Bridge.send({"t": "silo_launch", "u": unit, "to": index}), 90)
		b.theme_type_variation = "FGreenButton"
		b.disabled = not ready
		b.tooltip_text = "Launch the rocket to %s" % str(t[1]) if ready else "The rocket isn't ready"
		r.add_child(b)
		# Riding up: the character gets into the rocket and goes to the platform's hub.
		var go_up := func() -> void:
			Bridge.send({"t": "ride", "u": unit, "to": index})
			screen.close()
		var ride := EntityPanels.button("Ride", go_up, 70)
		ride.name = "Ride%d" % index
		ride.theme_type_variation = "FGreenButton"
		ride.disabled = not ready or waiting
		ride.tooltip_text = ("Ride the rocket up to %s's hub" % plain(str(t[1])) if ready and not waiting
			else ("The platform has no hub yet" if waiting else "The rocket isn't ready"))
		r.add_child(ride)
		box.add_child(r)
	return box


## gui.pad: {sec, cb?: {read, req, empty}}.
static func pad(screen, p: Dictionary) -> Control:
	var box := EntityPanels.column(8)
	box.add_child(sections(screen, _array(p.get("sec")).duplicate(true), [], false))
	var cb: Dictionary = p.get("cb") if p.get("cb") is Dictionary else {}
	var unit: int = screen.unit
	box.add_child(EntityPanels.heading("Circuit connection"))
	for opt in [["read", "Read contents"], ["req", "Set requests"], ["empty", "Read empty slots"]]:
		var key := str(opt[0])
		var on := func(v: bool) -> void: Bridge.send({"t": "set_pad", "u": unit, key: 1 if v else 0})
		box.add_child(EntityPanels.checkbox(str(opt[1]), int(cb.get(key, 0)) == 1, on))
	return EntityPanels.pane(box)


static func bay(b: Dictionary) -> Control:
	var owner := int(b.get("owner", 0))
	return EntityPanels.pane(Kit.label("Connected: its slots are part of the hub's or landing pad's inventory" if owner != 0
		else "Not connected to a hub or landing pad"))


## gui.col: {n, f: [chunk or ""]}. Click a filter: the next asteroid chunk; right click clears it.
static func collector(screen, col: Dictionary) -> Control:
	var box := EntityPanels.column(6)
	box.add_child(EntityPanels.heading("Asteroid chunk filter"))
	var n := int(col.get("n", 0))
	var filters: Array = _array(col.get("f")).duplicate()
	while filters.size() < n:
		filters.append("")
	var chunks := _chunk_names(screen)
	var unit: int = screen.unit
	var r := EntityPanels.row(4)
	for i in n:
		var index := i
		var s := Slot.new()
		s.theme_type_variation = "FSlotButton"
		s.set_stack(str(filters[i]), -1)
		s.set_tip(Kit.pretty(str(filters[i])) if str(filters[i]) != "" else "No filter",
			[["Click: the next asteroid chunk · Right click: clear", "", Kit.DISABLED_TEXT]])
		var on_click := func(button_index: int, _shift: bool) -> void:
			var l := filters.duplicate()
			if button_index == MOUSE_BUTTON_RIGHT or chunks.is_empty():
				l[index] = ""
			else:
				var at := chunks.find(str(l[index]))
				l[index] = chunks[(at + 1) % chunks.size()]
			Bridge.send({"t": "set_collector", "u": unit, "f": l})
		s.clicked.connect(on_click)
		r.add_child(s)
	box.add_child(r)
	r.tooltip_text = "Collects only these chunks (none set: any)"
	return box


## Asteroid chunks the game knows (items named *-asteroid-chunk).
static func _chunk_names(screen) -> Array:
	var out: Array = []
	var protos = screen.protos
	if protos != null:
		for name in protos.item_names.values():
			if str(name).ends_with("-asteroid-chunk"):
				out.append(str(name))
	if out.is_empty():
		out = ["metallic-asteroid-chunk", "carbonic-asteroid-chunk", "oxide-asteroid-chunk"]
	out.sort()
	return out


## gui.eff: the machine's effects, Factorio's "+20% speed" lines, in thousandths.
static func effects(eff: Dictionary) -> Control:
	var r := EntityPanels.row(14)
	r.add_child(EntityPanels.heading("Effects"))
	for e in EFFECT_NAMES:
		if eff.has(e[0]):
			var v := int(eff[e[0]]) / 10.0
			var l := Kit.label("%s %s%s%%" % [e[1], "+" if v > 0 else "", str(snappedf(v, 0.1))])
			var good := v > 0 if e[0] in ["sp", "pr", "q"] else v < 0
			l.add_theme_color_override("font_color", Kit.GREEN_TEXT if good else Kit.RED_TEXT)
			r.add_child(l)
	return r
