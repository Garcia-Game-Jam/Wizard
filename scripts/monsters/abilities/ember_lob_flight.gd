class_name EmberLobFlight
extends RefCounted

## Pure lob → apex → dive rules for Ember Lob projectiles.

const LOB_SPEED := 9.5
const LOB_UP_BIAS := 0.72
const GRAVITY := 14.0
const DIVE_SPEED := 28.0
const APEX_EPS := 0.02


static func initial_lob_velocity(from: Vector3, toward: Vector3) -> Vector3:
	var flat := Vector3(toward.x - from.x, 0.0, toward.z - from.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var dir := (flat + Vector3.UP * LOB_UP_BIAS).normalized()
	return dir * LOB_SPEED


static func step_lob_velocity(velocity: Vector3, delta: float, gravity: float = GRAVITY) -> Vector3:
	var next := velocity
	next.y -= maxf(gravity, 0.0) * maxf(delta, 0.0)
	return next


## True when vertical velocity crosses from rising to falling.
static func crossed_apex(prev_vy: float, next_vy: float) -> bool:
	return prev_vy > APEX_EPS and next_vy <= APEX_EPS


static func dive_velocity(
	from: Vector3,
	dive_target: Vector3,
	dive_speed: float = DIVE_SPEED
) -> Vector3:
	var delta := dive_target - from
	if delta.length_squared() < 0.0001:
		return Vector3.DOWN * dive_speed
	return delta.normalized() * maxf(dive_speed, 0.0)
