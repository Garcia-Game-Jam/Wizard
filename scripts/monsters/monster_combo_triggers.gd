class_name MonsterComboTriggers
extends RefCounted

## Shared combo trigger helpers for Ice Caster and Ember Caster.

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")


static func resolve_attacking_player(from: Node, monster: Node) -> Node3D:
	if from != null and is_instance_valid(from):
		if from.is_in_group("player") and from is Node3D:
			return from as Node3D
		if "_caster" in from:
			var caster_n3 := MonsterAIScript.live_node3d(from.get("_caster"))
			if caster_n3 != null and caster_n3.is_in_group("player"):
				return caster_n3
		var node: Node = from
		while node != null:
			if node.is_in_group("player") and node is Node3D:
				return node as Node3D
			node = node.get_parent()
	if monster is Monster:
		var aggro := (monster as Monster).get_aggro_player_target()
		if aggro != null:
			return aggro
	return nearest_player(monster)


static func nearest_player(monster: Node) -> Node3D:
	if monster == null:
		return null
	var tree := monster.get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_dist := INF
	for node in tree.get_nodes_in_group("player"):
		var n3 := MonsterAIScript.live_node3d(node)
		if n3 == null:
			continue
		var dist := MonsterAIScript.horizontal_distance(
			monster.global_position, n3.global_position
		)
		if dist < best_dist:
			best_dist = dist
			best = n3
	return best


static func is_player_within_range(
	monster: Node, player: Node3D, range_m: float
) -> bool:
	var live := MonsterAIScript.live_node3d(player)
	if monster == null or live == null:
		return false
	return (
		MonsterAIScript.horizontal_distance(monster.global_position, live.global_position)
		<= range_m
	)
