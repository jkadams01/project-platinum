extends Node2D
## Tile-locked grid movement: manual lerp with overshoot carry, a one-deep input
## buffer, a pivot-before-stepping turn, a run toggle, and four-direction facing.
##
## NOT A Tween, AND NOT A PHYSICS BODY -- and both of those were measured, not
## guessed (docs/research/godot-architecture.md 2.1):
##   * A per-step Tween lands exactly on target, but cannot be cleanly redirected
##     mid-step, discards the leftover frame time at every tile boundary (held-down
##     running visibly hitches), and awaiting a dead tween hangs forever.
##   * CharacterBody2D + move_and_slide brings float drift, wall-sliding that
##     Pokemon movement never does, and a fight with the physics tick to stay
##     tile-aligned.
## Manual lerp in _process is deterministic, cancellable, drift-free and
## testable with no frames, no physics server and no scene.
##
## THE TWO LOAD-BEARING LINES, both of which were bugs first:
##   `_elapsed = over`  carries the leftover time of the frame that crossed a tile
##       boundary into the next step. Without it every tile discards up to a frame
##       and a held run hitches once per tile. With it, 40 tiles under randomised
##       4-50 ms frames land on exactly 656 px with zero accumulated error.
##   `_buffered = Vector2i.ZERO`  clears the buffer as it is consumed. The first
##       version did not, and the mover chained off the stale buffer forever --
##       the headless suite caught it at 1,399 tiles east.
##
## Use `_process`, not `_physics_process`: there is no physics here, and _process
## runs at display rate so the interpolation is as smooth as the monitor allows.
## `2d/snap/snap_2d_transforms_to_pixel` snaps the RENDERED transform while
## leaving the logical float `position` alone, so the sprite never shimmers on a
## half pixel and the drift-free maths above still operates on exact values. Do
## not "fix" sub-pixel positions by rounding `position` yourself; that
## reintroduces the accumulation error the overshoot carry exists to prevent.

const Collision := preload("res://src/systems/collision.gd")

const TILE := 16

enum State { IDLE, TURNING, MOVING }

## How the run button behaves. HOLD is vanilla Running Shoes; TOGGLE is the
## accessibility option (press once, stay running).
enum RunMode { HOLD, TOGGLE }

@export var walk_time := 0.24       ## seconds per tile, walking
@export var run_time := 0.12        ## seconds per tile, running
@export var turn_time := 0.08       ## pivot-in-place delay before a step
@export var ledge_time := 0.34      ## a ledge hop covers two tiles
@export var mount_time := 0.40      ## surf / climb / waterfall / smash / cut
@export var ledge_arc := 10.0       ## peak height of the hop, in pixels
@export var run_mode: RunMode = RunMode.HOLD

var state: State = State.IDLE
var facing := Vector2i.DOWN
var cell := Vector2i.ZERO
var steps_taken := 0
var bumps := 0
## Flipped by [method toggle_run] when `run_mode == TOGGLE`.
var run_latched := false
## Set true while a verb animation owns the frame; the mover ignores input.
var busy := false

## `func(from: Vector2i, dir: Vector2i) -> Dictionary` -- a Collision result,
## normally Traversal.attempt. The default refuses every step, so a mover that
## was never wired up stands still instead of walking through the world.
var resolver: Callable = func(_from: Vector2i, _dir: Vector2i) -> Dictionary:
	return {"kind": Collision.Result.BLOCKED, "target": Vector2i.ZERO, "verb": "",
		"reason": "no-resolver", "message": ""}

## `func(cell: Vector2i, result: Dictionary) -> void`, called once per landing.
var on_arrive: Callable = Callable()

var _buffered: Vector2i = Vector2i.ZERO   ## exactly one queued direction
var _elapsed := 0.0
var _dur := 0.0
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _arc := 0.0
var _step: Dictionary = {}                ## the result driving the current step


func _ready() -> void:
	snap_to(cell)


## Place the player without animating. Used on map load and after a warp.
func snap_to(c: Vector2i) -> void:
	cell = c
	position = Vector2(c * TILE)
	state = State.IDLE
	_buffered = Vector2i.ZERO
	_elapsed = 0.0
	_arc = 0.0
	_step = {}


func is_moving() -> bool:
	return state == State.MOVING


## Press-handler for RunMode.TOGGLE.
func toggle_run() -> void:
	run_latched = not run_latched


## True when this frame should move at run speed.
func running_now(held: bool) -> bool:
	return run_latched if run_mode == RunMode.TOGGLE else held


# --------------------------------------------------------------------------
# The controller
# --------------------------------------------------------------------------

## Call every frame with the held direction (Vector2i.ZERO for none) and the run
## flag. Separated from _process so headless tests can drive exact frame times.
func tick(dir: Vector2i, running: bool, delta: float) -> void:
	if busy:
		dir = Vector2i.ZERO
	match state:
		State.IDLE:
			var d := dir if dir != Vector2i.ZERO else _buffered
			_buffered = Vector2i.ZERO
			if d == Vector2i.ZERO:
				return
			if d != facing:
				# DS games pivot in place before they step. Tapping a direction
				# you are not facing turns you and costs no tile.
				facing = d
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
			_apply_position()
			if _elapsed >= _dur:
				var over := _elapsed - _dur      # leftover time from this frame
				_land()
				var nxt := dir if dir != Vector2i.ZERO else _buffered
				_buffered = Vector2i.ZERO        # MUST clear, or you walk forever
				if nxt != Vector2i.ZERO and nxt == facing and not busy:
					_begin_step(nxt, running)
					if state == State.MOVING:
						_elapsed = over          # carry -> no stutter, no drift
						_apply_position()


func _process(delta: float) -> void:
	if GameState.input_locked:
		tick(Vector2i.ZERO, false, delta)
		return
	if run_mode == RunMode.TOGGLE and Input.is_action_just_pressed(&"game_run"):
		toggle_run()
	var dir := Vector2i(
		int(Input.get_axis(&"ui_left", &"ui_right")),
		int(Input.get_axis(&"ui_up", &"ui_down")))
	if dir.x != 0 and dir.y != 0:
		dir.y = 0                                # no diagonals; horizontal wins
	tick(dir, running_now(Input.is_action_pressed(&"game_run")), delta)


# --------------------------------------------------------------------------

func _begin_step(d: Vector2i, running: bool) -> void:
	facing = d
	var res: Dictionary = resolver.call(cell, d)
	var kind := int(res.get("kind", Collision.Result.BLOCKED))

	if kind == Collision.Result.BLOCKED or kind == Collision.Result.EDGE \
			or bool(res.get("blocked", false)):
		# A bump turns you and costs the turn delay -- it never moves you.
		state = State.IDLE
		bumps += 1
		return

	var target: Vector2i = res.get("target", cell + d)
	_step = res
	_from = Vector2(cell * TILE)
	_to = Vector2(target * TILE)
	_arc = ledge_arc if kind == Collision.Result.HOP else 0.0
	_dur = _duration_for(res, running)
	_elapsed = 0.0
	state = State.MOVING


func _duration_for(res: Dictionary, running: bool) -> float:
	match int(res.get("kind", Collision.Result.MOVE)):
		Collision.Result.HOP:
			return ledge_time
		Collision.Result.TRAVERSE:
			# A dismount is an ordinary step back onto land; the rest are
			# animated verbs and get their own, slower beat.
			return walk_time if String(res.get("verb", "")) == "dismount" else mount_time
	return run_time if running else walk_time


func _apply_position() -> void:
	var t := clampf(_elapsed / _dur, 0.0, 1.0)
	var p := _from.lerp(_to, t)
	if _arc > 0.0:
		# A simple parabola: 0 at both ends, -arc at the midpoint (up is -y).
		p.y -= _arc * 4.0 * t * (1.0 - t)
	position = p


func _land() -> void:
	position = _to
	cell = Vector2i(_to / TILE)
	_arc = 0.0
	_elapsed = 0.0
	steps_taken += 1
	state = State.IDLE
	GameState.player_cell = cell
	GameState.player_facing = facing
	EventBus.player_moved.emit(cell)
	if on_arrive.is_valid():
		on_arrive.call(cell, _step)
	_step = {}
