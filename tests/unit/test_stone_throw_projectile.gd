class_name TestStoneThrowProjectile
extends RefCounted

## Does a thrown stone actually connect and hurt/knock back what it hits?
##
## Both tests call internal methods directly rather than driving real flight via
## _simulate_flight() in a loop: Area3D.direct_space_state only reflects state as
## of the last completed physics step, and this suite's run() cannot await one
## (the harness calls run() synchronously — see test_spell_pipeline.gd's polling
## workaround for the same constraint). A manual _simulate_flight() loop with no
## elapsed physics frame reliably reports zero overlaps even for two shapes sitting
## exactly on top of each other, which would look like a hit-detection bug but
## isn't one — confirmed by isolated --script repros that awaited real
## physics_frame ticks and then got correct intersect_shape results every time.
##
## What IS worth covering here: that a landed hit actually damages/knocks back
## (_finish), and that the splash-radius group scan (_apply_splash_at) — the
## thing that makes a real hit forgiving of a creature's collision capsule not
## being centered on its root position — reaches a target by distance, not by
## requiring pixel-exact shape overlap.

const WretchScene := preload("res://scenes/monsters/evaluating/wretch.tscn")
const StoneThrowScene := preload("res://scenes/spells/stone_throw/stone_throw.tscn")


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_finish_applies_damage_and_knockback(tree)
	failures += _test_splash_reaches_nearby_target_by_distance(tree)
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
	stone.global_position = pos
	stone._direction = direction.normalized()
	return stone


func _test_finish_applies_damage_and_knockback(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := _spawn_target(holder, Vector3(0.0, 1.0, 5.0))
	var max_hp := target.health.max_health
	var stone := _spawn_stone(holder, Vector3(0.0, 1.0, 4.7), Vector3(0.0, 0.0, 1.0))

	stone.call("_finish", true, true)

	var err := ""
	if is_equal_approx(target.health.current_health, max_hp):
		err = (
			"Expected _finish(apply_splash=true) near the target to damage it; "
			+ "HP stayed at %.1f/%.1f"
		) % [target.health.current_health, max_hp]
	elif target.velocity.length_squared() < 0.01:
		err = "Expected the splash hit to also knock the target back (velocity ~0)"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


## Places the target near, but not exactly at, the impact point — the scenario a
## precise-only hit sphere used to miss because a character's collision capsule
## sits well above its root position. _apply_splash_at measures to the target's
## own global_position (root), so this only needs splash_radius, no shape overlap.
func _test_splash_reaches_nearby_target_by_distance(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var target := _spawn_target(holder, Vector3(0.4, 1.0, 3.6))
	var max_hp := target.health.max_health
	var stone := _spawn_stone(holder, Vector3(0.0, 1.0, 3.0), Vector3(0.0, 0.0, 1.0))
	stone.splash_radius = 1.0

	stone.call("_apply_splash_at", stone.global_position)

	var err := ""
	if is_equal_approx(target.health.current_health, max_hp):
		err = (
			"Expected a target %.2fm from impact (within splash_radius=%.1f) to take "
			+ "damage; HP stayed at %.1f/%.1f"
		) % [
			stone.global_position.distance_to(target.global_position),
			stone.splash_radius,
			target.health.current_health,
			max_hp,
		]
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1
