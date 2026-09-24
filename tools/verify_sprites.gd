# Headless verification that the sprite build is loadable and correct from Godot.
# godot --headless --path . --script res://tools/verify_sprites.gd
extends SceneTree

func _init() -> void:
	var fails := 0
	var f := FileAccess.open("res://data/rom/sprites.json", FileAccess.READ)
	if f == null:
		print("FAIL: data/rom/sprites.json missing"); quit(1); return
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	var species: Array = m["species"]
	print("manifest species: %d  complete: %s" % [species.size(), m["counts"]["complete"]])

	var probes := [1, 25, 150, 448, 483, 493, 649, 700, 887, 1000, 1025]
	for id in probes:
		var e: Dictionary = species[id - 1]
		for key in ["front", "back", "icon"]:
			var path: String = "res://" + str(e[key])
			var img := Image.new()
			if img.load(path) != OK:
				print("FAIL: %d %s cannot load %s" % [id, key, path]); fails += 1; continue
			var want := 32 if key == "icon" else 96
			if img.get_width() != want or img.get_height() != want:
				print("FAIL: %d %s is %dx%d, want %dx%d"
					% [id, key, img.get_width(), img.get_height(), want, want]); fails += 1; continue
			var opaque := 0
			for y in range(img.get_height()):
				for x in range(img.get_width()):
					if img.get_pixel(x, y).a > 0.5:
						opaque += 1
			if opaque < 40:
				print("FAIL: %d %s only %d opaque px" % [id, key, opaque]); fails += 1
			else:
				print("ok  %4d %-5s %dx%d  %d opaque px" % [id, key, img.get_width(), img.get_height(), opaque])

	# every manifest path must exist on disk
	var missing := 0
	for e in species:
		for key in ["front", "back", "icon"]:
			if e[key] == null or not FileAccess.file_exists("res://" + str(e[key])):
				missing += 1
	print("manifest paths missing on disk: %d" % missing)
	if missing > 0:
		fails += 1
	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
