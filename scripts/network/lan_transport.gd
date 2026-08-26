class_name LanTransport
extends MultiplayerTransport

## ENet listen-server. No Steam lobby, SteamMultiplayerPeer, or Steam P2P.

const DEFAULT_PORT := 7777
const DEFAULT_MAX_CLIENTS := 3
const DEFAULT_HOST := "127.0.0.1"
const JOIN_TIMEOUT_SEC := 8.0

var _room_code: String = ""


func get_room_code() -> String:
	return _room_code


static func is_join_code(text: String) -> bool:
	return not parse_endpoint(text).is_empty()


static func parse_endpoint(text: String) -> Dictionary:
	var stripped := text.strip_edges()
	if stripped.is_empty():
		return {}
	if stripped.contains(":"):
		var parts := stripped.rsplit(":", false, 1)
		if parts.size() != 2:
			return {}
		var hostname := parts[0].strip_edges()
		var port := _parse_port(parts[1])
		if hostname.is_empty() or port <= 0:
			return {}
		return {"host": hostname, "port": port}
	if stripped.contains("."):
		return {"host": stripped, "port": DEFAULT_PORT}
	var port_only := _parse_port(stripped)
	if port_only <= 0:
		return {}
	return {"host": DEFAULT_HOST, "port": port_only}


static func _parse_port(text: String) -> int:
	var trimmed := text.strip_edges()
	if trimmed.is_empty() or not trimmed.is_valid_int():
		return 0
	var port := int(trimmed)
	if port < 1 or port > 65535:
		return 0
	return port


func host(options: Dictionary) -> Error:
	if _tree == null:
		return ERR_UNCONFIGURED
	var port := int(options.get("port", DEFAULT_PORT))
	if port <= 0:
		port = DEFAULT_PORT
	var max_clients := int(options.get("max_members", DEFAULT_MAX_CLIENTS + 1)) - 1
	max_clients = maxi(max_clients, 1)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		status_changed.emit("LAN host failed on port %d." % port)
		return err
	_tree.get_multiplayer().multiplayer_peer = peer
	_room_code = str(port)
	status_changed.emit("LAN lobby listening on port %d." % port)
	return OK


func join(options: Dictionary) -> Error:
	if _tree == null:
		return ERR_UNCONFIGURED
	var endpoint := parse_endpoint(str(options.get("room_code", "")))
	if endpoint.is_empty():
		status_changed.emit("LAN join needs host:port (or a port for localhost).")
		return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(str(endpoint["host"]), int(endpoint["port"]))
	if err != OK:
		status_changed.emit("LAN join failed.")
		return err
	_tree.get_multiplayer().multiplayer_peer = peer
	_room_code = "%s:%d" % [endpoint["host"], int(endpoint["port"])]
	status_changed.emit("Connecting over LAN…")
	var wait_err := await wait_for_connection(JOIN_TIMEOUT_SEC)
	if wait_err != OK:
		status_changed.emit("Timed out connecting to LAN host.")
		disconnect_session()
		return wait_err
	status_changed.emit("Connected over LAN.")
	return OK


func disconnect_session() -> void:
	if _tree == null:
		_room_code = ""
		return
	var mp := _tree.get_multiplayer()
	var peer := mp.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	if mp.multiplayer_peer == null or not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()
	_room_code = ""
