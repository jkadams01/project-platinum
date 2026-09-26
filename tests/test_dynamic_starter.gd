extends "res://tests/framework/test_case.gd"
## Barry's dynamic starter: the rival carries the starter that counters the
## player's, in all seven of his fights.
##
## WHAT THIS FILE IS REALLY GUARDING. Substituting the species id is the easy
## half and it is not the bug. `data/rom/bosses.json` tags one slot per Barry
## fight, and that slot is AUTHORED AS THE CHIMCHAR LINE -- four hand-picked
## Fire/Fighting moves and Blaze (Iron Fist from r5 on). Swap the species without
## re-resolving those and a player who picks Chimchar faces an Empoleon holding
## Mach Punch and Ember, at full legality, with no error logged anywhere. A test
## that checks only `mon["species"]` sails straight past it. So every check here
## asks about the moves and the ability too.
##
## The rule itself (`Bosses.resolve_rival_starter`) is pure and is tested without
## any table at all. `data/rom/**` is gitignored, so the checks that need Barry's
## real roster degrade to `pending()` on a fresh checkout.

const Bosses := preload("res://src/systems/bosses.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")
const Deps := preload("res://src/battle/deps.gd")

## The three lines, lowest form first. Duplicated from the data on purpose: a test
## that reads its expectations out of the same table it is testing proves nothing.
const TURTWIG: Array = [387, 388, 389]
const CHIMCHAR: Array = [390, 391, 392]
const PIPLUP: Array = [393, 394, 395]

## Every Barry fight, and the stage its tagged slot carries.
const BARRY_FIGHTS: Array = [
	["barry_r1_route_201", 0],
	["barry_r2_route_203", 1],
	["barry_r3_route_209", 2],
	["barry_r4_pastoria", 2],
	["barry_r5_canalave", 2],
	["barry_r6_spear_pillar_ally", 2],
	["barry_r7_pokemon_league", 2],
]

var _saved_level: int = 0


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
	EventBus.disconnect_all()
	GameState.track_playtime = true
	GameState.reset()
	Log.level = _saved_level


func _have_barry() -> bool:
	return Bosses.count() > 0 and Bosses.has("barry_r1_route_201")


## A stand-in for Barry's late tagged slot: Infernape, authored with the Chimchar
## line's moves and its HIDDEN ability, exactly as the roster writes it.
func _tagged_member(stage: int = 2, level: int = 66, species: int = 392) -> Dictionary:
	return {
		"species": species,
		"speciesName": "Infernape",
		"level": level,
		"moves": ["mach-punch", "flare-blitz", "close-combat", "u-turn"],
		"item": "oran-berry",
		"ability": "iron-fist",
		"abilitySlot": 0,
		"nature": null,
		"megaEvolves": false,
		"megaForm": null,
		"dynamicSlot": "rival-starter",
		"starterStage": stage,
		"placeholderSpecies": species,
	}


## The move slugs on a built mon.
func _slugs(mon: Dictionary) -> Array:
	var out: Array = []
	for m: Variant in (mon.get("moves", []) as Array):
		out.append(String((m as Dictionary).get("slug", "")))
	return out


## Every ability the species may legally have: its normal slots plus its hidden.
func _legal_abilities(species_id: int) -> Array:
	var sp: Dictionary = DataRegistry.get_species(species_id)
	var out: Array = (sp.get("abilities", []) as Array).duplicate()
	if sp.get("hiddenAbility", null) != null:
		out.append(String(sp["hiddenAbility"]))
	return out


# ==========================================================================
# the rule, with no table involved
# ==========================================================================

## The counter map has to be a closed three-cycle, or some choice leaves Barry
## with nothing -- and every line has to have three stages for the tags to index.
func test_the_counter_map_is_a_closed_three_cycle() -> void:
	var counter := Bosses.starter_counter()
	var lines := Bosses.starter_lines()
	eq(counter.size(), 3, "three choices")
	eq(lines.size(), 3, "three lines")

	var seen: Array = []
	for choice: Variant in counter:
		var theirs := String(counter[choice])
		is_true(lines.has(theirs), "%s -> %s, which is a real line" % [choice, theirs])
		neq(theirs, String(choice), "%s never counters itself" % choice)
		is_false(seen.has(theirs), "%s is Barry's answer to exactly one pick" % theirs)
		seen.append(theirs)

	for k: Variant in lines:
		eq((lines[k] as Array).size(), 3, "the %s line has three stages" % k)


func test_resolve_picks_the_counter_line_at_the_right_stage() -> void:
	var lines := Bosses.starter_lines()
	var counter := Bosses.starter_counter()
	# Turtwig -> Chimchar -> Piplup -> Turtwig, each with the type advantage.
	var expected: Dictionary = {
		"turtwig": CHIMCHAR, "chimchar": PIPLUP, "piplup": TURTWIG,
	}
	for choice: String in expected:
		for stage: int in [0, 1, 2]:
			eq(Bosses.resolve_rival_starter(choice, stage, lines, counter),
				int((expected[choice] as Array)[stage]),
				"%s + stage %d" % [choice, stage])


## The choice is a Dictionary key, so case and stray whitespace would silently
## resolve to nothing at all.
func test_the_choice_is_normalised() -> void:
	var lines := Bosses.starter_lines()
	var counter := Bosses.starter_counter()
	eq(Bosses.resolve_rival_starter("TURTWIG", 0, lines, counter), 390, "upper case")
	eq(Bosses.resolve_rival_starter("  Piplup ", 2, lines, counter), 389, "padded and mixed")


func test_an_unusable_choice_resolves_to_zero_rather_than_guessing() -> void:
	var lines := Bosses.starter_lines()
	var counter := Bosses.starter_counter()
	eq(Bosses.resolve_rival_starter("", 0, lines, counter), 0, "no choice recorded yet")
	eq(Bosses.resolve_rival_starter("bulbasaur", 0, lines, counter), 0, "not a Sinnoh starter")
	eq(Bosses.resolve_rival_starter("turtwig", 0, {}, counter), 0, "no lines")
	eq(Bosses.resolve_rival_starter("turtwig", 0, lines, {}), 0, "no counter map")


## A roster that ever tags a stage past the end of a line should get the final
## form, not a crash and not species 0.
func test_the_stage_is_clamped_to_the_line() -> void:
	var lines := Bosses.starter_lines()
	var counter := Bosses.starter_counter()
	eq(Bosses.resolve_rival_starter("turtwig", 9, lines, counter), 392, "past the end")
	eq(Bosses.resolve_rival_starter("turtwig", -3, lines, counter), 390, "before the start")


## `boot.gd` records the choice from the species it handed over, so this lookup is
## the only thing keeping a second copy of the starter list out of the codebase.
func test_starter_slug_for_finds_the_line_from_any_stage() -> void:
	eq(Bosses.starter_slug_for(387), "turtwig", "base form")
	eq(Bosses.starter_slug_for(389), "turtwig", "final form")
	eq(Bosses.starter_slug_for(391), "chimchar", "middle form")
	eq(Bosses.starter_slug_for(395), "piplup", "final form")
	eq(Bosses.starter_slug_for(25), "", "Pikachu is not a Sinnoh starter")


# ==========================================================================
# the substitution -- moves and ability, which is where the bug lives
# ==========================================================================

## THE trap test. Torterra replaces the authored Infernape and must not keep one
## single thing that belonged to the Chimchar line.
func test_a_substituted_slot_resolves_its_moves_from_the_new_species() -> void:
	var member := _tagged_member()
	var mon := PartyBuilder.from_boss_member(member, 389)   # Torterra
	if mon.is_empty():
		pending("data/species.json did not resolve Torterra")
		return

	eq(int(mon["species"]), 389, "the species really was substituted")

	var got := _slugs(mon)
	is_false(got.is_empty(), "and it has moves")
	for authored: String in ["mach-punch", "flare-blitz", "close-combat", "u-turn"]:
		is_false(got.has(authored),
			"'%s' is Infernape's, not Torterra's, and did not carry over" % authored)

	# Positively: exactly what Torterra knows by level 66.
	eq(got, Array(PartyBuilder.moves_at_level(389, 66)),
		"the moveset is Torterra's own learnset roll")

	# And nothing it holds is a Fire move, which is the visible symptom.
	for m: Variant in (mon["moves"] as Array):
		neq(String((m as Dictionary).get("type", "")), "fire",
			"a Grass/Ground Pokemon carries no Fire move")


## The authored `iron-fist` is Infernape's HIDDEN ability, so the substitute gets
## ITS hidden ability -- Shell Armor -- not Overgrow and not a copied `iron-fist`,
## which Torterra cannot legally have.
func test_a_hidden_ability_maps_to_the_substitutes_hidden_ability() -> void:
	var mon := PartyBuilder.from_boss_member(_tagged_member(), 389)
	if mon.is_empty():
		pending("data/species.json did not resolve Torterra")
		return
	eq(String(mon["ability"]), "shell-armor", "hidden maps to hidden")
	is_true(_legal_abilities(389).has(String(mon["ability"])), "and it is legal for Torterra")

	var emp := PartyBuilder.from_boss_member(_tagged_member(), 395)   # Empoleon
	eq(String(emp["ability"]), "competitive", "and hidden-to-hidden again for Empoleon")


## An authored PRIMARY ability maps to the substitute's primary. Barry's early
## fights use Blaze, which must become Overgrow or Torrent.
func test_a_primary_ability_maps_to_the_substitutes_primary() -> void:
	var member := _tagged_member(0, 5, 390)
	member["ability"] = "blaze"
	member["speciesName"] = "Chimchar"

	var turt := PartyBuilder.from_boss_member(member, 387)
	if turt.is_empty():
		pending("data/species.json did not resolve Turtwig")
		return
	eq(String(turt["ability"]), "overgrow", "Blaze -> Overgrow")

	var pip := PartyBuilder.from_boss_member(member, 393)
	eq(String(pip["ability"]), "torrent", "Blaze -> Torrent")


## The mon is named after what it actually is. The authored `speciesName` names
## the placeholder, so keeping it would put "Infernape" over a Torterra's HP bar.
func test_the_substitute_is_not_named_after_the_placeholder() -> void:
	var mon := PartyBuilder.from_boss_member(_tagged_member(), 389)
	if mon.is_empty():
		pending("data/species.json did not resolve Torterra")
		return
	eq(String(mon["name"]), "Torterra", "named for the substituted species")
	neq(String(mon["name"]), "Infernape", "not for the placeholder")


## Sprites and icons are looked up from `mon["species"]` at draw time
## (`battle_screen._set_sprite`), so the substituted id is the whole fix -- but it
## has to actually be the substituted id in the built mon, which is what this
## pins down alongside the species record it resolves to.
func test_sprite_lookup_follows_the_substituted_dex_id() -> void:
	var mon := PartyBuilder.from_boss_member(_tagged_member(), 389)
	if mon.is_empty():
		pending("data/species.json did not resolve Torterra")
		return
	var sp: Dictionary = DataRegistry.get_species(int(mon["species"]))
	eq(String(sp.get("name", "")), "Torterra", "the species record is Torterra's")
	var sprite: Dictionary = sp.get("sprite", {})
	if sprite.is_empty():
		pending("data/species.json carries no sprite block")
		return
	for which: String in ["front", "back", "icon"]:
		is_true(String(sprite.get(which, "")).contains("389"),
			"the %s path is Torterra's (%s)" % [which, sprite.get(which, "")])


## Species-agnostic fields are the ones that SHOULD survive: the held item is a
## design decision about the fight, not about the Pokemon.
func test_the_item_survives_the_substitution() -> void:
	var mon := PartyBuilder.from_boss_member(_tagged_member(), 389)
	if mon.is_empty():
		pending("data/species.json did not resolve Torterra")
		return
	eq(String(mon["item"]), "oran-berry", "the authored item carried over")
	eq(int(mon["level"]), 66, "and the authored level")


# ==========================================================================
# what must NOT change
# ==========================================================================

## With no override the designed roster is used verbatim -- that is the contract
## for all thirty other bosses and the override must not have loosened it.
func test_without_an_override_the_authored_roster_is_verbatim() -> void:
	var member := _tagged_member()
	var mon := PartyBuilder.from_boss_member(member)
	if mon.is_empty():
		pending("data/species.json did not resolve Infernape")
		return
	eq(int(mon["species"]), 392, "the stored species")
	eq(String(mon["ability"]), "iron-fist", "the authored ability, verbatim")
	eq(String(mon["name"]), "Infernape", "the authored speciesName")
	var got := _slugs(mon)
	for authored: String in ["mach-punch", "flare-blitz", "close-combat", "u-turn"]:
		is_true(got.has(authored), "the authored move '%s' is kept" % authored)


## An override that names the species already stored is not a substitution, so it
## must not trigger the re-resolution path.
func test_an_override_equal_to_the_stored_species_is_a_no_op() -> void:
	var mon := PartyBuilder.from_boss_member(_tagged_member(), 392)
	if mon.is_empty():
		pending("data/species.json did not resolve Infernape")
		return
	eq(String(mon["ability"]), "iron-fist", "authored ability untouched")
	is_true(_slugs(mon).has("flare-blitz"), "authored moves untouched")


## `bosses.json` is the design document. Resolving a fight must never write to it,
## or a second playthrough in the same session inherits the first one's rival.
func test_building_a_party_never_mutates_the_member_row() -> void:
	var member := _tagged_member()
	var before := member.duplicate(true)
	PartyBuilder.from_boss_member(member, 389)
	eq(member, before, "the member Dictionary is unchanged")
	eq(int(member["species"]), 392, "still the placeholder species")


# ==========================================================================
# against Barry's real roster
# ==========================================================================

## Every one of the seven fights, for every one of the three choices: the right
## species, and a moveset and ability that species can actually have.
##
## The roster is authored as the CHIMCHAR line, so the player picking Turtwig is
## the one case where the resolved species is the stored one -- and then the
## hand-designed moveset is kept verbatim, which is the whole point of authoring
## it. The other two choices are genuine substitutions and roll the learnset.
func test_every_barry_fight_resolves_for_every_choice() -> void:
	if not _have_barry():
		pending("data/rom/bosses.json is not built")
		return
	var expected: Dictionary = {"turtwig": CHIMCHAR, "chimchar": PIPLUP, "piplup": TURTWIG}

	for choice: String in expected:
		GameState.set_starter_choice(choice)
		for row: Array in BARRY_FIGHTS:
			var key := String(row[0])
			if not Bosses.has(key):
				pending("%s is not in the table" % key)
				continue
			var stage := int(row[1])
			var want := int((expected[choice] as Array)[stage])
			var tagged := _tagged_slot_of(key)
			if tagged.is_empty():
				fail("%s has no slot tagged %s" % [key, Bosses.DYNAMIC_RIVAL_STARTER])
				continue
			var stored := int(tagged.get("species", 0))

			var party := Bosses.build_party(key)
			var found := false
			for mon: Dictionary in party:
				if int(mon.get("species", 0)) != want:
					continue
				found = true
				if want == stored:
					# Not a substitution: the designed moveset must survive.
					eq(_slugs(mon), Array(tagged.get("moves", [])),
						"%s / %s: the authored moveset is kept" % [key, choice])
				else:
					eq(_slugs(mon), Array(PartyBuilder.moves_at_level(want, int(mon["level"]))),
						"%s / %s: the substitute's moves are its own" % [key, choice])
				is_true(_legal_abilities(want).has(String(mon["ability"])),
					"%s / %s: '%s' is legal for species %d"
					% [key, choice, mon["ability"], want])
				break
			is_true(found, "%s / %s: species %d is in the party" % [key, choice, want])


## The `dynamicSlot` member of a fight, or {} when it has none.
func _tagged_slot_of(key: String) -> Dictionary:
	for member: Variant in (Bosses.get_boss(key).get("party", []) as Array):
		if member is Dictionary 				and String((member as Dictionary).get("dynamicSlot", "")) == Bosses.DYNAMIC_RIVAL_STARTER:
			return member
	return {}


## Two different choices must produce two different rivals, from the same table,
## in the same session. This is the check that a cached or mutated row breaks.
func test_two_choices_in_a_row_produce_different_rivals() -> void:
	if not _have_barry():
		pending("data/rom/bosses.json is not built")
		return
	var key := "barry_r5_canalave"
	if not Bosses.has(key):
		pending("%s is not in the table" % key)
		return

	GameState.set_starter_choice("turtwig")
	var first: Array = []
	for mon: Dictionary in Bosses.build_party(key):
		first.append(int(mon["species"]))

	GameState.set_starter_choice("chimchar")
	var second: Array = []
	for mon: Dictionary in Bosses.build_party(key):
		second.append(int(mon["species"]))

	neq(first, second, "the rival changed with the choice")
	is_true(first.has(392), "Turtwig faces Infernape")
	is_true(second.has(395), "Chimchar faces Empoleon")
	# and the rest of the roster did not move
	eq(first.size(), second.size(), "same party size")


## With no choice recorded the fight still has to start. The placeholder is a
## legal Pokemon; a party that comes back short is a broken game.
func test_an_unrecorded_choice_falls_back_to_the_placeholder() -> void:
	if not _have_barry():
		pending("data/rom/bosses.json is not built")
		return
	var key := "barry_r5_canalave"
	if not Bosses.has(key):
		pending("%s is not in the table" % key)
		return
	GameState.set_starter_choice("")
	var party := Bosses.build_party(key)
	eq(party.size(), (Bosses.get_boss(key)["party"] as Array).size(),
		"the party is still full")
	var placeholders: Array = []
	for member: Variant in (Bosses.get_boss(key)["party"] as Array):
		placeholders.append(int((member as Dictionary).get("species", 0)))
	for mon: Dictionary in party:
		is_true(placeholders.has(int(mon["species"])), "every mon is a stored species")


## Barry Mega Evolves Staraptor, never his starter. If a roster edit ever moves
## the Mega onto the dynamic slot, the substituted species would need a Mega form
## of its own and none of the three lines has one -- so catch it here.
func test_barrys_mega_is_never_the_dynamic_slot() -> void:
	if not _have_barry():
		pending("data/rom/bosses.json is not built")
		return
	var checked := 0
	for row: Array in BARRY_FIGHTS:
		var key := String(row[0])
		if not Bosses.has(key):
			continue
		var boss := Bosses.get_boss(key)
		var party: Array = boss.get("party", [])
		for i in party.size():
			var member: Dictionary = party[i]
			if String(member.get("dynamicSlot", "")) != Bosses.DYNAMIC_RIVAL_STARTER:
				continue
			checked += 1
			is_false(bool(member.get("megaEvolves", false)),
				"%s slot %d does not Mega Evolve" % [key, i])
			if boss.get("megaSlot", null) != null:
				neq(int(boss["megaSlot"]), i,
					"%s's Mega slot is not the dynamic slot" % key)
	is_true(checked > 0, "at least one tagged slot was checked (%d)" % checked)


# ==========================================================================
# persistence
# ==========================================================================

## The choice drives all seven fights, so losing it on load would silently
## re-roll Barry's starter mid-playthrough. Disk round-trip lives in
## test_save_system.gd; this is the pure dictionary round-trip.
func test_the_choice_round_trips_through_to_dict() -> void:
	GameState.set_starter_choice("Piplup")
	eq(GameState.starter_choice, "piplup", "stored normalised")
	var d := GameState.to_dict()
	has_key(d, "starterChoice", "the save carries it")

	GameState.reset()
	eq(GameState.starter_choice, "", "reset really cleared it")

	is_true(GameState.from_dict(d), "load succeeded")
	eq(GameState.starter_choice, "piplup", "and the choice came back")


## An older save has no `starterChoice`. It must load, not be rejected, and leave
## the choice empty so the placeholder path takes over.
func test_a_save_without_the_field_still_loads() -> void:
	var d := GameState.to_dict()
	d.erase("starterChoice")
	is_true(GameState.from_dict(d), "a save predating the field still loads")
	eq(GameState.starter_choice, "", "with no choice recorded")
