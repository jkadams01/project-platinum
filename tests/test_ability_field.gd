extends "res://tests/framework/test_case.gd"
## The FIELD ability group: **delta-stream**, **steadfast**, **stalwart**. Run:
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=ability_field
##
## Every assertion here is on an OUTCOME -- a type multiplier, a damage number, a
## stat stage, `engine.weather`, a line in the battle log -- never on a hook having
## been called.
##
## THE NUMBERS ARE HAND-COMPUTED. Level 50, IV 31, EV 0, neutral nature:
##   non-HP: floor((2B + 31) / 2) + 5
##   HP:     floor((2B + 31) / 2) + 60
## Mega Rayquaza (180/100/180/100/115) at 50 -> atk 200, def 120, spe 120.
##
## The type-chart rows, straight from data/typechart.json, for Dragon/Flying:
##   ice      2.0 * 2.0 = 4.0   -> strong winds -> 2.0
##   rock     1.0 * 2.0 = 2.0   -> strong winds -> 1.0
##   electric 0.5 * 2.0 = 1.0   -> strong winds -> 0.5   <-- the decisive row
##   dragon   2.0 * 1.0 = 2.0   -> unchanged (flying is not the weakness here)
##   fighting 1.0 * 0.5 = 0.5   -> unchanged (resistances survive)
##   ground   1.0 * 0.0 = 0.0   -> unchanged (immunities survive)
## Clamping the PRODUCT to 1.0 instead of fixing each component would leave ice at
## 1.0 and raise electric to 1.0 -- wrong in opposite directions at once, which is
## why the electric row is tested first and hardest.

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Damage := preload("res://src/battle/damage.gd")
const TurnOrder := preload("res://src/battle/turn_order.gd")
const Mega := preload("res://src/battle/mega.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")

const WINDS := "strong-winds"
const WINDS_UP := "mysterious air current is protecting"
const WINDS_DOWN := "mysterious air current has dissipated"

## A tank's base stats: it must survive a STAB 120-power Dragon Ascent so the
## battle does not end and take the weather with it.
const TANK: Dictionary = {"hp": 255, "atk": 50, "def": 150, "spa": 50, "spd": 150, "spe": 50}


## `has_key_stone()` is the only thing the player side's Mega gate asks GameState.
class FakeState extends RefCounted:
	func has_key_stone() -> bool:
		return true

	func current_level_cap() -> int:
		return 100


func before_each() -> void:
	Deps.set_override("GameState", FakeState.new())
	_load_real_mega_forms()


func after_each() -> void:
	Deps.clear_overrides()


# --------------------------------------------------------------------------
# Fixtures
# --------------------------------------------------------------------------

## The REAL data/megas.json, so `rayquaza-mega` (stone null, requiresMove
## dragon-ascent, ability delta-stream) is the row under test rather than a
## hand-written stand-in. test_mega.gd injects fake tables; this undoes that.
func _load_real_mega_forms() -> void:
	Mega.clear_forms()
	var f := FileAccess.open("res://data/megas.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		Mega.set_forms((parsed as Dictionary).get("forms", []) as Array, parsed as Dictionary)


func rayquaza(opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	if not o.has("moves"):
		o["moves"] = ["dragon-ascent", "harden"]
	o["name"] = String(o.get("name", "RAYQUAZA"))
	return Stats.build(384, 50, o)


func tank(mon_name: String, types: Array, ability: String, moves: Array,
		opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	o["species_data"] = {
		"name": mon_name, "types": types, "stats": TANK,
		"abilities": [ability], "baseExp": 100, "growthRate": "medium-fast",
	}
	o["name"] = mon_name
	o["moves"] = moves
	return Stats.build(9001, 50, o)


func engine_with(player_party: Array, opp_party: Array, setup: Dictionary = {}) -> Object:
	var b := BattleEngine.new()
	var s: Dictionary = {
		"kind": "trainer", "party": player_party, "opponent": opp_party,
		"trainer": {"name": "BOSS", "ai": 5, "keyStone": true},
		"cap": 100, "seed": 20260923,
	}
	for k: Variant in setup:
		s[String(k)] = setup[k]
	b.start(s)
	return b


func log_has(eng: Object, fragment: String) -> bool:
	for line: String in (eng.battle_log as Array):
		if line.contains(fragment):
			return true
	return false


## A defender that is Dragon/Flying but does NOT own Delta Stream, which is how
## "strong winds are a FIELD state, not a bearer effect" gets proven.
func flying_bystander(types: Array = ["dragon", "flying"]) -> Dictionary:
	return {"types": PackedStringArray(types), "ability": "pressure", "hp": 100, "maxHp": 100}


# --------------------------------------------------------------------------
# delta-stream -- the per-component type rule
# --------------------------------------------------------------------------

func test_delta_stream_electric_neutral_becomes_resisted() -> void:
	# THE decisive row. A per-component fix takes 0.5 * 2.0 -> 0.5 * 1.0; clamping
	# the product to 1.0 would leave it neutral and look plausible in a log.
	var d := flying_bystander()
	almost(Damage.type_multiplier("electric", d["types"], {"defender": d}), 1.0, 0.0001,
		"electric vs dragon/flying with no winds")
	almost(Damage.type_multiplier("electric", d["types"], {"defender": d, "weather": WINDS}),
		0.5, 0.0001, "electric vs dragon/flying UNDER STRONG WINDS")


func test_delta_stream_removes_only_the_flying_weakness_component() -> void:
	var d := flying_bystander()
	var ctx: Dictionary = {"defender": d, "weather": WINDS}
	# ice 4x -> 2x: the dragon component (2.0) is untouched, the flying one is fixed.
	almost(Damage.type_multiplier("ice", d["types"], {"defender": d}), 4.0, 0.0001, "ice, no winds")
	almost(Damage.type_multiplier("ice", d["types"], ctx), 2.0, 0.0001, "ice UNDER winds is 2x, not 1x")
	# rock 2x -> 1x
	almost(Damage.type_multiplier("rock", d["types"], {"defender": d}), 2.0, 0.0001, "rock, no winds")
	almost(Damage.type_multiplier("rock", d["types"], ctx), 1.0, 0.0001, "rock UNDER winds")
	# dragon 2x unchanged: flying contributes 1.0, so there is no weakness to remove.
	almost(Damage.type_multiplier("dragon", d["types"], ctx), 2.0, 0.0001, "dragon UNDER winds")


func test_delta_stream_leaves_resistances_and_immunities_alone() -> void:
	var d := flying_bystander()
	var ctx: Dictionary = {"defender": d, "weather": WINDS}
	almost(Damage.type_multiplier("fighting", d["types"], ctx), 0.5, 0.0001,
		"fighting stays resisted UNDER winds")
	almost(Damage.type_multiplier("ground", d["types"], ctx), 0.0, 0.0001,
		"ground still does NOTHING UNDER winds -- only weaknesses are removed")


func test_delta_stream_protects_every_flying_type_on_the_field() -> void:
	# Steel/Flying, ability sturdy: nothing to do with Delta Stream. Strong winds
	# are a FIELD state, so it is protected too -- both sides, every Flying-type.
	var skarmory := flying_bystander(["steel", "flying"])
	skarmory["ability"] = "sturdy"
	almost(Damage.type_multiplier("electric", skarmory["types"], {"defender": skarmory}), 2.0,
		0.0001, "electric vs steel/flying normally")
	almost(Damage.type_multiplier("electric", skarmory["types"],
		{"defender": skarmory, "weather": WINDS}), 1.0, 0.0001,
		"electric vs steel/flying UNDER winds")
	# A non-Flying defender is not protected at all.
	var ground_mon := flying_bystander(["ground"])
	almost(Damage.type_multiplier("water", ground_mon["types"],
		{"defender": ground_mon, "weather": WINDS}), 2.0, 0.0001,
		"a non-Flying defender keeps its weakness UNDER winds")


func test_delta_stream_halves_a_real_damage_number() -> void:
	# Gengar (spa 130 -> 135 at 50) Thunderbolt (90, electric) into Mega Rayquaza's
	# typing, pinned roll and no crit so only the type multiplier can differ.
	var gengar := Stats.build(94, 50, {"moves": ["thunderbolt"], "name": "GENGAR"})
	var target := rayquaza()
	target["types"] = PackedStringArray(["dragon", "flying"])
	var move: Dictionary = (gengar["moves"] as Array)[0]
	var base_ctx: Dictionary = {"roll": 100, "crit": false}
	var plain := int(Damage.compute(gengar, target, move, base_ctx)["damage"])
	var windy_ctx := base_ctx.duplicate()
	windy_ctx["weather"] = WINDS
	var windy_hit := Damage.compute(gengar, target, move, windy_ctx)
	var windy := int(windy_hit["damage"])

	check(plain > 0, "the control hit does damage (%d)" % plain)
	almost(float(windy_hit["effectiveness"]), 0.5, 0.0001, "effectiveness reported as 0.5")
	eq(windy, plain / 2, "strong winds halve a neutral Electric hit: %d -> %d" % [plain, windy])
	check(windy < plain, "and it is strictly less")


# --------------------------------------------------------------------------
# delta-stream -- the field state, through the real turn loop
# --------------------------------------------------------------------------

func test_delta_stream_switches_on_at_mega_evolution() -> void:
	# Mega Evolution is how Rayquaza ACQUIRES the ability: mega.gd rewrites
	# mon["ability"] inside evolve(), so a switch-in-only refresh would never fire.
	var ray := rayquaza()
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([ray], [wall])

	eq(String(eng.weather), "", "no weather before the Mega")
	eq(String(ray["ability"]), "air-lock", "base Rayquaza does NOT have Delta Stream")
	is_true(eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true}),
		"Mega + move accepted")
	eng.resolve_turn()

	eq(String(ray["ability"]), "delta-stream", "the Mega granted the ability")
	eq(String(eng.weather), WINDS, "strong winds are up")
	eq(int(eng.weather_turns), 0, "weather_turns 0 -- _end_of_turn only decrements above 0")
	is_true(log_has(eng, WINDS_UP), "the log announced the air current")
	is_false(eng.over, "the battle is still going")


func test_delta_stream_persists_across_turns() -> void:
	var ray := rayquaza()
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([ray], [wall])
	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	eng.resolve_turn()
	eq(String(eng.weather), WINDS, "up after turn 1")

	for i in 3:
		eng.submit_action(0, {"kind": "move", "move_index": 1})   # Harden, harmless
		eng.resolve_turn()
	is_false(eng.over, "still going after four turns")
	eq(String(eng.weather), WINDS, "strong winds never tick down")
	is_false(log_has(eng, "The weather cleared up."), "and _end_of_turn never cleared them")


func test_delta_stream_clears_when_the_holder_switches_out() -> void:
	var ray := rayquaza()
	var backup := tank("BACKUP", ["normal"], "sturdy", ["growl"])
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([ray, backup], [wall])
	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	eng.resolve_turn()
	eq(String(eng.weather), WINDS, "winds up")

	is_true(eng.submit_action(0, {"kind": "switch", "index": 1}), "switch accepted")
	eng.resolve_turn()
	eq(String(eng.weather), "", "the holder left, so the field state ended")
	is_true(log_has(eng, WINDS_DOWN), "and said so")


func test_delta_stream_does_not_restore_the_previous_weather() -> void:
	# The games do not put the old weather back. Rain goes in, strong winds
	# displace it, and when the holder leaves the slot is simply EMPTY.
	var ray := rayquaza()
	var backup := tank("BACKUP", ["normal"], "sturdy", ["growl"])
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([ray, backup], [wall], {"weather": "rain"})
	eq(String(eng.weather), "rain", "rain first")

	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	eng.resolve_turn()
	eq(String(eng.weather), WINDS, "strong winds displaced the rain")

	eng.submit_action(0, {"kind": "switch", "index": 1})
	eng.resolve_turn()
	eq(String(eng.weather), "", "rain is NOT restored")


func test_delta_stream_clears_when_the_holder_faints() -> void:
	# A fainted holder stops holding the field: Abilities.for_mon() returns null at
	# 0 HP, and _check_faints refreshes after Mega.revert().
	var ray := rayquaza({"hp": 5})
	var backup := tank("BACKUP", ["normal"], "sturdy", ["growl"])
	# Aerial Ace: accuracy null, so it never misses and the test never flakes.
	var wall := tank("WALL", ["normal"], "sturdy", ["aerial-ace"])
	var eng := engine_with([ray, backup], [wall])
	eng.auto_player = true

	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	eng.resolve_turn()

	is_true(Stats.is_fainted(ray), "Rayquaza went down to Aerial Ace")
	is_false(eng.over, "the battle continues -- the backup is alive")
	eq(String(eng.weather), "", "the field state died with its holder")
	is_true(log_has(eng, WINDS_DOWN), "and the log says so")


func test_delta_stream_clears_at_the_end_of_the_battle() -> void:
	# _finish reverts every Mega, which takes the ability away; the field must end
	# with the battle rather than leak into the next one.
	var ray := rayquaza()
	var doomed := tank("DOOMED", ["normal"], "sturdy", ["growl"], {"hp": 20})
	var eng := engine_with([ray], [doomed])
	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	eng.resolve_turn()

	is_true(eng.over, "Dragon Ascent finished it")
	eq(String(eng.outcome), "win", "won")
	eq(String(eng.weather), "", "strong winds gone")
	eq(String(ray["ability"]), "air-lock", "and the ability reverted with the form")


func test_delta_stream_blocks_other_weather_from_being_set() -> void:
	# No weather move exists yet, so this hook has no caller -- but drizzle,
	# drought, sand-stream and snow-warning are all tier 1 and the failure mode of
	# leaving it out is invisible.
	var holder := flying_bystander()
	holder["ability"] = "delta-stream"
	for w: String in ["sun", "rain", "sandstorm", "hail", "snow"]:
		is_true(Abilities.blocks_weather_set([holder], w, WINDS),
			"strong winds refuse %s" % w)
	is_false(Abilities.blocks_weather_set([holder], WINDS, WINDS),
		"setting strong winds again is not a failure")
	is_false(Abilities.blocks_weather_set([flying_bystander()], "sun", ""),
		"a mon without the ability blocks nothing")


func test_delta_stream_field_refresh_ignores_ordinary_weather() -> void:
	# The refresh must never touch rain or sandstorm: no implementation claims them.
	var plain := flying_bystander()
	var r: Dictionary = Abilities.field_refresh([plain], "rain", 4)
	eq(String(r["weather"]), "rain", "rain survives a refresh")
	eq(int(r["weather_turns"]), 4, "and keeps its countdown")

	# A fainted holder does not hold the field.
	var dead := flying_bystander()
	dead["ability"] = "delta-stream"
	dead["hp"] = 0
	var r2: Dictionary = Abilities.field_refresh([dead], WINDS, 0)
	eq(String(r2["weather"]), "", "a fainted holder releases the field")


# --------------------------------------------------------------------------
# steadfast
# --------------------------------------------------------------------------

func test_steadfast_raises_speed_when_the_flinch_message_prints() -> void:
	var lucario := Stats.build(448, 50, {"moves": ["tackle"], "name": "LUCARIO"})
	eq(String(lucario["ability"]), "steadfast", "base Lucario ships it -- not Mega-exclusive")
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([lucario], [wall])
	(lucario["volatile"] as Dictionary)["flinch"] = true

	eng.submit_action(0, {"kind": "move", "move_index": 0})
	eng.resolve_turn()

	is_true(log_has(eng, "flinched and couldn't move!"), "the flinch message printed")
	eq(Stats.get_stage(lucario, "spe"), 1, "Speed rose one stage")
	is_true(log_has(eng, "Steadfast raised its Speed"), "and the ability said so")
	is_false(log_has(eng, "used Tackle"), "the turn is STILL LOST -- the move never happened")


func test_steadfast_control_ability_gets_no_boost() -> void:
	var lucario := Stats.build(448, 50,
		{"moves": ["tackle"], "name": "LUCARIO", "ability": "inner-focus"})
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([lucario], [wall])
	(lucario["volatile"] as Dictionary)["flinch"] = true

	eng.submit_action(0, {"kind": "move", "move_index": 0})
	eng.resolve_turn()

	is_true(log_has(eng, "flinched and couldn't move!"), "same flinch, same message")
	eq(Stats.get_stage(lucario, "spe"), 0, "no Steadfast, no Speed stage")
	is_false(log_has(eng, "raised its Speed"), "and nothing claimed otherwise")


func test_steadfast_boost_is_felt_on_the_next_turn() -> void:
	var mewtwo := Stats.build(150, 50,
		{"moves": ["tackle"], "name": "MEWTWO-X", "ability": "steadfast"})
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([mewtwo], [wall])
	var before := TurnOrder.effective_speed(mewtwo)
	(mewtwo["volatile"] as Dictionary)["flinch"] = true

	eng.submit_action(0, {"kind": "move", "move_index": 0})
	eng.resolve_turn()

	var after := TurnOrder.effective_speed(mewtwo)
	eq(Stats.get_stage(mewtwo, "spe"), 1, "one stage")
	eq(after, floori(float(before) * 1.5), "+1 Speed is a 1.5x effective speed: %d -> %d"
		% [before, after])


func test_steadfast_stops_at_plus_six() -> void:
	var lucario := Stats.build(448, 50, {"moves": ["tackle"], "name": "LUCARIO"})
	Stats.change_stage(lucario, "spe", 6)
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([lucario], [wall])
	(lucario["volatile"] as Dictionary)["flinch"] = true

	eng.submit_action(0, {"kind": "move", "move_index": 0})
	eng.resolve_turn()

	eq(Stats.get_stage(lucario, "spe"), 6, "capped at +6 like any other boost")
	is_false(log_has(eng, "raised its Speed"),
		"and no message is printed for a boost that did not happen")


func test_steadfast_does_nothing_without_a_flinch() -> void:
	var lucario := Stats.build(448, 50, {"moves": ["tackle"], "name": "LUCARIO"})
	var wall := tank("WALL", ["normal"], "sturdy", ["growl"])
	var eng := engine_with([lucario], [wall])

	eng.submit_action(0, {"kind": "move", "move_index": 0})
	eng.resolve_turn()

	eq(Stats.get_stage(lucario, "spe"), 0, "no flinch, no boost")
	is_true(log_has(eng, "used Tackle"), "and the move went through normally")


# --------------------------------------------------------------------------
# stalwart -- a DELIBERATE no-op in a single-battle engine
# --------------------------------------------------------------------------

func test_stalwart_declares_redirection_immunity() -> void:
	var skarmory := flying_bystander(["steel", "flying"])
	skarmory["ability"] = "stalwart"
	is_true(Abilities.ignores_redirection(skarmory), "Mega Skarmory ignores redirection")
	is_true(Abilities.ignores_redirection({"ability": "propeller-tail", "hp": 10})
			== Abilities.has_impl("propeller-tail"),
		"propeller-tail is the same file with a different slug, once it is registered")
	is_false(Abilities.ignores_redirection(flying_bystander()), "a control mon does not")
	is_false(Abilities.ignores_redirection({"ability": "stalwart", "hp": 0}),
		"a fainted bearer's ability does nothing")


func test_stalwart_changes_no_battle_outcome() -> void:
	# It must NOT be quietly turned into Mold Breaker. Same mon, same seed, same
	# move: identical damage, identical log, no weather.
	var attacker_a := tank("A", ["steel", "flying"], "stalwart", ["aerial-ace"])
	var attacker_b := tank("B", ["steel", "flying"], "sturdy", ["aerial-ace"])
	var target := flying_bystander(["normal"])
	target["ability"] = "pressure"
	target["stats"] = {"hp": 200, "atk": 50, "def": 100, "spa": 50, "spd": 100, "spe": 50}
	target["level"] = 50
	var move_a: Dictionary = (attacker_a["moves"] as Array)[0]
	var move_b: Dictionary = (attacker_b["moves"] as Array)[0]
	var ctx: Dictionary = {"roll": 100, "crit": false}

	var dmg_a := int(Damage.compute(attacker_a, target, move_a, ctx)["damage"])
	var dmg_b := int(Damage.compute(attacker_b, target, move_b, ctx)["damage"])
	check(dmg_a > 0, "the hit lands (%d)" % dmg_a)
	eq(dmg_a, dmg_b, "Stalwart is not a damage ability")

	var eng := engine_with([attacker_a], [tank("WALL", ["normal"], "sturdy", ["growl"])])
	eng.submit_action(0, {"kind": "move", "move_index": 0})
	eng.resolve_turn()
	eq(String(eng.weather), "", "Stalwart owns no field state")
	eq(String((Abilities.of("stalwart") as RefCounted).field_state()), "",
		"field_state() is empty, so field_impls() never picks it up")


# --------------------------------------------------------------------------
# the registry itself
# --------------------------------------------------------------------------

func test_the_field_group_is_registered() -> void:
	for slug: String in ["delta-stream", "steadfast", "stalwart"]:
		is_true(Abilities.has_impl(slug), "%s is in IMPL" % slug)
		neq(Abilities.of(slug), null, "%s resolves to an instance" % slug)
	# One shared, cached, stateless instance per slug.
	eq(Abilities.of("delta-stream"), Abilities.of("delta-stream"), "instances are cached")
	eq(String((Abilities.of("delta-stream") as RefCounted).field_state()), WINDS,
		"only delta-stream owns a field state")
	eq(Abilities.field_impls(WINDS).size(), 1, "exactly one implementation holds strong-winds")
	eq(Abilities.field_impls("").size(), 0,
		'"" is the ABSENCE of a field state, not a state every ability matches')


func test_an_unimplemented_ability_is_a_complete_no_op() -> void:
	var stench: Dictionary = {"ability": "stench", "hp": 10, "maxHp": 10,
		"types": PackedStringArray(["normal"]), "stats": {"spe": 100}, "volatile": {}}
	eq(Abilities.of("stench"), null, "no implementation")
	eq(Abilities.for_mon(stench), null, "and none for the mon")
	eq(Abilities.flinch(stench), {}, "onFlinch neutral")
	eq(Abilities.escape_block(stench, stench, "switch"), {}, "onSwitchAttempt neutral")
	is_false(Abilities.ignores_redirection(stench), "onRedirect neutral")
	is_false(Abilities.blocks_weather_set([stench], "sun", ""), "onWeatherSet neutral")
	eq(String(Abilities.weather_view(stench, "rain")), "rain", "onWeatherView neutral")
	almost(Abilities.effectiveness(4.0, "ice", "flying", stench, ""), 4.0, 0.0001,
		"onEffectiveness neutral with no field state")
	var r: Dictionary = Abilities.field_refresh([stench], "", 0)
	eq(String(r["weather"]), "", "field_refresh neutral")
