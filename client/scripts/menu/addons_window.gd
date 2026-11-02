extends PanelContainer
## The Add-ons menu (main menu, the in-game Esc menu, Settings): every Zenith add-on found
## (scripts/addons/addon_host.gd) in a list on the left, each with its version, whether it's on and
## why it couldn't load; clicking one opens its page on the right: what it is, its switch, its
## settings (declared with api.settings, add-on API 1.1, addon_settings.gd), the options it builds
## itself (api.ui.set_options) and its keys, rebound as in Settings → Controls (click, press the
## key; right click clears; Esc cancels). Controls are named for tests: "addon-item-<id>",
## "addon-switch-<id>", "addon-setting-<id>-<setting>", "addon-key-<action>-<slot>".

signal closed

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Settings := preload("res://scripts/menu/settings.gd")
const ControlsInfo := preload("res://scripts/menu/controls_info.gd")
const Sfx := preload("res://scripts/fx/sfx.gd")

## addon_host.gd (main.addons).
var addons = null
## The add-on whose page opens first ("" the first in the list).
var selected := ""

var _list: VBoxContainer
var _page: VBoxContainer
var _scroll: ScrollContainer
var _capturing := ""  # "<action>/<slot>" waiting for a key


func _ready() -> void:
	theme_type_variation = "FFrame"
	name = "AddonsWindow"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	add_child(box)
	var bar := Kit.title_bar("Add-ons", true)
	box.add_child(bar)
	(bar.get_child(bar.get_child_count() - 1) as Button).pressed.connect(_close)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", Kit.px(8))
	box.add_child(body)
	var deep: Array = Kit.deep_scroll(Kit.pxv(250, 470))
	body.add_child(deep[0])
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.add_theme_constant_override("separation", Kit.px(2))
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deep[1].add_child(_list)
	var pane := Kit.panel("FShallowFrame")
	pane.custom_minimum_size = Kit.pxv(640, 470)
	body.add_child(pane)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_NONE
	pane.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(12))
	_scroll.add_child(pad)
	_page = VBoxContainer.new()
	_page.name = "Page"
	_page.add_theme_constant_override("separation", Kit.px(8))
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_page)
	var row: Array = MenuKit.dialog_buttons("Back", "")
	box.add_child(row[0])
	(row[1] as Button).pressed.connect(func() -> void:
		Sfx.play_ui("gui-back")
		_close())
	if addons != null:
		addons.addons_changed.connect(_refresh)
		if selected == "" and not addons.addons.is_empty():
			selected = str(addons.addons[0]["id"])
	_refresh()


func _exit_tree() -> void:
	if addons != null and addons.addons_changed.is_connected(_refresh):
		addons.addons_changed.disconnect(_refresh)


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.physical_keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return  # a modifier on its own: wait for the key it goes with
	var target := _capturing
	_capturing = ""
	if key.physical_keycode != KEY_ESCAPE:
		capture(target, Settings.event_code(key))
	_show_page()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	_capturing = ""
	closed.emit()


## Binds "<action>/<slot>" to a key code with modifiers (what a key press while capturing does).
func capture(target: String, code: int) -> void:
	Settings.bind_slot(target.get_slice("/", 0), int(target.get_slice("/", 1)), code)
	Sfx.play_ui("gui-click")


## Opens an add-on's page.
func select(id: String) -> void:
	selected = id
	_capturing = ""
	_refresh()


func _refresh() -> void:
	_fill_list()
	_show_page()


func _fill_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var found: Array = addons.addons if addons != null else []
	if found.is_empty():
		var n := MenuKit.paragraph("None installed.", 220)
		n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
		_list.add_child(n)
		return
	for m: Dictionary in found:
		var id := str(m["id"])
		var b := Button.new()
		b.name = "addon-item-" + id
		b.theme_type_variation = "FListItemSelected" if id == selected else "FListItem"
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Kit.pxv(230, 30)
		var state := "on" if m.has("object") else ("can't load" if _problem(m) != "" else "off")
		b.text = "%s  %s  (%s)" % [str(m["name"]), str(m["version"]), state]
		b.tooltip_text = str(m["description"]) + ("\nFrom a zip: " + str(m["zip"]) if m.has("zip") else "")
		if not (m.get("also", []) as Array).is_empty():
			b.tooltip_text += "\nAlso found: " + "; ".join(m["also"])
		if _problem(m) != "":
			b.add_theme_color_override("font_color", Kit.RED_TEXT)
		b.pressed.connect(func() -> void:
			Sfx.play_ui("gui-click")
			select(id))
		_list.add_child(b)


func _problem(m: Dictionary) -> String:
	return str(m.get("error", m["problem"]))


func _show_page() -> void:
	for c in _page.get_children():
		_page.remove_child(c)
		c.queue_free()
	var m: Dictionary = addons.find(selected) if addons != null and selected != "" else {}
	if m.is_empty():
		_page.add_child(_note("An add-on is a folder put in %s (or beside Zenith.exe in addons\\). docs/ADDONS.md says how to write one." % ProjectSettings.globalize_path("user://addons")))
		return
	var id := str(m["id"])
	_page.add_child(Kit.label(str(m["name"]), "FHeading"))
	var who := "Version %s" % str(m["version"])
	if str(m["author"]) != "":
		who += "  ·  by %s" % str(m["author"])
	_page.add_child(Kit.label(who))
	if str(m["description"]) != "":
		_page.add_child(MenuKit.paragraph(str(m["description"]), 600))
	if m.has("zip"):
		_page.add_child(_note("From %s (Zenith unpacks it into %s)" % [str(m["zip"]), ProjectSettings.globalize_path(str(m["dir"]))]))
	else:
		_page.add_child(_note(str(m["dir"])))
	for other in m.get("also", []):
		var n := _note("Also found: %s. This one is used." % str(other))
		n.name = "addon-also-" + id
		_page.add_child(n)
	var on := MenuKit.checkbox("On", m.has("object"))
	on.name = "addon-switch-" + id
	on.disabled = not bool(m["ok"]) or str(m["source"]) == "command line"
	if str(m["source"]) == "command line":
		on.tooltip_text = "Given with --addons: always on."
	on.toggled.connect(func(v: bool) -> void:
		Sfx.play_ui("gui-checkbox-click")
		addons.set_enabled(id, v))  # addons_changed redraws the page
	_page.add_child(on)
	var why := _problem(m)
	if why != "":
		var n := MenuKit.paragraph("Not loaded: " + why, 600)
		n.name = "addon-problem-" + id
		n.add_theme_color_override("font_color", Kit.RED_TEXT)
		_page.add_child(n)
	if not m.has("object"):
		_page.add_child(_note("Switch it on to see its settings and keys."))
		return
	var api = m["object"]
	_settings_rows(api)
	var builder: Callable = api.ui._options_builder()
	if builder.is_valid():
		_page.add_child(Kit.label("More options", "FHeading"))
		var holder := VBoxContainer.new()
		holder.name = "addon-options-" + id
		holder.add_theme_constant_override("separation", Kit.px(6))
		_page.add_child(holder)
		builder.call(holder)
	_key_rows(api)


# --- settings ---------------------------------------------------------------------------------

func _settings_rows(api) -> void:
	var defs: Array = api.settings.list()
	if defs.is_empty():
		return
	_page.add_child(Kit.label("Settings", "FHeading"))
	var grid: GridContainer = null
	var section := "\u0000"
	for def: Dictionary in defs:
		if str(def["section"]) != section:
			section = str(def["section"])
			if section != "":
				var h := Kit.label(section)
				h.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
				_page.add_child(h)
			grid = GridContainer.new()
			grid.columns = 3
			grid.add_theme_constant_override("h_separation", Kit.px(10))
			grid.add_theme_constant_override("v_separation", Kit.px(4))
			_page.add_child(grid)
		_setting_row(grid, api, def)
	var reset := MenuKit.button("Reset settings")
	reset.name = "addon-reset-" + str(api.id)
	reset.custom_minimum_size.x = Kit.px(160)
	reset.pressed.connect(func() -> void:
		Sfx.play_ui("gui-click")
		for def: Dictionary in defs:
			api.settings.reset(str(def["id"]))
		_show_page())
	_page.add_child(reset)


func _setting_row(grid: GridContainer, api, def: Dictionary) -> void:
	var sid := str(def["id"])
	var l := Kit.label(str(def["label"]))
	l.custom_minimum_size.x = Kit.px(230)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.tooltip_text = str(def["note"])
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)
	var control: Control
	var value = api.settings.value(sid)
	match str(def["type"]):
		"bool":
			var c := MenuKit.checkbox("", bool(value))
			c.toggled.connect(func(v: bool) -> void:
				Sfx.play_ui("gui-checkbox-click")
				api.settings.set_value(sid, v))
			control = c
		"number":
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", Kit.px(8))
			var s := MenuKit.slider(float(def["min"]), float(def["max"]), float(def["step"]) if float(def["step"]) > 0.0 else 0.001, float(value))
			s.custom_minimum_size.x = Kit.px(200)
			s.name = "slider"
			var shown := Kit.label(_number_text(value, def))
			shown.custom_minimum_size.x = Kit.px(90)
			s.value_changed.connect(func(v: float) -> void:
				api.settings.set_value(sid, v, false)
				shown.text = _number_text(api.settings.value(sid), def))
			s.drag_ended.connect(func(_changed: bool) -> void: Settings.save())
			row.add_child(s)
			row.add_child(shown)
			control = row
		"choice":
			var o := MenuKit.dropdown(def["choices"], value)
			o.item_selected.connect(func(i: int) -> void:
				Sfx.play_ui("gui-click")
				api.settings.set_value(sid, o.get_item_metadata(i)))
			control = o
		"text":
			var e := MenuKit.textbox(str(value), str(def["placeholder"]))
			e.custom_minimum_size.x = Kit.px(260)
			e.text_submitted.connect(func(t: String) -> void: api.settings.set_value(sid, t))
			e.focus_exited.connect(func() -> void: api.settings.set_value(sid, e.text))
			control = e
	control.name = "addon-setting-%s-%s" % [str(api.id), sid]
	control.tooltip_text = str(def["note"])
	grid.add_child(control)
	var reset := MenuKit.button("Default")
	reset.custom_minimum_size.x = Kit.px(72)
	reset.tooltip_text = "Back to " + _value_text(def["default"], def)
	reset.disabled = api.settings.is_default(sid)
	reset.pressed.connect(func() -> void:
		Sfx.play_ui("gui-click")
		api.settings.reset(sid)
		_show_page())
	grid.add_child(reset)


static func _number_text(v: Variant, def: Dictionary) -> String:
	var f := float(v)
	var text := str(int(f)) if f == floorf(f) else str(snappedf(f, maxf(float(def["step"]), 0.01)))
	var unit := str(def["unit"])
	if unit == "":
		return text
	return text + (unit if unit.begins_with("°") or unit.begins_with("×") or unit.begins_with("%") else " " + unit)


static func _value_text(v: Variant, def: Dictionary) -> String:
	match str(def["type"]):
		"bool":
			return "on" if bool(v) else "off"
		"number":
			return _number_text(v, def)
		"choice":
			for c in def["choices"]:
				if str(c[1]) == str(v):
					return str(c[0])
	return "\"%s\"" % str(v)


# --- keys ---------------------------------------------------------------------------------------

func _key_rows(api) -> void:
	var actions: Dictionary = api.keys._actions
	if actions.is_empty():
		return
	_page.add_child(Kit.label("Keys", "FHeading"))
	_page.add_child(_note("Click a binding, then press the key (with Shift, Ctrl or Alt if you like). Right click clears it, Esc cancels. Bindings that clash are red. They are in Settings → Controls too."))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Kit.px(10))
	grid.add_theme_constant_override("v_separation", Kit.px(4))
	_page.add_child(grid)
	for key_name in actions:
		var action := str(actions[key_name])
		var l := Kit.label(ControlsInfo.name_of(action))
		if str(api.keys._contexts.get(key_name, "")) == "camera":
			l.text += "  (camera)"
			l.tooltip_text = "Works while the add-on has the camera."
			l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.custom_minimum_size.x = Kit.px(230)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(l)
		var keys := Settings.keys_for(action)
		for slot in 2:
			var target := "%s/%d" % [action, slot]
			var b := MenuKit.button(Settings.key_name(action, slot))
			b.name = "addon-key-%s-%d" % [action, slot]
			b.custom_minimum_size.x = Kit.px(130)
			var clash := Settings.conflicts(action, int(keys[slot]))
			if not clash.is_empty():
				b.add_theme_color_override("font_color", Kit.RED_TEXT)
				b.tooltip_text = "Also bound to: " + ", ".join(clash.map(func(a: String) -> String: return ControlsInfo.name_of(a)))
			if _capturing == target:
				b.text = "Press a key…"
			b.pressed.connect(func() -> void:
				Sfx.play_ui("gui-click")
				_capturing = target
				b.text = "Press a key…")
			b.gui_input.connect(func(ev: InputEvent) -> void:
				var mb := ev as InputEventMouseButton
				if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
					capture(target, 0)
					_show_page())
			grid.add_child(b)
		if keys != Settings.default_keys(action):
			var reset := MenuKit.button("Default")
			reset.custom_minimum_size.x = Kit.px(72)
			reset.pressed.connect(func() -> void:
				Sfx.play_ui("gui-click")
				Settings.bind(action, [])
				_show_page())
			grid.add_child(reset)
		else:
			grid.add_child(Control.new())


func _note(text: String) -> Label:
	var n := MenuKit.paragraph(text, 600)
	n.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	return n
