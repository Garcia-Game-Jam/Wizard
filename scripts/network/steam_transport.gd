class_name SteamTransport
extends MultiplayerTransport

const MAX_PLAYERS := 4
const CONNECT_TIMEOUT_SEC := 20.0

var _room_code: String = ""
var _awaiting_client_peer: bool = false


func get_room_code() -> String:
	return _room_code


static func parse_lobby_id(text: String) -> int:
	var stripped := text.strip_edges()
	if stripped.is_empty() or not stripped.is_valid_int():
		return 0
	return int(stripped)


static func validate_lobby_id(text: String) -> Error:
	if parse_lobby_id(text) <= 0:
		return ERR_INVALID_PARAMETER
	return OK


func uses_steam() -> bool:
	return true


func invite_to_session() -> void:
	var lobby_id := parse_lobby_id(_room_code)
	if lobby_id > 0:
		SteamService.invite_friends_to_lobby(lobby_id)


func get_player_display_name(peer_id: int) -> String:
	if _tree == null or not SteamService.is_ready():
		return ""
	var mp := _tree.get_multiplayer()
	var peer := mp.multiplayer_peer
	if peer == null or not peer.has_method("get_steam_id_for_peer_id"):
		return ""
	var steam_id := int(peer.call("get_steam_id_for_peer_id", peer_id))
	if steam_id == 0:
		return ""
	return SteamService.get_friend_persona_name(steam_id)


func host(options: Dictionary) -> Error:
	var ready_err := _require_steam_multiplayer_peer()
	if ready_err != OK:
		return ready_err

	var max_members := int(options.get("max_members", MAX_PLAYERS))
	_room_code = ""
	_bind_connect_handlers()
	_ensure_offline_peer()

	status_changed.emit("Creating Steam lobby…")
	var create_err := SteamService.create_lobby(max_members)
	if create_err != OK:
		return create_err

	var create_result: Dictionary = await SteamService.lobby_create_finished
	if int(create_result.get("error", ERR_CANT_CREATE)) != OK:
		status_changed.emit("Failed to create Steam lobby.")
		return int(create_result.get("error", ERR_CANT_CREATE)) as Error

	var lobby_id := int(create_result.get("lobby_id", 0))
	return _start_host_peer(lobby_id)


func join(options: Dictionary) -> Error:
	var ready_err := _require_steam_multiplayer_peer()
	if ready_err != OK:
		return ready_err

	var lobby_id := parse_lobby_id(str(options.get("room_code", "")))
	if validate_lobby_id(str(lobby_id)) != OK:
		status_changed.emit("Enter a valid Steam lobby ID.")
		return ERR_INVALID_PARAMETER

	_room_code = ""
	_bind_connect_handlers()
	_ensure_offline_peer()
	_awaiting_client_peer = true

	status_changed.emit("Joining Steam lobby…")
	var join_err := SteamService.join_lobby(lobby_id)
	if join_err != OK:
		_awaiting_client_peer = false
		return join_err

	var join_result: Dictionary = await SteamService.lobby_join_finished
	var result_err := int(join_result.get("error", ERR_CANT_CONNECT))
	if result_err != OK:
		_awaiting_client_peer = false
		status_changed.emit("Could not enter Steam lobby.")
		return result_err as Error

	lobby_id = int(join_result.get("lobby_id", lobby_id))
	if SteamService.is_local_lobby_owner(lobby_id):
		return _start_host_peer(lobby_id)
	return await _start_client_peer(lobby_id)


func _require_steam_multiplayer_peer() -> Error:
	if not SteamService.is_ready():
		status_changed.emit("Steam is not running. Launch the Steam client and try again.")
		return ERR_UNAVAILABLE
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		status_changed.emit("GodotSteam MultiplayerPeer missing — reinstall GodotSteam.")
		return ERR_UNAVAILABLE
	return OK


func disconnect_session() -> void:
	_awaiting_client_peer = false
	var mp := _tree.get_multiplayer()
	var peer := mp.multiplayer_peer
	if peer != null and not peer is OfflineMultiplayerPeer:
		peer.close()
	_ensure_offline_peer()
	SteamService.leave_lobby()
	_room_code = ""


func _start_host_peer(lobby_id: int) -> Error:
	SteamService.allow_p2p_relay()
	var peer: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		status_changed.emit("GodotSteam MultiplayerPeer missing — reinstall GodotSteam.")
		return ERR_UNAVAILABLE
	var err: Error = peer.call("host_with_lobby", lobby_id)
	if err != OK:
		status_changed.emit("Failed to start Steam host.")
		return err

	_tree.get_multiplayer().multiplayer_peer = peer
	_room_code = str(lobby_id)
	status_changed.emit("Lobby ready. Invite friends or share lobby ID.")
	return OK


func _start_client_peer(lobby_id: int) -> Error:
	SteamService.allow_p2p_relay()
	var peer: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer == null:
		status_changed.emit("GodotSteam MultiplayerPeer missing — reinstall GodotSteam.")
		_awaiting_client_peer = false
		return ERR_UNAVAILABLE
	var err: Error = peer.call("connect_to_lobby", lobby_id)
	if err != OK:
		status_changed.emit("Failed to connect to Steam host.")
		_awaiting_client_peer = false
		return err

	_tree.get_multiplayer().multiplayer_peer = peer
	_room_code = str(lobby_id)

	err = await wait_for_connection(CONNECT_TIMEOUT_SEC)
	_awaiting_client_peer = false
	if err != OK:
		status_changed.emit("Timed out connecting to host.")
		disconnect_session()
		return err

	status_changed.emit("Connected to host.")
	return OK


func _ensure_offline_peer() -> void:
	var mp := _tree.get_multiplayer()
	if mp.multiplayer_peer == null:
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()


func _bind_connect_handlers() -> void:
	pass
