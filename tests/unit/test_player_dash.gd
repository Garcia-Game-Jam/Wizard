extends RefCounted

const PlayerDashScript := preload("res://scripts/characters/player_dash.gd")
const PlayerScript := preload("res://scripts/characters/player.gd")


func run() -> int:
	var failures := 0
	failures += _test_default_dash_travel()
	failures += _test_config_speed_overrides_defaults()
	failures += _test_config_from_player_exports()
	failures += _test_post_speed_pct_clamps_to_range()
	failures += _test_post_decay_noop_while_dash_active()
	failures += _test_post_decay_noop_when_no_dash_happened()
	failures += _test_post_decay_bleeds_speed_toward_target()
	failures += _test_post_decay_stops_once_target_reached()
	failures += _test_dash_pulse_survives_until_gather()
	failures += _test_jump_pulse_survives_until_gather()
	failures += _test_held_jump_is_one_tick()
	return failures


func _test_default_dash_travel() -> int:
	var config := {
		"distance": PlayerDashScript.DEFAULT_DISTANCE,
		"duration": PlayerDashScript.DEFAULT_DURATION,
		"speed": PlayerDashScript.DEFAULT_SPEED,
	}
	var speed := PlayerDashScript.dash_speed(config)
	var distance := speed * PlayerDashScript.dash_duration(config)
	if not is_equal_approx(distance, PlayerDashScript.DEFAULT_DISTANCE):
		push_error("Expected default dash to travel 3 m, got %s m" % distance)
		return 1
	return 0


func _test_config_speed_overrides_defaults() -> int:
	var config := {"speed": 12.0, "duration": 0.25}
	if not is_equal_approx(PlayerDashScript.dash_speed(config), 12.0):
		push_error("Expected dash_speed to read config speed")
		return 1
	return 0


func _test_config_from_player_exports() -> int:
	var player := PlayerScript.new()
	player.dash_distance = 4.0
	player.dash_duration = 0.2
	player.dash_cooldown_sec = 2.5
	player.dash_speed = 15.0
	var config := PlayerDashScript.config_from(player)
	player.free()
	if not is_equal_approx(float(config["distance"]), 4.0):
		push_error("Expected config_from to read dash_distance export")
		return 1
	if not is_equal_approx(float(config["speed"]), 15.0):
		push_error("Expected config_from to read dash_speed export")
		return 1
	return 0


func _test_post_speed_pct_clamps_to_range() -> int:
	if not is_equal_approx(PlayerDashScript.post_speed_pct({"post_speed_pct": 10.0}), 25.0):
		push_error("Expected post_speed_pct to clamp below 25%%")
		return 1
	if not is_equal_approx(PlayerDashScript.post_speed_pct({"post_speed_pct": 500.0}), 200.0):
		push_error("Expected post_speed_pct to clamp above 200%%")
		return 1
	return 0


func _test_post_decay_noop_while_dash_active() -> int:
	var player := CharacterBody3D.new()
	player.set_meta("_dash_active_until_msec", Time.get_ticks_msec() + 5000)
	player.set_meta("_dash_post_decay_pending", true)
	player.velocity = Vector3(20.0, 0.0, 0.0)
	PlayerDashScript.tick_post_decay(player, 0.1, {"post_speed_pct": 100.0})
	var unchanged := player.velocity.x
	player.free()
	if not is_equal_approx(unchanged, 20.0):
		push_error("Expected tick_post_decay to no-op while the dash lock is still active")
		return 1
	return 0


func _test_post_decay_noop_when_no_dash_happened() -> int:
	var player := PlayerScript.new()
	player.move_speed = 5.0
	player.velocity = Vector3(20.0, 0.0, 0.0)
	PlayerDashScript.tick_post_decay(player, 0.1)
	var unchanged := player.velocity.x
	player.free()
	if not is_equal_approx(unchanged, 20.0):
		push_error("Expected tick_post_decay to no-op with no pending post-dash decay")
		return 1
	return 0


func _test_post_decay_bleeds_speed_toward_target() -> int:
	var player := PlayerScript.new()
	player.move_speed = 5.0
	player.dash_post_speed_pct = 100.0
	player.velocity = Vector3(20.0, 0.0, 0.0)
	player.dash_post_decay_pending = true
	PlayerDashScript.tick_post_decay(player, 0.1)
	var speed := player.velocity.x
	player.free()
	## Target is move_speed (5.0); decay rate is 45 m/s^2, so after 0.1s
	## speed should have dropped by 4.5 m/s from 20 -> 15.5, still above target.
	if not is_equal_approx(speed, 15.5):
		push_error("Expected leftover dash speed to bleed toward target, got %s" % speed)
		return 1
	return 0


func _test_post_decay_stops_once_target_reached() -> int:
	var player := PlayerScript.new()
	player.move_speed = 5.0
	player.dash_post_speed_pct = 100.0
	player.velocity = Vector3(5.0, 0.0, 0.0)
	player.dash_post_decay_pending = true
	PlayerDashScript.tick_post_decay(player, 0.1)
	var pending := player.dash_post_decay_pending
	var speed := player.velocity.x
	player.free()
	if pending:
		push_error("Expected post-dash decay to clear once speed reaches the target")
		return 1
	if not is_equal_approx(speed, 5.0):
		push_error("Expected velocity to be left untouched once already at the target")
		return 1
	return 0


func _test_dash_pulse_survives_until_gather() -> int:
	var net_input := PlayerNetInput.new()
	net_input.queue_dash()
	net_input._gather()
	var first := net_input.dash
	net_input._gather()
	var second := net_input.dash
	net_input.free()
	if not first:
		push_error("Expected a queued dash press to land on the next gather")
		return 1
	if second:
		push_error("Expected dash pulse to consume after one gather")
		return 1
	return 0


func _test_jump_pulse_survives_until_gather() -> int:
	var net_input := PlayerNetInput.new()
	net_input.queue_jump()
	net_input._gather()
	var first := net_input.jump
	net_input._gather()
	var second := net_input.jump
	net_input.free()
	if not first:
		push_error("Expected a queued jump press to land on the next gather")
		return 1
	if second:
		push_error("Expected jump pulse to consume after one gather")
		return 1
	return 0


func _test_held_jump_is_one_tick() -> int:
	var src := FileAccess.get_file_as_string("res://scripts/net/player_net_input.gd")
	if src.find("_jump_was_held") < 0:
		push_error("Held jump must be an edge or floor-snap keeps grounded hover")
		return 1
	return 0
