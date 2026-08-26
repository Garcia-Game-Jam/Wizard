class_name TestLanTransport
extends RefCounted

const LanTransportScript := preload("res://scripts/network/lan_transport.gd")


func run() -> int:
	var failures := 0
	failures += _test_port_only_is_localhost()
	failures += _test_host_port_pair()
	failures += _test_steam_lobby_id_is_not_lan()
	return failures


func _test_port_only_is_localhost() -> int:
	var endpoint := LanTransportScript.parse_endpoint("7777")
	if str(endpoint.get("host", "")) != "127.0.0.1" or int(endpoint.get("port", 0)) != 7777:
		push_error("Expected port-only LAN join to target localhost:7777")
		return 1
	if not LanTransportScript.is_join_code("7777"):
		push_error("Expected port 7777 to count as a LAN join code")
		return 1
	return 0


func _test_host_port_pair() -> int:
	var endpoint := LanTransportScript.parse_endpoint("192.168.1.20:7777")
	if str(endpoint.get("host", "")) != "192.168.1.20" or int(endpoint.get("port", 0)) != 7777:
		push_error("Expected IP:port LAN join to parse host and port")
		return 1
	return 0


func _test_steam_lobby_id_is_not_lan() -> int:
	if LanTransportScript.is_join_code("109775241000000000"):
		push_error("Steam lobby ids must not be treated as LAN endpoints")
		return 1
	if not LanTransportScript.parse_endpoint("abc").is_empty():
		push_error("Garbage join text must not parse as LAN")
		return 1
	return 0
