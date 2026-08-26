class_name MatchStateSnapshot
extends RefCounted

## Pack/unpack match state for network RPC payloads.


static func pack(state: MatchState) -> Dictionary:
	return state.to_snapshot()


static func unpack(data: Dictionary) -> MatchState:
	return MatchState.from_snapshot(data)


static func pack_initial(config: HorrorMatchConfig) -> Dictionary:
	return pack(MatchState.create_initial(config))
