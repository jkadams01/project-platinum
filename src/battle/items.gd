extends RefCounted
## Held items the battle engine acts on.
##
## WHY THIS EXISTS. Before it, a held item did exactly two things: `mega.gd`
## matched it against a Mega Stone, and `exp.gd` looked for `lucky-egg`. Everything
## else was inert -- including the items the DESIGNED FIGHTS already hand out. 23
## boss slots hold a Sitrus Berry, 22 hold Leftovers, 21 a Life Orb, 14 an Expert
## Belt, and 56 ordinary trainers hold a Sitrus Berry. Every one of those rosters
## was being played without the item it was authored with.
##
## SHAPE: ONE TABLE, NOT ONE FILE PER ITEM. `abilities/registry.gd` gives each
## ability its own script because abilities carry real logic across many hooks. An
## item is a number and a trigger, so the numbers live in the constants below and
## the dispatchers are flat matches. The prose -- name, description, and the `tier`
## that says whether the engine implements it -- lives in `data/items.json`, which
## `tools/build_items.py` owns.
##
## PURE WHERE IT HAS TO BE. [method damage_mods] never mutates and never consumes:
## `ai.gd` scores every legal move through `Damage.average()` on every turn, so a
## multiplier hook that ate a berry would have the AI eat the defender berries just
## by thinking about attacking. Consumption is a separate call the ENGINE makes,
## once, after a hit actually lands.
##
## CONSUMING IS PERMANENT, and that is correct: a berry eaten in battle is gone in
## the mainline games too. In the campaign these are the Dictionaries in
## `GameState.party`, so a Sitrus Berry eaten is a Sitrus Berry to re-buy.

const Stats := preload("res://src/battle/stats.gd")
const Deps := preload("res://src/battle/deps.gd")

const DATA_PATH := "res://data/items.json"

# --------------------------------------------------------------------------
# The mechanics table. Numbers live here; prose lives in data/items.json.
# --------------------------------------------------------------------------

## Item -> the move type it boosts, x1.2 (Gen 4 onward).
const TYPE_BOOST: Dictionary = {
	"black-belt": "fighting", "charcoal": "fire", "magnet": "electric",
	"mystic-water": "water", "sharp-beak": "flying", "silk-scarf": "normal",
}
const TYPE_BOOST_MULT := 1.2

## Item -> the stat it multiplies by 1.5 while locking the holder into one move.
const CHOICE: Dictionary = {
	"choice-band": "atk", "choice-specs": "spa", "choice-scarf": "spe",
}
const CHOICE_MULT := 1.5

## Item -> the move type whose super-effective hits it halves, then is eaten.
const RESIST_BERRY: Dictionary = {"shuca-berry": "ground"}
const RESIST_BERRY_MULT := 0.5

const LIFE_ORB_MULT := 1.3
const LIFE_ORB_RECOIL_DIV := 10
const EXPERT_BELT_MULT := 1.2
const BAND_MULT := 1.1
const ASSAULT_VEST_SPD_MULT := 1.5
const ROCKY_HELMET_DIV := 6
const LEFTOVERS_DIV := 16
const BLACK_SLUDGE_HEAL_DIV := 16
const BLACK_SLUDGE_HURT_DIV := 8
const SITRUS_DIV := 4
const ORAN_FLAT := 10

## Every id this file actually acts on. `data/items.json` marks these `tier: 1`
## and the builder UI reads that, so the two must not drift -- `tests/test_items.gd`
## checks them against each other.
const IMPLEMENTED: Array = [
	"leftovers", "black-sludge", "flame-orb", "life-orb", "expert-belt",
	"muscle-band", "wise-glasses", "choice-band", "choice-specs", "choice-scarf",
	"assault-vest", "rocky-helmet", "focus-sash", "sitrus-berry", "oran-berry",
	"shuca-berry", "black-belt", "charcoal", "magnet", "mystic-water",
	"sharp-beak", "silk-scarf", "lucky-egg",
	# Read by the ability layer rather than by this file: paradox.gd spends it and
	# the engine clears the slot. It belongs here because the builder asks THIS
	# list whether an item does anything.
	"booster-energy",
]

static var _rows: Dictionary = {}      # id -> the data/items.json row
static var _loaded: bool = false


# --------------------------------------------------------------------------
# The data half (names and descriptions for the UI)
# --------------------------------------------------------------------------

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	var rows: Array = []
	if parsed is Array:
		rows = parsed
	elif parsed is Dictionary:
		rows = (parsed as Dictionary).get("items", [])
	for row: Variant in rows:
		if row is Dictionary:
			_rows[String((row as Dictionary).get("id", ""))] = row


static func row(item_id: String) -> Dictionary:
	_ensure_loaded()
	return _rows.get(item_id, {})


static func display_name(item_id: String) -> String:
	var r := row(item_id)
	return String(r.get("name", item_id))


static func describe(item_id: String) -> String:
	var r := row(item_id)
	return String(r.get("description", ""))


## True when this file acts on the item. Distinct from "the row exists": a roster
## may hold something the engine does not read, and the UI has to be able to say so.
static func implemented(item_id: String) -> bool:
	return IMPLEMENTED.has(item_id)


## The BATTLE items, sorted: category `held-item` and nothing else.
##
## Not simply "everything holdable". The 40 evolution items are holdable too -- a
## Razor Claw is held while levelling -- but none of them does anything in a
## battle, and listing them would bury 24 real choices under 40 rows that all read
## "no effect". Mega Stones are excluded for the opposite reason: they matter, but
## only to one species, so `battle_spec.stone_choices()` offers them per holder.
static func holdable_ids() -> PackedStringArray:
	_ensure_loaded()
	var out := PackedStringArray()
	for id: String in _rows.keys():
		if String((_rows[id] as Dictionary).get("category", "")) == "held-item":
			out.append(id)
	out.sort()
	return out


# --------------------------------------------------------------------------
# Damage
# --------------------------------------------------------------------------

## The attacker and defender item multipliers, folded into one Dictionary the way
## `Abilities.damage_mods()` does, so `damage.gd` composes both without either
## knowing the other exists.
##
## NEVER MUTATES. See the header: the AI calls this many times a turn purely to
## score moves.
##
## `ctx`: category, move_type, effectiveness.
static func damage_mods(attacker: Dictionary, defender: Dictionary, move: Dictionary,
		ctx: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {
		"atk_mult": 1.0, "def_mult": 1.0, "power_mult": 1.0, "damage_mult": 1.0,
	}
	var category := String(ctx.get("category", move.get("category", "status")))
	if category == "status":
		return out
	var move_type := String(ctx.get("move_type", move.get("type", "normal")))
	var eff := float(ctx.get("effectiveness", 1.0))

	# --- attacker ---------------------------------------------------------
	var held := String(attacker.get("item", ""))
	if TYPE_BOOST.get(held, "") == move_type:
		out["power_mult"] = float(out["power_mult"]) * TYPE_BOOST_MULT
	if CHOICE.has(held) and String(CHOICE[held]) == ("atk" if category == "physical" else "spa"):
		out["atk_mult"] = float(out["atk_mult"]) * CHOICE_MULT
	if held == "life-orb":
		out["damage_mult"] = float(out["damage_mult"]) * LIFE_ORB_MULT
	if held == "expert-belt" and eff > 1.0:
		out["damage_mult"] = float(out["damage_mult"]) * EXPERT_BELT_MULT
	if held == "muscle-band" and category == "physical":
		out["damage_mult"] = float(out["damage_mult"]) * BAND_MULT
	if held == "wise-glasses" and category == "special":
		out["damage_mult"] = float(out["damage_mult"]) * BAND_MULT

	# --- defender ---------------------------------------------------------
	var worn := String(defender.get("item", ""))
	if worn == "assault-vest" and category == "special":
		out["def_mult"] = float(out["def_mult"]) * ASSAULT_VEST_SPD_MULT
	# The berry halves the hit here, and the ENGINE eats it afterwards through
	# [method consume_resist_berry]. Splitting the two is what keeps the AI from
	# eating a berry by considering a Ground move.
	if RESIST_BERRY.get(worn, "") == move_type and eff > 1.0:
		out["damage_mult"] = float(out["damage_mult"]) * RESIST_BERRY_MULT
	return out


## Speed, for `turn_order.effective_speed()`.
static func speed_mult(mon: Dictionary) -> float:
	return CHOICE_MULT if String(mon.get("item", "")) == "choice-scarf" else 1.0


# --------------------------------------------------------------------------
# Triggers the engine drives
# --------------------------------------------------------------------------

## Leftovers, Black Sludge and Flame Orb, at the end of the turn.
## Returns `{hp_delta:int, status:String, messages:Array[String]}`.
static func end_of_turn(mon: Dictionary) -> Dictionary:
	var out: Dictionary = {"hp_delta": 0, "status": "", "messages": []}
	if mon.is_empty() or Stats.is_fainted(mon):
		return out
	var held := String(mon.get("item", ""))
	var max_hp := int(mon.get("maxHp", 1))
	var name := Stats.display_name(mon)

	match held:
		"leftovers":
			if int(mon.get("hp", 0)) < max_hp:
				out["hp_delta"] = maxi(1, max_hp / LEFTOVERS_DIV)
				(out["messages"] as Array).append("%s restored a little HP using its Leftovers!" % name)
		"black-sludge":
			if PackedStringArray(mon.get("types", [])).has("poison"):
				if int(mon.get("hp", 0)) < max_hp:
					out["hp_delta"] = maxi(1, max_hp / BLACK_SLUDGE_HEAL_DIV)
					(out["messages"] as Array).append("%s restored a little HP using its Black Sludge!" % name)
			else:
				out["hp_delta"] = -maxi(1, max_hp / BLACK_SLUDGE_HURT_DIV)
				(out["messages"] as Array).append("%s is hurt by its Black Sludge!" % name)
		"flame-orb":
			if String(mon.get("status", "")).is_empty():
				out["status"] = "burn"
				(out["messages"] as Array).append("%s was burned by its Flame Orb!" % name)
	return out


## Rocky Helmet. `move` must be the move that landed; only contact is punished.
static func contact_punish(attacker: Dictionary, defender: Dictionary,
		move: Dictionary) -> Dictionary:
	var out: Dictionary = {"hp_delta": 0, "messages": []}
	if String(defender.get("item", "")) != "rocky-helmet":
		return out
	if not PackedStringArray(move.get("flags", [])).has("contact"):
		return out
	if attacker.is_empty() or Stats.is_fainted(attacker):
		return out
	out["hp_delta"] = -maxi(1, int(attacker.get("maxHp", 1)) / ROCKY_HELMET_DIV)
	(out["messages"] as Array).append("%s was hurt by the Rocky Helmet!"
		% Stats.display_name(attacker))
	return out


## Focus Sash, consulted BEFORE the damage is applied.
##
## Returns `{damage:int, survived:bool, messages:Array[String]}` -- `damage` is
## what should actually be dealt. The sash only works from FULL HP, and it is
## consumed when it works.
static func survive_fatal(mon: Dictionary, incoming: int) -> Dictionary:
	var out: Dictionary = {"damage": incoming, "survived": false, "messages": []}
	if String(mon.get("item", "")) != "focus-sash":
		return out
	var hp := int(mon.get("hp", 0))
	if hp < int(mon.get("maxHp", 1)) or incoming < hp:
		return out
	out["damage"] = maxi(hp - 1, 0)
	out["survived"] = true
	(out["messages"] as Array).append("%s hung on using its Focus Sash!" % Stats.display_name(mon))
	_consume(mon)
	return out


## Sitrus and Oran, checked after anything that lowered the holder HP.
## Returns `{hp_delta:int, messages:Array[String]}` and eats the berry.
static func low_hp_trigger(mon: Dictionary) -> Dictionary:
	var out: Dictionary = {"hp_delta": 0, "messages": []}
	if mon.is_empty() or Stats.is_fainted(mon):
		return out
	var held := String(mon.get("item", ""))
	var max_hp := int(mon.get("maxHp", 1))
	var hp := int(mon.get("hp", 0))
	if hp * 2 > max_hp:
		return out                      # not at half yet

	var heal := 0
	match held:
		"sitrus-berry":
			heal = maxi(1, max_hp / SITRUS_DIV)
		"oran-berry":
			heal = ORAN_FLAT
		_:
			return out
	if hp >= max_hp:
		return out
	out["hp_delta"] = heal
	(out["messages"] as Array).append("%s restored HP using its %s!" % [
		Stats.display_name(mon), display_name(held)])
	_consume(mon)
	return out


## Eat a type-resist berry that just softened a hit. The multiplier itself was
## applied in [method damage_mods]; this is the half that has a side effect, and
## the engine calls it exactly once, after the hit landed.
static func consume_resist_berry(defender: Dictionary, move_type: String,
		effectiveness: float) -> Dictionary:
	var out: Dictionary = {"messages": []}
	var worn := String(defender.get("item", ""))
	if RESIST_BERRY.get(worn, "") != move_type or effectiveness <= 1.0:
		return out
	(out["messages"] as Array).append("The %s weakened the damage to %s!" % [
		display_name(worn), Stats.display_name(defender)])
	_consume(defender)
	return out


## Life Orb recoil, charged once per move that dealt damage.
static func recoil(attacker: Dictionary, total_dealt: int) -> Dictionary:
	var out: Dictionary = {"hp_delta": 0, "messages": []}
	if total_dealt <= 0 or String(attacker.get("item", "")) != "life-orb":
		return out
	if Stats.is_fainted(attacker):
		return out
	out["hp_delta"] = -maxi(1, int(attacker.get("maxHp", 1)) / LIFE_ORB_RECOIL_DIV)
	(out["messages"] as Array).append("%s is hurt by its Life Orb!"
		% Stats.display_name(attacker))
	return out


# --------------------------------------------------------------------------
# Restrictions:  Choice lock and Assault Vest
# --------------------------------------------------------------------------

## The move slug a Choice item has locked the holder into, or "".
##
## The lock lives in `volatile`, which `_switch_in` already clears, so switching
## out frees the holder exactly as it does in the games. It is keyed on the SLUG
## rather than the index because a switch can reorder nothing but a Mega can
## change the mon underneath it.
static func choice_lock(mon: Dictionary) -> String:
	return String((mon.get("volatile", {}) as Dictionary).get("choiceLock", ""))


## Remember the move a Choice holder just committed to. A no-op for anything else,
## so the engine can call it after every move without a condition.
static func note_move_used(mon: Dictionary, slug: String) -> void:
	if not CHOICE.has(String(mon.get("item", ""))) or slug.is_empty():
		return
	if not mon.has("volatile"):
		mon["volatile"] = {}
	(mon["volatile"] as Dictionary)["choiceLock"] = slug


static func clear_choice_lock(mon: Dictionary) -> void:
	if mon.has("volatile"):
		(mon["volatile"] as Dictionary).erase("choiceLock")


## Why this move cannot be chosen right now, or "" when it can.
##
## The message is the point: a move menu that silently refuses is indistinguishable
## from a frozen game, which is the trap the PP check in `move_list.gd` already
## documents.
static func blocks_move(mon: Dictionary, move: Dictionary) -> String:
	if mon.is_empty() or move.is_empty():
		return ""
	var held := String(mon.get("item", ""))
	var name := Stats.display_name(mon)
	if held == "assault-vest" and String(move.get("category", "")) == "status":
		return "%s cannot use status moves while it holds an Assault Vest!" % name
	var locked := choice_lock(mon)
	if not locked.is_empty() and CHOICE.has(held) \
			and String(move.get("slug", "")) != locked:
		return "%s is locked into %s by its %s!" % [
			name, _pretty(locked), display_name(held)]
	return ""


## True when the holder may still use this move. The AI asks before scoring, so a
## Choice-locked opponent never picks a move it cannot use and then Struggles.
static func allows_move(mon: Dictionary, move: Dictionary) -> bool:
	return blocks_move(mon, move).is_empty()


# --------------------------------------------------------------------------
# Internals
# --------------------------------------------------------------------------

## Eat the held item. `usedItem` is recorded so a later Recycle -- or a test --
## can tell "never held one" from "ate one".
static func _consume(mon: Dictionary) -> void:
	mon["usedItem"] = String(mon.get("item", ""))
	mon["item"] = ""


static func _pretty(slug: String) -> String:
	var parts := PackedStringArray()
	for part in slug.split("-"):
		parts.append(part.capitalize())
	return String(" ").join(parts)
