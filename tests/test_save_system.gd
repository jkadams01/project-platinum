extends "res://tests/framework/test_case.gd"
## SaveSystem: JSON round-trip to user://, and refusing malformed input.
## Uses high slot numbers so a developer's real saves are never touched.

const SLOT := 7
const SLOT_B := 8

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR
	DataRegistry.boot(DataRegistry.FIXTURE_DIR)
	EventBus.disconnect_all()
	GameState.track_playtime = false
	GameState.reset()
	SaveSystem.delete_slot(SLOT)
	SaveSystem.delete_slot(SLOT_B)


func after_each() -> void:
	SaveSystem.delete_slot(SLOT)
	SaveSystem.delete_slot(SLOT_B)
	EventBus.disconnect_all()
	GameState.track_playtime = true
	Log.level = _saved_level


func _populate() -> void:
	GameState.player_name = "Dawn"
	GameState.earn_badge("coal")
	GameState.earn_badge("forest")
	GameState.money = 4242
	GameState.playtime = 1234.5
	GameState.set_flag("met_rival")
	GameState.bag["potion"] = 5
	GameState.current_map = &"eterna_forest"
	GameState.player_cell = Vector2i(14, 9)
	GameState.player_facing = Vector2i.LEFT
	GameState.rng_seed = 42
	GameState.set_starter_choice("piplup")
	GameState.add_to_party({
		"species": 387, "level": 12, "exp": 640, "hp": 33, "maxHp": 38,
		"moves": ["tackle", "withdraw"], "ivs": [31, 20, 5, 14, 9, 2],
		"evs": [0, 4, 0, 0, 0, 0], "nickname": "Sprout",
	})


# --------------------------------------------------------------------------

func test_round_trip_preserves_every_field() -> void:
	_populate()
	is_true(SaveSystem.save_slot(SLOT), "save succeeded")
	is_true(SaveSystem.has_save(SLOT), "file exists")

	GameState.reset()
	eq(GameState.money, 3000, "state really was wiped")

	is_true(SaveSystem.load_slot(SLOT), "load succeeded")
	eq(GameState.player_name, "Dawn", "player name")
	eq(GameState.badges, 0b11, "badge bitfield")
	eq(GameState.badge_count(), 2, "badge count")
	eq(GameState.money, 4242, "money")
	almost(GameState.playtime, 1234.5, 0.001, "playtime")
	is_true(GameState.get_flag("met_rival"), "flag")
	eq(int(GameState.bag["potion"]), 5, "bag")
	eq(GameState.cap_index, 3, "cap index")
	eq(GameState.current_level_cap(), 26, "level cap after two badges")
	eq(GameState.current_map, &"eterna_forest", "map")
	eq(GameState.player_cell, Vector2i(14, 9), "player cell")
	eq(GameState.player_facing, Vector2i.LEFT, "facing")
	eq(GameState.rng_seed, 42, "rng seed")
	# Barry's starter is derived from this in all seven of his fights, so a choice
	# lost on load would silently re-roll his party mid-playthrough.
	eq(GameState.starter_choice, "piplup", "starter choice")

	eq(GameState.party_size(), 1, "party size")
	var mon: Dictionary = GameState.party[0]
	eq(int(mon["species"]), 387, "species")
	eq(int(mon["level"]), 12, "level")
	eq(int(mon["exp"]), 640, "exp")
	eq(String(mon["nickname"]), "Sprout", "nickname")
	eq(Array(mon["moves"]), ["tackle", "withdraw"], "moves")
	eq(Array(mon["ivs"]), [31, 20, 5, 14, 9, 2], "ivs")


func test_loaded_numbers_are_ints_not_floats() -> void:
	# This is the whole reason GameState.from_dict() re-casts: JSON has no int
	# type, so without the cast `party[0]["level"]` comes back as 12.0 and every
	# `level == 12` comparison downstream becomes a coin flip.
	_populate()
	is_true(SaveSystem.save_slot(SLOT), "saved")
	GameState.reset()
	is_true(SaveSystem.load_slot(SLOT), "loaded")
	var mon: Dictionary = GameState.party[0]
	is_int(mon["species"], "species")
	is_int(mon["level"], "level")
	is_int(mon["exp"], "exp")
	is_int(mon["hp"], "hp")
	is_int(mon["maxHp"], "maxHp")
	is_int((mon["ivs"] as Array)[0], "iv")
	is_int((mon["evs"] as Array)[1], "ev")
	is_int(GameState.money, "money")
	is_int(GameState.badges, "badges")
	is_int(GameState.cap_index, "cap index")
	is_int(GameState.rng_seed, "rng seed")
	is_int(GameState.player_cell.x, "player cell x")


func test_the_file_on_disk_is_readable_json_with_an_envelope() -> void:
	_populate()
	is_true(SaveSystem.save_slot(SLOT), "saved")
	var text := FileAccess.get_file_as_string(SaveSystem.slot_path(SLOT))
	check(not text.is_empty(), "file has content")
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "parses as a JSON object")
	var payload: Dictionary = parsed
	eq(String(payload["magic"]), "PLAT", "magic")
	eq(int(payload["version"]), 1, "version")
	has_key(payload, "state", "state present")
	has_key(payload, "summary", "summary present")
	# no temp file left behind
	is_false(FileAccess.file_exists(SaveSystem.slot_path(SLOT) + SaveSystem.TMP_SUFFIX),
		"temp file was renamed away")


func test_slot_summary_reads_a_header_without_touching_game_state() -> void:
	_populate()
	SaveSystem.save_slot(SLOT)
	GameState.reset()
	var s := SaveSystem.slot_summary(SLOT)
	is_true(bool(s["exists"]), "exists")
	eq(String(s["playerName"]), "Dawn", "player name in the header")
	eq(int(s["badges"]), 2, "badge count in the header")
	eq(int(s["levelCap"]), 26, "level cap in the header")
	eq(GameState.player_name, "Lucas", "GameState was NOT modified")
	eq(GameState.badges, 0, "GameState badges untouched")


func test_empty_slot() -> void:
	is_false(SaveSystem.has_save(SLOT), "no file")
	is_false(SaveSystem.load_slot(SLOT), "load returns false")
	eq(SaveSystem.read_slot(SLOT), {}, "read returns an empty dict")
	eq(SaveSystem.slot_summary(SLOT), {"exists": false}, "summary says empty")
	is_false(SaveSystem.delete_slot(SLOT), "deleting nothing returns false")


func test_slots_are_independent() -> void:
	GameState.money = 111
	SaveSystem.save_slot(SLOT)
	GameState.money = 222
	SaveSystem.save_slot(SLOT_B)
	is_true(SaveSystem.load_slot(SLOT), "load slot A")
	eq(GameState.money, 111, "slot A money")
	is_true(SaveSystem.load_slot(SLOT_B), "load slot B")
	eq(GameState.money, 222, "slot B money")


func test_corrupt_and_hostile_files_are_refused() -> void:
	Log.level = Log.Level.OFF          # these paths log errors on purpose
	var path := SaveSystem.slot_path(SLOT)

	# 1. not JSON at all
	_write(path, "this is not json {{{")
	is_false(SaveSystem.load_slot(SLOT), "garbage refused")

	# 2. valid JSON, wrong shape
	_write(path, "[1, 2, 3]")
	is_false(SaveSystem.load_slot(SLOT), "JSON array refused")

	# 3. right shape, wrong magic -- someone else's save file
	_write(path, JSON.stringify({"magic": "XXXX", "version": 1, "state": {"v": 1}}))
	is_false(SaveSystem.load_slot(SLOT), "bad magic refused")

	# 4. right magic, future version
	_write(path, JSON.stringify({"magic": "PLAT", "version": 99, "state": {"v": 1}}))
	is_false(SaveSystem.load_slot(SLOT), "future version refused")

	# 5. right envelope, no state
	_write(path, JSON.stringify({"magic": "PLAT", "version": 1}))
	is_false(SaveSystem.load_slot(SLOT), "missing state refused")

	# 6. zero bytes
	_write(path, "")
	is_false(SaveSystem.load_slot(SLOT), "empty file refused")

	# and GameState is still a pristine new game after all of that
	eq(GameState.badges, 0, "GameState untouched by every rejection")
	eq(GameState.money, 3000, "money untouched")
	eq(GameState.party_size(), 0, "party untouched")


func test_a_failed_load_does_not_half_apply() -> void:
	Log.level = Log.Level.OFF
	_populate()
	SaveSystem.save_slot(SLOT)
	# a save whose state object is a version this build does not read
	_write(SaveSystem.slot_path(SLOT_B),
		JSON.stringify({"magic": "PLAT", "version": 1, "state": {"v": 99, "money": 1}}))
	is_false(SaveSystem.load_slot(SLOT_B), "refused")
	eq(GameState.money, 4242, "in-memory state is exactly as it was")
	eq(GameState.party_size(), 1, "party intact")


func test_save_and_load_signals() -> void:
	var saved: Array = []
	var loaded: Array = []
	EventBus.game_saved.connect(func(s: int, ok: bool) -> void: saved.append([s, ok]))
	EventBus.game_loaded.connect(func(s: int, ok: bool) -> void: loaded.append([s, ok]))
	SaveSystem.save_slot(SLOT)
	eq(saved, [[SLOT, true]], "game_saved fired")
	SaveSystem.load_slot(SLOT)
	eq(loaded, [[SLOT, true]], "game_loaded fired")
	Log.level = Log.Level.OFF
	SaveSystem.load_slot(SLOT_B)
	eq(loaded.size(), 2, "a failed load still reports")
	eq(loaded[1], [SLOT_B, false], "with ok = false")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		fail("could not open %s for writing" % path)
		return
	f.store_string(text)
	f.close()
