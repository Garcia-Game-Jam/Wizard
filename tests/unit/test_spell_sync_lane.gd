class_name TestSpellSyncLane
extends RefCounted

const LaneScript := preload("res://scripts/spells/spell_sync_lane.gd")
const EphemeralScript := preload("res://scripts/spells/spell_ephemeral_fx.gd")
const SyncScript := preload("res://scripts/spells/spell_effect_sync.gd")


func run() -> int:
	var failures := 0
	failures += _test_known_effects_have_lanes()
	failures += _test_lane_descriptions()
	failures += _test_ephemeral_ray_round_trip()
	failures += _test_effect_sync_lane_helper()
	return failures


func _test_known_effects_have_lanes() -> int:
	var expected := {
		"haste": LaneScript.PLAYER_BOUND,
		"flashlight_toggle": LaneScript.PLAYER_BOUND,
		"fireball": LaneScript.EPHEMERAL,
		"flare": LaneScript.EPHEMERAL,
		"ward": LaneScript.EPHEMERAL,
		"light_ball": LaneScript.WORLD_OBJECT,
		"target": LaneScript.TARGETED,
		"pull": LaneScript.TARGETED,
		"follow": LaneScript.TARGETED,
		"stop": LaneScript.TARGETED,
		"dispell": LaneScript.TARGETED,
		"clone": LaneScript.TARGETED,
	}
	for effect_id in expected.keys():
		if not LaneScript.is_known(effect_id) or not SyncScript.is_supported_effect(effect_id):
			push_error("Expected effect '%s' to be known/supported" % effect_id)
			return 1
		if LaneScript.for_effect(effect_id) != str(expected[effect_id]):
			push_error(
				"Expected effect '%s' lane '%s'" % [effect_id, str(expected[effect_id])]
			)
			return 1
	return 0


func _test_lane_descriptions() -> int:
	for lane in [
		LaneScript.PLAYER_BOUND,
		LaneScript.EPHEMERAL,
		LaneScript.WORLD_OBJECT,
		LaneScript.TARGETED,
	]:
		if LaneScript.describe(lane).is_empty():
			push_error("Expected description for lane '%s'" % lane)
			return 1
	return 0


func _test_ephemeral_ray_round_trip() -> int:
	var wire := {"effect_id": "fireball"}
	EphemeralScript.pack_ray(wire, Vector3(1.0, 2.0, 3.0), Vector3(0.0, 0.0, -1.0))
	if not EphemeralScript.is_ray_wire(wire):
		push_error("Expected packed ray to detect as wire format")
		return 1
	var unpacked := EphemeralScript.unpack_ray(wire)
	var origin: Vector3 = unpacked[EphemeralScript.KEY_ORIGIN]
	var direction: Vector3 = unpacked[EphemeralScript.KEY_DIRECTION]
	if not origin.is_equal_approx(Vector3(1.0, 2.0, 3.0)):
		push_error("Expected ephemeral ray origin round-trip")
		return 1
	if not direction.is_equal_approx(Vector3(0.0, 0.0, -1.0)):
		push_error("Expected ephemeral ray direction round-trip")
		return 1
	return 0


func _test_effect_sync_lane_helper() -> int:
	if SyncScript.sync_lane_for("fireball") != LaneScript.EPHEMERAL:
		push_error("Expected SpellEffectSync.sync_lane_for to match SpellSyncLane")
		return 1
	return 0
