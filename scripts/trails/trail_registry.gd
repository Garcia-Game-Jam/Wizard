extends Node

## Host-authoritative position history for smoke trails. Clients mirror via RPC.

signal trails_changed

const TrailSampleScript := preload("res://scripts/trails/trail_sample.gd")
const NODE_LIFETIME_SEC := 150.0
const MAX_SAMPLES_PER_PEER := 500
const MIN_SAMPLE_DISTANCE_SQ := 0.3 * 0.3
const MAX_SAMPLE_SPEED := 9.0

var _trails: Dictionary = {}
var _reveal_until_msec: int = 0
var _last_sample_pos: Dictionary = {}
var _last_sample_time_msec: Dictionary = {}


func reset() -> void:
	_trails.clear()
	_reveal_until_msec = 0
	_last_sample_pos.clear()
	_last_sample_time_msec.clear()
	trails_changed.emit()


func reveal_trails(duration_sec: float) -> void:
	var until := Time.get_ticks_msec() + int(maxf(duration_sec, 0.0) * 1000.0)
	_reveal_until_msec = maxi(_reveal_until_msec, until)
	trails_changed.emit()


func is_revealed() -> bool:
	return Time.get_ticks_msec() < _reveal_until_msec


func get_node_lifetime_sec() -> float:
	return NODE_LIFETIME_SEC


func get_trails() -> Dictionary:
	return _trails.duplicate(true)


func get_samples_for_peer(peer_id: int) -> Array:
	var samples: Variant = _trails.get(peer_id, [])
	if samples is Array:
		return samples.duplicate(true)
	return []


func submit_sample(seq: int, x: float, z: float) -> void:
	if not GameState.is_multiplayer:
		_host_accept_sample(1, seq, x, z)
		return
	if not multiplayer.is_server():
		if not MatchStateManager.allows_gameplay_actions():
			return
		NetworkManager._submit_trail_sample.rpc_id(1, seq, x, z)
		return
	_host_accept_sample(multiplayer.get_unique_id(), seq, x, z)


func host_accept_sample(peer_id: int, seq: int, x: float, z: float) -> void:
	if not multiplayer.is_server():
		return
	_host_accept_sample(peer_id, seq, x, z)


func client_apply_sample(peer_id: int, seq: int, x: float, z: float, time_msec: int) -> void:
	if multiplayer.is_server():
		return
	_append_sample(peer_id, seq, x, z, time_msec)


func _host_accept_sample(peer_id: int, seq: int, x: float, z: float) -> void:
	if not _validate_sample(peer_id, seq, x, z):
		return
	var time_msec := Time.get_ticks_msec()
	_append_sample(peer_id, seq, x, z, time_msec)
	if GameState.is_multiplayer:
		NetworkManager._broadcast_trail_sample.rpc(peer_id, seq, x, z, time_msec)


func _validate_sample(peer_id: int, seq: int, x: float, z: float) -> bool:
	if seq < 0:
		return false
	var pos := Vector2(x, z)
	if _last_sample_pos.has(peer_id):
		var last_pos: Vector2 = _last_sample_pos[peer_id]
		if pos.distance_squared_to(last_pos) < MIN_SAMPLE_DISTANCE_SQ:
			return false
		if _last_sample_time_msec.has(peer_id):
			var last_time: int = _last_sample_time_msec[peer_id]
			var elapsed_sec := maxf((Time.get_ticks_msec() - last_time) / 1000.0, 0.001)
			var speed := pos.distance_to(last_pos) / elapsed_sec
			if speed > MAX_SAMPLE_SPEED:
				return false
	var samples: Array = _trails.get(peer_id, [])
	for existing in samples:
		if existing is Dictionary and TrailSampleScript.seq(existing) == seq:
			return false
	return true


func _append_sample(peer_id: int, seq: int, x: float, z: float, time_msec: int) -> void:
	if not _trails.has(peer_id):
		_trails[peer_id] = []
	var samples: Array = _trails[peer_id]
	samples.append(TrailSampleScript.make(seq, x, z, time_msec))
	_last_sample_pos[peer_id] = Vector2(x, z)
	_last_sample_time_msec[peer_id] = time_msec
	_prune_peer(peer_id)
	trails_changed.emit()


func _prune_peer(peer_id: int) -> void:
	if not _trails.has(peer_id):
		return
	var cutoff := Time.get_ticks_msec() - int(NODE_LIFETIME_SEC * 1000.0)
	var samples: Array = _trails[peer_id]
	var kept: Array = []
	for sample in samples:
		if sample is Dictionary and TrailSampleScript.time_msec(sample) >= cutoff:
			kept.append(sample)
	if kept.size() > MAX_SAMPLES_PER_PEER:
		kept = kept.slice(kept.size() - MAX_SAMPLES_PER_PEER, kept.size())
	_trails[peer_id] = kept


func _process(_delta: float) -> void:
	var changed := false
	for peer_id in _trails.keys():
		var before: int = (_trails[peer_id] as Array).size()
		_prune_peer(int(peer_id))
		if (_trails[peer_id] as Array).size() != before:
			changed = true
	if changed:
		trails_changed.emit()
