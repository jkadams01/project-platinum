extends "res://src/battle/abilities/ability.gd"
## Aura Guard -- Mega Lucario Z (lucario-mega-z). Mega-exclusive.
##
## "A Pokemon with Aura Guard takes half damage from moves that make contact."
##
## When the BEARER IS THE DEFENDER and the incoming move has the `contact` flag,
## FINAL damage is multiplied by 0.5. Bearer only; it does not protect allies.
##
## WHY A FINAL-DAMAGE MULTIPLIER AND NOT A DEFENCE MULTIPLIER
## Fluffy is the exact precedent (Showdown: `onSourceModifyDamage` ->
## `chainModify(0.5)`). Doubling Defence gives a DIFFERENT number, because the base
## formula divides by Defence and floors, and it interacts wrongly with critical
## hits, which ignore positive Defence stages. So this returns `damage_mult`, which
## damage.gd applies after burn and before `maxi(1, dmg)`.
##
## LONG REACH is not special-cased here. Long Reach removes the `contact` flag from
## the attacker's move, so the exception ("a move affected by Long Reach deals
## regular damage") resolves itself the moment long-reach lands -- this file only
## ever asks whether the move that arrived makes contact.
##
## It does NOT halve indirect damage: burn, poison, recoil and hazards never reach
## on_damage_calc at all. Contact moves only.
##
## Mega Lucario Z is 70/70/70 behind 164 Sp. Atk -- a glass cannon whose entire
## survivability story is this one multiplier.

const CONTACT_DAMAGE_MULT := 0.5


func slug() -> String:
	return "aura-guard"


func on_damage_calc(ctx: Dictionary) -> Dictionary:
	# Defender side only. registry.damage_mods() folds both sides and tags the
	# role, so the attacker's own contact moves are untouched.
	if String(ctx.get("role", "")) != "defender":
		return {}
	var move: Dictionary = ctx.get("move", {})
	if String(move.get("category", "status")) == "status":
		return {}
	if not bool(ctx.get("contact", _makes_contact(move))):
		return {}
	return {"damage_mult": CONTACT_DAMAGE_MULT}


static func _makes_contact(move: Dictionary) -> bool:
	var flags: Variant = move.get("flags", null)
	if flags is PackedStringArray:
		return (flags as PackedStringArray).has("contact")
	if flags is Array:
		return (flags as Array).has("contact")
	return false
