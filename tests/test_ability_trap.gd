extends "res://tests/framework/test_case.gd"
## The "trap" ability group: shadow-tag, parental-bond, skill-link. Run:
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=ability_trap
##
## Every assertion here is on a BATTLE OUTCOME -- a switch that is refused, a
## second damage event, a hit count in the log, a hand-computed damage number --
## never on "the hook was called".
##
## Moves come from the committed data/moves.json so the tests exercise the real
## `effectId` / `flags` rows the abilities branch on; base stats are pinned inline
## so the arithmetic does not depend on the species table.

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")
const Damage := preload("res://src/battle/damage.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")
const MultiHit := preload("res://src/battle/multi_hit.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")

const FAST: Dictionary = {"hp": 200, "atk": 120, "def": 100, "spa": 100, "spd": 100, "spe": 120}
const SLOW: Dictionary = {"hp": 200, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 40}
const WALL: Dictionary = {"hp": 400, "atk": 60, "def": 100, "spa": 60, "spd": 100, "spe": 40}


func before_each() -> void:
	Deps.clear_overrides()


func after_each() -> void:
	Deps.clear_overrides()


# --------------------------------------------------------------------------
# fixtures
# --------------------------------------------------------------------------

## A Pokemon with pinned battle stats. `moves` are slugs from data/moves.json.
func fixture(mon_name: String, types: Array, level: int, stats: Dictionary,
		moves: Array = [], opts: Dictionary = {}) -> Dictionary:
	var species_data: Dictionary = {
		"name": mon_name, "types": types,
		"stats": {"hp": 50, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50},
		"abilities": [String(opts.get("ability", ""))],
		"baseExp": 64, "growthRate": "medium-fast",
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


## A move dictionary straight out of data/moves.json, so `effectId` and `flags`
## are the real rows. Returns {} when the data has not been generated.
func real_move(slug: String) -> Dictionary:
	return Stats.make_move(slug)


## A status move that does nothing at all: the sparring partner's action, so the
## only HP movement in a test is the one being measured.
func idle_move() -> Dictionary:
	return {
		"id": 0, "name": "Idle", "slug": "idle", "type": "normal", "category": "status",
		"power": 0, "accuracy": 100, "pp": 30, "maxPp": 30, "priority": 0,
		"effect": "", "effectChance": 0, "flags": PackedStringArray(), "effectId": 0,
	}


func engine_for(party: Array, opponent: Array, seed_value: int,
		battle_kind: String = "trainer") -> RefCounted:
	var b := BattleEngine.new()
	b.start({
		"kind": battle_kind, "party": party, "opponent": opponent, "cap": 100,
		"seed": seed_value,
		"trainer": {"name": "Fantina", "ai": 6, "keyStone": false, "prizeMoney": 0},
	})
	return b


func log_has(b: RefCounted, needle: String) -> bool:
	for line: String in b.battle_log:
		if line.contains(needle):
			return true
	return false


func log_count(b: RefCounted, needle: String) -> int:
	var n := 0
	for line: String in b.battle_log:
		if line.contains(needle):
			n += 1
	return n


# ==========================================================================
# shadow-tag -- the Fantina ability
# ==========================================================================

## The headline case: Fantina's Mega Gengar is on the field, the player tries to
## pull its Normal-type out, and the switch is REFUSED.
func test_shadow_tag_refuses_the_player_s_switch() -> void:
	var lead := fixture("LEAD", ["normal"], 50, FAST, ["tackle"])
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var gengar := fixture("MEGA GENGAR", ["ghost", "poison"], 50, SLOW, ["shadow-ball"],
		{"ability": "shadow-tag"})
	var b := engine_for([lead, bench], [gengar], 1001)

	is_false(b.submit_action(0, {"kind": "switch", "index": 1}),
		"a trapped switch is refused")
	is_true(log_has(b, "LEAD can't escape!"), "the log names the trap")
	# And the battle is NOT stuck: the turn still resolves and the lead is still out.
	b.resolve_turn()
	eq(Stats.display_name(b.active(0)), "LEAD", "the lead never left")


## Gen 6+: a Ghost-type walks out of Shadow Tag. Deliberate -- a Gen 4/5 reading
## would trap the player's own Ghost answers to a Ghost/Poison Mega Gengar.
func test_a_ghost_type_escapes_shadow_tag() -> void:
	var ghost := fixture("GASTLY", ["ghost", "poison"], 50, FAST, ["tackle"])
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var gengar := fixture("MEGA GENGAR", ["ghost", "poison"], 50, SLOW, ["shadow-ball"],
		{"ability": "shadow-tag"})
	var b := engine_for([ghost, bench], [gengar], 1002)

	is_true(b.submit_action(0, {"kind": "switch", "index": 1}), "a Ghost-type may leave")
	is_false(log_has(b, "can't escape!"), "no trap message")
	b.resolve_turn()
	eq(Stats.display_name(b.active(0)), "BENCH", "the switch actually happened")


## A Shed Shell buys a SWITCH. It does not buy an escape from a wild battle.
func test_shed_shell_switches_out_but_still_cannot_run() -> void:
	var holder := fixture("HOLDER", ["normal"], 50, FAST, ["tackle"], {"item": "shed-shell"})
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var wob := fixture("WOBBUFFET", ["psychic"], 50, SLOW, ["tackle"], {"ability": "shadow-tag"})
	var b := engine_for([holder, bench], [wob], 1003)
	is_true(b.submit_action(0, {"kind": "switch", "index": 1}), "Shed Shell permits the switch")

	var wild := engine_for([holder.duplicate(true), bench.duplicate(true)],
		[wob.duplicate(true)], 1004, "wild")
	wild.submit_action(0, {"kind": "run"})
	wild.resolve_turn()
	is_true(log_has(wild, "HOLDER can't escape!"), "Shed Shell does not permit running")
	is_false(bool(wild.over), "the battle did not end in an escape")
	neq(wild.outcome, "run", "no escape")


## Two Shadow Tags cancel.
func test_shadow_tag_does_not_trap_another_shadow_tag() -> void:
	var mine := fixture("WOBBUFFET", ["psychic"], 50, FAST, ["tackle"], {"ability": "shadow-tag"})
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var theirs := fixture("MEGA GENGAR", ["ghost", "poison"], 50, SLOW, ["shadow-ball"],
		{"ability": "shadow-tag"})
	var b := engine_for([mine, bench], [theirs], 1005)
	is_true(b.submit_action(0, {"kind": "switch", "index": 1}), "mutual immunity")


## Checked LIVE, never latched: a Gengar that died this turn traps nothing.
func test_a_fainted_trapper_traps_nothing() -> void:
	var lead := fixture("LEAD", ["normal"], 50, FAST, ["tackle"])
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var gengar := fixture("MEGA GENGAR", ["ghost", "poison"], 50, SLOW, ["shadow-ball"],
		{"ability": "shadow-tag"})
	var b := engine_for([lead, bench], [gengar], 1006)
	is_false(b.submit_action(0, {"kind": "switch", "index": 1}), "trapped while it lives")
	gengar["hp"] = 0
	is_true(b.submit_action(0, {"kind": "switch", "index": 1}), "free once it faints")


## THE DEADLOCK GUARD. A forced replacement after a faint is never blocked; if it
## were, `awaiting_switch` would have no legal action and the battle would hang.
func test_a_forced_replacement_after_a_faint_is_never_blocked() -> void:
	var lead := fixture("LEAD", ["normal"], 50, FAST, ["tackle"], {"hp": 1})
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var gengar := fixture("MEGA GENGAR", ["ghost", "poison"], 50, SLOW, ["shadow-ball"],
		{"ability": "shadow-tag"})
	var b := engine_for([lead, bench], [gengar], 1007)
	lead["hp"] = 0
	b.resolve_turn()
	eq(int(b.awaiting_switch), 0, "the player owes a replacement")
	is_true(b.switch_in(0, 1), "the forced replacement is allowed")
	eq(int(b.awaiting_switch), -1, "no deadlock")
	eq(Stats.display_name(b.active(0)), "BENCH", "the replacement came in")


## The AI must be trapped too: _execute() calls _switch_in() directly and never
## re-validates, so the gate has to be in auto_action's `can_switch`.
##
## The scenario is built so the AI genuinely WANTS to switch -- its only move is
## Normal and the player's Gengar is immune, while its bench has Shadow Ball --
## and the second half of the test proves it by removing the ability.
func test_the_ai_will_not_switch_out_while_trapped() -> void:
	var gengar := fixture("MEGA GENGAR", ["ghost", "poison"], 50, FAST, ["shadow-ball"],
		{"ability": "shadow-tag"})
	var ai_lead := fixture("AI LEAD", ["normal"], 50, SLOW, ["tackle"])
	var ai_bench := fixture("AI BENCH", ["dark"], 50, SLOW, ["shadow-ball"])
	var b := engine_for([gengar], [ai_lead, ai_bench], 1008)

	var trapped: Dictionary = b.auto_action(1)
	neq(String(trapped.get("kind", "")), "switch", "a trapped AI does not switch")

	# Prove the scenario would otherwise switch.
	gengar["ability"] = ""
	var free_choice: Dictionary = b.auto_action(1)
	eq(String(free_choice.get("kind", "")), "switch", "untrapped, the same AI switches")


## An ability with no implementation costs nothing and blocks nothing.
func test_an_unimplemented_ability_traps_nobody() -> void:
	var lead := fixture("LEAD", ["normal"], 50, FAST, ["tackle"])
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var stinker := fixture("STINKER", ["normal"], 50, SLOW, ["tackle"], {"ability": "stench"})
	var b := engine_for([lead, bench], [stinker], 1009)
	is_true(b.submit_action(0, {"kind": "switch", "index": 1}), "stench is not a trap")
	is_true(Abilities.of("stench") == null, "stench has no implementation")
	is_true(Abilities.of("shadow-tag") != null, "shadow-tag does")


# ==========================================================================
# parental-bond
# ==========================================================================

## One turn of `attacker_moves[0]`, with the sparring partner doing nothing.
## Returns {b, dealt, attacker_lost}.
func one_attack(ability: String, move_slug: String, seed_value: int,
		target_hp: int = 400) -> Dictionary:
	var move := real_move(move_slug)
	if move.is_empty():
		return {}
	var attacker := fixture("KANGA", ["normal"], 50, FAST, [], {"ability": ability})
	(attacker["moves"] as Array).append(move)
	var target := fixture("TARGET", ["water"], 50, WALL, [], {"hp": target_hp})
	target["maxHp"] = int(WALL["hp"])
	(target["moves"] as Array).append(idle_move())

	var hp_before := int(target["hp"])
	var atk_before := int(attacker["hp"])
	var b := engine_for([attacker], [target], seed_value)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	return {
		"b": b,
		"dealt": hp_before - int(target["hp"]),
		"attacker_lost": atk_before - int(attacker["hp"]),
	}


## THE OUTCOME: two damage events instead of one, and the extra one is small.
func test_parental_bond_produces_a_second_smaller_hit() -> void:
	var plain := one_attack("", "tackle", 2001)
	var bond := one_attack("parental-bond", "tackle", 2001)
	if plain.is_empty() or bond.is_empty():
		pending("data/moves.json has no tackle row")
		return

	is_false(log_has(plain["b"], "Hit "), "one hit without the ability")
	is_true(log_has(bond["b"], "Hit 2 time(s)!"), "two hits with it")

	var first := int(plain["dealt"])
	var total := int(bond["dealt"])
	# Hit 1 is byte-identical (same seed, same rng draws up to that point), so the
	# difference IS hit 2.
	var second := total - first
	is_true(second >= 1, "the second hit landed: %d" % second)
	# 0.25x of a full hit, before the 85..100 spread: comfortably under a third.
	is_true(second <= floori(float(first) * 0.34),
		"the second hit is a quarter-ish, not a full hit (%d vs %d)" % [second, first])


## The 0.25 is a FINAL DAMAGE multiplier. Hand-computed, level 50, Atk 120 vs Def
## 100, 40-power Tackle, STAB 1.5, roll 100, no crit:
##   levelFactor = floor(2*50/5) + 2            = 22
##   inner       = floor(22 * 40 * 120 / 100)   = 1056
##   base        = floor(1056 / 50) + 2         = 23
##   roll 100    = 23 ; STAB 1.5 -> floor(34.5) = 34
##   hit 2       = floor(34 * 0.25)             = 8
func test_the_second_hit_multiplier_is_exactly_a_quarter_of_the_damage() -> void:
	var move := real_move("tackle")
	if move.is_empty():
		pending("data/moves.json has no tackle row")
		return
	var attacker := fixture("KANGA", ["normal"], 50, FAST, [], {"ability": "parental-bond"})
	var target := fixture("TARGET", ["water"], 50, WALL)

	var one := Damage.compute(attacker, target, move, {"roll": 100, "crit": false})
	var two := Damage.compute(attacker, target, move, {
		"roll": 100, "crit": false, "hit_index": 1, "hit_plan_by": "parental-bond",
	})
	eq(int(one["damage"]), 34, "hit 1")
	eq(int(two["damage"]), 8, "hit 2 = floor(34 * 0.25)")

	# The same ctx WITHOUT the plan tag must not be quartered -- that is what keeps
	# the multiplier off hit 2 of a naturally multi-hit move.
	var untagged := Damage.compute(attacker, target, move, {
		"roll": 100, "crit": false, "hit_index": 1, "hit_plan_by": "",
	})
	eq(int(untagged["damage"]), 34, "no plan tag, no quarter")


## ONE accuracy check for the pair, not one per hit.
func test_parental_bond_rolls_accuracy_once_for_the_pair() -> void:
	var move := real_move("tackle")
	if move.is_empty():
		pending("data/moves.json has no tackle row")
		return
	var kanga := fixture("KANGA", ["normal"], 50, FAST, [], {"ability": "parental-bond"})
	var plan := MultiHit.plan(kanga, move, null)
	eq(int(plan["hits"]), 2, "two hits")
	is_true(bool(plan["single_accuracy"]), "one accuracy roll covers both")
	eq(String(plan["by"]), "parental-bond", "the plan is tagged with its author")


## Bullet Seed does NOT become ten hits, and hit 2 of it is never quartered.
func test_parental_bond_does_not_stack_with_a_multi_hit_move() -> void:
	var move := real_move("bullet-seed")
	if move.is_empty():
		pending("data/moves.json has no bullet-seed row")
		return
	var kanga := fixture("KANGA", ["normal"], 50, FAST, [], {"ability": "parental-bond"})
	var rng := RandomNumberGenerator.new()
	for s in 25:
		rng.seed = 7000 + s
		var plan := MultiHit.plan(kanga, move, rng)
		var hits := int(plan["hits"])
		is_true(hits >= 2 and hits <= 5, "bullet seed stays 2-5, got %d" % hits)
		eq(String(plan["by"]), "", "the ability did not author this plan")


## Status moves, zero-power moves and charging moves are excluded.
func test_parental_bond_excludes_status_and_charging_moves() -> void:
	var kanga := fixture("KANGA", ["normal"], 50, FAST, [], {"ability": "parental-bond"})
	for slug: String in ["growl", "solar-beam", "explosion", "endeavor", "fissure"]:
		var move := real_move(slug)
		if move.is_empty():
			pending("data/moves.json has no %s row" % slug)
			continue
		eq(int(MultiHit.plan(kanga, move, null)["hits"]), 1, "%s hits once" % slug)


## Stop on hit 1 when hit 1 kills: no second hit, no second damage event.
func test_a_kill_on_hit_one_ends_the_pair() -> void:
	var bond := one_attack("parental-bond", "tackle", 2002, 5)
	if bond.is_empty():
		pending("data/moves.json has no tackle row")
		return
	is_false(log_has(bond["b"], "Hit 2 time(s)!"), "the pair stopped at the KO")
	is_true(log_has(bond["b"], "TARGET fainted!"), "it did faint")


## RECOIL ONCE, FROM THE SUM. Charging it inside the per-hit block would bill a
## Parental Bond pair twice, each time at the wrong size.
func test_recoil_is_charged_once_from_the_summed_damage() -> void:
	var bond := one_attack("parental-bond", "double-edge", 2003)
	if bond.is_empty():
		pending("data/moves.json has no double-edge row")
		return
	var b: RefCounted = bond["b"]
	is_true(log_has(b, "Hit 2 time(s)!"), "the pair landed")
	eq(log_count(b, "is damaged by recoil!"), 1, "recoil is announced once")
	# Double-Edge is 1/3 recoil in data/moves.json's effect text.
	var expected := maxi(1, floori(float(int(bond["dealt"])) / 3.0))
	eq(int(bond["attacker_lost"]), expected,
		"recoil = floor(total / 3) of %d" % int(bond["dealt"]))


# ==========================================================================
# skill-link
# ==========================================================================

## A 2-5 move becomes exactly 5, every time.
func test_skill_link_maximises_a_two_to_five_move() -> void:
	var move := real_move("icicle-spear")
	if move.is_empty():
		pending("data/moves.json has no icicle-spear row")
		return
	var cloyster := fixture("CLOYSTER", ["water", "ice"], 50, FAST, [], {"ability": "skill-link"})
	var plain := fixture("SHELLDER", ["water"], 50, FAST, [])
	var rng := RandomNumberGenerator.new()
	var saw_fewer := false
	for s in 40:
		rng.seed = 8000 + s
		eq(int(MultiHit.plan(cloyster, move, rng)["hits"]), 5, "skill link seed %d" % s)
		rng.seed = 8000 + s
		if int(MultiHit.plan(plain, move, rng)["hits"]) < 5:
			saw_fewer = true
	is_true(saw_fewer, "without the ability the count really does vary")


## FIXED-count moves are untouched: branching on the effect STRING instead of
## effectId is exactly how this goes wrong.
func test_skill_link_leaves_fixed_count_moves_alone() -> void:
	var cloyster := fixture("CLOYSTER", ["water", "ice"], 50, FAST, [], {"ability": "skill-link"})
	var fixed: Dictionary = {"gear-grind": 2, "twineedle": 2, "dragon-darts": 2, "surging-strikes": 3}
	for slug: String in fixed.keys():
		var move := real_move(slug)
		if move.is_empty():
			pending("data/moves.json has no %s row" % slug)
			continue
		eq(int(MultiHit.plan(cloyster, move, null)["hits"]), int(fixed[slug]),
			"%s keeps its fixed count" % slug)


## Triple Kick: 3 hits AND per-hit accuracy removed. The second half is the one
## people skip, so it gets a battle-level test below as well.
func test_skill_link_fixes_triple_kick_at_three_hits() -> void:
	var move := real_move("triple-kick")
	if move.is_empty():
		pending("data/moves.json has no triple-kick row")
		return
	var linked := fixture("MEGA HERACROSS", ["bug", "fighting"], 50, FAST, [],
		{"ability": "skill-link"})
	var plain := fixture("HITMONTOP", ["fighting"], 50, FAST, [])

	var a := MultiHit.plan(linked, move, null)
	eq(int(a["hits"]), 3, "three kicks")
	is_true(bool(a["single_accuracy"]), "per-hit accuracy removed")

	var c := MultiHit.plan(plain, move, null)
	eq(int(c["hits"]), 3, "three kicks naturally too")
	is_false(bool(c["single_accuracy"]), "but each kick rolls its own accuracy")

	# The escalating 10/20/30 ramp survives -- Skill Link guarantees the hits, it
	# does not flatten the power.
	eq(MultiHit.power_mult_for_hit(a, 0), 1.0, "kick 1")
	eq(MultiHit.power_mult_for_hit(a, 1), 2.0, "kick 2")
	eq(MultiHit.power_mult_for_hit(a, 2), 3.0, "kick 3")


## THE BATTLE-LEVEL PROOF of the per-hit accuracy half: with the accuracy dropped
## to 50, an unlinked Triple Kick often lands 1 or 2 kicks. With Skill Link, any
## turn that connects at all lands all three.
func test_skill_link_never_drops_a_kick() -> void:
	var move := real_move("triple-kick")
	if move.is_empty():
		pending("data/moves.json has no triple-kick row")
		return
	var shaky := move.duplicate(true)
	shaky["accuracy"] = 50

	var partial_without := 0
	var partial_with := 0
	var landed_three_with := 0
	for s in 40:
		for linked: bool in [false, true]:
			var user := fixture("KICKER", ["fighting"], 50, FAST, [],
				{"ability": "skill-link" if linked else ""})
			(user["moves"] as Array).append(shaky.duplicate(true))
			var target := fixture("TARGET", ["normal"], 50, WALL)
			(target["moves"] as Array).append(idle_move())
			var b := engine_for([user], [target], 9000 + s)
			b.submit_action(0, {"kind": "move", "move_index": 0})
			b.resolve_turn()
			var three := log_has(b, "Hit 3 time(s)!")
			var two := log_has(b, "Hit 2 time(s)!")
			# "landed exactly one kick" = it connected but never reported a count.
			var one := not three and not two and not log_has(b, "attack missed")
			if linked:
				if two or one:
					partial_with += 1
				if three:
					landed_three_with += 1
			elif two or one:
				partial_without += 1

	is_true(partial_without > 0,
		"unlinked Triple Kick drops kicks (%d partial turns of 40)" % partial_without)
	eq(partial_with, 0, "Skill Link never lands a partial Triple Kick")
	is_true(landed_three_with > 0,
		"and it did connect sometimes (%d full turns of 40)" % landed_three_with)


## The whole point of Mega Heracross: a five-hit Pin Missile, in a real turn.
func test_skill_link_five_hits_in_a_real_battle() -> void:
	var move := real_move("pin-missile")
	if move.is_empty():
		pending("data/moves.json has no pin-missile row")
		return
	var results: Dictionary = {}
	for linked: bool in [false, true]:
		var user := fixture("MEGA HERACROSS", ["bug", "fighting"], 50, FAST, [],
			{"ability": "skill-link" if linked else ""})
		(user["moves"] as Array).append(move.duplicate(true))
		var target := fixture("TARGET", ["normal"], 50, WALL)
		(target["moves"] as Array).append(idle_move())
		var before := int(target["hp"])
		var b := engine_for([user], [target], 9500)
		b.submit_action(0, {"kind": "move", "move_index": 0})
		b.resolve_turn()
		results[linked] = {"b": b, "dealt": before - int(target["hp"])}

	var linked_row: Dictionary = results[true]
	var plain_row: Dictionary = results[false]
	is_true(log_has(linked_row["b"], "Hit 5 time(s)!"), "five hits with Skill Link")
	is_false(log_has(plain_row["b"], "Hit 5 time(s)!"), "not five without it")
	is_true(int(linked_row["dealt"]) > int(plain_row["dealt"]),
		"and it hurts more: %d vs %d" % [int(linked_row["dealt"]), int(plain_row["dealt"])])


## Population Bomb: ten hits, and Skill Link is what guarantees them.
##
## It used to be invisible here -- veekun ships no `effect_id` for the move, so its
## data row read as ordinary single-hit damage. tools/build_species.py now assigns
## the project-local id 20001 (LOCAL_EFFECT_IDS) and both hit-count tables carry it.
## Ten attempts either way; without Skill Link each one rolls accuracy and the hit
## loop stops at the first miss, which is the whole difference the ability makes.
func test_population_bomb_hits_ten_times_with_skill_link() -> void:
	var move := real_move("population-bomb")
	if move.is_empty():
		pending("data/moves.json has no population-bomb row")
		return
	eq(int(move.get("effectId", 0)), 20001, "the data row carries the local effect id")

	var plain := fixture("MAUSHOLD", ["normal"], 50, FAST, [])
	var natural := MultiHit.plan(plain, move, null)
	eq(int(natural["hits"]), 10, "ten hits on its own")
	is_false(bool(natural["single_accuracy"]), "but every hit rolls accuracy")

	var cloyster := fixture("CLOYSTER", ["water", "ice"], 50, FAST, [], {"ability": "skill-link"})
	var linked := MultiHit.plan(cloyster, move, null)
	eq(int(linked["hits"]), 10, "still ten with Skill Link")
	is_true(bool(linked["single_accuracy"]), "and now one roll covers all ten")


# ==========================================================================
# regression: nothing changes for an ordinary move
# ==========================================================================

## A single-hit move with no ability involved still deals exactly one hit's worth
## of damage and prints no hit count.
func test_an_ordinary_move_is_unchanged() -> void:
	var move := real_move("tackle")
	if move.is_empty():
		pending("data/moves.json has no tackle row")
		return
	var attacker := fixture("PLAIN", ["normal"], 50, FAST, [])
	var target := fixture("TARGET", ["water"], 50, WALL)
	var plan := MultiHit.plan(attacker, move, null)
	eq(int(plan["hits"]), 1, "one hit")
	eq(String(plan["by"]), "", "no ability authored it")
	var hit := Damage.compute(attacker, target, move, {"roll": 100, "crit": false})
	eq(int(hit["damage"]), 34, "the hand-computed single hit is untouched")


# ==========================================================================
# the Fantina path: Mega Evolution is how the trap ARRIVES
# ==========================================================================

## END TO END, through mega.gd and data/megas.json: Gengar's base ability does not
## trap, Mega Evolution rewrites mon["ability"] to shadow-tag mid-battle, and the
## very next switch attempt is refused. This is gym 3.
func test_mega_evolution_brings_the_trap_with_it() -> void:
	var lead := fixture("LEAD", ["normal"], 50, SLOW, ["tackle"])
	var bench := fixture("BENCH", ["water"], 50, SLOW, ["tackle"])
	var gengar := fixture("GENGAR", ["ghost", "poison"], 50, FAST, ["shadow-ball"],
		{"species": 94, "item": "gengarite", "ability": "cursed-body"})

	var b := BattleEngine.new()
	b.start({
		"kind": "trainer", "party": [lead, bench], "opponent": [gengar], "cap": 100,
		"seed": 4242,
		"trainer": {"name": "Fantina", "ai": 6, "keyStone": true, "prizeMoney": 0},
	})
	if not b.can_mega_evolve(gengar, 1):
		pending("data/megas.json has no gengar-mega row reachable from this fixture")
		return

	# Before the Mega: base Gengar does not trap.
	is_true(b.submit_action(0, {"kind": "switch", "index": 1}), "base Gengar is no trap")

	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(String(gengar.get("ability", "")), "shadow-tag", "the Mega granted Shadow Tag")

	# And now the door is shut.
	is_false(b.submit_action(0, {"kind": "switch", "index": 1}),
		"Mega Gengar traps the player")
	is_true(log_has(b, "can't escape!"), "with the named message")
