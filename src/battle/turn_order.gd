extends RefCounted
## Action ordering for one turn.
##
## Three keys, compared in this order:
##
## 1. **Action bracket.** Everything that is not a move happens first, in the
##    games' order: running > using an item > switching > moves. Mega Evolution
##    is resolved by the engine before this runs (DATA_CONTRACT 11.2), so it is
##    not a bracket here.
## 2. **Move priority** (DATA_CONTRACT 2 `priority`, -7..+5). Quick Attack (+1)
##    goes before any 0-priority move regardless of Speed.
## 3. **Effective Speed** — the Speed stat after stat stages *and* status
##    (paralysis halves it).
##
## TIE-BREAK, documented because it has to be: when bracket, priority and
## effective Speed are all equal the games flip a coin, and so do we -- one
## `rng.randi() & 1` per tied pair, drawn from the battle RNG so a seeded battle
## replays identically. **If `rng` is null the tie-break is deterministic
## instead: lower `side` first, then lower `index`.** Tests use the null form so
## a speed tie can never make them flaky.

const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Items := preload("res://src/battle/items.gd")

const BRACKET_RUN := 30
const BRACKET_ITEM := 20
const BRACKET_SWITCH := 10
const BRACKET_MOVE := 0


## Effective Speed: stat stages, then paralysis.
static func effective_speed(mon: Dictionary) -> int:
	var spe := Stats.effective_stat(mon, "spe")
	# Paralysis and a Choice Scarf compose: the scarf multiplies the stat, the
	# status divides it, and the order does not matter because both are floats
	# applied before the single floor.
	return maxi(1, floori(float(spe) * Status.speed_mult(mon) * Items.speed_mult(mon)))


static func bracket_of(action: Dictionary) -> int:
	match String(action.get("kind", "move")):
		"run": return BRACKET_RUN
		"item": return BRACKET_ITEM
		"switch": return BRACKET_SWITCH
	return BRACKET_MOVE


static func priority_of(action: Dictionary) -> int:
	if String(action.get("kind", "move")) != "move":
		return 0
	var move: Dictionary = action.get("move", {})
	return int(move.get("priority", 0))


## Sort `actions` into resolution order. Each action is a Dictionary with at
## least `{side: int, mon: Dictionary, kind: String}` and, for moves, `move`.
## The input is not modified; a new Array is returned.
static func order(actions: Array, rng: RandomNumberGenerator = null) -> Array:
	var decorated: Array = []
	for i in actions.size():
		var a: Dictionary = actions[i]
		decorated.append({
			"action": a,
			"bracket": bracket_of(a),
			"priority": priority_of(a),
			"speed": effective_speed(a.get("mon", {})),
			"index": i,
			"side": int(a.get("side", 0)),
			# One coin per action, drawn up front so the comparator stays a pure
			# function of the decorated rows (sort_custom may call it many times).
			"coin": (rng.randi() & 1) if rng != null else 0,
		})

	decorated.sort_custom(_compare)

	var out: Array = []
	for d: Dictionary in decorated:
		out.append(d["action"])
	return out


static func _compare(a: Dictionary, b: Dictionary) -> bool:
	if a["bracket"] != b["bracket"]:
		return a["bracket"] > b["bracket"]
	if a["priority"] != b["priority"]:
		return a["priority"] > b["priority"]
	if a["speed"] != b["speed"]:
		return a["speed"] > b["speed"]
	if a["coin"] != b["coin"]:
		return a["coin"] > b["coin"]
	if a["side"] != b["side"]:
		return a["side"] < b["side"]
	return a["index"] < b["index"]


## Debug helper: the ordering keys as a readable line per action.
static func explain(actions: Array, rng: RandomNumberGenerator = null) -> PackedStringArray:
	var out := PackedStringArray()
	for a: Dictionary in order(actions, rng):
		out.append("%s: %s (bracket %d, priority %+d, speed %d)" % [
			Stats.display_name(a.get("mon", {})),
			String(a.get("kind", "move")),
			bracket_of(a), priority_of(a), effective_speed(a.get("mon", {}))])
	return out
