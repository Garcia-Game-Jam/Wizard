class_name SteamP2PVoiceTransport
extends RefCounted

## Steam P2P send/recv for voice PCM packets. No Steam Voice capture API.

var available: bool = false

var _steam: Object


func _init() -> void:
	_refresh_available()


func send_packet(steam_id: int, data: PackedByteArray, p2p_channel: int) -> void:
	if not _refresh_available() or data.is_empty() or steam_id == 0:
		return
	var send_type := _p2p_send_unreliable_no_delay()
	_steam.call("sendP2PPacket", steam_id, data, send_type, p2p_channel)


func read_packets(p2p_channel: int, max_packet_size: int = 8192) -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	if not _refresh_available() or not _steam.has_method("readP2PPacket"):
		return packets
	while _steam.has_method("getAvailableP2PPacketSize"):
		var available_size := int(_steam.call("getAvailableP2PPacketSize", p2p_channel))
		if available_size <= 0:
			break
		var packet_size := mini(available_size, max_packet_size)
		var result: Variant = _steam.call("readP2PPacket", packet_size, p2p_channel)
		if not result is Dictionary:
			break
		var data: Dictionary = result
		if data.is_empty():
			break
		var payload: PackedByteArray = data.get("data", PackedByteArray()) as PackedByteArray
		if payload.is_empty():
			break
		packets.append(normalize_p2p_packet(data))
	return packets


static func parse_sender_steam_id(data: Dictionary) -> int:
	for key in ["steam_id", "steam_id_remote", "remote_steam_id", "steamIDRemote"]:
		if data.has(key):
			return int(data[key])
	return 0


static func normalize_p2p_packet(data: Dictionary) -> Dictionary:
	return {
		"data": data.get("data", PackedByteArray()) as PackedByteArray,
		"steam_id": parse_sender_steam_id(data),
	}


static func pcm_bytes_to_mono_floats(buffer: PackedByteArray) -> PackedFloat32Array:
	var sample_count := buffer.size() >> 1
	var out := PackedFloat32Array()
	out.resize(sample_count)
	for i in sample_count:
		var offset := i * 2
		var sample := buffer.decode_s16(offset)
		out[i] = float(sample) / 32768.0
	return out


func _refresh_available() -> bool:
	if not SteamService.is_ready():
		_steam = null
		available = false
		return false
	if _steam == null and Engine.has_singleton("Steam"):
		_steam = Engine.get_singleton("Steam")
	available = _steam != null
	return available


func _p2p_send_unreliable_no_delay() -> int:
	if _steam != null and _steam.get("P2P_SEND_UNRELIABLE_NO_DELAY") != null:
		return int(_steam.get("P2P_SEND_UNRELIABLE_NO_DELAY"))
	## GodotSteam 4.x P2P_SEND_UNRELIABLE_NO_DELAY fallback
	return 2
