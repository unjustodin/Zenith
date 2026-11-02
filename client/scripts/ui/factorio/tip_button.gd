extends Button
## A button whose tooltip is Factorio's plain one: the text, and the control that does the same
## in parentheses with the keys in bold blue ("Blueprint library (B)"). Set tooltip_text as usual.

const Kit := preload("res://scripts/ui/factorio/kit.gd")


func _make_custom_tooltip(for_text: String) -> Object:
	return Kit.simple_tooltip(for_text)
