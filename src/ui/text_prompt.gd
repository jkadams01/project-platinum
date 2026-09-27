extends Control
## A one-line typed-text box: preset names and the RNG seed.
##
## Like `src/ui/pick_list.gd` it reads raw keycodes rather than the `ui_*` actions,
## because `project.godot` binds WASD to them and a text box cannot hand W to the
## menu. Enter submits, Escape cancels, Backspace deletes. `digits_only` is what
## the seed field uses; everything else accepts any printable character and
## whatever consumes the text is responsible for sanitising it
## (`BattleSpec.sanitize_name`).
##
## An EMPTY submission is still a submission -- clearing the seed back to "auto"
## is a real choice, so `submitted("")` fires rather than being swallowed as a
## cancel.

signal submitted(text: String)
signal cancelled()

const UI := preload("res://src/ui/ui_kit.gd")

const PANEL := Rect2(20, 66, 216, 58)
const MAX_LENGTH := 32

var text: String = ""

var _title: Label = null
var _value: Label = null
var _hint: Label = null
var _digits_only: bool = false


func _ready() -> void:
	name = "TextPrompt"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Dim whatever is behind: this is a small box over a full screen, and it owns
	# the keyboard while it is up.
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.size = Vector2(256, 192)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var frame := UI.panel(self, PANEL, "Frame", UI.BG_SOLID)
	_title = UI.label(frame, "", Vector2(6, 5), UI.FONT_BIG, UI.ACCENT, 204)
	_value = UI.label(frame, "", Vector2(6, 22), UI.FONT_BIG, UI.TEXT, 204)
	_hint = UI.label(frame, "enter ok   esc cancel", Vector2(6, 40), UI.FONT, UI.TEXT_DIM, 204)
	visible = false


## `config`: {title: String, text: String, hint: String, digits_only: bool}
func open(config: Dictionary) -> void:
	text = String(config.get("text", ""))
	_digits_only = bool(config.get("digits_only", false))
	_title.text = String(config.get("title", ""))
	_hint.text = String(config.get("hint", "enter ok   esc cancel"))
	visible = true
	_refresh()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _refresh() -> void:
	_value.text = text + "_"


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			submitted.emit(text)
			return
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			cancelled.emit()
			return
		KEY_BACKSPACE:
			if not text.is_empty():
				text = text.substr(0, text.length() - 1)
			get_viewport().set_input_as_handled()
			_refresh()
			return

	var c := key.unicode
	if c >= 32 and c < 127 and text.length() < MAX_LENGTH:
		var ch := String.chr(c)
		if _digits_only and not (ch >= "0" and ch <= "9"):
			return
		text += ch
		get_viewport().set_input_as_handled()
		_refresh()
