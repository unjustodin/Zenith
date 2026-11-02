extends Control
## Factorio's respawn screen: while the character is dead (`dead`, every half second) the world
## dims and a window says "You died. Bad luck. Respawn in N seconds." (core.cfg
## waiting-for-respawn), counting down; where the player has to press Respawn (single-player,
## `left` 0) its button does it. It closes when the new character's `me` arrives (alive()).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const UiModel := preload("res://scripts/ui/factorio/ui_model.gd")

var model: UiModel
## Seconds until the respawn, counted down here between messages; -1 while alive.
var left := -1.0
## Where the character died (tiles), or null.
var died_at = null

var _text: Label
var _button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # the world can't be clicked while dead
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := Kit.panel("FFrame")
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Kit.px(8))
	frame.add_child(box)
	box.add_child(Kit.title_bar("Died", false))
	var inner := Kit.panel("FShallowFrame")
	box.add_child(inner)
	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, Kit.px(12))
	inner.add_child(pad)
	_text = Kit.label("")
	_text.custom_minimum_size.x = Kit.px(360)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad.add_child(_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(row)
	_button = Button.new()
	_button.text = "Respawn"
	_button.theme_type_variation = "FConfirmButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.custom_minimum_size = Kit.pxv(160, 36)
	var press := func() -> void:
		if model != null:
			model.respawn()
	_button.pressed.connect(press)
	row.add_child(_button)
	if model != null:
		model.died.connect(show_dead)


## `dead`: `ticks` until the respawn (0: waiting for the Respawn button), and where it died.
func show_dead(ticks: int, at) -> void:
	left = ticks / 60.0
	died_at = at
	visible = true
	_update_text()


## The character is back (or the game ended).
func alive() -> void:
	if visible or left >= 0.0:
		visible = false
		left = -1.0
		died_at = null


func is_dead() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible:
		return
	if left > 0.0:
		left = maxf(0.0, left - delta)
	_update_text()


func _update_text() -> void:
	var s := ceili(left)
	if left > 0.0:
		_text.text = "You died. Bad luck. Respawn in %d %s." % [s, "second" if s == 1 else "seconds"]
	else:
		_text.text = "You died. Bad luck."
	_button.visible = left <= 0.0
