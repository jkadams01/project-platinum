extends "res://src/battle/abilities/paradox.gd"
## **Protosynthesis** -- the Ancient Paradox line (Great Tusk, Flutter Mane,
## Roaring Moon and the rest).
##
## Roused by HARSH SUNLIGHT, or by a Booster Energy when the sun is not out. All
## of the behaviour is in paradox.gd; this file supplies the trigger and the name.

func slug() -> String:
	return "protosynthesis"


func field_condition() -> String:
	return "sun"


func ability_name() -> String:
	return "Protosynthesis"
