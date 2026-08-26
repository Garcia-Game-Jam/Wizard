class_name SpellWardBlock
extends RefCounted

## Shared ward hit resolution for player and monster projectiles.


static func live_node(node: Variant) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if not (node is Node):
		return null
	return node as Node


static func ward_from_node(node: Node) -> Node:
	var walk: Node = node
	while walk != null:
		if walk.is_in_group("spell_ward") and walk.has_method("notify_spell_blocked"):
			return walk
		walk = walk.get_parent()
	return null


## If `body` belongs to a live ward, spend it and return true.
## `damage` is subtracted on HP wards; hit-count wards still spend one cast.
## Pass `ignore_caster` so a monster/player cannot pop their own shield.
static func try_block(
	body: Node, damage: float = 0.0, ignore_caster: Variant = null
) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	var caster := live_node(ignore_caster)
	var ward := ward_from_node(body)
	if ward == null:
		return false
	if caster != null and ward.has_method("is_owned_by"):
		if bool(ward.call("is_owned_by", caster)):
			return false
	ward.call("notify_spell_blocked", damage, caster)
	notify_caster_warded(caster, ward)
	return true


## Swept check for projectiles that teleport along a path (ice bolts, lobs).
static func try_block_along_path(
	tree: SceneTree,
	from: Vector3,
	to: Vector3,
	projectile_radius: float,
	damage: float = 0.0,
	ignore_caster: Variant = null
) -> bool:
	var ward := find_along_path(tree, from, to, projectile_radius, ignore_caster)
	if ward == null:
		return false
	return try_block(ward, damage, ignore_caster)


static func find_along_path(
	tree: SceneTree,
	from: Vector3,
	to: Vector3,
	projectile_radius: float,
	ignore_caster: Variant = null
) -> Node:
	if tree == null:
		return null
	var caster := live_node(ignore_caster)
	var best: Node = null
	var best_dist_sq := INF
	var pad := maxf(projectile_radius, 0.0)
	for node in tree.get_nodes_in_group("spell_ward"):
		if node == null or not node.has_method("notify_spell_blocked"):
			continue
		if not (node is Node3D):
			continue
		if caster != null and node.has_method("is_owned_by"):
			if bool(node.call("is_owned_by", caster)):
				continue
		if node.has_method("is_broken") and bool(node.call("is_broken")):
			continue
		var ward_node := node as Node3D
		var ward_radius := 1.35
		if "radius" in ward_node:
			ward_radius = float(ward_node.get("radius"))
		var reach := ward_radius * 1.15 + pad
		var dist_sq := _segment_distance_sq(from, to, ward_node.global_position)
		if dist_sq <= reach * reach and dist_sq < best_dist_sq:
			best = ward_node
			best_dist_sq = dist_sq
	return best


static func _segment_distance_sq(from: Vector3, to: Vector3, point: Vector3) -> float:
	var delta := to - from
	var len_sq := delta.length_squared()
	var t := 0.0
	if len_sq > 0.0001:
		t = clampf((point - from).dot(delta) / len_sq, 0.0, 1.0)
	var closest := from + delta * t
	return closest.distance_squared_to(point)


## Tell the attacking caster a live ward ate their spell.
static func notify_caster_warded(caster: Variant = null, blocked_by: Node = null) -> void:
	var live := live_node(caster)
	if live is Character:
		(live as Character).on_spell_ward_blocked(blocked_by)
