extends RefCounted
## Every keyboard control, as Godot InputMap actions with Factorio's default keys, so Settings →
## Controls can rebind each one (settings.gd keeps the bindings). Labels are Factorio's names for
## its controls (core.cfg [controls]); the client's own camera controls come last.
##
## A key may carry modifiers (KEY_R | KEY_MASK_SHIFT is Shift+R). Controls are matched with
## exactly their modifiers (`pressed`), so R and Shift+R, or C and Ctrl+C, are different controls,
## as in Factorio. Mouse buttons aren't actions: building, mining, copying settings and the slot
## clicks are fixed (Settings lists them).
##
## Factorio's Z (drop item), X (swap quickbars) and V (flip) took the client's old camera keys:
## the camera now turns with , and . and Factorio's view moved to F6.
##
## Quality and book cycling are on the mouse wheel by default (Ctrl+wheel and Shift+wheel,
## player_input.gd); their actions here start without keys, so a key can be bound to them.

const LIST := [
	["move_up", "Move up", [KEY_W, KEY_UP]],
	["move_down", "Move down", [KEY_S, KEY_DOWN]],
	["move_left", "Move left", [KEY_A, KEY_LEFT]],
	["move_right", "Move right", [KEY_D, KEY_RIGHT]],
	["open_screen", "Open character screen", [KEY_E]],
	["open_technology", "Toggle technology screen", [KEY_T]],
	["toggle_map", "Toggle world map", [KEY_M]],
	["production_statistics", "Toggle production statistics", [KEY_P]],
	["kill_statistics", "Toggle kill statistics", [KEY_K]],
	["logistic_networks", "Toggle logistic networks", [KEY_L]],
	["toggle_factoriopedia", "Factoriopedia (Alt+click opens a thing's page)", [KEY_F2]],
	["toggle_console", "Toggle chat (and Lua console)", [KEY_QUOTELEFT, KEY_SLASH]],
	["shoot_enemies", "Shoot enemy", [KEY_SPACE]],
	["shoot_cursor", "Shoot selected", [KEY_C]],
	["next_gun", "Next weapon", [KEY_TAB]],
	["enter_vehicle", "Enter/leave vehicle", [KEY_ENTER, KEY_KP_ENTER]],
	["pick_up", "Pick up items on the ground", [KEY_F]],
	["rotate", "Rotate", [KEY_R]],
	["reverse_rotate", "Reverse rotate", [KEY_R | KEY_MASK_SHIFT]],
	["flip_horizontal", "Flip horizontal", [KEY_H]],
	["flip_vertical", "Flip vertical", [KEY_V]],
	["clear_cursor", "Clear cursor", [KEY_Q]],
	["pipette", "Pipette tool", [KEY_Q]],
	["drop_item", "Drop item", [KEY_Z]],
	["alt_mode", "Toggle \"Alt-mode\"", [KEY_ALT]],
	["copy", "Copy", [KEY_C | KEY_MASK_CTRL]],
	["cut", "Cut", [KEY_X | KEY_MASK_CTRL]],
	["paste", "Paste", [KEY_V | KEY_MASK_CTRL]],
	["undo", "Undo", [KEY_Z | KEY_MASK_CTRL]],
	["redo", "Redo", [KEY_Y | KEY_MASK_CTRL]],
	["focus_search", "Focus search", [KEY_F | KEY_MASK_CTRL]],
	["give_blueprint", "Blueprint (shortcut)", [KEY_B | KEY_MASK_ALT]],
	["blueprint_library", "Toggle blueprint library", [KEY_B]],
	["cycle_quality_up", "Increase quality", []],
	["cycle_quality_down", "Decrease quality", []],
	["cycle_blueprint_forwards", "Blueprint book next", []],
	["cycle_blueprint_backwards", "Blueprint book previous", []],
	["give_deconstruction_planner", "Deconstruction planner (shortcut)", [KEY_D | KEY_MASK_ALT]],
	["give_upgrade_planner", "Upgrade planner (shortcut)", [KEY_U | KEY_MASK_ALT]],
	["give_red_wire", "Red wire (shortcut)", [KEY_R | KEY_MASK_ALT]],
	["give_green_wire", "Green wire (shortcut)", [KEY_G | KEY_MASK_ALT]],
	["give_copper_wire", "Copper wire (shortcut)", [KEY_C | KEY_MASK_ALT]],
	["toggle_personal_logistics", "Toggle personal logistic requests", [KEY_L | KEY_MASK_ALT]],
	["toggle_personal_roboport", "Toggle personal roboport", [KEY_F | KEY_MASK_ALT]],
	["toggle_equipment_movement_bonus", "Toggle equipment movement bonus", [KEY_E | KEY_MASK_ALT]],
	["toggle_players", "Players (client)", []],
	["quickbar_1", "Shortcut 1", [KEY_1]],
	["quickbar_2", "Shortcut 2", [KEY_2]],
	["quickbar_3", "Shortcut 3", [KEY_3]],
	["quickbar_4", "Shortcut 4", [KEY_4]],
	["quickbar_5", "Shortcut 5", [KEY_5]],
	["quickbar_6", "Shortcut 6", [KEY_6]],
	["quickbar_7", "Shortcut 7", [KEY_7]],
	["quickbar_8", "Shortcut 8", [KEY_8]],
	["quickbar_9", "Shortcut 9", [KEY_9]],
	["quickbar_10", "Shortcut 10", [KEY_0]],
	["quickbar_page_1", "Select quickbar 1", [KEY_1 | KEY_MASK_SHIFT]],
	["quickbar_page_2", "Select quickbar 2", [KEY_2 | KEY_MASK_SHIFT]],
	["quickbar_page_3", "Select quickbar 3", [KEY_3 | KEY_MASK_SHIFT]],
	["quickbar_page_4", "Select quickbar 4", [KEY_4 | KEY_MASK_SHIFT]],
	["quickbar_page_5", "Select quickbar 5", [KEY_5 | KEY_MASK_SHIFT]],
	["quickbar_page_6", "Select quickbar 6", [KEY_6 | KEY_MASK_SHIFT]],
	["quickbar_page_7", "Select quickbar 7", [KEY_7 | KEY_MASK_SHIFT]],
	["quickbar_page_8", "Select quickbar 8", [KEY_8 | KEY_MASK_SHIFT]],
	["quickbar_page_9", "Select quickbar 9", [KEY_9 | KEY_MASK_SHIFT]],
	["quickbar_page_10", "Select quickbar 10", [KEY_0 | KEY_MASK_SHIFT]],
	["rotate_quickbars", "Rotate active quickbars", [KEY_X]],
	["larger_tile_area", "Larger tile building area", [KEY_KP_ADD]],
	["smaller_tile_area", "Smaller tile building area", [KEY_KP_SUBTRACT]],
	["toggle_rail_layer", "Toggle rail layer", [KEY_R | KEY_MASK_ALT]],
	["increase_ui_scale", "Increase UI scale", [KEY_EQUAL | KEY_MASK_CTRL]],
	["decrease_ui_scale", "Decrease UI scale", [KEY_MINUS | KEY_MASK_CTRL]],
	["reset_ui_scale", "Reset UI scale to automatic", [KEY_0 | KEY_MASK_CTRL]],
	["toggle_help", "Help (client)", [KEY_F1]],
	["debug_line", "Debug line (client)", [KEY_F4]],
	["camera_left", "Turn camera left (client)", [KEY_COMMA]],
	["camera_right", "Turn camera right (client)", [KEY_PERIOD]],
	["camera_tilt_up", "Tilt camera up (client)", [KEY_PAGEUP]],
	["camera_tilt_down", "Tilt camera down (client)", [KEY_PAGEDOWN]],
	["factorio_view", "Factorio's view (client)", [KEY_F6]],
	["first_person", "First person (client)", [KEY_F5]],
	["toggle_projection", "Perspective / orthographic (client)", [KEY_F7]],
	["show_factorio", "Show in Factorio (client)", [KEY_F9 | KEY_MASK_CTRL]],
]

const MODIFIERS := [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]


## Adds the actions that aren't defined yet, with their default keys. Call once before the scene
## starts (main.gd, before Settings.apply_bindings), or from anything that needs them in a test.
static func define() -> void:
	for entry in LIST:
		var action: String = entry[0]
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for code in entry[2]:
			InputMap.action_add_event(action, key_event(int(code)))


## An InputEventKey for a keycode with modifier masks (OS.get_keycode_string / find_keycode_from_string).
static func key_event(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code & KEY_CODE_MASK
	ev.shift_pressed = code & KEY_MASK_SHIFT != 0
	ev.ctrl_pressed = code & KEY_MASK_CTRL != 0
	ev.alt_pressed = code & KEY_MASK_ALT != 0
	ev.meta_pressed = code & KEY_MASK_META != 0
	return ev


static func label(action: String) -> String:
	for entry in LIST:
		if entry[0] == action:
			return entry[1]
	return ""


static func is_modifier(code: int) -> bool:
	return MODIFIERS.has(code & KEY_CODE_MASK)


## The event presses the action with exactly its modifiers. A modifier on its own (Alt-mode's Alt)
## arrives with its own flag set, so it matches loosely.
static func pressed(event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	if event.is_action_pressed(action, false, true):
		return true
	var key := event as InputEventKey
	return key != null and is_modifier(key.physical_keycode) and event.is_action_pressed(action)


## The keys bound to an action, as text ("Shift+R / Q").
static func keys_text(action: String) -> String:
	var names: Array = []
	if InputMap.has_action(action):
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				names.append(OS.get_keycode_string((ev as InputEventKey).get_physical_keycode_with_modifiers()))
	return " / ".join(names)
