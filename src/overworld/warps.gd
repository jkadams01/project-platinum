extends RefCounted
## Map-to-map travel: doors/stairs (`warps`) and walked-off-the-edge route
## seams (`connections`). Both from docs/DATA_CONTRACT.md 9.
##
## TWO DIFFERENT THINGS, ON PURPOSE.
##   * A WARP is a point-to-point teleport declared on a tile:
##     `{"x":20,"y":0,"to":"sandgem_town","toX":15,"toY":29}`. The destination
##     cell is authored, so it is exact. Doors, cave mouths, stairs.
##   * A CONNECTION is a seam: `{"north":"sandgem_town"}`. No destination cell is
##     authored, because the two maps are meant to read as one continuous route.
##     The arrival cell is DERIVED -- you come out of the opposite edge at the
##     same lateral offset you left at ([method arrival_cell]).
##
## Deriving the connection cell rather than authoring it is what keeps a route
## seam from drifting when a map is resized: only the edge you left from and the
## destination's own dimensions are involved, so there is no third number to keep
## in sync and get wrong.

const MapLoader := preload("res://src/overworld/map_loader.gd")

## Facing -> the edge name used in a map's `connections` object.
const DIR_NAME: Dictionary = {
	Vector2i.UP: "north",
	Vector2i.DOWN: "south",
	Vector2i.LEFT: "west",
	Vector2i.RIGHT: "east",
}

const OPPOSITE: Dictionary = {
	"north": "south",
	"south": "north",
	"east": "west",
	"west": "east",
}


static func dir_name(dir: Vector2i) -> String:
	return String(DIR_NAME.get(dir, ""))


## The warp declared on [param cell], or {}. Call after a step lands.
static func warp_at(map: Object, cell: Vector2i) -> Dictionary:
	return map.warp_at(cell)


## Resolves a step that left the map. Returns {} when there is no connection that
## way -- which means the edge is simply solid and the player bumps.
##
## The result is warp-shaped so callers only ever handle one kind of thing:
##   {"to": String, "toX": int, "toY": int, "reason": "connection", "edge": String}
static func resolve_edge(map: Object, from: Vector2i, dir: Vector2i,
		map_dir: String = MapLoader.MAP_DIR) -> Dictionary:
	var edge := dir_name(dir)
	if edge.is_empty():
		return {}
	var to_id: String = map.connection(edge)
	if to_id.is_empty():
		return {}
	var dest := MapLoader.load_map(to_id, map_dir)
	if dest == null:
		Log.error("map '%s' connects %s to '%s', which does not exist" % [map.id, edge, to_id],
			"Warps")
		return {}
	var cell := arrival_cell(map, dest, edge, from)
	return {
		"to": to_id,
		"toX": cell.x,
		"toY": cell.y,
		"reason": "connection",
		"edge": edge,
	}


## Where you come out when you leave [param from_map] across its [param edge] at
## [param exit_cell]. You appear on the destination's OPPOSITE edge, at the same
## lateral offset, clamped into the destination's bounds.
##
## An optional `connectionOffsets: {"north": 3}` on the source map shifts that
## lateral offset, for the (common) case of two maps whose shared seam is not
## aligned at 0.
static func arrival_cell(from_map: Object, to_map: Object, edge: String,
		exit_cell: Vector2i) -> Vector2i:
	var shift := int(from_map.connection_offsets.get(edge, 0))

	match edge:
		"north":
			return Vector2i(clampi(exit_cell.x + shift, 0, to_map.width - 1), to_map.height - 1)
		"south":
			return Vector2i(clampi(exit_cell.x + shift, 0, to_map.width - 1), 0)
		"west":
			return Vector2i(to_map.width - 1, clampi(exit_cell.y + shift, 0, to_map.height - 1))
		"east":
			return Vector2i(0, clampi(exit_cell.y + shift, 0, to_map.height - 1))
	return Vector2i.ZERO


## Sanity check a warp before travelling: the destination map must exist and the
## arrival cell must be inside it and standable. Returns "" when it is fine, or
## the reason it is not. Content bugs here are the ones that strand a player.
static func validate(warp: Dictionary, map_dir: String = MapLoader.MAP_DIR) -> String:
	var to_id := String(warp.get("to", ""))
	if to_id.is_empty():
		return "warp has no destination"
	var dest := MapLoader.load_map(to_id, map_dir)
	if dest == null:
		return "destination map '%s' does not exist" % to_id
	var cell := Vector2i(int(warp.get("toX", 0)), int(warp.get("toY", 0)))
	if not dest.in_bounds(cell):
		return "arrival %s is outside '%s' (%dx%d)" % [cell, to_id, dest.width, dest.height]
	if dest.code_at(cell) == 1:
		return "arrival %s in '%s' is a blocked tile" % [cell, to_id]
	return ""


## Commits a warp to GameState and announces it. Returns false and changes
## nothing when [method validate] rejects it, so a bad warp is a stuck door
## rather than a player stranded inside a wall.
static func apply(warp: Dictionary, map_dir: String = MapLoader.MAP_DIR) -> bool:
	var why := validate(warp, map_dir)
	if not why.is_empty():
		Log.error("refusing warp: %s" % why, "Warps")
		return false
	var to_id := StringName(String(warp["to"]))
	var cell := Vector2i(int(warp.get("toX", 0)), int(warp.get("toY", 0)))
	GameState.current_map = to_id
	GameState.player_cell = cell
	EventBus.map_changed.emit(to_id, cell)
	Log.info("warp -> %s at %s (%s)" % [to_id, cell, warp.get("reason", "warp")], "Warps")
	return true
