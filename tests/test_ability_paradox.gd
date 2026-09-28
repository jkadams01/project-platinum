extends "res://tests/framework/test_case.gd"
## Protosynthesis, Quark Drive, and the Booster Energy that rouses them.
##
## WHAT MAKES THESE TWO DIFFERENT from every other ability already implemented:
## they hold a multiplier on ONE stat, for a duration that depends on WHERE the
## boost came from. A sun-roused boost ends with the sun; an item-roused one lasts
## until the bearer leaves the field. Forget which, and the sun going down strips a
## boost that was paid for with an item -- so `paradoxSource` is checked as
## carefully here as the multiplier itself.
##
## They are also the first abilities to use `volatile.statMult`, which is a flat
## multiplier rather than a stat stage. That distinction is load-bearing: a stage
## would round to the wrong number and a critical hit would ignore it.

const Abilities := preload("res://src/battle/abilities/registry.gd")
const Stats := preload("res://src/battle/stats.gd")
const TurnOrder := preload("res://src/battle/turn_order.gd")
const Items := preload("res://src/battle/items.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const Deps := preload("res://src/battle/deps.gd")

## Great Tusk (Protosynthesis, physical) and Iron Valiant (Quark Drive).
const GREAT_TUSK := 984
const IRON_VALIANT := 1006
const MAGIKARP := 129

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	Deps.clear_overrides()
	DataRegistry.boot(DataRegistry.DATA_DIR)


func after_each() -> void:
	Deps.clear_overrides()
	Log.level = _saved_level


func _have_data() -> bool:
	return DataRegistry.species_count() > 0


## A mon with a pinned stat spread, so "the highest stat" is not a data question.
func _mon(ability: String, item: String, stats: Dictionary) -> Dictionary:
	var mon := PartyBuilder.wild(MAGIKARP, 50, {"ability": ability, "item": item,
		"moves": ["tackle"]})
	mon["stats"] = stats.duplicate()
	mon["maxHp"] = int(stats.get("hp", 100))
	mon["hp"] = int(mon["maxHp"])
	return mon


const SPREAD: Dictionary = {"hp": 200, "atk": 180, "def": 100, "spa": 90, "spd": 95, "spe": 120}


# --------------------------------------------------------------------------
# Registration
# --------------------------------------------------------------------------

func test_both_abilities_register() -> void:
	is_true(Abilities.has_impl("protosynthesis"), "protosynthesis is registered")
	is_true(Abilities.has_impl("quark-drive"), "quark-drive is registered")
	eq(Abilities.of("protosynthesis").slug(), "protosynthesis", "and reports its own slug")
	eq(Abilities.of("quark-drive").slug(), "quark-drive", "and so does the other")
	# They share a base class but must NOT share an instance, or one battle's
	# bearer would be indistinguishable from the other's.
	neq(Abilities.of("protosynthesis"), Abilities.of("quark-drive"),
		"they are distinct instances")
	# The shared base is not an ability and must never be registered.
	is_false(Abilities.slugs().has("paradox"), "paradox.gd is a base, not an ability")


func test_the_data_says_they_are_implemented() -> void:
	if not _have_data():
		pending("data/abilities.json is not built")
		return
	for slug: String in ["protosynthesis", "quark-drive"]:
		var row: Dictionary = DataRegistry.get_ability_by_name(slug)
		is_false(row.is_empty(), "%s has a row" % slug)
		eq(int(row.get("tier", 0)), 1,
			"%s must be tier 1 now that it is implemented, or the builder lies" % slug)


# --------------------------------------------------------------------------
# Which stat, and by how much
# --------------------------------------------------------------------------

func test_it_boosts_the_highest_stat() -> void:
	var impl := Abilities.of("protosynthesis")
	var attacker := _mon("protosynthesis", "", SPREAD)
	eq(impl.highest_stat(attacker), "atk", "Attack is the highest of the spread")

	var fast := _mon("protosynthesis", "",
		{"hp": 200, "atk": 100, "def": 100, "spa": 90, "spd": 95, "spe": 180})
	eq(impl.highest_stat(fast), "spe", "Speed when Speed is highest")

	# Stat stages count: a Pokemon at +2 Attack picks Attack even when another
	# raw stat is higher, which is what the games do.
	var boosted := _mon("protosynthesis", "",
		{"hp": 200, "atk": 100, "def": 100, "spa": 150, "spd": 95, "spe": 80})
	eq(impl.highest_stat(boosted), "spa", "Sp. Atk on the raw spread")
	Stats.change_stage(boosted, "atk", 2)
	eq(impl.highest_stat(boosted), "atk", "but Attack once it is at +2")

	# HP is never chosen, however large it is.
	var tanky := _mon("protosynthesis", "",
		{"hp": 999, "atk": 50, "def": 60, "spa": 40, "spd": 45, "spe": 30})
	eq(impl.highest_stat(tanky), "def", "HP is excluded; the best real stat wins")


func test_the_multiplier_is_1_3_or_1_5_for_speed() -> void:
	var impl := Abilities.of("protosynthesis")

	var attacker := _mon("protosynthesis", "", SPREAD)
	var res: Dictionary = impl.on_field_change({"mon": attacker, "weather": "sun"})
	eq(float((res["stat_mults"] as Dictionary)["atk"]), 1.3, "1.3 on a normal stat")

	var fast := _mon("protosynthesis", "",
		{"hp": 200, "atk": 100, "def": 100, "spa": 90, "spd": 95, "spe": 180})
	var res2: Dictionary = impl.on_field_change({"mon": fast, "weather": "sun"})
	eq(float((res2["stat_mults"] as Dictionary)["spe"]), 1.5, "and 1.5 when it is Speed")


func test_the_multiplier_reaches_the_stats_that_matter() -> void:
	var mon := _mon("protosynthesis", "", SPREAD)
	var before := Stats.effective_stat(mon, "atk")
	var speed_before := TurnOrder.effective_speed(mon)

	mon["volatile"]["statMult"] = {"atk": 1.3}
	eq(Stats.effective_stat(mon, "atk"), int(float(before) * 1.3),
		"effective_stat applies it, so damage.gd sees it")
	eq(TurnOrder.effective_speed(mon), speed_before, "and Speed is untouched")

	mon["volatile"]["statMult"] = {"spe": 1.5}
	is_true(TurnOrder.effective_speed(mon) > speed_before,
		"a Speed boost reaches turn order: %d -> %d" % [
			speed_before, TurnOrder.effective_speed(mon)])


# --------------------------------------------------------------------------
# What rouses them, and for how long
# --------------------------------------------------------------------------

func test_sun_rouses_protosynthesis_and_dusk_ends_it() -> void:
	var impl := Abilities.of("protosynthesis")
	var mon := _mon("protosynthesis", "", SPREAD)

	var up: Dictionary = impl.on_field_change({"mon": mon, "weather": "sun"})
	is_false(up.is_empty(), "the sun rouses it")
	eq(String(up.get("paradox_source", "")), "weather", "from the weather")
	is_false(bool(up.get("consume_item", false)), "and costs no item")

	# Simulate the engine writing it back, then ask again in the same sun.
	mon["volatile"]["statMult"] = up["stat_mults"]
	mon["volatile"]["paradoxSource"] = "weather"
	is_true(impl.on_field_change({"mon": mon, "weather": "sun"}).is_empty(),
		"asking again in the same sun changes nothing")

	var down: Dictionary = impl.on_field_change({"mon": mon, "weather": ""})
	is_true(bool(down.get("clear", false)), "and the boost goes when the sun does")


func test_rain_does_not_rouse_protosynthesis() -> void:
	var impl := Abilities.of("protosynthesis")
	var mon := _mon("protosynthesis", "", SPREAD)
	is_true(impl.on_field_change({"mon": mon, "weather": "rain"}).is_empty(),
		"only harsh sunlight will do")
	is_true(impl.on_field_change({"mon": mon, "weather": "sandstorm"}).is_empty(),
		"a sandstorm is not sunlight either")


func test_quark_drive_wants_electric_terrain_which_this_engine_has_none_of() -> void:
	var impl := Abilities.of("quark-drive")
	eq(impl.field_condition(), "electric",
		"it is written against the rule it actually has")
	var mon := _mon("quark-drive", "", SPREAD)
	is_true(impl.on_field_change({"mon": mon, "weather": "sun"}).is_empty(),
		"the sun does nothing for Quark Drive")
	# The day a terrain system lands, this is what will start working -- nothing
	# in the ability changes.
	is_false(impl.on_field_change({"mon": mon, "terrain": "electric"}).is_empty(),
		"and Electric Terrain would rouse it")


# --------------------------------------------------------------------------
# Booster Energy
# --------------------------------------------------------------------------

func test_booster_energy_rouses_either_ability_and_is_spent() -> void:
	for slug: String in ["protosynthesis", "quark-drive"]:
		var impl := Abilities.of(slug)
		var mon := _mon(slug, "booster-energy", SPREAD)
		var res: Dictionary = impl.on_field_change({"mon": mon, "weather": ""})
		is_false(res.is_empty(), "%s: the item rouses it with no weather at all" % slug)
		eq(String(res.get("paradox_source", "")), "item", "%s: from the item" % slug)
		is_true(bool(res.get("consume_item", false)), "%s: and it is spent" % slug)
		eq(float((res["stat_mults"] as Dictionary)["atk"]), 1.3, "%s: on its best stat" % slug)


func test_an_item_boost_outlasts_the_weather() -> void:
	# The whole reason to hold one: the sun can go down and the boost stays.
	var impl := Abilities.of("protosynthesis")
	var mon := _mon("protosynthesis", "booster-energy", SPREAD)
	var res: Dictionary = impl.on_field_change({"mon": mon, "weather": ""})
	mon["volatile"]["statMult"] = res["stat_mults"]
	mon["volatile"]["paradoxSource"] = "item"

	is_true(impl.on_field_change({"mon": mon, "weather": ""}).is_empty(),
		"nothing further happens without weather")
	is_true(impl.on_field_change({"mon": mon, "weather": "sun"}).is_empty(),
		"the sun coming out does not re-roll it")
	is_true(impl.on_field_change({"mon": mon, "weather": "rain"}).is_empty(),
		"and rain does NOT take it away, which a weather-roused boost would lose")


func test_the_sun_means_the_item_is_not_wasted() -> void:
	# Roused by the sun, the Booster Energy stays in the bag for later.
	var impl := Abilities.of("protosynthesis")
	var mon := _mon("protosynthesis", "booster-energy", SPREAD)
	var res: Dictionary = impl.on_field_change({"mon": mon, "weather": "sun"})
	eq(String(res.get("paradox_source", "")), "weather", "the sun wins")
	is_false(bool(res.get("consume_item", false)), "so the item is NOT spent")


func test_the_item_is_marked_implemented_now() -> void:
	is_true(Items.implemented("booster-energy"),
		"the builder must stop calling it 'no effect'")
	if not _have_data():
		pending("data/items.json is not built")
		return
	eq(int(Items.row("booster-energy").get("tier", 0)), 1, "and the data agrees")


# --------------------------------------------------------------------------
# End to end, through the engine
# --------------------------------------------------------------------------

func test_a_booster_energy_fires_on_the_lead_and_raises_a_real_stat() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var holder := PartyBuilder.wild(MAGIKARP, 50,
		{"ability": "protosynthesis", "item": "booster-energy", "moves": ["tackle"]})
	var foe := PartyBuilder.wild(MAGIKARP, 5, {"moves": ["splash"]})
	var best: String = (Abilities.of("protosynthesis") as RefCounted).highest_stat(holder)
	var before := Stats.effective_stat(holder, best)

	var e := BattleEngineScript.new()
	e.start({"kind": "trainer", "party": [holder], "opponent": [foe],
		"cap": 100, "seed": 5, "awardExp": false, "trainer": {"name": "T", "ai": 0}})

	eq(String(holder.get("item", "")), "", "the Booster Energy was spent on the lead")
	eq(String(holder.get("usedItem", "")), "booster-energy", "and recorded as used")
	is_true(Stats.effective_stat(holder, best) > before,
		"%s really went up: %d -> %d" % [best, before,
			Stats.effective_stat(holder, best)])
	var said := false
	for line: String in e.battle_log:
		if line.contains("Booster Energy"):
			said = true
			break
	is_true(said, "and the log says so")


func test_the_sun_rouses_it_through_a_real_battle() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var holder := PartyBuilder.wild(MAGIKARP, 50,
		{"ability": "protosynthesis", "moves": ["tackle"]})
	var foe := PartyBuilder.wild(MAGIKARP, 5, {"moves": ["splash"]})
	var e := BattleEngineScript.new()
	e.start({"kind": "trainer", "party": [holder], "opponent": [foe],
		"cap": 100, "seed": 5, "awardExp": false, "weather": "sun",
		"trainer": {"name": "T", "ai": 0}})
	var boost: Variant = (holder.get("volatile", {}) as Dictionary).get("statMult", null)
	is_true(boost is Dictionary and not (boost as Dictionary).is_empty(),
		"a battle that starts in the sun rouses it with no item at all")
	eq(String((holder["volatile"] as Dictionary).get("paradoxSource", "")), "weather",
		"from the weather")


func test_switching_out_ends_it() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var holder := PartyBuilder.wild(MAGIKARP, 50,
		{"ability": "protosynthesis", "item": "booster-energy", "moves": ["tackle"]})
	var bench := PartyBuilder.wild(MAGIKARP, 50, {"moves": ["tackle"]})
	var foe := PartyBuilder.wild(MAGIKARP, 5, {"moves": ["splash"]})
	var e := BattleEngineScript.new()
	e.start({"kind": "trainer", "party": [holder, bench], "opponent": [foe],
		"cap": 100, "seed": 5, "awardExp": false, "trainer": {"name": "T", "ai": 0}})
	is_false((holder["volatile"] as Dictionary).get("statMult", {}).is_empty(),
		"it is up after the lead")

	e.submit_action(0, {"kind": "switch", "index": 1})
	e.resolve_turn()
	# Status.clear_volatiles() on the switch is what drops it, which is exactly
	# the duration the games give an item-roused boost.
	is_true((holder.get("volatile", {}) as Dictionary).get("statMult", {}).is_empty(),
		"and gone once it leaves the field")
