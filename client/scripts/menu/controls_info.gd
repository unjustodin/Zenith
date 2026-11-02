extends RefCounted
## How Settings → Controls shows the input actions: in Factorio's groups, under Factorio's names
## ([gui-control-settings] and [controls] in core/locale/en/core.cfg). An action defined anywhere
## (InputMap, before Settings.apply_bindings()) appears in the tab by itself; add a row here to put
## it in its Factorio group under Factorio's name, otherwise it goes under Miscellaneous with a
## name made from its id.
##
## FIXED lists what can't be rebound yet (the mouse and keys handled directly by the UI), shown
## greyed in their groups so the tab lists every control the client has.

## Factorio's groups, in its order, then ours.
const GROUPS := [
	"Movement", "Basic interaction", "Advanced interaction", "Tools", "Crafting", "Inventory",
	"Quickbar", "Panels", "Miscellaneous", "Camera",
]

## action -> [group, Factorio's name (or ours, for the camera)].
const ACTIONS := {
	"move_up": ["Movement", "Move up"],
	"move_down": ["Movement", "Move down"],
	"move_left": ["Movement", "Move left"],
	"move_right": ["Movement", "Move right"],
	"rotate": ["Basic interaction", "Rotate (Shift: reverse rotate)"],
	"reverse_rotate": ["Basic interaction", "Reverse rotate"],
	"flip_horizontal": ["Basic interaction", "Flip horizontal"],
	"flip_vertical": ["Basic interaction", "Flip vertical"],
	"pick_up": ["Basic interaction", "Pick up items on the ground"],
	"drop_item": ["Basic interaction", "Drop item"],
	"clear_cursor": ["Basic interaction", "Clear cursor"],
	"pipette": ["Basic interaction", "Pipette tool"],
	"open_screen": ["Basic interaction", "Open character screen / object's GUI"],
	"enter_vehicle": ["Basic interaction", "Enter/leave vehicle"],
	"shoot_enemies": ["Basic interaction", "Shoot enemy"],
	"shoot_cursor": ["Basic interaction", "Shoot selected"],
	"next_gun": ["Basic interaction", "Next weapon"],
	"zoom_in": ["Basic interaction", "Zoom in"],
	"zoom_out": ["Basic interaction", "Zoom out"],
	"alt_mode": ["Basic interaction", "Toggle \"Alt-mode\""],
	"copy_settings": ["Advanced interaction", "Copy entity settings"],
	"paste_settings": ["Advanced interaction", "Paste entity settings"],
	"toggle_rail_layer": ["Advanced interaction", "Toggle rail layer"],
	"larger_tile_area": ["Advanced interaction", "Larger tile building area"],
	"smaller_tile_area": ["Advanced interaction", "Smaller tile building area"],
	"copy": ["Tools", "Copy"],
	"cut": ["Tools", "Cut"],
	"paste": ["Tools", "Paste"],
	"undo": ["Tools", "Undo"],
	"redo": ["Tools", "Redo"],
	"give_blueprint": ["Tools", "Blueprint"],
	"give_deconstruction_planner": ["Tools", "Deconstruction planner"],
	"give_upgrade_planner": ["Tools", "Upgrade planner"],
	"give_red_wire": ["Tools", "Red wire"],
	"give_green_wire": ["Tools", "Green wire"],
	"give_copper_wire": ["Tools", "Copper wire"],
	"toggle_personal_logistics": ["Tools", "Toggle personal logistic requests"],
	"toggle_personal_roboport": ["Tools", "Toggle personal roboport"],
	"toggle_equipment_movement_bonus": ["Tools", "Toggle equipment movement bonus"],
	"toggle_players": ["Panels", "Players"],
	"cycle_quality_up": ["Tools", "Increase quality"],
	"cycle_quality_down": ["Tools", "Decrease quality"],
	"cycle_blueprint_forwards": ["Tools", "Blueprint book next"],
	"cycle_blueprint_backwards": ["Tools", "Blueprint book previous"],
	"focus_search": ["Inventory", "Focus search"],
	"quickbar_1": ["Quickbar", "Shortcut 1"],
	"quickbar_2": ["Quickbar", "Shortcut 2"],
	"quickbar_3": ["Quickbar", "Shortcut 3"],
	"quickbar_4": ["Quickbar", "Shortcut 4"],
	"quickbar_5": ["Quickbar", "Shortcut 5"],
	"quickbar_6": ["Quickbar", "Shortcut 6"],
	"quickbar_7": ["Quickbar", "Shortcut 7"],
	"quickbar_8": ["Quickbar", "Shortcut 8"],
	"quickbar_9": ["Quickbar", "Shortcut 9"],
	"quickbar_10": ["Quickbar", "Shortcut 10"],
	"quickbar_page_1": ["Quickbar", "Select quickbar 1"],
	"quickbar_page_2": ["Quickbar", "Select quickbar 2"],
	"quickbar_page_3": ["Quickbar", "Select quickbar 3"],
	"quickbar_page_4": ["Quickbar", "Select quickbar 4"],
	"quickbar_page_5": ["Quickbar", "Select quickbar 5"],
	"quickbar_page_6": ["Quickbar", "Select quickbar 6"],
	"quickbar_page_7": ["Quickbar", "Select quickbar 7"],
	"quickbar_page_8": ["Quickbar", "Select quickbar 8"],
	"quickbar_page_9": ["Quickbar", "Select quickbar 9"],
	"quickbar_page_10": ["Quickbar", "Select quickbar 10"],
	"toggle_filter": ["Inventory", "Toggle filter"],
	"rotate_quickbars": ["Quickbar", "Rotate active quickbars"],
	"toggle_menu": ["Panels", "Toggle menu"],
	"open_character": ["Panels", "Open character screen"],
	"open_technology": ["Panels", "Toggle technology screen"],
	"production_statistics": ["Panels", "Toggle production statistics"],
	"kill_statistics": ["Panels", "Toggle kill statistics"],
	"toggle_map": ["Panels", "Toggle world map"],
	"logistic_networks": ["Panels", "Toggle logistic networks"],
	"blueprint_library": ["Panels", "Toggle blueprint library"],
	"train_overview": ["Panels", "Toggle train overview"],
	"toggle_console": ["Panels", "Toggle chat (and Lua console)"],
	"factoriopedia": ["Panels", "Open factoriopedia"],
	"toggle_help": ["Miscellaneous", "Show control hints (F1)"],
	"debug_line": ["Miscellaneous", "Debug line"],
	"increase_ui_scale": ["Miscellaneous", "Increase UI scale"],
	"decrease_ui_scale": ["Miscellaneous", "Decrease UI scale"],
	"reset_ui_scale": ["Miscellaneous", "Reset UI scale to automatic"],
	"camera_left": ["Camera", "Turn camera left"],
	"camera_right": ["Camera", "Turn camera right"],
	"camera_tilt_up": ["Camera", "Tilt camera up"],
	"camera_tilt_down": ["Camera", "Tilt camera down"],
	"factorio_view": ["Camera", "Factorio's view"],
	"first_person": ["Camera", "First person"],
	"toggle_projection": ["Camera", "Perspective or orthographic, for the view in use (the map's or the normal one)"],
	"show_factorio": ["Miscellaneous", "Show in Factorio (the same game, Ctrl+F9 there comes back)"],
}

## [group, name, binding] for controls handled directly, not through InputMap (not rebindable).
## A row goes away by itself once an action of the same name exists.
const FIXED := [
	["Basic interaction", "Build", "Left mouse"],
	["Basic interaction", "Mine", "Right mouse"],
	["Basic interaction", "Build ghost / super-forced build", "Shift / Ctrl + Shift + Left mouse"],
	["Basic interaction", "Fast entity transfer / split", "Ctrl + Left / Right mouse"],
	["Advanced interaction", "Copy / paste entity settings", "Shift + Right / Left mouse"],
	["Inventory", "Toggle filter", "Middle mouse on a slot"],
	["Basic interaction", "Zoom in / out", "Mouse wheel"],
	["Tools", "Increase / decrease quality", "Ctrl + Mouse wheel up / down"],
	["Tools", "Blueprint book next / previous", "Shift + Mouse wheel down / up"],
	["Tools", "Cancel deconstruction / upgrade (planner held)", "Shift + Left mouse drag"],
	["Inventory", "Pick up / drop item stack, stack transfer, splits", "Mouse (with Shift / Ctrl)"],
	["Crafting", "Craft 1 / 5 / all", "Left / Right / Shift + Left mouse"],
	["Panels", "Toggle menu / close windows", "Escape"],
	["Camera", "Turn and tilt the camera", "Middle mouse drag"],
]


## Add-ons' controls (scripts/addons/addon_keys.gd): action -> [group (the add-on's name), name].
## Each add-on's group follows Zenith's own.
static var extra := {}


## GROUPS, then the add-ons' groups in the order they were added.
static func groups() -> Array:
	var out: Array = GROUPS.duplicate()
	for action in extra:
		var g := str(extra[action][0])
		if not out.has(g):
			out.append(g)
	return out


static func group_of(action: String) -> String:
	if extra.has(action):
		return str(extra[action][0])
	return str(ACTIONS[action][0]) if ACTIONS.has(action) else "Miscellaneous"


static func name_of(action: String) -> String:
	if extra.has(action):
		return str(extra[action][1])
	return str(ACTIONS[action][1]) if ACTIONS.has(action) else action.replace("_", " ").capitalize()
