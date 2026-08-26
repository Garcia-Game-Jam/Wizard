class_name GdvoskExtensionConfig
extends RefCounted

## Validates gdvosk.gdextension has editor library mappings so Play-in-Editor loads STT.

const GDEXTENSION_PATH := "res://addons/gdvosk/gdvosk.gdextension"

const REQUIRED_EDITOR_LIBRARY_KEYS: Array[String] = [
	"windows.editor.x86_64",
	"windows.editor.x86_32",
	"linux.editor.x86_64",
	"macos.editor",
]


static func get_missing_editor_library_keys(manifest_text: String) -> PackedStringArray:
	var missing := PackedStringArray()
	for key in REQUIRED_EDITOR_LIBRARY_KEYS:
		if not _manifest_has_library_key(manifest_text, key):
			missing.append(key)
	return missing


static func validate_manifest(manifest_text: String) -> String:
	var missing := get_missing_editor_library_keys(manifest_text)
	if missing.is_empty():
		return ""
	return (
		"gdvosk.gdextension is missing editor library entries required for Play-in-Editor: "
		+ ", ".join(missing)
		+ ". Re-run make setup-voice."
	)


static func validate_installed_manifest() -> String:
	if not FileAccess.file_exists(GDEXTENSION_PATH):
		return ""
	var file := FileAccess.open(GDEXTENSION_PATH, FileAccess.READ)
	if file == null:
		return "Could not read gdvosk.gdextension"
	return validate_manifest(file.get_as_text())


static func is_extension_loaded() -> bool:
	return ClassDB.class_exists("VoskRecognizer") and ClassDB.class_exists("VoskModel")


static func _manifest_has_library_key(manifest_text: String, key: String) -> bool:
	return manifest_text.contains("%s =" % key)
