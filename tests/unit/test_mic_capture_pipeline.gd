class_name TestMicCapturePipeline
extends RefCounted

## Unit-tests the mic broker pipeline with injected PCM (no real mic / Steam).
##
## Contracts:
## 1. Captured audio always reaches the voip subscriber when subscribed
## 2. With wand STT enabled (MATCH_FANOUT), STT receives the same PCM
## 3. Both run concurrently — no pause/resume ownership handoff
## 4. Lobby (CHAT_ONLY) rejects STT — single subscriber pipeline

const MicCaptureBrokerScript := preload("res://scripts/voice/mic_capture_broker.gd")


func run() -> int:
	var failures := 0
	failures += _test_voip_always_receives_injected_pcm()
	failures += _test_match_fanout_voip_and_stt_same_pcm()
	failures += _test_simultaneous_no_pause_api()
	failures += _test_lobby_voip_only_rejects_stt()
	failures += _test_policy_drop_stt_when_collapsing_to_lobby()
	failures += _test_voice_session_authors_listeners()
	failures += _test_chat_proximity_settings()
	failures += _test_no_pause_handoff_in_sources()
	return failures


func _test_voip_always_receives_injected_pcm() -> int:
	var broker: Node = MicCaptureBrokerScript.new()
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT)
	var voip := {"chunks": 0, "last": PackedFloat32Array()}
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_CHAT,
		func(mono: PackedFloat32Array, _rate: int) -> void:
			voip["chunks"] = int(voip["chunks"]) + 1
			voip["last"] = mono.duplicate()
	)
	var sample := PackedFloat32Array([0.25, -0.5, 0.75, 0.0])
	broker.call("inject_pcm", sample, 48000)
	if int(voip["chunks"]) != 1:
		push_error("VoIP subscriber must receive every injected capture chunk")
		broker.free()
		return 1
	var got: PackedFloat32Array = voip["last"] as PackedFloat32Array
	if got.size() != sample.size() or not is_equal_approx(got[0], sample[0]):
		push_error("VoIP must receive the same PCM samples that were captured/injected")
		broker.free()
		return 1
	broker.free()
	return 0


func _test_match_fanout_voip_and_stt_same_pcm() -> int:
	var broker: Node = MicCaptureBrokerScript.new()
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT)
	var voip := {"n": 0, "sum": 0.0}
	var stt := {"n": 0, "sum": 0.0}
	var on_voip := func(mono: PackedFloat32Array, _rate: int) -> void:
		voip["n"] = int(voip["n"]) + 1
		for s in mono:
			voip["sum"] = float(voip["sum"]) + float(s)
	var on_stt := func(mono: PackedFloat32Array, _rate: int) -> void:
		stt["n"] = int(stt["n"]) + 1
		for s in mono:
			stt["sum"] = float(stt["sum"]) + float(s)
	broker.call("subscribe", MicCaptureBrokerScript.SUB_CHAT, on_voip)
	if not bool(broker.call("subscribe", MicCaptureBrokerScript.SUB_SPELLCASTING, on_stt)):
		push_error("MATCH_FANOUT must allow STT (wand) subscribe")
		broker.free()
		return 1
	var sample := PackedFloat32Array([0.1, 0.2, 0.3])
	broker.call("inject_pcm", sample, 44100)
	broker.call("inject_pcm", sample, 44100)
	if int(voip["n"]) != 2 or int(stt["n"]) != 2:
		push_error(
			"Wand STT and VoIP must both receive live chunks (voip=%s stt=%s)"
			% [voip["n"], stt["n"]]
		)
		broker.free()
		return 1
	if not is_equal_approx(float(voip["sum"]), float(stt["sum"])):
		push_error("VoIP and STT must see identical PCM copies during fan-out")
		broker.free()
		return 1
	if int(broker.call("get_subscriber_count")) != 2:
		push_error("Match fan-out should keep both voip and stt subscribed")
		broker.free()
		return 1
	broker.free()
	return 0


func _test_simultaneous_no_pause_api() -> int:
	## Ensure the pipeline has no pause/resume capture handoff anymore.
	var chat_src := FileAccess.get_file_as_string("res://scripts/voice/simple_voice_chat.gd")
	if chat_src.find("pause_capture") >= 0 or chat_src.find("capture_paused") >= 0:
		push_error("SimpleVoiceChat must not pause capture — fan-out replaces handoff")
		return 1
	var broker: Node = MicCaptureBrokerScript.new()
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT)
	var hits := {"voip": 0, "stt": 0}
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_CHAT,
		func(_m: PackedFloat32Array, _r: int) -> void:
			hits["voip"] = int(hits["voip"]) + 1
	)
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_SPELLCASTING,
		func(_m: PackedFloat32Array, _r: int) -> void:
			hits["stt"] = int(hits["stt"]) + 1
	)
	## Simulate wand enabling mid-stream: both already subscribed, inject continues.
	for _i in 5:
		broker.call("inject_pcm", PackedFloat32Array([0.4, -0.4]), 48000)
	if int(hits["voip"]) != 5 or int(hits["stt"]) != 5:
		push_error("Simultaneous capture failed — both sinks must keep receiving")
		broker.free()
		return 1
	broker.free()
	return 0


func _test_lobby_voip_only_rejects_stt() -> int:
	var broker: Node = MicCaptureBrokerScript.new()
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.CHAT_ONLY)
	var voip_n := {"n": 0}
	var stt_n := {"n": 0}
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_CHAT,
		func(_m: PackedFloat32Array, _r: int) -> void:
			voip_n["n"] = int(voip_n["n"]) + 1
	)
	var stt_ok: bool = broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_SPELLCASTING,
		func(_m: PackedFloat32Array, _r: int) -> void:
			stt_n["n"] = int(stt_n["n"]) + 1
	)
	if stt_ok:
		push_error("Lobby CHAT_ONLY must reject STT subscribe (single pipeline)")
		broker.free()
		return 1
	broker.call("inject_pcm", PackedFloat32Array([1.0]), 48000)
	if int(voip_n["n"]) != 1:
		push_error("Lobby voip pipeline must still receive PCM")
		broker.free()
		return 1
	if int(stt_n["n"]) != 0:
		push_error("Lobby must not deliver PCM to STT")
		broker.free()
		return 1
	if int(broker.call("get_subscriber_count")) != 1:
		push_error("Lobby must remain a single-subscriber pipeline")
		broker.free()
		return 1
	broker.free()
	return 0


func _test_policy_drop_stt_when_collapsing_to_lobby() -> int:
	var broker: Node = MicCaptureBrokerScript.new()
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT)
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_CHAT,
		func(_m: PackedFloat32Array, _r: int) -> void: pass
	)
	broker.call(
		"subscribe",
		MicCaptureBrokerScript.SUB_SPELLCASTING,
		func(_m: PackedFloat32Array, _r: int) -> void: pass
	)
	broker.call("set_fanout_policy", MicCaptureBrokerScript.FanoutPolicy.CHAT_ONLY)
	if bool(broker.call("has_subscriber", MicCaptureBrokerScript.SUB_SPELLCASTING)):
		push_error("Switching to CHAT_ONLY must drop STT subscriber")
		broker.free()
		return 1
	if not bool(broker.call("has_subscriber", MicCaptureBrokerScript.SUB_CHAT)):
		push_error("Switching to CHAT_ONLY must keep voip subscriber")
		broker.free()
		return 1
	broker.free()
	return 0


func _test_voice_session_authors_listeners() -> int:
	var path := "res://scripts/voice/game_voice_session.gd"
	var src := FileAccess.get_file_as_string(path)
	var scene := FileAccess.get_file_as_string("res://scenes/game_app.tscn")
	var err := ""
	if src.find("allows_spellcasting_fanout") < 0:
		err = "GameVoiceSession must derive fan-out from authored Listeners/Spellcasting"
	elif src.find("allow_stt_fanout") >= 0:
		err = "GameVoiceSession must not use allow_stt_fanout export — use Listeners nodes"
	elif src.find("_register_authored_listeners") < 0:
		err = "GameVoiceSession must pre-register authored Listeners with the broker"
	elif src.find("attach_sink") < 0:
		err = "GameVoiceSession must attach Chat sink to VoiceEngine"
	elif src.find("get_chat_listener") < 0 or src.find("is_proximity_active") < 0:
		err = "GameVoiceSession must expose Chat proximity via get_chat_listener/is_proximity_active"
	elif src.find("set_fanout_policy") < 0:
		err = "GameVoiceSession must apply MicCaptureBroker fanout policy on start"
	elif scene.find("States/Lobby/VoiceSession/Listeners") < 0:
		err = "game_app.tscn Lobby VoiceSession must author Listeners/"
	elif scene.find("States/Match/VoiceSession/Listeners") < 0:
		err = "game_app.tscn Match VoiceSession must author Listeners/"
	elif not _scene_has_match_spellcasting_listener(scene):
		err = "game_app.tscn Match must author Listeners/Spellcasting"
	elif scene.find("parent=\"States/Lobby/VoiceSession/Listeners\"") < 0:
		err = "game_app.tscn Lobby must nest Chat under Listeners"
	elif scene.find("proximity_chat_settings.gd") < 0:
		err = "game_app.tscn Chat listeners must wire ProximityChatSettings"
	if not err.is_empty():
		push_error(err)
		return 1
	return 0


func _scene_has_match_spellcasting_listener(scene: String) -> bool:
	## Godot 4.6 may append unique_id=… on the same line as the node declaration.
	return scene.contains(
		'name="Spellcasting" type="Node" parent="States/Match/VoiceSession/Listeners"'
	)


func _test_chat_proximity_settings() -> int:
	const ListenerScript := preload("res://scripts/voice/mic_capture_listener.gd")
	const ProxScript := preload("res://scripts/voice/proximity_chat_settings.gd")
	var chat: Node = ListenerScript.new()
	chat.set("service", ListenerScript.Service.CHAT)
	var prox: Resource = ProxScript.new()
	prox.set("enabled", true)
	prox.set("full_volume_m", 8.0)
	prox.set("max_range_m", 40.0)
	chat.set("proximity", prox)
	if not bool(chat.call("is_proximity_active")):
		push_error("Chat listener with proximity.enabled must report is_proximity_active")
		chat.free()
		return 1
	prox.set("enabled", false)
	if bool(chat.call("is_proximity_active")):
		push_error("Chat listener must respect proximity enabled toggle")
		chat.free()
		return 1
	var spell: Node = ListenerScript.new()
	spell.set("service", ListenerScript.Service.SPELLCASTING)
	if spell.call("get_proximity_settings") != null and bool(spell.call("is_proximity_active")):
		push_error("Spellcasting listener must not expose active proximity")
		chat.free()
		spell.free()
		return 1
	chat.free()
	spell.free()
	return 0


func _test_no_pause_handoff_in_sources() -> int:
	for path in [
		"res://scripts/voice/simple_voice_chat.gd",
		"res://scripts/voice/steam_proximity_voice_hub.gd",
		"res://scripts/spells/spell_casting_session.gd",
	]:
		var src := FileAccess.get_file_as_string(path)
		if src.find("pause_capture") >= 0 or src.find("resume_capture") >= 0:
			push_error("%s must not use pause/resume capture handoff" % path)
			return 1
	var session_src := FileAccess.get_file_as_string(
		"res://scripts/voice/game_voice_session.gd"
	)
	if session_src.find("_register_authored_listeners") < 0:
		push_error("GameVoiceSession must pre-register authored listeners")
		return 1
	return 0
