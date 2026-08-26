class_name SmokeTrailManager
extends Node3D

## Renders TrailRegistry samples as fading ground footprints.

const PuffScript := preload("res://scripts/smoke_trail_puff.gd")

var _puffs: Dictionary = {}


func _ready() -> void:
	add_to_group("smoke_trail_manager")
	TrailRegistry.trails_changed.connect(_sync_from_registry)
	_sync_from_registry()


func _sync_from_registry() -> void:
	_purge_invalid_puffs()
	var live_keys: Dictionary = {}
	var trails := TrailRegistry.get_trails()
	for peer_id_variant in trails.keys():
		var peer_id := int(peer_id_variant)
		var color := _color_for_peer(peer_id)
		var samples: Array = trails[peer_id_variant]
		for sample_index in samples.size():
			var sample: Variant = samples[sample_index]
			if sample is not Dictionary:
				continue
			var key := _footprint_key(peer_id, TrailSample.seq(sample))
			live_keys[key] = true
			if _puffs.has(key) and is_instance_valid(_puffs[key]):
				continue
			if _puffs.has(key):
				_puffs.erase(key)
			var direction := _movement_direction(samples, sample_index)
			var foot_side: int = TrailSample.seq(sample)
			var footprint := MeshInstance3D.new()
			footprint.name = "Footprint"
			footprint.set_script(PuffScript)
			add_child(footprint)
			footprint.call("setup_from_sample", sample, color, direction, foot_side)
			_track_puff(key, footprint)

	for key in _puffs.keys():
		if live_keys.has(key):
			continue
		_remove_puff(key)


func _track_puff(key: String, footprint: Node) -> void:
	_puffs[key] = footprint
	if not footprint.tree_exiting.is_connected(_on_puff_tree_exiting):
		footprint.tree_exiting.connect(_on_puff_tree_exiting.bind(key))


func _on_puff_tree_exiting(key: String) -> void:
	_puffs.erase(key)


func _purge_invalid_puffs() -> void:
	for key in _puffs.keys():
		if not is_instance_valid(_puffs[key]):
			_puffs.erase(key)


func _remove_puff(key: String) -> void:
	var puff = _puffs.get(key)
	_puffs.erase(key)
	if puff != null and is_instance_valid(puff):
		puff.queue_free()


func _footprint_key(peer_id: int, seq: int) -> String:
	return "%d:%d" % [peer_id, seq]


func _movement_direction(samples: Array, sample_index: int) -> Vector2:
	if sample_index <= 0:
		return Vector2(0.0, 1.0)
	var current := TrailSample.position(samples[sample_index])
	var previous := TrailSample.position(samples[sample_index - 1])
	var direction := current - previous
	if direction.length_squared() <= 0.0001:
		return Vector2(0.0, 1.0)
	return direction


func _color_for_peer(peer_id: int) -> Color:
	if GameState.is_multiplayer and NetworkManager.is_online():
		return GameState.get_snail_color(NetworkManager.get_player_index_for_peer(peer_id))
	return GameState.get_snail_color(0)
