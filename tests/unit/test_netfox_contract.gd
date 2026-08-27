class_name TestNetfoxContract
extends RefCounted

## Lanes pick primitives; profiles split input vs state.

const NetWorldEventScript := preload("res://scripts/net/net_world_event.gd")
const Profiles := preload("res://scripts/net/net_rewindable_profiles.gd")


func run() -> int:
	var failures := 0
	failures += _test_lane_primitives()
	failures += _test_profile_split()
	return failures


func _test_lane_primitives() -> int:
	var failures := 0
	var expected := {
		"haste": NetWorldEventScript.KIND_ACTION,
		"flashlight_toggle": NetWorldEventScript.KIND_ACTION,
		"fireball": NetWorldEventScript.KIND_WEAPON,
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
	probe.free()
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
	if not playable_input.has("Input:charge_factor"):
		push_error("Charge hold must be gathered as Input")
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
	if not ("Health:current_health" in Character.NET_STATE_PATHS):
		push_error("HP must be rewindable character state")
		failures += 1
	if not playable_state.has("Health:current_health"):
		push_error("Playable net_state_paths must include HP")
		failures += 1
	var charge_state := Profiles.state_paths(Profiles.CHARGE)
	if not charge_state.has(":net_phase") or not charge_state.has(":net_telegraph"):
		push_error("Charger telegraph+ram must share rewindable phase state")
		failures += 1
	if not charge_state.has("Health:current_health"):
		push_error("Charger HP must be character net state")
		failures += 1
	var world_state := Profiles.state_paths(Profiles.WORLD_PROP)
	if world_state.has(":net_phase") or world_state.has(":net_telegraph"):
		push_error("Charger phase state belongs on CHARGE, not every world_prop")
		failures += 1
	if world_state.has("Health:current_health"):
		push_error("Orb/cover world_prop must not assume a Health child")
		failures += 1
	var cover_state := Profiles.state_paths(Profiles.COVER)
	if not cover_state.has(":cover_t") or not cover_state.has(":home"):
		push_error("Cover restage must rewind height and home")
		failures += 1
	if not charge_state.has("Head:rotation"):
		push_error("Charger bow must be rewindable pose, not a late interpolator ghost")
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
