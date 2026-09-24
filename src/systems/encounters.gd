extends RefCounted
## Wild encounters: the per-step roll on tall grass, and the merged
## vanilla + curated species table behind it.
##
## DATA (docs/DATA_CONTRACT.md 6, `data/rom/encounters.json`, gitignored):
##   "route_201": {"grassRate": 30,
##                 "grass":   [{"species","min","max","weight"}, ...],   <- ROM
##                 "surf": [], "oldRod": [], "goodRod": [], "superRod": [],
##                 "curated": [{..., "table": "grass", "gen": 9}]}       <- design
## `grass` is the vanilla Platinum table extracted from the owner's cartridge.
## `curated` is the cross-gen placement from docs/research/game-design.md 4.
## THE RUNTIME MERGES THEM BY WEIGHT -- neither list is a replacement for the
## other, and a curated entry carries `table` saying which list it joins.
##
## THE LEVEL CAP IS ENFORCED HERE, NOT IN THE BATTLE. A wild Pokemon rolled above
## the active cap would be unbeatable-by-design in a game whose whole premise is
## "at/above the cap you gain zero exp" (game-design.md 2.5): the player could
## never grind past it. [method roll] clamps the rolled level to the cap, so the
## invariant "no wild encounter ever exceeds the current cap" holds by
## construction rather than by every caller remembering to check.
##
## RNG is an owned RandomNumberGenerator, not the global `randi()`, so a test can
## seed it and get the same sequence every run.

const DATA_PATH := "res://data/rom/encounters.json"
const FIXTURE_PATH := "res://tests/fixtures/encounters.json"

## The tables a zone can offer. `grass` is the only one the step counter drives;
## the rest are entered deliberately (surfing, fishing) by other systems.
const TABLES: Array = ["grass", "surf", "oldRod", "goodRod", "superRod"]

## DS-style encounter roll: one byte per step, `rand(0, 255) < rate`. A route
## with `grassRate` 30 therefore encounters on ~11.7% of grass steps -- about one
## every 8.5 steps, which is the vanilla feel.
const RATE_DENOMINATOR := 256.0

var rng := RandomNumberGenerator.new()

## Steps taken on grass since the last encounter. Reset on battle end.
var steps_since_encounter: int = 0
## Total grass steps this session, for telemetry and tests.
var grass_steps: int = 0
## Vanilla grants a short grace period after a battle so you can walk out of the
## patch. Without it a 30-rate route can chain two encounters back to back.
var min_steps_between: int = 3
## Multiplies every encounter chance. 0.0 disables encounters outright (used by
## cutscenes and by the Repel-equivalent), >1.0 is a debug convenience.
var rate_scale: float = 1.0
## "" = ignore the `time` field on curated entries; "day"/"night" filter on it.
var time_of_day: String = ""
## `func() -> int`. Left unset, the real GameState cap is used.
var cap_provider: Callable = Callable()

var _zones: Dictionary = {}          # String zone -> Dictionary
var _source: String = "missing"      # "data" | "fixture" | "missing"
var _merged_cache: Dictionary = {}   # "zone/table/time" -> Array


func _init() -> void:
	rng.randomize()


## Loads the encounter tables. Falls back to the committed fixture when the
## ROM-derived file has not been generated, exactly like DataRegistry, so this
## system is usable in a fresh checkout. Returns true only for the real data.
func boot(path: String = DATA_PATH) -> bool:
	_zones.clear()
	_merged_cache.clear()
	var raw: Variant = _parse(path)
	_source = "data"
	if raw == null and path != FIXTURE_PATH:
		raw = _parse(FIXTURE_PATH)
		_source = "fixture"
	if raw == null or not (raw is Dictionary):
		_source = "missing"
		_log("warn", "no encounter data at %s; every roll will come back empty" % path)
		return false
	for k: Variant in (raw as Dictionary):
		var v: Variant = (raw as Dictionary)[k]
		if v is Dictionary:
			_zones[String(k)] = v
	_log("info", "loaded %d encounter zones (%s)" % [_zones.size(), _source])
	return _source == "data"


func source() -> String:
	return _source


func zone_count() -> int:
	return _zones.size()


func has_zone(zone: String) -> bool:
	return _zones.has(zone)


func zone_data(zone: String) -> Dictionary:
	return _zones.get(zone, {})


# --------------------------------------------------------------------------
# The merged table
# --------------------------------------------------------------------------

## Vanilla entries for [param table] plus every curated entry tagged for that
## table, as one weighted list. Entries keep a `source` of "vanilla" or
## "curated" so the encounter log can say where a Pokemon came from.
func merged_table(zone: String, table: String = "grass") -> Array:
	var key := "%s/%s/%s" % [zone, table, time_of_day]
	if _merged_cache.has(key):
		return _merged_cache[key]

	var z: Dictionary = _zones.get(zone, {})
	var out: Array = []
	for entry: Variant in (z.get(table, []) as Array):
		if entry is Dictionary:
			out.append(_normalise(entry, "vanilla"))
	for entry: Variant in (z.get("curated", []) as Array):
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		# A curated entry without `table` joins the grass table, which is where
		# the overwhelming majority of them live.
		if String(e.get("table", "grass")) != table:
			continue
		if not _time_ok(e):
			continue
		out.append(_normalise(e, "curated"))

	_merged_cache[key] = out
	return out


## Sum of the merged table's weights. 0 means "this zone has no such table".
func total_weight(zone: String, table: String = "grass") -> int:
	var sum := 0
	for e: Dictionary in merged_table(zone, table):
		sum += int(e["weight"])
	return sum


## Probability per step of an encounter on this zone's [param table], 0.0..1.0.
func encounter_chance(zone: String, table: String = "grass") -> float:
	var z: Dictionary = _zones.get(zone, {})
	if z.is_empty() or merged_table(zone, table).is_empty():
		return 0.0
	var rate := 0
	if table == "grass":
		rate = int(z.get("grassRate", 0))
	else:
		rate = int((z.get("rates", {}) as Dictionary).get(table, 0))
	return clampf(float(rate) / RATE_DENOMINATOR * rate_scale, 0.0, 1.0)


# --------------------------------------------------------------------------
# Rolling
# --------------------------------------------------------------------------

## The active hard level cap.
func level_cap() -> int:
	if cap_provider.is_valid():
		return int(cap_provider.call())
	return GameState.current_level_cap()


## Picks one entry by weight and rolls its level. Returns {} when the zone has no
## such table.
##
## The returned `level` is ALWAYS <= [method level_cap]. `cappedFrom` records the
## uncapped roll when clamping actually happened, so the encounter log can show
## "a level 18 Bidoof, held to 14 by the cap" rather than silently lying.
func roll(zone: String, table: String = "grass") -> Dictionary:
	var entries := merged_table(zone, table)
	if entries.is_empty():
		return {}
	var total := total_weight(zone, table)
	if total <= 0:
		return {}

	var pick := rng.randi_range(1, total)
	var chosen: Dictionary = entries[entries.size() - 1]
	var running := 0
	for e: Dictionary in entries:
		running += int(e["weight"])
		if pick <= running:
			chosen = e
			break

	var lo: int = int(chosen["min"])
	var hi: int = maxi(int(chosen["max"]), lo)
	var raw_level := rng.randi_range(lo, hi)

	var cap := level_cap()
	var level := mini(raw_level, cap)
	level = maxi(level, 1)

	var out: Dictionary = {
		"species": int(chosen["species"]),
		"level": level,
		"table": table,
		"zone": zone,
		"source": String(chosen["source"]),
		"weight": int(chosen["weight"]),
	}
	if level != raw_level:
		out["cappedFrom"] = raw_level
	return out


## Call once per completed step. [param code] is the collision code of the tile
## the player just landed on; only tall grass (4) counts.
##
## Returns the encounter dictionary, or {} for "nothing happened" -- which is the
## overwhelmingly common case, so it allocates nothing on the hot path beyond the
## empty literal.
func step(code: int, zone: String) -> Dictionary:
	if code != 4:
		return {}
	grass_steps += 1
	steps_since_encounter += 1
	if steps_since_encounter <= min_steps_between:
		return {}
	var chance := encounter_chance(zone, "grass")
	if chance <= 0.0 or rng.randf() >= chance:
		return {}
	var result := roll(zone, "grass")
	if result.is_empty():
		return {}
	steps_since_encounter = 0
	_announce(zone, result)
	return result


## Deliberate (non-step) encounter: surfing, or a fishing rod.
func roll_table(zone: String, table: String) -> Dictionary:
	var result := roll(zone, table)
	if not result.is_empty():
		_announce(zone, result)
	return result


## Call when a battle ends so the grace period starts again.
func notify_battle_ended() -> void:
	steps_since_encounter = 0


func reset() -> void:
	steps_since_encounter = 0
	grass_steps = 0


# --------------------------------------------------------------------------

func _announce(zone: String, result: Dictionary) -> void:
	var lv: int = int(result["level"])
	EventBus.encounter_triggered.emit(StringName(zone), Vector2i(lv, lv))


func _normalise(e: Dictionary, src: String) -> Dictionary:
	var lo: int = int(e.get("min", 1))
	var hi: int = maxi(int(e.get("max", lo)), lo)
	return {
		"species": int(e.get("species", 0)),
		"min": lo,
		"max": hi,
		"weight": maxi(int(e.get("weight", 0)), 0),
		"source": src,
		"name": String(e.get("name", "")),
	}


func _time_ok(e: Dictionary) -> bool:
	if time_of_day.is_empty():
		return true
	var t := String(e.get("time", ""))
	return t.is_empty() or t == time_of_day


func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		_log("error", "%s: JSON parse error on line %d: %s" % [
			path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _log(level: String, message: String) -> void:
	match level:
		"error": Log.error(message, "Encounters")
		"warn": Log.warn(message, "Encounters")
		_: Log.info(message, "Encounters")
