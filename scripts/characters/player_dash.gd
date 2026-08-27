class_name PlayerDash
extends RefCounted

## Foot dash for PlayableCharacter (Headmaster + Apprentice).
## Tunables live on PlayableCharacter; defaults below are fallbacks for tests.

const SlideSurfaceScript := preload("res://scripts/slide_surface.gd")
const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")

const DEFAULT_DISTANCE := 3.0
const DEFAULT_DURATION := 0.15
const DEFAULT_COOLDOWN_SEC := 3.0
const DEFAULT_SPEED := 20.0
## Where leftover dash speed quickly settles once the dash lock ends, as a
## % of move_speed. 100% = your normal run speed.
const DEFAULT_POST_SPEED_PCT := 100.0
const POST_SPEED_PCT_MIN := 25.0
const POST_SPEED_PCT_MAX := 200.0
## How fast leftover speed bleeds off toward that target (m/s²). Flat and
## fast by design — this is a quick settle, not a gentle glide.
const POST_DASH_DECAY_RATE := 45.0
const META_ACTIVE_UNTIL := "_dash_active_until_msec"
const META_COOLDOWN := "_dash_cooldown_sec"
const META_POST_DECAY_PENDING := "_dash_post_decay_pending"


static func dash_speed(config: Dictionary = {}) -> float:
	return maxf(float(config.get("speed", DEFAULT_SPEED)), 0.0)


static func dash_duration(config: Dictionary = {}) -> float:
	return maxf(float(config.get("duration", DEFAULT_DURATION)), 0.05)


static func dash_cooldown(config: Dictionary = {}) -> float:
	return maxf(float(config.get("cooldown_sec", DEFAULT_COOLDOWN_SEC)), 0.0)


static func post_speed_pct(config: Dictionary = {}) -> float:
	return clampf(
		float(config.get("post_speed_pct", DEFAULT_POST_SPEED_PCT)),
		POST_SPEED_PCT_MIN,
		POST_SPEED_PCT_MAX
	)


static func config_from(player: CharacterBody3D) -> Dictionary:
	return {
		"distance": _export_float(player, "dash_distance", DEFAULT_DISTANCE),
		"duration": _export_float(player, "dash_duration", DEFAULT_DURATION),
		"cooldown_sec": _export_float(player, "dash_cooldown_sec", DEFAULT_COOLDOWN_SEC),
		"speed": _export_float(player, "dash_speed", DEFAULT_SPEED),
		"post_speed_pct": _export_float(player, "dash_post_speed_pct", DEFAULT_POST_SPEED_PCT),
	}


static func _export_float(player: Object, property: StringName, default: float) -> float:
	if player is PlayableCharacter:
		return float(player.get(property))
	var value: Variant = player.get(property)
	if value == null:
		return default
	return float(value)


static func is_active(player: CharacterBody3D) -> bool:
	if "dash_lock_remaining" in player:
		return float(player.get("dash_lock_remaining")) > 0.0
	return Time.get_ticks_msec() < int(player.get_meta(META_ACTIVE_UNTIL, 0))


static func tick_and_try(
	player: CharacterBody3D,
	head: Node3D,
	delta: float,
	config: Dictionary = {},
	net_input: Object = null
) -> void:
	if config.is_empty():
		config = config_from(player)
	_tick_cooldown(player, delta)
	_tick_lock(player, delta)
	if is_active(player):
		return
	_try_dash(player, head, config, net_input)


static func _tick_lock(player: CharacterBody3D, delta: float) -> void:
	if "dash_lock_remaining" in player:
		var left := float(player.get("dash_lock_remaining"))
		if left > 0.0:
			player.set("dash_lock_remaining", maxf(0.0, left - delta))


static func _tick_cooldown(player: CharacterBody3D, delta: float) -> void:
	if "dash_cooldown_remaining" in player:
		var left := float(player.get("dash_cooldown_remaining"))
		if left > 0.0:
			player.set("dash_cooldown_remaining", maxf(0.0, left - delta))
		return
	var cooldown := float(player.get_meta(META_COOLDOWN, 0.0))
	if cooldown <= 0.0:
		return
	player.set_meta(META_COOLDOWN, maxf(0.0, cooldown - delta))


static func _try_dash(
	player: CharacterBody3D, head: Node3D, config: Dictionary, net_input: Object = null
) -> void:
	if "dash_cooldown_remaining" in player:
		if float(player.get("dash_cooldown_remaining")) > 0.0:
			return
	elif float(player.get_meta(META_COOLDOWN, 0.0)) > 0.0:
		return
	var wants_dash := false
	if net_input != null and "dash" in net_input:
		wants_dash = bool(net_input.get("dash"))
	else:
		wants_dash = Input.is_action_just_pressed("dash")
	if not wants_dash:
		return
	var direction := SlideSurfaceScript.camera_relative_move_direction(head, net_input)
	if direction == Vector3.ZERO:
		return
	var speed := dash_speed(config)
	var duration := dash_duration(config)
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	if "dash_lock_remaining" in player:
		player.set("dash_lock_remaining", duration)
		player.set("dash_cooldown_remaining", dash_cooldown(config))
		player.set("dash_post_decay_pending", true)
	else:
		player.set_meta(
			META_ACTIVE_UNTIL, Time.get_ticks_msec() + int(round(duration * 1000.0))
		)
		player.set_meta(META_COOLDOWN, dash_cooldown(config))
		player.set_meta(META_POST_DECAY_PENDING, true)
	var grace := _export_float(player, "crouch_slide_dash_grace_sec", 0.6)
	PlayerCrouchScript.mark_dash_slide_grace(player, duration, grace)


## Once the dash lock (is_active) ends, whatever horizontal speed is left
## over quickly bleeds down to post_speed_pct of move_speed — otherwise a
## dash off a ledge with no further input would carry dash_speed forever,
## since ground move only overrides speed when it has WASD input to snap to,
## and air control only pulls speed UP toward its (lower) cap, never down.
## No-op once dash_speed is at/below the target, or while a fresh dash is
## still locking velocity.
static func tick_post_decay(
	player: CharacterBody3D, delta: float, config: Dictionary = {}
) -> void:
	if is_active(player):
		return
	if "dash_post_decay_pending" in player:
		if not bool(player.get("dash_post_decay_pending")):
			return
	elif not bool(player.get_meta(META_POST_DECAY_PENDING, false)):
		return
	if config.is_empty():
		config = config_from(player)
	var target := PlayerCrouchScript.resolve_move_speed(player) * (post_speed_pct(config) / 100.0)
	var horiz := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var speed := horiz.length()
	if speed <= target + 0.01:
		if "dash_post_decay_pending" in player:
			player.set("dash_post_decay_pending", false)
		else:
			player.set_meta(META_POST_DECAY_PENDING, false)
		return
	var dir := horiz / speed
	var new_speed := move_toward(speed, target, POST_DASH_DECAY_RATE * delta)
	player.velocity.x = dir.x * new_speed
	player.velocity.z = dir.z * new_speed
