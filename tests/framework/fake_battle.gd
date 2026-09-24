extends Node
## Stand-in for the real battle scene, used by tests/test_scene_router.gd.
## SceneRouter calls `setup(Dictionary)` on whatever it instantiates; this records
## the call so the test can prove the payload arrived intact.

var received: Dictionary = {}
var setup_calls: int = 0


func setup(data: Dictionary) -> void:
	received = data
	setup_calls += 1
