extends "res://tests/framework/test_case.gd"
## The evolution rework: every evolution in the game can actually be performed.
##
## This is a single-player game with no link cable, no clock, no Alola or Galar
## locations and no Legends: Arceus move styles. 73 of veekun's 500 evolution
## edges therefore cannot be performed at all, and `tools/fix_evolutions.py` holds
## the owner-approved replacement table (docs/research/evolution-audit.md §4),
## applied by `tools/build_species.py` as part of the build.
##
## WHY THIS LIVES IN THE GODOT SUITE. The pass is Python and asserts on its own
## output, but `data/species.json` is committed and can be edited by hand, by a
## merge, or by an upstream veekun change that shifts a row out from under the
## design table. This file is the check that runs in the suite James actually
## runs, and it asserts on the shipped data rather than on the tool.
##
## Sweeps here are property-based, not count-based: a count would break on any
## upstream data refresh without telling anyone anything useful.

## Methods that cannot be performed. Mirrors `fix_evolutions.DEAD_METHODS`.
const DEAD_METHODS: Array = [
	"trade", "use-move", "take-damage", "spin", "recoil-damage",
	"three-critical-hits", "three-defeated-bisharp", "agile-style-move",
	"strong-style-move", "in-battle-level-up", "tower-of-darkness",
	"tower-of-waters", "meltan-candies", "gimmighoul-coins",
]

## Conditions that can never be satisfied. Mirrors `fix_evolutions.DEAD_KEYS`.
const DEAD_KEYS: Array = [
	"timeOfDay", "location", "beauty", "upsideDown", "needsRain", "tradeSpecies",
]

## L37 for every plain trade evolution: one above the Fantina cap (36), so the
## line unlocks the moment the Relic Badge lifts the cap to 45, and it keeps
## Machamp, Golem and Gengar out of the windows game-design.md §5.2 bans them
## from. Also the value the owner's reference ROM patch uses.
const TRADE_LEVEL := 37

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	DataRegistry.boot(DataRegistry.DATA_DIR)


func after_each() -> void:
	Log.level = _saved_level


func _have_real_species() -> bool:
	return DataRegistry.source_of("species") == "data" \
		and DataRegistry.species_count() >= 1025


## Every evolution edge in the game, as `[from_dex, edge]` pairs.
func _all_edges() -> Array:
	var out: Array = []
	for dex in range(1, DataRegistry.species_count() + 1):
		var sp: Dictionary = DataRegistry.get_species(dex)
		if sp.is_empty():
			continue
		for edge: Variant in (sp.get("evolutions", []) as Array):
			if edge is Dictionary:
				out.append([dex, edge as Dictionary])
	return out


## The edges out of `from_dex` that lead to `to_dex`.
func _routes(from_dex: int, to_dex: int) -> Array:
	var out: Array = []
	for edge: Variant in (DataRegistry.get_species(from_dex).get("evolutions", []) as Array):
		if edge is Dictionary and int((edge as Dictionary).get("to", 0)) == to_dex:
			out.append(edge)
	return out


## Every edge that leads to `to_dex`, from anywhere.
func _routes_into(to_dex: int) -> Array:
	var out: Array = []
	for pair: Array in _all_edges():
		if int((pair[1] as Dictionary).get("to", 0)) == to_dex:
			out.append(pair[1])
	return out


# ==========================================================================
# the sweeps -- nothing unperformable may survive anywhere in the dex
# ==========================================================================

func test_no_evolution_uses_an_unperformable_method() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var offenders := PackedStringArray()
	for pair: Array in _all_edges():
		var method := String((pair[1] as Dictionary).get("method", ""))
		if DEAD_METHODS.has(method):
			offenders.append("#%d -> %d (%s)" % [
				pair[0], int((pair[1] as Dictionary).get("to", 0)), method])
	eq(Array(offenders), [], "no edge uses a method this game cannot perform")


func test_no_evolution_carries_an_unsatisfiable_condition() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var offenders := PackedStringArray()
	for pair: Array in _all_edges():
		var edge: Dictionary = pair[1]
		for key: String in DEAD_KEYS:
			if edge.has(key):
				offenders.append("#%d -> %d (%s)" % [
					pair[0], int(edge.get("to", 0)), key])
	eq(Array(offenders), [], "no edge waits on a clock, a place or a trade partner")


## A `level-up` edge with no level and no other condition fires the instant the
## Pokemon gains a level, which eats every sibling branch on the same species.
## Eevee is the extreme case: two of these would consume all eight Eeveelutions.
func test_no_edge_is_a_bare_level_up() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var offenders := PackedStringArray()
	for pair: Array in _all_edges():
		var edge: Dictionary = pair[1]
		if String(edge.get("method", "")) != "level-up":
			continue
		var conditions: Array = edge.keys().filter(
			func(k: Variant) -> bool: return String(k) != "to" and String(k) != "method")
		if conditions.is_empty():
			offenders.append("#%d -> %d" % [pair[0], int(edge.get("to", 0))])
	eq(Array(offenders), [], "every level-up edge has a level or a condition")


## Whatever the method, an edge has to say something about WHEN. Catches a future
## table row that drops a condition without supplying a replacement.
func test_every_edge_has_a_method_this_engine_knows() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var known: Array = ["level-up", "use-item", "shed"]
	var offenders := PackedStringArray()
	for pair: Array in _all_edges():
		var method := String((pair[1] as Dictionary).get("method", ""))
		if not known.has(method):
			offenders.append("#%d: %s" % [pair[0], method])
	eq(Array(offenders), [], "only level-up, use-item and shed survive the rework")


# ==========================================================================
# the owner's four rules, spot-checked where they matter most
# ==========================================================================

## Rule 1: a plain trade becomes a level-up at L37. These four are the headline
## cases and the ones game-design.md §5.2 constrains by type.
func test_the_plain_trade_evolutions_became_level_37() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var cases: Dictionary = {
		65: 64,    # Alakazam  <- Kadabra
		68: 67,    # Machamp   <- Machoke   (Fighting, banned before Roark)
		76: 75,    # Golem     <- Graveler  (Rock/Ground, banned before Roark)
		94: 93,    # Gengar    <- Haunter   (Ghost, banned before Fantina)
		534: 533,  # Conkeldurr
		711: 710,  # Gourgeist
	}
	for to: int in cases:
		var routes := _routes(int(cases[to]), to)
		eq(routes.size(), 1, "#%d has exactly one route in" % to)
		if routes.is_empty():
			continue
		var edge: Dictionary = routes[0]
		eq(String(edge.get("method", "")), "level-up", "#%d evolves by level-up" % to)
		eq(int(edge.get("level", 0)), TRADE_LEVEL, "#%d at L%d" % [to, TRADE_LEVEL])


## Gengar is the case the cap curve was checked against: Fantina is gym 3 (cap
## 36), she Mega Evolves Gengar, and she is who awards the Gengarite. L37 puts
## Gengar in the player's hands the moment that fight is won -- stone and species
## arriving together -- and keeps Ghost out of the pre-Fantina window §5.2 bans.
func test_gengar_lands_exactly_when_the_gengarite_does() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var routes := _routes(93, 94)
	eq(routes.size(), 1, "Haunter has one route to Gengar")
	if routes.is_empty():
		return
	eq(int((routes[0] as Dictionary).get("level", 0)), 37,
		"L37: one above the Fantina cap of 36, so it unlocks with the Relic Badge")


## Rule 2: trade-while-holding becomes level-up-while-holding. The item stays the
## gate, which is what keeps these cap-neutral.
func test_trade_with_item_became_level_up_holding_that_item() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var cases: Dictionary = {
		212: [123, "metal-coat"],     # Scizor    <- Scyther
		230: [117, "dragon-scale"],   # Kingdra   <- Seadra
		464: [112, "protector"],      # Rhyperior <- Rhydon
		466: [125, "electirizer"],    # Electivire
		467: [126, "magmarizer"],     # Magmortar
		477: [356, "reaper-cloth"],   # Dusknoir
		186: [61, "kings-rock"],      # Politoed  <- Poliwhirl
	}
	for to: int in cases:
		var want: Array = cases[to]
		var routes := _routes(int(want[0]), to)
		var found := false
		for edge: Dictionary in routes:
			if String(edge.get("method", "")) == "level-up" \
					and String(edge.get("heldItem", "")) == String(want[1]):
				found = true
				is_false(edge.has("level"),
					"#%d is gated by the item, not by a level" % to)
		is_true(found, "#%d evolves by levelling up holding %s" % [to, want[1]])


## Rule 3, and the reason deleting an edge is safe: the 11 deleted edges were
## impossible AND redundant. Each of these species keeps a working route.
func test_the_deleted_edges_left_every_species_a_route() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	# Magnezone/Probopass lost their magnetic-field location edge; Leafeon and
	# Glaceon lost their mossy/icy rock edges. All four keep a stone.
	var cases: Dictionary = {
		462: [82, "thunder-stone"],   # Magnezone <- Magneton
		476: [299, "thunder-stone"],  # Probopass <- Nosepass
		470: [133, "leaf-stone"],     # Leafeon   <- Eevee
		471: [133, "ice-stone"],      # Glaceon   <- Eevee
	}
	for to: int in cases:
		var want: Array = cases[to]
		var routes := _routes(int(want[0]), to)
		eq(routes.size(), 1, "#%d has exactly one surviving route" % to)
		if routes.is_empty():
			continue
		var edge: Dictionary = routes[0]
		eq(String(edge.get("method", "")), "use-item", "#%d is a stone evolution" % to)
		eq(String(edge.get("item", "")), String(want[1]), "#%d uses the %s" % [to, want[1]])


## Feebas is why the design table has to be matched on its condition, not on
## (target, method): both of its routes to Milotic were `level-up` once the trade
## edge was converted. The Beauty edge is deleted, so exactly one survives.
func test_feebas_has_exactly_one_route_to_milotic() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var routes := _routes(349, 350)
	eq(routes.size(), 1, "one route, not two")
	if routes.is_empty():
		return
	var edge: Dictionary = routes[0]
	eq(String(edge.get("method", "")), "level-up", "by levelling up")
	eq(String(edge.get("heldItem", "")), "prism-scale", "while holding the Prism Scale")
	is_false(edge.has("beauty"), "and Beauty is gone -- this game has no contest stats")


## The owner's explicit carve-out: evolution stones are NOT impossible and must be
## left completely alone. If the pass ever starts rewriting use-item edges, these
## are what notice.
func test_evolution_stones_were_left_alone() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var cases: Dictionary = {
		26: [25, "thunder-stone"],    # Raichu    <- Pikachu
		36: [35, "moon-stone"],       # Clefable  <- Clefairy
		45: [44, "leaf-stone"],       # Vileplume <- Gloom
		121: [120, "water-stone"],    # Starmie   <- Staryu
		136: [133, "fire-stone"],     # Flareon   <- Eevee
	}
	for to: int in cases:
		var want: Array = cases[to]
		var found := false
		for edge: Dictionary in _routes(int(want[0]), to):
			if String(edge.get("method", "")) == "use-item" \
					and String(edge.get("item", "")) == String(want[1]):
				found = true
		is_true(found, "#%d is still a %s evolution" % [to, want[1]])


## Eevee is the branch-collision stress case: eight routes, each separated by its
## own item or condition, and not one of them a bare level-up.
func test_eevee_keeps_eight_separable_branches() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var routes: Array = DataRegistry.get_species(133).get("evolutions", [])
	eq(routes.size(), 8, "eight Eeveelutions")
	var targets: Array = []
	for edge: Dictionary in routes:
		targets.append(int(edge.get("to", 0)))
		var conditions: Array = edge.keys().filter(
			func(k: Variant) -> bool: return String(k) != "to" and String(k) != "method")
		is_false(conditions.is_empty(),
			"the route to #%d is separable" % int(edge.get("to", 0)))
	targets.sort()
	eq(targets, [134, 135, 136, 196, 197, 470, 471, 700], "all eight targets")


## Every species that something evolves into must be reachable by SOME edge -- a
## rewrite that orphans a target is worse than the impossible edge it replaced.
## `tools/check_reachability.py` is the full version of this over all 1025.
func test_no_evolution_target_was_orphaned() -> void:
	if not _have_real_species():
		pending("data/species.json is not built")
		return
	var orphans := PackedStringArray()
	for dex in range(1, DataRegistry.species_count() + 1):
		var sp: Dictionary = DataRegistry.get_species(dex)
		if sp.is_empty() or sp.get("evolvesFrom", null) == null:
			continue
		if _routes_into(dex).is_empty():
			orphans.append("#%d %s" % [dex, sp.get("name", "?")])
	eq(Array(orphans), [], "every evolved species has at least one route in")
