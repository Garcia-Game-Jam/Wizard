class_name FlareFlight
extends RefCounted

## Pure flare rocket physics — unit-testable without a scene tree.
## Gameplay tuning lives on FlareEffect (launch_speed, drag, horizontal_drag, flight_gravity).

## Default muzzle speed when a scene does not override launch_speed.
const LAUNCH_SPEED := 38.0
## Light drag on vertical velocity (upward coast bleeds slowly).
const DRAG := 0.12
## Strong horizontal drag — limits sideways travel while low gravity keeps hang time.
const HORIZONTAL_DRAG := 1.55
## Downward pull (m/s²). Lower values keep the rocket in the sky longer.
const GRAVITY := 0.18
## Extra added to `drag` while sliding on any contact (walls, floor, players, monsters).
const CONTACT_DRAG := 1.6
## Default collision sphere for player / world hits.
const HIT_RADIUS := 0.22


static func launch_direction(aim: Vector3) -> Vector3:
	## Follow the crosshair / cast aim exactly — no forced skyward bias.
	if aim.length_squared() < 0.0001:
		return Vector3.FORWARD
	return aim.normalized()


static func initial_velocity(aim: Vector3, launch_speed: float = LAUNCH_SPEED) -> Vector3:
	return launch_direction(aim) * maxf(launch_speed, 0.0)


static func step_velocity(
	velocity: Vector3,
	delta: float,
	drag: float = DRAG,
	gravity: float = GRAVITY,
	horizontal_drag: float = HORIZONTAL_DRAG
) -> Vector3:
	var dt := maxf(delta, 0.0)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var vertical_y := velocity.y
	horizontal *= exp(-maxf(horizontal_drag, 0.0) * dt)
	vertical_y *= exp(-maxf(drag, 0.0) * dt)
	vertical_y -= maxf(gravity, 0.0) * dt
	return Vector3(horizontal.x, vertical_y, horizontal.z)


static func slide_on_contact(velocity: Vector3, normal: Vector3) -> Vector3:
	if normal.length_squared() < 0.0001:
		return velocity
	return velocity.slide(normal.normalized())


static func simulate_altitude(
	origin_y: float,
	aim: Vector3,
	elapsed_sec: float,
	step_sec: float = 1.0 / 60.0,
	launch_speed: float = LAUNCH_SPEED,
	drag: float = DRAG,
	gravity: float = GRAVITY,
	horizontal_drag: float = HORIZONTAL_DRAG
) -> float:
	var y := origin_y
	var velocity := initial_velocity(aim, launch_speed)
	var t := 0.0
	var life := maxf(elapsed_sec, 0.0)
	var dt_step := maxf(step_sec, 0.0001)
	while t < life:
		var dt := minf(dt_step, life - t)
		velocity = step_velocity(velocity, dt, drag, gravity, horizontal_drag)
		y += velocity.y * dt
		t += dt
	return y


static func simulate_horizontal_distance(
	origin: Vector3,
	aim: Vector3,
	elapsed_sec: float,
	step_sec: float = 1.0 / 60.0,
	launch_speed: float = LAUNCH_SPEED,
	drag: float = DRAG,
	gravity: float = GRAVITY,
	horizontal_drag: float = HORIZONTAL_DRAG
) -> float:
	var pos := origin
	var velocity := initial_velocity(aim, launch_speed)
	var t := 0.0
	var life := maxf(elapsed_sec, 0.0)
	var dt_step := maxf(step_sec, 0.0001)
	while t < life:
		var dt := minf(dt_step, life - t)
		velocity = step_velocity(velocity, dt, drag, gravity, horizontal_drag)
		pos += velocity * dt
		t += dt
	var flat := Vector3(pos.x - origin.x, 0.0, pos.z - origin.z)
	return flat.length()
