extends RefCounted

const PlayableCharacterScript := preload("res://scripts/characters/playable_character.gd")
const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")


func run() -> int:
	var failures := 0
	failures += _test_default_crouch_walk_speed()
	failures += _test_slide_entry_threshold()
	failures += _test_slide_friction_ramp()
	failures += _test_dash_grace_entry()
	failures += _test_config_from_player_exports()
	failures += _test_move_speed_export()
	failures += _test_move_friction_export()
	failures += _test_slide_friction_with_wish_dir()
	return failures


func _test_default_crouch_walk_speed() -> int:
	var player := PlayableCharacterScript.new()
	player.net_crouching = true
	var speed := PlayerCrouchScript.ground_move_speed(player, 1.0)
	player.free()
	if not is_equal_approx(speed, PlayerCrouchScript.DEFAULT_CROUCH_SPEED):
		push_error("Expected default crouch walk speed 2.5 m/s, got %s" % speed)
		return 1
	return 0


func _test_slide_entry_threshold() -> int:
	var config := {}
	if not PlayerCrouchScript.should_enter_slide(0.6, config, false):
		push_error("Expected speed above entry threshold to allow slide")
		return 1
	if PlayerCrouchScript.should_enter_slide(0.5, config, false):
		push_error("Expected speed at entry threshold not to allow slide")
		return 1
	if not PlayerCrouchScript.should_enter_slide(1.5, config, true):
		push_error("Expected dash grace to allow slide below entry when above exit")
		return 1
	return 0


func _test_slide_friction_ramp() -> int:
	var player := PlayableCharacterScript.new()
	player.move_friction = 50.0
	var config := {}
	var ramp_high := maxf(
		PlayerCrouchScript.slide_threshold(config), PlayerCrouchScript.slide_exit_speed(config)
	) + 8.0
	var fast := PlayerCrouchScript.slide_friction_decel(player, config, ramp_high + 1.0)
	var slow := PlayerCrouchScript.slide_friction_decel(player, config, 1.2)
	player.free()
	if fast >= slow:
		push_error("Expected less friction at high speed than near exit")
		return 1
	if not is_equal_approx(fast, 50.0 * 0.12):
		push_error("Expected high-speed slide friction at start percent")
		return 1
	return 0


func _test_dash_grace_entry() -> int:
	var player := PlayableCharacterScript.new()
	PlayerCrouchScript.mark_dash_slide_grace(player, 0.2, 0.4)
	if not PlayerCrouchScript.dash_slide_grace_active(player):
		push_error("Expected dash slide grace to be active after marking")
		player.free()
		return 1
	var config := {"slide_threshold": 5.0, "slide_exit_speed": 1.0}
	if not PlayerCrouchScript.should_enter_slide(3.0, config, true):
		push_error("Expected dash grace to enter slide below entry threshold")
		player.free()
		return 1
	player.free()
	return 0


func _test_config_from_player_exports() -> int:
	var player := PlayableCharacterScript.new()
	player.crouch_speed = 1.8
	player.crouch_slide_threshold = 2.0
	player.crouch_slide_exit_speed = 0.8
	player.crouch_slide_friction_start = 10.0
	player.crouch_slide_friction = 60.0
	var config := PlayerCrouchScript.config_from(player)
	player.free()
	if not is_equal_approx(float(config["speed"]), 1.8):
		push_error("Expected config_from to read crouch_speed export")
		return 1
	if not is_equal_approx(float(config["slide_friction"]), 60.0):
		push_error("Expected config_from to read crouch_slide_friction export")
		return 1
	return 0


func _test_move_speed_export() -> int:
	var player := PlayableCharacterScript.new()
	player.move_speed = 6.5
	if not is_equal_approx(PlayerCrouchScript.resolve_move_speed(player), 6.5):
		push_error("Expected resolve_move_speed to read move_speed export")
		player.free()
		return 1
	player.free()
	return 0


func _test_move_friction_export() -> int:
	var player := PlayableCharacterScript.new()
	player.move_friction = 12.0
	if not is_equal_approx(PlayerCrouchScript.resolve_move_friction(player), 12.0):
		push_error("Expected resolve_move_friction to read move_friction export")
		player.free()
		return 1
	player.free()
	return 0


func _test_slide_friction_with_wish_dir() -> int:
	var vel := Vector3(12.0, 0.0, 0.0)
	var wish := Vector3.FORWARD
	var out := PlayerCrouchScript.step_slide_velocity(vel, wish, 0.1, 2.5, 35.0)
	if out.length() >= vel.length():
		push_error(
			"Expected crouch slide friction to bleed speed even while steering, got %s" % out
		)
		return 1
	return 0
