extends RefCounted
## Factorio's rich text (chat, train stop names, labels, map tags): [item=iron-plate] and the other
## icon tags (fluid, entity, recipe, technology, virtual-signal, tile, planet, space-location,
## quality, item-group, img=type/name) drawn as their icons, [color=…]…[/color] (names, r,g,b in
## 0-1 or 0-255, #rrggbb), [font=default-bold]…[/font], [gps=x,y,surface] as Factorio's map pin and
## the position (a link: clicking it looks there and pings the map), and [train=id] /
## [train-stop=unit] as their icons. Unknown tags stay as written, as Factorio leaves them.
##
## `fill` writes into a RichTextLabel (links come back through its meta_clicked as
## "gps:x,y,surface"); `plain` gives the text without tags; `draw` draws it on a CanvasItem (the
## map's tags).

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")
const ItemIcons := preload("res://scripts/world/item_icons.gd")

## Factorio's named colours (the chat's player colours).
const COLORS := {
	"default": Color(1.0, 0.63, 0.259), "red": Color(1.0, 0.166, 0.141), "green": Color(0.173, 0.824, 0.25),
	"blue": Color(0.343, 0.683, 1.0), "orange": Color(1.0, 0.63, 0.259), "yellow": Color(1.0, 0.828, 0.231),
	"pink": Color(1.0, 0.5, 0.818), "purple": Color(0.821, 0.44, 0.998), "white": Color(0.9, 0.9, 0.9),
	"black": Color(0.5, 0.5, 0.5), "gray": Color(0.7, 0.7, 0.7), "brown": Color(0.757, 0.522, 0.371),
	"cyan": Color(0.335, 0.918, 0.866), "acid": Color(0.708, 0.996, 0.134),
}
const ICON_TAGS := ["item", "fluid", "entity", "recipe", "technology", "virtual-signal", "tile", "planet", "space-location",
	"quality", "item-group", "achievement", "space-platform", "armor", "special-item", "img"]
const GPS_COLOR := Color(0.55, 0.85, 1.0)

static var _tag := RegEx.create_from_string("\\[(/?)([a-z][a-z\\-\\.]*)(?:=([^\\]]*))?\\]")


## Tokens: {"t": "text", "s", "color" (Color or null), "font" ("" / "bold" / "semibold")},
## {"t": "icon", "kind", "name", "quality"}, {"t": "gps", "at": Vector2, "surface"},
## {"t": "train", "id"}, {"t": "train-stop", "id"}.
static func parse(text: String) -> Array:
	var out: Array = []
	var colors: Array = []
	var fonts: Array = []
	var at := 0
	for m in _tag.search_all(text):
		var closing := m.get_string(1) == "/"
		var tag := m.get_string(2)
		var value := m.get_string(3)
		var token = null
		var push = null  # [stack, value] to push after the text before the tag
		var pop: Array = []  # the stack to pop after it
		var known := true
		if (closing and (tag == "color" or tag == "font")) or tag == ".color" or tag == ".font":
			pop = colors if tag.ends_with("color") else fonts
		elif closing:
			known = false
		elif tag == "color":
			var c = color_of(value)
			known = c != null
			push = [colors, c]
		elif tag == "font":
			push = [fonts, "bold" if value.contains("bold") else "semibold" if value.contains("semibold") else ""]
		elif tag == "gps":
			var parts := value.split(",")
			known = parts.size() >= 2 and parts[0].strip_edges().is_valid_float() and parts[1].strip_edges().is_valid_float()
			if known:
				token = {"t": "gps", "at": Vector2(float(parts[0]), float(parts[1])), "surface": parts[2].strip_edges() if parts.size() > 2 else ""}
		elif tag == "train" or tag == "train-stop":
			known = value.strip_edges().is_valid_int()
			if known:
				token = {"t": tag, "id": int(value)}
		elif ICON_TAGS.has(tag):
			var name := value
			var quality := ""
			var comma := value.find(",")
			if comma >= 0:
				name = value.substr(0, comma)
				var rest := value.substr(comma + 1)
				if rest.begins_with("quality="):
					quality = rest.substr(8)
			var kind := tag
			if tag == "img":
				var slash := name.find("/")
				kind = name.substr(0, slash) if slash > 0 else "item"
				name = name.substr(slash + 1) if slash > 0 else name
			known = name != ""
			if known:
				token = {"t": "icon", "kind": kind, "name": name, "quality": quality}
		else:
			known = false
		if not known:
			continue
		if m.get_start() > at:
			out.append(_text(text.substr(at, m.get_start() - at), colors, fonts))
		if token != null:
			out.append(token)
		if push != null:
			(push[0] as Array).append(push[1])
		if not pop.is_empty():
			pop.pop_back()
		at = m.get_end()
	if at < text.length():
		out.append(_text(text.substr(at), colors, fonts))
	return out


static func _text(s: String, colors: Array, fonts: Array) -> Dictionary:
	return {"t": "text", "s": s, "color": colors.back() if not colors.is_empty() else null, "font": fonts.back() if not fonts.is_empty() else ""}


## A [color=…] value: a name, "r,g,b" (0-1, or 0-255 when any is over 1) or "#rrggbb"; null when it
## isn't one.
static func color_of(value: String):
	value = value.strip_edges()
	if COLORS.has(value):
		return COLORS[value]
	if value.begins_with("#") and Color.html_is_valid(value):
		return Color.html(value)
	var parts := value.split(",")
	if parts.size() >= 3 and parts[0].strip_edges().is_valid_float():
		var c := Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		if c.x > 1.0 or c.y > 1.0 or c.z > 1.0:
			c /= 255.0
		return Color(c.x, c.y, c.z)
	return null


## The icon a rich text tag (or Factoriopedia) shows for a kind of thing; null without one.
static func icon(kind: String, name: String) -> Texture2D:
	match kind:
		"technology":
			return GuiAssets.tech_icon(name)
		"quality":
			return ItemIcons.texture_for("quality-" + name)
		"item-group":
			return GuiAssets.group_icon(name)
		"entity", "planet", "space-location", "space-platform", "tile", "achievement":
			var t := ItemIcons.texture_for(name)
			if t == null and kind == "entity":
				t = GuiAssets.core_sprite("icons/entity/%s.png" % name)
			if t != null:
				return t
			return Kit.item_icon(name) if kind != "space-platform" else ItemIcons.texture_for("space-platform-hub")
		"train":
			return ItemIcons.texture_for("locomotive")
		"train-stop":
			return ItemIcons.texture_for("train-stop")
		"gps":
			return GuiAssets.core_sprite("gps-map-placeholder.png")
	return Kit.item_icon(name)


## The text without tags: icons by their names in brackets, as plain text shows them.
static func plain(text: String) -> String:
	var out := ""
	for tok in parse(text):
		out += plain_token(tok)
	return out


static func has_tags(text: String) -> bool:
	return text.contains("[") and not parse(text).all(func(tok) -> bool: return tok["t"] == "text" and tok["color"] == null and tok["font"] == "")


## Appends the text to a RichTextLabel (its own bbcode off): coloured runs, fonts, icons the size
## of the line, gps links (meta "gps:x,y,surface"). `color` is the text's colour where no tag sets one.
static func fill(label: RichTextLabel, text: String, color := Color.WHITE, icon_px := 0) -> void:
	var size := icon_px if icon_px > 0 else label.get_theme_font_size("normal_font_size") + Kit.px(4)
	for tok in parse(text):
		match str(tok["t"]):
			"text":
				var c = tok["color"]
				label.push_color(c if c is Color else color)
				var f := str(tok["font"])
				var font := Kit.font(f) if f != "" else null
				if font != null:
					label.push_font(font)
				label.add_text(str(tok["s"]))
				if font != null:
					label.pop()
				label.pop()
			"icon":
				var t := icon(str(tok["kind"]), str(tok["name"]))
				if t != null:
					label.add_image(t, size, size, Color.WHITE, INLINE_ALIGNMENT_CENTER, Rect2(), null, false, Kit.pretty(str(tok["name"])))
				else:
					label.add_text("[%s]" % Kit.pretty(str(tok["name"])))
				var q := str(tok["quality"])
				if q != "" and q != "normal":
					var qt := icon("quality", q)
					if qt != null:
						label.add_image(qt, size / 2, size / 2, Color.WHITE, INLINE_ALIGNMENT_BOTTOM)
			"gps":
				var at: Vector2 = tok["at"]
				label.push_meta("gps:%s,%s,%s" % [at.x, at.y, str(tok["surface"])])
				var pin := icon("gps", "")
				if pin != null:
					label.add_image(pin, size, size, Color.WHITE, INLINE_ALIGNMENT_CENTER)
				label.push_color(GPS_COLOR)
				label.push_underline()
				label.add_text("[%d, %d%s]" % [roundi(at.x), roundi(at.y), (", " + str(tok["surface"])) if str(tok["surface"]) not in ["", "nauvis"] else ""])
				label.pop()
				label.pop()
				label.pop()
			_:
				var t := icon(str(tok["t"]), "")
				if t != null:
					label.add_image(t, size, size, Color.WHITE, INLINE_ALIGNMENT_CENTER)
				label.add_text(str(int(tok["id"])))


## A RichTextLabel showing `text`, sized to it.
static func label(text: String, color := Color.WHITE, font_size := 0) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = false
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	if font_size > 0:
		l.add_theme_font_size_override("normal_font_size", font_size)
	var f := Kit.font("regular")
	if f != null:
		l.add_theme_font_override("normal_font", f)
	fill(l, text, color)
	return l


## A name players write (train stops, train and logistic groups, interrupts: G8) as a control: a plain
## Label of that theme variation when it has no tags, else a RichTextLabel drawing its icons, bold for
## a heading or caption. `color` (if given) is the text's colour either way.
static func text_label(text: String, variation := "", color: Variant = null) -> Control:
	if not has_tags(text):
		var plain_label := Kit.label(text, variation)
		if color is Color:
			plain_label.add_theme_color_override("font_color", color)
		return plain_label
	var heading := variation in ["FHeading", "FCaption"]
	var c: Color = color if color is Color else (Kit.CAPTION if heading else Kit.WHITE)
	var l := RichTextLabel.new()
	l.bbcode_enabled = false
	l.fit_content = true
	l.scroll_active = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var f := Kit.font("bold" if heading else "regular")
	if f != null:
		l.add_theme_font_override("normal_font", f)
	if variation == "FCaption":
		l.add_theme_font_size_override("normal_font_size", Kit.px(18))
	fill(l, text, c)
	return l


## For places that draw one icon beside plain text (buttons, drop-down lists, menus): the first icon
## in the text (null without one) and the text without that tag; other tags as `plain` writes them.
static func icon_and_text(text: String) -> Array:
	var first: Texture2D = null
	var out := ""
	for tok in parse(text):
		if first == null and str(tok["t"]) == "icon":
			first = icon(str(tok["kind"]), str(tok["name"]))
			if first != null:
				continue
		out += plain_token(tok)
	out = out.strip_edges()
	if out == "" and first != null:
		out = plain(text)
	return [first, out]


## One token of `parse` as `plain` writes it.
static func plain_token(tok: Dictionary) -> String:
	match str(tok["t"]):
		"text":
			return str(tok["s"])
		"icon":
			return "[%s]" % Kit.pretty(str(tok["name"]))
		"gps":
			return "[%d, %d]" % [roundi((tok["at"] as Vector2).x), roundi((tok["at"] as Vector2).y)]
	return "[%s %d]" % [str(tok["t"]), int(tok["id"])]


## Gives the entries of a drop-down or menu with rich text names their icon and plain text;
## `names[i]` is entry i's name.
static func decorate_items(menu: Object, names: Array) -> void:
	var popup: PopupMenu = menu if menu is PopupMenu else (menu as OptionButton).get_popup()
	if menu is OptionButton:
		(menu as OptionButton).add_theme_constant_override("icon_max_width", Kit.px(20))
	for i in mini(names.size(), popup.get_item_count()):
		var it := icon_and_text(str(names[i]))
		if it[0] != null:
			menu.set_item_text(i, str(it[1]))
			menu.set_item_icon(i, it[0])
			popup.set_item_icon_max_width(i, Kit.px(20))


## A Button showing a rich text name: its first icon and the rest as text.
static func decorate_button(b: Button, text: String) -> void:
	var it := icon_and_text(text)
	b.text = str(it[1])
	if it[0] != null:
		b.icon = it[0]
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", Kit.px(20))


## A "gps:x,y,surface" meta from fill: [position (tiles), surface name], or [] for anything else.
static func gps_of(meta) -> Array:
	var s := str(meta)
	if not s.begins_with("gps:"):
		return []
	var p := s.substr(4).split(",")
	if p.size() < 2:
		return []
	return [Vector2(float(p[0]), float(p[1])), p[2] if p.size() > 2 else ""]


## Draws the text on a CanvasItem from `pos` (the baseline's left end), icons the font's height;
## returns how wide it was.
static func draw(canvas: CanvasItem, font: Font, pos: Vector2, text: String, font_size: int, color: Color, outline := 0) -> float:
	var x := pos.x
	var h := float(font_size)
	for tok in parse(text):
		match str(tok["t"]):
			"text":
				var c = tok["color"]
				var s := str(tok["s"])
				if outline > 0:
					canvas.draw_string_outline(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, Color(0, 0, 0, 0.85))
				canvas.draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c if c is Color else color)
				x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			_:
				var kind := str(tok["kind"]) if tok["t"] == "icon" else str(tok["t"])
				var t := icon(kind, str(tok.get("name", "")))
				if t != null:
					canvas.draw_texture_rect(t, Rect2(x, pos.y - h * 0.85, h, h), false)
					x += h + 1.0
				if tok["t"] == "gps":
					var at: Vector2 = tok["at"]
					var s := "[%d, %d]" % [roundi(at.x), roundi(at.y)]
					canvas.draw_string(font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, GPS_COLOR)
					x += font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return x - pos.x


## How wide `draw` would draw it.
static func width(font: Font, text: String, font_size: int) -> float:
	var x := 0.0
	for tok in parse(text):
		if tok["t"] == "text":
			x += font.get_string_size(str(tok["s"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		else:
			x += font_size + 1.0
			if tok["t"] == "gps":
				var at: Vector2 = tok["at"]
				x += font.get_string_size("[%d, %d]" % [roundi(at.x), roundi(at.y)], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return x
