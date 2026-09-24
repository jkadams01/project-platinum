extends Control
## The two combatant panels, plus the one readout this game needs that the
## original does not: the hard level cap.
##
## WHY THE CAP IS ON SCREEN. A Pokemon at or above the cap gains exactly zero EXP
## (CLAUDE.md "Locked design decisions", DATA_CONTRACT 8 `"rule": "hard-xp-stop"`).
## That is the headline mechanic, and a player who cannot see the number has no way
## to tell "this fight gave nothing" from "the EXP bar is broken". The panel shows
## the cap and marks any party member sitting on it.
##
## The HUD reads the engine; it never writes to it. [method refresh] pulls
## everything from `BattleEngine.active(side)` each time it is called, so there is
## no cached mon Dictionary to go stale when the engine switches one out or a Mega
## Evolution rewrites its stats in place.

const UI := preload("res://src/ui/ui_kit.gd")
const Stats := preload("res://src/battle/stats.gd")
const Mega := preload("res://src/battle/mega.gd")

var engine: RefCounted = null

var _foe_name: Label
var _foe_level: Label
var _foe_bar: ColorRect
var _foe_tag: Label
var _own_name: Label
var _own_level: Label
var _own_bar: ColorRect
var _own_hp: Label
var _own_tag: Label
var _cap: Label
var _foe_count: Label


func _ready() -> void:
	name = "BattleHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# opponent, top-left (their sprite would sit top-right)
	var foe := UI.panel(self, Rect2(6, 8, 130, 34), "FoePanel")
	_foe_name = UI.label(foe, "", Vector2(5, 3), UI.FONT_BIG, UI.TEXT, 92)
	_foe_level = UI.label(foe, "", Vector2(98, 4), UI.FONT, UI.TEXT_DIM, 28,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_foe_bar = UI.bar(foe, Rect2(5, 17, 120, 5), "FoeHp")
	_foe_tag = UI.label(foe, "", Vector2(5, 23), UI.FONT, UI.ACCENT, 120)
	_foe_count = UI.label(self, "", Vector2(140, 12), UI.FONT, UI.TEXT_DIM, 108,
		HORIZONTAL_ALIGNMENT_RIGHT)

	# player, bottom-right
	var own := UI.panel(self, Rect2(120, 88, 130, 40), "OwnPanel")
	_own_name = UI.label(own, "", Vector2(5, 3), UI.FONT_BIG, UI.TEXT, 92)
	_own_level = UI.label(own, "", Vector2(98, 4), UI.FONT, UI.TEXT_DIM, 28,
		HORIZONTAL_ALIGNMENT_RIGHT)
	_own_bar = UI.bar(own, Rect2(5, 17, 120, 5), "OwnHp")
	_own_hp = UI.label(own, "", Vector2(5, 23), UI.FONT, UI.TEXT, 60)
	_own_tag = UI.label(own, "", Vector2(66, 23), UI.FONT, UI.ACCENT, 60,
		HORIZONTAL_ALIGNMENT_RIGHT)

	_cap = UI.label(self, "", Vector2(6, 46), UI.FONT, UI.TEXT_DIM, 160)


func bind(battle_engine: RefCounted) -> void:
	engine = battle_engine
	refresh()


func refresh() -> void:
	if engine == null or _foe_name == null:
		return
	_panel(engine.active(1), _foe_name, _foe_level, _foe_bar, null, _foe_tag)
	_panel(engine.active(0), _own_name, _own_level, _own_bar, _own_hp, _own_tag)

	var cap := int(engine.current_cap())
	var at_cap := 0
	for mon: Dictionary in engine.party_of(0):
		if int(mon.get("level", 1)) >= cap:
			at_cap += 1
	var text := "CAP %d" % cap
	if at_cap > 0:
		text += "  -  %d at the cap (no EXP)" % at_cap
	_cap.text = text
	_cap.add_theme_color_override("font_color", UI.ACCENT if at_cap > 0 else UI.TEXT_DIM)

	var standing := 0
	for mon: Dictionary in engine.party_of(1):
		if not Stats.is_fainted(mon):
			standing += 1
	_foe_count.text = "" if standing <= 1 else "x%d left" % standing


func _panel(mon: Dictionary, name_label: Label, level_label: Label, bar: ColorRect,
		hp_label: Label, tag_label: Label) -> void:
	if mon.is_empty():
		name_label.text = "-"
		level_label.text = ""
		UI.set_bar(bar, 0.0)
		if hp_label != null:
			hp_label.text = ""
		tag_label.text = ""
		return
	name_label.text = Stats.display_name(mon)
	level_label.text = UI.level_text(int(mon.get("level", 1)))
	var max_hp := maxi(int(mon.get("maxHp", 1)), 1)
	var hp := clampi(int(mon.get("hp", 0)), 0, max_hp)
	UI.set_bar(bar, float(hp) / float(max_hp))
	if hp_label != null:
		hp_label.text = "%d/%d" % [hp, max_hp]

	# Status and Mega are the two things that change how the next turn plays out,
	# so they share the one tag slot with status winning: a burned Mega still
	# wants you to see the burn.
	var status := String(mon.get("status", ""))
	if not status.is_empty():
		tag_label.text = status.substr(0, 3).to_upper()
	elif Mega.is_mega(mon):
		tag_label.text = "MEGA"
	else:
		tag_label.text = ""
