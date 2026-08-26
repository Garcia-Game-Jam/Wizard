class_name NetClock
extends RefCounted

## Start/stop netfox NetworkTime with the match, not the lobby.


static func is_ticking() -> bool:
	var nt := _network_time()
	if nt == null:
		return false
	return bool(nt.call("is_initial_sync_done"))


static func is_session_multiplayer() -> bool:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return false
	var state := (tree as SceneTree).root.get_node_or_null("GameState")
	return state != null and bool(state.get("is_multiplayer"))


static func start_for_match() -> void:
	_disable_auto_events()
	var nt := _network_time()
	if nt == null:
		push_error("NetClock: NetworkTime autoload missing")
		return
	if is_ticking():
		return
	await nt.start()


static func stop() -> void:
	var nt := _network_time()
	if nt == null:
		return
	nt.stop()


static func move_character(body: CharacterBody3D) -> void:
	if body == null:
		return
	if not is_ticking():
		body.move_and_slide()
		return
	var nt := _network_time()
	var factor := 1.0
	if nt != null:
		factor = float(nt.get("physics_factor"))
	body.velocity *= factor
	body.move_and_slide()
	body.velocity /= factor


static func _disable_auto_events() -> void:
	var events := _network_events()
	if events != null:
		events.set("enabled", false)


static func _network_time() -> Node:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	return (tree as SceneTree).root.get_node_or_null("NetworkTime")


static func _network_events() -> Node:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	return (tree as SceneTree).root.get_node_or_null("NetworkEvents")
