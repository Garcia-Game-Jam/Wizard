class_name TestSettingsEditSession
extends RefCounted

const SessionScript := preload("res://scripts/ui/settings_edit_session.gd")
const StoreScript := preload("res://scripts/ui/keybinds/input_rebind_store.gd")
const CfgBackupScript := preload("res://tests/unit/settings_cfg_backup.gd")
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_BACKUP := "user://settings.cfg.friendslop_session_test_bak"


func run() -> int:
	var failures := 0
	var input_bak := StoreScript.snapshot_catalog()
	var volume_bak := SettingsManager.master_volume
	var had_cfg := _backup_settings_file()
	failures += _test_capture_is_clean()
	failures += _test_volume_and_bind_mark_dirty()
	failures += _test_revert_restores_volume_and_binds()
	failures += _test_save_replaces_last_save_copy()
	failures += _test_discard_does_not_write_cfg()
	failures += _test_reset_default_can_dirty()
	StoreScript.apply_snapshot(input_bak)
	SettingsManager.master_volume = volume_bak
	_restore_settings_file(had_cfg)
	return failures


func _p_key() -> Dictionary:
	return {
		"type": "key",
		"physical_keycode": KEY_P,
		"alt": false,
		"shift": false,
		"ctrl": false,
		"meta": false,
	}


func _test_capture_is_clean() -> int:
	var session := SessionScript.new()
	session.capture_last_save()
	if session.is_dirty():
		push_error("Fresh capture must not be dirty")
		return 1
	return 0


func _test_volume_and_bind_mark_dirty() -> int:
	var session := SessionScript.new()
	session.capture_last_save()
	SettingsManager.master_volume = 0.11
	if not session.is_dirty():
		push_error("Volume change must mark dirty")
		return 1
	session.revert()
	StoreScript.apply_packed("interact", _p_key())
	if not session.is_dirty():
		push_error("Bind change must mark dirty")
		return 1
	session.revert()
	return 0


func _test_revert_restores_volume_and_binds() -> int:
	var session := SessionScript.new()
	var interact_before := StoreScript.pack_action("interact")
	SettingsManager.master_volume = 0.55
	session.capture_last_save()
	SettingsManager.master_volume = 0.12
	StoreScript.apply_packed("interact", _p_key())
	session.revert()
	if not is_equal_approx(SettingsManager.master_volume, 0.55):
		push_error("Revert must restore volume from last-save copy")
		return 1
	if StoreScript.fingerprint_packed(StoreScript.pack_action("interact")) \
			!= StoreScript.fingerprint_packed(interact_before):
		push_error("Revert must restore InputMap from last-save copy")
		return 1
	if session.is_dirty():
		push_error("Revert must clear dirty")
		return 1
	return 0


func _test_save_replaces_last_save_copy() -> int:
	var session := SessionScript.new()
	SettingsManager.master_volume = 0.3
	session.capture_last_save()
	SettingsManager.master_volume = 0.6
	session.commit_save()
	if session.is_dirty():
		push_error("Save must refresh last-save copy")
		return 1
	SettingsManager.master_volume = 0.9
	session.revert()
	if not is_equal_approx(SettingsManager.master_volume, 0.6):
		push_error("Revert after Save must return to the saved value, not the open value")
		return 1
	return 0


func _test_discard_does_not_write_cfg() -> int:
	var session := SessionScript.new()
	SettingsManager.master_volume = 0.25
	session.commit_save()
	var before := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	SettingsManager.master_volume = 0.05
	session.revert()
	var result: Dictionary = session.request_exit()
	if not bool(result.get("should_close", false)):
		push_error("Clean discard/exit after revert should close")
		return 1
	var after := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	if before != after:
		push_error("Discard/revert must not rewrite settings.cfg")
		return 1
	return 0


func _test_reset_default_can_dirty() -> int:
	SettingsManager.snapshot_input_project_defaults()
	var session := SessionScript.new()
	StoreScript.apply_packed("interact", _p_key())
	session.capture_last_save()
	SettingsManager.reset_input_action_to_project_default("interact")
	var defaults := SettingsManager.get_input_project_defaults()
	var expected: Dictionary = defaults.get("interact", {})
	var last: Dictionary = session.last_save_copy().get("input", {}).get("interact", {})
	if StoreScript.fingerprint_packed(expected) == StoreScript.fingerprint_packed(last):
		return 0
	if not session.is_dirty():
		push_error("Reset to project default must dirty when it differs from last-save")
		return 1
	session.revert()
	return 0


func _backup_settings_file() -> bool:
	return CfgBackupScript.backup(SETTINGS_PATH, SETTINGS_BACKUP)


func _restore_settings_file(had_cfg: bool) -> void:
	CfgBackupScript.restore(SETTINGS_PATH, SETTINGS_BACKUP, had_cfg)
