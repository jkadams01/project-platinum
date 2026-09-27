extends Control
## The mode select, and the project's main scene.
##
## It exists so Custom Battle mode is a MODE rather than a debug key: the campaign
## and the battle sandbox are separate entry points that share the engine, the
## data and the battle scene, and neither can wander into the other's state.
##
## It is deliberately the thinnest possible scene. `scenes/Boot.tscn` is still the
## whole campaign integrator and is loaded unchanged; this file only decides which
## of the two roots the tree gets. `change_scene_to_file` is deferred, so the call
## is always the last statement of its branch.

const UI := preload("res://src/ui/ui_kit.gd")

const CAMPAIGN_SCENE := "res://scenes/Boot.tscn"
const CUSTOM_SCENE := "res://scenes/CustomBattle.tscn"

const ENTRIES: Array = [
	{"id": "campaign", "label": "CAMPAIGN", "note": "Twinleaf Town onward"},
	{"id": "custom", "label": "CUSTOM BATTLE", "note": "build both teams, then fight"},
	{"id": "quit", "label": "QUIT", "note": ""},
]

var index: int = 0

var _rows: Array = []
var _note: Label = null


func _ready() -> void:
	name = "Title"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.07, 0.09, 0.13, 1.0)
	backdrop.size = Vector2(256, 192)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	UI.label(self, "PROJECT PLATINUM", Vector2(20, 34), UI.FONT_BIG, UI.ACCENT, 216)
	UI.label(self, "Godot %s" % Engine.get_version_info().string,
		Vector2(20, 48), UI.FONT, UI.TEXT_DIM, 216)

	for i in ENTRIES.size():
		_rows.append(UI.label(self, "", Vector2(28, 84.0 + float(i) * 16.0),
			UI.FONT_BIG, UI.TEXT, 200))
	_note = UI.label(self, "", Vector2(20, 146), UI.FONT, UI.TEXT_DIM, 216)
	UI.label(self, "w/s move   enter select", Vector2(20, 176), UI.FONT, UI.TEXT_DIM, 216)
	_refresh()


func _refresh() -> void:
	for i in _rows.size():
		var row: Label = _rows[i]
		var selected := i == index
		row.text = "%s%s" % ["> " if selected else "  ",
			String((ENTRIES[i] as Dictionary)["label"])]
		row.add_theme_color_override("font_color", UI.ACCENT if selected else UI.TEXT)
	_note.text = String((ENTRIES[index] as Dictionary).get("note", ""))


func _unhandled_input(event: InputEvent) -> void:
	var n := ENTRIES.size()
	if _moved(event, &"ui_down", KEY_DOWN):
		index = (index + 1) % n
	elif _moved(event, &"ui_up", KEY_UP):
		index = (index - 1 + n) % n
	elif event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_choose(String((ENTRIES[index] as Dictionary)["id"]))
		return
	else:
		return
	_refresh()
	get_viewport().set_input_as_handled()


static func _moved(event: InputEvent, action: StringName, keycode: Key) -> bool:
	if event.is_action_pressed(action):
		return true
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.keycode == keycode


func _choose(id: String) -> void:
	match id:
		"campaign":
			_go(CAMPAIGN_SCENE)
		"custom":
			_go(CUSTOM_SCENE)
		"quit":
			get_tree().quit()


func _go(path: String) -> void:
	if not ResourceLoader.exists(path):
		Log.error("no scene at %s" % path, "Title")
		_note.text = "that scene is missing: %s" % path
		return
	Log.info("-> %s" % path, "Title")
	get_tree().change_scene_to_file(path)
