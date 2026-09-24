extends "res://src/battle/abilities/ability.gd"
## Shadow Tag -- Mega Gengar (gengar-mega), and base Wobbuffet (202).
##
## While the bearer is on the field and not fainted, the opposing active Pokemon
## may not choose `switch` and may not choose `run`.
##
## THIS IS THE ABILITY FANTINA'S GYM RUNS ON. Gym 3 is the first boss in the game
## that Mega Evolves, and the Mega Ring is handed over the moment she loses; a
## Mega Gengar that swaps stats but does not trap turns that fight into a normal
## one.
##
## EXEMPTIONS -- blocked unless ANY of these hold:
##   * the escaper is a GHOST-type. Gen 6+ only, and deliberately taken: a Gen 4/5
##     reading would trap the player's own Ghost answers to a Ghost/Poison Mega
##     Gengar, which is the opposite of the intended fight.
##   * the escaper holds a Shed Shell -- switching is allowed, RUNNING still is
##     not (the item is an escape from a trainer's trap, not from a wild one).
##   * the escaper has Shadow Tag itself: mutual immunity.
##   * the trapper has fainted or left the field -- checked LIVE by
##     `registry.for_mon()`, never latched, so a Gengar that dies this turn traps
##     nothing next turn.
##
## A FORCED REPLACEMENT AFTER A FAINT IS NEVER BLOCKED. The engine simply does not
## consult the hook there; a trapped side with no legal action would deadlock
## `awaiting_switch`.
##
## arena-trap and magnet-pull are this same hook with a different predicate
## (`Abilities.is_grounded(escaper)` / `types.has("steel")`), so they drop in as
## their own files with no engine change.
##
## Source: https://bulbapedia.bulbagarden.net/wiki/Shadow_Tag_(Ability)

## Gen 6 onwards. Flip to false only to model a Gen 4/5 battle.
const GHOST_IS_EXEMPT := true
const SHED_SHELL := "shed-shell"


func slug() -> String:
	return "shadow-tag"


func on_switch_attempt(ctx: Dictionary) -> Dictionary:
	var escaper: Dictionary = ctx.get("escaper", {})
	if escaper.is_empty():
		return {}
	if int(escaper.get("hp", 0)) <= 0:
		return {}

	# Mutual immunity: two Shadow Tags cancel.
	if String(escaper.get("ability", "")) == slug():
		return {}

	if GHOST_IS_EXEMPT and PackedStringArray(escaper.get("types", PackedStringArray())).has("ghost"):
		return {}

	var reason := String(ctx.get("reason", "switch"))
	if reason == "switch" and String(escaper.get("item", "")) == SHED_SHELL:
		return {}

	# A named message: _try_run already prints the generic "Can't escape!" when the
	# escape odds simply fail, and the log has to tell those two apart.
	return {
		"block": true,
		"message": "%s can't escape!" % String(escaper.get("nickname", escaper.get("name", "MON"))),
	}
