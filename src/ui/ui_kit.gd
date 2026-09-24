extends RefCounted
## The four widgets the whole UI is built from. Static factories, no Theme
## resource, no .tscn, no font file.
##
## WHY NOT A Theme RESOURCE, AND WHY NOT _draw()
##
## * A `.tres` Theme would have to be imported before it resolves, and
##   `tools/run_tests.sh` runs `--import` precisely because imported resources do
##   not exist until it has. Building the UI out of plain `ColorRect` + `Label`
##   nodes means a headless `--script` run can instance every screen with no
##   import pass at all.
## * `draw_string()` needs a Font. `ThemeDB.fallback_font` can be null in a
##   headless run, and a null font is a hard error inside `_draw`, which cannot be
##   caught. `Label` resolves its own font lazily and simply renders nothing when
##   there is none, so the same code is safe both on screen and in the suite.
##
## THE VIEWPORT IS 256x192 (project.godot: the DS's native resolution, integer
## scaled to 1024x768). Every size in here is in those units, so [constant FONT]
## of 8 is a 32-pixel glyph on a 1024-wide window. Do not "fix" the small numbers.

## Base font size. The DS UI font is 8px tall and this is rendered at 4x.
const FONT := 8
## Slightly larger, for a Pokemon's name and the box that wants to be read first.
const FONT_BIG := 10

const BG := Color(0.09, 0.10, 0.13, 0.94)
const BG_SOLID := Color(0.09, 0.10, 0.13, 1.0)
const EDGE := Color(0.62, 0.66, 0.74, 1.0)
const TEXT := Color(0.94, 0.95, 0.97, 1.0)
const TEXT_DIM := Color(0.62, 0.65, 0.70, 1.0)
const ACCENT := Color(0.98, 0.80, 0.24, 1.0)
const HP_GOOD := Color(0.30, 0.83, 0.38, 1.0)
const HP_WARN := Color(0.97, 0.78, 0.20, 1.0)
const HP_LOW := Color(0.91, 0.27, 0.24, 1.0)
const HP_TRACK := Color(0.20, 0.22, 0.26, 1.0)


## A bordered box: an EDGE rect with a BG rect inset by one pixel. Two ColorRects
## rather than a StyleBox, so there is nothing to import and nothing to theme.
static func panel(parent: Node, rect: Rect2, node_name: String = "Panel",
		fill: Color = BG) -> Control:
	var frame := ColorRect.new()
	frame.name = node_name
	frame.color = EDGE
	frame.position = rect.position
	frame.size = rect.size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)

	var inner := ColorRect.new()
	inner.name = "Inner"
	inner.color = fill
	inner.position = Vector2.ONE
	inner.size = rect.size - Vector2(2, 2)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inner)
	return frame


## A single-line label. `width <= 0` means "as wide as the text wants".
static func label(parent: Node, text: String, pos: Vector2, size: int = FONT,
		color: Color = TEXT, width: float = -1.0,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if width > 0.0:
		l.size = Vector2(width, size + 4)
		l.clip_text = true
	parent.add_child(l)
	return l


## A multi-line label that wraps inside `size`.
static func wrapped(parent: Node, text: String, rect: Rect2, font_size: int = FONT,
		color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## An HP bar: a track plus a fill whose width is set by [method set_bar]. Returns
## the FILL, which is the node the caller keeps and resizes.
static func bar(parent: Node, rect: Rect2, node_name: String = "Bar") -> ColorRect:
	var track := ColorRect.new()
	track.name = node_name + "Track"
	track.color = HP_TRACK
	track.position = rect.position
	track.size = rect.size
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(track)

	var fill := ColorRect.new()
	fill.name = node_name
	fill.color = HP_GOOD
	fill.position = Vector2.ZERO
	fill.size = rect.size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	return fill


## Resize and recolour an HP fill from a 0..1 fraction. Green above 1/2, yellow
## above 1/5, red below -- the same three bands the games use.
static func set_bar(fill: ColorRect, fraction: float) -> void:
	if not is_instance_valid(fill):
		return
	var f := clampf(fraction, 0.0, 1.0)
	var track := fill.get_parent() as ColorRect
	var full: float = track.size.x if track != null else fill.size.x
	fill.size = Vector2(maxf(full * f, 0.0), fill.size.y)
	if f > 0.5:
		fill.color = HP_GOOD
	elif f > 0.2:
		fill.color = HP_WARN
	else:
		fill.color = HP_LOW


## "Lv18", uniformly, so the two HUD panels and the party list agree.
static func level_text(level: int) -> String:
	return "Lv%d" % level


## Title-case a hyphenated data slug: "rock-slide" -> "Rock Slide".
static func pretty(slug: String) -> String:
	if slug.is_empty():
		return ""
	var out := PackedStringArray()
	for part in slug.split("-"):
		out.append(part.capitalize())
	return String(" ").join(out)
