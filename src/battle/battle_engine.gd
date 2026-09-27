extends RefCounted
## The turn loop: action selection, ordering, move resolution, switching, items,
## running, fainting, EXP (through the level cap), and win/loss.
##
## Single battles only, two sides. Side 0 is the player, side 1 the opponent.
## Everything crossing the stream boundary is plain data (DATA_CONTRACT shapes),
## so no other stream has to wait for this class to exist.
##
## USAGE
## [codeblock]
## var b := BattleEngineScript.new()
## b.start({"kind": "trainer", "party": my_party, "opponent": their_party,
##          "cap": 22, "seed": 1234})
## b.submit_action(0, {"kind": "move", "move_index": 0})
## var r := b.resolve_turn()      # r.log, r.over, r.outcome
## [/codeblock]
##
## The engine never blocks: if a side has not submitted an action by the time
## `resolve_turn()` is called, one is chosen for it by ai.gd. That is what makes
## `run_to_completion()` -- and the headless tests -- possible.
##
## RNG: one seeded RandomNumberGenerator owns every roll (accuracy, damage
## spread, crits, secondary effects, status ticks, speed ties). Same seed plus
## same actions equals the same battle, which is the only way to debug a report
## of "the AI did something insane on turn 6".

const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Damage := preload("res://src/battle/damage.gd")
const TurnOrder := preload("res://src/battle/turn_order.gd")
const Exp := preload("res://src/battle/exp.gd")
const AI := preload("res://src/battle/ai.gd")
const Deps := preload("res://src/battle/deps.gd")
const Mega := preload("res://src/battle/mega.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")
const MultiHit := preload("res://src/battle/multi_hit.gd")

signal message(text: String)
signal turn_resolved(turn: int)
signal battle_over(result: Dictionary)

const PLAYER := 0
const OPPONENT := 1
const MAX_TURNS := 500

## Protect / Detect. Both are effectId 112 in data/moves.json, both +4 priority,
## both target the user. They are the PURE protection moves -- block everything,
## punish nothing -- which is why they are the pair implemented here.
##
## The punishing protections are deliberately NOT in this list: Spiky Shield (362),
## Baneful Bunker (384), Obstruct (472), King's Shield, Silk Trap and Burning
## Bulwark each owe the attacker a recoil, a poison or a stat drop, and shipping
## them as plain Protect would silently drop that half of the move. They join the
## list as their punishes land. Max Guard is a Dynamax move and is excluded by
## DATA_CONTRACT 11.4.
const PROTECT_EFFECT_IDS: Array = [112]

## Heal items the engine understands. Anything else is a no-op with a message.
const HEAL_ITEMS: Dictionary = {
	"potion": 20, "super-potion": 60, "hyper-potion": 120, "max-potion": -1,
	"full-restore": -1, "sitrus-berry": -1, "oran-berry": 10,
}
const CURE_ITEMS: Dictionary = {
	"antidote": ["poison", "toxic"], "burn-heal": ["burn"], "ice-heal": ["freeze"],
	"awakening": ["sleep"], "paralyze-heal": ["paralysis"],
	"full-heal": ["poison", "toxic", "burn", "freeze", "sleep", "paralysis"],
	"full-restore": ["poison", "toxic", "burn", "freeze", "sleep", "paralysis"],
}

var rng := RandomNumberGenerator.new()
var sides: Array = []
var battle_log: Array = []
var turn: int = 0
var over: bool = false
var outcome: String = ""          ## "" | "win" | "loss" | "run"
var kind: String = "wild"
var weather: String = ""
var weather_turns: int = 0
var level_cap: int = -1           ## -1 = ask GameState every time
## Overrides `GameState.has_key_stone()` for side 0 when not null, so a fight
## can be given (or denied) Mega Evolution without touching the save.
var player_key_stone: Variant = null
## False switches EXP off entirely -- not capped to zero, not awarded and
## discarded: never computed. Custom battles want the teams they were handed.
var award_exp: bool = true
var exp_awarded: int = 0
var money_awarded: int = 0
var awaiting_switch: int = -1     ## side that must choose a replacement, or -1
## When true the engine picks the player's actions too (tests, demos, auto-battle).
var auto_player: bool = false

var _pending: Dictionary = {}     # side -> action
var _participants: Dictionary = {}# party index -> true, for the current foe
## Mon dictionaries whose faint message has already been printed this battle.
## Kept here rather than as a key on the mon so nothing battle-only leaks into
## the save payload (GameState.party holds these very Dictionaries).
var _announced_faints: Array = []
var _run_attempts: int = 0


# --------------------------------------------------------------------------
# Setup
# --------------------------------------------------------------------------

## `setup` (DATA_CONTRACT: EventBus.battle_started payload):
## [codeblock]
## {kind: "wild"|"trainer", party: Array[Dictionary], opponent: Dictionary|Array,
##  cap: int, seed: int, trainer: Dictionary, weather: String}
## [/codeblock]
func start(setup: Dictionary) -> void:
	kind = String(setup.get("kind", "wild"))
	level_cap = int(setup.get("cap", -1))
	weather = String(setup.get("weather", ""))
	rng.seed = int(setup.get("seed", randi()))
	player_key_stone = setup.get("playerKeyStone", null)
	award_exp = bool(setup.get("awardExp", true))

	var player_party: Array = setup.get("party", [])
	var opp: Variant = setup.get("opponent", [])
	var opp_party: Array = opp if opp is Array else [opp]
	var trainer: Dictionary = setup.get("trainer", {})

	sides = [
		_make_side(player_party, false, String(setup.get("playerName", "You")), {}),
		_make_side(opp_party, true, String(trainer.get("name", "Wild")), trainer),
	]
	battle_log.clear()
	turn = 0
	over = false
	outcome = ""
	exp_awarded = 0
	money_awarded = 0
	awaiting_switch = -1
	_pending.clear()
	_run_attempts = 0
	_announced_faints.clear()
	_reset_participants()

	if kind == "wild":
		_say("A wild %s appeared!" % Stats.display_name(active(OPPONENT)))
	else:
		_say("%s wants to battle!" % String(trainer.get("name", "The opponent")))
	_say("Go! %s!" % Stats.display_name(active(PLAYER)))
	_refresh_field()

	Deps.emit("battle_started", [setup])


func _make_side(party: Array, is_ai: bool, side_name: String, trainer: Dictionary) -> Dictionary:
	var first := 0
	for i in party.size():
		if not Stats.is_fainted(party[i]):
			first = i
			break
	return {
		"party": party, "active": first, "isAi": is_ai, "name": side_name,
		"trainer": trainer, "megaUsed": false,
		"difficulty": int(trainer.get("ai", 5)),
	}


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

func active(side: int) -> Dictionary:
	var s: Dictionary = sides[side]
	var party: Array = s["party"]
	if party.is_empty():
		return {}
	return party[int(s["active"])]


func party_of(side: int) -> Array:
	return (sides[side] as Dictionary)["party"]


func bench_of(side: int) -> Array:
	var out: Array = []
	var s: Dictionary = sides[side]
	for i in (s["party"] as Array).size():
		if i != int(s["active"]) and not Stats.is_fainted((s["party"] as Array)[i]):
			out.append((s["party"] as Array)[i])
	return out


## True while `mon` carries a protection volatile. Protect / Detect write it in
## [method _apply_protect], [method _end_of_turn] clears it, and the Protect-piercing
## abilities (Unseen Fist, Piercing Drill) are what get through it.
func _is_protected(mon: Dictionary) -> bool:
	if mon.is_empty():
		return false
	return bool((mon.get("volatile", {}) as Dictionary).get("protect", false))


func has_usable(side: int) -> bool:
	for mon: Dictionary in party_of(side):
		if not Stats.is_fainted(mon):
			return true
	return false


func current_cap() -> int:
	return level_cap if level_cap >= 0 else Deps.level_cap()


## DATA_CONTRACT 11.2. True when the holder has the Key Stone, the Pokemon holds
## the matching Mega Stone -- or knows the required move, which is Mega Rayquaza's
## whole deal -- and this side has not Mega Evolved yet this battle. This is the
## gate the UI asks before drawing the button; `mega.gd` owns the rules.
func can_mega_evolve(mon: Dictionary, side: int = PLAYER) -> bool:
	return bool(mega_check(mon, side)["ok"])


## [method can_mega_evolve] with the reason attached:
## `{ok: bool, reason: String, form: Dictionary}`. `reason` is one of
## `fainted`, `already-mega`, `side-used`, `no-key-stone`, `no-form`, `no-side`,
## which is what lets a greyed-out Mega button explain itself.
func mega_check(mon: Dictionary, side: int = PLAYER) -> Dictionary:
	if side < 0 or side >= sides.size():
		return {"ok": false, "reason": "no-side", "form": {}}
	return Mega.check(mon, {
		"mega_used": bool((sides[side] as Dictionary).get("megaUsed", false)),
		"has_key_stone": _has_key_stone(side),
	})


## Who on `side` owns a Key Stone.
##
## The player's comes from `GameState.has_key_stone()` (DATA_CONTRACT 11.2), so
## no autoload means no Mega -- failing closed is right for a gimmick gate.
##
## An opponent's comes from its trainer entry: `keyStone` defaults to true, so a
## boss handed a Mega Stone in the trainer table just works, and a trainer who
## must never Mega -- every Team Galactic grunt, per the design doc -- sets
## `"keyStone": false`. A WILD Pokemon has no trainer and therefore never Megas.
func _has_key_stone(side: int) -> bool:
	if side == PLAYER:
		# DATA_CONTRACT 13: an explicit `playerKeyStone` wins, which is how a
		# custom battle enables Megas without granting the save a Key Stone.
		if player_key_stone != null:
			return bool(player_key_stone)
		var state := Deps.state()
		if state != null and state.has_method("has_key_stone"):
			return bool(state.has_key_stone())
		return false
	if kind != "trainer":
		return false
	var trainer: Dictionary = (sides[side] as Dictionary).get("trainer", {})
	return bool(trainer.get("keyStone", true))


## Mega Evolve `side`'s active Pokemon right now, marking the side as having used
## its one Mega. Returns false when the gate refuses. The turn loop calls this
## from [method _resolve_megas]; the UI may call it directly.
func mega_evolve(side: int) -> bool:
	if side < 0 or side >= sides.size():
		return false
	var s: Dictionary = sides[side]
	var gate := mega_check(active(side), side)
	if not bool(gate["ok"]):
		return false
	var res := Mega.evolve(active(side), gate["form"], {"trainer": String(s.get("name", ""))})
	if not bool(res["ok"]):
		return false
	s["megaUsed"] = true
	for m: String in (res["messages"] as Array):
		_say(m)
	# Mega Evolution is how an ability is GAINED mid-battle: mega.gd rewrote
	# mon["ability"], so the field has to be re-read right here and not only on a
	# switch-in. This is the call that turns on Mega Rayquaza's strong winds.
	_refresh_field()
	return true


## DATA_CONTRACT 11.2: Mega Evolution resolves at the START of the turn, before
## any move, and the Mega's Speed applies to that same turn's ordering. This runs
## before `TurnOrder.order()` and mutates the very Dictionaries the actions point
## at, so the sort reads the new Speed.
##
## Both sides may Mega Evolve on the same turn. They resolve in side order
## (player first), which only affects message order -- no Mega has an on-evolve
## effect, so nothing observable depends on it.
func _resolve_megas(actions: Array) -> void:
	for a: Dictionary in actions:
		if bool(a.get("mega", false)):
			mega_evolve(int(a.get("side", PLAYER)))


# --------------------------------------------------------------------------
# Action submission
# --------------------------------------------------------------------------

## `action` is one of:
## [codeblock]
## {kind: "move",   move_index: int}
## {kind: "switch", index: int}          # index into that side's party
## {kind: "item",   item: String, target: int}
## {kind: "run"}
## [/codeblock]
## Returns false (and logs nothing) when the action is illegal right now.
func submit_action(side: int, action: Dictionary) -> bool:
	if over:
		return false
	var a := action.duplicate()
	match String(a.get("kind", "")):
		"move":
			var moves: Array = active(side).get("moves", [])
			var idx := int(a.get("move_index", -1))
			if idx < 0 or idx >= moves.size():
				return false
			if int((moves[idx] as Dictionary).get("pp", 0)) <= 0:
				return false
			# A Mega request rides along with the move (DATA_CONTRACT 11.2: it
			# resolves before the move, it is not an action of its own). An
			# illegal request is dropped and the move still stands, rather than
			# refusing the whole action and stalling the turn.
			if bool(a.get("mega", false)) and not can_mega_evolve(active(side), side):
				a["mega"] = false
		"switch":
			var idx2 := int(a.get("index", -1))
			var party: Array = party_of(side)
			if idx2 < 0 or idx2 >= party.size():
				return false
			if idx2 == int((sides[side] as Dictionary)["active"]):
				return false
			if Stats.is_fainted(party[idx2]):
				return false
			# onSwitchAttempt (shadow-tag, and arena-trap / magnet-pull behind it).
			# Checked LIVE on every attempt, never latched: a trapper that faints this
			# turn traps nothing next turn. NEVER consulted for the forced replacement
			# after a faint -- that goes through switch_in(), and a trapped side with no
			# legal action would deadlock `awaiting_switch`.
			if awaiting_switch != side:
				var trap := Abilities.escape_block(active(1 - side), active(side), "switch")
				if bool(trap.get("block", false)):
					var trap_msg := String(trap.get("message", ""))
					if trap_msg != "":
						_say(trap_msg)
					return false
		"item", "run":
			pass
		_:
			return false
	_pending[side] = a
	return true


## What the AI would do for `side` this turn.
func auto_action(side: int) -> Dictionary:
	var me := active(side)
	var foe := active(1 - side)
	var moves: Array = me.get("moves", [])
	var usable := false
	for m: Dictionary in moves:
		if int(m.get("pp", 0)) > 0:
			usable = true
			break
	if not usable:
		return {"kind": "struggle"}

	# A trapped AI must not even CONSIDER switching: _execute() calls _switch_in()
	# directly and never re-validates, so a switch action that got chosen would run
	# anyway. This is the second of the three escape gates.
	var can_switch := kind == "trainer" and not bench_of(side).is_empty()
	if can_switch and bool(Abilities.escape_block(foe, me, "switch").get("block", false)):
		can_switch = false
	var chosen := AI.choose_action({
		"self": me, "foe": foe, "bench": bench_of(side), "side": side,
		"difficulty": int((sides[side] as Dictionary).get("difficulty", 5)),
		"can_switch": can_switch,
		"weather": weather,
	})
	# ai.gd indexes the *bench*; the engine wants a party index.
	if String(chosen.get("kind", "")) == "switch":
		var wanted: Dictionary = bench_of(side)[int(chosen["index"])]
		var party: Array = party_of(side)
		for i in party.size():
			if party[i] == wanted:
				return {"kind": "switch", "index": i}
		return {"kind": "move", "move_index": 0}
	# A boss handed a Mega Stone uses it the first turn it can. No cleverness:
	# holding the Mega back is never right for a one-shot buff, and the design doc
	# gives stones only to the trainers that are meant to Mega.
	if String(chosen.get("kind", "")) == "move" and can_mega_evolve(me, side):
		chosen["mega"] = true
	return chosen


# --------------------------------------------------------------------------
# The turn
# --------------------------------------------------------------------------

## Resolve one full turn. Returns
## `{turn:int, log:Array[String], over:bool, outcome:String}`.
func resolve_turn() -> Dictionary:
	if over:
		return result()
	if awaiting_switch >= 0:
		if auto_player:
			_auto_replace(awaiting_switch)
		else:
			_say("Waiting for a replacement Pokemon.")
			return result()

	turn += 1
	var start_of_turn := battle_log.size()

	var actions: Array = []
	for side in sides.size():
		var a: Dictionary = _pending.get(side, {})
		if a.is_empty():
			a = auto_action(side)
		a = a.duplicate()
		a["side"] = side
		a["mon"] = active(side)
		if String(a.get("kind", "")) == "move":
			var moves: Array = active(side).get("moves", [])
			var idx := int(a.get("move_index", 0))
			if idx >= 0 and idx < moves.size():
				a["move"] = moves[idx]
			else:
				a["kind"] = "struggle"
		actions.append(a)
	_pending.clear()

	_resolve_megas(actions)

	for a: Dictionary in TurnOrder.order(actions, rng):
		if over:
			break
		_execute(a)
		_check_faints()
		if over:
			break

	if not over:
		_end_of_turn()

	turn_resolved.emit(turn)
	var r := result()
	r["log"] = battle_log.slice(start_of_turn)
	return r


## Drive the whole battle with both sides on AI. Used by tests and demos.
func run_to_completion(max_turns: int = MAX_TURNS) -> Dictionary:
	auto_player = true
	var guard := 0
	while not over and guard < max_turns:
		guard += 1
		resolve_turn()
	if not over:
		_finish("draw")
	return result()


func result() -> Dictionary:
	return {
		"turn": turn, "over": over, "outcome": outcome,
		"log": battle_log.duplicate(),
		"expAwarded": exp_awarded, "money": money_awarded,
		"party": party_of(PLAYER),
	}


# --------------------------------------------------------------------------
# Execution
# --------------------------------------------------------------------------

func _execute(action: Dictionary) -> void:
	var side := int(action.get("side", 0))
	var mon := active(side)
	if Stats.is_fainted(mon):
		return                      # it fainted earlier this turn; its action is lost

	match String(action.get("kind", "move")):
		"switch":
			_switch_in(side, int(action.get("index", -1)), true)
		"item":
			_use_item(side, String(action.get("item", "")), int(action.get("target", -1)))
		"run":
			_try_run(side)
		"struggle":
			_say("%s has no moves left!" % Stats.display_name(mon))
		_:
			_use_move(side, action.get("move", {}))


func _use_move(side: int, move: Dictionary) -> void:
	var attacker := active(side)
	var defender := active(1 - side)
	if move.is_empty():
		return

	var before := Status.before_move(attacker, rng)
	for m: String in before["messages"]:
		_say(m)
	# onFlinch fires exactly where the flinch MESSAGE was printed -- the branch
	# Status.before_move() reports with its additive "flinched" key. The bearer is
	# the one that flinched and the turn is still lost, so Steadfast's Speed stage
	# is felt on the NEXT turn.
	if bool(before.get("flinched", false)):
		_apply_ability_boosts(attacker, Abilities.flinch(attacker,
			{"name": Stats.display_name(attacker)}))
	if not bool(before["can_move"]):
		return

	move["pp"] = maxi(int(move.get("pp", 0)) - 1, 0)

	# Using anything other than a protection move breaks the consecutive-use chain,
	# so Protect is cheap again next turn. Kept here -- on the USE, not at end of
	# turn -- because that is the event the games key it to.
	if not PROTECT_EFFECT_IDS.has(int(move.get("effectId", -1))):
		var streak_vol: Dictionary = attacker.get("volatile", {})
		if int(streak_vol.get("protect_streak", 0)) != 0:
			streak_vol["protect_streak"] = 0
			attacker["volatile"] = streak_vol

	# onModifyMoveType (dragonize and the -ate family). The PP decrement above had
	# to land on the mon's LIVE move dictionary -- resolve_turn() puts that very
	# dictionary into the action -- so the rewrite happens immediately after it and
	# every later read goes through a DUPLICATE. Mutating in place would make
	# Mega Feraligatr's Body Slam permanently Dragon-type in the save.
	var move_mods := Abilities.modify_move(attacker, move)
	if not move_mods.is_empty():
		move = move.duplicate(true)
		if move_mods.has("type"):
			move["type"] = String(move_mods["type"])
		var move_power_mult := float(move_mods.get("power_mult", 1.0))
		var move_power := int(move.get("power", 0))
		if move_power > 0 and not is_equal_approx(move_power_mult, 1.0):
			# A POWER multiplier, folded in before the base formula reads `power`;
			# 85 -> 102 for Dragonize's 1.2x. The epsilon is not cosmetic: binary
			# 1.2 is a hair under 1.2, so a bare floori() of 85 * 1.2 gives 101.
			move["power"] = maxi(1, floori(float(move_power) * move_power_mult + 1e-6))

	_say("%s used %s!" % [Stats.display_name(attacker), String(move.get("name", "a move"))])

	if not Stats.accuracy_check(move.get("accuracy", null), attacker, defender, rng):
		_say("%s's attack missed!" % Stats.display_name(attacker))
		return

	# --- protection -------------------------------------------------------
	# Protect / Detect set `volatile["protect"]` (see _apply_protect), so this gate
	# is LIVE: it is what Unseen Fist and Piercing Drill pierce. `flags` names the
	# moves Protect actually affects, so a self-targeting status move is never
	# gated, and a mon with nothing protecting it takes the same path as before.
	var pierce_mult := 1.0
	var pierced := false
	if _is_protected(defender) and Abilities.move_has_flag(move, "protect"):
		var pierce := Abilities.protect_check(attacker, defender, move)
		if not bool(pierce.get("pierce", false)):
			_say("%s protected itself!" % Stats.display_name(defender))
			return
		pierced = true
		pierce_mult = float(pierce.get("damage_mult", 1.0))

	var category := String(move.get("category", "status"))
	if category == "status":
		_apply_status_move(side, move)
		return

	# --- the hit plan, decided ONCE (hook order step 7) --------------------
	# How many times a move hits is the MOVE's business (multi_hit.gd: Pin Missile
	# 2-5, Gear Grind 2, Triple Kick 3 with per-hit accuracy), which the attacker's
	# ability may then override -- Skill Link takes the range maximum and switches
	# per-hit accuracy off, Parental Bond adds a second hit to a single-hit move.
	# Fixed before the loop, so losing the ability mid-move cannot shrink it (Gen 5+),
	# and the ONE accuracy check above covers the whole move rather than one per hit.
	var plan := MultiHit.plan(attacker, move, rng)
	var hits := int(plan["hits"])
	var plan_by := String(plan.get("by", ""))
	var total_dealt := 0
	var landed := 0

	for hit_index: int in hits:
		if Stats.is_fainted(attacker):
			break
		# Per-hit accuracy exists only for Triple Kick / Triple Axel; hit 0 is the
		# check already made above. Skill Link is precisely what removes the rest.
		if hit_index > 0 and not bool(plan["single_accuracy"]):
			if not Stats.accuracy_check(move.get("accuracy", null), attacker, defender, rng):
				_say("%s's attack missed!" % Stats.display_name(attacker))
				break

		# onWeatherView (mega-sol): the weather the ATTACKER'S move sees. The field's
		# real weather is untouched -- residual damage, the opponent's moves and
		# _end_of_turn all still read `weather`.
		# `weather` is the attacker's VIEW; `field_weather` is what is really on the
		# field. Both are needed and they are not the same: Mega Sol resolves its own
		# moves under sun, but Delta Stream's strong winds protect every Flying-type
		# on the field whoever is attacking, so the type chart reads the field state.
		var ctx: Dictionary = {
			"rng": rng, "weather": Abilities.weather_view(attacker, weather),
			"field_weather": weather,
			"hit_index": hit_index, "hits": hits, "hit_plan_by": plan_by,
		}
		if pierced:
			ctx["protect_pierced"] = true
			if not is_equal_approx(pierce_mult, 1.0):
				ctx["damage_mult"] = pierce_mult
		if String(move.get("effect", "")).contains("increased-chance-for-a-critical-hit"):
			ctx["crit_stage"] = 1
		# Triple Kick's 10/20/30 ramp. Skill Link guarantees the kicks; it does not
		# flatten the ramp.
		var escalate := MultiHit.power_mult_for_hit(plan, hit_index)
		if not is_equal_approx(escalate, 1.0):
			ctx["power_mult"] = escalate
		var hit := Damage.compute(attacker, defender, move, ctx)

		if bool(hit["immune"]):
			_say("It doesn't affect %s..." % Stats.display_name(defender))
			return

		var dealt := -Stats.apply_hp_delta(defender, -int(hit["damage"]))
		total_dealt += dealt
		landed += 1
		if bool(hit["crit"]):
			_say("A critical hit!")
		if hit_index == 0:
			var eff_msg := Damage.effectiveness_message(float(hit["effectiveness"]),
				Stats.display_name(defender))
			if eff_msg != "":
				_say(eff_msg)

		var ko := Stats.is_fainted(defender)

		# on_hit_taken / onContactHit fire here -- after the damage lands, BEFORE any
		# faint break and before _check_faints() reverts a Mega. That ordering is what
		# lets Spicy Spray burn the attacker even when the hit killed its bearer, and
		# it is INSIDE the loop because Spicy Spray fires once per hit.
		var taken := Abilities.hit_taken(attacker, defender, move, {
			"damage": dealt, "rng": rng, "crit": bool(hit["crit"]),
			"hit_index": hit_index, "ko": ko,
		})
		for m: String in (taken.get("messages", []) as Array):
			_say(m)

		# onAfterHit, per hit, with `ko` true only when THIS hit fainted the target.
		# Firing it from the damage path is what keeps eelevate's snowball to DIRECT
		# KOs: _check_faints() cannot say who did the killing and would also credit
		# recoil, hazards and residual damage. A Parental Bond pair that KOs on hit 1
		# therefore pays the bonus exactly once.
		var after := Abilities.after_hit(attacker, defender, move, {
			"damage": dealt, "dealt": dealt, "ko": ko,
			"hit_index": hit_index, "crit": bool(hit["crit"]),
		})
		_apply_ability_boosts(attacker, after)

		# Secondaries roll INDEPENDENTLY PER HIT, and drain heals per hit. That is
		# the half of Parental Bond that actually broke the ability.
		_apply_damage_side_effects(side, move, dealt)

		if ko:
			break

	if landed > 1:
		_say("Hit %d time(s)!" % landed)

	# Recoil ONCE, from the SUMMED damage (hook order step 9).
	_apply_recoil(side, move, total_dealt)


## Recoil, computed from the TOTAL damage the move dealt and charged once.
##
## It lives outside [method _apply_damage_side_effects] because that runs once per
## hit: leaving recoil there would charge a Parental Bond pair -- or a five-hit
## Skill Link Pin Missile -- several times over, each time at the wrong size.
func _apply_recoil(side: int, move: Dictionary, total_dealt: int) -> void:
	if total_dealt <= 0:
		return
	var effect := String(move.get("effect", ""))
	if not effect.contains("recoil"):
		return
	var attacker := active(side)
	var fraction := 3.0 if effect.contains("1-3") else 4.0
	var recoil := maxi(1, floori(float(total_dealt) / fraction))
	Stats.apply_hp_delta(attacker, -recoil)
	_say("%s is damaged by recoil!" % Stats.display_name(attacker))

## Secondary effects that only fire on a damaging hit that connected. Runs ONCE
## PER HIT; recoil is deliberately not here (see [method _apply_recoil]).
func _apply_damage_side_effects(side: int, move: Dictionary, dealt: int) -> void:
	var attacker := active(side)
	var defender := active(1 - side)
	var effect := String(move.get("effect", ""))
	var chance := int(move.get("effectChance", 0))

	if effect.contains("drains-half-the-damage"):
		var healed := -Stats.apply_hp_delta(attacker, maxi(1, dealt / 2))
		if healed != 0:
			_say("%s had its energy drained!" % Stats.display_name(defender))

	if Stats.is_fainted(defender):
		return
	if chance <= 0 or rng.randi_range(1, 100) > chance:
		return

	if effect.contains("flinch"):
		Status.set_flinch(defender, true)
		return
	if effect.contains("confuse"):
		for m: String in (Status.confuse(defender, rng)["messages"] as Array):
			_say(m)
		return
	var inflicted := _status_from_effect(effect)
	if inflicted != "":
		for m: String in (Status.apply(defender, inflicted, rng)["messages"] as Array):
			_say(m)
		return
	_apply_stat_change_effect(side, effect, true)


func _apply_status_move(side: int, move: Dictionary) -> void:
	var user := active(side)
	var target := active(1 - side)
	var effect := String(move.get("effect", ""))

	# Protect / Detect. Branching on effectId rather than the effect string, the way
	# multi_hit.gd does, because 57 Gen 9 rows carry `"effect": null`.
	if PROTECT_EFFECT_IDS.has(int(move.get("effectId", -1))):
		_apply_protect(side)
		return

	# Type immunity still applies to status moves: Thunder Wave does nothing to
	# a Ground-type, and that is a type-chart lookup, not a status immunity.
	var inflicted := _status_from_effect(effect)
	if inflicted != "":
		var eff := Damage.type_multiplier(String(move.get("type", "normal")),
			target.get("types", PackedStringArray()))
		if is_zero_approx(eff):
			_say("It doesn't affect %s..." % Stats.display_name(target))
			return
		for m: String in (Status.apply(target, inflicted, rng)["messages"] as Array):
			_say(m)
		return

	if effect.contains("confuses"):
		for m: String in (Status.confuse(target, rng)["messages"] as Array):
			_say(m)
		return
	if effect.contains("heals-the-user-by-half"):
		var healed := Stats.apply_hp_delta(user, int(user.get("maxHp", 1)) / 2)
		_say("%s regained health!" % Stats.display_name(user) if healed > 0
			else "But it failed!")
		return
	if not _apply_stat_change_effect(side, effect, false):
		_say("But nothing happened!")


## Protect / Detect: raise the volatile the protection gate in [method _use_move]
## reads, and make consecutive use progressively unreliable.
##
## SUCCESS ODDS, Gen 6+: the first use always works, and each CONSECUTIVE use
## succeeds with probability 1/3 of the one before -- 1, 1/3, 1/9, 1/27. Without
## that, +4 priority protection is an unbreakable stall and every AI trainer
## holding Protect becomes unloseable-by-attrition. A failure resets the chain, and
## so does using any other move (see [method _use_move]).
##
## The streak lives in `volatile["protect_streak"]`, so `Status.clear_volatiles()`
## on a switch resets it -- which is correct: the chain is broken by switching out.
## `_end_of_turn` clears `protect` but deliberately leaves `protect_streak` alone,
## because the chain has to outlive the turn to mean anything.
func _apply_protect(side: int) -> void:
	var user := active(side)
	var vol: Dictionary = user.get("volatile", {})
	var streak := int(vol.get("protect_streak", 0))

	if streak > 0:
		var odds := 1.0 / pow(3.0, float(streak))
		if rng.randf() >= odds:
			vol["protect"] = false
			vol["protect_streak"] = 0
			user["volatile"] = vol
			_say("But it failed!")
			return

	vol["protect"] = true
	vol["protect_streak"] = streak + 1
	user["volatile"] = vol
	_say("%s protected itself!" % Stats.display_name(user))


## Parse "raises-the-user-s-attack-by-two-stages" /
## "lowers-the-target-s-speed-by-one-stage" and apply it. Returns false when the
## effect string is not a stat change at all.
func _apply_stat_change_effect(side: int, effect: String, secondary: bool) -> bool:
	var raises := effect.contains("raise")
	var lowers := effect.contains("lower")
	if raises == lowers:
		return false        # neither, or a string claiming both

	var stat := _stat_from_effect(effect)
	if stat == "":
		return false

	var amount := 2 if effect.contains("two-stages") else 1
	# "raises-the-user-s-attack" / "lowers-the-user-s-special-attack-..." target
	# the user; everything else targets the opponent.
	var to_user := effect.contains("the-user")
	var target_mon := active(side) if to_user else active(1 - side)
	var delta := amount if raises else -amount

	var applied := Stats.change_stage(target_mon, stat, delta)
	var name := Stats.display_name(target_mon)
	if applied == 0:
		_say("%s's %s won't go %s!" % [name, stat, "higher" if delta > 0 else "lower"])
	else:
		_say("%s's %s %s!" % [name, stat,
			("rose" if absi(applied) == 1 else "rose sharply") if delta > 0
			else ("fell" if absi(applied) == 1 else "harshly fell")])
	return true


## Apply an ability hook's `{stat_boosts, messages}` result. Shared by onFlinch and
## onAfterHit. The message is suppressed when every stage was already capped, so a
## Pokemon sitting at +6 Speed does not announce a boost it did not get.
func _apply_ability_boosts(mon: Dictionary, res: Dictionary) -> void:
	if res.is_empty():
		return
	var boosts: Dictionary = res.get("stat_boosts", {})
	var applied := 0
	for key: String in boosts.keys():
		applied += absi(Stats.change_stage(mon, key, int(boosts[key])))
	if not boosts.is_empty() and applied == 0:
		return
	for m: String in (res.get("messages", []) as Array):
		_say(m)


## Re-evaluate persistent field state (Delta Stream's strong winds) after ANY
## field change. Called after the opening lead-in, after a Mega Evolution -- which
## is how Rayquaza ACQUIRES Delta Stream, since mega.gd rewrites mon["ability"] --
## after every switch-in, after every faint, and once more when the battle ends and
## `Mega.revert_party()` has taken the ability away again.
##
## No-op when nothing on the field owns a field state and the slot does not hold
## one, so ordinary weather (rain, sandstorm) is never touched.
func _refresh_field() -> void:
	if sides.is_empty():
		return
	var mons: Array = []
	for side in sides.size():
		mons.append(active(side))
	var r := Abilities.field_refresh(mons, weather, weather_turns)
	var next := String(r.get("weather", weather))
	if next == weather:
		return
	weather = next
	weather_turns = int(r.get("weather_turns", 0))
	for m: String in (r.get("messages", []) as Array):
		_say(m)


func _stat_from_effect(effect: String) -> String:
	if effect.contains("special-attack"): return "spa"
	if effect.contains("special-defense"): return "spd"
	if effect.contains("attack"): return "atk"
	if effect.contains("defense"): return "def"
	if effect.contains("speed"): return "spe"
	if effect.contains("accuracy"): return "acc"
	if effect.contains("evasion"): return "eva"
	return ""


func _status_from_effect(effect: String) -> String:
	if effect.contains("paralyz"): return Status.PARALYSIS
	if effect.contains("burn"): return Status.BURN
	if effect.contains("badly-poison"): return Status.TOXIC
	if effect.contains("poison"): return Status.POISON
	if effect.contains("sleep"): return Status.SLEEP
	if effect.contains("freeze") or effect.contains("frozen"): return Status.FREEZE
	return ""


# --------------------------------------------------------------------------
# Switching, items, running
# --------------------------------------------------------------------------

func _switch_in(side: int, index: int, voluntary: bool) -> bool:
	var s: Dictionary = sides[side]
	var party: Array = s["party"]
	if index < 0 or index >= party.size() or Stats.is_fainted(party[index]):
		return false
	var outgoing := active(side)
	if voluntary and not Stats.is_fainted(outgoing):
		Status.clear_volatiles(outgoing)
		_say("%s, come back!" % Stats.display_name(outgoing))
	s["active"] = index
	Status.clear_volatiles(party[index])
	_say("Go! %s!" % Stats.display_name(party[index]) if side == PLAYER
		else "%s sent out %s!" % [String(s["name"]), Stats.display_name(party[index])])
	if side == PLAYER:
		_reset_participants()
	_refresh_field()
	return true


## Public switch, used by the UI once the player has chosen a replacement.
func switch_in(side: int, index: int) -> bool:
	var ok := _switch_in(side, index, awaiting_switch != side)
	if ok and awaiting_switch == side:
		awaiting_switch = -1
	return ok


func _use_item(side: int, item: String, target_index: int) -> void:
	var s: Dictionary = sides[side]
	var party: Array = s["party"]
	var idx := target_index if target_index >= 0 else int(s["active"])
	if idx < 0 or idx >= party.size():
		return
	var mon: Dictionary = party[idx]
	var name := Stats.display_name(mon)
	_say("%s used the %s." % [String(s["name"]), item])

	var did := false
	if HEAL_ITEMS.has(item) and not Stats.is_fainted(mon):
		var amount := int(HEAL_ITEMS[item])
		if amount < 0:
			amount = int(mon.get("maxHp", 1))
		var healed := Stats.apply_hp_delta(mon, amount)
		if healed > 0:
			_say("%s recovered %d HP!" % [name, healed])
			did = true
	if CURE_ITEMS.has(item) and Status.has_status(mon):
		if (CURE_ITEMS[item] as Array).has(Status.status_of(mon)):
			Status.cure(mon)
			_say("%s's status returned to normal." % name)
			did = true
	if item == "revive" and Stats.is_fainted(mon):
		Stats.apply_hp_delta(mon, int(mon.get("maxHp", 1)) / 2)
		_say("%s was revived!" % name)
		did = true
	if not did:
		_say("But it had no effect!")


## Classic escape odds: floor(A*128/B) + 30*attempts, rolled against 256.
func _try_run(side: int) -> void:
	if kind != "wild":
		_say("No! There's no running from a Trainer battle!")
		return
	# Shadow Tag and Arena Trap stop a wild escape outright, before the odds are
	# even rolled. A Shed Shell does NOT help here: the item buys a switch, not an
	# escape, which is why the hook is told the reason.
	var trap := Abilities.escape_block(active(1 - side), active(side), "run")
	if bool(trap.get("block", false)):
		var trap_msg := String(trap.get("message", ""))
		_say(trap_msg if trap_msg != "" else "Can't escape!")
		return
	_run_attempts += 1
	var a := TurnOrder.effective_speed(active(side))
	var b := TurnOrder.effective_speed(active(1 - side))
	var odds := 256
	if b > 0:
		odds = floori(float(a) * 128.0 / float(b)) + 30 * _run_attempts
	if a >= b or odds >= 256 or rng.randi_range(0, 255) < odds:
		_say("Got away safely!")
		_finish("run")
	else:
		_say("Can't escape!")


# --------------------------------------------------------------------------
# Faints, EXP, end of battle
# --------------------------------------------------------------------------

func _check_faints() -> void:
	for side in sides.size():
		var mon := active(side)
		if mon.is_empty() or not Stats.is_fainted(mon):
			continue
		if _announced_faints.has(mon):
			continue
		_announced_faints.append(mon)
		_say("%s fainted!" % Stats.display_name(mon))
		# DATA_CONTRACT 11.2: a Mega reverts the moment it faints. After the
		# message (so the log names the Mega that died) and before the EXP award.
		Mega.revert(mon)
		if side == OPPONENT:
			_award_exp_for(mon)

	if not has_usable(OPPONENT):
		_finish("win")
		return
	if not has_usable(PLAYER):
		_finish("loss")
		return

	for side in sides.size():
		if Stats.is_fainted(active(side)):
			if side == OPPONENT or auto_player:
				_auto_replace(side)
			else:
				awaiting_switch = side

	# A fainted holder stops holding the field even before its replacement is
	# chosen: Abilities.for_mon() returns null at 0 HP.
	_refresh_field()


func _auto_replace(side: int) -> void:
	var s: Dictionary = sides[side]
	var party: Array = s["party"]
	var bench := bench_of(side)
	if bench.is_empty():
		return
	var pick: Dictionary = bench[0]
	if side == OPPONENT or auto_player:
		var i := AI.choose_replacement(active(1 - side), bench, weather)
		if i >= 0:
			pick = bench[i]
	for i in party.size():
		if party[i] == pick:
			_switch_in(side, i, false)
			break
	if awaiting_switch == side:
		awaiting_switch = -1


## EXP for everything on the player's side that took part. THE CAP LIVES IN
## exp.gd -- this only decides who gets paid.
func _award_exp_for(defeated: Dictionary) -> void:
	if not award_exp:
		# Not "capped to zero": Exp.award() would print "<NAME> is at the level
		# cap!" for every participant, which is a lie in a fight that has no
		# progression in it at all.
		_reset_participants()
		return
	var party: Array = party_of(PLAYER)
	var participants: Array = []
	for idx: int in _participants.keys():
		if idx >= 0 and idx < party.size() and not Stats.is_fainted(party[idx]):
			participants.append(idx)
	if participants.is_empty():
		var a := int((sides[PLAYER] as Dictionary)["active"])
		if not Stats.is_fainted(party[a]):
			participants.append(a)

	for idx: int in participants:
		var mon: Dictionary = party[idx]
		var amount := Exp.gain_from_defeat(defeated, int(mon.get("level", 1)), {
			"participants": participants.size(),
			"is_trainer": kind == "trainer",
			"lucky_egg": String(mon.get("item", "")) == "lucky-egg",
		})
		var res := Exp.award(mon, amount, {"cap": current_cap()})
		exp_awarded += int(res["granted"])
		for m: String in (res["messages"] as Array):
			_say(m)

	_reset_participants()


func _reset_participants() -> void:
	_participants.clear()
	if sides.size() > PLAYER:
		_participants[int((sides[PLAYER] as Dictionary)["active"])] = true


func _end_of_turn() -> void:
	# Protection lasts exactly the turn it was raised.
	for side in sides.size():
		var vol: Dictionary = (active(side) as Dictionary).get("volatile", {})
		if bool(vol.get("protect", false)):
			vol["protect"] = false

	if weather_turns > 0:
		weather_turns -= 1
		if weather_turns == 0:
			_say("The weather cleared up.")
			weather = ""

	# Residual damage resolves in Speed order, like the games.
	var rows: Array = []
	for side in sides.size():
		rows.append({"side": side, "mon": active(side), "kind": "move"})
	for row: Dictionary in TurnOrder.order(rows, rng):
		var mon: Dictionary = row["mon"]
		if Stats.is_fainted(mon):
			continue
		var tick := Status.end_of_turn(mon)
		for m: String in (tick["messages"] as Array):
			_say(m)
	_check_faints()


func _finish(final_outcome: String) -> void:
	if over:
		return
	over = true
	outcome = final_outcome
	match final_outcome:
		"win":
			if kind == "trainer":
				var trainer: Dictionary = (sides[OPPONENT] as Dictionary)["trainer"]
				money_awarded = int(trainer.get("prizeMoney", 0))
				_say("%s defeated %s!" % [String((sides[PLAYER] as Dictionary)["name"]),
					String(trainer.get("name", "the opponent"))])
				if money_awarded > 0:
					_say("Got $%d for winning!" % money_awarded)
					var state := Deps.state()
					if state != null and state.has_method("add_money"):
						state.add_money(money_awarded)
		"loss":
			_say("%s is out of usable Pokemon!" % String((sides[PLAYER] as Dictionary)["name"]))
			_say("%s whited out!" % String((sides[PLAYER] as Dictionary)["name"]))
		"run":
			pass

	# DATA_CONTRACT 11.2 and megas.json `revertsAfterBattle`: nothing leaves a
	# battle still Mega Evolved, on either side. Before result(), so the payload
	# the overworld and the save system receive is already base-form.
	for side in sides.size():
		Mega.revert_party(party_of(side))
	# The ability has just been reverted away, so the field state it owned ends
	# with the battle rather than leaking into the next one.
	_refresh_field()

	var r := result()
	battle_over.emit(r)
	Deps.emit("battle_ended", [r])


func _say(text: String) -> void:
	battle_log.append(text)
	message.emit(text)
