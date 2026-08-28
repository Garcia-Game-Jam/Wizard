class_name PlayerCombatReactions
extends RefCounted

## Player-only hit reactions that are not the shared Character knock status.

const EmberHaloFlightScript := preload("res://scripts/monsters/abilities/ember_halo_flight.gd")


static func apply_ember_halo_jump_pad(
	player: Player,
	strength_mult: float = 1.0
) -> void:
	if not player.is_multiplayer_authority() and GameState.is_multiplayer:
		return
	player.velocity.y = EmberHaloFlightScript.jump_pad_velocity(player.gravity, strength_mult)


static func apply_ember_halo_hit(player: Player, _hit_dir: Vector3) -> void:
	if not player.is_multiplayer_authority() and GameState.is_multiplayer:
		return
	player.apply_speed_boost(
		EmberHaloFlightScript.SLOW_DURATION_SEC,
		EmberHaloFlightScript.SLOW_MULTIPLIER
	)


static func tick_knockback_bleed(player: Player, delta: float) -> void:
	if player._knockback_timer <= 0.0:
		return
	player._knockback_timer -= delta
	var bleed := Character.KNOCKBACK_BLEED_PER_SEC * delta
	player.velocity.x += player._knockback_vel.x * bleed
	player.velocity.z += player._knockback_vel.z * bleed
	player._knockback_vel = player._knockback_vel.move_toward(
		Vector3.ZERO, Character.KNOCKBACK_DECAY * delta
	)
