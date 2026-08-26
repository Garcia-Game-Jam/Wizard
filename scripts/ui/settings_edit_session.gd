class_name SettingsEditSession
extends RefCounted

## In-memory last-save copy for the settings panel. Exit never writes cfg.

const EXIT_CONFIRM_TEXT := "Exit Without Saving"

var _last_save: Dictionary = {}
var _exit_confirm_pending: bool = false


func capture_last_save() -> void:
	_last_save = pack_live()
	_exit_confirm_pending = false


func last_save_copy() -> Dictionary:
	return _last_save.duplicate(true)


func is_dirty() -> bool:
	return pack_live() != _last_save


func is_exit_confirm_pending() -> bool:
	return _exit_confirm_pending


func request_exit() -> Dictionary:
	if not is_dirty():
		_exit_confirm_pending = false
		return {"should_close": true, "confirm_pending": false, "message": ""}
	if _exit_confirm_pending:
		revert()
		return {"should_close": true, "confirm_pending": false, "message": ""}
	_exit_confirm_pending = true
	return {
		"should_close": false,
		"confirm_pending": true,
		"message": EXIT_CONFIRM_TEXT,
	}


func revert() -> void:
	apply_copy(_last_save)
	_exit_confirm_pending = false


func commit_save() -> void:
	SettingsManager.save_settings()
	capture_last_save()


func apply_copy(copy: Dictionary) -> void:
	_apply_manager(copy.get("manager", {}))
	var binds: Variant = copy.get("input", {})
	if binds is Dictionary:
		SettingsManager.apply_saved_input_binds(binds)
	SettingsManager.apply_audio_settings()
	SettingsManager.apply_display_settings()


func pack_live() -> Dictionary:
	return {"manager": _pack_manager(), "input": SettingsManager.pack_live_input_binds()}


func _pack_manager() -> Dictionary:
	return {
		"window_width": SettingsManager.window_width,
		"window_height": SettingsManager.window_height,
		"fullscreen": SettingsManager.fullscreen,
		"master_volume": SettingsManager.master_volume,
		"mic_volume": SettingsManager.mic_volume,
		"mic_muted": SettingsManager.mic_muted,
		"input_device": SettingsManager.input_device,
		"output_device": SettingsManager.output_device,
		"hear_myself": SettingsManager.hear_myself,
		"crosshair_color": SettingsManager.crosshair_color.to_html(false),
		"crosshair_opacity": SettingsManager.crosshair_opacity,
		"crosshair_thickness": SettingsManager.crosshair_thickness,
		"crosshair_show_outer": SettingsManager.crosshair_show_outer,
		"crosshair_show_dot": SettingsManager.crosshair_show_dot,
		"dev_solo_role": SettingsManager.dev_solo_role,
		"lobby_voice_default": SettingsManager.lobby_voice_default,
		"dev_allow_any_lobby_size": SettingsManager.dev_allow_any_lobby_size,
	}


func _apply_manager(data: Dictionary) -> void:
	if data.is_empty():
		return
	SettingsManager.window_width = int(data.get("window_width", SettingsManager.window_width))
	SettingsManager.window_height = int(data.get("window_height", SettingsManager.window_height))
	SettingsManager.fullscreen = bool(data.get("fullscreen", SettingsManager.fullscreen))
	SettingsManager.master_volume = float(data.get("master_volume", SettingsManager.master_volume))
	SettingsManager.mic_volume = clampf(
		float(data.get("mic_volume", SettingsManager.mic_volume)),
		0.0,
		SettingsManager.MIC_VOLUME_MAX
	)
	SettingsManager.mic_muted = bool(data.get("mic_muted", SettingsManager.mic_muted))
	SettingsManager.input_device = str(data.get("input_device", SettingsManager.input_device))
	SettingsManager.output_device = str(data.get("output_device", SettingsManager.output_device))
	SettingsManager.hear_myself = bool(data.get("hear_myself", SettingsManager.hear_myself))
	var color_html := str(data.get("crosshair_color", ""))
	if not color_html.is_empty():
		SettingsManager.crosshair_color = Color.html(color_html)
	SettingsManager.crosshair_opacity = float(
		data.get("crosshair_opacity", SettingsManager.crosshair_opacity)
	)
	SettingsManager.crosshair_thickness = float(
		data.get("crosshair_thickness", SettingsManager.crosshair_thickness)
	)
	SettingsManager.crosshair_show_outer = bool(
		data.get("crosshair_show_outer", SettingsManager.crosshair_show_outer)
	)
	SettingsManager.crosshair_show_dot = bool(
		data.get("crosshair_show_dot", SettingsManager.crosshair_show_dot)
	)
	SettingsManager.dev_solo_role = int(data.get("dev_solo_role", SettingsManager.dev_solo_role))
	SettingsManager.lobby_voice_default = bool(
		data.get("lobby_voice_default", SettingsManager.lobby_voice_default)
	)
	SettingsManager.dev_allow_any_lobby_size = bool(
		data.get("dev_allow_any_lobby_size", SettingsManager.dev_allow_any_lobby_size)
	)
