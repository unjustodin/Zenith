extends VBoxContainer
## Factorio 2.1's "Circuit connection" and "Logistic connection" windows: frames docked to the
## right of an entity window, opened by the circuit network and logistic network buttons in its
## title bar (lit orange while open). The circuit one has a dark strip per side, "Input" or
## "Output" with the wires that side is connected to (R / G), and under it the settings of
## circuit_panel.gd's SPECS (or a train stop's own), then the network's signals. Which windows are
## open is remembered per entity type; a wired entity opens with its circuit window.
##
## machine_screen.gd makes one, puts its buttons in the title bar (add_buttons) and calls
## refresh() with each `gui` message.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const LogicKit := preload("res://scripts/ui/factorio/logic_kit.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")
const CircuitPanel := preload("res://scripts/ui/factorio/circuit_panel.gd")

## entity type -> {"circuit": bool, "logistic": bool}, as the player last left them.
static var remembered := {}

var screen = null
var circuit_button: Button = null
var logistic_button: Button = null
var _sig := ""
var _type := ""
var _open := {"circuit": false, "logistic": false}
var _has := {"circuit": false, "logistic": false}
var _circuit_frame := PanelContainer.new()
var _logistic_frame := PanelContainer.new()


func _ready() -> void:
	theme = EntityPanels.theme()
	add_theme_constant_override("separation", Kit.px(4))
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for f in [_circuit_frame, _logistic_frame]:
		f.theme_type_variation = "FFrame"
		f.custom_minimum_size.x = Kit.px(200)
		f.visible = false
		add_child(f)
	_circuit_frame.name = "CircuitConnection"
	_logistic_frame.name = "LogisticConnection"
	visible = false


## The two title bar buttons, put before the close button.
func add_buttons(bar: HBoxContainer) -> void:
	circuit_button = LogicKit.frame_button("icons/mip/circuit-connection.png", "Circuit network", false)
	circuit_button.name = "CircuitButton"
	logistic_button = LogicKit.frame_button("icons/mip/logistic-connection.png", "Logistic network", false)
	logistic_button.name = "LogisticButton"
	for b in [circuit_button, logistic_button]:
		b.visible = false
		bar.add_child(b)
		bar.move_child(b, bar.get_child_count() - 2)
	circuit_button.toggled.connect(func(on: bool) -> void: _toggle("circuit", on))
	logistic_button.toggled.connect(func(on: bool) -> void: _toggle("logistic", on))


func is_open(which: String) -> bool:
	return bool(_open.get(which, false)) and bool(_has.get(which, false))


func _toggle(which: String, on: bool) -> void:
	_open[which] = on
	var r: Dictionary = remembered.get(_type, {})
	r[which] = on
	remembered[_type] = r
	_show()


## Called with each `gui` message of the open entity (and {} when it closes).
func refresh(msg: Dictionary, entity_type: String) -> void:
	if msg.is_empty() or screen == null or not screen.is_open():
		visible = false
		_sig = ""
		for b in [circuit_button, logistic_button]:
			if b != null:
				b.visible = false
		return
	var cc = msg.get("cc")
	var stop = msg.get("stop")
	var stop_cb = stop.get("cb") if stop is Dictionary else null
	var wired := (cc is Dictionary and int(cc.get("w", 0)) == 1) or (stop_cb is Dictionary and int(stop_cb.get("wired", 0)) == 1)
	# Until the player opens or closes it for this type, the circuit window follows the wires.
	_type = entity_type
	var r: Dictionary = remembered.get(_type, {})
	_open["circuit"] = bool(r.get("circuit", wired))
	_open["logistic"] = bool(r.get("logistic", false))
	var sig := JSON.stringify([cc, stop_cb, msg.get("sig")])
	if sig != _sig and not _editing():
		_sig = sig
		var sections: Array = []
		if cc is Dictionary:
			sections = CircuitPanel.sections(screen, cc)
		elif stop_cb is Dictionary:
			sections = CircuitPanel.stop_sections(screen, stop_cb)
		var logistic: Control = CircuitPanel.logistic_row(screen, cc) if cc is Dictionary else null
		_has["circuit"] = not sections.is_empty()
		_has["logistic"] = logistic != null
		_fill(_circuit_frame, "Circuit connection", sections, cc if cc is Dictionary else {}, msg.get("sig"), wired)
		_fill_logistic(logistic, cc if cc is Dictionary else {})
	_show()


func _editing() -> bool:
	var focus: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return focus is LineEdit and is_ancestor_of(focus)


func _show() -> void:
	for pair in [["circuit", circuit_button, _circuit_frame], ["logistic", logistic_button, _logistic_frame]]:
		var which: String = pair[0]
		var b: Button = pair[1]
		var f: PanelContainer = pair[2]
		if b != null:
			b.visible = bool(_has[which])
			b.set_pressed_no_signal(is_open(which))
		f.visible = is_open(which)
	visible = screen != null and screen.is_open() and (_circuit_frame.visible or _logistic_frame.visible)


func _clear(frame: PanelContainer) -> VBoxContainer:
	for c in frame.get_children():
		frame.remove_child(c)
		c.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(4))
	frame.add_child(box)
	box.add_child(Kit.title_bar("", false))
	return box


func _fill(frame: PanelContainer, title: String, sections: Array, cc: Dictionary, sig, wired: bool) -> void:
	var box := _clear(frame)
	(box.get_child(0).get_child(0) as Label).text = title
	var nets: Dictionary = cc.get("nets") if cc.get("nets") is Dictionary else {}
	if sig is Dictionary:
		nets = {"r": int(sig.get("ri", nets.get("r", 0))), "g": int(sig.get("gi", nets.get("g", 0)))}
	for s in sections:
		var shallow := Kit.panel("FShallowFrame")
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", Kit.px(4))
		shallow.add_child(col)
		var sh := LogicKit.subheader()
		var head: HBoxContainer = sh[1]
		head.add_child(Kit.label(str(s[0]), "FHeading"))
		# Which wires this side is on: Factorio's ticked R / G.
		var on := {"red": int(nets.get("r", 0)) > 0, "green": int(nets.get("g", 0)) > 0}
		LogicKit.push_right(head, LogicKit.wire_checks(on, Callable(), false))
		col.add_child(sh[0])
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", Kit.px(6))
		for r in s[1]:
			rows.add_child(r)
		col.add_child(LogicKit.padded(rows, 12, 6))
		box.add_child(shallow)
	if sig is Dictionary or wired:
		var shallow := Kit.panel("FShallowFrame")
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", Kit.px(4))
		shallow.add_child(LogicKit.padded(col, 8, 6))
		if sig is Dictionary:
			col.add_child(CircuitPanel.signals(sig))
		else:
			col.add_child(CircuitPanel.network_line(nets))
		box.add_child(shallow)


func _fill_logistic(row: Control, _cc: Dictionary) -> void:
	var box := _clear(_logistic_frame)
	(box.get_child(0).get_child(0) as Label).text = "Logistic connection"
	if row == null:
		return
	var shallow := Kit.panel("FShallowFrame")
	shallow.add_child(LogicKit.padded(row, 12, 8))
	box.add_child(shallow)
