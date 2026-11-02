extends RefCounted
## Small 3D models for items on belts, on the ground and in inserter hands:
## res://assets/models/items/<item>.glb, made by tools/models/items.py. Each is a few dozen
## triangles with its colours (picked once from Factorio's item icon) in the vertices, so every
## item type shares one plain material and draws as one MultiMesh (item_cards.gd).

const ItemShader := preload("res://shaders/item.gdshader")
const DIR := "res://assets/models/items/"
## Item colours are picked from icons that are drawn lit already; under the sun they'd read
## brighter than the icon (compared side by side with the icon cards).
const EXPOSURE := 0.75

static var _cache := {}  # item name -> Mesh, or null when it has no model
static var _material: ShaderMaterial


## The item's model, or null (the item keeps its icon card).
static func mesh_for(item: String) -> Mesh:
	if _cache.has(item):
		return _cache[item]
	var path := DIR + item + ".glb"
	var mesh: Mesh = null
	if item != "" and ResourceLoader.exists(path):
		mesh = _mesh_of(load(path) as PackedScene)
	_cache[item] = mesh
	return mesh


## Whether mesh_for(item) answers at once; if not, its model is read on a thread meanwhile. Reading
## one on the main thread took 10-40 ms the first time an item came into view while walking.
static func ready(item: String) -> bool:
	if _cache.has(item):
		return true
	var path := DIR + item + ".glb"
	if not _loading.has(item):
		if item == "" or not ResourceLoader.exists(path):
			_cache[item] = null
			return true
		if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
			mesh_for(item)
			return true
		_loading[item] = path
		return false
	match ResourceLoader.load_threaded_get_status(path):
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
		ResourceLoader.THREAD_LOAD_LOADED:
			_cache[item] = _mesh_of(ResourceLoader.load_threaded_get(path) as PackedScene)
		_:
			_cache[item] = null
	_loading.erase(item)
	return true


static var _loading := {}  # item name -> its model's path, being read on a thread


static func _mesh_of(packed: PackedScene) -> Mesh:
	if packed == null:
		return null
	var mesh: Mesh = null
	var root := packed.instantiate()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		mesh = (node as MeshInstance3D).mesh
		break
	root.free()
	return mesh


## One material for every item model: the vertex colours are the albedo (linear, as glTF
## stores them).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = ItemShader
		_material.set_shader_parameter("exposure", EXPOSURE)
	return _material


## A plain block for an item with neither a model nor an icon.
static func block_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ItemShader
	m.set_shader_parameter("color", color)
	return m
