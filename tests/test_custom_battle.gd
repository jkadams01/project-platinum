extends "res://tests/framework/test_case.gd"
## Custom Battle mode: the spec model, the builder, and one real battle end to end.
##
## THE CHECKS THAT ONLY FAIL WHEN SOMETHING IS ACTUALLY BROKEN
##   * a preset survives a JSON round trip AS INTEGERS (JSON.parse_string returns
##     floats, and a float species id resolves to nothing at all)
##   * `validate` blocks what cannot be played and `advisories` does NOT block what
##     merely bends a learnset -- the boss pre-fill depends on that split
##   * the payload carries `playerKeyStone` and `awardExp`, and the ENGINE honours
##     both: a Mega with no Key Stone in the save, and a battle that awards no EXP
##   * changing a slot's species drops the moves/ability/item that belonged to the
##     old one, rather than leaving the slot illegal
##   * a whole battle runs in watch mode and `GameState` comes out untouched --
##     party, money and bag. The sandbox must never write to the campaign.

const Spec := preload("res://src/custom/battle_spec.gd")
const TeamBuilder := preload("res://src/custom/team_builder.gd")
const Bosses := preload("res://src/systems/bosses.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")
const Stats := preload("res://src/battle/stats.gd")
const Mega := preload("res://src/battle/mega.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const Deps := preload("res://src/battle/deps.gd")

const CUSTOM_SCENE := "res://scenes/CustomBattle.tscn"
const TITLE_SCENE := "res://scenes/Title.tscn"

## Garchomp: has a Mega (garchompite) and a deep learnset. Torterra and Magikarp
## make a fight with exactly one plausible winner, which is what an end-to-end
## check needs.
const GARCHOMP := 445
const TORTERRA := 389
const MAGIKARP := 129

var _saved_level: int = 0
var _nodes: Array = []


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	Deps.clear_overrides()
	DataRegistry.boot(DataRegistry.DATA_DIR)
	EventBus.disconnect_all()
	GameState.track_playtime = false
	GameState.reset()
	Bosses.boot()


func after_each() -> void:
	if SceneRouter.in_battle():
		SceneRouter.exit_battle({})
	for n: Node in _nodes:
		if is_instance_valid(n):
			if n.is_inside_tree():
				tree.root.remove_child(n)
			n.free()
	_nodes.clear()
	SceneRouter.register(null, null)
	SceneRouter.mode = SceneRouter.Mode.BOOT
	EventBus.disconnect_all()
	Deps.clear_overrides()
	GameState.track_playtime = true
	GameState.reset()
	Log.level = _saved_level


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _adopt(node: Node) -> Node:
	_nodes.append(node)
	tree.root.add_child(node)
	return node


## A one-a-side spec with a pinned seed, so every run of it is the same battle.
func _duel_spec(mine: int = TORTERRA, theirs: int = MAGIKARP, level: int = 50) -> Dictionary:
	var spec := Spec.new_spec()
	spec["seed"] = 4242
	(spec["player"]["slots"] as Array)[0] = _slot(mine, level)
	(spec["foe"]["slots"] as Array)[0] = _slot(theirs, level)
	return spec


func _slot(species: int, level: int) -> Dictionary:
	var slot := Spec.new_slot(species, level)
	slot["moves"] = Spec.default_moves(species, level)
	return slot


func _have_data() -> bool:
	return DataRegistry.species_count() > 0 and DataRegistry.move_count() > 0


# --------------------------------------------------------------------------
# The spec model
# --------------------------------------------------------------------------

func test_new_spec_defaults_are_the_safe_ones() -> void:
	var spec := Spec.new_spec()
	eq(String(spec["format"]), "single", "format")
	is_false(bool(spec["awardExp"]), "EXP must default off -- a level-up mid-fight")
	is_false(bool(spec["watch"]), "watch mode defaults off")
	eq(int(spec["seed"]), 0, "seed 0 means a fresh one each battle")
	eq((spec["player"]["slots"] as Array).size(), Spec.MAX_SLOTS, "player slots")
	eq((spec["foe"]["slots"] as Array).size(), Spec.MAX_SLOTS, "foe slots")
	is_true(bool(spec["player"]["keyStone"]), "Megas available by default")


func test_json_round_trip_keeps_integers() -> void:
	# THE trap: JSON.parse_string makes every number a float, and 445.0 != 445 in
	# a Dictionary lookup, so a reloaded preset would resolve to no species at all.
	var spec := _duel_spec()
	var reloaded: Variant = JSON.parse_string(JSON.stringify(spec))
	if not (reloaded is Dictionary):
		fail("a spec did not survive JSON.stringify")
		return
	var raw_species: Variant = ((reloaded as Dictionary)["player"]["slots"] as Array)[0]["species"]
	eq(typeof(raw_species), TYPE_FLOAT, "raw JSON really does hand back a float")

	var fixed := Spec.normalize(reloaded as Dictionary)
	var slot: Dictionary = (fixed["player"]["slots"] as Array)[0]
	is_int(slot["species"], "normalized species")
	is_int(slot["level"], "normalized level")
	is_int(fixed["seed"], "normalized seed")
	eq(int(slot["species"]), TORTERRA, "species value")
	eq(int(fixed["seed"]), 4242, "seed value")


func test_normalize_pads_and_clamps() -> void:
	var fixed := Spec.normalize({
		"format": "hexuple", "seed": 9, "player": {"slots": [{"species": 1, "level": 900}]},
		"foe": {"ai": 99, "slots": []},
	})
	eq(String(fixed["format"]), "single", "an unknown format falls back")
	eq((fixed["player"]["slots"] as Array).size(), Spec.MAX_SLOTS, "short team is padded")
	eq(int((fixed["player"]["slots"] as Array)[0]["level"]), Spec.MAX_LEVEL, "level clamped")
	eq(int(fixed["foe"]["ai"]), 10, "ai clamped to 0-10")


func test_legal_pools_are_real() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var moves := Spec.legal_moves(GARCHOMP)
	is_true(moves.size() > 20, "Garchomp should have a deep pool, got %d" % moves.size())
	is_true(moves.has("dragon-claw"), "a level-up move is in the pool")
	is_false(moves.has("thunderbolt"), "Garchomp cannot learn Thunderbolt")
	# Every offered slug must build, or the mon quietly comes out short.
	for slug in moves:
		if Stats.make_move(slug).is_empty():
			fail("legal_moves offered '%s', which make_move() cannot build" % slug)
			break

	var abilities := Spec.legal_abilities(GARCHOMP)
	is_true(abilities.has("sand-veil"), "normal ability")
	is_true(abilities.has("rough-skin"), "hidden ability is offered too")

	if Mega.form_count() <= 0:
		pending("data/megas.json is not built")
		return
	is_true(Spec.item_choices(GARCHOMP).has("garchompite"), "its own stone is offered")
	is_false(Spec.item_choices(MAGIKARP).has("garchompite"), "someone else stone is not")


func test_validate_blocks_only_the_unplayable() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	is_true(Spec.validate(_duel_spec()).is_empty(), "a plain duel is playable")

	var empty := Spec.new_spec()
	is_false(Spec.validate(empty).is_empty(), "two empty teams cannot fight")

	var doubles := _duel_spec()
	doubles["format"] = "double"
	var problems := Spec.validate(doubles)
	is_false(problems.is_empty(), "doubles are not implemented and must be refused")
	is_true(String(problems[0]).to_lower().contains("not implemented"),
		"and the refusal must say why: %s" % problems[0])

	var bad_species := _duel_spec()
	(bad_species["player"]["slots"] as Array)[0]["species"] = 99999
	is_false(Spec.validate(bad_species).is_empty(), "an unknown species is blocking")

	var bad_move := _duel_spec()
	(bad_species["player"]["slots"] as Array)[0]["species"] = TORTERRA
	(bad_move["player"]["slots"] as Array)[0]["moves"] = ["hyper-nonsense"]
	is_false(Spec.validate(bad_move).is_empty(),
		"a slug make_move() would silently drop is blocking")


func test_advisories_do_not_block() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	# Torterra cannot learn Thunderbolt, but the move exists -- so the battle is
	# buildable and must be allowed. This is what makes the boss pre-fill work.
	var spec := _duel_spec()
	(spec["player"]["slots"] as Array)[0]["moves"] = ["thunderbolt"]
	is_true(Spec.validate(spec).is_empty(), "an illegal-but-real move must not block")
	var notes := Spec.advisories(spec)
	is_false(notes.is_empty(), "but it must be reported")
	is_true(String(notes[0]).contains("cannot learn"), "with the reason: %s" % notes[0])

	# An Oran Berry used to be inert -- src/battle/items.gd implements it now, so
	# the same roster item that Roark Roggenrola carries actually heals.
	var berry := _duel_spec()
	(berry["player"]["slots"] as Array)[0]["item"] = "oran-berry"
	is_true(Spec.validate(berry).is_empty(), "a held berry does not block")
	is_true(Spec.item_is_live((berry["player"]["slots"] as Array)[0]),
		"and is live, because the engine reads it")

	# Booster Energy USED to be the counter-example here; it works now that
	# protosynthesis.gd and quark-drive.gd exist. An evolution item is the honest
	# one: holdable, real, and doing nothing whatever in a battle.
	var inert := _duel_spec()
	(inert["player"]["slots"] as Array)[0]["item"] = "razor-claw"
	is_true(Spec.validate(inert).is_empty(), "an item with no battle effect does not block")
	is_false(Spec.item_is_live((inert["player"]["slots"] as Array)[0]),
		"but it is marked inert rather than pretending to work")
	is_true(Spec.item_is_live({"species": GARCHOMP, "item": "booster-energy"}),
		"while Booster Energy is live now that the Paradox abilities exist")


func test_build_mon_uses_the_slot() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var slot := Spec.new_slot(GARCHOMP, 62)
	slot["nature"] = "jolly"
	slot["ability"] = "rough-skin"
	slot["item"] = "garchompite"
	slot["moves"] = ["dragon-claw", "earthquake"]
	var mon := Spec.build_mon(slot)
	eq(int(mon["species"]), GARCHOMP, "species")
	eq(int(mon["level"]), 62, "level")
	eq(String(mon["nature"]), "jolly", "nature")
	eq(String(mon["ability"]), "rough-skin", "ability")
	eq(String(mon["item"]), "garchompite", "held item")
	eq((mon["moves"] as Array).size(), 2, "exactly the two moves asked for")
	eq(int(mon["hp"]), int(mon["maxHp"]), "starts at full HP")

	# An untouched slot still fights: the learnset fills it in.
	var rolled := Spec.build_mon(Spec.new_slot(GARCHOMP, 50))
	is_true((rolled["moves"] as Array).size() > 0, "a slot with no moves gets a moveset")


func test_to_setup_is_the_battle_payload() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var setup := Spec.to_setup(_duel_spec())
	eq(String(setup["kind"]), "trainer", "a custom battle is a trainer battle")
	eq(int(setup["cap"]), 100, "no campaign cap in the sandbox")
	eq(int(setup["seed"]), 4242, "the pinned seed travels")
	eq((setup["party"] as Array).size(), 1, "one Pokemon a side")
	eq((setup["opponent"] as Array).size(), 1, "one Pokemon a side")
	has_key(setup, "playerKeyStone", "the Key Stone override")
	is_false(bool(setup["awardExp"]), "EXP off by default")
	is_false((setup["trainer"] as Dictionary).has("prizeMoney"),
		"NO prize money -- the engine pays it into GameState.add_money()")

	var doubles := _duel_spec()
	doubles["format"] = "triple"
	is_true(Spec.to_setup(doubles).is_empty(), "an unplayable spec yields no payload")


# --------------------------------------------------------------------------
# The engine honours the two new payload fields
# --------------------------------------------------------------------------

func test_player_key_stone_overrides_the_save() -> void:
	if not _have_data() or Mega.form_count() <= 0:
		pending("data/species.json or data/megas.json is not built")
		return
	is_false(GameState.has_key_stone(), "the save must start without one")
	var mon := PartyBuilder.wild(GARCHOMP, 50,
		{"item": "garchompite", "moves": ["dragon-claw"]})
	var foe := PartyBuilder.wild(MAGIKARP, 5, {"moves": ["splash"]})

	var granted := BattleEngineScript.new()
	granted.start({"kind": "trainer", "party": [mon.duplicate(true)],
		"opponent": [foe.duplicate(true)], "cap": 100, "seed": 1,
		"trainer": {"name": "T", "ai": 5}, "playerKeyStone": true})
	is_true(granted.can_mega_evolve(granted.active(0), 0),
		"playerKeyStone true must enable the Mega with no Key Stone in the bag")

	var denied := BattleEngineScript.new()
	denied.start({"kind": "trainer", "party": [mon.duplicate(true)],
		"opponent": [foe.duplicate(true)], "cap": 100, "seed": 1,
		"trainer": {"name": "T", "ai": 5}, "playerKeyStone": false})
	is_false(denied.can_mega_evolve(denied.active(0), 0), "and false must deny it")

	var absent := BattleEngineScript.new()
	absent.start({"kind": "trainer", "party": [mon.duplicate(true)],
		"opponent": [foe.duplicate(true)], "cap": 100, "seed": 1,
		"trainer": {"name": "T", "ai": 5}})
	is_false(absent.can_mega_evolve(absent.active(0), 0),
		"omitting it must leave campaign behaviour exactly as it was")


func test_award_exp_false_awards_nothing_and_says_nothing() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var winner := PartyBuilder.wild(TORTERRA, 50, {"moves": ["wood-hammer", "earthquake"]})
	var loser := PartyBuilder.wild(MAGIKARP, 5, {"moves": ["splash"]})

	var off := BattleEngineScript.new()
	off.start({"kind": "trainer", "party": [winner.duplicate(true)],
		"opponent": [loser.duplicate(true)], "cap": 100, "seed": 11,
		"trainer": {"name": "T", "ai": 5}, "awardExp": false})
	off.run_to_completion()
	eq(String(off.outcome), "win", "the level 50 should win")
	eq(off.exp_awarded, 0, "no EXP with awardExp false")
	for line: String in off.battle_log:
		if line.contains("EXP") or line.contains("level cap"):
			fail("awardExp false must not talk about EXP or caps: '%s'" % line)
			break

	# The flag is what did it, not the cap: the same fight with EXP on pays out.
	var on := BattleEngineScript.new()
	on.start({"kind": "trainer", "party": [winner.duplicate(true)],
		"opponent": [loser.duplicate(true)], "cap": 100, "seed": 11,
		"trainer": {"name": "T", "ai": 5}, "awardExp": true})
	on.run_to_completion()
	is_true(on.exp_awarded > 0, "EXP on must award some, got %d" % on.exp_awarded)


# --------------------------------------------------------------------------
# Pre-fill
# --------------------------------------------------------------------------

func test_boss_prefill_is_editable_and_playable() -> void:
	if Bosses.count() <= 0:
		pending("data/rom/bosses.json is not built (it is gitignored; needs the ROMs)")
		return
	var keys := Bosses.keys()
	var key := "roark" if Bosses.has("roark") else String(keys[0])
	var team := Spec.from_boss(key, Bosses)
	is_false(team.is_empty(), "a boss roster should import")
	eq((team["slots"] as Array).size(), Spec.MAX_SLOTS, "always six slots")
	is_true(Spec.filled_slots(team).size() > 0, "and some of them filled")
	eq(bool(team["keyStone"]), Bosses.get_boss(key).get("megaForm", null) != null,
		"Key Stone must match Bosses.trainer_block(): only a boss with a Mega gets one")

	var first: Dictionary = Spec.filled_slots(team)[0]
	is_int(first["species"], "imported species")
	is_int(first["level"], "imported level")

	# The whole point of the split: an authored roster must be PLAYABLE as it is.
	var spec := Spec.new_spec()
	spec["foe"] = team
	(spec["player"]["slots"] as Array)[0] = _slot(TORTERRA, 50)
	var problems := Spec.validate(spec)
	is_true(problems.is_empty(),
		"a boss roster must not be blocked: %s" % ("" if problems.is_empty() else problems[0]))


func test_from_party_copies_the_live_moveset() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var mon := PartyBuilder.wild(TORTERRA, 33, {"moves": ["crunch", "earthquake"]})
	var team := Spec.from_party([mon], "You")
	var slot: Dictionary = Spec.filled_slots(team)[0]
	eq(int(slot["species"]), TORTERRA, "species")
	eq(int(slot["level"]), 33, "level")
	eq((slot["moves"] as Array).size(), 2, "both moves came across")
	is_true((slot["moves"] as Array).has("crunch"), "as slugs, not display names")


func test_random_team_is_buildable() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var team := Spec.random_team(rng, 6, 50)
	eq(Spec.filled_slots(team).size(), 6, "six random Pokemon")
	for slot: Dictionary in Spec.filled_slots(team):
		if Spec.build_mon(slot).is_empty():
			fail("a random slot did not build: %s" % slot)
			break


# --------------------------------------------------------------------------
# Presets
# --------------------------------------------------------------------------

func test_preset_round_trip() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var spec := _duel_spec(GARCHOMP, TORTERRA, 77)
	var saved := Spec.save_preset(spec, "Test Matchup!!")
	eq(saved, "test-matchup", "the name is sanitised into something path-safe")
	is_true(Spec.list_presets().has(saved), "and it shows up in the listing")

	var loaded := Spec.load_preset(saved)
	is_false(loaded.is_empty(), "it loads back")
	var slot: Dictionary = (loaded["player"]["slots"] as Array)[0]
	is_int(slot["species"], "and comes back as ints, not JSON floats")
	eq(int(slot["species"]), GARCHOMP, "species survived")
	eq(int(slot["level"]), 77, "level survived")
	eq(int(loaded["seed"]), 4242, "the pinned seed survived -- this is the rematch")

	is_true(Spec.delete_preset(saved), "and it can be deleted")
	is_false(Spec.list_presets().has(saved), "leaving no trace")
	eq(Spec.sanitize_name("!!!"), "", "a name with nothing usable is refused")


# --------------------------------------------------------------------------
# The builder
# --------------------------------------------------------------------------

func test_changing_species_drops_what_belonged_to_the_old_one() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var builder := TeamBuilder.new()
	builder.spec = _duel_spec(GARCHOMP, MAGIKARP, 50)
	var slot: Dictionary = (builder.spec["player"]["slots"] as Array)[0]
	slot["ability"] = "rough-skin"
	slot["item"] = "garchompite"
	slot["moves"] = ["dragon-claw"]
	_adopt(builder)

	builder.debug_focus(0, 0)
	builder.debug_edit_field("species")
	builder.debug_pick(TORTERRA)

	var after: Dictionary = (builder.spec["player"]["slots"] as Array)[0]
	eq(int(after["species"]), TORTERRA, "species changed")
	eq(String(after["ability"]), "", "Garchomp ability dropped")
	eq(String(after["item"]), "", "Garchomp stone dropped")
	is_false((after["moves"] as Array).has("dragon-claw"),
		"and its moves with it -- Torterra cannot learn Dragon Claw")
	is_true((after["moves"] as Array).size() > 0, "the new species gets its own moveset")
	is_true(Spec.advisories(builder.spec).is_empty(),
		"so the slot is left legal, with nothing to report")


func test_the_species_picker_finds_by_number_name_and_type() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var builder := TeamBuilder.new()
	builder.spec = _duel_spec()
	_adopt(builder)
	builder.debug_focus(0, 0)
	builder.debug_edit_field("species")
	var picker: Control = builder._picker
	is_true(picker.is_open(), "the species picker opened")
	eq(picker.match_count(), DataRegistry.species_count(), "unfiltered, it offers all of them")

	# 1. by dex number
	picker.filter("445")
	is_true(picker.match_ids().has(GARCHOMP), "445 finds Garchomp")

	# 2. by name, including a partial one
	picker.filter("garchomp")
	eq(picker.match_count(), 1, "a full name narrows to exactly one")
	eq(int(picker.match_ids()[0]), GARCHOMP, "and it is the right one")
	is_true(picker.filter("garch") >= 1, "a partial name still finds it")

	# 3. by type -- the new part. The note column abbreviates Dragon/Ground to
	#    DRA/GRO, so this only works if the full type names are searchable too.
	var dragons: int = picker.filter("dragon")
	is_true(dragons > 20, "dragon lists the Dragon-types, got %d" % dragons)
	is_true(picker.match_ids().has(GARCHOMP), "including Garchomp")
	is_true(picker.match_ids().has(149), "and Dragonite")
	is_false(picker.match_ids().has(MAGIKARP), "but not a Water-type")

	picker.filter("ground")
	is_true(picker.match_ids().has(GARCHOMP), "its second type finds it too")

	# A type the note shows in full rather than abbreviated.
	picker.filter("water")
	is_true(picker.match_ids().has(MAGIKARP), "water finds Magikarp")
	is_false(picker.match_ids().has(GARCHOMP), "and not Garchomp")

	picker.filter("")
	eq(picker.match_count(), DataRegistry.species_count(), "clearing restores the list")


func test_picker_rows_show_what_they_can_be_searched_by() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var builder := TeamBuilder.new()
	builder.spec = _duel_spec()
	_adopt(builder)
	builder.debug_focus(0, 0)
	builder.debug_edit_field("species")
	var picker: Control = builder._picker
	picker.filter("garchomp")
	var row: Dictionary = picker.current()
	eq(String(row["label"]), "445 Garchomp", "the row shows the number and the name")
	eq(String(row["note"]), "DRA/GRO", "and the types, abbreviated to fit the column")
	eq(TeamBuilder.type_note(["water"]), "WATER", "a single type is not abbreviated")
	eq(TeamBuilder.type_note([]), "", "and a species with no types shows nothing")


func test_every_move_slot_writes_to_its_own_slot() -> void:
	# REGRESSION. The picker purpose used to be re-encoded as a 0-based index and
	# decoded with the 1-based field rule, so MOVE 1 silently did nothing and
	# MOVE 2-4 each overwrote the slot above. Picking a move for ONE slot and
	# checking that slot alone would not have caught it -- this walks all four.
	if not _have_data():
		pending("data/species.json is not built")
		return
	var builder := TeamBuilder.new()
	builder.spec = _duel_spec(GARCHOMP, MAGIKARP, 50)
	var slot: Dictionary = (builder.spec["player"]["slots"] as Array)[0]
	var starting: Array = (slot["moves"] as Array).duplicate()
	is_true(starting.size() >= 1, "the slot starts with a moveset")
	_adopt(builder)
	builder.debug_focus(0, 0)

	# Four legal slugs it does not already know, so every write is observable.
	var picks: Array = []
	for slug in Spec.legal_moves(GARCHOMP):
		if not starting.has(slug) and picks.size() < Spec.MAX_MOVES:
			picks.append(slug)
	if picks.size() < Spec.MAX_MOVES:
		pending("Garchomp has too few spare legal moves to test with")
		return

	# The exact symptom first: MOVE 1, on its own, must change.
	builder.debug_edit_field("move1")
	builder.debug_pick(picks[0])
	eq(String((slot["moves"] as Array)[0]), String(picks[0]),
		"MOVE 1 must take the move it was given")

	for i in range(1, Spec.MAX_MOVES):
		builder.debug_edit_field("move%d" % (i + 1))
		builder.debug_pick(picks[i])
		eq(String((slot["moves"] as Array)[i]), String(picks[i]),
			"MOVE %d must take the move it was given" % (i + 1))

	eq((slot["moves"] as Array).size(), Spec.MAX_MOVES, "four moves, no more")
	for i in Spec.MAX_MOVES:
		eq(String((slot["moves"] as Array)[i]), String(picks[i]),
			"and slot %d still holds its own move at the end" % (i + 1))

	# The screen has to agree with the data, which is the half a data-only
	# assertion misses -- the bug was visible on screen as an unchanged row.
	builder.debug_edit_field("move2")
	builder._on_pick_cancelled()
	is_true(builder.debug_field_text("move2").contains(Spec.pretty(String(picks[1]))),
		"the MOVE 2 row shows '%s', got '%s'" % [
			Spec.pretty(String(picks[1])), builder.debug_field_text("move2")])

	# (empty) clears a slot and closes the gap, so Stats.build gets a dense array.
	builder.debug_edit_field("move2")
	builder.debug_pick("")
	eq((slot["moves"] as Array).size(), Spec.MAX_MOVES - 1, "clearing removes one move")
	eq(String((slot["moves"] as Array)[1]), String(picks[2]),
		"and closes the gap rather than leaving a hole")


func test_the_move_picker_explains_what_a_move_does() -> void:
	if not _have_data():
		pending("data/moves.json is not built")
		return

	var slide: Dictionary = DataRegistry.get_move_by_name("rock-slide")
	eq(TeamBuilder.move_note(slide), "ROCK 75 PHY",
		"the row shows type, power and category")
	var line := TeamBuilder.move_stats_line(slide)
	is_true(line.begins_with("PHYSICAL"), "the detail line leads with the category: %s" % line)
	is_true(line.contains("PWR 75"), "power: %s" % line)
	is_true(line.contains("ACC 90"), "accuracy: %s" % line)
	is_true(line.contains("PP 10"), "PP: %s" % line)
	is_false(line.contains("PRI"), "and says nothing about priority when it is 0")
	eq(TeamBuilder.move_effect_text(slide), "30% chance to make the target flinch.",
		"the effect reads as a sentence, with the chance in front")

	# A status move: no power, and DATA_CONTRACT 2 says a null accuracy NEVER
	# MISSES -- drawing that as 0 would be the opposite of the truth.
	var dance: Dictionary = DataRegistry.get_move_by_name("swords-dance")
	eq(TeamBuilder.move_note(dance), "NORM - STA", "a status move has no power")
	is_true(TeamBuilder.move_stats_line(dance).contains("PWR -"), "shown as a dash")
	# Swords Dance has an accuracy in the data; Aerial Ace is the null case.
	var ace: Dictionary = DataRegistry.get_move_by_name("aerial-ace")
	is_true(TeamBuilder.move_stats_line(ace).contains("ACC always"),
		"null accuracy is 'always', not 0: %s" % TeamBuilder.move_stats_line(ace))

	# 246 of 919 effect strings carry a possessive that slugification flattened to
	# a lone "s". Rejoining without restoring it reads as a typo.
	eq(TeamBuilder.move_effect_text(dance), "Raises the user's attack by two stages.",
		"the possessive apostrophe comes back")

	# Priority and contact are the two things that change how a turn plays out.
	var speed: Dictionary = DataRegistry.get_move_by_name("extreme-speed")
	is_true(TeamBuilder.move_stats_line(speed).contains("PRI +2"),
		"priority is shown with its sign: %s" % TeamBuilder.move_stats_line(speed))
	is_true(TeamBuilder.move_effect_text(speed).contains("Makes contact"),
		"and contact, which is what the ability layer branches on")

	# 92 moves have no effect text (an upstream veekun gap). Say so; a blank line
	# reads as a broken UI rather than as a real hole in the data.
	var gap := TeamBuilder.move_effect_text({"effect": null, "pp": 5})
	is_true(gap.contains("no effect text"), "a missing effect is stated: '%s'" % gap)
	eq(TeamBuilder.move_effect_text({}), "", "and an unknown move contributes nothing")


func test_the_move_picker_shows_the_detail_of_the_highlighted_row() -> void:
	if not _have_data():
		pending("data/moves.json is not built")
		return
	var builder := TeamBuilder.new()
	builder.spec = _duel_spec(GARCHOMP, MAGIKARP, 50)
	_adopt(builder)
	builder.debug_focus(0, 0)
	builder.debug_edit_field("move1")
	var picker: Control = builder._picker
	is_true(picker.is_open(), "the move picker opened")

	eq(picker.filter("rock slide"), 1, "one match")
	var row: Dictionary = picker.current()
	is_true(String(row.get("detail", "")).contains("PHYSICAL"),
		"the highlighted row carries its stat line")
	is_true(String(row.get("effect", "")).contains("flinch"),
		"and its effect text")

	# Category is searchable because it is on the row.
	var physical: int = picker.filter("physical")
	is_true(physical > 10, "filtering by category works, got %d" % physical)
	is_true(picker.filter("special") > 0, "both ways")

	# Detail costs rows, and the list has to stay usable.
	is_true(picker.ROWS_WITH_DETAIL >= 8,
		"a detail picker still shows %d rows" % picker.ROWS_WITH_DETAIL)


func test_the_species_picker_shows_base_stats() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var sp: Dictionary = DataRegistry.get_species(GARCHOMP)
	var line := TeamBuilder.base_stat_line(sp)
	is_true(line.contains("HP 108"), "HP: %s" % line)
	is_true(line.contains("ATK 130"), "Attack: %s" % line)
	is_true(line.contains("SPE 102"), "Speed: %s" % line)
	# The total is what separates a Bidoof from a Garchomp at a glance.
	is_true(line.contains("BST 600"), "and the total: %s" % line)
	eq(TeamBuilder.base_stat_line({}), "", "an unknown species contributes nothing")

	var blurb := TeamBuilder.species_blurb(sp)
	is_true(blurb.begins_with("Dragon/Ground"),
		"both types are capitalised, not just the first: %s" % blurb)
	is_true(blurb.contains("Sand Veil"), "its normal ability: %s" % blurb)
	is_true(blurb.contains("Rough Skin (hidden)"),
		"and the hidden one, marked as hidden: %s" % blurb)

	var builder := TeamBuilder.new()
	builder.spec = _duel_spec()
	_adopt(builder)
	builder.debug_focus(0, 0)
	builder.debug_edit_field("species")
	var picker: Control = builder._picker
	picker.filter("garchomp")
	is_true(String(picker.current().get("detail", "")).contains("BST 600"),
		"and the picker row carries it")


func test_the_ability_picker_says_whether_an_ability_works() -> void:
	if not _have_data():
		pending("data/abilities.json is not built")
		return
	# The slug is what species.abilities holds; a by-id-only lookup would make
	# every caller scan the table.
	var rough: Dictionary = DataRegistry.get_ability_by_name("rough-skin")
	is_false(rough.is_empty(), "abilities are reachable by slug")
	eq(String(rough.get("name", "")), "Rough Skin", "and it is the right row")
	is_true(DataRegistry.get_ability_by_name("Rough Skin").has("id"),
		"the display name works too, like get_move_by_name")
	is_true(DataRegistry.get_ability_by_name("no-such-ability").is_empty(),
		"and an unknown slug is empty, not a half-row")

	is_true(TeamBuilder.ability_text(rough).length() > 10,
		"the description comes from the data: %s" % TeamBuilder.ability_text(rough))

	# DATA_CONTRACT 4 tier: 1 implemented, 2 declared but inert, 3 data only.
	# In a battle sandbox, picking an ability that silently does nothing is a bad
	# surprise, so the row says which it is.
	eq(TeamBuilder.ability_note({"tier": 1}), "works", "tier 1")
	eq(TeamBuilder.ability_note({"tier": 2}), "inert", "tier 2")
	eq(TeamBuilder.ability_note({"tier": 3}), "no effect", "tier 3")
	is_true(TeamBuilder.ability_status({"tier": 1, "hook": "onContactHit"})
		.contains("IMPLEMENTED"), "tier 1 says so")
	is_true(TeamBuilder.ability_status({"tier": 1, "hook": "onContactHit"})
		.contains("onContactHit"), "and names the engine seam it uses")
	is_true(TeamBuilder.ability_status({"tier": 2}).contains("nothing in battle"),
		"tier 2 is honest about doing nothing")
	is_true(TeamBuilder.ability_status({"tier": 3}).contains("nothing in battle"),
		"and so is tier 3")
	eq(TeamBuilder.ability_text({"text": ""}), "(no description in the data)",
		"a missing description is stated rather than left blank")

	# Stench is tier 3 in the data and Skuntank has it -- a real end-to-end case.
	var stench: Dictionary = DataRegistry.get_ability_by_name("stench")
	if stench.is_empty():
		pending("stench is not in data/abilities.json")
		return
	eq(int(stench.get("tier", 0)), 3, "stench is data only")
	is_true(TeamBuilder.ability_status(stench).contains("DATA ONLY"),
		"so the picker warns before it is chosen")


func test_builder_refuses_an_unplayable_start() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var builder := TeamBuilder.new()
	builder.spec = Spec.new_spec()          # two empty teams
	_adopt(builder)
	var started := [false]
	builder.start_requested.connect(func(_s: Dictionary) -> void: started[0] = true)
	builder.debug_start()
	is_false(started[0], "an empty matchup must not start")
	is_true(builder.debug_status().to_lower().contains("no pokemon"),
		"and must say why: '%s'" % builder.debug_status())


func test_builder_reports_a_locked_format_without_changing_the_engine() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	var builder := TeamBuilder.new()
	builder.spec = _duel_spec()
	_adopt(builder)
	builder.debug_option("format")
	builder.debug_pick("rotation")
	eq(String(builder.spec["format"]), "rotation", "the choice is remembered")
	var started := [false]
	builder.start_requested.connect(func(_s: Dictionary) -> void: started[0] = true)
	builder.debug_start()
	is_false(started[0], "but it cannot be played")
	is_true(builder.debug_status().to_lower().contains("not implemented"),
		"and the refusal names the reason: '%s'" % builder.debug_status())


# --------------------------------------------------------------------------
# End to end
# --------------------------------------------------------------------------

func test_a_whole_custom_battle_runs_and_leaves_the_save_alone() -> void:
	if not _have_data():
		pending("data/species.json is not built")
		return
	if not ResourceLoader.exists(CUSTOM_SCENE):
		fail("%s is missing" % CUSTOM_SCENE)
		return

	# A campaign state worth protecting.
	GameState.money = 1234
	GameState.party = [PartyBuilder.wild(TORTERRA, 9, {"moves": ["tackle"]})]
	GameState.bag = {"potion": 3}
	var party_size := GameState.party.size()
	var party_hp := int((GameState.party[0] as Dictionary)["hp"])
	var party_level := int((GameState.party[0] as Dictionary)["level"])

	var scene: Node = (load(CUSTOM_SCENE) as PackedScene).instantiate()
	_adopt(scene)
	is_true(SceneRouter.is_registered(), "the mode registers its own holders")

	var spec := _duel_spec(TORTERRA, MAGIKARP, 50)
	spec["watch"] = true                    # both sides on AI, so no input is needed
	scene.builder.spec = spec
	var used_seed: int = scene.debug_launch(spec)
	eq(used_seed, 4242, "it ran with the pinned seed")
	is_true(SceneRouter.in_battle(), "and the router entered a battle")

	var battle: Node = SceneRouter.active_battle()
	if battle == null:
		fail("no battle scene was instanced")
		return
	# Watch mode resolves a turn whenever the log empties, so paging the log is the
	# only thing driving the fight -- exactly as holding A would.
	var lines: int = battle.debug_flush_log(4000)
	is_true(lines > 0, "the battle produced a log")
	is_false(SceneRouter.in_battle(), "and finished, after %d lines" % lines)

	is_true(scene.debug_result_visible(), "the result panel is up")
	is_true(scene.debug_result_text().contains("4242"), "and shows the seed for a rematch")
	is_false(bool(scene.builder.active), "the builder is not also reading the keyboard")

	eq(GameState.money, 1234, "money untouched -- no prizeMoney in the payload")
	eq(GameState.party.size(), party_size, "party size untouched")
	eq(int((GameState.party[0] as Dictionary)["hp"]), party_hp, "party HP untouched")
	eq(int((GameState.party[0] as Dictionary)["level"]), party_level, "party level untouched")
	eq(int(GameState.bag.get("potion", 0)), 3, "bag untouched")
	is_false(GameState.has_key_stone(), "and the save still has no Key Stone")


func test_the_title_screen_points_at_scenes_that_exist() -> void:
	var title := preload("res://src/title.gd")
	is_true(ResourceLoader.exists(title.CAMPAIGN_SCENE),
		"campaign scene %s" % title.CAMPAIGN_SCENE)
	is_true(ResourceLoader.exists(title.CUSTOM_SCENE),
		"custom battle scene %s" % title.CUSTOM_SCENE)
	is_true(ResourceLoader.exists(TITLE_SCENE), "and the title scene itself")
	eq(String(ProjectSettings.get_setting("application/run/main_scene", "")), TITLE_SCENE,
		"the title screen is the main scene")
