extends Node3D
## The decorative layer (scripts/world/decoratives.gd) fed `dprotos` and `dec` as the mod sends
## them, with a picture made here and a stand-in index (nothing of Factorio's), then malformed
## lists. Exits 1 if a check fails; CI also fails on any SCRIPT ERROR in the output.
##
##   godot --headless --path client res://tests/decor_test.tscn

const Decoratives := preload("res://scripts/world/decoratives.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")

var fails := 0


## Stands in for world.gd: the chunks still loaded.
class FakeWorld:
	extends Node
	var chunks := {}


func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", what)


func _ready() -> void:
	# A 64x32 sheet with two 32x32 variants, in a stand-in data folder.
	var dir := OS.get_user_data_dir().path_join("decor_test")
	DirAccess.make_dir_recursive_absolute(dir.path_join("base/graphics/decorative"))
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.6, 0.2, 1.0))
	image.save_png(dir.path_join("base/graphics/decorative/test.png"))
	ItemIcons.data_dir = dir
	ItemIcons._searched = true
	Decoratives._index = {
		"green-carpet-grass": {"layer": "decals", "box": [-0.5, -0.5, 0.5, 0.5],
			"pics": [["base/graphics/decorative/test.png", 0, 0, 32, 32, 0.5, 0, 0], ["base/graphics/decorative/test.png", 32, 0, 32, 32, 0.5, 0, 0]]},
		"small-rock": {"layer": "object", "box": [-0.5, -0.5, 0.5, 0.5],
			"pics": [["base/graphics/decorative/test.png", 0, 0, 32, 32, 0.5, 0.1, 0]]},
		"no-pictures": {"layer": "decorative", "box": [-0.5, -0.5, 0.5, 0.5], "pics": [["base/graphics/decorative/missing.png", 0, 0, 8, 8, 1, 0, 0]]},
	}
	var world := FakeWorld.new()
	add_child(world)
	world.chunks[Vector2i(0, 0)] = true
	world.chunks[Vector2i(1, 0)] = true
	var d: Node3D = Decoratives.new()
	d.world = world
	add_child(d)

	d.handle({"t": "dprotos", "part": 1, "parts": 1, "l": [[1, "green-carpet-grass"], [2, "small-rock"], [3, "no-pictures"]]})
	var l := []
	for i in 100:
		l.append_array([1, i % 32, i / 32, 1])
	l.append_array([2, 5, 5, 2, 3, 6, 6, 1])
	# Two parts: nothing is drawn until the second arrives.
	d.handle({"t": "dec", "cx": 0, "cy": 0, "part": 1, "parts": 2, "l": l.slice(0, 200)})
	check(_instances(d) == 0, "a chunk is drawn only when all its parts arrived")
	d.handle({"t": "dec", "cx": 0, "cy": 0, "part": 2, "parts": 2, "l": l.slice(200)})
	# Built on a worker thread: shown once the job is done (finish_jobs waits for it).
	check(_instances(d) == 0, "the chunk isn't built on the spot (a worker thread does it)")
	d.finish_jobs()
	check(d.count() == 102, "the chunk's decoratives are kept: %d" % d.count())
	check(_instances(d) == 101, "one instance per grass and rock; a decorative without pictures draws nothing: %d" % _instances(d))
	check(_meshes(d) == 2, "one MultiMesh per decorative in the chunk: %d" % _meshes(d))

	d.set_options(true, 0.5)
	d.finish_jobs()
	var half := _instances(d)
	check(half > 30 and half < 75, "density 0.5 keeps about half: %d" % half)
	d.set_options(true, 0.5)
	d.finish_jobs()
	check(_instances(d) == half, "and the same ones each time")
	d.set_options(true, 1.0)
	d.finish_jobs()
	check(_instances(d) == 101, "back to all of them: %d" % _instances(d))

	d.handle({"t": "dec", "cx": 0, "cy": 0, "part": 1, "parts": 1, "l": {}})
	check(_instances(d) == 0, "an empty list (Factorio's {}) clears the chunk")

	# Malformed lists and messages must not stop the layer.
	d.handle({"t": "dec", "cx": 1, "cy": 0, "part": 1, "parts": 1, "l": [1, 2, 3]})
	d.handle({"t": "dec", "cx": "x", "cy": null, "part": "a", "parts": -5, "l": "nope"})
	d.handle({"t": "dec", "cx": 1, "cy": 0, "part": 1, "parts": 1, "l": [99, 1, 1, 1, 1, 400, -3, 1]})
	d.handle({"t": "dprotos", "l": [[], ["x"], 5, null]})
	d.handle({"t": "dec", "cx": 1, "cy": 0, "part": 1, "parts": 1, "l": [1, 2, 3, 4]})
	d.finish_jobs()
	check(_instances(d) == 1, "a good list after bad ones draws: %d" % _instances(d))

	# A chunk the world no longer has is dropped.
	world.chunks.erase(Vector2i(1, 0))
	d._sweep = 10.0
	d._process(0.0)
	await get_tree().process_frame
	check(_instances(d) == 0 and d.count() == 0, "an unloaded chunk's decoratives go")

	print("decor test: %s" % ("all passed" if fails == 0 else "%d failed" % fails))
	get_tree().quit(1 if fails > 0 else 0)


func _instances(d: Node) -> int:
	var n := 0
	for inst in _all(d):
		if not inst.is_queued_for_deletion() and not inst.get_parent().is_queued_for_deletion():
			n += inst.multimesh.instance_count
	return n


func _meshes(d: Node) -> int:
	var n := 0
	for inst in _all(d):
		if not inst.get_parent().is_queued_for_deletion():
			n += 1
	return n


func _all(node: Node) -> Array:
	var out := []
	for child in node.get_children():
		if child is MultiMeshInstance3D:
			out.append(child)
		out.append_array(_all(child))
	return out
