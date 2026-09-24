extends "res://src/battle/abilities/ability.gd"
## Eelevate -- Mega Eelektross (eelektross-mega). Mega-exclusive.
##
## data/abilities.json: "The Pokemon floats off the ground, making it immune to
## Ground-type moves, as well as the Spikes, Toxic Spikes, and Sticky Web
## statuses. When the Pokemon knocks out a target with an attack, its highest stat
## is boosted by 1 stage."
##
## TWO INDEPENDENT HALVES. A naive "it's just Levitate" reading ships HALF an
## ability, and the half it drops is the new one: base Eelektross ALREADY has
## Levitate, so the grounding half is continuity, not a gain -- the KO snowball is
## what Mega Eelektross actually buys.
##
## HALF 1 -- GROUNDING. is_grounded(mon) is false: damaging Ground-type moves do 0
## (except Thousand Arrows), and no Arena Trap, Spikes, Toxic Spikes, Sticky Web,
## Rototiller or terrain effect applies. A Poison-type holder also does not absorb
## Toxic Spikes on switch-in. Negated by Gravity, Iron Ball, Ingrain, Smack Down
## or Thousand Arrows. This is routed through on_type_immunity so it shares one
## seam with levitate (tier 1, onTypeImmunity, also unimplemented and Eelektross's
## BASE ability) -- the two must behave identically on this half. The five
## forward-grounders do not exist yet; all of them read through
## registry.is_grounded() and vol["grounded_by"], so they have ONE place to land
## instead of five.
##
## HALF 2 -- THE KO SNOWBALL. Beast Boost's rule, verbatim:
##   * stats considered are atk/def/spa/spd/spe -- HP EXCLUDED
##   * the comparison uses the RAW calculated stat: Bulbapedia, "does not account
##     for stat stage changes, held items, or status condition reductions". So it
##     reads mon["stats"][key] and NEVER Stats.effective_stat(). Using the
##     effective stat is the single most common Beast Boost bug: the choice then
##     drifts as stages change and can flip the boosted stat mid-battle.
##   * tie-break order is fixed: Attack, Defense, Special Attack, Special Defense,
##     Speed -- iterate in that exact order with a STRICT > comparison
##   * DIRECT KOs from damaging moves only. Never recoil, hazards or residual
##     damage, which is why the engine fires this from the damage path and not from
##     _check_faints() (which does not know who did the killing).
##   * once per KO, from inside the hit loop, so a Parental-Bond-style double hit
##     that KOs on hit 1 gives exactly one boost.
## For Mega Eelektross (145/80/135/90/80) the winner is ATTACK every time until it
## caps at +6.
##
## SURPRISING BUT CORRECT: on the pure-Electric Mega form this deletes its only
## weakness. Post-game `za` form.
##
## SOURCE: https://bulbapedia.bulbagarden.net/wiki/Eelevate_(Ability)
##         https://bulbapedia.bulbagarden.net/wiki/Beast_Boost_(Ability)  (tie-break)

const StatsUtil := preload("res://src/battle/stats.gd")

const GROUND := "ground"

## Beast Boost's stat order. HP is excluded; the order IS the tie-break.
const BOOST_KEYS: Array = ["atk", "def", "spa", "spd", "spe"]

## The one damaging Ground move that hits an ungrounded target anyway. Not
## implemented yet (no move in the engine reads this), named so the exception is
## visible rather than silently missing.
const GROUNDS_TARGET: Array = ["thousand-arrows"]


func slug() -> String:
	return "eelevate"


## onTypeImmunity. Half 1. `ctx` = {mon, move_type, move}.
func on_type_immunity(ctx: Dictionary) -> Dictionary:
	if String(ctx.get("move_type", "")).to_lower() != GROUND:
		return {}
	var mon: Dictionary = ctx.get("mon", {})
	# Gravity / Iron Ball / Ingrain / Smack Down set this. None exist yet; one
	# flag is where all five land.
	var vol: Dictionary = mon.get("volatile", {})
	if bool(vol.get("grounded_by", false)):
		return {}
	var move: Dictionary = ctx.get("move", {})
	if GROUNDS_TARGET.has(String(move.get("slug", ""))):
		return {}
	return {"immune": true, "ungrounded": true}


## onAfterHit. Half 2. `ctx` = {mon, target, move, dealt, ko, hit_index}.
## `mon` is the bearer, which is the ATTACKER here.
func on_after_hit(ctx: Dictionary) -> Dictionary:
	if not bool(ctx.get("ko", false)):
		return {}
	var move: Dictionary = ctx.get("move", {})
	if String(move.get("category", "status")) == "status":
		return {}
	var mon: Dictionary = ctx.get("mon", {})
	var best := highest_stat(mon)
	if best.is_empty():
		return {}
	# The engine applies the stage and prints `messages` only if a stage actually
	# moved, so a bearer already at +6 boosts nothing and says nothing.
	return {
		"stat_boosts": {best: 1},
		"messages": ["%s's %s rose!" % [StatsUtil.display_name(mon), best]],
	}


## The bearer's highest RAW non-HP stat, ties broken in BOOST_KEYS order.
## Deliberately reads mon["stats"], never Stats.effective_stat().
static func highest_stat(mon: Dictionary) -> String:
	var stats: Dictionary = mon.get("stats", {})
	if stats.is_empty():
		return ""
	var best := ""
	var best_value := -1
	for key: String in BOOST_KEYS:
		var value := int(stats.get(key, 0))
		if value > best_value:            # strict >: earlier key wins a tie
			best_value = value
			best = key
	return best
