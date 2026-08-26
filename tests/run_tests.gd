extends SceneTree

## Headless test entry point.
## Run: godot --headless --path . --script res://tests/run_tests.gd
## Offline only — no live Steam client or Steamworks session required.

const TestEnvScript := preload("res://scripts/test/test_env.gd")
const UNIT_LIST_PATH := "res://tests/test_suites.unit.txt"
const TREE_LIST_PATH := "res://tests/test_suites.tree.txt"


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await process_frame
	var multiplayer_api := root.get_multiplayer()
	if multiplayer_api.multiplayer_peer == null:
		multiplayer_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("Running Wizard unit tests (offline — no Steam required)...")
	if not _assert_steam_offline():
		_finish(1)
		return
	if not _assert_autoloads_ready():
		_finish(1)
		return

	var failures := 0
	failures += _run_suite_file(UNIT_LIST_PATH, false)
	failures += _run_suite_file(TREE_LIST_PATH, true)

	if failures == 0:
		print("All tests passed.")
		_finish(0)
	else:
		push_error("%d test(s) failed." % failures)
		_finish(1)


func _run_suite_file(list_path: String, needs_tree: bool) -> int:
	var file := FileAccess.open(list_path, FileAccess.READ)
	if file == null:
		push_error("Failed to open suite list: %s" % list_path)
		return 1

	var failures := 0
	while file.get_position() < file.get_length():
		var line := file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		failures += _run_suite(line, needs_tree)
	return failures


func _run_suite(path: String, needs_tree: bool = false) -> int:
	var script: GDScript = load(path) as GDScript
	if script == null:
		push_error("Failed to load test suite: %s" % path)
		return 1
	var suite: Object = script.new()
	if not suite.has_method("run"):
		push_error("Test suite missing run(): %s" % path)
		return 1
	if needs_tree:
		return suite.call("run", self)
	return suite.call("run")


func _assert_autoloads_ready() -> bool:
	if get_root().get_node_or_null("GameState") == null:
		push_error(
			"Autoloads are not ready. Close other Godot instances for this project "
			+ "and re-run tests."
		)
		return false
	return true


func _finish(exit_code: int) -> void:
	_prepare_exit()
	quit(exit_code)


func _prepare_exit() -> void:
	for child in root.get_children():
		if child.name == "SpellValidationRunner" and child.has_method("shutdown"):
			child.shutdown()
		elif child is CharacterBody3D:
			child.free()
	var steam_service := get_root().get_node_or_null("SteamService")
	if steam_service != null and steam_service.has_method("shutdown"):
		steam_service.shutdown()
	SpellValidationWorker.force_stt_in_tests = false
	if TestEnvScript.is_active():
		return
	GdvoskAdapter.unload_model()


func _assert_steam_offline() -> bool:
	if not TestEnvScript.is_active():
		return true
	var steam_service := get_root().get_node_or_null("SteamService")
	if steam_service == null:
		return true
	if steam_service.get("initialized"):
		push_error("Unit tests must not initialize Steam (check FRIEND_SLOP_TEST=1)")
		return false
	return true
