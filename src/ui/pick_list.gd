extends Control
## A scrolling, type-to-filter list. The one widget Custom Battle mode picks
## everything with: species, moves, abilities, natures, items, bosses, presets and
## its own options menu.
##
## WHY IT HANDLES RAW KEYCODES INSTEAD OF THE ui_* ACTIONS
## `project.godot` rebinds `ui_up`/`ui_down`/`ui_left`/`ui_right` to WASD, which
## replaces their arrow-key defaults outright. A list you filter by typing cannot
## also move its cursor on W and S -- "Wailord" would scroll instead of filtering.
## So navigation here is on the arrow keys, PageUp/PageDown and Home/End, read
## straight off the InputEventKey, and every printable character goes to the
## filter. The footer says so on screen, because a control scheme that differs
## from the rest of the game has to announce itself.
##
## ITEMS ARE `{id, label, note}`. `id` is whatever the caller wants back -- an int
## dex number, a move slug, an option name -- and travels through untouched;
## `label` is matched against the filter; `note` is the dim right-hand column
## (a type, a stat line, a level). Nothing in here interprets any of them.
##
## THE FILTER MATCHES label OR id, case-insensitively, as a substring. Matching
## the id is what lets a dex number find a species while its name is what the
## player sees.

signal picked(id: Variant)
signal cancelled()

const UI := preload("res://src/ui/ui_kit.gd")

## Rows drawn at once. 11 at a 11px pitch fills the panel exactly.
const ROWS := 11
const ROW_PITCH := 11.0
const PANEL := Rect2(6, 6, 244, 180)

var items: Array = []           ## the unfiltered item list
var index: int = 0              ## cursor into `_view`
var query: String = ""

var _view: Array = []           ## items matching `query`
var _top: int = 0               ## first visible row of `_view`
var _rows: Array = []           ## Array[Dictionary] {label, note}
var _title: Label = null
var _search: Label = null
var _footer: Label = null
var _empty: Label = null
var _searchable: bool = true


func _ready() -> void:
	name = "PickList"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# A full-screen opaque backing, not just the panel: the panel stops at y=186
	# and the screen underneath has a footer at y=178, so its bottom four pixels
	# used to poke out below the list and read as a rendering fault.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = UI.BG_SOLID
	backdrop.size = Vector2(256, 192)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var frame := UI.panel(self, PANEL, "Frame", UI.BG_SOLID)
	_title = UI.label(frame, "", Vector2(6, 4), UI.FONT_BIG, UI.ACCENT, 232)
	_search = UI.label(frame, "", Vector2(6, 17), UI.FONT, UI.TEXT_DIM, 232)
	for i in ROWS:
		var y := 30.0 + float(i) * ROW_PITCH
		_rows.append({
			"label": UI.label(frame, "", Vector2(8, y), UI.FONT, UI.TEXT, 156),
			"note": UI.label(frame, "", Vector2(166, y), UI.FONT, UI.TEXT_DIM, 70,
				HORIZONTAL_ALIGNMENT_RIGHT),
		})
	_empty = UI.label(frame, "", Vector2(8, 30), UI.FONT, UI.HP_WARN, 232)
	_footer = UI.label(frame, "", Vector2(6, 166), UI.FONT, UI.TEXT_DIM, 232)
	visible = false


## Show the list. `config`:
## [codeblock]
## {title: String, items: Array[{id, label, note}], selected: Variant,
##  searchable: bool, footer: String}
## [/codeblock]
## `selected` puts the cursor on that id if it is present -- so reopening a picker
## lands on what the slot already has rather than at the top.
func open(config: Dictionary) -> void:
	items = (config.get("items", []) as Array).duplicate()
	_searchable = bool(config.get("searchable", true))
	query = ""
	_title.text = String(config.get("title", ""))
	_footer.text = String(config.get("footer",
		"up/down move  enter pick  esc back" + ("  type to filter" if _searchable else "")))
	# Start at the top. The cursor is a property of THIS list, not of whatever was
	# picked last -- without the reset, opening the options menu after scrolling a
	# 1025-row species list lands on the bottom entry.
	index = 0
	_view.clear()               # a new list has no previously-held item to follow
	_rebuild()
	var want: Variant = config.get("selected", null)
	if want != null:
		for i in _view.size():
			var id: Variant = (_view[i] as Dictionary).get("id")
			if typeof(id) == typeof(want) and id == want:
				index = i
				break
	visible = true
	_refresh()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


## The item under the cursor, or `{}` when the filter matched nothing.
func current() -> Dictionary:
	if index < 0 or index >= _view.size():
		return {}
	return _view[index]


func match_count() -> int:
	return _view.size()


# --------------------------------------------------------------------------
# Filtering
# --------------------------------------------------------------------------

func _rebuild() -> void:
	# Follow the highlighted ITEM across a filter change rather than the row
	# number: clamping the index alone drags the cursor to the end of the list as
	# the matches narrow, which is what typing a filter does constantly.
	var held: Variant = null
	if index >= 0 and index < _view.size():
		held = (_view[index] as Dictionary).get("id")

	var needle := query.to_lower()
	_view.clear()
	for row: Variant in items:
		if not (row is Dictionary):
			continue
		var d: Dictionary = row
		if needle.is_empty() \
				or String(d.get("label", "")).to_lower().contains(needle) \
				or str(d.get("id", "")).to_lower().contains(needle):
			_view.append(d)

	index = 0
	if held != null:
		for i in _view.size():
			# Compare types first. Ids are homogeneous within one list but not
			# between lists, and `String == int` is a hard error in GDScript, not a
			# false -- so a stale id from the previous list would crash the rebuild.
			var id: Variant = (_view[i] as Dictionary).get("id")
			if typeof(id) == typeof(held) and id == held:
				index = i
				break
	_top = 0


func _refresh() -> void:
	if _rows.is_empty():
		return
	# Keep the cursor inside the window, scrolling by one row at the edges.
	if index < _top:
		_top = index
	elif index >= _top + ROWS:
		_top = index - ROWS + 1
	_top = clampi(_top, 0, maxi(_view.size() - ROWS, 0))

	for i in ROWS:
		var row: Dictionary = _rows[i]
		var label: Label = row["label"]
		var note: Label = row["note"]
		var at := _top + i
		if at >= _view.size():
			label.text = ""
			note.text = ""
			continue
		var item: Dictionary = _view[at]
		var selected := at == index
		label.text = "%s%s" % ["> " if selected else "  ", String(item.get("label", ""))]
		label.add_theme_color_override("font_color", UI.ACCENT if selected else UI.TEXT)
		note.text = String(item.get("note", ""))

	_empty.text = "" if not _view.is_empty() else "nothing matches that."
	if _searchable:
		_search.text = "find: %s_   %d/%d" % [query, _view.size(), items.size()]
	elif _view.size() > ROWS:
		# A scrollable list that cannot be filtered still has to say where you are.
		_search.text = "%d of %d" % [index + 1, _view.size()]
	else:
		_search.text = ""


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	var handled := true
	match key.keycode:
		KEY_UP:
			index = _step(-1)
		KEY_DOWN:
			index = _step(1)
		KEY_PAGEUP:
			index = _step(-ROWS)
		KEY_PAGEDOWN:
			index = _step(ROWS)
		KEY_HOME:
			index = 0
		KEY_END:
			index = maxi(_view.size() - 1, 0)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			var item := current()
			if not item.is_empty():
				get_viewport().set_input_as_handled()
				picked.emit(item.get("id"))
				return
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			cancelled.emit()
			return
		KEY_BACKSPACE:
			if _searchable and not query.is_empty():
				query = query.substr(0, query.length() - 1)
				_rebuild()
			else:
				get_viewport().set_input_as_handled()
				cancelled.emit()
				return
		_:
			handled = false

	if not handled:
		# Anything printable extends the filter. `key.unicode` is 0 for the
		# modifier and function keys, which is exactly the filter we want.
		var c := key.unicode
		if _searchable and c >= 33 and c < 127 and query.length() < 24:
			query += String.chr(c)
			_rebuild()
		else:
			return

	_refresh()
	get_viewport().set_input_as_handled()


func _step(delta: int) -> int:
	if _view.is_empty():
		return 0
	return clampi(index + delta, 0, _view.size() - 1)
