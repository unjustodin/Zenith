extends Button
## One of Factorio's technology slots (72x100 at 100%): the technology_slot image for its state
## (yellow available, green researched, red not yet available; toggled is the highlighted look),
## its icon, the science packs it costs on the band at the bottom, the research progress bar when
## it is being researched and its place in the queue. `compact` draws a 40x40 slot-sized version
## for the queue.

const Kit := preload("res://scripts/ui/factorio/kit.gd")
const GuiAssets := preload("res://scripts/ui/factorio/gui_assets.gd")

const STATES := ["unavailable", "available", "researched"]  # by the mod's state 0/1/2

var tech := ""
var state := 1
var packs: Array = []  # science pack names
## 0..1 while it is being researched, else -1.
var progress := -1.0
## Its place in the research queue (1 = being researched), or 0.
var queue_place := 0
var compact := false
## Tooltip lines under the name, as Kit.tooltip takes them.
var tip_lines: Array = []
## The name shown (an infinite technology's with its level); the technology's own when empty.
var title := ""
## Drawn in the top right corner: "∞" for infinite technologies.
var level_text := ""
## The level shown in the badge on the strip over the packs (levelled technologies), or 0.
var level := 0
## The level range on the strip's right ("1 - ∞" for infinite ones), or "".
var level_range := ""
## The selected technology's large card in the tree.
var big := false

## The strip between the icon and the packs, and the level badge on it, by state (measured on
## Factorio's tree at 100%).
const STRIP := [Color8(141, 42, 41), Color8(117, 97, 24), Color8(0, 114, 25)]
const BADGE := [Color8(255, 215, 214), Color8(255, 238, 178), Color8(166, 255, 172)]
const STRIP_HEIGHT := 12


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	toggle_mode = true
	texture_filter = Kit.ICON_FILTER


func setup(name: String, new_state: int, new_packs: Array, small := false) -> void:
	tech = name
	state = clampi(new_state, 0, 2)
	packs = new_packs
	compact = small
	theme_type_variation = "FTech" + str(STATES[state]).capitalize()
	custom_minimum_size = Kit.pxv(40, 40) if compact else Kit.pxv(72, 100)
	tooltip_text = Kit.tech_name(name)
	queue_redraw()


func set_progress(value: float, place: int) -> void:
	if not is_equal_approx(value, progress) or place != queue_place:
		progress = value
		queue_place = place
		queue_redraw()


func _make_custom_tooltip(_for_text: String) -> Object:
	return Kit.tooltip(title if title != "" else Kit.tech_name(tech), tip_lines)


func _draw() -> void:
	var icon := GuiAssets.tech_icon(tech)
	var band := 0.0 if compact else float(Kit.px(20))
	var strip := 0.0 if compact else float(Kit.px(STRIP_HEIGHT))
	var area := Rect2(Vector2.ZERO, Vector2(size.x, size.y - band - strip)).grow(-Kit.px(4 if not compact else 3))
	var side := minf(area.size.x, area.size.y)
	var rect := Rect2(area.get_center() - Vector2(side, side) * 0.5, Vector2(side, side))
	if icon != null:
		draw_texture_rect(icon, rect, false)
	else:
		var pack := str(packs[0]) if not packs.is_empty() else "automation-science-pack"
		draw_texture_rect(Kit.item_icon(pack), rect.grow(-side * 0.15), false)
	if not compact:
		var strip_rect := Rect2(Kit.px(2), size.y - band - strip, size.x - Kit.px(4), strip)
		draw_rect(strip_rect, STRIP[state])
		_draw_level(strip_rect)
		var band_rect := Rect2(Kit.px(2), size.y - band, size.x - Kit.px(4), band - Kit.px(2))
		var box: StyleBox = get_theme_stylebox("panel", "FTechBand" + str(STATES[state]).capitalize())
		if box != null:
			draw_style_box(box, band_rect)
		var n := packs.size()
		var icon_side := float(Kit.px(16))
		var step := icon_side - Kit.px(4) if n > 4 else icon_side  # ingredient_icon_overlap
		var x := band_rect.get_center().x - (step * (n - 1) + icon_side) * 0.5
		for p in packs:
			draw_texture_rect(Kit.item_icon(str(p)), Rect2(x, band_rect.get_center().y - icon_side * 0.5, icon_side, icon_side), false)
			x += step
	if progress >= 0.0:
		var h := float(Kit.px(4))
		var y := size.y - band - strip - h - Kit.px(2)
		var bar := Rect2(Kit.px(4), y, size.x - Kit.px(8), h)
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(progress, 0.0, 1.0), h)), Color(0.2, 1.0, 0.2))
	if level_text != "" and not compact and level == 0:
		var lf := Kit.font("bold")
		var lfs := Kit.px(14)
		var lw := lf.get_string_size(level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs).x
		var lpos := Vector2(size.x - lw - Kit.px(6), Kit.px(16))
		draw_string_outline(lf, lpos, level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Kit.px(3), Color(0, 0, 0, 0.9))
		draw_string(lf, lpos, level_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Kit.YELLOW_TEXT)
	if queue_place > 0:
		var f := Kit.font("bold")
		var fs := Kit.px(14)
		var pos := Vector2(Kit.px(5), Kit.px(16))
		draw_string_outline(f, pos, str(queue_place), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Kit.px(3), Color(0, 0, 0, 0.9))
		draw_string(f, pos, str(queue_place), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Kit.WHITE)


## Factorio's level badge (a light box with the level in dark bold) at the strip's left, and an
## infinite technology's range ("1 - ∞") at its right.
func _draw_level(strip: Rect2) -> void:
	var f := Kit.font("bold")
	var fs := Kit.px(12)
	if level > 0:
		var text := str(level)
		var w := maxf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + Kit.px(10), Kit.px(26))
		var box := Rect2(strip.position, Vector2(w, strip.size.y))
		draw_rect(box, BADGE[state])
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(box.get_center().x - tw * 0.5, box.end.y - Kit.px(2)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color8(30, 30, 30))
	if level_range != "":
		var rw := f.get_string_size(level_range, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(strip.end.x - rw - Kit.px(4), strip.end.y - Kit.px(2)), level_range, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BADGE[state])
