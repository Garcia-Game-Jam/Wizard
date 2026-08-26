class_name EmberHaloFlight
extends RefCounted

## Expanding ring radius vs distance traveled.

const TRAVEL_SPEED := 14.0
const START_RADIUS := 0.35
const MAX_RADIUS := 2.4
## Radius gain per meter traveled.
const EXPAND_PER_METER := 0.55
## Torus hole vs outer rim — matches EmberHaloProjectile visual inner_radius mult.
const INNER_RADIUS_MULT := 0.85
## Center jump pad apex height (meters).
const JUMP_PAD_HEIGHT_M := 2.0
## Player hit: 60% move speed for 0.5s (via apply_speed_boost).
const SLOW_DURATION_SEC := 0.5
const SLOW_MULTIPLIER := 0.6
const HIT_KNOCKBACK_SPEED := 3.8


static func radius_at_distance(
	distance_traveled: float,
	start_radius: float = START_RADIUS,
	max_radius: float = MAX_RADIUS,
	expand_per_meter: float = EXPAND_PER_METER
) -> float:
	var grown := start_radius + maxf(distance_traveled, 0.0) * maxf(expand_per_meter, 0.0)
	return minf(grown, maxf(max_radius, start_radius))


static func flat_direction(from: Vector3, toward: Vector3) -> Vector3:
	var flat := Vector3(toward.x - from.x, 0.0, toward.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


static func inner_radius(outer_radius: float) -> float:
	return maxf(0.05, outer_radius * INNER_RADIUS_MULT)


static func flat_distance(ring_center: Vector3, body_pos: Vector3) -> float:
	var flat := Vector2(body_pos.x - ring_center.x, body_pos.z - ring_center.z)
	return flat.length()


static func is_in_center(flat_dist: float, outer_radius: float) -> bool:
	return flat_dist <= inner_radius(outer_radius)


static func is_in_ring(flat_dist: float, outer_radius: float) -> bool:
	var inner := inner_radius(outer_radius)
	return flat_dist > inner and flat_dist <= outer_radius


## strength_mult scales the apex height (1.0 = the normal JUMP_PAD_HEIGHT_M
## pop; 2.0 = double the apex height, etc.) — velocity scales with its
## square root, not linearly, since it's derived from v = sqrt(2 * g * h).
static func jump_pad_velocity(
	gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity"),
	strength_mult: float = 1.0
) -> float:
	var height := JUMP_PAD_HEIGHT_M * maxf(strength_mult, 0.0)
	return sqrt(2.0 * maxf(gravity, 0.01) * height)
