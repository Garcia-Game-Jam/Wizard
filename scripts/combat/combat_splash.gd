class_name CombatSplash
extends RefCounted

## Detonate connect: combat groups by root distance. Not Area3D overlap.
## ponytail: O(bodies in groups) per detonate; upgrade if dump size makes it hot.

const GROUPS: PackedStringArray = ["monster", "combat_target", "player"]


static func bodies_near(
	tree: SceneTree, origin: Vector3, radius: float, skip: Node = null
) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if tree == null or radius <= 0.0:
		return found
	var radius_sq := radius * radius
	var seen: Dictionary = {}
	for group_name in GROUPS:
		for node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node) or node == skip:
				continue
			if seen.has(node) or not (node is Node3D):
				continue
			var body := node as Node3D
			if body.global_position.distance_squared_to(origin) > radius_sq:
				continue
			seen[node] = true
			found.append(body)
	return found


static func apply_at(
	tree: SceneTree,
	origin: Vector3,
	radius: float,
	from: Variant,
	payload: CombatPayload,
	skip: Node = null
) -> void:
	if payload == null:
		return
	for body in bodies_near(tree, origin, radius, skip):
		if not (body is Character):
			continue
		var aimed := _aim_knock(payload, origin, body.global_position)
		(body as Character).apply(from, aimed)


static func _aim_knock(
	payload: CombatPayload, origin: Vector3, body_pos: Vector3
) -> CombatPayload:
	var needs := false
	for effect in payload.effects:
		if effect is Knock and (effect as Knock).from_impact:
			needs = true
			break
	if not needs:
		return payload
	var copy := payload.duplicate(true) as CombatPayload
	if copy == null:
		return payload
	var dir := body_pos - origin
	for effect in copy.effects:
		if not (effect is Knock):
			continue
		var knock := effect as Knock
		if not knock.from_impact:
			continue
		var horizontal := knock.impulse.x if absf(knock.impulse.x) > 0.0001 else 9.0
		var up := knock.impulse.y if absf(knock.impulse.y) > 0.0001 else 3.5
		knock.impulse = Knock.impulse_from_dir(dir, horizontal, up)
		knock.from_impact = false
	return copy
