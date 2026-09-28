extends Control
## The Custom Battle builder: two teams, twelve slots, and everything about the
## fight that is not the fight itself.
##
## It owns a `BattleSpec` (see `src/custom/battle_spec.gd` for the shape) and edits
## it in place. It never builds a Pokemon except to show a stat line, never starts
## a battle, and never touches `GameState` -- it emits [signal start_requested]
## with the spec and `src/custom/custom_battle.gd` does the rest. That split is
## what lets the whole builder be driven from a headless test.
##
## THREE SCREENS, ONE STATE MACHINE
##   TEAMS   the overview: 6 slots a side, a cursor, the settings summary.
##   SLOT    one Pokemon: species, level, nature, ability, item, four moves.
##   PICK    a `pick_list` is up and owns the keyboard; `_pick_purpose` says what
##           the answer means. PROMPT is the same thing for typed text.
##
## CONTROLS ARE DELIBERATELY NOT THE OVERWORLD'S. WASD moves the cursor (the
## `ui_*` actions, as everywhere else) but the pickers filter as you type, so
## inside one the arrow keys move instead -- see `pick_list.gd`'s header. Both
## schemes are printed on screen; a builder is not a place to make someone guess.
##
## CHANGING A SPECIES RESETS WHAT DEPENDED ON IT. Moves, ability and held stone are
## all species-specific, so keeping them across a species change would leave the
## slot illegal -- exactly the silent trap `party_builder.from_boss_member()`
## documents for the rival's dynamic starter. The new species gets its level-up
## moveset and a default ability instead.

signal start_requested(spec: Dictionary)
signal exit_requested()

const UI := preload("res://src/ui/ui_kit.gd")
const PickList := preload("res://src/ui/pick_list.gd")
const TextPrompt := preload("res://src/ui/text_prompt.gd")
const Spec := preload("res://src/custom/battle_spec.gd")
const Stats := preload("res://src/battle/stats.gd")
const Bosses := preload("res://src/systems/bosses.gd")
const Deps := preload("res://src/battle/deps.gd")

enum State { TEAMS, SLOT, PICK, PROMPT }

const SIDE_KEYS: Array = ["player", "foe"]
const SIDE_LABELS: Array = ["YOU", "FOE"]

## The slot editor's rows, in cursor order. The move rows are ONE-BASED
## (`move1`..`move4`) and that name is the only encoding: it is the cursor row, the
## picker purpose and, through [method _move_index], the 0-based index into the
## slot moves array. Never re-encode it.
const FIELDS: Array = ["species", "level", "nature", "ability", "item",
	"move1", "move2", "move3", "move4", "clear"]
const FIELD_LABELS: Dictionary = {
	"species": "SPECIES", "level": "LEVEL", "nature": "NATURE",
	"ability": "ABILITY", "item": "ITEM", "move1": "MOVE 1", "move2": "MOVE 2",
	"move3": "MOVE 3", "move4": "MOVE 4", "clear": "CLEAR SLOT",
}

var spec: Dictionary = {}
## False while something else owns the keyboard (the result panel). Explicit
## rather than relying on `_unhandled_input` ordering between sibling nodes.
var active: bool = true

var _state: State = State.TEAMS
var _side: int = 0
var _row: int = 0
var _field: int = 0
var _status: String = ""

var _picker: Control = null
var _prompt: Control = null
var _pick_purpose: String = ""

var _teams_root: Control = null
var _slot_root: Control = null
var _team_rows: Array = []          # [side][row] -> Label
var _team_heads: Array = []         # [side] -> Label
var _settings: Array = []           # Array[Label]
var _status_label: Label = null
var _slot_title: Label = null
var _slot_rows: Array = []          # Array[Label]
var _slot_detail: Array = []        # Array[Label]
var _species_cache: Array = []


func _ready() -> void:
	name = "TeamBuilder"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if spec.is_empty():
		spec = Spec.new_spec()

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.07, 0.09, 0.13, 1.0)
	backdrop.size = Vector2(256, 192)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_build_teams_screen()
	_build_slot_screen()

	_picker = PickList.new()
	add_child(_picker)
	_picker.picked.connect(_on_picked)
	_picker.cancelled.connect(_on_pick_cancelled)

	_prompt = TextPrompt.new()
	add_child(_prompt)
	_prompt.submitted.connect(_on_prompt_submitted)
	_prompt.cancelled.connect(_on_pick_cancelled)

	_enter(State.TEAMS)


# --------------------------------------------------------------------------
# Screen construction
# --------------------------------------------------------------------------

func _build_teams_screen() -> void:
	_teams_root = Control.new()
	_teams_root.name = "Teams"
	_teams_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_teams_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_teams_root)

	UI.label(_teams_root, "CUSTOM BATTLE", Vector2(6, 2), UI.FONT_BIG, UI.ACCENT, 160)

	for side in 2:
		var frame := UI.panel(_teams_root,
			Rect2(4 + float(side) * 128, 14, 120, 86), "Team%d" % side)
		_team_heads.append(UI.label(frame, String(SIDE_LABELS[side]),
			Vector2(5, 3), UI.FONT, UI.ACCENT, 110))
		var rows: Array = []
		for i in Spec.MAX_SLOTS:
			rows.append(UI.label(frame, "--", Vector2(5, 15.0 + float(i) * 11.0),
				UI.FONT, UI.TEXT, 110))
		_team_rows.append(rows)

	for i in 3:
		_settings.append(UI.label(_teams_root, "", Vector2(6, 104.0 + float(i) * 10.0),
			UI.FONT, UI.TEXT_DIM, 244))

	_status_label = UI.wrapped(_teams_root, "", Rect2(6, 138, 244, 30), UI.FONT, UI.TEXT)
	UI.label(_teams_root, "wasd move  enter edit  tab menu  r start  esc title",
		Vector2(6, 178), UI.FONT, UI.TEXT_DIM, 244)


func _build_slot_screen() -> void:
	_slot_root = Control.new()
	_slot_root.name = "Slot"
	_slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_slot_root)

	_slot_title = UI.label(_slot_root, "", Vector2(6, 2), UI.FONT_BIG, UI.ACCENT, 244)
	var frame := UI.panel(_slot_root, Rect2(4, 14, 248, 138), "Fields")
	for i in FIELDS.size():
		var y := 4.0 + float(i) * 13.0
		UI.label(frame, String(FIELD_LABELS[FIELDS[i]]), Vector2(6, y), UI.FONT, UI.TEXT_DIM, 74)
		_slot_rows.append(UI.label(frame, "", Vector2(82, y), UI.FONT, UI.TEXT, 160))
	for i in 2:
		_slot_detail.append(UI.label(_slot_root, "", Vector2(6, 156.0 + float(i) * 10.0),
			UI.FONT, UI.TEXT_DIM, 244))
	UI.label(_slot_root, "wasd move  a/d level  enter change  esc back",
		Vector2(6, 178), UI.FONT, UI.TEXT_DIM, 244)


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

func _enter(next: State) -> void:
	_state = next
	_teams_root.visible = next == State.TEAMS
	_slot_root.visible = next == State.SLOT
	if next != State.PICK and _picker != null:
		_picker.close()
	if next != State.PROMPT and _prompt != null:
		_prompt.close()
	refresh()


## Redraw whichever screen is up. Public so a test can assert on what is shown.
func refresh() -> void:
	if _teams_root != null and _teams_root.visible:
		_refresh_teams()
	if _slot_root != null and _slot_root.visible:
		_refresh_slot()


func _refresh_teams() -> void:
	for side in 2:
		var team: Dictionary = spec[SIDE_KEYS[side]]
		var head: Label = _team_heads[side]
		head.text = "%s  %s" % [String(SIDE_LABELS[side]), String(team.get("name", ""))]
		head.add_theme_color_override("font_color",
			UI.ACCENT if side == _side else UI.TEXT_DIM)
		for i in Spec.MAX_SLOTS:
			var label: Label = (_team_rows[side] as Array)[i]
			var slot: Dictionary = (team["slots"] as Array)[i]
			var selected := side == _side and i == _row
			label.text = "%s%s" % ["> " if selected else "  ", Spec.slot_label(slot)]
			var empty := int(slot.get("species", 0)) <= 0
			label.add_theme_color_override("font_color",
				UI.ACCENT if selected else (UI.TEXT_DIM if empty else UI.TEXT))

	var seed_value := int(spec.get("seed", 0))
	(_settings[0] as Label).text = "FORMAT %s%s      SEED %s" % [
		String(spec.get("format", "single")),
		"" if Spec.IMPLEMENTED_FORMATS.has(String(spec.get("format", "single")))
			else " (locked)",
		"auto" if seed_value == 0 else str(seed_value)]
	(_settings[1] as Label).text = "EXP %s   WATCH %s   FOE AI %d" % [
		"on" if bool(spec.get("awardExp", false)) else "off",
		"on" if bool(spec.get("watch", false)) else "off",
		int((spec["foe"] as Dictionary).get("ai", Spec.DEFAULT_AI))]
	(_settings[2] as Label).text = "MEGA  you %s   foe %s" % [
		"on" if bool((spec["player"] as Dictionary).get("keyStone", true)) else "off",
		"on" if bool((spec["foe"] as Dictionary).get("keyStone", true)) else "off"]

	_status_label.text = _status if not _status.is_empty() else _readiness()
	# Red is "R will refuse", amber is "R will work but read this first".
	var colour := UI.TEXT
	if not Spec.validate(spec).is_empty():
		colour = UI.HP_LOW
	elif not Spec.advisories(spec).is_empty():
		colour = UI.HP_WARN
	_status_label.add_theme_color_override("font_color", colour)


## The one line that says whether R will do anything, and why not when it will not.
func _readiness() -> String:
	var problems := Spec.validate(spec)
	if not problems.is_empty():
		return problems[0]
	var notes := Spec.advisories(spec)
	if not notes.is_empty():
		return "%s%s  R to battle anyway." % [notes[0],
			"" if notes.size() == 1 else "  (+%d more)" % (notes.size() - 1)]
	return "Ready: %d v %d.  R to battle." % [
		Spec.filled_slots(spec["player"]).size(), Spec.filled_slots(spec["foe"]).size()]


func _refresh_slot() -> void:
	var slot := _current_slot()
	var species := int(slot.get("species", 0))
	_slot_title.text = "%s TEAM - SLOT %d" % [String(SIDE_LABELS[_side]), _row + 1]

	for i in FIELDS.size():
		var label: Label = _slot_rows[i]
		var selected := i == _field
		label.text = "%s%s" % ["> " if selected else "  ", _field_value(String(FIELDS[i]), slot)]
		label.add_theme_color_override("font_color", UI.ACCENT if selected else UI.TEXT)

	if species <= 0:
		(_slot_detail[0] as Label).text = "Empty slot -- pick a species."
		(_slot_detail[1] as Label).text = ""
		return
	var mon := Spec.build_mon(slot)
	var types := PackedStringArray(mon.get("types", []))
	(_slot_detail[0] as Label).text = "%s   %s" % [
		String("/").join(types), UI.pretty(String(mon.get("ability", "-")))]
	var stats: Dictionary = mon.get("stats", {})
	(_slot_detail[1] as Label).text = "HP%d ATK%d DEF%d SPA%d SPD%d SPE%d" % [
		int(stats.get("hp", 0)), int(stats.get("atk", 0)), int(stats.get("def", 0)),
		int(stats.get("spa", 0)), int(stats.get("spd", 0)), int(stats.get("spe", 0))]


func _field_value(field: String, slot: Dictionary) -> String:
	var species := int(slot.get("species", 0))
	match field:
		"species":
			return "--" if species <= 0 else Spec.species_name(species)
		"level":
			return str(int(slot.get("level", Spec.DEFAULT_LEVEL)))
		"nature":
			return String(slot.get("nature", "hardy"))
		"ability":
			var a := String(slot.get("ability", ""))
			return "(default)" if a.is_empty() else UI.pretty(a)
		"item":
			var it := String(slot.get("item", ""))
			if it.is_empty():
				return "(none)"
			# A held item the engine never reads is marked, not hidden: a roster can
			# bring one in and the player has to be able to see that it does nothing.
			return UI.pretty(it) + ("" if Spec.item_is_live(slot) else "  (inert)")
		"clear":
			return ""
	var move_index := _move_index(field)
	if move_index >= 0:
		var moves: Array = slot.get("moves", [])
		if move_index < moves.size():
			return UI.pretty(String(moves[move_index]))
		return "(empty)"
	return ""


static func _move_index(field: String) -> int:
	if field.begins_with("move"):
		return int(field.substr(4)) - 1
	return -1


func _current_team() -> Dictionary:
	return spec[SIDE_KEYS[_side]]


func _current_slot() -> Dictionary:
	return (_current_team()["slots"] as Array)[_row]


# --------------------------------------------------------------------------
# Input
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not active or not visible:
		return
	if _picker == null or _prompt == null:
		return                          # _ready() aborted; do not bury the real error
	if _picker.is_open() or _prompt.is_open():
		return                          # they own the keyboard while they are up
	match _state:
		State.TEAMS:
			_teams_input(event)
		State.SLOT:
			_slot_input(event)
		_:
			pass


func _teams_input(event: InputEvent) -> void:
	if _pressed(event, &"ui_down", KEY_DOWN):
		_row = (_row + 1) % Spec.MAX_SLOTS
	elif _pressed(event, &"ui_up", KEY_UP):
		_row = (_row - 1 + Spec.MAX_SLOTS) % Spec.MAX_SLOTS
	elif _pressed(event, &"ui_right", KEY_RIGHT) or _pressed(event, &"ui_left", KEY_LEFT):
		_side = 1 - _side
	elif event.is_action_pressed(&"ui_accept"):
		_status = ""
		_field = 0
		_enter(State.SLOT)
		get_viewport().set_input_as_handled()
		return
	elif _key(event, KEY_TAB):
		_open_options()
		get_viewport().set_input_as_handled()
		return
	elif _key(event, KEY_R):
		_start()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		exit_requested.emit()
		return
	else:
		return
	_status = ""
	refresh()
	get_viewport().set_input_as_handled()


func _slot_input(event: InputEvent) -> void:
	var field := String(FIELDS[_field])
	if _pressed(event, &"ui_down", KEY_DOWN):
		_field = (_field + 1) % FIELDS.size()
	elif _pressed(event, &"ui_up", KEY_UP):
		_field = (_field - 1 + FIELDS.size()) % FIELDS.size()
	elif _pressed(event, &"ui_right", KEY_RIGHT):
		_nudge_level(10 if _shift(event) else 1)
	elif _pressed(event, &"ui_left", KEY_LEFT):
		_nudge_level(-10 if _shift(event) else -1)
	elif event.is_action_pressed(&"ui_accept"):
		get_viewport().set_input_as_handled()
		_activate_field(field)
		return
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_enter(State.TEAMS)
		return
	else:
		return
	refresh()
	get_viewport().set_input_as_handled()


## True for either the WASD action or the raw arrow key, so both schemes work on
## the screens that are not filter boxes.
static func _pressed(event: InputEvent, action: StringName, keycode: Key) -> bool:
	if event.is_action_pressed(action):
		return true
	return _key(event, keycode)


static func _key(event: InputEvent, keycode: Key) -> bool:
	var k := event as InputEventKey
	return k != null and k.pressed and not k.echo and k.keycode == keycode


static func _shift(event: InputEvent) -> bool:
	var k := event as InputEventKey
	return k != null and k.shift_pressed


func _nudge_level(delta: int) -> void:
	if String(FIELDS[_field]) != "level":
		return
	var slot := _current_slot()
	slot["level"] = clampi(int(slot.get("level", Spec.DEFAULT_LEVEL)) + delta,
		Spec.MIN_LEVEL, Spec.MAX_LEVEL)


# --------------------------------------------------------------------------
# Field actions
# --------------------------------------------------------------------------

func _activate_field(field: String) -> void:
	var slot := _current_slot()
	var species := int(slot.get("species", 0))

	match field:
		"species":
			_open_pick("species", {
				"title": "SPECIES", "items": _species_items(), "details": true,
				"selected": species if species > 0 else null,
				"footer": "up/down move  enter pick  esc back  filter: no. name type"})
			return
		"level":
			var levels: Array = []
			for lvl in range(Spec.MIN_LEVEL, Spec.MAX_LEVEL + 1):
				levels.append({"id": lvl, "label": "Lv%d" % lvl, "note": ""})
			_open_pick("level", {"title": "LEVEL", "items": levels,
				"selected": int(slot.get("level", Spec.DEFAULT_LEVEL))})
			return
		"clear":
			(_current_team()["slots"] as Array)[_row] = Spec.new_slot()
			_enter(State.TEAMS)
			return

	if species <= 0:
		_note("Pick a species first.")
		return

	match field:
		"nature":
			var natures: Array = []
			for n: String in Stats.nature_names():
				natures.append({"id": n, "label": n, "note": _nature_note(n)})
			_open_pick("nature", {"title": "NATURE", "items": natures,
				"selected": String(slot.get("nature", "hardy"))})
		"ability":
			var first := Spec.legal_abilities(species)
			var abilities: Array = [{"id": "", "label": "(default)",
				"note": "", "detail": "",
				"effect": "Use the first ability this species has: %s." % (
					UI.pretty(String(first[0])) if not first.is_empty() else "none")}]
			for a: String in first:
				var row: Dictionary = _ability_data(a)
				abilities.append({
					"id": a, "label": UI.pretty(a),
					"note": ability_note(row),
					"detail": ability_status(row),
					"effect": ability_text(row),
				})
			_open_pick("ability", {"title": "ABILITY", "items": abilities,
				"details": true, "selected": String(slot.get("ability", ""))})
		"item":
			var stones := Spec.item_choices(species)
			if stones.is_empty():
				_note("%s has no Mega Stone. (Held items other than stones do nothing yet.)"
					% Spec.species_name(species))
				return
			var items: Array = [{"id": "", "label": "(none)", "note": ""}]
			for s: String in stones:
				items.append({"id": s, "label": UI.pretty(s), "note": "mega"})
			_open_pick("item", {"title": "HELD ITEM", "items": items,
				"selected": String(slot.get("item", ""))})
		_:
			var move_index := _move_index(field)
			if move_index < 0:
				return
			var pool := Spec.legal_moves(species)
			if pool.is_empty():
				_note("%s has no legal moves in the data." % Spec.species_name(species))
				return
			var moves: Array = [{"id": "", "label": "(empty)", "note": "",
				"detail": "", "effect": "Leave this slot empty."}]
			for slug: String in pool:
				var m: Dictionary = _move_data(slug)
				moves.append({
					"id": slug,
					"label": UI.pretty(slug),
					"note": move_note(m),
					"detail": move_stats_line(m),
					"effect": move_effect_text(m),
					# So a learnset narrows on "physical" as well as on "rock".
					"search": "%s %s" % [String(m.get("type", "")),
						String(m.get("category", ""))],
				})
			var current: Array = slot.get("moves", [])
			# The purpose is the FIELD NAME, not the index. Encoding the 0-based
			# index here and decoding it with the 1-based field rule in _on_picked
			# is an off-by-one that silently dropped MOVE 1 and made MOVE 2-4 each
			# write to the slot above. One convention, no arithmetic.
			_open_pick(field, {"title": "MOVE %d" % (move_index + 1),
				"items": moves, "details": true,
				"selected": String(current[move_index]) if move_index < current.size() else ""})


func _nature_note(nature: String) -> String:
	var pair: Array = Stats.NATURES.get(nature, [])
	if pair.size() != 2 or pair[0] == pair[1]:
		return "neutral"
	return "+%s -%s" % [String(pair[0]).to_upper(), String(pair[1]).to_upper()]


func _ability_data(slug: String) -> Dictionary:
	var reg := Deps.registry()
	if reg == null or not reg.has_method("get_ability_by_name"):
		return {}
	return reg.get_ability_by_name(slug)


## DATA_CONTRACT 4 `tier`: 1 = the engine implements it, 2 = declared but inert,
## 3 = data only. In a battle sandbox that is the single most important thing about
## an ability, so it goes on the row and not just in the detail line -- picking
## Stench to test a flinch strategy and getting nothing is a bad way to find out.
static func ability_note(row: Dictionary) -> String:
	if row.is_empty():
		return ""
	match int(row.get("tier", 3)):
		1:
			return "works"
		2:
			return "inert"
		_:
			return "no effect"


static func ability_status(row: Dictionary) -> String:
	if row.is_empty():
		return ""
	var hook := String(row.get("hook", "none"))
	match int(row.get("tier", 3)):
		1:
			return "IMPLEMENTED%s" % ("" if hook == "none" else "   hook: " + hook)
		2:
			return "DECLARED BUT INERT -- it does nothing in battle yet"
		_:
			return "DATA ONLY -- it does nothing in battle yet"


static func ability_text(row: Dictionary) -> String:
	if row.is_empty():
		return ""
	var text := String(row.get("text", ""))
	return text if not text.is_empty() else "(no description in the data)"


func _move_data(slug: String) -> Dictionary:
	var reg := Deps.registry()
	return {} if reg == null else reg.get_move_by_name(slug)


## The narrow right-hand column: type, power and category, for scanning a list.
## "ROCK 75 PHY". Physical versus special decides which attacking stat is used, so
## it belongs on the row and not only in the detail line.
static func move_note(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	var power: Variant = m.get("power", null)
	return "%s %s %s" % [
		String(m.get("type", "?")).substr(0, 4).to_upper(),
		"-" if power == null or int(power) <= 0 else str(int(power)),
		String(m.get("category", "status")).substr(0, 3).to_upper()]


## The detail line under the list: everything that decides whether a move is worth
## a slot, in the order it gets asked about.
static func move_stats_line(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	var power: Variant = m.get("power", null)
	var acc: Variant = m.get("accuracy", null)
	var parts := PackedStringArray([
		String(m.get("category", "status")).to_upper(),
		"PWR %s" % ("-" if power == null or int(power) <= 0 else str(int(power))),
		# DATA_CONTRACT 2: a null accuracy never misses, which is not the same as
		# an accuracy of 0 and must not be drawn as one.
		"ACC %s" % ("always" if acc == null else str(int(acc))),
		"PP %d" % int(m.get("pp", 0)),
	])
	var priority := int(m.get("priority", 0))
	if priority != 0:
		parts.append("PRI %+d" % priority)
	return String("   ").join(parts)


## The effect, turned back into a sentence.
##
## `data/moves.json` stores it slugified -- `lowers-the-target-s-defense-by-two-stages`
## -- so the possessive apostrophe survives only as a lone `s` between hyphens, in
## 246 of the 919 rows. Rejoining without putting it back reads as a typo.
##
## 92 moves have no effect text at all (an upstream veekun gap, mostly Gen 8-9).
## That is stated rather than left blank: a blank line reads as a UI fault, and the
## gap is real and worth seeing.
static func move_effect_text(m: Dictionary) -> String:
	if m.is_empty():
		return ""
	var slug := String(m.get("effect", "")) if m.get("effect", null) != null else ""
	if slug.is_empty():
		return "(no effect text for this move in the data)"
	var out := ""
	for word: String in slug.split("-"):
		if word == "s" and not out.is_empty():
			out += "'s"
		else:
			out += ("" if out.is_empty() else " ") + word
	out = out.substr(0, 1).to_upper() + out.substr(1)

	var chance := int(m.get("effectChance", 0)) if m.get("effectChance", null) != null else 0
	# A 100% "chance" is not a chance; the sentence already covers it.
	if chance > 0 and chance < 100:
		out = "%d%% %s" % [chance, out.substr(0, 1).to_lower() + out.substr(1)]
	out += "."
	if PackedStringArray(m.get("flags", [])).has("contact"):
		# Contact is the flag the ability layer actually branches on (Rough Skin,
		# Aura Guard, Unseen Fist), so it is worth a word.
		out += "  Makes contact."
	return out


func _species_items() -> Array:
	if not _species_cache.is_empty():
		return _species_cache
	var reg := Deps.registry()
	if reg == null:
		return []
	for id in reg.species_ids():
		var sp: Dictionary = reg.get_species(int(id))
		var types: Array = sp.get("types", [])
		# The dex number moves into the label so the note column is free for the
		# types: all three things a player might search by are then on screen, and
		# typing any of them narrows the list.
		_species_cache.append({
			"id": int(id),
			"label": "%d %s" % [int(id), String(sp.get("name", "?"))],
			"note": type_note(types),
			# The note abbreviates a dual type to DRA/GRO to fit the column; the
			# full names live here so `dragon` and `ground` still find it.
			"search": String(" ").join(PackedStringArray(types)).to_lower(),
			"detail": base_stat_line(sp),
			"effect": species_blurb(sp),
		})
	return _species_cache


## The six base stats and their total, for the detail line under the list.
##
## BASE stats, not the stats at this level: the level is set on the slot, not in
## this picker, and a level-1 stat line would make every species look identical.
## The total is what actually separates a Bidoof from a Garchomp at a glance.
static func base_stat_line(sp: Dictionary) -> String:
	var stats: Dictionary = sp.get("stats", {})
	if stats.is_empty():
		return ""
	var total := 0
	var parts := PackedStringArray()
	for key: String in ["hp", "atk", "def", "spa", "spd", "spe"]:
		var v := int(stats.get(key, 0))
		total += v
		parts.append("%s %d" % [key.to_upper(), v])
	return "%s   BST %d" % [String(" ").join(parts), total]


## The prose line under a species: what it is and what it can have.
static func species_blurb(sp: Dictionary) -> String:
	# Capitalise each type, not the joined string: String.capitalize() only
	# touches the first letter and leaves "Dragon/ground".
	var types := PackedStringArray()
	for t: Variant in (sp.get("types", []) as Array):
		types.append(String(t).capitalize())
	var out := String("/").join(types)
	var abilities := PackedStringArray()
	for slug: Variant in (sp.get("abilities", []) as Array):
		abilities.append(Spec.pretty(String(slug)))
	if sp.get("hiddenAbility", null) != null and not String(sp["hiddenAbility"]).is_empty():
		abilities.append("%s (hidden)" % Spec.pretty(String(sp["hiddenAbility"])))
	if not abilities.is_empty():
		out += ".   " + String(", ").join(abilities)
	return out + "."


## Types as the narrow right-hand column can draw them: one type in full, two
## abbreviated to three letters each. `electric/flying` is fifteen characters and
## the column fits about nine.
static func type_note(types: Array) -> String:
	if types.is_empty():
		return ""
	if types.size() == 1:
		return String(types[0]).to_upper()
	var out := PackedStringArray()
	for t: Variant in types:
		out.append(String(t).substr(0, 3).to_upper())
	return String("/").join(out)


# --------------------------------------------------------------------------
# The options menu
# --------------------------------------------------------------------------

func _open_options() -> void:
	var seed_value := int(spec.get("seed", 0))
	var player: Dictionary = spec["player"]
	var foe: Dictionary = spec["foe"]
	var rows: Array = [
		{"id": "start", "label": "Start battle", "note": "r"},
		{"id": "format", "label": "Format: %s" % String(spec.get("format", "single")),
			"note": "singles only"},
		{"id": "watch", "label": "Watch mode (AI vs AI): %s"
			% ("on" if bool(spec.get("watch", false)) else "off"), "note": ""},
		{"id": "seed", "label": "Seed: %s" % ("auto" if seed_value == 0 else str(seed_value)),
			"note": "repeatable"},
		{"id": "exp", "label": "Award EXP: %s"
			% ("on" if bool(spec.get("awardExp", false)) else "off"), "note": ""},
		{"id": "ai", "label": "Foe AI: %d" % int(foe.get("ai", Spec.DEFAULT_AI)), "note": "0-10"},
		{"id": "mega0", "label": "Your Key Stone: %s"
			% ("on" if bool(player.get("keyStone", true)) else "off"), "note": ""},
		{"id": "mega1", "label": "Foe Key Stone: %s"
			% ("on" if bool(foe.get("keyStone", true)) else "off"), "note": ""},
		{"id": "fill0", "label": "Fill YOUR team...", "note": ""},
		{"id": "fill1", "label": "Fill FOE team...", "note": ""},
		{"id": "swap", "label": "Swap the two teams", "note": ""},
		{"id": "save", "label": "Save this matchup...", "note": ""},
		{"id": "load", "label": "Load a matchup...", "note": ""},
		{"id": "delete", "label": "Delete a saved matchup...", "note": ""},
		{"id": "title", "label": "Back to the title screen", "note": "esc"},
	]
	_open_pick("option", {"title": "OPTIONS", "items": rows, "searchable": false,
		"footer": "up/down move  enter choose  esc back"})


func _on_option(id: String) -> void:
	match id:
		"start":
			_enter(State.TEAMS)
			_start()
		"format":
			var formats: Array = []
			for f: String in Spec.FORMATS:
				formats.append({"id": f, "label": f.capitalize(),
					"note": "%d out" % int(Spec.FORMAT_ACTIVE.get(f, 1))
						if Spec.IMPLEMENTED_FORMATS.has(f) else "not implemented"})
			_open_pick("format", {"title": "FORMAT", "items": formats, "searchable": false,
				"selected": String(spec.get("format", "single"))})
		"watch":
			spec["watch"] = not bool(spec.get("watch", false))
			_note("Watch mode %s." % ("on -- both sides play themselves"
				if bool(spec["watch"]) else "off"))
			_enter(State.TEAMS)
		"exp":
			spec["awardExp"] = not bool(spec.get("awardExp", false))
			_note("EXP %s." % ("on -- Pokemon may level up mid-battle"
				if bool(spec["awardExp"]) else "off"))
			_enter(State.TEAMS)
		"seed":
			var current := int(spec.get("seed", 0))
			_open_prompt("seed", {"title": "RNG SEED",
				"text": "" if current == 0 else str(current),
				"hint": "empty = a new seed each battle", "digits_only": true})
		"ai":
			var levels: Array = []
			for i in 11:
				levels.append({"id": i, "label": "AI %d" % i,
					"note": "picks its best move" if i < 3 else "switches on a bad matchup"})
			_open_pick("ai", {"title": "FOE AI", "items": levels, "searchable": false,
				"selected": int((spec["foe"] as Dictionary).get("ai", Spec.DEFAULT_AI))})
		"mega0", "mega1":
			var side_key := "player" if id == "mega0" else "foe"
			var team: Dictionary = spec[side_key]
			team["keyStone"] = not bool(team.get("keyStone", true))
			_note("%s Key Stone %s." % [
				"Your" if side_key == "player" else "The foe's",
				"on" if bool(team["keyStone"]) else "off"])
			_enter(State.TEAMS)
		"fill0", "fill1":
			var side := 0 if id == "fill0" else 1
			_open_pick("fill%d" % side, {"title": "FILL %s TEAM" % String(SIDE_LABELS[side]),
				"searchable": false, "items": [
					{"id": "boss", "label": "A boss roster...",
						"note": "%d" % Bosses.count()},
					{"id": "random", "label": "Six random Pokemon", "note": "Lv50"},
					{"id": "party", "label": "My campaign party",
						"note": "%d" % GameState.party.size()},
					{"id": "clear", "label": "Clear the team", "note": ""},
				]})
		"swap":
			var was: Dictionary = spec["player"]
			spec["player"] = spec["foe"]
			spec["foe"] = was
			_note("Teams swapped.")
			_enter(State.TEAMS)
		"save":
			_open_prompt("save", {"title": "SAVE AS", "text": "",
				"hint": "letters, digits and dashes"})
		"load", "delete":
			var names := Spec.list_presets()
			if names.is_empty():
				_note("No saved matchups yet.")
				_enter(State.TEAMS)
				return
			var rows: Array = []
			for n: String in names:
				rows.append({"id": n, "label": n, "note": ""})
			_open_pick(id, {"title": id.to_upper(), "items": rows, "searchable": false})
		"title":
			exit_requested.emit()
		_:
			_enter(State.TEAMS)


# --------------------------------------------------------------------------
# Picker plumbing
# --------------------------------------------------------------------------

func _open_pick(purpose: String, config: Dictionary) -> void:
	_pick_purpose = purpose
	_state = State.PICK
	_prompt.close()
	_picker.open(config)


func _open_prompt(purpose: String, config: Dictionary) -> void:
	_pick_purpose = purpose
	_state = State.PROMPT
	_picker.close()
	_prompt.open(config)


func _on_pick_cancelled() -> void:
	_picker.close()
	_prompt.close()
	_pick_purpose = ""
	_enter(State.TEAMS if not _slot_root.visible else State.SLOT)


func _on_picked(id: Variant) -> void:
	var purpose := _pick_purpose
	_picker.close()
	_pick_purpose = ""

	if purpose == "option":
		_on_option(String(id))
		return
	if purpose == "format":
		spec["format"] = String(id)
		if not Spec.IMPLEMENTED_FORMATS.has(String(id)):
			_note("%s battles need multi-slot support in battle_engine.gd; singles only for now."
				% String(id).capitalize())
		else:
			_note("")
		_enter(State.TEAMS)
		return
	if purpose == "ai":
		(spec["foe"] as Dictionary)["ai"] = int(id)
		_enter(State.TEAMS)
		return
	if purpose == "fill0" or purpose == "fill1":
		_fill(int(purpose.substr(4)), String(id))
		return
	if purpose == "boss0" or purpose == "boss1":
		var side := int(purpose.substr(4))
		var team := Spec.from_boss(String(id), Bosses)
		if team.is_empty():
			_note("Could not read that boss roster.")
		else:
			spec[SIDE_KEYS[side]] = team
			_note("%s loaded into the %s team." % [
				String(team.get("name", id)), String(SIDE_LABELS[side])])
		_enter(State.TEAMS)
		return
	if purpose == "load":
		var loaded := Spec.load_preset(String(id))
		if loaded.is_empty():
			_note("Could not read '%s'." % String(id))
		else:
			spec = loaded
			_note("Loaded '%s'." % String(id))
		_enter(State.TEAMS)
		return
	if purpose == "delete":
		_note("Deleted '%s'." % String(id) if Spec.delete_preset(String(id))
			else "Could not delete '%s'." % String(id))
		_enter(State.TEAMS)
		return

	# Everything left edits the slot the cursor is on.
	var slot := _current_slot()
	match purpose:
		"species":
			_set_species(slot, int(id))
		"level":
			slot["level"] = clampi(int(id), Spec.MIN_LEVEL, Spec.MAX_LEVEL)
		"nature":
			slot["nature"] = String(id)
		"ability":
			slot["ability"] = String(id)
		"item":
			slot["item"] = String(id)
		_:
			var move_index := _move_index(purpose)
			if move_index >= 0:
				_set_move(slot, move_index, String(id))
	_enter(State.SLOT)


## Changing the species invalidates the moves, the ability and the held stone --
## see the header. The replacement gets the level-up moveset it would have in the
## wild, which is a legal, sensible starting point rather than an empty slot.
func _set_species(slot: Dictionary, species: int) -> void:
	if int(slot.get("species", 0)) == species:
		return
	slot["species"] = species
	slot["ability"] = ""
	slot["item"] = ""
	slot["moves"] = Spec.default_moves(species, int(slot.get("level", Spec.DEFAULT_LEVEL)))


## Write one move slot. The moves array is dense, so setting slot 3 of a mon with
## two moves appends rather than leaving a hole, and clearing a middle move closes
## the gap -- which is what `Stats.build` expects to receive.
func _set_move(slot: Dictionary, move_index: int, slug: String) -> void:
	var moves: Array = (slot.get("moves", []) as Array).duplicate()
	if slug.is_empty():
		if move_index < moves.size():
			moves.remove_at(move_index)
	elif moves.has(slug) and (move_index >= moves.size() or String(moves[move_index]) != slug):
		_note("It already knows %s." % UI.pretty(slug))
		return
	elif move_index < moves.size():
		moves[move_index] = slug
	elif moves.size() < Spec.MAX_MOVES:
		moves.append(slug)
	slot["moves"] = moves


func _fill(side: int, what: String) -> void:
	match what:
		"boss":
			if Bosses.count() <= 0:
				_note("No boss table. data/rom/bosses.json is gitignored and needs the ROMs "
					+ "(python tools/build_gamedata.py).")
				_enter(State.TEAMS)
				return
			var rows: Array = []
			for key: String in Bosses.keys():
				var boss: Dictionary = Bosses.get_boss(key)
				rows.append({"id": key, "label": String(boss.get("name", key)),
					"note": "cap %d" % int(boss.get("cap", 0))})
			_open_pick("boss%d" % side, {"title": "BOSS ROSTER", "items": rows})
			return
		"random":
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			spec[SIDE_KEYS[side]] = Spec.random_team(rng)
			_note("Six random Pokemon in the %s team." % String(SIDE_LABELS[side]))
		"party":
			if GameState.party.is_empty():
				_note("The campaign party is empty -- there is no save loaded.")
			else:
				spec[SIDE_KEYS[side]] = Spec.from_party(GameState.party,
					String(SIDE_LABELS[side]))
				_note("Campaign party copied into the %s team." % String(SIDE_LABELS[side]))
		"clear":
			spec[SIDE_KEYS[side]] = Spec.new_team(String(SIDE_LABELS[side]).capitalize())
			_note("%s team cleared." % String(SIDE_LABELS[side]))
	_enter(State.TEAMS)


func _on_prompt_submitted(value: String) -> void:
	var purpose := _pick_purpose
	_prompt.close()
	_pick_purpose = ""
	match purpose:
		"seed":
			spec["seed"] = 0 if value.strip_edges().is_empty() else int(value)
			_note("Seed %s." % ("auto" if int(spec["seed"]) == 0
				else "pinned to %d -- the same battle every time" % int(spec["seed"])))
		"save":
			var saved := Spec.save_preset(spec, value)
			_note("Saved as '%s'." % saved if not saved.is_empty()
				else "That name has nothing usable in it.")
	_enter(State.TEAMS)


# --------------------------------------------------------------------------
# Starting
# --------------------------------------------------------------------------

func _start() -> void:
	var problems := Spec.validate(spec)
	if not problems.is_empty():
		_note(problems[0])
		refresh()
		return
	start_requested.emit(spec)


func _note(message: String) -> void:
	_status = message
	if not message.is_empty():
		Log.info(message, "CustomBattle")


# --------------------------------------------------------------------------
# Test / debug hooks -- the same code paths the keys take
# --------------------------------------------------------------------------

func debug_state() -> String:
	return ["teams", "slot", "pick", "prompt"][int(_state)]


## The text the slot editor is drawing for one field, so a test can assert on what
## is ON SCREEN and not just on what is in the spec. The move off-by-one showed up
## as a row that did not change.
func debug_field_text(field: String) -> String:
	var at := FIELDS.find(field)
	if at < 0 or at >= _slot_rows.size():
		return ""
	return (_slot_rows[at] as Label).text


func debug_status() -> String:
	return _status_label.text if _status_label != null else ""


func debug_focus(side: int, row: int) -> void:
	_side = clampi(side, 0, 1)
	_row = clampi(row, 0, Spec.MAX_SLOTS - 1)
	refresh()


## Open the slot editor on the focused slot, move to `field` and activate it.
func debug_edit_field(field: String) -> void:
	_field = maxi(FIELDS.find(field), 0)
	_enter(State.SLOT)
	_activate_field(field)


## Answer whatever picker is open, as if it had been chosen with Enter.
func debug_pick(id: Variant) -> void:
	if _picker.is_open() or _state == State.PICK:
		_on_picked(id)


func debug_option(id: String) -> void:
	_on_option(id)


func debug_start() -> void:
	_start()
