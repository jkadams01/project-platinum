# Headless load test for the committed dex data (docs/DATA_CONTRACT.md sections 1-5).
# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/data_contract_test.gd
# Exit 0 = pass, 1 = fail.
extends SceneTree

var failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  [PASS] ", label)
	else:
		failures += 1
		print("  [FAIL] ", label, "  ", detail)


func _load(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_check("open " + path, false, "FileAccess.open returned null")
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	if v == null:
		_check("parse " + path, false, "JSON.parse_string returned null")
	return v


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	var species: Variant = _load("res://data/species.json")
	var moves: Variant = _load("res://data/moves.json")
	var learnsets: Variant = _load("res://data/learnsets.json")
	var abilities: Variant = _load("res://data/abilities.json")
	var typechart: Variant = _load("res://data/typechart.json")
	var ms := Time.get_ticks_msec() - t0
	print("parsed 5 files in %d ms" % ms)

	_check("species is a 1025-entry Array",
		species is Array and species.size() == 1025,
		"got %s" % [species.size() if species is Array else typeof(species)])

	# Godot's JSON parser returns every number as float - ids must be int()-cast.
	var contiguous := true
	for i in species.size():
		if int(species[i]["id"]) != i + 1:
			contiguous = false
			break
	_check("species[i].id == i+1 for all 1025", contiguous)

	var pika: Dictionary = species[24]
	_check("species[24] is Pikachu", pika["name"] == "Pikachu", str(pika["name"]))
	_check("Pikachu stats spe == 90", int(pika["stats"]["spe"]) == 90, str(pika["stats"]))
	_check("Pikachu types == [electric]", pika["types"] == ["electric"], str(pika["types"]))
	_check("Pikachu evolves to 26 via thunder-stone",
		int(pika["evolutions"][0]["to"]) == 26
			and pika["evolutions"][0]["item"] == "thunder-stone",
		str(pika["evolutions"]))
	_check("species[1024] is Pecharunt", species[1024]["name"] == "Pecharunt",
		str(species[1024]["name"]))

	_check("moves is a non-empty Array", moves is Array and moves.size() == 919,
		"got %s" % [moves.size() if moves is Array else typeof(moves)])
	var tbolt: Dictionary = {}
	for m in moves:
		if int(m["id"]) == 85:
			tbolt = m
			break
	_check("move 85 is Thunderbolt, 90 BP, electric",
		tbolt.get("name", "") == "Thunderbolt" and int(tbolt.get("power", 0)) == 90
			and tbolt.get("type", "") == "electric", str(tbolt))
	var never_miss := 0
	for m in moves:
		if m["accuracy"] == null:
			never_miss += 1
	_check("288 moves have accuracy null (never miss)", never_miss == 288, str(never_miss))

	_check("learnsets has 1025 keys",
		learnsets is Dictionary and learnsets.size() == 1025,
		"got %s" % [learnsets.size() if learnsets is Dictionary else typeof(learnsets)])
	var pika_ls: Dictionary = learnsets["25"]
	_check("Pikachu levelUp is a non-empty [level, move] list",
		pika_ls["levelUp"].size() > 0 and pika_ls["levelUp"][0].size() == 2
			and int(pika_ls["levelUp"][0][0]) >= 1,
		str(pika_ls["levelUp"].slice(0, 3)))

	_check("abilities is a 314-entry Array",
		abilities is Array and abilities.size() == 314,
		"got %s" % [abilities.size() if abilities is Array else typeof(abilities)])
	var static_ab: Dictionary = {}
	for a in abilities:
		if int(a["id"]) == 9:
			static_ab = a
			break
	_check("ability 9 is Static / onContactHit / tier 1",
		static_ab.get("name", "") == "Static" and static_ab.get("hook", "") == "onContactHit"
			and int(static_ab.get("tier", 0)) == 1, str(static_ab))

	_check("typechart is 18x18 with Fairy",
		typechart is Dictionary and typechart.size() == 18
			and typechart.has("fairy") and (typechart["fairy"] as Dictionary).size() == 18)
	_check("dragon -> fairy == 0.0", float(typechart["dragon"]["fairy"]) == 0.0,
		str(typechart["dragon"]["fairy"]))
	_check("steel -> ghost == 1.0", float(typechart["steel"]["ghost"]) == 1.0,
		str(typechart["steel"]["ghost"]))
	_check("electric -> water == 2.0", float(typechart["electric"]["water"]) == 2.0,
		str(typechart["electric"]["water"]))

	# Every learnset move must resolve against moves.json. moves.json carries the display
	# name in `name` and the veekun slug in `slug`; learnsets reference the slug.
	var slugs := {}
	for m in moves:
		slugs[m["slug"]] = true
	var unresolved := 0
	for key in learnsets:
		for pair in learnsets[key]["levelUp"]:
			if not slugs.has(pair[1]):
				unresolved += 1
		for bucket in ["machine", "egg", "tutor"]:
			for mv in learnsets[key][bucket]:
				if not slugs.has(mv):
					unresolved += 1
	_check("every learnset move slug resolves in moves.json", unresolved == 0,
		"%d unresolved" % unresolved)

	# species.abilities / hiddenAbility reference ability slugs.
	var ab_slugs := {}
	for a in abilities:
		ab_slugs[a["slug"]] = true
	var bad_ab := 0
	for sp in species:
		for a in sp["abilities"]:
			if not ab_slugs.has(a):
				bad_ab += 1
		if sp["hiddenAbility"] != null and not ab_slugs.has(sp["hiddenAbility"]):
			bad_ab += 1
	_check("every species ability slug resolves in abilities.json", bad_ab == 0,
		"%d unresolved" % bad_ab)

	print("\n%s (%d failure(s))" % ["DATA CONTRACT OK" if failures == 0 else "FAILED", failures])
	quit(1 if failures > 0 else 0)
