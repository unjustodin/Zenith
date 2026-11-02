extends HBoxContainer
## Factorio's crafting queue in the bottom-left corner: one crafting_queue_slot per queue entry
## with the recipe's icon and count, the first with the orange progress pie, the slots touching;
## the tooltip is Factorio's recipe tooltip. Click cancels one craft, right click five,
## Shift+click the whole entry; the ingredients come back. Needs the mod's
## `cq` (ui_model.craft_queue); with only the queue length (`me.q`) it shows nothing.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const Slot := preload("res://scripts/ui/factorio/slot.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const CraftingPanel := preload("res://scripts/ui/factorio/crafting_panel.gd")

## Entries shown at most (Factorio wraps; this many fill a row at 1280x720 beside the weapons).
const MAX_SHOWN := 12

var model: UiModel
var _slots: Array[Slot] = []


func _ready() -> void:
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = Kit.px(8)
	offset_bottom = -Kit.px(8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)  # crafting_queue_slots touch, as in Factorio
	model.queue_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var entries: Array = []
	for e in model.craft_queue:
		if e is Dictionary and int(e.get("count", 0)) > 0:
			entries.append(e)
	entries = entries.slice(0, MAX_SHOWN)
	while _slots.size() < entries.size():
		_slots.append(_new_slot(_slots.size()))
	for i in _slots.size():
		var s := _slots[i]
		s.visible = i < entries.size()
		if not s.visible:
			continue
		var e: Dictionary = entries[i]
		var recipe := str(e.get("recipe", ""))
		var r := model.recipe(recipe)
		s.set_stack(_icon_item(recipe, r), int(e.get("count", 1)))
		s.set_progress(float(e.get("progress", 0.0)) if i == 0 else -1.0)
		s.set_meta("index", int(e.get("index", i + 1)))
		s.set_meta("count", int(e.get("count", 1)))
		s.set_tip("%s (Recipe)" % Kit.recipe_name(recipe), CraftingPanel.recipe_tip_lines(model, r))


func _new_slot(_i: int) -> Slot:
	var s := Slot.new()
	s.theme_type_variation = "FQueueSlot"
	var on_click := func(button_index: int, shift: bool) -> void:
		if button_index == MOUSE_BUTTON_MIDDLE:
			return
		var n := 5 if button_index == MOUSE_BUTTON_RIGHT else 1
		if shift:
			n = int(s.get_meta("count", 1))
		model.cancel_craft(int(s.get_meta("index", 1)), n)
	s.clicked.connect(on_click)
	add_child(s)
	return s


static func _icon_item(recipe: String, r: Dictionary) -> String:
	var products: Array = r.get("products", [])
	if products.size() == 1 and products[0] is Array:
		return str(products[0][0])
	return recipe
