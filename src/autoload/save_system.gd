extends Node
## Save/load to `user://` as JSON.
##
## WHY JSON AND NOT A Resource
## `ResourceLoader.load()` runs code. A hand-written .tres that embeds a GDScript
## sub-resource executes its `_init()` during the load, and in 4.7.2 there is no
## opt-out: the signature is `load(path, type_hint, cache_mode)` with no
## `allow_objects` flag, and the type hint does not stop the sub-resource being
## instantiated (docs/research/godot-architecture.md 3.5, demonstrated, not theoretical).
## Save files get shared in the fan-remake scene, so `user://` is hostile input.
## `JSON.parse_string` cannot construct an Object, so it cannot execute anything.
##
## THE PRICE OF JSON, AND HOW IT IS PAID
## JSON has no integer type: every number comes back TYPE_FLOAT. The fix is
## applied exactly once, at the boundary, in `GameState.from_dict()` -- every
## numeric field is re-cast with `int()` there. Nothing downstream sees a float
## where an int is meant. [method load_slot] additionally validates the envelope
## (magic, version, state is a Dictionary) before handing anything to GameState.
##
## WRITES ARE CRASH-SAFE
## The payload is written to `<slot>.json.tmp` and renamed over the real file, so
## a crash mid-write destroys the temp file, never the previous save.

const SLOT_FMT := "user://save_%d.json"
const TMP_SUFFIX := ".tmp"
const MAGIC := "PLAT"
const VERSION := 1
const MAX_SLOTS := 3


func slot_path(slot: int) -> String:
	return SLOT_FMT % slot


func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Writes GameState to `user://save_<slot>.json`. Returns true on success and
## emits `game_saved`.
func save_slot(slot: int = 0) -> bool:
	var payload := {
		"magic": MAGIC,
		"version": VERSION,
		"savedAt": Time.get_unix_time_from_system(),
		"savedAtString": Time.get_datetime_string_from_system(false, true),
		"summary": {
			"playerName": GameState.player_name,
			"badges": GameState.badge_count(),
			"party": GameState.party_size(),
			"playtime": GameState.playtime_string(),
			"levelCap": GameState.current_level_cap(),
		},
		"state": GameState.to_dict(),
	}
	var text := JSON.stringify(payload, "\t")
	var path := slot_path(slot)
	var tmp := path + TMP_SUFFIX

	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		Log.error("cannot open %s: error %d" % [tmp, FileAccess.get_open_error()], "SaveSystem")
		EventBus.game_saved.emit(slot, false)
		return false
	f.store_string(text)
	f.close()

	var d := DirAccess.open("user://")
	if d == null:
		Log.error("cannot open user:// : error %d" % DirAccess.get_open_error(), "SaveSystem")
		EventBus.game_saved.emit(slot, false)
		return false
	if d.file_exists(path):
		d.remove(path)
	var err := d.rename(tmp, path)
	if err != OK:
		Log.error("rename %s -> %s failed: error %d" % [tmp, path, err], "SaveSystem")
		EventBus.game_saved.emit(slot, false)
		return false

	Log.info("saved slot %d (%d bytes)" % [slot, text.length()], "SaveSystem")
	EventBus.game_saved.emit(slot, true)
	return true


## Reads a slot and applies it to GameState. Returns false -- leaving GameState
## untouched -- on any missing file, parse error, bad envelope or version mismatch.
func load_slot(slot: int = 0) -> bool:
	var payload := read_slot(slot)
	if payload.is_empty():
		EventBus.game_loaded.emit(slot, false)
		return false
	var state: Variant = payload.get("state")
	if not (state is Dictionary):
		Log.error("slot %d has no state object" % slot, "SaveSystem")
		EventBus.game_loaded.emit(slot, false)
		return false
	if not GameState.from_dict(state):
		EventBus.game_loaded.emit(slot, false)
		return false
	Log.info("loaded slot %d" % slot, "SaveSystem")
	EventBus.game_loaded.emit(slot, true)
	return true


## Parses and validates a slot WITHOUT applying it. Empty Dictionary on failure.
func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		Log.debug("slot %d is empty (%s)" % [slot, path], "SaveSystem")
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		Log.error("slot %d is a zero-byte file" % slot, "SaveSystem")
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		Log.error("slot %d: JSON parse error on line %d: %s" % [
			slot, json.get_error_line(), json.get_error_message()], "SaveSystem")
		return {}
	var data: Variant = json.data
	if not (data is Dictionary):
		Log.error("slot %d is not a JSON object" % slot, "SaveSystem")
		return {}
	var payload: Dictionary = data
	if String(payload.get("magic", "")) != MAGIC:
		Log.error("slot %d has bad magic '%s'" % [slot, payload.get("magic", "")], "SaveSystem")
		return {}
	if int(payload.get("version", -1)) != VERSION:
		Log.error("slot %d is save version %s, this build reads %d" % [
			slot, payload.get("version", "?"), VERSION], "SaveSystem")
		return {}
	return payload


## The header a save-slot menu needs, without touching GameState.
## `{"exists": bool}` when the slot is empty or unreadable.
func slot_summary(slot: int) -> Dictionary:
	var payload := read_slot(slot)
	if payload.is_empty():
		return {"exists": false}
	var summary: Dictionary = payload.get("summary", {})
	summary["exists"] = true
	summary["savedAt"] = int(payload.get("savedAt", 0))
	summary["savedAtString"] = String(payload.get("savedAtString", ""))
	return summary


func delete_slot(slot: int) -> bool:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return false
	var d := DirAccess.open("user://")
	if d == null:
		return false
	var err := d.remove(path)
	if err != OK:
		Log.error("could not delete slot %d: error %d" % [slot, err], "SaveSystem")
		return false
	Log.info("deleted slot %d" % slot, "SaveSystem")
	return true
