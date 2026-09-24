extends "res://tests/framework/test_case.gd"
## `data/maps/*.json` -- the committed, hand-authored geometry (DATA_CONTRACT 9).
##
## These are CONTENT tests, not logic tests: every check here is about the data on
## disk, loaded through the real `map_loader.gd`. `tools/build_maps.py` asserts the
## same invariants at author time; this file is what stops a later hand-edit of the
## JSON from quietly breaking them, because the Python generator is not run by CI
## and a hand-edited map would sail straight through.
##
## THE TWO THAT MATTER MOST
##
## 1. NO SOFT-LOCK. A cross-map BFS over the warp graph proves a player with NO
##    badges can still walk Twinleaf -> the tile in front of Roark. Roark is the
##    boss who *awards* the Coal badge, so if the Oreburgh Gate rock ever ended up
##    on the main corridor the slice would be unwinnable -- and nothing else in the
##    suite would notice.
## 2. THE ROCK GATES SOMETHING. The same BFS proves the alcove behind it is
##    unreachable without Coal and reachable with it. A gate that gates nothing is
##    the other way this content silently rots.

const MapLoader := preload("res://src/overworld/map_loader.gd")
const Collision := preload("res://src/systems/collision.gd")
const Traversal := preload("res://src/systems/traversal.gd")
const Warps := preload("res://src/overworld/warps.gd")
const Encounters := preload("res://src/systems/encounters.gd")

const MAP_DIR := "res://data/maps"

## The slice, in order. Every neighbouring pair must warp BOTH ways.
const CHAIN: Array = [
	"twinleaf_town", "route_201", "sandgem_town", "route_202", "jubilife_city",
	"route_203", "oreburgh_gate", "oreburgh_city", "oreburgh_gym",
]
## Routes that must carry tall grass wired to an encounter zone.
const GRASS_ROUTES: Array = ["route_201", "route_202", "route_203"]

const START_MAP := "twinleaf_town"
const START_CELL := Vector2i(12, 12)
## The walkable tile you stand on to face Roark at (6,3).
const ROARK_STAND := Vector2i(6, 4)
## Behind the smash rock in Oreburgh Gate.
const ALCOVE := Vector2i(5, 2)

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	DataRegistry.boot(DataRegistry.DATA_DIR)
	EventBus.disconnect_all()
	GameState.track_playtime = false
	GameState.reset()


func after_each() -> void:
	EventBus.disconnect_all()
	GameState.track_playtime = true
	DataRegistry.boot(DataRegistry.DATA_DIR)
	Log.level = _saved_level


func _load(map_id: String) -> Object:
	return MapLoader.load_map(map_id, MAP_DIR)


func _all() -> Dictionary:
	var out: Dictionary = {}
	for map_id: String in CHAIN:
		var m: Object = _load(map_id)
		if m != null:
			out[map_id] = m
	return out


# --------------------------------------------------------------------------

func test_every_slice_map_loads_with_the_contract_shape() -> void:
	for map_id: String in CHAIN:
		var m: Object = _load(map_id)
		if not check(m != null, "%s failed to load from %s" % [map_id, MAP_DIR]):
			continue
		eq(String(m.id), map_id, "%s id" % map_id)
		eq(String(m.source), "data", "%s came from data/, not a fixture" % map_id)
		is_true(int(m.width) > 0 and int(m.height) > 0, "%s has a real size" % map_id)
		eq(int(m.tile_size), 16, "%s tileSize" % map_id)
		eq(String(m.tileset), "outdoor_sinnoh", "%s tileset" % map_id)
		var cells: int = int(m.width) * int(m.height)
		eq((m.collision as PackedInt32Array).size(), cells, "%s collision cell count" % map_id)
		for layer_name: String in ["ground", "overlay", "above"]:
			is_true((m.layers as Dictionary).has(layer_name),
				"%s has a '%s' layer" % [map_id, layer_name])
			eq((m.layers[layer_name] as PackedInt32Array).size(), cells,
				"%s layer '%s' cell count" % [map_id, layer_name])


func test_every_collision_code_is_one_the_contract_defines() -> void:
	for map_id: String in CHAIN:
		var m: Object = _load(map_id)
		if m == null:
			continue
		var seen: Dictionary = {}
		for c: int in (m.collision as PackedInt32Array):
			seen[c] = true
			is_true(c >= 0 and c <= 7, "%s has collision code %d, outside 0..7" % [map_id, c])
		# A map made entirely of one code is a drawing that went wrong.
		is_true(seen.size() >= 2, "%s uses only %d distinct collision code(s)" % [map_id, seen.size()])


func test_every_adjacency_warps_both_ways_onto_a_walkable_tile() -> void:
	var maps := _all()
	if not check(maps.size() == CHAIN.size(), "all %d slice maps present" % CHAIN.size()):
		return

	for i in CHAIN.size() - 1:
		var a: String = CHAIN[i]
		var b: String = CHAIN[i + 1]
		for pair: Array in [[a, b], [b, a]]:
			var src: Object = maps[pair[0]]
			var found := false
			for cell: Vector2i in (src.warps as Dictionary):
				if String((src.warps[cell] as Dictionary)["to"]) == String(pair[1]):
					found = true
					break
			is_true(found, "%s has no warp to %s" % [pair[0], pair[1]])

	# Every warp in every map: standable source, real destination, walkable arrival.
	for map_id: String in maps:
		var m: Object = maps[map_id]
		for cell: Vector2i in (m.warps as Dictionary):
			var w: Dictionary = m.warps[cell]
			is_true(Collision.LAND_CODES.has(int(m.code_at(cell))),
				"%s warp tile %s is collision %d, so it can never be stepped on"
					% [map_id, cell, int(m.code_at(cell))])
			eq(Warps.validate(w, MAP_DIR), "",
				"%s warp %s -> %s" % [map_id, cell, w.get("to")])


func test_a_warp_and_its_return_do_not_bounce_the_player_back() -> void:
	# Arriving ON the return warp tile would ping-pong the player the moment they
	# stepped anywhere and came back. The arrival must be a tile NEXT TO the return
	# warp, not the return warp itself.
	var maps := _all()
	if maps.size() != CHAIN.size():
		pending("data/maps is incomplete")
		return
	for map_id: String in maps:
		var m: Object = maps[map_id]
		for cell: Vector2i in (m.warps as Dictionary):
			var w: Dictionary = m.warps[cell]
			var dest: Object = maps.get(String(w["to"]), null)
			if dest == null:
				continue
			var arrival := Vector2i(int(w["toX"]), int(w["toY"]))
			var back: Dictionary = dest.warp_at(arrival)
			is_true(back.is_empty() or String(back.get("to", "")) != map_id,
				"%s -> %s lands on %s, which warps straight back to %s"
					% [map_id, w["to"], arrival, map_id])


func test_the_routes_carry_tall_grass_wired_to_a_real_encounter_zone() -> void:
	var enc := Encounters.new()
	var have_rom := enc.boot() and enc.source() == "data"

	for map_id: String in GRASS_ROUTES:
		var m: Object = _load(map_id)
		if not check(m != null, "%s loads" % map_id):
			continue
		var grass := 0
		for c: int in (m.collision as PackedInt32Array):
			if c == Collision.TALL_GRASS:
				grass += 1
		is_true(grass >= 20, "%s has only %d tall-grass tiles" % [map_id, grass])

		var zone := String(m.encounter_zone)
		is_false(zone.is_empty(), "%s declares an encounterZone" % map_id)
		if not have_rom:
			pending("%s: data/rom/encounters.json is not built, so zone '%s' is unverified"
				% [map_id, zone])
			continue
		is_true(enc.has_zone(zone), "zone '%s' exists in data/rom/encounters.json" % zone)
		is_true(enc.encounter_chance(zone, "grass") > 0.0,
			"zone '%s' has a non-zero grass rate" % zone)
		is_true(enc.total_weight(zone, "grass") > 0,
			"zone '%s' has a non-empty merged grass table" % zone)


func test_a_grass_step_on_each_route_rolls_a_wild_pokemon_under_the_cap() -> void:
	var enc := Encounters.new()
	if not enc.boot() or enc.source() != "data":
		pending("data/rom/encounters.json is not built")
		return
	enc.rng.seed = 424242
	enc.min_steps_between = 0
	enc.rate_scale = 50.0                      # force the roll; the table is what is under test
	var cap := GameState.current_level_cap()

	for map_id: String in GRASS_ROUTES:
		var m: Object = _load(map_id)
		if m == null:
			continue
		var zone := String(m.encounter_zone)
		var got := 0
		for _i in 40:
			var roll := enc.step(Collision.TALL_GRASS, zone)
			if roll.is_empty():
				continue
			got += 1
			is_true(DataRegistry.has_species(int(roll["species"])),
				"%s rolled species %d, which is not in species.json" % [zone, int(roll["species"])])
			is_true(int(roll["level"]) >= 1 and int(roll["level"]) <= cap,
				"%s rolled L%d against cap %d" % [zone, int(roll["level"]), cap])
		is_true(got > 0, "%s produced no encounters in 40 grass steps" % zone)


func test_oreburgh_gate_has_exactly_one_smash_obstacle_needing_the_coal_badge() -> void:
	var m: Object = _load("oreburgh_gate")
	if not check(m != null, "oreburgh_gate loads"):
		return
	var smashes: Array = []
	for cell: Vector2i in (m.traversal as Dictionary):
		var t: Dictionary = m.traversal[cell]
		is_true(Traversal.is_verb(String(t["type"])),
			"obstacle at %s has type '%s', which is not a verb" % [cell, t["type"]])
		neq(String(t["type"]), "defog", "there is no defog verb")
		if String(t["type"]) == "smash":
			smashes.append(cell)
	eq(smashes.size(), 1, "exactly one smash obstacle")
	if smashes.is_empty():
		return
	var rock: Vector2i = smashes[0]
	eq(String((m.traversal[rock] as Dictionary)["requires"]), "badge:coal", "smash requires")
	is_true(Collision.LAND_CODES.has(int(m.code_at(rock))),
		"the tile under the rock is collision %d; clearing it would strand the player"
			% int(m.code_at(rock)))
	eq(Traversal.badge_for("smash"), "coal", "smash is bound to the Coal badge")


func test_the_rock_blocks_without_coal_and_shatters_with_it() -> void:
	var m: Object = _load("oreburgh_gate")
	if m == null:
		return
	var rock := Vector2i(-1, -1)
	for cell: Vector2i in (m.traversal as Dictionary):
		if String((m.traversal[cell] as Dictionary)["type"]) == "smash":
			rock = cell
			break
	if not check(rock.x >= 0, "found the smash rock"):
		return
	# Approach it from the south -- the alcove runs north off the main corridor.
	var from := rock + Vector2i.DOWN

	var t := Traversal.new()
	t.announce = false
	t.on_map_loaded(m.id)
	t.badge_gate = func(_v: String) -> bool: return false
	var blocked := t.attempt(m, from, Vector2i.UP)
	eq(int(blocked["kind"]), Collision.Result.BLOCKED, "badgeless: blocked")
	eq(String(blocked["reason"]), "no-badge", "badgeless: reason")
	eq(String(blocked["performed"]), "", "badgeless: nothing fired")
	is_true(String(blocked["message"]).contains("Coal"),
		"the refusal names the Coal Badge: %s" % blocked["message"])
	eq(t.cleared_count(), 0, "badgeless: the rock is still there")

	var t2 := Traversal.new()
	t2.announce = false
	t2.on_map_loaded(m.id)
	t2.badge_gate = func(v: String) -> bool: return v == "smash"
	var ok := t2.attempt(m, from, Vector2i.UP)
	eq(int(ok["kind"]), Collision.Result.TRAVERSE, "with Coal: traverses")
	eq(String(ok["performed"]), "smash", "with Coal: smash fired")
	eq(Vector2i(ok["target"]), rock, "with Coal: steps onto the rock's tile")
	eq(t2.cleared_count(), 1, "with Coal: the rock is gone")
	# and it stays gone until the map reloads, exactly as in vanilla
	is_true(t2.is_cleared(rock), "cleared for this visit")
	t2.on_map_loaded(m.id)
	eq(t2.cleared_count(), 0, "obstacles respawn on map reload")


# --------------------------------------------------------------------------
# Reachability
# --------------------------------------------------------------------------

## Every (map, cell) a walking player holding `badges` can get to from `start`,
## crossing warps. Mirrors `world_bfs()` in tools/build_maps.py.
func _reach(maps: Dictionary, start: Array, badges: Array) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		var map_id: String = cur[0]
		var cell: Vector2i = cur[1]
		var m: Object = maps[map_id]

		var w: Dictionary = m.warp_at(cell)
		if not w.is_empty() and maps.has(String(w["to"])):
			var nxt: Array = [String(w["to"]), Vector2i(int(w["toX"]), int(w["toY"]))]
			if not seen.has(nxt):
				seen[nxt] = true
				queue.append(nxt)
			continue           # a warp tile moves you; you do not walk off it

		for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var target: Vector2i = cell + dir
			if not m.in_bounds(target):
				continue
			var landed := target
			var ob: Dictionary = m.traversal_at(target)
			if not ob.is_empty():
				var req := String(ob.get("requires", ""))
				if not req.begins_with("badge:") or not badges.has(req.substr(6)):
					continue
			elif int(m.code_at(target)) == Collision.LEDGE:
				if dir != Vector2i.DOWN:
					continue
				landed = cell + dir * 2
				if not m.in_bounds(landed) or not Collision.LAND_CODES.has(int(m.code_at(landed))):
					continue
			elif not Collision.LAND_CODES.has(int(m.code_at(target))):
				continue
			var state: Array = [map_id, landed]
			if not seen.has(state):
				seen[state] = true
				queue.append(state)
	return seen


func test_a_badgeless_player_can_walk_from_twinleaf_to_roark() -> void:
	var maps := _all()
	if not check(maps.size() == CHAIN.size(), "all %d slice maps present" % CHAIN.size()):
		return
	var start: Array = [START_MAP, START_CELL]
	is_true(Collision.LAND_CODES.has(int((maps[START_MAP] as Object).code_at(START_CELL))),
		"the start cell %s is walkable" % START_CELL)

	var reach := _reach(maps, start, [])
	is_true(reach.has([&"oreburgh_gym", ROARK_STAND]) or reach.has(["oreburgh_gym", ROARK_STAND]),
		"SOFT-LOCK: the tile in front of Roark is not reachable with no badges")
	for map_id: String in CHAIN:
		var touched := false
		for k: Variant in reach:
			if String((k as Array)[0]) == map_id:
				touched = true
				break
		is_true(touched, "map '%s' is unreachable from the start with no badges" % map_id)


func test_the_smash_alcove_is_the_only_thing_the_coal_badge_opens_here() -> void:
	var maps := _all()
	if maps.size() != CHAIN.size():
		pending("data/maps is incomplete")
		return
	var start: Array = [START_MAP, START_CELL]
	var without := _reach(maps, start, [])
	var with_coal := _reach(maps, start, ["coal"])

	is_false(without.has(["oreburgh_gate", ALCOVE]),
		"the alcove %s is reachable with no badges; the rock gates nothing" % ALCOVE)
	is_true(with_coal.has(["oreburgh_gate", ALCOVE]),
		"the alcove %s is still unreachable with the Coal badge" % ALCOVE)
	is_true(with_coal.size() > without.size(),
		"the Coal badge opened nothing at all (%d cells either way)" % without.size())


func test_every_interactable_object_sits_on_a_blocked_tile_you_can_reach() -> void:
	# An object on a walkable tile is an object you walk straight through, and can
	# therefore never face to talk to: src/systems/collision.gd knows nothing about
	# the `objects` array, so the grid is the only thing that stops the step.
	var maps := _all()
	if maps.size() != CHAIN.size():
		pending("data/maps is incomplete")
		return
	var reach := _reach(maps, [START_MAP, START_CELL], ["coal"])
	for map_id: String in maps:
		var m: Object = maps[map_id]
		for o: Variant in (m.objects as Array):
			if not (o is Dictionary):
				continue
			var d: Dictionary = o
			var cell := Vector2i(int(d.get("x", -1)), int(d.get("y", -1)))
			var kind := String(d.get("type", ""))
			if kind == "spawn":
				is_true(Collision.LAND_CODES.has(int(m.code_at(cell))),
					"%s spawn '%s' at %s is not walkable" % [map_id, d.get("id"), cell])
				continue
			eq(int(m.code_at(cell)), Collision.BLOCK,
				"%s %s '%s' at %s must be on a blocked tile" % [map_id, kind, d.get("id"), cell])
			var adjacent := false
			for dir: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if reach.has([map_id, cell + dir]):
					adjacent = true
					break
			is_true(adjacent, "%s %s '%s' at %s cannot be stood next to"
				% [map_id, kind, d.get("id"), cell])


func test_roark_is_on_the_gym_map_and_names_a_real_boss() -> void:
	var m: Object = _load("oreburgh_gym")
	if not check(m != null, "oreburgh_gym loads"):
		return
	var roark: Dictionary = {}
	for o: Variant in (m.objects as Array):
		if o is Dictionary and String((o as Dictionary).get("type", "")) == "boss":
			roark = o
			break
	if not check(not roark.is_empty(), "the gym has a boss object"):
		return
	eq(String(roark.get("boss", "")), "roark", "the boss key")
	eq(Vector2i(int(roark["x"]), int(roark["y"])), Vector2i(6, 3), "Roark's tile")
	is_true((roark.get("lines", []) as Array).size() > 0, "he has something to say")
	is_true((roark.get("afterLines", []) as Array).size() > 0, "and something after losing")
