class_name GameVoiceSession
extends Node

## Per-state voice configuration. Starts/stops the shared VoiceEngine for this state's
## player group (lobby open-mic vs match). Select this node in the Inspector to tune.
##
## Author mic consumers under [code]Listeners/[/code] as [MicCaptureListener] nodes:
## - [code]Chat[/code] — voice chat (required for voice). Tune proximity on that node.
## - [code]Spellcasting[/code] — wand STT fan-out (match only; omit in lobby).
##
## On [method start_session], every authored listener is pre-registered with
## [MicCaptureBroker]. Chat/wand attach short-lived PCM sinks; they do not
## subscribe/unsubscribe the broker themselves.

const MicCaptureBrokerScript := preload("res://scripts/voice/mic_capture_broker.gd")
const MicCaptureListenerScript := preload("res://scripts/voice/mic_capture_listener.gd")

@export var open_mic: bool = true
@export var debug_logging: bool = false

var _engine: Node = null
var _active: bool = false


func is_session_active() -> bool:
	return _active and _engine != null and bool(_engine.get("is_active"))


func bind_engine(engine: Node) -> void:
	_engine = engine


func start_session() -> void:
	if _engine == null:
		push_error("GameVoiceSession '%s': no VoiceEngine bound" % name)
		return
	## Apply saved device first, then drop settings-only meter so Match/Lobby
	## Listeners own the same MicCaptureBroker chain.
	SettingsManager.apply_audio_settings()
	SettingsManager.release_microphone_for_voice()
	if not _register_authored_listeners():
		push_error("GameVoiceSession '%s': listener registration failed — voice not started" % name)
		return
	_engine.set("debug_logging", debug_logging)
	_engine.set("transmit_muted", SettingsManager.mic_muted)
	if not bool(_engine.get("is_active")):
		_engine.call("start")
	var chat := get_chat_listener()
	if chat == null:
		push_error("GameVoiceSession '%s': missing Listeners/Chat" % name)
		_unregister_authored_listeners()
		_engine.call("stop")
		return
	chat.attach_sink(Callable(_engine, "_on_broker_pcm"))
	## Chat listener owns the falloff rules; the engine only needs them while this
	## session is the live one (lobby leaves them off for open mic).
	_engine.call("set_proximity_settings", get_proximity_settings())
	_active = true
	TomeDebug.log(
		"VoiceSession",
		"'%s' started listeners=%s policy=%s device='%s' peers=%s"
		% [
			name,
			_listener_ids_label(),
			_policy_label(),
			AudioServer.get_input_device(),
			str(_engine.call("get_peers")),
		]
	)


func stop_session() -> void:
	_active = false
	for listener in get_authored_listeners():
		listener.detach_sink()
	if _engine != null:
		_engine.call("clear_peer_anchors")
		_engine.call("set_proximity_settings", null)
	if _engine != null and bool(_engine.get("is_active")):
		_engine.call("stop")
	_unregister_authored_listeners()
	_set_broker_fanout_policy(MicCaptureBrokerScript.FanoutPolicy.CHAT_ONLY)


func allows_spellcasting_fanout() -> bool:
	return get_spellcasting_listener() != null


func get_chat_listener() -> MicCaptureListener:
	for listener in get_authored_listeners():
		if listener.is_chat():
			return listener
	return null


func get_spellcasting_listener() -> MicCaptureListener:
	for listener in get_authored_listeners():
		if listener.is_spellcasting():
			return listener
	return null


func is_proximity_active() -> bool:
	var chat := get_chat_listener()
	return chat != null and chat.is_proximity_active()


func get_proximity_settings() -> Resource:
	var chat := get_chat_listener()
	if chat == null:
		return null
	return chat.get_proximity_settings()


## World node a remote speaker's voice emits from — their character body in a match.
func set_peer_anchor(steam_id: int, anchor: Node3D) -> void:
	if _engine != null:
		_engine.call("set_peer_anchor", steam_id, anchor)


func get_authored_listeners() -> Array[MicCaptureListener]:
	var out: Array[MicCaptureListener] = []
	var root := get_node_or_null("Listeners")
	if root == null:
		return out
	for child in root.get_children():
		if child is MicCaptureListener:
			out.append(child as MicCaptureListener)
		elif child.get_script() == MicCaptureListenerScript:
			out.append(child as MicCaptureListener)
	return out


func _register_authored_listeners() -> bool:
	var broker := _resolve_broker()
	var err := ""
	if broker == null or not broker.has_method("subscribe"):
		err = "MicCaptureBroker missing or has no subscribe()"
	else:
		_apply_broker_fanout_policy()
		var listeners := get_authored_listeners()
		if listeners.is_empty():
			err = "no Listeners/* authored"
		else:
			err = _subscribe_listeners(broker, listeners)
			if err.is_empty() and broker.has_method("ensure_mic_live"):
				if not bool(broker.call("ensure_mic_live")):
					err = "mic failed to start (device='%s')" % AudioServer.get_input_device()
	if not err.is_empty():
		push_error("GameVoiceSession '%s': %s" % [name, err])
		_unregister_authored_listeners()
		return false
	return true


func _subscribe_listeners(broker: Node, listeners: Array[MicCaptureListener]) -> String:
	for listener in listeners:
		var sub_id: StringName = listener.get_subscriber_id()
		if (
			sub_id == MicCaptureBrokerScript.SUB_SPELLCASTING
			and broker.has_method("is_spellcasting_fanout_allowed")
			and not bool(broker.call("is_spellcasting_fanout_allowed"))
		):
			return "Spellcasting listener requires MATCH_FANOUT"
		if not bool(broker.call("subscribe", sub_id, Callable(listener, "forward_pcm"))):
			return "failed to register listener '%s'" % sub_id
	return ""


func _unregister_authored_listeners() -> void:
	var broker := _resolve_broker()
	if broker != null and broker.has_method("unsubscribe"):
		for listener in get_authored_listeners():
			broker.call("unsubscribe", listener.get_subscriber_id())
			listener.set_listening_state(false)


func _apply_broker_fanout_policy() -> void:
	var policy: int = (
		MicCaptureBrokerScript.FanoutPolicy.MATCH_FANOUT
		if allows_spellcasting_fanout()
		else MicCaptureBrokerScript.FanoutPolicy.CHAT_ONLY
	)
	_set_broker_fanout_policy(policy)


func _set_broker_fanout_policy(policy: int) -> void:
	var broker := _resolve_broker()
	if broker == null:
		return
	if broker.has_method("set_fanout_policy"):
		broker.call("set_fanout_policy", policy)
	else:
		broker.set("fanout_policy", policy)


func _resolve_broker() -> Node:
	var parent := get_parent()
	while parent != null:
		var broker := parent.get_node_or_null("MicCaptureBroker")
		if broker != null:
			return broker
		if parent.is_in_group("game_app") and parent.get("mic_broker") != null:
			return parent.get("mic_broker") as Node
		parent = parent.get_parent()
	var tree := get_tree()
	if tree != null:
		return tree.get_first_node_in_group("mic_capture_broker")
	return null


func _listener_ids_label() -> String:
	var ids: PackedStringArray = PackedStringArray()
	for listener in get_authored_listeners():
		ids.append(str(listener.get_subscriber_id()))
	return ", ".join(ids)


func _policy_label() -> String:
	return "match_fanout" if allows_spellcasting_fanout() else "chat_only"


func refresh_peers() -> void:
	if not _active or _engine == null:
		return
	_engine.call("prune_stale_peers")


func set_transmit_muted(muted: bool) -> void:
	if _engine != null:
		_engine.set("transmit_muted", muted)


func is_local_speaking(timeout_ms: int = 350) -> bool:
	if _engine == null:
		return false
	return bool(_engine.call("is_local_speaking", timeout_ms))


func is_remote_speaking(steam_id: int, timeout_ms: int = 350) -> bool:
	if _engine == null:
		return false
	return bool(_engine.call("is_remote_speaking", steam_id, timeout_ms))


func is_peer_muted(steam_id: int) -> bool:
	if _engine == null:
		return false
	return bool(_engine.call("is_peer_muted", steam_id))


func set_peer_muted(steam_id: int, muted: bool) -> void:
	if _engine != null:
		_engine.call("set_peer_muted", steam_id, muted)


func get_peer_volume(steam_id: int) -> float:
	if _engine == null:
		return 1.0
	return float(_engine.call("get_peer_volume", steam_id))


func set_peer_volume(steam_id: int, linear: float) -> void:
	if _engine != null:
		_engine.call("set_peer_volume", steam_id, linear)
