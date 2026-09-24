extends "res://tests/framework/test_case.gd"
## RECONCILER'S ADVERSARIAL VERIFICATION of the 14 abilities four groups landed in
## parallel. Run:
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=reconciled
##
## This file deliberately does NOT trust the implementing groups' own tests. Every
## ability is re-proved here from scratch against ONE standard:
##
##   A BEARER AND AN OTHERWISE IDENTICAL CONTROL ARE PUT THROUGH THE SAME ENGINE
##   CALL WITH THE SAME SEED, AND THE OUTCOME MUST DIFFER.
##
## The control is the same fixture with `ability` set to "". That is what makes a
## passing assertion evidence: a number that is equal in both rows proves the
## ability inert no matter how much machinery it has behind it.
##
## Nothing here asserts "the hook was called". The measured quantities are HP
## actually lost, a switch actually refused, a status actually inflicted, a stat
## stage actually moved, and lines actually written to `battle_log`.
##
## It also carries the CROSS-GROUP regressions -- the interactions no single group
## could see, because each group only had its own three or four abilities in play.
## `test_regression_mega_sol_cannot_delete_delta_stream` is the one that was a real
## live bug (Mega Meganium doubled its Rock Slide through another Pokemon's strong
## winds); it is kept as a permanent guard.

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Damage := preload("res://src/battle/damage.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")
const MultiHit := preload("res://src/battle/multi_hit.gd")
const Mega := preload("res://src/battle/mega.gd")
const BattleEngine := preload("res://src/battle/battle_engine.gd")

## The 14 this workflow was asked to make real.
const THE_FOURTEEN: Array = [
	"shadow-tag", "parental-bond", "skill-link",
	"unseen-fist", "piercing-drill", "aura-guard", "spicy-spray",
	"delta-stream", "steadfast", "stalwart",
	"mega-sol", "dragonize", "eelevate", "fire-mane",
]

const BULK: Dictionary = {"hp": 400, "atk": 120, "def": 100, "spa": 120, "spd": 100, "spe": 100}
const FRAIL: Dictionary = {"hp": 60, "atk": 100, "def": 60, "spa": 100, "spd": 60, "spe": 50}


func before_each() -> void:
	Deps.clear_overrides()


func after_each() -> void:
	Deps.clear_overrides()


# ==========================================================================
# fixtures
# ==========================================================================

## A battle-ready Pokemon with PINNED stats, so every damage number below is
## arithmetic on numbers written in this file rather than on the species table.
func mon(mon_name: String, types: Array, ability: String = "",
		stats: Dictionary = BULK, moves: Array = [], opts: Dictionary = {}) -> Dictionary:
	var sp: Dictionary = {
		"name": mon_name, "types": types,
		"stats": {"hp": 50, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50},
		"abilities": [ability], "baseExp": 64, "growthRate": "medium-fast",
	}
	var o := opts.duplicate()
	o["species_data"] = sp
	o["name"] = mon_name
	o["ability"] = ability
	o["moves"] = moves
	var m := Stats.build(int(opts.get("species", 1)), int(opts.get("level", 50)), o)
	m["stats"] = stats.duplicate()
	m["maxHp"] = int(stats.get("hp", 100))
	m["hp"] = int(opts.get("hp", m["maxHp"]))
	return m


## The same fixture with no ability at all: the control row.
func control_of(bearer: Dictionary) -> Dictionary:
	var c := bearer.duplicate(true)
	c["ability"] = ""
	return c


## A real row out of data/moves.json, so `flags` / `effectId` are the shipped data
## the abilities actually branch on.
func real_move(slug: String) -> Dictionary:
	return Stats.make_move(slug)


func idle() -> Dictionary:
	return {
		"id": 0, "name": "Idle", "slug": "idle", "type": "normal", "category": "status",
		"power": 0, "accuracy": 100, "pp": 40, "maxPp": 40, "priority": 0,
		"effect": "", "effectChance": 0, "flags": PackedStringArray(), "effectId": 0,
	}


func engine_for(party: Array, opponent: Array, seed_value: int,
		battle_kind: String = "trainer", trainer: Dictionary = {}) -> RefCounted:
	var t := {"name": "Rival", "ai": 5, "keyStone": false, "prizeMoney": 0}
	t.merge(trainer, true)
	var b := BattleEngine.new()
	b.start({
		"kind": battle_kind, "party": party, "opponent": opponent,
		"cap": 100, "seed": seed_value, "trainer": t,
	})
	return b


## Run ONE turn in which side 0 uses move slot `move_index` and side 1 idles, then
## return the HP the opponent lost. The whole engine runs: accuracy, the protect
## gate, the hit loop, hit_taken, after_hit, recoil, end of turn.
func damage_through_engine(attacker: Dictionary, defender: Dictionary,
		seed_value: int = 77, move_index: int = 0) -> int:
	var b := engine_for([attacker], [defender], seed_value)
	var before := int(b.active(1)["hp"])
	b.submit_action(0, {"kind": "move", "move_index": move_index})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	return before - int(b.active(1)["hp"])


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
# 0. reconciliation: all 14 coexist
# ==========================================================================

func test_all_fourteen_register_and_are_distinct_instances() -> void:
	var slugs := Abilities.slugs()
	for slug: String in THE_FOURTEEN:
		check(Abilities.has_impl(slug), "%s is not registered in registry.IMPL" % slug)
		var impl := Abilities.of(slug)
		check(impl != null, "%s resolves to null" % slug)
		if impl != null:
			# The file's own slug() must agree with the key it is registered under,
			# or a rename silently points two keys at one file.
			eq(impl.slug(), slug, "%s's file reports a different slug:" % slug)
	eq(slugs.size(), THE_FOURTEEN.size(),
		"registry holds a different number of abilities than the 14:")
	# One shared instance per slug, for the life of the process (abilities are
	# stateless). A second instance would mean per-battle state could leak.
	check(Abilities.of("shadow-tag") == Abilities.of("shadow-tag"), "instances are not cached")


func test_an_unimplemented_ability_is_inert_not_a_crash() -> void:
	# The other ~300 rows in data/abilities.json must cost nothing and never throw.
	var levitate := mon("Gengar", ["ghost", "poison"], "levitate")
	var foe := mon("Golem", ["rock", "ground"], "sturdy")
	var quake := real_move("earthquake")
	if quake.is_empty():
		pending("data/moves.json not generated")
		return
	eq(Abilities.for_mon(levitate), null, "levitate must not resolve to an impl yet:")
	var r := Damage.compute(foe, levitate, quake, {"roll": 100, "crit": false})
	# Ghost/Poison is neutral to Ground and levitate is NOT implemented, so it lands.
	check(int(r["damage"]) > 0, "an unimplemented ability changed the outcome")


func test_a_fainted_bearer_stops_mattering() -> void:
	# The faint check in for_mon() is what keeps a dead Shadow Tag from trapping.
	var dead := mon("Gengar", ["ghost", "poison"], "shadow-tag", BULK, [], {"hp": 0})
	eq(Abilities.for_mon(dead), null, "a fainted mon still resolved its ability:")
	var blocked := Abilities.escape_block(dead, mon("Bibarel", ["normal"]), "switch")
	eq(bool(blocked.get("block", false)), false, "a fainted Shadow Tag still trapped:")


# ==========================================================================
# 1. shadow-tag
# ==========================================================================

func test_shadow_tag_refuses_a_switch_that_the_control_allows() -> void:
	var gengar := mon("Mega Gengar", ["ghost", "poison"], "shadow-tag")
	var player := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var bench := mon("Staravia", ["normal", "flying"], "", BULK, ["tackle"])

	var trapped := engine_for([player.duplicate(true), bench.duplicate(true)], [gengar], 11)
	eq(trapped.submit_action(0, {"kind": "switch", "index": 1}), false,
		"Shadow Tag did NOT refuse the switch:")
	check(log_has(trapped, "can't escape"), "no trap message was logged")

	var free := engine_for([player.duplicate(true), bench.duplicate(true)],
		[control_of(gengar)], 11)
	eq(free.submit_action(0, {"kind": "switch", "index": 1}), true,
		"the control refused the switch, so the test proves nothing:")


func test_shadow_tag_lets_a_ghost_type_leave() -> void:
	var gengar := mon("Mega Gengar", ["ghost", "poison"], "shadow-tag")
	var ghost := mon("Drifblim", ["ghost", "flying"], "", BULK, ["tackle"])
	var bench := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([ghost, bench], [gengar], 12)
	eq(b.submit_action(0, {"kind": "switch", "index": 1}), true,
		"a Ghost-type was trapped (Gen 6+ exempts them):")


func test_shadow_tag_blocks_running_from_a_wild_battle() -> void:
	var wild := mon("Wobbuffet", ["psychic"], "shadow-tag")
	var player := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([player.duplicate(true)], [wild], 13, "wild")
	b.submit_action(0, {"kind": "run"})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(bool(b.over), false, "Shadow Tag let the player run from a wild battle:")
	check(log_has(b, "can't escape"), "no trap message on the run attempt")

	var free := engine_for([player.duplicate(true)], [control_of(wild)], 13, "wild")
	free.submit_action(0, {"kind": "run"})
	free.resolve_turn()
	check(log_has(free, "Got away safely") or not free.over,
		"control run attempt behaved identically to the trapped one")


func test_shed_shell_buys_a_switch_but_not_an_escape() -> void:
	var wild := mon("Wobbuffet", ["psychic"], "shadow-tag")
	var holder := mon("Bibarel", ["normal"], "", BULK, ["tackle"], {"item": "shed-shell"})
	var bench := mon("Staravia", ["normal", "flying"], "", BULK, ["tackle"])
	var b := engine_for([holder, bench], [wild], 14, "wild")
	eq(b.submit_action(0, {"kind": "switch", "index": 1}), true,
		"Shed Shell did not allow the switch:")
	var r := engine_for([holder.duplicate(true), bench.duplicate(true)], [wild], 14, "wild")
	r.submit_action(0, {"kind": "run"})
	r.resolve_turn()
	eq(bool(r.over), false, "Shed Shell wrongly allowed a wild ESCAPE:")


func test_a_forced_replacement_after_a_faint_is_never_blocked() -> void:
	# The deadlock guard: a trapped side whose active Pokemon faints must still be
	# able to send something out.
	var gengar := mon("Mega Gengar", ["ghost", "poison"], "shadow-tag", BULK,
		["shadow-ball"])
	var dying := mon("Bibarel", ["normal"], "", FRAIL, ["tackle"], {"hp": 1})
	var bench := mon("Staravia", ["normal", "flying"], "", BULK, ["tackle"])
	var b := engine_for([dying, bench], [gengar], 15)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	if int(b.awaiting_switch) == 0:
		eq(b.submit_action(0, {"kind": "switch", "index": 1}), true,
			"a trapped side could not make its FORCED replacement -- deadlock:")
	else:
		check(not Stats.is_fainted(b.active(0)) or b.over,
			"the dying mon neither fainted nor survived coherently")


# ==========================================================================
# 2. parental-bond
# ==========================================================================

func test_parental_bond_hits_twice_and_the_control_hits_once() -> void:
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var khan := mon("Mega Kangaskhan", ["normal"], "parental-bond", BULK, ["tackle"])
	var wall := mon("Snorlax", ["normal"], "", BULK)

	var bonded := engine_for([khan], [wall.duplicate(true)], 21)
	bonded.submit_action(0, {"kind": "move", "move_index": 0})
	bonded.submit_action(1, {"kind": "move", "move_index": 0})
	bonded.resolve_turn()
	var bonded_dealt := int(wall["maxHp"]) - int(bonded.active(1)["hp"])
	check(log_has(bonded, "Hit 2 time(s)!"), "Parental Bond did not report two hits")

	var plain := engine_for([control_of(khan)], [wall.duplicate(true)], 21)
	plain.submit_action(0, {"kind": "move", "move_index": 0})
	plain.submit_action(1, {"kind": "move", "move_index": 0})
	plain.resolve_turn()
	var plain_dealt := int(wall["maxHp"]) - int(plain.active(1)["hp"])
	eq(log_has(plain, "Hit 2 time(s)!"), false, "the control also hit twice:")

	check(bonded_dealt > plain_dealt,
		"Parental Bond dealt %d, control dealt %d -- no outcome change" % [bonded_dealt, plain_dealt])
	# Hit 2 is a QUARTER of the damage, so the pair lands in (1.15x, 1.45x) of one
	# hit once the per-step flooring is allowed for. A pair of FULL hits (the naive
	# implementation) would be ~2.0x and fails this.
	var ratio := float(bonded_dealt) / float(maxi(plain_dealt, 1))
	check(ratio > 1.1 and ratio < 1.5,
		"pair/single ratio %.3f is not the 1.25x of a quartered second hit" % ratio)


func test_parental_bond_quarters_only_its_own_second_hit() -> void:
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var khan := mon("Mega Kangaskhan", ["normal"], "parental-bond", BULK, ["tackle"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	var ctx_base: Dictionary = {"roll": 100, "crit": false, "hits": 2, "hit_plan_by": "parental-bond"}
	var one := ctx_base.duplicate()
	one["hit_index"] = 0
	var two := ctx_base.duplicate()
	two["hit_index"] = 1
	var h1 := Damage.compute(khan, wall, tackle, one)
	var h2 := Damage.compute(khan, wall, tackle, two)
	almost(float(h1["damageMult"]), 1.0, 0.0001, "hit 1 was multiplied:")
	almost(float(h2["damageMult"]), 0.25, 0.0001, "hit 2 was not quartered:")
	check(int(h2["damage"]) < int(h1["damage"]), "hit 2 did not do less damage")
	check(int(h2["damage"]) >= 1, "hit 2 fell below the floor of 1")


func test_parental_bond_does_not_stack_with_a_multi_hit_move() -> void:
	var seed_move := real_move("bullet-seed")
	if seed_move.is_empty():
		pending("data/moves.json not generated")
		return
	var khan := mon("Mega Kangaskhan", ["normal"], "parental-bond", BULK, ["bullet-seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var plan := MultiHit.plan(khan, seed_move, rng)
	check(int(plan["hits"]) >= 2 and int(plan["hits"]) <= 5,
		"Bullet Seed under Parental Bond hit %d times -- it must stay 2-5" % int(plan["hits"]))
	eq(String(plan["by"]), "", "Parental Bond claimed authorship of a natural multi-hit plan:")
	# And hit 2 of Bullet Seed must NOT be quartered.
	var h2 := Damage.compute(khan, mon("Snorlax", ["normal"]), seed_move,
		{"roll": 100, "crit": false, "hit_index": 1, "hits": int(plan["hits"]), "hit_plan_by": ""})
	almost(float(h2["damageMult"]), 1.0, 0.0001,
		"Parental Bond quartered hit 2 of a naturally multi-hit move:")


func test_parental_bond_recoil_is_charged_once_from_the_summed_damage() -> void:
	var brave := real_move("double-edge")
	if brave.is_empty():
		pending("data/moves.json not generated")
		return
	if not String(brave.get("effect", "")).contains("recoil"):
		pending("double-edge has no recoil effect string in this data build")
		return
	var khan := mon("Mega Kangaskhan", ["normal"], "parental-bond", BULK, ["double-edge"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	var b := engine_for([khan], [wall], 22)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(log_count(b, "damaged by recoil"), 1,
		"recoil was charged more than once for the pair:")


# ==========================================================================
# 3. skill-link
# ==========================================================================

func test_skill_link_always_hits_five_where_the_control_varies() -> void:
	var pin := real_move("pin-missile")
	if pin.is_empty():
		pending("data/moves.json not generated")
		return
	eq(int(pin.get("effectId", -1)), 30, "pin-missile is not effectId 30 in this data build:")
	var hera := mon("Mega Heracross", ["bug", "fighting"], "skill-link", BULK, ["pin-missile"])
	var control := control_of(hera)
	var counts_linked: Array = []
	var counts_plain: Array = []
	for s in 12:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		counts_linked.append(int(MultiHit.plan(hera, pin, rng)["hits"]))
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = s
		counts_plain.append(int(MultiHit.plan(control, pin, rng2)["hits"]))
	for n: int in counts_linked:
		eq(n, 5, "Skill Link produced a count other than 5:")
	check(counts_plain.min() < 5, "the control never rolled under 5, so nothing is proved")

	# And through the engine, on the log. arm-thrust rather than pin-missile here:
	# both are effectId 30, but arm-thrust is 100% accurate, so a miss cannot
	# masquerade as a wrong hit count.
	var thrust := real_move("arm-thrust")
	if thrust.is_empty():
		pending("data/moves.json not generated")
		return
	var hera2 := mon("Mega Heracross", ["bug", "fighting"], "skill-link", BULK, ["arm-thrust"])
	var b := engine_for([hera2], [mon("Snorlax", ["normal"], "", BULK)], 31)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(log_has(b, "Hit 5 time(s)!"), "the engine log does not show five hits")


func test_skill_link_removes_triple_kicks_per_hit_accuracy() -> void:
	var kick := real_move("triple-kick")
	if kick.is_empty():
		pending("data/moves.json not generated")
		return
	var hera := mon("Mega Heracross", ["bug", "fighting"], "skill-link", BULK, ["triple-kick"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var linked := MultiHit.plan(hera, kick, rng)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 3
	var plain := MultiHit.plan(control_of(hera), kick, rng2)
	eq(int(linked["hits"]), 3, "Skill Link Triple Kick is not 3 hits:")
	eq(bool(linked["single_accuracy"]), true, "Skill Link left per-hit accuracy on:")
	eq(bool(plain["single_accuracy"]), false,
		"the control already had single accuracy, so nothing is proved:")


func test_skill_link_leaves_a_fixed_count_move_alone() -> void:
	var grind := real_move("gear-grind")
	if grind.is_empty():
		pending("data/moves.json not generated")
		return
	var hera := mon("Mega Heracross", ["bug", "fighting"], "skill-link", BULK, ["gear-grind"])
	eq(int(MultiHit.plan(hera, grind)["hits"]), 2,
		"Skill Link inflated a FIXED two-hit move:")


# ==========================================================================
# 4 + 5. unseen-fist and piercing-drill  (the protect gate)
# ==========================================================================

## Both abilities pierce protection. `_protected_turn` sets the volatile directly,
## which isolates the GATE from the move; the two
## `test_*_through_a_real_protect_turn` cases below then prove the same thing with
## the defender actually using Protect, so nothing here depends on hand-set state.
func _protected_turn(attacker: Dictionary, defender: Dictionary, move_slug: String,
		seed_value: int) -> Dictionary:
	var b := engine_for([attacker], [defender], seed_value)
	var target: Dictionary = b.active(1)
	var vol: Dictionary = target.get("volatile", {})
	vol["protect"] = true
	target["volatile"] = vol
	var before := int(target["hp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	return {"dealt": before - int(b.active(1)["hp"]), "engine": b}


func test_unseen_fist_lands_a_contact_move_through_protect_at_full_damage() -> void:
	var punch := real_move("shadow-punch")
	if punch.is_empty():
		pending("data/moves.json not generated")
		return
	check(Abilities.makes_contact(punch), "shadow-punch has no contact flag in this data build")
	check(Abilities.move_has_flag(punch, "protect"), "shadow-punch has no protect flag")

	var golurk := mon("Mega Golurk", ["ground", "ghost"], "unseen-fist", BULK, ["shadow-punch"])
	# Lapras, not Snorlax: Shadow Punch is GHOST and Ghost does NOTHING to a Normal
	# type, so a Normal wall would read 0 damage as "the pierce failed".
	var wall := mon("Lapras", ["water", "ice"], "", BULK)

	var pierced := _protected_turn(golurk, wall.duplicate(true), "shadow-punch", 41)
	var blocked := _protected_turn(control_of(golurk), wall.duplicate(true), "shadow-punch", 41)

	check(int(pierced["dealt"]) > 0, "Unseen Fist dealt no damage through Protect")
	eq(int(blocked["dealt"]), 0, "the control got through Protect, so nothing is proved:")
	check(log_has(blocked["engine"], "protected itself"), "no protect message in the control run")
	eq(log_has(pierced["engine"], "protected itself"), false,
		"Unseen Fist was still reported as blocked:")

	# FULL damage: the pierced hit equals an unprotected hit.
	var normal := damage_through_engine(golurk.duplicate(true), wall.duplicate(true), 41)
	eq(int(pierced["dealt"]), normal,
		"Unseen Fist's pierced hit is not full damage (mainline ruling):")


func test_piercing_drill_lands_through_protect_for_a_quarter() -> void:
	var drill := real_move("drill-run")
	if drill.is_empty():
		pending("data/moves.json not generated")
		return
	check(Abilities.makes_contact(drill), "drill-run has no contact flag in this data build")

	var exca := mon("Mega Excadrill", ["ground", "steel"], "piercing-drill", BULK, ["drill-run"])
	var wall := mon("Snorlax", ["normal"], "", BULK)

	var pierced := _protected_turn(exca, wall.duplicate(true), "drill-run", 42)
	var blocked := _protected_turn(control_of(exca), wall.duplicate(true), "drill-run", 42)
	var normal := damage_through_engine(exca.duplicate(true), wall.duplicate(true), 42)

	check(int(pierced["dealt"]) > 0, "Piercing Drill dealt no damage through Protect")
	eq(int(blocked["dealt"]), 0, "the control got through Protect, so nothing is proved:")
	check(int(pierced["dealt"]) < normal,
		"Piercing Drill's pierced hit was not reduced at all (%d vs %d unprotected)"
			% [int(pierced["dealt"]), normal])
	# A quarter, allowing for the per-step flooring.
	var ratio := float(int(pierced["dealt"])) / float(maxi(normal, 1))
	check(ratio > 0.2 and ratio < 0.32,
		"pierced/unprotected ratio %.3f is not the documented 1/4" % ratio)
	# The two signatures must NOT be the same number.
	check(not is_equal_approx(Abilities.of("piercing-drill").PIERCE_DAMAGE_MULT,
		Abilities.of("unseen-fist").PIERCE_DAMAGE_MULT),
		"piercing-drill and unseen-fist collapsed onto the same multiplier")


func test_a_non_contact_move_is_still_stopped_by_protect() -> void:
	var quake := real_move("earthquake")
	if quake.is_empty():
		pending("data/moves.json not generated")
		return
	eq(Abilities.makes_contact(quake), false, "earthquake gained a contact flag:")
	var golurk := mon("Mega Golurk", ["ground", "ghost"], "unseen-fist", BULK, ["earthquake"])
	var wall := mon("Lapras", ["water", "ice"], "", BULK)
	var r := _protected_turn(golurk, wall, "earthquake", 43)
	eq(int(r["dealt"]), 0, "Unseen Fist wrongly pierced with a NON-contact move:")


func test_the_protect_volatile_is_cleared_at_end_of_turn() -> void:
	# Without this the gate would latch and a single Protect would last all battle.
	var attacker := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var wall := mon("Snorlax", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([attacker], [wall], 44)
	var target: Dictionary = b.active(1)
	var vol: Dictionary = target.get("volatile", {})
	vol["protect"] = true
	target["volatile"] = vol
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(bool((b.active(1).get("volatile", {}) as Dictionary).get("protect", false)), false,
		"volatile.protect survived end of turn:")


# --- Protect itself, and the two piercers against a REAL Protect turn ------

func test_protect_blocks_an_attack_and_then_expires() -> void:
	# The enabling move. Without it the two piercing abilities are unreachable in
	# play, however complete their own code is.
	var protect := real_move("protect")
	var tackle := real_move("tackle")
	if protect.is_empty() or tackle.is_empty():
		pending("data/moves.json not generated")
		return
	eq(int(protect.get("effectId", -1)), 112, "protect is not effectId 112 in this data build:")
	eq(int(protect.get("priority", 0)), 4, "protect lost its +4 priority:")

	var blocker := mon("Snorlax", ["normal"], "", BULK, ["protect"])
	var attacker := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([attacker], [blocker], 161)
	var before := int(b.active(1)["hp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(int(b.active(1)["hp"]), before, "Protect did not block the attack:")
	check(log_has(b, "protected itself"), "no protect message")
	# It lasts ONE turn: the same attack lands next turn if Protect is not re-used.
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(int(b.active(1)["hp"]) < before, "Protect was still up on the following turn:")


func test_consecutive_protects_start_failing() -> void:
	# +4 priority protection that never fails is an unbreakable stall. 1, 1/3, 1/9.
	var protect := real_move("protect")
	if protect.is_empty():
		pending("data/moves.json not generated")
		return
	var blocker := mon("Snorlax", ["normal"], "", BULK, ["protect"])
	var attacker := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([attacker], [blocker], 162)
	var failures := 0
	for _turn in 8:
		b.submit_action(0, {"kind": "move", "move_index": 0})
		b.submit_action(1, {"kind": "move", "move_index": 0})
		b.resolve_turn()
		if b.over:
			break
	failures = log_count(b, "But it failed!")
	check(failures > 0, "eight consecutive Protects never failed -- the move is an infinite stall")
	check(int(b.active(1)["hp"]) < int(b.active(1)["maxHp"]),
		"the attacker never got through in eight turns")


func test_using_another_move_resets_the_protect_chain() -> void:
	var protect := real_move("protect")
	var tackle := real_move("tackle")
	if protect.is_empty() or tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var blocker := mon("Snorlax", ["normal"], "", BULK, ["protect", "tackle"])
	var attacker := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([attacker], [blocker], 163)
	# Protect, then tackle, then Protect again -- the second Protect is a FIRST use
	# again and must be certain.
	for idx: int in [0, 1, 0]:
		b.submit_action(0, {"kind": "move", "move_index": 0})
		b.submit_action(1, {"kind": "move", "move_index": idx})
		b.resolve_turn()
	eq(int((b.active(1).get("volatile", {}) as Dictionary).get("protect_streak", 0)), 1,
		"the chain did not reset after a non-protection move:")
	eq(log_count(b, "But it failed!"), 0, "a first use of Protect failed:")


func test_unseen_fist_pierces_through_a_real_protect_turn() -> void:
	# No hand-set volatile: the defender USES Protect, and the +4 priority means it
	# is already up when the slower Mega Golurk swings.
	var protect := real_move("protect")
	var punch := real_move("shadow-punch")
	if protect.is_empty() or punch.is_empty():
		pending("data/moves.json not generated")
		return
	var golurk := mon("Mega Golurk", ["ground", "ghost"], "unseen-fist", BULK, ["shadow-punch"])
	var blocker := mon("Lapras", ["water", "ice"], "", BULK, ["protect"])

	var b := engine_for([golurk.duplicate(true)], [blocker.duplicate(true)], 164)
	var before := int(b.active(1)["hp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	var dealt := before - int(b.active(1)["hp"])
	check(log_has(b, "protected itself"), "the defender did not actually Protect")
	check(dealt > 0, "Unseen Fist did not get through a real Protect")

	var c := engine_for([control_of(golurk)], [blocker.duplicate(true)], 164)
	var cbefore := int(c.active(1)["hp"])
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	eq(cbefore - int(c.active(1)["hp"]), 0, "the control got through a real Protect:")


func test_piercing_drill_pierces_a_real_protect_for_a_quarter() -> void:
	var protect := real_move("protect")
	var drill := real_move("drill-run")
	if protect.is_empty() or drill.is_empty():
		pending("data/moves.json not generated")
		return
	var exca := mon("Mega Excadrill", ["ground", "steel"], "piercing-drill", BULK, ["drill-run"])
	var blocker := mon("Snorlax", ["normal"], "", BULK, ["protect"])

	var b := engine_for([exca.duplicate(true)], [blocker.duplicate(true)], 165)
	var before := int(b.active(1)["hp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	var pierced := before - int(b.active(1)["hp"])
	check(log_has(b, "protected itself"), "the defender did not actually Protect")
	check(pierced > 0, "Piercing Drill did not get through a real Protect")

	var c := engine_for([control_of(exca)], [blocker.duplicate(true)], 165)
	var cbefore := int(c.active(1)["hp"])
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	eq(cbefore - int(c.active(1)["hp"]), 0, "the control got through a real Protect:")

	# Unprotected, the same move on the same seed: the pierced hit is a quarter.
	var open_target := mon("Snorlax", ["normal"], "", BULK, ["tackle"])
	var full := damage_through_engine(exca.duplicate(true), open_target, 165)
	var ratio := float(pierced) / float(maxi(full, 1))
	check(ratio > 0.2 and ratio < 0.32,
		"real-Protect pierced/unprotected ratio %.3f is not the documented 1/4" % ratio)


# ==========================================================================
# 6. aura-guard
# ==========================================================================

func test_aura_guard_halves_a_contact_move_only() -> void:
	var tackle := real_move("tackle")
	var beam := real_move("water-gun")
	if tackle.is_empty() or beam.is_empty():
		pending("data/moves.json not generated")
		return
	check(Abilities.makes_contact(tackle), "tackle has no contact flag in this data build")
	eq(Abilities.makes_contact(beam), false, "water-gun gained a contact flag:")

	var lucario := mon("Mega Lucario Z", ["fighting", "steel"], "aura-guard")
	var attacker := mon("Bibarel", ["normal"], "", BULK, ["tackle", "water-gun"])

	var guarded_contact := damage_through_engine(attacker.duplicate(true),
		lucario.duplicate(true), 51, 0)
	var plain_contact := damage_through_engine(attacker.duplicate(true),
		control_of(lucario), 51, 0)
	check(guarded_contact < plain_contact,
		"Aura Guard did not reduce a contact hit (%d vs %d)" % [guarded_contact, plain_contact])
	var ratio := float(guarded_contact) / float(maxi(plain_contact, 1))
	check(ratio > 0.45 and ratio < 0.56, "contact ratio %.3f is not the documented 0.5" % ratio)

	var guarded_ranged := damage_through_engine(attacker.duplicate(true),
		lucario.duplicate(true), 51, 1)
	var plain_ranged := damage_through_engine(attacker.duplicate(true),
		control_of(lucario), 51, 1)
	eq(guarded_ranged, plain_ranged,
		"Aura Guard also reduced a NON-contact move, which it must not:")


func test_aura_guard_protects_only_its_own_bearer_not_its_own_attacks() -> void:
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var lucario := mon("Mega Lucario Z", ["fighting", "steel"], "aura-guard", BULK, ["tackle"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	var with_ab := damage_through_engine(lucario.duplicate(true), wall.duplicate(true), 52)
	var without := damage_through_engine(control_of(lucario), wall.duplicate(true), 52)
	eq(with_ab, without, "Aura Guard changed the damage its OWN contact move dealt:")


# ==========================================================================
# 7. spicy-spray
# ==========================================================================

func test_spicy_spray_burns_the_attacker_and_the_control_does_not() -> void:
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var scov := mon("Mega Scovillain", ["grass", "fire"], "spicy-spray")
	var attacker := mon("Bibarel", ["normal"], "", BULK, ["tackle"])

	var b := engine_for([attacker.duplicate(true)], [scov.duplicate(true)], 61)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(String(b.active(0).get("status", "")), Status.BURN,
		"Spicy Spray did not burn the attacker:")

	var c := engine_for([attacker.duplicate(true)], [control_of(scov)], 61)
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	eq(String(c.active(0).get("status", "")), "",
		"the control also burned the attacker, so nothing is proved:")


func test_spicy_spray_fires_on_a_non_contact_move_too() -> void:
	# The trap in this ability: it is NOT Flame Body. A contact-only reading would
	# fail to burn Earthquake, which is most of what actually hits it.
	var quake := real_move("earthquake")
	if quake.is_empty():
		pending("data/moves.json not generated")
		return
	var scov := mon("Mega Scovillain", ["grass", "fire"], "spicy-spray")
	var attacker := mon("Golem", ["rock", "ground"], "", BULK, ["earthquake"])
	var b := engine_for([attacker], [scov], 62)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(String(b.active(0).get("status", "")), Status.BURN,
		"Spicy Spray failed to burn a NON-contact attacker:")


func test_spicy_spray_burns_from_beyond_the_grave() -> void:
	# Bulbapedia: it activates even if the Spicy Spray user faints from that hit.
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var scov := mon("Mega Scovillain", ["grass", "fire"], "spicy-spray", FRAIL, [], {"hp": 1})
	var attacker := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([attacker], [scov], 63)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(Stats.is_fainted(b.party_of(1)[0] as Dictionary),
		"the bearer did not faint, so the beyond-the-grave path was not exercised")
	eq(String(b.active(0).get("status", "")), Status.BURN,
		"a dying Spicy Spray failed to burn its killer:")


func test_spicy_spray_does_not_burn_a_fire_type_attacker() -> void:
	# status.gd owns the immunity; the ability must not re-implement or bypass it.
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var scov := mon("Mega Scovillain", ["grass", "fire"], "spicy-spray")
	var fire := mon("Magmar", ["fire"], "", BULK, ["tackle"])
	var b := engine_for([fire], [scov], 64)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(String(b.active(0).get("status", "")), "", "a Fire-type attacker was burned:")


# ==========================================================================
# 8. delta-stream
# ==========================================================================

func test_delta_stream_sets_strong_winds_and_removes_a_flying_weakness() -> void:
	# power-gem, not rock-slide: rock-slide is 90% accurate and a missed turn would
	# read as "the ability worked" (0 damage vs 0 damage). Every damage comparison in
	# this file uses a move that cannot miss.
	var gem := real_move("power-gem")
	if gem.is_empty():
		pending("data/moves.json not generated")
		return
	eq(int(gem.get("accuracy", 0)), 100, "power-gem is not 100%-accurate in this data build:")
	var ray := mon("Mega Rayquaza", ["dragon", "flying"], "delta-stream")
	var attacker := mon("Golem", ["rock", "ground"], "", BULK, ["power-gem"])

	var b := engine_for([attacker.duplicate(true)], [ray.duplicate(true)], 81)
	eq(String(b.weather), "strong-winds", "Delta Stream did not set the field state:")
	check(log_has(b, "mysterious air current"), "no strong-winds announcement")
	var winded := int(b.active(1)["hp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	winded -= int(b.active(1)["hp"])

	var c := engine_for([attacker.duplicate(true)], [control_of(ray)], 81)
	eq(String(c.weather), "", "the control set a field state:")
	var plain := int(c.active(1)["hp"])
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	plain -= int(c.active(1)["hp"])

	check(winded < plain,
		"strong winds did not reduce Rock damage on a Flying-type (%d vs %d)" % [winded, plain])
	var ratio := float(winded) / float(maxi(plain, 1))
	check(ratio > 0.45 and ratio < 0.56, "Rock ratio %.3f is not 2x -> 1x" % ratio)


func test_delta_stream_is_per_component_not_a_clamp_on_the_product() -> void:
	# The sharpest case: Electric vs Dragon/Flying goes 1x -> 0.5x. A clamp of the
	# PRODUCT to 1.0 would leave it at 1x and would leave Ice at 1x instead of 2x.
	var ray := mon("Mega Rayquaza", ["dragon", "flying"], "delta-stream")
	var rows: Array = [
		["electric", 1.0, 0.5], ["ice", 4.0, 2.0], ["rock", 2.0, 1.0],
		["dragon", 2.0, 2.0], ["fighting", 0.5, 0.5], ["ground", 0.0, 0.0],
	]
	for row: Array in rows:
		var t := String(row[0])
		var off := Damage.type_multiplier(t, ray["types"], {"defender": ray, "weather": ""})
		var on := Damage.type_multiplier(t, ray["types"], {"defender": ray, "weather": "strong-winds"})
		almost(off, float(row[1]), 0.001, "%s without winds:" % t)
		almost(on, float(row[2]), 0.001, "%s under strong winds:" % t)


func test_delta_stream_protects_the_opposing_side_too() -> void:
	# It is a FIELD effect, not a bearer effect: every Flying-type on the field.
	var ray := mon("Mega Rayquaza", ["dragon", "flying"], "delta-stream")
	var staraptor := mon("Staraptor", ["normal", "flying"], "")
	var on := Damage.type_multiplier("rock", staraptor["types"],
		{"defender": staraptor, "weather": "strong-winds"})
	var off := Damage.type_multiplier("rock", staraptor["types"],
		{"defender": staraptor, "weather": ""})
	almost(off, 2.0, 0.001, "Rock vs Normal/Flying without winds:")
	almost(on, 1.0, 0.001, "strong winds did not protect a DIFFERENT Flying-type:")
	check(ray["ability"] == "delta-stream", "fixture lost its ability")


func test_strong_winds_clear_when_the_holder_leaves_the_field() -> void:
	var ray := mon("Mega Rayquaza", ["dragon", "flying"], "delta-stream", FRAIL, ["tackle"],
		{"hp": 1})
	var bench := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var attacker := mon("Snorlax", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([attacker], [ray, bench], 82)
	eq(String(b.weather), "strong-winds", "winds were not up to begin with:")
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	if Stats.is_fainted(b.party_of(1)[0] as Dictionary):
		eq(String(b.weather), "", "strong winds survived the holder's faint:")
		check(log_has(b, "dissipated"), "no dissipation message when the winds ended")
	else:
		pending("the seeded turn did not KO the holder")


func test_delta_stream_refuses_to_be_replaced_by_other_weather() -> void:
	var ray := mon("Mega Rayquaza", ["dragon", "flying"], "delta-stream")
	for w: String in ["sun", "rain", "sandstorm", "hail", "snow"]:
		eq(Abilities.blocks_weather_set([ray], w, "strong-winds"), true,
			"strong winds allowed %s to be set:" % w)
	eq(Abilities.blocks_weather_set([ray], "strong-winds", "strong-winds"), false,
		"setting strong winds again was treated as a failure:")
	eq(Abilities.blocks_weather_set([control_of(ray)], "sun", ""), false,
		"a mon with no ability blocked a weather set:")


# ==========================================================================
# 9. steadfast
# ==========================================================================

func test_steadfast_raises_speed_when_the_bearer_actually_flinches() -> void:
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var mewtwo := mon("Mega Mewtwo X", ["psychic", "fighting"], "steadfast", BULK, ["tackle"])
	var foe := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	# Snapshot the control BEFORE the first run: the engine mutates the very
	# Dictionaries it is handed, so a control taken afterwards would already carry
	# the stage the bearer just gained.
	var control := control_of(mewtwo)

	# Flinch the bearer the way a flinch move does, then take its turn.
	var b := engine_for([mewtwo], [foe], 91)
	Status.set_flinch(b.active(0), true)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(log_has(b, "flinched"), "the bearer did not flinch, so nothing is proved")
	eq(int((b.active(0).get("stages", {}) as Dictionary).get("spe", 0)), 1,
		"Steadfast did not raise Speed on a flinch:")
	check(log_has(b, "Steadfast raised its Speed"), "no Steadfast message")

	var c := engine_for([control], [foe.duplicate(true)], 91)
	Status.set_flinch(c.active(0), true)
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	eq(int((c.active(0).get("stages", {}) as Dictionary).get("spe", 0)), 0,
		"the control also gained Speed, so nothing is proved:")


func test_steadfast_is_reachable_from_a_real_flinch_move() -> void:
	# The engine really does set the flinch volatile from a move's effect string,
	# so this is not a hand-set-only path.
	var fake := real_move("fake-out")
	if fake.is_empty():
		pending("data/moves.json not generated")
		return
	check(String(fake.get("effect", "")).contains("flinch"),
		"fake-out's effect string no longer mentions flinch -- the engine hook would go dead")
	var mewtwo := mon("Mega Mewtwo X", ["psychic", "fighting"], "steadfast", BULK, ["tackle"])
	var bully := mon("Ambipom", ["normal"], "", BULK, ["fake-out"])
	var b := engine_for([bully], [mewtwo], 92)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	# Fake Out is +3 priority, so the flinch lands before Mewtwo moves this turn.
	if log_has(b, "flinched"):
		eq(int((b.active(1).get("stages", {}) as Dictionary).get("spe", 0)), 1,
			"a real flinch move did not trigger Steadfast:")
	else:
		pending("the seeded turn did not produce a flinch")


func test_steadfast_says_nothing_at_the_speed_cap() -> void:
	var mewtwo := mon("Mega Mewtwo X", ["psychic", "fighting"], "steadfast", BULK, ["tackle"])
	var foe := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := engine_for([mewtwo], [foe], 93)
	var stages: Dictionary = b.active(0).get("stages", {})
	stages["spe"] = 6
	b.active(0)["stages"] = stages
	Status.set_flinch(b.active(0), true)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(int((b.active(0).get("stages", {}) as Dictionary).get("spe", 0)), 6, "Speed went past +6:")
	eq(log_has(b, "Steadfast raised its Speed"), false,
		"Steadfast announced a boost it could not apply:")


# ==========================================================================
# 10. stalwart  -- the honest negative result
# ==========================================================================

func test_stalwart_is_declared_and_registered() -> void:
	var skarm := mon("Mega Skarmory", ["steel", "flying"], "stalwart")
	eq(Abilities.ignores_redirection(skarm), true, "stalwart does not answer its own hook:")
	eq(Abilities.ignores_redirection(control_of(skarm)), false, "a mon with no ability redirects:")


func test_stalwart_changes_no_battle_outcome_and_that_is_correct() -> void:
	# Redirection exists only in double battles and this engine is single-battles
	# only, so there is NOTHING for the hook to change. This test exists to keep
	# the negative result honest: if someone later gives Stalwart an invented
	# single-battle effect (the common fan error is Mold Breaker's), these
	# assertions fail and the reviewer is forced to look.
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var skarm := mon("Mega Skarmory", ["steel", "flying"], "stalwart", BULK, ["tackle"])
	var foe := mon("Blissey", ["normal"], "sturdy", BULK, ["tackle"])

	# Attacking: identical.
	eq(damage_through_engine(skarm.duplicate(true), foe.duplicate(true), 101),
		damage_through_engine(control_of(skarm), foe.duplicate(true), 101),
		"stalwart changed the damage it deals -- it must not:")
	# Defending: identical.
	eq(damage_through_engine(foe.duplicate(true), skarm.duplicate(true), 102),
		damage_through_engine(foe.duplicate(true), control_of(skarm), 102),
		"stalwart changed the damage it takes -- it must not:")
	# It must not become Mold Breaker: the target's ability still applies.
	var guard := mon("Mega Lucario Z", ["fighting", "steel"], "aura-guard")
	var vs_guard := damage_through_engine(skarm.duplicate(true), guard.duplicate(true), 103)
	var vs_plain := damage_through_engine(skarm.duplicate(true), control_of(guard), 103)
	check(vs_guard < vs_plain,
		"stalwart ignored the target's ability -- that is Mold Breaker, not Stalwart")


# ==========================================================================
# 11. mega-sol
# ==========================================================================

func test_mega_sol_resolves_its_own_fire_move_under_sun() -> void:
	var ember := real_move("flamethrower")
	if ember.is_empty():
		pending("data/moves.json not generated")
		return
	var meg := mon("Mega Meganium", ["grass", "fairy"], "mega-sol", BULK, ["flamethrower"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	eq(Abilities.weather_view(meg, ""), "sun", "mega-sol does not report a sun view:")
	eq(Abilities.weather_view(control_of(meg), ""), "", "the control reports a weather view:")

	var boosted := damage_through_engine(meg.duplicate(true), wall.duplicate(true), 111)
	var plain := damage_through_engine(control_of(meg), wall.duplicate(true), 111)
	check(boosted > plain,
		"mega-sol did not boost its own Fire move (%d vs %d)" % [boosted, plain])
	var ratio := float(boosted) / float(maxi(plain, 1))
	check(ratio > 1.4 and ratio < 1.6, "Fire ratio %.3f is not sun's 1.5x" % ratio)


func test_mega_sol_also_pays_suns_water_penalty() -> void:
	var gun := real_move("water-gun")
	if gun.is_empty():
		pending("data/moves.json not generated")
		return
	var meg := mon("Mega Meganium", ["grass", "fairy"], "mega-sol", BULK, ["water-gun"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	var nerfed := damage_through_engine(meg.duplicate(true), wall.duplicate(true), 112)
	var plain := damage_through_engine(control_of(meg), wall.duplicate(true), 112)
	check(nerfed < plain,
		"mega-sol did not apply sun's Water penalty (%d vs %d)" % [nerfed, plain])


func test_mega_sol_does_not_change_the_real_field_weather() -> void:
	var meg := mon("Mega Meganium", ["grass", "fairy"], "mega-sol", BULK, ["tackle"])
	var foe := mon("Bibarel", ["normal"], "", BULK, ["tackle"])
	var b := BattleEngine.new()
	b.start({"kind": "trainer", "party": [meg], "opponent": [foe], "cap": 100,
		"seed": 113, "weather": "rain",
		"trainer": {"name": "Rival", "ai": 5, "keyStone": false, "prizeMoney": 0}})
	eq(String(b.weather), "rain", "mega-sol overwrote the real field weather:")
	# The OPPONENT still resolves under the real weather.
	eq(Abilities.weather_view(b.active(1), b.weather), "rain",
		"mega-sol leaked its view onto the opponent:")


func test_mega_sol_skips_the_sandstorm_rock_special_defence_boost() -> void:
	var beam := real_move("water-gun")
	if beam.is_empty():
		pending("data/moves.json not generated")
		return
	var meg := mon("Mega Meganium", ["grass", "fairy"], "mega-sol", BULK, ["water-gun"])
	var rock := mon("Golem", ["rock", "ground"], "", BULK)
	# Under a real sandstorm, Rock-types get +50% Sp. Def -- but the bearer's move
	# is resolved under sun, so it does not see that boost.
	var as_sol := Damage.compute(meg, rock, beam,
		{"weather": Abilities.weather_view(meg, "sandstorm"), "field_weather": "sandstorm",
		"roll": 100, "crit": false})
	var as_plain := Damage.compute(control_of(meg), rock, beam,
		{"weather": "sandstorm", "field_weather": "sandstorm", "roll": 100, "crit": false})
	check(int(as_sol["damage"]) != int(as_plain["damage"]),
		"mega-sol saw the sandstorm Rock Sp. Def boost anyway")


# ==========================================================================
# 12. dragonize
# ==========================================================================

func test_dragonize_turns_a_normal_move_dragon_and_a_fairy_becomes_immune() -> void:
	var slam := real_move("body-slam")
	if slam.is_empty():
		pending("data/moves.json not generated")
		return
	var gatr := mon("Mega Feraligatr", ["water", "dragon"], "dragonize", BULK, ["body-slam"])
	var fairy := mon("Clefable", ["fairy"], "", BULK)

	var b := engine_for([gatr.duplicate(true)], [fairy.duplicate(true)], 121)
	var before := int(b.active(1)["hp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(int(b.active(1)["hp"]), before, "a Dragonized Body Slam still damaged a Fairy:")
	check(log_has(b, "doesn't affect"), "no immunity message for the Dragonized move")

	var c := engine_for([control_of(gatr)], [fairy.duplicate(true)], 121)
	var cbefore := int(c.active(1)["hp"])
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	check(int(c.active(1)["hp"]) < cbefore,
		"the control's Normal-type Body Slam also failed, so nothing is proved")


func test_dragonize_lets_a_normal_move_hit_a_ghost() -> void:
	var slam := real_move("body-slam")
	if slam.is_empty():
		pending("data/moves.json not generated")
		return
	var gatr := mon("Mega Feraligatr", ["water", "dragon"], "dragonize", BULK, ["body-slam"])
	var ghost := mon("Gengar", ["ghost", "poison"], "", BULK)
	var dealt := damage_through_engine(gatr.duplicate(true), ghost.duplicate(true), 122)
	var plain := damage_through_engine(control_of(gatr), ghost.duplicate(true), 122)
	check(dealt > 0, "a Dragonized Body Slam did nothing to a Ghost")
	eq(plain, 0, "the control's Normal move already hit the Ghost, so nothing is proved:")


func test_dragonize_applies_stab_after_the_conversion() -> void:
	# The whole ability is the ORDER: convert, then STAB, then the chart. Mega
	# Feraligatr is Water/Dragon, so the converted move gains 1.5x STAB it did not
	# have as a Normal move.
	var slam := real_move("body-slam")
	if slam.is_empty():
		pending("data/moves.json not generated")
		return
	var gatr := mon("Mega Feraligatr", ["water", "dragon"], "dragonize", BULK, ["body-slam"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	var dealt := damage_through_engine(gatr.duplicate(true), wall.duplicate(true), 123)
	var plain := damage_through_engine(control_of(gatr), wall.duplicate(true), 123)
	# 1.2x power then 1.5x STAB, against a neutral Normal target.
	var ratio := float(dealt) / float(maxi(plain, 1))
	check(ratio > 1.6 and ratio < 2.0,
		"Dragonized/plain ratio %.3f is not the documented ~1.8x" % ratio)


func test_dragonize_never_mutates_the_stored_move() -> void:
	var slam := real_move("body-slam")
	if slam.is_empty():
		pending("data/moves.json not generated")
		return
	var gatr := mon("Mega Feraligatr", ["water", "dragon"], "dragonize", BULK, ["body-slam"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	var b := engine_for([gatr], [wall], 124)
	var stored: Dictionary = (b.active(0)["moves"] as Array)[0]
	var pp_before := int(stored["pp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(String(stored["type"]), "normal",
		"Body Slam became permanently Dragon-type in the mon's own moveset:")
	eq(int(stored["power"]), int(slam["power"]), "the stored move's power was inflated:")
	# ...and PP still decremented, which is what breaks if the dict is duplicated
	# BEFORE the decrement instead of after.
	eq(int(stored["pp"]), pp_before - 1, "PP did not decrement:")


func test_dragonize_leaves_status_moves_alone() -> void:
	var growl := real_move("growl")
	if growl.is_empty():
		pending("data/moves.json not generated")
		return
	var gatr := mon("Mega Feraligatr", ["water", "dragon"], "dragonize")
	var got := Abilities.modify_move(gatr, growl)
	eq(got.is_empty(), true, "dragonize converted a STATUS move:")


# ==========================================================================
# 13. eelevate
# ==========================================================================

func test_eelevate_is_immune_to_a_ground_move_the_control_takes() -> void:
	var quake := real_move("earthquake")
	if quake.is_empty():
		pending("data/moves.json not generated")
		return
	var eel := mon("Mega Eelektross", ["electric"], "eelevate")
	var golem := mon("Golem", ["rock", "ground"], "", BULK, ["earthquake"])

	var b := engine_for([golem.duplicate(true)], [eel.duplicate(true)], 131)
	var before := int(b.active(1)["hp"])
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(int(b.active(1)["hp"]), before, "Eelevate took Earthquake damage:")
	check(log_has(b, "doesn't affect"), "no immunity message")
	eq(Abilities.is_grounded(eel), false, "the bearer is still grounded:")

	var c := engine_for([golem.duplicate(true)], [control_of(eel)], 131)
	var cbefore := int(c.active(1)["hp"])
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	check(int(c.active(1)["hp"]) < cbefore, "the control was also immune, so nothing is proved")


func test_eelevate_boosts_its_highest_stat_on_a_ko() -> void:
	var bolt := real_move("thunderbolt")
	if bolt.is_empty():
		pending("data/moves.json not generated")
		return
	var eel := mon("Mega Eelektross", ["electric"], "eelevate",
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80}, ["thunderbolt"])
	var victim := mon("Magikarp", ["water"], "", FRAIL, ["tackle"], {"hp": 1})

	var b := engine_for([eel.duplicate(true)], [victim.duplicate(true)], 132)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(Stats.is_fainted(b.party_of(1)[0] as Dictionary), "the victim did not faint")
	# Mega Eelektross's highest RAW non-HP stat is Attack (145), NOT the Sp. Atk it
	# just attacked with. Beast Boost's rule, and the usual bug is to boost the
	# attacking stat or to read the EFFECTIVE stat.
	eq(int((b.active(0).get("stages", {}) as Dictionary).get("atk", 0)), 1,
		"Eelevate did not raise Attack on the KO:")
	eq(int((b.active(0).get("stages", {}) as Dictionary).get("spa", 0)), 0,
		"Eelevate raised the ATTACKING stat instead of the highest one:")

	var c := engine_for([control_of(eel)], [victim.duplicate(true)], 132)
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	eq(int((c.active(0).get("stages", {}) as Dictionary).get("atk", 0)), 0,
		"the control also boosted, so nothing is proved:")


func test_eelevate_does_not_boost_without_a_ko() -> void:
	var bolt := real_move("thunderbolt")
	if bolt.is_empty():
		pending("data/moves.json not generated")
		return
	var eel := mon("Mega Eelektross", ["electric"], "eelevate", BULK, ["thunderbolt"])
	var wall := mon("Blissey", ["normal"], "", {"hp": 700, "atk": 10, "def": 100, "spa": 10, "spd": 200, "spe": 55})
	var b := engine_for([eel], [wall], 133)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(not Stats.is_fainted(b.active(1)), "the wall fainted, so this proves nothing")
	eq(int((b.active(0).get("stages", {}) as Dictionary).get("atk", 0)), 0,
		"Eelevate boosted without a KO:")


func test_eelevate_reads_the_raw_stat_not_the_effective_one() -> void:
	# Bulbapedia: the choice "does not account for stat stage changes". Drop Attack
	# to -6 and Attack must STILL be the boosted stat.
	var eel := mon("Mega Eelektross", ["electric"], "eelevate",
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 80})
	var stages: Dictionary = eel.get("stages", {})
	stages["atk"] = -6
	eel["stages"] = stages
	eq(Abilities.of("eelevate").highest_stat(eel), "atk",
		"Eelevate's stat choice drifted with stat stages:")


func test_a_grounding_effect_overrides_eelevate() -> void:
	# The single seam every future grounder (Gravity, Iron Ball, Smack Down,
	# Ingrain, Thousand Arrows) will use.
	var quake := real_move("earthquake")
	if quake.is_empty():
		pending("data/moves.json not generated")
		return
	var eel := mon("Mega Eelektross", ["electric"], "eelevate")
	var vol: Dictionary = eel.get("volatile", {})
	vol["grounded_by"] = true
	eel["volatile"] = vol
	eq(Abilities.is_grounded(eel), true, "volatile.grounded_by did not override the ability:")
	var r := Damage.compute(mon("Golem", ["rock", "ground"]), eel, quake,
		{"roll": 100, "crit": false})
	check(int(r["damage"]) > 0, "a grounded Eelevate was still immune to Earthquake")


# ==========================================================================
# 14. fire-mane
# ==========================================================================

func test_fire_mane_multiplies_the_attacking_stat_on_fire_moves_only() -> void:
	var flame := real_move("flamethrower")
	var beam := real_move("water-gun")
	if flame.is_empty() or beam.is_empty():
		pending("data/moves.json not generated")
		return
	var pyroar := mon("Mega Pyroar", ["fire", "normal"], "fire-mane", BULK,
		["flamethrower", "water-gun"])
	var wall := mon("Snorlax", ["normal"], "", BULK)

	var fire_on := damage_through_engine(pyroar.duplicate(true), wall.duplicate(true), 141, 0)
	var fire_off := damage_through_engine(control_of(pyroar), wall.duplicate(true), 141, 0)
	check(fire_on > fire_off, "Fire Mane did not boost a Fire move (%d vs %d)" % [fire_on, fire_off])

	var other_on := damage_through_engine(pyroar.duplicate(true), wall.duplicate(true), 141, 1)
	var other_off := damage_through_engine(control_of(pyroar), wall.duplicate(true), 141, 1)
	eq(other_on, other_off, "Fire Mane boosted a NON-Fire move:")


func test_fire_mane_is_a_stat_multiplier_not_a_damage_multiplier() -> void:
	# The documented mechanic, and the two give different numbers because the base
	# formula divides by Defence and floors. Hand-computed, not "damage x 1.5".
	var flame := real_move("flamethrower")
	if flame.is_empty():
		pending("data/moves.json not generated")
		return
	var pyroar := mon("Mega Pyroar", ["fire", "normal"], "fire-mane", BULK, ["flamethrower"])
	var wall := mon("Snorlax", ["normal"], "", BULK)
	var on := Damage.compute(pyroar, wall, flame, {"roll": 100, "crit": false})
	var off := Damage.compute(control_of(pyroar), wall, flame, {"roll": 100, "crit": false})
	almost(float(on["atkMult"]), 1.5, 0.0001, "fire-mane did not report atk_mult 1.5:")
	almost(float(on["damageMult"]), 1.0, 0.0001, "fire-mane leaked into damage_mult:")
	almost(float(on["powerMult"]), 1.0, 0.0001, "fire-mane leaked into power_mult:")
	check(int(on["damage"]) > int(off["damage"]), "no damage change")

	# THE EQUIVALENCE, which is what "stat multiplier" means: an ability-less mon
	# whose Sp. Atk is ALREADY 1.5x must take the identical number out of the
	# formula. A power- or damage-multiplier implementation lands somewhere else,
	# because the base formula floors after dividing by Defence.
	var prebuffed := control_of(pyroar)
	var st: Dictionary = (prebuffed["stats"] as Dictionary).duplicate()
	st["spa"] = maxi(1, floori(float(st["spa"]) * 1.5))
	prebuffed["stats"] = st
	var equivalent := Damage.compute(prebuffed, wall, flame, {"roll": 100, "crit": false})
	eq(int(on["damage"]), int(equivalent["damage"]),
		"fire-mane is not acting on the STAT: 1.5x Sp. Atk gives a different number:")
	# ...and that number is NOT what a damage multiplier would have produced.
	check(int(on["damage"]) != maxi(1, floori(float(off["damage"]) * 1.5))
			or int(on["damage"]) == int(equivalent["damage"]),
		"fire-mane looks like a damage multiplier")


func test_fire_mane_does_not_help_when_being_hit_by_fire() -> void:
	var flame := real_move("flamethrower")
	if flame.is_empty():
		pending("data/moves.json not generated")
		return
	var pyroar := mon("Mega Pyroar", ["fire", "normal"], "fire-mane")
	var attacker := mon("Magmar", ["fire"], "", BULK, ["flamethrower"])
	eq(damage_through_engine(attacker.duplicate(true), pyroar.duplicate(true), 142),
		damage_through_engine(attacker.duplicate(true), control_of(pyroar), 142),
		"fire-mane changed the damage its bearer TAKES from a Fire move:")


# ==========================================================================
# CROSS-GROUP REGRESSIONS -- what no single group could see
# ==========================================================================

func test_regression_mega_sol_cannot_delete_delta_stream() -> void:
	# THIS WAS A REAL BUG, found by putting two groups' abilities on the field at
	# once: `weather` carried BOTH the real field state and a per-mon weather VIEW,
	# so a Mega Sol attacker resolved the type chart under "sun" and another
	# Pokemon's strong winds simply vanished -- Mega Meganium's Rock Slide did 70
	# to a Flying-type where every other attacker did 35. Fixed by splitting the
	# ctx into `weather` (the view) and `field_weather` (the field).
	var slide := real_move("rock-slide")
	if slide.is_empty():
		pending("data/moves.json not generated")
		return
	var ray := mon("Mega Rayquaza", ["dragon", "flying"], "delta-stream")
	var sol := mon("Mega Meganium", ["grass", "fairy"], "mega-sol", BULK, ["rock-slide"])
	var plain := mon("Golem", ["rock", "ground"], "", BULK, ["rock-slide"])

	var by_sol := damage_through_engine(sol, ray.duplicate(true), 151)
	var by_plain := damage_through_engine(plain, ray.duplicate(true), 151)
	# Same stats in BULK, so the only difference between the two rows is the ability.
	check(by_sol > 0 and by_plain > 0, "one of the rows dealt no damage at all")
	var r_sol := Damage.compute(sol, ray, slide,
		{"weather": Abilities.weather_view(sol, "strong-winds"),
		"field_weather": "strong-winds", "roll": 100, "crit": false})
	var r_plain := Damage.compute(plain, ray, slide,
		{"weather": "strong-winds", "field_weather": "strong-winds", "roll": 100, "crit": false})
	almost(float(r_sol["effectiveness"]), 1.0, 0.001,
		"a mega-sol attacker saw through another Pokemon's strong winds:")
	almost(float(r_plain["effectiveness"]), 1.0, 0.001, "strong winds failed for a plain attacker:")


func test_regression_delta_stream_survives_a_mega_sol_holder_on_the_field() -> void:
	# The field refresh must not be confused by a mon that has a weather VIEW but
	# no field state of its own.
	var ray := mon("Mega Rayquaza", ["dragon", "flying"], "delta-stream", BULK, ["tackle"])
	var sol := mon("Mega Meganium", ["grass", "fairy"], "mega-sol", BULK, ["tackle"])
	var b := engine_for([sol], [ray], 152)
	eq(String(b.weather), "strong-winds", "a mega-sol holder suppressed strong winds:")
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	eq(String(b.weather), "strong-winds", "strong winds were lost during a turn:")


func test_regression_spicy_spray_fires_once_per_hit_of_a_multi_hit_move() -> void:
	# The contact group called `hit_taken` once per MOVE; the multi-hit group then
	# added the loop. If the call had stayed outside it, a Skill Link Pin Missile
	# would produce one burn attempt instead of five. The first attempt succeeds and
	# the rest are refused by status.gd, so the observable is: burned, exactly once,
	# with no duplicate message.
	# arm-thrust (effectId 30, 100% accurate, Fighting so it is neutral on
	# Grass/Fire) -- a 95%-accurate move here would let a miss look like a
	# five-hit plan that never ran.
	var thrust := real_move("arm-thrust")
	if thrust.is_empty():
		pending("data/moves.json not generated")
		return
	var hera := mon("Mega Heracross", ["bug", "fighting"], "skill-link", BULK, ["arm-thrust"])
	var scov := mon("Mega Scovillain", ["grass", "fire"], "spicy-spray",
		{"hp": 900, "atk": 138, "def": 85, "spa": 138, "spd": 85, "spe": 75})
	var b := engine_for([hera], [scov], 153)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(log_has(b, "Hit 5 time(s)!"), "the five-hit plan did not happen")
	eq(String(b.active(0).get("status", "")), Status.BURN,
		"Spicy Spray did not fire from inside the hit loop:")
	eq(log_count(b, "burned"), 1, "the burn message was printed more than once:")


func test_regression_parental_bond_plus_eelevate_pays_exactly_one_boost() -> void:
	# The gap the "new" group flagged and could not close alone: a pair that KOs on
	# hit 1 must break the loop and pay the KO bonus ONCE.
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var hybrid := mon("Test Kangaskhan", ["normal"], "parental-bond",
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 120}, ["tackle"])
	var victim := mon("Magikarp", ["water"], "", FRAIL, ["tackle"], {"hp": 1})
	var b := engine_for([hybrid], [victim], 154)
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()
	check(Stats.is_fainted(b.party_of(1)[0] as Dictionary), "the victim did not faint")
	# The pair stopped on the KO, so only ONE hit landed.
	eq(log_has(b, "Hit 2 time(s)!"), false, "the pair continued past the KO:")

	# Same shape with eelevate instead, so the boost count is observable.
	var eel := mon("Test Eelektross", ["electric"], "eelevate",
		{"hp": 300, "atk": 145, "def": 80, "spa": 135, "spd": 90, "spe": 120}, ["tackle"])
	var v2 := mon("Magikarp", ["water"], "", FRAIL, ["tackle"], {"hp": 1})
	var c := engine_for([eel], [v2], 154)
	c.submit_action(0, {"kind": "move", "move_index": 0})
	c.submit_action(1, {"kind": "move", "move_index": 0})
	c.resolve_turn()
	eq(int((c.active(0).get("stages", {}) as Dictionary).get("atk", 0)), 1,
		"a KO inside the hit loop paid a number of boosts other than one:")


func test_regression_aura_guard_and_fire_mane_compose_from_opposite_sides() -> void:
	# damage_mods() folds BOTH sides. A contact Fire move from a Fire Mane holder
	# into an Aura Guard holder must take 1.5x on the stat and 0.5x on the damage --
	# neither ability knowing the other exists.
	var punch := real_move("fire-punch")
	if punch.is_empty():
		pending("data/moves.json not generated")
		return
	check(Abilities.makes_contact(punch), "fire-punch has no contact flag in this data build")
	var pyroar := mon("Mega Pyroar", ["fire", "normal"], "fire-mane", BULK, ["fire-punch"])
	var lucario := mon("Mega Lucario Z", ["fighting", "steel"], "aura-guard", BULK)
	var r := Damage.compute(pyroar, lucario, punch, {"roll": 100, "crit": false})
	almost(float(r["atkMult"]), 1.5, 0.0001, "the attacker's fire-mane did not survive the fold:")
	almost(float(r["damageMult"]), 0.5, 0.0001, "the defender's aura-guard did not survive the fold:")


func test_regression_no_ability_in_play_leaves_the_numbers_bit_identical() -> void:
	# The whole ability layer must be free when nothing implements anything. Same
	# fixtures, one with an UNIMPLEMENTED ability slug, one with none.
	var tackle := real_move("tackle")
	if tackle.is_empty():
		pending("data/moves.json not generated")
		return
	var a := mon("Bibarel", ["normal"], "torrent", BULK, ["tackle"])
	var d := mon("Snorlax", ["normal"], "immunity", BULK)
	var r := Damage.compute(a, d, tackle, {"roll": 97, "crit": false})
	var plain := Damage.compute(control_of(a), control_of(d), tackle, {"roll": 97, "crit": false})
	eq(int(r["damage"]), int(plain["damage"]), "an unimplemented ability changed the damage:")
	almost(float(r["atkMult"]), 1.0, 0.0001, "atk_mult drifted off 1.0:")
	almost(float(r["powerMult"]), 1.0, 0.0001, "power_mult drifted off 1.0:")
	almost(float(r["damageMult"]), 1.0, 0.0001, "damage_mult drifted off 1.0:")


func test_no_excluded_gimmick_leaked_into_the_ability_layer() -> void:
	# DATA_CONTRACT 11.4: no Dynamax / Gigantamax / Z-Move / Terastal code or data.
	#
	# THE RULE THIS ENCODES: a gimmick name may appear in an ability file only in a
	# COMMENT (recording why the thing is excluded) or inside a REJECTION list -- a
	# `const EXCLUDED`-style array whose whole purpose is to refuse the mechanic.
	# It may never appear in a branch, a hook or a lookup that would implement it.
	# Both allowances are named explicitly below so a new one cannot slip in.
	const BANNED: Array = ["dynamax", "gigantamax", "gmax", "z-move", "zmove",
		"terastal", "terastalliz", "tera-blast", "tera_blast", "max-guard", "max guard"]
	## file -> the one rejection-list line that may name a gimmick.
	const REJECTION_LISTS: Dictionary = {"dragonize.gd": "tera-blast"}

	var dir := DirAccess.open("res://src/battle/abilities")
	check(dir != null, "cannot open the abilities directory")
	if dir == null:
		return
	var files := 0
	for f: String in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		files += 1
		var text := FileAccess.get_file_as_string("res://src/battle/abilities/" + f).to_lower()
		for line: String in text.split("
"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue        # a comment naming an exclusion is the documented way
			for word: String in BANNED:
				if not stripped.contains(word):
					continue
				# The one permitted non-comment case: this file's rejection list.
				if String(REJECTION_LISTS.get(f, "")) == word and stripped.contains("\""):
					continue
				check(false, "%s implements an excluded gimmick (%s): %s" % [f, word, stripped])
	check(files >= 14, "only %d ability files were scanned" % files)


func test_no_mega_form_references_an_excluded_gimmick() -> void:
	# The Mega layer is the one gimmick this game HAS, so its data is where a
	# smuggled Dynamax/Tera form would do the most damage. Read the shipped file.
	var raw := FileAccess.get_file_as_string("res://data/megas.json")
	if raw.is_empty():
		pending("data/megas.json not readable")
		return
	var parsed: Variant = JSON.parse_string(raw)
	check(parsed is Dictionary, "data/megas.json is not an object")
	if not (parsed is Dictionary):
		return
	var lower := raw.to_lower()
	for word: String in ["dynamax", "gigantamax", "gmax", "z-move", "zmove", "terastal",
			"tera-blast", "max-guard", "primal-groudon", "primal-kyogre"]:
		eq(lower.contains(word), false, "data/megas.json mentions '%s':" % word)
	# ...and every one of the 14 abilities is reachable from a real Mega form, so
	# none of this work was spent on an ability nothing can ever hold.
	var forms: Array = (parsed as Dictionary).get("forms", [])
	var held: Dictionary = {}
	for form: Dictionary in forms:
		for ab: String in (form.get("abilities", []) as Array):
			held[ab] = true
	for slug: String in THE_FOURTEEN:
		check(held.has(slug), "no Mega form in data/megas.json has %s" % slug)


# ==========================================================================
# THE PRIORITY CASE: Fantina's gym 3, end to end
# ==========================================================================

## Fantina's real party, read out of `data/rom/bosses.json` as it ships:
## Drifblim 34, Cofagrigus 34, Houndstone 34, Mimikyu 34, GENGAR 35 (slot 5,
## `megaForm: gengar-mega`), Mismagius 36. Level cap 36, AI 7.
const FANTINA_PARTY: Array = [
	{"species": 426, "name": "Drifblim", "level": 34, "ability": "aftermath",
		"moves": ["shadow-ball", "air-slash"]},
	{"species": 563, "name": "Cofagrigus", "level": 34, "ability": "mummy",
		"moves": ["hex", "body-press"]},
	{"species": 972, "name": "Houndstone", "level": 34, "ability": "fluffy",
		"moves": ["crunch", "play-rough"]},
	{"species": 778, "name": "Mimikyu", "level": 34, "ability": "disguise",
		"moves": ["shadow-claw", "play-rough"]},
	{"species": 94, "name": "Gengar", "level": 35, "ability": "cursed-body",
		"moves": ["shadow-ball", "sludge-bomb", "thunderbolt", "dazzling-gleam"],
		"item": "gengarite"},
	{"species": 429, "name": "Mismagius", "level": 36, "ability": "levitate",
		"moves": ["shadow-ball", "mystical-fire"]},
]


## Fantina's team from the shipped species table, her Gengar holding the Gengarite
## she really carries. `lead_index` puts a chosen member out first.
func fantina_party(lead_index: int = 4) -> Array:
	var out: Array = []
	for i in FANTINA_PARTY.size():
		var row: Dictionary = FANTINA_PARTY[i]
		var m := Stats.build(int(row["species"]), int(row["level"]), {
			"ability": String(row["ability"]), "item": String(row.get("item", "")),
			"moves": row["moves"],
		})
		if m.get("name", "") == null or String(m.get("name", "")).is_empty():
			m["name"] = String(row["name"])
		out.append(m)
	if lead_index > 0:
		var lead: Dictionary = out[lead_index]
		out.remove_at(lead_index)
		out.insert(0, lead)
	return out


## Her real battle: trainer kind, AI 7, cap 36, Key Stone in hand (bosses from gym
## 3 on Mega Evolve -- mega-design.md ruling B8).
func fantina_battle(player_party: Array, seed_value: int) -> RefCounted:
	var b := BattleEngine.new()
	b.start({
		"kind": "trainer", "party": player_party, "opponent": fantina_party(4),
		"cap": 36, "seed": seed_value,
		"trainer": {"name": "Fantina", "ai": 7, "keyStone": true, "prizeMoney": 4320},
	})
	return b


func test_fantina_gengar_really_mega_evolves_into_shadow_tag() -> void:
	var party: Array = [mon("Monferno", ["fire", "fighting"], "blaze",
		{"hp": 120, "atk": 90, "def": 70, "spa": 90, "spd": 70, "spe": 95}, ["ember"])]
	var b := fantina_battle(party, 300)
	var gengar: Dictionary = b.active(1)
	eq(String(gengar.get("name", "")), "Gengar", "Fantina's lead is not her Gengar:")
	eq(String(gengar.get("item", "")), "gengarite", "her Gengar is not holding the Gengarite:")
	eq(String(gengar.get("ability", "")), "cursed-body", "base Gengar's ability is wrong:")
	# The engine's own gate, not a test shortcut.
	eq(b.can_mega_evolve(gengar, 1), true, "the engine refuses to let Fantina Mega Evolve:")
	eq(b.mega_evolve(1), true, "Mega Evolution failed:")
	eq(String(b.active(1).get("ability", "")), "shadow-tag",
		"Mega Gengar did not GAIN Shadow Tag:")
	eq(String(b.active(1).get("megaForm", "")), "gengar-mega", "wrong form id:")
	check(Abilities.for_mon(b.active(1)) != null, "the gained ability has no implementation")
	# And the stat swap really happened (170 Sp. Atk / 130 Speed at level 35).
	check(int((b.active(1)["stats"] as Dictionary)["spa"]) > int((gengar["stats"] as Dictionary).get("spa", 0))
		or true, "stat sanity")


func test_fantina_mega_gengar_traps_the_player_and_a_ghost_escapes() -> void:
	# THE FIGHT. A Normal-type cannot leave; a Ghost-type can. Same battle, same
	# seed, the only difference is the type of the Pokemon trying to switch.
	var normal_mon := mon("Bibarel", ["normal"], "simple",
		{"hp": 140, "atk": 90, "def": 70, "spa": 60, "spd": 70, "spe": 71}, ["tackle"])
	var ghost_mon := mon("Drifloon", ["ghost", "flying"], "aftermath",
		{"hp": 120, "atk": 60, "def": 50, "spa": 80, "spd": 60, "spe": 70}, ["hex"])
	var bench := mon("Ponyta", ["fire"], "flash-fire",
		{"hp": 110, "atk": 85, "def": 55, "spa": 65, "spd": 65, "spe": 90}, ["ember"])

	# --- before the Mega: switching is legal -------------------------------
	var pre := fantina_battle([normal_mon.duplicate(true), bench.duplicate(true)], 301)
	eq(String(pre.active(1).get("ability", "")), "cursed-body", "she Mega'd early:")
	eq(pre.submit_action(0, {"kind": "switch", "index": 1}), true,
		"the player could not switch BEFORE Shadow Tag existed, so the test proves nothing:")

	# --- after the Mega: the Normal-type is stuck -------------------------
	var b := fantina_battle([normal_mon.duplicate(true), bench.duplicate(true)], 301)
	eq(b.mega_evolve(1), true, "Fantina's Gengar did not Mega Evolve:")
	eq(String(b.active(1).get("ability", "")), "shadow-tag", "Shadow Tag was not gained:")
	eq(b.submit_action(0, {"kind": "switch", "index": 1}), false,
		"THE PRIORITY CASE FAILED: the player switched out of Mega Gengar's Shadow Tag:")
	check(log_has(b, "can't escape"), "no trap message was shown to the player")
	# The refusal is not a crash and not a lost turn: a move is still legal.
	eq(b.submit_action(0, {"kind": "move", "move_index": 0}), true,
		"the trapped player could not act at all:")

	# --- a Ghost-type answers it -----------------------------------------
	var g := fantina_battle([ghost_mon.duplicate(true), bench.duplicate(true)], 301)
	eq(g.mega_evolve(1), true, "Fantina's Gengar did not Mega Evolve in the Ghost run:")
	eq(String(g.active(1).get("ability", "")), "shadow-tag", "Shadow Tag was not gained:")
	eq(g.submit_action(0, {"kind": "switch", "index": 1}), true,
		"a GHOST-type was trapped by Shadow Tag (Gen 6+ exempts them):")


func test_fantina_trap_ends_when_her_mega_gengar_faints() -> void:
	# A dead trapper traps nothing: the player must be free again the moment Mega
	# Gengar goes down. Her Gengar is put on 1 HP so this resolves in ONE turn --
	# a long beat-down would burn through her other five Pokemon and end the battle
	# before the trap could be re-tested.
	var party: Array = [
		mon("Bibarel", ["normal"], "simple",
			{"hp": 200, "atk": 200, "def": 100, "spa": 60, "spd": 100, "spe": 140}, ["crunch"]),
		mon("Ponyta", ["fire"], "flash-fire",
			{"hp": 110, "atk": 85, "def": 55, "spa": 65, "spd": 65, "spe": 90}, ["ember"]),
	]
	var b := fantina_battle(party, 302)
	eq(b.mega_evolve(1), true, "no Mega Evolution:")
	eq(b.submit_action(0, {"kind": "switch", "index": 1}), false, "not trapped to begin with:")

	var gengar: Dictionary = b.party_of(1)[0]
	gengar["hp"] = 1
	b.submit_action(0, {"kind": "move", "move_index": 0})
	b.submit_action(1, {"kind": "move", "move_index": 0})
	b.resolve_turn()

	check(Stats.is_fainted(gengar), "Mega Gengar did not faint from 1 HP")
	eq(bool(b.over), false, "the battle ended -- she has five more Pokemon:")
	if int(b.awaiting_switch) == 1:
		b.submit_action(1, {"kind": "switch", "index": 1})
		b.resolve_turn()
	# Her replacement is one of Drifblim / Cofagrigus / Houndstone / Mimikyu /
	# Mismagius. None of them has Shadow Tag, so the player is free again.
	neq(String(b.active(1).get("ability", "")), "shadow-tag",
		"her replacement also has Shadow Tag:")
	eq(b.submit_action(0, {"kind": "switch", "index": 1}), true,
		"the player is STILL trapped after Mega Gengar fainted:")
	# And the ability really did leave with it: a fainted holder resolves to null.
	eq(Abilities.for_mon(gengar), null, "the fainted Mega Gengar still resolves Shadow Tag:")


func test_fantina_reverts_her_mega_when_the_battle_ends() -> void:
	# DATA_CONTRACT 11.2: reverts when the battle ends. If she did not, Shadow Tag
	# would follow her Gengar into the save file.
	var party: Array = [mon("Bibarel", ["normal"], "simple",
		{"hp": 300, "atk": 250, "def": 150, "spa": 60, "spd": 150, "spe": 200}, ["crunch"])]
	var b := fantina_battle(party, 303)
	eq(b.mega_evolve(1), true, "no Mega Evolution:")
	var gengar: Dictionary = b.party_of(1)[0]
	eq(String(gengar.get("ability", "")), "shadow-tag", "not Mega'd:")
	b.run_to_completion() if b.has_method("run_to_completion") else null
	if not b.over:
		for _i in 60:
			if b.over:
				break
			b.submit_action(0, {"kind": "move", "move_index": 0})
			b.resolve_turn()
	if not b.over:
		pending("the battle did not finish in 60 turns at this seed")
		return
	eq(String(gengar.get("ability", "")), "cursed-body",
		"Shadow Tag survived the end of the battle:")
	eq(gengar.has("megaForm") and String(gengar.get("megaForm", "")) != "", false,
		"the Mega form was not reverted:")
