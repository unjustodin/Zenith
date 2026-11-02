extends RefCounted
## api.keys: an add-on's own controls. Each is an input action shown in Settings → Controls under
## the add-on's name, rebindable like Zenith's own (a primary and an alternative key, each with
## any of Shift, Ctrl and Alt), and saved in the same settings file.
##
## Where a control works:
##   "global"  always in a game. Its default keys mustn't be any of Zenith's or another add-on's
##             global keys: a default that is already taken is left unbound (the log says so),
##             so an add-on can't take a key from Zenith; the player can still bind it there.
##   "camera"  only while this add-on has the camera with the player's controls off
##             (api.camera.take): then it may share keys with Zenith's controls (WASD to fly), and
##             Zenith doesn't see those keys meanwhile.
## Neither works while the player types in a text box or Zenith's menu is over the game.

const Settings := preload("res://scripts/menu/settings.gd")
const ControlsInfo := preload("res://scripts/menu/controls_info.gd")

var _host
var _api
var _actions := {}  # name -> action
var _contexts := {}  # name -> "global" or "camera"


func _init(host, api) -> void:
	_host = host
	_api = api


## Adds a control: `name` within the add-on ("free_camera"), its label in Settings → Controls,
## its default keys (up to two: key codes with modifier masks, KEY_F8 | KEY_MASK_SHIFT, or names
## such as "Shift+F8"), and where it works. Returns the input action's name.
func add(name: String, label: String, default_keys: Array = [], context := "global") -> String:
	var action := action_of(name)
	var ctx := "global" if context != "camera" else "%s:camera" % _api.id
	Settings.contexts[action] = ctx
	var codes: Array = []
	for k in default_keys:
		var code: int = OS.find_keycode_from_string(k) if k is String else int(k)
		if code == 0:
			continue
		var clash := Settings.conflicts(action, code)
		if not clash.is_empty():
			_api.note("%s: %s is already %s; left unbound (set it in Settings → Controls)" % [label,
				Settings.key_text(code), ", ".join(clash.map(func(a: String) -> String: return ControlsInfo.name_of(a)))])
			continue
		codes.append(code)
	ControlsInfo.extra[action] = [_api.name, label]
	Settings.add_action(action, codes, ctx)
	_actions[name] = action
	_contexts[name] = "camera" if context == "camera" else "global"
	return action


## The input action of one of this add-on's controls.
func action_of(name: String) -> String:
	return "addon_%s__%s" % [_api.id.replace("-", "_"), name]


## This control was pressed by this event, where it works now. Its modifiers must be held; others
## held as well only count against it when another of the add-on's controls has exactly those
## (Shift+= is still "=" for "faster", but Shift+F8 isn't F8 when Shift+F8 is a control of its own).
func pressed(event: InputEvent, name: String) -> bool:
	if not _active(name):
		return false
	if event.is_action_pressed(_actions[name], false, true):
		return true
	if not event.is_action_pressed(_actions[name], false, false):
		return false
	for other in _actions:
		if other != name and event.is_action_pressed(_actions[other], false, true):
			return false
	return true


func released(event: InputEvent, name: String) -> bool:
	return _actions.has(name) and event.is_action_released(_actions[name], true)


## The control is held down now, where it works now.
func held(name: String) -> bool:
	return _active(name) and Input.is_action_pressed(_actions[name])


## Its keys, for hints: "F8", "Shift + F8 / F10", or "(none)".
func text(name: String) -> String:
	return Settings.key_names(_actions[name]) if _actions.has(name) else "(none)"


## The other controls (labels) sharing one of its keys where both work.
func conflicts(name: String) -> Array:
	var out: Array = []
	if not _actions.has(name):
		return out
	for code in Settings.keys_for(_actions[name]):
		for other in Settings.conflicts(_actions[name], int(code)):
			out.append(ControlsInfo.name_of(other))
	return out


func _active(name: String) -> bool:
	if not _actions.has(name) or not _host.in_game() or _host.keys_blocked():
		return false
	return _contexts[name] == "global" or _api.camera.has_input()


## Actions that are this add-on's camera controls (the host keeps them from Zenith meanwhile).
func _camera_actions() -> Array:
	var out: Array = []
	for name in _actions:
		if _contexts[name] == "camera":
			out.append(_actions[name])
	return out


func _remove_all() -> void:
	for name in _actions:
		Settings.remove_action(_actions[name])
		ControlsInfo.extra.erase(_actions[name])
	_actions.clear()
	_contexts.clear()
