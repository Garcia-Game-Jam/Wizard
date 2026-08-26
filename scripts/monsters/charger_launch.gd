class_name ChargerLaunch
extends RefCounted

## Pure helpers for Charger ram speed and knockup launch vectors.

const CHARGE_SPEED_MULT := 2.3
const PATROL_SPEED_MULT := 0.8
const DEFAULT_KNOCKUP_CELLS := 6
const DEFAULT_CELL_SIZE_M := 3.0
const DEFAULT_WALL_HEIGHT_M := 3.0
const DEFAULT_OVER_WALL_M := 3.5
const YAW_SPREAD_RAD := 0.32
const SPEED_JITTER := 0.12


static func plunge_pitch_rad(plunge_deg: float) -> float:
	## 360° = looking ahead. 330° = 30° down. Snout-down is negative X pitch.
	return deg_to_rad(plunge_deg - 360.0)


static func toss_pitch_rad(toss_deg: float) -> float:
	## Positive X pitch lifts the snout (gore / throw).
	return deg_to_rad(toss_deg)


static func charge_speed(
	sprint_speed: float, mult: float = CHARGE_SPEED_MULT
) -> float:
	return maxf(0.0, sprint_speed) * maxf(mult, 0.0)


static func patrol_speed(walk_speed: float) -> float:
	return maxf(0.0, walk_speed) * PATROL_SPEED_MULT


static func gravity_of(node: Object, fallback: float) -> float:
	if node == null:
		return fallback
	var raw: Variant = node.get("gravity")
	if raw is float:
		return raw
	if raw is int:
		return float(raw)
	return fallback


static func horiz_speed(cells: int, cell_size: float = DEFAULT_CELL_SIZE_M) -> float:
	## Steeper arc: hang time is long, so horizontal speed stays modest.
	return maxf(cell_size, 0.1) * float(maxi(cells, 1)) / 3.5


static func knockup_velocity(
	away_dir: Vector3,
	gravity: float,
	wall_height: float,
	over_wall_m: float,
	horiz_mps: float,
	rng: RandomNumberGenerator = null
) -> Vector3:
	var flat := Vector3(away_dir.x, 0.0, away_dir.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var yaw := 0.0
	var speed := maxf(horiz_mps, 1.0)
	if rng != null:
		yaw = rng.randf_range(-YAW_SPREAD_RAD, YAW_SPREAD_RAD)
		speed *= 1.0 + rng.randf_range(-SPEED_JITTER, SPEED_JITTER)
	if absf(yaw) > 0.0001:
		flat = flat.rotated(Vector3.UP, yaw)
	var g := maxf(gravity, 0.05)
	var peak := maxf(wall_height + maxf(over_wall_m, 0.2), 1.2)
	var vy := sqrt(2.0 * g * peak)
	return Vector3(flat.x * speed, vy, flat.z * speed)


static func apex_height(from_pos: Vector3, velocity: Vector3, gravity: float) -> float:
	var g := maxf(gravity, 0.05)
	if velocity.y <= 0.0:
		return from_pos.y
	return from_pos.y + (velocity.y * velocity.y) / (2.0 * g)


static func integrate_launch(
	from_pos: Vector3, velocity: Vector3, gravity: float, flight_sec: float
) -> Vector3:
	var t := maxf(flight_sec, 0.0)
	return Vector3(
		from_pos.x + velocity.x * t,
		from_pos.y + velocity.y * t - 0.5 * gravity * t * t,
		from_pos.z + velocity.z * t
	)


static func arc_points(
	from_pos: Vector3, velocity: Vector3, gravity: float, count: int = 12
) -> PackedVector3Array:
	var g := maxf(gravity, 0.05)
	var flight := 0.8
	if velocity.y > 0.0:
		flight = 2.0 * velocity.y / g
	var n := maxi(count, 2)
	var pts := PackedVector3Array()
	for i in n:
		var t := flight * float(i) / float(n - 1)
		pts.append(integrate_launch(from_pos, velocity, g, t))
	return pts


static func wall_height_from_node(_node: Node, fallback: float = DEFAULT_WALL_HEIGHT_M) -> float:
	return fallback


static func cell_size_from_node(_node: Node, fallback: float = DEFAULT_CELL_SIZE_M) -> float:
	return fallback

