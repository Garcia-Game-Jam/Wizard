class_name SettingsPanel
extends Control

signal closed

const DisplayResolutionPresetsScript := preload("res://scripts/ui/display_resolution_presets.gd")
const SettingsEditSessionScript := preload("res://scripts/ui/settings_edit_session.gd")
const SettingsControlsTabScript := preload("res://scripts/ui/keybinds/settings_controls_tab.gd")
const ValueSliderScript := preload("res://scripts/ui/scaffolding/value_slider.gd")
const LevelCatalogScript := preload("res://scripts/arena/level_catalog.gd")
const EXIT_LABEL := "Exit"

var _mic_test_active := false
var _mic_peak: float = 0.0
var _output_device_option: OptionButton
var _input_device_option: OptionButton
var _master_volume_slider: ValueSliderScript
var _mic_volume_slider: ValueSliderScript
var _mic_test_button: Button
var _hear_myself_switch: CheckButton
var _mic_level_bar: ProgressBar
var _mic_status_label: Label
var _lobby_voice_switch: CheckButton
var _lobby_voice_hint: Label
var _player_voice_list: VBoxContainer
var _display_mode_option: OptionButton
var _resolution_option: OptionButton
var _resolution_hint_label: Label
var _crosshair_opacity_slider: ValueSliderScript
var _crosshair_thickness_slider: ValueSliderScript
var _crosshair_color_picker: ColorPickerButton
var _crosshair_outer_switch: CheckButton
var _crosshair_dot_switch: CheckButton
var _crosshair_preview: Control
var _dev_allow_any_lobby_size_checkbox: CheckBox
var _netfox_debug_logs_checkbox: CheckBox
var _net_diag_capture_checkbox: CheckBox
var _random_level_checkbox: CheckBox
var _level_option: OptionButton
var _session: SettingsEditSessionScript = SettingsEditSessionScript.new()
var _exit_style_normal: StyleBoxFlat
var _exit_style_dirty: StyleBoxFlat
var _exit_wobble: Tween

@onready var _general_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/General/MarginContainer/ScrollContainer/GeneralVBox
)
@onready var _graphics_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/Graphics/MarginContainer/ScrollContainer/GraphicsVBox
)
@onready var _audio_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/Audio/MarginContainer/ScrollContainer/AudioVBox
)
@onready var _dev_vbox: VBoxContainer = (
	$Panel/MarginContainer/VBox/TabContainer/Developer/MarginContainer/DevVBox
)
@onready var _dev_settings_vbox: VBoxContainer = (
	$"Panel/MarginContainer/VBox/TabContainer/Dev Settings/MarginContainer/DevSettingsVBox"
)
@onready var _controls_tab: SettingsControlsTabScript = (
	$Panel/MarginContainer/VBox/TabContainer/Controls/SettingsControlsTab
)
@onready var _revert_button: Button = $Panel/MarginContainer/VBox/Footer/RevertButton
@onready var _save_button: Button = $Panel/MarginContainer/VBox/Footer/SaveButton
@onready var _exit_button: Button = $Panel/MarginContainer/VBox/Footer/ExitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Engine.is_editor_hint():
		visible = false
	$Dimmer.color = UiPalette.SCRIM
	_cache_node_refs()
	_mic_level_bar.min_value = 0.0
	_mic_level_bar.max_value = 1.0
	_mic_level_bar.value = 0.0
	_revert_button.pressed.connect(_on_revert_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_controls_tab.binds_changed.connect(_on_binds_changed)
	_build_exit_styles()
	_mic_test_button.pressed.connect(_on_mic_test_pressed)
	_hear_myself_switch.toggled.connect(_on_hear_myself_toggled)
	_master_volume_slider.value_changed.connect(_on_master_volume_changed)
	_mic_volume_slider.value_changed.connect(_on_mic_volume_changed)
	_crosshair_opacity_slider.value_changed.connect(_on_crosshair_opacity_changed)
	_crosshair_thickness_slider.value_changed.connect(_on_crosshair_thickness_changed)
	_crosshair_color_picker.color_changed.connect(_on_crosshair_color_changed)
	_crosshair_outer_switch.toggled.connect(_on_crosshair_outer_toggled)
	_crosshair_dot_switch.toggled.connect(_on_crosshair_dot_toggled)
	_lobby_voice_switch.toggled.connect(_on_lobby_voice_toggled)
	_display_mode_option.item_selected.connect(_on_display_mode_selected)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_input_device_option.item_selected.connect(_on_input_device_selected)
	_output_device_option.item_selected.connect(_on_output_device_selected)
	_dev_allow_any_lobby_size_checkbox.toggled.connect(_on_dev_flags_changed)
	_netfox_debug_logs_checkbox.toggled.connect(_on_dev_flags_changed)
	_net_diag_capture_checkbox.toggled.connect(_on_dev_flags_changed)
	_random_level_checkbox.toggled.connect(_on_random_level_toggled)
	_level_option.item_selected.connect(_on_level_selected)
	NetworkManager.lobby_roster_changed.connect(_on_lobby_roster_changed)
	_populate_from_settings()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_exit_pressed()
		get_viewport().set_input_as_handled()


func open() -> void:
	_populate_from_settings()
	visible = true
	_mic_test_active = false
	_mic_peak = 0.0
	_mic_level_bar.value = 0.0
	_mic_status_label.text = "Press Test Microphone to check input."
	_mic_test_button.text = "Test Microphone"
	_refresh_lobby_voice_switch()
	_refresh_player_voice_list()
	_controls_tab.cancel_listen()
	_controls_tab.rebuild()
	_session.capture_last_save()
	_refresh_footer()


func close_panel() -> void:
	_on_exit_pressed()


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_lobby_voice_switch()
	if not _mic_test_active:
		return

	var level: float = SettingsManager.poll_mic_level()
	_mic_peak = maxf(_mic_peak * 0.92, level)
	_mic_level_bar.value = _mic_peak
	if _mic_peak > 0.02:
		_mic_status_label.text = "Microphone detected — speak to see levels."
	elif _mic_peak > 0.005:
		_mic_status_label.text = "Quiet input detected — try speaking louder."
	else:
		_mic_status_label.text = "Listening… no input yet. Check device selection."


func _cache_node_refs() -> void:
	_display_mode_option = _graphics_vbox.get_node("DisplayModeOption")
	_resolution_option = _graphics_vbox.get_node("ResolutionOption")
	_resolution_hint_label = _graphics_vbox.get_node("ResolutionHintLabel")
	_crosshair_opacity_slider = _general_vbox.get_node(
		"CrosshairOpacityRow/CrosshairOpacitySlider"
	)
	_crosshair_thickness_slider = _general_vbox.get_node(
		"CrosshairThicknessRow/CrosshairThicknessSlider"
	)
	_crosshair_color_picker = _general_vbox.get_node(
		"CrosshairColorRow/CrosshairColorPicker"
	)
	_crosshair_outer_switch = _general_vbox.get_node(
		"CrosshairOuterRow/CrosshairOuterSwitch"
	)
	_crosshair_dot_switch = _general_vbox.get_node("CrosshairDotRow/CrosshairDotSwitch")
	_crosshair_preview = _general_vbox.get_node("CrosshairPreviewFrame/CrosshairPreview")
	_output_device_option = _audio_vbox.get_node("OutputDeviceOption")
	_input_device_option = _audio_vbox.get_node("InputDeviceOption")
	_master_volume_slider = _audio_vbox.get_node("MasterVolumeRow/MasterVolumeSlider")
	_mic_volume_slider = _audio_vbox.get_node("MicVolumeRow/MicVolumeSlider")
	_mic_test_button = _audio_vbox.get_node("MicTestButton")
	_hear_myself_switch = _audio_vbox.get_node("HearMyselfRow/HearMyselfSwitch")
	_mic_level_bar = _audio_vbox.get_node("MicLevelBar")
	_mic_status_label = _audio_vbox.get_node("MicStatusLabel")
	_lobby_voice_switch = _audio_vbox.get_node("LobbyVoiceRow/LobbyVoiceSwitch")
	_lobby_voice_hint = _audio_vbox.get_node("LobbyVoiceHint")
	_player_voice_list = _audio_vbox.get_node_or_null("PlayerVoiceList") as VBoxContainer
	_dev_allow_any_lobby_size_checkbox = _dev_vbox.get_node("DevAllowAnyLobbySizeCheckBox")
	_netfox_debug_logs_checkbox = _dev_vbox.get_node("NetfoxDebugLogsCheckBox")
	_net_diag_capture_checkbox = _dev_vbox.get_node("NetDiagCaptureCheckBox")
	_random_level_checkbox = _dev_settings_vbox.get_node("RandomLevelCheckBox")
	_level_option = _dev_settings_vbox.get_node("LevelOptionButton")


func _populate_from_settings() -> void:
	_populate_display_mode_options()
	_select_display_mode(SettingsManager.fullscreen)
	_populate_resolution_options()
	_select_resolution(SettingsManager.get_window_resolution_preset_index())
	_fill_device_option(
		_output_device_option,
		SettingsManager.get_output_devices(),
		"System Default"
	)
	_fill_device_option(
		_input_device_option,
		SettingsManager.get_input_devices(),
		"System Default"
	)
	_output_device_option.set_block_signals(true)
	_input_device_option.set_block_signals(true)
	_select_device(_output_device_option, SettingsManager.output_device)
	_select_device(_input_device_option, SettingsManager.input_device)
	_output_device_option.set_block_signals(false)
	_input_device_option.set_block_signals(false)
	_master_volume_slider.set_value_no_signal(SettingsManager.master_volume)
	_mic_volume_slider.set_value_no_signal(SettingsManager.mic_volume)
	_hear_myself_switch.set_pressed_no_signal(SettingsManager.hear_myself)
	_crosshair_opacity_slider.set_value_no_signal(SettingsManager.crosshair_opacity)
	_crosshair_thickness_slider.set_value_no_signal(SettingsManager.crosshair_thickness)
	_crosshair_color_picker.set_block_signals(true)
	_crosshair_color_picker.color = SettingsManager.crosshair_color
	_crosshair_color_picker.set_block_signals(false)
	_crosshair_outer_switch.set_pressed_no_signal(SettingsManager.crosshair_show_outer)
	_crosshair_dot_switch.set_pressed_no_signal(SettingsManager.crosshair_show_dot)
	_refresh_crosshair_preview()
	_refresh_lobby_voice_switch()
	_dev_allow_any_lobby_size_checkbox.set_pressed_no_signal(
		SettingsManager.dev_allow_any_lobby_size
	)
	_netfox_debug_logs_checkbox.set_pressed_no_signal(SettingsManager.netfox_debug_logs)
	_net_diag_capture_checkbox.set_pressed_no_signal(SettingsManager.net_diag_capture)
	_populate_level_options()
	_random_level_checkbox.set_pressed_no_signal(SettingsManager.dev_random_level)
	_select_level_option(SettingsManager.dev_selected_level_id)
	_level_option.disabled = SettingsManager.dev_random_level


func _populate_display_mode_options() -> void:
	_display_mode_option.clear()
	_display_mode_option.add_item("Windowed")
	_display_mode_option.add_item("Fullscreen")


func _select_display_mode(is_fullscreen: bool) -> void:
	_display_mode_option.set_block_signals(true)
	_display_mode_option.select(1 if is_fullscreen else 0)
	_display_mode_option.set_block_signals(false)


func _populate_resolution_options() -> void:
	_resolution_option.clear()
	for resolution_size in SettingsManager.get_resolution_presets():
		_resolution_option.add_item(
			DisplayResolutionPresetsScript.format_label(resolution_size)
		)
	_update_resolution_hint()


func _update_resolution_hint() -> void:
	if _resolution_hint_label == null:
		return
	if SettingsManager.is_running_embedded_in_editor():
		_resolution_hint_label.text = (
			"Window size cannot change in the embedded Game tab, "
			+ "but render and UI scale still follow the chosen resolution."
		)
	elif SettingsManager.fullscreen:
		_resolution_hint_label.text = (
			"Fullscreen fills your monitor. Resolution sets the render and UI scale."
		)
	else:
		_resolution_hint_label.text = (
			"Windowed mode uses this size for the game window. "
			+ "Drag the window edges to resize manually."
		)


func _select_resolution(index: int) -> void:
	if _resolution_option.item_count == 0:
		return
	_resolution_option.set_block_signals(true)
	_resolution_option.select(clampi(index, 0, _resolution_option.item_count - 1))
	_resolution_option.set_block_signals(false)


func _fill_device_option(
	option: OptionButton,
	devices: PackedStringArray,
	default_label: String
) -> void:
	option.clear()
	option.add_item(default_label)
	for device_name in devices:
		option.add_item(device_name)


func _select_device(option: OptionButton, saved_device: String) -> void:
	if saved_device.is_empty():
		option.select(0)
		return
	for i in option.item_count:
		if option.get_item_text(i) == saved_device:
			option.select(i)
			return
	option.select(0)


func _populate_level_options() -> void:
	_level_option.clear()
	for level_id in LevelCatalogScript.all_ids():
		_level_option.add_item(LevelCatalogScript.display_name_for_id(level_id))
		_level_option.set_item_metadata(_level_option.item_count - 1, level_id)


func _select_level_option(level_id: String) -> void:
	if _level_option.item_count == 0:
		return
	var target := level_id
	if not LevelCatalogScript.is_known_id(target):
		target = LevelCatalogScript.default_id()
	_level_option.set_block_signals(true)
	for i in _level_option.item_count:
		if str(_level_option.get_item_metadata(i)) == target:
			_level_option.select(i)
			break
	_level_option.set_block_signals(false)


func _selected_level_id() -> String:
	if _level_option.selected < 0:
		return ""
	return str(_level_option.get_item_metadata(_level_option.selected))


func _apply_to_manager() -> void:
	## Push UI into live SettingsManager + audio/display systems.
	## Does not write settings.cfg — that happens on Save.
	SettingsManager.fullscreen = _display_mode_option.selected == 1
	SettingsManager.set_window_resolution_preset_index(_resolution_option.selected)
	SettingsManager.master_volume = _master_volume_slider.value
	SettingsManager.mic_volume = clampf(
		_mic_volume_slider.value, 0.0, SettingsManager.MIC_VOLUME_MAX
	)
	SettingsManager.hear_myself = _hear_myself_switch.button_pressed
	SettingsManager.output_device = _read_device_selection(_output_device_option)
	SettingsManager.input_device = _read_device_selection(_input_device_option)
	SettingsManager.crosshair_opacity = _crosshair_opacity_slider.value
	SettingsManager.crosshair_thickness = _crosshair_thickness_slider.value
	SettingsManager.crosshair_color = _crosshair_color_picker.color
	SettingsManager.crosshair_show_outer = _crosshair_outer_switch.button_pressed
	SettingsManager.crosshair_show_dot = _crosshair_dot_switch.button_pressed
	SettingsManager.dev_allow_any_lobby_size = (
		_dev_allow_any_lobby_size_checkbox.button_pressed
	)
	SettingsManager.netfox_debug_logs = _netfox_debug_logs_checkbox.button_pressed
	SettingsManager.net_diag_capture = _net_diag_capture_checkbox.button_pressed
	SettingsManager.dev_random_level = _random_level_checkbox.button_pressed
	SettingsManager.dev_selected_level_id = _selected_level_id()
	SettingsManager.apply_audio_settings()
	SettingsManager.apply_display_settings()


func _on_binds_changed() -> void:
	_refresh_footer()


func _on_revert_pressed() -> void:
	_session.revert()
	_populate_from_settings()
	_controls_tab.rebuild()
	_refresh_footer()


func _on_save_pressed() -> void:
	_apply_to_manager()
	_session.commit_save()
	_refresh_footer()


func _on_exit_pressed() -> void:
	if not visible:
		return
	if _controls_tab.is_listening():
		_controls_tab.cancel_listen()
		return
	_apply_to_manager()
	var result: Dictionary = _session.request_exit()
	if bool(result.get("should_close", false)):
		_finish_close()
		return
	_refresh_footer()
	_wobble_exit()


func _finish_close() -> void:
	if _mic_test_active:
		_stop_mic_test()
	visible = false
	closed.emit()


func _refresh_footer() -> void:
	if _revert_button == null or _exit_button == null:
		return
	var dirty := _session.is_dirty()
	_revert_button.disabled = not dirty
	if _session.is_exit_confirm_pending():
		_exit_button.text = SettingsEditSessionScript.EXIT_CONFIRM_TEXT
	else:
		_exit_button.text = EXIT_LABEL
	_apply_exit_outline(dirty)


func _build_exit_styles() -> void:
	_exit_style_normal = _make_exit_style(UiPalette.BORDER_DEFAULT)
	_exit_style_dirty = _make_exit_style(Color("eb3838"))


func _make_exit_style(border: Color) -> StyleBoxFlat:
	var box := UiPalette.button_style(UiPalette.BUTTON_FILL, border)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _apply_exit_outline(dirty: bool) -> void:
	var box := _exit_style_dirty if dirty else _exit_style_normal
	_exit_button.add_theme_stylebox_override("normal", box)
	_exit_button.add_theme_stylebox_override("hover", box)
	_exit_button.add_theme_stylebox_override("pressed", box)


func _wobble_exit() -> void:
	if _exit_button == null:
		return
	if _exit_wobble != null:
		_exit_wobble.kill()
	var origin := _exit_button.position
	_exit_wobble = create_tween()
	_exit_wobble.tween_property(_exit_button, "position:x", origin.x + 7.0, 0.04)
	_exit_wobble.tween_property(_exit_button, "position:x", origin.x - 7.0, 0.06)
	_exit_wobble.tween_property(_exit_button, "position:x", origin.x + 4.0, 0.05)
	_exit_wobble.tween_property(_exit_button, "position:x", origin.x, 0.05)


func _read_device_selection(option: OptionButton) -> String:
	if option.selected <= 0:
		return ""
	return option.get_item_text(option.selected)


func _on_display_mode_selected(index: int) -> void:
	SettingsManager.fullscreen = index == 1
	_update_resolution_hint()
	SettingsManager.apply_display_settings()
	_refresh_footer()


func _on_resolution_selected(index: int) -> void:
	SettingsManager.set_window_resolution_preset_index(index)
	SettingsManager.apply_display_settings()
	_refresh_footer()


func _on_dev_flags_changed(_on: bool) -> void:
	SettingsManager.dev_allow_any_lobby_size = (
		_dev_allow_any_lobby_size_checkbox.button_pressed
	)
	SettingsManager.netfox_debug_logs = _netfox_debug_logs_checkbox.button_pressed
	SettingsManager.net_diag_capture = _net_diag_capture_checkbox.button_pressed
	_refresh_footer()


func _on_random_level_toggled(enabled: bool) -> void:
	SettingsManager.dev_random_level = enabled
	_level_option.disabled = enabled
	_refresh_footer()


func _on_level_selected(_index: int) -> void:
	SettingsManager.dev_selected_level_id = _selected_level_id()
	_refresh_footer()


func _on_master_volume_changed(value: float) -> void:
	SettingsManager.master_volume = value
	SettingsManager.apply_audio_settings()
	_refresh_footer()


func _on_mic_volume_changed(value: float) -> void:
	SettingsManager.mic_volume = clampf(value, 0.0, SettingsManager.MIC_VOLUME_MAX)
	SettingsManager.apply_audio_settings()
	_refresh_footer()


func _on_crosshair_opacity_changed(value: float) -> void:
	SettingsManager.crosshair_opacity = value
	_refresh_crosshair_preview()
	_refresh_footer()


func _on_crosshair_thickness_changed(value: float) -> void:
	SettingsManager.crosshair_thickness = value
	_refresh_crosshair_preview()
	_refresh_footer()


func _on_crosshair_color_changed(color: Color) -> void:
	SettingsManager.crosshair_color = color
	_refresh_crosshair_preview()
	_refresh_footer()


func _on_crosshair_outer_toggled(enabled: bool) -> void:
	SettingsManager.crosshair_show_outer = enabled
	_refresh_crosshair_preview()
	_refresh_footer()


func _on_crosshair_dot_toggled(enabled: bool) -> void:
	SettingsManager.crosshair_show_dot = enabled
	_refresh_crosshair_preview()
	_refresh_footer()


func _on_hear_myself_toggled(enabled: bool) -> void:
	SettingsManager.hear_myself = enabled
	SettingsManager.apply_audio_settings()
	_refresh_footer()


func _on_input_device_selected(_index: int) -> void:
	## Live preview: free old mic stream and open the selected device.
	## Persisted to settings.cfg only when Save is pressed.
	SettingsManager.input_device = _read_device_selection(_input_device_option)
	SettingsManager.apply_audio_settings()
	_refresh_footer()


func _on_output_device_selected(_index: int) -> void:
	SettingsManager.output_device = _read_device_selection(_output_device_option)
	SettingsManager.apply_audio_settings()
	_refresh_footer()


func _is_lobby_voice_ui_on() -> bool:
	if NetworkManager.is_session_active:
		return SteamProximityVoiceHub.get_mode() == SteamProximityVoiceHub.Mode.LOBBY
	return SettingsManager.lobby_voice_default


func _can_toggle_lobby_voice_live() -> bool:
	return NetworkManager.is_session_active and NetworkManager.is_host()


func _refresh_lobby_voice_switch() -> void:
	if _lobby_voice_switch == null:
		return
	var enabled := _is_lobby_voice_ui_on()
	_lobby_voice_switch.set_pressed_no_signal(enabled)
	if NetworkManager.is_session_active:
		_lobby_voice_switch.disabled = not NetworkManager.is_host()
		if _lobby_voice_hint != null:
			_lobby_voice_hint.text = (
				"Same control as the lobby menu. Only the host can change lobby voice."
				if NetworkManager.is_host()
				else "Lobby voice is controlled by the host."
			)
	else:
		_lobby_voice_switch.disabled = false
		if _lobby_voice_hint != null:
			_lobby_voice_hint.text = (
				"Sets your default for the next lobby. Hosts can still toggle voice live "
				+ "from the lobby menu or here."
			)


func _on_lobby_voice_toggled(enabled: bool) -> void:
	if _lobby_voice_switch.disabled:
		_refresh_lobby_voice_switch()
		return

	SettingsManager.lobby_voice_default = enabled

	if _can_toggle_lobby_voice_live():
		_set_lobby_voice_enabled(enabled)
	_refresh_lobby_voice_switch()
	_refresh_footer()


func _set_lobby_voice_enabled(enabled: bool) -> void:
	if enabled:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.LOBBY)
	else:
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
	if (
		enabled
		and not SteamProximityVoiceHub.is_lobby_voice_active()
	):
		SteamProximityVoiceHub.set_mode(SteamProximityVoiceHub.Mode.OFF)
		SettingsManager.lobby_voice_default = false
		_lobby_voice_switch.set_pressed_no_signal(false)


func _refresh_crosshair_preview() -> void:
	if _crosshair_preview != null:
		_crosshair_preview.queue_redraw()


func _on_mic_test_pressed() -> void:
	if _mic_test_active:
		_stop_mic_test()
	else:
		_start_mic_test()


func _start_mic_test() -> void:
	## Apply current UI to the live mic path (no file write); test forces Hear Myself.
	_apply_to_manager()
	_mic_peak = 0.0
	_mic_level_bar.value = 0.0
	SettingsManager.start_mic_test()
	_mic_test_active = true
	_mic_test_button.text = "Stop Microphone Test"
	_mic_status_label.text = "Listening… (Hear Myself on for this test)"


func _stop_mic_test() -> void:
	SettingsManager.stop_mic_test()
	_mic_test_active = false
	_mic_test_button.text = "Test Microphone"
	_mic_status_label.text = "Microphone test stopped."


func _on_lobby_roster_changed() -> void:
	if not visible:
		return
	_refresh_player_voice_list()


func _refresh_player_voice_list() -> void:
	if _player_voice_list != null and _player_voice_list.has_method("refresh"):
		_player_voice_list.call("refresh")
