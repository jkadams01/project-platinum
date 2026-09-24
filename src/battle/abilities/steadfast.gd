extends "res://src/battle/abilities/ability.gd"
## **Steadfast** -- Mega Mewtwo X (`mewtwo-mega-x`), and the base ability of
## Lucario (448) and Gallade (475) in `data/species.json`. Not Mega-exclusive.
##
## Raises the bearer's Speed by one stage every time it flinches, capped only by
## the normal +6. The turn is still lost, so the boost is felt on the NEXT turn.
##
## TIED TO THE MESSAGE, NOT THE FLAG. Bulbapedia: "The Speed boost will only apply
## if the flinching message is displayed." `status.gd:174-178` prints
## "<Name> flinched and couldn't move!" and clears `vol.flinch` in the same
## breath, so any check made after the fact sees nothing. `Status.before_move()`
## therefore reports it with an additive `"flinched": bool` key and the engine
## calls this hook on exactly that branch -- which also means a flinch that is
## PREVENTED (Inner Focus, Substitute; neither implemented yet) will correctly
## never reach here.
##
## `status.gd` stays below the ability layer: it returns the flag, the engine
## calls the hook.
##
## SOURCE: https://bulbapedia.bulbagarden.net/wiki/Steadfast_(Ability)


func slug() -> String:
	return "steadfast"


## `ctx` = {mon, name}. The engine applies `stat_boosts` through
## `Stats.change_stage()` and suppresses the message when the stage is already +6.
func on_flinch(ctx: Dictionary) -> Dictionary:
	return {
		"stat_boosts": {"spe": 1},
		"messages": ["%s's Steadfast raised its Speed!" % String(ctx.get("name", "It"))],
	}
