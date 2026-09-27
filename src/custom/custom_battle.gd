extends Control
## Custom Battle mode's root: the integrator for the half of the game that is not
## the campaign.
##
## It is `src/boot.gd`'s smaller sibling and reuses the same machinery on purpose.
## `SceneRouter` holds two slots, the builder lives in WorldHolder and is SUSPENDED
## (process_mode DISABLED + hidden) while a battle runs in BattleHolder, so the
## twelve slots, the cursor position and the pinned seed all survive a fight with
## no save/restore code. `scenes/Battle.tscn` is instanced unmodified -- a custom
## battle is the same `EventBus.battle_started` payload a boss fight is, which is
## the whole reason this mode is worth having as a test bed.
##
## IT MUST NOT TOUCH THE CAMPAIGN SAVE, AND THAT IS NOT AN ACCIDENT OF OMISSION:
##   * the teams are built fresh from the spec every battle, so nothing here is
##     ever a Dictionary out of `GameState.party` (damage and EXP would persist);
##   * `BattleSpec.to_setup()` sends no `prizeMoney`, because the engine pays a
##     trainer prize straight into `GameState.add_money()`;
##   * `awardExp` defaults to false, so nothing levels up;
##   * `playerKeyStone` rides in the payload instead of granting the save a Key
##     Stone (DATA_CONTRACT 11.2);
##   * `SaveSystem` is never called.
## `tests/test_custom_battle.gd` asserts the party, money and bag are untouched
## after a full battle.
##
## THE RESULT PANEL OWNS THE KEYBOARD, EXPLICITLY. When a battle ends the router
## has already un-suspended the builder, so both would be reading input. Rather
## than lean on `_unhandled_input` ordering between siblings, the panel sets
## `builder.active = false` and hands it back on dismissal.

const UI := preload("res://src/ui/ui_kit.gd")
const Spec := preload("res://src/custom/battle_spec.gd")
const TeamBuilder := preload("res://src/custom/team_builder.gd")
const Bosses := preload("res://src/systems/bosses.gd")

const TITLE_SCENE := "res://scenes/Title.tscn"

var builder: Control = null

var _world: Control = null
var _battle: Node = null
var _ui: CanvasLayer = null
var _result: Control = null
var _result_lines: Array = []
## The seed the last battle actually ran with, so the result panel can show it and
## a rematch can be made identical.
var _last_seed: int = 0


func _ready() -> void:
	Log.info("Custom Battle mode", "CustomBattle")
	_world = get_node_or_null("WorldHolder") as Control
	_battle = get_node_or_null("BattleHolder")
	_ui = get_node_or_null("UILayer") as CanvasLayer
	if _world == null or _battle == null or _ui == null:
		Log.error("CustomBattle.tscn is missing WorldHolder / BattleHolder / UILayer",
			"CustomBattle")
		return

	# The boss table is what the "fill from a boss roster" pre-fill reads. It is
	# gitignored (ROM-derived), so a fresh checkout simply has no rosters to offer
	# and the builder says so rather than failing.
	Bosses.boot()

	builder = TeamBuilder.new()
	_world.add_child(builder)
	builder.start_requested.connect(_on_start_requested)
	builder.exit_requested.connect(_on_exit_requested)

	_build_result_panel()
	SceneRouter.register(_world, _battle, _ui)

	if not EventBus.battle_ended.is_connected(_on_battle_ended):
		EventBus.battle_ended.connect(_on_battle_ended)


func _build_result_panel() -> void:
	_result = Control.new()
	_result.name = "Result"
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(_result)

	# Dim the builder behind it. The panel takes the keyboard, so it has to LOOK
	# like it has: an overlay drawn over a fully lit screen reads as a screen you
	# can still use.
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.0, 0.0, 0.0, 0.55)
	shade.size = Vector2(256, 192)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_child(shade)

	var frame := UI.panel(_result, Rect2(24, 52, 208, 88), "Frame", UI.BG_SOLID)
	_result_lines.append(UI.label(frame, "", Vector2(8, 6), UI.FONT_BIG, UI.ACCENT, 192))
	for i in 3:
		_result_lines.append(UI.label(frame, "", Vector2(8, 26.0 + float(i) * 11.0),
			UI.FONT, UI.TEXT, 192))
	UI.label(frame, "a rematch   x builder   esc title", Vector2(8, 68),
		UI.FONT, UI.TEXT_DIM, 192)
	_result.visible = false


# --------------------------------------------------------------------------
# Starting a battle
# --------------------------------------------------------------------------

func _on_start_requested(spec: Dictionary) -> void:
	_launch(spec)


## Build the payload and hand it to the router. Returns the seed the battle ran
## with, or 0 when it could not start -- which is what a test asserts on.
func _launch(spec: Dictionary) -> int:
	var problems := Spec.validate(spec)
	if not problems.is_empty():
		Log.error("refusing to start: %s" % problems[0], "CustomBattle")
		return 0
	var setup := Spec.to_setup(spec)
	if setup.is_empty():
		return 0
	_last_seed = int(setup.get("seed", 0))
	_result.visible = false
	if not SceneRouter.enter_battle(setup):
		Log.error("SceneRouter refused the battle", "CustomBattle")
		return 0
	return _last_seed


# --------------------------------------------------------------------------
# Finishing one
# --------------------------------------------------------------------------

func _on_battle_ended(result: Dictionary) -> void:
	# The campaign's own battles also emit this signal; only ours land here
	# because the campaign runs in a different scene, but guard anyway so a future
	# shared mode cannot show a custom-battle result panel over the overworld.
	if not is_instance_valid(builder):
		return
	var outcome := String(result.get("outcome", "?"))
	(_result_lines[0] as Label).text = {
		"win": "YOU WON", "loss": "YOU LOST", "run": "YOU RAN", "draw": "A DRAW",
	}.get(outcome, outcome.to_upper())
	(_result_lines[1] as Label).text = "%d turn%s" % [
		int(result.get("turn", 0)), "" if int(result.get("turn", 0)) == 1 else "s"]
	(_result_lines[2] as Label).text = "seed %d" % _last_seed
	(_result_lines[3] as Label).text = "A replays it with the same teams."

	builder.active = false
	_result.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if _result == null or not _result.visible:
		return
	if event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_dismiss_result()
		_launch(builder.spec)
	elif event.is_action_pressed(&"game_menu"):
		get_viewport().set_input_as_handled()
		_dismiss_result()
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_dismiss_result()
		_on_exit_requested()


func _dismiss_result() -> void:
	_result.visible = false
	if is_instance_valid(builder):
		builder.active = true
		builder.refresh()


func _on_exit_requested() -> void:
	# change_scene_to_file is deferred, so nothing may run after it that assumes
	# this scene is still current (godot-architecture.md 4.1).
	if not ResourceLoader.exists(TITLE_SCENE):
		Log.error("no title scene at %s" % TITLE_SCENE, "CustomBattle")
		return
	get_tree().change_scene_to_file(TITLE_SCENE)


# --------------------------------------------------------------------------
# Test hooks -- the same code paths the keys take
# --------------------------------------------------------------------------

## Start a battle from `spec`; returns the seed it ran with, or 0 on refusal.
func debug_launch(spec: Dictionary) -> int:
	return _launch(spec)


func debug_result_visible() -> bool:
	return _result != null and _result.visible


func debug_result_text() -> String:
	var out := PackedStringArray()
	for label: Label in _result_lines:
		out.append(label.text)
	return String(" | ").join(out)


func debug_last_seed() -> int:
	return _last_seed
