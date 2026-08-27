class_name TestPlayerSpawnAuthority
extends RefCounted

## Host owns the body (authority 1). The controlling peer owns Input and the
## first-person camera, decided from owner_peer_id before enter-tree.

const LOCAL_PEER_ID := 1
const REMOTE_PEER_ID := 7


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_remote_body_gives_up_local_view(tree)
	failures += _test_local_body_keeps_local_view(tree)
	failures += _test_host_owns_body_peer_owns_input(tree)
	return failures


func _test_remote_body_gives_up_local_view(tree: SceneTree) -> int:
	var players_root := Node3D.new()
	tree.root.add_child(players_root)
	var failures := 0
	var player := _spawn(players_root, REMOTE_PEER_ID)

	if player == null:
		push_error("Expected a spawned body for peer %d" % REMOTE_PEER_ID)
		failures = 1
	elif _has_live_view_camera(player):
		push_error("Remote body kept the first-person camera")
		failures = 1

	players_root.queue_free()
	return failures


func _test_local_body_keeps_local_view(tree: SceneTree) -> int:
	var players_root := Node3D.new()
	tree.root.add_child(players_root)
	var failures := 0
	var player := _spawn(players_root, LOCAL_PEER_ID)

	if player == null:
		push_error("Expected a spawned body for peer %d" % LOCAL_PEER_ID)
		failures = 1
	elif not _has_live_view_camera(player):
		push_error("Local body should keep its first-person camera")
		failures = 1

	players_root.queue_free()
	return failures


func _test_host_owns_body_peer_owns_input(tree: SceneTree) -> int:
	var players_root := Node3D.new()
	tree.root.add_child(players_root)
	var failures := 0
	var player := _spawn(players_root, REMOTE_PEER_ID)
	if player == null:
		push_error("Expected a spawned body for peer %d" % REMOTE_PEER_ID)
		players_root.queue_free()
		return 1
	if player.get_multiplayer_authority() != 1:
		push_error(
			"Expected host to own body state, got authority %d"
			% player.get_multiplayer_authority()
		)
		failures = 1
	var input := player.get_node_or_null("Input")
	if input == null:
		push_error("Expected peer-owned Input child")
		failures = 1
	elif input.get_multiplayer_authority() != REMOTE_PEER_ID:
		push_error(
			"Expected Input authority %d, got %d"
			% [REMOTE_PEER_ID, input.get_multiplayer_authority()]
		)
		failures = 1
	if player.get_node_or_null("RollbackSynchronizer") == null:
		push_error("Expected RollbackSynchronizer on playable")
		failures = 1
	if player.get_node_or_null("TickInterpolator") == null:
		push_error("Expected TickInterpolator on playable")
		failures = 1
	if player.get_node_or_null("MultiplayerSynchronizer") != null:
		push_error("Playable should not keep MultiplayerSynchronizer")
		failures = 1
	players_root.queue_free()
	return failures


func _spawn(players_root: Node3D, peer_id: int) -> CharacterBody3D:
	NetworkManager.spawn_player_for_peer(
		peer_id,
		players_root,
		func(_player: CharacterBody3D) -> void: pass
	)
	return players_root.get_node_or_null(str(peer_id)) as CharacterBody3D


func _has_live_view_camera(player: CharacterBody3D) -> bool:
	var camera := player.get_node_or_null("%FirstPersonCamera") as Camera3D
	return camera != null and not camera.is_queued_for_deletion()
