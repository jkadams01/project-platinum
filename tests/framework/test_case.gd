extends RefCounted
## Base class for every `tests/test_*.gd`.
##
## Deliberately has no `class_name`. Global class names live in
## `.godot/global_script_class_cache.cfg`, which only an editor or `--import`
## pass writes, so a `class_name` base would make `--script res://tests/run_tests.gd`
## fail outright in a fresh checkout with
## `Parse Error: Could not find type "TestCase" in the current scope`.
## Test files extend the path instead:
##   extends "res://tests/framework/test_case.gd"
##
## Subclasses define `test_*` methods. They may be coroutines; the runner awaits
## every call, and `await` on a non-coroutine return value passes straight through.

var tree: SceneTree          ## injected by the runner; use tree.root, await tree.process_frame
var _fails: Array[String] = []
var _pendings: Array[String] = []
var _checks: int = 0


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- assertions -----------------------------------------------------------

func check(condition: bool, message: String) -> bool:
	_checks += 1
	if not condition:
		_fails.append(message)
	return condition


func eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	return check(actual == expected, "%s expected %s, got %s" % [message, expected, actual])


func neq(actual: Variant, unexpected: Variant, message: String = "") -> bool:
	return check(actual != unexpected, "%s expected anything but %s" % [message, unexpected])


func almost(actual: float, expected: float, eps: float = 0.0001, message: String = "") -> bool:
	return check(absf(actual - expected) <= eps,
		"%s expected ~%f (+/-%f), got %f" % [message, expected, eps, actual])


func is_true(value: bool, message: String = "") -> bool:
	return check(value, "%s expected true" % message)


func is_false(value: bool, message: String = "") -> bool:
	return check(not value, "%s expected false" % message)


## Asserts the value is an int, not a float. JSON round-trips silently turn every
## number into TYPE_FLOAT, so this is the guard that catches it.
func is_int(value: Variant, message: String = "") -> bool:
	return check(typeof(value) == TYPE_INT,
		"%s expected TYPE_INT(2), got type %d (%s)" % [message, typeof(value), value])


func has_key(d: Dictionary, key: Variant, message: String = "") -> bool:
	return check(d.has(key), "%s expected key '%s' in %s" % [message, key, d.keys()])


func fail(message: String) -> void:
	_checks += 1
	_fails.append(message)


## Records something that could not be verified yet because a dependency is not
## built (typically `data/*.json`, which another stream generates). Pendings are
## reported separately and do NOT fail the run -- unless `--require-data` is
## passed, which is how CI enforces them once the dependency lands.
func pending(message: String) -> void:
	_pendings.append(message)


# --- runner interface -----------------------------------------------------

func fails() -> Array[String]:
	return _fails


func pendings() -> Array[String]:
	return _pendings


func checks() -> int:
	return _checks


func reset() -> void:
	_fails.clear()
	_pendings.clear()
	_checks = 0
