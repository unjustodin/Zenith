@tool
extends EditorPlugin
## Adds models_export.gd to every export (tools/release/package.py).

const ModelsExport := preload("res://addons/zenith_export/models_export.gd")

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = ModelsExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
