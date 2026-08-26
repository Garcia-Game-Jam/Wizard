class_name RoleAssignment
extends RefCounted

## Lobby roster helpers. Everyone is an Apprentice.


static func role_label(_role: int = 0) -> String:
	return "Apprentice"


static func count_roles(roles: Dictionary) -> Dictionary:
	return {"apprentices": roles.size(), "headmasters": 0}


static func validate_relaxed_roster(peer_ids: Array, roles: Dictionary) -> Error:
	if peer_ids.is_empty():
		return ERR_INVALID_PARAMETER
	for peer_id in peer_ids:
		if not roles.has(peer_id):
			return ERR_INVALID_PARAMETER
	return OK


static func default_roles_for_peers(peer_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	for peer_id in peer_ids:
		result[int(peer_id)] = GameState.PlayerRole.APPRENTICE
	return result
