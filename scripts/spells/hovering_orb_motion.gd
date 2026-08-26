class_name HoveringOrbMotion
extends RefCounted

## Shared ground-height + bob + smooth XZ cruise for light balls and relics.

const WorldGroundScript := preload("res://scripts/world_ground.gd")

const HEIGHT_LIGHT_BALL := 1.15
const HEIGHT_RELIC := 1.1
const BOB_SPEED := 1.9
const BOB_AMPLITUDE := 0.08
## Soft cruise: exponential blend toward the route point, capped by max speed.
const CRUISE_SMOOTH := 7.5
const CRUISE_MAX_SPEED := 4.5
const GOAL_SMOOTH := 4.0


static func snap_base(
	world_3d: World3D,
	pos: Vector3,
	height_above_ground: float
) -> Vector3:
	return WorldGroundScript.with_height_above_ground(
		world_3d, pos, height_above_ground, pos.y - height_above_ground
	)


static func bob_offset(phase: float, amplitude: float = BOB_AMPLITUDE) -> Vector3:
	return Vector3(0.0, sin(phase) * amplitude, 0.0)


static func advance_bob_phase(
	phase: float,
	delta: float,
	speed: float = BOB_SPEED
) -> float:
	return phase + delta * speed


static func visual_from_base(
	base: Vector3,
	phase: float,
	amplitude: float = BOB_AMPLITUDE
) -> Vector3:
	return base + bob_offset(phase, amplitude)


static func cruise_base_toward(
	from_base: Vector3,
	waypoint: Vector3,
	delta: float,
	world_3d: World3D,
	height_above_ground: float,
	max_speed: float = CRUISE_MAX_SPEED,
	smooth_rate: float = CRUISE_SMOOTH
) -> Vector3:
	## Smooth horizontal step; Y is always ground + height (bob applied by caller).
	var flat_from := Vector3(from_base.x, 0.0, from_base.z)
	var flat_to := Vector3(waypoint.x, 0.0, waypoint.z)
	var t := 1.0 - exp(-smooth_rate * delta)
	var blended := flat_from.lerp(flat_to, t)
	var max_step := max_speed * delta
	if flat_from.distance_to(blended) > max_step:
		blended = flat_from.move_toward(blended, max_step)
	var next := Vector3(blended.x, from_base.y, blended.z)
	return snap_base(world_3d, next, height_above_ground)


static func cruise_pull_toward(
	from_base: Vector3,
	dest: Vector3,
	delta: float,
	world_3d: World3D,
	height_above_ground: float,
	speed: float
) -> Vector3:
	## Ground-plane pull step at a caller-chosen speed (fast far / slow near).
	var flat_from := Vector3(from_base.x, 0.0, from_base.z)
	var flat_to := Vector3(dest.x, 0.0, dest.z)
	var dist := flat_from.distance_to(flat_to)
	if dist <= 0.0001:
		return snap_base(world_3d, from_base, height_above_ground)
	var step := minf(maxf(speed, 0.0) * delta, dist)
	var next := flat_from.move_toward(flat_to, step)
	return snap_base(world_3d, Vector3(next.x, from_base.y, next.z), height_above_ground)


static func smooth_goal(
	current_goal: Vector3,
	ideal_goal: Vector3,
	delta: float,
	smooth_rate: float = GOAL_SMOOTH
) -> Vector3:
	## Soften the follow chase point on XZ; keep ideal height for path queries.
	var flat_current := Vector3(current_goal.x, 0.0, current_goal.z)
	var flat_ideal := Vector3(ideal_goal.x, 0.0, ideal_goal.z)
	var t := 1.0 - exp(-smooth_rate * delta)
	var flat := flat_current.lerp(flat_ideal, t)
	return Vector3(flat.x, ideal_goal.y, flat.z)
