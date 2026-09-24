extends "res://src/battle/abilities/ability.gd"
## **Stalwart** -- Mega Skarmory (`skarmory-mega`). Mega-exclusive here: base
## Duraludon and Archaludon ship other abilities in `data/species.json`.
##
## A DELIBERATE NO-OP IN THIS ENGINE, and the spec says so rather than inventing
## an effect.
##
## The ability bypasses target-redirecting effects from both moves and abilities
## -- Rage Powder, Follow Me, Ally Switch, Storm Drain, Lightning Rod. Bulbapedia,
## verbatim: "The ability has no practical effect in single battles since
## redirecting moves and abilities only function in double/triple battles."
## `battle_engine.gd` line 4 is "Single battles only, two sides", and no double
## battle appears in DATA_CONTRACT.md or game-design.md.
##
## DO NOT invent a single-battle effect. Some fan implementations give Stalwart
## "ignore the target's ability" -- that is **Mold Breaker**, a separate ability
## which is already tier 1. Conflating them silently buffs Mega Skarmory's 140
## Attack past what the design signed off.
##
## It ships anyway: flipping its tier 3 -> 1 is what keeps mega-design.md's claim
## that all five gym-leader Megas use tier-1 abilities true (ruling B9 is about
## declared-vs-implemented, not about observable effect). If doubles ever land,
## the hook is already in the right place and the redirection resolver just asks.
##
## `propeller-tail` is this file with a different slug.
##
## SOURCE: https://bulbapedia.bulbagarden.net/wiki/Stalwart_(Ability)


func slug() -> String:
	return "stalwart"


func ignores_redirection(_ctx: Dictionary) -> bool:
	return true
