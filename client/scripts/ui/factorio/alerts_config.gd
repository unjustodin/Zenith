extends "res://scripts/ui/factorio/global_window.gd"
## Factorio's "Alerts configuration": a table of every kind of alert (Icon, Name, Muted, Disabled,
## Latest), sorted by clicking a column's header (again: the other way). Disabled kinds leave the
## alert bar and the icons over entities (alerts.gd's hidden_kinds); muted ones are kept for when
## alerts make sounds (the client's alerts are silent). Latest is how long since the client last
## saw that alert. Both choices are kept in settings.cfg [alerts].
##
## The bridge's character has no player, so these are the client's own settings, not
## LuaPlayer.mute_alert / disable_alert.

const Alerts := preload("res://scripts/ui/factorio/alerts.gd")
const Settings := preload("res://scripts/menu/settings.gd")

## Factorio's alert types in its order: [Factorio's name, picture, the alerts.gd kind it covers ("" none)].
const TYPES := [
	["Entity destroyed", "destroyed-icon.png", "destroyed"],
	["Entity being damaged", "danger-icon.png", "attack"],
	["Not enough construction robots", "not-enough-construction-robots-icon.png", "no_robots"],
	["Missing material for construction", "no-building-material-icon.png", "no_material"],
	["Missing repair packs", "not-enough-repair-packs-icon.png", "no_repair"],
	["Space platform cannot place tiles", "no-building-material-icon.png", ""],
	["Turret out of ammunition", "ammo-icon-red.png", "no_ammo"],
	["Turret engaged with the enemy", "warning-icon.png", "fire"],
	["Custom alert", "warning-icon.png", ""],
	["Not enough logistic network storage", "no-storage-space-icon.png", ""],
	["Train out of fuel", "fuel-icon-red.png", "train_fuel"],
	["Train cannot find path", "no-path-icon.png", "train_path"],
	["Not enough platform hub storage", "no-platform-storage-space-icon.png", "platform_storage"],
	["Asteroid collector blocked", "asteroid-collector-path-blocked-icon.png", "collector"],
	["Unclaimed items waiting", "unclaimed-cargo-icon.png", ""],
	["Not enough empty roboport robot slots", "no-roboport-storage-space-icon.png", ""],
	["Pipeline overextended", "fluid-icon-red.png", ""],
	["Fluids mixed", "fluid-icon-red.png", ""],
	["Enemy expansion base detected", "biter-base-icon.png", ""],
]
const COLUMNS := ["Icon", "Name", "Muted", "Disabled", "Latest"]
const WIDTHS := [40, 260, 56, 64, 72]

## The alert bar (alerts.gd), set by factorio_ui.gd.
var alerts: Node = null
## Column sorted by and which way.
var sort_by := "Icon"
var ascending := true

var _table := GridContainer.new()


func _ready() -> void:
	_init_frame("Alerts configuration", false)
	var deep: Array = Kit.deep_scroll(Kit.pxv(520, 28 * TYPES.size() + 32))
	body.add_child(deep[0])
	_table.columns = COLUMNS.size()
	_table.add_theme_constant_override("h_separation", 0)
	_table.add_theme_constant_override("v_separation", 0)
	(deep[1] as ScrollContainer).add_child(_table)


## The kinds the player switched off or muted (Factorio's names).
static func disabled() -> Array:
	var v = Settings.get_value("alerts", "disabled")
	return v if v is Array else []


static func muted() -> Array:
	var v = Settings.get_value("alerts", "muted")
	return v if v is Array else []


## Applies the saved choices to the alert bar.
func apply() -> void:
	if alerts == null:
		return
	var hidden: Array = Alerts.HIDDEN_BY_DEFAULT.duplicate()
	for t in TYPES:
		if disabled().has(t[0]) and str(t[2]) != "":
			hidden.append(str(t[2]))
	alerts.hidden_kinds = hidden


func set_flag(name: String, which: String, on: bool) -> void:
	var list: Array = (disabled() if which == "disabled" else muted()).duplicate()
	list.erase(name)
	if on:
		list.append(name)
	Settings.set_value("alerts", which, list)
	apply()
	rebuild()


func sort(column: String) -> void:
	ascending = not ascending if sort_by == column else true
	sort_by = column
	rebuild()


## Seconds since the client last saw that kind, or -1.
func _age(t: Array) -> float:
	if alerts == null or str(t[2]) == "":
		return -1.0
	var seen: Dictionary = alerts.get("last_seen") if alerts.get("last_seen") is Dictionary else {}
	if not seen.has(str(t[2])):
		return -1.0
	return (Time.get_ticks_msec() - int(seen[str(t[2])])) / 1000.0


static func age_text(s: float) -> String:
	if s < 0.0:
		return "never"
	if s < 60.0:
		return "%.1f s ago" % s
	if s < 3600.0:
		return "%d m ago" % int(s / 60.0)
	return "%d h ago" % int(s / 3600.0)


func rows() -> Array:
	var out: Array = []
	for i in TYPES.size():
		out.append([i, TYPES[i]])
	var key := func(r: Array):
		var t: Array = r[1]
		match sort_by:
			"Name":
				return str(t[0])
			"Muted":
				return 1 if muted().has(t[0]) else 0
			"Disabled":
				return 1 if disabled().has(t[0]) else 0
			"Latest":
				var a := _age(t)
				return a if a >= 0.0 else 1e12
		return int(r[0])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		var ka = key.call(a)
		var kb = key.call(b)
		if ka == kb:
			return int(a[0]) < int(b[0])
		return ka < kb if ascending else ka > kb)
	return out


func rebuild() -> void:
	clear(_table)
	for i in COLUMNS.size():
		var h := Button.new()
		var c: String = COLUMNS[i]
		h.name = "Sort" + c
		h.text = ("▲ " if ascending else "▼ ") + c if c == sort_by else c
		h.flat = true
		h.alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.focus_mode = Control.FOCUS_NONE
		h.custom_minimum_size = Kit.pxv(WIDTHS[i], 24)
		h.add_theme_font_override("font", Kit.font("bold"))
		h.add_theme_color_override("font_color", Kit.CAPTION)
		h.add_theme_color_override("font_hover_color", Kit.ORANGE)
		h.pressed.connect(func() -> void: sort(c))
		_table.add_child(h)
	for r in rows():
		var t: Array = r[1]
		var name: String = t[0]
		var icon := TextureRect.new()
		icon.texture = GuiAssets.core_sprite("icons/alerts/" + str(t[1]))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Kit.pxv(WIDTHS[0], 28)
		_table.add_child(icon)
		var l := Kit.label(name)
		l.custom_minimum_size.x = Kit.px(WIDTHS[1])
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_table.add_child(l)
		for which in ["muted", "disabled"]:
			var box := MenuKit.checkbox("", (muted() if which == "muted" else disabled()).has(name))
			box.name = "%s_%s" % [which, name]
			box.custom_minimum_size.x = Kit.px(WIDTHS[2 if which == "muted" else 3])
			box.toggled.connect(func(on: bool) -> void: set_flag.call_deferred(name, which, on))
			_table.add_child(box)
		var age := Kit.label(age_text(_age(t)))
		age.custom_minimum_size.x = Kit.px(WIDTHS[4])
		age.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		age.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_table.add_child(age)
