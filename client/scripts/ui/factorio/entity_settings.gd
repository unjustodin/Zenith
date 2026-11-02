extends RefCounted
## Pieces of entity windows the others share (logic_windows.gd): the colour of a gui.col, and a
## display panel's message row (its icon, text and condition, sent as gui.dp.msgs).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const MenuKit := preload("res://scripts/menu/menu_kit.gd")
const EntityPanels := preload("res://scripts/ui/factorio/entity_panels.gd")

const SIGNAL_KINDS := ["item", "fluid", "virtual"]


static func _col(c) -> Color:
	if c is Array and (c as Array).size() >= 3:
		return Color8(int(c[0]), int(c[1]), int(c[2]))
	return Color.WHITE


## A display panel message: its icon, text, the condition that shows it, and remove.
static func _message_row(screen, msgs: Array, i: int, send: Callable) -> Control:
	var m: Dictionary = msgs[i] if msgs[i] is Dictionary else {}
	msgs[i] = m
	var r := EntityPanels.row(4)
	var set_icon := func(t: String, n: String) -> void:
		m["icon"] = {"type": t, "name": n} if n != "" else {}
		send.call()
	r.add_child(EntityPanels.choose_slot(screen, EntityPanels._signal_name(m.get("icon")), SIGNAL_KINDS, set_icon, "Icon"))
	var text := MenuKit.textbox(str(m.get("text", "")), "Message")
	text.custom_minimum_size.x = Kit.px(150)
	var set_text := func(t: String) -> void:
		m["text"] = t
		send.call()
	text.text_submitted.connect(set_text)
	r.add_child(text)
	var cond: Dictionary = (m.get("cond") as Dictionary).duplicate(true) if m.get("cond") is Dictionary else {"comparator": "<", "constant": 0}
	cond.erase("ful")
	var set_cond := func(c: Dictionary) -> void:
		m["cond"] = c
		send.call()
	r.add_child(EntityPanels._condition_editor(screen, cond, SIGNAL_KINDS, set_cond))
	var remove := func() -> void:
		msgs.remove_at(i)
		send.call()
	r.add_child(EntityPanels.button("✕", remove, 32))
	return r
