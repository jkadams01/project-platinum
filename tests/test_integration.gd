extends "res://tests/framework/test_case.gd"
## THE END-TO-END TESTS. Everything else in this suite tests one module against
## fixtures; this file boots the real `scenes/Boot.tscn` against the real `data/`
## and asks whether the game actually works.
##
## WHAT IT IS FOR. The engine modules were written in parallel and each one's own
## tests pass, which says nothing about whether they agree with each other. These
## are the checks that only fail when the seams are wrong:
##   * Boot.tscn produces a world, a party and a registered router
##   * the battle scene is at the path SceneRouter loads it from
##   * a `data/rom/bosses.json` roster survives the trip through
##     `bosses.gd` -> `party_builder.gd` -> `stats.gd` -> `battle_engine.gd`
##   * beating Roark awards the badge, raises the hard cap 18 -> 27 and unlocks
##     SMASH, in that order, off one call
##   * a Pokemon at the cap earns exactly zero EXP from a real battle
##
## `data/rom/**` is gitignored, so every boss check degrades to `pending()` on a
## fresh checkout rather than failing.

const Bosses := preload("res://src/systems/bosses.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")
const Stats := preload("res://src/battle/stats.gd")
const BattleEngineScript := preload("res://src/battle/battle_engine.gd")
const Deps := preload("res://src/battle/deps.gd")
const Collision := preload("res://src/systems/collision.gd")

const BOOT_SCENE := "res://scenes/Boot.tscn"
const BATTLE_SCENE := "res://scenes/Battle.tscn"

## Torterra: Grass/Ground, so it is 4x into nothing on Roark's team and 2x on most
## of it. A deterministic winner, which is what a rewards test needs.
const STRONG_SPECIES := 389

var _saved_level: int = 0
var _boot: Node = null


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
	if _boot != null and is_instance_valid(_boot):
		if _boot.is_inside_tree():
			tree.root.remove_child(_boot)
		_boot.free()
	_boot = null
	SceneRouter.register(null, null)
	SceneRouter.mode = SceneRouter.Mode.BOOT
	EventBus.disconnect_all()
	Deps.clear_overrides()
	GameState.track_playtime = true
	GameState.reset()
	DataRegistry.boot(DataRegistry.DATA_DIR)
	Log.level = _saved_level


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

func _boot_the_game() -> Node:
	var packed: PackedScene = load(BOOT_SCENE) as PackedScene
	if packed == null:
		fail("could not load %s" % BOOT_SCENE)
		return null
	_boot = packed.instantiate()
	tree.root.add_child(_boot)
	return _boot


## A party that beats Roark from any seed: six Torterra well above his level. Their
## level is deliberately far above the cap, which is also what makes them the right
## subject for the "zero EXP at the cap" check.
func _strong_party(level: int = 50, size: int = 3) -> Array:
	var party: Array = []
	for _i in size:
		party.append(PartyBuilder.wild(STRONG_SPECIES, level, {"moves": [
			"wood-hammer", "earthquake", "crunch", "synthesis"]}))
	return party


func _have_bosses() -> bool:
	return Bosses.count() > 0 and Bosses.has("roark")


# --------------------------------------------------------------------------
# Boot
# --------------------------------------------------------------------------

func test_the_boot_scene_produces_a_world_a_party_and_a_registered_router() -> void:
	var main := _boot_the_game()
	if main == null:
		return
	await tree.process_frame

	# the shape SceneRouter's contract requires
	check(main.get_node_or_null("WorldHolder") != null, "WorldHolder exists")
	check(main.get_node_or_null("BattleHolder") != null, "BattleHolder exists")
	check(main.get_node_or_null("UILayer") != null, "UILayer exists")
	is_true(SceneRouter.is_registered(), "the router was handed both holders")
	eq(SceneRouter.mode, SceneRouter.Mode.OVERWORLD, "boots into the overworld")
	is_false(SceneRouter.in_battle(), "not in a battle")

	# the world
	var ow: Node2D = main.get("overworld")
	check(ow != null, "the Overworld instance was created")
	if ow == null:
		return
	check(ow.get("map") != null, "a map is loaded")
	eq(String(GameState.current_map), "twinleaf_town", "starts in Twinleaf Town")
	check(is_instance_valid(ow.get("player")), "the player node exists")
	var cell: Vector2i = GameState.player_cell
	is_true(Collision.LAND_CODES.has(int((ow.get("map") as Object).code_at(cell))),
		"the player spawned on a walkable tile %s" % cell)

	# the camera must NOT be a child of the Overworld: load_map() frees those
	var holder: Node = main.get_node("WorldHolder")
	check(holder.get_node_or_null("Camera") != null,
		"the camera is a sibling of the Overworld, so a warp cannot free it")

	# the party
	is_true(GameState.party.size() >= 1, "the player has a starter")
	var starter: Dictionary = GameState.party[0]
	is_true(int(starter.get("level", 0)) >= 1, "the starter has a level")
	is_true(int(starter.get("maxHp", 0)) > 0, "the starter has HP")
	is_true((starter.get("moves", []) as Array).size() >= 1,
		"the starter knows at least one move, so it is not stuck on Struggle")
	for m: Dictionary in (starter.get("moves", []) as Array):
		is_true(int(m.get("pp", 0)) > 0, "move '%s' has PP" % m.get("name"))


func test_a_warp_moves_the_player_between_two_real_maps() -> void:
	var main := _boot_the_game()
	if main == null:
		return
	await tree.process_frame
	var ow: Node2D = main.get("overworld")
	if ow == null:
		return

	# Twinleaf's only exit, taken as data rather than as a hard-coded cell.
	var warps: Dictionary = (ow.get("map") as Object).warps
	if not check(not warps.is_empty(), "twinleaf_town declares a warp"):
		return
	var from: Vector2i = warps.keys()[0]
	var w: Dictionary = warps[from]

	is_true(ow.call("load_map", String(w["to"]), Vector2i(int(w["toX"]), int(w["toY"]))),
		"loaded %s" % w["to"])
	eq(String(GameState.current_map), String(w["to"]), "GameState followed the warp")
	eq(GameState.player_cell, Vector2i(int(w["toX"]), int(w["toY"])), "arrival cell")
	var dest: Object = ow.get("map")
	is_true(Collision.LAND_CODES.has(int(dest.code_at(GameState.player_cell))),
		"arrived on a walkable tile")
	check(is_instance_valid(ow.get("player")), "the player survived the map swap")
	check(main.get_node("WorldHolder").get_node_or_null("Camera") != null,
		"and so did the camera")


func test_the_battle_scene_is_where_the_router_looks_for_it() -> void:
	is_true(ResourceLoader.exists(BATTLE_SCENE), "%s exists" % BATTLE_SCENE)
	eq(SceneRouter.DEFAULT_BATTLE_SCENE, BATTLE_SCENE,
		"the router's default path points at the scene that exists")
	var packed: PackedScene = load(BATTLE_SCENE) as PackedScene
	if not check(packed != null, "it loads as a PackedScene"):
		return
	var inst := packed.instantiate()
	check(inst != null, "it instantiates")
	is_true(inst.has_method("setup"), "it exposes setup(), which is how the router feeds it")
	inst.free()


# --------------------------------------------------------------------------
# Roark
# --------------------------------------------------------------------------

func test_roarks_roster_matches_the_contract() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	var boss := Bosses.get_boss("roark")
	eq(String(boss["name"]), "Roark", "name")
	eq(String(boss["badge"]), "coal", "badge")
	eq(int(boss["cap"]), 18, "the cap in force during the fight")
	eq((boss["party"] as Array).size(), Bosses.PARTY_SIZE, "exactly 6 Pokemon")

	var ace: Dictionary = boss["ace"]
	eq(int(ace["species"]), 408, "the ace is Cranidos")
	eq(int(ace["level"]), 18, "at level 18")
	is_true(int(ace["species"]) >= 387 and int(ace["species"]) <= 493,
		"the ace is a Gen 4 species (dex 387-493)")
	eq(int(ace["level"]), int(boss["cap"]), "ace.level equals the cap, so the fight is level-matched")

	var highest := -1
	for member: Dictionary in (boss["party"] as Array):
		is_true(int(member["level"]) <= int(boss["cap"]),
			"%s L%d is at or under the cap" % [member.get("speciesName"), int(member["level"])])
		highest = maxi(highest, int(member["level"]))
	eq(highest, int(ace["level"]), "the ace is the highest level on the team")
	eq(int(ace["slot"]), 5, "the ace is sent out last")
	eq(int((boss["party"] as Array).size()) - 1, int(ace["slot"]), "ace.slot indexes the last member")

	# gym 1 -- nothing Mega Evolves before gym 3 (Fantina)
	eq(boss.get("megaForm", null), null, "Roark has no Mega form")
	eq(boss.get("megaSlot", null), null, "and no Mega slot")
	eq(String(boss["awardsStone"]), "aerodactylite", "he still awards Aerodactylite")


func test_roarks_party_builds_into_six_usable_battle_pokemon() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	var party := Bosses.build_party("roark")
	eq(party.size(), 6, "six built")
	var authored: Array = (Bosses.get_boss("roark") as Dictionary)["party"]
	for i in party.size():
		var mon: Dictionary = party[i]
		var src: Dictionary = authored[i]
		eq(int(mon["species"]), int(src["species"]), "slot %d species" % i)
		eq(int(mon["level"]), int(src["level"]), "slot %d level" % i)
		is_true(int(mon["maxHp"]) > 0, "slot %d has HP" % i)
		eq(int(mon["hp"]), int(mon["maxHp"]), "slot %d starts at full HP" % i)
		is_false(Stats.is_fainted(mon), "slot %d is not fainted" % i)
		# the authored moveset is used verbatim -- these rosters are designed
		eq((mon["moves"] as Array).size(), (src["moves"] as Array).size(),
			"slot %d kept all %d authored moves" % [i, (src["moves"] as Array).size()])
		for m: Dictionary in (mon["moves"] as Array):
			is_true(int(m["pp"]) > 0, "slot %d move '%s' has PP" % [i, m["name"]])
		if src.get("ability", null) != null:
			eq(String(mon["ability"]), String(src["ability"]), "slot %d ability" % i)
		var six := mon["stats"] as Dictionary
		for key: String in ["hp", "atk", "def", "spa", "spd", "spe"]:
			is_true(int(six[key]) > 0, "slot %d stat %s" % [i, key])


func test_roark_never_mega_evolves_because_he_is_gym_one() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	var block := Bosses.trainer_block("roark")
	is_false(bool(block["keyStone"]),
		"a gym-1 boss must not be handed the Key Stone (nothing Megas before gym 3)")

	var engine := BattleEngineScript.new()
	engine.start(Bosses.battle_setup("roark", _strong_party(), 99))
	for mon: Dictionary in engine.party_of(1):
		is_false(bool(engine.can_mega_evolve(mon, 1)),
			"%s must not be able to Mega Evolve" % Stats.display_name(mon))
	for member: Dictionary in ((Bosses.get_boss("roark") as Dictionary)["party"] as Array):
		is_false(bool(member.get("megaEvolves", false)),
			"%s is not flagged megaEvolves" % member.get("speciesName"))


func test_a_full_roark_fight_resolves_to_a_definite_outcome() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	var engine := BattleEngineScript.new()
	var setup := Bosses.battle_setup("roark", _strong_party(), 20250923)
	engine.start(setup)
	eq(String(engine.kind), "trainer", "a boss fight is a trainer battle")
	eq(engine.party_of(1).size(), 6, "six on the other side")
	eq(int(engine.current_cap()), GameState.current_level_cap(), "the fight runs under the live cap")

	var r := engine.run_to_completion()
	is_true(bool(r["over"]), "the battle ended")
	is_true(["win", "loss", "run", "draw"].has(String(r["outcome"])),
		"a real outcome, got '%s'" % r["outcome"])
	eq(String(r["outcome"]), "win", "an overlevelled Grass/Ground party beats a Rock gym")
	is_true((r["log"] as Array).size() > 6, "the battle produced a log")
	var joined := String("\n").join(PackedStringArray(r["log"]))
	is_true(joined.contains("Roark"), "Roark is named in the log")
	# every one of his six must be down for a win
	for mon: Dictionary in engine.party_of(1):
		is_true(Stats.is_fainted(mon), "%s fainted" % Stats.display_name(mon))


func test_beating_roark_awards_the_badge_the_cap_raise_and_aerodactylite() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	eq(GameState.cap_index, 0, "starts on cap row 0")
	eq(GameState.current_level_cap(), 18, "the starting cap is Roark's ace level")
	is_false(GameState.has_badge("coal"), "no Coal badge yet")
	is_false(GameState.can_traverse("smash"), "SMASH is locked")
	is_false(Bosses.is_defeated("roark"), "not yet defeated")

	var raised: Array = []
	EventBus.level_cap_raised.connect(func(o: int, n: int, i: int) -> void: raised.append([o, n, i]))
	var badges: Array = []
	EventBus.badge_earned.connect(func(b: StringName) -> void: badges.append(String(b)))

	var reward := Bosses.apply_victory("roark")

	is_true(GameState.get_flag("roark_defeated"), "flag:roark_defeated is set")
	is_true(Bosses.is_defeated("roark"), "is_defeated agrees")
	is_true(GameState.has_badge("coal"), "the Coal badge was earned")
	eq(badges, ["coal"], "badge_earned fired once, for coal")

	# the cap raise: row 1 is `raisedBy badge:coal`, so clearing it moves to row 2
	eq(GameState.cap_index, 2, "cap row advanced past the Roark row")
	eq(GameState.current_level_cap(), 27, "the cap rose 18 -> 27 (Gardenia's ace)")
	eq(int(reward["capBefore"]), 18, "reward reports the old cap")
	eq(int(reward["capAfter"]), 27, "reward reports the new cap")
	eq(raised.size(), 1, "level_cap_raised fired once")
	eq(raised[0], [18, 27, 2], "with the right payload")

	# SMASH
	is_true(GameState.can_traverse("smash"), "SMASH is unlocked")
	is_true((reward["verbs"] as PackedStringArray).has("smash"), "the reward names SMASH")
	is_false(GameState.can_traverse("cut"), "and nothing else came with it")

	# the stone
	eq(Array(reward["stones"] as PackedStringArray), ["aerodactylite"], "Aerodactylite awarded")
	eq(int(GameState.bag.get("aerodactylite", 0)), 1, "and it is in the bag")
	is_false(GameState.has_key_stone(),
		"but no Key Stone -- the Ring comes after Fantina, so the stone is dormant")
	is_false(GameState.mega_unlocked(), "Mega Evolution is still locked")

	is_true((reward["messages"] as Array).size() >= 3, "there is something to put on screen")


func test_a_second_victory_over_roark_awards_nothing_twice() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	Bosses.apply_victory("roark")
	var cap := GameState.current_level_cap()
	var stones := int(GameState.bag.get("aerodactylite", 0))

	var again := Bosses.apply_victory("roark")
	eq(GameState.current_level_cap(), cap, "the cap did not move again")
	eq(int(GameState.bag.get("aerodactylite", 0)), stones, "no duplicate stone")
	eq((again["messages"] as Array).size(), 0, "and nothing new to announce")


func test_an_unknown_boss_key_refuses_instead_of_crashing() -> void:
	Log.level = Log.Level.OFF
	is_false(Bosses.has("definitely_not_a_boss"), "not in the table")
	eq(Bosses.get_boss("definitely_not_a_boss"), {}, "empty row")
	eq(Bosses.build_party("definitely_not_a_boss"), [], "empty party")
	eq(Bosses.battle_setup("definitely_not_a_boss", []), {}, "no setup")
	var reward := Bosses.apply_victory("definitely_not_a_boss")
	eq(String(reward["badge"]), "", "no badge")
	eq(GameState.cap_index, 0, "the cap did not move")


# --------------------------------------------------------------------------
# The level cap, through a real battle
# --------------------------------------------------------------------------

func test_a_pokemon_at_the_cap_earns_zero_exp_from_a_real_boss_fight() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	var capped: Array = []
	EventBus.exp_capped.connect(func(mon: Dictionary, c: int) -> void: capped.append([mon, c]))

	# level 50 against a cap of 18: every one of these is over the line
	var party := _strong_party(50, 2)
	var before: Array = []
	for mon: Dictionary in party:
		before.append(int(mon.get("exp", 0)))

	var engine := BattleEngineScript.new()
	engine.start(Bosses.battle_setup("roark", party, 7777))
	var r := engine.run_to_completion()
	eq(String(r["outcome"]), "win", "won the fight")

	eq(int(r["expAwarded"]), 0, "the whole fight awarded 0 EXP")
	for i in party.size():
		eq(int((party[i] as Dictionary).get("exp", 0)), int(before[i]),
			"party member %d gained no EXP at all" % i)
	is_true(capped.size() > 0, "EventBus.exp_capped fired")
	for entry: Array in capped:
		eq(int(entry[1]), 18, "the cap reported was the live one")
	is_true(int(r["money"]) > 0, "prize money is not capped -- only EXP is")


func test_a_pokemon_below_the_cap_does_earn_exp_from_the_same_fight() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	# One under the cap to be paid, one well over it to carry the fight.
	var learner := PartyBuilder.wild(STRONG_SPECIES, 10, {"moves": ["wood-hammer", "earthquake"]})
	var carry := PartyBuilder.wild(STRONG_SPECIES, 50, {"moves": ["wood-hammer", "earthquake"]})
	var party: Array = [learner, carry]
	var exp_before := int(learner.get("exp", 0))
	var level_before := int(learner.get("level", 1))

	var engine := BattleEngineScript.new()
	engine.start(Bosses.battle_setup("roark", party, 1234))
	var r := engine.run_to_completion()
	eq(String(r["outcome"]), "win", "won the fight")

	is_true(int(r["expAwarded"]) > 0, "the fight awarded EXP (%d)" % int(r["expAwarded"]))
	is_true(int(learner.get("exp", 0)) > exp_before,
		"the under-cap member gained EXP (%d -> %d)" % [exp_before, int(learner.get("exp", 0))])
	is_true(int(learner.get("level", 1)) >= level_before, "and never lost a level")
	is_true(int(learner.get("level", 1)) <= 18,
		"and was clamped at the cap, not vaulted past it (L%d)" % int(learner.get("level", 1)))


# --------------------------------------------------------------------------
# The real Battle scene, driven the way a player drives it
# --------------------------------------------------------------------------

func test_the_real_battle_scene_takes_a_turn_and_reports_back() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	var packed: PackedScene = load(BATTLE_SCENE) as PackedScene
	var screen: Control = packed.instantiate()
	screen.set("standalone", true)              # do not call SceneRouter
	tree.root.add_child(screen)
	await tree.process_frame

	var party := _strong_party(50, 2)
	screen.call("setup", Bosses.battle_setup("roark", party, 555))
	await tree.process_frame

	var engine: RefCounted = screen.get("engine")
	if not check(engine != null, "the screen built an engine"):
		screen.free()
		return
	eq(engine.party_of(1).size(), 6, "Roark's six are on the field")

	# the HUD, the move list and the party view all bound to that engine
	for child_name: String in ["BattleHud", "MoveList", "PartyView", "MessageBox"]:
		check(screen.get_node_or_null(child_name) != null, "%s was built" % child_name)
	eq(screen.get_node("BattleHud").get("engine"), engine, "the HUD is bound")
	eq(screen.get_node("MoveList").get("engine"), engine, "the move list is bound")

	# the lead-in is queued as a message, not dumped
	is_true(screen.get_node("MessageBox").call("is_open"), "the lead-in is on screen")
	screen.call("debug_flush_log")
	eq(int(screen.get("state")), 1, "and it hands over to the action menu (State.ACTION)")

	var foe_before := int((engine.active(1) as Dictionary)["hp"])
	screen.call("debug_pick_move", 0)
	var after: Dictionary = engine.result()
	eq(int(after["turn"]), 1, "one turn resolved")
	is_true(int((engine.active(1) as Dictionary)["hp"]) < foe_before
			or Stats.is_fainted((engine.party_of(1) as Array)[0]),
		"the move actually landed on something")

	# and the HUD can be refreshed against the mutated engine without error
	screen.get_node("BattleHud").call("refresh")
	screen.free()


func test_the_router_brings_the_battle_scene_up_and_suspends_the_overworld() -> void:
	var main := _boot_the_game()
	if main == null:
		return
	await tree.process_frame
	var ow: Node2D = main.get("overworld")
	var holder: Node = main.get_node("BattleHolder")

	var wild := PartyBuilder.wild(396, 3)      # Starly, Route 201's headline encounter
	is_true(SceneRouter.enter_battle({
		"kind": "wild", "party": GameState.party, "opponent": [wild], "seed": 42}),
		"the router loaded scenes/Battle.tscn")
	await tree.process_frame

	is_true(SceneRouter.in_battle(), "in a battle")
	eq(holder.get_child_count(), 1, "exactly one battle scene")
	is_true(SceneRouter.world_suspended(), "the overworld is suspended, not freed")
	is_true(is_instance_valid(ow), "the Overworld node is still alive")
	is_true(GameState.input_locked, "overworld input is locked")

	var screen: Node = holder.get_child(0)
	var engine: RefCounted = screen.get("engine")
	check(engine != null, "the scene received setup() and built an engine")
	if engine != null:
		eq(int(engine.current_cap()), 18, "the router injected the live level cap")
		eq(engine.party_of(0), GameState.party,
			"the battle holds the very party Dictionaries GameState owns, so damage persists")

	SceneRouter.exit_battle({"outcome": "run"})
	eq(holder.get_child_count(), 0, "the battle scene was torn down")
	is_false(SceneRouter.world_suspended(), "the overworld resumed")
	is_false(GameState.input_locked, "input unlocked")
	is_true(is_instance_valid(ow.get("player")), "the player is still there")


# --------------------------------------------------------------------------
# Interaction
# --------------------------------------------------------------------------

func test_facing_roark_starts_his_fight_and_facing_him_again_afterwards_does_not() -> void:
	if not _have_bosses():
		pending("data/rom/bosses.json is not built")
		return
	var main := _boot_the_game()
	if main == null:
		return
	await tree.process_frame
	var ow: Node2D = main.get("overworld")
	if not check(ow.call("load_map", "oreburgh_gym", Vector2i(6, 12)), "loaded the gym"):
		return

	# stand in front of Roark and face him
	var player: Node2D = ow.get("player")
	player.call("snap_to", Vector2i(6, 4))
	player.set("facing", Vector2i.UP)

	var faced: Dictionary = main.call("faced_object")
	eq(String(faced.get("type", "")), "boss", "facing the boss object")
	eq(String(faced.get("boss", "")), "roark", "which is Roark")

	is_true(bool(main.call("interact")), "talking to him did something")
	is_true(main.get("message_box").call("is_open"), "his intro is on screen")
	# the fight starts only once the intro has been read
	is_false(SceneRouter.in_battle(), "the battle has not jumped the dialogue")
	while main.get("message_box").call("is_open"):
		main.get("message_box").call("advance")
	await tree.process_frame
	is_true(SceneRouter.in_battle(), "the fight began after the dialogue")
	eq(main.get_node("BattleHolder").get_child_count(), 1, "one battle scene")

	var engine: RefCounted = (main.get_node("BattleHolder").get_child(0) as Node).get("engine")
	if engine != null:
		eq(engine.party_of(1).size(), 6, "against all six of his")
		eq(String((engine.sides[1] as Dictionary)["name"]), "Roark", "and it is Roark")

	SceneRouter.exit_battle({"outcome": "run"})
	await tree.process_frame

	# after the flag is set he only talks
	GameState.set_flag("roark_defeated", true)
	main.get("message_box").call("close")
	is_true(bool(main.call("interact")), "he still talks")
	while main.get("message_box").call("is_open"):
		main.get("message_box").call("advance")
	await tree.process_frame
	is_false(SceneRouter.in_battle(), "but does not fight again")


func test_an_item_ball_pays_out_exactly_once() -> void:
	var main := _boot_the_game()
	if main == null:
		return
	await tree.process_frame
	var ow: Node2D = main.get("overworld")
	if not check(ow.call("load_map", "jubilife_city", Vector2i(16, 20)), "loaded Jubilife"):
		return
	var ball: Dictionary = {}
	for o: Variant in ((ow.get("map") as Object).objects as Array):
		if o is Dictionary and String((o as Dictionary).get("type", "")) == "item":
			ball = o
			break
	if not check(not ball.is_empty(), "Jubilife has an item ball"):
		return

	var player: Node2D = ow.get("player")
	player.call("snap_to", Vector2i(int(ball["x"]) - 1, int(ball["y"])))
	player.set("facing", Vector2i.RIGHT)
	var item := String(ball["item"])
	var before := int(GameState.bag.get(item, 0))

	is_true(bool(main.call("interact")), "picked it up")
	eq(int(GameState.bag.get(item, 0)), before + int(ball["count"]), "the item is in the bag")
	main.get("message_box").call("close")

	is_true(bool(main.call("interact")), "talking to the empty spot still responds")
	eq(int(GameState.bag.get(item, 0)), before + int(ball["count"]), "but pays nothing twice")
