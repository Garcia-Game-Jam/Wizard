extends RefCounted

const PlayerAirControlScript := preload("res://scripts/characters/player_air_control.gd")
const PlayableCharacterScript := preload("res://scripts/characters/playable_character.gd")


func run() -> int:
	var failures := 0
	failures += _test_scale_starts_at_start_pct()
	failures += _test_scale_decays_over_time()
	failures += _test_scale_floors_at_min_pct()
	failures += _test_tick_air_time_resets_when_grounded()
	failures += _test_tick_air_time_accumulates_when_airborne()
	failures += _test_config_from_player_exports()
	return failures


func _test_scale_starts_at_start_pct() -> int:
	var config := {
		"start_pct": 90.0,
		"min_pct": 65.0,
		"decay_pct_per_sec": PlayerAirControlScript.DEFAULT_DECAY_PCT_PER_SEC,
	}
	var player := CharacterBody3D.new()
	var scale := PlayerAirControlScript.control_scale(player, config)
	player.free()
	if not is_equal_approx(scale, 0.9):
		push_error("Expected fresh-airborne control scale to start at 90%%, got %s" % scale)
		return 1
	return 0


func _test_scale_decays_over_time() -> int:
	var config := {"start_pct": 90.0, "min_pct": 65.0, "decay_pct_per_sec": 7.5}
	var player := CharacterBody3D.new()
	player.set_meta("_player_air_time_sec", 2.0)
	var scale := PlayerAirControlScript.control_scale(player, config)
	player.free()
	## 90 - 7.5*2 = 75%
	if not is_equal_approx(scale, 0.75):
		push_error("Expected control scale to decay to 75%% after 2s airborne, got %s" % scale)
		return 1
	return 0


func _test_scale_floors_at_min_pct() -> int:
	var config := {"start_pct": 90.0, "min_pct": 65.0, "decay_pct_per_sec": 7.5}
	var player := CharacterBody3D.new()
	player.set_meta("_player_air_time_sec", 10.0)
	var scale := PlayerAirControlScript.control_scale(player, config)
	player.free()
	if not is_equal_approx(scale, 0.65):
		push_error("Expected control scale to floor at 65%%, got %s" % scale)
		return 1
	return 0


func _test_tick_air_time_resets_when_grounded() -> int:
	var player := CharacterBody3D.new()
	player.set_meta("_player_air_time_sec", 3.5)
	PlayerAirControlScript.tick_air_time(player, 0.1, true)
	var t := PlayerAirControlScript.air_time(player)
	player.free()
	if not is_equal_approx(t, 0.0):
		push_error("Expected air time to reset to 0 when grounded, got %s" % t)
		return 1
	return 0


func _test_tick_air_time_accumulates_when_airborne() -> int:
	var player := CharacterBody3D.new()
	PlayerAirControlScript.tick_air_time(player, 0.1, false)
	PlayerAirControlScript.tick_air_time(player, 0.2, false)
	var t := PlayerAirControlScript.air_time(player)
	player.free()
	if not is_equal_approx(t, 0.3):
		push_error("Expected air time to accumulate delta while airborne, got %s" % t)
		return 1
	return 0


func _test_config_from_player_exports() -> int:
	var player := PlayableCharacterScript.new()
	player.air_control_start_pct = 100.0
	player.air_control_min_pct = 50.0
	player.air_control_decay_pct_per_sec = 10.0
	var config := PlayerAirControlScript.config_from(player)
	player.free()
	if not is_equal_approx(float(config["start_pct"]), 100.0):
		push_error("Expected config_from to read air_control_start_pct export")
		return 1
	if not is_equal_approx(float(config["min_pct"]), 50.0):
		push_error("Expected config_from to read air_control_min_pct export")
		return 1
	if not is_equal_approx(float(config["decay_pct_per_sec"]), 10.0):
		push_error("Expected config_from to read air_control_decay_pct_per_sec export")
		return 1
	return 0
