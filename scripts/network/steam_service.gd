extends Node

## GodotSteam lifecycle and lobby helpers. Steam is attempted once at boot;
## if init fails, this autoload stays off and the rest of the game uses Local/LAN.

signal api_initialized(success: bool)
signal lobby_create_finished(result: Dictionary)
signal lobby_join_finished(result: Dictionary)
signal lobby_invite_received(lobby_id: int)
signal lobby_member_joined(steam_id: int)

const TestEnvScript := preload("res://scripts/test/test_env.gd")
const STEAM_INIT_OK := 0
const LOBBY_CREATE_OK := 1
const LOBBY_ENTER_OK := 1
const LOBBY_TYPE_FRIENDS_ONLY := 1
const DEFAULT_APP_ID := 480

const SteamMultiplayerPeerAdapterScript := preload(
	"res://scripts/network/steam_multiplayer_peer_adapter.gd"
)

var initialized: bool = false
var current_lobby_id: int = 0

var _signals_bound: bool = false
var _p2p_peers: Dictionary = {}
var _quit_started: bool = false
var _teardown_in_progress: bool = false


func _ready() -> void:
	if TestEnvScript.is_active():
		set_process(false)
		return
	get_tree().set_auto_accept_quit(false)
	_bind_window_close()
	if not is_api_available():
		_disable("GodotSteam not loaded — Local and LAN still work.")
		return
	_initialize_api()


func _process(_delta: float) -> void:
	if not is_ready():
		return
	_steam_call("run_callbacks")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_app_quit()
	elif what == NOTIFICATION_PREDELETE:
		# Editor Stop / abrupt tree teardown when quit path did not run.
		# Skip when Steam never started (unit tests) or already shut down.
		if initialized:
			teardown_steam_session(false)


func is_api_available() -> bool:
	return _get_steam_object() != null


func is_ready() -> bool:
	return initialized and is_api_available()


func get_steam_id() -> int:
	if not is_ready():
		return 0
	return int(_steam_call("getSteamID"))


func get_lobby_owner(lobby_id: int) -> int:
	if not is_ready() or lobby_id == 0:
		return 0
	return int(_steam_call("getLobbyOwner", [lobby_id]))


func is_local_lobby_owner(lobby_id: int) -> bool:
	var lobby_owner := get_lobby_owner(lobby_id)
	return lobby_owner != 0 and lobby_owner == get_steam_id()


func create_lobby(max_members: int, lobby_type: int = -1) -> Error:
	if not is_ready():
		return ERR_UNCONFIGURED
	if lobby_type < 0:
		lobby_type = LOBBY_TYPE_FRIENDS_ONLY
	_steam_call("createLobby", [lobby_type, max_members])
	return OK


func join_lobby(lobby_id: int) -> Error:
	if not is_ready():
		return ERR_UNCONFIGURED
	if lobby_id <= 0:
		return ERR_INVALID_PARAMETER
	_steam_call("joinLobby", [lobby_id])
	return OK


func leave_lobby() -> void:
	if not is_ready() or current_lobby_id == 0:
		current_lobby_id = 0
		return
	_steam_call("leaveLobby", [current_lobby_id])
	current_lobby_id = 0


## Ordered cleanup for Exit / window close so Steam does not keep "Playing Spacewar".
func request_app_quit() -> void:
	if _quit_started:
		return
	_quit_started = true
	teardown_steam_session(true)
	var tree := get_tree()
	if tree != null:
		tree.quit()


func teardown_steam_session(stop_network: bool = true) -> void:
	## Stop voice → close P2P (while lobby known) → multiplayer/lobby → steamShutdown.
	if _teardown_in_progress:
		return
	_teardown_in_progress = true
	set_process(false)
	var hub: Node = null
	if is_inside_tree():
		hub = get_node_or_null("/root/SteamProximityVoiceHub")
	if hub != null and hub.has_method("stop_session"):
		hub.call("stop_session")
	# Close P2P before leaveLobby so lobby membership is still enumerable.
	_close_tracked_p2p_sessions()
	if stop_network and is_inside_tree():
		var network := get_node_or_null("/root/NetworkManager")
		if network != null and network.has_method("disconnect_session"):
			network.call("disconnect_session")
	leave_lobby()
	_steam_shutdown_api()
	_teardown_in_progress = false


func shutdown() -> void:
	## Full Steam teardown without quitting the process (tests, etc.).
	teardown_steam_session(true)


func allow_p2p_relay() -> void:
	if is_ready():
		_steam_call("allowP2PPacketRelay", [true])


func invite_friends_to_lobby(lobby_id: int) -> Error:
	if not is_ready() or lobby_id == 0:
		return ERR_UNCONFIGURED
	_steam_call("activateGameOverlayInviteDialog", [lobby_id])
	return OK


func get_friend_persona_name(steam_id: int) -> String:
	if not is_ready() or steam_id == 0:
		return ""
	return str(_steam_call("getFriendPersonaName", [steam_id]))


func get_lobby_member_count(lobby_id: int = 0) -> int:
	var id := lobby_id if lobby_id != 0 else current_lobby_id
	if not is_ready() or id == 0:
		return 0
	return int(_steam_call("getNumLobbyMembers", [id]))


func get_lobby_member_by_index(index: int, lobby_id: int = 0) -> int:
	var id := lobby_id if lobby_id != 0 else current_lobby_id
	if not is_ready() or id == 0:
		return 0
	return int(_steam_call("getLobbyMemberByIndex", [id, index]))


func _steam_shutdown_api() -> void:
	if not initialized:
		return
	if is_api_available():
		var steam := _get_steam_object()
		if steam != null and steam.has_method("steamShutdown"):
			_steam_call("steamShutdown")
			TomeDebug.log("SteamService", "Steam shut down")
	initialized = false


func _initialize_api() -> void:
	var app_id := _read_app_id()
	# Pass app ID so Steamworks sets the environment; embed_callbacks=false (we run in _process).
	var init_result: Variant = _steam_call("steamInitEx", [app_id, false])
	var status := STEAM_INIT_OK
	if init_result is Dictionary:
		status = int(init_result.get("status", STEAM_INIT_OK))
	elif init_result is bool:
		status = STEAM_INIT_OK if init_result else 1

	if status != STEAM_INIT_OK:
		var verbal := ""
		if init_result is Dictionary:
			verbal = str(init_result.get("verbal", ""))
		_disable(
			"Steam unavailable (status=%s): %s — Local and LAN still work."
			% [status, verbal]
		)
		return

	initialized = true
	_bind_steam_signals()
	allow_p2p_relay()
	TomeDebug.log("SteamService", "Steam initialized (app_id=%s)" % app_id)
	api_initialized.emit(true)


func _disable(reason: String) -> void:
	initialized = false
	set_process(false)
	_unbind_steam_signals()
	TomeDebug.log("SteamService", reason)
	api_initialized.emit(false)


func _read_app_id() -> int:
	const APP_ID_PATH := "res://steam_appid.txt"
	if not FileAccess.file_exists(APP_ID_PATH):
		return DEFAULT_APP_ID
	var text := FileAccess.get_file_as_string(APP_ID_PATH).strip_edges()
	if text.is_valid_int():
		return int(text)
	return DEFAULT_APP_ID


func _bind_window_close() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var window := tree.root
	if window is Window:
		var win := window as Window
		if not win.close_requested.is_connected(request_app_quit):
			win.close_requested.connect(request_app_quit)


func _bind_steam_signals() -> void:
	if _signals_bound:
		return
	var steam := _get_steam_object()
	if steam == null:
		return
	steam.lobby_created.connect(_on_lobby_created)
	steam.lobby_joined.connect(_on_lobby_joined)
	steam.lobby_chat_update.connect(_on_lobby_chat_update)
	if steam.has_signal("game_lobby_join_requested"):
		steam.game_lobby_join_requested.connect(_on_game_lobby_join_requested)
	if steam.has_signal("p2p_session_request"):
		steam.p2p_session_request.connect(_on_p2p_session_request)
	_signals_bound = true


func _unbind_steam_signals() -> void:
	if not _signals_bound:
		return
	var steam := _get_steam_object()
	if steam != null:
		if steam.lobby_created.is_connected(_on_lobby_created):
			steam.lobby_created.disconnect(_on_lobby_created)
		if steam.lobby_joined.is_connected(_on_lobby_joined):
			steam.lobby_joined.disconnect(_on_lobby_joined)
		if steam.lobby_chat_update.is_connected(_on_lobby_chat_update):
			steam.lobby_chat_update.disconnect(_on_lobby_chat_update)
		if (
			steam.has_signal("game_lobby_join_requested")
			and steam.game_lobby_join_requested.is_connected(_on_game_lobby_join_requested)
		):
			steam.game_lobby_join_requested.disconnect(_on_game_lobby_join_requested)
		if (
			steam.has_signal("p2p_session_request")
			and steam.p2p_session_request.is_connected(_on_p2p_session_request)
		):
			steam.p2p_session_request.disconnect(_on_p2p_session_request)
	_signals_bound = false


func _get_steam_object() -> Object:
	if Engine.has_singleton("Steam"):
		return Engine.get_singleton("Steam")
	return null


func _steam_call(method: String, args: Array = []) -> Variant:
	if method != "steamInitEx" and not initialized:
		return null
	var steam := _get_steam_object()
	if steam == null:
		return null
	if not steam.has_method(method):
		push_error("SteamService: Steam.%s is not available" % method)
		return null
	return steam.callv(method, args)


func _track_p2p_peer(steam_id: int) -> void:
	if steam_id == 0 or steam_id == get_steam_id():
		return
	_p2p_peers[steam_id] = true


func _close_tracked_p2p_sessions() -> void:
	if not is_ready():
		_p2p_peers.clear()
		return
	for steam_id in _collect_known_remote_steam_ids():
		_track_p2p_peer(steam_id)
	var steam := _get_steam_object()
	var can_close := steam != null and steam.has_method("closeP2PSessionWithUser")
	for steam_id in _p2p_peers.keys():
		var id := int(steam_id)
		if id == 0 or not can_close:
			continue
		_steam_call("closeP2PSessionWithUser", [id])
	_p2p_peers.clear()


func _collect_known_remote_steam_ids() -> Array[int]:
	var ids: Array[int] = []
	if current_lobby_id != 0:
		for index in range(get_lobby_member_count()):
			var member_id := get_lobby_member_by_index(index)
			if member_id != 0 and member_id != get_steam_id() and not ids.has(member_id):
				ids.append(member_id)
	var tree := get_tree() if is_inside_tree() else null
	if tree != null:
		var mp := tree.get_multiplayer()
		if mp != null:
			for session_id in SteamMultiplayerPeerAdapterScript.collect_session_steam_ids(mp):
				var id := int(session_id)
				if id != 0 and id != get_steam_id() and not ids.has(id):
					ids.append(id)
	return ids


func _on_lobby_created(result_code: int, lobby_id: int) -> void:
	if result_code != LOBBY_CREATE_OK:
		lobby_create_finished.emit({"error": ERR_CANT_CREATE, "lobby_id": 0})
		return
	current_lobby_id = lobby_id
	_steam_call("setLobbyJoinable", [lobby_id, true])
	lobby_create_finished.emit({"error": OK, "lobby_id": lobby_id})


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != LOBBY_ENTER_OK:
		lobby_join_finished.emit({"error": ERR_CANT_CONNECT, "lobby_id": 0})
		return
	current_lobby_id = lobby_id
	lobby_join_finished.emit({"error": OK, "lobby_id": lobby_id})


func _on_game_lobby_join_requested(lobby_id: int, _friend_id: int) -> void:
	lobby_invite_received.emit(lobby_id)


func _on_p2p_session_request(remote_steam_id: int) -> void:
	if not is_ready() or remote_steam_id == 0:
		return
	if not _is_known_session_steam_id(remote_steam_id):
		return
	_steam_call("acceptP2PSessionWithUser", [remote_steam_id])
	_track_p2p_peer(remote_steam_id)


func _is_known_session_steam_id(steam_id: int) -> bool:
	if steam_id == get_steam_id():
		return true
	if current_lobby_id != 0:
		for index in range(get_lobby_member_count()):
			if get_lobby_member_by_index(index) == steam_id:
				return true
	var tree := get_tree() if is_inside_tree() else null
	if tree != null:
		var mp := tree.get_multiplayer()
		if mp != null:
			for session_id in SteamMultiplayerPeerAdapterScript.collect_session_steam_ids(mp):
				if int(session_id) == steam_id:
					return true
	return false


func _on_lobby_chat_update(
	_lobby_id: int,
	change_id: int,
	_making_change: int,
	chat_state: int
) -> void:
	if not _is_member_entered(chat_state):
		return
	if change_id == 0:
		return
	if is_ready():
		_steam_call("acceptP2PSessionWithUser", [change_id])
		_track_p2p_peer(change_id)
	lobby_member_joined.emit(change_id)


func _is_member_entered(chat_state: int) -> bool:
	var steam := _get_steam_object()
	if steam != null and steam.get("CHAT_MEMBER_STATE_CHANGE_ENTERED") != null:
		return chat_state == int(steam.CHAT_MEMBER_STATE_CHANGE_ENTERED)
	return chat_state == 1
