class_name TestNetfoxContract
extends RefCounted

## Lanes pick primitives; profiles split input vs state.

const NetWorldEventScript := preload("res://scripts/net/net_world_event.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")


func run() -> int:
	var failures := 0
	failures += _test_lane_primitives()
	failures += _test_profile_split()
	failures += _test_input_schema()
	return failures


func _test_lane_primitives() -> int:
	var failures := 0
	var expected := {
		"haste": NetWorldEventScript.KIND_ACTION,
		"flashlight_toggle": NetWorldEventScript.KIND_ACTION,
		"fireball": NetWorldEventScript.KIND_WEAPON,
		"stone_throw": NetWorldEventScript.KIND_WEAPON,
		"flare": NetWorldEventScript.KIND_WEAPON,
		"ward": NetWorldEventScript.KIND_WEAPON,
		"light_ball": NetWorldEventScript.KIND_WORLD_PROP,
		"target": "",
		"pull": "",
		"follow": "",
		"stop": "",
		"dispell": "",
		"clone": "",
	}
	for effect_id in expected.keys():
		var got := NetWorldEventScript.primitive_for_effect(str(effect_id))
		if got != str(expected[effect_id]):
			push_error("Effect '%s' should use %s, got %s" % [effect_id, expected[effect_id], got])
			failures += 1
	if NetWorldEventScript.primitive_for_effect("unknown") != "":
		push_error("Unknown effects must not pick a primitive")
		failures += 1
	return failures


func _test_profile_split() -> int:
	var failures := 0
	var probe := Player.new()
	var playable_state := probe.net_state_paths()
	var playable_input := PlayerNetInput.net_input_paths()
	if playable_input.is_empty():
		push_error("Playable profile must list Input properties")
		failures += 1
	for path in playable_input:
		if playable_state.has(path):
			push_error("Input path %s must not also be state" % path)
			failures += 1
	if Profiles.input_paths(Profiles.WORLD_PROP).size() != 0:
		push_error("World props are inputless")
		failures += 1
	if not playable_state.has(":net_charge_factor"):
		push_error("Charge tell must be playable state")
		failures += 1
	if not playable_state.has(":net_cast_phase"):
		push_error("Cast phase tell must be playable state")
		failures += 1
	if not playable_state.has(":net_cast_effect_id"):
		push_error("Cast effect tell must be playable state")
		failures += 1
	if not playable_input.has("Input:charge_factor"):
		push_error("Charge hold must be gathered as Input")
		failures += 1
	if playable_input.has("Input:cast_effect_id"):
		push_error("Cast effect must be an int Input code, not a string")
		failures += 1
	if not playable_input.has("Input:cast_effect_code"):
		push_error("Cast effect code must be gathered as Input")
		failures += 1
	if SpellSyncLane.code_for("") != 0:
		push_error("Empty effect id must encode as 0")
		failures += 1
	if SpellSyncLane.id_for_code(SpellSyncLane.code_for("fireball")) != "fireball":
		push_error("SpellSyncLane effect codes must round-trip")
		failures += 1
	if not playable_input.has("Input:jump"):
		push_error("Jump must be gathered as Input")
		failures += 1
	var local_lerp := Profiles.local_playable_interpolate_paths()
	if not local_lerp.has(":position"):
		push_error("Local playable must interpolate position or host walk ticks")
		failures += 1
	if local_lerp.has("Head:rotation") or local_lerp.has("Head/CameraPivot:rotation"):
		push_error("Local playable must not interpolate look (mouse is frame-rate)")
		failures += 1
	if not (":current_health" in Character.NET_STATE_PATHS):
		push_error("HP must be rewindable character state")
		failures += 1
	if not playable_state.has(":current_health"):
		push_error("Playable net_state_paths must include HP")
		failures += 1
	var hp_entry := PropertyEntry.parse(probe, ":current_health")
	if not hp_entry.is_valid():
		push_error("current_health must be storage-exported so LAN rewind records HP")
		failures += 1
	else:
		probe.current_health = 17.0
		if not is_equal_approx(float(hp_entry.get_value()), 17.0):
			push_error("netfox must read current_health off the character root")
			failures += 1
		hp_entry.set_value(0.0)
		if probe.is_alive() or not probe.is_death_physics():
			push_error("netfox restore of HP 0 must run death teardown")
			failures += 1
	probe.free()
	var charge_state := Profiles.state_paths(Profiles.CHARGE)
	if not charge_state.has(":net_phase") or not charge_state.has(":net_telegraph"):
		push_error("Charger telegraph+ram must share rewindable phase state")
		failures += 1
	if not charge_state.has(":current_health"):
		push_error("Charger HP must be character net state")
		failures += 1
	var world_state := Profiles.state_paths(Profiles.WORLD_PROP)
	if world_state.has(":net_phase") or world_state.has(":net_telegraph"):
		push_error("Charger phase state belongs on CHARGE, not every world_prop")
		failures += 1
	if world_state.has(":current_health"):
		push_error("Orb/cover world_prop must not assume character HP")
		failures += 1
	var cover_state := Profiles.state_paths(Profiles.COVER)
	if not cover_state.has(":cover_t") or not cover_state.has(":home"):
		push_error("Cover restage must rewind height and home")
		failures += 1
	if not charge_state.has("Head:rotation"):
		push_error("Charger bow must be rewindable pose, not a late interpolator ghost")
		failures += 1
	if not playable_state.has("Stun:_stunned"):
		push_error("Stun:_stunned must be playable rewind state")
		failures += 1
	if playable_state.has("Stun:visual_active"):
		push_error("Stun FX must not be rewindable net state")
		failures += 1
	if not (":_eyes_chasing" in Character.NET_STATE_PATHS):
		push_error("Chase eye lights must be character net state so remotes can draw them")
		failures += 1
	if not (":eye_glow_color" in Character.NET_STATE_PATHS):
		push_error("Eye glow must be character net state so remotes can draw them")
		failures += 1
	var charger := Charger.new()
	var charger_profile := charger._net_rewind_profile()
	charger.free()
	if charger_profile != Profiles.CHARGE:
		push_error("Charger must attach with CHARGE interpolator profile")
		failures += 1
	return failures


func _test_input_schema() -> int:
	var failures := 0
	var paths := PlayerNetInput.net_input_paths()
	var schema := PlayerNetInput.net_schema()
	if schema.size() != paths.size():
		push_error("Every Input field must have a compact net schema")
		failures += 1
	var samples := {
		"Input:movement": Vector2(1.0, 0.0),
		"Input:jump": true,
		"Input:dash": false,
		"Input:crouch": true,
		"Input:look_yaw": 1.2,
		"Input:look_pitch": -0.4,
		"Input:charging": true,
		"Input:charge_slot": -1,
		"Input:charge_factor": 0.5,
		"Input:cast_phase": 1,
		"Input:cast_effect_code": 3,
		"Input:wand_raised": true,
	}
	var buffer := StreamPeerBuffer.new()
	for path in paths:
		if not schema.has(path):
			push_error("Input path %s must have a compact net schema" % path)
			failures += 1
			continue
		var serializer := schema[path] as NetworkSchemaSerializer
		if serializer == null:
			push_error("Input path %s schema must be a NetworkSchemaSerializer" % path)
			failures += 1
			continue
		if not samples.has(path):
			push_error("Input schema test needs a sample for %s" % path)
			failures += 1
			continue
		var before := buffer.get_position()
		serializer.encode(samples[path], buffer)
		if buffer.get_position() <= before:
			push_error("Input path %s encoded to 0 bytes" % path)
			failures += 1
	## Identity + tick header per redundant snapshot; keep headroom under 508.
	const MAX_PACKET := 508
	const REDUNDANCY := 3
	const PER_TICK_OVERHEAD := 80
	var packed := (buffer.get_position() + PER_TICK_OVERHEAD) * REDUNDANCY
	if packed > MAX_PACKET:
		push_error(
			"Schemed input is %d bytes over %d redundant ticks; must fit in %d"
			% [packed, REDUNDANCY, MAX_PACKET]
		)
		failures += 1
	buffer.seek(0)
	for path in paths:
		if not schema.has(path) or not samples.has(path):
			continue
		var serializer := schema[path] as NetworkSchemaSerializer
		if serializer == null:
			continue
		var decoded: Variant = serializer.decode(buffer)
		if not _schema_values_match(samples[path], decoded):
			push_error("Input path %s did not round-trip (%s -> %s)" % [path, samples[path], decoded])
			failures += 1
	var mover := FileAccess.get_file_as_string("res://scripts/net/net_rewindable_mover.gd")
	if not mover.contains("PlayerNetInputScript.net_schema()"):
		push_error("Playable rollback must set_schema from PlayerNetInput.net_schema")
		failures += 1
	var dispatch := FileAccess.get_file_as_string("res://scripts/net/net_world_event.gd")
	var dispatch_fn := dispatch.find("func dispatch_spell")
	var next_fn := dispatch.find("\nstatic func", dispatch_fn + 10)
	var body := dispatch.substr(dispatch_fn, next_fn - dispatch_fn if next_fn > dispatch_fn else -1)
	if body.contains("if not NetClockScript.is_ticking()"):
		push_error("dispatch_spell must not dump weapon spells through apply() when the clock is off")
		failures += 1
	return failures


func _schema_values_match(expected: Variant, got: Variant) -> bool:
	if expected is Vector2 and got is Vector2:
		return (expected as Vector2).is_equal_approx(got as Vector2)
	if expected is float or got is float:
		return absf(float(expected) - float(got)) < 0.01
	return expected == got
