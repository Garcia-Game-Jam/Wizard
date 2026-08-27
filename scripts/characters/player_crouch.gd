class_name PlayerCrouch
extends RefCounted

## Foot crouch + momentum slide for PlayableCharacter. Tunables live on
## PlayableCharacter; defaults below are fallbacks for tests.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")

const DEFAULT_CROUCH_SPEED := 2.5
const DEFAULT_SLIDE_THRESHOLD := 0.5
const DEFAULT_SLIDE_EXIT_SPEED := 1.0
const DEFAULT_SLIDE_DASH_GRACE_SEC := 0.6
const DEFAULT_SLIDE_RECOVERY_SEC := 0.3
const DEFAULT_SLIDE_FRICTION_START := 12.0
const DEFAULT_SLIDE_FRICTION := 35.0
const META_CROUCHING := "_player_crouching"
const META_SLIDING := "_player_crouch_sliding"
const META_RECOVERY_UNTIL := "_crouch_slide_recovery_until_msec"
const META_DASH_SLIDE_UNTIL := "_dash_slide_grace_until_msec"


static func config_from(player: CharacterBody3D) -> Dictionary:
	return {
		"speed": _export_float(player, "crouch_speed", DEFAULT_CROUCH_SPEED),
		"slide_threshold": _export_float(
			player, "crouch_slide_threshold", DEFAULT_SLIDE_THRESHOLD
		),
		"slide_exit_speed": _export_float(
			player, "crouch_slide_exit_speed", DEFAULT_SLIDE_EXIT_SPEED
		),
		"dash_grace_sec": _export_float(
			player, "crouch_slide_dash_grace_sec", DEFAULT_SLIDE_DASH_GRACE_SEC
		),
		"recovery_sec": _export_float(
			player, "crouch_slide_recovery_sec", DEFAULT_SLIDE_RECOVERY_SEC
		),
		"slide_friction_start": _export_float(
			player, "crouch_slide_friction_start", DEFAULT_SLIDE_FRICTION_START
		),
		"slide_friction": _export_float(
			player, "crouch_slide_friction", DEFAULT_SLIDE_FRICTION
		),
	}


static func _export_float(player: Object, property: StringName, default: float) -> float:
	if player is PlayableCharacter:
		return float(player.get(property))
	var value: Variant = player.get(property)
	if value == null:
		return default
	return float(value)


static func resolve_move_speed(player: CharacterBody3D) -> float:
	return maxf(_export_float(player, "move_speed", PlayableCharacter.DEFAULT_WALK_SPEED), 0.0)


static func resolve_move_friction(player: CharacterBody3D) -> float:
	return maxf(
		_export_float(player, "move_friction", PlayableCharacter.DEFAULT_MOVE_FRICTION), 0.0
	)


static func crouch_speed(config: Dictionary = {}) -> float:
	return maxf(float(config.get("speed", DEFAULT_CROUCH_SPEED)), 0.0)


static func slide_threshold(config: Dictionary = {}) -> float:
	return maxf(float(config.get("slide_threshold", DEFAULT_SLIDE_THRESHOLD)), 0.0)


static func slide_exit_speed(config: Dictionary = {}) -> float:
	return maxf(float(config.get("slide_exit_speed", DEFAULT_SLIDE_EXIT_SPEED)), 0.0)


static func slide_friction_start_percent(config: Dictionary = {}) -> float:
	return clampf(
		float(config.get("slide_friction_start", DEFAULT_SLIDE_FRICTION_START)), 0.0, 100.0
	)


static func slide_friction_end_percent(config: Dictionary = {}) -> float:
	return clampf(float(config.get("slide_friction", DEFAULT_SLIDE_FRICTION)), 0.0, 100.0)


static func slide_friction_decel(
	player: CharacterBody3D, config: Dictionary, speed: float
) -> float:
	var ground := resolve_move_friction(player)
	var exit_sp := slide_exit_speed(config)
	var entry := slide_threshold(config)
	var ramp_high := maxf(entry, exit_sp) + 8.0
	var span := maxf(ramp_high - exit_sp, 0.01)
	var t := clampf((speed - exit_sp) / span, 0.0, 1.0)
	var pct := lerpf(slide_friction_end_percent(config), slide_friction_start_percent(config), t)
	return ground * (pct / 100.0)


static func step_slide_velocity(
	velocity: Vector3,
	wish_dir: Vector3,
	delta: float,
	steer_cap: float,
	friction: float
) -> Vector3:
	var vel := Vector3(velocity.x, 0.0, velocity.z)
	if friction > 0.0:
		vel = vel.move_toward(Vector3.ZERO, friction * delta)
	if wish_dir.length_squared() > 0.0001 and steer_cap > 0.0:
		var wish_n := wish_dir.normalized()
		var along := vel.dot(wish_n)
		if along < steer_cap:
			vel += wish_n * minf(steer_cap * 3.0 * delta, steer_cap - maxf(along, 0.0))
	return vel


static func is_crouching(player: CharacterBody3D) -> bool:
	if "net_crouching" in player:
		return bool(player.get("net_crouching"))
	return bool(player.get_meta(META_CROUCHING, false))


## Force crouch collision state (e.g. maze-hole burrow) without reading input.
static func apply_crouch_collision(player: CharacterBody3D, crouching: bool) -> void:
	player.set_meta(META_CROUCHING, crouching)
	if "net_crouching" in player:
		player.set("net_crouching", crouching)
	if crouching:
		return
	player.set_meta(META_SLIDING, false)
	if "net_sliding" in player:
		player.set("net_sliding", false)
	_clear_recovery(player)


static func is_sliding(player: CharacterBody3D) -> bool:
	if "net_sliding" in player:
		return bool(player.get("net_sliding"))
	return bool(player.get_meta(META_SLIDING, false))


static func is_recovering(player: CharacterBody3D) -> bool:
	if "crouch_recovery_remaining" in player:
		return float(player.get("crouch_recovery_remaining")) > 0.0
	return Time.get_ticks_msec() < int(player.get_meta(META_RECOVERY_UNTIL, 0))


static func is_coasting(player: CharacterBody3D) -> bool:
	return is_sliding(player) or is_recovering(player)


static func dash_slide_grace_active(player: CharacterBody3D) -> bool:
	if "dash_slide_grace_remaining" in player:
		return float(player.get("dash_slide_grace_remaining")) > 0.0
	return Time.get_ticks_msec() < int(player.get_meta(META_DASH_SLIDE_UNTIL, 0))


static func mark_dash_slide_grace(
	player: CharacterBody3D, dash_duration: float, grace_sec: float
) -> void:
	var total := maxf(dash_duration, 0.0) + maxf(grace_sec, 0.0)
	if "dash_slide_grace_remaining" in player:
		player.set("dash_slide_grace_remaining", total)
		return
	player.set_meta(
		META_DASH_SLIDE_UNTIL, Time.get_ticks_msec() + int(round(total * 1000.0))
	)


static func ground_move_speed(player: CharacterBody3D, boost: float) -> float:
	if is_crouching(player) and not is_coasting(player):
		return crouch_speed(config_from(player)) * boost
	return resolve_move_speed(player) * boost


static func horizontal_speed(player: CharacterBody3D) -> float:
	return Vector3(player.velocity.x, 0.0, player.velocity.z).length()


static func should_enter_slide(
	speed: float, config: Dictionary, dash_grace: bool
) -> bool:
	if dash_grace and speed > slide_exit_speed(config):
		return true
	return speed > slide_threshold(config)


static func tick(
	player: CharacterBody3D, net_input: Object = null, delta: float = -1.0
) -> void:
	if delta < 0.0:
		delta = player.get_physics_process_delta_time()
	if "dash_slide_grace_remaining" in player:
		var grace := float(player.get("dash_slide_grace_remaining"))
		if grace > 0.0:
			player.set("dash_slide_grace_remaining", maxf(0.0, grace - delta))
	if "crouch_recovery_remaining" in player:
		var rec := float(player.get("crouch_recovery_remaining"))
		if rec > 0.0:
			player.set("crouch_recovery_remaining", maxf(0.0, rec - delta))
	var jump_pressed := false
	if net_input != null and "jump" in net_input:
		jump_pressed = bool(net_input.get("jump"))
	else:
		jump_pressed = Input.is_action_just_pressed("jump")
	if jump_pressed:
		_clear_state(player)
		return
	if not _wants_crouch(player, net_input):
		_clear_state(player)
		return
	var config := config_from(player)
	var speed := horizontal_speed(player)
	var exit_sp := slide_exit_speed(config)
	var dash_grace := dash_slide_grace_active(player)
	player.set_meta(META_CROUCHING, true)
	if "net_crouching" in player:
		player.set("net_crouching", true)
	if is_recovering(player) and speed <= crouch_speed(config) * 1.05:
		_clear_recovery(player)
	if is_sliding(player):
		if speed <= exit_sp or not player.is_on_floor():
			_end_slide(player, config)
	elif should_enter_slide(speed, config, dash_grace):
		player.set_meta(META_SLIDING, true)
		if "net_sliding" in player:
			player.set("net_sliding", true)


static func apply_slide_physics(
	player: CharacterBody3D,
	head: Node3D,
	delta: float,
	boost: float,
	net_input: Object = null
) -> void:
	var config := config_from(player)
	var speed := horizontal_speed(player)
	var wish := SlideSurfaceScript.camera_relative_move_direction(head, net_input)
	var steer_cap := crouch_speed(config) * boost
	var vel := step_slide_velocity(
		player.velocity,
		wish,
		delta,
		steer_cap,
		slide_friction_decel(player, config, speed)
	)
	player.velocity.x = vel.x
	player.velocity.z = vel.z


static func apply_recovery_physics(player: CharacterBody3D, delta: float, boost: float) -> void:
	var config := config_from(player)
	var cap := crouch_speed(config) * boost
	var speed := horizontal_speed(player)
	if speed <= cap:
		_clear_recovery(player)
		return
	var friction := resolve_move_friction(player)
	var vel := Vector3(player.velocity.x, 0.0, player.velocity.z)
	vel = vel.move_toward(Vector3.ZERO, friction * delta)
	player.velocity.x = vel.x
	player.velocity.z = vel.z


static func apply_coast_physics(
	player: CharacterBody3D,
	head: Node3D,
	delta: float,
	boost: float,
	net_input: Object = null
) -> void:
	if is_sliding(player):
		apply_slide_physics(player, head, delta, boost, net_input)
	elif is_recovering(player):
		apply_recovery_physics(player, delta, boost)


static func _wants_crouch(player: CharacterBody3D, net_input: Object = null) -> bool:
	var held := false
	if net_input != null and "crouch" in net_input:
		held = bool(net_input.get("crouch"))
	else:
		held = Input.is_action_pressed("crouch")
	if not held:
		return false
	if not player.is_on_floor():
		return false
	if SlideSurfaceScript.should_slide(player):
		return false
	return true


static func _end_slide(player: CharacterBody3D, config: Dictionary) -> void:
	player.set_meta(META_SLIDING, false)
	if "net_sliding" in player:
		player.set("net_sliding", false)
	var recovery_sec := maxf(float(config.get("recovery_sec", DEFAULT_SLIDE_RECOVERY_SEC)), 0.0)
	if recovery_sec <= 0.0:
		return
	if "crouch_recovery_remaining" in player:
		player.set("crouch_recovery_remaining", recovery_sec)
		return
	player.set_meta(
		META_RECOVERY_UNTIL, Time.get_ticks_msec() + int(round(recovery_sec * 1000.0))
	)


static func _clear_recovery(player: CharacterBody3D) -> void:
	player.set_meta(META_RECOVERY_UNTIL, 0)
	if "crouch_recovery_remaining" in player:
		player.set("crouch_recovery_remaining", 0.0)


static func _clear_state(player: CharacterBody3D) -> void:
	player.set_meta(META_CROUCHING, false)
	player.set_meta(META_SLIDING, false)
	if "net_crouching" in player:
		player.set("net_crouching", false)
	if "net_sliding" in player:
		player.set("net_sliding", false)
	_clear_recovery(player)
