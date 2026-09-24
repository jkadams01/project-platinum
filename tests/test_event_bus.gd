extends "res://tests/framework/test_case.gd"
## EventBus is the cross-stream contract. These tests fail if a signal is renamed
## or loses a parameter, which is exactly when every other stream would break.

## name -> ordered argument names. Every entry is depended on by another stream.
const REQUIRED: Dictionary = {
	"battle_started": ["setup"],
	"battle_ended": ["result"],
	"exp_capped": ["pokemon", "cap"],
	"badge_earned": ["badge"],
	"level_cap_raised": ["old_cap", "new_cap", "index"],
	"flag_set": ["flag", "value"],
	"map_changed": ["map_id", "spawn"],
	"traversal_used": ["verb"],
	"player_moved": ["cell"],
	"encounter_triggered": ["zone", "level_range"],
	"dialogue_requested": ["lines"],
	"game_saved": ["slot", "ok"],
	"game_loaded": ["slot", "ok"],
	"party_changed": [],
}


func before_each() -> void:
	EventBus.disconnect_all()


func after_each() -> void:
	EventBus.disconnect_all()


func test_every_required_signal_exists_with_the_right_arguments() -> void:
	var declared: Dictionary = {}
	for s: Dictionary in EventBus.get_script().get_script_signal_list():
		var names: Array = []
		for a: Dictionary in (s["args"] as Array):
			names.append(String(a["name"]))
		declared[String(s["name"])] = names

	for sig_name: String in REQUIRED:
		if not declared.has(sig_name):
			fail("EventBus is missing the signal '%s'" % sig_name)
			continue
		eq(declared[sig_name], REQUIRED[sig_name], "signature of %s" % sig_name)


func test_signals_actually_carry_their_payloads() -> void:
	var got: Array = []
	EventBus.exp_capped.connect(func(p: Dictionary, c: int) -> void: got.append([p, c]))
	EventBus.traversal_used.connect(func(v: StringName) -> void: got.append(v))
	EventBus.map_changed.connect(func(m: StringName, s: Vector2i) -> void: got.append([m, s]))

	EventBus.exp_capped.emit({"species": 25}, 14)
	EventBus.traversal_used.emit(&"surf")
	EventBus.map_changed.emit(&"route_205", Vector2i(3, 40))

	eq(got.size(), 3, "three payloads")
	eq(int((got[0][0] as Dictionary)["species"]), 25, "exp_capped pokemon")
	eq(got[0][1], 14, "exp_capped cap")
	eq(got[1], &"surf", "traversal verb")
	eq(got[2], [&"route_205", Vector2i(3, 40)], "map + spawn")


func test_disconnect_all_clears_listeners_but_not_engine_wiring() -> void:
	var hits := [0]
	EventBus.badge_earned.connect(func(_b: StringName) -> void: hits[0] += 1)
	EventBus.badge_earned.emit(&"coal")
	eq(hits[0], 1, "connected")
	EventBus.disconnect_all()
	EventBus.badge_earned.emit(&"coal")
	eq(hits[0], 1, "disconnected")
	# the bus itself is still a live node in the tree
	is_true(EventBus.is_inside_tree(), "EventBus survived disconnect_all")
	is_true(is_instance_valid(EventBus), "still valid")
