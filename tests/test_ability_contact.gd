extends "res://tests/framework/test_case.gd"
## The CONTACT ability group: unseen-fist, piercing-drill, aura-guard, spicy-spray.
##
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=ability_contact
##
## Every assertion is on a BATTLE OUTCOME -- HP actually lost, a status actually
## inflicted, a move actually blocked or not blocked -- never on a hook having been
## called. Damage numbers are hand-computed in the comment above the assertion from
## the formula in src/battle/damage.gd, so a number that moves says whether the new
## number is right.
##
## Moves come from the committed data/moves.json (DATA_CONTRACT 2), which is the
## point: `flags` has to survive Stats.make_move() or none of these abilities can
## tell a contact move from a non-contact one.

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Damage := preload("res://src/battle/damage.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")


func before_each() -> void:
	Deps.clear_overrides()


func after_each() -> void:
	Deps.clear_overrides()


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

## A Pokemon with PINNED battle stats, so the arithmetic is exact and independent
## of the species table.
func fixture(mon_name: String, types: Array, ability: String, stats: Dictionary,
		moves: Array = [], opts: Dictionary = {}) -> Dictionary:
	var species_data: Dictionary = {
		"name": mon_name, "types": types,
		"stats": {"hp": 50, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50},
		"abilities": [ability], "baseExp": 64, "growthRate": "medium-fast",
	}
	var build_opts := opts.duplicate()
	build_opts["species_data"] = species_data
	build_opts["name"] = mon_name
	build_opts["ability"] = ability
	build_opts["moves"] = moves
	var mon := Stats.build(1, 50, build_opts)
	mon["stats"] = stats.duplicate()
	mon["maxHp"] = int(stats.get("hp", 100))
	mon["hp"] = int(opts.get("hp", mon["maxHp"]))
	return mon


func attacker_with(ability: String, moves: Array = ["tackle"], spe: int = 200) -> Dictionary:
	return fixture("ATTACKER", ["water"], ability,
		{"hp": 300, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": spe}, moves)


func defender_with(ability: String, hp: int = 300, types: Array = ["water"]) -> Dictionary:
	return fixture("DEFENDER", types, ability,
		{"hp": hp, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 1}, [], {"hp": hp})


## One turn of a real battle: the player attacks with move 0, the foe has no moves
## at all (auto_action returns "struggle", which prints a line and does nothing), so
## the only thing that moves the numbers is the player's move and the abilities.
func one_turn(player_mon: Dictionary, foe_mon: Dictionary, seed_value: int = 4242) -> Dictionary:
	var b := BattleEngine.new()
	b.start({
		"kind": "trainer", "party": [player_mon], "opponent": [foe_mon],
		"cap": 100, "seed": seed_value,
		"trainer": {"name": "Tester", "ai": 1, "keyStone": false, "prizeMoney": 0},
	})
	b.submit_action(0, {"kind": "move", "move_index": 0})
	var r := b.resolve_turn()
	return {"engine": b, "log": r["log"] as Array}


func log_has(lines: Array, fragment: String) -> bool:
	for line: String in lines:
		if line.contains(fragment):
			return true
	return false


func pin(roll_value: int = 100) -> Dictionary:
	return {"roll": roll_value, "crit": false}


# --------------------------------------------------------------------------
# blocker A -- `flags` and `effectId` must survive make_move()
# --------------------------------------------------------------------------

func test_make_move_keeps_the_contact_flag() -> void:
	var tackle := Stats.make_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not readable")
		return
	is_true(Abilities.makes_contact(tackle), "tackle makes contact")
	is_true(Abilities.move_has_flag(tackle, "protect"), "tackle is affected by Protect")
	var water_gun := Stats.make_move("water-gun")
	is_false(Abilities.makes_contact(water_gun), "water-gun makes no contact")
	# effectId comes along for the ride; the multi-hit abilities branch on it.
	eq(int(tackle.get("effectId", -1)), 1, "tackle effectId")


# --------------------------------------------------------------------------
# aura-guard
# --------------------------------------------------------------------------

func test_aura_guard_halves_a_contact_move() -> void:
	var atk := attacker_with("")
	var plain := defender_with("")
	var guard := defender_with("aura-guard")
	var tackle := Stats.make_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not readable")
		return

	# L50, power 40, A 100, D 100: level_factor 22,
	# base = floor(floor(22*40*100/100)/50)+2 = floor(880/50)+2 = 19.
	# roll 100, no crit, no STAB (Water attacker, Normal move), Normal vs Water 1.0.
	var normal_hit := Damage.compute(atk, plain, tackle, pin())
	eq(int(normal_hit["damage"]), 19, "unguarded tackle")

	# Aura Guard is a FINAL damage multiplier: floor(19 * 0.5) = 9.
	var guarded := Damage.compute(atk, guard, tackle, pin())
	eq(int(guarded["damage"]), 9, "aura-guard tackle")
	almost(float(guarded["damageMult"]), 0.5, 0.0001, "damage_mult folded")


func test_aura_guard_ignores_a_non_contact_move() -> void:
	var atk := attacker_with("")
	var aura_sphere := Stats.make_move("aura-sphere")
	if aura_sphere.is_empty():
		pending("data/moves.json not readable")
		return
	# power 80 special, A 100, D 100: base = floor(floor(22*80*100/100)/50)+2 = 37.
	var plain := int(Damage.compute(atk, defender_with(""), aura_sphere, pin())["damage"])
	var guarded := int(Damage.compute(atk, defender_with("aura-guard"), aura_sphere, pin())["damage"])
	eq(plain, 37, "unguarded aura-sphere")
	eq(guarded, 37, "aura-guard does nothing to a non-contact move")


func test_aura_guard_protects_only_its_bearer() -> void:
	var tackle := Stats.make_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not readable")
		return
	# The BEARER IS THE ATTACKER here: its own contact move is not weakened.
	var bearer_attacking := int(Damage.compute(
		attacker_with("aura-guard"), defender_with(""), tackle, pin())["damage"])
	eq(bearer_attacking, 19, "aura-guard on the attacker changes nothing")


func test_aura_guard_halves_damage_in_a_real_battle() -> void:
	if Stats.make_move("tackle").is_empty():
		pending("data/moves.json not readable")
		return
	var plain := one_turn(attacker_with("", ["tackle"]), defender_with(""), 99)
	var guarded := one_turn(attacker_with("", ["tackle"]), defender_with("aura-guard"), 99)
	var plain_lost := 300 - int((plain["engine"].active(1) as Dictionary)["hp"])
	var guard_lost := 300 - int((guarded["engine"].active(1) as Dictionary)["hp"])
	is_true(plain_lost > 0, "the unguarded hit landed (%d)" % plain_lost)
	eq(guard_lost, floori(float(plain_lost) * 0.5), "aura-guard halved the real hit")


# --------------------------------------------------------------------------
# unseen-fist
# --------------------------------------------------------------------------

func test_protect_blocks_an_ordinary_contact_move() -> void:
	if Stats.make_move("shadow-punch").is_empty():
		pending("data/moves.json not readable")
		return
	var foe := defender_with("")
	(foe["volatile"] as Dictionary)["protect"] = true
	var r := one_turn(attacker_with("", ["shadow-punch"]), foe)
	eq(int(foe["hp"]), 300, "protected: no damage")
	is_true(log_has(r["log"], "protected itself"), "the block was announced")


func test_unseen_fist_strikes_through_protect() -> void:
	if Stats.make_move("shadow-punch").is_empty():
		pending("data/moves.json not readable")
		return
	var foe := defender_with("")
	(foe["volatile"] as Dictionary)["protect"] = true
	var r := one_turn(attacker_with("unseen-fist", ["shadow-punch"]), foe)
	is_true(int(foe["hp"]) < 300, "unseen-fist pierced Protect (hp %d)" % int(foe["hp"]))
	is_false(log_has(r["log"], "protected itself"), "no block message")


func test_unseen_fist_pierces_at_full_damage() -> void:
	if Stats.make_move("shadow-punch").is_empty():
		pending("data/moves.json not readable")
		return
	# Shadow Punch has accuracy null (never misses), so the two runs consume the
	# same RNG in the same order and the damage rolls are identical.
	var unprotected := defender_with("")
	one_turn(attacker_with("unseen-fist", ["shadow-punch"]), unprotected, 7)
	var protected := defender_with("")
	(protected["volatile"] as Dictionary)["protect"] = true
	one_turn(attacker_with("unseen-fist", ["shadow-punch"]), protected, 7)

	var open_dmg := 300 - int(unprotected["hp"])
	var pierced := 300 - int(protected["hp"])
	is_true(open_dmg > 0, "baseline hit landed (%d)" % open_dmg)
	eq(pierced, open_dmg, "mainline Unseen Fist pierces at FULL damage")


func test_unseen_fist_is_contact_only() -> void:
	if Stats.make_move("earthquake").is_empty():
		pending("data/moves.json not readable")
		return
	# Earthquake is affected by Protect and makes NO contact, so Mega Golurk's own
	# best move is still blocked.
	var foe := defender_with("")
	(foe["volatile"] as Dictionary)["protect"] = true
	var r := one_turn(attacker_with("unseen-fist", ["earthquake"]), foe)
	eq(int(foe["hp"]), 300, "non-contact move still blocked")
	is_true(log_has(r["log"], "protected itself"), "the block was announced")


# --------------------------------------------------------------------------
# piercing-drill
# --------------------------------------------------------------------------

func test_piercing_drill_pierces_for_a_quarter() -> void:
	if Stats.make_move("shadow-punch").is_empty():
		pending("data/moves.json not readable")
		return
	var unprotected := defender_with("")
	one_turn(attacker_with("piercing-drill", ["shadow-punch"]), unprotected, 7)
	var protected := defender_with("")
	(protected["volatile"] as Dictionary)["protect"] = true
	one_turn(attacker_with("piercing-drill", ["shadow-punch"]), protected, 7)

	var open_dmg := 300 - int(unprotected["hp"])
	var pierced := 300 - int(protected["hp"])
	is_true(open_dmg > 0, "baseline hit landed (%d)" % open_dmg)
	is_true(pierced > 0, "the pierced hit still did damage (%d)" % pierced)
	# damage_mult is applied after burn and before maxi(1, dmg).
	eq(pierced, maxi(1, floori(float(open_dmg) * 0.25)), "pierced for a quarter")


func test_piercing_drill_does_not_tax_an_unprotected_target() -> void:
	if Stats.make_move("shadow-punch").is_empty():
		pending("data/moves.json not readable")
		return
	# The 0.25 must apply ONLY when protection was actually pierced. Wiring it
	# anywhere else would be a permanent 75% damage penalty on a 165-Attack Mega.
	var with_ability := defender_with("")
	one_turn(attacker_with("piercing-drill", ["shadow-punch"]), with_ability, 7)
	var without := defender_with("")
	one_turn(attacker_with("", ["shadow-punch"]), without, 7)
	eq(300 - int(with_ability["hp"]), 300 - int(without["hp"]),
		"unprotected target takes full damage")


func test_piercing_drill_is_contact_only() -> void:
	if Stats.make_move("earthquake").is_empty():
		pending("data/moves.json not readable")
		return
	var foe := defender_with("")
	(foe["volatile"] as Dictionary)["protect"] = true
	var r := one_turn(attacker_with("piercing-drill", ["earthquake"]), foe)
	eq(int(foe["hp"]), 300, "Earthquake is still blocked")
	is_true(log_has(r["log"], "protected itself"), "the block was announced")


# --------------------------------------------------------------------------
# spicy-spray
# --------------------------------------------------------------------------

func test_spicy_spray_burns_on_a_non_contact_move() -> void:
	if Stats.make_move("water-gun").is_empty():
		pending("data/moves.json not readable")
		return
	# THE WHOLE POINT: Water Gun makes no contact. A Flame-Body-shaped
	# (contact-only) implementation would not burn here.
	var atk := attacker_with("", ["water-gun"])
	var r := one_turn(atk, defender_with("spicy-spray", 300, ["grass", "fire"]))
	eq(String(atk["status"]), Status.BURN, "the attacker was burned")
	is_true(log_has(r["log"], "was burned!"), "the burn was announced")


func test_spicy_spray_burns_on_a_contact_move_too() -> void:
	if Stats.make_move("tackle").is_empty():
		pending("data/moves.json not readable")
		return
	var atk := attacker_with("", ["tackle"])
	one_turn(atk, defender_with("spicy-spray", 300, ["grass", "fire"]))
	eq(String(atk["status"]), Status.BURN, "contact move burns as well")


func test_without_spicy_spray_nothing_burns() -> void:
	if Stats.make_move("water-gun").is_empty():
		pending("data/moves.json not readable")
		return
	var atk := attacker_with("", ["water-gun"])
	var r := one_turn(atk, defender_with("", 300, ["grass", "fire"]))
	eq(String(atk["status"]), "", "no ability, no burn")
	is_false(log_has(r["log"], "was burned!"), "no burn message")


func test_spicy_spray_burns_from_beyond_the_grave() -> void:
	if Stats.make_move("water-gun").is_empty():
		pending("data/moves.json not readable")
		return
	# 1 HP: the bearer faints from the very hit that triggers the ability, and the
	# burn must still land -- the hook runs before the faint break and before
	# _check_faints() reverts the Mega.
	var atk := attacker_with("", ["water-gun"])
	var dying := defender_with("spicy-spray", 300, ["grass", "fire"])
	dying["hp"] = 1
	var r := one_turn(atk, dying)
	is_true(Stats.is_fainted(dying), "the bearer fainted")
	eq(String(atk["status"]), Status.BURN, "the burn landed anyway")
	is_true(log_has(r["log"], "fainted!"), "the faint was announced")


func test_spicy_spray_cannot_burn_a_fire_type() -> void:
	if Stats.make_move("tackle").is_empty():
		pending("data/moves.json not readable")
		return
	# status.gd already refuses Fire-types (IMMUNE_TYPES[BURN] == ["fire"]); the
	# ability must not re-implement the check, and must not leak its refusal
	# messages into the log.
	var atk := fixture("TORCH", ["fire"], "",
		{"hp": 300, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 200}, ["tackle"])
	var r := one_turn(atk, defender_with("spicy-spray", 300, ["grass", "fire"]))
	eq(String(atk["status"]), "", "a Fire-type attacker is not burned")
	is_false(log_has(r["log"], "was burned!"), "no burn message")
	is_false(log_has(r["log"], "It doesn't affect TORCH"), "no leaked refusal message")


func test_spicy_spray_does_not_burn_twice() -> void:
	if Stats.make_move("tackle").is_empty():
		pending("data/moves.json not readable")
		return
	# Second hit: the attacker already carries burn, so Status.apply refuses with
	# reason "already" and the ability stays silent rather than logging
	# "ATTACKER is already burn!" every turn.
	var atk := attacker_with("", ["tackle"])
	var foe := defender_with("spicy-spray", 300, ["grass", "fire"])
	var b := BattleEngine.new()
	b.start({
		"kind": "trainer", "party": [atk], "opponent": [foe], "cap": 100, "seed": 11,
		"trainer": {"name": "Tester", "ai": 1, "keyStone": false, "prizeMoney": 0},
	})
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	b.submit_action(0, {"kind": "move", "move_index": 0})
	var r2 := b.resolve_turn()
	eq(String(atk["status"]), Status.BURN, "still burned")
	is_false(log_has(r2["log"], "is already"), "no 'already burned' noise on turn 2")


# --------------------------------------------------------------------------
# registry hygiene -- an unimplemented ability must cost nothing and do nothing
# --------------------------------------------------------------------------

func test_registry_is_a_no_op_for_unimplemented_abilities() -> void:
	is_true(Abilities.of("stench") == null, "stench has no implementation")
	is_true(Abilities.of("") == null, "the empty slug resolves to null")
	is_false(Abilities.has_impl("stench"), "has_impl is false for stench")

	var mon := fixture("STINKER", ["normal"], "stench",
		{"hp": 100, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50})
	var foe := fixture("FOE", ["normal"], "stench",
		{"hp": 100, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50})
	var move := Stats.make_move("tackle")
	if move.is_empty():
		pending("data/moves.json not readable")
		return

	var mods := Abilities.damage_mods(mon, foe, move, {})
	almost(float(mods["atk_mult"]), 1.0, 0.0001, "neutral atk_mult")
	almost(float(mods["power_mult"]), 1.0, 0.0001, "neutral power_mult")
	almost(float(mods["damage_mult"]), 1.0, 0.0001, "neutral damage_mult")
	eq(Abilities.protect_check(mon, foe, move), {}, "neutral protect_check")
	eq(Abilities.hit_taken(mon, foe, move, {"damage": 10}), {}, "neutral hit_taken")
	eq(Abilities.weather_view(mon, "rain"), "rain", "weather_view passes through")
	eq(Abilities.escape_block(mon, foe, "switch"), {}, "neutral escape_block")
	is_false(Abilities.ignores_redirection(mon), "neutral ignores_redirection")


func test_a_fainted_bearer_has_no_ability() -> void:
	var dead := defender_with("aura-guard")
	dead["hp"] = 0
	is_true(Abilities.for_mon(dead) == null, "a fainted mon's ability is inert")


func test_damage_is_unchanged_when_no_ability_overrides_a_hook() -> void:
	# The property the other 2974 checks depend on: with no implemented ability in
	# play, every multiplier is exactly 1.0 and the numbers are the old numbers.
	var tackle := Stats.make_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not readable")
		return
	var hit := Damage.compute(attacker_with("stench"), defender_with("stench"), tackle, pin())
	eq(int(hit["damage"]), 19, "unmodified damage")
	almost(float(hit["damageMult"]), 1.0, 0.0001, "no damage multiplier")
