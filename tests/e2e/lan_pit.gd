extends SceneTree

## Optional LAN host/guest pit. Driven by tools/run_e2e_lan.py — not make test.
## godot --headless --script res://tests/e2e/lan_pit.gd -- --role=host --port=7778

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const ArenaEncountersScript := preload("res://scripts/arena/arena_encounters.gd")

const DUMP_WAIT_SEC := 25.0
const JOIN_WAIT_SEC := 12.0
const PEER_WAIT_SEC := 12.0
const MATCH_WAIT_SEC := 20.0


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	await process_frame
	var args := _parse_args()
	var role := str(args.get("role", ""))
	var port := int(args.get("port", 0))
	if (role != "host" and role != "guest") or port <= 0:
		_fail("Need --role=host|guest and --port=")
		return
	if _net() == null or _game() == null:
		_fail("Autoloads missing (NetworkManager / GameState)")
		return
	var packed := load("res://scenes/game_app.tscn") as PackedScene
	if packed == null:
		_fail("Could not load game_app.tscn")
		return
	var app := packed.instantiate()
	root.add_child(app)
	await process_frame
	if role == "host":
		await _run_host(port)
	else:
		await _run_guest(port)


func _net() -> Node:
	return root.get_node_or_null("NetworkManager")


func _game() -> Node:
	return root.get_node_or_null("GameState")


func _run_host(port: int) -> void:
	var err: Error = await _net().host_session({
		"mode": "lan",
		"port": port,
	})
	if err != OK:
		_fail("LAN host failed (%s)" % err)
		return
	print("E2E_HOST_LISTENING %d" % port)
	if not await _wait_until("guest peer", PEER_WAIT_SEC, func() -> bool:
		return _net().get_lobby_peer_ids().size() >= 2
	):
		return
	_net().start_game()
	await _assert_match("host")


func _run_guest(port: int) -> void:
	var joined := false
	var deadline := Time.get_ticks_msec() + int(JOIN_WAIT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var err: Error = await _net().join_session("127.0.0.1:%d" % port)
		if err == OK:
			joined = true
			break
		await create_timer(0.25).timeout
	if not joined:
		_fail("LAN join failed")
		return
	await _assert_match("guest")


func _assert_match(role: String) -> void:
	if not await _wait_until("match world", MATCH_WAIT_SEC, func() -> bool:
		return _monsters_root() != null
	):
		return
	if not await _assert_session(role):
		return
	if not await _assert_dump(role):
		return
	print("E2E_OK %s" % role)
	quit(0)


func _assert_session(role: String) -> bool:
	if not bool(_game().get("is_multiplayer")):
		_fail("GameState.is_multiplayer should be set after start_game")
		return false
	var peer_id := root.get_multiplayer().get_unique_id()
	print("E2E_PEER %s %d" % [role, peer_id])
	if role == "host" and peer_id != 1:
		_fail("LAN host must be peer 1, got %d" % peer_id)
		return false
	if role == "guest" and peer_id == 1:
		_fail("LAN guest must not be peer 1")
		return false
	if not await _wait_until("net clock", MATCH_WAIT_SEC, func() -> bool:
		return NetClockScript.is_ticking()
	):
		return false
	print("E2E_CLOCK %s" % role)
	var cover := _cover_block()
	if cover == null or cover.get_node_or_null("RollbackSynchronizer") == null:
		_fail("Cover/Block0 must be enrolled before rewind")
		return false
	print("E2E_COVER %s" % role)
	var tell := _find_named(root, "SpawnTelegraph")
	if tell == null or tell.get_node_or_null("RollbackSynchronizer") == null:
		_fail("SpawnTelegraph must be enrolled before rewind")
		return false
	print("E2E_TELL %s" % role)
	return true


func _assert_dump(role: String) -> bool:
	var dump_name := ArenaEncountersScript.dump_node_name(0, 0)
	if not await _wait_until("dump %s" % dump_name, DUMP_WAIT_SEC, func() -> bool:
		var monsters := _monsters_root()
		return monsters != null and monsters.get_node_or_null(dump_name) != null
	):
		return false
	print("E2E_DUMP %s %s" % [role, dump_name])
	var body := _monsters_root().get_node_or_null(dump_name) as Node3D
	if body == null:
		_fail("Dump node vanished")
		return false
	if body.name.contains("@"):
		_fail("Dump name collided: %s" % body.name)
		return false
	return true


func _monsters_root() -> Node:
	return _find_named(root, "Monsters")


func _cover_block() -> Node:
	var cover := _find_named(root, "Cover")
	if cover == null:
		return null
	return cover.get_node_or_null("Block0")


func _find_named(from: Node, node_name: String) -> Node:
	if from == null:
		return null
	if from.name == node_name:
		return from
	for child in from.get_children():
		var found := _find_named(child, node_name)
		if found != null:
			return found
	return null


func _wait_until(label: String, timeout_sec: float, pred: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await process_frame
	_fail("timeout waiting for %s" % label)
	return false


func _parse_args() -> Dictionary:
	var out := {}
	for raw in OS.get_cmdline_user_args():
		var text := str(raw)
		if not text.begins_with("--"):
			continue
		var pair := text.substr(2).split("=", true, 1)
		if pair.size() != 2:
			continue
		out[pair[0]] = pair[1]
	return out


func _fail(message: String) -> void:
	push_error("E2E_FAIL %s" % message)
	print("E2E_FAIL %s" % message)
	quit(1)
