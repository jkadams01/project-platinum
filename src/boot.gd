extends Node
## THE INTEGRATOR. `scenes/Boot.tscn` is the project's main scene and this is its
## script: the one file that knows the overworld, the battle, the UI and the data
## all exist, and wires them to each other.
##
## THE SHAPE, and why (src/autoload/scene_router.gd's header owns this decision):
## [codeblock]
## Main (this)
## |-- WorldHolder    Node2D   the Overworld instance + the camera
## |-- BattleHolder   Node     empty except during a battle
## |-- UILayer        CanvasLayer  message box, party view
## +-- TransitionLayer CanvasLayer
## [/codeblock]
## The overworld is SUSPENDED during a battle, never switched away from, so every
## NPC position, cleared rock and cutscene step survives a fight with no restore
## code. `SceneRouter.register()` is what hands it the two holders.
##
## THE CAMERA IS A SIBLING OF THE OVERWORLD, NOT A CHILD OF IT.
## `Overworld.load_map()` frees all of its own children on every map load, so a
## camera parented to it would be destroyed by the first warp. It lives under
## WorldHolder and follows `overworld.player.position`.
##
## NO MAP SCENES. `SceneRouter.load_map()` looks for `res://scenes/maps/<id>.tscn`
## and there are none: maps are DATA (`data/maps/*.json`, DATA_CONTRACT 9) and the
## Overworld node builds its TileMapLayers from that JSON. So warps go through
## `Overworld.load_map()`, which announces itself on `EventBus.map_changed`, and
## the router is used only for the battle transition.

const OVERWORLD_SCENE := "res://scenes/Overworld.tscn"

const Bosses := preload("res://src/systems/bosses.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")
const MessageBox := preload("res://src/ui/message_box.gd")
const PartyView := preload("res://src/ui/party_view.gd")
const Stats := preload("res://src/battle/stats.gd")

## The vertical slice starts here (DATA_CONTRACT 9 `data/maps/twinleaf_town.json`).
const START_MAP := "twinleaf_town"
## Sinnoh's grass starter, at the level the games hand it over at.
const STARTER_SPECIES := 387
const STARTER_LEVEL := 5

var overworld: Node2D = null
var camera: Camera2D = null
var message_box: Control = null
var party_view: Control = null

var _world: Node = null
var _battle: Node = null
var _ui: CanvasLayer = null
## Run after the message box empties -- how a boss's intro leads into the fight.
var _after_dialogue: Callable = Callable()
var _last_encounter_zone: String = ""


func _ready() -> void:
	Log.info("Project Platinum booting (Godot %s)" % Engine.get_version_info().string, "Boot")

	_world = get_node_or_null("WorldHolder")
	_battle = get_node_or_null("BattleHolder")
	_ui = get_node_or_null("UILayer") as CanvasLayer
	if _world == null or _battle == null or _ui == null:
		Log.error("Boot.tscn is missing WorldHolder / BattleHolder / UILayer", "Boot")
		return

	_report_data()
	Bosses.boot()

	_build_ui()
	_build_world()
	SceneRouter.register(_world, _battle, _ui)

	if GameState.party.is_empty():
		_give_starter()

	if not EventBus.battle_ended.is_connected(_on_battle_ended):
		EventBus.battle_ended.connect(_on_battle_ended)

	var spawn := _spawn_for(START_MAP)
	if not overworld.load_map(START_MAP, spawn):
		Log.error("could not load the starting map '%s'; data/maps is empty?" % START_MAP, "Boot")
		return

	Log.info("ready: %s at %s, %d in the party, cap %d" % [
		GameState.current_map, GameState.player_cell, GameState.party.size(),
		GameState.current_level_cap()], "Boot")
	message_box.show_lines(PackedStringArray([
		"%s's adventure begins in Twinleaf Town." % GameState.player_name,
		"WASD to walk, Shift to run, A (Enter) to talk, X to check your party.",
		"Oreburgh City and Roark are north, then east. Mind the level cap."]))


func _report_data() -> void:
	# `source_of()` distinguishes "the logic is wrong" from "the data is not built".
	# Saying it once at boot is what makes a degraded run obvious instead of weird.
	var stems := ["species", "moves", "learnsets", "abilities", "typechart", "level_caps"]
	var degraded := PackedStringArray()
	for s in stems:
		if DataRegistry.source_of(s) != "data":
			degraded.append("%s=%s" % [s, DataRegistry.source_of(s)])
	Log.info("data: %d species, %d moves, %d caps (cap now %d)" % [
		DataRegistry.species_count(), DataRegistry.move_count(),
		DataRegistry.level_cap_count(), GameState.current_level_cap()], "Boot")
	if not degraded.is_empty():
		Log.warn("running on fallback data: %s (run `python tools/build_all.py`)"
			% String(", ").join(degraded), "Boot")


func _build_ui() -> void:
	message_box = MessageBox.new()
	_ui.add_child(message_box)
	message_box.closed.connect(_on_dialogue_closed)

	party_view = PartyView.new()
	_ui.add_child(party_view)


func _build_world() -> void:
	var packed: PackedScene = load(OVERWORLD_SCENE) as PackedScene
	if packed == null:
		Log.error("could not load %s" % OVERWORLD_SCENE, "Boot")
		return
	overworld = packed.instantiate() as Node2D
	_world.add_child(overworld)
	overworld.encounter.connect(_on_wild_encounter)
	overworld.map_ready.connect(_on_map_ready)

	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position_smoothing_enabled = false
	_world.add_child(camera)
	camera.make_current()


func _give_starter() -> void:
	for mon: Dictionary in PartyBuilder.starter_party(STARTER_SPECIES, STARTER_LEVEL):
		GameState.add_to_party(mon)
	# Recorded from the species actually handed over, so there is no second copy of
	# the starter list to fall out of step. Every Barry fight derives his starter
	# from this, so the slice must set it even though the choice is not yet a
	# player-facing menu.
	GameState.set_starter_choice(Bosses.starter_slug_for(STARTER_SPECIES))
	# Enough to actually finish the slice: Roark's Cranidos hits hard.
	GameState.bag["potion"] = int(GameState.bag.get("potion", 0)) + 5
	GameState.bag["super-potion"] = int(GameState.bag.get("super-potion", 0)) + 2
	Log.info("starter party: %s" % _party_summary(), "Boot")


func _party_summary() -> String:
	var parts := PackedStringArray()
	for mon: Dictionary in GameState.party:
		parts.append("%s L%d %d/%d" % [Stats.display_name(mon), int(mon.get("level", 1)),
			int(mon.get("hp", 0)), int(mon.get("maxHp", 0))])
	return String(", ").join(parts)


# --------------------------------------------------------------------------
# Maps
# --------------------------------------------------------------------------

## The `{"type":"spawn"}` object of a map, or (-1,-1) to mean "use GameState".
## Spawn points live in the map JSON rather than in code so a map can be moved or
## resized without touching this file (DATA_CONTRACT 9 `objects`).
func _spawn_for(map_id: String) -> Vector2i:
	var path := "res://data/maps/%s.json" % map_id
	if not FileAccess.file_exists(path):
		return Vector2i(-1, -1)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return Vector2i(-1, -1)
	for o: Variant in ((parsed as Dictionary).get("objects", []) as Array):
		if o is Dictionary and String((o as Dictionary).get("type", "")) == "spawn":
			return Vector2i(int((o as Dictionary)["x"]), int((o as Dictionary)["y"]))
	return Vector2i(-1, -1)


func _on_map_ready(map_id: StringName) -> void:
	_last_encounter_zone = String(overworld.map.encounter_zone)
	_clamp_camera()
	Log.debug("map ready: %s zone=%s" % [map_id, _last_encounter_zone], "Boot")


## Stop the camera showing the void past a map's edge.
func _clamp_camera() -> void:
	if camera == null or overworld == null or overworld.map == null:
		return
	# `overworld` is a plain Node2D here (the Overworld script has no class_name), so
	# `map` comes back untyped and every field off it needs an explicit cast.
	var m: Object = overworld.map
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(m.get("width")) * int(m.get("tile_size"))
	camera.limit_bottom = int(m.get("height")) * int(m.get("tile_size"))


func _process(_delta: float) -> void:
	if camera != null and overworld != null and is_instance_valid(overworld.player):
		camera.position = overworld.player.position


# --------------------------------------------------------------------------
# Battles
# --------------------------------------------------------------------------

func _on_wild_encounter(roll: Dictionary) -> void:
	if SceneRouter.in_battle():
		return
	var mon := PartyBuilder.wild(int(roll["species"]), int(roll["level"]))
	if mon.is_empty():
		Log.warn("wild roll for species %s produced nothing" % roll.get("species"), "Boot")
		return
	SceneRouter.enter_battle({
		"kind": "wild",
		"party": GameState.party,
		"opponent": [mon],
		"playerName": GameState.player_name,
		"zone": String(roll.get("zone", _last_encounter_zone)),
	})


## Start a `data/rom/bosses.json` fight (DATA_CONTRACT 7.1).
func start_boss(key: String) -> bool:
	if SceneRouter.in_battle():
		return false
	if not Bosses.has(key):
		message_box.show_lines(PackedStringArray([
			"That fight is not built yet (no '%s' in data/rom/bosses.json)." % key]))
		return false
	var setup := Bosses.battle_setup(key, GameState.party)
	if setup.is_empty():
		return false
	return SceneRouter.enter_battle(setup)


func _on_battle_ended(result: Dictionary) -> void:
	if overworld != null:
		overworld.encounters.notify_battle_ended()
	var outcome := String(result.get("outcome", ""))
	var boss := String(result.get("boss", ""))
	var lines := PackedStringArray()

	if outcome == "win" and not boss.is_empty():
		var reward := Bosses.apply_victory(boss)
		for m: Variant in (reward["messages"] as Array):
			lines.append(String(m))
	elif outcome == "loss":
		lines.append_array(_white_out())

	if not lines.is_empty():
		message_box.show_lines(lines)
	Log.info("battle ended: %s%s | party: %s" % [
		outcome, "" if boss.is_empty() else " (%s)" % boss, _party_summary()], "Boot")


## Blacking out: full heal, and back to the last place with a bed in it. The slice
## has no Pokemon Centers to enter, so the current map's own spawn point stands in
## for one -- which keeps the player playable instead of stranded with a fainted
## party and no way to heal.
func _white_out() -> PackedStringArray:
	for mon: Dictionary in GameState.party:
		mon["hp"] = int(mon.get("maxHp", 1))
		mon["status"] = ""
		mon["statusCounter"] = 0
		for m: Dictionary in (mon.get("moves", []) as Array):
			m["pp"] = int(m.get("maxPp", m.get("pp", 0)))
	EventBus.party_changed.emit()
	var here := String(GameState.current_map)
	var spawn := _spawn_for(here)
	if spawn.x >= 0:
		overworld.load_map(here, spawn)
	return PackedStringArray([
		"%s scurried to safety and healed up." % GameState.player_name])


# --------------------------------------------------------------------------
# Interaction
# --------------------------------------------------------------------------

## The map object the player is facing, or {}. Objects sit on collision-1 tiles
## (tools/build_maps.py enforces that), so "facing it" and "bumped into it" are the
## same thing and no extra proximity rule is needed.
func faced_object() -> Dictionary:
	if overworld == null or overworld.map == null or not is_instance_valid(overworld.player):
		return {}
	var target: Vector2i = overworld.player.cell + overworld.player.facing
	for o: Variant in overworld.map.objects:
		if not (o is Dictionary):
			continue
		var d: Dictionary = o
		if Vector2i(int(d.get("x", -1)), int(d.get("y", -1))) == target:
			return d
	return {}


func interact() -> bool:
	var o := faced_object()
	if o.is_empty():
		return false
	match String(o.get("type", "")):
		"npc":
			_say(o, "lines")
			return true
		"item":
			return _take_item(o)
		"boss":
			return _talk_to_boss(o)
	return false


func _say(o: Dictionary, key: String) -> void:
	var lines := PackedStringArray()
	for l: Variant in (o.get(key, []) as Array):
		lines.append(String(l))
	if lines.is_empty():
		lines.append("...")
	message_box.show_lines(lines)


func _take_item(o: Dictionary) -> bool:
	var flag := "item_taken:%s" % String(o.get("id", "?"))
	if GameState.get_flag(flag):
		message_box.show_lines(PackedStringArray(["Nothing left here."]))
		return true
	var item := String(o.get("item", ""))
	var count := maxi(int(o.get("count", 1)), 1)
	if not item.is_empty():
		GameState.bag[item] = int(GameState.bag.get(item, 0)) + count
	GameState.set_flag(flag, true)
	_say(o, "lines")
	return true


func _talk_to_boss(o: Dictionary) -> bool:
	var key := String(o.get("boss", o.get("id", "")))
	if Bosses.is_defeated(key):
		_say(o, "afterLines")
		return true
	_say(o, "lines")
	# The intro plays, THEN the fight: starting the battle here would put the
	# battle scene up underneath a dialogue box the player has not read.
	_after_dialogue = func() -> void: start_boss(key)
	return true


func _on_dialogue_closed() -> void:
	if not _after_dialogue.is_valid():
		return
	var f := _after_dialogue
	_after_dialogue = Callable()
	f.call()


func _unhandled_input(event: InputEvent) -> void:
	if SceneRouter.in_battle():
		return
	if message_box != null and message_box.is_open():
		return
	if party_view != null and party_view.is_open():
		return
	if event.is_action_pressed(&"game_menu"):
		party_view.open(false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_accept"):
		if interact():
			get_viewport().set_input_as_handled()
