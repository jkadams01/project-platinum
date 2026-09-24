extends SceneTree
## Builds resources/outdoor_sinnoh.tres from the manifest that
## tools/build_tilesets.py wrote, IN CODE, via TileSetAtlasSource.
##
##   godot --headless --path . --import
##   godot --headless --path . --script res://tools/build_tileset_res.gd
##
## The --import pass is mandatory and must come first: it turns the atlas PNG
## into a CompressedTexture2D with a resource_path, so the saved .tres stores a
## one-line [ext_resource] instead of inlining the whole pixel buffer
## (docs/research/godot-architecture.md section 1.4, "the texture-embedding trap").
##
## Custom data layers, per the stream brief:
##     collision  : int     DATA_CONTRACT.md section 9 codes
##     encounter  : bool    wild encounters trigger on this tile
##     traversal  : String  badge-gated verb, "" when none
##
## Exit 0 = saved and re-verified. Exit 1 = anything went wrong.

const MANIFEST := "res://data/tilesets/outdoor_sinnoh.json"
const OUT := "res://resources/outdoor_sinnoh.tres"

const CUSTOM_DATA := {
	"collision": TYPE_INT,
	"encounter": TYPE_BOOL,
	"traversal": TYPE_STRING,
}

var failures := 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("  [PASS] ", label)
	else:
		failures += 1
		printerr("  [FAIL] %s  %s" % [label, detail])


func _initialize() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		printerr("no manifest at %s - run tools/build_tilesets.py first" % MANIFEST)
		quit(1)
		return
	var m: Variant = JSON.parse_string(f.get_as_text())
	if not (m is Dictionary):
		printerr("manifest did not parse as a Dictionary")
		quit(1)
		return

	var tile_size := int(m["tileSize"])
	var atlas_path: String = "res://" + String(m["atlas"])
	var tiles: Array = m["tiles"]

	# The atlas must come back as an imported CompressedTexture2D, not an
	# ImageTexture built here: see the texture-embedding trap above.
	var tex: Texture2D = load(atlas_path)
	if tex == null:
		printerr("could not load %s - did --import run?" % atlas_path)
		quit(1)
		return

	# --- 1. TileSet + tile_size -------------------------------------------
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout = TileSet.TILE_LAYOUT_STACKED
	ts.tile_size = Vector2i(tile_size, tile_size)

	# --- 2. custom data layers, BEFORE any tile writes --------------------
	for cd_name: String in CUSTOM_DATA:
		var i := ts.get_custom_data_layers_count()
		ts.add_custom_data_layer()
		ts.set_custom_data_layer_name(i, cd_name)
		ts.set_custom_data_layer_type(i, CUSTOM_DATA[cd_name])

	# --- 3. the atlas source, one tile per manifest cell -------------------
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile_size, tile_size)
	src.margins = Vector2i.ZERO
	src.separation = Vector2i.ZERO

	var grid := src.get_atlas_grid_size()
	var coords: Array[Vector2i] = []
	for t: Dictionary in tiles:
		var c := Vector2i(int(t["atlasX"]), int(t["atlasY"]))
		if c.x >= grid.x or c.y >= grid.y:
			printerr("manifest tile %s is outside the atlas grid %s" % [c, grid])
			quit(1)
			return
		src.create_tile(c)
		coords.append(c)

	# --- 4. add_source BEFORE writing custom data --------------------------
	# TileData resolves custom-data layer names through its owning TileSet.
	# Writing before add_source() silently loses the value and it reads back as
	# the type default afterwards (godot-architecture.md section 1.4).
	var source_id := ts.add_source(src, 0)

	# --- 5. now the per-tile metadata --------------------------------------
	for t: Dictionary in tiles:
		var c := Vector2i(int(t["atlasX"]), int(t["atlasY"]))
		var td := src.get_tile_data(c, 0)
		td.set_custom_data("collision", int(t["collision"]))
		td.set_custom_data("encounter", bool(t["encounter"]))
		td.set_custom_data("traversal", String(t["traversal"]))
		# Tall standing props (the White 2 32x64 trees, fences, doors, gates)
		# must y-sort by the row their base sits on, not by each cell's own
		# centre, or the player walks *through* a canopy cell and *behind* the
		# trunk cell of the same tree. Ground textures are never given an
		# origin - a 64x64 cave floor is not a standing object.
		var cat := String(t["category"])
		var cells_h := int(t["cellsH"])
		if cells_h > 1 and (cat == "tree" or cat == "building"):
			td.y_sort_origin = (cells_h - 1 - int(t["subY"])) * tile_size + tile_size / 2

	var err := ResourceSaver.save(ts, OUT)
	if err != OK:
		printerr("ResourceSaver.save -> %d" % err)
		quit(1)
		return
	print("saved %s  source_id=%d tiles=%d" % [OUT, source_id, src.get_tiles_count()])

	# --- 6. re-open it from disk and assert the data survived --------------
	var reloaded: TileSet = ResourceLoader.load(OUT, "TileSet", ResourceLoader.CACHE_MODE_IGNORE)
	_check("reloads as a TileSet", reloaded != null)
	if reloaded == null:
		quit(1)
		return
	_check("tile_size round-trips", reloaded.tile_size == Vector2i(tile_size, tile_size),
		str(reloaded.tile_size))
	_check("3 custom data layers", reloaded.get_custom_data_layers_count() == 3,
		str(reloaded.get_custom_data_layers_count()))
	var rsrc: TileSetAtlasSource = reloaded.get_source(reloaded.get_source_id(0))
	_check("atlas source present", rsrc != null)
	_check("tile count matches the manifest",
		rsrc != null and rsrc.get_tiles_count() == tiles.size(),
		"%d vs %d" % [rsrc.get_tiles_count() if rsrc else -1, tiles.size()])

	# every tile's collision code must survive the save/load, and at least one
	# tile of each interesting kind must actually exist.
	var mismatched := 0
	var n_grass := 0
	var n_water := 0
	var n_cut := 0
	for t: Dictionary in tiles:
		var c := Vector2i(int(t["atlasX"]), int(t["atlasY"]))
		var td := rsrc.get_tile_data(c, 0)
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
			n_grass += 1
		if int(t["collision"]) == 3:
			n_water += 1
		if String(t["traversal"]) == "cut":
			n_cut += 1
	_check("all %d tiles round-trip collision/encounter/traversal" % tiles.size(),
		mismatched == 0, "%d mismatches" % mismatched)
	_check("has tall-grass tiles (collision 4)", n_grass > 0, str(n_grass))
	_check("has deep-water tiles (collision 3)", n_water > 0, str(n_water))
	_check("has cut-traversal tiles (trees)", n_cut > 0, str(n_cut))

	# The .tres must reference the PNG, not inline it.
	var raw := FileAccess.get_file_as_string(OUT)
	_check(".tres references the atlas as an ext_resource",
		raw.contains("[ext_resource") and raw.contains("outdoor_sinnoh.png"))
	_check(".tres does not inline the pixel buffer",
		not raw.contains("PackedByteArray("), "sub_resource Image was embedded")

	print("tileset codegen: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
