class_name TestSteamTransport
extends RefCounted

const SteamTransportScript := preload("res://scripts/network/steam_transport.gd")


func run() -> int:
	var failures := 0
	failures += _test_parse_lobby_id()
	failures += _test_validate_lobby_id()
	return failures


func _test_parse_lobby_id() -> int:
	if SteamTransportScript.parse_lobby_id(" 12345 ") != 12345:
		push_error("Expected trimmed lobby id parse")
		return 1
	if SteamTransportScript.parse_lobby_id("") != 0:
		push_error("Expected empty lobby id to parse as 0")
		return 1
	if SteamTransportScript.parse_lobby_id("abc") != 0:
		push_error("Expected invalid lobby id to parse as 0")
		return 1
	return 0


func _test_validate_lobby_id() -> int:
	if SteamTransportScript.validate_lobby_id("999") != OK:
		push_error("Expected valid lobby id to pass validation")
		return 1
	if SteamTransportScript.validate_lobby_id("") != ERR_INVALID_PARAMETER:
		push_error("Expected empty lobby id to fail validation")
		return 1
	return 0
