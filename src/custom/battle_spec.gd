extends RefCounted
## The data model behind Custom Battle mode: an editable description of a fight,
## and the one place that turns it into an engine payload.
##
## A SPEC IS NOT A BATTLE. `src/battle/stats.gd` builds a live Pokemon and
## `src/systems/party_builder.gd` decides its moveset, but neither is editable --
## once built, a mon carries computed stats, resolved move Dictionaries and PP,
## and there is no way back to "Garchomp at Lv50 with these four slugs". So the
## builder edits SPECS (plain, JSON-safe, serialisable) and [method build_party]
## is the one-way door into battle mons. That is what makes a preset reloadable
## and a rematch exact.
##
## THE SHAPES
## [codeblock]
## slot = {species:int, level:int, nature:String, ability:String, item:String,
##         moves:Array[String]}         # <= 4 move slugs; [] = roll the learnset
## team = {name:String, keyStone:bool, ai:int, slots:Array[slot]}
## spec = {format:String, seed:int, awardExp:bool, watch:bool,
##         player:team, foe:team}
## [/codeblock]
##
## MOVES ARE LEGAL-ONLY, AND THE PICKER IS WHAT ENFORCES IT.
## [method legal_moves] is the whole pool a slot may be given by hand: the union of
## a species levelUp / machine / egg / tutor lists (DATA_CONTRACT 3), filtered to
## slugs that actually resolve in `data/moves.json`. That filter is not decoration.
## `Stats.make_move()` returns `{}` for an unknown slug and the move is then
## silently dropped from the mon, so a learnset entry with no move row would
## produce a three-move Pokemon with no error anywhere.
##
## TWO TIERS OF WRONG, AND THE DIFFERENCE MATTERS.
## [method validate] is BLOCKING and covers only what makes a battle unbuildable or
## a lie: an empty team, a species the data does not have, a level out of range, a
## move slug that would silently vanish, a format the engine cannot play.
## [method advisories] is ADVISORY and covers legality beyond that: a move the
## species cannot learn, an ability it cannot have, a Mega Stone that belongs to
## somebody else.
##
## The split exists because of the boss pre-fill. `data/rom/bosses.json` rosters are
## authored, and sanitising them on import is exactly the silent data loss CLAUDE.md
## warns about, while blocking the fight over an authored quirk would make the
## feature useless. So an imported roster is shown as it is, with a note, and it
## fights. A team edited by hand cannot get into that state: the pickers only ever
## offer legal choices.
##
## ITEMS: THE STONES FOR THIS SPECIES, THEN EVERYTHING THE ENGINE ACTS ON.
## `src/battle/items.gd` implements the held battle items -- Leftovers, Life Orb,
## the Choice trio, the berries, Focus Sash, Assault Vest, Rocky Helmet and the
## type boosters -- so [method item_choices] offers a species Mega Stones first and
## then every holdable item in `data/items.json`. A Mega Stone is offered only to
## the species it belongs to, because it is meaningless anywhere else; the rest are
## offered to everything, because they work on everything.
##
## An item the ENGINE does not read is still selectable and still kept when a
## roster brings one in, but it is marked. [method item_is_live] is what the slot
## editor asks to draw that mark.
##
## FORMAT IS SINGLES ONLY AND [method validate] SAYS SO OUT LOUD.
## `battle_engine.gd` keeps one active Pokemon per side (`sides[side]["active"]`
## is an int), so double / triple / rotation cannot be played yet. The field
## exists because the builder shows the choice, but a non-single spec is REFUSED
## rather than quietly played as a single -- a format that silently downgrades is
## worse than one that is greyed out.

const Stats := preload("res://src/battle/stats.gd")
const Mega := preload("res://src/battle/mega.gd")
const Deps := preload("res://src/battle/deps.gd")
const PartyBuilder := preload("res://src/systems/party_builder.gd")
const Items := preload("res://src/battle/items.gd")

const MAX_SLOTS := 6
const MAX_MOVES := 4
const MIN_LEVEL := 1
const MAX_LEVEL := 100
const DEFAULT_LEVEL := 50
const DEFAULT_AI := 7

## Formats the builder offers. Only `single` is playable; see the header.
const FORMATS: Array = ["single", "double", "triple", "rotation"]
const IMPLEMENTED_FORMATS: Array = ["single"]
## How many Pokemon a side sends out at once, once the engine can.
const FORMAT_ACTIVE: Dictionary = {"single": 1, "double": 2, "triple": 3, "rotation": 3}

const SPEC_VERSION := 1


# --------------------------------------------------------------------------
# Construction
# --------------------------------------------------------------------------

## An empty slot. `species == 0` means "nothing here"; the builder draws it as
## `--` and [method build_party] skips it.
static func new_slot(species: int = 0, level: int = DEFAULT_LEVEL) -> Dictionary:
	return {
		"species": maxi(species, 0),
		"level": clampi(level, MIN_LEVEL, MAX_LEVEL),
		"nature": "hardy",
		"ability": "",
		"item": "",
		"moves": [],
	}


static func new_team(team_name: String = "Team") -> Dictionary:
	var slots: Array = []
	for _i in MAX_SLOTS:
		slots.append(new_slot())
	return {"name": team_name, "keyStone": true, "ai": DEFAULT_AI, "slots": slots}


static func new_spec() -> Dictionary:
	return {
		"version": SPEC_VERSION,
		"format": "single",
		"seed": 0,
		"awardExp": false,
		"watch": false,
		"player": new_team("You"),
		"foe": new_team("Foe"),
	}


# --------------------------------------------------------------------------
# Choice pools  (what the pickers are allowed to offer)
# --------------------------------------------------------------------------

## Every move slug this species may legally be given, sorted. Empty for a species
## with no learnset data -- which the builder shows as "no legal moves" rather
## than as an empty list the player might read as a bug.
static func legal_moves(species_id: int) -> PackedStringArray:
	var reg := Deps.registry()
	if reg == null or species_id <= 0:
		return PackedStringArray()
	var learnset: Dictionary = reg.get_learnset(species_id)
	var seen: Dictionary = {}

	for pair: Variant in (learnset.get("levelUp", []) as Array):
		if pair is Array and (pair as Array).size() >= 2:
			seen[String((pair as Array)[1]).to_lower()] = true
	for key: String in ["machine", "egg", "tutor"]:
		for slug: Variant in (learnset.get(key, []) as Array):
			seen[String(slug).to_lower()] = true

	var out := PackedStringArray()
	for slug: String in seen.keys():
		# A learnset slug with no row in data/moves.json is dropped by
		# Stats.make_move() with no error at all, leaving a short moveset the
		# player never asked for. Never offer one.
		if not (reg.get_move_by_name(slug) as Dictionary).is_empty():
			out.append(slug)
	out.sort()
	return out


## The abilities this species may be given: its normal slots in order, then its
## hidden ability. Never empty for a real species -- `Stats.build` falls back to
## slot 0, so an empty pool means the data is missing, not that the species has
## no ability.
static func legal_abilities(species_id: int) -> PackedStringArray:
	var reg := Deps.registry()
	if reg == null or species_id <= 0:
		return PackedStringArray()
	var sp: Dictionary = reg.get_species(species_id)
	var out := PackedStringArray()
	for slug: Variant in (sp.get("abilities", []) as Array):
		var s := String(slug).to_lower()
		if not s.is_empty() and not out.has(s):
			out.append(s)
	if sp.get("hiddenAbility", null) != null:
		var hidden := String(sp["hiddenAbility"]).to_lower()
		if not hidden.is_empty() and not out.has(hidden):
			out.append(hidden)
	return out


## The Mega Stones this species can use, and nothing else. Kept separate from
## [method item_choices] because a stone is the one item whose legality depends on
## who is holding it.
##
## A stoneless form (Mega Rayquaza, gated on knowing Dragon Ascent instead) has no
## stone to offer, so it is skipped here and works through its move.
static func stone_choices(species_id: int) -> PackedStringArray:
	var out := PackedStringArray()
	for form: Variant in Mega.forms_for(species_id):
		if form is Dictionary and (form as Dictionary).get("stone", null) != null:
			var stone := String((form as Dictionary)["stone"]).to_lower()
			if not stone.is_empty() and not out.has(stone):
				out.append(stone)
	return out


## Everything this species may sensibly be given: its own Mega Stones first, then
## every holdable battle item. See the header.
static func item_choices(species_id: int) -> PackedStringArray:
	var out := stone_choices(species_id)
	for id: String in Items.holdable_ids():
		if not out.has(id):
			out.append(id)
	return out


## The moves a fresh slot starts with: what the species would know at that level,
## exactly as `PartyBuilder` gives a wild Pokemon.
static func default_moves(species_id: int, level: int) -> Array:
	return Array(PartyBuilder.moves_at_level(species_id, level))


# --------------------------------------------------------------------------
# Normalising and validating
# --------------------------------------------------------------------------

## Coerce a spec that came from anywhere (a JSON preset, an older version, a
## hand-edited file) into the canonical shape.
##
## THE INT CAST IS THE POINT. `JSON.parse_string` turns every number into
## TYPE_FLOAT, so a reloaded preset carries `species: 445.0` and `level: 50.0`.
## `Stats.build` int-casts its own level, but `species` travels into Dictionary
## keys and comparisons where 445.0 != 445, so a float species resolves to
## nothing at all. `tests/test_custom_battle.gd` asserts on this.
static func normalize(spec: Dictionary) -> Dictionary:
	var out := new_spec()
	out["version"] = int(spec.get("version", SPEC_VERSION))
	out["format"] = _one_of(String(spec.get("format", "single")).to_lower(), FORMATS, "single")
	out["seed"] = int(spec.get("seed", 0))
	out["awardExp"] = bool(spec.get("awardExp", false))
	out["watch"] = bool(spec.get("watch", false))
	out["player"] = normalize_team(spec.get("player", {}), "You")
	out["foe"] = normalize_team(spec.get("foe", {}), "Foe")
	return out


static func normalize_team(team: Variant, fallback_name: String) -> Dictionary:
	var src: Dictionary = team if team is Dictionary else {}
	var out := new_team(String(src.get("name", fallback_name)))
	out["keyStone"] = bool(src.get("keyStone", true))
	out["ai"] = clampi(int(src.get("ai", DEFAULT_AI)), 0, 10)
	var slots: Array = []
	for row: Variant in (src.get("slots", []) as Array):
		if slots.size() >= MAX_SLOTS:
			break
		slots.append(normalize_slot(row))
	while slots.size() < MAX_SLOTS:
		slots.append(new_slot())
	out["slots"] = slots
	return out


static func normalize_slot(slot: Variant) -> Dictionary:
	var src: Dictionary = slot if slot is Dictionary else {}
	var out := new_slot(int(src.get("species", 0)), int(src.get("level", DEFAULT_LEVEL)))
	out["nature"] = _one_of(String(src.get("nature", "hardy")).to_lower(),
		Array(Stats.nature_names()), "hardy")
	out["ability"] = String(src.get("ability", "")).to_lower()
	out["item"] = String(src.get("item", "")).to_lower()
	var moves: Array = []
	for slug: Variant in (src.get("moves", []) as Array):
		var s := String(slug).to_lower()
		if moves.size() < MAX_MOVES and not s.is_empty() and not moves.has(s):
			moves.append(s)
	out["moves"] = moves
	return out


## The BLOCKING problems, in plain language; empty when the spec is playable. The
## builder shows the first line and refuses to start. See the header for what
## belongs here and what belongs in [method advisories].
static func validate(spec: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var format := String(spec.get("format", "single"))
	if not IMPLEMENTED_FORMATS.has(format):
		out.append("%s battles are not implemented yet -- the engine plays singles only."
			% format.capitalize())
	for side: String in ["player", "foe"]:
		var team: Dictionary = spec.get(side, {})
		var label := "Your team" if side == "player" else "The foe's team"
		if filled_slots(team).is_empty():
			out.append("%s has no Pokemon." % label)
		for i in (team.get("slots", []) as Array).size():
			for problem: String in validate_slot((team["slots"] as Array)[i]):
				out.append("%s slot %d: %s" % [label, i + 1, problem])
	return out


static func validate_slot(slot: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var species := int(slot.get("species", 0))
	if species <= 0:
		return out                      # an empty slot is legal; it is skipped
	var reg := Deps.registry()
	if reg != null and not bool(reg.has_species(species)):
		out.append("species %d is not in the data" % species)
		return out                      # nothing below this can be checked
	var level := int(slot.get("level", 0))
	if level < MIN_LEVEL or level > MAX_LEVEL:
		out.append("level %d is outside 1-100" % level)
	if not Stats.NATURES.has(String(slot.get("nature", ""))):
		out.append("'%s' is not a nature" % String(slot.get("nature", "")))

	var moves: Array = slot.get("moves", [])
	if moves.size() > MAX_MOVES:
		out.append("%d moves (max %d)" % [moves.size(), MAX_MOVES])
	# An unresolvable slug IS blocking: Stats.make_move() drops it and the mon comes
	# out with fewer moves than the spec asked for, silently.
	for slug: Variant in moves:
		if reg != null and (reg.get_move_by_name(String(slug)) as Dictionary).is_empty():
			out.append("there is no move '%s' in the data" % String(slug))
	return out


## Legality notes that do NOT stop the battle: a move outside the learnset, an
## ability the species cannot have, somebody else Mega Stone. The builder shows
## these and still starts the fight -- see the header for why.
static func advisories(spec: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for side: String in ["player", "foe"]:
		var team: Dictionary = spec.get(side, {})
		var label := "You" if side == "player" else "Foe"
		for i in (team.get("slots", []) as Array).size():
			for note: String in advise_slot((team["slots"] as Array)[i]):
				out.append("%s %d: %s" % [label, i + 1, note])
	return out


static func advise_slot(slot: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var species := int(slot.get("species", 0))
	if species <= 0:
		return out
	var reg := Deps.registry()
	if reg != null and not bool(reg.has_species(species)):
		return out                      # validate() already blocks on this

	var ability := String(slot.get("ability", ""))
	if not ability.is_empty() and not legal_abilities(species).has(ability):
		out.append("%s cannot have %s" % [_species_name(species), pretty(ability)])

	# A Mega Stone belonging to somebody else is the one item worth complaining
	# about: it looks like it will do something and never will. A plain unknown item
	# is reported the same way, while an item the engine simply has not implemented
	# is left to the slot editor inert marker rather than nagged about here.
	var item := String(slot.get("item", ""))
	if not item.is_empty() and not item_choices(species).has(item):
		out.append("%s does nothing for %s" % [pretty(item), _species_name(species)])

	var pool := legal_moves(species)
	for slug: Variant in (slot.get("moves", []) as Array):
		if not pool.has(String(slug)):
			out.append("%s cannot learn %s" % [_species_name(species), pretty(String(slug))])
	return out


## True when this slot holds an item the engine will actually act on: a Mega Stone
## this species can use, or an implemented battle item. The slot editor marks
## anything else inert, which is how a roster item nothing reads stays visible
## instead of looking like it works.
static func item_is_live(slot: Dictionary) -> bool:
	var item := String(slot.get("item", ""))
	if item.is_empty():
		return false
	if stone_choices(int(slot.get("species", 0))).has(item):
		return true
	return Items.implemented(item)


## "rock-slide" -> "Rock Slide". A copy of `ui_kit.pretty()` on purpose: this file
## is data and must not preload a UI script to format a sentence.
static func pretty(slug: String) -> String:
	if slug.is_empty():
		return ""
	var parts := PackedStringArray()
	for part in slug.split("-"):
		parts.append(part.capitalize())
	return String(" ").join(parts)


# --------------------------------------------------------------------------
# Building the fight
# --------------------------------------------------------------------------

## The slots of a team that actually hold a Pokemon, in order.
static func filled_slots(team: Dictionary) -> Array:
	var out: Array = []
	for row: Variant in (team.get("slots", []) as Array):
		if row is Dictionary and int((row as Dictionary).get("species", 0)) > 0:
			out.append(row)
	return out


## One slot as a battle-ready mon. An empty `moves` list is handed to
## `PartyBuilder.wild`, which rolls the learnset -- so a slot the player filled
## but never opened fights with a sensible moveset instead of Struggling.
static func build_mon(slot: Dictionary) -> Dictionary:
	var species := int(slot.get("species", 0))
	if species <= 0:
		return {}
	var opts: Dictionary = {
		"nature": String(slot.get("nature", "hardy")),
		"item": String(slot.get("item", "")),
	}
	var ability := String(slot.get("ability", ""))
	if not ability.is_empty():
		opts["ability"] = ability
	var moves: Array = (slot.get("moves", []) as Array).duplicate()
	if not moves.is_empty():
		opts["moves"] = moves
	return PartyBuilder.wild(species, int(slot.get("level", DEFAULT_LEVEL)), opts)


static func build_party(team: Dictionary) -> Array:
	var out: Array = []
	for slot: Dictionary in filled_slots(team):
		var mon := build_mon(slot)
		if not mon.is_empty():
			out.append(mon)
	return out


## The `EventBus.battle_started` payload for this spec, or `{}` when it does not
## validate (the caller shows [method validate]'s lines instead).
##
## `kind` is always `trainer`: a custom battle has a named opponent, the AI reads
## `trainer.ai`, and `trainer.keyStone` is what lets the foe Mega Evolve. It is
## never `wild` -- `battle_engine._has_key_stone()` returns false for a wild side
## by design, so a wild custom battle could never test a Mega.
##
## `prizeMoney` is deliberately absent. The engine pays a trainer prize straight
## into `GameState.add_money()`, and a practice fight must not touch the campaign
## wallet.
static func to_setup(spec: Dictionary, seed_override: int = 0) -> Dictionary:
	if not validate(spec).is_empty():
		return {}
	var player: Dictionary = spec.get("player", {})
	var foe: Dictionary = spec.get("foe", {})
	var seed_value := seed_override if seed_override != 0 else int(spec.get("seed", 0))
	if seed_value == 0:
		seed_value = randi()
	return {
		"kind": "trainer",
		"party": build_party(player),
		"opponent": build_party(foe),
		"trainer": {
			"name": String(foe.get("name", "Foe")),
			"class": "custom",
			"ai": clampi(int(foe.get("ai", DEFAULT_AI)), 0, 10),
			"keyStone": bool(foe.get("keyStone", true)),
		},
		# DATA_CONTRACT 11.2: the player's Key Stone for this fight only, so Mega
		# Evolution is testable from a fresh boot without granting the save one.
		"playerKeyStone": bool(player.get("keyStone", true)),
		# DATA_CONTRACT 8: no EXP by default. A mon that levels up mid-fight is not
		# the mon the builder described, which makes a rematch not a rematch.
		"awardExp": bool(spec.get("awardExp", false)),
		"autoPlayer": bool(spec.get("watch", false)),
		# 100 rather than the campaign cap: the builder set these levels on
		# purpose and nothing here is progression.
		"cap": MAX_LEVEL,
		"seed": seed_value,
		"playerName": String(player.get("name", "You")),
		"custom": true,
	}


# --------------------------------------------------------------------------
# Pre-fill
# --------------------------------------------------------------------------

## A boss's authored roster (DATA_CONTRACT 7.1) as an editable team spec.
## `bosses` is `src/systems/bosses.gd` -- passed in rather than preloaded so a
## test can hand over a stand-in table.
##
## The rows are read straight out of the table rather than through
## `Bosses.build_party()`, because that returns built mons and a spec needs the
## authored slugs back. A `dynamicSlot` member (Barry's starter, normally resolved
## against the player's choice) keeps its placeholder species here: there is no
## campaign starter choice in a custom battle, and a visible placeholder the owner
## can edit beats a silent guess.
static func from_boss(key: String, bosses: Object) -> Dictionary:
	if bosses == null or not bool(bosses.has(key)):
		return {}
	var boss: Dictionary = bosses.get_boss(key)
	var team := new_team(String(boss.get("name", key.capitalize())))
	team["ai"] = clampi(int(boss.get("ai", DEFAULT_AI)), 0, 10)
	# Mirrors Bosses.trainer_block(): only a boss with an authored Mega gets the
	# Key Stone, so a pre-filled roster Megas exactly when the real fight does.
	team["keyStone"] = boss.get("megaForm", null) != null

	var slots: Array = []
	for member: Variant in (boss.get("party", []) as Array):
		if not (member is Dictionary) or slots.size() >= MAX_SLOTS:
			continue
		slots.append(_slot_from_member(member as Dictionary))
	while slots.size() < MAX_SLOTS:
		slots.append(new_slot())
	team["slots"] = slots
	return team


static func _slot_from_member(member: Dictionary) -> Dictionary:
	var slot := new_slot(int(member.get("species", 0)), int(member.get("level", DEFAULT_LEVEL)))
	if member.get("nature", null) != null and not String(member["nature"]).is_empty():
		slot["nature"] = _one_of(String(member["nature"]).to_lower(),
			Array(Stats.nature_names()), "hardy")
	if member.get("ability", null) != null:
		slot["ability"] = String(member["ability"]).to_lower()
	if member.get("item", null) != null:
		slot["item"] = String(member["item"]).to_lower()
	var moves: Array = []
	for slug: Variant in (member.get("moves", []) as Array):
		var s := String(slug).to_lower()
		if moves.size() < MAX_MOVES and not s.is_empty() and not moves.has(s):
			moves.append(s)
	slot["moves"] = moves
	return slot


## A team of `count` random species at `level`, each with its level-up moveset.
## Only species the registry actually knows are drawn, so a partial data build
## produces a smaller team rather than slots that fail to build.
static func random_team(rng: RandomNumberGenerator, count: int = MAX_SLOTS,
		level: int = DEFAULT_LEVEL) -> Dictionary:
	var reg := Deps.registry()
	var team := new_team("Random")
	if reg == null:
		return team
	var ids: PackedInt32Array = reg.species_ids()
	if ids.is_empty():
		return team
	var slots: Array = []
	var used: Dictionary = {}
	var guard := 0
	while slots.size() < mini(count, MAX_SLOTS) and guard < 500:
		guard += 1
		var id := int(ids[rng.randi_range(0, ids.size() - 1)])
		if used.has(id):
			continue
		used[id] = true
		var slot := new_slot(id, level)
		slot["moves"] = default_moves(id, level)
		slots.append(slot)
	while slots.size() < MAX_SLOTS:
		slots.append(new_slot())
	team["slots"] = slots
	return team


## The live campaign party as a team spec, so a real save can be thrown at a boss
## roster. Levels, natures, abilities, items and the four CURRENT moves are
## copied; PP and damage are not -- a custom battle always starts fresh.
static func from_party(party: Array, team_name: String = "You") -> Dictionary:
	var team := new_team(team_name)
	var slots: Array = []
	for mon: Variant in party:
		if not (mon is Dictionary) or slots.size() >= MAX_SLOTS:
			continue
		var m: Dictionary = mon
		var slot := new_slot(int(m.get("species", 0)), int(m.get("level", DEFAULT_LEVEL)))
		slot["nature"] = String(m.get("nature", "hardy")).to_lower()
		slot["ability"] = String(m.get("ability", "")).to_lower()
		slot["item"] = String(m.get("item", "")).to_lower()
		var moves: Array = []
		for move: Variant in (m.get("moves", []) as Array):
			if not (move is Dictionary) or moves.size() >= MAX_MOVES:
				continue
			# `slug` is what Stats.make_move() stored; fall back to the display
			# name only because a mon restored from an older save may predate it.
			var slug := String((move as Dictionary).get("slug", ""))
			if slug.is_empty():
				slug = String((move as Dictionary).get("name", "")).to_lower().replace(" ", "-")
			if not slug.is_empty() and not moves.has(slug):
				moves.append(slug)
		slot["moves"] = moves
		slots.append(slot)
	while slots.size() < MAX_SLOTS:
		slots.append(new_slot())
	team["slots"] = slots
	return team


# --------------------------------------------------------------------------
# Presets  (user://, never the repo)
# --------------------------------------------------------------------------

const PRESET_DIR := "user://custom_battles"
const PRESET_EXT := ".json"


## Preset names (no directory, no extension), sorted.
static func list_presets() -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(PRESET_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(PRESET_EXT):
			out.append(f.substr(0, f.length() - PRESET_EXT.length()))
	out.sort()
	return out


## Strip a typed name down to something safe to put in a path. Returns "" when
## nothing usable is left, which the caller must treat as "do not save".
static func sanitize_name(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "-"
	while out.contains("--"):
		out = out.replace("--", "-")
	out = out.lstrip("-").rstrip("-")
	return out.substr(0, 32)


## Write `spec` to `user://custom_battles/<name>.json`. Returns the sanitised name
## it was stored under, or "" on refusal or a write failure.
static func save_preset(spec: Dictionary, raw_name: String) -> String:
	var safe := sanitize_name(raw_name)
	if safe.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(PRESET_DIR)
	var path := "%s/%s%s" % [PRESET_DIR, safe, PRESET_EXT]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		Log.error("could not write preset %s (error %d)" % [path, FileAccess.get_open_error()],
			"CustomBattle")
		return ""
	var payload := normalize(spec)
	payload["name"] = safe
	f.store_string(JSON.stringify(payload, "  "))
	f.close()
	return safe


## Load a preset by name. Returns `{}` when it is missing or not valid JSON, and
## normalises what it does read, so a preset from an older build still opens.
static func load_preset(preset_name: String) -> Dictionary:
	var path := "%s/%s%s" % [PRESET_DIR, sanitize_name(preset_name), PRESET_EXT]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		Log.error("preset %s is not a JSON object" % path, "CustomBattle")
		return {}
	return normalize(parsed as Dictionary)


static func delete_preset(preset_name: String) -> bool:
	var safe := sanitize_name(preset_name)
	if safe.is_empty():
		return false
	var d := DirAccess.open(PRESET_DIR)
	if d == null:
		return false
	return d.remove(safe + PRESET_EXT) == OK


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

static func _one_of(value: String, allowed: Array, fallback: String) -> String:
	return value if allowed.has(value) else fallback


static func species_name(species_id: int) -> String:
	return _species_name(species_id)


static func _species_name(species_id: int) -> String:
	var reg := Deps.registry()
	if reg == null:
		return "#%d" % species_id
	return String((reg.get_species(species_id) as Dictionary).get("name", "#%d" % species_id))


## "Lv50 Garchomp" -- the one-line label the builder draws for a filled slot.
static func slot_label(slot: Dictionary) -> String:
	var species := int(slot.get("species", 0))
	if species <= 0:
		return "--"
	return "Lv%d %s" % [int(slot.get("level", DEFAULT_LEVEL)), _species_name(species)]
