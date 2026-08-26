class_name MatchState
extends RefCounted

## Server-authoritative match snapshot (pure logic; sync via MatchStateSnapshot).

enum Phase {
	LOBBY,
	BRIEFING,
	ACTIVE,
	RESOLVING,
	ENDED,
}

var phase: Phase = Phase.LOBBY
var anchor_count: int = 3
var anchors_activated: int = 0
var checkpoint_anchor_id: int = -1
var sealed_peers: Dictionary = {}
var headmaster_dread: int = 0


static func create_initial(config: HorrorMatchConfig) -> MatchState:
	var state := MatchState.new()
	state.phase = Phase.BRIEFING
	state.anchor_count = maxi(config.anchor_count, 1)
	state.anchors_activated = 0
	state.checkpoint_anchor_id = -1
	state.sealed_peers = {}
	state.headmaster_dread = 0
	return state


static func phase_from_int(value: int) -> Phase:
	if value < 0 or value >= Phase.size():
		return Phase.LOBBY
	return value as Phase


static func phase_to_string(value: Phase) -> String:
	match value:
		Phase.LOBBY:
			return "LOBBY"
		Phase.BRIEFING:
			return "BRIEFING"
		Phase.ACTIVE:
			return "ACTIVE"
		Phase.RESOLVING:
			return "RESOLVING"
		Phase.ENDED:
			return "ENDED"
		_:
			return "LOBBY"


static func is_gameplay_phase(value: Phase) -> bool:
	return value == Phase.ACTIVE


static func is_teardown_phase(value: Phase) -> bool:
	return value == Phase.RESOLVING or value == Phase.ENDED


func can_transition_to(next: Phase) -> bool:
	match phase:
		Phase.LOBBY:
			return next == Phase.BRIEFING
		Phase.BRIEFING:
			return next == Phase.ACTIVE
		Phase.ACTIVE:
			return next == Phase.RESOLVING or next == Phase.ENDED
		Phase.RESOLVING:
			return next == Phase.ENDED
		Phase.ENDED:
			return false
	return false


func transition_to(next: Phase) -> Error:
	if not can_transition_to(next):
		return ERR_INVALID_PARAMETER
	phase = next
	return OK


func to_snapshot() -> Dictionary:
	return {
		"phase": phase,
		"anchor_count": anchor_count,
		"anchors_activated": anchors_activated,
		"checkpoint_anchor_id": checkpoint_anchor_id,
		"sealed_peers": sealed_peers.duplicate(true),
		"headmaster_dread": headmaster_dread,
	}


static func from_snapshot(data: Dictionary) -> MatchState:
	var state := MatchState.new()
	state.phase = phase_from_int(int(data.get("phase", Phase.LOBBY)))
	state.anchor_count = int(data.get("anchor_count", 3))
	state.anchors_activated = int(data.get("anchors_activated", 0))
	state.checkpoint_anchor_id = int(data.get("checkpoint_anchor_id", -1))
	var sealed: Variant = data.get("sealed_peers", {})
	state.sealed_peers = sealed if sealed is Dictionary else {}
	state.headmaster_dread = int(data.get("headmaster_dread", 0))
	return state
