extends RefCounted
## EXP gain, the six growth curves, levelling up -- and THE LEVEL CAP HOOK.
##
## THE HEADLINE FEATURE (docs/research/game-design.md 2, DATA_CONTRACT 8
## `"rule": "hard-xp-stop"`):
##
##   A Pokemon whose level is **at or above the current cap gains exactly zero
##   EXP**. Not reduced, not deferred -- zero. When that happens
##   `EventBus.exp_capped(pokemon, cap)` fires and the caller is handed the
##   message `"<NAME> is at the level cap!"` to put on screen.
##
## The cap itself comes from `GameState.current_level_cap()`. [method award]
## accepts an explicit `cap` in `opts` so the rule can be tested without the
## autoload, but production code passes nothing and gets the live cap.
##
## A Pokemon *below* the cap gains EXP normally and may level up -- but its level
## is clamped to the cap, so a single huge EXP award can never vault past it. Its
## EXP total is then parked exactly on the cap level's threshold, which means the
## instant the cap is raised it is ready to grow again with nothing banked.
##
## THE PER-SEGMENT EXP MULTIPLIER (DATA_CONTRACT 8). [method award] scales the
## incoming amount by `GameState.current_exp_multiplier()` -- the multiplier of
## the cap segment currently in force -- and does so **before** the cap check, so
## the cap always wins: a Pokemon at the cap gains exactly 0 no matter how large
## the multiplier is. The multiplier is per-segment and there is no global one;
## `data/level_caps.json`'s top-level `expMultiplier` is permanently null.

const Deps := preload("res://src/battle/deps.gd")
const Stats := preload("res://src/battle/stats.gd")

const MAX_LEVEL := 100
const CAP_MESSAGE := "%s is at the level cap!"

const GROWTH_RATES: Array = [
	"erratic", "fast", "medium-fast", "medium-slow", "slow", "fluctuating",
]


# --------------------------------------------------------------------------
# Growth curves  (total EXP required to *be* level n)
# --------------------------------------------------------------------------

static func exp_for_level(growth_rate: String, level: int) -> int:
	var n := clampi(level, 1, MAX_LEVEL)
	if n == 1:
		return 0
	var f := float(n)
	var cube := f * f * f
	match growth_rate:
		"fast":
			return floori(4.0 * cube / 5.0)
		"medium-fast":
			return floori(cube)
		"medium-slow":
			return maxi(0, floori(1.2 * cube - 15.0 * f * f + 100.0 * f - 140.0))
		"slow":
			return floori(5.0 * cube / 4.0)
		"erratic":
			if n < 50:
				return floori(cube * (100.0 - f) / 50.0)
			if n < 68:
				return floori(cube * (150.0 - f) / 100.0)
			if n < 98:
				return floori(cube * float(floori((1911.0 - 10.0 * f) / 3.0)) / 500.0)
			return floori(cube * (160.0 - f) / 100.0)
		"fluctuating":
			if n < 15:
				return floori(cube * ((float(floori((f + 1.0) / 3.0)) + 24.0) / 50.0))
			if n < 36:
				return floori(cube * ((f + 14.0) / 50.0))
			return floori(cube * ((float(floori(f / 2.0)) + 32.0) / 50.0))
	return floori(cube)      # unknown rate -> medium-fast


## Highest level whose threshold `exp_total` has reached.
static func level_for_exp(growth_rate: String, exp_total: int) -> int:
	var lvl := 1
	for n in range(2, MAX_LEVEL + 1):
		if exp_total >= exp_for_level(growth_rate, n):
			lvl = n
		else:
			break
	return lvl


# --------------------------------------------------------------------------
# EXP yield
# --------------------------------------------------------------------------

## Modern (Gen 5+) EXP formula:
## [codeblock]
## exp = floor( (b * L / 5) * (1/s) * ((2L + 10) / (L + Lp + 10))^2.5 + 1 )
## [/codeblock]
## `b` the fainted Pokemon's base EXP yield, `L` its level, `Lp` the winner's
## level, `s` the number of participants. `opts`: participants (int, default 1),
## is_trainer (bool, x1.5), lucky_egg (bool, x1.5), traded (bool, x1.5).
static func gain_from_defeat(defeated: Dictionary, winner_level: int, opts: Dictionary = {}) -> int:
	var b := float(defeated.get("baseExp", 64))
	var l := float(int(defeated.get("level", 1)))
	var lp := float(maxi(winner_level, 1))
	var s := float(maxi(int(opts.get("participants", 1)), 1))

	var core := (b * l / 5.0) * (1.0 / s) * pow((2.0 * l + 10.0) / (l + lp + 10.0), 2.5) + 1.0
	var total := floori(core)

	if bool(opts.get("is_trainer", false)):
		total = floori(float(total) * 1.5)
	if bool(opts.get("lucky_egg", false)):
		total = floori(float(total) * 1.5)
	if bool(opts.get("traded", false)):
		total = floori(float(total) * 1.5)
	return maxi(total, 1)


# --------------------------------------------------------------------------
# Awarding  --  THE LEVEL CAP HOOK
# --------------------------------------------------------------------------

## Give `amount` EXP to `mon`, honouring the per-segment multiplier and the hard
## level cap.
##
## `opts`: cap (int, -1 = ask GameState), exp_multiplier (float, < 0 = ask
## GameState), learn_moves (bool, default true).
##
## Returns:
## [codeblock]
## {granted:int, capped:bool, cap:int, levels:int, levelBefore:int, levelAfter:int,
##  learned:PackedStringArray, messages:Array[String],
##  expMultiplier:float, rawAmount:int}
## [/codeblock]
## `rawAmount` is `amount` as handed in; `granted` is that amount scaled by
## `expMultiplier` (floored, and never rounded down to 0 when the raw amount was
## positive). `granted` is **0** and `capped` is **true** for a Pokemon at or
## above the cap -- the multiplier is applied first and the cap still wins -- and
## `messages[0]` is then exactly `"<NAME> is at the level cap!"`.
static func award(mon: Dictionary, amount: int, opts: Dictionary = {}) -> Dictionary:
	var cap := int(opts.get("cap", -1))
	if cap < 0:
		cap = Deps.level_cap()

	# ---- PER-SEGMENT MULTIPLIER (DATA_CONTRACT 8) ------------------------
	# Resolved and applied BEFORE the cap check below, per the contract. A test
	# or a debug menu can pin it through opts; production passes nothing and gets
	# the active segment's value.
	var mult := float(opts.get("exp_multiplier", -1.0))
	if mult < 0.0:
		mult = Deps.exp_multiplier()
	var raw := maxi(amount, 0)
	var scaled := raw
	if raw > 0 and not is_equal_approx(mult, 1.0):
		# floori, not roundi: the curve was derived against a floor. maxi(..., 1)
		# so a sub-1.0 multiplier can never silently turn a real award into zero
		# and be mistaken for the cap firing.
		scaled = maxi(floori(float(raw) * mult), 1)
	# ----------------------------------------------------------------------

	var level_before := int(mon.get("level", 1))
	var name := Stats.display_name(mon)
	var out: Dictionary = {
		"granted": 0, "capped": false, "cap": cap, "levels": 0,
		"levelBefore": level_before, "levelAfter": level_before,
		"learned": PackedStringArray(), "messages": [],
		"expMultiplier": mult, "rawAmount": raw,
	}

	# ---- THE HOOK --------------------------------------------------------
	if level_before >= cap:
		out["capped"] = true
		Deps.emit("exp_capped", [mon, cap])
		(out["messages"] as Array).append(CAP_MESSAGE % name)
		return out
	# ----------------------------------------------------------------------

	var granted := scaled
	if granted == 0:
		return out

	var growth := String(mon.get("growthRate", "medium-fast"))
	mon["exp"] = int(mon.get("exp", 0)) + granted
	out["granted"] = granted
	(out["messages"] as Array).append("%s gained %d EXP. Points!" % [name, granted])

	var new_level := mini(level_for_exp(growth, int(mon["exp"])), cap)
	new_level = mini(new_level, MAX_LEVEL)
	if new_level > level_before:
		# Park the EXP bar exactly on the cap's threshold when the cap is what
		# stopped us, so nothing is banked for the moment the cap is raised.
		if new_level == cap and int(mon["exp"]) > exp_for_level(growth, cap):
			mon["exp"] = exp_for_level(growth, cap)
		set_level(mon, new_level)
		out["levels"] = new_level - level_before
		out["levelAfter"] = new_level
		(out["messages"] as Array).append("%s grew to Lv. %d!" % [name, new_level])
		if bool(opts.get("learn_moves", true)):
			out["learned"] = _moves_learned(mon, level_before + 1, new_level)
			for slug in (out["learned"] as PackedStringArray):
				(out["messages"] as Array).append("%s learned %s!" % [name, slug])
	return out


## Convenience wrapper: work out the yield from a defeat and award it. `opts` goes
## to both halves, so the per-segment multiplier applies exactly once -- in
## [method award], to the unscaled yield [method gain_from_defeat] returned.
static func award_for_defeat(winner: Dictionary, defeated: Dictionary,
		opts: Dictionary = {}) -> Dictionary:
	var amount := gain_from_defeat(defeated, int(winner.get("level", 1)), opts)
	return award(winner, amount, opts)


## Recompute stats for a new level, keeping the current HP *fraction* -- the same
## rule DATA_CONTRACT 11.2 mandates for Mega Evolution.
static func set_level(mon: Dictionary, new_level: int) -> void:
	var old_max: int = maxi(int(mon.get("maxHp", 1)), 1)
	var fraction := float(int(mon.get("hp", 0))) / float(old_max)
	mon["level"] = new_level

	var reg := Deps.registry()
	var sp: Dictionary = {}
	if reg != null:
		sp = reg.get_species(int(mon.get("species", 0)))
	var base: Dictionary = sp.get("stats", {})
	if base.is_empty():
		# No species record reachable: scale nothing but the level. Better a
		# stale stat block than a mon with 1 HP in every stat.
		return
	mon["stats"] = Stats.calc_all(base, mon.get("ivs", []), mon.get("evs", []),
		new_level, String(mon.get("nature", "hardy")))
	mon["maxHp"] = int((mon["stats"] as Dictionary)["hp"])
	mon["hp"] = clampi(roundi(fraction * float(mon["maxHp"])), 1, int(mon["maxHp"]))


static func _moves_learned(mon: Dictionary, from_level: int, to_level: int) -> PackedStringArray:
	var out := PackedStringArray()
	var reg := Deps.registry()
	if reg == null or not reg.has_method("moves_learned_at"):
		return out
	for lvl in range(from_level, to_level + 1):
		for slug in reg.moves_learned_at(int(mon.get("species", 0)), lvl):
			out.append(String(slug))
	return out
