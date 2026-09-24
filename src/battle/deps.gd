extends RefCounted
## Runtime access to the engine:core autoloads, with a working fallback.
##
## WHY THIS FILE EXISTS
##
## The battle stream is written against the documented autoload API
## (`DataRegistry`, `EventBus`, `GameState`) but must not *fail to parse* when an
## autoload is missing or failed to instantiate. On this engine a GDScript that
## names a missing autoload is a **compile error**, not a runtime one, so a single
## broken autoload would take the whole battle engine — and the test suite — down
## with it. Verified on 4.7.2: `--script` against a project whose autoload script
## fails to parse prints `Compile Error: Identifier not found: DataRegistry`.
##
## So every reference goes through here, by node name, at runtime:
##   * [method registry] returns the real `DataRegistry` when it is alive, and a
##     self-contained JSON reader over the committed `data/*.json` otherwise.
##     Both expose the same accessors, so callers never branch.
##   * [method bus] / [method state] return the autoload or `null`; [method emit]
##     and [method level_cap] degrade safely.
##   * [method set_override] lets a test inject a fake for any of the three.
##
## Nothing here is ROM-derived: species/move/type data comes from veekun via
## `data/*.json`, which is committed (docs/DATA_CONTRACT.md).

const DATA_DIR := "res://data"
const FIXTURE_DIR := "res://tests/fixtures"

## Used only when neither GameState nor a cap table can be reached. Row 0 of
## docs/DATA_CONTRACT.md 8.
const DEFAULT_CAP := 14

## Used only when neither GameState nor a cap table can be reached. 1.0 = vanilla
## EXP rates, which under-supplies rather than over-levels.
const DEFAULT_EXP_MULTIPLIER := 1.0

static var _overrides: Dictionary = {}
static var _fallback_registry: RefCounted = null


# --------------------------------------------------------------------------
# Injection points (tests)
# --------------------------------------------------------------------------

## Force [method registry] / [method bus] / [method state] to return [param obj].
## `name` is "DataRegistry", "EventBus" or "GameState". Pass null to drop it.
static func set_override(node_name: String, obj: Object) -> void:
	if obj == null:
		_overrides.erase(node_name)
	else:
		_overrides[node_name] = obj


static func clear_overrides() -> void:
	_overrides.clear()


# --------------------------------------------------------------------------
# Resolution
# --------------------------------------------------------------------------

## The autoload node of that name, an injected override, or null.
static func node(node_name: String) -> Object:
	if _overrides.has(node_name):
		return _overrides[node_name]
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root: Window = (loop as SceneTree).root
		if root != null:
			return root.get_node_or_null(NodePath(node_name))
	return null


## `DataRegistry`, or a JSON-backed stand-in with the same accessors.
static func registry() -> Object:
	var n := node("DataRegistry")
	if n != null:
		return n
	if _fallback_registry == null:
		_fallback_registry = JsonRegistry.new()
	return _fallback_registry


static func bus() -> Object:
	return node("EventBus")


static func state() -> Object:
	return node("GameState")


static func has_real_autoloads() -> bool:
	return node("DataRegistry") != null and node("GameState") != null


## Emit an EventBus signal if the bus exists. Never throws when it does not.
static func emit(signal_name: String, args: Array) -> bool:
	var b := bus()
	if b == null:
		return false
	if not b.has_signal(signal_name):
		return false
	b.callv("emit_signal", [signal_name] + args)
	return true


## The level cap currently in force. `GameState.current_level_cap()` when the
## autoload is alive, else row 0 of the cap table, else [constant DEFAULT_CAP].
static func level_cap() -> int:
	var s := state()
	if s != null and s.has_method("current_level_cap"):
		return int(s.current_level_cap())
	var r := registry()
	if r != null and r.has_method("get_level_cap"):
		return int(r.get_level_cap(0))
	return DEFAULT_CAP


## The PER-SEGMENT EXP multiplier currently in force (DATA_CONTRACT 8).
## `GameState.current_exp_multiplier()` when the autoload is alive, else the
## multiplier on row 0 of the cap table, else [constant DEFAULT_EXP_MULTIPLIER].
## There is no global multiplier to fall back on -- the top-level `expMultiplier`
## in `data/level_caps.json` is permanently null.
static func exp_multiplier() -> float:
	var s := state()
	if s != null and s.has_method("current_exp_multiplier"):
		return float(s.current_exp_multiplier())
	var r := registry()
	if r != null and r.has_method("get_exp_multiplier"):
		return float(r.get_exp_multiplier(0))
	return DEFAULT_EXP_MULTIPLIER


# --------------------------------------------------------------------------
# Fallback registry
# --------------------------------------------------------------------------

## A minimal read-only DataRegistry work-alike. Reads the committed veekun tables
## straight off disk, lazily, and int-casts everything JSON floated. Only the
## accessors the battle engine actually calls are implemented.
class JsonRegistry extends RefCounted:
	var _species: Dictionary = {}
	var _moves_by_name: Dictionary = {}
	var _moves_by_id: Dictionary = {}
	var _types: Dictionary = {}
	var _caps: Array = []
	var _loaded: Dictionary = {}

	func _read(file_name: String) -> Variant:
		for dir_path in [DATA_DIR, FIXTURE_DIR]:
			var path: String = dir_path.path_join(file_name)
			if not FileAccess.file_exists(path):
				continue
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				continue
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed != null:
				return parsed
		return null

	func _ensure(what: String) -> void:
		if _loaded.get(what, false):
			return
		_loaded[what] = true
		match what:
			"species":
				var rows: Variant = _read("species.json")
				if rows is Array:
					for row: Dictionary in rows:
						_species[int(row.get("id", 0))] = row
			"moves":
				var rows: Variant = _read("moves.json")
				if rows is Array:
					for row: Dictionary in rows:
						_moves_by_id[int(row.get("id", 0))] = row
						_moves_by_name[_slug(String(row.get("name", "")))] = row
			"types":
				var t: Variant = _read("typechart.json")
				if t is Dictionary:
					_types = t
			"caps":
				var c: Variant = _read("level_caps.json")
				if c is Dictionary and c.get("caps", null) is Array:
					_caps = c["caps"]

	static func _slug(s: String) -> String:
		return s.to_lower().replace(" ", "-").replace("_", "-")

	func get_species(id: int) -> Dictionary:
		_ensure("species")
		return _species.get(id, {})

	func has_species(id: int) -> bool:
		_ensure("species")
		return _species.has(id)

	func species_count() -> int:
		_ensure("species")
		return _species.size()

	func get_base_stat(id: int, stat: String) -> int:
		var s := get_species(id)
		if s.is_empty():
			return 0
		return int((s.get("stats", {}) as Dictionary).get(stat, 0))

	func get_species_types(id: int) -> PackedStringArray:
		var s := get_species(id)
		if s.is_empty():
			return PackedStringArray()
		return PackedStringArray(s.get("types", []))

	func get_move(id: int) -> Dictionary:
		_ensure("moves")
		return _moves_by_id.get(id, {})

	func get_move_by_name(move_name: String) -> Dictionary:
		_ensure("moves")
		return _moves_by_name.get(_slug(move_name), {})

	func move_count() -> int:
		_ensure("moves")
		return _moves_by_id.size()

	func get_type_effectiveness(atk: String, def: String) -> float:
		_ensure("types")
		var row: Dictionary = _types.get(atk.to_lower(), {})
		if row.is_empty() or not row.has(def.to_lower()):
			return 1.0
		return float(row[def.to_lower()])

	func get_type_multiplier(atk: String, defender_types: PackedStringArray) -> float:
		var m := 1.0
		for t in defender_types:
			m *= get_type_effectiveness(atk, t)
		return m

	func get_level_cap(index: int) -> int:
		_ensure("caps")
		if _caps.is_empty():
			return DEFAULT_CAP
		var i := clampi(index, 0, _caps.size() - 1)
		return int((_caps[i] as Dictionary).get("cap", DEFAULT_CAP))

	func level_cap_count() -> int:
		_ensure("caps")
		return _caps.size()

	func get_exp_multiplier(index: int) -> float:
		_ensure("caps")
		if _caps.is_empty():
			return DEFAULT_EXP_MULTIPLIER
		var i := clampi(index, 0, _caps.size() - 1)
		var raw: Variant = (_caps[i] as Dictionary).get("expMultiplier")
		if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
			return DEFAULT_EXP_MULTIPLIER
		var m := float(raw)
		if not is_finite(m) or m <= 0.0:
			return DEFAULT_EXP_MULTIPLIER
		return m
