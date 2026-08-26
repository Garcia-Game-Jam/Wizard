class_name AshIceFlight
extends RefCounted

## Pure curved ice bolt path: quadratic Bezier with up + lateral control point.

const FLIGHT_SPEED := 11.9
const SIDE_OFFSET := 2.4
const UP_OFFSET := 1.9
const SAMPLE_COUNT := 20


static func make_control(from: Vector3, to: Vector3, side_sign: float) -> Vector3:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var flat_len := flat.length()
	if flat_len < 0.0001:
		flat = Vector3.FORWARD
	else:
		flat = flat.normalized()
	var lateral := Vector3(-flat.z, 0.0, flat.x) * side_sign
	var mid := from.lerp(to, 0.42)
	var arc_scale := clampf(flat_len / 8.0, 0.35, 1.0)
	return mid + lateral * SIDE_OFFSET * arc_scale + Vector3.UP * UP_OFFSET * arc_scale


static func point_on_curve(from: Vector3, control: Vector3, to: Vector3, t: float) -> Vector3:
	var clamped := clampf(t, 0.0, 1.0)
	var u := 1.0 - clamped
	return (u * u * from) + (2.0 * u * clamped * control) + (clamped * clamped * to)


static func approximate_length(from: Vector3, control: Vector3, to: Vector3) -> float:
	var length := 0.0
	var prev := from
	for i in range(1, SAMPLE_COUNT + 1):
		var t := float(i) / float(SAMPLE_COUNT)
		var p := point_on_curve(from, control, to, t)
		length += prev.distance_to(p)
		prev = p
	return maxf(length, 0.01)


static func t_at_arc_length(
	from: Vector3, control: Vector3, to: Vector3, target_length: float
) -> float:
	var total := approximate_length(from, control, to)
	if target_length <= 0.0:
		return 0.0
	if target_length >= total:
		return 1.0
	var accum := 0.0
	var prev := from
	var prev_t := 0.0
	for i in range(1, SAMPLE_COUNT + 1):
		var t := float(i) / float(SAMPLE_COUNT)
		var p := point_on_curve(from, control, to, t)
		var seg := prev.distance_to(p)
		if accum + seg >= target_length:
			var frac := (target_length - accum) / maxf(seg, 0.0001)
			return lerpf(prev_t, t, frac)
		accum += seg
		prev = p
		prev_t = t
	return 1.0


static func advance_arc_distance(
	from: Vector3,
	control: Vector3,
	to: Vector3,
	distance: float,
	delta: float,
	speed: float = FLIGHT_SPEED
) -> Dictionary:
	var total := approximate_length(from, control, to)
	var next_dist := minf(
		distance + maxf(speed, 0.0) * maxf(delta, 0.0),
		total
	)
	var t := t_at_arc_length(from, control, to, next_dist)
	return {
		"distance": next_dist,
		"t": t,
		"position": point_on_curve(from, control, to, t),
		"total_length": total,
	}


static func advance_t(
	from: Vector3,
	control: Vector3,
	to: Vector3,
	t: float,
	delta: float,
	speed: float = FLIGHT_SPEED
) -> float:
	var duration := approximate_length(from, control, to) / maxf(speed, 0.1)
	return clampf(t + maxf(delta, 0.0) / maxf(duration, 0.05), 0.0, 1.0)


static func tangent(from: Vector3, control: Vector3, to: Vector3, t: float) -> Vector3:
	## Derivative of quadratic Bezier: 2(1-t)(C-A) + 2t(B-C).
	var clamped := clampf(t, 0.0, 1.0)
	var d := 2.0 * (1.0 - clamped) * (control - from) + 2.0 * clamped * (to - control)
	if d.length_squared() < 0.0001:
		var fallback := to - from
		if fallback.length_squared() < 0.0001:
			return Vector3.FORWARD
		return fallback.normalized()
	return d.normalized()
