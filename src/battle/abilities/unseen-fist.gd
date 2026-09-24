extends "res://src/battle/abilities/ability.gd"
## Unseen Fist -- Mega Golurk (golurk-mega). Also base Urshifu (892).
##
## "If the Pokemon uses a move that makes direct contact, it can strike the target
## even if the target protects itself."
##
## The move hits through every protection move, at FULL damage, and everything the
## move would normally do still happens.
##
## VERSION DECISION -- mainline Gen 8/9 FULL DAMAGE, not the Pokemon Champions 25%
## nerf. Three reasons, in order:
##   1. data/species.json gives BASE URSHIFU this ability, so it must follow
##      mainline rules; whatever is chosen here lands on Urshifu too.
##   2. data/abilities.json already ships the mainline text, with no damage clause.
##   3. Under the Champions reading this file would be byte-identical to
##      piercing-drill, Mega Excadrill's signature -- two signatures collapsing
##      into one is a design regression, not a fidelity win.
## [constant PIERCE_DAMAGE_MULT] is the single knob if the owner ever wants
## Champions-strict instead.
##
## CONTACT ONLY. Mega Golurk's Shadow Punch has the flag; Earthquake does not.
##
## Max Guard is the one protection Bulbapedia names as NOT bypassed -- and it is a
## Dynamax move, excluded by DATA_CONTRACT 11.4, so that exception is inert here.
## Bulbapedia does NOT enumerate Crafty Shield, Wide Guard, Quick Guard, Mat Block,
## Obstruct, King's Shield, Spiky Shield, Baneful Bunker, Silk Trap or Burning
## Bulwark, so this file invents no per-move rules: it answers "yes, pierce" and
## lets the protection layer decide what protection was in force.
##
## FORWARD RULE, recorded rather than silently omitted: the protection move's own
## punish should still apply on a pierced hit (King's Shield's Attack drop, Spiky
## Shield's recoil, Baneful Bunker's poison). None of those exist in the engine yet.
##
## DORMANT TODAY: the engine has no Protect move, so on_protect_check is only
## reached when something sets `volatile["protect"]`. The unit test sets it by hand.
## Mega Golurk's Speed is 55, so full-damage Protect-break is its one real trick and
## it is spec-complete the moment Protect lands.

## 1.0 = mainline Gen 8/9. Champions-strict would be 0.25 -- see the note above.
const PIERCE_DAMAGE_MULT := 1.0


func slug() -> String:
	return "unseen-fist"


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
