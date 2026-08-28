class_name NetLiveness
extends RefCounted

## Tick-loop spawn/despawn and engine-physics skip for rewindable bodies.
## Projectiles: after_spawn() from spawn(). NPCs / cover / orbs: attach().
## Motion: skip_engine_physics() in _physics_process; _rollback_tick on the
## moving node; activate/deactivate/despawn_or_free instead of queue_free.

const NetClockScript := preload("res://scripts/net/net_clock.gd")
const NetRewindableMoverScript := preload("res://scripts/net/net_rewindable_mover.gd")


static func skip_engine_physics() -> bool:
	return NetClockScript.is_ticking() and not Engine.is_editor_hint()


## Rollback still ticks deactivated / visual-only areas. Godot errors if we
## query overlaps while monitoring is off.
static func can_query_overlaps(node: Node) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	if node is Area3D:
		return (node as Area3D).monitoring
	return true


static func after_spawn(node: Node3D) -> void:
	if node == null or not node.is_inside_tree() or not NetClockScript.is_ticking():
		return
	NetRewindableMoverScript.apply_projectile(node)


static func replicate_world_fx(kind: String, origin: Vector3, extra: Dictionary) -> void:
	## Guests do not see PredictiveSynchronizer spawns. This is the replica door.
	## load() avoids a parse cycle with NetThreatFx -> ember scenes -> NetLiveness.
	(load("res://scripts/net/net_threat_fx.gd") as GDScript).call(
		"broadcast", kind, origin, extra
	)


static func attach(node: Node, profile: String = "") -> void:
	if node == null or not node.is_inside_tree():
		return
	if not NetClockScript.is_session_multiplayer():
		return
	NetRewindableMoverScript.apply_world_prop(node, profile)


static func commit_pose(node: Node) -> void:
	if node == null:
		return
	NetRewindableMoverScript.commit_world_pose(node)


static func activate(node: Node) -> void:
	if node == null:
		return
	if "visible" in node:
		node.set("visible", true)
	if node is Area3D:
		var area := node as Area3D
		area.monitoring = true
		area.monitorable = true
	if "_finished" in node:
		node.set("_finished", false)
	if "_done" in node:
		node.set("_done", false)
	if "_playing" in node:
		node.set("_playing", true)


static func deactivate(node: Node) -> void:
	if node == null:
		return
	if "visible" in node:
		node.set("visible", false)
	if node is Area3D:
		var area := node as Area3D
		area.monitoring = false
		area.monitorable = false


static func despawn_or_free(node: Node) -> void:
	if node == null:
		return
	var predictive := node.get_node_or_null("PredictiveSynchronizer")
	if NetClockScript.is_ticking() and predictive != null and predictive.has_method("despawn"):
		predictive.call("despawn")
		return
	node.queue_free()
