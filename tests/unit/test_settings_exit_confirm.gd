class_name TestSettingsExitConfirm
extends RefCounted

const SessionScript := preload("res://scripts/ui/settings_edit_session.gd")
const StoreScript := preload("res://scripts/ui/keybinds/input_rebind_store.gd")
const CfgBackupScript := preload("res://tests/unit/settings_cfg_backup.gd")
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_BACKUP := "user://settings.cfg.friendslop_exit_test_bak"


func run() -> int:
	var failures := 0
	var input_bak := StoreScript.snapshot_catalog()
	var volume_bak := SettingsManager.master_volume
	var had_cfg := _backup_settings_file()
	failures += _test_clean_exit_closes()
	failures += _test_dirty_first_exit_confirms()
	failures += _test_dirty_second_exit_reverts_without_save()
	failures += _test_save_and_revert_clear_confirm()
	failures += _test_edit_keeps_confirm_pending()
	StoreScript.apply_snapshot(input_bak)
	SettingsManager.master_volume = volume_bak
	_restore_settings_file(had_cfg)
	return failures


func _test_clean_exit_closes() -> int:
	var session := SessionScript.new()
	session.capture_last_save()
	var result: Dictionary = session.request_exit()
	if not bool(result.get("should_close", false)):
		push_error("Clean request_exit must close")
		return 1
	if bool(result.get("confirm_pending", true)):
		push_error("Clean request_exit must not confirm")
		return 1
	if session.is_dirty():
		push_error("Clean session must not need an Exit warning outline")
		return 1
	return 0


func _test_dirty_first_exit_confirms() -> int:
	var session := SessionScript.new()
	session.capture_last_save()
	SettingsManager.master_volume = 0.08
	if not session.is_dirty():
		push_error("Dirty session must report is_dirty for the red Exit outline")
		return 1
	var result: Dictionary = session.request_exit()
	if bool(result.get("should_close", false)):
		push_error("Dirty first request_exit must not close")
		return 1
	if not bool(result.get("confirm_pending", false)):
		push_error("Dirty first request_exit must set confirm pending")
		return 1
	if str(result.get("message", "")) != SessionScript.EXIT_CONFIRM_TEXT:
		push_error("Confirm message must be Exit Without Saving")
		return 1
	session.revert()
	return 0


func _test_dirty_second_exit_reverts_without_save() -> int:
	var session := SessionScript.new()
	SettingsManager.master_volume = 0.4
	session.commit_save()
	var before := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	SettingsManager.master_volume = 0.01
	session.request_exit()
	var result: Dictionary = session.request_exit()
	if not bool(result.get("should_close", false)):
		push_error("Second dirty Exit must close")
		return 1
	if not is_equal_approx(SettingsManager.master_volume, 0.4):
		push_error("Second dirty Exit must revert to last-save copy")
		return 1
	var after := FileAccess.get_file_as_bytes(SETTINGS_PATH)
	if before != after:
		push_error("Second dirty Exit must not write settings.cfg")
		return 1
	return 0


func _test_save_and_revert_clear_confirm() -> int:
	var session := SessionScript.new()
	session.capture_last_save()
	SettingsManager.master_volume = 0.07
	session.request_exit()
	if not session.is_exit_confirm_pending():
		push_error("Expected confirm pending before Save")
		return 1
	session.commit_save()
	if session.is_exit_confirm_pending():
		push_error("Save must clear Exit confirm")
		return 1
	SettingsManager.master_volume = 0.02
	session.request_exit()
	session.revert()
	if session.is_exit_confirm_pending():
		push_error("Revert must clear Exit confirm")
		return 1
	return 0


func _test_edit_keeps_confirm_pending() -> int:
	var session := SessionScript.new()
	session.capture_last_save()
	SettingsManager.master_volume = 0.09
	session.request_exit()
	SettingsManager.master_volume = 0.03
	if not session.is_exit_confirm_pending():
		push_error("Further edits must leave Exit confirm pending")
		return 1
	if not session.is_dirty():
		push_error("Further edits must stay dirty")
		return 1
	session.revert()
	return 0


func _backup_settings_file() -> bool:
	return CfgBackupScript.backup(SETTINGS_PATH, SETTINGS_BACKUP)


func _restore_settings_file(had_cfg: bool) -> void:
	CfgBackupScript.restore(SETTINGS_PATH, SETTINGS_BACKUP, had_cfg)
