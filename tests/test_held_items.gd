extends "res://tests/framework/test_case.gd"
## Held items, in battle.
##
## WHY THIS MATTERS BEYOND THE SANDBOX. Before `src/battle/items.gd` a held item
## did two things: `mega.gd` matched a Mega Stone and `exp.gd` looked for a Lucky
## Egg. Everything else was inert -- INCLUDING the items the designed fights hand
## out. 23 boss slots hold a Sitrus Berry, 22 Leftovers, 21 a Life Orb, 14 an
## Expert Belt, and 56 ordinary trainers hold a Sitrus Berry. Every one of those
## rosters was being played without the item it was authored with, so these checks
## are campaign checks, not only Custom Battle ones.
##
## The numbers are pinned deliberately. An item whose multiplier quietly drifts is
## a balance change nothing else in the suite would notice.

const Items := preload("res://src/battle/items.gd")
const Stats := preload("res://src/battle/stats.gd")
const Damage := preload("res://src/battle/damage.gd")
const TurnOrder := preload("res://src/battle/turn_order.gd")
const AI := preload("res://src/battle/ai.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const Deps := preload("res://src/battle/deps.gd")

const ITEMS_PATH := "res://data/items.json"

## Garchomp (Dragon/Ground), Torterra (Grass/Ground), Magikarp, Muk (Poison).
const GARCHOMP := 445
const TORTERRA := 389
const MAGIKARP := 129
const MUK := 89

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
	return DataRegistry.species_count() > 0 and DataRegistry.move_count() > 0


func _mon(species: int, level: int, item: String, moves: Array = []) -> Dictionary:
	return PartyBuilder.wild(species, level,
		{"item": item, "moves": moves if not moves.is_empty() else ["tackle"]})


# --------------------------------------------------------------------------
# Data and engine must agree on what is implemented
# --------------------------------------------------------------------------

func test_the_data_tier_matches_what_the_engine_implements() -> void:
	# `tier: 1` in data/items.json is what the builder UI shows the player. If it
	# claims an item works and items.gd does not implement it, the UI repeats the
	# lie -- which is the exact failure the tier field exists to prevent.
	var text := FileAccess.get_file_as_string(ITEMS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		fail("data/items.json is not valid JSON")
		return
	var rows: Array = parsed if parsed is Array else (parsed as Dictionary).get("items", [])
	var held := 0
	for row: Variant in rows:
		var r: Dictionary = row
		if String(r.get("category", "")) != "held-item":
			continue
		held += 1
		var id := String(r.get("id", ""))
		var tier := int(r.get("tier", 3))
		eq(Items.implemented(id), tier == 1,
			"%s: data says tier %d, items.gd %s implement it" % [
				id, tier, "does" if Items.implemented(id) else "does not"])
	is_true(held >= 20, "the held-item family is built, got %d rows" % held)

	# And the other way: nothing in IMPLEMENTED may be missing from the data, or
	# the builder cannot offer an item the engine acts on.
	for id: String in Items.IMPLEMENTED:
		is_false(Items.row(id).is_empty(), "%s has no row in data/items.json" % id)


# --------------------------------------------------------------------------
# End of turn
# --------------------------------------------------------------------------

func test_leftovers_heals_a_sixteenth() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var mon := _mon(TORTERRA, 50, "leftovers")
	var max_hp := int(mon["maxHp"])
	mon["hp"] = max_hp / 2
	var tick := Items.end_of_turn(mon)
	eq(int(tick["hp_delta"]), max_hp / 16, "one sixteenth of max HP")
	is_true(String((tick["messages"] as Array)[0]).contains("Leftovers"), "and says so")

	mon["hp"] = max_hp
	eq(int(Items.end_of_turn(mon)["hp_delta"]), 0, "nothing to heal at full HP")


func test_black_sludge_depends_on_the_type() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var muk := _mon(MUK, 50, "black-sludge")
	muk["hp"] = int(muk["maxHp"]) / 2
	is_true(int(Items.end_of_turn(muk)["hp_delta"]) > 0, "a Poison-type is healed")

	var karp := _mon(MAGIKARP, 50, "black-sludge")
	karp["hp"] = int(karp["maxHp"])
	var tick := Items.end_of_turn(karp)
	eq(int(tick["hp_delta"]), -maxi(1, int(karp["maxHp"]) / 8), "anything else is hurt for an eighth")


func test_flame_orb_burns_its_holder() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var mon := _mon(TORTERRA, 50, "flame-orb")
	eq(String(Items.end_of_turn(mon)["status"]), "burn", "it burns")
	mon["status"] = "paralysis"
	eq(String(Items.end_of_turn(mon)["status"]), "", "but never overwrites a status")


# --------------------------------------------------------------------------
# Damage multipliers
# --------------------------------------------------------------------------

func _dmg(attacker: Dictionary, defender: Dictionary, move_slug: String) -> int:
	var move := Stats.make_move(move_slug)
	return int(Damage.compute(attacker, defender, move,
		{"roll": 100, "crit": false})["damage"])


func test_life_orb_and_the_band_items_scale_damage() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var plain := _mon(GARCHOMP, 50, "", ["earthquake"])
	var orb := _mon(GARCHOMP, 50, "life-orb", ["earthquake"])
	var band := _mon(GARCHOMP, 50, "muscle-band", ["earthquake"])
	var choice := _mon(GARCHOMP, 50, "choice-band", ["earthquake"])
	var target := _mon(MAGIKARP, 50, "")

	var base := _dmg(plain, target, "earthquake")
	is_true(base > 0, "the baseline hit lands")
	is_true(_dmg(orb, target, "earthquake") > base, "Life Orb hits harder")
	is_true(_dmg(band, target, "earthquake") > base, "Muscle Band hits harder")
	is_true(_dmg(choice, target, "earthquake") > base, "Choice Band hits harder")
	# The Choice item multiplies the STAT, so it beats the flat 1.1 band.
	is_true(_dmg(choice, target, "earthquake") > _dmg(band, target, "earthquake"),
		"and a Choice Band beats a Muscle Band")

	# A special move must not care about a physical booster.
	var special := _mon(GARCHOMP, 50, "choice-band", ["fire-blast"])
	var special_plain := _mon(GARCHOMP, 50, "", ["fire-blast"])
	eq(_dmg(special, target, "fire-blast"), _dmg(special_plain, target, "fire-blast"),
		"a Choice Band does nothing for a special move")


func test_expert_belt_only_pays_on_super_effective() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var belt := _mon(GARCHOMP, 50, "expert-belt", ["earthquake", "dragon-claw"])
	var plain := _mon(GARCHOMP, 50, "", ["earthquake", "dragon-claw"])
	# Earthquake into Magikarp is neutral; into a Steel/Rock target it is 2x.
	var neutral := _mon(MAGIKARP, 50, "")
	eq(_dmg(belt, neutral, "earthquake"), _dmg(plain, neutral, "earthquake"),
		"no boost on a neutral hit")

	var weak_to_ground := _mon(95, 50, "")          # Onix: Rock/Ground, 2x
	if int(weak_to_ground.get("species", 0)) == 95:
		is_true(_dmg(belt, weak_to_ground, "earthquake")
			> _dmg(plain, weak_to_ground, "earthquake"),
			"but it pays on a super effective one")


func test_assault_vest_defends_and_forbids() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var attacker := _mon(GARCHOMP, 50, "", ["fire-blast"])
	var bare := _mon(TORTERRA, 50, "")
	var vested := _mon(TORTERRA, 50, "assault-vest")
	is_true(_dmg(attacker, vested, "fire-blast") < _dmg(attacker, bare, "fire-blast"),
		"a special hit is softened")

	var physical := _mon(GARCHOMP, 50, "", ["earthquake"])
	eq(_dmg(physical, vested, "earthquake"), _dmg(physical, bare, "earthquake"),
		"a physical one is not")

	var status := Stats.make_move("swords-dance")
	var holder := _mon(GARCHOMP, 50, "assault-vest", ["swords-dance", "earthquake"])
	is_false(Items.allows_move(holder, status), "status moves are forbidden")
	is_true(Items.blocks_move(holder, status).contains("Assault Vest"),
		"and the refusal names the item")
	is_true(Items.allows_move(holder, Stats.make_move("earthquake")),
		"attacking moves are fine")


func test_type_boosters_only_boost_their_type() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var target := _mon(MAGIKARP, 50, "")
	var plain := _mon(GARCHOMP, 50, "", ["earthquake", "dragon-claw"])
	var magnet := _mon(GARCHOMP, 50, "magnet", ["earthquake", "dragon-claw"])
	eq(_dmg(magnet, target, "earthquake"), _dmg(plain, target, "earthquake"),
		"a Magnet does nothing for a Ground move")

	# Every booster must name a real type, or it can never fire.
	for item_id: String in Items.TYPE_BOOST:
		var t := String(Items.TYPE_BOOST[item_id])
		is_true(DataRegistry.type_names().has(t), "%s boosts '%s', which must be a type"
			% [item_id, t])


# --------------------------------------------------------------------------
# Triggers
# --------------------------------------------------------------------------

func test_focus_sash_works_once_and_only_from_full_health() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var mon := _mon(MAGIKARP, 50, "focus-sash")
	var max_hp := int(mon["maxHp"])
	var sash := Items.survive_fatal(mon, max_hp * 4)
	is_true(bool(sash["survived"]), "a fatal hit from full HP is survived")
	eq(int(sash["damage"]), max_hp - 1, "leaving exactly 1 HP")
	eq(String(mon["item"]), "", "and the sash is used up")
	eq(String(mon["usedItem"]), "focus-sash", "recorded as used, not as never held")

	var hurt := _mon(MAGIKARP, 50, "focus-sash")
	hurt["hp"] = int(hurt["maxHp"]) - 1
	is_false(bool(Items.survive_fatal(hurt, 9999)["survived"]),
		"below full HP it does nothing")


func test_berries_fire_at_half_health_and_are_eaten() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var mon := _mon(TORTERRA, 50, "sitrus-berry")
	var max_hp := int(mon["maxHp"])
	mon["hp"] = max_hp                      # full: no trigger
	eq(int(Items.low_hp_trigger(mon)["hp_delta"]), 0, "nothing at full health")

	mon["hp"] = max_hp / 2
	var eaten := Items.low_hp_trigger(mon)
	eq(int(eaten["hp_delta"]), maxi(1, max_hp / 4), "Sitrus restores a quarter")
	eq(String(mon["item"]), "", "and is eaten")
	eq(int(Items.low_hp_trigger(mon)["hp_delta"]), 0, "so it cannot fire twice")

	var oran := _mon(TORTERRA, 50, "oran-berry")
	oran["hp"] = int(oran["maxHp"]) / 2
	eq(int(Items.low_hp_trigger(oran)["hp_delta"]), 10, "Oran restores a flat 10")


func test_shuca_berry_softens_one_ground_hit() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var attacker := _mon(GARCHOMP, 50, "", ["earthquake"])
	# Onix is Rock/Ground: 2x to Ground.
	var bare := _mon(95, 50, "")
	var berried := _mon(95, 50, "shuca-berry")
	is_true(_dmg(attacker, berried, "earthquake") < _dmg(attacker, bare, "earthquake"),
		"the super effective Ground hit is halved")

	# THE IMPORTANT HALF: computing damage must not eat the berry. ai.gd scores
	# every legal move through Damage.average() on every turn.
	eq(String(berried["item"]), "shuca-berry",
		"scoring a move must NOT consume the berry")
	var ate := Items.consume_resist_berry(berried, "ground", 2.0)
	eq(String(berried["item"]), "", "the engine eats it explicitly, after the hit")
	is_false((ate["messages"] as Array).is_empty(), "and says so")


func test_rocky_helmet_only_punishes_contact() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var attacker := _mon(GARCHOMP, 50, "")
	var helmet := _mon(TORTERRA, 50, "rocky-helmet")
	var contact := Stats.make_move("tackle")
	var ranged := Stats.make_move("earthquake")
	is_true(PackedStringArray(contact.get("flags", [])).has("contact"), "Tackle makes contact")
	eq(int(Items.contact_punish(attacker, helmet, contact)["hp_delta"]),
		-maxi(1, int(attacker["maxHp"]) / 6), "a sixth of the attacker max HP")
	eq(int(Items.contact_punish(attacker, helmet, ranged)["hp_delta"]), 0,
		"and nothing at all for a move that does not touch")


func test_life_orb_recoil_is_charged_once_per_move() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var mon := _mon(GARCHOMP, 50, "life-orb")
	eq(int(Items.recoil(mon, 120)["hp_delta"]), -maxi(1, int(mon["maxHp"]) / 10),
		"a tenth of max HP")
	eq(int(Items.recoil(mon, 0)["hp_delta"]), 0, "nothing when the move dealt nothing")
	eq(int(Items.recoil(_mon(GARCHOMP, 50, ""), 120)["hp_delta"]), 0, "and nothing without the orb")


# --------------------------------------------------------------------------
# Choice lock
# --------------------------------------------------------------------------

func test_a_choice_item_locks_the_holder_in() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var mon := _mon(GARCHOMP, 50, "choice-band", ["earthquake", "dragon-claw"])
	var quake := Stats.make_move("earthquake")
	var claw := Stats.make_move("dragon-claw")
	is_true(Items.allows_move(mon, claw), "anything goes before the first move")

	Items.note_move_used(mon, "earthquake")
	eq(Items.choice_lock(mon), "earthquake", "the lock remembers the move used")
	is_true(Items.allows_move(mon, quake), "the chosen move is still legal")
	is_false(Items.allows_move(mon, claw), "but nothing else is")
	is_true(Items.blocks_move(mon, claw).contains("locked into"),
		"and the refusal explains itself: %s" % Items.blocks_move(mon, claw))

	# Switching out frees it, and Status.clear_volatiles() is what the engine
	# already calls on a switch.
	Status_clear(mon)
	is_true(Items.allows_move(mon, claw), "switching out clears the lock")

	# Without a Choice item, nothing locks.
	var free := _mon(GARCHOMP, 50, "", ["earthquake", "dragon-claw"])
	Items.note_move_used(free, "earthquake")
	is_true(Items.allows_move(free, claw), "no item, no lock")


func Status_clear(mon: Dictionary) -> void:
	var status := load("res://src/battle/status.gd")
	status.clear_volatiles(mon)


func test_the_ai_never_picks_a_move_its_item_forbids() -> void:
	if not _have_data():
		pending("data is not built")
		return
	# Without this the AI chooses a locked-out move, submit_action refuses it and
	# the side wastes the turn.
	var me := _mon(GARCHOMP, 50, "choice-band", ["earthquake", "dragon-claw"])
	var foe := _mon(TORTERRA, 50, "")
	Items.note_move_used(me, "dragon-claw")
	var scores := AI.score_moves(me, foe, "")
	is_true(float(scores[1]) > float(scores[0]),
		"the locked move must outscore the forbidden one: %s" % [scores])

	var action := AI.choose_action({"self": me, "foe": foe, "bench": [],
		"side": 1, "difficulty": 7, "can_switch": false, "weather": ""})
	eq(int(action.get("move_index", -1)), 1, "so the AI picks the move it is locked into")


# --------------------------------------------------------------------------
# End to end, through the engine
# --------------------------------------------------------------------------

func test_leftovers_actually_heals_during_a_battle() -> void:
	if not _have_data():
		pending("data is not built")
		return
	# Growl: no healing and NO DAMAGE. A healing move would mask the item, and a
	# damaging one would knock the level 5 foe out, ending the battle before
	# _end_of_turn() ever runs -- which is how this check first failed for a
	# reason that had nothing to do with Leftovers.
	var holder := _mon(TORTERRA, 60, "leftovers", ["growl"])
	holder["hp"] = int(holder["maxHp"]) / 2
	var before := int(holder["hp"])
	var foe := _mon(MAGIKARP, 5, "", ["splash"])

	var e := BattleEngineScript.new()
	e.start({"kind": "trainer", "party": [holder], "opponent": [foe],
		"cap": 100, "seed": 3, "awardExp": false, "trainer": {"name": "T", "ai": 0}})
	e.submit_action(0, {"kind": "move", "move_index": 0})
	e.resolve_turn()
	is_true(int(holder["hp"]) > before,
		"HP went up over the turn: %d -> %d" % [before, int(holder["hp"])])
	var saw := false
	for line: String in e.battle_log:
		if line.contains("Leftovers"):
			saw = true
			break
	is_true(saw, "and the log says why")


func test_a_choice_scarf_changes_who_moves_first() -> void:
	if not _have_data():
		pending("data is not built")
		return
	var slow := _mon(TORTERRA, 50, "")
	var scarfed := _mon(TORTERRA, 50, "choice-scarf")
	is_true(TurnOrder.effective_speed(scarfed) > TurnOrder.effective_speed(slow),
		"the scarf raises effective speed: %d vs %d" % [
			TurnOrder.effective_speed(scarfed), TurnOrder.effective_speed(slow)])
	eq(TurnOrder.effective_speed(scarfed),
		maxi(1, floori(float(TurnOrder.effective_speed(slow)) * 1.5)),
		"by exactly half again")
