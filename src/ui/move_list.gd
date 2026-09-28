extends Control
## The four move slots, plus the Mega toggle.
##
## A 2x2 grid of slots showing name / type / PP, a cursor moved with the D-pad,
## and one line of detail (power, accuracy, category) for the highlighted move.
## `chosen(index)` fires on A; `cancelled()` on B.
##
## PP IS THE GATE, NOT THE DISPLAY. A slot at 0 PP is dimmed *and*
## [method _confirm] refuses it, because `BattleEngine.submit_action` also refuses
## it -- a UI that let you pick a 0-PP move would silently stall the turn.
##
## THE MEGA TOGGLE (DATA_CONTRACT 11.2). Mega Evolution is not an action of its
## own: it rides along with the move as `{"kind":"move","move_index":i,"mega":true}`
## and resolves at the start of the turn, before any move. So this is a toggle you
## arm before picking a move, not a fifth button. It is drawn only when
## `BattleEngine.can_mega_evolve()` says yes -- which for the vertical slice is
## never, since the Key Stone arrives in Hearthome after gym 3 and Roark is gym 1.

signal chosen(move_index: int, mega: bool)
signal cancelled()

const UI := preload("res://src/ui/ui_kit.gd")
const Items := preload("res://src/battle/items.gd")

const SLOT_W := 118.0
const SLOT_H := 22.0
const ORIGIN := Vector2(6, 136)

var engine: RefCounted = null
var index: int = 0
var mega_armed: bool = false

var _slots: Array = []          # Array[Dictionary] {frame, name, meta}
var _detail: Label
var _mega: Label
var _moves: Array = []          # the move Dictionaries currently shown


func _ready() -> void:
	name = "MoveList"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	for i in 4:
		var col := i % 2
		var row := i / 2
		var rect := Rect2(ORIGIN + Vector2(col * (SLOT_W + 6), row * (SLOT_H + 3)),
			Vector2(SLOT_W, SLOT_H))
		var frame := UI.panel(self, rect, "Slot%d" % i)
		_slots.append({
			"frame": frame,
			"name": UI.label(frame, "-", Vector2(5, 2), UI.FONT, UI.TEXT, 78),
			"meta": UI.label(frame, "", Vector2(5, 11), UI.FONT, UI.TEXT_DIM, 108),
		})
	_detail = UI.label(self, "", Vector2(8, 184), UI.FONT, UI.TEXT_DIM, 180)
	_mega = UI.label(self, "", Vector2(188, 184), UI.FONT, UI.ACCENT, 60,
		HORIZONTAL_ALIGNMENT_RIGHT)
	visible = false


func bind(battle_engine: RefCounted) -> void:
	engine = battle_engine


## Show the menu for the player's active Pokemon and take the cursor.
func open() -> void:
	if engine == null:
		return
	_moves = (engine.active(0) as Dictionary).get("moves", [])
	index = _first_usable()
	mega_armed = false
	visible = true
	refresh()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func refresh() -> void:
	if _slots.is_empty():
		return
	for i in 4:
		var slot: Dictionary = _slots[i]
		var frame: Control = slot["frame"]
		var name_label: Label = slot["name"]
		var meta_label: Label = slot["meta"]
		if i >= _moves.size():
			frame.visible = false
			continue
		frame.visible = true
		var m: Dictionary = _moves[i]
		var pp := int(m.get("pp", 0))
		# A move a held item forbids is dimmed exactly like one with no PP, and for
		# the same reason: submit_action() refuses it, so offering it as selectable
		# would stall the turn on a keypress that looks legal.
		var out_of_pp := pp <= 0 or not Items.allows_move(_mon(), m)
		var selected := i == index
		frame.color = UI.ACCENT if selected else UI.EDGE
		var body := frame.get_node_or_null("Inner") as ColorRect
		if body != null:
			body.color = UI.BG_SOLID if selected else UI.BG
		name_label.text = "%s%s" % ["> " if selected else "", String(m.get("name", "-"))]
		name_label.add_theme_color_override("font_color", UI.TEXT_DIM if out_of_pp else UI.TEXT)
		meta_label.text = "%s  %d/%d PP" % [
			String(m.get("type", "?")).to_upper(), pp, int(m.get("maxPp", 0))]
		meta_label.add_theme_color_override("font_color",
			UI.HP_LOW if out_of_pp else UI.TEXT_DIM)

	_detail.text = _detail_text()
	var can_mega := engine != null and bool(engine.can_mega_evolve(engine.active(0), 0))
	_mega.visible = can_mega
	_mega.text = "MEGA: ON" if mega_armed else "MEGA: off"


func _detail_text() -> String:
	if index < 0 or index >= _moves.size():
		return "No moves -- Struggle."
	var m: Dictionary = _moves[index]
	var power := int(m.get("power", 0))
	var acc: Variant = m.get("accuracy", null)
	return "%s  POW %s  ACC %s" % [
		String(m.get("category", "status")).to_upper(),
		"-" if power <= 0 else str(power),
		"-" if acc == null else str(int(acc))]


func _first_usable() -> int:
	for i in _moves.size():
		if int((_moves[i] as Dictionary).get("pp", 0)) > 0:
			return i
	return 0


## The Pokemon whose moves are on screen, or {} before bind().
func _mon() -> Dictionary:
	return {} if engine == null else (engine.active(0) as Dictionary)


func _confirm() -> void:
	if index < 0 or index >= _moves.size():
		return
	if int((_moves[index] as Dictionary).get("pp", 0)) <= 0:
		EventBus.dialogue_requested.emit(PackedStringArray(["There is no PP left for that move!"]))
		return
	var blocked := Items.blocks_move(_mon(), _moves[index])
	if not blocked.is_empty():
		EventBus.dialogue_requested.emit(PackedStringArray([blocked]))
		return
	chosen.emit(index, mega_armed)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var moved := false
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
		index = (index + 1) % maxi(_moves.size(), 1)
		moved = true
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
		index = (index - 1 + maxi(_moves.size(), 1)) % maxi(_moves.size(), 1)
		moved = true
	elif event.is_action_pressed(&"game_run") and engine != null \
			and bool(engine.can_mega_evolve(engine.active(0), 0)):
		mega_armed = not mega_armed
		moved = true
	elif event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_confirm()
		return
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
		return
	if moved:
		refresh()
		get_viewport().set_input_as_handled()
