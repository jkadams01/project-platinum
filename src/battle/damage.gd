extends RefCounted
## The damage formula, modern (Gen 5+) shape.
##
## [codeblock]
## base   = floor( floor( floor(2*L/5 + 2) * Power * A / D ) / 50 ) + 2
## damage = base
##          * weather      (1.5 / 0.5, rain & sun)
##          * critical     (1.5)
##          * random       (85..100 / 100, a whole percent, uniform)
##          * STAB         (1.5, or 2.0 with Adaptability)
##          * type         (0, 0.25, 0.5, 1, 2, 4)
##          * burn         (0.5 on a physical move, unless Guts)
## [/codeblock]
##
## Every multiplier truncates immediately after it is applied, which is what the
## games do and is why `damage(85 roll) * 1.5 != damage with STAB` in general.
## The final result is floored at 1 -- except against an immune target, which
## takes exactly 0 and is reported with `immune: true`.
##
## DELIBERATE VERSION CHOICES (the brief says "modern Gen 5+"):
##   * Critical hits multiply by **1.5**, not the Gen 5 2.0 (changed in Gen 6).
##   * Critical stages are 1/24, 1/8, 1/2, 1/1 (Gen 7+).
##   * A critical hit ignores the attacker's *negative* stat stages and the
##     defender's *positive* ones.
##   * The random spread is the 16 values 85..100 inclusive, uniformly.
##
## [method compute] is pure: pass `roll` and `crit` explicitly and it is fully
## deterministic, which is how the tests pin exact numbers. Pass an `rng` and it
## rolls for you.

const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Deps := preload("res://src/battle/deps.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")

const MIN_ROLL := 85
const MAX_ROLL := 100
const CRIT_MULT := 1.5
const STAB_MULT := 1.5
const ADAPTABILITY_STAB := 2.0

## Probability of a critical hit at crit stage 0..3+.
const CRIT_CHANCE: Array = [1.0 / 24.0, 1.0 / 8.0, 1.0 / 2.0, 1.0]


## Compute one hit.
##
## `ctx` keys, all optional:
##   rng       RandomNumberGenerator -- used for the roll and the crit check
##   roll      int 85..100           -- pins the random factor (wins over rng)
##   crit      bool                  -- pins the crit (wins over rng)
##   crit_stage int                  -- 0..3, used when rolling the crit
##   weather   String                -- "", "rain", "sun", "sandstorm", "hail", "snow".
##                                    The ATTACKER'S VIEW (Mega Sol sees "sun").
##   field_weather String             -- the REAL field state, for field-scoped
##                                    effects (Delta Stream). Defaults to `weather`.
##   type_mult float                 -- override the type chart entirely (tests)
##
## Returns:
## [codeblock]
## {damage:int, effectiveness:float, immune:bool, crit:bool, stab:float,
##  roll:int, category:String, base:int}
## [/codeblock]
static func compute(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> Dictionary:
	var category := String(move.get("category", "status"))
	var power := int(move.get("power", 0))
	var move_type := String(move.get("type", "normal"))

	var result: Dictionary = {
		"damage": 0, "effectiveness": 1.0, "immune": false, "crit": false,
		"stab": 1.0, "roll": MAX_ROLL, "category": category, "base": 0,
	}
	if category == "status" or power <= 0:
		return result

	var rng: RandomNumberGenerator = ctx.get("rng", null)

	# --- type effectiveness (0 short-circuits everything) -----------------
	var eff: float
	if ctx.has("type_mult"):
		eff = float(ctx["type_mult"])
	else:
		# `defender` and the FIELD state ride along so the per-component
		# onEffectiveness hook (Delta Stream's strong winds) can be consulted
		# inside the loop.
		#
		# RECONCILIATION, and the one place these two must not be confused:
		# `ctx.weather` is the attacker's weather VIEW (Mega Sol resolves its own
		# moves under sun), while strong winds are a FIELD state that protects
		# every Flying-type on the field regardless of who is attacking. Feeding
		# the view in here let a Mega Meganium delete another mon's Delta Stream
		# and double its own Rock Slide. `field_weather` falls back to `weather`,
		# so the AI's 0x pre-checks and every existing test keep their behaviour.
		eff = type_multiplier(move_type, defender.get("types", PackedStringArray()),
			{"weather": String(ctx.get("field_weather", ctx.get("weather", ""))),
			"defender": defender, "move": move})
	result["effectiveness"] = eff
	if is_zero_approx(eff):
		result["immune"] = true
		return result

	# --- crit -------------------------------------------------------------
	var crit: bool
	if ctx.has("crit"):
		crit = bool(ctx["crit"])
	elif rng != null:
		crit = rng.randf() < crit_chance(int(ctx.get("crit_stage", 0)))
	else:
		crit = false
	result["crit"] = crit

	# --- ability multipliers ----------------------------------------------
	# BOTH sides fold into one Dictionary, every value 1.0 by default, so an
	# attacker-side ability (Fire Mane's atk_mult, Dragonize's power_mult) and a
	# defender-side one (Aura Guard's damage_mult) compose without either knowing
	# the other exists. ctx may also carry the same three keys directly -- that is
	# how the engine passes a Protect-pierce penalty in, and how tests pin one.
	var mods := Abilities.damage_mods(attacker, defender, move, {
		"category": category,
		"move_type": move_type,
		"weather": String(ctx.get("weather", "")),
		"crit": crit,
		"protect_pierced": bool(ctx.get("protect_pierced", false)),
		# Which hit of a multi-hit move this is, and which ability authored the hit
		# plan. Parental Bond quarters ONLY hit 2 of the pair IT created, never hit 2
		# of a naturally multi-hit move.
		"hit_index": int(ctx.get("hit_index", 0)),
		"hits": int(ctx.get("hits", 1)),
		"hit_plan_by": String(ctx.get("hit_plan_by", "")),
	})
	var atk_mult := float(ctx.get("atk_mult", 1.0)) * float(mods["atk_mult"])
	var power_mult := float(ctx.get("power_mult", 1.0)) * float(mods["power_mult"])
	var damage_mult := float(ctx.get("damage_mult", 1.0)) * float(mods["damage_mult"])
	result["atkMult"] = atk_mult
	result["powerMult"] = power_mult
	result["damageMult"] = damage_mult

	# --- attack / defence -------------------------------------------------
	var atk_key := "atk" if category == "physical" else "spa"
	var def_key := "def" if category == "physical" else "spd"
	# A crit ignores the attacker's drops and the defender's boosts.
	var a := Stats.effective_stat(attacker, atk_key, crit, false)
	var d := Stats.effective_stat(defender, def_key, false, crit)
	if not is_equal_approx(atk_mult, 1.0):
		a = maxi(1, floori(float(a) * atk_mult))

	var weather := String(ctx.get("weather", ""))
	if weather == "sandstorm" and category == "special" \
			and PackedStringArray(defender.get("types", PackedStringArray())).has("rock"):
		d = floori(float(d) * 1.5)      # Sandstorm boosts Rock-type Sp. Def by 50%

	# --- base -------------------------------------------------------------
	var level := int(attacker.get("level", 1))
	var level_factor := floori(2.0 * float(level) / 5.0) + 2
	var eff_power := power
	if not is_equal_approx(power_mult, 1.0):
		eff_power = maxi(1, floori(float(power) * power_mult))
	var base := floori(floori(float(level_factor) * float(eff_power) * float(a) / float(d)) / 50.0) + 2
	result["base"] = base

	var dmg := base

	# --- weather ----------------------------------------------------------
	var w := weather_mult(weather, move_type)
	if not is_equal_approx(w, 1.0):
		dmg = floori(float(dmg) * w)

	# --- crit -------------------------------------------------------------
	if crit:
		dmg = floori(float(dmg) * CRIT_MULT)

	# --- random -----------------------------------------------------------
	var roll: int
	if ctx.has("roll"):
		roll = clampi(int(ctx["roll"]), MIN_ROLL, MAX_ROLL)
	elif rng != null:
		roll = rng.randi_range(MIN_ROLL, MAX_ROLL)
	else:
		roll = MAX_ROLL
	result["roll"] = roll
	dmg = floori(float(dmg) * float(roll) / 100.0)

	# --- STAB -------------------------------------------------------------
	var stab := stab_mult(attacker, move_type)
	result["stab"] = stab
	if not is_equal_approx(stab, 1.0):
		dmg = floori(float(dmg) * stab)

	# --- type -------------------------------------------------------------
	dmg = floori(float(dmg) * eff)

	# --- burn -------------------------------------------------------------
	var burn := Status.attack_mult(attacker, category)
	if not is_equal_approx(burn, 1.0):
		dmg = floori(float(dmg) * burn)

	# --- ability / pierce final damage multiplier -------------------------
	# Last step before the floor-at-1, so a 0.5x or 0.25x hit still does >= 1.
	if not is_equal_approx(damage_mult, 1.0):
		dmg = floori(float(dmg) * damage_mult)

	result["damage"] = maxi(1, dmg)
	return result


## Minimum and maximum of the 16-value spread, same ctx otherwise.
static func roll_range(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> Vector2i:
	var lo := ctx.duplicate()
	var hi := ctx.duplicate()
	lo["roll"] = MIN_ROLL
	hi["roll"] = MAX_ROLL
	return Vector2i(int(compute(attacker, defender, move, lo)["damage"]),
		int(compute(attacker, defender, move, hi)["damage"]))


## Average damage over the spread, used by the AI to score a move without
## consuming battle RNG.
static func average(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> int:
	var r := roll_range(attacker, defender, move, ctx)
	return (r.x + r.y) / 2


static func stab_mult(attacker: Dictionary, move_type: String) -> float:
	var types := PackedStringArray(attacker.get("types", PackedStringArray()))
	if not types.has(move_type):
		return 1.0
	return ADAPTABILITY_STAB if String(attacker.get("ability", "")) == "adaptability" else STAB_MULT


## Attacking type vs the defender's 1 or 2 types, from `data/typechart.json`.
##
## RESOLVED PER COMPONENT, not as one finished product: `Abilities.effectiveness()`
## is consulted for each of the defender's types separately. Delta Stream's rule is
## per component -- against Dragon/Flying it takes Ice from 4x to 2x and Electric
## from 1x to 0.5x -- and clamping the product to 1.0 instead would be wrong in
## both directions at once.
##
## `ctx` is optional and carries `weather` and `defender`. The three existing
## two-argument call sites keep compiling and behave identically: with no ability
## overriding the hook, the product of the components is exactly what
## `get_type_multiplier()` returned. Both DataRegistry and Deps.JsonRegistry expose
## `get_type_effectiveness(atk, def)`, so the loop works with the real autoload and
## with the headless fallback.
static func type_multiplier(move_type: String, defender_types: Variant,
		ctx: Dictionary = {}) -> float:
	var types := PackedStringArray(defender_types)
	var reg := Deps.registry()
	if reg == null:
		return 1.0
	var weather := String(ctx.get("weather", ""))
	var defender: Dictionary = ctx.get("defender", {})
	# onTypeImmunity (eelevate, and the levitate cluster behind it) is a FLAT
	# immunity and short-circuits the chart: an ungrounded target takes 0 from a
	# Ground move, not a reduced amount. `move` rides along for the slug-level
	# exception (Thousand Arrows grounds its target).
	if not defender.is_empty():
		var immunity: Dictionary = Abilities.type_immunity(defender, move_type,
			{"move": ctx.get("move", {})})
		if bool(immunity.get("immune", false)):
			return 0.0
	var total := 1.0
	for t: String in types:
		var component := float(reg.get_type_effectiveness(move_type, t))
		total *= Abilities.effectiveness(component, move_type, t, defender, weather)
	return total


static func crit_chance(stage: int) -> float:
	return float(CRIT_CHANCE[clampi(stage, 0, CRIT_CHANCE.size() - 1)])


## Rain: Water x1.5, Fire x0.5. Harsh sun: the reverse.
static func weather_mult(weather: String, move_type: String) -> float:
	match weather:
		"rain":
			if move_type == "water": return 1.5
			if move_type == "fire": return 0.5
		"sun":
			if move_type == "fire": return 1.5
			if move_type == "water": return 0.5
	return 1.0


## "It's super effective!" / "It's not very effective..." / "It doesn't affect X..."
static func effectiveness_message(eff: float, defender_name: String) -> String:
	if is_zero_approx(eff):
		return "It doesn't affect %s..." % defender_name
	if eff > 1.0:
		return "It's super effective!"
	if eff < 1.0:
		return "It's not very effective..."
	return ""
