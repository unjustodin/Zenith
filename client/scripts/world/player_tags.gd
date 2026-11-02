extends Node3D
## Other players' names over their characters, in their colour, as Factorio shows them: each
## connected player in `pl` whose character is a mover near the camera (not the client's own)
## gets a label that follows it.

const MoverLayer := preload("res://scripts/world/movers.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")
const Kit := preload("res://scripts/ui/factorio/kit.gd")

## Over the character's head (it is about 2 tiles tall).
const HEIGHT := 2.6

var movers: MoverLayer
var model: UiModel

var _labels := {}  # character unit -> Label3D


func _process(_delta: float) -> void:
	if movers == null or model == null:
		return
	var seen := {}
	for p in model.players:
		var unit := int(p["unit"])
		if unit == 0 or not p["connected"] or unit == model.me_unit or unit == movers.puppet_unit:
			continue
		var at = movers.position_of(unit)
		if at == null:
			continue
		seen[unit] = true
		var label: Label3D = _labels.get(unit)
		if label == null:
			label = _make_label()
			add_child(label)
			_labels[unit] = label
		var text := str(p["name"]) + (" " + str(p["tag"]) if str(p["tag"]) != "" else "")
		if label.text != text:
			label.text = text
		label.modulate = (p["color"] as Color).lightened(0.2)
		label.position = (at as Vector3) + Vector3(0, HEIGHT, 0)
	for unit in _labels.keys():
		if not seen.has(unit):
			(_labels[unit] as Node).queue_free()
			_labels.erase(unit)


func count() -> int:
	return _labels.size()


func _make_label() -> Label3D:
	var l := Label3D.new()
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.pixel_size = 0.0006
	l.font_size = 22
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.no_depth_test = true
	l.render_priority = 10
	var f := Kit.font("bold")
	if f != null:
		l.font = f
	return l
