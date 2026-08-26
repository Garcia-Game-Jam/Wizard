class_name SimpleVoiceChat
extends Node

## Minimal lobby/game voice: broker-fed mic PCM over Godot multiplayer RPCs.
##
## Local mic is owned by MicCaptureBroker. GameVoiceSession registers
## Listeners/Chat and attaches this engine as the Chat PCM sink. This node
## only handles encode/send + remote playback (mic_volume gain on transmit).
##
## Playback is flat (AudioStreamPlayer) until a caller supplies proximity
## settings plus a world anchor per peer — see [method set_proximity_settings]
## and [method set_peer_anchor]. Anchored peers move to AudioStreamPlayer3D so
## the mix pans with the maze. Flat playback stays the fallback because the
## lobby has no Camera3D and 3D audio needs a listener.
##
## Scene children:
## - Peers: container for per-peer AudioStreamPlayer + AudioStreamGenerator

signal log_message(event: String, detail: String)

const MicGainUtilScript := preload("res://scripts/voice/mic_gain_util.gd")

const LOG_PREFIX := "[friend-slop-voice]"
## Packet magic "FSVC"
const MAGIC_0 := 0x46
const MAGIC_1 := 0x53
const MAGIC_2 := 0x56
const MAGIC_3 := 0x43
const DEFAULT_SAMPLE_RATE := 16000
const FRAME_MSEC := 40
const HEARTBEAT_MSEC := 2000
const SPEAKING_TIMEOUT_MSEC := 350
const RMS_SPEAK_THRESHOLD := 0.01
const NO_PEERS_LOG_MSEC := 5000
const MUTED_DB := -80.0
## Printed without debug_logging: session lifecycle plus every state needed to
## tell "nobody was listening" apart from "packets never arrived".
const ALWAYS_LOG_EVENTS: Array[String] = [
	"started",
	"stopped",
	"start_failed",
	"no_peers",
	"first_send",
	"first_recv",
	"remote_added",
	"proximity",
	"anchor",
]

@export var debug_logging: bool = false
@export var sample_rate: int = DEFAULT_SAMPLE_RATE
@export var transmit_muted: bool = false

var is_active: bool = false

var _local_peer_id: int = 0
var _broker: Node
var _peers_root: Node
var _playback_by_steam_id: Dictionary = {} ## int -> AudioStreamGeneratorPlayback
var _player_by_steam_id: Dictionary = {} ## int -> AudioStreamPlayer or AudioStreamPlayer3D
var _anchor_by_steam_id: Dictionary = {} ## int -> Node3D the peer speaks from
var _proximity: Resource = null ## ProximityChatSettings while match voice is spatial
var _muted_steam_ids: Dictionary = {}
var _gain_by_steam_id: Dictionary = {}
var _last_local_speak_msec: int = 0
var _last_remote_speak_msec: Dictionary = {} ## int -> int
var _pcm_accum: PackedFloat32Array = PackedFloat32Array()
var _debug_sent: int = 0
var _debug_recv: int = 0
var _debug_last_rms: float = 0.0
var _debug_last_msec: int = 0
var _debug_last_send_log_msec: int = 0
var _samples_per_frame: int = 0
var _decim_counter: int = 0
var _logged_first_send: bool = false
var _logged_first_recv: Dictionary = {} ## int -> true
var _no_peers_log_msec: int = 0


func _ready() -> void:
	_ensure_child_nodes()
	set_process(false)


func start() -> void:
	if is_active:
		return
	_ensure_child_nodes()
	_broker = _resolve_broker()
	if _broker == null:
		push_warning("SimpleVoiceChat: MicCaptureBroker missing — cannot start voice")
		_emit_log("start_failed", "no_mic_broker")
		return
	_local_peer_id = _resolve_local_peer_id()
	_samples_per_frame = maxi(1, int(round(float(sample_rate) * float(FRAME_MSEC) / 1000.0)))
	_pcm_accum = PackedFloat32Array()
	_decim_counter = 0
	if _broker.has_method("set"):
		_broker.set("debug_logging", debug_logging)
	## MicCaptureBroker registration is owned by GameVoiceSession Listeners/*.
	## This engine only receives PCM via Chat listener.attach_sink(...).
	is_active = true
	_debug_sent = 0
	_debug_recv = 0
	_logged_first_send = false
	_logged_first_recv.clear()
	_no_peers_log_msec = 0
	_debug_last_msec = Time.get_ticks_msec()
	set_process(true)
	_emit_log("started", "device=%s rate=%d local=%d peers=%s" % [
		AudioServer.get_input_device(),
		sample_rate,
		_local_peer_id,
		str(_remote_peer_ids()),
	])


func stop() -> void:
	if not is_active:
		_teardown_peers()
		return
	is_active = false
	set_process(false)
	_pcm_accum = PackedFloat32Array()
	_teardown_peers()
	_emit_log("stopped", "")


func get_peers() -> Array[int]:
	return _remote_peer_ids()


func prune_stale_peers() -> void:
	_prune_stale_peers()


## Pass the Chat listener's ProximityChatSettings to spatialize playback, or null
## for open mic. Existing peers are rebuilt so nobody keeps the wrong player type.
func set_proximity_settings(settings: Resource) -> void:
	var was_active := is_proximity_active()
	_proximity = settings
	var now_active := is_proximity_active()
	if was_active == now_active:
		return
	for steam_id in _player_by_steam_id.keys():
		_drop_peer_player(int(steam_id))
	_emit_log("proximity", "active=%s" % now_active)


func is_proximity_active() -> bool:
	if _proximity == null or not _proximity.has_method("is_active"):
		return false
	return bool(_proximity.call("is_active"))


## Node this peer's voice comes from in the world — normally their character body.
func set_peer_anchor(steam_id: int, anchor: Node3D) -> void:
	if steam_id == 0:
		return
	if _anchor_by_steam_id.get(steam_id) == anchor:
		return
	_anchor_by_steam_id[steam_id] = anchor
	var spatial := _wants_spatial(steam_id)
	## Rebuild only when the peer is currently mixed the wrong way.
	if _is_spatial_player(_player_by_steam_id.get(steam_id) as Node) != spatial:
		_drop_peer_player(steam_id)
	_emit_log(
		"anchor",
		"steam_id=%d node='%s' spatial=%s"
		% [steam_id, str(anchor.name) if anchor != null else "<none>", spatial]
	)


## Match teardown: every peer drops back to flat playback.
func clear_peer_anchors() -> void:
	for key in _anchor_by_steam_id.keys():
		var steam_id := int(key)
		if _is_spatial_player(_player_by_steam_id.get(steam_id) as Node):
			_drop_peer_player(steam_id)
	_anchor_by_steam_id.clear()


func is_local_speaking(timeout_ms: int = SPEAKING_TIMEOUT_MSEC) -> bool:
	if transmit_muted or _last_local_speak_msec <= 0:
		return false
	return Time.get_ticks_msec() - _last_local_speak_msec <= timeout_ms


func is_remote_speaking(steam_id: int, timeout_ms: int = SPEAKING_TIMEOUT_MSEC) -> bool:
	var last := int(_last_remote_speak_msec.get(steam_id, 0))
	if last <= 0:
		return false
	return Time.get_ticks_msec() - last <= timeout_ms


func is_peer_muted(steam_id: int) -> bool:
	return bool(_muted_steam_ids.get(steam_id, false))


func set_peer_muted(steam_id: int, muted: bool) -> void:
	if steam_id == 0:
		return
	if muted:
		_muted_steam_ids[steam_id] = true
	else:
		_muted_steam_ids.erase(steam_id)
	_apply_remote_volume(steam_id)


func get_peer_volume(steam_id: int) -> float:
	return float(_gain_by_steam_id.get(steam_id, 1.0))


func set_peer_volume(steam_id: int, linear: float) -> void:
	if steam_id == 0:
		return
	_gain_by_steam_id[steam_id] = clampf(linear, 0.0, 1.0)
	_apply_remote_volume(steam_id)


func _process(_delta: float) -> void:
	if not is_active:
		return
	_prune_stale_peers()
	_update_spatial_peers()
	_maybe_heartbeat()


func _on_broker_pcm(mono: PackedFloat32Array, mix_rate: int) -> void:
	if not is_active or mono.is_empty():
		return
	var gain: float = MicGainUtilScript.from_settings()
	var target_rate := float(sample_rate)
	var decim_every := (
		maxi(1, int(round(float(mix_rate) / target_rate))) if target_rate > 0.0 else 1
	)
	var sum_sq := 0.0
	var sum_sq_linear := 0.0
	for sample in mono:
		var linear: float = sample * gain
		sum_sq_linear += linear * linear
		var scaled: float = MicGainUtilScript.apply_sample(sample)
		sum_sq += scaled * scaled
		_decim_counter += 1
		if _decim_counter >= decim_every:
			_decim_counter = 0
			_pcm_accum.append(scaled)
	_debug_last_rms = sqrt(sum_sq / float(mono.size()))
	## VAD uses linear (pre-soft-clip) level so boost does not permanently trip speak.
	if (
		sqrt(sum_sq_linear / float(mono.size())) >= RMS_SPEAK_THRESHOLD
		and not transmit_muted
	):
		_last_local_speak_msec = Time.get_ticks_msec()
	if transmit_muted:
		_pcm_accum.clear()
		return
	while _pcm_accum.size() >= _samples_per_frame:
		var frame_samples := _pcm_accum.slice(0, _samples_per_frame)
		_pcm_accum = _pcm_accum.slice(_samples_per_frame)
		if _frame_rms(frame_samples) < RMS_SPEAK_THRESHOLD * 0.5:
			continue
		var packet := _build_packet(frame_samples)
		_send_to_peers(packet)


func deliver_voice_frame(peer_id: int, raw: PackedByteArray) -> void:
	if not is_active or peer_id <= 0 or raw.is_empty():
		return
	var parsed := _parse_packet(raw)
	if parsed.is_empty():
		return
	var rate := int(parsed.get("sample_rate", sample_rate))
	var pcm: PackedByteArray = parsed.get("pcm", PackedByteArray()) as PackedByteArray
	if pcm.is_empty():
		return
	_push_remote_pcm(peer_id, pcm, rate)
	_last_remote_speak_msec[peer_id] = Time.get_ticks_msec()
	_debug_recv += 1
	if not _logged_first_recv.has(peer_id):
		_logged_first_recv[peer_id] = true
		_emit_log(
			"first_recv",
			"peer_id=%d rate=%d bytes=%d" % [peer_id, rate, pcm.size()]
		)


func _send_to_peers(packet: PackedByteArray) -> void:
	if packet.is_empty():
		return
	var remotes := _remote_peer_ids()
	if remotes.is_empty():
		_log_no_peers()
		return
	var tree := get_tree()
	if tree == null:
		return
	var network := tree.root.get_node_or_null("NetworkManager")
	if network == null or not network.has_method("send_voice_frame"):
		return
	network.call("send_voice_frame", packet)
	_debug_sent += 1
	if not _logged_first_send:
		_logged_first_send = true
		_emit_log("first_send", "bytes=%d to=%s" % [packet.size(), str(remotes)])
	if debug_logging:
		var now := Time.get_ticks_msec()
		if now - _debug_last_send_log_msec >= 250:
			_debug_last_send_log_msec = now
			_emit_log("send_frame", "bytes=%d to=%s" % [packet.size(), remotes])


## Speech was ready to transmit with nobody registered to send it to — the only
## silent discard in the send path, so it must be visible without debug_logging.
func _log_no_peers() -> void:
	var now := Time.get_ticks_msec()
	if _no_peers_log_msec != 0 and now - _no_peers_log_msec < NO_PEERS_LOG_MSEC:
		return
	_no_peers_log_msec = now
	_emit_log("no_peers", "discarding speech frames — peer list is empty")


func _build_packet(samples: PackedFloat32Array) -> PackedByteArray:
	var packet := PackedByteArray()
	packet.resize(6 + samples.size() * 2)
	packet[0] = MAGIC_0
	packet[1] = MAGIC_1
	packet[2] = MAGIC_2
	packet[3] = MAGIC_3
	packet[4] = sample_rate & 0xFF
	packet[5] = (sample_rate >> 8) & 0xFF
	for i in samples.size():
		var s := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		packet.encode_s16(6 + i * 2, s)
	return packet


func _parse_packet(raw: PackedByteArray) -> Dictionary:
	if raw.size() < 8:
		return {}
	if raw[0] != MAGIC_0 or raw[1] != MAGIC_1 or raw[2] != MAGIC_2 or raw[3] != MAGIC_3:
		return {}
	var rate := int(raw[4]) | (int(raw[5]) << 8)
	return {"sample_rate": rate, "pcm": raw.slice(6)}


static func _pcm_bytes_to_mono_floats(buffer: PackedByteArray) -> PackedFloat32Array:
	var sample_count := buffer.size() >> 1
	var out := PackedFloat32Array()
	out.resize(sample_count)
	for i in sample_count:
		out[i] = float(buffer.decode_s16(i * 2)) / 32768.0
	return out


func _push_remote_pcm(steam_id: int, pcm: PackedByteArray, rate: int) -> void:
	if is_peer_muted(steam_id):
		return
	var playback := _ensure_remote_playback(steam_id, rate)
	if playback == null:
		return
	var samples := _pcm_bytes_to_mono_floats(pcm)
	var frames: PackedVector2Array = PackedVector2Array()
	frames.resize(samples.size())
	for i in samples.size():
		var s := samples[i]
		frames[i] = Vector2(s, s)
	var available := playback.get_frames_available()
	if available <= 0:
		return
	if frames.size() > available:
		playback.push_buffer(frames.slice(0, available))
	else:
		playback.push_buffer(frames)


## Never cache a null playback: get_stream_playback() can come back empty on the
## frame the player is created, and a cached null mutes that peer for the rest of
## the session. Re-resolve until it succeeds instead.
func _ensure_remote_playback(steam_id: int, rate: int) -> AudioStreamGeneratorPlayback:
	var playback := _playback_by_steam_id.get(steam_id) as AudioStreamGeneratorPlayback
	if playback != null:
		return playback
	var player := _player_by_steam_id.get(steam_id) as Node
	if player == null or not is_instance_valid(player):
		player = _create_remote_player(steam_id, rate)
	if not bool(player.get("playing")):
		player.call("play")
	playback = player.call("get_stream_playback") as AudioStreamGeneratorPlayback
	if playback == null:
		return null
	_playback_by_steam_id[steam_id] = playback
	return playback


func _create_remote_player(steam_id: int, rate: int) -> Node:
	_ensure_child_nodes()
	var spatial := _wants_spatial(steam_id)
	var player: Node
	if spatial:
		player = AudioStreamPlayer3D.new()
	else:
		player = AudioStreamPlayer.new()
	player.name = "Peer_%d" % steam_id
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = float(rate if rate > 0 else sample_rate)
	stream.buffer_length = 0.35
	player.set("stream", stream)
	player.set("volume_db", _flat_volume_db(steam_id))
	_peers_root.add_child(player)
	if spatial:
		_configure_spatial_player(player as AudioStreamPlayer3D, steam_id)
	player.call("play")
	_player_by_steam_id[steam_id] = player
	_emit_log(
		"remote_added",
		"steam_id=%d rate=%d spatial=%s" % [steam_id, int(stream.mix_rate), spatial]
	)
	return player


## Godot's own falloff is disabled: the authored ProximityChatSettings curve drives
## volume_db instead, so range/dB stay the codified values. Panning still follows
## the emitter position, which is the point of using a 3D player.
func _configure_spatial_player(player: AudioStreamPlayer3D, steam_id: int) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	player.max_distance = 0.0
	## Start silent so a distant peer cannot pop in at full volume. Playback is
	## created from _receive_and_play(), and _update_spatial_peers() runs later in
	## that same _process, so the real level lands before anything is heard.
	player.volume_db = MUTED_DB
	var anchor := _anchor_by_steam_id.get(steam_id) as Node3D
	if anchor != null and is_instance_valid(anchor) and anchor.is_inside_tree():
		player.global_position = anchor.global_position


## Anchored peers pan and attenuate; everyone else stays flat so lobby chat (no
## Camera3D listener) keeps working.
func _wants_spatial(steam_id: int) -> bool:
	if not is_proximity_active():
		return false
	var anchor := _anchor_by_steam_id.get(steam_id) as Node3D
	return anchor != null and is_instance_valid(anchor)


func _is_spatial_player(player: Node) -> bool:
	return player != null and is_instance_valid(player) and player is AudioStreamPlayer3D


func _update_spatial_peers() -> void:
	if not is_proximity_active():
		return
	var camera := _listener_camera()
	if camera == null:
		return
	var listener := camera.global_position
	for key in _player_by_steam_id.keys():
		var steam_id := int(key)
		var player := _player_by_steam_id.get(steam_id) as AudioStreamPlayer3D
		if player == null or not is_instance_valid(player):
			continue
		var anchor := _anchor_by_steam_id.get(steam_id) as Node3D
		if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
			continue
		var speaker_pos := anchor.global_position
		player.global_position = speaker_pos
		player.volume_db = _spatial_volume_db(steam_id, speaker_pos.distance_to(listener))


## The Camera3D is Godot's audio listener, so measuring from it keeps our volume
## curve and Godot's panning agreed on where the local player is. Null means 3D
## audio cannot be mixed at all (no listener), so callers skip the update.
func _listener_camera() -> Camera3D:
	var viewport := get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


func _flat_volume_db(steam_id: int) -> float:
	if is_peer_muted(steam_id):
		return MUTED_DB
	return linear_to_db(maxf(get_peer_volume(steam_id), 0.0001))


func _spatial_volume_db(steam_id: int, distance_m: float) -> float:
	if is_peer_muted(steam_id):
		return MUTED_DB
	## The curve already floors to silence past max_range_m, so that is the cull.
	var falloff_db := float(_proximity.call("volume_db_for_distance", distance_m))
	return falloff_db + linear_to_db(maxf(get_peer_volume(steam_id), 0.0001))


func _apply_remote_volume(steam_id: int) -> void:
	var player := _player_by_steam_id.get(steam_id) as Node
	if player == null or not is_instance_valid(player):
		return
	## Spatial peers get their level from the next _update_spatial_peers pass.
	if _is_spatial_player(player):
		return
	player.set("volume_db", _flat_volume_db(steam_id))


func _drop_peer_player(steam_id: int) -> void:
	var player := _player_by_steam_id.get(steam_id) as Node
	if player != null and is_instance_valid(player):
		player.queue_free()
	_player_by_steam_id.erase(steam_id)
	_playback_by_steam_id.erase(steam_id)


func _prune_stale_peers() -> void:
	var live := _remote_peer_ids()
	var stale: Array[int] = []
	for steam_id in _player_by_steam_id.keys():
		if not live.has(int(steam_id)):
			stale.append(int(steam_id))
	for steam_id in stale:
		_drop_peer_player(steam_id)
		_anchor_by_steam_id.erase(steam_id)
		_last_remote_speak_msec.erase(steam_id)


func _teardown_peers() -> void:
	for steam_id in _player_by_steam_id.keys():
		_drop_peer_player(int(steam_id))
	_player_by_steam_id.clear()
	_playback_by_steam_id.clear()
	_last_remote_speak_msec.clear()


func _ensure_child_nodes() -> void:
	_peers_root = get_node_or_null("Peers")
	if _peers_root == null:
		## Back-compat with older authored "Remotes" name.
		_peers_root = get_node_or_null("Remotes")
	if _peers_root == null:
		_peers_root = Node.new()
		_peers_root.name = "Peers"
		add_child(_peers_root)
	elif _peers_root.name != "Peers":
		_peers_root.name = "Peers"


func _resolve_broker() -> Node:
	var parent := get_parent()
	if parent != null:
		var sibling := parent.get_node_or_null("MicCaptureBroker")
		if sibling != null:
			return sibling
		if parent.has_method("get") and parent.get("mic_broker") != null:
			return parent.get("mic_broker") as Node
	var tree := get_tree()
	if tree != null:
		return tree.get_first_node_in_group("mic_capture_broker")
	return null


func _frame_rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum_sq := 0.0
	for s in samples:
		sum_sq += s * s
	return sqrt(sum_sq / float(samples.size()))


func _resolve_local_peer_id() -> int:
	if not is_inside_tree():
		return 1
	var tree := get_tree()
	if tree != null:
		var mp := tree.get_multiplayer()
		if mp != null:
			return int(mp.get_unique_id())
	return 1


func _remote_peer_ids() -> Array[int]:
	var remotes: Array[int] = []
	if not _has_live_multiplayer():
		return remotes
	for peer_id in get_tree().get_multiplayer().get_peers():
		var id := int(peer_id)
		if id > 0:
			remotes.append(id)
	return remotes


func _has_live_multiplayer() -> bool:
	if not is_inside_tree():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var mp := tree.get_multiplayer()
	if mp == null or mp.multiplayer_peer == null:
		return false
	return mp.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _maybe_heartbeat() -> void:
	if not debug_logging:
		return
	var now := Time.get_ticks_msec()
	if now - _debug_last_msec < HEARTBEAT_MSEC:
		return
	_debug_last_msec = now
	var broker_capturing := false
	if _broker != null and _broker.has_method("is_capturing"):
		broker_capturing = bool(_broker.call("is_capturing"))
	_emit_log(
		"heartbeat",
		(
			"sent=%d recv=%d peers=%s mic_rms=%.4f muted=%s device=%s broker=%s"
			% [
				_debug_sent,
				_debug_recv,
				str(_remote_peer_ids()),
				_debug_last_rms,
				transmit_muted,
				AudioServer.get_input_device(),
				broker_capturing,
			]
		)
	)
	_debug_sent = 0
	_debug_recv = 0


func _emit_log(event: String, detail: String) -> void:
	log_message.emit(event, detail)
	if not debug_logging and not ALWAYS_LOG_EVENTS.has(event):
		return
	if detail.is_empty():
		print("%s %s" % [LOG_PREFIX, event])
	else:
		print("%s %s %s" % [LOG_PREFIX, event, detail])
