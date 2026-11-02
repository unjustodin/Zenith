@tool
extends EditorExportPlugin
## Entity models (res://assets/models/<name>.glb) go into an exported game as the .glb files
## themselves instead of their imported scenes. model_library.gd parses a .glb on a worker thread
## and keeps its arrays on the CPU; from an imported scene it could only merge the meshes by
## reading them back from the GPU on the main thread, 20-250 ms per model's first appearance.
## Item models (assets/models/items/) stay imported scenes: item_models.gd loads those.

const DIR := "res://assets/models/"


func _get_name() -> String:
	return "ZenithModels"


static func ships_raw(path: String) -> bool:
	# Subfolders too (fue5/: models under their own licence), but not items/.
	return path.begins_with(DIR) and not path.begins_with(DIR + "items/") and path.get_extension().to_lower() in ["glb", "gltf"]


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if not ships_raw(path):
		return
	add_file(path, FileAccess.get_file_as_bytes(path), false)
	skip()
