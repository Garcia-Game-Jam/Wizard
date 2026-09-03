class_name TestMonsterAi
extends RefCounted

## Shared hunt brain: target-priority scoring, last-known memory, seek goal.

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterTargetMemoryScript := preload("res://scripts/monsters/monster_target_memory.gd")
const CollisionLayersScript := preload("res://scripts/collision_layers.gd")
const MonsterRangeGizmosScript := preload("res://scripts/monsters/monster_range_gizmos.gd")


func run() -> int:
	var failures := 0
	failures += _test_priority_prefers_nearer()
	failures += _test_priority_in_view_bonus()
	failures += _test_priority_stickiness()
	failures += _test_target_memory_notes_and_expires()
	failures += _test_seek_goal_centroid_of_spawns()
	failures += await _test_avoid_obstacles()
	failures += await _test_charge_staging()
	failures += _test_charger_distance_specs()
	return failures


func _add_marker(parent: Node, marker_name: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	parent.add_child(m)
	m.global_position = pos


func _score(pos: Vector3, seen: bool, is_current: bool, facing := Vector3(0, 0, -1)) -> float:
	return MonsterAIScript.score_player_target(
		Vector3.ZERO, facing, pos, 20.0, seen, is_current
	)


func _test_priority_prefers_nearer() -> int:
	var near := _score(Vector3(0, 0, -4), true, false)
	var far := _score(Vector3(0, 0, -16), true, false)
	if near <= far:
		push_error("priority: nearer player (%.2f) did not outscore farther (%.2f)" % [near, far])
		return 1
	return 0


func _test_priority_in_view_bonus() -> int:
	# Same distance; one dead ahead, one behind.
	var ahead := _score(Vector3(0, 0, -8), true, false)
	var behind := _score(Vector3(0, 0, 8), true, false)
	if ahead <= behind:
		push_error("priority: in-view player (%.2f) did not beat one behind (%.2f)" % [ahead, behind])
		return 1
	return 0


func _test_priority_stickiness() -> int:
	# Farther current target should still beat a slightly nearer newcomer.
	var current_far := _score(Vector3(0, 0, -9), true, true)
	var fresh_near := _score(Vector3(0, 0, -8), true, false)
	if current_far <= fresh_near:
		push_error(
			"priority: stickiness bonus did not hold the current target (%.2f vs %.2f)"
			% [current_far, fresh_near]
		)
		return 1
	# But a much nearer newcomer should win.
	var fresh_close := _score(Vector3(0, 0, -2), true, false)
	if fresh_close <= current_far:
		push_error("priority: a much closer newcomer should override stickiness")
		return 1
	return 0


func _test_target_memory_notes_and_expires() -> int:
	var mem := MonsterTargetMemoryScript.new()
	mem.configure(2.0)
	if mem.has_goal():
		push_error("memory: fresh memory should have no goal")
		return 1
	mem.note_seen(42, Vector3(1, 0, 2))
	if not mem.has_goal() or mem.last_goal() != Vector3(1, 0, 2) or mem.target_id() != 42:
		push_error("memory: note_seen did not record the goal / id")
		return 1
	mem.tick(1.0)
	if not mem.has_goal():
		push_error("memory: forgot the goal before memory_sec elapsed")
		return 1
	mem.tick(1.5)
	if mem.has_goal():
		push_error("memory: kept the goal past memory_sec")
		return 1
	return 0


func _test_seek_goal_centroid_of_spawns() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("seek goal: expected a SceneTree")
		return 1
	var root := Node3D.new()
	tree.root.add_child(root)
	_add_marker(root, "PlayerSpawn_0", Vector3(2, 0, 10))
	_add_marker(root, "PlayerSpawn_1", Vector3(-2, 0, 14))
	_add_marker(root, "Cover", Vector3(50, 0, 50))

	var goal := MonsterAIScript.hunt_seek_goal(root, Vector3(0, 1, 0))
	root.queue_free()
	if not goal.is_equal_approx(Vector3(0, 1, 12)):
		push_error("seek goal: expected spawn centroid (0,1,12), got %s" % goal)
		return 1
	var empty_goal := MonsterAIScript.hunt_seek_goal(null, Vector3(3, 1, 3))
	if empty_goal != Vector3(3, 1, 3):
		push_error("seek goal: null root should return the fallback")
		return 1
	return 0


func _test_avoid_obstacles() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("avoid: expected a SceneTree")
		return 1
	var world := Node3D.new()
	tree.root.add_child(world)
	# A wall blocking the straight line from origin toward +Z.
	var block := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 4, 1)
	cs.shape = box
	block.add_child(cs)
	block.collision_layer = CollisionLayersScript.WORLD
	block.collision_mask = 0
	world.add_child(block)
	block.global_position = Vector3(0, 0, 5)
	await tree.physics_frame  # let the static body register with the physics space
	var w := world.get_world_3d()

	var from := Vector3(0, 0, 0)
	var goal := Vector3(0, 0, 10)
	var nav := MonsterAIScript.avoid_obstacles(w, from, goal, RID())
	var clear := MonsterAIScript.avoid_obstacles(w, from, Vector3(12, 0, 0), RID())
	world.queue_free()
	await tree.process_frame

	if absf(nav.x) < 1.0:
		push_error("avoid: blocked lane was not steered aside (nav=%s)" % nav)
		return 1
	if clear != Vector3(12, 0, 0):
		push_error("avoid: a clear lane should return the goal unchanged (got %s)" % clear)
		return 1
	return 0


func _test_charge_staging() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("staging: expected a SceneTree")
		return 1
	var world := Node3D.new()
	tree.root.add_child(world)
	await tree.physics_frame
	var w := world.get_world_3d()
	var player := Vector3(0, 0, 0)
	var charger := Vector3(3, 0, 0)
	# Open arena: some clean bearing at stage_range should always resolve.
	var stage := MonsterAIScript.pick_charge_staging(w, charger, player, 8.0, 0.85, 1.5, RID())
	world.queue_free()
	await tree.process_frame
	if not bool(stage.get("ok")):
		push_error("staging: open space should give a clean staging spot")
		return 1
	var pos: Vector3 = stage.get("pos")
	if absf(pos.distance_to(player) - 8.0) > 0.75:
		push_error("staging: spot should sit ~stage_range from the player (got %s)" % pos)
		return 1
	return 0


func _test_charger_distance_specs() -> int:
	var radii := [10.0, 8.0, 3.0, 0.85, 3.0, 15.0, 0.55, 2.5]
	var all: Array = MonsterRangeGizmosScript.charger_distance_specs(radii, 0)
	if all.size() != radii.size():
		push_error("specs: 'All' should return one ring per distance (got %d)" % all.size())
		return 1
	var one: Array = MonsterRangeGizmosScript.charger_distance_specs(radii, 2)
	if one.size() != 1 or str(one[0].get("name")) != "charge_stage_range":
		push_error("specs: pick=2 should return only charge_stage_range (got %s)" % one)
		return 1
	return 0
