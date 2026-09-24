extends RefCounted
## The collision grid reader. Pure, static, node-free -- every decision the
## overworld makes about "can I step there" happens in this one function so it
## can be unit-tested headlessly with no scene, no physics server and no frames.
##
## THE CODES ARE AUTHORITATIVE (docs/DATA_CONTRACT.md 9):
##   0 walk  1 block  2 ledge (jump south)  3 deep water (SURF)
##   4 tall grass     5 shallow water       6 stairs/climb (CLIMB)  7 waterfall
##
## WHY NOT PHYSICS BODIES. docs/research/godot-architecture.md 2.5: a grid lookup
## is exact, free (0.363 us per lookup), has no tunnelling and no wall-slide
## (Pokemon movement never slides along a wall), and -- the decisive one --
## "passable southbound only" is one `if` here and a mess of one-way collision
## shapes there.
##
## WHY THE RESULT IS A DICTIONARY, NOT A BOOL. A step has five possible outcomes
## and three of them need to say something to the player. A bool would push the
## ledge/surf/climb/waterfall/smash logic back out into the mover, which is
## exactly where it would rot. [method resolve] returns the whole decision.

## Collision codes. Names, not magic numbers, at every call site.
enum {
	WALK = 0,
	BLOCK = 1,
	LEDGE = 2,
	DEEP_WATER = 3,
	TALL_GRASS = 4,
	SHALLOW_WATER = 5,
	CLIMB = 6,
	WATERFALL = 7,
}

const CODE_NAMES: Array = [
	"walk", "block", "ledge", "deep-water", "tall-grass", "shallow-water",
	"climb", "waterfall",
]

## What [method resolve] decided.
enum Result {
	MOVE,       ## plain step onto `target`
	HOP,        ## ledge jump; `target` is two tiles away
	TRAVERSE,   ## a badge verb fires; `verb` names it, then you land on `target`
	BLOCKED,    ## nothing happens; `reason` and `message` say why
	EDGE,       ## walked off the map; warps.gd decides whether a connection exists
}

## Codes a walking (not surfing) player may stand on.
const LAND_CODES: Array = [WALK, TALL_GRASS, SHALLOW_WATER]
## Codes a surfing player may stay on the water for.
const WATER_CODES: Array = [DEEP_WATER, WATERFALL]

## Shown when the badge for a verb is missing. Keyed by verb.
const NEED_MESSAGE: Dictionary = {
	"smash": "A cracked rock blocks the way. It looks like it could be shattered.",
	"cut": "A thick tree blocks the way. It looks like it could be cut down.",
	"surf": "The water is deep here. You cannot swim across it yet.",
	"strength": "A huge boulder sits in the way. It looks like it could be pushed.",
	"climb": "The rock face is far too steep to climb.",
	"waterfall": "The wall of water crashes down. You cannot climb it yet.",
}

## Badge whose name completes the above message, keyed by verb. Mirrors
## GameState.can_traverse and docs/research/game-design.md 3.1 exactly.
## There is deliberately no `defog` row -- fog is deleted from the game (3.4).
const VERB_BADGE: Dictionary = {
	"smash": "Coal",
	"cut": "Forest",
	"fly": "Cobble",
	"surf": "Fen",
	"strength": "Mine",
	"climb": "Icicle",
	"waterfall": "Beacon",
}


## Builds the ctx [method resolve] takes.
## [param can_traverse] is `func(verb: String) -> bool`; leave it unset to use
## GameState (which is the real gate) -- tests inject a fake instead.
## [param obstacles] maps Vector2i -> the map's traversal entry, minus anything
## already cleared this visit. Traversal owns that dictionary.
static func make_ctx(surfing: bool = false, can_traverse: Callable = Callable(),
		obstacles: Dictionary = {}) -> Dictionary:
	return {
		"surfing": surfing,
		"can_traverse": can_traverse,
		"obstacles": obstacles,
	}


## THE function. [param map] is a MapData (src/overworld/map_loader.gd).
##
## Order of checks, and the order matters:
##   1. bounds        -- EDGE, so warps.gd can look for a connection
##   2. obstacle      -- smash/cut/strength objects sit ON TOP of a tile and win
##   3. collision code
static func resolve(map: Object, from: Vector2i, dir: Vector2i, ctx: Dictionary) -> Dictionary:
	var target: Vector2i = from + dir
	var surfing: bool = bool(ctx.get("surfing", false))

	if not map.in_bounds(target):
		return _r(Result.EDGE, target, "", "off-map", "")

	# --- 2. obstacle objects (map objects, not grid codes) -----------------
	var obstacles: Dictionary = ctx.get("obstacles", {})
	if obstacles.has(target):
		var ob: Dictionary = obstacles[target]
		var verb: String = String(ob.get("type", ""))
		if not _allowed(ctx, verb):
			return _r(Result.BLOCKED, from, verb, "no-badge", need_message(verb))
		# The obstacle clears and the player steps onto the tile it stood on --
		# one input, no menu, no move, no party check (game-design.md 3.2).
		return _r(Result.TRAVERSE, target, verb, "", "")

	var code: int = map.code_at(target)

	match code:
		BLOCK:
			return _r(Result.BLOCKED, from, "", "solid", "")

		LEDGE:
			# A ledge is one-way and the only way is south. Vector2i.DOWN is +y.
			if dir != Vector2i.DOWN:
				return _r(Result.BLOCKED, from, "", "ledge-wrong-way", "")
			if surfing:
				return _r(Result.BLOCKED, from, "", "ledge-while-surfing", "")
			var landing: Vector2i = from + dir * 2
			if not map.in_bounds(landing):
				return _r(Result.BLOCKED, from, "", "ledge-landing-offmap", "")
			if obstacles.has(landing) or not LAND_CODES.has(map.code_at(landing)):
				return _r(Result.BLOCKED, from, "", "ledge-landing-blocked", "")
			return _r(Result.HOP, landing, "", "", "")

		DEEP_WATER:
			if surfing:
				return _r(Result.MOVE, target, "", "", "")
			if not _allowed(ctx, "surf"):
				return _r(Result.BLOCKED, from, "surf", "no-badge", need_message("surf"))
			# Mount at the shoreline. Same input, no prompt.
			return _r(Result.TRAVERSE, target, "surf", "", "")

		WATERFALL:
			if not _allowed(ctx, "waterfall"):
				return _r(Result.BLOCKED, from, "waterfall", "no-badge", need_message("waterfall"))
			if not surfing:
				return _r(Result.BLOCKED, from, "waterfall", "not-surfing",
					"The waterfall roars down. You would have to be on the water.")
			return _r(Result.TRAVERSE, target, "waterfall", "", "")

		CLIMB:
			if surfing:
				return _r(Result.BLOCKED, from, "", "climb-while-surfing", "")
			if not _allowed(ctx, "climb"):
				return _r(Result.BLOCKED, from, "climb", "no-badge", need_message("climb"))
			return _r(Result.TRAVERSE, target, "climb", "", "")

		WALK, TALL_GRASS, SHALLOW_WATER:
			if surfing:
				# Dismounting is automatic and ungated -- getting OUT of the
				# water is never a gate, or you could strand the player in a lake.
				return _r(Result.TRAVERSE, target, "dismount", "", "")
			return _r(Result.MOVE, target, "", "", "")

	# An unknown code is a data bug. Fail closed rather than letting the player
	# walk through something the map author believed was solid.
	return _r(Result.BLOCKED, from, "", "unknown-code-%d" % code, "")


## True when the tile can be stood on right now with no verb at all.
static func is_walkable(map: Object, cell: Vector2i, surfing: bool = false) -> bool:
	if not map.in_bounds(cell):
		return false
	var code: int = map.code_at(cell)
	return WATER_CODES.has(code) if surfing else LAND_CODES.has(code)


## True when standing here rolls for wild Pokemon on foot.
static func is_encounter_tile(code: int) -> bool:
	return code == TALL_GRASS


static func code_name(code: int) -> String:
	return CODE_NAMES[code] if code >= 0 and code < CODE_NAMES.size() else "code-%d" % code


## "A huge boulder sits in the way... The Mine Badge would let you get past."
static func need_message(verb: String) -> String:
	var base: String = String(NEED_MESSAGE.get(verb, "You cannot get past this yet."))
	if VERB_BADGE.has(verb):
		return "%s The %s Badge would let you get past." % [base, VERB_BADGE[verb]]
	return base


# --------------------------------------------------------------------------

static func _allowed(ctx: Dictionary, verb: String) -> bool:
	var f: Callable = ctx.get("can_traverse", Callable())
	if f.is_valid():
		return bool(f.call(verb))
	# No injected gate: ask the real one.
	return GameState.can_traverse(verb)


static func _r(kind: int, target: Vector2i, verb: String, reason: String, message: String) -> Dictionary:
	return {
		"kind": kind,
		"target": target,
		"verb": verb,
		"reason": reason,
		"message": message,
	}
