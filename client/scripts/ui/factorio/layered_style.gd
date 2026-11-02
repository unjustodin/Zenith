extends StyleBox
## Several style boxes drawn on top of each other, the way Factorio draws a graphical set: its
## shadow, then the base image, then the glow. The content margins are the element's padding.

var layers: Array[StyleBox] = []


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	for layer in layers:
		layer.draw(to_canvas_item, rect)
