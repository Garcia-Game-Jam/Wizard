class_name NetClock
extends RefCounted

## Start/stop netfox NetworkTime with the match, not the lobby.

## Debug-only tunnelling guard state, keyed by instance id.
static var _tunnel_warned: Dictionary = {}
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
	_warn_if_tunnelling(body)
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


## Every character moves through move_character, so this one check guards the
## whole class of speed bugs. A body that travels further than its own collision
## radius in a tick can penetrate geometry; rollback then resimulates from inside
## the wall and move_and_slide resolves to zero displacement -- the mid-air stall
## (see docs/netcode/diagnostics.md). Debug builds only.
static func _warn_if_tunnelling(body: CharacterBody3D) -> void:
	if not OS.is_debug_build():
		return
	var radius := _collision_radius(body)
	if radius <= 0.0:
		return
	var step := body.velocity.length() * tick_delta()
	var ratio := step / radius
	if ratio <= 1.0:
		return
	## High-water mark: a known violator (dash) warns once, and only a worse
	## violation warns again. A per-tick warning would train us to ignore it.
	var id := body.get_instance_id()
	var worst := float(_tunnel_warned.get(id, 1.0))
	if ratio <= worst * 1.25:
		return
	_tunnel_warned[id] = ratio
	push_warning(
		"NetClock: %s moves %.2f m/tick (%.1fx its %.2f m collision radius) — "
		% [body.name, step, ratio, radius]
		+ "it can penetrate geometry and stall on the other peer."
	)


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
