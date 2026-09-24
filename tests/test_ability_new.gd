extends "res://tests/framework/test_case.gd"
## The four previously-undocumented Mega abilities: mega-sol, dragonize, eelevate,
## fire-mane. Run:
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=ability_new
##
## Every damage number is HAND COMPUTED in the comment above the assertion, from
## the formula in src/battle/damage.gd, exactly as tests/test_battle.gd does it.
## Two styles are used deliberately:
##
##   * `Damage.compute` with `roll`/`crit` pinned, for exact arithmetic. This is
##     where a stat multiplier is distinguished from a damage multiplier -- the
##     numbers are chosen so `floor(a * 1.5)` and `floor(damage * 1.5)` DISAGREE.
##   * the real `BattleEngine`, for the wiring. The engine rolls its own damage
##     spread, so those assertions use BANDS whose hand-computed extremes cannot
##     overlap: an ability that is not wired in lands in the control band and
##     fails.
##
## Type chart and nothing else comes from the committed data (Deps falls back to a
## JSON reader over data/typechart.json when DataRegistry is not alive); every
## stat, power and type is pinned inline.

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Damage := preload("res://src/battle/damage.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")
const Mega := preload("res://src/battle/mega.gd")


func before_each() -> void:
	Deps.clear_overrides()


func after_each() -> void:
	Deps.clear_overrides()


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

## A Pokemon with pinned battle stats, so the arithmetic is exact.
func fixture(mon_name: String, types: Array, level: int, stats: Dictionary,
		opts: Dictionary = {}) -> Dictionary:
	var species_data: Dictionary = {
		"name": mon_name, "types": types,
		"stats": {"hp": 50, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50},
		"abilities": [String(opts.get("ability", ""))],
		"baseExp": 64, "growthRate": "medium-fast",
	}
	var build_opts := opts.duplicate()
	build_opts["species_data"] = species_data
	build_opts["name"] = mon_name
	build_opts["moves"] = []
	var mon := Stats.build(int(opts.get("species", 1)), level, build_opts)
	mon["stats"] = stats.duplicate()
	mon["maxHp"] = int(stats.get("hp", 100))
	mon["hp"] = int(opts.get("hp", mon["maxHp"]))
	mon["ability"] = String(opts.get("ability", ""))
	mon["moves"] = (opts.get("moves", []) as Array).duplicate()
	return mon


func plain_move(move_name: String, move_type: String, category: String, power: int,
		extra: Dictionary = {}) -> Dictionary:
	var move: Dictionary = {
		"id": 0, "name": move_name, "slug": move_name.to_lower().replace(" ", "-"),
		"type": move_type, "category": category, "power": power, "accuracy": null,
		"pp": 10, "maxPp": 10, "priority": 0, "effect": "", "effectChance": 0,
	}
	move.merge(extra, true)
	return move


## Damage a single move actually took off the target in one engine turn.
func one_turn_damage(attacker: Dictionary, defender: Dictionary, seed_value: int = 4242,
		weather: String = "") -> int:
	var engine := BattleEngine.new()
	engine.start({"kind": "wild", "party": [attacker], "opponent": [defender],
		"cap": 100, "seed": seed_value, "weather": weather})
	var before := int(defender["hp"])
	engine.submit_action(0, {"kind": "move", "move_index": 0})
	engine.submit_action(1, {"kind": "move", "move_index": 0})
	engine.resolve_turn()
	return before - int(defender["hp"])


# --------------------------------------------------------------------------
# mega-sol -- Mega Meganium. Per-mon weather VIEW.
# --------------------------------------------------------------------------

## HAND COMPUTED, level 50, SpA 100 vs SpD 103, 90-power special, STAB 1.5,
## neutral type, roll 100, no crit:
##   levelFactor = floor(2*50/5) + 2                  = 22
##   inner       = floor(22 * 90 * 100 / 103)         = 1922
##   base        = floor(1922 / 50) + 2               = 40
##   no view  : 40 -> roll 40 -> STAB floor(60.0)     = 60
##   sun view : floor(40 * 1.5) = 60 -> roll 60
##                  -> STAB floor(90.0)               = 90
func test_mega_sol_makes_the_bearers_own_fire_move_hit_as_if_in_sun() -> void:
	var flare := plain_move("Flare", "fire", "special", 90)
	var sunlit := fixture("MEGA MEGANIUM", ["fire", "grass"], 50,
		{"hp": 160, "atk": 92, "def": 115, "spa": 100, "spd": 115, "spe": 80},
		{"ability": "mega-sol", "moves": [flare.duplicate()]})
	var plain := fixture("CONTROL", ["fire", "grass"], 50,
		{"hp": 160, "atk": 92, "def": 115, "spa": 100, "spd": 115, "spe": 80},
		{"ability": "", "moves": [flare.duplicate()]})
	var target := fixture("TARGET", ["normal"], 50,
		{"hp": 400, "atk": 80, "def": 100, "spa": 80, "spd": 103, "spe": 50})

	# The weather the bearer's move is resolved under, with an empty field.
	eq(Abilities.weather_view(sunlit, ""), "sun", "mega-sol's view")
	eq(Abilities.weather_view(plain, ""), "", "no ability, no view")

	var lit := Damage.compute(sunlit, target, flare,
		{"roll": 100, "crit": false, "weather": Abilities.weather_view(sunlit, "")})
	var control := Damage.compute(plain, target, flare,
		{"roll": 100, "crit": false, "weather": Abilities.weather_view(plain, "")})
	eq(int(control["base"]), 40, "hand-computed base")
	eq(int(control["damage"]), 60, "no view, no weather")
	eq(int(lit["damage"]), 90, "mega-sol: Fire x1.5 as if in harsh sunlight")


## The engine must thread the view into the damage ctx (battle_engine _use_move).
## BANDS, hand computed: with no view the 16 rolls give
## floor(floor(40*r/100)*1.5) = 51..60; under the sun view
## floor(floor(60*r/100)*1.5) = 76..90. They cannot overlap, so a broken wiring
## cannot pass.
func test_mega_sol_is_wired_into_the_engine_and_does_not_leak_to_the_opponent() -> void:
	var flare := plain_move("Flare", "fire", "special", 90)
	var sunlit := fixture("MEGA MEGANIUM", ["fire", "grass"], 50,
		{"hp": 400, "atk": 92, "def": 115, "spa": 100, "spd": 103, "spe": 200},
		{"ability": "mega-sol", "moves": [flare.duplicate()]})
	var plain := fixture("CONTROL", ["fire", "grass"], 50,
		{"hp": 400, "atk": 92, "def": 115, "spa": 100, "spd": 103, "spe": 200},
		{"ability": "", "moves": [flare.duplicate()]})

	# The foe is a Fire-type too, with the SAME move and stats, so its own damage
	# output prices whether the view leaked onto the field.
	var foe_a := fixture("FOE", ["fire", "grass"], 50,
		{"hp": 400, "atk": 80, "def": 100, "spa": 100, "spd": 103, "spe": 10},
		{"ability": "", "moves": [flare.duplicate()]})
	var foe_b := fixture("FOE", ["fire", "grass"], 50,
		{"hp": 400, "atk": 80, "def": 100, "spa": 100, "spd": 103, "spe": 10},
		{"ability": "", "moves": [flare.duplicate()]})

	var lit_dealt := one_turn_damage(sunlit, foe_a, 1234)
	var control_dealt := one_turn_damage(plain, foe_b, 1234)

	check(control_dealt >= 51 and control_dealt <= 60,
		"control band 51..60, got %d" % control_dealt)
	check(lit_dealt >= 76 and lit_dealt <= 90,
		"mega-sol band 76..90, got %d" % lit_dealt)
	# The view is per-mon: the foe holds no ability and must be unaffected, so the
	# damage IT dealt back is identical in both battles.
	eq(400 - int(sunlit["hp"]), 400 - int(plain["hp"]),
		"the opponent's Fire move was not boosted by the bearer's view")


## The view replaces the field for the bearer's move, so the sandstorm Rock
## Sp. Def boost is skipped. HAND COMPUTED, 90-power special PSYCHIC move (neither
## Fire nor Water, so weather_mult is 1.0 either way), SpA 100, target Rock with
## SpD 103, roll 100:
##   sandstorm: d = floor(103 * 1.5) = 154
##              base = floor(floor(22*90*100/154)/50) + 2 = 27   (no STAB)
##   sun view : d = 103 -> base = 40
func test_mega_sol_view_skips_the_sandstorm_rock_special_defence_boost() -> void:
	var psybeam := plain_move("Mind Ray", "psychic", "special", 90)
	var sunlit := fixture("MEGA MEGANIUM", ["grass", "fairy"], 50,
		{"hp": 160, "atk": 92, "def": 115, "spa": 100, "spd": 115, "spe": 80},
		{"ability": "mega-sol", "moves": [psybeam.duplicate()]})
	var plain := fixture("CONTROL", ["grass", "fairy"], 50,
		{"hp": 160, "atk": 92, "def": 115, "spa": 100, "spd": 115, "spe": 80},
		{"ability": "", "moves": [psybeam.duplicate()]})
	var rocky := fixture("ROCKY", ["rock"], 50,
		{"hp": 400, "atk": 80, "def": 100, "spa": 80, "spd": 103, "spe": 50})

	var in_sand := Damage.compute(plain, rocky, psybeam,
		{"roll": 100, "crit": false, "weather": Abilities.weather_view(plain, "sandstorm")})
	var viewed := Damage.compute(sunlit, rocky, psybeam,
		{"roll": 100, "crit": false, "weather": Abilities.weather_view(sunlit, "sandstorm")})
	eq(int(in_sand["damage"]), 27, "sandstorm boosts Rock Sp. Def by 50%")
	eq(int(viewed["damage"]), 40, "the sun view never sees the sandstorm")


## The other half of the view is a self-nerf, and it must be present: Water moves
## lose 50%. Same 40 base, no STAB (Grass/Fairy using a Water move):
##   no view : 40 -> roll 40 = 40
##   sun view: floor(40 * 0.5) = 20 -> roll 20 = 20
func test_mega_sol_also_halves_the_bearers_own_water_moves() -> void:
	var splash := plain_move("Water Jet", "water", "special", 90)
	var sunlit := fixture("MEGA MEGANIUM", ["grass", "fairy"], 50,
		{"hp": 160, "atk": 92, "def": 115, "spa": 100, "spd": 115, "spe": 80},
		{"ability": "mega-sol", "moves": [splash.duplicate()]})
	var target := fixture("TARGET", ["normal"], 50,
		{"hp": 400, "atk": 80, "def": 100, "spa": 80, "spd": 103, "spe": 50})

	var wet := Damage.compute(sunlit, target, splash,
		{"roll": 100, "crit": false, "weather": Abilities.weather_view(sunlit, "")})
	eq(int(wet["damage"]), 20, "mega-sol: Water x0.5, the documented downside")


# --------------------------------------------------------------------------
# dragonize -- Mega Feraligatr. Normal -> Dragon, +20% power.
# --------------------------------------------------------------------------

func test_dragonize_converts_only_damaging_normal_moves() -> void:
	var gatr := fixture("MEGA FERALIGATR", ["water", "dragon"], 50,
		{"hp": 170, "atk": 200, "def": 125, "spa": 89, "spd": 93, "spe": 78},
		{"ability": "dragonize"})

	var body_slam := plain_move("Body Slam", "normal", "physical", 85)
	var got := Abilities.modify_move(gatr, body_slam)
	eq(String(got.get("type", "")), "dragon", "Body Slam becomes Dragon")
	almost(float(got.get("power_mult", 1.0)), 1.2, 0.0001, "+20% power")
	# 85 * 1.2 = 102 -- and binary 1.2 is a hair UNDER 1.2, which is why the
	# engine adds an epsilon before flooring. A bare floori() gives 101.
	eq(maxi(1, floori(85.0 * 1.2 + 1e-6)), 102, "85 power -> 102 power")

	# Status moves are not converted: "Normal-type ATTACKING moves".
	var growl := plain_move("Growl", "normal", "status", 0)
	eq(Abilities.modify_move(gatr, growl), {}, "status move untouched")
	# Nor is a move that is already another type.
	var surf := plain_move("Surf", "water", "special", 90)
	eq(Abilities.modify_move(gatr, surf), {}, "non-Normal move untouched")
	# Nor a move whose type is set by another mechanism (the -ate exclusion list).
	var hp_move := plain_move("Hidden Power", "normal", "special", 60)
	eq(Abilities.modify_move(gatr, hp_move), {}, "hidden-power excluded")


## The whole ability is the ORDER: convert, then STAB, then the type chart.
## HAND COMPUTED, level 50, Atk 200 vs Def 100, target pure Fighting (Normal x1
## AND Dragon x1, so the chart is not what changes), roll 100, no crit:
##   control   85 power, no STAB (Water/Dragon using a Normal move):
##     base = floor(floor(22*85*200/100)/50) + 2 = 76 -> 76
##   dragonized 102 power, Dragon STAB off Water/DRAGON:
##     base = floor(floor(22*102*200/100)/50) + 2 = 91
##     roll 91 -> STAB floor(136.5) = 136
## 76 -> 136 is the 1.2 x 1.5 = 1.8 "80% effective increase" the source cites.
## Engine bands over the 16 rolls: control 64..76, dragonized 115..136.
func test_dragonize_engine_damage_adds_power_then_stab_and_never_mutates_the_move() -> void:
	var body_slam := plain_move("Body Slam", "normal", "physical", 85)
	var gatr := fixture("MEGA FERALIGATR", ["water", "dragon"], 50,
		{"hp": 170, "atk": 200, "def": 125, "spa": 89, "spd": 93, "spe": 200},
		{"ability": "dragonize", "moves": [body_slam.duplicate()]})
	var plain := fixture("CONTROL", ["water", "dragon"], 50,
		{"hp": 170, "atk": 200, "def": 125, "spa": 89, "spd": 93, "spe": 200},
		{"ability": "", "moves": [body_slam.duplicate()]})
	var brawler_a := fixture("BRAWLER", ["fighting"], 50,
		{"hp": 500, "atk": 80, "def": 100, "spa": 60, "spd": 80, "spe": 10},
		{"moves": [plain_move("Tackle", "normal", "physical", 40)]})
	var brawler_b := fixture("BRAWLER", ["fighting"], 50,
		{"hp": 500, "atk": 80, "def": 100, "spa": 60, "spd": 80, "spe": 10},
		{"moves": [plain_move("Tackle", "normal", "physical", 40)]})

	var boosted := one_turn_damage(gatr, brawler_a, 77)
	var control := one_turn_damage(plain, brawler_b, 77)
	check(control >= 64 and control <= 76, "control band 64..76, got %d" % control)
	check(boosted >= 115 and boosted <= 136,
		"dragonized band 115..136, got %d" % boosted)

	# THE MON'S STORED MOVE MUST BE UNTOUCHED. resolve_turn() hands _use_move the
	# live dictionary; a mutation here would make Body Slam permanently
	# Dragon-type in the save. PP still decremented, on that same live dict.
	var stored: Dictionary = (gatr["moves"] as Array)[0]
	eq(String(stored["type"]), "normal", "stored move type not rewritten")
	eq(int(stored["power"]), 85, "stored move power not rewritten")
	eq(int(stored["pp"]), 9, "PP still decremented on the live move")


## Dragonize changes IMMUNITIES too, in both directions. Against a Ghost, Normal
## does nothing at all and a Dragonized Body Slam does full damage; against a
## Fairy, the reverse.
func test_dragonize_flips_the_ghost_and_fairy_immunities() -> void:
	var body_slam := plain_move("Body Slam", "normal", "physical", 85)
	var make_gatr := func(ability: String) -> Dictionary:
		return fixture("MEGA FERALIGATR", ["water", "dragon"], 50,
			{"hp": 170, "atk": 200, "def": 125, "spa": 89, "spd": 93, "spe": 200},
			{"ability": ability, "moves": [body_slam.duplicate()]})
	var make_target := func(types: Array) -> Dictionary:
		return fixture("TARGET", types, 50,
			{"hp": 500, "atk": 60, "def": 100, "spa": 60, "spd": 80, "spe": 10},
			{"moves": [plain_move("Tackle", "normal", "physical", 40)]})

	var ghost_vs_dragonize := one_turn_damage(make_gatr.call("dragonize"),
		make_target.call(["ghost"]), 5)
	var ghost_vs_control := one_turn_damage(make_gatr.call(""),
		make_target.call(["ghost"]), 5)
	check(ghost_vs_dragonize > 0,
		"a Dragonized Body Slam hits a Ghost, got %d" % ghost_vs_dragonize)
	eq(ghost_vs_control, 0, "Normal-type Body Slam does nothing to a Ghost")

	var fairy_vs_dragonize := one_turn_damage(make_gatr.call("dragonize"),
		make_target.call(["fairy"]), 5)
	var fairy_vs_control := one_turn_damage(make_gatr.call(""),
		make_target.call(["fairy"]), 5)
	eq(fairy_vs_dragonize, 0, "a Fairy takes 0 from a Dragonized Body Slam")
	check(fairy_vs_control > 0, "Normal-type Body Slam hits a Fairy normally")


# --------------------------------------------------------------------------
# fire-mane -- Mega Pyroar. x1.5 on the attacking STAT.
# --------------------------------------------------------------------------

## THE NUMBERS ARE CHOSEN SO A STAT MULTIPLIER AND A DAMAGE MULTIPLIER DISAGREE.
## Level 50, SpA 100 vs SpD 103, 90-power special FIRE move, STAB 1.5, target
## Normal (Fire x1), roll 100, no crit:
##   control  : inner = floor(22*90*100/103) = 1922
##              base  = floor(1922/50) + 2   = 40 -> STAB floor(60.0) = 60
##   fire-mane: a = floor(100 * 1.5) = 150
##              inner = floor(22*90*150/103) = 2883
##              base  = floor(2883/50) + 2   = 59 -> STAB floor(88.5) = 88
##   a naive damage x 1.5 would give floor(60 * 1.5) = 90, NOT 88.
func test_fire_mane_multiplies_the_attacking_stat_not_the_damage() -> void:
	var flare := plain_move("Flare", "fire", "special", 90)
	var pyroar := fixture("MEGA PYROAR", ["fire", "normal"], 50,
		{"hp": 166, "atk": 88, "def": 92, "spa": 100, "spd": 86, "spe": 126},
		{"ability": "fire-mane", "moves": [flare.duplicate()]})
	var plain := fixture("CONTROL", ["fire", "normal"], 50,
		{"hp": 166, "atk": 88, "def": 92, "spa": 100, "spd": 86, "spe": 126},
		{"ability": "", "moves": [flare.duplicate()]})
	var target := fixture("TARGET", ["normal"], 50,
		{"hp": 400, "atk": 80, "def": 100, "spa": 80, "spd": 103, "spe": 50})

	var control := Damage.compute(plain, target, flare, {"roll": 100, "crit": false})
	var maned := Damage.compute(pyroar, target, flare, {"roll": 100, "crit": false})
	eq(int(control["base"]), 40, "hand-computed control base")
	eq(int(control["damage"]), 60, "control damage")
	eq(int(maned["base"]), 59, "the STAT was multiplied: base moves 40 -> 59")
	eq(int(maned["damage"]), 88, "fire-mane damage")
	neq(int(maned["damage"]), 90, "NOT a damage multiplier (that would be 90)")


func test_fire_mane_only_touches_fire_moves_and_only_on_the_attacking_side() -> void:
	var flare := plain_move("Flare", "fire", "special", 90)
	var punch := plain_move("Force Punch", "fighting", "physical", 90)
	var pyroar := fixture("MEGA PYROAR", ["fire", "normal"], 50,
		{"hp": 166, "atk": 100, "def": 92, "spa": 100, "spd": 86, "spe": 126},
		{"ability": "fire-mane", "moves": [flare.duplicate()]})
	var plain := fixture("CONTROL", ["fire", "normal"], 50,
		{"hp": 166, "atk": 100, "def": 92, "spa": 100, "spd": 86, "spe": 126},
		{"ability": "", "moves": [flare.duplicate()]})
	var target := fixture("TARGET", ["normal"], 50,
		{"hp": 400, "atk": 100, "def": 100, "spa": 100, "spd": 103, "spe": 50},
		{"moves": [flare.duplicate()]})

	# A non-Fire move is untouched.
	eq(int(Damage.compute(pyroar, target, punch, {"roll": 100, "crit": false})["damage"]),
		int(Damage.compute(plain, target, punch, {"roll": 100, "crit": false})["damage"]),
		"a Fighting move gets nothing")

	# Being HIT by a Fire move is not affected: the hook is attacker-role only.
	eq(int(Damage.compute(target, pyroar, flare, {"roll": 100, "crit": false})["damage"]),
		int(Damage.compute(target, plain, flare, {"roll": 100, "crit": false})["damage"]),
		"fire-mane does not reduce incoming Fire damage")

	# And the physical half of the sentence: Attack, not Sp. Atk, for a physical
	# Fire move. Atk 100 -> 150 moves the base exactly as the special case did.
	var fire_punch := plain_move("Fire Punch", "fire", "physical", 90)
	var phys_control := Damage.compute(plain, target, fire_punch, {"roll": 100, "crit": false})
	var phys_maned := Damage.compute(pyroar, target, fire_punch, {"roll": 100, "crit": false})
	check(int(phys_maned["damage"]) > int(phys_control["damage"]),
		"physical Fire move boosted too: %d vs %d"
			% [int(phys_maned["damage"]), int(phys_control["damage"])])


## Engine wiring. Bands over the 16 rolls with the fixture above:
##   control  : floor(floor(40*r/100)*1.5) = 51..60
##   fire-mane: floor(floor(59*r/100)*1.5) = 75..88
func test_fire_mane_is_wired_into_the_engine() -> void:
	var flare := plain_move("Flare", "fire", "special", 90)
	var pyroar := fixture("MEGA PYROAR", ["fire", "normal"], 50,
		{"hp": 400, "atk": 88, "def": 92, "spa": 100, "spd": 86, "spe": 200},
		{"ability": "fire-mane", "moves": [flare.duplicate()]})
	var plain := fixture("CONTROL", ["fire", "normal"], 50,
		{"hp": 400, "atk": 88, "def": 92, "spa": 100, "spd": 86, "spe": 200},
		{"ability": "", "moves": [flare.duplicate()]})
	var target_a := fixture("TARGET", ["normal"], 50,
		{"hp": 500, "atk": 80, "def": 100, "spa": 80, "spd": 103, "spe": 10},
		{"moves": [plain_move("Tackle", "normal", "physical", 40)]})
	var target_b := fixture("TARGET", ["normal"], 50,
		{"hp": 500, "atk": 80, "def": 100, "spa": 80, "spd": 103, "spe": 10},
		{"moves": [plain_move("Tackle", "normal", "physical", 40)]})

	var maned := one_turn_damage(pyroar, target_a, 909)
	var control := one_turn_damage(plain, target_b, 909)
	check(control >= 51 and control <= 60, "control band 51..60, got %d" % control)
	check(maned >= 75 and maned <= 88, "fire-mane band 75..88, got %d" % maned)


# --------------------------------------------------------------------------
# eelevate -- Mega Eelektross. Grounding + the Beast Boost KO snowball.
# --------------------------------------------------------------------------

func test_eelevate_is_immune_to_ground_moves_in_a_real_battle() -> void:
	var quake := plain_move("Earthquake", "ground", "physical", 100)
	var digger_a := fixture("DIGGER", ["ground"], 50,
		{"hp": 200, "atk": 150, "def": 100, "spa": 60, "spd": 80, "spe": 200},
		{"moves": [quake.duplicate()]})
	var digger_b := fixture("DIGGER", ["ground"], 50,
		{"hp": 200, "atk": 150, "def": 100, "spa": 60, "spd": 80, "spe": 200},
		{"moves": [quake.duplicate()]})
	var eel := fixture("MEGA EELEKTROSS", ["electric"], 50,
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80},
		{"ability": "eelevate", "moves": [plain_move("Spark", "electric", "physical", 65)]})
	var control := fixture("CONTROL", ["electric"], 50,
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80},
		{"ability": "", "moves": [plain_move("Spark", "electric", "physical", 65)]})

	eq(one_turn_damage(digger_a, eel, 31), 0, "Earthquake does nothing to eelevate")
	check(one_turn_damage(digger_b, control, 31) > 0,
		"the same Earthquake hurts the same Pokemon without the ability")
	almost(Damage.type_multiplier("ground", eel["types"], {"defender": eel}), 0.0, 0.0001,
		"ground vs an ungrounded target")
	almost(Damage.type_multiplier("ground", control["types"], {"defender": control}), 2.0,
		0.0001, "ground vs Electric is x2 without the ability")
	is_false(Abilities.is_grounded(eel), "eelevate is not grounded")
	is_true(Abilities.is_grounded(control), "the control mon is grounded")


## Gravity / Iron Ball / Ingrain / Smack Down do not exist yet; they all land on
## `volatile.grounded_by`, and the ability must already respect it.
func test_eelevate_grounding_is_negated_by_the_grounded_by_flag() -> void:
	var eel := fixture("MEGA EELEKTROSS", ["electric"], 50,
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80},
		{"ability": "eelevate"})
	(eel["volatile"] as Dictionary)["grounded_by"] = true
	almost(Damage.type_multiplier("ground", eel["types"], {"defender": eel}), 2.0, 0.0001,
		"a grounded eelevate takes Ground damage again")
	is_true(Abilities.is_grounded(eel), "grounded_by wins over the ability")


## HALF 2, the part a "it's just Levitate" implementation would silently drop.
## Mega Eelektross's real spread is 145/80/135/90/80, so ATTACK wins -- and the
## spread is pinned exactly, because an inflated Speed here would (correctly) be
## the stat that rises and the test would stop testing what it claims to.
func test_eelevate_raises_its_highest_raw_stat_on_a_direct_ko() -> void:
	var eel := fixture("MEGA EELEKTROSS", ["electric"], 50,
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80},
		{"ability": "eelevate", "moves": [plain_move("Spark", "electric", "physical", 65)]})
	var doomed := fixture("DOOMED", ["normal"], 50,
		{"hp": 300, "atk": 60, "def": 100, "spa": 60, "spd": 80, "spe": 10},
		{"hp": 1, "moves": [plain_move("Tackle", "normal", "physical", 40)]})

	var engine := BattleEngine.new()
	engine.start({"kind": "wild", "party": [eel], "opponent": [doomed],
		"cap": 100, "seed": 8})
	engine.submit_action(0, {"kind": "move", "move_index": 0})
	engine.resolve_turn()

	check(int(doomed["hp"]) <= 0, "the target actually fainted")
	eq(Stats.get_stage(eel, "atk"), 1, "Attack rose one stage on the KO")
	for key: String in ["def", "spa", "spd", "spe"]:
		eq(Stats.get_stage(eel, key), 0, "only Attack rose, %s did not" % key)
	check(engine.battle_log.has("MEGA EELEKTROSS's atk rose!"),
		"the boost was announced, log: %s" % [engine.battle_log])


## A hit that does NOT knock the target out gives nothing.
func test_eelevate_does_not_boost_without_a_ko() -> void:
	var eel := fixture("MEGA EELEKTROSS", ["electric"], 50,
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80},
		{"ability": "eelevate", "moves": [plain_move("Spark", "electric", "physical", 65)]})
	var tank := fixture("TANK", ["normal"], 50,
		{"hp": 999, "atk": 60, "def": 250, "spa": 60, "spd": 80, "spe": 10},
		{"moves": [plain_move("Tackle", "normal", "physical", 40)]})

	var dealt := one_turn_damage(eel, tank, 12)
	check(dealt > 0, "the hit connected, got %d" % dealt)
	check(int(tank["hp"]) > 0, "the target survived")
	for key: String in ["atk", "def", "spa", "spd", "spe"]:
		eq(Stats.get_stage(eel, key), 0, "no boost without a KO, %s" % key)


## Beast Boost's rule, verbatim: RAW stats, HP excluded, ties broken
## atk -> def -> spa -> spd -> spe. Using effective_stat() instead is the classic
## bug -- the choice would drift as stages change.
func test_eelevate_reads_raw_stats_and_breaks_ties_in_order() -> void:
	var impl := Abilities.of("eelevate")
	check(impl != null, "eelevate is registered")
	if impl == null:
		return

	var mon := fixture("EEL", ["electric"], 50,
		{"hp": 999, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80},
		{"ability": "eelevate"})
	eq(impl.highest_stat(mon), "atk", "145 Atk beats 135 SpA")

	# +6 Sp. Atk, -6 Attack: the EFFECTIVE Sp. Atk is now far higher, and the
	# answer must not move.
	Stats.change_stage(mon, "spa", 6)
	Stats.change_stage(mon, "atk", -6)
	check(Stats.effective_stat(mon, "spa") > Stats.effective_stat(mon, "atk"),
		"the stages really did invert the effective stats")
	eq(impl.highest_stat(mon), "atk", "still Attack: RAW stats, not effective ones")

	# Ties go to the earlier key in atk, def, spa, spd, spe.
	var tied := fixture("TIED", ["normal"], 50,
		{"hp": 100, "atk": 120, "def": 120, "spa": 120, "spd": 120, "spe": 120})
	eq(impl.highest_stat(tied), "atk", "a five-way tie goes to Attack")
	var speedy := fixture("SPEEDY", ["normal"], 50,
		{"hp": 100, "atk": 90, "def": 90, "spa": 90, "spd": 90, "spe": 130})
	eq(impl.highest_stat(speedy), "spe", "the highest wins when there is no tie")

	# A status move never triggers it, and neither does a non-KO.
	eq(impl.on_after_hit({"mon": mon, "ko": false,
		"move": {"category": "physical"}}), {}, "no KO, no boost")
	eq(impl.on_after_hit({"mon": mon, "ko": true,
		"move": {"category": "status"}}), {}, "status moves cannot KO-boost")


# --------------------------------------------------------------------------
# the no-op guarantee these four rely on
# --------------------------------------------------------------------------

## An ability with no implementation must cost exactly one Dictionary miss and
## return every neutral value. This is what keeps the other ~300 abilities safe.
func test_an_unimplemented_ability_is_a_no_op_through_every_hook_used_here() -> void:
	var stinker := fixture("STINKER", ["poison"], 50,
		{"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100},
		{"ability": "stench"})
	var move := plain_move("Body Slam", "normal", "physical", 85)

	eq(Abilities.of("stench"), null, "no implementation for stench")
	eq(Abilities.weather_view(stinker, "rain"), "rain", "weather_view is neutral")
	eq(Abilities.modify_move(stinker, move), {}, "modify_move is neutral")
	eq(Abilities.after_hit(stinker, stinker, move, {"ko": true}), {},
		"after_hit is neutral")
	eq(Abilities.type_immunity(stinker, "ground"), {}, "type_immunity is neutral")
	var mods := Abilities.damage_mods(stinker, stinker, move)
	almost(float(mods["atk_mult"]), 1.0, 0.0001, "atk_mult neutral")
	almost(float(mods["power_mult"]), 1.0, 0.0001, "power_mult neutral")
	almost(float(mods["damage_mult"]), 1.0, 0.0001, "damage_mult neutral")
	almost(Damage.type_multiplier("ground", stinker["types"], {"defender": stinker}), 2.0,
		0.0001, "ground vs poison is still x2")


# --------------------------------------------------------------------------
# the real Mega path: data/megas.json -> mega.gd -> registry
# --------------------------------------------------------------------------

## All four are Mega-exclusive, so the only way a player ever meets them is
## Mega Evolution. mega.gd's evolve() rewrites mon["ability"], and
## Abilities.for_mon() reads exactly that key -- this test is the join between the
## data file, the form table and the four implementations.
func test_mega_evolution_grants_each_of_the_four_abilities_and_they_work() -> void:
	var cases: Array = [
		["meganium-mega", "mega-sol"],
		["feraligatr-mega", "dragonize"],
		["eelektross-mega", "eelevate"],
		["pyroar-mega", "fire-mane"],
	]
	for row: Array in cases:
		var form := Mega.form_by_id(String(row[0]))
		if form.is_empty():
			pending("data/megas.json has no form %s" % row[0])
			continue
		eq(PackedStringArray(form.get("abilities", [])).has(String(row[1])), true,
			"%s carries %s in data/megas.json" % [row[0], row[1]])

		var mon := fixture("SUBJECT", ["normal"], 50,
			{"hp": 200, "atk": 120, "def": 100, "spa": 120, "spd": 100, "spe": 100},
			{"ability": "run-away"})
		var res := Mega.evolve(mon, form)
		is_true(bool(res["ok"]), "%s: evolve() succeeded (%s)" % [row[0], res.get("reason", "")])
		eq(String(mon["ability"]), String(row[1]), "%s: ability rewritten" % row[0])
		check(Abilities.for_mon(mon) != null,
			"%s: the registry resolves the new ability" % row[0])

	# And each one's real effect, read off the evolved mon rather than a fixture.
	var meganium := fixture("MEGANIUM", ["grass"], 50,
		{"hp": 200, "atk": 92, "def": 115, "spa": 143, "spd": 115, "spe": 80})
	if not Mega.form_by_id("meganium-mega").is_empty():
		Mega.evolve(meganium, Mega.form_by_id("meganium-mega"))
		eq(Abilities.weather_view(meganium, "rain"), "sun",
			"an evolved Mega Meganium resolves its moves in the sun")

	var gatr := fixture("FERALIGATR", ["water"], 50,
		{"hp": 200, "atk": 160, "def": 125, "spa": 89, "spd": 93, "spe": 78})
	if not Mega.form_by_id("feraligatr-mega").is_empty():
		Mega.evolve(gatr, Mega.form_by_id("feraligatr-mega"))
		var converted := Abilities.modify_move(gatr, plain_move("Body Slam", "normal", "physical", 85))
		eq(String(converted.get("type", "")), "dragon",
			"an evolved Mega Feraligatr Dragonizes Body Slam")

	var eel := fixture("EELEKTROSS", ["electric"], 50,
		{"hp": 200, "atk": 115, "def": 80, "spa": 105, "spd": 80, "spe": 50})
	if not Mega.form_by_id("eelektross-mega").is_empty():
		Mega.evolve(eel, Mega.form_by_id("eelektross-mega"))
		is_false(Abilities.is_grounded(eel), "an evolved Mega Eelektross floats")
		var impl := Abilities.of("eelevate")
		if impl != null:
			# Its real recomputed stats, not a hand-picked spread: 145 base Atk beats
			# 135 base SpA at every level, so Attack is the snowball stat.
			eq(impl.highest_stat(eel), "atk",
				"Attack is the highest raw stat on the real form, got %s"
					% impl.highest_stat(eel))

	var pyroar := fixture("PYROAR", ["fire", "normal"], 50,
		{"hp": 200, "atk": 68, "def": 72, "spa": 109, "spd": 66, "spe": 106})
	if not Mega.form_by_id("pyroar-mega").is_empty():
		Mega.evolve(pyroar, Mega.form_by_id("pyroar-mega"))
		var flare := plain_move("Flare", "fire", "special", 90)
		var mods := Abilities.damage_mods(pyroar, pyroar, flare)
		almost(float(mods["atk_mult"]), 1.5, 0.0001,
			"an evolved Mega Pyroar gets x1.5 on its Fire attacking stat")
		var punch := plain_move("Force Punch", "fighting", "physical", 90)
		almost(float(Abilities.damage_mods(pyroar, pyroar, punch)["atk_mult"]), 1.0, 0.0001,
			"and nothing on a non-Fire move")
