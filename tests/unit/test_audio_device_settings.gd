class_name TestAudioDeviceSettings
extends RefCounted

## Covers the mic/device bugs: persist on close, menu populate must not wipe a
## saved device, resolve never remaps, and the broker keeps running while paused.
## Headless-safe — no real AudioStreamMicrophone / WASAPI required.

const MicCaptureBrokerScript := preload("res://scripts/voice/mic_capture_broker.gd")
const MicGainUtilScript := preload("res://scripts/voice/mic_gain_util.gd")
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_BACKUP := "user://settings.cfg.friendslop_audio_test_bak"


func run() -> int:
	var failures := 0
	var snap := _snapshot_audio()
	var had_cfg := _backup_settings_file()
	failures += _test_mic_gain_curve()
	failures += _test_devices_round_trip_config()
	failures += _test_legacy_mic_test_monitor_migrates()
	failures += _test_resolve_never_remaps_missing_device()
	failures += _test_missing_device_keeps_saved_preference()
	failures += _test_block_signals_prevents_populate_overwrite()
	failures += _test_settings_panel_close_persists_devices()
	failures += _test_settings_panel_live_preview_does_not_save()
	failures += _test_broker_remembers_device_before_stream_opens()
	failures += _test_broker_survives_tree_pause()
	failures += _test_broker_discards_with_queue_free()
	failures += _test_pause_menu_pauses_scene_tree()
	_restore_audio(snap)
	_restore_settings_file(had_cfg)
	return failures


func _snapshot_audio() -> Dictionary:
	return {
		"input_device": SettingsManager.input_device,
		"output_device": SettingsManager.output_device,
		"hear_myself": SettingsManager.hear_myself,
		"master_volume": SettingsManager.master_volume,
		"mic_volume": SettingsManager.mic_volume,
		"mic_muted": SettingsManager.mic_muted,
		"lobby_voice_default": SettingsManager.lobby_voice_default,
		"retry_count": SettingsManager._capture_device_retry_count,
		"retry_scheduled": SettingsManager._capture_device_retry_scheduled,
	}


func _restore_audio(snap: Dictionary) -> void:
	SettingsManager.input_device = str(snap.get("input_device", ""))
	SettingsManager.output_device = str(snap.get("output_device", ""))
	SettingsManager.hear_myself = bool(snap.get("hear_myself", false))
	SettingsManager.master_volume = float(snap.get("master_volume", 1.0))
	SettingsManager.mic_volume = float(snap.get("mic_volume", 1.0))
	SettingsManager.mic_muted = bool(snap.get("mic_muted", false))
	SettingsManager.lobby_voice_default = bool(snap.get("lobby_voice_default", true))
	SettingsManager._capture_device_retry_count = int(snap.get("retry_count", 0))
	SettingsManager._capture_device_retry_scheduled = bool(
		snap.get("retry_scheduled", false)
	)


func _test_mic_gain_curve() -> int:
	var prior := SettingsManager.mic_volume
	var problem := ""
	SettingsManager.mic_volume = 0.0
	if not is_equal_approx(MicGainUtilScript.from_settings(), 0.0):
		problem = "mic gain at dial 0 should be mute"
	else:
		SettingsManager.mic_volume = 1.0
		if not is_equal_approx(MicGainUtilScript.from_settings(), 1.0):
			problem = "mic gain at dial midpoint should be unity"
		else:
			SettingsManager.mic_volume = 1.5
			var mid_boost: float = MicGainUtilScript.from_settings()
			if mid_boost <= 2.0:
				problem = "mic gain at 150%% dial should exceed 2×, got %s" % mid_boost
			else:
				SettingsManager.mic_volume = 2.0
				if not is_equal_approx(
					MicGainUtilScript.from_settings(), SettingsManager.MIC_BOOST_CEILING
				):
					problem = "mic gain at max dial should hit MIC_BOOST_CEILING"
				elif absf(MicGainUtilScript.apply_sample(0.5)) <= 0.5:
					problem = "apply_sample under boost should raise mid samples"
	SettingsManager.mic_volume = prior
	if problem.is_empty():
		return 0
	push_error(problem)
	return 1


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


func _scene_tree() -> SceneTree:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return loop as SceneTree
	return null


## Saved mic/speaker names must survive save → clear → load.
func _test_devices_round_trip_config() -> int:
	SettingsManager.input_device = "FriendSlop Test Mic"
	SettingsManager.output_device = "FriendSlop Test Speakers"
	SettingsManager.hear_myself = true
	SettingsManager.save_settings()
	SettingsManager.input_device = ""
	SettingsManager.output_device = ""
	SettingsManager.hear_myself = false
	SettingsManager.load_settings()
	var issue := ""
	if SettingsManager.input_device != "FriendSlop Test Mic":
		issue = "Expected input_device to round-trip through settings.cfg"
	elif SettingsManager.output_device != "FriendSlop Test Speakers":
		issue = "Expected output_device to round-trip through settings.cfg"
	elif not SettingsManager.hear_myself:
		issue = "Expected hear_myself to round-trip through settings.cfg"
	else:
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) != OK:
			issue = "Expected settings.cfg to exist after save_settings"
		elif not cfg.has_section_key("audio", "input_device"):
			issue = "settings.cfg must write audio/input_device"
		elif not cfg.has_section_key("audio", "output_device"):
			issue = "settings.cfg must write audio/output_device"
		elif not cfg.has_section_key("audio", "hear_myself"):
			issue = "settings.cfg must write audio/hear_myself"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


## Short-lived mic_test_monitor key must still load into hear_myself.
func _test_legacy_mic_test_monitor_migrates() -> int:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "window_width", SettingsManager.window_width)
	cfg.set_value("display", "window_height", SettingsManager.window_height)
	cfg.set_value("display", "fullscreen", SettingsManager.fullscreen)
	cfg.set_value("audio", "mic_test_monitor", true)
	cfg.save(SETTINGS_PATH)
	SettingsManager.hear_myself = false
	SettingsManager.load_settings()
	if SettingsManager.hear_myself:
		return 0
	push_error("Expected legacy audio/mic_test_monitor to migrate into hear_myself")
	return 1


## Unknown saved names must resolve to "" (retry), never another mic.
func _test_resolve_never_remaps_missing_device() -> int:
	SettingsManager.input_device = "FriendSlop Missing Capture Device"
	var resolved: String = SettingsManager.call("_resolve_capture_input_device")
	var src := FileAccess.get_file_as_string("res://scripts/settings_manager.gd")
	var issue := ""
	if not resolved.is_empty():
		issue = (
			"Missing saved input must resolve to empty (retry), not remap to '%s'"
			% resolved
		)
	elif src.find("Never remap") < 0:
		issue = "SettingsManager must document never-remap resolve policy"
	elif src.find("_schedule_capture_device_retry") < 0:
		issue = "Missing capture devices must schedule a retry, not pick another mic"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


## apply_audio_settings must keep the saved preference when the device is absent.
func _test_missing_device_keeps_saved_preference() -> int:
	var saved := "FriendSlop Missing Capture Device"
	SettingsManager.input_device = saved
	SettingsManager._capture_device_retry_count = 0
	SettingsManager._capture_device_retry_scheduled = false
	SettingsManager.apply_audio_settings()
	var kept := SettingsManager.input_device == saved
	var applied := SettingsManager._applied_input_device
	SettingsManager._capture_device_retry_scheduled = false
	SettingsManager._capture_device_retry_count = 0
	if kept and applied == saved:
		return 0
	push_error(
		"apply_audio_settings must keep a missing saved input preference for retry"
	)
	return 1


## OptionButton populate used to emit item_selected(0) and wipe the saved mic.
func _test_block_signals_prevents_populate_overwrite() -> int:
	var prev := SettingsManager.input_device
	SettingsManager.input_device = "FriendSlop Saved Mic"
	var option := OptionButton.new()
	var wiped := {"n": 0}
	option.item_selected.connect(
		func(_index: int) -> void:
			## Same write the live settings handler performs on System Default.
			SettingsManager.input_device = ""
			wiped["n"] = int(wiped["n"]) + 1
	)
	option.add_item("System Default")
	option.add_item("Default")
	option.set_block_signals(true)
	option.select(0)
	option.item_selected.emit(0)
	option.set_block_signals(false)
	var blocked_ok := (
		SettingsManager.input_device == "FriendSlop Saved Mic" and int(wiped["n"]) == 0
	)
	option.item_selected.emit(0)
	var unblocked_wipes := SettingsManager.input_device.is_empty() and int(wiped["n"]) > 0
	option.free()
	SettingsManager.input_device = prev
	var panel_src := FileAccess.get_file_as_string("res://scripts/ui/settings_panel.gd")
	var issue := ""
	if not blocked_ok:
		issue = "Populate must block OptionButton signals so select(0) cannot wipe devices"
	elif not unblocked_wipes:
		issue = "Expected unblocked item_selected to clear the saved mic preference"
	elif panel_src.find("set_block_signals(true)") < 0:
		issue = "SettingsPanel must call set_block_signals around _select_device"
	elif panel_src.find(
		"_select_device(_input_device_option, SettingsManager.input_device)"
	) < 0:
		issue = "SettingsPanel must restore SettingsManager.input_device on populate"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


## Devices chosen in the menu must hit disk only on Save, not Exit.
func _test_settings_panel_close_persists_devices() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/ui/settings_panel.gd")
	var close_at := src.find("func close_panel")
	var save_fn := src.find("func _on_save_pressed")
	var issue := ""
	if close_at < 0:
		issue = "SettingsPanel must keep close_panel() for PauseMenu Esc"
	elif src.find("func _on_exit_pressed") < 0:
		issue = "SettingsPanel must route Exit through _on_exit_pressed"
	elif save_fn < 0:
		issue = "SettingsPanel must have _on_save_pressed"
	else:
		var save_body := _gd_func_body(src, "func _on_save_pressed")
		var close_body := _gd_func_body(src, "func close_panel")
		var exit_body := _gd_func_body(src, "func _on_exit_pressed")
		var session_src := FileAccess.get_file_as_string(
			"res://scripts/ui/settings_edit_session.gd"
		)
		if save_body.find("commit_save") < 0:
			issue = "Save must commit through SettingsEditSession"
		elif session_src.find("SettingsManager.save_settings()") < 0:
			issue = "Edit session Save must call SettingsManager.save_settings()"
		elif close_body.find("save_settings") >= 0 or exit_body.find("save_settings") >= 0:
			issue = "close_panel / Exit must not write settings.cfg"
		elif src.find("Persisted to settings.cfg only when Save is pressed") < 0:
			issue = "Live device handlers must document Save-only persistence"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


## Live preview may apply audio, but must not write settings.cfg.
func _test_settings_panel_live_preview_does_not_save() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/ui/settings_panel.gd")
	var issue := ""
	var input_body := _gd_func_body(src, "func _on_input_device_selected")
	var output_body := _gd_func_body(src, "func _on_output_device_selected")
	var apply_body := _gd_func_body(src, "func _apply_to_manager")
	if input_body.is_empty() or output_body.is_empty() or apply_body.is_empty():
		issue = "SettingsPanel missing device selection / apply helpers"
	elif input_body.find("save_settings") >= 0:
		issue = "_on_input_device_selected must not save_settings (Save persists)"
	elif output_body.find("save_settings") >= 0:
		issue = "_on_output_device_selected must not save_settings (Save persists)"
	elif apply_body.find("save_settings") >= 0:
		issue = "_apply_to_manager must not save_settings (Save owns persist)"
	elif input_body.find("apply_audio_settings") < 0:
		issue = "Live input preview must still call apply_audio_settings()"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


func _gd_func_body(src: String, signature: String) -> String:
	var start := src.find(signature)
	if start < 0:
		return ""
	var nxt := src.find("\nfunc ", start + 1)
	if nxt < 0:
		return src.substr(start)
	return src.substr(start, nxt - start)


## Preference is stored even before a capture stream exists.
func _test_broker_remembers_device_before_stream_opens() -> int:
	var broker: Node = MicCaptureBrokerScript.new()
	var first: bool = broker.call("set_input_device_from_settings", "FriendSlop Mic A")
	var second: bool = broker.call("set_input_device_from_settings", "FriendSlop Mic A")
	var changed: bool = broker.call("set_input_device_from_settings", "FriendSlop Mic B")
	var requested: String = str(broker.get("_requested_input_device"))
	broker.free()
	var issue := ""
	if first:
		issue = "set_input_device_from_settings must return false when no stream is open"
	elif second:
		issue = "Identical device selection must be idempotent"
	elif changed:
		issue = "Device preference change without an open stream must not restart"
	elif requested != "FriendSlop Mic B":
		issue = "Broker must remember the latest Settings device before opening"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


## Pause menu sets get_tree().paused; broker must keep draining under ALWAYS.
func _test_broker_survives_tree_pause() -> int:
	var tree := _scene_tree()
	if tree == null:
		push_error("Expected a live SceneTree for pause coverage")
		return 1
	var broker: Node = MicCaptureBrokerScript.new()
	tree.root.add_child(broker)
	var mode_ok := broker.process_mode == Node.PROCESS_MODE_ALWAYS
	var was_paused := tree.paused
	tree.paused = true
	var processes_while_paused := broker.can_process()
	tree.paused = was_paused
	tree.root.remove_child(broker)
	broker.free()
	var issue := ""
	if not mode_ok:
		issue = "MicCaptureBroker._ready must set PROCESS_MODE_ALWAYS"
	elif not processes_while_paused:
		issue = "MicCaptureBroker must keep processing while the scene tree is paused"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


## Outgoing Mic players must queue_free after rename so reopen can reuse "Mic".
func _test_broker_discards_with_queue_free() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/voice/mic_capture_broker.gd")
	var discard_at := src.find("func _discard_mic_player")
	var issue := ""
	if discard_at < 0:
		issue = "MicCaptureBroker must expose _discard_mic_player()"
	else:
		var body := src.substr(discard_at, 400)
		if body.find("MicClosing") < 0:
			issue = "Discarded mic players must rename to MicClosing"
		elif body.find("queue_free()") < 0:
			issue = "Discarded mic players must queue_free (not free) for the audio thread"
		elif body.find("\n\toutgoing.free()") >= 0 or body.find("\n\t_mic_player.free()") >= 0:
			issue = "Mic discard must not free() the player immediately"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1


## Documents why PROCESS_MODE_ALWAYS matters for the broker.
func _test_pause_menu_pauses_scene_tree() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/ui/pause_menu.gd")
	var issue := ""
	if src.find("get_tree().paused = true") < 0:
		issue = "PauseMenu must pause the scene tree"
	elif src.find("PROCESS_MODE_ALWAYS") < 0:
		issue = "PauseMenu itself must use PROCESS_MODE_ALWAYS"
	if issue.is_empty():
		return 0
	push_error(issue)
	return 1
