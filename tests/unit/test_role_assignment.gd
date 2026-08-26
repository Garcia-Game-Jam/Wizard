class_name TestRoleAssignment
extends RefCounted

const GameStateScript := preload("res://scripts/game_state.gd")
const RoleAssignmentScript := preload("res://scripts/match/role_assignment.gd")


func run() -> int:
	var failures := 0
	failures += _test_default_roles_all_apprentice()
	failures += _test_relaxed_two_player_roster()
	failures += _test_relaxed_one_player_roster()
	failures += _test_rejects_empty_or_missing()
	return failures


func _test_default_roles_all_apprentice() -> int:
	var peers: Array = [1, 2, 3]
	var roles := RoleAssignmentScript.default_roles_for_peers(peers)
	var counts := RoleAssignmentScript.count_roles(roles)
	if counts.headmasters != 0:
		push_error("Expected default roles to assign no Headmaster")
		return 1
	if counts.apprentices != 3:
		push_error("Expected default roles to assign every peer as Apprentice")
		return 1
	if int(roles[1]) != GameStateScript.PlayerRole.APPRENTICE:
		push_error("Expected lowest peer id to be an Apprentice")
		return 1
	if RoleAssignmentScript.role_label(0) != "Apprentice":
		push_error("Expected role label to be Apprentice")
		return 1
	return 0


func _test_relaxed_two_player_roster() -> int:
	var peers: Array = [1, 2]
	var roles := {
		1: GameStateScript.PlayerRole.APPRENTICE,
		2: GameStateScript.PlayerRole.APPRENTICE,
	}
	if RoleAssignmentScript.validate_relaxed_roster(peers, roles) != OK:
		push_error("Expected roster to allow two apprentices")
		return 1
	return 0


func _test_relaxed_one_player_roster() -> int:
	var peers: Array = [1]
	var roles := {1: GameStateScript.PlayerRole.APPRENTICE}
	if RoleAssignmentScript.validate_relaxed_roster(peers, roles) != OK:
		push_error("Expected roster to allow a single player")
		return 1
	return 0


func _test_rejects_empty_or_missing() -> int:
	if RoleAssignmentScript.validate_relaxed_roster([], {}) == OK:
		push_error("Expected empty peer list to fail validation")
		return 1
	var peers: Array = [1, 2]
	var roles := {1: GameStateScript.PlayerRole.APPRENTICE}
	if RoleAssignmentScript.validate_relaxed_roster(peers, roles) == OK:
		push_error("Expected roster missing a peer role to fail validation")
		return 1
	return 0
