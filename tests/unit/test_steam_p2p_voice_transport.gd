class_name TestSteamP2PVoiceTransport
extends RefCounted

const SteamP2PVoiceTransportScript := preload(
	"res://scripts/voice/steam_p2p_voice_transport.gd"
)


func run() -> int:
	var failures := 0
	failures += _test_parse_sender_steam_id_remote_key()
	failures += _test_normalize_p2p_packet()
	return failures


func _test_parse_sender_steam_id_remote_key() -> int:
	var packet := {
		"data": PackedByteArray([1, 2, 3]),
		"steam_id_remote": 7654321,
	}
	if SteamP2PVoiceTransportScript.parse_sender_steam_id(packet) != 7654321:
		push_error("Expected steam_id_remote to resolve sender steam id")
		return 1
	return 0


func _test_normalize_p2p_packet() -> int:
	var payload := PackedByteArray([9, 8, 7])
	var normalized := SteamP2PVoiceTransportScript.normalize_p2p_packet({
		"data": payload,
		"steam_id_remote": 42,
	})
	if int(normalized.get("steam_id", 0)) != 42:
		push_error("Expected normalized packet to include steam_id")
		return 1
	if (normalized.get("data", PackedByteArray()) as PackedByteArray) != payload:
		push_error("Expected normalized packet to preserve data payload")
		return 1
	return 0
