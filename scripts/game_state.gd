extends Node

## Shared game context for arena pit runs.

enum PlayerRole {
	APPRENTICE,
}

const PLAYER_COLORS: Array[Color] = [
	Color(0.92, 0.28, 0.32), # crimson
	Color(0.28, 0.55, 0.95), # azure
	Color(0.35, 0.82, 0.42), # emerald
	Color(0.95, 0.78, 0.22), # gold
	Color(0.72, 0.38, 0.92), # violet
	Color(0.95, 0.48, 0.18), # amber
	Color(0.28, 0.88, 0.86), # teal
	Color(0.95, 0.42, 0.72), # rose
]

var is_multiplayer: bool = false
var run_seed: int = -1
## Shared epoch for deterministic time-driven effects (e.g. clouds). Set once per run.
var match_start_time_msec: int = 0
var peer_roles: Dictionary = {}
var peer_character_configs: Dictionary = {}


func reset_for_new_game() -> void:
	is_multiplayer = false
	run_seed = randi()
	match_start_time_msec = Time.get_ticks_msec()
	peer_roles = {}
	peer_character_configs = {}


func prepare_match(
	match_seed: int,
	roles: Dictionary,
	character_configs: Dictionary = {}
) -> void:
	is_multiplayer = true
	run_seed = match_seed
	## NetworkManager sets the shared epoch immediately after this call.
	match_start_time_msec = 0
	peer_roles = _normalize_peer_roles(roles)
	peer_character_configs = _normalize_peer_configs(character_configs)


func get_local_role() -> PlayerRole:
	var peer_id := 1
	if is_multiplayer:
		var tree := Engine.get_main_loop()
		if tree is SceneTree:
			peer_id = tree.get_multiplayer().get_unique_id()
	return get_role_for_peer(peer_id)


func get_role_for_peer(peer_id: int) -> PlayerRole:
	if peer_roles.has(peer_id):
		return int(peer_roles[peer_id]) as PlayerRole
	return PlayerRole.APPRENTICE


## Team id from lobby character config (spawn clustering).
func get_team_for_peer(peer_id: int) -> int:
	return get_character_config_for_peer(peer_id).team_id


func get_character_config_for_peer(peer_id: int) -> PlayerCharacterConfig:
	if peer_character_configs.has(peer_id):
		return PlayerCharacterConfig.from_dict(peer_character_configs[peer_id])
	return PlayerCharacterConfig.create_default(get_role_for_peer(peer_id))


func apply_solo_dev_loadout(role: int) -> void:
	is_multiplayer = false
	peer_roles = {1: role}
	var config := PlayerCharacterConfig.create_default(role)
	config.role = role
	peer_character_configs = {1: config.to_dict()}


func _normalize_peer_roles(roles: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key in roles.keys():
		normalized[int(key)] = int(roles[key])
	return normalized


func _normalize_peer_configs(configs: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key in configs.keys():
		var entry: Variant = configs[key]
		if entry is Dictionary:
			normalized[int(key)] = PlayerCharacterConfig.from_dict(entry).to_dict()
	return normalized


func get_player_color(player_index: int) -> Color:
	return PLAYER_COLORS[player_index % PLAYER_COLORS.size()]
