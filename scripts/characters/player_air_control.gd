class_name PlayerAirControl
extends RefCounted

## Air strafing for PlayableCharacter. WASD steers horizontal velocity while
## airborne (previously: zero air control — velocity.x/z were frozen once you
## left the floor). Steering strength starts at a percentage of normal
## move_speed the instant you leave the ground and decays the longer you stay
## airborne, floored at a minimum percentage — so jump-puzzle platforming
## still rewards a good takeoff over endlessly correcting mid-air.
## Tunables live on PlayableCharacter; defaults below are fallbacks for tests.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")

const DEFAULT_START_PCT := 90.0
const DEFAULT_MIN_PCT := 65.0
const DEFAULT_DECAY_PCT_PER_SEC := 7.5
## Reference: 3x steer_cap accel factor lives in PlayerCrouch.step_slide_velocity.
const META_AIR_TIME := "_player_air_time_sec"


static func config_from(player: CharacterBody3D) -> Dictionary:
	return {
		"start_pct": _export_float(player, "air_control_start_pct", DEFAULT_START_PCT),
		"min_pct": _export_float(player, "air_control_min_pct", DEFAULT_MIN_PCT),
		"decay_pct_per_sec": _export_float(
			player, "air_control_decay_pct_per_sec", DEFAULT_DECAY_PCT_PER_SEC
		),
	}


static func _export_float(player: Object, property: StringName, default: float) -> float:
	if player is PlayableCharacter:
		return float(player.get(property))
	var value: Variant = player.get(property)
	if value == null:
		return default
	return float(value)


static func air_time(player: CharacterBody3D) -> float:
	return float(player.get_meta(META_AIR_TIME, 0.0))


## `grounded` covers both is_on_floor() and standing on a SlideSurface — both
## reset the clock; only genuine freefall (jump, fall, launch) should count.
static func tick_air_time(player: CharacterBody3D, delta: float, grounded: bool) -> void:
	if grounded:
		player.set_meta(META_AIR_TIME, 0.0)
	else:
		player.set_meta(META_AIR_TIME, air_time(player) + delta)


## Fraction (0–1) of move_speed the player can currently steer with in the air.
static func control_scale(player: CharacterBody3D, config: Dictionary = {}) -> float:
	if config.is_empty():
		config = config_from(player)
	var start_pct: float = config.get("start_pct", DEFAULT_START_PCT)
	var min_pct: float = config.get("min_pct", DEFAULT_MIN_PCT)
	var decay: float = config.get("decay_pct_per_sec", DEFAULT_DECAY_PCT_PER_SEC)
	var pct := start_pct - decay * air_time(player)
	return clampf(pct, minf(min_pct, start_pct), maxf(min_pct, start_pct)) / 100.0


## Steers (not overrides) horizontal velocity toward the camera-relative wish
## direction, capped at move_speed * boost * control_scale. Zero friction —
## momentum from a jump, dash, or knockback carries over; only the component
## along the wish direction gets pulled up toward the air-speed cap.
static func apply(
	player: CharacterBody3D,
	head: Node3D,
	delta: float,
	boost: float,
	net_input: Object = null
) -> void:
	var wish := SlideSurfaceScript.camera_relative_move_direction(head, net_input)
	if wish == Vector3.ZERO:
		return
	var speed := PlayerCrouchScript.resolve_move_speed(player) * boost * control_scale(player)
	var vel: Vector3 = PlayerCrouchScript.step_slide_velocity(player.velocity, wish, delta, speed, 0.0)
	player.velocity.x = vel.x
	player.velocity.z = vel.z
