extends "res://src/battle/abilities/ability.gd"
## Shared base for **Protosynthesis** and **Quark Drive**, the two Paradox
## abilities. Not registered in `registry.gd` itself -- only its two subclasses
## are, and they differ by exactly two things: the field condition that rouses
## them and the name in the message.
##
## THE RULE (both abilities, identically):
##   * Rouse when the bearer's field condition is up -- harsh sunlight for
##     Protosynthesis, Electric Terrain for Quark Drive -- or, when it is not,
##     the instant the bearer holds a **Booster Energy**, which is then used up.
##   * The bearer's HIGHEST stat is multiplied by 1.3, or by **1.5 if that stat
##     is Speed**.
##   * A field-roused boost ENDS when the field condition does. A Booster Energy
##     boost does NOT -- it lasts until the bearer leaves the field, which is
##     the whole reason the item is worth holding.
##
## SO THE SOURCE HAS TO BE REMEMBERED, not just the boost. `volatile.paradoxSource`
## is "weather" or "item"; without it, the sun going down would strip a boost that
## was paid for with an item, and there would be no way to tell the two apart.
## `Status.clear_volatiles()` drops both keys on a switch, which is exactly the
## duration the games give it.
##
## QUARK DRIVE HAS NO TERRAIN TO WAKE UP IN. This engine has weather and no
## terrain system at all, so Quark Drive is reachable only through Booster Energy
## today. That is a gap in the ENGINE, not in this file: `field_condition()` below
## is already asked for a terrain, and the day terrain exists it starts answering.
## HANDOFF.md records it.
##
## STATELESS, like every ability: the boost is returned and the ENGINE writes it
## to the mon, the same way `stat_boosts` already works for Steadfast.
##
## SOURCES: https://bulbapedia.bulbagarden.net/wiki/Protosynthesis_(Ability)
##          https://bulbapedia.bulbagarden.net/wiki/Quark_Drive_(Ability)

const Stats := preload("res://src/battle/stats.gd")

const BOOSTER_ITEM := "booster-energy"
const BOOST := 1.3
const SPEED_BOOST := 1.5

## Official tie-break order when two stats are equal: the first of these wins.
const STAT_ORDER: Array = ["atk", "def", "spa", "spd", "spe"]


## The field state that rouses this ability. Overridden by each subclass.
func field_condition() -> String:
	return ""


## What the log calls it.
func ability_name() -> String:
	return "Paradox"


## `ctx` = {mon, weather, terrain}. Returns
## `{stat_mults: Dictionary, consume_item: bool, messages: Array, clear: bool}`.
##
## `clear: true` means "take the boost away"; an empty return means "nothing
## changes", which is the overwhelmingly common case and costs one comparison.
func on_field_change(ctx: Dictionary) -> Dictionary:
	var mon: Dictionary = ctx.get("mon", {})
	if mon.is_empty() or Stats.is_fainted(mon):
		return {}

	var volatiles: Dictionary = mon.get("volatile", {})
	var source := String(volatiles.get("paradoxSource", ""))
	var roused := _condition_met(ctx)

	# Already up on the item: nothing the field does can change it.
	if source == "item":
		return {}

	if roused:
		if source == "weather":
			return {}                   # already up, and still is
		return _activate(mon, "weather", "%s was roused by the %s!" % [
			Stats.display_name(mon), _condition_label()])

	# The condition is gone. A field-roused boost goes with it.
	if source == "weather":
		return {"clear": true, "stat_mults": {}, "consume_item": false,
			"messages": ["%s's %s faded." % [Stats.display_name(mon), ability_name()]]}

	# Not roused, not boosted -- this is where the Booster Energy earns its place.
	if String(mon.get("item", "")) == BOOSTER_ITEM:
		return _activate(mon, "item", "%s used its Booster Energy to go all out!"
			% Stats.display_name(mon), true)
	return {}


func _activate(mon: Dictionary, source: String, message: String,
		consume: bool = false) -> Dictionary:
	var stat := highest_stat(mon)
	if stat.is_empty():
		return {}
	var mult := SPEED_BOOST if stat == "spe" else BOOST
	return {
		"stat_mults": {stat: mult},
		"paradox_source": source,
		"consume_item": consume,
		"messages": [message, "%s's %s was heightened!" % [
			Stats.display_name(mon), _stat_label(stat)]],
	}


## The bearer's best stat, HP excluded -- Protosynthesis never boosts HP.
##
## Read through `Stats.effective_stat()` so stat stages count, which is what the
## games do: a Pokemon at +2 Attack picks Attack even when its raw Special Attack
## is higher. The ability is not active yet at this point, so there is no risk of
## the multiplier feeding back into its own choice.
func highest_stat(mon: Dictionary) -> String:
	var best := ""
	var best_value := -1
	for key: String in STAT_ORDER:
		var value := Stats.effective_stat(mon, key)
		if value > best_value:
			best_value = value
			best = key
	return best


func _condition_met(ctx: Dictionary) -> bool:
	var want := field_condition()
	if want.is_empty():
		return false
	return String(ctx.get("weather", "")) == want or String(ctx.get("terrain", "")) == want


func _condition_label() -> String:
	match field_condition():
		"sun":
			return "harsh sunlight"
		"electric":
			return "Electric Terrain"
	return field_condition()


static func _stat_label(key: String) -> String:
	match key:
		"atk": return "Attack"
		"def": return "Defense"
		"spa": return "Sp. Atk"
		"spd": return "Sp. Def"
		"spe": return "Speed"
	return key
