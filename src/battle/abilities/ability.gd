extends RefCounted
## Base class for every ability implementation. **EVERY HOOK IS A NO-OP HERE.**
##
## Subclasses extend this file BY PATH, never by `class_name`:
## [codeblock]
## extends "res://src/battle/abilities/ability.gd"
## [/codeblock]
## Global class names live in `.godot/global_script_class_cache.cfg`, which only an
## editor or `--import` pass writes, so a `class_name` base breaks
## `--script res://tests/run_tests.gd` in a fresh checkout.
## `tests/framework/test_case.gd` documents the same trap.
##
## HARD RULE: an ability file must NEVER preload `registry.gd`. Abilities are
## leaves of the preload graph; the registry preloads them, not the reverse.
##
## Abilities are STATELESS. Every mutable value lives on the mon Dictionary or on
## the engine, so the registry can hold ONE shared instance per slug for the life
## of the process and hand it to both sides of every battle.
##
## The GDScript method names below are the snake_case image of the camelCase
## `hook` field `data/abilities.json` already carries (DATA_CONTRACT section 4).
##
## Each hook takes one `ctx` Dictionary and returns the NEUTRAL value defined
## here. The engine calls the registry's static dispatchers unconditionally, so
## an ability that does not override a hook costs exactly one Dictionary miss.


## The data/abilities.json slug this implements. Informational; the registry keys
## on its own IMPL table, not on this.
func slug() -> String:
	return ""


# --------------------------------------------------------------------------
# 1..3  the move pipeline
# --------------------------------------------------------------------------

## onBeforeMove. Called after Status.before_move, before the move is read.
## Returns `{cancel: bool, messages: Array}`.
func on_before_move(_ctx: Dictionary) -> Dictionary:
	return {}


## onModifyMoveType. Called on a DUPLICATE of the move dictionary, before
## anything reads it. Returns `{type: String, power_mult: float}`.
func on_modify_move(_ctx: Dictionary) -> Dictionary:
	return {}


## onDamageCalc. Called for BOTH sides; `ctx.role` is "attacker" or "defender".
## Returns `{atk_mult: float, power_mult: float, damage_mult: float}`.
func on_damage_calc(_ctx: Dictionary) -> Dictionary:
	return {}


# --------------------------------------------------------------------------
# 4..6  effectiveness, immunity, weather
# --------------------------------------------------------------------------

## onEffectiveness. Called from Damage.type_multiplier ONCE PER DEFENDER TYPE
## COMPONENT, not once per move. `ctx` = {mult, move_type, def_type, defender,
## weather}. Returns the multiplier for that one component.
func on_effectiveness(ctx: Dictionary) -> float:
	return float(ctx.get("mult", 1.0))


## onTypeImmunity. Returns `{immune: bool, heal_fraction: float, ungrounded: bool}`.
func on_type_immunity(_ctx: Dictionary) -> Dictionary:
	return {}


## onWeatherView. The weather THIS mon's move sees; the field is unchanged.
## Returns a weather String.
func on_weather_view(ctx: Dictionary) -> String:
	return String(ctx.get("weather", ""))


# --------------------------------------------------------------------------
# 7..12  the hit loop
# --------------------------------------------------------------------------

## onMultiHitCount. Decided ONCE, before the hit loop.
## Returns `{hits: int, single_accuracy: bool}`.
func on_multi_hit_count(_ctx: Dictionary) -> Dictionary:
	return {}


## onProtectCheck. Called only when the target is protected.
## Returns `{pierce: bool, damage_mult: float}`.
func on_protect_check(_ctx: Dictionary) -> Dictionary:
	return {}


## onHitTaken. After each connecting hit, BEFORE the faint break. Bearer is the
## one that was hit. Returns `{status: String, messages: Array}`.
func on_hit_taken(_ctx: Dictionary) -> Dictionary:
	return {}


## onContactHit. Same moment as [method on_hit_taken], only when `ctx.contact`.
func on_contact_taken(_ctx: Dictionary) -> Dictionary:
	return {}


## onAfterHit. After each hit; `ctx.ko` is true when that hit fainted the target.
## Returns `{stat_boosts: Dictionary, messages: Array}`.
func on_after_hit(_ctx: Dictionary) -> Dictionary:
	return {}


## onFlinch. Called only where the flinch MESSAGE is printed.
## Returns `{stat_boosts: Dictionary, messages: Array}`.
func on_flinch(_ctx: Dictionary) -> Dictionary:
	return {}


# --------------------------------------------------------------------------
# 13..17  trapping, the field, redirection
# --------------------------------------------------------------------------

## onSwitchAttempt. THE BEARER IS THE TRAPPER, `ctx.escaper` is trying to leave.
## Never called for a forced replacement after a faint.
## Returns `{block: bool, message: String}`.
func on_switch_attempt(_ctx: Dictionary) -> Dictionary:
	return {}


## onFieldEnter. Bearer entered the field, or just gained the ability (Mega
## Evolution). Returns `{weather: String, weather_turns: int, messages: Array}`.
func on_field_enter(_ctx: Dictionary) -> Dictionary:
	return {}


## Bearer left the field, fainted, or lost the ability.
func on_field_leave(_ctx: Dictionary) -> Dictionary:
	return {}


## The bearer is on the field and something about the field just changed -- it
## arrived, the weather turned, or a Mega Evolution swapped its ability. Distinct
## from [method on_field_enter], which is only for the abilities that OWN a field
## state (Delta Stream): this one is asked of every active Pokemon.
##
## Returns `{stat_mults: Dictionary, paradox_source: String, consume_item: bool,
## clear: bool, messages: Array}`. The engine writes the result to the mon; the
## ability stays stateless, exactly as `stat_boosts` already works.
func on_field_change(_ctx: Dictionary) -> Dictionary:
	return {}


## The persistent field state this ability owns, e.g. "strong-winds". "" for the
## overwhelming majority. Used by `registry.field_impls()` so a field effect is
## not tied to who happens to be attacking.
func field_state() -> String:
	return ""


## onWeatherSet. True when this ability stops `ctx.weather` from being set.
func blocks_weather_set(_ctx: Dictionary) -> bool:
	return false


## onRedirect. True when the bearer's moves ignore target redirection.
func ignores_redirection(_ctx: Dictionary) -> bool:
	return false
