extends "res://tests/framework/test_case.gd"
## Type effectiveness. The numbers below are the Gen 6+ chart, which is what the
## game uses (18 types, Fairy present, Steel no longer resists Ghost or Dark).

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	DataRegistry.boot(DataRegistry.FIXTURE_DIR)


func after_each() -> void:
	Log.level = _saved_level


func test_the_two_canonical_cases() -> void:
	almost(DataRegistry.get_type_effectiveness("electric", "water"), 2.0, 0.0001, "electric->water")
	almost(DataRegistry.get_type_effectiveness("electric", "ground"), 0.0, 0.0001, "electric->ground")


func test_super_effective() -> void:
	almost(DataRegistry.get_type_effectiveness("water", "fire"), 2.0, 0.0001, "water->fire")
	almost(DataRegistry.get_type_effectiveness("fighting", "normal"), 2.0, 0.0001, "fighting->normal")
	almost(DataRegistry.get_type_effectiveness("ground", "steel"), 2.0, 0.0001, "ground->steel")
	almost(DataRegistry.get_type_effectiveness("fairy", "dragon"), 2.0, 0.0001, "fairy->dragon")


func test_resisted() -> void:
	almost(DataRegistry.get_type_effectiveness("electric", "electric"), 0.5, 0.0001, "electric->electric")
	almost(DataRegistry.get_type_effectiveness("fire", "water"), 0.5, 0.0001, "fire->water")
	almost(DataRegistry.get_type_effectiveness("normal", "rock"), 0.5, 0.0001, "normal->rock")


func test_immunities() -> void:
	almost(DataRegistry.get_type_effectiveness("normal", "ghost"), 0.0, 0.0001, "normal->ghost")
	almost(DataRegistry.get_type_effectiveness("ghost", "normal"), 0.0, 0.0001, "ghost->normal")
	almost(DataRegistry.get_type_effectiveness("fighting", "ghost"), 0.0, 0.0001, "fighting->ghost")
	almost(DataRegistry.get_type_effectiveness("poison", "steel"), 0.0, 0.0001, "poison->steel")
	almost(DataRegistry.get_type_effectiveness("dragon", "fairy"), 0.0, 0.0001, "dragon->fairy")
	almost(DataRegistry.get_type_effectiveness("psychic", "dark"), 0.0, 0.0001, "psychic->dark")


func test_gen6_steel_no_longer_resists_ghost_or_dark() -> void:
	almost(DataRegistry.get_type_effectiveness("ghost", "steel"), 1.0, 0.0001, "ghost->steel")
	almost(DataRegistry.get_type_effectiveness("dark", "steel"), 1.0, 0.0001, "dark->steel")


func test_case_insensitive() -> void:
	almost(DataRegistry.get_type_effectiveness("ELECTRIC", "Water"), 2.0, 0.0001, "mixed case")


func test_unknown_types_are_neutral_not_fatal() -> void:
	almost(DataRegistry.get_type_effectiveness("banana", "water"), 1.0, 0.0001, "unknown attacker")
	almost(DataRegistry.get_type_effectiveness("electric", "banana"), 1.0, 0.0001, "unknown defender")


func test_dual_type_multiplier_is_the_product() -> void:
	# Gyarados: water/flying. Electric hits both for 2x.
	almost(DataRegistry.get_type_multiplier("electric", PackedStringArray(["water", "flying"])),
		4.0, 0.0001, "electric vs water/flying")
	# Gible: dragon/ground. Electric is neutral on dragon, 0x on ground.
	almost(DataRegistry.get_type_multiplier("electric", PackedStringArray(["dragon", "ground"])),
		0.0, 0.0001, "electric vs dragon/ground")
	# Ice vs dragon/ground: 2 * 2
	almost(DataRegistry.get_type_multiplier("ice", PackedStringArray(["dragon", "ground"])),
		4.0, 0.0001, "ice vs dragon/ground")
	# Fire vs water/rock: 0.5 * 0.5
	almost(DataRegistry.get_type_multiplier("fire", PackedStringArray(["water", "rock"])),
		0.25, 0.0001, "fire vs water/rock")
	almost(DataRegistry.get_type_multiplier("water", PackedStringArray(["fire"])),
		2.0, 0.0001, "single type")


func test_the_chart_is_square_and_complete() -> void:
	var types := DataRegistry.type_names()
	eq(types.size(), 18, "18 types")
	is_true(types.has("fairy"), "fairy present")
	# all 324 pairs must resolve, and to one of the only four legal multipliers
	var allowed := [0.0, 0.5, 1.0, 2.0]
	var bad: Array[String] = []
	for a in types:
		for d in types:
			var v := DataRegistry.get_type_effectiveness(a, d)
			if not allowed.has(v):
				bad.append("%s->%s=%f" % [a, d, v])
	eq(bad.size(), 0, "unexpected multipliers: %s" % ", ".join(PackedStringArray(bad)))
