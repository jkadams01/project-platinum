extends Node
## The entire mutable world: party, badges, money, playtime, flags, level cap.
## Nothing else lives here, and nothing here knows about scenes or nodes.
##
## BADGES ARE BITFLAGS. `badges` is a single int; bit N is BADGE_ORDER[N].
## Eight badges fit in a byte, saving and comparing is trivial, and
## `badge_count()` is a popcount rather than an array scan.
##
## THE LEVEL CAP LADDER. `cap_index` points at a row of data/level_caps.json.
## Each row's `raisedBy` names the event that CLEARS that row, so clearing it
## advances you to the row AFTER it:
##   index 0 "start"  cap 14   (game start: the next checkpoint is Roark, ace 14)
##   index 1 "roark"  cap 14   raisedBy badge:coal
##   index 2 "gardenia" cap 22 raisedBy badge:forest
## Earning the Coal Badge matches row 1, so `cap_index` becomes 2 and the active
## cap becomes 22 -- "the cap equals the next checkpoint boss's ace level"
## (docs/research/game-design.md 2.5). See [method raise_cap_for].
##
## A party member is a plain Dictionary, not a custom class, so that this file
## has no dependency on the battle stream and so that saving is a pure JSON
## round-trip. Documented shape (the battle stream owns the extra keys):
##   {"species": int, "level": int, "exp": int, "hp": int, "maxHp": int,
##    "moves": Array[String], "ivs": Array[int], "evs": Array[int],
##    "nature": String, "ability": int, "item": String, "nickname": String,
##    "status": String, "friendship": int}

const SAVE_VERSION := 1

## Bit order for the `badges` bitfield. Sinnoh gym order.
const BADGE_ORDER: Array = [
	"coal", "forest", "relic", "cobble", "fen", "mine", "icicle", "beacon",
]

const MAX_PARTY := 6
const STARTING_MONEY := 3000

# --- persisted state ------------------------------------------------------

var party: Array = []                       # Array[Dictionary]
var badges: int = 0                         # bitflags, see BADGE_ORDER
var money: int = STARTING_MONEY
var playtime: float = 0.0                   # seconds
var flags: Dictionary = {}                  # String -> bool
var bag: Dictionary = {}                    # String item id -> int count
var cap_index: int = 0                      # row in data/level_caps.json
var player_name: String = "Lucas"
## The starter the player chose, as a `starterLines` key in data/rom/bosses.json
## ("turtwig" | "chimchar" | "piplup"). Empty until the choice is made.
##
## This file does not know what the values mean -- `Bosses` owns that. It only has
## to remember the choice and round-trip it, because Barry's starter is derived
## from it in EVERY one of his seven fights: a choice lost on load would silently
## re-roll his party, mid-playthrough, with no error anywhere.
var starter_choice: String = ""
var current_map: StringName = &"twinleaf_town"
var player_cell: Vector2i = Vector2i.ZERO
var player_facing: Vector2i = Vector2i.DOWN
var rng_seed: int = 0

# --- runtime-only (never saved) ------------------------------------------

## Set while a cutscene, dialogue or transition owns the input.
var input_locked: bool = false
## Set false in tests so playtime does not drift with frame count.
var track_playtime: bool = true


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	if track_playtime:
		playtime += delta


## Back to a fresh game. Does not touch save files.
func reset() -> void:
	party.clear()
	badges = 0
	money = STARTING_MONEY
	playtime = 0.0
	flags.clear()
	bag.clear()
	cap_index = 0
	player_name = "Lucas"
	starter_choice = ""
	current_map = &"twinleaf_town"
	player_cell = Vector2i.ZERO
	player_facing = Vector2i.DOWN
	rng_seed = 0
	input_locked = false


# --------------------------------------------------------------------------
# The starter
# --------------------------------------------------------------------------

## Records the player's starter. Normalised to lower case and trimmed because the
## value is used directly as a Dictionary key in `bosses.json`'s `starterLines`
## and `starterCounter`; a stray "Turtwig" would resolve to nothing and quietly
## leave Barry on his placeholder.
##
## Deliberately not validated here -- the set of legal starters lives in the boss
## table, and `GameState` must not depend on it. `Bosses.resolve_rival_starter()`
## returns 0 for a value it does not recognise, which is where that is caught.
func set_starter_choice(slug: String) -> void:
	var was := starter_choice
	starter_choice = slug.strip_edges().to_lower()
	if starter_choice != was:
		Log.info("starter choice: '%s'" % starter_choice, "GameState")


# --------------------------------------------------------------------------
# Badges
# --------------------------------------------------------------------------

## Bit index of a badge name, or -1 if it is not a real badge.
static func badge_bit(badge: String) -> int:
	return BADGE_ORDER.find(badge.to_lower())


func has_badge(b: String) -> bool:
	var bit := badge_bit(b)
	if bit < 0:
		return false
	return (badges & (1 << bit)) != 0


## Grants a badge. Returns false if it was already held or the name is unknown.
## Emits `badge_earned` and, when the badge clears a cap row, `level_cap_raised`.
func earn_badge(b: String) -> bool:
	var bit := badge_bit(b)
	if bit < 0:
		Log.error("unknown badge '%s'" % b, "GameState")
		return false
	if (badges & (1 << bit)) != 0:
		return false
	badges |= 1 << bit
	Log.info("earned the %s badge (%d total)" % [b, badge_count()], "GameState")
	EventBus.badge_earned.emit(StringName(b.to_lower()))
	raise_cap_for("badge:" + b.to_lower())
	return true


func badge_count() -> int:
	var n := 0
	var v := badges
	while v != 0:
		n += v & 1
		v >>= 1
	return n


## Badge names held, in gym order.
func badge_names() -> PackedStringArray:
	var out := PackedStringArray()
	for i in BADGE_ORDER.size():
		if (badges & (1 << i)) != 0:
			out.append(BADGE_ORDER[i])
	return out


## True when the traversal verb is unlocked. Mapping from DATA_CONTRACT.md.
## `fly` needs Cobble, `surf` needs Fen, and so on. There is no `defog`.
func can_traverse(verb: String) -> bool:
	match verb.to_lower():
		"smash": return has_badge("coal")
		"cut": return has_badge("forest")
		"fly": return has_badge("cobble")
		"surf": return has_badge("fen")
		"strength": return has_badge("mine")
		"climb": return has_badge("icicle")
		"waterfall": return has_badge("beacon")
	Log.warn("unknown traversal verb '%s'" % verb, "GameState")
	return false


## Convenience for the overworld stream: checks the gate and announces the verb.
func use_traversal(verb: String) -> bool:
	if not can_traverse(verb):
		return false
	EventBus.traversal_used.emit(StringName(verb.to_lower()))
	return true


# --------------------------------------------------------------------------
# Mega Evolution (DATA_CONTRACT 11.2)
# --------------------------------------------------------------------------

## The Key Stone lives in the bag like any other item, so it saves and loads for
## free -- there is no separate persisted flag to keep in sync.
const KEY_STONE_ITEM := "key-stone"

## The story checkpoint that grants the Key Stone (DATA_CONTRACT 11.2,
## docs/research/mega-design.md 1). Cynthia hands it over in Hearthome after the
## Relic Badge: the first gym at which the level-cap type-discipline guard is no
## longer also doing balance work, with 10 capped boss fights still to come. A
## var, not a const, so a test or a debug menu can move it without a rebuild.
var mega_unlocked_at: String = "badge:relic"


## Gates the Mega button appearing at all (DATA_CONTRACT 11.2).
func has_key_stone() -> bool:
	return int(bag.get(KEY_STONE_ITEM, 0)) > 0


## True once the story has reached [member mega_unlocked_at]. Understands
## "badge:<name>" and "flag:<name>"; anything else is never unlocked, which fails
## closed rather than handing out a Mega early.
func mega_unlocked() -> bool:
	if mega_unlocked_at.begins_with("badge:"):
		return has_badge(mega_unlocked_at.substr(6))
	if mega_unlocked_at.begins_with("flag:"):
		return get_flag(mega_unlocked_at.substr(5))
	return false


## Hand over the Key Stone. Returns false when it is already held. Does NOT check
## [method mega_unlocked]: the gift event is what enforces the gate, and a debug
## menu is allowed to skip it.
func grant_key_stone() -> bool:
	if has_key_stone():
		return false
	bag[KEY_STONE_ITEM] = 1
	Log.info("granted the Key Stone", "GameState")
	return true


# --------------------------------------------------------------------------
# Level cap
# --------------------------------------------------------------------------

func current_level_cap() -> int:
	return DataRegistry.get_level_cap(cap_index)


## The EXP multiplier of the segment currently in force -- DATA_CONTRACT 8.
##
## PER-SEGMENT, NEVER GLOBAL. Each row of `data/level_caps.json` carries its own
## `expMultiplier` and this returns the active row's. The top-level
## `expMultiplier` in that file is permanently null and must never be read: caps
## are hard, so surplus EXP inside a segment is discarded instead of carried
## forward, and each segment has to supply its own cap's worth on its own. The
## early segments already over-supply at 1.0x while the League runs a 0.4
## shortfall, so one flat number cannot serve both ends of the game.
##
## `src/battle/exp.gd` applies this to every award *before* the cap check, so the
## multiplier can never lift a Pokemon that is already at the cap off zero.
func current_exp_multiplier() -> float:
	return DataRegistry.get_exp_multiplier(cap_index)


## Advance past the cap row cleared by [param event] ("badge:coal",
## "flag:hall_of_fame"). Returns true if the active cap index moved.
func raise_cap_for(event: String) -> bool:
	var row := DataRegistry.find_cap_index_for(event)
	if row < 0:
		Log.debug("no cap row is raised by '%s'" % event, "GameState")
		return false
	return set_cap_index(row + 1)


## Move the cap pointer directly. Never moves backwards. Emits `level_cap_raised`.
func set_cap_index(index: int) -> bool:
	var target := clampi(index, 0, maxi(DataRegistry.level_cap_count() - 1, 0))
	if target <= cap_index:
		return false
	var old_cap := current_level_cap()
	cap_index = target
	var new_cap := current_level_cap()
	Log.info("level cap %d -> %d (row %d)" % [old_cap, new_cap, cap_index], "GameState")
	EventBus.level_cap_raised.emit(old_cap, new_cap, cap_index)
	return true


## The hard cap rule: at or above the cap, zero exp (and zero EVs).
func can_gain_exp(level: int) -> bool:
	return level < current_level_cap()


## Award exp to a party-member Dictionary, honouring the hard cap. Returns the
## amount actually granted -- 0 when capped, in which case `exp_capped` fires.
## The caller owns levelling up; this is only the cap gate plus the exp field.
##
## `amount` is taken as already-multiplied. The per-segment multiplier belongs to
## `src/battle/exp.gd` (DATA_CONTRACT 8) and applying it here as well would scale
## every battle award twice -- see [method current_exp_multiplier].
func award_exp(pokemon: Dictionary, amount: int) -> int:
	var level := int(pokemon.get("level", 1))
	if not can_gain_exp(level):
		EventBus.exp_capped.emit(pokemon, current_level_cap())
		return 0
	var granted := maxi(amount, 0)
	pokemon["exp"] = int(pokemon.get("exp", 0)) + granted
	return granted


# --------------------------------------------------------------------------
# Flags, money, party
# --------------------------------------------------------------------------

func set_flag(flag: String, value: bool = true) -> void:
	if bool(flags.get(flag, false)) == value:
		return
	flags[flag] = value
	EventBus.flag_set.emit(StringName(flag), value)
	# Some cap rows are cleared by a story flag rather than a badge.
	if value:
		raise_cap_for("flag:" + flag)


func get_flag(flag: String, default_value: bool = false) -> bool:
	return bool(flags.get(flag, default_value))


func add_money(amount: int) -> void:
	money = clampi(money + amount, 0, 999999)


## Returns false and changes nothing when the player cannot afford it.
func spend_money(amount: int) -> bool:
	if amount < 0 or money < amount:
		return false
	money -= amount
	return true


func add_to_party(pokemon: Dictionary) -> bool:
	if party.size() >= MAX_PARTY:
		return false
	party.append(pokemon)
	EventBus.party_changed.emit()
	return true


func party_size() -> int:
	return party.size()


## Playtime as H:MM:SS, for the save-slot UI.
func playtime_string() -> String:
	var total := int(playtime)
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


# --------------------------------------------------------------------------
# Serialisation
# --------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"v": SAVE_VERSION,
		"playerName": player_name,
		"starterChoice": starter_choice,
		"party": party.duplicate(true),
		"badges": badges,
		"money": money,
		"playtime": playtime,
		"flags": flags.duplicate(true),
		"bag": bag.duplicate(true),
		"capIndex": cap_index,
		"map": String(current_map),
		"cell": [player_cell.x, player_cell.y],
		"facing": [player_facing.x, player_facing.y],
		"rngSeed": rng_seed,
	}


## Applies a saved dictionary. Every numeric field is re-cast with int(): JSON
## returns TYPE_FLOAT for every number (verified on 4.7.2), and a float level or
## species id would corrupt dictionary lookups downstream. Returns false when the
## payload is not a version this build understands.
func from_dict(d: Dictionary) -> bool:
	var v := int(d.get("v", 0))
	if v != SAVE_VERSION:
		Log.error("save version %d, expected %d" % [v, SAVE_VERSION], "GameState")
		return false

	player_name = String(d.get("playerName", "Lucas"))
	# Normalised on the way in as well as the way out: a save hand-edited to
	# "Piplup" must still resolve Barry's starter.
	starter_choice = String(d.get("starterChoice", "")).strip_edges().to_lower()

	party.clear()
	for entry: Variant in (d.get("party", []) as Array):
		if entry is Dictionary:
			party.append(_restore_pokemon(entry))

	badges = int(d.get("badges", 0))
	money = int(d.get("money", STARTING_MONEY))
	playtime = float(d.get("playtime", 0.0))

	flags.clear()
	for k: Variant in (d.get("flags", {}) as Dictionary):
		flags[String(k)] = bool((d["flags"] as Dictionary)[k])

	bag.clear()
	for k: Variant in (d.get("bag", {}) as Dictionary):
		bag[String(k)] = int((d["bag"] as Dictionary)[k])

	cap_index = int(d.get("capIndex", 0))
	current_map = StringName(String(d.get("map", "twinleaf_town")))

	var cell: Array = d.get("cell", [0, 0])
	player_cell = Vector2i(int(cell[0]), int(cell[1])) if cell.size() >= 2 else Vector2i.ZERO
	var facing: Array = d.get("facing", [0, 1])
	player_facing = Vector2i(int(facing[0]), int(facing[1])) if facing.size() >= 2 else Vector2i.DOWN

	rng_seed = int(d.get("rngSeed", 0))
	return true


## int-casts the fields the rest of the engine indexes on. Unknown keys survive
## untouched so the battle stream can add its own without editing this file --
## but any numeric key it adds and then reads as an int must be listed here.
func _restore_pokemon(src: Dictionary) -> Dictionary:
	var m: Dictionary = src.duplicate(true)
	for k in ["species", "level", "exp", "hp", "maxHp", "ability", "friendship"]:
		if m.has(k):
			m[k] = int(m[k])
	for k in ["ivs", "evs"]:
		if m.has(k) and m[k] is Array:
			var nums: Array = []
			for n: Variant in (m[k] as Array):
				nums.append(int(n))
			m[k] = nums
	return m
