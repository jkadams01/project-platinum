extends RefCounted
## `data/rom/bosses.json` (DATA_CONTRACT 7.1) -> a battle setup, and a boss's
## rewards on defeat.
##
## Boss fights are NOT in `trainers.json`. Every gym leader, Elite Four member,
## Champion, Galactic boss and rival battle is authored in `bosses.json`, which
## overrides the ROM record of the same trainer by `romTrainerKey`. So this is the
## only place the engine gets a boss roster from, and `trainers.json` is never
## consulted for one.
##
## `bosses.json` is GITIGNORED (it is regenerated from the owner's ROM), so every
## accessor degrades: a missing file leaves the table empty, [method has] returns
## false, and the caller shows "that fight is not built yet" instead of crashing.
## That is the same policy as `DataRegistry` and `Encounters`.
##
## THE THREE THINGS A VICTORY DOES, in this order (DATA_CONTRACT 7.1 + 8):
##   1. `flag:<key>_defeated` is set -- what §12 events and the Elite Four cap
##      rows condition on.
##   2. the badge is earned, which is what raises the hard level cap and unlocks
##      the traversal verb bound to it (Coal -> SMASH).
##   3. `awardsStone` goes into the bag. Gym leaders only, and it may be a LIST
##      (Volkner hands over two).
## Both 1 and 2 route through `GameState`, which owns the cap ladder, so this file
## never touches `cap_index` itself.

const Stats := preload("res://src/battle/stats.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")

const DATA_PATH := "res://data/rom/bosses.json"
const FIXTURE_PATH := "res://tests/fixtures/bosses.json"

## Every boss has exactly this many party members (DATA_CONTRACT 7.1).
const PARTY_SIZE := 6

static var _bosses: Dictionary = {}
static var _meta: Dictionary = {}
static var _source: String = "missing"


## Load (or reload) the table. Returns the number of bosses read. Safe to call
## repeatedly; tests call it with an explicit path.
static func boot(path: String = DATA_PATH) -> int:
	_bosses = {}
	_meta = {}
	_source = "missing"
	var raw: Variant = _parse(path)
	if raw != null:
		_source = "data"
	elif path != FIXTURE_PATH:
		raw = _parse(FIXTURE_PATH)
		if raw != null:
			_source = "fixture"
	if raw == null or not (raw is Dictionary):
		Log.warn("no boss table at %s; boss fights are unavailable" % path, "Bosses")
		return 0

	var d: Dictionary = raw
	for k: Variant in d:
		if String(k) != "bosses":
			_meta[String(k)] = d[k]
	var rows: Variant = d.get("bosses", {})
	if not (rows is Dictionary):
		Log.error("bosses.json 'bosses' must be an object keyed by boss id", "Bosses")
		return 0
	for k: Variant in (rows as Dictionary):
		var row: Variant = (rows as Dictionary)[k]
		if row is Dictionary:
			_bosses[String(k)] = _intify(row)

	# DATA_CONTRACT 7.1 says this field "mirrors data/level_caps.json", where the
	# top-level expMultiplier is permanently null and multipliers are per-segment
	# (DATA_CONTRACT 8). A number here is a stale generator, not a rule -- say so
	# once and read nothing from it.
	if _meta.get("expMultiplier", null) != null:
		Log.warn("bosses.json carries a top-level expMultiplier (%s); EXP multipliers "
			% _meta["expMultiplier"]
			+ "are per-segment (DATA_CONTRACT 8) and this field is ignored", "Bosses")

	Log.info("loaded %d bosses (%s)" % [_bosses.size(), _source], "Bosses")
	return _bosses.size()


static func source() -> String:
	return _source


static func count() -> int:
	return _bosses.size()


static func keys() -> PackedStringArray:
	var out := PackedStringArray(_bosses.keys())
	out.sort()
	return out


static func has(key: String) -> bool:
	return _bosses.has(key)


## The raw contract row, or {} when the table has no such boss.
static func get_boss(key: String) -> Dictionary:
	return _bosses.get(key, {})


static func meta() -> Dictionary:
	return _meta


# --------------------------------------------------------------------------
# Building the fight
# --------------------------------------------------------------------------

## The boss's six Pokemon as battle-ready Dictionaries, in send-out order.
static func build_party(key: String) -> Array:
	var boss := get_boss(key)
	var out: Array = []
	for member: Variant in (boss.get("party", []) as Array):
		if member is Dictionary:
			var mon := PartyBuilder.from_boss_member(member)
			if not mon.is_empty():
				out.append(mon)
	return out


## The trainer block the battle engine reads (`name`, `ai`, `prizeMoney`, and the
## `keyStone` gate that decides whether this side may Mega Evolve at all).
##
## `keyStone` is true only when the row actually declares a `megaForm`: the engine
## defaults it to true, and a boss with no Mega must never be handed the Key Stone
## just because one of its Pokemon happens to hold a stone-shaped item.
static func trainer_block(key: String) -> Dictionary:
	var boss := get_boss(key)
	return {
		"name": String(boss.get("name", key.capitalize())),
		"class": String(boss.get("class", "trainer")),
		"ai": int(boss.get("ai", 7)),
		"prizeMoney": int(boss.get("prizeMoney", 0)) if boss.get("prizeMoney", null) != null else 0,
		"keyStone": boss.get("megaForm", null) != null,
	}


## The `EventBus.battle_started` / `SceneRouter.enter_battle` payload for this
## fight. `player_party` is passed through untouched -- these are the very
## Dictionaries in `GameState.party`, so damage and EXP persist after the battle.
##
## `cap` is the level cap the PLAYER is actually under (`GameState`), not the row's
## authored `cap`. The two agree when the player arrives on schedule; when they do
## not, the player's real progression has to win, or beating a boss early would
## silently re-lower their cap.
static func battle_setup(key: String, player_party: Array, seed_value: int = 0) -> Dictionary:
	var boss := get_boss(key)
	if boss.is_empty():
		Log.error("no boss '%s' in the table" % key, "Bosses")
		return {}
	var authored_cap := int(boss.get("cap", 0))
	var live_cap := GameState.current_level_cap()
	if authored_cap > 0 and authored_cap != live_cap:
		Log.info("boss '%s' is authored at cap %d; the player is under cap %d" % [
			key, authored_cap, live_cap], "Bosses")
	return {
		"kind": "trainer",
		"party": player_party,
		"opponent": build_party(key),
		"trainer": trainer_block(key),
		"cap": live_cap,
		"seed": seed_value if seed_value != 0 else randi(),
		"boss": key,
		"playerName": GameState.player_name,
	}


## The ace's party index, so the UI can say "this is the one".
static func ace_slot(key: String) -> int:
	return int((get_boss(key).get("ace", {}) as Dictionary).get("slot", -1))


# --------------------------------------------------------------------------
# Rewards
# --------------------------------------------------------------------------

## True once `flag:<key>_defeated` is set.
static func is_defeated(key: String) -> bool:
	return GameState.get_flag("%s_defeated" % key)


## Apply everything beating this boss grants. Idempotent: calling it twice awards
## nothing the second time, because `earn_badge` and the flag both refuse a repeat.
##
## Returns `{flag, badge, stones, capBefore, capAfter, messages}` so the caller can
## put the fanfare on screen without re-deriving any of it.
static func apply_victory(key: String) -> Dictionary:
	var boss := get_boss(key)
	var out: Dictionary = {
		"boss": key,
		"flag": "%s_defeated" % key,
		"badge": "",
		"stones": PackedStringArray(),
		"capBefore": GameState.current_level_cap(),
		"capAfter": GameState.current_level_cap(),
		"verbs": PackedStringArray(),
		"messages": [],
	}
	if boss.is_empty():
		return out

	var first_time := not GameState.get_flag(String(out["flag"]))
	GameState.set_flag(String(out["flag"]), true)

	var badge := String(boss.get("badge", "")) if boss.get("badge", null) != null else ""
	if not badge.is_empty():
		out["badge"] = badge
		if GameState.earn_badge(badge):
			(out["messages"] as Array).append("%s received the %s Badge!" % [
				GameState.player_name, badge.capitalize()])
			var verb := _verb_for_badge(badge)
			if not verb.is_empty():
				(out["verbs"] as PackedStringArray).append(verb)
				(out["messages"] as Array).append(
					"%s can now be used outside of battle!" % verb.to_upper())

	out["capAfter"] = GameState.current_level_cap()
	if int(out["capAfter"]) > int(out["capBefore"]):
		(out["messages"] as Array).append("The level cap rose to %d!" % int(out["capAfter"]))

	for stone: String in _stones_of(boss):
		(out["stones"] as PackedStringArray).append(stone)
		if first_time:
			GameState.bag[stone] = int(GameState.bag.get(stone, 0)) + 1
			(out["messages"] as Array).append("%s obtained the %s!" % [
				GameState.player_name, _pretty(stone)])

	Log.info("victory over %s: badge=%s stones=%s cap %d -> %d" % [
		key, out["badge"], String(", ").join(out["stones"]),
		int(out["capBefore"]), int(out["capAfter"])], "Bosses")
	return out


## `awardsStone` is a single id or a list of them (Volkner hands over two).
static func _stones_of(boss: Dictionary) -> PackedStringArray:
	var raw: Variant = boss.get("awardsStone", null)
	var out := PackedStringArray()
	if raw == null:
		return out
	if raw is Array:
		for s: Variant in (raw as Array):
			out.append(String(s))
	else:
		out.append(String(raw))
	return out


## The traversal verb a badge unlocks. Mirrors `GameState.can_traverse` and
## DATA_CONTRACT's "Traversal verbs" table 1:1. The Relic badge deliberately maps
## to nothing -- there is no `defog` verb, fog is deleted from the game.
static func _verb_for_badge(badge: String) -> String:
	match badge.to_lower():
		"coal": return "smash"
		"forest": return "cut"
		"cobble": return "fly"
		"fen": return "surf"
		"mine": return "strength"
		"icicle": return "climb"
		"beacon": return "waterfall"
	return ""


static func _pretty(item_id: String) -> String:
	var parts := item_id.split("-")
	var out := PackedStringArray()
	for p in parts:
		out.append(p.capitalize())
	return String(" ").join(out)


# --------------------------------------------------------------------------

static func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		Log.error("%s is empty" % path, "Bosses")
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		Log.error("%s: JSON parse error on line %d: %s" % [
			path, json.get_error_line(), json.get_error_message()], "Bosses")
		return null
	return json.data


## JSON floats every number (verified on 4.7.2); species ids, levels and slots are
## all integers and a float used as a level or a Dictionary key is a bug that
## surfaces hours later. Same boundary fix DataRegistry applies.
static func _intify(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and absf(f) < 9.007199254740992e15 and f == floor(f):
				return int(f)
			return f
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k: Variant in (v as Dictionary):
				out[k] = _intify((v as Dictionary)[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for e: Variant in (v as Array):
				arr.append(_intify(e))
			return arr
	return v
