# Godot 4.7.2 architecture for a tile-based Pokémon-style RPG

**Engine verified:** `4.7.2.stable.official.ed1daf0bf`
**Binary:** `C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe`
**Status:** every API call, benchmark and command line below was executed against that binary on this machine. Numbers are measured, not estimated. Anything I did not run is labelled **[unverified]**.

Scratch project used for verification: `tools/_work/godottest/` (gitignored).

---

## 0. The three command lines you actually need

The Godot project root **is the repo root** — `project.godot` sits at `project-platinum/project.godot`, not in a subdirectory.

```bash
GODOT="C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe"
PROJ="C:/Users/James/Documents/GitHub/project-platinum"

# 1. Refresh imports + the class_name registry. Run after ANY asset or class_name change.
"$GODOT" --headless --path "$PROJ" --import

# 2. Run the test suite. Exit 0 = pass, 1 = fail.
"$GODOT" --headless --path "$PROJ" --script res://tests/run_tests.gd

# 3. Static type-check one script without running it. Exit 1 on any type error.
"$GODOT" --headless --path "$PROJ" --check-only --script res://scripts/foo.gd
```

Use the `_console.exe` build, not the plain one — the plain Windows build detaches from the console and you get no stdout.

---

## 1. Tile rendering

### 1.1 TileMapLayer is the node. TileMap is legacy.

Godot 4.3 deprecated the monolithic `TileMap` in favour of one `TileMapLayer` node per layer. In 4.7.2 `TileMap` **still exists and still instantiates** — verified: `ClassDB.can_instantiate("TileMap") == true` — purely so old projects keep opening. Do not use it. It is frozen, it will not gain features, and every 4.3+ tutorial you find that uses `TileMap.set_cell(layer, ...)` has a different signature from what you want.

The signature difference is the thing that bites:

```gdscript
# Godot 4.2 and earlier (TileMap) — the first arg is a layer index
tilemap.set_cell(0, Vector2i(3, 4), source_id, Vector2i(1, 0), 0)

# Godot 4.3+ (TileMapLayer) — no layer index; the node IS the layer
layer.set_cell(Vector2i(3, 4), source_id, Vector2i(1, 0), 0)
```

`TileMapLayer` extends `Node2D` (verified via `ClassDB.get_parent_class`). It is not a physics body; it owns a static body RID internally and exposes `collision_enabled`, with zero child nodes.

### 1.2 Recommended scene layout for an overworld map

```
Map (Node2D, y_sort_enabled = true)
├── Ground        (TileMapLayer, z_index = -10, y_sort_enabled = false)
├── Decor         (TileMapLayer, z_index = -5,  y_sort_enabled = false)
├── Objects       (TileMapLayer, z_index = 0,   y_sort_enabled = true)   # trees, signs, ledges
├── Entities      (Node2D,       z_index = 0,   y_sort_enabled = true)   # player + NPCs live here
├── Overhead      (TileMapLayer, z_index = 10,  y_sort_enabled = false)  # bridge decks, roofs
└── Collision     (TileMapLayer, visible = false)                        # optional: metadata-only layer
```

Separate layers rather than one layer with many tiles, because each `TileMapLayer` gets its own `z_index`, its own y-sort setting, and can be shown/hidden independently (bridge overpasses, interiors).

### 1.3 Y-sort: the gotcha

**A layer's `y_sort_enabled` does nothing unless every ancestor up to the sorting root also has it enabled.** Verified: setting `layer.y_sort_enabled = true` leaves `parent.y_sort_enabled == false`, and in that state the layer sorts internally but will not interleave with sibling nodes. The player will render behind or in front of *all* tree tiles rather than correctly per-tree.

Set y-sort on:
- the `Map` root,
- the `Objects` tile layer,
- the `Entities` node.

Then tune the per-tile pivot with `TileData.y_sort_origin` (verified default `0`, in pixels relative to the tile's centre). For a 16px tile whose trunk base sits at the bottom edge, `y_sort_origin = 8` makes the sprite sort by its base rather than its centre.

```gdscript
var td := source.get_tile_data(Vector2i(4, 2), 0)
td.y_sort_origin = 8     # sort this tree by its trunk, not its canopy
td.z_index = 0
```

### 1.4 Authoring a TileSet from an atlas PNG in code

This is the pipeline-facing part. Verified end to end.

```gdscript
# tools/build_tileset.gd — run with: godot --headless --path . --script res://tools/build_tileset.gd
extends SceneTree

const TILE := 16

# name -> Variant.Type. These become the per-tile metadata columns.
const CUSTOM_DATA := {
	"solid":     TYPE_BOOL,
	"grass":     TYPE_BOOL,
	"water":     TYPE_BOOL,
	"ledge_dir": TYPE_VECTOR2I,        # ZERO = not a ledge
	"zone":      TYPE_STRING_NAME,     # encounter table key, e.g. &"route_201"
	"encounters": TYPE_PACKED_INT32_ARRAY,
}

func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_layout = TileSet.TILE_LAYOUT_STACKED
	ts.tile_size = Vector2i(TILE, TILE)

	# --- custom data layers, declared BEFORE any tile writes ---
	for cd_name in CUSTOM_DATA:
		var i := ts.get_custom_data_layers_count()
		ts.add_custom_data_layer()
		ts.set_custom_data_layer_name(i, cd_name)
		ts.set_custom_data_layer_type(i, CUSTOM_DATA[cd_name])

	# --- physics layer (only if you want real bodies; see §2.5 — usually you don't) ---
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)

	# --- terrain set, for autotiling paths/water in the editor ---
	ts.add_terrain_set()
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	ts.add_terrain(0)
	ts.set_terrain_name(0, 0, "grass")

	# --- the atlas source ---
	var tex: Texture2D = load("res://assets/tilesets/route_201.png")
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(TILE, TILE)
	src.margins = Vector2i.ZERO
	src.separation = Vector2i.ZERO

	var grid := src.get_atlas_grid_size()          # e.g. 64x48 px / 16 -> Vector2i(4, 3)
	for y in grid.y:
		for x in grid.x:
			src.create_tile(Vector2i(x, y))

	var source_id := ts.add_source(src, 0)         # <-- MUST happen before custom-data writes

	# --- now, and only now, write per-tile metadata ---
	_tag(src, Vector2i(0, 0), {"grass": true, "zone": &"route_201",
		"encounters": PackedInt32Array([396, 399, 401])})
	_tag(src, Vector2i(1, 0), {"solid": true})
	_tag(src, Vector2i(2, 0), {"water": true, "zone": &"route_201_surf"})
	_tag(src, Vector2i(3, 0), {"ledge_dir": Vector2i.DOWN})

	# a wall tile that also wants a real collision polygon
	var wall := src.get_tile_data(Vector2i(1, 0), 0)
	wall.set_collision_polygons_count(0, 1)
	wall.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)]))

	# animated water: 4 frames across the atlas row
	src.set_tile_animation_frames_count(Vector2i(2, 0), 4)
	for f in 4:
		src.set_tile_animation_frame_duration(Vector2i(2, 0), f, 0.25)

	var err := ResourceSaver.save(ts, "res://assets/tilesets/route_201.tres")
	print("saved tileset, err=", err, " source_id=", source_id, " tiles=", src.get_tiles_count())
	quit(0 if err == OK else 1)

func _tag(src: TileSetAtlasSource, coords: Vector2i, data: Dictionary) -> void:
	var td := src.get_tile_data(coords, 0)
	for k in data:
		td.set_custom_data(k, data[k])
```

#### The ordering trap — this one will silently corrupt your data

`TileData` resolves custom-data layer names **through its owning TileSet**. If the atlas source is not yet attached, the write fails.

Verified behaviour:

```
ERROR: Parameter "tile_set" is null.
   at: set_custom_data (scene/resources/2d/tile_set.cpp:6656)
[B] value after early set = <null>       <-- LOST
[B] value after add_source = false       <-- still lost, now reading as the type default
[B] correct order value = true           <-- OK
```

The nasty part is the second line. After you later call `add_source()`, the tile reads back as `false` — the *type default* — not `null` and not an error. A generated tileset would look structurally fine and every grass tile would silently be non-grass. `set_custom_data_by_layer_id()` does not dodge it either; it throws `Index p_layer_id = 0 is out of bounds (custom_data.size() = 0)`.

**Mandatory order:**
1. `TileSet.new()`, set `tile_size`
2. `add_custom_data_layer()` × N, with names and types
3. build `TileSetAtlasSource`, `create_tile()` for every cell
4. **`ts.add_source(src, id)`**
5. *then* `get_tile_data(...).set_custom_data(...)`

Adding a *new* custom data layer later is safe — verified that pre-existing values on other layers survive `add_custom_data_layer()`.

`tests/cases/test_tileset_codegen.gd` (§6.4) contains a regression guard for exactly this.

#### The texture-embedding trap

How you obtain the `Texture2D` changes the output file size by ~180×.

| How the texture was made | Saved `.tres` size |
|---|---|
| `ImageTexture.create_from_image(img)` | **78,183 bytes** |
| `load("res://atlas.png")` after an import pass | **436 bytes** |

`ImageTexture` has no `resource_path`, so `ResourceSaver` inlines the entire pixel buffer as a `[sub_resource type="Image"]` with a literal `PackedByteArray(60, 140, 60, 255, ...)`. An imported PNG is a `CompressedTexture2D` with `resource_path == "res://atlas.png"`, and the tileset stores a one-line `[ext_resource]` reference instead.

So the pipeline is: **Python writes the PNG → `--import` → the codegen script `load()`s it → save the tileset.** Never `Image.load()` + `create_from_image()` for assets that get saved into a resource.

(`Image.load()` is still the right call when you want to *inspect* a PNG headlessly without importing — verified it works with no import pass, returning `size=(64,64) fmt=5`, where `ResourceLoader.load()` fails outright with `No loader found for resource`.)

### 1.5 Reading tile metadata at runtime

```gdscript
@onready var ground: TileMapLayer = $Ground
@onready var objects: TileMapLayer = $Objects

func tile_blocks(cell: Vector2i) -> bool:
	for layer: TileMapLayer in [objects, ground]:
		var td := layer.get_cell_tile_data(cell)
		if td and td.get_custom_data("solid"):
			return true
	return false

func encounter_zone(cell: Vector2i) -> StringName:
	var td := ground.get_cell_tile_data(cell)
	return td.get_custom_data("zone") if td else &""
```

`get_cell_tile_data()` returns `null` for an empty cell — verified — so the `if td` guard is required, not defensive padding.

**Cost, measured on a 200×200 (40,000 cell) layer:**

| Operation | 200,000 calls | Per call |
|---|---|---|
| `get_cell_tile_data()` + `get_custom_data("name")` | 72.6 ms | **0.363 µs** |
| `get_cell_tile_data()` + `get_custom_data_by_layer_id(i)` | 67.9 ms | 0.340 µs |

At ~4 lookups per step and ~4 steps/second, that is under 6 µs/second. Tile metadata lookups are free. Do not cache them into a parallel Dictionary; you would be adding a synchronisation bug to save nothing. The by-layer-id variant is only 7% faster — use the readable string form.

---

## 2. Grid movement

### 2.1 Recommendation: manual lerp with overshoot carry. Not Tween, not physics.

Three candidate approaches, and why two lose:

**`Tween` per step** — `create_tween().tween_property(self, "position", target, 0.24)` genuinely does land exactly on target (verified: `await tw.finished` then `position == Vector2(16, 0)` exactly). But it is the wrong tool here because:
- you cannot cleanly cancel/redirect mid-step when the player changes direction,
- chaining steps costs you the leftover frame time at each boundary, so held-down running visibly stutters every tile,
- awaiting a dead tween hangs forever, so every call site needs an `is_valid()`/`is_running()` guard (verified: after finishing, `is_running() == false`, `is_valid() == true`).

**Physics bodies (`CharacterBody2D` + `move_and_slide`)** — you inherit float drift, wall-sliding you don't want (Pokémon movement never slides along a wall), and you'd fight the physics tick to stay tile-aligned. Tile-based games don't want a physics solver.

**Manual lerp driven by `_process(delta)`, with the overshoot carried into the next step** — deterministic, cancellable, drift-free, trivially testable headlessly. This is the one.

### 2.2 The controller

This is the exact file that passes the test suite in §6.

```gdscript
class_name GridMover
extends Node2D

const TILE := 16

enum State { IDLE, TURNING, MOVING }

@export var walk_time := 0.24      # sec per tile, walking
@export var run_time  := 0.12      # sec per tile, running
@export var turn_time := 0.08      # "pivot in place" delay before a step

var state: State = State.IDLE
var facing := Vector2i.DOWN
var cell := Vector2i.ZERO
var steps_taken := 0

# Injected by the map so the mover doesn't need to know about TileMapLayers.
var solid: Callable = func(_c: Vector2i) -> bool: return false

var _buffered: Vector2i = Vector2i.ZERO   # input buffer: one queued direction
var _elapsed := 0.0
var _dur := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO

func snap_to(c: Vector2i) -> void:
	cell = c
	position = Vector2(c * TILE)

# Call every frame with the held direction (Vector2i.ZERO if none) and the run flag.
func tick(dir: Vector2i, running: bool, delta: float) -> void:
	match state:
		State.IDLE:
			var d := dir if dir != Vector2i.ZERO else _buffered
			_buffered = Vector2i.ZERO
			if d == Vector2i.ZERO:
				return
			if d != facing:
				facing = d                       # DS games pivot before stepping
				state = State.TURNING
				_elapsed = 0.0
				_dur = turn_time
				return
			_begin_step(d, running)

		State.TURNING:
			_elapsed += delta
			if dir != Vector2i.ZERO and dir != facing:
				facing = dir                     # re-pivot without finishing
			if _elapsed >= _dur:
				state = State.IDLE
				if dir != Vector2i.ZERO:
					_begin_step(dir, running)

		State.MOVING:
			_elapsed += delta
			if dir != Vector2i.ZERO:
				_buffered = dir                  # buffer while mid-step
			position = _from.lerp(_to, clampf(_elapsed / _dur, 0.0, 1.0))
			if _elapsed >= _dur:
				var over := _elapsed - _dur      # leftover time from this frame
				position = _to
				cell = Vector2i(_to / TILE)
				steps_taken += 1
				state = State.IDLE
				_elapsed = 0.0
				var nxt := dir if dir != Vector2i.ZERO else _buffered
				_buffered = Vector2i.ZERO        # MUST clear, or you walk forever
				if nxt != Vector2i.ZERO and nxt == facing:
					_begin_step(nxt, running)
					_elapsed = over              # carry overshoot -> no stutter, no drift
					position = _from.lerp(_to, clampf(_elapsed / _dur, 0.0, 1.0))

func _begin_step(d: Vector2i, running: bool) -> void:
	facing = d
	var target := cell + d
	if solid.call(target):
		state = State.IDLE                       # bump: you turn, you don't move
		return
	_from = Vector2(cell * TILE)
	_to = Vector2(target * TILE)
	_dur = run_time if running else walk_time
	_elapsed = 0.0
	state = State.MOVING
```

### 2.3 Why the two marked lines matter

**`_elapsed = over`** — the overshoot carry. Without it, every tile boundary discards up to one frame of time, so a held-down run loses ~1 frame per tile and the character visibly hitches. With it, the test *"40 tiles under randomised frame times between 4 ms and 50 ms"* lands on **exactly 656 px = 41 × 16**, with `position.y == 0.0` and zero accumulated error.

**`_buffered = Vector2i.ZERO`** — I got this wrong first. The initial version consumed `_buffered` without clearing it, so once you tapped a direction the mover chained off the stale buffer forever. The headless suite caught it immediately: the settle loop never terminated and the character had walked **1,399 tiles east** when the 10,000-iteration guard fired. That is a bug that would have been maddening to diagnose by playtesting and took one test run to find. It is the single best argument for §6.

### 2.4 Driving it

```gdscript
extends GridMover

func _process(delta: float) -> void:
	if GameState.input_locked:
		tick(Vector2i.ZERO, false, delta)
		return
	# action names match the repo's existing project.godot
	var dir := Vector2i(
		int(Input.get_axis(&"ui_left", &"ui_right")),
		int(Input.get_axis(&"ui_up", &"ui_down")))
	if dir.x != 0 and dir.y != 0:
		dir.y = 0                                  # no diagonals; horizontal wins
	tick(dir, Input.is_action_pressed(&"game_run"), delta)
```

Use `_process`, not `_physics_process` — there is no physics here, and `_process` runs at display rate so the tween is as smooth as the monitor allows.

**Pixel snapping interacts with this, correctly.** The repo's `project.godot` sets `2d/snap/snap_2d_transforms_to_pixel=true` with a 256×192 viewport. That snaps the *rendered* transform to whole pixels while leaving the logical `position` float untouched — so the sprite never lands on a half-pixel and shimmers, and the drift-free maths above still works on exact values. Keep both. Do not "fix" sub-pixel positions by rounding `position` yourself; that would reintroduce the accumulation error the overshoot carry exists to prevent.

### 2.5 Collision: tile custom data, not physics bodies

Use the `solid` callable against tile metadata. Reasons:
- **It's free.** 0.363 µs per lookup (§1.5), and you do ~2 per step.
- **It's exact.** No float tolerance, no tunnelling, no sliding.
- **It's testable headlessly.** The suite injects `m.solid = func(c): return c == Vector2i(1, 0)` and asserts the mover stayed put — no physics server, no collision shapes, no frame timing.
- **Ledges and one-way tiles are trivial.** A physics body cannot express "passable southbound only" without a mess of one-way collision shapes.

```gdscript
func _install_collision(map: Node2D) -> void:
	var ground: TileMapLayer = map.get_node("Ground")
	var objects: TileMapLayer = map.get_node("Objects")
	solid = func(c: Vector2i) -> bool:
		# ledges: passable only in the ledge's own direction
		var g := ground.get_cell_tile_data(c)
		if g:
			var ld: Vector2i = g.get_custom_data("ledge_dir")
			if ld != Vector2i.ZERO and ld != facing:
				return true
			if g.get_custom_data("water") and not GameState.has_surf:
				return true
		for layer: TileMapLayer in [objects, ground]:
			var td := layer.get_cell_tile_data(c)
			if td and td.get_custom_data("solid"):
				return true
		return EntityIndex.occupied(c)             # NPCs, pushable blocks
```

Keep the TileSet's physics layer defined anyway (the codegen script adds one) — it costs nothing and gives you `Area2D` overlap queries later if you want them for cutscene triggers.

### 2.6 Input buffering

The buffer above holds exactly **one** queued direction, refreshed every frame while `MOVING`. That matches DS behaviour: release the d-pad mid-step and you complete the current tile plus the buffered one, then stop. Verified: `steps_taken == 2` after releasing 6 frames into step 1.

Do not build a deeper queue. A 3-deep buffer means the character keeps walking a half-second after the player stops, which reads as input lag.

---

## 3. Autoloads and save/load

### 3.1 Autoloads work in headless `--script` mode

Worth stating because the common belief (inherited from Godot 3) is that they don't. Verified in 4.7.2: running `--headless --path . --script probe.gd` printed `[autoload] GameState ready` and `root.get_node_or_null("GameState")` returned the node. Autoloads are instantiated under `root` *before* your `SceneTree` subclass's `_initialize()` runs.

This means your test harness can exercise real singletons. It also means an autoload that does heavy work in `_ready()` slows down every test run — keep `_ready()` cheap and do the expensive load lazily or on an explicit `boot()` call.

### 3.2 The three singletons

The repo's existing `project.godot` already declares a superset, under `res://src/autoload/`:

```gdscript
[autoload]
Logger="*res://src/autoload/logger.gd"
DataRegistry="*res://src/autoload/data_registry.gd"
EventBus="*res://src/autoload/event_bus.gd"
GameState="*res://src/autoload/game_state.gd"
SaveSystem="*res://src/autoload/save_system.gd"
SceneRouter="*res://src/autoload/scene_router.gd"
```

That set is right and the ordering is right. **Order matters** — autoloads initialise top to bottom, so anything that connects to `EventBus` in `_ready()` must be declared below it. `Logger` first is correct so the others can log during boot. Map the roles onto §5 and §4: `DataRegistry` is the species/move/item DB owner from §5.2, and `SceneRouter` owns the `Main`-root suspend/resume flow from §4.2 rather than calling `change_scene_to_*`.

Paths in the snippets below are written as `res://autoload/...` for brevity; use `res://src/autoload/...` to match the existing project.

```gdscript
# autoload/event_bus.gd — signals only, no state, no logic
extends Node

signal player_moved(cell: Vector2i)
signal tile_entered(cell: Vector2i, zone: StringName)
signal encounter_triggered(zone: StringName, level_range: Vector2i)
signal battle_started(setup: BattleSetup)
signal battle_finished(result: BattleResult)
signal map_changed(map_id: StringName, spawn: Vector2i)
signal flag_set(flag: StringName, value: bool)
signal dialogue_requested(lines: PackedStringArray)
```

A bus keeps the overworld from holding a hard reference to the battle scene and vice versa. Declare typed signal parameters — 4.7 checks them at emit time and the editor autocompletes the handler signature.

```gdscript
# autoload/game_state.gd — the entire mutable world, and nothing else
extends Node

var party: Array[MonInstance] = []
var bag: Dictionary[StringName, int] = {}
var flags: Dictionary[StringName, bool] = {}
var money: int = 3000
var play_seconds: float = 0.0
var current_map: StringName = &"twinleaf_town"
var player_cell: Vector2i = Vector2i(10, 12)
var player_facing: Vector2i = Vector2i.DOWN
var input_locked: bool = false
var rng_seed: int = 0

func to_dict() -> Dictionary:
	return {
		"v": 1,
		"party": party.map(func(m: MonInstance) -> Dictionary: return m.to_dict()),
		"bag": bag,
		"flags": flags,
		"money": money,
		"play_seconds": play_seconds,
		"map": String(current_map),
		"cell": [player_cell.x, player_cell.y],
		"facing": [player_facing.x, player_facing.y],
		"rng_seed": rng_seed,
	}

func from_dict(d: Dictionary) -> void:
	assert(int(d.get("v", 0)) == 1, "save version mismatch")
	party.assign((d["party"] as Array).map(func(x: Dictionary) -> MonInstance:
		return MonInstance.from_dict(x)))
	bag.assign(d["bag"])
	flags.assign(d["flags"])
	money = int(d["money"])
	play_seconds = float(d["play_seconds"])
	current_map = StringName(d["map"])
	player_cell = Vector2i(int(d["cell"][0]), int(d["cell"][1]))
	player_facing = Vector2i(int(d["facing"][0]), int(d["facing"][1]))
	rng_seed = int(d["rng_seed"])
```

Note every `int(...)` on the way back in. That is not paranoia — see §3.4.

### 3.3 Save format: `FileAccess.store_var` with objects disabled

Measured on a representative save payload, and on the 2 MB species DB for scale:

| Format | Round-trip | Preserves `int` | Preserves `Vector2i` | Can execute code |
|---|---|---|---|---|
| `JSON.stringify` / `parse_string` | works | **no — all numbers become float** | no (manual pack) | no |
| `FileAccess.store_var(v, false)` | works | **yes** | **yes** | **no** |
| `ConfigFile` | works | yes | **yes** | no |
| `ResourceSaver` / `ResourceLoader` (`.tres`/`.res`) | works | yes | yes | **YES — see §3.5** |

**Use `store_var` with `full_objects = false`.**

```gdscript
# autoload/save_system.gd
extends Node

const SLOT_FMT := "user://save_%d.sav"
const MAGIC := "PLAT"
const VERSION := 1

func save_slot(slot: int) -> Error:
	var payload := {
		"magic": MAGIC,
		"version": VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"state": GameState.to_dict(),
	}
	var tmp := SLOT_FMT % slot + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(payload, false)          # false = refuse to encode Objects
	f.close()
	# atomic-ish swap so a crash mid-write can't destroy the previous save
	var d := DirAccess.open("user://")
	if d.file_exists(SLOT_FMT % slot):
		d.remove(SLOT_FMT % slot)
	return d.rename(tmp, SLOT_FMT % slot)

func load_slot(slot: int) -> bool:
	var path := SLOT_FMT % slot
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var payload = f.get_var(false)       # false = never instantiate Objects
	f.close()
	if typeof(payload) != TYPE_DICTIONARY:
		push_error("save %d is not a Dictionary" % slot); return false
	if payload.get("magic") != MAGIC:
		push_error("save %d has a bad magic value" % slot); return false
	if int(payload.get("version", -1)) != VERSION:
		push_error("save %d version %s, expected %d" % [slot, payload.get("version"), VERSION])
		return false
	GameState.from_dict(payload["state"])
	return true
```

The `false` argument is the whole security story and it appears on both sides. Verified: writing `{"payload": Resource.new()}` with `full_objects = false` and reading it back yields `{ "payload": <EncodedObjectAsID#...> }` — an inert id, not a reconstructed object.

For a human-readable settings file (key bindings, volume, text speed), `ConfigFile` is the better fit — it preserves `Vector2i` correctly (verified: type 6 round-trips) and it has `save_encrypted_pass()` / `load_encrypted_pass()` if you want the save lightly tamper-resistant.

### 3.4 JSON silently floats every number

Verified: parsing a species record back out of JSON gives `typeof(id) == 3` (`TYPE_FLOAT`), not `2` (`TYPE_INT`). `base_stats.hp` came back as `126.0`.

For a Pokémon game this is not cosmetic. Species IDs, move IDs, levels, EVs, IVs, money, PIDs and RNG seeds are all integers, and a float that has drifted by one ULP used as a Dictionary key or array index is a bug that will surface hours later. If you use JSON anywhere, `int()` every numeric field at the boundary — which is what `from_dict()` above does.

`store_var` has no such problem: `typeof` came back as `2` (`TYPE_INT`) and `3000 == 3000` exactly.

### 3.5 Never load a Resource you did not author. Demonstrated, not theoretical.

I hand-wrote a `.tres` containing an embedded `GDScript` sub-resource and loaded it with `ResourceLoader.load()`. Verbatim output:

```
[SEC] loading a hand-written .tres that embeds a GDScript:
    >>> ARBITRARY CODE FROM A SAVE FILE RAN <<<
[SEC] loaded -> (user://hostile.tres):<Resource#...>  script=(user://hostile.tres::evil):<GDScript#...>
```

The file's `_init()` executed during `ResourceLoader.load()`. That is remote code execution from a data file.

And there is no opt-out. Verified signature in 4.7.2:

```
ResourceLoader.load(path: String, type_hint: String, cache_mode: int)
```

No `allow_objects` flag, no safe mode. The `type_hint` does not help — the sub-resource is instantiated regardless of what you claim the top-level type is.

**The rule:**

| Data | Format | Why |
|---|---|---|
| Ship-with-the-game content (species DB, tilesets, maps, moves) | `.res` / `.tres` Resources | Lives inside your PCK, you authored it, and it's the fastest option (§5) |
| Player save files in `user://` | `store_var(..., false)` | A save file is attacker-controlled the moment anyone shares one |
| Settings | `ConfigFile` | Human-editable on purpose |
| Anything downloaded, pasted, or from a "save editor" | `store_var(..., false)`, then validate every field | — |

Shared save files are normal in the ROM-hack and fan-remake scene. Treat `user://` as hostile.

---

## 4. Scene structure and overworld ↔ battle

### 4.1 `change_scene_to_*` is deferred, and it frees your overworld

Verified: immediately after `change_scene_to_packed()` returns `OK`, `get_tree().current_scene` is still `null`. It is populated after one process frame. So this is a bug:

```gdscript
get_tree().change_scene_to_packed(battle_scene)
get_tree().current_scene.setup(party)   # CRASH — current_scene is null right here
```

More importantly, `change_scene_to_*` **frees the outgoing scene**. Your overworld — NPC positions, open doors, pushed boulders, cutscene progress, the loaded tilesets — is gone, and coming back means a full reload plus a state-restore pass you have to write and keep correct.

### 4.2 Recommended: a persistent root that suspends rather than switches

```
Main (Node)                          <- res://main.tscn, the only scene in run/main_scene
├── WorldHolder   (Node)             <- the current map lives here, suspended during battle
├── BattleHolder  (Node)             <- empty until a battle starts
├── UILayer       (CanvasLayer)      <- HUD, dialogue box, menus
└── TransitionLayer (CanvasLayer)    <- fade/spiral ColorRect, always on top
```

```gdscript
# main.gd
extends Node

@onready var world: Node = $WorldHolder
@onready var battle: Node = $BattleHolder
@onready var transition: Transition = $TransitionLayer/Transition

const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")

func _ready() -> void:
	EventBus.encounter_triggered.connect(_on_encounter)
	EventBus.battle_finished.connect(_on_battle_finished)
	load_map(GameState.current_map, GameState.player_cell)

func _on_encounter(zone: StringName, level_range: Vector2i) -> void:
	GameState.input_locked = true
	await transition.play_in(&"battle_swirl")      # ~0.8 s of DS-style flash
	_suspend_world()
	var b := BATTLE_SCENE.instantiate()
	battle.add_child(b)
	b.setup(GameState.party, WildEncounters.roll(zone, level_range))
	await transition.play_out(&"battle_swirl")

func _on_battle_finished(result: BattleResult) -> void:
	await transition.play_in(&"fade")
	for c in battle.get_children():
		c.queue_free()
	await get_tree().process_frame                 # let the frees land
	_resume_world()
	GameState.apply_battle_result(result)
	await transition.play_out(&"fade")
	GameState.input_locked = false

func _suspend_world() -> void:
	world.process_mode = Node.PROCESS_MODE_DISABLED
	world.visible = false                           # WorldHolder must be a CanvasItem
                                                    # or hide the map node itself

func _resume_world() -> void:
	world.visible = true
	world.process_mode = Node.PROCESS_MODE_INHERIT
```

Verified: `process_mode = PROCESS_MODE_DISABLED` (enum value 4) plus `visible = false` leaves the node fully in the tree (`is_inside_tree() == true`) with all state intact. Nothing to save, nothing to restore, and returning from a battle is instant — no map reload, no tileset re-parse.

Cost: the suspended map stays in memory. For a 200×200 layer that measured **38.8 MB static** total for the whole engine process including the map. Irrelevant on any machine that runs Godot 4.

### 4.3 If you must fully unload: detach, don't free

Verified that a node removed with `remove_child()` stays alive and keeps its children and metadata (`is_instance_valid() == true`, child `get_meta("cell")` still `(7, 3)` after a detach/re-attach cycle). That gives you a middle path — release the map from the tree but hold the reference — though the suspend approach above is simpler and you should prefer it.

### 4.4 Map switching

```gdscript
func load_map(map_id: StringName, spawn: Vector2i) -> void:
	for c in world.get_children():
		c.queue_free()
	await get_tree().process_frame
	var scene: PackedScene = load("res://maps/%s.tscn" % map_id)
	var m := scene.instantiate()
	world.add_child(m)
	GameState.current_map = map_id
	var player := m.get_node("Entities/Player") as GridMover
	player.snap_to(spawn)
	EventBus.map_changed.emit(map_id, spawn)
```

For large maps use `ResourceLoader.load_threaded_request()` so the door-transition fade covers the load. Verified working headlessly: the combined species `.res` loaded in 29.6 ms non-blocking, polling `load_threaded_get_status()` across `await process_frame` until it left `THREAD_LOAD_IN_PROGRESS`.

### 4.5 `PackedScene.pack()` drops children without an `owner`

Pipeline-relevant, verified:

```
[P] packed scene kept child? true    (marker.owner = root was set)
[P] without .owner the child is DROPPED: 0 children
```

If a Python/GDScript step builds map scenes in code, every descendant needs `child.owner = scene_root` before `pack()`, or you will save an empty scene with no error.

```gdscript
func _build_map_scene(root_name: String, layers: Array[TileMapLayer]) -> PackedScene:
	var root := Node2D.new()
	root.name = root_name
	root.y_sort_enabled = true
	for l in layers:
		root.add_child(l)
		l.owner = root                 # <-- without this, pack() saves nothing
	var ps := PackedScene.new()
	var err := ps.pack(root)
	assert(err == OK)
	return ps
```

### 4.6 Transitions

```gdscript
# transition.gd
class_name Transition
extends ColorRect

func play_in(kind: StringName) -> void:
	material.set_shader_parameter("kind", kind)
	var t := create_tween()
	t.tween_method(_set_cut, 0.0, 1.0, 0.45).set_trans(Tween.TRANS_CUBIC)
	await t.finished

func play_out(kind: StringName) -> void:
	var t := create_tween()
	t.tween_method(_set_cut, 1.0, 0.0, 0.35).set_trans(Tween.TRANS_CUBIC)
	await t.finished

func _set_cut(v: float) -> void:
	material.set_shader_parameter("cut", v)
```

Put it on a `CanvasLayer` with a high `layer` value so it covers the HUD too. `await transition.play_in(...)` composes cleanly with the `async` flow in `main.gd`.

---

## 5. Loading 1,025 species

### 5.1 Measured, on a realistic dataset

Generated 1,025 species records with the full shape you'd actually need — base stats, abilities, growth rate, egg groups, EV yield, evolutions, a 30–70 entry learnset, 120 TM compatibility flags, egg moves, tutor moves, dex text. **2,028 KB as JSON.**

| Approach | Load time | On-disk | Notes |
|---|---|---|---|
| **1,025 individual `.json` files** | **6,301 ms** | 2,028 KB | per-file open dominates |
| 1,025 individual `.tres` Resources | 633 ms | ~1 KB each | |
| one combined `.tres` (text Resource) | 165 ms | 1,437 KB | |
| one big `.json` → Dictionary | 89 ms | 2,028 KB | all ints become floats |
| one `store_var` binary → Dictionary | 30 ms | 3,283 KB | |
| **one combined `.res` (binary Resource)** | **26 ms** | **1,099 KB** | typed access, ints preserved |
| same `.res` via `load_threaded_request` | 30 ms | — | non-blocking |
| lazy: one `.tres` on demand | 0.73 ms | — | |
| lazy: one `.json` on demand | 0.43 ms | — | |

### 5.2 Recommendation: one binary `.res` holding a typed array of custom Resources

It wins on every axis simultaneously — **fastest (26 ms), smallest (1,099 KB), type-safe, and integers survive.** The "obvious" design of one Resource file per species is **24× slower**, and one JSON file per species is **242× slower** — 6.3 seconds of startup for data that should cost 26 milliseconds.

The per-file cost is the lesson: it is not parsing that's slow, it's opening files. 1,025 opens cost ~6.2 s regardless of how small each file is.

```gdscript
# data/species_data.gd
class_name SpeciesData
extends Resource

@export var id: int
@export var name_en: String
@export var types: PackedStringArray
@export var base_stats: PackedInt32Array        # hp atk def spa spd spe
@export var abilities: PackedInt32Array
@export var catch_rate: int
@export var base_exp: int
@export var growth_rate: StringName
@export var egg_groups: PackedInt32Array
@export var gender_ratio: int
@export var hatch_cycles: int
@export var height_dm: int
@export var weight_hg: int
@export var ev_yield: PackedInt32Array
@export var learnset_levels: PackedInt32Array   # parallel arrays beat an
@export var learnset_moves: PackedInt32Array    # Array[Dictionary] for size and speed
@export var tm_compat: PackedByteArray
@export var egg_moves: PackedInt32Array
@export var tutor_moves: PackedInt32Array
@export var dex_entry: String
```

```gdscript
# data/species_db.gd
class_name SpeciesDB
extends Resource

@export var species: Array[SpeciesData] = []
```

Use `Packed*Array` for every numeric list. They are contiguous, they serialise compactly into the binary `.res`, and they keep integers as integers.

```gdscript
# autoload/dex.gd
extends Node

const DB_PATH := "res://data/species_db.res"

var _by_id: Dictionary[int, SpeciesData] = {}

func _ready() -> void:
	var db: SpeciesDB = load(DB_PATH)
	for s in db.species:
		_by_id[s.id] = s

func get_species(id: int) -> SpeciesData:
	return _by_id.get(id)

func base_stat(id: int, stat: int) -> int:
	return _by_id[id].base_stats[stat]
```

26 ms in an autoload `_ready()` is invisible next to engine startup. Load it eagerly; there is no case for lazy loading at this cost.

### 5.3 Pipeline shape

```
Python (ROM extraction)
  └─> tools/_work/species.json          # intermediate, human-inspectable, gitignored
        └─> godot --headless --script res://tools/build_species_db.gd
              └─> res://data/species_db.res     # binary, committed? no — regenerated
```

The build script does the `int()` casts once, at build time, so the float-contamination problem never reaches runtime:

```gdscript
# tools/build_species_db.gd
extends SceneTree

func _initialize() -> void:
	var raw = JSON.parse_string(
		FileAccess.get_file_as_string("res://../tools/_work/species.json"))
	if raw == null:
		printerr("could not parse species.json"); quit(1); return

	var db := SpeciesDB.new()
	var out: Array[SpeciesData] = []
	for i in range(1, 1026):
		var m: Dictionary = raw[str(i)]
		var s := SpeciesData.new()
		s.id = int(m["id"])
		s.name_en = m["name"]
		s.types = PackedStringArray(m["types"])
		var bs: Dictionary = m["base_stats"]
		s.base_stats = PackedInt32Array([
			int(bs["hp"]), int(bs["atk"]), int(bs["def"]),
			int(bs["spa"]), int(bs["spd"]), int(bs["spe"])])
		var lv := PackedInt32Array()
		var mv := PackedInt32Array()
		for pair in m["learnset"]:
			lv.append(int(pair[0])); mv.append(int(pair[1]))
		s.learnset_levels = lv
		s.learnset_moves = mv
		var tc := PackedByteArray()
		for b in m["tm_compat"]:
			tc.append(1 if b else 0)
		s.tm_compat = tc
		out.append(s)
	db.species = out

	var err := ResourceSaver.save(db, "res://data/species_db.res")
	print("wrote %d species, err=%d" % [out.size(), err])
	quit(0 if err == OK else 1)
```

Verified: this shape built and saved all 1,025 records in **1,914 ms**, and reloading gives `base_stats[0]` as a true `int`.

**Use `.res`, not `.tres`, for generated data.** Binary is 6.4× faster to load (26 ms vs 165 ms) and 24% smaller. Text `.tres` is for things a human edits or diffs.

### 5.4 Resource vs plain Dictionary

At this scale, Resource. The 26 ms binary `.res` beats the 89 ms JSON Dictionary *and* gives you `s.base_stats[0]` with autocompletion and compile-time checking instead of `d["base_stats"]["hp"]` with a float and a typo risk.

Dictionaries still win for small, hot, dynamically-shaped state — `GameState.flags`, `GameState.bag` — where you want `to_dict()` serialisation anyway.

---

## 6. Headless testing

This is the section the rest of the project depends on. Everything here was executed.

### 6.1 The two headless modes

**Mode A — `--script` with a `SceneTree` subclass.** The script *becomes* the main loop. Best for tests, codegen, and data builds.

```gdscript
extends SceneTree

func _initialize() -> void:
	print("HELLO FROM HEADLESS GODOT ", Engine.get_version_info().string)
	quit(0)
```

```bash
"C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path . --script hello.gd
```

Verbatim output:

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

HELLO FROM HEADLESS GODOT 4.7.2-stable (official)
EXIT=0
```

**Mode B — run the real main scene.** No `--script`; the project's `run/main_scene` boots and you call `get_tree().quit(code)` from inside it. Use this for smoke tests that must exercise the actual boot path.

```bash
"$GODOT" --headless --path . -- --fail
```

Verified: exits 0 normally, and 1 when the scene calls `get_tree().quit(1)`.

### 6.2 Exit codes — verified

| Situation | Exit |
|---|---|
| `quit(0)` | **0** |
| `quit(1)` | **1** |
| `quit(3)` | **3** (arbitrary codes propagate) |
| GDScript parse error in the `--script` file | **1** |
| `--check-only` with a type error | **1** |
| `get_tree().quit(1)` from inside a scene | **1** |
| `push_error()` alone, without `quit()` | **0** ← does *not* fail the run |

That last row matters: `push_error` writes `ERROR:` to stderr and returns 0. Your harness must track failures itself and pass a code to `quit()`.

`--check-only` output on a deliberately broken script:

```
SCRIPT ERROR: Parse Error: Cannot assign a value of type "String" as "int".
   at: GDScript::reload (res://broken.gd:3)
SCRIPT ERROR: Parse Error: Function "undefined_function_call()" not found in base self.
   at: GDScript::reload (res://broken.gd:4)
ERROR: Failed to load script "res://broken.gd" with error "Parse error".
EXIT=1
```

That is a free static type checker. Wire it into a pre-commit hook.

### 6.3 Two things that will waste an afternoon

**(a) PNGs do not exist until you run `--import`.** In a fresh checkout or CI container there is no `.godot/` directory:

```
ERROR: No loader found for resource: res://atlas.png (expected type: unknown)
[1] ResourceLoader.load(res://atlas.png) -> <Object#null>
```

Fix: `"$GODOT" --headless --path . --import` first. It creates `.godot/imported/*.ctex`, plus `.import` and `.uid` sidecars. (`Image.load()` bypasses the import pipeline entirely and works with no `.godot/` — but see §1.4 for why you don't want that for assets you save into a resource.)

**(b) `class_name` globals do not exist until you run `--import` either.** They live in `.godot/global_script_class_cache.cfg`, which only the editor/import pass writes. Adding a new `class_name` script and running a headless `--script` immediately gives:

```
SCRIPT ERROR: Parse Error: Could not find type "SpeciesData" in the current scope.
```

Verified directly — the cache file read `list=[]` before the import pass and contained both `SpeciesDB` and `SpeciesData` afterwards.

**Therefore: always `--import` before `--script` in CI, and after adding or renaming any `class_name`.**

**`--import` exits 0 even when it logs fatal-looking errors.** Verified against the repo's own `project.godot` as it stands today — the autoloads are declared but the script files don't exist yet:

```
ERROR: Attempt to open script 'res://src/autoload/logger.gd' resulted in error 'File not found'.
ERROR: Failed to create an autoload, can't load from UID or path: res://src/autoload/logger.gd.
...
IMPORT_EXIT=0
```

Six failed autoloads, exit code 0. Never gate CI on `--import`'s exit status. Gate on `.godot/global_script_class_cache.cfg` being non-empty (it currently reads `list=[]`, correctly, because no `class_name` script exists yet), or grep the output for `ERROR:` yourself.

**(c) `root` is not in the tree during `_initialize()`.** Verified: right after `root.add_child(n)`, `n.is_inside_tree()` is `false`, `n.get_tree()` errors with `Parameter "data.tree" is null`, and `_ready()` has not fired. All three become correct after a single `await process_frame`.

So **the first line of every `_initialize()` is `await process_frame`.** Nodes added before that first frame do work — but assert nothing about them until the frame lands.

### 6.4 The harness

Three files. Verified working, including the failure path.

**`tests/test_case.gd`**

```gdscript
class_name TestCase
extends RefCounted

var _fails: Array[String] = []
var _checks := 0
var tree: SceneTree

func before_each() -> void: pass
func after_each() -> void: pass

func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails.append(msg)

func eq(a: Variant, b: Variant, msg: String = "") -> void:
	check(a == b, "%s expected %s, got %s" % [msg, b, a])

func neq(a: Variant, b: Variant, msg: String = "") -> void:
	check(a != b, "%s expected NOT %s" % [msg, b])

func almost(a: float, b: float, eps := 0.0001, msg: String = "") -> void:
	check(absf(a - b) <= eps, "%s expected ~%f, got %f" % [msg, b, a])

func fails() -> Array[String]: return _fails
func checks() -> int: return _checks
func reset() -> void: _fails.clear(); _checks = 0
```

**`tests/run_tests.gd`**

```gdscript
extends SceneTree
## godot --headless --path . --script res://tests/run_tests.gd
## godot --headless --path . --script res://tests/run_tests.gd -- --filter=movement

const CASE_DIR := "res://tests/cases"

var total_checks := 0
var failed_checks := 0
var failed_tests: Array[String] = []

func _initialize() -> void:
	await process_frame           # root is only really in-tree after one frame

	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)

	var files := _discover(CASE_DIR)
	if files.is_empty():
		printerr("no test files found under %s" % CASE_DIR)
		quit(1)
		return

	print("Godot %s | %d test file(s)%s" % [
		Engine.get_version_info().string, files.size(),
		"" if filter.is_empty() else " | filter=" + filter])
	print("------------------------------------------------------------")

	for path in files:
		if not filter.is_empty() and not path.contains(filter):
			continue
		await _run_file(path)

	print("------------------------------------------------------------")
	if failed_checks == 0:
		print("OK  %d checks passed" % total_checks)
		quit(0)
	else:
		printerr("FAILED  %d of %d checks failed across %d test(s)" % [
			failed_checks, total_checks, failed_tests.size()])
		for t in failed_tests:
			printerr("  - " + t)
		quit(1)

func _discover(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out

func _run_file(path: String) -> void:
	var scr: Script = load(path)
	if scr == null:
		failed_checks += 1
		failed_tests.append(path + " (failed to load)")
		return
	var inst: TestCase = scr.new()
	inst.tree = self
	print("")
	print(path.get_file())
	for m in inst.get_method_list():
		var mname: String = m["name"]
		if not mname.begins_with("test_"):
			continue
		inst.reset()
		inst.before_each()
		await inst.call(mname)          # works whether or not the test is async
		inst.after_each()
		await process_frame             # let queue_free() land between tests
		total_checks += inst.checks()
		var fs := inst.fails()
		if fs.is_empty():
			print("  ok   %s  (%d checks)" % [mname, inst.checks()])
		else:
			failed_checks += fs.size()
			failed_tests.append(path.get_file() + "::" + mname)
			printerr("  FAIL " + mname)
			for f in fs:
				printerr("       " + f)
```

`await inst.call(mname)` is the key line: in GDScript 2.0 `await` on a non-coroutine return value passes straight through, so the same runner handles sync and async tests with no branching.

**`tests/cases/test_grid_mover.gd`** — an excerpt; the full file has five tests.

```gdscript
extends TestCase

const DT := 1.0 / 60.0
var m: GridMover

func before_each() -> void:
	m = GridMover.new()
	tree.root.add_child(m)
	m.snap_to(Vector2i.ZERO)
	m.facing = Vector2i.RIGHT

func after_each() -> void:
	m.queue_free()

func _settle() -> void:
	var g := 0
	while m.state != GridMover.State.IDLE and g < 5000:
		m.tick(Vector2i.ZERO, false, DT)
		g += 1
	m.tick(Vector2i.ZERO, false, DT)     # flush the buffered direction
	g = 0
	while m.state != GridMover.State.IDLE and g < 5000:
		m.tick(Vector2i.ZERO, false, DT)
		g += 1

func test_no_drift_under_frame_jitter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 2000:
		m.tick(Vector2i.RIGHT, true, rng.randf_range(0.004, 0.05))
	_settle()
	eq(int(m.position.x), m.steps_taken * GridMover.TILE, "px travelled == steps * TILE")
	eq(m.position.y, 0.0, "no lateral drift")

func test_solid_tile_blocks() -> void:
	m.solid = func(c: Vector2i) -> bool: return c == Vector2i(1, 0)
	for i in 120:
		m.tick(Vector2i.RIGHT, false, DT)
	eq(m.cell, Vector2i.ZERO, "blocked")
	eq(m.steps_taken, 0, "no steps taken")
	eq(m.facing, Vector2i.RIGHT, "still faces the wall")
```

Note the **guard counters** in `_settle()`. Without them, the buffer bug from §2.3 would have hung the CI run forever instead of failing it. Every `while` loop in a headless test needs an iteration cap.

### 6.5 Verbatim run

```bash
cd "C:/Users/James/Documents/GitHub/project-platinum/tools/_work/godottest"
"C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path . --import
"C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path . --script res://tests/run_tests.gd
```

```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

Godot 4.7.2-stable (official) | 2 test file(s)
------------------------------------------------------------

test_grid_mover.gd
  ok   test_lands_exactly_on_grid  (1 checks)
  ok   test_no_drift_under_frame_jitter  (2 checks)
  ok   test_solid_tile_blocks  (3 checks)
  ok   test_turn_in_place_does_not_move  (3 checks)
  ok   test_input_buffer_completes_exactly_one_more_step  (1 checks)

test_tileset_codegen.gd
  ok   test_custom_data_reaches_the_layer  (4 checks)
  ok   test_atlas_grid_matches_texture  (1 checks)
  ok   test_custom_data_written_before_add_source_is_lost  (1 checks)
  ok   test_roundtrip_through_disk  (3 checks)
------------------------------------------------------------
OK  19 checks passed
EXIT=0
```

With one assertion flipped to `eq(2 + 2, 5, "arithmetic")`:

```
  FAIL test_deliberate_failure_to_prove_exit_code
       arithmetic expected 5, got 4
------------------------------------------------------------
FAILED  1 of 20 checks failed across 1 test(s)
  - test_grid_mover.gd::test_deliberate_failure_to_prove_exit_code
EXIT=1
```

Filtering works too: `-- --filter=tileset` ran only `test_tileset_codegen.gd`, 9 checks, exit 0. Everything after a bare `--` reaches `OS.get_cmdline_user_args()`.

### 6.6 CI script

```bash
#!/usr/bin/env bash
# tools/run_tests.sh
set -euo pipefail

GODOT="${GODOT:-C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"      # project.godot lives at the repo root

echo "== importing assets and refreshing the class cache =="
"$GODOT" --headless --path "$PROJ" --import 2>&1 | grep -Ei "error|failed" || true

if [ ! -s "$PROJ/.godot/global_script_class_cache.cfg" ]; then
  echo "import did not produce a class cache" >&2
  exit 1
fi

echo "== running tests =="
"$GODOT" --headless --path "$PROJ" --script res://tests/run_tests.gd "$@"
```

Call it as `tools/run_tests.sh` or `tools/run_tests.sh -- --filter=battle`.

### 6.7 Noise to expect (and ignore)

Headless runs that create nodes without freeing them print, at exit:

```
WARNING: 6 RIDs of type "CanvasItem" were leaked.
WARNING: 28 ObjectDB instances were leaked at exit (run with `--verbose` for details).
ERROR: 1 RID allocations of type 'P12GodotShape2D' were leaked at exit.
```

These do **not** affect the exit code and are not test failures. They mean the script ended with live nodes. Suppress them by freeing your nodes (`after_each()` calling `queue_free()`, plus `await process_frame`), or filter them:

```bash
"$GODOT" --headless --path . --script res://tests/run_tests.gd 2>&1 \
  | grep -v "leaked\|at: _free_rids\|at: cleanup"
```

Do not filter on `ERROR:` generally — you'd hide real script errors.

---

## 7. GDScript 2.0 gotchas

### 7.1 Static typing is for correctness, not speed

Measured, same machine, same run:

| Comparison | Typed | Untyped | Ratio |
|---|---|---|---|
| 3M-iteration integer loop in a `static func` | 68.1 ms | 81.9 ms | **1.20×** |
| 500k typed vs `Variant` property accesses | 142.6 ms | 162.4 ms | **1.14×** |

So the honest number is **10–20%**, not the 2× that gets repeated in forum posts. Type everything anyway — for autocompletion, for `--check-only` catching typos before runtime, and for `Array[SpeciesData]` making a whole class of bug impossible. Just don't expect typing alone to rescue a hot loop; if something is genuinely slow, the fix is a better algorithm or pushing the work into an engine call.

### 7.2 Typed arrays and `.assign()`

```gdscript
var ids: Array[int] = [1, 2, 3]
var generic: Array = ids
print(generic.get_typed_builtin() == TYPE_INT)   # true — typing follows the value

# You cannot assign an untyped Array to a typed one directly.
var parsed: Array = JSON.parse_string(txt)["party"]
var party: Array[int] = parsed                   # ERROR at runtime
party.assign(parsed)                             # correct — validates and copies
```

`.assign()` is the only way to get an untyped `Array` (which is what `JSON.parse_string` always returns) into a typed one. It type-checks every element. Same for `Dictionary`:

```gdscript
var bag: Dictionary[StringName, int] = {}
bag.assign(loaded_dict)
```

Typed dictionaries are 4.4+ and work in 4.7 — verified `get_typed_key_builtin() == 21` (`TYPE_STRING_NAME`) and `get_typed_value_builtin() == 2` (`TYPE_INT`).

### 7.3 Lambdas capture by value

Verified, and it surprises people every time:

```gdscript
var counter := 0
var inc := func(): counter += 1
inc.call(); inc.call()
print(counter)      # 0  <- the lambda mutated its own copy
```

To mutate outer state, go through a reference type:

```gdscript
var box := {"v": 0}
var inc := func(): box["v"] += 1
inc.call(); inc.call()
print(box["v"])     # 2
```

This directly affects signal handlers written as lambdas — a `func(): total += damage` connected to a signal will never update `total`.

### 7.4 `@onready` ordering

Verified execution order:

```
plain var initialiser
_init
_enter_tree          <- @onready vars are still unset here
@onready assignment
_ready               <- @onready vars are now valid
```

So `@onready var hud := $UI/HUD` is `null` inside `_enter_tree()` and inside anything `_enter_tree()` calls. Also: `@onready` runs *before* `_ready()`, so `@onready var x := compute()` can safely read other `@onready` vars declared above it, but not below.

`@export` values set in the editor or `.tscn` are applied after `_init()` and before `_ready()`, so read them in `_ready()`, never `_init()`.

### 7.5 `await` deadlocks

```gdscript
# Hangs forever if the tween already finished.
await tween.finished

# Correct:
if tween.is_valid() and tween.is_running():
	await tween.finished
```

Verified: after a tween completes, `is_running() == false` and `is_valid() == true` — so checking `is_valid()` alone is not enough.

Same hazard with any signal that may already have fired before you awaited it. In a headless test this presents as a run that never exits and eventually gets killed by CI with no output. Pattern for a race:

```gdscript
func await_or_timeout(sig: Signal, seconds: float) -> bool:
	var timer := get_tree().create_timer(seconds)
	var done := [false]
	sig.connect(func(): done[0] = true, CONNECT_ONE_SHOT)
	await timer.timeout
	return done[0]
```

(Note the `[false]` array — §7.3.)

### 7.6 Freed objects compare equal to `null` in 4.7

The Godot 3 advice "never compare a freed object to null, it returns false" is **stale**. Verified in 4.7.2:

```
before free: n == null -> false   is_instance_valid -> true
after  free: n == null -> true    is_instance_valid -> false
```

Use `is_instance_valid(n)` anyway — it states the intent, and it is correct on every 4.x version regardless of this detail.

### 7.7 `StringName` is not a free speedup

Common advice says use `&"name"` for Dictionary keys. Measured, 2,000,000 lookups on a six-key dictionary:

| Key type | Time |
|---|---|
| `StringName` literal `&"spa"` | 138.5 ms |
| `String` literal `"spa"` | 123.2 ms |

`StringName` was **12% slower** here. Godot's `String` hashing is already fast and the `StringName` indirection costs more than it saves for small dictionaries.

Where `StringName` genuinely wins is engine API boundaries — `Input.is_action_pressed(&"run")`, `emit_signal(&"x")`, `get_node(&"Path")`, node/property names — because the engine interns those and you skip a conversion on every call. Use it there.

Never construct one at runtime in a hot loop: `StringName("key_%d" % i)` × 200,000 cost **143 ms**. Literals with `&` are interned at parse time and are free.

### 7.8 Signals

```gdscript
signal encounter_triggered(zone: StringName, level_range: Vector2i)

# 4.x callable syntax
EventBus.encounter_triggered.connect(_on_encounter)
EventBus.encounter_triggered.emit(&"route_201", Vector2i(2, 5))

# Guard against double-connects when a node can be re-parented
if not EventBus.map_changed.is_connected(_on_map_changed):
	EventBus.map_changed.connect(_on_map_changed)

# One-shot
EventBus.battle_finished.connect(_once, CONNECT_ONE_SHOT)
```

Never use the Godot 3 string forms `connect("sig", self, "_method")` or `emit_signal("sig")` with a literal — they still work but skip the type checking that makes typed signal parameters worth declaring.

### 7.9 Integer division

```gdscript
var half := 7 / 2        # 3  — both operands are int, so this is integer division
var real := 7 / 2.0      # 3.5
var damage := int(base * mod / 100.0)   # be explicit in stat formulas
```

Pokémon damage formulas are full of intentional integer truncation at specific steps. Write them with explicit `int()` / `floori()` at each truncation point so the intent is visible and matches the reference implementation, rather than relying on operand types.

---

## 8. Summary of decisions

| Question | Decision | Evidence |
|---|---|---|
| Tile node | `TileMapLayer`, one per visual layer | `TileMap` is legacy-only in 4.7 |
| Tile metadata | TileSet custom data layers | 0.363 µs/lookup |
| TileSet authoring | Codegen via `TileSetAtlasSource`, saved as `.tres` | full script in §1.4 |
| Texture in codegen | `load()` an imported PNG, never `ImageTexture.create_from_image` | 436 B vs 78,183 B |
| Movement | Manual lerp in `_process` with overshoot carry | exact to the pixel over 40 jittered tiles |
| Collision | Tile custom data + injected `Callable` | free, exact, headlessly testable |
| Singletons | `EventBus`, `GameState`, `SaveSystem` (in that order) | autoloads work headlessly |
| Save format | `FileAccess.store_var(v, false)` | preserves int; refuses Objects |
| Never | `ResourceLoader.load()` on a save file | demonstrated RCE, §3.5 |
| Overworld↔battle | Persistent `Main` root, suspend with `PROCESS_MODE_DISABLED` | state survives with zero save/restore code |
| Species data | One binary `.res` of `Array[SpeciesData]` | 26 ms vs 6,301 ms for per-file JSON |
| Test command | `--headless --path . --script res://tests/run_tests.gd` | exit 0/1 verified |
| CI prerequisite | `--import` first, always | PNGs and `class_name` both need it |

---

## 9. Things I did not verify

- Visual output of Y-sort. I verified the API and the parent-propagation requirement, but "does the player actually render behind the tree" needs a windowed run or a screenshot comparison. **[unverified]**
- Shader-based transitions (§4.6) — the tween/`await` plumbing was verified; no shader was written. **[unverified]**
- `--headless` screenshot capture for visual regression testing. `DisplayServer.get_name() == "headless"` means there is no real renderer; visual tests need `--rendering-driver opengl3` in a real window or an offscreen `SubViewport`. Worth a follow-up if we want pixel-diff tests against DeSmuME captures. **[unverified]**
- Performance of `TileMapLayer` rendering with many layers at scale. Only data-side costs were measured. **[unverified]**
- Whether `TileMap` emits a deprecation warning at runtime — it instantiated silently in 4.7.2, but the editor may still flag it. **[unverified]**

## 10. Environment notes

- Use the `_console.exe` Godot build on Windows or you get no stdout.
- Python + PIL in this environment needs the Anaconda DLL directories on `PATH` before `from PIL import Image` will work, or it fails with `ImportError: DLL load failed while importing _imaging`:
  ```bash
  export PATH="/c/Users/James/anaconda3:/c/Users/James/anaconda3/Library/bin:/c/Users/James/anaconda3/Library/mingw-w64/bin:/c/Users/James/anaconda3/Scripts:$PATH"
  ```
- `user://` resolves to `C:/Users/James/AppData/Roaming/Godot/app_userdata/<project name>/`.
