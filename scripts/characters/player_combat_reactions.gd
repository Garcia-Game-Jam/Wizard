class_name PlayerCombatReactions
extends RefCounted

## Spell and monster hit reactions shared by PlayableCharacter.

const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")
const FIREBALL_KNOCKBACK_HORIZONTAL := 9.0
const FIREBALL_KNOCKBACK_UP := 3.5


static func apply_fireball_knockback(player: PlayableCharacter, fireball_dir: Vector3) -> void:
	if not player.is_multiplayer_authority() and GameState.is_multiplayer:
		return
	var impulse := _fireball_knockback_impulse(fireball_dir)
	_set_knockback(player, impulse, 0.35)
	player.velocity += impulse


static func apply_ember_halo_jump_pad(
	player: PlayableCharacter,
	strength_mult: float = 1.0
) -> void:
	if not player.is_multiplayer_authority() and GameState.is_multiplayer:
		return
	player.velocity.y = EmberHaloFlightScript.jump_pad_velocity(player.gravity, strength_mult)


static func apply_ember_halo_hit(player: PlayableCharacter, hit_dir: Vector3) -> void:
	if not player.is_multiplayer_authority() and GameState.is_multiplayer:
		return
	player.velocity.y = maxf(player.velocity.y, PlayableCharacter.JUMP_VELOCITY)
	var flat := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		var impulse := flat * EmberHaloFlightScript.HIT_KNOCKBACK_SPEED
		_set_knockback(player, impulse, 0.25)
		player.velocity.x += impulse.x
		player.velocity.z += impulse.z
	player.apply_speed_boost(
		EmberHaloFlightScript.SLOW_DURATION_SEC,
		EmberHaloFlightScript.SLOW_MULTIPLIER
	)


static func apply_wretch_command_hit(player: PlayableCharacter, hit_dir: Vector3) -> void:
	_apply_flat_knockback_hit(player, hit_dir, 6.0, 1.5, 0.28, 2.0, 0.1)


static func apply_rat_explode_hit(player: PlayableCharacter, hit_dir: Vector3) -> void:
	_apply_flat_knockback_hit(player, hit_dir, 14.0, 4.0, 0.5, 0.75, 0.25)


static func tick_knockback_bleed(player: PlayableCharacter, delta: float) -> void:
	if player._knockback_timer <= 0.0:
		return
	player._knockback_timer -= delta
	player.velocity.x += player._knockback_vel.x * 0.35
	player.velocity.z += player._knockback_vel.z * 0.35
	player._knockback_vel = player._knockback_vel.move_toward(Vector3.ZERO, 28.0 * delta)


static func _apply_flat_knockback_hit(
	player: PlayableCharacter,
	hit_dir: Vector3,
	flat_speed: float,
	up_speed: float,
	timer: float,
	slow_duration: float,
	slow_multiplier: float
) -> void:
	if not player.is_multiplayer_authority() and GameState.is_multiplayer:
		return
	var flat := _flat_hit_direction(player, hit_dir)
	var impulse := flat * flat_speed + Vector3.UP * up_speed
	_set_knockback(player, impulse, timer)
	player.velocity += impulse
	if slow_duration > 0.0:
		player.apply_speed_boost(slow_duration, slow_multiplier)


static func _fireball_knockback_impulse(fireball_dir: Vector3) -> Vector3:
	var dir := fireball_dir
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	return flat * FIREBALL_KNOCKBACK_HORIZONTAL + Vector3.UP * FIREBALL_KNOCKBACK_UP


static func _flat_hit_direction(player: PlayableCharacter, hit_dir: Vector3) -> Vector3:
	var dir := hit_dir
	if dir.length_squared() < 0.0001:
		dir = -player.global_transform.basis.z
	else:
		dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


static func _set_knockback(player: PlayableCharacter, impulse: Vector3, timer: float) -> void:
	player._knockback_vel = impulse
	player._knockback_timer = timer
