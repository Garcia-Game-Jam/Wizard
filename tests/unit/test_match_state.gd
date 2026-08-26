class_name TestMatchState
extends RefCounted

const MatchStateScript := preload("res://scripts/match/match_state.gd")
const HorrorMatchConfigScript := preload("res://scripts/match/horror_match_config.gd")
const MatchStateSnapshotScript := preload("res://scripts/match/match_state_snapshot.gd")


func run() -> int:
	var failures := 0
	failures += _test_create_initial_briefing()
	failures += _test_phase_transitions()
	failures += _test_invalid_transition_rejected()
	failures += _test_gameplay_and_teardown_phases()
	failures += _test_snapshot_round_trip()
	return failures


func _test_create_initial_briefing() -> int:
	var config := HorrorMatchConfigScript.defaults()
	var state := MatchStateScript.create_initial(config)
	if state.phase != MatchStateScript.Phase.BRIEFING:
		push_error("Expected initial match phase BRIEFING")
		return 1
	if state.anchor_count != 3:
		push_error("Expected default anchor_count 3")
		return 1
	if state.anchors_activated != 0:
		push_error("Expected zero activated anchors at start")
		return 1
	return 0


func _test_phase_transitions() -> int:
	var state := MatchStateScript.create_initial(HorrorMatchConfigScript.defaults())
	if state.transition_to(MatchStateScript.Phase.ACTIVE) != OK:
		push_error("Expected BRIEFING -> ACTIVE transition")
		return 1
	if state.transition_to(MatchStateScript.Phase.RESOLVING) != OK:
		push_error("Expected ACTIVE -> RESOLVING transition")
		return 1
	if state.transition_to(MatchStateScript.Phase.ENDED) != OK:
		push_error("Expected RESOLVING -> ENDED transition")
		return 1
	return 0


func _test_invalid_transition_rejected() -> int:
	var state := MatchStateScript.create_initial(HorrorMatchConfigScript.defaults())
	if state.transition_to(MatchStateScript.Phase.ENDED) == OK:
		push_error("Expected BRIEFING -> ENDED to be rejected")
		return 1
	state.phase = MatchStateScript.Phase.ENDED
	if state.transition_to(MatchStateScript.Phase.ACTIVE) == OK:
		push_error("Expected ENDED -> ACTIVE to be rejected")
		return 1
	return 0


func _test_gameplay_and_teardown_phases() -> int:
	if not MatchStateScript.is_gameplay_phase(MatchStateScript.Phase.ACTIVE):
		push_error("Expected ACTIVE to be a gameplay phase")
		return 1
	if MatchStateScript.is_gameplay_phase(MatchStateScript.Phase.BRIEFING):
		push_error("Expected BRIEFING not to be a gameplay phase")
		return 1
	if not MatchStateScript.is_teardown_phase(MatchStateScript.Phase.ENDED):
		push_error("Expected ENDED to be a teardown phase")
		return 1
	if not MatchStateScript.is_teardown_phase(MatchStateScript.Phase.RESOLVING):
		push_error("Expected RESOLVING to be a teardown phase")
		return 1
	if MatchStateScript.is_teardown_phase(MatchStateScript.Phase.ACTIVE):
		push_error("Expected ACTIVE not to be a teardown phase")
		return 1
	return 0


func _test_snapshot_round_trip() -> int:
	var config := HorrorMatchConfigScript.defaults()
	var original := MatchStateScript.create_initial(config)
	original.anchors_activated = 2
	original.checkpoint_anchor_id = 1
	original.sealed_peers = {2: {"room_id": 5}}
	original.headmaster_dread = 10

	var packed := MatchStateSnapshotScript.pack(original)
	var restored := MatchStateSnapshotScript.unpack(packed)

	if restored.phase != original.phase:
		push_error("Snapshot round-trip lost phase")
		return 1
	if restored.anchors_activated != 2:
		push_error("Snapshot round-trip lost anchors_activated")
		return 1
	if restored.checkpoint_anchor_id != 1:
		push_error("Snapshot round-trip lost checkpoint_anchor_id")
		return 1
	if int(restored.sealed_peers.get(2, {}).get("room_id", -1)) != 5:
		push_error("Snapshot round-trip lost sealed_peers")
		return 1
	if restored.headmaster_dread != 10:
		push_error("Snapshot round-trip lost headmaster_dread")
		return 1
	return 0
