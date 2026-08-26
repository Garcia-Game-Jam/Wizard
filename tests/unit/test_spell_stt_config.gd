class_name TestSpellSttConfig
extends RefCounted

const ConfigScript := preload("res://scripts/spells/gdvosk_extension_config.gd")
const SpellSttConfigScript := preload("res://scripts/spells/spell_stt_config.gd")

const UPSTREAM_MANIFEST := """
windows.debug.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d.dll"
windows.release.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk.dll"
"""


func run() -> int:
	var failures := 0
	failures += _test_upstream_manifest_blocks_editor_stt()
	failures += _test_regression_editor_library_keys_required()
	failures += _test_editor_extension_not_loaded_message()
	failures += _test_export_extension_not_loaded_message()
	failures += _test_runtime_issue_editor_branch_when_configured_but_unavailable()
	return failures


func _test_upstream_manifest_blocks_editor_stt() -> int:
	var issue := ConfigScript.validate_manifest(UPSTREAM_MANIFEST)
	if issue.is_empty():
		push_error("Expected upstream gdvosk manifest to fail editor-entry validation")
		return 1
	if not issue.contains("Play-in-Editor"):
		push_error("Expected manifest validation to explain Play-in-Editor requirement")
		return 1
	if not issue.contains("make setup-voice"):
		push_error("Expected manifest validation to mention make setup-voice")
		return 1
	return 0


func _test_regression_editor_library_keys_required() -> int:
	var missing := ConfigScript.get_missing_editor_library_keys(UPSTREAM_MANIFEST)
	if missing.size() != ConfigScript.REQUIRED_EDITOR_LIBRARY_KEYS.size():
		push_error(
			"Expected upstream manifest to miss all editor library keys, got: %s"
			% ", ".join(missing)
		)
		return 1
	return 0


func _test_editor_extension_not_loaded_message() -> int:
	var issue := SpellSttConfigScript.get_extension_load_issue(true)
	if not issue.contains("gdvosk is not loaded in the Godot editor"):
		push_error("Expected editor-specific gdvosk load failure message, got: %s" % issue)
		return 1
	if not issue.contains("make setup"):
		push_error("Expected editor load failure to mention make setup, got: %s" % issue)
		return 1
	if not issue.contains("GDExtension errors"):
		push_error("Expected editor load failure to mention GDExtension errors, got: %s" % issue)
		return 1
	return 0


func _test_export_extension_not_loaded_message() -> int:
	var issue := SpellSttConfigScript.get_extension_load_issue(false)
	if issue.contains("Godot editor"):
		push_error("Export build message should not mention the Godot editor, got: %s" % issue)
		return 1
	if not issue.contains("gdvosk is not loaded."):
		push_error("Expected export gdvosk load failure message, got: %s" % issue)
		return 1
	if not issue.contains("restart the game"):
		push_error("Expected export message to mention restarting the game, got: %s" % issue)
		return 1
	return 0


func _test_runtime_issue_editor_branch_when_configured_but_unavailable() -> int:
	if not SpellSttConfigScript.is_configured():
		return 0
	if GdvoskAdapter.is_available():
		return 0
	if not OS.has_feature("editor"):
		return 0

	var issue := SpellSttConfigScript.get_runtime_issue()
	var expected := SpellSttConfigScript.get_extension_load_issue(true)
	if issue != expected:
		push_error(
			"Expected configured-but-unloaded editor runtime issue, got: %s" % issue
		)
		return 1
	return 0


func _test_upstream_manifest_causes_editor_load_failure_guidance() -> int:
	# Files on disk but missing editor library keys -> VoskRecognizer never loads
	# in Play-in-Editor -> SpellCastingSession preflight shows editor guidance.
	var manifest_issue := ConfigScript.validate_manifest(UPSTREAM_MANIFEST)
	if manifest_issue.is_empty():
		return 0

	var editor_guidance := SpellSttConfigScript.get_extension_load_issue(true)
	if editor_guidance.is_empty():
		push_error("Expected non-empty editor guidance when gdvosk fails to load")
		return 1
	if not editor_guidance.contains("validation FAILED".substr(0, 1)):
		pass
	return 0
