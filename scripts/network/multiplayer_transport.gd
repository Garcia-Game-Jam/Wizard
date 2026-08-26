class_name MultiplayerTransport
extends RefCounted

## Connection backend for multiplayer sessions (SteamTransport or LanTransport).

signal status_changed(message: String)

var _tree: SceneTree


func setup(tree: SceneTree) -> void:
	_tree = tree


func host(_options: Dictionary) -> Error:
	status_changed.emit("MultiplayerTransport.host() is not implemented.")
	return ERR_UNAVAILABLE


func join(_options: Dictionary) -> Error:
	status_changed.emit("MultiplayerTransport.join() is not implemented.")
	return ERR_UNAVAILABLE


func disconnect_session() -> void:
	pass


func get_room_code() -> String:
	return ""


func uses_steam() -> bool:
	return false


func invite_to_session() -> void:
	pass


func wait_for_connection(timeout_sec: float) -> Error:
	if _tree == null:
		return ERR_UNCONFIGURED
	var elapsed := 0.0
	while elapsed < timeout_sec:
		var mp := _tree.get_multiplayer()
		if mp != null and mp.multiplayer_peer != null:
			var status := mp.multiplayer_peer.get_connection_status()
			if status == MultiplayerPeer.CONNECTION_CONNECTED:
				return OK
			if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
				return ERR_CANT_CONNECT
		await _tree.process_frame
		elapsed += _tree.root.get_process_delta_time()
	return ERR_TIMEOUT


func get_player_display_name(_peer_id: int) -> String:
	return ""
