class_name SpellSttConfig
extends RefCounted

## File-based STT setup checks (safe on the main game thread without loading gdvosk).

const TestEnvScript := preload("res://scripts/test/test_env.gd")

const GDEXTENSION_PATH := "res://addons/gdvosk/gdvosk.gdextension"
const GDEXTENSION_DISABLED_PATH := "res://addons/gdvosk/gdvosk.gdextension.disabled"
const SETUP_SCRIPT_HINT := (
	"Run make setup-voice from the repo root, then fully quit and reopen Godot."
)
const MODEL_SEARCH_PATHS: Array[String] = [
	"res://addons/gdvosk/model",
	"res://models/vosk",
	"user://vosk-model",
]


static func is_gdextension_disabled() -> bool:
	return (
		FileAccess.file_exists(GDEXTENSION_DISABLED_PATH)
		and not FileAccess.file_exists(GDEXTENSION_PATH)
	)


static func is_configured() -> bool:
	return FileAccess.file_exists(GDEXTENSION_PATH) and not find_model_path().is_empty()


static func get_setup_issue() -> String:
	if is_gdextension_disabled():
		return (
			"Speech recognition was disabled (gdvosk.gdextension renamed). "
			+ SETUP_SCRIPT_HINT
		)
	if not FileAccess.file_exists(GDEXTENSION_PATH):
		return (
			"Speech recognition not installed (gdvosk). "
			+ SETUP_SCRIPT_HINT
		)
	if find_model_path().is_empty():
		return (
			"Vosk speech model not found. "
			+ SETUP_SCRIPT_HINT
		)
	return ""


static func get_extension_load_issue(is_editor: bool) -> String:
	if is_editor:
		return (
			"gdvosk is not loaded in the Godot editor. "
			+ SETUP_SCRIPT_HINT
			+ " Fully quit Godot, reopen the project, and check the Output panel for GDExtension errors."
		)
	return (
		"gdvosk is not loaded. "
		+ SETUP_SCRIPT_HINT
		+ " Then restart the game."
	)


static func get_runtime_issue() -> String:
	var setup_issue := get_setup_issue()
	if not setup_issue.is_empty():
		return setup_issue
	if TestEnvScript.is_active():
		return ""
	if not GdvoskAdapter.is_available():
		return get_extension_load_issue(OS.has_feature("editor"))
	if not GdvoskAdapter.is_model_loaded():
		var loader_status: String = _speech_stt_loader_status()
		if loader_status.is_empty():
			return "Speech model is not loaded yet."
		return loader_status
	return ""


static func _speech_stt_loader_status() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	var loader: Node = tree.root.get_node_or_null("SpeechSttLoader")
	if loader == null:
		return ""
	return str(loader.call("get_status"))


static func find_model_path() -> String:
	return GdvoskAdapter.find_model_path()
