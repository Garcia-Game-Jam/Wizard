class_name LobbyMatchState
extends RefCounted

## Pre-match roster, roles, and character configs (host syncs via NetworkManager RPCs).

var roles: Dictionary = {}
var character_configs: Dictionary = {}


func reset() -> void:
	roles = {}
	character_configs = {}


func get_role(peer_id: int) -> int:
	if roles.has(peer_id):
		return int(roles[peer_id])
	return GameState.PlayerRole.APPRENTICE


func get_character_config(peer_id: int) -> Dictionary:
	if character_configs.has(peer_id):
		return character_configs[peer_id].duplicate(true)
	var config := PlayerCharacterConfig.create_default(get_role(peer_id))
	return config.to_dict()


func set_default_roles(peer_ids: Array[int]) -> void:
	roles = RoleAssignment.default_roles_for_peers(peer_ids)
	_ensure_default_configs(peer_ids)


func ensure_roles_for_peers(peer_ids: Array[int]) -> bool:
	var changed := false
	for peer_id in peer_ids:
		if not roles.has(peer_id):
			roles[peer_id] = GameState.PlayerRole.APPRENTICE
			changed = true
	if _ensure_default_configs(peer_ids):
		changed = true
	return changed


func apply_role(peer_id: int, _role: int = 0) -> void:
	roles[peer_id] = GameState.PlayerRole.APPRENTICE
	_update_config_role(peer_id, GameState.PlayerRole.APPRENTICE)


func apply_character_config(peer_id: int, config_data: Dictionary) -> void:
	var config := PlayerCharacterConfig.from_dict(config_data)
	config.role = get_role(peer_id)
	character_configs[peer_id] = config.to_dict()


func remove_peer(peer_id: int) -> bool:
	var changed := false
	if roles.erase(peer_id):
		changed = true
	if character_configs.erase(peer_id):
		changed = true
	return changed


func can_start(peer_ids: Array[int]) -> bool:
	return RoleAssignment.validate_relaxed_roster(peer_ids, roles) == OK


func get_start_block_reason(peer_ids: Array[int]) -> String:
	if can_start(peer_ids):
		return ""
	if peer_ids.is_empty():
		return "Need at least one connected player."
	return "Waiting for player roles to sync."


static func pack_roles_for_peers(roles_map: Dictionary, peer_ids: Array[int]) -> Dictionary:
	var packed: Dictionary = {}
	for peer_id in peer_ids:
		if roles_map.has(peer_id):
			packed[peer_id] = int(roles_map[peer_id])
	return packed


static func pack_character_configs_for_peers(
	configs_map: Dictionary,
	peer_ids: Array[int]
) -> Dictionary:
	var packed: Dictionary = {}
	for peer_id in peer_ids:
		if configs_map.has(peer_id):
			packed[peer_id] = configs_map[peer_id].duplicate(true)
	return packed


static func normalize_roles(roles_map: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key in roles_map.keys():
		normalized[int(key)] = int(roles_map[key])
	return normalized


static func normalize_character_configs(configs_map: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key in configs_map.keys():
		var entry: Variant = configs_map[key]
		if entry is Dictionary:
			normalized[int(key)] = PlayerCharacterConfig.from_dict(entry).to_dict()
	return normalized


func _ensure_default_configs(peer_ids: Array[int]) -> bool:
	var changed := false
	for peer_id in peer_ids:
		if character_configs.has(peer_id):
			continue
		character_configs[peer_id] = PlayerCharacterConfig.create_default(get_role(peer_id)).to_dict()
		changed = true
	return changed


func _update_config_role(peer_id: int, role: int) -> void:
	var config := PlayerCharacterConfig.from_dict(get_character_config(peer_id))
	config.role = role
	character_configs[peer_id] = config.to_dict()
