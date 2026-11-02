extends Control
## vr_test.gd: counts the key presses that reach the HUD.

var counter: Array


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		counter[0] += 1
