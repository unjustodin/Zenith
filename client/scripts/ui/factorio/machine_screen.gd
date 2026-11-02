extends PanelContainer
## An open machine's screen, the right side of the character window like in Factorio (the
## inventory stays on the left), from the mod's "gui" messages (twice a second while open). Under
## the title (the entity's name) Factorio's status line (a coloured dot and "Working", "No
## ingredients", "No fuel", "Normal" for a chest...) and the entity preview, then
## production_panels.gd's rows as Factorio lays them out:
##   chest:      a 10-wide grid with the red X limit button inside it (click it, then a slot, to
##               move the limit there; right click: no limit); logistic chests' filters, requests
##               and trash slots
##   assembler:  the recipe row (gear: Factorio's recipe chooser, a window of its own, as is an
##               assembler without a recipe), ingredients, progress with %, products, fuel, modules
##   furnace:    the product row, source, progress, result (the recycler's 12), fuel, modules
##   drills, burners, reactors, labs, beacons, the agricultural tower: their own rows
##   others:     each inventory as a row of slots
## then what entity_panels.gd draws for the kind (inserter filters, splitter priorities, power
## switch, rocket parts, pole statistics, train stop, schedule, roboport logistics),
## entity_settings.gd's (colour, speaker, pump filter, turret targets, display panel messages),
## circuit_panel.gd's (combinators, the circuit and logistic connection, the network signals),
## and the fluid boxes of entities that aren't production machines. Slots report clicks to
## factorio_ui.gd (slot_clicked), which picks stacks up into the cursor or moves them. Without slot
## data from the mod (`gui.slots`) the slots are the item totals and a click takes them
## (take/put). The mod closes the screen when the machine is gone or out of reach.

const ProtoDB := preload("res://scripts/world/protos.gd")
const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const CircuitPanel := preload("res://scripts/ui/factorio/circuit_panel.gd")
const EntitySettings := preload("res://scripts/ui/factorio/entity_settings.gd")
const SpacePanels := preload("res://scripts/ui/factorio/space_panels.gd")
const ProductionPanels := preload("res://scripts/ui/factorio/production_panels.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const LogicWindows := preload("res://scripts/ui/factorio/logic_windows.gd")
const CircuitWindow := preload("res://scripts/ui/factorio/circuit_window.gd")

## Shown or hidden (the window lays itself out around it).
signal opened_changed(open: bool)
## A slot of the machine was clicked. `index` is 1-based, or 0 without slot data (then `item` and
## `count` are the total of that item in `role`).
signal slot_clicked(role: String, index: int, item: String, count: int, button_index: int, shift: bool, ctrl: bool)

const ROLE_TITLES := {
	"chest": "Contents", "input": "Ingredients", "output": "Products", "fuel": "Fuel",
	"burnt": "Burnt result", "modules": "Modules", "cargo": "Cargo", "ammo": "Ammo", "trunk": "Trunk",
	"turret_ammo": "Ammo", "car_ammo": "Ammo", "trash": "Trash", "robots": "Robots", "repair": "Repair packs",
	"rocket": "Rocket inventory",
}
const OTHER_ROLES := ["input", "output", "fuel", "burnt", "modules", "chest", "cargo", "ammo", "trunk", "turret_ammo",
	"car_ammo", "robots", "repair", "rocket", "trash"]
## Slots of the vanilla chests, for mods that don't send `gui.slots` (which gives the real size).
const CHEST_SLOTS := {"wooden-chest": 16, "iron-chest": 32, "steel-chest": 48}
## Space Age's hub and landing pad hold hundreds of slots: their inventories scroll after this
## many rows, so the platform's settings under them stay on screen.
const SCROLL_ROWS := 4
const SCROLLED_KINDS := ["hub", "pad"]
## No message for this long means the mod refused to open it (it says why) or the link is gone.
const STALE_MSEC := 3000
## Entity status (defines.entity_status names) -> the dot Factorio shows. Anything else is yellow.
const GREEN_STATUS := ["working", "normal", "charging", "discharging", "fully_charged", "networks_connected"]
const RED_STATUS := ["item_ingredient_shortage", "fluid_ingredient_shortage", "full_output", "waiting_for_space_in_destination",
	"no_modules_to_transmit", "no_food", "full_burnt_result_output", "no_power", "no_fuel", "no_recipe", "no_ingredients", "no_input_fluid", "no_minable_resources",
	"no_research_in_progress", "missing_required_fluid", "missing_science_packs", "disabled", "disabled_by_script",
	"disabled_by_control_behavior", "marked_for_deconstruction", "not_plugged_in_electric_network", "no_ammo", "broken",
	"networks_disconnected", "frozen", "not_connected_to_rail"]
## Status names whose English text isn't the name with spaces (core.cfg's [entity-status]).
const STATUS_TEXT := {
	"full_output": "Output full", "waiting_for_space_in_destination": "Target full",
	"cant_divide_segments": "Cannot divide segments", "not_enough_space_in_output": "Not enough space in the output",
	"full_burnt_result_output": "Burnt result output full",
}

var protos: ProtoDB
## Set by factorio_ui.gd: the UI model (commands), the item chooser, the held item, the names of
## train stops near the camera, and opening the statistics window (kind, target).
var model = null
var picker = null
var held_item := Callable()
var stop_names := Callable()
var open_stats := Callable()
## (unit, map position): remote view following a mover (a train window's camera click).
var remote_follow := Callable()
## Unit number of the entity being shown or asked for; 0 when closed.
var unit := 0
## The open entity's identity as `open` named it ({u, p, x, y}) and its prototype name.
var target := {}
var proto_name := ""
## Where the stack in the cursor came from: [role, index], or [] (factorio_ui.gd sets it).
var hand_slot: Array = []

var _title: Label
var _body := VBoxContainer.new()
var _columns := HBoxContainer.new()
var _progress: ProgressBar = null
var _recipes: Array = []  # what the assembler can make (`rl`), kept between messages
var _recipe_groups: Array = []  # their item groups (`rg`), for the chooser's tabs
var _picking := false  # the recipe chooser is showing (the gear button)
var _pick_quality := "normal"  # the quality the recipe chooser sets (Space Age)
var _pick_group := ""  # the chooser's group tab
var _was_alone := false
## The entity preview, kept while the same prototype's screen is rebuilt.
var _preview: Control = null
var _preview_proto := ""
## What the progress bar shows: "pr" (crafting) or "mp" (mining).
var _progress_key := "pr"
var _sig := ""
var _scroll_key := ""  # unit|kind of the last build, whose scroll places a rebuild keeps
var _last_msec := 0
var _last: Dictionary = {}
## Setting the chest's limit: the next slot click moves the bar there.
var _setting_bar := false
## The circuit and logistic connection windows docked on the right (circuit_window.gd).
var circuit_dock = CircuitWindow.new()


func _ready() -> void:
	theme = EntityPanels.theme()
	theme_type_variation = "FFrameRight"
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	# Factorio's entity window is one frame: the entity's name heads the character window's half
	# (character_window.gd shows title_text() there), this half carries on the drag handle to the
	# close button, and the contents sit in an inside_shallow_frame.
	var bar := Kit.title_bar("", true)
	_title = bar.get_child(0)
	_title.visible = false
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(close)
	circuit_dock.screen = self
	circuit_dock.add_buttons(bar)
	_dock.call_deferred()
	box.add_child(bar)
	# Factorio's bigger windows (silo, landing pad, hub) add columns of their own beside the first.
	_columns.add_theme_constant_override("separation", Kit.px(12))
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_columns)
	var shallow := Kit.panel("FShallowFrame")
	shallow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shallow.custom_minimum_size.x = Kit.px(Kit.SLOT * Kit.COLUMNS + 24)
	_columns.add_child(shallow)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(12))
	pad.add_theme_constant_override("margin_top", Kit.px(8))
	shallow.add_child(pad)
	_body.add_theme_constant_override("separation", Kit.px(8))
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(_body)


## Asks the mod to open an entity. The panel shows once its first state arrives.
func request(target_unit: int, cmd: Dictionary) -> void:
	unit = target_unit
	target = cmd.duplicate()
	_last_msec = Time.get_ticks_msec()
	_sig = ""
	_recipes = []
	_recipe_groups = []
	_pick_group = ""
	_picking = false
	_setting_bar = false
	set_meta("chooser_search", "")
	_last = {}
	_set_open(false)
	Bridge.send(cmd)


func is_open() -> bool:
	return visible and unit != 0


## The open entity's name, for the window's title.
func title_text() -> String:
	return _title.text


## The circuit window goes right of the screen, in the same row of the character window.
func _dock() -> void:
	var parent := get_parent()
	if parent != null and circuit_dock.get_parent() == null:
		parent.add_child(circuit_dock)
		parent.move_child(circuit_dock, get_index() + 1)


## Entity types whose Factorio window is a narrow one of its own, without the character's
## inventory beside it (seen in tools/ui_reference's pictures).
const ALONE_TYPES := ["lamp", "programmable-speaker", "power-switch", "display-panel", "pump", "storage-tank",
	"splitter", "lane-splitter", "transport-belt", "arithmetic-combinator", "decider-combinator", "constant-combinator",
	"selector-combinator", "offshore-pump", "accumulator", "radar", "heat-interface", "rail-signal", "rail-chain-signal",
	"locomotive", "train-stop", "pipe", "pipe-to-ground", "heat-pipe", "land-mine"]


## Whether the open entity's window has the character's inventory beside it.
func shows_inventory() -> bool:
	if choosing_recipe():
		return false
	var proto: ProtoDB.EntityProto = protos.entities_by_name.get(proto_name) if protos != null else null
	if proto != null and proto.type == "boiler" and not knows_slots("fuel") and not (_last.get("inv", {}) as Dictionary).has("fuel"):
		return false  # a heat exchanger: the compact window, its temperature only
	return proto == null or not ALONE_TYPES.has(proto.type)


## Factorio opens an assembler without a recipe (or after its gear button) as the recipe chooser
## alone: "Select a recipe for assembling".
func choosing_recipe() -> bool:
	if str(_last.get("kind", "")) != "crafter" or int(_last.get("fixed", 0)) == 1:
		return false
	return _picking or str(_last.get("recipe", "")) == ""


## Ctrl+F while the recipe chooser is open: its search box. False when there is none.
func focus_search() -> bool:
	if not (is_open() and choosing_recipe()):
		return false
	var box: LineEdit = find_child("ChooserSearch", true, false)
	if box == null:
		return false
	box.visible = true
	box.grab_focus()
	box.select_all()
	return true


## The open entity's prototype type ("" unknown).
func proto_type() -> String:
	var proto: ProtoDB.EntityProto = protos.entities_by_name.get(proto_name) if protos != null else null
	return proto.type if proto != null else ""


## On its own (no inventory half) the screen is a whole frame with its own title.
func set_alone(alone: bool) -> void:
	theme_type_variation = "FFrame" if alone else "FFrameRight"
	_title.visible = alone


## Closes the screen and tells the mod.
func close() -> void:
	if unit != 0:
		Bridge.send({"t": "close"})
	close_local()


## Hides the screen without a message (the mod closed it, or the session restarted).
func close_local() -> void:
	unit = 0
	_set_open(false)


## Takes up to n of an item out of the machine (inventory `role`, or anywhere if "").
func take(role: String, item: String, n: int) -> void:
	var cmd := {"t": "take", "u": unit, "item": item, "n": n}
	if role != "":
		cmd["inv"] = role
	Bridge.send(cmd)


## Puts up to n of an item from the character's inventory into the machine.
func put(item: String, n: int) -> void:
	if is_open() and n > 0:
		Bridge.send({"t": "put", "u": unit, "item": item, "n": n})


## Opened from the remote view out of reach (`gui.far`): items can't move, modules are asked for.
func far() -> bool:
	return int(_last.get("far", 0)) == 1


## Each module slot's requested module ("" for none; `gui.mrq`), for the faint icons Factorio draws.
func module_requests() -> Array:
	var out: Array = []
	for v in (_last.get("mrq", []) if _last.get("mrq") is Array else []):
		out.append(str(v))
	return out


## The machine's inventories come slot by slot (`gui.slots`).
func knows_slots(role: String) -> bool:
	var slots = _last.get("slots")
	return slots is Dictionary and slots.get(role) is Array


## The stack in slot `index` (1-based) of the machine's `role`, as {"item", "count"} or {}.
func stack_at(role: String, index: int) -> Dictionary:
	var list := _slot_list(role)
	return list[index - 1] if index >= 1 and index <= list.size() else {}


## The status line's text and dot colour for an entity status name ("" when the mod sent none).
static func status_text(status: String) -> String:
	if status == "":
		return ""
	if STATUS_TEXT.has(status):
		return STATUS_TEXT[status]
	return status.substr(0, 1).to_upper() + status.substr(1).replace("_", " ")


static func status_color(status: String) -> String:
	if GREEN_STATUS.has(status):
		return "green"
	if RED_STATUS.has(status):
		return "red"
	return "yellow"


func set_hand_slot(slot: Array) -> void:
	if slot != hand_slot:
		hand_slot = slot.duplicate()
		_rebuild_now()


func handle(msg: Dictionary) -> void:
	if unit == 0 or int(msg.get("u", 0)) != unit:
		return  # a late message for a screen that has been closed or replaced
	if msg.get("closed", false):
		close_local()
		return
	_last_msec = Time.get_ticks_msec()
	_last = msg
	var kind := str(msg.get("kind", "other"))
	var proto: ProtoDB.EntityProto = protos.entity(int(msg.get("p", 0))) if protos != null else null
	_title.text = Kit.entity_name(proto.name) if proto != null else "Machine"
	if choosing_recipe():
		_title.text = "Select a recipe for assembling"
	_title.set_meta("proto", proto.name if proto != null else "")
	proto_name = proto.name if proto != null else ""
	var rl = msg.get("rl")
	if rl is Array:
		_recipes = rl.duplicate()
		_recipe_groups = (msg.get("rg") as Array).duplicate() if msg.get("rg") is Array else []
	var inv = msg.get("inv")
	if not (inv is Dictionary):
		inv = {}
	var sig := "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [kind, str(msg.get("recipe", "")), JSON.stringify(inv),
		JSON.stringify(msg.get("slots", {})), _picking, JSON.stringify(_recipes), str(msg.get("status", "")),
		JSON.stringify(msg.get("fb", [])), str(msg.get("pw", -1)), JSON.stringify(hand_slot), _setting_bar, _panel_sig(msg) + _production_sig(msg) + LogicWindows.sig_extra(self, msg)]
	# Not while a text field of the screen is being typed in: rebuilding would take it away.
	if sig != _sig and not _editing():
		_sig = sig
		_build(kind, str(msg.get("recipe", "")), inv)
	if _progress != null:
		ProductionPanels.set_percent(_progress, int(msg.get(_progress_key, 0)) / 1000.0)
	SpacePanels.refresh(self, msg)
	LogicWindows.refresh(self, msg)
	_follow_train(msg)
	_set_open(true)
	circuit_dock.refresh(msg, LogicWindows.entity_type(self))
	# The chooser and the machine are different windows (alone or beside the inventory).
	var alone := not shows_inventory()
	if alone != _was_alone:
		_was_alone = alone
		opened_changed.emit(true)


## The train window's camera keeps above the train as it moves (entity_panels.gd's _train_camera).
func _follow_train(msg: Dictionary) -> void:
	var cam = get_meta("train_camera") if has_meta("train_camera") else null
	var tr = msg.get("tr")
	if is_instance_valid(cam) and cam is Camera3D and tr is Dictionary and tr.get("pos") is Array and (tr["pos"] as Array).size() >= 2:
		EntityPanels.aim_train_camera(cam, Vector2(int(tr["pos"][0]), int(tr["pos"][1])) / 256.0)


func _process(_delta: float) -> void:
	if unit != 0 and Time.get_ticks_msec() - _last_msec > STALE_MSEC:
		close_local()


## What entity_panels.gd draws from, for the rebuild check: the settings, without what changes all
## the time (a moving train's speed and state).
func _panel_sig(msg: Dictionary) -> String:
	var tr = msg.get("tr")
	var train_part = [tr.get("manual"), tr.get("sched"), tr.get("cargo"), tr.get("fuel"), tr.get("fluids"), tr.get("stops")] if tr is Dictionary else null
	if tr is Dictionary:
		train_part.append(tr.get("name"))
	var ins = msg.get("ins")
	if ins is Dictionary and ins.has("h"):
		ins = ins.duplicate()
		ins.erase("h")  # the hand: logic_windows.gd's refresh() shows it without a rebuild
	var hub = msg.get("hub")
	var hub_part = [hub.get("n"), hub.get("pa"), hub.get("prov"), hub.get("sched"), hub.get("sec"), hub.get("dest")] if hub is Dictionary else null
	return JSON.stringify([ins, msg.get("ao"), msg.get("desc"), msg.get("guns"), msg.get("spl"), msg.get("sw"), msg.get("rk"), msg.get("dp"), msg.get("bar"),
		msg.get("cb"), msg.get("stop"), msg.get("lg"), msg.get("sig"), train_part, msg.get("cc"), msg.get("col"), msg.get("spk"),
		msg.get("pf"), msg.get("tgt"), hub_part, msg.get("pad"), msg.get("bay"), msg.get("eff"), msg.get("rq"), msg.get("ql")])


## machine_info.lua's fields that change the layout (the progress bar updates in place).
func _production_sig(msg: Dictionary) -> String:
	return JSON.stringify([msg.get("rd"), msg.get("rp"), msg.get("fixed"), msg.get("mt"), msg.get("lc"), msg.get("li"), msg.get("ld"),
		int(msg.get("pb", 0)) > 0, roundi(int(msg.get("bn", 0)) / 50.0), roundi(int(msg.get("bp", 0)) / 50.0),
		roundi(int(msg.get("tc", 0)) / 100.0), _pick_group, _pick_quality, _recipe_groups.size()])


func _editing() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return focus is LineEdit and is_ancestor_of(focus)


func _set_open(open: bool) -> void:
	if visible != open:
		visible = open
		opened_changed.emit(open)
	if not open:
		circuit_dock.refresh({}, "")


## The screen is rebuilt whenever what it shows changes (a hub's inventory every second on a busy
## platform), and its scroll boxes came back at the top: the hub's schedule jumped up while being
## scrolled. Their places are kept across rebuilds of the same entity's screen.
func _build(kind: String, recipe: String, inv: Dictionary) -> void:
	var kept: Array = []
	if _scroll_key == "%d|%s" % [unit, kind]:
		for sc in _columns.find_children("*", "ScrollContainer", true, false):
			kept.append((sc as ScrollContainer).scroll_vertical)
	_scroll_key = "%d|%s" % [unit, kind]
	_build_screen(kind, recipe, inv)
	if kept.any(func(v: int) -> bool: return v > 0):
		_keep_scrolls(_columns.find_children("*", "ScrollContainer", true, false), kept)


## Puts the new scroll boxes back where the old ones were, once their contents are laid out (the
## scroll bar's range is known only then: set earlier, the value is clamped to 0).
func _keep_scrolls(scrolls: Array, kept: Array) -> void:
	if not is_inside_tree():
		return
	var applied: Array = []
	for i in mini(scrolls.size(), kept.size()):
		var sc: ScrollContainer = scrolls[i]
		var v: int = kept[i]
		if v <= 0:
			continue
		var bar := sc.get_v_scroll_bar()
		var put := func() -> void:
			if is_instance_valid(sc):
				sc.scroll_vertical = v
		bar.changed.connect(put)
		put.call()
		applied.append([bar, put])
	# Only while the rebuild settles: afterwards the player's own scrolling stays.
	for i in 2:
		await get_tree().process_frame
	for a in applied:
		var bar: ScrollBar = a[0]
		if is_instance_valid(bar) and bar.changed.is_connected(a[1]):
			bar.changed.disconnect(a[1])


func _build_screen(kind: String, recipe: String, inv: Dictionary) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		if child != _preview:  # the preview's 3D view is kept across rebuilds of the same entity
			child.queue_free()
	_progress = null
	_progress_key = "pr"
	for c in _columns.get_children():
		if c.has_meta("extra_column"):
			_columns.remove_child(c)
			c.queue_free()
	if choosing_recipe():  # the chooser has no status line
		_body.add_child(_recipe_picker(recipe))
		return
	_body.add_child(_status_row(kind, recipe))
	var ptype := proto_type()
	# Factorio's entity preview under the status (a train's window has its camera instead).
	if kind != "train" and proto_name != "":
		if _preview == null or _preview_proto != proto_name:
			if _preview != null:
				_preview.queue_free()
			var proto: ProtoDB.EntityProto = protos.entities_by_name.get(proto_name)
			_preview = ProductionPanels.preview(proto_name, ptype, proto.size() if proto != null else Vector2.ONE)
			_preview_proto = proto_name
		if _preview.get_parent() != null:  # a window that wrapped it last time (the train stop's)
			_preview.get_parent().remove_child(_preview)
		_body.add_child(_preview)
	var own := LogicWindows.build(self, kind, inv, _body)
	match "" if own else kind:
		"":
			pass
		"container":
			_build_chest(inv)
		"crafter":
			var gear := func() -> void:
				_picking = true
				_rebuild_now()
			_progress = ProductionPanels.crafter(self, _body, recipe, gear)
		"furnace":
			_progress = ProductionPanels.furnace(self, _body)
		"lab":
			ProductionPanels.lab(self, _body)
		"silo":  # Factorio's two columns: the rocket parts' production and progress; the rocket
			_progress = ProductionPanels.crafter(self, _body, str(_last.get("recipe", "")), Callable())
			if _last.get("rk") is Dictionary:
				_body.add_child(ProductionPanels.rocket_progress(_last["rk"]))
			var col := _column()
			if inv.has("rocket") or knows_slots("rocket"):
				col.add_child(Kit.label(ROLE_TITLES["rocket"], "FHeading"))
				col.add_child(ProductionPanels.bare_row(self, "rocket"))
			if _last.get("rw") is Array:
				col.add_child(ProductionPanels.rocket_capacity(_last["rw"]))
			if _last.get("rk") is Dictionary:
				col.add_child(SpacePanels.silo(self, _last["rk"]))
			_requests_column(col, "Logistic requests")
		"pad":  # the inventory with its X; then the requests and trash slots beside it
			_body.add_child(ProductionPanels.chest_grid(self, "chest", _bar_button() if _last.has("bar") else null, SCROLL_ROWS))
			var col := _column()
			_requests_column(col, "")
			if _last.get("pad") is Dictionary:
				col.add_child(SpacePanels.pad_circuit(self, _last["pad"]))
		"hub":  # Factorio's three columns: inventory; requests; the platform and its schedule
			if _last.get("hub") is Dictionary:
				_body.add_child(SpacePanels.provide_box(self, _last["hub"]))
			_body.add_child(ProductionPanels.chest_grid(self, "chest", _bar_button() if _last.has("bar") else null, SCROLL_ROWS))
			var col := _column()
			var hub_sec: Array = (_last["hub"].get("sec") as Array).duplicate(true) if _last.get("hub") is Dictionary and _last["hub"].get("sec") is Array else []
			col.add_child(SpacePanels.sections(self, hub_sec, (_last["hub"].get("dest", []) as Array) if _last.get("hub") is Dictionary else [], true))
			if knows_slots("trash"):
				col.add_child(ProductionPanels.trash_slots(self))
			if _last.get("hub") is Dictionary:
				_column().add_child(SpacePanels.hub_platform(self, _last["hub"]))
		"collector":
			if _last.get("col") is Dictionary:
				_body.add_child(SpacePanels.collector(self, _last["col"]))
			_body.add_child(ProductionPanels.chest_grid(self, "output", null))
		_:
			if ptype in ProductionPanels.DRILL_TYPES:
				_progress_key = "mp"
				_progress = ProductionPanels.drill(self, _body)
			elif ptype in ProductionPanels.BURNER_TYPES:
				ProductionPanels.burner(self, _body)
			elif ptype == "beacon":
				_body.add_child(ProductionPanels.bare_row(self, "modules"))
			elif ptype == "agricultural-tower":
				ProductionPanels.agricultural_tower(self, _body)
			else:
				for role in OTHER_ROLES:
					if inv.has(role) or knows_slots(role):
						var grid := _labelled_grid(ROLE_TITLES[role], role, inv, Kit.COLUMNS)
						if kind in SCROLLED_KINDS and _slot_list(role).size() > Kit.COLUMNS * SCROLL_ROWS:
							grid = _scrolled(grid)
						_body.add_child(grid)
	_add_panels(kind, own)
	if not (ptype in ProductionPanels.NO_FLUID_TYPES or kind in ["crafter", "furnace", "lab", "silo"] or LogicWindows.hides_fluids(self)):
		var fluids := _fluid_boxes()
		if fluids != null:
			_body.add_child(fluids)


## A chest: its grid with the X, then a logistic chest's filters, or its requests and trash slots.
func _build_chest(_inv: Dictionary) -> void:
	_body.add_child(ProductionPanels.chest_grid(self, "chest", _bar_button() if _last.has("bar") else null))
	var lg = _last.get("lg")
	if not (lg is Dictionary):
		return
	var mode := str(lg.get("mode", ""))
	if mode == "storage":
		_body.add_child(ProductionPanels.line())
		var set_filter := func(_t: String, item: String) -> void: Bridge.send({"t": "set_storage_filter", "u": unit, "item": item})
		var choose := func() -> Control: return EntityPanels.choose_slot(self, str(lg.get("filter", "")), ["item"], set_filter, "Anything")
		_body.add_child(ProductionPanels.storage_filter(self, lg, choose))
	elif mode == "requester" or mode == "buffer":
		_body.add_child(ProductionPanels.line())
		var lc = _last.get("lc")
		var secs: Control
		if lc is Dictionary:
			secs = SpacePanels.sections(self, (lc.get("sec") as Array).duplicate(true) if lc.get("sec") is Array else [], [], false)
			# The sections' own heading is the chest's "Logistic requests" here.
			var heading := secs.get_child(0)
			secs.remove_child(heading)
			heading.queue_free()
		else:  # an older mod: section 1 only, as min / max requests
			var list: Array = (lg.get("requests") as Array).duplicate(true) if lg.get("requests") is Array else []
			var set_requests := func(l: Array) -> void: Bridge.send({"t": "set_requests", "u": unit, "l": l})
			secs = EntityPanels.request_grid(self, list, set_requests)
		_body.add_child(ProductionPanels.chest_requests(self, lg, lc if lc is Dictionary else {}, secs))
		if knows_slots("trash") or (_last.get("inv", {}) as Dictionary).has("trash"):
			_body.add_child(ProductionPanels.trash_slots(self))


## Another column of the window, right of the first (a shallow frame like it), for the silo's,
## landing pad's and hub's windows. Returned empty; they go when the window is rebuilt.
func _column() -> VBoxContainer:
	var shallow := Kit.panel("FShallowFrame")
	shallow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shallow.custom_minimum_size.x = Kit.px(Kit.SLOT * Kit.COLUMNS + 24)
	shallow.set_meta("extra_column", true)
	var pad := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(12))
	pad.add_theme_constant_override("margin_top", Kit.px(8))
	shallow.add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Kit.px(8))
	pad.add_child(col)
	_columns.add_child(shallow)
	return col


## A labelled grid whose slots scroll after SCROLL_ROWS rows (the heading stays).
func _scrolled(labelled: Control) -> Control:
	var frame: Control = labelled.get_child(1)
	labelled.remove_child(frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.custom_minimum_size = Vector2(0, Kit.px(Kit.SLOT * SCROLL_ROWS + 8))
	scroll.add_child(frame)
	labelled.add_child(scroll)
	return labelled


## What the kinds logic_windows.gd doesn't draw add, then logistics. The circuit and logistic
## connection and the network's signals are in the docked circuit window (circuit_window.gd).
func _add_panels(kind: String, own := false) -> void:
	match "" if own else kind:
		"bay":
			if _last.get("bay") is Dictionary:
				_body.add_child(SpacePanels.bay(_last["bay"]))
	if _last.get("eff") is Dictionary:
		_body.add_child(SpacePanels.effects(_last["eff"]))
	if _last.get("lg") is Dictionary and kind != "container":
		_body.add_child(EntityPanels.logistics(self, _last["lg"]))


## A landing pad's or silo's "Trash unrequested" header with the network dot, its request sections
## (`gui.lc`, else the pad's own `sec`) and its trash slots.
func _requests_column(col: VBoxContainer, heading: String) -> void:
	var lc: Dictionary = _last.get("lc") if _last.get("lc") is Dictionary else {}
	var secs: Array = []
	if lc.get("sec") is Array:
		secs = (lc["sec"] as Array).duplicate(true)
	elif _last.get("pad") is Dictionary and _last["pad"].get("sec") is Array:
		secs = (_last["pad"]["sec"] as Array).duplicate(true)
	if heading != "":
		col.add_child(Kit.label(heading, "FHeading"))
	var tu := func(on: bool) -> void: Bridge.send({"t": "set_chest_logistics", "u": unit, "tu": 1 if on else 0})
	var head := HBoxContainer.new()
	var box := MenuKit.checkbox("Trash unrequested", int(lc.get("tu", 0)) == 1)
	box.toggled.connect(tu)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(box)
	col.add_child(head)
	var sections := SpacePanels.sections(self, secs, [], false)
	var title := sections.get_child(0)  # its own "Requests" heading: the column has its header
	sections.remove_child(title)
	title.queue_free()
	col.add_child(sections)
	if knows_slots("trash") or (_last.get("inv", {}) as Dictionary).has("trash"):
		col.add_child(ProductionPanels.trash_slots(self))


## Factorio's red X inside a chest's grid, at the limit: click it, then a slot, to move the limit
## there; right click: no limit.
func _bar_button() -> Slot:
	var b := Slot.new()
	b.name = "LimitButton"
	b.theme_type_variation = "FRedSlotButton"
	b.empty_icon = GuiAssets.core_sprite("icons/close.png")
	b.toggle_mode = true
	b.button_pressed = _setting_bar
	var bar := int(_last.get("bar", 0))
	var size := _slot_list(_bar_role()).size()
	b.set_tip("Limit", [["Limited to %d slots" % bar if bar < size else "No limit"],
		["Click, then click a slot: machines use only the slots before it", "", Kit.DISABLED_TEXT],
		["Right click: no limit", "", Kit.DISABLED_TEXT]])
	var on_click := func(button_index: int, _shift: bool) -> void:
		if button_index == MOUSE_BUTTON_RIGHT:
			_setting_bar = false
			if model != null:
				model.set_bar(unit, _slot_list(_bar_role()).size())
		elif button_index == MOUSE_BUTTON_LEFT:
			_setting_bar = not _setting_bar
		_rebuild_now()
	b.clicked.connect(on_click)
	return b


## The inventory with the limit bar: a chest's, or a cargo wagon's.
func _bar_role() -> String:
	return "cargo" if knows_slots("cargo") or (_last.get("inv") is Dictionary and _last["inv"].has("cargo")) else "chest"


## Factorio's entity status: the dot and the status, and the electric buffer for electric machines.
func _status_row(kind: String, recipe: String) -> Control:
	var status := str(_last.get("status", ""))
	if status == "" and kind == "crafter":
		status = "working" if recipe != "" else "no_recipe"
	if status == "" and kind == "container":
		status = "normal"  # a chest has no status; Factorio says "Normal"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	if status != "":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(6))
		var dot_tex := GuiAssets.status_dot(status_color(status))
		if dot_tex != null:
			var dot := TextureRect.new()
			dot.texture = dot_tex
			dot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			dot.custom_minimum_size = Kit.pxv(16, 16)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.texture_filter = Kit.ICON_FILTER
			row.add_child(dot)
		else:
			var flat := ColorRect.new()
			flat.custom_minimum_size = Kit.pxv(10, 10)
			flat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			flat.color = {"green": Color(0.2, 0.85, 0.2), "red": Color(0.9, 0.2, 0.2)}.get(status_color(status), Color(0.95, 0.75, 0.1))
			row.add_child(flat)
		row.add_child(Kit.label(status_text(status)))
		box.add_child(row)
	# Factorio's production windows have no energy bar or temperature line here: the temperature is
	# production_panels.gd's red bar, a lab's research its research box.
	return box


## The machine's fluid boxes (`gui.fb`), like Factorio's fluid box widgets: the fluid's icon and a
## bar in its colour with the amount, per box. Null when it has none.
func _fluid_boxes() -> Control:
	var fb = _last.get("fb")
	if not (fb is Array) or (fb as Array).is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	box.add_child(Kit.label("Fluids", "FHeading"))
	for entry in fb:
		if not (entry is Array) or entry.size() < 3:
			continue
		var fluid := str(entry[0])
		var amount := float(entry[1])
		var capacity := maxf(1.0, float(entry[2]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", Kit.px(8))
		var s := Slot.new()
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		if fluid != "":
			s.set_stack(fluid, -1)
		var lines: Array = [["%s / %s" % [_amount_text(amount), _amount_text(capacity)]]]
		if entry.size() > 3 and fluid != "":
			lines.append(["Temperature: %d °C" % int(entry[3])])
		s.set_tip(Kit.pretty(fluid) if fluid != "" else "Empty fluid box", lines)
		row.add_child(s)
		var bar := Kit.progress_bar(_fluid_color(fluid))
		bar.max_value = capacity
		bar.value = amount
		bar.custom_minimum_size = Kit.pxv(200, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		var label := Kit.label(("%s / %s" % [_amount_text(amount), _amount_text(capacity)]) if fluid != "" else "Empty")
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		box.add_child(row)
	return box


func _fluid_color(fluid: String) -> Color:
	if protos != null and protos.fluid_colors.has(fluid):
		var c: Color = protos.fluid_colors[fluid]
		return c.lightened(0.15)
	return Color(0.3, 0.55, 0.9)


static func _amount_text(v: float) -> String:
	if v >= 1000.0:
		return ("%.1fk" % (v / 1000.0)).replace(".0k", "k")
	return str(roundi(v))


func _rebuild_now() -> void:
	_sig = ""
	if not _last.is_empty():
		handle(_last)


func _labelled_grid(title: String, role: String, inv: Dictionary, columns: int) -> Control:
	var box := VBoxContainer.new()
	box.add_child(Kit.label(title, "FHeading"))
	box.add_child(_grid_frame(role, inv, columns))
	return box


## The slots of one inventory: [{"item", "count"} or {}] from `gui.slots`, or the totals from `inv`.
func _slot_list(role: String) -> Array:
	var out: Array = []
	if knows_slots(role):
		for entry in _last["slots"][role]:
			if entry is Array and entry.size() >= 2 and str(entry[0]) != "" and int(entry[1]) > 0:
				var d := {"item": str(entry[0]), "count": int(entry[1])}
				if entry.size() >= 3:
					d["quality"] = str(entry[2])
				if entry.size() >= 4:
					d["freshness"] = int(entry[3]) / 1000.0
				out.append(d)
			else:
				out.append({})
		return out
	var inv = _last.get("inv")
	if inv is Dictionary and inv.get(role) is Array:
		for entry in inv[role]:
			if entry is Array and entry.size() >= 2:
				out.append({"item": str(entry[0]), "count": int(entry[1])})
	return out


## A deep frame holding one inventory as slots: every slot when the mod sends them, else its
## stacks padded with empty slots to the known size or the end of the row.
func _grid_frame(role: String, _inv: Dictionary, columns: int, min_slots := 0) -> Control:
	var frame := Kit.panel("FDeepFrame")
	frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var stacks := _slot_list(role)
	var exact := knows_slots(role)
	var cols := mini(columns, maxi(1, stacks.size())) if exact or columns < Kit.COLUMNS else columns
	var grid := Kit.slot_grid(cols)
	frame.add_child(grid)
	for i in stacks.size():
		grid.add_child(_stack_slot(role, i + 1 if exact else 0, stacks[i]))
	var cells := stacks.size()
	var target := cells
	if not exact:
		target = maxi(min_slots, cells) if min_slots > 0 else maxi(1, ceili(cells / float(cols)) * cols)
	while cells < target:
		grid.add_child(_stack_slot(role, 0, {}))
		cells += 1
	return frame


func _stack_slot(role: String, index: int, stack: Dictionary) -> Slot:
	var s := Slot.new()
	s.slot_role = role if index > 0 else ""
	s.slot_index = index
	s.set_extra(stack)
	if role == _bar_role() and _last.has("bar") and index > int(_last["bar"]):
		s.blocked = true
	if stack.is_empty():
		if role == "fuel":
			s.empty_icon = GuiAssets.core_sprite("icons/mip/empty-fuel-slot.png")
		elif role == "modules":
			s.empty_icon = GuiAssets.core_sprite("icons/mip/empty-module-slot.png")
	else:
		var item: String = stack["item"]
		var count: int = stack["count"]
		s.set_stack(item, count)
		s.set_hand(hand_slot.size() >= 2 and hand_slot[0] == role and int(hand_slot[1]) == index and index > 0, Slot.hand_left_of(hand_slot, stack))
		s.set_tip(Kit.pretty(item), Slot.extra_lines(stack) + [["%d in the %s" % [count, str(ROLE_TITLES.get(role, role)).to_lower()]],
			["Click: pick up · Right click: half", "", Kit.DISABLED_TEXT],
			["Shift click: into your inventory", "", Kit.DISABLED_TEXT]])
	var on_click := func(button_index: int, shift: bool) -> void:
		if _setting_bar and role == _bar_role() and index > 0 and button_index == MOUSE_BUTTON_LEFT:
			_setting_bar = false
			if model != null:
				model.set_bar(unit, index - 1)
			_rebuild_now()
			return
		slot_clicked.emit(role, index, s.item, s.count, button_index, shift, s.ctrl)
	s.clicked.connect(on_click)
	return s
## Factorio's recipe chooser (production_panels.gd): picking a recipe sets it with the chosen
## ingredient quality and goes back to the machine; the tick does too.
func _recipe_picker(current: String) -> Control:
	var on_group := func(g: String) -> void:
		_pick_group = g
		_rebuild_now()
	var pick := func(name: String) -> void:
		_picking = false
		var cmd := {"t": "set_recipe", "u": unit, "recipe": name}
		if _pick_quality != "normal":
			cmd["q"] = _pick_quality
		Bridge.send(cmd)
		_rebuild_now()
	var on_quality := func(q: String) -> void:
		_pick_quality = q
		_rebuild_now()
	var done := func() -> void:
		_picking = false
		_rebuild_now()
	return ProductionPanels.recipe_chooser(self, _recipes, _recipe_groups, current, _pick_group, on_group, pick,
		_pick_quality, on_quality, done)
