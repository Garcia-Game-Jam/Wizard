class_name TestProximityVoice
extends RefCounted

## Covers the codified falloff curve and the playback type SimpleVoiceChat picks.
## A peer only becomes spatial when proximity is on AND a world anchor is known;
## everything else must stay flat, because lobby chat has no Camera3D listener.

const ProximityChatSettingsScript := preload("res://scripts/voice/proximity_chat_settings.gd")
const SimpleVoiceChatScript := preload("res://scripts/voice/simple_voice_chat.gd")

const LOCAL_STEAM_ID := 111
const REMOTE_STEAM_ID := 222


func run() -> int:
	var failures := 0
	failures += _test_full_volume_inside_radius()
	failures += _test_falloff_between_radii()
	failures += _test_silent_past_max_range()
	failures += _test_spatial_requires_proximity_and_anchor()
	return failures


func _test_full_volume_inside_radius() -> int:
	var prox := _settings()
	for distance in [0.0, 4.0, 8.0]:
		var db := prox.volume_db_for_distance(float(distance))
		if not is_equal_approx(db, prox.max_volume_db):
			push_error(
				"Expected full volume %.1f dB at %.1fm, got %.1f"
				% [prox.max_volume_db, float(distance), db]
			)
			return 1
	return 0


func _test_falloff_between_radii() -> int:
	var prox := _settings()
	var midpoint := (prox.full_volume_m + prox.max_range_m) * 0.5
	var expected := (prox.max_volume_db + prox.min_volume_db) * 0.5
	var db := prox.volume_db_for_distance(midpoint)
	if not is_equal_approx(db, expected):
		push_error("Expected %.1f dB midway at %.1fm, got %.1f" % [expected, midpoint, db])
		return 1
	## Falloff must be monotonic so walking away never gets louder.
	var previous := prox.max_volume_db + 1.0
	for step in range(0, 50):
		var current := prox.volume_db_for_distance(float(step))
		if current > previous:
			push_error("Falloff rose from %.1f to %.1f dB at %dm" % [previous, current, step])
			return 1
		previous = current
	return 0


## Culling is the curve's job: max_range_m and beyond must floor to silence.
func _test_silent_past_max_range() -> int:
	var prox := _settings()
	for distance in [prox.max_range_m, prox.max_range_m + 5.0]:
		var db := prox.volume_db_for_distance(distance)
		if not is_equal_approx(db, ProximityChatSettingsScript.SILENT_DB):
			push_error("Expected silence at %.1fm, got %.1f dB" % [distance, db])
			return 1
	return 0


func _test_spatial_requires_proximity_and_anchor() -> int:
	var chat: Node = SimpleVoiceChatScript.new()
	chat.set("_local_peer_id", LOCAL_STEAM_ID)
	var anchor := Node3D.new()
	var failures := 0

	if bool(chat.call("_wants_spatial", REMOTE_STEAM_ID)):
		push_error("Peer must stay flat with no proximity settings and no anchor")
		failures = 1
	else:
		chat.call("set_peer_anchor", REMOTE_STEAM_ID, anchor)
		if bool(chat.call("_wants_spatial", REMOTE_STEAM_ID)):
			push_error("An anchor alone must not spatialize — lobby chat is open mic")
			failures = 1
		else:
			chat.call("set_proximity_settings", _settings())
			if not bool(chat.call("_wants_spatial", REMOTE_STEAM_ID)):
				push_error("Proximity settings plus an anchor must spatialize the peer")
				failures = 1
			elif bool(chat.call("_wants_spatial", LOCAL_STEAM_ID)):
				push_error("A peer with no anchor must stay flat")
				failures = 1
			else:
				chat.call("clear_peer_anchors")
				if bool(chat.call("_wants_spatial", REMOTE_STEAM_ID)):
					push_error("Clearing anchors must return peers to flat playback")
					failures = 1

	anchor.free()
	chat.free()
	return failures


func _settings() -> ProximityChatSettings:
	var prox := ProximityChatSettings.new()
	prox.enabled = true
	prox.full_volume_m = 8.0
	prox.max_range_m = 40.0
	prox.max_volume_db = 0.0
	prox.min_volume_db = -40.0
	return prox
