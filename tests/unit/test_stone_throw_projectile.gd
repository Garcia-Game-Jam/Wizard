class_name TestStoneThrowProjectile
extends RefCounted

## Thrown stone connects on overlap and spends Damage+Knock. Nearby-without-overlap
## is not a hit. Flight coverage still awaits a real physics_frame.

const WretchScene := preload("res://scenes/monsters/evaluating/wretch.tscn")
const StoneThrowScene := preload("res://scenes/spells/stone_throw/stone_throw.tscn")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_finish_applies_damage_and_knockback(tree)
	failures += _test_nearby_without_overlap_does_not_hit(tree)
	failures += _test_two_overlapping_bodies_both_apply(tree)
	failures += _test_catchup_does_apply_payload(tree)
	failures += await _test_connect_awaits_physics_frame(tree)
	return failures


func _holder(tree: SceneTree) -> Node3D:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	return holder


func _spawn_target(holder: Node3D, pos: Vector3) -> Character:
	var target := WretchScene.instantiate() as Character
	holder.add_child(target)
	target.global_position = pos
	return target


func _spawn_stone(holder: Node3D, pos: Vector3, direction: Vector3) -> StoneThrowProjectile:
	var stone := StoneThrowScene.instantiate() as StoneThrowProjectile
	holder.add_child(stone)
	stone.setup_launch(pos, direction)
	return stone


func _test_finish_applies_damage_and_knockback(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := _spawn_target(holder, Vector3(0.0, 1.0, 5.0))
	var max_hp := target.max_health
	var stone := _spawn_stone(holder, Vector3(0.0, 1.0, 5.0), Vector3(0.0, 0.0, 1.0))

	stone.call("_finish", true)

	var err := ""
	if is_equal_approx(target.current_health, max_hp):
		err = (
			"Expected _finish on an overlapping stone to damage the target; "
			+ "HP stayed at %.1f/%.1f"
		) % [target.current_health, max_hp]
	elif target.velocity.length_squared() < 0.01:
		err = "Expected the overlapping hit to also knock the target back (velocity ~0)"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_nearby_without_overlap_does_not_hit(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := _spawn_target(holder, Vector3(0.0, 1.0, 4.0))
	var max_hp := target.max_health
	var stone := _spawn_stone(holder, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))

	stone.call("_finish", true)

	var err := ""
	if not is_equal_approx(target.current_health, max_hp):
		err = "A target the hit sphere never overlapped must not take damage"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_two_overlapping_bodies_both_apply(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var a := _spawn_target(holder, Vector3(0.0, 1.0, 5.0))
	var b := _spawn_target(holder, Vector3(0.15, 1.0, 5.0))
	var a_hp := a.max_health
	var b_hp := b.max_health
	var stone := _spawn_stone(holder, Vector3(0.08, 1.0, 5.0), Vector3(0.0, 0.0, 1.0))

	stone.call("_finish", true)

	var err := ""
	if is_equal_approx(a.current_health, a_hp) or is_equal_approx(b.current_health, b_hp):
		err = "Both overlapping bodies must take the payload"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_catchup_does_apply_payload(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := _spawn_target(holder, Vector3(0.0, 1.0, 5.0))
	var max_hp := target.max_health
	var stone := _spawn_stone(holder, Vector3(0.0, 1.0, 5.0), Vector3(0.0, 0.0, 1.0))
	stone.call("_finish", true)
	var ok := not is_equal_approx(target.current_health, max_hp)
	holder.queue_free()
	if ok:
		return 0
	push_error("Catch-up _finish must spend the payload (combat stays on)")
	return 1


func _test_connect_awaits_physics_frame(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := _spawn_target(holder, Vector3(0.0, 1.0, 2.0))
	var max_hp := target.max_health
	var stone := _spawn_stone(holder, Vector3(0.0, 1.0, 0.2), Vector3(0.0, 0.0, 1.0))
	for _i in 45:
		await tree.physics_frame
		if not is_instance_valid(stone):
			break
	var damaged := is_instance_valid(target) and target.current_health < max_hp
	holder.queue_free()
	if damaged:
		return 0
	push_error(
		"Expected a stone flown across physics frames to connect and spend HP"
	)
	return 1
