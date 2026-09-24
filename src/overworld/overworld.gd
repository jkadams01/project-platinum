extends Node2D
## The overworld root: one node that owns a loaded map, the player, and the four
## rule systems, and wires them to each other.
##
## Nothing in here contains a rule. Collision decides what a step means,
## Traversal applies badge verbs, Encounters rolls wild Pokemon, Warps moves
## between maps; this file only routes between them and owns the nodes. That is
## why all four are unit-testable without ever instancing this scene.
##
## Scene shape follows docs/research/godot-architecture.md 1.2:
##   Overworld (this, y_sort_enabled)
##   |-- Ground   TileMapLayer  z -10
##   |-- Overlay  TileMapLayer  z  -5   y_sort_enabled
##   |-- Above    TileMapLayer  z  10
##   +-- Entities Node2D        y_sort_enabled
##       +-- Player

const MapLoader := preload("res://src/overworld/map_loader.gd")
const PlayerScript := preload("res://src/overworld/player.gd")
const Warps := preload("res://src/overworld/warps.gd")
const Collision := preload("res://src/systems/collision.gd")
const Traversal := preload("res://src/systems/traversal.gd")
const Encounters := preload("res://src/systems/encounters.gd")

signal map_ready(map_id: StringName)
signal encounter(details: Dictionary)

var map: MapLoader.MapData = null
var player: Node2D = null
var traversal := Traversal.new()
var encounters := Encounters.new()

## Where map JSON is read from. Tests point it at the fixture directory.
var map_dir: String = MapLoader.MAP_DIR
## Set false in tests that do not want TileMapLayer nodes or a texture load.
var render: bool = true

var _layers: Dictionary = {}
var _entities: Node2D = null
var _tilesets: Dictionary = {}      # tileset name -> TileSet


func _ready() -> void:
	y_sort_enabled = true
	encounters.boot()


## Loads a map and places the player. Returns false when the map does not exist,
## leaving whatever was loaded before untouched.
func load_map(map_id: String, spawn: Vector2i = Vector2i(-1, -1)) -> bool:
	var m := MapLoader.load_map(map_id, map_dir)
	if m == null:
		return false

	for c in get_children():
		c.queue_free()
	_layers.clear()
	_entities = null
	player = null

	map = m
	traversal.on_map_loaded(m.id)     # obstacles respawn, exactly as in vanilla

	if render:
		var ts := _tileset_for(m.tileset)
		_layers = MapLoader.build_layers(m, self, ts)

	_entities = Node2D.new()
	_entities.name = "Entities"
	_entities.y_sort_enabled = true
	add_child(_entities)

	player = PlayerScript.new()
	player.name = "Player"
	player.resolver = _resolve_step
	player.on_arrive = _on_arrive
	_entities.add_child(player)

	var start := spawn if spawn.x >= 0 else GameState.player_cell
	if not m.in_bounds(start):
		start = Vector2i.ZERO
	player.snap_to(start)
	player.facing = GameState.player_facing

	GameState.current_map = m.id
	GameState.player_cell = start
	EventBus.map_changed.emit(m.id, start)
	map_ready.emit(m.id)
	Log.info("loaded %s (%s) %dx%d, spawn %s" % [m.id, m.source, m.width, m.height, start],
		"Overworld")
	return true


func layer(layer_name: String) -> TileMapLayer:
	return _layers.get(layer_name, null)


func surfing() -> bool:
	return traversal.surfing


# --------------------------------------------------------------------------

## Player -> rules. Every step in the game comes through here.
func _resolve_step(from: Vector2i, dir: Vector2i) -> Dictionary:
	var res := traversal.attempt(map, from, dir)
	if int(res["kind"]) == Collision.Result.EDGE:
		# Off the map: a connection makes it a warp, otherwise it is a bump.
		var seam := Warps.resolve_edge(map, from, dir, map_dir)
		if not seam.is_empty():
			call_deferred("_travel", seam)
	return res


## Player -> the world reacting. Runs once per landed step.
func _on_arrive(at: Vector2i, _step: Dictionary) -> void:
	var w := map.warp_at(at)
	if not w.is_empty():
		call_deferred("_travel", w)
		return
	var roll := encounters.step(map.code_at(at), String(map.encounter_zone))
	if not roll.is_empty():
		Log.info("wild %s L%d (%s, %s)" % [roll["species"], roll["level"], roll["zone"],
			roll["source"]], "Overworld")
		encounter.emit(roll)


func _travel(w: Dictionary) -> void:
	if not Warps.apply(w, map_dir):
		return
	# Warping always puts you back on your feet; nothing in Sinnoh warps you
	# from water to water, and staying mounted on dry land is the bug this
	# prevents.
	traversal.dismount()
	encounters.notify_battle_ended()
	load_map(String(w["to"]), Vector2i(int(w["toX"]), int(w["toY"])))


func _tileset_for(tileset_name: String) -> TileSet:
	if tileset_name.is_empty():
		return null
	if not _tilesets.has(tileset_name):
		_tilesets[tileset_name] = MapLoader.make_tileset(tileset_name)
	return _tilesets[tileset_name]
