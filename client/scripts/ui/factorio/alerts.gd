extends HBoxContainer
## Factorio's alert bar (bottom right, over the shortcut bar): one button per kind of alert with
## Factorio's alert picture (core/graphics/icons/alerts) and how many there are; its tooltip says
## what is wrong in Factorio's words and lists the entities by kind. Clicking one looks at its
## entities in remote view, one after another, as Factorio's alert buttons do. alert_icons.gd puts
## the same pictures over the entities in the world.
##
## The alerts come from the mod (`al`, alerts.lua: LuaPlayer.get_alerts needs a player, so the mod
## works them out for the force). With an older mod that doesn't send them, the client's own
## guesses stand in: machines without power (`pw`) and damaged buildings (`hp`).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const AlertIcons := preload("res://scripts/ui/factorio/alert_icons.gd")

## Look at a position (tiles) in remote view.
signal show_at(at: Vector2)
## Something to say in the HUD's message line.
signal say(text: String)
## An alert on another surface: look at it on that surface's map (the 3D world is the character's).
signal show_on_surface(at: Vector2, si: int)

const REFRESH := 0.5
## Kinds the bar leaves out unless `hidden_kinds` is changed. Factorio has no "output full" alert,
## and on a big base it fires for hundreds of machines; the mod still sends it.
const HIDDEN_BY_DEFAULT := ["output_full"]
## Entity statuses Factorio draws only as an icon over the entity, never in its alert list (H5: the bar
## listed them, so the client showed alerts the game didn't): icons yes, bar no.
const STATUS_ONLY := ["no_power", "unplugged", "low_power", "no_fuel"]
## Types whose damage isn't the player's alert: enemies and nature.
const NOT_OURS := ["unit-spawner", "turret", "tree", "simple-entity", "resource", "cliff", "fish", "plant"]
## kind -> [picture, title, what Factorio's tooltip says (%d: how many; one or several)].
const KINDS := {
	"destroyed": ["destroyed-icon.png", "Entity destroyed", ["%d entity is destroyed.", "%d entities are destroyed."]],
	"attack": ["danger-icon.png", "Entity under attack", ["%d entity is being damaged.", "%d entities are being damaged."]],
	"fire": ["warning-icon.png", "Turret fire", ["%d turret is engaged with the enemy.", "%d turrets are engaged with the enemy."]],
	"no_ammo": ["ammo-icon-red.png", "Turret out of ammo", ["%d turret just ran out of ammunition.", "%d turrets just ran out of ammunition."]],
	"no_material": ["no-building-material-icon.png", "No material for construction",
		["%d entity is missing the material for construction.", "%d entities are missing the material for construction."]],
	"no_robots": ["not-enough-construction-robots-icon.png", "Not enough construction robots",
		["%d entity is missing construction robots.", "%d entities are missing construction robots."]],
	"no_repair": ["not-enough-repair-packs-icon.png", "Not enough repair packs",
		["%d entity is missing repair packs.", "%d entities are missing repair packs."]],
	"train_fuel": ["fuel-icon-red.png", "Train out of fuel", ["Train out of fuel.", "%d trains out of fuel."]],
	"train_path": ["no-path-icon.png", "Train has no path", ["Train cannot find path to destination.", "%d trains cannot find a path to their destination."]],
	"platform_path": ["no-path-icon.png", "Platform has no path", ["Space platform cannot find a path.", "%d space platforms cannot find a path."]],
	"platform_storage": ["no-platform-storage-space-icon.png", "Platform hub full",
		["Not enough platform hub storage space available.", "%d platform hubs are out of storage space."]],
	"collector": ["asteroid-collector-path-blocked-icon.png", "Asteroid collector blocked",
		["%d asteroid collector can't collect.", "%d asteroid collectors can't collect."]],
	"launch": ["destination-full-icon.png", "Rocket can't launch", ["%d rocket silo can't launch.", "%d rocket silos can't launch."]],
	"no_power": ["electricity-icon-red.png", "No power", ["%d entity has no power.", "%d entities have no power."]],
	"unplugged": ["electricity-icon-unplugged.png", "Not connected to power", ["%d entity isn't connected to an electric network.",
		"%d entities aren't connected to an electric network."]],
	"low_power": ["electricity-icon-red.png", "Low power", ["%d entity has low power.", "%d entities have low power."]],
	"no_fuel": ["fuel-icon-red.png", "No fuel", ["%d entity is out of fuel.", "%d entities are out of fuel."]],
	"output_full": ["destination-full-icon.png", "Output full", ["%d entity has its output full.", "%d entities have their output full."]],
	# The client's own, for an older mod:
	"damaged": ["danger-icon.png", "Damaged", ["%d entity is damaged.", "%d entities are damaged."]],
}

## A button whose tooltip is Factorio's (title, lines) from its "tip" meta. It draws its alert picture
## itself, square and at half its 64 pixels (the mipmap that is exactly that size, so it stays crisp),
## and how many there are in the bottom-right corner in the slots' count font, as Factorio's alert
## buttons do; Godot's own icon and text sat on top of each other in the middle.
class AlertButton extends Button:
	const K := preload("res://scripts/ui/factorio/kit.gd")
	## The picture's side: Factorio's 64-pixel alert pictures at half size.
	const ICON := 32

	var picture: Texture2D = null
	var count := 0

	func _make_custom_tooltip(_for_text: String) -> Object:
		var tip = get_meta("tip", null)
		if tip is Array and tip.size() == 2:
			return K.tooltip(str(tip[0]), tip[1])
		return null

	func _draw() -> void:
		var side := float(K.px(ICON))
		if picture != null:
			draw_texture_rect(picture, Rect2(((size - Vector2(side, side)) * 0.5).round(), Vector2(side, side)), false)
		if count > 1:
			var f := K.font("bold")
			var fs := K.px(13)
			var text := K.count_text(count)
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2(size.x - w - K.px(3), size.y - K.px(3))
			draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, K.px(3), Color(0, 0, 0, 0.9))
			draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


var player: Node = null
var model = null
## Alert kinds not shown on the bar or over the entities (HIDDEN_BY_DEFAULT to start with).
var hidden_kinds: Array = HIDDEN_BY_DEFAULT.duplicate()
## kind -> Time.get_ticks_msec() when it was last there (the Alerts configuration's "Latest").
var last_seen := {}

var _buttons := {}  # kind -> Button
var _lists := {}  # kind -> [{"position", "si", "name", "unit", "subject"}]
var _counts := {}  # kind -> how many
var _next := {}  # kind -> which entity a click looks at next
var _timer := 0.0
var _icons: AlertIcons = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", Kit.px(4))
	if model != null:
		model.alerts_changed.connect(_refresh)


static func texture(kind: String) -> Texture2D:
	var k: Array = KINDS.get(kind, KINDS["attack"])
	return GuiAssets.core_sprite("icons/alerts/" + str(k[0]))


func _button(kind: String) -> AlertButton:
	if _buttons.has(kind):
		return _buttons[kind]
	var b := AlertButton.new()
	b.theme_type_variation = "FSlotButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Kit.pxv(Kit.SLOT, Kit.SLOT)
	b.picture = texture(kind)
	b.texture_filter = Kit.ICON_FILTER
	b.tooltip_text = kind
	b.pressed.connect(look.bind(kind))
	add_child(b)
	_buttons[kind] = b
	return b


## Looks at the kind's next entity, as a click on its button does.
func look(kind: String) -> void:
	var list: Array = _lists.get(kind, [])
	if list.is_empty():
		return
	var i := int(_next.get(kind, 0)) % list.size()
	_next[kind] = i + 1
	var e: Dictionary = list[i]
	var here := int(model.character_si) if model != null and model.get("character_si") != null else 0
	if int(e.get("si", 0)) != 0 and here != 0 and int(e["si"]) != here:
		show_on_surface.emit(e["position"], int(e["si"]))
		return
	show_at.emit(e["position"])


## What the button's tooltip says: the sentence, then the entities by kind with how many.
func tooltip_lines(kind: String) -> Array:
	var list: Array = _lists.get(kind, [])
	var n := int(_counts.get(kind, list.size()))
	var k: Array = KINDS.get(kind, ["", kind, ["%d", "%d"]])
	var sentence: String = k[2][0] if n == 1 else k[2][1]
	var lines: Array = [[sentence % n if sentence.contains("%d") else sentence]]
	var by_name := {}
	var order: Array = []
	for e in list:
		var key := str(e["name"]) + ("|" + str(e["subject"]) if kind in ["no_material", "no_robots"] else "")
		if not by_name.has(key):
			by_name[key] = 0
			order.append(key)
		by_name[key] = int(by_name[key]) + 1
	for key in order:
		var name := str(key).get_slice("|", 0)
		var subject := str(key).get_slice("|", 1) if str(key).contains("|") else ""
		var text := "%s × %d" % [Kit.entity_name(name), int(by_name[key])]
		if subject != "":
			text += " (needs %s)" % Kit.pretty(subject)
		lines.append([text, name])
	if n > list.size():
		lines.append(["and %d more" % (n - list.size()), "", Kit.DISABLED_TEXT])
	lines.append(["Click: look at it" + (" (again: the next one)" if list.size() > 1 else ""), "", Kit.DISABLED_TEXT])
	return lines


func _process(delta: float) -> void:
	if _icons == null and player != null and player.get_parent() != null:
		_icons = AlertIcons.new()
		_icons.name = "AlertIcons"
		_icons.world = player.get("world")
		_icons.movers = player.get("movers")
		player.get_parent().add_child(_icons)
		_refresh()
	if model != null and model.alerts_known:
		return
	_timer -= delta
	if _timer > 0.0 or player == null:
		return
	_timer = REFRESH
	_guess()


## The mod's alerts (`al`).
func _refresh() -> void:
	if model == null or not model.alerts_known:
		return
	var lists := {}
	var counts := {}
	for a in model.alerts:
		lists[a["kind"]] = a["entities"]
		counts[a["kind"]] = a["count"]
	_show(lists, counts)


## With an older mod: what the client knows (no power from `pw`, damage from `hp`).
func _guess() -> void:
	var world = player.get("world")
	if world == null:
		return
	var parent: Node = player.get_parent()
	var power = parent.get_node_or_null("FluidsPower") if parent != null else null
	var combat = player.get("combat")
	var found := {"no_power": [], "damaged": []}
	if power != null:
		for unit in power.unpowered:
			if power.has_no_power(int(unit)) and world.entities.has(unit):
				var r = world.entities[unit]
				found["no_power"].append({"position": r.pos, "si": 0, "name": _proto_name(world, r), "unit": int(unit), "subject": ""})
	var health = combat.get("_health") if combat != null else null
	if health is Dictionary:
		for unit in health:
			var r = world.entities.get(unit)
			if r == null or float(health[unit]) >= 1.0:
				continue
			var proto = world.protos.entity(r.proto_id)
			if proto != null and not NOT_OURS.has(proto.type):
				found["damaged"].append({"position": r.pos, "si": 0, "name": proto.name, "unit": int(unit), "subject": ""})
	var counts := {}
	for k in found:
		counts[k] = (found[k] as Array).size()
	_show(found, counts)


static func _proto_name(world, r) -> String:
	var proto = world.protos.entity(r.proto_id)
	return proto.name if proto != null else ""


func _show(lists: Dictionary, counts: Dictionary) -> void:
	for kind in counts:
		if int(counts[kind]) > 0:
			last_seen[kind] = Time.get_ticks_msec()
	if not hidden_kinds.is_empty():
		lists = lists.duplicate()
		counts = counts.duplicate()
		for kind in hidden_kinds:
			lists.erase(kind)
			counts.erase(kind)
	var icon_lists := lists
	lists = lists.duplicate()
	counts = counts.duplicate()
	for kind in STATUS_ONLY:
		lists.erase(kind)
		counts.erase(kind)
	_lists = lists
	_counts = counts
	var order := 0
	for kind in KINDS:
		var list: Array = lists.get(kind, [])
		var n := int(counts.get(kind, list.size()))
		if n <= 0:
			if _buttons.has(kind):
				(_buttons[kind] as Button).visible = false
			continue
		var b: AlertButton = _button(str(kind))
		b.visible = true
		move_child(b, order)
		order += 1
		if b.count != n:
			b.count = n
			b.queue_redraw()
		b.set_meta("tip", [str(KINDS[kind][1]), tooltip_lines(str(kind))])
		b.tooltip_text = str(KINDS[kind][1])
	if _icons != null:
		_icons.show_alerts(icon_lists, int(model.character_si) if model != null and model.get("character_si") != null else 0)
