extends "res://src/battle/abilities/ability.gd"
## Piercing Drill -- Mega Excadrill (excadrill-mega). Mega-exclusive, Champions-only
## (no mainline holder).
##
## "When the Pokemon uses contact moves, it can hit even targets that are protecting
## themselves, DEALING 1/4 OF THE DAMAGE it would otherwise deal."
##
## Same plumbing as unseen-fist with `damage_mult` 0.25 instead of 1.0.
##
## THE 0.25 APPLIES ONLY WHEN PROTECTION WAS ACTUALLY PIERCED. on_protect_check is
## reached only when the target is protected, so an unprotected target takes full
## damage for free. Wiring the 0.25 anywhere else -- on_damage_calc, say -- turns a
## niche ability into a permanent 75% damage penalty on a 165-Attack Mega.
##
## Everything aside from the target's protective effects still triggers on the
## pierced hit: flinch chances, stat drops, the KO hook, all normal. And the 0.25 is
## a multiply, not a floor to zero -- damage.gd still honours `maxi(1, dmg)`.
##
## CONTACT ONLY: Drill Run and Iron Head qualify, Earthquake does not.
##
## DATA NOTE: data/abilities.json's stored text for this slug was TRUNCATED before
## the "dealing 1/4 of the damage" clause, so a UI showing it told the player Mega
## Excadrill ignores Protect for free. Corrected alongside this file.
##
## DORMANT TODAY, exactly like unseen-fist: no Protect move exists, so the unit test
## sets `volatile["protect"]` by hand.

const PIERCE_DAMAGE_MULT := 0.25


func slug() -> String:
	return "piercing-drill"


func on_protect_check(ctx: Dictionary) -> Dictionary:
	var move: Dictionary = ctx.get("move", {})
	if not bool(ctx.get("contact", _makes_contact(move))):
		return {}
	return {"pierce": true, "damage_mult": PIERCE_DAMAGE_MULT}


static func _makes_contact(move: Dictionary) -> bool:
	var flags: Variant = move.get("flags", null)
	if flags is PackedStringArray:
		return (flags as PackedStringArray).has("contact")
	if flags is Array:
		return (flags as Array).has("contact")
	return false
