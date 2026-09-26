extends RefCounted
## How many times one move hits, and whether each hit rolls accuracy of its own.
##
## The engine had no multi-hit loop at all, so the NATURAL plan lives here rather
## than inside any ability: Pin Missile hitting 2-5 times is the move's behaviour,
## not Skill Link's. [method plan] computes that natural plan and then lets the
## attacker's ability override it through `registry.hit_count()`, which is how
## Skill Link (range maximum, no per-hit accuracy) and Parental Bond (a second hit
## on a single-hit move) both land with one call site in battle_engine.
##
## BRANCHING IS ON `effectId`, NEVER on the effect string: 57 Gen 9 moves in
## data/moves.json have `"effect": null`, and "hits 2-5 times" vs "hits twice in
## one turn" is a distinction no substring match should be trusted with.
##
## VARIABLE ranges (the ones Skill Link maximises)
##   30  hits-2-5-times-in-one-turn -- 13 moves
##   361 water-shuriken (2-5)
##   443 scale-shot (2-5)
##   105 triple-kick / triple-axel -- 3 hits, ESCALATING power, and each kick rolls
##       accuracy separately
##
## FIXED counts (untouched by anything)
##   45  hits-twice-in-one-turn -- 7 moves      78  twineedle
##   450 dragon-darts                           486 surging-strikes (3)
##
## PER-HIT ACCURACY at a fixed maximum
##   20001 population-bomb -- 10 hits, each rolling accuracy, so the hit loop in
##       battle_engine stops at the first miss. 20001 is a PROJECT-LOCAL effect id:
##       veekun ships no effect_id for this move, so tools/build_species.py assigns
##       it (see LOCAL_EFFECT_IDS there). Skill Link turns per-hit accuracy off and
##       all ten land.

const Abilities := preload("res://src/battle/abilities/registry.gd")

## effectId values whose count is 2-5.
const VARIABLE_2_5: Array = [30, 361, 443]
## effectId -> a fixed number of hits.
const FIXED_HITS: Dictionary = {45: 2, 78: 2, 450: 2, 486: 3}
## Triple Kick / Triple Axel.
const TRIPLE_KICK := 105
const TRIPLE_KICK_HITS := 3
## Population Bomb: a fixed maximum, but every hit rolls its own accuracy.
## Project-local effect id -- see the header and tools/build_species.py.
const PER_HIT_ACCURACY_HITS: Dictionary = {20001: 10}

## Gen 5+ 2-5 distribution: 2 and 3 at 35% each, 4 and 5 at 15% each. Twenty
## entries so a single randi_range gives exactly those odds.
const SPREAD_2_5: Array = [
	2, 2, 2, 2, 2, 2, 2,
	3, 3, 3, 3, 3, 3, 3,
	4, 4, 4,
	5, 5, 5,
]


## The move's own hit plan, before any ability sees it.
##
## Returns `{hits, single_accuracy, natural_hits, escalating}`:
##   hits            how many times it hits this time
##   single_accuracy true when one accuracy roll covers every hit
##   natural_hits    the same number, kept so an ability can tell a single-hit
##                   move from a multi-strike one after the count is overridden
##   escalating      Triple Kick's 10/20/30 power ramp
static func natural(move: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var out: Dictionary = {
		"hits": 1, "single_accuracy": true, "natural_hits": 1, "escalating": false,
	}
	if String(move.get("category", "status")) == "status":
		return out
	var raw: Variant = move.get("effectId", null)
	if raw == null:
		return out
	var effect_id := int(raw)

	if effect_id == TRIPLE_KICK:
		out["hits"] = TRIPLE_KICK_HITS
		out["natural_hits"] = TRIPLE_KICK_HITS
		out["single_accuracy"] = false     # each kick rolls its own accuracy
		out["escalating"] = true
		return out

	if PER_HIT_ACCURACY_HITS.has(effect_id):
		out["hits"] = int(PER_HIT_ACCURACY_HITS[effect_id])
		out["natural_hits"] = out["hits"]
		out["single_accuracy"] = false   # the loop stops at the first miss
		return out

	if FIXED_HITS.has(effect_id):
		out["hits"] = int(FIXED_HITS[effect_id])
		out["natural_hits"] = out["hits"]
		return out

	if VARIABLE_2_5.has(effect_id):
		var n := 3
		if rng != null:
			n = int(SPREAD_2_5[rng.randi_range(0, SPREAD_2_5.size() - 1)])
		out["hits"] = n
		out["natural_hits"] = n
		return out

	return out


## The natural plan with the attacker's ability folded in, decided ONCE before the
## hit loop (Gen 5+: losing the ability mid-move does not shrink the count).
##
## Adds `by`: the slug of the ability that changed the plan, "" when none did.
## Parental Bond's second-hit multiplier keys on that, which is what stops it from
## touching hit 2 of Bullet Seed.
static func plan(attacker: Dictionary, move: Dictionary,
		rng: RandomNumberGenerator = null) -> Dictionary:
	var out := natural(move, rng)
	out["by"] = ""
	var got: Dictionary = Abilities.hit_count(attacker, move, out)
	if got.is_empty():
		return out
	if got.has("hits"):
		out["hits"] = maxi(1, int(got["hits"]))
	if got.has("single_accuracy"):
		out["single_accuracy"] = bool(got["single_accuracy"])
	out["by"] = String(attacker.get("ability", ""))
	return out


## The power multiplier for hit `index` (0-based). 1.0 everywhere except Triple
## Kick's ramp, which Skill Link guarantees the hits of but does NOT flatten.
static func power_mult_for_hit(plan_row: Dictionary, index: int) -> float:
	if not bool(plan_row.get("escalating", false)):
		return 1.0
	return float(index + 1)
