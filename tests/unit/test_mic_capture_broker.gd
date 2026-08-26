class_name TestMicCaptureBroker
extends RefCounted

## Guards MicCaptureBroker API: subscribe lifecycle, inject fan-out, sole drain owner.

const MicCaptureBrokerScript := preload("res://scripts/voice/mic_capture_broker.gd")


func run() -> int:
	var failures := 0
	failures += _test_subscribe_unsubscribe()
	failures += _test_inject_fanout()
	failures += _test_spell_session_uses_listener_sink()
	failures += _test_hub_exposes_listener_api()
	failures += _test_voice_chat_does_not_drain_or_subscribe()
	failures += _test_broker_exposes_ensure_mic_live()
	failures += _test_settings_uses_broker_only()
	failures += _test_device_switch_waits_before_reopening()
	failures += _test_broker_never_reinits_input_device()
	failures += _test_broker_keeps_capturing_while_paused()
	failures += _test_driver_switches_have_one_choke_point()
	failures += _test_stream_closes_before_driver_reinit()
	failures += _test_broker_exposes_device_switch_close()
	return failures


## Both set_*_device calls must stay funnelled through their helpers, so the
## close-before-reinit ordering below cannot be bypassed by a new call site.
func _test_driver_switches_have_one_choke_point() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/settings_manager.gd")
	for call_name in ["AudioServer.set_input_device", "AudioServer.set_output_device"]:
		if src.count(call_name) != 1:
			push_error("%s must be called only from its guarded helper" % call_name)
			return 1
	for helper in ["func _set_driver_input_device", "func _set_driver_output_device"]:
		if src.find(helper) < 0:
			push_error("SettingsManager is missing guarded helper: %s" % helper)
			return 1
	return 0


## Reinitialising a device while an AudioStreamMicrophone is open invalidates its
## WASAPI handle permanently. The stream has to close first.
func _test_stream_closes_before_driver_reinit() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/settings_manager.gd")
	var close_at := src.find("_close_mic_stream_for_device_change(capture_device)")
	var output_at := src.find("_set_driver_output_device(output_device)")
	var input_at := src.find("_set_driver_input_device(capture_device)")
	if close_at < 0 or output_at < 0 or input_at < 0:
		push_error("apply_audio_settings must close the mic stream then switch devices")
		return 1
	if close_at > output_at or close_at > input_at:
		push_error("Mic stream must close before either device is reinitialised")
		return 1
	return 0


func _test_broker_exposes_device_switch_close() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/voice/mic_capture_broker.gd")
	if src.find("func close_for_device_switch") < 0:
		push_error("MicCaptureBroker must expose close_for_device_switch() for Settings")
		return 1
	return 0


## The pause menu sets get_tree().paused. A pausable broker stops draining
## AudioEffectCapture and Godot sets stream_paused on the child mic player,
## which wedges the WASAPI handle for the rest of the session.
func _test_broker_keeps_capturing_while_paused() -> int:
	var path := "res://scripts/voice/mic_capture_broker.gd"
	var src := FileAccess.get_file_as_string(path)
	if src.find("PROCESS_MODE_ALWAYS") < 0:
		push_error("MicCaptureBroker must run with process_mode = PROCESS_MODE_ALWAYS")
		return 1
	return 0


func _test_subscribe_unsubscribe() -> int:
	var broker: Node = MicCaptureBrokerScript.new()
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT)
	var hits := {"n": 0}
	var cb := func(_mono: PackedFloat32Array, _rate: int) -> void:
		hits["n"] = int(hits["n"]) + 1
	if not bool(broker.call("subscribe", MicCaptureBrokerScript.SUB_SPELLCASTING, cb)):
		push_error("Expected subscribe(stt) to succeed under MATCH_FANOUT")
		broker.free()
		return 1
	if not bool(broker.call("has_subscriber", MicCaptureBrokerScript.SUB_SPELLCASTING)):
		push_error("Expected has_subscriber(stt) after subscribe")
		broker.free()
		return 1
	broker.call("inject_pcm", PackedFloat32Array([0.5]), 48000)
	if int(hits["n"]) != 1:
		push_error("Expected inject to fan out to spellcasting subscriber")
		broker.free()
		return 1
	broker.call("unsubscribe", MicCaptureBrokerScript.SUB_SPELLCASTING)
	if bool(broker.call("has_subscriber", MicCaptureBrokerScript.SUB_SPELLCASTING)):
		push_error("Expected unsubscribe to clear spellcasting")
		broker.free()
		return 1
	broker.free()
	return 0


func _test_inject_fanout() -> int:
	var broker: Node = MicCaptureBrokerScript.new()
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT)
	var chat_n := {"n": 0}
	var stt_n := {"n": 0}
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_CHAT,
		func(_m: PackedFloat32Array, _r: int) -> void:
			chat_n["n"] = int(chat_n["n"]) + 1
	)
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_SPELLCASTING,
		func(_m: PackedFloat32Array, _r: int) -> void:
			stt_n["n"] = int(stt_n["n"]) + 1
	)
	broker.call("inject_pcm", PackedFloat32Array([0.1, 0.2]), 48000)
	if int(chat_n["n"]) != 1 or int(stt_n["n"]) != 1:
		push_error("inject_pcm must fan out to chat and spellcasting")
		broker.free()
		return 1
	broker.free()
	return 0


func _test_spell_session_uses_listener_sink() -> int:
	var path := "res://scripts/spells/spell_casting_session.gd"
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		push_error("Could not read %s" % path)
		return 1
	if src.find("get_spellcasting_listener") < 0 or src.find("attach_sink") < 0:
		push_error(
			"SpellCastingSession must attach a sink to Match Listeners/Spellcasting"
		)
		return 1
	if src.find("subscribe_spellcasting") >= 0:
		push_error("SpellCastingSession must not subscribe the broker directly")
		return 1
	if src.find("AudioStreamMicrophone") >= 0:
		push_error("SpellCastingSession must not open a second mic — use Listeners/Spellcasting")
		return 1
	return 0


func _test_hub_exposes_listener_api() -> int:
	var path := "res://scripts/voice/steam_proximity_voice_hub.gd"
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		push_error("Could not read %s" % path)
		return 1
	for method_name in ["get_spellcasting_listener", "get_chat_listener", "get_mic_broker"]:
		if src.find("func %s" % method_name) < 0:
			push_error("SteamProximityVoiceHub missing %s()" % method_name)
			return 1
	if src.find("subscribe_spellcasting") >= 0:
		push_error("Hub must not own cast-time broker subscribe anymore")
		return 1
	return 0


func _test_voice_chat_does_not_drain_or_subscribe() -> int:
	var path := "res://scripts/voice/simple_voice_chat.gd"
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		push_error("Could not read %s" % path)
		return 1
	if src.find("get_buffer") >= 0:
		push_error("SimpleVoiceChat must not call get_buffer — MicCaptureBroker owns drain")
		return 1
	if src.find("SUB_CHAT") >= 0:
		push_error("SimpleVoiceChat must not broker-subscribe as SUB_CHAT — VoiceSession owns that")
		return 1
	return 0


func _test_broker_exposes_ensure_mic_live() -> int:
	var path := "res://scripts/voice/mic_capture_broker.gd"
	var src := FileAccess.get_file_as_string(path)
	var missing := ""
	if src.find("func ensure_mic_live") < 0:
		missing = "ensure_mic_live()"
	elif src.find("func rebind_mic_stream") < 0:
		missing = "rebind_mic_stream()"
	elif src.find("func get_bound_input_device") < 0:
		missing = "get_bound_input_device()"
	elif src.find("func set_input_device_from_settings") < 0:
		missing = "set_input_device_from_settings()"
	elif src.find("func set_output_monitor") < 0:
		missing = "set_output_monitor()"
	elif src.find("func _ensure_mic_open") < 0:
		missing = "_ensure_mic_open() so hear-myself works without subscribers"
	elif src.find("func _restart_mic_stream") < 0:
		missing = "_restart_mic_stream() for device switches"
	if not missing.is_empty():
		push_error("MicCaptureBroker must expose %s" % missing)
		return 1
	return 0


func _test_settings_uses_broker_only() -> int:
	var path := "res://scripts/settings_manager.gd"
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		push_error("Could not read %s" % path)
		return 1
	## Ignore ## / # comments — docs may name AudioStreamMicrophone without owning one.
	var src := _code_without_line_comments(raw)
	var err := ""
	if src.find("AudioStreamMicrophone") >= 0:
		err = "SettingsManager must not open its own AudioStreamMicrophone"
	elif src.find("get_buffer") >= 0:
		err = "SettingsManager must not drain AudioEffectCapture — broker owns drain"
	elif src.find("SUB_METER") < 0:
		err = "SettingsManager mic test must subscribe MicCaptureBroker SUB_METER"
	elif src.find("set_output_monitor") < 0:
		err = "SettingsManager must sync hear_myself to MicCaptureBroker output monitor"
	elif src.find("hear_myself") < 0:
		err = "SettingsManager must persist hear_myself"
	elif src.find("set_input_device_from_settings") < 0:
		err = "SettingsManager must hand the settings device to the broker"
	elif src.find("func _set_driver_input_device") < 0:
		err = "SettingsManager must route input changes through _set_driver_input_device"
	elif src.find("AudioServer.get_input_device() == device") < 0:
		err = (
			"SettingsManager must only call set_input_device on a real change — "
			+ "reinitialising input silences a live mic capture stream"
		)
	if not err.is_empty():
		push_error(err)
		return 1
	return 0


func _code_without_line_comments(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		var cut := line.find("#")
		if cut >= 0:
			out.append(line.substr(0, cut))
		else:
			out.append(line)
	return "\n".join(out)


## Closing and reopening the capture client in one frame lets the outgoing
## stream's input_stop() land after the new stream's input_start(), leaving the
## replacement playing but permanently silent.
func _test_device_switch_waits_before_reopening() -> int:
	var path := "res://scripts/voice/mic_capture_broker.gd"
	var src := FileAccess.get_file_as_string(path)
	if src.find("DEVICE_SWITCH_GAP_SEC") < 0:
		push_error("Device switches must wait between closing and reopening the mic")
		return 1
	var restart_at := src.find("func _restart_mic_stream")
	var finish_at := src.find("func _finish_mic_restart")
	if restart_at < 0 or finish_at < 0:
		push_error("Expected _restart_mic_stream + _finish_mic_restart split")
		return 1
	if src.substr(restart_at, finish_at - restart_at).find("_open_mic_stream(") >= 0:
		push_error("_restart_mic_stream must not reopen in the same frame it closes")
		return 1
	if src.find("AudioStreamMicrophone.new()") < 0:
		push_error("Reopen must create a new AudioStreamMicrophone")
		return 1
	return 0


## The broker must never second-guess the device by reading AudioServer back:
## WASAPI applies set_input_device on the audio thread, so the readback lags and
## a mismatch check tears down a healthy stream.
func _test_broker_never_reinits_input_device() -> int:
	var path := "res://scripts/voice/mic_capture_broker.gd"
	var src := FileAccess.get_file_as_string(path)
	if src.find("AudioServer.set_input_device") >= 0:
		push_error("MicCaptureBroker must not select input devices — Settings owns that")
		return 1
	if src.find("device_mismatch") >= 0:
		push_error("Device-mismatch watchdogs race the WASAPI readback — removed")
		return 1
	return 0
