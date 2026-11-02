extends RefCounted
## api.ui: windows in Zenith's style (Factorio's frames, title bars, buttons, sliders and check
## boxes, from the player's own install like the rest of Zenith's UI), a layer for the add-on's own
## overlays, messages, and whether the player is busy with Zenith's own UI.
##
## Windows open over the game under Zenith's menus; their title bar drags them, the × and Esc close
## them, and they hide with the interface (api.view.hide_interface). Build their content with the
## helpers here or with Godot's own Controls (they take Zenith's theme).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const Sfx := preload("res://scripts/fx/sfx.gd")

## Zenith's UI kits, for anything the helpers here don't cover (kit.gd, menu_kit.gd).
var kit = Kit
var menu_kit = MenuKit

var _host
var _api
var _windows: Array = []  # PanelContainer frames
var _options := Callable()
var _layer: CanvasLayer


func _init(host, api) -> void:
	_host = host
	_api = api


## A new window, hidden until show(): {"frame" (PanelContainer: show and move this), "box"
## (VBoxContainer: put the content here), "close" (its × Button)}.
func window(title: String) -> Dictionary:
	var parts: Array = MenuKit.window(title, true)
	var frame: PanelContainer = parts[0]
	frame.name = "%s_%s" % [_api.id, title.validate_node_name()]
	frame.visible = false
	var close: Button = parts[2]
	close.pressed.connect(func() -> void:
		Sfx.play_ui("gui-click")
		show(frame, false))
	var bar: Control = (parts[1] as VBoxContainer).get_child(0)
	bar.gui_input.connect(func(ev: InputEvent) -> void:
		var mm := ev as InputEventMouseMotion
		if mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			frame.position += mm.relative)
	_host.ui_root.add_child(frame)
	_windows.append(frame)
	return {"frame": frame, "box": parts[1], "close": close}


## Shows a window (the first time near the top right, under the minimap) or hides it.
func show(frame: Control, on := true) -> void:
	if frame == null:
		return
	if on and not frame.has_meta("placed"):
		frame.set_meta("placed", true)
		frame.reset_size()
		var screen: Vector2 = _host.get_viewport().get_visible_rect().size
		frame.position = Vector2(screen.x - frame.size.x - Kit.px(16), Kit.px(300))
	frame.visible = on and not _host.interface_hidden()
	frame.set_meta("open", on)
	_host.windows_changed()


func toggle(frame: Control) -> void:
	show(frame, not is_open(frame))


## Open (it stays open while the interface is hidden, only out of sight).
func is_open(frame: Control) -> bool:
	return frame != null and bool(frame.get_meta("open", false))


## A CanvasLayer of the add-on's own over the world and the HUD (under add-ons' windows and
## Zenith's menus) for overlays such as letterbox bars or a recording mark; it stays when the
## interface hides.
func layer() -> CanvasLayer:
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.name = "Layer_" + _api.id
		_layer.layer = 14
		_host.add_child(_layer)
	return _layer


## A message over the quickbar, as Zenith's own ("Free camera: F8 again to go back").
func message(text: String) -> void:
	var hud = _host.game_node("hud")
	if hud != null and hud.has_method("show_message"):
		hud.show_message(text)


## The player is typing in a text box (the chat, a search): keys aren't controls now.
func typing() -> bool:
	var focus: Control = _host.get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


## Zenith's menu (Esc), a dialog or the settings are over the game.
func menu_open() -> bool:
	return _host.menu_open()


## One of Zenith's own windows (inventory, a machine, the map...) or an add-on's is open.
func windows_open() -> bool:
	return _host.windows_open()


## Rows for this add-on's options in the Mods window (its Options button): called with an empty
## VBoxContainer each time they are shown.
func set_options(builder: Callable) -> void:
	_options = builder


# --- helpers, each a Control in Zenith's style ------------------------------------------------

func label(text: String) -> Label:
	return Kit.label(text)


func heading(text: String) -> Label:
	return Kit.label(text, "FHeading")


func note(text: String, width := 360) -> Label:
	var l := MenuKit.paragraph(text, width)
	l.add_theme_color_override("font_color", Kit.DISABLED_TEXT)
	return l


func button(text: String, on_press: Callable = Callable()) -> Button:
	var b := MenuKit.button(text)
	if on_press.is_valid():
		b.pressed.connect(func() -> void:
			Sfx.play_ui("gui-click")
			on_press.call())
	return b


func checkbox(text: String, on: bool, on_toggle: Callable = Callable()) -> CheckBox:
	var c := MenuKit.checkbox(text, on)
	if on_toggle.is_valid():
		c.toggled.connect(func(v: bool) -> void:
			Sfx.play_ui("gui-checkbox-click")
			on_toggle.call(v))
	return c


## A slider with its value shown beside it (`fmt` turns the value into text, "%d" by default);
## `on_change` is called as it moves. Returns the row ([HBoxContainer, HSlider] as a Dictionary:
## {"row", "slider"}).
func slider(from: float, to: float, step: float, value: float, on_change: Callable = Callable(), fmt := "%s") -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(8))
	var s := MenuKit.slider(from, to, step, value)
	s.custom_minimum_size.x = Kit.px(160)
	var shown := Kit.label(fmt % _num(value, step))
	shown.custom_minimum_size.x = Kit.px(56)
	s.value_changed.connect(func(v: float) -> void:
		shown.text = fmt % _num(v, step)
		if on_change.is_valid():
			on_change.call(v))
	row.add_child(s)
	row.add_child(shown)
	return {"row": row, "slider": s}


## A dropdown of [label, value] pairs; `on_select` gets the value.
func dropdown(items: Array, value: Variant, on_select: Callable = Callable()) -> OptionButton:
	var o := MenuKit.dropdown(items, value)
	if on_select.is_valid():
		o.item_selected.connect(func(i: int) -> void:
			Sfx.play_ui("gui-click")
			on_select.call(o.get_item_metadata(i)))
	return o


func textbox(text: String, placeholder := "") -> LineEdit:
	return MenuKit.textbox(text, placeholder)


## "Name:  control" in a row, the name's column a fixed width so rows line up.
func row(text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", Kit.px(8))
	var l := Kit.label(text)
	l.custom_minimum_size.x = Kit.px(150)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	h.add_child(control)
	return h


static func _num(v: float, step: float) -> String:
	return str(int(v)) if step >= 1.0 else str(snappedf(v, step))


func _close_all() -> void:
	for w in _windows:
		if is_instance_valid(w):
			w.queue_free()
	_windows.clear()
	if _layer != null:
		_layer.queue_free()
		_layer = null
	_options = Callable()
	_host.windows_changed()


## Its windows hide with the interface and come back with it.
func _interface_hidden(hidden: bool) -> void:
	for w: Control in _windows:
		if is_instance_valid(w):
			w.visible = is_open(w) and not hidden


func _open_windows() -> Array:
	return _windows.filter(func(w: Control) -> bool: return is_instance_valid(w) and w.visible)


func _options_builder() -> Callable:
	return _options
