class_name MonsterCombatSpacing
extends RefCounted

## Radial keep-away / cast-band locomotion helpers for Monster.

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")


static func apply_keep_away(
	host: CharacterBody3D,
	target: Node3D,
	keep_away_range: float,
	move_speed: float,
	face_cb: Callable
) -> void:
	var to_target := Vector3(
		target.global_position.x - host.global_position.x,
		0.0,
		target.global_position.z - host.global_position.z
	)
	var dist := to_target.length()
	var arrive_eps := 0.5
	face_cb.call(to_target)
	if dist < 0.05:
		host.velocity.x = 0.0
		host.velocity.z = 0.0
		return
	var radial := to_target.normalized()
	if dist < keep_away_range - arrive_eps:
		var retreat_goal := target.global_position - radial * keep_away_range
		var desired_away: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			host.global_position, retreat_goal, move_speed, host.velocity.y
		)
		host.velocity.x = desired_away.x
		host.velocity.z = desired_away.z
		return
	if dist > keep_away_range + arrive_eps:
		var approach_goal := target.global_position - radial * keep_away_range
		var desired_in: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			host.global_position, approach_goal, move_speed, host.velocity.y
		)
		host.velocity.x = desired_in.x
		host.velocity.z = desired_in.z
		return
	host.velocity.x = 0.0
	host.velocity.z = 0.0


static func apply_cast_band(
	host: CharacterBody3D,
	target: Node3D,
	ability: Node,
	move_speed: float,
	face_cb: Callable
) -> void:
	var min_r := float(ability.get("min_cast_range")) if "min_cast_range" in ability else 3.0
	var max_r := float(ability.get("max_cast_range")) if "max_cast_range" in ability else 12.0
	var ideal := (min_r + max_r) * 0.5
	if ability.has_method("preferred_cast_range"):
		ideal = float(ability.call("preferred_cast_range"))
	var to_target := Vector3(
		target.global_position.x - host.global_position.x,
		0.0,
		target.global_position.z - host.global_position.z
	)
	var dist := to_target.length()
	var arrive_eps := 0.45
	face_cb.call(to_target)

	if dist < min_r or dist < ideal - arrive_eps:
		if dist < 0.05:
			host.velocity.x = 0.0
			host.velocity.z = 0.0
			return
		var radial := to_target.normalized()
		var retreat_goal := target.global_position - radial * ideal
		var desired_away: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			host.global_position, retreat_goal, move_speed, host.velocity.y
		)
		host.velocity.x = desired_away.x
		host.velocity.z = desired_away.z
		return

	if dist > max_r or dist > ideal + arrive_eps:
		var radial_in := to_target.normalized()
		var approach_goal := target.global_position - radial_in * ideal
		var desired_in: Vector3 = MonsterAIScript.horizontal_velocity_toward(
			host.global_position, approach_goal, move_speed, host.velocity.y
		)
		host.velocity.x = desired_in.x
		host.velocity.z = desired_in.z
		return

	host.velocity.x = 0.0
	host.velocity.z = 0.0


static func preferred_cast_ideal(ability: Node) -> float:
	var min_r := float(ability.get("min_cast_range")) if "min_cast_range" in ability else 3.0
	var max_r := float(ability.get("max_cast_range")) if "max_cast_range" in ability else 12.0
	var ideal := (min_r + max_r) * 0.5
	if ability.has_method("preferred_cast_range"):
		ideal = float(ability.call("preferred_cast_range"))
	return ideal


static func first_ranged_castable(abilities: Array) -> Node:
	for ability in abilities:
		if "requires_target" in ability and not bool(ability.get("requires_target")):
			continue
		if not bool(ability.call("can_cast")):
			continue
		return ability
	return null


static func preferred_spacing(abilities: Array) -> Node:
	for ability in abilities:
		if "requires_target" in ability and not bool(ability.get("requires_target")):
			continue
		return ability
	if abilities.is_empty():
		return null
	return abilities[0]
