extends "res://tests/framework/test_case.gd"
## Mega Evolution tests -- DATA_CONTRACT 11. Run:
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=mega
##
## Two layers, deliberately:
##
##   * `mega.gd` in isolation, with the form table INJECTED (`Mega.set_forms`) so
##     the arithmetic does not wait on `data/megas.json`, which the data stream
##     generates. Every stat number below is hand-computed in the comment above
##     the assertion from the formula in `stats.gd`, so if a number moves the
##     comment says whether the new one is right.
##   * the real `battle_engine.gd` turn loop, which is the only place the
##     "start of turn, before any move, Mega's Speed orders that turn" rule can
##     actually be observed.
##
## THE STAT FORMULA, once, so the comments can be short. Level 50, IV 31, EV 0,
## neutral nature:
##   non-HP: floor((2B + 31) * 50 / 100) + 5  ==  floor((2B + 31) / 2) + 5
##   HP:     floor((2B + 31) / 2) + 50 + 10
## So B=45 -> HP 120, B=95 -> HP 170, B=50 -> 70, B=100 -> 120, B=150 -> 170.
##
## EXCLUDED GIMMICKS: there is no Dynamax, Gigantamax, Z-Move, Terastal or Primal
## Reversion test here because there is nothing to test -- they do not exist. What
## is tested is that mega.gd REFUSES them if a data build ever emits one
## (DATA_CONTRACT 11.4/11.5).

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")
const Exp := preload("res://src/battle/exp.gd")
const TurnOrder := preload("res://src/battle/turn_order.gd")
const Mega := preload("res://src/battle/mega.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")

const REAL_DATA := "res://data/megas.json"


## Records the EventBus emissions mega.gd makes, without needing the autoload.
class SignalSpy extends RefCounted:
	var evolved: Array = []
	var reverted: Array = []
	var capped: Array = []

	func _init() -> void:
		add_user_signal("mega_evolved")
		add_user_signal("mega_reverted")
		add_user_signal("exp_capped")
		add_user_signal("battle_started")
		add_user_signal("battle_ended")
		connect("mega_evolved", _on_evolved)
		connect("mega_reverted", _on_reverted)
		connect("exp_capped", _on_capped)

	func _on_evolved(pokemon: Dictionary, form_id: String) -> void:
		evolved.append({"pokemon": pokemon, "formId": form_id})

	func _on_reverted(pokemon: Dictionary, form_id: String) -> void:
		reverted.append({"pokemon": pokemon, "formId": form_id})

	func _on_capped(pokemon: Dictionary, cap: int) -> void:
		capped.append({"pokemon": pokemon, "cap": cap})


## A DataRegistry that has grown `mega_forms_for()`. DataRegistry does not have it
## today, so this is the only way to exercise the branch in `Mega.forms_for()` that
## prefers the autoload over reading the file itself -- the seam the data stream
## will land on.
class RegistryWithMegas extends RefCounted:
	var calls: Array = []
	var table: Dictionary = {}          # base dex id -> Array[Dictionary]

	func mega_forms_for(species_id: int) -> Array:
		calls.append(species_id)
		return table.get(species_id, [])

	# Mega.forms_for() is the only thing this fake is for, but Stats.build() also
	# reaches for the registry, so forward the two accessors it uses.
	func get_species(_id: int) -> Dictionary:
		return {}

	func get_move_by_name(_slug: String) -> Dictionary:
		return {}


## Stands in for GameState so the Key Stone can be switched off mid-test without
## touching the real autoload's bag.
class FakeState extends RefCounted:
	var key_stone := true

	func has_key_stone() -> bool:
		return key_stone


var spy: SignalSpy
var state: FakeState


func before_each() -> void:
	Deps.clear_overrides()
	Mega.clear_forms()
	spy = SignalSpy.new()
	state = FakeState.new()
	Deps.set_override("EventBus", spy)
	Deps.set_override("GameState", state)
	# ISOLATION, and it is load-bearing: tests/test_data_registry.gd reboots the
	# real DataRegistry autoload against tests/fixtures in its before_each and
	# never boots it back, so every test file after it alphabetically -- this one
	# included -- otherwise sees a two-species, ten-move registry. Symptom when
	# that happens: `Stats.make_move("harden")` returns {} and mons quietly come
	# out with fewer moves than they were built with. Injecting a reader over the
	# committed data/*.json makes these tests describe the shipped data no matter
	# what ran first, which is what they are about.
	Deps.set_override("DataRegistry", Deps.JsonRegistry.new())


func after_each() -> void:
	Deps.clear_overrides()
	Mega.clear_forms()


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

## Charizard's real base line, so the Mega Charizard X numbers below are the ones
## the shipped game will produce.
const CHARIZARD: Dictionary = {"hp": 78, "atk": 84, "def": 78, "spa": 109, "spd": 85, "spe": 100}

const FORM_CHARIZARD_X: Dictionary = {
	"id": "charizard-mega-x", "base": 6, "name": "Mega Charizard X",
	"stone": "charizardite-x", "types": ["fire", "dragon"],
	"stats": {"hp": 78, "atk": 130, "def": 111, "spa": 130, "spd": 85, "spe": 100},
	"abilities": ["tough-claws"], "introducedIn": "xy",
}
const FORM_CHARIZARD_Y: Dictionary = {
	"id": "charizard-mega-y", "base": 6, "name": "Mega Charizard Y",
	"stone": "charizardite-y", "types": ["fire", "flying"],
	"stats": {"hp": 78, "atk": 104, "def": 78, "spa": 159, "spd": 115, "spe": 100},
	"abilities": ["drought"], "introducedIn": "xy",
}
const FORM_GENGAR: Dictionary = {
	"id": "gengar-mega", "base": 94, "name": "Mega Gengar",
	"stone": "gengarite", "types": ["ghost", "poison"],
	"stats": {"hp": 60, "atk": 65, "def": 80, "spa": 170, "spd": 95, "spe": 130},
	"abilities": ["shadow-tag"], "introducedIn": "xy",
}
## The one Mega with no stone: it goes off the MOVESET instead (DATA_CONTRACT 11.5).
const FORM_RAYQUAZA: Dictionary = {
	"id": "rayquaza-mega", "base": 384, "name": "Mega Rayquaza",
	"stone": null, "requiresMove": "dragon-ascent", "types": ["dragon", "flying"],
	"stats": {"hp": 105, "atk": 180, "def": 100, "spa": 180, "spd": 100, "spe": 115},
	"abilities": ["delta-stream"], "introducedIn": "oras",
}
## A Z-A Mega Pokemon Champions does not cover: `abilities: []`, pending the owner.
const FORM_HEATRAN: Dictionary = {
	"id": "heatran-mega", "base": 485, "name": "Mega Heatran",
	"stone": "heatranite", "types": ["fire", "steel"],
	"stats": {"hp": 91, "atk": 120, "def": 106, "spa": 175, "spd": 141, "spe": 67},
	"abilities": [], "abilityStatus": "pending-owner", "introducedIn": "za",
}

## Something whose only job is to faint on turn one.
const FRAIL: Dictionary = {"hp": 30, "atk": 30, "def": 30, "spa": 30, "spd": 30, "spe": 30}

## SYNTHETIC, and only for the HP-fraction and Speed-ordering tests. No real Mega
## changes its base HP (a fact this file also asserts), and none of the real Speed
## jumps lands on numbers as readable as 70 -> 170, so these two tests use a made-up
## species rather than dressing a real one up in fake stats.
const SPECIES_SYNTH: Dictionary = {"hp": 45, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50}
const FORM_SYNTH: Dictionary = {
	"id": "synth-mega", "base": 900, "name": "Mega Synth",
	"stone": "synthite", "types": ["steel", "dragon"],
	"stats": {"hp": 95, "atk": 150, "def": 50, "spa": 50, "spd": 50, "spe": 150},
	"abilities": ["levitate"],
}


## A battle-ready Pokemon built through the real `Stats.build`, so its stats come
## out of the real formula and `Mega.evolve`'s recomputation is comparable.
## Unlike test_battle.gd's fixture this does NOT pin `stats` afterwards: pinned
## stats would make the Mega's recomputed line look like a bug.
func mon(species_id: int, mon_name: String, types: Array, base: Dictionary, level: int,
		opts: Dictionary = {}) -> Dictionary:
	var build_opts := opts.duplicate()
	build_opts["species_data"] = {
		"name": mon_name, "types": types, "stats": base,
		"abilities": [String(opts.get("ability", "blaze"))],
		"baseExp": int(opts.get("baseExp", 100)),
		"growthRate": String(opts.get("growthRate", "medium-fast")),
	}
	build_opts["name"] = mon_name
	return Stats.build(species_id, level, build_opts)


func charizard(level: int = 50, item: String = "charizardite-x") -> Dictionary:
	return mon(6, "CHARIZARD", ["fire", "flying"], CHARIZARD, level,
		{"item": item, "ability": "blaze", "moves": ["tackle"]})


func first_index(lines: Array, needle: String) -> int:
	for i in lines.size():
		if String(lines[i]).contains(needle):
			return i
	return -1


func types_of(m: Dictionary) -> Array:
	return Array(m.get("types", PackedStringArray()))


# --------------------------------------------------------------------------
# 1. the gate: Key Stone AND the matching stone (DATA_CONTRACT 11.2)
# --------------------------------------------------------------------------

func test_needs_both_the_key_stone_and_the_matching_mega_stone() -> void:
	Mega.set_forms([FORM_CHARIZARD_X, FORM_CHARIZARD_Y, FORM_GENGAR])

	# Both halves present: yes.
	var ok_mon := charizard(50, "charizardite-x")
	is_true(Mega.can_mega_evolve(ok_mon), "key stone + charizardite-x")
	eq(String(Mega.eligible_form(ok_mon)["id"]), "charizard-mega-x", "form chosen")

	# Key Stone gone, stone still held: no.
	state.key_stone = false
	is_false(Mega.can_mega_evolve(ok_mon), "stone but no Key Stone")
	eq(String(Mega.check(ok_mon)["reason"]), "no-key-stone", "reason")
	state.key_stone = true

	# Key Stone held, no stone: no.
	var bare := charizard(50, "")
	is_false(Mega.can_mega_evolve(bare), "Key Stone but no stone")
	eq(String(Mega.check(bare)["reason"]), "no-form", "reason")

	# Key Stone held, WRONG item: no.
	var wrong := charizard(50, "leftovers")
	is_false(Mega.can_mega_evolve(wrong), "Key Stone but the wrong item")

	# Key Stone held, right item, wrong species: no. (Gengarite on a Charizard.)
	var mismatch := charizard(50, "gengarite")
	is_false(Mega.can_mega_evolve(mismatch), "gengarite on a Charizard")

	# A species with no Mega at all, holding a real stone: no.
	var no_mega := mon(1, "BULBASAUR", ["grass"], CHARIZARD, 50, {"item": "charizardite-x"})
	is_false(Mega.can_mega_evolve(no_mega), "species with no Mega form")

	# Fainted: no. The button must not draw over a corpse.
	var down := charizard(50, "charizardite-x")
	down["hp"] = 0
	is_false(Mega.can_mega_evolve(down), "fainted")
	eq(String(Mega.check(down)["reason"]), "fainted", "reason")

	# No GameState at all -> fails closed rather than handing out a free Mega.
	Deps.set_override("GameState", null)
	is_false(Mega.can_mega_evolve(ok_mon), "no GameState means no Key Stone")


func test_the_stone_decides_which_of_two_megas_you_get() -> void:
	Mega.set_forms([FORM_CHARIZARD_X, FORM_CHARIZARD_Y])
	eq(Mega.forms_for(6).size(), 2, "Charizard has two Megas")

	var x := charizard(50, "charizardite-x")
	var y := charizard(50, "charizardite-y")
	eq(String(Mega.eligible_form(x)["id"]), "charizard-mega-x", "X stone")
	eq(String(Mega.eligible_form(y)["id"]), "charizard-mega-y", "Y stone")

	Mega.evolve(x)
	Mega.evolve(y)
	eq(types_of(x), ["fire", "dragon"], "Mega X is Fire/Dragon")
	eq(types_of(y), ["fire", "flying"], "Mega Y stays Fire/Flying")
	eq(String(x["ability"]), "tough-claws", "Mega X ability")
	eq(String(y["ability"]), "drought", "Mega Y ability")


# --------------------------------------------------------------------------
# 2. types, stats and ability actually change
# --------------------------------------------------------------------------

## HAND COMPUTED, Charizard -> Mega Charizard X at level 50, IV 31, EV 0, hardy:
##   atk  base 84 -> floor((168+31)/2) + 5 = 99 + 5   = 104
##   atk  Mega 130 -> floor((260+31)/2) + 5 = 145 + 5 = 150
##   spa  base 109 -> floor((218+31)/2) + 5 = 124 + 5 = 129
##   spa  Mega 130 -> 150
##   def  base 78 -> floor((156+31)/2) + 5 = 93 + 5   = 98
##   def  Mega 111 -> floor((222+31)/2) + 5 = 126 + 5 = 131
##   HP   base 78 == Mega 78 -> floor(187/2) + 60 = 93 + 60 = 153, unchanged
func test_evolving_swaps_types_stats_and_ability() -> void:
	Mega.set_forms([FORM_CHARIZARD_X])
	var c := charizard(50, "charizardite-x")

	eq(types_of(c), ["fire", "flying"], "base types")
	eq(String(c["ability"]), "blaze", "base ability")
	eq(int((c["stats"] as Dictionary)["atk"]), 104, "base Atk")
	eq(int((c["stats"] as Dictionary)["spa"]), 129, "base Spa")
	eq(int((c["stats"] as Dictionary)["def"]), 98, "base Def")
	eq(int(c["maxHp"]), 153, "base max HP")

	var res := Mega.evolve(c)
	is_true(bool(res["ok"]), "evolve succeeded")
	eq(String(res["formId"]), "charizard-mega-x", "form id")

	is_true(Mega.is_mega(c), "flagged as Mega")
	eq(types_of(c), ["fire", "dragon"], "Mega X types: Flying becomes Dragon")
	eq(String(c["ability"]), "tough-claws", "Mega X ability")
	eq(int((c["stats"] as Dictionary)["atk"]), 150, "Mega Atk (recomputed, not a flat bonus)")
	eq(int((c["stats"] as Dictionary)["spa"]), 150, "Mega Spa")
	eq(int((c["stats"] as Dictionary)["def"]), 131, "Mega Def")
	eq(int(c["maxHp"]), 153, "Mega X does not change base HP")
	eq(String(c["name"]), "Mega Charizard X", "display name")

	# EventBus.mega_evolved(pokemon, form_id) -- DATA_CONTRACT 11.2.
	eq(spy.evolved.size(), 1, "one mega_evolved emission")
	eq(String((spy.evolved[0] as Dictionary)["formId"]), "charizard-mega-x", "signal payload")

	# The IV/EV/nature line still applies: a Mega is a new base-stat row, not a
	# fixed stat block. Same form, EV-trained, must come out higher.
	var trained := mon(6, "CHARIZARD", ["fire", "flying"], CHARIZARD, 50,
		{"item": "charizardite-x", "evs": [0, 252, 0, 0, 0, 0], "nature": "adamant"})
	Mega.evolve(trained)
	# atk: floor((260+31+63)*50/100) + 5 = floor(177) + 5 = 182, * 1.1 -> 200
	eq(int((trained["stats"] as Dictionary)["atk"]), 200, "252 Atk EVs + Adamant still count")


## No Mega changes its base HP -- which is why the HP-fraction rule is invisible in
## normal play, and why the fraction test below needs a synthetic form to bite on.
##
## TWO forms look like exceptions and are not: they Mega Evolve from an alternate
## FORME of the base species, so their HP matches that forme rather than the dex
## default. Both are pinned by name here, so a third one cannot appear quietly --
## if this list grows, someone changed a stat line and should say why.
const HP_EXCEPTIONS: Dictionary = {
	"floette-mega": 74,      # Floette Eternal Flower (74), not default Floette (54)
	"zygarde-mega": 216,     # Zygarde Complete Forme (216), not 50% Forme (108)
}

func test_no_shipped_mega_changes_its_base_hp() -> void:
	if not FileAccess.file_exists(REAL_DATA):
		pending("data/megas.json not generated yet -- base-HP check deferred")
		return
	var f := FileAccess.open(REAL_DATA, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	is_true(parsed is Dictionary, "megas.json parses")
	if not (parsed is Dictionary):
		return
	var reg := Deps.registry()
	var checked := 0
	var exceptions_seen: Array = []
	for entry: Variant in ((parsed as Dictionary).get("forms", []) as Array):
		var form: Dictionary = entry
		var fid := String(form.get("id", "?"))
		var base_sp: Dictionary = reg.get_species(int(form.get("base", 0)))
		if base_sp.is_empty():
			continue
		var base_hp := int((base_sp.get("stats", {}) as Dictionary).get("hp", -1))
		var mega_hp := int((form.get("stats", {}) as Dictionary).get("hp", -2))
		if base_hp < 0:
			continue
		checked += 1
		if HP_EXCEPTIONS.has(fid):
			exceptions_seen.append(fid)
			eq(mega_hp, int(HP_EXCEPTIONS[fid]), "%s alternate-forme HP" % fid)
		else:
			eq(mega_hp, base_hp, "%s base HP is unchanged" % fid)
	is_true(checked > 20, "checked the whole table against species.json (%d forms)" % checked)
	exceptions_seen.sort()
	var expected := HP_EXCEPTIONS.keys()
	expected.sort()
	eq(exceptions_seen, expected, "exactly the two known alternate-forme exceptions")


## Regression guard: `data/megas.json` writes `"requiresForm": null` and
## `"requiresMove": null` on every form that has neither, and `String(null)` is
## not the empty string. Reading those naively made every stoned form look like it
## demanded a specific base forme and refused all 97 of them.
func test_explicit_json_nulls_do_not_gate_a_normal_form() -> void:
	var venusaur := Mega.form_by_id("venusaur-mega")
	if venusaur.is_empty():
		pending("venusaur-mega not in the table yet")
		return
	is_false(Mega.is_stoneless(venusaur), "Mega Venusaur has a stone")
	var v := mon(3, "VENUSAUR", ["grass", "poison"], CHARIZARD, 50,
		{"item": "venusaurite", "ability": "overgrow"})
	# `form` is unset on the mon, and the form's requiresForm is JSON null.
	is_true(Mega.can_mega_evolve(v), "a null requiresForm gates nothing")
	eq(String(Mega.eligible_form(v)["id"]), "venusaur-mega", "form resolved off disk")


# --------------------------------------------------------------------------
# 3. HP fraction is preserved (DATA_CONTRACT 11.2)
# --------------------------------------------------------------------------

## HAND COMPUTED, synthetic species base HP 45 -> Mega base HP 95, level 50:
##   base max HP = floor((90+31)/2) + 60 = 60 + 60  = 120
##   Mega max HP = floor((190+31)/2) + 60 = 110 + 60 = 170
## 50% of 120 is 60; 50% of 170 is 85. The contract says keep the FRACTION, so
## 60/120 must become 85/170 -- not 60/170 (keep the value) and not 110/170
## (keep the damage).
func test_hp_fraction_survives_the_stat_swap() -> void:
	Mega.set_forms([FORM_SYNTH])

	var m := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 50, {"item": "synthite"})
	eq(int(m["maxHp"]), 120, "base max HP")
	m["hp"] = 60
	almost(float(m["hp"]) / float(m["maxHp"]), 0.5, 0.0001, "50% before")

	is_true(bool(Mega.evolve(m)["ok"]), "evolved")
	eq(int(m["maxHp"]), 170, "Mega max HP is higher")
	eq(int(m["hp"]), 85, "50% of 170")
	almost(float(m["hp"]) / float(m["maxHp"]), 0.5, 0.0001, "still 50% after")

	# Full HP stays full HP -- the commonest case, and the one a player would
	# notice instantly if the engine kept the HP value instead.
	var full := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 50, {"item": "synthite"})
	Mega.evolve(full)
	eq(int(full["hp"]), int(full["maxHp"]), "full stays full")
	eq(int(full["hp"]), 170, "on the bigger bar")

	# 20% of 120 is 24; 20% of 170 is 34.
	var hurt := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 50, {"item": "synthite"})
	hurt["hp"] = 24
	Mega.evolve(hurt)
	eq(int(hurt["hp"]), 34, "20% of 170")
	almost(float(hurt["hp"]) / float(hurt["maxHp"]), 0.2, 0.005, "still ~20%")

	# 1 HP is 0.83% of 120, which rounds to 1 of 170 -- and must never round to 0.
	# Mega Evolving is not allowed to be what faints you.
	var sliver := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 50, {"item": "synthite"})
	sliver["hp"] = 1
	Mega.evolve(sliver)
	eq(int(sliver["hp"]), 1, "1 HP survives the swap")
	is_false(Stats.is_fainted(sliver), "not fainted by its own Mega Evolution")


func test_reverting_puts_the_fraction_back_on_the_smaller_bar() -> void:
	Mega.set_forms([FORM_SYNTH])
	var m := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 50, {"item": "synthite"})
	m["hp"] = 60                       # 50% of 120
	Mega.evolve(m)
	eq(int(m["hp"]), 85, "50% of 170")
	m["hp"] = 34                       # knocked down to 20% of the Mega bar
	is_true(Mega.revert(m), "reverted")
	eq(int(m["maxHp"]), 120, "base max HP back")
	eq(int(m["hp"]), 24, "20% of 120")
	almost(float(m["hp"]) / float(m["maxHp"]), 0.2, 0.005, "fraction held")


# --------------------------------------------------------------------------
# 4. everything else is preserved: level, moves, PP, status, stages
# --------------------------------------------------------------------------

func test_level_moves_pp_status_and_stages_all_survive() -> void:
	Mega.set_forms([FORM_CHARIZARD_X])
	var c := mon(6, "CHARIZARD", ["fire", "flying"], CHARIZARD, 37,
		{"item": "charizardite-x", "moves": ["tackle", "harden"]})
	c["nickname"] = "ZARD"            # `build()` has no nickname opt; set it directly
	c["status"] = "burn"
	c["statusCounter"] = 3
	Stats.change_stage(c, "spe", 2)
	Stats.change_stage(c, "def", -1)
	((c["moves"] as Array)[0] as Dictionary)["pp"] = 4
	var exp_before := int(c["exp"])
	var growth_before := String(c["growthRate"])
	var nickname_before := String(c["nickname"])

	is_true(bool(Mega.evolve(c)["ok"]), "evolved")

	eq(int(c["level"]), 37, "level unchanged")
	eq(int(c["exp"]), exp_before, "exp unchanged")
	eq(int(c["species"]), 6, "species is still the BASE dex id")
	eq(String(c["growthRate"]), growth_before, "growth rate unchanged")
	eq((c["moves"] as Array).size(), 2, "still two moves")
	eq(String(((c["moves"] as Array)[0] as Dictionary)["name"]), "Tackle", "same move")
	eq(int(((c["moves"] as Array)[0] as Dictionary)["pp"]), 4, "spent PP stays spent")
	eq(String(c["status"]), "burn", "status kept")
	eq(int(c["statusCounter"]), 3, "status counter kept")
	eq(Stats.get_stage(c, "spe"), 2, "+2 Speed stage kept")
	eq(Stats.get_stage(c, "def"), -1, "-1 Defense stage kept")
	eq(String(c["item"]), "charizardite-x", "still holding the stone")
	# A nickname outranks the form name, so a nicknamed Mega stays nicknamed.
	eq(Stats.display_name(c), nickname_before, "nickname wins over the form name")

	is_true(Mega.revert(c), "reverted")
	eq(int(c["level"]), 37, "level still unchanged after reverting")
	eq(String(c["status"]), "burn", "status still there")
	eq(Stats.get_stage(c, "spe"), 2, "stages still there")
	eq(int(((c["moves"] as Array)[0] as Dictionary)["pp"]), 4, "PP still there")


## DATA_CONTRACT 11.3: "Mega Evolution does not change a Pokemon's level and
## therefore never affects EXP capping." Asserted against the real cap gate in
## exp.gd, not just by reading `level` back.
func test_mega_evolution_does_not_affect_exp_capping() -> void:
	Mega.set_forms([FORM_CHARIZARD_X])

	# At the cap: zero EXP, capped, whether or not it is Mega Evolved.
	var at_cap := charizard(26, "charizardite-x")
	var before := Exp.award(at_cap, 5000, {"cap": 26})
	eq(int(before["granted"]), 0, "at cap, base form: no EXP")
	is_true(bool(before["capped"]), "capped")
	eq(int(at_cap["level"]), 26, "level parked at the cap")

	is_true(bool(Mega.evolve(at_cap)["ok"]), "Mega Evolved at the cap")
	eq(int(at_cap["level"]), 26, "Mega Evolution did not change the level")
	var after := Exp.award(at_cap, 5000, {"cap": 26})
	eq(int(after["granted"]), 0, "at cap, Mega form: still no EXP")
	is_true(bool(after["capped"]), "still capped")
	eq(int(at_cap["level"]), 26, "still level 26")
	eq(spy.capped.size(), 2, "exp_capped fired both times, identically")

	# Below the cap: EXP flows normally and the level still clamps to the cap.
	var below := charizard(20, "charizardite-x")
	is_true(bool(Mega.evolve(below)["ok"]), "Mega Evolved below the cap")
	var gain := Exp.award(below, 500000, {"cap": 26})
	is_true(int(gain["granted"]) > 0, "below the cap, EXP is granted while Mega")
	eq(int(below["level"]), 26, "and the level clamps to the cap, not past it")
	is_true(Mega.is_mega(below), "still Mega after levelling")


# --------------------------------------------------------------------------
# 5. Mega Rayquaza: the one Mega with no stone (DATA_CONTRACT 11.5, ruling B)
# --------------------------------------------------------------------------

func test_mega_rayquaza_needs_dragon_ascent_and_no_stone_at_all() -> void:
	Mega.set_forms([FORM_RAYQUAZA])
	is_true(Mega.is_stoneless(FORM_RAYQUAZA), "stone is null + requiresMove is set")

	var base: Dictionary = {"hp": 105, "atk": 150, "def": 90, "spa": 150, "spd": 90, "spe": 95}

	# Knows Dragon Ascent, holds NOTHING: yes. This is the only Mega for which an
	# empty item slot is not a refusal.
	var ascendant := mon(384, "RAYQUAZA", ["dragon", "flying"], base, 70,
		{"item": "", "moves": ["dragon-ascent", "tackle"], "ability": "air-lock"})
	is_true(Mega.can_mega_evolve(ascendant), "Dragon Ascent, no held item")
	eq(String(Mega.eligible_form(ascendant)["id"]), "rayquaza-mega", "form")

	# Same Rayquaza without the move: no.
	var grounded := mon(384, "RAYQUAZA", ["dragon", "flying"], base, 70,
		{"item": "", "moves": ["tackle"], "ability": "air-lock"})
	is_false(Mega.can_mega_evolve(grounded), "no Dragon Ascent, no Mega")
	eq(String(Mega.check(grounded)["reason"]), "no-form", "reason")

	# It still needs the Key Stone.
	state.key_stone = false
	is_false(Mega.can_mega_evolve(ascendant), "no Key Stone, no Mega Rayquaza")
	state.key_stone = true

	# And it still obeys one-per-side.
	is_false(Mega.can_mega_evolve(ascendant, {"mega_used": true}), "one Mega per side")

	is_true(bool(Mega.evolve(ascendant)["ok"]), "evolved")
	eq(String(ascendant["ability"]), "delta-stream", "Delta Stream")
	eq(String(ascendant["item"]), "", "still holding nothing")
	# atk: Mega 180 -> floor((360+31)*70/100) + 5 = floor(273.7) + 5 = 273 + 5 = 278
	eq(int((ascendant["stats"] as Dictionary)["atk"]), 278, "Mega Rayquaza Atk at level 70")


# --------------------------------------------------------------------------
# 6. abilities are an ARRAY, and nine Z-A forms have none yet (ruling C/D)
# --------------------------------------------------------------------------

func test_abilities_is_an_array_and_a_pending_form_keeps_its_base_ability() -> void:
	Mega.set_forms([FORM_HEATRAN])
	is_true(Mega.ability_pending(FORM_HEATRAN), "Mega Heatran's ability is unresolved")
	eq(Array(Mega.abilities_of(FORM_HEATRAN)), [], "empty array, not a guess")

	var h := mon(485, "HEATRAN", ["fire", "steel"], CHARIZARD, 60,
		{"item": "heatranite", "ability": "flash-fire"})
	is_true(bool(Mega.evolve(h)["ok"]), "evolves anyway -- the form is real, the ability is not")
	# DATA_CONTRACT 11.5: no invented ability. It keeps the base one and says so,
	# rather than shipping an empty ability slot that silently does nothing.
	eq(String(h["ability"]), "flash-fire", "base ability kept")
	eq(String(h["megaAbilityStatus"]), "pending-owner", "flagged for the owner")
	eq(types_of(h), ["fire", "steel"], "the rest of the form still applies")

	# A form with TWO abilities: slot 0 goes live, the array is parked for later.
	var two := FORM_HEATRAN.duplicate(true)
	two["abilities"] = ["flash-fire", "flame-body"]
	two.erase("abilityStatus")
	Mega.set_forms([two])
	eq(Array(Mega.abilities_of(two)), ["flash-fire", "flame-body"], "both read back")
	var h2 := mon(485, "HEATRAN", ["fire", "steel"], CHARIZARD, 60,
		{"item": "heatranite", "ability": "flash-fire"})
	Mega.evolve(h2)
	eq(String(h2["ability"]), "flash-fire", "slot 0 is the live ability")
	eq(Array(h2["megaAbilities"]), ["flash-fire", "flame-body"], "the array survives for later")
	neq(String(h2.get("megaAbilityStatus", "")), "pending-owner", "not pending")


# --------------------------------------------------------------------------
# 7. excluded gimmicks are refused, not imported (DATA_CONTRACT 11.4 / 11.5)
# --------------------------------------------------------------------------

func test_primal_reversion_and_the_other_gimmicks_are_refused_at_load() -> void:
	var accepted := Mega.set_forms([
		FORM_CHARIZARD_X,
		{"id": "groudon-primal", "base": 383, "name": "Primal Groudon",
		 "stone": "red-orb", "types": ["ground", "fire"],
		 "stats": {"hp": 100, "atk": 180, "def": 160, "spa": 150, "spd": 90, "spe": 90},
		 "abilities": ["desolate-land"]},
		{"id": "kyogre-primal", "base": 382, "name": "Primal Kyogre",
		 "stone": "blue-orb", "types": ["water"],
		 "stats": {"hp": 100, "atk": 150, "def": 90, "spa": 180, "spd": 160, "spe": 90},
		 "abilities": ["primordial-sea"]},
		{"id": "charizard-gmax", "base": 6, "name": "Gigantamax Charizard",
		 "stone": null, "types": ["fire", "flying"], "abilities": []},
		{"id": "flutter-tera", "base": 987, "name": "Terastal Flutter Mane",
		 "stone": "tera-shard", "types": ["ghost", "fairy"], "abilities": []},
	])
	eq(accepted, 1, "only the actual Mega was accepted")
	eq(Mega.rejected_ids().size(), 4, "four gimmick entries refused")
	eq(Mega.forms_for(383).size(), 0, "no Primal Groudon")
	eq(Mega.forms_for(382).size(), 0, "no Primal Kyogre")
	eq(Mega.forms_for(6).size(), 1, "Charizard keeps its Mega, loses the Gigantamax")

	# And a Pokemon holding a Red Orb gets nothing, because the form does not exist.
	var groudon := mon(383, "GROUDON", ["ground"], CHARIZARD, 70, {"item": "red-orb"})
	is_false(Mega.can_mega_evolve(groudon), "Red Orb does nothing")

	# Belt and braces: evolve() refuses an excluded form even if handed one directly.
	var res := Mega.evolve(groudon, {"id": "groudon-primal", "base": 383,
		"name": "Primal Groudon", "stone": "red-orb", "abilities": ["desolate-land"]})
	is_false(bool(res["ok"]), "evolve() refuses it directly too")
	eq(String(res["reason"]), "excluded-gimmick", "reason")


# --------------------------------------------------------------------------
# 8. the real table, once the data stream has written it
# --------------------------------------------------------------------------

func test_the_form_table_loads_off_disk() -> void:
	# No injection: this is the production path (data/megas.json, then the
	# tests/fixtures copy while the data stream is still building it).
	is_true(Mega.table_loaded(), "a form table was found")
	eq(Mega.rejected_ids().size(), 0, "nothing in the shipped table is an excluded gimmick")
	eq(Mega.forms_for(6).size(), 2, "Charizard has exactly two Megas on disk")

	var ray := Mega.form_by_id("rayquaza-mega")
	is_false(ray.is_empty(), "Mega Rayquaza is in the table")
	if not ray.is_empty():
		is_true(Mega.is_stoneless(ray), "Mega Rayquaza has no stone")
		eq(String(ray.get("requiresMove", "")), "dragon-ascent", "and needs Dragon Ascent")

	is_true(Mega.form_by_id("groudon-primal").is_empty(), "no Primal Groudon")
	is_true(Mega.form_by_id("kyogre-primal").is_empty(), "no Primal Kyogre")

	if not FileAccess.file_exists(REAL_DATA):
		pending("data/megas.json not generated yet -- ran against tests/fixtures/megas.json")
		return

	var f := FileAccess.open(REAL_DATA, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	is_true(parsed is Dictionary, "megas.json is an object")
	if not (parsed is Dictionary):
		return
	var top: Dictionary = parsed
	eq(String(top.get("keyItem", "")), "key-stone", "keyItem")
	eq(String(top.get("rule", "")), "one-per-battle", "rule")
	eq(bool(top.get("revertsAfterBattle", false)), true, "revertsAfterBattle")

	var stoneless := 0
	var pending_abilities := 0
	for entry: Variant in (top.get("forms", []) as Array):
		var form: Dictionary = entry
		var fid := String(form.get("id", ""))
		# Ruling C: abilities is an ARRAY on every single form.
		is_true(form.get("abilities", null) is Array, "%s abilities is an array" % fid)
		if Mega.is_stoneless(form):
			stoneless += 1
			eq(fid, "rayquaza-mega", "the only stoneless Mega is Rayquaza")
		if Mega.ability_pending(form):
			pending_abilities += 1
			# DATA_CONTRACT 11.5: visibly unresolved, never silently wrong.
			eq(String(form.get("abilityStatus", "")), "pending-owner",
				"%s carries abilityStatus" % fid)
	eq(stoneless, 1, "exactly one stoneless Mega")
	is_true(pending_abilities <= 9, "at most the nine Champions-less Z-A forms are pending")


## The real GameState gate, not the FakeState one: `has_key_stone()`,
## `grant_key_stone()` and the `mega_unlocked_at` story checkpoint are code this
## stream added, and nothing else covers them.
##
## This is the one test here that touches a live autoload, so it saves and
## restores exactly what it changes. (The alternative -- leaving the autoload
## dirty -- is what tests/test_data_registry.gd does, and it is why before_each
## above has to inject a registry.)
func test_the_real_game_state_key_stone_gate() -> void:
	var gs := Deps.node("GameState")
	Deps.set_override("GameState", null)          # talk to the autoload, not the fake
	gs = Deps.node("GameState")
	if gs == null or not gs.has_method("grant_key_stone"):
		pending("GameState autoload not available in this run")
		return

	var saved_bag: Dictionary = (gs.get("bag") as Dictionary).duplicate(true)
	var saved_badges := int(gs.get("badges"))
	var saved_at := String(gs.get("mega_unlocked_at"))

	(gs.get("bag") as Dictionary).erase("key-stone")
	is_false(bool(gs.has_key_stone()), "no Key Stone at the start of the game")

	# The story gate: docs/research/mega-design.md 1 puts it after the Relic Badge.
	eq(saved_at, "badge:relic", "Key Stone is gated on the Relic Badge")
	gs.set("badges", 0)
	is_false(bool(gs.mega_unlocked()), "not unlocked with no badges")
	gs.set("badges", 1 << 2)                       # BADGE_ORDER[2] == "relic"
	is_true(bool(gs.mega_unlocked()), "unlocked once the Relic Badge is held")

	is_true(bool(gs.grant_key_stone()), "granted")
	is_true(bool(gs.has_key_stone()), "and now held")
	is_false(bool(gs.grant_key_stone()), "granting twice is refused")

	# End to end through mega.gd with the real autoload and the real form table.
	Mega.clear_forms()
	var c := charizard(50, "charizardite-x")
	is_true(Mega.can_mega_evolve(c), "real GameState + real megas.json: can Mega")
	(gs.get("bag") as Dictionary).erase("key-stone")
	is_false(Mega.can_mega_evolve(c), "and cannot once the Key Stone is gone")

	gs.set("bag", saved_bag)
	gs.set("badges", saved_badges)
	gs.set("mega_unlocked_at", saved_at)


## The form table comes from `DataRegistry.mega_forms_for()` when that autoload
## offers it, and from `data/megas.json` directly when it does not -- so this stream
## works today and does not have to change when the data stream adds the accessor.
func test_a_registry_that_offers_mega_forms_for_is_preferred_over_the_file() -> void:
	var reg := RegistryWithMegas.new()
	reg.table[6] = [FORM_CHARIZARD_Y]        # deliberately NOT what the file says
	Deps.set_override("DataRegistry", reg)

	# No injection, so forms_for() is free to consult the registry.
	var forms := Mega.forms_for(6)
	eq(forms.size(), 1, "the registry's answer, not the file's two")
	eq(String((forms[0] as Dictionary)["id"]), "charizard-mega-y", "and it is the registry's form")
	is_true(reg.calls.has(6), "the registry was actually asked")

	# It is still filtered: an autoload cannot smuggle an excluded gimmick in either.
	reg.table[383] = [{"id": "groudon-primal", "base": 383, "name": "Primal Groudon",
		"stone": "red-orb", "abilities": ["desolate-land"]}]
	eq(Mega.forms_for(383).size(), 0, "the registry's Primal Groudon is dropped too")

	# An INJECTED table beats the registry, which is what keeps the rest of this
	# file hermetic.
	Mega.set_forms([FORM_CHARIZARD_X])
	var injected := Mega.forms_for(6)
	eq(injected.size(), 1, "one injected form")
	eq(String((injected[0] as Dictionary)["id"]), "charizard-mega-x", "injection wins")


# --------------------------------------------------------------------------
# 9. the engine: one Mega per side, per battle
# --------------------------------------------------------------------------

## Both sides use a harmless status move, so nothing faints and the battle runs as
## long as the test needs it to.
func engine_with(player_party: Array, opp_party: Array, trainer: Dictionary = {}) -> Object:
	var b := BattleEngine.new()
	var t := {"name": "BOSS", "ai": 5}
	for k: Variant in trainer:
		t[String(k)] = trainer[k]
	b.start({"kind": "trainer", "party": player_party, "opponent": opp_party,
		"trainer": t, "cap": 100, "seed": 20260923})
	return b


func test_one_mega_per_side_per_battle() -> void:
	Mega.set_forms([FORM_CHARIZARD_X, FORM_GENGAR])

	var a := mon(6, "ZARD-A", ["fire", "flying"], CHARIZARD, 50,
		{"item": "charizardite-x", "moves": ["harden"]})
	var b := mon(6, "ZARD-B", ["fire", "flying"], CHARIZARD, 50,
		{"item": "charizardite-x", "moves": ["harden"]})
	var foe := mon(94, "GENGAR", ["ghost", "poison"], CHARIZARD, 50,
		{"item": "", "moves": ["growl"]})
	var eng := engine_with([a, b], [foe], {"keyStone": false})

	is_true(eng.can_mega_evolve(a, 0), "A can Mega before the battle starts moving")
	is_true(eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true}), "action taken")
	eng.submit_action(1, {"kind": "move", "move_index": 0})
	var turn1: Dictionary = eng.resolve_turn()

	is_true(Mega.is_mega(a), "A Mega Evolved")
	is_true(first_index(turn1["log"], "Mega Evolved into Mega Charizard X") >= 0,
		"the log says so: %s" % [turn1["log"]])
	is_true(bool((eng.sides[0] as Dictionary)["megaUsed"]), "side 0 has spent its Mega")

	# B holds a perfectly good stone and the player still has the Key Stone -- and
	# it is still refused, because the SIDE has used its one Mega.
	is_false(eng.can_mega_evolve(b, 0), "B cannot Mega: the side already did")
	eq(String(eng.mega_check(b, 0)["reason"]), "side-used", "reason")
	is_false(eng.mega_evolve(0), "and forcing it fails")

	# Switch B in and try again through the real action path.
	eng.submit_action(0, {"kind": "switch", "index": 1})
	eng.submit_action(1, {"kind": "move", "move_index": 0})
	eng.resolve_turn()
	eq(Stats.display_name(eng.active(0)), "ZARD-B", "B is out")
	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	eng.submit_action(1, {"kind": "move", "move_index": 0})
	var turn3: Dictionary = eng.resolve_turn()
	is_false(Mega.is_mega(b), "B did not Mega Evolve")
	eq(first_index(turn3["log"], "Mega Evolved"), -1, "and nothing in the log claims it did")

	# A is still Mega: switching out does not revert it (only fainting and the end
	# of the battle do, per DATA_CONTRACT 11.2).
	is_true(Mega.is_mega(a), "A is still Mega on the bench")


func test_one_per_SIDE_not_one_per_battle() -> void:
	Mega.set_forms([FORM_CHARIZARD_X, FORM_GENGAR])
	var me := mon(6, "ZARD", ["fire", "flying"], CHARIZARD, 50,
		{"item": "charizardite-x", "moves": ["harden"]})
	# The opponent is a boss with a Key Stone of its own and a Gengarite.
	var foe := mon(94, "GENGAR", ["ghost", "poison"], CHARIZARD, 50,
		{"item": "gengarite", "moves": ["growl"]})
	var eng := engine_with([me], [foe], {"keyStone": true})

	is_true(eng.can_mega_evolve(foe, 1), "the boss can Mega too")
	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	var log1: Array = (eng.resolve_turn() as Dictionary)["log"]

	is_true(Mega.is_mega(me), "the player Mega Evolved")
	# The AI Megas on the first turn it can, so both sides do it on turn 1.
	is_true(Mega.is_mega(foe), "and so did the boss, on the same turn")
	is_true(first_index(log1, "Mega Charizard X") >= 0, "player's Mega in the log")
	is_true(first_index(log1, "Mega Gengar") >= 0, "boss's Mega in the log: %s" % [log1])
	is_true(bool((eng.sides[0] as Dictionary)["megaUsed"]), "side 0 spent")
	is_true(bool((eng.sides[1] as Dictionary)["megaUsed"]), "side 1 spent")


func test_a_wild_pokemon_never_mega_evolves() -> void:
	Mega.set_forms([FORM_GENGAR])
	var me := mon(6, "ZARD", ["fire", "flying"], CHARIZARD, 50,
		{"item": "", "moves": ["harden"]})
	var wild := mon(94, "GENGAR", ["ghost", "poison"], CHARIZARD, 50,
		{"item": "gengarite", "moves": ["growl"]})
	var eng := BattleEngine.new()
	eng.start({"kind": "wild", "party": [me], "opponent": wild, "cap": 100, "seed": 7})
	is_false(eng.can_mega_evolve(wild, 1), "a wild Gengar has no trainer and no Key Stone")
	eng.submit_action(0, {"kind": "move", "move_index": 0})
	eng.resolve_turn()
	is_false(Mega.is_mega(wild), "and it did not Mega Evolve")


# --------------------------------------------------------------------------
# 10. the Mega's Speed orders the turn it evolves (DATA_CONTRACT 11.2)
# --------------------------------------------------------------------------

## HAND COMPUTED, level 50, IV 31, EV 0, hardy:
##   synthetic base Spe  50 -> floor((100+31)/2) + 5 = 65 + 5  = 70
##   Mega Synth   Spe 150 -> floor((300+31)/2) + 5 = 165 + 5 = 170
##   the opponent's base Spe 100 -> floor((200+31)/2) + 5 = 115 + 5 = 120
## 70 < 120 < 170, so the SAME Pokemon moves second without the Mega and first
## with it -- and no speed tie can make this flaky either way.
func test_the_megas_speed_orders_the_turn_it_evolves() -> void:
	Mega.set_forms([FORM_SYNTH])
	var fast_base: Dictionary = {"hp": 200, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 100}

	# --- control: no Mega. The opponent is faster and goes first. ---
	var slow := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 50,
		{"item": "synthite", "moves": ["harden"]})
	var foe1 := mon(94, "SPEEDY", ["normal"], fast_base, 50, {"item": "", "moves": ["growl"]})
	eq(int((slow["stats"] as Dictionary)["spe"]), 70, "base Speed")
	eq(int((foe1["stats"] as Dictionary)["spe"]), 120, "opponent Speed")
	eq(TurnOrder.effective_speed(slow), 70, "effective base Speed")

	var control := engine_with([slow], [foe1], {"keyStone": false})
	control.submit_action(0, {"kind": "move", "move_index": 0})
	control.submit_action(1, {"kind": "move", "move_index": 0})
	var c_log: Array = (control.resolve_turn() as Dictionary)["log"]
	var c_me := first_index(c_log, "used Harden")
	var c_foe := first_index(c_log, "used Growl")
	is_true(c_me >= 0 and c_foe >= 0, "both moved: %s" % [c_log])
	is_true(c_foe < c_me, "control: Speed 120 moves before Speed 70 (%d < %d)" % [c_foe, c_me])

	# --- the real thing: Mega on the same turn, and now it outruns the foe. ---
	var mega_me := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 50,
		{"item": "synthite", "moves": ["harden"]})
	var foe2 := mon(94, "SPEEDY", ["normal"], fast_base, 50, {"item": "", "moves": ["growl"]})
	var eng := engine_with([mega_me], [foe2], {"keyStone": false})
	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	eng.submit_action(1, {"kind": "move", "move_index": 0})
	var m_log: Array = (eng.resolve_turn() as Dictionary)["log"]

	is_true(Mega.is_mega(mega_me), "Mega Evolved")
	eq(int((mega_me["stats"] as Dictionary)["spe"]), 170, "Mega Speed")
	eq(TurnOrder.effective_speed(mega_me), 170, "effective Mega Speed")

	var m_evolve := first_index(m_log, "Mega Evolved")
	var m_me := first_index(m_log, "used Harden")
	var m_foe := first_index(m_log, "used Growl")
	is_true(m_evolve >= 0, "the Mega happened: %s" % [m_log])
	is_true(m_me >= 0 and m_foe >= 0, "both moved: %s" % [m_log])
	is_true(m_evolve < m_me and m_evolve < m_foe,
		"Mega Evolution resolved BEFORE any move (%d < %d, %d)" % [m_evolve, m_me, m_foe])
	is_true(m_me < m_foe,
		"the MEGA's Speed ordered this turn: Speed 170 moved first (%d < %d)" % [m_me, m_foe])


# --------------------------------------------------------------------------
# 11. reverting: on fainting, and at the end of the battle
# --------------------------------------------------------------------------

func test_it_reverts_when_the_battle_ends() -> void:
	Mega.set_forms([FORM_CHARIZARD_X])
	var me := mon(6, "ZARD", ["fire", "flying"], CHARIZARD, 50,
		{"item": "charizardite-x", "moves": ["tackle"]})
	# Normal-type, because Tackle is Normal and Normal does not touch a Ghost.
	var doomed := mon(19, "RATTATA", ["normal"], FRAIL, 5,
		{"item": "", "moves": ["growl"], "hp": 1})
	var eng := engine_with([me], [doomed], {"keyStone": false})

	eng.submit_action(0, {"kind": "move", "move_index": 0, "mega": true})
	var r: Dictionary = eng.resolve_turn()
	is_true(bool(r["over"]), "the battle ended: %s" % [r["log"]])
	eq(String(r["outcome"]), "win", "we won")

	# DATA_CONTRACT 11.2 / megas.json revertsAfterBattle.
	is_false(Mega.is_mega(me), "no longer Mega")
	eq(types_of(me), ["fire", "flying"], "types back to Fire/Flying")
	eq(String(me["ability"]), "blaze", "ability back to Blaze")
	eq(String(me["name"]), "ZARD", "name back")
	eq(int((me["stats"] as Dictionary)["atk"]), 104, "Atk back to the base 104")
	eq(int(me["maxHp"]), 153, "max HP back")
	eq(int(me["level"]), 50, "level never moved")
	is_false(me.has("megaForm"), "no Mega bookkeeping left to reach the save file")
	is_false(me.has("megaBase"), "snapshot cleaned up")
	eq(spy.reverted.size(), 1, "mega_reverted fired once")

	# The party in the result payload -- what the overworld and the save system
	# actually receive -- is the base form too.
	var payload_mon: Dictionary = (r["party"] as Array)[0]
	is_false(Mega.is_mega(payload_mon), "result payload is base-form")


func test_it_reverts_when_it_faints() -> void:
	Mega.set_forms([FORM_SYNTH])
	# The boss's Mega is the one that dies, so the player's EXP award runs over an
	# already-reverted Pokemon. Steel/Dragon, not Ghost: Tackle has to be able to
	# reach it (Steel resists Normal, but the damage floor is 1 and it has 1 HP).
	var me := mon(6, "ZARD", ["fire", "flying"], CHARIZARD, 60,
		{"item": "", "moves": ["tackle"]})
	var foe := mon(900, "SYNTH", ["steel"], SPECIES_SYNTH, 30,
		{"item": "synthite", "moves": ["growl"], "hp": 1})
	var eng := engine_with([me], [foe], {"keyStone": true})

	eng.submit_action(0, {"kind": "move", "move_index": 0})
	var r: Dictionary = eng.resolve_turn()

	is_true(first_index(r["log"], "Mega Synth") >= 0, "it did Mega Evolve first: %s" % [r["log"]])
	is_true(Stats.is_fainted(foe), "and then it fainted")
	is_false(Mega.is_mega(foe), "reverted on fainting")
	eq(int(foe["hp"]), 0, "reverting does not revive it")
	eq(types_of(foe), ["steel"], "base types back")
	is_false(foe.has("megaBase"), "snapshot cleaned up")


func test_revert_is_a_no_op_on_something_that_never_mega_evolved() -> void:
	Mega.set_forms([FORM_CHARIZARD_X])
	var c := charizard(50, "charizardite-x")
	var hp_before := int(c["hp"])
	is_false(Mega.revert(c), "nothing to revert")
	eq(int(c["hp"]), hp_before, "HP untouched")
	eq(types_of(c), ["fire", "flying"], "types untouched")
	eq(Mega.revert_party([c, charizard(50, "")]), 0, "revert_party counted nothing")
