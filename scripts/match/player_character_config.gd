class_name PlayerCharacterConfig
extends RefCounted

## Lobby character setup payload (synced per peer before match start).

var role: int = 0 ## GameState.PlayerRole.APPRENTICE
## Matches ApprenticeSpawn_* index; same team_id → shared spawn cluster.
var team_id: int = 0


static func create_default(for_role: int = 0) -> PlayerCharacterConfig:
	var config := PlayerCharacterConfig.new()
	config.role = for_role
	return config


static func from_dict(data: Dictionary) -> PlayerCharacterConfig:
	var config := PlayerCharacterConfig.new()
	config.role = int(data.get("role", 0))
	config.team_id = maxi(int(data.get("team_id", 0)), 0)
	return config


func to_dict() -> Dictionary:
	return {"role": role, "team_id": team_id}


func summary() -> String:
	return RoleLoadout.role_label(role)


func get_starting_spell_ids() -> Array[String]:
	return RoleLoadout.get_starting_spell_ids(role)
