extends "res://tests/framework/test_case.gd"
## Battle engine tests. Run:
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=battle
##
## Every damage number in here is hand-computed in the comment above the
## assertion, from the formula in src/battle/damage.gd. If the engine changes and
## a number moves, the comment says whether the new number is right.
##
## Moves come from the committed `data/moves.json` (DATA_CONTRACT 2) so the tests
## exercise the real data path; base stats are pinned inline so the arithmetic
## does not depend on the species table being finished.

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Damage := preload("res://src/battle/damage.gd")
const TurnOrder := preload("res://src/battle/turn_order.gd")
const Exp := preload("res://src/battle/exp.gd")
const AI := preload("res://src/battle/ai.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")


## Records EventBus emissions without needing the autoload to exist.
class SignalSpy extends RefCounted:
	var capped: Array = []
	var ended: Array = []

	func _init() -> void:
		add_user_signal("exp_capped")
		add_user_signal("battle_started")
		add_user_signal("battle_ended")
		connect("exp_capped", _on_capped)
		connect("battle_ended", _on_ended)

	func _on_capped(pokemon: Dictionary, cap: int) -> void:
		capped.append({"pokemon": pokemon, "cap": cap})

	func _on_ended(r: Dictionary) -> void:
		ended.append(r)


var spy: SignalSpy


func before_each() -> void:
	Deps.clear_overrides()
	spy = SignalSpy.new()
	Deps.set_override("EventBus", spy)


func after_each() -> void:
	Deps.clear_overrides()


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

## A Pokemon with *pinned* battle stats, so damage arithmetic is exact.
## `stats` is {hp,atk,def,spa,spd,spe}; `moves` are slugs from data/moves.json.
func fixture(mon_name: String, types: Array, level: int, stats: Dictionary,
		moves: Array = [], opts: Dictionary = {}) -> Dictionary:
	var species_data: Dictionary = {
		"name": mon_name, "types": types,
		"stats": {"hp": 50, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50},
		"abilities": [String(opts.get("ability", ""))],
		"baseExp": int(opts.get("baseExp", 64)),
		"growthRate": String(opts.get("growthRate", "medium-fast")),
	}
	var build_opts := opts.duplicate()
	build_opts["species_data"] = species_data
	build_opts["name"] = mon_name
	build_opts["moves"] = moves
	var mon := Stats.build(int(opts.get("species", 1)), level, build_opts)
	mon["stats"] = stats.duplicate()
	mon["maxHp"] = int(stats.get("hp", 100))
	mon["hp"] = int(opts.get("hp", mon["maxHp"]))
	return mon


func plain_move(move_name: String, move_type: String, category: String, power: int,
		priority: int = 0) -> Dictionary:
	return {
		"id": 0, "name": move_name, "slug": move_name.to_lower(), "type": move_type,
		"category": category, "power": power, "accuracy": 100, "pp": 10, "maxPp": 10,
		"priority": priority, "effect": "", "effectChance": 0,
	}


func seeded(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# --------------------------------------------------------------------------
# damage
# --------------------------------------------------------------------------

## HAND COMPUTED, level 50, Atk 100 vs Def 100, 60-power physical, no STAB,
## neutral, no crit:
##   levelFactor = floor(2*50/5) + 2                 = 22
##   inner       = floor(22 * 60 * 100 / 100)        = 1320
##   base        = floor(1320 / 50) + 2              = 28
##   roll 85     = floor(28 * 85 / 100)              = 23
##   roll 100    = floor(28 * 100 / 100)             = 28
func test_damage_known_roll_range_matches_hand_computation() -> void:
	var attacker := fixture("ATTACKER", ["fighting"], 50,
		{"hp": 150, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	var defender := fixture("DEFENDER", ["normal"], 50,
		{"hp": 150, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	var move := plain_move("Test Pound", "normal", "physical", 60)

	var lo := Damage.compute(attacker, defender, move, {"roll": 85, "crit": false})
	var hi := Damage.compute(attacker, defender, move, {"roll": 100, "crit": false})
	eq(int(lo["base"]), 28, "base damage")
	eq(int(lo["damage"]), 23, "min roll (85)")
	eq(int(hi["damage"]), 28, "max roll (100)")
	almost(float(hi["effectiveness"]), 1.0, 0.0001, "normal vs normal")

	var span := Damage.roll_range(attacker, defender, move, {"crit": false})
	eq(span, Vector2i(23, 28), "roll_range")

	# Every one of the 16 rolls stays inside the hand-computed band.
	for roll in range(Damage.MIN_ROLL, Damage.MAX_ROLL + 1):
		var d := int(Damage.compute(attacker, defender, move, {"roll": roll, "crit": false})["damage"])
		check(d >= 23 and d <= 28, "roll %d gave %d, outside 23..28" % [roll, d])


## Real move, real type chart: Thunderbolt (90 BP special, electric) from an
## Electric attacker into a Water defender, level 50, SpA 100 vs SpD 100:
##   base = floor(floor(22 * 90 * 100/100) / 50) + 2 = 41
##   roll 100: 41 -> STAB floor(61.5)=61 -> x2 = 122
##   roll  85: floor(41*0.85)=34 -> STAB 51 -> x2 = 102
func test_real_move_and_type_chart_produce_hand_computed_damage() -> void:
	var pikachu := fixture("PIKACHU", ["electric"], 50,
		{"hp": 110, "atk": 75, "def": 60, "spa": 100, "spd": 100, "spe": 110},
		["thunderbolt"])
	var gyarados := fixture("GYARADOS", ["water", "flying"], 50,
		{"hp": 180, "atk": 150, "def": 100, "spa": 80, "spd": 100, "spe": 100})
	check(not (pikachu["moves"] as Array).is_empty(), "thunderbolt resolved from data/moves.json")
	if (pikachu["moves"] as Array).is_empty():
		return
	var bolt: Dictionary = (pikachu["moves"] as Array)[0]
	eq(int(bolt["power"]), 90, "Thunderbolt power")
	eq(String(bolt["type"]), "electric", "Thunderbolt type")

	# water x2, flying x2 -> x4 on Gyarados. Use a pure-Water target for the
	# hand-computed number and check the dual type separately.
	var vaporeon := fixture("VAPOREON", ["water"], 50,
		{"hp": 180, "atk": 80, "def": 80, "spa": 100, "spd": 100, "spe": 80})
	var hi := Damage.compute(pikachu, vaporeon, bolt, {"roll": 100, "crit": false})
	var lo := Damage.compute(pikachu, vaporeon, bolt, {"roll": 85, "crit": false})
	eq(int(hi["base"]), 41, "base")
	almost(float(hi["stab"]), 1.5, 0.0001, "STAB applied")
	almost(float(hi["effectiveness"]), 2.0, 0.0001, "electric vs water")
	eq(int(hi["damage"]), 122, "max roll")
	eq(int(lo["damage"]), 102, "min roll")

	almost(Damage.type_multiplier("electric", gyarados["types"]), 4.0, 0.0001,
		"electric vs water/flying")


func test_electric_move_vs_ground_type_deals_zero() -> void:
	var pikachu := fixture("PIKACHU", ["electric"], 50,
		{"hp": 110, "atk": 75, "def": 60, "spa": 200, "spd": 100, "spe": 110},
		["thunderbolt"])
	var golem := fixture("GOLEM", ["rock", "ground"], 50,
		{"hp": 160, "atk": 140, "def": 180, "spa": 60, "spd": 80, "spe": 60})
	var bolt: Dictionary = (pikachu["moves"] as Array)[0]

	almost(Damage.type_multiplier("electric", golem["types"]), 0.0, 0.0001,
		"electric vs rock/ground")
	var hit := Damage.compute(pikachu, golem, bolt, {"roll": 100, "crit": true})
	eq(int(hit["damage"]), 0, "damage against an immune type")
	is_true(bool(hit["immune"]), "reported as immune")

	# And through the engine: HP must not move.
	var diglett := fixture("DIGLETT", ["ground"], 50,
		{"hp": 100, "atk": 55, "def": 25, "spa": 35, "spd": 45, "spe": 95},
		["tackle"])
	var engine := BattleEngine.new()
	engine.start({"kind": "wild", "party": [pikachu], "opponent": [diglett],
		"cap": 100, "seed": 7})
	var before := int(diglett["hp"])
	engine.submit_action(0, {"kind": "move", "move_index": 0})
	engine.submit_action(1, {"kind": "move", "move_index": 0})
	engine.resolve_turn()
	eq(int(diglett["hp"]), before, "Thunderbolt did not scratch the Ground-type")
	check(engine.battle_log.has("It doesn't affect DIGLETT..."),
		"immunity message logged, got %s" % [engine.battle_log])


func test_stab_applies_exactly_1_5x() -> void:
	var stats := {"hp": 150, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100}
	var with_stab := fixture("STABBER", ["normal"], 50, stats)
	var without := fixture("NEUTRAL", ["fighting"], 50, stats)
	var defender := fixture("TARGET", ["normal"], 50, stats)
	var move := plain_move("Test Pound", "normal", "physical", 60)

	var a := Damage.compute(without, defender, move, {"roll": 100, "crit": false})
	var b := Damage.compute(with_stab, defender, move, {"roll": 100, "crit": false})
	almost(float(a["stab"]), 1.0, 0.0001, "no STAB for a Fighting-type")
	almost(float(b["stab"]), 1.5, 0.0001, "STAB for a Normal-type")
	eq(int(a["damage"]), 28, "without STAB")
	eq(int(b["damage"]), 42, "with STAB: floor(28 * 1.5)")
	eq(int(b["damage"]), floori(float(a["damage"]) * 1.5), "exactly 1.5x at the same roll")


func test_critical_hit_multiplies_by_1_5_and_ignores_defence_boosts() -> void:
	var stats := {"hp": 150, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100}
	var attacker := fixture("ATTACKER", ["fighting"], 50, stats)
	var defender := fixture("DEFENDER", ["normal"], 50, stats)
	var move := plain_move("Test Pound", "normal", "physical", 60)

	# base 28 -> crit floor(28*1.5)=42 -> roll 100 -> 42
	eq(int(Damage.compute(attacker, defender, move, {"roll": 100, "crit": true})["damage"]),
		42, "critical hit")

	# +2 Def (x2.0) halves the damage: base = floor(floor(22*60*100/200)/50)+2 = 15
	Stats.change_stage(defender, "def", 2)
	eq(int(Damage.compute(attacker, defender, move, {"roll": 100, "crit": false})["damage"]),
		15, "+2 Def resists")
	# ...but a crit ignores the defender's boost, so it is back to 42.
	eq(int(Damage.compute(attacker, defender, move, {"roll": 100, "crit": true})["damage"]),
		42, "crit ignores the defender's Def boost")


func test_burn_halves_physical_damage_but_not_special() -> void:
	var stats := {"hp": 150, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100}
	var attacker := fixture("ATTACKER", ["fighting"], 50, stats)
	var defender := fixture("DEFENDER", ["normal"], 50, stats)
	var physical := plain_move("Test Pound", "normal", "physical", 60)
	var special := plain_move("Test Beam", "normal", "special", 60)

	var phys_before := int(Damage.compute(attacker, defender, physical, {"roll": 100, "crit": false})["damage"])
	var spec_before := int(Damage.compute(attacker, defender, special, {"roll": 100, "crit": false})["damage"])
	attacker["status"] = Status.BURN
	var phys_after := int(Damage.compute(attacker, defender, physical, {"roll": 100, "crit": false})["damage"])
	var spec_after := int(Damage.compute(attacker, defender, special, {"roll": 100, "crit": false})["damage"])

	eq(phys_before, 28, "physical before burn")
	eq(phys_after, 14, "physical halved by burn")
	eq(spec_before, spec_after, "special damage untouched by burn")


# --------------------------------------------------------------------------
# stats
# --------------------------------------------------------------------------

## Pikachu, level 50, 31 IVs, 0 EVs, neutral nature:
##   HP  = floor((2*35 + 31) * 50 / 100) + 50 + 10 = 50 + 60  = 110
##   Spe = floor((2*90 + 31) * 50 / 100) + 5       = 105 + 5  = 110
##   Atk = floor((2*55 + 31) * 50 / 100) + 5       = 70 + 5   = 75
## Adamant (+Atk) => floor(75 * 1.1) = 82
func test_stat_formula_and_natures_match_known_values() -> void:
	var base := {"hp": 35, "atk": 55, "def": 40, "spa": 50, "spd": 50, "spe": 90}
	var ivs := [31, 31, 31, 31, 31, 31]
	var evs := [0, 0, 0, 0, 0, 0]

	var neutral := Stats.calc_all(base, ivs, evs, 50, "hardy")
	eq(int(neutral["hp"]), 110, "Pikachu L50 HP")
	eq(int(neutral["spe"]), 110, "Pikachu L50 Speed")
	eq(int(neutral["atk"]), 75, "Pikachu L50 Attack")

	var adamant := Stats.calc_all(base, ivs, evs, 50, "adamant")
	eq(int(adamant["atk"]), 82, "Adamant raises Attack 10%")
	eq(int(adamant["spa"]), floori(float(neutral["spa"]) * 0.9), "Adamant lowers Sp. Atk 10%")
	eq(int(adamant["hp"]), 110, "nature never touches HP")

	almost(Stats.nature_mult("hardy", "atk"), 1.0, 0.0001, "neutral nature")
	eq(Stats.NATURES.size(), 25, "all 25 natures present")

	# 252 Atk EVs: floor(252/4) = 63 added to the (2B + IV) term.
	#   floor((2*55 + 31 + 63) * 50 / 100) + 5 = floor(204 * 0.5) + 5 = 107
	var trained := Stats.calc_all(base, ivs, [0, 252, 0, 0, 0, 0], 50, "hardy")
	eq(int(trained["atk"]), 107, "252 Atk EVs")
	eq(int(trained["atk"]) - int(neutral["atk"]), 32, "252 EVs are worth +32 at L50")


func test_stat_stages_clamp_at_plus_minus_6_and_scale_correctly() -> void:
	var mon := fixture("MON", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})

	eq(Stats.effective_stat(mon, "atk"), 100, "no stage")
	Stats.change_stage(mon, "atk", 2)
	eq(Stats.effective_stat(mon, "atk"), 200, "+2 is x2.0")
	Stats.change_stage(mon, "atk", -4)
	eq(Stats.effective_stat(mon, "atk"), 50, "-2 is x0.5")

	eq(Stats.change_stage(mon, "atk", -10), -4, "clamped delta down to -6")
	eq(Stats.get_stage(mon, "atk"), -6, "floor at -6")
	eq(Stats.effective_stat(mon, "atk"), 25, "-6 is x0.25")
	eq(Stats.change_stage(mon, "atk", 99), 12, "clamped delta up to +6")
	eq(Stats.get_stage(mon, "atk"), 6, "ceiling at +6")
	eq(Stats.effective_stat(mon, "atk"), 400, "+6 is x4.0")

	almost(Stats.acc_stage_mult(0), 1.0, 0.0001, "accuracy stage 0")
	almost(Stats.acc_stage_mult(6), 3.0, 0.0001, "accuracy +6 is x3")
	almost(Stats.acc_stage_mult(-6), 1.0 / 3.0, 0.0001, "accuracy -6 is x1/3")

	# A never-miss move (accuracy null, DATA_CONTRACT 2) ignores evasion entirely.
	var dodger := fixture("DODGER", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	Stats.change_stage(dodger, "eva", 6)
	is_true(Stats.accuracy_check(null, mon, dodger, seeded(1)), "null accuracy never misses")


# --------------------------------------------------------------------------
# status
# --------------------------------------------------------------------------

func test_paralysis_halves_speed() -> void:
	var mon := fixture("SPEEDY", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	eq(TurnOrder.effective_speed(mon), 100, "healthy Speed")
	var applied := Status.apply(mon, Status.PARALYSIS, seeded(1))
	is_true(bool(applied["ok"]), "paralysis applied")
	eq(Status.status_of(mon), "paralysis", "status field")
	eq(TurnOrder.effective_speed(mon), 50, "paralysis halves Speed")
	almost(Status.speed_mult(mon), 0.5, 0.0001, "speed multiplier")

	# Stat stages and paralysis compose: +2 Spe (x2) then halved is back to 100.
	Stats.change_stage(mon, "spe", 2)
	eq(TurnOrder.effective_speed(mon), 100, "+2 Speed, paralysed")


func test_paralysis_sometimes_skips_the_turn() -> void:
	var rng := seeded(20260923)
	var skipped := 0
	var trials := 2000
	for i in trials:
		var mon := fixture("PARAMON", ["normal"], 50,
			{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
		mon["status"] = Status.PARALYSIS
		var r := Status.before_move(mon, rng)
		if not bool(r["can_move"]):
			skipped += 1
			check((r["messages"] as Array).has("PARAMON is paralyzed! It can't move!"),
				"full-paralysis message")
	# 25% of 2000 = 500; a fair binomial sits well inside +/-90.
	check(skipped > 0, "paralysis skipped at least one turn")
	check(skipped < trials, "paralysis did not skip every turn")
	check(absi(skipped - 500) < 90,
		"expected ~500 skipped turns in 2000, got %d" % skipped)

	# An unparalysed Pokemon never skips.
	var healthy := fixture("HEALTHY", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	for i in 200:
		is_true(bool(Status.before_move(healthy, rng)["can_move"]), "healthy mon always moves")


func test_status_residual_damage_burn_poison_toxic() -> void:
	var burned := fixture("BURNED", ["normal"], 50,
		{"hp": 160, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	burned["status"] = Status.BURN
	eq(int(Status.end_of_turn(burned)["damage"]), 10, "burn is 1/16 of 160")
	eq(int(burned["hp"]), 150, "hp after burn tick")

	var poisoned := fixture("POISONED", ["normal"], 50,
		{"hp": 160, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	poisoned["status"] = Status.POISON
	eq(int(Status.end_of_turn(poisoned)["damage"]), 20, "poison is 1/8 of 160")

	var toxiced := fixture("TOXICED", ["normal"], 50,
		{"hp": 160, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	Status.apply(toxiced, Status.TOXIC, seeded(1))
	eq(int(Status.end_of_turn(toxiced)["damage"]), 10, "toxic turn 1 is 1/16")
	eq(int(Status.end_of_turn(toxiced)["damage"]), 20, "toxic turn 2 is 2/16")
	eq(int(Status.end_of_turn(toxiced)["damage"]), 30, "toxic turn 3 is 3/16")


func test_status_type_immunities_and_single_status_rule() -> void:
	var fire := fixture("FIREMON", ["fire"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	is_false(bool(Status.apply(fire, Status.BURN, seeded(1))["ok"]), "Fire cannot be burned")

	var steel := fixture("STEELMON", ["steel"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	is_false(bool(Status.apply(steel, Status.POISON, seeded(1))["ok"]), "Steel cannot be poisoned")
	is_false(bool(Status.apply(steel, Status.TOXIC, seeded(1))["ok"]), "Steel cannot be badly poisoned")

	var electric := fixture("ELECMON", ["electric"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	is_false(bool(Status.apply(electric, Status.PARALYSIS, seeded(1))["ok"]),
		"Electric cannot be paralysed (Gen 6+)")

	var ice := fixture("ICEMON", ["ice"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	is_false(bool(Status.apply(ice, Status.FREEZE, seeded(1))["ok"]), "Ice cannot be frozen")

	var normal := fixture("NORMALMON", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	is_true(bool(Status.apply(normal, Status.BURN, seeded(1))["ok"]), "Normal can be burned")
	is_false(bool(Status.apply(normal, Status.PARALYSIS, seeded(1))["ok"]),
		"a Pokemon can only carry one non-volatile status")
	eq(Status.status_of(normal), "burn", "the first status stays")


func test_sleep_counts_down_and_flinch_lasts_one_turn() -> void:
	var rng := seeded(11)
	var sleeper := fixture("SLEEPER", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	sleeper["status"] = Status.SLEEP
	sleeper["statusCounter"] = 3
	is_false(bool(Status.before_move(sleeper, rng)["can_move"]), "asleep turn 1")
	is_false(bool(Status.before_move(sleeper, rng)["can_move"]), "asleep turn 2")
	var wake := Status.before_move(sleeper, rng)
	is_true(bool(wake["can_move"]), "wakes on the third check")
	eq(Status.status_of(sleeper), "", "no status after waking")

	var flincher := fixture("FLINCHER", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100})
	Status.set_flinch(flincher, true)
	is_false(bool(Status.before_move(flincher, rng)["can_move"]), "flinched")
	is_true(bool(Status.before_move(flincher, rng)["can_move"]), "flinch is gone next turn")


# --------------------------------------------------------------------------
# turn order
# --------------------------------------------------------------------------

func test_priority_move_goes_first_despite_much_lower_speed() -> void:
	var slow := fixture("SLOWPOKE", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 30},
		["quick-attack"])
	var fast := fixture("JOLTEON", ["electric"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 200},
		["tackle"])
	check(not (slow["moves"] as Array).is_empty(), "quick-attack resolved")
	check(not (fast["moves"] as Array).is_empty(), "tackle resolved")
	if (slow["moves"] as Array).is_empty() or (fast["moves"] as Array).is_empty():
		return

	var quick: Dictionary = (slow["moves"] as Array)[0]
	var tackle: Dictionary = (fast["moves"] as Array)[0]
	eq(int(quick["priority"]), 1, "Quick Attack is +1 priority")
	eq(int(tackle["priority"]), 0, "Tackle is 0 priority")
	check(TurnOrder.effective_speed(slow) < TurnOrder.effective_speed(fast),
		"the priority user really is slower")

	var actions: Array = [
		{"side": 0, "mon": slow, "kind": "move", "move": quick},
		{"side": 1, "mon": fast, "kind": "move", "move": tackle},
	]
	var ordered := TurnOrder.order(actions, null)
	eq(Stats.display_name((ordered[0] as Dictionary)["mon"]), "SLOWPOKE",
		"+1 priority acts first")
	# ...and the RNG tie-break cannot overturn priority.
	for s in 20:
		var o := TurnOrder.order(actions, seeded(s))
		eq(Stats.display_name((o[0] as Dictionary)["mon"]), "SLOWPOKE",
			"priority beats the speed tie-break with seed %d" % s)

	# Without the priority move, Speed decides.
	var plain: Array = [
		{"side": 0, "mon": slow, "kind": "move", "move": tackle},
		{"side": 1, "mon": fast, "kind": "move", "move": tackle},
	]
	eq(Stats.display_name((TurnOrder.order(plain, null)[0] as Dictionary)["mon"]), "JOLTEON",
		"equal priority: the faster Pokemon goes first")


func test_switches_and_items_resolve_before_any_move() -> void:
	var slow := fixture("SLOWPOKE", ["normal"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 5})
	var fast := fixture("JOLTEON", ["electric"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 200},
		["quick-attack"])
	var quick: Dictionary = (fast["moves"] as Array)[0]

	var ordered := TurnOrder.order([
		{"side": 1, "mon": fast, "kind": "move", "move": quick},
		{"side": 0, "mon": slow, "kind": "switch", "index": 1},
	], null)
	eq(String((ordered[0] as Dictionary)["kind"]), "switch",
		"a switch outruns a +1 priority move")

	var with_item := TurnOrder.order([
		{"side": 1, "mon": fast, "kind": "switch", "index": 1},
		{"side": 0, "mon": slow, "kind": "item", "item": "potion"},
	], null)
	eq(String((with_item[0] as Dictionary)["kind"]), "item", "items outrun switches")


# --------------------------------------------------------------------------
# exp and THE LEVEL CAP
# --------------------------------------------------------------------------

func test_pokemon_at_the_level_cap_gains_exactly_zero_exp() -> void:
	var at_cap := fixture("PIKACHU", ["electric"], 14,
		{"hp": 40, "atk": 25, "def": 20, "spa": 24, "spd": 24, "spe": 35},
		[], {"exp": 2744})
	var before := int(at_cap["exp"])

	var res := Exp.award(at_cap, 500, {"cap": 14})
	eq(int(res["granted"]), 0, "EXP granted at the cap")
	is_true(bool(res["capped"]), "reported as capped")
	eq(int(at_cap["exp"]), before, "the EXP field did not move")
	eq(int(at_cap["level"]), 14, "the level did not move")
	eq((res["messages"] as Array)[0], "PIKACHU is at the level cap!", "cap message")
	eq(int(res["cap"]), 14, "cap reported back")

	# EventBus.exp_capped fired, with the cap in force.
	eq(spy.capped.size(), 1, "exp_capped emitted once")
	if spy.capped.size() == 1:
		eq(int((spy.capped[0] as Dictionary)["cap"]), 14, "signal carried the cap")

	# Above the cap is capped too (a traded//gift Pokemon over the line).
	var over_cap := fixture("PONYTA", ["fire"], 20,
		{"hp": 60, "atk": 40, "def": 30, "spa": 35, "spd": 35, "spe": 50})
	eq(int(Exp.award(over_cap, 9999, {"cap": 14})["granted"]), 0, "above the cap is also 0")
	eq(spy.capped.size(), 2, "exp_capped emitted again")


func test_pokemon_below_the_level_cap_gains_exp() -> void:
	var below := fixture("STARLY", ["normal", "flying"], 13,
		{"hp": 38, "atk": 24, "def": 20, "spa": 17, "spd": 17, "spe": 26},
		[], {"exp": Exp.exp_for_level("medium-slow", 13), "growthRate": "medium-slow"})
	var before := int(below["exp"])

	# exp_multiplier pinned: these are curve numbers, not segment numbers.
	var res := Exp.award(below, 400, {"cap": 14, "learn_moves": false, "exp_multiplier": 1.0})
	eq(int(res["granted"]), 400, "EXP granted below the cap")
	is_false(bool(res["capped"]), "not reported as capped")
	check(int(res["granted"]) > 0, "strictly greater than zero")
	eq(spy.capped.size(), 0, "exp_capped did NOT fire below the cap")
	# 400 EXP carries it from level 13 (1261) past level 14 (1612), which IS the
	# cap -- so the total is parked exactly on the cap threshold: 1612 - 1261 = 351
	# banked out of the 400 granted. Nothing is hoarded for later.
	eq(int(below["level"]), 14, "levelled up to the cap")
	eq(int(below["exp"]) - before, 351, "banked up to the cap threshold, no further")

	# With the cap out of the way the whole grant is banked.
	var roomy := fixture("STARAVIA", ["normal", "flying"], 13,
		{"hp": 44, "atk": 30, "def": 25, "spa": 20, "spd": 22, "spe": 32},
		[], {"exp": Exp.exp_for_level("medium-slow", 13), "growthRate": "medium-slow"})
	var roomy_before := int(roomy["exp"])
	var res2 := Exp.award(roomy, 400, {"cap": 50, "learn_moves": false, "exp_multiplier": 1.0})
	eq(int(res2["granted"]), 400, "granted below a distant cap")
	eq(int(roomy["exp"]) - roomy_before, 400, "all 400 banked")


func test_levelling_up_stops_dead_at_the_cap() -> void:
	var mon := fixture("BIDOOF", ["normal"], 10,
		{"hp": 40, "atk": 25, "def": 22, "spa": 15, "spd": 18, "spe": 16},
		[], {"exp": Exp.exp_for_level("medium-fast", 10), "growthRate": "medium-fast"})

	# Enough EXP for level 30; the cap is 14, so it must stop at 14 and bank
	# exactly the level-14 threshold.
	var res := Exp.award(mon, Exp.exp_for_level("medium-fast", 30),
		{"cap": 14, "learn_moves": false, "exp_multiplier": 1.0})
	eq(int(mon["level"]), 14, "levelled up to the cap, not past it")
	eq(int(res["levelAfter"]), 14, "reported new level")
	eq(int(mon["exp"]), Exp.exp_for_level("medium-fast", 14),
		"EXP parked exactly on the cap threshold, nothing banked")
	# The very next award is refused, because it is now AT the cap.
	eq(int(Exp.award(mon, 5000, {"cap": 14})["granted"]), 0, "now at the cap: zero")


## Bulbapedia totals for level 50 on each of the six curves.
func test_growth_curves_match_known_totals() -> void:
	eq(Exp.exp_for_level("erratic", 50), 125000, "erratic 50")
	eq(Exp.exp_for_level("fast", 50), 100000, "fast 50")
	eq(Exp.exp_for_level("medium-fast", 50), 125000, "medium-fast 50")
	eq(Exp.exp_for_level("medium-slow", 50), 117360, "medium-slow 50")
	eq(Exp.exp_for_level("slow", 50), 156250, "slow 50")
	eq(Exp.exp_for_level("fluctuating", 50), 142500, "fluctuating 50")

	eq(Exp.exp_for_level("medium-fast", 100), 1000000, "medium-fast 100")
	eq(Exp.exp_for_level("fast", 100), 800000, "fast 100")
	eq(Exp.exp_for_level("slow", 100), 1250000, "slow 100")
	eq(Exp.exp_for_level("medium-fast", 1), 0, "level 1 is always 0")

	eq(Exp.level_for_exp("medium-fast", 124999), 49, "one point short of 50")
	eq(Exp.level_for_exp("medium-fast", 125000), 50, "exactly 50")


## exp = floor( (b * L / 5) * (1/s) * ((2L+10)/(L+Lp+10))^2.5 + 1 )
## b=64, L=20, Lp=20, s=1 -> (64*20/5) * 1 * (50/50)^2.5 + 1 = 257
func test_exp_yield_formula_is_hand_computable() -> void:
	var defeated := fixture("FOE", ["normal"], 20,
		{"hp": 60, "atk": 40, "def": 40, "spa": 40, "spd": 40, "spe": 40},
		[], {"baseExp": 64})
	eq(Exp.gain_from_defeat(defeated, 20, {}), 257, "level 20 beats level 20")
	# The +1 sits INSIDE the floor, so a two-way split is 256/2 + 1 = 129, not 128.
	eq(Exp.gain_from_defeat(defeated, 20, {"participants": 2}), 129, "split two ways")
	eq(Exp.gain_from_defeat(defeated, 20, {"is_trainer": true}), 385, "trainer bonus x1.5")
	# A higher-levelled winner earns less from the same target.
	check(Exp.gain_from_defeat(defeated, 50, {}) < 257, "scales down with winner level")


# --------------------------------------------------------------------------
# AI
# --------------------------------------------------------------------------

func test_ai_never_picks_a_move_the_target_is_immune_to() -> void:
	var me := fixture("RAICHU", ["electric"], 30,
		{"hp": 100, "atk": 70, "def": 60, "spa": 110, "spd": 90, "spe": 120},
		["thunderbolt", "tackle"])
	var ground := fixture("DUGTRIO", ["ground"], 30,
		{"hp": 90, "atk": 100, "def": 60, "spa": 50, "spd": 70, "spe": 120})
	eq((me["moves"] as Array).size(), 2, "both moves resolved")

	var scores := AI.score_moves(me, ground)
	check(float(scores[0]) <= AI.SCORE_IMMUNE, "Thunderbolt scored as immune")
	check(float(scores[1]) > 0.0, "Tackle scored positively")

	var choice := AI.choose_action({"self": me, "foe": ground, "bench": [],
		"difficulty": 5, "can_switch": false})
	eq(String(choice["kind"]), "move", "chose a move")
	eq(int(choice["move_index"]), 1, "chose Tackle, not the immune Thunderbolt")


func test_ai_prefers_the_super_effective_move() -> void:
	var me := fixture("SQUIRTLE", ["water"], 30,
		{"hp": 100, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 60},
		["tackle", "water-gun"])
	var fire := fixture("PONYTA", ["fire"], 30,
		{"hp": 100, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 100})
	var choice := AI.choose_action({"self": me, "foe": fire, "bench": [],
		"difficulty": 5, "can_switch": false})
	eq(int(choice["move_index"]), 1, "Water Gun (x2, STAB) over Tackle (x1)")

	# Against a Water target the same two moves flip: Water Gun is now x0.5.
	var water := fixture("VAPOREON", ["water"], 30,
		{"hp": 100, "atk": 80, "def": 80, "spa": 80, "spd": 80, "spe": 60})
	var choice2 := AI.choose_action({"self": me, "foe": water, "bench": [],
		"difficulty": 5, "can_switch": false})
	eq(int(choice2["move_index"]), 0, "Tackle over a resisted Water Gun")


func test_ai_switches_out_of_a_hopeless_matchup() -> void:
	var stuck := fixture("SNORLAX", ["normal"], 30,
		{"hp": 200, "atk": 110, "def": 65, "spa": 65, "spd": 110, "spe": 30},
		["tackle"])
	var ghost := fixture("GENGAR", ["ghost", "poison"], 30,
		{"hp": 100, "atk": 65, "def": 60, "spa": 130, "spd": 75, "spe": 110},
		["shadow-ball"])
	var answer := fixture("UMBREON", ["dark"], 30,
		{"hp": 150, "atk": 65, "def": 110, "spa": 60, "spd": 130, "spe": 65},
		["bite"])
	check(not (answer["moves"] as Array).is_empty(), "bite resolved from data/moves.json")

	var choice := AI.choose_action({"self": stuck, "foe": ghost, "bench": [answer],
		"difficulty": 5, "can_switch": true})
	eq(String(choice["kind"]), "switch", "switched out of a Normal-vs-Ghost wall")
	eq(int(choice["index"]), 0, "switched to the Dark-type answer")

	# With a good matchup it stays in and attacks.
	var choice2 := AI.choose_action({"self": answer, "foe": ghost, "bench": [stuck],
		"difficulty": 5, "can_switch": true})
	eq(String(choice2["kind"]), "move", "a winning matchup does not switch")

	# A low-difficulty trainer never considers switching at all.
	var dumb := AI.choose_action({"self": stuck, "foe": ghost, "bench": [answer],
		"difficulty": 1, "can_switch": true})
	eq(String(dumb["kind"]), "move", "difficulty below the threshold just attacks")


# --------------------------------------------------------------------------
# the engine end to end
# --------------------------------------------------------------------------

func test_battle_runs_to_a_win_and_pays_exp_through_the_cap() -> void:
	var hero := fixture("MONFERNO", ["fire", "fighting"], 20,
		{"hp": 70, "atk": 60, "def": 45, "spa": 55, "spd": 45, "spe": 55},
		["ember", "tackle"], {"exp": Exp.exp_for_level("medium-slow", 20),
			"growthRate": "medium-slow"})
	var foe := fixture("BUDEW", ["grass", "poison"], 8,
		{"hp": 24, "atk": 15, "def": 16, "spa": 22, "spd": 20, "spe": 17},
		["tackle"], {"baseExp": 56})

	var engine := BattleEngine.new()
	engine.start({"kind": "wild", "party": [hero], "opponent": [foe],
		"cap": 30, "seed": 424242})
	var out := engine.run_to_completion(60)

	eq(String(out["outcome"]), "win", "the level 20 starter beat a level 8 Budew")
	is_true(bool(out["over"]), "battle marked over")
	check(int(foe["hp"]) <= 0, "the foe actually fainted")
	check(int(out["expAwarded"]) > 0, "EXP was paid: %d" % int(out["expAwarded"]))
	check(spy.ended.size() == 1, "battle_ended emitted once")
	check(engine.battle_log.size() > 4, "something was written to the log")

	# Same seed, same battle.
	var hero2 := fixture("MONFERNO", ["fire", "fighting"], 20,
		{"hp": 70, "atk": 60, "def": 45, "spa": 55, "spd": 45, "spe": 55},
		["ember", "tackle"])
	var foe2 := fixture("BUDEW", ["grass", "poison"], 8,
		{"hp": 24, "atk": 15, "def": 16, "spa": 22, "spd": 20, "spe": 17},
		["tackle"], {"baseExp": 56})
	var engine2 := BattleEngine.new()
	engine2.start({"kind": "wild", "party": [hero2], "opponent": [foe2],
		"cap": 30, "seed": 424242})
	var out2 := engine2.run_to_completion(60)
	eq(out2["log"], out["log"], "a seeded battle replays identically")


func test_engine_awards_zero_exp_when_the_winner_is_at_the_cap() -> void:
	var capped_hero := fixture("LUXIO", ["electric"], 14,
		{"hp": 60, "atk": 50, "def": 35, "spa": 40, "spd": 35, "spe": 45},
		["tackle"], {"exp": Exp.exp_for_level("medium-slow", 14), "growthRate": "medium-slow"})
	var foe := fixture("BIDOOF", ["normal"], 5,
		{"hp": 22, "atk": 14, "def": 14, "spa": 10, "spd": 11, "spe": 10},
		["tackle"], {"baseExp": 50})

	var engine := BattleEngine.new()
	engine.start({"kind": "wild", "party": [capped_hero], "opponent": [foe],
		"cap": 14, "seed": 99})
	var out := engine.run_to_completion(60)

	eq(String(out["outcome"]), "win", "won the battle")
	eq(int(out["expAwarded"]), 0, "zero EXP at the cap")
	eq(int(capped_hero["level"]), 14, "still level 14")
	eq(int(capped_hero["exp"]), Exp.exp_for_level("medium-slow", 14), "EXP untouched")
	check(engine.battle_log.has("LUXIO is at the level cap!"),
		"the cap message reached the battle log: %s" % [engine.battle_log])
	eq(spy.capped.size(), 1, "EventBus.exp_capped fired from the engine")


func test_engine_handles_faint_switch_and_loss() -> void:
	var weakling := fixture("MAGIKARP", ["water"], 5,
		{"hp": 12, "atk": 5, "def": 10, "spa": 5, "spd": 10, "spe": 20},
		["tackle"])
	var backup := fixture("FEEBAS", ["water"], 5,
		{"hp": 12, "atk": 6, "def": 10, "spa": 6, "spd": 10, "spe": 15},
		["tackle"])
	var boss := fixture("GARCHOMP", ["dragon", "ground"], 60,
		{"hp": 250, "atk": 220, "def": 160, "spa": 120, "spd": 140, "spe": 190},
		["tackle"], {"baseExp": 270})

	var engine := BattleEngine.new()
	engine.start({"kind": "trainer", "party": [weakling, backup], "opponent": [boss],
		"cap": 62, "seed": 5, "trainer": {"name": "Cynthia", "ai": 8, "prizeMoney": 12000}})
	var out := engine.run_to_completion(80)

	eq(String(out["outcome"]), "loss", "both Pokemon went down")
	check(int(weakling["hp"]) <= 0 and int(backup["hp"]) <= 0, "whole party fainted")
	check(engine.battle_log.has("MAGIKARP fainted!"), "first faint logged")
	check(engine.battle_log.has("FEEBAS fainted!"), "second faint logged")
	check(engine.battle_log.has("You whited out!"), "white-out message")


func test_engine_rejects_illegal_actions() -> void:
	var a := fixture("A", ["normal"], 10,
		{"hp": 50, "atk": 30, "def": 30, "spa": 30, "spd": 30, "spe": 30}, ["tackle"])
	var b := fixture("B", ["normal"], 10,
		{"hp": 50, "atk": 30, "def": 30, "spa": 30, "spd": 30, "spe": 30}, ["tackle"])
	var engine := BattleEngine.new()
	engine.start({"kind": "wild", "party": [a], "opponent": [b], "cap": 20, "seed": 1})

	is_false(engine.submit_action(0, {"kind": "move", "move_index": 3}), "no such move")
	is_false(engine.submit_action(0, {"kind": "switch", "index": 0}), "cannot switch to itself")
	is_false(engine.submit_action(0, {"kind": "switch", "index": 9}), "no such party slot")
	is_false(engine.submit_action(0, {"kind": "dance"}), "unknown action kind")
	is_true(engine.submit_action(0, {"kind": "move", "move_index": 0}), "a legal move is accepted")

	# Mega Evolution is gated off until the key stone exists (DATA_CONTRACT 11.2).
	is_false(engine.can_mega_evolve(a), "no Key Stone, no Mega")


func test_running_from_a_trainer_is_refused() -> void:
	var a := fixture("A", ["normal"], 10,
		{"hp": 50, "atk": 30, "def": 30, "spa": 30, "spd": 30, "spe": 90}, ["tackle"])
	var b := fixture("B", ["normal"], 10,
		{"hp": 50, "atk": 30, "def": 30, "spa": 30, "spd": 30, "spe": 10}, ["tackle"])

	var trainer_battle := BattleEngine.new()
	trainer_battle.start({"kind": "trainer", "party": [a], "opponent": [b],
		"cap": 20, "seed": 2, "trainer": {"name": "Rival", "ai": 5}})
	trainer_battle.submit_action(0, {"kind": "run"})
	trainer_battle.resolve_turn()
	is_false(trainer_battle.over, "cannot flee a trainer battle")
	check(trainer_battle.battle_log.has("No! There's no running from a Trainer battle!"),
		"refusal message")

	var wild := BattleEngine.new()
	var a2 := fixture("A", ["normal"], 10,
		{"hp": 50, "atk": 30, "def": 30, "spa": 30, "spd": 30, "spe": 90}, ["tackle"])
	var b2 := fixture("B", ["normal"], 10,
		{"hp": 50, "atk": 30, "def": 30, "spa": 30, "spd": 30, "spe": 10}, ["tackle"])
	wild.start({"kind": "wild", "party": [a2], "opponent": [b2], "cap": 20, "seed": 3})
	wild.submit_action(0, {"kind": "run"})
	wild.resolve_turn()
	is_true(wild.over, "a faster Pokemon always escapes a wild battle")
	eq(wild.outcome, "run", "outcome recorded")
