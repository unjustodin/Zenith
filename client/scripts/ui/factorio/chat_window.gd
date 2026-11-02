extends VBoxContainer
## Factorio's chat and console in the bottom-left corner: lines from the game's chat (the mod's
## `chat`: what players type, and this client's own lines) fade out after a while; ` or / opens the
## input line (/ starts it with a slash), Enter sends, Esc closes. A line starting with / is a
## console command, run wherever it can be (console_commands.gd: here, by the bridge, over RCON,
## or in Factorio itself), and its answer is shown. Up and Down go back through what was typed,
## Tab completes a command's name, as in Factorio's console.
## While open, the whole history shows and the keys go to the line, not the character.
##
## Lines look like Factorio's: the player's name in their chat colour, rich text (rich_text.gd:
## item icons, colours, fonts, gps links), Factorio's font at 18 with a faint dark edge over the
## world, 28 pixels apart. While open, the history and the input line sit on a translucent black
## backdrop as wide as the HUD up to the quickbar's right edge (factorio_ui.gd sets `right_edge`),
## the input a plain dark line with no hint text, as in Factorio's console.
## Clicking a gps link (while the chat is open) looks there; a line with one pings the map.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const RichText := preload("res://scripts/ui/factorio/rich_text.gd")
const Commands := preload("res://scripts/ui/factorio/console_commands.gd")

## A [gps=…] link was clicked, or a line with one arrived (`clicked` false): position in tiles.
signal gps(at: Vector2, surface: String, clicked: bool)

## Seconds a line stays when the chat is closed (Factorio: 10 s, then it fades).
const SHOW_SECONDS := 10.0
const FADE_SECONDS := 1.5
const MAX_SHOWN := 12
const MAX_HISTORY := 100

var model
## Runs the / lines (factorio_ui.gd gives it RCON and the windows).
var console := Commands.new()
## Players whose chat /ignore hides here: name -> true.
var ignored := {}

var _lines := VBoxContainer.new()
var _input: LineEdit
## The open console's translucent black backdrop is drawn (_draw, behind the lines).
var backdrop_shown := false
## Where the open console's backdrop ends on the right (GUI pixels from the left; 0: 560 wide).
var right_edge := 0.0
var _local: Array = []  # [from, text, msec] lines that only this client sees (command answers)
var _cleared_msec := -1  # /clear: lines before this are gone
var _history: Array = []  # what was sent, oldest first
var _history_at := -1  # Up/Down: how far back (-1: the line being typed)
var _draft := ""


func _ready() -> void:
	theme = MenuKit.theme()
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = Kit.px(8)
	offset_right = Kit.px(560)
	offset_bottom = -Kit.px(110)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	alignment = BoxContainer.ALIGNMENT_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", Kit.px(4))
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", Kit.px(4))
	add_child(_lines)
	_input = MenuKit.textbox("", "")
	_input.custom_minimum_size.x = Kit.px(540)
	_input.custom_minimum_size.y = Kit.px(30)
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0.35)
	line.content_margin_left = Kit.px(8)
	line.content_margin_right = Kit.px(8)
	for state in ["normal", "focus", "read_only"]:
		_input.add_theme_stylebox_override(state, line)
	_input.add_theme_color_override("font_color", Kit.WHITE)
	_input.add_theme_color_override("caret_color", Kit.WHITE)
	_input.add_theme_font_size_override("font_size", Kit.px(16))
	_input.tooltip_text = "Chat (/ for a command) · Enter: send · Esc: close"
	_input.visible = false
	_input.text_submitted.connect(_submit)
	_input.gui_input.connect(_on_input_key)
	add_child(_input)
	var arrived := func(_f: String, text: String) -> void:
		for tok in RichText.parse(text):
			if tok["t"] == "gps":
				gps.emit(tok["at"], str(tok["surface"]), false)
		_refresh()
	model.chat_received.connect(arrived)
	console.model = model
	console.chat = self


func is_open() -> bool:
	return _input.visible


## Opens the input line; with_slash starts it with "/" (Factorio's / key).
func open(with_slash := false) -> void:
	_input.visible = true
	_input.text = "/" if with_slash else ""
	_input.grab_focus.call_deferred()
	_input.set_deferred("caret_column", _input.text.length())
	_refresh()


func close() -> void:
	_input.visible = false
	_input.release_focus()
	_refresh()


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.physical_keycode:
		KEY_ESCAPE:
			close()
		KEY_UP:
			browse(1)
		KEY_DOWN:
			browse(-1)
		KEY_TAB:
			complete()
		_:
			return
	_input.accept_event()


## Up (+1) and Down (-1) through what was typed before; past the newest, the line being typed.
func browse(step: int) -> void:
	if _history.is_empty():
		return
	if _history_at == -1:
		_draft = _input.text
	_history_at = clampi(_history_at + step, -1, _history.size() - 1)
	_input.text = _draft if _history_at == -1 else str(_history[_history.size() - 1 - _history_at])
	_input.caret_column = _input.text.length()


## Tab: completes the command's name, or lists the choices.
func complete() -> void:
	var got: Array = Commands.complete(_input.text)
	_input.text = str(got[0])
	_input.caret_column = _input.text.length()
	if not (got[1] as Array).is_empty():
		_say_local("/" + " /".join(PackedStringArray(got[1])))


## /clear: the console starts empty again.
func clear() -> void:
	_cleared_msec = Time.get_ticks_msec()
	_local.clear()
	_refresh()


func _say_local(text: String) -> void:
	for l in text.split("\n"):
		_local.append(["", l, Time.get_ticks_msec()])
	_refresh()


func _submit(text: String) -> void:
	text = text.strip_edges()
	close()
	if text == "":
		return
	if _history.is_empty() or _history[-1] != text:
		_history.append(text)
		if _history.size() > MAX_HISTORY:
			_history.pop_front()
	_history_at = -1
	if text.begins_with("/"):
		_say_local("> " + text)
		var reply := str(await console.run(text)).strip_edges()
		if reply != "":
			_say_local(reply)
	else:
		model.say(text)


func _process(_delta: float) -> void:
	# Fading lines only change with time; redraw a few times a second.
	if Engine.get_process_frames() % 10 == 0:
		_refresh()
	if right_edge > 0.0:
		offset_right = maxf(offset_left + Kit.px(200), right_edge)
		_input.custom_minimum_size.x = offset_right - offset_left
	if backdrop_shown != is_open():
		backdrop_shown = is_open()
		queue_redraw()


func _draw() -> void:
	if backdrop_shown:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))


func _refresh() -> void:
	var all: Array = []
	for l in model.chat_log:
		if int(l[2]) > _cleared_msec and not ignored.has(str(l[0])):
			all.append(l)
	for l in _local:
		all.append(l)
	all.sort_custom(func(a, b) -> bool: return int(a[2]) < int(b[2]))
	var now := Time.get_ticks_msec()
	var shown: Array = []
	for l in all:
		var age := (now - int(l[2])) / 1000.0
		if is_open() or age < SHOW_SECONDS + FADE_SECONDS:
			shown.append([l, 1.0 if is_open() else clampf((SHOW_SECONDS + FADE_SECONDS - age) / FADE_SECONDS, 0.0, 1.0)])
	shown = shown.slice(maxi(0, shown.size() - MAX_SHOWN))
	while _lines.get_child_count() < shown.size():
		var label := RichTextLabel.new()
		label.bbcode_enabled = false
		label.fit_content = true
		label.scroll_active = false
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = Kit.px(540)
		var f := Kit.font("regular")
		if f != null:
			label.add_theme_font_override("normal_font", f)
		label.add_theme_font_size_override("normal_font_size", Kit.px(18))
		label.add_theme_constant_override("outline_size", Kit.px(2))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		label.meta_clicked.connect(_on_meta)
		label.set_meta("sig", "")
		_lines.add_child(label)
	while _lines.get_child_count() > shown.size():
		var last := _lines.get_child(_lines.get_child_count() - 1)
		_lines.remove_child(last)
		last.queue_free()
	for i in shown.size():
		var l: Array = shown[i][0]
		var label: RichTextLabel = _lines.get_child(i)
		var from := str(l[0])
		var sig := "%s|%s|%d" % [from, str(l[1]), int(l[2])]
		if str(label.get_meta("sig")) != sig:
			label.set_meta("sig", sig)
			label.clear()
			var name_color: Color = l[3] if l.size() > 3 and l[3] is Color and (l[3] as Color).a > 0.0 else Color(0.75, 0.88, 1.0)
			if from != "":
				label.push_color(name_color)
				label.add_text(from)
				label.pop()
				label.push_color(Kit.WHITE)
				label.add_text(": ")
				label.pop()
			RichText.fill(label, str(l[1]), Kit.WHITE if from != "" else Kit.YELLOW_TEXT, Kit.px(18))
		label.modulate.a = float(shown[i][1])
		# Links take clicks only while the chat is open; otherwise the world gets them.
		label.mouse_filter = Control.MOUSE_FILTER_STOP if is_open() else Control.MOUSE_FILTER_IGNORE


func _on_meta(meta) -> void:
	var g := RichText.gps_of(meta)
	if not g.is_empty():
		gps.emit(g[0], g[1], true)
