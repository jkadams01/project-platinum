extends RefCounted
## THE HM REPLACEMENT. Badge-gated automatic traversal.
##
## No HM items exist. No move slot is consumed. There is no HM slave, no party
## check, no "Would you like to use SURF?" prompt and no menu. The *badge* grants
## the verb; the obstacle belongs to the map, not to the party; walking into it
## performs the verb on the same input that walked into it.
## (docs/research/game-design.md 3, docs/DATA_CONTRACT.md "Traversal verbs")
##
##   Coal    -> SMASH      cracked rock
##   Forest  -> CUT        cuttable tree
##   Relic   -> (nothing)  Defog is DELETED -- see below
##   Cobble  -> FLY        map menu, visited Pokemon Centers only
##   Fen     -> SURF       deep water, code 3
##   Mine    -> STRENGTH   push-boulder, one tile
##   Icicle  -> CLIMB      chevron rock face, code 6
##   Beacon  -> WATERFALL  code 7, only while surfing
##
## THERE IS NO DEFOG VERB. Fog is removed from the game entirely: no weather
## state, no visibility overlay, no accuracy modifier, no obstacle type
## (game-design.md 3.4). [constant VERBS] is the whole list and `defog` is not in
## it; [method is_verb] returns false for it, and map_loader.gd rejects a `defog`
## obstacle at parse time. This is asserted by tests/test_overworld.gd.
##
## WHY THE BADGE ORDER IS SAFE. The verb bindings are a 1:1 preservation of
## vanilla Platinum's badge->HM bindings, so every obstacle becomes passable
## exactly when a vanilla player could have passed it and never earlier; vanilla
## badge order is already a topological sort of the obstacle graph, so binding
## verbs to badges 1:1 cannot introduce a soft-lock (game-design.md 3.5).

const Collision := preload("res://src/systems/collision.gd")

## Every traversal verb in the game. `defog` is deliberately absent.
const VERBS: Array = ["smash", "cut", "fly", "surf", "strength", "climb", "waterfall"]

## Obstacles that occupy a tile and are cleared by walking into them.
const CLEARING_VERBS: Array = ["smash", "cut"]

## Verb -> the badge that grants it. Must agree with GameState.can_traverse.
const VERB_BADGE: Dictionary = {
	"smash": "coal",
	"cut": "forest",
	"fly": "cobble",
	"surf": "fen",
	"strength": "mine",
	"climb": "icicle",
	"waterfall": "beacon",
}

## What the player is told when the verb fires. No prompt precedes these; they
## are narration after the fact, exactly like vanilla's "The rock was smashed!".
const DID_MESSAGE: Dictionary = {
	"smash": "The cracked rock broke apart!",
	"cut": "The tree was cut down!",
	"strength": "You gave the boulder a heave!",
	"surf": "You climbed onto the water!",
	"climb": "You started climbing!",
	"waterfall": "You ascended the waterfall!",
	"dismount": "You stepped back onto dry land.",
}

## Flag prefix recording that a town's Pokemon Center has been entered. FLY can
## only reach these, so it can never reach content the story has not opened.
const CENTER_FLAG_PREFIX := "center_visited:"

## True while the player is on the water. Owned here because every verb that
## cares (surf, waterfall, dismount, ledge) is resolved through this object.
var surfing: bool = false

## `func(verb: String) -> bool`. Unset -> the real GameState badge gate.
var badge_gate: Callable = Callable()
## Set false in tests that do not want dialogue spam on the bus.
var announce: bool = true

## Cells whose obstacle has been cleared THIS VISIT. Cleared obstacles respawn on
## map reload, as in vanilla, which is why this is wiped by [method on_map_loaded]
## and never saved.
var _cleared: Dictionary = {}
## Boulders pushed this visit: original cell -> current cell. Also per-visit.
var _moved: Dictionary = {}
var _map_id: StringName = &""


static func is_verb(verb: String) -> bool:
	return VERBS.has(verb)


## The badge name for a verb, or "" when the verb does not exist.
static func badge_for(verb: String) -> String:
	return String(VERB_BADGE.get(verb, ""))


## Call every time a map is entered, including re-entering one. Obstacles respawn.
func on_map_loaded(map_id: StringName) -> void:
	_map_id = map_id
	_cleared.clear()
	_moved.clear()


## Leaving the water (a warp, a battle loss, a scripted teleport).
func dismount() -> void:
	surfing = false


func is_cleared(cell: Vector2i) -> bool:
	return _cleared.has(cell)


func cleared_count() -> int:
	return _cleared.size()


## The obstacle set as the collision layer should see it: every obstacle the map
## declares, minus the ones already cleared, with pushed boulders at their
## current positions.
func obstacles_for(map: Object) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in map.traversal:
		if _cleared.has(cell):
			continue
		var entry: Dictionary = map.traversal[cell]
		var at: Vector2i = _moved.get(cell, cell)
		var live: Dictionary = entry.duplicate()
		live["origin"] = cell
		live["x"] = at.x
		live["y"] = at.y
		out[at] = live
	return out


## The ctx Collision.resolve needs, wired to this object's live state.
func context(map: Object) -> Dictionary:
	return Collision.make_ctx(surfing, _gate(), obstacles_for(map))


# --------------------------------------------------------------------------
# The one entry point the player controller uses
# --------------------------------------------------------------------------

## Resolve a step and apply whatever it implies. Returns the Collision result
## dictionary with two extra keys:
##   `performed` -- the verb that actually fired, or ""
##   `blocked`   -- true when the player does not move
##
## A BLOCKED result carrying a `message` has already been announced on the bus;
## the caller only has to not move.
func attempt(map: Object, from: Vector2i, dir: Vector2i) -> Dictionary:
	var res := Collision.resolve(map, from, dir, context(map))
	res["performed"] = ""
	res["blocked"] = false

	match int(res["kind"]):
		Collision.Result.BLOCKED:
			res["blocked"] = true
			var msg := String(res["message"])
			if not msg.is_empty():
				_say(msg)
		Collision.Result.EDGE:
			res["blocked"] = true
		Collision.Result.TRAVERSE:
			var verb := String(res["verb"])
			if not perform(map, verb, from, res["target"], dir):
				# The verb was allowed but the world would not co-operate (a
				# boulder with nowhere to go). That is a bump, and it must READ
				# as a bump -- the caller switches on `kind`.
				res["kind"] = Collision.Result.BLOCKED
				res["target"] = from
				res["blocked"] = true
				res["reason"] = "verb-failed"
			else:
				res["performed"] = verb
	return res


## Applies a verb's world effect. Returns false when the verb could not actually
## be carried out (a boulder with nowhere to go), which turns the step into a bump.
func perform(map: Object, verb: String, from: Vector2i, target: Vector2i, dir: Vector2i) -> bool:
	match verb:
		"smash", "cut":
			var origin := _origin_of(map, target)
			_cleared[origin] = true
			_fire(verb)
			return true

		"strength":
			# The boulder slides exactly one tile. The puzzle geometry is vanilla;
			# only the "does someone know Strength" check is gone (3.2).
			var dest: Vector2i = target + dir
			if not map.in_bounds(dest):
				return false
			var live := obstacles_for(map)
			if live.has(dest) or not Collision.LAND_CODES.has(map.code_at(dest)):
				return false
			_moved[_origin_of(map, target)] = dest
			_fire(verb)
			return true

		"surf":
			surfing = true
			_fire(verb)
			return true

		"dismount":
			surfing = false
			_say(String(DID_MESSAGE["dismount"]))
			return true

		"climb", "waterfall":
			_fire(verb)
			return true

	Log.warn("unknown traversal verb '%s'" % verb, "Traversal")
	return false


# --------------------------------------------------------------------------
# FLY -- a map menu, not a move (game-design.md 3.3)
# --------------------------------------------------------------------------

func can_fly() -> bool:
	return _allowed("fly")


## Records that the player entered this town's Pokemon Center, which is what
## makes it a FLY destination. The unlock is "Center visited", not "map exists".
func record_center_visit(map_id: StringName) -> void:
	GameState.set_flag(CENTER_FLAG_PREFIX + String(map_id), true)


func has_visited_center(map_id: StringName) -> bool:
	return GameState.get_flag(CENTER_FLAG_PREFIX + String(map_id), false)


## Every town the MAP menu may currently offer. Empty without the Cobble Badge.
func fly_destinations() -> PackedStringArray:
	var out := PackedStringArray()
	if not can_fly():
		return out
	for k: Variant in GameState.flags:
		var key := String(k)
		if key.begins_with(CENTER_FLAG_PREFIX) and bool(GameState.flags[k]):
			out.append(key.substr(CENTER_FLAG_PREFIX.length()))
	out.sort()
	return out


## The warp FLY should perform, or {} when it is not allowed right now.
func fly_to(map_id: StringName) -> Dictionary:
	if not can_fly():
		_say(Collision.need_message("fly"))
		return {}
	if not has_visited_center(map_id):
		return {}
	surfing = false
	_fire("fly")
	return {"to": String(map_id), "reason": "fly"}


# --------------------------------------------------------------------------

func _origin_of(map: Object, at: Vector2i) -> Vector2i:
	for origin: Vector2i in _moved:
		if _moved[origin] == at:
			return origin
	return at


func _gate() -> Callable:
	return badge_gate if badge_gate.is_valid() else Callable()


func _allowed(verb: String) -> bool:
	if badge_gate.is_valid():
		return bool(badge_gate.call(verb))
	return GameState.can_traverse(verb)


func _fire(verb: String) -> void:
	EventBus.traversal_used.emit(StringName(verb))
	if DID_MESSAGE.has(verb):
		_say(String(DID_MESSAGE[verb]))


func _say(message: String) -> void:
	if announce and not message.is_empty():
		EventBus.dialogue_requested.emit(PackedStringArray([message]))
