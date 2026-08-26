class_name TestMultiplayerTransport
extends RefCounted

const MultiplayerTransportScript := preload("res://scripts/network/multiplayer_transport.gd")


func run() -> int:
	var failures := 0
	failures += _test_default_room_code_is_empty()
	failures += _test_default_host_is_unavailable()
	failures += _test_default_join_is_unavailable()
	return failures


func _test_default_room_code_is_empty() -> int:
	var transport := MultiplayerTransportScript.new()
	if transport.get_room_code() != "":
		push_error("Expected base transport room code to be empty")
		return 1
	return 0


func _test_default_host_is_unavailable() -> int:
	var transport := MultiplayerTransportScript.new()
	var err: Error = transport.host({})
	if err != ERR_UNAVAILABLE:
		push_error("Expected base transport host() to return ERR_UNAVAILABLE")
		return 1
	return 0


func _test_default_join_is_unavailable() -> int:
	var transport := MultiplayerTransportScript.new()
	var err: Error = transport.join({})
	if err != ERR_UNAVAILABLE:
		push_error("Expected base transport join() to return ERR_UNAVAILABLE")
		return 1
	return 0
