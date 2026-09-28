extends RefCounted
## Trainer AI. Simple, but not stupid.
##
## It scores every legal move with the real damage formula at the *average* roll
## (never consuming battle RNG, so the AI cannot desync a seeded replay) and
## picks the best. On top of that:
##
##   * **Immunities are never chosen.** A move the target takes 0 from scores
##     [constant SCORE_IMMUNE] and is only used if literally nothing else exists.
##   * **Super-effective is preferred** -- the score is expected damage as a
##     percentage of the target's *remaining* HP, so x2 beats x1 naturally, and
##     a guaranteed KO gets [constant KO_BONUS] on top.
##   * **Accuracy is priced in**: score is multiplied by accuracy/100, so a
##     70%-accurate big hit loses to a reliable one when the margin is thin.
##   * **Status moves** score a flat [constant STATUS_SCORE], zero if the target
##     already has a status or is immune to the one on offer -- enough to make
##     the AI open with Thunder Wave without spamming it.
##   * **It switches on a bad matchup**: if its best move is weak (resisted or
##     immune) *and* a benched Pokemon has a clearly better one, it switches.
##     [constant SWITCH_MARGIN] stops it from switch-looping on a coin-flip.
##
## `difficulty` (0..10, the `ai` field of DATA_CONTRACT 7 trainers) gates the
## smart parts: below [constant SMART_THRESHOLD] it picks its best *damaging*
## move without considering switching, which is what a Youngster should do.

const Stats := preload("res://src/battle/stats.gd")
const Status := preload("res://src/battle/status.gd")
const Damage := preload("res://src/battle/damage.gd")
const Abilities := preload("res://src/battle/abilities/registry.gd")
const Items := preload("res://src/battle/items.gd")

const SCORE_IMMUNE := -1000.0
const KO_BONUS := 60.0
const STATUS_SCORE := 18.0
const SWITCH_MARGIN := 25.0
const SMART_THRESHOLD := 3


## Pick an action for `ctx.self`.
##
## `ctx`:
## [codeblock]
## {self: Dictionary, foe: Dictionary, bench: Array[Dictionary],
##  side: int, difficulty: int, can_switch: bool, weather: String}
## [/codeblock]
## Returns `{kind:"move", move_index:int}` or `{kind:"switch", index:int}`,
## where `index` indexes `ctx.bench`. `{kind:"struggle"}` when nothing is legal.
static func choose_action(ctx: Dictionary) -> Dictionary:
	var me: Dictionary = ctx.get("self", {})
	var foe: Dictionary = ctx.get("foe", {})
	var difficulty := int(ctx.get("difficulty", 5))
	var weather := String(ctx.get("weather", ""))

	var scores := score_moves(me, foe, weather)
	var best_index := -1
	var best_score := -INF
	for i in scores.size():
		if float(scores[i]) > best_score:
			best_score = float(scores[i])
			best_index = i

	if best_index < 0:
		return {"kind": "struggle"}

	if difficulty >= SMART_THRESHOLD and bool(ctx.get("can_switch", false)):
		var sw := _consider_switch(ctx, best_score, weather)
		if sw >= 0:
			return {"kind": "switch", "index": sw, "reason": "bad matchup"}

	return {"kind": "move", "move_index": best_index, "score": best_score}


## Score every move of `me` against `foe`. Parallel to `me.moves`.
static func score_moves(me: Dictionary, foe: Dictionary, weather: String = "") -> Array:
	var out: Array = []
	for move: Dictionary in (me.get("moves", []) as Array):
		out.append(score_move(me, foe, move, weather))
	return out


static func score_move(me: Dictionary, foe: Dictionary, move: Dictionary,
		weather: String = "") -> float:
	if int(move.get("pp", 0)) <= 0:
		return SCORE_IMMUNE - 1.0
	# A held item can forbid a move outright -- a Choice lock, or an Assault Vest
	# against status moves. Scored below an immunity rather than skipped, so the
	# AI reaches for it only when there is literally nothing else, exactly as the
	# no-PP case does. Without this the AI picks a move the engine then refuses
	# and the side wastes its turn.
	if not Items.allows_move(me, move):
		return SCORE_IMMUNE - 1.0

	var category := String(move.get("category", "status"))
	var accuracy := 100.0 if move.get("accuracy", null) == null else float(move.get("accuracy", 100))

	if category == "status" or int(move.get("power", 0)) <= 0:
		return _score_status_move(me, foe, move) * (accuracy / 100.0)

	var eff := Damage.type_multiplier(String(move.get("type", "normal")),
		foe.get("types", PackedStringArray()), {"defender": foe, "move": move,
		"weather": weather})
	if is_zero_approx(eff):
		return SCORE_IMMUNE

	# onWeatherView: price the move under the weather ITS OWN user resolves it in.
	# Without this an AI Mega Meganium under-rates its best Fire move by a third,
	# and (once it has one) over-rates its Water moves.
	# `field_weather` keeps field-scoped effects (Delta Stream) visible while the
	# view changes only what THIS mon's move resolves under -- the same split the
	# engine makes in _use_move.
	var avg := Damage.average(me, foe, move, {
		"weather": Abilities.weather_view(me, weather), "field_weather": weather})
	var foe_hp := maxi(int(foe.get("hp", 1)), 1)
	var score := 100.0 * float(avg) / float(foe_hp)
	if avg >= foe_hp:
		score += KO_BONUS
	score *= accuracy / 100.0
	# A tie between equal-damage moves goes to the higher-priority one.
	score += 0.5 * float(int(move.get("priority", 0)))
	return score


static func _score_status_move(me: Dictionary, foe: Dictionary, move: Dictionary) -> float:
	var effect := String(move.get("effect", ""))
	var inflicts := _status_from_effect(effect)
	if inflicts != "":
		if Status.has_status(foe) or Status.is_immune(foe, inflicts):
			return 0.0
		return STATUS_SCORE
	# Boosting or utility: mildly positive, and worthless at full boost.
	if effect.begins_with("raise") or effect.contains("boost"):
		return STATUS_SCORE * 0.75 if Stats.get_stage(me, "atk") < 4 else 2.0
	return STATUS_SCORE * 0.5


static func _status_from_effect(effect: String) -> String:
	if effect.contains("paralyz"): return Status.PARALYSIS
	if effect.contains("burn"): return Status.BURN
	if effect.contains("badly-poison") or effect.contains("toxic"): return Status.TOXIC
	if effect.contains("poison"): return Status.POISON
	if effect.contains("sleep"): return Status.SLEEP
	if effect.contains("freeze"): return Status.FREEZE
	return ""


## Index into `ctx.bench` of a Pokemon worth switching to, or -1 to stay in.
static func _consider_switch(ctx: Dictionary, best_score: float, weather: String) -> int:
	var me: Dictionary = ctx.get("self", {})
	var foe: Dictionary = ctx.get("foe", {})
	var bench: Array = ctx.get("bench", [])
	if bench.is_empty():
		return -1

	# Only consider switching when the current matchup is genuinely poor: the
	# best move on offer is resisted/immune, or barely dents the target.
	var threat := _incoming_threat(foe, me, weather)
	if best_score > 35.0 and threat < 55.0:
		return -1

	var best_bench := -1
	var best_bench_score := best_score + SWITCH_MARGIN
	for i in bench.size():
		var candidate: Dictionary = bench[i]
		if Stats.is_fainted(candidate):
			continue
		var scores := score_moves(candidate, foe, weather)
		var s := -INF
		for v in scores:
			s = maxf(s, float(v))
		# Penalise sending something in that dies to the foe's best hit.
		var incoming := _incoming_threat(foe, candidate, weather)
		s -= incoming * 0.5
		if s > best_bench_score:
			best_bench_score = s
			best_bench = i
	return best_bench


## How hard `attacker`'s best move hits `target`, as a percentage of its HP.
static func _incoming_threat(attacker: Dictionary, target: Dictionary, weather: String) -> float:
	var worst := 0.0
	for move: Dictionary in (attacker.get("moves", []) as Array):
		if String(move.get("category", "status")) == "status":
			continue
		var eff := Damage.type_multiplier(String(move.get("type", "normal")),
			target.get("types", PackedStringArray()))
		if is_zero_approx(eff):
			continue
		var avg := Damage.average(attacker, target, move, {
			"weather": Abilities.weather_view(attacker, weather), "field_weather": weather})
		worst = maxf(worst, 100.0 * float(avg) / float(maxi(int(target.get("hp", 1)), 1)))
	return worst


## Which benched Pokemon to send out after a faint. Best matchup wins; -1 when
## the whole party is down.
static func choose_replacement(foe: Dictionary, bench: Array, weather: String = "") -> int:
	var best := -1
	var best_score := -INF
	for i in bench.size():
		var candidate: Dictionary = bench[i]
		if Stats.is_fainted(candidate):
			continue
		var s := -INF
		for v in score_moves(candidate, foe, weather):
			s = maxf(s, float(v))
		s -= _incoming_threat(foe, candidate, weather) * 0.5
		if s > best_score:
			best_score = s
			best = i
	return best
