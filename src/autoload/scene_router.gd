extends Node
## Owns the overworld <-> battle transition.
##
## THE OVERWORLD IS SUSPENDED, NEVER SWITCHED AWAY FROM.
## `SceneTree.change_scene_to_*` frees the outgoing scene, so every NPC position,
## opened door, pushed boulder and cutscene step would have to be serialised and
## restored by hand -- and it is deferred, so `get_tree().current_scene` is still
## null on the line after the call (docs/research/godot-architecture.md 4.1).
##
## Instead one persistent root holds two slots:
##
##   Main (Node)
##   |-- WorldHolder   <- the map; process_mode = DISABLED during a battle
##   |-- BattleHolder  <- empty except during a battle
##   |-- UILayer
##   +-- TransitionLayer
##
## Suspending with `PROCESS_MODE_DISABLED` + hide leaves the map fully in the
## tree with every node, signal connection and piece of state intact, so
## returning from a battle is instant and there is no restore code to get wrong.
##
## Main calls [method register] once at boot. Until it does, the router logs and
## no-ops rather than crashing, which is what lets headless tests drive it with
## plain `Node`s standing in for the real holders.

enum Mode { BOOT, OVERWORLD, BATTLE }

const MAP_SCENE_FMT := "res://scenes/maps/%s.tscn"
## There is exactly one battle scene and it sits at the top of `scenes/`. Maps do
## NOT get scenes -- they are `data/maps/*.json` (DATA_CONTRACT 9), built into
## TileMapLayers by `Overworld.load_map()` -- so `scenes/` never grew the `battle/`
## and `maps/` subdirectories this path was originally guessing at.
const DEFAULT_BATTLE_SCENE := "res://scenes/Battle.tscn"

## Where the battle scene is loaded from when [method enter_battle] is not given
## an explicit PackedScene.
var battle_scene_path: String = DEFAULT_BATTLE_SCENE

var mode: Mode = Mode.BOOT

var _world: Node = null
var _battle: Node = null
var _ui: Node = null
## Optional. Anything exposing `play_in(kind)` / `play_out(kind)`; both may be
## coroutines. Left null in tests and in headless runs.
var _transition: Object = null

var _active_battle: Node = null


## Called once by Main. `transition` is optional.
func register(world: Node, battle_holder: Node, ui: Node = null, transition: Object = null) -> void:
	_world = world
	_battle = battle_holder
	_ui = ui
	_transition = transition
	mode = Mode.OVERWORLD
	Log.info("registered holders world=%s battle=%s" % [
		world.name if world else "<null>", battle_holder.name if battle_holder else "<null>"],
		"SceneRouter")


func is_registered() -> bool:
	return is_instance_valid(_world) and is_instance_valid(_battle)


func world_holder() -> Node:
	return _world


func battle_holder() -> Node:
	return _battle


func ui_layer() -> Node:
	return _ui


func in_battle() -> bool:
	return mode == Mode.BATTLE


func active_battle() -> Node:
	return _active_battle


func world_suspended() -> bool:
	return is_instance_valid(_world) and _world.process_mode == Node.PROCESS_MODE_DISABLED


# --------------------------------------------------------------------------
# Battle
# --------------------------------------------------------------------------

## Suspend the overworld and bring up a battle. `setup` travels straight through
## to the battle scene's `setup()` method if it has one, and is echoed on
## `EventBus.battle_started`. Pass `scene` to inject one in a test.
## Returns false if the router is unregistered, a battle is already running, or
## the battle scene could not be loaded -- and in every one of those cases the
## overworld is left exactly as it was.
func enter_battle(setup: Dictionary, scene: PackedScene = null) -> bool:
	if not is_registered():
		Log.error("enter_battle before register()", "SceneRouter")
		return false
	if mode == Mode.BATTLE:
		Log.error("enter_battle while already in a battle", "SceneRouter")
		return false

	var packed := scene
	if packed == null:
		if not ResourceLoader.exists(battle_scene_path):
			Log.error("battle scene %s does not exist" % battle_scene_path, "SceneRouter")
			return false
		packed = load(battle_scene_path) as PackedScene
	if packed == null:
		Log.error("could not load a battle scene", "SceneRouter")
		return false

	var instance := packed.instantiate()
	if instance == null:
		Log.error("battle scene failed to instantiate", "SceneRouter")
		return false

	_suspend_world()
	_battle.add_child(instance)
	_active_battle = instance
	mode = Mode.BATTLE

	var enriched := setup.duplicate(true)
	if not enriched.has("cap"):
		enriched["cap"] = GameState.current_level_cap()
	if instance.has_method("setup"):
		instance.call("setup", enriched)

	GameState.input_locked = true
	Log.info("battle started (%s)" % String(enriched.get("kind", "wild")), "SceneRouter")
	EventBus.battle_started.emit(enriched)
	return true


## Tear the battle down and resume the overworld exactly where it was.
## Returns false if no battle is running.
func exit_battle(result: Dictionary = {}) -> bool:
	if mode != Mode.BATTLE:
		Log.error("exit_battle with no battle running", "SceneRouter")
		return false

	# remove_child before queue_free so the holder is empty on the very next
	# line -- queue_free alone defers to the end of the frame, and a caller that
	# starts another battle immediately would otherwise stack two battle scenes.
	for c: Node in _battle.get_children():
		_battle.remove_child(c)
		c.queue_free()
	_active_battle = null

	_resume_world()
	mode = Mode.OVERWORLD
	GameState.input_locked = false
	Log.info("battle ended (%s)" % String(result.get("outcome", "?")), "SceneRouter")
	EventBus.battle_ended.emit(result)
	return true


func _suspend_world() -> void:
	if not is_instance_valid(_world):
		return
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	if _world is CanvasItem:
		(_world as CanvasItem).visible = false


func _resume_world() -> void:
	if not is_instance_valid(_world):
		return
	if _world is CanvasItem:
		(_world as CanvasItem).visible = true
	_world.process_mode = Node.PROCESS_MODE_INHERIT


# --------------------------------------------------------------------------
# Maps
# --------------------------------------------------------------------------

## Swap the map in WorldHolder. Returns false when the map scene does not exist
## yet (the overworld stream owns `scenes/maps/`), leaving GameState untouched so
## a bad warp cannot strand the player in a half-changed state.
func load_map(map_id: StringName, spawn: Vector2i) -> bool:
	if not is_registered():
		Log.error("load_map before register()", "SceneRouter")
		return false
	var path := MAP_SCENE_FMT % String(map_id)
	if not ResourceLoader.exists(path):
		Log.error("map scene %s does not exist" % path, "SceneRouter")
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		Log.error("map scene %s failed to load" % path, "SceneRouter")
		return false

	for c: Node in _world.get_children():
		_world.remove_child(c)
		c.queue_free()
	var m := packed.instantiate()
	_world.add_child(m)

	GameState.current_map = map_id
	GameState.player_cell = spawn
	mode = Mode.OVERWORLD
	Log.info("map -> %s at %s" % [map_id, spawn], "SceneRouter")
	EventBus.map_changed.emit(map_id, spawn)
	return true


## For the overworld stream: announce a map change it performed itself.
func note_map_changed(map_id: StringName, spawn: Vector2i) -> void:
	GameState.current_map = map_id
	GameState.player_cell = spawn
	EventBus.map_changed.emit(map_id, spawn)
