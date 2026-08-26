class_name AshFrostBreathFlight
extends RefCounted

## Frost breath projectile travel, growth, and hit tuning.

const MONSTER_BODY_RADIUS := 0.2
const MAX_RADIUS := MONSTER_BODY_RADIUS * 2.5 * 1.5
const GROW_SEC := 0.4
const LINGER_SEC := 0.15
const LAUNCH_OFFSET := 0.35
const LAUNCH_HEIGHT_OFFSET := 0.22
const TRAVEL_ARC_UP := 0.21
const TRAVEL_PITCH_DOWN_DEG := 10.0
const BASE_TRAVEL_RANGE := 7.0
const RANGE_MULT := 2.125
const RANGE_EXTRA_M := 2.0
const MAX_TRAVEL_RANGE := BASE_TRAVEL_RANGE * RANGE_MULT + RANGE_EXTRA_M
const LAUNCH_SPEED := 18.0
const TRAVEL_DECEL_K := 9.0
const TRAVEL_SPEED := LAUNCH_SPEED
const MAX_TRAVEL_SEC := 2.8

const KNOCKBACK_SPEED := 9.0
const KNOCKBACK_LIFT := 3.2
const SLOW_DURATION_SEC := 2.2
const SLOW_MULTIPLIER := 0.5
const HIT_DAMAGE := 0.0
const MANA_DRAIN := 40.0

const COMBO_WARD_DELAY_SEC := 0.6
const COMBO_AFTER_CLOUD_DELAY_SEC := 0.3


static func travel_speed_at_distance(
	traveled: float,
	range_m: float = MAX_TRAVEL_RANGE,
	launch_speed: float = LAUNCH_SPEED,
	decel_k: float = TRAVEL_DECEL_K
) -> float:
	## Fast launch, then a log drop vs distance so most speed is spent early.
	var span := maxf(range_m, 0.01)
	var t := clampf(traveled / span, 0.0, 1.0)
	var k := maxf(decel_k, 0.01)
	var remain := 1.0 - (log(1.0 + k * t) / log(1.0 + k))
	return maxf(launch_speed * remain, 0.0)


static func travel_step(traveled: float, delta: float) -> float:
	var left := maxf(MAX_TRAVEL_RANGE - traveled, 0.0)
	if left <= 0.0:
		return 0.0
	var speed := travel_speed_at_distance(traveled)
	if speed < 0.12:
		return 0.0
	return minf(speed * maxf(delta, 0.0), left)


static func knockback_impulse(away: Vector3) -> Vector3:
	var flat := Vector3(away.x, 0.0, away.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	return flat * KNOCKBACK_SPEED + Vector3.UP * KNOCKBACK_LIFT


static func radius_at_age(
	age: float, grow_sec: float = GROW_SEC, max_radius: float = MAX_RADIUS
) -> float:
	var t := clampf(age / maxf(grow_sec, 0.01), 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 2.0)
	return max_radius * eased


static func flat_direction(from: Vector3, toward: Vector3) -> Vector3:
	var flat := Vector3(toward.x - from.x, 0.0, toward.z - from.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


static func travel_direction(from: Vector3, toward: Vector3) -> Vector3:
	var flat := flat_direction(from, toward)
	var arced := (flat + Vector3.UP * TRAVEL_ARC_UP).normalized()
	var horiz := Vector3(arced.x, 0.0, arced.z)
	if horiz.length_squared() < 0.0001:
		horiz = flat
	else:
		horiz = horiz.normalized()
	var pitch := asin(clampf(arced.y, -1.0, 1.0)) - deg_to_rad(TRAVEL_PITCH_DOWN_DEG)
	return (horiz * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


static func launch_position(
	from: Vector3,
	toward: Vector3,
	offset: float = LAUNCH_OFFSET
) -> Vector3:
	var flat := flat_direction(from, toward)
	return from + flat * maxf(offset, 0.0) + Vector3.UP * LAUNCH_HEIGHT_OFFSET


static func total_life_sec(
	grow_sec: float = GROW_SEC, linger_sec: float = LINGER_SEC
) -> float:
	return maxf(grow_sec, 0.01) + maxf(linger_sec, 0.0)
