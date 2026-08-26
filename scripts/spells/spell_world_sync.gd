class_name SpellWorldSync
extends RefCounted

## Thin multiplayer contract for SpellSyncLane.WORLD_OBJECT props.
## Spawn via SpellEffectSync wire; mutate/despawn via one shared event RPC.
## Ephemeral projectiles (fireball) use SpellEphemeralFx instead — no spawn_id.

const KIND_LIGHT_BALL := "light_ball"
const KIND_RELIC_CLONE := "relic_clone"

const EVENT_REMOVE := "remove"
const EVENT_FLICKER := "flicker"

const GROUP_NAME := "spell_world_object"
const BUCKET_LIGHT_BALLS := "LightBalls"
const BUCKET_RELIC_CLONES := "RelicClones"

const LIGHT_BALL_FIND_DIST := 2.25


static func make_spawn_id(player: CharacterBody3D = null) -> String:
	var peer := 0
	if player != null and player.is_inside_tree() and player.multiplayer != null:
		peer = int(player.multiplayer.get_unique_id())
	return "%d_%d" % [peer, Time.get_ticks_usec()]


static func make_cell_id(cell: Vector2i) -> String:
	return "%d_%d" % [cell.x, cell.y]


static func parse_cell_id(id: String) -> Vector2i:
	if id.is_empty() or not id.contains("_"):
		return Vector2i(-1, -1)
	var parts := id.split("_")
	if parts.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func register(node: Node, kind: String, object_id: String) -> void:
	if node == null or kind.is_empty():
		return
	node.set_meta("spell_world_kind", kind)
	node.set_meta("spell_world_id", object_id)
	if not node.is_in_group(GROUP_NAME):
		node.add_to_group(GROUP_NAME)
	if not node.is_in_group(kind):
		node.add_to_group(kind)


static func get_kind(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method("get_spell_world_kind"):
		return str(node.call("get_spell_world_kind"))
	if node.has_meta("spell_world_kind"):
		return str(node.get_meta("spell_world_kind"))
	return ""


static func get_id(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method("get_spell_world_id"):
		return str(node.call("get_spell_world_id"))
	if node.has_meta("spell_world_id"):
		return str(node.get_meta("spell_world_id"))
	var spawn_id: Variant = node.get("spawn_id")
	if spawn_id is String:
		return str(spawn_id)
	return ""


static func ensure_bucket(world: Node, bucket_name: String) -> Node:
	if world == null:
		return null
	var bucket := world.get_node_or_null(bucket_name)
	if bucket != null:
		return bucket
	bucket = Node3D.new()
	bucket.name = bucket_name
	world.add_child(bucket)
	return bucket


static func find(tree: SceneTree, kind: String, object_id: String) -> Node3D:
	if tree == null or kind.is_empty() or object_id.is_empty():
		return null
	for node in tree.get_nodes_in_group(kind):
		if node is Node3D and get_id(node) == object_id:
			return node as Node3D
	return null


static func find_nearest(
	tree: SceneTree,
	kind: String,
	mark: Vector3,
	max_dist: float = LIGHT_BALL_FIND_DIST
) -> Node3D:
	if tree == null or kind.is_empty():
		return null
	var best: Node3D = null
	var best_dist := max_dist * max_dist
	for node in tree.get_nodes_in_group(kind):
		if not node is Node3D:
			continue
		var dist := (node as Node3D).global_position.distance_squared_to(mark)
		if dist < best_dist:
			best_dist = dist
			best = node as Node3D
	return best


static func resolve(
	tree: SceneTree,
	kind: String,
	object_id: String,
	mark: Vector3
) -> Node3D:
	var found := find(tree, kind, object_id)
	if found != null:
		return found
	if kind == KIND_LIGHT_BALL or kind == KIND_RELIC_CLONE:
		return find_nearest(tree, kind, mark)
	return null


static func apply_event(
	tree: SceneTree,
	kind: String,
	event: String,
	object_id: String,
	mark: Vector3
) -> bool:
	var node := resolve(tree, kind, object_id, mark)
	if node == null:
		return false
	match event:
		EVENT_REMOVE:
			if node.has_method("destroy_from_spell"):
				node.call("destroy_from_spell", true)
				return true
		EVENT_FLICKER:
			if node.has_method("flicker"):
				node.call("flicker", true, false)
				return true
			if node.has_method("apply_spell_world_event"):
				node.call("apply_spell_world_event", event, true)
				return true
		_:
			if node.has_method("apply_spell_world_event"):
				node.call("apply_spell_world_event", event, true)
				return true
	return false


static func broadcast_event(node: Node, event: String) -> void:
	if node == null or event.is_empty():
		return
	if not _is_multiplayer_match() or not _allows_gameplay_actions():
		return
	var kind := get_kind(node)
	var object_id := get_id(node)
	if kind.is_empty() or object_id.is_empty():
		return
	var mark := Vector3.ZERO
	if node is Node3D:
		mark = (node as Node3D).global_position
	_send_event(kind, event, object_id, mark)


static func _is_multiplayer_match() -> bool:
	var state := _autoload("GameState")
	return state != null and bool(state.get("is_multiplayer"))


static func _allows_gameplay_actions() -> bool:
	var manager := _autoload("MatchStateManager")
	return manager != null and bool(manager.call("allows_gameplay_actions"))


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)


static func _send_event(
	kind: String,
	event: String,
	object_id: String,
	mark: Vector3
) -> void:
	var tree := Engine.get_main_loop()
	if tree == null or not (tree is SceneTree):
		return
	var mp := (tree as SceneTree).get_multiplayer()
	if mp == null or not mp.has_multiplayer_peer():
		return
	var network := _autoload("NetworkManager")
	if network == null:
		return
	if mp.is_server():
		network.rpc("_rpc_spell_world_event", kind, event, object_id, mark.x, mark.y, mark.z)
	else:
		network.rpc_id(
			1, "_request_spell_world_event", kind, event, object_id, mark.x, mark.y, mark.z
		)
