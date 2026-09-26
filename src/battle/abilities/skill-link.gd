extends "res://src/battle/abilities/ability.gd"
## Skill Link -- Mega Heracross (heracross-mega), and base Cloyster (91).
##
## On moves with a VARIABLE hit count, two changes:
##   1. the hit count becomes the MAXIMUM of the range -- 2-5 becomes 5, Triple
##      Kick and Triple Axel become 3, Population Bomb becomes 10;
##   2. per-hit accuracy is switched OFF, so Triple Kick rolls accuracy once and
##      all three kicks land.
##
## Moves with a FIXED hit count are untouched: Gear Grind stays 2, Twineedle stays
## 2, Dragon Darts stays 2, Surging Strikes stays 3.
##
## BRANCH ON effectId, NOT ON THE EFFECT STRING. 57 Gen 9 moves in data/moves.json
## carry `"effect": null`, so a string match silently finds nothing; and the two
## families read almost identically in prose ("hits 2-5 times" vs "hits twice").
##
## Triple Kick's escalating power (10/20/30) is NOT flattened -- Skill Link
## guarantees the hits, the ramp is the move's own business (multi_hit.gd owns it).
##
## Losing the ability mid-move keeps the maximum (Gen 5+), which is free here:
## the count is decided once, before the hit loop.
##
## THE POINT: five-hit Pin Missile / Arm Thrust off 185 Attack breaks Sturdy and
## Focus Sash, which is what makes Mega Heracross a boss Mega rather than a stat
## sheet.
##
## Source: https://bulbapedia.bulbagarden.net/wiki/Skill_Link_(Ability)

## effectId -> the maximum of that move's hit range.
##   30  hits-2-5-times-in-one-turn (13 moves)
##   361 water-shuriken
##   443 scale-shot
##   105 triple-kick / triple-axel -- 3 hits WITH per-hit accuracy, which is the
##       half of the ability people skip
##   20001 population-bomb -- 10 hits with per-hit accuracy. PROJECT-LOCAL effect
##       id: veekun ships none for this move, so tools/build_species.py assigns it
##       (LOCAL_EFFECT_IDS). Without Skill Link the hit loop stops at the first
##       miss; with it, all ten land.
const VARIABLE_HITS: Dictionary = {
	30: 5,
	105: 3,
	361: 5,
	443: 5,
	20001: 10,
}

## Fixed-count families, listed only so the exclusion is visible and greppable:
## 45 (7 moves, 2 hits), 78 twineedle, 450 dragon-darts, 486 surging-strikes.
const FIXED_HIT_EFFECTS: Array = [45, 78, 450, 486]


func slug() -> String:
	return "skill-link"


func on_multi_hit_count(ctx: Dictionary) -> Dictionary:
	var move: Dictionary = ctx.get("move", {})
	var raw: Variant = move.get("effectId", null)
	if raw == null:
		return {}
	var effect_id := int(raw)
	if not VARIABLE_HITS.has(effect_id):
		return {}
	# `single_accuracy` is the removal of per-hit accuracy (Showdown deletes
	# move.multiaccuracy); without it Triple Kick would still drop kicks 2 and 3.
	return {"hits": int(VARIABLE_HITS[effect_id]), "single_accuracy": true}
