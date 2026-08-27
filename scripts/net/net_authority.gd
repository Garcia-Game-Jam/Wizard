class_name NetAuthority
extends RefCounted

## Host owns rewindable body state. The controlling peer owns only Input.

const NetClockScript := preload("res://scripts/net/net_clock.gd")

const HOST_PEER_ID := 1


static func session_host_peer_id() -> int:
	return HOST_PEER_ID


static func should_simulate(node: Node) -> bool:
	if node == null:
		return false
	if not NetClockScript.is_session_multiplayer():
		return true
	if not node.is_inside_tree():
		return true
	return node.is_multiplayer_authority()


static func should_predict_or_simulate(player: Node) -> bool:
	if player == null:
		return false
	if not NetClockScript.is_session_multiplayer():
		return true
	if is_local_owner(player):
		return true
	return should_simulate(player)


static func is_local_owner(player: Node) -> bool:
	if player == null:
		return false
	if player.has_method("is_local_owner"):
		return bool(player.call("is_local_owner"))
	if not NetClockScript.is_session_multiplayer():
		return true
	if not player.is_inside_tree():
		return true
	return player.is_multiplayer_authority()
