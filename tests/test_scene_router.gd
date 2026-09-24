extends "res://tests/framework/test_case.gd"
## SceneRouter: the overworld must survive a battle untouched.

const FAKE_BATTLE := preload("res://tests/framework/fake_battle.gd")

var _saved_level: int = 0
var world: Node2D
var battle_holder: Node
var marker: Node2D


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	DataRegistry.boot(DataRegistry.FIXTURE_DIR)
	EventBus.disconnect_all()
	GameState.track_playtime = false
	GameState.reset()

	world = Node2D.new()
	world.name = "WorldHolder"
	# a stand-in for the loaded map, carrying state that must survive the battle
	marker = Node2D.new()
	marker.name = "PushedBoulder"
	marker.position = Vector2(48, 96)
	marker.set_meta("cell", Vector2i(3, 6))
	world.add_child(marker)

	battle_holder = Node.new()
	battle_holder.name = "BattleHolder"

	tree.root.add_child(world)
	tree.root.add_child(battle_holder)
	SceneRouter.register(world, battle_holder)


func after_each() -> void:
	if SceneRouter.in_battle():
		SceneRouter.exit_battle({})
	SceneRouter.register(null, null)
	SceneRouter.mode = SceneRouter.Mode.BOOT
	world.queue_free()
	battle_holder.queue_free()
	EventBus.disconnect_all()
	GameState.track_playtime = true
	Log.level = _saved_level


func _fake_battle_scene() -> PackedScene:
	var root := Node.new()
	root.name = "FakeBattle"
	root.set_script(FAKE_BATTLE)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		fail("could not pack the fake battle scene: %d" % err)
	return packed


# --------------------------------------------------------------------------

func test_registration() -> void:
	is_true(SceneRouter.is_registered(), "registered")
	eq(SceneRouter.world_holder(), world, "world holder")
	eq(SceneRouter.battle_holder(), battle_holder, "battle holder")
	eq(SceneRouter.mode, SceneRouter.Mode.OVERWORLD, "starts in the overworld")
	is_false(SceneRouter.in_battle(), "not in a battle")
	is_false(SceneRouter.world_suspended(), "world is running")


func test_entering_a_battle_suspends_the_overworld_without_freeing_it() -> void:
	is_true(SceneRouter.enter_battle({"kind": "wild", "opponent": {"species": 396}},
		_fake_battle_scene()), "entered")

	is_true(SceneRouter.in_battle(), "in battle")
	is_true(SceneRouter.world_suspended(), "world suspended")
	eq(world.process_mode, Node.PROCESS_MODE_DISABLED, "PROCESS_MODE_DISABLED")
	is_false(world.visible, "world hidden")
	is_true(GameState.input_locked, "overworld input locked")

	# the map is suspended, NOT freed: every node and every piece of state is
	# still there, which is the whole reason we do not use change_scene_to_*
	is_true(is_instance_valid(marker), "map node still alive")
	is_true(marker.is_inside_tree(), "still in the tree")
	eq(marker.get_meta("cell"), Vector2i(3, 6), "metadata intact")
	eq(marker.position, Vector2(48, 96), "position intact")
	eq(world.get_child_count(), 1, "world still owns its children")

	eq(battle_holder.get_child_count(), 1, "battle scene instantiated")


func test_the_setup_payload_reaches_the_battle_scene() -> void:
	GameState.earn_badge("coal")          # cap becomes 22
	var setup := {"kind": "trainer", "opponent": {"name": "Roark"}}
	is_true(SceneRouter.enter_battle(setup, _fake_battle_scene()), "entered")

	var b := SceneRouter.active_battle()
	check(b != null, "active battle exists")
	eq(int(b.get("setup_calls")), 1, "setup() called once")
	var got: Dictionary = b.get("received")
	eq(String(got["kind"]), "trainer", "kind passed through")
	eq(String((got["opponent"] as Dictionary)["name"]), "Roark", "opponent passed through")
	eq(int(got["cap"]), 22, "the active level cap is injected for the exp-block UI")
	# the caller's dictionary is not mutated
	is_false(setup.has("cap"), "caller's dictionary left alone")


func test_battle_started_and_ended_signals() -> void:
	var started: Array = []
	var ended: Array = []
	EventBus.battle_started.connect(func(s: Dictionary) -> void: started.append(s))
	EventBus.battle_ended.connect(func(r: Dictionary) -> void: ended.append(r))

	SceneRouter.enter_battle({"kind": "wild"}, _fake_battle_scene())
	eq(started.size(), 1, "battle_started once")
	eq(String((started[0] as Dictionary)["kind"]), "wild", "payload")

	SceneRouter.exit_battle({"outcome": "win", "expAwarded": 120})
	eq(ended.size(), 1, "battle_ended once")
	eq(String((ended[0] as Dictionary)["outcome"]), "win", "result payload")


func test_exiting_restores_the_overworld_exactly() -> void:
	SceneRouter.enter_battle({"kind": "wild"}, _fake_battle_scene())
	is_true(SceneRouter.exit_battle({"outcome": "win"}), "exited")

	is_false(SceneRouter.in_battle(), "back in the overworld")
	eq(SceneRouter.mode, SceneRouter.Mode.OVERWORLD, "mode")
	is_false(SceneRouter.world_suspended(), "world resumed")
	eq(world.process_mode, Node.PROCESS_MODE_INHERIT, "PROCESS_MODE_INHERIT")
	is_true(world.visible, "world visible")
	is_false(GameState.input_locked, "input unlocked")
	eq(SceneRouter.active_battle(), null, "no active battle")

	# the battle holder is empty on the very next line, not at the end of the
	# frame -- otherwise a second encounter would stack two battle scenes
	eq(battle_holder.get_child_count(), 0, "battle holder emptied synchronously")

	# and the overworld is byte-for-byte what it was
	is_true(is_instance_valid(marker), "map node survived the whole round trip")
	eq(marker.get_meta("cell"), Vector2i(3, 6), "metadata survived")
	eq(marker.position, Vector2(48, 96), "position survived")


func test_two_battles_in_a_row() -> void:
	SceneRouter.enter_battle({"kind": "wild"}, _fake_battle_scene())
	SceneRouter.exit_battle({"outcome": "run"})
	is_true(SceneRouter.enter_battle({"kind": "wild"}, _fake_battle_scene()),
		"a second battle starts cleanly")
	eq(battle_holder.get_child_count(), 1, "exactly one battle scene")
	SceneRouter.exit_battle({"outcome": "win"})
	eq(battle_holder.get_child_count(), 0, "cleaned up again")


func test_nested_battles_are_refused() -> void:
	Log.level = Log.Level.OFF
	SceneRouter.enter_battle({"kind": "wild"}, _fake_battle_scene())
	is_false(SceneRouter.enter_battle({"kind": "wild"}, _fake_battle_scene()),
		"a second enter_battle is refused")
	eq(battle_holder.get_child_count(), 1, "still exactly one battle scene")


func test_exit_without_a_battle_is_refused() -> void:
	Log.level = Log.Level.OFF
	is_false(SceneRouter.exit_battle({}), "refused")
	is_false(SceneRouter.world_suspended(), "world untouched")


func test_unregistered_router_refuses_instead_of_crashing() -> void:
	Log.level = Log.Level.OFF
	SceneRouter.register(null, null)
	is_false(SceneRouter.is_registered(), "not registered")
	is_false(SceneRouter.enter_battle({"kind": "wild"}, _fake_battle_scene()),
		"enter_battle refused")
	is_false(SceneRouter.load_map(&"twinleaf_town", Vector2i(10, 12)), "load_map refused")


func test_load_map_refuses_a_map_that_does_not_exist() -> void:
	Log.level = Log.Level.OFF
	var before := GameState.current_map
	is_false(SceneRouter.load_map(&"definitely_not_a_map", Vector2i(1, 1)),
		"missing map scene refused")
	eq(GameState.current_map, before, "GameState not half-changed by a bad warp")


func test_note_map_changed_updates_state_and_announces() -> void:
	var seen: Array = []
	EventBus.map_changed.connect(func(m: StringName, s: Vector2i) -> void: seen.append([m, s]))
	SceneRouter.note_map_changed(&"route_201", Vector2i(20, 4))
	eq(GameState.current_map, &"route_201", "map id")
	eq(GameState.player_cell, Vector2i(20, 4), "spawn cell")
	eq(seen.size(), 1, "map_changed emitted once")
	eq(seen[0], [&"route_201", Vector2i(20, 4)], "payload")
