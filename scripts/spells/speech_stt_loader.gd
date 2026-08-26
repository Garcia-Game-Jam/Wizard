extends Node

## Preloads gdvosk + the Vosk model at app startup so spell casts do not hitch.

signal loading_finished(stt_ready: bool)

const TestEnvScript := preload("res://scripts/test/test_env.gd")

var _is_ready := false
var _loading := false
var _status := ""


func _ready() -> void:
	if TestEnvScript.is_active():
		_set_state(false, "disabled in tests")
		return
	SettingsManager.settings_applied.connect(_on_settings_applied)
	call_deferred("_start_prewarm")


func is_ready() -> bool:
	return _is_ready


func is_loading() -> bool:
	return _loading


func get_status() -> String:
	return _status


func ensure_ready() -> bool:
	if _is_ready and GdvoskAdapter.is_model_loaded():
		return true
	if not SpellSttConfig.is_configured():
		_set_state(false, SpellSttConfig.get_setup_issue())
		return false
	if _loading:
		return _is_ready and GdvoskAdapter.is_model_loaded()
	_start_prewarm()
	return _is_ready and GdvoskAdapter.is_model_loaded()


func _on_settings_applied() -> void:
	if not _is_ready and not _loading:
		call_deferred("_start_prewarm")


func _start_prewarm() -> void:
	if _loading:
		return
	if not SpellSttConfig.is_configured():
		_set_state(false, "Speech recognition not installed")
		return
	if not GdvoskAdapter.is_available():
		_set_state(false, "gdvosk extension not available")
		return

	_loading = true
	_is_ready = false
	_status = "Loading speech model..."
	TomeDebug.log("SpeechStt", _status)

	var sample_rate: int = int(AudioServer.get_mix_rate())
	var ok: bool = GdvoskAdapter.prewarm_full(sample_rate)
	if ok:
		_set_state(true, "")
		TomeDebug.log("SpeechStt", "speech model ready (sample_rate=%d)" % sample_rate)
	else:
		_set_state(false, "Failed to load speech model")
		TomeDebug.log("SpeechStt", "speech model load FAILED at %s" % SpellSttConfig.find_model_path())


func _set_state(stt_ready: bool, status: String) -> void:
	_is_ready = stt_ready
	_loading = false
	_status = status
	loading_finished.emit(_is_ready)
