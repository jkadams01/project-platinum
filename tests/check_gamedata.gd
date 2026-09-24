extends SceneTree
# Contract smoke test for the romdata stream.
#   godot --headless --path . --script res://tests/check_gamedata.gd
# Reads the four files build_gamedata.py produces and asserts on their CONTENT.

var failed := 0

func expect(label: String, ok: bool, detail: String = "") -> void:
	print("  [%s] %s%s" % ["PASS" if ok else "FAIL", label,
		("  -- " + detail) if detail != "" else ""])
	if not ok:
		failed += 1

func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open " + path)
		failed += 1
		return null
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_error("bad JSON in %s: %s (line %d)" % [path, j.get_error_message(), j.get_error_line()])
		failed += 1
		return null
	return j.data

func caps_non_decreasing(rows: Array) -> bool:
	var prev := 0
	for r in rows:
		if int(r["cap"]) < prev:
			return false
		prev = int(r["cap"])
	return prev == 100

func has_species(rows: Array, dex: int) -> bool:
	for e in rows:
		if int(e["species"]) == dex:
			return true
	return false

func all_tables_have_contract_fields(enc: Dictionary) -> bool:
	for k in enc:
		for field in ["grassRate", "grass", "surf", "oldRod", "goodRod", "superRod", "curated"]:
			if not (enc[k] as Dictionary).has(field):
				return false
	return true

func _initialize() -> void:
	print("Godot %s -- gamedata contract check" % Engine.get_version_info().string)

	var caps: Dictionary = load_json("res://data/level_caps.json")
	var text: Dictionary = load_json("res://data/rom/text.json")
	var enc: Dictionary = load_json("res://data/rom/encounters.json")
	var trn: Dictionary = load_json("res://data/rom/trainers.json")
	if failed > 0:
		quit(1)
		return

	var species: Array = text["species"]

	# --- contract section 8: level caps (COMMITTED) ---
	var rows: Array = caps["caps"]
	expect("level_caps.json has 15 rows", rows.size() == 15, "got %d" % rows.size())
	expect("caps are non-decreasing and end at 100", caps_non_decreasing(rows))
	expect("roark cap row is 14, raised by badge:coal",
		rows[1]["checkpoint"] == "roark" and int(rows[1]["cap"]) == 14
			and rows[1]["raisedBy"] == "badge:coal")
	expect("cynthia cap row is 62",
		rows[13]["checkpoint"] == "cynthia" and int(rows[13]["cap"]) == 62)
	expect("rule is hard-xp-stop", caps["rule"] == "hard-xp-stop")

	# --- contract section 7: trainers ---
	expect("928 trainers", trn.size() == 928, "got %d" % trn.size())
	var roark: Dictionary = trn["roark"]
	var rparty: Array = roark["party"]
	var ace: Dictionary = rparty[rparty.size() - 1]
	expect("Roark's ace is Cranidos 14",
		species[int(ace["species"])] == "Cranidos" and int(ace["level"]) == 14,
		"%s %d" % [species[int(ace["species"])], int(ace["level"])])
	expect("Roark keyed as gym-leader with the coal badge",
		roark["class"] == "gym-leader" and roark["badge"] == "coal")
	var cyn: Dictionary = trn["cynthia"]
	var cparty: Array = cyn["party"]
	var cace: Dictionary = cparty[cparty.size() - 1]
	expect("Cynthia's ace is Garchomp 62",
		species[int(cace["species"])] == "Garchomp" and int(cace["level"]) == 62,
		"%s %d" % [species[int(cace["species"])], int(cace["level"])])
	var cmoves: Array = cace["moves"]
	expect("Cynthia's Garchomp has 4 named moves",
		cmoves.size() == 4 and cmoves[0] == "dragon-rush", str(cmoves))

	# --- contract section 6: encounters ---
	expect("183 encounter tables", enc.size() == 183, "got %d" % enc.size())
	var r201: Dictionary = enc["route_201"]
	var grass: Array = r201["grass"]
	var names := PackedStringArray()
	var total := 0
	for e in grass:
		names.append(species[int(e["species"])])
		total += int(e["weight"])
	expect("Route 201 vanilla grass has Starly and Bidoof",
		"Starly" in names and "Bidoof" in names, ", ".join(names))
	expect("Route 201 vanilla grass weights sum to 100", total == 100, "sum=%d" % total)
	var r201_curated: Array = r201["curated"]
	expect("Route 201 curated array is separate and holds Lechonk #915",
		has_species(r201_curated, 915) and not has_species(grass, 915),
		"%d curated rows" % r201_curated.size())
	var curated_areas := 0
	for k in enc:
		if (enc[k]["curated"] as Array).size() > 0:
			curated_areas += 1
	expect("13 encounter tables carry curated rows", curated_areas == 13, "got %d" % curated_areas)
	expect("every table exposes the full contract shape", all_tables_have_contract_fields(enc))

	print("\n%s (%d failures)" % ["ALL GODOT CHECKS PASSED" if failed == 0 else "GODOT CHECKS FAILED", failed])
	quit(0 if failed == 0 else 1)
