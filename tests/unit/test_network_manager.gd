class_name TestNetworkManager
extends RefCounted

const NetworkManagerScript := preload("res://scripts/network/network_manager.gd")
const MultiplayerTransportScript := preload("res://scripts/network/multiplayer_transport.gd")
const LobbyMatchStateScript := preload("res://scripts/match/lobby_match_state.gd")
const GameStateScript := preload("res://scripts/game_state.gd")


func run() -> int:
	var failures := 0
	failures += _test_compute_player_index_for_host_only()
	failures += _test_compute_player_index_for_three_peers()
	failures += _test_disconnect_session_delegates_to_transport()
	failures += _test_end_match_to_menu_does_not_quit()
	failures += _test_collect_lobby_peer_ids()
	failures += _test_client_player_index_from_lobby_roster()
	failures += _test_format_lobby_player_label()
	failures += _test_normalize_lobby_roles()
	failures += _test_pack_roles_for_peers()
	failures += _test_session_mode_index_round_trip()
	failures += _test_host_falls_back_when_steam_unavailable()
	failures += _test_session_host_peer()
	return failures


func _test_compute_player_index_for_host_only() -> int:
	if NetworkManagerScript.compute_player_index_for_peers(1, [1]) != 0:
		push_error("Expected host peer id 1 to map to player index 0")
		return 1
	return 0


func _test_compute_player_index_for_three_peers() -> int:
	var peers: Array = [1, 2, 3]
	if NetworkManagerScript.compute_player_index_for_peers(1, peers) != 0:
		push_error("Expected host to remain player index 0")
		return 1
	if NetworkManagerScript.compute_player_index_for_peers(2, peers) != 1:
		push_error("Expected client peer 2 to map to player index 1")
		return 1
	if NetworkManagerScript.compute_player_index_for_peers(3, peers) != 2:
		push_error("Expected client peer 3 to map to player index 2")
		return 1
	return 0


func _test_collect_lobby_peer_ids() -> int:
	var host_only := NetworkManagerScript.collect_lobby_peer_ids(1, [])
	if host_only != [1]:
		push_error("Expected host-only lobby to contain peer 1")
		return 1

	var host_and_client := NetworkManagerScript.collect_lobby_peer_ids(1, [2])
	if host_and_client != [1, 2]:
		push_error("Expected lobby roster [1, 2] for host with one client")
		return 1

	var client_view := NetworkManagerScript.collect_lobby_peer_ids(2, [1])
	if client_view != [1, 2]:
		push_error("Expected joining client roster [1, 2] when host is in get_peers()")
		return 1
	var client_alone := NetworkManagerScript.collect_lobby_peer_ids(2, [])
	if client_alone != [2]:
		push_error("Expected no invented host peer when remotes are empty, got %s" % str(client_alone))
		return 1
	return 0


func _test_client_player_index_from_lobby_roster() -> int:
	var client_roster := NetworkManagerScript.collect_lobby_peer_ids(2, [1])
	if NetworkManagerScript.compute_player_index_for_peers(2, [2]) != 0:
		push_error("Expected a solo session roster [2] to place peer 2 at index 0")
		return 1
	if client_roster.find(2) != 1:
		push_error("Expected client peer id 2 to be player index 1 in lobby roster")
		return 1
	return 0


func _test_format_lobby_player_label() -> int:
	var peers: Array = [1, 2, 3]
	if NetworkManagerScript.format_lobby_player_label(1, 1, peers) != "Host (You)":
		push_error("Expected host self label")
		return 1
	if NetworkManagerScript.format_lobby_player_label(2, 1, peers) != "Player 2":
		push_error("Expected client label for peer 2")
		return 1
	if NetworkManagerScript.format_lobby_player_label(2, 2, peers) != "Player 2 (You)":
		push_error("Expected client self label for peer 2")
		return 1
	return 0


func _test_disconnect_session_delegates_to_transport() -> int:
	var manager := NetworkManagerScript.new()
	var fake := _FakeTransport.new()
	manager.transport = fake
	manager.is_session_active = true

	manager.disconnect_session()

	if manager.is_session_active:
		push_error("Expected disconnect_session to clear session flag")
		return 1
	if fake.disconnect_calls != 1:
		push_error("Expected disconnect_session to delegate to transport")
		return 1
	return 0


func _test_end_match_to_menu_does_not_quit() -> int:
	var manager := NetworkManagerScript.new()
	var fake := _FakeTransport.new()
	manager.transport = fake
	manager.is_session_active = true
	manager.end_match_to_menu()
	if manager.is_session_active:
		push_error("Expected end_match_to_menu to clear the session")
		return 1
	if fake.disconnect_calls != 1:
		push_error("Expected end_match_to_menu to tear down the transport")
		return 1
	return 0


func _test_normalize_lobby_roles() -> int:
	var normalized := LobbyMatchStateScript.normalize_roles({
		"1": GameStateScript.PlayerRole.APPRENTICE,
		2: GameStateScript.PlayerRole.APPRENTICE,
	})
	if int(normalized[1]) != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected normalized roles to coerce string keys to int")
		return 1
	if int(normalized[2]) != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected normalized roles to preserve int keys")
		return 1
	return 0


func _test_pack_roles_for_peers() -> int:
	var roles := {
		1: GameStateScript.PlayerRole.APPRENTICE,
		2: GameStateScript.PlayerRole.APPRENTICE,
		99: GameStateScript.PlayerRole.APPRENTICE,
	}
	var peers: Array[int] = [1, 2]
	var packed := LobbyMatchStateScript.pack_roles_for_peers(roles, peers)
	if packed.size() != 2:
		push_error("Expected packed roles to include only connected peers")
		return 1
	if int(packed[1]) != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected packed roles to include Apprentice for peer 1")
		return 1
	return 0


func _test_session_mode_index_round_trip() -> int:
	var modes := [
		NetworkManagerScript.SESSION_MODE_LOCAL,
		NetworkManagerScript.SESSION_MODE_LAN,
		NetworkManagerScript.SESSION_MODE_STEAM,
	]
	for mode in modes:
		var index := NetworkManagerScript.session_index_from_mode(mode)
		if NetworkManagerScript.session_mode_from_index(index) != mode:
			push_error("Expected session mode %s to round-trip through slider index" % mode)
			return 1
	if NetworkManagerScript.session_mode_from_index(0) != NetworkManagerScript.SESSION_MODE_LOCAL:
		push_error("Expected slider index 0 to be local")
		return 1
	if NetworkManagerScript.session_index_from_mode("offline") != 0:
		push_error("Expected unknown session mode to map to local")
		return 1
	return 0


func _test_host_falls_back_when_steam_unavailable() -> int:
	if (
		NetworkManagerScript.resolve_requested_host_mode(
			NetworkManagerScript.SESSION_MODE_STEAM, false
		)
		!= NetworkManagerScript.SESSION_MODE_LOCAL
	):
		push_error("Expected Steam host to fall back to local when Steam is unavailable")
		return 1
	if (
		NetworkManagerScript.resolve_requested_host_mode(
			NetworkManagerScript.SESSION_MODE_LAN, false
		)
		!= NetworkManagerScript.SESSION_MODE_LAN
	):
		push_error("Expected LAN host to stay LAN when Steam is unavailable")
		return 1
	if (
		NetworkManagerScript.resolve_requested_host_mode(
			NetworkManagerScript.SESSION_MODE_STEAM, true
		)
		!= NetworkManagerScript.SESSION_MODE_STEAM
	):
		push_error("Expected Steam host to stay Steam when Steam is ready")
		return 1
	var without_steam := NetworkManagerScript.host_transport_option_labels(false)
	if without_steam != PackedStringArray(["Local", "LAN"]):
		push_error("Expected host transport options without Steam to be Local and LAN")
		return 1
	var with_steam := NetworkManagerScript.host_transport_option_labels(true)
	if with_steam != PackedStringArray(["Local", "LAN", "Steam"]):
		push_error("Expected host transport options with Steam to include Steam")
		return 1
	return 0


func _test_session_host_peer() -> int:
	if not NetworkManagerScript.is_session_host_peer(1):
		push_error("Expected peer id 1 to be the session host")
		return 1
	if NetworkManagerScript.is_session_host_peer(2016843338):
		push_error("Expected a joining peer not to be treated as the session host")
		return 1
	if NetworkManagerScript.is_session_host_peer(0):
		push_error("Expected peer id 0 not to be the session host")
		return 1
	return 0


class _FakeTransport extends MultiplayerTransportScript:
	var disconnect_calls := 0

	func disconnect_session() -> void:
		disconnect_calls += 1
