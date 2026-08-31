class_name TestEmberLobProjectile
extends RefCounted

## Lob must leave the caster. Payload is Damage only (no knock). Spawn origin is
## the authored hand Marker3D — keep it clear of the capsule in the scene.

const EmberScene := preload("res://scenes/monsters/ember_wretch.tscn")
const PlayerScene := preload("res://scenes/characters/player.tscn")
const EmberLobScene := preload("res://scenes/monsters/abilities/ember_lob_projectile.tscn")
const LOB_HIT_RADIUS := 0.18


func run(tree: SceneTree) -> int:
	var failures := 0
	failures += _test_impact_damages_nearby_player_without_knockback(tree)
	failures += _test_authored_hands_clear_lob_sphere(tree)
	failures += _test_hands_follow_ember_move(tree)
	failures += _test_first_step_does_not_detonate_on_caster(tree)
	failures += _test_replica_without_caster_does_not_detonate_on_ember(tree)
	return failures


func _holder(tree: SceneTree) -> Node3D:
	var holder := Node3D.new()
	tree.root.add_child(holder)
	return holder


func _test_impact_damages_nearby_player_without_knockback(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var player := PlayerScene.instantiate() as Character
	holder.add_child(player)
	player.global_position = Vector3(0.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	var max_hp := player.max_health
	var lob := EmberLobScene.instantiate() as EmberLobProjectile
	holder.add_child(lob)
	lob.global_position = Vector3(0.0, 0.2, 0.4)
	lob.monitoring = true
	lob.call("_finish", true)
	var err := ""
	if is_equal_approx(player.current_health, max_hp):
		err = (
			"Expected ember lob impact near the player to spend HP; stayed at %.1f/%.1f"
			% [player.current_health, max_hp]
		)
	elif player.velocity.length_squared() > 0.01:
		err = "Ember lob must not knock the player back (velocity %s)" % player.velocity
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_authored_hands_clear_lob_sphere(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var ember := EmberScene.instantiate() as Character
	holder.add_child(ember)
	ember.global_position = Vector3.ZERO
	var col := ember.get_node_or_null("%CollisionShape3D") as CollisionShape3D
	var err := ""
	if col == null or not (col.shape is CapsuleShape3D):
		err = "Ember must have an authored capsule"
	else:
		for path in ["%RightHand", "%LeftHand"]:
			var hand := ember.get_node_or_null(path) as Node3D
			if hand == null:
				err = "Missing %s" % path
				break
			var gap := _gap_outside_capsule(col, hand.global_position)
			if gap < LOB_HIT_RADIUS:
				err = (
					"%s is %.3fm outside the capsule; need >= %.2fm for lob hit_radius"
					% [path, gap, LOB_HIT_RADIUS]
				)
				break
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_hands_follow_ember_move(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var ember := EmberScene.instantiate() as Character
	holder.add_child(ember)
	ember.global_position = Vector3.ZERO
	var hand := ember.get_node_or_null("%RightHand") as Node3D
	var err := ""
	if hand == null:
		err = "Missing %RightHand"
	else:
		var local := hand.position
		ember.global_position = Vector3(4.0, 0.0, -3.0)
		var expected := ember.to_global(local)
		if hand.global_position.distance_to(expected) > 0.001:
			err = (
				"RightHand must follow the ember (got %s, expected %s)"
				% [hand.global_position, expected]
			)
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_first_step_does_not_detonate_on_caster(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var ember := EmberScene.instantiate() as Character
	holder.add_child(ember)
	ember.global_position = Vector3.ZERO
	var origin := _hand_origin(ember)
	var lob := EmberLobScene.instantiate() as EmberLobProjectile
	holder.add_child(lob)
	lob.global_position = origin
	lob.setup(ember, origin + Vector3(0.0, 0.0, -6.0))
	lob.call("_simulate_flight", 1.0 / 60.0)
	var err := ""
	if bool(lob.get("_finished")):
		err = "Host lob must not detonate on the caster's first flight step"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _test_replica_without_caster_does_not_detonate_on_ember(tree: SceneTree) -> int:
	var holder := _holder(tree)
	var ember := EmberScene.instantiate() as Character
	holder.add_child(ember)
	ember.global_position = Vector3.ZERO
	var origin := _hand_origin(ember)
	var lob := EmberLobProjectile.spawn(
		holder, origin, null, null, true, origin + Vector3(0.0, 0.0, -6.0)
	)
	var err := ""
	if lob == null:
		err = "Replica spawn must return a lob"
	else:
		lob.call("_simulate_flight", 1.0 / 60.0)
		if bool(lob.get("_finished")):
			err = "Guest replica must not detonate on the ember when caster was omitted"
	holder.queue_free()
	if err.is_empty():
		return 0
	push_error(err)
	return 1


func _hand_origin(ember: Node3D) -> Vector3:
	var hand := ember.get_node_or_null("%RightHand") as Node3D
	if hand != null:
		return hand.global_position
	return ember.global_position + Vector3(0.22, 0.36, -0.32)


func _gap_outside_capsule(col: CollisionShape3D, point: Vector3) -> float:
	var cap := col.shape as CapsuleShape3D
	var center := col.global_position
	var half := cap.height * 0.5 - cap.radius
	var local := point - center
	var closest := center + Vector3(0.0, clampf(local.y, -half, half), 0.0)
	return point.distance_to(closest) - cap.radius
