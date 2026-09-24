extends "res://tests/framework/test_case.gd"
## PER-SEGMENT EXP MULTIPLIERS -- docs/DATA_CONTRACT.md 8.
##
## The contract in three sentences:
##   1. Every row of `data/level_caps.json` carries its own `expMultiplier`, and
##      `GameState.current_exp_multiplier()` returns the ACTIVE row's.
##   2. `src/battle/exp.gd` applies it to every award BEFORE the level-cap check.
##   3. The top-level `expMultiplier` is permanently null and NOTHING reads it.
##      An earlier build ran a flat 2.5 from there; these tests exist so it cannot
##      come back unnoticed.
##
## Every number below is asserted, not sampled: the 15 designed multipliers, the
## exact EXP a Pokemon receives in the Roark and Cynthia segments, and 0 at the cap.

const Deps := preload("res://src/battle/deps.gd")
const Exp := preload("res://src/battle/exp.gd")

## The designed ladder, docs/research/level-curve.md, index 0..14.
const CHECKPOINTS: Array = [
	"start", "roark", "gardenia", "fantina", "maylene", "crasher_wake", "byron",
	"candice", "volkner", "aaron", "bertha", "flint", "lucian", "cynthia", "post-game",
]
const MULTIPLIERS: Array = [
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.35, 2.95, 1.8, 1.3, 2.05, 2.55, 3.3, 3.4, 1.0,
]
const CAPS: Array = [18, 18, 27, 36, 45, 54, 66, 78, 90, 96, 97, 98, 99, 100, 100]

const ROARK := 1
const CYNTHIA := 13

const POISON_DIR := "user://test_expseg_poison"

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.OFF
	Deps.clear_overrides()
	# The real committed table -- this suite is the cross-stream integration check
	# between data/level_caps.json and the engine.
	DataRegistry.boot(DataRegistry.DATA_DIR)
	EventBus.disconnect_all()
	GameState.track_playtime = false
	GameState.reset()


func after_each() -> void:
	EventBus.disconnect_all()
	GameState.reset()
	GameState.track_playtime = true
	DataRegistry.allow_fixture_fallback = true
	DataRegistry.boot(DataRegistry.DATA_DIR)      # leave production state behind
	Log.level = _saved_level


## True when data/level_caps.json is the table actually loaded.
func _real_data() -> bool:
	return DataRegistry.source_of("level_caps") == "data"


# --------------------------------------------------------------------------
# 1. the data: 15 rows, each with its own multiplier
# --------------------------------------------------------------------------

func test_every_cap_row_carries_its_own_multiplier() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated (source=%s)"
			% DataRegistry.source_of("level_caps"))
		return
	eq(DataRegistry.level_cap_count(), 15, "15 cap rows")
	eq(DataRegistry.exp_multiplier_mode(), "per-segment", "expMultiplierMode")
	for i in MULTIPLIERS.size():
		var row := DataRegistry.get_level_cap_entry(i)
		eq(String(row.get("checkpoint", "")), CHECKPOINTS[i], "row %d checkpoint" % i)
		eq(int(row.get("cap", 0)), CAPS[i], "row %d cap" % i)
		almost(DataRegistry.get_exp_multiplier(i), MULTIPLIERS[i], 0.0001,
			"row %d (%s) expMultiplier" % [i, CHECKPOINTS[i]])


func test_the_top_level_expmultiplier_is_null_on_disk() -> void:
	# It is null in the file and it must stay null: the per-segment mode is what
	# the engine implements.
	var text := FileAccess.get_file_as_string("res://data/level_caps.json")
	if text.is_empty():
		pending("data/level_caps.json absent")
		return
	var doc: Variant = JSON.parse_string(text)
	is_true(doc is Dictionary, "level_caps.json parses to an object")
	if not (doc is Dictionary):
		return
	var d: Dictionary = doc
	is_true(d.has("expMultiplier"), "the key is present")
	eq(d.get("expMultiplier"), null, "top-level expMultiplier is null")
	eq(String(d.get("expMultiplierMode", "")), "per-segment", "expMultiplierMode")
	for row: Variant in (d.get("caps", []) as Array):
		var r: Dictionary = row
		is_true(r.has("expMultiplier"),
			"row %s carries its own expMultiplier" % r.get("checkpoint"))


func test_a_top_level_multiplier_is_ignored_not_obeyed() -> void:
	# THE REGRESSION GUARD. Hand the registry a table with a fat global
	# expMultiplier and per-row 1.0s. If anything still reads the global, the
	# multiplier comes back 2.5 and this fails.
	DirAccess.make_dir_recursive_absolute(POISON_DIR)
	var rows: Array = []
	for i in 15:
		rows.append({"index": i, "checkpoint": CHECKPOINTS[i], "cap": CAPS[i],
			"raisedBy": null, "expMultiplier": 7.0 if i == ROARK else 1.0})
	var f := FileAccess.open(POISON_DIR.path_join("level_caps.json"), FileAccess.WRITE)
	is_true(f != null, "poison table written")
	if f == null:
		return
	f.store_string(JSON.stringify({
		"caps": rows, "postGameCap": 100, "rule": "hard-xp-stop",
		"expMultiplier": 2.5, "expMultiplierMode": "per-segment",
	}))
	f.close()

	# Capture only records lines the level lets through, so raise it to ERROR and
	# silence the console instead of letting the guard shout into the test output.
	Log.level = Log.Level.ERROR
	Log.echo = false
	Log.capture = true
	Log.clear_records()
	DataRegistry.boot(POISON_DIR)
	Log.capture = false
	Log.echo = true
	Log.level = Log.Level.OFF

	almost(DataRegistry.get_exp_multiplier(0), 1.0, 0.0001,
		"row 0 uses its own 1.0, NOT the global 2.5")
	almost(DataRegistry.get_exp_multiplier(ROARK), 7.0, 0.0001,
		"row 1 uses its own 7.0, NOT the global 2.5")
	GameState.set_cap_index(ROARK)
	almost(GameState.current_exp_multiplier(), 7.0, 0.0001,
		"GameState reads the row, not the global")

	var shouted := false
	var lines := Log.records()
	for line: String in lines:
		if line.contains("top-level expMultiplier"):
			shouted = true
	is_true(shouted, "the loader logged an error about the global field: %s" % [lines])
	Log.clear_records()

	DirAccess.remove_absolute(POISON_DIR.path_join("level_caps.json"))
	DirAccess.remove_absolute(POISON_DIR)


# --------------------------------------------------------------------------
# 2. GameState.current_exp_multiplier() -- the active segment
# --------------------------------------------------------------------------

func test_current_exp_multiplier_tracks_the_active_segment() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated")
		return
	for i in MULTIPLIERS.size():
		GameState.cap_index = i            # direct: set_cap_index refuses to go back
		almost(GameState.current_exp_multiplier(), MULTIPLIERS[i], 0.0001,
			"cap_index %d (%s)" % [i, CHECKPOINTS[i]])
	# Deps is what the battle stream actually calls, and it must agree.
	GameState.cap_index = CYNTHIA
	almost(Deps.exp_multiplier(), 3.4, 0.0001, "Deps.exp_multiplier() in cynthia")


func test_advancing_the_checkpoint_changes_the_multiplier() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated")
		return
	eq(GameState.cap_index, 0, "a fresh game starts at row 0")
	almost(GameState.current_exp_multiplier(), 1.0, 0.0001, "start segment x1.0")

	# badge:mine clears row 6 (byron), so the pointer lands on row 7 (candice).
	is_true(GameState.earn_badge("mine"), "Mine Badge earned")
	eq(GameState.cap_index, 7, "row 7 after the Mine Badge")
	almost(GameState.current_exp_multiplier(), 2.95, 0.0001,
		"candice segment x2.95 -- the multiplier MOVED")

	# badge:icicle clears row 7, landing on row 8 (volkner).
	is_true(GameState.earn_badge("icicle"), "Icicle Badge earned")
	eq(GameState.cap_index, 8, "row 8 after the Icicle Badge")
	almost(GameState.current_exp_multiplier(), 1.8, 0.0001,
		"volkner segment x1.8 -- and moved again, downwards")

	# flag:lucian_defeated clears row 12, landing on row 13 (cynthia).
	GameState.set_flag("lucian_defeated")
	eq(GameState.cap_index, 13, "row 13 after Lucian")
	almost(GameState.current_exp_multiplier(), 3.4, 0.0001, "cynthia segment x3.4")

	# Post-game drops back to vanilla rates: nothing is left to reach.
	GameState.set_flag("hall_of_fame")
	eq(GameState.cap_index, 14, "row 14 after the Hall of Fame")
	almost(GameState.current_exp_multiplier(), 1.0, 0.0001, "post-game x1.0")


# --------------------------------------------------------------------------
# 3. exp.gd applies it -- real numbers
# --------------------------------------------------------------------------

## Level `lvl`, medium-fast, parked exactly on its level threshold.
func _mon(lvl: int) -> Dictionary:
	return {"species": 393, "nickname": "PIPLUP", "level": lvl,
		"exp": Exp.exp_for_level("medium-fast", lvl), "growthRate": "medium-fast",
		"hp": 30, "maxHp": 30}


func test_roark_segment_awards_exp_unchanged() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated")
		return
	GameState.cap_index = ROARK
	eq(GameState.current_level_cap(), 18, "the Roark segment caps at 18")
	almost(GameState.current_exp_multiplier(), 1.0, 0.0001, "x1.0")

	var mon := _mon(10)
	var before := int(mon["exp"])
	var res := Exp.award(mon, 100, {"learn_moves": false})   # no cap/mult in opts
	eq(int(res["rawAmount"]), 100, "raw amount")
	almost(float(res["expMultiplier"]), 1.0, 0.0001, "multiplier used")
	eq(int(res["granted"]), 100, "100 raw -> 100 granted (x1.0, unchanged)")
	eq(int(mon["exp"]) - before, 100, "exactly 100 landed on the EXP bar")
	eq(int(res["cap"]), 18, "the live cap came from GameState")
	is_false(bool(res["capped"]), "not capped at level 10")


func test_cynthia_segment_awards_exp_times_3_point_4() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated")
		return
	GameState.cap_index = CYNTHIA
	eq(GameState.current_level_cap(), 100, "the Cynthia segment caps at 100")
	almost(GameState.current_exp_multiplier(), 3.4, 0.0001, "x3.4")

	var mon := _mon(50)
	var before := int(mon["exp"])
	var res := Exp.award(mon, 100, {"learn_moves": false})
	eq(int(res["rawAmount"]), 100, "raw amount")
	almost(float(res["expMultiplier"]), 3.4, 0.0001, "multiplier used")
	eq(int(res["granted"]), 340, "100 raw x3.4 -> 340 granted")
	eq(int(mon["exp"]) - before, 340, "340 landed on the EXP bar")

	# floor(), not round(): 1000 x 3.4 is exact, so use a value that is not.
	var mon2 := _mon(50)
	var res2 := Exp.award(mon2, 7, {"learn_moves": false})
	eq(int(res2["granted"]), 23, "7 x 3.4 = 23.8 -> floor 23")

	# And the same award in the Roark segment is 100/7 -- the difference IS the
	# per-segment multiplier and nothing else.
	GameState.cap_index = ROARK
	var mon3 := _mon(10)
	eq(int(Exp.award(mon3, 100, {"learn_moves": false})["granted"]), 100,
		"the identical award is 100 one segment earlier")


func test_the_cap_beats_the_multiplier_at_every_size() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated")
		return
	# A Pokemon AT the cap gains exactly 0 -- the multiplier is applied first and
	# then thrown away, in the fattest segment in the game.
	GameState.cap_index = CYNTHIA
	almost(GameState.current_exp_multiplier(), 3.4, 0.0001, "x3.4 in force")

	var capped: Array = []
	EventBus.exp_capped.connect(func(p: Dictionary, c: int) -> void: capped.append(c))

	var at_cap := _mon(100)
	var before := int(at_cap["exp"])
	var res := Exp.award(at_cap, 1000, {"learn_moves": false})
	eq(int(res["granted"]), 0, "AT the cap: exactly 0 granted despite x3.4")
	is_true(bool(res["capped"]), "reported as capped")
	eq(int(res["cap"]), 100, "cap 100")
	eq(int(at_cap["exp"]), before, "the EXP field did not move")
	eq(int(at_cap["level"]), 100, "the level did not move")
	eq((res["messages"] as Array)[0], "PIPLUP is at the level cap!", "cap message")
	eq(capped.size(), 1, "EventBus.exp_capped fired once")

	# Same at a mid-game cap, and with an absurd explicit multiplier: still 0.
	GameState.cap_index = 7                                   # candice, cap 78
	var at_78 := _mon(78)
	eq(int(Exp.award(at_78, 9999, {"learn_moves": false})["granted"]), 0,
		"at the cap 78: 0 under x2.95")
	eq(int(Exp.award(at_78, 9999, {"exp_multiplier": 1000.0, "learn_moves": false})["granted"]),
		0, "x1000 does not buy a single point past the cap")
	eq(int(at_78["exp"]), Exp.exp_for_level("medium-fast", 78), "EXP untouched")

	# Above the cap too (a traded Pokemon over the line).
	var over := _mon(90)
	eq(int(Exp.award(over, 9999, {"learn_moves": false})["granted"]), 0,
		"above the cap: also 0")
	eq(capped.size(), 4, "exp_capped fired for every refusal")


func test_the_multiplier_cannot_vault_a_pokemon_past_the_cap() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated")
		return
	# x3.4 on a big award is exactly the case where a naive implementation would
	# overshoot: the level still stops dead on the cap and nothing is banked.
	GameState.cap_index = 7                                   # candice, cap 78
	almost(GameState.current_exp_multiplier(), 2.95, 0.0001, "x2.95")
	var mon := _mon(70)
	var res := Exp.award(mon, 500000, {"learn_moves": false})
	eq(int(res["granted"]), 1475000, "500000 x2.95 = 1475000 granted")
	eq(int(mon["level"]), 78, "levelled to the cap, not past it")
	eq(int(mon["exp"]), Exp.exp_for_level("medium-fast", 78),
		"parked exactly on the cap threshold, nothing banked")
	eq(int(Exp.award(mon, 5000, {"learn_moves": false})["granted"]), 0,
		"now AT the cap: zero")


func test_award_for_defeat_multiplies_the_yield_exactly_once() -> void:
	if not _real_data():
		pending("data/level_caps.json not generated")
		return
	# gain_from_defeat() is unscaled; award() is where the multiplier lands. Both
	# winners are level 20 so the raw yield is the same 257 on either side and the
	# only difference left is the segment.
	var defeated := {"baseExp": 64, "level": 20}
	eq(Exp.gain_from_defeat(defeated, 20, {}), 257,
		"the unscaled Gen 5 yield (b=64, L=Lp=20)")

	GameState.cap_index = 2                              # gardenia, cap 27, x1.0
	almost(GameState.current_exp_multiplier(), 1.0, 0.0001, "gardenia x1.0")
	var early := _mon(20)
	var r1 := Exp.award_for_defeat(early, defeated, {"learn_moves": false})
	eq(int(r1["rawAmount"]), 257, "the yield reached award() unscaled")
	eq(int(r1["granted"]), 257, "gardenia segment: 257 granted, unscaled")

	GameState.cap_index = CYNTHIA                        # cap 100, x3.4
	var late := _mon(20)
	var r2 := Exp.award_for_defeat(late, defeated, {"learn_moves": false})
	eq(int(r2["rawAmount"]), 257, "same raw yield, same winner level")
	# 257 x 3.4 = 873.8 -> 873. Multiplied ONCE, in award(), not twice
	# (257 x 3.4 x 3.4 would be 2971).
	eq(int(r2["granted"]), 873, "cynthia segment: 257 x3.4 floored to 873")
	eq(int(late["exp"]) - int(early["exp"]), 873 - 257,
		"the whole difference between the two segments is the multiplier")


# --------------------------------------------------------------------------
# 4. degradation -- a missing multiplier must never zero the EXP economy
# --------------------------------------------------------------------------

func test_a_row_without_a_multiplier_falls_back_to_1_point_0() -> void:
	# The built-in FALLBACK_CAPS ladder predates the field. Booting with nothing
	# on disk must still yield a usable 1.0, not 0.0.
	DataRegistry.allow_fixture_fallback = false
	DataRegistry.boot("res://tests/fixtures/definitely_not_here")
	eq(DataRegistry.source_of("level_caps"), "builtin", "built-in ladder in use")
	for i in DataRegistry.level_cap_count():
		almost(DataRegistry.get_exp_multiplier(i), 1.0, 0.0001,
			"built-in row %d degrades to 1.0" % i)
	almost(DataRegistry.get_exp_multiplier(-5), 1.0, 0.0001, "negative index clamps")
	almost(DataRegistry.get_exp_multiplier(999), 1.0, 0.0001, "past the end clamps")
	DataRegistry.allow_fixture_fallback = true


func test_exp_multiplier_degrades_without_the_autoloads() -> void:
	# deps.gd must answer even when GameState is unreachable (the battle stream
	# runs headless in tests and must not hard-depend on the autoload).
	# Overrides that answer neither current_exp_multiplier() nor
	# get_exp_multiplier(): both branches miss and the constant has to hold.
	Deps.set_override("GameState", RefCounted.new())
	Deps.set_override("DataRegistry", RefCounted.new())
	almost(Deps.exp_multiplier(), 1.0, 0.0001, "falls back to 1.0, never 0.0")
	almost(Deps.DEFAULT_EXP_MULTIPLIER, 1.0, 0.0001, "the constant itself")
	Deps.clear_overrides()

	# With only GameState missing, the registry's row 0 answers.
	Deps.set_override("GameState", RefCounted.new())
	DataRegistry.boot(DataRegistry.DATA_DIR)
	almost(Deps.exp_multiplier(), DataRegistry.get_exp_multiplier(0), 0.0001,
		"no GameState -> row 0 of the cap table")
	Deps.clear_overrides()
