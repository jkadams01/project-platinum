extends Control
## The Battle scene's root: the only thing that drives `BattleEngine` from input.
##
## `SceneRouter.enter_battle()` instantiates `scenes/Battle.tscn`, adds it to
## BattleHolder and calls [method setup] with the payload. That payload is the
## DATA_CONTRACT `EventBus.battle_started` shape, so this file works for a wild
## encounter, an ordinary trainer and a `data/rom/bosses.json` fight without
## branching on which.
##
## THE ENGINE IS SYNCHRONOUS AND DOES NOT BLOCK. `resolve_turn()` runs the whole
## turn and hands back `{turn, log, over, outcome}`. So this screen is a small
## state machine over that call: collect one action, resolve, then page the log
## out one line at a time. Nothing here awaits anything, which is why a headless
## test can drive the identical code path with [method debug_pick_move].
##
## THE THREE ORDERING RULES THAT ARE EASY TO GET WRONG
##
## 1. `awaiting_switch` must be serviced BEFORE `resolve_turn()`. The engine
##    refuses to advance while a side owes a replacement and just logs "Waiting for
##    a replacement Pokemon" -- call it in that state and the battle silently
##    deadlocks. A forced replacement goes through `switch_in()`, which does NOT
##    consume a turn; a voluntary switch is submitted as an action, which does.
## 2. Mega Evolution is not an action. It rides the move as
##    `{"kind":"move","move_index":i,"mega":true}` (DATA_CONTRACT 11.2) and the
##    engine resolves it at the start of the turn, before any move.
## 3. `SceneRouter.exit_battle()` frees this node synchronously, so it is the last
##    statement of the last frame this scene is alive for. Nothing may touch the
##    tree after it.

const UI := preload("res://src/ui/ui_kit.gd")
const BattleHud := preload("res://src/ui/battle_hud.gd")
const MoveList := preload("res://src/ui/move_list.gd")
const PartyView := preload("res://src/ui/party_view.gd")
const MessageBox := preload("res://src/ui/message_box.gd")

const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const Stats := preload("res://src/battle/stats.gd")

const SPRITE_ROOT := "res://assets/generated/"

enum State { LEAD_IN, ACTION, MOVES, PARTY, RESOLVING, FORCED_SWITCH, DONE }

## Top-level menu, in cursor order.
const ACTIONS: Array = ["FIGHT", "PKMN", "BAG", "RUN"]

signal finished(result: Dictionary)

var engine: RefCounted = null
var state: State = State.LEAD_IN
## When true the screen never calls SceneRouter (tests drive it in isolation).
var standalone: bool = false
## WATCH MODE (`autoPlayer` in the setup payload, DATA_CONTRACT 13). The screen
## submits an EMPTY action for the player, which `resolve_turn()` fills in from
## `ai.gd` -- so both sides play themselves and the log still pages one line at a
## time. Custom Battle mode uses it to judge pacing and AI quality without
## playing every turn by hand.
var auto_player: bool = false

var _setup: Dictionary = {}
var _hud: Control = null
var _moves: Control = null
var _party: Control = null
var _box: Control = null
var _menu: Control = null
var _menu_labels: Array = []
var _menu_index: int = 0
var _log: PackedStringArray = PackedStringArray()
var _foe_sprite: TextureRect = null
var _own_sprite: TextureRect = null
var _exited: bool = false
## Consecutive auto-resolved turns that produced no log line at all. A turn always
## logs something in practice, but "resolve, log nothing, return to ACTION" would
## recurse without bound in watch mode, so it is counted rather than trusted.
var _auto_turns: int = 0

const AUTO_TURN_LIMIT := 8


func _ready() -> void:
	name = "Battle"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.16, 0.20, 0.27, 1.0)
	backdrop.size = Vector2(256, 192)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_foe_sprite = _make_sprite("FoeSprite", Vector2(168, 26))
	_own_sprite = _make_sprite("OwnSprite", Vector2(22, 60))

	_hud = BattleHud.new()
	add_child(_hud)

	_menu = UI.panel(self, Rect2(6, 136, 118, 48), "ActionMenu")
	for i in ACTIONS.size():
		_menu_labels.append(UI.label(_menu, String(ACTIONS[i]),
			Vector2(6 + (i % 2) * 56, 5 + (i / 2) * 20), UI.FONT_BIG, UI.TEXT, 52))
	UI.label(self, "A pick   B back   X party", Vector2(130, 178), UI.FONT, UI.TEXT_DIM, 120)

	_moves = MoveList.new()
	add_child(_moves)
	_moves.chosen.connect(_on_move_chosen)
	_moves.cancelled.connect(_on_move_cancelled)

	_party = PartyView.new()
	add_child(_party)
	_party.picked.connect(_on_party_picked)
	_party.closed.connect(_on_party_closed)

	_box = MessageBox.new()
	_box.autonomous = false            # this screen paces the battle log itself
	add_child(_box)

	if engine != null:
		_bind()


func _make_sprite(node_name: String, pos: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.name = node_name
	t.position = pos
	t.size = Vector2(64, 64)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(t)
	return t


# --------------------------------------------------------------------------
# Entry point (SceneRouter calls this)
# --------------------------------------------------------------------------

## `data` is the `EventBus.battle_started` payload. Safe to call before or after
## `_ready()`: the router adds the node and calls `setup()` in the same frame, and
## the order between them is not something this file should depend on.
func setup(data: Dictionary) -> void:
	_setup = data.duplicate(true)
	auto_player = bool(data.get("autoPlayer", false))
	engine = BattleEngineScript.new()
	engine.start(_setup)
	if is_inside_tree() and _hud != null:
		_bind()


func _bind() -> void:
	_hud.bind(engine)
	_moves.bind(engine)
	_party.bind(engine)
	if not engine.message.is_connected(_on_engine_message):
		engine.message.connect(_on_engine_message)
	_load_sprites()
	# start() has already logged the lead-in ("A wild X appeared!", "Go! Y!").
	_log = PackedStringArray(engine.battle_log)
	_enter_state(State.LEAD_IN)


func _load_sprites() -> void:
	_set_sprite(_foe_sprite, engine.active(1), "front")
	_set_sprite(_own_sprite, engine.active(0), "back")


## Sprites live under the gitignored `assets/generated/`, so a fresh checkout has
## none. A missing sprite leaves an empty TextureRect rather than failing the
## battle -- the fight is playable off the HUD alone.
func _set_sprite(target: TextureRect, mon: Dictionary, which: String) -> void:
	if target == null:
		return
	target.texture = null
	if mon.is_empty():
		return
	var species: Dictionary = DataRegistry.get_species(int(mon.get("species", 0)))
	var rel := String((species.get("sprite", {}) as Dictionary).get(which, ""))
	if rel.is_empty():
		return
	var path := SPRITE_ROOT + rel
	if not ResourceLoader.exists(path):
		return
	var res: Resource = ResourceLoader.load(path)
	if res is Texture2D:
		target.texture = res


# --------------------------------------------------------------------------
# State machine
# --------------------------------------------------------------------------

func _enter_state(next: State) -> void:
	state = next
	_moves.close()
	if _party.is_open() and next != State.PARTY and next != State.FORCED_SWITCH:
		_party.visible = false
	_menu.visible = false
	match next:
		State.LEAD_IN, State.RESOLVING, State.DONE:
			_show_next_line()
		State.ACTION:
			_menu.visible = true
			_menu_index = 0
			_refresh_menu()
			_box.close()
		State.MOVES:
			_moves.open()
			_box.close()
		State.PARTY:
			_party.open(true)
			_box.close()
		State.FORCED_SWITCH:
			_box.close()
			_party.open(true)
	_hud.refresh()
	if auto_player and not _exited:
		_auto_advance(next)


func _refresh_menu() -> void:
	for i in _menu_labels.size():
		var l: Label = _menu_labels[i]
		l.text = ("> " if i == _menu_index else "  ") + String(ACTIONS[i])
		l.add_theme_color_override("font_color", UI.ACCENT if i == _menu_index else UI.TEXT)


## Page one queued log line into the box. When the queue empties, move on:
## the battle is over -> leave; a side owes a replacement -> ask for it;
## otherwise -> back to the action menu.
func _show_next_line() -> void:
	if _log.size() > 0:
		var line := _log[0]
		_log.remove_at(0)
		_box.show_lines(PackedStringArray([line]))
		_hud.refresh()
		_auto_turns = 0
		return
	_box.close()
	if engine.over:
		_leave()
		return
	if int(engine.awaiting_switch) == 0:
		_enter_state(State.FORCED_SWITCH)
		return
	_enter_state(State.ACTION)


func _queue(lines: PackedStringArray) -> void:
	for l in lines:
		_log.append(l)


## Submit the player's action and run the turn. An EMPTY action means "let the
## engine choose", which is how Struggle happens: `submit_action` has no
## `struggle` kind, but `resolve_turn()` falls back to `auto_action()` for any side
## that submitted nothing, and that returns Struggle when no move has PP left.
func _resolve(action: Dictionary) -> void:
	if not action.is_empty() and not bool(engine.submit_action(0, action)):
		_box.show_lines(PackedStringArray(["That cannot be done right now."]))
		return
	var r: Dictionary = engine.resolve_turn()
	_log = PackedStringArray(r.get("log", []))
	_enter_state(State.DONE if bool(r.get("over", false)) else State.RESOLVING)


func _leave() -> void:
	if _exited:
		return
	_exited = true
	var r: Dictionary = engine.result()
	# The boss key travels back out so the integrator can award the badge, the
	# stone and the cap raise without re-deriving which fight this was.
	if _setup.has("boss"):
		r["boss"] = String(_setup["boss"])
	r["kind"] = String(_setup.get("kind", "wild"))
	finished.emit(r)
	if standalone or not SceneRouter.in_battle():
		return
	# Frees this node. Nothing below this line may touch the tree.
	SceneRouter.exit_battle(r)


## Watch mode: take the decision the player would have taken.
##
## An EMPTY action is the whole trick -- `resolve_turn()` calls `auto_action()` for
## any side that submitted nothing, so the AI plays side 0 through the identical
## code path the buttons use. A forced replacement cannot go that way (the engine
## refuses to advance while a side owes one), so it is chosen here.
func _auto_advance(state_now: State) -> void:
	match state_now:
		State.ACTION:
			_auto_turns += 1
			if _auto_turns > AUTO_TURN_LIMIT:
				auto_player = false
				_box.show_lines(PackedStringArray([
					"Watch mode stopped: the turn produced no messages."]))
				Log.error("watch mode made %d turns with an empty log; stopping"
					% AUTO_TURN_LIMIT, "BattleScreen")
				return
			_resolve({})
		State.FORCED_SWITCH:
			var party: Array = engine.party_of(0)
			var current := int((engine.sides[0] as Dictionary)["active"])
			for i in party.size():
				if i != current and not Stats.is_fainted(party[i]):
					_on_party_picked(i)
					return


# --------------------------------------------------------------------------
# Widget callbacks
# --------------------------------------------------------------------------

func _on_engine_message(text: String) -> void:
	# Messages produced outside a resolve_turn() (a refused switch, say) still have
	# to reach the player.
	if state == State.MOVES or state == State.PARTY or state == State.ACTION:
		_box.show_lines(PackedStringArray([text]))


func _on_move_chosen(move_index: int, mega: bool) -> void:
	_resolve({"kind": "move", "move_index": move_index, "mega": mega})


func _on_move_cancelled() -> void:
	_enter_state(State.ACTION)


func _on_party_picked(index: int) -> void:
	if state == State.FORCED_SWITCH:
		# A replacement after a faint is free: switch_in(), never an action.
		if bool(engine.switch_in(0, index)):
			_party.visible = false
			_log = PackedStringArray(["Go! %s!" % Stats.display_name(engine.active(0))])
			_enter_state(State.RESOLVING)
		return
	_party.visible = false
	_resolve({"kind": "switch", "index": index})


func _on_party_closed() -> void:
	if state == State.FORCED_SWITCH:
		# There is no opting out of a forced replacement.
		_party.open(true)
		return
	if state == State.PARTY:
		_enter_state(State.ACTION)


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.LEAD_IN, State.RESOLVING, State.DONE:
			if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
				get_viewport().set_input_as_handled()
				_show_next_line()
		State.ACTION:
			_action_input(event)
		_:
			pass


func _action_input(event: InputEvent) -> void:
	var n := ACTIONS.size()
	if event.is_action_pressed(&"ui_right") or event.is_action_pressed(&"ui_down"):
		_menu_index = (_menu_index + 1) % n
	elif event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_up"):
		_menu_index = (_menu_index - 1 + n) % n
	elif event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_choose_action(String(ACTIONS[_menu_index]))
		return
	else:
		return
	_refresh_menu()
	get_viewport().set_input_as_handled()


func _choose_action(what: String) -> void:
	match what:
		"FIGHT":
			if _has_pp(engine.active(0)):
				_enter_state(State.MOVES)
			else:
				_log = PackedStringArray(["%s has no moves left!" % Stats.display_name(engine.active(0))])
				_resolve({})
		"PKMN":
			if engine.bench_of(0).is_empty():
				_box.show_lines(PackedStringArray(["There is no one else to send out."]))
			else:
				_enter_state(State.PARTY)
		"BAG":
			var item := _first_heal_item()
			if item.is_empty():
				_box.show_lines(PackedStringArray(["There are no usable items in the Bag."]))
			else:
				_resolve({"kind": "item", "item": item,
					"target": int((engine.sides[0] as Dictionary)["active"])})
		"RUN":
			_resolve({"kind": "run"})


static func _has_pp(mon: Dictionary) -> bool:
	for m: Dictionary in (mon.get("moves", []) as Array):
		if int(m.get("pp", 0)) > 0:
			return true
	return false


## The first bag entry the engine actually implements. Anything else is a no-op
## with a message, so offering it would be a lie.
func _first_heal_item() -> String:
	for key: Variant in GameState.bag:
		var id := String(key)
		if int(GameState.bag[key]) <= 0:
			continue
		if BattleEngineScript.HEAL_ITEMS.has(id) or BattleEngineScript.CURE_ITEMS.has(id):
			return id
	return ""


# --------------------------------------------------------------------------
# Test / debug hooks -- the same code path the buttons take
# --------------------------------------------------------------------------

## Pick move `i` for the player and resolve the turn. Returns the engine result.
func debug_pick_move(i: int, mega: bool = false) -> Dictionary:
	_on_move_chosen(i, mega)
	return engine.result()


## Page the whole pending log out in one go, as if A had been held down.
func debug_flush_log(max_lines: int = 500) -> int:
	var n := 0
	while (_log.size() > 0 or _box.is_open()) and n < max_lines and not _exited:
		_show_next_line()
		n += 1
	return n
