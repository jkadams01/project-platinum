extends RefCounted
## Turns contract data into battle-ready Pokemon Dictionaries.
##
## `src/battle/stats.gd` owns the Dictionary *shape* ([method Stats.build]) but
## deliberately knows nothing about where a moveset comes from: it takes an
## explicit `moves` array of slugs. Something has to decide which four slugs, and
## that decision is different for each caller:
##
##   * a WILD Pokemon or a starter gets the last four moves it would have learnt
##     by level-up (DATA_CONTRACT 3 `levelUp`), newest first, exactly as the games
##     do when they generate one;
##   * a BOSS member gets the four hand-authored slugs in `data/rom/bosses.json`
##     (DATA_CONTRACT 7.1), never a learnset roll -- the rosters are designed.
##
## Keeping both here means `bosses.gd`, `boot.gd` and the battle scene never
## build a mon themselves, so there is exactly one place where "a Pokemon in this
## game" is defined.
##
## Nothing here is ROM-derived: species and learnsets come from veekun via the
## committed `data/*.json`.

const Stats := preload("res://src/battle/stats.gd")
const Deps := preload("res://src/battle/deps.gd")

## Moves a Pokemon of this species would know at this level: the four highest
## level-up entries at or below `level`, in learn order (so slot 0 is the oldest
## of the four, matching how the games lay a fresh party member out).
static func moves_at_level(species_id: int, level: int, max_moves: int = 4) -> PackedStringArray:
	var reg := Deps.registry()
	var learnset: Dictionary = {}
	if reg != null and reg.has_method("get_learnset"):
		learnset = reg.get_learnset(species_id)
	var pairs: Array = learnset.get("levelUp", [])

	var eligible: Array = []
	for pair: Variant in pairs:
		if pair is Array and (pair as Array).size() >= 2 and int((pair as Array)[0]) <= level:
			eligible.append([int((pair as Array)[0]), String((pair as Array)[1])])
	# Stable by level; `levelUp` is already in learn order, so a stable sort keeps
	# same-level moves in the order the data declares them.
	eligible.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))

	var out := PackedStringArray()
	var start := maxi(eligible.size() - max_moves, 0)
	for i in range(start, eligible.size()):
		var slug := String((eligible[i] as Array)[1])
		if not out.has(slug):
			out.append(slug)
	return out


## A wild Pokemon, or the player's starter. `opts` passes straight through to
## [method Stats.build], so a caller may pin nature/ivs/item/nickname.
##
## A species with no usable level-up data still comes back with a working mon --
## it falls back to `tackle`, then to whatever the species does know -- because a
## moveless Pokemon can only Struggle and that reads as an engine bug, not as a
## data gap.
static func wild(species_id: int, level: int, opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	if not o.has("moves"):
		var slugs := moves_at_level(species_id, level)
		if slugs.is_empty():
			slugs = PackedStringArray(["tackle"])
		o["moves"] = Array(slugs)
	var mon := Stats.build(species_id, level, o)
	if (mon.get("moves", []) as Array).is_empty():
		var fallback := Stats.make_move("tackle")
		if not fallback.is_empty():
			(mon["moves"] as Array).append(fallback)
		Log.warn("%s L%d had no resolvable moves; gave it Tackle" % [
			String(mon.get("name", species_id)), level], "PartyBuilder")
	return mon


## One `data/rom/bosses.json` party member (DATA_CONTRACT 7.1) as a battle mon.
##
## The authored `moves`, `item`, `ability` and `nature` are used verbatim -- these
## rosters are designed, and rolling a learnset over them would quietly undo the
## design. `megaEvolves` members keep their stone in `item`, which is what
## `battle_engine.can_mega_evolve()` reads.
static func from_boss_member(member: Dictionary) -> Dictionary:
	var opts: Dictionary = {
		"moves": (member.get("moves", []) as Array).duplicate(),
		"item": String(member.get("item", "")) if member.get("item", null) != null else "",
		"friendship": 70,
	}
	if member.get("ability", null) != null and not String(member["ability"]).is_empty():
		opts["ability"] = String(member["ability"])
	if member.get("nature", null) != null and not String(member["nature"]).is_empty():
		opts["nature"] = String(member["nature"])
	if member.get("speciesName", null) != null and not String(member["speciesName"]).is_empty():
		opts["name"] = String(member["speciesName"])

	var mon := wild(int(member.get("species", 0)), int(member.get("level", 5)), opts)
	# Trainer Pokemon are full EV-less but max-IV like the ROM rosters; nothing to
	# copy across beyond what `opts` already carried.
	return mon


## The player's starting party for the vertical slice. Turtwig, the Sinnoh grass
## starter, at the level the games hand it over at.
static func starter_party(species_id: int = 387, level: int = 5) -> Array:
	var mon := wild(species_id, level, {"nature": "jolly"})
	return [mon] if not mon.is_empty() else []
