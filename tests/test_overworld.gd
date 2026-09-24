extends "res://tests/framework/test_case.gd"
## The overworld stream: map loading, grid movement, collision, badge-gated
## traversal, wild encounters and warps.
##
## Everything here runs against `tests/fixtures/maps/test_arena.json`, a
## hand-authored 12x12 map (nothing ROM-derived) whose grid is laid out so that
## every collision branch has exactly one place to be exercised:
##
##       x=012345678901
##   y=0 111110111111     (5,0) is the only gap -> north connection
##   y=1 100000000001     smash obstacle (4,1), cut obstacle (6,1), warp (1,1)
##   y=2 106000500001     climb (2,2), shallow water (6,2)
##   y=3 100100000001     plain wall (3,3)
##   y=4 100000000001
##   y=5 100002000701     ledge (5,5), waterfall (9,5)
##   y=6 100000003331     strength boulder (2,6); lake x=8..10
##   y=7 100000003331
##   y=8 144400003331     tall grass x=1..3, y=8..10
##   y=9 144400003331
##   y=10 144400000001
##   y=11 111111111111

const MapLoader := preload("res://src/overworld/map_loader.gd")
const PlayerScript := preload("res://src/overworld/player.gd")
const Warps := preload("res://src/overworld/warps.gd")
const Collision := preload("res://src/systems/collision.gd")
const Traversal := preload("res://src/systems/traversal.gd")
const Encounters := preload("res://src/systems/encounters.gd")
const Overworld := preload("res://src/overworld/overworld.gd")

const FIXTURE_MAPS := "res://tests/fixtures/maps"
const ENC_FIXTURE := "res://tests/fixtures/encounters.json"

var _saved_level: int = 0
var map: MapLoader.MapData = null
var trav: Traversal = null


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	DataRegistry.boot(DataRegistry.FIXTURE_DIR)
	EventBus.disconnect_all()
	GameState.track_playtime = false
	GameState.reset()
	map = MapLoader.load_map("test_arena", FIXTURE_MAPS)
	trav = Traversal.new()
	trav.announce = false


func after_each() -> void:
	EventBus.disconnect_all()
	Log.level = _saved_level
	GameState.track_playtime = true


# --- helpers --------------------------------------------------------------

## A step attempt made with an explicit badge set, bypassing GameState.
func attempt_with(badges: Array, from: Vector2i, dir: Vector2i) -> Dictionary:
	trav.badge_gate = func(verb: String) -> bool: return badges.has(verb)
	return trav.attempt(map, from, dir)


func kind_of(res: Dictionary) -> int:
	return int(res["kind"])


## Drives a mover until it settles, with a hard iteration guard -- the stale
## input buffer bug (player.gd header) presented exactly as a loop that never
## terminated, so the guard is the assertion.
func settle(p: Node2D, frames: int = 400) -> int:
	var i := 0
	while p.state != PlayerScript.State.IDLE and i < frames:
		p.tick(Vector2i.ZERO, false, 1.0 / 60.0)
		i += 1
	return i


func always_move() -> Callable:
	return func(from: Vector2i, dir: Vector2i) -> Dictionary:
		return {"kind": Collision.Result.MOVE, "target": from + dir, "verb": "",
			"reason": "", "message": "", "blocked": false}


# ==========================================================================
# 1. Map loading -- DATA_CONTRACT.md 9
# ==========================================================================

func test_map_loads_with_the_contract_shape() -> void:
	if not check(map != null, "test_arena.json failed to load"):
		return
	eq(String(map.id), "test_arena", "id")
	eq(map.width, 12, "width")
	eq(map.height, 12, "height")
	eq(map.tile_size, 16, "tileSize")
	eq(map.tileset, "outdoor_sinnoh", "tileset")
	eq(String(map.encounter_zone), "test_arena", "encounterZone")
	eq(map.source, "fixture", "loaded from the fixture directory")

	# Three layers, each exactly width*height cells, row-major.
	for layer_name: String in ["ground", "overlay", "above"]:
		is_true(map.layers.has(layer_name), "layer '%s' present" % layer_name)
		eq((map.layers[layer_name] as PackedInt32Array).size(), 144,
			"layer '%s' cell count" % layer_name)
	eq(map.tile_at("overlay", Vector2i(5, 5)), 7, "overlay tile over the ledge")
	eq(map.tile_at("above", Vector2i(6, 1)), 20, "above-layer treetop")
	eq(map.tile_at("above", Vector2i(0, 0)), -1, "-1 means empty")


func test_collision_grid_reads_row_major_and_fails_closed_off_map() -> void:
	eq(map.collision.size(), 144, "collision cell count")
	# Spot-check one cell of every code, at its authored position.
	eq(map.code_at(Vector2i(4, 4)), Collision.WALK, "(4,4) walk")
	eq(map.code_at(Vector2i(3, 3)), Collision.BLOCK, "(3,3) block")
	eq(map.code_at(Vector2i(5, 5)), Collision.LEDGE, "(5,5) ledge")
	eq(map.code_at(Vector2i(8, 7)), Collision.DEEP_WATER, "(8,7) deep water")
	eq(map.code_at(Vector2i(2, 9)), Collision.TALL_GRASS, "(2,9) tall grass")
	eq(map.code_at(Vector2i(6, 2)), Collision.SHALLOW_WATER, "(6,2) shallow water")
	eq(map.code_at(Vector2i(2, 2)), Collision.CLIMB, "(2,2) climb")
	eq(map.code_at(Vector2i(9, 5)), Collision.WATERFALL, "(9,5) waterfall")

	# x and y are not transposed. (3,3) is a wall; its mirror (3,1)... is not.
	eq(map.code_at(Vector2i(4, 1)), Collision.WALK, "(4,1) is floor under an obstacle")
	is_false(map.in_bounds(Vector2i(-1, 5)), "negative x is off-map")
	is_false(map.in_bounds(Vector2i(12, 5)), "x == width is off-map")
	eq(map.code_at(Vector2i(-1, 5)), Collision.BLOCK, "off-map reads as BLOCK, not a crash")
	eq(map.code_at(Vector2i(5, 99)), Collision.BLOCK, "off-map reads as BLOCK")


func test_traversal_warps_and_connections_are_indexed_by_cell() -> void:
	eq(map.traversal.size(), 3, "three obstacles")
	eq(String(map.traversal_at(Vector2i(4, 1))["type"]), "smash", "smash at (4,1)")
	eq(String(map.traversal_at(Vector2i(4, 1))["requires"]), "badge:coal", "smash requires")
	eq(String(map.traversal_at(Vector2i(6, 1))["type"]), "cut", "cut at (6,1)")
	eq(String(map.traversal_at(Vector2i(2, 6))["type"]), "strength", "strength at (2,6)")
	is_true(map.traversal_at(Vector2i(0, 0)).is_empty(), "no obstacle at (0,0)")

	eq(String(map.warp_at(Vector2i(1, 1))["to"]), "test_hut", "warp destination")
	eq(int(map.warp_at(Vector2i(1, 1))["toX"]), 2, "warp toX")
	eq(map.connection("north"), "test_north", "north connection")
	eq(map.connection("south"), "", "no south connection")


func test_a_missing_map_returns_null_rather_than_an_empty_map() -> void:
	Log.level = Log.Level.OFF
	is_true(MapLoader.load_map("no_such_map_at_all", FIXTURE_MAPS) == null,
		"missing map is null")
	# A degenerate size is a shape error, not a 0x0 map you can walk around in.
	is_true(MapLoader.from_dict({"id": "x", "width": 0, "height": 5}) == null,
		"zero width refused")
	# Collision grid that does not match the declared size.
	is_true(MapLoader.from_dict({"id": "x", "width": 4, "height": 4,
		"collision": [[0, 0], [0, 0]]}) == null, "short collision grid refused")


# ==========================================================================
# 2. Collision -- the required behaviours
# ==========================================================================

func test_walking_into_collision_code_1_does_not_move_the_player() -> void:
	# (3,4) is floor; (3,3) directly north of it is code 1.
	eq(map.code_at(Vector2i(3, 3)), Collision.BLOCK, "precondition: (3,3) is code 1")
	var res := attempt_with([], Vector2i(3, 4), Vector2i.UP)
	eq(kind_of(res), Collision.Result.BLOCKED, "blocked")
	eq(String(res["reason"]), "solid", "reason")
	eq(res["target"] as Vector2i, Vector2i(3, 4), "target stays where the player was")
	is_true(bool(res["blocked"]), "blocked flag")

	# And the mover actually stays put, across a full step's worth of frames.
	var p := PlayerScript.new()
	p.snap_to(Vector2i(3, 4))
	p.facing = Vector2i.UP
	p.resolver = func(from: Vector2i, dir: Vector2i) -> Dictionary:
		return trav.attempt(map, from, dir)
	trav.badge_gate = func(_v: String) -> bool: return false
	for i in 60:
		p.tick(Vector2i.UP, false, 1.0 / 60.0)
	eq(p.cell, Vector2i(3, 4), "cell unchanged after 60 frames of pushing into a wall")
	eq(p.position, Vector2(3 * 16, 4 * 16), "position unchanged")
	eq(p.steps_taken, 0, "no steps taken")
	is_true(p.bumps > 0, "the bump was counted")
	eq(p.facing, Vector2i.UP, "you still turn to face the wall")
	p.free()

	# No badge in the game unblocks a plain wall.
	var all_verbs: Array = Traversal.VERBS
	eq(kind_of(attempt_with(all_verbs, Vector2i(3, 4), Vector2i.UP)),
		Collision.Result.BLOCKED, "still blocked holding every badge")


func test_a_ledge_only_permits_southward_jumps() -> void:
	eq(map.code_at(Vector2i(5, 5)), Collision.LEDGE, "precondition: (5,5) is a ledge")

	# Southbound: hop two tiles, clearing the ledge.
	var south := attempt_with([], Vector2i(5, 4), Vector2i.DOWN)
	eq(kind_of(south), Collision.Result.HOP, "southbound hops")
	eq(south["target"] as Vector2i, Vector2i(5, 6), "lands two tiles down, not on the ledge")

	# Every other direction is a wall.
	eq(kind_of(attempt_with([], Vector2i(5, 6), Vector2i.UP)), Collision.Result.BLOCKED,
		"northbound blocked")
	eq(String(attempt_with([], Vector2i(5, 6), Vector2i.UP)["reason"]), "ledge-wrong-way",
		"northbound reason")
	eq(kind_of(attempt_with([], Vector2i(4, 5), Vector2i.RIGHT)), Collision.Result.BLOCKED,
		"eastbound blocked")
	eq(kind_of(attempt_with([], Vector2i(6, 5), Vector2i.LEFT)), Collision.Result.BLOCKED,
		"westbound blocked")

	# Holding every badge does not turn a ledge into a two-way door.
	eq(kind_of(attempt_with(Traversal.VERBS, Vector2i(5, 6), Vector2i.UP)),
		Collision.Result.BLOCKED, "badges do not open a ledge backwards")

	# The mover lands on the far side, exactly, with no residual arc offset.
	var p := PlayerScript.new()
	p.snap_to(Vector2i(5, 4))
	p.facing = Vector2i.DOWN
	p.resolver = func(from: Vector2i, dir: Vector2i) -> Dictionary:
		return trav.attempt(map, from, dir)
	trav.badge_gate = func(_v: String) -> bool: return false
	p.tick(Vector2i.DOWN, false, 0.001)
	is_true(p.is_moving(), "the hop started")
	settle(p)
	eq(p.cell, Vector2i(5, 6), "landed past the ledge")
	eq(p.position, Vector2(5 * 16, 6 * 16), "pixel-exact landing, arc fully resolved")
	eq(p.steps_taken, 1, "one step for a two-tile hop")
	p.free()


func test_deep_water_blocks_without_the_fen_badge_and_auto_surfs_with_it() -> void:
	# (7,7) is the shoreline; (8,7) is deep water.
	eq(map.code_at(Vector2i(8, 7)), Collision.DEEP_WATER, "precondition: (8,7) is code 3")

	# --- without the badge ---
	GameState.reset()
	is_false(GameState.has_badge("fen"), "precondition: no Fen badge")
	trav.badge_gate = Callable()          # use the REAL GameState gate
	var denied := trav.attempt(map, Vector2i(7, 7), Vector2i.RIGHT)
	eq(kind_of(denied), Collision.Result.BLOCKED, "blocked without Fen")
	eq(String(denied["reason"]), "no-badge", "reason")
	eq(String(denied["verb"]), "surf", "it knows which verb was wanted")
	is_true(String(denied["message"]).contains("Fen"),
		"the message names the Fen Badge, got: %s" % denied["message"])
	is_false(trav.surfing, "still on foot")

	# --- with the badge, through the real GameState ---
	var verbs: Array = []
	EventBus.traversal_used.connect(func(v: StringName) -> void: verbs.append(String(v)))
	is_true(GameState.earn_badge("fen"), "earned the Fen badge")
	var ok := trav.attempt(map, Vector2i(7, 7), Vector2i.RIGHT)
	eq(kind_of(ok), Collision.Result.TRAVERSE, "surf fires")
	eq(String(ok["verb"]), "surf", "verb")
	eq(String(ok["performed"]), "surf", "it was actually performed")
	eq(ok["target"] as Vector2i, Vector2i(8, 7), "you end up on the water tile")
	is_false(bool(ok["blocked"]), "not blocked")
	is_true(trav.surfing, "now surfing")
	eq(verbs, ["surf"], "traversal_used fired exactly once, for surf")

	# NO MENU, NO MOVE, NO PARTY CHECK: the party is empty and it still worked.
	eq(GameState.party_size(), 0, "surfed with an empty party -- no HM slave")

	# While surfing, open water is an ordinary step and land dismounts you.
	eq(kind_of(trav.attempt(map, Vector2i(8, 7), Vector2i.RIGHT)), Collision.Result.MOVE,
		"water to water is a plain move")
	var back := trav.attempt(map, Vector2i(8, 7), Vector2i.LEFT)
	eq(kind_of(back), Collision.Result.TRAVERSE, "stepping ashore")
	eq(String(back["verb"]), "dismount", "dismount verb")
	is_false(trav.surfing, "back on foot")


func test_a_smash_obstacle_blocks_without_the_coal_badge_and_clears_with_it() -> void:
	# The rock sits at (4,1); the player walks north into it from (4,2).
	eq(String(map.traversal_at(Vector2i(4, 1))["type"]), "smash", "precondition")

	GameState.reset()
	trav.badge_gate = Callable()          # the REAL badge gate
	var denied := trav.attempt(map, Vector2i(4, 2), Vector2i.UP)
	eq(kind_of(denied), Collision.Result.BLOCKED, "blocked without Coal")
	eq(String(denied["verb"]), "smash", "verb identified")
	is_true(String(denied["message"]).contains("Coal"),
		"message names the Coal Badge, got: %s" % denied["message"])
	eq(trav.cleared_count(), 0, "nothing was cleared")
	is_true(trav.obstacles_for(map).has(Vector2i(4, 1)), "the rock is still there")

	is_true(GameState.earn_badge("coal"), "earned Coal")
	var ok := trav.attempt(map, Vector2i(4, 2), Vector2i.UP)
	eq(kind_of(ok), Collision.Result.TRAVERSE, "smash fires")
	eq(String(ok["performed"]), "smash", "performed")
	eq(ok["target"] as Vector2i, Vector2i(4, 1), "you step onto the tile it stood on")
	eq(trav.cleared_count(), 1, "one obstacle cleared")
	is_false(trav.obstacles_for(map).has(Vector2i(4, 1)), "the rock is gone")

	# Cleared stays cleared while you are on the map...
	eq(kind_of(trav.attempt(map, Vector2i(4, 2), Vector2i.UP)), Collision.Result.MOVE,
		"second pass is an ordinary step")
	# ...and respawns on reload, as in vanilla (game-design.md 3.2).
	trav.on_map_loaded(map.id)
	eq(trav.cleared_count(), 0, "obstacles respawn on map reload")
	is_true(trav.obstacles_for(map).has(Vector2i(4, 1)), "the rock is back")

	# The Coal Badge does not open a Forest-badge tree.
	var tree_res := trav.attempt(map, Vector2i(6, 2), Vector2i.UP)
	eq(kind_of(tree_res), Collision.Result.BLOCKED, "cut tree still blocked")
	is_true(String(tree_res["message"]).contains("Forest"), "names the Forest Badge")


# ==========================================================================
# 3. The rest of the traversal ladder
# ==========================================================================

func test_every_verb_is_gated_by_exactly_its_own_badge() -> void:
	# (from, dir, verb, badge) for each obstacle on the fixture map.
	var cases: Array = [
		[Vector2i(4, 2), Vector2i.UP, "smash", "coal"],
		[Vector2i(6, 2), Vector2i.UP, "cut", "forest"],
		[Vector2i(1, 6), Vector2i.RIGHT, "strength", "mine"],
		[Vector2i(2, 3), Vector2i.UP, "climb", "icicle"],
		[Vector2i(7, 7), Vector2i.RIGHT, "surf", "fen"],
	]
	for c: Array in cases:
		var verb: String = c[2]
		# Holding every OTHER verb must not open it.
		var others: Array = Traversal.VERBS.duplicate()
		others.erase(verb)
		var t1 := Traversal.new()
		t1.announce = false
		t1.badge_gate = func(v: String) -> bool: return others.has(v)
		eq(kind_of(t1.attempt(map, c[0], c[1])), Collision.Result.BLOCKED,
			"%s stays blocked while holding every other badge" % verb)

		var t2 := Traversal.new()
		t2.announce = false
		t2.badge_gate = func(v: String) -> bool: return v == verb
		eq(kind_of(t2.attempt(map, c[0], c[1])), Collision.Result.TRAVERSE,
			"%s fires on its own badge alone" % verb)
		eq(Traversal.badge_for(verb), c[3], "%s <- %s badge" % [verb, c[3]])


func test_strength_pushes_the_boulder_exactly_one_tile() -> void:
	trav.badge_gate = func(v: String) -> bool: return v == "strength"
	is_true(trav.obstacles_for(map).has(Vector2i(2, 6)), "boulder starts at (2,6)")

	var res := trav.attempt(map, Vector2i(1, 6), Vector2i.RIGHT)
	eq(kind_of(res), Collision.Result.TRAVERSE, "push fires")
	eq(String(res["performed"]), "strength", "performed")
	eq(res["target"] as Vector2i, Vector2i(2, 6), "player takes the boulder's old tile")

	var live := trav.obstacles_for(map)
	is_false(live.has(Vector2i(2, 6)), "boulder left its old tile")
	is_true(live.has(Vector2i(3, 6)), "boulder is one tile east -- exactly one")
	is_false(live.has(Vector2i(4, 6)), "and not two")

	# Pushing it into the wall at x=11 eventually fails rather than deleting it.
	var t := Traversal.new()
	t.announce = false
	t.badge_gate = func(v: String) -> bool: return v == "strength"
	# (2,6) pushed west from (3,6): destination (1,6) is floor, so this works;
	# pushing it west again would put it on the border wall at (0,6).
	eq(kind_of(t.attempt(map, Vector2i(3, 6), Vector2i.LEFT)), Collision.Result.TRAVERSE,
		"first westward push")
	var stuck := t.attempt(map, Vector2i(2, 6), Vector2i.LEFT)
	eq(kind_of(stuck), Collision.Result.BLOCKED, "a boulder against the wall does not move")
	eq(String(stuck["reason"]), "verb-failed", "and says so")
	is_true(t.obstacles_for(map).has(Vector2i(1, 6)), "boulder still exists at (1,6)")


func test_waterfall_needs_the_beacon_badge_and_the_water_underneath_you() -> void:
	eq(map.code_at(Vector2i(9, 5)), Collision.WATERFALL, "precondition: (9,5) is code 7")
	eq(map.code_at(Vector2i(9, 6)), Collision.DEEP_WATER, "precondition: water below it")

	trav.badge_gate = func(v: String) -> bool: return v == "surf"
	trav.surfing = true
	var no_badge := trav.attempt(map, Vector2i(9, 6), Vector2i.UP)
	eq(kind_of(no_badge), Collision.Result.BLOCKED, "blocked without Beacon")
	is_true(String(no_badge["message"]).contains("Beacon"), "names the Beacon Badge")

	trav.badge_gate = func(v: String) -> bool: return v == "waterfall" or v == "surf"
	eq(kind_of(trav.attempt(map, Vector2i(9, 6), Vector2i.UP)), Collision.Result.TRAVERSE,
		"ascends with Beacon while surfing")

	# On foot, the Beacon Badge alone is not enough -- you have to be on water.
	var t := Traversal.new()
	t.announce = false
	t.badge_gate = func(_v: String) -> bool: return true
	t.surfing = false
	var dry := t.attempt(map, Vector2i(9, 4), Vector2i.DOWN)
	eq(kind_of(dry), Collision.Result.BLOCKED, "blocked on foot")
	eq(String(dry["reason"]), "not-surfing", "reason")


func test_there_is_no_defog_verb_anywhere() -> void:
	# game-design.md 3.4: fog is deleted from the build. Relic grants no verb.
	is_false(Traversal.VERBS.has("defog"), "defog is not a verb")
	is_false(Traversal.is_verb("defog"), "is_verb rejects it")
	eq(Traversal.badge_for("defog"), "", "no badge maps to it")
	is_false(Collision.VERB_BADGE.has("defog"), "collision knows no defog")
	is_false(GameState.can_traverse("defog"), "GameState refuses it")
	eq(Traversal.VERBS.size(), 7, "seven verbs, not eight")

	# The Relic badge is real, raises the cap, and grants no movement verb.
	Log.level = Log.Level.OFF
	is_true(GameState.earn_badge("relic"), "relic is a real badge")
	for verb: String in Traversal.VERBS:
		is_false(GameState.can_traverse(verb),
			"the Relic badge alone does not grant %s" % verb)

	# A map that declares a defog obstacle has it dropped at parse time.
	var d := MapLoader.from_dict({
		"id": "foggy", "width": 3, "height": 3,
		"collision": [[0, 0, 0], [0, 0, 0], [0, 0, 0]],
		"traversal": [{"x": 1, "y": 1, "type": "defog", "requires": "badge:relic"}]})
	is_true(d != null, "the map still loads")
	eq(d.traversal.size(), 0, "the defog obstacle was dropped")


func test_fly_is_a_map_menu_limited_to_visited_centers() -> void:
	GameState.reset()
	is_false(trav.can_fly(), "no Fly without the Cobble badge")
	eq(trav.fly_destinations().size(), 0, "no destinations")

	trav.record_center_visit(&"jubilife_city")
	trav.record_center_visit(&"oreburgh_city")
	eq(trav.fly_destinations().size(), 0, "still nothing without the badge")
	is_true(trav.fly_to(&"jubilife_city").is_empty(), "flying is refused")

	GameState.earn_badge("cobble")
	is_true(trav.can_fly(), "Cobble grants Fly")
	eq(Array(trav.fly_destinations()), ["jubilife_city", "oreburgh_city"],
		"only the two visited Centers, sorted")
	is_true(trav.fly_to(&"sunyshore_city").is_empty(),
		"an unvisited Center is not a destination")
	eq(String(trav.fly_to(&"jubilife_city")["to"]), "jubilife_city", "flies to a visited one")


# ==========================================================================
# 4. Grid movement
# ==========================================================================

func test_the_mover_is_drift_free_under_randomised_frame_times() -> void:
	# The overshoot-carry regression guard (player.gd header): 40 tiles east under
	# 4-50 ms frames must land on EXACTLY 40*16 px with y untouched.
	var p := PlayerScript.new()
	p.snap_to(Vector2i.ZERO)
	p.facing = Vector2i.RIGHT
	p.resolver = always_move()
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var guard := 0
	while p.steps_taken < 40 and guard < 10000:
		p.tick(Vector2i.RIGHT, true, rng.randf_range(0.004, 0.050))
		guard += 1
	is_true(guard < 10000, "the run terminated (guard fired at %d)" % guard)
	settle(p)
	# 41, not 40: the frame that completed tile 40 carried its overshoot into a
	# 41st step, which is exactly the behaviour being tested. The invariant is
	# that the landing is pixel-exact and y never moved.
	eq(p.steps_taken, 41, "40 held tiles + the one chained by the overshoot carry")
	eq(p.position, Vector2(41 * 16, 0), "exact landing: no accumulated float drift")
	eq(p.position.y, 0.0, "y never moved at all")
	eq(p.cell, Vector2i(p.steps_taken, 0), "cell agrees with position")
	p.free()


func test_the_input_buffer_is_exactly_one_deep() -> void:
	var p := PlayerScript.new()
	p.snap_to(Vector2i.ZERO)
	p.facing = Vector2i.RIGHT
	p.resolver = always_move()

	# Hold right through step 1, release 6 frames in. DS behaviour: you finish
	# the current tile plus the buffered one, then stop.
	for i in 6:
		p.tick(Vector2i.RIGHT, false, 1.0 / 60.0)
	var frames := settle(p)
	is_true(frames < 400, "settled without looping forever (%d frames)" % frames)
	eq(p.steps_taken, 2, "current tile + one buffered tile, and no more")
	eq(p.cell, Vector2i(2, 0), "two tiles east")

	# And it really stops: another 200 idle frames move nothing.
	for i in 200:
		p.tick(Vector2i.ZERO, false, 1.0 / 60.0)
	eq(p.steps_taken, 2, "no phantom walking from a stale buffer")
	p.free()


func test_facing_turning_and_the_run_toggle() -> void:
	var p := PlayerScript.new()
	p.snap_to(Vector2i(4, 4))
	p.resolver = always_move()
	eq(p.facing, Vector2i.DOWN, "starts facing south")

	# A direction you are not facing pivots you and costs no tile.
	p.tick(Vector2i.RIGHT, false, 1.0 / 60.0)
	eq(p.facing, Vector2i.RIGHT, "pivoted")
	eq(p.state, PlayerScript.State.TURNING, "turning, not moving")
	eq(p.cell, Vector2i(4, 4), "did not move while turning")

	# Four directions, and only four.
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var q := PlayerScript.new()
		q.snap_to(Vector2i(4, 4))
		q.resolver = always_move()
		q.facing = d
		q.tick(d, false, 0.001)
		settle(q)
		eq(q.cell, Vector2i(4, 4) + d, "stepped %s" % d)
		q.free()

	# Run toggle: latched, not held.
	p.run_mode = PlayerScript.RunMode.TOGGLE
	is_false(p.running_now(false), "not running")
	is_false(p.running_now(true), "holding the key does nothing in TOGGLE mode")
	p.toggle_run()
	is_true(p.running_now(false), "latched on")
	p.toggle_run()
	is_false(p.running_now(false), "latched off")
	# HOLD mode is the vanilla Running Shoes behaviour.
	p.run_mode = PlayerScript.RunMode.HOLD
	is_true(p.running_now(true), "held")
	is_false(p.running_now(false), "released")
	is_true(p.run_time < p.walk_time, "running is faster than walking")
	p.free()


func test_an_unwired_mover_refuses_to_move() -> void:
	# The default resolver blocks, so a mover someone forgot to wire up stands
	# still instead of walking through the world.
	var p := PlayerScript.new()
	p.snap_to(Vector2i(5, 5))
	p.facing = Vector2i.RIGHT
	for i in 60:
		p.tick(Vector2i.RIGHT, false, 1.0 / 60.0)
	eq(p.cell, Vector2i(5, 5), "no movement without a resolver")
	eq(p.steps_taken, 0, "no steps")
	p.free()


# ==========================================================================
# 5. Encounters
# ==========================================================================

func test_the_merged_table_is_vanilla_plus_curated_by_weight() -> void:
	var enc := Encounters.new()
	enc.boot(ENC_FIXTURE)
	eq(enc.source(), "data", "loaded the fixture as its data file")

	var grass := enc.merged_table("test_arena", "grass")
	eq(grass.size(), 6, "3 vanilla + 3 curated grass entries")
	eq(enc.total_weight("test_arena", "grass"), 50 + 40 + 10 + 10 + 5 + 4, "summed weight")

	var sources: Dictionary = {"vanilla": 0, "curated": 0}
	for e: Dictionary in grass:
		sources[String(e["source"])] += 1
	eq(sources["vanilla"], 3, "vanilla entries kept")
	eq(sources["curated"], 3, "curated entries merged in, not replacing")

	# A curated entry tagged for another table does not join this one.
	var surf := enc.merged_table("test_arena", "surf")
	eq(surf.size(), 2, "1 vanilla + 1 curated surf entry")
	eq(enc.total_weight("test_arena", "surf"), 120, "surf weight")

	# Time-of-day filtering on curated entries.
	enc.time_of_day = "day"
	eq(enc.merged_table("test_arena", "grass").size(), 5, "the night-only entry drops out")
	enc.time_of_day = "night"
	eq(enc.merged_table("test_arena", "grass").size(), 6, "and comes back at night")

	eq(enc.merged_table("test_empty", "grass").size(), 0, "an empty zone is empty")
	eq(enc.roll("test_empty", "grass").size(), 0, "and rolls nothing")
	eq(enc.roll("no_such_zone", "grass").size(), 0, "an unknown zone rolls nothing")


func test_stepping_on_tall_grass_triggers_an_encounter_under_the_level_cap() -> void:
	var enc := Encounters.new()
	enc.boot(ENC_FIXTURE)
	enc.rng.seed = 20260923
	enc.min_steps_between = 0

	GameState.reset()
	var cap := GameState.current_level_cap()
	is_true(cap > 0, "there is a level cap (%d)" % cap)

	var fired: Array = []
	EventBus.encounter_triggered.connect(func(zone: StringName, lv: Vector2i) -> void:
		fired.append([String(zone), lv]))

	# Walking on something that is not tall grass never rolls.
	for i in 200:
		is_true(enc.step(Collision.WALK, "test_arena").is_empty(), "no encounter on plain floor")
		is_true(enc.step(Collision.BLOCK, "test_arena").is_empty(), "nor on a wall code")
	eq(enc.grass_steps, 0, "and those steps were not counted as grass steps")

	# Now walk in the grass until something jumps out.
	var got: Dictionary = {}
	var steps := 0
	while got.is_empty() and steps < 500:
		got = enc.step(Collision.TALL_GRASS, "test_arena")
		steps += 1
	is_true(not got.is_empty(), "an encounter fired within 500 grass steps")
	is_true(steps < 100, "and it took %d steps, which is a plausible rate" % steps)
	eq(enc.grass_steps, steps, "every grass step was counted")
	eq(fired.size(), 1, "encounter_triggered fired once")
	eq(String(fired[0][0]), "test_arena", "with the zone")
	eq((fired[0][1] as Vector2i).x, int(got["level"]), "and the rolled level")

	is_true(int(got["species"]) > 0, "a real species id")
	is_true(int(got["level"]) >= 1 and int(got["level"]) <= cap,
		"level %d is within 1..cap(%d)" % [int(got["level"]), cap])
	eq(enc.steps_since_encounter, 0, "the step counter reset")

	# 2,000 rolls from a table whose levels are 30-40, against the start cap.
	var over := 0
	var highest := 0
	for i in 2000:
		var r := enc.roll("test_overcap", "grass")
		var lv := int(r["level"])
		highest = maxi(highest, lv)
		if lv > cap:
			over += 1
		if not r.has("cappedFrom"):
			fail("a 30-40 roll against cap %d should record cappedFrom" % cap)
			break
	eq(over, 0, "not one of 2,000 rolls exceeded the cap")
	eq(highest, cap, "and the cap is actually reached, so the clamp is real")

	# Raise the cap and the ceiling moves with it -- the clamp reads the live cap.
	GameState.earn_badge("coal")
	GameState.earn_badge("forest")
	var new_cap := GameState.current_level_cap()
	is_true(new_cap > cap, "badges raised the cap %d -> %d" % [cap, new_cap])
	var highest2 := 0
	for i in 2000:
		highest2 = maxi(highest2, int(enc.roll("test_overcap", "grass")["level"]))
	eq(highest2, new_cap, "rolls now reach, and stop at, the new cap")


func test_the_grace_period_stops_back_to_back_encounters() -> void:
	var enc := Encounters.new()
	enc.boot(ENC_FIXTURE)
	enc.rng.seed = 7
	enc.min_steps_between = 3
	# test_overcap has grassRate 255, so every eligible step would otherwise roll.
	for i in 3:
		is_true(enc.step(Collision.TALL_GRASS, "test_overcap").is_empty(),
			"step %d is inside the grace period" % (i + 1))
	is_true(not enc.step(Collision.TALL_GRASS, "test_overcap").is_empty(),
		"the 4th step encounters")

	# rate_scale 0 is the cutscene / Repel switch.
	enc.rate_scale = 0.0
	enc.steps_since_encounter = 99
	for i in 50:
		is_true(enc.step(Collision.TALL_GRASS, "test_overcap").is_empty(),
			"rate_scale 0 suppresses encounters entirely")


func test_the_real_rom_encounter_table_merges_if_it_has_been_built() -> void:
	# data/rom/encounters.json is ROM-derived and gitignored, so this is a
	# pending, not a failure, in a fresh checkout.
	if not FileAccess.file_exists(Encounters.DATA_PATH):
		pending("data/rom/encounters.json not built (run the ROM pipeline)")
		return
	var enc := Encounters.new()
	is_true(enc.boot(Encounters.DATA_PATH), "loaded the real tables")
	is_true(enc.zone_count() > 100, "%d zones extracted" % enc.zone_count())
	is_true(enc.has_zone("route_201"), "route_201 present")

	var merged := enc.merged_table("route_201", "grass")
	var vanilla := 0
	var curated := 0
	for e: Dictionary in merged:
		if String(e["source"]) == "vanilla":
			vanilla += 1
		else:
			curated += 1
	is_true(vanilla > 0, "route_201 has vanilla grass entries (%d)" % vanilla)
	is_true(curated > 0, "route_201 has curated cross-gen entries (%d)" % curated)
	is_true(enc.total_weight("route_201", "grass") > 100,
		"merged weight exceeds the vanilla 100")

	# Curated entries really are from later generations.
	var found_modern := false
	for e: Dictionary in merged:
		if String(e["source"]) == "curated" and int(e["species"]) > 493:
			found_modern = true
	is_true(found_modern, "at least one curated species is post-Gen-4")

	# Every roll on the very first route respects the starting cap.
	GameState.reset()
	enc.rng.seed = 99
	var cap := GameState.current_level_cap()
	for i in 500:
		is_true(int(enc.roll("route_201", "grass")["level"]) <= cap,
			"a route_201 roll exceeded the cap")


# ==========================================================================
# 6. Warps and connections
# ==========================================================================

func test_a_warp_tile_travels_to_its_authored_cell() -> void:
	var w := Warps.warp_at(map, Vector2i(1, 1))
	is_false(w.is_empty(), "there is a warp at (1,1)")
	eq(Warps.validate(w, FIXTURE_MAPS), "", "the warp validates")

	GameState.reset()
	var seen: Array = []
	EventBus.map_changed.connect(func(id: StringName, cell: Vector2i) -> void:
		seen.append([String(id), cell]))
	is_true(Warps.apply(w, FIXTURE_MAPS), "the warp applied")
	eq(String(GameState.current_map), "test_hut", "map changed")
	eq(GameState.player_cell, Vector2i(2, 3), "arrived on the authored cell")
	eq(seen.size(), 1, "map_changed fired once")
	eq(String(seen[0][0]), "test_hut", "with the destination")

	is_true(Warps.warp_at(map, Vector2i(4, 4)).is_empty(), "no warp on a plain tile")


func test_a_broken_warp_is_refused_rather_than_stranding_the_player() -> void:
	Log.level = Log.Level.OFF
	var bad := MapLoader.load_map("test_bad_warp", FIXTURE_MAPS)
	if not check(bad != null, "test_bad_warp.json loaded"):
		return

	var missing := bad.warp_at(Vector2i(1, 1))
	is_true(Warps.validate(missing, FIXTURE_MAPS).contains("does not exist"),
		"a warp to a nonexistent map is rejected")

	var into_wall := bad.warp_at(Vector2i(2, 2))
	is_true(Warps.validate(into_wall, FIXTURE_MAPS).contains("blocked"),
		"a warp landing inside a wall is rejected")

	GameState.reset()
	GameState.current_map = &"test_bad_warp"
	is_false(Warps.apply(missing, FIXTURE_MAPS), "apply refuses")
	is_false(Warps.apply(into_wall, FIXTURE_MAPS), "apply refuses")
	eq(String(GameState.current_map), "test_bad_warp", "and nothing moved")


func test_walking_off_an_edge_uses_the_connection_and_lands_on_the_far_side() -> void:
	# (5,0) is the gap in the north wall; north connects to test_north (8x8).
	var res := attempt_with([], Vector2i(5, 0), Vector2i.UP)
	eq(kind_of(res), Collision.Result.EDGE, "leaving the map is EDGE, not BLOCKED")

	var seam := Warps.resolve_edge(map, Vector2i(5, 0), Vector2i.UP, FIXTURE_MAPS)
	is_false(seam.is_empty(), "the north connection resolved")
	eq(String(seam["to"]), "test_north", "destination")
	eq(String(seam["reason"]), "connection", "tagged as a connection")
	# You come out of the OPPOSITE edge at the same lateral offset.
	eq(int(seam["toX"]), 5, "same x")
	eq(int(seam["toY"]), 7, "bottom row of an 8-tall map")
	eq(Warps.validate(seam, FIXTURE_MAPS), "", "the derived cell is standable")

	# No connection that way -> nothing, so the edge is simply solid.
	is_true(Warps.resolve_edge(map, Vector2i(5, 11), Vector2i.DOWN, FIXTURE_MAPS).is_empty(),
		"no south connection")

	# The seam is symmetric: coming back south lands on the arena's top row.
	var north_map := MapLoader.load_map("test_north", FIXTURE_MAPS)
	var back := Warps.resolve_edge(north_map, Vector2i(5, 7), Vector2i.DOWN, FIXTURE_MAPS)
	eq(String(back["to"]), "test_arena", "back to the arena")
	eq(int(back["toY"]), 0, "top row")
	eq(int(back["toX"]), 5, "same x")

	eq(Warps.dir_name(Vector2i.UP), "north", "direction naming")
	eq(Warps.dir_name(Vector2i.RIGHT), "east", "direction naming")


# ==========================================================================
# 7. Integration -- the whole overworld node
# ==========================================================================

func test_the_overworld_node_wires_the_map_player_and_systems_together() -> void:
	var ow := Overworld.new()
	ow.map_dir = FIXTURE_MAPS
	ow.render = false            # no TileMapLayers, no texture load, no import pass
	tree.root.add_child(ow)
	await tree.process_frame
	ow.encounters.boot(ENC_FIXTURE)
	ow.encounters.rate_scale = 0.0     # no random battles mid-assertion
	ow.traversal.announce = false

	GameState.reset()
	is_true(ow.load_map("test_arena", Vector2i(4, 4)), "map loaded")
	eq(String(ow.map.id), "test_arena", "the right map")
	eq(String(GameState.current_map), "test_arena", "GameState follows")
	is_true(ow.player != null, "a player exists")
	eq(ow.player.cell, Vector2i(4, 4), "spawned where asked")
	is_true(ow.get_node_or_null("Entities/Player") != null,
		"the player is under Entities, for y-sorting")
	is_true(ow.y_sort_enabled, "the root y-sorts, or the layers' own flag does nothing")

	# Walk west three tiles: (4,4) -> (1,4), all floor.
	ow.player.facing = Vector2i.LEFT
	for i in 3:
		ow.player.tick(Vector2i.LEFT, false, 0.001)
		settle(ow.player)
	eq(ow.player.cell, Vector2i(1, 4), "walked three tiles west")

	# Into the border wall at x=0: blocked, through the real wiring.
	var before: int = ow.player.steps_taken
	for i in 60:
		ow.player.tick(Vector2i.LEFT, false, 1.0 / 60.0)
	eq(ow.player.cell, Vector2i(1, 4), "the border wall holds")
	eq(ow.player.steps_taken, before, "no step was taken")

	# Now the headline feature, end to end: walk into deep water with the badge.
	ow.player.snap_to(Vector2i(7, 7))
	ow.player.facing = Vector2i.RIGHT
	is_false(ow.surfing(), "on foot")
	ow.player.tick(Vector2i.RIGHT, false, 0.001)
	settle(ow.player)
	eq(ow.player.cell, Vector2i(7, 7), "deep water blocks without the Fen badge")

	GameState.earn_badge("fen")
	ow.player.tick(Vector2i.RIGHT, false, 0.001)
	settle(ow.player)
	eq(ow.player.cell, Vector2i(8, 7), "and auto-surfs with it")
	is_true(ow.surfing(), "now surfing")

	ow.queue_free()
	await tree.process_frame


func test_a_grass_step_in_the_real_node_produces_a_capped_encounter() -> void:
	var ow := Overworld.new()
	ow.map_dir = FIXTURE_MAPS
	ow.render = false
	tree.root.add_child(ow)
	await tree.process_frame
	ow.encounters.boot(ENC_FIXTURE)
	ow.encounters.rng.seed = 31337
	ow.encounters.min_steps_between = 0
	ow.traversal.announce = false

	GameState.reset()
	var cap := GameState.current_level_cap()
	var rolls: Array = []
	ow.encounter.connect(func(d: Dictionary) -> void: rolls.append(d))

	is_true(ow.load_map("test_arena", Vector2i(2, 9)), "spawned in the grass")
	eq(ow.map.code_at(Vector2i(2, 9)), Collision.TALL_GRASS, "precondition")

	# Pace back and forth across the grass patch at (1..3, 8..10).
	var dirs: Array = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.LEFT]
	var i := 0
	while rolls.is_empty() and i < 400:
		var d: Vector2i = dirs[i % dirs.size()]
		ow.player.facing = d
		ow.player.tick(d, false, 0.001)
		settle(ow.player)
		i += 1
	is_true(not rolls.is_empty(), "an encounter fired while pacing the grass (%d steps)" % i)
	is_true(int(rolls[0]["level"]) <= cap,
		"level %d <= cap %d" % [int(rolls[0]["level"]), cap])
	is_true(int(rolls[0]["species"]) > 0, "a real species")
	eq(String(rolls[0]["zone"]), "test_arena", "from the map's encounter zone")

	ow.queue_free()
	await tree.process_frame


# ==========================================================================
# 8. Rendering -- TileMapLayer, not TileMap
# ==========================================================================

func test_build_layers_makes_three_tilemaplayers_in_the_right_z_order() -> void:
	var root := Node2D.new()
	tree.root.add_child(root)
	await tree.process_frame

	var layers := MapLoader.build_layers(map, root, null)
	eq(layers.size(), 3, "three layers")
	is_true(root.y_sort_enabled,
		"the parent y-sorts: a layer's own flag does nothing without it (arch 1.3)")

	for layer_name: String in ["ground", "overlay", "above"]:
		var l: TileMapLayer = layers[layer_name]
		# `is TileMap` will not even compile against a TileMapLayer, so the
		# class name is the check that survives the type checker.
		eq(l.get_class(), "TileMapLayer",
			"'%s' is a TileMapLayer, not the deprecated TileMap" % layer_name)
		eq(l.z_index, int(MapLoader.LAYER_Z[layer_name]), "'%s' z_index" % layer_name)
		is_true(root.get_node_or_null(NodePath(layer_name.capitalize())) != null,
			"'%s' is in the tree" % layer_name)
	is_true((layers["ground"] as TileMapLayer).z_index
		< (layers["above"] as TileMapLayer).z_index,
		"ground draws under the above-layer")
	is_true((layers["overlay"] as TileMapLayer).y_sort_enabled,
		"the entity-height layer y-sorts")

	root.queue_free()
	await tree.process_frame


func test_a_real_tileset_paints_the_cells_the_map_asked_for() -> void:
	# The atlas is ROM-derived (assets/generated/, gitignored), so this is a
	# pending rather than a failure when the extraction pipeline has not run.
	var meta := "res://data/tilesets/outdoor_sinnoh.json"
	if not FileAccess.file_exists(meta):
		pending("data/tilesets/outdoor_sinnoh.json not built")
		return
	# Exercise the SYNTHESISED path explicitly -- make_tileset() would prefer an
	# authored res://resources/outdoor_sinnoh.tres when the tileset stream has
	# written one, and both must produce the same index -> atlas mapping.
	var ts := MapLoader.synthesize_tileset("outdoor_sinnoh")
	if ts == null:
		pending("assets/generated/tilesets/outdoor_sinnoh.png not extracted yet")
		return
	var preferred := MapLoader.make_tileset("outdoor_sinnoh")
	is_true(preferred != null, "make_tileset returns something")
	var pref_src := preferred.get_source(0) as TileSetAtlasSource
	is_true(pref_src != null, "and it has an atlas source")
	eq(pref_src.get_atlas_grid_size(), (ts.get_source(0) as TileSetAtlasSource).get_atlas_grid_size(),
		"authored and synthesised tilesets agree on the atlas grid")

	var src := ts.get_source(0) as TileSetAtlasSource
	is_true(src != null, "the tileset has an atlas source")
	eq(ts.tile_size, Vector2i(16, 16), "16px tiles")
	is_true(src.texture != null, "with a real texture")
	is_true(src.texture.get_width() >= 16 and src.texture.get_height() >= 16,
		"atlas is %dx%d" % [src.texture.get_width(), src.texture.get_height()])
	is_true(src.get_tiles_count() > 0, "%d tiles created" % src.get_tiles_count())

	# Cross-check the Python pipeline against Godot: `columns` in the tileset
	# JSON is what MapLoader.paint() divides a linear tile index by, so if it
	# disagreed with the atlas's real grid width every map would be scrambled
	# while every script still exited 0.
	var meta_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta))
	eq(src.get_atlas_grid_size().x, int(meta_json["columns"]),
		"tileset JSON `columns` matches the atlas grid width Godot computes")
	is_true(src.get_tiles_count() >= int(meta_json["tileCount"]),
		"at least the declared %d tiles exist" % int(meta_json["tileCount"]))

	var root := Node2D.new()
	tree.root.add_child(root)
	await tree.process_frame
	var layers := MapLoader.build_layers(map, root, ts)

	# The fixture paints ground index 1 everywhere, 10 overlay cells and 1 above.
	var ground: TileMapLayer = layers["ground"]
	var overlay: TileMapLayer = layers["overlay"]
	var above: TileMapLayer = layers["above"]
	eq(ground.get_used_cells().size(), 144, "every ground cell painted")
	eq(overlay.get_used_cells().size(), 10, "9 grass overlay cells + 1 ledge cell")
	eq(above.get_used_cells().size(), 1, "one above-layer treetop")
	is_true(above.get_used_cells().has(Vector2i(6, 1)), "and it is at (6,1)")

	# A painted cell really resolves to tile data, not an empty cell.
	is_true(ground.get_cell_tile_data(Vector2i(4, 4)) != null,
		"a painted cell has tile data")
	is_true(overlay.get_cell_tile_data(Vector2i(0, 0)) == null,
		"an unpainted cell is genuinely empty")
	# Linear tile index -> atlas coords uses the tileset's own column count.
	eq(ground.get_cell_atlas_coords(Vector2i(4, 4)), Vector2i(1, 0),
		"ground index 1 maps to atlas column 1, row 0")

	root.queue_free()
	await tree.process_frame
