extends "res://src/battle/abilities/ability.gd"
## **Delta Stream** -- Mega Rayquaza (`rayquaza-mega`, the stoneless form that
## Mega Evolves off `requiresMove: dragon-ascent`). Mega-exclusive.
##
## Sets the persistent field state `strong-winds` on entering the field OR on
## gaining the ability, and holds it while an active Pokemon has Delta Stream.
##
## THE TYPE RULE IS PER DEFENDING-TYPE-COMPONENT, not per move. For each of the
## defender's types: if that type is `flying` and its own multiplier against the
## incoming move type is > 1, that component becomes 1.0.
##
## Worked examples against Dragon/Flying (Mega Rayquaza itself):
## [codeblock]
##   Ice       4x -> 2x     (dragon 2 * flying 2 -> dragon 2 * 1)
##   Rock      2x -> 1x     (flying 2 -> 1)
##   Electric  1x -> 0.5x   (dragon 0.5 * flying 2 -> dragon 0.5 * 1)
##   Dragon    2x -> 2x     (dragon 2 * flying 1; flying is not a weakness here)
##   Fighting  0.5x         (untouched: only WEAKNESSES are removed)
##   Ground    0x           (untouched: immunity survives)
## [/codeblock]
## Clamping the *product* to 1.0 instead would leave Ice at 1x and Electric at 1x
## -- wrong in opposite directions. The Electric row is the sharpest single test:
## a neutral matchup becomes a resisted one.
##
## It is a FIELD state, not a bearer effect: it protects every Flying-type on the
## field, on BOTH sides. That is why `registry.effectiveness()` resolves it
## through `field_impls(weather)` and never through the defender's own ability.
##
## It occupies the weather slot with `weather_turns = 0`; `battle_engine._end_of_turn`
## only decrements when `> 0`, so 0 already means "infinite".
## `Damage.weather_mult()` has no row for it, so no Fire/Water multiplier leaks in.
##
## Sunny Day / Rain Dance / Sandstorm / Hail fail while it holds, and Drought /
## Drizzle / Sand Stream / Snow Warning fail to activate -- [method blocks_weather_set].
## It has no caller today (the engine has no weather-setting move), but every one
## of those four abilities is tier 1 and will arrive.
##
## When the holder leaves, the field simply CLEARS. The previous weather is not
## restored; the games do not restore it.
##
## Strong winds do not affect Stealth Rock or Anticipation.
##
## SOURCE: https://bulbapedia.bulbagarden.net/wiki/Delta_Stream_(Ability)
##         https://bulbapedia.bulbagarden.net/wiki/Strong_winds

## The field state slug. Also the value stored in `battle_engine.weather`.
const FIELD := "strong-winds"

## The only defending type strong winds protect.
const PROTECTED_TYPE := "flying"

const ENTER_MESSAGE := "A mysterious air current is protecting Flying-type Pokemon!"
const LEAVE_MESSAGE := "The mysterious air current has dissipated!"


func slug() -> String:
	return "delta-stream"


func field_state() -> String:
	return FIELD


func on_field_enter(_ctx: Dictionary) -> Dictionary:
	return {"weather": FIELD, "weather_turns": 0, "messages": [ENTER_MESSAGE]}


func on_field_leave(_ctx: Dictionary) -> Dictionary:
	return {"weather": "", "weather_turns": 0, "messages": [LEAVE_MESSAGE]}


## One defender type component. `ctx` = {mult, move_type, def_type, defender, weather}.
func on_effectiveness(ctx: Dictionary) -> float:
	var mult := float(ctx.get("mult", 1.0))
	if String(ctx.get("weather", "")) != FIELD:
		return mult
	if String(ctx.get("def_type", "")).to_lower() != PROTECTED_TYPE:
		return mult
	# Only weaknesses are removed. Resistances and immunities are untouched.
	if mult > 1.0:
		return 1.0
	return mult


## Nothing may replace strong winds while they hold -- not a weather move, not a
## weather ability. Setting strong winds again is a no-op rather than a failure.
func blocks_weather_set(ctx: Dictionary) -> bool:
	return String(ctx.get("weather", "")) != FIELD
