class_name TestInputRebind
extends RefCounted

const CatalogScript := preload("res://scripts/ui/keybinds/input_rebind_catalog.gd")
const StoreScript := preload("res://scripts/ui/keybinds/input_rebind_store.gd")
const CfgBackupScript := preload("res://tests/unit/settings_cfg_backup.gd")
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_BACKUP := "user://settings.cfg.friendslop_rebind_test_bak"


func run() -> int:
	var failures := 0
	var input_bak := StoreScript.snapshot_catalog()
	var had_cfg := _backup_settings_file()
	var volume_bak := SettingsManager.master_volume
	failures += _test_pack_unpack_key_and_mouse()
	failures += _test_unpack_ignores_junk()
	failures += _test_apply_replaces_only_that_action()
	failures += _test_reset_one_restores_project_default()
	failures += _test_reset_all_restores_project_defaults()
	failures += _test_conflict_scan()
	failures += _test_input_cfg_does_not_clobber_audio()
	failures += _test_catalog_actions()
	failures += _test_cfg_migrates_sprint_and_wand_raise()
	failures += _test_source_guards()
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


func _test_pack_unpack_key_and_mouse() -> int:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_P
	key.shift_pressed = true
	var packed_key := StoreScript.pack_event(key)
	var restored_key := StoreScript.unpack_event(packed_key) as InputEventKey
	if restored_key == null or restored_key.physical_keycode != KEY_P:
		push_error("Key pack/unpack lost physical_keycode")
		return 1
	if not restored_key.shift_pressed:
		push_error("Key pack/unpack lost shift")
		return 1
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	var packed_mouse := StoreScript.pack_event(mouse)
	var restored_mouse := StoreScript.unpack_event(packed_mouse) as InputEventMouseButton
	if restored_mouse == null or restored_mouse.button_index != MOUSE_BUTTON_MIDDLE:
		push_error("Mouse pack/unpack lost button_index")
		return 1
	return 0


func _test_unpack_ignores_junk() -> int:
	if StoreScript.unpack_event({}) != null:
		push_error("Empty dict must not unpack to an event")
		return 1
	if StoreScript.unpack_event({"type": "midi", "note": 60}) != null:
		push_error("Unknown type must be ignored")
		return 1
	return 0


func _test_apply_replaces_only_that_action() -> int:
	var jump_before := StoreScript.pack_action("jump")
	var dash_before := StoreScript.pack_action("dash")
	StoreScript.apply_packed("jump", _p_key())
	var jump_after := StoreScript.pack_action("jump")
	var dash_after := StoreScript.pack_action("dash")
	StoreScript.apply_packed("jump", jump_before)
	if StoreScript.fingerprint_packed(jump_after) != StoreScript.fingerprint_packed(_p_key()):
		push_error("apply_packed must set the action bind")
		return 1
	if StoreScript.fingerprint_packed(dash_after) != StoreScript.fingerprint_packed(dash_before):
		push_error("apply_packed must not change other actions")
		return 1
	return 0


func _test_reset_one_restores_project_default() -> int:
	SettingsManager.snapshot_input_project_defaults()
	var defaults := SettingsManager.get_input_project_defaults()
	StoreScript.apply_packed("interact", _p_key())
	SettingsManager.reset_input_action_to_project_default("interact")
	var after := StoreScript.pack_action("interact")
	var expected: Dictionary = defaults.get("interact", {})
	if StoreScript.fingerprint_packed(after) != StoreScript.fingerprint_packed(expected):
		push_error("Reset-one must restore the project default snapshot")
		return 1
	return 0


func _test_reset_all_restores_project_defaults() -> int:
	SettingsManager.snapshot_input_project_defaults()
	var defaults := SettingsManager.get_input_project_defaults()
	StoreScript.apply_packed("interact", _p_key())
	StoreScript.apply_packed("jump", _p_key())
	StoreScript.apply_snapshot(defaults)
	var interact_after := StoreScript.pack_action("interact")
	var jump_after := StoreScript.pack_action("jump")
	var interact_expected: Dictionary = defaults.get("interact", {})
	var jump_expected: Dictionary = defaults.get("jump", {})
	if StoreScript.fingerprint_packed(interact_after) != StoreScript.fingerprint_packed(
		interact_expected
	):
		push_error("Reset-all must restore interact to the project default")
		return 1
	if StoreScript.fingerprint_packed(jump_after) != StoreScript.fingerprint_packed(jump_expected):
		push_error("Reset-all must restore jump to the project default")
		return 1
	return 0


func _test_conflict_scan() -> int:
	var jump_before := StoreScript.pack_action("jump")
	var dash_before := StoreScript.pack_action("dash")
	StoreScript.apply_packed("jump", _p_key())
	StoreScript.apply_packed("dash", _p_key())
	var conflicts := StoreScript.conflict_action_names()
	StoreScript.apply_packed("jump", jump_before)
	StoreScript.apply_packed("dash", dash_before)
	if not conflicts.has("jump") or not conflicts.has("dash"):
		push_error("Shared binds must appear in the conflict list")
		return 1
	return 0


func _test_input_cfg_does_not_clobber_audio() -> int:
	SettingsManager.master_volume = 0.42
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", 0.42)
	cfg.set_value("input", "interact", _p_key())
	cfg.save(SETTINGS_PATH)
	SettingsManager.load_settings()
	if not is_equal_approx(SettingsManager.master_volume, 0.42):
		push_error("Loading [input] must not rewrite audio volume")
		return 1
	var interact := StoreScript.pack_action("interact")
	if int(interact.get("physical_keycode", 0)) != KEY_P:
		push_error("load_settings must apply packed [input] binds")
		return 1
	return 0


func _test_catalog_actions() -> int:
	var names := CatalogScript.action_names()
	var err := _catalog_error(names)
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _catalog_error(names: PackedStringArray) -> String:
	var err := ""
	var required := [
		"dash",
		"spell_capture",
		"spell_slot_1",
		"spell_slot_2",
		"spell_slot_3",
		"spell_slot_4",
		"hotbar_1",
		"hotbar_2",
		"hotbar_3",
		"hotbar_4",
	]
	for action in required:
		if not names.has(action):
			err = "Catalog missing %s" % action
			break
		if not InputMap.has_action(action):
			err = "InputMap missing catalog action %s" % action
			break
	if err.is_empty():
		for action in names:
			if not InputMap.has_action(action):
				err = "Catalog action %s is not in InputMap" % action
				break
	if err.is_empty() and (names.has("sprint") or names.has("wand_raise")):
		err = "Catalog must not list renamed sprint/wand_raise"
	if err.is_empty() and (names.has("spell_fire") or names.has("ui_cancel")):
		err = "Catalog must not list spell_fire or ui_cancel"
	if err.is_empty() and (names.has("fly_ascend") or names.has("fly_descend")):
		err = "Catalog must not list broom fly actions"
	if err.is_empty() and (InputMap.has_action("sprint") or InputMap.has_action("wand_raise")):
		err = "InputMap must not keep sprint/wand_raise after rename"
	return err


func _test_cfg_migrates_sprint_and_wand_raise() -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "sprint", _p_key())
	var mouse := {"type": "mouse", "button_index": MOUSE_BUTTON_XBUTTON1}
	cfg.set_value("input", "wand_raise", mouse)
	cfg.save(SETTINGS_PATH)
	SettingsManager.load_settings()
	var dash := StoreScript.pack_action("dash")
	var capture := StoreScript.pack_action("spell_capture")
	if StoreScript.fingerprint_packed(dash) != StoreScript.fingerprint_packed(_p_key()):
		push_error("sprint cfg key must apply onto dash")
		return 1
	if StoreScript.fingerprint_packed(capture) != StoreScript.fingerprint_packed(mouse):
		push_error("wand_raise cfg key must apply onto spell_capture")
		return 1
	return 0


func _test_source_guards() -> int:
	var player := FileAccess.get_file_as_string("res://scripts/characters/player.gd")
	var dash := FileAccess.get_file_as_string("res://scripts/characters/player_dash.gd")
	if player.find('is_action_pressed("spell_capture")') < 0:
		push_error("player.gd must listen for spell_capture")
		return 1
	if dash.find('is_action_just_pressed("dash")') < 0:
		push_error("player_dash.gd must dash on dash")
		return 1
	return 0


func _backup_settings_file() -> bool:
	return CfgBackupScript.backup(SETTINGS_PATH, SETTINGS_BACKUP)


func _restore_settings_file(had_cfg: bool) -> void:
	CfgBackupScript.restore(SETTINGS_PATH, SETTINGS_BACKUP, had_cfg)
