extends "res://src/battle/abilities/paradox.gd"
## **Quark Drive** -- the Future Paradox line (Iron Treads, Iron Valiant,
## Miraidon and the rest).
##
## Roused by ELECTRIC TERRAIN, or by a Booster Energy when there is none. This
## engine has no terrain system, so today only the item can rouse it -- see
## paradox.gd. The condition below is already the right answer for the day terrain
## lands; nothing here changes then.

func slug() -> String:
	return "quark-drive"


func field_condition() -> String:
	return "electric"


func ability_name() -> String:
	return "Quark Drive"
