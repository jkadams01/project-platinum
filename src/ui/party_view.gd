extends Control
## The party list. Six rows: name, level, HP bar, HP numbers, status -- and the
## one column this game needs that the original does not, the cap marker.
##
## Two jobs, one screen:
##   * in the OVERWORLD it is read-only (X toggles it open, B closes it);
##   * in a BATTLE it is a chooser -- `picked(index)` fires on A, and a fainted or
##     already-active member is refused, because `BattleEngine.submit_action`
##     refuses those switches too and a UI that offered them would stall the turn.
##
## `AT CAP` on a row means that Pokemon is at or above the hard level cap and will
## gain **zero** EXP (DATA_CONTRACT 8). It is the single most important thing a
## player needs to know before choosing who to send out, so it is on the row
## rather than buried in a summary screen.

signal picked(index: int)
signal closed()

const UI := preload("res://src/ui/ui_kit.gd")
const Stats := preload("res://src/battle/stats.gd")
const Mega := preload("res://src/battle/mega.gd")

const ROW_H := 26.0

## Set by the battle screen. When null the list is read-only.
var engine: RefCounted = null
## Party index the cursor is on.
var index: int = 0
## When true, A emits `picked`. The overworld view leaves this false.
var choosing: bool = false

var _rows: Array = []      # Array[Dictionary]
var _title: Label
var _hint: Label
var _party: Array = []


func _ready() -> void:
	name = "PartyView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	UI.panel(self, Rect2(2, 2, 252, 188), "Frame", UI.BG_SOLID)
	_title = UI.label(self, "PARTY", Vector2(8, 6), UI.FONT_BIG, UI.ACCENT, 120)
	_hint = UI.label(self, "", Vector2(130, 7), UI.FONT, UI.TEXT_DIM, 118,
		HORIZONTAL_ALIGNMENT_RIGHT)

	for i in GameState.MAX_PARTY:
		var y := 20.0 + i * ROW_H
		var frame := UI.panel(self, Rect2(6, y, 244, ROW_H - 2), "Row%d" % i)
		_rows.append({
			"frame": frame,
			"name": UI.label(frame, "", Vector2(5, 2), UI.FONT_BIG, UI.TEXT, 104),
			"level": UI.label(frame, "", Vector2(112, 3), UI.FONT, UI.TEXT_DIM, 32),
			"bar": UI.bar(frame, Rect2(148, 6, 66, 5), "Hp%d" % i),
			"hp": UI.label(frame, "", Vector2(148, 13), UI.FONT, UI.TEXT, 66),
			"tag": UI.label(frame, "", Vector2(214, 8), UI.FONT, UI.ACCENT, 26,
				HORIZONTAL_ALIGNMENT_RIGHT),
		})
	visible = false


func bind(battle_engine: RefCounted) -> void:
	engine = battle_engine


## `as_chooser` = the battle's "switch to whom?" mode.
func open(as_chooser: bool = false) -> void:
	choosing = as_chooser
	_party = engine.party_of(0) if engine != null else GameState.party
	index = clampi(index, 0, maxi(_party.size() - 1, 0))
	if as_chooser:
		index = _first_switchable()
	visible = true
	refresh()


func close() -> void:
	visible = false
	choosing = false
	closed.emit()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if _rows.is_empty():
		return
	_title.text = "SWITCH TO" if choosing else "PARTY"
	_hint.text = ("A choose   B back" if choosing else "B close")
	var cap := int(engine.current_cap()) if engine != null else GameState.current_level_cap()
	var active := -1
	if engine != null:
		active = int((engine.sides[0] as Dictionary)["active"])

	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var frame: Control = row["frame"]
		if i >= _party.size():
			frame.visible = false
			continue
		frame.visible = true
		var mon: Dictionary = _party[i]
		var selected := i == index and visible
		frame.color = UI.ACCENT if selected else UI.EDGE
		var body := frame.get_node_or_null("Inner") as ColorRect
		if body != null:
			body.color = UI.BG_SOLID if selected else UI.BG

		var fainted := Stats.is_fainted(mon)
		var label_text := Stats.display_name(mon)
		if i == active:
			label_text = "* " + label_text
		if Mega.is_mega(mon):
			label_text += " (Mega)"
		(row["name"] as Label).text = label_text
		(row["name"] as Label).add_theme_color_override("font_color",
			UI.TEXT_DIM if fainted else UI.TEXT)
		(row["level"] as Label).text = UI.level_text(int(mon.get("level", 1)))

		var max_hp := maxi(int(mon.get("maxHp", 1)), 1)
		var hp := clampi(int(mon.get("hp", 0)), 0, max_hp)
		UI.set_bar(row["bar"], float(hp) / float(max_hp))
		(row["hp"] as Label).text = "%d/%d" % [hp, max_hp]

		var tag := ""
		if fainted:
			tag = "FNT"
		elif not String(mon.get("status", "")).is_empty():
			tag = String(mon["status"]).substr(0, 3).to_upper()
		elif int(mon.get("level", 1)) >= cap:
			tag = "CAP"
		(row["tag"] as Label).text = tag


func _first_switchable() -> int:
	var active := int((engine.sides[0] as Dictionary)["active"]) if engine != null else -1
	for i in _party.size():
		if i != active and not Stats.is_fainted(_party[i]):
			return i
	return 0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var n := maxi(_party.size(), 1)
	if event.is_action_pressed(&"ui_down"):
		index = (index + 1) % n
	elif event.is_action_pressed(&"ui_up"):
		index = (index - 1 + n) % n
	elif event.is_action_pressed(&"ui_accept") and choosing:
		get_viewport().set_input_as_handled()
		if index < _party.size() and not Stats.is_fainted(_party[index]):
			picked.emit(index)
		else:
			EventBus.dialogue_requested.emit(PackedStringArray([
				"%s has no energy left to battle!" % Stats.display_name(_party[index])]))
		return
	elif event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"game_menu"):
		get_viewport().set_input_as_handled()
		close()
		return
	else:
		return
	refresh()
	get_viewport().set_input_as_handled()
