class_name SlideSurface
extends RefCounted

## Maze wall colliders tagged so players slide instead of walking. CharacterBody
## ignores PhysicsMaterial friction, so locomotion must skip ground move and use
## floating motion while the floor is a tagged wall.

const GROUP := "slide_surface"
## Cosine of ~70° from vertical. Vertical faces stay walls; tops and shoulders slide.
const FLOOR_DOT := 0.35
## Probe used when is_on_floor() is stale after rollback (apex hover).
const FLOOR_PROBE_M := 0.22
## Crest of a cylinder/sphere: normal is almost UP, so gravity has no downhill.
const PEAK_DOT := 0.98
const PEAK_SPEED := 0.35
const PEAK_NUDGE := 2.4

const PlayerCrouchScript := preload("res://scripts/characters/player_crouch.gd")
const PlayerAirControlScript := preload("res://scripts/characters/player_air_control.gd")


static func tag(body: CollisionObject3D) -> void:
	if body == null:
		return
	body.add_to_group(GROUP, true)
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	body.physics_material_override = mat


static func is_tagged(node: Object) -> bool:
	var as_node := node as Node
	return as_node != null and as_node.is_in_group(GROUP)


static func is_slide_floor(collider: Object, normal: Vector3) -> bool:
	return is_tagged(collider) and normal.dot(Vector3.UP) > FLOOR_DOT


static func is_walkable_floor(collider: Object, normal: Vector3) -> bool:
	if collider == null or is_tagged(collider):
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


static func should_slide(body: CharacterBody3D) -> bool:
	if body == null or hit_walkable_floor(body):
		return false
	for i in body.get_slide_collision_count():
		var col: KinematicCollision3D = body.get_slide_collision(i)
		if is_slide_floor(col.get_collider(), col.get_normal()):
			return true
	return false


static func prepare(body: CharacterBody3D) -> bool:
	var sliding := should_slide(body)
	if body == null:
		return sliding
	if sliding:
		body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		_nudge_off_peak(body)
	else:
		body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	return sliding


static func has_floor_below(player: CharacterBody3D) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	return player.test_move(player.global_transform, Vector3(0.0, -FLOOR_PROBE_M, 0.0))


## Re-derive motion_mode / floor_snap from the restored pose. is_on_floor() is
## leftover from the last simulated tick (and stays false in FLOATING mode).
static func sync_motion_from_pose(body: CharacterBody3D, sliding: bool = false) -> bool:
	if body == null:
		return false
	var on_floor := has_floor_below(body)
	if sliding or not on_floor:
		body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		body.floor_snap_length = 0.0
		return false
	body.motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	var stunned := false
	if body.has_method("is_stunned"):
		stunned = bool(body.call("is_stunned"))
	if not stunned and body.velocity.y <= 0.05:
		body.floor_snap_length = 0.15
	return true


static func peak_push(
	velocity: Vector3, normal: Vector3, rng: RandomNumberGenerator = null
) -> Vector3:
	if normal.dot(Vector3.UP) < PEAK_DOT:
		return velocity
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() >= PEAK_SPEED:
		return velocity
	var dir := horiz
	if dir.length_squared() < 0.0025:
		var yaw := randf() * TAU
		if rng != null:
			yaw = rng.randf() * TAU
		dir = Vector3(cos(yaw), 0.0, sin(yaw))
	else:
		dir = dir.normalized()
	return Vector3(dir.x * PEAK_NUDGE, velocity.y, dir.z * PEAK_NUDGE)


static func _nudge_off_peak(body: CharacterBody3D) -> void:
	var peak_n := Vector3.ZERO
	for i in body.get_slide_collision_count():
		var col: KinematicCollision3D = body.get_slide_collision(i)
		var n: Vector3 = col.get_normal()
		if is_slide_floor(col.get_collider(), n) and n.y >= peak_n.y:
			peak_n = n
	if peak_n == Vector3.ZERO:
		return
	body.velocity = peak_push(body.velocity, peak_n)


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
	var on_slide := prepare(player)
	var on_floor := sync_motion_from_pose(player, on_slide)
	PlayerAirControlScript.tick_air_time(player, delta, on_floor or on_slide)
	if not on_floor or on_slide:
		player.velocity.y -= gravity * delta
	var jump_pressed := false
	if net_input != null and "jump" in net_input:
		jump_pressed = bool(net_input.get("jump"))
	else:
		jump_pressed = Input.is_action_just_pressed("jump")
	if (
		jump_pressed
		and on_floor
		and not on_slide
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
	if on_slide or preserve_horizontal:
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
