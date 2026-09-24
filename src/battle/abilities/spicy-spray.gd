extends "res://src/battle/abilities/ability.gd"
## Spicy Spray -- Mega Scovillain (scovillain-mega). Mega-exclusive.
##
## "When the Pokemon takes damage from a move, it burns the attacker."
##
## ANY DAMAGING MOVE, NOT CONTACT MOVES. This is the trap in the ability: it reads
## like Flame Body / Rough Skin and it is not one. A contact-only implementation
## fails to burn Flamethrower, Earthquake and Thunderbolt -- which is most of what
## actually hits a 65/85/85 Mega. That is precisely why the hook interface carries
## `on_hit_taken` ALONGSIDE `on_contact_taken`, and why this file overrides the
## former.
##
## 100%, with no effectChance roll -- unlike Flame Body's 30%.
##
## FIRES FROM BEYOND THE GRAVE. Bulbapedia: it activates "even if the Spicy Spray
## user faints" from that same hit. The engine therefore calls on_hit_taken after the
## damage lands and BEFORE the faint break and before `_check_faints()` reverts the
## Mega. Once a multi-hit host loop exists it is called per hit from inside the loop,
## so a 5-hit Icicle Spear gets five (failing, after the first) burn attempts.
##
## NO RE-IMPLEMENTED BURN CHECKS. status.gd already refuses a Fire-type
## (IMMUNE_TYPES[BURN] == ["fire"]), a target that already carries a non-volatile
## status (reason "already") and a fainted target. This file calls
## `Status.apply(attacker, BURN, rng)` and lets it say no.
##
## MESSAGES ONLY ON SUCCESS. Status.apply's refusal messages ("X is already burn!",
## "It doesn't affect X...") are written for a move that targeted the mon on purpose;
## a silent ability failing silently is right, so only the success message is
## surfaced.
##
## Mega Scovillain is Grass/FIRE, so it is immune to its own medicine in mirror
## matches. The payoff is the burn's halving of physical Attack (status.gd:79-83).
##
## Substitute: the ability does not activate if the BEARER is behind a Substitute --
## the hit never reaches it. Substitute does not exist in the engine, so the check
## reads a forward-compatible volatile and is a no-op today. The burn still applies
## when the ATTACKER is behind one.

const Status := preload("res://src/battle/status.gd")


func slug() -> String:
	return "spicy-spray"


func on_hit_taken(ctx: Dictionary) -> Dictionary:
	if int(ctx.get("damage", 0)) <= 0:
		return {}
	if String(ctx.get("category", "status")) == "status":
		return {}
	# The bearer behind a Substitute never took the hit itself.
	var vol: Dictionary = (ctx.get("defender", {}) as Dictionary).get("volatile", {})
	if int(vol.get("substitute", 0)) > 0:
		return {}

	var attacker: Dictionary = ctx.get("attacker", {})
	if attacker.is_empty():
		return {}

	var res: Dictionary = Status.apply(attacker, Status.BURN, ctx.get("rng", null))
	if not bool(res.get("ok", false)):
		return {}
	return {"status": Status.BURN, "messages": (res.get("messages", []) as Array).duplicate()}
