extends RefCounted
## Non-volatile status (burn / poison / badly-poisoned / paralysis / sleep /
## freeze) and the volatile ones the turn loop needs (confusion, flinch).
##
## RULES CHOSEN, AND WHY
##
## The project targets "modern Gen 5+" mechanics (docs/DATA_CONTRACT.md, the
## damage brief), so where Gen 5 and Gen 6+ disagree this file takes the modern
## behaviour and says so:
##   * Paralysis multiplies Speed by 0.50. (Gen 1-6 used 0.25; Gen 7 changed it.)
##   * Electric-types cannot be paralysed. (Gen 6+.)
##   * Sleep lasts 1-3 turns, counted down before the move. (Gen 5+.)
##   * Freeze thaws with a 20% chance per turn, and any Fire-type move used on a
##     frozen target thaws it.
##   * Burn halves *physical* damage (applied in damage.gd, which is where the
##     multiplier belongs in the damage chain) and ticks 1/16 max HP.
##   * Poison ticks 1/8; Toxic ticks n/16 with n climbing each turn.
##   * Confusion lasts 2-5 turns and has a 33% chance of a 40-power typeless
##     physical self-hit that cannot crit.
##
## Every `apply_*` returns a Dictionary with at least `ok` and `messages` so the
## battle log is built from the same place the rules are.

const Stats := preload("res://src/battle/stats.gd")

const NONE := ""
const BURN := "burn"
const POISON := "poison"
const TOXIC := "toxic"
const PARALYSIS := "paralysis"
const SLEEP := "sleep"
const FREEZE := "freeze"

const ALL: Array = [BURN, POISON, TOXIC, PARALYSIS, SLEEP, FREEZE]

## Type immunities to each non-volatile status.
const IMMUNE_TYPES: Dictionary = {
	BURN: ["fire"],
	POISON: ["poison", "steel"],
	TOXIC: ["poison", "steel"],
	PARALYSIS: ["electric"],
	FREEZE: ["ice"],
	SLEEP: [],
}

const PARALYSIS_SPEED_MULT := 0.5
const FREEZE_THAW_CHANCE := 0.20
const FULL_PARALYSIS_CHANCE := 0.25
const CONFUSION_SELF_HIT_CHANCE := 0.33
const CONFUSION_SELF_HIT_POWER := 40


# --------------------------------------------------------------------------
# Queries
# --------------------------------------------------------------------------

static func has_status(mon: Dictionary) -> bool:
	return String(mon.get("status", NONE)) != NONE


static func status_of(mon: Dictionary) -> String:
	return String(mon.get("status", NONE))


static func is_immune(mon: Dictionary, status: String) -> bool:
	var immune: Array = IMMUNE_TYPES.get(status, [])
	for t: String in mon.get("types", PackedStringArray()):
		if immune.has(t):
			return true
	return false


## Speed multiplier from status alone. Stat stages are handled by stats.gd.
static func speed_mult(mon: Dictionary) -> float:
	return PARALYSIS_SPEED_MULT if status_of(mon) == PARALYSIS else 1.0


## Attack multiplier from status alone: burn halves physical output.
static func attack_mult(mon: Dictionary, category: String) -> float:
	if status_of(mon) == BURN and category == "physical" \
			and String(mon.get("ability", "")) != "guts":
		return 0.5
	return 1.0


# --------------------------------------------------------------------------
# Applying
# --------------------------------------------------------------------------

## Inflict a non-volatile status. Fails (ok=false) when the target already has
## one, is immune by type, or has fainted -- exactly the game's ordering.
static func apply(mon: Dictionary, status: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var name := Stats.display_name(mon)
	if Stats.is_fainted(mon):
		return {"ok": false, "reason": "fainted", "messages": []}
	if has_status(mon):
		return {"ok": false, "reason": "already", "messages": ["%s is already %s!" % [name, status_of(mon)]]}
	if not ALL.has(status):
		return {"ok": false, "reason": "unknown", "messages": []}
	if is_immune(mon, status):
		return {"ok": false, "reason": "immune", "messages": ["It doesn't affect %s..." % name]}

	mon["status"] = status
	match status:
		SLEEP:
			# 1-3 turns. rng optional so tests can pin it.
			mon["statusCounter"] = rng.randi_range(1, 3) if rng != null else 2
		TOXIC:
			mon["statusCounter"] = 1
		_:
			mon["statusCounter"] = 0
	return {"ok": true, "reason": "", "messages": [_inflict_message(name, status)]}


static func cure(mon: Dictionary) -> void:
	mon["status"] = NONE
	mon["statusCounter"] = 0


## Confusion: 2-5 turns, stored as a volatile counter.
static func confuse(mon: Dictionary, rng: RandomNumberGenerator = null) -> Dictionary:
	var vol: Dictionary = mon.get("volatile", {})
	if int(vol.get("confusion", 0)) > 0:
		return {"ok": false, "messages": ["%s is already confused!" % Stats.display_name(mon)]}
	vol["confusion"] = rng.randi_range(2, 5) if rng != null else 3
	mon["volatile"] = vol
	return {"ok": true, "messages": ["%s became confused!" % Stats.display_name(mon)]}


static func set_flinch(mon: Dictionary, value: bool = true) -> void:
	var vol: Dictionary = mon.get("volatile", {})
	vol["flinch"] = value
	mon["volatile"] = vol


## Volatiles do not survive a switch-out; non-volatile status does.
static func clear_volatiles(mon: Dictionary) -> void:
	mon["volatile"] = {"confusion": 0, "flinch": false}
	Stats.reset_stages(mon)


# --------------------------------------------------------------------------
# Turn hooks
# --------------------------------------------------------------------------

## Called immediately before a Pokemon's move resolves.
##
## Returns `{can_move: bool, messages: Array[String], self_damage: int}`.
## Order matches the games: freeze/sleep (which can end here), then flinch, then
## paralysis, then confusion.
static func before_move(mon: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var name := Stats.display_name(mon)
	var msgs: Array = []
	var vol: Dictionary = mon.get("volatile", {})

	match status_of(mon):
		FREEZE:
			if rng.randf() < FREEZE_THAW_CHANCE:
				cure(mon)
				msgs.append("%s thawed out!" % name)
			else:
				msgs.append("%s is frozen solid!" % name)
				return {"can_move": false, "messages": msgs, "self_damage": 0}
		SLEEP:
			var left := int(mon.get("statusCounter", 0)) - 1
			mon["statusCounter"] = maxi(left, 0)
			if left <= 0:
				cure(mon)
				msgs.append("%s woke up!" % name)
			else:
				msgs.append("%s is fast asleep." % name)
				return {"can_move": false, "messages": msgs, "self_damage": 0}

	if bool(vol.get("flinch", false)):
		vol["flinch"] = false
		mon["volatile"] = vol
		msgs.append("%s flinched and couldn't move!" % name)
		# `flinched` is reported ONLY on this branch -- the one that actually prints
		# the message -- because Bulbapedia ties Steadfast to the message, not to the
		# volatile flag, and the flag is cleared in the same breath. Additive: every
		# existing caller reads `can_move` and is unaffected. This file stays below
		# the ability layer and does not know abilities exist; the engine calls the
		# hook. Once flinch PREVENTION lands (Inner Focus, Substitute) it will take
		# its own branch and Steadfast will correctly not fire.
		return {"can_move": false, "messages": msgs, "self_damage": 0, "flinched": true}

	if status_of(mon) == PARALYSIS and rng.randf() < FULL_PARALYSIS_CHANCE:
		msgs.append("%s is paralyzed! It can't move!" % name)
		return {"can_move": false, "messages": msgs, "self_damage": 0}

	var confusion := int(vol.get("confusion", 0))
	if confusion > 0:
		confusion -= 1
		vol["confusion"] = confusion
		mon["volatile"] = vol
		if confusion == 0:
			msgs.append("%s snapped out of its confusion!" % name)
		else:
			msgs.append("%s is confused!" % name)
			if rng.randf() < CONFUSION_SELF_HIT_CHANCE:
				var dmg := confusion_self_damage(mon)
				Stats.apply_hp_delta(mon, -dmg)
				msgs.append("It hurt itself in its confusion!")
				return {"can_move": false, "messages": msgs, "self_damage": dmg}

	return {"can_move": true, "messages": msgs, "self_damage": 0}


## A 40-power typeless physical hit using the mon's own Attack and Defence, at
## the average damage roll (the games roll it; using the average keeps the
## self-hit reproducible without threading the RNG through the damage module).
static func confusion_self_damage(mon: Dictionary) -> int:
	var level: int = int(mon.get("level", 1))
	var atk := Stats.effective_stat(mon, "atk")
	var def := Stats.effective_stat(mon, "def")
	var base := floori(floori(float(floori(2.0 * level / 5.0) + 2) * CONFUSION_SELF_HIT_POWER
		* float(atk) / float(def)) / 50.0) + 2
	return maxi(1, floori(float(base) * 0.925))


## End-of-turn residual damage. Returns `{damage: int, messages: Array[String]}`.
static func end_of_turn(mon: Dictionary) -> Dictionary:
	if Stats.is_fainted(mon):
		return {"damage": 0, "messages": []}
	var name := Stats.display_name(mon)
	var max_hp: int = int(mon.get("maxHp", 1))
	var dmg := 0
	var msgs: Array = []

	match status_of(mon):
		BURN:
			dmg = maxi(1, max_hp / 16)
			msgs.append("%s was hurt by its burn!" % name)
		POISON:
			dmg = maxi(1, max_hp / 8)
			msgs.append("%s was hurt by poison!" % name)
		TOXIC:
			var n: int = maxi(1, int(mon.get("statusCounter", 1)))
			dmg = maxi(1, (max_hp * n) / 16)
			mon["statusCounter"] = mini(n + 1, 15)
			msgs.append("%s was hurt by poison!" % name)

	if dmg > 0:
		Stats.apply_hp_delta(mon, -dmg)
		# The faint message itself belongs to the engine, which announces every
		# faint in one place -- otherwise it gets printed twice.
	return {"damage": dmg, "messages": msgs}


static func _inflict_message(name: String, status: String) -> String:
	match status:
		BURN: return "%s was burned!" % name
		POISON: return "%s was poisoned!" % name
		TOXIC: return "%s was badly poisoned!" % name
		PARALYSIS: return "%s is paralyzed! It may be unable to move!" % name
		SLEEP: return "%s fell asleep!" % name
		FREEZE: return "%s was frozen solid!" % name
	return "%s was afflicted." % name
