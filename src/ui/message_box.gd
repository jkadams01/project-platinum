extends Control
## The boxed narration voice: one queue of lines, advanced with the A button.
##
## THE ONLY LISTENER ON `EventBus.dialogue_requested`. Every stream that wants to
## say something -- `traversal.gd` announcing "The cracked rock broke apart!",
## the battle log, an NPC, a story event's `dialogue` step (DATA_CONTRACT 12.3) --
## emits that signal with a `PackedStringArray` and never touches this node. That
## is why the overworld and the battle engine can both talk without either one
## knowing a UI exists.
##
## INPUT LOCK OWNERSHIP, which is the subtle part. This box locks the player while
## it is open, but `SceneRouter` ALSO locks input for the whole duration of a
## battle. So on close it restores the lock to `SceneRouter.in_battle()` rather
## than clearing it: clearing it unconditionally would let the player walk around
## the overworld underneath a running battle the first time a battle message was
## dismissed.

## Emitted when the queue empties and the box closes.
signal closed()

const UI := preload("res://src/ui/ui_kit.gd")

## Lines still to show, oldest first.
var queue: PackedStringArray = PackedStringArray()
## When false the box neither locks input nor listens to the bus. The battle
## screen sets this: it owns its own log pacing and must not fight this node for
## the A button.
var autonomous: bool = true

var _body: Label = null
var _cursor: Label = null
var _open: bool = false


func _ready() -> void:
	name = "MessageBox"
	# A dismissed-but-alive box must not eat clicks or block the world behind it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var box := UI.panel(self, Rect2(4, 136, 248, 52), "Frame", UI.BG_SOLID)
	_body = UI.wrapped(box, "", Rect2(6, 5, 236, 42), UI.FONT_BIG)
	_cursor = UI.label(box, "▼", Vector2(236, 38), UI.FONT, UI.ACCENT)

	visible = false
	if not EventBus.dialogue_requested.is_connected(_on_dialogue):
		EventBus.dialogue_requested.connect(_on_dialogue)


func _exit_tree() -> void:
	if EventBus.dialogue_requested.is_connected(_on_dialogue):
		EventBus.dialogue_requested.disconnect(_on_dialogue)


func is_open() -> bool:
	return _open


## Queue lines and open. Tokens are expanded here (DATA_CONTRACT 12.4) so no
## caller has to know the player's name.
func show_lines(lines: PackedStringArray) -> void:
	for line in lines:
		queue.append(expand(line))
	if not _open:
		_open = true
		visible = true
		if autonomous:
			GameState.input_locked = true
	_render()


func show_line(line: String) -> void:
	show_lines(PackedStringArray([line]))


## Advance one line. Returns false once the box has closed.
func advance() -> bool:
	if not _open:
		return false
	if queue.size() > 1:
		queue.remove_at(0)
		_render()
		return true
	close()
	return false


func close() -> void:
	queue = PackedStringArray()
	_open = false
	visible = false
	if _body != null:
		_body.text = ""
	if autonomous:
		# SceneRouter owns the lock during a battle; do not steal it back.
		GameState.input_locked = SceneRouter.in_battle()
	closed.emit()


## DATA_CONTRACT 12.4 dialogue tokens. `{counterpart}` is Dawn when the player is
## Lucas and Lucas when the player is Dawn.
static func expand(line: String) -> String:
	var counterpart := "Dawn" if GameState.player_name == "Lucas" else "Lucas"
	return line \
		.replace("{player}", GameState.player_name) \
		.replace("{counterpart}", counterpart) \
		.replace("{rival}", "Barry")


func _render() -> void:
	if _body == null:
		return
	_body.text = queue[0] if not queue.is_empty() else ""
	if _cursor != null:
		_cursor.visible = queue.size() > 1


func _on_dialogue(lines: PackedStringArray) -> void:
	if not autonomous:
		return
	show_lines(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not autonomous:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
		advance()
		get_viewport().set_input_as_handled()
