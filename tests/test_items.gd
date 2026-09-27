extends "res://tests/framework/test_case.gd"
## `data/items.json` against everything that references an item id.
##
## WHY THIS FILE EXISTS. `items.json` shipped 93 rows -- 92 Mega Stones and the Key
## Stone -- while the evolution data referenced 40 items and NONE of them existed.
## Nothing caught it: no engine code loads `items.json` (DataRegistry does not index
## it), so the only thing that would ever have noticed was a player trying to evolve
## a Scyther. `tools/build_items.py` builds those 40 now, and this is the check that
## the linkage stays intact.
##
## It reads the files directly rather than through `DataRegistry`, precisely because
## the registry has no item accessor. If one is ever added, this file should keep
## reading raw -- it is testing the committed data, not the loader.

const ITEMS_PATH := "res://data/items.json"
const SPECIES_PATH := "res://data/species.json"
const MEGAS_PATH := "res://data/megas.json"

var _saved_level: int = 0


func before_each() -> void:
	_saved_level = Log.level
	Log.level = Log.Level.ERROR


func after_each() -> void:
	Log.level = _saved_level


## Raw JSON, or an empty Array when the file is absent or malformed.
func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed == null:
		return []
	# Both shapes are legal per build_items.py: a flat array, or {"items": [...]}.
	if parsed is Dictionary:
		return (parsed as Dictionary).get("items", [])
	return parsed


func _items() -> Array:
	var raw: Variant = _read(ITEMS_PATH)
	return raw if raw is Array else []


func _by_id() -> Dictionary:
	var out: Dictionary = {}
	for row: Variant in _items():
		if row is Dictionary:
			out[String((row as Dictionary).get("id", ""))] = row
	return out


## Every item id the evolution data asks for, mapped to the role it is used in:
## "use" for `item`, "hold" for `heldItem`.
func _evolution_items() -> Dictionary:
	var out: Dictionary = {}
	var species: Variant = _read(SPECIES_PATH)
	if not (species is Array):
		return out
	for sp: Variant in (species as Array):
		if not (sp is Dictionary):
			continue
		for edge: Variant in ((sp as Dictionary).get("evolutions", []) as Array):
			if not (edge is Dictionary):
				continue
			var e: Dictionary = edge
			if e.get("item", null) != null and not String(e["item"]).is_empty():
				out[String(e["item"])] = "use"
			if e.get("heldItem", null) != null and not String(e["heldItem"]).is_empty():
				out[String(e["heldItem"])] = "hold"
	return out


# ==========================================================================
# the linkage that was broken
# ==========================================================================

## THE regression this file exists for. 40 referenced, 0 present.
func test_every_item_an_evolution_needs_exists() -> void:
	var needed := _evolution_items()
	if needed.is_empty():
		pending("data/species.json has no evolution items to check")
		return
	var have := _by_id()
	if have.is_empty():
		pending("data/items.json is not built")
		return
	eq(needed.size(), 40, "the evolution data references 40 distinct items")

	var missing := PackedStringArray()
	for item_id: String in needed:
		if not have.has(item_id):
			missing.append(item_id)
	eq(Array(missing), [], "every referenced evolution item exists in items.json")


## Mega Stones are the other referencing file, and the same class of bug applies.
func test_every_mega_stone_exists() -> void:
	var megas: Variant = _read(MEGAS_PATH)
	if not (megas is Array) and not (megas is Dictionary):
		pending("data/megas.json is not built")
		return
	# megas.json is an object with a `forms` array, so _read hands back the raw doc
	# only when it has an `items` key -- read it directly instead.
	var f := FileAccess.open(MEGAS_PATH, FileAccess.READ)
	if f == null:
		pending("data/megas.json is not readable")
		return
	var doc: Variant = JSON.parse_string(f.get_as_text())
	if not (doc is Dictionary):
		pending("data/megas.json is not an object")
		return
	var forms: Array = (doc as Dictionary).get("forms", [])
	if forms.is_empty():
		pending("data/megas.json has no forms")
		return

	var have := _by_id()
	var missing := PackedStringArray()
	var stones := 0
	for form: Variant in forms:
		var stone: Variant = (form as Dictionary).get("stone", null)
		if stone == null or String(stone).is_empty():
			continue     # Mega Rayquaza: requiresMove, no stone
		stones += 1
		if not have.has(String(stone)):
			missing.append(String(stone))
	is_true(stones > 0, "there are stones to check (%d)" % stones)
	eq(Array(missing), [], "every Mega Stone exists in items.json")
	is_true(have.has("key-stone"), "and so does the Key Stone")


# ==========================================================================
# the mechanic each item has to support
# ==========================================================================

## A hold-and-level item that is not holdable cannot be held, so the evolution it
## gates is unreachable -- exactly the failure mode the rework was meant to end.
## Not consumable either: levelling up while holding it does not spend it.
func test_hold_and_level_items_are_holdable_and_not_consumed() -> void:
	var needed := _evolution_items()
	var have := _by_id()
	if have.is_empty() or needed.is_empty():
		pending("data/items.json or species.json is not built")
		return
	var checked := 0
	for item_id: String in needed:
		if String(needed[item_id]) != "hold" or not have.has(item_id):
			continue
		checked += 1
		var row: Dictionary = have[item_id]
		is_true(bool(row.get("holdable", false)), "%s is holdable" % item_id)
		is_false(bool(row.get("consumable", true)), "%s is not consumed" % item_id)
	eq(checked, 17, "all 17 hold-and-level items were checked")


## A use-item IS spent when it is used, which is what separates the two families.
func test_use_items_are_consumable() -> void:
	var needed := _evolution_items()
	var have := _by_id()
	if have.is_empty() or needed.is_empty():
		pending("data/items.json or species.json is not built")
		return
	var checked := 0
	for item_id: String in needed:
		if String(needed[item_id]) != "use" or not have.has(item_id):
			continue
		checked += 1
		is_true(bool((have[item_id] as Dictionary).get("consumable", false)),
			"%s is consumed when used" % item_id)
	eq(checked, 23, "all 23 use-items were checked")


## `evolves` is derived from the evolution data by the builder. If it ever stops
## matching, the file is stale and the builder was not re-run.
func test_the_evolves_field_matches_the_evolution_data() -> void:
	var species: Variant = _read(SPECIES_PATH)
	var have := _by_id()
	if have.is_empty() or not (species is Array):
		pending("data/items.json or species.json is not built")
		return

	var actual: Dictionary = {}
	for sp: Variant in (species as Array):
		for edge: Variant in ((sp as Dictionary).get("evolutions", []) as Array):
			var e: Dictionary = edge
			for key: String in ["item", "heldItem"]:
				if e.get(key, null) == null or String(e[key]).is_empty():
					continue
				var id := String(e[key])
				if not actual.has(id):
					actual[id] = []
				var target := int(e.get("to", 0))
				if not (actual[id] as Array).has(target):
					(actual[id] as Array).append(target)

	var checked := 0
	for item_id: String in actual:
		if not have.has(item_id):
			continue
		var row: Dictionary = have[item_id]
		if not row.has("evolves"):
			continue
		checked += 1
		var want: Array = (actual[item_id] as Array).duplicate()
		want.sort()
		var got: Array = []
		for v: Variant in (row["evolves"] as Array):
			got.append(int(v))
		got.sort()
		eq(got, want, "%s evolves the species the data says it does" % item_id)
	is_true(checked >= 40, "every evolution item's `evolves` was checked (%d)" % checked)


# ==========================================================================
# the file's own shape
# ==========================================================================

func test_item_ids_are_unique() -> void:
	var rows := _items()
	if rows.is_empty():
		pending("data/items.json is not built")
		return
	var seen: Dictionary = {}
	var dupes := PackedStringArray()
	for row: Variant in rows:
		var id := String((row as Dictionary).get("id", ""))
		if seen.has(id):
			dupes.append(id)
		seen[id] = true
	eq(Array(dupes), [], "no duplicate item ids")
	eq(seen.size(), rows.size(), "every row has a distinct id")


func test_every_row_is_complete() -> void:
	var rows := _items()
	if rows.is_empty():
		pending("data/items.json is not built")
		return
	var bad := PackedStringArray()
	for row: Variant in rows:
		var r: Dictionary = row
		var id := String(r.get("id", ""))
		if id.is_empty() \
				or String(r.get("name", "")).is_empty() \
				or String(r.get("description", "")).is_empty() \
				or String(r.get("category", "")).is_empty() \
				or String(r.get("pocket", "")).is_empty() \
				or int(r.get("price", -1)) < 0:
			bad.append(id if not id.is_empty() else "<no id>")
	eq(Array(bad), [], "every row has an id, name, description, category, pocket and price")


## A free item cannot be sold for half of nothing.
func test_sellable_agrees_with_price() -> void:
	var rows := _items()
	if rows.is_empty():
		pending("data/items.json is not built")
		return
	var bad := PackedStringArray()
	for row: Variant in rows:
		var r: Dictionary = row
		if bool(r.get("sellable", false)) and int(r.get("price", 0)) <= 0:
			bad.append(String(r.get("id", "")))
	eq(Array(bad), [], "nothing priced at 0 is marked sellable")
