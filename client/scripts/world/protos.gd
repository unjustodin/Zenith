extends RefCounted
## Entity, tile and item prototypes from the mod's dictionaries, looked up by the small ids
## that world messages use.


class EntityProto:
	var id := 0
	var name := ""
	var type := ""
	## Selection box in tiles, relative to the entity position, for the north-facing entity.
	## x is east, y is south (Factorio's axes).
	var box_min := Vector2.ZERO
	var box_max := Vector2.ZERO
	var color := Color.GRAY
	var tile_size := Vector2i.ONE

	func size() -> Vector2:
		return box_max - box_min

	func center() -> Vector2:
		return (box_min + box_max) * 0.5


var entities := {}  # id -> EntityProto
var entities_by_name := {}  # name -> EntityProto
var tile_colors := PackedColorArray()
var tile_names := PackedStringArray()
## Per tile id: 1 water, 2 empty space (a space platform's surroundings: nothing to draw), else 0.
var tile_is_water := PackedByteArray()
var item_names := {}  # id -> name
var fluid_names := {}  # id -> name
var fluid_colors := {}  # name -> Color
var item_places := {}  # item name -> the entity it builds, when that has another name (rail)


func clear() -> void:
	entities.clear()
	entities_by_name.clear()
	item_names.clear()
	fluid_names.clear()
	fluid_colors.clear()
	item_places.clear()
	tile_colors = PackedColorArray()
	tile_names = PackedStringArray()
	tile_is_water = PackedByteArray()


## [id, name, type, x1, y1, x2, y2, r, g, b, tile_width, tile_height]
func add_entities(list: Array) -> void:
	for rec in list:
		if not (rec is Array) or rec.size() < 12:
			continue
		var p := EntityProto.new()
		p.id = int(rec[0])
		p.name = str(rec[1])
		p.type = str(rec[2])
		p.box_min = Vector2(float(rec[3]), float(rec[4]))
		p.box_max = Vector2(float(rec[5]), float(rec[6]))
		p.color = Color8(int(rec[7]), int(rec[8]), int(rec[9]))
		p.tile_size = Vector2i(int(rec[10]), int(rec[11]))
		entities[p.id] = p
		entities_by_name[p.name] = p


## [id, name, r, g, b]
func add_tiles(list: Array) -> void:
	for rec in list:
		if not (rec is Array) or rec.size() < 5:
			continue
		var id := int(rec[0])
		if tile_colors.size() <= id:
			tile_colors.resize(id + 1)
			tile_names.resize(id + 1)
			tile_is_water.resize(id + 1)
		var tile_name := str(rec[1])
		tile_colors[id] = Color8(int(rec[2]), int(rec[3]), int(rec[4]))
		tile_names[id] = tile_name
		tile_is_water[id] = 1 if _terrain().is_water_tile(tile_name) else (2 if tile_name.ends_with("empty-space") else 0)


## Water by its collision mask in Factorio's definitions (Gleba's wetlands, Aquilo's ocean), not
## only by name. Loaded, not preloaded: terrain_textures.gd preloads visuals.gd, which preloads this.
static func _terrain() -> GDScript:
	return load("res://scripts/world/terrain_textures.gd")


## [id, name] or [id, name, the entity it builds]
func add_items(list: Array) -> void:
	for rec in list:
		if rec is Array and rec.size() >= 2:
			item_names[int(rec[0])] = str(rec[1])
			if rec.size() >= 3:
				item_places[str(rec[1])] = str(rec[2])


## The entity an item builds, or null.
func placed_entity(item: String) -> EntityProto:
	return entities_by_name.get(item_places.get(item, item))


## [id, name, r, g, b]: the fluid's base colour.
func add_fluids(list: Array) -> void:
	for rec in list:
		if rec is Array and rec.size() >= 5:
			fluid_names[int(rec[0])] = str(rec[1])
			fluid_colors[str(rec[1])] = Color8(int(rec[2]), int(rec[3]), int(rec[4]))


func fluid_name(id: int) -> String:
	return fluid_names.get(id, "")


func item_name(id: int) -> String:
	return item_names.get(id, "")


func entity(id: int) -> EntityProto:
	return entities.get(id)


func tile_color(id: int) -> Color:
	if id >= 0 and id < tile_colors.size():
		return tile_colors[id]
	return Color.MAGENTA


func is_water(id: int) -> bool:
	return id >= 0 and id < tile_is_water.size() and tile_is_water[id] == 1


func is_void(id: int) -> bool:
	return id >= 0 and id < tile_is_water.size() and tile_is_water[id] == 2
