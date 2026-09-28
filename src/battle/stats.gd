extends RefCounted
## Stat maths: natures, IVs/EVs, the Gen 3+ stat formula, stat stages, accuracy,
## and the canonical in-battle Pokemon Dictionary.
##
## The battle engine never invents its own mon shape. It extends the save shape
## that `GameState._restore_pokemon()` already int-casts
## (`species`, `level`, `exp`, `hp`, `maxHp`, `ability`, `friendship`, `ivs`, `evs`)
## with battle-only fields. [method build] is the single constructor; see its doc
## comment for the full key list.
##
## Rounding matters and is deliberate everywhere: the games truncate, so this file
## uses floori() rather than round().

const Deps := preload("res://src/battle/deps.gd")

## Stat keys, in the order `ivs` / `evs` arrays use.
const KEYS: Array = ["hp", "atk", "def", "spa", "spd", "spe"]
## Keys that carry a -6..+6 stage in battle. `acc`/`eva` use a different curve.
const STAGE_KEYS: Array = ["atk", "def", "spa", "spd", "spe", "acc", "eva"]

const MIN_STAGE := -6
const MAX_STAGE := 6
const MAX_IV := 31
const MAX_EV_PER_STAT := 252
const MAX_EV_TOTAL := 510

## nature -> [raised, lowered]. The five neutral natures raise and lower the same
## stat, which is exactly how the games encode them (index % 6 == index / 5).
const NATURES: Dictionary = {
	"hardy": ["atk", "atk"], "lonely": ["atk", "def"], "brave": ["atk", "spe"],
	"adamant": ["atk", "spa"], "naughty": ["atk", "spd"],
	"bold": ["def", "atk"], "docile": ["def", "def"], "relaxed": ["def", "spe"],
	"impish": ["def", "spa"], "lax": ["def", "spd"],
	"timid": ["spe", "atk"], "hasty": ["spe", "def"], "serious": ["spe", "spe"],
	"jolly": ["spe", "spa"], "naive": ["spe", "spd"],
	"modest": ["spa", "atk"], "mild": ["spa", "def"], "quiet": ["spa", "spe"],
	"bashful": ["spa", "spa"], "rash": ["spa", "spd"],
	"calm": ["spd", "atk"], "gentle": ["spd", "def"], "sassy": ["spd", "spe"],
	"careful": ["spd", "spa"], "quirky": ["spd", "spd"],
}


# --------------------------------------------------------------------------
# Natures
# --------------------------------------------------------------------------

## 1.1 for the raised stat, 0.9 for the lowered one, 1.0 otherwise (and always
## 1.0 for a neutral nature or an unknown name).
static func nature_mult(nature: String, stat: String) -> float:
	var pair: Array = NATURES.get(nature.to_lower(), [])
	if pair.size() != 2 or pair[0] == pair[1]:
		return 1.0
	if stat == pair[0]:
		return 1.1
	if stat == pair[1]:
		return 0.9
	return 1.0


static func nature_names() -> PackedStringArray:
	var out := PackedStringArray(NATURES.keys())
	out.sort()
	return out


# --------------------------------------------------------------------------
# The stat formula (Gen 3 onwards)
# --------------------------------------------------------------------------

## HP  = floor((2*B + IV + floor(EV/4)) * L / 100) + L + 10
## Rest= floor((floor((2*B + IV + floor(EV/4)) * L / 100) + 5) * nature)
static func calc_stat(base: int, iv: int, ev: int, level: int, nature_multiplier: float = 1.0,
		is_hp: bool = false) -> int:
	var lvl := maxi(level, 1)
	var core := floori(float((2 * base + iv + floori(ev / 4.0)) * lvl) / 100.0)
	if is_hp:
		if base == 1:
			return 1               # Shedinja
		return core + lvl + 10
	return floori(float(core + 5) * nature_multiplier)


## All six stats at once. `base_stats` is the DATA_CONTRACT 1 `stats` Dictionary.
static func calc_all(base_stats: Dictionary, ivs: Array, evs: Array, level: int,
		nature: String = "hardy") -> Dictionary:
	var out: Dictionary = {}
	for i in KEYS.size():
		var key: String = KEYS[i]
		out[key] = calc_stat(
			int(base_stats.get(key, 1)),
			int(ivs[i]) if i < ivs.size() else 0,
			int(evs[i]) if i < evs.size() else 0,
			level,
			nature_mult(nature, key),
			key == "hp")
	return out


# --------------------------------------------------------------------------
# Stat stages
# --------------------------------------------------------------------------

## atk/def/spa/spd/spe: (2+s)/2 going up, 2/(2-s) going down.
static func stage_mult(stage: int) -> float:
	var s := clampi(stage, MIN_STAGE, MAX_STAGE)
	if s >= 0:
		return float(2 + s) / 2.0
	return 2.0 / float(2 - s)


## accuracy/evasion use a 3-based curve instead: (3+s)/3 up, 3/(3-s) down.
static func acc_stage_mult(stage: int) -> float:
	var s := clampi(stage, MIN_STAGE, MAX_STAGE)
	if s >= 0:
		return float(3 + s) / 3.0
	return 3.0 / float(3 - s)


static func get_stage(mon: Dictionary, key: String) -> int:
	return int((mon.get("stages", {}) as Dictionary).get(key, 0))


## Change a stage, clamped to -6..+6. Returns the actual delta applied, so the
## caller can say "it won't go any higher!" when that is 0.
static func change_stage(mon: Dictionary, key: String, delta: int) -> int:
	if not mon.has("stages"):
		mon["stages"] = {}
	var stages: Dictionary = mon["stages"]
	var before: int = int(stages.get(key, 0))
	var after := clampi(before + delta, MIN_STAGE, MAX_STAGE)
	stages[key] = after
	return after - before


static func reset_stages(mon: Dictionary) -> void:
	var stages: Dictionary = {}
	for k: String in STAGE_KEYS:
		stages[k] = 0
	mon["stages"] = stages


## The stat a move actually divides by / multiplies with: raw stat times its
## stage multiplier. `ignore_negative` / `ignore_positive` implement the critical
## hit rule (a crit ignores the attacker's drops and the defender's boosts).
static func effective_stat(mon: Dictionary, key: String, ignore_negative: bool = false,
		ignore_positive: bool = false) -> int:
	var raw: int = int((mon.get("stats", {}) as Dictionary).get(key, 1))
	var stage := get_stage(mon, key)
	if (stage < 0 and ignore_negative) or (stage > 0 and ignore_positive):
		stage = 0
	return maxi(1, floori(float(raw) * stage_mult(stage) * stat_mult(mon, key)))


## A flat multiplier on one stat, held in `volatile.statMult` and applied by
## [method effective_stat] on top of the stage curve.
##
## STAGES ARE NOT THE RIGHT TOOL FOR EVERY BOOST. A stat stage is a -6..+6 step on
## a fixed curve, it is what Swords Dance and Intimidate move, and it is visible to
## Haze and to a critical hit. Protosynthesis multiplying the bearer's best stat by
## 1.3 is none of those things, and forcing it into a stage would round to the
## wrong number AND make a crit ignore it.
##
## Living in `volatile` means `Status.clear_volatiles()` already drops it on a
## switch, which is the duration the Paradox abilities want. Anything else needing
## a non-stage multiplier (Flower Gift, Slow Start) reuses this rather than
## inventing a second mechanism.
static func stat_mult(mon: Dictionary, key: String) -> float:
	var table: Variant = (mon.get("volatile", {}) as Dictionary).get("statMult", null)
	if not (table is Dictionary):
		return 1.0
	return float((table as Dictionary).get(key, 1.0))


# --------------------------------------------------------------------------
# Accuracy
# --------------------------------------------------------------------------

## `move_accuracy` of null (DATA_CONTRACT 2: "accuracy null = never misses") or
## <= 0 always hits. Otherwise accuracy * accStage/evaStage curve, rolled once.
static func accuracy_check(move_accuracy: Variant, attacker: Dictionary, defender: Dictionary,
		rng: RandomNumberGenerator) -> bool:
	if move_accuracy == null:
		return true
	var acc := float(move_accuracy)
	if acc <= 0.0:
		return true
	var stage := clampi(get_stage(attacker, "acc") - get_stage(defender, "eva"), MIN_STAGE, MAX_STAGE)
	var chance := acc * acc_stage_mult(stage)
	return rng.randf() * 100.0 < chance


# --------------------------------------------------------------------------
# Building a battle-ready Pokemon
# --------------------------------------------------------------------------

## Build the canonical in-battle Dictionary.
##
## Keys produced (superset of the save shape):
## [codeblock]
## species int, name String, level int, exp int,
## types PackedStringArray, ivs Array[int x6], evs Array[int x6], nature String,
## ability String(slug), item String, friendship int,
## stats {hp,atk,def,spa,spd,spe}, maxHp int, hp int,
## moves [ {id,name,type,category,power,accuracy,pp,maxPp,priority,effect,effectChance} ],
## status String(""|burn|poison|toxic|paralysis|sleep|freeze), statusCounter int,
## stages {atk,def,spa,spd,spe,acc,eva}, volatile {confusion,flinch,...}
## [/codeblock]
##
## `opts` accepts any of: name, ivs, evs, nature, ability, item, moves
## (Array of move slugs), hp, exp, friendship, species_data (a DATA_CONTRACT 1
## record used instead of a DataRegistry lookup -- this is how tests stay
## independent of the data stream).
static func build(species_id: int, level: int, opts: Dictionary = {}) -> Dictionary:
	var reg := Deps.registry()
	var sp: Dictionary = opts.get("species_data", {})
	if sp.is_empty() and reg != null:
		sp = reg.get_species(species_id)

	var ivs: Array = opts.get("ivs", [31, 31, 31, 31, 31, 31])
	var evs: Array = opts.get("evs", [0, 0, 0, 0, 0, 0])
	var nature: String = String(opts.get("nature", "hardy")).to_lower()
	var base: Dictionary = sp.get("stats", {"hp": 50, "atk": 50, "def": 50, "spa": 50, "spd": 50, "spe": 50})

	var mon: Dictionary = {
		"species": species_id,
		"name": String(opts.get("name", sp.get("name", "MON"))),
		"level": maxi(level, 1),
		"exp": int(opts.get("exp", 0)),
		"types": PackedStringArray(sp.get("types", ["normal"])),
		"ivs": ivs,
		"evs": evs,
		"nature": nature,
		"ability": String(opts.get("ability", _first_ability(sp))),
		"item": String(opts.get("item", "")),
		"friendship": int(opts.get("friendship", 70)),
		"baseExp": int(sp.get("baseExp", 64)),
		"growthRate": String(sp.get("growthRate", "medium-fast")),
		"status": String(opts.get("status", "")),
		"statusCounter": int(opts.get("statusCounter", 0)),
		"volatile": {"confusion": 0, "flinch": false},
		"moves": [],
	}

	mon["stats"] = calc_all(base, ivs, evs, mon["level"], nature)
	mon["maxHp"] = int((mon["stats"] as Dictionary)["hp"])
	mon["hp"] = int(opts.get("hp", mon["maxHp"]))
	reset_stages(mon)

	for slug: Variant in (opts.get("moves", []) as Array):
		var m := make_move(String(slug), reg)
		if not m.is_empty():
			(mon["moves"] as Array).append(m)

	return mon


## First normal ability slug of a DATA_CONTRACT 1 species record, or "".
static func _first_ability(sp: Dictionary) -> String:
	var abilities: Array = sp.get("abilities", [])
	return String(abilities[0]) if not abilities.is_empty() else ""


## Resolve a move slug into the in-battle move Dictionary. Unknown slugs return
## an empty Dictionary rather than a half-built move.
static func make_move(slug: String, reg: Object = null) -> Dictionary:
	var r: Object = reg if reg != null else Deps.registry()
	var src: Dictionary = {}
	if r != null:
		src = r.get_move_by_name(slug)
	if src.is_empty():
		return {}
	var pp := int(src.get("pp", 10))
	return {
		"id": int(src.get("id", 0)),
		"name": String(src.get("name", slug)),
		"slug": slug.to_lower(),
		"type": String(src.get("type", "normal")),
		"category": String(src.get("category", "status")),
		"power": int(src.get("power", 0)) if src.get("power", null) != null else 0,
		"accuracy": src.get("accuracy", null),
		"pp": pp,
		"maxPp": pp,
		"priority": int(src.get("priority", 0)),
		# 57 Gen 9 rows carry "effect": null, and String(null) is a hard error on
		# this engine -- it crashed make_move() outright for population-bomb.
		"effect": String(src.get("effect", "")) if src.get("effect", null) != null else "",
		"effectChance": int(src.get("effectChance", 0)) if src.get("effectChance", null) != null else 0,
		# `flags` and `effectId` are what the ability layer branches on: the
		# `contact` flag decides Aura Guard / Unseen Fist / Piercing Drill, and
		# `effectId` is the only reliable multi-hit discriminator (57 Gen 9 moves
		# have "effect": null, so the effect STRING finds nothing). make_move()
		# dropping them silently disabled every contact-aware ability.
		"flags": PackedStringArray(src.get("flags", [])),
		"effectId": int(src.get("effectId", 0)) if src.get("effectId", null) != null else 0,
	}


## True when the mon has fainted. `hp <= 0` is the single source of truth.
static func is_fainted(mon: Dictionary) -> bool:
	return int(mon.get("hp", 0)) <= 0


static func display_name(mon: Dictionary) -> String:
	return String(mon.get("nickname", mon.get("name", "MON")))


## Damage / heal helper that keeps hp inside 0..maxHp and returns the real delta.
static func apply_hp_delta(mon: Dictionary, delta: int) -> int:
	var max_hp: int = int(mon.get("maxHp", 1))
	var before: int = int(mon.get("hp", 0))
	var after := clampi(before + delta, 0, max_hp)
	mon["hp"] = after
	return after - before
