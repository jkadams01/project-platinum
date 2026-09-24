extends "res://tests/framework/test_case.gd"
## Log (the autoload is named Log, not Logger -- see src/autoload/logger.gd).

var _saved_level: int = 0
var _saved_capture: bool = false
var _saved_echo: bool = true


func before_each() -> void:
	_saved_level = Log.level
	_saved_capture = Log.capture
	Log.clear_records()
	Log.reset_counts()
	Log.capture = true
	Log.show_time = false
	_saved_echo = Log.echo
	Log.echo = false        # record, but do not spray samples into the suite output


func after_each() -> void:
	Log.echo = _saved_echo
	Log.capture = _saved_capture
	Log.level = _saved_level
	Log.show_time = true
	Log.clear_records()


func test_the_autoload_exists_under_the_name_Log() -> void:
	# `Logger` is a native Godot class, so an autoload of that name is shadowed by
	# it and `Logger.info(...)` will not even parse. This check exists so a rename
	# back to `Logger` fails loudly here rather than in six other files.
	var node := tree.root.get_node_or_null("Log")
	check(node != null, "autoload node /root/Log exists")
	check(node == Log, "the global name Log resolves to that node")
	is_true(ClassDB.class_exists("Logger"),
		"Logger is still a native class -- do not rename the autoload back")


func test_levels_filter_output() -> void:
	Log.level = Log.Level.WARN
	Log.error("e")
	Log.warn("w")
	Log.info("i")
	Log.debug("d")
	Log.trace("t")
	var r := Log.records()
	eq(r.size(), 2, "only error and warn were emitted")
	is_true(r[0].contains("ERROR"), "error line")
	is_true(r[1].contains("WARN"), "warn line")


func test_off_silences_everything() -> void:
	Log.level = Log.Level.OFF
	Log.error("e")
	Log.info("i")
	eq(Log.records().size(), 0, "nothing emitted")


func test_trace_emits_everything() -> void:
	Log.level = Log.Level.TRACE
	Log.error("e")
	Log.warn("w")
	Log.info("i")
	Log.debug("d")
	Log.trace("t")
	eq(Log.records().size(), 5, "all five levels")


func test_counts_are_kept_even_when_suppressed() -> void:
	Log.level = Log.Level.OFF
	Log.error("boom")
	Log.error("boom again")
	Log.warn("hmm")
	eq(Log.count(Log.Level.ERROR), 2, "errors counted while silenced")
	eq(Log.count(Log.Level.WARN), 1, "warnings counted")
	eq(Log.records().size(), 0, "but nothing printed")


func test_tags_and_formatting() -> void:
	Log.level = Log.Level.INFO
	Log.info("loaded 1025 species", "DataRegistry")
	var line := Log.records()[0]
	is_true(line.contains("[DataRegistry]"), "tag present: %s" % line)
	is_true(line.contains("loaded 1025 species"), "message present")
	is_true(line.contains("INFO"), "level present")


func test_set_level_by_name() -> void:
	is_true(Log.set_level_name("debug"), "by lowercase name")
	eq(Log.level, Log.Level.DEBUG, "debug")
	is_true(Log.set_level_name("WARN"), "by uppercase name")
	eq(Log.level, Log.Level.WARN, "warn")
	is_true(Log.set_level_name("5"), "by number")
	eq(Log.level, Log.Level.TRACE, "trace")
	eq(Log.level_name(), "TRACE", "level_name")
	Log.level = Log.Level.OFF
	is_false(Log.set_level_name("banana"), "unknown name rejected")


func test_capture_buffer_is_bounded() -> void:
	Log.level = Log.Level.INFO
	Log.capture_limit = 10
	for i in 50:
		Log.info("line %d" % i)
	eq(Log.records().size(), 10, "ring buffer capped")
	is_true(Log.records()[9].contains("line 49"), "keeps the most recent")
	Log.capture_limit = 512
