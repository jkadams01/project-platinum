extends "res://src/battle/abilities/ability.gd"
## Fire Mane -- Mega Pyroar (pyroar-mega). Mega-exclusive.
##
## Bulbapedia, verbatim: "If a Fire-type move is used by a Pokemon with this
## Ability, its Attack or Special Attack stat is multiplied by 1.5 during damage
## calculation, effectively increasing damage dealt by 50%."
##
## A STAT MULTIPLIER. Not a power multiplier, not a damage multiplier. The effect
## text is explicit and it matters: the base formula divides by Defence and
## floors, so 1.5 x A then floor is not 1.5 x power then floor and is not
## 1.5 x damage. Implemented as `atk_mult`, which is the same seam Blaze, Solar
## Power, Huge Power, Guts and Hustle all need (every one tier 1 and unimplemented).
## dragonize is the mirror-image lesson: one is a stat multiplier, the other a
## power multiplier, and swapping them produces numbers that look plausible and
## are wrong. Test against a hand-computed number, never against damage x 1.5.
##
## Damage.compute picks the stat from the move's category -- Attack for physical,
## Sp. Atk for special -- so one `atk_mult` covers both halves of the sentence.
##
## THE MOVE'S TYPE AFTER CONVERSION is what counts, which the hook ordering in
## docs/research/ability-implementation.md section 4.3 guarantees: on_modify_move
## (4) runs before on_damage_calc (8d), so a Normalize/Dragonize-style conversion
## into or out of Fire is respected.
##
## The bearer's own Fire moves ONLY: no field effect, no ally effect. And it
## stacks multiplicatively with harsh sunlight's x1.5, which is a separate step of
## the damage chain rather than a stat step -- Fire Mane under sun is 2.25x
## overall, with each step floored in turn.
##
## Bulbapedia notes NO out-of-battle effect. Unlike Flame Body or Flash Fire,
## nothing hatches eggs faster. Do not add one.
##
## SOURCE: https://bulbapedia.bulbagarden.net/wiki/Fire_Mane_(Ability)

const MOVE_TYPE := "fire"
const ATK_MULT := 1.5


func slug() -> String:
	return "fire-mane"


## onDamageCalc. ATTACKER side only -- being hit by a Fire move changes nothing.
func on_damage_calc(ctx: Dictionary) -> Dictionary:
	if String(ctx.get("role", "")) != "attacker":
		return {}
	var move: Dictionary = ctx.get("move", {})
	if move.is_empty():
		return {}
	if String(move.get("category", "status")) == "status":
		return {}
	if String(move.get("type", "")) != MOVE_TYPE:
		return {}
	return {"atk_mult": ATK_MULT}
