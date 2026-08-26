extends Node

## Thin autoload façade → GameApp voice API (keeps existing call sites working).

enum Mode { OFF, LOBBY, GAME }


func _app() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("game_app")


func get_mode() -> Mode:
	var app := _app()
	if app == null:
		return Mode.OFF
	var state := int(app.get("state"))
	if not bool(app.call("is_voice_active")):
		return Mode.OFF
	match state:
		1:
			return Mode.LOBBY
		2:
			return Mode.GAME
		_:
			return Mode.OFF


func is_active() -> bool:
	var app := _app()
	return app != null and bool(app.call("is_voice_active"))


func is_lobby_voice_active() -> bool:
	var app := _app()
	return app != null and bool(app.call("is_lobby_voice_active"))


func stop_session() -> void:
	var app := _app()
	if app != null:
		app.call("stop_voice")


func get_mic_broker() -> Node:
	var app := _app()
	if app != null and app.get("mic_broker") != null:
		return app.get("mic_broker") as Node
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("mic_capture_broker")


## Match VoiceSession Spellcasting listener (pre-registered while match voice is on).
func get_spellcasting_listener() -> MicCaptureListener:
	var session := _match_voice_session()
	if session == null or not session.has_method("get_spellcasting_listener"):
		return null
	return session.call("get_spellcasting_listener") as MicCaptureListener


func get_chat_listener() -> MicCaptureListener:
	var session := _active_voice_session()
	if session == null or not session.has_method("get_chat_listener"):
		return null
	return session.call("get_chat_listener") as MicCaptureListener


func _match_voice_session() -> Node:
	var app := _app()
	if app == null:
		return null
	return app.get("match_voice") as Node


func _active_voice_session() -> Node:
	var app := _app()
	if app == null or not app.has_method("get_active_voice_session"):
		return null
	return app.call("get_active_voice_session") as Node


func _voice_engine() -> Node:
	var app := _app()
	if app == null:
		return null
	return app.get("voice_engine") as Node


func set_mode(next: Mode) -> void:
	var app := _app()
	if app == null:
		return
	match next:
		Mode.OFF:
			app.call("stop_voice")
		Mode.LOBBY:
			app.call("set_lobby_voice_enabled", true)
		Mode.GAME:
			app.call("set_match_voice_enabled", true)


func is_peer_speaking(peer_id: int, timeout_ms: int = 350) -> bool:
	var app := _app()
	if app == null:
		return false
	return bool(app.call("is_peer_speaking", peer_id, timeout_ms))


func is_local_speaking(timeout_ms: int = 350) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	return is_peer_speaking(tree.get_multiplayer().get_unique_id(), timeout_ms)


func is_peer_muted(peer_id: int) -> bool:
	var app := _app()
	if app == null:
		return false
	return bool(app.call("is_peer_muted", peer_id))


func set_peer_muted(peer_id: int, muted: bool) -> void:
	var app := _app()
	if app != null:
		app.call("set_peer_muted", peer_id, muted)


func get_peer_volume(peer_id: int) -> float:
	var app := _app()
	if app == null:
		return 1.0
	return float(app.call("get_peer_volume", peer_id))


func set_peer_volume(peer_id: int, linear: float) -> void:
	var app := _app()
	if app != null:
		app.call("set_peer_volume", peer_id, linear)


## World node this peer's voice emits from — their character body during a match.
## Only anchored peers get proximity falloff; the local peer is the listener, not
## an emitter, so it is skipped.
func set_peer_anchor(peer_id: int, anchor: Node3D) -> void:
	if peer_id <= 0:
		return
	var tree := get_tree()
	if tree != null and peer_id == tree.get_multiplayer().get_unique_id():
		return
	var session := _active_voice_session()
	if session != null:
		session.call("set_peer_anchor", peer_id, anchor)


func set_debug_logging(enabled: bool) -> void:
	var app := _app()
	if app != null:
		app.set("debug_voice", enabled)
	var broker := get_mic_broker()
	if broker != null:
		broker.set("debug_logging", enabled)
	var engine := _voice_engine()
	if engine != null:
		engine.set("debug_logging", enabled)
