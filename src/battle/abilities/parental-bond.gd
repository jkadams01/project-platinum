extends "res://src/battle/abilities/ability.gd"
## Parental Bond -- Mega Kangaskhan (kangaskhan-mega). Mega-exclusive.
##
## A damaging, non-excluded move hits TWICE. Hit 1 is normal; hit 2 is the same
## move again with a final DAMAGE multiplier of 0.25 (the Gen 7+ value -- Gen 6
## used 0.5, and 0.25 is what every modern sim and every balance discussion of
## this ability means).
##
## The pair is ONE move, so:
##   * ONE accuracy check for both hits. A per-hit roll would double the miss rate
##     on a 90%-accurate move, which is not what the ability does.
##   * `effectChance` secondaries roll INDEPENDENTLY PER HIT -- that, far more than
##     the raw damage, is why the ability was considered broken.
##   * drain heals per hit; RECOIL is computed from the SUMMED damage and applied
##     once, after hit 2 (battle_engine does that part: the recoil block lives
##     outside `_apply_damage_side_effects` for exactly this reason).
##   * if the target faints on hit 1 the loop stops there and the KO hook fires on
##     hit 1, not after the pair.
##
## EXCLUSIONS (Bulbapedia, verbatim): multi-strike moves, OHKO moves, Fling,
## Self-Destruct, Explosion, Final Gambit, Uproar, Rollout, Ice Ball, charging
## moves and Endeavor -- plus status moves and fixed-damage moves. In this engine
## that reduces to: status category, zero power, a move that already has a
## multi-hit `effectId`, the `charge` flag, or one of the named ids below.
##
## 0.25 is a DAMAGE multiplier at the very end of the chain, so hit 2 still
## respects `maxi(1, dmg)` -- a resisted second hit does 1, never 0.
##
## DOES NOT STACK with a multi-hit move: Bullet Seed does not become 10 hits, and
## the 0.25 must never touch hit 2 of a naturally multi-hit move. Both come from
## the same guard: the hook only fires when the natural hit count is 1, and
## `on_damage_calc` only applies the multiplier when the hit plan was set BY THIS
## ABILITY (`ctx.hit_plan_by`).
##
## Source: https://bulbapedia.bulbagarden.net/wiki/Parental_Bond_(Ability)

const HITS := 2
## Gen 7+. Gen 6 used 0.5.
const SECOND_HIT_DAMAGE_MULT := 0.25

## Multi-strike families: 30 (2-5), 45 (twice), 78 twineedle, 105 triple-kick,
## 361 water-shuriken, 443 scale-shot, 450 dragon-darts, 486 surging-strikes.
const MULTI_HIT_EFFECTS: Array = [30, 45, 78, 105, 361, 443, 450, 486]

## Named exclusions that DO carry power, so the `power <= 0` guard misses them.
##   8   self-destruct / explosion
##   39  OHKO (guillotine, horn-drill, fissure, sheer-cold)
##   118 rollout / ice-ball
##   160 uproar
##   190 endeavor
##   321 final-gambit
##   234 fling
const EXCLUDED_EFFECTS: Array = [8, 39, 118, 160, 190, 234, 321]

## Belt-and-braces slug list, so the exclusion survives an effectId of null.
const EXCLUDED_SLUGS: Array = [
	"fling", "self-destruct", "explosion", "final-gambit", "uproar",
	"rollout", "ice-ball", "endeavor",
]


func slug() -> String:
	return "parental-bond"


func on_multi_hit_count(ctx: Dictionary) -> Dictionary:
	if not _applies(ctx):
		return {}
	return {"hits": HITS, "single_accuracy": true}


func on_damage_calc(ctx: Dictionary) -> Dictionary:
	if String(ctx.get("role", "")) != "attacker":
		return {}
	# Only the pair THIS ability created: hit 2 of Bullet Seed is not a child.
	if String(ctx.get("hit_plan_by", "")) != slug():
		return {}
	if int(ctx.get("hit_index", 0)) != 1:
		return {}
	return {"damage_mult": SECOND_HIT_DAMAGE_MULT}


## The exclusion list, in one place so both hooks agree.
func _applies(ctx: Dictionary) -> bool:
	var move: Dictionary = ctx.get("move", {})
	if move.is_empty():
		return false
	if String(move.get("category", "status")) == "status":
		return false
	if int(move.get("power", 0)) <= 0:
		return false
	# Already a multi-strike move: never stack.
	if int(ctx.get("natural_hits", 1)) > 1:
		return false
	var raw: Variant = move.get("effectId", null)
	if raw != null:
		var effect_id := int(raw)
		if MULTI_HIT_EFFECTS.has(effect_id) or EXCLUDED_EFFECTS.has(effect_id):
			return false
	if EXCLUDED_SLUGS.has(String(move.get("slug", ""))):
		return false
	# Charging moves. Charge turns are not implemented yet, so Solar Beam currently
	# fires immediately -- the flag guard is already right for when they land.
	if _has_flag(move, "charge"):
		return false
	return true


static func _has_flag(move: Dictionary, flag: String) -> bool:
	var flags: Variant = move.get("flags", null)
	if flags is PackedStringArray:
		return (flags as PackedStringArray).has(flag)
	if flags is Array:
		return (flags as Array).has(flag)
	return false
