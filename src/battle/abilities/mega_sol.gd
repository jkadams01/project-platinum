extends "res://src/battle/abilities/ability.gd"
## Mega Sol -- Mega Meganium (meganium-mega). Mega-exclusive.
##
## "The Pokemon can use its moves as if the weather were harsh sunlight."
##
## A PER-MON WEATHER *VIEW*, not a weather setter. Everywhere the engine reads
## `weather` in order to resolve THIS Pokemon's move, "sun" is substituted. The
## field's real weather is untouched: the opponent still sees rain, residual
## sandstorm damage still ticks, and `_end_of_turn` still counts the real
## weather down. Under rain Mega Meganium is simultaneously rained on (residual,
## opponent) and sunlit (its own moves).
##
## FULL DOCUMENTED EFFECT (Bulbapedia; the owner-supplied pokemondb page gives
## only part of it). All moves used by the bearer behave as though the weather
## were harsh sunlight:
##   * Solar Beam / Solar Blade fire in one turn, no rain/sand/snow halving
##   * Growth raises Attack and Sp. Atk by TWO stages
##   * Weather Ball becomes Fire-type at base power 100
##   * Synthesis / Moonlight / Morning Sun restore 2/3 max HP
##   * Thunder and Hurricane accuracy drops to 50%
##   * FIRE moves x1.5, WATER moves x0.5 (except Hydro Steam)
##   * ignores the sandstorm Rock Sp. Def boost and the snow Ice Def boost
##   * ignores Sand Veil / Snow Cloak accuracy reduction
## "The ability does not alter actual weather and is unaffected by Cloud Nine."
##
## LIVE IN THIS ENGINE TODAY -- exactly two of those, both for free once the view
## is threaded into the damage ctx:
##   1. Damage.weather_mult("sun", type): the bearer's Fire moves x1.5 and its
##      Water moves x0.5.
##   2. The sandstorm Rock Sp. Def boost (damage.gd) is skipped, because the view
##      the bearer's move sees is "sun", not "sandstorm".
## Every remaining bullet becomes correct automatically the day the feature that
## needs it (charge turns, Growth, Weather Ball, the healing moves, per-move
## accuracy modifiers) reads weather through this view instead of the field.
##
## SCOPE, HONESTLY: Mega Meganium is Grass/Fairy with 143 Sp. Atk and no Fire
## moves in a normal Grass learnset, so the Fire x1.5 half is mostly theoretical
## today and the Water x0.5 half is a small self-nerf. The real payoff is
## one-turn Solar Beam, and that needs charge turns to exist first.
##
## The bearer's own moves ONLY: "The effect does not extend to other Pokemon on
## the field." That is why this is keyed on the mon whose move is resolving
## (registry.weather_view(mon, weather)) and never on the field, and why ai.gd
## must score through the same view -- otherwise an AI Mega Meganium under-rates
## its own best move.
##
## It does not SET weather, so it never conflicts with Delta Stream's field
## state, never blocks a weather-setting move, and is never displaced by one.
##
## SOURCE: https://pokemondb.net/ability/mega-sol
##         https://bulbapedia.bulbagarden.net/wiki/Mega_Sol_(Ability)

## The weather every move of the bearer's is resolved under.
const VIEW := "sun"


func slug() -> String:
	return "mega-sol"


## onWeatherView. Unconditional: there is no weather the view does not replace,
## and Cloud Nine / Air Lock must suppress the FIELD, never this view.
func on_weather_view(_ctx: Dictionary) -> String:
	return VIEW
