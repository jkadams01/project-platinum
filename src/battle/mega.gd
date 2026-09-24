extends RefCounted
## Mega Evolution. **The only battle gimmick in this game** (DATA_CONTRACT 11).
##
## There is deliberately no Dynamax, Gigantamax, Z-Move, Terastal or Primal
## Reversion code path anywhere in this file, and [method _is_excluded] actively
## rejects any form that smells like one at load time, so bad data cannot sneak a
## second gimmick in through `data/megas.json`. `tests/test_mega.gd` asserts that.
##
## WHAT THIS FILE OWNS
##
##   * the form table -- `data/megas.json` (DATA_CONTRACT 11.1), read through
##     `DataRegistry.mega_forms_for()` when that autoload offers it and straight
##     off disk when it does not, so this stream does not block on the data one;
##   * the gate: [method can_mega_evolve] / [method check];
##   * the transform: [method evolve] and its inverse [method revert].
##
## The turn loop itself lives in `battle_engine.gd`, which resolves Mega
## Evolution at the START of the turn before any move, so the Mega's Speed orders
## that same turn (DATA_CONTRACT 11.2). Nothing in here reads the turn state.
##
## THE TWO SPECIAL CASES, both decided and both handled here:
##
##   * **Mega Rayquaza has no stone.** Its entry is `"stone": null` with
##     `"requiresMove": "dragon-ascent"`; it Mega Evolves off the MOVESET instead
##     of the held item, and holds no stone at all. It still obeys
##     one-Mega-per-side. See [method eligible_form].
##   * **Primal Reversion is OUT.** Primal Groudon/Kyogre are not Megas and are
##     not in this game. No Red Orb, no Blue Orb. [method _is_excluded] refuses
##     them even if a data build emits them.
##
## ABILITIES ARE AN ARRAY (`"abilities": [...]`, DATA_CONTRACT 11.1), not a
## string: a few Legends Z-A Megas carry two (Mega Heatran = Flash Fire + Flame
## Body). The engine has one live ability slot, so element 0 becomes `ability`
## and the whole array is parked on `megaAbilities` for whatever implements a
## second slot later. Nine Z-A forms ship `"abilities": []` with
## `"abilityStatus": "pending-owner"` (DATA_CONTRACT 11.5): those KEEP the base
## form's ability rather than losing it, and are flagged on the mon so the UI can
## say so. Nothing here invents an ability.
##
## HP: the contract says recompute stats **keeping the current HP fraction**, not
## the current HP value, so 50% before is 50% after on a bigger bar. In practice
## no Mega changes its base HP, with two apparent exceptions that are really
## alternate-forme bookkeeping: Mega Floette (74, from the Eternal Flower, not
## default Floette's 54) and Mega Zygarde (216, from the Complete Forme, not the
## 50% Forme's 108). The rule still earns its keep on the way back, where the bar
## shrinks. A Mega Evolution can never faint its own user: the new HP floors at 1.
##
## LEVEL CAPS: Mega Evolution does not touch `level`, `exp`, `growthRate` or
## `species` -- `species` stays the BASE dex id -- so it cannot affect EXP capping
## (DATA_CONTRACT 11.3). [method evolve] never writes those keys.

const Stats := preload("res://src/battle/stats.gd")
const Deps := preload("res://src/battle/deps.gd")

## The Key Stone item id. `GameState.has_key_stone()` is the real gate; this is
## the bag key it reads.
const KEY_ITEM := "key-stone"

const DATA_PATH := "res://data/megas.json"
const FIXTURE_PATH := "res://tests/fixtures/megas.json"

## Keys [method evolve] writes and [method revert] erases. Listed so a reader can
## see the entire footprint of a Mega on a party Dictionary in one place -- and so
## that a mon which somehow reaches the save file mid-Mega can be cleaned.
const MON_KEYS: Array = ["isMega", "megaForm", "megaBase", "megaAbilities",
	"megaAbilityStatus"]

## Substrings that mark a form as an excluded gimmick (DATA_CONTRACT 11.4/11.5).
## Matched against the form id and name, case-insensitively.
const EXCLUDED: Array = ["dynamax", "gigantamax", "gmax", "z-move", "zmove",
	"terastal", "tera-", "primal"]

## `"abilities": []` plus this status means the owner has not ruled yet
## (DATA_CONTRACT 11.5). Not an error; not a licence to guess.
const PENDING_ABILITY := "pending-owner"

static var _by_base: Dictionary = {}      # int base dex id -> Array[Dictionary]
static var _by_id: Dictionary = {}        # String form id  -> Dictionary
static var _meta: Dictionary = {}         # keyItem/rule/revertsAfterBattle
static var _rejected: Array = []          # ids refused by _is_excluded
static var _loaded := false
static var _injected := false             # set_forms() beats every other source


# --------------------------------------------------------------------------
# The form table
# --------------------------------------------------------------------------

## Load `forms` directly, bypassing `data/megas.json` and the registry. Returns
## the number accepted; excluded gimmicks are dropped and counted in
## [method rejected_ids]. Tests use this; so can a data build that wants to hand
## the engine a table it already has in memory.
static func set_forms(forms: Array, meta: Dictionary = {}) -> int:
	_by_base.clear()
	_by_id.clear()
	_rejected.clear()
	_meta = {"keyItem": KEY_ITEM, "rule": "one-per-battle", "revertsAfterBattle": true}
	for k: Variant in meta:
		_meta[String(k)] = meta[k]
	for entry: Variant in forms:
		if entry is Dictionary:
			_add(entry)
	_injected = true
	_loaded = true
	return _by_id.size()


## Drop the injected table and go back to reading the real data.
static func clear_forms() -> void:
	_by_base.clear()
	_by_id.clear()
	_rejected.clear()
	_meta.clear()
	_injected = false
	_loaded = false


static func _add(form: Dictionary) -> bool:
	var id := _opt(form, "id")
	if id.is_empty():
		return false
	if _is_excluded(form):
		if not _rejected.has(id):
			_rejected.append(id)
		return false
	var base := int(form.get("base", 0))
	if base <= 0:
		return false
	_by_id[id] = form
	if not _by_base.has(base):
		_by_base[base] = []
	(_by_base[base] as Array).append(form)
	return true


## True for anything that is not a Mega: an excluded gimmick (11.4) or a Primal
## Reversion (11.5). Checked on the id, the name and the stone, because a build
## that emits Primal Groudon will name the item `red-orb` even if it calls the
## form something else.
static func _is_excluded(form: Dictionary) -> bool:
	var haystack := ("%s %s %s" % [
		_opt(form, "id"), _opt(form, "name"), _stone_of(form)]).to_lower()
	for bad: String in EXCLUDED:
		if haystack.contains(bad):
			return true
	return haystack.contains("red-orb") or haystack.contains("blue-orb")


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = null
	for path: String in [DATA_PATH, FIXTURE_PATH]:
		if not FileAccess.file_exists(path):
			continue
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		parsed = JSON.parse_string(f.get_as_text())
		if parsed != null:
			break
	if parsed is Dictionary:
		set_forms((parsed as Dictionary).get("forms", []), parsed)
		_injected = false      # this came from disk, not an injection


## Every Mega form of `species_id` (a BASE national dex id), in table order.
## Charizard and Mewtwo return two; the held stone decides which.
static func forms_for(species_id: int) -> Array:
	if not _injected:
		var reg := Deps.registry()
		if reg != null and reg.has_method("mega_forms_for"):
			var from_reg: Variant = reg.mega_forms_for(species_id)
			if from_reg is Array:
				var clean: Array = []
				for f: Variant in from_reg:
					if f is Dictionary and not _is_excluded(f):
						clean.append(f)
				return clean
	_ensure_loaded()
	return (_by_base.get(species_id, []) as Array).duplicate()


static func form_by_id(form_id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id.get(form_id, {})


static func form_count() -> int:
	_ensure_loaded()
	return _by_id.size()


## Ids refused by [method _is_excluded] during the last load. Should always be
## empty against real data; a test asserts it.
static func rejected_ids() -> Array:
	_ensure_loaded()
	return _rejected.duplicate()


static func table_loaded() -> bool:
	_ensure_loaded()
	return not _by_id.is_empty()


# --------------------------------------------------------------------------
# Reading a form
# --------------------------------------------------------------------------

## The form's stone item id. `""` for Mega Rayquaza, whose `stone` is JSON null.
static func _stone_of(form: Dictionary) -> String:
	return _opt(form, "stone")


## An optional string field, `""` when the key is missing **or** explicitly null.
##
## This exists because `data/megas.json` writes the field on EVERY form and uses
## `null` for "not applicable" -- `"requiresForm": null`, `"requiresMove": null`
## -- and `String(null)` is not the empty string. Reading those with a plain
## `String(form.get(k, ""))` would make every stoned form look like it demanded a
## specific base forme, and refuse all 97 of them.
static func _opt(form: Dictionary, key: String) -> String:
	var v: Variant = form.get(key, null)
	return "" if v == null else String(v)


## The ability slugs of a form, in order. Empty for the nine Z-A forms awaiting an
## owner ruling (DATA_CONTRACT 11.5).
static func abilities_of(form: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var raw: Variant = form.get("abilities", [])
	if raw is Array:
		for a: Variant in raw:
			var slug := String(a).strip_edges()
			if not slug.is_empty():
				out.append(slug)
	elif raw != null and String(raw) != "":
		# Tolerates a table still on the old single-string `ability` shape.
		out.append(String(raw))
	return out


## True when the form's ability is unresolved and must not be guessed.
static func ability_pending(form: Dictionary) -> bool:
	return abilities_of(form).is_empty()


## True when this form needs no stone at all -- the Mega Rayquaza rule.
static func is_stoneless(form: Dictionary) -> bool:
	return _stone_of(form).is_empty() and not _opt(form, "requiresMove").is_empty()


# --------------------------------------------------------------------------
# The gate (DATA_CONTRACT 11.2)
# --------------------------------------------------------------------------

## Slug of a move the way `Stats.make_move()` writes it.
static func _slug(s: String) -> String:
	return s.to_lower().strip_edges().replace(" ", "-").replace("_", "-")


## True when `mon` has `slug` in its CURRENT moveset. PP is irrelevant: knowing
## Dragon Ascent is what Mega Evolves Rayquaza, not being able to use it.
static func knows_move(mon: Dictionary, slug: String) -> bool:
	if slug.is_empty():
		return false
	var want := _slug(slug)
	for m: Variant in (mon.get("moves", []) as Array):
		if m is Dictionary:
			if _slug(String((m as Dictionary).get("slug", ""))) == want:
				return true
			if _slug(String((m as Dictionary).get("name", ""))) == want:
				return true
		elif _slug(String(m)) == want:
			return true
	return false


## Some forms are restricted to one form of the base species: Mega Floette needs
## the Eternal Flower, Mega Zygarde comes from the Complete Forme, Mega Meowstic
## and Mega Tatsugiri exist per cosmetic form. When a table entry carries
## `requiresForm`, the mon's `form` must match it; when it does not, anything
## goes. Forward-compatible: no data has to grow the field for this to work.
static func _form_gate_ok(mon: Dictionary, form: Dictionary) -> bool:
	var need := _opt(form, "requiresForm")
	if need.is_empty():
		return true
	return _slug(String(mon.get("form", ""))) == _slug(need)


## The form `mon` would Mega Evolve into right now, judged ONLY on what it is
## carrying or knows -- the Key Stone and one-per-side are [method check]'s job.
## `{}` when nothing matches.
static func eligible_form(mon: Dictionary) -> Dictionary:
	for form: Dictionary in forms_for(int(mon.get("species", 0))):
		if not _form_gate_ok(mon, form):
			continue
		if is_stoneless(form):
			if knows_move(mon, _opt(form, "requiresMove")):
				return form
			continue
		var stone := _stone_of(form)
		if not stone.is_empty() and String(mon.get("item", "")) == stone:
			return form
	return {}


## Does the trainer on this side own a Key Stone?
##
## `opts["has_key_stone"]` wins when present (that is how the AI side and the
## tests say so). Otherwise `GameState.has_key_stone()` (DATA_CONTRACT 11.2),
## then the bag directly, then false. False is the right default: no Key Stone
## means the Mega button never draws.
static func holder_has_key_stone(opts: Dictionary = {}) -> bool:
	if opts.has("has_key_stone") and opts["has_key_stone"] != null:
		return bool(opts["has_key_stone"])
	var st := Deps.state()
	if st == null:
		return false
	if st.has_method("has_key_stone"):
		return bool(st.has_key_stone())
	var bag: Variant = st.get("bag")
	if bag is Dictionary:
		return int((bag as Dictionary).get(KEY_ITEM, 0)) > 0
	return false


## The full gate, with a reason. Returns
## `{ok: bool, reason: String, form: Dictionary}`; `reason` is `""` when ok and
## otherwise one of `fainted`, `already-mega`, `side-used`, `no-key-stone`,
## `no-form` -- which is what makes a greyed-out Mega button explainable.
##
## `opts`: `mega_used` (bool, has this side already Mega Evolved this battle),
## `has_key_stone` (bool, overrides GameState).
static func check(mon: Dictionary, opts: Dictionary = {}) -> Dictionary:
	if mon.is_empty() or Stats.is_fainted(mon):
		return {"ok": false, "reason": "fainted", "form": {}}
	if is_mega(mon):
		return {"ok": false, "reason": "already-mega", "form": {}}
	if bool(opts.get("mega_used", false)):
		return {"ok": false, "reason": "side-used", "form": {}}
	if not holder_has_key_stone(opts):
		return {"ok": false, "reason": "no-key-stone", "form": {}}
	var form := eligible_form(mon)
	if form.is_empty():
		return {"ok": false, "reason": "no-form", "form": {}}
	return {"ok": true, "reason": "", "form": form}


## DATA_CONTRACT 11.2: true when the holder has the Key Stone, the Pokemon holds
## the matching Mega Stone (or knows the required move, for Mega Rayquaza), and
## this side has not Mega Evolved yet this battle.
static func can_mega_evolve(mon: Dictionary, opts: Dictionary = {}) -> bool:
	return bool(check(mon, opts)["ok"])


static func is_mega(mon: Dictionary) -> bool:
	return bool(mon.get("isMega", false))


static func form_id_of(mon: Dictionary) -> String:
	return String(mon.get("megaForm", ""))


# --------------------------------------------------------------------------
# The transform
# --------------------------------------------------------------------------

## Mega Evolve `mon` into `form` (or into [method eligible_form] when `form` is
## empty). Returns `{ok: bool, formId: String, reason: String, messages: Array}`.
##
## Changed: `types`, `stats`, `maxHp`, `hp` (same FRACTION), `ability`, `name`.
## Untouched, deliberately: `species`, `level`, `exp`, `growthRate`, `moves`
## (and their PP), `status`, `statusCounter`, `stages`, `volatile`, `item`,
## `ivs`, `evs`, `nature`, `friendship`, `nickname`.
##
## Callers must enforce one-per-side themselves -- this function does not know
## about sides. `battle_engine.gd` sets `sides[side].megaUsed` right after.
static func evolve(mon: Dictionary, form: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var target := form
	if target.is_empty():
		target = eligible_form(mon)
	if target.is_empty():
		return {"ok": false, "formId": "", "reason": "no-form", "messages": []}
	if is_mega(mon):
		return {"ok": false, "formId": form_id_of(mon), "reason": "already-mega", "messages": []}
	if Stats.is_fainted(mon):
		return {"ok": false, "formId": "", "reason": "fainted", "messages": []}
	if _is_excluded(target):
		return {"ok": false, "formId": "", "reason": "excluded-gimmick", "messages": []}

	var before_name := Stats.display_name(mon)
	var old_max := maxi(int(mon.get("maxHp", 1)), 1)
	var fraction := clampf(float(int(mon.get("hp", 0))) / float(old_max), 0.0, 1.0)

	# The snapshot revert() restores. Deep enough that nothing aliases: `stats`
	# is a fresh Dictionary and `types` a fresh PackedStringArray.
	mon["megaBase"] = {
		"types": PackedStringArray(mon.get("types", PackedStringArray())),
		"stats": (mon.get("stats", {}) as Dictionary).duplicate(true),
		"maxHp": old_max,
		"ability": String(mon.get("ability", "")),
		"name": String(mon.get("name", "")),
	}

	# Recompute through the real stat formula (Stats.calc_all) from the FORM's
	# base stats, so IVs, EVs, nature and level all still apply. A Mega is a new
	# base-stat line, not a flat bonus.
	var base: Dictionary = target.get("stats", {})
	if not base.is_empty():
		mon["stats"] = Stats.calc_all(base,
			mon.get("ivs", [31, 31, 31, 31, 31, 31]),
			mon.get("evs", [0, 0, 0, 0, 0, 0]),
			int(mon.get("level", 1)),
			String(mon.get("nature", "hardy")))
		var new_max := maxi(int((mon["stats"] as Dictionary).get("hp", old_max)), 1)
		mon["maxHp"] = new_max
		# HP FRACTION, not HP value (DATA_CONTRACT 11.2). Floors at 1: Mega
		# Evolving must never be what faints you.
		mon["hp"] = clampi(int(round(fraction * float(new_max))), 1, new_max)

	if target.has("types"):
		mon["types"] = PackedStringArray(target.get("types", []))

	var abilities := abilities_of(target)
	mon["megaAbilities"] = abilities
	if abilities.is_empty():
		# DATA_CONTRACT 11.5: unresolved, so KEEP the base ability rather than
		# ship a hole, and flag it. Never guess one here.
		mon["megaAbilityStatus"] = PENDING_ABILITY
	else:
		mon["ability"] = abilities[0]
		var status := _opt(target, "abilityStatus")
		mon["megaAbilityStatus"] = status if not status.is_empty() else "ok"

	var form_name := _opt(target, "name")
	if not form_name.is_empty():
		mon["name"] = form_name
	mon["isMega"] = true
	mon["megaForm"] = _opt(target, "id")

	var messages: Array = []
	var trainer := String(opts.get("trainer", ""))
	if trainer.is_empty():
		messages.append("%s's Key Stone is reacting to the %s!" % [before_name, _stone_label(target)])
	else:
		messages.append("%s's Key Stone is reacting to the %s!" % [trainer, _stone_label(target)])
	messages.append("%s Mega Evolved into %s!" % [before_name, Stats.display_name(mon)])

	Deps.emit("mega_evolved", [mon, String(mon["megaForm"])])
	return {"ok": true, "formId": String(mon["megaForm"]), "reason": "", "messages": messages}


## Human-readable stone name for the flavour line. Mega Rayquaza has no stone, so
## the line names Dragon Ascent instead.
static func _stone_label(form: Dictionary) -> String:
	if is_stoneless(form):
		return _opt(form, "requiresMove").replace("-", " ").capitalize()
	return _stone_of(form).replace("-", " ").capitalize()


## Put `mon` back to its base form. Called when the battle ends and when the
## Pokemon faints (DATA_CONTRACT 11.2). Returns false when it was not a Mega.
##
## HP comes back as the same FRACTION on the base form's bar, except for a
## fainted Mega, which stays at 0 -- reverting must not revive anything.
static func revert(mon: Dictionary) -> bool:
	if not is_mega(mon):
		# Still scrub the bookkeeping keys: a half-set mon must not reach a save.
		for k: String in MON_KEYS:
			mon.erase(k)
		return false
	var snap: Dictionary = mon.get("megaBase", {})
	if snap.is_empty():
		for k: String in MON_KEYS:
			mon.erase(k)
		return false

	var mega_max := maxi(int(mon.get("maxHp", 1)), 1)
	var fraction := clampf(float(int(mon.get("hp", 0))) / float(mega_max), 0.0, 1.0)
	var fainted := Stats.is_fainted(mon)

	mon["types"] = PackedStringArray(snap.get("types", PackedStringArray()))
	mon["stats"] = (snap.get("stats", {}) as Dictionary).duplicate(true)
	var base_max := maxi(int(snap.get("maxHp", mega_max)), 1)
	mon["maxHp"] = base_max
	mon["ability"] = String(snap.get("ability", ""))
	mon["name"] = String(snap.get("name", mon.get("name", "")))
	mon["hp"] = 0 if fainted else clampi(int(round(fraction * float(base_max))), 1, base_max)

	var was := String(mon.get("megaForm", ""))
	for k: String in MON_KEYS:
		mon.erase(k)
	Deps.emit("mega_reverted", [mon, was])
	return true


## Revert every Mega in a party. Returns how many were reverted.
static func revert_party(party: Array) -> int:
	var n := 0
	for mon: Variant in party:
		if mon is Dictionary and revert(mon as Dictionary):
			n += 1
	return n
