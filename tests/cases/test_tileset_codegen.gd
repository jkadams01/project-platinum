extends "res://tests/framework/test_case.gd"
## Guards the generated outdoor_sinnoh tileset and its manifest.
##
## Both inputs are ROM-derived and gitignored, so in a fresh checkout every
## check here is PENDING rather than a failure. Build them first with:
##     source tools/_work/gen5/env.sh && python tools/build_tilesets.py
##
## What this actually protects:
##  * the manifest keeps the shape DATA_CONTRACT.md section 10 promises;
##  * every tile's provenance is one of the three decided sources, and only
##    White 2 tiles carry the HSV lift flag;
##  * the .tres declares the three custom data layers with the right TYPES;
##  * custom data actually survived the save (the add_source ordering trap in
##    godot-architecture.md section 1.4 fails SILENTLY, reading back as the
##    type default, so this is the only thing that catches it);
##  * the .tres references the atlas PNG instead of inlining its pixels.

const MANIFEST := "res://data/tilesets/outdoor_sinnoh.json"
const TRES := "res://resources/outdoor_sinnoh.tres"
const ATLAS := "res://assets/generated/tilesets/outdoor_sinnoh.png"
const SOURCES := ["platinum", "white2", "heartgold"]
const TILE := 16


func _manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return v if v is Dictionary else {}


func test_manifest_shape() -> void:
	var m := _manifest()
	if m.is_empty():
		pending("%s not built - run tools/build_tilesets.py" % MANIFEST)
		return
	eq(String(m.get("name", "")), "outdoor_sinnoh", "manifest name")
	eq(int(m.get("tileSize", 0)), TILE, "tileSize")
	eq(int(m.get("columns", 0)), 32, "columns")
	has_key(m, "atlas", "manifest")
	has_key(m, "tiles", "manifest")
	var tiles: Array = m.get("tiles", [])
	is_true(tiles.size() > 0, "manifest lists at least one tile")

	var bad_source := 0
	var bad_collision := 0
	var bad_lift := 0
	var bad_index := 0
	var seen_index := {}
	var cols := int(m["columns"])
	for t: Dictionary in tiles:
		if not SOURCES.has(String(t.get("source", ""))):
			bad_source += 1
		var c := int(t.get("collision", -1))
		if c < 0 or c > 7:
			bad_collision += 1
		# provenance: the HSV lift is applied to White 2 assets and nothing else
		if bool(t.get("hsvLift", false)) != (String(t["source"]) == "white2"):
			bad_lift += 1
		var idx := int(t["atlasY"]) * cols + int(t["atlasX"])
		if idx != int(t["index"]) or seen_index.has(idx):
			bad_index += 1
		seen_index[idx] = true
	eq(bad_source, 0, "every tile has a known source")
	eq(bad_collision, 0, "every collision code is in 0..7 (DATA_CONTRACT section 9)")
	eq(bad_lift, 0, "hsvLift is set for White 2 tiles and only those")
	eq(bad_index, 0, "index == atlasY*columns + atlasX, and is unique")


func test_tileset_resource() -> void:
	var m := _manifest()
	if m.is_empty() or not ResourceLoader.exists(TRES):
		pending("%s not built - run tools/build_tilesets.py" % TRES)
		return
	var ts: TileSet = ResourceLoader.load(TRES, "TileSet", ResourceLoader.CACHE_MODE_IGNORE)
	if ts == null:
		fail("%s did not load as a TileSet" % TRES)
		return
	eq(ts.tile_size, Vector2i(TILE, TILE), "tile_size")

	# custom data layers: names AND types, in the order the contract names them
	var want := {"collision": TYPE_INT, "encounter": TYPE_BOOL, "traversal": TYPE_STRING}
	eq(ts.get_custom_data_layers_count(), want.size(), "custom data layer count")
	for i in ts.get_custom_data_layers_count():
		var n := ts.get_custom_data_layer_name(i)
		if not want.has(n):
			fail("unexpected custom data layer '%s'" % n)
			continue
		eq(ts.get_custom_data_layer_type(i), want[n], "layer '%s' type" % n)

	var src: TileSetAtlasSource = ts.get_source(ts.get_source_id(0))
	if src == null:
		fail("no TileSetAtlasSource on the tileset")
		return
	var tiles: Array = m["tiles"]
	eq(src.get_tiles_count(), tiles.size(), "tile count matches the manifest")

	# The ordering trap: a custom_data write before add_source() is lost and
	# reads back as the TYPE DEFAULT, so a silently-broken tileset looks fine
	# structurally and has every flag false / every string empty. Compare every
	# tile against the manifest rather than spot-checking.
	var mismatched := 0
	var grass := 0
	var water := 0
	var cut := 0
	for t: Dictionary in tiles:
		var td := src.get_tile_data(Vector2i(int(t["atlasX"]), int(t["atlasY"])), 0)
		if td == null:
			mismatched += 1
			continue
		if int(td.get_custom_data("collision")) != int(t["collision"]):
			mismatched += 1
		if bool(td.get_custom_data("encounter")) != bool(t["encounter"]):
			mismatched += 1
		if String(td.get_custom_data("traversal")) != String(t["traversal"]):
			mismatched += 1
		if int(t["collision"]) == 4:
			grass += 1
		if int(t["collision"]) == 3:
			water += 1
		if String(t["traversal"]) == "cut":
			cut += 1
	eq(mismatched, 0, "custom data survived the save for all %d tiles" % tiles.size())
	is_true(grass > 0, "tileset has tall-grass tiles (collision 4)")
	is_true(water > 0, "tileset has deep-water tiles (collision 3)")
	is_true(cut > 0, "tileset has cut-traversal tiles (the White 2 trees)")


func test_atlas_is_referenced_not_embedded() -> void:
	if not FileAccess.file_exists(TRES):
		pending("%s not built - run tools/build_tilesets.py" % TRES)
		return
	var raw := FileAccess.get_file_as_string(TRES)
	is_true(raw.contains("[ext_resource"), ".tres references the atlas as an ext_resource")
	is_true(raw.contains("outdoor_sinnoh.png"), ".tres names the atlas PNG")
	# ImageTexture.create_from_image() has no resource_path, so ResourceSaver
	# inlines the whole pixel buffer (~180x bigger). Catch a regression to it.
	is_false(raw.contains("PackedByteArray("), ".tres does not inline the pixel buffer")


func test_atlas_png_is_power_of_two() -> void:
	var m := _manifest()
	if m.is_empty() or not FileAccess.file_exists(ATLAS):
		pending("%s not built - run tools/build_tilesets.py" % ATLAS)
		return
	var img := Image.new()
	eq(img.load(ATLAS), OK, "atlas PNG loads")
	var w := img.get_width()
	var h := img.get_height()
	is_true(w > 0 and (w & (w - 1)) == 0, "atlas width %d is a power of two" % w)
	is_true(h > 0 and (h & (h - 1)) == 0, "atlas height %d is a power of two" % h)
	eq(w, int(m["columns"]) * TILE, "atlas width == columns * tileSize")
	is_true(img.has_mipmaps() == false, "atlas has no mipmaps")
