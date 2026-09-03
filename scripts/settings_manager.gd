extends Node

## Loads, applies, and persists player settings to user://settings.cfg.

signal settings_applied

const DisplayResolutionPresetsScript := preload("res://scripts/ui/display_resolution_presets.gd")
const MicCaptureBrokerScript := preload("res://scripts/voice/mic_capture_broker.gd")
const MicGainUtilScript := preload("res://scripts/voice/mic_gain_util.gd")
const InputRebindCatalogScript := preload("res://scripts/ui/keybinds/input_rebind_catalog.gd")
const InputRebindStoreScript := preload("res://scripts/ui/keybinds/input_rebind_store.gd")
const LevelCatalogScript := preload("res://scripts/arena/level_catalog.gd")

const INPUT_KEY_MIGRATE := {
	"sprint": "dash",
	"wand_raise": "spell_capture",
}

const SETTINGS_PATH := "user://settings.cfg"
const MIC_BUS_NAME := "MicCapture"
## Slider range: 0 = mute, 1.0 = unity (midpoint), MIC_VOLUME_MAX = max dial.
const MIC_VOLUME_MAX := 2.0
## Actual linear gain at the right end of the dial (midpoint stays 1×).
## 2× was too subtle in mic-test hearback; ~5× (~14 dB) is clearly audible.
const MIC_BOOST_CEILING := 5.0
const CAPTURE_DEVICE_RETRY_MAX := 20
const CAPTURE_DEVICE_RETRY_SEC := 0.25

var window_width: int = DisplayResolutionPresetsScript.DEFAULT_SIZE.x
var window_height: int = DisplayResolutionPresetsScript.DEFAULT_SIZE.y
## When true, borderless fullscreen; resolution sets content scale + 3D render scale.
var fullscreen: bool = false
var master_volume: float = 1.0
var mic_volume: float = 1.0
var mic_muted: bool = false
var input_device: String = ""
var output_device: String = ""
## Hear local mic through speakers during voice chat (and mic test).
var hear_myself: bool = false
var crosshair_color: Color = Color(1.0, 1.0, 1.0)
var crosshair_opacity: float = 0.92
var crosshair_thickness: float = 1.75
var crosshair_show_outer: bool = true
var crosshair_show_dot: bool = true
var dev_solo_role: int = GameState.PlayerRole.APPRENTICE
var lobby_voice_default: bool = true
var dev_allow_any_lobby_size: bool = false
## When true, start_game() rolls the level at random (LevelCatalog.random_id()) —
## a level pins both its map and its encounter sequence. When false, it uses
## dev_selected_level_id instead.
var dev_random_level: bool = true
var dev_selected_level_id: String = ""
## When true, netfox's own logger is Debug (tree dumps, identity IDs). Off = Warning.
var netfox_debug_logs: bool = false:
	set(value):
		netfox_debug_logs = value
		_apply_netfox_logging()
## When true, NetDiag writes a per-frame netcode/CPU capture during matches.
var net_diag_capture: bool = false:
	set(value):
		net_diag_capture = value
		_apply_net_diag()

var _mic_testing: bool = false
var _voice_meter_active: bool = false
## Last input_device preference string (UI), and last WASAPI device we opened.
var _applied_input_device: String = ""
var _opened_capture_device: String = ""
var _capture_device_retry_count: int = 0
var _capture_device_retry_scheduled: bool = false
## Catalog action -> packed event from project.godot, captured before user cfg.
var _input_project_defaults: Dictionary = {}


func _ready() -> void:
	_ensure_mic_bus()
	snapshot_input_project_defaults()
	load_settings()
	apply_audio_settings()
	apply_display_settings()
	_apply_netfox_logging()
	_apply_net_diag()


func get_resolution_presets() -> Array[Vector2i]:
	return DisplayResolutionPresetsScript.build_presets(Vector2i(window_width, window_height))


func set_window_resolution_preset_index(index: int) -> void:
	var current := Vector2i(window_width, window_height)
	var size := DisplayResolutionPresetsScript.get_preset(index, current)
	window_width = size.x
	window_height = size.y


func get_window_resolution_preset_index() -> int:
	var current := Vector2i(window_width, window_height)
	return DisplayResolutionPresetsScript.find_preset_index(current, current)


func is_running_embedded_in_editor() -> bool:
	return Engine.is_embedded_in_editor()


func apply_display_settings() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	call_deferred("_deferred_apply_display_settings")


func _deferred_apply_display_settings() -> void:
	var window := get_tree().root as Window
	if window == null:
		return
	var target := Vector2i(window_width, window_height)
	if Engine.is_embedded_in_editor():
		_apply_embedded_content_scale(window)
		return
	DisplayServer.window_set_min_size(Vector2i(640, 360))
	if fullscreen:
		_apply_fullscreen(window, target)
	else:
		_apply_windowed(window, target)


func _apply_embedded_content_scale(window: Window) -> void:
	## Game tab owns the window; still apply UI layout and 3D render scale.
	var chosen := _chosen_resolution()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = chosen
	_set_scaling_3d_scale(window, chosen, window.size)


func _apply_fullscreen(window: Window, target: Vector2i) -> void:
	_configure_root_window(window, true)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = target
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	window.mode = Window.MODE_FULLSCREEN
	_set_scaling_3d_scale(window, target, _current_screen_size())


func _apply_windowed(window: Window, target: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	window.mode = Window.MODE_WINDOWED
	_configure_root_window(window, false)
	## Fit the work area minus decorations, not the raw screen size: a client
	## area as tall as the screen puts the bottom of the HUD under the taskbar
	## and the title bar above the top edge. Fullscreen gives a true
	## native-resolution viewport.
	var size := _fit_to_work_area(target)
	DisplayServer.window_set_size(size)
	window.size = size
	## Decorations measure as zero until the window is really windowed, so
	## re-measure now that it is and shrink again if the title bar pushed it over.
	var refit := _fit_to_work_area(size)
	if refit != size:
		size = refit
		DisplayServer.window_set_size(size)
		window.size = size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = _chosen_resolution()
	_set_scaling_3d_scale(window, _chosen_resolution(), size)
	_center_window(size)


func _fit_to_work_area(size: Vector2i) -> Vector2i:
	return DisplayResolutionPresetsScript.fit_client_to_work_area(
		size, _usable_screen_rect().size, _window_decoration_overhead()
	)


## Chosen window resolution from settings (native on first run). This is both
## the UI layout size and the 3D render target. project.godot stays at 1080p
## only as a boot fallback so Play does not open a 4K window before this runs.
func _chosen_resolution() -> Vector2i:
	if (
		window_width >= DisplayResolutionPresetsScript.MIN_SIZE.x
		and window_height >= DisplayResolutionPresetsScript.MIN_SIZE.y
	):
		return Vector2i(window_width, window_height)
	return DisplayResolutionPresetsScript.DEFAULT_SIZE


func _set_scaling_3d_scale(window: Window, render_size: Vector2i, output_size: Vector2i) -> void:
	var scale := DisplayResolutionPresetsScript.compute_scaling_3d_scale(render_size, output_size)
	window.scaling_3d_scale = scale


func _configure_root_window(window: Window, is_fullscreen: bool) -> void:
	## Avoid popup_window / WINDOW_FLAG_POPUP — setting either on the main window errors.
	window.extend_to_title = false
	window.exclusive = false
	window.borderless = is_fullscreen
	window.unresizable = is_fullscreen
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, is_fullscreen)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED, is_fullscreen)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_EXTEND_TO_TITLE, false)


func _center_window(window_size: Vector2i) -> void:
	var usable := _usable_screen_rect()
	var overhead := _window_decoration_overhead()
	var offset := _window_decoration_offset()
	var delta := usable.size - overhead - window_size
	## window_set_position places the *client* area, so shift down by the title
	## bar height to keep the decorated window inside the work area.
	var window_pos := (
		usable.position
		+ offset
		+ Vector2i(maxi(int(delta.x * 0.5), 0), maxi(int(delta.y * 0.5), 0))
	)
	DisplayServer.window_set_position(window_pos)


## Screen area excluding taskbars and other reserved desktop space.
func _usable_screen_rect() -> Rect2i:
	var screen_id := DisplayServer.window_get_current_screen()
	if screen_id < 0:
		screen_id = DisplayServer.get_primary_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen_id)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return Rect2i(
			DisplayServer.screen_get_position(screen_id),
			DisplayServer.screen_get_size(screen_id)
		)
	return usable


## Pixels the border and title bar add around the client area.
func _window_decoration_overhead() -> Vector2i:
	var overhead := (
		DisplayServer.window_get_size_with_decorations()
		- DisplayServer.window_get_size()
	)
	return Vector2i(maxi(overhead.x, 0), maxi(overhead.y, 0))


## Distance from the decorated top-left to the client top-left (title bar height).
func _window_decoration_offset() -> Vector2i:
	var offset := (
		DisplayServer.window_get_position()
		- DisplayServer.window_get_position_with_decorations()
	)
	return Vector2i(maxi(offset.x, 0), maxi(offset.y, 0))


func _current_screen_size() -> Vector2i:
	var screen_id := DisplayServer.window_get_current_screen()
	if screen_id < 0:
		screen_id = DisplayServer.get_primary_screen()
	return DisplayServer.screen_get_size(screen_id)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_apply_native_default_window_size()
		return

	var loaded_size := Vector2i(
		int(config.get_value("display", "window_width", window_width)),
		int(config.get_value("display", "window_height", window_height))
	)
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	var resolved_size := DisplayResolutionPresetsScript.resolve_saved_window_size(
		loaded_size, DisplayResolutionPresetsScript.get_default_monitor_size()
	)
	window_width = resolved_size.x
	window_height = resolved_size.y
	var persist_display := resolved_size != loaded_size
	master_volume = config.get_value("audio", "master_volume", master_volume)
	mic_volume = clampf(
		float(config.get_value("audio", "mic_volume", mic_volume)),
		0.0,
		MIC_VOLUME_MAX
	)
	mic_muted = bool(config.get_value("audio", "mic_muted", mic_muted))
	input_device = config.get_value("audio", "input_device", input_device)
	output_device = config.get_value("audio", "output_device", output_device)
	lobby_voice_default = bool(
		config.get_value("audio", "lobby_voice_default", lobby_voice_default)
	)
	## Prefer hear_myself; fall back to short-lived mic_test_monitor key if present.
	if config.has_section_key("audio", "hear_myself"):
		hear_myself = bool(config.get_value("audio", "hear_myself", hear_myself))
	elif config.has_section_key("audio", "mic_test_monitor"):
		hear_myself = bool(config.get_value("audio", "mic_test_monitor", hear_myself))
	crosshair_color = config.get_value("crosshair", "color", crosshair_color)
	crosshair_opacity = clampf(
		float(config.get_value("crosshair", "opacity", crosshair_opacity)),
		0.0,
		1.0
	)
	crosshair_thickness = clampf(
		float(config.get_value("crosshair", "thickness", crosshair_thickness)),
		0.5,
		5.0
	)
	crosshair_show_outer = bool(
		config.get_value("crosshair", "show_outer", crosshair_show_outer)
	)
	crosshair_show_dot = bool(config.get_value("crosshair", "show_dot", crosshair_show_dot))
	dev_solo_role = int(config.get_value("dev", "dev_solo_role", dev_solo_role))
	dev_allow_any_lobby_size = config.get_value(
		"dev", "dev_allow_any_lobby_size", dev_allow_any_lobby_size
	)
	netfox_debug_logs = bool(config.get_value("dev", "netfox_debug_logs", netfox_debug_logs))
	net_diag_capture = bool(config.get_value("dev", "net_diag_capture", net_diag_capture))
	dev_random_level = bool(config.get_value("dev", "dev_random_level", dev_random_level))
	dev_selected_level_id = str(
		config.get_value("dev", "dev_selected_level_id", dev_selected_level_id)
	)
	_load_input_binds(config)
	if persist_display:
		save_settings()


func snapshot_input_project_defaults() -> void:
	if not _input_project_defaults.is_empty():
		return
	_input_project_defaults = InputRebindStoreScript.snapshot_catalog()


func get_input_project_defaults() -> Dictionary:
	if _input_project_defaults.is_empty():
		snapshot_input_project_defaults()
	return _input_project_defaults.duplicate(true)


func apply_saved_input_binds(binds: Dictionary) -> void:
	for action in binds.keys():
		var action_name := str(action)
		if not InputRebindCatalogScript.has_action(action_name):
			continue
		if binds[action] is Dictionary:
			InputRebindStoreScript.apply_packed(action_name, binds[action] as Dictionary)


func pack_live_input_binds() -> Dictionary:
	return InputRebindStoreScript.snapshot_catalog()


func reset_input_action_to_project_default(action: String) -> void:
	InputRebindStoreScript.restore_action_from_defaults(action, _input_project_defaults)


func _load_input_binds(config: ConfigFile) -> void:
	if not config.has_section("input"):
		return
	var binds := {}
	for key in config.get_section_keys("input"):
		var action := _migrate_input_action_name(str(key))
		var value: Variant = config.get_value("input", key, {})
		if value is Dictionary:
			binds[action] = value
	apply_saved_input_binds(binds)


func _migrate_input_action_name(action: String) -> String:
	if INPUT_KEY_MIGRATE.has(action):
		return str(INPUT_KEY_MIGRATE[action])
	return action


func _apply_netfox_logging() -> void:
	var verbose := netfox_debug_logs
	if OS.get_environment("WIZARD_E2E") == "1":
		verbose = false
	var level := NetfoxLogger.LOG_DEBUG if verbose else NetfoxLogger.LOG_WARN
	NetfoxLogger.log_level = level
	NetfoxLogger.module_log_level["netfox"] = level
	NetfoxLogger.module_log_level["netfox.extras"] = level


func _apply_net_diag() -> void:
	if not is_inside_tree():
		return
	var diag := get_tree().root.get_node_or_null("NetDiag")
	if diag != null and diag.has_method("set_enabled"):
		diag.call("set_enabled", net_diag_capture)


func apply_solo_dev_loadout_to_game_state() -> void:
	GameState.apply_solo_dev_loadout(GameState.PlayerRole.APPRENTICE)


## What NetworkManager.start_game() should ship as the match's level id: a
## fresh random pick unless Dev Settings pinned a specific known level. The
## level's own map_id decides which arena scene loads.
func resolve_match_level_id() -> String:
	if dev_random_level or not LevelCatalogScript.is_known_id(dev_selected_level_id):
		return LevelCatalogScript.random_id()
	return dev_selected_level_id


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "window_width", window_width)
	config.set_value("display", "window_height", window_height)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "mic_volume", mic_volume)
	config.set_value("audio", "mic_muted", mic_muted)
	config.set_value("audio", "input_device", input_device)
	config.set_value("audio", "output_device", output_device)
	config.set_value("audio", "lobby_voice_default", lobby_voice_default)
	config.set_value("audio", "hear_myself", hear_myself)
	config.set_value("crosshair", "color", crosshair_color)
	config.set_value("crosshair", "opacity", crosshair_opacity)
	config.set_value("crosshair", "thickness", crosshair_thickness)
	config.set_value("crosshair", "show_outer", crosshair_show_outer)
	config.set_value("crosshair", "show_dot", crosshair_show_dot)
	config.set_value("dev", "dev_solo_role", dev_solo_role)
	config.set_value("dev", "dev_allow_any_lobby_size", dev_allow_any_lobby_size)
	config.set_value("dev", "netfox_debug_logs", netfox_debug_logs)
	config.set_value("dev", "net_diag_capture", net_diag_capture)
	config.set_value("dev", "dev_random_level", dev_random_level)
	config.set_value("dev", "dev_selected_level_id", dev_selected_level_id)
	var binds := pack_live_input_binds()
	for action in binds.keys():
		config.set_value("input", str(action), binds[action])
	config.save(SETTINGS_PATH)
	settings_applied.emit()


func apply_audio_settings() -> void:
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		var volume: float = clampf(master_volume, 0.0, 1.0)
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(volume, 0.0001)))

	## MicCapture must stay at 0 dB so STT sees full-scale PCM. Apply mic gain
	## only as software gain on VoIP / hearback / meters (see mic_gain()).
	_ensure_mic_bus()
	var mic_idx: int = AudioServer.get_bus_index(MIC_BUS_NAME)
	if mic_idx >= 0:
		AudioServer.set_bus_volume_db(mic_idx, 0.0)

	var capture_device := _resolve_capture_input_device()
	_close_mic_stream_for_device_change(capture_device)
	_set_driver_output_device(output_device)
	if (
		capture_device.is_empty()
		and not input_device.is_empty()
		and input_device != "Default"
	):
		## Boot often enumerates only ["Default"] before real WASAPI names appear.
		## Do not substitute another device — retry until the saved name shows up.
		_schedule_capture_device_retry()
		_applied_input_device = input_device
		_apply_sidetone()
		return
	_capture_device_retry_count = 0
	if not capture_device.is_empty():
		_set_driver_input_device(capture_device)
		_opened_capture_device = capture_device
	_applied_input_device = input_device
	## Last, because enabling sidetone opens a keepalive stream and it must not
	## land on the outgoing device. The broker holds this off until its reopen.
	_apply_sidetone()


## Reinitialising either device invalidates the WASAPI capture handle held by a
## live mic stream, and the stream never recovers on its own. Close it first;
## the broker reopens on the new device once the driver has settled, so a switch
## costs a moment of capture rather than the rest of the session.
func _close_mic_stream_for_device_change(device: String) -> void:
	var output_changing: bool = (
		not output_device.is_empty()
		and AudioServer.get_output_device() != output_device
	)
	var input_changing: bool = (
		not device.is_empty()
		and AudioServer.get_input_device() != device
	)
	if not output_changing and not input_changing:
		return
	var broker := _find_mic_broker()
	if broker == null:
		return
	if input_changing and broker.has_method("set_input_device_from_settings"):
		broker.call("set_input_device_from_settings", device)
	## Covers the output switch, and any input switch the broker already
	## considered current — the driver reinit invalidates the handle either way.
	if broker.has_method("close_for_device_switch"):
		broker.call("close_for_device_switch")


## The only two calls in the codebase that reinitialise the audio driver. Both
## no-op on an unchanged device, because set_*_device tears the device down even
## when passed the name that is already selected.
func _set_driver_output_device(device: String) -> void:
	if device.is_empty() or AudioServer.get_output_device() == device:
		return
	AudioServer.set_output_device(device)


func _set_driver_input_device(device: String) -> void:
	if device.is_empty() or AudioServer.get_input_device() == device:
		return
	AudioServer.set_input_device(device)


## Hear Myself from settings; mic test always enables sidetone while active.
func _apply_sidetone() -> void:
	_set_broker_output_monitor(_mic_testing or hear_myself)


func _schedule_capture_device_retry() -> void:
	if _capture_device_retry_scheduled:
		return
	if _capture_device_retry_count >= CAPTURE_DEVICE_RETRY_MAX:
		push_warning(
			"SettingsManager: saved input '%s' not in device list after retries"
			% input_device
		)
		return
	_capture_device_retry_scheduled = true
	_capture_device_retry_count += 1
	var tree := get_tree()
	if tree == null:
		_capture_device_retry_scheduled = false
		return
	tree.create_timer(CAPTURE_DEVICE_RETRY_SEC).timeout.connect(
		_on_capture_device_retry_timeout
	)


func _on_capture_device_retry_timeout() -> void:
	_capture_device_retry_scheduled = false
	var capture_device := _resolve_capture_input_device()
	if capture_device.is_empty():
		_schedule_capture_device_retry()
		return
	apply_audio_settings()


## Honor the Settings input device exactly.
## Empty / "Default" = System Default. Never remap HyperX→Default or auto-pick
## another mic — that ignored the user's designated device (debug 2c05d7 H).
func _resolve_capture_input_device() -> String:
	var devices := AudioServer.get_input_device_list()
	if input_device.is_empty() or input_device == "Default":
		if _device_list_has(devices, "Default"):
			return "Default"
		return ""
	if _device_list_has(devices, input_device):
		return input_device
	return ""


func _device_list_has(devices: PackedStringArray, needle: String) -> bool:
	for device_name in devices:
		if device_name == needle:
			return true
	return false


func get_input_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func get_output_devices() -> PackedStringArray:
	return AudioServer.get_output_device_list()


func is_mic_testing() -> bool:
	return _mic_testing


func start_mic_test() -> void:
	## Force Hear Myself sidetone for the test; preference is restored on stop.
	_mic_testing = true
	apply_audio_settings()
	if not _subscribe_meter():
		_mic_testing = false
		_set_broker_output_monitor(hear_myself)
		push_error("SettingsManager: mic test failed — MicCaptureBroker unavailable")
		return
	## If still silent after a beat, dump stage diagnosis to the console.
	var broker := _find_mic_broker()
	if broker != null and broker.has_method("diagnose_capture"):
		get_tree().create_timer(0.85).timeout.connect(
			func() -> void:
				if _mic_testing and broker.has_method("diagnose_capture"):
					broker.call("diagnose_capture")
		)


func stop_mic_test() -> void:
	_mic_testing = false
	_maybe_unsubscribe_meter()
	_set_broker_output_monitor(hear_myself)


## Silent meter for lobby/game speaking indicators (same capture path as mic test).
func start_voice_meter() -> void:
	_voice_meter_active = true
	if not _subscribe_meter():
		_voice_meter_active = false


func stop_voice_meter() -> void:
	_voice_meter_active = false
	_maybe_unsubscribe_meter()


## Drop settings-only meter subscription before VoiceSession takes the broker.
func release_microphone_for_voice() -> void:
	_mic_testing = false
	_voice_meter_active = false
	_unsubscribe_meter()
	_set_broker_output_monitor(hear_myself)


## Clear a stored input device that opened a silent WASAPI endpoint.
func clear_input_device_preference() -> void:
	input_device = ""
	_applied_input_device = ""
	_opened_capture_device = ""


func poll_mic_level() -> float:
	var broker := _find_mic_broker()
	if broker == null:
		return 0.0
	if not bool(broker.call("is_capturing")):
		return 0.0
	## Same PCM path as Match voice/STT — meter follows effective mic gain.
	return float(broker.call("get_last_rms")) * MicGainUtilScript.from_settings()


func _subscribe_meter() -> bool:
	var broker := _find_mic_broker()
	if broker == null or not broker.has_method("subscribe"):
		return false
	## No-op sink: keeps capture alive so get_last_rms updates. Chat/spellcasting
	## may already be subscribed; replacing meter is fine.
	return bool(
		broker.call(
			"subscribe",
			MicCaptureBrokerScript.SUB_METER,
			Callable(self, "_on_meter_pcm")
		)
	)


func _unsubscribe_meter() -> void:
	var broker := _find_mic_broker()
	if broker != null and broker.has_method("unsubscribe"):
		broker.call("unsubscribe", MicCaptureBrokerScript.SUB_METER)


func _maybe_unsubscribe_meter() -> void:
	if _mic_testing or _voice_meter_active:
		return
	_unsubscribe_meter()


func _on_meter_pcm(_mono: PackedFloat32Array, _mix_rate: int) -> void:
	## Intentionally empty — MicCaptureBroker updates get_last_rms while draining.
	pass


func _find_mic_broker() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("mic_capture_broker")


func _set_broker_output_monitor(enabled: bool) -> void:
	var broker := _find_mic_broker()
	if broker != null and broker.has_method("set_output_monitor"):
		broker.call("set_output_monitor", enabled)


func _ensure_mic_bus() -> void:
	var bus_idx: int = AudioServer.get_bus_index(MIC_BUS_NAME)
	if bus_idx < 0:
		AudioServer.add_bus()
		bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus_idx, MIC_BUS_NAME)
		AudioServer.add_bus_effect(bus_idx, AudioEffectCapture.new())
	## Prefer broker config (owns MicCapture mute + hear-myself sidetone).
	var broker := _find_mic_broker()
	if broker != null and broker.has_method("ensure_mic_bus_configured"):
		broker.call("ensure_mic_bus_configured")
		return
	## Early boot before broker exists: mute MicCapture (capture still works).
	AudioServer.set_bus_mute(bus_idx, true)
	AudioServer.set_bus_volume_db(bus_idx, 0.0)
	AudioServer.set_bus_send(bus_idx, &"")


func _apply_native_default_window_size() -> void:
	var native := DisplayResolutionPresetsScript.get_default_monitor_size()
	window_width = native.x
	window_height = native.y
