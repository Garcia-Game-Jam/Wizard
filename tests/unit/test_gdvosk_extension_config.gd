class_name TestGdvoskExtensionConfig
extends RefCounted

const ConfigScript := preload("res://scripts/spells/gdvosk_extension_config.gd")
const SpellSttConfigScript := preload("res://scripts/spells/spell_stt_config.gd")

const UPSTREAM_MANIFEST := """
windows.debug.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d.dll"
windows.release.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk.dll"
linux.debug.x86_64 = "res://addons/gdvosk/lib/linux/x86_64/libgdvosk-d.so"
macos.debug = "res://addons/gdvosk/lib/macos/universal/libgdvosk-d.dylib"
"""

const PATCHED_MANIFEST := """
windows.debug.x86_32 = "res://addons/gdvosk/lib/windows/x86_32/libgdvosk-d.dll"
windows.editor.x86_32 = "res://addons/gdvosk/lib/windows/x86_32/libgdvosk-d.dll"
windows.debug.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d.dll"
windows.editor.x86_64 = "res://addons/gdvosk/lib/windows/x86_64/libgdvosk-d.dll"
linux.debug.x86_64 = "res://addons/gdvosk/lib/linux/x86_64/libgdvosk-d.so"
linux.editor.x86_64 = "res://addons/gdvosk/lib/linux/x86_64/libgdvosk-d.so"
macos.debug = "res://addons/gdvosk/lib/macos/universal/libgdvosk-d.dylib"
macos.editor = "res://addons/gdvosk/lib/macos/universal/libgdvosk-d.dylib"
"""


func run() -> int:
	var failures := 0
	failures += _test_upstream_manifest_missing_editor_entries()
	failures += _test_patched_manifest_passes()
	failures += _test_installed_manifest_when_present()
	failures += _test_regression_editor_keys_prevent_play_in_editor_load()
	failures += _test_runtime_loaded_implies_empty_runtime_issue()
	return failures


func _test_upstream_manifest_missing_editor_entries() -> int:
	var issue := ConfigScript.validate_manifest(UPSTREAM_MANIFEST)
	if issue.is_empty():
		push_error("Expected upstream gdvosk manifest to fail editor-entry validation")
		return 1
	if not issue.contains("windows.editor.x86_64"):
		push_error("Expected validation issue to mention missing editor keys")
		return 1
	return 0


func _test_patched_manifest_passes() -> int:
	var issue := ConfigScript.validate_manifest(PATCHED_MANIFEST)
	if not issue.is_empty():
		push_error("Expected patched manifest to pass validation, got: %s" % issue)
		return 1
	return 0


func _test_installed_manifest_when_present() -> int:
	if not FileAccess.file_exists(ConfigScript.GDEXTENSION_PATH):
		return 0
	var issue := ConfigScript.validate_installed_manifest()
	if not issue.is_empty():
		push_error("Installed gdvosk.gdextension failed validation: %s" % issue)
		return 1
	return 0


func _test_regression_editor_keys_prevent_play_in_editor_load() -> int:
	# Regression: missing windows.editor.* entries meant Play-in-Editor never loaded
	# VoskRecognizer, so casts failed in SpellCastingSession._try_fail_missing_stt().
	var issue := ConfigScript.validate_manifest(UPSTREAM_MANIFEST)
	if issue.is_empty():
		push_error("Expected upstream manifest to fail validation")
		return 1
	var editor_stt_issue := SpellSttConfigScript.get_extension_load_issue(true)
	if not editor_stt_issue.contains("gdvosk is not loaded in the Godot editor"):
		push_error(
			"Expected editor STT preflight guidance when gdvosk fails to load, got: %s"
			% editor_stt_issue
		)
		return 1
	return 0


func _test_runtime_loaded_implies_empty_runtime_issue() -> int:
	if not ConfigScript.is_extension_loaded():
		return 0
	if not SpellSttConfigScript.is_configured():
		return 0
	var issue := SpellSttConfigScript.get_runtime_issue()
	if not issue.is_empty():
		push_error(
			"Expected no runtime STT issue when gdvosk is loaded and configured, got: %s"
			% issue
		)
		return 1
	return 0
