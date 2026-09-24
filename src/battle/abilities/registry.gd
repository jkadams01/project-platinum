extends RefCounted
## slug -> implementation, plus the static dispatch facade the engine calls.
##
## ADDING AN ABILITY IS ONE LINE in [constant IMPL] plus one new file. Nothing
## else in the engine changes, which is what lets many abilities land in parallel.
##
## LOADED ONCE: [constant IMPL] holds `preload()`s, so every ability script is
## resolved at COMPILE time and a typo is a parse error rather than a silent
## runtime miss. [member _cache] then holds ONE instance per slug for the life of
## the process -- safe because abilities are stateless (see ability.gd).
##
## NO AUTOLOAD DEPENDENCY: everything here resolves from `const` + `preload`, the
## way deps.gd avoids hard autoload references, so abilities work headless with no
## DataRegistry alive.
##
## NO-OP BY DEFAULT, in two layers:
##   1. ability.gd defines every hook returning the neutral value;
##   2. [method of] returns null for any slug it does not know, and every
##      dispatcher below coalesces that to the neutral value.
## So the engine calls these dispatchers UNCONDITIONALLY -- there is no
## `if ability == "..."` anywhere in battle_engine.gd, and the other ~300
## abilities in data/abilities.json cost one Dictionary miss each.
##
## HARD RULE: an ability file must never preload this file. Abilities are leaves.

const IMPL: Dictionary = {
	"aura-guard": preload("res://src/battle/abilities/aura-guard.gd"),
	"delta-stream": preload("res://src/battle/abilities/delta-stream.gd"),
	"dragonize": preload("res://src/battle/abilities/dragonize.gd"),
	"eelevate": preload("res://src/battle/abilities/eelevate.gd"),
	"fire-mane": preload("res://src/battle/abilities/fire_mane.gd"),
	"mega-sol": preload("res://src/battle/abilities/mega_sol.gd"),
	"parental-bond": preload("res://src/battle/abilities/parental-bond.gd"),
	"piercing-drill": preload("res://src/battle/abilities/piercing-drill.gd"),
	"shadow-tag": preload("res://src/battle/abilities/shadow-tag.gd"),
	"skill-link": preload("res://src/battle/abilities/skill-link.gd"),
	"spicy-spray": preload("res://src/battle/abilities/spicy-spray.gd"),
	"stalwart": preload("res://src/battle/abilities/stalwart.gd"),
	"steadfast": preload("res://src/battle/abilities/steadfast.gd"),
	"unseen-fist": preload("res://src/battle/abilities/unseen-fist.gd"),
}

## slug -> one shared instance. Abilities are stateless, so one instance serves
## every battle and both sides.
static var _cache: Dictionary = {}


# --------------------------------------------------------------------------
# Resolution
# --------------------------------------------------------------------------

## The implementation for `slug`, or null when nothing implements it.
static func of(slug: String) -> RefCounted:
	if slug.is_empty():
		return null
	if _cache.has(slug):
		return _cache[slug]
	if not IMPL.has(slug):
		return null
	var script: GDScript = IMPL[slug]
	var inst: RefCounted = script.new()
	_cache[slug] = inst
	return inst


## The implementation for whatever `mon` currently has. Null for an empty or
## fainted mon -- a fainted Pokemon's ability does nothing, which is the rule
## that keeps Shadow Tag from trapping after its holder dies.
##
## Reads `mon["ability"]`, which mega.gd rewrites during `evolve()`; that is how
## Mega Evolution grants an ability mid-battle with no extra plumbing.
static func for_mon(mon: Dictionary) -> RefCounted:
	if mon.is_empty():
		return null
	if int(mon.get("hp", 0)) <= 0:
		return null
	return of(String(mon.get("ability", "")))


## Like [method for_mon] but WITHOUT the faint check, for the one hook that fires
## from beyond the grave. The bearer was alive when the hit connected, and the games
## resolve on-damage abilities (Spicy Spray, Rough Skin, Static, Flame Body) even
## when that hit killed their holder -- Bulbapedia is explicit for Spicy Spray:
## it activates "even if the Spicy Spray user faints". Only [method hit_taken] may
## use this; every other hook keeps the faint check, which is what stops a dead
## Shadow Tag from trapping.
static func _impl_after_hit_taken(mon: Dictionary) -> RefCounted:
	if mon.is_empty():
		return null
	return of(String(mon.get("ability", "")))


static func has_impl(slug: String) -> bool:
	return IMPL.has(slug)


static func slugs() -> PackedStringArray:
	var out := PackedStringArray(IMPL.keys())
	out.sort()
	return out


## Every implementation whose `field_state()` equals `state`, so a field effect is
## not tied to whoever happens to be attacking.
static func field_impls(state: String) -> Array:
	var out: Array = []
	# "" is not a field state, it is the absence of one. Without this guard every
	# ability in IMPL matches (they all return "" from field_state()) and the
	# onEffectiveness loop would run 14 no-op calls per defender type component.
	if state.is_empty():
		return out
	for slug: String in IMPL.keys():
		var impl := of(slug)
		if impl != null and impl.field_state() == state:
			out.append(impl)
	return out


# --------------------------------------------------------------------------
# Small shared helpers
# --------------------------------------------------------------------------

## `flags` survives Stats.make_move() as an Array (JSON) or PackedStringArray.
static func move_has_flag(move: Dictionary, flag: String) -> bool:
	var flags: Variant = move.get("flags", null)
	if flags is PackedStringArray:
		return (flags as PackedStringArray).has(flag)
	if flags is Array:
		return (flags as Array).has(flag)
	return false


static func makes_contact(move: Dictionary) -> bool:
	return move_has_flag(move, "contact")


# --------------------------------------------------------------------------
# Dispatchers -- the engine calls these, never IMPL directly
# --------------------------------------------------------------------------

## 1. onBeforeMove -> {cancel: bool, messages: Array}
static func before_move(mon: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var impl := for_mon(mon)
	if impl == null:
		return {}
	var c := ctx.duplicate()
	c["mon"] = mon
	return impl.on_before_move(c)


## 2. onModifyMoveType -> {type: String, power_mult: float}. The CALLER passes a
## duplicate of the move dictionary; this never mutates what it is given.
static func modify_move(mon: Dictionary, move: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var impl := for_mon(mon)
	if impl == null:
		return {}
	var c := ctx.duplicate()
	c["mon"] = mon
	c["move"] = move
	return impl.on_modify_move(c)


## 3. onDamageCalc, BOTH sides folded into one Dictionary. Every multiplier
## defaults to 1.0 and the two sides multiply together, so Fire Mane on the
## attacker and Aura Guard on the defender compose without either knowing about
## the other.
##
## Returns `{atk_mult: float, power_mult: float, damage_mult: float}`.
static func damage_mods(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"atk_mult": 1.0, "power_mult": 1.0, "damage_mult": 1.0}
	_fold_damage(out, attacker, "attacker", attacker, defender, move, ctx)
	_fold_damage(out, defender, "defender", attacker, defender, move, ctx)
	return out


static func _fold_damage(out: Dictionary, bearer: Dictionary, role: String,
		attacker: Dictionary, defender: Dictionary, move: Dictionary, ctx: Dictionary) -> void:
	var impl := for_mon(bearer)
	if impl == null:
		return
	var c := ctx.duplicate()
	c["mon"] = bearer
	c["role"] = role
	c["attacker"] = attacker
	c["defender"] = defender
	c["move"] = move
	c["contact"] = makes_contact(move)
	if not c.has("category"):
		c["category"] = String(move.get("category", "status"))
	if not c.has("move_type"):
		c["move_type"] = String(move.get("type", "normal"))
	var got: Dictionary = impl.on_damage_calc(c)
	for key: String in ["atk_mult", "power_mult", "damage_mult"]:
		if got.has(key):
			out[key] = float(out[key]) * float(got[key])


## 4. onEffectiveness, for ONE defender type component. Field-scoped abilities
## (Delta Stream) reach every Flying-type on the field, so this asks the field
## implementations rather than only the defender's own ability.
static func effectiveness(mult: float, move_type: String, def_type: String,
		defender: Dictionary, weather: String = "") -> float:
	var out := mult
	var c: Dictionary = {
		"mult": out, "move_type": move_type, "def_type": def_type,
		"defender": defender, "weather": weather,
	}
	var impl := for_mon(defender)
	if impl != null:
		c["mult"] = out
		out = impl.on_effectiveness(c)
	for field: Variant in field_impls(weather):
		if field == impl:
			continue
		c["mult"] = out
		out = (field as RefCounted).on_effectiveness(c)
	return out


## 5. onTypeImmunity -> {immune: bool, heal_fraction: float, ungrounded: bool}
static func type_immunity(defender: Dictionary, move_type: String,
		ctx: Dictionary = {}) -> Dictionary:
	var impl := for_mon(defender)
	if impl == null:
		return {}
	var c := ctx.duplicate()
	c["mon"] = defender
	c["defender"] = defender
	c["move_type"] = move_type
	return impl.on_type_immunity(c)


## 6. onWeatherView. The weather THIS mon's move sees; the field is unchanged.
static func weather_view(mon: Dictionary, weather: String) -> String:
	var impl := for_mon(mon)
	if impl == null:
		return weather
	return impl.on_weather_view({"mon": mon, "weather": weather})


## 7. onMultiHitCount -> {hits: int, single_accuracy: bool}. Decided ONCE, before
## the hit loop.
static func hit_count(mon: Dictionary, move: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var impl := for_mon(mon)
	if impl == null:
		return {}
	var c := ctx.duplicate()
	c["mon"] = mon
	c["move"] = move
	return impl.on_multi_hit_count(c)


## 8. onProtectCheck -> {pierce: bool, damage_mult: float}. Called only when the
## target is protected; the BEARER IS THE ATTACKER trying to punch through.
static func protect_check(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> Dictionary:
	var impl := for_mon(attacker)
	if impl == null:
		return {}
	var c := ctx.duplicate()
	c["mon"] = attacker
	c["attacker"] = attacker
	c["defender"] = defender
	c["move"] = move
	c["contact"] = makes_contact(move)
	return impl.on_protect_check(c)


## 9 + 10. onHitTaken, plus onContactHit when the move made contact. The BEARER
## IS THE ONE THAT WAS HIT. Called after each connecting hit and BEFORE the faint
## break, which is what lets Spicy Spray burn from beyond the grave.
##
## Returns `{status: String, messages: Array}` with the two hooks' messages
## concatenated.
static func hit_taken(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> Dictionary:
	var impl := _impl_after_hit_taken(defender)
	if impl == null:
		return {}
	var contact := makes_contact(move)
	var c := ctx.duplicate()
	c["mon"] = defender
	c["attacker"] = attacker
	c["defender"] = defender
	c["move"] = move
	c["contact"] = contact
	if not c.has("category"):
		c["category"] = String(move.get("category", "status"))
	var out: Dictionary = impl.on_hit_taken(c)
	if not contact:
		return out
	var extra: Dictionary = impl.on_contact_taken(c)
	if extra.is_empty():
		return out
	if out.is_empty():
		return extra
	var merged := out.duplicate()
	var msgs: Array = (merged.get("messages", []) as Array).duplicate()
	msgs.append_array(extra.get("messages", []) as Array)
	merged["messages"] = msgs
	if extra.has("status"):
		merged["status"] = extra["status"]
	return merged


## 11. onAfterHit -> {stat_boosts: Dictionary, messages: Array}. `ctx.ko` is true
## when that hit fainted the target. The BEARER IS THE ATTACKER.
static func after_hit(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> Dictionary:
	var impl := for_mon(attacker)
	if impl == null:
		return {}
	var c := ctx.duplicate()
	c["mon"] = attacker
	c["attacker"] = attacker
	c["defender"] = defender
	c["move"] = move
	return impl.on_after_hit(c)


## 12. onFlinch -> {stat_boosts: Dictionary, messages: Array}. Called ONLY where
## the flinch message is printed.
static func flinch(mon: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var impl := for_mon(mon)
	if impl == null:
		return {}
	var c := ctx.duplicate()
	c["mon"] = mon
	return impl.on_flinch(c)


## 13. onSwitchAttempt -> {block: bool, message: String}. THE BEARER IS THE
## TRAPPER; `escaper` is the one trying to leave. `reason` is "switch" or "run".
## NEVER call this for a forced replacement after a faint.
static func escape_block(trapper: Dictionary, escaper: Dictionary,
		reason: String = "switch") -> Dictionary:
	var impl := for_mon(trapper)
	if impl == null:
		return {}
	return impl.on_switch_attempt({
		"mon": trapper, "trapper": trapper, "escaper": escaper, "reason": reason,
	})


## 14. onFieldEnter / onFieldLeave, folded into one "what is the field now?" pass.
## Re-evaluated after every field change -- switch-in, Mega Evolution (which is
## how Rayquaza ACQUIRES Delta Stream) and every faint.
##
## `active_mons` is every Pokemon currently on the field, both sides.
## Returns `{weather: String, weather_turns: int, messages: Array}`.
static func field_refresh(active_mons: Array, weather: String,
		weather_turns: int = 0) -> Dictionary:
	var out: Dictionary = {"weather": weather, "weather_turns": weather_turns, "messages": []}
	var holder: RefCounted = null
	for mon: Dictionary in active_mons:
		var impl := for_mon(mon)
		if impl != null and impl.field_state() != "":
			holder = impl
			break
	if holder != null:
		var got: Dictionary = holder.on_field_enter({"weather": weather})
		if got.has("weather") and String(got["weather"]) != weather:
			out["weather"] = String(got["weather"])
			out["weather_turns"] = int(got.get("weather_turns", 0))
			out["messages"] = (got.get("messages", []) as Array).duplicate()
		return out
	# The holder left: an ability-owned field state just ends. The games do not
	# restore whatever weather was there before it, so the slot is simply emptied.
	# on_field_leave() is what supplies the "it dissipated" line, so the log reads
	# symmetrically with the on_field_enter() announcement.
	var leaving := field_impls(weather)
	if not leaving.is_empty():
		var gone: Dictionary = (leaving[0] as RefCounted).on_field_leave({"weather": weather})
		out["weather"] = String(gone.get("weather", ""))
		out["weather_turns"] = int(gone.get("weather_turns", 0))
		out["messages"] = (gone.get("messages", []) as Array).duplicate()
	return out


## 16. onWeatherSet. True when any ability on the field stops `weather` from
## being set (Delta Stream's strong winds refuse Sunny Day and friends).
static func blocks_weather_set(active_mons: Array, weather: String,
		current: String = "") -> bool:
	for mon: Dictionary in active_mons:
		var impl := for_mon(mon)
		if impl == null:
			continue
		if impl.blocks_weather_set({"mon": mon, "weather": weather, "current": current}):
			return true
	return false


## 17. onRedirect. True when `mon`'s moves ignore target redirection. No caller in
## a single-battle engine; the hook exists so the resolver can just ask if doubles
## ever land.
static func ignores_redirection(mon: Dictionary) -> bool:
	var impl := for_mon(mon)
	if impl == null:
		return false
	return impl.ignores_redirection({"mon": mon})


## The single grounding seam: abilities (eelevate, levitate), items (air-balloon,
## iron-ball) and moves (Gravity, Smack Down, Ingrain, Thousand Arrows) all land
## here rather than in five places. `vol["grounded_by"]` wins over any ability,
## because every grounding effect in the games overrides Levitate.
static func is_grounded(mon: Dictionary) -> bool:
	if mon.is_empty():
		return true
	var vol: Dictionary = mon.get("volatile", {})
	if bool(vol.get("grounded_by", false)):
		return true
	var impl := for_mon(mon)
	if impl != null:
		var got: Dictionary = impl.on_type_immunity({
			"mon": mon, "defender": mon, "move_type": "ground", "query": "grounded",
		})
		if bool(got.get("ungrounded", false)):
			return false
	return not PackedStringArray(mon.get("types", PackedStringArray())).has("flying")
