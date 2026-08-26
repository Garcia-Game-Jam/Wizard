class_name MonsterChaseLocomotion
extends RefCounted

## Spacing-only chase locomotion for caster monsters (no auto cast initiation).

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterCombatSpacingScript := preload("res://scripts/monsters/monster_combat_spacing.gd")


static func tick(monster: Node, delta: float, target: Node3D) -> void:
	if not monster.has_method("_interest_is_actionable"):
		return
	var interest = monster.get("_interest")
	if not bool(monster.call("_interest_is_actionable", interest)):
		if monster.has_method("_cancel_cast"):
			monster.call("_cancel_cast")
		if monster.has_method("_clear_chase_move"):
			monster.call("_clear_chase_move")
		monster.velocity.x = 0.0
		monster.velocity.z = 0.0
		return
	var goal: Vector3 = interest.call("resolved_goal_position", monster.global_position)
	if monster.has_method("_try_tick_chase_reposition"):
		if bool(monster.call("_try_tick_chase_reposition", delta, target)):
			return
	if monster.has_method("_tick_chase_reposition_wait"):
		if bool(monster.call("_tick_chase_reposition_wait", delta, target)):
			return
	_tick_approach_spacing_only(monster, goal, target)


static func _tick_approach_spacing_only(monster: Node, goal: Vector3, target: Node3D) -> void:
	var close_in := int(monster.get("chase_style")) == 0
	if (
		close_in
		and target != null
		and is_instance_valid(target)
		and monster.has_method("_has_ranged_spacing_abilities")
		and bool(monster.call("_has_ranged_spacing_abilities"))
	):
		var abilities: Variant = monster.call("get_combat_abilities")
		var awaiting: Variant = MonsterCombatSpacingScript.first_ranged_castable(abilities)
		if awaiting != null:
			monster.call("_move_toward_cast_range", target, awaiting)
			return
		var spacer: Variant = MonsterCombatSpacingScript.preferred_spacing(abilities)
		if spacer != null:
			monster.call("_move_toward_cast_range", target, spacer)
			return
	var keep_away := int(monster.get("chase_style")) == 1
	if keep_away and target != null and is_instance_valid(target):
		if monster.has_method("_move_keep_away"):
			monster.call("_move_keep_away", target)
		return
	var to_goal := Vector3(
		goal.x - monster.global_position.x,
		0.0,
		goal.z - monster.global_position.z
	)
	var attack_range := float(monster.get("attack_range"))
	if to_goal.length() <= attack_range:
		monster.velocity.x = 0.0
		monster.velocity.z = 0.0
		if target != null and is_instance_valid(target) and monster.has_method("_try_touch_damage"):
			monster.call("_try_touch_damage", target)
		return
	var desired: Vector3 = MonsterAIScript.horizontal_velocity_toward(
		monster.global_position, goal, float(monster.get("move_speed")), monster.velocity.y
	)
	monster.velocity.x = desired.x
	monster.velocity.z = desired.z
	if monster.has_method("_face_horizontal"):
		monster.call("_face_horizontal", desired)
