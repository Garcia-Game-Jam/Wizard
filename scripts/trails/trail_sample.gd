class_name TrailSample
extends RefCounted

## Compact trail breadcrumb for host storage and RPC payloads.

const KEY_SEQ := "s"
const KEY_X := "x"
const KEY_Z := "z"
const KEY_TIME_MSEC := "t"


static func make(trail_seq: int, x: float, z: float, trail_time_msec: int) -> Dictionary:
	return {
		KEY_SEQ: trail_seq,
		KEY_X: x,
		KEY_Z: z,
		KEY_TIME_MSEC: trail_time_msec,
	}


static func seq(sample: Dictionary) -> int:
	return int(sample.get(KEY_SEQ, -1))


static func position(sample: Dictionary) -> Vector2:
	return Vector2(float(sample.get(KEY_X, 0.0)), float(sample.get(KEY_Z, 0.0)))


static func time_msec(sample: Dictionary) -> int:
	return int(sample.get(KEY_TIME_MSEC, 0))
