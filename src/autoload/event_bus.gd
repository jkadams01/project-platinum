extends Node
## Signals only. No state, no logic, no references to any scene.
##
## This is the seam between the streams: the overworld never holds a reference to
## the battle scene and vice versa. Everything travels as plain data
## (Dictionary / int / StringName / Vector2i) so no stream has to wait for another
## stream's class to exist before it can emit or listen.
##
## Payload shapes are documented per signal. Where a payload is a Dictionary the
## shape is owned by the stream that emits it; treat undocumented keys as optional.
##
## Connect with the 4.x callable syntax and guard re-parented nodes:
## [codeblock]
## if not EventBus.badge_earned.is_connected(_on_badge):
##     EventBus.badge_earned.connect(_on_badge)
## [/codeblock]

# --- battle ---------------------------------------------------------------

## A battle is starting. `setup` carries at least:
## {"kind": "wild"|"trainer", "party": Array[Dictionary], "opponent": Dictionary|Array,
##  "cap": int}  -- `cap` is the level cap in force, for the exp-block UI.
signal battle_started(setup: Dictionary)

## A battle ended. `result` carries at least:
## {"outcome": "win"|"loss"|"run"|"caught", "expAwarded": int, "money": int,
##  "party": Array[Dictionary]}
signal battle_ended(result: Dictionary)

## A Pokemon Mega Evolved (DATA_CONTRACT 11.2). `pokemon` is the in-battle
## Dictionary, already transformed; `form_id` is the `data/megas.json` form id
## ("charizard-mega-x"). For UI and animation only -- the engine has applied the
## swap by the time this fires. Mega Evolution is the ONLY battle gimmick in this
## game: there is deliberately no Dynamax, Z-Move or Terastal signal here, and
## there must never be one.
signal mega_evolved(pokemon: Dictionary, form_id: String)

## A Mega went back to its base form -- the battle ended, or it fainted.
## `form_id` is the form it *was*, since `pokemon` no longer carries it.
signal mega_reverted(pokemon: Dictionary, form_id: String)

## Exp was withheld because the Pokemon is at or above the active cap
## (docs/research/game-design.md 2.5: at/above cap = zero exp). `pokemon` is the
## party-member Dictionary, `cap` the level cap that blocked it.
signal exp_capped(pokemon: Dictionary, cap: int)

# --- progression ----------------------------------------------------------

## A gym badge was earned for the first time. One of
## coal/forest/relic/cobble/fen/mine/icicle/beacon.
signal badge_earned(badge: StringName)

## The active hard level cap moved. `index` is the new row in data/level_caps.json.
signal level_cap_raised(old_cap: int, new_cap: int, index: int)

## A story flag changed value.
signal flag_set(flag: StringName, value: bool)

# --- overworld ------------------------------------------------------------

## The player entered a different map. `spawn` is the tile they arrived on.
signal map_changed(map_id: StringName, spawn: Vector2i)

## A badge-gated traversal verb was used: smash/cut/fly/surf/strength/climb/waterfall
## (docs/DATA_CONTRACT.md, "Traversal verbs"). There is no `defog`.
signal traversal_used(verb: StringName)

## The player finished a step onto `cell`.
signal player_moved(cell: Vector2i)

## A wild encounter roll succeeded. `level_range` is (min, max) inclusive.
signal encounter_triggered(zone: StringName, level_range: Vector2i)

## Show a dialogue box. The UI stream owns the presentation.
signal dialogue_requested(lines: PackedStringArray)

# --- meta -----------------------------------------------------------------

## A save slot was written (or failed to be written).
signal game_saved(slot: int, ok: bool)

## A save slot was applied to GameState (or failed to load).
signal game_loaded(slot: int, ok: bool)

## The party array changed identity or contents (add, remove, faint, heal).
signal party_changed()


## Disconnect every listener from every signal on this bus. Tests call it in
## `before_each` so a leaked connection from an earlier test cannot make a later
## one pass or fail for the wrong reason.
func disconnect_all() -> void:
	# get_script_signal_list(), not get_signal_list(): the latter also returns
	# Node's own built-in signals and we must not touch the engine's wiring.
	for s: Dictionary in get_script().get_script_signal_list():
		var sig_name: StringName = s["name"]
		for c: Dictionary in get_signal_connection_list(sig_name):
			disconnect(sig_name, c["callable"])
