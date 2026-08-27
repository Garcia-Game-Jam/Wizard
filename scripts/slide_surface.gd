class_name SlideSurface
extends RefCounted

## Ground/air locomotion helpers for CharacterBody3D.
##
## Characters are ALWAYS MOTION_MODE_GROUNDED — walking, airborne, knocked back,
## stunned. MOTION_MODE_FLOATING drops the entire motion vector (vertical
## included) when a body is pressed into a wall at speed, which hung a
## fireballed wizard mid-air for 67 of 70 ticks in both Jolt and Godot Physics.
## Being airborne is expressed with floor_snap_length = 0, not a mode change.
## See tests/unit/test_wall_slide_stall.gd and AGENTS.md.

## Cosine of ~70° from vertical. Steeper faces are walls, not floors.
const FLOOR_DOT := 0.35
## Probe used when is_on_floor() is stale after rollback (apex hover).
const FLOOR_PROBE_M := 0.22

const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")
const PlayerAirControlScript := preload("res://scripts/characters/player_air_control.gd")


static func is_walkable_floor(collider: Object, normal: Vector3) -> bool:
	if collider == null:
		return false
	return normal.dot(Vector3.UP) > FLOOR_DOT


static func hit_walkable_floor(body: CharacterBody3D) -> bool:
	if body == null:
		return false
	for i in body.get_slide_collision_count():
		var col: KinematicCollision3D = body.get_slide_collision(i)
		if is_walkable_floor(col.get_collider(), col.get_normal()):
			return true
	return false


## Characters are always GROUNDED. Single place that asserts the mode.
static func prepare(body: CharacterBody3D) -> void:
	if body == null:
		return
	body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED


static func has_floor_below(player: CharacterBody3D) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	return player.test_move(player.global_transform, Vector3(0.0, -FLOOR_PROBE_M, 0.0))


## Re-derive floor snap from the restored pose and report grounded state.
## is_on_floor() is leftover from the last simulated tick, so probe instead.
## The mode is always GROUNDED; airborne is expressed as snap 0.
static func sync_motion_from_pose(body: CharacterBody3D) -> bool:
	if body == null:
		return false
	body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	if not has_floor_below(body):
		body.floor_snap_length = 0.0
		return false
	var stunned := false
	if body.has_method("is_stunned"):
		stunned = bool(body.call("is_stunned"))
	if not stunned and body.velocity.y <= 0.05:
		body.floor_snap_length = 0.15
	return true


static func apply_ground_move(
	player: CharacterBody3D,
	head: Node3D,
	gravity: float,
	delta: float,
	boost: float,
	preserve_horizontal: bool = false,
	block_crouch_slide: bool = false,
	net_input: Object = null
) -> void:
	prepare(player)
	var on_floor := sync_motion_from_pose(player)
	PlayerAirControlScript.tick_air_time(player, delta, on_floor)
	if not on_floor:
		player.velocity.y -= gravity * delta
	var jump_pressed := false
	if net_input != null and "jump" in net_input:
		jump_pressed = bool(net_input.get("jump"))
	else:
		jump_pressed = Input.is_action_just_pressed("jump")
	if (
		jump_pressed
		and on_floor
		and not PlayerCrouchScript.is_crouching(player)
	):
		player.velocity.y = PlayableCharacter.JUMP_VELOCITY
		player.floor_snap_length = 0.0
		on_floor = false
	elif on_floor and player.velocity.y <= 0.05:
		var stunned := false
		if player.has_method("is_stunned"):
			stunned = bool(player.call("is_stunned"))
		if not stunned:
			player.floor_snap_length = 0.15
	if preserve_horizontal:
		if not block_crouch_slide and PlayerCrouchScript.is_coasting(player):
			PlayerCrouchScript.apply_coast_physics(player, head, delta, boost, net_input)
		return
	if not on_floor:
		PlayerAirControlScript.apply(player, head, delta, boost, net_input)
		return
	var direction := camera_relative_move_direction(head, net_input)
	var speed := PlayerCrouchScript.ground_move_speed(player, boost)
	if direction:
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.z * speed
	else:
		var friction_step := PlayerCrouchScript.resolve_move_friction(player) * delta
		player.velocity.x = move_toward(player.velocity.x, 0.0, friction_step)
		player.velocity.z = move_toward(player.velocity.z, 0.0, friction_step)


static func camera_relative_move_direction(
	head: Node3D, net_input: Object = null
) -> Vector3:
	var input_dir := Vector2.ZERO
	if net_input != null and "movement" in net_input:
		input_dir = net_input.get("movement") as Vector2
	else:
		input_dir = Input.get_vector(
			"move_left", "move_right", "move_forward", "move_back"
		)
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var local := Vector3(input_dir.x, 0.0, input_dir.y)
	return (head.transform.basis * local).normalized()
