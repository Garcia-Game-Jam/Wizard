extends Node

## Autoload: read-only client view + host helpers for synced MatchState.

signal snapshot_changed(snapshot: Dictionary)

var snapshot: Dictionary = {}


func reset() -> void:
	snapshot = {}
	snapshot_changed.emit(snapshot)


func apply_snapshot(data: Dictionary) -> void:
	snapshot = data.duplicate(true)
	snapshot_changed.emit(snapshot)


func get_phase() -> MatchState.Phase:
	return MatchState.phase_from_int(int(snapshot.get("phase", MatchState.Phase.LOBBY)))


func is_gameplay_active() -> bool:
	if snapshot.is_empty():
		return false
	return MatchState.is_gameplay_phase(get_phase())


func allows_gameplay_actions() -> bool:
	if not GameState.is_multiplayer:
		return true
	if not NetworkManager.is_session_active:
		return false
	return is_gameplay_active()


func get_role_for_peer(peer_id: int) -> int:
	var roles: Variant = GameState.peer_roles
	if roles is Dictionary and roles.has(peer_id):
		return int(roles[peer_id])
	return GameState.PlayerRole.APPRENTICE


func log_summary() -> void:
	if snapshot.is_empty():
		return
	var phase_name := MatchState.phase_to_string(get_phase())
	TomeDebug.log(
		"MatchState",
		"phase=%s anchors=%s/%s dread=%s sealed=%s"
		% [
			phase_name,
			snapshot.get("anchors_activated", 0),
			snapshot.get("anchor_count", 0),
			snapshot.get("headmaster_dread", 0),
			snapshot.get("sealed_peers", {}).size(),
		]
	)
