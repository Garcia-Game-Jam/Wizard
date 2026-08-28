class_name NetClock
extends RefCounted

## Start/stop netfox NetworkTime with the match, not the lobby.

## Caps how many move_and_slide calls one tick can make (20 m/s dash needs 3).
const _MAX_SLIDE_SUBSTEPS := 8

static var _radius_cache: Dictionary = {}


static func is_ticking() -> bool:
	var nt := _network_time()
	if nt == null:
		return false
	return bool(nt.call("is_initial_sync_done"))


static func tick_delta() -> float:
	var nt := _network_time()
	if nt != null and is_ticking():
		return float(nt.get("ticktime"))
	return 1.0 / 60.0


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
	var history := _autoload("NetworkHistoryServer")
	if history != null and history.has_method("clear_history"):
		history.call("clear_history")
	var rollback := _autoload("NetworkRollback")
	if rollback != null and rollback.has_method("reset_session"):
		rollback.call("reset_session")


static func move_character(body: CharacterBody3D) -> void:
	if body == null:
		return
	if not is_ticking():
		_slide_within_radius(body)
		return
	var nt := _network_time()
	var factor := 1.0
	if nt != null:
		factor = float(nt.get("physics_factor"))
	body.velocity *= factor
	_slide_within_radius(body)
	body.velocity /= factor


## Chunks a slide so each move_and_slide stays inside the collision radius.
static func _slide_within_radius(body: CharacterBody3D) -> void:
	var radius := _collision_radius(body)
	var delta := (
		body.get_physics_process_delta_time()
		if Engine.is_in_physics_frame()
		else body.get_process_delta_time()
	)
	var step := body.velocity.length() * delta
	if radius <= 0.0 or delta <= 0.0 or step <= radius:
		body.move_and_slide()
		return
	var n := mini(ceili(step / radius), _MAX_SLIDE_SUBSTEPS)
	body.velocity /= float(n)
	for _i in n:
		body.move_and_slide()
	body.velocity *= float(n)


static func _collision_radius(body: CharacterBody3D) -> float:
	var id := body.get_instance_id()
	if _radius_cache.has(id):
		return float(_radius_cache[id])
	var radius := 0.0
	for child in body.get_children():
		var col := child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		var shape: Variant = col.shape
		if shape is CapsuleShape3D or shape is SphereShape3D or shape is CylinderShape3D:
			radius = float(shape.get("radius"))
		elif shape is BoxShape3D:
			var size: Vector3 = (shape as BoxShape3D).size
			radius = minf(size.x, size.z) * 0.5
		if radius > 0.0:
			break
	_radius_cache[id] = radius
	return radius


static func _disable_auto_events() -> void:
	var events := _network_events()
	if events != null:
		events.set("enabled", false)


static func _network_time() -> Node:
	return _autoload("NetworkTime")


static func _network_events() -> Node:
	return _autoload("NetworkEvents")


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	return (tree as SceneTree).root.get_node_or_null(node_name)
