class_name TestSettingsDisplay
extends RefCounted

## Display save: first run is native; a fitting save is kept; an oversized save
## from another monitor is rewritten to native.

const DisplayResolutionPresetsScript := preload("res://scripts/ui/display_resolution_presets.gd")
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_BACKUP := "user://settings.cfg.friendslop_display_test_bak"


func run() -> int:
	var failures := 0
	var snap := _snapshot_display()
	var had_cfg := _backup_settings_file()
	failures += _test_first_run_uses_native_without_writing()
	failures += _test_fitting_save_is_kept()
	failures += _test_oversized_save_is_rewritten_to_native()
	_restore_display(snap)
	_restore_settings_file(had_cfg)
	return failures


func _snapshot_display() -> Dictionary:
	return {
		"window_width": SettingsManager.window_width,
		"window_height": SettingsManager.window_height,
		"fullscreen": SettingsManager.fullscreen,
	}


func _restore_display(snap: Dictionary) -> void:
	SettingsManager.window_width = int(snap.get("window_width", 1920))
	SettingsManager.window_height = int(snap.get("window_height", 1080))
	SettingsManager.fullscreen = bool(snap.get("fullscreen", false))


func _backup_settings_file() -> bool:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return false
	var bytes := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	var out := FileAccess.open(SETTINGS_BACKUP, FileAccess.WRITE)
	if out == null:
		return false
	out.store_buffer(bytes)
	out.close()
	return true


func _restore_settings_file(had_cfg: bool) -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	if had_cfg and FileAccess.file_exists(SETTINGS_BACKUP):
		var bytes := FileAccess.get_file_as_bytes(SETTINGS_BACKUP)
		var out := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if out != null:
			out.store_buffer(bytes)
			out.close()
		DirAccess.remove_absolute(SETTINGS_BACKUP)
	elif FileAccess.file_exists(SETTINGS_BACKUP):
		DirAccess.remove_absolute(SETTINGS_BACKUP)


func _native() -> Vector2i:
	return DisplayResolutionPresetsScript.get_default_monitor_size()


func _write_display_cfg(size: Vector2i) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "window_width", size.x)
	cfg.set_value("display", "window_height", size.y)
	cfg.set_value("display", "fullscreen", false)
	cfg.save(SETTINGS_PATH)


func _test_first_run_uses_native_without_writing() -> int:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	SettingsManager.window_width = 1280
	SettingsManager.window_height = 720
	SettingsManager.load_settings()
	var native := _native()
	var issue := ""
	if SettingsManager.window_width != native.x or SettingsManager.window_height != native.y:
		issue = "Expected first run to use native %s, got %dx%d" % [
			str(native), SettingsManager.window_width, SettingsManager.window_height
		]
	elif FileAccess.file_exists(SETTINGS_PATH):
		issue = "Expected first run not to write settings.cfg"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


func _test_fitting_save_is_kept() -> int:
	var saved := Vector2i(1280, 720)
	if not DisplayResolutionPresetsScript.is_viable_on_display(saved, _native()):
		return 0
	_write_display_cfg(saved)
	SettingsManager.window_width = 1920
	SettingsManager.window_height = 1080
	SettingsManager.load_settings()
	var issue := ""
	if SettingsManager.window_width != saved.x or SettingsManager.window_height != saved.y:
		issue = "Expected a fitting save to be kept"
	else:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) != OK:
			issue = "Expected settings.cfg to remain after a fitting load"
		elif int(cfg.get_value("display", "window_width", 0)) != saved.x:
			issue = "Expected a fitting save not to be rewritten"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


func _test_oversized_save_is_rewritten_to_native() -> int:
	var native := _native()
	var oversized := DisplayResolutionPresetsScript.UHD_4K
	if DisplayResolutionPresetsScript.is_viable_on_display(oversized, native):
		## Native already fits 4K; oversized rewrite is covered by
		## resolve_saved_window_size unit tests. Do not invent a non-preset size.
		return 0
	_write_display_cfg(oversized)
	SettingsManager.load_settings()
	var issue := ""
	if SettingsManager.window_width != native.x or SettingsManager.window_height != native.y:
		issue = "Expected an oversized save to load as native %s, got %dx%d" % [
			str(native), SettingsManager.window_width, SettingsManager.window_height
		]
	else:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) != OK:
			issue = "Expected an oversized save to be rewritten"
		elif int(cfg.get_value("display", "window_width", 0)) != native.x:
			issue = "Expected settings.cfg window_width to be overwritten to native"
		elif int(cfg.get_value("display", "window_height", 0)) != native.y:
			issue = "Expected settings.cfg window_height to be overwritten to native"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1
