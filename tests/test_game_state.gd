extends "res://tests/framework/test_case.gd"
## GameState: badge bitflags, the level cap ladder, and the hard exp stop.

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	DataRegistry.boot(DataRegistry.FIXTURE_DIR)
	EventBus.disconnect_all()
	GameState.track_playtime = false
	GameState.reset()


func after_each() -> void:
	EventBus.disconnect_all()
	Log.level = _saved_level
	GameState.track_playtime = true


# --- badges ---------------------------------------------------------------

func test_badges_start_empty() -> void:
	eq(GameState.badges, 0, "bitfield")
	eq(GameState.badge_count(), 0, "count")
	is_false(GameState.has_badge("coal"), "no coal badge")
	eq(GameState.badge_names().size(), 0, "no names")


func test_earn_badge_sets_exactly_one_bit() -> void:
	is_true(GameState.earn_badge("coal"), "first earn returns true")
	eq(GameState.badges, 1, "coal is bit 0")
	is_true(GameState.has_badge("coal"), "has coal")
	is_false(GameState.has_badge("forest"), "does not have forest")
	eq(GameState.badge_count(), 1, "count")

	is_true(GameState.earn_badge("forest"), "second badge")
	eq(GameState.badges, 0b11, "coal + forest")
	eq(GameState.badge_count(), 2, "count")

	is_true(GameState.earn_badge("beacon"), "eighth badge")
	eq(GameState.badges, 0b10000011, "beacon is bit 7")
	eq(GameState.badge_count(), 3, "count")
	eq(Array(GameState.badge_names()), ["coal", "forest", "beacon"], "names in gym order")


func test_earning_a_badge_twice_is_a_no_op() -> void:
	is_true(GameState.earn_badge("coal"), "first")
	is_false(GameState.earn_badge("coal"), "second returns false")
	eq(GameState.badge_count(), 1, "still one badge")


func test_unknown_badge_is_rejected() -> void:
	Log.level = Log.Level.OFF          # an unknown badge logs an error on purpose
	is_false(GameState.earn_badge("sriracha"), "unknown badge not granted")
	eq(GameState.badges, 0, "bitfield untouched")
	is_false(GameState.has_badge("sriracha"), "has_badge false")
	eq(GameState.badge_bit("sriracha"), -1, "no bit index")


func test_badge_earned_signal_fires_once() -> void:
	var seen: Array = []
	EventBus.badge_earned.connect(func(b: StringName) -> void: seen.append(String(b)))
	GameState.earn_badge("Coal")        # case-insensitive input
	GameState.earn_badge("coal")        # duplicate, must not re-emit
	eq(seen, ["coal"], "one normalised emission")


func test_all_eight_badges_fit_in_a_byte() -> void:
	for b in GameState.BADGE_ORDER:
		GameState.earn_badge(b)
	eq(GameState.badges, 255, "all eight bits")
	eq(GameState.badge_count(), 8, "count")


# --- traversal ------------------------------------------------------------

func test_traversal_is_badge_gated() -> void:
	is_false(GameState.can_traverse("smash"), "no smash without coal")
	GameState.earn_badge("coal")
	is_true(GameState.can_traverse("smash"), "smash after coal")
	is_false(GameState.can_traverse("surf"), "no surf without fen")
	GameState.earn_badge("fen")
	is_true(GameState.can_traverse("surf"), "surf after fen")
	# the verb ladder from docs/DATA_CONTRACT.md
	GameState.earn_badge("forest")
	is_true(GameState.can_traverse("cut"), "cut after forest")
	GameState.earn_badge("cobble")
	is_true(GameState.can_traverse("fly"), "fly after cobble")
	GameState.earn_badge("mine")
	is_true(GameState.can_traverse("strength"), "strength after mine")
	GameState.earn_badge("icicle")
	is_true(GameState.can_traverse("climb"), "climb after icicle")
	GameState.earn_badge("beacon")
	is_true(GameState.can_traverse("waterfall"), "waterfall after beacon")


func test_defog_does_not_exist() -> void:
	Log.level = Log.Level.OFF
	for b in GameState.BADGE_ORDER:
		GameState.earn_badge(b)
	is_false(GameState.can_traverse("defog"),
		"fog is removed from the game; there is no defog verb")


func test_use_traversal_emits_only_when_unlocked() -> void:
	var used: Array = []
	EventBus.traversal_used.connect(func(v: StringName) -> void: used.append(String(v)))
	is_false(GameState.use_traversal("cut"), "blocked without forest")
	eq(used.size(), 0, "nothing emitted")
	GameState.earn_badge("forest")
	is_true(GameState.use_traversal("cut"), "allowed with forest")
	eq(used, ["cut"], "emitted once")


# --- level caps -----------------------------------------------------------

func test_starting_cap_is_roarks_ace() -> void:
	eq(GameState.cap_index, 0, "start at row 0")
	eq(GameState.current_level_cap(), 14, "cap 14 before the first gym")


func test_badges_advance_the_cap_ladder() -> void:
	# Each cap row names the event that CLEARS it, so clearing row 1 (roark,
	# raisedBy badge:coal) moves the pointer to row 2 -> cap 22.
	GameState.earn_badge("coal")
	eq(GameState.cap_index, 2, "row 2 after coal")
	eq(GameState.current_level_cap(), 22, "Gardenia's ace")
	GameState.earn_badge("forest")
	eq(GameState.current_level_cap(), 26, "Fantina's ace")
	GameState.earn_badge("relic")
	eq(GameState.current_level_cap(), 32, "Maylene's ace")
	GameState.earn_badge("cobble")
	eq(GameState.current_level_cap(), 37, "Crasher Wake's ace")
	GameState.earn_badge("fen")
	eq(GameState.current_level_cap(), 41, "Byron's ace")
	GameState.earn_badge("mine")
	eq(GameState.current_level_cap(), 44, "Candice's ace")
	GameState.earn_badge("icicle")
	eq(GameState.current_level_cap(), 50, "Volkner's ace")
	GameState.earn_badge("beacon")
	eq(GameState.current_level_cap(), 53, "Aaron's ace, the first Elite Four member")


func test_elite_four_flags_advance_the_cap() -> void:
	GameState.set_cap_index(9)
	eq(GameState.current_level_cap(), 53, "Aaron")
	GameState.set_flag("aaron_defeated")
	eq(GameState.current_level_cap(), 55, "Bertha (Rhyperior 55, not Hippowdon)")
	GameState.set_flag("bertha_defeated")
	eq(GameState.current_level_cap(), 57, "Flint")
	GameState.set_flag("flint_defeated")
	eq(GameState.current_level_cap(), 59, "Lucian")
	GameState.set_flag("lucian_defeated")
	eq(GameState.current_level_cap(), 62, "Cynthia")
	GameState.set_flag("hall_of_fame")
	eq(GameState.current_level_cap(), 100, "post-game is uncapped")


func test_level_cap_raised_signal_carries_old_new_and_index() -> void:
	var events: Array = []
	EventBus.level_cap_raised.connect(func(o: int, n: int, i: int) -> void:
		events.append([o, n, i]))
	GameState.earn_badge("coal")
	eq(events.size(), 1, "one raise")
	eq(events[0], [14, 22, 2], "old, new, row")


func test_the_cap_never_moves_backwards() -> void:
	GameState.earn_badge("coal")
	eq(GameState.cap_index, 2, "row 2")
	is_false(GameState.set_cap_index(0), "setting a lower row is refused")
	eq(GameState.cap_index, 2, "still row 2")
	is_false(GameState.set_cap_index(2), "setting the same row is refused")


func test_hard_exp_stop_at_the_cap() -> void:
	# game-design.md 2.5: at or above the cap, zero exp from every source.
	var mon := {"species": 396, "level": 13, "exp": 0}
	eq(GameState.current_level_cap(), 14, "cap")
	is_true(GameState.can_gain_exp(13), "below the cap")
	eq(GameState.award_exp(mon, 500), 500, "granted below the cap")
	eq(int(mon["exp"]), 500, "exp accumulated")

	mon["level"] = 14
	is_false(GameState.can_gain_exp(14), "at the cap")
	eq(GameState.award_exp(mon, 500), 0, "zero exp at the cap")
	eq(int(mon["exp"]), 500, "exp unchanged")

	mon["level"] = 20
	eq(GameState.award_exp(mon, 500), 0, "zero exp above the cap")


func test_exp_capped_signal_carries_the_pokemon_and_the_cap() -> void:
	var blocked: Array = []
	EventBus.exp_capped.connect(func(p: Dictionary, c: int) -> void: blocked.append([p, c]))
	var mon := {"species": 408, "level": 14, "exp": 0}
	GameState.award_exp(mon, 100)
	eq(blocked.size(), 1, "one exp_capped emission")
	eq(int((blocked[0][0] as Dictionary)["species"]), 408, "the blocked Pokemon")
	eq(blocked[0][1], 14, "the cap that blocked it")
	# and nothing is emitted when exp flows normally
	mon["level"] = 5
	GameState.award_exp(mon, 100)
	eq(blocked.size(), 1, "still one")


# --- money, flags, party --------------------------------------------------

func test_money() -> void:
	eq(GameState.money, 3000, "starting money")
	GameState.add_money(500)
	eq(GameState.money, 3500, "added")
	is_true(GameState.spend_money(3500), "afford")
	eq(GameState.money, 0, "spent")
	is_false(GameState.spend_money(1), "cannot overdraw")
	eq(GameState.money, 0, "unchanged")
	GameState.add_money(-100)
	eq(GameState.money, 0, "clamped at zero")


func test_flags_emit_once_per_change() -> void:
	var seen: Array = []
	EventBus.flag_set.connect(func(f: StringName, v: bool) -> void: seen.append([String(f), v]))
	is_false(GameState.get_flag("met_rival"), "unset flag reads false")
	GameState.set_flag("met_rival")
	is_true(GameState.get_flag("met_rival"), "now true")
	GameState.set_flag("met_rival")           # no change, no emission
	GameState.set_flag("met_rival", false)
	eq(seen, [["met_rival", true], ["met_rival", false]], "two emissions")


func test_party_is_capped_at_six() -> void:
	for i in 6:
		is_true(GameState.add_to_party({"species": i + 1, "level": 5}), "member %d" % i)
	eq(GameState.party_size(), 6, "full party")
	is_false(GameState.add_to_party({"species": 7, "level": 5}), "seventh refused")
	eq(GameState.party_size(), 6, "still six")


func test_playtime_string() -> void:
	GameState.playtime = 3725.4
	eq(GameState.playtime_string(), "1:02:05", "H:MM:SS")


# --- serialisation --------------------------------------------------------

func test_to_dict_from_dict_round_trip() -> void:
	GameState.player_name = "Dawn"
	GameState.earn_badge("coal")
	GameState.earn_badge("forest")
	GameState.money = 12345
	GameState.playtime = 99.5
	GameState.set_flag("met_rival")
	GameState.bag["potion"] = 3
	GameState.current_map = &"eterna_forest"
	GameState.player_cell = Vector2i(14, 9)
	GameState.player_facing = Vector2i.LEFT
	GameState.rng_seed = 987654321
	GameState.add_to_party({"species": 387, "level": 12, "exp": 640, "moves": ["tackle"]})
	var snapshot := GameState.to_dict()

	GameState.reset()
	eq(GameState.badges, 0, "reset cleared badges")

	is_true(GameState.from_dict(snapshot), "restored")
	eq(GameState.player_name, "Dawn", "name")
	eq(GameState.badges, 0b11, "badges")
	eq(GameState.badge_count(), 2, "badge count")
	eq(GameState.money, 12345, "money")
	almost(GameState.playtime, 99.5, 0.0001, "playtime")
	is_true(GameState.get_flag("met_rival"), "flag")
	eq(int(GameState.bag["potion"]), 3, "bag")
	eq(GameState.cap_index, 3, "cap index survived")
	eq(GameState.current_level_cap(), 26, "cap value")
	eq(GameState.current_map, &"eterna_forest", "map")
	eq(GameState.player_cell, Vector2i(14, 9), "cell")
	eq(GameState.player_facing, Vector2i.LEFT, "facing")
	eq(GameState.rng_seed, 987654321, "rng seed")
	eq(GameState.party_size(), 1, "party size")
	eq(int((GameState.party[0] as Dictionary)["species"]), 387, "party species")


func test_from_dict_rejects_a_foreign_version() -> void:
	Log.level = Log.Level.OFF
	var d := GameState.to_dict()
	d["v"] = 99
	is_false(GameState.from_dict(d), "refused")


func test_reset_returns_to_a_new_game() -> void:
	GameState.earn_badge("coal")
	GameState.money = 1
	GameState.add_to_party({"species": 1, "level": 5})
	GameState.reset()
	eq(GameState.badges, 0, "badges")
	eq(GameState.money, 3000, "money")
	eq(GameState.party_size(), 0, "party")
	eq(GameState.cap_index, 0, "cap index")
	eq(GameState.current_level_cap(), 14, "cap")
