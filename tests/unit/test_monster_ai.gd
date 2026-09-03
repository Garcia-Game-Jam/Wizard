class_name TestMonsterAi
extends RefCounted

## Shared hunt brain: target-priority scoring, last-known memory, seek goal.

const MonsterAIScript := preload("res://scripts/monsters/monster_ai.gd")
const MonsterTargetMemoryScript := preload("res://scripts/monsters/monster_target_memory.gd")


func run() -> int:
	var failures := 0
	failures += _test_priority_prefers_nearer()
	failures += _test_priority_in_view_bonus()
	failures += _test_priority_stickiness()
	failures += _test_target_memory_notes_and_expires()
	failures += _test_seek_goal_centroid_of_spawns()
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
