extends "res://scripts/ui/factorio/global_window.gd"
## Factorio's Bonuses window: a grid four cells wide, one cell per thing the force's research
## improves (the character, inserters, mining drills, labs, robots, each ammo category, each
## turret), with the things' icons along the top and their bonuses under them ("Inserter capacity:
## +1", "Damage: +80%"); empty cells fill the last row. From the mod's `bonus` (asked for when it
## opens).

const COLUMNS := 4
const CELL := Vector2(200, 112)

## Kind -> [Factorio's words, how the value reads: "+n" a count, "%" a fraction as +x%, "n" a count as is].
const LABELS := {
	"inserter_stack_size_bonus": ["Inserter capacity", "+n"],
	"bulk_inserter_capacity_bonus": ["Bulk inserter capacity", "+n"],
	"belt_stack_size_bonus": ["Belt stack size", "+n"],
	"mining_drill_productivity_bonus": ["Mining productivity", "%"],
	"laboratory_speed_modifier": ["Research speed", "%"],
	"laboratory_productivity_bonus": ["Research productivity", "%"],
	"worker_robots_speed_modifier": ["Movement speed", "%"],
	"worker_robots_storage_bonus": ["Cargo capacity", "+n"],
	"worker_robots_battery_modifier": ["Battery capacity", "%"],
	"following_robots_lifetime_modifier": ["Lifetime", "%"],
	"character_inventory_slots_bonus": ["Inventory slots", "+n"],
	"character_health_bonus": ["Health", "+n"],
	"manual_crafting_speed_modifier": ["Crafting speed", "%"],
	"manual_mining_speed_modifier": ["Mining speed", "%"],
	"train_braking_force_bonus": ["Braking force", "%"],
	"artillery_range_modifier": ["Range", "%"],
	"beacon_distribution_modifier": ["Distribution effectivity", "%"],
	"character_reach_distance_bonus": ["Reach distance", "+n"],
}

var _grid := GridContainer.new()


func _ready() -> void:
	_init_frame("Bonuses")
	var deep := Kit.panel("FDeepFrame")
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", Kit.px(2))
	_grid.add_theme_constant_override("v_separation", Kit.px(2))
	deep.add_child(_grid)
	body.add_child(deep)
	model.bonuses_changed.connect(rebuild)


func opened() -> void:
	model.request_bonuses()


## A bonus in Factorio's words: "Inserter capacity: +1", "Damage: +80%".
static func line_of(kind: String, value: float) -> String:
	var how := "%"
	var label := kind
	if LABELS.has(kind):
		label = LABELS[kind][0]
		how = LABELS[kind][1]
	elif kind.begins_with("ammo_damage:"):
		label = "Damage"
	elif kind.begins_with("gun_speed:"):
		label = "Shooting speed"
	elif kind.begins_with("turret_attack:"):
		return "Damage: +%d%%\n(Stacks with ammo bonuses)" % roundi(value * 100.0)
	if how == "+n":
		return "%s: +%d" % [label, roundi(value)]
	return "%s: %s%d%%" % [label, "+" if value >= 0.0 else "", roundi(value * 100.0)]


## Cells: bonuses of the same things together (robot speed and cargo, an ammo's damage and speed);
## the character's in one.
func cells() -> Array:
	var order: Array = []
	var by := {}
	for r in model.bonuses:
		var kind := str(r[0])
		var icons: Array = r[2]
		var key := "character" if kind.begins_with("character_") or kind.begins_with("manual_") else ",".join(PackedStringArray(icons))
		if key == "":
			key = kind
		if not by.has(key):
			by[key] = {"icons": ["character"] if key == "character" else icons, "lines": []}
			order.append(key)
		(by[key]["lines"] as Array).append(line_of(kind, float(r[1])))
	return order.map(func(k: String) -> Dictionary: return by[k])


func rebuild() -> void:
	clear(_grid)
	var shown := 0
	for cell in cells():
		var text := "\n".join(PackedStringArray(cell["lines"]))
		if search != "" and not text.to_lower().contains(search):
			continue
		_grid.add_child(_cell(cell["icons"], text))
		shown += 1
	for i in (COLUMNS - shown % COLUMNS) % COLUMNS + (COLUMNS if shown == 0 else 0):
		_grid.add_child(_cell([], ""))


func _cell(icons: Array, text: String) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color8(62, 62, 62) if text != "" else Color8(40, 40, 40)
	s.set_content_margin_all(Kit.px(8))
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Kit.pxv(CELL.x, CELL.y)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Kit.px(6))
	p.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.px(2))
	for icon in icons:
		var t := TextureRect.new()
		t.texture = GuiAssets.core_sprite("icons/entity/character.png") if str(icon) == "character" else Kit.item_icon(str(icon))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Kit.pxv(32, 32)
		t.texture_filter = Kit.ICON_FILTER
		row.add_child(t)
	v.add_child(row)
	if text != "":
		var l := Kit.label(text)
		l.add_theme_font_size_override("font_size", Kit.px(13))
		v.add_child(l)
	return p
