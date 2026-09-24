extends RefCounted
## Loads `data/maps/<id>.json` (docs/DATA_CONTRACT.md 9) into a [MapData] value
## object, and -- separately -- into TileMapLayer nodes.
##
## THE SPLIT IS DELIBERATE. Parsing and rendering are two jobs:
##   * [method load_map] / [method from_dict] need no scene tree, no textures and
##     no import pass, so collision, encounters, traversal and warps are all
##     testable headlessly against real map JSON.
##   * [method build_layers] is the only part that touches nodes, and a map with
##     no tileset built yet still produces a fully playable (if invisible) map
##     rather than failing to load.
##
## TileMapLayer, never TileMap. Godot 4.3 deprecated the monolithic TileMap and
## its `set_cell(layer, ...)` signature; 4.7.2 still instantiates it purely so old
## projects open (docs/research/godot-architecture.md 1.1). One node per layer.
##
## FALLBACK, same policy as DataRegistry: `data/maps/` is generated from the
## owner's ROM and is gitignored, so a fresh checkout has none. Missing maps fall
## back to `tests/fixtures/maps/`, which holds hand-authored (non-ROM-derived)
## maps that are safe to commit. [member MapData.source] records which won.

const MAP_DIR := "res://data/maps"
const FIXTURE_MAP_DIR := "res://tests/fixtures/maps"
const TILESET_DIR := "res://data/tilesets"
const RESOURCE_DIR := "res://resources"

const TILE := 16

## Layer name -> z_index. Matches the scene layout in
## docs/research/godot-architecture.md 1.2: ground below everything, overlay just
## under the entities, `above` drawn over the player's head.
const LAYER_Z: Dictionary = {
	"ground": -10,
	"overlay": -5,
	"above": 10,
}
const LAYER_ORDER: Array = ["ground", "overlay", "above"]


## One parsed map. Plain data: no nodes, no textures, no tree.
class MapData extends RefCounted:
	var id: StringName = &""
	var name: String = ""
	var width: int = 0
	var height: int = 0
	var tile_size: int = 16
	var tileset: String = ""
	var encounter_zone: StringName = &""
	## "data" | "fixture" | "inline"
	var source: String = "inline"

	## name -> PackedInt32Array, row-major, length width*height. -1 = empty.
	var layers: Dictionary = {}
	## row-major, length width*height. See Collision's code enum.
	var collision: PackedInt32Array = PackedInt32Array()
	## Vector2i -> {"x","y","type","requires"}
	var traversal: Dictionary = {}
	## Vector2i -> {"x","y","to","toX","toY"}
	var warps: Dictionary = {}
	## direction name ("north"/"south"/"east"/"west") -> map id
	var connections: Dictionary = {}
	## Optional lateral shift applied when crossing a seam, keyed by edge name.
	var connection_offsets: Dictionary = {}
	var objects: Array = []

	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

	## Collision code at [param cell]. Out of bounds reads as BLOCK(1) so every
	## caller that forgets to bounds-check fails closed instead of indexing past
	## the array. resolve() checks bounds first and returns EDGE before reaching
	## this, so the two are not in conflict.
	func code_at(cell: Vector2i) -> int:
		if not in_bounds(cell):
			return 1
		var i: int = cell.y * width + cell.x
		if i < 0 or i >= collision.size():
			return 1
		return collision[i]

	## Tile index on [param layer_name] at [param cell]; -1 for empty/missing.
	func tile_at(layer_name: String, cell: Vector2i) -> int:
		if not in_bounds(cell) or not layers.has(layer_name):
			return -1
		var arr: PackedInt32Array = layers[layer_name]
		var i: int = cell.y * width + cell.x
		return arr[i] if i >= 0 and i < arr.size() else -1

	## The traversal obstacle standing on [param cell], or {}.
	func traversal_at(cell: Vector2i) -> Dictionary:
		return traversal.get(cell, {})

	func warp_at(cell: Vector2i) -> Dictionary:
		return warps.get(cell, {})

	func connection(dir_name: String) -> String:
		return String(connections.get(dir_name, ""))

	func cell_count() -> int:
		return width * height

	func _to_string() -> String:
		return "<MapData %s %dx%d src=%s>" % [id, width, height, source]


## Reads `data/maps/<map_id>.json`, falling back to the committed fixture maps.
## Returns null when neither exists or the JSON is malformed -- callers must
## check, because a missing map is a content bug, not something to paper over.
static func load_map(map_id: String, dir_path: String = MAP_DIR) -> MapData:
	var primary := dir_path.path_join("%s.json" % map_id)
	var parsed: Variant = _parse(primary)
	var src := "fixture" if dir_path == FIXTURE_MAP_DIR else "data"
	if parsed == null and dir_path != FIXTURE_MAP_DIR:
		parsed = _parse(FIXTURE_MAP_DIR.path_join("%s.json" % map_id))
		src = "fixture"
		if parsed != null:
			_log("warn", "%s missing -> using fixture map" % primary)
	if parsed == null:
		_log("error", "no map JSON for '%s' (looked in %s and %s)" % [
			map_id, dir_path, FIXTURE_MAP_DIR])
		return null
	if not (parsed is Dictionary):
		_log("error", "%s: a map must be a JSON object" % primary)
		return null
	var m := from_dict(parsed)
	if m != null:
		m.source = src
		if String(m.id).is_empty():
			m.id = StringName(map_id)
	return m


## Parses a contract-shaped map dictionary. Returns null on a shape error, and
## says which field was wrong -- silently producing a 0x0 map would surface hours
## later as "the player cannot move".
static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.id = StringName(String(d.get("id", "")))
	m.name = String(d.get("name", String(m.id)))
	m.width = int(d.get("width", 0))
	m.height = int(d.get("height", 0))
	m.tile_size = int(d.get("tileSize", TILE))
	m.tileset = String(d.get("tileset", ""))
	m.encounter_zone = StringName(String(d.get("encounterZone", String(m.id))))

	if m.width <= 0 or m.height <= 0:
		_log("error", "map '%s' has a degenerate size %dx%d" % [m.id, m.width, m.height])
		return null

	var cells := m.width * m.height

	var raw_layers: Dictionary = d.get("layers", {})
	for layer_name: String in LAYER_ORDER:
		var flat := _flatten(raw_layers.get(layer_name, []), m.width, m.height, -1)
		if flat.size() != cells:
			_log("warn", "map '%s' layer '%s' has %d cells, expected %d" % [
				m.id, layer_name, flat.size(), cells])
		m.layers[layer_name] = flat

	if not _grid_matches(d.get("collision", []), m.width, m.height):
		_log("error", "map '%s' collision grid does not match the declared %dx%d" % [
			m.id, m.width, m.height])
		return null
	m.collision = _flatten(d.get("collision", []), m.width, m.height, 0)
	if m.collision.size() != cells:
		_log("error", "map '%s' collision grid is %d cells, expected %d (%dx%d)" % [
			m.id, m.collision.size(), cells, m.width, m.height])
		return null

	for entry: Variant in (d.get("traversal", []) as Array):
		if not (entry is Dictionary):
			continue
		var t: Dictionary = (entry as Dictionary).duplicate(true)
		var cell := Vector2i(int(t.get("x", 0)), int(t.get("y", 0)))
		t["x"] = cell.x
		t["y"] = cell.y
		t["type"] = String(t.get("type", ""))
		t["requires"] = String(t.get("requires", ""))
		if String(t["type"]) == "defog":
			# Fog is deleted from this build (game-design.md 3.4). Loudly.
			_log("error", "map '%s' has a defog obstacle at %s; there is no defog verb" % [m.id, cell])
			continue
		m.traversal[cell] = t

	for entry: Variant in (d.get("warps", []) as Array):
		if not (entry is Dictionary):
			continue
		var w: Dictionary = (entry as Dictionary).duplicate(true)
		var cell2 := Vector2i(int(w.get("x", 0)), int(w.get("y", 0)))
		w["x"] = cell2.x
		w["y"] = cell2.y
		w["to"] = String(w.get("to", ""))
		w["toX"] = int(w.get("toX", 0))
		w["toY"] = int(w.get("toY", 0))
		m.warps[cell2] = w

	for k: Variant in (d.get("connections", {}) as Dictionary):
		m.connections[String(k)] = String((d["connections"] as Dictionary)[k])
	for k: Variant in (d.get("connectionOffsets", {}) as Dictionary):
		m.connection_offsets[String(k)] = int((d["connectionOffsets"] as Dictionary)[k])

	m.objects = (d.get("objects", []) as Array).duplicate(true)
	return m


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

## Creates the three TileMapLayer nodes under [param parent] and paints them.
## Returns the layers by name. [param tile_set] may be null -- the nodes are
## still created (so the scene shape is stable) and simply stay empty.
##
## Y-SORT (godot-architecture.md 1.3): a layer's `y_sort_enabled` does nothing
## unless every ancestor up to the sorting root also has it. Parent gets it too.
static func build_layers(map: MapData, parent: Node2D, tile_set: TileSet = null) -> Dictionary:
	parent.y_sort_enabled = true
	var out: Dictionary = {}
	for layer_name: String in LAYER_ORDER:
		var layer := TileMapLayer.new()
		layer.name = layer_name.capitalize()
		layer.z_index = int(LAYER_Z[layer_name])
		layer.y_sort_enabled = (layer_name == "overlay")
		layer.tile_set = tile_set
		parent.add_child(layer)
		out[layer_name] = layer
		if tile_set != null:
			paint(layer, map, layer_name, tile_set)
	return out


## Writes one layer's tile indices onto a TileMapLayer. A linear tile index is
## turned into atlas coordinates with the tileset's own column count, which is
## why `columns` is part of the tileset contract (DATA_CONTRACT 10).
static func paint(layer: TileMapLayer, map: MapData, layer_name: String, tile_set: TileSet,
		source_id: int = 0) -> int:
	var src := tile_set.get_source(source_id) as TileSetAtlasSource
	if src == null:
		_log("error", "tileset has no atlas source %d" % source_id)
		return 0
	var grid := src.get_atlas_grid_size()
	var painted := 0
	for y in map.height:
		for x in map.width:
			var idx := map.tile_at(layer_name, Vector2i(x, y))
			if idx < 0:
				continue
			var coords := Vector2i(idx % grid.x, idx / grid.x)
			if coords.y >= grid.y or not src.has_tile(coords):
				continue
			layer.set_cell(Vector2i(x, y), source_id, coords)
			painted += 1
	return painted


## The TileSet for a named tileset.
##
## An AUTHORED `res://resources/<name>.tres` wins whenever one exists: it carries
## the custom-data layers, terrain sets and per-tile collision polygons that the
## tileset pipeline writes, none of which can be recovered from the atlas PNG.
## Only when there is none do we synthesise a bare atlas source from
## `data/tilesets/<name>.json` + the PNG, so a map still renders in a checkout
## where the tileset build has not run.
static func make_tileset(tileset_name: String, dir_path: String = TILESET_DIR) -> TileSet:
	var authored := RESOURCE_DIR.path_join("%s.tres" % tileset_name)
	if ResourceLoader.exists(authored):
		var res: Resource = ResourceLoader.load(authored)
		if res is TileSet:
			_log("info", "tileset '%s': loaded the authored %s" % [tileset_name, authored])
			return res
		_log("warn", "%s is not a TileSet; synthesising one instead" % authored)
	return synthesize_tileset(tileset_name, dir_path)


## Builds a bare TileSet from `data/tilesets/<name>.json` + its atlas PNG.
##
## The texture is fetched with `load()` first (an imported CompressedTexture2D),
## and only falls back to Image+ImageTexture when there is no import pass -- see
## godot-architecture.md 1.4 for why an ImageTexture is the wrong thing to put in
## a resource you SAVE. Nothing here is saved, so the fallback is safe.
static func synthesize_tileset(tileset_name: String, dir_path: String = TILESET_DIR) -> TileSet:
	var meta: Variant = _parse(dir_path.path_join("%s.json" % tileset_name))
	if meta == null or not (meta is Dictionary):
		_log("warn", "no tileset metadata for '%s'; maps will load unpainted" % tileset_name)
		return null
	var d: Dictionary = meta
	var tile := int(d.get("tileSize", TILE))
	var atlas_path := String(d.get("atlas", ""))
	if not atlas_path.begins_with("res://"):
		atlas_path = "res://" + atlas_path
	var tex := _load_texture(atlas_path)
	if tex == null:
		_log("warn", "tileset atlas '%s' is not present; maps will load unpainted" % atlas_path)
		return null

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout = TileSet.TILE_LAYOUT_STACKED
	ts.tile_size = Vector2i(tile, tile)

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile, tile)
	var grid := src.get_atlas_grid_size()
	var declared := int(d.get("tileCount", grid.x * grid.y))
	var made := 0
	for y in grid.y:
		for x in grid.x:
			if made >= declared:
				break
			src.create_tile(Vector2i(x, y))
			made += 1
	ts.add_source(src, 0)
	_log("info", "tileset '%s': %d tiles from %s (%dx%d atlas)" % [
		tileset_name, made, atlas_path, grid.x, grid.y])
	return ts


# --------------------------------------------------------------------------

static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = ResourceLoader.load(path)
		if res is Texture2D:
			return res
	# No import pass (fresh checkout, CI container): read the PNG directly.
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return ImageTexture.create_from_image(img)


## True when [param raw] really is a width x height grid (or a flat array of
## exactly width*height). [method _flatten] pads a short grid, which is right for
## a decorative tile layer and WRONG for the collision grid: padding a short
## collision grid with 0 would silently make the missing region walkable.
static func _grid_matches(raw: Variant, width: int, height: int) -> bool:
	if not (raw is Array):
		return false
	var arr: Array = raw
	if arr.is_empty():
		return false
	if not (arr[0] is Array):
		return arr.size() == width * height
	if arr.size() != height:
		return false
	for row: Variant in arr:
		if not (row is Array) or (row as Array).size() != width:
			return false
	return true


## Accepts either the contract's `[[row], [row]]` or an already-flat array, and
## always returns exactly width*height entries when the input is well-formed.
static func _flatten(raw: Variant, width: int, height: int, fill: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not (raw is Array):
		return out
	var arr: Array = raw
	if arr.is_empty():
		return out
	if arr[0] is Array:
		out.resize(width * height)
		out.fill(fill)
		for y in mini(arr.size(), height):
			var row: Array = arr[y]
			for x in mini(row.size(), width):
				out[y * width + x] = int(row[x])
		return out
	for v: Variant in arr:
		out.append(int(v))
	return out


static func _parse(path: String) -> Variant:
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


static func _log(level: String, message: String) -> void:
	match level:
		"error": Log.error(message, "MapLoader")
		"warn": Log.warn(message, "MapLoader")
		_: Log.info(message, "MapLoader")
