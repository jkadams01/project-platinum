extends "res://src/battle/abilities/ability.gd"
## Dragonize -- Mega Feraligatr (feraligatr-mega). Mega-exclusive.
##
## pokemondb: "Dragonize causes all Normal-type attacking moves used by the
## Pokemon to become Dragon-type, and increase in power by 20%." Dragon-types
## gain STAB on the converted move, "resulting in an 80% effective increase."
## Bulbapedia flavour: "The Pokemon's Normal-type moves become Dragon-type moves
## and their power is boosted by 20%." Listed as a variation of Normalize
## alongside Aerilate, Pixilate, Refrigerate and Galvanize.
##
## ORDER IS THE WHOLE ABILITY: convert first, THEN STAB, THEN the type chart.
## That is why this is onModifyMove (hook 2 of the ordering in
## docs/research/ability-implementation.md section 4.3) and runs before anything
## reads the move. Body Slam 85 power becomes a 102-power Dragon-type move which
## then takes x1.5 STAB off Mega Feraligatr's Water/DRAGON typing -- the
## 1.2 x 1.5 = 1.8 figure pokemondb cites. Applying STAB from the original Normal
## type, or applying the 1.2x after the type multiplier, both give wrong numbers.
##
## 1.2x is a POWER multiplier, not a damage multiplier: it goes into the base
## formula, where the integer divisions make the two differ.
##
## DAMAGING MOVES ONLY -- "Normal-type ATTACKING moves". The -ate family does not
## convert status moves, so a status move is left alone (Growl stays Normal).
##
## THE MOVE DICTIONARY MUST BE DUPLICATED, not mutated. resolve_turn() puts the
## mon's LIVE move dict into the action and _use_move writes move["pp"] into it,
## so mutating it here would make Body Slam permanently Dragon-type in the save.
## registry.modify_move() owns that duplication; this hook only reports the
## override.
##
## SIDE EFFECTS THAT LOOK LIKE BUGS AND ARE THE ABILITY WORKING: the move is
## Dragon for IMMUNITY purposes too, so a Fairy takes 0 from a Dragonized Body
## Slam, and a Ghost takes normal damage where Normal-type did nothing at all.
##
## SOURCE: https://pokemondb.net/ability/dragonize
##         https://bulbapedia.bulbagarden.net/wiki/Dragonize_(Ability)

const FROM_TYPE := "normal"
const TO_TYPE := "dragon"
const POWER_MULT := 1.2

## Moves whose type is set by another mechanism are not converted.
##
## INFERENCE, FLAGGED AS SUCH: neither source page states an exclusion list for
## Dragonize. This list is inherited from the documented -ate family (the
## Aerilate / Pixilate pages), which is how every other member of the family
## behaves. Of these only Struggle and Hidden Power are realistically reachable
## in this project; Tera Blast is excluded from the project entirely
## (DATA_CONTRACT 11.4 -- Mega Evolution is the only gimmick).
const EXCLUDED: Array = [
	"hidden-power", "weather-ball", "natural-gift", "judgment", "multi-attack",
	"techno-blast", "revelation-dance", "terrain-pulse", "struggle", "tera-blast",
]


func slug() -> String:
	return "dragonize"


## onModifyMoveType. Returns {} for anything it does not convert, which is the
## neutral value: registry.modify_move() then hands the ORIGINAL move dict back
## and nothing is duplicated.
func on_modify_move(ctx: Dictionary) -> Dictionary:
	var move: Dictionary = ctx.get("move", {})
	if move.is_empty():
		return {}
	if String(move.get("category", "status")) == "status":
		return {}
	if String(move.get("type", "")) != FROM_TYPE:
		return {}
	if EXCLUDED.has(String(move.get("slug", ""))):
		return {}
	# Endeavor and Flail are on Bulbapedia's own converted list and have no power
	# for the 1.2x to multiply. Harmless: registry.modify_move() leaves a power of
	# 0 alone rather than promoting it to 1.
	return {"type": TO_TYPE, "power_mult": POWER_MULT}
