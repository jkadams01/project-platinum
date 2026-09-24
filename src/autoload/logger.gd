extends Node
## Levelled logging that works in a headless `--script` run.
##
## AUTOLOAD NAME IS [code]Log[/code], NOT [code]Logger[/code].
## [code]Logger[/code] is a real native class in Godot 4.7.2
## ([code]ClassDB.class_exists("Logger") == true[/code]) and the native global wins
## the name lookup, so an autoload called `Logger` is unreachable by name:
## [codeblock]
## SCRIPT ERROR: Parse Error: Static function "info()" not found in base "GDScriptNativeClass".
## [/codeblock]
## That was verified against this exact binary. Always write [code]Log.info(...)[/code].
##
## Levels are ordered; a message prints when its level is <= the active level.
## ERROR and WARN go to stderr (so a CI log shows them), everything else to stdout.
## [code]push_error()[/code] is deliberately NOT used: it does not affect the exit
## code and it buries the message in an engine stack trace.

enum Level {
	OFF = 0,
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	DEBUG = 4,
	TRACE = 5,
}

const LEVEL_NAMES: Array = ["OFF", "ERROR", "WARN", "INFO", "DEBUG", "TRACE"]
const DEFAULT_LEVEL := Level.INFO

## Active threshold. Set directly or via [method set_level_name].
var level: int = DEFAULT_LEVEL
## When true every emitted line is also appended to an in-memory ring buffer so
## tests can assert on log output without scraping stdout.
var capture: bool = false
## Maximum number of captured lines kept.
var capture_limit: int = 512
## Prefix every line with milliseconds since engine start.
var show_time: bool = true
## Set false to stop writing to stdout/stderr while still counting and (if
## `capture` is on) recording. Tests that exercise the logger itself use this so
## they do not spray their sample messages into the suite output.
var echo: bool = true

var _records: Array[String] = []
var _counts: Array[int] = [0, 0, 0, 0, 0, 0]


func _ready() -> void:
	# `--log-level=debug` after a bare `--` on the command line, or PLAT_LOG_LEVEL.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--log-level="):
			set_level_name(arg.substr("--log-level=".length()))
	var env := OS.get_environment("PLAT_LOG_LEVEL")
	if not env.is_empty():
		set_level_name(env)


func set_level_name(name_or_number: String) -> bool:
	var s := name_or_number.strip_edges().to_upper()
	if s.is_valid_int():
		var n := clampi(int(s), 0, LEVEL_NAMES.size() - 1)
		level = n
		return true
	var idx := LEVEL_NAMES.find(s)
	if idx < 0:
		warn("unknown log level '%s'" % name_or_number, "Log")
		return false
	level = idx
	return true


func level_name() -> String:
	return LEVEL_NAMES[level]


func error(message: String, tag: String = "") -> void:
	_emit(Level.ERROR, message, tag)


func warn(message: String, tag: String = "") -> void:
	_emit(Level.WARN, message, tag)


func info(message: String, tag: String = "") -> void:
	_emit(Level.INFO, message, tag)


func debug(message: String, tag: String = "") -> void:
	_emit(Level.DEBUG, message, tag)


func trace(message: String, tag: String = "") -> void:
	_emit(Level.TRACE, message, tag)


## Number of messages emitted at [param lvl] since boot (counted even when the
## level threshold suppressed the output, so tests can assert "nothing errored").
func count(lvl: int) -> int:
	return _counts[lvl]


func records() -> PackedStringArray:
	return PackedStringArray(_records)


func clear_records() -> void:
	_records.clear()


func reset_counts() -> void:
	_counts = [0, 0, 0, 0, 0, 0]


func _emit(lvl: int, message: String, tag: String) -> void:
	_counts[lvl] += 1
	if lvl > level:
		return
	var line := ""
	if show_time:
		line += "[%7.3f] " % (Time.get_ticks_msec() / 1000.0)
	line += "%-5s " % LEVEL_NAMES[lvl]
	if not tag.is_empty():
		line += "[%s] " % tag
	line += message
	if capture:
		_records.append(line)
		while _records.size() > capture_limit:
			_records.remove_at(0)
	if not echo:
		return
	if lvl <= Level.WARN:
		printerr(line)
	else:
		print(line)
