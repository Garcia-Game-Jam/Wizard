class_name TestArenaRun
extends RefCounted

const ArenaRunScript := preload("res://scripts/arena/arena_run.gd")

const QUEUE: Array[String] = ["ward", "haste", "pull"]


func run() -> int:
	var failures := 0
	failures += _test_three_fights_grant_once()
	failures += _test_six_fights_grant_twice()
	failures += _test_empty_queue_grants_nothing()
	failures += _test_exhausted_queue_stops_granting()
	failures += _test_snapshot_round_trip()
	return failures


func _test_three_fights_grant_once() -> int:
	var arena := ArenaRunScript.create(QUEUE)
	if arena.complete_fight() != "":
		push_error("Fight 1 must not grant a spell")
		return 1
	if arena.complete_fight() != "":
		push_error("Fight 2 must not grant a spell")
		return 1
	if arena.complete_fight() != "ward":
		push_error("Fight 3 must grant the first queued spell")
		return 1
	if arena.fights_into_cycle() != 0:
		push_error("Cycle should reset after a grant")
		return 1
	if arena.cycle_index() != 1:
		push_error("First grant is the start of cycle 1")
		return 1
	return 0


func _test_six_fights_grant_twice() -> int:
	var arena := ArenaRunScript.create(QUEUE)
	for _i in 3:
		arena.complete_fight()
	if arena.complete_fight() != "":
		push_error("Fight 4 must not grant")
		return 1
	if arena.complete_fight() != "":
		push_error("Fight 5 must not grant")
		return 1
	if arena.complete_fight() != "haste":
		push_error("Fight 6 must grant the second queued spell")
		return 1
	if arena.granted_spell_ids != ["ward", "haste"]:
		push_error("Granted list should be ward then haste")
		return 1
	return 0


func _test_empty_queue_grants_nothing() -> int:
	var arena := ArenaRunScript.create()
	for _i in 3:
		if arena.complete_fight() != "":
			push_error("Empty queue must never grant")
			return 1
	return 0


func _test_exhausted_queue_stops_granting() -> int:
	var arena := ArenaRunScript.create(["ward"])
	arena.complete_fight()
	arena.complete_fight()
	if arena.complete_fight() != "ward":
		push_error("Expected sole queued grant on fight 3")
		return 1
	arena.complete_fight()
	arena.complete_fight()
	if arena.complete_fight() != "":
		push_error("Exhausted queue must grant nothing on fight 6")
		return 1
	return 0


func _test_snapshot_round_trip() -> int:
	var arena := ArenaRunScript.create(QUEUE)
	arena.complete_fight()
	arena.complete_fight()
	arena.complete_fight()
	var restored := ArenaRunScript.from_snapshot(arena.to_snapshot())
	if restored.completed_fights != 3:
		push_error("Snapshot should restore completed_fights")
		return 1
	if restored.granted_spell_ids != ["ward"]:
		push_error("Snapshot should restore granted spells")
		return 1
	if restored.complete_fight() != "":
		push_error("Restored run should continue the cycle at fight 4")
		return 1
	return 0
