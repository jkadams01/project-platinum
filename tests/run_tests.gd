extends SceneTree
## Headless test runner.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --filter=save
##   godot --headless --path . --script res://tests/run_tests.gd -- --require-data
##
## Exit 0 = every check passed. Exit 1 = at least one check failed, no test files
## were found, or a test file failed to load. `push_error()` alone returns 0 on
## this engine, so failures are tracked here and passed to `quit()` explicitly.
##
## `--require-data` promotes pendings (checks skipped because `data/*.json` has
## not been generated yet) into failures. Use it in CI once the data stream lands.

const TEST_DIRS: Array = ["res://tests", "res://tests/cases"]
const FRAMEWORK := "res://tests/framework/test_case.gd"

var total_checks := 0
var failed_checks := 0
var total_pendings := 0
var failed_tests: Array[String] = []
var pending_notes: Array[String] = []
var require_data := false


func _initialize() -> void:
	# root is not really in the tree until one frame has elapsed: before it,
	# is_inside_tree() is false and _ready() has not fired on the autoloads.
	await process_frame

	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr("--filter=".length())
		elif arg == "--require-data":
			require_data = true

	var files := _discover()
	if files.is_empty():
		printerr("no test files found under %s" % ", ".join(PackedStringArray(TEST_DIRS)))
		quit(1)
		return

	print("Godot %s | %d test file(s)%s%s" % [
		Engine.get_version_info().string, files.size(),
		"" if filter.is_empty() else " | filter=" + filter,
		" | --require-data" if require_data else ""])
	print("============================================================")

	var ran := 0
	for path in files:
		if not filter.is_empty() and not path.contains(filter):
			continue
		await _run_file(path)
		ran += 1

	print("============================================================")
	if ran == 0:
		printerr("filter '%s' matched no test files" % filter)
		quit(1)
		return

	if total_pendings > 0:
		print("PENDING %d check(s) skipped -- dependency not built yet:" % total_pendings)
		for n in pending_notes:
			print("  ~ " + n)

	if failed_checks == 0 and not (require_data and total_pendings > 0):
		print("OK  %d checks passed in %d file(s)%s" % [
			total_checks, ran,
			", %d pending" % total_pendings if total_pendings > 0 else ""])
		quit(0)
		return

	if failed_checks > 0:
		printerr("FAILED  %d of %d checks failed across %d test(s)" % [
			failed_checks, total_checks, failed_tests.size()])
		for t in failed_tests:
			printerr("  - " + t)
	if require_data and total_pendings > 0:
		printerr("FAILED  %d pending check(s) with --require-data" % total_pendings)
	quit(1)


func _discover() -> PackedStringArray:
	var out := PackedStringArray()
	for dir_path: String in TEST_DIRS:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if not f.begins_with("test_") or not f.ends_with(".gd"):
				continue
			out.append(dir_path.path_join(f))
	out.sort()
	return out


func _run_file(path: String) -> void:
	var script: Script = load(path)
	if script == null:
		failed_checks += 1
		failed_tests.append(path + " (failed to load)")
		printerr("FAIL  could not load " + path)
		return
	var instance: RefCounted = script.new() if script.can_instantiate() else null
	if instance == null:
		failed_checks += 1
		failed_tests.append(path + " (failed to compile)")
		printerr("FAIL  could not instantiate " + path + " -- parse/compile error above")
		return
	if not instance.has_method("reset") or not instance.has_method("fails"):
		failed_checks += 1
		failed_tests.append(path + " (does not extend " + FRAMEWORK + ")")
		printerr("FAIL  %s does not extend %s" % [path, FRAMEWORK])
		return
	instance.set("tree", self)

	print("")
	print(path.get_file())

	var method_names: Array[String] = []
	for m: Dictionary in instance.get_method_list():
		var mname: String = m["name"]
		if mname.begins_with("test_") and not method_names.has(mname):
			method_names.append(mname)
	method_names.sort()

	for mname in method_names:
		instance.call("reset")
		instance.call("before_each")
		await instance.call(mname)
		instance.call("after_each")
		await process_frame          # let queue_free() land between tests

		total_checks += instance.call("checks")
		var fs: Array = instance.call("fails")
		var ps: Array = instance.call("pendings")
		total_pendings += ps.size()
		for p: String in ps:
			pending_notes.append("%s::%s  %s" % [path.get_file(), mname, p])

		if fs.is_empty():
			var suffix := ""
			if not ps.is_empty():
				suffix = ", %d pending" % ps.size()
			print("  ok   %s  (%d checks%s)" % [mname, instance.call("checks"), suffix])
		else:
			failed_checks += fs.size()
			failed_tests.append(path.get_file() + "::" + mname)
			printerr("  FAIL %s" % mname)
			for f: String in fs:
				printerr("       " + f)
