extends Node3D
## Items lying on the ground near the camera (`gi`): models, icon cards or blocks (item_cards.gd), at
## the positions the mod sends twice a second. They don't move, so each complete update simply
## replaces the last one.

const ProtoDB := preload("res://scripts/world/protos.gd")
const ItemCards := preload("res://scripts/world/item_cards.gd")

## Just above the terrain, so the cards don't flicker into it.
const HEIGHT := 0.03

var protos: ProtoDB:
	set(value):
		protos = value
		_cards.protos = value

var _cards := ItemCards.new()
var _frame_tick := -1
var _groups := {}  # item id -> Array of Vector3, the update being received
var _yaws := {}  # item id -> Array of turns, by where each item lies
var _count := 0


func _ready() -> void:
	_cards.name = "Cards"
	add_child(_cards)


func reset() -> void:
	_cards.reset()
	_groups.clear()
	_frame_tick = -1
	_count = 0


func count() -> int:
	return _count


## One part of an update: {t: "gi", k: tick, part, parts, l: [item id, x, y, ...]}. The parts of
## an update share k; it is drawn once its last part is in.
func handle(msg: Dictionary) -> void:
	var k := int(msg.get("k", 0))
	if k != _frame_tick:
		_frame_tick = k
		_groups = {}
		_yaws = {}
	var list = msg.get("l")
	if list is Array:
		var i := 0
		while i + 2 < list.size():
			var id := int(list[i])
			if not _groups.has(id):
				_groups[id] = []
				_yaws[id] = []
			var x := int(list[i + 1])
			var y := int(list[i + 2])
			_groups[id].append(Vector3(x / 256.0, HEIGHT, y / 256.0))
			_yaws[id].append(ItemCards.yaw_for(x * 92821 + y))
			i += 3
	if int(msg.get("part", 1)) < int(msg.get("parts", 1)):
		return
	_cards.draw(_groups, _yaws)
	_count = 0
	for id in _groups:
		_count += (_groups[id] as Array).size()
